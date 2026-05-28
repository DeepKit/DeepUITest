(*******************************************************************************
                                                                               
  UniFlow Audit Types                                                          
  Type definitions for audit logging system                                    
                                                                               
  Features:                                                                    
  - Audit event types and categories                                           
  - Audit entry structure                                                      
  - Query filters and pagination                                               
  - Report types                                                               
                                                                               
*******************************************************************************)

unit UniFlow.Audit.Types;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  System.JSON;

type
  //----------------------------------------------------------------------------
  // Enums
  //----------------------------------------------------------------------------

  /// <summary>Audit event category</summary>
  TAuditCategory = (
    acSystem,        // System events (startup, shutdown, config changes)
    acWorkflow,      // Workflow lifecycle events
    acSession,       // Session events
    acSecurity,      // Security events (auth, access control)
    acLLM,           // LLM calls and responses
    acSkill,         // Skill executions
    acUser,          // User actions
    acError          // Errors and exceptions
  );

  /// <summary>Audit event severity</summary>
  TAuditSeverity = (
    asDebug,
    asInfo,
    asWarning,
    asError,
    asCritical
  );

  /// <summary>Audit event action type</summary>
  TAuditAction = (
    // System actions
    aaSystemStart,
    aaSystemStop,
    aaConfigChange,

    // Workflow actions
    aaWorkflowCreated,
    aaWorkflowStarted,
    aaWorkflowCompleted,
    aaWorkflowFailed,
    aaWorkflowCancelled,
    aaWorkflowPaused,
    aaWorkflowResumed,
    aaStepStarted,
    aaStepCompleted,
    aaStepFailed,

    // Session actions
    aaSessionCreated,
    aaSessionClosed,
    aaSessionExpired,
    aaMessageAdded,

    // Security actions
    aaLoginSuccess,
    aaLoginFailed,
    aaLogout,
    aaAccessDenied,
    aaRateLimited,
    aaSensitiveDataAccess,

    // LLM actions
    aaLLMRequest,
    aaLLMResponse,
    aaLLMError,
    aaTokenUsage,

    // Skill actions
    aaSkillExecuted,
    aaSkillFailed,
    aaSkillTimeout,

    // User actions
    aaUserInput,
    aaUserAction,

    // Error actions
    aaException,
    aaValidationError
  );

  //----------------------------------------------------------------------------
  // Helper records
  //----------------------------------------------------------------------------

  TAuditCategoryHelper = record helper for TAuditCategory
    function ToString: string;
    class function FromString(const AValue: string): TAuditCategory; static;
  end;

  TAuditSeverityHelper = record helper for TAuditSeverity
    function ToString: string;
    class function FromString(const AValue: string): TAuditSeverity; static;
  end;

  TAuditActionHelper = record helper for TAuditAction
    function ToString: string;
    function GetCategory: TAuditCategory;
    class function FromString(const AValue: string): TAuditAction; static;
  end;

  //----------------------------------------------------------------------------
  // Forward declarations
  //----------------------------------------------------------------------------

