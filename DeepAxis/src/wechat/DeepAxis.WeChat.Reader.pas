unit DeepAxis.WeChat.Reader;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Hash, System.Math,
  Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef, FireDAC.Stan.Param,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.WeChat.Adapter, DeepAxis.WeChat.Zstd;

type
  /// <summary>
  ///   Read-only access to WeChat SQLite databases.
  ///   Maps username → MD5(username.lower()) → Msg_<hash> table.
  ///   For testing with already-decrypted DBs, pass empty key.
  ///
  ///   Performance: message DB connections are cached after first access.
  ///   Use ReadAllMessages for batch scanning (single pass over all DBs).
  /// </summary>
  TWeChatReader = class(TInterfacedObject, IWxReader)
  private
    FAdapter: ISchemaAdapter;
    FIsOpen: Boolean;
    FDataPath: string;
    FMessageFiles: TArray<string>;
    FContactFile: string;
    FSessionFile: string;
    FConnection: TFDConnection;
    FZstdDecompressor: TObject; // TZstdDecompressor
    // ContactId (SHA-256 username) -> Msg_<MD5(lowercase username)> table
    FContactIdToMsgTable: TDictionary<string, string>;
    // ── Message DB connection cache ─────────────────────────────
    // Avoids opening/closing connections for every ReadMessages call.
    FMsgDbCacheConns: TArray<TFDConnection>;
    FMsgDbCacheTables: TArray<TArray<string>>;  // parallel array: Msg_* tables per conn
    FMsgDbCacheReady: Boolean;
    procedure EnsureMsgDbCache;
    procedure FreeMsgDbCache;
    function ConnectToDb(const ADbPath: string; const AKeyBytes: TBytes): TFDConnection;
    function GetMsgTableNames(const AConnection: TFDConnection): TArray<string>;
    function DiscoverDbFiles(const ADataPath: string): Boolean;
    function BuildContactQuery: string;
    function BuildMessageQuery(const ATableName: string): string;
    function BuildSessionQuery: string;
    function RowToContact(const ARow: TDataSet): TContact;
    function RowToMessageMeta(const ARow: TDataSet): TMessageMeta;
    function RowToConversation(const ARow: TDataSet): TConversation;
    function ComputeContactId(const AUsername: string): string;
    function RedactDisplayName(const AName: string): string;
    function ComputeMsgTableHash(const AUsername: string): string;
    function ResolveMsgTableName(const AContactId: string): string;
  public
    constructor Create(const AAdapter: ISchemaAdapter);
    destructor Destroy; override;

    // IWxReader
    function Open(const ADbPath: string; const AKeyBytes: TBytes): Boolean;
    function OpenPaths(const AContactPath, AMessage0Path, ASessionPath: string): Boolean;
    function ReadContacts: TArray<TContact>;
    function ReadMessages(const AContactId: string;
      const ASince: TScanCursor): TArray<TMessageMeta>;
    function ReadConversations: TArray<TConversation>;
    function GetScanCursors: TScanCursorArray;
    procedure Close;
    function IsOpen: Boolean;
    function GetAdapter: ISchemaAdapter;

    /// <summary>
    ///   Batch: read messages for ALL contacts in one pass over all message DBs.
    ///   Much faster than calling ReadMessages per contact.
    ///   Returns a dictionary: ContactId → messages array.
    /// </summary>
    function ReadAllMessages(const ASince: TScanCursor):
      TDictionary<string, TArray<TMessageMeta>>;
  end;

implementation

type
  TSnapshotSQLiteConnection = class(TFDConnection)
  private
    FTempFiles: TList<string>;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure TrackTempFile(const APath: string);
  end;

constructor TSnapshotSQLiteConnection.Create(AOwner: TComponent);
begin
  inherited;
  FTempFiles := TList<string>.Create;
end;

destructor TSnapshotSQLiteConnection.Destroy;
var
  LFile: string;
begin
  if Connected then
    Close;
  for LFile in FTempFiles do
    if TFile.Exists(LFile) then
      try TFile.Delete(LFile); except end;
  FTempFiles.Free;
  inherited;
end;

procedure TSnapshotSQLiteConnection.TrackTempFile(const APath: string);
begin
  FTempFiles.Add(APath);
end;

{ TWeChatReader }

constructor TWeChatReader.Create(const AAdapter: ISchemaAdapter);
begin
  inherited Create;
  FAdapter := AAdapter;
  FIsOpen := False;
  FConnection := nil;
  FContactIdToMsgTable := nil;
  FMsgDbCacheReady := False;
  FZstdDecompressor := TZstdDecompressor.Create;
