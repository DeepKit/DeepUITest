unit DeepAxis.Pipeline.ScriptEngine;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.DateUtils, System.Math,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   话术模板变量。模板中用 {变量名} 引用，引擎自动替换。
  ///   例: "{客户名}你好，上��联系是{上次互动}，最近{产品名}有活动..."
  /// </summary>
  TScriptVariable = record
    Name: string;       // 变量名
    Value: string;      // 替换值
    Source: string;     // 来源: metadata/remark/content/user
  end;

  /// <summary>
  ///   话术模板。P0 阶段使用规则模板，不需要 LLM。
  ///   模板包含: 名称、分类、适用场景、变量列表、话术正文。
  /// </summary>
  TScriptTemplate = class
  public
    Name: string;           // 模板名称
    Category: string;       // 分类: 跟进/促销/关怀/删除确认
    Tone: string;           // 口吻: 正式/亲切/直接
    Body: string;           // 模板正文，含 {变量名} 占位符
    Variables: TArray<string>; // 需要的变量列表
    Confidence: Double;     // 推荐置信度
    constructor Create(const AName, ACategory, ATone, ABody: string;
      const AVars: TArray<string>; AConfidence: Double);
  end;

  /// <summary>
  ///   话术引擎。P0: 基于规则模板 + 变量替换。
  ///   P2+: 接入 LLM 生成话术。
  /// </summary>
  TScriptEngine = class
  private
    FTemplates: TObjectList<TScriptTemplate>;
    function ReplaceVariables(const ATemplate: string;
      const AVariables: TArray<TScriptVariable>): string;
    function ExtractVariableValue(const AContact: TContact;
      const AVarName: string): string;
    function ScoreTemplate(const ATemplate: TScriptTemplate;
      const AContact: TContact; const AHintType: TRadarHintType): Double;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>加载内置话术模板</summary>
    procedure LoadBuiltinTemplates;

    /// <summary>注册自定义模板</summary>
    procedure RegisterTemplate(const ATemplate: TScriptTemplate);

    /// <summary>为指定联系人和提示类型生成话术</summary>
    function GenerateScript(const AContact: TContact;
      const AHintType: TRadarHintType): string;

    /// <summary>生成多个口吻变体</summary>
    function GenerateVariants(const AContact: TContact;
      const AHintType: TRadarHintType; ACount: Integer): TArray<string>;

    /// <summary>获取所有模板</summary>
    function GetTemplates: TArray<TScriptTemplate>;

    /// <summary>按分类获取模板</summary>
    function GetTemplatesByCategory(const ACategory: string): TArray<TScriptTemplate>;
  end;

implementation

{ TScriptTemplate }

constructor TScriptTemplate.Create(const AName, ACategory, ATone, ABody: string;
  const AVars: TArray<string>; AConfidence: Double);
begin
  inherited Create;
  Name := AName;
  Category := ACategory;
  Tone := ATone;
  Body := ABody;
  Variables := AVars;
  Confidence := AConfidence;
end;

{ TScriptEngine }

constructor TScriptEngine.Create;
begin
  inherited Create;
  FTemplates := TObjectList<TScriptTemplate>.Create(True);
  LoadBuiltinTemplates;
end;

destructor TScriptEngine.Destroy;
begin
  FTemplates.Free;
  inherited;
end;

