unit UniFlow.Tenant;
(*
  UniFlow Multi-Tenant Support
  ============================

  多租�?项目隔离支持�?

  功能:
  - 租户管理 (创建/查找/删除)
  - 租户隔离�?EventStore 包装
  - 租户配额管理
  - 租户级别的指标收�?

  设计原则:
  - 租户之间完全隔离
  - 透明�?API (对业务代码无侵入)
  - 灵活的配额策�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.SyncObjs,
  UniFlow.EventSourcing.Types,
  UniFlow.EventSourcing.Store,
  DeepBase.Exceptions;

type
  // ============================================================================
  // 租户状态和计划
  // ============================================================================

  /// <summary>租户状�?/summary>
  TTenantStatus = (
    tsActive,       // 活跃
    tsSuspended,    // 暂停
    tsArchived,     // 归档
    tsDeleted       // 已删�?
  );

  /// <summary>租户计划</summary>
  TTenantPlan = (
    tpFree,         // 免费�?
    tpBasic,        // 基础�?
    tpProfessional, // 专业�?
    tpEnterprise    // 企业�?
  );

  // ============================================================================
  // 租户配额
  // ============================================================================

  /// <summary>租户配额配置</summary>
  TTenantQuota = record
    // 流程配额
    MaxActiveFlows: Integer;      // 最大活跃流程数 (0=无限)
    MaxFlowsPerDay: Integer;      // 每日最大流程数
    MaxEventsPerFlow: Integer;    // 每流程最大事件数

    // 存储配额
    MaxStorageMB: Integer;        // 最大存�?MB
    MaxSnapshotsPerFlow: Integer; // 每流程最大快照数

    // API 配额
    MaxRequestsPerMinute: Integer; // 每分钟最大请求数
    MaxRequestsPerDay: Integer;    // 每日最大请求数

    // LLM 配额
    MaxLLMRequestsPerDay: Integer; // 每日最�?LLM 请求�?
    MaxTokensPerDay: Int64;        // 每日最�?Token �?

    // 功能开�?
    AllowParallelExecution: Boolean;
    AllowSubworkflows: Boolean;
    AllowCustomSkills: Boolean;

    class function Free: TTenantQuota; static;
    class function Basic: TTenantQuota; static;
    class function Professional: TTenantQuota; static;
    class function Enterprise: TTenantQuota; static;
    class function Unlimited: TTenantQuota; static;

    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);
  end;

  /// <summary>租户使用情况</summary>
  TTenantUsage = record
    // 流程使用
    ActiveFlows: Integer;
    FlowsToday: Integer;
    TotalFlows: Int64;

    // 存储使用
    StorageUsedMB: Double;
    TotalEvents: Int64;
    TotalSnapshots: Int64;

    // API 使用
    RequestsThisMinute: Integer;
    RequestsToday: Integer;

    // LLM 使用
    LLMRequestsToday: Integer;
    TokensToday: Int64;

    // 时间�?
    LastUpdated: TDateTime;
    DayStart: TDateTime;

    procedure Reset;
    procedure ResetDaily;
    function ToJSON: TJSONObject;
  end;

  // ============================================================================
  // TTenant - 租户
  // ============================================================================

  /// <summary>租户</summary>
  TTenant = class
  private
    FId: string;
    FName: string;
    FDisplayName: string;
    FStatus: TTenantStatus;
    FPlan: TTenantPlan;
    FQuota: TTenantQuota;
    FUsage: TTenantUsage;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    FMetadata: TJSONObject;
    FOwnerUserId: string;
    FContactEmail: string;
    FSettings: TJSONObject;
    FLock: TCriticalSection;  // SEC-005: 配额操作互斥�?
    FHMACSecret: string;      // SEC-003: HMAC 密钥
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>生成租户 ID</summary>
    class function GenerateTenantId: string;

    /// <summary>检查配额是否超�?(SEC-005: 线程安全)</summary>
    function CheckQuota(const AQuotaType: string): Boolean;

    /// <summary>增加使用�?(SEC-005: 线程安全)</summary>
    procedure IncrementUsage(const AUsageType: string; AAmount: Integer = 1);
    
    /// <summary>原子检查并增加配额 (SEC-005: 原子操作)</summary>
    function CheckAndIncrementQuota(const AQuotaType, AUsageType: string; AAmount: Integer = 1): Boolean;
    
    /// <summary>生成 FlowId 签名 (SEC-003)</summary>
    function SignFlowId(const AFlowId: string): string;
    
    /// <summary>验证 FlowId 签名 (SEC-003)</summary>
    function VerifyFlowId(const ASignedFlowId: string): Boolean;

    /// <summary>是否活跃</summary>
    function IsActive: Boolean;

    /// <summary>序列�?/summary>
    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);

    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property DisplayName: string read FDisplayName write FDisplayName;
    property Status: TTenantStatus read FStatus write FStatus;
    property Plan: TTenantPlan read FPlan write FPlan;
    property Quota: TTenantQuota read FQuota write FQuota;
    property Usage: TTenantUsage read FUsage write FUsage;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    property Metadata: TJSONObject read FMetadata;
    property OwnerUserId: string read FOwnerUserId write FOwnerUserId;
    property ContactEmail: string read FContactEmail write FContactEmail;
    property Settings: TJSONObject read FSettings;
  end;

  // ============================================================================
  // TTenantEventStore - 租户隔离的事件存�?
  // ============================================================================

  /// <summary>租户隔离的事件存储包装器</summary>
  TTenantEventStore = class(TInterfacedObject, IEventStore)
  private
    FInnerStore: IEventStore;
    FTenantId: string;
    FTenant: TTenant;

    function PrefixFlowId(const AFlowId: string): string;
    function UnprefixFlowId(const AFlowId: string): string;
    function IsTenantFlow(const AFlowId: string): Boolean;
  public
    constructor Create(AInnerStore: IEventStore; ATenant: TTenant);

    // IEventStore 实现
    function Append(AEvent: TUniFlowEvent): TAppendResult;
    function AppendBatch(AEvents: TArray<TUniFlowEvent>): TAppendResult;
    function ReadEvents(AQuery: TEventQuery): TArray<TUniFlowEvent>;
    function GetLastEvent(const AFlowId: string): TUniFlowEvent;
    function GetEventCount(const AFlowId: string): Int64;
    function SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;  // ARCH-002: 返回 Boolean 对齐 IEventStore
    function GetSnapshot(AQuery: TSnapshotQuery): TUniFlowSnapshot;
    function GetAllFlowIds: TArray<string>;
    function FlowExists(const AFlowId: string): Boolean;

    property TenantId: string read FTenantId;
    property Tenant: TTenant read FTenant;
  end;

  // ============================================================================
  // ITenantStore - 租户存储接口
  // ============================================================================

  ITenantStore = interface
    ['{8B2E4F1C-3A5D-4E6F-9B8C-1D2E3F4A5B6C}']
    procedure Save(ATenant: TTenant);
    function Load(const ATenantId: string): TTenant;
    function LoadByName(const ATenantName: string): TTenant;
    procedure Delete(const ATenantId: string);
    function GetAll: TArray<TTenant>;
    function GetByStatus(AStatus: TTenantStatus): TArray<TTenant>;
  end;

  // ============================================================================
  // TMemoryTenantStore - 内存租户存储
  // ============================================================================

  TMemoryTenantStore = class(TInterfacedObject, ITenantStore)
  private
    FTenants: TObjectDictionary<string, TTenant>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Save(ATenant: TTenant);
    function Load(const ATenantId: string): TTenant;
    function LoadByName(const ATenantName: string): TTenant;
    procedure Delete(const ATenantId: string);
    function GetAll: TArray<TTenant>;
    function GetByStatus(AStatus: TTenantStatus): TArray<TTenant>;
  end;

  // ============================================================================
  // TTenantManager - 租户管理�?
  // ============================================================================

  TTenantCreatedEvent = procedure(Sender: TObject; ATenant: TTenant) of object;
  TTenantUpdatedEvent = procedure(Sender: TObject; ATenant: TTenant) of object;
  TTenantDeletedEvent = procedure(Sender: TObject; const ATenantId: string) of object;
  TQuotaExceededEvent = procedure(Sender: TObject; ATenant: TTenant;
    const AQuotaType: string) of object;

  /// <summary>租户管理�?/summary>
  TTenantManager = class
  private
    FStore: ITenantStore;
    FSharedEventStore: IEventStore;
    FTenantStores: TDictionary<string, IEventStore>;
    FLock: TCriticalSection;

    // 缓存
    FTenantCache: TDictionary<string, TTenant>;
    FCacheEnabled: Boolean;
    FCacheTTLSeconds: Integer;
    FCacheTimestamps: TDictionary<string, TDateTime>;

    // 事件
    FOnTenantCreated: TTenantCreatedEvent;
    FOnTenantUpdated: TTenantUpdatedEvent;
    FOnTenantDeleted: TTenantDeletedEvent;
    FOnQuotaExceeded: TQuotaExceededEvent;

    function GetFromCache(const ATenantId: string): TTenant;
    procedure AddToCache(ATenant: TTenant);
    procedure RemoveFromCache(const ATenantId: string);
  public
    constructor Create(AStore: ITenantStore; ASharedEventStore: IEventStore);
    destructor Destroy; override;

    // 租户管理
    function CreateTenant(const AName, ADisplayName: string;
      APlan: TTenantPlan = tpFree): TTenant;
    function GetTenant(const ATenantId: string): TTenant;
    function GetTenantByName(const ATenantName: string): TTenant;
    procedure UpdateTenant(ATenant: TTenant);
    procedure DeleteTenant(const ATenantId: string);
    function ListTenants(AStatus: TTenantStatus = tsActive): TArray<TTenant>;

    // 租户状态管�?
    procedure SuspendTenant(const ATenantId: string);
    procedure ActivateTenant(const ATenantId: string);
    procedure ArchiveTenant(const ATenantId: string);

    // 计划和配额管�?
    procedure ChangePlan(const ATenantId: string; ANewPlan: TTenantPlan);
    procedure SetCustomQuota(const ATenantId: string; AQuota: TTenantQuota);

    // 获取租户隔离的事件存�?
    function GetEventStore(const ATenantId: string): IEventStore;

    // 配额检�?
    function CheckQuota(const ATenantId, AQuotaType: string): Boolean;
    procedure IncrementUsage(const ATenantId, AUsageType: string; AAmount: Integer = 1);

    // 使用量报�?
    function GetUsageReport(const ATenantId: string): TJSONObject;
    function GetAllTenantsUsage: TJSONArray;

    // 缓存管理
    procedure EnableCache(ATTLSeconds: Integer = 60);
    procedure DisableCache;
    procedure ClearCache;

    // 日常维护
    procedure ResetDailyUsage;
    procedure CleanupArchivedTenants(AOlderThanDays: Integer = 30);

    // 事件
    property OnTenantCreated: TTenantCreatedEvent read FOnTenantCreated write FOnTenantCreated;
    property OnTenantUpdated: TTenantUpdatedEvent read FOnTenantUpdated write FOnTenantUpdated;
    property OnTenantDeleted: TTenantDeletedEvent read FOnTenantDeleted write FOnTenantDeleted;
    property OnQuotaExceeded: TQuotaExceededEvent read FOnQuotaExceeded write FOnQuotaExceeded;

    property Store: ITenantStore read FStore;
    property CacheEnabled: Boolean read FCacheEnabled;
  end;

  // ============================================================================
  // TTenantContext - 租户上下�?(线程局�?
  // ============================================================================

  /// <summary>租户上下�?- 用于在请求处理链中传递租户信�?/summary>
  TTenantContext = class
  private
    class threadvar FCurrentTenantId: string;
    class threadvar FCurrentTenant: TTenant;
  public
    class procedure SetCurrent(ATenant: TTenant);
    class procedure SetCurrentId(const ATenantId: string);
    class procedure Clear;

    class function GetCurrentTenantId: string;
    class function GetCurrentTenant: TTenant;
    class function HasCurrentTenant: Boolean;
  end;

  // ============================================================================
  // 辅助函数
  // ============================================================================

