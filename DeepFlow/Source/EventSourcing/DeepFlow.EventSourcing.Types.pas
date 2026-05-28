unit UniFlow.EventSourcing.Types;
(*
  UniFlow Event Sourcing - Core Types
  ====================================
  
  基于设计文档 03.02.Design-uniFlow-CoreModelAndPrinciples 实现�?
  Event Sourcing 核心类型定义�?
  
  核心概念:
  - UniFlowEvent: 所有状态变化的唯一记录
  - UniFlowSnapshot: 事件聚合后的状态快�?
  - FlowInstance: 一次流程执行的实例
  
  设计原则:
  - 单一事实�? 所有状态变化都通过 Event 体现
  - 全程可追�? 任何状态都可从事件序列重建
  - 可回放与分叉: 支持从历史事件重放和分叉新流�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.SyncObjs;

type
  // ============================================================================
  // 基础类型
  // ============================================================================
  
  /// <summary>流程类型</summary>
  TUniFlowType = (
    uftBuild,       // 构建流（Loop A�? �?0 �?1
    uftMaintain,    // 维护流（Loop B�? �?N �?N+1
    uftNlConvert,   // 自然语言→结构化转换子流
    uftSceneChange, // 场景�?节点级结构变�?
    uftCodeChange,  // 代码级变�?
    uftCustom       // 自定义流程类�?
  );
  
  /// <summary>流程实例状�?/summary>
  TUniFlowStatus = (
    ufsCreated,     // 已创建，尚未开�?
    ufsRunning,     // 运行�?
    ufsWaitingUser, // 等待用户输入
    ufsSucceeded,   // 成功完成
    ufsFailed,      // 失败
    ufsCancelled    // 已取�?
  );
  
  /// <summary>事件状�?/summary>
  TEventStatus = (
    esStarted,      // 步骤开�?
    esSucceeded,    // 步骤成功
    esFailed        // 步骤失败
  );
  
  // ============================================================================
  // UniFlowEvent - 事件
  // ============================================================================
  
  /// <summary>
  /// UniFlow 事件 - 所有状态变化的唯一记录
  /// 约定: 所有状态变化都通过 UniFlowEvent 体现，禁止静默变�?
  /// </summary>
  TUniFlowEvent = class
  private
    FId: string;              // 事件 ID（全局唯一�?
    FFlowId: string;          // 所�?FlowInstance
    FFlowType: TUniFlowType;  // 流程类型
    FStep: string;            // 业务步骤�?
    FSource: string;          // 事件来源模块
    FStatus: TEventStatus;    // 事件状�?
    FTimestamp: TDateTime;    // 时间�?
    FPayload: TJSONObject;    // 业务数据
    FErrorCode: string;       // 错误码（Failed 时必须）
    FErrorMessage: string;    // 错误描述
    FSequenceNumber: Int64;   // 序列号（�?Flow 内递增�?
    FCorrelationId: string;   // 关联 ID（跨系统追踪�?
    FNodePath: string;        // 节点路径（定位相关）
    FMetadata: TJSONObject;   // 扩展元数�?
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>生成唯一事件 ID</summary>
    class function GenerateEventId: string;
    
    /// <summary>创建 Started 事件</summary>
    class function Started(const AFlowId, AStep, ASource: string): TUniFlowEvent;
    
    /// <summary>创建 Succeeded 事件</summary>
    class function Succeeded(const AFlowId, AStep, ASource: string;
      APayload: TJSONObject = nil): TUniFlowEvent;
    
    /// <summary>创建 Failed 事件</summary>
    class function Failed(const AFlowId, AStep, ASource, AErrorCode, AErrorMessage: string): TUniFlowEvent;
    
    /// <summary>验证事件完整�?/summary>
    function Validate: Boolean;
    
    /// <summary>序列化为 JSON</summary>
    function ToJSON: TJSONObject;
    
    /// <summary>�?JSON 反序列化</summary>
    procedure LoadFromJSON(AJson: TJSONObject);
    
    /// <summary>克隆事件</summary>
    function Clone: TUniFlowEvent;
    
    // 属�?
    property Id: string read FId write FId;
    property FlowId: string read FFlowId write FFlowId;
    property FlowType: TUniFlowType read FFlowType write FFlowType;
    property Step: string read FStep write FStep;
    property Source: string read FSource write FSource;
    property Status: TEventStatus read FStatus write FStatus;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property Payload: TJSONObject read FPayload;
    property ErrorCode: string read FErrorCode write FErrorCode;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property SequenceNumber: Int64 read FSequenceNumber write FSequenceNumber;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
    property NodePath: string read FNodePath write FNodePath;
    property Metadata: TJSONObject read FMetadata;
  end;
  
  // ============================================================================
  // UniFlowSnapshot - 快照
  // ============================================================================
  
  /// <summary>
  /// UniFlow 快照 - 事件聚合后的状�?
  /// 可由事件「重放」得到，也可在关键节点直接持久化
  /// </summary>
  TUniFlowSnapshot = class
  private
    FId: string;              // 快照 ID
    FFlowId: string;          // 所�?FlowInstance
    FVersion: Integer;        // 版本号（�?0 开始自增）
    FEventSequence: Int64;    // 对应的最后一个事件序列号
    FStateJson: TJSONObject;  // 聚合后的当前状�?
    FCreatedAt: TDateTime;    // 创建时间
    FFlowStatus: TUniFlowStatus; // 流程状�?
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>序列化为 JSON</summary>
    function ToJSON: TJSONObject;
    
    /// <summary>�?JSON 反序列化</summary>
    procedure LoadFromJSON(AJson: TJSONObject);
    
    /// <summary>克隆快照</summary>
    function Clone: TUniFlowSnapshot;
    
    property Id: string read FId write FId;
    property FlowId: string read FFlowId write FFlowId;
    property Version: Integer read FVersion write FVersion;
    property EventSequence: Int64 read FEventSequence write FEventSequence;
    property StateJson: TJSONObject read FStateJson;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property FlowStatus: TUniFlowStatus read FFlowStatus write FFlowStatus;
  end;
  
  // ============================================================================
  // FlowInstance - 流程实例
  // ============================================================================
  
  /// <summary>
  /// 流程实例 - 一次流程执�?
  /// FlowInstance 完全由事件（UniFlowEvent）和快照（UniFlowSnapshot）在存储中体�?
  /// </summary>
  TFlowInstance = class
  private
    FId: string;              // 流程实例 ID
    FFlowType: TUniFlowType;  // 流程类型
    FStatus: TUniFlowStatus;  // 当前状�?
    FCreatedAt: TDateTime;    // 创建时间
    FUpdatedAt: TDateTime;    // 最后更新时�?
    FCompletedAt: TDateTime;  // 完成时间
    FParentFlowId: string;    // 父流�?ID（用于子流程/分叉�?
    FRootNodePath: string;    // 根节点路�?
    FSource: string;          // 发起来源
    FUserId: string;          // 关联用户
    FSessionId: string;       // 关联会话
    FMetadata: TJSONObject;   // 元数�?
    FEventCount: Int64;       // 事件计数
    FLastEventId: string;     // 最后事�?ID
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>生成唯一流程 ID</summary>
    class function GenerateFlowId: string;
    
    /// <summary>创建新流程实�?/summary>
    class function CreateNew(AFlowType: TUniFlowType; const ASource: string): TFlowInstance;
    
    /// <summary>从父流程分叉</summary>
    class function Fork(const AParentFlowId: string; AFlowType: TUniFlowType): TFlowInstance;
    
    /// <summary>检查状态是否为终�?/summary>
    function IsTerminal: Boolean;
    
    /// <summary>检查状态迁移是否合�?/summary>
    function CanTransitionTo(ANewStatus: TUniFlowStatus): Boolean;
    
    /// <summary>序列化为 JSON</summary>
    function ToJSON: TJSONObject;
    
    /// <summary>�?JSON 反序列化</summary>
    procedure LoadFromJSON(AJson: TJSONObject);
    
    property Id: string read FId write FId;
    property FlowType: TUniFlowType read FFlowType write FFlowType;
    property Status: TUniFlowStatus read FStatus write FStatus;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    property CompletedAt: TDateTime read FCompletedAt write FCompletedAt;
    property ParentFlowId: string read FParentFlowId write FParentFlowId;
    property RootNodePath: string read FRootNodePath write FRootNodePath;
    property Source: string read FSource write FSource;
    property UserId: string read FUserId write FUserId;
    property SessionId: string read FSessionId write FSessionId;
    property Metadata: TJSONObject read FMetadata;
    property EventCount: Int64 read FEventCount write FEventCount;
    property LastEventId: string read FLastEventId write FLastEventId;
  end;
  
  // ============================================================================
  // UniFlowNode - 节点
  // ============================================================================
  
  /// <summary>
  /// UniFlow 节点 - 用于在不同层次上定位
  /// </summary>
  TUniFlowNode = class
  private
    FNodeId: string;          // 节点 ID
    FNodeType: string;        // 节点类型
    FParentId: string;        // 父节�?ID
    FAttributes: TJSONObject; // 节点属�?
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>生成节点路径</summary>
    function GetPath: string;
    
    /// <summary>解析节点路径</summary>
    class function ParsePath(const APath: string): TArray<TPair<string, string>>;
    
    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);
    
    property NodeId: string read FNodeId write FNodeId;
    property NodeType: string read FNodeType write FNodeType;
    property ParentId: string read FParentId write FParentId;
    property Attributes: TJSONObject read FAttributes;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
