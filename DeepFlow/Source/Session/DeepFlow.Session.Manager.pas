{ ============================================================================
  UniFlow.Session.Manager - Session Lifecycle Manager

  Version: 1.0
  Description: Manages session lifecycle including creation, lookup, expiry

  Features:
    - Session creation and lookup
    - Automatic expiry cleanup
    - Memory and file-based storage
    - User session limits
    - Session statistics

  Usage:
    var Manager := TSessionManager.Create;
    var Session := Manager.CreateSession('user123');
    Session.AddUserMessage('Hello');
    // ... later ...
    Session := Manager.GetSession(SessionId);
  ============================================================================ }

unit UniFlow.Session.Manager;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.SyncObjs,
  System.IOUtils,
  System.Threading,
  UniFlow.Session.Types,
  DeepBase.Exceptions;

type
  /// <summary>
  /// Session storage interface
  /// </summary>
  ISessionStore = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function Save(Session: TSession): Boolean;
    function Load(const SessionId: string): TSession;
    function Delete(const SessionId: string): Boolean;
    function GetAllSessionIds: TArray<string>;
    function GetSessionCount: Integer;
  end;

  /// <summary>
  /// Memory-based session store
  /// </summary>
  TMemorySessionStore = class(TInterfacedObject, ISessionStore)
  private
    FSessions: TObjectDictionary<string, TSession>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    function Save(Session: TSession): Boolean;
    function Load(const SessionId: string): TSession;
    function Delete(const SessionId: string): Boolean;
    function GetAllSessionIds: TArray<string>;
    function GetSessionCount: Integer;
  end;

  /// <summary>
  /// File-based session store (JSON files)
  /// </summary>
  TFileSessionStore = class(TInterfacedObject, ISessionStore)
  private
    FBasePath: string;
    FLock: TCriticalSection;

    function GetSessionFilePath(const SessionId: string): string;
  public
    constructor Create(const ABasePath: string);
    destructor Destroy; override;

    function Save(Session: TSession): Boolean;
    function Load(const SessionId: string): TSession;
    function Delete(const SessionId: string): Boolean;
    function GetAllSessionIds: TArray<string>;
    function GetSessionCount: Integer;
  end;

  /// <summary>
  /// Session event types
  /// </summary>
  TSessionEvent = (
    seCreated,
    seAccessed,
    seUpdated,
    seExpired,
    seClosed,
    seDeleted
  );

  TSessionEventHandler = reference to procedure(const SessionId: string; Event: TSessionEvent);

  /// <summary>
  /// Session manager
  /// </summary>
  TSessionManager = class
  private
    FStore: ISessionStore;
    FConfig: TSessionConfig;
    FLock: TCriticalSection;
    FCleanupTimer: TThread;
    FOnSessionEvent: TSessionEventHandler;
    FUserSessionCount: TDictionary<string, Integer>;

    procedure StartCleanupTimer;
    procedure StopCleanupTimer;
    procedure DoCleanup;
    procedure FireEvent(const SessionId: string; Event: TSessionEvent);
    procedure IncrementUserSessionCount(const UserId: string);
    procedure DecrementUserSessionCount(const UserId: string);
    function GetUserSessionCount(const UserId: string): Integer;
  public
    constructor Create(AStore: ISessionStore = nil);
    destructor Destroy; override;

    /// <summary>
    /// Create new session
    /// </summary>
    function CreateSession(const UserId: string = ''): TSession;

    /// <summary>
    /// Get existing session by ID
    /// </summary>
    function GetSession(const SessionId: string): TSession;

    /// <summary>
    /// Get or create session
    /// </summary>
    function GetOrCreateSession(const SessionId: string; const UserId: string = ''): TSession;

    /// <summary>
    /// Check if session exists
    /// </summary>
    function SessionExists(const SessionId: string): Boolean;

    /// <summary>
    /// Close session (mark as closed but keep data)
    /// </summary>
    procedure CloseSession(const SessionId: string);

    /// <summary>
    /// Delete session completely
    /// </summary>
    procedure DeleteSession(const SessionId: string);

    /// <summary>
    /// Get all sessions for a user
    /// </summary>
    function GetUserSessions(const UserId: string): TArray<TSession>;

    /// <summary>
    /// Clean up expired sessions
    /// </summary>
    function CleanupExpiredSessions: Integer;

    /// <summary>
    /// Get session statistics
    /// </summary>
    function GetStats: TJSONObject;

    /// <summary>
    /// Save session to store
    /// </summary>
    procedure SaveSession(Session: TSession);

    property Config: TSessionConfig read FConfig write FConfig;
    property Store: ISessionStore read FStore;
    property OnSessionEvent: TSessionEventHandler read FOnSessionEvent write FOnSessionEvent;
  end;