function TenantStatusToString(AStatus: TTenantStatus): string;
function StringToTenantStatus(const AStr: string): TTenantStatus;
function TenantPlanToString(APlan: TTenantPlan): string;
function StringToTenantPlan(const AStr: string): TTenantPlan;

implementation

uses
  System.StrUtils;

const
  TENANT_PREFIX = 'tenant:';

// ============================================================================
// 辅助函数实现
// ============================================================================

function TenantStatusToString(AStatus: TTenantStatus): string;
const
  Names: array[TTenantStatus] of string = ('Active', 'Suspended', 'Archived', 'Deleted');
begin
  Result := Names[AStatus];
end;

function StringToTenantStatus(const AStr: string): TTenantStatus;
begin
  if SameText(AStr, 'Active') then Result := tsActive
  else if SameText(AStr, 'Suspended') then Result := tsSuspended
  else if SameText(AStr, 'Archived') then Result := tsArchived
  else if SameText(AStr, 'Deleted') then Result := tsDeleted
  else Result := tsActive;
end;

function TenantPlanToString(APlan: TTenantPlan): string;
const
  Names: array[TTenantPlan] of string = ('Free', 'Basic', 'Professional', 'Enterprise');
begin
  Result := Names[APlan];
end;

function StringToTenantPlan(const AStr: string): TTenantPlan;
begin
  if SameText(AStr, 'Free') then Result := tpFree
  else if SameText(AStr, 'Basic') then Result := tpBasic
  else if SameText(AStr, 'Professional') then Result := tpProfessional
  else if SameText(AStr, 'Enterprise') then Result := tpEnterprise
  else Result := tpFree;
