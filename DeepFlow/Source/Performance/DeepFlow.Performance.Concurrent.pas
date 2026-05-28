unit UniFlow.Performance.Concurrent;
(*
  UniFlow Performance - Concurrent Execution
  ==========================================
  高性能并发执行模块，提供：
  - 工作窃取队列
  - 增强型线程池
  - 并行执行�?
  - 异步工作流执�?

  Author: UniFlow Team
  Date: 2025-12-05
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.SyncObjs, System.Threading, System.Diagnostics,
  DeepBase.Exceptions;

type
  // ============================================================================
  // 任务优先�?
  // ============================================================================

  TTaskPriority = (
    tpLow,
    tpNormal,
    tpHigh,
    tpCritical
  );

  // ============================================================================
  // 工作窃取队列
  // ============================================================================

  /// <summary>工作窃取双端队列</summary>
  TWorkStealingQueue<T> = class
  private
    FItems: TArray<T>;
    FHead: Integer;  // 头部（本�?push/pop�?
    FTail: Integer;  // 尾部（远�?steal�?
    FMask: Integer;
    FLock: TSpinLock;

    procedure Grow;
    function GetCount: Integer;
  public
    constructor Create(AInitialCapacity: Integer = 32);
    destructor Destroy; override;

    /// <summary>本地推入（头部）</summary>
    procedure Push(const AItem: T);

    /// <summary>本地弹出（头部）- 无竞�?/summary>
    function Pop(out AItem: T): Boolean;

    /// <summary>远程窃取（尾部）- 可能与其他窃取者竞�?/summary>
    function Steal(out AItem: T): Boolean;

    /// <summary>队列是否为空</summary>
    function IsEmpty: Boolean;

    /// <summary>当前项数</summary>
    property Count: Integer read GetCount;
  end;

  // ============================================================================
  // 工作�?
  // ============================================================================

  TWorkItem = class
  private
    FId: string;
    FProc: TProc;
    FPriority: TTaskPriority;
    FCreatedAt: TDateTime;
    FTimeout: Integer;
    FTag: string;
  public
    constructor Create(AProc: TProc; APriority: TTaskPriority = tpNormal);

    property Id: string read FId write FId;
    property Proc: TProc read FProc;
    property Priority: TTaskPriority read FPriority write FPriority;
    property CreatedAt: TDateTime read FCreatedAt;
    property Timeout: Integer read FTimeout write FTimeout;
    property Tag: string read FTag write FTag;
  end;

  // ============================================================================
  // 工作线程
  // ============================================================================

  TWorkerThread = class;
  TEnhancedThreadPool = class;

  TWorkerThread = class(TThread)
  private
    FPool: TEnhancedThreadPool;
    FLocalQueue: TWorkStealingQueue<TWorkItem>;
    FWorkerId: Integer;
    FIdleSince: TDateTime;
    FTasksExecuted: Int64;
    FTotalExecutionMs: Int64;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TEnhancedThreadPool; AWorkerId: Integer);
    destructor Destroy; override;

    property WorkerId: Integer read FWorkerId;
    property LocalQueue: TWorkStealingQueue<TWorkItem> read FLocalQueue;
    property TasksExecuted: Int64 read FTasksExecuted;
    property TotalExecutionMs: Int64 read FTotalExecutionMs;
  end;

  // ============================================================================
  // 线程池统�?
  // ============================================================================

  TThreadPoolStats = record
    ActiveWorkers: Integer;
    IdleWorkers: Integer;
    TotalTasks: Int64;
    CompletedTasks: Int64;
    FailedTasks: Int64;
    QueuedTasks: Integer;
    StolenTasks: Int64;
    AvgExecutionMs: Double;
    PeakWorkers: Integer;

    function ToJSON: TJSONObject;
    procedure Reset;
  end;

  // ============================================================================
  // 增强型线程池
  // ============================================================================

  /// <summary>线程池配�?/summary>
  TThreadPoolConfig = record
    MinWorkers: Integer;
    MaxWorkers: Integer;
    IdleTimeoutMs: Integer;
    QueueCapacity: Integer;
    EnableWorkStealing: Boolean;

    class function Default: TThreadPoolConfig; static;
    class function Small: TThreadPoolConfig; static;
    class function Large: TThreadPoolConfig; static;
  end;

  /// <summary>增强型线程池</summary>
  TEnhancedThreadPool = class
  private
    FWorkers: TObjectList<TWorkerThread>;
    FGlobalQueue: TThreadedQueue<TWorkItem>;
    FConfig: TThreadPoolConfig;
    FLock: TCriticalSection;
    FStats: TThreadPoolStats;
    FShutdown: Boolean;
    FWorkAvailable: TEvent;

    procedure AdjustWorkerCount;
    function TryStealWork(AThief: TWorkerThread; out AItem: TWorkItem): Boolean;
    procedure WorkerIdle(AWorker: TWorkerThread);
    procedure WorkerBusy(AWorker: TWorkerThread);
  public
    constructor Create(AConfig: TThreadPoolConfig); overload;
    constructor Create(AWorkerCount: Integer = 0); overload;
    destructor Destroy; override;

    /// <summary>提交任务</summary>
    procedure Submit(AProc: TProc; APriority: TTaskPriority = tpNormal); overload;
    procedure Submit(AWorkItem: TWorkItem); overload;

    /// <summary>提交到指定工作线�?/summary>
    procedure SubmitTo(AWorkerId: Integer; AProc: TProc);

    /// <summary>等待所有任务完�?/summary>
    procedure WaitAll(ATimeoutMs: Integer = INFINITE);

    /// <summary>关闭线程�?/summary>
    procedure Shutdown(AWaitForCompletion: Boolean = True);

    /// <summary>获取统计信息</summary>
    function GetStats: TThreadPoolStats;

    /// <summary>设置工作线程�?/summary>
    procedure SetWorkerCount(ACount: Integer);

    property Config: TThreadPoolConfig read FConfig;
    property IsShutdown: Boolean read FShutdown;
  end;

  // ============================================================================
  // Future/Promise
  // ============================================================================

  TFutureState = (fsNotStarted, fsPending, fsCompleted, fsFailed, fsCancelled);

  /// <summary>Future 基类</summary>
  TFutureBase = class
  private
    FState: TFutureState;
    FError: Exception;
    FEvent: TEvent;
    FLock: TCriticalSection;
  protected
    procedure SetCompleted;
    procedure SetFailed(E: Exception);
  public
    constructor Create;
    destructor Destroy; override;

    function Wait(ATimeoutMs: Integer = INFINITE): Boolean;
    procedure Cancel;

    property State: TFutureState read FState;
    property Error: Exception read FError;
  end;

  /// <summary>泛型 Future</summary>
  TFuture<T> = class(TFutureBase)
  private
    FValue: T;
  public
    procedure SetResult(const AValue: T);
    function GetResult: T;

    property Value: T read GetResult;
  end;

  /// <summary>Promise</summary>
  TPromise<T> = class
  private
    FFuture: TFuture<T>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Resolve(const AValue: T);
    procedure Reject(E: Exception);

    function GetFuture: TFuture<T>;
  end;

  // ============================================================================
  // 并行执行�?
  // ============================================================================

  /// <summary>并行任务结果</summary>
  TParallelResult<T> = record
    Index: Integer;
    Value: T;
    Success: Boolean;
    Error: string;
    DurationMs: Int64;
  end;

  /// <summary>并行执行�?/summary>
  TParallelExecutor = class
  private
    FPool: TEnhancedThreadPool;
    FOwnsPool: Boolean;
  public
    constructor Create(APool: TEnhancedThreadPool = nil);
    destructor Destroy; override;

    /// <summary>并行执行多个任务</summary>
    procedure ForEach<T>(const AItems: TArray<T>; AAction: TProc<T>);

    /// <summary>并行执行并收集结�?/summary>
    function Map<TIn, TOut>(const AItems: TArray<TIn>;
      AFunc: TFunc<TIn, TOut>): TArray<TParallelResult<TOut>>;

    /// <summary>并行执行，任一完成即返�?/summary>
    function Any<T>(const AFuncs: TArray<TFunc<T>>; ATimeoutMs: Integer = 0): T;

    /// <summary>并行执行，等待全部完�?/summary>
    function All<T>(const AFuncs: TArray<TFunc<T>>; ATimeoutMs: Integer = 0): TArray<T>;

    /// <summary>批量执行</summary>
    procedure Batch(const AProcs: TArray<TProc>; AMaxConcurrency: Integer = 0);
  end;

  // ============================================================================
  // 异步工作流执�?
  // ============================================================================

  TAsyncStepState = (assNotStarted, assRunning, assCompleted, assFailed, assCancelled);

  /// <summary>异步步骤</summary>
  TAsyncStep = class
  private
    FId: string;
    FName: string;
    FState: TAsyncStepState;
    FProc: TProc;
    FDependencies: TList<string>;
    FResult: TJSONValue;
    FError: string;
    FStartTime: TDateTime;
    FEndTime: TDateTime;
  public
    constructor Create(const AId, AName: string; AProc: TProc);
    destructor Destroy; override;

    procedure AddDependency(const AStepId: string);

    property Id: string read FId;
    property Name: string read FName;
    property State: TAsyncStepState read FState write FState;
    property Proc: TProc read FProc;
    property Dependencies: TList<string> read FDependencies;
    property Result: TJSONValue read FResult write FResult;
    property Error: string read FError write FError;
    property StartTime: TDateTime read FStartTime write FStartTime;
    property EndTime: TDateTime read FEndTime write FEndTime;
  end;

  /// <summary>异步工作流执行器</summary>
  TAsyncWorkflowExecutor = class
  private
    FSteps: TObjectDictionary<string, TAsyncStep>;
    FPool: TEnhancedThreadPool;
    FOwnsPool: Boolean;
    FLock: TCriticalSection;
    FCompletedSteps: TList<string>;
    FOnStepComplete: TProc<TAsyncStep>;
    FOnStepFailed: TProc<TAsyncStep>;

    function CanExecute(AStep: TAsyncStep): Boolean;
    procedure ExecuteStep(AStep: TAsyncStep);
    procedure CheckAndExecutePending;
  public
    constructor Create(APool: TEnhancedThreadPool = nil);
    destructor Destroy; override;

    /// <summary>添加步骤</summary>
    procedure AddStep(const AId, AName: string; AProc: TProc);

    /// <summary>添加依赖</summary>
    procedure AddDependency(const AStepId, ADependsOn: string);

    /// <summary>开始执�?/summary>
    procedure Start;

    /// <summary>等待完成</summary>
    function WaitAll(ATimeoutMs: Integer = INFINITE): Boolean;

    /// <summary>获取步骤状�?/summary>
    function GetStepState(const AStepId: string): TAsyncStepState;

    /// <summary>获取执行摘要</summary>
    function GetSummary: TJSONObject;

    property OnStepComplete: TProc<TAsyncStep> read FOnStepComplete write FOnStepComplete;
    property OnStepFailed: TProc<TAsyncStep> read FOnStepFailed write FOnStepFailed;
  end;

  // ============================================================================
  // 全局线程�?
  // ============================================================================

  /// <summary>获取全局线程�?/summary>
  function GlobalThreadPool: TEnhancedThreadPool;

  /// <summary>释放全局线程�?/summary>
  procedure ReleaseGlobalThreadPool;

  /// <summary>便捷并行执行</summary>
  procedure ParallelFor(AFrom, ATo: Integer; AProc: TProc<Integer>);

