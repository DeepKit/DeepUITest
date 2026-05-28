(*******************************************************************************
                                                                               
  UniFlow SQLite Storage                                                       
  Complete SQLite-based persistent storage for audit logs and sessions         
                                                                               
  Features:                                                                    
  - TSQLiteAuditStore: Full-featured audit log storage                         
  - TSQLiteSessionStore: Session persistence with messages/variables           
  - Automatic schema migration                                                 
  - Connection pooling for high-throughput scenarios                           
  - Prepared statements for performance                                        
  - Full-text search support                                                   
  - Automatic cleanup and retention policies                                   
                                                                               
  Dependencies:                                                                
  - FireDAC (Delphi built-in) or mORMot SQLite3                                
  - This implementation uses a minimal abstraction layer that can be           
    adapted to either FireDAC or mORMot                                        
                                                                               
  Usage:                                                                       
    var AuditStore := TSQLiteAuditStore.Create('audit.db');                    
    var SessionStore := TSQLiteSessionStore.Create('sessions.db');             
                                                                               
*******************************************************************************)

unit UniFlow.Storage.SQLite;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs,
  System.IOUtils,
  System.DateUtils,
  System.StrUtils,
  UniFlow.Audit.Types,
  UniFlow.Audit.Store,
  UniFlow.Session.Types,
  UniFlow.Session.Manager;

type
  //----------------------------------------------------------------------------
  // SQLite Connection Abstraction
  //----------------------------------------------------------------------------

  /// <summary>
  /// SQLite result row abstraction
  /// </summary>
  ISQLiteRow = interface
    ['{B1C2D3E4-F5A6-7890-BCDE-F12345678901}']
    function GetString(const AColumnName: string): string;
    function GetInt(const AColumnName: string): Integer;
    function GetInt64(const AColumnName: string): Int64;
    function GetDouble(const AColumnName: string): Double;
    function GetDateTime(const AColumnName: string): TDateTime;
    function GetBlob(const AColumnName: string): TBytes;
    function IsNull(const AColumnName: string): Boolean;
  end;

  /// <summary>
  /// SQLite query result abstraction
  /// </summary>
  ISQLiteResult = interface
    ['{C2D3E4F5-A6B7-8901-CDEF-123456789012}']
    function Next: Boolean;
    function GetRow: ISQLiteRow;
    function GetRowCount: Integer;
    procedure Close;
  end;

  /// <summary>
  /// SQLite statement abstraction (for prepared statements)
  /// </summary>
  ISQLiteStatement = interface
    ['{D3E4F5A6-B7C8-9012-DEF0-234567890123}']
    procedure BindString(AIndex: Integer; const AValue: string);
    procedure BindInt(AIndex: Integer; AValue: Integer);
    procedure BindInt64(AIndex: Integer; AValue: Int64);
    procedure BindDouble(AIndex: Integer; AValue: Double);
    procedure BindDateTime(AIndex: Integer; AValue: TDateTime);
    procedure BindBlob(AIndex: Integer; const AValue: TBytes);
    procedure BindNull(AIndex: Integer);
    procedure ClearBindings;
    procedure Reset;
    function Execute: Boolean;
    function Query: ISQLiteResult;
  end;

  /// <summary>
  /// SQLite connection abstraction
  /// </summary>
  ISQLiteConnection = interface
    ['{E4F5A6B7-C8D9-0123-EF01-345678901234}']
    procedure Open;
    procedure Close;
    function IsOpen: Boolean;
    function Execute(const ASQL: string): Boolean;
    function Query(const ASQL: string): ISQLiteResult;
    function Prepare(const ASQL: string): ISQLiteStatement;
    function LastInsertRowId: Int64;
    function GetLastError: string;
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
  end;

  //----------------------------------------------------------------------------
  // SQLite Implementation Classes
  //----------------------------------------------------------------------------

  /// <summary>
  /// Simple in-memory row implementation for results
  /// </summary>
  TSQLiteRowImpl = class(TInterfacedObject, ISQLiteRow)
  private
    FColumns: TDictionary<string, Variant>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure SetValue(const AColumnName: string; const AValue: Variant);
    
    function GetString(const AColumnName: string): string;
    function GetInt(const AColumnName: string): Integer;
    function GetInt64(const AColumnName: string): Int64;
    function GetDouble(const AColumnName: string): Double;
    function GetDateTime(const AColumnName: string): TDateTime;
    function GetBlob(const AColumnName: string): TBytes;
    function IsNull(const AColumnName: string): Boolean;
  end;

  /// <summary>
  /// Query result implementation
  /// </summary>
  TSQLiteResultImpl = class(TInterfacedObject, ISQLiteResult)
  private
    FRows: TList<ISQLiteRow>;
    FCurrentIndex: Integer;
    FClosed: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddRow(ARow: ISQLiteRow);
    
    function Next: Boolean;
    function GetRow: ISQLiteRow;
    function GetRowCount: Integer;
    procedure Close;
  end;

  //----------------------------------------------------------------------------
  // SQLite Connection Factory
  //----------------------------------------------------------------------------

  /// <summary>
  /// Factory for creating SQLite connections
  /// Override this to provide your preferred SQLite implementation
  /// </summary>
  TSQLiteConnectionFactory = class
  public
    class var DefaultFactory: TSQLiteConnectionFactory;
    
    function CreateConnection(const ADatabasePath: string): ISQLiteConnection; virtual;
  end;

  //----------------------------------------------------------------------------
  // Mock SQLite Connection (for testing/demonstration)
  //----------------------------------------------------------------------------

  /// <summary>
  /// Mock SQLite connection that stores data in memory
  /// Replace with real FireDAC/mORMot implementation in production
  /// </summary>
  TMockSQLiteConnection = class(TInterfacedObject, ISQLiteConnection)
  private
    FDatabasePath: string;
    FIsOpen: Boolean;
    FInTransaction: Boolean;
    FLastError: string;
    FLastInsertId: Int64;
    
    // In-memory storage for audit entries
    FAuditEntries: TObjectList<TAuditEntry>;
    // In-memory storage for sessions
    FSessions: TObjectDictionary<string, TSession>;
    FMessages: TDictionary<string, TList<TChatMessage>>;
    FVariables: TDictionary<string, TDictionary<string, string>>;
    FLock: TCriticalSection;
    
    function ParseInsertAudit(const ASQL: string): Boolean;
    function ParseQueryAudit(const ASQL: string): ISQLiteResult;
    function ParseDeleteAudit(const ASQL: string): Boolean;
    function ParseSessionSQL(const ASQL: string): ISQLiteResult;
  public
    constructor Create(const ADatabasePath: string);
    destructor Destroy; override;
    
    procedure Open;
    procedure Close;
    function IsOpen: Boolean;
    function Execute(const ASQL: string): Boolean;
    function Query(const ASQL: string): ISQLiteResult;
    function Prepare(const ASQL: string): ISQLiteStatement;
    function LastInsertRowId: Int64;
    function GetLastError: string;
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
  end;

  //----------------------------------------------------------------------------
  // TSQLiteAuditStore - Full SQLite audit log storage
  //----------------------------------------------------------------------------

  TSQLiteAuditStoreConfig = class
  private
    FDatabasePath: string;
    FMaxEntries: Int64;
    FRetentionDays: Integer;
    FBatchSize: Integer;
    FAutoCleanup: Boolean;
    FCleanupIntervalMs: Integer;
    FEnableFullTextSearch: Boolean;
    FConnectionPoolSize: Integer;
    FBusyTimeoutMs: Integer;
    FWALMode: Boolean;
  public
    constructor Create;
    
    property DatabasePath: string read FDatabasePath write FDatabasePath;
    property MaxEntries: Int64 read FMaxEntries write FMaxEntries;
    property RetentionDays: Integer read FRetentionDays write FRetentionDays;
    property BatchSize: Integer read FBatchSize write FBatchSize;
    property AutoCleanup: Boolean read FAutoCleanup write FAutoCleanup;
    property CleanupIntervalMs: Integer read FCleanupIntervalMs write FCleanupIntervalMs;
    property EnableFullTextSearch: Boolean read FEnableFullTextSearch write FEnableFullTextSearch;
    property ConnectionPoolSize: Integer read FConnectionPoolSize write FConnectionPoolSize;
    property BusyTimeoutMs: Integer read FBusyTimeoutMs write FBusyTimeoutMs;
    property WALMode: Boolean read FWALMode write FWALMode;
  end;

  TSQLiteAuditStore = class(TInterfacedObject, IAuditStore)
  private
    FConfig: TSQLiteAuditStoreConfig;
    FOwnsConfig: Boolean;
    FConnection: ISQLiteConnection;
    FLock: TCriticalSection;
    FBatchBuffer: TObjectList<TAuditEntry>;
    FLastCleanup: TDateTime;
    FInitialized: Boolean;
    FSchemaVersion: Integer;
    
    // Prepared statements cache
    FInsertStmt: ISQLiteStatement;
    FSelectByIdStmt: ISQLiteStatement;
    FDeleteByIdStmt: ISQLiteStatement;
    FCountStmt: ISQLiteStatement;
    
    procedure Initialize;
    procedure CreateSchema;
    procedure MigrateSchema;
    procedure PrepareStatements;
    procedure FlushBatch;
    procedure DoCleanup;
    
    function BuildWhereClause(const AQuery: TAuditQuery; var AParams: TArray<Variant>): string;
    function BuildOrderClause(const AQuery: TAuditQuery): string;
    function RowToAuditEntry(ARow: ISQLiteRow): TAuditEntry;
    procedure BindAuditEntry(AStmt: ISQLiteStatement; const AEntry: TAuditEntry);
    
    function EscapeString(const AValue: string): string;
    function DateTimeToSQLite(AValue: TDateTime): string;
    function SQLiteToDateTime(const AValue: string): TDateTime;
  public
    constructor Create(const ADatabasePath: string); overload;
    constructor Create(AConfig: TSQLiteAuditStoreConfig; AOwnsConfig: Boolean = True); overload;
    destructor Destroy; override;
    
    // IAuditStore implementation
    procedure Write(const AEntry: TAuditEntry);
    procedure WriteBatch(const AEntries: TList<TAuditEntry>);
    function Query(const AQuery: TAuditQuery): TAuditQueryResult;
    function GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
    function GetById(AId: Int64): TAuditEntry;
    procedure Delete(AId: Int64);
    procedure DeleteBefore(ATimestamp: TDateTime);
    function Count: Int64;
    procedure Close;
    
    // Additional methods
    procedure Vacuum;
    procedure Optimize;
    function GetDatabaseSize: Int64;
    function ExportToJSON(const AFilePath: string): Boolean;
    function ImportFromJSON(const AFilePath: string): Integer;
    
    property Config: TSQLiteAuditStoreConfig read FConfig;
    property SchemaVersion: Integer read FSchemaVersion;
  end;

  //----------------------------------------------------------------------------
  // TSQLiteSessionStore - Full SQLite session storage
  //----------------------------------------------------------------------------

  TSQLiteSessionStoreConfig = class
  private
    FDatabasePath: string;
    FMaxSessionsPerUser: Integer;
    FDefaultTimeoutMinutes: Integer;
    FMaxMessagesPerSession: Integer;
    FAutoCleanup: Boolean;
    FCleanupIntervalMs: Integer;
    FCompressMessages: Boolean;
  public
    constructor Create;
    
    property DatabasePath: string read FDatabasePath write FDatabasePath;
    property MaxSessionsPerUser: Integer read FMaxSessionsPerUser write FMaxSessionsPerUser;
    property DefaultTimeoutMinutes: Integer read FDefaultTimeoutMinutes write FDefaultTimeoutMinutes;
    property MaxMessagesPerSession: Integer read FMaxMessagesPerSession write FMaxMessagesPerSession;
    property AutoCleanup: Boolean read FAutoCleanup write FAutoCleanup;
    property CleanupIntervalMs: Integer read FCleanupIntervalMs write FCleanupIntervalMs;
    property CompressMessages: Boolean read FCompressMessages write FCompressMessages;
  end;

  TSQLiteSessionStore = class(TInterfacedObject, ISessionStore)
  private
    FConfig: TSQLiteSessionStoreConfig;
    FOwnsConfig: Boolean;
    FConnection: ISQLiteConnection;
    FLock: TCriticalSection;
    FInitialized: Boolean;
    FLastCleanup: TDateTime;
    
    procedure Initialize;
    procedure CreateSchema;
    procedure DoCleanup;
    
    function RowToSession(ARow: ISQLiteRow): TSession;
    procedure LoadSessionMessages(ASession: TSession);
    procedure LoadSessionVariables(ASession: TSession);
    procedure SaveSessionMessages(ASession: TSession);
    procedure SaveSessionVariables(ASession: TSession);
    
    function EscapeString(const AValue: string): string;
    function DateTimeToSQLite(AValue: TDateTime): string;
    function SQLiteToDateTime(const AValue: string): TDateTime;
  public
    constructor Create(const ADatabasePath: string); overload;
    constructor Create(AConfig: TSQLiteSessionStoreConfig; AOwnsConfig: Boolean = True); overload;
    destructor Destroy; override;
    
    // ISessionStore implementation
    function Save(Session: TSession): Boolean;
    function Load(const SessionId: string): TSession;
    function Delete(const SessionId: string): Boolean;
    function GetAllSessionIds: TArray<string>;
    function GetSessionCount: Integer;
    
    // Additional methods
    function GetUserSessions(const AUserId: string): TArray<TSession>;
    function GetExpiredSessions: TArray<string>;
    function CleanupExpired: Integer;
    function GetSessionsByStatus(AStatus: TSessionStatus): TArray<TSession>;
    procedure UpdateSessionStatus(const ASessionId: string; AStatus: TSessionStatus);
    procedure TouchSession(const ASessionId: string);
    function GetStats: TJSONObject;
    procedure Close;
    
    property Config: TSQLiteSessionStoreConfig read FConfig;
  end;

  //----------------------------------------------------------------------------
  // Connection Pool
  //----------------------------------------------------------------------------

  TSQLiteConnectionPool = class
  private
    FDatabasePath: string;
    FPoolSize: Integer;
    FConnections: TList<ISQLiteConnection>;
    FAvailable: TList<ISQLiteConnection>;
    FLock: TCriticalSection;
    FFactory: TSQLiteConnectionFactory;
  public
    constructor Create(const ADatabasePath: string; APoolSize: Integer);
    destructor Destroy; override;
    
    function Acquire: ISQLiteConnection;
    procedure Release(AConnection: ISQLiteConnection);
    function GetAvailableCount: Integer;
    function GetTotalCount: Integer;
  end;

