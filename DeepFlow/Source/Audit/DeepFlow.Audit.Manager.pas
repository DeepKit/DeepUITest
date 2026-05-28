(*******************************************************************************
                                                                               
  UniFlow Audit Manager                                                        
  Central audit logging manager with report generation                         
                                                                               
  Features:                                                                    
  - Centralized audit logging API                                              
  - Multiple storage backends                                                  
  - Report generation (Text, HTML, JSON, CSV)                                  
  - Real-time event subscriptions                                              
                                                                               
*******************************************************************************)

unit UniFlow.Audit.Manager;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs,
  UniFlow.Audit.Types,
  UniFlow.Audit.Store;

type
  //----------------------------------------------------------------------------
  // Event types
  //----------------------------------------------------------------------------

  TAuditEventHandler = reference to procedure(const AEntry: TAuditEntry);
  TAuditFilterPredicate = reference to function(const AEntry: TAuditEntry): Boolean;

  //----------------------------------------------------------------------------
  // TAuditSubscription - Event subscription
  //----------------------------------------------------------------------------

  TAuditSubscription = class
  private
    FId: string;
    FHandler: TAuditEventHandler;
    FFilter: TAuditFilterPredicate;
    FCategories: TList<TAuditCategory>;
    FMinSeverity: TAuditSeverity;
  public
    constructor Create;
    destructor Destroy; override;

    function Matches(const AEntry: TAuditEntry): Boolean;

    property Id: string read FId write FId;
    property Handler: TAuditEventHandler read FHandler write FHandler;
    property Filter: TAuditFilterPredicate read FFilter write FFilter;
    property Categories: TList<TAuditCategory> read FCategories;
    property MinSeverity: TAuditSeverity read FMinSeverity write FMinSeverity;
  end;

  //----------------------------------------------------------------------------
  // TAuditManager - Central audit manager
  //----------------------------------------------------------------------------

  TAuditManager = class
  private
    FStore: IAuditStore;
    FSubscriptions: TObjectList<TAuditSubscription>;
    FLock: TCriticalSection;
    FEnabled: Boolean;
    FMinLogLevel: TAuditSeverity;
    FDefaultUserId: string;
    FDefaultSessionId: string;
    FCorrelationId: string;
    FSanitizeEnabled: Boolean;  // SEC-002: 启用日志脱敏

    procedure NotifySubscribers(const AEntry: TAuditEntry);
    function SanitizeMessage(const AMessage: string): string;  // SEC-002: 消息脱敏
  public
    constructor Create(AStore: IAuditStore);
    destructor Destroy; override;

    //--------------------------------------------------------------------------
    // Configuration
    //--------------------------------------------------------------------------

    procedure Enable;
    procedure Disable;
    procedure SetMinLogLevel(ASeverity: TAuditSeverity);
    procedure SetDefaultContext(const AUserId, ASessionId: string);
    procedure SetCorrelationId(const ACorrelationId: string);
    function GenerateCorrelationId: string;

    //--------------------------------------------------------------------------
    // Logging API
    //--------------------------------------------------------------------------

    procedure Log(const AEntry: TAuditEntry);

    // Convenience methods
    procedure LogSystem(AAction: TAuditAction; const AMessage: string);
    procedure LogWorkflow(AAction: TAuditAction; const AWorkflowId, AWorkflowName, AMessage: string);
    procedure LogSession(AAction: TAuditAction; const ASessionId, AUserId, AMessage: string);
    procedure LogSecurity(AAction: TAuditAction; const AUserId, AMessage: string;
      ASeverity: TAuditSeverity = asWarning);
    procedure LogLLM(AAction: TAuditAction; const AMessage: string;
      ATokens: Integer; ADurationMs: Integer);
    procedure LogSkill(AAction: TAuditAction; const ASkillName, AMessage: string;
      ADurationMs: Integer);
    procedure LogError(const AMessage: string; const AException: Exception = nil);
    procedure LogDebug(const AMessage: string);
    procedure LogInfo(const AMessage: string);
    procedure LogWarning(const AMessage: string);

    //--------------------------------------------------------------------------
    // Querying
    //--------------------------------------------------------------------------

    function Query(const AQuery: TAuditQuery): TAuditQueryResult;
    function GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
    function GetById(AId: Int64): TAuditEntry;
    function GetRecent(ACount: Integer = 100): TAuditQueryResult;
    function GetErrors(AStartTime, AEndTime: TDateTime; ALimit: Integer = 100): TAuditQueryResult;
    function GetByCorrelation(const ACorrelationId: string): TAuditQueryResult;

    //--------------------------------------------------------------------------
    // Subscriptions
    //--------------------------------------------------------------------------

    function Subscribe(const AHandler: TAuditEventHandler): string; overload;
    function Subscribe(const AHandler: TAuditEventHandler;
      const ACategories: array of TAuditCategory): string; overload;
    function Subscribe(const AHandler: TAuditEventHandler;
      AMinSeverity: TAuditSeverity): string; overload;
    function Subscribe(const AHandler: TAuditEventHandler;
      const AFilter: TAuditFilterPredicate): string; overload;
    procedure Unsubscribe(const ASubscriptionId: string);

    //--------------------------------------------------------------------------
    // Maintenance
    //--------------------------------------------------------------------------

    procedure Cleanup(ARetentionDays: Integer);
    function Count: Int64;

    //--------------------------------------------------------------------------
    // Properties
    //--------------------------------------------------------------------------

    property Store: IAuditStore read FStore;
    property Enabled: Boolean read FEnabled;
    property MinLogLevel: TAuditSeverity read FMinLogLevel;
    property CorrelationId: string read FCorrelationId;
    /// <summary>SEC-002: 启用审计日志敏感信息脱敏</summary>
    property SanitizeEnabled: Boolean read FSanitizeEnabled write FSanitizeEnabled;
  end;

  //----------------------------------------------------------------------------
  // TAuditReportGenerator - Generate audit reports
  //----------------------------------------------------------------------------

  TAuditReportGenerator = class
  private
    FManager: TAuditManager;

    function GenerateTextReport(const AStats: TAuditStats;
      const AErrors, ASlowest: TAuditQueryResult): string;
    function GenerateHTMLReport(const AStats: TAuditStats;
      const AErrors, ASlowest: TAuditQueryResult): string;
    function GenerateCSVReport(const AEntries: TAuditQueryResult): string;
  public
    constructor Create(AManager: TAuditManager);

    /// <summary>Generate a summary report for a time period</summary>
    function GenerateSummaryReport(AStartTime, AEndTime: TDateTime;
      AFormat: TReportFormat = rfJSON): TAuditReport;

    /// <summary>Generate a detailed report with all entries</summary>
    function GenerateDetailedReport(const AQuery: TAuditQuery;
      AFormat: TReportFormat = rfJSON): TAuditReport;

    /// <summary>Generate an error report</summary>
    function GenerateErrorReport(AStartTime, AEndTime: TDateTime;
      AFormat: TReportFormat = rfJSON): TAuditReport;

    /// <summary>Generate a performance report</summary>
    function GeneratePerformanceReport(AStartTime, AEndTime: TDateTime;
      AFormat: TReportFormat = rfJSON): TAuditReport;

    /// <summary>Generate a security audit report</summary>
    function GenerateSecurityReport(AStartTime, AEndTime: TDateTime;
      AFormat: TReportFormat = rfJSON): TAuditReport;

    /// <summary>Export entries to CSV</summary>
    function ExportToCSV(const AQuery: TAuditQuery): string;

    /// <summary>Export entries to JSON Lines format</summary>
    function ExportToJSONL(const AQuery: TAuditQuery): string;
  end;

  //----------------------------------------------------------------------------
  // Global instance
  //----------------------------------------------------------------------------

