{******************************************************************************}
{                                                                              }
{  UniFlow Metrics Collector                                                   }
{  Central metrics registry and collection system                              }
{                                                                              }
{  Features:                                                                   }
{  - Global metrics registry                                                   }
{  - Predefined UniFlow metrics                                                }
{  - Prometheus text format export                                             }
{  - JSON format export                                                        }
{  - HTTP endpoint handler                                                     }
{                                                                              }
{******************************************************************************}

unit UniFlow.Metrics.Collector;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs,
  System.DateUtils,
  UniFlow.Metrics.Types,
  DeepBase.Exceptions;

type
  //----------------------------------------------------------------------------
  // TMetricsRegistry - Central metrics registry
  //----------------------------------------------------------------------------

  TMetricsRegistry = class
  private
    FMetrics: TObjectDictionary<string, TMetricFamily>;
    FLock: TCriticalSection;
    FNamespace: string;
    FSubsystem: string;
    FConstLabels: TMetricLabels;

    function BuildName(const AName: string): string;
  public
    constructor Create(const ANamespace: string = ''; const ASubsystem: string = '');
    destructor Destroy; override;

    // Registry configuration
    procedure SetNamespace(const ANamespace: string);
    procedure SetSubsystem(const ASubsystem: string);
    procedure AddConstLabel(const AName, AValue: string);

    // Metric registration
    function RegisterCounter(const AName, AHelp: string): TMetricFamily;
    function RegisterGauge(const AName, AHelp: string): TMetricFamily;
    function RegisterHistogram(const AName, AHelp: string;
      const ABuckets: TArray<Double> = nil): TMetricFamily;
    function RegisterSummary(const AName, AHelp: string;
      const AQuantiles: TArray<Double> = nil): TMetricFamily;

    // Get existing metric
    function GetMetric(const AName: string): TMetricFamily;
    function HasMetric(const AName: string): Boolean;

    // Unregister
    procedure Unregister(const AName: string);
    procedure Clear;

    // Export
    function ToPrometheusText: string;
    function ToJSON: TJSONObject;

    // Stats
    function MetricCount: Integer;
    function GetMetricNames: TArray<string>;

    property Namespace: string read FNamespace;
    property Subsystem: string read FSubsystem;
  end;

  //----------------------------------------------------------------------------
  // TUniFlowMetrics - Predefined UniFlow metrics
  //----------------------------------------------------------------------------

  TUniFlowMetrics = class
  private
    FRegistry: TMetricsRegistry;

    // Workflow metrics
    FWorkflowsStarted: TMetricFamily;
    FWorkflowsCompleted: TMetricFamily;
    FWorkflowsFailed: TMetricFamily;
    FWorkflowDuration: TMetricFamily;
    FActiveWorkflows: TMetricFamily;

    // Step metrics
    FStepsExecuted: TMetricFamily;
    FStepsFailed: TMetricFamily;
    FStepDuration: TMetricFamily;

    // LLM metrics
    FLLMRequests: TMetricFamily;
    FLLMErrors: TMetricFamily;
    FLLMDuration: TMetricFamily;
    FLLMTokensInput: TMetricFamily;
    FLLMTokensOutput: TMetricFamily;
    FLLMCost: TMetricFamily;

    // Skill metrics
    FSkillInvocations: TMetricFamily;
    FSkillErrors: TMetricFamily;
    FSkillDuration: TMetricFamily;

    // Session metrics
    FActiveSessions: TMetricFamily;
    FSessionsCreated: TMetricFamily;
    FSessionsExpired: TMetricFamily;
    FMessagesProcessed: TMetricFamily;

    // Rate limiting metrics
    FRateLimitHits: TMetricFamily;
    FQuotaExceeded: TMetricFamily;

    // System metrics
    FUptime: TMetricFamily;
    FStartTime: TDateTime;

    procedure RegisterMetrics;
  public
    constructor Create(ARegistry: TMetricsRegistry = nil);
    destructor Destroy; override;

    //--------------------------------------------------------------------------
    // Workflow tracking
    //--------------------------------------------------------------------------

    procedure WorkflowStarted(const AWorkflowName: string);
    procedure WorkflowCompleted(const AWorkflowName: string; ADurationMs: Double);
    procedure WorkflowFailed(const AWorkflowName: string; const AError: string);
    procedure SetActiveWorkflows(ACount: Integer);

    //--------------------------------------------------------------------------
    // Step tracking
    //--------------------------------------------------------------------------

    procedure StepExecuted(const AWorkflowName, AStepName, AStepType: string;
      ADurationMs: Double);
    procedure StepFailed(const AWorkflowName, AStepName, AStepType: string);

    //--------------------------------------------------------------------------
    // LLM tracking
    //--------------------------------------------------------------------------

    procedure LLMRequest(const AProvider, AModel: string; ADurationMs: Double;
      AInputTokens, AOutputTokens: Integer; ACost: Double = 0);
    procedure LLMError(const AProvider, AModel, AErrorType: string);

    //--------------------------------------------------------------------------
    // Skill tracking
    //--------------------------------------------------------------------------

    procedure SkillInvoked(const ASkillName: string; ADurationMs: Double);
    procedure SkillError(const ASkillName, AErrorType: string);

    //--------------------------------------------------------------------------
    // Session tracking
    //--------------------------------------------------------------------------

    procedure SessionCreated;
    procedure SessionExpired;
    procedure SetActiveSessions(ACount: Integer);
    procedure MessageProcessed(const ARole: string);

    //--------------------------------------------------------------------------
    // Rate limiting tracking
    //--------------------------------------------------------------------------

    procedure RateLimitHit(const AScope, AIdentifier: string);
    procedure QuotaExceeded(const AUserId: string);

    //--------------------------------------------------------------------------
    // System metrics
    //--------------------------------------------------------------------------

    function GetUptimeSeconds: Double;

    //--------------------------------------------------------------------------
    // Export
    //--------------------------------------------------------------------------

    function ToPrometheusText: string;
    function ToJSON: TJSONObject;

    property Registry: TMetricsRegistry read FRegistry;
  end;

  //----------------------------------------------------------------------------
  // TMetricsHTTPHandler - HTTP endpoint handler
  //----------------------------------------------------------------------------

  TMetricsFormat = (mfPrometheus, mfJSON);

  TMetricsHTTPHandler = class
  private
    FMetrics: TUniFlowMetrics;
    FPath: string;
  public
    constructor Create(AMetrics: TUniFlowMetrics; const APath: string = '/metrics');

    /// <summary>Handle HTTP request, returns response body and content type</summary>
    function HandleRequest(const AAcceptHeader: string;
      out AContentType: string): string;

    /// <summary>Get metrics in specified format</summary>
    function GetMetrics(AFormat: TMetricsFormat): string;

    property Path: string read FPath;
  end;

  //----------------------------------------------------------------------------
  // TMetricTimer - Helper for timing operations
  //----------------------------------------------------------------------------

  TMetricTimer = class
  private
    FHistogram: THistogramValue;
    FSummary: TSummaryValue;
    FStartTime: TDateTime;
  public
    constructor Create(AHistogram: THistogramValue); overload;
    constructor Create(ASummary: TSummaryValue); overload;

    /// <summary>Record elapsed time in milliseconds</summary>
    function ObserveDuration: Double;

    /// <summary>Record elapsed time without stopping</summary>
    function ElapsedMs: Double;
  end;

  //----------------------------------------------------------------------------
  // Global metrics instance
  //----------------------------------------------------------------------------