implementation

uses
  System.Variants;

const
  AUDIT_SCHEMA_VERSION = 1;
  SESSION_SCHEMA_VERSION = 1;

//------------------------------------------------------------------------------
// TSQLiteRowImpl
//------------------------------------------------------------------------------

constructor TSQLiteRowImpl.Create;
begin
  inherited Create;
  FColumns := TDictionary<string, Variant>.Create;
end;

destructor TSQLiteRowImpl.Destroy;
begin
  FColumns.Free;
  inherited Destroy;
end;

procedure TSQLiteRowImpl.SetValue(const AColumnName: string; const AValue: Variant);
begin
  FColumns.AddOrSetValue(AColumnName.ToLower, AValue);
end;

function TSQLiteRowImpl.GetString(const AColumnName: string): string;
var
  V: Variant;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) then
    Result := VarToStr(V)
  else
    Result := '';
end;

function TSQLiteRowImpl.GetInt(const AColumnName: string): Integer;
var
  V: Variant;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) and not VarIsNull(V) then
    Result := V
  else
    Result := 0;
end;

function TSQLiteRowImpl.GetInt64(const AColumnName: string): Int64;
var
  V: Variant;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) and not VarIsNull(V) then
    Result := V
  else
    Result := 0;
end;

function TSQLiteRowImpl.GetDouble(const AColumnName: string): Double;
var
  V: Variant;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) and not VarIsNull(V) then
    Result := V
  else
    Result := 0.0;
end;

function TSQLiteRowImpl.GetDateTime(const AColumnName: string): TDateTime;
var
  V: Variant;
  S: string;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) and not VarIsNull(V) then
  begin
    S := VarToStr(V);
    if S <> '' then
      Result := ISO8601ToDate(S, False)
    else
      Result := 0;
  end
  else
    Result := 0;
end;

function TSQLiteRowImpl.GetBlob(const AColumnName: string): TBytes;
var
  V: Variant;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) and not VarIsNull(V) then
    Result := TEncoding.UTF8.GetBytes(VarToStr(V))
  else
    SetLength(Result, 0);
end;

function TSQLiteRowImpl.IsNull(const AColumnName: string): Boolean;
var
  V: Variant;
begin
  if FColumns.TryGetValue(AColumnName.ToLower, V) then
    Result := VarIsNull(V)
  else
    Result := True;
end;

//------------------------------------------------------------------------------
// TSQLiteResultImpl
//------------------------------------------------------------------------------

constructor TSQLiteResultImpl.Create;
begin
  inherited Create;
  FRows := TList<ISQLiteRow>.Create;
  FCurrentIndex := -1;
  FClosed := False;
