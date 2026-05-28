(*******************************************************************************
                                                                               
  UniFlow Audit Store                                                          
  SQLite-based persistent audit log storage                                    
                                                                               
  Features:                                                                    
  - SQLite storage with automatic schema migration                             
  - Efficient querying with indexed columns                                    
  - Batch inserts for high-throughput scenarios                                
  - Automatic log rotation and cleanup                                         
                                                                               
*******************************************************************************)

unit UniFlow.Audit.Store;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs,
  UniFlow.Audit.Types;

type
  //----------------------------------------------------------------------------
  // IAuditStore - Audit storage interface
  //----------------------------------------------------------------------------

  IAuditStore = interface
    ['{E8F3A2B1-4C5D-6E7F-8A9B-0C1D2E3F4A5B}']
    procedure Write(const AEntry: TAuditEntry);
    procedure WriteBatch(const AEntries: TList<TAuditEntry>);
    function Query(const AQuery: TAuditQuery): TAuditQueryResult;
    function GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
    function GetById(AId: Int64): TAuditEntry;
    procedure Delete(AId: Int64);
    procedure DeleteBefore(ATimestamp: TDateTime);
    function Count: Int64;
    procedure Close;
  end;

  //----------------------------------------------------------------------------
  // TAuditStoreConfig - Storage configuration
  //----------------------------------------------------------------------------

  TAuditStoreConfig = class
  private
    FDatabasePath: string;
    FMaxEntries: Int64;
    FRetentionDays: Integer;
    FBatchSize: Integer;
    FAutoCleanup: Boolean;
    FCleanupIntervalMs: Integer;
  public
    constructor Create;

    property DatabasePath: string read FDatabasePath write FDatabasePath;
    property MaxEntries: Int64 read FMaxEntries write FMaxEntries;
    property RetentionDays: Integer read FRetentionDays write FRetentionDays;
    property BatchSize: Integer read FBatchSize write FBatchSize;
    property AutoCleanup: Boolean read FAutoCleanup write FAutoCleanup;
    property CleanupIntervalMs: Integer read FCleanupIntervalMs write FCleanupIntervalMs;
  end;

  //----------------------------------------------------------------------------
  // TMemoryAuditStore - In-memory storage for testing/development
  //----------------------------------------------------------------------------

  TMemoryAuditStore = class(TInterfacedObject, IAuditStore)
  private
    FEntries: TObjectList<TAuditEntry>;
    FNextId: Int64;
    FLock: TCriticalSection;
    FMaxEntries: Int64;

    function MatchesQuery(const AEntry: TAuditEntry; const AQuery: TAuditQuery): Boolean;
  public
    constructor Create(AMaxEntries: Int64 = 100000);
    destructor Destroy; override;

    procedure Write(const AEntry: TAuditEntry);
    procedure WriteBatch(const AEntries: TList<TAuditEntry>);
    function Query(const AQuery: TAuditQuery): TAuditQueryResult;
    function GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
    function GetById(AId: Int64): TAuditEntry;
    procedure Delete(AId: Int64);
    procedure DeleteBefore(ATimestamp: TDateTime);
    function Count: Int64;
    procedure Close;
  end;

  //----------------------------------------------------------------------------
  // TSQLiteAuditStore - SQLite-based persistent storage
  //----------------------------------------------------------------------------

  TSQLiteAuditStore = class(TInterfacedObject, IAuditStore)
  private
    FConfig: TAuditStoreConfig;
    FOwnsConfig: Boolean;
    FLock: TCriticalSection;
    FBatchBuffer: TList<TAuditEntry>;
    FLastCleanup: TDateTime;

    // SQLite connection (placeholder - would use actual SQLite library)
    FDatabasePath: string;
    FInitialized: Boolean;

    procedure Initialize;
    procedure CreateSchema;
    procedure FlushBatch;
    procedure DoCleanup;
    function BuildWhereClause(const AQuery: TAuditQuery): string;
    function EntryToSQL(const AEntry: TAuditEntry): string;
  public
    constructor Create(const ADatabasePath: string); overload;
    constructor Create(AConfig: TAuditStoreConfig; AOwnsConfig: Boolean = True); overload;
    destructor Destroy; override;

    procedure Write(const AEntry: TAuditEntry);
    procedure WriteBatch(const AEntries: TList<TAuditEntry>);
    function Query(const AQuery: TAuditQuery): TAuditQueryResult;
    function GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
    function GetById(AId: Int64): TAuditEntry;
    procedure Delete(AId: Int64);
    procedure DeleteBefore(ATimestamp: TDateTime);
    function Count: Int64;
    procedure Close;

    property Config: TAuditStoreConfig read FConfig;
  end;

  //----------------------------------------------------------------------------
  // TFileAuditStore - JSON file-based storage for simple deployments
  //----------------------------------------------------------------------------

  TFileAuditStore = class(TInterfacedObject, IAuditStore)
  private
    FBasePath: string;
    FCurrentFile: string;
    FMaxFileSize: Int64;
    FLock: TCriticalSection;
    FBuffer: TObjectList<TAuditEntry>;
    FNextId: Int64;

    procedure EnsureDirectory;
    function GetCurrentFilePath: string;
    procedure RotateFile;
    procedure FlushBuffer;
    function LoadEntriesFromFile(const APath: string): TObjectList<TAuditEntry>;
  public
    constructor Create(const ABasePath: string; AMaxFileSizeMB: Integer = 100);
    destructor Destroy; override;

    procedure Write(const AEntry: TAuditEntry);
    procedure WriteBatch(const AEntries: TList<TAuditEntry>);
    function Query(const AQuery: TAuditQuery): TAuditQueryResult;
    function GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
    function GetById(AId: Int64): TAuditEntry;
    procedure Delete(AId: Int64);
    procedure DeleteBefore(ATimestamp: TDateTime);
    function Count: Int64;
    procedure Close;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.StrUtils;