end;

destructor TWeChatReader.Destroy;
begin
  FreeMsgDbCache;
  Close;
  FZstdDecompressor.Free;
  inherited;
end;

function TWeChatReader.ComputeMsgTableHash(const AUsername: string): string;
begin
  // WCDB: Msg_<MD5(lowercase_username)>
  Result := 'Msg_' + THashMD5.GetHashString(AUsername.ToLower);
end;

function TWeChatReader.Open(const ADbPath: string; const AKeyBytes: TBytes): Boolean;
begin
  Close;
  FDataPath := ADbPath;
  FIsOpen := DiscoverDbFiles(ADbPath);
  Result := FIsOpen;
  if not Result then Close;
end;

function TWeChatReader.OpenPaths(const AContactPath, AMessage0Path,
  ASessionPath: string): Boolean;
var
  LMessageDir: string;
  LFiles: TArray<string>;
  LFile: string;
begin
  Close;
  FIsOpen := False;
  Result := False;

  if not TFile.Exists(AContactPath) then Exit;
  if not TFile.Exists(AMessage0Path) then Exit;

  FContactFile := AContactPath;
  LMessageDir := TPath.GetDirectoryName(AMessage0Path);
  if TDirectory.Exists(LMessageDir) then
  begin
    LFiles := TDirectory.GetFiles(LMessageDir, 'message_*.db*',
      TSearchOption.soTopDirectoryOnly);
    for LFile in LFiles do
    begin
      if LFile.Contains('-wal') or LFile.Contains('-shm') then
        Continue;
      SetLength(FMessageFiles, Length(FMessageFiles) + 1);
      FMessageFiles[High(FMessageFiles)] := LFile;
    end;
  end;

  if Length(FMessageFiles) = 0 then
  begin
    SetLength(FMessageFiles, 1);
    FMessageFiles[0] := AMessage0Path;
  end;
  TArray.Sort<string>(FMessageFiles);

  if (ASessionPath <> '') and TFile.Exists(ASessionPath) then
    FSessionFile := ASessionPath;

  FDataPath := TPath.GetDirectoryName(AMessage0Path);
  FIsOpen := True;
  Result := True;
end;

function TWeChatReader.DiscoverDbFiles(const ADataPath: string): Boolean;
var
  LFiles: TArray<string>;
  LFile: string;
  LMsgDir, LContactDir, LSessionDir: string;
begin
  Result := False;
  if not TDirectory.Exists(ADataPath) then Exit;

  // ── Message files: flat layout first, then nested WCDB layout ──
  // Flat: ADataPath/message_0.db (legacy/extracted)
  // Nested: ADataPath/message/message_0.db (WCDB original structure)
  LFiles := TDirectory.GetFiles(ADataPath, 'message_*.db*',
    TSearchOption.soTopDirectoryOnly);
  for LFile in LFiles do
  begin
    if LFile.Contains('-wal') or LFile.Contains('-shm') then Continue;
    SetLength(FMessageFiles, Length(FMessageFiles) + 1);
    FMessageFiles[High(FMessageFiles)] := LFile;
  end;

  if Length(FMessageFiles) = 0 then
  begin
    LMsgDir := TPath.Combine(ADataPath, 'message');
    if TDirectory.Exists(LMsgDir) then
    begin
      LFiles := TDirectory.GetFiles(LMsgDir, 'message_*.db*',
        TSearchOption.soTopDirectoryOnly);
      for LFile in LFiles do
      begin
        if LFile.Contains('-wal') or LFile.Contains('-shm') then Continue;
        SetLength(FMessageFiles, Length(FMessageFiles) + 1);
        FMessageFiles[High(FMessageFiles)] := LFile;
      end;
    end;
  end;
  TArray.Sort<string>(FMessageFiles);

  // ── Contact file: ADataPath/contact.db or ADataPath/contact/contact.db ──
  LFile := TPath.Combine(ADataPath, 'contact.db');
  if TFile.Exists(LFile) then
    FContactFile := LFile
  else
  begin
    LContactDir := TPath.Combine(ADataPath, 'contact');
    LFile := TPath.Combine(LContactDir, 'contact.db');
    if TFile.Exists(LFile) then FContactFile := LFile;
  end;

  // ── Session file: ADataPath/session.db or ADataPath/session/session.db ──
  LFile := TPath.Combine(ADataPath, 'session.db');
  if TFile.Exists(LFile) then
    FSessionFile := LFile
  else
  begin
    LSessionDir := TPath.Combine(ADataPath, 'session');
    LFile := TPath.Combine(LSessionDir, 'session.db');
    if TFile.Exists(LFile) then FSessionFile := LFile;
  end;

  Result := (Length(FMessageFiles) > 0) and (FContactFile <> '');
