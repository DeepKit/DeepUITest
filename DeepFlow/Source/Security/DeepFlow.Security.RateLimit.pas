(* ============================================================================
  UniFlow.Security.RateLimit - Rate Limiting and Quota Management

  Version: 1.0
  Description: Controls request rates and resource quotas

  Features:
    - Request rate limiting (sliding window)
    - Token bucket algorithm
    - Per-user/session/global limits
    - Token quota management
    - Multiple policy support

  Usage:
    var Limiter := TRateLimiter.Create;
    Limiter.AddPolicy('default', 100, 60);  // 100 requests per 60 seconds
    if Limiter.TryAcquire('user_123') then
      // Process request
    else
      // Rate limited
  ============================================================================ *)

unit UniFlow.Security.RateLimit;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Math,
  System.Generics.Collections,
  System.SyncObjs,
  System.DateUtils;

type
  // ============================================================================
  // Rate Limit Types
  // ============================================================================

  /// <summary>
  /// Rate limit scope
  /// </summary>
  TRateLimitScope = (
    rlsGlobal,     // Shared across all requests
    rlsUser,       // Per user
    rlsSession,    // Per session
    rlsIP,         // Per IP address
    rlsEndpoint    // Per endpoint
  );

  /// <summary>
  /// Rate limit algorithm
  /// </summary>
  TRateLimitAlgorithm = (
    rlaFixedWindow,     // Simple fixed time window
    rlaSlidingWindow,   // Sliding time window
    rlaTokenBucket,     // Token bucket
    rlaLeakyBucket      // Leaky bucket
  );

  /// <summary>
  /// Rate limit result
  /// </summary>
  TRateLimitResult = record
    Allowed: Boolean;
    Remaining: Integer;
    ResetTime: TDateTime;
    RetryAfterSeconds: Integer;
    CurrentUsage: Integer;
    Limit: Integer;
    PolicyName: string;
  end;

  /// <summary>
  /// Rate limit policy configuration
  /// </summary>
  TRateLimitPolicy = class
  private
    FName: string;
    FMaxRequests: Integer;
    FWindowSeconds: Integer;
    FScope: TRateLimitScope;
    FAlgorithm: TRateLimitAlgorithm;
    FBurstSize: Integer;       // For token bucket
    FRefillRate: Double;       // Tokens per second
    FEnabled: Boolean;
    FPriority: Integer;        // Higher = checked first
  public
    constructor Create(const AName: string);

    property Name: string read FName write FName;
    property MaxRequests: Integer read FMaxRequests write FMaxRequests;
    property WindowSeconds: Integer read FWindowSeconds write FWindowSeconds;
    property Scope: TRateLimitScope read FScope write FScope;
    property Algorithm: TRateLimitAlgorithm read FAlgorithm write FAlgorithm;
    property BurstSize: Integer read FBurstSize write FBurstSize;
    property RefillRate: Double read FRefillRate write FRefillRate;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Priority: Integer read FPriority write FPriority;

    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);
  end;

  /// <summary>
  /// Token bucket state
  /// </summary>
  TTokenBucket = class
  private
    FTokens: Double;
    FLastRefill: TDateTime;
    FBurstSize: Integer;
    FRefillRate: Double;
    FLock: TCriticalSection;
  public
    constructor Create(ABurstSize: Integer; ARefillRate: Double);
    destructor Destroy; override;

    function TryConsume(ATokens: Integer = 1): Boolean;
    function GetAvailableTokens: Double;
    procedure Reset;
  end;

  /// <summary>
  /// Sliding window counter
  /// </summary>
  TSlidingWindowCounter = class
  private
    FRequests: TList<TDateTime>;
    FWindowSeconds: Integer;
    FLock: TCriticalSection;

    procedure Cleanup;
  public
    constructor Create(AWindowSeconds: Integer);
    destructor Destroy; override;

    function GetCount: Integer;
    procedure AddRequest;
    function TryAdd(AMaxRequests: Integer): Boolean;
    procedure Reset;
  end;

  /// <summary>
  /// Rate limit entry for a specific key
  /// </summary>
  TRateLimitEntry = class
  private
    FKey: string;
    FPolicyName: string;
    FCounter: TSlidingWindowCounter;
    FTokenBucket: TTokenBucket;
    FCreatedAt: TDateTime;
    FLastAccess: TDateTime;
  public
    constructor Create(const AKey, APolicyName: string; APolicy: TRateLimitPolicy);
    destructor Destroy; override;

    property Key: string read FKey;
    property PolicyName: string read FPolicyName;
    property Counter: TSlidingWindowCounter read FCounter;
    property TokenBucket: TTokenBucket read FTokenBucket;
    property CreatedAt: TDateTime read FCreatedAt;
    property LastAccess: TDateTime read FLastAccess write FLastAccess;
  end;

  /// <summary>
  /// Rate limit event handler
  /// </summary>
  TOnRateLimitExceeded = reference to procedure(const AKey, APolicyName: string;
    const AResult: TRateLimitResult);

  /// <summary>
  /// Main rate limiter
  /// </summary>
  TRateLimiter = class
  private
    FPolicies: TObjectDictionary<string, TRateLimitPolicy>;
    FEntries: TObjectDictionary<string, TRateLimitEntry>;
    FDefaultPolicyName: string;
    FLock: TCriticalSection;
    FEnabled: Boolean;
    FCleanupInterval: Integer;  // Seconds
    FLastCleanup: TDateTime;
    FOnRateLimitExceeded: TOnRateLimitExceeded;

    function GetPolicyForKey(const AKey: string): TRateLimitPolicy;
    function GetOrCreateEntry(const AKey: string; APolicy: TRateLimitPolicy): TRateLimitEntry;
    function BuildKey(const AIdentifier: string; AScope: TRateLimitScope): string;
    procedure DoCleanup;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Add a rate limit policy
    /// </summary>
    procedure AddPolicy(const AName: string; AMaxRequests, AWindowSeconds: Integer;
      AScope: TRateLimitScope = rlsUser; AAlgorithm: TRateLimitAlgorithm = rlaSlidingWindow);

    /// <summary>
    /// Add token bucket policy
    /// </summary>
    procedure AddTokenBucketPolicy(const AName: string; ABurstSize: Integer;
      ARefillRate: Double; AScope: TRateLimitScope = rlsUser);

    /// <summary>
    /// Remove a policy
    /// </summary>
    procedure RemovePolicy(const AName: string);

    /// <summary>
    /// Get a policy by name
    /// </summary>
    function GetPolicy(const AName: string): TRateLimitPolicy;

    /// <summary>
    /// Try to acquire rate limit (returns false if limited)
    /// </summary>
    function TryAcquire(const AIdentifier: string;
      const APolicyName: string = ''): TRateLimitResult;

    /// <summary>
    /// Check without consuming (peek)
    /// </summary>
    function Check(const AIdentifier: string;
      const APolicyName: string = ''): TRateLimitResult;

    /// <summary>
    /// Get current usage for an identifier
    /// </summary>
    function GetUsage(const AIdentifier: string;
      const APolicyName: string = ''): TRateLimitResult;

    /// <summary>
    /// Reset rate limit for an identifier
    /// </summary>
    procedure Reset(const AIdentifier: string; const APolicyName: string = '');

    /// <summary>
    /// Reset all entries
    /// </summary>
    procedure ResetAll;

    /// <summary>
    /// Load policies from JSON file
    /// </summary>
    procedure LoadPolicies(const AFilePath: string);

    /// <summary>
    /// Save policies to JSON file
    /// </summary>
    procedure SavePolicies(const AFilePath: string);

    /// <summary>
    /// Get statistics
    /// </summary>
    function GetStats: TJSONObject;

    property Policies: TObjectDictionary<string, TRateLimitPolicy> read FPolicies;
    property DefaultPolicyName: string read FDefaultPolicyName write FDefaultPolicyName;
    property Enabled: Boolean read FEnabled write FEnabled;
    property CleanupInterval: Integer read FCleanupInterval write FCleanupInterval;
    property OnRateLimitExceeded: TOnRateLimitExceeded read FOnRateLimitExceeded write FOnRateLimitExceeded;
  end;

  // ============================================================================
  // Token Quota Manager
  // ============================================================================

  /// <summary>
  /// Token quota entry
  /// </summary>
  TTokenQuota = class
  private
    FUserId: string;
    FTotalTokens: Int64;
    FUsedTokens: Int64;
    FResetPeriod: string;  // 'daily', 'monthly', 'never'
    FLastReset: TDateTime;
    FLock: TCriticalSection;
  public
    constructor Create(const AUserId: string; ATotalTokens: Int64);
    destructor Destroy; override;

    function TryConsume(ATokens: Integer): Boolean;
    function GetRemaining: Int64;
    procedure AddTokens(ATokens: Int64);
    procedure Reset;
    procedure CheckReset;

    property UserId: string read FUserId;
    property TotalTokens: Int64 read FTotalTokens write FTotalTokens;
    property UsedTokens: Int64 read FUsedTokens;
    property ResetPeriod: string read FResetPeriod write FResetPeriod;
    property LastReset: TDateTime read FLastReset;

    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);
  end;

  /// <summary>
  /// Token quota manager
  /// </summary>
  TTokenQuotaManager = class
  private
    FQuotas: TObjectDictionary<string, TTokenQuota>;
    FDefaultQuota: Int64;
    FDefaultResetPeriod: string;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Set quota for a user
    /// </summary>
    procedure SetQuota(const AUserId: string; ATotalTokens: Int64;
      const AResetPeriod: string = 'monthly');

    /// <summary>
    /// Get user quota
    /// </summary>
    function GetQuota(const AUserId: string): TTokenQuota;

    /// <summary>
    /// Try to consume tokens
    /// </summary>
    function TryConsume(const AUserId: string; ATokens: Integer): Boolean;

    /// <summary>
    /// Get remaining tokens
    /// </summary>
    function GetRemaining(const AUserId: string): Int64;

    /// <summary>
    /// Add tokens to user quota
    /// </summary>
    procedure AddTokens(const AUserId: string; ATokens: Int64);

    /// <summary>
    /// Reset user quota
    /// </summary>
    procedure ResetQuota(const AUserId: string);

    /// <summary>
    /// Save quotas to file
    /// </summary>
    procedure SaveToFile(const AFilePath: string);

    /// <summary>
    /// Load quotas from file
    /// </summary>
    procedure LoadFromFile(const AFilePath: string);

    /// <summary>
    /// Get statistics
    /// </summary>
    function GetStats: TJSONObject;

    property DefaultQuota: Int64 read FDefaultQuota write FDefaultQuota;
    property DefaultResetPeriod: string read FDefaultResetPeriod write FDefaultResetPeriod;
  end;

  /// <summary>
  /// Helper functions
  /// </summary>
  function ScopeToString(AScope: TRateLimitScope): string;
  function StringToScope(const AStr: string): TRateLimitScope;
  function AlgorithmToString(AAlgorithm: TRateLimitAlgorithm): string;
  function StringToAlgorithm(const AStr: string): TRateLimitAlgorithm;