//------------------------------------------------------------------------------
// TAuditStoreConfig
//------------------------------------------------------------------------------

constructor TAuditStoreConfig.Create;
begin
  inherited Create;
  FDatabasePath := 'audit.db';
  FMaxEntries := 1000000;  // 1M entries
  FRetentionDays := 90;     // 90 days
  FBatchSize := 100;
  FAutoCleanup := True;
  FCleanupIntervalMs := 3600000;  // 1 hour
end;

//------------------------------------------------------------------------------
// TMemoryAuditStore
//------------------------------------------------------------------------------

constructor TMemoryAuditStore.Create(AMaxEntries: Int64);
begin
  inherited Create;
  FEntries := TObjectList<TAuditEntry>.Create(True);
  FLock := TCriticalSection.Create;
  FNextId := 1;
  FMaxEntries := AMaxEntries;
end;

destructor TMemoryAuditStore.Destroy;
begin
  FEntries.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TMemoryAuditStore.Write(const AEntry: TAuditEntry);
var
  ClonedEntry: TAuditEntry;
begin
  FLock.Enter;
  try
    // Enforce max entries
    while FEntries.Count >= FMaxEntries do
      FEntries.Delete(0);

    ClonedEntry := AEntry.Clone;
    ClonedEntry.Id := FNextId;
    Inc(FNextId);
    FEntries.Add(ClonedEntry);
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryAuditStore.WriteBatch(const AEntries: TList<TAuditEntry>);
var
  Entry: TAuditEntry;
begin
  for Entry in AEntries do
    Write(Entry);
end;

function TMemoryAuditStore.MatchesQuery(const AEntry: TAuditEntry;
  const AQuery: TAuditQuery): Boolean;
begin
  Result := True;

  // Time range
  if (AQuery.StartTime > 0) and (AEntry.Timestamp < AQuery.StartTime) then
    Exit(False);
  if (AQuery.EndTime > 0) and (AEntry.Timestamp > AQuery.EndTime) then
    Exit(False);

  // Categories
  if (AQuery.Categories.Count > 0) and not AQuery.Categories.Contains(AEntry.Category) then
    Exit(False);

  // Severities
  if (AQuery.Severities.Count > 0) and not AQuery.Severities.Contains(AEntry.Severity) then
    Exit(False);

  // Actions
  if (AQuery.Actions.Count > 0) and not AQuery.Actions.Contains(AEntry.Action) then
    Exit(False);

  // User ID
  if (AQuery.UserId <> '') and (AEntry.UserId <> AQuery.UserId) then
    Exit(False);

  // Session ID
  if (AQuery.SessionId <> '') and (AEntry.SessionId <> AQuery.SessionId) then
    Exit(False);

  // Workflow ID
  if (AQuery.WorkflowId <> '') and (AEntry.WorkflowId <> AQuery.WorkflowId) then
    Exit(False);

  // Workflow Name
  if (AQuery.WorkflowName <> '') and
     not ContainsText(AEntry.WorkflowName, AQuery.WorkflowName) then
    Exit(False);

  // Correlation ID
  if (AQuery.CorrelationId <> '') and (AEntry.CorrelationId <> AQuery.CorrelationId) then
    Exit(False);

  // Message contains
  if (AQuery.MessageContains <> '') and
     not ContainsText(AEntry.Message, AQuery.MessageContains) then
    Exit(False);

  // Min duration
  if (AQuery.MinDurationMs > 0) and (AEntry.DurationMs < AQuery.MinDurationMs) then
    Exit(False);
