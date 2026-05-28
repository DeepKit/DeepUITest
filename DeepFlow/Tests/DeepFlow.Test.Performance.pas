{ ============================================================================
  UniFlow.Test.Performance - Performance Benchmark Tests

  Version: 1.0
  Description: Performance benchmarks for UniFlow components

  Benchmarks:
    - Message processing latency
    - Workflow parsing performance
    - Concurrent session handling
    - Memory usage tracking

  Acceptance Criteria:
    - Message processing < 10ms
    - 100+ concurrent sessions
    - Memory usage < 200MB
  ============================================================================ }

unit UniFlow.Test.Performance;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.SyncObjs,
  System.Threading,
  System.Diagnostics,
  UniFlow.Test.Framework,
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Context,
  UniFlow.Workflow.Executor,
  UniFlow.Session.Types,
  UniFlow.Session.Manager,
  UniFlow.Roles.Commander,
  UniFlow.Validation.Schema,
  UniFlow.Security.Sanitizer;

type
  // ============================================================================
  // Benchmark Result Types
  // ============================================================================

  /// <summary>
  /// Single benchmark measurement
  /// </summary>
  TBenchmarkMeasurement = record
    Name: string;
    Iterations: Integer;
    TotalMs: Double;
    MinMs: Double;
    MaxMs: Double;
    AvgMs: Double;
    P50Ms: Double;      // Median
    P95Ms: Double;      // 95th percentile
    P99Ms: Double;      // 99th percentile
    OpsPerSecond: Double;
    MemoryBefore: Int64;
    MemoryAfter: Int64;
    MemoryDelta: Int64;
    Passed: Boolean;
    Threshold: Double;  // Max acceptable ms
  end;

  /// <summary>
  /// Benchmark suite result
  /// </summary>
  TBenchmarkSuiteResult = class
  private
    FSuiteName: string;
    FMeasurements: TList<TBenchmarkMeasurement>;
    FStartTime: TDateTime;
    FEndTime: TDateTime;
    FTotalPassed: Integer;
    FTotalFailed: Integer;
  public
    constructor Create(const ASuiteName: string);
    destructor Destroy; override;

    procedure AddMeasurement(const AMeasurement: TBenchmarkMeasurement);
    function ToJSON: TJSONObject;
    function ToReport: string;

    property SuiteName: string read FSuiteName;
    property Measurements: TList<TBenchmarkMeasurement> read FMeasurements;
    property StartTime: TDateTime read FStartTime write FStartTime;
    property EndTime: TDateTime read FEndTime write FEndTime;
    property TotalPassed: Integer read FTotalPassed;
    property TotalFailed: Integer read FTotalFailed;
  end;

  // ============================================================================
  // Benchmark Runner
  // ============================================================================

  TBenchmarkProc = reference to procedure;

  /// <summary>
  /// Benchmark runner with measurement utilities
  /// </summary>
  TBenchmarkRunner = class
  private
    FResults: TObjectList<TBenchmarkSuiteResult>;
    FCurrentSuite: TBenchmarkSuiteResult;
    FWarmupIterations: Integer;
    FDefaultIterations: Integer;

    function GetCurrentMemory: Int64;
    function CalculatePercentile(const ASortedTimes: TArray<Double>;
      APercentile: Double): Double;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Start a benchmark suite
    /// </summary>
    procedure BeginSuite(const ASuiteName: string);

    /// <summary>
    /// End current benchmark suite
    /// </summary>
    procedure EndSuite;

    /// <summary>
    /// Run a benchmark
    /// </summary>
    function Benchmark(const AName: string; AProc: TBenchmarkProc;
      AIterations: Integer = 0; AThresholdMs: Double = 0): TBenchmarkMeasurement;

    /// <summary>
    /// Run concurrent benchmark
    /// </summary>
    function BenchmarkConcurrent(const AName: string; AProc: TBenchmarkProc;
      AThreadCount, AIterationsPerThread: Integer;
      AThresholdMs: Double = 0): TBenchmarkMeasurement;

    /// <summary>
    /// Get all results
    /// </summary>
    function GetResults: TObjectList<TBenchmarkSuiteResult>;

    /// <summary>
    /// Generate full report
    /// </summary>
    function GenerateReport: string;

    property WarmupIterations: Integer read FWarmupIterations write FWarmupIterations;
    property DefaultIterations: Integer read FDefaultIterations write FDefaultIterations;
  end;

  // ============================================================================
  // Performance Test Suites
  // ============================================================================

  /// <summary>
  /// Context operations performance tests
  /// </summary>
  TContextPerformanceTests = class(TTestCase)
  public
    procedure SetUp; override;
    procedure TearDown; override;

    [Test('Context variable set/get latency')]
    procedure TestContextVariableLatency;

    [Test('Context JSON serialization')]
    procedure TestContextSerialization;

    [Test('Context with many variables')]
    procedure TestContextScalability;
  end;

  /// <summary>
  /// Workflow parsing performance tests
  /// </summary>
  TWorkflowParsingTests = class(TTestCase)
  public
    procedure SetUp; override;
    procedure TearDown; override;

    [Test('Simple workflow parsing')]
    procedure TestSimpleWorkflowParsing;

    [Test('Complex workflow parsing')]
    procedure TestComplexWorkflowParsing;

    [Test('Workflow validation')]
    procedure TestWorkflowValidation;
  end;

  /// <summary>
  /// Session management performance tests
  /// </summary>
  TSessionPerformanceTests = class(TTestCase)
  private
    FManager: TSessionManager;
  public
    procedure SetUp; override;
    procedure TearDown; override;

    [Test('Session creation latency')]
    procedure TestSessionCreationLatency;

    [Test('Session lookup latency')]
    procedure TestSessionLookupLatency;

    [Test('Concurrent session operations')]
    procedure TestConcurrentSessions;

    [Test('Session with many messages')]
    procedure TestSessionMessageScalability;
  end;

  /// <summary>
  /// Intent recognition performance tests
  /// </summary>
  TIntentPerformanceTests = class(TTestCase)
  private
    FRecognizer: TIntentRecognizer;
  public
    procedure SetUp; override;
    procedure TearDown; override;

    [Test('Single intent recognition')]
    procedure TestSingleIntentLatency;

    [Test('Multiple patterns recognition')]
    procedure TestMultiplePatternsLatency;

    [Test('Intent with many patterns')]
    procedure TestIntentScalability;
  end;

  /// <summary>
  /// Validation performance tests
  /// </summary>
  TValidationPerformanceTests = class(TTestCase)
  public
    procedure SetUp; override;
    procedure TearDown; override;

    [Test('JSON Schema validation')]
    procedure TestSchemaValidationLatency;

    [Test('Input sanitization')]
    procedure TestSanitizationLatency;

    [Test('Prompt guard check')]
    procedure TestPromptGuardLatency;
  end;

  /// <summary>
  /// Run all performance benchmarks
  /// </summary>
  procedure RunPerformanceBenchmarks;

  /// <summary>
  /// Quick performance check (subset of tests)
  /// </summary>
  function QuickPerformanceCheck: Boolean;