function FlowTypeToString(AType: TUniFlowType): string;
function StringToFlowType(const AStr: string): TUniFlowType;
function FlowStatusToString(AStatus: TUniFlowStatus): string;
function StringToFlowStatus(const AStr: string): TUniFlowStatus;
function EventStatusToString(AStatus: TEventStatus): string;
function StringToEventStatus(const AStr: string): TEventStatus;

implementation

uses
  System.StrUtils;

// ============================================================================
// 辅助函数实现
// ============================================================================

function FlowTypeToString(AType: TUniFlowType): string;
const
  Names: array[TUniFlowType] of string = (
    'Build', 'Maintain', 'NlConvert', 'SceneChange', 'CodeChange', 'Custom'
  );
begin
  Result := Names[AType];
end;

function StringToFlowType(const AStr: string): TUniFlowType;
begin
  if SameText(AStr, 'Build') then Result := uftBuild
  else if SameText(AStr, 'Maintain') then Result := uftMaintain
  else if SameText(AStr, 'NlConvert') then Result := uftNlConvert
  else if SameText(AStr, 'SceneChange') then Result := uftSceneChange
  else if SameText(AStr, 'CodeChange') then Result := uftCodeChange
  else Result := uftCustom;
end;

function FlowStatusToString(AStatus: TUniFlowStatus): string;
const
  Names: array[TUniFlowStatus] of string = (
    'Created', 'Running', 'WaitingUser', 'Succeeded', 'Failed', 'Cancelled'
  );
