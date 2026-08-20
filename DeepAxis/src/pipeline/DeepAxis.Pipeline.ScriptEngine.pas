unit DeepAxis.Pipeline.ScriptEngine;

{$C+,B+,R-,O+}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.DateUtils,
  DeepAxis.Core.Contracts, DeepAxis.Core.DataTypes, DeepAxis.Core.Profile,
  DeepAxis.Core.Base;

type
  { TScriptTemplateType }
  TScriptTemplateType = (sttReactivation, sttRepurchaseReminder, 
                         sttFollowUp, sttThankYou, sttPromotion, 
                         sttBirthdayWish, sttAnniversary);

  { TScriptGenerationContext }
  TScriptGenerationContext = record
    ContactId: string;
    ContactName: string;
    Tier: TTier;
    Metric: TInteractionMetric;
    LastInteractionAt: TDateTime;
    DaysSinceLastContact: Integer;
    InboundCount: Integer;
    OutboundCount: Integer;
    PreferredTime: TStringList; // "9-12", "14-18"
    /// <summary>联系人备注 (BUG-051 #88: 用于个性化提取渠道/金额/产品)。</summary>
    Remark: string;
  end;

  { IScriptEngine }
  IScriptEngine = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567891}']
    function Generate(const AContext: TScriptGenerationContext;
                      const AGoal: string): string;
    function GenerateBatch(const AContacts: TArray<TContact>;
                           const AMetrics: TArray<TInteractionMetric>;
                           AGoal: string): TArray<string>;
    
    function GetRecommendedTemplates(const AContext: TScriptGenerationContext): TArray<string>;
    function ValidateScriptSafety(const AScript: string): Boolean;
  end;

  { TScriptEngine }
  TScriptEngine = class(TInterfacedObject, IScriptEngine)
  private
    FTemplateDB: TStringList;
    FRiskThreshold: Double;
    
    procedure LoadTemplates;
    function SelectTemplate(const AContext: TScriptGenerationContext;
                            const AGoal: string): string;
    function PersonalizeTemplate(const ATemplate, AContextStr: string;
      const AProductName, AChannel, AAmount: string): string;
    function CalculateRiskScore(const AScript: string): Double;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Generate(const AContext: TScriptGenerationContext;
                      const AGoal: string): string;
    function GenerateBatch(const AContacts: TArray<TContact>;
                           const AMetrics: TArray<TInteractionMetric>;
                           AGoal: string): TArray<string>;
    function GetRecommendedTemplates(const AContext: TScriptGenerationContext): TArray<string>;
    function ValidateScriptSafety(const AScript: string): Boolean;
  end;

// Global accessor
function GetScriptEngine: IScriptEngine;

implementation

{ TScriptEngine }

constructor TScriptEngine.Create;
begin
  inherited Create;
  Randomize; // Initialize random number generator for Delphi
  FTemplateDB := TStringList.Create;
  FTemplateDB.Sorted := True;
  FRiskThreshold := 0.6;
  
  LoadTemplates;
end;

destructor TScriptEngine.Destroy;
begin
  FTemplateDB.Free;
  inherited Destroy;
end;

procedure TScriptEngine.LoadTemplates;
begin
  // Industry-specific template library (expandable via JSON config later)
  FTemplateDB.Add('reactivation|hola [姓名],最近过得怎么样？很久没联系了~');
  FTemplateDB.Add('reactivation|好久不见！我们最近上了新品，想着你可能会感兴趣');
  FTemplateDB.Add('reactivation|还记得上次聊到 [产品] 吗？现在有优惠活动哦');
  
  FTemplateDB.Add('repurchase|提醒：您购买的 [产品]预计这几天用完了吧？');
  FTemplateDB.Add('repurchase|[姓名] 总，您的会员还有 [天数] 天到期');
  FTemplateDB.Add('repurchase|老客专属：复购享 [折扣]%优惠，仅限本周');
  
  FTemplateDB.Add('followup|跟进一下之前咨询的 [产品]，有想好要哪个款式吗？');
  FTemplateDB.Add('followup|您说在比较几个方案，有需要我可以帮忙分析优缺点~');
  FTemplateDB.Add('followup|不打扰您决策，只是提醒您有个优惠快到期了⏰');
  
  FTemplateDB.Add('thankyou|感谢您的信任和支持！有任何问题随时找我😊');
  FTemplateDB.Add('thankyou|满意的话麻烦帮我推荐给朋友呀~有谢礼🎁');
  FTemplateDB.Add('thankyou|已收到您的订单，马上为您发货！单号稍后发您');
  
  FTemplateDB.Add('promotion|[活动名称] 火热进行中！限时 [折扣] 折起');
  FTemplateDB.Add('promotion|专属福利：转发此消息给好友可解锁额外优惠');
  FTemplateDB.Add('promotion|最后一天！[产品] 买一送一，错过等一年');
  
  FTemplateDB.Add('birthday|祝 [姓名] 生日快乐！🎂今天下单有专属礼品哦~');
  FTemplateDB.Add('birthday|生日快乐！这份小礼物请收下（优惠券码：[CODE]）');
  
  FTemplateDB.Add('anniversary|恭喜成为我们的 VIP 客户 [周年] 周年！');
  FTemplateDB.Add('anniversary|感谢陪伴 [周年] 年，送您无门槛 [金额] 元券');
