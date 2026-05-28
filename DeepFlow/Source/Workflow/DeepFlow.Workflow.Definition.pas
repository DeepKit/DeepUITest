unit UniFlow.Workflow.Definition;
{
  UniFlow Workflow Definition
  ===========================
  工作流定义数据结构，支持 JSON 配置解析�?
  
  核心概念:
  - Workflow: 工作流定义，包含步骤序列
  - Step: 执行单元，支持多种类型（action/condition/loop/parallel�?
  - Action: 具体动作（skill/llm/guard/log/assign/http/script�?
  
  参�? 05.03.API-UniFlow-Workflow定义规范-v1.0.md
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.RegularExpressions;

type
  // ============================================================================
  // 基础类型定义
  // ============================================================================
  
  /// <summary>步骤类型</summary>
  TStepType = (
    stAction,       // 执行动作
    stCondition,    // 条件分支
    stLoop,         // 循环
    stParallel,     // 并行执行
    stSubWorkflow,  // 子工作流
    stWait,         // 等待（人�?事件�?
    stEnd           // 结束
  );
  
  /// <summary>动作类型</summary>
  TActionType = (
    atSkill,        // 调用 Skill
    atLLM,          // 调用 LLM (AgentTask)
    atGuard,        // 调用 Guard 验证
    atLog,          // 日志记录
    atAssign,       // 变量赋�?
    atHttp,         // HTTP 调用
    atScript        // 脚本执行
  );
  
  /// <summary>循环模式</summary>
  TLoopMode = (
    lmForEach,      // 遍历集合
    lmWhile,        // 条件循环
    lmRepeat        // 重复 N �?
  );
  
  /// <summary>等待策略（并行）</summary>
  TWaitStrategy = (
    wsAll,          // 等待全部完成
    wsAny,          // 任一完成即可
    wsN             // 等待 N 个完�?
  );
  
  /// <summary>失败策略</summary>
  TFailureStrategy = (
    fsFailFast,     // 快速失�?
    fsContinue,     // 继续执行
    fsRollback      // 回滚
  );
  
  /// <summary>条件操作�?/summary>
  TConditionOperator = (
    coEq,           // 等于
    coNe,           // 不等�?
    coGt,           // 大于
    coLt,           // 小于
    coGe,           // 大于等于
    coLe,           // 小于等于
    coContains,     // 包含
    coStartsWith,   // �?..开�?
    coEndsWith,     // �?..结尾
    coMatches,      // 正则匹配
    coIsEmpty,      // 为空
    coIsNotEmpty,   // 不为�?
    coIn,           // 在列表中
    coAnd,          // 逻辑�?
    coOr,           // 逻辑�?
    coNot           // 逻辑�?
  );
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
  function StepTypeToStr(AType: TStepType): string;
  function StrToStepType(const S: string): TStepType;
  function ActionTypeToStr(AType: TActionType): string;
  function StrToActionType(const S: string): TActionType;
  function LoopModeToStr(AMode: TLoopMode): string;
  function StrToLoopMode(const S: string): TLoopMode;
  function ConditionOperatorToStr(AOp: TConditionOperator): string;
  function StrToConditionOperator(const S: string): TConditionOperator;

type
  // ============================================================================
  // 前向声明
  // ============================================================================
  
  TConditionExpression = class;
  TActionDefinition = class;
  TWorkflowStep = class;
  TConditionBranch = class;
  TWorkflowDefinition = class;
  
  // ============================================================================
  // 重试策略
  // ============================================================================
  
  TRetryPolicy = class
  private
    FMaxRetries: Integer;
    FBackoffType: string;       // 'fixed' | 'linear' | 'exponential'
    FBaseDelayMs: Integer;
    FMaxDelayMs: Integer;
    FRetryableErrors: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TRetryPolicy;
    
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;
    property BackoffType: string read FBackoffType write FBackoffType;
    property BaseDelayMs: Integer read FBaseDelayMs write FBaseDelayMs;
    property MaxDelayMs: Integer read FMaxDelayMs write FMaxDelayMs;
    property RetryableErrors: TList<string> read FRetryableErrors;
  end;
  
  // ============================================================================
  // 条件表达�?
  // ============================================================================
  
  TConditionExpression = class
  private
    FOperator: TConditionOperator;
    FLeftExpr: string;           // 左操作数表达�?(�?"{{ vars.status }}")
    FRightExpr: string;          // 右操作数表达�?
    FSubConditions: TObjectList<TConditionExpression>;  // 用于 And/Or/Not
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONValue);
    function ToJSON: TJSONValue;
    function Clone: TConditionExpression;
    
    /// <summary>从简单表达式解析 (�?"vars.count > 10")</summary>
    class function ParseSimple(const AExpr: string): TConditionExpression;
    
    property Operator: TConditionOperator read FOperator write FOperator;
    property LeftExpr: string read FLeftExpr write FLeftExpr;
    property RightExpr: string read FRightExpr write FRightExpr;
    property SubConditions: TObjectList<TConditionExpression> read FSubConditions;
  end;
  
  // ============================================================================
  // 输出配置
  // ============================================================================
  
  TOutputConfig = class
  private
    FVariable: string;           // 存储到的变量�?
    FTransform: string;          // 转换表达�?
    FCollect: Boolean;           // 是否收集（用于循环）
    FMerge: string;              // 合并方式 ('object' | 'array')
  public
    constructor Create;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TOutputConfig;
    
    property Variable: string read FVariable write FVariable;
    property Transform: string read FTransform write FTransform;
    property Collect: Boolean read FCollect write FCollect;
    property Merge: string read FMerge write FMerge;
  end;
  
  // ============================================================================
  // 动作定义
  // ============================================================================
  
  TActionDefinition = class
  private
    FActionType: TActionType;
    FSkillId: string;            // Skill ID (atSkill)
    FParams: TJSONObject;        // 参数（支持表达式�?
    FTimeoutMs: Integer;
    FRetryPolicy: TRetryPolicy;
    FOutput: TOutputConfig;
    
    // LLM 特有
    FLLMAction: string;          // 'understand' | 'generate' | 'diagnose'
    FLLMModel: string;
    FTemperature: Double;
    FMaxTokens: Integer;
    
    // Guard 特有
    FGuardType: string;          // 'input' | 'output' | 'security'
    FRules: TJSONArray;
    
    // HTTP 特有
    FHttpMethod: string;
    FHttpUrl: string;
    FHttpHeaders: TJSONObject;
    FHttpBody: string;
    
    // Script 特有
    FScriptLang: string;
    FScriptCode: string;
    
    // Assign 特有
    FAssignments: TDictionary<string, string>;  // varName -> expression
    
    // Log 特有
    FLogLevel: string;
    FLogMessage: string;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TActionDefinition;
    
    property ActionType: TActionType read FActionType write FActionType;
    property SkillId: string read FSkillId write FSkillId;
    property Params: TJSONObject read FParams write FParams;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property RetryPolicy: TRetryPolicy read FRetryPolicy;
    property Output: TOutputConfig read FOutput;
    
    // LLM
    property LLMAction: string read FLLMAction write FLLMAction;
    property LLMModel: string read FLLMModel write FLLMModel;
    property Temperature: Double read FTemperature write FTemperature;
    property MaxTokens: Integer read FMaxTokens write FMaxTokens;
    
    // Guard
    property GuardType: string read FGuardType write FGuardType;
    property Rules: TJSONArray read FRules write FRules;
    
    // HTTP
    property HttpMethod: string read FHttpMethod write FHttpMethod;
    property HttpUrl: string read FHttpUrl write FHttpUrl;
    property HttpHeaders: TJSONObject read FHttpHeaders write FHttpHeaders;
    property HttpBody: string read FHttpBody write FHttpBody;
    
    // Script
    property ScriptLang: string read FScriptLang write FScriptLang;
    property ScriptCode: string read FScriptCode write FScriptCode;
    
    // Assign
    property Assignments: TDictionary<string, string> read FAssignments;
    
    // Log
    property LogLevel: string read FLogLevel write FLogLevel;
    property LogMessage: string read FLogMessage write FLogMessage;
  end;
  
  // ============================================================================
  // 条件分支
  // ============================================================================
  
  TConditionBranch = class
  private
    FId: string;
    FWhenValue: TJSONValue;      // 匹配�?
    FMatchExpr: string;          // 匹配表达式（�?">= 0.9"�?
    FIsDefault: Boolean;
    FCondition: TConditionExpression;
    FSteps: TObjectList<TWorkflowStep>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TConditionBranch;
    
    property Id: string read FId write FId;
    property WhenValue: TJSONValue read FWhenValue write FWhenValue;
    property MatchExpr: string read FMatchExpr write FMatchExpr;
    property IsDefault: Boolean read FIsDefault write FIsDefault;
    property Condition: TConditionExpression read FCondition write FCondition;
    property Steps: TObjectList<TWorkflowStep> read FSteps;
  end;
  
  // ============================================================================
  // 循环配置
  // ============================================================================
  
  TLoopConfig = class
  private
    FMode: TLoopMode;
    FCollection: string;         // 集合表达�?(forEach)
    FItemVariable: string;       // 当前项变量名
    FIndexVariable: string;      // 索引变量�?
    FCondition: TConditionExpression;  // while 条件
    FMaxIterations: Integer;
    FParallelism: Integer;       // 并行度（0 = 串行�?
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TLoopConfig;
    
    property Mode: TLoopMode read FMode write FMode;
    property Collection: string read FCollection write FCollection;
    property ItemVariable: string read FItemVariable write FItemVariable;
    property IndexVariable: string read FIndexVariable write FIndexVariable;
    property Condition: TConditionExpression read FCondition write FCondition;
    property MaxIterations: Integer read FMaxIterations write FMaxIterations;
    property Parallelism: Integer read FParallelism write FParallelism;
  end;
  
  // ============================================================================
  // 并行配置
  // ============================================================================
  
  TParallelConfig = class
  private
    FWaitStrategy: TWaitStrategy;
    FWaitCount: Integer;         // �?wsN 时使�?
    FFailureStrategy: TFailureStrategy;
  public
    constructor Create;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TParallelConfig;
    
    property WaitStrategy: TWaitStrategy read FWaitStrategy write FWaitStrategy;
    property WaitCount: Integer read FWaitCount write FWaitCount;
    property FailureStrategy: TFailureStrategy read FFailureStrategy write FFailureStrategy;
  end;
  
  // ============================================================================
  // 等待配置
  // ============================================================================
  
  TWaitConfig = class
  private
    FPrompt: string;             // 提示信息
    FOptions: TJSONArray;        // 选项列表
    FInputSchema: TJSONObject;   // 自由输入 Schema
    FTimeoutMs: Integer;
    FTimeoutAction: string;      // 'cancel' | 'skip' | 'default'
    FDefaultValue: TJSONValue;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TWaitConfig;
    
    property Prompt: string read FPrompt write FPrompt;
    property Options: TJSONArray read FOptions write FOptions;
    property InputSchema: TJSONObject read FInputSchema write FInputSchema;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property TimeoutAction: string read FTimeoutAction write FTimeoutAction;
    property DefaultValue: TJSONValue read FDefaultValue write FDefaultValue;
  end;
  
  // ============================================================================
  // 错误处理
  // ============================================================================
  
  TErrorHandler = class
  private
    FMatchPattern: string;       // 错误码匹配模式（支持 *�?
    FAction: string;             // 'retry' | 'fallback' | 'fail' | 'goto' | 'circuitBreak'
    FFallbackStepId: string;
    FGotoStepId: string;
    FMaxTimes: Integer;
    FCooldownMs: Integer;
    FMessage: string;
  public
    constructor Create;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TErrorHandler;
    
    /// <summary>检查错误码是否匹配</summary>
    function Matches(const AErrorCode: string): Boolean;
    
    property MatchPattern: string read FMatchPattern write FMatchPattern;
    property Action: string read FAction write FAction;
    property FallbackStepId: string read FFallbackStepId write FFallbackStepId;
    property GotoStepId: string read FGotoStepId write FGotoStepId;
    property MaxTimes: Integer read FMaxTimes write FMaxTimes;
    property CooldownMs: Integer read FCooldownMs write FCooldownMs;
    property Message: string read FMessage write FMessage;
  end;
  
  // ============================================================================
  // 工作流步�?
  // ============================================================================
  
  TWorkflowStep = class
  private
    FId: string;
    FName: string;
    FStepType: TStepType;
    FDescription: string;
    FCondition: TConditionExpression;  // 执行条件
    
    // Action 步骤
    FAction: TActionDefinition;
    
    // Condition 步骤
    FExpression: string;         // 条件表达�?
    FBranches: TObjectList<TConditionBranch>;
    
    // Loop 步骤
    FLoopConfig: TLoopConfig;
    FLoopSteps: TObjectList<TWorkflowStep>;
    
    // Parallel 步骤
    FParallelConfig: TParallelConfig;
    FParallelBranches: TObjectList<TConditionBranch>;  // 复用 Branch 结构
    
    // SubWorkflow 步骤
    FSubWorkflowId: string;
    FSubWorkflowInput: TJSONObject;
    FInheritContext: Boolean;
    FAsync: Boolean;
    
    // Wait 步骤
    FWaitConfig: TWaitConfig;
    
    // 错误处理
    FOnError: TObjectList<TErrorHandler>;
    FOutput: TOutputConfig;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TWorkflowStep;
    
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property StepType: TStepType read FStepType write FStepType;
    property Description: string read FDescription write FDescription;
    property Condition: TConditionExpression read FCondition write FCondition;
    
    // Action
    property Action: TActionDefinition read FAction;
    
    // Condition
    property Expression: string read FExpression write FExpression;
    property Branches: TObjectList<TConditionBranch> read FBranches;
    
    // Loop
    property LoopConfig: TLoopConfig read FLoopConfig;
    property LoopSteps: TObjectList<TWorkflowStep> read FLoopSteps;
    
    // Parallel
    property ParallelConfig: TParallelConfig read FParallelConfig;
    property ParallelBranches: TObjectList<TConditionBranch> read FParallelBranches;
    
    // SubWorkflow
    property SubWorkflowId: string read FSubWorkflowId write FSubWorkflowId;
    property SubWorkflowInput: TJSONObject read FSubWorkflowInput write FSubWorkflowInput;
    property InheritContext: Boolean read FInheritContext write FInheritContext;
    property Async: Boolean read FAsync write FAsync;
    
    // Wait
    property WaitConfig: TWaitConfig read FWaitConfig;
    
    // Error & Output
    property OnError: TObjectList<TErrorHandler> read FOnError;
    property Output: TOutputConfig read FOutput;
  end;
  
  // ============================================================================
  // 生命周期钩子
  // ============================================================================
  
  TWorkflowHook = class
  private
    FHookType: string;           // 'log' | 'metric' | 'notify' | 'alert' | 'webhook'
    FCondition: string;          // 执行条件
    FConfig: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TWorkflowHook;
    
    property HookType: string read FHookType write FHookType;
    property Condition: string read FCondition write FCondition;
    property Config: TJSONObject read FConfig write FConfig;
  end;
  
  TWorkflowHooks = class
  private
    FOnStart: TObjectList<TWorkflowHook>;
    FOnComplete: TObjectList<TWorkflowHook>;
    FOnError: TObjectList<TWorkflowHook>;
    FOnStepStart: TObjectList<TWorkflowHook>;
    FOnStepComplete: TObjectList<TWorkflowHook>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TWorkflowHooks;
    
    property OnStart: TObjectList<TWorkflowHook> read FOnStart;
    property OnComplete: TObjectList<TWorkflowHook> read FOnComplete;
    property OnError: TObjectList<TWorkflowHook> read FOnError;
    property OnStepStart: TObjectList<TWorkflowHook> read FOnStepStart;
    property OnStepComplete: TObjectList<TWorkflowHook> read FOnStepComplete;
  end;
  
  // ============================================================================
  // 触发器配�?
  // ============================================================================
  
  TTriggerConfig = class
  private
    FTriggerType: string;        // 'api' | 'schedule' | 'event'
    FEndpoint: string;           // API 端点
    FCron: string;               // Cron 表达�?
    FEventName: string;          // 事件�?
    FConfig: TJSONObject;        // 其他配置
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure LoadFromJSON(AJson: TJSONObject);
    function ToJSON: TJSONObject;
    function Clone: TTriggerConfig;
    
    property TriggerType: string read FTriggerType write FTriggerType;
    property Endpoint: string read FEndpoint write FEndpoint;
    property Cron: string read FCron write FCron;
    property EventName: string read FEventName write FEventName;
    property Config: TJSONObject read FConfig write FConfig;
  end;
  
  // ============================================================================
  // 工作流定�?
  // ============================================================================
  
  TWorkflowDefinition = class
  private
    FId: string;
    FName: string;
    FVersion: string;
    FDescription: string;
    
    FTrigger: TTriggerConfig;
    FInputSchema: TJSONObject;
    FOutputSchema: TJSONObject;
    FVariables: TJSONObject;     // 全局变量
    
    FSteps: TObjectList<TWorkflowStep>;
    FErrorHandlers: TObjectList<TErrorHandler>;
    FHooks: TWorkflowHooks;
    
    FMetadata: TJSONObject;      // owner, tags, timeout, etc.
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>�?JSON 对象加载</summary>
    procedure LoadFromJSON(AJson: TJSONObject);
    
    /// <summary>�?JSON 字符串加�?/summary>
    procedure LoadFromString(const AJsonStr: string);
    
    /// <summary>从文件加�?/summary>
    procedure LoadFromFile(const AFilePath: string);
    
    /// <summary>导出�?JSON 对象</summary>
    function ToJSON: TJSONObject;
    
    /// <summary>导出�?JSON 字符�?/summary>
    function ToJSONString(APretty: Boolean = True): string;
    
    /// <summary>保存到文�?/summary>
    procedure SaveToFile(const AFilePath: string; APretty: Boolean = True);
    
    /// <summary>验证定义有效�?/summary>
    function Validate(out AErrors: TArray<string>): Boolean;
    
    /// <summary>根据 ID 查找步骤</summary>
    function FindStepById(const AStepId: string): TWorkflowStep;
    
    /// <summary>克隆</summary>
    function Clone: TWorkflowDefinition;
    
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Version: string read FVersion write FVersion;
    property Description: string read FDescription write FDescription;
    
    property Trigger: TTriggerConfig read FTrigger;
    property InputSchema: TJSONObject read FInputSchema write FInputSchema;
    property OutputSchema: TJSONObject read FOutputSchema write FOutputSchema;
    property Variables: TJSONObject read FVariables write FVariables;
    
    property Steps: TObjectList<TWorkflowStep> read FSteps;
    property ErrorHandlers: TObjectList<TErrorHandler> read FErrorHandlers;
    property Hooks: TWorkflowHooks read FHooks;
    
    property Metadata: TJSONObject read FMetadata write FMetadata;
  end;