procedure TScriptEngine.LoadBuiltinTemplates;
begin
  // ── 跟进类话术 ─────────────────────────────────────────────────
  RegisterTemplate(TScriptTemplate.Create(
    '降温回暖', '跟进', '亲切',
    '{客户名}你好！好久没联系了，最近还好吗？上次聊到{产品名}，不知道你这边有没有新的想法？',
    TArray<string>.Create('客户名', '产品名'), 0.8));

  RegisterTemplate(TScriptTemplate.Create(
    '长期沉默唤醒', '跟进', '亲切',
    '{客户名}，好久不见！最近我们{产品名}有一些新变化，想跟你分享一下~',
    TArray<string>.Create('客户名', '产品名'), 0.7));

  RegisterTemplate(TScriptTemplate.Create(
    '重新活跃跟进', '跟进', '直接',
    '{客户名}，看到你最近在关注{产品名}，有什么我可以帮你的吗？',
    TArray<string>.Create('客户名', '产品名'), 0.9));

  RegisterTemplate(TScriptTemplate.Create(
    '单向过多提醒', '跟进', '直接',
    '{客户名}，之前给你发了不少消息，可能打扰到你了。如果你对{产品名}有兴趣，随时告诉我~',
    TArray<string>.Create('客户名', '产品名'), 0.6));

  // ── 促销类话术 ─────────────────────────────────────────────────
  RegisterTemplate(TScriptTemplate.Create(
    '新品推荐', '促销', '亲切',
    '{客户名}，最近{产品名}出了新款，我觉得很适合你，要不要看看？',
    TArray<string>.Create('客户名', '产品名'), 0.7));

  RegisterTemplate(TScriptTemplate.Create(
    '限时优惠', '促销', '直接',
    '{客户名}，{产品名}这两天有活动，比平时便宜不少，有需要的话抓紧哦！',
    TArray<string>.Create('客户名', '产品名'), 0.75));

  // ── 关怀类话术 ─────────────────────────────────────────────────
  RegisterTemplate(TScriptTemplate.Create(
    '节日问候', '关怀', '亲切',
    '{客户名}，节日快乐！感谢一直以来的支持，祝你和家人一切顺利！',
    TArray<string>.Create('客户名'), 0.9));

  RegisterTemplate(TScriptTemplate.Create(
    '生日祝福', '关怀', '亲切',
    '{客户名}，生日快乐！祝你新的一岁万事如意，越来越美！',
    TArray<string>.Create('客户名'), 0.9));

  // ── 删除确认类话术 ─────────────────────────────────────────────
  RegisterTemplate(TScriptTemplate.Create(
    '删除前最后联系', '删除确认', '直接',
    '{客户名}，你好！之前给你发过几次{产品名}的信息，一直没有收到回复。如果不需要了，我这边就不再打扰了哦~',
    TArray<string>.Create('客户名', '产品名'), 0.8));

  // ── 渠道特定话术 ───────────────────────────────────────────────
  RegisterTemplate(TScriptTemplate.Create(
    '小红书渠道', '跟进', '亲切',
    '{客户名}，在小红书上看到你的分享，觉得你对{产品名}很了解。想跟你交流一下~',
    TArray<string>.Create('客户名', '产品名'), 0.75));

  RegisterTemplate(TScriptTemplate.Create(
    '转介绍渠道', '跟进', '亲切',
    '{客户名}，{渠道}推荐你过来的，说你对{产品名}感兴趣。我来跟你详细介绍一下？',
    TArray<string>.Create('客户名', '渠道', '产品名'), 0.85));
end;

procedure TScriptEngine.RegisterTemplate(const ATemplate: TScriptTemplate);
begin
  FTemplates.Add(ATemplate);
end;

function TScriptEngine.ExtractVariableValue(const AContact: TContact;
  const AVarName: string): string;
var
  LProfile: TJSONObject;
  LObj: TJSONObject;
begin
  Result := '';

  if AVarName = '客户名' then
  begin
    Result := AContact.DisplayNameRedacted;
    Exit;
  end;

  if AVarName = '产品名' then
  begin
    // 从标签中提取产品关联
    try
      LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
      if LProfile <> nil then
      begin
        var LArr := LProfile.GetValue('product_associations') as TJSONArray;
        if (LArr <> nil) and (LArr.Count > 0) then
        begin
          LObj := LArr.Items[0] as TJSONObject;
          if LObj <> nil then
            Result := LObj.GetValue<string>('name', '');
        end;
      end;
    except
    end;
    if Result = '' then
      Result := '我们的产品';
    Exit;
  end;

  // 渠道
  if AVarName = '渠道' then
  begin
    try
      LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
      if LProfile <> nil then
      begin
        LObj := LProfile.GetValue('channel') as TJSONObject;
        if LObj <> nil then
          Result := LObj.GetValue<string>('label', '');
      end;
    except
    end;
    if Result = '' then Result := '朋友';
    Exit;
  end;

  // 默认: 从备注中提取
  if AContact.Remark <> '' then
    Result := AContact.Remark;
end;

function TScriptEngine.ReplaceVariables(const ATemplate: string;
  const AVariables: TArray<TScriptVariable>): string;
var
  LVar: TScriptVariable;
begin
  Result := ATemplate;
  for LVar in AVariables do
    Result := Result.Replace('{' + LVar.Name + '}', LVar.Value);
end;

function TScriptEngine.ScoreTemplate(const ATemplate: TScriptTemplate;
  const AContact: TContact; const AHintType: TRadarHintType): Double;