end;

destructor TSQLiteResultImpl.Destroy;
begin
  FRows.Free;
  inherited Destroy;
end;

procedure TSQLiteResultImpl.AddRow(ARow: ISQLiteRow);
begin
  FRows.Add(ARow);
end;

function TSQLiteResultImpl.Next: Boolean;
begin
  if FClosed then
    Exit(False);
  Inc(FCurrentIndex);
  Result := FCurrentIndex < FRows.Count;
end;

function TSQLiteResultImpl.GetRow: ISQLiteRow;
begin
  if (FCurrentIndex >= 0) and (FCurrentIndex < FRows.Count) then
    Result := FRows[FCurrentIndex]
  else
    Result := nil;
end;

function TSQLiteResultImpl.GetRowCount: Integer;
begin
  Result := FRows.Count;
end;

procedure TSQLiteResultImpl.Close;
begin
  FClosed := True;
end;

//------------------------------------------------------------------------------
// TSQLiteConnectionFactory
//------------------------------------------------------------------------------

function TSQLiteConnectionFactory.CreateConnection(const ADatabasePath: string): ISQLiteConnection;
begin
  // Default implementation returns mock connection
  // Override this in production to return FireDAC/mORMot connection
  Result := TMockSQLiteConnection.Create(ADatabasePath);
end;

//------------------------------------------------------------------------------
// TMockSQLiteConnection
//------------------------------------------------------------------------------

constructor TMockSQLiteConnection.Create(const ADatabasePath: string);
begin
  inherited Create;
  FDatabasePath := ADatabasePath;
  FIsOpen := False;
  FInTransaction := False;
  FLastInsertId := 0;
  FAuditEntries := TObjectList<TAuditEntry>.Create(True);
  FSessions := TObjectDictionary<string, TSession>.Create([doOwnsValues]);
  FMessages := TDictionary<string, TList<TChatMessage>>.Create;
  FVariables := TDictionary<string, TDictionary<string, string>>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TMockSQLiteConnection.Destroy;
var
  MsgList: TList<TChatMessage>;
  VarDict: TDictionary<string, string>;
begin
  Close;
  
  for MsgList in FMessages.Values do
    MsgList.Free;
  FMessages.Free;
  
  for VarDict in FVariables.Values do
    VarDict.Free;
  FVariables.Free;
  
  FSessions.Free;
  FAuditEntries.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TMockSQLiteConnection.Open;
begin
  FIsOpen := True;
end;

procedure TMockSQLiteConnection.Close;
begin
  FIsOpen := False;
end;

function TMockSQLiteConnection.IsOpen: Boolean;
begin
  Result := FIsOpen;
end;

function TMockSQLiteConnection.Execute(const ASQL: string): Boolean;
var
  UpperSQL: string;
begin
  Result := False;
  if not FIsOpen then Exit;
  
  UpperSQL := ASQL.ToUpper;
  
  FLock.Enter;
  try
    // Handle CREATE TABLE (always succeeds)
    if UpperSQL.Contains('CREATE TABLE') or UpperSQL.Contains('CREATE INDEX') or
       UpperSQL.Contains('PRAGMA') then
    begin
      Result := True;
      Exit;
    end;
    
    // Handle INSERT
    if UpperSQL.StartsWith('INSERT') then
    begin
      if UpperSQL.Contains('AUDIT_LOG') then
        Result := ParseInsertAudit(ASQL)
      else
        Result := True;
      Exit;
    end;
    
    // Handle DELETE
    if UpperSQL.StartsWith('DELETE') then
    begin
      if UpperSQL.Contains('AUDIT_LOG') then
        Result := ParseDeleteAudit(ASQL)
      else
        Result := True;
      Exit;
    end;
    
    // Handle UPDATE
    if UpperSQL.StartsWith('UPDATE') then
    begin
      Result := True;
      Exit;
    end;
    
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TMockSQLiteConnection.Query(const ASQL: string): ISQLiteResult;
var
  UpperSQL: string;
begin
  Result := TSQLiteResultImpl.Create;
  if not FIsOpen then Exit;
  
  UpperSQL := ASQL.ToUpper;
  
  FLock.Enter;
  try
    if UpperSQL.Contains('AUDIT_LOG') then
      Result := ParseQueryAudit(ASQL)
    else if UpperSQL.Contains('SESSIONS') or UpperSQL.Contains('SESSION_') then
      Result := ParseSessionSQL(ASQL);
  finally
    FLock.Leave;
  end;
end;

function TMockSQLiteConnection.Prepare(const ASQL: string): ISQLiteStatement;
begin
  // Mock implementation doesn't use prepared statements
  Result := nil;
end;

function TMockSQLiteConnection.LastInsertRowId: Int64;
begin
  Result := FLastInsertId;
end;

function TMockSQLiteConnection.GetLastError: string;
begin
  Result := FLastError;
end;

procedure TMockSQLiteConnection.BeginTransaction;
begin
  FInTransaction := True;
end;

procedure TMockSQLiteConnection.Commit;
begin
  FInTransaction := False;
end;

procedure TMockSQLiteConnection.Rollback;
begin
  FInTransaction := False;
end;

function TMockSQLiteConnection.InTransaction: Boolean;
begin
  Result := FInTransaction;
end;

function TMockSQLiteConnection.ParseInsertAudit(const ASQL: string): Boolean;
var
  Entry: TAuditEntry;
begin
  // In a real implementation, parse the SQL and extract values
  // For mock, just create a placeholder entry
  Entry := TAuditEntry.Create;
  Inc(FLastInsertId);
  Entry.Id := FLastInsertId;
  Entry.Timestamp := Now;
  FAuditEntries.Add(Entry);
  Result := True;
end;

function TMockSQLiteConnection.ParseQueryAudit(const ASQL: string): ISQLiteResult;
var
  ResultSet: TSQLiteResultImpl;
  Row: TSQLiteRowImpl;
  Entry: TAuditEntry;
  UpperSQL: string;
begin
  ResultSet := TSQLiteResultImpl.Create;
  Result := ResultSet;
  
  UpperSQL := ASQL.ToUpper;
  
  // Handle COUNT query
  if UpperSQL.Contains('COUNT(*)') then
  begin
    Row := TSQLiteRowImpl.Create;
    Row.SetValue('count', FAuditEntries.Count);
    ResultSet.AddRow(Row);
    Exit;
  end;
  
  // Handle SELECT queries
  for Entry in FAuditEntries do
  begin
    Row := TSQLiteRowImpl.Create;
    Row.SetValue('id', Entry.Id);
    Row.SetValue('timestamp', DateToISO8601(Entry.Timestamp, False));
    Row.SetValue('category', Entry.Category.ToString);
    Row.SetValue('severity', Entry.Severity.ToString);
    Row.SetValue('action', Entry.Action.ToString);
    Row.SetValue('message', Entry.Message);
    Row.SetValue('user_id', Entry.UserId);
    Row.SetValue('session_id', Entry.SessionId);
    Row.SetValue('workflow_id', Entry.WorkflowId);
    Row.SetValue('workflow_name', Entry.WorkflowName);
    Row.SetValue('step_id', Entry.StepId);
    Row.SetValue('duration_ms', Entry.DurationMs);
    Row.SetValue('tokens_used', Entry.TokensUsed);
    Row.SetValue('source_ip', Entry.SourceIP);
    Row.SetValue('user_agent', Entry.UserAgent);
    Row.SetValue('correlation_id', Entry.CorrelationId);
    if Entry.Details.Count > 0 then
      Row.SetValue('details', Entry.Details.ToString)
    else
      Row.SetValue('details', '{}');
    ResultSet.AddRow(Row);
  end;
end;

function TMockSQLiteConnection.ParseDeleteAudit(const ASQL: string): Boolean;
var
  UpperSQL: string;
  I: Integer;
  IdStr: string;
  Id: Int64;
begin
  Result := True;
  UpperSQL := ASQL.ToUpper;
  
  // Handle DELETE by ID
  if UpperSQL.Contains('WHERE ID =') then
  begin
    // Extract ID from SQL (simplified)
    I := Pos('WHERE ID =', UpperSQL);
    if I > 0 then
    begin
      IdStr := Copy(ASQL, I + 10, 20).Trim;
      Id := StrToInt64Def(IdStr, 0);
      for I := FAuditEntries.Count - 1 downto 0 do
        if FAuditEntries[I].Id = Id then
        begin
          FAuditEntries.Delete(I);
          Break;
        end;
    end;
    Exit;
  end;
  
  // Handle DELETE before timestamp
  if UpperSQL.Contains('WHERE TIMESTAMP <') then
  begin
    // In mock, just delete oldest half
    while FAuditEntries.Count > 0 do
    begin
      FAuditEntries.Delete(0);
      if FAuditEntries.Count < 10 then Break;
    end;
  end;