implementation

// ============================================================================
// 辅助函数实现
// ============================================================================

function StepTypeToStr(AType: TStepType): string;
begin
  case AType of
    stAction:      Result := 'action';
    stCondition:   Result := 'condition';
    stLoop:        Result := 'loop';
    stParallel:    Result := 'parallel';
    stSubWorkflow: Result := 'subworkflow';
    stWait:        Result := 'wait';
    stEnd:         Result := 'end';
  else
    Result := 'unknown';
  end;
end;

function StrToStepType(const S: string): TStepType;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if LowerS = 'action' then Result := stAction
  else if LowerS = 'condition' then Result := stCondition
  else if LowerS = 'loop' then Result := stLoop
  else if LowerS = 'parallel' then Result := stParallel
  else if (LowerS = 'subworkflow') or (LowerS = 'sub_workflow') then Result := stSubWorkflow
  else if (LowerS = 'wait') or (LowerS = 'humantask') then Result := stWait
  else if LowerS = 'end' then Result := stEnd
  // 兼容规范中的类型�?
  else if LowerS = 'skilltask' then Result := stAction
  else if LowerS = 'agenttask' then Result := stAction
  else
    Result := stAction;  // 默认
end;

function ActionTypeToStr(AType: TActionType): string;
begin
  case AType of
    atSkill:  Result := 'skill';
    atLLM:    Result := 'llm';
    atGuard:  Result := 'guard';
    atLog:    Result := 'log';
    atAssign: Result := 'assign';
    atHttp:   Result := 'http';
    atScript: Result := 'script';
  else
    Result := 'unknown';
  end;