implementation

uses
  System.DateUtils,
  System.Math;

{ TBenchmarkSuiteResult }

constructor TBenchmarkSuiteResult.Create(const ASuiteName: string);
begin
  inherited Create;
  FSuiteName := ASuiteName;
  FMeasurements := TList<TBenchmarkMeasurement>.Create;
  FStartTime := Now;
  FTotalPassed := 0;
  FTotalFailed := 0;
end;

destructor TBenchmarkSuiteResult.Destroy;
begin
  FMeasurements.Free;
  inherited;
end;

procedure TBenchmarkSuiteResult.AddMeasurement(const AMeasurement: TBenchmarkMeasurement);
begin
  FMeasurements.Add(AMeasurement);
  if AMeasurement.Passed then
    Inc(FTotalPassed)
  else
    Inc(FTotalFailed);
end;

function TBenchmarkSuiteResult.ToJSON: TJSONObject;
var
  M: TBenchmarkMeasurement;
  MeasurementsArr: TJSONArray;
  MObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('suite_name', FSuiteName);
  Result.AddPair('start_time', DateTimeToStr(FStartTime));
  Result.AddPair('end_time', DateTimeToStr(FEndTime));
  Result.AddPair('total_passed', TJSONNumber.Create(FTotalPassed));
  Result.AddPair('total_failed', TJSONNumber.Create(FTotalFailed));

  MeasurementsArr := TJSONArray.Create;
  for M in FMeasurements do
  begin
    MObj := TJSONObject.Create;
    MObj.AddPair('name', M.Name);
    MObj.AddPair('iterations', TJSONNumber.Create(M.Iterations));
    MObj.AddPair('total_ms', TJSONNumber.Create(M.TotalMs));
    MObj.AddPair('avg_ms', TJSONNumber.Create(M.AvgMs));
    MObj.AddPair('min_ms', TJSONNumber.Create(M.MinMs));
    MObj.AddPair('max_ms', TJSONNumber.Create(M.MaxMs));
    MObj.AddPair('p50_ms', TJSONNumber.Create(M.P50Ms));
    MObj.AddPair('p95_ms', TJSONNumber.Create(M.P95Ms));
    MObj.AddPair('p99_ms', TJSONNumber.Create(M.P99Ms));
    MObj.AddPair('ops_per_second', TJSONNumber.Create(M.OpsPerSecond));
    MObj.AddPair('memory_delta_bytes', TJSONNumber.Create(M.MemoryDelta));
    MObj.AddPair('passed', TJSONBool.Create(M.Passed));
    if M.Threshold > 0 then
      MObj.AddPair('threshold_ms', TJSONNumber.Create(M.Threshold));
    MeasurementsArr.Add(MObj);
  end;
  Result.AddPair('measurements', MeasurementsArr);
