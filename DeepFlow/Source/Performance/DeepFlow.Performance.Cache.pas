unit UniFlow.Performance.Cache;
(*
  UniFlow Performance - Cache System
  ===================================
  高性能缓存系统，提供：
  - 泛型 LRU 缓存
  - 工作流定义缓�?
  - Schema 缓存
  - 统一缓存管理�?

  Author: UniFlow Team
  Date: 2025-12-05
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.SyncObjs, System.Hash, System.DateUtils;

type
  // ============================================================================
  // LRU 缓存节点
  // ============================================================================

  /// <summary>双向链表节点</summary>
  TLRUNode<K, V> = class
  public
    Key: K;
    Value: V;
    Prev: TLRUNode<K, V>;
    Next: TLRUNode<K, V>;
    CreatedAt: TDateTime;
    LastAccess: TDateTime;
    AccessCount: Integer;
    SizeBytes: Integer;

    constructor Create(const AKey: K; const AValue: V; ASizeBytes: Integer = 0);
  end;

  // ============================================================================
  // LRU 缓存
  // ============================================================================

  /// <summary>缓存统计信息</summary>
  TCacheStats = record
    Items: Integer;
    Capacity: Integer;
    Hits: Int64;
    Misses: Int64;
    Evictions: Int64;
    SizeBytes: Int64;
    MaxSizeBytes: Int64;

    function HitRate: Double;
    function ToJSON: TJSONObject;
    procedure Reset;
  end;

  /// <summary>缓存配置</summary>
  TCacheConfig = record
    Capacity: Integer;        // 最大项�?
    MaxSizeBytes: Int64;      // 最大字节数 (0=不限�?
    TTLSeconds: Integer;      // 生存时间 (0=不过�?
    CleanupIntervalSec: Integer; // 清理间隔

    class function Default: TCacheConfig; static;
    class function Small: TCacheConfig; static;
    class function Large: TCacheConfig; static;
  end;

  /// <summary>泛型 LRU 缓存</summary>
  TLRUCache<K, V> = class
  private
    FMap: TDictionary<K, TLRUNode<K, V>>;
    FHead: TLRUNode<K, V>;  // 最近使�?
    FTail: TLRUNode<K, V>;  // 最久未�?
    FConfig: TCacheConfig;
    FLock: TCriticalSection;
    FStats: TCacheStats;
    FCurrentSizeBytes: Int64;
    FOnEvict: TProc<K, V>;

    procedure MoveToHead(ANode: TLRUNode<K, V>);
    procedure RemoveNode(ANode: TLRUNode<K, V>);
    procedure AddToHead(ANode: TLRUNode<K, V>);
    function RemoveTail: TLRUNode<K, V>;
    procedure Evict;
    procedure CleanExpired;
    function IsExpired(ANode: TLRUNode<K, V>): Boolean;
  public
    constructor Create(AConfig: TCacheConfig); overload;
    constructor Create(ACapacity: Integer = 1000); overload;
    destructor Destroy; override;

    /// <summary>获取�?/summary>
    function Get(const AKey: K; out AValue: V): Boolean;

    /// <summary>获取值（返回默认值）</summary>
    function GetOrDefault(const AKey: K; const ADefault: V): V;

    /// <summary>设置�?/summary>
    procedure Put(const AKey: K; const AValue: V; ASizeBytes: Integer = 0);

    /// <summary>移除�?/summary>
    function Remove(const AKey: K): Boolean;

    /// <summary>检查键是否存在</summary>
    function Contains(const AKey: K): Boolean;

    /// <summary>清空缓存</summary>
    procedure Clear;

    /// <summary>获取统计信息</summary>
    function GetStats: TCacheStats;

    /// <summary>获取所有键</summary>
    function Keys: TArray<K>;

    /// <summary>当前项数</summary>
    function Count: Integer;

    /// <summary>淘汰回调</summary>
    property OnEvict: TProc<K, V> read FOnEvict write FOnEvict;
    property Config: TCacheConfig read FConfig;
  end;

  // ============================================================================
  // 字符串键 LRU 缓存
  // ============================================================================

  /// <summary>字符串键值缓�?/summary>
  TStringCache = class(TLRUCache<string, string>)
  public
    /// <summary>获取或计�?/summary>
    function GetOrCompute(const AKey: string; ACompute: TFunc<string>): string;
  end;

  // ============================================================================
  // 工作流定义缓�?
  // ============================================================================

  /// <summary>缓存的工作流定义�?/summary>
  TCachedWorkflowDef = class
  private
    FJson: TJSONObject;
    FFilePath: string;
    FFileHash: string;
    FFileModTime: TDateTime;
    FLoadedAt: TDateTime;
    FAccessCount: Integer;
  public
    constructor Create(AJson: TJSONObject; const AFilePath, AHash: string; AModTime: TDateTime);
    destructor Destroy; override;

    procedure Touch;

    property Json: TJSONObject read FJson;
    property FilePath: string read FFilePath;
    property FileHash: string read FFileHash;
    property FileModTime: TDateTime read FFileModTime;
    property LoadedAt: TDateTime read FLoadedAt;
    property AccessCount: Integer read FAccessCount;
  end;

  /// <summary>工作流定义缓�?/summary>
  TWorkflowDefinitionCache = class
  private
    FCache: TLRUCache<string, TCachedWorkflowDef>;
    FLock: TCriticalSection;
    FAutoReload: Boolean;

    function ComputeFileHash(const AFilePath: string): string;
    function GetFileModTime(const AFilePath: string): TDateTime;
  public
    constructor Create(ACapacity: Integer = 100);
    destructor Destroy; override;

    /// <summary>从文件加载（带缓存）</summary>
    function LoadFromFile(const AFilePath: string): TJSONObject;

    /// <summary>从字符串加载（带缓存�?/summary>
    function LoadFromString(const AContent: string): TJSONObject;

    /// <summary>使指定文件失�?/summary>
    procedure Invalidate(const AFilePath: string);

    /// <summary>使所有缓存失�?/summary>
    procedure InvalidateAll;

    /// <summary>预加载多个文�?/summary>
    procedure Preload(const AFilePaths: TArray<string>);

    /// <summary>获取统计信息</summary>
    function GetStats: TJSONObject;

    /// <summary>是否自动重新加载变更的文�?/summary>
    property AutoReload: Boolean read FAutoReload write FAutoReload;
  end;

  // ============================================================================
  // Schema 缓存
  // ============================================================================

  /// <summary>缓存�?Schema</summary>
  TCachedSchema = class
  private
    FSchema: TJSONObject;
    FCompiledData: TObject;  // 编译后的数据（可选）
    FVersion: string;
    FLoadedAt: TDateTime;
  public
    constructor Create(ASchema: TJSONObject; const AVersion: string);
    destructor Destroy; override;

    property Schema: TJSONObject read FSchema;
    property CompiledData: TObject read FCompiledData write FCompiledData;
    property Version: string read FVersion;
    property LoadedAt: TDateTime read FLoadedAt;
  end;

  /// <summary>Schema 缓存</summary>
  TSchemaCache = class
  private
    FCache: TLRUCache<string, TCachedSchema>;
    FLock: TCriticalSection;
    FSchemaDir: string;
  public
    constructor Create(const ASchemaDir: string; ACapacity: Integer = 50);
    destructor Destroy; override;

    /// <summary>获取 Schema</summary>
    function Get(const ASchemaId: string): TJSONObject;

    /// <summary>加载 Schema 文件</summary>
    function LoadSchema(const ASchemaId: string): TJSONObject;

    /// <summary>注册 Schema</summary>
    procedure Register(const ASchemaId: string; ASchema: TJSONObject; const AVersion: string = '1.0');

    /// <summary>�?Schema 失效</summary>
    procedure Invalidate(const ASchemaId: string);

    /// <summary>获取统计信息</summary>
    function GetStats: TJSONObject;

    property SchemaDir: string read FSchemaDir write FSchemaDir;
  end;

  // ============================================================================
  // 多级缓存
  // ============================================================================

  /// <summary>缓存级别</summary>
  TCacheLevel = (
    clL1,   // 一级缓存（最快，最小）
    clL2,   // 二级缓存
    clL3    // 三级缓存（最大，可持久化�?
  );

  /// <summary>多级字符串缓�?/summary>
  TMultiLevelCache = class
  private
    FL1: TLRUCache<string, string>;
    FL2: TLRUCache<string, string>;
    FL3: TLRUCache<string, string>;
    FLock: TCriticalSection;
    FPromoteOnHit: Boolean;
  public
    constructor Create(AL1Size: Integer = 100; AL2Size: Integer = 1000; AL3Size: Integer = 10000);
    destructor Destroy; override;

    /// <summary>获取�?/summary>
    function Get(const AKey: string; out AValue: string): Boolean;

    /// <summary>设置�?/summary>
    procedure Put(const AKey: string; const AValue: string; ALevel: TCacheLevel = clL2);

    /// <summary>移除�?/summary>
    procedure Remove(const AKey: string);

    /// <summary>清空所有级�?/summary>
    procedure Clear;

    /// <summary>获取统计信息</summary>
    function GetStats: TJSONObject;

    /// <summary>命中时是否提升级�?/summary>
    property PromoteOnHit: Boolean read FPromoteOnHit write FPromoteOnHit;
  end;

  // ============================================================================
  // 缓存管理�?
  // ============================================================================

  /// <summary>缓存管理�?/summary>
  TCacheManager = class
  private
    FCaches: TDictionary<string, TObject>;
    FLock: TCriticalSection;
    FWorkflowCache: TWorkflowDefinitionCache;
    FSchemaCache: TSchemaCache;
    FStringCache: TStringCache;
    class var FInstance: TCacheManager;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>注册缓存</summary>
    procedure RegisterCache(const AName: string; ACache: TObject);

    /// <summary>获取缓存</summary>
    function GetCache<T: class>(const AName: string): T;

    /// <summary>工作流定义缓�?/summary>
    property WorkflowCache: TWorkflowDefinitionCache read FWorkflowCache;

    /// <summary>Schema 缓存</summary>
    property SchemaCache: TSchemaCache read FSchemaCache;

    /// <summary>字符串缓�?/summary>
    property StringCache: TStringCache read FStringCache;

    /// <summary>清空所有缓�?/summary>
    procedure ClearAll;

    /// <summary>获取所有缓存统�?/summary>
    function GetAllStats: TJSONObject;

    /// <summary>预热缓存</summary>
    procedure Warmup(const AWorkflowDir, ASchemaDir: string);

    /// <summary>全局实例</summary>
    class function GetInstance: TCacheManager;
    class procedure ReleaseInstance;
  end;

/// <summary>全局缓存管理�?/summary>
function CacheManager: TCacheManager;

implementation

uses
  System.IOUtils, System.Types;

// ============================================================================
// TLRUNode<K, V>
// ============================================================================

constructor TLRUNode<K, V>.Create(const AKey: K; const AValue: V; ASizeBytes: Integer);
begin
  inherited Create;
  Key := AKey;
  Value := AValue;
  Prev := nil;
  Next := nil;
  CreatedAt := Now;
  LastAccess := Now;
  AccessCount := 0;
  SizeBytes := ASizeBytes;
end;

// ============================================================================
// TCacheStats
// ============================================================================

function TCacheStats.HitRate: Double;
var
  Total: Int64;
begin
  Total := Hits + Misses;
  if Total > 0 then
    Result := Hits / Total
  else
    Result := 0;
end;

function TCacheStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('items', TJSONNumber.Create(Items));
  Result.AddPair('capacity', TJSONNumber.Create(Capacity));
  Result.AddPair('hits', TJSONNumber.Create(Hits));
  Result.AddPair('misses', TJSONNumber.Create(Misses));
  Result.AddPair('evictions', TJSONNumber.Create(Evictions));
  Result.AddPair('hitRate', TJSONNumber.Create(HitRate));
  Result.AddPair('sizeBytes', TJSONNumber.Create(SizeBytes));
  Result.AddPair('maxSizeBytes', TJSONNumber.Create(MaxSizeBytes));
end;

procedure TCacheStats.Reset;
begin
  Items := 0;
  Capacity := 0;
  Hits := 0;
  Misses := 0;
  Evictions := 0;
  SizeBytes := 0;
  MaxSizeBytes := 0;
end;

// ============================================================================
// TCacheConfig
// ============================================================================

class function TCacheConfig.Default: TCacheConfig;
begin
  Result.Capacity := 1000;
  Result.MaxSizeBytes := 50 * 1024 * 1024; // 50 MB
  Result.TTLSeconds := 300; // 5 minutes
  Result.CleanupIntervalSec := 60;
end;

class function TCacheConfig.Small: TCacheConfig;
begin
  Result.Capacity := 100;
  Result.MaxSizeBytes := 5 * 1024 * 1024; // 5 MB
  Result.TTLSeconds := 60;
  Result.CleanupIntervalSec := 30;
end;

class function TCacheConfig.Large: TCacheConfig;
begin
  Result.Capacity := 10000;
  Result.MaxSizeBytes := 500 * 1024 * 1024; // 500 MB
  Result.TTLSeconds := 3600; // 1 hour
  Result.CleanupIntervalSec := 300;
end;

// ============================================================================
// TLRUCache<K, V>
// ============================================================================

constructor TLRUCache<K, V>.Create(AConfig: TCacheConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FMap := TDictionary<K, TLRUNode<K, V>>.Create;
  FLock := TCriticalSection.Create;
  FHead := nil;
  FTail := nil;
  FCurrentSizeBytes := 0;
  FStats.Reset;
  FStats.Capacity := FConfig.Capacity;
  FStats.MaxSizeBytes := FConfig.MaxSizeBytes;
end;

constructor TLRUCache<K, V>.Create(ACapacity: Integer);
var
  Config: TCacheConfig;
begin
  Config := TCacheConfig.Default;
  Config.Capacity := ACapacity;
  Create(Config);
end;

destructor TLRUCache<K, V>.Destroy;
begin
  Clear;
  FMap.Free;
  FLock.Free;
  inherited;
end;

procedure TLRUCache<K, V>.AddToHead(ANode: TLRUNode<K, V>);
begin
  ANode.Prev := nil;
  ANode.Next := FHead;
  if FHead <> nil then
    FHead.Prev := ANode;
  FHead := ANode;
  if FTail = nil then
    FTail := ANode;
end;

procedure TLRUCache<K, V>.RemoveNode(ANode: TLRUNode<K, V>);
begin
  if ANode.Prev <> nil then
    ANode.Prev.Next := ANode.Next
  else
    FHead := ANode.Next;

  if ANode.Next <> nil then
    ANode.Next.Prev := ANode.Prev
  else
    FTail := ANode.Prev;
end;

procedure TLRUCache<K, V>.MoveToHead(ANode: TLRUNode<K, V>);
begin
  RemoveNode(ANode);
  AddToHead(ANode);
  ANode.LastAccess := Now;
  Inc(ANode.AccessCount);
end;

function TLRUCache<K, V>.RemoveTail: TLRUNode<K, V>;
begin
  Result := FTail;
  if Result <> nil then
    RemoveNode(Result);
end;

function TLRUCache<K, V>.IsExpired(ANode: TLRUNode<K, V>): Boolean;
begin
  if FConfig.TTLSeconds <= 0 then
    Result := False
  else
    Result := SecondsBetween(Now, ANode.CreatedAt) > FConfig.TTLSeconds;
end;

procedure TLRUCache<K, V>.CleanExpired;
var
  Node, NextNode: TLRUNode<K, V>;
begin
  if FConfig.TTLSeconds <= 0 then
    Exit;

  Node := FTail;
  while Node <> nil do
  begin
    NextNode := Node.Prev;
    if IsExpired(Node) then
    begin
      RemoveNode(Node);
      FMap.Remove(Node.Key);
      FCurrentSizeBytes := FCurrentSizeBytes - Node.SizeBytes;
      if Assigned(FOnEvict) then
        FOnEvict(Node.Key, Node.Value);
      Node.Free;
      Inc(FStats.Evictions);
    end;
    Node := NextNode;
  end;
end;

procedure TLRUCache<K, V>.Evict;
var
  Node: TLRUNode<K, V>;
begin
  Node := RemoveTail;
  if Node <> nil then
  begin
    FMap.Remove(Node.Key);
    FCurrentSizeBytes := FCurrentSizeBytes - Node.SizeBytes;
    if Assigned(FOnEvict) then
      FOnEvict(Node.Key, Node.Value);
    Node.Free;
    Inc(FStats.Evictions);
  end;
end;

function TLRUCache<K, V>.Get(const AKey: K; out AValue: V): Boolean;
var
  Node: TLRUNode<K, V>;
begin
  FLock.Enter;
  try
    if FMap.TryGetValue(AKey, Node) then
    begin
      if IsExpired(Node) then
      begin
        // 过期，移�?
        RemoveNode(Node);
        FMap.Remove(AKey);
        FCurrentSizeBytes := FCurrentSizeBytes - Node.SizeBytes;
        Node.Free;
        Inc(FStats.Misses);
        Result := False;
      end
      else
      begin
        MoveToHead(Node);
        AValue := Node.Value;
        Inc(FStats.Hits);
        Result := True;
      end;
    end
    else
    begin
      Inc(FStats.Misses);
      Result := False;
    end;
    FStats.Items := FMap.Count;
    FStats.SizeBytes := FCurrentSizeBytes;
  finally
    FLock.Leave;
  end;
end;

function TLRUCache<K, V>.GetOrDefault(const AKey: K; const ADefault: V): V;
begin
  if not Get(AKey, Result) then
    Result := ADefault;
end;

procedure TLRUCache<K, V>.Put(const AKey: K; const AValue: V; ASizeBytes: Integer);
var
  Node: TLRUNode<K, V>;
begin
  FLock.Enter;
  try
    // 清理过期
    CleanExpired;

    if FMap.TryGetValue(AKey, Node) then
    begin
      // 更新现有节点
      FCurrentSizeBytes := FCurrentSizeBytes - Node.SizeBytes;
      Node.Value := AValue;
      Node.SizeBytes := ASizeBytes;
      Node.CreatedAt := Now;
      FCurrentSizeBytes := FCurrentSizeBytes + ASizeBytes;
      MoveToHead(Node);
    end
    else
    begin
      // 淘汰直到有空�?
      while (FMap.Count >= FConfig.Capacity) or
            ((FConfig.MaxSizeBytes > 0) and (FCurrentSizeBytes + ASizeBytes > FConfig.MaxSizeBytes)) do
      begin
        if FMap.Count = 0 then
          Break;
        Evict;
      end;

      // 添加新节�?
      Node := TLRUNode<K, V>.Create(AKey, AValue, ASizeBytes);
      AddToHead(Node);
      FMap.Add(AKey, Node);
      FCurrentSizeBytes := FCurrentSizeBytes + ASizeBytes;
    end;

    FStats.Items := FMap.Count;
    FStats.SizeBytes := FCurrentSizeBytes;
  finally
    FLock.Leave;
  end;
end;

function TLRUCache<K, V>.Remove(const AKey: K): Boolean;
var
  Node: TLRUNode<K, V>;
begin
  FLock.Enter;
  try
    if FMap.TryGetValue(AKey, Node) then
    begin
      RemoveNode(Node);
      FMap.Remove(AKey);
      FCurrentSizeBytes := FCurrentSizeBytes - Node.SizeBytes;
      Node.Free;
      FStats.Items := FMap.Count;
      FStats.SizeBytes := FCurrentSizeBytes;
      Result := True;
    end
    else
      Result := False;
  finally
    FLock.Leave;
  end;
end;

function TLRUCache<K, V>.Contains(const AKey: K): Boolean;
begin
  FLock.Enter;
  try
    Result := FMap.ContainsKey(AKey);
  finally
    FLock.Leave;
  end;
end;

procedure TLRUCache<K, V>.Clear;
var
  Node, NextNode: TLRUNode<K, V>;
begin
  FLock.Enter;
  try
    Node := FHead;
    while Node <> nil do
    begin
      NextNode := Node.Next;
      Node.Free;
      Node := NextNode;
    end;
    FMap.Clear;
    FHead := nil;
    FTail := nil;
    FCurrentSizeBytes := 0;
    FStats.Items := 0;
    FStats.SizeBytes := 0;
  finally
    FLock.Leave;
  end;
end;

function TLRUCache<K, V>.GetStats: TCacheStats;
begin
  FLock.Enter;
  try
    Result := FStats;
  finally
    FLock.Leave;
  end;
end;

function TLRUCache<K, V>.Keys: TArray<K>;
begin
  FLock.Enter;
  try
    Result := FMap.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TLRUCache<K, V>.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FMap.Count;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TStringCache
// ============================================================================

function TStringCache.GetOrCompute(const AKey: string; ACompute: TFunc<string>): string;
begin
  if not Get(AKey, Result) then
  begin
    Result := ACompute();
    Put(AKey, Result, Length(Result) * SizeOf(Char));
  end;
end;

// ============================================================================
// TCachedWorkflowDef
// ============================================================================

constructor TCachedWorkflowDef.Create(AJson: TJSONObject; const AFilePath, AHash: string;
  AModTime: TDateTime);
begin
  inherited Create;
  FJson := AJson;
  FFilePath := AFilePath;
  FFileHash := AHash;
  FFileModTime := AModTime;
  FLoadedAt := Now;
  FAccessCount := 0;
end;

destructor TCachedWorkflowDef.Destroy;
begin
  FJson.Free;
  inherited;
end;

procedure TCachedWorkflowDef.Touch;
begin
  Inc(FAccessCount);
end;

// ============================================================================
// TWorkflowDefinitionCache
// ============================================================================

constructor TWorkflowDefinitionCache.Create(ACapacity: Integer);
begin
  inherited Create;
  FCache := TLRUCache<string, TCachedWorkflowDef>.Create(ACapacity);
  FLock := TCriticalSection.Create;
  FAutoReload := True;
end;

destructor TWorkflowDefinitionCache.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

function TWorkflowDefinitionCache.ComputeFileHash(const AFilePath: string): string;
begin
  if TFile.Exists(AFilePath) then
    Result := THashMD5.GetHashString(TFile.ReadAllText(AFilePath))
  else
    Result := '';
end;

function TWorkflowDefinitionCache.GetFileModTime(const AFilePath: string): TDateTime;
begin
  if TFile.Exists(AFilePath) then
    Result := TFile.GetLastWriteTime(AFilePath)
  else
    Result := 0;
end;

function TWorkflowDefinitionCache.LoadFromFile(const AFilePath: string): TJSONObject;
var
  Cached: TCachedWorkflowDef;
  Content: string;
  CurrentModTime: TDateTime;
  Json: TJSONObject;
begin
  Result := nil;

  FLock.Enter;
  try
    // 检查缓�?
    if FCache.Get(AFilePath, Cached) then
    begin
      if FAutoReload then
      begin
        // 检查文件是否变�?
        CurrentModTime := GetFileModTime(AFilePath);
        if CurrentModTime <> Cached.FileModTime then
        begin
          // 文件已变更，重新加载
          FCache.Remove(AFilePath);
        end
        else
        begin
          Cached.Touch;
          Result := TJSONObject(TJSONObject.ParseJSONValue(Cached.Json.ToString));
          Exit;
        end;
      end
      else
      begin
        Cached.Touch;
        Result := TJSONObject(TJSONObject.ParseJSONValue(Cached.Json.ToString));
        Exit;
      end;
    end;

    // 加载文件
    if not TFile.Exists(AFilePath) then
      Exit;

    Content := TFile.ReadAllText(AFilePath);
    Json := TJSONObject(TJSONObject.ParseJSONValue(Content));
    if Json = nil then
      Exit;

    // 添加到缓�?
    Cached := TCachedWorkflowDef.Create(
      Json,
      AFilePath,
      THashMD5.GetHashString(Content),
      GetFileModTime(AFilePath)
    );
    FCache.Put(AFilePath, Cached, Length(Content));

    // 返回克隆
    Result := TJSONObject(TJSONObject.ParseJSONValue(Json.ToString));
  finally
    FLock.Leave;
  end;
end;

function TWorkflowDefinitionCache.LoadFromString(const AContent: string): TJSONObject;
var
  Hash: string;
  Cached: TCachedWorkflowDef;
  Json: TJSONObject;
begin
  Result := nil;
  Hash := THashMD5.GetHashString(AContent);

  FLock.Enter;
  try
    // 检查缓�?
    if FCache.Get(Hash, Cached) then
    begin
      Cached.Touch;
      Result := TJSONObject(TJSONObject.ParseJSONValue(Cached.Json.ToString));
      Exit;
    end;

    // 解析
    Json := TJSONObject(TJSONObject.ParseJSONValue(AContent));
    if Json = nil then
      Exit;

    // 添加到缓�?
    Cached := TCachedWorkflowDef.Create(Json, '', Hash, 0);
    FCache.Put(Hash, Cached, Length(AContent));

    // 返回克隆
    Result := TJSONObject(TJSONObject.ParseJSONValue(Json.ToString));
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDefinitionCache.Invalidate(const AFilePath: string);
begin
  FLock.Enter;
  try
    FCache.Remove(AFilePath);
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDefinitionCache.InvalidateAll;
begin
  FLock.Enter;
  try
    FCache.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDefinitionCache.Preload(const AFilePaths: TArray<string>);
var
  FilePath: string;
  Json: TJSONObject;
begin
  for FilePath in AFilePaths do
  begin
    Json := LoadFromFile(FilePath);
    if Json <> nil then
      Json.Free;
  end;
end;

function TWorkflowDefinitionCache.GetStats: TJSONObject;
var
  Stats: TCacheStats;
begin
  Stats := FCache.GetStats;
  Result := Stats.ToJSON;
  Result.AddPair('autoReload', TJSONBool.Create(FAutoReload));
end;

// ============================================================================
// TCachedSchema
// ============================================================================

constructor TCachedSchema.Create(ASchema: TJSONObject; const AVersion: string);
begin
  inherited Create;
  FSchema := ASchema;
  FVersion := AVersion;
  FLoadedAt := Now;
  FCompiledData := nil;
end;

destructor TCachedSchema.Destroy;
begin
  FSchema.Free;
  FCompiledData.Free;
  inherited;
end;

// ============================================================================
// TSchemaCache
// ============================================================================

constructor TSchemaCache.Create(const ASchemaDir: string; ACapacity: Integer);
begin
  inherited Create;
  FSchemaDir := ASchemaDir;
  FCache := TLRUCache<string, TCachedSchema>.Create(ACapacity);
  FLock := TCriticalSection.Create;
end;

destructor TSchemaCache.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

function TSchemaCache.Get(const ASchemaId: string): TJSONObject;
var
  Cached: TCachedSchema;
begin
  Result := nil;
  FLock.Enter;
  try
    if FCache.Get(ASchemaId, Cached) then
      Result := TJSONObject(TJSONObject.ParseJSONValue(Cached.Schema.ToString));
  finally
    FLock.Leave;
  end;
end;

function TSchemaCache.LoadSchema(const ASchemaId: string): TJSONObject;
var
  FilePath, Content: string;
  Cached: TCachedSchema;
  Json: TJSONObject;
begin
  Result := nil;

  // 先检查缓�?
  Result := Get(ASchemaId);
  if Result <> nil then
    Exit;

  // 加载文件
  FilePath := TPath.Combine(FSchemaDir, ASchemaId + '.schema.json');
  if not TFile.Exists(FilePath) then
    Exit;

  FLock.Enter;
  try
    Content := TFile.ReadAllText(FilePath);
    Json := TJSONObject(TJSONObject.ParseJSONValue(Content));
    if Json = nil then
      Exit;

    Cached := TCachedSchema.Create(Json, '1.0');
    FCache.Put(ASchemaId, Cached, Length(Content));

    Result := TJSONObject(TJSONObject.ParseJSONValue(Json.ToString));
  finally
    FLock.Leave;
  end;
end;

procedure TSchemaCache.Register(const ASchemaId: string; ASchema: TJSONObject; const AVersion: string);
var
  Cached: TCachedSchema;
  Clone: TJSONObject;
begin
  FLock.Enter;
  try
    Clone := TJSONObject(TJSONObject.ParseJSONValue(ASchema.ToString));
    Cached := TCachedSchema.Create(Clone, AVersion);
    FCache.Put(ASchemaId, Cached, Length(ASchema.ToString));
  finally
    FLock.Leave;
  end;
end;

procedure TSchemaCache.Invalidate(const ASchemaId: string);
begin
  FLock.Enter;
  try
    FCache.Remove(ASchemaId);
  finally
    FLock.Leave;
  end;
end;

function TSchemaCache.GetStats: TJSONObject;
var
  Stats: TCacheStats;
begin
  Stats := FCache.GetStats;
  Result := Stats.ToJSON;
  Result.AddPair('schemaDir', FSchemaDir);
end;

// ============================================================================
// TMultiLevelCache
// ============================================================================

constructor TMultiLevelCache.Create(AL1Size, AL2Size, AL3Size: Integer);
begin
  inherited Create;
  FL1 := TLRUCache<string, string>.Create(AL1Size);
  FL2 := TLRUCache<string, string>.Create(AL2Size);
  FL3 := TLRUCache<string, string>.Create(AL3Size);
  FLock := TCriticalSection.Create;
  FPromoteOnHit := True;
end;

destructor TMultiLevelCache.Destroy;
begin
  FL1.Free;
  FL2.Free;
  FL3.Free;
  FLock.Free;
  inherited;
end;

function TMultiLevelCache.Get(const AKey: string; out AValue: string): Boolean;
begin
  FLock.Enter;
  try
    // L1
    if FL1.Get(AKey, AValue) then
    begin
      Result := True;
      Exit;
    end;

    // L2
    if FL2.Get(AKey, AValue) then
    begin
      if FPromoteOnHit then
        FL1.Put(AKey, AValue, Length(AValue) * SizeOf(Char));
      Result := True;
      Exit;
    end;

    // L3
    if FL3.Get(AKey, AValue) then
    begin
      if FPromoteOnHit then
      begin
        FL2.Put(AKey, AValue, Length(AValue) * SizeOf(Char));
        FL1.Put(AKey, AValue, Length(AValue) * SizeOf(Char));
      end;
      Result := True;
      Exit;
    end;

    Result := False;
  finally
    FLock.Leave;
  end;
end;

procedure TMultiLevelCache.Put(const AKey, AValue: string; ALevel: TCacheLevel);
var
  Size: Integer;
begin
  Size := Length(AValue) * SizeOf(Char);
  FLock.Enter;
  try
    case ALevel of
      clL1:
        FL1.Put(AKey, AValue, Size);
      clL2:
        FL2.Put(AKey, AValue, Size);
      clL3:
        FL3.Put(AKey, AValue, Size);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMultiLevelCache.Remove(const AKey: string);
begin
  FLock.Enter;
  try
    FL1.Remove(AKey);
    FL2.Remove(AKey);
    FL3.Remove(AKey);
  finally
    FLock.Leave;
  end;
end;

procedure TMultiLevelCache.Clear;
begin
  FLock.Enter;
  try
    FL1.Clear;
    FL2.Clear;
    FL3.Clear;
  finally
    FLock.Leave;
  end;
end;

function TMultiLevelCache.GetStats: TJSONObject;
begin
  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('l1', FL1.GetStats.ToJSON);
    Result.AddPair('l2', FL2.GetStats.ToJSON);
    Result.AddPair('l3', FL3.GetStats.ToJSON);
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TCacheManager
// ============================================================================

constructor TCacheManager.Create;
begin
  inherited Create;
  FCaches := TDictionary<string, TObject>.Create;
  FLock := TCriticalSection.Create;
  FWorkflowCache := TWorkflowDefinitionCache.Create(100);
  FSchemaCache := TSchemaCache.Create('', 50);
  FStringCache := TStringCache.Create(1000);

  RegisterCache('workflow', FWorkflowCache);
  RegisterCache('schema', FSchemaCache);
  RegisterCache('string', FStringCache);
end;

destructor TCacheManager.Destroy;
begin
  // 注意：不要释放已注册的缓存，因为它们也在 FCaches �?
  FWorkflowCache := nil;
  FSchemaCache := nil;
  FStringCache := nil;

  FLock.Enter;
  try
    for var Cache in FCaches.Values do
      Cache.Free;
    FCaches.Free;
  finally
    FLock.Leave;
  end;
  FLock.Free;
  inherited;
end;

procedure TCacheManager.RegisterCache(const AName: string; ACache: TObject);
begin
  FLock.Enter;
  try
    FCaches.AddOrSetValue(AName, ACache);
  finally
    FLock.Leave;
  end;
end;

function TCacheManager.GetCache<T>(const AName: string): T;
var
  Obj: TObject;
begin
  Result := nil;
  FLock.Enter;
  try
    if FCaches.TryGetValue(AName, Obj) then
      Result := T(Obj);
  finally
    FLock.Leave;
  end;
end;

procedure TCacheManager.ClearAll;
begin
  FLock.Enter;
  try
    FWorkflowCache.InvalidateAll;
    FStringCache.Clear;
  finally
    FLock.Leave;
  end;
end;

function TCacheManager.GetAllStats: TJSONObject;
begin
  Result := TJSONObject.Create;
  FLock.Enter;
  try
    Result.AddPair('workflow', FWorkflowCache.GetStats);
    Result.AddPair('schema', FSchemaCache.GetStats);
    Result.AddPair('string', FStringCache.GetStats.ToJSON);
  finally
    FLock.Leave;
  end;
end;

procedure TCacheManager.Warmup(const AWorkflowDir, ASchemaDir: string);
var
  Files: TStringDynArray;
  FilePath: string;
begin
  FSchemaCache.SchemaDir := ASchemaDir;

  // 预加载工作流
  if TDirectory.Exists(AWorkflowDir) then
  begin
    Files := TDirectory.GetFiles(AWorkflowDir, '*.json');
    for FilePath in Files do
      FWorkflowCache.LoadFromFile(FilePath);
  end;

  // 预加�?Schema
  if TDirectory.Exists(ASchemaDir) then
  begin
    Files := TDirectory.GetFiles(ASchemaDir, '*.schema.json');
    for FilePath in Files do
    begin
      var SchemaId := TPath.GetFileNameWithoutExtension(FilePath);
      SchemaId := SchemaId.Replace('.schema', '');
      FSchemaCache.LoadSchema(SchemaId);
    end;
  end;
end;

class function TCacheManager.GetInstance: TCacheManager;
begin
  if FInstance = nil then
    FInstance := TCacheManager.Create;
  Result := FInstance;
end;

class procedure TCacheManager.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

// ============================================================================
// Global Function
// ============================================================================

function CacheManager: TCacheManager;
begin
  Result := TCacheManager.GetInstance;
end;

initialization

finalization
  TCacheManager.ReleaseInstance;

end.
