unit DeepAxis.Pipeline.Metrics;

interface

uses
  System.SysUtils, System.DateUtils, System.Math,
  System.Generics.Collections, System.Generics.Defaults,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.WeChat.MsgParser;

type
  /// <summary>
  ///   Computes interaction metrics from message metadata.
  ///   P0: Pure metadata analysis — no body content accessed.
  /// </summary>
  TMetricCalculator = class(TInterfacedObject, IMetricCalculator)
  public
    function Compute(const AMessages: TArray<TMessageMeta>;
      const AOldMetric: TInteractionMetric): TInteractionMetric;
    function ComputeBatch(const AContacts: TArray<TContact>;
      const AMessagesByContact: TArray<TMessageMeta>;
      const AOldMetrics: TArray<TInteractionMetric>): TArray<TInteractionMetric>;
  end;

implementation

{ TMetricCalculator }

function TMetricCalculator.Compute(const AMessages: TArray<TMessageMeta>;
  const AOldMetric: TInteractionMetric): TInteractionMetric;
var
  LMsg: TMessageMeta;
  LInboundCount, LOutboundCount: Integer;
  LLastInteraction: TDateTime;
  LInboundTimes: TArray<TDateTime>;
  LOutboundTimes: TArray<TDateTime>;
  LTotalDelay: Double;
  LDelayCount: Integer;
  I, J: Integer;
  LDelay: Double;
  LWindowStart, LWindowEnd: TDateTime;
  LContactId, LConversationId: string;
  // Content-based metrics
  LLinkCount, LMediaCount: Integer;
  LTotalTextLen: Int64;
  LTextCount: Integer;
  LHasMarketing: Boolean;
  LParsed: TParsedMessage;
  LSorted: TArray<TMessageMeta>;
begin
  Result := Default(TInteractionMetric);

  // BodyQueried is now allowed (user command override)

  if Length(AMessages) = 0 then
  begin
    // Carry forward old metric but mark as potentially stale
    if AOldMetric.MetricId <> '' then
    begin
      Result := AOldMetric;
      // If last interaction was long ago, degrade quality
      if (AOldMetric.LastInteractionAt > 0) and
         (DaysBetween(Now, AOldMetric.LastInteractionAt) > LONG_SILENCE_DAYS) then
        Result.DataQuality := dqDataInsufficient;
    end
    else
    begin
      Result.MetricId := GenerateId;
      Result.DataQuality := dqDataInsufficient;
      Result.ComputedAt := Now;
    end;
    Exit;
  end;

  // 按 SentAt 排序，确保跨 DB 合并后窗口边界正确
  LSorted := Copy(AMessages);
  TArray.Sort<TMessageMeta>(LSorted, TComparer<TMessageMeta>.Construct(
    function(const A, B: TMessageMeta): Integer
    begin
      if A.SentAt < B.SentAt then Result := -1
      else if A.SentAt > B.SentAt then Result := 1
      else Result := 0;
    end));

  // Count inbound/outbound, track timestamps, analyze content
  LInboundCount := 0;
  LOutboundCount := 0;
  LLastInteraction := 0;
  LWindowStart := 0;
  LWindowEnd := 0;
  LContactId := LSorted[0].ContactId;
  LConversationId := LSorted[0].ConversationId;
  SetLength(LInboundTimes, 0);
  SetLength(LOutboundTimes, 0);

  // Content-based metrics
  LLinkCount := 0;
  LMediaCount := 0;
  LTotalTextLen := 0;
  LTextCount := 0;
  LHasMarketing := False;

  for LMsg in LSorted do
  begin
    if (LContactId <> '') and (LMsg.ContactId <> LContactId) then
      LContactId := '';
    if (LConversationId <> '') and (LMsg.ConversationId <> LConversationId) then
      LConversationId := '';

    if LMsg.SentAt = 0 then
      Continue;

    if (LWindowStart = 0) or (LMsg.SentAt < LWindowStart) then
      LWindowStart := LMsg.SentAt;
    if LMsg.SentAt > LWindowEnd then
      LWindowEnd := LMsg.SentAt;

    if LMsg.Direction = dInbound then
    begin
      Inc(LInboundCount);
      SetLength(LInboundTimes, Length(LInboundTimes) + 1);
      LInboundTimes[High(LInboundTimes)] := LMsg.SentAt;
    end
    else if LMsg.Direction = dOutbound then
    begin
      Inc(LOutboundCount);
      SetLength(LOutboundTimes, Length(LOutboundTimes) + 1);
      LOutboundTimes[High(LOutboundTimes)] := LMsg.SentAt;
    end;

    if LMsg.SentAt > LLastInteraction then
      LLastInteraction := LMsg.SentAt;

    // Content analysis
    LParsed := TMessageParser.Parse(LMsg);
    case LParsed.ContentType of
      pctLink: Inc(LLinkCount);
      pctImage, pctVideo, pctVoice: Inc(LMediaCount);
      pctText:
      begin
        Inc(LTextCount);
        LTotalTextLen := LTotalTextLen + Length(LParsed.TextBody);
        // Detect marketing keywords
        if LParsed.TextBody.Contains('优惠') or LParsed.TextBody.Contains('折扣') or
           LParsed.TextBody.Contains('红包') or LParsed.TextBody.Contains('活动') or
           LParsed.TextBody.Contains('促销') or LParsed.TextBody.Contains('下单') or
           LParsed.TextBody.Contains('购买') then
          LHasMarketing := True;
      end;
    end;
  end;

  // Response delay trend: for each outbound, find next inbound, measure delay
  LTotalDelay := 0;
  LDelayCount := 0;
  for I := 0 to Length(LOutboundTimes) - 1 do
  begin
    for J := 0 to Length(LInboundTimes) - 1 do
    begin
      if LInboundTimes[J] > LOutboundTimes[I] then
      begin
        LDelay := SecondsBetween(LInboundTimes[J], LOutboundTimes[I]);
        LTotalDelay := LTotalDelay + LDelay;
        Inc(LDelayCount);
        Break;
      end;
    end;
  end;

  // Build result
  Result.MetricId := GenerateId;
  if AOldMetric.MetricId <> '' then
    Result.MetricId := AOldMetric.MetricId; // keep same ID for updates

  Result.WindowStart := LWindowStart;
  Result.WindowEnd := LWindowEnd;
  Result.ContactId := LContactId;
  Result.ConversationId := LConversationId;
  Result.SourceAccountId := LSorted[0].SourceAccountId;
  Result.LastInteractionAt := LLastInteraction;
  Result.InboundCount := LInboundCount;
  Result.OutboundCount := LOutboundCount;

  // Content-based metrics
  Result.LinkCount := LLinkCount;
  Result.MediaCount := LMediaCount;
  if LTextCount > 0 then
    Result.AvgTextLength := Round(LTotalTextLen / LTextCount)
  else
    Result.AvgTextLength := 0;
  Result.HasMarketingKeywords := LHasMarketing;

  if LDelayCount > 0 then
    Result.ResponseDelayTrend := LTotalDelay / LDelayCount
  else if AOldMetric.ResponseDelayTrend <> 0 then
    Result.ResponseDelayTrend := AOldMetric.ResponseDelayTrend
  else
    Result.ResponseDelayTrend := -1; // 无数据标记 (负值表示无数据)

  if LInboundCount > 0 then
    Result.OutboundInboundRatio := LOutboundCount / LInboundCount
  else
    Result.OutboundInboundRatio := -1; // no inbound data

  // Data quality
  if (LInboundCount + LOutboundCount) < MIN_MESSAGES_FOR_METRIC then
    Result.DataQuality := dqDataInsufficient
  else if (LInboundCount + LOutboundCount) < MIN_MESSAGES_FOR_OK then
    Result.DataQuality := dqPartial
  else
    Result.DataQuality := dqOK;

  Result.ComputedAt := Now;
