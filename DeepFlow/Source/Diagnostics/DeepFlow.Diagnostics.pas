unit UniFlow.Diagnostics;
(*
  UniFlow Diagnostics
  ===================
  诊断与日志模块，提供统一的日志门面和执行追踪功能�?
*)

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, System.SyncObjs, 
  System.Generics.Collections, System.JSON;

type
  TStringArray = TArray<string>;

type
  // ============================================================================
  // 日志级别
  // ============================================================================
  
  TLogLevel = (
    llTrace,    // 最详细，仅开�?
    llDebug,    // 调试信息
    llInfo,     // 一般信�?
    llWarning,  // 警告
    llError,    // 错误
    llFatal     // 致命错误
  );
  
  // ============================================================================
  // 追踪级别
  // ============================================================================
  
  TTraceLevel = (
    tlOff,      // 关闭追踪
    tlMinimal,  // 仅关键节�?
    tlNormal,   // 步骤级别
    tlVerbose   // 包含变量�?
  );

  // ============================================================================
  // 日志条目
  // ============================================================================
  
  TLogEntry = record
    Timestamp: TDateTime;
    Level: TLogLevel;
    Category: string;
    Message: string;
    CorrelationId: string;
    WorkflowId: string;
    StepId: string;
    Data: TJSONObject;
    
    function ToJSON: TJSONObject;
    function ToString: string;
  end;

  // ============================================================================
  // 日志接口 - 宿主程序实现此接口注入自己的日志系统
  // ============================================================================
  
  ILogger = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    procedure Log(const Entry: TLogEntry);
    function GetMinLevel: TLogLevel;
    procedure SetMinLevel(ALevel: TLogLevel);
    property MinLevel: TLogLevel read GetMinLevel write SetMinLevel;
  end;
  
  ILoggerFactory = interface
    ['{B2C3D4E5-F678-9012-BCDE-F12345678901}']
    function CreateLogger(const Category: string): ILogger;
  end;

  // ============================================================================
  // 默认控制台日志实�?
  // ============================================================================
  
  TConsoleLogger = class(TInterfacedObject, ILogger)
  private
    FCategory: string;
    FMinLevel: TLogLevel;
    FLock: TCriticalSection;
  public
    constructor Create(const ACategory: string);
    destructor Destroy; override;
    
    procedure Log(const Entry: TLogEntry);
    function GetMinLevel: TLogLevel;
    procedure SetMinLevel(ALevel: TLogLevel);
    property MinLevel: TLogLevel read GetMinLevel write SetMinLevel;
  end;
  
  TConsoleLoggerFactory = class(TInterfacedObject, ILoggerFactory)
  private
    FDefaultLevel: TLogLevel;
  public
    constructor Create(ADefaultLevel: TLogLevel = llInfo);
    function CreateLogger(const Category: string): ILogger;
  end;

  // ============================================================================
  // 执行追踪条目
  // ============================================================================
  
  TTraceEntry = record
    Timestamp: TDateTime;
    CorrelationId: string;
    WorkflowId: string;
    StepId: string;
    StepType: string;
    Action: string;       // 'enter', 'exit', 'error'
    Duration: Int64;      // 毫秒
    InputData: string;    // JSON
    OutputData: string;   // JSON
    ErrorMessage: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TTraceEntryArray = array of TTraceEntry;

  // ============================================================================
  // 错误上下�?- 异常时自动收�?
  // ============================================================================
  
  TErrorContext = record
    Timestamp: TDateTime;
    CorrelationId: string;
    WorkflowId: string;
    WorkflowName: string;
    StepId: string;
    StepType: string;
    ErrorMessage: string;
    ErrorClass: string;
    StackTrace: string;
    Variables: TJSONObject;
    InputData: TJSONObject;
    PreviousSteps: TStringArray;
    
    function ToJSON: TJSONObject;
    function ToString: string;
  end;

  // ============================================================================
  // 诊断事件
  // ============================================================================
  
  TStepEventArgs = record
    CorrelationId: string;
    WorkflowId: string;
    StepId: string;
    StepType: string;
    Variables: TJSONObject;
    InputData: TJSONObject;
  end;
  
  TErrorEventArgs = record
    CorrelationId: string;
    WorkflowId: string;
    StepId: string;
    ErrorMessage: string;
    ErrorClass: string;
    Context: TErrorContext;
  end;
  
  TStepEvent = procedure(Sender: TObject; const Args: TStepEventArgs) of object;
  TErrorEvent = procedure(Sender: TObject; const Args: TErrorEventArgs) of object;

  // ============================================================================
  // 诊断配置
  // ============================================================================
  
  TDiagnosticsConfig = record
    TraceLevel: TTraceLevel;
    LogLevel: TLogLevel;
    MaxTraceEntries: Integer;
    CaptureVariablesOnError: Boolean;
    CaptureStackTrace: Boolean;
    EnablePerformanceCounters: Boolean;
    
    class function Default: TDiagnosticsConfig; static;
  end;

  // ============================================================================
  // 核心诊断�?
  // ============================================================================
  
  TUniFlowDiagnostics = class
  private
    FConfig: TDiagnosticsConfig;
    FLoggerFactory: ILoggerFactory;
    FDefaultLogger: ILogger;
    FLoggers: TDictionary<string, ILogger>;
    FTraceEntries: TTraceEntryArray;
    FTraceIndex: Integer;
    FLock: TCriticalSection;
    
    // 当前上下�?
    FCurrentCorrelationId: string;
    FCurrentWorkflowId: string;
    FExecutedSteps: TStringList;
    FStepStartTimes: TDictionary<string, TDateTime>;
    
    // 事件
    FOnBeforeStep: TStepEvent;
    FOnAfterStep: TStepEvent;
    FOnError: TErrorEvent;
    
    function GetLogger(const Category: string): ILogger;
    procedure AddTraceEntry(const Entry: TTraceEntry);
    function GetTraceEntries: TTraceEntryArray;
  public
    constructor Create(const AConfig: TDiagnosticsConfig);
    destructor Destroy; override;
    
    // 日志工厂注入
    procedure SetLoggerFactory(AFactory: ILoggerFactory);
    
    // 上下文管�?
    procedure BeginCorrelation(const ACorrelationId: string = '');
    procedure EndCorrelation;
    procedure SetWorkflowContext(const AWorkflowId: string);
    function GetCorrelationId: string;
    
    // 日志方法
    procedure Trace(const Category, Msg: string); overload;
    procedure Trace(const Category, Msg: string; const Args: array of const); overload;
    procedure Debug(const Category, Msg: string); overload;
    procedure Debug(const Category, Msg: string; const Args: array of const); overload;
    procedure Info(const Category, Msg: string); overload;
    procedure Info(const Category, Msg: string; const Args: array of const); overload;
    procedure Warning(const Category, Msg: string); overload;
    procedure Warning(const Category, Msg: string; const Args: array of const); overload;
    procedure Error(const Category, Msg: string); overload;
    procedure Error(const Category, Msg: string; const Args: array of const); overload;
    procedure Fatal(const Category, Msg: string); overload;
    procedure Fatal(const Category, Msg: string; const Args: array of const); overload;
    
    // 步骤追踪
    procedure TraceStepEnter(const StepId, StepType: string; Input: TJSONObject = nil);
    procedure TraceStepExit(const StepId: string; Output: TJSONObject = nil);
    procedure TraceStepError(const StepId, ErrorMsg: string);
    
    // 错误上下�?
    function CaptureErrorContext(const StepId, ErrorMsg, ErrorClass: string;
      Variables, InputData: TJSONObject): TErrorContext;
    
    // 状态导�?
    function DumpState: string;
    function ExportTrace(Format: string = 'json'): string;
    function GetRecentTrace(Count: Integer = 100): TTraceEntryArray;
    procedure ClearTrace;
    
    // 性能计数
    function GetStepDuration(const StepId: string): Int64;
    
    // 属�?
    property Config: TDiagnosticsConfig read FConfig write FConfig;
    property TraceLevel: TTraceLevel read FConfig.TraceLevel write FConfig.TraceLevel;
    property LogLevel: TLogLevel read FConfig.LogLevel write FConfig.LogLevel;
    property CorrelationId: string read GetCorrelationId;
    property TraceEntries: TTraceEntryArray read GetTraceEntries;
    
    // 事件
    property OnBeforeStep: TStepEvent read FOnBeforeStep write FOnBeforeStep;
    property OnAfterStep: TStepEvent read FOnAfterStep write FOnAfterStep;
    property OnError: TErrorEvent read FOnError write FOnError;
  end;