var
  DefaultAuditManager: TAuditManager;

  /// <summary>Initialize global audit manager</summary>
  procedure InitializeAuditManager(AStore: IAuditStore);

  /// <summary>Finalize global audit manager</summary>
  procedure FinalizeAuditManager;

  /// <summary>Get global audit manager (creates memory store if not initialized)</summary>
  function AuditManager: TAuditManager;

implementation

uses
  System.DateUtils,
  System.StrUtils;

//------------------------------------------------------------------------------
// TAuditSubscription
//------------------------------------------------------------------------------

constructor TAuditSubscription.Create;
begin
  inherited Create;
  FId := TGUID.NewGuid.ToString;
  FCategories := TList<TAuditCategory>.Create;
  FMinSeverity := asDebug;
end;

destructor TAuditSubscription.Destroy;
begin
  FCategories.Free;
  inherited Destroy;
end;

function TAuditSubscription.Matches(const AEntry: TAuditEntry): Boolean;
begin
  // Check severity
  if Ord(AEntry.Severity) < Ord(FMinSeverity) then
    Exit(False);

  // Check categories
  if (FCategories.Count > 0) and not FCategories.Contains(AEntry.Category) then
    Exit(False);

  // Check custom filter
  if Assigned(FFilter) then
    Exit(FFilter(AEntry));

  Result := True;