implementation

uses
  System.DateUtils;

{ TMemorySessionStore }

constructor TMemorySessionStore.Create;
begin
  inherited;
  FSessions := TObjectDictionary<string, TSession>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
end;

destructor TMemorySessionStore.Destroy;
begin
  FLock.Free;
  FSessions.Free;
  inherited;
end;

function TMemorySessionStore.Save(Session: TSession): Boolean;
begin
  FLock.Enter;
  try
    // Note: we don't own the session passed in, we store a reference
    // The caller is responsible for the session's lifetime
    // In a real implementation, we'd clone the session
    FSessions.AddOrSetValue(Session.Id, Session);
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TMemorySessionStore.Load(const SessionId: string): TSession;
begin
  FLock.Enter;
  try
    if not FSessions.TryGetValue(SessionId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TMemorySessionStore.Delete(const SessionId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FSessions.ContainsKey(SessionId);
    if Result then
      FSessions.Remove(SessionId);
  finally
    FLock.Leave;
  end;
end;

function TMemorySessionStore.GetAllSessionIds: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FSessions.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TMemorySessionStore.GetSessionCount: Integer;
begin
  FLock.Enter;
  try
    Result := FSessions.Count;
  finally
    FLock.Leave;
  end;
end;

{ TFileSessionStore }

constructor TFileSessionStore.Create(const ABasePath: string);
begin
  inherited Create;
  FBasePath := ABasePath;
  FLock := TCriticalSection.Create;

  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);
end;

destructor TFileSessionStore.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TFileSessionStore.GetSessionFilePath(const SessionId: string): string;
begin
  Result := TPath.Combine(FBasePath, SessionId + '.json');
end;

function TFileSessionStore.Save(Session: TSession): Boolean;
var
  JSON: TJSONObject;
  FilePath: string;
begin
  FLock.Enter;
  try
    try
      FilePath := GetSessionFilePath(Session.Id);
      JSON := Session.ToJSON;
      try
        TFile.WriteAllText(FilePath, JSON.ToString, TEncoding.UTF8);
        Result := True;
      finally
        JSON.Free;
      end;
    except
      Result := False;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileSessionStore.Load(const SessionId: string): TSession;
var
  FilePath, Content: string;
  JSON: TJSONObject;
begin
  Result := nil;
  FLock.Enter;
  try
    FilePath := GetSessionFilePath(SessionId);
    if not TFile.Exists(FilePath) then
      Exit;

    try
      Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);
      JSON := TJSONObject.ParseJSONValue(Content) as TJSONObject;
      if Assigned(JSON) then
      try
        Result := TSession.Create(SessionId);
        Result.LoadFromJSON(JSON);
      finally
        JSON.Free;
      end;
    except
      Result := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileSessionStore.Delete(const SessionId: string): Boolean;
var
  FilePath: string;
begin
  FLock.Enter;
  try
    FilePath := GetSessionFilePath(SessionId);
    Result := TFile.Exists(FilePath);
    if Result then
      TFile.Delete(FilePath);
  finally
    FLock.Leave;
  end;
end;

function TFileSessionStore.GetAllSessionIds: TArray<string>;
var
  Files: TArray<string>;
  I: Integer;