implementation

uses
  System.DateUtils, System.Math;

var
  GThreadPool: TEnhancedThreadPool;
  GThreadPoolLock: TCriticalSection;

// ============================================================================
// TWorkStealingQueue<T>
// ============================================================================

constructor TWorkStealingQueue<T>.Create(AInitialCapacity: Integer);
begin
  inherited Create;
  // 确保容量�?2 的幂
  AInitialCapacity := Max(AInitialCapacity, 4);
  SetLength(FItems, AInitialCapacity);
  FMask := AInitialCapacity - 1;
  FHead := 0;
  FTail := 0;
end;

destructor TWorkStealingQueue<T>.Destroy;
begin
  inherited;
end;

procedure TWorkStealingQueue<T>.Grow;
var
  OldItems: TArray<T>;
  OldMask, i, Count: Integer;
begin
  OldItems := FItems;
  OldMask := FMask;
  Count := FHead - FTail;

  SetLength(FItems, Length(OldItems) * 2);
  FMask := Length(FItems) - 1;

  // 复制元素
  for i := 0 to Count - 1 do
    FItems[i] := OldItems[(FTail + i) and OldMask];

  FTail := 0;
  FHead := Count;
end;

function TWorkStealingQueue<T>.GetCount: Integer;
begin
  Result := FHead - FTail;