end;

function StrToActionType(const S: string): TActionType;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if LowerS = 'skill' then Result := atSkill
  else if (LowerS = 'llm') or (LowerS = 'agent') then Result := atLLM
  else if LowerS = 'guard' then Result := atGuard
  else if LowerS = 'log' then Result := atLog
  else if LowerS = 'assign' then Result := atAssign
  else if LowerS = 'http' then Result := atHttp
  else if LowerS = 'script' then Result := atScript
  else
    Result := atSkill;  // 默认
end;

function LoopModeToStr(AMode: TLoopMode): string;
begin
  case AMode of
    lmForEach: Result := 'forEach';
    lmWhile:   Result := 'while';
    lmRepeat:  Result := 'repeat';
  else
    Result := 'forEach';
  end;
end;

function StrToLoopMode(const S: string): TLoopMode;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if (LowerS = 'foreach') or (LowerS = 'for_each') then Result := lmForEach
  else if LowerS = 'while' then Result := lmWhile
  else if LowerS = 'repeat' then Result := lmRepeat
  else
    Result := lmForEach;
end;

function ConditionOperatorToStr(AOp: TConditionOperator): string;
begin
  case AOp of
    coEq:         Result := 'eq';
    coNe:         Result := 'ne';
    coGt:         Result := 'gt';
    coLt:         Result := 'lt';
    coGe:         Result := 'ge';
    coLe:         Result := 'le';
    coContains:   Result := 'contains';
    coStartsWith: Result := 'startsWith';
    coEndsWith:   Result := 'endsWith';
    coMatches:    Result := 'matches';
    coIsEmpty:    Result := 'isEmpty';
    coIsNotEmpty: Result := 'isNotEmpty';
    coIn:         Result := 'in';
    coAnd:        Result := 'and';
    coOr:         Result := 'or';
    coNot:        Result := 'not';
  else
    Result := 'eq';
  end;
end;

function StrToConditionOperator(const S: string): TConditionOperator;
var
  LowerS: string;
begin
  LowerS := LowerCase(S);
  if (LowerS = 'eq') or (LowerS = '==') or (LowerS = '=') then Result := coEq
  else if (LowerS = 'ne') or (LowerS = '!=') or (LowerS = '<>') then Result := coNe
  else if (LowerS = 'gt') or (LowerS = '>') then Result := coGt
  else if (LowerS = 'lt') or (LowerS = '<') then Result := coLt
  else if (LowerS = 'ge') or (LowerS = '>=') then Result := coGe
  else if (LowerS = 'le') or (LowerS = '<=') then Result := coLe
  else if LowerS = 'contains' then Result := coContains
  else if (LowerS = 'startswith') or (LowerS = 'starts_with') then Result := coStartsWith
  else if (LowerS = 'endswith') or (LowerS = 'ends_with') then Result := coEndsWith
  else if LowerS = 'matches' then Result := coMatches
  else if (LowerS = 'isempty') or (LowerS = 'is_empty') then Result := coIsEmpty
  else if (LowerS = 'isnotempty') or (LowerS = 'is_not_empty') then Result := coIsNotEmpty
  else if LowerS = 'in' then Result := coIn
  else if (LowerS = 'and') or (LowerS = '&&') then Result := coAnd
  else if (LowerS = 'or') or (LowerS = '||') then Result := coOr
  else if (LowerS = 'not') or (LowerS = '!') then Result := coNot
  else
    Result := coEq;
end;

// ============================================================================
// TRetryPolicy
// ============================================================================

constructor TRetryPolicy.Create;
begin
  inherited Create;
  FMaxRetries := 3;
  FBackoffType := 'exponential';
  FBaseDelayMs := 1000;
  FMaxDelayMs := 30000;
  FRetryableErrors := TList<string>.Create;
end;

destructor TRetryPolicy.Destroy;
begin
  FRetryableErrors.Free;
  inherited;
end;

procedure TRetryPolicy.LoadFromJSON(AJson: TJSONObject);
var
  Arr: TJSONArray;
  I: Integer;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<Integer>('maxRetries', FMaxRetries) then;
  if AJson.TryGetValue<string>('backoff', FBackoffType) then;
  if AJson.TryGetValue<Integer>('baseMs', FBaseDelayMs) then;
  if AJson.TryGetValue<Integer>('maxBackoffMs', FMaxDelayMs) then;
  
  if AJson.TryGetValue<TJSONArray>('retryableErrors', Arr) then
  begin
    FRetryableErrors.Clear;
    for I := 0 to Arr.Count - 1 do
      FRetryableErrors.Add(Arr.Items[I].Value);
  end;
end;

function TRetryPolicy.ToJSON: TJSONObject;
var
  Arr: TJSONArray;
  S: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('maxRetries', TJSONNumber.Create(FMaxRetries));
  Result.AddPair('backoff', FBackoffType);
  Result.AddPair('baseMs', TJSONNumber.Create(FBaseDelayMs));
  Result.AddPair('maxBackoffMs', TJSONNumber.Create(FMaxDelayMs));
  
  if FRetryableErrors.Count > 0 then
  begin
    Arr := TJSONArray.Create;
    for S in FRetryableErrors do
      Arr.Add(S);
    Result.AddPair('retryableErrors', Arr);
  end;
end;

function TRetryPolicy.Clone: TRetryPolicy;
var
  S: string;
begin
  Result := TRetryPolicy.Create;
  Result.FMaxRetries := FMaxRetries;
  Result.FBackoffType := FBackoffType;
  Result.FBaseDelayMs := FBaseDelayMs;
  Result.FMaxDelayMs := FMaxDelayMs;
  for S in FRetryableErrors do
    Result.FRetryableErrors.Add(S);
end;

// ============================================================================
// TConditionExpression
// ============================================================================

constructor TConditionExpression.Create;
begin
  inherited Create;
  FOperator := coEq;
  FSubConditions := TObjectList<TConditionExpression>.Create(True);
end;

destructor TConditionExpression.Destroy;
begin
  FSubConditions.Free;
  inherited;
end;

procedure TConditionExpression.LoadFromJSON(AJson: TJSONValue);
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  OpStr: string;
  SubCond: TConditionExpression;
begin
  if AJson is TJSONString then
  begin
    // 简单字符串表达�?
    FLeftExpr := AJson.Value;
    FOperator := coEq;
    FRightExpr := 'true';
  end
  else if AJson is TJSONObject then
  begin
    Obj := TJSONObject(AJson);
    
    if Obj.TryGetValue<string>('op', OpStr) then
      FOperator := StrToConditionOperator(OpStr);
    if Obj.TryGetValue<string>('left', FLeftExpr) then;
    if Obj.TryGetValue<string>('right', FRightExpr) then;
    
    if Obj.TryGetValue<TJSONArray>('conditions', Arr) then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        SubCond := TConditionExpression.Create;
        SubCond.LoadFromJSON(Arr.Items[I]);
        FSubConditions.Add(SubCond);
      end;
    end;
  end;
end;

function TConditionExpression.ToJSON: TJSONValue;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  SubCond: TConditionExpression;
begin
  if (FSubConditions.Count = 0) and (FRightExpr = 'true') then
  begin
    Result := TJSONString.Create(FLeftExpr);
  end
  else
  begin
    Obj := TJSONObject.Create;
    Obj.AddPair('op', ConditionOperatorToStr(FOperator));
    
    if FLeftExpr <> '' then
      Obj.AddPair('left', FLeftExpr);
    if FRightExpr <> '' then
      Obj.AddPair('right', FRightExpr);
    
    if FSubConditions.Count > 0 then
    begin
      Arr := TJSONArray.Create;
      for SubCond in FSubConditions do
        Arr.AddElement(SubCond.ToJSON);
      Obj.AddPair('conditions', Arr);
    end;
    
    Result := Obj;
  end;
