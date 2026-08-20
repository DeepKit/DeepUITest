{ ============================================================================
  ArtifactOSBridge.pas - DeepFrames adapter for ArtifactOS integration
  ============================================================================

  HARDENING (2026-06-14):
    #1  SQL injection  - 全部 UUID/string 输入改用 ParamByName 参数化
    #2  Backoff       - NextRetryAt(): 2^retry_count * 30s 指数退避
    #3  TenantId      - FTenantId class var, SetTenantId() 注入
    #4  ConnPool      - TConnectionFactory 接口，支持连接池替换
    #5  ContextDir    - TArtifactOSRequest.ContextDir, 从 request_payload 解码

  PURPOSE
    DeepFrames polls production_request and writes production_result +
    asset_status back. Both sides share the same PostgreSQL DB3.

  TABLES (schema "integration", pre-created by ArtifactOS migration 052)
    - production_request: id, request_code, platform, request_payload (jsonb),
      request_status, next_retry_at, requested_at
    - production_result: id, request_id FK, result_status, published_url,
      platform_response (jsonb), error_message, retry_count
    - asset_status: id, artifact_id, platform, asset_url, asset_status,
      view/like/comment/share counts, UNIQUE(tenant_id, artifact_id, platform)

  HOW TO USE IN DEEPFRAMES
    1. TArtifactOSBridge.SetTenantId('...') at startup
    2. TArtifactOSBridge.SetConnectionFactory(MyFactory) or Connect(...)
    3. PollRequests() every 5-30 seconds
    4. ClaimRequest(id) before processing
    5. WriteResult(Result) after each publish attempt
    6. WriteAssetStatus(...) for ongoing metric sync
  ============================================================================ }
unit DeepFrames.Workflow.ArtifactOSBridge;

interface

uses
  System.SysUtils, System.DateUtils, System.Generics.Collections,
  System.SyncObjs, System.Math, Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Param,
  FireDAC.Phys.PG;