implementation

uses
  System.IOUtils;

function ScopeToString(AScope: TRateLimitScope): string;
begin
  case AScope of
    rlsGlobal: Result := 'global';
    rlsUser: Result := 'user';
    rlsSession: Result := 'session';
    rlsIP: Result := 'ip';
    rlsEndpoint: Result := 'endpoint';
  else
    Result := 'user';
  end;
end;

function StringToScope(const AStr: string): TRateLimitScope;
var
  LowerStr: string;
begin
  LowerStr := LowerCase(AStr);
  if LowerStr = 'global' then Result := rlsGlobal
  else if LowerStr = 'session' then Result := rlsSession
  else if LowerStr = 'ip' then Result := rlsIP
  else if LowerStr = 'endpoint' then Result := rlsEndpoint
  else Result := rlsUser;
end;

function AlgorithmToString(AAlgorithm: TRateLimitAlgorithm): string;
begin
  case AAlgorithm of
    rlaFixedWindow: Result := 'fixed_window';
    rlaSlidingWindow: Result := 'sliding_window';
    rlaTokenBucket: Result := 'token_bucket';
    rlaLeakyBucket: Result := 'leaky_bucket';
  else
    Result := 'sliding_window';
  end;
end;

function StringToAlgorithm(const AStr: string): TRateLimitAlgorithm;
var
  LowerStr: string;
