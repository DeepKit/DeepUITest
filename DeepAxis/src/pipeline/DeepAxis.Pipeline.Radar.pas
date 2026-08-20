unit DeepAxis.Pipeline.Radar;

interface

uses
  System.SysUtils, System.DateUtils, System.Math, System.Classes, System.JSON,
  Winapi.Windows,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Core.DataStore,
  DeepAxis.Core.Config;

type
  /// <summary>
  ///   Generates radar hints from interaction metrics.
  ///   P0: 5 hint types — COOLING, LONG_SILENCE, REACTIVATED, OUTBOUND_HEAVY, DATA_INSUFFICIENT.
  ///   Each hint includes confidence, thresholds used, uncertainty, prediction.
  /// </summary>
  TRadarEngine = class(TInterfacedObject, IRadarEngine)
  private
    FRadarHintStore: IRadarHintStore;
    FUseDB1Store: Boolean;
    FConfig: TDeepAxisConfig;
    
    // Threshold values (loaded from ConfigDB at runtime)
    FCoolingDays: Integer;
    FLongSilenceDays: Integer;
    FReactivatedDays: Integer;
    FOutboundHeavyRatio: Double;
    FMinMessagesForMetric: Integer;
    
    procedure LoadThresholdsFromConfig;
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
    procedure PersistRadarHint(const AHint: TRadarHint);
    function GenerateUUID: string;
    function BuildThresholdsJSON(const AThresholds: array of string;
      const AValues: array of Double): string;
  public
    constructor Create(AUseDB1Store: Boolean = True; ARadarHintStore: IRadarHintStore = nil); reintroduce; overload;
    constructor Create; reintroduce; overload;
    
    function Generate(const AMetrics: TArray<TInteractionMetric>;
      const AContacts: TArray<TContact>;
      const AOldMetrics: TArray<TInteractionMetric>): TArray<TRadarHint>;
  end;

implementation

{ TRadarEngine }

constructor TRadarEngine.Create;
begin
  Self.Create(True, nil);
end;

constructor TRadarEngine.Create(AUseDB1Store: Boolean; ARadarHintStore: IRadarHintStore);
begin
  inherited Create;
  FUseDB1Store := AUseDB1Store;
  FRadarHintStore := ARadarHintStore;
  
  // Load thresholds from Config (with fallback defaults)
  LoadThresholdsFromConfig;
end;

procedure TRadarEngine.LoadThresholdsFromConfig;
var
  LValue: string;
begin
  // Load thresholds from Config via GetCapability/SetCapability
  try
    LValue := TDeepAxisConfig.GetCapability('radar.cooling_days_threshold');
    if LValue = '' then LValue := IntToStr(RADAR_COOLING_DAYS_DEFAULT);
    FCoolingDays := StrToIntDef(LValue, RADAR_COOLING_DAYS_DEFAULT);
    
    LValue := TDeepAxisConfig.GetCapability('radar.long_silence_days_threshold');
    if LValue = '' then LValue := IntToStr(RADAR_LONG_SILENCE_DAYS_DEFAULT);
    FLongSilenceDays := StrToIntDef(LValue, RADAR_LONG_SILENCE_DAYS_DEFAULT);
    
    LValue := TDeepAxisConfig.GetCapability('radar.reactivated_days_threshold');
    if LValue = '' then LValue := IntToStr(RADAR_REACTIVATED_DAYS_DEFAULT);
    FReactivatedDays := StrToIntDef(LValue, RADAR_REACTIVATED_DAYS_DEFAULT);
    
    LValue := TDeepAxisConfig.GetCapability('radar.outbound_heavy_ratio_threshold');
    if LValue = '' then LValue := FloatToStr(RADAR_OUTBOUND_HEAVY_RATIO_DEFAULT);
    FOutboundHeavyRatio := StrToFloatDef(LValue, RADAR_OUTBOUND_HEAVY_RATIO_DEFAULT);
    
    LValue := TDeepAxisConfig.GetCapability('radar.min_messages_for_metric');
    if LValue = '' then LValue := IntToStr(RADAR_MIN_MESSAGES_FOR_METRIC_DEFAULT);
    FMinMessagesForMetric := StrToIntDef(LValue, RADAR_MIN_MESSAGES_FOR_METRIC_DEFAULT);
  except
    on E: Exception do
    begin
      WriteLn('[Radar] Warning: Could not load thresholds from Config, using defaults');
      
      // Use hardcoded defaults
      FCoolingDays := RADAR_COOLING_DAYS_DEFAULT;
      FLongSilenceDays := RADAR_LONG_SILENCE_DAYS_DEFAULT;
      FReactivatedDays := RADAR_REACTIVATED_DAYS_DEFAULT;
      FOutboundHeavyRatio := RADAR_OUTBOUND_HEAVY_RATIO_DEFAULT;
      FMinMessagesForMetric := RADAR_MIN_MESSAGES_FOR_METRIC_DEFAULT;
    end;
  end;
end;

function TRadarEngine.GenerateUUID: string;
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

procedure TRadarEngine.PersistRadarHint(const AHint: TRadarHint);
begin
  if not (FUseDB1Store and Assigned(FRadarHintStore)) then Exit;
  
  try
    FRadarHintStore.Save(AHint);
  except
    on E: Exception do
      ; // Ignore persistence errors
  end;