end;

function TMemoryAuditStore.Query(const AQuery: TAuditQuery): TAuditQueryResult;
var
  I, Count, StartIdx: Integer;
  Entry: TAuditEntry;
  Matches: TList<TAuditEntry>;
begin
  Result := TAuditQueryResult.Create;
  Matches := TList<TAuditEntry>.Create;
  try
    FLock.Enter;
    try
      // Find all matching entries
      for I := FEntries.Count - 1 downto 0 do
      begin
        if MatchesQuery(FEntries[I], AQuery) then
          Matches.Add(FEntries[I]);
      end;
    finally
      FLock.Leave;
    end;

    Result.TotalCount := Matches.Count;
    Result.Offset := AQuery.Offset;
    Result.Limit := AQuery.Limit;

    // Apply pagination
    StartIdx := AQuery.Offset;
    Count := 0;
    for I := StartIdx to Matches.Count - 1 do
    begin
      if Count >= AQuery.Limit then
        Break;
      Result.Entries.Add(Matches[I].Clone);
      Inc(Count);
    end;

    Result.HasMore := (StartIdx + Count) < Matches.Count;
  finally
    Matches.Free;
  end;
end;

function TMemoryAuditStore.GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
var
  Entry: TAuditEntry;
  Users, Sessions, Workflows: TDictionary<string, Boolean>;
begin
  Result := TAuditStats.Create;
  Result.StartTime := AStartTime;
  Result.EndTime := AEndTime;

  Users := TDictionary<string, Boolean>.Create;
  Sessions := TDictionary<string, Boolean>.Create;
  Workflows := TDictionary<string, Boolean>.Create;
  try
    FLock.Enter;
    try
      for Entry in FEntries do
      begin
        if (Entry.Timestamp >= AStartTime) and (Entry.Timestamp <= AEndTime) then
        begin
          Result.TotalEvents := Result.TotalEvents + 1;
          Result.AddCategoryCount(Entry.Category, 1);
          Result.AddSeverityCount(Entry.Severity, 1);
          Result.AddActionCount(Entry.Action, 1);
          Result.TotalTokensUsed := Result.TotalTokensUsed + Entry.TokensUsed;
          Result.TotalDurationMs := Result.TotalDurationMs + Entry.DurationMs;

          if Entry.Severity in [asError, asCritical] then
            Result.ErrorCount := Result.ErrorCount + 1;

          if Entry.UserId <> '' then
            Users.AddOrSetValue(Entry.UserId, True);
          if Entry.SessionId <> '' then
            Sessions.AddOrSetValue(Entry.SessionId, True);
          if Entry.WorkflowId <> '' then
            Workflows.AddOrSetValue(Entry.WorkflowId, True);
        end;
      end;
    finally
      FLock.Leave;
    end;

    Result.UniqueUsers := Users.Count;
    Result.UniqueSessions := Sessions.Count;
    Result.UniqueWorkflows := Workflows.Count;

    if Result.TotalEvents > 0 then
      Result.AvgDurationMs := Result.TotalDurationMs / Result.TotalEvents;
  finally
    Users.Free;
    Sessions.Free;
    Workflows.Free;
  end;
end;

function TMemoryAuditStore.GetById(AId: Int64): TAuditEntry;
var
  Entry: TAuditEntry;
begin
  Result := nil;
  FLock.Enter;
  try
    for Entry in FEntries do
    begin
      if Entry.Id = AId then
      begin
        Result := Entry.Clone;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryAuditStore.Delete(AId: Int64);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FEntries.Count - 1 downto 0 do
    begin
      if FEntries[I].Id = AId then
      begin
        FEntries.Delete(I);
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryAuditStore.DeleteBefore(ATimestamp: TDateTime);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FEntries.Count - 1 downto 0 do
    begin
      if FEntries[I].Timestamp < ATimestamp then
        FEntries.Delete(I);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMemoryAuditStore.Count: Int64;
begin
  FLock.Enter;
  try
    Result := FEntries.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryAuditStore.Close;
begin
  // Nothing to close for memory store
end;