begin
  LowerStr := LowerCase(AStr);
  if LowerStr = 'fixed_window' then Result := rlaFixedWindow
  else if LowerStr = 'token_bucket' then Result := rlaTokenBucket
  else if LowerStr = 'leaky_bucket' then Result := rlaLeakyBucket
  else Result := rlaSlidingWindow;
end;

{ TRateLimitPolicy }

constructor TRateLimitPolicy.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FMaxRequests := 100;
  FWindowSeconds := 60;
  FScope := rlsUser;
  FAlgorithm := rlaSlidingWindow;
  FBurstSize := 10;
  FRefillRate := 1.0;
  FEnabled := True;
  FPriority := 0;
end;

function TRateLimitPolicy.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('max_requests', TJSONNumber.Create(FMaxRequests));
  Result.AddPair('window_seconds', TJSONNumber.Create(FWindowSeconds));
  Result.AddPair('scope', ScopeToString(FScope));
  Result.AddPair('algorithm', AlgorithmToString(FAlgorithm));
  Result.AddPair('burst_size', TJSONNumber.Create(FBurstSize));
  Result.AddPair('refill_rate', TJSONNumber.Create(FRefillRate));
  Result.AddPair('enabled', TJSONBool.Create(FEnabled));
  Result.AddPair('priority', TJSONNumber.Create(FPriority));
end;

procedure TRateLimitPolicy.LoadFromJSON(AJson: TJSONObject);
begin
  FName := AJson.GetValue<string>('name', FName);
  FMaxRequests := AJson.GetValue<Integer>('max_requests', FMaxRequests);
  FWindowSeconds := AJson.GetValue<Integer>('window_seconds', FWindowSeconds);
  FScope := StringToScope(AJson.GetValue<string>('scope', 'user'));
  FAlgorithm := StringToAlgorithm(AJson.GetValue<string>('algorithm', 'sliding_window'));
  FBurstSize := AJson.GetValue<Integer>('burst_size', FBurstSize);
  FRefillRate := AJson.GetValue<Double>('refill_rate', FRefillRate);
  FEnabled := AJson.GetValue<Boolean>('enabled', FEnabled);
  FPriority := AJson.GetValue<Integer>('priority', FPriority);