type
  TAuditEntry = class;
  TAuditQuery = class;
  TAuditQueryResult = class;
  TAuditStats = class;
  TAuditReport = class;

  //----------------------------------------------------------------------------
  // TAuditEntry - Single audit log entry
  //----------------------------------------------------------------------------

  TAuditEntry = class
  private
    FId: Int64;
    FTimestamp: TDateTime;
    FCategory: TAuditCategory;
    FSeverity: TAuditSeverity;
    FAction: TAuditAction;
    FUserId: string;
    FSessionId: string;
    FWorkflowId: string;
    FWorkflowName: string;
    FStepId: string;
    FMessage: string;
    FDetails: TJSONObject;
    FDurationMs: Integer;
    FTokensUsed: Integer;
    FSourceIP: string;
    FUserAgent: string;
    FCorrelationId: string;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TAuditEntry; static;

    function Clone: TAuditEntry;

    // Fluent setters
    function WithUser(const AUserId: string): TAuditEntry;
    function WithSession(const ASessionId: string): TAuditEntry;
    function WithWorkflow(const AWorkflowId, AWorkflowName: string): TAuditEntry;
    function WithStep(const AStepId: string): TAuditEntry;
    function WithDuration(ADurationMs: Integer): TAuditEntry;
    function WithTokens(ATokens: Integer): TAuditEntry;
    function WithDetail(const AKey: string; const AValue: TValue): TAuditEntry;
    function WithCorrelation(const ACorrelationId: string): TAuditEntry;

    property Id: Int64 read FId write FId;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property Category: TAuditCategory read FCategory write FCategory;
    property Severity: TAuditSeverity read FSeverity write FSeverity;
    property Action: TAuditAction read FAction write FAction;
    property UserId: string read FUserId write FUserId;
    property SessionId: string read FSessionId write FSessionId;
    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property WorkflowName: string read FWorkflowName write FWorkflowName;
    property StepId: string read FStepId write FStepId;
    property Message: string read FMessage write FMessage;
    property Details: TJSONObject read FDetails;
    property DurationMs: Integer read FDurationMs write FDurationMs;
    property TokensUsed: Integer read FTokensUsed write FTokensUsed;
    property SourceIP: string read FSourceIP write FSourceIP;
    property UserAgent: string read FUserAgent write FUserAgent;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
  end;

  //----------------------------------------------------------------------------
  // TAuditQuery - Query filter for audit logs
  //----------------------------------------------------------------------------

  TSortOrder = (soAscending, soDescending);

  TAuditQuery = class
  private
    FStartTime: TDateTime;
    FEndTime: TDateTime;
    FCategories: TList<TAuditCategory>;
    FSeverities: TList<TAuditSeverity>;
    FActions: TList<TAuditAction>;
    FUserId: string;
    FSessionId: string;
    FWorkflowId: string;
    FWorkflowName: string;
    FCorrelationId: string;
    FMessageContains: string;
    FMinDurationMs: Integer;
    FLimit: Integer;
    FOffset: Integer;
    FSortBy: string;
    FSortOrder: TSortOrder;
  public
    constructor Create;
    destructor Destroy; override;

    // Fluent builders
    function TimeRange(AStart, AEnd: TDateTime): TAuditQuery;
    function InCategory(ACategory: TAuditCategory): TAuditQuery;
    function InCategories(const ACategories: array of TAuditCategory): TAuditQuery;
    function WithSeverity(ASeverity: TAuditSeverity): TAuditQuery;
    function MinSeverity(ASeverity: TAuditSeverity): TAuditQuery;
    function ForAction(AAction: TAuditAction): TAuditQuery;
    function ForUser(const AUserId: string): TAuditQuery;
    function ForSession(const ASessionId: string): TAuditQuery;
    function ForWorkflow(const AWorkflowId: string): TAuditQuery;
    function ForWorkflowName(const AName: string): TAuditQuery;
    function WithCorrelation(const ACorrelationId: string): TAuditQuery;
    function MessageLike(const APattern: string): TAuditQuery;
    function SlowerThan(AMinMs: Integer): TAuditQuery;
    function Page(AOffset, ALimit: Integer): TAuditQuery;
    function OrderBy(const AField: string; AOrder: TSortOrder = soDescending): TAuditQuery;

    function ToJSON: TJSONObject;

    property StartTime: TDateTime read FStartTime write FStartTime;
    property EndTime: TDateTime read FEndTime write FEndTime;
    property Categories: TList<TAuditCategory> read FCategories;
    property Severities: TList<TAuditSeverity> read FSeverities;
    property Actions: TList<TAuditAction> read FActions;
    property UserId: string read FUserId write FUserId;
    property SessionId: string read FSessionId write FSessionId;
    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property WorkflowName: string read FWorkflowName write FWorkflowName;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
    property MessageContains: string read FMessageContains write FMessageContains;
    property MinDurationMs: Integer read FMinDurationMs write FMinDurationMs;
    property Limit: Integer read FLimit write FLimit;
    property Offset: Integer read FOffset write FOffset;
    property SortBy: string read FSortBy write FSortBy;
    property SortOrder: TSortOrder read FSortOrder write FSortOrder;
  end;

  //----------------------------------------------------------------------------
  // TAuditQueryResult - Query result with pagination
  //----------------------------------------------------------------------------

  TAuditQueryResult = class
  private
    FEntries: TObjectList<TAuditEntry>;
    FTotalCount: Int64;
    FOffset: Integer;
    FLimit: Integer;
    FHasMore: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;

    property Entries: TObjectList<TAuditEntry> read FEntries;
    property TotalCount: Int64 read FTotalCount write FTotalCount;
    property Offset: Integer read FOffset write FOffset;
    property Limit: Integer read FLimit write FLimit;
    property HasMore: Boolean read FHasMore write FHasMore;
  end;

  //----------------------------------------------------------------------------
  // TAuditStats - Aggregated statistics
  //----------------------------------------------------------------------------

  TAuditStats = class
  private
    FStartTime: TDateTime;
    FEndTime: TDateTime;
    FTotalEvents: Int64;
    FEventsByCategory: TDictionary<TAuditCategory, Int64>;
    FEventsBySeverity: TDictionary<TAuditSeverity, Int64>;
    FEventsByAction: TDictionary<TAuditAction, Int64>;
    FTotalTokensUsed: Int64;
    FTotalDurationMs: Int64;
    FAvgDurationMs: Double;
    FErrorCount: Int64;
    FUniqueUsers: Integer;
    FUniqueSessions: Integer;
    FUniqueWorkflows: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddCategoryCount(ACategory: TAuditCategory; ACount: Int64);
    procedure AddSeverityCount(ASeverity: TAuditSeverity; ACount: Int64);
    procedure AddActionCount(AAction: TAuditAction; ACount: Int64);

    function GetCategoryCount(ACategory: TAuditCategory): Int64;
    function GetSeverityCount(ASeverity: TAuditSeverity): Int64;
    function GetActionCount(AAction: TAuditAction): Int64;

    function ToJSON: TJSONObject;

    property StartTime: TDateTime read FStartTime write FStartTime;
    property EndTime: TDateTime read FEndTime write FEndTime;
    property TotalEvents: Int64 read FTotalEvents write FTotalEvents;
    property TotalTokensUsed: Int64 read FTotalTokensUsed write FTotalTokensUsed;
    property TotalDurationMs: Int64 read FTotalDurationMs write FTotalDurationMs;
    property AvgDurationMs: Double read FAvgDurationMs write FAvgDurationMs;
    property ErrorCount: Int64 read FErrorCount write FErrorCount;
    property UniqueUsers: Integer read FUniqueUsers write FUniqueUsers;
    property UniqueSessions: Integer read FUniqueSessions write FUniqueSessions;
    property UniqueWorkflows: Integer read FUniqueWorkflows write FUniqueWorkflows;
  end;

  //----------------------------------------------------------------------------
  // TAuditReport - Generated report
  //----------------------------------------------------------------------------

  TReportFormat = (rfText, rfHTML, rfJSON, rfCSV);

  TAuditReport = class
  private
    FTitle: string;
    FGeneratedAt: TDateTime;
    FPeriodStart: TDateTime;
    FPeriodEnd: TDateTime;
    FStats: TAuditStats;
    FTopErrors: TObjectList<TAuditEntry>;
    FSlowestOperations: TObjectList<TAuditEntry>;
    FContent: string;
    FFormat: TReportFormat;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;

    property Title: string read FTitle write FTitle;
    property GeneratedAt: TDateTime read FGeneratedAt write FGeneratedAt;
    property PeriodStart: TDateTime read FPeriodStart write FPeriodStart;
    property PeriodEnd: TDateTime read FPeriodEnd write FPeriodEnd;
    property Stats: TAuditStats read FStats;
    property TopErrors: TObjectList<TAuditEntry> read FTopErrors;
    property SlowestOperations: TObjectList<TAuditEntry> read FSlowestOperations;
    property Content: string read FContent write FContent;
    property Format: TReportFormat read FFormat write FFormat;
  end;

  //----------------------------------------------------------------------------
  // Factory functions
  //----------------------------------------------------------------------------

  function CreateAuditEntry(AAction: TAuditAction; const AMessage: string;
    ASeverity: TAuditSeverity = asInfo): TAuditEntry;

  function CreateSystemEntry(AAction: TAuditAction; const AMessage: string): TAuditEntry;
  function CreateWorkflowEntry(AAction: TAuditAction; const AWorkflowId, AWorkflowName, AMessage: string): TAuditEntry;
  function CreateSessionEntry(AAction: TAuditAction; const ASessionId, AUserId, AMessage: string): TAuditEntry;
  function CreateSecurityEntry(AAction: TAuditAction; const AUserId, AMessage: string;
    ASeverity: TAuditSeverity = asWarning): TAuditEntry;
  function CreateLLMEntry(AAction: TAuditAction; const AMessage: string;
    ATokens: Integer; ADurationMs: Integer): TAuditEntry;
  function CreateErrorEntry(const AMessage: string; const AException: Exception = nil): TAuditEntry;

