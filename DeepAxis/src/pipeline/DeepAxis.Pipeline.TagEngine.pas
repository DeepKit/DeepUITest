unit DeepAxis.Pipeline.TagEngine;

interface

uses
  System.SysUtils, System.Math, System.RegularExpressions, System.JSON,
  System.DateUtils, System.Generics.Collections, System.Generics.Defaults,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.WeChat.MsgParser;

type
  /// <summary>
  ///   Tag matrix derivation engine. P0 L0: read-only tag derivation from
  ///   M0 metadata (WeChat labels, remark regex, interaction pattern) and
  ///   message content analysis.
  ///   All tags include confidence, source, and timestamp.
  ///   Principle: "宁愿空白也不乱标" — leave blank rather than guess.
  /// </summary>
  TTagEngine = class(TInterfacedObject, ITagEngine)
  private
    function DeriveIdentity(const AContact: TContact): TJSONObject;
    function DeriveInteractionState(const AMetric: TInteractionMetric): TJSONObject;
    function DeriveChannel(const AContact: TContact): TJSONObject;
    function DeriveKeyDates(const AContact: TContact): TJSONObject;
    function DeriveIdleJudge(const AContact: TContact): TJSONObject;
    function DeriveContentProfile(const AMessages: TArray<TMessageMeta>): TJSONObject;
    function MergeProfile(const AOldProfile: string;
      const ANewTags: TJSONObject): string;
    function ExtractDateFromRemark(const ARemark: string): TDateTime;
    function ExtractChannelFromRemark(const ARemark: string): string;
    function GuessIdentityFromLabels(const ALabels: TArray<string>): string;
    function ComputeConfidence(const AConfidence: Double): Double;
  public
    function DeriveTags(const AContact: TContact;
      const AMetrics: TArray<TInteractionMetric>;
      const AMessages: TArray<TMessageMeta>): TContact;
    function DeriveTagsBatch(const AContacts: TArray<TContact>;
      const AMetrics: TArray<TInteractionMetric>;
      const AMessagesByContact: TDictionary<string, TArray<TMessageMeta>>): TArray<TContact>;
  end;

implementation

{ TTagEngine }

function TTagEngine.ComputeConfidence(const AConfidence: Double): Double;
begin
  if AConfidence < 0.3 then
    Result := 0.0 // below threshold: leave blank
  else
    Result := Min(1.0, Max(0.3, AConfidence));
end;

function TTagEngine.GuessIdentityFromLabels(const ALabels: TArray<string>): string;
// Known WeChat label patterns -> identity category
const
  CUSTOMER_PATTERNS: array[0..5] of string = ('客户', '顾客', '买家', '客户', '客', '會員');
  FRIEND_PATTERNS: array[0..3] of string = ('朋友', '好友', '同学', '同事');
  FAMILY_PATTERNS: array[0..3] of string = ('家人', '亲戚', '爸', '妈');
  COMPETITOR_PATTERNS: array[0..2] of string = ('同行', '竞品', '供应商');
var
  S: string;
  L: string;
begin
  Result := '';
  for L in ALabels do
  begin
    for S in CUSTOMER_PATTERNS do
      if L.Contains(S) then Exit('客户');
    for S in FRIEND_PATTERNS do
      if L.Contains(S) then Exit('朋友');
    for S in FAMILY_PATTERNS do
      if L.Contains(S) then Exit('家人');
    for S in COMPETITOR_PATTERNS do
      if L.Contains(S) then Exit('同行');
  end;
end;

function TTagEngine.ExtractDateFromRemark(const ARemark: string): TDateTime;
// Extract date patterns from remark text: YYYY-MM-DD, YYYY/MM/DD, MM-DD, MM/DD
var
  LMatch: TMatch;
begin
  Result := 0;

  // Pattern: YYYY-MM-DD or YYYY/MM/DD
  LMatch := TRegEx.Match(ARemark, '\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b');
  if LMatch.Success then
  begin
    Result := EncodeDate(
      StrToInt(LMatch.Groups[1].Value),
      StrToInt(LMatch.Groups[2].Value),
      StrToInt(LMatch.Groups[3].Value));
    Exit;
  end;

  // Pattern: MM-DD or MM/DD (birthday, purchase date)
  LMatch := TRegEx.Match(ARemark, '\b(\d{1,2})[-/](\d{1,2})\b');
  if LMatch.Success then
  begin
    Result := EncodeDate(2020,
      StrToInt(LMatch.Groups[1].Value),
      StrToInt(LMatch.Groups[2].Value));
    Exit;
  end;