end;

//------------------------------------------------------------------------------
// TAuditManager
//------------------------------------------------------------------------------

constructor TAuditManager.Create(AStore: IAuditStore);
begin
  inherited Create;
  FStore := AStore;
  FSubscriptions := TObjectList<TAuditSubscription>.Create(True);
  FLock := TCriticalSection.Create;
  FEnabled := True;
  FMinLogLevel := asDebug;
  FSanitizeEnabled := True;  // SEC-002: 默认启用脱敏
end;

function TAuditManager.SanitizeMessage(const AMessage: string): string;
var
  SensitivePatterns: TArray<string>;
  Pattern: string;
  I: Integer;
begin
  // SEC-002: 简单的敏感信息脱敏
  Result := AMessage;
  if not FSanitizeEnabled then Exit;
  
  // 敏感模式列表
  SensitivePatterns := ['password', 'passwd', 'pwd', 'secret', 'token', 
    'api_key', 'apikey', 'authorization', 'credential', 'private_key'];
  
  // 对每个模式进行脱�?
  for Pattern in SensitivePatterns do
  begin
    // 查找并替�?pattern=value �?pattern:value 模式
    I := Pos(LowerCase(Pattern), LowerCase(Result));
    while I > 0 do
    begin
      // 查找到值的结束位置（空格、逗号、引号结束）
      var StartPos := I + Length(Pattern);
      // 跳过分隔�?(=, :, 空格)
      while (StartPos <= Length(Result)) and CharInSet(Result[StartPos], ['=', ':', ' ', '"', '''']) do
        Inc(StartPos);
      
      var EndPos := StartPos;
      while (EndPos <= Length(Result)) and not CharInSet(Result[EndPos], [' ', ',', '}', ']', '"', '''', #13, #10]) do
        Inc(EndPos);
      
      // 替换敏感�?
      if EndPos > StartPos then
        Result := Copy(Result, 1, StartPos - 1) + '[REDACTED]' + Copy(Result, EndPos, MaxInt);
      
      // 继续查找下一�?
      I := Pos(LowerCase(Pattern), LowerCase(Result));
      if I <= StartPos then Break;  // 避免无限循环
    end;
  end;
end;

destructor TAuditManager.Destroy;
begin
  FSubscriptions.Free;
  FLock.Free;
  FStore := nil;
  inherited Destroy;
end;

procedure TAuditManager.Enable;
begin
  FEnabled := True;
end;

procedure TAuditManager.Disable;
begin
  FEnabled := False;
end;

procedure TAuditManager.SetMinLogLevel(ASeverity: TAuditSeverity);
begin
  FMinLogLevel := ASeverity;
end;

procedure TAuditManager.SetDefaultContext(const AUserId, ASessionId: string);
begin
  FDefaultUserId := AUserId;
  FDefaultSessionId := ASessionId;
end;

procedure TAuditManager.SetCorrelationId(const ACorrelationId: string);
begin
  FCorrelationId := ACorrelationId;
end;

function TAuditManager.GenerateCorrelationId: string;
begin
  Result := TGUID.NewGuid.ToString;
  FCorrelationId := Result;
end;

procedure TAuditManager.NotifySubscribers(const AEntry: TAuditEntry);
var
  Subscription: TAuditSubscription;
begin
  FLock.Enter;
  try
    for Subscription in FSubscriptions do
    begin
      if Subscription.Matches(AEntry) and Assigned(Subscription.Handler) then
      begin
        try
          Subscription.Handler(AEntry);
        except
          // Ignore subscriber errors
        end;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAuditManager.Log(const AEntry: TAuditEntry);
begin
  if not FEnabled then
    Exit;

  if Ord(AEntry.Severity) < Ord(FMinLogLevel) then
    Exit;

  // Apply defaults
  if (AEntry.UserId = '') and (FDefaultUserId <> '') then
    AEntry.UserId := FDefaultUserId;
  if (AEntry.SessionId = '') and (FDefaultSessionId <> '') then
    AEntry.SessionId := FDefaultSessionId;
  if (AEntry.CorrelationId = '') and (FCorrelationId <> '') then
    AEntry.CorrelationId := FCorrelationId;

  // SEC-002: 审计日志脱敏
  if FSanitizeEnabled then
    AEntry.Message := SanitizeMessage(AEntry.Message);

  // Store
  FStore.Write(AEntry);

  // Notify subscribers
  NotifySubscribers(AEntry);
end;

procedure TAuditManager.LogSystem(AAction: TAuditAction; const AMessage: string);
var
  Entry: TAuditEntry;
begin
  Entry := CreateSystemEntry(AAction, AMessage);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogWorkflow(AAction: TAuditAction;
  const AWorkflowId, AWorkflowName, AMessage: string);
var
  Entry: TAuditEntry;
begin
  Entry := CreateWorkflowEntry(AAction, AWorkflowId, AWorkflowName, AMessage);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogSession(AAction: TAuditAction;
  const ASessionId, AUserId, AMessage: string);
var
  Entry: TAuditEntry;
begin
  Entry := CreateSessionEntry(AAction, ASessionId, AUserId, AMessage);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogSecurity(AAction: TAuditAction;
  const AUserId, AMessage: string; ASeverity: TAuditSeverity);
var
  Entry: TAuditEntry;
begin
  Entry := CreateSecurityEntry(AAction, AUserId, AMessage, ASeverity);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogLLM(AAction: TAuditAction; const AMessage: string;
  ATokens: Integer; ADurationMs: Integer);
var
  Entry: TAuditEntry;
begin
  Entry := CreateLLMEntry(AAction, AMessage, ATokens, ADurationMs);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogSkill(AAction: TAuditAction;
  const ASkillName, AMessage: string; ADurationMs: Integer);
var
  Entry: TAuditEntry;
begin
  Entry := CreateAuditEntry(AAction, AMessage, asInfo);
  try
    Entry.WithDetail('skill_name', ASkillName);
    Entry.WithDuration(ADurationMs);
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogError(const AMessage: string; const AException: Exception);
var
  Entry: TAuditEntry;
begin
  Entry := CreateErrorEntry(AMessage, AException);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogDebug(const AMessage: string);
var
  Entry: TAuditEntry;
begin
  Entry := CreateAuditEntry(aaUserAction, AMessage, asDebug);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogInfo(const AMessage: string);
var
  Entry: TAuditEntry;
begin
  Entry := CreateAuditEntry(aaUserAction, AMessage, asInfo);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

procedure TAuditManager.LogWarning(const AMessage: string);
var
  Entry: TAuditEntry;
begin
  Entry := CreateAuditEntry(aaUserAction, AMessage, asWarning);
  try
    Log(Entry);
  finally
    Entry.Free;
  end;
end;

function TAuditManager.Query(const AQuery: TAuditQuery): TAuditQueryResult;
begin
  Result := FStore.Query(AQuery);
end;

function TAuditManager.GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
begin
  Result := FStore.GetStats(AStartTime, AEndTime);
end;

function TAuditManager.GetById(AId: Int64): TAuditEntry;
begin
  Result := FStore.GetById(AId);
end;

function TAuditManager.GetRecent(ACount: Integer): TAuditQueryResult;
var
  Q: TAuditQuery;
begin
  Q := TAuditQuery.Create;
  try
    Q.Page(0, ACount);
    Q.OrderBy('timestamp', soDescending);
    Result := Query(Q);
  finally
    Q.Free;
  end;
end;

function TAuditManager.GetErrors(AStartTime, AEndTime: TDateTime;
  ALimit: Integer): TAuditQueryResult;
var
  Q: TAuditQuery;
begin
  Q := TAuditQuery.Create;
  try
    Q.TimeRange(AStartTime, AEndTime);
    Q.MinSeverity(asError);
    Q.Page(0, ALimit);
    Q.OrderBy('timestamp', soDescending);
    Result := Query(Q);
  finally
    Q.Free;
  end;
end;

function TAuditManager.GetByCorrelation(const ACorrelationId: string): TAuditQueryResult;
var
  Q: TAuditQuery;
begin
  Q := TAuditQuery.Create;
  try
    Q.WithCorrelation(ACorrelationId);
    Q.OrderBy('timestamp', soAscending);
    Result := Query(Q);
  finally
    Q.Free;
  end;
end;

function TAuditManager.Subscribe(const AHandler: TAuditEventHandler): string;
var
  Sub: TAuditSubscription;
begin
  Sub := TAuditSubscription.Create;
  Sub.Handler := AHandler;

  FLock.Enter;
  try
    FSubscriptions.Add(Sub);
    Result := Sub.Id;
  finally
    FLock.Leave;
  end;
end;

function TAuditManager.Subscribe(const AHandler: TAuditEventHandler;
  const ACategories: array of TAuditCategory): string;
var
  Sub: TAuditSubscription;
  Cat: TAuditCategory;
begin
  Sub := TAuditSubscription.Create;
  Sub.Handler := AHandler;
  for Cat in ACategories do
    Sub.Categories.Add(Cat);

  FLock.Enter;
  try
    FSubscriptions.Add(Sub);
    Result := Sub.Id;
  finally
    FLock.Leave;
  end;
end;

function TAuditManager.Subscribe(const AHandler: TAuditEventHandler;
  AMinSeverity: TAuditSeverity): string;
var
  Sub: TAuditSubscription;
begin
  Sub := TAuditSubscription.Create;
  Sub.Handler := AHandler;
  Sub.MinSeverity := AMinSeverity;

  FLock.Enter;
  try
    FSubscriptions.Add(Sub);
    Result := Sub.Id;
  finally
    FLock.Leave;
  end;
end;

function TAuditManager.Subscribe(const AHandler: TAuditEventHandler;
  const AFilter: TAuditFilterPredicate): string;
var
  Sub: TAuditSubscription;
begin
  Sub := TAuditSubscription.Create;
  Sub.Handler := AHandler;
  Sub.Filter := AFilter;

  FLock.Enter;
  try
    FSubscriptions.Add(Sub);
    Result := Sub.Id;
  finally
    FLock.Leave;
  end;
end;

procedure TAuditManager.Unsubscribe(const ASubscriptionId: string);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FSubscriptions.Count - 1 downto 0 do
    begin
      if FSubscriptions[I].Id = ASubscriptionId then
      begin
        FSubscriptions.Delete(I);
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAuditManager.Cleanup(ARetentionDays: Integer);
var
  CutoffDate: TDateTime;
begin
  CutoffDate := IncDay(Now, -ARetentionDays);
  FStore.DeleteBefore(CutoffDate);
end;

function TAuditManager.Count: Int64;
begin
  Result := FStore.Count;
end;

//------------------------------------------------------------------------------
// TAuditReportGenerator
//------------------------------------------------------------------------------

constructor TAuditReportGenerator.Create(AManager: TAuditManager);
begin
  inherited Create;
  FManager := AManager;
end;

function TAuditReportGenerator.GenerateTextReport(const AStats: TAuditStats;
  const AErrors, ASlowest: TAuditQueryResult): string;
var
  SB: TStringBuilder;
  Entry: TAuditEntry;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('================================================================================');
    SB.AppendLine('AUDIT REPORT');
    SB.AppendLine('================================================================================');
    SB.AppendLine;
    SB.AppendFormat('Period: %s to %s', [
      FormatDateTime('yyyy-mm-dd hh:nn:ss', AStats.StartTime),
      FormatDateTime('yyyy-mm-dd hh:nn:ss', AStats.EndTime)
    ]);
    SB.AppendLine;
    SB.AppendLine;

    SB.AppendLine('SUMMARY');
    SB.AppendLine('--------------------------------------------------------------------------------');
    SB.AppendFormat('Total Events:      %d', [AStats.TotalEvents]);
    SB.AppendLine;
    SB.AppendFormat('Total Errors:      %d', [AStats.ErrorCount]);
    SB.AppendLine;
    SB.AppendFormat('Unique Users:      %d', [AStats.UniqueUsers]);
    SB.AppendLine;
    SB.AppendFormat('Unique Sessions:   %d', [AStats.UniqueSessions]);
    SB.AppendLine;
    SB.AppendFormat('Unique Workflows:  %d', [AStats.UniqueWorkflows]);
    SB.AppendLine;
    SB.AppendFormat('Total Tokens:      %d', [AStats.TotalTokensUsed]);
    SB.AppendLine;
    SB.AppendFormat('Avg Duration:      %.2f ms', [AStats.AvgDurationMs]);
    SB.AppendLine;
    SB.AppendLine;

    if AErrors.TotalCount > 0 then
    begin
      SB.AppendLine('TOP ERRORS');
      SB.AppendLine('--------------------------------------------------------------------------------');
      for Entry in AErrors.Entries do
      begin
        SB.AppendFormat('[%s] %s: %s', [
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.Timestamp),
          Entry.Severity.ToString,
          Entry.Message
        ]);
        SB.AppendLine;
      end;
      SB.AppendLine;
    end;

    if ASlowest.TotalCount > 0 then
    begin
      SB.AppendLine('SLOWEST OPERATIONS');
      SB.AppendLine('--------------------------------------------------------------------------------');
      for Entry in ASlowest.Entries do
      begin
        SB.AppendFormat('[%s] %dms: %s', [
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.Timestamp),
          Entry.DurationMs,
          Entry.Message
        ]);
        SB.AppendLine;
      end;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TAuditReportGenerator.GenerateHTMLReport(const AStats: TAuditStats;
  const AErrors, ASlowest: TAuditQueryResult): string;