end;

procedure TWorkStealingQueue<T>.Push(const AItem: T);
var
  H, T: Integer;
begin
  FLock.Enter;
  try
    H := FHead;
    T := FTail;

    // 检查是否需要扩�?
    if H - T >= Length(FItems) then
      Grow;

    FItems[H and FMask] := AItem;
    FHead := H + 1;
  finally
    FLock.Exit;
  end;
end;

function TWorkStealingQueue<T>.Pop(out AItem: T): Boolean;
var
  H, T: Integer;
begin
  FLock.Enter;
  try
    H := FHead;
    T := FTail;
    
    // 检查队列是否为�?
    if T >= H then
    begin
      Result := False;
      Exit;
    end;
    
    // 从头部弹出（LIFO�?
    Dec(H);
    FHead := H;
    AItem := FItems[H and FMask];
    Result := True;
  finally
    FLock.Exit;
  end;
end;

function TWorkStealingQueue<T>.Steal(out AItem: T): Boolean;
var
  T, H: Integer;
begin
  FLock.Enter;
  try
    T := FTail;
    H := FHead;

    if T < H then
    begin
      AItem := FItems[T and FMask];
      FTail := T + 1;
      Result := True;
    end
    else
      Result := False;
  finally
    FLock.Exit;
  end;
end;

function TWorkStealingQueue<T>.IsEmpty: Boolean;
begin
  Result := FHead <= FTail;
end;

// ============================================================================
// TWorkItem
// ============================================================================

constructor TWorkItem.Create(AProc: TProc; APriority: TTaskPriority);
begin
  inherited Create;
  FId := TGUID.NewGuid.ToString;
  FProc := AProc;
  FPriority := APriority;
  FCreatedAt := Now;
  FTimeout := 0;
end;

// ============================================================================
// TWorkerThread
// ============================================================================

constructor TWorkerThread.Create(APool: TEnhancedThreadPool; AWorkerId: Integer);
begin
  inherited Create(True);
  FPool := APool;
  FWorkerId := AWorkerId;
  FLocalQueue := TWorkStealingQueue<TWorkItem>.Create;
  FIdleSince := Now;
  FTasksExecuted := 0;
  FTotalExecutionMs := 0;
  FreeOnTerminate := False;
end;

destructor TWorkerThread.Destroy;
begin
  FLocalQueue.Free;
  inherited;
end;

procedure TWorkerThread.Execute;
var
  Item: TWorkItem;
  SW: TStopwatch;