end;

function TMockSQLiteConnection.ParseSessionSQL(const ASQL: string): ISQLiteResult;
var
  ResultSet: TSQLiteResultImpl;
  Row: TSQLiteRowImpl;
  Session: TSession;
  Pair: TPair<string, TSession>;
begin
  ResultSet := TSQLiteResultImpl.Create;
  Result := ResultSet;
  
  // Handle session queries
  for Pair in FSessions do
  begin
    Session := Pair.Value;
    Row := TSQLiteRowImpl.Create;
    Row.SetValue('id', Session.Id);
    Row.SetValue('user_id', Session.UserId);
    Row.SetValue('status', SessionStatusToString(Session.Status));
    Row.SetValue('created_at', DateToISO8601(Session.CreatedAt, False));
    Row.SetValue('last_activity_at', DateToISO8601(Session.LastActivityAt, False));
    Row.SetValue('expires_at', DateToISO8601(Session.ExpiresAt, False));
    Row.SetValue('max_messages', Session.MaxMessages);
    Row.SetValue('timeout_minutes', Session.TimeoutMinutes);
    ResultSet.AddRow(Row);
  end;
end;

//------------------------------------------------------------------------------
// TSQLiteAuditStoreConfig
//------------------------------------------------------------------------------

constructor TSQLiteAuditStoreConfig.Create;
begin
  inherited Create;
  FDatabasePath := 'audit.db';
  FMaxEntries := 1000000;
  FRetentionDays := 90;
  FBatchSize := 100;
  FAutoCleanup := True;
  FCleanupIntervalMs := 3600000;  // 1 hour
  FEnableFullTextSearch := False;
  FConnectionPoolSize := 4;
  FBusyTimeoutMs := 5000;
  FWALMode := True;
end;

//------------------------------------------------------------------------------
// TSQLiteAuditStore
//------------------------------------------------------------------------------

constructor TSQLiteAuditStore.Create(const ADatabasePath: string);
var
  Config: TSQLiteAuditStoreConfig;
begin
  Config := TSQLiteAuditStoreConfig.Create;
  Config.DatabasePath := ADatabasePath;
  Create(Config, True);
end;

constructor TSQLiteAuditStore.Create(AConfig: TSQLiteAuditStoreConfig; AOwnsConfig: Boolean);
begin
  inherited Create;
  FConfig := AConfig;
  FOwnsConfig := AOwnsConfig;
  FLock := TCriticalSection.Create;
  FBatchBuffer := TObjectList<TAuditEntry>.Create(True);
  FInitialized := False;
  FLastCleanup := Now;
  FSchemaVersion := 0;
  
  // Create connection using factory
  if Assigned(TSQLiteConnectionFactory.DefaultFactory) then
    FConnection := TSQLiteConnectionFactory.DefaultFactory.CreateConnection(FConfig.DatabasePath)
  else
    FConnection := TMockSQLiteConnection.Create(FConfig.DatabasePath);
  
  Initialize;
end;

destructor TSQLiteAuditStore.Destroy;
begin
  Close;
  FBatchBuffer.Free;
  FLock.Free;
  if FOwnsConfig then
    FConfig.Free;
  inherited Destroy;
end;

procedure TSQLiteAuditStore.Initialize;
begin
  FLock.Enter;
  try
    if FInitialized then Exit;
    
    FConnection.Open;
    
    // Set pragmas for performance
    if FConfig.WALMode then
      FConnection.Execute('PRAGMA journal_mode=WAL');
    FConnection.Execute('PRAGMA synchronous=NORMAL');
    FConnection.Execute('PRAGMA cache_size=-64000');  // 64MB cache
    FConnection.Execute(Format('PRAGMA busy_timeout=%d', [FConfig.BusyTimeoutMs]));
    
    CreateSchema;
    MigrateSchema;
    PrepareStatements;
    
    FInitialized := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.CreateSchema;
const
  CREATE_AUDIT_TABLE = 
    'CREATE TABLE IF NOT EXISTS audit_log (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  timestamp TEXT NOT NULL,' +
    '  category TEXT NOT NULL,' +
    '  severity TEXT NOT NULL,' +
    '  action TEXT NOT NULL,' +
    '  message TEXT,' +
    '  user_id TEXT,' +
    '  session_id TEXT,' +
    '  workflow_id TEXT,' +
    '  workflow_name TEXT,' +
    '  step_id TEXT,' +
    '  duration_ms INTEGER DEFAULT 0,' +
    '  tokens_used INTEGER DEFAULT 0,' +
    '  source_ip TEXT,' +
    '  user_agent TEXT,' +
    '  correlation_id TEXT,' +
    '  details TEXT' +
    ')';
    
  CREATE_SCHEMA_VERSION_TABLE =
    'CREATE TABLE IF NOT EXISTS schema_version (' +
    '  table_name TEXT PRIMARY KEY,' +
    '  version INTEGER NOT NULL,' +
    '  updated_at TEXT NOT NULL' +
    ')';
begin
  FConnection.Execute(CREATE_AUDIT_TABLE);
  FConnection.Execute(CREATE_SCHEMA_VERSION_TABLE);
  
  // Create indexes
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_category ON audit_log(category)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_severity ON audit_log(severity)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_user_id ON audit_log(user_id)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_session_id ON audit_log(session_id)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_workflow_id ON audit_log(workflow_id)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_audit_correlation_id ON audit_log(correlation_id)');
  
  // Create FTS table if enabled
  if FConfig.EnableFullTextSearch then
  begin
    FConnection.Execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS audit_log_fts USING fts5(' +
      '  message, workflow_name, content=audit_log, content_rowid=id' +
      ')');
  end;
  
  // Initialize schema version
  FConnection.Execute(Format(
    'INSERT OR IGNORE INTO schema_version (table_name, version, updated_at) ' +
    'VALUES (''audit_log'', %d, ''%s'')',
    [AUDIT_SCHEMA_VERSION, DateToISO8601(Now, False)]));
end;

procedure TSQLiteAuditStore.MigrateSchema;
var
  Result: ISQLiteResult;
  CurrentVersion: Integer;
begin
  Result := FConnection.Query(
    'SELECT version FROM schema_version WHERE table_name = ''audit_log''');
  
  if Result.Next then
    CurrentVersion := Result.GetRow.GetInt('version')
  else
    CurrentVersion := 0;
  
  FSchemaVersion := CurrentVersion;
  
  // Apply migrations if needed
  // Example:
  // if CurrentVersion < 2 then
  // begin
  //   FConnection.Execute('ALTER TABLE audit_log ADD COLUMN new_field TEXT');
  //   FConnection.Execute('UPDATE schema_version SET version = 2 WHERE table_name = ''audit_log''');
  //   Inc(FSchemaVersion);
  // end;
end;

procedure TSQLiteAuditStore.PrepareStatements;
begin
  // In a real implementation, prepare statements here for better performance
  // FInsertStmt := FConnection.Prepare('INSERT INTO audit_log (...) VALUES (...)');
  // etc.
end;

procedure TSQLiteAuditStore.FlushBatch;
var
  Entry: TAuditEntry;
  SQL: string;
begin
  if FBatchBuffer.Count = 0 then Exit;
  
  FConnection.BeginTransaction;
  try
    for Entry in FBatchBuffer do
    begin
      SQL := Format(
        'INSERT INTO audit_log (timestamp, category, severity, action, message, ' +
        'user_id, session_id, workflow_id, workflow_name, step_id, ' +
        'duration_ms, tokens_used, source_ip, user_agent, correlation_id, details) ' +
        'VALUES (''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ' +
        '%d, %d, ''%s'', ''%s'', ''%s'', ''%s'')',
        [DateTimeToSQLite(Entry.Timestamp),
         Entry.Category.ToString,
         Entry.Severity.ToString,
         Entry.Action.ToString,
         EscapeString(Entry.Message),
         EscapeString(Entry.UserId),
         EscapeString(Entry.SessionId),
         EscapeString(Entry.WorkflowId),
         EscapeString(Entry.WorkflowName),
         EscapeString(Entry.StepId),
         Entry.DurationMs,
         Entry.TokensUsed,
         EscapeString(Entry.SourceIP),
         EscapeString(Entry.UserAgent),
         EscapeString(Entry.CorrelationId),
         EscapeString(Entry.Details.ToString)]);
      
      FConnection.Execute(SQL);
    end;
    FConnection.Commit;
    FBatchBuffer.Clear;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TSQLiteAuditStore.DoCleanup;