implementation

uses
  System.DateUtils,
  System.StrUtils;

//------------------------------------------------------------------------------
// TAuditCategoryHelper
//------------------------------------------------------------------------------

function TAuditCategoryHelper.ToString: string;
begin
  case Self of
    acSystem:   Result := 'system';
    acWorkflow: Result := 'workflow';
    acSession:  Result := 'session';
    acSecurity: Result := 'security';
    acLLM:      Result := 'llm';
    acSkill:    Result := 'skill';
    acUser:     Result := 'user';
    acError:    Result := 'error';
  else
    Result := 'unknown';
  end;
end;

class function TAuditCategoryHelper.FromString(const AValue: string): TAuditCategory;
begin
  if AValue = 'system' then Result := acSystem
  else if AValue = 'workflow' then Result := acWorkflow
  else if AValue = 'session' then Result := acSession
  else if AValue = 'security' then Result := acSecurity
  else if AValue = 'llm' then Result := acLLM
  else if AValue = 'skill' then Result := acSkill
  else if AValue = 'user' then Result := acUser
  else if AValue = 'error' then Result := acError
  else Result := acSystem;
end;

//------------------------------------------------------------------------------
// TAuditSeverityHelper
//------------------------------------------------------------------------------

function TAuditSeverityHelper.ToString: string;
begin
  case Self of
    asDebug:    Result := 'debug';
    asInfo:     Result := 'info';
    asWarning:  Result := 'warning';
    asError:    Result := 'error';
    asCritical: Result := 'critical';
  else
    Result := 'info';
  end;
end;

class function TAuditSeverityHelper.FromString(const AValue: string): TAuditSeverity;
begin
  if AValue = 'debug' then Result := asDebug
  else if AValue = 'info' then Result := asInfo
  else if AValue = 'warning' then Result := asWarning
  else if AValue = 'error' then Result := asError
  else if AValue = 'critical' then Result := asCritical
  else Result := asInfo;
end;

//------------------------------------------------------------------------------
// TAuditActionHelper
//------------------------------------------------------------------------------