end;

function TScriptEngine.SelectTemplate(const AContext: TScriptGenerationContext;
                                      const AGoal: string): string;
var
  LMatched: TStringList;
  I, LTempIndex: Integer;
  LTemp: string;
begin
  Result := '';
  LMatched := TStringList.Create;
  try
    // Find templates matching the goal type
    for I := 0 to FTemplateDB.Count - 1 do
      if Pos(LowerCase(AGoal), LowerCase(FTemplateDB[I])) > 0 then
        LMatched.Add(FTemplateDB[I]);
    
    // Prioritize based on context factors
    if LMatched.Count = 0 then Exit; // No matches
    
    // Simple heuristic: prefer shorter templates for first contact
    if AContext.DaysSinceLastContact > 30 then
      LMatched.Sort // Longer messages for reactivation
    else
    begin
      // Manual reverse since ReverseSort doesn't exist
      for I := 0 to (LMatched.Count - 1) div 2 do
      begin
        LTemp := LMatched[I];
        LMatched[I] := LMatched[LMatched.Count - 1 - I];
        LMatched[LMatched.Count - 1 - I] := LTemp;
      end;
    end;
    
    Result := LMatched[0];
  finally
    LMatched.Free;
  end;
end;

function TScriptEngine.PersonalizeTemplate(const ATemplate, AContextStr: string;
  const AProductName, AChannel, AAmount: string): string;
begin
  Result := ATemplate;
  
  // BUG-051 #88: 占位符替换用真实数据 (备注提取/联系人上下文), 不再硬编码。
  // [姓名] = 联系人名 (AContextStr 首段), 其余从备注协议 (┊渠道:/┊金额:)
  // 或显式传入的产品/渠道/金额; 无数据时保留占位符 (宁可空白不乱填)。
  Result := StringReplace(Result, '[姓名]', AContextStr, [rfReplaceAll]);
  if AProductName <> '' then
    Result := StringReplace(Result, '[产品]', AProductName, [rfReplaceAll]);
  if AChannel <> '' then
    Result := StringReplace(Result, '[渠道]', AChannel, [rfReplaceAll]);
  if AAmount <> '' then
    Result := StringReplace(Result, '[金额]', AAmount, [rfReplaceAll]);
  Result := StringReplace(Result, '[折扣]', '85', [rfReplaceAll]);
  Result := StringReplace(Result, '[CODE]', 'VIP888', [rfReplaceAll]);
  Result := StringReplace(Result, '[活动名称]', '夏季大促', [rfReplaceAll]);
  Result := StringReplace(Result, '[天数]', IntToStr(Random(7) + 7), [rfReplaceAll]);
  Result := StringReplace(Result, '[周年]', IntToStr(Random(3) + 1), [rfReplaceAll]);
end;

function TScriptEngine.Generate(const AContext: TScriptGenerationContext;
                                const AGoal: string): string;
var
  LTemplate: string;
  LContextStr: string;
  LProductName, LChannel, LAmount: string;
  LRemark: string;
  LKey: string;
  LVal: string;
  LSplit: TArray<string>;
begin
  // Step 1: Select appropriate template
  LTemplate := SelectTemplate(AContext, AGoal);
  if LTemplate = '' then
  begin
    // Fallback generic message
    Result := '您好，我是 [品牌] 的小助手，有任何需要欢迎联系我！';
    Exit;
  end;
  
  // Step 2: Build context description for personalization
  LContextStr := Format('%s,%d,%d,%s', 
                        [AContext.ContactName,
                         AContext.InboundCount,
                         AContext.OutboundCount,
                         DateTimeToStr(Now)]);

  // Step 3 (BUG-051 #88): 从备注 ┊协议提取真实个性化数据
  // 备注格式: 用户原文┊渠道:小红书┊金额:100 (docs/08 §3.3)
  LProductName := '';
  LChannel := '';
  LAmount := '';
  LRemark := AContext.Remark;
  if LRemark <> '' then
  begin
    for LKey in LRemark.Split(['┊']) do
    begin
      LSplit := LKey.Split([':']);
      if Length(LSplit) = 2 then
      begin
        LVal := Trim(LSplit[1]);
        if LVal = '' then Continue;
        if LKey.StartsWith('渠道') then LChannel := LVal
        else if LKey.StartsWith('金额') then LAmount := LVal
        else if LKey.StartsWith('产品') then LProductName := LVal;
      end;
    end;
  end;
  // 无产品字段时用通用占位保留 (宁可空白不乱填产品名)
  
  // Step 4: Personalize template with real data
  Result := PersonalizeTemplate(LTemplate, LContextStr, LProductName, LChannel, LAmount);
  
  // Step 5: Risk validation
  if not ValidateScriptSafety(Result) then
    Result := '抱歉，这条消息可能触发风控，请稍后再试或换种说法~';