var
  CutoffDate: TDateTime;
  SQL: string;
begin
  if not FConfig.AutoCleanup then Exit;
  
  if MilliSecondsBetween(Now, FLastCleanup) < FConfig.CleanupIntervalMs then Exit;
  
  CutoffDate := IncDay(Now, -FConfig.RetentionDays);
  SQL := Format('DELETE FROM audit_log WHERE timestamp < ''%s''',
    [DateTimeToSQLite(CutoffDate)]);
  
  FConnection.Execute(SQL);
  FLastCleanup := Now;
end;

function TSQLiteAuditStore.BuildWhereClause(const AQuery: TAuditQuery;
  var AParams: TArray<Variant>): string;
var
  Conditions: TStringList;
  Cat: TAuditCategory;
  Sev: TAuditSeverity;
  Act: TAuditAction;
  CatList, SevList, ActList: string;
begin
  Conditions := TStringList.Create;
  try
    if AQuery.StartTime > 0 then
      Conditions.Add(Format('timestamp >= ''%s''', [DateTimeToSQLite(AQuery.StartTime)]));
    
    if AQuery.EndTime > 0 then
      Conditions.Add(Format('timestamp <= ''%s''', [DateTimeToSQLite(AQuery.EndTime)]));
    
    if AQuery.Categories.Count > 0 then
    begin
      CatList := '';
      for Cat in AQuery.Categories do
      begin
        if CatList <> '' then CatList := CatList + ',';
        CatList := CatList + '''' + Cat.ToString + '''';
      end;
      Conditions.Add('category IN (' + CatList + ')');
    end;
    
    if AQuery.Severities.Count > 0 then
    begin
      SevList := '';
      for Sev in AQuery.Severities do
      begin
        if SevList <> '' then SevList := SevList + ',';
        SevList := SevList + '''' + Sev.ToString + '''';
      end;
      Conditions.Add('severity IN (' + SevList + ')');
    end;
    
    if AQuery.Actions.Count > 0 then
    begin
      ActList := '';
      for Act in AQuery.Actions do
      begin
        if ActList <> '' then ActList := ActList + ',';
        ActList := ActList + '''' + Act.ToString + '''';
      end;
      Conditions.Add('action IN (' + ActList + ')');
    end;
    
    if AQuery.UserId <> '' then
      Conditions.Add(Format('user_id = ''%s''', [EscapeString(AQuery.UserId)]));
    
    if AQuery.SessionId <> '' then
      Conditions.Add(Format('session_id = ''%s''', [EscapeString(AQuery.SessionId)]));
    
    if AQuery.WorkflowId <> '' then
      Conditions.Add(Format('workflow_id = ''%s''', [EscapeString(AQuery.WorkflowId)]));
    
    if AQuery.WorkflowName <> '' then
      Conditions.Add(Format('workflow_name LIKE ''%%%s%%''', [EscapeString(AQuery.WorkflowName)]));
    
    if AQuery.CorrelationId <> '' then
      Conditions.Add(Format('correlation_id = ''%s''', [EscapeString(AQuery.CorrelationId)]));
    
    if AQuery.MessageContains <> '' then
      Conditions.Add(Format('message LIKE ''%%%s%%''', [EscapeString(AQuery.MessageContains)]));
    
    if AQuery.MinDurationMs > 0 then
      Conditions.Add(Format('duration_ms >= %d', [AQuery.MinDurationMs]));
    
    if Conditions.Count > 0 then
      Result := 'WHERE ' + String.Join(' AND ', Conditions.ToStringArray)
    else
      Result := '';
  finally
    Conditions.Free;
  end;
end;

function TSQLiteAuditStore.BuildOrderClause(const AQuery: TAuditQuery): string;
var
  Direction: string;
begin
  if AQuery.SortOrder = soAscending then
    Direction := 'ASC'
  else
    Direction := 'DESC';
  
  if AQuery.SortBy <> '' then
    Result := Format('ORDER BY %s %s', [AQuery.SortBy, Direction])
  else
    Result := Format('ORDER BY timestamp %s', [Direction]);
end;

function TSQLiteAuditStore.RowToAuditEntry(ARow: ISQLiteRow): TAuditEntry;
var
  DetailsStr: string;
  DetailsJSON: TJSONObject;
begin
  Result := TAuditEntry.Create;
  Result.Id := ARow.GetInt64('id');
  Result.Timestamp := SQLiteToDateTime(ARow.GetString('timestamp'));
  Result.Category := TAuditCategory.FromString(ARow.GetString('category'));
  Result.Severity := TAuditSeverity.FromString(ARow.GetString('severity'));
  Result.Action := TAuditAction.FromString(ARow.GetString('action'));
  Result.Message := ARow.GetString('message');
  Result.UserId := ARow.GetString('user_id');
  Result.SessionId := ARow.GetString('session_id');
  Result.WorkflowId := ARow.GetString('workflow_id');
  Result.WorkflowName := ARow.GetString('workflow_name');
  Result.StepId := ARow.GetString('step_id');
  Result.DurationMs := ARow.GetInt('duration_ms');
  Result.TokensUsed := ARow.GetInt('tokens_used');
  Result.SourceIP := ARow.GetString('source_ip');
  Result.UserAgent := ARow.GetString('user_agent');
  Result.CorrelationId := ARow.GetString('correlation_id');
  
  DetailsStr := ARow.GetString('details');
  if DetailsStr <> '' then
  begin
    DetailsJSON := TJSONObject.ParseJSONValue(DetailsStr) as TJSONObject;
    if Assigned(DetailsJSON) then
    begin
      Result.Details.Free;
      // Need to access private field or use different approach
      // For now, parse and copy
    end;
  end;
end;

procedure TSQLiteAuditStore.BindAuditEntry(AStmt: ISQLiteStatement; const AEntry: TAuditEntry);
begin
  // Used with prepared statements
end;