begin
  Result := Names[AStatus];
end;

function StringToFlowStatus(const AStr: string): TUniFlowStatus;
begin
  if SameText(AStr, 'Created') then Result := ufsCreated
  else if SameText(AStr, 'Running') then Result := ufsRunning
  else if SameText(AStr, 'WaitingUser') then Result := ufsWaitingUser
  else if SameText(AStr, 'Succeeded') then Result := ufsSucceeded
  else if SameText(AStr, 'Failed') then Result := ufsFailed
  else if SameText(AStr, 'Cancelled') then Result := ufsCancelled
  else Result := ufsCreated;
end;

function EventStatusToString(AStatus: TEventStatus): string;
const
  Names: array[TEventStatus] of string = ('Started', 'Succeeded', 'Failed');
begin
  Result := Names[AStatus];
end;

function StringToEventStatus(const AStr: string): TEventStatus;
begin
  if SameText(AStr, 'Started') then Result := esStarted
  else if SameText(AStr, 'Succeeded') then Result := esSucceeded
  else if SameText(AStr, 'Failed') then Result := esFailed
  else Result := esStarted;
end;

// ============================================================================
// TUniFlowEvent
// ============================================================================

constructor TUniFlowEvent.Create;
begin
  inherited;
  FId := GenerateEventId;
  FTimestamp := Now;
  FPayload := TJSONObject.Create;
  FMetadata := TJSONObject.Create;
  FSequenceNumber := 0;
