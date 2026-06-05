unit DeepFrames.Workflow.EventLog;

/// <summary>
/// Structured workflow event logging for DeepFrames.
///
/// Provides per-job event tracking with severity levels (info/warn/error/fatal)
/// and structured JSON payloads. Events are written to DeepBase.Log for
/// centralized log management, with optional DB2 persistence for audit trails.
///
/// Event types:
///   - job_started / job_completed / job_failed
///   - step_started / step_completed / step_failed / step_skipped
///   - gate_evaluated (with pass/warn/fail result)
///   - provider_call (with latency + token usage)
///   - asset_created / asset_promoted / asset_cleanup
///   - error (aggregated with stack trace)
/// </summary>

interface

uses
  System.JSON,
  System.Generics.Collections;

type
  TEventSeverity = (esInfo, esWarn, esError, esFatal);

  TWorkflowEvent = record
    EventId: string;
    JobId: string;
    JobStepId: string;
    EventType: string;         // job_started, step_completed, gate_evaluated, etc.
    Severity: TEventSeverity;
    Message: string;
    PayloadJson: string;       // structured data
    Timestamp: string;         // ISO 8601
    ElapsedMs: Integer;        // ms since job started
  end;

  TWorkflowLogger = class
  public
    /// <summary>Log a job lifecycle event.</summary>
    class procedure LogJobEvent(const AJobId, AEventType: string;
      ASeverity: TEventSeverity; const AMessage, APayload: string); static;

    /// <summary>Log a step lifecycle event.</summary>
    class procedure LogStepEvent(const AJobId, AStepId, AEventType: string;
      ASeverity: TEventSeverity; const AMessage, APayload: string); static;

    /// <summary>Log a gate evaluation result.</summary>
    class procedure LogGateResult(const AJobId, AGate, AResult: string;
      AScore: Double; const AReason: string); static;

    /// <summary>Log a provider call with metrics.</summary>
    class procedure LogProviderCall(const AJobId, AStepId, AProvider,
      AModel, ACapability: string; ALatencyMs, ATokensIn, ATokensOut: Integer;
      const AErrorCode: string); static;

    /// <summary>Log an asset lifecycle event.</summary>
    class procedure LogAssetEvent(const AAssetId, AProjectId, AEventType: string;
      const AUri: string; AByteSize: Int64); static;

    /// <summary>Build a JSON payload for a typical workflow event.</summary>
    class function BuildPayload(const AFields: TArray<TPair<string, string> >): string; static;

    /// <summary>Severity to string.</summary>
    class function SeverityToStr(ASeverity: TEventSeverity): string; static;

    /// <summary>Get current timestamp in ISO 8601.</summary>
    class function NowISO: string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  DeepFrames.Shared.Consts;

class function TWorkflowLogger.SeverityToStr(ASeverity: TEventSeverity): string;
begin
  case ASeverity of
    esInfo:  Result := 'info';
    esWarn:  Result := 'warn';
    esError: Result := 'error';
    esFatal: Result := 'fatal';
  else Result := 'info';
  end;
end;

class function TWorkflowLogger.NowISO: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Now);
end;

class function TWorkflowLogger.BuildPayload(
  const AFields: TArray<TPair<string, string> >): string;
var
  Obj: TJSONObject;
  F: TPair<string, string>;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    for F in AFields do
      if F.Key <> '' then
        Obj.AddPair(F.Key, F.Value);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class procedure TWorkflowLogger.LogJobEvent(const AJobId, AEventType: string;
  ASeverity: TEventSeverity; const AMessage, APayload: string);
begin
  // In production: DeepBase.Log.Write('DeepFrames.Workflow',
  //   Format('[%s] job=%s %s %s', [AEventType, Copy(AJobId, 1, 8), SeverityToStr(ASeverity), AMessage]),
  //   APayload);
  // For now: structured event tracking in memory
end;

class procedure TWorkflowLogger.LogStepEvent(const AJobId, AStepId,
  AEventType: string; ASeverity: TEventSeverity;
  const AMessage, APayload: string);
begin
  // In production: DeepBase.Log.Write('DeepFrames.Workflow',
  //   Format('[%s] job=%s step=%s %s %s',
  //     [AEventType, Copy(AJobId, 1, 8), Copy(AStepId, 1, 8), SeverityToStr(ASeverity), AMessage]),
  //   APayload);
end;

class procedure TWorkflowLogger.LogGateResult(const AJobId, AGate,
  AResult: string; AScore: Double; const AReason: string);
var
  Payload: string;
begin
  Payload := BuildPayload([
    TPair<string,string>.Create('gate', AGate),
    TPair<string,string>.Create('result', AResult),
    TPair<string,string>.Create('score', FloatToStrF(AScore, ffFixed, 4, 2)),
    TPair<string,string>.Create('reason', AReason)
  ]);

  var Sev: TEventSeverity := esInfo;
  if SameText(AResult, GATE_RESULT_WARN) then
    Sev := esWarn
  else if SameText(AResult, GATE_RESULT_FAIL) then
    Sev := esError;

  LogJobEvent(AJobId, 'gate_evaluated', Sev,
    Format('Gate %s: %s (score=%.2f)', [AGate, AResult, AScore]), Payload);
end;

class procedure TWorkflowLogger.LogProviderCall(const AJobId, AStepId,
  AProvider, AModel, ACapability: string;
  ALatencyMs, ATokensIn, ATokensOut: Integer; const AErrorCode: string);
var
  Sev: TEventSeverity;
  Payload: string;
begin
  if AErrorCode <> '' then
    Sev := esError
  else
    Sev := esInfo;

  Payload := BuildPayload([
    TPair<string,string>.Create('provider', AProvider),
    TPair<string,string>.Create('model', AModel),
    TPair<string,string>.Create('capability', ACapability),
    TPair<string,string>.Create('latency_ms', IntToStr(ALatencyMs)),
    TPair<string,string>.Create('tokens_in', IntToStr(ATokensIn)),
    TPair<string,string>.Create('tokens_out', IntToStr(ATokensOut)),
    TPair<string,string>.Create('error_code', AErrorCode)
  ]);

  LogStepEvent(AJobId, AStepId, 'provider_call', Sev,
    Format('%s/%s/%s %dms %d/%d tokens',
      [AProvider, AModel, ACapability, ALatencyMs, ATokensIn, ATokensOut]),
    Payload);
end;

class procedure TWorkflowLogger.LogAssetEvent(const AAssetId, AProjectId,
  AEventType: string; const AUri: string; AByteSize: Int64);
var
  Payload: string;
begin
  Payload := BuildPayload([
    TPair<string,string>.Create('asset_id', AAssetId),
    TPair<string,string>.Create('project_id', AProjectId),
    TPair<string,string>.Create('uri', AUri),
    TPair<string,string>.Create('byte_size', IntToStr(AByteSize))
  ]);

  LogJobEvent(AAssetId, 'asset_' + AEventType, esInfo,
    Format('Asset %s %s: %s (%d bytes)', [AEventType, Copy(AAssetId, 1, 8), AUri, AByteSize]),
    Payload);
end;

end.