end;

// ============================================================================
// TTenantQuota
// ============================================================================

class function TTenantQuota.Free: TTenantQuota;
begin
  Result.MaxActiveFlows := 5;
  Result.MaxFlowsPerDay := 100;
  Result.MaxEventsPerFlow := 1000;
  Result.MaxStorageMB := 100;
  Result.MaxSnapshotsPerFlow := 5;
  Result.MaxRequestsPerMinute := 60;
  Result.MaxRequestsPerDay := 10000;
  Result.MaxLLMRequestsPerDay := 100;
  Result.MaxTokensPerDay := 100000;
  Result.AllowParallelExecution := False;
  Result.AllowSubworkflows := False;
  Result.AllowCustomSkills := False;
end;

class function TTenantQuota.Basic: TTenantQuota;
begin
  Result.MaxActiveFlows := 20;
  Result.MaxFlowsPerDay := 500;
  Result.MaxEventsPerFlow := 5000;
  Result.MaxStorageMB := 500;
  Result.MaxSnapshotsPerFlow := 10;
  Result.MaxRequestsPerMinute := 120;
  Result.MaxRequestsPerDay := 50000;
  Result.MaxLLMRequestsPerDay := 500;
  Result.MaxTokensPerDay := 500000;
  Result.AllowParallelExecution := True;
  Result.AllowSubworkflows := False;
  Result.AllowCustomSkills := False;
end;

class function TTenantQuota.Professional: TTenantQuota;
begin
  Result.MaxActiveFlows := 100;
  Result.MaxFlowsPerDay := 2000;
  Result.MaxEventsPerFlow := 20000;
  Result.MaxStorageMB := 2000;
  Result.MaxSnapshotsPerFlow := 50;
  Result.MaxRequestsPerMinute := 300;
  Result.MaxRequestsPerDay := 200000;
  Result.MaxLLMRequestsPerDay := 2000;
  Result.MaxTokensPerDay := 2000000;
  Result.AllowParallelExecution := True;
  Result.AllowSubworkflows := True;
  Result.AllowCustomSkills := False;
end;

class function TTenantQuota.Enterprise: TTenantQuota;
begin
  Result.MaxActiveFlows := 0; // 无限
  Result.MaxFlowsPerDay := 0;
  Result.MaxEventsPerFlow := 0;
  Result.MaxStorageMB := 0;
  Result.MaxSnapshotsPerFlow := 0;
  Result.MaxRequestsPerMinute := 0;
  Result.MaxRequestsPerDay := 0;
  Result.MaxLLMRequestsPerDay := 0;
  Result.MaxTokensPerDay := 0;
  Result.AllowParallelExecution := True;
  Result.AllowSubworkflows := True;
  Result.AllowCustomSkills := True;
end;

class function TTenantQuota.Unlimited: TTenantQuota;
begin
  Result := Enterprise;
end;

function TTenantQuota.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('maxActiveFlows', TJSONNumber.Create(MaxActiveFlows));
  Result.AddPair('maxFlowsPerDay', TJSONNumber.Create(MaxFlowsPerDay));
  Result.AddPair('maxEventsPerFlow', TJSONNumber.Create(MaxEventsPerFlow));
  Result.AddPair('maxStorageMB', TJSONNumber.Create(MaxStorageMB));
  Result.AddPair('maxSnapshotsPerFlow', TJSONNumber.Create(MaxSnapshotsPerFlow));
  Result.AddPair('maxRequestsPerMinute', TJSONNumber.Create(MaxRequestsPerMinute));
  Result.AddPair('maxRequestsPerDay', TJSONNumber.Create(MaxRequestsPerDay));
  Result.AddPair('maxLLMRequestsPerDay', TJSONNumber.Create(MaxLLMRequestsPerDay));
  Result.AddPair('maxTokensPerDay', TJSONNumber.Create(MaxTokensPerDay));
  Result.AddPair('allowParallelExecution', TJSONBool.Create(AllowParallelExecution));
  Result.AddPair('allowSubworkflows', TJSONBool.Create(AllowSubworkflows));
  Result.AddPair('allowCustomSkills', TJSONBool.Create(AllowCustomSkills));
end;