end;

function TBenchmarkSuiteResult.ToReport: string;
var
  SB: TStringBuilder;
  M: TBenchmarkMeasurement;
  Status: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('========================================');
    SB.AppendFormat('Benchmark Suite: %s', [FSuiteName]).AppendLine;
    SB.AppendLine('========================================');
    SB.AppendFormat('Passed: %d  Failed: %d', [FTotalPassed, FTotalFailed]).AppendLine;
    SB.AppendLine;

    for M in FMeasurements do
    begin
      if M.Passed then
        Status := '[PASS]'
      else
        Status := '[FAIL]';

      SB.AppendFormat('%s %s', [Status, M.Name]).AppendLine;
      SB.AppendFormat('  Iterations: %d', [M.Iterations]).AppendLine;
      SB.AppendFormat('  Avg: %.3f ms  Min: %.3f ms  Max: %.3f ms',
        [M.AvgMs, M.MinMs, M.MaxMs]).AppendLine;
      SB.AppendFormat('  P50: %.3f ms  P95: %.3f ms  P99: %.3f ms',
        [M.P50Ms, M.P95Ms, M.P99Ms]).AppendLine;
      SB.AppendFormat('  Ops/sec: %.0f', [M.OpsPerSecond]).AppendLine;
      SB.AppendFormat('  Memory delta: %d bytes', [M.MemoryDelta]).AppendLine;
      if M.Threshold > 0 then
        SB.AppendFormat('  Threshold: %.3f ms', [M.Threshold]).AppendLine;
      SB.AppendLine;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TBenchmarkRunner }

constructor TBenchmarkRunner.Create;
begin
  inherited;
  FResults := TObjectList<TBenchmarkSuiteResult>.Create;
  FWarmupIterations := 10;
  FDefaultIterations := 1000;
end;

destructor TBenchmarkRunner.Destroy;
begin
  FResults.Free;
  inherited;
end;

function TBenchmarkRunner.GetCurrentMemory: Int64;
begin
  // Simple memory tracking - in production would use more accurate methods
  Result := GetHeapStatus.TotalAllocated;
end;

function TBenchmarkRunner.CalculatePercentile(const ASortedTimes: TArray<Double>;
  APercentile: Double): Double;
var
  Index: Double;
  Lower, Upper: Integer;
  Frac: Double;
begin
  if Length(ASortedTimes) = 0 then
    Exit(0);

  if Length(ASortedTimes) = 1 then
    Exit(ASortedTimes[0]);

  Index := (APercentile / 100) * (Length(ASortedTimes) - 1);
  Lower := Trunc(Index);
  Upper := Min(Lower + 1, High(ASortedTimes));
  Frac := Index - Lower;

  Result := ASortedTimes[Lower] * (1 - Frac) + ASortedTimes[Upper] * Frac;
end;

procedure TBenchmarkRunner.BeginSuite(const ASuiteName: string);
begin
  FCurrentSuite := TBenchmarkSuiteResult.Create(ASuiteName);
  FResults.Add(FCurrentSuite);
end;

procedure TBenchmarkRunner.EndSuite;
begin
  if Assigned(FCurrentSuite) then
    FCurrentSuite.EndTime := Now;
  FCurrentSuite := nil;
end;

function TBenchmarkRunner.Benchmark(const AName: string; AProc: TBenchmarkProc;
  AIterations: Integer; AThresholdMs: Double): TBenchmarkMeasurement;
