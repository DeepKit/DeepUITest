unit UniFlow.Performance.Pool;
(*
  UniFlow Performance - Object Pool
  ==================================
  高性能对象池实现，减少频繁创建/销毁对象的开销�?
  
  特性：
  - 泛型对象池，支持任意类型
  - 线程安全
  - 预分�?+ 动态扩�?
  - 对象重置机制
  - 统计信息
  
  Author: UniFlow Team
  Date: 2025-12-05
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.SyncObjs, System.JSON;

type
  // ============================================================================
  // 池化对象接口
  // ============================================================================
  
  /// <summary>可池化对象接�?/summary>
  IPoolable = interface
    ['{8A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D}']
    /// <summary>重置对象状态，准备重用</summary>
    procedure Reset;
    /// <summary>对象是否可重�?/summary>
    function IsReusable: Boolean;
  end;
  
  // ============================================================================
  // 对象池统�?
  // ============================================================================
  
  TPoolStats = record
    TotalCreated: Int64;      // 总创建数
    TotalAcquired: Int64;     // 总获取数
    TotalReleased: Int64;     // 总释放数
    TotalReset: Int64;        // 总重置数
    CurrentPoolSize: Integer; // 当前池大�?
    CurrentInUse: Integer;    // 当前使用�?
    PeakInUse: Integer;       // 峰值使�?
    HitRate: Double;          // 命中�?
    
    procedure Reset;
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // 对象池配�?
  // ============================================================================
  
  TPoolConfig = record
    InitialSize: Integer;     // 初始池大�?
    MaxSize: Integer;         // 最大池大小 (0 = 无限�?
    GrowthFactor: Double;     // 扩容因子
    ShrinkThreshold: Double;  // 收缩阈�?
    MaxIdleTimeMs: Int64;     // 最大空闲时�?(ms)
    
    class function Default: TPoolConfig; static;
    class function Small: TPoolConfig; static;
    class function Large: TPoolConfig; static;
  end;
  
  // ============================================================================
  // 池化对象包装
  // ============================================================================
  
  TPooledItem<T: class> = class
  private
    FInstance: T;
    FLastUsed: TDateTime;
    FUseCount: Integer;
  public
    constructor Create(AInstance: T);
    destructor Destroy; override;
    
    procedure MarkUsed;
    function IsExpired(MaxIdleMs: Int64): Boolean;
    
    property Instance: T read FInstance;
    property LastUsed: TDateTime read FLastUsed;
    property UseCount: Integer read FUseCount;
  end;
  
  // ============================================================================
  // 泛型对象�?
  // ============================================================================
  
  /// <summary>对象工厂函数类型</summary>
  TObjectFactory<T: class> = reference to function: T;
  
  /// <summary>对象重置函数类型</summary>
  TObjectResetter<T: class> = reference to procedure(AInstance: T);
  
  /// <summary>对象验证函数类型</summary>
  TObjectValidator<T: class> = reference to function(AInstance: T): Boolean;
  
  TObjectPool<T: class> = class
  private
    FPool: TObjectList<TPooledItem<T>>;
    FConfig: TPoolConfig;
    FFactory: TObjectFactory<T>;
    FResetter: TObjectResetter<T>;
    FValidator: TObjectValidator<T>;
    FLock: TCriticalSection;
    FStats: TPoolStats;
    FEnabled: Boolean;
    
    function CreateInstance: T;
    procedure ResetInstance(AInstance: T);
    function ValidateInstance(AInstance: T): Boolean;
    procedure GrowPool;
    procedure ShrinkPool;
    procedure CleanExpired;
  public
    constructor Create(AFactory: TObjectFactory<T>; AConfig: TPoolConfig); overload;
    constructor Create(AFactory: TObjectFactory<T>); overload;
    destructor Destroy; override;
    
    /// <summary>设置对象重置�?/summary>
    procedure SetResetter(AResetter: TObjectResetter<T>);
    
    /// <summary>设置对象验证�?/summary>
    procedure SetValidator(AValidator: TObjectValidator<T>);
    
    /// <summary>获取对象</summary>
    function Acquire: T;
    
    /// <summary>释放对象回池</summary>
    procedure Release(AInstance: T);
    
    /// <summary>预热池（预创建对象）</summary>
    procedure Warmup(ACount: Integer = 0);
    
    /// <summary>清空�?/summary>
    procedure Clear;
    
    /// <summary>收缩池到指定大小</summary>
    procedure Shrink(ATargetSize: Integer);
    
    /// <summary>获取统计信息</summary>
    function GetStats: TPoolStats;
    
    /// <summary>启用/禁用池化（禁用时直接创建新对象）</summary>
    property Enabled: Boolean read FEnabled write FEnabled;
    property Config: TPoolConfig read FConfig;
  end;
  
  // ============================================================================
  // 专用对象池：TJSONObject �?
  // ============================================================================
  
  TJSONObjectPool = class
  private
    FPool: TObjectPool<TJSONObject>;
    class var FInstance: TJSONObjectPool;
    class var FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Acquire: TJSONObject;
    procedure Release(AJson: TJSONObject);
    
    class function GetInstance: TJSONObjectPool;
    class procedure ReleaseInstance;
  end;
  
  // ============================================================================
  // 专用对象池：TStringBuilder �?
  // ============================================================================
  
  TStringBuilderPool = class
  private
    FPool: TObjectPool<TStringBuilder>;
    class var FInstance: TStringBuilderPool;
    class var FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Acquire: TStringBuilder;
    procedure Release(ASB: TStringBuilder);
    
    class function GetInstance: TStringBuilderPool;
    class procedure ReleaseInstance;
  end;
  
  // ============================================================================
  // 专用对象池：TStringList �?
  // ============================================================================
  
  TStringListPool = class
  private
    FPool: TObjectPool<TStringList>;
    class var FInstance: TStringListPool;
    class var FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Acquire: TStringList;
    procedure Release(ASL: TStringList);
    
    class function GetInstance: TStringListPool;
    class procedure ReleaseInstance;
  end;
  
  // ============================================================================
  // CODE-002: 循环变量对象�?(轻量�?
  // ============================================================================
  
  /// <summary>池化循环变量（不依赖 TVariableValue�?/summary>
  TPooledLoopVar = class
  private
    FValueType: string;
    FStringValue: string;
    FIntValue: Int64;
    FJsonValue: TJSONValue;  // 不拥�?
    FIsNull: Boolean;
    FPooled: Boolean;
  public
    constructor Create;
    procedure Reset;
    procedure SetInt(AValue: Int64);
    procedure SetStr(const AValue: string);
    procedure SetJson(AValue: TJSONValue);
    
    function AsString: string;
    function AsInteger: Int64;
    function AsJSON: TJSONValue;  // 可能创建新对象，调用者负责释�?
    
    property ValueType: string read FValueType;
    property IsPooled: Boolean read FPooled write FPooled;
    property IsNull: Boolean read FIsNull;
  end;
  
  TVariableValuePool = class
  private
    FIntPool: TObjectList<TPooledLoopVar>;     // 整数值池
    FStrPool: TObjectList<TPooledLoopVar>;     // 字符串值池
    FLock: TCriticalSection;
    FStats: TPoolStats;
    class var FInstance: TVariableValuePool;
    class var FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>获取整数值包�?/summary>
    function AcquireInt(AValue: Int64): TPooledLoopVar;
    /// <summary>获取字符串值包�?/summary>
    function AcquireStr(const AValue: string): TPooledLoopVar;
    /// <summary>获取 JSON 值包�?/summary>
    function AcquireJson(AValue: TJSONValue): TPooledLoopVar;
    /// <summary>释放值回�?/summary>
    procedure Release(AValue: TPooledLoopVar);
    /// <summary>获取统计</summary>
    function GetStats: TPoolStats;
    
    class function GetInstance: TVariableValuePool;
    class procedure ReleaseInstance;
  end;

  // ============================================================================
  // 对象池管理器
  // ============================================================================
  
  TPoolManager = class
  private
    FPools: TDictionary<string, TObject>;
    FLock: TCriticalSection;
    class var FInstance: TPoolManager;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>注册�?/summary>
    procedure RegisterPool(const AName: string; APool: TObject);
    
    /// <summary>获取�?/summary>
    function GetPool<T: class>(const AName: string): TObjectPool<T>;
    
    /// <summary>获取所有池统计</summary>
    function GetAllStats: TJSONObject;
    
    /// <summary>清理所有池</summary>
    procedure ClearAll;
    
    class function GetInstance: TPoolManager;
    class procedure ReleaseInstance;
  end;
  
  // ============================================================================
  // 池化作用域辅助类
  // ============================================================================
  
  /// <summary>RAII 风格的池化对象作用域</summary>
  TPooledScope<T: class> = record
  private
    FPool: TObjectPool<T>;
    FInstance: T;
  public
    class function Create(APool: TObjectPool<T>): TPooledScope<T>; static;
    procedure Release;
    property Instance: T read FInstance;
  end;

// ============================================================================
// 全局便捷函数
// ============================================================================

/// <summary>获取 TJSONObject 池实�?/summary>
function JSONPool: TJSONObjectPool;

/// <summary>获取 TStringBuilder 池实�?/summary>
function StringBuilderPool: TStringBuilderPool;

/// <summary>获取 TStringList 池实�?/summary>
function StringListPool: TStringListPool;

/// <summary>获取池管理器实例</summary>
function PoolManager: TPoolManager;

/// <summary>CODE-002: 获取 TVariableValue 池实�?/summary>
function VariableValuePool: TVariableValuePool;

implementation

uses
  System.DateUtils,
  System.StrUtils;

// ============================================================================
// TPoolStats
// ============================================================================

procedure TPoolStats.Reset;
begin
  TotalCreated := 0;
  TotalAcquired := 0;
  TotalReleased := 0;
  TotalReset := 0;
  CurrentPoolSize := 0;
  CurrentInUse := 0;
  PeakInUse := 0;
  HitRate := 0;
end;

function TPoolStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('totalCreated', TJSONNumber.Create(TotalCreated));
  Result.AddPair('totalAcquired', TJSONNumber.Create(TotalAcquired));
  Result.AddPair('totalReleased', TJSONNumber.Create(TotalReleased));
  Result.AddPair('totalReset', TJSONNumber.Create(TotalReset));
  Result.AddPair('currentPoolSize', TJSONNumber.Create(CurrentPoolSize));
  Result.AddPair('currentInUse', TJSONNumber.Create(CurrentInUse));
  Result.AddPair('peakInUse', TJSONNumber.Create(PeakInUse));
  Result.AddPair('hitRate', TJSONNumber.Create(HitRate));
end;

// ============================================================================
// TPoolConfig
// ============================================================================

class function TPoolConfig.Default: TPoolConfig;
begin
  Result.InitialSize := 16;
  Result.MaxSize := 256;
  Result.GrowthFactor := 2.0;
  Result.ShrinkThreshold := 0.25;
  Result.MaxIdleTimeMs := 60000; // 1 minute
end;

class function TPoolConfig.Small: TPoolConfig;
begin
  Result.InitialSize := 4;
  Result.MaxSize := 32;
  Result.GrowthFactor := 2.0;
  Result.ShrinkThreshold := 0.25;
  Result.MaxIdleTimeMs := 30000;
end;

class function TPoolConfig.Large: TPoolConfig;
begin
  Result.InitialSize := 64;
  Result.MaxSize := 1024;
  Result.GrowthFactor := 1.5;
  Result.ShrinkThreshold := 0.1;
  Result.MaxIdleTimeMs := 120000; // 2 minutes
end;

// ============================================================================
// TPooledItem<T>
// ============================================================================

constructor TPooledItem<T>.Create(AInstance: T);
begin
  inherited Create;
  FInstance := AInstance;
  FLastUsed := Now;
  FUseCount := 0;
end;

destructor TPooledItem<T>.Destroy;
begin
  if Assigned(FInstance) then
    FInstance.Free;
  inherited;
end;

procedure TPooledItem<T>.MarkUsed;
begin
  FLastUsed := Now;
  Inc(FUseCount);
end;

function TPooledItem<T>.IsExpired(MaxIdleMs: Int64): Boolean;
begin
  if MaxIdleMs <= 0 then
    Result := False
  else
    Result := MilliSecondsBetween(Now, FLastUsed) > MaxIdleMs;
end;

// ============================================================================
// TObjectPool<T>
// ============================================================================

constructor TObjectPool<T>.Create(AFactory: TObjectFactory<T>; AConfig: TPoolConfig);
begin
  inherited Create;
  FFactory := AFactory;
  FConfig := AConfig;
  FPool := TObjectList<TPooledItem<T>>.Create(True);
  FLock := TCriticalSection.Create;
  FStats.Reset;
  FEnabled := True;
  
  // 初始化池
  Warmup(FConfig.InitialSize);
end;

constructor TObjectPool<T>.Create(AFactory: TObjectFactory<T>);
begin
  Create(AFactory, TPoolConfig.Default);
end;

destructor TObjectPool<T>.Destroy;
begin
  Clear;
  FPool.Free;
  FLock.Free;
  inherited;
end;

procedure TObjectPool<T>.SetResetter(AResetter: TObjectResetter<T>);
begin
  FResetter := AResetter;
end;

procedure TObjectPool<T>.SetValidator(AValidator: TObjectValidator<T>);
begin
  FValidator := AValidator;
end;

function TObjectPool<T>.CreateInstance: T;
begin
  Result := FFactory();
  Inc(FStats.TotalCreated);
end;

procedure TObjectPool<T>.ResetInstance(AInstance: T);
begin
  if Assigned(FResetter) then
  begin
    FResetter(AInstance);
    Inc(FStats.TotalReset);
  end
  else if Supports(AInstance, IPoolable) then
  begin
    (AInstance as IPoolable).Reset;
    Inc(FStats.TotalReset);
  end;
end;

function TObjectPool<T>.ValidateInstance(AInstance: T): Boolean;
begin
  if Assigned(FValidator) then
    Result := FValidator(AInstance)
  else if Supports(AInstance, IPoolable) then
    Result := (AInstance as IPoolable).IsReusable
  else
    Result := True;
end;

procedure TObjectPool<T>.GrowPool;
var
  NewSize, i: Integer;
begin
  // 计算新大�?
  NewSize := Round(FPool.Count * FConfig.GrowthFactor);
  if NewSize < FPool.Count + 1 then
    NewSize := FPool.Count + 1;
  
  // 限制最大大�?
  if (FConfig.MaxSize > 0) and (NewSize > FConfig.MaxSize) then
    NewSize := FConfig.MaxSize;
  
  // 扩容
  for i := FPool.Count to NewSize - 1 do
    FPool.Add(TPooledItem<T>.Create(CreateInstance));
  
  FStats.CurrentPoolSize := FPool.Count;
end;

procedure TObjectPool<T>.ShrinkPool;
var
  TargetSize, i: Integer;
begin
  // 计算目标大小
  TargetSize := FConfig.InitialSize;
  if FStats.PeakInUse > TargetSize then
    TargetSize := FStats.PeakInUse;
  
  // 收缩
  while FPool.Count > TargetSize do
    FPool.Delete(FPool.Count - 1);
  
  FStats.CurrentPoolSize := FPool.Count;
end;

procedure TObjectPool<T>.CleanExpired;
var
  i: Integer;
begin
  if FConfig.MaxIdleTimeMs <= 0 then
    Exit;
    
  for i := FPool.Count - 1 downto 0 do
  begin
    if FPool[i].IsExpired(FConfig.MaxIdleTimeMs) then
      FPool.Delete(i);
  end;
  
  FStats.CurrentPoolSize := FPool.Count;
end;

function TObjectPool<T>.Acquire: T;
var
  Item: TPooledItem<T>;
  i: Integer;
begin
  // 如果禁用池化，直接创建新对象
  if not FEnabled then
  begin
    Result := CreateInstance;
    Exit;
  end;
  
  FLock.Enter;
  try
    Inc(FStats.TotalAcquired);
    
    // 清理过期对象
    CleanExpired;
    
    // 从池中获�?
    for i := FPool.Count - 1 downto 0 do
    begin
      Item := FPool[i];
      if ValidateInstance(Item.Instance) then
      begin
        Result := Item.Instance;
        Item.MarkUsed;
        FPool.OwnsObjects := False;
        FPool.Delete(i);
        FPool.OwnsObjects := True;
        Item.Free;
        
        Inc(FStats.CurrentInUse);
        if FStats.CurrentInUse > FStats.PeakInUse then
          FStats.PeakInUse := FStats.CurrentInUse;
        
        FStats.CurrentPoolSize := FPool.Count;
        
        // 计算命中�?(保护除零)
        if FStats.TotalAcquired > 0 then
          FStats.HitRate := (FStats.TotalAcquired - FStats.TotalCreated) / FStats.TotalAcquired
        else
          FStats.HitRate := 0;
        
        Exit;
      end;
    end;
    
    // 池空，创建新对象
    Result := CreateInstance;
    Inc(FStats.CurrentInUse);
    if FStats.CurrentInUse > FStats.PeakInUse then
      FStats.PeakInUse := FStats.CurrentInUse;
    
    // 计算命中�?
    if FStats.TotalAcquired > 0 then
      FStats.HitRate := (FStats.TotalAcquired - FStats.TotalCreated) / FStats.TotalAcquired;
  finally
    FLock.Leave;
  end;
end;

procedure TObjectPool<T>.Release(AInstance: T);
var
  Item: TPooledItem<T>;
begin
  if AInstance = nil then
    Exit;
    
  // 如果禁用池化，直接销�?
  if not FEnabled then
  begin
    AInstance.Free;
    Exit;
  end;
  
  FLock.Enter;
  try
    Inc(FStats.TotalReleased);
    Dec(FStats.CurrentInUse);
    
    // 检查是否超过最大大�?
    if (FConfig.MaxSize > 0) and (FPool.Count >= FConfig.MaxSize) then
    begin
      AInstance.Free;
      Exit;
    end;
    
    // 重置对象
    ResetInstance(AInstance);
    
    // 验证对象
    if not ValidateInstance(AInstance) then
    begin
      AInstance.Free;
      Exit;
    end;
    
    // 放回池中
    Item := TPooledItem<T>.Create(AInstance);
    FPool.Add(Item);
    FStats.CurrentPoolSize := FPool.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TObjectPool<T>.Warmup(ACount: Integer);
var
  i, TargetCount: Integer;
begin
  FLock.Enter;
  try
    if ACount <= 0 then
      TargetCount := FConfig.InitialSize
    else
      TargetCount := ACount;
      
    // 限制最大大�?
    if (FConfig.MaxSize > 0) and (TargetCount > FConfig.MaxSize) then
      TargetCount := FConfig.MaxSize;
    
    for i := FPool.Count to TargetCount - 1 do
      FPool.Add(TPooledItem<T>.Create(CreateInstance));
    
    FStats.CurrentPoolSize := FPool.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TObjectPool<T>.Clear;
begin
  FLock.Enter;
  try
    FPool.Clear;
    FStats.CurrentPoolSize := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TObjectPool<T>.Shrink(ATargetSize: Integer);
begin
  FLock.Enter;
  try
    while FPool.Count > ATargetSize do
      FPool.Delete(FPool.Count - 1);
    FStats.CurrentPoolSize := FPool.Count;
  finally
    FLock.Leave;
  end;
end;

function TObjectPool<T>.GetStats: TPoolStats;
begin
  FLock.Enter;
  try
    Result := FStats;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TJSONObjectPool
// ============================================================================

constructor TJSONObjectPool.Create;
begin
  inherited Create;
  FPool := TObjectPool<TJSONObject>.Create(
    function: TJSONObject
    begin
      Result := TJSONObject.Create;
    end,
    TPoolConfig.Default
  );
  
  FPool.SetResetter(
    procedure(AJson: TJSONObject)
    var
      I: Integer;
      Pair: TJSONPair;
    begin
      // 清空 JSON 对象 - 使用倒序删除避免索引问题
      for I := AJson.Count - 1 downto 0 do
      begin
        Pair := AJson.Pairs[I];
        AJson.RemovePair(Pair.JsonString.Value);
        Pair.Free; // Free pair (also frees JsonValue)
      end;
    end
  );
end;

destructor TJSONObjectPool.Destroy;
begin
  FPool.Free;
  inherited;
end;

function TJSONObjectPool.Acquire: TJSONObject;
begin
  Result := FPool.Acquire;
end;

procedure TJSONObjectPool.Release(AJson: TJSONObject);
begin
  FPool.Release(AJson);
end;

class function TJSONObjectPool.GetInstance: TJSONObjectPool;
begin
  if FInstance = nil then
  begin
    if FLock = nil then
      FLock := TCriticalSection.Create;
    FLock.Enter;
    try
      if FInstance = nil then
        FInstance := TJSONObjectPool.Create;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

class procedure TJSONObjectPool.ReleaseInstance;
begin
  if FLock <> nil then
  begin
    FLock.Enter;
    try
      FreeAndNil(FInstance);
    finally
      FLock.Leave;
    end;
    FreeAndNil(FLock);
  end;
end;

// ============================================================================
// TStringBuilderPool
// ============================================================================

constructor TStringBuilderPool.Create;
begin
  inherited Create;
  FPool := TObjectPool<TStringBuilder>.Create(
    function: TStringBuilder
    begin
      Result := TStringBuilder.Create(256);
    end,
    TPoolConfig.Default
  );
  
  FPool.SetResetter(
    procedure(ASB: TStringBuilder)
    begin
      ASB.Clear;
    end
  );
end;

destructor TStringBuilderPool.Destroy;
begin
  FPool.Free;
  inherited;
end;

function TStringBuilderPool.Acquire: TStringBuilder;
begin
  Result := FPool.Acquire;
end;

procedure TStringBuilderPool.Release(ASB: TStringBuilder);
begin
  FPool.Release(ASB);
end;

class function TStringBuilderPool.GetInstance: TStringBuilderPool;
begin
  if FInstance = nil then
  begin
    if FLock = nil then
      FLock := TCriticalSection.Create;
    FLock.Enter;
    try
      if FInstance = nil then
        FInstance := TStringBuilderPool.Create;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

class procedure TStringBuilderPool.ReleaseInstance;
begin
  if FLock <> nil then
  begin
    FLock.Enter;
    try
      FreeAndNil(FInstance);
    finally
      FLock.Leave;
    end;
    FreeAndNil(FLock);
  end;
end;

// ============================================================================
// TStringListPool
// ============================================================================

constructor TStringListPool.Create;
begin
  inherited Create;
  FPool := TObjectPool<TStringList>.Create(
    function: TStringList
    begin
      Result := TStringList.Create;
    end,
    TPoolConfig.Default
  );
  
  FPool.SetResetter(
    procedure(ASL: TStringList)
    begin
      ASL.Clear;
    end
  );
end;

destructor TStringListPool.Destroy;
begin
  FPool.Free;
  inherited;
end;

function TStringListPool.Acquire: TStringList;
begin
  Result := FPool.Acquire;
end;

procedure TStringListPool.Release(ASL: TStringList);
begin
  FPool.Release(ASL);
end;

class function TStringListPool.GetInstance: TStringListPool;
begin
  if FInstance = nil then
  begin
    if FLock = nil then
      FLock := TCriticalSection.Create;
    FLock.Enter;
    try
      if FInstance = nil then
        FInstance := TStringListPool.Create;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

class procedure TStringListPool.ReleaseInstance;
begin
  if FLock <> nil then
  begin
    FLock.Enter;
    try
      FreeAndNil(FInstance);
    finally
      FLock.Leave;
    end;
    FreeAndNil(FLock);
  end;
end;

// ============================================================================
// TPoolManager
// ============================================================================

constructor TPoolManager.Create;
begin
  inherited Create;
  FPools := TDictionary<string, TObject>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TPoolManager.Destroy;
var
  Pool: TObject;
begin
  FLock.Enter;
  try
    for Pool in FPools.Values do
      Pool.Free;
    FPools.Free;
  finally
    FLock.Leave;
  end;
  FLock.Free;
  inherited;
end;

procedure TPoolManager.RegisterPool(const AName: string; APool: TObject);
begin
  FLock.Enter;
  try
    if FPools.ContainsKey(AName) then
      FPools[AName].Free;
    FPools.AddOrSetValue(AName, APool);
  finally
    FLock.Leave;
  end;
end;

function TPoolManager.GetPool<T>(const AName: string): TObjectPool<T>;
begin
  FLock.Enter;
  try
    if FPools.ContainsKey(AName) then
      Result := TObjectPool<T>(FPools[AName])
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TPoolManager.GetAllStats: TJSONObject;
var
  Pair: TPair<string, TObject>;
  PoolStats: TJSONObject;
begin
  Result := TJSONObject.Create;
  FLock.Enter;
  try
    for Pair in FPools do
    begin
      // 尝试获取统计信息 - 简化处�?
      PoolStats := TJSONObject.Create;
      PoolStats.AddPair('registered', TJSONBool.Create(True));
      Result.AddPair(Pair.Key, PoolStats);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TPoolManager.ClearAll;
var
  Pool: TObject;
begin
  FLock.Enter;
  try
    for Pool in FPools.Values do
      Pool.Free;
    FPools.Clear;
  finally
    FLock.Leave;
  end;
end;

class function TPoolManager.GetInstance: TPoolManager;
begin
  if FInstance = nil then
    FInstance := TPoolManager.Create;
  Result := FInstance;
end;

class procedure TPoolManager.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

// ============================================================================
// TPooledScope<T>
// ============================================================================

class function TPooledScope<T>.Create(APool: TObjectPool<T>): TPooledScope<T>;
begin
  Result.FPool := APool;
  Result.FInstance := APool.Acquire;
end;

procedure TPooledScope<T>.Release;
begin
  if Assigned(FPool) and Assigned(FInstance) then
  begin
    FPool.Release(FInstance);
    FInstance := nil;
  end;
end;

// ============================================================================
// 全局便捷函数
// ============================================================================

function JSONPool: TJSONObjectPool;
begin
  Result := TJSONObjectPool.GetInstance;
end;

function StringBuilderPool: TStringBuilderPool;
begin
  Result := TStringBuilderPool.GetInstance;
end;

function StringListPool: TStringListPool;
begin
  Result := TStringListPool.GetInstance;
end;

function PoolManager: TPoolManager;
begin
  Result := TPoolManager.GetInstance;
end;

function VariableValuePool: TVariableValuePool;
begin
  Result := TVariableValuePool.GetInstance;
end;

// ============================================================================
// TVariableValuePool - CODE-002
// 使用轻量级循环变量包装类，包含完整字�?
// ============================================================================

constructor TPooledLoopVar.Create;
begin
  inherited Create;
  FValueType := 'null';
  FIsNull := True;
  FPooled := False;
end;

procedure TPooledLoopVar.Reset;
begin
  FValueType := 'null';
  FStringValue := '';
  FIntValue := 0;
  FJsonValue := nil;  // 不拥有，不释�?
  FIsNull := True;
end;

procedure TPooledLoopVar.SetInt(AValue: Int64);
begin
  FValueType := 'integer';
  FIntValue := AValue;
  FIsNull := False;
end;

procedure TPooledLoopVar.SetStr(const AValue: string);
begin
  FValueType := 'string';
  FStringValue := AValue;
  FIsNull := False;
end;

procedure TPooledLoopVar.SetJson(AValue: TJSONValue);
begin
  FValueType := 'json';
  FJsonValue := AValue;  // 不拥�?
  FIsNull := (AValue = nil);
end;

function TPooledLoopVar.AsString: string;
begin
  if FIsNull then Exit('');
  case IndexStr(FValueType, ['string', 'integer', 'json']) of
    0: Result := FStringValue;
    1: Result := IntToStr(FIntValue);
    2: if FJsonValue <> nil then Result := FJsonValue.Value else Result := '';
  else
    Result := '';
  end;
end;

function TPooledLoopVar.AsInteger: Int64;
begin
  if FIsNull then Exit(0);
  case IndexStr(FValueType, ['integer', 'string']) of
    0: Result := FIntValue;
    1: Result := StrToInt64Def(FStringValue, 0);
  else
    Result := 0;
  end;
end;

function TPooledLoopVar.AsJSON: TJSONValue;
begin
  if FIsNull then Exit(nil);
  case IndexStr(FValueType, ['json', 'string', 'integer']) of
    0: Result := FJsonValue;
    1: Result := TJSONString.Create(FStringValue);
    2: Result := TJSONNumber.Create(FIntValue);
  else
    Result := nil;
  end;
end;

constructor TVariableValuePool.Create;
begin
  inherited Create;
  FIntPool := TObjectList<TPooledLoopVar>.Create(True);
  FStrPool := TObjectList<TPooledLoopVar>.Create(True);
  FLock := TCriticalSection.Create;
  FStats.Reset;
  
  // 预热：循环常�?16 个整数和 8 个字符串
  for var I := 0 to 15 do
  begin
    var V := TPooledLoopVar.Create;
    V.FPooled := True;
    FIntPool.Add(V);
  end;
  for var I := 0 to 7 do
  begin
    var V := TPooledLoopVar.Create;
    V.FPooled := True;
    FStrPool.Add(V);
  end;
  FStats.CurrentPoolSize := FIntPool.Count + FStrPool.Count;
  FStats.TotalCreated := FStats.CurrentPoolSize;
end;

destructor TVariableValuePool.Destroy;
begin
  FIntPool.Free;
  FStrPool.Free;
  FLock.Free;
  inherited;
end;

function TVariableValuePool.AcquireInt(AValue: Int64): TPooledLoopVar;
begin
  FLock.Enter;
  try
    Inc(FStats.TotalAcquired);
    
    if FIntPool.Count > 0 then
    begin
      FIntPool.OwnsObjects := False;
      Result := FIntPool.Last;
      FIntPool.Delete(FIntPool.Count - 1);
      FIntPool.OwnsObjects := True;
    end
    else
    begin
      Result := TPooledLoopVar.Create;
      Result.FPooled := True;
      Inc(FStats.TotalCreated);
    end;
    
    Result.SetInt(AValue);
    Inc(FStats.CurrentInUse);
    if FStats.CurrentInUse > FStats.PeakInUse then
      FStats.PeakInUse := FStats.CurrentInUse;
    FStats.CurrentPoolSize := FIntPool.Count + FStrPool.Count;
  finally
    FLock.Leave;
  end;
end;

function TVariableValuePool.AcquireStr(const AValue: string): TPooledLoopVar;
begin
  FLock.Enter;
  try
    Inc(FStats.TotalAcquired);
    
    if FStrPool.Count > 0 then
    begin
      FStrPool.OwnsObjects := False;
      Result := FStrPool.Last;
      FStrPool.Delete(FStrPool.Count - 1);
      FStrPool.OwnsObjects := True;
    end
    else
    begin
      Result := TPooledLoopVar.Create;
      Result.FPooled := True;
      Inc(FStats.TotalCreated);
    end;
    
    Result.SetStr(AValue);
    Inc(FStats.CurrentInUse);
    if FStats.CurrentInUse > FStats.PeakInUse then
      FStats.PeakInUse := FStats.CurrentInUse;
    FStats.CurrentPoolSize := FIntPool.Count + FStrPool.Count;
  finally
    FLock.Leave;
  end;
end;

function TVariableValuePool.AcquireJson(AValue: TJSONValue): TPooledLoopVar;
begin
  FLock.Enter;
  try
    Inc(FStats.TotalAcquired);
    
    // JSON 使用字符串池
    if FStrPool.Count > 0 then
    begin
      FStrPool.OwnsObjects := False;
      Result := FStrPool.Last;
      FStrPool.Delete(FStrPool.Count - 1);
      FStrPool.OwnsObjects := True;
    end
    else
    begin
      Result := TPooledLoopVar.Create;
      Result.FPooled := True;
      Inc(FStats.TotalCreated);
    end;
    
    Result.SetJson(AValue);
    Inc(FStats.CurrentInUse);
    if FStats.CurrentInUse > FStats.PeakInUse then
      FStats.PeakInUse := FStats.CurrentInUse;
    FStats.CurrentPoolSize := FIntPool.Count + FStrPool.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TVariableValuePool.Release(AValue: TPooledLoopVar);
begin
  if (AValue = nil) or (not AValue.FPooled) then
  begin
    AValue.Free;  // 非池化对象直接释�?
    Exit;
  end;
  
  FLock.Enter;
  try
    Inc(FStats.TotalReleased);
    Dec(FStats.CurrentInUse);
    Inc(FStats.TotalReset);
    
    // 按原类型放回对应�?
    if AValue.FValueType = 'integer' then
    begin
      AValue.Reset;
      FIntPool.Add(AValue);
    end
    else
    begin
      AValue.Reset;
      FStrPool.Add(AValue);
    end;
    
    FStats.CurrentPoolSize := FIntPool.Count + FStrPool.Count;
  finally
    FLock.Leave;
  end;
end;

function TVariableValuePool.GetStats: TPoolStats;
begin
  FLock.Enter;
  try
    if FStats.TotalAcquired > 0 then
      FStats.HitRate := (FStats.TotalAcquired - FStats.TotalCreated) / FStats.TotalAcquired;
    Result := FStats;
  finally
    FLock.Leave;
  end;
end;

class function TVariableValuePool.GetInstance: TVariableValuePool;
begin
  if FInstance = nil then
  begin
    if FLock = nil then
      FLock := TCriticalSection.Create;
    FLock.Enter;
    try
      if FInstance = nil then
        FInstance := TVariableValuePool.Create;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

class procedure TVariableValuePool.ReleaseInstance;
begin
  if FLock <> nil then
  begin
    FLock.Enter;
    try
      FreeAndNil(FInstance);
    finally
      FLock.Leave;
    end;
    FreeAndNil(FLock);
  end;
end;

initialization

finalization
  TJSONObjectPool.ReleaseInstance;
  TStringBuilderPool.ReleaseInstance;
  TStringListPool.ReleaseInstance;
  TVariableValuePool.ReleaseInstance;
  TPoolManager.ReleaseInstance;

end.
