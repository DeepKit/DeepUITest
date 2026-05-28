# API Reference

Complete API documentation for UniFlow Workflow Engine.

## Table of Contents

- [Workflow Definition](#workflow-definition)
- [Workflow Executor](#workflow-executor)
- [Workflow Context](#workflow-context)
- [Session Management](#session-management)
- [Skill Client](#skill-client)
- [Audit Manager](#audit-manager)
- [Metrics](#metrics)
- [Diagnostics](#diagnostics)
- [Security](#security)

---

## Workflow Definition

### TWorkflowDefinition

Main class representing a workflow structure.

```pascal
TWorkflowDefinition = class
  property Id: string;
  property Name: string;
  property Version: string;
  property Description: string;
  property Steps: TArray<TWorkflowStep>;
  property Triggers: TArray<TTriggerConfig>;
  property Hooks: TWorkflowHooks;
  
  class function FromJSON(const JSON: string): TWorkflowDefinition;
  class function FromFile(const FileName: string): TWorkflowDefinition;
  function ToJSON: string;
  function Validate: TValidationResult;
  function Clone: TWorkflowDefinition;
  function GetStep(const StepId: string): TWorkflowStep;
end;
```

### TWorkflowStep

Represents a single step in the workflow.

```pascal
TWorkflowStep = class
  property Id: string;
  property StepType: TStepType;
  property Name: string;
  property Description: string;
  property Action: TActionDefinition;
  property Condition: TConditionExpression;
  property LoopConfig: TLoopConfig;
  property ParallelConfig: TParallelConfig;
  property WaitConfig: TWaitConfig;
  property Branches: TArray<TConditionBranch>;
  property NextStep: string;
  property ErrorHandler: TErrorHandler;
  property RetryPolicy: TRetryPolicy;
  property Output: TOutputConfig;
  property Timeout: Integer;  // milliseconds
end;
```

### TStepType

```pascal
TStepType = (
  stAction,      // Execute an action
  stCondition,   // Conditional branching
  stLoop,        // Loop iteration
  stParallel,    // Parallel execution
  stSubworkflow, // Call sub-workflow
  stWait,        // Wait for event/duration
  stEnd          // Workflow end
);
```

### TActionType

```pascal
TActionType = (
  atSkill,   // Call external skill
  atLLM,     // Call LLM provider
  atGuard,   // Input validation
  atLog,     // Log message
  atAssign,  // Variable assignment
  atHTTP,    // HTTP request
  atScript   // Execute script
);
```

### TRetryPolicy

```pascal
TRetryPolicy = class
  property MaxRetries: Integer;       // default: 3
  property BackoffMs: Integer;        // initial delay
  property BackoffMultiplier: Double; // exponential backoff
  property MaxBackoffMs: Integer;     // max delay cap
  property RetryableErrors: TArray<string>;
end;
```

---

## Workflow Executor

### TWorkflowExecutor

Main execution engine for workflows.

```pascal
TWorkflowExecutor = class
  constructor Create(Definition: TWorkflowDefinition);
  
  // Execute workflow
  procedure Execute(Context: TWorkflowContext);
  procedure ExecuteAsync(Context: TWorkflowContext; OnComplete: TProc);
  procedure ExecuteWithSession(Session: TWorkflowSession);
  
  // Execution control
  procedure Pause;
  procedure Resume;
  procedure Cancel;
  
  // State management
  function SaveSnapshot: TWorkflowSnapshot;
  procedure RestoreSnapshot(Snapshot: TWorkflowSnapshot);
  
  // Action executors
  procedure RegisterExecutor(ActionType: TActionType; Executor: IActionExecutor);
  
  // Properties
  property Status: TExecutionStatus read FStatus;
  property CurrentStep: TWorkflowStep read FCurrentStep;
  property Definition: TWorkflowDefinition read FDefinition;
  
  // Events
  property OnBeforeStep: TStepEvent;
  property OnAfterStep: TStepEvent;
  property OnError: TErrorEvent;
  property OnStatusChanged: TStatusEvent;
end;
```

### TExecutionStatus

```pascal
TExecutionStatus = (
  esIdle,       // Not started
  esRunning,    // Executing
  esPaused,     // Paused by user
  esWaiting,    // Waiting for event
  esCompleted,  // Finished successfully
  esFailed,     // Failed with error
  esCancelled   // Cancelled by user
);
```

### IActionExecutor

Interface for custom action executors.

```pascal
IActionExecutor = interface
  function Execute(
    const Action: TActionDefinition;
    Context: TWorkflowContext
  ): TStepResult;
  
  function CanHandle(ActionType: TActionType): Boolean;
end;
```

### TStepResult

```pascal
TStepResult = record
  Success: Boolean;
  Output: TJSONValue;
  Error: string;
  ErrorCode: string;
  Duration: Int64;  // milliseconds
  
  class function OK(Output: TJSONValue = nil): TStepResult; static;
  class function Fail(const Error: string; Code: string = ''): TStepResult; static;
end;
```

---

## Workflow Context

### TWorkflowContext

Variable management and expression evaluation.

```pascal
TWorkflowContext = class
  // Variable operations
  procedure SetVariable(const Name: string; const Value: TValue); overload;
  procedure SetVariable(const Name: string; const Value: TJSONValue); overload;
  function GetVariable(const Name: string): TVariableValue;
  function HasVariable(const Name: string): Boolean;
  procedure DeleteVariable(const Name: string);
  
  // Scope management
  procedure PushScope(Scope: TVariableScope);
  procedure PopScope;
  function GetCurrentScope: TVariableScope;
  
  // Expression evaluation
  function Evaluate(const Expression: string): TValue;
  function EvaluateString(const Template: string): string;
  function EvaluateBoolean(const Expression: string): Boolean;
  
  // Serialization
  function ToJSON: TJSONObject;
  procedure FromJSON(JSON: TJSONObject);
  
  // Properties
  property Variables: TDictionary<string, TVariableValue>;
  property WorkflowId: string;
  property InstanceId: string;
  property CorrelationId: string;
end;
```

### TVariableScope

```pascal
TVariableScope = (
  vsGlobal,    // Global across all workflows
  vsWorkflow,  // Current workflow instance
  vsStep,      // Current step only
  vsInput,     // Input parameters
  vsOutput     // Output parameters
);
```

### Expression Syntax

UniFlow uses a template syntax for expressions:

```
{{ vars.variable_name }}           - Access variable
{{ vars.object.nested.property }}  - Nested access
{{ vars.array[0] }}                - Array indexing
{{ vars.name | default:'Unknown' }} - Default filter
{{ vars.text | upper }}            - Uppercase filter
{{ vars.text | lower }}            - Lowercase filter
{{ vars.text | trim }}             - Trim whitespace
{{ vars.obj | json }}              - JSON stringify
{{ vars.text | truncate:100 }}     - Truncate to length
```

---

## Session Management

### TSessionManager

Multi-turn conversation management.

```pascal
TSessionManager = class
  constructor Create(Store: ISessionStore = nil);
  
  // Session operations
  function CreateSession(const UserId, WorkflowId: string): TWorkflowSession;
  function GetSession(const SessionId: string): TWorkflowSession;
  function GetOrCreate(const UserId, WorkflowId: string): TWorkflowSession;
  procedure DeleteSession(const SessionId: string);
  
  // Query
  function GetUserSessions(const UserId: string): TArray<TWorkflowSession>;
  function GetActiveSessions: TArray<TWorkflowSession>;
  
  // Cleanup
  procedure CleanupExpired;
  
  // Properties
  property DefaultTTL: Integer;  // seconds
  property Store: ISessionStore;
end;
```

### TWorkflowSession

```pascal
TWorkflowSession = class
  property Id: string;
  property UserId: string;
  property WorkflowId: string;
  property Status: TSessionStatus;
  property Messages: TList<TSessionMessage>;
  property Variables: TDictionary<string, TValue>;
  property Metadata: TDictionary<string, string>;
  property CreatedAt: TDateTime;
  property UpdatedAt: TDateTime;
  property ExpiresAt: TDateTime;
  
  procedure AddMessage(Message: TSessionMessage);
  procedure SetVariable(const Name: string; Value: TValue);
  function GetVariable(const Name: string): TValue;
  procedure Touch;  // Update expiry
end;
```

### TSessionMessage

```pascal
TSessionMessage = class
  property Id: string;
  property Role: TMessageRole;  // mrUser, mrAssistant, mrSystem
  property Content: string;
  property Timestamp: TDateTime;
  property Metadata: TJSONObject;
  
  class function CreateUser(const Content: string): TSessionMessage;
  class function CreateAssistant(const Content: string): TSessionMessage;
  class function CreateSystem(const Content: string): TSessionMessage;
end;
```

### ISessionStore

Interface for session persistence.

```pascal
ISessionStore = interface
  procedure Save(Session: TWorkflowSession);
  function Load(const SessionId: string): TWorkflowSession;
  procedure Delete(const SessionId: string);
  function Query(const Filter: TSessionFilter): TArray<TWorkflowSession>;
end;
```

Built-in implementations:
- `TMemorySessionStore` - In-memory storage
- `TSQLiteSessionStore` - SQLite database storage

---

## Skill Client

### TSkillClient

HTTP client for skill services.

```pascal
TSkillClient = class
  constructor Create(const BaseUrl: string);
  
  // Skill operations
  function Execute(const SkillName: string; Input: TJSONObject): TSkillResult;
  function ExecuteAsync(const SkillName: string; Input: TJSONObject): IFuture<TSkillResult>;
  function ExecuteBatch(Requests: TArray<TSkillRequest>): TArray<TSkillResult>;
  
  // Discovery
  function ListSkills: TArray<TSkillInfo>;
  function GetSkillInfo(const SkillName: string): TSkillInfo;
  function HealthCheck: Boolean;
  
  // Configuration
  property Timeout: Integer;  // milliseconds
  property RetryPolicy: TRetryPolicy;
  property Headers: TDictionary<string, string>;
end;
```

### TSkillResult

```pascal
TSkillResult = record
  Success: Boolean;
  Output: TJSONObject;
  Error: string;
  ErrorCode: string;
  Duration: Int64;
  SkillName: string;
  RequestId: string;
end;
```

### TSkillInfo

```pascal
TSkillInfo = class
  property Name: string;
  property Description: string;
  property Version: string;
  property InputSchema: TJSONObject;
  property OutputSchema: TJSONObject;
  property Tags: TArray<string>;
end;
```

---

## Audit Manager

### TAuditManager

Structured audit logging.

```pascal
TAuditManager = class
  // Logging
  procedure Log(Entry: TAuditEntry);
  procedure LogSystem(Action: TAuditAction; const Details: string);
  procedure LogWorkflow(const WorkflowId: string; Action: TAuditAction; const Details: string);
  procedure LogSession(const SessionId: string; Action: TAuditAction; const Details: string);
  procedure LogSecurity(Action: TAuditAction; const Details: string; Severity: TAuditSeverity);
  procedure LogLLM(const Provider, Model: string; TokensIn, TokensOut: Integer);
  procedure LogSkill(const SkillName: string; Success: Boolean; Duration: Int64);
  procedure LogError(E: Exception; const Context: string);
  
  // Querying
  function Query(Filter: TAuditQuery): TAuditQueryResult;
  function GetRecent(Count: Integer): TArray<TAuditEntry>;
  function GetStats(StartTime, EndTime: TDateTime): TAuditStats;
  function GetErrors(Count: Integer): TArray<TAuditEntry>;
  function GetByCorrelation(const CorrelationId: string): TArray<TAuditEntry>;
  
  // Configuration
  property MinLevel: TAuditSeverity;
  property DefaultUserId: string;
  property DefaultSessionId: string;
  property CorrelationId: string;
  property Store: IAuditStore;
end;
```

### TAuditEntry

```pascal
TAuditEntry = class
  property Id: string;
  property Timestamp: TDateTime;
  property Category: TAuditCategory;
  property Severity: TAuditSeverity;
  property Action: TAuditAction;
  property Message: string;
  property Details: TJSONObject;
  property UserId: string;
  property SessionId: string;
  property WorkflowId: string;
  property StepId: string;
  property CorrelationId: string;
  property Duration: Int64;
  property Tags: TArray<string>;
  
  // Fluent API
  function WithUser(const UserId: string): TAuditEntry;
  function WithSession(const SessionId: string): TAuditEntry;
  function WithWorkflow(const WorkflowId: string): TAuditEntry;
  function WithDuration(Ms: Int64): TAuditEntry;
  function WithDetails(Details: TJSONObject): TAuditEntry;
  function WithTag(const Tag: string): TAuditEntry;
end;
```

### TAuditCategory

```pascal
TAuditCategory = (
  acSystem,    // System events
  acWorkflow,  // Workflow execution
  acSession,   // Session management
  acSecurity,  // Security events
  acLLM,       // LLM calls
  acSkill,     // Skill invocations
  acUser,      // User actions
  acError      // Errors
);
```

### TAuditSeverity

```pascal
TAuditSeverity = (
  asDebug,     // Debug information
  asInfo,      // Informational
  asWarning,   // Warning
  asError,     // Error
  asCritical   // Critical error
);
```

---

## Metrics

### TMetricsRegistry

Prometheus-compatible metrics collection.

```pascal
TMetricsRegistry = class
  // Counter
  function Counter(const Name, Help: string; Labels: TArray<string> = nil): TCounterValue;
  procedure CounterInc(const Name: string; Value: Double = 1; Labels: TMetricLabels = nil);
  
  // Gauge
  function Gauge(const Name, Help: string; Labels: TArray<string> = nil): TGaugeValue;
  procedure GaugeSet(const Name: string; Value: Double; Labels: TMetricLabels = nil);
  procedure GaugeInc(const Name: string; Value: Double = 1; Labels: TMetricLabels = nil);
  procedure GaugeDec(const Name: string; Value: Double = 1; Labels: TMetricLabels = nil);
  
  // Histogram
  function Histogram(const Name, Help: string; Buckets: TArray<Double>; Labels: TArray<string> = nil): THistogramValue;
  procedure HistogramObserve(const Name: string; Value: Double; Labels: TMetricLabels = nil);
  
  // Export
  function ExportPrometheus: string;
  function ExportJSON: TJSONObject;
  
  // Properties
  property Namespace: string;
  property Subsystem: string;
end;
```

### Pre-defined Metrics

```pascal
TUniFlowMetrics = class
  // Workflow metrics
  class procedure WorkflowStarted(const WorkflowId: string);
  class procedure WorkflowCompleted(const WorkflowId: string; Duration: Double);
  class procedure WorkflowFailed(const WorkflowId: string; const Error: string);
  
  // Step metrics
  class procedure StepExecuted(const StepId, StepType: string; Duration: Double);
  class procedure StepFailed(const StepId: string);
  
  // LLM metrics
  class procedure LLMRequest(const Provider, Model: string; Duration: Double);
  class procedure LLMTokens(const Provider, Model: string; InputTokens, OutputTokens: Integer);
  class procedure LLMError(const Provider, Model, Error: string);
  
  // Skill metrics
  class procedure SkillInvoked(const SkillName: string; Duration: Double);
  class procedure SkillError(const SkillName: string);
  
  // Session metrics
  class procedure SessionCreated;
  class procedure SessionExpired;
end;
```

---

## Diagnostics

### TUniFlowDiagnostics

Debugging and tracing support.

```pascal
TUniFlowDiagnostics = class
  // Logging
  procedure Trace(const Msg: string; Args: array of const);
  procedure Debug(const Msg: string; Args: array of const);
  procedure Info(const Msg: string; Args: array of const);
  procedure Warning(const Msg: string; Args: array of const);
  procedure Error(const Msg: string; Args: array of const);
  procedure Fatal(const Msg: string; Args: array of const);
  
  // Step tracing
  procedure TraceStepEnter(const StepId, StepType: string);
  procedure TraceStepExit(const StepId: string; Duration: Int64);
  procedure TraceStepError(const StepId: string; E: Exception);
  
  // Error context
  function CaptureErrorContext(E: Exception; Context: TWorkflowContext): TErrorContext;
  
  // Export
  function DumpState(Context: TWorkflowContext): string;
  function ExportTrace: string;
  
  // Configuration
  property TraceEnabled: Boolean;
  property TraceLevel: TTraceLevel;  // tlMinimal, tlNormal, tlVerbose
  property LoggerFactory: ILoggerFactory;
  property CorrelationId: string;
  
  // Events
  property OnBeforeStep: TStepEvent;
  property OnAfterStep: TStepEvent;
  property OnError: TErrorEvent;
end;
```

### TWorkflowDebugger

Interactive debugging support.

```pascal
TWorkflowDebugger = class
  // Breakpoints
  procedure AddBreakpoint(const StepId: string; Condition: string = '');
  procedure RemoveBreakpoint(const StepId: string);
  procedure EnableBreakpoint(const StepId: string);
  procedure DisableBreakpoint(const StepId: string);
  function GetBreakpoints: TArray<TBreakpoint>;
  
  // Execution control
  procedure Continue;
  procedure Pause;
  procedure StepInto;
  procedure StepOver;
  procedure StepOut;
  procedure Stop;
  
  // Inspection
  function GetCallStack: TArray<TDebugFrame>;
  function GetVariables: TArray<TVariableInfo>;
  function GetVariable(const Name: string): TValue;
  function EvaluateExpression(const Expr: string): TValue;
  
  // Properties
  property State: TDebuggerState;
  property CurrentStep: TWorkflowStep;
end;
```

---

## Security

### TSanitizer

Input sanitization.

```pascal
TSanitizer = class
  // Text sanitization
  class function SanitizeHTML(const Input: string): string;
  class function SanitizeSQL(const Input: string): string;
  class function SanitizePath(const Input: string): string;
  class function SanitizeFileName(const Input: string): string;
  
  // Validation
  class function IsValidEmail(const Input: string): Boolean;
  class function IsValidURL(const Input: string): Boolean;
  class function IsValidJSON(const Input: string): Boolean;
end;
```

### TPromptGuard

Prompt injection detection.

```pascal
TPromptGuard = class
  function DetectInjection(const Input: string): TDetectionResult;
  function Sanitize(const Input: string): string;
  
  property Patterns: TArray<TDangerPattern>;
  property Sensitivity: TSensitivity;  // Low, Medium, High
end;
```

### TSensitiveFilter

PII and sensitive data filtering.

```pascal
TSensitiveFilter = class
  function Filter(const Input: string): string;
  function Detect(const Input: string): TArray<TSensitiveMatch>;
  
  procedure AddPattern(const Name, Pattern: string; Category: TSensitiveCategory);
  procedure SetMaskMode(Mode: TMaskMode);  // Partial, Full, Hash
  
  // Pre-defined patterns
  class function Email: TFilterPattern;
  class function Phone: TFilterPattern;
  class function SSN: TFilterPattern;
  class function CreditCard: TFilterPattern;
  class function APIKey: TFilterPattern;
end;
```

### TRateLimiter

Request rate limiting.

```pascal
TRateLimiter = class
  function TryAcquire(const Key: string): Boolean;
  function GetRemainingQuota(const Key: string): Integer;
  procedure Reset(const Key: string);
  
  property Policy: TRateLimitPolicy;
  property Scope: TRateLimitScope;  // Global, User, Session, IP
end;

TRateLimitPolicy = class
  property MaxRequests: Integer;
  property WindowSeconds: Integer;
  property BurstLimit: Integer;
end;
```

---

## Exceptions

### Common Exceptions

```pascal
EWorkflowException = class(Exception);
EWorkflowValidationError = class(EWorkflowException);
EWorkflowExecutionError = class(EWorkflowException);
EWorkflowTimeoutError = class(EWorkflowException);
EStepExecutionError = class(EWorkflowException);
ESkillExecutionError = class(EWorkflowException);
ELLMExecutionError = class(EWorkflowException);
ESessionNotFoundError = class(EWorkflowException);
ERateLimitExceededError = class(EWorkflowException);
```

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `UNIFLOW_LOG_LEVEL` | Logging level (debug/info/warning/error) | `info` |
| `UNIFLOW_TRACE_ENABLED` | Enable execution tracing | `false` |
| `UNIFLOW_METRICS_ENABLED` | Enable Prometheus metrics | `true` |
| `UNIFLOW_SKILL_TIMEOUT` | Skill call timeout (ms) | `30000` |
| `UNIFLOW_LLM_TIMEOUT` | LLM call timeout (ms) | `60000` |
| `UNIFLOW_SESSION_TTL` | Session TTL (seconds) | `3600` |
| `UNIFLOW_AUDIT_RETENTION` | Audit log retention (days) | `90` |

---

## Thread Safety

- `TWorkflowExecutor` - Single-threaded per instance
- `TWorkflowContext` - Not thread-safe
- `TSessionManager` - Thread-safe
- `TAuditManager` - Thread-safe
- `TMetricsRegistry` - Thread-safe
- `TSkillClient` - Thread-safe

For concurrent workflow execution, create separate `TWorkflowExecutor` and `TWorkflowContext` instances per thread.
