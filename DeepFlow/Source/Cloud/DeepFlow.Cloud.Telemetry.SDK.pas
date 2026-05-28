unit UniFlow.Cloud.Telemetry.SDK;

{*******************************************************************************
  UniFlow OpenTelemetry SDK
  
  功能:
  - TracerProvider / Tracer
  - MeterProvider / Meter
  - LoggerProvider / Logger
  - 批处理导出器
  - OTLP HTTP/gRPC 导出
  
  作�? UniFlow Team
  日期: 2024-01
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.SyncObjs, System.Threading, System.Net.HttpClient,
  System.Net.URLClient, System.DateUtils, System.NetEncoding,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  UniFlow.Cloud.Telemetry.Types;

type
  {$REGION 'Tracer Provider'}
  
  /// <summary>采样决策</summary>
  TSamplingDecision = (sdDrop, sdRecordOnly, sdRecordAndSample);
  
  /// <summary>采样器接�?/summary>
  ISampler = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function ShouldSample(AContext: TTraceContext; const AName: string;
      AKind: TSpanKind): TSamplingDecision;
  end;
  
  /// <summary>Span 处理器接�?/summary>
  ISpanProcessor = interface
    ['{B2C3D4E5-F678-90AB-CDEF-123456789012}']
    procedure OnStart(ASpan: TSpan);
    procedure OnEnd(ASpan: TSpan);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>Tracer</summary>
  TTracer = class
  private
    FName: string;
    FVersion: string;
    FSampler: ISampler;
    FProcessors: TList<ISpanProcessor>;
    FResource: TResource;
    FActiveSpan: TSpan;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, AVersion: string; ASampler: ISampler;
      AResource: TResource);
    destructor Destroy; override;
    
    function StartSpan(const AName: string; AKind: TSpanKind = skInternal;
      AParentContext: TTraceContext = nil): TSpan;
    procedure EndSpan(ASpan: TSpan);
    
    procedure AddProcessor(AProcessor: ISpanProcessor);
    
    property Name: string read FName;
    property Version: string read FVersion;
    property ActiveSpan: TSpan read FActiveSpan;
  end;
  
  /// <summary>TracerProvider</summary>
  TTracerProvider = class
  private
    FTracers: TObjectDictionary<string, TTracer>;
    FSampler: ISampler;
    FResource: TResource;
    FProcessors: TList<ISpanProcessor>;
    FLock: TCriticalSection;
  public
    constructor Create(ASampler: ISampler; AResource: TResource);
    destructor Destroy; override;
    
    function GetTracer(const AName: string; const AVersion: string = ''): TTracer;
    procedure AddProcessor(AProcessor: ISpanProcessor);
    procedure Shutdown;
    procedure ForceFlush;
    
    property Resource: TResource read FResource;
  end;
  
  {$ENDREGION}
  
  {$REGION 'Meter Provider'}
  
  /// <summary>Meter</summary>
  TMeter = class
  private
    FName: string;
    FVersion: string;
    FCounters: TObjectDictionary<string, TCounter>;
    FGauges: TObjectDictionary<string, TGauge>;
    FHistograms: TObjectDictionary<string, THistogramMetric>;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, AVersion: string);
    destructor Destroy; override;
    
    function CreateCounter(const AName, ADescription, AUnit: string): TCounter;
    function CreateGauge(const AName, ADescription, AUnit: string): TGauge;
    function CreateHistogram(const AName, ADescription, AUnit: string;
      const ABoundaries: TArray<Double> = nil): THistogramMetric;
    
    function GetCounter(const AName: string): TCounter;
    function GetGauge(const AName: string): TGauge;
    function GetHistogram(const AName: string): THistogramMetric;
    
    function GetAllMetrics: TArray<TMetric>;
    
    property Name: string read FName;
    property Version: string read FVersion;
  end;
  
  /// <summary>指标读取器接�?/summary>
  IMetricReader = interface
    ['{C3D4E5F6-7890-ABCD-EF12-345678901234}']
    procedure Collect(AMetrics: TArray<TMetric>);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>MeterProvider</summary>
  TMeterProvider = class
  private
    FMeters: TObjectDictionary<string, TMeter>;
    FResource: TResource;
    FReaders: TList<IMetricReader>;
    FCollectTimer: TTimer;
    FCollectIntervalMS: Integer;
    FLock: TCriticalSection;
    procedure DoCollect;
  public
    constructor Create(AResource: TResource; ACollectIntervalMS: Integer = 60000);
    destructor Destroy; override;
    
    function GetMeter(const AName: string; const AVersion: string = ''): TMeter;
    procedure AddReader(AReader: IMetricReader);
    procedure Shutdown;
    procedure ForceFlush;
    
    property Resource: TResource read FResource;
  end;
  
  {$ENDREGION}
  
  {$REGION 'Logger Provider'}
  
  /// <summary>日志处理器接�?/summary>
  ILogProcessor = interface
    ['{D4E5F678-90AB-CDEF-1234-567890123456}']
    procedure Process(ARecord: TLogRecord);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>Logger</summary>
  TLogger = class
  private
    FName: string;
    FVersion: string;
    FProcessors: TList<ILogProcessor>;
    FMinSeverity: TLogSeverity;
    FResource: TResource;
    FCurrentContext: TTraceContext;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, AVersion: string; AResource: TResource);
    destructor Destroy; override;
    
    procedure Log(ASeverity: TLogSeverity; const AMessage: string);
    procedure Trace(const AMessage: string);
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warn(const AMessage: string);
    procedure Error(const AMessage: string);
    procedure Fatal(const AMessage: string);
    
    procedure SetContext(AContext: TTraceContext);
    procedure AddProcessor(AProcessor: ILogProcessor);
    
    property Name: string read FName;
    property MinSeverity: TLogSeverity read FMinSeverity write FMinSeverity;
  end;
  
  /// <summary>LoggerProvider</summary>
  TLoggerProvider = class
  private
    FLoggers: TObjectDictionary<string, TLogger>;
    FResource: TResource;
    FProcessors: TList<ILogProcessor>;
    FLock: TCriticalSection;
  public
    constructor Create(AResource: TResource);
    destructor Destroy; override;
    
    function GetLogger(const AName: string; const AVersion: string = ''): TLogger;
    procedure AddProcessor(AProcessor: ILogProcessor);
    procedure Shutdown;
    procedure ForceFlush;
    
    property Resource: TResource read FResource;
  end;
  
  {$ENDREGION}
  
  {$REGION '采样器实�?}
  
  /// <summary>始终采样</summary>
  TAlwaysOnSampler = class(TInterfacedObject, ISampler)
  public
    function ShouldSample(AContext: TTraceContext; const AName: string;
      AKind: TSpanKind): TSamplingDecision;
  end;
  
  /// <summary>始终不采�?/summary>
  TAlwaysOffSampler = class(TInterfacedObject, ISampler)
  public
    function ShouldSample(AContext: TTraceContext; const AName: string;
      AKind: TSpanKind): TSamplingDecision;
  end;
  
  /// <summary>TraceId 比例采样</summary>
  TTraceIdRatioSampler = class(TInterfacedObject, ISampler)
  private
    FRatio: Double;
  public
    constructor Create(ARatio: Double);
    function ShouldSample(AContext: TTraceContext; const AName: string;
      AKind: TSpanKind): TSamplingDecision;
  end;
  
  /// <summary>基于父级采样</summary>
  TParentBasedSampler = class(TInterfacedObject, ISampler)
  private
    FRootSampler: ISampler;
  public
    constructor Create(ARootSampler: ISampler);
    function ShouldSample(AContext: TTraceContext; const AName: string;
      AKind: TSpanKind): TSamplingDecision;
  end;
  
  {$ENDREGION}
  
  {$REGION '批处理导出器'}
  
  /// <summary>批处�?Span 处理�?/summary>
  TBatchSpanProcessor = class(TInterfacedObject, ISpanProcessor)
  private
    FQueue: TThreadedQueue<TSpan>;
    FBatchSize: Integer;
    FExportTimeoutMS: Integer;
    FExportIntervalMS: Integer;
    FExporter: ISpanProcessor;
    FExportThread: TThread;
    FShutdown: Boolean;
    FLock: TCriticalSection;
    procedure ExportBatch;
  public
    constructor Create(AExporter: ISpanProcessor; ABatchSize: Integer = 512;
      AExportIntervalMS: Integer = 5000; AExportTimeoutMS: Integer = 30000);
    destructor Destroy; override;
    
    procedure OnStart(ASpan: TSpan);
    procedure OnEnd(ASpan: TSpan);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>简�?Span 处理�?/summary>
  TSimpleSpanProcessor = class(TInterfacedObject, ISpanProcessor)
  private
    FExporter: ISpanProcessor;
  public
    constructor Create(AExporter: ISpanProcessor);
    procedure OnStart(ASpan: TSpan);
    procedure OnEnd(ASpan: TSpan);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  {$ENDREGION}
  
  {$REGION 'OTLP 导出�?}
  
  /// <summary>OTLP HTTP Span 导出�?/summary>
  TOTLPHttpSpanExporter = class(TInterfacedObject, ISpanProcessor)
  private
    FEndpoint: string;
    FHeaders: TDictionary<string, string>;
    FHttpClient: THTTPClient;
    FCompression: Boolean;
    FTimeoutMS: Integer;
    FResource: TResource;
    FPendingSpans: TObjectList<TSpan>;
    FLock: TCriticalSection;
    
    function BuildExportRequest: TJSONObject;
    procedure DoExport;
  public
    constructor Create(const AEndpoint: string; AResource: TResource;
      AHeaders: TDictionary<string, string> = nil;
      ACompression: Boolean = True; ATimeoutMS: Integer = 30000);
    destructor Destroy; override;
    
    procedure OnStart(ASpan: TSpan);
    procedure OnEnd(ASpan: TSpan);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>OTLP HTTP 指标导出�?/summary>
  TOTLPHttpMetricExporter = class(TInterfacedObject, IMetricReader)
  private
    FEndpoint: string;
    FHeaders: TDictionary<string, string>;
    FHttpClient: THTTPClient;
    FCompression: Boolean;
    FTimeoutMS: Integer;
    FResource: TResource;
    FLock: TCriticalSection;
    
    function BuildExportRequest(AMetrics: TArray<TMetric>): TJSONObject;
    procedure DoExport(AMetrics: TArray<TMetric>);
  public
    constructor Create(const AEndpoint: string; AResource: TResource;
      AHeaders: TDictionary<string, string> = nil;
      ACompression: Boolean = True; ATimeoutMS: Integer = 30000);
    destructor Destroy; override;
    
    procedure Collect(AMetrics: TArray<TMetric>);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>OTLP HTTP 日志导出�?/summary>
  TOTLPHttpLogExporter = class(TInterfacedObject, ILogProcessor)
  private
    FEndpoint: string;
    FHeaders: TDictionary<string, string>;
    FHttpClient: THTTPClient;
    FCompression: Boolean;
    FTimeoutMS: Integer;
    FResource: TResource;
    FPendingLogs: TObjectList<TLogRecord>;
    FLock: TCriticalSection;
    
    function BuildExportRequest: TJSONObject;
    procedure DoExport;
  public
    constructor Create(const AEndpoint: string; AResource: TResource;
      AHeaders: TDictionary<string, string> = nil;
      ACompression: Boolean = True; ATimeoutMS: Integer = 30000);
    destructor Destroy; override;
    
    procedure Process(ARecord: TLogRecord);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  /// <summary>控制台导出器</summary>
  TConsoleSpanExporter = class(TInterfacedObject, ISpanProcessor)
  public
    procedure OnStart(ASpan: TSpan);
    procedure OnEnd(ASpan: TSpan);
    procedure Shutdown;
    procedure ForceFlush;
  end;
  
  {$ENDREGION}
  
  {$REGION 'OpenTelemetry 全局实例'}
  
  /// <summary>OpenTelemetry SDK</summary>
  TOpenTelemetry = class
  private
    class var FInstance: TOpenTelemetry;
    class var FLock: TCriticalSection;
    
    FTracerProvider: TTracerProvider;
    FMeterProvider: TMeterProvider;
    FLoggerProvider: TLoggerProvider;
    FConfig: TOTelConfig;
    FInitialized: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    
    class function Instance: TOpenTelemetry;
    class procedure Initialize(const AConfig: TOTelConfig);
    class procedure Shutdown;
    
    function GetTracer(const AName: string): TTracer;
    function GetMeter(const AName: string): TMeter;
    function GetLogger(const AName: string): TLogger;
    
    property TracerProvider: TTracerProvider read FTracerProvider;
    property MeterProvider: TMeterProvider read FMeterProvider;
    property LoggerProvider: TLoggerProvider read FLoggerProvider;
    property Config: TOTelConfig read FConfig;
    property Initialized: Boolean read FInitialized;
  end;
  
  {$ENDREGION}

/// <summary>全局便捷函数</summary>
function OTel: TOpenTelemetry;

implementation

function OTel: TOpenTelemetry;
begin
  Result := TOpenTelemetry.Instance;
end;

{$REGION 'TTracer'}

constructor TTracer.Create(const AName, AVersion: string; ASampler: ISampler;
  AResource: TResource);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FName := AName;
  FVersion := AVersion;
  FSampler := ASampler;
  FResource := AResource;
  FProcessors := TList<ISpanProcessor>.Create;
end;

destructor TTracer.Destroy;
begin
  FProcessors.Free;
  FLock.Free;
  inherited;
end;

function TTracer.StartSpan(const AName: string; AKind: TSpanKind;
  AParentContext: TTraceContext): TSpan;
var
  Context: TTraceContext;
  Decision: TSamplingDecision;
  Processor: ISpanProcessor;
begin
  // 创建上下�?
  if Assigned(AParentContext) then
    Context := AParentContext.CreateChildContext
  else
  begin
    Context := TTraceContext.Create;
    Context.TraceId := TTraceContext.NewTraceId;
    Context.SpanId := TTraceContext.NewSpanId;
  end;
  
  // 采样决策
  Decision := FSampler.ShouldSample(Context, AName, AKind);
  if Decision = sdDrop then
  begin
    Context.Free;
    Result := nil;
    Exit;
  end;
  
  // 创建 Span
  Result := TSpan.Create(AName, AKind, Context);
  
  // 通知处理�?
  FLock.Enter;
  try
    for Processor in FProcessors do
      Processor.OnStart(Result);
    FActiveSpan := Result;
  finally
    FLock.Leave;
  end;
end;

procedure TTracer.EndSpan(ASpan: TSpan);
var
  Processor: ISpanProcessor;
begin
  if Assigned(ASpan) then
  begin
    ASpan.Finish;
    
    FLock.Enter;
    try
      for Processor in FProcessors do
        Processor.OnEnd(ASpan);
      
      if FActiveSpan = ASpan then
        FActiveSpan := nil;
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TTracer.AddProcessor(AProcessor: ISpanProcessor);
begin
  FLock.Enter;
  try
    FProcessors.Add(AProcessor);
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TTracerProvider'}

constructor TTracerProvider.Create(ASampler: ISampler; AResource: TResource);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FTracers := TObjectDictionary<string, TTracer>.Create([doOwnsValues]);
  FSampler := ASampler;
  FResource := AResource;
  FProcessors := TList<ISpanProcessor>.Create;
end;

destructor TTracerProvider.Destroy;
begin
  Shutdown;
  FProcessors.Free;
  FTracers.Free;
  FResource.Free;
  FLock.Free;
  inherited;
end;

function TTracerProvider.GetTracer(const AName, AVersion: string): TTracer;
var
  Key: string;
begin
  Key := AName + '@' + AVersion;
  
  FLock.Enter;
  try
    if not FTracers.TryGetValue(Key, Result) then
    begin
      Result := TTracer.Create(AName, AVersion, FSampler, FResource);
      for var P in FProcessors do
        Result.AddProcessor(P);
      FTracers.Add(Key, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TTracerProvider.AddProcessor(AProcessor: ISpanProcessor);
var
  Tracer: TTracer;
begin
  FLock.Enter;
  try
    FProcessors.Add(AProcessor);
    for Tracer in FTracers.Values do
      Tracer.AddProcessor(AProcessor);
  finally
    FLock.Leave;
  end;
end;

procedure TTracerProvider.Shutdown;
var
  Processor: ISpanProcessor;
begin
  FLock.Enter;
  try
    for Processor in FProcessors do
      Processor.Shutdown;
  finally
    FLock.Leave;
  end;
end;

procedure TTracerProvider.ForceFlush;
var
  Processor: ISpanProcessor;
begin
  FLock.Enter;
  try
    for Processor in FProcessors do
      Processor.ForceFlush;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TMeter'}

constructor TMeter.Create(const AName, AVersion: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FName := AName;
  FVersion := AVersion;
  FCounters := TObjectDictionary<string, TCounter>.Create([doOwnsValues]);
  FGauges := TObjectDictionary<string, TGauge>.Create([doOwnsValues]);
  FHistograms := TObjectDictionary<string, THistogramMetric>.Create([doOwnsValues]);
end;

destructor TMeter.Destroy;
begin
  FHistograms.Free;
  FGauges.Free;
  FCounters.Free;
  FLock.Free;
  inherited;
end;

function TMeter.CreateCounter(const AName, ADescription, AUnit: string): TCounter;
begin
  FLock.Enter;
  try
    if not FCounters.TryGetValue(AName, Result) then
    begin
      Result := TCounter.Create(AName, ADescription, AUnit);
      FCounters.Add(AName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMeter.CreateGauge(const AName, ADescription, AUnit: string): TGauge;
begin
  FLock.Enter;
  try
    if not FGauges.TryGetValue(AName, Result) then
    begin
      Result := TGauge.Create(AName, ADescription, AUnit);
      FGauges.Add(AName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMeter.CreateHistogram(const AName, ADescription, AUnit: string;
  const ABoundaries: TArray<Double>): THistogramMetric;
var
  Boundaries: TArray<Double>;
begin
  if Length(ABoundaries) = 0 then
    Boundaries := [0, 5, 10, 25, 50, 75, 100, 250, 500, 750, 1000, 2500, 5000, 7500, 10000]
  else
    Boundaries := ABoundaries;
    
  FLock.Enter;
  try
    if not FHistograms.TryGetValue(AName, Result) then
    begin
      Result := THistogramMetric.Create(AName, ADescription, AUnit, Boundaries);
      FHistograms.Add(AName, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMeter.GetCounter(const AName: string): TCounter;
begin
  FLock.Enter;
  try
    FCounters.TryGetValue(AName, Result);
  finally
    FLock.Leave;
  end;
end;

function TMeter.GetGauge(const AName: string): TGauge;
begin
  FLock.Enter;
  try
    FGauges.TryGetValue(AName, Result);
  finally
    FLock.Leave;
  end;
end;

function TMeter.GetHistogram(const AName: string): THistogramMetric;
begin
  FLock.Enter;
  try
    FHistograms.TryGetValue(AName, Result);
  finally
    FLock.Leave;
  end;
end;

function TMeter.GetAllMetrics: TArray<TMetric>;
var
  List: TList<TMetric>;
  Counter: TCounter;
  Gauge: TGauge;
  Histogram: THistogramMetric;
begin
  List := TList<TMetric>.Create;
  try
    FLock.Enter;
    try
      for Counter in FCounters.Values do
        List.Add(Counter.Metric);
      for Gauge in FGauges.Values do
        List.Add(Gauge.Metric);
      for Histogram in FHistograms.Values do
        List.Add(Histogram.Metric);
    finally
      FLock.Leave;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TMeterProvider'}

constructor TMeterProvider.Create(AResource: TResource; ACollectIntervalMS: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMeters := TObjectDictionary<string, TMeter>.Create([doOwnsValues]);
  FResource := AResource;
  FReaders := TList<IMetricReader>.Create;
  FCollectIntervalMS := ACollectIntervalMS;
end;

destructor TMeterProvider.Destroy;
begin
  Shutdown;
  FReaders.Free;
  FMeters.Free;
  FResource.Free;
  FLock.Free;
  inherited;
end;

function TMeterProvider.GetMeter(const AName, AVersion: string): TMeter;
var
  Key: string;
begin
  Key := AName + '@' + AVersion;
  
  FLock.Enter;
  try
    if not FMeters.TryGetValue(Key, Result) then
    begin
      Result := TMeter.Create(AName, AVersion);
      FMeters.Add(Key, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMeterProvider.AddReader(AReader: IMetricReader);
begin
  FLock.Enter;
  try
    FReaders.Add(AReader);
  finally
    FLock.Leave;
  end;
end;

procedure TMeterProvider.DoCollect;
var
  Meter: TMeter;
  Metrics: TList<TMetric>;
  Reader: IMetricReader;
begin
  Metrics := TList<TMetric>.Create;
  try
    FLock.Enter;
    try
      for Meter in FMeters.Values do
        Metrics.AddRange(Meter.GetAllMetrics);
        
      for Reader in FReaders do
        Reader.Collect(Metrics.ToArray);
    finally
      FLock.Leave;
    end;
  finally
    Metrics.Free;
  end;
end;

procedure TMeterProvider.Shutdown;
var
  Reader: IMetricReader;
begin
  FLock.Enter;
  try
    for Reader in FReaders do
      Reader.Shutdown;
  finally
    FLock.Leave;
  end;
end;

procedure TMeterProvider.ForceFlush;
var
  Reader: IMetricReader;
begin
  DoCollect;
  FLock.Enter;
  try
    for Reader in FReaders do
      Reader.ForceFlush;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TLogger'}

constructor TLogger.Create(const AName, AVersion: string; AResource: TResource);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FName := AName;
  FVersion := AVersion;
  FResource := AResource;
  FProcessors := TList<ILogProcessor>.Create;
  FMinSeverity := lsInfo;
end;

destructor TLogger.Destroy;
begin
  FProcessors.Free;
  FLock.Free;
  inherited;
end;

procedure TLogger.Log(ASeverity: TLogSeverity; const AMessage: string);
var
  LogRecord: TLogRecord;
  Processor: ILogProcessor;
begin
  if ASeverity < FMinSeverity then Exit;
  
  LogRecord := TLogRecord.Create(ASeverity, AMessage);
  try
    LogRecord.SetTraceContext(FCurrentContext);
    
    FLock.Enter;
    try
      for Processor in FProcessors do
        Processor.Process(LogRecord);
    finally
      FLock.Leave;
    end;
  finally
    LogRecord.Free;
  end;
end;

procedure TLogger.Trace(const AMessage: string);
begin
  Log(lsTrace, AMessage);
end;

procedure TLogger.Debug(const AMessage: string);
begin
  Log(lsDebug, AMessage);
end;

procedure TLogger.Info(const AMessage: string);
begin
  Log(lsInfo, AMessage);
end;

procedure TLogger.Warn(const AMessage: string);
begin
  Log(lsWarn, AMessage);
end;

procedure TLogger.Error(const AMessage: string);
begin
  Log(lsError, AMessage);
end;

procedure TLogger.Fatal(const AMessage: string);
begin
  Log(lsFatal, AMessage);
end;

procedure TLogger.SetContext(AContext: TTraceContext);
begin
  FCurrentContext := AContext;
end;

procedure TLogger.AddProcessor(AProcessor: ILogProcessor);
begin
  FLock.Enter;
  try
    FProcessors.Add(AProcessor);
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TLoggerProvider'}

constructor TLoggerProvider.Create(AResource: TResource);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FLoggers := TObjectDictionary<string, TLogger>.Create([doOwnsValues]);
  FResource := AResource;
  FProcessors := TList<ILogProcessor>.Create;
end;

destructor TLoggerProvider.Destroy;
begin
  Shutdown;
  FProcessors.Free;
  FLoggers.Free;
  FResource.Free;
  FLock.Free;
  inherited;
end;

function TLoggerProvider.GetLogger(const AName, AVersion: string): TLogger;
var
  Key: string;
begin
  Key := AName + '@' + AVersion;
  
  FLock.Enter;
  try
    if not FLoggers.TryGetValue(Key, Result) then
    begin
      Result := TLogger.Create(AName, AVersion, FResource);
      for var P in FProcessors do
        Result.AddProcessor(P);
      FLoggers.Add(Key, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TLoggerProvider.AddProcessor(AProcessor: ILogProcessor);
var
  Logger: TLogger;
begin
  FLock.Enter;
  try
    FProcessors.Add(AProcessor);
    for Logger in FLoggers.Values do
      Logger.AddProcessor(AProcessor);
  finally
    FLock.Leave;
  end;
end;

procedure TLoggerProvider.Shutdown;
var
  Processor: ILogProcessor;
begin
  FLock.Enter;
  try
    for Processor in FProcessors do
      Processor.Shutdown;
  finally
    FLock.Leave;
  end;
end;

procedure TLoggerProvider.ForceFlush;
var
  Processor: ILogProcessor;
begin
  FLock.Enter;
  try
    for Processor in FProcessors do
      Processor.ForceFlush;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION '采样器实�?}

function TAlwaysOnSampler.ShouldSample(AContext: TTraceContext;
  const AName: string; AKind: TSpanKind): TSamplingDecision;
begin
  Result := sdRecordAndSample;
end;

function TAlwaysOffSampler.ShouldSample(AContext: TTraceContext;
  const AName: string; AKind: TSpanKind): TSamplingDecision;
begin
  Result := sdDrop;
end;

constructor TTraceIdRatioSampler.Create(ARatio: Double);
begin
  inherited Create;
  FRatio := ARatio;
  if FRatio < 0 then FRatio := 0;
  if FRatio > 1 then FRatio := 1;
end;

function TTraceIdRatioSampler.ShouldSample(AContext: TTraceContext;
  const AName: string; AKind: TSpanKind): TSamplingDecision;
begin
  if Random < FRatio then
    Result := sdRecordAndSample
  else
    Result := sdDrop;
end;

constructor TParentBasedSampler.Create(ARootSampler: ISampler);
begin
  inherited Create;
  FRootSampler := ARootSampler;
end;

function TParentBasedSampler.ShouldSample(AContext: TTraceContext;
  const AName: string; AKind: TSpanKind): TSamplingDecision;
begin
  if Assigned(AContext) and (AContext.ParentSpanId <> '') then
  begin
    // 有父级，根据父级采样标志
    if (AContext.TraceFlags and 1) = 1 then
      Result := sdRecordAndSample
    else
      Result := sdDrop;
  end
  else
  begin
    // 无父级，使用根采样器
    Result := FRootSampler.ShouldSample(AContext, AName, AKind);
  end;
end;

{$ENDREGION}

{$REGION '批处理导出器'}

constructor TBatchSpanProcessor.Create(AExporter: ISpanProcessor;
  ABatchSize, AExportIntervalMS, AExportTimeoutMS: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FQueue := TThreadedQueue<TSpan>.Create(10000, 100, 100);
  FExporter := AExporter;
  FBatchSize := ABatchSize;
  FExportIntervalMS := AExportIntervalMS;
  FExportTimeoutMS := AExportTimeoutMS;
  FShutdown := False;
  
  // 启动导出线程
  FExportThread := TThread.CreateAnonymousThread(
    procedure
    begin
      while not FShutdown do
      begin
        Sleep(FExportIntervalMS);
        if not FShutdown then
          ExportBatch;
      end;
    end
  );
  FExportThread.FreeOnTerminate := False;
  FExportThread.Start;
end;

destructor TBatchSpanProcessor.Destroy;
begin
  Shutdown;
  FExportThread.Free;
  FQueue.Free;
  FLock.Free;
  inherited;
end;

procedure TBatchSpanProcessor.OnStart(ASpan: TSpan);
begin
  // 批处理器不处�?OnStart
end;

procedure TBatchSpanProcessor.OnEnd(ASpan: TSpan);
begin
  if not FShutdown then
    FQueue.PushItem(ASpan);
end;

procedure TBatchSpanProcessor.ExportBatch;
var
  Span: TSpan;
  Count: Integer;
begin
  Count := 0;
  while (Count < FBatchSize) and (FQueue.PopItem(Span) = wrSignaled) do
  begin
    FExporter.OnEnd(Span);
    Inc(Count);
  end;
end;

procedure TBatchSpanProcessor.Shutdown;
begin
  FShutdown := True;
  FExportThread.Terminate;
  FExportThread.WaitFor;
  ForceFlush;
  FExporter.Shutdown;
end;

procedure TBatchSpanProcessor.ForceFlush;
begin
  ExportBatch;
  FExporter.ForceFlush;
end;

constructor TSimpleSpanProcessor.Create(AExporter: ISpanProcessor);
begin
  inherited Create;
  FExporter := AExporter;
end;

procedure TSimpleSpanProcessor.OnStart(ASpan: TSpan);
begin
  FExporter.OnStart(ASpan);
end;

procedure TSimpleSpanProcessor.OnEnd(ASpan: TSpan);
begin
  FExporter.OnEnd(ASpan);
end;

procedure TSimpleSpanProcessor.Shutdown;
begin
  FExporter.Shutdown;
end;

procedure TSimpleSpanProcessor.ForceFlush;
begin
  FExporter.ForceFlush;
end;

{$ENDREGION}

{$REGION 'OTLP 导出�?}

constructor TOTLPHttpSpanExporter.Create(const AEndpoint: string;
  AResource: TResource; AHeaders: TDictionary<string, string>;
  ACompression: Boolean; ATimeoutMS: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEndpoint := AEndpoint;
  FResource := AResource;
  FHeaders := AHeaders;
  FCompression := ACompression;
  FTimeoutMS := ATimeoutMS;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ConnectionTimeout := ATimeoutMS;
  FHttpClient.ResponseTimeout := ATimeoutMS;
  FPendingSpans := TObjectList<TSpan>.Create(False);
end;

destructor TOTLPHttpSpanExporter.Destroy;
begin
  FPendingSpans.Free;
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

procedure TOTLPHttpSpanExporter.OnStart(ASpan: TSpan);
begin
  // OTLP 导出器不处理 OnStart
end;

procedure TOTLPHttpSpanExporter.OnEnd(ASpan: TSpan);
begin
  FLock.Enter;
  try
    FPendingSpans.Add(ASpan);
  finally
    FLock.Leave;
  end;
end;

function TOTLPHttpSpanExporter.BuildExportRequest: TJSONObject;
var
  ResourceSpans, ScopeSpans, Spans: TJSONArray;
  ResourceObj, ScopeObj: TJSONObject;
  Span: TSpan;
begin
  Result := TJSONObject.Create;
  
  ResourceSpans := TJSONArray.Create;
  Result.AddPair('resourceSpans', ResourceSpans);
  
  ResourceObj := TJSONObject.Create;
  ResourceSpans.Add(ResourceObj);
  
  if Assigned(FResource) then
    ResourceObj.AddPair('resource', FResource.ToJSON)
  else
    ResourceObj.AddPair('resource', TJSONObject.Create);
  
  ScopeSpans := TJSONArray.Create;
  ResourceObj.AddPair('scopeSpans', ScopeSpans);
  
  ScopeObj := TJSONObject.Create;
  ScopeSpans.Add(ScopeObj);
  ScopeObj.AddPair('scope', TJSONObject.Create
    .AddPair('name', 'uniflow')
    .AddPair('version', '1.0.0'));
  
  Spans := TJSONArray.Create;
  ScopeObj.AddPair('spans', Spans);
  
  FLock.Enter;
  try
    for Span in FPendingSpans do
      Spans.Add(Span.ToJSON);
    FPendingSpans.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TOTLPHttpSpanExporter.DoExport;
var
  Request: TJSONObject;
  Response: IHTTPResponse;
  Headers: TArray<TNameValuePair>;
  Key: string;
  I: Integer;
begin
  Request := BuildExportRequest;
  try
    // 构建请求�?
    SetLength(Headers, 1);
    Headers[0] := TNameValuePair.Create('Content-Type', 'application/json');
    
    if Assigned(FHeaders) then
    begin
      I := Length(Headers);
      SetLength(Headers, I + FHeaders.Count);
      for Key in FHeaders.Keys do
      begin
        Headers[I] := TNameValuePair.Create(Key, FHeaders[Key]);
        Inc(I);
      end;
    end;
    
    try
      Response := FHttpClient.Post(FEndpoint + '/v1/traces',
        TStringStream.Create(Request.ToJSON, TEncoding.UTF8),
        nil, Headers);
    except
      on E: Exception do
      begin
        // ENTROPY-011: 记录遥测导出失败（不影响主流程）
        {$IFDEF DEBUG}
        OutputDebugString(PChar(Format('[OTLP] Trace export failed: %s', [E.Message])));
        {$ENDIF}
      end;
    end;
  finally
    Request.Free;
  end;
end;

procedure TOTLPHttpSpanExporter.Shutdown;
begin
  ForceFlush;
end;

procedure TOTLPHttpSpanExporter.ForceFlush;
begin
  DoExport;
end;

// TOTLPHttpMetricExporter

constructor TOTLPHttpMetricExporter.Create(const AEndpoint: string;
  AResource: TResource; AHeaders: TDictionary<string, string>;
  ACompression: Boolean; ATimeoutMS: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEndpoint := AEndpoint;
  FResource := AResource;
  FHeaders := AHeaders;
  FCompression := ACompression;
  FTimeoutMS := ATimeoutMS;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ConnectionTimeout := ATimeoutMS;
  FHttpClient.ResponseTimeout := ATimeoutMS;
end;

destructor TOTLPHttpMetricExporter.Destroy;
begin
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

function TOTLPHttpMetricExporter.BuildExportRequest(AMetrics: TArray<TMetric>): TJSONObject;
var
  ResourceMetrics, ScopeMetrics, Metrics: TJSONArray;
  ResourceObj, ScopeObj: TJSONObject;
  Metric: TMetric;
begin
  Result := TJSONObject.Create;
  
  ResourceMetrics := TJSONArray.Create;
  Result.AddPair('resourceMetrics', ResourceMetrics);
  
  ResourceObj := TJSONObject.Create;
  ResourceMetrics.Add(ResourceObj);
  
  if Assigned(FResource) then
    ResourceObj.AddPair('resource', FResource.ToJSON)
  else
    ResourceObj.AddPair('resource', TJSONObject.Create);
  
  ScopeMetrics := TJSONArray.Create;
  ResourceObj.AddPair('scopeMetrics', ScopeMetrics);
  
  ScopeObj := TJSONObject.Create;
  ScopeMetrics.Add(ScopeObj);
  ScopeObj.AddPair('scope', TJSONObject.Create
    .AddPair('name', 'uniflow')
    .AddPair('version', '1.0.0'));
  
  Metrics := TJSONArray.Create;
  ScopeObj.AddPair('metrics', Metrics);
  
  for Metric in AMetrics do
    Metrics.Add(Metric.ToJSON);
end;

procedure TOTLPHttpMetricExporter.DoExport(AMetrics: TArray<TMetric>);
var
  Request: TJSONObject;
  Response: IHTTPResponse;
  Headers: TArray<TNameValuePair>;
begin
  Request := BuildExportRequest(AMetrics);
  try
    SetLength(Headers, 1);
    Headers[0] := TNameValuePair.Create('Content-Type', 'application/json');
    
    try
      Response := FHttpClient.Post(FEndpoint + '/v1/metrics',
        TStringStream.Create(Request.ToJSON, TEncoding.UTF8),
        nil, Headers);
    except
      on E: Exception do
      begin
        // ENTROPY-011: 记录指标导出失败
        {$IFDEF DEBUG}
        OutputDebugString(PChar(Format('[OTLP] Metrics export failed: %s', [E.Message])));
        {$ENDIF}
      end;
    end;
  finally
    Request.Free;
  end;
end;

procedure TOTLPHttpMetricExporter.Collect(AMetrics: TArray<TMetric>);
begin
  DoExport(AMetrics);
end;

procedure TOTLPHttpMetricExporter.Shutdown;
begin
  // 无操�?
end;

procedure TOTLPHttpMetricExporter.ForceFlush;
begin
  // 无操�?
end;

// TOTLPHttpLogExporter

constructor TOTLPHttpLogExporter.Create(const AEndpoint: string;
  AResource: TResource; AHeaders: TDictionary<string, string>;
  ACompression: Boolean; ATimeoutMS: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEndpoint := AEndpoint;
  FResource := AResource;
  FHeaders := AHeaders;
  FCompression := ACompression;
  FTimeoutMS := ATimeoutMS;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ConnectionTimeout := ATimeoutMS;
  FHttpClient.ResponseTimeout := ATimeoutMS;
  FPendingLogs := TObjectList<TLogRecord>.Create(False);
end;

destructor TOTLPHttpLogExporter.Destroy;
begin
  FPendingLogs.Free;
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

procedure TOTLPHttpLogExporter.Process(ARecord: TLogRecord);
begin
  FLock.Enter;
  try
    FPendingLogs.Add(ARecord);
    if FPendingLogs.Count >= 100 then
      DoExport;
  finally
    FLock.Leave;
  end;
end;

function TOTLPHttpLogExporter.BuildExportRequest: TJSONObject;
var
  ResourceLogs, ScopeLogs, Logs: TJSONArray;
  ResourceObj, ScopeObj: TJSONObject;
  LogRecord: TLogRecord;
begin
  Result := TJSONObject.Create;
  
  ResourceLogs := TJSONArray.Create;
  Result.AddPair('resourceLogs', ResourceLogs);
  
  ResourceObj := TJSONObject.Create;
  ResourceLogs.Add(ResourceObj);
  
  if Assigned(FResource) then
    ResourceObj.AddPair('resource', FResource.ToJSON)
  else
    ResourceObj.AddPair('resource', TJSONObject.Create);
  
  ScopeLogs := TJSONArray.Create;
  ResourceObj.AddPair('scopeLogs', ScopeLogs);
  
  ScopeObj := TJSONObject.Create;
  ScopeLogs.Add(ScopeObj);
  ScopeObj.AddPair('scope', TJSONObject.Create
    .AddPair('name', 'uniflow')
    .AddPair('version', '1.0.0'));
  
  Logs := TJSONArray.Create;
  ScopeObj.AddPair('logRecords', Logs);
  
  for LogRecord in FPendingLogs do
    Logs.Add(LogRecord.ToJSON);
  FPendingLogs.Clear;
end;

procedure TOTLPHttpLogExporter.DoExport;
var
  Request: TJSONObject;
  Response: IHTTPResponse;
  Headers: TArray<TNameValuePair>;
begin
  if FPendingLogs.Count = 0 then Exit;
  
  Request := BuildExportRequest;
  try
    SetLength(Headers, 1);
    Headers[0] := TNameValuePair.Create('Content-Type', 'application/json');
    
    try
      Response := FHttpClient.Post(FEndpoint + '/v1/logs',
        TStringStream.Create(Request.ToJSON, TEncoding.UTF8),
        nil, Headers);
    except
      on E: Exception do
      begin
        // ENTROPY-011: 记录日志导出失败
        {$IFDEF DEBUG}
        OutputDebugString(PChar(Format('[OTLP] Log export failed: %s', [E.Message])));
        {$ENDIF}
      end;
    end;
  finally
    Request.Free;
  end;
end;

procedure TOTLPHttpLogExporter.Shutdown;
begin
  ForceFlush;
end;

procedure TOTLPHttpLogExporter.ForceFlush;
begin
  FLock.Enter;
  try
    DoExport;
  finally
    FLock.Leave;
  end;
end;

// TConsoleSpanExporter

procedure TConsoleSpanExporter.OnStart(ASpan: TSpan);
begin
  WriteLn(Format('[SPAN START] %s (TraceId: %s, SpanId: %s)',
    [ASpan.Name, ASpan.Context.TraceId, ASpan.Context.SpanId]));
end;

procedure TConsoleSpanExporter.OnEnd(ASpan: TSpan);
var
  DurationMS: Int64;
begin
  DurationMS := MilliSecondsBetween(ASpan.EndTime, ASpan.StartTime);
  WriteLn(Format('[SPAN END] %s (Duration: %dms, Status: %d)',
    [ASpan.Name, DurationMS, Ord(ASpan.Status)]));
end;

procedure TConsoleSpanExporter.Shutdown;
begin
  // 无操�?
end;

procedure TConsoleSpanExporter.ForceFlush;
begin
  // 无操�?
end;

{$ENDREGION}

{$REGION 'TOpenTelemetry'}

constructor TOpenTelemetry.Create;
begin
  inherited Create;
  FInitialized := False;
end;

destructor TOpenTelemetry.Destroy;
begin
  if FInitialized then
  begin
    FTracerProvider.Free;
    FMeterProvider.Free;
    FLoggerProvider.Free;
  end;
  inherited;
end;

class function TOpenTelemetry.Instance: TOpenTelemetry;
begin
  if not Assigned(FLock) then
    FLock := TCriticalSection.Create;
    
  FLock.Enter;
  try
    if not Assigned(FInstance) then
      FInstance := TOpenTelemetry.Create;
    Result := FInstance;
  finally
    FLock.Leave;
  end;
end;

class procedure TOpenTelemetry.Initialize(const AConfig: TOTelConfig);
var
  Sampler: ISampler;
  Resource: TResource;
  SpanExporter: ISpanProcessor;
  MetricExporter: IMetricReader;
  LogExporter: ILogProcessor;
begin
  with Instance do
  begin
    if FInitialized then Exit;
    
    FConfig := AConfig;
    
    // 创建资源
    Resource := TResource.Default;
    Resource.SetServiceInfo(AConfig.ServiceName, AConfig.ServiceVersion, '');
    
    // 创建采样�?
    case AConfig.Sampler.SamplerType of
      stAlwaysOn: Sampler := TAlwaysOnSampler.Create;
      stAlwaysOff: Sampler := TAlwaysOffSampler.Create;
      stTraceIdRatio: Sampler := TTraceIdRatioSampler.Create(AConfig.Sampler.Ratio);
      stParentBased: Sampler := TParentBasedSampler.Create(
        TTraceIdRatioSampler.Create(AConfig.Sampler.Ratio));
    else
      Sampler := TAlwaysOnSampler.Create;
    end;
    
    // 创建 Provider
    FTracerProvider := TTracerProvider.Create(Sampler, Resource);
    FMeterProvider := TMeterProvider.Create(TResource.Default, 60000);
    FLoggerProvider := TLoggerProvider.Create(TResource.Default);
    
    // 配置导出�?
    case AConfig.TracesExporter.ExporterType of
      etOTLP:
        SpanExporter := TOTLPHttpSpanExporter.Create(
          AConfig.TracesExporter.Endpoint, TResource.Default);
      etConsole:
        SpanExporter := TConsoleSpanExporter.Create;
    else
      SpanExporter := TConsoleSpanExporter.Create;
    end;
    
    FTracerProvider.AddProcessor(TBatchSpanProcessor.Create(SpanExporter));
    
    if AConfig.MetricsExporter.ExporterType = etOTLP then
    begin
      MetricExporter := TOTLPHttpMetricExporter.Create(
        AConfig.MetricsExporter.Endpoint, TResource.Default);
      FMeterProvider.AddReader(MetricExporter);
    end;
    
    if AConfig.LogsExporter.ExporterType = etOTLP then
    begin
      LogExporter := TOTLPHttpLogExporter.Create(
        AConfig.LogsExporter.Endpoint, TResource.Default);
      FLoggerProvider.AddProcessor(LogExporter);
    end;
    
    FInitialized := True;
  end;
end;

class procedure TOpenTelemetry.Shutdown;
begin
  if Assigned(FInstance) then
  begin
    if FInstance.FInitialized then
    begin
      FInstance.FTracerProvider.Shutdown;
      FInstance.FMeterProvider.Shutdown;
      FInstance.FLoggerProvider.Shutdown;
    end;
    FreeAndNil(FInstance);
  end;
  FreeAndNil(FLock);
end;

function TOpenTelemetry.GetTracer(const AName: string): TTracer;
begin
  if FInitialized then
    Result := FTracerProvider.GetTracer(AName)
  else
    Result := nil;
end;

function TOpenTelemetry.GetMeter(const AName: string): TMeter;
begin
  if FInitialized then
    Result := FMeterProvider.GetMeter(AName)
  else
    Result := nil;
end;

function TOpenTelemetry.GetLogger(const AName: string): TLogger;
begin
  if FInitialized then
    Result := FLoggerProvider.GetLogger(AName)
  else
    Result := nil;
end;

{$ENDREGION}

initialization

finalization
  TOpenTelemetry.Shutdown;

end.
