unit ArtifactOS.Services.PerformanceCollector;

// L4-74: Performance data collection and aggregation service.
// Collects post-publish performance data from signal_event,
// aggregates into performance_observation snapshots, and triggers
// calibration updates.

interface

uses
  System.SysUtils, System.JSON, System.DateUtils, System.StrUtils,
  ArtifactOS.Core.DB.Connection;

type
  TPerformanceMetrics = record
    Views: Integer;
    Likes: Integer;
    Favorites: Integer;
    Comments: Integer;
    Shares: Integer;
    Follows: Integer;
    EngagementRate: Double;
    ConversionRate: Double;
  end;

  TPerformanceCollector = class
  public
    /// <summary>
    /// Aggregate signal_event data into a performance_observation snapshot
    /// for the given artifact + platform + time window.
    /// </summary>
    class function CollectObservation(const AArtifactId, AVersionId,
      APackageId, APlatform, AWindow: string;
      out AObsId: string): Boolean;

    /// <summary>
    /// Record a single signal event (view, like, etc.) from external source.
    /// </summary>
    class function RecordSignal(const AArtifactId, ASignalType: string;
      ARawValue: Double; const AChannel: string): Boolean;

    /// <summary>
    /// Get the latest observation for an artifact.
    /// Returns JSON with all metrics.
    /// </summary>
    class function GetLatestObservation(const AArtifactId, APlatform: string): string;

    /// <summary>
    /// Run calibration update: compare prediction vs actual,
    /// update cognition_trace.calibration_delta.
    /// </summary>
    class function UpdateCalibration(const AArtifactId, ACognitionTraceId: string;
      const AActual: TPerformanceMetrics): Boolean;

    /// <summary>
    /// Check if observation triggers a cognitive disturbance
    /// (calibration drift, consecutive miss, etc.)
    /// </summary>
    class function CheckDisturbance(const AArtifactId: string;
      out AEventType, ASeverity: string): Boolean;
  end;

implementation

{ TPerformanceCollector }

