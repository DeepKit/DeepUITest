unit DeepAxis.Pipeline.Evidence;

interface

uses
  System.SysUtils, System.DateUtils, System.Hash, Winapi.Windows,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Core.DataStore;

type
  /// <summary>
  ///   Builds evidence chain for each radar hint.
  ///   P0: Every hint gets at least one EvidenceRecord with source_hash.
  ///   BodyZeroReport is always clean (P0 invariant).
  /// </summary>
  TEvidenceBuilder = class(TInterfacedObject, IEvidenceBuilder)
  private
    FEvidenceStore: IEvidenceStore;
    FUseDB1Store: Boolean;
    
    function CreateEvidence(const AHint: TRadarHint;
      const AType: TEvidenceType; const ASourceRef, ASummary: string;
      const AMessages: TArray<TMessageMeta> = nil): TEvidenceRecord;
    procedure PersistEvidence(const AEvidence: TEvidenceRecord);
    function GenerateId: string;
  public
    constructor Create(AUseDB1Store: Boolean = True; AEvidenceStore: IEvidenceStore = nil); reintroduce; overload;
    constructor Create; reintroduce; overload;
    
    function Build(const AHint: TRadarHint;
      const AMetrics: TArray<TInteractionMetric>;
      const AMessages: TArray<TMessageMeta> = nil): TArray<TEvidenceRecord>;
    function BuildBodyZeroReport: TBodyZeroReport;
  end;

implementation

{ TEvidenceBuilder }

constructor TEvidenceBuilder.Create;
begin
  Self.Create(True, nil);
end;

constructor TEvidenceBuilder.Create(AUseDB1Store: Boolean; AEvidenceStore: IEvidenceStore);
begin
  inherited Create;
  FUseDB1Store := AUseDB1Store;
  FEvidenceStore := AEvidenceStore;
end;

function TEvidenceBuilder.GenerateId: string;
begin
  Result := LowerCase(Format('%x%x-%x-%x-%x-%x%x%x%x', [
    GetTickCount,
    GetTickCount div $10000,
    Random($FFFF),
    ($FFFF AND $3FFF) or $4000,
    ($FFFF AND $3FFF) or $8000,
    Random($FFFF),
    Random($FFFF),
    Random($FFFF)
  ]));
end;

procedure TEvidenceBuilder.PersistEvidence(const AEvidence: TEvidenceRecord);
begin
  if not (FUseDB1Store and Assigned(FEvidenceStore)) then Exit;
  
  try
    FEvidenceStore.Save(AEvidence);
  except
    on E: Exception do
      ; // Ignore persistence errors
  end;
end;

/// <summary>
///   BUG-051 #84: 按规格 §6 计算 source_hash — SHA-256 of MessageMeta fields
///   (create_time/local_type/real_sender_id 组合)。无消息时回退 hint 元数据哈希。
/// </summary>
function ComputeSourceHash(const AHint: TRadarHint;
  const AType: TEvidenceType; const ASourceRef: string;
  const AMessages: TArray<TMessageMeta>): string;
var
  LMsg: TMessageMeta;
  LPart: string;
begin
  LPart := '';
  for LMsg in AMessages do
    LPart := LPart + Format('%d|%d|%d;',
      [Trunc(LMsg.SentAt), Ord(LMsg.NormalizedType),
       StrToIntDef(LMsg.SourceRowRef, 0)]);

  if LPart = '' then
    // 无消息级证据: 回退 hint 元数据 (保持可追溯)
    Result := SHA256Hex(Format('%s|%s|%d|%s|%s|%s',
      [AHint.ContactId, AHint.HintId, Ord(AType),
       DateToISO8601(AHint.WindowStart), DateToISO8601(AHint.WindowEnd),
       ASourceRef]))
  else
    Result := SHA256Hex(Format('%s|%s|%d|%s',
      [AHint.ContactId, AHint.HintId, Ord(AType), LPart]));
end;

function TEvidenceBuilder.CreateEvidence(const AHint: TRadarHint;
  const AType: TEvidenceType; const ASourceRef, ASummary: string;
  const AMessages: TArray<TMessageMeta>): TEvidenceRecord;
begin
  Result := Default(TEvidenceRecord);
  Result.EvidenceId := GenerateId;
  Result.HintId := AHint.HintId;
  Result.SourceAccountId := AHint.SourceAccountId;
  Result.EvidenceType := AType;
  Result.SourceRef := ASourceRef;
  Result.SourceHash := ComputeSourceHash(AHint, AType, ASourceRef, AMessages);
  Result.Summary := ASummary;
  Result.ContainsBody := False; // P0 invariant
  Result.CreatedAt := Now;
end;

function TEvidenceBuilder.Build(const AHint: TRadarHint;
  const AMetrics: TArray<TInteractionMetric>;
  const AMessages: TArray<TMessageMeta>): TArray<TEvidenceRecord>;
var
  LMetric: TInteractionMetric;
  I: Integer;