end;

destructor TUniFlowEvent.Destroy;
begin
  FPayload.Free;
  FMetadata.Free;
  inherited;
end;

class function TUniFlowEvent.GenerateEventId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'evt-' + Copy(GUIDToString(GUID), 2, 36);
end;

class function TUniFlowEvent.Started(const AFlowId, AStep, ASource: string): TUniFlowEvent;
begin
  Result := TUniFlowEvent.Create;
  Result.FFlowId := AFlowId;
  Result.FStep := AStep;
  Result.FSource := ASource;
  Result.FStatus := esStarted;
end;

class function TUniFlowEvent.Succeeded(const AFlowId, AStep, ASource: string;
  APayload: TJSONObject): TUniFlowEvent;
begin
  Result := TUniFlowEvent.Create;
  Result.FFlowId := AFlowId;
  Result.FStep := AStep;
  Result.FSource := ASource;
  Result.FStatus := esSucceeded;
  if APayload <> nil then
  begin
    Result.FPayload.Free;
    Result.FPayload := APayload.Clone as TJSONObject;
  end;
end;

class function TUniFlowEvent.Failed(const AFlowId, AStep, ASource, AErrorCode, AErrorMessage: string): TUniFlowEvent;
begin
  Result := TUniFlowEvent.Create;
  Result.FFlowId := AFlowId;
  Result.FStep := AStep;
  Result.FSource := ASource;
  Result.FStatus := esFailed;
  Result.FErrorCode := AErrorCode;
  Result.FErrorMessage := AErrorMessage;
end;

function TUniFlowEvent.Validate: Boolean;
begin
  // 基础字段必须存在
  if FId.IsEmpty or FFlowId.IsEmpty or FStep.IsEmpty or FSource.IsEmpty then
    Exit(False);
    
  // Failed 事件必须�?ErrorCode
  if (FStatus = esFailed) and FErrorCode.IsEmpty then
    Exit(False);
    
  Result := True;
end;

function TUniFlowEvent.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('flowId', FFlowId);
  Result.AddPair('flowType', FlowTypeToString(FFlowType));
  Result.AddPair('step', FStep);
  Result.AddPair('source', FSource);
  Result.AddPair('status', EventStatusToString(FStatus));
  Result.AddPair('timestamp', DateToISO8601(FTimestamp));
  Result.AddPair('sequenceNumber', TJSONNumber.Create(FSequenceNumber));
  
  if FPayload.Count > 0 then
    Result.AddPair('payload', FPayload.Clone as TJSONObject);
  if not FErrorCode.IsEmpty then
    Result.AddPair('errorCode', FErrorCode);
  if not FErrorMessage.IsEmpty then
    Result.AddPair('errorMessage', FErrorMessage);
  if not FCorrelationId.IsEmpty then
    Result.AddPair('correlationId', FCorrelationId);
  if not FNodePath.IsEmpty then
    Result.AddPair('nodePath', FNodePath);
  if FMetadata.Count > 0 then
    Result.AddPair('metadata', FMetadata.Clone as TJSONObject);
end;