end;

function TWeChatReader.ConnectToDb(const ADbPath: string;
  const AKeyBytes: TBytes): TFDConnection;
var
  LConn: TSnapshotSQLiteConnection;
  LTempPath: string;
  LSuffix: string;
const
  SIDE_SUFFIXES: array[0..2] of string = ('-wal', '-shm', '-journal');
begin
  LConn := TSnapshotSQLiteConnection.Create(nil);
  try
    LTempPath := TPath.Combine(TPath.GetTempPath,
      'DeepAxis_' + GenerateId + '_' + TPath.GetFileName(ADbPath));
    TFile.Copy(ADbPath, LTempPath, True);
    LConn.TrackTempFile(LTempPath);
    for LSuffix in SIDE_SUFFIXES do
    begin
      LConn.TrackTempFile(LTempPath + LSuffix);
      if TFile.Exists(ADbPath + LSuffix) then
        TFile.Copy(ADbPath + LSuffix, LTempPath + LSuffix, True);
    end;

    LConn.DriverName := 'SQLite';
    LConn.Params.Database := LTempPath;
    // Open the disposable snapshot read/write so SQLite can reconcile WAL/SHM.
    // Source DB files are never opened for writing, and the snapshot is deleted
    // when the connection is destroyed.
    LConn.Params.Add('OpenMode=ReadWrite');
    LConn.Params.Add('LockingMode=Normal');
    LConn.Params.Add('BusyTimeout=5000');
    LConn.Params.Add('StringFormat=Unicode');
    LConn.Open;
    Result := LConn;
  except
    LConn.Free;
    raise;
  end;
end;

function TWeChatReader.GetMsgTableNames(const AConnection: TFDConnection): TArray<string>;
var
  LQuery: TFDQuery;
begin
  Result := nil;
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := AConnection;
    LQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' AND name LIKE ''Msg_%''';
    LQuery.Open;
    while not LQuery.Eof do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LQuery.Fields[0].AsString;
      LQuery.Next;
    end;
  finally
    LQuery.Free;
  end;
end;

function TWeChatReader.BuildContactQuery: string;
begin
  Result :=
    'SELECT username, alias, remark, nick_name, flag, ' +
    'delete_flag, verify_flag, local_type, encrypt_username ' +
    'FROM contact ' +
    'WHERE delete_flag = 0 AND verify_flag = 0 ' +
    'AND (flag & 2048) = 0 ' +
    'ORDER BY username';
end;

function TWeChatReader.BuildMessageQuery(const ATableName: string): string;
begin
  Result :=
    'SELECT local_id, local_type, create_time, real_sender_id, status, server_seq, ' +
    'CAST(message_content AS BLOB) as msg_blob, ' +
    'CAST(source AS BLOB) as src_blob, ' +
    'WCDB_CT_message_content ' +
    'FROM ' + ATableName + ' ' +
    'WHERE real_sender_id IN (0, 1) ' +
    'AND local_id > :LastLocalId ' +
    'ORDER BY local_id ASC';
end;

function TWeChatReader.BuildSessionQuery: string;
begin
  Result :=
    'SELECT username, session_type, session_flag, last_message_time, ' +
    'unread_count, draft ' +
    'FROM session';
end;

function TWeChatReader.RowToContact(const ARow: TDataSet): TContact;
var
  LUsername: string;
  LNickname: string;
begin
  Result := Default(TContact);

  LUsername := ARow.FieldByName('username').AsString;
  LNickname := '';
  try
    if not ARow.FieldByName('nick_name').IsNull then
      LNickname := ARow.FieldByName('nick_name').AsString;
  except
  end;

  Result.ContactId := ComputeContactId(LUsername);
  if FContactIdToMsgTable <> nil then
    FContactIdToMsgTable.AddOrSetValue(Result.ContactId, ComputeMsgTableHash(LUsername));
  Result.SourceAccountId := '';
  Result.DisplayNameHash := SHA256Hex(LNickname);
  Result.DisplayNameRedacted := RedactDisplayName(LNickname);
  Result.Privacy := psUnknown;
  Result.PrivacySource := psSystemGuess;
  Result.FirstSeen := 0;
  Result.LastSeen := 0;
  Result.TagProfile := '{}';

  // Keep only a stable hash of remark in P0. Raw remarks often contain PII.
  try
    if not ARow.FieldByName('remark').IsNull then
    begin
      var LRemark := ARow.FieldByName('remark').AsString;
      if LRemark <> '' then
        Result.Remark := 'hash:' + SHA256Hex(LRemark);
    end;
  except
  end;