begin
  while not Terminated and not FPool.IsShutdown do
  begin
    Item := nil;

    // 1. 先从本地队列�?
    if FLocalQueue.Pop(Item) then
    begin
      // 执行任务
    end
    // 2. 从全局队列�?
    else if FPool.FGlobalQueue.PopItem(Item) = TWaitResult.wrSignaled then
    begin
      // 执行任务
    end
    // 3. 尝试从其他工作线程窃�?
    else if FPool.Config.EnableWorkStealing and FPool.TryStealWork(Self, Item) then
    begin
      Inc(FPool.FStats.StolenTasks);
    end
    else
    begin
      // 无任务，等待
      FPool.WorkerIdle(Self);
      FPool.FWorkAvailable.WaitFor(100);
      FPool.WorkerBusy(Self);
      Continue;
    end;

    if Item <> nil then
    try
      SW := TStopwatch.StartNew;
      try
        Item.Proc();
        Inc(FPool.FStats.CompletedTasks);
      except
        Inc(FPool.FStats.FailedTasks);
      end;
      SW.Stop;
      Inc(FTasksExecuted);
      FTotalExecutionMs := FTotalExecutionMs + SW.ElapsedMilliseconds;
    finally
      Item.Free;
    end;
  end;
end;

// ============================================================================
// TThreadPoolStats
// ============================================================================

function TThreadPoolStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('activeWorkers', TJSONNumber.Create(ActiveWorkers));
  Result.AddPair('idleWorkers', TJSONNumber.Create(IdleWorkers));
  Result.AddPair('totalTasks', TJSONNumber.Create(TotalTasks));
  Result.AddPair('completedTasks', TJSONNumber.Create(CompletedTasks));
  Result.AddPair('failedTasks', TJSONNumber.Create(FailedTasks));
  Result.AddPair('queuedTasks', TJSONNumber.Create(QueuedTasks));
  Result.AddPair('stolenTasks', TJSONNumber.Create(StolenTasks));
  Result.AddPair('avgExecutionMs', TJSONNumber.Create(AvgExecutionMs));
  Result.AddPair('peakWorkers', TJSONNumber.Create(PeakWorkers));
end;

procedure TThreadPoolStats.Reset;
begin
  ActiveWorkers := 0;
  IdleWorkers := 0;
  TotalTasks := 0;
  CompletedTasks := 0;
  FailedTasks := 0;
  QueuedTasks := 0;
  StolenTasks := 0;
  AvgExecutionMs := 0;
  PeakWorkers := 0;
end;

// ============================================================================
// TThreadPoolConfig
// ============================================================================

class function TThreadPoolConfig.Default: TThreadPoolConfig;
begin
  Result.MinWorkers := 2;
  Result.MaxWorkers := TThread.ProcessorCount * 2;
  Result.IdleTimeoutMs := 60000;
  Result.QueueCapacity := 10000;
  Result.EnableWorkStealing := True;
end;

class function TThreadPoolConfig.Small: TThreadPoolConfig;
begin
  Result.MinWorkers := 1;
  Result.MaxWorkers := 4;
  Result.IdleTimeoutMs := 30000;
  Result.QueueCapacity := 1000;
  Result.EnableWorkStealing := False;
end;

class function TThreadPoolConfig.Large: TThreadPoolConfig;
begin
  Result.MinWorkers := TThread.ProcessorCount;
  Result.MaxWorkers := TThread.ProcessorCount * 4;
  Result.IdleTimeoutMs := 120000;
  Result.QueueCapacity := 100000;
  Result.EnableWorkStealing := True;
end;

// ============================================================================
// TEnhancedThreadPool
// ============================================================================

constructor TEnhancedThreadPool.Create(AConfig: TThreadPoolConfig);
var
  i: Integer;
begin
  inherited Create;
  FConfig := AConfig;
  FWorkers := TObjectList<TWorkerThread>.Create(True);
  FGlobalQueue := TThreadedQueue<TWorkItem>.Create(FConfig.QueueCapacity);
  FLock := TCriticalSection.Create;
  FStats.Reset;
  FShutdown := False;
  FWorkAvailable := TEvent.Create(nil, False, False, '');

  // 创建初始工作线程
  for i := 0 to FConfig.MinWorkers - 1 do
  begin
    FWorkers.Add(TWorkerThread.Create(Self, i));
    FWorkers[i].Start;
  end;
  FStats.ActiveWorkers := FConfig.MinWorkers;
  FStats.PeakWorkers := FConfig.MinWorkers;
end;

constructor TEnhancedThreadPool.Create(AWorkerCount: Integer);
var
  Config: TThreadPoolConfig;
begin
  Config := TThreadPoolConfig.Default;
  if AWorkerCount > 0 then
  begin
    Config.MinWorkers := AWorkerCount;
    Config.MaxWorkers := AWorkerCount;
  end;
  Create(Config);
end;

destructor TEnhancedThreadPool.Destroy;
begin
  Shutdown(True);
  FWorkers.Free;
  FGlobalQueue.Free;
  FLock.Free;
  FWorkAvailable.Free;
  inherited;
end;

procedure TEnhancedThreadPool.AdjustWorkerCount;
var
  QueueSize, WorkerCount, NewCount: Integer;
