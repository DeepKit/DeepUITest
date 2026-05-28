unit UniFlow.AI.SmartRetry;

{*******************************************************************************
  UniFlow 智能重试策略引擎
  
  功能:
  - 动态重试策略选择
  - 错误分类学习
  - 重试参数自适应
  - 熔断器集�?
  - 历史分析优化
  
  作�? UniFlow Team
  日期: 2024-01
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.Math, System.DateUtils, System.SyncObjs,
  System.RegularExpressions;

type
  {$REGION '错误分类'}
  
  /// <summary>错误类别</summary>
  TErrorCategory = (
    ecTransient,          // 瞬态错�?(网络抖动, 临时过载)
    ecRateLimited,        // 限流错误
    ecResourceExhausted,  // 资源耗尽
    ecTimeout,            // 超时
    ecServiceUnavailable, // 服务不可�?
    ecBadRequest,         // 请求错误 (不应重试)
    ecAuthentication,     // 认证错误 (不应重试)
    ecPermission,         // 权限错误 (不应重试)
    ecDataIntegrity,      // 数据完整性错�?
    ecCircuitOpen,        // 熔断器打开
    ecUnknown             // 未知
  );
  
  /// <summary>错误严重程度</summary>
  TErrorSeverity = (
    esLow,       // �?- 可安全重�?
    esMedium,    // �?- 谨慎重试
    esHigh,      // �?- 限制重试
    esCritical   // 严重 - 不应重试
  );
  
  /// <summary>错误分类结果</summary>
  TErrorClassification = record
    Category: TErrorCategory;
    Severity: TErrorSeverity;
    Retryable: Boolean;
    SuggestedWaitMs: Integer;
    Confidence: Double;
    Reason: string;
  end;
  
  /// <summary>错误信息</summary>
  TErrorInfo = record
    ErrorCode: Integer;
    ErrorMessage: string;
    ExceptionType: string;
    StackTrace: string;
    HttpStatus: Integer;
    ServiceName: string;
    Timestamp: TDateTime;
  end;
  
  {$ENDREGION}
  
  {$REGION '错误分类�?}
  
  /// <summary>错误模式</summary>
  TErrorPattern = record
    Pattern: string;
    Category: TErrorCategory;
    Severity: TErrorSeverity;
    Retryable: Boolean;
    BaseWaitMs: Integer;
  end;
  
  /// <summary>错误分类�?/summary>
  TErrorClassifier = class
  private
    FPatterns: TList<TErrorPattern>;
    FHttpStatusMapping: TDictionary<Integer, TErrorClassification>;
    FExceptionMapping: TDictionary<string, TErrorClassification>;
    FLearningEnabled: Boolean;
    FLearnedPatterns: TDictionary<string, TErrorClassification>;
    
    procedure InitializePatterns;
    procedure InitializeHttpStatusMapping;
    function MatchPattern(const AError: TErrorInfo): TErrorPattern;
    function ClassifyByHttpStatus(AStatus: Integer): TErrorClassification;
    function ClassifyByException(const AType: string): TErrorClassification;
    function ClassifyByMessage(const AMessage: string): TErrorClassification;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Classify(const AError: TErrorInfo): TErrorClassification;
    procedure AddPattern(const APattern: TErrorPattern);
    procedure LearnFromOutcome(const AError: TErrorInfo; ARetrySucceeded: Boolean);
    
    property LearningEnabled: Boolean read FLearningEnabled write FLearningEnabled;
  end;
  
  {$ENDREGION}
  
  {$REGION '重试策略'}
  
  /// <summary>退避策略类�?/summary>
  TBackoffType = (
    btFixed,              // 固定延迟
    btLinear,             // 线性退�?
    btExponential,        // 指数退�?
    btExponentialJitter,  // 指数退�?+ 抖动
    btFibonacci,          // 斐波那契退�?
    btDecorrelated        // 去相关抖�?
  );
  
  /// <summary>退避配�?/summary>
  TBackoffConfig = record
    BackoffType: TBackoffType;
    InitialDelayMs: Integer;
    MaxDelayMs: Integer;
    Multiplier: Double;
    JitterFactor: Double;
    UseFullJitter: Boolean;
  end;
  
  /// <summary>重试配置</summary>
  TRetryConfig = record
    MaxRetries: Integer;
    Backoff: TBackoffConfig;
    RetryableCategories: TArray<TErrorCategory>;
    NonRetryableCategories: TArray<TErrorCategory>;
    TotalTimeoutMs: Integer;
    PerAttemptTimeoutMs: Integer;
  end;
  
  /// <summary>重试策略接口</summary>
  IRetryStrategy = interface
    ['{9C6E5B3D-2D4E-4F9A-8B7C-1E3F5A6C8D9E}']
    function ShouldRetry(const AError: TErrorInfo; AAttempt: Integer): Boolean;
    function GetDelayMs(AAttempt: Integer): Integer;
    function GetMaxRetries: Integer;
    procedure RecordSuccess(AAttempt: Integer; AElapsedMs: Integer);
    procedure RecordFailure(const AError: TErrorInfo; AAttempt: Integer);
  end;
  
  /// <summary>固定延迟策略</summary>
  TFixedDelayStrategy = class(TInterfacedObject, IRetryStrategy)
  private
    FDelayMs: Integer;
    FMaxRetries: Integer;
    FClassifier: TErrorClassifier;
  public
    constructor Create(ADelayMs, AMaxRetries: Integer);
    
    function ShouldRetry(const AError: TErrorInfo; AAttempt: Integer): Boolean;
    function GetDelayMs(AAttempt: Integer): Integer;
    function GetMaxRetries: Integer;
    procedure RecordSuccess(AAttempt: Integer; AElapsedMs: Integer);
    procedure RecordFailure(const AError: TErrorInfo; AAttempt: Integer);
  end;
  
  /// <summary>指数退避策�?/summary>
  TExponentialBackoffStrategy = class(TInterfacedObject, IRetryStrategy)
  private
    FConfig: TBackoffConfig;
    FMaxRetries: Integer;
    FClassifier: TErrorClassifier;
    
    function CalculateDelay(AAttempt: Integer): Integer;
    function AddJitter(ADelayMs: Integer): Integer;
  public
    constructor Create(const AConfig: TBackoffConfig; AMaxRetries: Integer);
    
    function ShouldRetry(const AError: TErrorInfo; AAttempt: Integer): Boolean;
    function GetDelayMs(AAttempt: Integer): Integer;
    function GetMaxRetries: Integer;
    procedure RecordSuccess(AAttempt: Integer; AElapsedMs: Integer);
    procedure RecordFailure(const AError: TErrorInfo; AAttempt: Integer);
  end;
  
  /// <summary>自适应重试策略</summary>
  TAdaptiveRetryStrategy = class(TInterfacedObject, IRetryStrategy)
  private
    FBaseConfig: TRetryConfig;
    FClassifier: TErrorClassifier;
    FSuccessRates: TDictionary<string, Double>;
    FAverageDelays: TDictionary<string, Double>;
    FRecentErrors: TList<TErrorInfo>;
    FLock: TCriticalSection;
    
    function GetServiceKey(const AError: TErrorInfo): string;
    function CalculateAdaptiveDelay(const AError: TErrorInfo; AAttempt: Integer): Integer;
    function CalculateAdaptiveMaxRetries(const AError: TErrorInfo): Integer;
    procedure UpdateSuccessRate(const AServiceKey: string; ASuccess: Boolean);
  public
    constructor Create(const AConfig: TRetryConfig);
    destructor Destroy; override;
    
    function ShouldRetry(const AError: TErrorInfo; AAttempt: Integer): Boolean;
    function GetDelayMs(AAttempt: Integer): Integer;
    function GetMaxRetries: Integer;
    procedure RecordSuccess(AAttempt: Integer; AElapsedMs: Integer);
    procedure RecordFailure(const AError: TErrorInfo; AAttempt: Integer);
    
    function GetSuccessRate(const AServiceName: string): Double;
  end;
  
  {$ENDREGION}
  
  {$REGION '熔断�?}
  
  /// <summary>熔断器状�?/summary>
  TCircuitState = (
    csClosed,     // 关闭 - 正常运行
    csOpen,       // 打开 - 拒绝请求
    csHalfOpen    // 半开 - 测试恢复
  );
  
  /// <summary>熔断器配�?/summary>
  TCircuitBreakerConfig = record
    FailureThreshold: Integer;      // 触发熔断的失败次�?
    SuccessThreshold: Integer;      // 关闭熔断的成功次�?
    TimeoutMs: Integer;             // 熔断超时时间
    SamplingWindowMs: Integer;      // 采样窗口
    MinimumRequests: Integer;       // 最小请求数
    FailureRateThreshold: Double;   // 失败率阈�?
  end;
  
  /// <summary>熔断器事�?/summary>
  TCircuitBreakerEvent = (
    cbeStateChanged,
    cbeRequestRejected,
    cbeRequestSucceeded,
    cbeRequestFailed
  );
  
  /// <summary>熔断器事件处理器</summary>
  TCircuitBreakerEventHandler = reference to procedure(
    AEvent: TCircuitBreakerEvent; AState: TCircuitState);
  
  /// <summary>熔断�?/summary>
  TCircuitBreaker = class
  private
    FName: string;
    FConfig: TCircuitBreakerConfig;
    FState: TCircuitState;
    FFailureCount: Integer;
    FSuccessCount: Integer;
    FRequestCount: Integer;
    FLastFailureTime: TDateTime;
    FStateChangedTime: TDateTime;
    FLock: TCriticalSection;
    FEventHandler: TCircuitBreakerEventHandler;
    FRequestHistory: TList<TPair<TDateTime, Boolean>>;
    
    procedure TransitionTo(ANewState: TCircuitState);
    procedure CleanupHistory;
    function CalculateFailureRate: Double;
    function IsTimeoutExpired: Boolean;
  public
    constructor Create(const AName: string; const AConfig: TCircuitBreakerConfig);
    destructor Destroy; override;
    
    function AllowRequest: Boolean;
    procedure RecordSuccess;
    procedure RecordFailure;
    procedure Reset;
    
    property Name: string read FName;
    property State: TCircuitState read FState;
    property FailureRate: Double read CalculateFailureRate;
    property OnEvent: TCircuitBreakerEventHandler read FEventHandler write FEventHandler;
  end;
  
  /// <summary>熔断器注册表</summary>
  TCircuitBreakerRegistry = class
  private
    FCircuitBreakers: TDictionary<string, TCircuitBreaker>;
    FDefaultConfig: TCircuitBreakerConfig;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    function GetOrCreate(const AName: string): TCircuitBreaker;
    function GetOrCreateWithConfig(const AName: string;
      const AConfig: TCircuitBreakerConfig): TCircuitBreaker;
    procedure Remove(const AName: string);
    function GetAll: TArray<TCircuitBreaker>;
    
    property DefaultConfig: TCircuitBreakerConfig read FDefaultConfig write FDefaultConfig;
  end;
  
  {$ENDREGION}
  
  {$REGION '重试执行�?}
  
  /// <summary>重试尝试记录</summary>
  TRetryAttempt = record
    AttemptNumber: Integer;
    StartTime: TDateTime;
    EndTime: TDateTime;
    DurationMs: Integer;
    Success: Boolean;
    Error: TErrorInfo;
    DelayBeforeMs: Integer;
  end;
  
  /// <summary>重试结果</summary>
  TRetryResult<T> = record
    Success: Boolean;
    Value: T;
    TotalAttempts: Integer;
    TotalDurationMs: Integer;
    Attempts: TArray<TRetryAttempt>;
    FinalError: TErrorInfo;
  end;
  
  /// <summary>可重试操�?/summary>
  TRetryableOperation<T> = reference to function: T;
  
  /// <summary>错误提取�?/summary>
  TErrorExtractor = reference to function(E: Exception): TErrorInfo;
  
  /// <summary>重试执行�?/summary>
  TRetryExecutor = class
  private
    FStrategy: IRetryStrategy;
    FCircuitBreaker: TCircuitBreaker;
    FErrorExtractor: TErrorExtractor;
    FOnRetry: TProc<TRetryAttempt>;
    
    function DefaultErrorExtractor(E: Exception): TErrorInfo;
  public
    constructor Create(AStrategy: IRetryStrategy; ACircuitBreaker: TCircuitBreaker = nil);
    
    function Execute<T>(AOperation: TRetryableOperation<T>): TRetryResult<T>;
    function ExecuteAsync<T>(AOperation: TRetryableOperation<T>): TRetryResult<T>;
    
    property ErrorExtractor: TErrorExtractor read FErrorExtractor write FErrorExtractor;
    property OnRetry: TProc<TRetryAttempt> read FOnRetry write FOnRetry;
  end;
  
  {$ENDREGION}
  
  {$REGION '策略选择�?}
  
  /// <summary>服务特征</summary>
  TServiceCharacteristics = record
    ServiceName: string;
    AverageLatencyMs: Double;
    FailureRate: Double;
    IsIdempotent: Boolean;
    HasSideEffects: Boolean;
    CriticalityLevel: Integer;
  end;
  
  /// <summary>策略推荐</summary>
  TStrategyRecommendation = record
    StrategyType: TBackoffType;
    MaxRetries: Integer;
    InitialDelayMs: Integer;
    MaxDelayMs: Integer;
    Confidence: Double;
    Reasoning: string;
  end;
  
  /// <summary>智能策略选择�?/summary>
  TSmartStrategySelector = class
  private
    FHistoricalData: TDictionary<string, TList<TRetryAttempt>>;
    FServiceCharacteristics: TDictionary<string, TServiceCharacteristics>;
    FDefaultRecommendation: TStrategyRecommendation;
    FLock: TCriticalSection;
    
    function AnalyzeHistoricalData(const AServiceName: string): TStrategyRecommendation;
    function ApplyHeuristics(const ACharacteristics: TServiceCharacteristics): TStrategyRecommendation;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure RecordAttempt(const AServiceName: string; const AAttempt: TRetryAttempt);
    procedure SetServiceCharacteristics(const ACharacteristics: TServiceCharacteristics);
    function Recommend(const AServiceName: string): TStrategyRecommendation;
    function CreateStrategy(const ARecommendation: TStrategyRecommendation): IRetryStrategy;
  end;
  
  {$ENDREGION}
  
  {$REGION '重试服务'}
  
  /// <summary>重试统计</summary>
  TRetryStatistics = record
    TotalRequests: Int64;
    TotalRetries: Int64;
    SuccessfulRetries: Int64;
    FailedRetries: Int64;
    AverageRetriesPerRequest: Double;
    AverageDelayMs: Double;
    SuccessRate: Double;
  end;
  
  /// <summary>重试服务配置</summary>
  TRetryServiceConfig = record
    EnableAdaptiveStrategy: Boolean;
    EnableCircuitBreaker: Boolean;
    EnableLearning: Boolean;
    GlobalMaxRetries: Integer;
    GlobalMaxDelayMs: Integer;
  end;
  
  /// <summary>智能重试服务</summary>
  TSmartRetryService = class
  private
    FConfig: TRetryServiceConfig;
    FClassifier: TErrorClassifier;
    FStrategySelector: TSmartStrategySelector;
    FCircuitRegistry: TCircuitBreakerRegistry;
    FStrategies: TDictionary<string, IRetryStrategy>;
    FStatistics: TDictionary<string, TRetryStatistics>;
    FLock: TCriticalSection;
    
    function GetOrCreateStrategy(const AServiceName: string): IRetryStrategy;
    function GetOrCreateCircuitBreaker(const AServiceName: string): TCircuitBreaker;
    procedure UpdateStatistics(const AServiceName: string; const AResult: TRetryResult<Variant>);
  public
    constructor Create(const AConfig: TRetryServiceConfig);
    destructor Destroy; override;
    
    function Execute<T>(const AServiceName: string;
      AOperation: TRetryableOperation<T>): TRetryResult<T>;
    
    function ShouldRetry(const AServiceName: string;
      const AError: TErrorInfo; AAttempt: Integer): Boolean;
    function GetDelay(const AServiceName: string; AAttempt: Integer): Integer;
    
    procedure SetServiceConfig(const AServiceName: string; const AConfig: TRetryConfig);
    function GetStatistics(const AServiceName: string): TRetryStatistics;
    function GetAllStatistics: TDictionary<string, TRetryStatistics>;
    
    procedure ReportFeedback(const AServiceName: string;
      const AError: TErrorInfo; ARetrySucceeded: Boolean);
    
    property Classifier: TErrorClassifier read FClassifier;
    property CircuitRegistry: TCircuitBreakerRegistry read FCircuitRegistry;
  end;
  
  {$ENDREGION}
  
  {$REGION '重试策略构建�?}
  
  /// <summary>重试策略构建�?/summary>
  TRetryStrategyBuilder = class
  private
    FMaxRetries: Integer;
    FBackoffType: TBackoffType;
    FInitialDelayMs: Integer;
    FMaxDelayMs: Integer;
    FMultiplier: Double;
    FJitterFactor: Double;
    FRetryableCategories: TList<TErrorCategory>;
    FNonRetryableCategories: TList<TErrorCategory>;
  public
    constructor Create;
    destructor Destroy; override;
    
    function WithMaxRetries(AMaxRetries: Integer): TRetryStrategyBuilder;
    function WithBackoffType(AType: TBackoffType): TRetryStrategyBuilder;
    function WithInitialDelay(ADelayMs: Integer): TRetryStrategyBuilder;
    function WithMaxDelay(AMaxDelayMs: Integer): TRetryStrategyBuilder;
    function WithMultiplier(AMultiplier: Double): TRetryStrategyBuilder;
    function WithJitter(AJitterFactor: Double): TRetryStrategyBuilder;
    function RetryOn(ACategory: TErrorCategory): TRetryStrategyBuilder;
    function DoNotRetryOn(ACategory: TErrorCategory): TRetryStrategyBuilder;
    
    function Build: IRetryStrategy;
    function BuildConfig: TRetryConfig;
  end;
  
  {$ENDREGION}

implementation

{$REGION 'TErrorClassifier'}

constructor TErrorClassifier.Create;
begin
  inherited Create;
  FPatterns := TList<TErrorPattern>.Create;
  FHttpStatusMapping := TDictionary<Integer, TErrorClassification>.Create;
  FExceptionMapping := TDictionary<string, TErrorClassification>.Create;
  FLearnedPatterns := TDictionary<string, TErrorClassification>.Create;
  FLearningEnabled := True;
  
  InitializePatterns;
  InitializeHttpStatusMapping;
end;

destructor TErrorClassifier.Destroy;
begin
  FLearnedPatterns.Free;
  FExceptionMapping.Free;
  FHttpStatusMapping.Free;
  FPatterns.Free;
  inherited;
end;

procedure TErrorClassifier.InitializePatterns;
var
  Pattern: TErrorPattern;
begin
  // 瞬态错误模�?
  Pattern.Pattern := '(connection|connect|network|socket).*(refused|reset|timeout|failed)';
  Pattern.Category := ecTransient;
  Pattern.Severity := esLow;
  Pattern.Retryable := True;
  Pattern.BaseWaitMs := 1000;
  FPatterns.Add(Pattern);
  
  Pattern.Pattern := '(temporary|transient|intermittent)';
  Pattern.Category := ecTransient;
  Pattern.Severity := esLow;
  Pattern.Retryable := True;
  Pattern.BaseWaitMs := 500;
  FPatterns.Add(Pattern);
  
  // 限流模式
  Pattern.Pattern := '(rate.?limit|too.?many.?requests|throttl|quota)';
  Pattern.Category := ecRateLimited;
  Pattern.Severity := esMedium;
  Pattern.Retryable := True;
  Pattern.BaseWaitMs := 5000;
  FPatterns.Add(Pattern);
  
  // 超时模式
  Pattern.Pattern := '(timeout|timed?.?out|deadline.?exceeded)';
  Pattern.Category := ecTimeout;
  Pattern.Severity := esLow;
  Pattern.Retryable := True;
  Pattern.BaseWaitMs := 2000;
  FPatterns.Add(Pattern);
  
  // 服务不可用模�?
  Pattern.Pattern := '(service.?unavailable|server.?error|internal.?error|503|502|500)';
  Pattern.Category := ecServiceUnavailable;
  Pattern.Severity := esMedium;
  Pattern.Retryable := True;
  Pattern.BaseWaitMs := 3000;
  FPatterns.Add(Pattern);
  
  // 资源耗尽模式
  Pattern.Pattern := '(resource.?exhausted|out.?of.?memory|no.?space|disk.?full)';
  Pattern.Category := ecResourceExhausted;
  Pattern.Severity := esHigh;
  Pattern.Retryable := True;
  Pattern.BaseWaitMs := 10000;
  FPatterns.Add(Pattern);
  
  // 认证错误 - 不可重试
  Pattern.Pattern := '(unauthorized|authentication|invalid.?token|expired.?token|401)';
  Pattern.Category := ecAuthentication;
  Pattern.Severity := esCritical;
  Pattern.Retryable := False;
  Pattern.BaseWaitMs := 0;
  FPatterns.Add(Pattern);
  
  // 权限错误 - 不可重试
  Pattern.Pattern := '(forbidden|access.?denied|permission|403)';
  Pattern.Category := ecPermission;
  Pattern.Severity := esCritical;
  Pattern.Retryable := False;
  Pattern.BaseWaitMs := 0;
  FPatterns.Add(Pattern);
  
  // 请求错误 - 不可重试
  Pattern.Pattern := '(bad.?request|invalid.?(param|argument|input)|400)';
  Pattern.Category := ecBadRequest;
  Pattern.Severity := esCritical;
  Pattern.Retryable := False;
  Pattern.BaseWaitMs := 0;
  FPatterns.Add(Pattern);
end;

procedure TErrorClassifier.InitializeHttpStatusMapping;
var
  Classification: TErrorClassification;
begin
  // 4xx 客户端错�?
  Classification.Category := ecBadRequest;
  Classification.Severity := esCritical;
  Classification.Retryable := False;
  Classification.SuggestedWaitMs := 0;
  Classification.Confidence := 0.95;
  FHttpStatusMapping.Add(400, Classification);
  
  Classification.Category := ecAuthentication;
  FHttpStatusMapping.Add(401, Classification);
  
  Classification.Category := ecPermission;
  FHttpStatusMapping.Add(403, Classification);
  
  // 404 通常不应重试
  Classification.Category := ecBadRequest;
  FHttpStatusMapping.Add(404, Classification);
  
  // 429 限流 - 应该重试
  Classification.Category := ecRateLimited;
  Classification.Severity := esMedium;
  Classification.Retryable := True;
  Classification.SuggestedWaitMs := 5000;
  FHttpStatusMapping.Add(429, Classification);
  
  // 5xx 服务器错�?
  Classification.Category := ecServiceUnavailable;
  Classification.Severity := esMedium;
  Classification.Retryable := True;
  Classification.SuggestedWaitMs := 3000;
  FHttpStatusMapping.Add(500, Classification);
  FHttpStatusMapping.Add(502, Classification);
  FHttpStatusMapping.Add(503, Classification);
  
  // 504 网关超时
  Classification.Category := ecTimeout;
  Classification.SuggestedWaitMs := 2000;
  FHttpStatusMapping.Add(504, Classification);
end;

function TErrorClassifier.MatchPattern(const AError: TErrorInfo): TErrorPattern;
var
  Pattern: TErrorPattern;
  CombinedText: string;
begin
  CombinedText := LowerCase(AError.ErrorMessage + ' ' + AError.ExceptionType);
  
  for Pattern in FPatterns do
  begin
    if TRegEx.IsMatch(CombinedText, Pattern.Pattern, [roIgnoreCase]) then
      Exit(Pattern);
  end;
  
  // 默认未知模式
  Result.Pattern := '';
  Result.Category := ecUnknown;
  Result.Severity := esMedium;
  Result.Retryable := True;
  Result.BaseWaitMs := 1000;
end;

function TErrorClassifier.ClassifyByHttpStatus(AStatus: Integer): TErrorClassification;
begin
  if not FHttpStatusMapping.TryGetValue(AStatus, Result) then
  begin
    Result.Category := ecUnknown;
    Result.Severity := esMedium;
    Result.Retryable := AStatus >= 500;
    Result.SuggestedWaitMs := 1000;
    Result.Confidence := 0.5;
  end;
end;

function TErrorClassifier.ClassifyByException(const AType: string): TErrorClassification;
begin
  if not FExceptionMapping.TryGetValue(AType, Result) then
  begin
    Result.Category := ecUnknown;
    Result.Severity := esMedium;
    Result.Retryable := True;
    Result.SuggestedWaitMs := 1000;
    Result.Confidence := 0.5;
  end;
end;

function TErrorClassifier.ClassifyByMessage(const AMessage: string): TErrorClassification;
var
  Pattern: TErrorPattern;
begin
  Pattern := MatchPattern(Default(TErrorInfo));
  
  Result.Category := Pattern.Category;
  Result.Severity := Pattern.Severity;
  Result.Retryable := Pattern.Retryable;
  Result.SuggestedWaitMs := Pattern.BaseWaitMs;
  Result.Confidence := 0.7;
end;

function TErrorClassifier.Classify(const AError: TErrorInfo): TErrorClassification;
var
  Pattern: TErrorPattern;
  LearnedClass: TErrorClassification;
  Key: string;
begin
  // 优先检查学习到的模�?
  Key := AError.ExceptionType + ':' + IntToStr(AError.HttpStatus);
  if FLearnedPatterns.TryGetValue(Key, LearnedClass) then
  begin
    Result := LearnedClass;
    Exit;
  end;
  
  // HTTP 状态码分类
  if AError.HttpStatus > 0 then
  begin
    Result := ClassifyByHttpStatus(AError.HttpStatus);
    if Result.Confidence > 0.8 then
      Exit;
  end;
  
  // 模式匹配
  Pattern := MatchPattern(AError);
  Result.Category := Pattern.Category;
  Result.Severity := Pattern.Severity;
  Result.Retryable := Pattern.Retryable;
  Result.SuggestedWaitMs := Pattern.BaseWaitMs;
  Result.Confidence := 0.75;
  
  // 生成原因说明
  case Result.Category of
    ecTransient:
      Result.Reason := '瞬态网络或连接错误';
    ecRateLimited:
      Result.Reason := '请求被限�?;
    ecTimeout:
      Result.Reason := '请求超时';
    ecServiceUnavailable:
      Result.Reason := '服务暂时不可�?;
    ecResourceExhausted:
      Result.Reason := '资源耗尽';
    ecBadRequest:
      Result.Reason := '请求参数错误';
    ecAuthentication:
      Result.Reason := '认证失败';
    ecPermission:
      Result.Reason := '权限不足';
  else
    Result.Reason := '未知错误类型';
  end;
end;

procedure TErrorClassifier.AddPattern(const APattern: TErrorPattern);
begin
  FPatterns.Add(APattern);
end;

procedure TErrorClassifier.LearnFromOutcome(const AError: TErrorInfo;
  ARetrySucceeded: Boolean);
var
  Key: string;
  Classification: TErrorClassification;
begin
  if not FLearningEnabled then Exit;
  
  Key := AError.ExceptionType + ':' + IntToStr(AError.HttpStatus);
  
  if FLearnedPatterns.TryGetValue(Key, Classification) then
  begin
    // 更新现有分类
    if ARetrySucceeded then
    begin
      Classification.Retryable := True;
      Classification.Confidence := Min(0.99, Classification.Confidence + 0.05);
    end
    else
    begin
      Classification.Confidence := Max(0.1, Classification.Confidence - 0.1);
      if Classification.Confidence < 0.3 then
        Classification.Retryable := False;
    end;
    FLearnedPatterns[Key] := Classification;
  end
  else if ARetrySucceeded then
  begin
    // 添加新的可重试分�?
    Classification := Classify(AError);
    Classification.Retryable := True;
    Classification.Confidence := 0.6;
    FLearnedPatterns.Add(Key, Classification);
  end;
end;

{$ENDREGION}

{$REGION 'TFixedDelayStrategy'}

constructor TFixedDelayStrategy.Create(ADelayMs, AMaxRetries: Integer);
begin
  inherited Create;
  FDelayMs := ADelayMs;
  FMaxRetries := AMaxRetries;
  FClassifier := TErrorClassifier.Create;
end;

function TFixedDelayStrategy.ShouldRetry(const AError: TErrorInfo;
  AAttempt: Integer): Boolean;
var
  Classification: TErrorClassification;
begin
  if AAttempt >= FMaxRetries then
    Exit(False);
  
  Classification := FClassifier.Classify(AError);
  Result := Classification.Retryable;
end;

function TFixedDelayStrategy.GetDelayMs(AAttempt: Integer): Integer;
begin
  Result := FDelayMs;
end;

function TFixedDelayStrategy.GetMaxRetries: Integer;
begin
  Result := FMaxRetries;
end;

procedure TFixedDelayStrategy.RecordSuccess(AAttempt: Integer; AElapsedMs: Integer);
begin
  // 固定策略不需要记�?
end;

procedure TFixedDelayStrategy.RecordFailure(const AError: TErrorInfo; AAttempt: Integer);
begin
  // 固定策略不需要记�?
end;

{$ENDREGION}

{$REGION 'TExponentialBackoffStrategy'}

constructor TExponentialBackoffStrategy.Create(const AConfig: TBackoffConfig;
  AMaxRetries: Integer);
begin
  inherited Create;
  FConfig := AConfig;
  FMaxRetries := AMaxRetries;
  FClassifier := TErrorClassifier.Create;
end;

function TExponentialBackoffStrategy.CalculateDelay(AAttempt: Integer): Integer;
var
  Delay: Double;
begin
  case FConfig.BackoffType of
    btFixed:
      Delay := FConfig.InitialDelayMs;
    btLinear:
      Delay := FConfig.InitialDelayMs * (AAttempt + 1);
    btExponential, btExponentialJitter:
      Delay := FConfig.InitialDelayMs * Power(FConfig.Multiplier, AAttempt);
    btFibonacci:
      begin
        // 斐波那契序列: 1, 1, 2, 3, 5, 8, 13...
        var Fib1: Integer := 1;
        var Fib2: Integer := 1;
        for var I := 0 to AAttempt - 1 do
        begin
          var Temp := Fib1 + Fib2;
          Fib1 := Fib2;
          Fib2 := Temp;
        end;
        Delay := FConfig.InitialDelayMs * Fib1;
      end;
    btDecorrelated:
      begin
        // 去相关抖�? delay = random_between(base, previous_delay * 3)
        if AAttempt = 0 then
          Delay := FConfig.InitialDelayMs
        else
          Delay := FConfig.InitialDelayMs + Random * 
            (FConfig.InitialDelayMs * Power(FConfig.Multiplier, AAttempt) * 3 - FConfig.InitialDelayMs);
      end;
  else
    Delay := FConfig.InitialDelayMs;
  end;
  
  Result := Round(Min(Delay, FConfig.MaxDelayMs));
end;

function TExponentialBackoffStrategy.AddJitter(ADelayMs: Integer): Integer;
var
  Jitter: Double;
begin
  if FConfig.JitterFactor <= 0 then
    Exit(ADelayMs);
  
  if FConfig.UseFullJitter then
    // Full jitter: [0, delay]
    Result := Random(ADelayMs + 1)
  else
  begin
    // Decorrelated jitter: [delay * (1-jitter), delay * (1+jitter)]
    Jitter := FConfig.JitterFactor * (Random * 2 - 1);
    Result := Round(ADelayMs * (1 + Jitter));
  end;
  
  Result := Max(1, Result);
end;

function TExponentialBackoffStrategy.ShouldRetry(const AError: TErrorInfo;
  AAttempt: Integer): Boolean;
var
  Classification: TErrorClassification;
begin
  if AAttempt >= FMaxRetries then
    Exit(False);
  
  Classification := FClassifier.Classify(AError);
  Result := Classification.Retryable;
end;

function TExponentialBackoffStrategy.GetDelayMs(AAttempt: Integer): Integer;
begin
  Result := CalculateDelay(AAttempt);
  
  if FConfig.BackoffType in [btExponentialJitter, btDecorrelated] then
    Result := AddJitter(Result);
end;

function TExponentialBackoffStrategy.GetMaxRetries: Integer;
begin
  Result := FMaxRetries;
end;

procedure TExponentialBackoffStrategy.RecordSuccess(AAttempt: Integer;
  AElapsedMs: Integer);
begin
  // 可以用于统计
end;

procedure TExponentialBackoffStrategy.RecordFailure(const AError: TErrorInfo;
  AAttempt: Integer);
begin
  // 可以用于学习
end;

{$ENDREGION}

{$REGION 'TAdaptiveRetryStrategy'}

constructor TAdaptiveRetryStrategy.Create(const AConfig: TRetryConfig);
begin
  inherited Create;
  FBaseConfig := AConfig;
  FClassifier := TErrorClassifier.Create;
  FSuccessRates := TDictionary<string, Double>.Create;
  FAverageDelays := TDictionary<string, Double>.Create;
  FRecentErrors := TList<TErrorInfo>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TAdaptiveRetryStrategy.Destroy;
begin
  FLock.Free;
  FRecentErrors.Free;
  FAverageDelays.Free;
  FSuccessRates.Free;
  FClassifier.Free;
  inherited;
end;

function TAdaptiveRetryStrategy.GetServiceKey(const AError: TErrorInfo): string;
begin
  if AError.ServiceName <> '' then
    Result := AError.ServiceName
  else
    Result := 'default';
end;

function TAdaptiveRetryStrategy.CalculateAdaptiveDelay(const AError: TErrorInfo;
  AAttempt: Integer): Integer;
var
  BaseDelay: Double;
  SuccessRate, AverageDelay: Double;
  ServiceKey: string;
  Classification: TErrorClassification;
begin
  ServiceKey := GetServiceKey(AError);
  Classification := FClassifier.Classify(AError);
  
  // 基础延迟
  BaseDelay := FBaseConfig.Backoff.InitialDelayMs * 
    Power(FBaseConfig.Backoff.Multiplier, AAttempt);
  
  FLock.Enter;
  try
    // 根据成功率调�?
    if FSuccessRates.TryGetValue(ServiceKey, SuccessRate) then
    begin
      if SuccessRate < 0.3 then
        BaseDelay := BaseDelay * 2  // 成功率低，增加延�?
      else if SuccessRate > 0.8 then
        BaseDelay := BaseDelay * 0.7;  // 成功率高，减少延�?
    end;
    
    // 根据历史平均延迟调整
    if FAverageDelays.TryGetValue(ServiceKey, AverageDelay) then
    begin
      if BaseDelay < AverageDelay * 0.5 then
        BaseDelay := AverageDelay * 0.5;
    end;
  finally
    FLock.Leave;
  end;
  
  // 根据错误分类调整
  if Classification.SuggestedWaitMs > 0 then
    BaseDelay := Max(BaseDelay, Classification.SuggestedWaitMs);
  
  // 限制最大延�?
  Result := Round(Min(BaseDelay, FBaseConfig.Backoff.MaxDelayMs));
end;

function TAdaptiveRetryStrategy.CalculateAdaptiveMaxRetries(
  const AError: TErrorInfo): Integer;
var
  ServiceKey: string;
  SuccessRate: Double;
begin
  Result := FBaseConfig.MaxRetries;
  ServiceKey := GetServiceKey(AError);
  
  FLock.Enter;
  try
    if FSuccessRates.TryGetValue(ServiceKey, SuccessRate) then
    begin
      if SuccessRate < 0.2 then
        Result := Max(1, Result div 2)  // 成功率很低，减少重试
      else if SuccessRate > 0.9 then
        Result := Result + 2;  // 成功率很高，可以多试几次
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAdaptiveRetryStrategy.UpdateSuccessRate(const AServiceKey: string;
  ASuccess: Boolean);
var
  CurrentRate: Double;
  Alpha: Double;
begin
  Alpha := 0.1;  // 学习�?
  
  FLock.Enter;
  try
    if not FSuccessRates.TryGetValue(AServiceKey, CurrentRate) then
      CurrentRate := 0.5;
    
    if ASuccess then
      CurrentRate := CurrentRate + Alpha * (1 - CurrentRate)
    else
      CurrentRate := CurrentRate - Alpha * CurrentRate;
    
    FSuccessRates.AddOrSetValue(AServiceKey, CurrentRate);
  finally
    FLock.Leave;
  end;
end;

function TAdaptiveRetryStrategy.ShouldRetry(const AError: TErrorInfo;
  AAttempt: Integer): Boolean;
var
  Classification: TErrorClassification;
  MaxRetries: Integer;
  Category: TErrorCategory;
begin
  MaxRetries := CalculateAdaptiveMaxRetries(AError);
  
  if AAttempt >= MaxRetries then
    Exit(False);
  
  Classification := FClassifier.Classify(AError);
  
  // 检查是否在不可重试列表�?
  for Category in FBaseConfig.NonRetryableCategories do
  begin
    if Classification.Category = Category then
      Exit(False);
  end;
  
  // 检查是否在可重试列表中
  if Length(FBaseConfig.RetryableCategories) > 0 then
  begin
    Result := False;
    for Category in FBaseConfig.RetryableCategories do
    begin
      if Classification.Category = Category then
      begin
        Result := True;
        Break;
      end;
    end;
  end
  else
    Result := Classification.Retryable;
end;

function TAdaptiveRetryStrategy.GetDelayMs(AAttempt: Integer): Integer;
var
  Error: TErrorInfo;
begin
  // 简化版本，实际应该传入错误信息
  Error := Default(TErrorInfo);
  Result := CalculateAdaptiveDelay(Error, AAttempt);
end;

function TAdaptiveRetryStrategy.GetMaxRetries: Integer;
begin
  Result := FBaseConfig.MaxRetries;
end;

procedure TAdaptiveRetryStrategy.RecordSuccess(AAttempt: Integer;
  AElapsedMs: Integer);
begin
  UpdateSuccessRate('default', True);
end;

procedure TAdaptiveRetryStrategy.RecordFailure(const AError: TErrorInfo;
  AAttempt: Integer);
begin
  UpdateSuccessRate(GetServiceKey(AError), False);
  
  FLock.Enter;
  try
    FRecentErrors.Add(AError);
    while FRecentErrors.Count > 100 do
      FRecentErrors.Delete(0);
  finally
    FLock.Leave;
  end;
end;

function TAdaptiveRetryStrategy.GetSuccessRate(const AServiceName: string): Double;
begin
  FLock.Enter;
  try
    if not FSuccessRates.TryGetValue(AServiceName, Result) then
      Result := 0.5;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TCircuitBreaker'}

constructor TCircuitBreaker.Create(const AName: string;
  const AConfig: TCircuitBreakerConfig);
begin
  inherited Create;
  FName := AName;
  FConfig := AConfig;
  FState := csClosed;
  FFailureCount := 0;
  FSuccessCount := 0;
  FRequestCount := 0;
  FStateChangedTime := Now;
  FLock := TCriticalSection.Create;
  FRequestHistory := TList<TPair<TDateTime, Boolean>>.Create;
end;

destructor TCircuitBreaker.Destroy;
begin
  FRequestHistory.Free;
  FLock.Free;
  inherited;
end;

procedure TCircuitBreaker.TransitionTo(ANewState: TCircuitState);
begin
  if FState <> ANewState then
  begin
    FState := ANewState;
    FStateChangedTime := Now;
    
    if ANewState = csClosed then
    begin
      FFailureCount := 0;
      FSuccessCount := 0;
    end
    else if ANewState = csHalfOpen then
      FSuccessCount := 0;
    
    if Assigned(FEventHandler) then
      FEventHandler(cbeStateChanged, FState);
  end;
end;

procedure TCircuitBreaker.CleanupHistory;
var
  CutoffTime: TDateTime;
begin
  CutoffTime := IncMilliSecond(Now, -FConfig.SamplingWindowMs);
  
  while FRequestHistory.Count > 0 do
  begin
    if FRequestHistory[0].Key < CutoffTime then
      FRequestHistory.Delete(0)
    else
      Break;
  end;
end;

function TCircuitBreaker.CalculateFailureRate: Double;
var
  Pair: TPair<TDateTime, Boolean>;
  TotalCount, FailureCount: Integer;
begin
  FLock.Enter;
  try
    CleanupHistory;
    
    TotalCount := 0;
    FailureCount := 0;
    
    for Pair in FRequestHistory do
    begin
      Inc(TotalCount);
      if not Pair.Value then
        Inc(FailureCount);
    end;
    
    if TotalCount > 0 then
      Result := FailureCount / TotalCount
    else
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

function TCircuitBreaker.IsTimeoutExpired: Boolean;
begin
  Result := MilliSecondsBetween(Now, FStateChangedTime) >= FConfig.TimeoutMs;
end;

function TCircuitBreaker.AllowRequest: Boolean;
begin
  FLock.Enter;
  try
    Inc(FRequestCount);
    
    case FState of
      csClosed:
        Result := True;
        
      csOpen:
        begin
          if IsTimeoutExpired then
          begin
            TransitionTo(csHalfOpen);
            Result := True;
          end
          else
          begin
            Result := False;
            if Assigned(FEventHandler) then
              FEventHandler(cbeRequestRejected, FState);
          end;
        end;
        
      csHalfOpen:
        // 半开状态只允许有限的测试请�?
        Result := FSuccessCount < FConfig.SuccessThreshold;
    else
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCircuitBreaker.RecordSuccess;
begin
  FLock.Enter;
  try
    FRequestHistory.Add(TPair<TDateTime, Boolean>.Create(Now, True));
    Inc(FSuccessCount);
    
    if Assigned(FEventHandler) then
      FEventHandler(cbeRequestSucceeded, FState);
    
    case FState of
      csHalfOpen:
        if FSuccessCount >= FConfig.SuccessThreshold then
          TransitionTo(csClosed);
      csClosed:
        FFailureCount := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCircuitBreaker.RecordFailure;
begin
  FLock.Enter;
  try
    FRequestHistory.Add(TPair<TDateTime, Boolean>.Create(Now, False));
    FLastFailureTime := Now;
    Inc(FFailureCount);
    
    if Assigned(FEventHandler) then
      FEventHandler(cbeRequestFailed, FState);
    
    case FState of
      csClosed:
        begin
          CleanupHistory;
          if FRequestHistory.Count >= FConfig.MinimumRequests then
          begin
            if (FFailureCount >= FConfig.FailureThreshold) or
               (CalculateFailureRate >= FConfig.FailureRateThreshold) then
              TransitionTo(csOpen);
          end;
        end;
      csHalfOpen:
        TransitionTo(csOpen);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCircuitBreaker.Reset;
begin
  FLock.Enter;
  try
    FState := csClosed;
    FFailureCount := 0;
    FSuccessCount := 0;
    FRequestCount := 0;
    FRequestHistory.Clear;
    FStateChangedTime := Now;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TCircuitBreakerRegistry'}

constructor TCircuitBreakerRegistry.Create;
begin
  inherited Create;
  FCircuitBreakers := TDictionary<string, TCircuitBreaker>.Create;
  FLock := TCriticalSection.Create;
  
  // 默认配置
  FDefaultConfig.FailureThreshold := 5;
  FDefaultConfig.SuccessThreshold := 3;
  FDefaultConfig.TimeoutMs := 30000;
  FDefaultConfig.SamplingWindowMs := 60000;
  FDefaultConfig.MinimumRequests := 10;
  FDefaultConfig.FailureRateThreshold := 0.5;
end;

destructor TCircuitBreakerRegistry.Destroy;
var
  CB: TCircuitBreaker;
begin
  for CB in FCircuitBreakers.Values do
    CB.Free;
  FCircuitBreakers.Free;
  FLock.Free;
  inherited;
end;

function TCircuitBreakerRegistry.GetOrCreate(const AName: string): TCircuitBreaker;
begin
  Result := GetOrCreateWithConfig(AName, FDefaultConfig);
end;

function TCircuitBreakerRegistry.GetOrCreateWithConfig(const AName: string;
  const AConfig: TCircuitBreakerConfig): TCircuitBreaker;
begin
  FLock.Enter;
  try
    if not FCircuitBreakers.TryGetValue(AName, Result) then
    begin
      Result := TCircuitBreaker.Create(AName, AConfig);
      FCircuitBreakers.Add(AName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCircuitBreakerRegistry.Remove(const AName: string);
var
  CB: TCircuitBreaker;
begin
  FLock.Enter;
  try
    if FCircuitBreakers.TryGetValue(AName, CB) then
    begin
      FCircuitBreakers.Remove(AName);
      CB.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TCircuitBreakerRegistry.GetAll: TArray<TCircuitBreaker>;
var
  List: TList<TCircuitBreaker>;
  CB: TCircuitBreaker;
begin
  List := TList<TCircuitBreaker>.Create;
  try
    FLock.Enter;
    try
      for CB in FCircuitBreakers.Values do
        List.Add(CB);
    finally
      FLock.Leave;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TRetryExecutor'}

constructor TRetryExecutor.Create(AStrategy: IRetryStrategy;
  ACircuitBreaker: TCircuitBreaker);
begin
  inherited Create;
  FStrategy := AStrategy;
  FCircuitBreaker := ACircuitBreaker;
  FErrorExtractor := DefaultErrorExtractor;
end;

function TRetryExecutor.DefaultErrorExtractor(E: Exception): TErrorInfo;
begin
  Result.ErrorCode := 0;
  Result.ErrorMessage := E.Message;
  Result.ExceptionType := E.ClassName;
  Result.StackTrace := '';
  Result.HttpStatus := 0;
  Result.ServiceName := '';
  Result.Timestamp := Now;
end;

function TRetryExecutor.Execute<T>(AOperation: TRetryableOperation<T>): TRetryResult<T>;
var
  Attempt: Integer;
  StartTime, AttemptStart: TDateTime;
  AttemptRecord: TRetryAttempt;
  Attempts: TList<TRetryAttempt>;
  DelayMs: Integer;
  ErrorInfo: TErrorInfo;
begin
  Attempts := TList<TRetryAttempt>.Create;
  try
    StartTime := Now;
    Attempt := 0;
    Result.Success := False;
    
    while Attempt <= FStrategy.GetMaxRetries do
    begin
      // 检查熔断器
      if Assigned(FCircuitBreaker) and not FCircuitBreaker.AllowRequest then
      begin
        ErrorInfo.ErrorCode := -1;
        ErrorInfo.ErrorMessage := '熔断器已打开';
        ErrorInfo.ExceptionType := 'ECircuitOpen';
        ErrorInfo.Timestamp := Now;
        Result.FinalError := ErrorInfo;
        Break;
      end;
      
      AttemptStart := Now;
      AttemptRecord.AttemptNumber := Attempt;
      AttemptRecord.StartTime := AttemptStart;
      
      if Attempt > 0 then
      begin
        DelayMs := FStrategy.GetDelayMs(Attempt - 1);
        AttemptRecord.DelayBeforeMs := DelayMs;
        Sleep(DelayMs);
      end
      else
        AttemptRecord.DelayBeforeMs := 0;
      
      try
        Result.Value := AOperation();
        
        AttemptRecord.EndTime := Now;
        AttemptRecord.DurationMs := MilliSecondsBetween(AttemptRecord.EndTime, AttemptStart);
        AttemptRecord.Success := True;
        Attempts.Add(AttemptRecord);
        
        Result.Success := True;
        FStrategy.RecordSuccess(Attempt, AttemptRecord.DurationMs);
        
        if Assigned(FCircuitBreaker) then
          FCircuitBreaker.RecordSuccess;
        
        Break;
      except
        on E: Exception do
        begin
          ErrorInfo := FErrorExtractor(E);
          
          AttemptRecord.EndTime := Now;
          AttemptRecord.DurationMs := MilliSecondsBetween(AttemptRecord.EndTime, AttemptStart);
          AttemptRecord.Success := False;
          AttemptRecord.Error := ErrorInfo;
          Attempts.Add(AttemptRecord);
          
          FStrategy.RecordFailure(ErrorInfo, Attempt);
          
          if Assigned(FCircuitBreaker) then
            FCircuitBreaker.RecordFailure;
          
          if Assigned(FOnRetry) then
            FOnRetry(AttemptRecord);
          
          if not FStrategy.ShouldRetry(ErrorInfo, Attempt) then
          begin
            Result.FinalError := ErrorInfo;
            Break;
          end;
          
          Result.FinalError := ErrorInfo;
        end;
      end;
      
      Inc(Attempt);
    end;
    
    Result.TotalAttempts := Attempts.Count;
    Result.TotalDurationMs := MilliSecondsBetween(Now, StartTime);
    Result.Attempts := Attempts.ToArray;
  finally
    Attempts.Free;
  end;
end;

function TRetryExecutor.ExecuteAsync<T>(
  AOperation: TRetryableOperation<T>): TRetryResult<T>;
begin
  // 简化版本，实际应该使用异步执行
  Result := Execute<T>(AOperation);
end;

{$ENDREGION}

{$REGION 'TSmartStrategySelector'}

constructor TSmartStrategySelector.Create;
begin
  inherited Create;
  FHistoricalData := TDictionary<string, TList<TRetryAttempt>>.Create;
  FServiceCharacteristics := TDictionary<string, TServiceCharacteristics>.Create;
  FLock := TCriticalSection.Create;
  
  // 默认推荐
  FDefaultRecommendation.StrategyType := btExponentialJitter;
  FDefaultRecommendation.MaxRetries := 3;
  FDefaultRecommendation.InitialDelayMs := 1000;
  FDefaultRecommendation.MaxDelayMs := 30000;
  FDefaultRecommendation.Confidence := 0.5;
  FDefaultRecommendation.Reasoning := '默认策略';
end;

destructor TSmartStrategySelector.Destroy;
var
  List: TList<TRetryAttempt>;
begin
  for List in FHistoricalData.Values do
    List.Free;
  FHistoricalData.Free;
  FServiceCharacteristics.Free;
  FLock.Free;
  inherited;
end;

function TSmartStrategySelector.AnalyzeHistoricalData(
  const AServiceName: string): TStrategyRecommendation;
var
  History: TList<TRetryAttempt>;
  TotalAttempts, SuccessAttempts: Integer;
  TotalDelay: Integer;
  Attempt: TRetryAttempt;
  SuccessRate, AvgDelay: Double;
begin
  Result := FDefaultRecommendation;
  
  FLock.Enter;
  try
    if not FHistoricalData.TryGetValue(AServiceName, History) then
      Exit;
    
    if History.Count < 10 then
      Exit;
    
    TotalAttempts := 0;
    SuccessAttempts := 0;
    TotalDelay := 0;
    
    for Attempt in History do
    begin
      Inc(TotalAttempts);
      if Attempt.Success then
        Inc(SuccessAttempts);
      TotalDelay := TotalDelay + Attempt.DelayBeforeMs;
    end;
    
    SuccessRate := SuccessAttempts / TotalAttempts;
    AvgDelay := TotalDelay / TotalAttempts;
    
    // 根据成功率调整策�?
    if SuccessRate > 0.9 then
    begin
      Result.MaxRetries := 5;
      Result.InitialDelayMs := Round(AvgDelay * 0.8);
      Result.Reasoning := '高成功率，增加重试次�?;
    end
    else if SuccessRate < 0.3 then
    begin
      Result.MaxRetries := 2;
      Result.InitialDelayMs := Round(AvgDelay * 1.5);
      Result.StrategyType := btExponential;
      Result.Reasoning := '低成功率，减少重试并增加延迟';
    end
    else
    begin
      Result.MaxRetries := 3;
      Result.InitialDelayMs := Round(AvgDelay);
      Result.Reasoning := '中等成功率，使用平衡策略';
    end;
    
    Result.Confidence := Min(0.95, 0.5 + (History.Count / 100) * 0.45);
  finally
    FLock.Leave;
  end;
end;

function TSmartStrategySelector.ApplyHeuristics(
  const ACharacteristics: TServiceCharacteristics): TStrategyRecommendation;
begin
  Result := FDefaultRecommendation;
  
  // 根据服务特征调整
  if ACharacteristics.AverageLatencyMs > 5000 then
  begin
    // 慢速服务：更长的延迟，更少的重�?
    Result.InitialDelayMs := Round(ACharacteristics.AverageLatencyMs * 0.5);
    Result.MaxRetries := 2;
    Result.Reasoning := '慢速服务，减少重试';
  end;
  
  if ACharacteristics.FailureRate > 0.5 then
  begin
    // 不稳定服务：更保守的策略
    Result.StrategyType := btExponential;
    Result.MaxDelayMs := 60000;
    Result.Reasoning := '不稳定服务，保守策略';
  end;
  
  if not ACharacteristics.IsIdempotent then
  begin
    // 非幂等操作：限制重试
    Result.MaxRetries := 1;
    Result.Reasoning := '非幂等操作，限制重试';
  end;
  
  if ACharacteristics.HasSideEffects then
  begin
    // 有副作用的操作：更谨�?
    Result.MaxRetries := Min(2, Result.MaxRetries);
    Result.Reasoning := '有副作用，谨慎重�?;
  end;
  
  if ACharacteristics.CriticalityLevel > 3 then
  begin
    // 高关键性：更多重试机会
    Result.MaxRetries := Max(5, Result.MaxRetries);
    Result.Reasoning := '高关键性，增加重试';
  end;
  
  Result.Confidence := 0.7;
end;

procedure TSmartStrategySelector.RecordAttempt(const AServiceName: string;
  const AAttempt: TRetryAttempt);
var
  History: TList<TRetryAttempt>;
begin
  FLock.Enter;
  try
    if not FHistoricalData.TryGetValue(AServiceName, History) then
    begin
      History := TList<TRetryAttempt>.Create;
      FHistoricalData.Add(AServiceName, History);
    end;
    
    History.Add(AAttempt);
    
    // 保留最�?1000 条记�?
    while History.Count > 1000 do
      History.Delete(0);
  finally
    FLock.Leave;
  end;
end;

procedure TSmartStrategySelector.SetServiceCharacteristics(
  const ACharacteristics: TServiceCharacteristics);
begin
  FLock.Enter;
  try
    FServiceCharacteristics.AddOrSetValue(ACharacteristics.ServiceName, ACharacteristics);
  finally
    FLock.Leave;
  end;
end;

function TSmartStrategySelector.Recommend(
  const AServiceName: string): TStrategyRecommendation;
var
  Characteristics: TServiceCharacteristics;
  HistoricalRec, HeuristicRec: TStrategyRecommendation;
begin
  // 基于历史数据的推�?
  HistoricalRec := AnalyzeHistoricalData(AServiceName);
  
  // 基于服务特征的推�?
  FLock.Enter;
  try
    if FServiceCharacteristics.TryGetValue(AServiceName, Characteristics) then
      HeuristicRec := ApplyHeuristics(Characteristics)
    else
      HeuristicRec := FDefaultRecommendation;
  finally
    FLock.Leave;
  end;
  
  // 合并推荐（优先历史数据）
  if HistoricalRec.Confidence > HeuristicRec.Confidence then
    Result := HistoricalRec
  else
    Result := HeuristicRec;
end;

function TSmartStrategySelector.CreateStrategy(
  const ARecommendation: TStrategyRecommendation): IRetryStrategy;
var
  Config: TBackoffConfig;
begin
  Config.BackoffType := ARecommendation.StrategyType;
  Config.InitialDelayMs := ARecommendation.InitialDelayMs;
  Config.MaxDelayMs := ARecommendation.MaxDelayMs;
  Config.Multiplier := 2.0;
  Config.JitterFactor := 0.2;
  Config.UseFullJitter := False;
  
  Result := TExponentialBackoffStrategy.Create(Config, ARecommendation.MaxRetries);
end;

{$ENDREGION}

{$REGION 'TSmartRetryService'}

constructor TSmartRetryService.Create(const AConfig: TRetryServiceConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FClassifier := TErrorClassifier.Create;
  FStrategySelector := TSmartStrategySelector.Create;
  FCircuitRegistry := TCircuitBreakerRegistry.Create;
  FStrategies := TDictionary<string, IRetryStrategy>.Create;
  FStatistics := TDictionary<string, TRetryStatistics>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TSmartRetryService.Destroy;
begin
  FLock.Free;
  FStatistics.Free;
  FStrategies.Free;
  FCircuitRegistry.Free;
  FStrategySelector.Free;
  FClassifier.Free;
  inherited;
end;

function TSmartRetryService.GetOrCreateStrategy(
  const AServiceName: string): IRetryStrategy;
var
  Recommendation: TStrategyRecommendation;
begin
  FLock.Enter;
  try
    if not FStrategies.TryGetValue(AServiceName, Result) then
    begin
      if FConfig.EnableAdaptiveStrategy then
      begin
        Recommendation := FStrategySelector.Recommend(AServiceName);
        Result := FStrategySelector.CreateStrategy(Recommendation);
      end
      else
      begin
        Result := TFixedDelayStrategy.Create(1000, FConfig.GlobalMaxRetries);
      end;
      FStrategies.Add(AServiceName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TSmartRetryService.GetOrCreateCircuitBreaker(
  const AServiceName: string): TCircuitBreaker;
begin
  if FConfig.EnableCircuitBreaker then
    Result := FCircuitRegistry.GetOrCreate(AServiceName)
  else
    Result := nil;
end;

procedure TSmartRetryService.UpdateStatistics(const AServiceName: string;
  const AResult: TRetryResult<Variant>);
var
  Stats: TRetryStatistics;
begin
  FLock.Enter;
  try
    if not FStatistics.TryGetValue(AServiceName, Stats) then
    begin
      Stats.TotalRequests := 0;
      Stats.TotalRetries := 0;
      Stats.SuccessfulRetries := 0;
      Stats.FailedRetries := 0;
    end;
    
    Inc(Stats.TotalRequests);
    Stats.TotalRetries := Stats.TotalRetries + AResult.TotalAttempts - 1;
    
    if AResult.Success then
    begin
      if AResult.TotalAttempts > 1 then
        Inc(Stats.SuccessfulRetries);
    end
    else
      Inc(Stats.FailedRetries);
    
    if Stats.TotalRequests > 0 then
    begin
      Stats.AverageRetriesPerRequest := Stats.TotalRetries / Stats.TotalRequests;
      Stats.SuccessRate := (Stats.TotalRequests - Stats.FailedRetries) / Stats.TotalRequests;
    end;
    
    FStatistics.AddOrSetValue(AServiceName, Stats);
  finally
    FLock.Leave;
  end;
end;

function TSmartRetryService.Execute<T>(const AServiceName: string;
  AOperation: TRetryableOperation<T>): TRetryResult<T>;
var
  Strategy: IRetryStrategy;
  CircuitBreaker: TCircuitBreaker;
  Executor: TRetryExecutor;
  Attempt: TRetryAttempt;
begin
  Strategy := GetOrCreateStrategy(AServiceName);
  CircuitBreaker := GetOrCreateCircuitBreaker(AServiceName);
  
  Executor := TRetryExecutor.Create(Strategy, CircuitBreaker);
  try
    Executor.OnRetry := procedure(A: TRetryAttempt)
    begin
      FStrategySelector.RecordAttempt(AServiceName, A);
    end;
    
    Result := Executor.Execute<T>(AOperation);
    
    // 记录最终结�?
    for Attempt in Result.Attempts do
      FStrategySelector.RecordAttempt(AServiceName, Attempt);
  finally
    Executor.Free;
  end;
end;

function TSmartRetryService.ShouldRetry(const AServiceName: string;
  const AError: TErrorInfo; AAttempt: Integer): Boolean;
var
  Strategy: IRetryStrategy;
begin
  Strategy := GetOrCreateStrategy(AServiceName);
  Result := Strategy.ShouldRetry(AError, AAttempt);
end;

function TSmartRetryService.GetDelay(const AServiceName: string;
  AAttempt: Integer): Integer;
var
  Strategy: IRetryStrategy;
begin
  Strategy := GetOrCreateStrategy(AServiceName);
  Result := Strategy.GetDelayMs(AAttempt);
end;

procedure TSmartRetryService.SetServiceConfig(const AServiceName: string;
  const AConfig: TRetryConfig);
var
  Strategy: IRetryStrategy;
begin
  Strategy := TAdaptiveRetryStrategy.Create(AConfig);
  
  FLock.Enter;
  try
    FStrategies.AddOrSetValue(AServiceName, Strategy);
  finally
    FLock.Leave;
  end;
end;

function TSmartRetryService.GetStatistics(const AServiceName: string): TRetryStatistics;
begin
  FLock.Enter;
  try
    if not FStatistics.TryGetValue(AServiceName, Result) then
    begin
      Result.TotalRequests := 0;
      Result.TotalRetries := 0;
      Result.SuccessfulRetries := 0;
      Result.FailedRetries := 0;
      Result.AverageRetriesPerRequest := 0;
      Result.AverageDelayMs := 0;
      Result.SuccessRate := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

function TSmartRetryService.GetAllStatistics: TDictionary<string, TRetryStatistics>;
var
  Key: string;
begin
  Result := TDictionary<string, TRetryStatistics>.Create;
  
  FLock.Enter;
  try
    for Key in FStatistics.Keys do
      Result.Add(Key, FStatistics[Key]);
  finally
    FLock.Leave;
  end;
end;

procedure TSmartRetryService.ReportFeedback(const AServiceName: string;
  const AError: TErrorInfo; ARetrySucceeded: Boolean);
begin
  if FConfig.EnableLearning then
    FClassifier.LearnFromOutcome(AError, ARetrySucceeded);
end;

{$ENDREGION}

{$REGION 'TRetryStrategyBuilder'}

constructor TRetryStrategyBuilder.Create;
begin
  inherited Create;
  FMaxRetries := 3;
  FBackoffType := btExponentialJitter;
  FInitialDelayMs := 1000;
  FMaxDelayMs := 30000;
  FMultiplier := 2.0;
  FJitterFactor := 0.2;
  FRetryableCategories := TList<TErrorCategory>.Create;
  FNonRetryableCategories := TList<TErrorCategory>.Create;
  
  // 默认不可重试类别
  FNonRetryableCategories.Add(ecBadRequest);
  FNonRetryableCategories.Add(ecAuthentication);
  FNonRetryableCategories.Add(ecPermission);
end;

destructor TRetryStrategyBuilder.Destroy;
begin
  FNonRetryableCategories.Free;
  FRetryableCategories.Free;
  inherited;
end;

function TRetryStrategyBuilder.WithMaxRetries(AMaxRetries: Integer): TRetryStrategyBuilder;
begin
  FMaxRetries := AMaxRetries;
  Result := Self;
end;

function TRetryStrategyBuilder.WithBackoffType(AType: TBackoffType): TRetryStrategyBuilder;
begin
  FBackoffType := AType;
  Result := Self;
end;

function TRetryStrategyBuilder.WithInitialDelay(ADelayMs: Integer): TRetryStrategyBuilder;
begin
  FInitialDelayMs := ADelayMs;
  Result := Self;
end;

function TRetryStrategyBuilder.WithMaxDelay(AMaxDelayMs: Integer): TRetryStrategyBuilder;
begin
  FMaxDelayMs := AMaxDelayMs;
  Result := Self;
end;

function TRetryStrategyBuilder.WithMultiplier(AMultiplier: Double): TRetryStrategyBuilder;
begin
  FMultiplier := AMultiplier;
  Result := Self;
end;

function TRetryStrategyBuilder.WithJitter(AJitterFactor: Double): TRetryStrategyBuilder;
begin
  FJitterFactor := AJitterFactor;
  Result := Self;
end;

function TRetryStrategyBuilder.RetryOn(ACategory: TErrorCategory): TRetryStrategyBuilder;
begin
  if FRetryableCategories.IndexOf(ACategory) < 0 then
    FRetryableCategories.Add(ACategory);
  Result := Self;
end;

function TRetryStrategyBuilder.DoNotRetryOn(ACategory: TErrorCategory): TRetryStrategyBuilder;
begin
  if FNonRetryableCategories.IndexOf(ACategory) < 0 then
    FNonRetryableCategories.Add(ACategory);
  Result := Self;
end;

function TRetryStrategyBuilder.Build: IRetryStrategy;
var
  Config: TRetryConfig;
begin
  Config := BuildConfig;
  Result := TAdaptiveRetryStrategy.Create(Config);
end;

function TRetryStrategyBuilder.BuildConfig: TRetryConfig;
begin
  Result.MaxRetries := FMaxRetries;
  Result.Backoff.BackoffType := FBackoffType;
  Result.Backoff.InitialDelayMs := FInitialDelayMs;
  Result.Backoff.MaxDelayMs := FMaxDelayMs;
  Result.Backoff.Multiplier := FMultiplier;
  Result.Backoff.JitterFactor := FJitterFactor;
  Result.Backoff.UseFullJitter := False;
  Result.RetryableCategories := FRetryableCategories.ToArray;
  Result.NonRetryableCategories := FNonRetryableCategories.ToArray;
  Result.TotalTimeoutMs := 120000;
  Result.PerAttemptTimeoutMs := 30000;
end;

{$ENDREGION}

end.