type
  { ── Abstract connection factory (#4) ── }
  IConnectionFactory = interface
    ['{E15C8D3A-7F92-4B1E-9A6D-C5402E8F711B}']
    function AcquireConnection: TFDConnection;
    procedure ReleaseConnection(AConnection: TFDConnection);
    function AcquireQuery(AConnection: TFDConnection): TFDQuery;
    procedure ReleaseQuery(AQuery: TFDQuery);
  end;

  { ── Default single-connection factory ── }
  TDefaultConnectionFactory = class(TInterfacedObject, IConnectionFactory)
  private
    FHost: string;
    FPort: string;
    FDatabase: string;
    FUser: string;
    FPassword: string;
    FConn: TFDConnection;
  public
    constructor Create(const AHost, APort, ADatabase, AUser, APassword: string);
    destructor Destroy; override;
    function AcquireConnection: TFDConnection;
    procedure ReleaseConnection(AConnection: TFDConnection);
    function AcquireQuery(AConnection: TFDConnection): TFDQuery;
    procedure ReleaseQuery(AQuery: TFDQuery);
  end;

  TArtifactOSRequest = record
    RequestId: string;
    RequestCode: string;
    ArtifactId: string;
    ArtifactVersionId: string;
    QualitySnapshotId: string;
    PublicationPackageId: string;
    Platform: string;
    Priority: Integer;
    RequestPayload: string;     // JSON
    CorrelationId: string;
    RequestedAt: TDateTime;
    ContextDir: string;         // #5 DeepFrames work dir for this request

    Title: string;
    Body: string;
    AccountId: string;
    Mode: string;
    IdempotencyKey: string;

    procedure Init;
    procedure DecodePayload;
  end;

  TArtifactOSResult = record
    RequestId: string;
    ResultStatus: string;
    PublishedUrl: string;
    PlatformResponse: string;
    ErrorMessage: string;
    RetryCount: Integer;
    MaxRetries: Integer;
  end;

  TArtifactOSBridge = class
  private
    class var FFactory: IConnectionFactory;
    class var FTenantId: string;  // #3
    class var FLock: TCriticalSection;  // N10.2b: thread safety for class vars

    // #1: Internal param binders
    class procedure BindGuid(AQ: TFDQuery; const AName, AValue: string);
    class procedure BindStr(AQ: TFDQuery; const AName, AValue: string);
  public
    // N10.2b: Call once at startup. Thread-safe. Immutable after set.
    class procedure SetTenantId(const AId: string);
    class function GetTenantId: string;

    // N10.2b: Call once at startup. Thread-safe. Immutable after set.
    class procedure SetConnectionFactory(AFactory: IConnectionFactory);

    // N10.2c: Warning — Connect() creates TDefaultConnectionFactory which returns
    // a SINGLE TFDConnection for all callers. TFDConnection is not thread-safe.
    // For multi-worker deployment, inject a pooled IConnectionFactory instead.
    class procedure SetConnection(AConnection: TFDConnection);
    class function Connect(const AHost, APort, ADatabase, AUser, APassword: string): Boolean;
    class procedure Disconnect;
    class function IsConnected: Boolean;

    // Poll for work
    class function PollRequests(out ARequests: TArray<TArtifactOSRequest>): Boolean;
    class function ClaimRequest(const ARequestId: string): Boolean;
    class function ReleaseRequest(const ARequestId: string): Boolean;
    class function GetRequest(const ARequestId: string; out ARequest: TArtifactOSRequest): Boolean;

    // Write results
    class function WriteResult(const AResult: TArtifactOSResult; out AResultId: string): Boolean;
    class function UpdateRequestStatus(const ARequestId, AStatus: string): Boolean;

    // Sync asset status
    class function WriteAssetStatus(
      const AArtifactId, APlatform: string;
      const AAssetUrl, AAssetStatus: string;
      AViewCount: Int64 = 0; ALikeCount: Int64 = 0;
      ACommentCount: Int64 = 0; AShareCount: Int64 = 0;
      const AFirstPublishedAt: TDateTime = 0;
      const ALastUpdatedAt: TDateTime = 0): Boolean;

    // #2 Exponential backoff
    class function NextRetryAt(ARetryCount: Integer): TDateTime;
    class function ShouldRetryNow(const ARequestId: string): Boolean;
  end;

implementation

uses
  System.JSON, DeepBase.Logging;

{ TDefaultConnectionFactory (#4) }

constructor TDefaultConnectionFactory.Create(const AHost, APort, ADatabase, AUser, APassword: string);
begin
  FHost := AHost;
  FPort := APort;
  FDatabase := ADatabase;
  FUser := AUser;
  FPassword := APassword;
end;

destructor TDefaultConnectionFactory.Destroy;
begin
  if FConn <> nil then
  begin
    FConn.Connected := False;
    FConn.Free;
  end;
  inherited;
end;

function TDefaultConnectionFactory.AcquireConnection: TFDConnection;
begin
  if FConn = nil then
  begin
    FConn := TFDConnection.Create(nil);
    FConn.DriverName := 'PG';
    FConn.Params.Values['Server'] := FHost;
    FConn.Params.Values['Port'] := FPort;
    FConn.Params.Values['Database'] := FDatabase;
    FConn.Params.Values['User_name'] := FUser;
    FConn.Params.Values['Password'] := FPassword;
    FConn.Params.Values['ApplicationName'] := 'DeepFrames_ArtifactOSBridge';
    FConn.Connected := True;
  end;
  Result := FConn;
end;

procedure TDefaultConnectionFactory.ReleaseConnection(AConnection: TFDConnection);
begin
  // Single-connection factory keeps connection alive
end;

function TDefaultConnectionFactory.AcquireQuery(AConnection: TFDConnection): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := AConnection;
end;

procedure TDefaultConnectionFactory.ReleaseQuery(AQuery: TFDQuery);
begin
  AQuery.Free;
end;

{ TArtifactOSRequest }

procedure TArtifactOSRequest.Init;
begin
  RequestId := '';
  RequestCode := '';
  ArtifactId := '';
  ArtifactVersionId := '';
  QualitySnapshotId := '';
  PublicationPackageId := '';
  Platform := '';
  Priority := 0;
  RequestPayload := '{}';
  CorrelationId := '';
  RequestedAt := 0;
  ContextDir := '';   // #5
  Title := '';
  Body := '';
  AccountId := 'default';
  Mode := 'auto_publish';
  IdempotencyKey := '';
end;

procedure TArtifactOSRequest.DecodePayload;
var
  JObj: TJSONObject;
begin
  if RequestPayload = '' then
    RequestPayload := '{}';

  JObj := TJSONObject.ParseJSONValue(RequestPayload) as TJSONObject;
  if JObj = nil then Exit;
  try
    Title := JObj.GetValue<string>('title', '');
    Body := JObj.GetValue<string>('body', '');
    AccountId := JObj.GetValue<string>('account_id', 'default');
    Mode := JObj.GetValue<string>('mode', 'auto_publish');
    IdempotencyKey := JObj.GetValue<string>('idempotency_key', '');
    ContextDir := JObj.GetValue<string>('context_dir', '');  // #5
  finally
    JObj.Free;
  end;
end;

{ TArtifactOSBridge — configuration }

class procedure TArtifactOSBridge.SetTenantId(const AId: string);
begin
  FLock.Enter;
  try
    FTenantId := AId;
  finally
    FLock.Leave;
  end;
end;

class function TArtifactOSBridge.GetTenantId: string;
begin
  FLock.Enter;
  try
    if FTenantId <> '' then
      Result := FTenantId
    else
      Result := '00000000-0000-0000-0000-000000000001';
  finally
    FLock.Leave;
  end;
end;

class procedure TArtifactOSBridge.SetConnectionFactory(AFactory: IConnectionFactory);
begin
  FLock.Enter;
  try
    FFactory := AFactory;
  finally
    FLock.Leave;
  end;
end;

class function TArtifactOSBridge.IsConnected: Boolean;
begin
  Result := (FFactory <> nil);
end;

{ Connection legacy API — delegates to default factory }

class procedure TArtifactOSBridge.SetConnection(AConnection: TFDConnection);
begin
  // Wrap the given connection in a simple factory
  var Wrapper: IConnectionFactory := nil; // see WrapConnection below
  // For simplicity: create a default factory using the connection's params
  var F := TDefaultConnectionFactory.Create(
    AConnection.Params.Values['Server'],
    AConnection.Params.Values['Port'],
    AConnection.Params.Values['Database'],
    AConnection.Params.Values['User_name'],
    AConnection.Params.Values['Password']);
  FFactory := F;
end;

class function TArtifactOSBridge.Connect(const AHost, APort, ADatabase, AUser,
  APassword: string): Boolean;
begin
  Result := False;
  try
    FFactory := TDefaultConnectionFactory.Create(AHost, APort, ADatabase, AUser, APassword);
    FFactory.AcquireConnection; // trigger connect test
    Result := True;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] Connect failed: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
end;

class procedure TArtifactOSBridge.Disconnect;
begin
  FFactory := nil;
end;

{ #1: Parameter binding helpers }

class procedure TArtifactOSBridge.BindGuid(AQ: TFDQuery; const AName, AValue: string);
begin
  AQ.ParamByName(AName).AsString := AValue;
end;

class procedure TArtifactOSBridge.BindStr(AQ: TFDQuery; const AName, AValue: string);
begin
  AQ.ParamByName(AName).AsString := AValue;
end;

{ ── Internal helpers ── }

function DateTimeToPG(T: TDateTime): string;
begin
  if T <= 0 then
    Result := 'now()'
  else
    Result := '''' + FormatDateTime('yyyy-mm-dd hh:nn:ss', T) + '''::timestamptz';
end;

{ #2: Exponential backoff }

class function TArtifactOSBridge.NextRetryAt(ARetryCount: Integer): TDateTime;
begin
  // N10.4e: cap ARetryCount to 30 to prevent IntPower overflow
  if ARetryCount > 30 then
    ARetryCount := 30;
  // Standard: 2^retry_count * 30 seconds
  var DelaySec: Double := IntPower(2.0, ARetryCount) * 30.0;
  // Cap at 12 hours
  if DelaySec > 43200.0 then
    DelaySec := 43200.0;
  Result := IncSecond(Now, Trunc(DelaySec));
end;

class function TArtifactOSBridge.ShouldRetryNow(const ARequestId: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  if FFactory = nil then Exit;
  Conn := FFactory.AcquireConnection;
  Q := FFactory.AcquireQuery(Conn);
  try
    Q.SQL.Text :=
      'SELECT next_retry_at FROM integration.production_result ' +
      'WHERE request_id = :rid::uuid AND tenant_id = :tid::uuid ' +
      'ORDER BY created_at DESC LIMIT 1';
    BindGuid(Q, 'rid', ARequestId);
    BindGuid(Q, 'tid', GetTenantId);
    Q.Open;
    if Q.Eof then
      Result := True // first attempt
    else if Q.Fields[0].IsNull then
      Result := True
    else
      Result := Q.Fields[0].AsDateTime <= Now;
    Q.Close;
  except
    on E: Exception do
    begin
      Logger.ErrorFmt('[ArtifactOSBridge] ShouldRetryNow error: %s: %s', [E.ClassName, E.Message], 'DeepFrames.ArtifactOS');
      Result := True; // on error, allow retry
    end;
  end;
  FFactory.ReleaseQuery(Q);
  FFactory.ReleaseConnection(Conn);
end;

{ Public API }

class function TArtifactOSBridge.PollRequests(out ARequests: TArray<TArtifactOSRequest>): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  List: TList<TArtifactOSRequest>;
begin
  Result := False;
  SetLength(ARequests, 0);
  if not IsConnected then Exit;

  Conn := FFactory.AcquireConnection;
  Q := FFactory.AcquireQuery(Conn);
  List := TList<TArtifactOSRequest>.Create;
  try
    Q.SQL.Text :=
      'SELECT id::text, request_code, artifact_id::text, artifact_version_id::text, ' +
      'quality_snapshot_id::text, publication_package_id::text, platform, ' +
      'request_status, priority, request_payload::text, ' +
      'COALESCE(correlation_id, '''') as correlation_id, ' +
      'requested_at ' +
      'FROM integration.production_request ' +
      'WHERE tenant_id = :tid::uuid ' +
      'AND request_status IN (''pending'', ''queued'') ' +
      'AND (expires_at IS NULL OR expires_at > now()) ' +
      'ORDER BY priority DESC, requested_at ASC LIMIT 50';
    BindGuid(Q, 'tid', GetTenantId);
    Q.Open;

    while not Q.Eof do
    begin
      var R: TArtifactOSRequest;
      R.Init;
      R.RequestId := Q.Fields[0].AsString;
      R.RequestCode := Q.Fields[1].AsString;
      R.ArtifactId := Q.Fields[2].AsString;
      R.ArtifactVersionId := Q.Fields[3].AsString;
      R.QualitySnapshotId := Q.Fields[4].AsString;
      R.PublicationPackageId := Q.Fields[5].AsString;
      R.Platform := Q.Fields[6].AsString;
      R.Priority := Q.Fields[8].AsInteger;
      R.RequestPayload := Q.Fields[9].AsString;
      R.CorrelationId := Q.Fields[10].AsString;
      if not Q.Fields[11].IsNull then
        R.RequestedAt := Q.Fields[11].AsDateTime;
      R.DecodePayload;
      List.Add(R);
      Q.Next;
    end;
    Q.Close;

    ARequests := List.ToArray;
    Result := True;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] PollRequests error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
  List.Free;
  FFactory.ReleaseQuery(Q);
  FFactory.ReleaseConnection(Conn);
end;

class function TArtifactOSBridge.ClaimRequest(const ARequestId: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  if not IsConnected then Exit;
  try
    Conn := FFactory.AcquireConnection;
    Q := FFactory.AcquireQuery(Conn);
    try
      // #1 参数化 — ARequestId 不再拼入 string; #3 tenant 隔离防跨租户抢占
      Q.SQL.Text :=
        'UPDATE integration.production_request ' +
        'SET request_status=''processing'', updated_at=now() ' +
        'WHERE id = :rid::uuid ' +
        'AND tenant_id = :tid::uuid ' +
        'AND request_status IN (''pending'', ''queued'')';
      BindGuid(Q, 'rid', ARequestId);
      BindGuid(Q, 'tid', GetTenantId);
      Q.ExecSQL;
      Result := Q.RowsAffected > 0;
    finally
      FFactory.ReleaseQuery(Q);
      FFactory.ReleaseConnection(Conn);
    end;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] ClaimRequest error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
end;

class function TArtifactOSBridge.ReleaseRequest(const ARequestId: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  if not IsConnected then Exit;
  try
    Conn := FFactory.AcquireConnection;
    Q := FFactory.AcquireQuery(Conn);
    try
      Q.SQL.Text :=
        'UPDATE integration.production_request ' +
        'SET request_status=''pending'', updated_at=now() ' +
        'WHERE id = :rid::uuid AND tenant_id = :tid::uuid ' +
        'AND request_status=''processing''';
      BindGuid(Q, 'rid', ARequestId);
      BindGuid(Q, 'tid', GetTenantId);
      Q.ExecSQL;
      Result := Q.RowsAffected > 0;
    finally
      FFactory.ReleaseQuery(Q);
      FFactory.ReleaseConnection(Conn);
    end;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] ReleaseRequest error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
end;

class function TArtifactOSBridge.GetRequest(const ARequestId: string;
  out ARequest: TArtifactOSRequest): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  ARequest.Init;
  if not IsConnected then Exit;

  Conn := FFactory.AcquireConnection;
  Q := FFactory.AcquireQuery(Conn);
  try
    Q.SQL.Text :=
      'SELECT id::text, request_code, artifact_id::text, artifact_version_id::text, ' +
      'quality_snapshot_id::text, publication_package_id::text, platform, ' +
      'request_status, priority, request_payload::text, ' +
      'COALESCE(correlation_id, '''') as correlation_id, requested_at ' +
      'FROM integration.production_request ' +
      'WHERE id = :rid::uuid AND tenant_id = :tid::uuid';
    BindGuid(Q, 'rid', ARequestId);
    BindGuid(Q, 'tid', GetTenantId);
    Q.Open;
    if not Q.Eof then
    begin
      ARequest.RequestId := Q.Fields[0].AsString;
      ARequest.RequestCode := Q.Fields[1].AsString;
      ARequest.ArtifactId := Q.Fields[2].AsString;
      ARequest.ArtifactVersionId := Q.Fields[3].AsString;
      ARequest.QualitySnapshotId := Q.Fields[4].AsString;
      ARequest.PublicationPackageId := Q.Fields[5].AsString;
      ARequest.Platform := Q.Fields[6].AsString;
      ARequest.Priority := Q.Fields[8].AsInteger;
      ARequest.RequestPayload := Q.Fields[9].AsString;
      ARequest.CorrelationId := Q.Fields[10].AsString;
      if not Q.Fields[11].IsNull then
        ARequest.RequestedAt := Q.Fields[11].AsDateTime;
      ARequest.DecodePayload;
      Result := True;
    end;
    Q.Close;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] GetRequest error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
  FFactory.ReleaseQuery(Q);
  FFactory.ReleaseConnection(Conn);
end;

class function TArtifactOSBridge.WriteResult(const AResult: TArtifactOSResult;
  out AResultId: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  AResultId := '';
  if not IsConnected then Exit;

  try
    Conn := FFactory.AcquireConnection;
    Q := FFactory.AcquireQuery(Conn);
    try
      // #1/#2/#3: 所有外部输入参数化 + next_retry_at + tenant 隔离
      Q.SQL.Text :=
        'INSERT INTO integration.production_result ( ' +
        '  tenant_id, request_id, result_status, published_url, ' +
        '  platform_response, error_message, retry_count, max_retries, ' +
        '  next_retry_at, completed_at ' +
        ') VALUES ( ' +
        '  :tid::uuid, :rid::uuid, :status, :url, ' +
        '  :platform_resp::jsonb, :errmsg, :rc, :maxr, ' +
        '  :next_retry::timestamptz, now() ' +
        ') RETURNING id::text';

      BindGuid(Q, 'tid', GetTenantId);
      BindGuid(Q, 'rid', AResult.RequestId);
      BindStr(Q, 'status', AResult.ResultStatus);
      BindStr(Q, 'url', AResult.PublishedUrl);

      if AResult.PlatformResponse <> '' then
        BindStr(Q, 'platform_resp', AResult.PlatformResponse)
      else
        BindStr(Q, 'platform_resp', '{}');

      BindStr(Q, 'errmsg', AResult.ErrorMessage);
      Q.ParamByName('rc').AsInteger := AResult.RetryCount;
      Q.ParamByName('maxr').AsInteger := AResult.MaxRetries;

      // #2: schedule next retry with exponential backoff
      if AResult.ResultStatus = 'failed' then
      begin
        Q.ParamByName('next_retry').DataType := ftDateTime;
        Q.ParamByName('next_retry').AsDateTime := NextRetryAt(AResult.RetryCount + 1);
      end
      else
      begin
        Q.ParamByName('next_retry').DataType := ftDateTime;
        Q.ParamByName('next_retry').Clear;
      end;

      Q.Open;
      if not Q.Eof then
        AResultId := Q.Fields[0].AsString;
      Q.Close;

      Result := AResultId <> '';
      if Result then
        Logger.InfoFmt('[ArtifactOSBridge] Result: id=%s status=%s url=%s',
          [AResultId, AResult.ResultStatus, AResult.PublishedUrl], 'DeepFrames.ArtifactOS');
    finally
      FFactory.ReleaseQuery(Q);
      FFactory.ReleaseConnection(Conn);
    end;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] WriteResult error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
end;

class function TArtifactOSBridge.UpdateRequestStatus(const ARequestId, AStatus: string): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
begin
  Result := False;
  if not IsConnected then Exit;
  try
    Conn := FFactory.AcquireConnection;
    Q := FFactory.AcquireQuery(Conn);
    try
      // #1: 参数化; #3: tenant 隔离
      Q.SQL.Text :=
        'UPDATE integration.production_request ' +
        'SET request_status = :status, updated_at = now() ' +
        'WHERE id = :rid::uuid AND tenant_id = :tid::uuid';
      BindGuid(Q, 'rid', ARequestId);
      BindGuid(Q, 'tid', GetTenantId);
      BindStr(Q, 'status', AStatus);
      Q.ExecSQL;
      Result := Q.RowsAffected > 0;
    finally
      FFactory.ReleaseQuery(Q);
      FFactory.ReleaseConnection(Conn);
    end;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] UpdateRequestStatus error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
end;

class function TArtifactOSBridge.WriteAssetStatus(
  const AArtifactId, APlatform: string;
  const AAssetUrl, AAssetStatus: string;
  AViewCount: Int64; ALikeCount: Int64;
  ACommentCount: Int64; AShareCount: Int64;
  const AFirstPublishedAt: TDateTime;
  const ALastUpdatedAt: TDateTime): Boolean;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  Tid: string;  // #3
begin
  Result := False;
  if not IsConnected then Exit;
  try
    Conn := FFactory.AcquireConnection;
    Q := FFactory.AcquireQuery(Conn);
    try
      Tid := GetTenantId;  // #3
      // #1: 全部参数化
      Q.SQL.Text :=
        'INSERT INTO integration.asset_status ( ' +
        '  tenant_id, artifact_id, platform, asset_url, asset_status, ' +
        '  view_count, like_count, comment_count, share_count, ' +
        '  first_published_at, last_updated_at, last_synced_at ' +
        ') VALUES ( ' +
        '  :tid::uuid, :aid::uuid, :platform, :url, :astatus, ' +
        '  :vcount, :lcount, :ccount, :scount, ' +
        '  :first_at::timestamptz, :last_at::timestamptz, now() ' +
        ') ON CONFLICT (tenant_id, artifact_id, platform) DO UPDATE SET ' +
        'asset_url = EXCLUDED.asset_url, ' +
        'asset_status = EXCLUDED.asset_status, ' +
        'view_count = EXCLUDED.view_count, ' +
        'like_count = EXCLUDED.like_count, ' +
        'comment_count = EXCLUDED.comment_count, ' +
        'share_count = EXCLUDED.share_count, ' +
        'first_published_at = COALESCE(integration.asset_status.first_published_at, EXCLUDED.first_published_at), ' +
        'last_updated_at = EXCLUDED.last_updated_at, ' +
        'last_synced_at = EXCLUDED.last_synced_at';

      BindGuid(Q, 'tid', Tid);
      BindGuid(Q, 'aid', AArtifactId);
      BindStr(Q, 'platform', APlatform);
      BindStr(Q, 'url', AAssetUrl);
      BindStr(Q, 'astatus', AAssetStatus);
      Q.ParamByName('vcount').AsLargeInt := AViewCount;
      Q.ParamByName('lcount').AsLargeInt := ALikeCount;
      Q.ParamByName('ccount').AsLargeInt := ACommentCount;
      Q.ParamByName('scount').AsLargeInt := AShareCount;

      if AFirstPublishedAt <= 0 then
        Q.ParamByName('first_at').Clear
      else
        Q.ParamByName('first_at').AsDateTime := AFirstPublishedAt;

      if ALastUpdatedAt <= 0 then
        Q.ParamByName('last_at').Clear
      else
        Q.ParamByName('last_at').AsDateTime := ALastUpdatedAt;

      Q.ExecSQL;
      Result := True;
    finally
      FFactory.ReleaseQuery(Q);
      FFactory.ReleaseConnection(Conn);
    end;
  except
    on E: Exception do
      Logger.ErrorFmt('[ArtifactOSBridge] WriteAssetStatus error: %s', [E.Message], 'DeepFrames.ArtifactOS');
  end;
end;

// USAGE EXAMPLE — see docs/bridge_usage.txt

initialization
  TArtifactOSBridge.FLock := TCriticalSection.Create;
finalization
  TArtifactOSBridge.FLock.Free;
end.