begin
  if FShutdown then
    Exit;

  FLock.Enter;
  try
    QueueSize := FGlobalQueue.QueueSize;
    WorkerCount := FWorkers.Count;

    // 如果队列太长，增加工作线�?
    if (QueueSize > WorkerCount * 10) and (WorkerCount < FConfig.MaxWorkers) then
    begin
      NewCount := Min(WorkerCount + 2, FConfig.MaxWorkers);
      while FWorkers.Count < NewCount do
      begin
        FWorkers.Add(TWorkerThread.Create(Self, FWorkers.Count));
        FWorkers.Last.Start;
      end;
      FStats.ActiveWorkers := FWorkers.Count;
      if FStats.ActiveWorkers > FStats.PeakWorkers then
        FStats.PeakWorkers := FStats.ActiveWorkers;
    end;
  finally
    FLock.Leave;
  end;
end;

function TEnhancedThreadPool.TryStealWork(AThief: TWorkerThread; out AItem: TWorkItem): Boolean;
var
  i: Integer;
  Victim: TWorkerThread;
begin
  Result := False;
  FLock.Enter;
  try
    for i := 0 to FWorkers.Count - 1 do
    begin
      Victim := FWorkers[i];
      if (Victim <> AThief) and Victim.LocalQueue.Steal(AItem) then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TEnhancedThreadPool.WorkerIdle(AWorker: TWorkerThread);
begin
  FLock.Enter;
  try
    Inc(FStats.IdleWorkers);
    Dec(FStats.ActiveWorkers);
    AWorker.FIdleSince := Now;
  finally
    FLock.Leave;
  end;
end;

procedure TEnhancedThreadPool.WorkerBusy(AWorker: TWorkerThread);
begin
  FLock.Enter;
  try
    Dec(FStats.IdleWorkers);
    Inc(FStats.ActiveWorkers);
  finally
    FLock.Leave;
  end;
end;

procedure TEnhancedThreadPool.Submit(AProc: TProc; APriority: TTaskPriority);
begin
  Submit(TWorkItem.Create(AProc, APriority));
end;

procedure TEnhancedThreadPool.Submit(AWorkItem: TWorkItem);
begin
  if FShutdown then
    raise EOperationException.Create('ThreadPool is shutdown');

  FLock.Enter;
  try
    Inc(FStats.TotalTasks);
    FStats.QueuedTasks := FGlobalQueue.QueueSize + 1;
  finally
    FLock.Leave;
  end;

  FGlobalQueue.PushItem(AWorkItem);
  FWorkAvailable.SetEvent;

  // 检查是否需要调整工作线程数
  AdjustWorkerCount;
end;

procedure TEnhancedThreadPool.SubmitTo(AWorkerId: Integer; AProc: TProc);
var
  Item: TWorkItem;
begin
  if FShutdown then
    raise EOperationException.Create('ThreadPool is shutdown');

  FLock.Enter;
  try
    if (AWorkerId >= 0) and (AWorkerId < FWorkers.Count) then
    begin
      Item := TWorkItem.Create(AProc);
      Inc(FStats.TotalTasks);
      FWorkers[AWorkerId].LocalQueue.Push(Item);
      FWorkAvailable.SetEvent;
    end
    else
      Submit(AProc);
  finally
    FLock.Leave;
  end;
end;

procedure TEnhancedThreadPool.WaitAll(ATimeoutMs: Integer);
var
  StartTime: TDateTime;
begin
  StartTime := Now;
  while (FStats.CompletedTasks + FStats.FailedTasks < FStats.TotalTasks) do
  begin
    if (ATimeoutMs <> INFINITE) and
       (MilliSecondsBetween(Now, StartTime) > ATimeoutMs) then
      Break;
    Sleep(10);
  end;
end;

procedure TEnhancedThreadPool.Shutdown(AWaitForCompletion: Boolean);
var
  i: Integer;
begin
  FShutdown := True;
  FWorkAvailable.SetEvent;

  if AWaitForCompletion then
  begin
    for i := 0 to FWorkers.Count - 1 do
    begin
      FWorkers[i].Terminate;
      FWorkers[i].WaitFor;
    end;
  end
  else
  begin
    for i := 0 to FWorkers.Count - 1 do
      FWorkers[i].Terminate;
  end;
end;

function TEnhancedThreadPool.GetStats: TThreadPoolStats;
var
  TotalExec: Int64;
  i: Integer;
begin
  FLock.Enter;
  try
    Result := FStats;
    Result.QueuedTasks := FGlobalQueue.QueueSize;

    // 计算平均执行时间
    TotalExec := 0;
    for i := 0 to FWorkers.Count - 1 do
      TotalExec := TotalExec + FWorkers[i].TotalExecutionMs;

    if Result.CompletedTasks > 0 then
      Result.AvgExecutionMs := TotalExec / Result.CompletedTasks;
  finally
    FLock.Leave;
  end;
end;

procedure TEnhancedThreadPool.SetWorkerCount(ACount: Integer);
var
  i: Integer;
begin
  FLock.Enter;
  try
    ACount := Max(FConfig.MinWorkers, Min(ACount, FConfig.MaxWorkers));

    while FWorkers.Count < ACount do
    begin
      FWorkers.Add(TWorkerThread.Create(Self, FWorkers.Count));
      FWorkers.Last.Start;
    end;

    FStats.ActiveWorkers := FWorkers.Count;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TFutureBase