end;

function TConditionExpression.Clone: TConditionExpression;
var
  SubCond: TConditionExpression;
begin
  Result := TConditionExpression.Create;
  Result.FOperator := FOperator;
  Result.FLeftExpr := FLeftExpr;
  Result.FRightExpr := FRightExpr;
  for SubCond in FSubConditions do
    Result.FSubConditions.Add(SubCond.Clone);
end;

class function TConditionExpression.ParseSimple(const AExpr: string): TConditionExpression;
var
  Match: TMatch;
begin
  Result := TConditionExpression.Create;
  
  // 尝试解析简单表达式�?"vars.count > 10"
  Match := TRegEx.Match(AExpr, '^\s*(.+?)\s*(==|!=|>=|<=|>|<|contains|startsWith|endsWith)\s*(.+?)\s*$');
  if Match.Success then
  begin
    Result.FLeftExpr := Match.Groups[1].Value;
    Result.FOperator := StrToConditionOperator(Match.Groups[2].Value);
    Result.FRightExpr := Match.Groups[3].Value;
  end
  else
  begin
    // 作为布尔表达�?
    Result.FLeftExpr := AExpr;
    Result.FOperator := coEq;
    Result.FRightExpr := 'true';
  end;
end;

// ============================================================================
// TOutputConfig
// ============================================================================

constructor TOutputConfig.Create;
begin
  inherited Create;
  FCollect := False;
  FMerge := 'object';
end;

procedure TOutputConfig.LoadFromJSON(AJson: TJSONObject);
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('variable', FVariable) then;
  if AJson.TryGetValue<string>('transform', FTransform) then;
  if AJson.TryGetValue<Boolean>('collect', FCollect) then;
  if AJson.TryGetValue<string>('merge', FMerge) then;
end;

function TOutputConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if FVariable <> '' then
    Result.AddPair('variable', FVariable);
  if FTransform <> '' then
    Result.AddPair('transform', FTransform);
  if FCollect then
    Result.AddPair('collect', TJSONBool.Create(True));
  if FMerge <> 'object' then
    Result.AddPair('merge', FMerge);
end;

function TOutputConfig.Clone: TOutputConfig;
begin
  Result := TOutputConfig.Create;
  Result.FVariable := FVariable;
  Result.FTransform := FTransform;
  Result.FCollect := FCollect;
  Result.FMerge := FMerge;
end;

// ============================================================================
// TActionDefinition
// ============================================================================

constructor TActionDefinition.Create;
begin
  inherited Create;
  FActionType := atSkill;
  FTimeoutMs := 30000;
  FTemperature := 0.7;
  FMaxTokens := 1000;
  FRetryPolicy := TRetryPolicy.Create;
  FOutput := TOutputConfig.Create;
  FAssignments := TDictionary<string, string>.Create;
end;

destructor TActionDefinition.Destroy;
begin
  FParams.Free;
  FRules.Free;
  FHttpHeaders.Free;
  FRetryPolicy.Free;
  FOutput.Free;
  FAssignments.Free;
  inherited;
end;