procedure TUniFlowEvent.LoadFromJSON(AJson: TJSONObject);
var
  Obj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  AJson.TryGetValue<string>('id', FId);
  AJson.TryGetValue<string>('flowId', FFlowId);
  
  var TypeStr: string;
  if AJson.TryGetValue<string>('flowType', TypeStr) then
    FFlowType := StringToFlowType(TypeStr);
    
  AJson.TryGetValue<string>('step', FStep);
  AJson.TryGetValue<string>('source', FSource);
  
  var StatusStr: string;
  if AJson.TryGetValue<string>('status', StatusStr) then
    FStatus := StringToEventStatus(StatusStr);
    
  var TimestampStr: string;
  if AJson.TryGetValue<string>('timestamp', TimestampStr) then
    FTimestamp := ISO8601ToDate(TimestampStr);
    
  AJson.TryGetValue<Int64>('sequenceNumber', FSequenceNumber);
  AJson.TryGetValue<string>('errorCode', FErrorCode);
  AJson.TryGetValue<string>('errorMessage', FErrorMessage);
  AJson.TryGetValue<string>('correlationId', FCorrelationId);
  AJson.TryGetValue<string>('nodePath', FNodePath);
  
  if AJson.TryGetValue<TJSONObject>('payload', Obj) then
  begin
    FPayload.Free;
    FPayload := Obj.Clone as TJSONObject;
  end;
  
  if AJson.TryGetValue<TJSONObject>('metadata', Obj) then
  begin
    FMetadata.Free;
    FMetadata := Obj.Clone as TJSONObject;
  end;
end;

function TUniFlowEvent.Clone: TUniFlowEvent;
begin
  Result := TUniFlowEvent.Create;
  Result.FId := FId;
  Result.FFlowId := FFlowId;
  Result.FFlowType := FFlowType;
  Result.FStep := FStep;
  Result.FSource := FSource;
  Result.FStatus := FStatus;
  Result.FTimestamp := FTimestamp;
  Result.FErrorCode := FErrorCode;
  Result.FErrorMessage := FErrorMessage;
  Result.FSequenceNumber := FSequenceNumber;
  Result.FCorrelationId := FCorrelationId;
  Result.FNodePath := FNodePath;
  Result.FPayload.Free;
  Result.FPayload := FPayload.Clone as TJSONObject;
  Result.FMetadata.Free;
  Result.FMetadata := FMetadata.Clone as TJSONObject;
end;

// ============================================================================
// TUniFlowSnapshot
// ============================================================================

constructor TUniFlowSnapshot.Create;
var
  GUID: TGUID;
begin
  inherited;
  CreateGUID(GUID);
  FId := 'snap-' + Copy(GUIDToString(GUID), 2, 36);
  FCreatedAt := Now;
  FStateJson := TJSONObject.Create;
  FVersion := 0;
end;

destructor TUniFlowSnapshot.Destroy;
begin
  FStateJson.Free;
  inherited;
end;

function TUniFlowSnapshot.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('flowId', FFlowId);
  Result.AddPair('version', TJSONNumber.Create(FVersion));
  Result.AddPair('eventSequence', TJSONNumber.Create(FEventSequence));
  Result.AddPair('flowStatus', FlowStatusToString(FFlowStatus));
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
  if FStateJson.Count > 0 then
    Result.AddPair('stateJson', FStateJson.Clone as TJSONObject);
end;

procedure TUniFlowSnapshot.LoadFromJSON(AJson: TJSONObject);
var
  Obj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  AJson.TryGetValue<string>('id', FId);
  AJson.TryGetValue<string>('flowId', FFlowId);
  AJson.TryGetValue<Integer>('version', FVersion);
  AJson.TryGetValue<Int64>('eventSequence', FEventSequence);
  
  var StatusStr: string;
  if AJson.TryGetValue<string>('flowStatus', StatusStr) then
    FFlowStatus := StringToFlowStatus(StatusStr);
    
  var TimestampStr: string;
  if AJson.TryGetValue<string>('createdAt', TimestampStr) then
    FCreatedAt := ISO8601ToDate(TimestampStr);
    
  if AJson.TryGetValue<TJSONObject>('stateJson', Obj) then
  begin
    FStateJson.Free;
    FStateJson := Obj.Clone as TJSONObject;
  end;