function TAuditActionHelper.ToString: string;
begin
  case Self of
    aaSystemStart:        Result := 'system.start';
    aaSystemStop:         Result := 'system.stop';
    aaConfigChange:       Result := 'system.config_change';
    aaWorkflowCreated:    Result := 'workflow.created';
    aaWorkflowStarted:    Result := 'workflow.started';
    aaWorkflowCompleted:  Result := 'workflow.completed';
    aaWorkflowFailed:     Result := 'workflow.failed';
    aaWorkflowCancelled:  Result := 'workflow.cancelled';
    aaWorkflowPaused:     Result := 'workflow.paused';
    aaWorkflowResumed:    Result := 'workflow.resumed';
    aaStepStarted:        Result := 'workflow.step_started';
    aaStepCompleted:      Result := 'workflow.step_completed';
    aaStepFailed:         Result := 'workflow.step_failed';
    aaSessionCreated:     Result := 'session.created';
    aaSessionClosed:      Result := 'session.closed';
    aaSessionExpired:     Result := 'session.expired';
    aaMessageAdded:       Result := 'session.message_added';
    aaLoginSuccess:       Result := 'security.login_success';
    aaLoginFailed:        Result := 'security.login_failed';
    aaLogout:             Result := 'security.logout';
    aaAccessDenied:       Result := 'security.access_denied';
    aaRateLimited:        Result := 'security.rate_limited';
    aaSensitiveDataAccess: Result := 'security.sensitive_data_access';
    aaLLMRequest:         Result := 'llm.request';
    aaLLMResponse:        Result := 'llm.response';
    aaLLMError:           Result := 'llm.error';
    aaTokenUsage:         Result := 'llm.token_usage';
    aaSkillExecuted:      Result := 'skill.executed';
    aaSkillFailed:        Result := 'skill.failed';
    aaSkillTimeout:       Result := 'skill.timeout';
    aaUserInput:          Result := 'user.input';
    aaUserAction:         Result := 'user.action';
    aaException:          Result := 'error.exception';
    aaValidationError:    Result := 'error.validation';
  else
    Result := 'unknown';
  end;
end;

function TAuditActionHelper.GetCategory: TAuditCategory;
begin
  case Self of
    aaSystemStart, aaSystemStop, aaConfigChange:
      Result := acSystem;
    aaWorkflowCreated, aaWorkflowStarted, aaWorkflowCompleted,
    aaWorkflowFailed, aaWorkflowCancelled, aaWorkflowPaused,
    aaWorkflowResumed, aaStepStarted, aaStepCompleted, aaStepFailed:
      Result := acWorkflow;
    aaSessionCreated, aaSessionClosed, aaSessionExpired, aaMessageAdded:
      Result := acSession;
    aaLoginSuccess, aaLoginFailed, aaLogout, aaAccessDenied,
    aaRateLimited, aaSensitiveDataAccess:
      Result := acSecurity;
    aaLLMRequest, aaLLMResponse, aaLLMError, aaTokenUsage:
      Result := acLLM;
    aaSkillExecuted, aaSkillFailed, aaSkillTimeout:
      Result := acSkill;
    aaUserInput, aaUserAction:
      Result := acUser;
    aaException, aaValidationError:
      Result := acError;
  else
    Result := acSystem;
  end;
end;

class function TAuditActionHelper.FromString(const AValue: string): TAuditAction;
begin
  if AValue = 'system.start' then Result := aaSystemStart
  else if AValue = 'system.stop' then Result := aaSystemStop
  else if AValue = 'system.config_change' then Result := aaConfigChange
  else if AValue = 'workflow.created' then Result := aaWorkflowCreated
  else if AValue = 'workflow.started' then Result := aaWorkflowStarted
  else if AValue = 'workflow.completed' then Result := aaWorkflowCompleted
  else if AValue = 'workflow.failed' then Result := aaWorkflowFailed
  else if AValue = 'workflow.cancelled' then Result := aaWorkflowCancelled
  else if AValue = 'workflow.paused' then Result := aaWorkflowPaused
  else if AValue = 'workflow.resumed' then Result := aaWorkflowResumed
  else if AValue = 'workflow.step_started' then Result := aaStepStarted
  else if AValue = 'workflow.step_completed' then Result := aaStepCompleted
  else if AValue = 'workflow.step_failed' then Result := aaStepFailed
  else if AValue = 'session.created' then Result := aaSessionCreated
  else if AValue = 'session.closed' then Result := aaSessionClosed
  else if AValue = 'session.expired' then Result := aaSessionExpired
  else if AValue = 'session.message_added' then Result := aaMessageAdded
  else if AValue = 'security.login_success' then Result := aaLoginSuccess
  else if AValue = 'security.login_failed' then Result := aaLoginFailed
  else if AValue = 'security.logout' then Result := aaLogout
  else if AValue = 'security.access_denied' then Result := aaAccessDenied
  else if AValue = 'security.rate_limited' then Result := aaRateLimited
  else if AValue = 'security.sensitive_data_access' then Result := aaSensitiveDataAccess
  else if AValue = 'llm.request' then Result := aaLLMRequest
  else if AValue = 'llm.response' then Result := aaLLMResponse
  else if AValue = 'llm.error' then Result := aaLLMError
  else if AValue = 'llm.token_usage' then Result := aaTokenUsage
  else if AValue = 'skill.executed' then Result := aaSkillExecuted
  else if AValue = 'skill.failed' then Result := aaSkillFailed
  else if AValue = 'skill.timeout' then Result := aaSkillTimeout
  else if AValue = 'user.input' then Result := aaUserInput
  else if AValue = 'user.action' then Result := aaUserAction
  else if AValue = 'error.exception' then Result := aaException
  else if AValue = 'error.validation' then Result := aaValidationError
  else Result := aaUserAction;