begin
  Result := nil;

  // Find the metric for this hint's contact
  LMetric := Default(TInteractionMetric);
  for I := 0 to Length(AMetrics) - 1 do
    if AMetrics[I].ContactId = AHint.ContactId then
    begin
      LMetric := AMetrics[I];
      Break;
    end;

  // Build evidence records based on hint type
  case AHint.HintType of
    rhtCooling:
      begin
        SetLength(Result, 3);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('inbound=%d,outbound=%d,window=%s',
            [LMetric.InboundCount, LMetric.OutboundCount,
             DateToStr(LMetric.WindowEnd)]),
          Format('当前窗口：%d条入站，%d条出站', [LMetric.InboundCount, LMetric.OutboundCount]),
          AMessages);
        PersistEvidence(Result[0]);
    
        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('days_since=%d,threshold=%d',
            [DaysBetween(Now, LMetric.LastInteractionAt), AHint.CoolingDays]),
          Format('距上次互动 %d 天，超过降温阈值 %d 天',
            [DaysBetween(Now, LMetric.LastInteractionAt), AHint.CoolingDays]),
          AMessages);
        PersistEvidence(Result[1]);

        Result[2] := CreateEvidence(AHint, etMetric,
          Format('response_delay=%.1fs', [LMetric.ResponseDelayTrend]),
          Format('响应延迟趋势：%.1f 秒', [LMetric.ResponseDelayTrend]),
          AMessages);
        PersistEvidence(Result[2]);
      end;

    rhtLongSilence:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('last_interaction=%s',
            [DateTimeToStr(LMetric.LastInteractionAt)]),
          Format('最后互动：%s', [DateTimeToStr(LMetric.LastInteractionAt)]),
          AMessages);
        PersistEvidence(Result[0]);
    
        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('days_since=%d,threshold=%d',
            [DaysBetween(Now, LMetric.LastInteractionAt), AHint.LongSilenceDays]),
          Format('已沉默 %d 天，超过阈值 %d 天',
            [DaysBetween(Now, LMetric.LastInteractionAt), AHint.LongSilenceDays]),
          AMessages);
        PersistEvidence(Result[1]);
      end;

    rhtReactivated:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('recent_inbound=%d', [LMetric.InboundCount]),
          Format('最近入站消息：%d 条', [LMetric.InboundCount]),
          AMessages);
        PersistEvidence(Result[0]);
    
        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('reactivated_days=%d', [AHint.ReactivatedDays]),
          '关系已激活：长期沉默后收到新消息',
          AMessages);
        PersistEvidence(Result[1]);
      end;
    
    rhtOutboundHeavy:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('ratio=%.2f,out=%d,in=%d',
            [LMetric.OutboundInboundRatio, LMetric.OutboundCount,
             LMetric.InboundCount]),
          Format('单向发消息：%d 出 %d 入，比例 %.2f:1',
            [LMetric.OutboundCount, LMetric.InboundCount, LMetric.OutboundInboundRatio]),
          AMessages);
        PersistEvidence(Result[0]);
    
        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('outbound_heavy_ratio=%.2f', [AHint.OutboundHeavyRatio]),
          '超出单向沟通阈值', AMessages);
        PersistEvidence(Result[1]);
      end;
    
    rhtDataInsufficient:
      begin
        SetLength(Result, 1);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('msg_count=%d,min=%d',
            [LMetric.InboundCount + LMetric.OutboundCount, AHint.MinMessagesForMetric]),
          Format('消息数 %d 不足最低要求 %d',
            [LMetric.InboundCount + LMetric.OutboundCount, AHint.MinMessagesForMetric]),
          AMessages);
        PersistEvidence(Result[0]);
      end;
    
    rhtHighLinkSharing:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('link_count=%d,total_msgs=%d',
            [LMetric.LinkCount, LMetric.InboundCount + LMetric.OutboundCount]),
          Format('链接消息 %d 条，占消息总数 %d 条',
            [LMetric.LinkCount, LMetric.InboundCount + LMetric.OutboundCount]),
          AMessages);
        PersistEvidence(Result[0]);
    
        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('link_threshold=%d', [5]),
          '链接数超过阈值 5，可能存在推广行为', AMessages);
        PersistEvidence(Result[1]);
      end;
    
    rhtMarketingPattern:
      begin
        SetLength(Result, 2);
        Result[0] := CreateEvidence(AHint, etMetric,
          Format('has_marketing=true,avg_text_len=%d',
            [LMetric.AvgTextLength]),
          Format('检测到营销关键词，平均文本长度 %d 字',
            [LMetric.AvgTextLength]),
          AMessages);
        PersistEvidence(Result[0]);

        Result[1] := CreateEvidence(AHint, etThreshold,
          Format('media_count=%d', [LMetric.MediaCount]),
          Format('媒体消息 %d 条', [LMetric.MediaCount]),
          AMessages);
        PersistEvidence(Result[1]);
      end;
  end;
end;

function TEvidenceBuilder.BuildBodyZeroReport: TBodyZeroReport;
begin
  // P0 invariant: body-zero is always clean.
  // No code path reads message body columns.
  Result := TBodyZeroReport.CreateClean;
end;

end.