end;

function TWeChatReader.RowToMessageMeta(const ARow: TDataSet): TMessageMeta;
var
  LRawType: Int64;
  LRawSender: Int64;
  LCreateTime: Int64;
  LMsgBlob: TBytes;
  LSrcBlob: TBytes;
  LBlobField: TBlobField;
  LStream: TMemoryStream;
  LDecompressor: TZstdDecompressor;
begin
  Result := TMessageMeta.CreateM0;

  Result.SourceAccountId := FDataPath; // use data dir as account identifier
  Result.SourceRowRef := ARow.FieldByName('local_id').AsString;
  LRawType := ARow.FieldByName('local_type').AsLargeInt;
  LRawSender := ARow.FieldByName('real_sender_id').AsLargeInt;

  Result.RawType := LRawType;
  Result.NormalizedType := FAdapter.MapType(LRawType);
  Result.Direction := FAdapter.MapDirection(LRawSender);
  Result.DirectionEvidence := Format('real_sender_id=%d', [LRawSender]);

  if not ARow.FieldByName('create_time').IsNull then
  begin
    LCreateTime := ARow.FieldByName('create_time').AsLargeInt;
    // Unix timestamp to TDateTime
    Result.SentAt := (LCreateTime / 86400.0) + 25569.0;
  end;

  Result.IngestedAt := Now;
  Result.HasBodyColumn := True;
  Result.BodyQueried := True;

  // Decompress message_content (zstd)
  LDecompressor := TZstdDecompressor(FZstdDecompressor);
  try
    LBlobField := ARow.FieldByName('msg_blob') as TBlobField;
    if not LBlobField.IsNull then
    begin
      LStream := TMemoryStream.Create;
      try
        LBlobField.SaveToStream(LStream);
        SetLength(LMsgBlob, LStream.Size);
        if LStream.Size > 0 then
        begin
          LStream.Position := 0;
          LStream.ReadBuffer(LMsgBlob[0], LStream.Size);
        end;
        // Check if it's zstd compressed
        if TZstdDecompressor.IsZstdData(LMsgBlob) then
          Result.Body := LDecompressor.DecompressToString(LMsgBlob)
        else
          Result.Body := TZstdDecompressor.SmartDecode(LMsgBlob);
      finally
        LStream.Free;
      end;
    end;
  except
    // If decompression fails, leave Body empty
    Result.Body := '';
  end;

  // Decompress source (zstd)
  try
    LBlobField := ARow.FieldByName('src_blob') as TBlobField;
    if not LBlobField.IsNull then
    begin
      LStream := TMemoryStream.Create;
      try
        LBlobField.SaveToStream(LStream);
        SetLength(LSrcBlob, LStream.Size);
        if LStream.Size > 0 then
        begin
          LStream.Position := 0;
          LStream.ReadBuffer(LSrcBlob[0], LStream.Size);
        end;
        // Check if it's zstd compressed
        if TZstdDecompressor.IsZstdData(LSrcBlob) then
          Result.SourceXml := LDecompressor.DecompressToString(LSrcBlob)
        else
          Result.SourceXml := TZstdDecompressor.SmartDecode(LSrcBlob);
      finally
        LStream.Free;
      end;
    end;
  except
    // If decompression fails, leave SourceXml empty
    Result.SourceXml := '';
  end;
end;

function TWeChatReader.RowToConversation(const ARow: TDataSet): TConversation;
begin
  Result := Default(TConversation);
  Result.ConversationId := ARow.FieldByName('username').AsString;
  Result.Kind := 'DIRECT';
  if not ARow.FieldByName('session_type').IsNull then
  begin
    case ARow.FieldByName('session_type').AsInteger of
      0: Result.Kind := 'DIRECT';
      1: Result.Kind := 'GROUP';
    else
      Result.Kind := 'UNKNOWN';
    end;
  end;
  Result.PrivacyScope := psUnknown;
end;