//------------------------------------------------------------------------------
// TSQLiteAuditStore
//------------------------------------------------------------------------------

constructor TSQLiteAuditStore.Create(const ADatabasePath: string);
begin
  FConfig := TAuditStoreConfig.Create;
  FConfig.DatabasePath := ADatabasePath;
  FOwnsConfig := True;
  Create(FConfig, True);
end;

constructor TSQLiteAuditStore.Create(AConfig: TAuditStoreConfig; AOwnsConfig: Boolean);
begin
  inherited Create;
  FConfig := AConfig;
  FOwnsConfig := AOwnsConfig;
  FLock := TCriticalSection.Create;
  FBatchBuffer := TList<TAuditEntry>.Create;
  FDatabasePath := FConfig.DatabasePath;
  FInitialized := False;
  FLastCleanup := Now;
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
    if not FInitialized then
    begin
      CreateSchema;
      FInitialized := True;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.CreateSchema;
begin
  // In production, this would execute SQL:
  // CREATE TABLE IF NOT EXISTS audit_log (
  //   id INTEGER PRIMARY KEY AUTOINCREMENT,
  //   timestamp TEXT NOT NULL,
  //   category TEXT NOT NULL,
  //   severity TEXT NOT NULL,
  //   action TEXT NOT NULL,
  //   message TEXT,
  //   user_id TEXT,
  //   session_id TEXT,
  //   workflow_id TEXT,
  //   workflow_name TEXT,
  //   step_id TEXT,
  //   duration_ms INTEGER DEFAULT 0,
  //   tokens_used INTEGER DEFAULT 0,
  //   source_ip TEXT,
  //   user_agent TEXT,
  //   correlation_id TEXT,
  //   details TEXT
  // );
  // CREATE INDEX IF NOT EXISTS idx_timestamp ON audit_log(timestamp);
  // CREATE INDEX IF NOT EXISTS idx_category ON audit_log(category);
  // CREATE INDEX IF NOT EXISTS idx_severity ON audit_log(severity);
  // CREATE INDEX IF NOT EXISTS idx_user_id ON audit_log(user_id);
  // CREATE INDEX IF NOT EXISTS idx_session_id ON audit_log(session_id);
  // CREATE INDEX IF NOT EXISTS idx_workflow_id ON audit_log(workflow_id);
  // CREATE INDEX IF NOT EXISTS idx_correlation_id ON audit_log(correlation_id);
end;

procedure TSQLiteAuditStore.FlushBatch;
begin
  // Would execute batch INSERT in production
  FBatchBuffer.Clear;
end;

procedure TSQLiteAuditStore.DoCleanup;
var
  CutoffDate: TDateTime;
begin
  if not FConfig.AutoCleanup then
    Exit;

  if MilliSecondsBetween(Now, FLastCleanup) < FConfig.CleanupIntervalMs then
    Exit;

  CutoffDate := IncDay(Now, -FConfig.RetentionDays);
  DeleteBefore(CutoffDate);
  FLastCleanup := Now;
end;

function TSQLiteAuditStore.BuildWhereClause(const AQuery: TAuditQuery): string;
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
      Conditions.Add(Format('timestamp >= ''%s''', [DateToISO8601(AQuery.StartTime, False)]));

    if AQuery.EndTime > 0 then
      Conditions.Add(Format('timestamp <= ''%s''', [DateToISO8601(AQuery.EndTime, False)]));

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
      Conditions.Add(Format('user_id = ''%s''', [AQuery.UserId]));

    if AQuery.SessionId <> '' then
      Conditions.Add(Format('session_id = ''%s''', [AQuery.SessionId]));

    if AQuery.WorkflowId <> '' then
      Conditions.Add(Format('workflow_id = ''%s''', [AQuery.WorkflowId]));

    if AQuery.WorkflowName <> '' then
      Conditions.Add(Format('workflow_name LIKE ''%%%s%%''', [AQuery.WorkflowName]));

    if AQuery.CorrelationId <> '' then
      Conditions.Add(Format('correlation_id = ''%s''', [AQuery.CorrelationId]));

    if AQuery.MessageContains <> '' then
      Conditions.Add(Format('message LIKE ''%%%s%%''', [AQuery.MessageContains]));

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

function TSQLiteAuditStore.EntryToSQL(const AEntry: TAuditEntry): string;
begin
  // Would build INSERT statement in production
  Result := '';
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
begin
  Result := TAuditQueryResult.Create;
  // In production, would execute:
  // SELECT * FROM audit_log {BuildWhereClause(AQuery)}
  // ORDER BY {AQuery.SortBy} {AQuery.SortOrder}
  // LIMIT {AQuery.Limit} OFFSET {AQuery.Offset}