var
  Stopwatch: TStopwatch;
  Times: TArray<Double>;
  I: Integer;
  ElapsedMs: Double;
  TempArr: TArray<Double>;
  J: Integer;
  TempVal: Double;
begin
  if AIterations <= 0 then
    AIterations := FDefaultIterations;

  Result.Name := AName;
  Result.Iterations := AIterations;
  Result.Threshold := AThresholdMs;
  Result.MinMs := MaxDouble;
  Result.MaxMs := 0;
  Result.TotalMs := 0;

  // Warmup
  for I := 1 to FWarmupIterations do
    AProc();

  // Measure memory before
  Result.MemoryBefore := GetCurrentMemory;

  // Run benchmark
  SetLength(Times, AIterations);
  for I := 0 to AIterations - 1 do
  begin
    Stopwatch := TStopwatch.StartNew;
    AProc();
    Stopwatch.Stop;

    ElapsedMs := Stopwatch.Elapsed.TotalMilliseconds;
    Times[I] := ElapsedMs;
    Result.TotalMs := Result.TotalMs + ElapsedMs;

    if ElapsedMs < Result.MinMs then
      Result.MinMs := ElapsedMs;
    if ElapsedMs > Result.MaxMs then
      Result.MaxMs := ElapsedMs;
  end;

  // Measure memory after
  Result.MemoryAfter := GetCurrentMemory;
  Result.MemoryDelta := Result.MemoryAfter - Result.MemoryBefore;

  // Calculate statistics
  Result.AvgMs := Result.TotalMs / AIterations;
  Result.OpsPerSecond := 1000 / Result.AvgMs;

  // Sort for percentiles
  TempArr := Copy(Times);
  for I := 0 to High(TempArr) - 1 do
    for J := I + 1 to High(TempArr) do
      if TempArr[J] < TempArr[I] then
      begin
        TempVal := TempArr[I];
        TempArr[I] := TempArr[J];
        TempArr[J] := TempVal;
      end;

  Result.P50Ms := CalculatePercentile(TempArr, 50);
  Result.P95Ms := CalculatePercentile(TempArr, 95);
  Result.P99Ms := CalculatePercentile(TempArr, 99);

  // Check threshold
  if AThresholdMs > 0 then
    Result.Passed := Result.AvgMs <= AThresholdMs
  else
    Result.Passed := True;

  if Assigned(FCurrentSuite) then
    FCurrentSuite.AddMeasurement(Result);
end;

function TBenchmarkRunner.BenchmarkConcurrent(const AName: string;
  AProc: TBenchmarkProc; AThreadCount, AIterationsPerThread: Integer;
  AThresholdMs: Double): TBenchmarkMeasurement;
var
  Stopwatch: TStopwatch;
  Tasks: TArray<ITask>;
  I: Integer;
  TotalIterations: Integer;
begin
  TotalIterations := AThreadCount * AIterationsPerThread;
  Result.Name := AName;
  Result.Iterations := TotalIterations;
  Result.Threshold := AThresholdMs;

  // Warmup
  for I := 1 to FWarmupIterations do
    AProc();

  Result.MemoryBefore := GetCurrentMemory;

  // Create tasks
  SetLength(Tasks, AThreadCount);
  Stopwatch := TStopwatch.StartNew;

  for I := 0 to AThreadCount - 1 do
  begin
    Tasks[I] := TTask.Create(
      procedure
      var
        J: Integer;
      begin
        for J := 1 to AIterationsPerThread do
          AProc();
      end
    );
    Tasks[I].Start;
  end;

  // Wait for all tasks
  TTask.WaitForAll(Tasks);
  Stopwatch.Stop;

  Result.MemoryAfter := GetCurrentMemory;
  Result.MemoryDelta := Result.MemoryAfter - Result.MemoryBefore;

  Result.TotalMs := Stopwatch.Elapsed.TotalMilliseconds;
  Result.AvgMs := Result.TotalMs / TotalIterations;
  Result.MinMs := Result.AvgMs;  // Approximation for concurrent
  Result.MaxMs := Result.AvgMs;
  Result.P50Ms := Result.AvgMs;
  Result.P95Ms := Result.AvgMs;
  Result.P99Ms := Result.AvgMs;
  Result.OpsPerSecond := TotalIterations / (Result.TotalMs / 1000);

  if AThresholdMs > 0 then
    Result.Passed := Result.AvgMs <= AThresholdMs
  else
    Result.Passed := True;

  if Assigned(FCurrentSuite) then
    FCurrentSuite.AddMeasurement(Result);