var
  DefaultMetrics: TUniFlowMetrics;

  procedure InitializeMetrics(ARegistry: TMetricsRegistry = nil);
  procedure FinalizeMetrics;
  function Metrics: TUniFlowMetrics;

implementation

//------------------------------------------------------------------------------
// TMetricsRegistry
//------------------------------------------------------------------------------

constructor TMetricsRegistry.Create(const ANamespace: string; const ASubsystem: string);
begin
  inherited Create;
  FMetrics := TObjectDictionary<string, TMetricFamily>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FNamespace := ANamespace;
  FSubsystem := ASubsystem;
  FConstLabels := TMetricLabels.Create;
end;

destructor TMetricsRegistry.Destroy;
begin
  FMetrics.Free;
  FLock.Free;
  FConstLabels.Free;
  inherited Destroy;
end;

function TMetricsRegistry.BuildName(const AName: string): string;
begin
  Result := '';
  if FNamespace <> '' then
    Result := FNamespace + '_';
  if FSubsystem <> '' then
    Result := Result + FSubsystem + '_';
  Result := Result + AName;
end;

procedure TMetricsRegistry.SetNamespace(const ANamespace: string);
begin
  FNamespace := ANamespace;
end;

procedure TMetricsRegistry.SetSubsystem(const ASubsystem: string);
begin
  FSubsystem := ASubsystem;