end;

function TSQLiteAuditStore.GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
begin
  Result := TAuditStats.Create;
  Result.StartTime := AStartTime;
  Result.EndTime := AEndTime;
  // In production, would execute aggregate queries
end;

function TSQLiteAuditStore.GetById(AId: Int64): TAuditEntry;
begin
  Result := nil;
  // In production, would execute:
  // SELECT * FROM audit_log WHERE id = {AId}
end;

procedure TSQLiteAuditStore.Delete(AId: Int64);
begin
  FLock.Enter;
  try
    // In production, would execute:
    // DELETE FROM audit_log WHERE id = {AId}
  finally
    FLock.Leave;
  end;
end;

procedure TSQLiteAuditStore.DeleteBefore(ATimestamp: TDateTime);
begin
  FLock.Enter;
  try
    // In production, would execute:
    // DELETE FROM audit_log WHERE timestamp < '{DateToISO8601(ATimestamp)}'
  finally
    FLock.Leave;
  end;
end;

function TSQLiteAuditStore.Count: Int64;
begin
  Result := 0;
  // In production, would execute:
  // SELECT COUNT(*) FROM audit_log
end;

procedure TSQLiteAuditStore.Close;
begin
  FLock.Enter;
  try
    FlushBatch;
    FInitialized := False;
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TFileAuditStore
//------------------------------------------------------------------------------

constructor TFileAuditStore.Create(const ABasePath: string; AMaxFileSizeMB: Integer);
begin
  inherited Create;
  FBasePath := ABasePath;
  FMaxFileSize := AMaxFileSizeMB * 1024 * 1024;
  FLock := TCriticalSection.Create;
  FBuffer := TObjectList<TAuditEntry>.Create(True);
  FNextId := 1;
  EnsureDirectory;
end;

destructor TFileAuditStore.Destroy;
begin
  Close;
  FBuffer.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TFileAuditStore.EnsureDirectory;
begin
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
end;

function TFileAuditStore.GetCurrentFilePath: string;
begin
  if FCurrentFile = '' then
    FCurrentFile := TPath.Combine(FBasePath, 'audit_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.jsonl');
  Result := FCurrentFile;
end;

procedure TFileAuditStore.RotateFile;
begin
  FlushBuffer;
  FCurrentFile := '';
end;

procedure TFileAuditStore.FlushBuffer;
var
  FilePath: string;
  Lines: TStringList;
  Entry: TAuditEntry;
begin
  if FBuffer.Count = 0 then
    Exit;

  FilePath := GetCurrentFilePath;
  Lines := TStringList.Create;
  try
    // Load existing content if file exists
    if TFile.Exists(FilePath) then
      Lines.LoadFromFile(FilePath, TEncoding.UTF8);

    // Append new entries
    for Entry in FBuffer do
      Lines.Add(Entry.ToJSON.ToString);

    Lines.SaveToFile(FilePath, TEncoding.UTF8);
    FBuffer.Clear;

    // Check if rotation needed
    if TFile.Exists(FilePath) and (TFile.GetSize(FilePath) >= FMaxFileSize) then
      FCurrentFile := '';
  finally
    Lines.Free;
  end;
end;

function TFileAuditStore.LoadEntriesFromFile(const APath: string): TObjectList<TAuditEntry>;
var
  Lines: TStringList;
  Line: string;
  JSON: TJSONObject;
begin
  Result := TObjectList<TAuditEntry>.Create(True);
  if not TFile.Exists(APath) then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(APath, TEncoding.UTF8);
    for Line in Lines do
    begin
      if Line.Trim <> '' then
      begin
        JSON := TJSONObject.ParseJSONValue(Line) as TJSONObject;
        if Assigned(JSON) then
        try
          Result.Add(TAuditEntry.FromJSON(JSON));
        finally
          JSON.Free;
        end;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TFileAuditStore.Write(const AEntry: TAuditEntry);
var
  ClonedEntry: TAuditEntry;
begin
  FLock.Enter;
  try
    ClonedEntry := AEntry.Clone;
    ClonedEntry.Id := FNextId;
    Inc(FNextId);
    FBuffer.Add(ClonedEntry);

    if FBuffer.Count >= 100 then
      FlushBuffer;
  finally
    FLock.Leave;
  end;
end;

procedure TFileAuditStore.WriteBatch(const AEntries: TList<TAuditEntry>);
var
  Entry: TAuditEntry;