var
  SB: TStringBuilder;
  Entry: TAuditEntry;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html><head>');
    SB.AppendLine('<title>Audit Report</title>');
    SB.AppendLine('<style>');
    SB.AppendLine('body { font-family: Arial, sans-serif; margin: 20px; }');
    SB.AppendLine('h1 { color: #333; }');
    SB.AppendLine('h2 { color: #666; border-bottom: 1px solid #ccc; }');
    SB.AppendLine('table { border-collapse: collapse; width: 100%; margin: 10px 0; }');
    SB.AppendLine('th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }');
    SB.AppendLine('th { background-color: #f5f5f5; }');
    SB.AppendLine('.error { color: #d00; }');
    SB.AppendLine('.warning { color: #f80; }');
    SB.AppendLine('.metric { font-size: 24px; font-weight: bold; color: #333; }');
    SB.AppendLine('.metric-label { font-size: 12px; color: #666; }');
    SB.AppendLine('.metrics { display: flex; gap: 30px; margin: 20px 0; }');
    SB.AppendLine('.metric-box { text-align: center; }');
    SB.AppendLine('</style>');
    SB.AppendLine('</head><body>');

    SB.AppendLine('<h1>Audit Report</h1>');
    SB.AppendFormat('<p>Period: %s to %s</p>', [
      FormatDateTime('yyyy-mm-dd hh:nn:ss', AStats.StartTime),
      FormatDateTime('yyyy-mm-dd hh:nn:ss', AStats.EndTime)
    ]);

    // Metrics
    SB.AppendLine('<div class="metrics">');
    SB.AppendFormat('<div class="metric-box"><div class="metric">%d</div><div class="metric-label">Total Events</div></div>', [AStats.TotalEvents]);
    SB.AppendFormat('<div class="metric-box"><div class="metric error">%d</div><div class="metric-label">Errors</div></div>', [AStats.ErrorCount]);
    SB.AppendFormat('<div class="metric-box"><div class="metric">%d</div><div class="metric-label">Users</div></div>', [AStats.UniqueUsers]);
    SB.AppendFormat('<div class="metric-box"><div class="metric">%d</div><div class="metric-label">Tokens Used</div></div>', [AStats.TotalTokensUsed]);
    SB.AppendLine('</div>');

    // Errors table
    if AErrors.TotalCount > 0 then
    begin
      SB.AppendLine('<h2>Recent Errors</h2>');
      SB.AppendLine('<table>');
      SB.AppendLine('<tr><th>Time</th><th>Severity</th><th>Action</th><th>Message</th></tr>');
      for Entry in AErrors.Entries do
      begin
        SB.AppendFormat('<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', [
          Entry.Severity.ToString,
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.Timestamp),
          Entry.Severity.ToString,
          Entry.Action.ToString,
          Entry.Message
        ]);
      end;
      SB.AppendLine('</table>');
    end;

    // Slowest operations
    if ASlowest.TotalCount > 0 then
    begin
      SB.AppendLine('<h2>Slowest Operations</h2>');
      SB.AppendLine('<table>');
      SB.AppendLine('<tr><th>Time</th><th>Duration (ms)</th><th>Action</th><th>Message</th></tr>');
      for Entry in ASlowest.Entries do
      begin
        SB.AppendFormat('<tr><td>%s</td><td>%d</td><td>%s</td><td>%s</td></tr>', [
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.Timestamp),
          Entry.DurationMs,
          Entry.Action.ToString,
          Entry.Message
        ]);
      end;
      SB.AppendLine('</table>');
    end;

    SB.AppendLine('</body></html>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TAuditReportGenerator.GenerateCSVReport(const AEntries: TAuditQueryResult): string;
var
  SB: TStringBuilder;
  Entry: TAuditEntry;
begin
  SB := TStringBuilder.Create;
  try
    // Header
    SB.AppendLine('id,timestamp,category,severity,action,message,user_id,session_id,workflow_id,duration_ms,tokens_used');

    for Entry in AEntries.Entries do
    begin
      SB.AppendFormat('%d,"%s","%s","%s","%s","%s","%s","%s","%s",%d,%d', [
        Entry.Id,
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.Timestamp),
        Entry.Category.ToString,
        Entry.Severity.ToString,
        Entry.Action.ToString,
        StringReplace(Entry.Message, '"', '""', [rfReplaceAll]),
        Entry.UserId,
        Entry.SessionId,
        Entry.WorkflowId,
        Entry.DurationMs,
        Entry.TokensUsed
      ]);
      SB.AppendLine;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TAuditReportGenerator.GenerateSummaryReport(AStartTime, AEndTime: TDateTime;
  AFormat: TReportFormat): TAuditReport;
