unit ArtifactOS.Services.FeedbackEvolution;

// L4-76/77/78/79: Feedback evolution services
// L4-76: Calibration delta ledger - track prediction vs actual
// L4-77: StrategyChangeProposal auto-generation
// L4-78: Algorithm noise overload detection (grey light)
// L4-79: Feedback scope annotation

interface

uses
  System.SysUtils, System.JSON, System.StrUtils,
  ArtifactOS.Core.DB.Connection;

type
  TDeltaDimension = (ddReading, ddInteraction, ddConversion, ddNegativeFeedback, ddTheoryRisk, ddOverall);
  TFeedbackScope = (fsArticle, fsStrategyUnit, fsAccount, fsPlatform, fsTheory);

  TFeedbackEvolution = class
  public
    // L4-76: Record a calibration ledger entry
    class function RecordCalibration(const AArtifactId, ATraceId, AObsId: string;
      ADimension: TDeltaDimension; AExpected, AActual: Double;
      out ALedgerId: string): Boolean;

    // L4-76: Get calibration summary for a strategy unit
    class function GetCalibrationSummary(const AArtifactId: string): string;

    // L4-77: Auto-generate StrategyChangeProposal if consecutive misses >= 3
    class function CheckAndGenerateProposal(const AArtifactId: string;
      out AProposalId: string): Boolean;

    // L4-77: Create a StrategyChangeProposal explicitly
    class function CreateProposal(const ATriggerType, ATitle, ABody: string;
      const AChanges: string; ARiskLevel: string;
      out AProposalId: string): Boolean;

    // L4-78: Detect algorithm noise overload
    // Returns true if grey light conditions detected
    class function DetectAlgorithmNoise(const AArtifactId, APlatform: string;
      out ANoiseScore: Double; out AAlertId: string): Boolean;

    // L4-79: Annotate feedback scope on a calibration entry or proposal
    class function AnnotateFeedbackScope(const ATargetType, ATargetId: string;
      AScope: TFeedbackScope; const AJustification: string): Boolean;

    // Helpers
    class function DimensionToStr(ADim: TDeltaDimension): string;
    class function ScopeToStr(AScope: TFeedbackScope): string;
  end;

implementation

uses
  System.Math,
  ArtifactOS.Services.CognitiveGovernance;

{ TFeedbackEvolution }

class function TFeedbackEvolution.DimensionToStr(ADim: TDeltaDimension): string;
begin
  case ADim of
    ddReading:          Result := 'reading';
    ddInteraction:      Result := 'interaction';
    ddConversion:       Result := 'conversion';
    ddNegativeFeedback: Result := 'negative_feedback';
    ddTheoryRisk:       Result := 'theory_risk';
    ddOverall:          Result := 'overall';
  else Result := 'overall';
  end;
end;

class function TFeedbackEvolution.ScopeToStr(AScope: TFeedbackScope): string;
begin
  case AScope of
    fsArticle:      Result := 'article';
    fsStrategyUnit: Result := 'strategy_unit';
    fsAccount:      Result := 'account';
    fsPlatform:     Result := 'platform';
    fsTheory:       Result := 'theory';
  else Result := 'article';
  end;
end;

class function TFeedbackEvolution.RecordCalibration(const AArtifactId, ATraceId, AObsId: string;
  ADimension: TDeltaDimension; AExpected, AActual: Double;
  out ALedgerId: string): Boolean;
var
  DB: TArtifactDB;
  Delta: Double;
  IsMiss: Boolean;
  Severity: string;
  MissCount: Integer;