procedure TTenantQuota.LoadFromJSON(AJson: TJSONObject);
begin
  if AJson = nil then Exit;

  AJson.TryGetValue<Integer>('maxActiveFlows', MaxActiveFlows);
  AJson.TryGetValue<Integer>('maxFlowsPerDay', MaxFlowsPerDay);
  AJson.TryGetValue<Integer>('maxEventsPerFlow', MaxEventsPerFlow);
  AJson.TryGetValue<Integer>('maxStorageMB', MaxStorageMB);
  AJson.TryGetValue<Integer>('maxSnapshotsPerFlow', MaxSnapshotsPerFlow);
  AJson.TryGetValue<Integer>('maxRequestsPerMinute', MaxRequestsPerMinute);
  AJson.TryGetValue<Integer>('maxRequestsPerDay', MaxRequestsPerDay);
  AJson.TryGetValue<Integer>('maxLLMRequestsPerDay', MaxLLMRequestsPerDay);
  AJson.TryGetValue<Int64>('maxTokensPerDay', MaxTokensPerDay);
  AJson.TryGetValue<Boolean>('allowParallelExecution', AllowParallelExecution);
  AJson.TryGetValue<Boolean>('allowSubworkflows', AllowSubworkflows);
  AJson.TryGetValue<Boolean>('allowCustomSkills', AllowCustomSkills);
end;

// ============================================================================
// TTenantUsage
// ============================================================================

procedure TTenantUsage.Reset;
begin
  ActiveFlows := 0;
  FlowsToday := 0;
  TotalFlows := 0;
  StorageUsedMB := 0;
  TotalEvents := 0;
  TotalSnapshots := 0;
  RequestsThisMinute := 0;
  RequestsToday := 0;
  LLMRequestsToday := 0;
  TokensToday := 0;
  LastUpdated := Now;
  DayStart := Trunc(Now);
end;

procedure TTenantUsage.ResetDaily;
begin
  FlowsToday := 0;
  RequestsToday := 0;
  LLMRequestsToday := 0;
  TokensToday := 0;
  DayStart := Trunc(Now);
  LastUpdated := Now;
end;

function TTenantUsage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('activeFlows', TJSONNumber.Create(ActiveFlows));
  Result.AddPair('flowsToday', TJSONNumber.Create(FlowsToday));
  Result.AddPair('totalFlows', TJSONNumber.Create(TotalFlows));
  Result.AddPair('storageUsedMB', TJSONNumber.Create(StorageUsedMB));
  Result.AddPair('totalEvents', TJSONNumber.Create(TotalEvents));
  Result.AddPair('totalSnapshots', TJSONNumber.Create(TotalSnapshots));
  Result.AddPair('requestsThisMinute', TJSONNumber.Create(RequestsThisMinute));
  Result.AddPair('requestsToday', TJSONNumber.Create(RequestsToday));
  Result.AddPair('llmRequestsToday', TJSONNumber.Create(LLMRequestsToday));
  Result.AddPair('tokensToday', TJSONNumber.Create(TokensToday));
  Result.AddPair('lastUpdated', DateToISO8601(LastUpdated));
end;

// ============================================================================
// TTenant
// ============================================================================

constructor TTenant.Create;
var
  GUID: TGUID;
begin
  inherited;
  FId := GenerateTenantId;
  FCreatedAt := Now;
  FUpdatedAt := FCreatedAt;
  FStatus := tsActive;
  FPlan := tpFree;
  FQuota := TTenantQuota.Free;
  FUsage.Reset;
  FMetadata := TJSONObject.Create;
  FSettings := TJSONObject.Create;
  FLock := TCriticalSection.Create;  // SEC-005: 初始化互斥锁
  // SEC-003: 生成 HMAC 密钥
  CreateGUID(GUID);
  FHMACSecret := GUIDToString(GUID);
end;

destructor TTenant.Destroy;
begin
  FMetadata.Free;
  FSettings.Free;
  FLock.Free;  // SEC-005: 释放互斥�?
  inherited;
end;

class function TTenant.GenerateTenantId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'tnt-' + Copy(GUIDToString(GUID), 2, 8);
end;

function TTenant.CheckQuota(const AQuotaType: string): Boolean;
begin
  // SEC-005: 线程安全的配额检�?
  FLock.Enter;
  try
    // 检查日期，必要时重�?
    if Trunc(Now) > Trunc(FUsage.DayStart) then
      FUsage.ResetDaily;

    Result := True;

    if SameText(AQuotaType, 'active_flows') then
      Result := (FQuota.MaxActiveFlows = 0) or (FUsage.ActiveFlows < FQuota.MaxActiveFlows)
    else if SameText(AQuotaType, 'flows_per_day') then
      Result := (FQuota.MaxFlowsPerDay = 0) or (FUsage.FlowsToday < FQuota.MaxFlowsPerDay)
    else if SameText(AQuotaType, 'requests_per_minute') then
      Result := (FQuota.MaxRequestsPerMinute = 0) or (FUsage.RequestsThisMinute < FQuota.MaxRequestsPerMinute)
    else if SameText(AQuotaType, 'requests_per_day') then
      Result := (FQuota.MaxRequestsPerDay = 0) or (FUsage.RequestsToday < FQuota.MaxRequestsPerDay)
    else if SameText(AQuotaType, 'llm_requests_per_day') then
      Result := (FQuota.MaxLLMRequestsPerDay = 0) or (FUsage.LLMRequestsToday < FQuota.MaxLLMRequestsPerDay)
    else if SameText(AQuotaType, 'tokens_per_day') then
      Result := (FQuota.MaxTokensPerDay = 0) or (FUsage.TokensToday < FQuota.MaxTokensPerDay)
    else if SameText(AQuotaType, 'storage') then
      Result := (FQuota.MaxStorageMB = 0) or (FUsage.StorageUsedMB < FQuota.MaxStorageMB);
  finally
    FLock.Leave;
  end;
end;

