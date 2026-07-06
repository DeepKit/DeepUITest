unit DeepAxis.Pipeline.Radar;

interface

uses
  System.SysUtils, System.DateUtils, System.Math, System.JSON,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts;

type
  /// <summary>
  ///   Generates radar hints from interaction metrics.
  ///   P0: 5 hint types — COOLING, LONG_SILENCE, REACTIVATED, OUTBOUND_HEAVY, DATA_INSUFFICIENT.
  ///   Each hint includes confidence, thresholds used, uncertainty, prediction.
  /// </summary>
  TRadarEngine = class(TInterfacedObject, IRadarEngine)
  private
    function ComputeCoolingHint(const AMetric: TInteractionMetric;
      const AOldMetric: TInteractionMetric): TRadarHint;
    function ComputeLongSilenceHint(const AMetric: TInteractionMetric): TRadarHint;
    function ComputeReactivatedHint(const AMetric: TInteractionMetric;
      const AOldMetric: TInteractionMetric): TRadarHint;
    function ComputeOutboundHeavyHint(const AMetric: TInteractionMetric): TRadarHint;
    function ComputeDataInsufficientHint(const AMetric: TInteractionMetric): TRadarHint;
    function ComputeHighLinkSharingHint(const AMetric: TInteractionMetric): TRadarHint;
    function ComputeMarketingPatternHint(const AMetric: TInteractionMetric): TRadarHint;
    function CalcConfidence(const AExcessRatio: Double; const ADataQuality: TDataQuality): Double;
    function FindOldMetric(const AContactId: string;
      const AOldMetrics: TArray<TInteractionMetric>): TInteractionMetric;
    function BuildThresholdsJSON(const AThresholds: array of string;
      const AValues: array of Double): string;
  public
    function Generate(const AMetrics: TArray<TInteractionMetric>;
      const AContacts: TArray<TContact>;
      const AOldMetrics: TArray<TInteractionMetric>): TArray<TRadarHint>;
  end;

implementation

{ TRadarEngine }

function TRadarEngine.FindOldMetric(const AContactId: string;
  const AOldMetrics: TArray<TInteractionMetric>): TInteractionMetric;
var
  I: Integer;
begin
  for I := 0 to Length(AOldMetrics) - 1 do
    if AOldMetrics[I].ContactId = AContactId then
      Exit(AOldMetrics[I]);
  Result := Default(TInteractionMetric);
end;

function TRadarEngine.CalcConfidence(const AExcessRatio: Double;
  const ADataQuality: TDataQuality): Double;
var
  LBase: Double;
begin
  // Base confidence from how far past threshold
  if AExcessRatio >= 3.0 then
    LBase := 0.95
  else if AExcessRatio >= 2.0 then
    LBase := 0.85
  else if AExcessRatio >= 1.5 then
    LBase := 0.70
  else if AExcessRatio >= 1.2 then
    LBase := 0.55
  else
    LBase := 0.40;

  // Adjust by data quality
  case ADataQuality of
    dqOK:               Result := LBase;
    dqPartial:          Result := LBase * 0.7;
    dqDataInsufficient: Result := LBase * 0.3;
  else
    Result := LBase;
  end;

  Result := Min(1.0, Max(0.1, Result));
end;

function TRadarEngine.BuildThresholdsJSON(const AThresholds: array of string;
  const AValues: array of Double): string;
var
  LObj: TJSONObject;
  I: Integer;
begin
  LObj := TJSONObject.Create;
  try
    for I := 0 to Length(AThresholds) - 1 do
    begin
      if I < Length(AValues) then
        LObj.AddPair(ATHresholds[I], TJSONNumber.Create(AValues[I]));
    end;
    Result := LObj.ToJSON;
  finally
    LObj.Free;
  end;
end;

function TRadarEngine.ComputeCoolingHint(const AMetric: TInteractionMetric;
  const AOldMetric: TInteractionMetric): TRadarHint;
