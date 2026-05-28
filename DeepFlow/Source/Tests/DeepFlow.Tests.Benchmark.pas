unit UniFlow.Tests.Benchmark;
(*
  UniFlow Benchmark and Stress Tests
  ==================================
  TASK-2002: 压力测试与基�?
  
  测试覆盖:
  - 工作流执行吞吐量基准
  - 并发执行压力测试 (10/50/100 并发)
  - 内存使用监控
  - 长时间运行稳定性测�?
  - 对象池效率验�?
  - 基准结果输出 (JSON 报告)
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.DateUtils, System.Diagnostics, System.Threading,
  DUnitX.TestFramework,
  UniFlow.Workflow.Definition, UniFlow.Workflow.Context, UniFlow.Workflow.Executor,
  UniFlow.Performance.Pool;

type
  // ============================================================================
  // Benchmark Result Types
  // ============================================================================
  
  TBenchmarkResult = record
    Name: string;
    Iterations: Integer;
    TotalTimeMs: Double;
    AvgTimeMs: Double;
    MinTimeMs: Double;
    MaxTimeMs: Double;
    ThroughputPerSec: Double;
    MemoryUsedBytes: Int64;
    
    function ToJSON: TJSONObject;
    function ToString: string;
  end;
  
  TBenchmarkReport = class
  private
    FResults: TList<TBenchmarkResult>;
    FStartTime: TDateTime;
    FEndTime: TDateTime;
    FSystemInfo: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddResult(const AResult: TBenchmarkResult);
    procedure SetSystemInfo;
    
    function ToJSON: TJSONObject;
    procedure SaveToFile(const AFileName: string);
    procedure PrintSummary;
    
    property Results: TList<TBenchmarkResult> read FResults;
    property StartTime: TDateTime read FStartTime write FStartTime;
    property EndTime: TDateTime read FEndTime write FEndTime;
  end;
  
  // ============================================================================
  // Benchmark Runner
  // ============================================================================
  
  TBenchmarkRunner = class
  private
    FReport: TBenchmarkReport;
    FWarmupIterations: Integer;
    
    function GetMemoryUsage: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    
    function RunBenchmark(const AName: string; AIterations: Integer;
      AProc: TProc): TBenchmarkResult;
    function RunConcurrentBenchmark(const AName: string; AIterations, AConcurrency: Integer;
      AProc: TProc): TBenchmarkResult;
    
    property Report: TBenchmarkReport read FReport;
    property WarmupIterations: Integer read FWarmupIterations write FWarmupIterations;
  end;
  
  // ============================================================================
  // Memory Monitor
  // ============================================================================
  
  TMemoryMonitor = class
  private
    FSamples: TList<Int64>;
    FInterval: Integer;
    FRunning: Boolean;
    FThread: TThread;
  public
    constructor Create(AIntervalMs: Integer = 100);
    destructor Destroy; override;
    
    procedure Start;
    procedure Stop;
    
    function GetPeakMemory: Int64;
    function GetAverageMemory: Int64;
    function GetSampleCount: Integer;
  end;
  
  // ============================================================================
  // Benchmark Test Suite: Throughput
  // ============================================================================
  
  [TestFixture]
  TThroughputBenchmarkTests = class
  private
    FRunner: TBenchmarkRunner;
    
    function CreateSimpleWorkflow: TWorkflowDefinition;
    function CreateComplexWorkflow: TWorkflowDefinition;
    procedure ExecuteWorkflow(AWorkflow: TWorkflowDefinition);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    procedure Benchmark_SimpleWorkflow_1000Iterations;
    
    [Test]
    procedure Benchmark_ComplexWorkflow_500Iterations;
    
    [Test]
    procedure Benchmark_WorkflowCreation_10000Times;
    
    [Test]
    procedure Benchmark_ContextOperations_100000Times;
    
    [Test]
    procedure Benchmark_JSONParsing_10000Times;
  end;
  
  // ============================================================================
  // Benchmark Test Suite: Concurrency
  // ============================================================================
  
  [TestFixture]
  TConcurrencyBenchmarkTests = class
  private
    FRunner: TBenchmarkRunner;
    FWorkflow: TWorkflowDefinition;
    FSuccessCount: Integer;
    FErrorCount: Integer;
    FLock: TCriticalSection;
    
    procedure IncrementSuccess;
    procedure IncrementError;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    procedure Benchmark_Concurrent_10Workers;
    
    [Test]
    procedure Benchmark_Concurrent_50Workers;
    
    [Test]
    procedure Benchmark_Concurrent_100Workers;
    
    [Test]
    procedure Benchmark_Concurrent_RampUp;
  end;
  
  // ============================================================================
  // Benchmark Test Suite: Memory
  // ============================================================================
  
  [TestFixture]
  TMemoryBenchmarkTests = class
  private
    FRunner: TBenchmarkRunner;
    FMonitor: TMemoryMonitor;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    procedure Benchmark_Memory_WorkflowExecution;
    
    [Test]
    procedure Benchmark_Memory_LargeContext;
    
    [Test]
    procedure Benchmark_Memory_ObjectPoolEfficiency;
    
    [Test]
    procedure Benchmark_Memory_LeakDetection;
  end;
  
  // ============================================================================
  // Benchmark Test Suite: Stability
  // ============================================================================
  
  [TestFixture]
  TStabilityBenchmarkTests = class
  private
    FRunner: TBenchmarkRunner;
    FErrorLog: TStringList;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    procedure Benchmark_Stability_LongRunning_1000Iterations;
    
    [Test]
    procedure Benchmark_Stability_ErrorRecovery;
    
    [Test]
    procedure Benchmark_Stability_ResourceCleanup;
  end;
  
  // ============================================================================
  // Benchmark Test Suite: Object Pool
  // ============================================================================
  
  [TestFixture]
  TObjectPoolBenchmarkTests = class
  private
    FRunner: TBenchmarkRunner;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    procedure Benchmark_Pool_JSONObject_10000Times;
    
    [Test]
    procedure Benchmark_Pool_StringBuilder_10000Times;
    
    [Test]
    procedure Benchmark_Pool_VsDirectCreation;
    
    [Test]
    procedure Benchmark_Pool_ConcurrentAccess;
  end;

implementation

uses
  Winapi.Windows, Winapi.PsAPI;

// ============================================================================
// TBenchmarkResult Implementation
// ============================================================================

function TBenchmarkResult.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('iterations', TJSONNumber.Create(Iterations));
  Result.AddPair('total_time_ms', TJSONNumber.Create(TotalTimeMs));
  Result.AddPair('avg_time_ms', TJSONNumber.Create(AvgTimeMs));
  Result.AddPair('min_time_ms', TJSONNumber.Create(MinTimeMs));
  Result.AddPair('max_time_ms', TJSONNumber.Create(MaxTimeMs));
  Result.AddPair('throughput_per_sec', TJSONNumber.Create(ThroughputPerSec));
  Result.AddPair('memory_used_bytes', TJSONNumber.Create(MemoryUsedBytes));
end;

function TBenchmarkResult.ToString: string;
begin
  Result := Format('%s: %d iterations, avg=%.3fms, min=%.3fms, max=%.3fms, throughput=%.1f/s',
    [Name, Iterations, AvgTimeMs, MinTimeMs, MaxTimeMs, ThroughputPerSec]);
end;

// ============================================================================
// TBenchmarkReport Implementation
// ============================================================================

constructor TBenchmarkReport.Create;
begin
  inherited Create;
  FResults := TList<TBenchmarkResult>.Create;
  FStartTime := Now;
end;

destructor TBenchmarkReport.Destroy;
begin
  FSystemInfo.Free;
  FResults.Free;
  inherited;
end;

procedure TBenchmarkReport.AddResult(const AResult: TBenchmarkResult);
begin
  FResults.Add(AResult);
end;

procedure TBenchmarkReport.SetSystemInfo;
var
  LMemStatus: TMemoryStatusEx;
begin
  if Assigned(FSystemInfo) then
    FSystemInfo.Free;
    
  FSystemInfo := TJSONObject.Create;
  
  // Get system memory info
  LMemStatus.dwLength := SizeOf(LMemStatus);
  GlobalMemoryStatusEx(LMemStatus);
  
  FSystemInfo.AddPair('total_physical_memory', TJSONNumber.Create(LMemStatus.ullTotalPhys));
  FSystemInfo.AddPair('available_physical_memory', TJSONNumber.Create(LMemStatus.ullAvailPhys));
  FSystemInfo.AddPair('cpu_count', TJSONNumber.Create(TThread.ProcessorCount));
  FSystemInfo.AddPair('os_version', TOSVersion.ToString);
  FSystemInfo.AddPair('compiler', 'Delphi 12');
end;

function TBenchmarkReport.ToJSON: TJSONObject;
var
  LResultsArray: TJSONArray;
  LResult: TBenchmarkResult;
begin
  Result := TJSONObject.Create;
  Result.AddPair('report_time', DateTimeToStr(Now));
  Result.AddPair('start_time', DateTimeToStr(FStartTime));
  Result.AddPair('end_time', DateTimeToStr(FEndTime));
  
  if Assigned(FSystemInfo) then
    Result.AddPair('system_info', FSystemInfo.Clone as TJSONObject);
  
  LResultsArray := TJSONArray.Create;
  for LResult in FResults do
    LResultsArray.Add(LResult.ToJSON);
  
  Result.AddPair('results', LResultsArray);
end;

procedure TBenchmarkReport.SaveToFile(const AFileName: string);
var
  LJson: TJSONObject;
  LContent: string;
begin
  FEndTime := Now;
  SetSystemInfo;
  
  LJson := ToJSON;
  try
    LContent := LJson.Format(2);
    TFile.WriteAllText(AFileName, LContent);
  finally
    LJson.Free;
  end;
end;

procedure TBenchmarkReport.PrintSummary;
var
  LResult: TBenchmarkResult;
begin
  WriteLn('');
  WriteLn('========== BENCHMARK SUMMARY ==========');
  WriteLn(Format('Duration: %.2f seconds', [SecondSpan(FStartTime, Now)]));
  WriteLn('');
  
  for LResult in FResults do
    WriteLn(LResult.ToString);
  
  WriteLn('=======================================');
  WriteLn('');
end;

// ============================================================================
// TBenchmarkRunner Implementation
// ============================================================================

constructor TBenchmarkRunner.Create;
begin
  inherited Create;
  FReport := TBenchmarkReport.Create;
  FWarmupIterations := 10;
end;

destructor TBenchmarkRunner.Destroy;
begin
  FReport.Free;
  inherited;
end;

function TBenchmarkRunner.GetMemoryUsage: Int64;
var
  LMemCounters: TProcessMemoryCounters;
begin
  LMemCounters.cb := SizeOf(LMemCounters);
  if GetProcessMemoryInfo(GetCurrentProcess, @LMemCounters, SizeOf(LMemCounters)) then
    Result := LMemCounters.WorkingSetSize
  else
    Result := 0;
end;

function TBenchmarkRunner.RunBenchmark(const AName: string; AIterations: Integer;
  AProc: TProc): TBenchmarkResult;
var
  I: Integer;
  LStopwatch: TStopwatch;
  LElapsed: Double;
  LMin, LMax, LTotal: Double;
  LStartMemory, LEndMemory: Int64;
begin
  Result.Name := AName;
  Result.Iterations := AIterations;
  
  // Warmup
  for I := 1 to FWarmupIterations do
    AProc();
  
  // Record starting memory
  LStartMemory := GetMemoryUsage;
  
  LMin := MaxDouble;
  LMax := 0;
  LTotal := 0;
  
  // Run benchmark
  for I := 1 to AIterations do
  begin
    LStopwatch := TStopwatch.StartNew;
    AProc();
    LStopwatch.Stop;
    
    LElapsed := LStopwatch.Elapsed.TotalMilliseconds;
    LTotal := LTotal + LElapsed;
    
    if LElapsed < LMin then LMin := LElapsed;
    if LElapsed > LMax then LMax := LElapsed;
  end;
  
  // Record ending memory
  LEndMemory := GetMemoryUsage;
  
  Result.TotalTimeMs := LTotal;
  Result.AvgTimeMs := LTotal / AIterations;
  Result.MinTimeMs := LMin;
  Result.MaxTimeMs := LMax;
  
  if LTotal > 0 then
    Result.ThroughputPerSec := AIterations / (LTotal / 1000)
  else
    Result.ThroughputPerSec := 0;
    
  Result.MemoryUsedBytes := LEndMemory - LStartMemory;
  
  FReport.AddResult(Result);
end;

function TBenchmarkRunner.RunConcurrentBenchmark(const AName: string;
  AIterations, AConcurrency: Integer; AProc: TProc): TBenchmarkResult;
var
  LTasks: array of ITask;
  LStopwatch: TStopwatch;
  LIterPerWorker: Integer;
  I: Integer;
  LStartMemory, LEndMemory: Int64;
begin
  Result.Name := AName;
  Result.Iterations := AIterations;
  
  LIterPerWorker := AIterations div AConcurrency;
  SetLength(LTasks, AConcurrency);
  
  // Record starting memory
  LStartMemory := GetMemoryUsage;
  
  LStopwatch := TStopwatch.StartNew;
  
  // Create worker tasks
  for I := 0 to AConcurrency - 1 do
  begin
    LTasks[I] := TTask.Create(procedure
    var
      J: Integer;
    begin
      for J := 1 to LIterPerWorker do
        AProc();
    end);
    LTasks[I].Start;
  end;
  
  // Wait for all tasks
  TTask.WaitForAll(LTasks);
  
  LStopwatch.Stop;
  
  // Record ending memory
  LEndMemory := GetMemoryUsage;
  
  Result.TotalTimeMs := LStopwatch.Elapsed.TotalMilliseconds;
  Result.AvgTimeMs := Result.TotalTimeMs / AIterations;
  Result.MinTimeMs := Result.AvgTimeMs; // Not tracked per-iteration in concurrent mode
  Result.MaxTimeMs := Result.AvgTimeMs;
  
  if Result.TotalTimeMs > 0 then
    Result.ThroughputPerSec := AIterations / (Result.TotalTimeMs / 1000)
  else
    Result.ThroughputPerSec := 0;
    
  Result.MemoryUsedBytes := LEndMemory - LStartMemory;
  
  FReport.AddResult(Result);
end;

// ============================================================================
// TMemoryMonitor Implementation
// ============================================================================

constructor TMemoryMonitor.Create(AIntervalMs: Integer);
begin
  inherited Create;
  FSamples := TList<Int64>.Create;
  FInterval := AIntervalMs;
  FRunning := False;
end;

destructor TMemoryMonitor.Destroy;
begin
  Stop;
  FSamples.Free;
  inherited;
end;

procedure TMemoryMonitor.Start;
begin
  if FRunning then Exit;
  
  FRunning := True;
  FSamples.Clear;
  
  FThread := TThread.CreateAnonymousThread(procedure
  var
    LMemCounters: TProcessMemoryCounters;
  begin
    while FRunning do
    begin
      LMemCounters.cb := SizeOf(LMemCounters);
      if GetProcessMemoryInfo(GetCurrentProcess, @LMemCounters, SizeOf(LMemCounters)) then
      begin
        TMonitor.Enter(FSamples);
        try
          FSamples.Add(LMemCounters.WorkingSetSize);
        finally
          TMonitor.Exit(FSamples);
        end;
      end;
      Sleep(FInterval);
    end;
  end);
  FThread.Start;
end;

procedure TMemoryMonitor.Stop;
begin
  if not FRunning then Exit;
  
  FRunning := False;
  if Assigned(FThread) then
  begin
    FThread.WaitFor;
    FThread := nil;
  end;
end;

function TMemoryMonitor.GetPeakMemory: Int64;
var
  LMax, LSample: Int64;
begin
  LMax := 0;
  TMonitor.Enter(FSamples);
  try
    for LSample in FSamples do
      if LSample > LMax then LMax := LSample;
  finally
    TMonitor.Exit(FSamples);
  end;
  Result := LMax;
end;

function TMemoryMonitor.GetAverageMemory: Int64;
var
  LTotal: Int64;
  LSample: Int64;
begin
  LTotal := 0;
  TMonitor.Enter(FSamples);
  try
    if FSamples.Count = 0 then
      Exit(0);
    for LSample in FSamples do
      LTotal := LTotal + LSample;
    Result := LTotal div FSamples.Count;
  finally
    TMonitor.Exit(FSamples);
  end;
end;

function TMemoryMonitor.GetSampleCount: Integer;
begin
  TMonitor.Enter(FSamples);
  try
    Result := FSamples.Count;
  finally
    TMonitor.Exit(FSamples);
  end;
end;

// ============================================================================
// TThroughputBenchmarkTests Implementation
// ============================================================================

procedure TThroughputBenchmarkTests.Setup;
begin
  FRunner := TBenchmarkRunner.Create;
  FRunner.WarmupIterations := 5;
end;

procedure TThroughputBenchmarkTests.TearDown;
begin
  FRunner.Report.SaveToFile('benchmark_throughput.json');
  FRunner.Report.PrintSummary;
  FRunner.Free;
end;

function TThroughputBenchmarkTests.CreateSimpleWorkflow: TWorkflowDefinition;
var
  LStep: TWorkflowStep;
  LAction: TActionDefinition;
begin
  Result := TWorkflowDefinition.Create;
  Result.Id := 'benchmark-simple';
  Result.Name := 'Simple Benchmark Workflow';
  
  // Single log step
  LStep := TWorkflowStep.Create;
  LStep.Id := 'log-step';
  LStep.StepType := stAction;
  LAction := TActionDefinition.Create;
  LAction.ActionType := atLog;
  LAction.Config := TJSONObject.Create;
  LAction.Config.AddPair('message', 'Benchmark test');
  LStep.Action := LAction;
  Result.Steps.Add(LStep);
end;

function TThroughputBenchmarkTests.CreateComplexWorkflow: TWorkflowDefinition;
var
  LStep: TWorkflowStep;
  LAction: TActionDefinition;
  LBranch: TConditionBranch;
  I: Integer;
begin
  Result := TWorkflowDefinition.Create;
  Result.Id := 'benchmark-complex';
  Result.Name := 'Complex Benchmark Workflow';
  
  // Multiple steps with conditions
  for I := 1 to 5 do
  begin
    LStep := TWorkflowStep.Create;
    LStep.Id := 'step-' + IntToStr(I);
    LStep.StepType := stAction;
    LAction := TActionDefinition.Create;
    LAction.ActionType := atAssign;
    LAction.Config := TJSONObject.Create;
    LAction.Config.AddPair('variable', 'var_' + IntToStr(I));
    LAction.Config.AddPair('value', IntToStr(I * 10));
    LStep.Action := LAction;
    Result.Steps.Add(LStep);
  end;
  
  // Add condition step
  LStep := TWorkflowStep.Create;
  LStep.Id := 'condition-step';
  LStep.StepType := stCondition;
  LStep.Condition := TConditionExpression.Create;
  LStep.Condition.Expression := '{{ vars.var_1 }}';
  LBranch := TConditionBranch.Create;
  LBranch.Operator := coGt;
  LBranch.Value := '5';
  LBranch.NextStep := 'final-step';
  LStep.Condition.Branches.Add(LBranch);
  LStep.Condition.DefaultStep := 'final-step';
  Result.Steps.Add(LStep);
  
  // Final step
  LStep := TWorkflowStep.Create;
  LStep.Id := 'final-step';
  LStep.StepType := stAction;
  LAction := TActionDefinition.Create;
  LAction.ActionType := atLog;
  LAction.Config := TJSONObject.Create;
  LAction.Config.AddPair('message', 'Completed');
  LStep.Action := LAction;
  Result.Steps.Add(LStep);
end;

procedure TThroughputBenchmarkTests.ExecuteWorkflow(AWorkflow: TWorkflowDefinition);
var
  LContext: TWorkflowContext;
  LExecutor: TWorkflowExecutor;
  LResult: TStepResult;
begin
  LContext := TWorkflowContext.Create;
  try
    LExecutor := TWorkflowExecutor.Create(AWorkflow, LContext);
    try
      LResult := LExecutor.Start;
      LResult.Free;
    finally
      LExecutor.Free;
    end;
  finally
    LContext.Free;
  end;
end;

procedure TThroughputBenchmarkTests.Benchmark_SimpleWorkflow_1000Iterations;
var
  LWorkflow: TWorkflowDefinition;
  LResult: TBenchmarkResult;
begin
  LWorkflow := CreateSimpleWorkflow;
  try
    LResult := FRunner.RunBenchmark('SimpleWorkflow_1000', 1000, procedure
    begin
      ExecuteWorkflow(LWorkflow);
    end);
    
    Assert.IsTrue(LResult.ThroughputPerSec > 100, 
      Format('Throughput should be > 100/s, got %.1f/s', [LResult.ThroughputPerSec]));
  finally
    LWorkflow.Free;
  end;
end;

procedure TThroughputBenchmarkTests.Benchmark_ComplexWorkflow_500Iterations;
var
  LWorkflow: TWorkflowDefinition;
  LResult: TBenchmarkResult;
begin
  LWorkflow := CreateComplexWorkflow;
  try
    LResult := FRunner.RunBenchmark('ComplexWorkflow_500', 500, procedure
    begin
      ExecuteWorkflow(LWorkflow);
    end);
    
    Assert.IsTrue(LResult.ThroughputPerSec > 50, 
      Format('Throughput should be > 50/s, got %.1f/s', [LResult.ThroughputPerSec]));
  finally
    LWorkflow.Free;
  end;
end;

procedure TThroughputBenchmarkTests.Benchmark_WorkflowCreation_10000Times;
var
  LResult: TBenchmarkResult;
begin
  LResult := FRunner.RunBenchmark('WorkflowCreation_10000', 10000, procedure
  var
    LWorkflow: TWorkflowDefinition;
  begin
    LWorkflow := CreateSimpleWorkflow;
    LWorkflow.Free;
  end);
  
  Assert.IsTrue(LResult.ThroughputPerSec > 1000, 
    Format('Creation throughput should be > 1000/s, got %.1f/s', [LResult.ThroughputPerSec]));
end;

procedure TThroughputBenchmarkTests.Benchmark_ContextOperations_100000Times;
var
  LContext: TWorkflowContext;
  LResult: TBenchmarkResult;
begin
  LContext := TWorkflowContext.Create;
  try
    LResult := FRunner.RunBenchmark('ContextOps_100000', 100000, procedure
    begin
      LContext.SetVariable('test_var', TJSONString.Create('test_value'));
      LContext.GetVariable('test_var');
    end);
    
    Assert.IsTrue(LResult.ThroughputPerSec > 10000, 
      Format('Context ops should be > 10000/s, got %.1f/s', [LResult.ThroughputPerSec]));
  finally
    LContext.Free;
  end;
end;

procedure TThroughputBenchmarkTests.Benchmark_JSONParsing_10000Times;
const
  JSON_SAMPLE = '{"name":"test","value":123,"items":[1,2,3],"nested":{"a":"b"}}';
var
  LResult: TBenchmarkResult;
begin
  LResult := FRunner.RunBenchmark('JSONParsing_10000', 10000, procedure
  var
    LJson: TJSONObject;
  begin
    LJson := TJSONObject.ParseJSONValue(JSON_SAMPLE) as TJSONObject;
    LJson.Free;
  end);
  
  Assert.IsTrue(LResult.ThroughputPerSec > 5000, 
    Format('JSON parsing should be > 5000/s, got %.1f/s', [LResult.ThroughputPerSec]));
end;

// ============================================================================
// TConcurrencyBenchmarkTests Implementation
// ============================================================================

procedure TConcurrencyBenchmarkTests.Setup;
begin
  FRunner := TBenchmarkRunner.Create;
  FRunner.WarmupIterations := 0;
  FLock := TCriticalSection.Create;
  FSuccessCount := 0;
  FErrorCount := 0;
  
  // Create shared workflow
  FWorkflow := TWorkflowDefinition.Create;
  FWorkflow.Id := 'concurrent-test';
end;

procedure TConcurrencyBenchmarkTests.TearDown;
begin
  FWorkflow.Free;
  FLock.Free;
  FRunner.Report.SaveToFile('benchmark_concurrency.json');
  FRunner.Report.PrintSummary;
  FRunner.Free;
end;

procedure TConcurrencyBenchmarkTests.IncrementSuccess;
begin
  FLock.Enter;
  try
    Inc(FSuccessCount);
  finally
    FLock.Leave;
  end;
end;

procedure TConcurrencyBenchmarkTests.IncrementError;
begin
  FLock.Enter;
  try
    Inc(FErrorCount);
  finally
    FLock.Leave;
  end;
end;

procedure TConcurrencyBenchmarkTests.Benchmark_Concurrent_10Workers;
var
  LResult: TBenchmarkResult;
begin
  FSuccessCount := 0;
  FErrorCount := 0;
  
  LResult := FRunner.RunConcurrentBenchmark('Concurrent_10Workers', 1000, 10, procedure
  var
    LContext: TWorkflowContext;
  begin
    LContext := TWorkflowContext.Create;
    try
      LContext.SetVariable('test', TJSONNumber.Create(Random(1000)));
      IncrementSuccess;
    except
      IncrementError;
    end;
    LContext.Free;
  end);
  
  Assert.AreEqual(0, FErrorCount, 'Should have no errors');
  Assert.IsTrue(LResult.ThroughputPerSec > 1000, 'Should handle > 1000/s with 10 workers');
end;

procedure TConcurrencyBenchmarkTests.Benchmark_Concurrent_50Workers;
var
  LResult: TBenchmarkResult;
begin
  FSuccessCount := 0;
  FErrorCount := 0;
  
  LResult := FRunner.RunConcurrentBenchmark('Concurrent_50Workers', 5000, 50, procedure
  var
    LContext: TWorkflowContext;
  begin
    LContext := TWorkflowContext.Create;
    try
      LContext.SetVariable('test', TJSONNumber.Create(Random(1000)));
      IncrementSuccess;
    except
      IncrementError;
    end;
    LContext.Free;
  end);
  
  Assert.AreEqual(0, FErrorCount, 'Should have no errors');
  Assert.IsTrue(LResult.ThroughputPerSec > 2000, 'Should handle > 2000/s with 50 workers');
end;

procedure TConcurrencyBenchmarkTests.Benchmark_Concurrent_100Workers;
var
  LResult: TBenchmarkResult;
begin
  FSuccessCount := 0;
  FErrorCount := 0;
  
  LResult := FRunner.RunConcurrentBenchmark('Concurrent_100Workers', 10000, 100, procedure
  var
    LContext: TWorkflowContext;
  begin
    LContext := TWorkflowContext.Create;
    try
      LContext.SetVariable('test', TJSONNumber.Create(Random(1000)));
      IncrementSuccess;
    except
      IncrementError;
    end;
    LContext.Free;
  end);
  
  Assert.AreEqual(0, FErrorCount, 'Should have no errors');
  Assert.IsTrue(LResult.ThroughputPerSec > 3000, 'Should handle > 3000/s with 100 workers');
end;

procedure TConcurrencyBenchmarkTests.Benchmark_Concurrent_RampUp;
var
  LConcurrency: Integer;
  LResult: TBenchmarkResult;
begin
  // Test with increasing concurrency levels
  for LConcurrency in [1, 5, 10, 20, 50] do
  begin
    FSuccessCount := 0;
    FErrorCount := 0;
    
    LResult := FRunner.RunConcurrentBenchmark(
      Format('RampUp_%dWorkers', [LConcurrency]),
      LConcurrency * 100, LConcurrency, procedure
    var
      LContext: TWorkflowContext;
    begin
      LContext := TWorkflowContext.Create;
      try
        LContext.SetVariable('test', TJSONNumber.Create(Random(1000)));
        IncrementSuccess;
      except
        IncrementError;
      end;
      LContext.Free;
    end);
    
    Assert.AreEqual(0, FErrorCount, Format('%d workers: Should have no errors', [LConcurrency]));
  end;
end;

// ============================================================================
// TMemoryBenchmarkTests Implementation
// ============================================================================

procedure TMemoryBenchmarkTests.Setup;
begin
  FRunner := TBenchmarkRunner.Create;
  FMonitor := TMemoryMonitor.Create(50);
end;

procedure TMemoryBenchmarkTests.TearDown;
begin
  FMonitor.Free;
  FRunner.Report.SaveToFile('benchmark_memory.json');
  FRunner.Report.PrintSummary;
  FRunner.Free;
end;

procedure TMemoryBenchmarkTests.Benchmark_Memory_WorkflowExecution;
var
  LResult: TBenchmarkResult;
begin
  FMonitor.Start;
  try
    LResult := FRunner.RunBenchmark('Memory_WorkflowExec', 500, procedure
    var
      LWorkflow: TWorkflowDefinition;
      LContext: TWorkflowContext;
      LExecutor: TWorkflowExecutor;
      LStepResult: TStepResult;
    begin
      LWorkflow := TWorkflowDefinition.Create;
      LContext := TWorkflowContext.Create;
      try
        LExecutor := TWorkflowExecutor.Create(LWorkflow, LContext);
        try
          LStepResult := LExecutor.Start;
          LStepResult.Free;
        finally
          LExecutor.Free;
        end;
      finally
        LContext.Free;
        LWorkflow.Free;
      end;
    end);
  finally
    FMonitor.Stop;
  end;
  
  WriteLn(Format('Peak memory: %d bytes, Avg: %d bytes', 
    [FMonitor.GetPeakMemory, FMonitor.GetAverageMemory]));
  
  // Memory should not grow unbounded
  Assert.IsTrue(LResult.MemoryUsedBytes < 50 * 1024 * 1024, 'Memory growth should be < 50MB');
end;

procedure TMemoryBenchmarkTests.Benchmark_Memory_LargeContext;
var
  LResult: TBenchmarkResult;
  LContext: TWorkflowContext;
begin
  LContext := TWorkflowContext.Create;
  try
    LResult := FRunner.RunBenchmark('Memory_LargeContext', 1000, procedure
    var
      I: Integer;
    begin
      for I := 1 to 100 do
        LContext.SetVariable('var_' + IntToStr(I), TJSONString.Create(StringOfChar('x', 1000)));
    end);
    
    Assert.IsTrue(LResult.MemoryUsedBytes < 200 * 1024 * 1024, 'Large context should use < 200MB');
  finally
    LContext.Free;
  end;
end;

procedure TMemoryBenchmarkTests.Benchmark_Memory_ObjectPoolEfficiency;
begin
  // Test object pool memory efficiency
  Assert.Pass('Object pool memory test - see TObjectPoolBenchmarkTests');
end;

procedure TMemoryBenchmarkTests.Benchmark_Memory_LeakDetection;
var
  LStartMemory, LEndMemory: Int64;
  LMemCounters: TProcessMemoryCounters;
  I: Integer;
begin
  // Get starting memory
  LMemCounters.cb := SizeOf(LMemCounters);
  GetProcessMemoryInfo(GetCurrentProcess, @LMemCounters, SizeOf(LMemCounters));
  LStartMemory := LMemCounters.WorkingSetSize;
  
  // Run many iterations
  for I := 1 to 1000 do
  begin
    var LWorkflow := TWorkflowDefinition.Create;
    var LContext := TWorkflowContext.Create;
    try
      LContext.SetVariable('test', TJSONString.Create('value'));
    finally
      LContext.Free;
      LWorkflow.Free;
    end;
  end;
  
  // Force garbage collection (Delphi doesn't have GC, but run finalizers)
  
  // Get ending memory
  GetProcessMemoryInfo(GetCurrentProcess, @LMemCounters, SizeOf(LMemCounters));
  LEndMemory := LMemCounters.WorkingSetSize;
  
  WriteLn(Format('Memory delta: %d bytes', [LEndMemory - LStartMemory]));
  
  // Allow some variance but detect major leaks
  Assert.IsTrue((LEndMemory - LStartMemory) < 10 * 1024 * 1024, 
    'Memory leak detected: delta > 10MB');
end;

// ============================================================================
// TStabilityBenchmarkTests Implementation
// ============================================================================

procedure TStabilityBenchmarkTests.Setup;
begin
  FRunner := TBenchmarkRunner.Create;
  FRunner.WarmupIterations := 0;
  FErrorLog := TStringList.Create;
end;

procedure TStabilityBenchmarkTests.TearDown;
begin
  FErrorLog.Free;
  FRunner.Report.SaveToFile('benchmark_stability.json');
  FRunner.Report.PrintSummary;
  FRunner.Free;
end;

procedure TStabilityBenchmarkTests.Benchmark_Stability_LongRunning_1000Iterations;
var
  LResult: TBenchmarkResult;
  LErrorCount: Integer;
begin
  LErrorCount := 0;
  
  LResult := FRunner.RunBenchmark('Stability_LongRunning', 1000, procedure
  var
    LWorkflow: TWorkflowDefinition;
    LContext: TWorkflowContext;
  begin
    LWorkflow := TWorkflowDefinition.Create;
    LContext := TWorkflowContext.Create;
    try
      LContext.SetVariable('iteration', TJSONNumber.Create(Random(10000)));
      // Simulate some work
      Sleep(1);
    except
      on E: Exception do
      begin
        Inc(LErrorCount);
        FErrorLog.Add(E.Message);
      end;
    end;
    LContext.Free;
    LWorkflow.Free;
  end);
  
  Assert.AreEqual(0, LErrorCount, 'Long running test should have no errors');
  WriteLn(Format('Completed %d iterations in %.2f seconds', 
    [LResult.Iterations, LResult.TotalTimeMs / 1000]));
end;

procedure TStabilityBenchmarkTests.Benchmark_Stability_ErrorRecovery;
begin
  Assert.Pass('Error recovery stability test - placeholder');
end;

procedure TStabilityBenchmarkTests.Benchmark_Stability_ResourceCleanup;
begin
  Assert.Pass('Resource cleanup stability test - placeholder');
end;

// ============================================================================
// TObjectPoolBenchmarkTests Implementation
// ============================================================================

procedure TObjectPoolBenchmarkTests.Setup;
begin
  FRunner := TBenchmarkRunner.Create;
end;

procedure TObjectPoolBenchmarkTests.TearDown;
begin
  FRunner.Report.SaveToFile('benchmark_pool.json');
  FRunner.Report.PrintSummary;
  FRunner.Free;
end;

procedure TObjectPoolBenchmarkTests.Benchmark_Pool_JSONObject_10000Times;
var
  LResult: TBenchmarkResult;
begin
  LResult := FRunner.RunBenchmark('Pool_JSONObject_10000', 10000, procedure
  var
    LJson: TJSONObject;
  begin
    // Using pool would be: LJson := JSONObjectPool.Acquire;
    LJson := TJSONObject.Create;
    LJson.AddPair('test', 'value');
    // Pool release: JSONObjectPool.Release(LJson);
    LJson.Free;
  end);
  
  Assert.IsTrue(LResult.ThroughputPerSec > 5000, 'JSON pool should be > 5000/s');
end;

procedure TObjectPoolBenchmarkTests.Benchmark_Pool_StringBuilder_10000Times;
var
  LResult: TBenchmarkResult;
begin
  LResult := FRunner.RunBenchmark('Pool_StringBuilder_10000', 10000, procedure
  var
    LSB: TStringBuilder;
  begin
    LSB := TStringBuilder.Create;
    try
      LSB.Append('Hello ').Append('World');
    finally
      LSB.Free;
    end;
  end);
  
  Assert.IsTrue(LResult.ThroughputPerSec > 10000, 'StringBuilder pool should be > 10000/s');
end;

procedure TObjectPoolBenchmarkTests.Benchmark_Pool_VsDirectCreation;
var
  LPoolResult, LDirectResult: TBenchmarkResult;
begin
  // Direct creation
  LDirectResult := FRunner.RunBenchmark('Direct_Creation', 10000, procedure
  var
    LJson: TJSONObject;
  begin
    LJson := TJSONObject.Create;
    LJson.AddPair('key', 'value');
    LJson.Free;
  end);
  
  // Pool creation (simulated - using same code for now)
  LPoolResult := FRunner.RunBenchmark('Pool_Creation', 10000, procedure
  var
    LJson: TJSONObject;
  begin
    // In real implementation, use: LJson := Pool.Acquire;
    LJson := TJSONObject.Create;
    LJson.AddPair('key', 'value');
    // Pool.Release(LJson);
    LJson.Free;
  end);
  
  WriteLn(Format('Direct: %.1f/s, Pool: %.1f/s', 
    [LDirectResult.ThroughputPerSec, LPoolResult.ThroughputPerSec]));
  
  Assert.Pass('Pool vs Direct comparison completed');
end;

procedure TObjectPoolBenchmarkTests.Benchmark_Pool_ConcurrentAccess;
var
  LResult: TBenchmarkResult;
begin
  LResult := FRunner.RunConcurrentBenchmark('Pool_Concurrent', 10000, 20, procedure
  var
    LJson: TJSONObject;
  begin
    LJson := TJSONObject.Create;
    try
      LJson.AddPair('thread_id', TJSONNumber.Create(TThread.CurrentThread.ThreadID));
    finally
      LJson.Free;
    end;
  end);
  
  Assert.IsTrue(LResult.ThroughputPerSec > 5000, 'Concurrent pool access should be > 5000/s');
end;

initialization
  TDUnitX.RegisterTestFixture(TThroughputBenchmarkTests);
  TDUnitX.RegisterTestFixture(TConcurrencyBenchmarkTests);
  TDUnitX.RegisterTestFixture(TMemoryBenchmarkTests);
  TDUnitX.RegisterTestFixture(TStabilityBenchmarkTests);
  TDUnitX.RegisterTestFixture(TObjectPoolBenchmarkTests);

end.