// ============================================================================

constructor TFutureBase.Create;
begin
  inherited Create;
  FState := fsNotStarted;
  FError := nil;
  FEvent := TEvent.Create(nil, True, False, '');
  FLock := TCriticalSection.Create;
end;

destructor TFutureBase.Destroy;
begin
  FEvent.Free;
  FLock.Free;
  FError.Free;
  inherited;
end;

procedure TFutureBase.SetCompleted;
begin
  FLock.Enter;
  try
    FState := fsCompleted;
    FEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TFutureBase.SetFailed(E: Exception);
begin
  FLock.Enter;
  try
    FState := fsFailed;
    FError := E;
    FEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TFutureBase.Wait(ATimeoutMs: Integer): Boolean;
begin
  Result := FEvent.WaitFor(ATimeoutMs) = wrSignaled;
end;

procedure TFutureBase.Cancel;
begin
  FLock.Enter;
  try
    if FState in [fsNotStarted, fsPending] then
    begin
      FState := fsCancelled;
      FEvent.SetEvent;
    end;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TFuture<T>
// ============================================================================

procedure TFuture<T>.SetResult(const AValue: T);
begin
  FLock.Enter;
  try
    FValue := AValue;
    SetCompleted;
  finally
    FLock.Leave;
  end;
end;

function TFuture<T>.GetResult: T;
begin
  Wait;
  if FState = fsFailed then
    raise FError;
  if FState = fsCancelled then
    raise EOperationException.Create('Future was cancelled');
  Result := FValue;
end;

// ============================================================================
// TPromise<T>
// ============================================================================

constructor TPromise<T>.Create;
begin
  inherited Create;
  FFuture := TFuture<T>.Create;
end;

destructor TPromise<T>.Destroy;
begin
  // Future 由调用者管�?
  inherited;
end;

procedure TPromise<T>.Resolve(const AValue: T);
begin
  FFuture.SetResult(AValue);
end;

procedure TPromise<T>.Reject(E: Exception);
begin
  FFuture.SetFailed(E);
end;

function TPromise<T>.GetFuture: TFuture<T>;
begin
  Result := FFuture;
end;

// ============================================================================
// TParallelExecutor
// ============================================================================

constructor TParallelExecutor.Create(APool: TEnhancedThreadPool);
begin
  inherited Create;
  if APool <> nil then
  begin
    FPool := APool;
    FOwnsPool := False;
  end
  else
  begin
    FPool := TEnhancedThreadPool.Create;
    FOwnsPool := True;
  end;
end;

destructor TParallelExecutor.Destroy;
begin
  if FOwnsPool then
    FPool.Free;
  inherited;
end;

procedure TParallelExecutor.ForEach<T>(const AItems: TArray<T>; AAction: TProc<T>);
var
  Remaining: Integer;
  Lock: TCriticalSection;
  Event: TEvent;
  i: Integer;
begin
  if Length(AItems) = 0 then
    Exit;

  Remaining := Length(AItems);
  Lock := TCriticalSection.Create;
  Event := TEvent.Create(nil, True, False, '');
  try
    for i := 0 to High(AItems) do
    begin
      var Item := AItems[i];
      FPool.Submit(
        procedure
        begin
          try
            AAction(Item);
          finally
            Lock.Enter;
            try
              Dec(Remaining);
              if Remaining = 0 then
                Event.SetEvent;
            finally
              Lock.Leave;
            end;
          end;
        end
      );
    end;

    Event.WaitFor(INFINITE);
  finally
    Lock.Free;
    Event.Free;
  end;
end;

function TParallelExecutor.Map<TIn, TOut>(const AItems: TArray<TIn>;
  AFunc: TFunc<TIn, TOut>): TArray<TParallelResult<TOut>>;
var
  Results: TArray<TParallelResult<TOut>>;
  Remaining: Integer;
  Lock: TCriticalSection;
  Event: TEvent;
  i: Integer;
begin
  SetLength(Results, Length(AItems));

  if Length(AItems) = 0 then
  begin
    Result := Results;
    Exit;
  end;

  Remaining := Length(AItems);
  Lock := TCriticalSection.Create;
  Event := TEvent.Create(nil, True, False, '');
  try
    for i := 0 to High(AItems) do
    begin
      var Idx := i;
      var Item := AItems[i];
      FPool.Submit(
        procedure
        var
          SW: TStopwatch;
        begin
          SW := TStopwatch.StartNew;
          try
            Results[Idx].Index := Idx;
            Results[Idx].Value := AFunc(Item);
            Results[Idx].Success := True;
          except
            on E: Exception do
            begin
              Results[Idx].Index := Idx;
              Results[Idx].Success := False;
              Results[Idx].Error := E.Message;
            end;
          end;
          SW.Stop;
          Results[Idx].DurationMs := SW.ElapsedMilliseconds;

          Lock.Enter;
          try
            Dec(Remaining);
            if Remaining = 0 then
              Event.SetEvent;
          finally
            Lock.Leave;
          end;
        end
      );
    end;

    Event.WaitFor(INFINITE);
    Result := Results;
  finally
    Lock.Free;
    Event.Free;
  end;