var
  LDropRatio: Double;
begin
  Result := Default(TRadarHint);
  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtCooling;

  // Calculate drop ratio
  if (AOldMetric.InboundCount > 0) and (AMetric.InboundCount > 0) then
  begin
    LDropRatio := AOldMetric.InboundCount / AMetric.InboundCount;
    Result.Confidence := CalcConfidence(LDropRatio, AMetric.DataQuality);
    Result.ThresholdsUsed := BuildThresholdsJSON(
      ['old_inbound', 'new_inbound', 'drop_ratio', 'threshold'],
      [AOldMetric.InboundCount, AMetric.InboundCount, LDropRatio, 2.0]);
  end
  else
  begin
    Result.Confidence := 0.3;
    Result.ThresholdsUsed := '{"reason":"insufficient_history"}';
  end;

  Result.WindowStart := AOldMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  Result.Uncertainty := Format('降温判定基于 %d 天窗口的互动变化', [DaysBetween(AMetric.WindowEnd, AOldMetric.WindowStart)]);
  Result.Prediction := Format('若不干预，预计 %d 天内继续降温', [COOLING_DAYS]);
  Result.ExpiresAt := IncDay(Now, COOLING_DAYS);
  Result.RecommendedIntervention := irReview;
  Result.CreatedAt := Now;
end;

function TRadarEngine.ComputeLongSilenceHint(const AMetric: TInteractionMetric): TRadarHint;
var
  LDaysSince: Integer;
begin
  Result := Default(TRadarHint);
  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtLongSilence;

  LDaysSince := DaysBetween(Now, AMetric.LastInteractionAt);
  Result.Confidence := CalcConfidence(LDaysSince / LONG_SILENCE_DAYS, AMetric.DataQuality);
  Result.WindowStart := AMetric.LastInteractionAt;
  Result.WindowEnd := Now;
  Result.ThresholdsUsed := BuildThresholdsJSON(
    ['days_since_last', 'threshold_days'],
    [LDaysSince, LONG_SILENCE_DAYS]);
  Result.Uncertainty := Format('最后互动距今 %d 天，超过阈值 %d 天', [LDaysSince, LONG_SILENCE_DAYS]);
  Result.Prediction := '若不主动联系，关系可能进一步疏远';
  Result.ExpiresAt := IncDay(Now, 7);
  Result.RecommendedIntervention := irReview;
  Result.CreatedAt := Now;
end;

function TRadarEngine.ComputeReactivatedHint(const AMetric: TInteractionMetric;
  const AOldMetric: TInteractionMetric): TRadarHint;
var
  LDaysSinceOld: Integer;
begin
  Result := Default(TRadarHint);
  if AOldMetric.LastInteractionAt = 0 then Exit;
  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtReactivated;

  LDaysSinceOld := DaysBetween(Now, AOldMetric.LastInteractionAt);
  Result.Confidence := CalcConfidence(LDaysSinceOld / REACTIVATED_DAYS, AMetric.DataQuality);
  Result.WindowStart := AOldMetric.LastInteractionAt;
  Result.WindowEnd := AMetric.LastInteractionAt;
  Result.ThresholdsUsed := BuildThresholdsJSON(
    ['silence_days', 'new_inbound', 'threshold_days'],
    [LDaysSinceOld, AMetric.InboundCount, REACTIVATED_DAYS]);
  Result.Uncertainty := Format('重新活跃的判定：%d 天沉默后出现 %d 条入站消息',
    [LDaysSinceOld, AMetric.InboundCount]);
  Result.Prediction := '可能对新话题产生兴趣，适合跟进';
  Result.ExpiresAt := IncDay(Now, 3);
  Result.RecommendedIntervention := irReview;
  Result.CreatedAt := Now;
end;

function TRadarEngine.ComputeOutboundHeavyHint(const AMetric: TInteractionMetric): TRadarHint;
var
  LRatio: Double;