end;

{ TTokenBucket }

constructor TTokenBucket.Create(ABurstSize: Integer; ARefillRate: Double);
begin
  inherited Create;
  FBurstSize := ABurstSize;
  FRefillRate := ARefillRate;
  FTokens := ABurstSize;
  FLastRefill := Now;
  FLock := TCriticalSection.Create;
end;

destructor TTokenBucket.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TTokenBucket.TryConsume(ATokens: Integer): Boolean;
var
  CurrentTime: TDateTime;
  ElapsedSeconds: Double;
  NewTokens: Double;
begin
  FLock.Enter;
  try
    CurrentTime := Now;
    ElapsedSeconds := SecondSpan(FLastRefill, CurrentTime);

    // Refill tokens
    NewTokens := FTokens + (ElapsedSeconds * FRefillRate);
    if NewTokens > FBurstSize then
      NewTokens := FBurstSize;
    FTokens := NewTokens;
    FLastRefill := CurrentTime;

    // Try to consume
    if FTokens >= ATokens then
    begin
      FTokens := FTokens - ATokens;
      Result := True;
    end
    else
      Result := False;
  finally
    FLock.Leave;
  end;
end;

function TTokenBucket.GetAvailableTokens: Double;
var
  CurrentTime: TDateTime;
  ElapsedSeconds: Double;
begin
  FLock.Enter;
  try
    CurrentTime := Now;
    ElapsedSeconds := SecondSpan(FLastRefill, CurrentTime);
    Result := FTokens + (ElapsedSeconds * FRefillRate);
    if Result > FBurstSize then
      Result := FBurstSize;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenBucket.Reset;
begin
  FLock.Enter;
  try
    FTokens := FBurstSize;
    FLastRefill := Now;
  finally
    FLock.Leave;
  end;
end;

{ TSlidingWindowCounter }

constructor TSlidingWindowCounter.Create(AWindowSeconds: Integer);
begin
  inherited Create;
  FRequests := TList<TDateTime>.Create;
  FWindowSeconds := AWindowSeconds;
  FLock := TCriticalSection.Create;
end;

destructor TSlidingWindowCounter.Destroy;
begin
  FRequests.Free;
  FLock.Free;
  inherited;
end;

procedure TSlidingWindowCounter.Cleanup;
var
  Cutoff: TDateTime;
  I: Integer;
begin
  Cutoff := IncSecond(Now, -FWindowSeconds);

  for I := FRequests.Count - 1 downto 0 do
  begin
    if FRequests[I] < Cutoff then
      FRequests.Delete(I);
  end;
end;

function TSlidingWindowCounter.GetCount: Integer;
begin
  FLock.Enter;
  try
    Cleanup;
    Result := FRequests.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TSlidingWindowCounter.AddRequest;
begin
  FLock.Enter;
  try
    Cleanup;
    FRequests.Add(Now);
  finally
    FLock.Leave;
  end;
end;

function TSlidingWindowCounter.TryAdd(AMaxRequests: Integer): Boolean;
begin
  FLock.Enter;
  try
    Cleanup;
    if FRequests.Count < AMaxRequests then
    begin
      FRequests.Add(Now);
      Result := True;
    end
    else
      Result := False;
  finally
    FLock.Leave;
  end;
end;

procedure TSlidingWindowCounter.Reset;
begin
  FLock.Enter;
  try
    FRequests.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TRateLimitEntry }

constructor TRateLimitEntry.Create(const AKey, APolicyName: string;
  APolicy: TRateLimitPolicy);
begin
  inherited Create;
  FKey := AKey;
  FPolicyName := APolicyName;
  FCreatedAt := Now;
  FLastAccess := Now;

  case APolicy.Algorithm of
    rlaTokenBucket, rlaLeakyBucket:
      FTokenBucket := TTokenBucket.Create(APolicy.BurstSize, APolicy.RefillRate);
  else
    FCounter := TSlidingWindowCounter.Create(APolicy.WindowSeconds);
  end;
end;

destructor TRateLimitEntry.Destroy;
begin
  FCounter.Free;
  FTokenBucket.Free;
  inherited;
end;

{ TRateLimiter }

constructor TRateLimiter.Create;
begin
  inherited;
  FPolicies := TObjectDictionary<string, TRateLimitPolicy>.Create([doOwnsValues]);
  FEntries := TObjectDictionary<string, TRateLimitEntry>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FEnabled := True;
  FCleanupInterval := 300;  // 5 minutes
  FLastCleanup := Now;
  FDefaultPolicyName := 'default';

  // Add default policy
  AddPolicy('default', 100, 60, rlsUser, rlaSlidingWindow);
