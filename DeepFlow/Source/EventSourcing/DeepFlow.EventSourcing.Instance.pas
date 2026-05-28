unit UniFlow.EventSourcing.Instance;
(*
  UniFlow Event Sourcing - FlowInstance Manager
  ==============================================
  
  流程实例生命周期管理�?
  
  核心职责:
  - 创建流程实例（CreateFlow�?
  - 状态迁移（TransitionTo�?
  - 事件发布（EmitEvent�?
  - 实例查询（GetInstance�?
  
  状态机:
  Created �?Running �?(WaitingUser)* �?(Running)* �?(Succeeded | Failed | Cancelled)
  
  CQRS 分离:
  - Write 路径: 通过 EmitEvent 写入事件
  - Read 路径: 通过 Snapshot + 增量事件重建状�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.DateUtils, System.Variants,
  UniFlow.EventSourcing.Types,
  UniFlow.EventSourcing.Store;

type
  // ============================================================================
  // 流程实例管理�?
  // ============================================================================
  
  /// <summary>流程创建参数</summary>
  TCreateFlowParams = record
    FlowType: TUniFlowType;
    Source: string;
    UserId: string;
    SessionId: string;
    RootNodePath: string;
    Metadata: TJSONObject;
    
    class function Create(AType: TUniFlowType; const ASource: string): TCreateFlowParams; static;
  end;
  
  /// <summary>事件发布结果</summary>
  TEmitResult = record
    Success: Boolean;
    EventId: string;
    SequenceNumber: Int64;
    NewStatus: TUniFlowStatus;
    ErrorMessage: string;
    SnapshotCreated: Boolean;
    
    class function Ok(const AEventId: string; ASeq: Int64; AStatus: TUniFlowStatus): TEmitResult; static;
    class function Fail(const AMessage: string): TEmitResult; static;
  end;
  
  /// <summary>状态迁移结�?/summary>
  TTransitionResult = record
    Success: Boolean;
    OldStatus: TUniFlowStatus;
    NewStatus: TUniFlowStatus;
    ErrorMessage: string;
    
    class function Ok(AOld, ANew: TUniFlowStatus): TTransitionResult; static;
    class function Fail(const AMessage: string; AOld: TUniFlowStatus): TTransitionResult; static;
  end;
  
  /// <summary>
  /// 流程实例管理�?- 核心管理�?
  /// </summary>
  TFlowInstanceManager = class
  private
    FStore: IEventStore;
    FSnapshotManager: TSnapshotManager;
    FInstances: TObjectDictionary<string, TFlowInstance>;
    FLock: TCriticalSection;
    
    function LoadInstance(const AFlowId: string): TFlowInstance;
    procedure SaveInstance(AInstance: TFlowInstance);
    procedure UpdateInstanceFromEvent(AInstance: TFlowInstance; AEvent: TUniFlowEvent);
    function DetermineNewStatus(AInstance: TFlowInstance; AEvent: TUniFlowEvent): TUniFlowStatus;
    function BuildCurrentState(const AFlowId: string): TJSONObject;
  public
    constructor Create(AStore: IEventStore; ASnapshotPolicy: TSnapshotPolicy);
    destructor Destroy; override;
    
    /// <summary>创建新流程实�?/summary>
    function CreateFlow(const AParams: TCreateFlowParams): TFlowInstance;
    
    /// <summary>获取流程实例</summary>
    function GetInstance(const AFlowId: string): TFlowInstance;
    
    /// <summary>检查流程是否存�?/summary>
    function FlowExists(const AFlowId: string): Boolean;
    
    /// <summary>发布事件</summary>
    /// <remarks>
    /// 这是状态变化的唯一入口�?
    /// 事件发布后，会自动更新流程状态，并在必要时生成快照�?
    /// </remarks>
    function EmitEvent(AEvent: TUniFlowEvent): TEmitResult;
    
    /// <summary>发布 Started 事件</summary>
    function EmitStarted(const AFlowId, AStep, ASource: string): TEmitResult;
    
    /// <summary>发布 Succeeded 事件</summary>
    function EmitSucceeded(const AFlowId, AStep, ASource: string;
      APayload: TJSONObject = nil): TEmitResult;
    
    /// <summary>发布 Failed 事件</summary>
    function EmitFailed(const AFlowId, AStep, ASource, AErrorCode, AErrorMessage: string): TEmitResult;
    
    /// <summary>状态迁�?/summary>
    /// <remarks>
    /// 内部方法，通过发布特殊事件来实现�?
    /// 推荐使用 EmitEvent 而非直接调用此方法�?
    /// </remarks>
    function TransitionTo(const AFlowId: string; ANewStatus: TUniFlowStatus;
      const AReason: string = ''): TTransitionResult;
    
    /// <summary>开始流�?/summary>
    function StartFlow(const AFlowId: string): TTransitionResult;
    
    /// <summary>完成流程</summary>
    function CompleteFlow(const AFlowId: string): TTransitionResult;
    
    /// <summary>失败流程</summary>
    function FailFlow(const AFlowId, AErrorCode, AErrorMessage: string): TTransitionResult;
    
    /// <summary>取消流程</summary>
    function CancelFlow(const AFlowId: string; const AReason: string = ''): TTransitionResult;
    
    /// <summary>暂停流程（等待用户）</summary>
    function PauseFlow(const AFlowId: string): TTransitionResult;
    
    /// <summary>恢复流程</summary>
    function ResumeFlow(const AFlowId: string): TTransitionResult;
    
    /// <summary>获取所有流�?/summary>
    function GetAllFlows: TArray<TFlowInstance>;
    
    /// <summary>获取活跃流程（非终态）</summary>
    function GetActiveFlows: TArray<TFlowInstance>;
    
    /// <summary>获取流程的所有事�?/summary>
    function GetFlowEvents(const AFlowId: string; AFromSeq: Int64 = 1): TArray<TUniFlowEvent>;
    
    /// <summary>获取流程的最新快�?/summary>
    function GetLatestSnapshot(const AFlowId: string): TUniFlowSnapshot;
    
    property Store: IEventStore read FStore;
    property SnapshotManager: TSnapshotManager read FSnapshotManager;
  end;
  
  // ============================================================================
  // 流程构建�?
  // ============================================================================
  
  /// <summary>
  /// 流程构建�?- 流式 API 创建流程
  /// </summary>
  TFlowBuilder = class
  private
    FManager: TFlowInstanceManager;
    FParams: TCreateFlowParams;
  public
    constructor Create(AManager: TFlowInstanceManager);
    
    function WithType(AType: TUniFlowType): TFlowBuilder;
    function WithSource(const ASource: string): TFlowBuilder;
    function WithUser(const AUserId: string): TFlowBuilder;
    function WithSession(const ASessionId: string): TFlowBuilder;
    function WithNodePath(const APath: string): TFlowBuilder;
    function WithMetadata(AMetadata: TJSONObject): TFlowBuilder;
    function WithMetadataValue(const AKey: string; const AValue: Variant): TFlowBuilder;
    
    function Build: TFlowInstance;
    function BuildAndStart: TFlowInstance;
  end;
  
  // ============================================================================
  // 流程会话
  // ============================================================================
  
  /// <summary>
  /// 流程会话 - 简化流程内事件发布
  /// </summary>
  TFlowSession = class
  private
    FManager: TFlowInstanceManager;
    FFlowId: string;
    FSource: string;
    FCurrentStep: string;
  public
    constructor Create(AManager: TFlowInstanceManager; const AFlowId, ASource: string);
    
    /// <summary>开始步�?/summary>
    function BeginStep(const AStepName: string): TFlowSession;
    
    /// <summary>完成当前步骤</summary>
    function EndStep(APayload: TJSONObject = nil): TFlowSession;
    
    /// <summary>步骤失败</summary>
    function FailStep(const AErrorCode, AErrorMessage: string): TFlowSession;
    
    /// <summary>发布自定义事�?/summary>
    function Emit(const AStep: string; AStatus: TEventStatus;
      APayload: TJSONObject = nil): TFlowSession;
    
    /// <summary>完成整个流程</summary>
    function Complete: TFlowSession;
    
    /// <summary>失败整个流程</summary>
    function Fail(const AErrorCode, AErrorMessage: string): TFlowSession;
    
    /// <summary>获取当前流程实例</summary>
    function GetInstance: TFlowInstance;
    
    property FlowId: string read FFlowId;
    property Source: string read FSource;
    property CurrentStep: string read FCurrentStep;
  end;

implementation

// ============================================================================
// TCreateFlowParams
// ============================================================================

class function TCreateFlowParams.Create(AType: TUniFlowType; const ASource: string): TCreateFlowParams;
begin
  Result := Default(TCreateFlowParams);
  Result.FlowType := AType;
  Result.Source := ASource;
end;

// ============================================================================
// TEmitResult
// ============================================================================

class function TEmitResult.Ok(const AEventId: string; ASeq: Int64;
  AStatus: TUniFlowStatus): TEmitResult;
begin
  Result.Success := True;
  Result.EventId := AEventId;
  Result.SequenceNumber := ASeq;
  Result.NewStatus := AStatus;
  Result.ErrorMessage := '';
  Result.SnapshotCreated := False;
end;

class function TEmitResult.Fail(const AMessage: string): TEmitResult;
begin
  Result.Success := False;
  Result.EventId := '';
  Result.SequenceNumber := 0;
  Result.NewStatus := ufsCreated;
  Result.ErrorMessage := AMessage;
  Result.SnapshotCreated := False;
end;

// ============================================================================
// TTransitionResult
// ============================================================================

class function TTransitionResult.Ok(AOld, ANew: TUniFlowStatus): TTransitionResult;
begin
  Result.Success := True;
  Result.OldStatus := AOld;
  Result.NewStatus := ANew;
  Result.ErrorMessage := '';
end;

class function TTransitionResult.Fail(const AMessage: string; AOld: TUniFlowStatus): TTransitionResult;
begin
  Result.Success := False;
  Result.OldStatus := AOld;
  Result.NewStatus := AOld;
  Result.ErrorMessage := AMessage;
end;

// ============================================================================
// TFlowInstanceManager
// ============================================================================

constructor TFlowInstanceManager.Create(AStore: IEventStore; ASnapshotPolicy: TSnapshotPolicy);
begin
  inherited Create;
  FStore := AStore;
  FSnapshotManager := TSnapshotManager.Create(AStore, ASnapshotPolicy);
  FInstances := TObjectDictionary<string, TFlowInstance>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
end;

destructor TFlowInstanceManager.Destroy;
begin
  FInstances.Free;
  FSnapshotManager.Free;
  FLock.Free;
  inherited;
end;

function TFlowInstanceManager.LoadInstance(const AFlowId: string): TFlowInstance;
var
  Snapshot: TUniFlowSnapshot;
  Events: TArray<TUniFlowEvent>;
  Query: TEventQuery;
  Event: TUniFlowEvent;
begin
  // 检查缓�?
  FLock.Enter;
  try
    if FInstances.TryGetValue(AFlowId, Result) then
      Exit;
  finally
    FLock.Leave;
  end;
  
  // 从最新快照恢�?
  Snapshot := FStore.GetSnapshot(TSnapshotQuery.Latest(AFlowId));
  if Snapshot <> nil then
  try
    Result := TFlowInstance.Create;
    Result.Id := AFlowId;
    Result.Status := Snapshot.FlowStatus;
    Result.EventCount := Snapshot.EventSequence;
    
    // 从快照中恢复其他属�?
    if Snapshot.StateJson.Count > 0 then
    begin
      var StateObj: TJSONObject;
      if Snapshot.StateJson.TryGetValue<TJSONObject>('instance', StateObj) then
        Result.LoadFromJSON(StateObj);
    end;
    
    // 从快照之后的事件继续恢复
    Query := TEventQuery.Create(AFlowId);
    Query.FromSequence := Snapshot.EventSequence + 1;
    Events := FStore.ReadEvents(Query);
    try
      for Event in Events do
        UpdateInstanceFromEvent(Result, Event);
    finally
      for Event in Events do
        Event.Free;
    end;
  finally
    Snapshot.Free;
  end
  else
  begin
    // 没有快照，从事件重建
    if not FStore.FlowExists(AFlowId) then
      Exit(nil);
      
    Query := TEventQuery.Create(AFlowId);
    Events := FStore.ReadEvents(Query);
    if Length(Events) = 0 then
      Exit(nil);
      
    try
      Result := TFlowInstance.Create;
      Result.Id := AFlowId;
      for Event in Events do
        UpdateInstanceFromEvent(Result, Event);
    finally
      for Event in Events do
        Event.Free;
    end;
  end;
  
  // 缓存
  FLock.Enter;
  try
    if not FInstances.ContainsKey(AFlowId) then
      FInstances.Add(AFlowId, Result)
    else
    begin
      Result.Free;
      FInstances.TryGetValue(AFlowId, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TFlowInstanceManager.SaveInstance(AInstance: TFlowInstance);
begin
  FLock.Enter;
  try
    if not FInstances.ContainsKey(AInstance.Id) then
      FInstances.Add(AInstance.Id, AInstance);
  finally
    FLock.Leave;
  end;
end;

procedure TFlowInstanceManager.UpdateInstanceFromEvent(AInstance: TFlowInstance;
  AEvent: TUniFlowEvent);
begin
  AInstance.UpdatedAt := AEvent.Timestamp;
  AInstance.LastEventId := AEvent.Id;
  AInstance.EventCount := AInstance.EventCount + 1;
  
  // 从特殊事件更新状�?
  if AEvent.Step = '_flow_status' then
  begin
    var StatusStr: string;
    if AEvent.Payload.TryGetValue<string>('newStatus', StatusStr) then
      AInstance.Status := StringToFlowStatus(StatusStr);
    if AInstance.IsTerminal then
      AInstance.CompletedAt := AEvent.Timestamp;
  end
  else
  begin
    // 根据事件状态推断流程状�?
    AInstance.Status := DetermineNewStatus(AInstance, AEvent);
  end;
  
  // 从事�?payload 更新元数�?
  if AEvent.FlowType <> uftCustom then
    AInstance.FlowType := AEvent.FlowType;
end;

function TFlowInstanceManager.DetermineNewStatus(AInstance: TFlowInstance;
  AEvent: TUniFlowEvent): TUniFlowStatus;
begin
  Result := AInstance.Status;
  
  // 如果是终态，不再变化
  if AInstance.IsTerminal then
    Exit;
  
  // 根据事件状态推�?
  case AEvent.Status of
    esStarted:
      if AInstance.Status = ufsCreated then
        Result := ufsRunning;
    esSucceeded:
      // 保持 Running
      Result := ufsRunning;
    esFailed:
      // 单个步骤失败不一定导致流程失�?
      // 除非是特定的终态事�?
      if AEvent.Step = '_flow_complete' then
        Result := ufsFailed;
  end;
end;

function TFlowInstanceManager.BuildCurrentState(const AFlowId: string): TJSONObject;
var
  Instance: TFlowInstance;
begin
  Result := TJSONObject.Create;
  Instance := GetInstance(AFlowId);
  if Instance <> nil then
    Result.AddPair('instance', Instance.ToJSON);
end;

function TFlowInstanceManager.CreateFlow(const AParams: TCreateFlowParams): TFlowInstance;
var
  Event: TUniFlowEvent;
begin
  Result := TFlowInstance.CreateNew(AParams.FlowType, AParams.Source);
  Result.UserId := AParams.UserId;
  Result.SessionId := AParams.SessionId;
  Result.RootNodePath := AParams.RootNodePath;
  
  if AParams.Metadata <> nil then
  begin
    Result.Metadata.Free;
    // Result.Metadata := AParams.Metadata.Clone as TJSONObject;
    var Pairs := AParams.Metadata.Clone as TJSONObject;
    for var Pair in Pairs do
      Result.Metadata.AddPair(Pair.Clone as TJSONPair);
    Pairs.Free;
  end;
  
  // 发布创建事件
  Event := TUniFlowEvent.Create;
  try
    Event.FlowId := Result.Id;
    Event.FlowType := Result.FlowType;
    Event.Step := '_flow_created';
    Event.Source := AParams.Source;
    Event.Status := esSucceeded;
    Event.Payload.AddPair('flowType', FlowTypeToString(AParams.FlowType));
    Event.Payload.AddPair('source', AParams.Source);
    if not AParams.UserId.IsEmpty then
      Event.Payload.AddPair('userId', AParams.UserId);
    if not AParams.SessionId.IsEmpty then
      Event.Payload.AddPair('sessionId', AParams.SessionId);
      
    FStore.Append(Event);
  finally
    Event.Free;
  end;
  
  SaveInstance(Result);
end;

function TFlowInstanceManager.GetInstance(const AFlowId: string): TFlowInstance;
begin
  Result := LoadInstance(AFlowId);
end;

function TFlowInstanceManager.FlowExists(const AFlowId: string): Boolean;
begin
  Result := FStore.FlowExists(AFlowId);
end;

function TFlowInstanceManager.EmitEvent(AEvent: TUniFlowEvent): TEmitResult;
var
  Instance: TFlowInstance;
  AppendResult: TAppendResult;
  NewStatus: TUniFlowStatus;
begin
  if AEvent = nil then
    Exit(TEmitResult.Fail('Event is nil'));
    
  Instance := GetInstance(AEvent.FlowId);
  if Instance = nil then
    Exit(TEmitResult.Fail('Flow not found: ' + AEvent.FlowId));
    
  // 终态检�?
  if Instance.IsTerminal then
    Exit(TEmitResult.Fail('Flow is in terminal state: ' + FlowStatusToString(Instance.Status)));
    
  // 追加事件
  AppendResult := FStore.Append(AEvent);
  if not AppendResult.Success then
    Exit(TEmitResult.Fail(AppendResult.ErrorMessage));
    
  // 更新实例状�?
  AEvent.SequenceNumber := AppendResult.SequenceNumber;
  UpdateInstanceFromEvent(Instance, AEvent);
  NewStatus := Instance.Status;
  
  Result := TEmitResult.Ok(AppendResult.EventId, AppendResult.SequenceNumber, NewStatus);
  
  // 检查是否需要快�?
  if FSnapshotManager.ShouldCreateSnapshot(AEvent.FlowId, Instance.EventCount, Instance.Status) then
  begin
    var State := BuildCurrentState(AEvent.FlowId);
    try
      FSnapshotManager.CreateSnapshot(AEvent.FlowId, State, Instance.Status, AppendResult.SequenceNumber);
      Result.SnapshotCreated := True;
    finally
      State.Free;
    end;
  end;
end;

function TFlowInstanceManager.EmitStarted(const AFlowId, AStep, ASource: string): TEmitResult;
var
  Event: TUniFlowEvent;
begin
  Event := TUniFlowEvent.Started(AFlowId, AStep, ASource);
  try
    Result := EmitEvent(Event);
  finally
    Event.Free;
  end;
end;

function TFlowInstanceManager.EmitSucceeded(const AFlowId, AStep, ASource: string;
  APayload: TJSONObject): TEmitResult;
var
  Event: TUniFlowEvent;
begin
  Event := TUniFlowEvent.Succeeded(AFlowId, AStep, ASource, APayload);
  try
    Result := EmitEvent(Event);
  finally
    Event.Free;
  end;
end;

function TFlowInstanceManager.EmitFailed(const AFlowId, AStep, ASource, AErrorCode,
  AErrorMessage: string): TEmitResult;
var
  Event: TUniFlowEvent;
begin
  Event := TUniFlowEvent.Failed(AFlowId, AStep, ASource, AErrorCode, AErrorMessage);
  try
    Result := EmitEvent(Event);
  finally
    Event.Free;
  end;
end;

function TFlowInstanceManager.TransitionTo(const AFlowId: string;
  ANewStatus: TUniFlowStatus; const AReason: string): TTransitionResult;
var
  Instance: TFlowInstance;
  Event: TUniFlowEvent;
  OldStatus: TUniFlowStatus;
begin
  Instance := GetInstance(AFlowId);
  if Instance = nil then
    Exit(TTransitionResult.Fail('Flow not found: ' + AFlowId, ufsCreated));
    
  OldStatus := Instance.Status;
  
  // 检查迁移是否合�?
  if not Instance.CanTransitionTo(ANewStatus) then
    Exit(TTransitionResult.Fail(
      Format('Cannot transition from %s to %s', [
        FlowStatusToString(OldStatus),
        FlowStatusToString(ANewStatus)
      ]), OldStatus));
      
  // 发布状态变化事�?
  Event := TUniFlowEvent.Create;
  try
    Event.FlowId := AFlowId;
    Event.Step := '_flow_status';
    Event.Source := 'FlowInstanceManager';
    Event.Status := esSucceeded;
    Event.Payload.AddPair('oldStatus', FlowStatusToString(OldStatus));
    Event.Payload.AddPair('newStatus', FlowStatusToString(ANewStatus));
    if not AReason.IsEmpty then
      Event.Payload.AddPair('reason', AReason);
      
    var EmitRes := EmitEvent(Event);
    if not EmitRes.Success then
      Exit(TTransitionResult.Fail(EmitRes.ErrorMessage, OldStatus));
  finally
    Event.Free;
  end;
  
  // 直接更新状�?
  Instance.Status := ANewStatus;
  Instance.UpdatedAt := Now;
  if Instance.IsTerminal then
    Instance.CompletedAt := Now;
    
  Result := TTransitionResult.Ok(OldStatus, ANewStatus);
end;

function TFlowInstanceManager.StartFlow(const AFlowId: string): TTransitionResult;
begin
  Result := TransitionTo(AFlowId, ufsRunning, 'Flow started');
end;

function TFlowInstanceManager.CompleteFlow(const AFlowId: string): TTransitionResult;
begin
  Result := TransitionTo(AFlowId, ufsSucceeded, 'Flow completed');
end;

function TFlowInstanceManager.FailFlow(const AFlowId, AErrorCode,
  AErrorMessage: string): TTransitionResult;
var
  Instance: TFlowInstance;
  OldStatus: TUniFlowStatus;
  Event: TUniFlowEvent;
begin
  Instance := GetInstance(AFlowId);
  if Instance = nil then
    Exit(TTransitionResult.Fail('Flow not found: ' + AFlowId, ufsCreated));
    
  OldStatus := Instance.Status;
  
  if not Instance.CanTransitionTo(ufsFailed) then
    Exit(TTransitionResult.Fail('Cannot fail flow in current state', OldStatus));
    
  // 发布失败事件
  Event := TUniFlowEvent.Failed(AFlowId, '_flow_failed', 'FlowInstanceManager', AErrorCode, AErrorMessage);
  try
    Event.Payload.AddPair('oldStatus', FlowStatusToString(OldStatus));
    Event.Payload.AddPair('newStatus', 'Failed');
    EmitEvent(Event);
  finally
    Event.Free;
  end;
  
  Instance.Status := ufsFailed;
  Instance.UpdatedAt := Now;
  Instance.CompletedAt := Now;
  
  Result := TTransitionResult.Ok(OldStatus, ufsFailed);
end;

function TFlowInstanceManager.CancelFlow(const AFlowId: string;
  const AReason: string): TTransitionResult;
begin
  Result := TransitionTo(AFlowId, ufsCancelled, AReason);
end;

function TFlowInstanceManager.PauseFlow(const AFlowId: string): TTransitionResult;
begin
  Result := TransitionTo(AFlowId, ufsWaitingUser, 'Waiting for user input');
end;

function TFlowInstanceManager.ResumeFlow(const AFlowId: string): TTransitionResult;
begin
  Result := TransitionTo(AFlowId, ufsRunning, 'Resumed by user');
end;

function TFlowInstanceManager.GetAllFlows: TArray<TFlowInstance>;
var
  FlowIds: TArray<string>;
  ResultList: TList<TFlowInstance>;
  Instance: TFlowInstance;
begin
  FlowIds := FStore.GetAllFlowIds;
  ResultList := TList<TFlowInstance>.Create;
  try
    for var Id in FlowIds do
    begin
      Instance := GetInstance(Id);
      if Instance <> nil then
        ResultList.Add(Instance);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TFlowInstanceManager.GetActiveFlows: TArray<TFlowInstance>;
var
  AllFlows: TArray<TFlowInstance>;
  ResultList: TList<TFlowInstance>;
begin
  AllFlows := GetAllFlows;
  ResultList := TList<TFlowInstance>.Create;
  try
    for var Flow in AllFlows do
      if not Flow.IsTerminal then
        ResultList.Add(Flow);
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TFlowInstanceManager.GetFlowEvents(const AFlowId: string;
  AFromSeq: Int64): TArray<TUniFlowEvent>;
var
  Query: TEventQuery;
begin
  Query := TEventQuery.Create(AFlowId);
  Query.FromSequence := AFromSeq;
  Result := FStore.ReadEvents(Query);
end;

function TFlowInstanceManager.GetLatestSnapshot(const AFlowId: string): TUniFlowSnapshot;
begin
  Result := FStore.GetSnapshot(TSnapshotQuery.Latest(AFlowId));
end;

// ============================================================================
// TFlowBuilder
// ============================================================================

constructor TFlowBuilder.Create(AManager: TFlowInstanceManager);
begin
  inherited Create;
  FManager := AManager;
  FParams := Default(TCreateFlowParams);
  FParams.FlowType := uftCustom;
  FParams.Source := 'FlowBuilder';
end;

function TFlowBuilder.WithType(AType: TUniFlowType): TFlowBuilder;
begin
  FParams.FlowType := AType;
  Result := Self;
end;

function TFlowBuilder.WithSource(const ASource: string): TFlowBuilder;
begin
  FParams.Source := ASource;
  Result := Self;
end;

function TFlowBuilder.WithUser(const AUserId: string): TFlowBuilder;
begin
  FParams.UserId := AUserId;
  Result := Self;
end;

function TFlowBuilder.WithSession(const ASessionId: string): TFlowBuilder;
begin
  FParams.SessionId := ASessionId;
  Result := Self;
end;

function TFlowBuilder.WithNodePath(const APath: string): TFlowBuilder;
begin
  FParams.RootNodePath := APath;
  Result := Self;
end;

function TFlowBuilder.WithMetadata(AMetadata: TJSONObject): TFlowBuilder;
begin
  FParams.Metadata := AMetadata;
  Result := Self;
end;

function TFlowBuilder.WithMetadataValue(const AKey: string;
  const AValue: Variant): TFlowBuilder;
begin
  if FParams.Metadata = nil then
    FParams.Metadata := TJSONObject.Create;
  FParams.Metadata.AddPair(AKey, TJSONString.Create(VarToStr(AValue)));
  Result := Self;
end;

function TFlowBuilder.Build: TFlowInstance;
begin
  Result := FManager.CreateFlow(FParams);
end;

function TFlowBuilder.BuildAndStart: TFlowInstance;
begin
  Result := Build;
  FManager.StartFlow(Result.Id);
end;

// ============================================================================
// TFlowSession
// ============================================================================

constructor TFlowSession.Create(AManager: TFlowInstanceManager;
  const AFlowId, ASource: string);
begin
  inherited Create;
  FManager := AManager;
  FFlowId := AFlowId;
  FSource := ASource;
end;

function TFlowSession.BeginStep(const AStepName: string): TFlowSession;
begin
  FCurrentStep := AStepName;
  FManager.EmitStarted(FFlowId, AStepName, FSource);
  Result := Self;
end;

function TFlowSession.EndStep(APayload: TJSONObject): TFlowSession;
begin
  if not FCurrentStep.IsEmpty then
    FManager.EmitSucceeded(FFlowId, FCurrentStep, FSource, APayload);
  FCurrentStep := '';
  Result := Self;
end;

function TFlowSession.FailStep(const AErrorCode, AErrorMessage: string): TFlowSession;
begin
  if not FCurrentStep.IsEmpty then
    FManager.EmitFailed(FFlowId, FCurrentStep, FSource, AErrorCode, AErrorMessage);
  FCurrentStep := '';
  Result := Self;
end;

function TFlowSession.Emit(const AStep: string; AStatus: TEventStatus;
  APayload: TJSONObject): TFlowSession;
var
  Event: TUniFlowEvent;
begin
  Event := TUniFlowEvent.Create;
  try
    Event.FlowId := FFlowId;
    Event.Step := AStep;
    Event.Source := FSource;
    Event.Status := AStatus;
    if APayload <> nil then
    begin
      Event.Payload.Free;
      Event.Payload.AddPair('data', APayload.Clone as TJSONObject);
    end;
    FManager.EmitEvent(Event);
  finally
    Event.Free;
  end;
  Result := Self;
end;

function TFlowSession.Complete: TFlowSession;
begin
  FManager.CompleteFlow(FFlowId);
  Result := Self;
end;

function TFlowSession.Fail(const AErrorCode, AErrorMessage: string): TFlowSession;
begin
  FManager.FailFlow(FFlowId, AErrorCode, AErrorMessage);
  Result := Self;
end;

function TFlowSession.GetInstance: TFlowInstance;
begin
  Result := FManager.GetInstance(FFlowId);
end;

end.