function TWeChatReader.ComputeContactId(const AUsername: string): string;
begin
  Result := SHA256Hex(AUsername);
end;

function TWeChatReader.RedactDisplayName(const AName: string): string;
begin
  if AName = '' then
    Result := '未知'
  else if Length(AName) = 1 then
    Result := AName + '*'
  else
    Result := Copy(AName, 1, 1) + StringOfChar('*', Min(2, Length(AName) - 1));
end;

// ── Message DB cache ──────────────────────────────────────────────

procedure TWeChatReader.EnsureMsgDbCache;
var
  I: Integer;
begin
  if FMsgDbCacheReady then Exit;

  SetLength(FMsgDbCacheConns, Length(FMessageFiles));
  SetLength(FMsgDbCacheTables, Length(FMessageFiles));
  for I := 0 to Length(FMessageFiles) - 1 do
  begin
    FMsgDbCacheConns[I] := ConnectToDb(FMessageFiles[I], nil);
    FMsgDbCacheTables[I] := GetMsgTableNames(FMsgDbCacheConns[I]);
  end;
  FMsgDbCacheReady := True;
end;

procedure TWeChatReader.FreeMsgDbCache;
var
  I: Integer;
begin
  for I := 0 to Length(FMsgDbCacheConns) - 1 do
  begin
    if FMsgDbCacheConns[I] <> nil then
    begin
      if FMsgDbCacheConns[I].Connected then
        FMsgDbCacheConns[I].Close;
      FMsgDbCacheConns[I].Free;
    end;
  end;
  FMsgDbCacheConns := nil;
  FMsgDbCacheTables := nil;
  FMsgDbCacheReady := False;
end;

function TWeChatReader.ResolveMsgTableName(const AContactId: string): string;
begin
  // Resolve contact ID to Msg_<hash> table name
  if (FContactIdToMsgTable <> nil) and
     FContactIdToMsgTable.TryGetValue(AContactId, Result) then
    Exit;
  // Fallback: caller may have passed raw username or table name directly
  if SameText(Copy(AContactId, 1, Length(FAdapter.GetMsgTablePrefix)),
    FAdapter.GetMsgTablePrefix) then
    Result := AContactId
  else
    Result := ComputeMsgTableHash(AContactId);
end;

// ── IWxReader ────────────────────────────────────────────────────

function TWeChatReader.IsOpen: Boolean;
begin
  Result := FIsOpen;
end;

function TWeChatReader.GetAdapter: ISchemaAdapter;
begin
  Result := FAdapter;
end;

procedure TWeChatReader.Close;
begin
  FreeMsgDbCache;
  if FConnection <> nil then
  begin
    if FConnection.Connected then FConnection.Close;
    FConnection.Free;
    FConnection := nil;
  end;
  FContactIdToMsgTable.Free;
  FContactIdToMsgTable := nil;
  FIsOpen := False;
  FDataPath := '';
  FMessageFiles := nil;
  FContactFile := '';
  FSessionFile := '';
end;

function TWeChatReader.ReadContacts: TArray<TContact>;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LContact: TContact;
begin
  Result := nil;
  if not FIsOpen or (FContactFile = '') then Exit;

  FreeAndNil(FContactIdToMsgTable);
  FContactIdToMsgTable := TDictionary<string, string>.Create;

  LConn := ConnectToDb(FContactFile, nil);
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := BuildContactQuery;
      LQuery.Open;

      while not LQuery.Eof do
      begin
        LContact := RowToContact(LQuery);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LContact;
        LQuery.Next;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TWeChatReader.ReadMessages(const AContactId: string;
  const ASince: TScanCursor): TArray<TMessageMeta>;
var
  I, J: Integer;
  LConn: TFDConnection;
  LMsgTableNames: TArray<string>;
  LMsgTableName: string;
  LQuery: TFDQuery;
  LMsg: TMessageMeta;
  LFound: Boolean;
