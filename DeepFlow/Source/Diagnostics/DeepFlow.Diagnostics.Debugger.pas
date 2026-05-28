unit UniFlow.Diagnostics.Debugger;
(*
  UniFlow Diagnostics Debugger
  ============================
  工作流调试器，支持断点、单步执行、变量检查等调试功能�?
*)

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, 
  System.JSON,
  UniFlow.Diagnostics;

type
  // ============================================================================
  // 调试器状�?
  // ============================================================================
  
  TDebuggerState = (
    dsIdle,       // 空闲
    dsRunning,    // 运行�?
    dsPaused,     // 已暂�?
    dsStepping,   // 单步�?
    dsBreakpoint  // 断点暂停
  );

  // ============================================================================
  // 断点类型
  // ============================================================================
  
  TBreakpointType = (
    bpStep,       // 步骤断点
    bpConditional,// 条件断点
    bpError,      // 错误断点
    bpWatch       // 监视断点（变量变化时触发�?
  );

  // ============================================================================
  // 断点定义
  // ============================================================================
  
  TBreakpoint = record
    Id: Integer;
    BreakpointType: TBreakpointType;
    StepId: string;           // 步骤ID（bpStep�?
    Condition: string;        // 条件表达式（bpConditional�?
    WatchVariable: string;    // 监视变量名（bpWatch�?
    Enabled: Boolean;
    HitCount: Integer;
    IgnoreCount: Integer;     // 忽略前N次命�?
    
    function Matches(const AStepId: string): Boolean;
  end;
  
  TBreakpointArray = array of TBreakpoint;

  // ============================================================================
  // 调试�?- 调用栈中的一�?
  // ============================================================================
  
  TDebugFrame = record
    WorkflowId: string;
    WorkflowName: string;
    StepId: string;
    StepType: string;
    StepIndex: Integer;
    Variables: TJSONObject;
    EnteredAt: TDateTime;
  end;
  
  TDebugFrameArray = array of TDebugFrame;

  // ============================================================================
  // 调试事件参数
  // ============================================================================
  
  TDebugEventArgs = record
    State: TDebuggerState;
    CurrentFrame: TDebugFrame;
    Breakpoint: TBreakpoint;
    Message: string;
  end;
  
  TDebugEvent = procedure(Sender: TObject; const Args: TDebugEventArgs) of object;

  // ============================================================================
  // 调试器配�?
  // ============================================================================
  
  TDebuggerConfig = record
    Enabled: Boolean;
    BreakOnStart: Boolean;      // 启动时暂�?
    BreakOnError: Boolean;      // 错误时暂�?
    BreakOnEnd: Boolean;        // 结束时暂�?
    MaxCallStackDepth: Integer;
    
    class function Default: TDebuggerConfig; static;
  end;

  // ============================================================================
  // 工作流调试器
  // ============================================================================
  
  TWorkflowDebugger = class
  private
    FConfig: TDebuggerConfig;
    FState: TDebuggerState;
    FBreakpoints: TBreakpointArray;
    FNextBreakpointId: Integer;
    FCallStack: TDebugFrameArray;
    FLock: TCriticalSection;
    FPauseEvent: TEvent;
    FStepMode: (smNone, smInto, smOver, smOut);
    FStepOverDepth: Integer;
    
    // 事件
    FOnStateChanged: TDebugEvent;
    FOnBreakpointHit: TDebugEvent;
    FOnStepCompleted: TDebugEvent;
    
    function GetCurrentFrame: TDebugFrame;
    function CheckBreakpoint(const StepId: string): Integer;
    procedure SetState(AState: TDebuggerState);
    procedure WaitIfPaused;
    procedure NotifyStateChanged(const Msg: string);
  public
    constructor Create(const AConfig: TDebuggerConfig);
    destructor Destroy; override;
    
    // 启用/禁用
    procedure Enable;
    procedure Disable;
    function IsEnabled: Boolean;
    
    // 断点管理
    function AddBreakpoint(const StepId: string): Integer;
    function AddConditionalBreakpoint(const StepId, Condition: string): Integer;
    function AddWatchBreakpoint(const VariableName: string): Integer;
    procedure RemoveBreakpoint(BreakpointId: Integer);
    procedure EnableBreakpoint(BreakpointId: Integer);
    procedure DisableBreakpoint(BreakpointId: Integer);
    procedure ClearBreakpoints;
    function GetBreakpoints: TBreakpointArray;
    
    // 执行控制
    procedure Continue;          // 继续执行
    procedure Pause;             // 暂停执行
    procedure StepInto;          // 单步进入
    procedure StepOver;          // 单步跳过
    procedure StepOut;           // 跳出当前
    procedure Stop;              // 停止执行
    
    // 调用�?
    function GetCallStack: TDebugFrameArray;
    function GetCallStackDepth: Integer;
    
    // 变量检�?
    function GetVariables: TJSONObject;
    function GetVariable(const Name: string): TJSONValue;
    function EvaluateExpression(const Expr: string): string;
    
    // 步骤钩子 - 由执行器调用
    procedure OnEnterStep(const WorkflowId, WorkflowName, StepId, StepType: string;
      Variables: TJSONObject);
    procedure OnExitStep(const StepId: string);
    procedure OnError(const StepId, ErrorMsg: string);
    
    // 属�?
    property Config: TDebuggerConfig read FConfig write FConfig;
    property State: TDebuggerState read FState;
    property CurrentFrame: TDebugFrame read GetCurrentFrame;
    
    // 事件
    property OnStateChanged: TDebugEvent read FOnStateChanged write FOnStateChanged;
    property OnBreakpointHit: TDebugEvent read FOnBreakpointHit write FOnBreakpointHit;
    property OnStepCompleted: TDebugEvent read FOnStepCompleted write FOnStepCompleted;
  end;

  // ============================================================================
  // 调试控制�?- 交互式调�?
  // ============================================================================
  
  TDebugConsole = class
  private
    FDebugger: TWorkflowDebugger;
    FRunning: Boolean;
    procedure PrintHelp;
    procedure PrintState;
    procedure PrintCallStack;
    procedure PrintBreakpoints;
    procedure PrintVariables;
    procedure ProcessCommand(const Cmd: string);
  public
    constructor Create(ADebugger: TWorkflowDebugger);
    
    // 启动交互式控制台
    procedure Run;
    procedure Stop;
    
    // 单个命令处理
    function ExecuteCommand(const Cmd: string): string;
  end;