end;

destructor TRateLimiter.Destroy;
begin
  FPolicies.Free;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

function TRateLimiter.BuildKey(const AIdentifier: string;
  AScope: TRateLimitScope): string;
begin
  Result := ScopeToString(AScope) + ':' + AIdentifier;
end;

function TRateLimiter.GetPolicyForKey(const AKey: string): TRateLimitPolicy;
begin
  if not FPolicies.TryGetValue(FDefaultPolicyName, Result) then
  begin
    if FPolicies.Count > 0 then
      Result := FPolicies.Values.ToArray[0]
    else
      Result := nil;
  end;
end;

function TRateLimiter.GetOrCreateEntry(const AKey: string;
  APolicy: TRateLimitPolicy): TRateLimitEntry;
begin
  if not FEntries.TryGetValue(AKey, Result) then
  begin
    Result := TRateLimitEntry.Create(AKey, APolicy.Name, APolicy);
    FEntries.Add(AKey, Result);
  end;
  Result.LastAccess := Now;
end;

procedure TRateLimiter.DoCleanup;
var
  Cutoff: TDateTime;
  KeysToRemove: TList<string>;
  Key: string;
  Entry: TRateLimitEntry;
begin
  if SecondsBetween(Now, FLastCleanup) < FCleanupInterval then
    Exit;

  Cutoff := IncMinute(Now, -30);  // Remove entries older than 30 minutes
  KeysToRemove := TList<string>.Create;
  try
    for Key in FEntries.Keys do
    begin
      Entry := FEntries[Key];
      if Entry.LastAccess < Cutoff then
        KeysToRemove.Add(Key);
    end;

    for Key in KeysToRemove do
      FEntries.Remove(Key);

    FLastCleanup := Now;
  finally
    KeysToRemove.Free;
  end;
end;

procedure TRateLimiter.AddPolicy(const AName: string;
  AMaxRequests, AWindowSeconds: Integer; AScope: TRateLimitScope;
  AAlgorithm: TRateLimitAlgorithm);
var
  Policy: TRateLimitPolicy;
begin
  FLock.Enter;
  try
    Policy := TRateLimitPolicy.Create(AName);
    Policy.MaxRequests := AMaxRequests;
    Policy.WindowSeconds := AWindowSeconds;
    Policy.Scope := AScope;
    Policy.Algorithm := AAlgorithm;
    FPolicies.AddOrSetValue(AName, Policy);
  finally
    FLock.Leave;
  end;
end;

procedure TRateLimiter.AddTokenBucketPolicy(const AName: string;
  ABurstSize: Integer; ARefillRate: Double; AScope: TRateLimitScope);
var
  Policy: TRateLimitPolicy;
begin
  FLock.Enter;
  try
    Policy := TRateLimitPolicy.Create(AName);
    Policy.Algorithm := rlaTokenBucket;
    Policy.BurstSize := ABurstSize;
    Policy.RefillRate := ARefillRate;
    Policy.Scope := AScope;
    FPolicies.AddOrSetValue(AName, Policy);
  finally
    FLock.Leave;
  end;
end;

procedure TRateLimiter.RemovePolicy(const AName: string);
begin
  FLock.Enter;
  try
    FPolicies.Remove(AName);
  finally
    FLock.Leave;
  end;
end;