end;

function TTagEngine.ExtractChannelFromRemark(const ARemark: string): string;
// Extract channel keywords from remark
const
  CHANNELS: array[0..7] of string = (
    '小红书', '抖音', '快手', '转介绍', '微信群', '线下', '公众号', '视频号'
  );
var
  S: string;
begin
  Result := '';
  for S in CHANNELS do
    if ARemark.Contains(S) then
      Exit(S);
end;

function TTagEngine.DeriveIdentity(const AContact: TContact): TJSONObject;
var
  LIdentity: string;
  LConfidence: Double;
begin
  Result := TJSONObject.Create;

  LIdentity := GuessIdentityFromLabels(AContact.WeChatLabels);
  if LIdentity <> '' then
  begin
    LConfidence := ComputeConfidence(0.5);
    Result.AddPair('label', LIdentity);
    Result.AddPair('confidence', TJSONNumber.Create(LConfidence));
    Result.AddPair('source', 'wechat_label');
    Result.AddPair('derived_at', DateToISO8601(Now));
  end
  else
  begin
    // Leave blank: not enough signal
    Result.AddPair('label', '');
    Result.AddPair('confidence', TJSONNumber.Create(0.0));
    Result.AddPair('source', 'none');
    Result.AddPair('derived_at', DateToISO8601(Now));
  end;
end;

function TTagEngine.DeriveInteractionState(const AMetric: TInteractionMetric): TJSONObject;
var
  LState: string;
  LConfidence: Double;
  LDaysSince: Integer;
begin
  Result := TJSONObject.Create;

  if AMetric.LastInteractionAt = 0 then
  begin
    Result.AddPair('label', '新导入');
    Result.AddPair('confidence', TJSONNumber.Create(0.5));
    Result.AddPair('source', 'metadata');
    Result.AddPair('derived_at', DateToISO8601(Now));
    Exit;
  end;

  LDaysSince := DaysBetween(Now, AMetric.LastInteractionAt);

  if LDaysSince <= 7 then
    LState := '活跃'
  else if LDaysSince <= 30 then
    LState := '降温'
  else if LDaysSince <= 90 then
    LState := '长期沉默'
  else
    LState := '极长期沉默';

  LConfidence := ComputeConfidence(1.0); // purely metadata-based, high confidence

  Result.AddPair('label', LState);
  Result.AddPair('confidence', TJSONNumber.Create(LConfidence));
  Result.AddPair('source', 'metadata');
  Result.AddPair('days_since', TJSONNumber.Create(LDaysSince));
  Result.AddPair('derived_at', DateToISO8601(Now));
end;

function TTagEngine.DeriveChannel(const AContact: TContact): TJSONObject;
var
  LChannel: string;
  LConfidence: Double;
begin
  Result := TJSONObject.Create;

  LChannel := ExtractChannelFromRemark(AContact.Remark);
  if LChannel <> '' then
  begin
    LConfidence := ComputeConfidence(0.7);
    Result.AddPair('label', LChannel);
    Result.AddPair('confidence', TJSONNumber.Create(LConfidence));
    Result.AddPair('source', 'remark_regex');
    Result.AddPair('derived_at', DateToISO8601(Now));
  end
  else
  begin
    Result.AddPair('label', '');
    Result.AddPair('confidence', TJSONNumber.Create(0.0));
    Result.AddPair('source', 'none');
    Result.AddPair('derived_at', DateToISO8601(Now));
  end;
end;

function TTagEngine.DeriveKeyDates(const AContact: TContact): TJSONObject;
var
  LDate: TDateTime;
begin
  Result := TJSONObject.Create;

  LDate := ExtractDateFromRemark(AContact.Remark);
  if LDate > 0 then
  begin
    Result.AddPair('date', DateToISO8601(LDate));
    Result.AddPair('confidence', TJSONNumber.Create(0.8));
    Result.AddPair('source', 'remark_regex');
  end
  else
  begin
    Result.AddPair('date', '');
    Result.AddPair('confidence', TJSONNumber.Create(0.0));
    Result.AddPair('source', 'none');
  end;
  Result.AddPair('derived_at', DateToISO8601(Now));
end;