end;

function TMetricCalculator.ComputeBatch(const AContacts: TArray<TContact>;
  const AMessagesByContact: TArray<TMessageMeta>;
  const AOldMetrics: TArray<TInteractionMetric>): TArray<TInteractionMetric>;
var
  LContact: TContact;
  LMsg: TMessageMeta;
  LOldMetric: TInteractionMetric;
  LMsgDict: TDictionary<string, TList<TMessageMeta>>;
  LOldDict: TDictionary<string, TInteractionMetric>;
  LMsgList: TList<TMessageMeta>;
  LContactMessages: TArray<TMessageMeta>;
  I: Integer;
begin
  Result := nil;

  // Pre-group messages by ContactId: O(M) instead of O(N*M)
  LMsgDict := TDictionary<string, TList<TMessageMeta>>.Create;
  try
    for LMsg in AMessagesByContact do
    begin
      if not LMsgDict.TryGetValue(LMsg.ContactId, LMsgList) then
      begin
        LMsgList := TList<TMessageMeta>.Create;
        LMsgDict.Add(LMsg.ContactId, LMsgList);
      end;
      LMsgList.Add(LMsg);
    end;

    // Pre-index old metrics by ContactId: O(K) instead of O(N*K)
    LOldDict := TDictionary<string, TInteractionMetric>.Create;
    try
      for I := 0 to Length(AOldMetrics) - 1 do
        LOldDict.AddOrSetValue(AOldMetrics[I].ContactId, AOldMetrics[I]);

      // For each contact, look up from dictionaries: O(N) total
      SetLength(Result, Length(AContacts));
      for I := 0 to Length(AContacts) - 1 do
      begin
        LContact := AContacts[I];

        // Get messages for this contact
        if LMsgDict.TryGetValue(LContact.ContactId, LMsgList) then
          LContactMessages := LMsgList.ToArray
        else
          LContactMessages := nil;

        // Get old metric for this contact
        if not LOldDict.TryGetValue(LContact.ContactId, LOldMetric) then
          LOldMetric := Default(TInteractionMetric);

        Result[I] := Compute(LContactMessages, LOldMetric);
        Result[I].ContactId := LContact.ContactId;
      end;
    finally
      LOldDict.Free;
    end;
  finally
    // Free all message lists
    for LMsgList in LMsgDict.Values do
      LMsgList.Free;
    LMsgDict.Free;
  end;
end;

end.