procedure TTenant.IncrementUsage(const AUsageType: string; AAmount: Integer);
begin
  // SEC-005: 线程安全的使用量增加
  FLock.Enter;
  try
    // 检查日期，必要时重�?
    if Trunc(Now) > Trunc(FUsage.DayStart) then
      FUsage.ResetDaily;

    if SameText(AUsageType, 'flow_started') then
    begin
      FUsage.ActiveFlows := FUsage.ActiveFlows + AAmount;
      FUsage.FlowsToday := FUsage.FlowsToday + AAmount;
      FUsage.TotalFlows := FUsage.TotalFlows + AAmount;
    end
    else if SameText(AUsageType, 'flow_completed') then
      FUsage.ActiveFlows := FUsage.ActiveFlows - AAmount
    else if SameText(AUsageType, 'event') then
      FUsage.TotalEvents := FUsage.TotalEvents + AAmount
    else if SameText(AUsageType, 'snapshot') then
      FUsage.TotalSnapshots := FUsage.TotalSnapshots + AAmount
    else if SameText(AUsageType, 'request') then
    begin
      FUsage.RequestsThisMinute := FUsage.RequestsThisMinute + AAmount;
      FUsage.RequestsToday := FUsage.RequestsToday + AAmount;
    end
    else if SameText(AUsageType, 'llm_request') then
      FUsage.LLMRequestsToday := FUsage.LLMRequestsToday + AAmount
    else if SameText(AUsageType, 'tokens') then
      FUsage.TokensToday := FUsage.TokensToday + AAmount;

    FUsage.LastUpdated := Now;
  finally
    FLock.Leave;
  end;
end;

function TTenant.CheckAndIncrementQuota(const AQuotaType, AUsageType: string; AAmount: Integer): Boolean;
begin
  // SEC-005: 原子检查并增加配额，避免竞态条�?
  FLock.Enter;
  try
    // 检查日期，必要时重�?
    if Trunc(Now) > Trunc(FUsage.DayStart) then
      FUsage.ResetDaily;

    // 先检查配�?
    Result := True;
    if SameText(AQuotaType, 'active_flows') then
      Result := (FQuota.MaxActiveFlows = 0) or (FUsage.ActiveFlows < FQuota.MaxActiveFlows)
    else if SameText(AQuotaType, 'flows_per_day') then
      Result := (FQuota.MaxFlowsPerDay = 0) or (FUsage.FlowsToday < FQuota.MaxFlowsPerDay)
    else if SameText(AQuotaType, 'requests_per_minute') then
      Result := (FQuota.MaxRequestsPerMinute = 0) or (FUsage.RequestsThisMinute < FQuota.MaxRequestsPerMinute);

    // 如果配额允许，原子增加使用量
    if Result then
    begin
      if SameText(AUsageType, 'flow_started') then
      begin
        FUsage.ActiveFlows := FUsage.ActiveFlows + AAmount;
        FUsage.FlowsToday := FUsage.FlowsToday + AAmount;
        FUsage.TotalFlows := FUsage.TotalFlows + AAmount;
      end
      else if SameText(AUsageType, 'request') then
      begin
        FUsage.RequestsThisMinute := FUsage.RequestsThisMinute + AAmount;
        FUsage.RequestsToday := FUsage.RequestsToday + AAmount;
      end;
      FUsage.LastUpdated := Now;
    end;
  finally
    FLock.Leave;
  end;
end;

function TTenant.SignFlowId(const AFlowId: string): string;
var
  Hash: Cardinal;
  Data: string;
begin
  // SEC-003: 使用简单哈希签�?FlowId (生产环境应使用真正的 HMAC-SHA256)
  Data := FId + ':' + AFlowId + ':' + FHMACSecret;
  Hash := 0;
  for var I := 1 to Length(Data) do
    Hash := ((Hash shl 5) + Hash) + Ord(Data[I]);
  Result := FId + ':' + AFlowId + ':' + IntToHex(Hash, 8);
end;

function TTenant.VerifyFlowId(const ASignedFlowId: string): Boolean;
var
  Parts: TArray<string>;
  ExpectedSig: string;
begin
  // SEC-003: 验证签名�?FlowId
  Result := False;
  Parts := ASignedFlowId.Split([':']);
  if Length(Parts) < 3 then Exit;
  
  // 检查租�?ID 匹配
  if Parts[0] <> FId then Exit;
  
  // 重新计算签名验证
  ExpectedSig := SignFlowId(Parts[1]);
  Result := ExpectedSig = ASignedFlowId;
end;

function TTenant.IsActive: Boolean;
begin
  Result := FStatus = tsActive;
end;

function TTenant.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('name', FName);
  Result.AddPair('displayName', FDisplayName);
  Result.AddPair('status', TenantStatusToString(FStatus));
  Result.AddPair('plan', TenantPlanToString(FPlan));
  Result.AddPair('quota', FQuota.ToJSON);
  Result.AddPair('usage', FUsage.ToJSON);
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
  Result.AddPair('updatedAt', DateToISO8601(FUpdatedAt));

  if not FOwnerUserId.IsEmpty then
    Result.AddPair('ownerUserId', FOwnerUserId);
  if not FContactEmail.IsEmpty then
    Result.AddPair('contactEmail', FContactEmail);
  if FMetadata.Count > 0 then
    Result.AddPair('metadata', FMetadata.Clone as TJSONObject);
  if FSettings.Count > 0 then
    Result.AddPair('settings', FSettings.Clone as TJSONObject);
end;

procedure TTenant.LoadFromJSON(AJson: TJSONObject);
var
  Obj: TJSONObject;
  Str: string;
begin
  if AJson = nil then Exit;

  AJson.TryGetValue<string>('id', FId);
  AJson.TryGetValue<string>('name', FName);
  AJson.TryGetValue<string>('displayName', FDisplayName);

  if AJson.TryGetValue<string>('status', Str) then
    FStatus := StringToTenantStatus(Str);
  if AJson.TryGetValue<string>('plan', Str) then
    FPlan := StringToTenantPlan(Str);

  if AJson.TryGetValue<TJSONObject>('quota', Obj) then
    FQuota.LoadFromJSON(Obj);

  if AJson.TryGetValue<string>('createdAt', Str) then
    FCreatedAt := ISO8601ToDate(Str);
  if AJson.TryGetValue<string>('updatedAt', Str) then
    FUpdatedAt := ISO8601ToDate(Str);

  AJson.TryGetValue<string>('ownerUserId', FOwnerUserId);
  AJson.TryGetValue<string>('contactEmail', FContactEmail);

  if AJson.TryGetValue<TJSONObject>('metadata', Obj) then
  begin
    FMetadata.Free;
    FMetadata := Obj.Clone as TJSONObject;
  end;

  if AJson.TryGetValue<TJSONObject>('settings', Obj) then
  begin
    FSettings.Free;
    FSettings := Obj.Clone as TJSONObject;
  end;