function TTagEngine.DeriveIdleJudge(const AContact: TContact): TJSONObject;
begin
  Result := TJSONObject.Create;

  // P0: all contacts are "闲人" (no product association support yet)
  Result.AddPair('label', '闲人');
  Result.AddPair('confidence', TJSONNumber.Create(1.0));
  Result.AddPair('source', 'metadata');
  Result.AddPair('reason', 'default_p0');
  Result.AddPair('derived_at', DateToISO8601(Now));
end;

function TTagEngine.MergeProfile(const AOldProfile: string;
  const ANewTags: TJSONObject): string;
var
  LOldProfile: TJSONObject;
  LPair: TJSONPair;
  LParsed: TJSONValue;
  I: Integer;
begin
  // Try to parse existing profile — fix: free non-TJSONObject results
  LParsed := nil;
  LOldProfile := nil;
  try
    LParsed := TJSONObject.ParseJSONValue(AOldProfile);
    if LParsed is TJSONObject then
      LOldProfile := TJSONObject(LParsed)
    else
    begin
      LParsed.Free;
      LParsed := nil;
    end;
  except
    // Parse failed — LParsed may be partially allocated
    LParsed.Free;
    LParsed := nil;
  end;

  if LOldProfile = nil then
    LOldProfile := TJSONObject.Create;

  try
    // Merge new tags into old profile
    for I := 0 to ANewTags.Count - 1 do
    begin
      LPair := ANewTags.Pairs[I];
      // Remove old key if exists
      if LOldProfile.GetValue(LPair.JsonString.Value) <> nil then
        LOldProfile.RemovePair(LPair.JsonString.Value);
      LOldProfile.AddPair(LPair.Clone as TJSONPair);
    end;

    Result := LOldProfile.ToJSON;
  finally
    LOldProfile.Free;
  end;
end;

function TTagEngine.DeriveTags(const AContact: TContact;
  const AMetrics: TArray<TInteractionMetric>;
  const AMessages: TArray<TMessageMeta>): TContact;
var
  LTags: TJSONObject;
  LMetric: TInteractionMetric;
  LContentProfile: TJSONObject;
  I: Integer;
begin
  Result := AContact;

  // Find metric for this contact
  LMetric := Default(TInteractionMetric);
  for I := 0 to Length(AMetrics) - 1 do
    if AMetrics[I].ContactId = AContact.ContactId then
    begin
      LMetric := AMetrics[I];
      Break;
    end;

  // Build tag JSON
  LTags := TJSONObject.Create;
  try
    LTags.AddPair('identity', DeriveIdentity(AContact));
    LTags.AddPair('interaction_state', DeriveInteractionState(LMetric));
    LTags.AddPair('channel', DeriveChannel(AContact));
    LTags.AddPair('key_dates', DeriveKeyDates(AContact));
    LTags.AddPair('idle_judge', DeriveIdleJudge(AContact));

    // Content-based tags from message analysis
    if Length(AMessages) > 0 then
    begin
      LContentProfile := DeriveContentProfile(AMessages);
      LTags.AddPair('content_profile', LContentProfile);
    end
    else
      LTags.AddPair('content_profile', TJSONObject.Create);

    LTags.AddPair('product_associations', TJSONArray.Create); // P0: empty
    LTags.AddPair('updated_at', DateToISO8601(Now));

    Result.TagProfile := MergeProfile(AContact.TagProfile, LTags);
  finally
    LTags.Free;
  end;
end;

function TTagEngine.DeriveTagsBatch(const AContacts: TArray<TContact>;
  const AMetrics: TArray<TInteractionMetric>;
  const AMessagesByContact: TDictionary<string, TArray<TMessageMeta>>): TArray<TContact>;
var
  I: Integer;
  LContactMessages: TArray<TMessageMeta>;
begin
  SetLength(Result, Length(AContacts));
  for I := 0 to Length(AContacts) - 1 do
  begin
    LContactMessages := nil;
    if (AMessagesByContact <> nil) then
      AMessagesByContact.TryGetValue(AContacts[I].ContactId, LContactMessages);
    Result[I] := DeriveTags(AContacts[I], AMetrics, LContactMessages);
  end;
end;

function TTagEngine.DeriveContentProfile(const AMessages: TArray<TMessageMeta>): TJSONObject;
var
  LMsg: TMessageMeta;
  LParsed: TParsedMessage;
  LTextCount, LLinkCount, LImageCount, LVideoCount, LVoiceCount: Integer;
  LSystemCount, LOtherCount: Integer;
  LTotalChars: Int64;
  LHasMarketing: Boolean;
  LHasProduct: Boolean;
  LLinkDomains: TDictionary<string, Integer>;
  LDomain: string;
  LCount: Integer;
  LTopDomains: TJSONArray;
  LDomainPairs: TArray<TPair<string, Integer>>;
  LKvp: TPair<string, Integer>;
  I, LIdx: Integer;