function TRateLimiter.GetPolicy(const AName: string): TRateLimitPolicy;
begin
  FLock.Enter;
  try
    if not FPolicies.TryGetValue(AName, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TRateLimiter.TryAcquire(const AIdentifier: string;
  const APolicyName: string): TRateLimitResult;
var
  Policy: TRateLimitPolicy;
  Entry: TRateLimitEntry;
  Key, UsedPolicyName: string;
  Allowed: Boolean;
begin
  Result.Allowed := True;
  Result.Remaining := MaxInt;
  Result.ResetTime := 0;
  Result.RetryAfterSeconds := 0;
  Result.CurrentUsage := 0;
  Result.Limit := MaxInt;
  Result.PolicyName := '';

  if not FEnabled then
    Exit;

  FLock.Enter;
  try
    DoCleanup;

    // Determine policy
    if APolicyName <> '' then
      UsedPolicyName := APolicyName
    else
      UsedPolicyName := FDefaultPolicyName;

    if not FPolicies.TryGetValue(UsedPolicyName, Policy) then
      Exit;

    if not Policy.Enabled then
      Exit;

    Result.PolicyName := Policy.Name;
    Result.Limit := Policy.MaxRequests;

    // Build key based on scope
    Key := BuildKey(AIdentifier, Policy.Scope);

    // Get or create entry
    Entry := GetOrCreateEntry(Key, Policy);

    // Check and acquire based on algorithm
    case Policy.Algorithm of
      rlaTokenBucket, rlaLeakyBucket:
      begin
        Allowed := Entry.TokenBucket.TryConsume(1);
        Result.Remaining := Trunc(Entry.TokenBucket.GetAvailableTokens);
        Result.CurrentUsage := Policy.BurstSize - Result.Remaining;
        Result.Limit := Policy.BurstSize;
        if not Allowed then
          Result.RetryAfterSeconds := Ceil(1 / Policy.RefillRate);
      end;
    else // Sliding window
      begin
        Allowed := Entry.Counter.TryAdd(Policy.MaxRequests);
        Result.CurrentUsage := Entry.Counter.GetCount;
        Result.Remaining := Policy.MaxRequests - Result.CurrentUsage;
        Result.ResetTime := IncSecond(Now, Policy.WindowSeconds);
        if not Allowed then
          Result.RetryAfterSeconds := Policy.WindowSeconds;
      end;
    end;

    Result.Allowed := Allowed;

    if not Allowed and Assigned(FOnRateLimitExceeded) then
      FOnRateLimitExceeded(AIdentifier, Policy.Name, Result);
  finally
    FLock.Leave;
  end;
end;

function TRateLimiter.Check(const AIdentifier: string;
  const APolicyName: string): TRateLimitResult;
var
  Policy: TRateLimitPolicy;
  Entry: TRateLimitEntry;
  Key, UsedPolicyName: string;
begin
  Result.Allowed := True;
  Result.Remaining := MaxInt;
  Result.ResetTime := 0;
  Result.RetryAfterSeconds := 0;
  Result.CurrentUsage := 0;
  Result.Limit := MaxInt;
  Result.PolicyName := '';

  if not FEnabled then
    Exit;

  FLock.Enter;
  try
    if APolicyName <> '' then
      UsedPolicyName := APolicyName
    else
      UsedPolicyName := FDefaultPolicyName;

    if not FPolicies.TryGetValue(UsedPolicyName, Policy) then
      Exit;

    Result.PolicyName := Policy.Name;
    Result.Limit := Policy.MaxRequests;

    Key := BuildKey(AIdentifier, Policy.Scope);

    if FEntries.TryGetValue(Key, Entry) then
    begin
      case Policy.Algorithm of
        rlaTokenBucket, rlaLeakyBucket:
        begin
          Result.Remaining := Trunc(Entry.TokenBucket.GetAvailableTokens);
          Result.CurrentUsage := Policy.BurstSize - Result.Remaining;
          Result.Limit := Policy.BurstSize;
          Result.Allowed := Result.Remaining >= 1;
        end;
      else
        begin
          Result.CurrentUsage := Entry.Counter.GetCount;
          Result.Remaining := Policy.MaxRequests - Result.CurrentUsage;
          Result.Allowed := Result.Remaining > 0;
        end;
      end;
    end
    else
    begin
      Result.Remaining := Policy.MaxRequests;
      Result.Allowed := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRateLimiter.GetUsage(const AIdentifier: string;
  const APolicyName: string): TRateLimitResult;
begin
  Result := Check(AIdentifier, APolicyName);
end;

procedure TRateLimiter.Reset(const AIdentifier: string;
  const APolicyName: string);
var
  Policy: TRateLimitPolicy;
  Key, UsedPolicyName: string;
begin
  FLock.Enter;
  try
    if APolicyName <> '' then
      UsedPolicyName := APolicyName
    else
      UsedPolicyName := FDefaultPolicyName;

    if FPolicies.TryGetValue(UsedPolicyName, Policy) then
    begin
      Key := BuildKey(AIdentifier, Policy.Scope);
      FEntries.Remove(Key);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TRateLimiter.ResetAll;
begin
  FLock.Enter;
  try
    FEntries.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TRateLimiter.LoadPolicies(const AFilePath: string);
var
  JsonStr: string;
  JsonObj: TJSONObject;
  PoliciesArr: TJSONArray;
  PolicyObj: TJSONObject;
  Policy: TRateLimitPolicy;
  I: Integer;
begin
  if not TFile.Exists(AFilePath) then
    Exit;

  JsonStr := TFile.ReadAllText(AFilePath);
  JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JsonObj = nil then
    Exit;

  try
    FLock.Enter;
    try
      PoliciesArr := JsonObj.GetValue('policies') as TJSONArray;
      if PoliciesArr <> nil then
      begin
        for I := 0 to PoliciesArr.Count - 1 do
        begin
          PolicyObj := PoliciesArr.Items[I] as TJSONObject;
          Policy := TRateLimitPolicy.Create('');
          Policy.LoadFromJSON(PolicyObj);
          FPolicies.AddOrSetValue(Policy.Name, Policy);
        end;
      end;

      FDefaultPolicyName := JsonObj.GetValue<string>('default_policy', FDefaultPolicyName);
    finally
      FLock.Leave;
    end;
  finally
    JsonObj.Free;
  end;
end;

procedure TRateLimiter.SavePolicies(const AFilePath: string);
var
  JsonObj: TJSONObject;
  PoliciesArr: TJSONArray;
  Policy: TRateLimitPolicy;
begin
  JsonObj := TJSONObject.Create;
  try
    PoliciesArr := TJSONArray.Create;

    FLock.Enter;
    try
      for Policy in FPolicies.Values do
        PoliciesArr.Add(Policy.ToJSON);
    finally
      FLock.Leave;
    end;

    JsonObj.AddPair('policies', PoliciesArr);
    JsonObj.AddPair('default_policy', FDefaultPolicyName);

    TFile.WriteAllText(AFilePath, JsonObj.Format(2));
  finally
    JsonObj.Free;
  end;
end;

function TRateLimiter.GetStats: TJSONObject;
begin
  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('enabled', TJSONBool.Create(FEnabled));
    Result.AddPair('policy_count', TJSONNumber.Create(FPolicies.Count));
    Result.AddPair('entry_count', TJSONNumber.Create(FEntries.Count));
    Result.AddPair('default_policy', FDefaultPolicyName);
    Result.AddPair('cleanup_interval_seconds', TJSONNumber.Create(FCleanupInterval));
  finally
    FLock.Leave;
  end;
end;

{ TTokenQuota }

constructor TTokenQuota.Create(const AUserId: string; ATotalTokens: Int64);
begin
  inherited Create;
  FUserId := AUserId;
  FTotalTokens := ATotalTokens;
  FUsedTokens := 0;
  FResetPeriod := 'monthly';
  FLastReset := Now;
  FLock := TCriticalSection.Create;
end;

destructor TTokenQuota.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TTokenQuota.TryConsume(ATokens: Integer): Boolean;
begin
  FLock.Enter;
  try
    CheckReset;
    if FUsedTokens + ATokens <= FTotalTokens then
    begin
      FUsedTokens := FUsedTokens + ATokens;
      Result := True;
    end
    else
      Result := False;
  finally
    FLock.Leave;
  end;
end;

function TTokenQuota.GetRemaining: Int64;
begin
  FLock.Enter;
  try
    CheckReset;
    Result := FTotalTokens - FUsedTokens;
    if Result < 0 then
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenQuota.AddTokens(ATokens: Int64);
begin
  FLock.Enter;
  try
    FTotalTokens := FTotalTokens + ATokens;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenQuota.Reset;
begin
  FLock.Enter;
  try
    FUsedTokens := 0;
    FLastReset := Now;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenQuota.CheckReset;
var
  ShouldReset: Boolean;
begin
  ShouldReset := False;

  if FResetPeriod = 'daily' then
    ShouldReset := DaysBetween(Now, FLastReset) >= 1
  else if FResetPeriod = 'weekly' then
    ShouldReset := DaysBetween(Now, FLastReset) >= 7
  else if FResetPeriod = 'monthly' then
    ShouldReset := MonthsBetween(Now, FLastReset) >= 1;

  if ShouldReset then
  begin
    FUsedTokens := 0;
    FLastReset := Now;
  end;
end;

function TTokenQuota.ToJSON: TJSONObject;
begin
  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('user_id', FUserId);
    Result.AddPair('total_tokens', TJSONNumber.Create(FTotalTokens));
    Result.AddPair('used_tokens', TJSONNumber.Create(FUsedTokens));
    Result.AddPair('reset_period', FResetPeriod);
    Result.AddPair('last_reset', DateTimeToStr(FLastReset));
  finally
    FLock.Leave;
  end;
end;

procedure TTokenQuota.LoadFromJSON(AJson: TJSONObject);
begin
  FLock.Enter;
  try
    FUserId := AJson.GetValue<string>('user_id', FUserId);
    FTotalTokens := AJson.GetValue<Int64>('total_tokens', FTotalTokens);
    FUsedTokens := AJson.GetValue<Int64>('used_tokens', FUsedTokens);
    FResetPeriod := AJson.GetValue<string>('reset_period', FResetPeriod);
    // Note: last_reset parsing simplified
  finally
    FLock.Leave;
  end;
end;

{ TTokenQuotaManager }

constructor TTokenQuotaManager.Create;
begin
  inherited;
  FQuotas := TObjectDictionary<string, TTokenQuota>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FDefaultQuota := 100000;  // 100K tokens default
  FDefaultResetPeriod := 'monthly';
end;

destructor TTokenQuotaManager.Destroy;
begin
  FQuotas.Free;
  FLock.Free;
  inherited;
end;

procedure TTokenQuotaManager.SetQuota(const AUserId: string;
  ATotalTokens: Int64; const AResetPeriod: string);
var
  Quota: TTokenQuota;
begin
  FLock.Enter;
  try
    if FQuotas.TryGetValue(AUserId, Quota) then
    begin
      Quota.TotalTokens := ATotalTokens;
      Quota.ResetPeriod := AResetPeriod;
    end
    else
    begin
      Quota := TTokenQuota.Create(AUserId, ATotalTokens);
      Quota.ResetPeriod := AResetPeriod;
      FQuotas.Add(AUserId, Quota);
    end;
  finally
    FLock.Leave;
  end;
end;

function TTokenQuotaManager.GetQuota(const AUserId: string): TTokenQuota;
begin
  FLock.Enter;
  try
    if not FQuotas.TryGetValue(AUserId, Result) then
    begin
      // Create default quota
      Result := TTokenQuota.Create(AUserId, FDefaultQuota);
      Result.ResetPeriod := FDefaultResetPeriod;
      FQuotas.Add(AUserId, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TTokenQuotaManager.TryConsume(const AUserId: string;
  ATokens: Integer): Boolean;
var
  Quota: TTokenQuota;
begin
  Quota := GetQuota(AUserId);
  Result := Quota.TryConsume(ATokens);
end;

function TTokenQuotaManager.GetRemaining(const AUserId: string): Int64;
var
  Quota: TTokenQuota;
begin
  Quota := GetQuota(AUserId);
  Result := Quota.GetRemaining;
end;

procedure TTokenQuotaManager.AddTokens(const AUserId: string; ATokens: Int64);
var
  Quota: TTokenQuota;
begin
  Quota := GetQuota(AUserId);
  Quota.AddTokens(ATokens);
end;

procedure TTokenQuotaManager.ResetQuota(const AUserId: string);
var
  Quota: TTokenQuota;
begin
  FLock.Enter;
  try
    if FQuotas.TryGetValue(AUserId, Quota) then
      Quota.Reset;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenQuotaManager.SaveToFile(const AFilePath: string);
var
  JsonObj: TJSONObject;
  QuotasArr: TJSONArray;
  Quota: TTokenQuota;
begin
  JsonObj := TJSONObject.Create;
  try
    QuotasArr := TJSONArray.Create;

    FLock.Enter;
    try
      for Quota in FQuotas.Values do
        QuotasArr.Add(Quota.ToJSON);
    finally
      FLock.Leave;
    end;

    JsonObj.AddPair('quotas', QuotasArr);
    JsonObj.AddPair('default_quota', TJSONNumber.Create(FDefaultQuota));
    JsonObj.AddPair('default_reset_period', FDefaultResetPeriod);

    TFile.WriteAllText(AFilePath, JsonObj.Format(2));
  finally
    JsonObj.Free;
  end;
end;

procedure TTokenQuotaManager.LoadFromFile(const AFilePath: string);
var
  JsonStr: string;
  JsonObj: TJSONObject;
  QuotasArr: TJSONArray;
  QuotaObj: TJSONObject;
  Quota: TTokenQuota;
  I: Integer;
begin
  if not TFile.Exists(AFilePath) then
    Exit;

  JsonStr := TFile.ReadAllText(AFilePath);
  JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JsonObj = nil then
    Exit;

  try
    FLock.Enter;
    try
      FDefaultQuota := JsonObj.GetValue<Int64>('default_quota', FDefaultQuota);
      FDefaultResetPeriod := JsonObj.GetValue<string>('default_reset_period', FDefaultResetPeriod);

      QuotasArr := JsonObj.GetValue('quotas') as TJSONArray;
      if QuotasArr <> nil then
      begin
        for I := 0 to QuotasArr.Count - 1 do
        begin
          QuotaObj := QuotasArr.Items[I] as TJSONObject;
          Quota := TTokenQuota.Create('', 0);
          Quota.LoadFromJSON(QuotaObj);
          FQuotas.AddOrSetValue(Quota.UserId, Quota);
        end;
      end;
    finally
      FLock.Leave;
    end;
  finally
    JsonObj.Free;
  end;
end;

function TTokenQuotaManager.GetStats: TJSONObject;
var
  TotalUsed, TotalQuota: Int64;
  Quota: TTokenQuota;
begin
  TotalUsed := 0;
  TotalQuota := 0;

  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('user_count', TJSONNumber.Create(FQuotas.Count));
    Result.AddPair('default_quota', TJSONNumber.Create(FDefaultQuota));
    Result.AddPair('default_reset_period', FDefaultResetPeriod);

    for Quota in FQuotas.Values do
    begin
      TotalUsed := TotalUsed + Quota.UsedTokens;
      TotalQuota := TotalQuota + Quota.TotalTokens;
    end;

    Result.AddPair('total_tokens_used', TJSONNumber.Create(TotalUsed));
    Result.AddPair('total_tokens_quota', TJSONNumber.Create(TotalQuota));
  finally
    FLock.Leave;
  end;
end;

end.