end;

function TParallelExecutor.Any<T>(const AFuncs: TArray<TFunc<T>>; ATimeoutMs: Integer): T;
var
  Found: Boolean;
  ResultValue: T;
  Lock: TCriticalSection;
  Event: TEvent;
  i: Integer;
begin
  if Length(AFuncs) = 0 then
    raise EOperationException.Create('No functions provided');

  Found := False;
  Lock := TCriticalSection.Create;
  Event := TEvent.Create(nil, True, False, '');
  try
    for i := 0 to High(AFuncs) do
    begin
      var Func := AFuncs[i];
      FPool.Submit(
        procedure
        var
          V: T;
        begin
          try
            V := Func();
            Lock.Enter;
            try
              if not Found then
              begin
                Found := True;
                ResultValue := V;
                Event.SetEvent;
              end;
            finally
              Lock.Leave;
            end;
          except
            // Ignore errors for Any
          end;
        end
      );
    end;

    if ATimeoutMs > 0 then
      Event.WaitFor(ATimeoutMs)
    else
      Event.WaitFor(INFINITE);

    if Found then
      Result := ResultValue
    else
      raise EOperationException.Create('No result available');
  finally
    Lock.Free;
    Event.Free;
  end;
end;

function TParallelExecutor.All<T>(const AFuncs: TArray<TFunc<T>>; ATimeoutMs: Integer): TArray<T>;
var
  Results: TArray<T>;
  Remaining: Integer;
  Lock: TCriticalSection;
  Event: TEvent;
  i: Integer;
begin
  SetLength(Results, Length(AFuncs));

  if Length(AFuncs) = 0 then
  begin
    Result := Results;
    Exit;
  end;

  Remaining := Length(AFuncs);
  Lock := TCriticalSection.Create;
  Event := TEvent.Create(nil, True, False, '');
  try
    for i := 0 to High(AFuncs) do
    begin
      var Idx := i;
      var Func := AFuncs[i];
      FPool.Submit(
        procedure
        begin
          try
            Results[Idx] := Func();
          finally
            Lock.Enter;
            try
              Dec(Remaining);
              if Remaining = 0 then
                Event.SetEvent;
            finally
              Lock.Leave;
            end;
          end;
        end
      );
    end;

    if ATimeoutMs > 0 then
      Event.WaitFor(ATimeoutMs)
    else
      Event.WaitFor(INFINITE);

    Result := Results;
  finally
    Lock.Free;
    Event.Free;
  end;
end;

procedure TParallelExecutor.Batch(const AProcs: TArray<TProc>; AMaxConcurrency: Integer);
var
  i: Integer;
begin
  if AMaxConcurrency <= 0 then
    AMaxConcurrency := TThread.ProcessorCount;

  for i := 0 to High(AProcs) do
    FPool.Submit(AProcs[i]);

  FPool.WaitAll;
end;

// ============================================================================
// TAsyncStep
// ============================================================================

constructor TAsyncStep.Create(const AId, AName: string; AProc: TProc);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FProc := AProc;
  FState := assNotStarted;
  FDependencies := TList<string>.Create;
  FResult := nil;
end;

destructor TAsyncStep.Destroy;
begin
  FDependencies.Free;
  FResult.Free;
  inherited;
end;

procedure TAsyncStep.AddDependency(const AStepId: string);
begin
  if not FDependencies.Contains(AStepId) then
    FDependencies.Add(AStepId);
end;

// ============================================================================
// TAsyncWorkflowExecutor
// ============================================================================

constructor TAsyncWorkflowExecutor.Create(APool: TEnhancedThreadPool);
begin
  inherited Create;
  FSteps := TObjectDictionary<string, TAsyncStep>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FCompletedSteps := TList<string>.Create;

  if APool <> nil then
  begin
    FPool := APool;
    FOwnsPool := False;
  end
  else
  begin
    FPool := TEnhancedThreadPool.Create;
    FOwnsPool := True;
  end;
end;

destructor TAsyncWorkflowExecutor.Destroy;
begin
  FSteps.Free;
  FLock.Free;
  FCompletedSteps.Free;
  if FOwnsPool then
    FPool.Free;
  inherited;
end;

procedure TAsyncWorkflowExecutor.AddStep(const AId, AName: string; AProc: TProc);
begin
  FLock.Enter;
  try
    FSteps.Add(AId, TAsyncStep.Create(AId, AName, AProc));
  finally
    FLock.Leave;
  end;
end;

procedure TAsyncWorkflowExecutor.AddDependency(const AStepId, ADependsOn: string);
var
  Step: TAsyncStep;
begin
  FLock.Enter;
  try
    if FSteps.TryGetValue(AStepId, Step) then
      Step.AddDependency(ADependsOn);
  finally
    FLock.Leave;
  end;
end;

function TAsyncWorkflowExecutor.CanExecute(AStep: TAsyncStep): Boolean;
var
  DepId: string;
begin
  Result := AStep.State = assNotStarted;
  if not Result then
    Exit;

  for DepId in AStep.Dependencies do
  begin
    if not FCompletedSteps.Contains(DepId) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