end;

function TUniFlowSnapshot.Clone: TUniFlowSnapshot;
begin
  Result := TUniFlowSnapshot.Create;
  Result.FId := FId;
  Result.FFlowId := FFlowId;
  Result.FVersion := FVersion;
  Result.FEventSequence := FEventSequence;
  Result.FFlowStatus := FFlowStatus;
  Result.FCreatedAt := FCreatedAt;
  Result.FStateJson.Free;
  Result.FStateJson := FStateJson.Clone as TJSONObject;
end;

// ============================================================================
// TFlowInstance
// ============================================================================

constructor TFlowInstance.Create;
begin
  inherited;
  FId := GenerateFlowId;
  FCreatedAt := Now;
  FUpdatedAt := FCreatedAt;
  FStatus := ufsCreated;
  FMetadata := TJSONObject.Create;
  FEventCount := 0;
end;

destructor TFlowInstance.Destroy;
begin
  FMetadata.Free;
  inherited;
end;

class function TFlowInstance.GenerateFlowId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'flow-' + Copy(GUIDToString(GUID), 2, 36);
end;

class function TFlowInstance.CreateNew(AFlowType: TUniFlowType; const ASource: string): TFlowInstance;
begin
  Result := TFlowInstance.Create;
  Result.FFlowType := AFlowType;
  Result.FSource := ASource;
end;

class function TFlowInstance.Fork(const AParentFlowId: string; AFlowType: TUniFlowType): TFlowInstance;
begin
  Result := TFlowInstance.Create;
  Result.FFlowType := AFlowType;
  Result.FParentFlowId := AParentFlowId;
  Result.FSource := 'Fork';
end;

function TFlowInstance.IsTerminal: Boolean;
begin
  Result := FStatus in [ufsSucceeded, ufsFailed, ufsCancelled];
end;

function TFlowInstance.CanTransitionTo(ANewStatus: TUniFlowStatus): Boolean;
begin
  // 终态不能再迁移
  if IsTerminal then
    Exit(False);
    
  // 状态迁移规�?
  case FStatus of
    ufsCreated:
      Result := ANewStatus in [ufsRunning, ufsCancelled];
    ufsRunning:
      Result := ANewStatus in [ufsWaitingUser, ufsSucceeded, ufsFailed, ufsCancelled];
    ufsWaitingUser:
      Result := ANewStatus in [ufsRunning, ufsCancelled];
    else
      Result := False;
  end;
end;

function TFlowInstance.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('flowType', FlowTypeToString(FFlowType));
  Result.AddPair('status', FlowStatusToString(FStatus));
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
  Result.AddPair('updatedAt', DateToISO8601(FUpdatedAt));
  Result.AddPair('eventCount', TJSONNumber.Create(FEventCount));
  
  if FCompletedAt > 0 then
    Result.AddPair('completedAt', DateToISO8601(FCompletedAt));
  if not FParentFlowId.IsEmpty then
    Result.AddPair('parentFlowId', FParentFlowId);
  if not FRootNodePath.IsEmpty then
    Result.AddPair('rootNodePath', FRootNodePath);
  if not FSource.IsEmpty then
    Result.AddPair('source', FSource);
  if not FUserId.IsEmpty then
    Result.AddPair('userId', FUserId);
  if not FSessionId.IsEmpty then
    Result.AddPair('sessionId', FSessionId);
  if not FLastEventId.IsEmpty then
    Result.AddPair('lastEventId', FLastEventId);
  if FMetadata.Count > 0 then
    Result.AddPair('metadata', FMetadata.Clone as TJSONObject);
end;