class function TPerformanceCollector.RecordSignal(const AArtifactId, ASignalType: string;
  ARawValue: Double; const AChannel: string): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'INSERT INTO artifactos.signal_event (artifact_id, signal_type, raw_value, channel, occurred_at) ' +
      'VALUES (:aid::uuid, :stype, :rval, :chan, now())',
      Format('{"aid":"%s","stype":"%s","rval":%f,"chan":"%s"}',
        [AArtifactId, ASignalType, ARawValue, AChannel]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TPerformanceCollector.CollectObservation(const AArtifactId, AVersionId,
  APackageId, APlatform, AWindow: string;
  out AObsId: string): Boolean;
var
  DB: TArtifactDB;
  Views, Likes, Favs, Comments, Shares, Follows: Integer;
  EngRate, ConvRate: Double;
  WindowInterval: string;
begin
  Result := False;
  AObsId := '';

  // Map window name to PG interval
  if AWindow = '24h' then WindowInterval := '24 hours'
  else if AWindow = '48h' then WindowInterval := '48 hours'
  else if AWindow = '72h' then WindowInterval := '72 hours'
  else if AWindow = '7d' then WindowInterval := '7 days'
  else if AWindow = '30d' then WindowInterval := '30 days'
  else if AWindow = 'cumulative' then WindowInterval := '100 years'
  else WindowInterval := '24 hours';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Aggregate signals from signal_event
    var AggJson := DB.ExecuteScalarJson(
      'SELECT COALESCE(json_build_object(' +
      '  ''views'', COALESCE(SUM(CASE WHEN signal_type=''views'' THEN raw_value ELSE 0 END), 0)::int, ' +
      '  ''likes'', COALESCE(SUM(CASE WHEN signal_type=''likes'' THEN raw_value ELSE 0 END), 0)::int, ' +
      '  ''favorites'', COALESCE(SUM(CASE WHEN signal_type=''saves'' THEN raw_value ELSE 0 END), 0)::int, ' +
      '  ''comments'', COALESCE(SUM(CASE WHEN signal_type=''comments'' THEN raw_value ELSE 0 END), 0)::int, ' +
      '  ''shares'', COALESCE(SUM(CASE WHEN signal_type=''shares'' THEN raw_value ELSE 0 END), 0)::int, ' +
      '  ''follows'', COALESCE(SUM(CASE WHEN signal_type=''follows'' THEN raw_value ELSE 0 END), 0)::int ' +
      ')::text, ''{}'')::text ' +
      'FROM artifactos.signal_event ' +
      'WHERE artifact_id=:aid::uuid AND occurred_at > now() - ''' + WindowInterval + '''::interval',
      '{"aid":"' + AArtifactId + '"}');

    var JObj := TJSONObject.ParseJSONValue(AggJson) as TJSONObject;
    if JObj <> nil then
    try
      Views := JObj.GetValue<Integer>('views', 0);
      Likes := JObj.GetValue<Integer>('likes', 0);
      Favs := JObj.GetValue<Integer>('favorites', 0);
      Comments := JObj.GetValue<Integer>('comments', 0);
      Shares := JObj.GetValue<Integer>('shares', 0);
      Follows := JObj.GetValue<Integer>('follows', 0);
    finally
      JObj.Free;
    end
    else
    begin
      Views := 0; Likes := 0; Favs := 0; Comments := 0; Shares := 0; Follows := 0;
    end;

    // Compute rates
    if Views > 0 then
    begin
      EngRate := (Likes + Favs + Comments + Shares) / Views;
      ConvRate := Follows / Views;
    end
    else
    begin
      EngRate := 0;
      ConvRate := 0;
    end;

    // Insert observation
    var PackageRef := IfThen(APackageId <> '', '''' + APackageId + '''', 'NULL');
    var VersionRef := IfThen(AVersionId <> '', '''' + AVersionId + '''', 'NULL');

    AObsId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.performance_observation ' +
      '  (artifact_id, artifact_version_id, publication_package_id, platform, ' +
      '   observation_window, views, likes, favorites, comments, shares, follows, ' +
      '   engagement_rate, conversion_rate, signal_source) ' +
      'VALUES (''' + AArtifactId + ''', ' + VersionRef + ', ' + PackageRef + ', ' +
      '  ''' + APlatform + ''', ''' + AWindow + ''', ' +
      '  ' + IntToStr(Views) + ', ' + IntToStr(Likes) + ', ' + IntToStr(Favs) + ', ' +
      '  ' + IntToStr(Comments) + ', ' + IntToStr(Shares) + ', ' + IntToStr(Follows) + ', ' +
      '  ' + FloatToStr(EngRate, TFormatSettings.Create('en-US')) + ', ' +
      '  ' + FloatToStr(ConvRate, TFormatSettings.Create('en-US')) + ', ' +
      '  ''estimated'') ' +
      'RETURNING id::text');

    WriteLn(Format('[PerfCollector] Observation: id=%s platform=%s window=%s views=%d eng=%.3f',
      [AObsId, APlatform, AWindow, Views, EngRate]));
    Result := True;

  finally
    DB.Disconnect;
  end;
end;

class function TPerformanceCollector.GetLatestObservation(const AArtifactId, APlatform: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalarJson(
      'SELECT row_to_json(o) FROM artifactos.performance_observation o ' +
      'WHERE artifact_id=:aid::uuid AND platform=:platform ' +
      'ORDER BY observed_at DESC LIMIT 1',
      Format('{"aid":"%s","platform":"%s"}', [AArtifactId, APlatform]));
  finally
    DB.Disconnect;
  end;
end;

class function TPerformanceCollector.UpdateCalibration(const AArtifactId, ACognitionTraceId: string;
  const AActual: TPerformanceMetrics): Boolean;
var
  DB: TArtifactDB;
  PredictedEng, ActualEng, Delta: Double;
  MissCount: Integer;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Read prediction from cognition_trace
    var PredJson := DB.ExecuteScalarJson(
      'SELECT predictions::text FROM artifactos.cognition_trace WHERE id=:id::uuid',
      '{"id":"' + ACognitionTraceId + '"}');

    PredictedEng := 0.5; // default
    var JObj := TJSONObject.ParseJSONValue(PredJson) as TJSONObject;
    if JObj <> nil then
    try
      PredictedEng := JObj.GetValue<Double>('expected_engagement', 0.5);
    finally
      JObj.Free;
    end;

    // Compute actual engagement rate
    if AActual.Views > 0 then
      ActualEng := (AActual.Likes + AActual.Favorites + AActual.Comments + AActual.Shares) / AActual.Views
    else
      ActualEng := 0;

    // Calibration delta = |predicted - actual|
    Delta := Abs(PredictedEng - ActualEng);

    // Get current consecutive miss count
    var CurMiss := DB.ExecuteScalar(
      'SELECT consecutive_miss_count FROM artifactos.cognition_trace WHERE id=''' + ACognitionTraceId + '''');
    if CurMiss = '' then CurMiss := '0';

    // Determine if this is a miss (delta > 0.25 threshold)
    if Delta > 0.25 then
      MissCount := StrToIntDef(CurMiss, 0) + 1
    else
      MissCount := 0;

    // Update cognition trace
    DB.ExecuteJson(
      'UPDATE artifactos.cognition_trace SET ' +
      '  calibration_delta=:delta, ' +
      '  consecutive_miss_count=:miss, ' +
      '  outcome_evidence=:evidence::jsonb, ' +
      '  outcome_status=CASE WHEN :delta < 0.25 THEN ''confirmed'' WHEN :delta < 0.5 THEN ''partial'' ELSE ''disproven'' END, ' +
      '  resolved_at=now() ' +
      'WHERE id=:id::uuid',
      Format('{"delta":%f,"miss":%d,"evidence":"{\"actual_engagement\":%f,\"predicted_engagement\":%f}","id":"%s"}',
        [Delta, MissCount, ActualEng, PredictedEng, ACognitionTraceId]));

    WriteLn(Format('[Calibration] trace=%s predicted=%.3f actual=%.3f delta=%.3f miss=%d',
      [ACognitionTraceId, PredictedEng, ActualEng, Delta, MissCount]));
    Result := True;

  finally
    DB.Disconnect;
  end;
end;

class function TPerformanceCollector.CheckDisturbance(const AArtifactId: string;
  out AEventType, ASeverity: string): Boolean;
var
  DB: TArtifactDB;
  Delta: Double;
  MissCount: Integer;
begin
  Result := False;
  AEventType := '';
  ASeverity := '';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Get latest cognition trace for this artifact
    var TraceInfo := DB.ExecuteScalarJson(
      'SELECT calibration_delta, consecutive_miss_count ' +
      'FROM artifactos.cognition_trace ' +
      'WHERE artifact_id=:aid::uuid AND trace_type=''publish'' ' +
      'ORDER BY created_at DESC LIMIT 1',
      '{"aid":"' + AArtifactId + '"}');

    if TraceInfo = '' then Exit;

    var JObj := TJSONObject.ParseJSONValue(TraceInfo) as TJSONObject;
    if JObj <> nil then
    try
      Delta := JObj.GetValue<Double>('calibration_delta', 0);
      MissCount := JObj.GetValue<Integer>('consecutive_miss_count', 0);
    finally
      JObj.Free;
    end
    else
      Exit;

    // Check disturbance triggers
    if MissCount >= 3 then
    begin
      AEventType := 'consecutive_miss';
      ASeverity := 'high';
      Result := True;
    end
    else if Delta > 0.5 then
    begin
      AEventType := 'calibration_drift';
      ASeverity := 'medium';
      Result := True;
    end
    else if Delta > 0.25 then
    begin
      AEventType := 'calibration_drift';
      ASeverity := 'low';
      Result := True;
    end;

  finally
    DB.Disconnect;
  end;
end;

end.