// ============================================================================
// 全局实例
// ============================================================================

function Diagnostics: TUniFlowDiagnostics;
procedure InitializeDiagnostics(const AConfig: TDiagnosticsConfig);
procedure FinalizeDiagnostics;

// 便捷函数
function GenerateCorrelationId: string;
function LogLevelToString(Level: TLogLevel): string;
function TraceLevelToString(Level: TTraceLevel): string;

implementation

var
  GDiagnostics: TUniFlowDiagnostics = nil;
  GDiagnosticsLock: TCriticalSection = nil;

// ============================================================================
// 辅助函数
// ============================================================================

function GenerateCorrelationId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := Copy(GUIDToString(G), 2, 8); // 短格�? 8字符
end;

function LogLevelToString(Level: TLogLevel): string;
begin
  case Level of
    llTrace:   Result := 'TRACE';
    llDebug:   Result := 'DEBUG';
    llInfo:    Result := 'INFO';
    llWarning: Result := 'WARN';
    llError:   Result := 'ERROR';
    llFatal:   Result := 'FATAL';
  else
    Result := 'UNKNOWN';
  end;
end;

function TraceLevelToString(Level: TTraceLevel): string;
begin
  case Level of
    tlOff:     Result := 'OFF';
    tlMinimal: Result := 'MINIMAL';
    tlNormal:  Result := 'NORMAL';
    tlVerbose: Result := 'VERBOSE';
  else
    Result := 'UNKNOWN';
  end;