end;

//------------------------------------------------------------------------------
// TAuditEntry
//------------------------------------------------------------------------------

constructor TAuditEntry.Create;
begin
  inherited Create;
  FTimestamp := Now;
  FDetails := TJSONObject.Create;
  FSeverity := asInfo;
end;

destructor TAuditEntry.Destroy;
begin
  FDetails.Free;
  inherited Destroy;
end;

function TAuditEntry.Clone: TAuditEntry;
begin
  Result := TAuditEntry.Create;
  Result.FId := FId;
  Result.FTimestamp := FTimestamp;
  Result.FCategory := FCategory;
  Result.FSeverity := FSeverity;
  Result.FAction := FAction;
  Result.FUserId := FUserId;
  Result.FSessionId := FSessionId;
  Result.FWorkflowId := FWorkflowId;
  Result.FWorkflowName := FWorkflowName;
  Result.FStepId := FStepId;
  Result.FMessage := FMessage;
  Result.FDurationMs := FDurationMs;
  Result.FTokensUsed := FTokensUsed;
  Result.FSourceIP := FSourceIP;
  Result.FUserAgent := FUserAgent;
  Result.FCorrelationId := FCorrelationId;
  Result.FDetails.Free;
  Result.FDetails := FDetails.Clone as TJSONObject;
end;

function TAuditEntry.WithUser(const AUserId: string): TAuditEntry;
begin
  FUserId := AUserId;
  Result := Self;
end;

function TAuditEntry.WithSession(const ASessionId: string): TAuditEntry;
begin
  FSessionId := ASessionId;
  Result := Self;
end;

function TAuditEntry.WithWorkflow(const AWorkflowId, AWorkflowName: string): TAuditEntry;
begin
  FWorkflowId := AWorkflowId;
  FWorkflowName := AWorkflowName;
  Result := Self;
end;

function TAuditEntry.WithStep(const AStepId: string): TAuditEntry;
begin
  FStepId := AStepId;
  Result := Self;
end;

function TAuditEntry.WithDuration(ADurationMs: Integer): TAuditEntry;
begin
  FDurationMs := ADurationMs;
  Result := Self;
end;

function TAuditEntry.WithTokens(ATokens: Integer): TAuditEntry;
begin
  FTokensUsed := ATokens;
  Result := Self;
end;

function TAuditEntry.WithDetail(const AKey: string; const AValue: TValue): TAuditEntry;
begin
  FDetails.RemovePair(AKey);
  case AValue.Kind of
    tkInteger, tkInt64:
      FDetails.AddPair(AKey, TJSONNumber.Create(AValue.AsInt64));
    tkFloat:
      FDetails.AddPair(AKey, TJSONNumber.Create(AValue.AsExtended));
    tkEnumeration:
      if AValue.TypeInfo = TypeInfo(Boolean) then
        FDetails.AddPair(AKey, TJSONBool.Create(AValue.AsBoolean))
      else
        FDetails.AddPair(AKey, AValue.ToString);
  else
    FDetails.AddPair(AKey, AValue.ToString);
  end;
  Result := Self;
end;

function TAuditEntry.WithCorrelation(const ACorrelationId: string): TAuditEntry;
begin
  FCorrelationId := ACorrelationId;
  Result := Self;
end;

function TAuditEntry.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if FId > 0 then
    Result.AddPair('id', TJSONNumber.Create(FId));
  Result.AddPair('timestamp', DateToISO8601(FTimestamp, False));
  Result.AddPair('category', FCategory.ToString);
  Result.AddPair('severity', FSeverity.ToString);
  Result.AddPair('action', FAction.ToString);
  Result.AddPair('message', FMessage);

  if FUserId <> '' then
    Result.AddPair('user_id', FUserId);
  if FSessionId <> '' then
    Result.AddPair('session_id', FSessionId);
  if FWorkflowId <> '' then
    Result.AddPair('workflow_id', FWorkflowId);
  if FWorkflowName <> '' then
    Result.AddPair('workflow_name', FWorkflowName);
  if FStepId <> '' then
    Result.AddPair('step_id', FStepId);
  if FDurationMs > 0 then
    Result.AddPair('duration_ms', TJSONNumber.Create(FDurationMs));
  if FTokensUsed > 0 then
    Result.AddPair('tokens_used', TJSONNumber.Create(FTokensUsed));
  if FSourceIP <> '' then
    Result.AddPair('source_ip', FSourceIP);
  if FUserAgent <> '' then
    Result.AddPair('user_agent', FUserAgent);
  if FCorrelationId <> '' then
    Result.AddPair('correlation_id', FCorrelationId);
  if FDetails.Count > 0 then
    Result.AddPair('details', FDetails.Clone as TJSONObject);
end;

class function TAuditEntry.FromJSON(const AJSON: TJSONObject): TAuditEntry;
var
  DetailsObj: TJSONObject;
  TimestampStr: string;
