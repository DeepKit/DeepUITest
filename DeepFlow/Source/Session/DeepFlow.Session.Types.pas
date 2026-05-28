{ ============================================================================
  UniFlow.Session.Types - Session Type Definitions

  Version: 1.0
  Description: Core types for session management
  ============================================================================ }

unit UniFlow.Session.Types;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON;

type
  /// <summary>
  /// Session status
  /// </summary>
  TSessionStatus = (
    ssActive,     // Active session
    ssIdle,       // Idle (no recent activity)
    ssSuspended,  // Temporarily suspended
    ssExpired,    // Expired due to timeout
    ssClosed      // Explicitly closed
  );

  /// <summary>
  /// Message role in conversation
  /// </summary>
  TMessageRole = (
    mrSystem,     // System message
    mrUser,       // User message
    mrAssistant,  // Assistant response
    mrTool        // Tool/function result
  );

  /// <summary>
  /// Chat message in session hiDeepStory
  /// </summary>
  TChatMessage = record
    Id: string;
    Role: TMessageRole;
    Content: string;
    Timestamp: TDateTime;
    Metadata: string;  // JSON metadata

    class function Create(ARole: TMessageRole; const AContent: string): TChatMessage; static;
    class function System(const AContent: string): TChatMessage; static;
    class function User(const AContent: string): TChatMessage; static;
    class function Assistant(const AContent: string): TChatMessage; static;
    function RoleToString: string;
    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TChatMessage; static;
  end;

  /// <summary>
  /// Session data
  /// </summary>
  TSession = class
  private
    FId: string;
    FUserId: string;
    FStatus: TSessionStatus;
    FCreatedAt: TDateTime;
    FLastActivityAt: TDateTime;
    FExpiresAt: TDateTime;
    FMessages: TList<TChatMessage>;
    FVariables: TDictionary<string, string>;
    FMetadata: TDictionary<string, string>;
    FMaxMessages: Integer;
    FTimeoutMinutes: Integer;

    function GetMessageCount: Integer;
    function GetIsExpired: Boolean;
    procedure TrimMessages;
  public
    constructor Create(const ASessionId: string; const AUserId: string = '');
    destructor Destroy; override;

    /// <summary>
    /// Add message to hiDeepStory
    /// </summary>
    procedure AddMessage(const Msg: TChatMessage);
    procedure AddUserMessage(const Content: string);
    procedure AddAssistantMessage(const Content: string);
    procedure AddSystemMessage(const Content: string);

    /// <summary>
    /// Get messages
    /// </summary>
    function GetMessages(Count: Integer = 0): TArray<TChatMessage>;
    function GetLastMessages(Count: Integer): TArray<TChatMessage>;
    procedure ClearMessages;

    /// <summary>
    /// Variable management
    /// </summary>
    procedure SetVariable(const Key, Value: string);
    function GetVariable(const Key: string; const Default: string = ''): string;
    function HasVariable(const Key: string): Boolean;
    procedure DeleteVariable(const Key: string);
    procedure ClearVariables;

    /// <summary>
    /// Metadata management
    /// </summary>
    procedure SetMetadata(const Key, Value: string);
    function GetMetadata(const Key: string; const Default: string = ''): string;

    /// <summary>
    /// Activity tracking
    /// </summary>
    procedure Touch;
    procedure UpdateExpiry;

    /// <summary>
    /// Serialization
    /// </summary>
    function ToJSON: TJSONObject;
    procedure LoadFromJSON(const AJSON: TJSONObject);

    property Id: string read FId;
    property UserId: string read FUserId write FUserId;
    property Status: TSessionStatus read FStatus write FStatus;
    property CreatedAt: TDateTime read FCreatedAt;
    property LastActivityAt: TDateTime read FLastActivityAt;
    property ExpiresAt: TDateTime read FExpiresAt;
    property MessageCount: Integer read GetMessageCount;
    property IsExpired: Boolean read GetIsExpired;
    property MaxMessages: Integer read FMaxMessages write FMaxMessages;
    property TimeoutMinutes: Integer read FTimeoutMinutes write FTimeoutMinutes;
    property Variables: TDictionary<string, string> read FVariables;
    property Messages: TList<TChatMessage> read FMessages;
  end;

  /// <summary>
  /// Session configuration
  /// </summary>
  TSessionConfig = record
    DefaultTimeoutMinutes: Integer;
    MaxMessagesPerSession: Integer;
    MaxSessionsPerUser: Integer;
    CleanupIntervalMinutes: Integer;
    PersistSessions: Boolean;

    class function Default: TSessionConfig; static;
  end;

function SessionStatusToString(Status: TSessionStatus): string;
function StringToSessionStatus(const S: string): TSessionStatus;
function MessageRoleToString(Role: TMessageRole): string;
function StringToMessageRole(const S: string): TMessageRole;
function GenerateSessionId: string;

implementation

uses
  System.DateUtils;