begin
  Result := Default(TRadarHint);
  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtOutboundHeavy;

  LRatio := AMetric.OutboundInboundRatio;
  if LRatio < 0 then
    LRatio := 999; // no inbound at all

  Result.Confidence := CalcConfidence(LRatio / OUTBOUND_HEAVY_RATIO, AMetric.DataQuality);
  Result.WindowStart := AMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  Result.ThresholdsUsed := BuildThresholdsJSON(
    ['outbound_count', 'inbound_count', 'ratio', 'threshold'],
    [AMetric.OutboundCount, AMetric.InboundCount, LRatio, OUTBOUND_HEAVY_RATIO]);
  Result.Uncertainty := Format('你发了 %d 条，对方回了 %d 条', [AMetric.OutboundCount, AMetric.InboundCount]);
  Result.Prediction := '对方可能已失去兴趣，建议调整沟通策略';
  Result.ExpiresAt := IncDay(Now, 7);
  Result.RecommendedIntervention := irReview;
  Result.CreatedAt := Now;
end;

function TRadarEngine.ComputeDataInsufficientHint(const AMetric: TInteractionMetric): TRadarHint;
begin
  Result := Default(TRadarHint);
  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtDataInsufficient;
  Result.Confidence := 0.1;
  Result.WindowStart := AMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  Result.ThresholdsUsed := Format('{"message_count":%d,"min_required":%d}',
    [AMetric.InboundCount + AMetric.OutboundCount, MIN_MESSAGES_FOR_METRIC]);
  Result.Uncertainty := '数据不足，无法生成有意义的提示';
  Result.Prediction := '等待更多互动数据后重新评估';
  Result.ExpiresAt := IncDay(Now, 14);
  Result.RecommendedIntervention := irNone;
  Result.CreatedAt := Now;
end;

function TRadarEngine.ComputeHighLinkSharingHint(const AMetric: TInteractionMetric): TRadarHint;
const
  LINK_THRESHOLD = 5; // 5+ links in window
var
  LLinkRatio: Double;
begin
  Result := Default(TRadarHint);

  // High link sharing: >5 links or >30% of messages are links
  if AMetric.LinkCount < LINK_THRESHOLD then
    Exit;

  LLinkRatio := 0;
  if (AMetric.InboundCount + AMetric.OutboundCount) > 0 then
    LLinkRatio := AMetric.LinkCount / (AMetric.InboundCount + AMetric.OutboundCount);

  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtHighLinkSharing;
  Result.WindowStart := AMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  Result.ThresholdsUsed := BuildThresholdsJSON(
    ['link_count', 'link_ratio', 'threshold'],
    [AMetric.LinkCount, LLinkRatio, LINK_THRESHOLD]);
  Result.Uncertainty := '基于链接分享频率';
  Result.Prediction := '可能是营销或推广行为';
  Result.RecommendedIntervention := irReview;
  Result.Confidence := CalcConfidence(AMetric.LinkCount / LINK_THRESHOLD, AMetric.DataQuality);
  Result.ExpiresAt := AMetric.WindowEnd + 7;
  Result.CreatedAt := Now;
end;

function TRadarEngine.ComputeMarketingPatternHint(const AMetric: TInteractionMetric): TRadarHint;
begin
  Result := Default(TRadarHint);

  // Marketing pattern: contains marketing keywords
  if not AMetric.HasMarketingKeywords then
    Exit;

  Result.HintId := GenerateId;
  Result.ContactId := AMetric.ContactId;
  Result.SourceAccountId := AMetric.SourceAccountId;
  Result.HintType := rhtMarketingPattern;
  Result.WindowStart := AMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  Result.ThresholdsUsed := BuildThresholdsJSON(
    ['has_marketing', 'avg_text_len'],
    [1.0, AMetric.AvgTextLength]);
  Result.Uncertainty := '基于消息内容关键词检测';
  Result.Prediction := '可能存在营销或推广行为';
  Result.RecommendedIntervention := irReview;
  Result.Confidence := CalcConfidence(1.5, AMetric.DataQuality);
  Result.ExpiresAt := AMetric.WindowEnd + 7;
  Result.CreatedAt := Now;