begin
  Result := TJSONObject.Create;

  // Count message types and analyze content
  LTextCount := 0;
  LLinkCount := 0;
  LImageCount := 0;
  LVideoCount := 0;
  LVoiceCount := 0;
  LSystemCount := 0;
  LOtherCount := 0;
  LTotalChars := 0;
  LHasMarketing := False;
  LHasProduct := False;
  LLinkDomains := TDictionary<string, Integer>.Create;

  try
    for LMsg in AMessages do
    begin
      LParsed := TMessageParser.Parse(LMsg);

      case LParsed.ContentType of
        pctText:
        begin
          Inc(LTextCount);
          LTotalChars := LTotalChars + Length(LParsed.TextBody);
          // Detect marketing keywords
          if LParsed.TextBody.Contains('优惠') or LParsed.TextBody.Contains('折扣') or
             LParsed.TextBody.Contains('红包') or LParsed.TextBody.Contains('活动') or
             LParsed.TextBody.Contains('促销') then
            LHasMarketing := True;
          // Detect product mentions (simple heuristic)
          if LParsed.TextBody.Contains('产品') or LParsed.TextBody.Contains('商品') or
             LParsed.TextBody.Contains('下单') or LParsed.TextBody.Contains('购买') then
            LHasProduct := True;
        end;

        pctLink:
        begin
          Inc(LLinkCount);
          // Extract domain from URL
          if LParsed.Link.Url <> '' then
          begin
            LDomain := LParsed.Link.Url;
            // Extract domain (simple: after ://)
            if LDomain.Contains('://') then
            begin
              LDomain := Copy(LDomain, Pos('://', LDomain) + 3, Length(LDomain));
              if LDomain.Contains('/') then
                LDomain := Copy(LDomain, 1, Pos('/', LDomain) - 1);
              if LLinkDomains.ContainsKey(LDomain) then
              begin
                LCount := LLinkDomains[LDomain];
                LLinkDomains[LDomain] := LCount + 1;
              end
              else
                LLinkDomains.Add(LDomain, 1);
            end;
          end;
        end;

        pctImage: Inc(LImageCount);
        pctVideo: Inc(LVideoCount);
        pctVoice: Inc(LVoiceCount);
        pctSystem: Inc(LSystemCount);
        pctEmoji, pctNone, pctUnknown: Inc(LOtherCount);
      end;
    end;

    // Build result JSON
    Result.AddPair('text_count', LTextCount);
    Result.AddPair('link_count', LLinkCount);
    Result.AddPair('image_count', LImageCount);
    Result.AddPair('video_count', LVideoCount);
    Result.AddPair('voice_count', LVoiceCount);
    Result.AddPair('system_count', LSystemCount);
    Result.AddPair('other_count', LOtherCount);
    Result.AddPair('total_chars', LTotalChars);

    if LTextCount > 0 then
      Result.AddPair('avg_chars', Round(LTotalChars / LTextCount))
    else
      Result.AddPair('avg_chars', 0);

    Result.AddPair('has_marketing', LHasMarketing);
    Result.AddPair('has_product', LHasProduct);

    // Top link domains (top 3, sorted by frequency descending)
    SetLength(LDomainPairs, LLinkDomains.Count);
    LIdx := 0;
    for LKvp in LLinkDomains do
    begin
      LDomainPairs[LIdx] := LKvp;
      Inc(LIdx);
    end;
    TArray.Sort<TPair<string, Integer>>(LDomainPairs,
      TComparer<TPair<string, Integer>>.Construct(
        function(const A, B: TPair<string, Integer>): Integer
        begin
          // Sort descending by count
          if A.Value > B.Value then Result := -1
          else if A.Value < B.Value then Result := 1
          else Result := 0;
        end));
    LTopDomains := TJSONArray.Create;
    for I := 0 to Length(LDomainPairs) - 1 do
    begin
      if I >= 3 then Break;
      LTopDomains.Add(LDomainPairs[I].Key);
    end;
    Result.AddPair('top_domains', LTopDomains);
  finally
    LLinkDomains.Free;
  end;
end;

end.