begin
  Result := TAuditEntry.Create;
  Result.Id := AJSON.GetValue<Int64>('id', 0);

  TimestampStr := AJSON.GetValue<string>('timestamp', '');
  if TimestampStr <> '' then
    Result.Timestamp := ISO8601ToDate(TimestampStr, False)
  else
    Result.Timestamp := Now;

  Result.Category := TAuditCategory.FromString(AJSON.GetValue<string>('category', 'system'));
  Result.Severity := TAuditSeverity.FromString(AJSON.GetValue<string>('severity', 'info'));
  Result.Action := TAuditAction.FromString(AJSON.GetValue<string>('action', ''));
  Result.Message := AJSON.GetValue<string>('message', '');
  Result.UserId := AJSON.GetValue<string>('user_id', '');
  Result.SessionId := AJSON.GetValue<string>('session_id', '');
  Result.WorkflowId := AJSON.GetValue<string>('workflow_id', '');
  Result.WorkflowName := AJSON.GetValue<string>('workflow_name', '');
  Result.StepId := AJSON.GetValue<string>('step_id', '');
  Result.DurationMs := AJSON.GetValue<Integer>('duration_ms', 0);
  Result.TokensUsed := AJSON.GetValue<Integer>('tokens_used', 0);
  Result.SourceIP := AJSON.GetValue<string>('source_ip', '');
  Result.UserAgent := AJSON.GetValue<string>('user_agent', '');
  Result.CorrelationId := AJSON.GetValue<string>('correlation_id', '');

  if AJSON.TryGetValue<TJSONObject>('details', DetailsObj) then
  begin
    Result.FDetails.Free;
    Result.FDetails := DetailsObj.Clone as TJSONObject;
  end;
end;

//------------------------------------------------------------------------------
// TAuditQuery
//------------------------------------------------------------------------------

constructor TAuditQuery.Create;
begin
  inherited Create;
  FCategories := TList<TAuditCategory>.Create;
  FSeverities := TList<TAuditSeverity>.Create;
  FActions := TList<TAuditAction>.Create;
  FLimit := 100;
  FOffset := 0;
  FSortBy := 'timestamp';
  FSortOrder := soDescending;
end;

destructor TAuditQuery.Destroy;
begin
  FCategories.Free;
  FSeverities.Free;
  FActions.Free;
  inherited Destroy;
end;

function TAuditQuery.TimeRange(AStart, AEnd: TDateTime): TAuditQuery;
begin
  FStartTime := AStart;
  FEndTime := AEnd;
  Result := Self;
end;

function TAuditQuery.InCategory(ACategory: TAuditCategory): TAuditQuery;
begin
  if not FCategories.Contains(ACategory) then
    FCategories.Add(ACategory);
  Result := Self;
end;

function TAuditQuery.InCategories(const ACategories: array of TAuditCategory): TAuditQuery;
var
  Cat: TAuditCategory;
begin
  for Cat in ACategories do
    InCategory(Cat);
  Result := Self;
end;

function TAuditQuery.WithSeverity(ASeverity: TAuditSeverity): TAuditQuery;
begin
  if not FSeverities.Contains(ASeverity) then
    FSeverities.Add(ASeverity);
  Result := Self;
end;

function TAuditQuery.MinSeverity(ASeverity: TAuditSeverity): TAuditQuery;
var
  Sev: TAuditSeverity;
begin
  FSeverities.Clear;
  for Sev := ASeverity to High(TAuditSeverity) do
    FSeverities.Add(Sev);
  Result := Self;
end;

function TAuditQuery.ForAction(AAction: TAuditAction): TAuditQuery;
begin
  if not FActions.Contains(AAction) then
    FActions.Add(AAction);
  Result := Self;
end;

function TAuditQuery.ForUser(const AUserId: string): TAuditQuery;
begin
  FUserId := AUserId;
  Result := Self;
end;

function TAuditQuery.ForSession(const ASessionId: string): TAuditQuery;
begin
  FSessionId := ASessionId;
  Result := Self;
end;

function TAuditQuery.ForWorkflow(const AWorkflowId: string): TAuditQuery;
begin
  FWorkflowId := AWorkflowId;
  Result := Self;
end;

function TAuditQuery.ForWorkflowName(const AName: string): TAuditQuery;
begin
  FWorkflowName := AName;
  Result := Self;
end;

function TAuditQuery.WithCorrelation(const ACorrelationId: string): TAuditQuery;
begin
  FCorrelationId := ACorrelationId;
  Result := Self;
end;

function TAuditQuery.MessageLike(const APattern: string): TAuditQuery;
begin
  FMessageContains := APattern;
  Result := Self;
end;

function TAuditQuery.SlowerThan(AMinMs: Integer): TAuditQuery;
begin
  FMinDurationMs := AMinMs;
  Result := Self;
end;

function TAuditQuery.Page(AOffset, ALimit: Integer): TAuditQuery;
begin
  FOffset := AOffset;
  FLimit := ALimit;
  Result := Self;
end;

function TAuditQuery.OrderBy(const AField: string; AOrder: TSortOrder): TAuditQuery;
begin
  FSortBy := AField;
  FSortOrder := AOrder;
  Result := Self;
end;

function TAuditQuery.ToJSON: TJSONObject;
var
  CatArray, SevArray, ActArray: TJSONArray;
  Cat: TAuditCategory;
  Sev: TAuditSeverity;
  Act: TAuditAction;
