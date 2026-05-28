unit UniFlow.EventSourcing.Replay;
(*
  UniFlow Event Sourcing - Event Replay & Fork
  =============================================
  
  事件重放和分叉能力�?
  
  核心功能:
  1. Event Replay - 从事件序列重建状�?
     - 全量重放：从第一个事件开�?
     - 增量重放：从快照 + 后续事件
     - 指定版本重放：重建到特定事件序列�?
  
  2. Fork - 从历史版本分叉新流程
     - 从任意历史版本创建新 FlowInstance
     - 保留原始事件历史的引�?
     - 支持 what-if 场景分析
  
  设计原则:
  - 事件不可变：重放不会修改原始事件
  - 幂等性：多次重放同一序列得到相同结果
  - 可追溯：分叉保留与父流程的关�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.StrUtils, System.Math,
  UniFlow.EventSourcing.Types,
  UniFlow.EventSourcing.Store,
  UniFlow.EventSourcing.Instance;

type
  // ============================================================================
  // 状态聚合器接口
  // ============================================================================
  
  /// <summary>
  /// 状态聚合器接口 - 将事件聚合为状�?
  /// </summary>
  IStateAggregator = interface
    ['{B2C3D4E5-F6A7-5B6C-9D0E-1F2A3B4C5D6E}']
    
    /// <summary>应用单个事件到当前状�?/summary>
    procedure ApplyEvent(AEvent: TUniFlowEvent);
    
    /// <summary>获取当前聚合状�?/summary>
    function GetState: TJSONObject;
    
    /// <summary>从快照恢复状�?/summary>
    procedure LoadFromSnapshot(ASnapshot: TUniFlowSnapshot);
    
    /// <summary>重置状�?/summary>
    procedure Reset;
    
    /// <summary>克隆当前聚合�?/summary>
    function Clone: IStateAggregator;
  end;
  
  // ============================================================================
  // 默认状态聚合器
  // ============================================================================
  
  /// <summary>
  /// 默认状态聚合器 - 简单地收集事件信息
  /// </summary>
  TDefaultStateAggregator = class(TInterfacedObject, IStateAggregator)
  private
    FState: TJSONObject;
    FStepHistory: TJSONArray;
    FLastEvent: TUniFlowEvent;
    FEventCount: Int64;
  public
    constructor Create;
    destructor Destroy; override;
    
    // IStateAggregator
    procedure ApplyEvent(AEvent: TUniFlowEvent);
    function GetState: TJSONObject;
    procedure LoadFromSnapshot(ASnapshot: TUniFlowSnapshot);
    procedure Reset;
    function Clone: IStateAggregator;
    
    property EventCount: Int64 read FEventCount;
  end;
  
  /// <summary>
  /// 自定义状态聚合器 - 支持自定义聚合逻辑
  /// </summary>
  TEventApplyFunc = reference to procedure(AEvent: TUniFlowEvent; AState: TJSONObject);
  
  TCustomStateAggregator = class(TInterfacedObject, IStateAggregator)
  private
    FState: TJSONObject;
    FApplyFunc: TEventApplyFunc;
    FEventCount: Int64;
  public
    constructor Create(AApplyFunc: TEventApplyFunc);
    destructor Destroy; override;
    
    // IStateAggregator
    procedure ApplyEvent(AEvent: TUniFlowEvent);
    function GetState: TJSONObject;
    procedure LoadFromSnapshot(ASnapshot: TUniFlowSnapshot);
    procedure Reset;
    function Clone: IStateAggregator;
  end;
  
  // ============================================================================
  // 重放结果
  // ============================================================================
  
  /// <summary>重放结果</summary>
  TReplayResult = record
    Success: Boolean;
    FlowId: string;
    FinalSequence: Int64;
    EventsReplayed: Int64;
    FinalStatus: TUniFlowStatus;
    State: TJSONObject;  // 调用者负责释�?
    Duration: TDateTime;
    ErrorMessage: string;
    
    class function Ok(const AFlowId: string; AFinalSeq, ACount: Int64;
      AStatus: TUniFlowStatus; AState: TJSONObject): TReplayResult; static;
    class function Fail(const AMessage: string): TReplayResult; static;
  end;
  
  /// <summary>分叉结果</summary>
  TForkResult = record
    Success: Boolean;
    NewFlowId: string;
    ParentFlowId: string;
    ForkPoint: Int64;        // 分叉点的事件序列�?
    ErrorMessage: string;
    
    class function Ok(const ANewId, AParentId: string; AForkPoint: Int64): TForkResult; static;
    class function Fail(const AMessage: string): TForkResult; static;
  end;
  
  // ============================================================================
  // 事件重放�?
  // ============================================================================
  
  /// <summary>
  /// 事件重放�?- 从事件序列重建状�?
  /// </summary>
  TEventReplayer = class
  private
    FStore: IEventStore;
    FAggregator: IStateAggregator;
  public
    constructor Create(AStore: IEventStore; AAggregator: IStateAggregator = nil);
    
    /// <summary>重放所有事�?/summary>
    function ReplayAll(const AFlowId: string): TReplayResult;
    
    /// <summary>重放到指定序列号</summary>
    function ReplayTo(const AFlowId: string; ATargetSequence: Int64): TReplayResult;
    
    /// <summary>从快照开始重�?/summary>
    function ReplayFromSnapshot(const AFlowId: string;
      ASnapshot: TUniFlowSnapshot = nil): TReplayResult;
    
    /// <summary>重放指定范围的事�?/summary>
    function ReplayRange(const AFlowId: string; AFromSeq, AToSeq: Int64): TReplayResult;
    
    /// <summary>增量重放（从上次位置继续�?/summary>
    function ReplayIncremental(const AFlowId: string; AFromSeq: Int64): TReplayResult;
    
    /// <summary>设置状态聚合器</summary>
    procedure SetAggregator(AAggregator: IStateAggregator);
    
    property Store: IEventStore read FStore;
    property Aggregator: IStateAggregator read FAggregator;
  end;
  
  // ============================================================================
  // 流程分叉�?
  // ============================================================================
  
  /// <summary>分叉选项</summary>
  TForkOptions = record
    ForkPoint: Int64;         // 分叉点序列号�? 表示从最新状态分�?
    CopyMetadata: Boolean;    // 是否复制元数�?
    NewFlowType: TUniFlowType;// 新流程类型，uftCustom 表示继承父流程类�?
    Source: string;           // 分叉来源
    
    class function Default: TForkOptions; static;
    class function AtSequence(ASeq: Int64): TForkOptions; static;
  end;
  
  /// <summary>
  /// 流程分叉�?- 从历史版本创建新流程
  /// </summary>
  TFlowForker = class
  private
    FStore: IEventStore;
    FManager: TFlowInstanceManager;
    FReplayer: TEventReplayer;
  public
    constructor Create(AStore: IEventStore; AManager: TFlowInstanceManager);
    destructor Destroy; override;
    
    /// <summary>从当前状态分�?/summary>
    function Fork(const AParentFlowId: string; const AOptions: TForkOptions): TForkResult;
    
    /// <summary>从指定版本分�?/summary>
    function ForkAt(const AParentFlowId: string; ASequence: Int64): TForkResult;
    
    /// <summary>复制流程（完整克隆）</summary>
    function CloneFlow(const ASourceFlowId: string): TForkResult;
    
    /// <summary>创建 what-if 分支</summary>
    /// <remarks>
    /// 创建一个临时分支用于模拟，不会持久化到主存储�?
    /// 适用于预览操作结果�?
    /// </remarks>
    function CreateWhatIf(const AParentFlowId: string; AAtSequence: Int64): TFlowInstance;
    
    property Store: IEventStore read FStore;
    property Manager: TFlowInstanceManager read FManager;
  end;
  
  // ============================================================================
  // 历史浏览�?
  // ============================================================================
  
  /// <summary>历史快照</summary>
  THistoryPoint = record
    Sequence: Int64;
    Timestamp: TDateTime;
    Step: string;
    Status: TEventStatus;
    FlowStatus: TUniFlowStatus;
    Summary: string;
  end;
  
  /// <summary>
  /// 历史浏览�?- 浏览流程的完整历�?
  /// </summary>
  THistoryBrowser = class
  private
    FStore: IEventStore;
    FFlowId: string;
    FPoints: TArray<THistoryPoint>;
    FLoaded: Boolean;
    
    procedure LoadHistory;
  public
    constructor Create(AStore: IEventStore; const AFlowId: string);
    
    /// <summary>获取所有历史点</summary>
    function GetAllPoints: TArray<THistoryPoint>;
    
    /// <summary>获取指定序列号的历史�?/summary>
    function GetPointAt(ASequence: Int64): THistoryPoint;
    
    /// <summary>获取时间范围内的历史�?/summary>
    function GetPointsInRange(AFrom, ATo: TDateTime): TArray<THistoryPoint>;
    
    /// <summary>获取指定步骤的所有历史点</summary>
    function GetPointsByStep(const AStep: string): TArray<THistoryPoint>;
    
    /// <summary>获取历史点数�?/summary>
    function Count: Integer;
    
    /// <summary>重新加载历史</summary>
    procedure Refresh;
    
    property FlowId: string read FFlowId;
  end;
  
  // ============================================================================
  // 时间旅行调试�?
  // ============================================================================
  
  /// <summary>
  /// 时间旅行调试�?- 支持前进/后退浏览状态变�?
  /// </summary>
  TTimeTravelDebugger = class
  private
    FStore: IEventStore;
    FFlowId: string;
    FCurrentSequence: Int64;
    FMaxSequence: Int64;
    FReplayer: TEventReplayer;
    FAggregator: IStateAggregator;
    FCurrentState: TJSONObject;
  public
    constructor Create(AStore: IEventStore; const AFlowId: string);
    destructor Destroy; override;
    
    /// <summary>移动到第一个事�?/summary>
    function MoveFirst: TJSONObject;
    
    /// <summary>移动到最后一个事�?/summary>
    function MoveLast: TJSONObject;
    
    /// <summary>向前移动一�?/summary>
    function StepForward: TJSONObject;
    
    /// <summary>向后移动一�?/summary>
    function StepBackward: TJSONObject;
    
    /// <summary>跳转到指定序列号</summary>
    function JumpTo(ASequence: Int64): TJSONObject;
    
    /// <summary>获取当前事件</summary>
    function GetCurrentEvent: TUniFlowEvent;
    
    /// <summary>获取当前状�?/summary>
    function GetCurrentState: TJSONObject;
    
    /// <summary>检查是否可以前�?/summary>
    function CanStepForward: Boolean;
    
    /// <summary>检查是否可以后退</summary>
    function CanStepBackward: Boolean;
    
    property FlowId: string read FFlowId;
    property CurrentSequence: Int64 read FCurrentSequence;
    property MaxSequence: Int64 read FMaxSequence;
  end;
  
  // ============================================================================
  // 差异计算�?
  // ============================================================================
  
  /// <summary>状态差�?/summary>
  TStateDiff = record
    Path: string;
    OldValue: string;
    NewValue: string;
    ChangeType: string;  // 'Added', 'Removed', 'Modified'
  end;
  
  /// <summary>
  /// 差异计算�?- 计算两个状态之间的差异
  /// </summary>
  TDiffCalculator = class
  public
    /// <summary>计算两个状态的差异</summary>
    class function CalculateDiff(AOldState, ANewState: TJSONObject): TArray<TStateDiff>;
    
    /// <summary>计算两个版本之间的差�?/summary>
    class function CalculateVersionDiff(AStore: IEventStore; const AFlowId: string;
      AFromSeq, AToSeq: Int64): TArray<TStateDiff>;
  end;

implementation

// ============================================================================
// TDefaultStateAggregator
// ============================================================================

constructor TDefaultStateAggregator.Create;
begin
  inherited;
  FState := TJSONObject.Create;
  FStepHistory := TJSONArray.Create;
  FState.AddPair('stepHistory', FStepHistory);
  FEventCount := 0;
end;

destructor TDefaultStateAggregator.Destroy;
begin
  FState.Free;
  if FLastEvent <> nil then
    FLastEvent.Free;
  inherited;
end;

procedure TDefaultStateAggregator.ApplyEvent(AEvent: TUniFlowEvent);
var
  StepInfo: TJSONObject;
begin
  Inc(FEventCount);
  
  // 记录步骤历史
  StepInfo := TJSONObject.Create;
  StepInfo.AddPair('sequence', TJSONNumber.Create(AEvent.SequenceNumber));
  StepInfo.AddPair('step', AEvent.Step);
  StepInfo.AddPair('status', EventStatusToString(AEvent.Status));
  StepInfo.AddPair('timestamp', DateToISO8601(AEvent.Timestamp));
  FStepHistory.Add(StepInfo);
  
  // 更新最后事�?
  if FLastEvent <> nil then
    FLastEvent.Free;
  FLastEvent := AEvent.Clone;
  
  // 更新状态摘�?
  FState.RemovePair('lastStep');
  FState.RemovePair('lastStatus');
  FState.RemovePair('lastTimestamp');
  FState.RemovePair('eventCount');
  
  FState.AddPair('lastStep', AEvent.Step);
  FState.AddPair('lastStatus', EventStatusToString(AEvent.Status));
  FState.AddPair('lastTimestamp', DateToISO8601(AEvent.Timestamp));
  FState.AddPair('eventCount', TJSONNumber.Create(FEventCount));
  
  // 合并事件 payload 到状�?
  if AEvent.Payload.Count > 0 then
  begin
    for var Pair in AEvent.Payload do
    begin
      FState.RemovePair(Pair.JsonString.Value);
      FState.AddPair(Pair.Clone as TJSONPair);
    end;
  end;
end;

function TDefaultStateAggregator.GetState: TJSONObject;
begin
  Result := FState.Clone as TJSONObject;
end;

procedure TDefaultStateAggregator.LoadFromSnapshot(ASnapshot: TUniFlowSnapshot);
begin
  Reset;
  
  if (ASnapshot <> nil) and (ASnapshot.StateJson.Count > 0) then
  begin
    FState.Free;
    FState := ASnapshot.StateJson.Clone as TJSONObject;
    
    // 恢复步骤历史引用
    if not FState.TryGetValue<TJSONArray>('stepHistory', FStepHistory) then
    begin
      FStepHistory := TJSONArray.Create;
      FState.AddPair('stepHistory', FStepHistory);
    end;
    
    FEventCount := ASnapshot.EventSequence;
  end;
end;

procedure TDefaultStateAggregator.Reset;
begin
  FState.Free;
  FState := TJSONObject.Create;
  FStepHistory := TJSONArray.Create;
  FState.AddPair('stepHistory', FStepHistory);
  FEventCount := 0;
  
  if FLastEvent <> nil then
  begin
    FLastEvent.Free;
    FLastEvent := nil;
  end;
end;

function TDefaultStateAggregator.Clone: IStateAggregator;
var
  NewAgg: TDefaultStateAggregator;
begin
  NewAgg := TDefaultStateAggregator.Create;
  NewAgg.FState.Free;
  NewAgg.FState := FState.Clone as TJSONObject;
  NewAgg.FState.TryGetValue<TJSONArray>('stepHistory', NewAgg.FStepHistory);
  NewAgg.FEventCount := FEventCount;
  if FLastEvent <> nil then
    NewAgg.FLastEvent := FLastEvent.Clone;
  Result := NewAgg;
end;

// ============================================================================
// TCustomStateAggregator
// ============================================================================

constructor TCustomStateAggregator.Create(AApplyFunc: TEventApplyFunc);
begin
  inherited Create;
  FState := TJSONObject.Create;
  FApplyFunc := AApplyFunc;
  FEventCount := 0;
end;

destructor TCustomStateAggregator.Destroy;
begin
  FState.Free;
  inherited;
end;

procedure TCustomStateAggregator.ApplyEvent(AEvent: TUniFlowEvent);
begin
  Inc(FEventCount);
  if Assigned(FApplyFunc) then
    FApplyFunc(AEvent, FState);
end;

function TCustomStateAggregator.GetState: TJSONObject;
begin
  Result := FState.Clone as TJSONObject;
end;

procedure TCustomStateAggregator.LoadFromSnapshot(ASnapshot: TUniFlowSnapshot);
begin
  Reset;
  if (ASnapshot <> nil) and (ASnapshot.StateJson.Count > 0) then
  begin
    FState.Free;
    FState := ASnapshot.StateJson.Clone as TJSONObject;
    FEventCount := ASnapshot.EventSequence;
  end;
end;

procedure TCustomStateAggregator.Reset;
begin
  FState.Free;
  FState := TJSONObject.Create;
  FEventCount := 0;
end;

function TCustomStateAggregator.Clone: IStateAggregator;
var
  NewAgg: TCustomStateAggregator;
begin
  NewAgg := TCustomStateAggregator.Create(FApplyFunc);
  NewAgg.FState.Free;
  NewAgg.FState := FState.Clone as TJSONObject;
  NewAgg.FEventCount := FEventCount;
  Result := NewAgg;
end;

// ============================================================================
// TReplayResult
// ============================================================================

class function TReplayResult.Ok(const AFlowId: string; AFinalSeq, ACount: Int64;
  AStatus: TUniFlowStatus; AState: TJSONObject): TReplayResult;
begin
  Result.Success := True;
  Result.FlowId := AFlowId;
  Result.FinalSequence := AFinalSeq;
  Result.EventsReplayed := ACount;
  Result.FinalStatus := AStatus;
  Result.State := AState;
  Result.ErrorMessage := '';
end;

class function TReplayResult.Fail(const AMessage: string): TReplayResult;
begin
  Result.Success := False;
  Result.FlowId := '';
  Result.FinalSequence := 0;
  Result.EventsReplayed := 0;
  Result.FinalStatus := ufsCreated;
  Result.State := nil;
  Result.ErrorMessage := AMessage;
end;

// ============================================================================
// TForkResult
// ============================================================================

class function TForkResult.Ok(const ANewId, AParentId: string;
  AForkPoint: Int64): TForkResult;
begin
  Result.Success := True;
  Result.NewFlowId := ANewId;
  Result.ParentFlowId := AParentId;
  Result.ForkPoint := AForkPoint;
  Result.ErrorMessage := '';
end;

class function TForkResult.Fail(const AMessage: string): TForkResult;
begin
  Result.Success := False;
  Result.NewFlowId := '';
  Result.ParentFlowId := '';
  Result.ForkPoint := 0;
  Result.ErrorMessage := AMessage;
end;

// ============================================================================
// TEventReplayer
// ============================================================================

constructor TEventReplayer.Create(AStore: IEventStore; AAggregator: IStateAggregator);
begin
  inherited Create;
  FStore := AStore;
  if AAggregator <> nil then
    FAggregator := AAggregator
  else
    FAggregator := TDefaultStateAggregator.Create;
end;

function TEventReplayer.ReplayAll(const AFlowId: string): TReplayResult;
begin
  Result := ReplayTo(AFlowId, High(Int64));
end;

function TEventReplayer.ReplayTo(const AFlowId: string;
  ATargetSequence: Int64): TReplayResult;
var
  Query: TEventQuery;
  Events: TArray<TUniFlowEvent>;
  Event: TUniFlowEvent;
  StartTime: TDateTime;
  FinalSeq: Int64;
  Count: Int64;
  LastStatus: TUniFlowStatus;
begin
  StartTime := Now;
  FAggregator.Reset;
  FinalSeq := 0;
  Count := 0;
  LastStatus := ufsCreated;
  
  Query := TEventQuery.Create(AFlowId);
  Query.ToSequence := ATargetSequence;
  
  Events := FStore.ReadEvents(Query);
  try
    for Event in Events do
    begin
      FAggregator.ApplyEvent(Event);
      FinalSeq := Event.SequenceNumber;
      Inc(Count);
      
      // 从事件推断流程状�?
      if Event.Step = '_flow_status' then
      begin
        var StatusStr: string;
        if Event.Payload.TryGetValue<string>('newStatus', StatusStr) then
          LastStatus := StringToFlowStatus(StatusStr);
      end;
    end;
    
    Result := TReplayResult.Ok(AFlowId, FinalSeq, Count, LastStatus, FAggregator.GetState);
    Result.Duration := Now - StartTime;
  finally
    for Event in Events do
      Event.Free;
  end;
end;

function TEventReplayer.ReplayFromSnapshot(const AFlowId: string;
  ASnapshot: TUniFlowSnapshot): TReplayResult;
var
  Snapshot: TUniFlowSnapshot;
  Query: TEventQuery;
  Events: TArray<TUniFlowEvent>;
  Event: TUniFlowEvent;
  StartTime: TDateTime;
  FinalSeq: Int64;
  Count: Int64;
  LastStatus: TUniFlowStatus;
  OwnSnapshot: Boolean;
begin
  StartTime := Now;
  OwnSnapshot := False;
  
  // 获取快照
  if ASnapshot <> nil then
    Snapshot := ASnapshot
  else
  begin
    Snapshot := FStore.GetSnapshot(TSnapshotQuery.Latest(AFlowId));
    OwnSnapshot := True;
  end;
  
  try
    // 从快照恢�?
    if Snapshot <> nil then
    begin
      FAggregator.LoadFromSnapshot(Snapshot);
      FinalSeq := Snapshot.EventSequence;
      LastStatus := Snapshot.FlowStatus;
    end
    else
    begin
      FAggregator.Reset;
      FinalSeq := 0;
      LastStatus := ufsCreated;
    end;
    
    // 重放快照之后的事�?
    Query := TEventQuery.Create(AFlowId);
    Query.FromSequence := FinalSeq + 1;
    
    Events := FStore.ReadEvents(Query);
    Count := 0;
    try
      for Event in Events do
      begin
        FAggregator.ApplyEvent(Event);
        FinalSeq := Event.SequenceNumber;
        Inc(Count);
        
        if Event.Step = '_flow_status' then
        begin
          var StatusStr: string;
          if Event.Payload.TryGetValue<string>('newStatus', StatusStr) then
            LastStatus := StringToFlowStatus(StatusStr);
        end;
      end;
    finally
      for Event in Events do
        Event.Free;
    end;
    
    Result := TReplayResult.Ok(AFlowId, FinalSeq, Count, LastStatus, FAggregator.GetState);
    Result.Duration := Now - StartTime;
  finally
    if OwnSnapshot and (Snapshot <> nil) then
      Snapshot.Free;
  end;
end;

function TEventReplayer.ReplayRange(const AFlowId: string;
  AFromSeq, AToSeq: Int64): TReplayResult;
var
  Query: TEventQuery;
  Events: TArray<TUniFlowEvent>;
  Event: TUniFlowEvent;
  StartTime: TDateTime;
  FinalSeq: Int64;
  Count: Int64;
  LastStatus: TUniFlowStatus;
begin
  StartTime := Now;
  FAggregator.Reset;
  
  Query := TEventQuery.Create(AFlowId);
  Query.FromSequence := AFromSeq;
  Query.ToSequence := AToSeq;
  
  FinalSeq := 0;
  Count := 0;
  LastStatus := ufsCreated;
  
  Events := FStore.ReadEvents(Query);
  try
    for Event in Events do
    begin
      FAggregator.ApplyEvent(Event);
      FinalSeq := Event.SequenceNumber;
      Inc(Count);
      
      if Event.Step = '_flow_status' then
      begin
        var StatusStr: string;
        if Event.Payload.TryGetValue<string>('newStatus', StatusStr) then
          LastStatus := StringToFlowStatus(StatusStr);
      end;
    end;
    
    Result := TReplayResult.Ok(AFlowId, FinalSeq, Count, LastStatus, FAggregator.GetState);
    Result.Duration := Now - StartTime;
  finally
    for Event in Events do
      Event.Free;
  end;
end;

function TEventReplayer.ReplayIncremental(const AFlowId: string;
  AFromSeq: Int64): TReplayResult;
begin
  Result := ReplayRange(AFlowId, AFromSeq, High(Int64));
end;

procedure TEventReplayer.SetAggregator(AAggregator: IStateAggregator);
begin
  FAggregator := AAggregator;
end;

// ============================================================================
// TForkOptions
// ============================================================================

class function TForkOptions.Default: TForkOptions;
begin
  Result.ForkPoint := 0;
  Result.CopyMetadata := True;
  Result.NewFlowType := uftCustom;
  Result.Source := 'Fork';
end;

class function TForkOptions.AtSequence(ASeq: Int64): TForkOptions;
begin
  Result := Default;
  Result.ForkPoint := ASeq;
end;

// ============================================================================
// TFlowForker
// ============================================================================

constructor TFlowForker.Create(AStore: IEventStore; AManager: TFlowInstanceManager);
begin
  inherited Create;
  FStore := AStore;
  FManager := AManager;
  FReplayer := TEventReplayer.Create(AStore);
end;

destructor TFlowForker.Destroy;
begin
  FReplayer.Free;
  inherited;
end;

function TFlowForker.Fork(const AParentFlowId: string;
  const AOptions: TForkOptions): TForkResult;
var
  ParentInstance: TFlowInstance;
  ReplayResult: TReplayResult;
  NewFlow: TFlowInstance;
  Params: TCreateFlowParams;
  ForkEvent: TUniFlowEvent;
  ForkPoint: Int64;
begin
  // 获取父流�?
  ParentInstance := FManager.GetInstance(AParentFlowId);
  if ParentInstance = nil then
    Exit(TForkResult.Fail('Parent flow not found: ' + AParentFlowId));
    
  // 确定分叉�?
  if AOptions.ForkPoint > 0 then
    ForkPoint := AOptions.ForkPoint
  else
    ForkPoint := FStore.GetEventCount(AParentFlowId);
    
  // 重放到分叉点获取状�?
  if AOptions.ForkPoint > 0 then
    ReplayResult := FReplayer.ReplayTo(AParentFlowId, ForkPoint)
  else
    ReplayResult := FReplayer.ReplayFromSnapshot(AParentFlowId);
    
  if not ReplayResult.Success then
    Exit(TForkResult.Fail('Failed to replay parent flow: ' + ReplayResult.ErrorMessage));
    
  try
    // 创建新流�?
    Params := TCreateFlowParams.Create(
      TUniFlowType(IfThen(Ord(AOptions.NewFlowType) = Ord(uftCustom), Ord(ParentInstance.FlowType), Ord(AOptions.NewFlowType))),
      AOptions.Source
    );
    
    if AOptions.CopyMetadata then
      Params.Metadata := ParentInstance.Metadata.Clone as TJSONObject;
      
    NewFlow := FManager.CreateFlow(Params);
    NewFlow.ParentFlowId := AParentFlowId;
    
    // 发布分叉事件
    ForkEvent := TUniFlowEvent.Create;
    try
      ForkEvent.FlowId := NewFlow.Id;
      ForkEvent.Step := '_flow_forked';
      ForkEvent.Source := AOptions.Source;
      ForkEvent.Status := esSucceeded;
      ForkEvent.Payload.AddPair('parentFlowId', AParentFlowId);
      ForkEvent.Payload.AddPair('forkPoint', TJSONNumber.Create(ForkPoint));
      ForkEvent.Payload.AddPair('parentState', ReplayResult.State.Clone as TJSONObject);
      
      FManager.EmitEvent(ForkEvent);
    finally
      ForkEvent.Free;
    end;
    
    Result := TForkResult.Ok(NewFlow.Id, AParentFlowId, ForkPoint);
  finally
    ReplayResult.State.Free;
  end;
end;

function TFlowForker.ForkAt(const AParentFlowId: string;
  ASequence: Int64): TForkResult;
var
  Options: TForkOptions;
begin
  Options := TForkOptions.AtSequence(ASequence);
  Result := Fork(AParentFlowId, Options);
end;

function TFlowForker.CloneFlow(const ASourceFlowId: string): TForkResult;
var
  Options: TForkOptions;
begin
  Options := TForkOptions.Default;
  Options.Source := 'Clone';
  Result := Fork(ASourceFlowId, Options);
end;

function TFlowForker.CreateWhatIf(const AParentFlowId: string;
  AAtSequence: Int64): TFlowInstance;
var
  ReplayResult: TReplayResult;
begin
  // 重放到指定点
  if AAtSequence > 0 then
    ReplayResult := FReplayer.ReplayTo(AParentFlowId, AAtSequence)
  else
    ReplayResult := FReplayer.ReplayFromSnapshot(AParentFlowId);
    
  if not ReplayResult.Success then
    Exit(nil);
    
  try
    // 创建临时流程实例（不持久化）
    Result := TFlowInstance.Create;
    Result.Id := 'whatif-' + TFlowInstance.GenerateFlowId;
    Result.ParentFlowId := AParentFlowId;
    Result.Status := ReplayResult.FinalStatus;
    Result.EventCount := ReplayResult.FinalSequence;
    Result.Source := 'WhatIf';
  finally
    ReplayResult.State.Free;
  end;
end;

// ============================================================================
// THistoryBrowser
// ============================================================================

constructor THistoryBrowser.Create(AStore: IEventStore; const AFlowId: string);
begin
  inherited Create;
  FStore := AStore;
  FFlowId := AFlowId;
  FLoaded := False;
end;

procedure THistoryBrowser.LoadHistory;
var
  Query: TEventQuery;
  Events: TArray<TUniFlowEvent>;
  Event: TUniFlowEvent;
  Point: THistoryPoint;
  CurrentStatus: TUniFlowStatus;
begin
  if FLoaded then Exit;
  
  Query := TEventQuery.Create(FFlowId);
  Events := FStore.ReadEvents(Query);
  
  SetLength(FPoints, Length(Events));
  CurrentStatus := ufsCreated;
  
  try
    for var I := 0 to High(Events) do
    begin
      Event := Events[I];
      
      // 更新流程状�?
      if Event.Step = '_flow_status' then
      begin
        var StatusStr: string;
        if Event.Payload.TryGetValue<string>('newStatus', StatusStr) then
          CurrentStatus := StringToFlowStatus(StatusStr);
      end;
      
      Point.Sequence := Event.SequenceNumber;
      Point.Timestamp := Event.Timestamp;
      Point.Step := Event.Step;
      Point.Status := Event.Status;
      Point.FlowStatus := CurrentStatus;
      Point.Summary := Format('%s: %s', [Event.Step, EventStatusToString(Event.Status)]);
      
      FPoints[I] := Point;
    end;
  finally
    for Event in Events do
      Event.Free;
  end;
  
  FLoaded := True;
end;

function THistoryBrowser.GetAllPoints: TArray<THistoryPoint>;
begin
  LoadHistory;
  Result := Copy(FPoints);
end;

function THistoryBrowser.GetPointAt(ASequence: Int64): THistoryPoint;
begin
  LoadHistory;
  Result := Default(THistoryPoint);
  
  for var Point in FPoints do
    if Point.Sequence = ASequence then
      Exit(Point);
end;

function THistoryBrowser.GetPointsInRange(AFrom, ATo: TDateTime): TArray<THistoryPoint>;
var
  ResultList: TList<THistoryPoint>;
begin
  LoadHistory;
  ResultList := TList<THistoryPoint>.Create;
  try
    for var Point in FPoints do
      if (Point.Timestamp >= AFrom) and (Point.Timestamp <= ATo) then
        ResultList.Add(Point);
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function THistoryBrowser.GetPointsByStep(const AStep: string): TArray<THistoryPoint>;
var
  ResultList: TList<THistoryPoint>;
begin
  LoadHistory;
  ResultList := TList<THistoryPoint>.Create;
  try
    for var Point in FPoints do
      if Point.Step = AStep then
        ResultList.Add(Point);
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function THistoryBrowser.Count: Integer;
begin
  LoadHistory;
  Result := Length(FPoints);
end;

procedure THistoryBrowser.Refresh;
begin
  FLoaded := False;
  SetLength(FPoints, 0);
  LoadHistory;
end;

// ============================================================================
// TTimeTravelDebugger
// ============================================================================

constructor TTimeTravelDebugger.Create(AStore: IEventStore; const AFlowId: string);
begin
  inherited Create;
  FStore := AStore;
  FFlowId := AFlowId;
  FCurrentSequence := 0;
  FMaxSequence := FStore.GetEventCount(AFlowId);
  FAggregator := TDefaultStateAggregator.Create;
  FReplayer := TEventReplayer.Create(AStore, FAggregator);
end;

destructor TTimeTravelDebugger.Destroy;
begin
  if FCurrentState <> nil then
    FCurrentState.Free;
  FReplayer.Free;
  inherited;
end;

function TTimeTravelDebugger.MoveFirst: TJSONObject;
begin
  Result := JumpTo(1);
end;

function TTimeTravelDebugger.MoveLast: TJSONObject;
begin
  Result := JumpTo(FMaxSequence);
end;

function TTimeTravelDebugger.StepForward: TJSONObject;
begin
  if CanStepForward then
    Result := JumpTo(FCurrentSequence + 1)
  else
    Result := GetCurrentState;
end;

function TTimeTravelDebugger.StepBackward: TJSONObject;
begin
  if CanStepBackward then
    Result := JumpTo(FCurrentSequence - 1)
  else
    Result := GetCurrentState;
end;

function TTimeTravelDebugger.JumpTo(ASequence: Int64): TJSONObject;
var
  ReplayResult: TReplayResult;
begin
  if ASequence < 1 then ASequence := 1;
  if ASequence > FMaxSequence then ASequence := FMaxSequence;
  
  ReplayResult := FReplayer.ReplayTo(FFlowId, ASequence);
  
  if FCurrentState <> nil then
    FCurrentState.Free;
    
  FCurrentSequence := ReplayResult.FinalSequence;
  FCurrentState := ReplayResult.State;
  Result := FCurrentState;
end;

function TTimeTravelDebugger.GetCurrentEvent: TUniFlowEvent;
var
  Query: TEventQuery;
  Events: TArray<TUniFlowEvent>;
begin
  Result := nil;
  
  Query := TEventQuery.Create(FFlowId);
  Query.FromSequence := FCurrentSequence;
  Query.ToSequence := FCurrentSequence;
  Query.MaxCount := 1;
  
  Events := FStore.ReadEvents(Query);
  if Length(Events) > 0 then
    Result := Events[0];
end;

function TTimeTravelDebugger.GetCurrentState: TJSONObject;
begin
  if FCurrentState = nil then
    JumpTo(FCurrentSequence);
  Result := FCurrentState;
end;

function TTimeTravelDebugger.CanStepForward: Boolean;
begin
  Result := FCurrentSequence < FMaxSequence;
end;

function TTimeTravelDebugger.CanStepBackward: Boolean;
begin
  Result := FCurrentSequence > 1;
end;

// ============================================================================
// TDiffCalculator
// ============================================================================

class function TDiffCalculator.CalculateDiff(AOldState, ANewState: TJSONObject): TArray<TStateDiff>;
var
  ResultList: TList<TStateDiff>;
  Diff: TStateDiff;
  
  procedure ComparePair(const APath: string; AOld, ANew: TJSONValue);
  var
    OldObj, NewObj: TJSONObject;
    OldArr, NewArr: TJSONArray;
    Pair: TJSONPair;
  begin
    // 类型不同
    if (AOld = nil) and (ANew <> nil) then
    begin
      Diff.Path := APath;
      Diff.OldValue := '';
      Diff.NewValue := ANew.ToJSON;
      Diff.ChangeType := 'Added';
      ResultList.Add(Diff);
      Exit;
    end;
    
    if (AOld <> nil) and (ANew = nil) then
    begin
      Diff.Path := APath;
      Diff.OldValue := AOld.ToJSON;
      Diff.NewValue := '';
      Diff.ChangeType := 'Removed';
      ResultList.Add(Diff);
      Exit;
    end;
    
    if AOld.ClassType <> ANew.ClassType then
    begin
      Diff.Path := APath;
      Diff.OldValue := AOld.ToJSON;
      Diff.NewValue := ANew.ToJSON;
      Diff.ChangeType := 'Modified';
      ResultList.Add(Diff);
      Exit;
    end;
    
    // 对象比较
    if AOld is TJSONObject then
    begin
      OldObj := AOld as TJSONObject;
      NewObj := ANew as TJSONObject;
      
      // 检查旧对象中的�?
      for Pair in OldObj do
        ComparePair(APath + '.' + Pair.JsonString.Value,
          Pair.JsonValue, NewObj.GetValue(Pair.JsonString.Value));
          
      // 检查新对象中新增的�?
      for Pair in NewObj do
        if OldObj.GetValue(Pair.JsonString.Value) = nil then
          ComparePair(APath + '.' + Pair.JsonString.Value, nil, Pair.JsonValue);
    end
    // 数组比较
    else if AOld is TJSONArray then
    begin
      OldArr := AOld as TJSONArray;
      NewArr := ANew as TJSONArray;
      
      for var I := 0 to Max(OldArr.Count, NewArr.Count) - 1 do
      begin
        if I < OldArr.Count then
        begin
          if I < NewArr.Count then
            ComparePair(APath + '[' + IntToStr(I) + ']', OldArr.Items[I], NewArr.Items[I])
          else
            ComparePair(APath + '[' + IntToStr(I) + ']', OldArr.Items[I], nil);
        end
        else
          ComparePair(APath + '[' + IntToStr(I) + ']', nil, NewArr.Items[I]);
      end;
    end
    // 值比�?
    else if AOld.ToJSON <> ANew.ToJSON then
    begin
      Diff.Path := APath;
      Diff.OldValue := AOld.ToJSON;
      Diff.NewValue := ANew.ToJSON;
      Diff.ChangeType := 'Modified';
      ResultList.Add(Diff);
    end;
  end;
  
begin
  ResultList := TList<TStateDiff>.Create;
  try
    if (AOldState = nil) and (ANewState = nil) then
      Exit(nil);
      
    if AOldState = nil then
      AOldState := TJSONObject.Create;
    if ANewState = nil then
      ANewState := TJSONObject.Create;
      
    for var Pair in AOldState do
      ComparePair(Pair.JsonString.Value, Pair.JsonValue, ANewState.GetValue(Pair.JsonString.Value));
      
    for var Pair in ANewState do
      if AOldState.GetValue(Pair.JsonString.Value) = nil then
        ComparePair(Pair.JsonString.Value, nil, Pair.JsonValue);
        
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

class function TDiffCalculator.CalculateVersionDiff(AStore: IEventStore;
  const AFlowId: string; AFromSeq, AToSeq: Int64): TArray<TStateDiff>;
var
  Replayer: TEventReplayer;
  FromResult, ToResult: TReplayResult;
begin
  Replayer := TEventReplayer.Create(AStore);
  try
    FromResult := Replayer.ReplayTo(AFlowId, AFromSeq);
    ToResult := Replayer.ReplayTo(AFlowId, AToSeq);
    
    try
      Result := CalculateDiff(FromResult.State, ToResult.State);
    finally
      if FromResult.State <> nil then
        FromResult.State.Free;
      if ToResult.State <> nil then
        ToResult.State.Free;
    end;
  finally
    Replayer.Free;
  end;
end;

// Helper function
function IfThen(ACondition: Boolean; ATrue, AFalse: TUniFlowType): TUniFlowType;
begin
  if ACondition then
    Result := ATrue
  else
    Result := AFalse;
end;

end.
