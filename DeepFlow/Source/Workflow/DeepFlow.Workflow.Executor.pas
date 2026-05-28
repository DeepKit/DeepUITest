unit UniFlow.Workflow.Executor;
(*
  UniFlow Workflow Executor
  =========================
  工作流步骤执行引擎，实现�?
  - 线性步骤执�?
  - 条件分支
  - 循环（forEach/while�?
  - 并行执行（基础支持�?
  - 错误处理与重�?
  
  设计原则�?
  - 可暂�?恢复执行
  - 支持检查点
  - 事件驱动
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.SyncObjs, System.Threading,
  UniFlow.Workflow.Definition, UniFlow.Workflow.Context, UniFlow.Workflow.Errors;

type
  // ============================================================================
  // 执行状�?
  // ============================================================================
  
  TExecutionStatus = (
    esIdle,         // 空闲
    esRunning,      // 运行�?
    esPaused,       // 暂停
    esWaiting,      // 等待外部输入
    esCompleted,    // 完成
    esFailed,       // 失败
    esCancelled     // 取消
  );
  
  // ============================================================================
  // 步骤执行结果
  // ============================================================================
  
  /// <summary>
  /// 步骤执行结果
  /// CODE-001: Output 所有权说明
  ///   - �?OwnsOutput=True 时，TStepResult 拥有 Output 的所有权，析构时会释�?
  ///   - �?OwnsOutput=False 时，调用者负责管�?Output 生命周期
  ///   - 默认 OwnsOutput=True
  /// </summary>
  TStepResult = class
  private
    FSuccess: Boolean;
    FOutput: TJSONValue;
    FOwnsOutput: Boolean;    // CODE-001: 明确 Output 所有权
    FErrorCode: string;
    FErrorMessage: string;
    FNextStepId: string;     // 跳转到指定步�?
    FNeedsWait: Boolean;     // 需要等待外部输�?
    FWaitData: TJSONObject;  // 等待配置
    procedure SetOutput(AValue: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    
    class function OK(AOutput: TJSONValue = nil): TStepResult;
    class function Fail(const ACode, AMessage: string): TStepResult;
    class function Wait(AWaitData: TJSONObject): TStepResult;
    class function GotoStep(const AStepId: string): TStepResult;
    
    function Clone: TStepResult;
    
    /// <summary>释放 Output 所有权，返�?Output 并清除引�?/summary>
    function ReleaseOutput: TJSONValue;
    
    property Success: Boolean read FSuccess write FSuccess;
    property Output: TJSONValue read FOutput write SetOutput;
    /// <summary>CODE-001: 是否拥有 Output 的所有权，默�?True</summary>
    property OwnsOutput: Boolean read FOwnsOutput write FOwnsOutput;
    property ErrorCode: string read FErrorCode write FErrorCode;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property NextStepId: string read FNextStepId write FNextStepId;
    property NeedsWait: Boolean read FNeedsWait write FNeedsWait;
    property WaitData: TJSONObject read FWaitData write FWaitData;
  end;
  
  // ============================================================================
  // 执行事件
  // ============================================================================
  
  TWorkflowExecutor = class;
  
  TOnStepStartEvent = procedure(Sender: TWorkflowExecutor; Step: TWorkflowStep) of object;
  TOnStepCompleteEvent = procedure(Sender: TWorkflowExecutor; Step: TWorkflowStep; Result: TStepResult) of object;
  TOnWorkflowCompleteEvent = procedure(Sender: TWorkflowExecutor; Success: Boolean; Output: TJSONValue) of object;
  TOnWorkflowErrorEvent = procedure(Sender: TWorkflowExecutor; const ErrorCode, ErrorMessage: string) of object;
  TOnWaitInputEvent = procedure(Sender: TWorkflowExecutor; Step: TWorkflowStep; WaitData: TJSONObject) of object;
  
  // ============================================================================
  // 动作执行器接�?
  // ============================================================================
  
  IActionExecutor = interface
    ['{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}']
    function Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
    function CanHandle(AActionType: TActionType): Boolean;
  end;
  
  // ============================================================================
  // 步骤执行位置
  // ============================================================================
  
  TExecutionCursor = class
  private
    FStepIndex: Integer;
    FStepId: string;
    FBranchIndex: Integer;
    FLoopIndex: Integer;
    FSubCursor: TExecutionCursor;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TExecutionCursor;
    
    property StepIndex: Integer read FStepIndex write FStepIndex;
    property StepId: string read FStepId write FStepId;
    property BranchIndex: Integer read FBranchIndex write FBranchIndex;
    property LoopIndex: Integer read FLoopIndex write FLoopIndex;
    property SubCursor: TExecutionCursor read FSubCursor write FSubCursor;
  end;
  
  // ============================================================================
  // 工作流执行器
  // ============================================================================
  
  TWorkflowExecutor = class
  private
    FWorkflow: TWorkflowDefinition;
    FContext: TWorkflowContext;
    FStatus: TExecutionStatus;
    FCursor: TExecutionCursor;
    FActionExecutors: TList<IActionExecutor>;
    FEvaluator: TExpressionEvaluator;
    
    FLock: TCriticalSection;
    FCancelled: Boolean;
    
    // 事件
    FOnStepStart: TOnStepStartEvent;
    FOnStepComplete: TOnStepCompleteEvent;
    FOnWorkflowComplete: TOnWorkflowCompleteEvent;
    FOnWorkflowError: TOnWorkflowErrorEvent;
    FOnWaitInput: TOnWaitInputEvent;
    
    // 错误处理追踪
    FRetryCount: TDictionary<string, Integer>;
    
    function ExecuteStep(AStep: TWorkflowStep): TStepResult;
    function ExecuteAction(AStep: TWorkflowStep): TStepResult;
    function ExecuteCondition(AStep: TWorkflowStep): TStepResult;
    function ExecuteLoop(AStep: TWorkflowStep): TStepResult;
    function ExecuteParallel(AStep: TWorkflowStep): TStepResult;
    function ExecuteWait(AStep: TWorkflowStep): TStepResult;
    function ExecuteSubWorkflow(AStep: TWorkflowStep): TStepResult;
    
    function EvaluateBranch(ABranch: TConditionBranch; const AExprValue: string): Boolean;
    function HandleStepError(AStep: TWorkflowStep; AResult: TStepResult): TStepResult;
    function FindErrorHandler(AStep: TWorkflowStep; const AErrorCode: string): TErrorHandler;
    function ApplyRetryPolicy(AStep: TWorkflowStep; ARetryPolicy: TRetryPolicy): Boolean;
    
    procedure SaveStepOutput(AStep: TWorkflowStep; AResult: TStepResult);
    procedure DoStepStart(AStep: TWorkflowStep);
    procedure DoStepComplete(AStep: TWorkflowStep; AResult: TStepResult);
  public
    constructor Create(AWorkflow: TWorkflowDefinition; AContext: TWorkflowContext);
    destructor Destroy; override;
    
    /// <summary>注册动作执行�?/summary>
    procedure RegisterActionExecutor(AExecutor: IActionExecutor);
    
    /// <summary>开始执�?/summary>
    function Start: TStepResult;
    
    /// <summary>从指定步骤恢复执�?/summary>
    function Resume(const AFromStepId: string = ''): TStepResult;
    
    /// <summary>提供等待输入</summary>
    procedure ProvideInput(AInput: TJSONValue);
    
    /// <summary>暂停执行</summary>
    procedure Pause;
    
    /// <summary>取消执行</summary>
    procedure Cancel;
    
    /// <summary>执行单步（调试用�?/summary>
    function StepOnce: TStepResult;
    
    /// <summary>获取当前状态快�?/summary>
    function GetSnapshot: TJSONObject;
    
    /// <summary>从快照恢�?/summary>
    procedure LoadFromSnapshot(ASnapshot: TJSONObject);
    
    property Workflow: TWorkflowDefinition read FWorkflow;
    property Context: TWorkflowContext read FContext;
    property Status: TExecutionStatus read FStatus;
    property Cursor: TExecutionCursor read FCursor;
    
    // 事件
    property OnStepStart: TOnStepStartEvent read FOnStepStart write FOnStepStart;
    property OnStepComplete: TOnStepCompleteEvent read FOnStepComplete write FOnStepComplete;
    property OnWorkflowComplete: TOnWorkflowCompleteEvent read FOnWorkflowComplete write FOnWorkflowComplete;
    property OnWorkflowError: TOnWorkflowErrorEvent read FOnWorkflowError write FOnWorkflowError;
    property OnWaitInput: TOnWaitInputEvent read FOnWaitInput write FOnWaitInput;
  end;
  
  // ============================================================================
  // 内置动作执行�?
  // ============================================================================
  
  /// <summary>日志动作执行�?/summary>
  TLogActionExecutor = class(TInterfacedObject, IActionExecutor)
  public
    function Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
    function CanHandle(AActionType: TActionType): Boolean;
  end;
  
  /// <summary>赋值动作执行器</summary>
  TAssignActionExecutor = class(TInterfacedObject, IActionExecutor)
  public
    function Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
    function CanHandle(AActionType: TActionType): Boolean;
  end;
  
  /// <summary>Guard 动作执行�?/summary>
  TGuardActionExecutor = class(TInterfacedObject, IActionExecutor)
  private
    function ValidateInput(AContext: TWorkflowContext; ARules: TJSONArray): TStepResult;
    function ValidateOutput(AContext: TWorkflowContext; ARules: TJSONArray): TStepResult;
  public
    function Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
    function CanHandle(AActionType: TActionType): Boolean;
  end;

implementation

uses
  System.StrUtils, System.DateUtils, System.Math, System.RegularExpressions;

// ============================================================================
// TStepResult
// ============================================================================

constructor TStepResult.Create;
begin
  inherited Create;
  FSuccess := True;
  FNeedsWait := False;
  FOwnsOutput := True;  // CODE-001: 默认拥有所有权
end;

destructor TStepResult.Destroy;
begin
  // CODE-001: 仅在拥有所有权时释�?
  if FOwnsOutput then
    FOutput.Free;
  FWaitData.Free;
  inherited;
end;

procedure TStepResult.SetOutput(AValue: TJSONValue);
begin
  // CODE-001: 设置新值前释放旧�?
  if FOwnsOutput and (FOutput <> AValue) then
    FOutput.Free;
  FOutput := AValue;
end;

function TStepResult.ReleaseOutput: TJSONValue;
begin
  // CODE-001: 释放所有权并返�?
  Result := FOutput;
  FOutput := nil;
  FOwnsOutput := False;
end;

class function TStepResult.OK(AOutput: TJSONValue): TStepResult;
begin
  Result := TStepResult.Create;
  Result.FSuccess := True;
  if AOutput <> nil then
    Result.FOutput := AOutput.Clone as TJSONValue;
end;

class function TStepResult.Fail(const ACode, AMessage: string): TStepResult;
begin
  Result := TStepResult.Create;
  Result.FSuccess := False;
  Result.FErrorCode := ACode;
  Result.FErrorMessage := AMessage;
end;

class function TStepResult.Wait(AWaitData: TJSONObject): TStepResult;
begin
  Result := TStepResult.Create;
  Result.FSuccess := True;
  Result.FNeedsWait := True;
  if AWaitData <> nil then
    Result.FWaitData := TJSONObject(AWaitData.Clone);
end;

class function TStepResult.GotoStep(const AStepId: string): TStepResult;
begin
  Result := TStepResult.Create;
  Result.FSuccess := True;
  Result.FNextStepId := AStepId;
end;

function TStepResult.Clone: TStepResult;
begin
  Result := TStepResult.Create;
  Result.FSuccess := FSuccess;
  if Assigned(FOutput) then
    Result.FOutput := FOutput.Clone as TJSONValue;
  Result.FOwnsOutput := True;  // CODE-001: 克隆的结果拥有所有权
  Result.FErrorCode := FErrorCode;
  Result.FErrorMessage := FErrorMessage;
  Result.FNextStepId := FNextStepId;
  Result.FNeedsWait := FNeedsWait;
  if Assigned(FWaitData) then
    Result.FWaitData := TJSONObject(FWaitData.Clone);
end;

// ============================================================================
// TExecutionCursor
// ============================================================================

constructor TExecutionCursor.Create;
begin
  inherited Create;
  FStepIndex := 0;
  FBranchIndex := -1;
  FLoopIndex := 0;
end;

destructor TExecutionCursor.Destroy;
begin
  FSubCursor.Free;
  inherited;
end;

procedure TExecutionCursor.LoadFromJSON(AJson: TJSONObject);
var
  SubObj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<Integer>('stepIndex', FStepIndex) then;
  if AJson.TryGetValue<string>('stepId', FStepId) then;
  if AJson.TryGetValue<Integer>('branchIndex', FBranchIndex) then;
  if AJson.TryGetValue<Integer>('loopIndex', FLoopIndex) then;
  
  if AJson.TryGetValue<TJSONObject>('subCursor', SubObj) then
  begin
    FSubCursor := TExecutionCursor.Create;
    FSubCursor.LoadFromJSON(SubObj);
  end;
end;

function TExecutionCursor.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('stepIndex', TJSONNumber.Create(FStepIndex));
  Result.AddPair('stepId', FStepId);
  Result.AddPair('branchIndex', TJSONNumber.Create(FBranchIndex));
  Result.AddPair('loopIndex', TJSONNumber.Create(FLoopIndex));
  
  if Assigned(FSubCursor) then
    Result.AddPair('subCursor', FSubCursor.ToJSON);
end;

function TExecutionCursor.Clone: TExecutionCursor;
begin
  Result := TExecutionCursor.Create;
  Result.FStepIndex := FStepIndex;
  Result.FStepId := FStepId;
  Result.FBranchIndex := FBranchIndex;
  Result.FLoopIndex := FLoopIndex;
  if Assigned(FSubCursor) then
    Result.FSubCursor := FSubCursor.Clone;
end;

// ============================================================================
// TWorkflowExecutor
// ============================================================================

constructor TWorkflowExecutor.Create(AWorkflow: TWorkflowDefinition; AContext: TWorkflowContext);
begin
  inherited Create;
  FWorkflow := AWorkflow;
  FContext := AContext;
  FStatus := esIdle;
  FCursor := TExecutionCursor.Create;
  FActionExecutors := TList<IActionExecutor>.Create;
  FEvaluator := TExpressionEvaluator.Create(FContext);
  FLock := TCriticalSection.Create;
  FCancelled := False;
  FRetryCount := TDictionary<string, Integer>.Create;
  
  // 注册内置执行�?
  RegisterActionExecutor(TLogActionExecutor.Create);
  RegisterActionExecutor(TAssignActionExecutor.Create);
  RegisterActionExecutor(TGuardActionExecutor.Create);
end;

destructor TWorkflowExecutor.Destroy;
begin
  FLock.Free;
  FEvaluator.Free;
  FCursor.Free;
  FActionExecutors.Free;
  FRetryCount.Free;
  inherited;
end;

procedure TWorkflowExecutor.RegisterActionExecutor(AExecutor: IActionExecutor);
begin
  FActionExecutors.Add(AExecutor);
end;

function TWorkflowExecutor.Start: TStepResult;
var
  I: Integer;
  Step: TWorkflowStep;
  StepResult: TStepResult;
begin
  FLock.Enter;
  try
    if FStatus = esRunning then
      Exit(TStepResult.Fail(ERR_ALREADY_RUNNING, 'FlowInstance is already running'));
    
    FStatus := esRunning;
    FCancelled := False;
    FCursor.StepIndex := 0;
  finally
    FLock.Leave;
  end;
  
  Result := nil;
  I := 0;
  
  while (I < FWorkflow.Steps.Count) and not FCancelled do
  begin
    Step := FWorkflow.Steps[I];
    FCursor.StepIndex := I;
    FCursor.StepId := Step.Id;
    
    // 检查执行条�?
    if Assigned(Step.Condition) then
    begin
      if not FEvaluator.Evaluate(Step.Condition) then
      begin
        Inc(I);
        Continue;
      end;
    end;
    
    // 执行步骤
    DoStepStart(Step);
    StepResult := ExecuteStep(Step);
    DoStepComplete(Step, StepResult);
    
    // 处理执行结果
    if StepResult.NeedsWait then
    begin
      FStatus := esWaiting;
      if Assigned(FOnWaitInput) then
        FOnWaitInput(Self, Step, StepResult.WaitData);
      Result := StepResult;
      Exit;
    end;
    
    if not StepResult.Success then
    begin
      // 尝试错误处理
      StepResult := HandleStepError(Step, StepResult);
      
      if not StepResult.Success then
      begin
        FStatus := esFailed;
        if Assigned(FOnWorkflowError) then
          FOnWorkflowError(Self, StepResult.ErrorCode, StepResult.ErrorMessage);
        Result := StepResult;
        Exit;
      end;
    end;
    
    // 保存输出
    SaveStepOutput(Step, StepResult);
    
    // 处理跳转
    if StepResult.NextStepId <> '' then
    begin
      // 查找目标步骤
      for var J := 0 to FWorkflow.Steps.Count - 1 do
      begin
        if FWorkflow.Steps[J].Id = StepResult.NextStepId then
        begin
          I := J;
          Break;
        end;
      end;
    end
    else
      Inc(I);
    
    StepResult.Free;
    StepResult := nil;
  end;
  
  if FCancelled then
  begin
    FStatus := esCancelled;
    Result := TStepResult.Fail(ERR_CANCELLED, 'FlowInstance was cancelled');
  end
  else
  begin
    FStatus := esCompleted;
    Result := TStepResult.OK;
    if Assigned(FOnWorkflowComplete) then
      FOnWorkflowComplete(Self, True, nil);
  end;
end;

function TWorkflowExecutor.Resume(const AFromStepId: string): TStepResult;
var
  StartIndex: Integer;
begin
  StartIndex := 0;
  
  if AFromStepId <> '' then
  begin
    for var I := 0 to FWorkflow.Steps.Count - 1 do
    begin
      if FWorkflow.Steps[I].Id = AFromStepId then
      begin
        StartIndex := I;
        Break;
      end;
    end;
  end
  else if FCursor.StepIndex > 0 then
    StartIndex := FCursor.StepIndex;
  
  FCursor.StepIndex := StartIndex;
  FStatus := esRunning;
  FCancelled := False;
  
  // 继续执行
  Result := nil;
  for var I := StartIndex to FWorkflow.Steps.Count - 1 do
  begin
    if FCancelled then Break;
    
    var Step := FWorkflow.Steps[I];
    FCursor.StepIndex := I;
    FCursor.StepId := Step.Id;
    
    if Assigned(Step.Condition) then
    begin
      if not FEvaluator.Evaluate(Step.Condition) then
        Continue;
    end;
    
    DoStepStart(Step);
    var StepResult := ExecuteStep(Step);
    DoStepComplete(Step, StepResult);
    
    if StepResult.NeedsWait then
    begin
      FStatus := esWaiting;
      if Assigned(FOnWaitInput) then
        FOnWaitInput(Self, Step, StepResult.WaitData);
      Exit(StepResult);
    end;
    
    if not StepResult.Success then
    begin
      StepResult := HandleStepError(Step, StepResult);
      if not StepResult.Success then
      begin
        FStatus := esFailed;
        if Assigned(FOnWorkflowError) then
          FOnWorkflowError(Self, StepResult.ErrorCode, StepResult.ErrorMessage);
        Exit(StepResult);
      end;
    end;
    
    SaveStepOutput(Step, StepResult);
    StepResult.Free;
  end;
  
  if FCancelled then
  begin
    FStatus := esCancelled;
    Result := TStepResult.Fail(ERR_CANCELLED, 'FlowInstance was cancelled');
  end
  else
  begin
    FStatus := esCompleted;
    Result := TStepResult.OK;
    if Assigned(FOnWorkflowComplete) then
      FOnWorkflowComplete(Self, True, nil);
  end;
end;

procedure TWorkflowExecutor.ProvideInput(AInput: TJSONValue);
begin
  if FStatus <> esWaiting then Exit;
  
  // 保存输入到当前步骤的输出
  if FCursor.StepIndex < FWorkflow.Steps.Count then
  begin
    var Step := FWorkflow.Steps[FCursor.StepIndex];
    FContext.SetStepOutput(Step.Id, AInput);
    
    if Step.Output.Variable <> '' then
      FContext.SetVariable(Step.Output.Variable, TVariableValue.Create(AInput));
  end;
  
  // 继续执行
  FCursor.StepIndex := FCursor.StepIndex + 1;
  FStatus := esRunning;
  Resume;
end;

procedure TWorkflowExecutor.Pause;
begin
  FLock.Enter;
  try
    if FStatus = esRunning then
      FStatus := esPaused;
  finally
    FLock.Leave;
  end;
end;

procedure TWorkflowExecutor.Cancel;
begin
  FLock.Enter;
  try
    FCancelled := True;
    if FStatus in [esRunning, esPaused, esWaiting] then
      FStatus := esCancelled;
  finally
    FLock.Leave;
  end;
end;

function TWorkflowExecutor.StepOnce: TStepResult;
var
  Step: TWorkflowStep;
begin
  if FCursor.StepIndex >= FWorkflow.Steps.Count then
    Exit(TStepResult.OK);
  
  Step := FWorkflow.Steps[FCursor.StepIndex];
  FCursor.StepId := Step.Id;
  
  DoStepStart(Step);
  Result := ExecuteStep(Step);
  DoStepComplete(Step, Result);
  
  if Result.Success and not Result.NeedsWait then
  begin
    SaveStepOutput(Step, Result);
    Inc(FCursor.FStepIndex);
  end;
end;

function TWorkflowExecutor.ExecuteStep(AStep: TWorkflowStep): TStepResult;
begin
  case AStep.StepType of
    stAction:
      Result := ExecuteAction(AStep);
    stCondition:
      Result := ExecuteCondition(AStep);
    stLoop:
      Result := ExecuteLoop(AStep);
    stParallel:
      Result := ExecuteParallel(AStep);
    stWait:
      Result := ExecuteWait(AStep);
    stSubWorkflow:
      Result := ExecuteSubWorkflow(AStep);
    stEnd:
      Result := TStepResult.OK;
  else
    Result := TStepResult.Fail(ERR_UNKNOWN_STEP_TYPE, 'Unknown step type');
  end;
end;

function TWorkflowExecutor.ExecuteAction(AStep: TWorkflowStep): TStepResult;
var
  Executor: IActionExecutor;
begin
  Result := nil;  // CODE-003: 初始�?
  try
    // 查找能处理此动作类型的执行器
    for Executor in FActionExecutors do
    begin
      if Executor.CanHandle(AStep.Action.ActionType) then
      begin
        Result := Executor.Execute(AStep.Action, FContext);
        Exit;
      end;
    end;
    
    // 默认处理
    case AStep.Action.ActionType of
      atSkill:
        Result := TStepResult.Fail(ERR_SKILL_NOT_IMPLEMENTED, 
          Format('Skill executor not registered for: %s', [AStep.Action.SkillId]));
      atLLM:
        Result := TStepResult.Fail(ERR_LLM_NOT_IMPLEMENTED, 
          'LLM executor not registered');
      atHttp:
        Result := TStepResult.Fail(ERR_HTTP_NOT_IMPLEMENTED, 
          'HTTP executor not registered');
      atScript:
        Result := TStepResult.Fail(ERR_SCRIPT_NOT_IMPLEMENTED, 
          'Script executor not registered');
    else
      Result := TStepResult.Fail(ERR_ACTION_NOT_HANDLED, 
        Format('No executor for action type: %s', [ActionTypeToStr(AStep.Action.ActionType)]));
    end;
  except
    on E: Exception do
    begin
      // CODE-003: 异常时释放已创建的结�?
      FreeAndNil(Result);
      Result := TStepResult.Fail(ERR_EXECUTION_FAILED, E.Message);
    end;
  end;
end;

function TWorkflowExecutor.ExecuteCondition(AStep: TWorkflowStep): TStepResult;
var
  Branch: TConditionBranch;
  ExprValue: string;
  SelectedBranch: TConditionBranch;
  DefaultBranch: TConditionBranch;
  SubStep: TWorkflowStep;
begin
  Result := nil;
  SelectedBranch := nil;
  DefaultBranch := nil;
  
  try  // CODE-003: 资源释放保护
    // 求值条件表达式
    ExprValue := FContext.ResolveString(AStep.Expression);
    
    // 查找匹配的分�?
    for Branch in AStep.Branches do
    begin
      if Branch.IsDefault then
      begin
        DefaultBranch := Branch;
        Continue;
      end;
      
      if EvaluateBranch(Branch, ExprValue) then
      begin
        SelectedBranch := Branch;
        Break;
      end;
    end;
    
    // 使用默认分支
    if (SelectedBranch = nil) and (DefaultBranch <> nil) then
      SelectedBranch := DefaultBranch;
    
    if SelectedBranch = nil then
      Exit(TStepResult.OK);
    
    // 执行选中分支的步�?
    FContext.PushScope(vsStep, AStep.Id + '.branch');
    try
      for SubStep in SelectedBranch.Steps do
      begin
        if FCancelled then Break;
        
        if Assigned(SubStep.Condition) then
        begin
          if not FEvaluator.Evaluate(SubStep.Condition) then
            Continue;
        end;
        
        Result := ExecuteStep(SubStep);
        
        if not Result.Success or Result.NeedsWait then
          Exit;
        
        SaveStepOutput(SubStep, Result);
        FreeAndNil(Result);  // CODE-003: 使用 FreeAndNil
      end;
    finally
      FContext.PopScope;
    end;
    
    if Result = nil then
      Result := TStepResult.OK;
  except
    on E: Exception do
    begin
      // CODE-003: 异常时释放已创建的结�?
      FreeAndNil(Result);
      Result := TStepResult.Fail(ERR_CONDITION_ERROR, E.Message);
    end;
  end;
end;

function TWorkflowExecutor.EvaluateBranch(ABranch: TConditionBranch; const AExprValue: string): Boolean;
var
  Value: TVariableValue;
begin
  Result := False;
  
  // 使用 when 值匹�?
  if Assigned(ABranch.WhenValue) then
  begin
    if ABranch.WhenValue is TJSONString then
      Result := AExprValue = TJSONString(ABranch.WhenValue).Value
    else if ABranch.WhenValue is TJSONBool then
      Result := SameText(AExprValue, BoolToStr(TJSONBool(ABranch.WhenValue).AsBoolean, True))
    else if ABranch.WhenValue is TJSONNumber then
      Result := AExprValue = ABranch.WhenValue.Value;
  end
  // 使用 match 表达�?
  else if ABranch.MatchExpr <> '' then
  begin
    Value := TVariableValue.Create(AExprValue);
    try
      Result := FEvaluator.MatchExpression(Value, ABranch.MatchExpr);
    finally
      Value.Free;
    end;
  end
  // 使用 condition 对象
  else if Assigned(ABranch.Condition) then
  begin
    Result := FEvaluator.Evaluate(ABranch.Condition);
  end;
end;

function TWorkflowExecutor.ExecuteLoop(AStep: TWorkflowStep): TStepResult;
var
  Collection: TJSONArray;
  CollectionJson: TJSONValue;
  Item: TJSONValue;
  SubStep: TWorkflowStep;
  Iteration: Integer;
  CollectedResults: TJSONArray;
begin
  Result := nil;
  CollectedResults := nil;
  
  if AStep.Output.Collect then
    CollectedResults := TJSONArray.Create;
  
  try
    case AStep.LoopConfig.Mode of
      lmForEach:
      begin
        // 解析集合
        CollectionJson := FContext.ResolveJSON(AStep.LoopConfig.Collection);
        try
          if not (CollectionJson is TJSONArray) then
            Exit(TStepResult.Fail(ERR_INVALID_COLLECTION, 'Collection must be an array'));
          
          Collection := TJSONArray(CollectionJson);
          Iteration := 0;
          
          for var I := 0 to Collection.Count - 1 do
          begin
            if FCancelled then Break;
            if Iteration >= AStep.LoopConfig.MaxIterations then Break;
            
            Item := Collection.Items[I];
            
            // 设置循环变量
            FContext.PushScope(vsStep, AStep.Id + '.loop.' + IntToStr(I));
            try
              FContext.SetVariable(AStep.LoopConfig.ItemVariable, TVariableValue.Create(Item));
              FContext.SetVariable(AStep.LoopConfig.IndexVariable, TVariableValue.Create(Int64(I)));
              
              // 执行循环�?
              for SubStep in AStep.LoopSteps do
              begin
                if FCancelled then Break;
                
                if Assigned(SubStep.Condition) then
                begin
                  if not FEvaluator.Evaluate(SubStep.Condition) then
                    Continue;
                end;
                
                Result := ExecuteStep(SubStep);
                
                if not Result.Success or Result.NeedsWait then
                  Exit;
                
                SaveStepOutput(SubStep, Result);
                
                // 收集结果
                if (CollectedResults <> nil) and (Result.Output <> nil) then
                  CollectedResults.AddElement(Result.Output.Clone as TJSONValue);
                
                Result.Free;
                Result := nil;
              end;
            finally
              FContext.PopScope;
            end;
            
            Inc(Iteration);
          end;
        finally
          CollectionJson.Free;
        end;
      end;
      
      lmWhile:
      begin
        Iteration := 0;
        
        while (Iteration < AStep.LoopConfig.MaxIterations) and not FCancelled do
        begin
          // 检查条�?
          if Assigned(AStep.LoopConfig.Condition) then
          begin
            if not FEvaluator.Evaluate(AStep.LoopConfig.Condition) then
              Break;
          end;
          
          FContext.PushScope(vsStep, AStep.Id + '.while.' + IntToStr(Iteration));
          try
            FContext.SetVariable(AStep.LoopConfig.IndexVariable, TVariableValue.Create(Int64(Iteration)));
            
            for SubStep in AStep.LoopSteps do
            begin
              if FCancelled then Break;
              
              if Assigned(SubStep.Condition) then
              begin
                if not FEvaluator.Evaluate(SubStep.Condition) then
                  Continue;
              end;
              
              Result := ExecuteStep(SubStep);
              
              if not Result.Success or Result.NeedsWait then
                Exit;
              
              SaveStepOutput(SubStep, Result);
              
              if (CollectedResults <> nil) and (Result.Output <> nil) then
                CollectedResults.AddElement(Result.Output.Clone as TJSONValue);
              
              Result.Free;
              Result := nil;
            end;
          finally
            FContext.PopScope;
          end;
          
          Inc(Iteration);
        end;
      end;
      
      lmRepeat:
      begin
        for Iteration := 0 to AStep.LoopConfig.MaxIterations - 1 do
        begin
          if FCancelled then Break;
          
          FContext.PushScope(vsStep, AStep.Id + '.repeat.' + IntToStr(Iteration));
          try
            FContext.SetVariable(AStep.LoopConfig.IndexVariable, TVariableValue.Create(Int64(Iteration)));
            
            for SubStep in AStep.LoopSteps do
            begin
              if FCancelled then Break;
              
              Result := ExecuteStep(SubStep);
              
              if not Result.Success or Result.NeedsWait then
                Exit;
              
              SaveStepOutput(SubStep, Result);
              
              if (CollectedResults <> nil) and (Result.Output <> nil) then
                CollectedResults.AddElement(Result.Output.Clone as TJSONValue);
              
              Result.Free;
              Result := nil;
            end;
          finally
            FContext.PopScope;
          end;
        end;
      end;
    end;
    
    if Result = nil then
    begin
      if CollectedResults <> nil then
        Result := TStepResult.OK(CollectedResults)
      else
        Result := TStepResult.OK;
    end;
    
  except
    CollectedResults.Free;
    raise;
  end;
end;

function TWorkflowExecutor.ExecuteParallel(AStep: TWorkflowStep): TStepResult;
var
  Branch: TConditionBranch;
  BranchResults: TArray<TStepResult>;
  Tasks: TArray<ITask>;
  BranchContexts: TArray<TWorkflowContext>;
  AllSuccess: Boolean;
  I, BranchCount: Integer;
  FailedResult: TStepResult;
  MergedOutput: TJSONObject;
  FailFast: Boolean;
  CancelFlag: Boolean;
begin
  // ARCH-004: 真正的并行执行实�?
  
  // 计算需要执行的分支�?
  BranchCount := 0;
  for Branch in AStep.ParallelBranches do
  begin
    if Assigned(Branch.Condition) then
    begin
      if not FEvaluator.Evaluate(Branch.Condition) then
        Continue;
    end;
    Inc(BranchCount);
  end;
  
  if BranchCount = 0 then
    Exit(TStepResult.OK);
  
  // 初始化数�?
  SetLength(BranchResults, BranchCount);
  SetLength(Tasks, BranchCount);
  SetLength(BranchContexts, BranchCount);
  
  FailFast := AStep.ParallelConfig.FailureStrategy = fsFailFast;
  CancelFlag := False;
  
  try
    // 为每个分支创建独立上下文和任�?
    I := 0;
    for Branch in AStep.ParallelBranches do
    begin
      if FCancelled then Break;
      
      // 检查分支条�?
      if Assigned(Branch.Condition) then
      begin
        if not FEvaluator.Evaluate(Branch.Condition) then
          Continue;
      end;
      
      // 为每个分支创建独立上下文副本
      BranchContexts[I] := FContext.Clone;
      BranchContexts[I].PushScope(vsStep, AStep.Id + '.parallel.' + Branch.Id);
      BranchResults[I] := nil;
      
      // 捕获当前索引和分�?
      var BranchIdx := I;
      var CurrentBranch := Branch;
      var BranchCtx := BranchContexts[I];
      
      // 创建并行任务
      Tasks[I] := TTask.Create(
        procedure
        var
          SubStep: TWorkflowStep;
          StepResult: TStepResult;
          Executor: IActionExecutor;
        begin
          StepResult := TStepResult.OK;
          try
            for SubStep in CurrentBranch.Steps do
            begin
              // 检查取消标�?
              if FCancelled or CancelFlag then
              begin
                FreeAndNil(StepResult);
                StepResult := TStepResult.Fail(ERR_CANCELLED, 'Execution cancelled');
                Break;
              end;
              
              FreeAndNil(StepResult);
              
              // 执行步骤 (使用分支上下�?
              case SubStep.StepType of
                stAction:
                begin
                  StepResult := nil;
                  for Executor in FActionExecutors do
                  begin
                    if Executor.CanHandle(SubStep.Action.ActionType) then
                    begin
                      StepResult := Executor.Execute(SubStep.Action, BranchCtx);
                      Break;
                    end;
                  end;
                  if StepResult = nil then
                    StepResult := TStepResult.Fail(ERR_NO_EXECUTOR, 'No executor for action');
                end;
              else
                StepResult := TStepResult.OK;  // 简�? 并行内仅支持 Action
              end;
              
              if not StepResult.Success then
              begin
                if FailFast then
                  CancelFlag := True;  // 通知其他分支停止
                Break;
              end;
            end;
          except
            on E: Exception do
            begin
              FreeAndNil(StepResult);
              StepResult := TStepResult.Fail(ERR_PARALLEL_ERROR, E.Message);
              if FailFast then
                CancelFlag := True;
            end;
          end;
          
          BranchResults[BranchIdx] := StepResult;
        end
      );
      
      Inc(I);
    end;
    
    // 启动所有任�?
    for I := 0 to BranchCount - 1 do
      if Tasks[I] <> nil then
        Tasks[I].Start;
    
    // 等待所有任务完�?
    TTask.WaitForAll(Tasks);
    
    // 合并结果
    AllSuccess := True;
    FailedResult := nil;
    
    for I := 0 to BranchCount - 1 do
    begin
      if (BranchResults[I] <> nil) and not BranchResults[I].Success then
      begin
        AllSuccess := False;
        if FailedResult = nil then
          FailedResult := BranchResults[I];
      end;
    end;
    
    if AllSuccess then
    begin
      MergedOutput := TJSONObject.Create;
      I := 0;
      for Branch in AStep.ParallelBranches do
      begin
        if I >= BranchCount then Break;
        if (BranchResults[I] <> nil) and (BranchResults[I].Output <> nil) then
          MergedOutput.AddPair(Branch.Id, BranchResults[I].Output.Clone as TJSONValue);
        Inc(I);
      end;
      Result := TStepResult.OK(MergedOutput);
    end
    else
    begin
      if FailedResult <> nil then
        Result := FailedResult.Clone
      else
        Result := TStepResult.Fail(ERR_PARALLEL_FAILED, 'Parallel execution failed');
    end;
    
  finally
    // 释放分支上下文和结果
    for I := 0 to BranchCount - 1 do
    begin
      BranchContexts[I].Free;
      BranchResults[I].Free;
    end;
  end;
end;

function TWorkflowExecutor.ExecuteWait(AStep: TWorkflowStep): TStepResult;
var
  WaitData: TJSONObject;
begin
  WaitData := TJSONObject.Create;
  WaitData.AddPair('stepId', AStep.Id);
  WaitData.AddPair('prompt', AStep.WaitConfig.Prompt);
  WaitData.AddPair('timeout', TJSONNumber.Create(AStep.WaitConfig.TimeoutMs));
  WaitData.AddPair('timeoutAction', AStep.WaitConfig.TimeoutAction);
  
  if Assigned(AStep.WaitConfig.Options) then
    WaitData.AddPair('options', TJSONArray(AStep.WaitConfig.Options.Clone));
  if Assigned(AStep.WaitConfig.InputSchema) then
    WaitData.AddPair('inputSchema', TJSONObject(AStep.WaitConfig.InputSchema.Clone));
  
  Result := TStepResult.Wait(WaitData);
  WaitData.Free;
end;

function TWorkflowExecutor.ExecuteSubWorkflow(AStep: TWorkflowStep): TStepResult;
var
  SubContext: TWorkflowContext;
  SubExecutor: TWorkflowExecutor;
  SubWorkflow: TWorkflowDefinition;
begin
  // CODE-005: 子工作流使用克隆的独立上下文，避免变量污�?
  Result := nil;
  SubContext := nil;
  SubExecutor := nil;
  
  try
    // 加载子工作流定义 (实际应该从仓库加�?
    SubWorkflow := nil;  // TODO: WorkflowRepository.Load(AStep.SubWorkflowId)
    if SubWorkflow = nil then
    begin
      Result := TStepResult.Fail(ERR_SUBWORKFLOW_NOT_FOUND, 
        Format('SubWorkflow not found: %s', [AStep.SubWorkflowId]));
      Exit;
    end;
    
    // CODE-005: 创建独立的子上下文，仅复制必要的输入变量
    SubContext := TWorkflowContext.Create(AStep.SubWorkflowId, TGUID.NewGuid.ToString);
    SubContext.CorrelationId := FContext.CorrelationId;  // 保持关联 ID
    SubContext.UserId := FContext.UserId;
    
    // 仅复制明确传递的输入参数，而非整个上下�?
    if Assigned(AStep.Action) and Assigned(AStep.Action.Params) then
    begin
      for var I := 0 to AStep.Action.Params.Count - 1 do
      begin
        var Pair := AStep.Action.Params.Pairs[I];
        var ResolvedValue := FContext.ResolveString(Pair.JsonValue.Value);
        SubContext.SetVariable(Pair.JsonString.Value, ResolvedValue);
      end;
    end;
    
    // 创建子执行器
    SubExecutor := TWorkflowExecutor.Create(SubWorkflow, SubContext);
    try
      // 注册相同的动作执行器
      for var Executor in FActionExecutors do
        SubExecutor.RegisterActionExecutor(Executor);
      
      // 执行子工作流
      Result := SubExecutor.Start;
      
      // CODE-005: 子工作流结果不会自动合并到父上下�?
      // 仅通过明确的输出配置传递结�?
    finally
      SubExecutor.Free;
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      Result := TStepResult.Fail(ERR_SUBWORKFLOW_ERROR, E.Message);
    end;
  end;
  
  // CODE-005: 子上下文在这里释放，不会污染父上下文
  SubContext.Free;
end;

function TWorkflowExecutor.HandleStepError(AStep: TWorkflowStep; AResult: TStepResult): TStepResult;
var
  Handler: TErrorHandler;
  RetryKey: string;
  CurrentRetry: Integer;
begin
  // 先检查步骤级错误处理
  Handler := FindErrorHandler(AStep, AResult.ErrorCode);
  
  // 再检查工作流级错误处�?
  if Handler = nil then
  begin
    for var WfHandler in FWorkflow.ErrorHandlers do
    begin
      if WfHandler.Matches(AResult.ErrorCode) then
      begin
        Handler := WfHandler;
        Break;
      end;
    end;
  end;
  
  if Handler = nil then
    Exit(AResult);
  
  // 处理错误
  if Handler.Action = 'retry' then
  begin
    RetryKey := AStep.Id + ':' + AResult.ErrorCode;
    if not FRetryCount.TryGetValue(RetryKey, CurrentRetry) then
      CurrentRetry := 0;
    
    if CurrentRetry < Handler.MaxTimes then
    begin
      FRetryCount.AddOrSetValue(RetryKey, CurrentRetry + 1);
      
      // 应用退避策�?
      if AStep.Action.RetryPolicy <> nil then
        ApplyRetryPolicy(AStep, AStep.Action.RetryPolicy);
      
      // 重新执行
      AResult.Free;
      Result := ExecuteStep(AStep);
      Exit;
    end;
  end
  else if Handler.Action = 'fallback' then
  begin
    if Handler.FallbackStepId <> '' then
    begin
      AResult.Free;
      Result := TStepResult.GotoStep(Handler.FallbackStepId);
      Exit;
    end;
  end
  else if Handler.Action = 'goto' then
  begin
    if Handler.GotoStepId <> '' then
    begin
      AResult.Free;
      Result := TStepResult.GotoStep(Handler.GotoStepId);
      Exit;
    end;
  end;
  
  // 返回原始错误
  Result := AResult;
end;

function TWorkflowExecutor.FindErrorHandler(AStep: TWorkflowStep; const AErrorCode: string): TErrorHandler;
begin
  Result := nil;
  
  for var Handler in AStep.OnError do
  begin
    if Handler.Matches(AErrorCode) then
    begin
      Result := Handler;
      Exit;
    end;
  end;
end;

function TWorkflowExecutor.ApplyRetryPolicy(AStep: TWorkflowStep; ARetryPolicy: TRetryPolicy): Boolean;
var
  RetryKey: string;
  CurrentRetry: Integer;
  DelayMs: Integer;
begin
  Result := True;
  
  RetryKey := AStep.Id;
  if not FRetryCount.TryGetValue(RetryKey, CurrentRetry) then
    CurrentRetry := 0;
  
  // 计算延迟
  if ARetryPolicy.BackoffType = 'exponential' then
    DelayMs := ARetryPolicy.BaseDelayMs * Trunc(Power(2, CurrentRetry))
  else if ARetryPolicy.BackoffType = 'linear' then
    DelayMs := ARetryPolicy.BaseDelayMs * (CurrentRetry + 1)
  else
    DelayMs := ARetryPolicy.BaseDelayMs;
  
  // 限制最大延�?
  if DelayMs > ARetryPolicy.MaxDelayMs then
    DelayMs := ARetryPolicy.MaxDelayMs;
  
  // 等待
  Sleep(DelayMs);
end;

procedure TWorkflowExecutor.SaveStepOutput(AStep: TWorkflowStep; AResult: TStepResult);
begin
  if AResult.Output = nil then Exit;
  
  // 保存到步骤输�?
  FContext.SetStepOutput(AStep.Id, AResult.Output);
  
  // 保存到指定变�?
  if AStep.Output.Variable <> '' then
    FContext.SetVariable(AStep.Output.Variable, TVariableValue.Create(AResult.Output));
end;

procedure TWorkflowExecutor.DoStepStart(AStep: TWorkflowStep);
begin
  if Assigned(FOnStepStart) then
    FOnStepStart(Self, AStep);
end;

procedure TWorkflowExecutor.DoStepComplete(AStep: TWorkflowStep; AResult: TStepResult);
begin
  if Assigned(FOnStepComplete) then
    FOnStepComplete(Self, AStep, AResult);
end;

function TWorkflowExecutor.GetSnapshot: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('workflowId', FWorkflow.Id);
  Result.AddPair('status', IntToStr(Ord(FStatus)));
  Result.AddPair('cursor', FCursor.ToJSON);
  Result.AddPair('context', FContext.ToJSON);
  
  // 保存重试计数
  var RetryObj := TJSONObject.Create;
  for var Pair in FRetryCount do
    RetryObj.AddPair(Pair.Key, TJSONNumber.Create(Pair.Value));
  Result.AddPair('retryCount', RetryObj);
end;

procedure TWorkflowExecutor.LoadFromSnapshot(ASnapshot: TJSONObject);
var
  StatusInt: Integer;
  CursorObj, ContextObj, RetryObj: TJSONObject;
begin
  if ASnapshot = nil then Exit;
  
  if ASnapshot.TryGetValue<Integer>('status', StatusInt) then
    FStatus := TExecutionStatus(StatusInt);
  
  if ASnapshot.TryGetValue<TJSONObject>('cursor', CursorObj) then
    FCursor.LoadFromJSON(CursorObj);
  
  if ASnapshot.TryGetValue<TJSONObject>('context', ContextObj) then
    FContext.LoadFromJSON(ContextObj);
  
  if ASnapshot.TryGetValue<TJSONObject>('retryCount', RetryObj) then
  begin
    FRetryCount.Clear;
    for var I := 0 to RetryObj.Count - 1 do
    begin
      var Pair := RetryObj.Pairs[I];
      FRetryCount.Add(Pair.JsonString.Value, TJSONNumber(Pair.JsonValue).AsInt);
    end;
  end;
end;

// ============================================================================
// TLogActionExecutor
// ============================================================================

function TLogActionExecutor.Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
var
  Message: string;
begin
  Message := AContext.ResolveString(AAction.LogMessage);
  
  // 输出日志（可扩展为实际日志系统）
  {$IFDEF DEBUG}
  Writeln(Format('[%s] %s: %s', [
    FormatDateTime('hh:nn:ss.zzz', Now),
    AAction.LogLevel,
    Message
  ]));
  {$ENDIF}
  
  Result := TStepResult.OK;
end;

function TLogActionExecutor.CanHandle(AActionType: TActionType): Boolean;
begin
  Result := AActionType = atLog;
end;

// ============================================================================
// TAssignActionExecutor
// ============================================================================

function TAssignActionExecutor.Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
var
  Pair: TPair<string, string>;
  ResolvedValue: string;
begin
  for Pair in AAction.Assignments do
  begin
    ResolvedValue := AContext.ResolveString(Pair.Value);
    AContext.SetVariable(Pair.Key, ResolvedValue);
  end;
  
  Result := TStepResult.OK;
end;

function TAssignActionExecutor.CanHandle(AActionType: TActionType): Boolean;
begin
  Result := AActionType = atAssign;
end;

// ============================================================================
// TGuardActionExecutor
// ============================================================================

function TGuardActionExecutor.Execute(AAction: TActionDefinition; AContext: TWorkflowContext): TStepResult;
begin
  if AAction.GuardType = 'input' then
    Result := ValidateInput(AContext, AAction.Rules)
  else if AAction.GuardType = 'output' then
    Result := ValidateOutput(AContext, AAction.Rules)
  else
    Result := TStepResult.OK;
end;

function TGuardActionExecutor.CanHandle(AActionType: TActionType): Boolean;
begin
  Result := AActionType = atGuard;
end;

function TGuardActionExecutor.ValidateInput(AContext: TWorkflowContext; ARules: TJSONArray): TStepResult;
var
  I: Integer;
  Rule: TJSONObject;
  Field, RuleType, Pattern: string;
  FieldValue: TVariableValue;
  MinLen, MaxLen: Integer;
begin
  if ARules = nil then
    Exit(TStepResult.OK);
  
  for I := 0 to ARules.Count - 1 do
  begin
    if not (ARules.Items[I] is TJSONObject) then Continue;
    
    Rule := TJSONObject(ARules.Items[I]);
    if not Rule.TryGetValue<string>('field', Field) then Continue;
    
    FieldValue := AContext.GetVariable('input.' + Field);
    try
      // 必填检�?
      if Rule.TryGetValue<string>('type', RuleType) then
      begin
        if RuleType = 'required' then
        begin
          if FieldValue.IsNull or FieldValue.IsEmpty then
            Exit(TStepResult.Fail(ERR_GUARD_REQUIRED, Format('Field %s is required', [Field])));
        end;
      end;
      
      // 长度检�?
      if Rule.TryGetValue<Integer>('minLength', MinLen) then
      begin
        if Length(FieldValue.AsString) < MinLen then
          Exit(TStepResult.Fail(ERR_GUARD_MIN_LENGTH, 
            Format('Field %s must be at least %d characters', [Field, MinLen])));
      end;
      
      if Rule.TryGetValue<Integer>('maxLength', MaxLen) then
      begin
        if Length(FieldValue.AsString) > MaxLen then
          Exit(TStepResult.Fail(ERR_GUARD_MAX_LENGTH, 
            Format('Field %s must be at most %d characters', [Field, MaxLen])));
      end;
      
      // 正则匹配
      if Rule.TryGetValue<string>('pattern', Pattern) then
      begin
        if not TRegEx.IsMatch(FieldValue.AsString, Pattern) then
          Exit(TStepResult.Fail(ERR_GUARD_PATTERN, 
            Format('Field %s does not match pattern', [Field])));
      end;
    finally
      FieldValue.Free;
    end;
  end;
  
  Result := TStepResult.OK;
end;

function TGuardActionExecutor.ValidateOutput(AContext: TWorkflowContext; ARules: TJSONArray): TStepResult;
begin
  // TODO: 实现输出验证
  Result := TStepResult.OK;
end;

end.