begin
  Result := TJSONObject.Create;

  if FStartTime > 0 then
    Result.AddPair('start_time', DateToISO8601(FStartTime, False));
  if FEndTime > 0 then
    Result.AddPair('end_time', DateToISO8601(FEndTime, False));

  if FCategories.Count > 0 then
  begin
    CatArray := TJSONArray.Create;
    for Cat in FCategories do
      CatArray.Add(Cat.ToString);
    Result.AddPair('categories', CatArray);
  end;

  if FSeverities.Count > 0 then
  begin
    SevArray := TJSONArray.Create;
    for Sev in FSeverities do
      SevArray.Add(Sev.ToString);
    Result.AddPair('severities', SevArray);
  end;

  if FActions.Count > 0 then
  begin
    ActArray := TJSONArray.Create;
    for Act in FActions do
      ActArray.Add(Act.ToString);
    Result.AddPair('actions', ActArray);
  end;

  if FUserId <> '' then
    Result.AddPair('user_id', FUserId);
  if FSessionId <> '' then
    Result.AddPair('session_id', FSessionId);
  if FWorkflowId <> '' then
    Result.AddPair('workflow_id', FWorkflowId);
  if FCorrelationId <> '' then
    Result.AddPair('correlation_id', FCorrelationId);
  if FMessageContains <> '' then
    Result.AddPair('message_contains', FMessageContains);
  if FMinDurationMs > 0 then
    Result.AddPair('min_duration_ms', TJSONNumber.Create(FMinDurationMs));

  Result.AddPair('limit', TJSONNumber.Create(FLimit));
  Result.AddPair('offset', TJSONNumber.Create(FOffset));
  Result.AddPair('sort_by', FSortBy);
  Result.AddPair('sort_order', IfThen(FSortOrder = soAscending, 'asc', 'desc'));
end;

//------------------------------------------------------------------------------
// TAuditQueryResult
//------------------------------------------------------------------------------

constructor TAuditQueryResult.Create;
begin
  inherited Create;
  FEntries := TObjectList<TAuditEntry>.Create(True);
end;

destructor TAuditQueryResult.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

function TAuditQueryResult.ToJSON: TJSONObject;
var
  EntriesArray: TJSONArray;
  Entry: TAuditEntry;
begin
  Result := TJSONObject.Create;
  Result.AddPair('total_count', TJSONNumber.Create(FTotalCount));
  Result.AddPair('offset', TJSONNumber.Create(FOffset));
  Result.AddPair('limit', TJSONNumber.Create(FLimit));
  Result.AddPair('has_more', TJSONBool.Create(FHasMore));

  EntriesArray := TJSONArray.Create;
  for Entry in FEntries do
    EntriesArray.Add(Entry.ToJSON);
  Result.AddPair('entries', EntriesArray);
end;

//------------------------------------------------------------------------------
// TAuditStats
//------------------------------------------------------------------------------

constructor TAuditStats.Create;
begin
  inherited Create;
  FEventsByCategory := TDictionary<TAuditCategory, Int64>.Create;
  FEventsBySeverity := TDictionary<TAuditSeverity, Int64>.Create;
  FEventsByAction := TDictionary<TAuditAction, Int64>.Create;
end;

destructor TAuditStats.Destroy;
begin
  FEventsByCategory.Free;
  FEventsBySeverity.Free;
  FEventsByAction.Free;
  inherited Destroy;
end;

procedure TAuditStats.AddCategoryCount(ACategory: TAuditCategory; ACount: Int64);
var
  Current: Int64;
begin
  if FEventsByCategory.TryGetValue(ACategory, Current) then
    FEventsByCategory[ACategory] := Current + ACount
  else
    FEventsByCategory.Add(ACategory, ACount);
end;

procedure TAuditStats.AddSeverityCount(ASeverity: TAuditSeverity; ACount: Int64);
var
  Current: Int64;
begin
  if FEventsBySeverity.TryGetValue(ASeverity, Current) then
    FEventsBySeverity[ASeverity] := Current + ACount
  else
    FEventsBySeverity.Add(ASeverity, ACount);
end;

procedure TAuditStats.AddActionCount(AAction: TAuditAction; ACount: Int64);
var
  Current: Int64;
begin
  if FEventsByAction.TryGetValue(AAction, Current) then
    FEventsByAction[AAction] := Current + ACount
  else
    FEventsByAction.Add(AAction, ACount);
end;

function TAuditStats.GetCategoryCount(ACategory: TAuditCategory): Int64;
begin
  if not FEventsByCategory.TryGetValue(ACategory, Result) then
    Result := 0;
end;

function TAuditStats.GetSeverityCount(ASeverity: TAuditSeverity): Int64;
begin
  if not FEventsBySeverity.TryGetValue(ASeverity, Result) then
    Result := 0;
end;

function TAuditStats.GetActionCount(AAction: TAuditAction): Int64;
begin
  if not FEventsByAction.TryGetValue(AAction, Result) then
    Result := 0;
end;

function TAuditStats.ToJSON: TJSONObject;
var
  CatObj, SevObj, ActObj: TJSONObject;
  CatPair: TPair<TAuditCategory, Int64>;
  SevPair: TPair<TAuditSeverity, Int64>;
  ActPair: TPair<TAuditAction, Int64>;
