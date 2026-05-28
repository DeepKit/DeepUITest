unit UniFlow.Cloud.Telemetry.Types;

{*******************************************************************************
  UniFlow OpenTelemetry 类型定义
  
  功能:
  - Trace/Span 类型
  - Metrics 类型  
  - Logs 类型
  - 属性和上下�?
  - 导出器配�?
  
  作�? UniFlow Team
  日期: 2024-01
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.DateUtils, System.SyncObjs;

type
  // 前向声明
  TSpan = class;
  TTraceContext = class;
  TMetric = class;
  TLogRecord = class;

  {$REGION 'Trace 类型'}
  
  /// <summary>Span 状�?/summary>
  TSpanStatus = (
    ssUnset,
    ssOk,
    ssError
  );
  
  /// <summary>Span 类型</summary>
  TSpanKind = (
    skInternal,
    skServer,
    skClient,
    skProducer,
    skConsumer
  );
  
  /// <summary>属性值类�?/summary>
  TAttributeValue = record
  private
    FValueType: (avtString, avtInt, avtDouble, avtBool, avtStringArray);
    FStringValue: string;
    FIntValue: Int64;
    FDoubleValue: Double;
    FBoolValue: Boolean;
    FStringArrayValue: TArray<string>;
  public
    class function FromString(const AValue: string): TAttributeValue; static;
    class function FromInt(AValue: Int64): TAttributeValue; static;
    class function FromDouble(AValue: Double): TAttributeValue; static;
    class function FromBool(AValue: Boolean): TAttributeValue; static;
    class function FromStringArray(const AValue: TArray<string>): TAttributeValue; static;
    
    function AsString: string;
    function AsInt: Int64;
    function AsDouble: Double;
    function AsBool: Boolean;
    function AsStringArray: TArray<string>;
    function ToJSON: TJSONValue;
  end;
  
  /// <summary>属性集�?/summary>
  TAttributes = class
  private
    FItems: TDictionary<string, TAttributeValue>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure SetAttribute(const AKey: string; const AValue: TAttributeValue); overload;
    procedure SetAttribute(const AKey, AValue: string); overload;
    procedure SetAttribute(const AKey: string; AValue: Int64); overload;
    procedure SetAttribute(const AKey: string; AValue: Double); overload;
    procedure SetAttribute(const AKey: string; AValue: Boolean); overload;
    
    function GetAttribute(const AKey: string): TAttributeValue;
    function Contains(const AKey: string): Boolean;
    function GetKeys: TArray<string>;
    function ToJSON: TJSONObject;
    
    property Items: TDictionary<string, TAttributeValue> read FItems;
  end;
  
  /// <summary>Span 事件</summary>
  TSpanEvent = class
  private
    FName: string;
    FTimestamp: TDateTime;
    FAttributes: TAttributes;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    
    property Name: string read FName;
    property Timestamp: TDateTime read FTimestamp;
    property Attributes: TAttributes read FAttributes;
  end;
  
  /// <summary>Span 链接</summary>
  TSpanLink = class
  private
    FTraceId: string;
    FSpanId: string;
    FAttributes: TAttributes;
  public
    constructor Create(const ATraceId, ASpanId: string);
    destructor Destroy; override;
    
    property TraceId: string read FTraceId;
    property SpanId: string read FSpanId;
    property Attributes: TAttributes read FAttributes;
  end;
  
  /// <summary>Trace 上下�?/summary>
  TTraceContext = class
  private
    FTraceId: string;
    FSpanId: string;
    FParentSpanId: string;
    FTraceFlags: Byte;
    FTraceState: string;
    FBaggage: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    
    class function NewTraceId: string;
    class function NewSpanId: string;
    class function Extract(const ACarrier: TDictionary<string, string>): TTraceContext;
    
    procedure Inject(const ACarrier: TDictionary<string, string>);
    function CreateChildContext: TTraceContext;
    
    property TraceId: string read FTraceId write FTraceId;
    property SpanId: string read FSpanId write FSpanId;
    property ParentSpanId: string read FParentSpanId write FParentSpanId;
    property TraceFlags: Byte read FTraceFlags write FTraceFlags;
    property TraceState: string read FTraceState write FTraceState;
    property Baggage: TDictionary<string, string> read FBaggage;
  end;
  
  /// <summary>Span</summary>
  TSpan = class
  private
    FContext: TTraceContext;
    FName: string;
    FKind: TSpanKind;
    FStartTime: TDateTime;
    FEndTime: TDateTime;
    FStatus: TSpanStatus;
    FStatusMessage: string;
    FAttributes: TAttributes;
    FEvents: TObjectList<TSpanEvent>;
    FLinks: TObjectList<TSpanLink>;
    FIsRecording: Boolean;
    FLock: TCriticalSection;
  public
    constructor Create(const AName: string; AKind: TSpanKind; AContext: TTraceContext);
    destructor Destroy; override;
    
    procedure SetAttribute(const AKey, AValue: string); overload;
    procedure SetAttribute(const AKey: string; AValue: Int64); overload;
    procedure SetAttribute(const AKey: string; AValue: Double); overload;
    procedure SetAttribute(const AKey: string; AValue: Boolean); overload;
    
    procedure AddEvent(const AName: string); overload;
    procedure AddEvent(const AName: string; AAttributes: TAttributes); overload;
    procedure AddLink(const ATraceId, ASpanId: string); overload;
    procedure AddLink(ALink: TSpanLink); overload;
    
    procedure SetStatus(AStatus: TSpanStatus; const AMessage: string = '');
    procedure RecordException(E: Exception);
    procedure Finish;
    
    function ToJSON: TJSONObject;
    
    property Context: TTraceContext read FContext;
    property Name: string read FName;
    property Kind: TSpanKind read FKind;
    property StartTime: TDateTime read FStartTime;
    property EndTime: TDateTime read FEndTime;
    property Status: TSpanStatus read FStatus;
    property StatusMessage: string read FStatusMessage;
    property Attributes: TAttributes read FAttributes;
    property Events: TObjectList<TSpanEvent> read FEvents;
    property Links: TObjectList<TSpanLink> read FLinks;
    property IsRecording: Boolean read FIsRecording;
  end;
  
  {$ENDREGION}
  
  {$REGION 'Metrics 类型'}
  
  /// <summary>指标类型</summary>
  TMetricKind = (
    mkCounter,
    mkUpDownCounter,
    mkGauge,
    mkHistogram,
    mkExponentialHistogram
  );
  
  /// <summary>指标数据�?/summary>
  TDataPoint = record
    Timestamp: TDateTime;
    Value: Double;
    Attributes: TAttributes;
  end;
  
  /// <summary>直方图边�?/summary>
  THistogramBuckets = record
    Boundaries: TArray<Double>;
    Counts: TArray<Int64>;
    Sum: Double;
    Count: Int64;
    Min: Double;
    Max: Double;
  end;
  
  /// <summary>指标</summary>
  TMetric = class
  private
    FName: string;
    FDescription: string;
    FUnit: string;
    FKind: TMetricKind;
    FDataPoints: TList<TDataPoint>;
    FHistogram: THistogramBuckets;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, ADescription, AUnit: string; AKind: TMetricKind);
    destructor Destroy; override;
    
    // Counter 操作
    procedure Add(AValue: Double; AAttributes: TAttributes = nil);
    
    // Gauge 操作
    procedure Record_(AValue: Double; AAttributes: TAttributes = nil);
    
    // Histogram 操作
    procedure RecordHistogram(AValue: Double; AAttributes: TAttributes = nil);
    
    function ToJSON: TJSONObject;
    
    property Name: string read FName;
    property Description: string read FDescription;
    property Unit_: string read FUnit;
    property Kind: TMetricKind read FKind;
    property DataPoints: TList<TDataPoint> read FDataPoints;
    property Histogram: THistogramBuckets read FHistogram;
  end;
  
  /// <summary>指标计数�?/summary>
  TCounter = class
  private
    FMetric: TMetric;
    FValue: Double;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, ADescription, AUnit: string);
    destructor Destroy; override;
    
    procedure Add(AValue: Double = 1; AAttributes: TAttributes = nil);
    function GetValue: Double;
    
    property Metric: TMetric read FMetric;
  end;
  
  /// <summary>指标仪表</summary>
  TGauge = class
  private
    FMetric: TMetric;
    FValue: Double;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, ADescription, AUnit: string);
    destructor Destroy; override;
    
    procedure Record_(AValue: Double; AAttributes: TAttributes = nil);
    function GetValue: Double;
    
    property Metric: TMetric read FMetric;
  end;
  
  /// <summary>直方图指�?/summary>
  THistogramMetric = class
  private
    FMetric: TMetric;
    FBoundaries: TArray<Double>;
    FBuckets: TArray<Int64>;
    FSum: Double;
    FCount: Int64;
    FMin: Double;
    FMax: Double;
    FLock: TCriticalSection;
  public
    constructor Create(const AName, ADescription, AUnit: string;
      const ABoundaries: TArray<Double>);
    destructor Destroy; override;
    
    procedure Record_(AValue: Double; AAttributes: TAttributes = nil);
    function GetHistogram: THistogramBuckets;
    
    property Metric: TMetric read FMetric;
  end;
  
  {$ENDREGION}
  
  {$REGION 'Logs 类型'}
  
  /// <summary>日志级别</summary>
  TLogSeverity = (
    lsTrace,
    lsDebug,
    lsInfo,
    lsWarn,
    lsError,
    lsFatal
  );
  
  /// <summary>日志记录</summary>
  TLogRecord = class
  private
    FTimestamp: TDateTime;
    FObservedTimestamp: TDateTime;
    FSeverity: TLogSeverity;
    FBody: string;
    FAttributes: TAttributes;
    FTraceId: string;
    FSpanId: string;
    FResource: TAttributes;
  public
    constructor Create(ASeverity: TLogSeverity; const ABody: string);
    destructor Destroy; override;
    
    procedure SetTraceContext(AContext: TTraceContext);
    function ToJSON: TJSONObject;
    
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property ObservedTimestamp: TDateTime read FObservedTimestamp;
    property Severity: TLogSeverity read FSeverity;
    property Body: string read FBody;
    property Attributes: TAttributes read FAttributes;
    property TraceId: string read FTraceId write FTraceId;
    property SpanId: string read FSpanId write FSpanId;
    property Resource: TAttributes read FResource;
  end;
  
  {$ENDREGION}
  
  {$REGION '资源和配�?}
  
  /// <summary>资源信息</summary>
  TResource = class
  private
    FAttributes: TAttributes;
    FSchemaUrl: string;
  public
    constructor Create;
    destructor Destroy; override;
    
    class function Default: TResource;
    class function FromEnvironment: TResource;
    
    procedure SetServiceInfo(const AName, AVersion, AInstanceId: string);
    procedure SetHostInfo(const AName, AArch: string);
    procedure Merge(AOther: TResource);
    
    function ToJSON: TJSONObject;
    
    property Attributes: TAttributes read FAttributes;
    property SchemaUrl: string read FSchemaUrl write FSchemaUrl;
  end;
  
  /// <summary>导出器类�?/summary>
  TExporterType = (
    etOTLP,
    etJaeger,
    etZipkin,
    etConsole,
    etPrometheus
  );
  
  /// <summary>OTLP 协议类型</summary>
  TOTLPProtocol = (
    opGrpc,
    opHttpProtobuf,
    opHttpJson
  );
  
  /// <summary>导出器配�?/summary>
  TExporterConfig = record
    ExporterType: TExporterType;
    Endpoint: string;
    Headers: TDictionary<string, string>;
    Protocol: TOTLPProtocol;
    Compression: Boolean;
    TimeoutMS: Integer;
    BatchSize: Integer;
    ExportIntervalMS: Integer;
    
    class function CreateOTLP(const AEndpoint: string;
      AProtocol: TOTLPProtocol = opGrpc): TExporterConfig; static;
    class function CreateJaeger(const AEndpoint: string): TExporterConfig; static;
    class function CreateZipkin(const AEndpoint: string): TExporterConfig; static;
    class function CreatePrometheus(APort: Integer): TExporterConfig; static;
    class function CreateConsole: TExporterConfig; static;
  end;
  
  /// <summary>采样策略</summary>
  TSamplerType = (
    stAlwaysOn,
    stAlwaysOff,
    stTraceIdRatio,
    stParentBased
  );
  
  /// <summary>采样器配�?/summary>
  TSamplerConfig = record
    SamplerType: TSamplerType;
    Ratio: Double;
    RootSampler: TSamplerType;
    
    class function AlwaysOn: TSamplerConfig; static;
    class function AlwaysOff: TSamplerConfig; static;
    class function TraceIdRatio(ARatio: Double): TSamplerConfig; static;
    class function ParentBased(ARootSampler: TSamplerType): TSamplerConfig; static;
  end;
  
  /// <summary>OpenTelemetry 配置</summary>
  TOTelConfig = record
    ServiceName: string;
    ServiceVersion: string;
    Environment: string;
    
    TracesExporter: TExporterConfig;
    MetricsExporter: TExporterConfig;
    LogsExporter: TExporterConfig;
    
    Sampler: TSamplerConfig;
    Resource: TResource;
    
    PropagatorFormat: string; // w3c, b3, jaeger
    
    class function Default(const AServiceName: string): TOTelConfig; static;
  end;
  
  {$ENDREGION}
  
  {$REGION '工作流特定类�?}
  
  /// <summary>工作流追踪属�?/summary>
  TWorkflowTraceAttributes = class
  public
    class procedure SetWorkflowAttributes(ASpan: TSpan;
      const AWorkflowId, AWorkflowName: string; AVersion: Integer);
    class procedure SetSkillAttributes(ASpan: TSpan;
      const ASkillId, ASkillType: string);
    class procedure SetSessionAttributes(ASpan: TSpan;
      const ASessionId, AUserId: string);
    class procedure SetLLMAttributes(ASpan: TSpan;
      const AProvider, AModel: string; ATokensIn, ATokensOut: Integer);
  end;
  
  /// <summary>工作流指标名�?/summary>
  TWorkflowMetrics = class
  public const
    // Workflow 指标
    WORKFLOW_EXECUTIONS_TOTAL = 'uniflow.workflow.executions.total';
    WORKFLOW_EXECUTION_DURATION = 'uniflow.workflow.execution.duration';
    WORKFLOW_ACTIVE = 'uniflow.workflow.active';
    WORKFLOW_ERRORS_TOTAL = 'uniflow.workflow.errors.total';
    
    // Skill 指标
    SKILL_EXECUTIONS_TOTAL = 'uniflow.skill.executions.total';
    SKILL_EXECUTION_DURATION = 'uniflow.skill.execution.duration';
    SKILL_ERRORS_TOTAL = 'uniflow.skill.errors.total';
    
    // LLM 指标
    LLM_REQUESTS_TOTAL = 'uniflow.llm.requests.total';
    LLM_REQUEST_DURATION = 'uniflow.llm.request.duration';
    LLM_TOKENS_TOTAL = 'uniflow.llm.tokens.total';
    LLM_ERRORS_TOTAL = 'uniflow.llm.errors.total';
    
    // Session 指标
    SESSION_ACTIVE = 'uniflow.session.active';
    SESSION_MESSAGES_TOTAL = 'uniflow.session.messages.total';
    
    // Queue 指标
    QUEUE_MESSAGES_TOTAL = 'uniflow.queue.messages.total';
    QUEUE_MESSAGE_DURATION = 'uniflow.queue.message.duration';
  end;
  
  {$ENDREGION}

implementation

uses
  System.Hash;

{$REGION 'TAttributeValue'}

class function TAttributeValue.FromString(const AValue: string): TAttributeValue;
begin
  Result.FValueType := avtString;
  Result.FStringValue := AValue;
end;

class function TAttributeValue.FromInt(AValue: Int64): TAttributeValue;
begin
  Result.FValueType := avtInt;
  Result.FIntValue := AValue;
end;

class function TAttributeValue.FromDouble(AValue: Double): TAttributeValue;
begin
  Result.FValueType := avtDouble;
  Result.FDoubleValue := AValue;
end;

class function TAttributeValue.FromBool(AValue: Boolean): TAttributeValue;
begin
  Result.FValueType := avtBool;
  Result.FBoolValue := AValue;
end;

class function TAttributeValue.FromStringArray(const AValue: TArray<string>): TAttributeValue;
begin
  Result.FValueType := avtStringArray;
  Result.FStringArrayValue := AValue;
end;

function TAttributeValue.AsString: string;
begin
  Result := FStringValue;
end;

function TAttributeValue.AsInt: Int64;
begin
  Result := FIntValue;
end;

function TAttributeValue.AsDouble: Double;
begin
  Result := FDoubleValue;
end;

function TAttributeValue.AsBool: Boolean;
begin
  Result := FBoolValue;
end;

function TAttributeValue.AsStringArray: TArray<string>;
begin
  Result := FStringArrayValue;
end;

function TAttributeValue.ToJSON: TJSONValue;
var
  Arr: TJSONArray;
  S: string;
begin
  case FValueType of
    avtString: Result := TJSONString.Create(FStringValue);
    avtInt: Result := TJSONNumber.Create(FIntValue);
    avtDouble: Result := TJSONNumber.Create(FDoubleValue);
    avtBool: Result := TJSONBool.Create(FBoolValue);
    avtStringArray:
      begin
        Arr := TJSONArray.Create;
        for S in FStringArrayValue do
          Arr.Add(S);
        Result := Arr;
      end;
  else
    Result := TJSONNull.Create;
  end;
end;

{$ENDREGION}

{$REGION 'TAttributes'}

constructor TAttributes.Create;
begin
  inherited Create;
  FItems := TDictionary<string, TAttributeValue>.Create;
end;

destructor TAttributes.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TAttributes.SetAttribute(const AKey: string; const AValue: TAttributeValue);
begin
  FItems.AddOrSetValue(AKey, AValue);
end;

procedure TAttributes.SetAttribute(const AKey, AValue: string);
begin
  SetAttribute(AKey, TAttributeValue.FromString(AValue));
end;

procedure TAttributes.SetAttribute(const AKey: string; AValue: Int64);
begin
  SetAttribute(AKey, TAttributeValue.FromInt(AValue));
end;

procedure TAttributes.SetAttribute(const AKey: string; AValue: Double);
begin
  SetAttribute(AKey, TAttributeValue.FromDouble(AValue));
end;

procedure TAttributes.SetAttribute(const AKey: string; AValue: Boolean);
begin
  SetAttribute(AKey, TAttributeValue.FromBool(AValue));
end;

function TAttributes.GetAttribute(const AKey: string): TAttributeValue;
begin
  if not FItems.TryGetValue(AKey, Result) then
    Result := TAttributeValue.FromString('');
end;

function TAttributes.Contains(const AKey: string): Boolean;
begin
  Result := FItems.ContainsKey(AKey);
end;

function TAttributes.GetKeys: TArray<string>;
begin
  Result := FItems.Keys.ToArray;
end;

function TAttributes.ToJSON: TJSONObject;
var
  Key: string;
begin
  Result := TJSONObject.Create;
  for Key in FItems.Keys do
    Result.AddPair(Key, FItems[Key].ToJSON);
end;

{$ENDREGION}

{$REGION 'TSpanEvent'}

constructor TSpanEvent.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FTimestamp := Now;
  FAttributes := TAttributes.Create;
end;

destructor TSpanEvent.Destroy;
begin
  FAttributes.Free;
  inherited;
end;

{$ENDREGION}

{$REGION 'TSpanLink'}

constructor TSpanLink.Create(const ATraceId, ASpanId: string);
begin
  inherited Create;
  FTraceId := ATraceId;
  FSpanId := ASpanId;
  FAttributes := TAttributes.Create;
end;

destructor TSpanLink.Destroy;
begin
  FAttributes.Free;
  inherited;
end;

{$ENDREGION}

{$REGION 'TTraceContext'}

constructor TTraceContext.Create;
begin
  inherited Create;
  FBaggage := TDictionary<string, string>.Create;
  FTraceFlags := 1; // Sampled
end;

destructor TTraceContext.Destroy;
begin
  FBaggage.Free;
  inherited;
end;

class function TTraceContext.NewTraceId: string;
var
  Guid1, Guid2: TGUID;
begin
  CreateGUID(Guid1);
  CreateGUID(Guid2);
  Result := LowerCase(
    GUIDToString(Guid1).Replace('{', '').Replace('}', '').Replace('-', '') +
    GUIDToString(Guid2).Replace('{', '').Replace('}', '').Replace('-', '')
  ).Substring(0, 32);
end;

class function TTraceContext.NewSpanId: string;
var
  Guid: TGUID;
begin
  CreateGUID(Guid);
  Result := LowerCase(
    GUIDToString(Guid).Replace('{', '').Replace('}', '').Replace('-', '')
  ).Substring(0, 16);
end;

class function TTraceContext.Extract(const ACarrier: TDictionary<string, string>): TTraceContext;
var
  TraceParent: string;
  Parts: TArray<string>;
begin
  Result := TTraceContext.Create;
  
  // W3C Trace Context
  if ACarrier.TryGetValue('traceparent', TraceParent) then
  begin
    Parts := TraceParent.Split(['-']);
    if Length(Parts) >= 4 then
    begin
      Result.FTraceId := Parts[1];
      Result.FSpanId := Parts[2];
      Result.FTraceFlags := StrToIntDef('$' + Parts[3], 1);
    end;
  end;
  
  // Trace State
  if ACarrier.ContainsKey('tracestate') then
    Result.FTraceState := ACarrier['tracestate'];
end;

procedure TTraceContext.Inject(const ACarrier: TDictionary<string, string>);
begin
  // W3C Trace Context
  ACarrier.AddOrSetValue('traceparent',
    Format('00-%s-%s-%s', [FTraceId, FSpanId, IntToHex(FTraceFlags, 2).ToLower]));
  
  if FTraceState <> '' then
    ACarrier.AddOrSetValue('tracestate', FTraceState);
end;

function TTraceContext.CreateChildContext: TTraceContext;
begin
  Result := TTraceContext.Create;
  Result.FTraceId := FTraceId;
  Result.FParentSpanId := FSpanId;
  Result.FSpanId := NewSpanId;
  Result.FTraceFlags := FTraceFlags;
  Result.FTraceState := FTraceState;
end;

{$ENDREGION}

{$REGION 'TSpan'}

constructor TSpan.Create(const AName: string; AKind: TSpanKind; AContext: TTraceContext);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FName := AName;
  FKind := AKind;
  FContext := AContext;
  FStartTime := Now;
  FStatus := ssUnset;
  FAttributes := TAttributes.Create;
  FEvents := TObjectList<TSpanEvent>.Create(True);
  FLinks := TObjectList<TSpanLink>.Create(True);
  FIsRecording := True;
end;

destructor TSpan.Destroy;
begin
  FLinks.Free;
  FEvents.Free;
  FAttributes.Free;
  FContext.Free;
  FLock.Free;
  inherited;
end;

procedure TSpan.SetAttribute(const AKey, AValue: string);
begin
  if FIsRecording then
  begin
    FLock.Enter;
    try
      FAttributes.SetAttribute(AKey, AValue);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSpan.SetAttribute(const AKey: string; AValue: Int64);
begin
  if FIsRecording then
  begin
    FLock.Enter;
    try
      FAttributes.SetAttribute(AKey, AValue);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSpan.SetAttribute(const AKey: string; AValue: Double);
begin
  if FIsRecording then
  begin
    FLock.Enter;
    try
      FAttributes.SetAttribute(AKey, AValue);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSpan.SetAttribute(const AKey: string; AValue: Boolean);
begin
  if FIsRecording then
  begin
    FLock.Enter;
    try
      FAttributes.SetAttribute(AKey, AValue);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSpan.AddEvent(const AName: string);
begin
  AddEvent(AName, nil);
end;

procedure TSpan.AddEvent(const AName: string; AAttributes: TAttributes);
var
  Event: TSpanEvent;
  Key: string;
begin
  if FIsRecording then
  begin
    FLock.Enter;
    try
      Event := TSpanEvent.Create(AName);
      if Assigned(AAttributes) then
      begin
        for Key in AAttributes.GetKeys do
          Event.Attributes.SetAttribute(Key, AAttributes.GetAttribute(Key));
      end;
      FEvents.Add(Event);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSpan.AddLink(const ATraceId, ASpanId: string);
begin
  AddLink(TSpanLink.Create(ATraceId, ASpanId));
end;

procedure TSpan.AddLink(ALink: TSpanLink);
begin
  if FIsRecording then
  begin
    FLock.Enter;
    try
      FLinks.Add(ALink);
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TSpan.SetStatus(AStatus: TSpanStatus; const AMessage: string);
begin
  FLock.Enter;
  try
    FStatus := AStatus;
    FStatusMessage := AMessage;
  finally
    FLock.Leave;
  end;
end;

procedure TSpan.RecordException(E: Exception);
var
  EventAttrs: TAttributes;
begin
  if FIsRecording then
  begin
    EventAttrs := TAttributes.Create;
    try
      EventAttrs.SetAttribute('exception.type', E.ClassName);
      EventAttrs.SetAttribute('exception.message', E.Message);
      AddEvent('exception', EventAttrs);
      SetStatus(ssError, E.Message);
    finally
      EventAttrs.Free;
    end;
  end;
end;

procedure TSpan.Finish;
begin
  FLock.Enter;
  try
    FEndTime := Now;
    FIsRecording := False;
  finally
    FLock.Leave;
  end;
end;

function TSpan.ToJSON: TJSONObject;
var
  EventsArr, LinksArr: TJSONArray;
  Event: TSpanEvent;
  Link: TSpanLink;
  EventObj, LinkObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('traceId', FContext.TraceId);
  Result.AddPair('spanId', FContext.SpanId);
  if FContext.ParentSpanId <> '' then
    Result.AddPair('parentSpanId', FContext.ParentSpanId);
  Result.AddPair('name', FName);
  Result.AddPair('kind', Integer(FKind));
  Result.AddPair('startTimeUnixNano', DateTimeToUnix(FStartTime, False) * 1000000000);
  if FEndTime > 0 then
    Result.AddPair('endTimeUnixNano', DateTimeToUnix(FEndTime, False) * 1000000000);
  Result.AddPair('status', TJSONObject.Create
    .AddPair('code', Integer(FStatus))
    .AddPair('message', FStatusMessage));
  Result.AddPair('attributes', FAttributes.ToJSON);
  
  EventsArr := TJSONArray.Create;
  for Event in FEvents do
  begin
    EventObj := TJSONObject.Create;
    EventObj.AddPair('name', Event.Name);
    EventObj.AddPair('timeUnixNano', DateTimeToUnix(Event.Timestamp, False) * 1000000000);
    EventObj.AddPair('attributes', Event.Attributes.ToJSON);
    EventsArr.Add(EventObj);
  end;
  Result.AddPair('events', EventsArr);
  
  LinksArr := TJSONArray.Create;
  for Link in FLinks do
  begin
    LinkObj := TJSONObject.Create;
    LinkObj.AddPair('traceId', Link.TraceId);
    LinkObj.AddPair('spanId', Link.SpanId);
    LinkObj.AddPair('attributes', Link.Attributes.ToJSON);
    LinksArr.Add(LinkObj);
  end;
  Result.AddPair('links', LinksArr);
end;

{$ENDREGION}

{$REGION 'TMetric'}

constructor TMetric.Create(const AName, ADescription, AUnit: string; AKind: TMetricKind);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FName := AName;
  FDescription := ADescription;
  FUnit := AUnit;
  FKind := AKind;
  FDataPoints := TList<TDataPoint>.Create;
  
  // 初始化直方图默认边界
  if AKind = mkHistogram then
  begin
    FHistogram.Boundaries := [0, 5, 10, 25, 50, 75, 100, 250, 500, 750, 1000, 2500, 5000, 7500, 10000];
    SetLength(FHistogram.Counts, Length(FHistogram.Boundaries) + 1);
  end;
end;

destructor TMetric.Destroy;
begin
  FDataPoints.Free;
  FLock.Free;
  inherited;
end;

procedure TMetric.Add(AValue: Double; AAttributes: TAttributes);
var
  Point: TDataPoint;
begin
  FLock.Enter;
  try
    Point.Timestamp := Now;
    Point.Value := AValue;
    Point.Attributes := AAttributes;
    FDataPoints.Add(Point);
  finally
    FLock.Leave;
  end;
end;

procedure TMetric.Record_(AValue: Double; AAttributes: TAttributes);
var
  Point: TDataPoint;
begin
  FLock.Enter;
  try
    Point.Timestamp := Now;
    Point.Value := AValue;
    Point.Attributes := AAttributes;
    FDataPoints.Add(Point);
  finally
    FLock.Leave;
  end;
end;

procedure TMetric.RecordHistogram(AValue: Double; AAttributes: TAttributes);
var
  I: Integer;
  BucketIdx: Integer;
begin
  FLock.Enter;
  try
    // 找到对应的桶
    BucketIdx := Length(FHistogram.Boundaries);
    for I := 0 to High(FHistogram.Boundaries) do
    begin
      if AValue <= FHistogram.Boundaries[I] then
      begin
        BucketIdx := I;
        Break;
      end;
    end;
    
    Inc(FHistogram.Counts[BucketIdx]);
    FHistogram.Sum := FHistogram.Sum + AValue;
    Inc(FHistogram.Count);
    
    if FHistogram.Count = 1 then
    begin
      FHistogram.Min := AValue;
      FHistogram.Max := AValue;
    end
    else
    begin
      if AValue < FHistogram.Min then FHistogram.Min := AValue;
      if AValue > FHistogram.Max then FHistogram.Max := AValue;
    end;
  finally
    FLock.Leave;
  end;
end;

function TMetric.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('description', FDescription);
  Result.AddPair('unit', FUnit);
  Result.AddPair('type', Integer(FKind));
  
  if FKind = mkHistogram then
  begin
    Result.AddPair('sum', FHistogram.Sum);
    Result.AddPair('count', FHistogram.Count);
    Result.AddPair('min', FHistogram.Min);
    Result.AddPair('max', FHistogram.Max);
  end;
end;

{$ENDREGION}

{$REGION 'TCounter'}

constructor TCounter.Create(const AName, ADescription, AUnit: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMetric := TMetric.Create(AName, ADescription, AUnit, mkCounter);
  FValue := 0;
end;

destructor TCounter.Destroy;
begin
  FMetric.Free;
  FLock.Free;
  inherited;
end;

procedure TCounter.Add(AValue: Double; AAttributes: TAttributes);
begin
  FLock.Enter;
  try
    FValue := FValue + AValue;
    FMetric.Add(AValue, AAttributes);
  finally
    FLock.Leave;
  end;
end;

function TCounter.GetValue: Double;
begin
  FLock.Enter;
  try
    Result := FValue;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TGauge'}

constructor TGauge.Create(const AName, ADescription, AUnit: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMetric := TMetric.Create(AName, ADescription, AUnit, mkGauge);
  FValue := 0;
end;

destructor TGauge.Destroy;
begin
  FMetric.Free;
  FLock.Free;
  inherited;
end;

procedure TGauge.Record_(AValue: Double; AAttributes: TAttributes);
begin
  FLock.Enter;
  try
    FValue := AValue;
    FMetric.Record_(AValue, AAttributes);
  finally
    FLock.Leave;
  end;
end;

function TGauge.GetValue: Double;
begin
  FLock.Enter;
  try
    Result := FValue;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'THistogramMetric'}

constructor THistogramMetric.Create(const AName, ADescription, AUnit: string;
  const ABoundaries: TArray<Double>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMetric := TMetric.Create(AName, ADescription, AUnit, mkHistogram);
  FBoundaries := ABoundaries;
  SetLength(FBuckets, Length(ABoundaries) + 1);
  FSum := 0;
  FCount := 0;
  FMin := MaxDouble;
  FMax := -MaxDouble;
end;

destructor THistogramMetric.Destroy;
begin
  FMetric.Free;
  FLock.Free;
  inherited;
end;

procedure THistogramMetric.Record_(AValue: Double; AAttributes: TAttributes);
var
  I: Integer;
  BucketIdx: Integer;
begin
  FLock.Enter;
  try
    BucketIdx := Length(FBoundaries);
    for I := 0 to High(FBoundaries) do
    begin
      if AValue <= FBoundaries[I] then
      begin
        BucketIdx := I;
        Break;
      end;
    end;
    
    Inc(FBuckets[BucketIdx]);
    FSum := FSum + AValue;
    Inc(FCount);
    
    if AValue < FMin then FMin := AValue;
    if AValue > FMax then FMax := AValue;
    
    FMetric.RecordHistogram(AValue, AAttributes);
  finally
    FLock.Leave;
  end;
end;

function THistogramMetric.GetHistogram: THistogramBuckets;
begin
  FLock.Enter;
  try
    Result.Boundaries := FBoundaries;
    Result.Counts := FBuckets;
    Result.Sum := FSum;
    Result.Count := FCount;
    Result.Min := FMin;
    Result.Max := FMax;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TLogRecord'}

constructor TLogRecord.Create(ASeverity: TLogSeverity; const ABody: string);
begin
  inherited Create;
  FTimestamp := Now;
  FObservedTimestamp := Now;
  FSeverity := ASeverity;
  FBody := ABody;
  FAttributes := TAttributes.Create;
  FResource := TAttributes.Create;
end;

destructor TLogRecord.Destroy;
begin
  FResource.Free;
  FAttributes.Free;
  inherited;
end;

procedure TLogRecord.SetTraceContext(AContext: TTraceContext);
begin
  if Assigned(AContext) then
  begin
    FTraceId := AContext.TraceId;
    FSpanId := AContext.SpanId;
  end;
end;

function TLogRecord.ToJSON: TJSONObject;
const
  SeverityNames: array[TLogSeverity] of string = (
    'TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'
  );
begin
  Result := TJSONObject.Create;
  Result.AddPair('timeUnixNano', DateTimeToUnix(FTimestamp, False) * 1000000000);
  Result.AddPair('observedTimeUnixNano', DateTimeToUnix(FObservedTimestamp, False) * 1000000000);
  Result.AddPair('severityNumber', Integer(FSeverity) + 1);
  Result.AddPair('severityText', SeverityNames[FSeverity]);
  Result.AddPair('body', TJSONObject.Create.AddPair('stringValue', FBody));
  Result.AddPair('attributes', FAttributes.ToJSON);
  if FTraceId <> '' then
    Result.AddPair('traceId', FTraceId);
  if FSpanId <> '' then
    Result.AddPair('spanId', FSpanId);
end;

{$ENDREGION}

{$REGION 'TResource'}

constructor TResource.Create;
begin
  inherited Create;
  FAttributes := TAttributes.Create;
end;

destructor TResource.Destroy;
begin
  FAttributes.Free;
  inherited;
end;

class function TResource.Default: TResource;
begin
  Result := TResource.Create;
  Result.FAttributes.SetAttribute('telemetry.sdk.name', 'uniflow-otel');
  Result.FAttributes.SetAttribute('telemetry.sdk.language', 'delphi');
  Result.FAttributes.SetAttribute('telemetry.sdk.version', '1.0.0');
end;

class function TResource.FromEnvironment: TResource;
var
  ServiceName, ServiceVersion: string;
begin
  Result := Default;
  
  ServiceName := GetEnvironmentVariable('OTEL_SERVICE_NAME');
  if ServiceName <> '' then
    Result.FAttributes.SetAttribute('service.name', ServiceName);
    
  ServiceVersion := GetEnvironmentVariable('OTEL_SERVICE_VERSION');
  if ServiceVersion <> '' then
    Result.FAttributes.SetAttribute('service.version', ServiceVersion);
end;

procedure TResource.SetServiceInfo(const AName, AVersion, AInstanceId: string);
begin
  FAttributes.SetAttribute('service.name', AName);
  FAttributes.SetAttribute('service.version', AVersion);
  if AInstanceId <> '' then
    FAttributes.SetAttribute('service.instance.id', AInstanceId);
end;

procedure TResource.SetHostInfo(const AName, AArch: string);
begin
  FAttributes.SetAttribute('host.name', AName);
  FAttributes.SetAttribute('host.arch', AArch);
end;

procedure TResource.Merge(AOther: TResource);
var
  Key: string;
begin
  if Assigned(AOther) then
  begin
    for Key in AOther.FAttributes.GetKeys do
      FAttributes.SetAttribute(Key, AOther.FAttributes.GetAttribute(Key));
  end;
end;

function TResource.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('attributes', FAttributes.ToJSON);
  if FSchemaUrl <> '' then
    Result.AddPair('schemaUrl', FSchemaUrl);
end;

{$ENDREGION}

{$REGION 'TExporterConfig'}

class function TExporterConfig.CreateOTLP(const AEndpoint: string;
  AProtocol: TOTLPProtocol): TExporterConfig;
begin
  Result.ExporterType := etOTLP;
  Result.Endpoint := AEndpoint;
  Result.Protocol := AProtocol;
  Result.Headers := TDictionary<string, string>.Create;
  Result.Compression := True;
  Result.TimeoutMS := 30000;
  Result.BatchSize := 512;
  Result.ExportIntervalMS := 5000;
end;

class function TExporterConfig.CreateJaeger(const AEndpoint: string): TExporterConfig;
begin
  Result.ExporterType := etJaeger;
  Result.Endpoint := AEndpoint;
  Result.Headers := TDictionary<string, string>.Create;
  Result.TimeoutMS := 30000;
  Result.BatchSize := 512;
  Result.ExportIntervalMS := 5000;
end;

class function TExporterConfig.CreateZipkin(const AEndpoint: string): TExporterConfig;
begin
  Result.ExporterType := etZipkin;
  Result.Endpoint := AEndpoint;
  Result.Headers := TDictionary<string, string>.Create;
  Result.TimeoutMS := 30000;
  Result.BatchSize := 512;
  Result.ExportIntervalMS := 5000;
end;

class function TExporterConfig.CreatePrometheus(APort: Integer): TExporterConfig;
begin
  Result.ExporterType := etPrometheus;
  Result.Endpoint := Format(':%d', [APort]);
  Result.Headers := TDictionary<string, string>.Create;
end;

class function TExporterConfig.CreateConsole: TExporterConfig;
begin
  Result.ExporterType := etConsole;
  Result.Headers := TDictionary<string, string>.Create;
end;

{$ENDREGION}

{$REGION 'TSamplerConfig'}

class function TSamplerConfig.AlwaysOn: TSamplerConfig;
begin
  Result.SamplerType := stAlwaysOn;
  Result.Ratio := 1.0;
end;

class function TSamplerConfig.AlwaysOff: TSamplerConfig;
begin
  Result.SamplerType := stAlwaysOff;
  Result.Ratio := 0.0;
end;

class function TSamplerConfig.TraceIdRatio(ARatio: Double): TSamplerConfig;
begin
  Result.SamplerType := stTraceIdRatio;
  Result.Ratio := ARatio;
end;

class function TSamplerConfig.ParentBased(ARootSampler: TSamplerType): TSamplerConfig;
begin
  Result.SamplerType := stParentBased;
  Result.RootSampler := ARootSampler;
end;

{$ENDREGION}

{$REGION 'TOTelConfig'}

class function TOTelConfig.Default(const AServiceName: string): TOTelConfig;
begin
  Result.ServiceName := AServiceName;
  Result.ServiceVersion := '1.0.0';
  Result.Environment := 'production';
  
  Result.TracesExporter := TExporterConfig.CreateOTLP('http://localhost:4317');
  Result.MetricsExporter := TExporterConfig.CreateOTLP('http://localhost:4317');
  Result.LogsExporter := TExporterConfig.CreateOTLP('http://localhost:4317');
  
  Result.Sampler := TSamplerConfig.TraceIdRatio(0.1);
  Result.Resource := TResource.Default;
  Result.Resource.SetServiceInfo(AServiceName, '1.0.0', '');
  
  Result.PropagatorFormat := 'w3c';
end;

{$ENDREGION}

{$REGION 'TWorkflowTraceAttributes'}

class procedure TWorkflowTraceAttributes.SetWorkflowAttributes(ASpan: TSpan;
  const AWorkflowId, AWorkflowName: string; AVersion: Integer);
begin
  ASpan.SetAttribute('uniflow.workflow.id', AWorkflowId);
  ASpan.SetAttribute('uniflow.workflow.name', AWorkflowName);
  ASpan.SetAttribute('uniflow.workflow.version', AVersion);
end;

class procedure TWorkflowTraceAttributes.SetSkillAttributes(ASpan: TSpan;
  const ASkillId, ASkillType: string);
begin
  ASpan.SetAttribute('uniflow.skill.id', ASkillId);
  ASpan.SetAttribute('uniflow.skill.type', ASkillType);
end;

class procedure TWorkflowTraceAttributes.SetSessionAttributes(ASpan: TSpan;
  const ASessionId, AUserId: string);
begin
  ASpan.SetAttribute('uniflow.session.id', ASessionId);
  ASpan.SetAttribute('uniflow.user.id', AUserId);
end;

class procedure TWorkflowTraceAttributes.SetLLMAttributes(ASpan: TSpan;
  const AProvider, AModel: string; ATokensIn, ATokensOut: Integer);
begin
  ASpan.SetAttribute('gen_ai.system', AProvider);
  ASpan.SetAttribute('gen_ai.request.model', AModel);
  ASpan.SetAttribute('gen_ai.usage.input_tokens', ATokensIn);
  ASpan.SetAttribute('gen_ai.usage.output_tokens', ATokensOut);
end;

{$ENDREGION}

end.