var
  Stats: TAuditStats;
  Errors, Slowest: TAuditQueryResult;
  ErrorQuery, SlowQuery: TAuditQuery;
begin
  Result := TAuditReport.Create;
  Result.Title := 'Audit Summary Report';
  Result.PeriodStart := AStartTime;
  Result.PeriodEnd := AEndTime;
  Result.Format := AFormat;

  // Get stats - copy values from stats
  Stats := FManager.GetStats(AStartTime, AEndTime);
  try
    Result.Stats.TotalEvents := Stats.TotalEvents;
    Result.Stats.TotalTokensUsed := Stats.TotalTokensUsed;
    Result.Stats.TotalDurationMs := Stats.TotalDurationMs;
    Result.Stats.AvgDurationMs := Stats.AvgDurationMs;
    Result.Stats.ErrorCount := Stats.ErrorCount;
    Result.Stats.UniqueUsers := Stats.UniqueUsers;
    Result.Stats.UniqueSessions := Stats.UniqueSessions;
    Result.Stats.UniqueWorkflows := Stats.UniqueWorkflows;
    Result.Stats.StartTime := Stats.StartTime;
    Result.Stats.EndTime := Stats.EndTime;
  finally
    Stats.Free;
  end;

  // Get top errors
  ErrorQuery := TAuditQuery.Create;
  try
    ErrorQuery.TimeRange(AStartTime, AEndTime);
    ErrorQuery.MinSeverity(asError);
    ErrorQuery.Page(0, 10);
    Errors := FManager.Query(ErrorQuery);
  finally
    ErrorQuery.Free;
  end;

  // Get slowest operations
  SlowQuery := TAuditQuery.Create;
  try
    SlowQuery.TimeRange(AStartTime, AEndTime);
    SlowQuery.SlowerThan(100);
    SlowQuery.Page(0, 10);
    SlowQuery.OrderBy('duration_ms', soDescending);
    Slowest := FManager.Query(SlowQuery);
  finally
    SlowQuery.Free;
  end;

  try
    // Generate content based on format
    case AFormat of
      rfText:
        Result.Content := GenerateTextReport(Stats, Errors, Slowest);
      rfHTML:
        Result.Content := GenerateHTMLReport(Stats, Errors, Slowest);
      rfJSON:
        Result.Content := Result.ToJSON.ToString;
      rfCSV:
        ; // CSV doesn't make sense for summary
    end;

    // Copy entries to report
    while Errors.Entries.Count > 0 do
    begin
      Result.TopErrors.Add(Errors.Entries.Extract(Errors.Entries.First));
    end;
    while Slowest.Entries.Count > 0 do
    begin
      Result.SlowestOperations.Add(Slowest.Entries.Extract(Slowest.Entries.First));
    end;
  finally
    Errors.Free;
    Slowest.Free;
  end;