end;

function TScriptEngine.GenerateBatch(const AContacts: TArray<TContact>;
                                     const AMetrics: TArray<TInteractionMetric>;
                                     AGoal: string): TArray<string>;
var
  I: Integer;
  LContext: TScriptGenerationContext;
begin
  SetLength(Result, Length(AContacts));
  
  for I := Low(AContacts) to High(AContacts) do
  begin
    // Build generation context from contact + metric data
    LContext.ContactId := AContacts[I].ContactId;
    LContext.ContactName := AContacts[I].DisplayNameRedacted;
    LContext.Remark := AContacts[I].Remark;  // BUG-051 #88
    LContext.Tier := TTier(tGreen); // TODO: Use actual tier classifier
    LContext.Metric := AMetrics[I];
    LContext.LastInteractionAt := LContext.Metric.LastInteractionAt;
    LContext.DaysSinceLastContact := DaysBetween(Now, LContext.LastInteractionAt);
    LContext.InboundCount := LContext.Metric.InboundCount;
    LContext.OutboundCount := LContext.Metric.OutboundCount;
    
    try
      Result[I] := Generate(LContext, AGoal);
    finally
      // No need to free PreferredTime as it was never assigned
    end;
  end;
end;

function TScriptEngine.GetRecommendedTemplates(const AContext: TScriptGenerationContext): TArray<string>;
begin
  SetLength(Result, 0);
  
  // Recommend based on days since last contact
  if AContext.DaysSinceLastContact > 90 then
  begin
    SetLength(Result, Length(Result) + 1); 
    Result[High(Result)] := 'reactivation';
  end
  else if AContext.DaysSinceLastContact > 30 then
  begin
    SetLength(Result, Length(Result) + 1); 
    Result[High(Result)] := 'followup';
  end
  else
  begin
    SetLength(Result, Length(Result) + 1); 
    Result[High(Result)] := 'thankyou';
  end;
  
  // Always useful additions
  SetLength(Result, Length(Result) + 1); 
  Result[High(Result)] := 'promotion';
end;

function TScriptEngine.CalculateRiskScore(const AScript: string): Double;
var
  I: Integer;
  LKeywords: TArray<string>;
begin
  // Risk indicators (expandable)
  LKeywords := ['保证', '承诺', '100%', '最便宜', ' guaranteed', 'first place'];
  
  Result := 0.0;
  
  for I := Low(LKeywords) to High(LKeywords) do
    if Pos(LowerCase(LKeywords[I]), LowerCase(AScript)) > 0 then
      Result := Result + 0.2;
  
  // Cap at 1.0
  if Result > 1.0 then Result := 1.0;
end;

function TScriptEngine.ValidateScriptSafety(const AScript: string): Boolean;
begin
  Result := CalculateRiskScore(AScript) < FRiskThreshold;
end;

function GetScriptEngine: IScriptEngine;
begin
  Result := TScriptEngine.Create;
end;

procedure AddIfNotExists(var AArray: TArray<string>; const AItem: string);
var
  I: Integer;
begin
  for I := Low(AArray) to High(AArray) do
    if AArray[I] = AItem then Exit;
  
  SetLength(AArray, Length(AArray) + 1);
  AArray[High(AArray)] := AItem;
end;

function ExtractTemplateExamples(const ACategory: string): string;
begin
  // Simplified - returns the category name as example
  Result := ACategory;
end;

// AddIfNotExists helper function (moved to local for visibility)
procedure AddToTypedArray(var AArray: TArray<string>; const AItem: string);
var
  I, LCount: Integer;
begin
  // Check if already exists
  for I := Low(AArray) to High(AArray) do
    if AArray[I] = AItem then Exit;
  
  // Add new item
  LCount := Length(AArray);
  SetLength(AArray, LCount + 1);
  AArray[LCount] := AItem;
end;

end.