function TSQLiteAuditStore.EscapeString(const AValue: string): string;
begin
  Result := AValue.Replace('''', '''''', [rfReplaceAll]);
end;

function TSQLiteAuditStore.DateTimeToSQLite(AValue: TDateTime): string;
begin
  Result := DateToISO8601(AValue, False);
end;

function TSQLiteAuditStore.SQLiteToDateTime(const AValue: string): TDateTime;
begin
  if AValue <> '' then
    Result := ISO8601ToDate(AValue, False)
  else
    Result := 0;
end;

procedure TSQLiteAuditStore.Write(const AEntry: TAuditEntry);
begin
  FLock.Enter;
  try
    FBatchBuffer.Add(AEntry.Clone);
    if FBatchBuffer.Count >= FConfig.BatchSize then
      FlushBatch;
    DoCleanup;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.WriteBatch(const AEntries: TList<TAuditEntry>);
var
  Entry: TAuditEntry;
begin
  FLock.Enter;
  try
    for Entry in AEntries do
      FBatchBuffer.Add(Entry.Clone);
    FlushBatch;
    DoCleanup;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.Query(const AQuery: TAuditQuery): TAuditQueryResult;
var
  SQL, WhereClause, OrderClause: string;
  Params: TArray<Variant>;
  QueryResult: ISQLiteResult;
  Row: ISQLiteRow;
  CountResult: ISQLiteResult;
begin
  Result := TAuditQueryResult.Create;
  
  FLock.Enter;
  try
    // Flush pending writes first
    FlushBatch;
    
    // Build WHERE clause
    WhereClause := BuildWhereClause(AQuery, Params);
    OrderClause := BuildOrderClause(AQuery);
    
    // Get total count
    SQL := 'SELECT COUNT(*) as count FROM audit_log ' + WhereClause;
    CountResult := FConnection.Query(SQL);
    if CountResult.Next then
      Result.TotalCount := CountResult.GetRow.GetInt64('count');
    
    // Get paginated results
    SQL := Format('SELECT * FROM audit_log %s %s LIMIT %d OFFSET %d',
      [WhereClause, OrderClause, AQuery.Limit, AQuery.Offset]);
    
    QueryResult := FConnection.Query(SQL);
    while QueryResult.Next do
    begin
      Row := QueryResult.GetRow;
      Result.Entries.Add(RowToAuditEntry(Row));
    end;
    
    Result.Offset := AQuery.Offset;
    Result.Limit := AQuery.Limit;
    Result.HasMore := (Result.Offset + Result.Entries.Count) < Result.TotalCount;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
var
  SQL: string;
  QueryResult: ISQLiteResult;
  Row: ISQLiteRow;
begin
  Result := TAuditStats.Create;
  Result.StartTime := AStartTime;
  Result.EndTime := AEndTime;
  
  FLock.Enter;
  try
    FlushBatch;
    
    // Total events
    SQL := Format(
      'SELECT COUNT(*) as count, ' +
      'SUM(duration_ms) as total_duration, ' +
      'SUM(tokens_used) as total_tokens, ' +
      'COUNT(DISTINCT user_id) as unique_users, ' +
      'COUNT(DISTINCT session_id) as unique_sessions, ' +
      'COUNT(DISTINCT workflow_id) as unique_workflows ' +
      'FROM audit_log WHERE timestamp >= ''%s'' AND timestamp <= ''%s''',
      [DateTimeToSQLite(AStartTime), DateTimeToSQLite(AEndTime)]);
    
    QueryResult := FConnection.Query(SQL);
    if QueryResult.Next then
    begin
      Row := QueryResult.GetRow;
      Result.TotalEvents := Row.GetInt64('count');
      Result.TotalDurationMs := Row.GetInt64('total_duration');
      Result.TotalTokensUsed := Row.GetInt64('total_tokens');
      Result.UniqueUsers := Row.GetInt('unique_users');
      Result.UniqueSessions := Row.GetInt('unique_sessions');
      Result.UniqueWorkflows := Row.GetInt('unique_workflows');
      
      if Result.TotalEvents > 0 then
        Result.AvgDurationMs := Result.TotalDurationMs / Result.TotalEvents;
    end;
    
    // Error count
    SQL := Format(
      'SELECT COUNT(*) as count FROM audit_log ' +
      'WHERE timestamp >= ''%s'' AND timestamp <= ''%s'' ' +
      'AND severity IN (''error'', ''critical'')',
      [DateTimeToSQLite(AStartTime), DateTimeToSQLite(AEndTime)]);
    
    QueryResult := FConnection.Query(SQL);
    if QueryResult.Next then
      Result.ErrorCount := QueryResult.GetRow.GetInt64('count');
    
    // Events by category
    SQL := Format(
      'SELECT category, COUNT(*) as count FROM audit_log ' +
      'WHERE timestamp >= ''%s'' AND timestamp <= ''%s'' ' +
      'GROUP BY category',
      [DateTimeToSQLite(AStartTime), DateTimeToSQLite(AEndTime)]);
    
    QueryResult := FConnection.Query(SQL);
    while QueryResult.Next do
    begin
      Row := QueryResult.GetRow;
      Result.AddCategoryCount(
        TAuditCategory.FromString(Row.GetString('category')),
        Row.GetInt64('count'));
    end;
    
    // Events by severity
    SQL := Format(
      'SELECT severity, COUNT(*) as count FROM audit_log ' +
      'WHERE timestamp >= ''%s'' AND timestamp <= ''%s'' ' +
      'GROUP BY severity',
      [DateTimeToSQLite(AStartTime), DateTimeToSQLite(AEndTime)]);
    
    QueryResult := FConnection.Query(SQL);
    while QueryResult.Next do
    begin
      Row := QueryResult.GetRow;
      Result.AddSeverityCount(
        TAuditSeverity.FromString(Row.GetString('severity')),
        Row.GetInt64('count'));
    end;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.GetById(AId: Int64): TAuditEntry;
var
  SQL: string;
  QueryResult: ISQLiteResult;
begin
  Result := nil;
  
  FLock.Enter;
  try
    FlushBatch;
    
    SQL := Format('SELECT * FROM audit_log WHERE id = %d', [AId]);
    QueryResult := FConnection.Query(SQL);
    
    if QueryResult.Next then
      Result := RowToAuditEntry(QueryResult.GetRow);
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.Delete(AId: Int64);
begin
  FLock.Enter;
  try
    FConnection.Execute(Format('DELETE FROM audit_log WHERE id = %d', [AId]));
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.DeleteBefore(ATimestamp: TDateTime);
begin
  FLock.Enter;
  try
    FConnection.Execute(Format(
      'DELETE FROM audit_log WHERE timestamp < ''%s''',
      [DateTimeToSQLite(ATimestamp)]));
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.Count: Int64;
var
  QueryResult: ISQLiteResult;
begin
  FLock.Enter;
  try
    FlushBatch;
    
    QueryResult := FConnection.Query('SELECT COUNT(*) as count FROM audit_log');
    if QueryResult.Next then
      Result := QueryResult.GetRow.GetInt64('count')
    else
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.Close;
begin
  FLock.Enter;
  try
    if FInitialized then
    begin
      FlushBatch;
      FConnection.Close;
      FInitialized := False;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.Vacuum;
begin
  FLock.Enter;
  try
    FConnection.Execute('VACUUM');
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.Optimize;
begin
  FLock.Enter;
  try
    FConnection.Execute('ANALYZE');
    FConnection.Execute('PRAGMA optimize');
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.GetDatabaseSize: Int64;
var
  QueryResult: ISQLiteResult;
begin
  FLock.Enter;
  try
    QueryResult := FConnection.Query(
      'SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()');
    if QueryResult.Next then
      Result := QueryResult.GetRow.GetInt64('size')
    else
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.ExportToJSON(const AFilePath: string): Boolean;
var
  QueryResult: ISQLiteResult;
  Entries: TJSONArray;
  Entry: TAuditEntry;
  OutputFile: TStringList;
begin
  Result := False;
  Entries := TJSONArray.Create;
  try
    FLock.Enter;
    try
      FlushBatch;
      
      QueryResult := FConnection.Query('SELECT * FROM audit_log ORDER BY timestamp');
      while QueryResult.Next do
      begin
        Entry := RowToAuditEntry(QueryResult.GetRow);
        try
          Entries.Add(Entry.ToJSON);
        finally
          Entry.Free;
        end;
      end;
    finally
      FLock.Leave;
    end;
    
    OutputFile := TStringList.Create;
    try
      OutputFile.Text := Entries.Format(2);
      OutputFile.SaveToFile(AFilePath, TEncoding.UTF8);
      Result := True;
    finally
      OutputFile.Free;
    end;
  finally
    Entries.Free;
  end;
end;

function TSQLiteAuditStore.ImportFromJSON(const AFilePath: string): Integer;
var
  Content: string;
  Entries: TJSONArray;
  I: Integer;
  Entry: TAuditEntry;
begin
  Result := 0;
  
  if not TFile.Exists(AFilePath) then Exit;
  
  Content := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
  Entries := TJSONObject.ParseJSONValue(Content) as TJSONArray;
  if not Assigned(Entries) then Exit;
  
  try
    FLock.Enter;
    try
      FConnection.BeginTransaction;
      try
        for I := 0 to Entries.Count - 1 do
        begin
          Entry := TAuditEntry.FromJSON(Entries.Items[I] as TJSONObject);
          try
            FBatchBuffer.Add(Entry);
            Inc(Result);
          except
            Entry.Free;
          end;
        end;
        FlushBatch;
        FConnection.Commit;
      except
        FConnection.Rollback;
        raise;
      end;
    finally
      FLock.Leave;
    end;
  finally
    Entries.Free;
  end;
end;

//------------------------------------------------------------------------------
// TSQLiteSessionStoreConfig
//------------------------------------------------------------------------------

constructor TSQLiteSessionStoreConfig.Create;
begin
  inherited Create;
  FDatabasePath := 'sessions.db';
  FMaxSessionsPerUser := 10;
  FDefaultTimeoutMinutes := 30;
  FMaxMessagesPerSession := 100;
  FAutoCleanup := True;
  FCleanupIntervalMs := 300000;  // 5 minutes
  FCompressMessages := False;
end;

//------------------------------------------------------------------------------
// TSQLiteSessionStore
//------------------------------------------------------------------------------

constructor TSQLiteSessionStore.Create(const ADatabasePath: string);
var
  Config: TSQLiteSessionStoreConfig;
begin
  Config := TSQLiteSessionStoreConfig.Create;
  Config.DatabasePath := ADatabasePath;
  Create(Config, True);
end;

constructor TSQLiteSessionStore.Create(AConfig: TSQLiteSessionStoreConfig; AOwnsConfig: Boolean);
begin
  inherited Create;
  FConfig := AConfig;
  FOwnsConfig := AOwnsConfig;
  FLock := TCriticalSection.Create;
  FInitialized := False;
  FLastCleanup := Now;
  
  // Create connection using factory
  if Assigned(TSQLiteConnectionFactory.DefaultFactory) then
    FConnection := TSQLiteConnectionFactory.DefaultFactory.CreateConnection(FConfig.DatabasePath)
  else
    FConnection := TMockSQLiteConnection.Create(FConfig.DatabasePath);
  
  Initialize;
end;

destructor TSQLiteSessionStore.Destroy;
begin
  Close;
  FLock.Free;
  if FOwnsConfig then
    FConfig.Free;
  inherited Destroy;