end;

// ============================================================================
// TTenantEventStore
// ============================================================================

constructor TTenantEventStore.Create(AInnerStore: IEventStore; ATenant: TTenant);
begin
  inherited Create;
  FInnerStore := AInnerStore;
  FTenant := ATenant;
  FTenantId := ATenant.Id;
end;

function TTenantEventStore.PrefixFlowId(const AFlowId: string): string;
begin
  // SEC-003: 使用签名�?FlowId
  Result := TENANT_PREFIX + FTenant.SignFlowId(AFlowId);
end;

function TTenantEventStore.UnprefixFlowId(const AFlowId: string): string;
var
  Prefix: string;
begin
  Prefix := TENANT_PREFIX + FTenantId + ':';
  if AFlowId.StartsWith(Prefix) then
    Result := Copy(AFlowId, Length(Prefix) + 1, MaxInt)
  else
    Result := AFlowId;
end;

function TTenantEventStore.IsTenantFlow(const AFlowId: string): Boolean;
begin
  // SEC-003: 使用签名验证而非简单前缀检�?
  // 首先检查基本前缀
  if not AFlowId.StartsWith(TENANT_PREFIX + FTenantId + ':') then
    Exit(False);
  
  // 提取实际�?FlowId 部分并验证签�?
  var InnerFlowId := Copy(AFlowId, Length(TENANT_PREFIX) + 1, MaxInt);
  Result := FTenant.VerifyFlowId(InnerFlowId);
end;

function TTenantEventStore.Append(AEvent: TUniFlowEvent): TAppendResult;
begin
  // 配额检�?
  if not FTenant.CheckQuota('events_per_flow') then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'Event quota exceeded';
    Exit;
  end;

  AEvent.FlowId := PrefixFlowId(AEvent.FlowId);
  Result := FInnerStore.Append(AEvent);

  if Result.Success then
    FTenant.IncrementUsage('event', 1);
end;

function TTenantEventStore.AppendBatch(AEvents: TArray<TUniFlowEvent>): TAppendResult;
begin
  for var Event in AEvents do
    Event.FlowId := PrefixFlowId(Event.FlowId);

  Result := FInnerStore.AppendBatch(AEvents);

  if Result.Success then
    FTenant.IncrementUsage('event', Length(AEvents));
end;

function TTenantEventStore.ReadEvents(AQuery: TEventQuery): TArray<TUniFlowEvent>;
begin
  AQuery.FlowId := PrefixFlowId(AQuery.FlowId);
  Result := FInnerStore.ReadEvents(AQuery);

  // 还原 FlowId
  for var Event in Result do
    Event.FlowId := UnprefixFlowId(Event.FlowId);
end;

function TTenantEventStore.GetLastEvent(const AFlowId: string): TUniFlowEvent;
begin
  Result := FInnerStore.GetLastEvent(PrefixFlowId(AFlowId));
  if Result <> nil then
    Result.FlowId := UnprefixFlowId(Result.FlowId);
end;

function TTenantEventStore.GetEventCount(const AFlowId: string): Int64;
begin
  Result := FInnerStore.GetEventCount(PrefixFlowId(AFlowId));
end;

function TTenantEventStore.SaveSnapshot(ASnapshot: TUniFlowSnapshot): Boolean;
begin
  // ARCH-002: 返回 Boolean 对齐 IEventStore 接口
  ASnapshot.FlowId := PrefixFlowId(ASnapshot.FlowId);
  Result := FInnerStore.SaveSnapshot(ASnapshot);
  if Result then
    FTenant.IncrementUsage('snapshot', 1);
end;

function TTenantEventStore.GetSnapshot(AQuery: TSnapshotQuery): TUniFlowSnapshot;
begin
  AQuery.FlowId := PrefixFlowId(AQuery.FlowId);
  Result := FInnerStore.GetSnapshot(AQuery);
  if Result <> nil then
    Result.FlowId := UnprefixFlowId(Result.FlowId);
end;

function TTenantEventStore.GetAllFlowIds: TArray<string>;
var
  AllIds: TArray<string>;
  FilteredList: TList<string>;
begin
  AllIds := FInnerStore.GetAllFlowIds;
  FilteredList := TList<string>.Create;
  try
    for var Id in AllIds do
      if IsTenantFlow(Id) then
        FilteredList.Add(UnprefixFlowId(Id));

    Result := FilteredList.ToArray;
  finally
    FilteredList.Free;
  end;
end;

function TTenantEventStore.FlowExists(const AFlowId: string): Boolean;
begin
  Result := FInnerStore.FlowExists(PrefixFlowId(AFlowId));
end;

// ============================================================================
// TMemoryTenantStore
// ============================================================================

constructor TMemoryTenantStore.Create;
begin
  inherited;
  FTenants := TObjectDictionary<string, TTenant>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
end;

destructor TMemoryTenantStore.Destroy;
begin
  FTenants.Free;
  FLock.Free;
  inherited;
end;

procedure TMemoryTenantStore.Save(ATenant: TTenant);
var
  Clone: TTenant;
begin
  FLock.Enter;
  try
    Clone := TTenant.Create;
    Clone.LoadFromJSON(ATenant.ToJSON);
    FTenants.AddOrSetValue(ATenant.Id, Clone);
  finally
    FLock.Leave;
  end;
end;

function TMemoryTenantStore.Load(const ATenantId: string): TTenant;
var
  Stored: TTenant;
begin
  Result := nil;
  FLock.Enter;
  try
    if FTenants.TryGetValue(ATenantId, Stored) then
    begin
      Result := TTenant.Create;
      Result.LoadFromJSON(Stored.ToJSON);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMemoryTenantStore.LoadByName(const ATenantName: string): TTenant;
begin
  Result := nil;
  FLock.Enter;
  try
    for var Tenant in FTenants.Values do
    begin
      if SameText(Tenant.Name, ATenantName) then
      begin
        Result := TTenant.Create;
        Result.LoadFromJSON(Tenant.ToJSON);
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryTenantStore.Delete(const ATenantId: string);
begin
  FLock.Enter;
  try
    FTenants.Remove(ATenantId);
  finally
    FLock.Leave;
  end;