end;

function NowUTC: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

// ============================================================================
// TLogEntry
// ============================================================================

function TLogEntry.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Timestamp));
  Result.AddPair('level', LogLevelToString(Level));
  Result.AddPair('category', Category);
  Result.AddPair('message', Message);
  
  if CorrelationId <> '' then
    Result.AddPair('correlationId', CorrelationId);
  if WorkflowId <> '' then
    Result.AddPair('workflowId', WorkflowId);
  if StepId <> '' then
    Result.AddPair('stepId', StepId);
  if Assigned(Data) then
    Result.AddPair('data', Data.Clone as TJSONObject);
end;

function TLogEntry.ToString: string;
var
  CID, WF, Step: string;
begin
  CID := '';
  WF := '';
  Step := '';
  
  if CorrelationId <> '' then
    CID := Format('[CID:%s] ', [CorrelationId]);
  if WorkflowId <> '' then
    WF := Format('[WF:%s] ', [WorkflowId]);
  if StepId <> '' then
    Step := Format('[STEP:%s] ', [StepId]);
  
  Result := Format('[%s] [%-5s] [%s] %s%s%s%s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Timestamp),
     LogLevelToString(Level),
     Category,
     CID, WF, Step,
     Message]);
end;

// ============================================================================
// TTraceEntry
// ============================================================================

function TTraceEntry.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Timestamp));
  Result.AddPair('correlationId', CorrelationId);
  Result.AddPair('workflowId', WorkflowId);
  Result.AddPair('stepId', StepId);
  Result.AddPair('stepType', StepType);
  Result.AddPair('action', Action);
  
  if Duration > 0 then
    Result.AddPair('durationMs', TJSONNumber.Create(Duration));
  if InputData <> '' then
    Result.AddPair('input', InputData);
  if OutputData <> '' then
    Result.AddPair('output', OutputData);
  if ErrorMessage <> '' then
    Result.AddPair('error', ErrorMessage);
end;

// ============================================================================
// TErrorContext
// ============================================================================

function TErrorContext.ToJSON: TJSONObject;
var
  StepsArr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Timestamp));
  Result.AddPair('correlationId', CorrelationId);
  Result.AddPair('workflowId', WorkflowId);
  Result.AddPair('workflowName', WorkflowName);
  Result.AddPair('stepId', StepId);
  Result.AddPair('stepType', StepType);
  Result.AddPair('errorMessage', ErrorMessage);
  Result.AddPair('errorClass', ErrorClass);
  
  if StackTrace <> '' then
    Result.AddPair('stackTrace', StackTrace);
  
  if Assigned(Variables) then
    Result.AddPair('variables', Variables.Clone as TJSONObject);
  
  if Assigned(InputData) then
    Result.AddPair('inputData', InputData.Clone as TJSONObject);
  
  if Length(PreviousSteps) > 0 then
  begin
    StepsArr := TJSONArray.Create;
    for I := 0 to High(PreviousSteps) do
      StepsArr.Add(PreviousSteps[I]);
    Result.AddPair('previousSteps', StepsArr);
  end;