begin
  FLock.Enter;
  try
    Files := TDirectory.GetFiles(FBasePath, '*.json');
    SetLength(Result, Length(Files));
    for I := 0 to High(Files) do
      Result[I] := TPath.GetFileNameWithoutExtension(Files[I]);
  finally
    FLock.Leave;
  end;
end;

function TFileSessionStore.GetSessionCount: Integer;
begin
  FLock.Enter;
  try
    Result := Length(TDirectory.GetFiles(FBasePath, '*.json'));
  finally
    FLock.Leave;
  end;
end;

{ TSessionManager }

constructor TSessionManager.Create(AStore: ISessionStore);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FUserSessionCount := TDictionary<string, Integer>.Create;
  FConfig := TSessionConfig.Default;

  if Assigned(AStore) then
    FStore := AStore
  else
    FStore := TMemorySessionStore.Create;

  StartCleanupTimer;
end;

destructor TSessionManager.Destroy;
begin
  StopCleanupTimer;
  FUserSessionCount.Free;
  FLock.Free;
  inherited;
end;

procedure TSessionManager.StartCleanupTimer;
begin
  FCleanupTimer := TThread.CreateAnonymousThread(
    procedure
    begin
      while not TThread.Current.CheckTerminated do
      begin
        Sleep(FConfig.CleanupIntervalMinutes * 60 * 1000);
        if not TThread.Current.CheckTerminated then
          DoCleanup;
      end;
    end);
  FCleanupTimer.FreeOnTerminate := False;
  FCleanupTimer.Start;
end;

procedure TSessionManager.StopCleanupTimer;
begin
  if Assigned(FCleanupTimer) then
  begin
    FCleanupTimer.Terminate;
    FCleanupTimer.WaitFor;
    FCleanupTimer.Free;
    FCleanupTimer := nil;
  end;
end;

procedure TSessionManager.DoCleanup;
begin
  CleanupExpiredSessions;
end;

procedure TSessionManager.FireEvent(const SessionId: string; Event: TSessionEvent);
begin
  if Assigned(FOnSessionEvent) then
  begin
    TThread.Queue(nil,
      procedure
      begin
        FOnSessionEvent(SessionId, Event);
      end);
  end;
end;

procedure TSessionManager.IncrementUserSessionCount(const UserId: string);
var
  Count: Integer;
begin
  if UserId.IsEmpty then Exit;

  FLock.Enter;
  try
    if FUserSessionCount.TryGetValue(UserId, Count) then
      FUserSessionCount[UserId] := Count + 1
    else
      FUserSessionCount.Add(UserId, 1);
  finally
    FLock.Leave;
  end;
end;

procedure TSessionManager.DecrementUserSessionCount(const UserId: string);
var
  Count: Integer;
begin
  if UserId.IsEmpty then Exit;

  FLock.Enter;
  try
    if FUserSessionCount.TryGetValue(UserId, Count) then
    begin
      if Count > 1 then
        FUserSessionCount[UserId] := Count - 1
      else
        FUserSessionCount.Remove(UserId);
    end;
  finally
    FLock.Leave;
  end;
end;

function TSessionManager.GetUserSessionCount(const UserId: string): Integer;
begin
  FLock.Enter;
  try
    if not FUserSessionCount.TryGetValue(UserId, Result) then
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

function TSessionManager.CreateSession(const UserId: string): TSession;
begin
  // Check user session limit
  if not UserId.IsEmpty and (GetUserSessionCount(UserId) >= FConfig.MaxSessionsPerUser) then
    raise EOperationException.CreateFmt('User %s has reached maximum session limit (%d)',
      [UserId, FConfig.MaxSessionsPerUser]);

  Result := TSession.Create('', UserId);
  Result.MaxMessages := FConfig.MaxMessagesPerSession;
  Result.TimeoutMinutes := FConfig.DefaultTimeoutMinutes;

  FStore.Save(Result);
  IncrementUserSessionCount(UserId);
  FireEvent(Result.Id, seCreated);