function SessionStatusToString(Status: TSessionStatus): string;
begin
  case Status of
    ssActive: Result := 'active';
    ssIdle: Result := 'idle';
    ssSuspended: Result := 'suspended';
    ssExpired: Result := 'expired';
    ssClosed: Result := 'closed';
  else
    Result := 'unknown';
  end;
end;

function StringToSessionStatus(const S: string): TSessionStatus;
var
  Lower: string;
begin
  Lower := S.ToLower;
  if Lower = 'active' then Result := ssActive
  else if Lower = 'idle' then Result := ssIdle
  else if Lower = 'suspended' then Result := ssSuspended
  else if Lower = 'expired' then Result := ssExpired
  else if Lower = 'closed' then Result := ssClosed
  else Result := ssActive;
end;

function MessageRoleToString(Role: TMessageRole): string;
begin
  case Role of
    mrSystem: Result := 'system';
    mrUser: Result := 'user';
    mrAssistant: Result := 'assistant';
    mrTool: Result := 'tool';
  else
    Result := 'user';
  end;
end;

function StringToMessageRole(const S: string): TMessageRole;
var
  Lower: string;
begin
  Lower := S.ToLower;
  if Lower = 'system' then Result := mrSystem
  else if Lower = 'user' then Result := mrUser
  else if Lower = 'assistant' then Result := mrAssistant
  else if Lower = 'tool' then Result := mrTool
  else Result := mrUser;
end;

function GenerateSessionId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'sess_' + Copy(GUIDToString(GUID), 2, 36).Replace('-', '', [rfReplaceAll]).ToLower;
end;

{ TChatMessage }

class function TChatMessage.Create(ARole: TMessageRole; const AContent: string): TChatMessage;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result.Id := Copy(GUIDToString(GUID), 2, 8);
  Result.Role := ARole;
  Result.Content := AContent;
  Result.Timestamp := Now;
  Result.Metadata := '';
end;

class function TChatMessage.System(const AContent: string): TChatMessage;
begin
  Result := Create(mrSystem, AContent);
end;

class function TChatMessage.User(const AContent: string): TChatMessage;
begin
  Result := Create(mrUser, AContent);
end;

class function TChatMessage.Assistant(const AContent: string): TChatMessage;
begin
  Result := Create(mrAssistant, AContent);
end;

function TChatMessage.RoleToString: string;
begin
  Result := MessageRoleToString(Role);
end;

function TChatMessage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', Id);
  Result.AddPair('role', RoleToString);
  Result.AddPair('content', Content);
  Result.AddPair('timestamp', DateToISO8601(Timestamp));
  if not Metadata.IsEmpty then
    Result.AddPair('metadata', Metadata);
end;

class function TChatMessage.FromJSON(const AJSON: TJSONObject): TChatMessage;
var
  RoleStr, TimestampStr: string;
begin
  Result.Id := AJSON.GetValue<string>('id', '');
  RoleStr := AJSON.GetValue<string>('role', 'user');
  Result.Role := StringToMessageRole(RoleStr);
  Result.Content := AJSON.GetValue<string>('content', '');
  TimestampStr := AJSON.GetValue<string>('timestamp', '');
  if not TimestampStr.IsEmpty then
    Result.Timestamp := ISO8601ToDate(TimestampStr)
  else
    Result.Timestamp := Now;
  Result.Metadata := AJSON.GetValue<string>('metadata', '');
end;

{ TSession }

constructor TSession.Create(const ASessionId: string; const AUserId: string);
begin
  inherited Create;
  if ASessionId.IsEmpty then
    FId := GenerateSessionId
  else
    FId := ASessionId;
  FUserId := AUserId;
  FStatus := ssActive;
  FCreatedAt := Now;
  FLastActivityAt := Now;
  FMaxMessages := 100;
  FTimeoutMinutes := 30;
  UpdateExpiry;

  FMessages := TList<TChatMessage>.Create;
  FVariables := TDictionary<string, string>.Create;
  FMetadata := TDictionary<string, string>.Create;
end;

destructor TSession.Destroy;
begin
  FMetadata.Free;
  FVariables.Free;
  FMessages.Free;
  inherited;
end;

function TSession.GetMessageCount: Integer;
begin
  Result := FMessages.Count;
end;

function TSession.GetIsExpired: Boolean;
begin
  Result := (FStatus = ssExpired) or (Now > FExpiresAt);
end;

procedure TSession.TrimMessages;
begin
  while FMessages.Count > FMaxMessages do
    FMessages.Delete(0);
end;

procedure TSession.AddMessage(const Msg: TChatMessage);
begin
  FMessages.Add(Msg);
  TrimMessages;
  Touch;
end;

procedure TSession.AddUserMessage(const Content: string);
begin
  AddMessage(TChatMessage.User(Content));
end;

procedure TSession.AddAssistantMessage(const Content: string);
begin
  AddMessage(TChatMessage.Assistant(Content));
end;

procedure TSession.AddSystemMessage(const Content: string);
begin
  AddMessage(TChatMessage.System(Content));
end;

function TSession.GetMessages(Count: Integer): TArray<TChatMessage>;
var
  I, Start: Integer;