end;

function TErrorContext.ToString: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('══════════════════════════════════════════════════════�?);
    SB.AppendLine('                    ERROR CONTEXT                       ');
    SB.AppendLine('══════════════════════════════════════════════════════�?);
    SB.AppendFormat('Timestamp:      %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Timestamp)]).AppendLine;
    SB.AppendFormat('CorrelationId:  %s', [CorrelationId]).AppendLine;
    SB.AppendFormat('Workflow:       %s (%s)', [WorkflowName, WorkflowId]).AppendLine;
    SB.AppendFormat('Step:           %s (%s)', [StepId, StepType]).AppendLine;
    SB.AppendLine('───────────────────────────────────────────────────────');
    SB.AppendFormat('Error:          %s', [ErrorMessage]).AppendLine;
    SB.AppendFormat('Exception:      %s', [ErrorClass]).AppendLine;
    
    if Length(PreviousSteps) > 0 then
    begin
      SB.AppendLine('───────────────────────────────────────────────────────');
      SB.AppendLine('Execution Path:');
      for I := 0 to High(PreviousSteps) do
        SB.AppendFormat('  %d. %s', [I + 1, PreviousSteps[I]]).AppendLine;
    end;
    
    if StackTrace <> '' then
    begin
      SB.AppendLine('───────────────────────────────────────────────────────');
      SB.AppendLine('Stack Trace:');
      SB.AppendLine(StackTrace);
    end;
    
    SB.AppendLine('══════════════════════════════════════════════════════�?);
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ============================================================================
// TDiagnosticsConfig
// ============================================================================

class function TDiagnosticsConfig.Default: TDiagnosticsConfig;
begin
  Result.TraceLevel := tlNormal;
  Result.LogLevel := llInfo;
  Result.MaxTraceEntries := 1000;
  Result.CaptureVariablesOnError := True;
  Result.CaptureStackTrace := True;
  Result.EnablePerformanceCounters := True;
end;

// ============================================================================
// TConsoleLogger
// ============================================================================

constructor TConsoleLogger.Create(const ACategory: string);
begin
  inherited Create;
  FCategory := ACategory;
  FMinLevel := llInfo;
  FLock := TCriticalSection.Create;
end;

destructor TConsoleLogger.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TConsoleLogger.Log(const Entry: TLogEntry);
var
  Color: Integer;
begin
  if Entry.Level < FMinLevel then
    Exit;
  
  FLock.Enter;
  try
    // ANSI color codes for different levels
    case Entry.Level of
      llTrace:   Color := 90;  // Gray
      llDebug:   Color := 36;  // Cyan
      llInfo:    Color := 32;  // Green
      llWarning: Color := 33;  // Yellow
      llError:   Color := 31;  // Red
      llFatal:   Color := 35;  // Magenta
    else
      Color := 0;
    end;
    
    WriteLn(Format(#27'[%dm%s'#27'[0m', [Color, Entry.ToString]));
  finally
    FLock.Leave;
  end;
end;

function TConsoleLogger.GetMinLevel: TLogLevel;
begin
  Result := FMinLevel;
end;

procedure TConsoleLogger.SetMinLevel(ALevel: TLogLevel);
begin
  FMinLevel := ALevel;
end;

// ============================================================================
// TConsoleLoggerFactory
// ============================================================================

constructor TConsoleLoggerFactory.Create(ADefaultLevel: TLogLevel);
begin
  inherited Create;
  FDefaultLevel := ADefaultLevel;
end;

function TConsoleLoggerFactory.CreateLogger(const Category: string): ILogger;
var
  Logger: TConsoleLogger;
begin
  Logger := TConsoleLogger.Create(Category);
  Logger.MinLevel := FDefaultLevel;
  Result := Logger;
end;

// ============================================================================
// TUniFlowDiagnostics
// ============================================================================

constructor TUniFlowDiagnostics.Create(const AConfig: TDiagnosticsConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FLock := TCriticalSection.Create;
  FLoggers := TDictionary<string, ILogger>.Create;
  FExecutedSteps := TStringList.Create;
  FStepStartTimes := TDictionary<string, TDateTime>.Create;
  
  SetLength(FTraceEntries, FConfig.MaxTraceEntries);
  FTraceIndex := 0;
  
  // 默认使用控制台日�?
  FLoggerFactory := TConsoleLoggerFactory.Create(FConfig.LogLevel);
  FDefaultLogger := FLoggerFactory.CreateLogger('UniFlow');
end;

destructor TUniFlowDiagnostics.Destroy;
begin
  FStepStartTimes.Free;
  FExecutedSteps.Free;
  FLoggers.Free;
  FLock.Free;
  inherited;
end;

procedure TUniFlowDiagnostics.SetLoggerFactory(AFactory: ILoggerFactory);
begin
  FLock.Enter;
  try
    FLoggerFactory := AFactory;
    FLoggers.Clear;
    FDefaultLogger := FLoggerFactory.CreateLogger('UniFlow');
  finally
    FLock.Leave;
  end;
end;

function TUniFlowDiagnostics.GetLogger(const Category: string): ILogger;
begin
  FLock.Enter;
  try
    if not FLoggers.TryGetValue(Category, Result) then
    begin
      Result := FLoggerFactory.CreateLogger(Category);
      FLoggers.Add(Category, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TUniFlowDiagnostics.BeginCorrelation(const ACorrelationId: string);
begin
  FLock.Enter;
  try
    if ACorrelationId = '' then
      FCurrentCorrelationId := GenerateCorrelationId
    else
      FCurrentCorrelationId := ACorrelationId;
    
    FExecutedSteps.Clear;
    FStepStartTimes.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TUniFlowDiagnostics.EndCorrelation;
begin
  FLock.Enter;
  try
    FCurrentCorrelationId := '';
    FCurrentWorkflowId := '';
    FExecutedSteps.Clear;
    FStepStartTimes.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TUniFlowDiagnostics.SetWorkflowContext(const AWorkflowId: string);
begin
  FLock.Enter;
  try
    FCurrentWorkflowId := AWorkflowId;
  finally
    FLock.Leave;
  end;
end;

function TUniFlowDiagnostics.GetCorrelationId: string;
begin
  FLock.Enter;
  try
    Result := FCurrentCorrelationId;
  finally
    FLock.Leave;
  end;
end;

procedure TUniFlowDiagnostics.AddTraceEntry(const Entry: TTraceEntry);
begin
  FLock.Enter;
  try
    FTraceEntries[FTraceIndex mod FConfig.MaxTraceEntries] := Entry;
    Inc(FTraceIndex);
  finally
    FLock.Leave;
  end;
end;

function TUniFlowDiagnostics.GetTraceEntries: TTraceEntryArray;
var
  Count, I, Idx: Integer;
begin
  FLock.Enter;
  try
    if FTraceIndex < FConfig.MaxTraceEntries then
      Count := FTraceIndex
    else
      Count := FConfig.MaxTraceEntries;
    
    SetLength(Result, Count);
    for I := 0 to Count - 1 do
    begin
      if FTraceIndex < FConfig.MaxTraceEntries then
        Idx := I
      else
        Idx := (FTraceIndex + I) mod FConfig.MaxTraceEntries;
      Result[I] := FTraceEntries[Idx];
    end;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// 日志方法
// ============================================================================

procedure TUniFlowDiagnostics.Trace(const Category, Msg: string);
var
  Entry: TLogEntry;
begin
  if FConfig.LogLevel > llTrace then Exit;
  
  Entry.Timestamp := NowUTC;
  Entry.Level := llTrace;
  Entry.Category := Category;
  Entry.Message := Msg;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := '';
  Entry.Data := nil;
  
  GetLogger(Category).Log(Entry);
end;

procedure TUniFlowDiagnostics.Trace(const Category, Msg: string; const Args: array of const);
begin
  Trace(Category, Format(Msg, Args));
end;

procedure TUniFlowDiagnostics.Debug(const Category, Msg: string);
var
  Entry: TLogEntry;
begin
  if FConfig.LogLevel > llDebug then Exit;
  
  Entry.Timestamp := NowUTC;
  Entry.Level := llDebug;
  Entry.Category := Category;
  Entry.Message := Msg;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := '';
  Entry.Data := nil;
  
  GetLogger(Category).Log(Entry);
end;

procedure TUniFlowDiagnostics.Debug(const Category, Msg: string; const Args: array of const);
begin
  Debug(Category, Format(Msg, Args));
end;

procedure TUniFlowDiagnostics.Info(const Category, Msg: string);
var
  Entry: TLogEntry;
begin
  if FConfig.LogLevel > llInfo then Exit;
  
  Entry.Timestamp := NowUTC;
  Entry.Level := llInfo;
  Entry.Category := Category;
  Entry.Message := Msg;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := '';
  Entry.Data := nil;
  
  GetLogger(Category).Log(Entry);
end;

procedure TUniFlowDiagnostics.Info(const Category, Msg: string; const Args: array of const);
begin
  Info(Category, Format(Msg, Args));
end;

procedure TUniFlowDiagnostics.Warning(const Category, Msg: string);
var
  Entry: TLogEntry;
begin
  if FConfig.LogLevel > llWarning then Exit;
  
  Entry.Timestamp := NowUTC;
  Entry.Level := llWarning;
  Entry.Category := Category;
  Entry.Message := Msg;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := '';
  Entry.Data := nil;
  
  GetLogger(Category).Log(Entry);
end;

procedure TUniFlowDiagnostics.Warning(const Category, Msg: string; const Args: array of const);
begin
  Warning(Category, Format(Msg, Args));
end;

procedure TUniFlowDiagnostics.Error(const Category, Msg: string);
var
  Entry: TLogEntry;
begin
  Entry.Timestamp := NowUTC;
  Entry.Level := llError;
  Entry.Category := Category;
  Entry.Message := Msg;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := '';
  Entry.Data := nil;
  
  GetLogger(Category).Log(Entry);
end;

procedure TUniFlowDiagnostics.Error(const Category, Msg: string; const Args: array of const);
begin
  Error(Category, Format(Msg, Args));
end;

procedure TUniFlowDiagnostics.Fatal(const Category, Msg: string);
var
  Entry: TLogEntry;
begin
  Entry.Timestamp := NowUTC;
  Entry.Level := llFatal;
  Entry.Category := Category;
  Entry.Message := Msg;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := '';
  Entry.Data := nil;
  
  GetLogger(Category).Log(Entry);
end;

procedure TUniFlowDiagnostics.Fatal(const Category, Msg: string; const Args: array of const);
begin
  Fatal(Category, Format(Msg, Args));
end;

// ============================================================================
// 步骤追踪
// ============================================================================

procedure TUniFlowDiagnostics.TraceStepEnter(const StepId, StepType: string; Input: TJSONObject);
var
  Entry: TTraceEntry;
  Args: TStepEventArgs;
begin
  if FConfig.TraceLevel = tlOff then Exit;
  
  FLock.Enter;
  try
    FStepStartTimes.AddOrSetValue(StepId, Now);
    FExecutedSteps.Add(StepId);
  finally
    FLock.Leave;
  end;
  
  Entry.Timestamp := NowUTC;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := StepId;
  Entry.StepType := StepType;
  Entry.Action := 'enter';
  Entry.Duration := 0;
  Entry.ErrorMessage := '';
  
  if (FConfig.TraceLevel >= tlVerbose) and Assigned(Input) then
    Entry.InputData := Input.ToJSON
  else
    Entry.InputData := '';
  
  Entry.OutputData := '';
  
  AddTraceEntry(Entry);
  
  // 触发事件
  if Assigned(FOnBeforeStep) then
  begin
    Args.CorrelationId := FCurrentCorrelationId;
    Args.WorkflowId := FCurrentWorkflowId;
    Args.StepId := StepId;
    Args.StepType := StepType;
    Args.Variables := nil;
    Args.InputData := Input;
    FOnBeforeStep(Self, Args);
  end;
  
  if FConfig.TraceLevel >= tlNormal then
    Info('Workflow', 'Step [%s] (%s) started', [StepId, StepType]);
end;

procedure TUniFlowDiagnostics.TraceStepExit(const StepId: string; Output: TJSONObject);
var
  Entry: TTraceEntry;
  Args: TStepEventArgs;
  StartTime: TDateTime;
begin
  if FConfig.TraceLevel = tlOff then Exit;
  
  Entry.Timestamp := NowUTC;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := StepId;
  Entry.StepType := '';
  Entry.Action := 'exit';
  Entry.ErrorMessage := '';
  Entry.InputData := '';
  
  FLock.Enter;
  try
    if FStepStartTimes.TryGetValue(StepId, StartTime) then
      Entry.Duration := MilliSecondsBetween(Now, StartTime)
    else
      Entry.Duration := 0;
  finally
    FLock.Leave;
  end;
  
  if (FConfig.TraceLevel >= tlVerbose) and Assigned(Output) then
    Entry.OutputData := Output.ToJSON
  else
    Entry.OutputData := '';
  
  AddTraceEntry(Entry);
  
  // 触发事件
  if Assigned(FOnAfterStep) then
  begin
    Args.CorrelationId := FCurrentCorrelationId;
    Args.WorkflowId := FCurrentWorkflowId;
    Args.StepId := StepId;
    Args.StepType := '';
    Args.Variables := nil;
    Args.InputData := Output;
    FOnAfterStep(Self, Args);
  end;
  
  if FConfig.TraceLevel >= tlNormal then
    Info('Workflow', 'Step [%s] completed (duration: %dms)', [StepId, Entry.Duration]);
end;

procedure TUniFlowDiagnostics.TraceStepError(const StepId, ErrorMsg: string);
var
  Entry: TTraceEntry;
  StartTime: TDateTime;
begin
  Entry.Timestamp := NowUTC;
  Entry.CorrelationId := FCurrentCorrelationId;
  Entry.WorkflowId := FCurrentWorkflowId;
  Entry.StepId := StepId;
  Entry.StepType := '';
  Entry.Action := 'error';
  Entry.ErrorMessage := ErrorMsg;
  Entry.InputData := '';
  Entry.OutputData := '';
  
  FLock.Enter;
  try
    if FStepStartTimes.TryGetValue(StepId, StartTime) then
      Entry.Duration := MilliSecondsBetween(Now, StartTime)
    else
      Entry.Duration := 0;
  finally
    FLock.Leave;
  end;
  
  AddTraceEntry(Entry);
  
  Error('Workflow', 'Step [%s] failed: %s', [StepId, ErrorMsg]);
end;

// ============================================================================
// 错误上下�?
// ============================================================================

function TUniFlowDiagnostics.CaptureErrorContext(const StepId, ErrorMsg, ErrorClass: string;
  Variables, InputData: TJSONObject): TErrorContext;
var
  I: Integer;
  Args: TErrorEventArgs;
begin
  Result.Timestamp := NowUTC;
  Result.CorrelationId := FCurrentCorrelationId;
  Result.WorkflowId := FCurrentWorkflowId;
  Result.WorkflowName := '';
  Result.StepId := StepId;
  Result.StepType := '';
  Result.ErrorMessage := ErrorMsg;
  Result.ErrorClass := ErrorClass;
  
  if FConfig.CaptureStackTrace then
    Result.StackTrace := '' // Delphi: use madExcept or JclDebug for stack traces
  else
    Result.StackTrace := '';
  
  if FConfig.CaptureVariablesOnError and Assigned(Variables) then
    Result.Variables := Variables.Clone as TJSONObject
  else
    Result.Variables := nil;
  
  if FConfig.CaptureVariablesOnError and Assigned(InputData) then
    Result.InputData := InputData.Clone as TJSONObject
  else
    Result.InputData := nil;
  
  FLock.Enter;
  try
    SetLength(Result.PreviousSteps, FExecutedSteps.Count);
    for I := 0 to FExecutedSteps.Count - 1 do
      Result.PreviousSteps[I] := FExecutedSteps[I];
  finally
    FLock.Leave;
  end;
  
  // 触发错误事件
  if Assigned(FOnError) then
  begin
    Args.CorrelationId := FCurrentCorrelationId;
    Args.WorkflowId := FCurrentWorkflowId;
    Args.StepId := StepId;
    Args.ErrorMessage := ErrorMsg;
    Args.ErrorClass := ErrorClass;
    Args.Context := Result;
    FOnError(Self, Args);
  end;
end;

// ============================================================================
// 状态导�?
// ============================================================================

function TUniFlowDiagnostics.DumpState: string;
var
  JSON: TJSONObject;
  StepsArr: TJSONArray;
  I: Integer;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', NowUTC));
    JSON.AddPair('correlationId', FCurrentCorrelationId);
    JSON.AddPair('workflowId', FCurrentWorkflowId);
    JSON.AddPair('traceLevel', TraceLevelToString(FConfig.TraceLevel));
    JSON.AddPair('logLevel', LogLevelToString(FConfig.LogLevel));
    JSON.AddPair('traceEntryCount', TJSONNumber.Create(FTraceIndex));
    
    FLock.Enter;
    try
      StepsArr := TJSONArray.Create;
      for I := 0 to FExecutedSteps.Count - 1 do
        StepsArr.Add(FExecutedSteps[I]);
      JSON.AddPair('executedSteps', StepsArr as TJSONValue);
    finally
      FLock.Leave;
    end;
    
    Result := JSON.Format;
  finally
    JSON.Free;
  end;
end;

function TUniFlowDiagnostics.ExportTrace(Format: string): string;
var
  Entries: TTraceEntryArray;
  JSON: TJSONArray;
  SB: TStringBuilder;
  I: Integer;
begin
  Entries := GetTraceEntries;
  
  if Format = 'json' then
  begin
    JSON := TJSONArray.Create;
    try
      for I := 0 to High(Entries) do
        JSON.AddElement(Entries[I].ToJSON);
      Result := JSON.Format;
    finally
      JSON.Free;
    end;
  end
  else // text format
  begin
    SB := TStringBuilder.Create;
    try
      SB.AppendLine('=== UniFlow Execution Trace ===');
      SB.AppendLine;
      for I := 0 to High(Entries) do
      begin
        SB.AppendFormat('[%s] [%s] %s.%s (%s)',
          [FormatDateTime('hh:nn:ss.zzz', Entries[I].Timestamp),
           Entries[I].CorrelationId,
           Entries[I].WorkflowId,
           Entries[I].StepId,
           Entries[I].Action]);
        if Entries[I].Duration > 0 then
          SB.AppendFormat(' [%dms]', [Entries[I].Duration]);
        if Entries[I].ErrorMessage <> '' then
          SB.AppendFormat(' ERROR: %s', [Entries[I].ErrorMessage]);
        SB.AppendLine;
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  end;
end;

function TUniFlowDiagnostics.GetRecentTrace(Count: Integer): TTraceEntryArray;
var
  All: TTraceEntryArray;
  StartIdx: Integer;
begin
  All := GetTraceEntries;
  if Length(All) <= Count then
    Result := All
  else
  begin
    StartIdx := Length(All) - Count;
    SetLength(Result, Count);
    Move(All[StartIdx], Result[0], Count * SizeOf(TTraceEntry));
  end;
end;

procedure TUniFlowDiagnostics.ClearTrace;
begin
  FLock.Enter;
  try
    FTraceIndex := 0;
  finally
    FLock.Leave;
  end;
end;

function TUniFlowDiagnostics.GetStepDuration(const StepId: string): Int64;
var
  StartTime: TDateTime;
begin
  FLock.Enter;
  try
    if FStepStartTimes.TryGetValue(StepId, StartTime) then
      Result := MilliSecondsBetween(Now, StartTime)
    else
      Result := -1;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// 全局实例
// ============================================================================

function Diagnostics: TUniFlowDiagnostics;
begin
  if GDiagnostics = nil then
  begin
    GDiagnosticsLock.Enter;
    try
      if GDiagnostics = nil then
        GDiagnostics := TUniFlowDiagnostics.Create(TDiagnosticsConfig.Default);
    finally
      GDiagnosticsLock.Leave;
    end;
  end;
  Result := GDiagnostics;
end;

procedure InitializeDiagnostics(const AConfig: TDiagnosticsConfig);
begin
  GDiagnosticsLock.Enter;
  try
    if GDiagnostics <> nil then
      FreeAndNil(GDiagnostics);
    GDiagnostics := TUniFlowDiagnostics.Create(AConfig);
  finally
    GDiagnosticsLock.Leave;
  end;
end;

procedure FinalizeDiagnostics;
begin
  GDiagnosticsLock.Enter;
  try
    FreeAndNil(GDiagnostics);
  finally
    GDiagnosticsLock.Leave;
  end;
end;

initialization
  GDiagnosticsLock := TCriticalSection.Create;

finalization
  FreeAndNil(GDiagnostics);
  FreeAndNil(GDiagnosticsLock);

end.