// ============================================================================
// 辅助函数
// ============================================================================

function DebuggerStateToString(State: TDebuggerState): string;
function BreakpointTypeToString(BpType: TBreakpointType): string;

// 全局调试�?
function Debugger: TWorkflowDebugger;
procedure InitializeDebugger(const AConfig: TDebuggerConfig);
procedure FinalizeDebugger;

implementation

var
  GDebugger: TWorkflowDebugger = nil;
  GDebuggerLock: TCriticalSection = nil;

// ============================================================================
// 辅助函数
// ============================================================================

function DebuggerStateToString(State: TDebuggerState): string;
begin
  case State of
    dsIdle:       Result := 'IDLE';
    dsRunning:    Result := 'RUNNING';
    dsPaused:     Result := 'PAUSED';
    dsStepping:   Result := 'STEPPING';
    dsBreakpoint: Result := 'BREAKPOINT';
  else
    Result := 'UNKNOWN';
  end;
end;

function BreakpointTypeToString(BpType: TBreakpointType): string;
begin
  case BpType of
    bpStep:        Result := 'Step';
    bpConditional: Result := 'Conditional';
    bpError:       Result := 'Error';
    bpWatch:       Result := 'Watch';
  else
    Result := 'Unknown';
  end;
end;

// ============================================================================
// TBreakpoint
// ============================================================================

function TBreakpoint.Matches(const AStepId: string): Boolean;
begin
  Result := False;
  if not Enabled then Exit;
  
  case BreakpointType of
    bpStep:
      Result := (StepId = '') or (StepId = AStepId);
    bpConditional:
      Result := (StepId = '') or (StepId = AStepId);
      // TODO: 评估条件表达�?
    bpError:
      Result := True; // 错误断点在OnError中处�?
    bpWatch:
      Result := False; // 监视断点在变量变化时处理
  end;
  
  if Result then
  begin
    // 检查忽略计�?
    if IgnoreCount > 0 then
      Result := False;
  end;
end;

// ============================================================================
// TDebuggerConfig
// ============================================================================

class function TDebuggerConfig.Default: TDebuggerConfig;
begin
  Result.Enabled := False;
  Result.BreakOnStart := False;
  Result.BreakOnError := True;
  Result.BreakOnEnd := False;
  Result.MaxCallStackDepth := 100;