procedure TActionDefinition.LoadFromJSON(AJson: TJSONObject);
var
  ActionStr: string;
  AssignObj: TJSONObject;
  Pair: TJSONPair;
  OutputObj: TJSONObject;
  RetryObj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  // 确定动作类型
  if AJson.TryGetValue<string>('type', ActionStr) then
    FActionType := StrToActionType(ActionStr)
  else if AJson.TryGetValue<string>('action', ActionStr) then
  begin
    // 兼容 AgentTask �?action 字段
    if (ActionStr = 'understand') or (ActionStr = 'generate') or (ActionStr = 'diagnose') then
    begin
      FActionType := atLLM;
      FLLMAction := ActionStr;
    end;
  end;
  
  // 通用字段
  if AJson.TryGetValue<string>('skill', FSkillId) then;
  if AJson.TryGetValue<Integer>('timeout', FTimeoutMs) then;
  
  // 参数
  if AJson.TryGetValue<TJSONObject>('params', FParams) then
    FParams := TJSONObject(FParams.Clone)
  else
    FParams := nil;
  
  // 重试策略
  if AJson.TryGetValue<TJSONObject>('retryPolicy', RetryObj) then
    FRetryPolicy.LoadFromJSON(RetryObj);
  
  // 输出配置
  if AJson.TryGetValue<TJSONObject>('output', OutputObj) then
    FOutput.LoadFromJSON(OutputObj);
  
  // LLM 特有
  if AJson.TryGetValue<string>('action', FLLMAction) then;
  if AJson.TryGetValue<string>('model', FLLMModel) then;
  if AJson.TryGetValue<Double>('temperature', FTemperature) then;
  if AJson.TryGetValue<Integer>('maxTokens', FMaxTokens) then;
  
  // Guard 特有
  if AJson.TryGetValue<string>('guardType', FGuardType) then;
  if AJson.TryGetValue<TJSONArray>('rules', FRules) then
    FRules := TJSONArray(FRules.Clone);
  
  // HTTP 特有
  if AJson.TryGetValue<string>('method', FHttpMethod) then;
  if AJson.TryGetValue<string>('url', FHttpUrl) then;
  if AJson.TryGetValue<TJSONObject>('headers', FHttpHeaders) then
    FHttpHeaders := TJSONObject(FHttpHeaders.Clone);
  if AJson.TryGetValue<string>('body', FHttpBody) then;
  
  // Script 特有
  if AJson.TryGetValue<string>('lang', FScriptLang) then;
  if AJson.TryGetValue<string>('code', FScriptCode) then;
  
  // Assign 特有
  if AJson.TryGetValue<TJSONObject>('assignments', AssignObj) then
  begin
    FAssignments.Clear;
    for Pair in AssignObj do
      FAssignments.Add(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;
  
  // Log 特有
  if AJson.TryGetValue<string>('level', FLogLevel) then;
  if AJson.TryGetValue<string>('message', FLogMessage) then;
end;

function TActionDefinition.ToJSON: TJSONObject;
var
  AssignObj: TJSONObject;
  Pair: TPair<string, string>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', ActionTypeToStr(FActionType));
  
  if FSkillId <> '' then
    Result.AddPair('skill', FSkillId);
  if FTimeoutMs <> 30000 then
    Result.AddPair('timeout', TJSONNumber.Create(FTimeoutMs));
  if Assigned(FParams) then
    Result.AddPair('params', TJSONObject(FParams.Clone));
  
  Result.AddPair('retryPolicy', FRetryPolicy.ToJSON);
  Result.AddPair('output', FOutput.ToJSON);
  
  // LLM
  if FActionType = atLLM then
  begin
    if FLLMAction <> '' then
      Result.AddPair('action', FLLMAction);
    if FLLMModel <> '' then
      Result.AddPair('model', FLLMModel);
    Result.AddPair('temperature', TJSONNumber.Create(FTemperature));
    Result.AddPair('maxTokens', TJSONNumber.Create(FMaxTokens));
  end;
  
  // Guard
  if FActionType = atGuard then
  begin
    if FGuardType <> '' then
      Result.AddPair('guardType', FGuardType);
    if Assigned(FRules) then
      Result.AddPair('rules', TJSONArray(FRules.Clone));
  end;
  
  // HTTP
  if FActionType = atHttp then
  begin
    Result.AddPair('method', FHttpMethod);
    Result.AddPair('url', FHttpUrl);
    if Assigned(FHttpHeaders) then
      Result.AddPair('headers', TJSONObject(FHttpHeaders.Clone));
    if FHttpBody <> '' then
      Result.AddPair('body', FHttpBody);
  end;
  
  // Script
  if FActionType = atScript then
  begin
    Result.AddPair('lang', FScriptLang);
    Result.AddPair('code', FScriptCode);
  end;
  
  // Assign
  if FActionType = atAssign then
  begin
    AssignObj := TJSONObject.Create;
    for Pair in FAssignments do
      AssignObj.AddPair(Pair.Key, Pair.Value);
    Result.AddPair('assignments', AssignObj);
  end;
  
  // Log
  if FActionType = atLog then
  begin
    Result.AddPair('level', FLogLevel);
    Result.AddPair('message', FLogMessage);
  end;
end;

function TActionDefinition.Clone: TActionDefinition;
var
  Pair: TPair<string, string>;
begin
  Result := TActionDefinition.Create;
  Result.FActionType := FActionType;
  Result.FSkillId := FSkillId;
  if Assigned(FParams) then
    Result.FParams := TJSONObject(FParams.Clone);
  Result.FTimeoutMs := FTimeoutMs;
  Result.FRetryPolicy.Free;
  Result.FRetryPolicy := FRetryPolicy.Clone;
  Result.FOutput.Free;
  Result.FOutput := FOutput.Clone;
  
  Result.FLLMAction := FLLMAction;
  Result.FLLMModel := FLLMModel;
  Result.FTemperature := FTemperature;
  Result.FMaxTokens := FMaxTokens;
  
  Result.FGuardType := FGuardType;
  if Assigned(FRules) then
    Result.FRules := TJSONArray(FRules.Clone);
  
  Result.FHttpMethod := FHttpMethod;
  Result.FHttpUrl := FHttpUrl;
  if Assigned(FHttpHeaders) then
    Result.FHttpHeaders := TJSONObject(FHttpHeaders.Clone);
  Result.FHttpBody := FHttpBody;
  
  Result.FScriptLang := FScriptLang;
  Result.FScriptCode := FScriptCode;
  
  for Pair in FAssignments do
    Result.FAssignments.Add(Pair.Key, Pair.Value);
  
  Result.FLogLevel := FLogLevel;
  Result.FLogMessage := FLogMessage;
end;

// ============================================================================
// TConditionBranch
// ============================================================================

constructor TConditionBranch.Create;
begin
  inherited Create;
  FIsDefault := False;
  FSteps := TObjectList<TWorkflowStep>.Create(True);
end;

destructor TConditionBranch.Destroy;
begin
  FWhenValue.Free;
  FCondition.Free;
  FSteps.Free;
  inherited;
end;

procedure TConditionBranch.LoadFromJSON(AJson: TJSONObject);
var
  StepsArr: TJSONArray;
  I: Integer;
  Step: TWorkflowStep;
  CondObj: TJSONValue;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('id', FId) then;
  
  if AJson.TryGetValue<TJSONValue>('when', FWhenValue) then
    FWhenValue := FWhenValue.Clone as TJSONValue;
  
  if AJson.TryGetValue<string>('match', FMatchExpr) then;
  if AJson.TryGetValue<Boolean>('default', FIsDefault) then;
  
  if AJson.TryGetValue<TJSONValue>('condition', CondObj) then
  begin
    FCondition := TConditionExpression.Create;
    FCondition.LoadFromJSON(CondObj);
  end;
  
  if AJson.TryGetValue<TJSONArray>('steps', StepsArr) then
  begin
    for I := 0 to StepsArr.Count - 1 do
    begin
      Step := TWorkflowStep.Create;
      Step.LoadFromJSON(StepsArr.Items[I] as TJSONObject);
      FSteps.Add(Step);
    end;
  end;
end;

function TConditionBranch.ToJSON: TJSONObject;
var
  StepsArr: TJSONArray;
  Step: TWorkflowStep;
begin
  Result := TJSONObject.Create;
  
  if FId <> '' then
    Result.AddPair('id', FId);
  if Assigned(FWhenValue) then
    Result.AddPair('when', FWhenValue.Clone as TJSONValue);
  if FMatchExpr <> '' then
    Result.AddPair('match', FMatchExpr);
  if FIsDefault then
    Result.AddPair('default', TJSONBool.Create(True));
  if Assigned(FCondition) then
    Result.AddPair('condition', FCondition.ToJSON);
  
  StepsArr := TJSONArray.Create;
  for Step in FSteps do
    StepsArr.AddElement(Step.ToJSON);
  Result.AddPair('steps', StepsArr);
end;

function TConditionBranch.Clone: TConditionBranch;
var
  Step: TWorkflowStep;
begin
  Result := TConditionBranch.Create;
  Result.FId := FId;
  if Assigned(FWhenValue) then
    Result.FWhenValue := FWhenValue.Clone as TJSONValue;
  Result.FMatchExpr := FMatchExpr;
  Result.FIsDefault := FIsDefault;
  if Assigned(FCondition) then
    Result.FCondition := FCondition.Clone;
  for Step in FSteps do
    Result.FSteps.Add(Step.Clone);
end;

// ============================================================================
// TLoopConfig
// ============================================================================

constructor TLoopConfig.Create;
begin
  inherited Create;
  FMode := lmForEach;
  FItemVariable := 'item';
  FIndexVariable := 'index';
  FMaxIterations := 1000;
  FParallelism := 0;
end;

destructor TLoopConfig.Destroy;
begin
  FCondition.Free;
  inherited;
end;

procedure TLoopConfig.LoadFromJSON(AJson: TJSONObject);
var
  ModeStr: string;
  CondObj: TJSONValue;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('mode', ModeStr) then
    FMode := StrToLoopMode(ModeStr);
  if AJson.TryGetValue<string>('collection', FCollection) then;
  if AJson.TryGetValue<string>('itemVariable', FItemVariable) then;
  if AJson.TryGetValue<string>('indexVariable', FIndexVariable) then;
  if AJson.TryGetValue<Integer>('maxIterations', FMaxIterations) then;
  if AJson.TryGetValue<Integer>('parallelism', FParallelism) then;
  
  if AJson.TryGetValue<TJSONValue>('condition', CondObj) then
  begin
    FCondition := TConditionExpression.Create;
    FCondition.LoadFromJSON(CondObj);
  end;
end;

function TLoopConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('mode', LoopModeToStr(FMode));
  
  if FCollection <> '' then
    Result.AddPair('collection', FCollection);
  Result.AddPair('itemVariable', FItemVariable);
  Result.AddPair('indexVariable', FIndexVariable);
  Result.AddPair('maxIterations', TJSONNumber.Create(FMaxIterations));
  
  if FParallelism > 0 then
    Result.AddPair('parallelism', TJSONNumber.Create(FParallelism));
  
  if Assigned(FCondition) then
    Result.AddPair('condition', FCondition.ToJSON);
end;

function TLoopConfig.Clone: TLoopConfig;
begin
  Result := TLoopConfig.Create;
  Result.FMode := FMode;
  Result.FCollection := FCollection;
  Result.FItemVariable := FItemVariable;
  Result.FIndexVariable := FIndexVariable;
  Result.FMaxIterations := FMaxIterations;
  Result.FParallelism := FParallelism;
  if Assigned(FCondition) then
    Result.FCondition := FCondition.Clone;
end;

// ============================================================================
// TParallelConfig
// ============================================================================

constructor TParallelConfig.Create;
begin
  inherited Create;
  FWaitStrategy := wsAll;
  FWaitCount := 1;
  FFailureStrategy := fsFailFast;
end;

procedure TParallelConfig.LoadFromJSON(AJson: TJSONObject);
var
  S: string;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('waitStrategy', S) then
  begin
    if S = 'all' then FWaitStrategy := wsAll
    else if S = 'any' then FWaitStrategy := wsAny
    else if S = 'n' then FWaitStrategy := wsN;
  end;
  
  if AJson.TryGetValue<Integer>('waitCount', FWaitCount) then;
  
  if AJson.TryGetValue<string>('failureStrategy', S) then
  begin
    if S = 'failFast' then FFailureStrategy := fsFailFast
    else if S = 'continue' then FFailureStrategy := fsContinue
    else if S = 'rollback' then FFailureStrategy := fsRollback;
  end;
end;

function TParallelConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  
  case FWaitStrategy of
    wsAll: Result.AddPair('waitStrategy', 'all');
    wsAny: Result.AddPair('waitStrategy', 'any');
    wsN:   Result.AddPair('waitStrategy', 'n');
  end;
  
  if FWaitStrategy = wsN then
    Result.AddPair('waitCount', TJSONNumber.Create(FWaitCount));
  
  case FFailureStrategy of
    fsFailFast: Result.AddPair('failureStrategy', 'failFast');
    fsContinue: Result.AddPair('failureStrategy', 'continue');
    fsRollback: Result.AddPair('failureStrategy', 'rollback');
  end;
end;

function TParallelConfig.Clone: TParallelConfig;
begin
  Result := TParallelConfig.Create;
  Result.FWaitStrategy := FWaitStrategy;
  Result.FWaitCount := FWaitCount;
  Result.FFailureStrategy := FFailureStrategy;
end;

// ============================================================================
// TWaitConfig
// ============================================================================

constructor TWaitConfig.Create;
begin
  inherited Create;
  FTimeoutMs := 3600000;  // 1 小时
  FTimeoutAction := 'cancel';
end;

destructor TWaitConfig.Destroy;
begin
  FOptions.Free;
  FInputSchema.Free;
  FDefaultValue.Free;
  inherited;
end;

procedure TWaitConfig.LoadFromJSON(AJson: TJSONObject);
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('prompt', FPrompt) then;
  if AJson.TryGetValue<TJSONArray>('options', FOptions) then
    FOptions := TJSONArray(FOptions.Clone);
  if AJson.TryGetValue<TJSONObject>('inputSchema', FInputSchema) then
    FInputSchema := TJSONObject(FInputSchema.Clone);
  if AJson.TryGetValue<Integer>('timeout', FTimeoutMs) then;
  if AJson.TryGetValue<string>('timeoutAction', FTimeoutAction) then;
  if AJson.TryGetValue<TJSONValue>('defaultValue', FDefaultValue) then
    FDefaultValue := FDefaultValue.Clone as TJSONValue;
end;

function TWaitConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('prompt', FPrompt);
  
  if Assigned(FOptions) then
    Result.AddPair('options', TJSONArray(FOptions.Clone));
  if Assigned(FInputSchema) then
    Result.AddPair('inputSchema', TJSONObject(FInputSchema.Clone));
  
  Result.AddPair('timeout', TJSONNumber.Create(FTimeoutMs));
  Result.AddPair('timeoutAction', FTimeoutAction);
  
  if Assigned(FDefaultValue) then
    Result.AddPair('defaultValue', FDefaultValue.Clone as TJSONValue);
end;

function TWaitConfig.Clone: TWaitConfig;
begin
  Result := TWaitConfig.Create;
  Result.FPrompt := FPrompt;
  if Assigned(FOptions) then
    Result.FOptions := TJSONArray(FOptions.Clone);
  if Assigned(FInputSchema) then
    Result.FInputSchema := TJSONObject(FInputSchema.Clone);
  Result.FTimeoutMs := FTimeoutMs;
  Result.FTimeoutAction := FTimeoutAction;
  if Assigned(FDefaultValue) then
    Result.FDefaultValue := FDefaultValue.Clone as TJSONValue;
end;

// ============================================================================
// TErrorHandler
// ============================================================================

constructor TErrorHandler.Create;
begin
  inherited Create;
  FMaxTimes := 3;
  FCooldownMs := 30000;
end;

procedure TErrorHandler.LoadFromJSON(AJson: TJSONObject);
var
  ConfigObj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('match', FMatchPattern) then;
  if AJson.TryGetValue<string>('action', FAction) then;
  
  if AJson.TryGetValue<TJSONObject>('config', ConfigObj) then
  begin
    if ConfigObj.TryGetValue<string>('fallbackStep', FFallbackStepId) then;
    if ConfigObj.TryGetValue<string>('step', FGotoStepId) then;
    if ConfigObj.TryGetValue<Integer>('maxTimes', FMaxTimes) then;
    if ConfigObj.TryGetValue<Integer>('cooldownMs', FCooldownMs) then;
    if ConfigObj.TryGetValue<string>('message', FMessage) then;
  end;
end;

function TErrorHandler.ToJSON: TJSONObject;
var
  ConfigObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('match', FMatchPattern);
  Result.AddPair('action', FAction);
  
  ConfigObj := TJSONObject.Create;
  if FFallbackStepId <> '' then
    ConfigObj.AddPair('fallbackStep', FFallbackStepId);
  if FGotoStepId <> '' then
    ConfigObj.AddPair('step', FGotoStepId);
  ConfigObj.AddPair('maxTimes', TJSONNumber.Create(FMaxTimes));
  if FCooldownMs > 0 then
    ConfigObj.AddPair('cooldownMs', TJSONNumber.Create(FCooldownMs));
  if FMessage <> '' then
    ConfigObj.AddPair('message', FMessage);
  Result.AddPair('config', ConfigObj);
end;

function TErrorHandler.Clone: TErrorHandler;
begin
  Result := TErrorHandler.Create;
  Result.FMatchPattern := FMatchPattern;
  Result.FAction := FAction;
  Result.FFallbackStepId := FFallbackStepId;
  Result.FGotoStepId := FGotoStepId;
  Result.FMaxTimes := FMaxTimes;
  Result.FCooldownMs := FCooldownMs;
  Result.FMessage := FMessage;
end;

function TErrorHandler.Matches(const AErrorCode: string): Boolean;
var
  Pattern: string;
begin
  if FMatchPattern = '*' then
    Exit(True);
  
  // 支持简单通配�?
  Pattern := '^' + TRegEx.Escape(FMatchPattern).Replace('\*', '.*') + '$';
  Result := TRegEx.IsMatch(AErrorCode, Pattern, [roIgnoreCase]);
end;

// ============================================================================
// TWorkflowStep
// ============================================================================

constructor TWorkflowStep.Create;
begin
  inherited Create;
  FStepType := stAction;
  FAction := TActionDefinition.Create;
  FBranches := TObjectList<TConditionBranch>.Create(True);
  FLoopConfig := TLoopConfig.Create;
  FLoopSteps := TObjectList<TWorkflowStep>.Create(True);
  FParallelConfig := TParallelConfig.Create;
  FParallelBranches := TObjectList<TConditionBranch>.Create(True);
  FWaitConfig := TWaitConfig.Create;
  FOnError := TObjectList<TErrorHandler>.Create(True);
  FOutput := TOutputConfig.Create;
  FInheritContext := True;
  FAsync := False;
end;

destructor TWorkflowStep.Destroy;
begin
  FCondition.Free;
  FAction.Free;
  FBranches.Free;
  FLoopConfig.Free;
  FLoopSteps.Free;
  FParallelConfig.Free;
  FParallelBranches.Free;
  FSubWorkflowInput.Free;
  FWaitConfig.Free;
  FOnError.Free;
  FOutput.Free;
  inherited;
end;

procedure TWorkflowStep.LoadFromJSON(AJson: TJSONObject);
var
  TypeStr: string;
  CondObj: TJSONValue;
  BranchesArr, StepsArr, ErrorArr: TJSONArray;
  I: Integer;
  Branch: TConditionBranch;
  Step: TWorkflowStep;
  Handler: TErrorHandler;
  OutputObj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  // 基本信息
  if AJson.TryGetValue<string>('id', FId) then;
  if AJson.TryGetValue<string>('name', FName) then;
  if AJson.TryGetValue<string>('description', FDescription) then;
  
  // 步骤类型
  if AJson.TryGetValue<string>('type', TypeStr) then
    FStepType := StrToStepType(TypeStr);
  
  // 执行条件
  if AJson.TryGetValue<TJSONValue>('condition', CondObj) then
  begin
    FCondition := TConditionExpression.Create;
    FCondition.LoadFromJSON(CondObj);
  end;
  
  // 根据类型加载特定配置
  case FStepType of
    stAction:
      FAction.LoadFromJSON(AJson);
    
    stCondition:
    begin
      if AJson.TryGetValue<string>('expression', FExpression) then;
      if AJson.TryGetValue<TJSONArray>('branches', BranchesArr) then
      begin
        for I := 0 to BranchesArr.Count - 1 do
        begin
          Branch := TConditionBranch.Create;
          Branch.LoadFromJSON(BranchesArr.Items[I] as TJSONObject);
          FBranches.Add(Branch);
        end;
      end;
    end;
    
    stLoop:
    begin
      FLoopConfig.LoadFromJSON(AJson);
      if AJson.TryGetValue<TJSONArray>('steps', StepsArr) then
      begin
        for I := 0 to StepsArr.Count - 1 do
        begin
          Step := TWorkflowStep.Create;
          Step.LoadFromJSON(StepsArr.Items[I] as TJSONObject);
          FLoopSteps.Add(Step);
        end;
      end;
    end;
    
    stParallel:
    begin
      FParallelConfig.LoadFromJSON(AJson);
      if AJson.TryGetValue<TJSONArray>('branches', BranchesArr) then
      begin
        for I := 0 to BranchesArr.Count - 1 do
        begin
          Branch := TConditionBranch.Create;
          Branch.LoadFromJSON(BranchesArr.Items[I] as TJSONObject);
          FParallelBranches.Add(Branch);
        end;
      end;
    end;
    
    stSubWorkflow:
    begin
      if AJson.TryGetValue<string>('workflow', FSubWorkflowId) then;
      if AJson.TryGetValue<TJSONObject>('input', FSubWorkflowInput) then
        FSubWorkflowInput := TJSONObject(FSubWorkflowInput.Clone);
      if AJson.TryGetValue<Boolean>('inheritContext', FInheritContext) then;
      if AJson.TryGetValue<Boolean>('async', FAsync) then;
    end;
    
    stWait:
      FWaitConfig.LoadFromJSON(AJson);
  end;
  
  // 错误处理
  if AJson.TryGetValue<TJSONArray>('onError', ErrorArr) then
  begin
    for I := 0 to ErrorArr.Count - 1 do
    begin
      Handler := TErrorHandler.Create;
      Handler.LoadFromJSON(ErrorArr.Items[I] as TJSONObject);
      FOnError.Add(Handler);
    end;
  end;
  
  // 输出配置
  if AJson.TryGetValue<TJSONObject>('output', OutputObj) then
    FOutput.LoadFromJSON(OutputObj);
end;

function TWorkflowStep.ToJSON: TJSONObject;
var
  BranchesArr, StepsArr, ErrorArr: TJSONArray;
  Branch: TConditionBranch;
  Step: TWorkflowStep;
  Handler: TErrorHandler;
  ActionJson: TJSONObject;
  Pair: TJSONPair;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  if FName <> '' then
    Result.AddPair('name', FName);
  Result.AddPair('type', StepTypeToStr(FStepType));
  if FDescription <> '' then
    Result.AddPair('description', FDescription);
  
  if Assigned(FCondition) then
    Result.AddPair('condition', FCondition.ToJSON);
  
  case FStepType of
    stAction:
    begin
      ActionJson := FAction.ToJSON;
      for Pair in ActionJson do
        if Pair.JsonString.Value <> 'type' then
          Result.AddPair(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSONValue);
      ActionJson.Free;
    end;
    
    stCondition:
    begin
      if FExpression <> '' then
        Result.AddPair('expression', FExpression);
      BranchesArr := TJSONArray.Create;
      for Branch in FBranches do
        BranchesArr.AddElement(Branch.ToJSON);
      Result.AddPair('branches', BranchesArr);
    end;
    
    stLoop:
    begin
      // 合并 LoopConfig
      Result.AddPair('mode', LoopModeToStr(FLoopConfig.Mode));
      if FLoopConfig.Collection <> '' then
        Result.AddPair('collection', FLoopConfig.Collection);
      Result.AddPair('itemVariable', FLoopConfig.ItemVariable);
      Result.AddPair('indexVariable', FLoopConfig.IndexVariable);
      Result.AddPair('maxIterations', TJSONNumber.Create(FLoopConfig.MaxIterations));
      if FLoopConfig.Parallelism > 0 then
        Result.AddPair('parallelism', TJSONNumber.Create(FLoopConfig.Parallelism));
      
      StepsArr := TJSONArray.Create;
      for Step in FLoopSteps do
        StepsArr.AddElement(Step.ToJSON);
      Result.AddPair('steps', StepsArr);
    end;
    
    stParallel:
    begin
      Result.AddPair('waitStrategy', 'all');  // TODO: from config
      Result.AddPair('failureStrategy', 'failFast');
      
      BranchesArr := TJSONArray.Create;
      for Branch in FParallelBranches do
        BranchesArr.AddElement(Branch.ToJSON);
      Result.AddPair('branches', BranchesArr);
    end;
    
    stSubWorkflow:
    begin
      Result.AddPair('workflow', FSubWorkflowId);
      if Assigned(FSubWorkflowInput) then
        Result.AddPair('input', TJSONObject(FSubWorkflowInput.Clone));
      Result.AddPair('inheritContext', TJSONBool.Create(FInheritContext));
      Result.AddPair('async', TJSONBool.Create(FAsync));
    end;
    
    stWait:
    begin
      Result.AddPair('prompt', FWaitConfig.Prompt);
      if Assigned(FWaitConfig.Options) then
        Result.AddPair('options', TJSONArray(FWaitConfig.Options.Clone));
      Result.AddPair('timeout', TJSONNumber.Create(FWaitConfig.TimeoutMs));
      Result.AddPair('timeoutAction', FWaitConfig.TimeoutAction);
    end;
  end;
  
  // 错误处理
  if FOnError.Count > 0 then
  begin
    ErrorArr := TJSONArray.Create;
    for Handler in FOnError do
      ErrorArr.AddElement(Handler.ToJSON);
    Result.AddPair('onError', ErrorArr);
  end;
  
  // 输出
  if FOutput.Variable <> '' then
    Result.AddPair('output', FOutput.ToJSON);
end;

function TWorkflowStep.Clone: TWorkflowStep;
var
  Branch: TConditionBranch;
  Step: TWorkflowStep;
  Handler: TErrorHandler;
begin
  Result := TWorkflowStep.Create;
  Result.FId := FId;
  Result.FName := FName;
  Result.FStepType := FStepType;
  Result.FDescription := FDescription;
  
  if Assigned(FCondition) then
    Result.FCondition := FCondition.Clone;
  
  Result.FAction.Free;
  Result.FAction := FAction.Clone;
  
  Result.FExpression := FExpression;
  for Branch in FBranches do
    Result.FBranches.Add(Branch.Clone);
  
  Result.FLoopConfig.Free;
  Result.FLoopConfig := FLoopConfig.Clone;
  for Step in FLoopSteps do
    Result.FLoopSteps.Add(Step.Clone);
  
  Result.FParallelConfig.Free;
  Result.FParallelConfig := FParallelConfig.Clone;
  for Branch in FParallelBranches do
    Result.FParallelBranches.Add(Branch.Clone);
  
  Result.FSubWorkflowId := FSubWorkflowId;
  if Assigned(FSubWorkflowInput) then
    Result.FSubWorkflowInput := TJSONObject(FSubWorkflowInput.Clone);
  Result.FInheritContext := FInheritContext;
  Result.FAsync := FAsync;
  
  Result.FWaitConfig.Free;
  Result.FWaitConfig := FWaitConfig.Clone;
  
  for Handler in FOnError do
    Result.FOnError.Add(Handler.Clone);
  
  Result.FOutput.Free;
  Result.FOutput := FOutput.Clone;
end;

// ============================================================================
// TWorkflowHook
// ============================================================================

constructor TWorkflowHook.Create;
begin
  inherited Create;
end;

destructor TWorkflowHook.Destroy;
begin
  FConfig.Free;
  inherited;
end;

procedure TWorkflowHook.LoadFromJSON(AJson: TJSONObject);
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('type', FHookType) then;
  if AJson.TryGetValue<string>('condition', FCondition) then;
  if AJson.TryGetValue<TJSONObject>('config', FConfig) then
    FConfig := TJSONObject(FConfig.Clone);
end;

function TWorkflowHook.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', FHookType);
  if FCondition <> '' then
    Result.AddPair('condition', FCondition);
  if Assigned(FConfig) then
    Result.AddPair('config', TJSONObject(FConfig.Clone));
end;

function TWorkflowHook.Clone: TWorkflowHook;
begin
  Result := TWorkflowHook.Create;
  Result.FHookType := FHookType;
  Result.FCondition := FCondition;
  if Assigned(FConfig) then
    Result.FConfig := TJSONObject(FConfig.Clone);
end;

// ============================================================================
// TWorkflowHooks
// ============================================================================

constructor TWorkflowHooks.Create;
begin
  inherited Create;
  FOnStart := TObjectList<TWorkflowHook>.Create(True);
  FOnComplete := TObjectList<TWorkflowHook>.Create(True);
  FOnError := TObjectList<TWorkflowHook>.Create(True);
  FOnStepStart := TObjectList<TWorkflowHook>.Create(True);
  FOnStepComplete := TObjectList<TWorkflowHook>.Create(True);
end;

destructor TWorkflowHooks.Destroy;
begin
  FOnStart.Free;
  FOnComplete.Free;
  FOnError.Free;
  FOnStepStart.Free;
  FOnStepComplete.Free;
  inherited;
end;

procedure TWorkflowHooks.LoadFromJSON(AJson: TJSONObject);

  procedure LoadHookList(const AKey: string; AList: TObjectList<TWorkflowHook>);
  var
    Arr: TJSONArray;
    I: Integer;
    Hook: TWorkflowHook;
  begin
    if AJson.TryGetValue<TJSONArray>(AKey, Arr) then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        Hook := TWorkflowHook.Create;
        Hook.LoadFromJSON(Arr.Items[I] as TJSONObject);
        AList.Add(Hook);
      end;
    end;
  end;

begin
  if AJson = nil then Exit;
  
  LoadHookList('onStart', FOnStart);
  LoadHookList('onComplete', FOnComplete);
  LoadHookList('onError', FOnError);
  LoadHookList('onStepStart', FOnStepStart);
  LoadHookList('onStepComplete', FOnStepComplete);
end;

function TWorkflowHooks.ToJSON: TJSONObject;

  function HookListToJSON(AList: TObjectList<TWorkflowHook>): TJSONArray;
  var
    Hook: TWorkflowHook;
  begin
    Result := TJSONArray.Create;
    for Hook in AList do
      Result.AddElement(Hook.ToJSON);
  end;

begin
  Result := TJSONObject.Create;
  if FOnStart.Count > 0 then
    Result.AddPair('onStart', HookListToJSON(FOnStart));
  if FOnComplete.Count > 0 then
    Result.AddPair('onComplete', HookListToJSON(FOnComplete));
  if FOnError.Count > 0 then
    Result.AddPair('onError', HookListToJSON(FOnError));
  if FOnStepStart.Count > 0 then
    Result.AddPair('onStepStart', HookListToJSON(FOnStepStart));
  if FOnStepComplete.Count > 0 then
    Result.AddPair('onStepComplete', HookListToJSON(FOnStepComplete));
end;

function TWorkflowHooks.Clone: TWorkflowHooks;
var
  Hook: TWorkflowHook;
begin
  Result := TWorkflowHooks.Create;
  for Hook in FOnStart do
    Result.FOnStart.Add(Hook.Clone);
  for Hook in FOnComplete do
    Result.FOnComplete.Add(Hook.Clone);
  for Hook in FOnError do
    Result.FOnError.Add(Hook.Clone);
  for Hook in FOnStepStart do
    Result.FOnStepStart.Add(Hook.Clone);
  for Hook in FOnStepComplete do
    Result.FOnStepComplete.Add(Hook.Clone);
end;

// ============================================================================
// TTriggerConfig
// ============================================================================

constructor TTriggerConfig.Create;
begin
  inherited Create;
  FTriggerType := 'api';
end;

destructor TTriggerConfig.Destroy;
begin
  FConfig.Free;
  inherited;
end;

procedure TTriggerConfig.LoadFromJSON(AJson: TJSONObject);
var
  ConfigObj: TJSONObject;
begin
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<string>('type', FTriggerType) then;
  
  if AJson.TryGetValue<TJSONObject>('config', ConfigObj) then
  begin
    FConfig := TJSONObject(ConfigObj.Clone);
    if ConfigObj.TryGetValue<string>('endpoint', FEndpoint) then;
    if ConfigObj.TryGetValue<string>('cron', FCron) then;
    if ConfigObj.TryGetValue<string>('event', FEventName) then;
  end;
end;

function TTriggerConfig.ToJSON: TJSONObject;
var
  ConfigObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', FTriggerType);
  
  ConfigObj := TJSONObject.Create;
  if FEndpoint <> '' then
    ConfigObj.AddPair('endpoint', FEndpoint);
  if FCron <> '' then
    ConfigObj.AddPair('cron', FCron);
  if FEventName <> '' then
    ConfigObj.AddPair('event', FEventName);
  Result.AddPair('config', ConfigObj);
end;

function TTriggerConfig.Clone: TTriggerConfig;
begin
  Result := TTriggerConfig.Create;
  Result.FTriggerType := FTriggerType;
  Result.FEndpoint := FEndpoint;
  Result.FCron := FCron;
  Result.FEventName := FEventName;
  if Assigned(FConfig) then
    Result.FConfig := TJSONObject(FConfig.Clone);
end;

// ============================================================================
// TWorkflowDefinition
// ============================================================================

constructor TWorkflowDefinition.Create;
begin
  inherited Create;
  FVersion := '1.0.0';
  FTrigger := TTriggerConfig.Create;
  FSteps := TObjectList<TWorkflowStep>.Create(True);
  FErrorHandlers := TObjectList<TErrorHandler>.Create(True);
  FHooks := TWorkflowHooks.Create;
end;

destructor TWorkflowDefinition.Destroy;
begin
  FTrigger.Free;
  FInputSchema.Free;
  FOutputSchema.Free;
  FVariables.Free;
  FSteps.Free;
  FErrorHandlers.Free;
  FHooks.Free;
  FMetadata.Free;
  inherited;
end;

procedure TWorkflowDefinition.LoadFromJSON(AJson: TJSONObject);
var
  TriggerObj, HooksObj: TJSONObject;
  StepsArr, ErrorArr: TJSONArray;
  I: Integer;
  Step: TWorkflowStep;
  Handler: TErrorHandler;
begin
  if AJson = nil then Exit;
  
  // 基本信息
  if AJson.TryGetValue<string>('id', FId) then;
  if AJson.TryGetValue<string>('name', FName) then;
  if AJson.TryGetValue<string>('version', FVersion) then;
  if AJson.TryGetValue<string>('description', FDescription) then;
  
  // 触发�?
  if AJson.TryGetValue<TJSONObject>('trigger', TriggerObj) then
    FTrigger.LoadFromJSON(TriggerObj);
  
  // Schema
  if AJson.TryGetValue<TJSONObject>('input', FInputSchema) then
    FInputSchema := TJSONObject(FInputSchema.Clone);
  if AJson.TryGetValue<TJSONObject>('output', FOutputSchema) then
    FOutputSchema := TJSONObject(FOutputSchema.Clone);
  
  // 变量
  if AJson.TryGetValue<TJSONObject>('variables', FVariables) then
    FVariables := TJSONObject(FVariables.Clone);
  
  // 步骤
  if AJson.TryGetValue<TJSONArray>('steps', StepsArr) then
  begin
    for I := 0 to StepsArr.Count - 1 do
    begin
      Step := TWorkflowStep.Create;
      Step.LoadFromJSON(StepsArr.Items[I] as TJSONObject);
      FSteps.Add(Step);
    end;
  end;
  
  // 错误处理
  if AJson.TryGetValue<TJSONArray>('errorHandlers', ErrorArr) then
  begin
    for I := 0 to ErrorArr.Count - 1 do
    begin
      Handler := TErrorHandler.Create;
      Handler.LoadFromJSON(ErrorArr.Items[I] as TJSONObject);
      FErrorHandlers.Add(Handler);
    end;
  end;
  
  // 钩子
  if AJson.TryGetValue<TJSONObject>('hooks', HooksObj) then
    FHooks.LoadFromJSON(HooksObj);
  
  // 元信�?
  if AJson.TryGetValue<TJSONObject>('metadata', FMetadata) then
    FMetadata := TJSONObject(FMetadata.Clone);
end;

procedure TWorkflowDefinition.LoadFromString(const AJsonStr: string);
var
  Json: TJSONObject;
begin
  Json := TJSONObject.ParseJSONValue(AJsonStr) as TJSONObject;
  try
    LoadFromJSON(Json);
  finally
    Json.Free;
  end;
end;

procedure TWorkflowDefinition.LoadFromFile(const AFilePath: string);
var
  Content: TStringList;
begin
  Content := TStringList.Create;
  try
    Content.LoadFromFile(AFilePath, TEncoding.UTF8);
    LoadFromString(Content.Text);
  finally
    Content.Free;
  end;
end;

function TWorkflowDefinition.ToJSON: TJSONObject;
var
  StepsArr, ErrorArr: TJSONArray;
  Step: TWorkflowStep;
  Handler: TErrorHandler;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('name', FName);
  Result.AddPair('version', FVersion);
  if FDescription <> '' then
    Result.AddPair('description', FDescription);
  
  Result.AddPair('trigger', FTrigger.ToJSON);
  
  if Assigned(FInputSchema) then
    Result.AddPair('input', TJSONObject(FInputSchema.Clone));
  if Assigned(FOutputSchema) then
    Result.AddPair('output', TJSONObject(FOutputSchema.Clone));
  if Assigned(FVariables) then
    Result.AddPair('variables', TJSONObject(FVariables.Clone));
  
  StepsArr := TJSONArray.Create;
  for Step in FSteps do
    StepsArr.AddElement(Step.ToJSON);
  Result.AddPair('steps', StepsArr);
  
  if FErrorHandlers.Count > 0 then
  begin
    ErrorArr := TJSONArray.Create;
    for Handler in FErrorHandlers do
      ErrorArr.AddElement(Handler.ToJSON);
    Result.AddPair('errorHandlers', ErrorArr);
  end;
  
  Result.AddPair('hooks', FHooks.ToJSON);
  
  if Assigned(FMetadata) then
    Result.AddPair('metadata', TJSONObject(FMetadata.Clone));
end;

function TWorkflowDefinition.ToJSONString(APretty: Boolean): string;
var
  Json: TJSONObject;
begin
  Json := ToJSON;
  try
    if APretty then
      Result := Json.Format(2)
    else
      Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

procedure TWorkflowDefinition.SaveToFile(const AFilePath: string; APretty: Boolean);
var
  Content: TStringList;
begin
  Content := TStringList.Create;
  try
    Content.Text := ToJSONString(APretty);
    Content.SaveToFile(AFilePath, TEncoding.UTF8);
  finally
    Content.Free;
  end;
end;

function TWorkflowDefinition.Validate(out AErrors: TArray<string>): Boolean;
var
  Errors: TList<string>;
  StepIds: TDictionary<string, Boolean>;
  I: Integer;
  Step: TWorkflowStep;
begin
  Errors := TList<string>.Create;
  StepIds := TDictionary<string, Boolean>.Create;
  try
    // 检查必填字�?
    if FId = '' then
      Errors.Add('FlowDefinition id is required');
    if FName = '' then
      Errors.Add('FlowDefinition name is required');
    if FSteps.Count = 0 then
      Errors.Add('FlowDefinition must have at least one step');
    
    // 检查步�?ID 唯一�?
    for I := 0 to FSteps.Count - 1 do
    begin
      Step := FSteps[I];
      if Step.Id = '' then
        Errors.Add(Format('Step %d: id is required', [I + 1]))
      else if StepIds.ContainsKey(Step.Id) then
        Errors.Add(Format('Duplicate step id: %s', [Step.Id]))
      else
        StepIds.Add(Step.Id, True);
    end;
    
    // TODO: 更多验证
    // - 变量引用有效�?
    // - 循环依赖检�?
    // - 表达式语法检�?
    
    AErrors := Errors.ToArray;
    Result := Errors.Count = 0;
  finally
    StepIds.Free;
    Errors.Free;
  end;
end;

function TWorkflowDefinition.FindStepById(const AStepId: string): TWorkflowStep;

  function FindInSteps(ASteps: TObjectList<TWorkflowStep>): TWorkflowStep;
  var
    Step: TWorkflowStep;
    Branch: TConditionBranch;
  begin
    Result := nil;
    for Step in ASteps do
    begin
      if Step.Id = AStepId then
        Exit(Step);
      
      // 搜索嵌套步骤
      case Step.StepType of
        stCondition:
          for Branch in Step.Branches do
          begin
            Result := FindInSteps(Branch.Steps);
            if Result <> nil then Exit;
          end;
        
        stLoop:
        begin
          Result := FindInSteps(Step.LoopSteps);
          if Result <> nil then Exit;
        end;
        
        stParallel:
          for Branch in Step.ParallelBranches do
          begin
            Result := FindInSteps(Branch.Steps);
            if Result <> nil then Exit;
          end;
      end;
    end;
  end;

begin
  Result := FindInSteps(FSteps);
end;

function TWorkflowDefinition.Clone: TWorkflowDefinition;
var
  Step: TWorkflowStep;
  Handler: TErrorHandler;
begin
  Result := TWorkflowDefinition.Create;
  Result.FId := FId;
  Result.FName := FName;
  Result.FVersion := FVersion;
  Result.FDescription := FDescription;
  
  Result.FTrigger.Free;
  Result.FTrigger := FTrigger.Clone;
  
  if Assigned(FInputSchema) then
    Result.FInputSchema := TJSONObject(FInputSchema.Clone);
  if Assigned(FOutputSchema) then
    Result.FOutputSchema := TJSONObject(FOutputSchema.Clone);
  if Assigned(FVariables) then
    Result.FVariables := TJSONObject(FVariables.Clone);
  
  for Step in FSteps do
    Result.FSteps.Add(Step.Clone);
  
  for Handler in FErrorHandlers do
    Result.FErrorHandlers.Add(Handler.Clone);
  
  Result.FHooks.Free;
  Result.FHooks := FHooks.Clone;
  
  if Assigned(FMetadata) then
    Result.FMetadata := TJSONObject(FMetadata.Clone);
end;

end.
