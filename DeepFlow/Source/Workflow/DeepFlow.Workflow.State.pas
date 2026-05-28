unit UniFlow.Workflow.State;
(*
  UniFlow Workflow State Persistence
  ==================================
  工作流状态持久化，支持：
  - SQLite 存储
  - 检查点保存/恢复
  - 执行历史记录
  
  表结�?
  - workflow_instances: 工作流实�?
  - workflow_snapshots: 状态快�?
  - workflow_events: 执行事件
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.DateUtils,
  UniFlow.Workflow.Definition, UniFlow.Workflow.Context, UniFlow.Workflow.Executor;

type
  // ============================================================================
  // 工作流实例状�?
  // ============================================================================
  
  TWorkflowInstanceStatus = (
    wisCreated,     // 已创�?
    wisRunning,     // 运行�?
    wisPaused,      // 已暂�?
    wisWaiting,     // 等待输入
    wisCompleted,   // 已完�?
    wisFailed,      // 已失�?
    wisCancelled    // 已取�?
  );
  
  // ============================================================================
  // 工作流实�?
  // ============================================================================
  
  TWorkflowInstance = class
  private
    FId: string;
    FWorkflowId: string;
    FWorkflowVersion: string;
    FStatus: TWorkflowInstanceStatus;
    FCurrentStepId: string;
    FCurrentStepIndex: Integer;
    FInput: TJSONObject;
    FOutput: TJSONObject;
    FErrorCode: string;
    FErrorMessage: string;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    FCompletedAt: TDateTime;
    FUserId: string;
    FCorrelationId: string;
    FMetadata: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    
    property Id: string read FId write FId;
    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property WorkflowVersion: string read FWorkflowVersion write FWorkflowVersion;
    property Status: TWorkflowInstanceStatus read FStatus write FStatus;
    property CurrentStepId: string read FCurrentStepId write FCurrentStepId;
    property CurrentStepIndex: Integer read FCurrentStepIndex write FCurrentStepIndex;
    property Input: TJSONObject read FInput write FInput;
    property Output: TJSONObject read FOutput write FOutput;
    property ErrorCode: string read FErrorCode write FErrorCode;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    property CompletedAt: TDateTime read FCompletedAt write FCompletedAt;
    property UserId: string read FUserId write FUserId;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
    property Metadata: TJSONObject read FMetadata write FMetadata;
  end;
  
  // ============================================================================
  // 工作流快�?
  // ============================================================================
  
  TWorkflowSnapshot = class
  private
    FInstanceId: string;
    FVersion: Integer;
    FStepId: string;
    FStepIndex: Integer;
    FContextJson: string;
    FCursorJson: string;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    
    property InstanceId: string read FInstanceId write FInstanceId;
    property Version: Integer read FVersion write FVersion;
    property StepId: string read FStepId write FStepId;
    property StepIndex: Integer read FStepIndex write FStepIndex;
    property ContextJson: string read FContextJson write FContextJson;
    property CursorJson: string read FCursorJson write FCursorJson;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;
  
  // ============================================================================
  // 工作流事�?
  // ============================================================================
  
  TWorkflowEventType = (
    wetStarted,       // 工作流开�?
    wetStepStarted,   // 步骤开�?
    wetStepCompleted, // 步骤完成
    wetStepFailed,    // 步骤失败
    wetWaiting,       // 等待输入
    wetResumed,       // 恢复执行
    wetCompleted,     // 工作流完�?
    wetFailed,        // 工作流失�?
    wetCancelled,     // 工作流取�?
    wetStatusChanged  // 状态变化（ENTROPY-006�?
  );
  
  TWorkflowEvent = class
  private
    FId: string;
    FInstanceId: string;
    FEventType: TWorkflowEventType;
    FStepId: string;
    FStepIndex: Integer;
    FPayload: TJSONObject;
    FErrorCode: string;
    FErrorMessage: string;
    FTimestamp: TDateTime;
    FDurationMs: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    
    property Id: string read FId write FId;
    property InstanceId: string read FInstanceId write FInstanceId;
    property EventType: TWorkflowEventType read FEventType write FEventType;
    property StepId: string read FStepId write FStepId;
    property StepIndex: Integer read FStepIndex write FStepIndex;
    property Payload: TJSONObject read FPayload write FPayload;
    property ErrorCode: string read FErrorCode write FErrorCode;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property DurationMs: Integer read FDurationMs write FDurationMs;
  end;
  
  // ============================================================================
  // 状态存储接�?
  // ============================================================================
  
  IWorkflowStateStore = interface
    ['{B1C2D3E4-F5A6-4B7C-8D9E-0F1A2B3C4D5E}']
    
    // 实例操作
    function CreateInstance(AInstance: TWorkflowInstance): string;
    procedure UpdateInstance(AInstance: TWorkflowInstance);
    function GetInstance(const AInstanceId: string): TWorkflowInstance;
    function ListInstances(const AWorkflowId: string; AStatus: TWorkflowInstanceStatus): TObjectList<TWorkflowInstance>;
    procedure DeleteInstance(const AInstanceId: string);
    
    // 快照操作
    procedure SaveSnapshot(ASnapshot: TWorkflowSnapshot);
    function GetLatestSnapshot(const AInstanceId: string): TWorkflowSnapshot;
    function GetSnapshot(const AInstanceId: string; AVersion: Integer): TWorkflowSnapshot;
    function ListSnapshots(const AInstanceId: string): TObjectList<TWorkflowSnapshot>;
    
    // 事件操作
    procedure AppendEvent(AEvent: TWorkflowEvent);
    function GetEvents(const AInstanceId: string): TObjectList<TWorkflowEvent>;
    function GetEventsSince(const AInstanceId: string; ASince: TDateTime): TObjectList<TWorkflowEvent>;
  end;
  
  // ============================================================================
  // 内存状态存储（测试/开发用�?
  // ============================================================================
  
  TMemoryWorkflowStateStore = class(TInterfacedObject, IWorkflowStateStore)
  private
    FInstances: TObjectDictionary<string, TWorkflowInstance>;
    FSnapshots: TObjectDictionary<string, TObjectList<TWorkflowSnapshot>>;
    FEvents: TObjectDictionary<string, TObjectList<TWorkflowEvent>>;
    FLock: TObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    function CreateInstance(AInstance: TWorkflowInstance): string;
    procedure UpdateInstance(AInstance: TWorkflowInstance);
    function GetInstance(const AInstanceId: string): TWorkflowInstance;
    function ListInstances(const AWorkflowId: string; AStatus: TWorkflowInstanceStatus): TObjectList<TWorkflowInstance>;
    procedure DeleteInstance(const AInstanceId: string);
    
    procedure SaveSnapshot(ASnapshot: TWorkflowSnapshot);
    function GetLatestSnapshot(const AInstanceId: string): TWorkflowSnapshot;
    function GetSnapshot(const AInstanceId: string; AVersion: Integer): TWorkflowSnapshot;
    function ListSnapshots(const AInstanceId: string): TObjectList<TWorkflowSnapshot>;
    
    procedure AppendEvent(AEvent: TWorkflowEvent);
    function GetEvents(const AInstanceId: string): TObjectList<TWorkflowEvent>;
    function GetEventsSince(const AInstanceId: string; ASince: TDateTime): TObjectList<TWorkflowEvent>;
  end;
  
  // ============================================================================
  // 工作流状态管理器
  // ============================================================================
  
  TWorkflowStateManager = class
  private
    FStore: IWorkflowStateStore;
    FAutoSaveInterval: Integer;  // 自动保存间隔（步骤数�?
  public
    constructor Create(AStore: IWorkflowStateStore);
    
    /// <summary>创建工作流实�?/summary>
    function CreateWorkflowInstance(
      AWorkflow: TWorkflowDefinition; 
      AInput: TJSONObject;
      const AUserId: string = '';
      const ACorrelationId: string = ''
    ): TWorkflowInstance;
    
    /// <summary>更新实例状�?/summary>
    procedure UpdateInstanceStatus(
      const AInstanceId: string; 
      AStatus: TWorkflowInstanceStatus;
      const ACurrentStepId: string = '';
      ACurrentStepIndex: Integer = -1
    );
    
    /// <summary>标记实例完成</summary>
    procedure MarkCompleted(
      const AInstanceId: string;
      AOutput: TJSONObject = nil
    );
    
    /// <summary>标记实例失败</summary>
    procedure MarkFailed(
      const AInstanceId: string;
      const AErrorCode, AErrorMessage: string
    );
    
    /// <summary>保存检查点</summary>
    procedure SaveCheckpoint(
      const AInstanceId: string;
      AExecutor: TWorkflowExecutor
    );
    
    /// <summary>从检查点恢复</summary>
    procedure RestoreFromCheckpoint(
      const AInstanceId: string;
      AExecutor: TWorkflowExecutor
    );
    
    /// <summary>记录步骤开始事�?/summary>
    procedure RecordStepStarted(
      const AInstanceId: string;
      AStep: TWorkflowStep;
      AStepIndex: Integer
    );
    
    /// <summary>记录步骤完成事件</summary>
    procedure RecordStepCompleted(
      const AInstanceId: string;
      AStep: TWorkflowStep;
      AStepIndex: Integer;
      AResult: TStepResult;
      ADurationMs: Integer
    );
    
    /// <summary>获取实例执行历史</summary>
    function GetExecutionHistory(const AInstanceId: string): TObjectList<TWorkflowEvent>;
    
    /// <summary>获取实例当前状�?/summary>
    function GetInstanceStatus(const AInstanceId: string): TWorkflowInstance;
    
    property Store: IWorkflowStateStore read FStore;
    property AutoSaveInterval: Integer read FAutoSaveInterval write FAutoSaveInterval;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
  function InstanceStatusToStr(AStatus: TWorkflowInstanceStatus): string;
  function StrToInstanceStatus(const S: string): TWorkflowInstanceStatus;
  function EventTypeToStr(AType: TWorkflowEventType): string;
  function StrToEventType(const S: string): TWorkflowEventType;

implementation

uses
  System.SyncObjs;

// ============================================================================
// 辅助函数
// ============================================================================

function InstanceStatusToStr(AStatus: TWorkflowInstanceStatus): string;
begin
  case AStatus of
    wisCreated:   Result := 'created';
    wisRunning:   Result := 'running';
    wisPaused:    Result := 'paused';
    wisWaiting:   Result := 'waiting';
    wisCompleted: Result := 'completed';
    wisFailed:    Result := 'failed';
    wisCancelled: Result := 'cancelled';
  else
    Result := 'unknown';
  end;
end;

function StrToInstanceStatus(const S: string): TWorkflowInstanceStatus;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if LowerS = 'created' then Result := wisCreated
  else if LowerS = 'running' then Result := wisRunning
  else if LowerS = 'paused' then Result := wisPaused
  else if LowerS = 'waiting' then Result := wisWaiting
  else if LowerS = 'completed' then Result := wisCompleted
  else if LowerS = 'failed' then Result := wisFailed
  else if LowerS = 'cancelled' then Result := wisCancelled
  else
    Result := wisCreated;
end;

function EventTypeToStr(AType: TWorkflowEventType): string;
begin
  case AType of
    wetStarted:       Result := 'started';
    wetStepStarted:   Result := 'step_started';
    wetStepCompleted: Result := 'step_completed';
    wetStepFailed:    Result := 'step_failed';
    wetWaiting:       Result := 'waiting';
    wetResumed:       Result := 'resumed';
    wetCompleted:     Result := 'completed';
    wetFailed:        Result := 'failed';
    wetCancelled:     Result := 'cancelled';
    wetStatusChanged: Result := 'status_changed';
  else
    Result := 'unknown';
  end;
end;

function StrToEventType(const S: string): TWorkflowEventType;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if LowerS = 'started' then Result := wetStarted
  else if LowerS = 'step_started' then Result := wetStepStarted
  else if LowerS = 'step_completed' then Result := wetStepCompleted
  else if LowerS = 'step_failed' then Result := wetStepFailed
  else if LowerS = 'waiting' then Result := wetWaiting
  else if LowerS = 'resumed' then Result := wetResumed
  else if LowerS = 'completed' then Result := wetCompleted
  else if LowerS = 'failed' then Result := wetFailed
  else if LowerS = 'cancelled' then Result := wetCancelled
  else if LowerS = 'status_changed' then Result := wetStatusChanged
  else
    Result := wetStarted;
end;

// ============================================================================
// TWorkflowInstance
// ============================================================================

constructor TWorkflowInstance.Create;
begin
  inherited Create;
  FId := TGUID.NewGuid.ToString;
  FStatus := wisCreated;
  FCurrentStepIndex := 0;
  FCreatedAt := Now;
  FUpdatedAt := Now;
end;

destructor TWorkflowInstance.Destroy;
begin
  FInput.Free;
  FOutput.Free;
  FMetadata.Free;
  inherited;
end;

procedure TWorkflowInstance.LoadFromJSON(AJson: TJSONObject);
var
  StatusStr: string;
  DateStr: string;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('id', FId) then;
  if AJson.TryGetValue<string>('workflowId', FWorkflowId) then;
  if AJson.TryGetValue<string>('workflowVersion', FWorkflowVersion) then;
  if AJson.TryGetValue<string>('status', StatusStr) then
    FStatus := StrToInstanceStatus(StatusStr);
  if AJson.TryGetValue<string>('currentStepId', FCurrentStepId) then;
  if AJson.TryGetValue<Integer>('currentStepIndex', FCurrentStepIndex) then;
  if AJson.TryGetValue<string>('errorCode', FErrorCode) then;
  if AJson.TryGetValue<string>('errorMessage', FErrorMessage) then;
  if AJson.TryGetValue<string>('userId', FUserId) then;
  if AJson.TryGetValue<string>('correlationId', FCorrelationId) then;
  
  if AJson.TryGetValue<TJSONObject>('input', FInput) then
    FInput := TJSONObject(FInput.Clone);
  if AJson.TryGetValue<TJSONObject>('output', FOutput) then
    FOutput := TJSONObject(FOutput.Clone);
  if AJson.TryGetValue<TJSONObject>('metadata', FMetadata) then
    FMetadata := TJSONObject(FMetadata.Clone);
  
  if AJson.TryGetValue<string>('createdAt', DateStr) then
    FCreatedAt := ISO8601ToDate(DateStr);
  if AJson.TryGetValue<string>('updatedAt', DateStr) then
    FUpdatedAt := ISO8601ToDate(DateStr);
  if AJson.TryGetValue<string>('completedAt', DateStr) then
    FCompletedAt := ISO8601ToDate(DateStr);
end;

function TWorkflowInstance.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('workflowId', FWorkflowId);
  Result.AddPair('workflowVersion', FWorkflowVersion);
  Result.AddPair('status', InstanceStatusToStr(FStatus));
  Result.AddPair('currentStepId', FCurrentStepId);
  Result.AddPair('currentStepIndex', TJSONNumber.Create(FCurrentStepIndex));
  
  if FErrorCode <> '' then
    Result.AddPair('errorCode', FErrorCode);
  if FErrorMessage <> '' then
    Result.AddPair('errorMessage', FErrorMessage);
  if FUserId <> '' then
    Result.AddPair('userId', FUserId);
  if FCorrelationId <> '' then
    Result.AddPair('correlationId', FCorrelationId);
  
  if Assigned(FInput) then
    Result.AddPair('input', TJSONObject(FInput.Clone));
  if Assigned(FOutput) then
    Result.AddPair('output', TJSONObject(FOutput.Clone));
  if Assigned(FMetadata) then
    Result.AddPair('metadata', TJSONObject(FMetadata.Clone));
  
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
  Result.AddPair('updatedAt', DateToISO8601(FUpdatedAt));
  if FCompletedAt > 0 then
    Result.AddPair('completedAt', DateToISO8601(FCompletedAt));
end;

// ============================================================================
// TWorkflowSnapshot
// ============================================================================

constructor TWorkflowSnapshot.Create;
begin
  inherited Create;
  FVersion := 1;
  FCreatedAt := Now;
end;

procedure TWorkflowSnapshot.LoadFromJSON(AJson: TJSONObject);
var
  DateStr: string;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('instanceId', FInstanceId) then;
  if AJson.TryGetValue<Integer>('version', FVersion) then;
  if AJson.TryGetValue<string>('stepId', FStepId) then;
  if AJson.TryGetValue<Integer>('stepIndex', FStepIndex) then;
  if AJson.TryGetValue<string>('contextJson', FContextJson) then;
  if AJson.TryGetValue<string>('cursorJson', FCursorJson) then;
  if AJson.TryGetValue<string>('createdAt', DateStr) then
    FCreatedAt := ISO8601ToDate(DateStr);
end;

function TWorkflowSnapshot.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('instanceId', FInstanceId);
  Result.AddPair('version', TJSONNumber.Create(FVersion));
  Result.AddPair('stepId', FStepId);
  Result.AddPair('stepIndex', TJSONNumber.Create(FStepIndex));
  Result.AddPair('contextJson', FContextJson);
  Result.AddPair('cursorJson', FCursorJson);
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
end;

// ============================================================================
// TWorkflowEvent
// ============================================================================

constructor TWorkflowEvent.Create;
begin
  inherited Create;
  FId := TGUID.NewGuid.ToString;
  FTimestamp := Now;
end;

destructor TWorkflowEvent.Destroy;
begin
  FPayload.Free;
  inherited;
end;

procedure TWorkflowEvent.LoadFromJSON(AJson: TJSONObject);
var
  TypeStr, DateStr: string;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('id', FId) then;
  if AJson.TryGetValue<string>('instanceId', FInstanceId) then;
  if AJson.TryGetValue<string>('eventType', TypeStr) then
    FEventType := StrToEventType(TypeStr);
  if AJson.TryGetValue<string>('stepId', FStepId) then;
  if AJson.TryGetValue<Integer>('stepIndex', FStepIndex) then;
  if AJson.TryGetValue<string>('errorCode', FErrorCode) then;
  if AJson.TryGetValue<string>('errorMessage', FErrorMessage) then;
  if AJson.TryGetValue<Integer>('durationMs', FDurationMs) then;
  
  if AJson.TryGetValue<TJSONObject>('payload', FPayload) then
    FPayload := TJSONObject(FPayload.Clone);
  
  if AJson.TryGetValue<string>('timestamp', DateStr) then
    FTimestamp := ISO8601ToDate(DateStr);
end;

function TWorkflowEvent.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('instanceId', FInstanceId);
  Result.AddPair('eventType', EventTypeToStr(FEventType));
  Result.AddPair('stepId', FStepId);
  Result.AddPair('stepIndex', TJSONNumber.Create(FStepIndex));
  
  if FErrorCode <> '' then
    Result.AddPair('errorCode', FErrorCode);
  if FErrorMessage <> '' then
    Result.AddPair('errorMessage', FErrorMessage);
  if FDurationMs > 0 then
    Result.AddPair('durationMs', TJSONNumber.Create(FDurationMs));
  
  if Assigned(FPayload) then
    Result.AddPair('payload', TJSONObject(FPayload.Clone));
  
  Result.AddPair('timestamp', DateToISO8601(FTimestamp));
end;

// ============================================================================
// TMemoryWorkflowStateStore
// ============================================================================

constructor TMemoryWorkflowStateStore.Create;
begin
  inherited Create;
  FInstances := TObjectDictionary<string, TWorkflowInstance>.Create([doOwnsValues]);
  FSnapshots := TObjectDictionary<string, TObjectList<TWorkflowSnapshot>>.Create([doOwnsValues]);
  FEvents := TObjectDictionary<string, TObjectList<TWorkflowEvent>>.Create([doOwnsValues]);
  FLock := TObject.Create;
end;

destructor TMemoryWorkflowStateStore.Destroy;
begin
  FLock.Free;
  FInstances.Free;
  FSnapshots.Free;
  FEvents.Free;
  inherited;
end;

function TMemoryWorkflowStateStore.CreateInstance(AInstance: TWorkflowInstance): string;
var
  Clone: TWorkflowInstance;
  Json: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    Result := AInstance.Id;
    
    // 创建副本存储
    Clone := TWorkflowInstance.Create;
    Json := AInstance.ToJSON;
    try
      Clone.LoadFromJSON(Json);
    finally
      Json.Free;
    end;
    
    FInstances.Add(Result, Clone);
    FSnapshots.Add(Result, TObjectList<TWorkflowSnapshot>.Create(True));
    FEvents.Add(Result, TObjectList<TWorkflowEvent>.Create(True));
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TMemoryWorkflowStateStore.UpdateInstance(AInstance: TWorkflowInstance);
var
  Existing: TWorkflowInstance;
  Json: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    if FInstances.TryGetValue(AInstance.Id, Existing) then
    begin
      Json := AInstance.ToJSON;
      try
        Existing.LoadFromJSON(Json);
      finally
        Json.Free;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.GetInstance(const AInstanceId: string): TWorkflowInstance;
var
  Instance: TWorkflowInstance;
  Json: TJSONObject;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    if FInstances.TryGetValue(AInstanceId, Instance) then
    begin
      Result := TWorkflowInstance.Create;
      Json := Instance.ToJSON;
      try
        Result.LoadFromJSON(Json);
      finally
        Json.Free;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.ListInstances(const AWorkflowId: string; AStatus: TWorkflowInstanceStatus): TObjectList<TWorkflowInstance>;
var
  Pair: TPair<string, TWorkflowInstance>;
  Clone: TWorkflowInstance;
  Json: TJSONObject;
begin
  Result := TObjectList<TWorkflowInstance>.Create(True);
  TMonitor.Enter(FLock);
  try
    for Pair in FInstances do
    begin
      if (AWorkflowId = '') or (Pair.Value.WorkflowId = AWorkflowId) then
      begin
        if (AStatus = wisCreated) or (Pair.Value.Status = AStatus) then
        begin
          Clone := TWorkflowInstance.Create;
          Json := Pair.Value.ToJSON;
          try
            Clone.LoadFromJSON(Json);
          finally
            Json.Free;
          end;
          Result.Add(Clone);
        end;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TMemoryWorkflowStateStore.DeleteInstance(const AInstanceId: string);
begin
  TMonitor.Enter(FLock);
  try
    FInstances.Remove(AInstanceId);
    FSnapshots.Remove(AInstanceId);
    FEvents.Remove(AInstanceId);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TMemoryWorkflowStateStore.SaveSnapshot(ASnapshot: TWorkflowSnapshot);
var
  Snapshots: TObjectList<TWorkflowSnapshot>;
  Clone: TWorkflowSnapshot;
  Json: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    if FSnapshots.TryGetValue(ASnapshot.InstanceId, Snapshots) then
    begin
      Clone := TWorkflowSnapshot.Create;
      Json := ASnapshot.ToJSON;
      try
        Clone.LoadFromJSON(Json);
      finally
        Json.Free;
      end;
      
      // 设置版本�?
      Clone.FVersion := Snapshots.Count + 1;
      Snapshots.Add(Clone);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.GetLatestSnapshot(const AInstanceId: string): TWorkflowSnapshot;
var
  Snapshots: TObjectList<TWorkflowSnapshot>;
  Latest: TWorkflowSnapshot;
  Json: TJSONObject;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    if FSnapshots.TryGetValue(AInstanceId, Snapshots) then
    begin
      if Snapshots.Count > 0 then
      begin
        Latest := Snapshots[Snapshots.Count - 1];
        Result := TWorkflowSnapshot.Create;
        Json := Latest.ToJSON;
        try
          Result.LoadFromJSON(Json);
        finally
          Json.Free;
        end;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.GetSnapshot(const AInstanceId: string; AVersion: Integer): TWorkflowSnapshot;
var
  Snapshots: TObjectList<TWorkflowSnapshot>;
  Snapshot: TWorkflowSnapshot;
  Json: TJSONObject;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    if FSnapshots.TryGetValue(AInstanceId, Snapshots) then
    begin
      for Snapshot in Snapshots do
      begin
        if Snapshot.Version = AVersion then
        begin
          Result := TWorkflowSnapshot.Create;
          Json := Snapshot.ToJSON;
          try
            Result.LoadFromJSON(Json);
          finally
            Json.Free;
          end;
          Break;
        end;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.ListSnapshots(const AInstanceId: string): TObjectList<TWorkflowSnapshot>;
var
  Snapshots: TObjectList<TWorkflowSnapshot>;
  Snapshot: TWorkflowSnapshot;
  Clone: TWorkflowSnapshot;
  Json: TJSONObject;
begin
  Result := TObjectList<TWorkflowSnapshot>.Create(True);
  TMonitor.Enter(FLock);
  try
    if FSnapshots.TryGetValue(AInstanceId, Snapshots) then
    begin
      for Snapshot in Snapshots do
      begin
        Clone := TWorkflowSnapshot.Create;
        Json := Snapshot.ToJSON;
        try
          Clone.LoadFromJSON(Json);
        finally
          Json.Free;
        end;
        Result.Add(Clone);
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TMemoryWorkflowStateStore.AppendEvent(AEvent: TWorkflowEvent);
var
  Events: TObjectList<TWorkflowEvent>;
  Clone: TWorkflowEvent;
  Json: TJSONObject;
begin
  TMonitor.Enter(FLock);
  try
    if FEvents.TryGetValue(AEvent.InstanceId, Events) then
    begin
      Clone := TWorkflowEvent.Create;
      Json := AEvent.ToJSON;
      try
        Clone.LoadFromJSON(Json);
      finally
        Json.Free;
      end;
      Events.Add(Clone);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.GetEvents(const AInstanceId: string): TObjectList<TWorkflowEvent>;
var
  Events: TObjectList<TWorkflowEvent>;
  Event: TWorkflowEvent;
  Clone: TWorkflowEvent;
  Json: TJSONObject;
begin
  Result := TObjectList<TWorkflowEvent>.Create(True);
  TMonitor.Enter(FLock);
  try
    if FEvents.TryGetValue(AInstanceId, Events) then
    begin
      for Event in Events do
      begin
        Clone := TWorkflowEvent.Create;
        Json := Event.ToJSON;
        try
          Clone.LoadFromJSON(Json);
        finally
          Json.Free;
        end;
        Result.Add(Clone);
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TMemoryWorkflowStateStore.GetEventsSince(const AInstanceId: string; ASince: TDateTime): TObjectList<TWorkflowEvent>;
var
  Events: TObjectList<TWorkflowEvent>;
  Event: TWorkflowEvent;
  Clone: TWorkflowEvent;
  Json: TJSONObject;
begin
  Result := TObjectList<TWorkflowEvent>.Create(True);
  TMonitor.Enter(FLock);
  try
    if FEvents.TryGetValue(AInstanceId, Events) then
    begin
      for Event in Events do
      begin
        if Event.Timestamp >= ASince then
        begin
          Clone := TWorkflowEvent.Create;
          Json := Event.ToJSON;
          try
            Clone.LoadFromJSON(Json);
          finally
            Json.Free;
          end;
          Result.Add(Clone);
        end;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

// ============================================================================
// TWorkflowStateManager
// ============================================================================

constructor TWorkflowStateManager.Create(AStore: IWorkflowStateStore);
begin
  inherited Create;
  FStore := AStore;
  FAutoSaveInterval := 5;  // �?5 步自动保�?
end;

function TWorkflowStateManager.CreateWorkflowInstance(
  AWorkflow: TWorkflowDefinition;
  AInput: TJSONObject;
  const AUserId: string;
  const ACorrelationId: string
): TWorkflowInstance;
var
  Event: TWorkflowEvent;
begin
  Result := TWorkflowInstance.Create;
  Result.WorkflowId := AWorkflow.Id;
  Result.WorkflowVersion := AWorkflow.Version;
  Result.Status := wisCreated;
  Result.UserId := AUserId;
  if ACorrelationId <> '' then
    Result.CorrelationId := ACorrelationId
  else
    Result.CorrelationId := TGUID.NewGuid.ToString;
  
  if AInput <> nil then
    Result.Input := TJSONObject(AInput.Clone);
  
  FStore.CreateInstance(Result);
  
  // 记录开始事�?
  Event := TWorkflowEvent.Create;
  Event.InstanceId := Result.Id;
  Event.EventType := wetStarted;
  if AInput <> nil then
    Event.Payload := TJSONObject(AInput.Clone);
  FStore.AppendEvent(Event);
  Event.Free;
end;

procedure TWorkflowStateManager.UpdateInstanceStatus(
  const AInstanceId: string;
  AStatus: TWorkflowInstanceStatus;
  const ACurrentStepId: string;
  ACurrentStepIndex: Integer
);
var
  Instance: TWorkflowInstance;
  Event: TWorkflowEvent;
  OldStatus: TWorkflowInstanceStatus;
begin
  Instance := FStore.GetInstance(AInstanceId);
  if Instance = nil then Exit;
  
  try
    OldStatus := Instance.Status;
    Instance.Status := AStatus;
    Instance.UpdatedAt := Now;
    
    if ACurrentStepId <> '' then
      Instance.CurrentStepId := ACurrentStepId;
    if ACurrentStepIndex >= 0 then
      Instance.CurrentStepIndex := ACurrentStepIndex;
    
    FStore.UpdateInstance(Instance);
    
    // ENTROPY-006: 记录状态变化事件（Event Sourcing 合规�?
    Event := TWorkflowEvent.Create;
    try
      Event.InstanceId := AInstanceId;
      Event.EventType := wetStatusChanged;
      Event.Payload := TJSONObject.Create;
      Event.Payload.AddPair('oldStatus', InstanceStatusToStr(OldStatus));
      Event.Payload.AddPair('newStatus', InstanceStatusToStr(AStatus));
      if ACurrentStepId <> '' then
        Event.Payload.AddPair('currentStepId', ACurrentStepId);
      if ACurrentStepIndex >= 0 then
        Event.Payload.AddPair('currentStepIndex', TJSONNumber.Create(ACurrentStepIndex));
      FStore.AppendEvent(Event);
    finally
      Event.Free;
    end;
  finally
    Instance.Free;
  end;
end;

procedure TWorkflowStateManager.MarkCompleted(
  const AInstanceId: string;
  AOutput: TJSONObject
);
var
  Instance: TWorkflowInstance;
  Event: TWorkflowEvent;
begin
  Instance := FStore.GetInstance(AInstanceId);
  if Instance = nil then Exit;
  
  try
    Instance.Status := wisCompleted;
    Instance.UpdatedAt := Now;
    Instance.CompletedAt := Now;
    
    if AOutput <> nil then
      Instance.Output := TJSONObject(AOutput.Clone);
    
    FStore.UpdateInstance(Instance);
    
    // 记录完成事件
    Event := TWorkflowEvent.Create;
    Event.InstanceId := AInstanceId;
    Event.EventType := wetCompleted;
    if AOutput <> nil then
      Event.Payload := TJSONObject(AOutput.Clone);
    FStore.AppendEvent(Event);
    Event.Free;
  finally
    Instance.Free;
  end;
end;

procedure TWorkflowStateManager.MarkFailed(
  const AInstanceId: string;
  const AErrorCode, AErrorMessage: string
);
var
  Instance: TWorkflowInstance;
  Event: TWorkflowEvent;
begin
  Instance := FStore.GetInstance(AInstanceId);
  if Instance = nil then Exit;
  
  try
    Instance.Status := wisFailed;
    Instance.UpdatedAt := Now;
    Instance.CompletedAt := Now;
    Instance.ErrorCode := AErrorCode;
    Instance.ErrorMessage := AErrorMessage;
    
    FStore.UpdateInstance(Instance);
    
    // 记录失败事件
    Event := TWorkflowEvent.Create;
    Event.InstanceId := AInstanceId;
    Event.EventType := wetFailed;
    Event.ErrorCode := AErrorCode;
    Event.ErrorMessage := AErrorMessage;
    FStore.AppendEvent(Event);
    Event.Free;
  finally
    Instance.Free;
  end;
end;

procedure TWorkflowStateManager.SaveCheckpoint(
  const AInstanceId: string;
  AExecutor: TWorkflowExecutor
);
var
  Snapshot: TWorkflowSnapshot;
  ExecutorSnapshot: TJSONObject;
  ContextJson, CursorJson: TJSONObject;
begin
  Snapshot := TWorkflowSnapshot.Create;
  try
    Snapshot.InstanceId := AInstanceId;
    Snapshot.StepId := AExecutor.Cursor.StepId;
    Snapshot.StepIndex := AExecutor.Cursor.StepIndex;
    
    ExecutorSnapshot := AExecutor.GetSnapshot;
    try
      if ExecutorSnapshot.TryGetValue<TJSONObject>('context', ContextJson) then
        Snapshot.ContextJson := ContextJson.ToJSON;
      if ExecutorSnapshot.TryGetValue<TJSONObject>('cursor', CursorJson) then
        Snapshot.CursorJson := CursorJson.ToJSON;
    finally
      ExecutorSnapshot.Free;
    end;
    
    FStore.SaveSnapshot(Snapshot);
  finally
    Snapshot.Free;
  end;
end;

procedure TWorkflowStateManager.RestoreFromCheckpoint(
  const AInstanceId: string;
  AExecutor: TWorkflowExecutor
);
var
  Snapshot: TWorkflowSnapshot;
  RestoreJson: TJSONObject;
  ContextJson, CursorJson: TJSONValue;
begin
  Snapshot := FStore.GetLatestSnapshot(AInstanceId);
  if Snapshot = nil then Exit;
  
  try
    RestoreJson := TJSONObject.Create;
    try
      if Snapshot.ContextJson <> '' then
      begin
        ContextJson := TJSONObject.ParseJSONValue(Snapshot.ContextJson);
        if ContextJson <> nil then
          RestoreJson.AddPair('context', ContextJson);
      end;
      
      if Snapshot.CursorJson <> '' then
      begin
        CursorJson := TJSONObject.ParseJSONValue(Snapshot.CursorJson);
        if CursorJson <> nil then
          RestoreJson.AddPair('cursor', CursorJson);
      end;
      
      AExecutor.LoadFromSnapshot(RestoreJson);
    finally
      RestoreJson.Free;
    end;
  finally
    Snapshot.Free;
  end;
end;

procedure TWorkflowStateManager.RecordStepStarted(
  const AInstanceId: string;
  AStep: TWorkflowStep;
  AStepIndex: Integer
);
var
  Event: TWorkflowEvent;
begin
  Event := TWorkflowEvent.Create;
  try
    Event.InstanceId := AInstanceId;
    Event.EventType := wetStepStarted;
    Event.StepId := AStep.Id;
    Event.StepIndex := AStepIndex;
    
    FStore.AppendEvent(Event);
  finally
    Event.Free;
  end;
  
  // 更新实例状�?
  UpdateInstanceStatus(AInstanceId, wisRunning, AStep.Id, AStepIndex);
end;

procedure TWorkflowStateManager.RecordStepCompleted(
  const AInstanceId: string;
  AStep: TWorkflowStep;
  AStepIndex: Integer;
  AResult: TStepResult;
  ADurationMs: Integer
);
var
  Event: TWorkflowEvent;
begin
  Event := TWorkflowEvent.Create;
  try
    Event.InstanceId := AInstanceId;
    Event.StepId := AStep.Id;
    Event.StepIndex := AStepIndex;
    Event.DurationMs := ADurationMs;
    
    if AResult.Success then
    begin
      Event.EventType := wetStepCompleted;
      if AResult.Output <> nil then
        Event.Payload := TJSONObject.Create.AddPair('output', AResult.Output.Clone as TJSONValue) as TJSONObject;
    end
    else
    begin
      Event.EventType := wetStepFailed;
      Event.ErrorCode := AResult.ErrorCode;
      Event.ErrorMessage := AResult.ErrorMessage;
    end;
    
    FStore.AppendEvent(Event);
  finally
    Event.Free;
  end;
end;

function TWorkflowStateManager.GetExecutionHistory(const AInstanceId: string): TObjectList<TWorkflowEvent>;
begin
  Result := FStore.GetEvents(AInstanceId);
end;

function TWorkflowStateManager.GetInstanceStatus(const AInstanceId: string): TWorkflowInstance;
begin
  Result := FStore.GetInstance(AInstanceId);
end;

end.
