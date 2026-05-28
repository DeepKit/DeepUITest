unit UniFlow.EventSourcing.Store;
(*
  UniFlow Event Sourcing - Event Store
  =====================================
  
  事件存储层，实现 Append-Only 语义�?
  
  核心职责:
  - 事件追加（Append�? 只允许追加，不允许修改或删除
  - 事件读取 - 支持�?FlowId、时间范围、序列号范围查询
  - 快照存储 - 支持快照的创建和检�?
  
  存储策略:
  - �?N 个事件（默认 10）生成一个快�?
  - 终态（Succeeded/Failed/Cancelled）时强制生成快照
  
  实现:
  - IEventStore: 抽象接口
  - TMemoryEventStore: 内存实现（测试用�?
  - TFileEventStore: 文件实现（开发用�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.IOUtils, System.SyncObjs, System.DateUtils,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  UniFlow.EventSourcing.Types;

type
  // ============================================================================
  // 查询参数
  // ============================================================================
  
  /// <summary>事件查询参数</summary>
  TEventQuery = record
    FlowId: string;           // 流程 ID（必须）
    FromSequence: Int64;      // 起始序列号（包含�?
    ToSequence: Int64;        // 结束序列号（包含），0 表示不限
    FromTimestamp: TDateTime; // 起始时间
    ToTimestamp: TDateTime;   // 结束时间
    Step: string;             // 过滤步骤�?
    Status: string;           // 过滤状态（Started/Succeeded/Failed�?
    MaxCount: Integer;        // 最大返回数量，0 表示不限
    
    class function Create(const AFlowId: string): TEventQuery; static;
  end;
  
  /// <summary>快照查询参数</summary>
  TSnapshotQuery = record
    FlowId: string;           // 流程 ID
    Version: Integer;         // 指定版本�?1 表示最�?
    BeforeSequence: Int64;    // 在此序列号之前的最近快�?
    
    class function Create(const AFlowId: string): TSnapshotQuery; static;
    class function Latest(const AFlowId: string): TSnapshotQuery; static;
  end;
  
  // ============================================================================
  // 事件追加结果
  // ============================================================================
  
  TAppendResult = record
    Success: Boolean;
    EventId: string;
    SequenceNumber: Int64;
    ErrorMessage: string;
    
    class function Ok(const AEventId: string; ASequence: Int64): TAppendResult; static;
    class function Fail(const AMessage: string): TAppendResult; static;
  end;
  
  // ============================================================================
  // 事件存储接口
  // ============================================================================
  
  /// <summary>
  /// 事件存储接口 - 支持 Append-Only 语义
  /// </summary>
  IEventStore = interface
    ['{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}']
    
    /// <summary>追加事件</summary>
    /// <remarks>
    /// 事件一旦追加，不可修改或删除�?
    /// 返回�?SequenceNumber �?Flow 内单调递增�?
    /// </remarks>
    function Append(AEvent: TUniFlowEvent): TAppendResult;
    
    /// <summary>批量追加事件</summary>
    function AppendBatch(AEvents: TArray<TUniFlowEvent>): TArray<TAppendResult>;
    
    /// <summary>读取事件</summary>
    function ReadEvents(const AQuery: TEventQuery): TArray<TUniFlowEvent>;
    
    /// <summary>获取流程的最后一个事�?/summary>
    function GetLastEvent(const AFlowId: string): TUniFlowEvent;
    
    /// <summary>获取流程的事件计�?/summary>
    function GetEventCount(const AFlowId: string): Int64;
    
    /// <summary>保存快照</summary>
    function SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;
    
    /// <summary>获取快照</summary>
    function GetSnapshot(const AQuery: TSnapshotQuery): TUniFlowSnapshot;
    
    /// <summary>获取所有流�?ID</summary>
    function GetAllFlowIds: TArray<string>;
    
    /// <summary>检查流程是否存�?/summary>
    function FlowExists(const AFlowId: string): Boolean;
  end;
  
  // ============================================================================
  // 内存事件存储
  // ============================================================================
  
  /// <summary>
  /// 内存事件存储 - 用于测试和开�?
  /// 线程安全
  /// </summary>
  TMemoryEventStore = class(TInterfacedObject, IEventStore)
  private
    FLock: TCriticalSection;
    FEvents: TObjectDictionary<string, TObjectList<TUniFlowEvent>>;
    FSnapshots: TObjectDictionary<string, TObjectList<TUniFlowSnapshot>>;
    FSequenceCounters: TDictionary<string, Int64>;
  public
    constructor Create;
    destructor Destroy; override;
    
    // IEventStore
    function Append(AEvent: TUniFlowEvent): TAppendResult;
    function AppendBatch(AEvents: TArray<TUniFlowEvent>): TArray<TAppendResult>;
    function ReadEvents(const AQuery: TEventQuery): TArray<TUniFlowEvent>;
    function GetLastEvent(const AFlowId: string): TUniFlowEvent;
    function GetEventCount(const AFlowId: string): Int64;
    function SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;
    function GetSnapshot(const AQuery: TSnapshotQuery): TUniFlowSnapshot;
    function GetAllFlowIds: TArray<string>;
    function FlowExists(const AFlowId: string): Boolean;
    
    /// <summary>清空所有数据（仅测试用�?/summary>
    procedure Clear;
  end;
  
  // ============================================================================
  // 文件事件存储
  // ============================================================================
  
  /// <summary>
  /// 文件事件存储 - 基于 JSON 文件持久�?
  /// 每个 Flow 一个目录，事件和快照分别存�?
  /// </summary>
  TFileEventStore = class(TInterfacedObject, IEventStore)
  private
    FBasePath: string;
    FLock: TCriticalSection;
    FCache: TObjectDictionary<string, TObjectList<TUniFlowEvent>>;
    FCacheEnabled: Boolean;
    
    function GetFlowPath(const AFlowId: string): string;
    function GetEventsFilePath(const AFlowId: string): string;
    function GetSnapshotsFilePath(const AFlowId: string): string;
    function LoadEvents(const AFlowId: string): TObjectList<TUniFlowEvent>;
    function LoadSnapshots(const AFlowId: string): TObjectList<TUniFlowSnapshot>;
    procedure SaveEvents(const AFlowId: string; AEvents: TObjectList<TUniFlowEvent>);
    procedure SaveSnapshots(const AFlowId: string; ASnapshots: TObjectList<TUniFlowSnapshot>);
    function GetNextSequence(const AFlowId: string; AEvents: TObjectList<TUniFlowEvent>): Int64;
  public
    constructor Create(const ABasePath: string; ACacheEnabled: Boolean = True);
    destructor Destroy; override;
    
    // IEventStore
    function Append(AEvent: TUniFlowEvent): TAppendResult;
    function AppendBatch(AEvents: TArray<TUniFlowEvent>): TArray<TAppendResult>;
    function ReadEvents(const AQuery: TEventQuery): TArray<TUniFlowEvent>;
    function GetLastEvent(const AFlowId: string): TUniFlowEvent;
    function GetEventCount(const AFlowId: string): Int64;
    function SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;
    function GetSnapshot(const AQuery: TSnapshotQuery): TUniFlowSnapshot;
    function GetAllFlowIds: TArray<string>;
    function FlowExists(const AFlowId: string): Boolean;
    
    /// <summary>清空缓存</summary>
    procedure ClearCache;
    
    property BasePath: string read FBasePath;
    property CacheEnabled: Boolean read FCacheEnabled write FCacheEnabled;
  end;
  
  // ============================================================================
  // 快照策略
  // ============================================================================
  
  /// <summary>快照策略配置</summary>
  TSnapshotPolicy = record
    EventInterval: Integer;       // �?N 个事件生成快�?
    ForceOnTerminal: Boolean;     // 终态时强制生成
    MaxSnapshotsPerFlow: Integer; // 每个 Flow 最多保留快照数
    
    class function Default: TSnapshotPolicy; static;
  end;
  
  /// <summary>
  /// 快照管理�?- 根据策略自动生成快照
  /// </summary>
  TSnapshotManager = class
  private
    FStore: IEventStore;
    FPolicy: TSnapshotPolicy;
  public
    constructor Create(AStore: IEventStore; APolicy: TSnapshotPolicy);
    
    /// <summary>检查是否需要生成快�?/summary>
    function ShouldCreateSnapshot(const AFlowId: string; AEventCount: Int64;
      AFlowStatus: TUniFlowStatus): Boolean;
    
    /// <summary>创建快照</summary>
    function CreateSnapshot(const AFlowId: string; AState: TJSONObject;
      AFlowStatus: TUniFlowStatus; AEventSequence: Int64): TUniFlowSnapshot;
    
    property Policy: TSnapshotPolicy read FPolicy write FPolicy;
  end;
  
  // ============================================================================
  // 事件�?
  // ============================================================================
  
  /// <summary>事件流迭代器</summary>
  TEventStream = class
  private
    FStore: IEventStore;
    FFlowId: string;
    FCurrentSequence: Int64;
    FBatchSize: Integer;
    FEvents: TArray<TUniFlowEvent>;
    FIndex: Integer;
    FEndOfStream: Boolean;
  public
    constructor Create(AStore: IEventStore; const AFlowId: string;
      AFromSequence: Int64 = 1; ABatchSize: Integer = 100);
    
    /// <summary>移动到下一个事�?/summary>
    function MoveNext: Boolean;
    
    /// <summary>当前事件</summary>
    function Current: TUniFlowEvent;
    
    /// <summary>重置到起始位�?/summary>
    procedure Reset(AFromSequence: Int64 = 1);
    
    property FlowId: string read FFlowId;
    property CurrentSequence: Int64 read FCurrentSequence;
    property EndOfStream: Boolean read FEndOfStream;
  end;

implementation

// ============================================================================
// TEventQuery
// ============================================================================

class function TEventQuery.Create(const AFlowId: string): TEventQuery;
begin
  Result := Default(TEventQuery);
  Result.FlowId := AFlowId;
  Result.FromSequence := 1;
  Result.ToSequence := 0;
  Result.MaxCount := 0;
end;

// ============================================================================
// TSnapshotQuery
// ============================================================================

class function TSnapshotQuery.Create(const AFlowId: string): TSnapshotQuery;
begin
  Result := Default(TSnapshotQuery);
  Result.FlowId := AFlowId;
  Result.Version := -1;
end;

class function TSnapshotQuery.Latest(const AFlowId: string): TSnapshotQuery;
begin
  Result := Create(AFlowId);
  Result.Version := -1;
end;

// ============================================================================
// TAppendResult
// ============================================================================

class function TAppendResult.Ok(const AEventId: string; ASequence: Int64): TAppendResult;
begin
  Result.Success := True;
  Result.EventId := AEventId;
  Result.SequenceNumber := ASequence;
  Result.ErrorMessage := '';
end;

class function TAppendResult.Fail(const AMessage: string): TAppendResult;
begin
  Result.Success := False;
  Result.EventId := '';
  Result.SequenceNumber := 0;
  Result.ErrorMessage := AMessage;
end;

// ============================================================================
// TMemoryEventStore
// ============================================================================

constructor TMemoryEventStore.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FEvents := TObjectDictionary<string, TObjectList<TUniFlowEvent>>.Create([doOwnsValues]);
  FSnapshots := TObjectDictionary<string, TObjectList<TUniFlowSnapshot>>.Create([doOwnsValues]);
  FSequenceCounters := TDictionary<string, Int64>.Create;
end;

destructor TMemoryEventStore.Destroy;
begin
  FSequenceCounters.Free;
  FSnapshots.Free;
  FEvents.Free;
  FLock.Free;
  inherited;
end;

function TMemoryEventStore.Append(AEvent: TUniFlowEvent): TAppendResult;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
  Seq: Int64;
  ClonedEvent: TUniFlowEvent;
begin
  if AEvent = nil then
    Exit(TAppendResult.Fail('Event is nil'));
    
  if not AEvent.Validate then
    Exit(TAppendResult.Fail('Event validation failed'));
    
  FLock.Enter;
  try
    // 获取或创建事件列�?
    if not FEvents.TryGetValue(AEvent.FlowId, FlowEvents) then
    begin
      FlowEvents := TObjectList<TUniFlowEvent>.Create(True);
      FEvents.Add(AEvent.FlowId, FlowEvents);
      FSequenceCounters.Add(AEvent.FlowId, 0);
    end;
    
    // 分配序列�?
    Seq := FSequenceCounters[AEvent.FlowId] + 1;
    FSequenceCounters[AEvent.FlowId] := Seq;
    
    // 克隆并存�?
    ClonedEvent := AEvent.Clone;
    ClonedEvent.SequenceNumber := Seq;
    FlowEvents.Add(ClonedEvent);
    
    Result := TAppendResult.Ok(ClonedEvent.Id, Seq);
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.AppendBatch(AEvents: TArray<TUniFlowEvent>): TArray<TAppendResult>;
var
  I: Integer;
begin
  SetLength(Result, Length(AEvents));
  for I := 0 to High(AEvents) do
    Result[I] := Append(AEvents[I]);
end;

function TMemoryEventStore.ReadEvents(const AQuery: TEventQuery): TArray<TUniFlowEvent>;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
  ResultList: TList<TUniFlowEvent>;
  Event: TUniFlowEvent;
begin
  Result := nil;
  
  FLock.Enter;
  try
    if not FEvents.TryGetValue(AQuery.FlowId, FlowEvents) then
      Exit;
      
    ResultList := TList<TUniFlowEvent>.Create;
    try
      for Event in FlowEvents do
      begin
        // 序列号过�?
        if Event.SequenceNumber < AQuery.FromSequence then
          Continue;
        if (AQuery.ToSequence > 0) and (Event.SequenceNumber > AQuery.ToSequence) then
          Continue;
          
        // 时间过滤
        if (AQuery.FromTimestamp > 0) and (Event.Timestamp < AQuery.FromTimestamp) then
          Continue;
        if (AQuery.ToTimestamp > 0) and (Event.Timestamp > AQuery.ToTimestamp) then
          Continue;
          
        // 步骤过滤
        if (AQuery.Step <> '') and (Event.Step <> AQuery.Step) then
          Continue;
          
        // 状态过�?
        if (AQuery.Status <> '') and (EventStatusToString(Event.Status) <> AQuery.Status) then
          Continue;
          
        ResultList.Add(Event.Clone);
        
        // 数量限制
        if (AQuery.MaxCount > 0) and (ResultList.Count >= AQuery.MaxCount) then
          Break;
      end;
      
      Result := ResultList.ToArray;
    finally
      ResultList.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.GetLastEvent(const AFlowId: string): TUniFlowEvent;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
begin
  Result := nil;
  
  FLock.Enter;
  try
    if FEvents.TryGetValue(AFlowId, FlowEvents) and (FlowEvents.Count > 0) then
      Result := FlowEvents.Last.Clone;
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.GetEventCount(const AFlowId: string): Int64;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
begin
  Result := 0;
  
  FLock.Enter;
  try
    if FEvents.TryGetValue(AFlowId, FlowEvents) then
      Result := FlowEvents.Count;
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;
var
  FlowSnapshots: TObjectList<TUniFlowSnapshot>;
  ClonedSnapshot: TUniFlowSnapshot;
begin
  Result := False;
  if ASnapshot = nil then Exit;
  
  FLock.Enter;
  try
    if not FSnapshots.TryGetValue(ASnapshot.FlowId, FlowSnapshots) then
    begin
      FlowSnapshots := TObjectList<TUniFlowSnapshot>.Create(True);
      FSnapshots.Add(ASnapshot.FlowId, FlowSnapshots);
    end;
    
    ClonedSnapshot := ASnapshot.Clone;
    ClonedSnapshot.Version := FlowSnapshots.Count;
    FlowSnapshots.Add(ClonedSnapshot);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.GetSnapshot(const AQuery: TSnapshotQuery): TUniFlowSnapshot;
var
  FlowSnapshots: TObjectList<TUniFlowSnapshot>;
  I: Integer;
begin
  Result := nil;
  
  FLock.Enter;
  try
    if not FSnapshots.TryGetValue(AQuery.FlowId, FlowSnapshots) then
      Exit;
    if FlowSnapshots.Count = 0 then
      Exit;
      
    if AQuery.Version >= 0 then
    begin
      // 指定版本
      if AQuery.Version < FlowSnapshots.Count then
        Result := FlowSnapshots[AQuery.Version].Clone;
    end
    else if AQuery.BeforeSequence > 0 then
    begin
      // 在指定序列号之前的最近快�?
      for I := FlowSnapshots.Count - 1 downto 0 do
      begin
        if FlowSnapshots[I].EventSequence <= AQuery.BeforeSequence then
        begin
          Result := FlowSnapshots[I].Clone;
          Break;
        end;
      end;
    end
    else
    begin
      // 最新快�?
      Result := FlowSnapshots.Last.Clone;
    end;
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.GetAllFlowIds: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FEvents.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TMemoryEventStore.FlowExists(const AFlowId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FEvents.ContainsKey(AFlowId);
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryEventStore.Clear;
begin
  FLock.Enter;
  try
    FEvents.Clear;
    FSnapshots.Clear;
    FSequenceCounters.Clear;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TFileEventStore
// ============================================================================

constructor TFileEventStore.Create(const ABasePath: string; ACacheEnabled: Boolean);
begin
  inherited Create;
  FBasePath := ABasePath;
  FCacheEnabled := ACacheEnabled;
  FLock := TCriticalSection.Create;
  FCache := TObjectDictionary<string, TObjectList<TUniFlowEvent>>.Create([doOwnsValues]);
  
  // 确保基础目录存在
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
end;

destructor TFileEventStore.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

function TFileEventStore.GetFlowPath(const AFlowId: string): string;
begin
  Result := TPath.Combine(FBasePath, AFlowId);
end;

function TFileEventStore.GetEventsFilePath(const AFlowId: string): string;
begin
  Result := TPath.Combine(GetFlowPath(AFlowId), 'events.json');
end;

function TFileEventStore.GetSnapshotsFilePath(const AFlowId: string): string;
begin
  Result := TPath.Combine(GetFlowPath(AFlowId), 'snapshots.json');
end;

function TFileEventStore.LoadEvents(const AFlowId: string): TObjectList<TUniFlowEvent>;
var
  FilePath: string;
  JsonStr: string;
  JsonArr: TJSONArray;
  I: Integer;
  Event: TUniFlowEvent;
begin
  // 检查缓�?
  if FCacheEnabled then
  begin
    if FCache.TryGetValue(AFlowId, Result) then
      Exit;
  end;
  
  Result := TObjectList<TUniFlowEvent>.Create(True);
  FilePath := GetEventsFilePath(AFlowId);
  
  if TFile.Exists(FilePath) then
  begin
    try
      JsonStr := TFile.ReadAllText(FilePath, TEncoding.UTF8);
      JsonArr := TJSONObject.ParseJSONValue(JsonStr) as TJSONArray;
      if JsonArr <> nil then
      try
        for I := 0 to JsonArr.Count - 1 do
        begin
          Event := TUniFlowEvent.Create;
          Event.LoadFromJSON(JsonArr.Items[I] as TJSONObject);
          Result.Add(Event);
        end;
      finally
        JsonArr.Free;
      end;
    except
      on E: Exception do
      begin
        // ENTROPY-011: 记录文件解析错误而非静默忽略
        {$IFDEF DEBUG}
        OutputDebugString(PChar(Format('[EventStore] Failed to load events for %s: %s', [AFlowId, E.Message])));
        {$ENDIF}
      end;
    end;
  end;
  
  // 添加到缓�?
  if FCacheEnabled then
  begin
    FCache.AddOrSetValue(AFlowId, Result);
  end;
end;

function TFileEventStore.LoadSnapshots(const AFlowId: string): TObjectList<TUniFlowSnapshot>;
var
  FilePath: string;
  JsonStr: string;
  JsonArr: TJSONArray;
  I: Integer;
  Snapshot: TUniFlowSnapshot;
begin
  Result := TObjectList<TUniFlowSnapshot>.Create(True);
  FilePath := GetSnapshotsFilePath(AFlowId);
  
  if TFile.Exists(FilePath) then
  begin
    try
      JsonStr := TFile.ReadAllText(FilePath, TEncoding.UTF8);
      JsonArr := TJSONObject.ParseJSONValue(JsonStr) as TJSONArray;
      if JsonArr <> nil then
      try
        for I := 0 to JsonArr.Count - 1 do
        begin
          Snapshot := TUniFlowSnapshot.Create;
          Snapshot.LoadFromJSON(JsonArr.Items[I] as TJSONObject);
          Result.Add(Snapshot);
        end;
      finally
        JsonArr.Free;
      end;
    except
      on E: Exception do
      begin
        // ENTROPY-011: 记录快照解析错误
        {$IFDEF DEBUG}
        OutputDebugString(PChar(Format('[EventStore] Failed to load snapshots for %s: %s', [AFlowId, E.Message])));
        {$ENDIF}
      end;
    end;
  end;
end;

procedure TFileEventStore.SaveEvents(const AFlowId: string; AEvents: TObjectList<TUniFlowEvent>);
var
  FlowPath, FilePath: string;
  JsonArr: TJSONArray;
  Event: TUniFlowEvent;
begin
  FlowPath := GetFlowPath(AFlowId);
  if not TDirectory.Exists(FlowPath) then
    TDirectory.CreateDirectory(FlowPath);
    
  FilePath := GetEventsFilePath(AFlowId);
  JsonArr := TJSONArray.Create;
  try
    for Event in AEvents do
      JsonArr.Add(Event.ToJSON);
    TFile.WriteAllText(FilePath, JsonArr.ToJSON, TEncoding.UTF8);
  finally
    JsonArr.Free;
  end;
end;

procedure TFileEventStore.SaveSnapshots(const AFlowId: string; ASnapshots: TObjectList<TUniFlowSnapshot>);
var
  FlowPath, FilePath: string;
  JsonArr: TJSONArray;
  Snapshot: TUniFlowSnapshot;
begin
  FlowPath := GetFlowPath(AFlowId);
  if not TDirectory.Exists(FlowPath) then
    TDirectory.CreateDirectory(FlowPath);
    
  FilePath := GetSnapshotsFilePath(AFlowId);
  JsonArr := TJSONArray.Create;
  try
    for Snapshot in ASnapshots do
      JsonArr.Add(Snapshot.ToJSON);
    TFile.WriteAllText(FilePath, JsonArr.ToJSON, TEncoding.UTF8);
  finally
    JsonArr.Free;
  end;
end;

function TFileEventStore.GetNextSequence(const AFlowId: string; 
  AEvents: TObjectList<TUniFlowEvent>): Int64;
begin
  if AEvents.Count > 0 then
    Result := AEvents.Last.SequenceNumber + 1
  else
    Result := 1;
end;

function TFileEventStore.Append(AEvent: TUniFlowEvent): TAppendResult;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
  Seq: Int64;
  ClonedEvent: TUniFlowEvent;
  OwnsList: Boolean;
begin
  if AEvent = nil then
    Exit(TAppendResult.Fail('Event is nil'));
    
  if not AEvent.Validate then
    Exit(TAppendResult.Fail('Event validation failed'));
    
  FLock.Enter;
  try
    // 加载事件
    OwnsList := not FCacheEnabled;
    FlowEvents := LoadEvents(AEvent.FlowId);
    try
      // 分配序列�?
      Seq := GetNextSequence(AEvent.FlowId, FlowEvents);
      
      // 克隆并添�?
      ClonedEvent := AEvent.Clone;
      ClonedEvent.SequenceNumber := Seq;
      FlowEvents.Add(ClonedEvent);
      
      // 保存
      SaveEvents(AEvent.FlowId, FlowEvents);
      
      Result := TAppendResult.Ok(ClonedEvent.Id, Seq);
    finally
      if OwnsList then
        FlowEvents.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.AppendBatch(AEvents: TArray<TUniFlowEvent>): TArray<TAppendResult>;
var
  I: Integer;
begin
  SetLength(Result, Length(AEvents));
  for I := 0 to High(AEvents) do
    Result[I] := Append(AEvents[I]);
end;

function TFileEventStore.ReadEvents(const AQuery: TEventQuery): TArray<TUniFlowEvent>;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
  ResultList: TList<TUniFlowEvent>;
  Event: TUniFlowEvent;
  OwnsList: Boolean;
begin
  Result := nil;
  
  FLock.Enter;
  try
    OwnsList := not FCacheEnabled;
    FlowEvents := LoadEvents(AQuery.FlowId);
    try
      ResultList := TList<TUniFlowEvent>.Create;
      try
        for Event in FlowEvents do
        begin
          // 序列号过�?
          if Event.SequenceNumber < AQuery.FromSequence then
            Continue;
          if (AQuery.ToSequence > 0) and (Event.SequenceNumber > AQuery.ToSequence) then
            Continue;
            
          // 时间过滤
          if (AQuery.FromTimestamp > 0) and (Event.Timestamp < AQuery.FromTimestamp) then
            Continue;
          if (AQuery.ToTimestamp > 0) and (Event.Timestamp > AQuery.ToTimestamp) then
            Continue;
            
          // 步骤过滤
          if (AQuery.Step <> '') and (Event.Step <> AQuery.Step) then
            Continue;
            
          // 状态过�?
          if (AQuery.Status <> '') and (EventStatusToString(Event.Status) <> AQuery.Status) then
            Continue;
            
          ResultList.Add(Event.Clone);
          
          // 数量限制
          if (AQuery.MaxCount > 0) and (ResultList.Count >= AQuery.MaxCount) then
            Break;
        end;
        
        Result := ResultList.ToArray;
      finally
        ResultList.Free;
      end;
    finally
      if OwnsList then
        FlowEvents.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.GetLastEvent(const AFlowId: string): TUniFlowEvent;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
  OwnsList: Boolean;
begin
  Result := nil;
  
  FLock.Enter;
  try
    OwnsList := not FCacheEnabled;
    FlowEvents := LoadEvents(AFlowId);
    try
      if FlowEvents.Count > 0 then
        Result := FlowEvents.Last.Clone;
    finally
      if OwnsList then
        FlowEvents.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.GetEventCount(const AFlowId: string): Int64;
var
  FlowEvents: TObjectList<TUniFlowEvent>;
  OwnsList: Boolean;
begin
  Result := 0;
  
  FLock.Enter;
  try
    OwnsList := not FCacheEnabled;
    FlowEvents := LoadEvents(AFlowId);
    try
      Result := FlowEvents.Count;
    finally
      if OwnsList then
        FlowEvents.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;
var
  FlowSnapshots: TObjectList<TUniFlowSnapshot>;
  ClonedSnapshot: TUniFlowSnapshot;
begin
  Result := False;
  if ASnapshot = nil then Exit;
  
  FLock.Enter;
  try
    FlowSnapshots := LoadSnapshots(ASnapshot.FlowId);
    try
      ClonedSnapshot := ASnapshot.Clone;
      ClonedSnapshot.Version := FlowSnapshots.Count;
      FlowSnapshots.Add(ClonedSnapshot);
      
      SaveSnapshots(ASnapshot.FlowId, FlowSnapshots);
      Result := True;
    finally
      FlowSnapshots.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.GetSnapshot(const AQuery: TSnapshotQuery): TUniFlowSnapshot;
var
  FlowSnapshots: TObjectList<TUniFlowSnapshot>;
  I: Integer;
begin
  Result := nil;
  
  FLock.Enter;
  try
    FlowSnapshots := LoadSnapshots(AQuery.FlowId);
    try
      if FlowSnapshots.Count = 0 then
        Exit;
        
      if AQuery.Version >= 0 then
      begin
        if AQuery.Version < FlowSnapshots.Count then
          Result := FlowSnapshots[AQuery.Version].Clone;
      end
      else if AQuery.BeforeSequence > 0 then
      begin
        for I := FlowSnapshots.Count - 1 downto 0 do
        begin
          if FlowSnapshots[I].EventSequence <= AQuery.BeforeSequence then
          begin
            Result := FlowSnapshots[I].Clone;
            Break;
          end;
        end;
      end
      else
      begin
        Result := FlowSnapshots.Last.Clone;
      end;
    finally
      FlowSnapshots.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.GetAllFlowIds: TArray<string>;
var
  Dirs: TArray<string>;
  I: Integer;
begin
  FLock.Enter;
  try
    if TDirectory.Exists(FBasePath) then
    begin
      Dirs := TDirectory.GetDirectories(FBasePath);
      SetLength(Result, Length(Dirs));
      for I := 0 to High(Dirs) do
        Result[I] := TPath.GetFileName(Dirs[I]);
    end
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TFileEventStore.FlowExists(const AFlowId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := TDirectory.Exists(GetFlowPath(AFlowId));
  finally
    FLock.Leave;
  end;
end;

procedure TFileEventStore.ClearCache;
begin
  FLock.Enter;
  try
    FCache.Clear;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TSnapshotPolicy
// ============================================================================

class function TSnapshotPolicy.Default: TSnapshotPolicy;
begin
  Result.EventInterval := 10;
  Result.ForceOnTerminal := True;
  Result.MaxSnapshotsPerFlow := 100;
end;

// ============================================================================
// TSnapshotManager
// ============================================================================

constructor TSnapshotManager.Create(AStore: IEventStore; APolicy: TSnapshotPolicy);
begin
  inherited Create;
  FStore := AStore;
  FPolicy := APolicy;
end;

function TSnapshotManager.ShouldCreateSnapshot(const AFlowId: string;
  AEventCount: Int64; AFlowStatus: TUniFlowStatus): Boolean;
begin
  // 终态强制生�?
  if FPolicy.ForceOnTerminal and (AFlowStatus in [ufsSucceeded, ufsFailed, ufsCancelled]) then
    Exit(True);
    
  // 按事件数量间�?
  if (FPolicy.EventInterval > 0) and (AEventCount mod FPolicy.EventInterval = 0) then
    Exit(True);
    
  Result := False;
end;

function TSnapshotManager.CreateSnapshot(const AFlowId: string; AState: TJSONObject;
  AFlowStatus: TUniFlowStatus; AEventSequence: Int64): TUniFlowSnapshot;
begin
  Result := TUniFlowSnapshot.Create;
  Result.FlowId := AFlowId;
  Result.FlowStatus := AFlowStatus;
  Result.EventSequence := AEventSequence;
  
  if AState <> nil then
  begin
    Result.StateJson.Free;
    Result.StateJson.AddPair('state', AState.Clone as TJSONObject);
  end;
  
  FStore.SaveSnapshot(Result);
end;

// ============================================================================
// TEventStream
// ============================================================================

constructor TEventStream.Create(AStore: IEventStore; const AFlowId: string;
  AFromSequence: Int64; ABatchSize: Integer);
begin
  inherited Create;
  FStore := AStore;
  FFlowId := AFlowId;
  FCurrentSequence := AFromSequence;
  FBatchSize := ABatchSize;
  FIndex := -1;
  FEndOfStream := False;
end;

function TEventStream.MoveNext: Boolean;
var
  Query: TEventQuery;
begin
  Inc(FIndex);
  
  // 检查当前批次是否还有数�?
  if FIndex < Length(FEvents) then
    Exit(True);
    
  // 检查是否已到流末尾
  if FEndOfStream then
    Exit(False);
    
  // 加载下一�?
  Query := TEventQuery.Create(FFlowId);
  Query.FromSequence := FCurrentSequence;
  Query.MaxCount := FBatchSize;
  
  // 释放旧事�?
  for var I := 0 to High(FEvents) do
    FEvents[I].Free;
    
  FEvents := FStore.ReadEvents(Query);
  FIndex := 0;
  
  if Length(FEvents) = 0 then
  begin
    FEndOfStream := True;
    Exit(False);
  end;
  
  // 更新当前序列�?
  FCurrentSequence := FEvents[High(FEvents)].SequenceNumber + 1;
  
  // 如果返回数量小于批次大小，说明到达末�?
  if Length(FEvents) < FBatchSize then
    FEndOfStream := True;
    
  Result := True;
end;

function TEventStream.Current: TUniFlowEvent;
begin
  if (FIndex >= 0) and (FIndex < Length(FEvents)) then
    Result := FEvents[FIndex]
  else
    Result := nil;
end;

procedure TEventStream.Reset(AFromSequence: Int64);
begin
  FCurrentSequence := AFromSequence;
  FIndex := -1;
  FEndOfStream := False;
  
  // 释放旧事�?
  for var I := 0 to High(FEvents) do
    FEvents[I].Free;
  SetLength(FEvents, 0);
end;

end.