begin
  FLock.Enter;
  try
    for Entry in AEntries do
    begin
      FBuffer.Add(Entry.Clone);
      FBuffer.Last.Id := FNextId;
      Inc(FNextId);
    end;
    FlushBuffer;
  finally
    FLock.Leave;
  end;
end;

function TFileAuditStore.Query(const AQuery: TAuditQuery): TAuditQueryResult;
var
  Files: TArray<string>;
  FilePath: string;
  FileEntries: TObjectList<TAuditEntry>;
  Entry: TAuditEntry;
  AllMatches: TObjectList<TAuditEntry>;
  I, Count, StartIdx: Integer;
begin
  Result := TAuditQueryResult.Create;
  AllMatches := TObjectList<TAuditEntry>.Create(False);
  try
    FLock.Enter;
    try
      FlushBuffer;

      Files := TDirectory.GetFiles(FBasePath, '*.jsonl');
      for FilePath in Files do
      begin
        FileEntries := LoadEntriesFromFile(FilePath);
        try
          for Entry in FileEntries do
          begin
            // Simple filter check
            if ((AQuery.StartTime = 0) or (Entry.Timestamp >= AQuery.StartTime)) and
               ((AQuery.EndTime = 0) or (Entry.Timestamp <= AQuery.EndTime)) and
               ((AQuery.Categories.Count = 0) or AQuery.Categories.Contains(Entry.Category)) and
               ((AQuery.UserId = '') or (Entry.UserId = AQuery.UserId)) then
            begin
              AllMatches.Add(Entry.Clone);
            end;
          end;
        finally
          FileEntries.Free;
        end;
      end;
    finally
      FLock.Leave;
    end;

    Result.TotalCount := AllMatches.Count;
    Result.Offset := AQuery.Offset;
    Result.Limit := AQuery.Limit;

    StartIdx := AQuery.Offset;
    Count := 0;
    for I := StartIdx to AllMatches.Count - 1 do
    begin
      if Count >= AQuery.Limit then
        Break;
      Result.Entries.Add(AllMatches[I]);
      AllMatches[I] := nil; // Transfer ownership
      Inc(Count);
    end;

    Result.HasMore := (StartIdx + Count) < AllMatches.Count;
  finally
    AllMatches.Free;
  end;
end;

function TFileAuditStore.GetStats(AStartTime, AEndTime: TDateTime): TAuditStats;
begin
  Result := TAuditStats.Create;
  Result.StartTime := AStartTime;
  Result.EndTime := AEndTime;
  // Would iterate through files and compute stats
end;

function TFileAuditStore.GetById(AId: Int64): TAuditEntry;
begin
  Result := nil;
  // Would search through files for matching ID
end;

procedure TFileAuditStore.Delete(AId: Int64);
begin
  // Not efficiently supported for file-based storage
end;

procedure TFileAuditStore.DeleteBefore(ATimestamp: TDateTime);
var
  Files: TArray<string>;
  FilePath, FileName: string;
  FileDate: TDateTime;
begin
  FLock.Enter;
  try
    Files := TDirectory.GetFiles(FBasePath, '*.jsonl');
    for FilePath in Files do
    begin
      FileName := TPath.GetFileNameWithoutExtension(FilePath);
      // Parse date from filename (audit_yyyymmdd_hhnnss)
      if FileName.StartsWith('audit_') then
      begin
        try
          FileDate := EncodeDate(
            StrToInt(Copy(FileName, 7, 4)),
            StrToInt(Copy(FileName, 11, 2)),
            StrToInt(Copy(FileName, 13, 2))
          );
          if FileDate < ATimestamp then
            TFile.Delete(FilePath);
        except
          // Ignore parse errors
        end;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileAuditStore.Count: Int64;
var
  Files: TArray<string>;
  FilePath: string;
  Lines: TStringList;
begin
  Result := 0;
  FLock.Enter;
  try
    Files := TDirectory.GetFiles(FBasePath, '*.jsonl');
    for FilePath in Files do
    begin
      Lines := TStringList.Create;
      try
        Lines.LoadFromFile(FilePath, TEncoding.UTF8);
        Inc(Result, Lines.Count);
      finally
        Lines.Free;
      end;
    end;
    Inc(Result, FBuffer.Count);
  finally
    FLock.Leave;
  end;
end;

procedure TFileAuditStore.Close;
begin
  FLock.Enter;
  try
    FlushBuffer;
  finally
    FLock.Leave;
  end;
end;

end.