end;

function TRadarEngine.Generate(const AMetrics: TArray<TInteractionMetric>;
  const AContacts: TArray<TContact>;
  const AOldMetrics: TArray<TInteractionMetric>): TArray<TRadarHint>;
var
  LMetric: TInteractionMetric;
  LOldMetric: TInteractionMetric;
  LContact: TContact;
  LHint: TRadarHint;
  LContactFound: Boolean;
  LDaysSince: Integer;
  I: Integer;
begin
  Result := nil;

  for LMetric in AMetrics do
  begin
    // Skip contacts that are not business
    LContactFound := False;
    for I := 0 to Length(AContacts) - 1 do
      if AContacts[I].ContactId = LMetric.ContactId then
      begin
        LContact := AContacts[I];
        LContactFound := True;
        Break;
      end;

    if LContactFound and (LContact.Privacy in [psPrivate, psUnknown]) then
      Continue;

    LHint := Default(TRadarHint);
    LOldMetric := FindOldMetric(LMetric.ContactId, AOldMetrics);

    // DATA_INSUFFICIENT: not enough messages
    if LMetric.DataQuality = dqDataInsufficient then
    begin
      LHint := ComputeDataInsufficientHint(LMetric);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LHint;
      Continue;
    end;

    LDaysSince := 0;
    if LMetric.LastInteractionAt > 0 then
      LDaysSince := DaysBetween(Now, LMetric.LastInteractionAt);

    // REACTIVATED: requires a real historical metric with old interaction
    if (LOldMetric.MetricId <> '') and (LOldMetric.LastInteractionAt > 0) and
       (DaysBetween(Now, LOldMetric.LastInteractionAt) >= REACTIVATED_DAYS) and
       (LMetric.InboundCount > 0) and
       (LMetric.LastInteractionAt > LOldMetric.LastInteractionAt) then
    begin
      LHint := ComputeReactivatedHint(LMetric, LOldMetric);
      if LHint.HintId <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LHint;
        Continue;
      end;
    end;

    // LONG_SILENCE: > 30 days without interaction
    if LDaysSince >= LONG_SILENCE_DAYS then
    begin
      LHint := ComputeLongSilenceHint(LMetric);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LHint;
      Continue;
    end;

    // OUTBOUND_HEAVY: outbound/inbound ratio > threshold
    if (LMetric.OutboundInboundRatio > OUTBOUND_HEAVY_RATIO) and
       (LMetric.OutboundCount > MIN_MESSAGES_FOR_METRIC) then
    begin
      LHint := ComputeOutboundHeavyHint(LMetric);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LHint;
      Continue;
    end;

    // COOLING: interaction dropping (requires historical metric)
    if (LOldMetric.MetricId <> '') and (LDaysSince >= COOLING_DAYS) then
    begin
      LHint := ComputeCoolingHint(LMetric, LOldMetric);
      // Check if drop is significant
      if LHint.Confidence > 0.3 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LHint;
        Continue;
      end;
    end;

    // Content-based hints (can co-exist with other hints)
    // HIGH_LINK_SHARING: high frequency of link sharing
    if LMetric.LinkCount >= 5 then
    begin
      LHint := ComputeHighLinkSharingHint(LMetric);
      if LHint.HintId <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LHint;
      end;
    end;

    // MARKETING_PATTERN: contains marketing keywords
    if LMetric.HasMarketingKeywords then
    begin
      LHint := ComputeMarketingPatternHint(LMetric);
      if LHint.HintId <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LHint;
      end;
    end;
  end;
end;

end.