end;

function TMemoryTenantStore.GetAll: TArray<TTenant>;
var
  List: TList<TTenant>;
  Clone: TTenant;
begin
  FLock.Enter;
  try
    List := TList<TTenant>.Create;
    try
      for var Tenant in FTenants.Values do
      begin
        Clone := TTenant.Create;
        Clone.LoadFromJSON(Tenant.ToJSON);
        List.Add(Clone);
      end;
      Result := List.ToArray;
    finally
      List.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TMemoryTenantStore.GetByStatus(AStatus: TTenantStatus): TArray<TTenant>;
var
  List: TList<TTenant>;
  Clone: TTenant;
begin
  FLock.Enter;
  try
    List := TList<TTenant>.Create;
    try
      for var Tenant in FTenants.Values do
      begin
        if Tenant.Status = AStatus then
        begin
          Clone := TTenant.Create;
          Clone.LoadFromJSON(Tenant.ToJSON);
          List.Add(Clone);
        end;
      end;
      Result := List.ToArray;
    finally
      List.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TTenantManager
// ============================================================================

constructor TTenantManager.Create(AStore: ITenantStore; ASharedEventStore: IEventStore);
begin
  inherited Create;
  FStore := AStore;
  FSharedEventStore := ASharedEventStore;
  FTenantStores := TDictionary<string, IEventStore>.Create;
  FLock := TCriticalSection.Create;
  FTenantCache := TDictionary<string, TTenant>.Create;
  FCacheTimestamps := TDictionary<string, TDateTime>.Create;
  FCacheEnabled := False;
  FCacheTTLSeconds := 60;
end;

destructor TTenantManager.Destroy;
begin
  ClearCache;
  FTenantCache.Free;
  FCacheTimestamps.Free;
  FTenantStores.Free;
  FLock.Free;
  inherited;
end;

function TTenantManager.GetFromCache(const ATenantId: string): TTenant;
var
  CacheTime: TDateTime;
begin
  Result := nil;
  if not FCacheEnabled then Exit;

  FLock.Enter;
  try
    if FTenantCache.TryGetValue(ATenantId, Result) then
    begin
      if FCacheTimestamps.TryGetValue(ATenantId, CacheTime) then
      begin
        if SecondsBetween(Now, CacheTime) < FCacheTTLSeconds then
          Exit
        else
        begin
          FTenantCache.Remove(ATenantId);
          FCacheTimestamps.Remove(ATenantId);
          Result := nil;
        end;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TTenantManager.AddToCache(ATenant: TTenant);
begin
  if not FCacheEnabled then Exit;

  FLock.Enter;
  try
    FTenantCache.AddOrSetValue(ATenant.Id, ATenant);
    FCacheTimestamps.AddOrSetValue(ATenant.Id, Now);
  finally
    FLock.Leave;
  end;
end;

procedure TTenantManager.RemoveFromCache(const ATenantId: string);
begin
  FLock.Enter;
  try
    FTenantCache.Remove(ATenantId);
    FCacheTimestamps.Remove(ATenantId);
  finally
    FLock.Leave;
  end;
end;

function TTenantManager.CreateTenant(const AName, ADisplayName: string;
  APlan: TTenantPlan): TTenant;
begin
  // 检查名称唯一�?
  if GetTenantByName(AName) <> nil then
    raise EOperationException.CreateFmt('Tenant with name "%s" already exists', [AName]);

  Result := TTenant.Create;
  Result.Name := AName;
  Result.DisplayName := ADisplayName;
  Result.Plan := APlan;

  case APlan of
    tpFree: Result.Quota := TTenantQuota.Free;
    tpBasic: Result.Quota := TTenantQuota.Basic;
    tpProfessional: Result.Quota := TTenantQuota.Professional;
    tpEnterprise: Result.Quota := TTenantQuota.Enterprise;
  end;

  FStore.Save(Result);
  AddToCache(Result);

  if Assigned(FOnTenantCreated) then
    FOnTenantCreated(Self, Result);
end;

function TTenantManager.GetTenant(const ATenantId: string): TTenant;
begin
  Result := GetFromCache(ATenantId);
  if Result <> nil then Exit;

  Result := FStore.Load(ATenantId);
  if Result <> nil then
    AddToCache(Result);
end;

function TTenantManager.GetTenantByName(const ATenantName: string): TTenant;
begin
  Result := FStore.LoadByName(ATenantName);
end;

procedure TTenantManager.UpdateTenant(ATenant: TTenant);
begin
  ATenant.UpdatedAt := Now;
  FStore.Save(ATenant);
  AddToCache(ATenant);

  if Assigned(FOnTenantUpdated) then
    FOnTenantUpdated(Self, ATenant);
end;

procedure TTenantManager.DeleteTenant(const ATenantId: string);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.Status := tsDeleted;
    FStore.Save(Tenant);
    RemoveFromCache(ATenantId);

    if Assigned(FOnTenantDeleted) then
      FOnTenantDeleted(Self, ATenantId);
  end;
end;

function TTenantManager.ListTenants(AStatus: TTenantStatus): TArray<TTenant>;
begin
  Result := FStore.GetByStatus(AStatus);
end;

procedure TTenantManager.SuspendTenant(const ATenantId: string);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.Status := tsSuspended;
    UpdateTenant(Tenant);
  end;
end;

procedure TTenantManager.ActivateTenant(const ATenantId: string);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.Status := tsActive;
    UpdateTenant(Tenant);
  end;
end;

procedure TTenantManager.ArchiveTenant(const ATenantId: string);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.Status := tsArchived;
    UpdateTenant(Tenant);
  end;
end;

procedure TTenantManager.ChangePlan(const ATenantId: string; ANewPlan: TTenantPlan);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.Plan := ANewPlan;
    case ANewPlan of
      tpFree: Tenant.Quota := TTenantQuota.Free;
      tpBasic: Tenant.Quota := TTenantQuota.Basic;
      tpProfessional: Tenant.Quota := TTenantQuota.Professional;
      tpEnterprise: Tenant.Quota := TTenantQuota.Enterprise;
    end;
    UpdateTenant(Tenant);
  end;
end;