end;

// ============================================================================
// TWorkflowDebugger
// ============================================================================

constructor TWorkflowDebugger.Create(const AConfig: TDebuggerConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FState := dsIdle;
  FLock := TCriticalSection.Create;
  FPauseEvent := TEvent.Create(nil, True, True, '');
  FNextBreakpointId := 1;
  FStepMode := smNone;
  SetLength(FBreakpoints, 0);
  SetLength(FCallStack, 0);
end;

destructor TWorkflowDebugger.Destroy;
begin
  FPauseEvent.Free;
  FLock.Free;
  inherited;
end;

procedure TWorkflowDebugger.Enable;
begin
  FConfig.Enabled := True;
  Diagnostics.Info('Debugger', 'Debugger enabled');
end;

procedure TWorkflowDebugger.Disable;
begin
  FConfig.Enabled := False;
  Continue; // 确保不会卡在暂停状�?
  Diagnostics.Info('Debugger', 'Debugger disabled');
end;

function TWorkflowDebugger.IsEnabled: Boolean;
begin
  Result := FConfig.Enabled;
end;

function TWorkflowDebugger.GetCurrentFrame: TDebugFrame;
begin
  FLock.Enter;
  try
    if Length(FCallStack) > 0 then
      Result := FCallStack[High(FCallStack)]
    else
    begin
      Result.WorkflowId := '';
      Result.StepId := '';
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDebugger.SetState(AState: TDebuggerState);
begin
  FLock.Enter;
  try
    if FState <> AState then
    begin
      FState := AState;
      
      case AState of
        dsRunning, dsIdle:
          FPauseEvent.SetEvent;
        dsPaused, dsBreakpoint, dsStepping:
          FPauseEvent.ResetEvent;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDebugger.WaitIfPaused;
begin
  if not FConfig.Enabled then Exit;
  
  while FState in [dsPaused, dsBreakpoint] do
  begin
    FPauseEvent.WaitFor(100);
    if FState in [dsIdle, dsRunning] then
      Break;
  end;
end;

procedure TWorkflowDebugger.NotifyStateChanged(const Msg: string);
var
  Args: TDebugEventArgs;
begin
  if Assigned(FOnStateChanged) then
  begin
    Args.State := FState;
    Args.CurrentFrame := GetCurrentFrame;
    Args.Message := Msg;
    FOnStateChanged(Self, Args);
  end;
end;

function TWorkflowDebugger.CheckBreakpoint(const StepId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  
  FLock.Enter;
  try
    for I := 0 to High(FBreakpoints) do
    begin
      if FBreakpoints[I].Matches(StepId) then
      begin
        Inc(FBreakpoints[I].HitCount);
        
        if FBreakpoints[I].IgnoreCount > 0 then
        begin
          Dec(FBreakpoints[I].IgnoreCount);
          Continue;
        end;
        
        Result := FBreakpoints[I].Id;
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// 断点管理
// ============================================================================

function TWorkflowDebugger.AddBreakpoint(const StepId: string): Integer;
var
  Bp: TBreakpoint;
begin
  FLock.Enter;
  try
    Bp.Id := FNextBreakpointId;
    Inc(FNextBreakpointId);
    Bp.BreakpointType := bpStep;
    Bp.StepId := StepId;
    Bp.Condition := '';
    Bp.WatchVariable := '';
    Bp.Enabled := True;
    Bp.HitCount := 0;
    Bp.IgnoreCount := 0;
    
    SetLength(FBreakpoints, Length(FBreakpoints) + 1);
    FBreakpoints[High(FBreakpoints)] := Bp;
    
    Result := Bp.Id;
    
    Diagnostics.Debug('Debugger', 'Breakpoint #%d added at step [%s]', [Result, StepId]);
  finally
    FLock.Leave;
  end;
end;

function TWorkflowDebugger.AddConditionalBreakpoint(const StepId, Condition: string): Integer;
var
  Bp: TBreakpoint;
begin
  FLock.Enter;
  try
    Bp.Id := FNextBreakpointId;
    Inc(FNextBreakpointId);
    Bp.BreakpointType := bpConditional;
    Bp.StepId := StepId;
    Bp.Condition := Condition;
    Bp.WatchVariable := '';
    Bp.Enabled := True;
    Bp.HitCount := 0;
    Bp.IgnoreCount := 0;
    
    SetLength(FBreakpoints, Length(FBreakpoints) + 1);
    FBreakpoints[High(FBreakpoints)] := Bp;
    
    Result := Bp.Id;
    
    Diagnostics.Debug('Debugger', 'Conditional breakpoint #%d added at step [%s] when [%s]', 
      [Result, StepId, Condition]);
  finally
    FLock.Leave;
  end;
end;

function TWorkflowDebugger.AddWatchBreakpoint(const VariableName: string): Integer;
var
  Bp: TBreakpoint;
begin
  FLock.Enter;
  try
    Bp.Id := FNextBreakpointId;
    Inc(FNextBreakpointId);
    Bp.BreakpointType := bpWatch;
    Bp.StepId := '';
    Bp.Condition := '';
    Bp.WatchVariable := VariableName;
    Bp.Enabled := True;
    Bp.HitCount := 0;
    Bp.IgnoreCount := 0;
    
    SetLength(FBreakpoints, Length(FBreakpoints) + 1);
    FBreakpoints[High(FBreakpoints)] := Bp;
    
    Result := Bp.Id;
    
    Diagnostics.Debug('Debugger', 'Watch breakpoint #%d added for variable [%s]', 
      [Result, VariableName]);
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDebugger.RemoveBreakpoint(BreakpointId: Integer);
var
  I, J: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to High(FBreakpoints) do
    begin
      if FBreakpoints[I].Id = BreakpointId then
      begin
        for J := I to High(FBreakpoints) - 1 do
          FBreakpoints[J] := FBreakpoints[J + 1];
        SetLength(FBreakpoints, Length(FBreakpoints) - 1);
        Diagnostics.Debug('Debugger', 'Breakpoint #%d removed', [BreakpointId]);
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDebugger.EnableBreakpoint(BreakpointId: Integer);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to High(FBreakpoints) do
    begin
      if FBreakpoints[I].Id = BreakpointId then
      begin
        FBreakpoints[I].Enabled := True;
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDebugger.DisableBreakpoint(BreakpointId: Integer);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to High(FBreakpoints) do
    begin
      if FBreakpoints[I].Id = BreakpointId then
      begin
        FBreakpoints[I].Enabled := False;
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowDebugger.ClearBreakpoints;
begin
  FLock.Enter;
  try
    SetLength(FBreakpoints, 0);
    Diagnostics.Debug('Debugger', 'All breakpoints cleared');
  finally
    FLock.Leave;
  end;
end;

function TWorkflowDebugger.GetBreakpoints: TBreakpointArray;
begin
  FLock.Enter;
  try
    Result := Copy(FBreakpoints);
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// 执行控制
// ============================================================================

procedure TWorkflowDebugger.Continue;
begin
  FStepMode := smNone;
  SetState(dsRunning);
  NotifyStateChanged('Continuing execution');
  Diagnostics.Debug('Debugger', 'Continue');
end;

procedure TWorkflowDebugger.Pause;
begin
  SetState(dsPaused);
  NotifyStateChanged('Execution paused');
  Diagnostics.Debug('Debugger', 'Paused');
end;

procedure TWorkflowDebugger.StepInto;
begin
  FStepMode := smInto;
  SetState(dsStepping);
  FPauseEvent.SetEvent; // 允许执行一�?
  NotifyStateChanged('Step into');
  Diagnostics.Debug('Debugger', 'Step into');
end;

procedure TWorkflowDebugger.StepOver;
begin
  FStepMode := smOver;
  FStepOverDepth := GetCallStackDepth;
  SetState(dsStepping);
  FPauseEvent.SetEvent;
  NotifyStateChanged('Step over');
  Diagnostics.Debug('Debugger', 'Step over');
end;

procedure TWorkflowDebugger.StepOut;
begin
  FStepMode := smOut;
  FStepOverDepth := GetCallStackDepth - 1;
  SetState(dsStepping);
  FPauseEvent.SetEvent;
  NotifyStateChanged('Step out');
  Diagnostics.Debug('Debugger', 'Step out');
end;

procedure TWorkflowDebugger.Stop;
begin
  SetState(dsIdle);
  FLock.Enter;
  try
    SetLength(FCallStack, 0);
  finally
    FLock.Leave;
  end;
  NotifyStateChanged('Execution stopped');
  Diagnostics.Debug('Debugger', 'Stopped');
end;

// ============================================================================
// 调用�?
// ============================================================================

function TWorkflowDebugger.GetCallStack: TDebugFrameArray;
begin
  FLock.Enter;
  try
    Result := Copy(FCallStack);
  finally
    FLock.Leave;
  end;
end;

function TWorkflowDebugger.GetCallStackDepth: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FCallStack);
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// 变量检�?
// ============================================================================

function TWorkflowDebugger.GetVariables: TJSONObject;
var
  Frame: TDebugFrame;
begin
  Frame := GetCurrentFrame;
  if Assigned(Frame.Variables) then
    Result := Frame.Variables.Clone as TJSONObject
  else
    Result := TJSONObject.Create;
end;

function TWorkflowDebugger.GetVariable(const Name: string): TJSONValue;
var
  Frame: TDebugFrame;
begin
  Result := nil;
  Frame := GetCurrentFrame;
  if Assigned(Frame.Variables) and (Frame.Variables.FindValue(Name) <> nil) then
    Result := Frame.Variables.FindValue(Name).Clone as TJSONValue;
end;

function TWorkflowDebugger.EvaluateExpression(const Expr: string): string;
var
  Frame: TDebugFrame;
  Data: TJSONValue;
begin
  Result := '<undefined>';
  Frame := GetCurrentFrame;
  
  if Assigned(Frame.Variables) then
  begin
    // 简单变量查�?
    Data := Frame.Variables.FindValue(Expr);
    if Assigned(Data) then
      Result := Data.ToJSON
    else
      Result := Format('<variable "%s" not found>', [Expr]);
  end;
end;

// ============================================================================
// 步骤钩子
// ============================================================================

procedure TWorkflowDebugger.OnEnterStep(const WorkflowId, WorkflowName, StepId, StepType: string;
  Variables: TJSONObject);
var
  Frame: TDebugFrame;
  BpId: Integer;
  Args: TDebugEventArgs;
  ShouldPause: Boolean;
begin
  if not FConfig.Enabled then Exit;
  
  // 添加到调用栈
  Frame.WorkflowId := WorkflowId;
  Frame.WorkflowName := WorkflowName;
  Frame.StepId := StepId;
  Frame.StepType := StepType;
  Frame.EnteredAt := Now;
  if Assigned(Variables) then
    Frame.Variables := Variables.Clone as TJSONObject
  else
    Frame.Variables := nil;
  
  FLock.Enter;
  try
    Frame.StepIndex := Length(FCallStack);
    SetLength(FCallStack, Length(FCallStack) + 1);
    FCallStack[High(FCallStack)] := Frame;
  finally
    FLock.Leave;
  end;
  
  // 检查是否需要暂�?
  ShouldPause := False;
  
  // 启动时暂�?
  if FConfig.BreakOnStart and (Frame.StepIndex = 0) then
    ShouldPause := True;
  
  // 检查断�?
  BpId := CheckBreakpoint(StepId);
  if BpId >= 0 then
  begin
    ShouldPause := True;
    SetState(dsBreakpoint);
    
    if Assigned(FOnBreakpointHit) then
    begin
      Args.State := dsBreakpoint;
      Args.CurrentFrame := Frame;
      // 查找断点
      FLock.Enter;
      try
        for BpId := 0 to High(FBreakpoints) do
          if FBreakpoints[BpId].Id = BpId then
          begin
            Args.Breakpoint := FBreakpoints[BpId];
            Break;
          end;
      finally
        FLock.Leave;
      end;
      Args.Message := Format('Breakpoint hit at step [%s]', [StepId]);
      FOnBreakpointHit(Self, Args);
    end;
    
    Diagnostics.Info('Debugger', 'Breakpoint hit at step [%s]', [StepId]);
  end;
  
  // 单步模式检�?
  case FStepMode of
    smInto:
      ShouldPause := True;
    smOver:
      if GetCallStackDepth <= FStepOverDepth then
        ShouldPause := True;
    smOut:
      if GetCallStackDepth <= FStepOverDepth then
        ShouldPause := True;
  end;
  
  if ShouldPause then
  begin
    if FState <> dsBreakpoint then
      SetState(dsPaused);
    FStepMode := smNone;
    NotifyStateChanged(Format('Paused at step [%s]', [StepId]));
  end;
  
  // 等待继续
  WaitIfPaused;
end;

procedure TWorkflowDebugger.OnExitStep(const StepId: string);
var
  Args: TDebugEventArgs;
begin
  if not FConfig.Enabled then Exit;
  
  // 从调用栈移除
  FLock.Enter;
  try
    if (Length(FCallStack) > 0) and (FCallStack[High(FCallStack)].StepId = StepId) then
    begin
      if Assigned(FCallStack[High(FCallStack)].Variables) then
        FCallStack[High(FCallStack)].Variables.Free;
      SetLength(FCallStack, Length(FCallStack) - 1);
    end;
  finally
    FLock.Leave;
  end;
  
  // 触发事件
  if Assigned(FOnStepCompleted) then
  begin
    Args.State := FState;
    Args.CurrentFrame := GetCurrentFrame;
    Args.Message := Format('Step [%s] completed', [StepId]);
    FOnStepCompleted(Self, Args);
  end;
  
  // 结束时暂�?
  if FConfig.BreakOnEnd and (GetCallStackDepth = 0) then
  begin
    SetState(dsPaused);
    NotifyStateChanged('Workflow completed');
  end;
end;

procedure TWorkflowDebugger.OnError(const StepId, ErrorMsg: string);
begin
  if not FConfig.Enabled then Exit;
  
  if FConfig.BreakOnError then
  begin
    SetState(dsBreakpoint);
    NotifyStateChanged(Format('Error at step [%s]: %s', [StepId, ErrorMsg]));
    Diagnostics.Error('Debugger', 'Break on error at [%s]: %s', [StepId, ErrorMsg]);
    WaitIfPaused;
  end;
end;

// ============================================================================
// TDebugConsole
// ============================================================================

constructor TDebugConsole.Create(ADebugger: TWorkflowDebugger);
begin
  inherited Create;
  FDebugger := ADebugger;
  FRunning := False;
end;

procedure TDebugConsole.PrintHelp;
begin
  WriteLn('UniFlow Debugger Commands:');
  WriteLn('  c, continue    - Continue execution');
  WriteLn('  p, pause       - Pause execution');
  WriteLn('  s, step        - Step into next');
  WriteLn('  n, next        - Step over');
  WriteLn('  o, out         - Step out');
  WriteLn('  q, quit        - Stop debugging');
  WriteLn('');
  WriteLn('  b <step>       - Set breakpoint at step');
  WriteLn('  d <id>         - Delete breakpoint');
  WriteLn('  bl             - List breakpoints');
  WriteLn('');
  WriteLn('  bt, backtrace  - Show call stack');
  WriteLn('  v, vars        - Show variables');
  WriteLn('  e <expr>       - Evaluate expression');
  WriteLn('  state          - Show debugger state');
  WriteLn('  h, help        - Show this help');
end;

procedure TDebugConsole.PrintState;
begin
  WriteLn(Format('State: %s', [DebuggerStateToString(FDebugger.State)]));
  if FDebugger.State in [dsPaused, dsBreakpoint] then
  begin
    WriteLn(Format('  Workflow: %s', [FDebugger.CurrentFrame.WorkflowName]));
    WriteLn(Format('  Step: %s (%s)', [FDebugger.CurrentFrame.StepId, FDebugger.CurrentFrame.StepType]));
  end;
end;

procedure TDebugConsole.PrintCallStack;
var
  Stack: TDebugFrameArray;
  I: Integer;
begin
  Stack := FDebugger.GetCallStack;
  if Length(Stack) = 0 then
  begin
    WriteLn('Call stack is empty');
    Exit;
  end;
  
  WriteLn('Call Stack:');
  for I := High(Stack) downto 0 do
    WriteLn(Format('  #%d %s.%s (%s)', [I, Stack[I].WorkflowName, Stack[I].StepId, Stack[I].StepType]));
end;

procedure TDebugConsole.PrintBreakpoints;
var
  Bps: TBreakpointArray;
  I: Integer;
begin
  Bps := FDebugger.GetBreakpoints;
  if Length(Bps) = 0 then
  begin
    WriteLn('No breakpoints set');
    Exit;
  end;
  
  WriteLn('Breakpoints:');
  for I := 0 to High(Bps) do
  begin
    Write(Format('  #%d [%s] ', [Bps[I].Id, BreakpointTypeToString(Bps[I].BreakpointType)]));
    if Bps[I].StepId <> '' then
      Write(Format('at %s ', [Bps[I].StepId]));
    if not Bps[I].Enabled then
      Write('(disabled) ');
    if Bps[I].HitCount > 0 then
      Write(Format('(hit %d times)', [Bps[I].HitCount]));
    WriteLn;
  end;
end;

procedure TDebugConsole.PrintVariables;
var
  Vars: TJSONObject;
begin
  Vars := FDebugger.GetVariables;
  try
    if Vars.Count = 0 then
      WriteLn('No variables in current scope')
    else
      WriteLn(Vars.Format);
  finally
    Vars.Free;
  end;
end;

procedure TDebugConsole.ProcessCommand(const Cmd: string);
var
  Parts: TStringArray;
  CmdLower: string;
begin
  Parts := Cmd.Split([' '], 2);
  if Length(Parts) = 0 then Exit;
  
  CmdLower := LowerCase(Parts[0]);
  
  if (CmdLower = 'c') or (CmdLower = 'continue') then
    FDebugger.Continue
  else if (CmdLower = 'p') or (CmdLower = 'pause') then
    FDebugger.Pause
  else if (CmdLower = 's') or (CmdLower = 'step') then
    FDebugger.StepInto
  else if (CmdLower = 'n') or (CmdLower = 'next') then
    FDebugger.StepOver
  else if (CmdLower = 'o') or (CmdLower = 'out') then
    FDebugger.StepOut
  else if (CmdLower = 'q') or (CmdLower = 'quit') then
  begin
    FDebugger.Stop;
    FRunning := False;
  end
  else if CmdLower = 'b' then
  begin
    if Length(Parts) > 1 then
      WriteLn(Format('Breakpoint #%d set', [FDebugger.AddBreakpoint(Parts[1])]))
    else
      WriteLn('Usage: b <step_id>');
  end
  else if CmdLower = 'd' then
  begin
    if Length(Parts) > 1 then
      FDebugger.RemoveBreakpoint(StrToIntDef(Parts[1], -1))
    else
      WriteLn('Usage: d <breakpoint_id>');
  end
  else if CmdLower = 'bl' then
    PrintBreakpoints
  else if (CmdLower = 'bt') or (CmdLower = 'backtrace') then
    PrintCallStack
  else if (CmdLower = 'v') or (CmdLower = 'vars') then
    PrintVariables
  else if CmdLower = 'e' then
  begin
    if Length(Parts) > 1 then
      WriteLn(FDebugger.EvaluateExpression(Parts[1]))
    else
      WriteLn('Usage: e <expression>');
  end
  else if CmdLower = 'state' then
    PrintState
  else if (CmdLower = 'h') or (CmdLower = 'help') then
    PrintHelp
  else
    WriteLn(Format('Unknown command: %s (type "help" for help)', [Parts[0]]));
end;

procedure TDebugConsole.Run;
var
  Input: string;
begin
  FRunning := True;
  WriteLn('UniFlow Debugger');
  WriteLn('Type "help" for available commands');
  WriteLn('');
  
  while FRunning do
  begin
    Write('(ufd) ');
    ReadLn(Input);
    Input := Trim(Input);
    if Input <> '' then
      ProcessCommand(Input);
  end;
end;

procedure TDebugConsole.Stop;
begin
  FRunning := False;
end;

function TDebugConsole.ExecuteCommand(const Cmd: string): string;
begin
  ProcessCommand(Cmd);
  Result := 'OK';
end;

// ============================================================================
// 全局实例
// ============================================================================

function Debugger: TWorkflowDebugger;
begin
  if GDebugger = nil then
  begin
    GDebuggerLock.Enter;
    try
      if GDebugger = nil then
        GDebugger := TWorkflowDebugger.Create(TDebuggerConfig.Default);
    finally
      GDebuggerLock.Leave;
    end;
  end;
  Result := GDebugger;
end;

procedure InitializeDebugger(const AConfig: TDebuggerConfig);
begin
  GDebuggerLock.Enter;
  try
    if GDebugger <> nil then
      FreeAndNil(GDebugger);
    GDebugger := TWorkflowDebugger.Create(AConfig);
  finally
    GDebuggerLock.Leave;
  end;
end;

procedure FinalizeDebugger;
begin
  GDebuggerLock.Enter;
  try
    FreeAndNil(GDebugger);
  finally
    GDebuggerLock.Leave;
  end;
end;

initialization
  GDebuggerLock := TCriticalSection.Create;

finalization
  FreeAndNil(GDebugger);
  FreeAndNil(GDebuggerLock);

end.