begin
  Result := TJSONObject.Create;

  Result.AddPair('start_time', DateToISO8601(FStartTime, False));
  Result.AddPair('end_time', DateToISO8601(FEndTime, False));
  Result.AddPair('total_events', TJSONNumber.Create(FTotalEvents));
  Result.AddPair('total_tokens_used', TJSONNumber.Create(FTotalTokensUsed));
  Result.AddPair('total_duration_ms', TJSONNumber.Create(FTotalDurationMs));
  Result.AddPair('avg_duration_ms', TJSONNumber.Create(FAvgDurationMs));
  Result.AddPair('error_count', TJSONNumber.Create(FErrorCount));
  Result.AddPair('unique_users', TJSONNumber.Create(FUniqueUsers));
  Result.AddPair('unique_sessions', TJSONNumber.Create(FUniqueSessions));
  Result.AddPair('unique_workflows', TJSONNumber.Create(FUniqueWorkflows));

  CatObj := TJSONObject.Create;
  for CatPair in FEventsByCategory do
    CatObj.AddPair(CatPair.Key.ToString, TJSONNumber.Create(CatPair.Value));
  Result.AddPair('events_by_category', CatObj);

  SevObj := TJSONObject.Create;
  for SevPair in FEventsBySeverity do
    SevObj.AddPair(SevPair.Key.ToString, TJSONNumber.Create(SevPair.Value));
  Result.AddPair('events_by_severity', SevObj);

  ActObj := TJSONObject.Create;
  for ActPair in FEventsByAction do
    ActObj.AddPair(ActPair.Key.ToString, TJSONNumber.Create(ActPair.Value));
  Result.AddPair('events_by_action', ActObj);
end;

//------------------------------------------------------------------------------
// TAuditReport
//------------------------------------------------------------------------------

constructor TAuditReport.Create;
begin
  inherited Create;
  FStats := TAuditStats.Create;
  FTopErrors := TObjectList<TAuditEntry>.Create(True);
  FSlowestOperations := TObjectList<TAuditEntry>.Create(True);
  FGeneratedAt := Now;
  FFormat := rfJSON;
end;

destructor TAuditReport.Destroy;
begin
  FStats.Free;
  FTopErrors.Free;
  FSlowestOperations.Free;
  inherited Destroy;
end;

function TAuditReport.ToJSON: TJSONObject;
var
  ErrorsArray, SlowArray: TJSONArray;
  Entry: TAuditEntry;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', FTitle);
  Result.AddPair('generated_at', DateToISO8601(FGeneratedAt, False));
  Result.AddPair('period_start', DateToISO8601(FPeriodStart, False));
  Result.AddPair('period_end', DateToISO8601(FPeriodEnd, False));
  Result.AddPair('stats', FStats.ToJSON);

  ErrorsArray := TJSONArray.Create;
  for Entry in FTopErrors do
    ErrorsArray.Add(Entry.ToJSON);
  Result.AddPair('top_errors', ErrorsArray);

  SlowArray := TJSONArray.Create;
  for Entry in FSlowestOperations do
    SlowArray.Add(Entry.ToJSON);
  Result.AddPair('slowest_operations', SlowArray);

  if FContent <> '' then
    Result.AddPair('content', FContent);
end;

//------------------------------------------------------------------------------
// Factory functions
//------------------------------------------------------------------------------

function CreateAuditEntry(AAction: TAuditAction; const AMessage: string;
  ASeverity: TAuditSeverity): TAuditEntry;
begin
  Result := TAuditEntry.Create;
  Result.Action := AAction;
  Result.Category := AAction.GetCategory;
  Result.Severity := ASeverity;
  Result.Message := AMessage;
end;

function CreateSystemEntry(AAction: TAuditAction; const AMessage: string): TAuditEntry;
begin
  Result := CreateAuditEntry(AAction, AMessage, asInfo);
end;

function CreateWorkflowEntry(AAction: TAuditAction; const AWorkflowId, AWorkflowName, AMessage: string): TAuditEntry;
begin
  Result := CreateAuditEntry(AAction, AMessage, asInfo);
  Result.WorkflowId := AWorkflowId;
  Result.WorkflowName := AWorkflowName;
end;

function CreateSessionEntry(AAction: TAuditAction; const ASessionId, AUserId, AMessage: string): TAuditEntry;
begin
  Result := CreateAuditEntry(AAction, AMessage, asInfo);
  Result.SessionId := ASessionId;
  Result.UserId := AUserId;
end;

function CreateSecurityEntry(AAction: TAuditAction; const AUserId, AMessage: string;
  ASeverity: TAuditSeverity): TAuditEntry;
begin
  Result := CreateAuditEntry(AAction, AMessage, ASeverity);
  Result.UserId := AUserId;
end;

function CreateLLMEntry(AAction: TAuditAction; const AMessage: string;
  ATokens: Integer; ADurationMs: Integer): TAuditEntry;
begin
  Result := CreateAuditEntry(AAction, AMessage, asInfo);
  Result.TokensUsed := ATokens;
  Result.DurationMs := ADurationMs;
end;

function CreateErrorEntry(const AMessage: string; const AException: Exception): TAuditEntry;
begin
  Result := CreateAuditEntry(aaException, AMessage, asError);
  if Assigned(AException) then
  begin
    Result.WithDetail('exception_class', AException.ClassName);
    Result.WithDetail('exception_message', AException.Message);
  end;
end;

end.