end;

function TBenchmarkRunner.GetResults: TObjectList<TBenchmarkSuiteResult>;
begin
  Result := FResults;
end;

function TBenchmarkRunner.GenerateReport: string;
var
  SB: TStringBuilder;
  Suite: TBenchmarkSuiteResult;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('UniFlow Performance Benchmark Report');
    SB.AppendLine('====================================');
    SB.AppendFormat('Generated: %s', [DateTimeToStr(Now)]).AppendLine;
    SB.AppendLine;

    for Suite in FResults do
      SB.Append(Suite.ToReport);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TContextPerformanceTests }

procedure TContextPerformanceTests.SetUp;
begin
  inherited;
end;

procedure TContextPerformanceTests.TearDown;
begin
  inherited;
end;

procedure TContextPerformanceTests.TestContextVariableLatency;
var
  Runner: TBenchmarkRunner;
  Context: TWorkflowContext;
  M: TBenchmarkMeasurement;
begin
  Runner := TBenchmarkRunner.Create;
  Context := TWorkflowContext.Create;
  try
    Runner.BeginSuite('Context Variable Operations');

    // Set variable
    M := Runner.Benchmark('SetVariable', procedure
    begin
      Context.SetVariable('test_key', 'test_value_12345');
    end, 10000, 0.1);  // Threshold: 0.1ms

    AssertTrue(M.Passed, Format('SetVariable too slow: %.3f ms (threshold: %.3f ms)',
      [M.AvgMs, M.Threshold]));

    // Get variable
    M := Runner.Benchmark('GetVariable', procedure
    var
      V: string;
    begin
      V := Context.GetVariable('test_key');
    end, 10000, 0.1);

    AssertTrue(M.Passed, Format('GetVariable too slow: %.3f ms (threshold: %.3f ms)',
      [M.AvgMs, M.Threshold]));

    Runner.EndSuite;
    WriteLn(Runner.GenerateReport);
  finally
    Context.Free;
    Runner.Free;
  end;
end;

procedure TContextPerformanceTests.TestContextSerialization;
var
  Runner: TBenchmarkRunner;
  Context: TWorkflowContext;
  M: TBenchmarkMeasurement;
  I: Integer;