procedure TAsyncWorkflowExecutor.ExecuteStep(AStep: TAsyncStep);
begin
  AStep.State := assRunning;
  AStep.StartTime := Now;

  FPool.Submit(
    procedure
    begin
      try
        AStep.Proc();
        AStep.State := assCompleted;
        AStep.EndTime := Now;

        FLock.Enter;
        try
          FCompletedSteps.Add(AStep.Id);
        finally
          FLock.Leave;
        end;

        if Assigned(FOnStepComplete) then
          FOnStepComplete(AStep);

        CheckAndExecutePending;
      except
        on E: Exception do
        begin
          AStep.State := assFailed;
          AStep.Error := E.Message;
          AStep.EndTime := Now;

          if Assigned(FOnStepFailed) then
            FOnStepFailed(AStep);
        end;
      end;
    end
  );
end;

procedure TAsyncWorkflowExecutor.CheckAndExecutePending;
var
  Step: TAsyncStep;
begin
  FLock.Enter;
  try
    for Step in FSteps.Values do
    begin
      if CanExecute(Step) then
        ExecuteStep(Step);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAsyncWorkflowExecutor.Start;
begin
  CheckAndExecutePending;
end;

function TAsyncWorkflowExecutor.WaitAll(ATimeoutMs: Integer): Boolean;
var
  StartTime: TDateTime;
  AllDone: Boolean;
  Step: TAsyncStep;
begin
  StartTime := Now;

  repeat
    AllDone := True;
    FLock.Enter;
    try
      for Step in FSteps.Values do
      begin
        if not (Step.State in [assCompleted, assFailed, assCancelled]) then
        begin
          AllDone := False;
          Break;
        end;
      end;
    finally
      FLock.Leave;
    end;

    if AllDone then
      Break;

    if (ATimeoutMs <> INFINITE) and (MilliSecondsBetween(Now, StartTime) > ATimeoutMs) then
      Break;

    Sleep(10);
  until False;

  Result := AllDone;
end;

function TAsyncWorkflowExecutor.GetStepState(const AStepId: string): TAsyncStepState;
var
  Step: TAsyncStep;
begin
  FLock.Enter;
  try
    if FSteps.TryGetValue(AStepId, Step) then
      Result := Step.State
    else
      Result := assNotStarted;
  finally
    FLock.Leave;
  end;
end;

function TAsyncWorkflowExecutor.GetSummary: TJSONObject;
var
  Step: TAsyncStep;
  StepsArr: TJSONArray;
  StepObj: TJSONObject;
  Completed, Failed, Running: Integer;
begin
  Result := TJSONObject.Create;
  StepsArr := TJSONArray.Create;
  Completed := 0;
  Failed := 0;
  Running := 0;

  FLock.Enter;
  try
    for Step in FSteps.Values do
    begin
      StepObj := TJSONObject.Create;
      StepObj.AddPair('id', Step.Id);
      StepObj.AddPair('name', Step.Name);
      StepObj.AddPair('state', Integer(Step.State));
      if Step.Error <> '' then
        StepObj.AddPair('error', Step.Error);
      if Step.StartTime > 0 then
        StepObj.AddPair('durationMs', TJSONNumber.Create(
          MilliSecondsBetween(Step.EndTime, Step.StartTime)));
      StepsArr.Add(StepObj);

      case Step.State of
        assCompleted: Inc(Completed);
        assFailed: Inc(Failed);
        assRunning: Inc(Running);
      end;
    end;

    Result.AddPair('totalSteps', TJSONNumber.Create(FSteps.Count));
    Result.AddPair('completed', TJSONNumber.Create(Completed));
    Result.AddPair('failed', TJSONNumber.Create(Failed));
    Result.AddPair('running', TJSONNumber.Create(Running));
    Result.AddPair('steps', StepsArr);
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// Global Functions
// ============================================================================

function GlobalThreadPool: TEnhancedThreadPool;
begin
  if GThreadPool = nil then
  begin
    GThreadPoolLock.Enter;
    try
      if GThreadPool = nil then
        GThreadPool := TEnhancedThreadPool.Create;
    finally
      GThreadPoolLock.Leave;
    end;
  end;
  Result := GThreadPool;
end;

procedure ReleaseGlobalThreadPool;
begin
  GThreadPoolLock.Enter;
  try
    FreeAndNil(GThreadPool);
  finally
    GThreadPoolLock.Leave;
  end;
end;

procedure ParallelFor(AFrom, ATo: Integer; AProc: TProc<Integer>);
var
  Executor: TParallelExecutor;
  Indices: TArray<Integer>;
  i: Integer;
begin
  if AFrom > ATo then
    Exit;

  SetLength(Indices, ATo - AFrom + 1);
  for i := AFrom to ATo do
    Indices[i - AFrom] := i;

  Executor := TParallelExecutor.Create(GlobalThreadPool);
  try
    Executor.ForEach<Integer>(Indices, AProc);
  finally
    Executor.Free;
  end;
end;

initialization
  GThreadPoolLock := TCriticalSection.Create;

finalization
  ReleaseGlobalThreadPool;
  GThreadPoolLock.Free;

end.