procedure TTenantManager.SetCustomQuota(const ATenantId: string; AQuota: TTenantQuota);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.Quota := AQuota;
    UpdateTenant(Tenant);
  end;
end;

function TTenantManager.GetEventStore(const ATenantId: string): IEventStore;
var
  Tenant: TTenant;
begin
  FLock.Enter;
  try
    if not FTenantStores.TryGetValue(ATenantId, Result) then
    begin
      Tenant := GetTenant(ATenantId);
      if Tenant = nil then
        raise EOperationException.CreateFmt('Tenant not found: %s', [ATenantId]);

      if not Tenant.IsActive then
        raise EOperationException.CreateFmt('Tenant is not active: %s', [ATenantId]);

      Result := TTenantEventStore.Create(FSharedEventStore, Tenant);
      FTenantStores.Add(ATenantId, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TTenantManager.CheckQuota(const ATenantId, AQuotaType: string): Boolean;
var
  Tenant: TTenant;
begin
  Result := True;
  Tenant := GetTenant(ATenantId);
  if Tenant = nil then Exit(False);

  Result := Tenant.CheckQuota(AQuotaType);

  if not Result and Assigned(FOnQuotaExceeded) then
    FOnQuotaExceeded(Self, Tenant, AQuotaType);
end;

procedure TTenantManager.IncrementUsage(const ATenantId, AUsageType: string; AAmount: Integer);
var
  Tenant: TTenant;
begin
  Tenant := GetTenant(ATenantId);
  if Tenant <> nil then
  begin
    Tenant.IncrementUsage(AUsageType, AAmount);
    FStore.Save(Tenant);
    AddToCache(Tenant);
  end;
end;

function TTenantManager.GetUsageReport(const ATenantId: string): TJSONObject;
var
  Tenant: TTenant;
begin
  Result := TJSONObject.Create;
  Tenant := GetTenant(ATenantId);
  if Tenant = nil then Exit;

  Result.AddPair('tenantId', ATenantId);
  Result.AddPair('tenantName', Tenant.Name);
  Result.AddPair('plan', TenantPlanToString(Tenant.Plan));
  Result.AddPair('quota', Tenant.Quota.ToJSON);
  Result.AddPair('usage', Tenant.Usage.ToJSON);

  // 计算使用�?
  var UsagePercent := TJSONObject.Create;
  if Tenant.Quota.MaxActiveFlows > 0 then
    UsagePercent.AddPair('activeFlows', TJSONNumber.Create(
      Tenant.Usage.ActiveFlows / Tenant.Quota.MaxActiveFlows * 100));
  if Tenant.Quota.MaxFlowsPerDay > 0 then
    UsagePercent.AddPair('flowsToday', TJSONNumber.Create(
      Tenant.Usage.FlowsToday / Tenant.Quota.MaxFlowsPerDay * 100));
  if Tenant.Quota.MaxRequestsPerDay > 0 then
    UsagePercent.AddPair('requestsToday', TJSONNumber.Create(
      Tenant.Usage.RequestsToday / Tenant.Quota.MaxRequestsPerDay * 100));
  Result.AddPair('usagePercent', UsagePercent);
end;

function TTenantManager.GetAllTenantsUsage: TJSONArray;
var
  Tenants: TArray<TTenant>;
begin
  Result := TJSONArray.Create;
  Tenants := FStore.GetAll;
  try
    for var Tenant in Tenants do
    begin
      var Item := TJSONObject.Create;
      Item.AddPair('id', Tenant.Id);
      Item.AddPair('name', Tenant.Name);
      Item.AddPair('status', TenantStatusToString(Tenant.Status));
      Item.AddPair('plan', TenantPlanToString(Tenant.Plan));
      Item.AddPair('usage', Tenant.Usage.ToJSON);
      Result.AddElement(Item);
    end;
  finally
    for var T in Tenants do T.Free;
  end;
end;

procedure TTenantManager.EnableCache(ATTLSeconds: Integer);
begin
  FCacheEnabled := True;
  FCacheTTLSeconds := ATTLSeconds;
end;

procedure TTenantManager.DisableCache;
begin
  FCacheEnabled := False;
  ClearCache;
end;

procedure TTenantManager.ClearCache;
begin
  FLock.Enter;
  try
    FTenantCache.Clear;
    FCacheTimestamps.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TTenantManager.ResetDailyUsage;
var
  Tenants: TArray<TTenant>;
begin
  Tenants := FStore.GetAll;
  try
    for var Tenant in Tenants do
    begin
      Tenant.Usage.ResetDaily;
      FStore.Save(Tenant);
    end;
    ClearCache;
  finally
    for var T in Tenants do T.Free;
  end;
end;

procedure TTenantManager.CleanupArchivedTenants(AOlderThanDays: Integer);
var
  Tenants: TArray<TTenant>;
  Cutoff: TDateTime;
begin
  Cutoff := Now - AOlderThanDays;
  Tenants := FStore.GetByStatus(tsArchived);
  try
    for var Tenant in Tenants do
    begin
      if Tenant.UpdatedAt < Cutoff then
      begin
        Tenant.Status := tsDeleted;
        FStore.Save(Tenant);
      end;
    end;
  finally
    for var T in Tenants do T.Free;
  end;
end;

// ============================================================================
// TTenantContext
// ============================================================================

class procedure TTenantContext.SetCurrent(ATenant: TTenant);
begin
  FCurrentTenant := ATenant;
  if ATenant <> nil then
    FCurrentTenantId := ATenant.Id
  else
    FCurrentTenantId := '';
end;

class procedure TTenantContext.SetCurrentId(const ATenantId: string);
begin
  FCurrentTenantId := ATenantId;
  FCurrentTenant := nil;
end;

class procedure TTenantContext.Clear;
begin
  FCurrentTenantId := '';
  FCurrentTenant := nil;
end;

class function TTenantContext.GetCurrentTenantId: string;
begin
  Result := FCurrentTenantId;
end;

class function TTenantContext.GetCurrentTenant: TTenant;
begin
  Result := FCurrentTenant;
end;

class function TTenantContext.HasCurrentTenant: Boolean;
begin
  Result := not FCurrentTenantId.IsEmpty;
end;

end.