begin
  if (Count <= 0) or (Count >= FMessages.Count) then
    Result := FMessages.ToArray
  else
  begin
    Start := FMessages.Count - Count;
    SetLength(Result, Count);
    for I := 0 to Count - 1 do
      Result[I] := FMessages[Start + I];
  end;
end;

function TSession.GetLastMessages(Count: Integer): TArray<TChatMessage>;
begin
  Result := GetMessages(Count);
end;

procedure TSession.ClearMessages;
begin
  FMessages.Clear;
end;

procedure TSession.SetVariable(const Key, Value: string);
begin
  FVariables.AddOrSetValue(Key, Value);
end;

function TSession.GetVariable(const Key: string; const Default: string): string;
begin
  if not FVariables.TryGetValue(Key, Result) then
    Result := Default;
end;

function TSession.HasVariable(const Key: string): Boolean;
begin
  Result := FVariables.ContainsKey(Key);
end;

procedure TSession.DeleteVariable(const Key: string);
begin
  FVariables.Remove(Key);
end;

procedure TSession.ClearVariables;
begin
  FVariables.Clear;
end;

procedure TSession.SetMetadata(const Key, Value: string);
begin
  FMetadata.AddOrSetValue(Key, Value);
end;

function TSession.GetMetadata(const Key: string; const Default: string): string;
begin
  if not FMetadata.TryGetValue(Key, Result) then
    Result := Default;
end;

procedure TSession.Touch;
begin
  FLastActivityAt := Now;
  UpdateExpiry;
  if FStatus = ssIdle then
    FStatus := ssActive;
end;

procedure TSession.UpdateExpiry;
begin
  FExpiresAt := IncMinute(Now, FTimeoutMinutes);
end;

function TSession.ToJSON: TJSONObject;
var
  MsgArray: TJSONArray;
  VarsObj, MetaObj: TJSONObject;
  Msg: TChatMessage;
  Key: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('user_id', FUserId);
  Result.AddPair('status', SessionStatusToString(FStatus));
  Result.AddPair('created_at', DateToISO8601(FCreatedAt));
  Result.AddPair('last_activity_at', DateToISO8601(FLastActivityAt));
  Result.AddPair('expires_at', DateToISO8601(FExpiresAt));
  Result.AddPair('max_messages', FMaxMessages);
  Result.AddPair('timeout_minutes', FTimeoutMinutes);

  // Messages
  MsgArray := TJSONArray.Create;
  for Msg in FMessages do
    MsgArray.Add(Msg.ToJSON);
  Result.AddPair('messages', MsgArray);

  // Variables
  VarsObj := TJSONObject.Create;
  for Key in FVariables.Keys do
    VarsObj.AddPair(Key, FVariables[Key]);
  Result.AddPair('variables', VarsObj);

  // Metadata
  MetaObj := TJSONObject.Create;
  for Key in FMetadata.Keys do
    MetaObj.AddPair(Key, FMetadata[Key]);
  Result.AddPair('metadata', MetaObj);
end;

procedure TSession.LoadFromJSON(const AJSON: TJSONObject);
var
  MsgArray: TJSONArray;
  VarsObj, MetaObj: TJSONObject;
  I: Integer;
  Pair: TJSONPair;
begin
  FUserId := AJSON.GetValue<string>('user_id', '');
  FStatus := StringToSessionStatus(AJSON.GetValue<string>('status', 'active'));
  FCreatedAt := ISO8601ToDate(AJSON.GetValue<string>('created_at', DateToISO8601(Now)));
  FLastActivityAt := ISO8601ToDate(AJSON.GetValue<string>('last_activity_at', DateToISO8601(Now)));
  FExpiresAt := ISO8601ToDate(AJSON.GetValue<string>('expires_at', DateToISO8601(IncMinute(Now, 30))));
  FMaxMessages := AJSON.GetValue<Integer>('max_messages', 100);
  FTimeoutMinutes := AJSON.GetValue<Integer>('timeout_minutes', 30);

  // Messages
  FMessages.Clear;
  if AJSON.TryGetValue<TJSONArray>('messages', MsgArray) then
  begin
    for I := 0 to MsgArray.Count - 1 do
      FMessages.Add(TChatMessage.FromJSON(MsgArray.Items[I] as TJSONObject));
  end;

  // Variables
  FVariables.Clear;
  if AJSON.TryGetValue<TJSONObject>('variables', VarsObj) then
  begin
    for Pair in VarsObj do
      FVariables.Add(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;

  // Metadata
  FMetadata.Clear;
  if AJSON.TryGetValue<TJSONObject>('metadata', MetaObj) then
  begin
    for Pair in MetaObj do
      FMetadata.Add(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;
end;

{ TSessionConfig }

class function TSessionConfig.Default: TSessionConfig;
begin
  Result.DefaultTimeoutMinutes := 30;
  Result.MaxMessagesPerSession := 100;
  Result.MaxSessionsPerUser := 10;
  Result.CleanupIntervalMinutes := 5;
  Result.PersistSessions := True;
end;

end.