end;

function TSessionManager.GetSession(const SessionId: string): TSession;
begin
  Result := FStore.Load(SessionId);
  if Assigned(Result) then
  begin
    if Result.IsExpired then
    begin
      Result.Status := ssExpired;
      FireEvent(SessionId, seExpired);
    end
    else
    begin
      Result.Touch;
      FireEvent(SessionId, seAccessed);
    end;
  end;
end;

function TSessionManager.GetOrCreateSession(const SessionId: string;
  const UserId: string): TSession;
begin
  if SessionId.IsEmpty then
    Result := CreateSession(UserId)
  else
  begin
    Result := GetSession(SessionId);
    if Result = nil then
      Result := CreateSession(UserId);
  end;
end;

function TSessionManager.SessionExists(const SessionId: string): Boolean;
var
  Session: TSession;
begin
  Session := FStore.Load(SessionId);
  Result := Assigned(Session) and not Session.IsExpired;
end;

procedure TSessionManager.CloseSession(const SessionId: string);
var
  Session: TSession;
begin
  Session := FStore.Load(SessionId);
  if Assigned(Session) then
  begin
    Session.Status := ssClosed;
    FStore.Save(Session);
    DecrementUserSessionCount(Session.UserId);
    FireEvent(SessionId, seClosed);
  end;
end;

procedure TSessionManager.DeleteSession(const SessionId: string);
var
  Session: TSession;
begin
  Session := FStore.Load(SessionId);
  if Assigned(Session) then
    DecrementUserSessionCount(Session.UserId);

  FStore.Delete(SessionId);
  FireEvent(SessionId, seDeleted);
end;

function TSessionManager.GetUserSessions(const UserId: string): TArray<TSession>;
var
  AllIds: TArray<string>;
  Sessions: TList<TSession>;
  Session: TSession;
  Id: string;
begin
  Sessions := TList<TSession>.Create;
  try
    AllIds := FStore.GetAllSessionIds;
    for Id in AllIds do
    begin
      Session := FStore.Load(Id);
      if Assigned(Session) and (Session.UserId = UserId) and not Session.IsExpired then
        Sessions.Add(Session);
    end;
    Result := Sessions.ToArray;
  finally
    Sessions.Free;
  end;
end;

function TSessionManager.CleanupExpiredSessions: Integer;
var
  AllIds: TArray<string>;
  Session: TSession;
  Id: string;
begin
  Result := 0;
  AllIds := FStore.GetAllSessionIds;

  for Id in AllIds do
  begin
    Session := FStore.Load(Id);
    if Assigned(Session) and Session.IsExpired then
    begin
      DecrementUserSessionCount(Session.UserId);
      FStore.Delete(Id);
      FireEvent(Id, seExpired);
      Inc(Result);
    end;
  end;
end;

function TSessionManager.GetStats: TJSONObject;
var
  AllIds: TArray<string>;
  Session: TSession;
  Id: string;
  ActiveCount, ExpiredCount, TotalMessages: Integer;
begin
  Result := TJSONObject.Create;
  AllIds := FStore.GetAllSessionIds;

  ActiveCount := 0;
  ExpiredCount := 0;
  TotalMessages := 0;

  for Id in AllIds do
  begin
    Session := FStore.Load(Id);
    if Assigned(Session) then
    begin
      if Session.IsExpired then
        Inc(ExpiredCount)
      else
        Inc(ActiveCount);
      TotalMessages := TotalMessages + Session.MessageCount;
    end;
  end;

  Result.AddPair('total_sessions', Length(AllIds));
  Result.AddPair('active_sessions', ActiveCount);
  Result.AddPair('expired_sessions', ExpiredCount);
  Result.AddPair('total_messages', TotalMessages);
  Result.AddPair('unique_users', FUserSessionCount.Count);
end;

procedure TSessionManager.SaveSession(Session: TSession);
begin
  FStore.Save(Session);
  FireEvent(Session.Id, seUpdated);
end;

end.
