unit UniFlow.AI.AnomalyDetection;

{*******************************************************************************
  UniFlow AI 异常检测引�?
  
  功能:
  - 工作流执行异常检�?
  - 时序异常分析
  - 多维度指标监�?
  - 自适应阈值学�?
  - 异常根因分析
  
  作�? UniFlow Team
  日期: 2024-01
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.Math, System.DateUtils, System.SyncObjs;

type
  {$REGION '基础类型'}
  
  /// <summary>异常类型</summary>
  TAnomalyType = (
    atLatencySpike,       // 延迟尖峰
    atErrorBurst,         // 错误爆发
    atResourceExhaustion, // 资源耗尽
    atThroughputDrop,     // 吞吐量下�?
    atPatternDeviation,   // 模式偏离
    atCyclicAnomaly,      // 周期性异�?
    atTrendAnomaly,       // 趋势异常
    atContextualAnomaly,  // 上下文异�?
    atCollectiveAnomaly,  // 集体异常
    atUnknown             // 未知
  );
  
  /// <summary>异常严重程度</summary>
  TAnomalySeverity = (
    asInfo,       // 信息
    asWarning,    // 警告
    asCritical,   // 严重
    asEmergency   // 紧�?
  );
  
  /// <summary>检测到的异�?/summary>
  TDetectedAnomaly = record
    Id: string;
    AnomalyType: TAnomalyType;
    Severity: TAnomalySeverity;
    DetectedAt: TDateTime;
    WorkflowId: string;
    StepId: string;
    MetricName: string;
    ObservedValue: Double;
    ExpectedValue: Double;
    Deviation: Double;
    ZScore: Double;
    Confidence: Double;
    Description: string;
    PossibleCauses: TArray<string>;
    Recommendations: TArray<string>;
  end;
  
  /// <summary>时序数据�?/summary>
  TTimeSeriesPoint = record
    Timestamp: TDateTime;
    Value: Double;
    Labels: TDictionary<string, string>;
  end;
  
  /// <summary>统计摘要</summary>
  TStatisticsSummary = record
    Count: Integer;
    Sum: Double;
    Mean: Double;
    Variance: Double;
    StdDev: Double;
    Min: Double;
    Max: Double;
    Median: Double;
    P95: Double;
    P99: Double;
  end;
  
  {$ENDREGION}
  
  {$REGION '统计分析�?}
  
  /// <summary>滑动窗口统计</summary>
  TSlidingWindowStats = class
  private
    FWindow: TList<Double>;
    FWindowSize: Integer;
    FSorted: TList<Double>;
    FNeedSort: Boolean;
    
    procedure EnsureSorted;
    function GetPercentile(P: Double): Double;
  public
    constructor Create(AWindowSize: Integer = 100);
    destructor Destroy; override;
    
    procedure Add(AValue: Double);
    procedure Clear;
    
    function GetMean: Double;
    function GetVariance: Double;
    function GetStdDev: Double;
    function GetMin: Double;
    function GetMax: Double;
    function GetMedian: Double;
    function GetP95: Double;
    function GetP99: Double;
    function GetZScore(AValue: Double): Double;
    function GetSummary: TStatisticsSummary;
    
    property Count: Integer read FWindowSize;
  end;
  
  /// <summary>指数加权移动平均</summary>
  TEWMACalculator = class
  private
    FAlpha: Double;
    FValue: Double;
    FVariance: Double;
    FInitialized: Boolean;
  public
    constructor Create(AAlpha: Double = 0.3);
    
    procedure Update(AValue: Double);
    procedure Reset;
    
    property Value: Double read FValue;
    property Variance: Double read FVariance;
    property StdDev: Double read GetStdDev;
    
    function GetStdDev: Double;
    function GetUpperBound(ASigma: Double = 3): Double;
    function GetLowerBound(ASigma: Double = 3): Double;
    function IsAnomaly(AValue: Double; ASigma: Double = 3): Boolean;
  end;
  
  {$ENDREGION}
  
  {$REGION '异常检测算�?}
  
  /// <summary>基础检测器接口</summary>
  IAnomalyDetector = interface
    ['{8B5D4A2E-1C3F-4E8D-9A6B-7D2E3F4C5A8B}']
    function Detect(const AValue: Double; const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TTimeSeriesPoint>);
    procedure Reset;
  end;
  
  /// <summary>Z-Score 检测器</summary>
  TZScoreDetector = class(TInterfacedObject, IAnomalyDetector)
  private
    FStats: TSlidingWindowStats;
    FThreshold: Double;
    FMetricName: string;
    FWorkflowId: string;
  public
    constructor Create(const AMetricName: string; AThreshold: Double = 3.0;
      AWindowSize: Integer = 100);
    destructor Destroy; override;
    
    function Detect(const AValue: Double; const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TTimeSeriesPoint>);
    procedure Reset;
    
    property Threshold: Double read FThreshold write FThreshold;
    property WorkflowId: string read FWorkflowId write FWorkflowId;
  end;
  
  /// <summary>IQR (四分位距) 检测器</summary>
  TIQRDetector = class(TInterfacedObject, IAnomalyDetector)
  private
    FStats: TSlidingWindowStats;
    FMultiplier: Double;
    FMetricName: string;
    FWorkflowId: string;
    
    function GetQ1: Double;
    function GetQ3: Double;
    function GetIQR: Double;
  public
    constructor Create(const AMetricName: string; AMultiplier: Double = 1.5;
      AWindowSize: Integer = 100);
    destructor Destroy; override;
    
    function Detect(const AValue: Double; const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TTimeSeriesPoint>);
    procedure Reset;
  end;
  
  /// <summary>EWMA 检测器</summary>
  TEWMADetector = class(TInterfacedObject, IAnomalyDetector)
  private
    FEWMA: TEWMACalculator;
    FSigmaThreshold: Double;
    FMetricName: string;
    FWorkflowId: string;
  public
    constructor Create(const AMetricName: string; AAlpha: Double = 0.3;
      ASigmaThreshold: Double = 3.0);
    destructor Destroy; override;
    
    function Detect(const AValue: Double; const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TTimeSeriesPoint>);
    procedure Reset;
  end;
  
  /// <summary>Isolation Forest 检测器 (简化版)</summary>
  TIsolationForestDetector = class(TInterfacedObject, IAnomalyDetector)
  private
    FTrees: TList<TObject>;  // 简化的树结�?
    FNumTrees: Integer;
    FSampleSize: Integer;
    FContaminationRate: Double;
    FThreshold: Double;
    FMetricName: string;
    FWorkflowId: string;
    FTrainingData: TList<Double>;
    
    function ComputeAnomalyScore(const AValue: Double): Double;
    function PathLength(const AValue: Double; ATree: TObject): Double;
  public
    constructor Create(const AMetricName: string; ANumTrees: Integer = 100;
      ASampleSize: Integer = 256; AContaminationRate: Double = 0.1);
    destructor Destroy; override;
    
    function Detect(const AValue: Double; const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TTimeSeriesPoint>);
    procedure Reset;
    procedure BuildForest;
  end;
  
  /// <summary>季节性分解检测器</summary>
  TSeasonalDetector = class(TInterfacedObject, IAnomalyDetector)
  private
    FSeasonalPeriod: Integer;
    FSeasonalPattern: TArray<Double>;
    FTrend: TArray<Double>;
    FResiduals: TSlidingWindowStats;
    FSigmaThreshold: Double;
    FMetricName: string;
    FWorkflowId: string;
    FDataPoints: TList<TTimeSeriesPoint>;
    
    procedure DecomposeTimeSeries;
    function GetSeasonalComponent(const ATimestamp: TDateTime): Double;
    function GetTrendComponent(AIndex: Integer): Double;
  public
    constructor Create(const AMetricName: string; ASeasonalPeriod: Integer = 24;
      ASigmaThreshold: Double = 3.0);
    destructor Destroy; override;
    
    function Detect(const AValue: Double; const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TTimeSeriesPoint>);
    procedure Reset;
    
    property SeasonalPeriod: Integer read FSeasonalPeriod write FSeasonalPeriod;
  end;
  
  {$ENDREGION}
  
  {$REGION '多维度异常检�?}
  
  /// <summary>多指标数据点</summary>
  TMultiMetricPoint = record
    Timestamp: TDateTime;
    Metrics: TDictionary<string, Double>;
    WorkflowId: string;
    StepId: string;
  end;
  
  /// <summary>相关性矩�?/summary>
  TCorrelationMatrix = class
  private
    FMetricNames: TStringList;
    FMatrix: array of array of Double;
    FDataCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddMetric(const AName: string);
    procedure Update(const AMetrics: TDictionary<string, Double>);
    function GetCorrelation(const AMetric1, AMetric2: string): Double;
    function FindCorrelated(const AMetric: string; AThreshold: Double = 0.7): TArray<string>;
  end;
  
  /// <summary>多维度异常检测器</summary>
  TMultiDimensionalDetector = class
  private
    FDetectors: TDictionary<string, IAnomalyDetector>;
    FCorrelationMatrix: TCorrelationMatrix;
    FLock: TCriticalSection;
    
    function GetOrCreateDetector(const AMetricName: string): IAnomalyDetector;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddDetector(const AMetricName: string; ADetector: IAnomalyDetector);
    function Detect(const APoint: TMultiMetricPoint): TArray<TDetectedAnomaly>;
    procedure Train(const AData: TArray<TMultiMetricPoint>);
    procedure Reset;
    
    function AnalyzeCorrelation(const AAnomaly: TDetectedAnomaly): TArray<string>;
  end;
  
  {$ENDREGION}
  
  {$REGION '根因分析'}
  
  /// <summary>因果关系</summary>
  TCausalRelation = record
    SourceMetric: string;
    TargetMetric: string;
    Strength: Double;
    Lag: Integer;
  end;
  
  /// <summary>根因候�?/summary>
  TRootCauseCandidate = record
    Metric: string;
    Probability: Double;
    Evidence: TArray<string>;
    RelatedAnomalies: TArray<TDetectedAnomaly>;
  end;
  
  /// <summary>根因分析�?/summary>
  TRootCauseAnalyzer = class
  private
    FCausalGraph: TDictionary<string, TList<TCausalRelation>>;
    FRecentAnomalies: TList<TDetectedAnomaly>;
    FTimeWindow: Integer;  // �?
    
    function FindUpstreamCauses(const AMetric: string): TArray<string>;
    function ComputeCauseProbability(const ASource, ATarget: string;
      const AAnomalies: TArray<TDetectedAnomaly>): Double;
  public
    constructor Create(ATimeWindow: Integer = 300);
    destructor Destroy; override;
    
    procedure AddCausalRelation(const ARelation: TCausalRelation);
    procedure RecordAnomaly(const AAnomaly: TDetectedAnomaly);
    function Analyze(const AAnomaly: TDetectedAnomaly): TArray<TRootCauseCandidate>;
    procedure LearnCausalRelations(const AData: TArray<TMultiMetricPoint>);
  end;
  
  {$ENDREGION}
  
  {$REGION '自适应阈�?}
  
  /// <summary>阈值调整策�?/summary>
  TThresholdStrategy = (
    tsFixed,              // 固定阈�?
    tsPercentile,         // 百分�?
    tsMAD,                // 中位数绝对偏�?
    tsAdaptive            // 自适应
  );
  
  /// <summary>自适应阈值管理器</summary>
  TAdaptiveThresholdManager = class
  private
    FThresholds: TDictionary<string, Double>;
    FStrategy: TThresholdStrategy;
    FStats: TDictionary<string, TSlidingWindowStats>;
    FFalsePositiveRate: Double;
    FAdjustmentFactor: Double;
    
    function ComputeThreshold(const AMetric: string): Double;
  public
    constructor Create(AStrategy: TThresholdStrategy = tsAdaptive);
    destructor Destroy; override;
    
    procedure SetThreshold(const AMetric: string; AThreshold: Double);
    function GetThreshold(const AMetric: string): Double;
    procedure UpdateStats(const AMetric: string; AValue: Double);
    procedure ReportFalsePositive(const AMetric: string);
    procedure ReportTruePositive(const AMetric: string);
    procedure AdjustThresholds;
    
    property Strategy: TThresholdStrategy read FStrategy write FStrategy;
    property FalsePositiveRate: Double read FFalsePositiveRate;
  end;
  
  {$ENDREGION}
  
  {$REGION '异常检测服�?}
  
  /// <summary>异常检测配�?/summary>
  TAnomalyDetectionConfig = record
    EnableLatencyDetection: Boolean;
    EnableErrorDetection: Boolean;
    EnableThroughputDetection: Boolean;
    EnableSeasonalDetection: Boolean;
    EnableCorrelationAnalysis: Boolean;
    EnableRootCauseAnalysis: Boolean;
    DefaultSigmaThreshold: Double;
    AlertCooldownSeconds: Integer;
  end;
  
  /// <summary>异常告警</summary>
  TAnomalyAlert = record
    Anomaly: TDetectedAnomaly;
    AlertedAt: TDateTime;
    Acknowledged: Boolean;
    AcknowledgedBy: string;
    Resolved: Boolean;
    ResolvedAt: TDateTime;
    Notes: string;
  end;
  
  /// <summary>告警处理�?/summary>
  TAnomalyAlertHandler = reference to procedure(const AAlert: TAnomalyAlert);
  
  /// <summary>异常检测服�?/summary>
  TAnomalyDetectionService = class
  private
    FConfig: TAnomalyDetectionConfig;
    FMultiDetector: TMultiDimensionalDetector;
    FRootCauseAnalyzer: TRootCauseAnalyzer;
    FThresholdManager: TAdaptiveThresholdManager;
    FAlerts: TDictionary<string, TAnomalyAlert>;
    FAlertHandlers: TList<TAnomalyAlertHandler>;
    FLastAlertTime: TDictionary<string, TDateTime>;
    FLock: TCriticalSection;
    FEnabled: Boolean;
    
    procedure ProcessAnomaly(const AAnomaly: TDetectedAnomaly);
    function ShouldAlert(const AAnomaly: TDetectedAnomaly): Boolean;
    procedure TriggerAlert(const AAnomaly: TDetectedAnomaly);
    procedure NotifyHandlers(const AAlert: TAnomalyAlert);
  public
    constructor Create(const AConfig: TAnomalyDetectionConfig);
    destructor Destroy; override;
    
    procedure Start;
    procedure Stop;
    
    // 数据输入
    procedure RecordMetric(const AWorkflowId, AStepId, AMetricName: string;
      AValue: Double; ATimestamp: TDateTime);
    procedure RecordMultiMetrics(const AWorkflowId, AStepId: string;
      const AMetrics: TDictionary<string, Double>; ATimestamp: TDateTime);
    
    // 检测控�?
    function DetectNow(const AWorkflowId: string): TArray<TDetectedAnomaly>;
    procedure TrainModels(const AHistoricalData: TArray<TMultiMetricPoint>);
    
    // 告警管理
    procedure RegisterAlertHandler(AHandler: TAnomalyAlertHandler);
    procedure AcknowledgeAlert(const AAlertId, AUser: string);
    procedure ResolveAlert(const AAlertId: string; const ANotes: string);
    function GetActiveAlerts: TArray<TAnomalyAlert>;
    
    // 反馈
    procedure ReportFalsePositive(const AAnomalyId: string);
    procedure ReportTruePositive(const AAnomalyId: string);
    
    property Config: TAnomalyDetectionConfig read FConfig write FConfig;
    property Enabled: Boolean read FEnabled;
  end;
  
  {$ENDREGION}
  
  {$REGION '工作流异常监控器'}
  
  /// <summary>步骤执行指标</summary>
  TStepMetrics = record
    WorkflowId: string;
    StepId: string;
    ExecutionTime: Double;
    QueueWaitTime: Double;
    RetryCount: Integer;
    ErrorCount: Integer;
    MemoryUsage: Int64;
    CPUUsage: Double;
    Timestamp: TDateTime;
  end;
  
  /// <summary>工作流健康状�?/summary>
  TWorkflowHealthStatus = (
    whsHealthy,      // 健康
    whsDegraded,     // 性能下降
    whsUnhealthy,    // 不健�?
    whsCritical      // 严重
  );
  
  /// <summary>工作流健康报�?/summary>
  TWorkflowHealthReport = record
    WorkflowId: string;
    Status: TWorkflowHealthStatus;
    Score: Double;
    ActiveAnomalies: TArray<TDetectedAnomaly>;
    RecentErrors: Integer;
    AverageLatency: Double;
    P99Latency: Double;
    Throughput: Double;
    Recommendations: TArray<string>;
    GeneratedAt: TDateTime;
  end;
  
  /// <summary>工作流异常监控器</summary>
  TWorkflowAnomalyMonitor = class
  private
    FDetectionService: TAnomalyDetectionService;
    FWorkflowStats: TDictionary<string, TSlidingWindowStats>;
    FStepStats: TDictionary<string, TSlidingWindowStats>;
    FHealthReports: TDictionary<string, TWorkflowHealthReport>;
    FLock: TCriticalSection;
    
    function ComputeHealthScore(const AWorkflowId: string): Double;
    function DetermineHealthStatus(AScore: Double): TWorkflowHealthStatus;
    function GenerateRecommendations(const AWorkflowId: string;
      const AAnomalies: TArray<TDetectedAnomaly>): TArray<string>;
  public
    constructor Create(ADetectionService: TAnomalyDetectionService);
    destructor Destroy; override;
    
    procedure RecordStepExecution(const AMetrics: TStepMetrics);
    function GetHealthReport(const AWorkflowId: string): TWorkflowHealthReport;
    function GetAllHealthReports: TArray<TWorkflowHealthReport>;
    function CheckHealth(const AWorkflowId: string): TWorkflowHealthStatus;
    
    procedure StartMonitoring(const AWorkflowId: string);
    procedure StopMonitoring(const AWorkflowId: string);
  end;
  
  {$ENDREGION}

implementation

{$REGION 'TSlidingWindowStats'}

constructor TSlidingWindowStats.Create(AWindowSize: Integer);
begin
  inherited Create;
  FWindowSize := AWindowSize;
  FWindow := TList<Double>.Create;
  FSorted := TList<Double>.Create;
  FNeedSort := False;
end;

destructor TSlidingWindowStats.Destroy;
begin
  FSorted.Free;
  FWindow.Free;
  inherited;
end;

procedure TSlidingWindowStats.Add(AValue: Double);
begin
  if FWindow.Count >= FWindowSize then
    FWindow.Delete(0);
  FWindow.Add(AValue);
  FNeedSort := True;
end;

procedure TSlidingWindowStats.Clear;
begin
  FWindow.Clear;
  FSorted.Clear;
  FNeedSort := False;
end;

procedure TSlidingWindowStats.EnsureSorted;
var
  I: Integer;
begin
  if not FNeedSort then Exit;
  
  FSorted.Clear;
  for I := 0 to FWindow.Count - 1 do
    FSorted.Add(FWindow[I]);
  
  FSorted.Sort;
  FNeedSort := False;
end;

function TSlidingWindowStats.GetMean: Double;
var
  I: Integer;
  Sum: Double;
begin
  if FWindow.Count = 0 then Exit(0);
  
  Sum := 0;
  for I := 0 to FWindow.Count - 1 do
    Sum := Sum + FWindow[I];
  Result := Sum / FWindow.Count;
end;

function TSlidingWindowStats.GetVariance: Double;
var
  I: Integer;
  Mean, SumSq: Double;
begin
  if FWindow.Count < 2 then Exit(0);
  
  Mean := GetMean;
  SumSq := 0;
  for I := 0 to FWindow.Count - 1 do
    SumSq := SumSq + Sqr(FWindow[I] - Mean);
  Result := SumSq / (FWindow.Count - 1);
end;

function TSlidingWindowStats.GetStdDev: Double;
begin
  Result := Sqrt(GetVariance);
end;

function TSlidingWindowStats.GetMin: Double;
begin
  EnsureSorted;
  if FSorted.Count = 0 then Exit(0);
  Result := FSorted[0];
end;

function TSlidingWindowStats.GetMax: Double;
begin
  EnsureSorted;
  if FSorted.Count = 0 then Exit(0);
  Result := FSorted[FSorted.Count - 1];
end;

function TSlidingWindowStats.GetPercentile(P: Double): Double;
var
  Index: Double;
  Lower, Upper: Integer;
  Frac: Double;
begin
  EnsureSorted;
  if FSorted.Count = 0 then Exit(0);
  if FSorted.Count = 1 then Exit(FSorted[0]);
  
  Index := P * (FSorted.Count - 1);
  Lower := Trunc(Index);
  Upper := Min(Lower + 1, FSorted.Count - 1);
  Frac := Index - Lower;
  
  Result := FSorted[Lower] * (1 - Frac) + FSorted[Upper] * Frac;
end;

function TSlidingWindowStats.GetMedian: Double;
begin
  Result := GetPercentile(0.5);
end;

function TSlidingWindowStats.GetP95: Double;
begin
  Result := GetPercentile(0.95);
end;

function TSlidingWindowStats.GetP99: Double;
begin
  Result := GetPercentile(0.99);
end;

function TSlidingWindowStats.GetZScore(AValue: Double): Double;
var
  Mean, StdDev: Double;
begin
  Mean := GetMean;
  StdDev := GetStdDev;
  if StdDev = 0 then Exit(0);
  Result := (AValue - Mean) / StdDev;
end;

function TSlidingWindowStats.GetSummary: TStatisticsSummary;
var
  I: Integer;
begin
  Result.Count := FWindow.Count;
  Result.Sum := 0;
  for I := 0 to FWindow.Count - 1 do
    Result.Sum := Result.Sum + FWindow[I];
  Result.Mean := GetMean;
  Result.Variance := GetVariance;
  Result.StdDev := GetStdDev;
  Result.Min := GetMin;
  Result.Max := GetMax;
  Result.Median := GetMedian;
  Result.P95 := GetP95;
  Result.P99 := GetP99;
end;

{$ENDREGION}

{$REGION 'TEWMACalculator'}

constructor TEWMACalculator.Create(AAlpha: Double);
begin
  inherited Create;
  FAlpha := AAlpha;
  FValue := 0;
  FVariance := 0;
  FInitialized := False;
end;

procedure TEWMACalculator.Update(AValue: Double);
var
  Diff: Double;
begin
  if not FInitialized then
  begin
    FValue := AValue;
    FInitialized := True;
  end
  else
  begin
    Diff := AValue - FValue;
    FValue := FValue + FAlpha * Diff;
    FVariance := (1 - FAlpha) * (FVariance + FAlpha * Sqr(Diff));
  end;
end;

procedure TEWMACalculator.Reset;
begin
  FValue := 0;
  FVariance := 0;
  FInitialized := False;
end;

function TEWMACalculator.GetStdDev: Double;
begin
  Result := Sqrt(FVariance);
end;

function TEWMACalculator.GetUpperBound(ASigma: Double): Double;
begin
  Result := FValue + ASigma * GetStdDev;
end;

function TEWMACalculator.GetLowerBound(ASigma: Double): Double;
begin
  Result := FValue - ASigma * GetStdDev;
end;

function TEWMACalculator.IsAnomaly(AValue: Double; ASigma: Double): Boolean;
begin
  Result := (AValue > GetUpperBound(ASigma)) or (AValue < GetLowerBound(ASigma));
end;

{$ENDREGION}

{$REGION 'TZScoreDetector'}

constructor TZScoreDetector.Create(const AMetricName: string; AThreshold: Double;
  AWindowSize: Integer);
begin
  inherited Create;
  FStats := TSlidingWindowStats.Create(AWindowSize);
  FThreshold := AThreshold;
  FMetricName := AMetricName;
end;

destructor TZScoreDetector.Destroy;
begin
  FStats.Free;
  inherited;
end;

function TZScoreDetector.Detect(const AValue: Double;
  const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
var
  ZScore: Double;
  Anomaly: TDetectedAnomaly;
begin
  SetLength(Result, 0);
  
  if FStats.FWindow.Count < 10 then
  begin
    FStats.Add(AValue);
    Exit;
  end;
  
  ZScore := FStats.GetZScore(AValue);
  
  if Abs(ZScore) > FThreshold then
  begin
    SetLength(Result, 1);
    Anomaly.Id := TGUID.NewGuid.ToString;
    if ZScore > 0 then
      Anomaly.AnomalyType := atLatencySpike
    else
      Anomaly.AnomalyType := atThroughputDrop;
    
    if Abs(ZScore) > FThreshold * 2 then
      Anomaly.Severity := asCritical
    else if Abs(ZScore) > FThreshold * 1.5 then
      Anomaly.Severity := asWarning
    else
      Anomaly.Severity := asInfo;
    
    Anomaly.DetectedAt := ATimestamp;
    Anomaly.WorkflowId := FWorkflowId;
    Anomaly.MetricName := FMetricName;
    Anomaly.ObservedValue := AValue;
    Anomaly.ExpectedValue := FStats.GetMean;
    Anomaly.Deviation := AValue - FStats.GetMean;
    Anomaly.ZScore := ZScore;
    Anomaly.Confidence := 1 - (1 / (1 + Abs(ZScore)));
    Anomaly.Description := Format('指标 %s 异常: 观测�?%.2f, 期望�?%.2f (Z-Score: %.2f)',
      [FMetricName, AValue, FStats.GetMean, ZScore]);
    
    SetLength(Anomaly.PossibleCauses, 2);
    Anomaly.PossibleCauses[0] := '系统负载突增';
    Anomaly.PossibleCauses[1] := '资源竞争';
    
    SetLength(Anomaly.Recommendations, 1);
    Anomaly.Recommendations[0] := '检查系统资源使用情�?;
    
    Result[0] := Anomaly;
  end;
  
  FStats.Add(AValue);
end;

procedure TZScoreDetector.Train(const AData: TArray<TTimeSeriesPoint>);
var
  Point: TTimeSeriesPoint;
begin
  FStats.Clear;
  for Point in AData do
    FStats.Add(Point.Value);
end;

procedure TZScoreDetector.Reset;
begin
  FStats.Clear;
end;

{$ENDREGION}

{$REGION 'TIQRDetector'}

constructor TIQRDetector.Create(const AMetricName: string; AMultiplier: Double;
  AWindowSize: Integer);
begin
  inherited Create;
  FStats := TSlidingWindowStats.Create(AWindowSize);
  FMultiplier := AMultiplier;
  FMetricName := AMetricName;
end;

destructor TIQRDetector.Destroy;
begin
  FStats.Free;
  inherited;
end;

function TIQRDetector.GetQ1: Double;
begin
  Result := FStats.GetPercentile(0.25);
end;

function TIQRDetector.GetQ3: Double;
begin
  Result := FStats.GetPercentile(0.75);
end;

function TIQRDetector.GetIQR: Double;
begin
  Result := GetQ3 - GetQ1;
end;

function TIQRDetector.Detect(const AValue: Double;
  const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
var
  Q1, Q3, IQR, LowerBound, UpperBound: Double;
  Anomaly: TDetectedAnomaly;
begin
  SetLength(Result, 0);
  
  if FStats.FWindow.Count < 10 then
  begin
    FStats.Add(AValue);
    Exit;
  end;
  
  Q1 := GetQ1;
  Q3 := GetQ3;
  IQR := Q3 - Q1;
  LowerBound := Q1 - FMultiplier * IQR;
  UpperBound := Q3 + FMultiplier * IQR;
  
  if (AValue < LowerBound) or (AValue > UpperBound) then
  begin
    SetLength(Result, 1);
    Anomaly.Id := TGUID.NewGuid.ToString;
    Anomaly.AnomalyType := atPatternDeviation;
    
    if (AValue < Q1 - 3 * IQR) or (AValue > Q3 + 3 * IQR) then
      Anomaly.Severity := asCritical
    else
      Anomaly.Severity := asWarning;
    
    Anomaly.DetectedAt := ATimestamp;
    Anomaly.WorkflowId := FWorkflowId;
    Anomaly.MetricName := FMetricName;
    Anomaly.ObservedValue := AValue;
    Anomaly.ExpectedValue := FStats.GetMedian;
    Anomaly.Confidence := 0.85;
    Anomaly.Description := Format('指标 %s 超出 IQR 范围: %.2f (范围: %.2f - %.2f)',
      [FMetricName, AValue, LowerBound, UpperBound]);
    
    Result[0] := Anomaly;
  end;
  
  FStats.Add(AValue);
end;

procedure TIQRDetector.Train(const AData: TArray<TTimeSeriesPoint>);
var
  Point: TTimeSeriesPoint;
begin
  FStats.Clear;
  for Point in AData do
    FStats.Add(Point.Value);
end;

procedure TIQRDetector.Reset;
begin
  FStats.Clear;
end;

{$ENDREGION}

{$REGION 'TEWMADetector'}

constructor TEWMADetector.Create(const AMetricName: string; AAlpha: Double;
  ASigmaThreshold: Double);
begin
  inherited Create;
  FEWMA := TEWMACalculator.Create(AAlpha);
  FSigmaThreshold := ASigmaThreshold;
  FMetricName := AMetricName;
end;

destructor TEWMADetector.Destroy;
begin
  FEWMA.Free;
  inherited;
end;

function TEWMADetector.Detect(const AValue: Double;
  const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
var
  Anomaly: TDetectedAnomaly;
begin
  SetLength(Result, 0);
  
  if FEWMA.IsAnomaly(AValue, FSigmaThreshold) then
  begin
    SetLength(Result, 1);
    Anomaly.Id := TGUID.NewGuid.ToString;
    Anomaly.AnomalyType := atTrendAnomaly;
    Anomaly.Severity := asWarning;
    Anomaly.DetectedAt := ATimestamp;
    Anomaly.WorkflowId := FWorkflowId;
    Anomaly.MetricName := FMetricName;
    Anomaly.ObservedValue := AValue;
    Anomaly.ExpectedValue := FEWMA.Value;
    Anomaly.Deviation := AValue - FEWMA.Value;
    Anomaly.Confidence := 0.8;
    Anomaly.Description := Format('EWMA 检测到异常: %.2f (期望: %.2f ± %.2f)',
      [AValue, FEWMA.Value, FSigmaThreshold * FEWMA.StdDev]);
    
    Result[0] := Anomaly;
  end;
  
  FEWMA.Update(AValue);
end;

procedure TEWMADetector.Train(const AData: TArray<TTimeSeriesPoint>);
var
  Point: TTimeSeriesPoint;
begin
  FEWMA.Reset;
  for Point in AData do
    FEWMA.Update(Point.Value);
end;

procedure TEWMADetector.Reset;
begin
  FEWMA.Reset;
end;

{$ENDREGION}

{$REGION 'TIsolationForestDetector'}

constructor TIsolationForestDetector.Create(const AMetricName: string;
  ANumTrees: Integer; ASampleSize: Integer; AContaminationRate: Double);
begin
  inherited Create;
  FTrees := TList<TObject>.Create;
  FNumTrees := ANumTrees;
  FSampleSize := ASampleSize;
  FContaminationRate := AContaminationRate;
  FThreshold := 0.5;
  FMetricName := AMetricName;
  FTrainingData := TList<Double>.Create;
end;

destructor TIsolationForestDetector.Destroy;
begin
  FTrainingData.Free;
  FTrees.Free;
  inherited;
end;

function TIsolationForestDetector.ComputeAnomalyScore(const AValue: Double): Double;
var
  AvgPathLength: Double;
  N: Integer;
  C: Double;
begin
  // 简化实�? 基于训练数据的分布估计异常分�?
  N := FTrainingData.Count;
  if N < 2 then Exit(0);
  
  // 计算平均路径长度的期望�?
  C := 2 * (Ln(N - 1) + 0.5772156649) - (2 * (N - 1) / N);
  
  // 简�? 基于与均值的距离估计
  var Mean: Double := 0;
  for var I := 0 to FTrainingData.Count - 1 do
    Mean := Mean + FTrainingData[I];
  Mean := Mean / FTrainingData.Count;
  
  var StdDev: Double := 0;
  for var I := 0 to FTrainingData.Count - 1 do
    StdDev := StdDev + Sqr(FTrainingData[I] - Mean);
  StdDev := Sqrt(StdDev / FTrainingData.Count);
  
  if StdDev = 0 then Exit(0);
  
  var NormDist := Abs(AValue - Mean) / StdDev;
  AvgPathLength := C - NormDist;
  if AvgPathLength < 1 then AvgPathLength := 1;
  
  Result := Power(2, -AvgPathLength / C);
end;

function TIsolationForestDetector.PathLength(const AValue: Double;
  ATree: TObject): Double;
begin
  // 简化实�?
  Result := 5;
end;

function TIsolationForestDetector.Detect(const AValue: Double;
  const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
var
  Score: Double;
  Anomaly: TDetectedAnomaly;
begin
  SetLength(Result, 0);
  
  if FTrainingData.Count < FSampleSize then
  begin
    FTrainingData.Add(AValue);
    Exit;
  end;
  
  Score := ComputeAnomalyScore(AValue);
  
  if Score > FThreshold then
  begin
    SetLength(Result, 1);
    Anomaly.Id := TGUID.NewGuid.ToString;
    Anomaly.AnomalyType := atPatternDeviation;
    
    if Score > 0.8 then
      Anomaly.Severity := asCritical
    else if Score > 0.6 then
      Anomaly.Severity := asWarning
    else
      Anomaly.Severity := asInfo;
    
    Anomaly.DetectedAt := ATimestamp;
    Anomaly.WorkflowId := FWorkflowId;
    Anomaly.MetricName := FMetricName;
    Anomaly.ObservedValue := AValue;
    Anomaly.Confidence := Score;
    Anomaly.Description := Format('Isolation Forest 检测到异常: %.2f (分数: %.2f)',
      [AValue, Score]);
    
    Result[0] := Anomaly;
  end;
  
  // 更新训练数据 (滑动窗口)
  if FTrainingData.Count >= FSampleSize * 2 then
    FTrainingData.Delete(0);
  FTrainingData.Add(AValue);
end;

procedure TIsolationForestDetector.Train(const AData: TArray<TTimeSeriesPoint>);
var
  Point: TTimeSeriesPoint;
begin
  FTrainingData.Clear;
  for Point in AData do
  begin
    FTrainingData.Add(Point.Value);
    if FTrainingData.Count >= FSampleSize * 2 then
      Break;
  end;
  BuildForest;
end;

procedure TIsolationForestDetector.Reset;
begin
  FTrainingData.Clear;
  FTrees.Clear;
end;

procedure TIsolationForestDetector.BuildForest;
begin
  // 简化实�? 实际应该构建隔离�?
end;

{$ENDREGION}

{$REGION 'TSeasonalDetector'}

constructor TSeasonalDetector.Create(const AMetricName: string;
  ASeasonalPeriod: Integer; ASigmaThreshold: Double);
begin
  inherited Create;
  FSeasonalPeriod := ASeasonalPeriod;
  FSigmaThreshold := ASigmaThreshold;
  FMetricName := AMetricName;
  FResiduals := TSlidingWindowStats.Create(100);
  FDataPoints := TList<TTimeSeriesPoint>.Create;
  SetLength(FSeasonalPattern, FSeasonalPeriod);
  SetLength(FTrend, 0);
end;

destructor TSeasonalDetector.Destroy;
begin
  FDataPoints.Free;
  FResiduals.Free;
  inherited;
end;

procedure TSeasonalDetector.DecomposeTimeSeries;
var
  I, J, Index: Integer;
  SeasonalSums: TArray<Double>;
  SeasonalCounts: TArray<Integer>;
begin
  if FDataPoints.Count < FSeasonalPeriod * 2 then Exit;
  
  // 计算季节性模�?
  SetLength(SeasonalSums, FSeasonalPeriod);
  SetLength(SeasonalCounts, FSeasonalPeriod);
  
  for I := 0 to FDataPoints.Count - 1 do
  begin
    Index := I mod FSeasonalPeriod;
    SeasonalSums[Index] := SeasonalSums[Index] + FDataPoints[I].Value;
    Inc(SeasonalCounts[Index]);
  end;
  
  for I := 0 to FSeasonalPeriod - 1 do
  begin
    if SeasonalCounts[I] > 0 then
      FSeasonalPattern[I] := SeasonalSums[I] / SeasonalCounts[I]
    else
      FSeasonalPattern[I] := 0;
  end;
  
  // 计算趋势 (简单移动平�?
  SetLength(FTrend, FDataPoints.Count);
  for I := 0 to FDataPoints.Count - 1 do
  begin
    var Sum: Double := 0;
    var Count: Integer := 0;
    for J := Max(0, I - FSeasonalPeriod div 2) to Min(FDataPoints.Count - 1, I + FSeasonalPeriod div 2) do
    begin
      Sum := Sum + FDataPoints[J].Value;
      Inc(Count);
    end;
    if Count > 0 then
      FTrend[I] := Sum / Count
    else
      FTrend[I] := 0;
  end;
end;

function TSeasonalDetector.GetSeasonalComponent(const ATimestamp: TDateTime): Double;
var
  Hour: Integer;
begin
  Hour := HourOf(ATimestamp) mod FSeasonalPeriod;
  if (Hour >= 0) and (Hour < Length(FSeasonalPattern)) then
    Result := FSeasonalPattern[Hour]
  else
    Result := 0;
end;

function TSeasonalDetector.GetTrendComponent(AIndex: Integer): Double;
begin
  if (AIndex >= 0) and (AIndex < Length(FTrend)) then
    Result := FTrend[AIndex]
  else if Length(FTrend) > 0 then
    Result := FTrend[High(FTrend)]
  else
    Result := 0;
end;

function TSeasonalDetector.Detect(const AValue: Double;
  const ATimestamp: TDateTime): TArray<TDetectedAnomaly>;
var
  Seasonal, Trend, Expected, Residual: Double;
  ZScore: Double;
  Anomaly: TDetectedAnomaly;
  Point: TTimeSeriesPoint;
begin
  SetLength(Result, 0);
  
  // 添加数据�?
  Point.Timestamp := ATimestamp;
  Point.Value := AValue;
  FDataPoints.Add(Point);
  
  // 定期重新分解
  if FDataPoints.Count mod FSeasonalPeriod = 0 then
    DecomposeTimeSeries;
  
  if FDataPoints.Count < FSeasonalPeriod * 2 then Exit;
  
  // 计算期望值和残差
  Seasonal := GetSeasonalComponent(ATimestamp);
  Trend := GetTrendComponent(FDataPoints.Count - 1);
  Expected := Seasonal + Trend;
  Residual := AValue - Expected;
  
  FResiduals.Add(Residual);
  
  if FResiduals.FWindow.Count < 10 then Exit;
  
  ZScore := FResiduals.GetZScore(Residual);
  
  if Abs(ZScore) > FSigmaThreshold then
  begin
    SetLength(Result, 1);
    Anomaly.Id := TGUID.NewGuid.ToString;
    Anomaly.AnomalyType := atCyclicAnomaly;
    
    if Abs(ZScore) > FSigmaThreshold * 2 then
      Anomaly.Severity := asCritical
    else
      Anomaly.Severity := asWarning;
    
    Anomaly.DetectedAt := ATimestamp;
    Anomaly.WorkflowId := FWorkflowId;
    Anomaly.MetricName := FMetricName;
    Anomaly.ObservedValue := AValue;
    Anomaly.ExpectedValue := Expected;
    Anomaly.Deviation := Residual;
    Anomaly.ZScore := ZScore;
    Anomaly.Confidence := 1 - (1 / (1 + Abs(ZScore)));
    Anomaly.Description := Format('季节性分解检测到异常: %.2f (期望: %.2f, 残差 Z-Score: %.2f)',
      [AValue, Expected, ZScore]);
    
    SetLength(Anomaly.PossibleCauses, 1);
    Anomaly.PossibleCauses[0] := '偏离正常季节性模�?;
    
    Result[0] := Anomaly;
  end;
end;

procedure TSeasonalDetector.Train(const AData: TArray<TTimeSeriesPoint>);
var
  Point: TTimeSeriesPoint;
begin
  FDataPoints.Clear;
  FResiduals.Clear;
  
  for Point in AData do
    FDataPoints.Add(Point);
  
  if FDataPoints.Count >= FSeasonalPeriod * 2 then
    DecomposeTimeSeries;
end;

procedure TSeasonalDetector.Reset;
begin
  FDataPoints.Clear;
  FResiduals.Clear;
  SetLength(FSeasonalPattern, FSeasonalPeriod);
  SetLength(FTrend, 0);
end;

{$ENDREGION}

{$REGION 'TCorrelationMatrix'}

constructor TCorrelationMatrix.Create;
begin
  inherited Create;
  FMetricNames := TStringList.Create;
  FDataCount := 0;
end;

destructor TCorrelationMatrix.Destroy;
begin
  FMetricNames.Free;
  inherited;
end;

procedure TCorrelationMatrix.AddMetric(const AName: string);
var
  OldSize, I: Integer;
begin
  if FMetricNames.IndexOf(AName) >= 0 then Exit;
  
  OldSize := FMetricNames.Count;
  FMetricNames.Add(AName);
  
  // 扩展矩阵
  SetLength(FMatrix, FMetricNames.Count, FMetricNames.Count);
  
  // 初始化新�?�?
  for I := 0 to FMetricNames.Count - 1 do
  begin
    FMatrix[OldSize, I] := 0;
    FMatrix[I, OldSize] := 0;
  end;
  FMatrix[OldSize, OldSize] := 1;  // 自相关为 1
end;

procedure TCorrelationMatrix.Update(const AMetrics: TDictionary<string, Double>);
begin
  Inc(FDataCount);
  // 简化实�? 实际应该计算增量相关�?
end;

function TCorrelationMatrix.GetCorrelation(const AMetric1, AMetric2: string): Double;
var
  I1, I2: Integer;
begin
  I1 := FMetricNames.IndexOf(AMetric1);
  I2 := FMetricNames.IndexOf(AMetric2);
  
  if (I1 < 0) or (I2 < 0) then Exit(0);
  
  Result := FMatrix[I1, I2];
end;

function TCorrelationMatrix.FindCorrelated(const AMetric: string;
  AThreshold: Double): TArray<string>;
var
  I, Index: Integer;
  Results: TList<string>;
begin
  Results := TList<string>.Create;
  try
    Index := FMetricNames.IndexOf(AMetric);
    if Index < 0 then Exit(Results.ToArray);
    
    for I := 0 to FMetricNames.Count - 1 do
    begin
      if I <> Index then
      begin
        if Abs(FMatrix[Index, I]) >= AThreshold then
          Results.Add(FMetricNames[I]);
      end;
    end;
    
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TMultiDimensionalDetector'}

constructor TMultiDimensionalDetector.Create;
begin
  inherited Create;
  FDetectors := TDictionary<string, IAnomalyDetector>.Create;
  FCorrelationMatrix := TCorrelationMatrix.Create;
  FLock := TCriticalSection.Create;
end;

destructor TMultiDimensionalDetector.Destroy;
begin
  FLock.Free;
  FCorrelationMatrix.Free;
  FDetectors.Free;
  inherited;
end;

function TMultiDimensionalDetector.GetOrCreateDetector(
  const AMetricName: string): IAnomalyDetector;
begin
  if not FDetectors.TryGetValue(AMetricName, Result) then
  begin
    Result := TZScoreDetector.Create(AMetricName);
    FDetectors.Add(AMetricName, Result);
  end;
end;

procedure TMultiDimensionalDetector.AddDetector(const AMetricName: string;
  ADetector: IAnomalyDetector);
begin
  FLock.Enter;
  try
    FDetectors.AddOrSetValue(AMetricName, ADetector);
    FCorrelationMatrix.AddMetric(AMetricName);
  finally
    FLock.Leave;
  end;
end;

function TMultiDimensionalDetector.Detect(
  const APoint: TMultiMetricPoint): TArray<TDetectedAnomaly>;
var
  MetricName: string;
  Value: Double;
  Detector: IAnomalyDetector;
  Anomalies: TArray<TDetectedAnomaly>;
  Results: TList<TDetectedAnomaly>;
  Anomaly: TDetectedAnomaly;
begin
  Results := TList<TDetectedAnomaly>.Create;
  try
    FLock.Enter;
    try
      FCorrelationMatrix.Update(APoint.Metrics);
      
      for MetricName in APoint.Metrics.Keys do
      begin
        Value := APoint.Metrics[MetricName];
        Detector := GetOrCreateDetector(MetricName);
        
        Anomalies := Detector.Detect(Value, APoint.Timestamp);
        for Anomaly in Anomalies do
        begin
          Anomaly.WorkflowId := APoint.WorkflowId;
          Anomaly.StepId := APoint.StepId;
          Results.Add(Anomaly);
        end;
      end;
    finally
      FLock.Leave;
    end;
    
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

procedure TMultiDimensionalDetector.Train(const AData: TArray<TMultiMetricPoint>);
var
  Point: TMultiMetricPoint;
  MetricName: string;
  Detector: IAnomalyDetector;
  MetricData: TDictionary<string, TList<TTimeSeriesPoint>>;
  PointData: TTimeSeriesPoint;
begin
  MetricData := TDictionary<string, TList<TTimeSeriesPoint>>.Create;
  try
    // 按指标分组数�?
    for Point in AData do
    begin
      FCorrelationMatrix.Update(Point.Metrics);
      
      for MetricName in Point.Metrics.Keys do
      begin
        if not MetricData.ContainsKey(MetricName) then
          MetricData.Add(MetricName, TList<TTimeSeriesPoint>.Create);
        
        PointData.Timestamp := Point.Timestamp;
        PointData.Value := Point.Metrics[MetricName];
        MetricData[MetricName].Add(PointData);
      end;
    end;
    
    // 训练每个检测器
    FLock.Enter;
    try
      for MetricName in MetricData.Keys do
      begin
        Detector := GetOrCreateDetector(MetricName);
        Detector.Train(MetricData[MetricName].ToArray);
      end;
    finally
      FLock.Leave;
    end;
  finally
    for var List in MetricData.Values do
      List.Free;
    MetricData.Free;
  end;
end;

procedure TMultiDimensionalDetector.Reset;
var
  Detector: IAnomalyDetector;
begin
  FLock.Enter;
  try
    for Detector in FDetectors.Values do
      Detector.Reset;
  finally
    FLock.Leave;
  end;
end;

function TMultiDimensionalDetector.AnalyzeCorrelation(
  const AAnomaly: TDetectedAnomaly): TArray<string>;
begin
  Result := FCorrelationMatrix.FindCorrelated(AAnomaly.MetricName, 0.7);
end;

{$ENDREGION}

{$REGION 'TRootCauseAnalyzer'}

constructor TRootCauseAnalyzer.Create(ATimeWindow: Integer);
begin
  inherited Create;
  FCausalGraph := TDictionary<string, TList<TCausalRelation>>.Create;
  FRecentAnomalies := TList<TDetectedAnomaly>.Create;
  FTimeWindow := ATimeWindow;
end;

destructor TRootCauseAnalyzer.Destroy;
var
  List: TList<TCausalRelation>;
begin
  for List in FCausalGraph.Values do
    List.Free;
  FCausalGraph.Free;
  FRecentAnomalies.Free;
  inherited;
end;

function TRootCauseAnalyzer.FindUpstreamCauses(const AMetric: string): TArray<string>;
var
  Relations: TList<TCausalRelation>;
  Relation: TCausalRelation;
  Results: TList<string>;
begin
  Results := TList<string>.Create;
  try
    if FCausalGraph.TryGetValue(AMetric, Relations) then
    begin
      for Relation in Relations do
        Results.Add(Relation.SourceMetric);
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TRootCauseAnalyzer.ComputeCauseProbability(const ASource, ATarget: string;
  const AAnomalies: TArray<TDetectedAnomaly>): Double;
var
  SourceAnomalyCount, TotalCount: Integer;
  Anomaly: TDetectedAnomaly;
begin
  SourceAnomalyCount := 0;
  TotalCount := 0;
  
  for Anomaly in AAnomalies do
  begin
    if Anomaly.MetricName = ATarget then
    begin
      Inc(TotalCount);
      // 检查是否有先前的源异常
      for var A in AAnomalies do
      begin
        if (A.MetricName = ASource) and (A.DetectedAt < Anomaly.DetectedAt) and
           (SecondsBetween(Anomaly.DetectedAt, A.DetectedAt) < FTimeWindow) then
        begin
          Inc(SourceAnomalyCount);
          Break;
        end;
      end;
    end;
  end;
  
  if TotalCount > 0 then
    Result := SourceAnomalyCount / TotalCount
  else
    Result := 0;
end;

procedure TRootCauseAnalyzer.AddCausalRelation(const ARelation: TCausalRelation);
var
  Relations: TList<TCausalRelation>;
begin
  if not FCausalGraph.TryGetValue(ARelation.TargetMetric, Relations) then
  begin
    Relations := TList<TCausalRelation>.Create;
    FCausalGraph.Add(ARelation.TargetMetric, Relations);
  end;
  Relations.Add(ARelation);
end;

procedure TRootCauseAnalyzer.RecordAnomaly(const AAnomaly: TDetectedAnomaly);
begin
  FRecentAnomalies.Add(AAnomaly);
  
  // 清理旧记�?
  while FRecentAnomalies.Count > 0 do
  begin
    if SecondsBetween(Now, FRecentAnomalies[0].DetectedAt) > FTimeWindow * 2 then
      FRecentAnomalies.Delete(0)
    else
      Break;
  end;
end;

function TRootCauseAnalyzer.Analyze(
  const AAnomaly: TDetectedAnomaly): TArray<TRootCauseCandidate>;
var
  UpstreamCauses: TArray<string>;
  Cause: string;
  Candidate: TRootCauseCandidate;
  Candidates: TList<TRootCauseCandidate>;
  RecentArray: TArray<TDetectedAnomaly>;
begin
  Candidates := TList<TRootCauseCandidate>.Create;
  try
    UpstreamCauses := FindUpstreamCauses(AAnomaly.MetricName);
    RecentArray := FRecentAnomalies.ToArray;
    
    for Cause in UpstreamCauses do
    begin
      Candidate.Metric := Cause;
      Candidate.Probability := ComputeCauseProbability(Cause, AAnomaly.MetricName, RecentArray);
      
      if Candidate.Probability > 0.3 then
      begin
        SetLength(Candidate.Evidence, 1);
        Candidate.Evidence[0] := Format('历史数据显示 %.0f%% 的相关�?, [Candidate.Probability * 100]);
        Candidates.Add(Candidate);
      end;
    end;
    
    // 按概率排�?
    Candidates.Sort(TComparer<TRootCauseCandidate>.Construct(
      function(const L, R: TRootCauseCandidate): Integer
      begin
        if R.Probability > L.Probability then Result := 1
        else if R.Probability < L.Probability then Result := -1
        else Result := 0;
      end
    ));
    
    Result := Candidates.ToArray;
  finally
    Candidates.Free;
  end;
end;

procedure TRootCauseAnalyzer.LearnCausalRelations(const AData: TArray<TMultiMetricPoint>);
begin
  // 简化实�? 基于时间滞后相关性学习因果关�?
end;

{$ENDREGION}

{$REGION 'TAdaptiveThresholdManager'}

constructor TAdaptiveThresholdManager.Create(AStrategy: TThresholdStrategy);
begin
  inherited Create;
  FThresholds := TDictionary<string, Double>.Create;
  FStats := TDictionary<string, TSlidingWindowStats>.Create;
  FStrategy := AStrategy;
  FFalsePositiveRate := 0;
  FAdjustmentFactor := 1.0;
end;

destructor TAdaptiveThresholdManager.Destroy;
var
  Stats: TSlidingWindowStats;
begin
  for Stats in FStats.Values do
    Stats.Free;
  FStats.Free;
  FThresholds.Free;
  inherited;
end;

function TAdaptiveThresholdManager.ComputeThreshold(const AMetric: string): Double;
var
  Stats: TSlidingWindowStats;
begin
  if not FStats.TryGetValue(AMetric, Stats) then
    Exit(3.0);  // 默认阈�?
  
  case FStrategy of
    tsFixed:
      Result := 3.0;
    tsPercentile:
      Result := Stats.GetP99;
    tsMAD:
      begin
        var Median := Stats.GetMedian;
        var MAD := Stats.GetPercentile(0.5);  // 简�?
        Result := Median + 3 * MAD;
      end;
    tsAdaptive:
      Result := Stats.GetMean + FAdjustmentFactor * 3 * Stats.GetStdDev;
  else
    Result := 3.0;
  end;
end;

procedure TAdaptiveThresholdManager.SetThreshold(const AMetric: string;
  AThreshold: Double);
begin
  FThresholds.AddOrSetValue(AMetric, AThreshold);
end;

function TAdaptiveThresholdManager.GetThreshold(const AMetric: string): Double;
begin
  if not FThresholds.TryGetValue(AMetric, Result) then
    Result := ComputeThreshold(AMetric);
end;

procedure TAdaptiveThresholdManager.UpdateStats(const AMetric: string; AValue: Double);
var
  Stats: TSlidingWindowStats;
begin
  if not FStats.TryGetValue(AMetric, Stats) then
  begin
    Stats := TSlidingWindowStats.Create(1000);
    FStats.Add(AMetric, Stats);
  end;
  Stats.Add(AValue);
end;

procedure TAdaptiveThresholdManager.ReportFalsePositive(const AMetric: string);
begin
  FFalsePositiveRate := FFalsePositiveRate * 0.9 + 0.1;
  FAdjustmentFactor := FAdjustmentFactor * 1.1;
end;

procedure TAdaptiveThresholdManager.ReportTruePositive(const AMetric: string);
begin
  FFalsePositiveRate := FFalsePositiveRate * 0.9;
end;

procedure TAdaptiveThresholdManager.AdjustThresholds;
begin
  if FFalsePositiveRate > 0.1 then
    FAdjustmentFactor := FAdjustmentFactor * 1.05
  else if FFalsePositiveRate < 0.01 then
    FAdjustmentFactor := FAdjustmentFactor * 0.95;
  
  FAdjustmentFactor := Max(0.5, Min(2.0, FAdjustmentFactor));
end;

{$ENDREGION}

{$REGION 'TAnomalyDetectionService'}

constructor TAnomalyDetectionService.Create(const AConfig: TAnomalyDetectionConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FMultiDetector := TMultiDimensionalDetector.Create;
  FRootCauseAnalyzer := TRootCauseAnalyzer.Create(300);
  FThresholdManager := TAdaptiveThresholdManager.Create(tsAdaptive);
  FAlerts := TDictionary<string, TAnomalyAlert>.Create;
  FAlertHandlers := TList<TAnomalyAlertHandler>.Create;
  FLastAlertTime := TDictionary<string, TDateTime>.Create;
  FLock := TCriticalSection.Create;
  FEnabled := False;
end;

destructor TAnomalyDetectionService.Destroy;
begin
  Stop;
  FLock.Free;
  FLastAlertTime.Free;
  FAlertHandlers.Free;
  FAlerts.Free;
  FThresholdManager.Free;
  FRootCauseAnalyzer.Free;
  FMultiDetector.Free;
  inherited;
end;

procedure TAnomalyDetectionService.Start;
begin
  FEnabled := True;
end;

procedure TAnomalyDetectionService.Stop;
begin
  FEnabled := False;
end;

procedure TAnomalyDetectionService.ProcessAnomaly(const AAnomaly: TDetectedAnomaly);
begin
  if not FEnabled then Exit;
  
  FRootCauseAnalyzer.RecordAnomaly(AAnomaly);
  
  if ShouldAlert(AAnomaly) then
    TriggerAlert(AAnomaly);
end;

function TAnomalyDetectionService.ShouldAlert(const AAnomaly: TDetectedAnomaly): Boolean;
var
  LastTime: TDateTime;
  Key: string;
begin
  Result := True;
  
  // 检查冷却时�?
  Key := AAnomaly.WorkflowId + '.' + AAnomaly.MetricName;
  
  FLock.Enter;
  try
    if FLastAlertTime.TryGetValue(Key, LastTime) then
    begin
      if SecondsBetween(Now, LastTime) < FConfig.AlertCooldownSeconds then
        Result := False;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAnomalyDetectionService.TriggerAlert(const AAnomaly: TDetectedAnomaly);
var
  Alert: TAnomalyAlert;
  Key: string;
begin
  Alert.Anomaly := AAnomaly;
  Alert.AlertedAt := Now;
  Alert.Acknowledged := False;
  Alert.Resolved := False;
  
  Key := AAnomaly.WorkflowId + '.' + AAnomaly.MetricName;
  
  FLock.Enter;
  try
    FAlerts.AddOrSetValue(AAnomaly.Id, Alert);
    FLastAlertTime.AddOrSetValue(Key, Now);
  finally
    FLock.Leave;
  end;
  
  NotifyHandlers(Alert);
end;

procedure TAnomalyDetectionService.NotifyHandlers(const AAlert: TAnomalyAlert);
var
  Handler: TAnomalyAlertHandler;
begin
  FLock.Enter;
  try
    for Handler in FAlertHandlers do
    begin
      try
        Handler(AAlert);
      except
        // 忽略处理器错�?
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAnomalyDetectionService.RecordMetric(const AWorkflowId, AStepId,
  AMetricName: string; AValue: Double; ATimestamp: TDateTime);
var
  Point: TMultiMetricPoint;
begin
  if not FEnabled then Exit;
  
  Point.WorkflowId := AWorkflowId;
  Point.StepId := AStepId;
  Point.Timestamp := ATimestamp;
  Point.Metrics := TDictionary<string, Double>.Create;
  try
    Point.Metrics.Add(AMetricName, AValue);
    
    FThresholdManager.UpdateStats(AMetricName, AValue);
    
    var Anomalies := FMultiDetector.Detect(Point);
    for var Anomaly in Anomalies do
      ProcessAnomaly(Anomaly);
  finally
    Point.Metrics.Free;
  end;
end;

procedure TAnomalyDetectionService.RecordMultiMetrics(const AWorkflowId, AStepId: string;
  const AMetrics: TDictionary<string, Double>; ATimestamp: TDateTime);
var
  Point: TMultiMetricPoint;
  MetricName: string;
begin
  if not FEnabled then Exit;
  
  Point.WorkflowId := AWorkflowId;
  Point.StepId := AStepId;
  Point.Timestamp := ATimestamp;
  Point.Metrics := AMetrics;
  
  for MetricName in AMetrics.Keys do
    FThresholdManager.UpdateStats(MetricName, AMetrics[MetricName]);
  
  var Anomalies := FMultiDetector.Detect(Point);
  for var Anomaly in Anomalies do
    ProcessAnomaly(Anomaly);
end;

function TAnomalyDetectionService.DetectNow(
  const AWorkflowId: string): TArray<TDetectedAnomaly>;
begin
  // 返回最近的异常
  SetLength(Result, 0);
end;

procedure TAnomalyDetectionService.TrainModels(
  const AHistoricalData: TArray<TMultiMetricPoint>);
begin
  FMultiDetector.Train(AHistoricalData);
  
  if FConfig.EnableRootCauseAnalysis then
    FRootCauseAnalyzer.LearnCausalRelations(AHistoricalData);
end;

procedure TAnomalyDetectionService.RegisterAlertHandler(AHandler: TAnomalyAlertHandler);
begin
  FLock.Enter;
  try
    FAlertHandlers.Add(AHandler);
  finally
    FLock.Leave;
  end;
end;

procedure TAnomalyDetectionService.AcknowledgeAlert(const AAlertId, AUser: string);
var
  Alert: TAnomalyAlert;
begin
  FLock.Enter;
  try
    if FAlerts.TryGetValue(AAlertId, Alert) then
    begin
      Alert.Acknowledged := True;
      Alert.AcknowledgedBy := AUser;
      FAlerts[AAlertId] := Alert;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAnomalyDetectionService.ResolveAlert(const AAlertId: string;
  const ANotes: string);
var
  Alert: TAnomalyAlert;
begin
  FLock.Enter;
  try
    if FAlerts.TryGetValue(AAlertId, Alert) then
    begin
      Alert.Resolved := True;
      Alert.ResolvedAt := Now;
      Alert.Notes := ANotes;
      FAlerts[AAlertId] := Alert;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAnomalyDetectionService.GetActiveAlerts: TArray<TAnomalyAlert>;
var
  Alert: TAnomalyAlert;
  Results: TList<TAnomalyAlert>;
begin
  Results := TList<TAnomalyAlert>.Create;
  try
    FLock.Enter;
    try
      for Alert in FAlerts.Values do
      begin
        if not Alert.Resolved then
          Results.Add(Alert);
      end;
    finally
      FLock.Leave;
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

procedure TAnomalyDetectionService.ReportFalsePositive(const AAnomalyId: string);
var
  Alert: TAnomalyAlert;
begin
  FLock.Enter;
  try
    if FAlerts.TryGetValue(AAnomalyId, Alert) then
      FThresholdManager.ReportFalsePositive(Alert.Anomaly.MetricName);
  finally
    FLock.Leave;
  end;
end;

procedure TAnomalyDetectionService.ReportTruePositive(const AAnomalyId: string);
var
  Alert: TAnomalyAlert;
begin
  FLock.Enter;
  try
    if FAlerts.TryGetValue(AAnomalyId, Alert) then
      FThresholdManager.ReportTruePositive(Alert.Anomaly.MetricName);
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TWorkflowAnomalyMonitor'}

constructor TWorkflowAnomalyMonitor.Create(ADetectionService: TAnomalyDetectionService);
begin
  inherited Create;
  FDetectionService := ADetectionService;
  FWorkflowStats := TDictionary<string, TSlidingWindowStats>.Create;
  FStepStats := TDictionary<string, TSlidingWindowStats>.Create;
  FHealthReports := TDictionary<string, TWorkflowHealthReport>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TWorkflowAnomalyMonitor.Destroy;
var
  Stats: TSlidingWindowStats;
begin
  FLock.Free;
  FHealthReports.Free;
  
  for Stats in FStepStats.Values do
    Stats.Free;
  FStepStats.Free;
  
  for Stats in FWorkflowStats.Values do
    Stats.Free;
  FWorkflowStats.Free;
  
  inherited;
end;

function TWorkflowAnomalyMonitor.ComputeHealthScore(const AWorkflowId: string): Double;
var
  Stats: TSlidingWindowStats;
  ErrorRate, LatencyScore: Double;
begin
  Result := 100;
  
  FLock.Enter;
  try
    if FWorkflowStats.TryGetValue(AWorkflowId + '.latency', Stats) then
    begin
      // 延迟分数 (P99 < 1000ms = 满分)
      LatencyScore := Max(0, 100 - Stats.GetP99 / 10);
      Result := Result * (LatencyScore / 100);
    end;
    
    if FWorkflowStats.TryGetValue(AWorkflowId + '.errors', Stats) then
    begin
      // 错误率分�?
      ErrorRate := Stats.GetMean;
      Result := Result * (1 - Min(1, ErrorRate));
    end;
  finally
    FLock.Leave;
  end;
  
  Result := Max(0, Min(100, Result));
end;

function TWorkflowAnomalyMonitor.DetermineHealthStatus(AScore: Double): TWorkflowHealthStatus;
begin
  if AScore >= 90 then
    Result := whsHealthy
  else if AScore >= 70 then
    Result := whsDegraded
  else if AScore >= 50 then
    Result := whsUnhealthy
  else
    Result := whsCritical;
end;

function TWorkflowAnomalyMonitor.GenerateRecommendations(const AWorkflowId: string;
  const AAnomalies: TArray<TDetectedAnomaly>): TArray<string>;
var
  Recommendations: TList<string>;
  Anomaly: TDetectedAnomaly;
begin
  Recommendations := TList<string>.Create;
  try
    for Anomaly in AAnomalies do
    begin
      case Anomaly.AnomalyType of
        atLatencySpike:
          Recommendations.Add('考虑增加并发处理能力或优化慢速步�?);
        atErrorBurst:
          Recommendations.Add('检查错误日志，确认错误根因');
        atResourceExhaustion:
          Recommendations.Add('增加资源配额或优化资源使�?);
        atThroughputDrop:
          Recommendations.Add('检查上游服务状态和网络连接');
      end;
    end;
    
    if Recommendations.Count = 0 then
      Recommendations.Add('系统运行正常，无需特别操作');
    
    Result := Recommendations.ToArray;
  finally
    Recommendations.Free;
  end;
end;

procedure TWorkflowAnomalyMonitor.RecordStepExecution(const AMetrics: TStepMetrics);
var
  Metrics: TDictionary<string, Double>;
begin
  Metrics := TDictionary<string, Double>.Create;
  try
    Metrics.Add('execution_time', AMetrics.ExecutionTime);
    Metrics.Add('queue_wait_time', AMetrics.QueueWaitTime);
    Metrics.Add('retry_count', AMetrics.RetryCount);
    Metrics.Add('error_count', AMetrics.ErrorCount);
    Metrics.Add('memory_usage', AMetrics.MemoryUsage);
    Metrics.Add('cpu_usage', AMetrics.CPUUsage);
    
    FDetectionService.RecordMultiMetrics(
      AMetrics.WorkflowId,
      AMetrics.StepId,
      Metrics,
      AMetrics.Timestamp
    );
    
    // 更新本地统计
    FLock.Enter;
    try
      var Key := AMetrics.WorkflowId + '.latency';
      if not FWorkflowStats.ContainsKey(Key) then
        FWorkflowStats.Add(Key, TSlidingWindowStats.Create(1000));
      FWorkflowStats[Key].Add(AMetrics.ExecutionTime);
      
      Key := AMetrics.WorkflowId + '.errors';
      if not FWorkflowStats.ContainsKey(Key) then
        FWorkflowStats.Add(Key, TSlidingWindowStats.Create(1000));
      FWorkflowStats[Key].Add(AMetrics.ErrorCount);
    finally
      FLock.Leave;
    end;
  finally
    Metrics.Free;
  end;
end;

function TWorkflowAnomalyMonitor.GetHealthReport(
  const AWorkflowId: string): TWorkflowHealthReport;
var
  Score: Double;
  Stats: TSlidingWindowStats;
begin
  Score := ComputeHealthScore(AWorkflowId);
  
  Result.WorkflowId := AWorkflowId;
  Result.Status := DetermineHealthStatus(Score);
  Result.Score := Score;
  Result.ActiveAnomalies := FDetectionService.DetectNow(AWorkflowId);
  
  FLock.Enter;
  try
    if FWorkflowStats.TryGetValue(AWorkflowId + '.latency', Stats) then
    begin
      Result.AverageLatency := Stats.GetMean;
      Result.P99Latency := Stats.GetP99;
    end;
    
    if FWorkflowStats.TryGetValue(AWorkflowId + '.errors', Stats) then
      Result.RecentErrors := Round(Stats.GetSum);
  finally
    FLock.Leave;
  end;
  
  Result.Recommendations := GenerateRecommendations(AWorkflowId, Result.ActiveAnomalies);
  Result.GeneratedAt := Now;
end;

function TWorkflowAnomalyMonitor.GetAllHealthReports: TArray<TWorkflowHealthReport>;
var
  WorkflowIds: TStringList;
  Key: string;
  Results: TList<TWorkflowHealthReport>;
begin
  WorkflowIds := TStringList.Create;
  WorkflowIds.Duplicates := dupIgnore;
  WorkflowIds.Sorted := True;
  Results := TList<TWorkflowHealthReport>.Create;
  try
    FLock.Enter;
    try
      for Key in FWorkflowStats.Keys do
      begin
        var Pos := System.Pos('.', Key);
        if Pos > 0 then
          WorkflowIds.Add(Copy(Key, 1, Pos - 1));
      end;
    finally
      FLock.Leave;
    end;
    
    for var I := 0 to WorkflowIds.Count - 1 do
      Results.Add(GetHealthReport(WorkflowIds[I]));
    
    Result := Results.ToArray;
  finally
    Results.Free;
    WorkflowIds.Free;
  end;
end;

function TWorkflowAnomalyMonitor.CheckHealth(
  const AWorkflowId: string): TWorkflowHealthStatus;
begin
  Result := DetermineHealthStatus(ComputeHealthScore(AWorkflowId));
end;

procedure TWorkflowAnomalyMonitor.StartMonitoring(const AWorkflowId: string);
begin
  FLock.Enter;
  try
    if not FWorkflowStats.ContainsKey(AWorkflowId + '.latency') then
      FWorkflowStats.Add(AWorkflowId + '.latency', TSlidingWindowStats.Create(1000));
    if not FWorkflowStats.ContainsKey(AWorkflowId + '.errors') then
      FWorkflowStats.Add(AWorkflowId + '.errors', TSlidingWindowStats.Create(1000));
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowAnomalyMonitor.StopMonitoring(const AWorkflowId: string);
var
  Stats: TSlidingWindowStats;
begin
  FLock.Enter;
  try
    if FWorkflowStats.TryGetValue(AWorkflowId + '.latency', Stats) then
    begin
      Stats.Free;
      FWorkflowStats.Remove(AWorkflowId + '.latency');
    end;
    if FWorkflowStats.TryGetValue(AWorkflowId + '.errors', Stats) then
    begin
      Stats.Free;
      FWorkflowStats.Remove(AWorkflowId + '.errors');
    end;
    FHealthReports.Remove(AWorkflowId);
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

end.