begin
  Result := nil;
  if not FIsOpen then Exit;

  // Use cached connections (open once, reuse across calls)
  EnsureMsgDbCache;

  for I := 0 to Length(FMsgDbCacheConns) - 1 do
  begin
    LConn := FMsgDbCacheConns[I];
    LMsgTableNames := FMsgDbCacheTables[I];

    // If AContactId is empty, read ALL Msg tables (for testing/aggregation)
    if AContactId = '' then
    begin
      for LMsgTableName in LMsgTableNames do
      begin
        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := LConn;
          LQuery.SQL.Text := BuildMessageQuery(LMsgTableName);
          LQuery.ParamByName('LastLocalId').AsLargeInt := ASince.LastLocalId;
          LQuery.Open;
          while not LQuery.Eof do
          begin
            LMsg := RowToMessageMeta(LQuery);
            LMsg.ContactId := LMsgTableName;
            LMsg.ConversationId := LMsgTableName;
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := LMsg;
            LQuery.Next;
          end;
        finally
          LQuery.Free;
        end;
      end;
    end
    else
    begin
      LMsgTableName := ResolveMsgTableName(AContactId);

      // Check if this table exists in this DB
      LFound := False;
      for J := 0 to Length(LMsgTableNames) - 1 do
        if SameText(LMsgTableNames[J], LMsgTableName) then
        begin
          LFound := True;
          Break;
        end;

      if not LFound then
        Continue;

      LQuery := TFDQuery.Create(nil);
      try
        LQuery.Connection := LConn;
        LQuery.SQL.Text := BuildMessageQuery(LMsgTableName);
        LQuery.ParamByName('LastLocalId').AsLargeInt := ASince.LastLocalId;
        LQuery.Open;
        while not LQuery.Eof do
        begin
          LMsg := RowToMessageMeta(LQuery);
          LMsg.ContactId := AContactId;
          LMsg.ConversationId := LMsgTableName;
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := LMsg;
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    end;
  end;
end;

function TWeChatReader.ReadAllMessages(const ASince: TScanCursor):
  TDictionary<string, TArray<TMessageMeta>>;
var
  I: Integer;
  LConn: TFDConnection;
  LMsgTableNames: TArray<string>;
  LMsgTableName: string;
  LQuery: TFDQuery;
  LMsg: TMessageMeta;
  LContactId: string;
  LExisting: TArray<TMessageMeta>;
  LTableToContact: TDictionary<string, string>;
  LPair: TPair<string, string>;
begin
  Result := TDictionary<string, TArray<TMessageMeta>>.Create;
  if not FIsOpen then Exit;

  EnsureMsgDbCache;

  // Build reverse map: Msg_<hash> → ContactId (O(M) once, O(1) per lookup)
  LTableToContact := TDictionary<string, string>.Create;
  try
    if FContactIdToMsgTable <> nil then
      for LPair in FContactIdToMsgTable do
        LTableToContact.AddOrSetValue(LPair.Value, LPair.Key);

    for I := 0 to Length(FMsgDbCacheConns) - 1 do
    begin
      LConn := FMsgDbCacheConns[I];
      LMsgTableNames := FMsgDbCacheTables[I];

      for LMsgTableName in LMsgTableNames do
      begin
        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := LConn;
          LQuery.SQL.Text := BuildMessageQuery(LMsgTableName);
          LQuery.ParamByName('LastLocalId').AsLargeInt := ASince.LastLocalId;
          LQuery.Open;
          while not LQuery.Eof do
          begin
            LMsg := RowToMessageMeta(LQuery);
            LMsg.ConversationId := LMsgTableName;

            // O(1) reverse-resolve: Msg_<hash> → ContactId
            if LTableToContact.TryGetValue(LMsgTableName, LContactId) then
              LMsg.ContactId := LContactId
            else
            begin
              LMsg.ContactId := LMsgTableName;
              LContactId := LMsgTableName;
            end;

            // Append to per-contact array
            if Result.TryGetValue(LContactId, LExisting) then
            begin
              SetLength(LExisting, Length(LExisting) + 1);
              LExisting[High(LExisting)] := LMsg;
              Result.Items[LContactId] := LExisting;
            end
            else
            begin
              SetLength(LExisting, 1);
              LExisting[0] := LMsg;
              Result.Add(LContactId, LExisting);
            end;

            LQuery.Next;
          end;
        finally
          LQuery.Free;
        end;
      end;
    end;
  finally
    LTableToContact.Free;
  end;
end;

function TWeChatReader.ReadConversations: TArray<TConversation>;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LConv: TConversation;
begin
  Result := nil;
  if not FIsOpen or (FSessionFile = '') then Exit;

  LConn := ConnectToDb(FSessionFile, nil);
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := BuildSessionQuery;
      LQuery.Open;
      while not LQuery.Eof do
      begin
        LConv := RowToConversation(LQuery);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := LConv;
        LQuery.Next;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TWeChatReader.GetScanCursors: TScanCursorArray;
begin
  Result := nil;
end;

end.