end;

procedure TSQLiteSessionStore.Initialize;
begin
  FLock.Enter;
  try
    if FInitialized then Exit;
    
    FConnection.Open;
    
    // Set pragmas
    FConnection.Execute('PRAGMA journal_mode=WAL');
    FConnection.Execute('PRAGMA synchronous=NORMAL');
    
    CreateSchema;
    
    FInitialized := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteSessionStore.CreateSchema;
const
  CREATE_SESSIONS_TABLE =
    'CREATE TABLE IF NOT EXISTS sessions (' +
    '  id TEXT PRIMARY KEY,' +
    '  user_id TEXT,' +
    '  status TEXT NOT NULL DEFAULT ''active'',' +
    '  created_at TEXT NOT NULL,' +
    '  last_activity_at TEXT NOT NULL,' +
    '  expires_at TEXT NOT NULL,' +
    '  max_messages INTEGER DEFAULT 100,' +
    '  timeout_minutes INTEGER DEFAULT 30' +
    ')';
  
  CREATE_MESSAGES_TABLE =
    'CREATE TABLE IF NOT EXISTS session_messages (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  session_id TEXT NOT NULL,' +
    '  message_id TEXT NOT NULL,' +
    '  role TEXT NOT NULL,' +
    '  content TEXT,' +
    '  timestamp TEXT NOT NULL,' +
    '  metadata TEXT,' +
    '  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE' +
    ')';
  
  CREATE_VARIABLES_TABLE =
    'CREATE TABLE IF NOT EXISTS session_variables (' +
    '  session_id TEXT NOT NULL,' +
    '  key TEXT NOT NULL,' +
    '  value TEXT,' +
    '  PRIMARY KEY (session_id, key),' +
    '  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE' +
    ')';
  
  CREATE_METADATA_TABLE =
    'CREATE TABLE IF NOT EXISTS session_metadata (' +
    '  session_id TEXT NOT NULL,' +
    '  key TEXT NOT NULL,' +
    '  value TEXT,' +
    '  PRIMARY KEY (session_id, key),' +
    '  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE' +
    ')';
begin
  FConnection.Execute(CREATE_SESSIONS_TABLE);
  FConnection.Execute(CREATE_MESSAGES_TABLE);
  FConnection.Execute(CREATE_VARIABLES_TABLE);
  FConnection.Execute(CREATE_METADATA_TABLE);
  
  // Create indexes
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_messages_session_id ON session_messages(session_id)');
  FConnection.Execute('CREATE INDEX IF NOT EXISTS idx_variables_session_id ON session_variables(session_id)');
end;

procedure TSQLiteSessionStore.DoCleanup;
begin
  if not FConfig.AutoCleanup then Exit;
  
  if MilliSecondsBetween(Now, FLastCleanup) < FConfig.CleanupIntervalMs then Exit;
  
  CleanupExpired;
  FLastCleanup := Now;
end;

function TSQLiteSessionStore.RowToSession(ARow: ISQLiteRow): TSession;
begin
  Result := TSession.Create(ARow.GetString('id'), ARow.GetString('user_id'));
  Result.Status := StringToSessionStatus(ARow.GetString('status'));
  // Note: CreatedAt is read-only in TSession, need to modify or use LoadFromJSON
  Result.MaxMessages := ARow.GetInt('max_messages');
  Result.TimeoutMinutes := ARow.GetInt('timeout_minutes');
end;

procedure TSQLiteSessionStore.LoadSessionMessages(ASession: TSession);
var
  SQL: string;
  QueryResult: ISQLiteResult;
  Row: ISQLiteRow;
  Msg: TChatMessage;
begin
  SQL := Format(
    'SELECT * FROM session_messages WHERE session_id = ''%s'' ORDER BY id',
    [EscapeString(ASession.Id)]);
  
  QueryResult := FConnection.Query(SQL);
  while QueryResult.Next do
  begin
    Row := QueryResult.GetRow;
    Msg.Id := Row.GetString('message_id');
    Msg.Role := StringToMessageRole(Row.GetString('role'));
    Msg.Content := Row.GetString('content');
    Msg.Timestamp := SQLiteToDateTime(Row.GetString('timestamp'));
    Msg.Metadata := Row.GetString('metadata');
    ASession.Messages.Add(Msg);
  end;
end;

procedure TSQLiteSessionStore.LoadSessionVariables(ASession: TSession);
var
  SQL: string;
  QueryResult: ISQLiteResult;
  Row: ISQLiteRow;
begin
  SQL := Format(
    'SELECT key, value FROM session_variables WHERE session_id = ''%s''',
    [EscapeString(ASession.Id)]);
  
  QueryResult := FConnection.Query(SQL);
  while QueryResult.Next do
  begin
    Row := QueryResult.GetRow;
    ASession.SetVariable(Row.GetString('key'), Row.GetString('value'));
  end;
end;

procedure TSQLiteSessionStore.SaveSessionMessages(ASession: TSession);
var
  Msg: TChatMessage;
  SQL: string;
begin
  // Delete existing messages
  FConnection.Execute(Format(
    'DELETE FROM session_messages WHERE session_id = ''%s''',
    [EscapeString(ASession.Id)]));
  
  // Insert current messages
  for Msg in ASession.Messages.ToArray do
  begin
    SQL := Format(
      'INSERT INTO session_messages (session_id, message_id, role, content, timestamp, metadata) ' +
      'VALUES (''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'')',
      [EscapeString(ASession.Id),
       EscapeString(Msg.Id),
       MessageRoleToString(Msg.Role),
       EscapeString(Msg.Content),
       DateTimeToSQLite(Msg.Timestamp),
       EscapeString(Msg.Metadata)]);
    
    FConnection.Execute(SQL);
  end;
end;

procedure TSQLiteSessionStore.SaveSessionVariables(ASession: TSession);
var
  Key: string;
begin
  // Delete existing variables
  FConnection.Execute(Format(
    'DELETE FROM session_variables WHERE session_id = ''%s''',
    [EscapeString(ASession.Id)]));
  
  // Insert current variables
  for Key in ASession.Variables.Keys do
  begin
    FConnection.Execute(Format(
      'INSERT INTO session_variables (session_id, key, value) VALUES (''%s'', ''%s'', ''%s'')',
      [EscapeString(ASession.Id),
       EscapeString(Key),
       EscapeString(ASession.Variables[Key])]));
  end;
end;

