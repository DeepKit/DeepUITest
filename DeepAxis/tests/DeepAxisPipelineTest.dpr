program DeepAxisPipelineTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils, System.Math,
  System.Generics.Collections, System.Hash,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Phys.SQLite,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.WeChat.Adapter, DeepAxis.WeChat.Adapter411053,
  DeepAxis.WeChat.Reader,
  DeepAxis.Pipeline.Metrics, DeepAxis.Pipeline.Radar, DeepAxis.Pipeline.Evidence,
  DeepAxis.Pipeline.TagEngine, DeepAxis.Pipeline.IdleFunnel,
  DeepAxis.Pipeline.Privacy, DeepAxis.Pipeline.BodyZero;

var
  LAdapter: ISchemaAdapter;
  LReader: IWxReader;
  LMetricCalc: IMetricCalculator;
  LRadarEngine: IRadarEngine;
  LEvidenceBuilder: IEvidenceBuilder;
  LTagEngine: ITagEngine;
  LIdleFunnel: IIdleFunnel;
  LPrivacy: TPrivacyClassifier;
  LBodyZero: TBodyZeroAuditor;
  LContacts, LTagged: TArray<TContact>;
  LAllMessages: TArray<TMessageMeta>;
  LMetrics: TArray<TInteractionMetric>;
  LHints: TArray<TRadarHint>;
  LEvidence: TArray<TEvidenceRecord>;
  LContact: TContact;
  LMsg: TMessageMeta;
  LHint: TRadarHint;
  LEv: TEvidenceRecord;
  I, J: Integer;
  LDataPath, LContactPath, LMsg0Path, LSessionPath: string;
  LCursor: TScanCursor;
  LContactMsgs: TArray<TMessageMeta>;
  LCooling, LLongSilence, LReactivated, LOutboundHeavy, LDataInsuff: Integer;
  LReport: TBodyZeroReport;
  LMsgByContact: TDictionary<string, TList<TMessageMeta>>;
  LMsgList: TList<TMessageMeta>;
  LContactMsgArr: TArray<TMessageMeta>;
  LTotalMsgs: Integer;