end;

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
    // ✅ FIXED: Parameterized thresholds instead of JSON
    Result.CoolingDays := FCoolingDays;
    Result.LongSilenceDays := FLongSilenceDays;
    Result.OutboundHeavyRatio := FOutboundHeavyRatio;
    Result.MinMessagesForMetric := FMinMessagesForMetric;
  end
  else
  begin
    Result.Confidence := 0.3;
    // ✅ FIXED: Parameterized threshold values instead of JSON
    Result.CoolingDays := FCoolingDays;
    Result.LongSilenceDays := FLongSilenceDays;
    Result.OutboundHeavyRatio := FOutboundHeavyRatio;
    Result.MinMessagesForMetric := FMinMessagesForMetric;
  end;

  Result.WindowStart := AOldMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  Result.Uncertainty := Format('降温判定基于 %d 天窗口的互动变化', [DaysBetween(AMetric.WindowEnd, AOldMetric.WindowStart)]);
  Result.Prediction := Format('若不干预，预计 %d 天内继续降温', [FCoolingDays]);
  Result.ExpiresAt := IncDay(Now, FCoolingDays);
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
  Result.Confidence := CalcConfidence(LDaysSince / FLongSilenceDays, AMetric.DataQuality);
  Result.WindowStart := AMetric.LastInteractionAt;
  Result.WindowEnd := Now;
  // ✅ FIXED: Parameterized threshold values instead of JSON
  Result.CoolingDays := FCoolingDays;
  Result.LongSilenceDays := FLongSilenceDays;
  Result.OutboundHeavyRatio := FOutboundHeavyRatio;
  Result.MinMessagesForMetric := FMinMessagesForMetric;
  Result.Uncertainty := Format('最后互动距今 %d 天，超过阈值 %d 天', [LDaysSince, FLongSilenceDays]);
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
  Result.Confidence := CalcConfidence(LDaysSinceOld / FReactivatedDays, AMetric.DataQuality);
  Result.WindowStart := AOldMetric.LastInteractionAt;
  Result.WindowEnd := AMetric.LastInteractionAt;
  // ✅ FIXED: Parameterized threshold values instead of JSON
  Result.CoolingDays := FCoolingDays;
  Result.LongSilenceDays := FLongSilenceDays;
  Result.OutboundHeavyRatio := FOutboundHeavyRatio;
  Result.MinMessagesForMetric := FMinMessagesForMetric;
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

  Result.Confidence := CalcConfidence(LRatio / FOutboundHeavyRatio, AMetric.DataQuality);
  Result.WindowStart := AMetric.WindowStart;
  Result.WindowEnd := AMetric.WindowEnd;
  // ✅ FIXED: Parameterized thresholds
  Result.CoolingDays := FCoolingDays;
  Result.LongSilenceDays := FLongSilenceDays;
  Result.OutboundHeavyRatio := FOutboundHeavyRatio;
  Result.MinMessagesForMetric := FMinMessagesForMetric;
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
  // ✅ FIXED: Parameterized thresholds
  Result.CoolingDays := FCoolingDays;
  Result.LongSilenceDays := FLongSilenceDays;
  Result.OutboundHeavyRatio := FOutboundHeavyRatio;
  Result.MinMessagesForMetric := FMinMessagesForMetric;
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
  // ✅ FIXED: Parameterized thresholds
  Result.CoolingDays := FCoolingDays;
  Result.LongSilenceDays := FLongSilenceDays;
  Result.OutboundHeavyRatio := FOutboundHeavyRatio;
  Result.MinMessagesForMetric := FMinMessagesForMetric;
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
  // ✅ FIXED: Parameterized thresholds
  Result.CoolingDays := FCoolingDays;
  Result.LongSilenceDays := FLongSilenceDays;
  Result.OutboundHeavyRatio := FOutboundHeavyRatio;
  Result.MinMessagesForMetric := FMinMessagesForMetric;
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
      PersistRadarHint(LHint);
      Continue;
    end;

    LDaysSince := 0;
    if LMetric.LastInteractionAt > 0 then
      LDaysSince := DaysBetween(Now, LMetric.LastInteractionAt);

    // REACTIVATED: requires a real historical metric with old interaction
    if (LOldMetric.MetricId <> '') and (LOldMetric.LastInteractionAt > 0) and
       (DaysBetween(Now, LOldMetric.LastInteractionAt) >= FReactivatedDays) and
       (LMetric.InboundCount > 0) and
       (LMetric.LastInteractionAt > LOldMetric.LastInteractionAt) then
    begin
      LHint := ComputeReactivatedHint(LMetric, LOldMetric);
      if LHint.HintId <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LHint;
        PersistRadarHint(LHint);
        Continue;
      end;
    end;

    // LONG_SILENCE: threshold-based silence detection
    if LDaysSince >= FLongSilenceDays then
    begin
      LHint := ComputeLongSilenceHint(LMetric);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LHint;
      PersistRadarHint(LHint);
      Continue;
    end;

    // OUTBOUND_HEAVY: outbound/inbound ratio > threshold
    if (LMetric.OutboundInboundRatio > FOutboundHeavyRatio) and
       (LMetric.OutboundCount > FMinMessagesForMetric) then
    begin
      LHint := ComputeOutboundHeavyHint(LMetric);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LHint;
      PersistRadarHint(LHint);
      Continue;
    end;

    // COOLING: interaction dropping (requires historical metric)
    if (LOldMetric.MetricId <> '') and (LDaysSince >= FCoolingDays) then
    begin
      LHint := ComputeCoolingHint(LMetric, LOldMetric);
      // Check if drop is significant
      if LHint.Confidence > 0.3 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LHint;
        PersistRadarHint(LHint);
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
        PersistRadarHint(LHint);
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
        PersistRadarHint(LHint);
      end;
    end;
  end;
end;

end.