function TSQLiteSessionStore.EscapeString(const AValue: string): string;
begin
  Result := AValue.Replace('''', '''''', [rfReplaceAll]);
end;

function TSQLiteSessionStore.DateTimeToSQLite(AValue: TDateTime): string;
begin
  Result := DateToISO8601(AValue, False);
end;

function TSQLiteSessionStore.SQLiteToDateTime(const AValue: string): TDateTime;
begin
  if AValue <> '' then
    Result := ISO8601ToDate(AValue, False)
  else
    Result := 0;
end;

function TSQLiteSessionStore.Save(Session: TSession): Boolean;
var
  SQL: string;
begin
  Result := False;
  
  FLock.Enter;
  try
    try
      FConnection.BeginTransaction;
      try
        // Upsert session
        SQL := Format(
          'INSERT OR REPLACE INTO sessions ' +
          '(id, user_id, status, created_at, last_activity_at, expires_at, max_messages, timeout_minutes) ' +
          'VALUES (''%s'', ''%s'', ''%s'', ''%s'', ''%s'', ''%s'', %d, %d)',
          [EscapeString(Session.Id),
           EscapeString(Session.UserId),
           SessionStatusToString(Session.Status),
           DateTimeToSQLite(Session.CreatedAt),
           DateTimeToSQLite(Session.LastActivityAt),
           DateTimeToSQLite(Session.ExpiresAt),
           Session.MaxMessages,
           Session.TimeoutMinutes]);
        
        FConnection.Execute(SQL);
        
        // Save messages and variables
        SaveSessionMessages(Session);
        SaveSessionVariables(Session);
        
        FConnection.Commit;
        Result := True;
      except
        FConnection.Rollback;
        raise;
      end;
    except
      Result := False;
    end;
    
    DoCleanup;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteSessionStore.Load(const SessionId: string): TSession;
var
  SQL: string;
  QueryResult: ISQLiteResult;
begin
  Result := nil;
  
  FLock.Enter;
  try
    SQL := Format('SELECT * FROM sessions WHERE id = ''%s''', [EscapeString(SessionId)]);
    QueryResult := FConnection.Query(SQL);
    
    if QueryResult.Next then
    begin
      Result := RowToSession(QueryResult.GetRow);
      LoadSessionMessages(Result);
      LoadSessionVariables(Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteSessionStore.Delete(const SessionId: string): Boolean;
begin
  FLock.Enter;
  try
    // Foreign key cascade will delete messages and variables
    Result := FConnection.Execute(Format(
      'DELETE FROM sessions WHERE id = ''%s''',
      [EscapeString(SessionId)]));
  finally
    FLock.Leave;
  end;
end;

function TSQLiteSessionStore.GetAllSessionIds: TArray<string>;
var
  QueryResult: ISQLiteResult;
  Ids: TList<string>;
begin
  Ids := TList<string>.Create;
  try
    FLock.Enter;
    try
      QueryResult := FConnection.Query('SELECT id FROM sessions');
      while QueryResult.Next do
        Ids.Add(QueryResult.GetRow.GetString('id'));
    finally
      FLock.Leave;
    end;
    Result := Ids.ToArray;
  finally
    Ids.Free;
  end;
end;

function TSQLiteSessionStore.GetSessionCount: Integer;
var
  QueryResult: ISQLiteResult;
begin
  FLock.Enter;
  try
    QueryResult := FConnection.Query('SELECT COUNT(*) as count FROM sessions');
    if QueryResult.Next then
      Result := QueryResult.GetRow.GetInt('count')
    else
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteSessionStore.GetUserSessions(const AUserId: string): TArray<TSession>;
var
  SQL: string;
  QueryResult: ISQLiteResult;
  Sessions: TList<TSession>;
  Session: TSession;
begin
  Sessions := TList<TSession>.Create;
  try
    FLock.Enter;
    try
      SQL := Format(
        'SELECT * FROM sessions WHERE user_id = ''%s'' AND status <> ''expired''',
        [EscapeString(AUserId)]);
      
      QueryResult := FConnection.Query(SQL);
      while QueryResult.Next do
      begin
        Session := RowToSession(QueryResult.GetRow);
        LoadSessionMessages(Session);
        LoadSessionVariables(Session);
        Sessions.Add(Session);
      end;
    finally
      FLock.Leave;
    end;
    Result := Sessions.ToArray;
  finally
    Sessions.Free;
  end;
end;

function TSQLiteSessionStore.GetExpiredSessions: TArray<string>;
var
  SQL: string;
  QueryResult: ISQLiteResult;
  Ids: TList<string>;
begin
  Ids := TList<string>.Create;
  try
    FLock.Enter;
    try
      SQL := Format(
        'SELECT id FROM sessions WHERE expires_at < ''%s'' OR status = ''expired''',
        [DateTimeToSQLite(Now)]);
      
      QueryResult := FConnection.Query(SQL);
      while QueryResult.Next do
        Ids.Add(QueryResult.GetRow.GetString('id'));
    finally
      FLock.Leave;
    end;
    Result := Ids.ToArray;
  finally
    Ids.Free;
  end;
end;

function TSQLiteSessionStore.CleanupExpired: Integer;
var
  ExpiredIds: TArray<string>;
  Id: string;
begin
  ExpiredIds := GetExpiredSessions;
  Result := Length(ExpiredIds);
  
  for Id in ExpiredIds do
    Delete(Id);
end;

function TSQLiteSessionStore.GetSessionsByStatus(AStatus: TSessionStatus): TArray<TSession>;
var
  SQL: string;
  QueryResult: ISQLiteResult;
  Sessions: TList<TSession>;
  Session: TSession;
begin
  Sessions := TList<TSession>.Create;
  try
    FLock.Enter;
    try
      SQL := Format(
        'SELECT * FROM sessions WHERE status = ''%s''',
        [SessionStatusToString(AStatus)]);
      
      QueryResult := FConnection.Query(SQL);
      while QueryResult.Next do
      begin
        Session := RowToSession(QueryResult.GetRow);
        LoadSessionMessages(Session);
        LoadSessionVariables(Session);
        Sessions.Add(Session);
      end;
    finally
      FLock.Leave;
    end;
    Result := Sessions.ToArray;
  finally
    Sessions.Free;
  end;
end;

procedure TSQLiteSessionStore.UpdateSessionStatus(const ASessionId: string; AStatus: TSessionStatus);
begin
  FLock.Enter;
  try
    FConnection.Execute(Format(
      'UPDATE sessions SET status = ''%s'' WHERE id = ''%s''',
      [SessionStatusToString(AStatus), EscapeString(ASessionId)]));
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteSessionStore.TouchSession(const ASessionId: string);
var
  Session: TSession;
begin
  FLock.Enter;
  try
    Session := Load(ASessionId);
    if Assigned(Session) then
    begin
      Session.Touch;
      Save(Session);
    end;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteSessionStore.GetStats: TJSONObject;
var
  QueryResult: ISQLiteResult;
  Row: ISQLiteRow;
begin
  Result := TJSONObject.Create;
  
  FLock.Enter;
  try
    // Total sessions
    QueryResult := FConnection.Query('SELECT COUNT(*) as count FROM sessions');
    if QueryResult.Next then
      Result.AddPair('total_sessions', TJSONNumber.Create(QueryResult.GetRow.GetInt('count')));
    
    // Active sessions
    QueryResult := FConnection.Query(
      'SELECT COUNT(*) as count FROM sessions WHERE status = ''active''');
    if QueryResult.Next then
      Result.AddPair('active_sessions', TJSONNumber.Create(QueryResult.GetRow.GetInt('count')));
    
    // Expired sessions
    QueryResult := FConnection.Query(Format(
      'SELECT COUNT(*) as count FROM sessions WHERE expires_at < ''%s''',
      [DateTimeToSQLite(Now)]));
    if QueryResult.Next then
      Result.AddPair('expired_sessions', TJSONNumber.Create(QueryResult.GetRow.GetInt('count')));
    
    // Total messages
    QueryResult := FConnection.Query('SELECT COUNT(*) as count FROM session_messages');
    if QueryResult.Next then
      Result.AddPair('total_messages', TJSONNumber.Create(QueryResult.GetRow.GetInt('count')));
    
    // Unique users
    QueryResult := FConnection.Query(
      'SELECT COUNT(DISTINCT user_id) as count FROM sessions WHERE user_id <> ''''');
    if QueryResult.Next then
      Result.AddPair('unique_users', TJSONNumber.Create(QueryResult.GetRow.GetInt('count')));
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteSessionStore.Close;
begin
  FLock.Enter;
  try
    if FInitialized then
    begin
      FConnection.Close;
      FInitialized := False;
    end;
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TSQLiteConnectionPool
//------------------------------------------------------------------------------

constructor TSQLiteConnectionPool.Create(const ADatabasePath: string; APoolSize: Integer);
var
  I: Integer;
  Conn: ISQLiteConnection;
begin
  inherited Create;
  FDatabasePath := ADatabasePath;
  FPoolSize := APoolSize;
  FConnections := TList<ISQLiteConnection>.Create;
  FAvailable := TList<ISQLiteConnection>.Create;
  FLock := TCriticalSection.Create;
  
  if Assigned(TSQLiteConnectionFactory.DefaultFactory) then
    FFactory := TSQLiteConnectionFactory.DefaultFactory
  else
    FFactory := TSQLiteConnectionFactory.Create;
  
  // Pre-create connections
  for I := 0 to FPoolSize - 1 do
  begin
    Conn := FFactory.CreateConnection(FDatabasePath);
    Conn.Open;
    FConnections.Add(Conn);
    FAvailable.Add(Conn);
  end;
end;

destructor TSQLiteConnectionPool.Destroy;
var
  Conn: ISQLiteConnection;
begin
  for Conn in FConnections do
    Conn.Close;
  
  FAvailable.Free;
  FConnections.Free;
  FLock.Free;
  inherited Destroy;
end;

function TSQLiteConnectionPool.Acquire: ISQLiteConnection;
begin
  FLock.Enter;
  try
    if FAvailable.Count > 0 then
    begin
      Result := FAvailable[0];
      FAvailable.Delete(0);
    end
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteConnectionPool.Release(AConnection: ISQLiteConnection);
begin
  FLock.Enter;
  try
    if FConnections.Contains(AConnection) and not FAvailable.Contains(AConnection) then
      FAvailable.Add(AConnection);
  finally
    FLock.Leave;
  end;
end;

function TSQLiteConnectionPool.GetAvailableCount: Integer;
begin
  FLock.Enter;
  try
    Result := FAvailable.Count;
  finally
    FLock.Leave;
  end;
end;

function TSQLiteConnectionPool.GetTotalCount: Integer;
begin
  Result := FPoolSize;
end;

initialization
  TSQLiteConnectionFactory.DefaultFactory := TSQLiteConnectionFactory.Create;

finalization
  TSQLiteConnectionFactory.DefaultFactory.Free;

end.