begin
  Result := False;
  ALedgerId := '';

  Delta := Abs(AExpected - AActual);
  IsMiss := Delta > 0.25;

  // Determine severity
  if Delta > 0.75 then Severity := 'critical'
  else if Delta > 0.5 then Severity := 'high'
  else if Delta > 0.25 then Severity := 'medium'
  else Severity := 'low';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Get running consecutive miss count for this artifact + dimension
    var LastMiss := DB.ExecuteScalar(
      'SELECT consecutive_miss_count FROM artifactos.calibration_ledger ' +
      'WHERE artifact_id=''' + AArtifactId + ''' AND delta_dimension=''' + DimensionToStr(ADimension) + ''' ' +
      'ORDER BY observed_at DESC LIMIT 1');
    MissCount := StrToIntDef(LastMiss, 0);
    if IsMiss then
      Inc(MissCount)
    else
      MissCount := 0;

    var TraceRef: string;
    if ATraceId <> '' then TraceRef := '''' + ATraceId + '''' else TraceRef := 'NULL';
    var ObsRef: string;
    if AObsId <> '' then ObsRef := '''' + AObsId + '''' else ObsRef := 'NULL';
    var IsMissStr: string;
    if IsMiss then IsMissStr := 'true' else IsMissStr := 'false';

    ALedgerId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.calibration_ledger ' +
      '  (artifact_id, cognition_trace_id, performance_observation_id, delta_dimension, ' +
      '   expected_value, actual_value, calibration_delta, delta_threshold, is_miss, severity, ' +
      '   consecutive_miss_count) ' +
      'VALUES (''' + AArtifactId + ''', ' + TraceRef + ', ' + ObsRef + ', ' +
      '  ''' + DimensionToStr(ADimension) + ''', ' +
      '  ' + FloatToStr(AExpected, TFormatSettings.Create('en-US')) + ', ' +
      '  ' + FloatToStr(AActual, TFormatSettings.Create('en-US')) + ', ' +
      '  ' + FloatToStr(Delta, TFormatSettings.Create('en-US')) + ', ' +
      '  0.25, ' +
      '  ' + IsMissStr + ', ' +
      '  ''' + Severity + ''', ' +
      '  ' + IntToStr(MissCount) + ') ' +
      'RETURNING id::text');

    var MissLabel: string;
    if IsMiss then MissLabel := 'Y' else MissLabel := 'N';
    WriteLn(Format('[CalibrationLedger] id=%s dim=%s expected=%.3f actual=%.3f delta=%.3f miss=%s count=%d',
      [ALedgerId, DimensionToStr(ADimension), AExpected, AActual, Delta, MissLabel, MissCount]));

    // Auto-file disturbance if severity >= medium
    if (Severity = 'high') or (Severity = 'critical') then
    begin
      var EventId: string;
      TCognitiveGovernance.RecordDisturbance(AArtifactId, ATraceId,
        'calibration_drift', Severity,
        '{"delta":' + FloatToStr(Delta, TFormatSettings.Create('en-US')) + ',"dimension":"' + DimensionToStr(ADimension) + '"}',
        EventId);

      // Mark ledger entry as disturbance filed
      DB.ExecuteJson(
        'UPDATE artifactos.calibration_ledger SET resolution_status=''disturbance_filed'' WHERE id=:id',
        '{"id":"' + ALedgerId + '"}');
    end;

    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TFeedbackEvolution.GetCalibrationSummary(const AArtifactId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalarJson(
      'SELECT json_build_object(' +
      '  ''total_entries'', COUNT(*), ' +
      '  ''misses'', COUNT(*) FILTER (WHERE is_miss), ' +
      '  ''avg_delta'', ROUND(AVG(calibration_delta)::numeric, 4), ' +
      '  ''max_consecutive_miss'', MAX(consecutive_miss_count), ' +
      '  ''by_dimension'', json_object_agg(' +
      '    delta_dimension, ' +
      '    json_build_object(''avg_delta'', ROUND(AVG(calibration_delta)::numeric, 4), ''misses'', COUNT(*) FILTER (WHERE is_miss))' +
      '  ) ' +
      ')::text ' +
      'FROM artifactos.calibration_ledger WHERE artifact_id=:aid::uuid',
      '{"aid":"' + AArtifactId + '"}');
  finally
    DB.Disconnect;
  end;
end;

class function TFeedbackEvolution.CheckAndGenerateProposal(const AArtifactId: string;
  out AProposalId: string): Boolean;
var
  DB: TArtifactDB;
  MissCount: Integer;
begin
  Result := False;
  AProposalId := '';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Check if consecutive misses >= 3 for any dimension
    var DimInfo := DB.ExecuteScalarJson(
      'SELECT delta_dimension, MAX(consecutive_miss_count) as max_miss ' +
      'FROM artifactos.calibration_ledger ' +
      'WHERE artifact_id=:aid::uuid AND is_miss = true ' +
      'GROUP BY delta_dimension ' +
      'HAVING MAX(consecutive_miss_count) >= 3 ' +
      'ORDER BY MAX(consecutive_miss_count) DESC LIMIT 1',
      '{"aid":"' + AArtifactId + '"}');

    if DimInfo = '' then Exit;

    var JObj := TJSONObject.ParseJSONValue(DimInfo) as TJSONObject;
    var Dim, MaxMissStr: string;
    if JObj <> nil then
    try
      Dim := JObj.GetValue<string>('delta_dimension', 'overall');
      MaxMissStr := JObj.GetValue<string>('max_miss', '0');
    finally
      JObj.Free;
    end
    else Exit;

    MissCount := StrToIntDef(MaxMissStr, 0);
    if MissCount < 3 then Exit;

    // Generate proposal
    AProposalId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.strategy_change_proposal ' +
      '  (trigger_type, proposal_title, proposal_body, proposed_changes, risk_level, ' +
      '   auto_tune_eligible, requires_human_confirmation) ' +
      'VALUES (''consecutive_calibration_miss'', ' +
      '  ''Consecutive calibration miss on ' + Dim + ''', ' +
      '  ''Artifact ' + AArtifactId + ' has ' + IntToStr(MissCount) + ' consecutive calibration misses on ' + Dim + '. ' +
      'A strategy change proposal should be reviewed.'', ' +
      '  ''{"dimension":"' + Dim + '","consecutive_misses":' + IntToStr(MissCount) + ',"artifact_id":"' + AArtifactId + '"}''::jsonb, ' +
      '  ''medium'', false, true) ' +
      'RETURNING id::text');

    WriteLn(Format('[FeedbackEvolution] Proposal generated: id=%s dim=%s misses=%d',
      [AProposalId, Dim, MissCount]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TFeedbackEvolution.CreateProposal(const ATriggerType, ATitle, ABody: string;
  const AChanges: string; ARiskLevel: string;
  out AProposalId: string): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    AProposalId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.strategy_change_proposal ' +
      '  (trigger_type, proposal_title, proposal_body, proposed_changes, risk_level, ' +
      '   auto_tune_eligible, requires_human_confirmation) ' +
      'VALUES (''' + ATriggerType + ''', ' +
      '  $title$' + ATitle + '$title$, ' +
      '  $body$' + ABody + '$body$, ' +
      '  $changes$' + AChanges + '$changes$::jsonb, ' +
      '  ''' + ARiskLevel + ''', ' +
      '  ' + IfThen(ARiskLevel = 'low', 'true', 'false') + ', ' +
      '  ' + IfThen(ARiskLevel = 'low', 'false', 'true') + ') ' +
      'RETURNING id::text');

    WriteLn('[FeedbackEvolution] Proposal created: ', AProposalId);
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TFeedbackEvolution.DetectAlgorithmNoise(const AArtifactId, APlatform: string;
  out ANoiseScore: Double; out AAlertId: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  ANoiseScore := 0;
  AAlertId := '';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Check for algorithm noise indicators:
    // 1. Internal quality high but external performance low
    // 2. Sudden performance drop without content change
    // 3. Platform-specific anomaly patterns

    // Get internal quality score
    var QualityScore := DB.ExecuteScalar(
      'SELECT COALESCE(MAX(es_score), 0) FROM artifactos.quality_snapshot ' +
      'WHERE artifact_id=''' + AArtifactId + '''');

    // Get external performance
    var PerfJson := DB.ExecuteScalarJson(
      'SELECT views, engagement_rate FROM artifactos.performance_observation ' +
      'WHERE artifact_id=:aid::uuid AND platform=:platform ' +
      'ORDER BY observed_at DESC LIMIT 1',
      Format('{"aid":"%s","platform":"%s"}', [AArtifactId, APlatform]));

    var Views: Integer := 0;
    var EngRate: Double := 0;
    if PerfJson <> '' then
    begin
      var JObj := TJSONObject.ParseJSONValue(PerfJson) as TJSONObject;
      if JObj <> nil then
      try
        Views := JObj.GetValue<Integer>('views', 0);
        EngRate := JObj.GetValue<Double>('engagement_rate', 0);
      finally
        JObj.Free;
      end;
    end;

    var QualityVal := StrToFloatDef(QualityScore, 0);

    // Noise score: high quality + low performance = noise
    // Normalize quality to 0-1 range (assuming quality is 0-100)
    var NormalizedQuality := QualityVal / 100;

    // Algorithm noise formula: quality is high (>0.7) but engagement is low (<0.05)
    if (NormalizedQuality > 0.7) and (EngRate < 0.05) and (Views > 100) then
    begin
      ANoiseScore := NormalizedQuality * (1 - EngRate);

      if ANoiseScore > 0.5 then
      begin
        // Create grey light alert
        AAlertId := DB.InsertAndReturnId(
          'INSERT INTO artifactos.field_state_alert ' +
          '  (artifact_id, alert_code, alert_light, blocks_auto_adjustment, details) ' +
          'VALUES (''' + AArtifactId + ''', ''algorithm_noise_overload'', ''gray'', true, ' +
          '  ''{"noise_score":' + FloatToStr(ANoiseScore, TFormatSettings.Create('en-US')) +
          '  ,"quality":' + FloatToStr(NormalizedQuality, TFormatSettings.Create('en-US')) +
          '  ,"engagement":' + FloatToStr(EngRate, TFormatSettings.Create('en-US')) +
          '  ,"platform":"' + APlatform + '"}''::jsonb) ' +
          'RETURNING id::text');

        // Record disturbance
        var EventId: string;
        TCognitiveGovernance.RecordDisturbance(AArtifactId, '',
          'platform_negative', 'medium',
          '{"noise_score":' + FloatToStr(ANoiseScore, TFormatSettings.Create('en-US')) +
          ',"platform":"' + APlatform + '"}',
          EventId);

        WriteLn(Format('[NoiseDetector] Grey light: score=%.3f platform=%s artifact=%s',
          [ANoiseScore, APlatform, AArtifactId]));
        Result := True;
      end;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TFeedbackEvolution.AnnotateFeedbackScope(const ATargetType, ATargetId: string;
  AScope: TFeedbackScope; const AJustification: string): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Update the target entity with feedback scope annotation
    if ATargetType = 'calibration_ledger' then
    begin
      DB.ExecuteJson(
        'UPDATE artifactos.calibration_ledger SET ' +
        '  metadata = jsonb_set(COALESCE(metadata, ''{}''::jsonb), ' +
        '    ''{feedback_scope}'', ' +
        '    ''{"scope":"' + ScopeToStr(AScope) + '","justification":"' + Copy(AJustification, 1, 200) + '"}'') ' +
        'WHERE id=:id',
        '{"id":"' + ATargetId + '"}');
    end
    else if ATargetType = 'strategy_change_proposal' then
    begin
      DB.ExecuteJson(
        'UPDATE artifactos.strategy_change_proposal SET ' +
        '  proposed_changes = jsonb_set(COALESCE(proposed_changes, ''{}''::jsonb), ' +
        '    ''{feedback_scope}'', ' +
        '    ''{"scope":"' + ScopeToStr(AScope) + '","justification":"' + Copy(AJustification, 1, 200) + '"}'') ' +
        'WHERE id=:id',
        '{"id":"' + ATargetId + '"}');
    end;

    WriteLn(Format('[FeedbackScope] Annotated %s %s: scope=%s', [ATargetType, ATargetId, ScopeToStr(AScope)]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

end.