procedure TFlowInstance.LoadFromJSON(AJson: TJSONObject);
var
  Obj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  AJson.TryGetValue<string>('id', FId);
  
  var TypeStr: string;
  if AJson.TryGetValue<string>('flowType', TypeStr) then
    FFlowType := StringToFlowType(TypeStr);
    
  var StatusStr: string;
  if AJson.TryGetValue<string>('status', StatusStr) then
    FStatus := StringToFlowStatus(StatusStr);
    
  var TimestampStr: string;
  if AJson.TryGetValue<string>('createdAt', TimestampStr) then
    FCreatedAt := ISO8601ToDate(TimestampStr);
  if AJson.TryGetValue<string>('updatedAt', TimestampStr) then
    FUpdatedAt := ISO8601ToDate(TimestampStr);
  if AJson.TryGetValue<string>('completedAt', TimestampStr) then
    FCompletedAt := ISO8601ToDate(TimestampStr);
    
  AJson.TryGetValue<Int64>('eventCount', FEventCount);
  AJson.TryGetValue<string>('parentFlowId', FParentFlowId);
  AJson.TryGetValue<string>('rootNodePath', FRootNodePath);
  AJson.TryGetValue<string>('source', FSource);
  AJson.TryGetValue<string>('userId', FUserId);
  AJson.TryGetValue<string>('sessionId', FSessionId);
  AJson.TryGetValue<string>('lastEventId', FLastEventId);
  
  if AJson.TryGetValue<TJSONObject>('metadata', Obj) then
  begin
    FMetadata.Free;
    FMetadata := Obj.Clone as TJSONObject;
  end;
end;

// ============================================================================
// TUniFlowNode
// ============================================================================

constructor TUniFlowNode.Create;
var
  GUID: TGUID;
begin
  inherited;
  CreateGUID(GUID);
  FNodeId := 'node-' + Copy(GUIDToString(GUID), 2, 36);
  FCreatedAt := Now;
  FUpdatedAt := FCreatedAt;
  FAttributes := TJSONObject.Create;
end;

destructor TUniFlowNode.Destroy;
begin
  FAttributes.Free;
  inherited;
end;

function TUniFlowNode.GetPath: string;
begin
  Result := FNodeType + ':' + FNodeId;
end;

class function TUniFlowNode.ParsePath(const APath: string): TArray<TPair<string, string>>;
var
  Parts: TArray<string>;
  TypeId: TArray<string>;
  I: Integer;
begin
  Parts := APath.Split(['/']);
  SetLength(Result, Length(Parts));
  
  for I := 0 to High(Parts) do
  begin
    TypeId := Parts[I].Split([':']);
    if Length(TypeId) >= 2 then
    begin
      Result[I].Key := TypeId[0];
      Result[I].Value := TypeId[1];
    end;
  end;
end;

function TUniFlowNode.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('nodeId', FNodeId);
  Result.AddPair('nodeType', FNodeType);
  if not FParentId.IsEmpty then
    Result.AddPair('parentId', FParentId);
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
  Result.AddPair('updatedAt', DateToISO8601(FUpdatedAt));
  if FAttributes.Count > 0 then
    Result.AddPair('attributes', FAttributes.Clone as TJSONObject);
end;

procedure TUniFlowNode.LoadFromJSON(AJson: TJSONObject);
var
  Obj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  AJson.TryGetValue<string>('nodeId', FNodeId);
  AJson.TryGetValue<string>('nodeType', FNodeType);
  AJson.TryGetValue<string>('parentId', FParentId);
  
  var TimestampStr: string;
  if AJson.TryGetValue<string>('createdAt', TimestampStr) then
    FCreatedAt := ISO8601ToDate(TimestampStr);
  if AJson.TryGetValue<string>('updatedAt', TimestampStr) then
    FUpdatedAt := ISO8601ToDate(TimestampStr);
    
  if AJson.TryGetValue<TJSONObject>('attributes', Obj) then
  begin
    FAttributes.Free;
    FAttributes := Obj.Clone as TJSONObject;
  end;
end;

end.
