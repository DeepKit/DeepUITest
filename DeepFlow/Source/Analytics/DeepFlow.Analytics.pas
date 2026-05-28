unit UniFlow.Analytics;
(*
  UniFlow Analytics
  =================
  
  工作流执行统计、聚合和报告生成�?
  
  功能:
  - 执行统计聚合（按时间/工作�?步骤�?
  - 趋势分析
  - 异常检�?
  - 报告生成（JSON/HTML�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.Math,
  UniFlow.EventSourcing.Types,
  UniFlow.EventSourcing.Store;

type
  // ============================================================================
  // 时间范围
  // ============================================================================
  
  TTimeRange = record
    StartTime: TDateTime;
    EndTime: TDateTime;
    
    class function Today: TTimeRange; static;
    class function Yesterday: TTimeRange; static;
    class function Last7Days: TTimeRange; static;
    class function Last30Days: TTimeRange; static;
    class function ThisMonth: TTimeRange; static;
    class function LastMonth: TTimeRange; static;
    class function Custom(AStart, AEnd: TDateTime): TTimeRange; static;
    
    function Duration: TDateTime;
    function DurationHours: Double;
    function Contains(ATime: TDateTime): Boolean;
  end;
  
  TTimeGranularity = (
    tgMinute,
    tgHour,
    tgDay,
    tgWeek,
    tgMonth
  );
  
  // ============================================================================
  // 统计数据结构
  // ============================================================================
  
  /// <summary>基础统计</summary>
  TBasicStats = record
    Count: Int64;
    Sum: Double;
    Min: Double;
    Max: Double;
    Avg: Double;
    StdDev: Double;
    
    procedure Reset;
    procedure AddValue(AValue: Double);
    procedure Calculate;
    function ToJSON: TJSONObject;
  end;
  
  /// <summary>工作流统�?/summary>
  TWorkflowStats = record
    WorkflowName: string;
    TotalExecutions: Int64;
    SuccessCount: Int64;
    FailedCount: Int64;
    CancelledCount: Int64;
    SuccessRate: Double;
    AvgDurationMs: Double;
    MinDurationMs: Double;
    MaxDurationMs: Double;
    TotalDurationMs: Double;
    
    function ToJSON: TJSONObject;
  end;
  
  /// <summary>步骤统计</summary>
  TStepStats = record
    StepName: string;
    StepType: string;
    ExecutionCount: Int64;
    SuccessCount: Int64;
    FailedCount: Int64;
    SuccessRate: Double;
    AvgDurationMs: Double;
    TotalDurationMs: Double;
    
    function ToJSON: TJSONObject;
  end;
  
  /// <summary>时间桶统�?/summary>
  TTimeBucketStats = record
    BucketStart: TDateTime;
    BucketEnd: TDateTime;
    ExecutionCount: Int64;
    SuccessCount: Int64;
    FailedCount: Int64;
    AvgDurationMs: Double;
    
    function ToJSON: TJSONObject;
  end;
  
  /// <summary>错误统计</summary>
  TErrorStats = record
    ErrorCode: string;
    ErrorMessage: string;
    OccurrenceCount: Int64;
    FirstSeen: TDateTime;
    LastSeen: TDateTime;
    AffectedWorkflows: TArray<string>;
    
    function ToJSON: TJSONObject;
  end;
  
  /// <summary>LLM 使用统计</summary>
  TLLMUsageStats = record
    Provider: string;
    Model: string;
    RequestCount: Int64;
    TotalInputTokens: Int64;
    TotalOutputTokens: Int64;
    TotalCost: Double;
    AvgLatencyMs: Double;
    ErrorCount: Int64;
    
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // 聚合报告
  // ============================================================================
  
  /// <summary>执行摘要报告</summary>
  TExecutionSummary = record
    TimeRange: TTimeRange;
    TotalFlows: Int64;
    CompletedFlows: Int64;
    FailedFlows: Int64;
    CancelledFlows: Int64;
    RunningFlows: Int64;
    SuccessRate: Double;
    AvgDurationMs: Double;
    TotalEvents: Int64;
    UniqueWorkflows: Integer;
    
    function ToJSON: TJSONObject;
  end;
  
  /// <summary>趋势数据�?/summary>
  TTrendPoint = record
    Timestamp: TDateTime;
    Value: Double;
    Label_: string;
  end;
  
  /// <summary>趋势报告</summary>
  TTrendReport = record
    MetricName: string;
    Granularity: TTimeGranularity;
    Points: TArray<TTrendPoint>;
    
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // 分析引擎
  // ============================================================================
  
  /// <summary>分析配置</summary>
  TAnalyticsConfig = record
    DefaultGranularity: TTimeGranularity;
    MaxDataPoints: Integer;
    EnableCaching: Boolean;
    CacheTTLSeconds: Integer;
    
    class function Default: TAnalyticsConfig; static;
  end;
  
  /// <summary>
  /// 分析引擎 - 工作流执行分�?
  /// </summary>
  TAnalyticsEngine = class
  private
    FStore: IEventStore;
    FConfig: TAnalyticsConfig;
    FCache: TObjectDictionary<string, TJSONObject>;
    FCacheTimestamps: TDictionary<string, TDateTime>;
    
    function GetCacheKey(const APrefix: string; ARange: TTimeRange): string;
    function TryGetFromCache(const AKey: string; out AValue: TJSONObject): Boolean;
    procedure AddToCache(const AKey: string; AValue: TJSONObject);
    
    function CollectFlowEvents(const AFlowId: string): TArray<TUniFlowEvent>;
    function CalculateDuration(AEvents: TArray<TUniFlowEvent>): Double;
    function GetFlowStatus(AEvents: TArray<TUniFlowEvent>): TUniFlowStatus;
    function GetBucketStart(ATime: TDateTime; AGranularity: TTimeGranularity): TDateTime;
  public
    constructor Create(AStore: IEventStore; AConfig: TAnalyticsConfig);
    destructor Destroy; override;
    
    /// <summary>获取执行摘要</summary>
    function GetExecutionSummary(ARange: TTimeRange): TExecutionSummary;
    
    /// <summary>获取工作流统计列�?/summary>
    function GetWorkflowStats(ARange: TTimeRange): TArray<TWorkflowStats>;
    
    /// <summary>获取单个工作流的详细统计</summary>
    function GetWorkflowDetail(const AWorkflowName: string; ARange: TTimeRange): TWorkflowStats;
    
    /// <summary>获取步骤统计</summary>
    function GetStepStats(ARange: TTimeRange): TArray<TStepStats>;
    
    /// <summary>获取时间序列统计</summary>
    function GetTimeSeriesStats(ARange: TTimeRange;
      AGranularity: TTimeGranularity): TArray<TTimeBucketStats>;
    
    /// <summary>获取错误统计</summary>
    function GetErrorStats(ARange: TTimeRange): TArray<TErrorStats>;
    
    /// <summary>获取趋势报告</summary>
    function GetTrendReport(const AMetricName: string; ARange: TTimeRange;
      AGranularity: TTimeGranularity): TTrendReport;
    
    /// <summary>获取成功率趋�?/summary>
    function GetSuccessRateTrend(ARange: TTimeRange;
      AGranularity: TTimeGranularity): TTrendReport;
    
    /// <summary>获取执行量趋�?/summary>
    function GetExecutionCountTrend(ARange: TTimeRange;
      AGranularity: TTimeGranularity): TTrendReport;
    
    /// <summary>获取延迟趋势</summary>
    function GetLatencyTrend(ARange: TTimeRange;
      AGranularity: TTimeGranularity): TTrendReport;
    
    /// <summary>获取热点步骤（最耗时�?/summary>
    function GetHotspotSteps(ARange: TTimeRange; ATopN: Integer = 10): TArray<TStepStats>;
    
    /// <summary>获取失败热点（最常失败）</summary>
    function GetFailureHotspots(ARange: TTimeRange; ATopN: Integer = 10): TArray<TStepStats>;
    
    /// <summary>检测异�?/summary>
    function DetectAnomalies(ARange: TTimeRange): TJSONArray;
    
    /// <summary>导出完整报告</summary>
    function ExportFullReport(ARange: TTimeRange): TJSONObject;
    
    /// <summary>导出 HTML 报告</summary>
    function ExportHTMLReport(ARange: TTimeRange): string;
    
    /// <summary>清除缓存</summary>
    procedure ClearCache;
    
    property Store: IEventStore read FStore;
    property Config: TAnalyticsConfig read FConfig write FConfig;
  end;
  
  // ============================================================================
  // Dashboard API
  // ============================================================================
  
  /// <summary>
  /// Dashboard API - REST 风格接口
  /// </summary>
  TDashboardAPI = class
  private
    FEngine: TAnalyticsEngine;
  public
    constructor Create(AEngine: TAnalyticsEngine);
    
    /// <summary>处理 API 请求</summary>
    function HandleRequest(const APath: string; AParams: TJSONObject): TJSONObject;
    
    // 预定义端�?
    function GetOverview(ARange: TTimeRange): TJSONObject;
    function GetWorkflows(ARange: TTimeRange): TJSONObject;
    function GetTimeline(ARange: TTimeRange; AGranularity: TTimeGranularity): TJSONObject;
    function GetErrors(ARange: TTimeRange): TJSONObject;
    function GetTrends(ARange: TTimeRange): TJSONObject;
    
    property Engine: TAnalyticsEngine read FEngine;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
function GranularityToString(AGranularity: TTimeGranularity): string;
function StringToGranularity(const AStr: string): TTimeGranularity;
function FormatDuration(AMs: Double): string;
function FormatPercentage(AValue: Double): string;

implementation

// ============================================================================
// TTimeRange
// ============================================================================

class function TTimeRange.Today: TTimeRange;
begin
  Result.StartTime := Trunc(Now);
  Result.EndTime := Now;
end;

class function TTimeRange.Yesterday: TTimeRange;
begin
  Result.StartTime := Trunc(Now) - 1;
  Result.EndTime := Trunc(Now) - EncodeTime(0, 0, 1, 0);
end;

class function TTimeRange.Last7Days: TTimeRange;
begin
  Result.StartTime := Trunc(Now) - 7;
  Result.EndTime := Now;
end;

class function TTimeRange.Last30Days: TTimeRange;
begin
  Result.StartTime := Trunc(Now) - 30;
  Result.EndTime := Now;
end;

class function TTimeRange.ThisMonth: TTimeRange;
var
  Y, M, D: Word;
begin
  DecodeDate(Now, Y, M, D);
  Result.StartTime := EncodeDate(Y, M, 1);
  Result.EndTime := Now;
end;

class function TTimeRange.LastMonth: TTimeRange;
var
  Y, M, D: Word;
begin
  DecodeDate(Now, Y, M, D);
  if M = 1 then
  begin
    Y := Y - 1;
    M := 12;
  end
  else
    M := M - 1;
  Result.StartTime := EncodeDate(Y, M, 1);
  Result.EndTime := EncodeDate(Y, M, DaysInMonth(EncodeDate(Y, M, 1)));
end;

class function TTimeRange.Custom(AStart, AEnd: TDateTime): TTimeRange;
begin
  Result.StartTime := AStart;
  Result.EndTime := AEnd;
end;

function TTimeRange.Duration: TDateTime;
begin
  Result := EndTime - StartTime;
end;

function TTimeRange.DurationHours: Double;
begin
  Result := Duration * 24;
end;

function TTimeRange.Contains(ATime: TDateTime): Boolean;
begin
  Result := (ATime >= StartTime) and (ATime <= EndTime);
end;

// ============================================================================
// TBasicStats
// ============================================================================

procedure TBasicStats.Reset;
begin
  Count := 0;
  Sum := 0;
  Min := MaxDouble;
  Max := -MaxDouble;
  Avg := 0;
  StdDev := 0;
end;

procedure TBasicStats.AddValue(AValue: Double);
begin
  Inc(Count);
  Sum := Sum + AValue;
  if AValue < Min then Min := AValue;
  if AValue > Max then Max := AValue;
end;

procedure TBasicStats.Calculate;
begin
  if Count > 0 then
  begin
    Avg := Sum / Count;
    if Min = MaxDouble then Min := 0;
    if Max = -MaxDouble then Max := 0;
  end
  else
  begin
    Avg := 0;
    Min := 0;
    Max := 0;
  end;
end;

function TBasicStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('count', TJSONNumber.Create(Count));
  Result.AddPair('sum', TJSONNumber.Create(Sum));
  Result.AddPair('min', TJSONNumber.Create(Min));
  Result.AddPair('max', TJSONNumber.Create(Max));
  Result.AddPair('avg', TJSONNumber.Create(Avg));
end;

// ============================================================================
// TWorkflowStats
// ============================================================================

function TWorkflowStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('workflowName', WorkflowName);
  Result.AddPair('totalExecutions', TJSONNumber.Create(TotalExecutions));
  Result.AddPair('successCount', TJSONNumber.Create(SuccessCount));
  Result.AddPair('failedCount', TJSONNumber.Create(FailedCount));
  Result.AddPair('cancelledCount', TJSONNumber.Create(CancelledCount));
  Result.AddPair('successRate', TJSONNumber.Create(SuccessRate));
  Result.AddPair('avgDurationMs', TJSONNumber.Create(AvgDurationMs));
  Result.AddPair('minDurationMs', TJSONNumber.Create(MinDurationMs));
  Result.AddPair('maxDurationMs', TJSONNumber.Create(MaxDurationMs));
end;

// ============================================================================
// TStepStats
// ============================================================================

function TStepStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('stepName', StepName);
  Result.AddPair('stepType', StepType);
  Result.AddPair('executionCount', TJSONNumber.Create(ExecutionCount));
  Result.AddPair('successCount', TJSONNumber.Create(SuccessCount));
  Result.AddPair('failedCount', TJSONNumber.Create(FailedCount));
  Result.AddPair('successRate', TJSONNumber.Create(SuccessRate));
  Result.AddPair('avgDurationMs', TJSONNumber.Create(AvgDurationMs));
end;

// ============================================================================
// TTimeBucketStats
// ============================================================================

function TTimeBucketStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('bucketStart', DateToISO8601(BucketStart));
  Result.AddPair('bucketEnd', DateToISO8601(BucketEnd));
  Result.AddPair('executionCount', TJSONNumber.Create(ExecutionCount));
  Result.AddPair('successCount', TJSONNumber.Create(SuccessCount));
  Result.AddPair('failedCount', TJSONNumber.Create(FailedCount));
  Result.AddPair('avgDurationMs', TJSONNumber.Create(AvgDurationMs));
end;

// ============================================================================
// TErrorStats
// ============================================================================

function TErrorStats.ToJSON: TJSONObject;
var
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('errorCode', ErrorCode);
  Result.AddPair('errorMessage', ErrorMessage);
  Result.AddPair('occurrenceCount', TJSONNumber.Create(OccurrenceCount));
  Result.AddPair('firstSeen', DateToISO8601(FirstSeen));
  Result.AddPair('lastSeen', DateToISO8601(LastSeen));
  
  Arr := TJSONArray.Create;
  for var WF in AffectedWorkflows do
    Arr.Add(WF);
  Result.AddPair('affectedWorkflows', Arr);
end;

// ============================================================================
// TLLMUsageStats
// ============================================================================

function TLLMUsageStats.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('provider', Provider);
  Result.AddPair('model', Model);
  Result.AddPair('requestCount', TJSONNumber.Create(RequestCount));
  Result.AddPair('totalInputTokens', TJSONNumber.Create(TotalInputTokens));
  Result.AddPair('totalOutputTokens', TJSONNumber.Create(TotalOutputTokens));
  Result.AddPair('totalCost', TJSONNumber.Create(TotalCost));
  Result.AddPair('avgLatencyMs', TJSONNumber.Create(AvgLatencyMs));
  Result.AddPair('errorCount', TJSONNumber.Create(ErrorCount));
end;

// ============================================================================
// TExecutionSummary
// ============================================================================

function TExecutionSummary.ToJSON: TJSONObject;
var
  RangeObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  
  RangeObj := TJSONObject.Create;
  RangeObj.AddPair('start', DateToISO8601(TimeRange.StartTime));
  RangeObj.AddPair('end', DateToISO8601(TimeRange.EndTime));
  Result.AddPair('timeRange', RangeObj);
  
  Result.AddPair('totalFlows', TJSONNumber.Create(TotalFlows));
  Result.AddPair('completedFlows', TJSONNumber.Create(CompletedFlows));
  Result.AddPair('failedFlows', TJSONNumber.Create(FailedFlows));
  Result.AddPair('cancelledFlows', TJSONNumber.Create(CancelledFlows));
  Result.AddPair('runningFlows', TJSONNumber.Create(RunningFlows));
  Result.AddPair('successRate', TJSONNumber.Create(SuccessRate));
  Result.AddPair('avgDurationMs', TJSONNumber.Create(AvgDurationMs));
  Result.AddPair('totalEvents', TJSONNumber.Create(TotalEvents));
  Result.AddPair('uniqueWorkflows', TJSONNumber.Create(UniqueWorkflows));
end;

// ============================================================================
// TTrendReport
// ============================================================================

function TTrendReport.ToJSON: TJSONObject;
var
  PointsArr: TJSONArray;
  PointObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('metricName', MetricName);
  Result.AddPair('granularity', GranularityToString(Granularity));
  
  PointsArr := TJSONArray.Create;
  for var P in Points do
  begin
    PointObj := TJSONObject.Create;
    PointObj.AddPair('timestamp', DateToISO8601(P.Timestamp));
    PointObj.AddPair('value', TJSONNumber.Create(P.Value));
    if P.Label_ <> '' then
      PointObj.AddPair('label', P.Label_);
    PointsArr.Add(PointObj);
  end;
  Result.AddPair('points', PointsArr);
end;

// ============================================================================
// TAnalyticsConfig
// ============================================================================

class function TAnalyticsConfig.Default: TAnalyticsConfig;
begin
  Result.DefaultGranularity := tgHour;
  Result.MaxDataPoints := 1000;
  Result.EnableCaching := True;
  Result.CacheTTLSeconds := 60;
end;

// ============================================================================
// TAnalyticsEngine
// ============================================================================

constructor TAnalyticsEngine.Create(AStore: IEventStore; AConfig: TAnalyticsConfig);
begin
  inherited Create;
  FStore := AStore;
  FConfig := AConfig;
  FCache := TObjectDictionary<string, TJSONObject>.Create([doOwnsValues]);
  FCacheTimestamps := TDictionary<string, TDateTime>.Create;
end;

destructor TAnalyticsEngine.Destroy;
begin
  FCache.Free;
  FCacheTimestamps.Free;
  inherited;
end;

function TAnalyticsEngine.GetCacheKey(const APrefix: string; ARange: TTimeRange): string;
begin
  Result := Format('%s_%s_%s', [APrefix,
    FormatDateTime('yyyymmddhhnnss', ARange.StartTime),
    FormatDateTime('yyyymmddhhnnss', ARange.EndTime)]);
end;

function TAnalyticsEngine.TryGetFromCache(const AKey: string; out AValue: TJSONObject): Boolean;
var
  CacheTime: TDateTime;
begin
  Result := False;
  if not FConfig.EnableCaching then Exit;
  
  if FCache.TryGetValue(AKey, AValue) then
  begin
    if FCacheTimestamps.TryGetValue(AKey, CacheTime) then
    begin
      if SecondsBetween(Now, CacheTime) < FConfig.CacheTTLSeconds then
        Result := True
      else
      begin
        FCache.Remove(AKey);
        FCacheTimestamps.Remove(AKey);
      end;
    end;
  end;
end;

procedure TAnalyticsEngine.AddToCache(const AKey: string; AValue: TJSONObject);
begin
  if not FConfig.EnableCaching then Exit;
  
  FCache.AddOrSetValue(AKey, AValue.Clone as TJSONObject);
  FCacheTimestamps.AddOrSetValue(AKey, Now);
end;

function TAnalyticsEngine.CollectFlowEvents(const AFlowId: string): TArray<TUniFlowEvent>;
var
  Query: TEventQuery;
begin
  Query := TEventQuery.Create(AFlowId);
  Result := FStore.ReadEvents(Query);
end;

function TAnalyticsEngine.CalculateDuration(AEvents: TArray<TUniFlowEvent>): Double;
var
  FirstTime, LastTime: TDateTime;
begin
  Result := 0;
  if Length(AEvents) < 2 then Exit;
  
  FirstTime := AEvents[0].Timestamp;
  LastTime := AEvents[High(AEvents)].Timestamp;
  Result := MilliSecondsBetween(LastTime, FirstTime);
end;

function TAnalyticsEngine.GetFlowStatus(AEvents: TArray<TUniFlowEvent>): TUniFlowStatus;
var
  Event: TUniFlowEvent;
  StatusStr: string;
begin
  Result := ufsCreated;
  
  for Event in AEvents do
  begin
    if Event.Step = '_flow_status' then
    begin
      if Event.Payload.TryGetValue<string>('newStatus', StatusStr) then
        Result := StringToFlowStatus(StatusStr);
    end;
  end;
end;

function TAnalyticsEngine.GetBucketStart(ATime: TDateTime; AGranularity: TTimeGranularity): TDateTime;
var
  Y, M, D, H, N, S, MS: Word;
begin
  DecodeDateTime(ATime, Y, M, D, H, N, S, MS);
  
  case AGranularity of
    tgMinute:
      Result := EncodeDateTime(Y, M, D, H, N, 0, 0);
    tgHour:
      Result := EncodeDateTime(Y, M, D, H, 0, 0, 0);
    tgDay:
      Result := EncodeDate(Y, M, D);
    tgWeek:
      Result := EncodeDate(Y, M, D) - (DayOfTheWeek(ATime) - 1);
    tgMonth:
      Result := EncodeDate(Y, M, 1);
  else
    Result := ATime;
  end;
end;

function TAnalyticsEngine.GetExecutionSummary(ARange: TTimeRange): TExecutionSummary;
var
  FlowIds: TArray<string>;
  Events: TArray<TUniFlowEvent>;
  Status: TUniFlowStatus;
  Duration: Double;
  TotalDuration: Double;
  UniqueNames: TDictionary<string, Boolean>;
  FirstEvent: TUniFlowEvent;
begin
  Result := Default(TExecutionSummary);
  Result.TimeRange := ARange;
  TotalDuration := 0;
  
  UniqueNames := TDictionary<string, Boolean>.Create;
  try
    FlowIds := FStore.GetAllFlowIds;
    
    for var FlowId in FlowIds do
    begin
      Events := CollectFlowEvents(FlowId);
      if Length(Events) = 0 then Continue;
      
      try
        FirstEvent := Events[0];
        
        // 检查是否在时间范围�?
        if not ARange.Contains(FirstEvent.Timestamp) then
        begin
          for var E in Events do E.Free;
          Continue;
        end;
        
        Inc(Result.TotalFlows);
        Result.TotalEvents := Result.TotalEvents + Length(Events);
        
        // 获取工作流名�?
        var WFName: string;
        if FirstEvent.Payload.TryGetValue<string>('workflowName', WFName) then
          UniqueNames.TryAdd(WFName, True);
          
        // 获取状�?
        Status := GetFlowStatus(Events);
        case Status of
          ufsSucceeded: Inc(Result.CompletedFlows);
          ufsFailed: Inc(Result.FailedFlows);
          ufsCancelled: Inc(Result.CancelledFlows);
          ufsRunning, ufsWaitingUser: Inc(Result.RunningFlows);
        end;
        
        // 计算持续时间
        Duration := CalculateDuration(Events);
        TotalDuration := TotalDuration + Duration;
      finally
        for var E in Events do E.Free;
      end;
    end;
    
    Result.UniqueWorkflows := UniqueNames.Count;
    
    if Result.TotalFlows > 0 then
    begin
      Result.AvgDurationMs := TotalDuration / Result.TotalFlows;
      Result.SuccessRate := Result.CompletedFlows / Result.TotalFlows * 100;
    end;
  finally
    UniqueNames.Free;
  end;
end;

function TAnalyticsEngine.GetWorkflowStats(ARange: TTimeRange): TArray<TWorkflowStats>;
var
  StatsMap: TDictionary<string, TWorkflowStats>;
  FlowIds: TArray<string>;
  Events: TArray<TUniFlowEvent>;
  Status: TUniFlowStatus;
  Duration: Double;
  WFName: string;
  Stats: TWorkflowStats;
  DurationList: TDictionary<string, TList<Double>>;
  Durations: TList<Double>;
begin
  StatsMap := TDictionary<string, TWorkflowStats>.Create;
  DurationList := TDictionary<string, TList<Double>>.Create;
  
  try
    FlowIds := FStore.GetAllFlowIds;
    
    for var FlowId in FlowIds do
    begin
      Events := CollectFlowEvents(FlowId);
      if Length(Events) = 0 then Continue;
      
      try
        if not ARange.Contains(Events[0].Timestamp) then
        begin
          for var E in Events do E.Free;
          Continue;
        end;
        
        // 获取工作流名�?
        WFName := '';
        if not Events[0].Payload.TryGetValue<string>('workflowName', WFName) then
          WFName := 'unknown';
          
        // 获取或创建统�?
        if not StatsMap.TryGetValue(WFName, Stats) then
        begin
          Stats := Default(TWorkflowStats);
          Stats.WorkflowName := WFName;
          Stats.MinDurationMs := MaxDouble;
          Stats.MaxDurationMs := 0;
          DurationList.Add(WFName, TList<Double>.Create);
        end;
        
        Inc(Stats.TotalExecutions);
        
        Status := GetFlowStatus(Events);
        case Status of
          ufsSucceeded: Inc(Stats.SuccessCount);
          ufsFailed: Inc(Stats.FailedCount);
          ufsCancelled: Inc(Stats.CancelledCount);
        end;
        
        Duration := CalculateDuration(Events);
        Stats.TotalDurationMs := Stats.TotalDurationMs + Duration;
        if Duration < Stats.MinDurationMs then Stats.MinDurationMs := Duration;
        if Duration > Stats.MaxDurationMs then Stats.MaxDurationMs := Duration;
        
        DurationList[WFName].Add(Duration);
        StatsMap.AddOrSetValue(WFName, Stats);
      finally
        for var E in Events do E.Free;
      end;
    end;
    
    // 计算平均值和成功�?
    SetLength(Result, StatsMap.Count);
    var I := 0;
    for var Pair in StatsMap do
    begin
      Stats := Pair.Value;
      if Stats.TotalExecutions > 0 then
      begin
        Stats.AvgDurationMs := Stats.TotalDurationMs / Stats.TotalExecutions;
        Stats.SuccessRate := Stats.SuccessCount / Stats.TotalExecutions * 100;
      end;
      if Stats.MinDurationMs = MaxDouble then Stats.MinDurationMs := 0;
      Result[I] := Stats;
      Inc(I);
    end;
  finally
    for var L in DurationList.Values do L.Free;
    DurationList.Free;
    StatsMap.Free;
  end;
end;

function TAnalyticsEngine.GetWorkflowDetail(const AWorkflowName: string;
  ARange: TTimeRange): TWorkflowStats;
var
  AllStats: TArray<TWorkflowStats>;
begin
  Result := Default(TWorkflowStats);
  Result.WorkflowName := AWorkflowName;
  
  AllStats := GetWorkflowStats(ARange);
  for var S in AllStats do
    if S.WorkflowName = AWorkflowName then
      Exit(S);
end;

function TAnalyticsEngine.GetStepStats(ARange: TTimeRange): TArray<TStepStats>;
var
  StatsMap: TDictionary<string, TStepStats>;
  FlowIds: TArray<string>;
  Events: TArray<TUniFlowEvent>;
  Stats: TStepStats;
  StepKey: string;
  PrevEvent: TUniFlowEvent;
  Duration: Double;
begin
  StatsMap := TDictionary<string, TStepStats>.Create;
  try
    FlowIds := FStore.GetAllFlowIds;
    
    for var FlowId in FlowIds do
    begin
      Events := CollectFlowEvents(FlowId);
      if Length(Events) = 0 then Continue;
      
      try
        if not ARange.Contains(Events[0].Timestamp) then
        begin
          for var E in Events do E.Free;
          Continue;
        end;
        
        PrevEvent := nil;
        for var Event in Events do
        begin
          if Event.Step.StartsWith('_') then Continue; // 跳过系统事件
          
          StepKey := Event.Step;
          if not StatsMap.TryGetValue(StepKey, Stats) then
          begin
            Stats := Default(TStepStats);
            Stats.StepName := Event.Step;
          end;
          
          if Event.Status = esStarted then
          begin
            Inc(Stats.ExecutionCount);
            PrevEvent := Event;
          end
          else if Event.Status = esSucceeded then
          begin
            Inc(Stats.SuccessCount);
            if PrevEvent <> nil then
            begin
              Duration := MilliSecondsBetween(Event.Timestamp, PrevEvent.Timestamp);
              Stats.TotalDurationMs := Stats.TotalDurationMs + Duration;
            end;
          end
          else if Event.Status = esFailed then
            Inc(Stats.FailedCount);
            
          StatsMap.AddOrSetValue(StepKey, Stats);
        end;
      finally
        for var E in Events do E.Free;
      end;
    end;
    
    // 计算统计
    SetLength(Result, StatsMap.Count);
    var I := 0;
    for var Pair in StatsMap do
    begin
      Stats := Pair.Value;
      if Stats.ExecutionCount > 0 then
      begin
        Stats.AvgDurationMs := Stats.TotalDurationMs / Stats.ExecutionCount;
        Stats.SuccessRate := Stats.SuccessCount / Stats.ExecutionCount * 100;
      end;
      Result[I] := Stats;
      Inc(I);
    end;
  finally
    StatsMap.Free;
  end;
end;

function TAnalyticsEngine.GetTimeSeriesStats(ARange: TTimeRange;
  AGranularity: TTimeGranularity): TArray<TTimeBucketStats>;
var
  BucketMap: TDictionary<TDateTime, TTimeBucketStats>;
  FlowIds: TArray<string>;
  Events: TArray<TUniFlowEvent>;
  BucketStart: TDateTime;
  Stats: TTimeBucketStats;
  Status: TUniFlowStatus;
  Duration: Double;
  SortedKeys: TList<TDateTime>;
begin
  BucketMap := TDictionary<TDateTime, TTimeBucketStats>.Create;
  try
    FlowIds := FStore.GetAllFlowIds;
    
    for var FlowId in FlowIds do
    begin
      Events := CollectFlowEvents(FlowId);
      if Length(Events) = 0 then Continue;
      
      try
        if not ARange.Contains(Events[0].Timestamp) then
        begin
          for var E in Events do E.Free;
          Continue;
        end;
        
        BucketStart := GetBucketStart(Events[0].Timestamp, AGranularity);
        
        if not BucketMap.TryGetValue(BucketStart, Stats) then
        begin
          Stats := Default(TTimeBucketStats);
          Stats.BucketStart := BucketStart;
          case AGranularity of
            tgMinute: Stats.BucketEnd := IncMinute(BucketStart, 1);
            tgHour: Stats.BucketEnd := IncHour(BucketStart, 1);
            tgDay: Stats.BucketEnd := IncDay(BucketStart, 1);
            tgWeek: Stats.BucketEnd := IncDay(BucketStart, 7);
            tgMonth: Stats.BucketEnd := IncMonth(BucketStart, 1);
          end;
        end;
        
        Inc(Stats.ExecutionCount);
        Status := GetFlowStatus(Events);
        if Status = ufsSucceeded then Inc(Stats.SuccessCount)
        else if Status = ufsFailed then Inc(Stats.FailedCount);
        
        Duration := CalculateDuration(Events);
        Stats.AvgDurationMs := (Stats.AvgDurationMs * (Stats.ExecutionCount - 1) + Duration) / Stats.ExecutionCount;
        
        BucketMap.AddOrSetValue(BucketStart, Stats);
      finally
        for var E in Events do E.Free;
      end;
    end;
    
    // 按时间排�?
    SortedKeys := TList<TDateTime>.Create;
    try
      for var K in BucketMap.Keys do
        SortedKeys.Add(K);
      SortedKeys.Sort;
      
      SetLength(Result, SortedKeys.Count);
      for var I := 0 to SortedKeys.Count - 1 do
        Result[I] := BucketMap[SortedKeys[I]];
    finally
      SortedKeys.Free;
    end;
  finally
    BucketMap.Free;
  end;
end;

function TAnalyticsEngine.GetErrorStats(ARange: TTimeRange): TArray<TErrorStats>;
var
  ErrorMap: TDictionary<string, TErrorStats>;
  FlowIds: TArray<string>;
  Events: TArray<TUniFlowEvent>;
  Stats: TErrorStats;
  AffectedList: TDictionary<string, TList<string>>;
  WFName: string;
begin
  ErrorMap := TDictionary<string, TErrorStats>.Create;
  AffectedList := TDictionary<string, TList<string>>.Create;
  
  try
    FlowIds := FStore.GetAllFlowIds;
    
    for var FlowId in FlowIds do
    begin
      Events := CollectFlowEvents(FlowId);
      if Length(Events) = 0 then Continue;
      
      try
        if not ARange.Contains(Events[0].Timestamp) then
        begin
          for var E in Events do E.Free;
          Continue;
        end;
        
        WFName := '';
        Events[0].Payload.TryGetValue<string>('workflowName', WFName);
        
        for var Event in Events do
        begin
          if Event.Status <> esFailed then Continue;
          if Event.ErrorCode.IsEmpty then Continue;
          
          if not ErrorMap.TryGetValue(Event.ErrorCode, Stats) then
          begin
            Stats := Default(TErrorStats);
            Stats.ErrorCode := Event.ErrorCode;
            Stats.ErrorMessage := Event.ErrorMessage;
            Stats.FirstSeen := Event.Timestamp;
            Stats.LastSeen := Event.Timestamp;
            AffectedList.Add(Event.ErrorCode, TList<string>.Create);
          end;
          
          Inc(Stats.OccurrenceCount);
          if Event.Timestamp < Stats.FirstSeen then Stats.FirstSeen := Event.Timestamp;
          if Event.Timestamp > Stats.LastSeen then Stats.LastSeen := Event.Timestamp;
          
          if (WFName <> '') and (AffectedList[Event.ErrorCode].IndexOf(WFName) < 0) then
            AffectedList[Event.ErrorCode].Add(WFName);
            
          ErrorMap.AddOrSetValue(Event.ErrorCode, Stats);
        end;
      finally
        for var E in Events do E.Free;
      end;
    end;
    
    // 构建结果
    SetLength(Result, ErrorMap.Count);
    var I := 0;
    for var Pair in ErrorMap do
    begin
      Stats := Pair.Value;
      if AffectedList.ContainsKey(Pair.Key) then
        Stats.AffectedWorkflows := AffectedList[Pair.Key].ToArray;
      Result[I] := Stats;
      Inc(I);
    end;
  finally
    for var L in AffectedList.Values do L.Free;
    AffectedList.Free;
    ErrorMap.Free;
  end;
end;

function TAnalyticsEngine.GetTrendReport(const AMetricName: string;
  ARange: TTimeRange; AGranularity: TTimeGranularity): TTrendReport;
begin
  Result.MetricName := AMetricName;
  Result.Granularity := AGranularity;
  
  if AMetricName = 'success_rate' then
    Result := GetSuccessRateTrend(ARange, AGranularity)
  else if AMetricName = 'execution_count' then
    Result := GetExecutionCountTrend(ARange, AGranularity)
  else if AMetricName = 'latency' then
    Result := GetLatencyTrend(ARange, AGranularity);
end;

function TAnalyticsEngine.GetSuccessRateTrend(ARange: TTimeRange;
  AGranularity: TTimeGranularity): TTrendReport;
var
  TimeSeries: TArray<TTimeBucketStats>;
  Point: TTrendPoint;
begin
  Result.MetricName := 'success_rate';
  Result.Granularity := AGranularity;
  
  TimeSeries := GetTimeSeriesStats(ARange, AGranularity);
  SetLength(Result.Points, Length(TimeSeries));
  
  for var I := 0 to High(TimeSeries) do
  begin
    Point.Timestamp := TimeSeries[I].BucketStart;
    if TimeSeries[I].ExecutionCount > 0 then
      Point.Value := TimeSeries[I].SuccessCount / TimeSeries[I].ExecutionCount * 100
    else
      Point.Value := 0;
    Point.Label_ := FormatPercentage(Point.Value);
    Result.Points[I] := Point;
  end;
end;

function TAnalyticsEngine.GetExecutionCountTrend(ARange: TTimeRange;
  AGranularity: TTimeGranularity): TTrendReport;
var
  TimeSeries: TArray<TTimeBucketStats>;
  Point: TTrendPoint;
begin
  Result.MetricName := 'execution_count';
  Result.Granularity := AGranularity;
  
  TimeSeries := GetTimeSeriesStats(ARange, AGranularity);
  SetLength(Result.Points, Length(TimeSeries));
  
  for var I := 0 to High(TimeSeries) do
  begin
    Point.Timestamp := TimeSeries[I].BucketStart;
    Point.Value := TimeSeries[I].ExecutionCount;
    Point.Label_ := IntToStr(TimeSeries[I].ExecutionCount);
    Result.Points[I] := Point;
  end;
end;

function TAnalyticsEngine.GetLatencyTrend(ARange: TTimeRange;
  AGranularity: TTimeGranularity): TTrendReport;
var
  TimeSeries: TArray<TTimeBucketStats>;
  Point: TTrendPoint;
begin
  Result.MetricName := 'latency';
  Result.Granularity := AGranularity;
  
  TimeSeries := GetTimeSeriesStats(ARange, AGranularity);
  SetLength(Result.Points, Length(TimeSeries));
  
  for var I := 0 to High(TimeSeries) do
  begin
    Point.Timestamp := TimeSeries[I].BucketStart;
    Point.Value := TimeSeries[I].AvgDurationMs;
    Point.Label_ := FormatDuration(TimeSeries[I].AvgDurationMs);
    Result.Points[I] := Point;
  end;
end;

function TAnalyticsEngine.GetHotspotSteps(ARange: TTimeRange;
  ATopN: Integer): TArray<TStepStats>;
var
  AllSteps: TArray<TStepStats>;
  Sorted: TList<TStepStats>;
begin
  AllSteps := GetStepStats(ARange);
  
  Sorted := TList<TStepStats>.Create;
  try
    for var S in AllSteps do
      Sorted.Add(S);
      
    Sorted.Sort(TComparer<TStepStats>.Construct(
      function(const L, R: TStepStats): Integer
      begin
        Result := -CompareValue(L.TotalDurationMs, R.TotalDurationMs);
      end));
      
    if Sorted.Count > ATopN then
      SetLength(Result, ATopN)
    else
      SetLength(Result, Sorted.Count);
      
    for var I := 0 to High(Result) do
      Result[I] := Sorted[I];
  finally
    Sorted.Free;
  end;
end;

function TAnalyticsEngine.GetFailureHotspots(ARange: TTimeRange;
  ATopN: Integer): TArray<TStepStats>;
var
  AllSteps: TArray<TStepStats>;
  Sorted: TList<TStepStats>;
begin
  AllSteps := GetStepStats(ARange);
  
  Sorted := TList<TStepStats>.Create;
  try
    for var S in AllSteps do
      if S.FailedCount > 0 then
        Sorted.Add(S);
      
    Sorted.Sort(TComparer<TStepStats>.Construct(
      function(const L, R: TStepStats): Integer
      begin
        Result := -CompareValue(L.FailedCount, R.FailedCount);
      end));
      
    if Sorted.Count > ATopN then
      SetLength(Result, ATopN)
    else
      SetLength(Result, Sorted.Count);
      
    for var I := 0 to High(Result) do
      Result[I] := Sorted[I];
  finally
    Sorted.Free;
  end;
end;

function TAnalyticsEngine.DetectAnomalies(ARange: TTimeRange): TJSONArray;
var
  Summary: TExecutionSummary;
  Anomaly: TJSONObject;
begin
  Result := TJSONArray.Create;
  
  Summary := GetExecutionSummary(ARange);
  
  // 高失败率警告
  if (Summary.TotalFlows > 10) and (Summary.SuccessRate < 80) then
  begin
    Anomaly := TJSONObject.Create;
    Anomaly.AddPair('type', 'high_failure_rate');
    Anomaly.AddPair('severity', 'warning');
    Anomaly.AddPair('message', Format('Success rate %.1f%% is below 80%%', [Summary.SuccessRate]));
    Anomaly.AddPair('value', TJSONNumber.Create(Summary.SuccessRate));
    Result.Add(Anomaly);
  end;
  
  // 高延迟警�?
  if Summary.AvgDurationMs > 5000 then
  begin
    Anomaly := TJSONObject.Create;
    Anomaly.AddPair('type', 'high_latency');
    Anomaly.AddPair('severity', 'warning');
    Anomaly.AddPair('message', Format('Average duration %s exceeds 5s', [FormatDuration(Summary.AvgDurationMs)]));
    Anomaly.AddPair('value', TJSONNumber.Create(Summary.AvgDurationMs));
    Result.Add(Anomaly);
  end;
  
  // 运行中流程过�?
  if Summary.RunningFlows > 100 then
  begin
    Anomaly := TJSONObject.Create;
    Anomaly.AddPair('type', 'too_many_running');
    Anomaly.AddPair('severity', 'info');
    Anomaly.AddPair('message', Format('%d workflows currently running', [Summary.RunningFlows]));
    Anomaly.AddPair('value', TJSONNumber.Create(Summary.RunningFlows));
    Result.Add(Anomaly);
  end;
end;

function TAnalyticsEngine.ExportFullReport(ARange: TTimeRange): TJSONObject;
var
  Summary: TExecutionSummary;
  WorkflowStats: TArray<TWorkflowStats>;
  StepStats: TArray<TStepStats>;
  ErrorStats: TArray<TErrorStats>;
  Anomalies: TJSONArray;
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  
  // 摘要
  Summary := GetExecutionSummary(ARange);
  Result.AddPair('summary', Summary.ToJSON);
  
  // 工作流统�?
  WorkflowStats := GetWorkflowStats(ARange);
  Arr := TJSONArray.Create;
  for var S in WorkflowStats do
    Arr.Add(S.ToJSON);
  Result.AddPair('workflows', Arr);
  
  // 步骤统计
  StepStats := GetStepStats(ARange);
  Arr := TJSONArray.Create;
  for var S in StepStats do
    Arr.Add(S.ToJSON);
  Result.AddPair('steps', Arr);
  
  // 错误统计
  ErrorStats := GetErrorStats(ARange);
  Arr := TJSONArray.Create;
  for var S in ErrorStats do
    Arr.Add(S.ToJSON);
  Result.AddPair('errors', Arr);
  
  // 趋势
  Result.AddPair('successRateTrend', GetSuccessRateTrend(ARange, tgHour).ToJSON);
  Result.AddPair('executionCountTrend', GetExecutionCountTrend(ARange, tgHour).ToJSON);
  Result.AddPair('latencyTrend', GetLatencyTrend(ARange, tgHour).ToJSON);
  
  // 异常
  Anomalies := DetectAnomalies(ARange);
  Result.AddPair('anomalies', Anomalies);
  
  // 生成时间
  Result.AddPair('generatedAt', DateToISO8601(Now));
end;

function TAnalyticsEngine.ExportHTMLReport(ARange: TTimeRange): string;
var
  Summary: TExecutionSummary;
  SB: TStringBuilder;
begin
  Summary := GetExecutionSummary(ARange);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html lang="en">');
    SB.AppendLine('<head>');
    SB.AppendLine('  <meta charset="UTF-8">');
    SB.AppendLine('  <title>UniFlow Analytics Report</title>');
    SB.AppendLine('  <style>');
    SB.AppendLine('    body { font-family: Arial, sans-serif; margin: 20px; background: #1e1e2e; color: #cdd6f4; }');
    SB.AppendLine('    .card { background: #313244; border-radius: 8px; padding: 20px; margin: 10px 0; }');
    SB.AppendLine('    .stat { display: inline-block; margin: 10px 20px; text-align: center; }');
    SB.AppendLine('    .stat-value { font-size: 2em; font-weight: bold; color: #89b4fa; }');
    SB.AppendLine('    .stat-label { color: #a6adc8; }');
    SB.AppendLine('    h1, h2 { color: #cba6f7; }');
    SB.AppendLine('    .success { color: #a6e3a1; }');
    SB.AppendLine('    .error { color: #f38ba8; }');
    SB.AppendLine('  </style>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.AppendLine('  <h1>UniFlow Analytics Report</h1>');
    SB.AppendFormat('  <p>Generated: %s</p>', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]);
    SB.AppendLine;
    
    SB.AppendLine('  <div class="card">');
    SB.AppendLine('    <h2>Execution Summary</h2>');
    SB.AppendFormat('    <div class="stat"><div class="stat-value">%d</div><div class="stat-label">Total Flows</div></div>', [Summary.TotalFlows]);
    SB.AppendLine;
    SB.AppendFormat('    <div class="stat"><div class="stat-value success">%d</div><div class="stat-label">Completed</div></div>', [Summary.CompletedFlows]);
    SB.AppendLine;
    SB.AppendFormat('    <div class="stat"><div class="stat-value error">%d</div><div class="stat-label">Failed</div></div>', [Summary.FailedFlows]);
    SB.AppendLine;
    SB.AppendFormat('    <div class="stat"><div class="stat-value">%.1f%%</div><div class="stat-label">Success Rate</div></div>', [Summary.SuccessRate]);
    SB.AppendLine;
    SB.AppendFormat('    <div class="stat"><div class="stat-value">%s</div><div class="stat-label">Avg Duration</div></div>', [FormatDuration(Summary.AvgDurationMs)]);
    SB.AppendLine;
    SB.AppendLine('  </div>');
    
    SB.AppendLine('</body>');
    SB.AppendLine('</html>');
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TAnalyticsEngine.ClearCache;
begin
  FCache.Clear;
  FCacheTimestamps.Clear;
end;

// ============================================================================
// TDashboardAPI
// ============================================================================

constructor TDashboardAPI.Create(AEngine: TAnalyticsEngine);
begin
  inherited Create;
  FEngine := AEngine;
end;

function TDashboardAPI.HandleRequest(const APath: string;
  AParams: TJSONObject): TJSONObject;
var
  Range: TTimeRange;
  RangeStr: string;
  GranStr: string;
  Granularity: TTimeGranularity;
begin
  // 解析时间范围
  if AParams.TryGetValue<string>('range', RangeStr) then
  begin
    if RangeStr = 'today' then Range := TTimeRange.Today
    else if RangeStr = 'yesterday' then Range := TTimeRange.Yesterday
    else if RangeStr = '7days' then Range := TTimeRange.Last7Days
    else if RangeStr = '30days' then Range := TTimeRange.Last30Days
    else Range := TTimeRange.Last7Days;
  end
  else
    Range := TTimeRange.Last7Days;
    
  // 解析粒度
  if AParams.TryGetValue<string>('granularity', GranStr) then
    Granularity := StringToGranularity(GranStr)
  else
    Granularity := tgHour;
  
  // 路由
  if APath = '/overview' then
    Result := GetOverview(Range)
  else if APath = '/workflows' then
    Result := GetWorkflows(Range)
  else if APath = '/timeline' then
    Result := GetTimeline(Range, Granularity)
  else if APath = '/errors' then
    Result := GetErrors(Range)
  else if APath = '/trends' then
    Result := GetTrends(Range)
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('error', 'Unknown endpoint');
  end;
end;

function TDashboardAPI.GetOverview(ARange: TTimeRange): TJSONObject;
var
  Summary: TExecutionSummary;
begin
  Summary := FEngine.GetExecutionSummary(ARange);
  Result := Summary.ToJSON;
  Result.AddPair('anomalies', FEngine.DetectAnomalies(ARange));
end;

function TDashboardAPI.GetWorkflows(ARange: TTimeRange): TJSONObject;
var
  Stats: TArray<TWorkflowStats>;
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  Stats := FEngine.GetWorkflowStats(ARange);
  
  Arr := TJSONArray.Create;
  for var S in Stats do
    Arr.Add(S.ToJSON);
  Result.AddPair('workflows', Arr);
  Result.AddPair('count', TJSONNumber.Create(Length(Stats)));
end;

function TDashboardAPI.GetTimeline(ARange: TTimeRange;
  AGranularity: TTimeGranularity): TJSONObject;
var
  TimeSeries: TArray<TTimeBucketStats>;
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  TimeSeries := FEngine.GetTimeSeriesStats(ARange, AGranularity);
  
  Arr := TJSONArray.Create;
  for var S in TimeSeries do
    Arr.Add(S.ToJSON);
  Result.AddPair('timeline', Arr);
  Result.AddPair('granularity', GranularityToString(AGranularity));
end;

function TDashboardAPI.GetErrors(ARange: TTimeRange): TJSONObject;
var
  Stats: TArray<TErrorStats>;
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  Stats := FEngine.GetErrorStats(ARange);
  
  Arr := TJSONArray.Create;
  for var S in Stats do
    Arr.Add(S.ToJSON);
  Result.AddPair('errors', Arr);
  Result.AddPair('count', TJSONNumber.Create(Length(Stats)));
end;

function TDashboardAPI.GetTrends(ARange: TTimeRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('successRate', FEngine.GetSuccessRateTrend(ARange, tgHour).ToJSON);
  Result.AddPair('executionCount', FEngine.GetExecutionCountTrend(ARange, tgHour).ToJSON);
  Result.AddPair('latency', FEngine.GetLatencyTrend(ARange, tgHour).ToJSON);
end;

// ============================================================================
// 辅助函数
// ============================================================================

function GranularityToString(AGranularity: TTimeGranularity): string;
const
  Names: array[TTimeGranularity] of string = ('minute', 'hour', 'day', 'week', 'month');
begin
  Result := Names[AGranularity];
end;

function StringToGranularity(const AStr: string): TTimeGranularity;
begin
  if SameText(AStr, 'minute') then Result := tgMinute
  else if SameText(AStr, 'hour') then Result := tgHour
  else if SameText(AStr, 'day') then Result := tgDay
  else if SameText(AStr, 'week') then Result := tgWeek
  else if SameText(AStr, 'month') then Result := tgMonth
  else Result := tgHour;
end;

function FormatDuration(AMs: Double): string;
begin
  if AMs < 1000 then
    Result := Format('%.0fms', [AMs])
  else if AMs < 60000 then
    Result := Format('%.1fs', [AMs / 1000])
  else
    Result := Format('%.1fm', [AMs / 60000]);
end;

function FormatPercentage(AValue: Double): string;
begin
  Result := Format('%.1f%%', [AValue]);
end;

end.