begin
  Result := ATemplate.Confidence;

  // 根据提示类型调整匹配度
  case AHintType of
    rhtCooling:       if ATemplate.Category = '跟进' then Result := Result * 1.2;
    rhtLongSilence:   if ATemplate.Name.Contains('沉默') then Result := Result * 1.3;
    rhtReactivated:   if ATemplate.Category = '跟进' then Result := Result * 1.1;
    rhtOutboundHeavy: if ATemplate.Tone = '直接' then Result := Result * 1.2;
  end;

  // 渠道匹配
  try
    var LProfile := TJSONObject.ParseJSONValue(AContact.TagProfile) as TJSONObject;
    if LProfile <> nil then
    begin
      var LChObj := LProfile.GetValue('channel') as TJSONObject;
      if LChObj <> nil then
      begin
        var LCh := LChObj.GetValue<string>('label', '');
        if ATemplate.Name.Contains(LCh) then Result := Result * 1.5;
      end;
    end;
  except
  end;

  Result := Min(1.0, Result);
end;

function TScriptEngine.GenerateScript(const AContact: TContact;
  const AHintType: TRadarHintType): string;
var
  LBest: TScriptTemplate;
  LBestScore: Double;
  LScore: Double;
  LTemplate: TScriptTemplate;
  LVars: TArray<TScriptVariable>;
  LVarname: string;
begin
  LBest := nil;
  LBestScore := 0;

  for LTemplate in FTemplates do
  begin
    LScore := ScoreTemplate(LTemplate, AContact, AHintType);
    if LScore > LBestScore then
    begin
      LBestScore := LScore;
      LBest := LTemplate;
    end;
  end;

  if LBest = nil then
  begin
    Result := Format('%s，你好！最近怎么样？', [AContact.DisplayNameRedacted]);
    Exit;
  end;

  // 构建变量
  SetLength(LVars, Length(LBest.Variables));
  for var I := 0 to Length(LBest.Variables) - 1 do
  begin
    LVars[I].Name := LBest.Variables[I];
    LVars[I].Value := ExtractVariableValue(AContact, LBest.Variables[I]);
    LVars[I].Source := 'metadata';
  end;

  Result := ReplaceVariables(LBest.Body, LVars);
end;

function TScriptEngine.GenerateVariants(const AContact: TContact;
  const AHintType: TRadarHintType; ACount: Integer): TArray<string>;
var
  LAll: TArray<TScriptTemplate>;
  LTemplate: TScriptTemplate;
  LScore: Double;
  LVars: TArray<TScriptVariable>;
  I: Integer;
begin
  Result := nil;
  LAll := GetTemplates;

  // 按分数排序，取前 N 个
  var LScores: TArray<Double>;
  SetLength(LScores, Length(LAll));
  for I := 0 to Length(LAll) - 1 do
    LScores[I] := ScoreTemplate(LAll[I], AContact, AHintType);

  // 简单冒泡排序
  for I := 0 to Length(LAll) - 2 do
    for var J := I + 1 to Length(LAll) - 1 do
      if LScores[J] > LScores[I] then
      begin
        LTemplate := LAll[I]; LAll[I] := LAll[J]; LAll[J] := LTemplate;
        LScore := LScores[I]; LScores[I] := LScores[J]; LScores[J] := LScore;
      end;

  ACount := Min(ACount, Length(LAll));
  SetLength(Result, ACount);

  for I := 0 to ACount - 1 do
  begin
    SetLength(LVars, Length(LAll[I].Variables));
    for var J := 0 to Length(LAll[I].Variables) - 1 do
    begin
      LVars[J].Name := LAll[I].Variables[J];
      LVars[J].Value := ExtractVariableValue(AContact, LAll[I].Variables[J]);
      LVars[J].Source := 'metadata';
    end;
    Result[I] := ReplaceVariables(LAll[I].Body, LVars);
  end;
end;

function TScriptEngine.GetTemplates: TArray<TScriptTemplate>;
begin
  Result := FTemplates.ToArray;
end;

function TScriptEngine.GetTemplatesByCategory(const ACategory: string): TArray<TScriptTemplate>;
var
  LTemplate: TScriptTemplate;
begin
  Result := nil;
  for LTemplate in FTemplates do
    if SameText(LTemplate.Category, ACategory) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LTemplate;
    end;
end;

end.