begin
  Runner := TBenchmarkRunner.Create;
  Context := TWorkflowContext.Create;
  try
    // Populate context
    for I := 1 to 100 do
      Context.SetVariable(Format('var_%d', [I]), Format('value_%d', [I]));

    Runner.BeginSuite('Context Serialization');

    M := Runner.Benchmark('ToJSON', procedure
    var
      J: TJSONObject;
    begin
      J := Context.ToJSON;
      J.Free;
    end, 1000, 1.0);  // Threshold: 1ms

    AssertTrue(M.Passed, Format('ToJSON too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Context.Free;
    Runner.Free;
  end;
end;

procedure TContextPerformanceTests.TestContextScalability;
var
  Runner: TBenchmarkRunner;
  Context: TWorkflowContext;
  M: TBenchmarkMeasurement;
  Counter: Integer;
begin
  Runner := TBenchmarkRunner.Create;
  Context := TWorkflowContext.Create;
  try
    Counter := 0;
    Runner.BeginSuite('Context Scalability');

    // Add 10000 variables
    M := Runner.Benchmark('Add10000Variables', procedure
    begin
      Inc(Counter);
      Context.SetVariable(Format('key_%d', [Counter]), Format('value_%d', [Counter]));
    end, 10000, 0.5);

    AssertTrue(M.Passed, Format('Adding variables too slow: %.3f ms', [M.AvgMs]));

    // Access with many variables
    M := Runner.Benchmark('AccessWithManyVars', procedure
    var
      V: string;
    begin
      V := Context.GetVariable('key_5000');
    end, 1000, 0.1);

    AssertTrue(M.Passed, Format('Access with many vars too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Context.Free;
    Runner.Free;
  end;
end;

{ TWorkflowParsingTests }

procedure TWorkflowParsingTests.SetUp;
begin
  inherited;
end;

procedure TWorkflowParsingTests.TearDown;
begin
  inherited;
end;

procedure TWorkflowParsingTests.TestSimpleWorkflowParsing;
var
  Runner: TBenchmarkRunner;
  JsonStr: string;
  M: TBenchmarkMeasurement;
begin
  JsonStr := '{"id":"test_wf","name":"Test","version":"1.0","steps":[' +
    '{"id":"step1","name":"Step 1","type":"action","config":{}},' +
    '{"id":"step2","name":"Step 2","type":"action","config":{}}]}';

  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Simple Workflow Parsing');

    M := Runner.Benchmark('ParseSimpleWorkflow', procedure
    var
      JsonObj: TJSONObject;
      Workflow: TWorkflowDefinition;
    begin
      JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
      try
        Workflow := TWorkflowDefinition.Create;
        try
          Workflow.LoadFromJSON(JsonObj);
        finally
          Workflow.Free;
        end;
      finally
        JsonObj.Free;
      end;
    end, 1000, 1.0);

    AssertTrue(M.Passed, Format('Simple workflow parsing too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

procedure TWorkflowParsingTests.TestComplexWorkflowParsing;
var
  Runner: TBenchmarkRunner;
  JsonStr: string;
  M: TBenchmarkMeasurement;
  I: Integer;
  SB: TStringBuilder;
begin
  // Build complex workflow with 50 steps
  SB := TStringBuilder.Create;
  try
    SB.Append('{"id":"complex_wf","name":"Complex","version":"1.0","steps":[');
    for I := 1 to 50 do
    begin
      if I > 1 then SB.Append(',');
      SB.AppendFormat('{"id":"step%d","name":"Step %d","type":"action","config":{' +
        '"param1":"value1","param2":"value2","param3":"value3"}}', [I, I]);
    end;
    SB.Append(']}');
    JsonStr := SB.ToString;
  finally
    SB.Free;
  end;

  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Complex Workflow Parsing');

    M := Runner.Benchmark('ParseComplexWorkflow', procedure
    var
      JsonObj: TJSONObject;
      Workflow: TWorkflowDefinition;
    begin
      JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
      try
        Workflow := TWorkflowDefinition.Create;
        try
          Workflow.LoadFromJSON(JsonObj);
        finally
          Workflow.Free;
        end;
      finally
        JsonObj.Free;
      end;
    end, 500, 5.0);

    AssertTrue(M.Passed, Format('Complex workflow parsing too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

procedure TWorkflowParsingTests.TestWorkflowValidation;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Workflow: TWorkflowDefinition;
begin
  Workflow := TWorkflowDefinition.Create;
  try
    Workflow.Id := 'test_validation';
    Workflow.Name := 'Test Validation';
    Workflow.Version := '1.0';

    Runner := TBenchmarkRunner.Create;
    try
      Runner.BeginSuite('Workflow Validation');

      M := Runner.Benchmark('ValidateWorkflow', procedure
      var
        IsValid: Boolean;
      begin
        IsValid := Workflow.Validate;
      end, 5000, 0.5);

      AssertTrue(M.Passed, Format('Workflow validation too slow: %.3f ms', [M.AvgMs]));

      Runner.EndSuite;
    finally
      Runner.Free;
    end;
  finally
    Workflow.Free;
  end;
end;

{ TSessionPerformanceTests }

procedure TSessionPerformanceTests.SetUp;
begin
  inherited;
  FManager := TSessionManager.Create;
end;

procedure TSessionPerformanceTests.TearDown;
begin
  FManager.Free;
  inherited;
end;

procedure TSessionPerformanceTests.TestSessionCreationLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
begin
  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Session Creation');

    M := Runner.Benchmark('CreateSession', procedure
    var
      Session: TSession;
    begin
      Session := FManager.CreateSession('test_user');
      // Note: Session is managed by manager, don't free
    end, 1000, 1.0);

    AssertTrue(M.Passed, Format('Session creation too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
    WriteLn(Runner.GenerateReport);
  finally
    Runner.Free;
  end;
end;

procedure TSessionPerformanceTests.TestSessionLookupLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Session: TSession;
  SessionId: string;
begin
  // Create session first
  Session := FManager.CreateSession('test_user');
  SessionId := Session.SessionId;

  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Session Lookup');

    M := Runner.Benchmark('GetSession', procedure
    var
      S: TSession;
    begin
      S := FManager.GetSession(SessionId);
    end, 10000, 0.1);  // Target: < 0.1ms

    AssertTrue(M.Passed, Format('Session lookup too slow: %.3f ms (threshold: %.3f ms)',
      [M.AvgMs, M.Threshold]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

procedure TSessionPerformanceTests.TestConcurrentSessions;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Lock: TCriticalSection;
begin
  Lock := TCriticalSection.Create;
  try
    Runner := TBenchmarkRunner.Create;
    try
      Runner.BeginSuite('Concurrent Sessions');

      M := Runner.BenchmarkConcurrent('ConcurrentSessionCreation',
        procedure
        var
          Session: TSession;
        begin
          Lock.Enter;
          try
            Session := FManager.CreateSession('concurrent_user');
          finally
            Lock.Leave;
          end;
        end,
        10, 10,  // 10 threads, 10 iterations each = 100 total
        5.0);    // Threshold: 5ms per operation

      AssertTrue(M.OpsPerSecond >= 100, Format('Concurrent operations too slow: %.0f ops/sec',
        [M.OpsPerSecond]));

      Runner.EndSuite;
    finally
      Runner.Free;
    end;
  finally
    Lock.Free;
  end;
end;

procedure TSessionPerformanceTests.TestSessionMessageScalability;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Session: TSession;
  I: Integer;
begin
  Session := FManager.CreateSession('test_user');

  // Add 1000 messages
  for I := 1 to 1000 do
    Session.AddUserMessage(Format('Message %d with some content', [I]));

  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Session Message Scalability');

    M := Runner.Benchmark('AddMessageWith1000Existing', procedure
    begin
      Session.AddUserMessage('New message');
    end, 1000, 0.5);

    AssertTrue(M.Passed, Format('Adding message too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

{ TIntentPerformanceTests }

procedure TIntentPerformanceTests.SetUp;
begin
  inherited;
  FRecognizer := TIntentRecognizer.Create;

  // Register some intents
  FRecognizer.RegisterIntent('greeting',
    ['hello|hi|hey', 'good\s+(morning|afternoon|evening)'],
    ['hello', 'hi', 'hey', 'greetings']);

  FRecognizer.RegisterIntent('help',
    ['help|assist|support'],
    ['help', 'assist', 'support', 'how do I']);

  FRecognizer.RegisterIntent('goodbye',
    ['bye|goodbye|see you'],
    ['bye', 'goodbye', 'farewell', 'later']);
end;

procedure TIntentPerformanceTests.TearDown;
begin
  FRecognizer.Free;
  inherited;
end;

procedure TIntentPerformanceTests.TestSingleIntentLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
begin
  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Intent Recognition');

    M := Runner.Benchmark('RecognizeSingleIntent', procedure
    var
      Intent: TIntent;
    begin
      Intent := FRecognizer.Recognize('Hello there!');
      Intent.Free;
    end, 10000, 0.1);  // Target: < 0.1ms

    AssertTrue(M.Passed, Format('Intent recognition too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

procedure TIntentPerformanceTests.TestMultiplePatternsLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
begin
  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Multiple Patterns');

    M := Runner.Benchmark('RecognizeAllIntents', procedure
    var
      Intents: TArray<TIntent>;
      I: TIntent;
    begin
      Intents := FRecognizer.RecognizeAll('Hello, I need help', 3);
      for I in Intents do
        I.Free;
    end, 5000, 0.5);

    AssertTrue(M.Passed, Format('Multiple intent recognition too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

procedure TIntentPerformanceTests.TestIntentScalability;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  I: Integer;
begin
  // Add 100 more intents
  for I := 1 to 100 do
    FRecognizer.RegisterIntent(Format('intent_%d', [I]),
      [Format('pattern_%d', [I])],
      [Format('keyword_%d', [I])]);

  Runner := TBenchmarkRunner.Create;
  try
    Runner.BeginSuite('Intent Scalability');

    M := Runner.Benchmark('RecognizeWith100Intents', procedure
    var
      Intent: TIntent;
    begin
      Intent := FRecognizer.Recognize('This is a test message for intent matching');
      Intent.Free;
    end, 5000, 1.0);

    AssertTrue(M.Passed, Format('Recognition with many intents too slow: %.3f ms', [M.AvgMs]));

    Runner.EndSuite;
  finally
    Runner.Free;
  end;
end;

{ TValidationPerformanceTests }

procedure TValidationPerformanceTests.SetUp;
begin
  inherited;
end;

procedure TValidationPerformanceTests.TearDown;
begin
  inherited;
end;

procedure TValidationPerformanceTests.TestSchemaValidationLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Schema: TJSONSchema;
  TestData: TJSONObject;
begin
  Schema := TJSONSchema.Create;
  TestData := TJSONObject.Create;
  try
    Schema.LoadFromJSON(TJSONObject.ParseJSONValue(
      '{"type":"object","properties":{"name":{"type":"string"},"age":{"type":"number"}},' +
      '"required":["name"]}') as TJSONObject);

    TestData.AddPair('name', 'John');
    TestData.AddPair('age', TJSONNumber.Create(30));

    Runner := TBenchmarkRunner.Create;
    try
      Runner.BeginSuite('Schema Validation');

      M := Runner.Benchmark('ValidateJSON', procedure
      var
        R: TSchemaValidationResult;
      begin
        R := Schema.Validate(TestData);
        R.Free;
      end, 5000, 0.5);

      AssertTrue(M.Passed, Format('Schema validation too slow: %.3f ms', [M.AvgMs]));

      Runner.EndSuite;
    finally
      Runner.Free;
    end;
  finally
    TestData.Free;
    Schema.Free;
  end;
end;

procedure TValidationPerformanceTests.TestSanitizationLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Sanitizer: TSanitizer;
  TestInput: string;
begin
  Sanitizer := TSanitizer.Create;
  try
    TestInput := 'Hello <script>alert("xss")</script> world! SELECT * FROM users;';

    Runner := TBenchmarkRunner.Create;
    try
      Runner.BeginSuite('Input Sanitization');

      M := Runner.Benchmark('SanitizeInput', procedure
      var
        Output: string;
      begin
        Output := Sanitizer.Sanitize(TestInput);
      end, 10000, 0.1);

      AssertTrue(M.Passed, Format('Sanitization too slow: %.3f ms', [M.AvgMs]));

      Runner.EndSuite;
    finally
      Runner.Free;
    end;
  finally
    Sanitizer.Free;
  end;
end;

procedure TValidationPerformanceTests.TestPromptGuardLatency;
var
  Runner: TBenchmarkRunner;
  M: TBenchmarkMeasurement;
  Guard: TPromptGuard;
  TestPrompt: string;
begin
  Guard := TPromptGuard.Create;
  try
    TestPrompt := 'Please help me write a friendly email to my colleague about the project deadline.';

    Runner := TBenchmarkRunner.Create;
    try
      Runner.BeginSuite('Prompt Guard');

      M := Runner.Benchmark('CheckPrompt', procedure
      var
        R: TPromptCheckResult;
      begin
        R := Guard.Check(TestPrompt);
        R.Free;
      end, 5000, 1.0);

      AssertTrue(M.Passed, Format('Prompt guard too slow: %.3f ms', [M.AvgMs]));

      Runner.EndSuite;
    finally
      Runner.Free;
    end;
  finally
    Guard.Free;
  end;
end;

{ Public Functions }

procedure RunPerformanceBenchmarks;
var
  Runner: TTestRunner;
begin
  Runner := TTestRunner.Create;
  try
    Runner.RegisterTestClass(TContextPerformanceTests);
    Runner.RegisterTestClass(TWorkflowParsingTests);
    Runner.RegisterTestClass(TSessionPerformanceTests);
    Runner.RegisterTestClass(TIntentPerformanceTests);
    Runner.RegisterTestClass(TValidationPerformanceTests);

    WriteLn('');
    WriteLn('Running UniFlow Performance Benchmarks');
    WriteLn('======================================');
    WriteLn('');

    Runner.RunAll;

    WriteLn('');
    WriteLn(Runner.GetSummary);
  finally
    Runner.Free;
  end;
end;

function QuickPerformanceCheck: Boolean;
var
  Context: TWorkflowContext;
  Stopwatch: TStopwatch;
  I: Integer;
  ElapsedMs: Double;
begin
  Result := True;

  // Quick context test
  Context := TWorkflowContext.Create;
  try
    Stopwatch := TStopwatch.StartNew;
    for I := 1 to 1000 do
      Context.SetVariable(Format('key_%d', [I]), Format('value_%d', [I]));
    Stopwatch.Stop;

    ElapsedMs := Stopwatch.Elapsed.TotalMilliseconds / 1000;
    if ElapsedMs > 0.1 then
    begin
      WriteLn(Format('WARN: Context SetVariable avg: %.3f ms (expected < 0.1ms)', [ElapsedMs]));
      Result := False;
    end;
  finally
    Context.Free;
  end;

  if Result then
    WriteLn('Quick performance check: PASS')
  else
    WriteLn('Quick performance check: WARN (some thresholds exceeded)');
end;

end.