end;

function TAuditReportGenerator.GenerateDetailedReport(const AQuery: TAuditQuery;
  AFormat: TReportFormat): TAuditReport;
var
  QueryResult: TAuditQueryResult;
begin
  Result := TAuditReport.Create;
  Result.Title := 'Detailed Audit Report';
  Result.PeriodStart := AQuery.StartTime;
  Result.PeriodEnd := AQuery.EndTime;
  Result.Format := AFormat;

  QueryResult := FManager.Query(AQuery);
  try
    case AFormat of
      rfCSV:
        Result.Content := GenerateCSVReport(QueryResult);
      rfJSON:
        Result.Content := QueryResult.ToJSON.ToString;
    else
      Result.Content := '';
    end;
  finally
    QueryResult.Free;
  end;
end;

function TAuditReportGenerator.GenerateErrorReport(AStartTime, AEndTime: TDateTime;
  AFormat: TReportFormat): TAuditReport;
var
  Q: TAuditQuery;
begin
  Q := TAuditQuery.Create;
  try
    Q.TimeRange(AStartTime, AEndTime);
    Q.MinSeverity(asError);
    Q.Page(0, 1000);
    Result := GenerateDetailedReport(Q, AFormat);
    Result.Title := 'Error Report';
  finally
    Q.Free;
  end;