begin
  WriteLn('DeepAxis 管道端到端测试');
  WriteLn('========================');
  WriteLn('');

  LDataPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\dbs');
  if ParamCount > 0 then LDataPath := ParamStr(1);

  LContactPath := TPath.Combine(LDataPath, 'contact\contact.db');
  LMsg0Path := TPath.Combine(LDataPath, 'message\message_0.db');
  LSessionPath := TPath.Combine(LDataPath, 'session\session.db');

  // 初始化
  LAdapter := TWeChat411053Adapter.Create;
  LReader := TWeChatReader.Create(LAdapter);
  LMetricCalc := TMetricCalculator.Create;
  LRadarEngine := TRadarEngine.Create;
  LEvidenceBuilder := TEvidenceBuilder.Create;
  LTagEngine := TTagEngine.Create;
  LIdleFunnel := TIdleFunnel.Create;
  LPrivacy := TPrivacyClassifier.Create;
  LBodyZero := TBodyZeroAuditor.Create;

  WriteLn('[1] 打开数据库...');
  if not LReader.OpenPaths(LContactPath, LMsg0Path, LSessionPath) then
  begin
    WriteLn('  失败');
    Halt(1);
  end;
  WriteLn('  成功');

  WriteLn('[2] 读取联系人...');
  LContacts := LReader.ReadContacts;
  WriteLn(Format('  读取 %d 个联系人', [Length(LContacts)]));
  if Length(LContacts) > 0 then
  begin
    for I := 0 to Min(2, Length(LContacts) - 1) do
      WriteLn(Format('  示例: 名=%s hash=%s',
        [LContacts[I].DisplayNameRedacted, LContacts[I].DisplayNameHash]));
  end;

  WriteLn('[3] 隐私分类...');
  LContacts := LPrivacy.ClassifyBatch(LContacts, nil);
  // 测试模式：全部标记为 BUSINESS
  for I := 0 to Length(LContacts) - 1 do
  begin
    LContacts[I].Privacy := psBusiness;
    LContacts[I].PrivacySource := psHumanConfirmed;
  end;
  WriteLn(Format('  全部分类为 BUSINESS (%d 人)', [Length(LContacts)]));

  WriteLn('[4] 读取所有消息并按联系人分组...');
  LMsgByContact := TDictionary<string, TList<TMessageMeta>>.Create;
  LTotalMsgs := 0;
  try
    // 读取所有 Msg 表
    LCursor := Default(TScanCursor);
    LContactMsgs := LReader.ReadMessages('', LCursor);
    LTotalMsgs := Length(LContactMsgs);

    // 按联系人分组：Msg 表名 = Msg_<MD5(username.lower())>
    for LMsg in LContactMsgs do
    begin
      // ConversationId 存的是 Msg 表名
      if not LMsgByContact.TryGetValue(LMsg.ConversationId, LMsgList) then
      begin
        LMsgList := TList<TMessageMeta>.Create;
        LMsgByContact.Add(LMsg.ConversationId, LMsgList);
      end;
      LMsgList.Add(LMsg);
    end;
    WriteLn(Format('  %d 条消息, %d 个 Msg 表', [LTotalMsgs, LMsgByContact.Count]));
  finally
  end;

  WriteLn('[5] 计算指标...');
  SetLength(LMetrics, LMsgByContact.Count);
  I := 0;
  for LMsgList in LMsgByContact.Values do
  begin
    LContactMsgArr := LMsgList.ToArray;
    LMetrics[I] := LMetricCalc.Compute(LContactMsgArr, Default(TInteractionMetric));
    LMetrics[I].ContactId := 'contact-' + IntToStr(I);
    Inc(I);
  end;
  WriteLn(Format('  %d 个指标', [Length(LMetrics)]));
  for I := 0 to Min(2, Length(LMetrics) - 1) do
    WriteLn(Format('  [%d] 入站=%d 出站=%d 比例=%.1f 质量=%d',
      [I, LMetrics[I].InboundCount, LMetrics[I].OutboundCount,
       LMetrics[I].OutboundInboundRatio, Ord(LMetrics[I].DataQuality)]));

  WriteLn('[6] 生成雷达提示 (真实数据)...');
  LHints := LRadarEngine.Generate(LMetrics, LContacts, nil);
  LCooling := 0; LLongSilence := 0; LReactivated := 0;
  LOutboundHeavy := 0; LDataInsuff := 0;
  for LHint in LHints do
  begin
    case LHint.HintType of
      rhtCooling: Inc(LCooling);
      rhtLongSilence: Inc(LLongSilence);
      rhtReactivated: Inc(LReactivated);
      rhtOutboundHeavy: Inc(LOutboundHeavy);
      rhtDataInsufficient: Inc(LDataInsuff);
    end;
  end;
  WriteLn(Format('  真实数据: %d 条提示 (降温=%d 沉默=%d 活跃=%d 多发=%d 不足=%d)',
    [Length(LHints), LCooling, LLongSilence, LReactivated, LOutboundHeavy, LDataInsuff]));

  // 合成数据验证
  WriteLn('[7] 合成数据验证 (无历史不生成降温/重活跃)...');
  var LTestContacts: TArray<TContact>;
  var LTestMetrics: TArray<TInteractionMetric>;
  SetLength(LTestContacts, 5);
  SetLength(LTestMetrics, 5);

  LTestContacts[0].ContactId := 'test-cooling'; LTestContacts[0].Privacy := psBusiness;
  LTestMetrics[0].ContactId := 'test-cooling'; LTestMetrics[0].LastInteractionAt := IncDay(Now, -10);
  LTestMetrics[0].InboundCount := 20; LTestMetrics[0].OutboundCount := 15; LTestMetrics[0].DataQuality := dqOK;

  LTestContacts[1].ContactId := 'test-silence'; LTestContacts[1].Privacy := psBusiness;
  LTestMetrics[1].ContactId := 'test-silence'; LTestMetrics[1].LastInteractionAt := IncDay(Now, -45);
  LTestMetrics[1].InboundCount := 20; LTestMetrics[1].DataQuality := dqOK;

  LTestContacts[2].ContactId := 'test-heavy'; LTestContacts[2].Privacy := psBusiness;
  LTestMetrics[2].ContactId := 'test-heavy'; LTestMetrics[2].LastInteractionAt := IncDay(Now, -2);
  LTestMetrics[2].InboundCount := 2; LTestMetrics[2].OutboundCount := 20;
  LTestMetrics[2].OutboundInboundRatio := 10.0; LTestMetrics[2].DataQuality := dqOK;

  LTestContacts[3].ContactId := 'test-insuff'; LTestContacts[3].Privacy := psBusiness;
  LTestMetrics[3].ContactId := 'test-insuff'; LTestMetrics[3].DataQuality := dqDataInsufficient;

  LTestContacts[4].ContactId := 'test-private'; LTestContacts[4].Privacy := psPrivate;
  LTestMetrics[4].ContactId := 'test-private'; LTestMetrics[4].DataQuality := dqOK;

  var LSyntheticHints := LRadarEngine.Generate(LTestMetrics, LTestContacts, nil);
  LCooling := 0; LLongSilence := 0; LReactivated := 0;
  LOutboundHeavy := 0; LDataInsuff := 0;
  for LHint in LSyntheticHints do
  begin
    case LHint.HintType of
      rhtCooling: Inc(LCooling);
      rhtLongSilence: Inc(LLongSilence);
      rhtReactivated: Inc(LReactivated);
      rhtOutboundHeavy: Inc(LOutboundHeavy);
      rhtDataInsufficient: Inc(LDataInsuff);
    end;
  end;
  WriteLn(Format('  合成数据: %d 条提示 (降温=%d 沉默=%d 活跃=%d 多发=%d 不足=%d)',
    [Length(LSyntheticHints), LCooling, LLongSilence, LReactivated, LOutboundHeavy, LDataInsuff]));
  WriteLn(Format('  私有跳过: %s (5 个联系人只生成 3 条有效提示)',
    [BoolToStr(Length(LSyntheticHints) = 3, True)]));

  WriteLn('[8] 构建证据链...');
  LEvidence := nil;
  for LHint in LSyntheticHints do
  begin
    var LHE := LEvidenceBuilder.Build(LHint, LTestMetrics);
    for LEv in LHE do
    begin
      SetLength(LEvidence, Length(LEvidence) + 1);
      LEvidence[High(LEvidence)] := LEv;
    end;
  end;
  WriteLn(Format('  %d 条证据记录', [Length(LEvidence)]));

  WriteLn('[9] 标签引擎...');
  LTagged := LTagEngine.DeriveTagsBatch(LContacts, LMetrics);
  WriteLn(Format('  %d 个联系人已打标签', [Length(LTagged)]));

  WriteLn('[10] 闲人漏斗...');
  LTagged := LIdleFunnel.ClassifyContacts(LTagged);
  WriteLn(Format('  %d 个已分类', [Length(LTagged)]));

  WriteLn('[11] BodyZero 审计...');
  LReport := LBodyZero.GenerateReport;
  WriteLn(Format('  BodyZero: %s', [BoolToStr(LReport.IsClean, True)]));

  // 清理
  for LMsgList in LMsgByContact.Values do LMsgList.Free;
  LMsgByContact.Free;

  WriteLn('');
  WriteLn('=== 总结 ===');
  WriteLn(Format('  联系人: %d  消息: %d  指标: %d  真实提示: %d  合成提示: %d  证据: %d  BodyZero: %s',
    [Length(LContacts), LTotalMsgs, Length(LMetrics), Length(LHints),
     Length(LSyntheticHints), Length(LEvidence), BoolToStr(LReport.IsClean, True)]));

  var LPassed := (Length(LContacts) > 0) and
    (Length(LSyntheticHints) = 3) and
    (LLongSilence = 1) and (LOutboundHeavy = 1) and (LDataInsuff = 1) and
    (LCooling = 0) and (LReactivated = 0) and LReport.IsClean;

  if LPassed then
    WriteLn('  结果: 通过')
  else begin
    WriteLn('  结果: 失败');
    Halt(1);
  end;

  if FindCmdLineSwitch('pause', True) then
    ReadLn;
end.