end;

procedure TMetricsRegistry.AddConstLabel(const AName, AValue: string);
begin
  FConstLabels.Add(AName, AValue);
end;

function TMetricsRegistry.RegisterCounter(const AName, AHelp: string): TMetricFamily;
var
  FullName: string;
begin
  FullName := BuildName(AName);

  FLock.Enter;
  try
    if FMetrics.TryGetValue(FullName, Result) then
    begin
      if Result.MetricType <> mtCounter then
        raise EOperationException.CreateFmt('Metric %s already registered as %s',
          [FullName, Result.MetricType.ToString]);
    end
    else
    begin
      Result := TMetricFamily.Create(FullName, AHelp, mtCounter);
      FMetrics.Add(FullName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.RegisterGauge(const AName, AHelp: string): TMetricFamily;
var
  FullName: string;
begin
  FullName := BuildName(AName);

  FLock.Enter;
  try
    if FMetrics.TryGetValue(FullName, Result) then
    begin
      if Result.MetricType <> mtGauge then
        raise EOperationException.CreateFmt('Metric %s already registered as %s',
          [FullName, Result.MetricType.ToString]);
    end
    else
    begin
      Result := TMetricFamily.Create(FullName, AHelp, mtGauge);
      FMetrics.Add(FullName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.RegisterHistogram(const AName, AHelp: string;
  const ABuckets: TArray<Double>): TMetricFamily;
var
  FullName: string;
begin
  FullName := BuildName(AName);

  FLock.Enter;
  try
    if FMetrics.TryGetValue(FullName, Result) then
    begin
      if Result.MetricType <> mtHistogram then
        raise EOperationException.CreateFmt('Metric %s already registered as %s',
          [FullName, Result.MetricType.ToString]);
    end
    else
    begin
      Result := TMetricFamily.Create(FullName, AHelp, mtHistogram);
      if Length(ABuckets) > 0 then
        Result.SetBuckets(ABuckets);
      FMetrics.Add(FullName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.RegisterSummary(const AName, AHelp: string;
  const AQuantiles: TArray<Double>): TMetricFamily;
var
  FullName: string;
begin
  FullName := BuildName(AName);

  FLock.Enter;
  try
    if FMetrics.TryGetValue(FullName, Result) then
    begin
      if Result.MetricType <> mtSummary then
        raise EOperationException.CreateFmt('Metric %s already registered as %s',
          [FullName, Result.MetricType.ToString]);
    end
    else
    begin
      Result := TMetricFamily.Create(FullName, AHelp, mtSummary);
      if Length(AQuantiles) > 0 then
        Result.SetQuantiles(AQuantiles);
      FMetrics.Add(FullName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.GetMetric(const AName: string): TMetricFamily;
var
  FullName: string;
begin
  FullName := BuildName(AName);

  FLock.Enter;
  try
    if not FMetrics.TryGetValue(FullName, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.HasMetric(const AName: string): Boolean;
begin
  Result := GetMetric(AName) <> nil;
end;

procedure TMetricsRegistry.Unregister(const AName: string);
var
  FullName: string;
begin
  FullName := BuildName(AName);

  FLock.Enter;
  try
    FMetrics.Remove(FullName);
  finally
    FLock.Leave;
  end;
end;

procedure TMetricsRegistry.Clear;
begin
  FLock.Enter;
  try
    FMetrics.Clear;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.ToPrometheusText: string;
var
  SB: TStringBuilder;
  Pair: TPair<string, TMetricFamily>;
  Names: TArray<string>;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    FLock.Enter;
    try
      // Sort metric names for consistent output
      Names := FMetrics.Keys.ToArray;
      TArray.Sort<string>(Names);

      for I := 0 to Length(Names) - 1 do
      begin
        if I > 0 then
          SB.AppendLine;
        SB.Append(FMetrics[Names[I]].ToPrometheusText);
      end;
    finally
      FLock.Leave;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMetricsRegistry.ToJSON: TJSONObject;
var
  MetricsArray: TJSONArray;
  Pair: TPair<string, TMetricFamily>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('timestamp', DateToISO8601(Now, False));

  if FNamespace <> '' then
    Result.AddPair('namespace', FNamespace);
  if FSubsystem <> '' then
    Result.AddPair('subsystem', FSubsystem);

  MetricsArray := TJSONArray.Create;
  FLock.Enter;
  try
    for Pair in FMetrics do
      MetricsArray.Add(Pair.Value.ToJSON);
  finally
    FLock.Leave;
  end;

  Result.AddPair('metrics', MetricsArray);
end;

function TMetricsRegistry.MetricCount: Integer;
begin
  FLock.Enter;
  try
    Result := FMetrics.Count;
  finally
    FLock.Leave;
  end;
end;

function TMetricsRegistry.GetMetricNames: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FMetrics.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TUniFlowMetrics
//------------------------------------------------------------------------------

constructor TUniFlowMetrics.Create(ARegistry: TMetricsRegistry);
begin
  inherited Create;
  FStartTime := Now;

  if ARegistry <> nil then
    FRegistry := ARegistry
  else
  begin
    FRegistry := TMetricsRegistry.Create('uniflow', '');
  end;

  RegisterMetrics;
end;

destructor TUniFlowMetrics.Destroy;
begin
  // Registry owns the metric families
  FRegistry.Free;
  inherited Destroy;
end;

procedure TUniFlowMetrics.RegisterMetrics;
begin
  // Workflow metrics
  FWorkflowsStarted := FRegistry.RegisterCounter('workflows_started_total',
    'Total number of workflows started');
  FWorkflowsCompleted := FRegistry.RegisterCounter('workflows_completed_total',
    'Total number of workflows completed successfully');
  FWorkflowsFailed := FRegistry.RegisterCounter('workflows_failed_total',
    'Total number of workflows that failed');
  FWorkflowDuration := FRegistry.RegisterHistogram('workflow_duration_milliseconds',
    'Workflow execution duration in milliseconds',
    TDefaultBuckets.LLMDuration);
  FActiveWorkflows := FRegistry.RegisterGauge('workflows_active',
    'Number of currently active workflows');

  // Step metrics
  FStepsExecuted := FRegistry.RegisterCounter('steps_executed_total',
    'Total number of workflow steps executed');
  FStepsFailed := FRegistry.RegisterCounter('steps_failed_total',
    'Total number of workflow steps that failed');
  FStepDuration := FRegistry.RegisterHistogram('step_duration_milliseconds',
    'Step execution duration in milliseconds',
    TDefaultBuckets.HTTPDuration);

  // LLM metrics
  FLLMRequests := FRegistry.RegisterCounter('llm_requests_total',
    'Total number of LLM API requests');
  FLLMErrors := FRegistry.RegisterCounter('llm_errors_total',
    'Total number of LLM API errors');
  FLLMDuration := FRegistry.RegisterHistogram('llm_duration_milliseconds',
    'LLM API request duration in milliseconds',
    TDefaultBuckets.LLMDuration);
  FLLMTokensInput := FRegistry.RegisterCounter('llm_tokens_input_total',
    'Total number of input tokens sent to LLM');
  FLLMTokensOutput := FRegistry.RegisterCounter('llm_tokens_output_total',
    'Total number of output tokens received from LLM');
  FLLMCost := FRegistry.RegisterCounter('llm_cost_total',
    'Total cost of LLM API calls');

  // Skill metrics
  FSkillInvocations := FRegistry.RegisterCounter('skill_invocations_total',
    'Total number of skill invocations');
  FSkillErrors := FRegistry.RegisterCounter('skill_errors_total',
    'Total number of skill errors');
  FSkillDuration := FRegistry.RegisterHistogram('skill_duration_milliseconds',
    'Skill execution duration in milliseconds',
    TDefaultBuckets.HTTPDuration);

  // Session metrics
  FActiveSessions := FRegistry.RegisterGauge('sessions_active',
    'Number of currently active sessions');
  FSessionsCreated := FRegistry.RegisterCounter('sessions_created_total',
    'Total number of sessions created');
  FSessionsExpired := FRegistry.RegisterCounter('sessions_expired_total',
    'Total number of sessions expired');
  FMessagesProcessed := FRegistry.RegisterCounter('messages_processed_total',
    'Total number of messages processed');

  // Rate limiting metrics
  FRateLimitHits := FRegistry.RegisterCounter('rate_limit_hits_total',
    'Total number of rate limit hits');
  FQuotaExceeded := FRegistry.RegisterCounter('quota_exceeded_total',
    'Total number of quota exceeded events');

  // System metrics
  FUptime := FRegistry.RegisterGauge('uptime_seconds',
    'Time since metrics initialization in seconds');
end;

procedure TUniFlowMetrics.WorkflowStarted(const AWorkflowName: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['workflow', AWorkflowName]);
  try
    FWorkflowsStarted.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.WorkflowCompleted(const AWorkflowName: string; ADurationMs: Double);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['workflow', AWorkflowName]);
  try
    FWorkflowsCompleted.GetCounter(Labels).Inc;
    FWorkflowDuration.GetHistogram(Labels).Observe(ADurationMs);
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.WorkflowFailed(const AWorkflowName: string; const AError: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['workflow', AWorkflowName, 'error', AError]);
  try
    FWorkflowsFailed.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.SetActiveWorkflows(ACount: Integer);
begin
  FActiveWorkflows.GetGauge.Set_(ACount);
end;

procedure TUniFlowMetrics.StepExecuted(const AWorkflowName, AStepName, AStepType: string;
  ADurationMs: Double);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['workflow', AWorkflowName, 'step', AStepName, 'type', AStepType]);
  try
    FStepsExecuted.GetCounter(Labels).Inc;
    FStepDuration.GetHistogram(Labels).Observe(ADurationMs);
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.StepFailed(const AWorkflowName, AStepName, AStepType: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['workflow', AWorkflowName, 'step', AStepName, 'type', AStepType]);
  try
    FStepsFailed.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.LLMRequest(const AProvider, AModel: string; ADurationMs: Double;
  AInputTokens, AOutputTokens: Integer; ACost: Double);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['provider', AProvider, 'model', AModel]);
  try
    FLLMRequests.GetCounter(Labels).Inc;
    FLLMDuration.GetHistogram(Labels).Observe(ADurationMs);
    FLLMTokensInput.GetCounter(Labels).Inc(AInputTokens);
    FLLMTokensOutput.GetCounter(Labels).Inc(AOutputTokens);
    if ACost > 0 then
      FLLMCost.GetCounter(Labels).Inc(ACost);
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.LLMError(const AProvider, AModel, AErrorType: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['provider', AProvider, 'model', AModel, 'error', AErrorType]);
  try
    FLLMErrors.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.SkillInvoked(const ASkillName: string; ADurationMs: Double);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['skill', ASkillName]);
  try
    FSkillInvocations.GetCounter(Labels).Inc;
    FSkillDuration.GetHistogram(Labels).Observe(ADurationMs);
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.SkillError(const ASkillName, AErrorType: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['skill', ASkillName, 'error', AErrorType]);
  try
    FSkillErrors.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.SessionCreated;
begin
  FSessionsCreated.GetCounter.Inc;
end;

procedure TUniFlowMetrics.SessionExpired;
begin
  FSessionsExpired.GetCounter.Inc;
end;

procedure TUniFlowMetrics.SetActiveSessions(ACount: Integer);
begin
  FActiveSessions.GetGauge.Set_(ACount);
end;

procedure TUniFlowMetrics.MessageProcessed(const ARole: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['role', ARole]);
  try
    FMessagesProcessed.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.RateLimitHit(const AScope, AIdentifier: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['scope', AScope, 'identifier', AIdentifier]);
  try
    FRateLimitHits.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

procedure TUniFlowMetrics.QuotaExceeded(const AUserId: string);
var
  Labels: TMetricLabels;
begin
  Labels := TMetricLabels.Create(['user_id', AUserId]);
  try
    FQuotaExceeded.GetCounter(Labels).Inc;
  finally
    Labels.Free;
  end;
end;

function TUniFlowMetrics.GetUptimeSeconds: Double;
begin
  Result := SecondSpan(Now, FStartTime);
end;

function TUniFlowMetrics.ToPrometheusText: string;
begin
  // Update uptime before export
  FUptime.GetGauge.Set_(GetUptimeSeconds);
  Result := FRegistry.ToPrometheusText;
end;

function TUniFlowMetrics.ToJSON: TJSONObject;
begin
  // Update uptime before export
  FUptime.GetGauge.Set_(GetUptimeSeconds);
  Result := FRegistry.ToJSON;
end;

//------------------------------------------------------------------------------
// TMetricsHTTPHandler
//------------------------------------------------------------------------------

constructor TMetricsHTTPHandler.Create(AMetrics: TUniFlowMetrics; const APath: string);
begin
  inherited Create;
  FMetrics := AMetrics;
  FPath := APath;
end;

function TMetricsHTTPHandler.HandleRequest(const AAcceptHeader: string;
  out AContentType: string): string;
begin
  // Check Accept header for format preference
  if Pos('application/json', LowerCase(AAcceptHeader)) > 0 then
  begin
    AContentType := 'application/json; charset=utf-8';
    Result := GetMetrics(mfJSON);
  end
  else
  begin
    // Default to Prometheus format
    AContentType := 'text/plain; version=0.0.4; charset=utf-8';
    Result := GetMetrics(mfPrometheus);
  end;
end;

function TMetricsHTTPHandler.GetMetrics(AFormat: TMetricsFormat): string;
var
  JSON: TJSONObject;
begin
  case AFormat of
    mfPrometheus:
      Result := FMetrics.ToPrometheusText;
    mfJSON:
    begin
      JSON := FMetrics.ToJSON;
      try
        Result := JSON.ToString;
      finally
        JSON.Free;
      end;
    end;
  else
    Result := '';
  end;
end;

//------------------------------------------------------------------------------
// TMetricTimer
//------------------------------------------------------------------------------

constructor TMetricTimer.Create(AHistogram: THistogramValue);
begin
  inherited Create;
  FHistogram := AHistogram;
  FSummary := nil;
  FStartTime := Now;
end;

constructor TMetricTimer.Create(ASummary: TSummaryValue);
begin
  inherited Create;
  FHistogram := nil;
  FSummary := ASummary;
  FStartTime := Now;
end;

function TMetricTimer.ElapsedMs: Double;
begin
  Result := MilliSecondSpan(Now, FStartTime);
end;

function TMetricTimer.ObserveDuration: Double;
begin
  Result := ElapsedMs;

  if FHistogram <> nil then
    FHistogram.Observe(Result)
  else if FSummary <> nil then
    FSummary.Observe(Result);
end;

//------------------------------------------------------------------------------
// Global functions
//------------------------------------------------------------------------------

procedure InitializeMetrics(ARegistry: TMetricsRegistry);
begin
  FinalizeMetrics;
  DefaultMetrics := TUniFlowMetrics.Create(ARegistry);
end;

procedure FinalizeMetrics;
begin
  FreeAndNil(DefaultMetrics);
end;

function Metrics: TUniFlowMetrics;
begin
  if DefaultMetrics = nil then
    InitializeMetrics(nil);
  Result := DefaultMetrics;
end;

end.