end;

function TAuditReportGenerator.GeneratePerformanceReport(AStartTime, AEndTime: TDateTime;
  AFormat: TReportFormat): TAuditReport;
var
  Q: TAuditQuery;
begin
  Q := TAuditQuery.Create;
  try
    Q.TimeRange(AStartTime, AEndTime);
    Q.SlowerThan(100);
    Q.OrderBy('duration_ms', soDescending);
    Q.Page(0, 1000);
    Result := GenerateDetailedReport(Q, AFormat);
    Result.Title := 'Performance Report';
  finally
    Q.Free;
  end;
end;

function TAuditReportGenerator.GenerateSecurityReport(AStartTime, AEndTime: TDateTime;
  AFormat: TReportFormat): TAuditReport;
var
  Q: TAuditQuery;
begin
  Q := TAuditQuery.Create;
  try
    Q.TimeRange(AStartTime, AEndTime);
    Q.InCategory(acSecurity);
    Q.Page(0, 1000);
    Result := GenerateDetailedReport(Q, AFormat);
    Result.Title := 'Security Audit Report';
  finally
    Q.Free;
  end;
end;

function TAuditReportGenerator.ExportToCSV(const AQuery: TAuditQuery): string;
var
  QueryResult: TAuditQueryResult;
begin
  QueryResult := FManager.Query(AQuery);
  try
    Result := GenerateCSVReport(QueryResult);
  finally
    QueryResult.Free;
  end;
end;

function TAuditReportGenerator.ExportToJSONL(const AQuery: TAuditQuery): string;
var
  QueryResult: TAuditQueryResult;
  SB: TStringBuilder;
  Entry: TAuditEntry;
begin
  QueryResult := FManager.Query(AQuery);
  try
    SB := TStringBuilder.Create;
    try
      for Entry in QueryResult.Entries do
      begin
        SB.AppendLine(Entry.ToJSON.ToString);
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  finally
    QueryResult.Free;
  end;
end;

//------------------------------------------------------------------------------
// Global functions
//------------------------------------------------------------------------------

procedure InitializeAuditManager(AStore: IAuditStore);
begin
  FinalizeAuditManager;
  DefaultAuditManager := TAuditManager.Create(AStore);
end;

procedure FinalizeAuditManager;
begin
  FreeAndNil(DefaultAuditManager);
end;

function AuditManager: TAuditManager;
begin
  if DefaultAuditManager = nil then
    InitializeAuditManager(TMemoryAuditStore.Create);
  Result := DefaultAuditManager;
end;

end.
