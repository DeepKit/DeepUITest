unit UniFlow.Storage.PostgreSQL;

{*******************************************************}
{                                                       }
{       UniFlow PostgreSQL 存储后端实现                 }
{                                                       }
{       版权所�?(C) 2024 UniFlow                       }
{                                                       }
{*******************************************************}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.SyncObjs, System.Threading, System.Net.HttpClient,
  UniFlow.Storage.Types,
  DeepBase.Exceptions;

type
  {==========================================================================}
  {  数据库连接接�?                                                         }
  {==========================================================================}
  IDbConnection = interface
    ['{D1E2F3A4-B5C6-7890-ABCD-EF1234567890}']
    function IsConnected: Boolean;
    procedure Connect;
    procedure Disconnect;
    function Execute(const ASQL: string; const AParams: TQueryParams): TResultSet;
    function ExecuteScalar(const ASQL: string; const AParams: TQueryParams): Variant;
    procedure BeginTransaction(AIsolation: TIsolationLevel = ilReadCommitted);
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
  end;

  {==========================================================================}
  {  PostgreSQL 连接实现 (HTTP REST)                                         }
  {==========================================================================}
  TPostgreSQLConnection = class(TInterfacedObject, IDbConnection)
  private
    FConfig: TPostgreSQLConfig;
    FHttpClient: THTTPClient;
    FRestEndpoint: string;
    FConnected: Boolean;
    FInTransaction: Boolean;
    FLock: TCriticalSection;
    
    function BuildRequestBody(const ASQL: string; const AParams: TQueryParams): TJSONObject;
    function ParseResponse(const AResponse: string): TResultSet;
  public
    constructor Create(const AConfig: TPostgreSQLConfig; const ARestEndpoint: string);
    destructor Destroy; override;
    
    function IsConnected: Boolean;
    procedure Connect;
    procedure Disconnect;
    function Execute(const ASQL: string; const AParams: TQueryParams): TResultSet;
    function ExecuteScalar(const ASQL: string; const AParams: TQueryParams): Variant;
    procedure BeginTransaction(AIsolation: TIsolationLevel = ilReadCommitted);
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    
    property Config: TPostgreSQLConfig read FConfig;
  end;

  {==========================================================================}
  {  连接�?                                                                 }
  {==========================================================================}
  TConnectionPool = class
  private
    FConfig: TPostgreSQLConfig;
    FRestEndpoint: string;
    FConnections: TList<IDbConnection>;
    FAvailable: TList<IDbConnection>;
    FLock: TCriticalSection;
    FMinSize: Integer;
    FMaxSize: Integer;
    
    procedure CreateConnection;
  public
    constructor Create(const AConfig: TPostgreSQLConfig; const ARestEndpoint: string;
      AMinSize: Integer = 2; AMaxSize: Integer = 10);
    destructor Destroy; override;
    
    function Acquire: IDbConnection;
    procedure Release(AConnection: IDbConnection);
    function GetActiveCount: Integer;
    function GetAvailableCount: Integer;
  end;

  {==========================================================================}
  {  存储仓库接口                                                            }
  {==========================================================================}
  IRepository<T: TStorageEntity> = interface
    ['{E2F3A4B5-C6D7-8901-BCDE-F12345678901}']
    function FindById(const AId: string): T;
    function FindAll(APagination: TPagination): TObjectList<T>;
    function FindByConditions(const AConditions: TFilterConditions; 
      APagination: TPagination): TObjectList<T>;
    function Count: Int64;
    function CountByConditions(const AConditions: TFilterConditions): Int64;
    procedure Insert(AEntity: T);
    procedure Update(AEntity: T);
    procedure Delete(const AId: string);
    procedure DeleteByConditions(const AConditions: TFilterConditions);
    function Exists(const AId: string): Boolean;
  end;

  {==========================================================================}
  {  工作流仓�?                                                             }
  {==========================================================================}
  TWorkflowRepository = class(TInterfacedObject, IRepository<TWorkflowEntity>)
  private
    FPool: TConnectionPool;
    FTableName: string;
    FTenantId: string;
  public
    constructor Create(APool: TConnectionPool; const ATenantId: string = '');
    
    function FindById(const AId: string): TWorkflowEntity;
    function FindAll(APagination: TPagination): TObjectList<TWorkflowEntity>;
    function FindByConditions(const AConditions: TFilterConditions;
      APagination: TPagination): TObjectList<TWorkflowEntity>;
    function FindByName(const AName: string): TWorkflowEntity;
    function FindByStatus(const AStatus: string; APagination: TPagination): TObjectList<TWorkflowEntity>;
    function FindByTags(const ATags: TArray<string>; APagination: TPagination): TObjectList<TWorkflowEntity>;
    function Count: Int64;
    function CountByConditions(const AConditions: TFilterConditions): Int64;
    procedure Insert(AEntity: TWorkflowEntity);
    procedure Update(AEntity: TWorkflowEntity);
    procedure Delete(const AId: string);
    procedure DeleteByConditions(const AConditions: TFilterConditions);
    function Exists(const AId: string): Boolean;
  end;

  {==========================================================================}
  {  会话仓库                                                                }
  {==========================================================================}
  TSessionRepository = class(TInterfacedObject, IRepository<TSessionEntity>)
  private
    FPool: TConnectionPool;
    FTableName: string;
    FTenantId: string;
  public
    constructor Create(APool: TConnectionPool; const ATenantId: string = '');
    
    function FindById(const AId: string): TSessionEntity;
    function FindAll(APagination: TPagination): TObjectList<TSessionEntity>;
    function FindByConditions(const AConditions: TFilterConditions;
      APagination: TPagination): TObjectList<TSessionEntity>;
    function FindByWorkflowId(const AWorkflowId: string; APagination: TPagination): TObjectList<TSessionEntity>;
    function FindByUserId(const AUserId: string; APagination: TPagination): TObjectList<TSessionEntity>;
    function FindByStatus(const AStatus: string; APagination: TPagination): TObjectList<TSessionEntity>;
    function FindActive: TObjectList<TSessionEntity>;
    function Count: Int64;
    function CountByConditions(const AConditions: TFilterConditions): Int64;
    function CountActive: Int64;
    procedure Insert(AEntity: TSessionEntity);
    procedure Update(AEntity: TSessionEntity);
    procedure Delete(const AId: string);
    procedure DeleteByConditions(const AConditions: TFilterConditions);
    function Exists(const AId: string): Boolean;
  end;

  {==========================================================================}
  {  技能仓�?                                                               }
  {==========================================================================}
  TSkillRepository = class(TInterfacedObject, IRepository<TSkillEntity>)
  private
    FPool: TConnectionPool;
    FTableName: string;
    FTenantId: string;
  public
    constructor Create(APool: TConnectionPool; const ATenantId: string = '');
    
    function FindById(const AId: string): TSkillEntity;
    function FindAll(APagination: TPagination): TObjectList<TSkillEntity>;
    function FindByConditions(const AConditions: TFilterConditions;
      APagination: TPagination): TObjectList<TSkillEntity>;
    function FindByName(const AName: string): TSkillEntity;
    function FindByCategory(const ACategory: string; APagination: TPagination): TObjectList<TSkillEntity>;
    function FindEnabled: TObjectList<TSkillEntity>;
    function Count: Int64;
    function CountByConditions(const AConditions: TFilterConditions): Int64;
    procedure Insert(AEntity: TSkillEntity);
    procedure Update(AEntity: TSkillEntity);
    procedure Delete(const AId: string);
    procedure DeleteByConditions(const AConditions: TFilterConditions);
    function Exists(const AId: string): Boolean;
  end;

  {==========================================================================}
  {  PostgreSQL 存储后端                                                     }
  {==========================================================================}
  TPostgreSQLStorageBackend = class
  private
    FConfig: TPostgreSQLConfig;
    FPool: TConnectionPool;
    FRestEndpoint: string;
    FWorkflowRepo: TWorkflowRepository;
    FSessionRepo: TSessionRepository;
    FSkillRepo: TSkillRepository;
    FInitialized: Boolean;
  public
    constructor Create(const AConfig: TPostgreSQLConfig; const ARestEndpoint: string);
    destructor Destroy; override;
    
    procedure Initialize;
    procedure CreateSchema;
    procedure DropSchema;
    procedure MigrateSchema(ATargetVersion: Integer);
    
    function GetStatistics: TStorageStatistics;
    
    property Workflows: TWorkflowRepository read FWorkflowRepo;
    property Sessions: TSessionRepository read FSessionRepo;
    property Skills: TSkillRepository read FSkillRepo;
    property Pool: TConnectionPool read FPool;
    property Initialized: Boolean read FInitialized;
  end;

  {==========================================================================}
  {  Schema 迁移�?                                                          }
  {==========================================================================}
  TSchemaMigration = record
    Version: Integer;
    Name: string;
    UpSQL: string;
    DownSQL: string;
  end;

  TSchemaMigrator = class
  private
    FPool: TConnectionPool;
    FMigrations: TList<TSchemaMigration>;
    FSchema: string;
    
    function GetCurrentVersion: Integer;
    procedure SetCurrentVersion(AVersion: Integer);
    procedure ExecuteMigration(const AMigration: TSchemaMigration; AUp: Boolean);
  public
    constructor Create(APool: TConnectionPool; const ASchema: string = 'public');
    destructor Destroy; override;
    
    procedure AddMigration(AVersion: Integer; const AName, AUpSQL, ADownSQL: string);
    procedure Migrate(ATargetVersion: Integer = -1);
    procedure Rollback(ATargetVersion: Integer = 0);
    function GetAppliedMigrations: TArray<Integer>;
    
    property CurrentVersion: Integer read GetCurrentVersion;
  end;

const
  SCHEMA_VERSION = 1;
  
  SQL_CREATE_WORKFLOWS = 
    'CREATE TABLE IF NOT EXISTS workflows (' +
    '  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),' +
    '  tenant_id VARCHAR(64),' +
    '  name VARCHAR(255) NOT NULL,' +
    '  description TEXT,' +
    '  definition JSONB NOT NULL DEFAULT ''{}'',' +
    '  status VARCHAR(32) DEFAULT ''draft'',' +
    '  tags TEXT[] DEFAULT ''{}'',' +
    '  version INTEGER DEFAULT 1,' +
    '  created_at TIMESTAMPTZ DEFAULT NOW(),' +
    '  updated_at TIMESTAMPTZ DEFAULT NOW()' +
    ')';
    
  SQL_CREATE_SESSIONS =
    'CREATE TABLE IF NOT EXISTS sessions (' +
    '  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),' +
    '  tenant_id VARCHAR(64),' +
    '  workflow_id UUID REFERENCES workflows(id),' +
    '  user_id VARCHAR(64),' +
    '  status VARCHAR(32) DEFAULT ''pending'',' +
    '  current_step VARCHAR(255),' +
    '  context JSONB DEFAULT ''{}'',' +
    '  started_at TIMESTAMPTZ,' +
    '  completed_at TIMESTAMPTZ,' +
    '  version INTEGER DEFAULT 1,' +
    '  created_at TIMESTAMPTZ DEFAULT NOW(),' +
    '  updated_at TIMESTAMPTZ DEFAULT NOW()' +
    ')';
    
  SQL_CREATE_SKILLS =
    'CREATE TABLE IF NOT EXISTS skills (' +
    '  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),' +
    '  tenant_id VARCHAR(64),' +
    '  name VARCHAR(255) NOT NULL,' +
    '  description TEXT,' +
    '  runtime VARCHAR(32) DEFAULT ''python'',' +
    '  code TEXT,' +
    '  input_schema JSONB DEFAULT ''{}'',' +
    '  output_schema JSONB DEFAULT ''{}'',' +
    '  category VARCHAR(64),' +
    '  enabled BOOLEAN DEFAULT TRUE,' +
    '  version INTEGER DEFAULT 1,' +
    '  created_at TIMESTAMPTZ DEFAULT NOW(),' +
    '  updated_at TIMESTAMPTZ DEFAULT NOW()' +
    ')';
    
  SQL_CREATE_MIGRATIONS =
    'CREATE TABLE IF NOT EXISTS schema_migrations (' +
    '  version INTEGER PRIMARY KEY,' +
    '  name VARCHAR(255),' +
    '  applied_at TIMESTAMPTZ DEFAULT NOW()' +
    ')';
    
  SQL_CREATE_INDEXES =
    'CREATE INDEX IF NOT EXISTS idx_workflows_tenant ON workflows(tenant_id);' +
    'CREATE INDEX IF NOT EXISTS idx_workflows_status ON workflows(status);' +
    'CREATE INDEX IF NOT EXISTS idx_workflows_tags ON workflows USING GIN(tags);' +
    'CREATE INDEX IF NOT EXISTS idx_sessions_tenant ON sessions(tenant_id);' +
    'CREATE INDEX IF NOT EXISTS idx_sessions_workflow ON sessions(workflow_id);' +
    'CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);' +
    'CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);' +
    'CREATE INDEX IF NOT EXISTS idx_skills_tenant ON skills(tenant_id);' +
    'CREATE INDEX IF NOT EXISTS idx_skills_category ON skills(category);';

implementation

uses
  System.Variants, System.NetEncoding;

{==========================================================================}
{  TPostgreSQLConnection                                                   }
{==========================================================================}

constructor TPostgreSQLConnection.Create(const AConfig: TPostgreSQLConfig;
  const ARestEndpoint: string);
begin
  inherited Create;
  FConfig := AConfig;
  FRestEndpoint := ARestEndpoint;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ContentType := 'application/json';
  FConnected := False;
  FInTransaction := False;
  FLock := TCriticalSection.Create;
end;

destructor TPostgreSQLConnection.Destroy;
begin
  Disconnect;
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

function TPostgreSQLConnection.IsConnected: Boolean;
begin
  Result := FConnected;
end;

procedure TPostgreSQLConnection.Connect;
var
  LBody: TJSONObject;
  LStream: TStringStream;
  LResp: IHTTPResponse;
begin
  if FConnected then Exit;
  
  FLock.Enter;
  try
    LBody := TJSONObject.Create;
    try
      LBody.AddPair('action', 'connect');
      LBody.AddPair('config', FConfig.ToJSON);
      
      LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
      try
        LResp := FHttpClient.Post(FRestEndpoint + '/connect', LStream);
        FConnected := LResp.StatusCode = 200;
      finally
        LStream.Free;
      end;
    finally
      LBody.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TPostgreSQLConnection.Disconnect;
begin
  if not FConnected then Exit;
  
  FLock.Enter;
  try
    FHttpClient.Post(FRestEndpoint + '/disconnect', nil);
    FConnected := False;
  finally
    FLock.Leave;
  end;
end;

function TPostgreSQLConnection.BuildRequestBody(const ASQL: string;
  const AParams: TQueryParams): TJSONObject;
var
  LParams: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('sql', ASQL);
  
  LParams := TJSONArray.Create;
  for I := 0 to High(AParams) do
  begin
    if VarIsNull(AParams[I].Value) then
      LParams.Add(TJSONNull.Create)
    else if VarType(AParams[I].Value) = varBoolean then
      LParams.Add(TJSONBool.Create(AParams[I].Value))
    else if VarIsNumeric(AParams[I].Value) then
      LParams.Add(TJSONNumber.Create(Double(AParams[I].Value)))
    else
      LParams.Add(VarToStr(AParams[I].Value));
  end;
  Result.AddPair('params', LParams);
end;

function TPostgreSQLConnection.ParseResponse(const AResponse: string): TResultSet;
var
  LJSON: TJSONObject;
  LRows: TJSONArray;
  LRow: TJSONValue;
  LResultRow: TResultRow;
  LCols: TJSONArray;
  I: Integer;
begin
  Result := TResultSet.Create;
  
  LJSON := TJSONObject.ParseJSONValue(AResponse) as TJSONObject;
  if not Assigned(LJSON) then Exit;
  
  try
    Result.AffectedRows := LJSON.GetValue<Int64>('affected_rows', 0);
    Result.LastInsertId := LJSON.GetValue<Int64>('last_insert_id', 0);
    
    if LJSON.TryGetValue<TJSONArray>('columns', LCols) then
    begin
      SetLength(Result.ColumnNames, LCols.Count);
      for I := 0 to LCols.Count - 1 do
        Result.ColumnNames[I] := LCols.Items[I].Value;
    end;
    
    if LJSON.TryGetValue<TJSONArray>('rows', LRows) then
    begin
      for LRow in LRows do
      begin
        LResultRow := Result.Add;
        LResultRow.FromJSON(LRow as TJSONObject);
      end;
    end;
  finally
    LJSON.Free;
  end;
end;

function TPostgreSQLConnection.Execute(const ASQL: string;
  const AParams: TQueryParams): TResultSet;
var
  LBody: TJSONObject;
  LStream: TStringStream;
  LResp: IHTTPResponse;
begin
  if not FConnected then
    Connect;
    
  FLock.Enter;
  try
    LBody := BuildRequestBody(ASQL, AParams);
    try
      LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
      try
        LResp := FHttpClient.Post(FRestEndpoint + '/query', LStream);
        
        if LResp.StatusCode = 200 then
          Result := ParseResponse(LResp.ContentAsString)
        else
          raise EOperationException.CreateFmt('SQL 执行失败: %d %s', 
            [LResp.StatusCode, LResp.ContentAsString]);
      finally
        LStream.Free;
      end;
    finally
      LBody.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TPostgreSQLConnection.ExecuteScalar(const ASQL: string;
  const AParams: TQueryParams): Variant;
var
  LResult: TResultSet;
begin
  Result := Null;
  LResult := Execute(ASQL, AParams);
  try
    if not LResult.IsEmpty then
      Result := LResult[0].Fields[LResult.ColumnNames[0]];
  finally
    LResult.Free;
  end;
end;

procedure TPostgreSQLConnection.BeginTransaction(AIsolation: TIsolationLevel);
var
  LSQL: string;
begin
  case AIsolation of
    ilReadUncommitted: LSQL := 'BEGIN ISOLATION LEVEL READ UNCOMMITTED';
    ilReadCommitted:   LSQL := 'BEGIN ISOLATION LEVEL READ COMMITTED';
    ilRepeatableRead:  LSQL := 'BEGIN ISOLATION LEVEL REPEATABLE READ';
    ilSerializable:    LSQL := 'BEGIN ISOLATION LEVEL SERIALIZABLE';
  else
    LSQL := 'BEGIN';
  end;
  
  Execute(LSQL, []);
  FInTransaction := True;
end;

procedure TPostgreSQLConnection.Commit;
begin
  if FInTransaction then
  begin
    Execute('COMMIT', []);
    FInTransaction := False;
  end;
end;

procedure TPostgreSQLConnection.Rollback;
begin
  if FInTransaction then
  begin
    Execute('ROLLBACK', []);
    FInTransaction := False;
  end;
end;

function TPostgreSQLConnection.InTransaction: Boolean;
begin
  Result := FInTransaction;
end;

{==========================================================================}
{  TConnectionPool                                                         }
{==========================================================================}

constructor TConnectionPool.Create(const AConfig: TPostgreSQLConfig;
  const ARestEndpoint: string; AMinSize, AMaxSize: Integer);
var
  I: Integer;
begin
  inherited Create;
  FConfig := AConfig;
  FRestEndpoint := ARestEndpoint;
  FMinSize := AMinSize;
  FMaxSize := AMaxSize;
  FConnections := TList<IDbConnection>.Create;
  FAvailable := TList<IDbConnection>.Create;
  FLock := TCriticalSection.Create;
  
  for I := 1 to FMinSize do
    CreateConnection;
end;

destructor TConnectionPool.Destroy;
var
  LConn: IDbConnection;
begin
  FLock.Enter;
  try
    for LConn in FConnections do
      LConn.Disconnect;
    FConnections.Clear;
    FAvailable.Clear;
  finally
    FLock.Leave;
  end;
  
  FConnections.Free;
  FAvailable.Free;
  FLock.Free;
  inherited;
end;

procedure TConnectionPool.CreateConnection;
var
  LConn: IDbConnection;
begin
  LConn := TPostgreSQLConnection.Create(FConfig, FRestEndpoint);
  LConn.Connect;
  
  FLock.Enter;
  try
    FConnections.Add(LConn);
    FAvailable.Add(LConn);
  finally
    FLock.Leave;
  end;
end;

function TConnectionPool.Acquire: IDbConnection;
begin
  FLock.Enter;
  try
    if FAvailable.Count > 0 then
    begin
      Result := FAvailable[0];
      FAvailable.Delete(0);
    end
    else if FConnections.Count < FMaxSize then
    begin
      FLock.Leave;
      try
        CreateConnection;
      finally
        FLock.Enter;
      end;
      
      if FAvailable.Count > 0 then
      begin
        Result := FAvailable[0];
        FAvailable.Delete(0);
      end
      else
        raise EOperationException.Create('无法获取连接');
    end
    else
      raise EOperationException.Create('连接池已�?);
  finally
    FLock.Leave;
  end;
end;

procedure TConnectionPool.Release(AConnection: IDbConnection);
begin
  FLock.Enter;
  try
    if not FAvailable.Contains(AConnection) then
      FAvailable.Add(AConnection);
  finally
    FLock.Leave;
  end;
end;

function TConnectionPool.GetActiveCount: Integer;
begin
  FLock.Enter;
  try
    Result := FConnections.Count - FAvailable.Count;
  finally
    FLock.Leave;
  end;
end;

function TConnectionPool.GetAvailableCount: Integer;
begin
  FLock.Enter;
  try
    Result := FAvailable.Count;
  finally
    FLock.Leave;
  end;
end;

{==========================================================================}
{  TWorkflowRepository                                                     }
{==========================================================================}

constructor TWorkflowRepository.Create(APool: TConnectionPool; const ATenantId: string);
begin
  inherited Create;
  FPool := APool;
  FTableName := 'workflows';
  FTenantId := ATenantId;
end;

function TWorkflowRepository.FindById(const AId: string): TWorkflowEntity;
var
  LConn: IDbConnection;
  LResult: TResultSet;
  LParams: TQueryParams;
begin
  Result := nil;
  LConn := FPool.Acquire;
  try
    SetLength(LParams, 1);
    LParams[0] := TQueryParam.Create('$1', AId);
    
    LResult := LConn.Execute(
      'SELECT * FROM ' + FTableName + ' WHERE id = $1', LParams);
    try
      if not LResult.IsEmpty then
      begin
        Result := TWorkflowEntity.Create;
        Result.Id := LResult[0].GetString('id');
        Result.TenantId := LResult[0].GetString('tenant_id');
        Result.Name := LResult[0].GetString('name');
        Result.Description := LResult[0].GetString('description');
        Result.Status := LResult[0].GetString('status');
        Result.Version := LResult[0].GetInteger('version');
        Result.CreatedAt := LResult[0].GetDateTime('created_at');
        Result.UpdatedAt := LResult[0].GetDateTime('updated_at');
      end;
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

function TWorkflowRepository.FindAll(APagination: TPagination): TObjectList<TWorkflowEntity>;
var
  LConn: IDbConnection;
  LResult: TResultSet;
  LParams: TQueryParams;
  LEntity: TWorkflowEntity;
  I: Integer;
begin
  Result := TObjectList<TWorkflowEntity>.Create(True);
  LConn := FPool.Acquire;
  try
    SetLength(LParams, 2);
    LParams[0] := TQueryParam.Create('$1', APagination.PageSize);
    LParams[1] := TQueryParam.Create('$2', APagination.Offset);
    
    LResult := LConn.Execute(
      'SELECT * FROM ' + FTableName + ' ORDER BY created_at DESC LIMIT $1 OFFSET $2', LParams);
    try
      for I := 0 to LResult.Count - 1 do
      begin
        LEntity := TWorkflowEntity.Create;
        LEntity.Id := LResult[I].GetString('id');
        LEntity.TenantId := LResult[I].GetString('tenant_id');
        LEntity.Name := LResult[I].GetString('name');
        LEntity.Description := LResult[I].GetString('description');
        LEntity.Status := LResult[I].GetString('status');
        LEntity.Version := LResult[I].GetInteger('version');
        LEntity.CreatedAt := LResult[I].GetDateTime('created_at');
        LEntity.UpdatedAt := LResult[I].GetDateTime('updated_at');
        Result.Add(LEntity);
      end;
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

function TWorkflowRepository.FindByConditions(const AConditions: TFilterConditions;
  APagination: TPagination): TObjectList<TWorkflowEntity>;
var
  LConn: IDbConnection;
  LBuilder: TQueryBuilder;
  LParams: TQueryParams;
  LSQL: string;
  LResult: TResultSet;
  LEntity: TWorkflowEntity;
  I: Integer;
begin
  Result := TObjectList<TWorkflowEntity>.Create(True);
  
  LBuilder := TQueryBuilder.Create(FTableName);
  try
    for I := 0 to High(AConditions) do
    begin
      if I = 0 then
        LBuilder.Where(AConditions[I])
      else
        LBuilder.AndWhere(AConditions[I]);
    end;
    LBuilder.Page(APagination.Page, APagination.PageSize);
    LBuilder.OrderBy('created_at', sdDesc);
    
    LSQL := LBuilder.BuildSelect(LParams);
  finally
    LBuilder.Free;
  end;
  
  LConn := FPool.Acquire;
  try
    LResult := LConn.Execute(LSQL, LParams);
    try
      for I := 0 to LResult.Count - 1 do
      begin
        LEntity := TWorkflowEntity.Create;
        LEntity.Id := LResult[I].GetString('id');
        LEntity.Name := LResult[I].GetString('name');
        LEntity.Description := LResult[I].GetString('description');
        LEntity.Status := LResult[I].GetString('status');
        Result.Add(LEntity);
      end;
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

function TWorkflowRepository.FindByName(const AName: string): TWorkflowEntity;
var
  LConditions: TFilterConditions;
  LList: TObjectList<TWorkflowEntity>;
begin
  Result := nil;
  SetLength(LConditions, 1);
  LConditions[0] := TFilterCondition.Create('name', foEqual, AName);
  
  LList := FindByConditions(LConditions, TPagination.Create(1, 1));
  try
    if LList.Count > 0 then
    begin
      Result := LList.Extract(LList[0]);
    end;
  finally
    LList.Free;
  end;
end;

function TWorkflowRepository.FindByStatus(const AStatus: string;
  APagination: TPagination): TObjectList<TWorkflowEntity>;
var
  LConditions: TFilterConditions;
begin
  SetLength(LConditions, 1);
  LConditions[0] := TFilterCondition.Create('status', foEqual, AStatus);
  Result := FindByConditions(LConditions, APagination);
end;

function TWorkflowRepository.FindByTags(const ATags: TArray<string>;
  APagination: TPagination): TObjectList<TWorkflowEntity>;
var
  LConditions: TFilterConditions;
begin
  SetLength(LConditions, 1);
  LConditions[0] := TFilterCondition.Create('tags', foIn, String.Join(',', ATags));
  Result := FindByConditions(LConditions, APagination);
end;

function TWorkflowRepository.Count: Int64;
var
  LConn: IDbConnection;
begin
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar('SELECT COUNT(*) FROM ' + FTableName, []);
  finally
    FPool.Release(LConn);
  end;
end;

function TWorkflowRepository.CountByConditions(const AConditions: TFilterConditions): Int64;
var
  LConn: IDbConnection;
  LBuilder: TQueryBuilder;
  LParams: TQueryParams;
  LSQL: string;
  I: Integer;
begin
  LBuilder := TQueryBuilder.Create(FTableName);
  try
    for I := 0 to High(AConditions) do
    begin
      if I = 0 then
        LBuilder.Where(AConditions[I])
      else
        LBuilder.AndWhere(AConditions[I]);
    end;
    LSQL := LBuilder.BuildCount(LParams);
  finally
    LBuilder.Free;
  end;
  
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar(LSQL, LParams);
  finally
    FPool.Release(LConn);
  end;
end;

procedure TWorkflowRepository.Insert(AEntity: TWorkflowEntity);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
  LSQL: string;
begin
  LSQL := 'INSERT INTO ' + FTableName + 
    ' (id, tenant_id, name, description, definition, status, tags, version) ' +
    'VALUES ($1, $2, $3, $4, $5, $6, $7, $8)';
    
  SetLength(LParams, 8);
  LParams[0] := TQueryParam.Create('$1', AEntity.Id);
  LParams[1] := TQueryParam.Create('$2', AEntity.TenantId);
  LParams[2] := TQueryParam.Create('$3', AEntity.Name);
  LParams[3] := TQueryParam.Create('$4', AEntity.Description);
  LParams[4] := TQueryParam.Create('$5', AEntity.Definition.ToJSON);
  LParams[5] := TQueryParam.Create('$6', AEntity.Status);
  LParams[6] := TQueryParam.Create('$7', String.Join(',', AEntity.Tags));
  LParams[7] := TQueryParam.Create('$8', AEntity.Version);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute(LSQL, LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TWorkflowRepository.Update(AEntity: TWorkflowEntity);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
  LSQL: string;
begin
  AEntity.UpdatedAt := Now;
  Inc(AEntity.FVersion);
  
  LSQL := 'UPDATE ' + FTableName + ' SET ' +
    'name = $1, description = $2, definition = $3, status = $4, ' +
    'tags = $5, version = $6, updated_at = NOW() WHERE id = $7';
    
  SetLength(LParams, 7);
  LParams[0] := TQueryParam.Create('$1', AEntity.Name);
  LParams[1] := TQueryParam.Create('$2', AEntity.Description);
  LParams[2] := TQueryParam.Create('$3', AEntity.Definition.ToJSON);
  LParams[3] := TQueryParam.Create('$4', AEntity.Status);
  LParams[4] := TQueryParam.Create('$5', String.Join(',', AEntity.Tags));
  LParams[5] := TQueryParam.Create('$6', AEntity.Version);
  LParams[6] := TQueryParam.Create('$7', AEntity.Id);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute(LSQL, LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TWorkflowRepository.Delete(const AId: string);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
begin
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute('DELETE FROM ' + FTableName + ' WHERE id = $1', LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TWorkflowRepository.DeleteByConditions(const AConditions: TFilterConditions);
var
  LConn: IDbConnection;
  LBuilder: TQueryBuilder;
  LParams: TQueryParams;
  LSQL: string;
  I: Integer;
begin
  LBuilder := TQueryBuilder.Create(FTableName);
  try
    for I := 0 to High(AConditions) do
    begin
      if I = 0 then
        LBuilder.Where(AConditions[I])
      else
        LBuilder.AndWhere(AConditions[I]);
    end;
    LSQL := LBuilder.BuildDelete(LParams);
  finally
    LBuilder.Free;
  end;
  
  LConn := FPool.Acquire;
  try
    LConn.Execute(LSQL, LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

function TWorkflowRepository.Exists(const AId: string): Boolean;
var
  LConn: IDbConnection;
  LParams: TQueryParams;
begin
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar(
      'SELECT COUNT(*) FROM ' + FTableName + ' WHERE id = $1', LParams) > 0;
  finally
    FPool.Release(LConn);
  end;
end;

{==========================================================================}
{  TSessionRepository                                                      }
{==========================================================================}

constructor TSessionRepository.Create(APool: TConnectionPool; const ATenantId: string);
begin
  inherited Create;
  FPool := APool;
  FTableName := 'sessions';
  FTenantId := ATenantId;
end;

function TSessionRepository.FindById(const AId: string): TSessionEntity;
var
  LConn: IDbConnection;
  LResult: TResultSet;
  LParams: TQueryParams;
begin
  Result := nil;
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    LResult := LConn.Execute('SELECT * FROM ' + FTableName + ' WHERE id = $1', LParams);
    try
      if not LResult.IsEmpty then
      begin
        Result := TSessionEntity.Create;
        Result.Id := LResult[0].GetString('id');
        Result.TenantId := LResult[0].GetString('tenant_id');
        Result.WorkflowId := LResult[0].GetString('workflow_id');
        Result.UserId := LResult[0].GetString('user_id');
        Result.Status := LResult[0].GetString('status');
        Result.CurrentStep := LResult[0].GetString('current_step');
        Result.StartedAt := LResult[0].GetDateTime('started_at');
        Result.CompletedAt := LResult[0].GetDateTime('completed_at');
      end;
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

function TSessionRepository.FindAll(APagination: TPagination): TObjectList<TSessionEntity>;
begin
  Result := FindByConditions([], APagination);
end;

function TSessionRepository.FindByConditions(const AConditions: TFilterConditions;
  APagination: TPagination): TObjectList<TSessionEntity>;
var
  LConn: IDbConnection;
  LBuilder: TQueryBuilder;
  LParams: TQueryParams;
  LSQL: string;
  LResult: TResultSet;
  LEntity: TSessionEntity;
  I: Integer;
begin
  Result := TObjectList<TSessionEntity>.Create(True);
  
  LBuilder := TQueryBuilder.Create(FTableName);
  try
    for I := 0 to High(AConditions) do
    begin
      if I = 0 then
        LBuilder.Where(AConditions[I])
      else
        LBuilder.AndWhere(AConditions[I]);
    end;
    LBuilder.Page(APagination.Page, APagination.PageSize);
    LBuilder.OrderBy('created_at', sdDesc);
    LSQL := LBuilder.BuildSelect(LParams);
  finally
    LBuilder.Free;
  end;
  
  LConn := FPool.Acquire;
  try
    LResult := LConn.Execute(LSQL, LParams);
    try
      for I := 0 to LResult.Count - 1 do
      begin
        LEntity := TSessionEntity.Create;
        LEntity.Id := LResult[I].GetString('id');
        LEntity.WorkflowId := LResult[I].GetString('workflow_id');
        LEntity.UserId := LResult[I].GetString('user_id');
        LEntity.Status := LResult[I].GetString('status');
        LEntity.CurrentStep := LResult[I].GetString('current_step');
        Result.Add(LEntity);
      end;
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

function TSessionRepository.FindByWorkflowId(const AWorkflowId: string;
  APagination: TPagination): TObjectList<TSessionEntity>;
var
  LConditions: TFilterConditions;
begin
  SetLength(LConditions, 1);
  LConditions[0] := TFilterCondition.Create('workflow_id', foEqual, AWorkflowId);
  Result := FindByConditions(LConditions, APagination);
end;

function TSessionRepository.FindByUserId(const AUserId: string;
  APagination: TPagination): TObjectList<TSessionEntity>;
var
  LConditions: TFilterConditions;
begin
  SetLength(LConditions, 1);
  LConditions[0] := TFilterCondition.Create('user_id', foEqual, AUserId);
  Result := FindByConditions(LConditions, APagination);
end;

function TSessionRepository.FindByStatus(const AStatus: string;
  APagination: TPagination): TObjectList<TSessionEntity>;
var
  LConditions: TFilterConditions;
begin
  SetLength(LConditions, 1);
  LConditions[0] := TFilterCondition.Create('status', foEqual, AStatus);
  Result := FindByConditions(LConditions, APagination);
end;

function TSessionRepository.FindActive: TObjectList<TSessionEntity>;
begin
  Result := FindByStatus('running', TPagination.Create(1, 1000));
end;

function TSessionRepository.Count: Int64;
var
  LConn: IDbConnection;
begin
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar('SELECT COUNT(*) FROM ' + FTableName, []);
  finally
    FPool.Release(LConn);
  end;
end;

function TSessionRepository.CountByConditions(const AConditions: TFilterConditions): Int64;
begin
  Result := 0;
end;

function TSessionRepository.CountActive: Int64;
var
  LConn: IDbConnection;
  LParams: TQueryParams;
begin
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', 'running');
  
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar(
      'SELECT COUNT(*) FROM ' + FTableName + ' WHERE status = $1', LParams);
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSessionRepository.Insert(AEntity: TSessionEntity);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
  LSQL: string;
begin
  LSQL := 'INSERT INTO ' + FTableName + 
    ' (id, tenant_id, workflow_id, user_id, status, current_step, context, started_at) ' +
    'VALUES ($1, $2, $3, $4, $5, $6, $7, $8)';
    
  SetLength(LParams, 8);
  LParams[0] := TQueryParam.Create('$1', AEntity.Id);
  LParams[1] := TQueryParam.Create('$2', AEntity.TenantId);
  LParams[2] := TQueryParam.Create('$3', AEntity.WorkflowId);
  LParams[3] := TQueryParam.Create('$4', AEntity.UserId);
  LParams[4] := TQueryParam.Create('$5', AEntity.Status);
  LParams[5] := TQueryParam.Create('$6', AEntity.CurrentStep);
  LParams[6] := TQueryParam.Create('$7', AEntity.Context.ToJSON);
  LParams[7] := TQueryParam.Create('$8', DateToISO8601(AEntity.StartedAt));
  
  LConn := FPool.Acquire;
  try
    LConn.Execute(LSQL, LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSessionRepository.Update(AEntity: TSessionEntity);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
  LSQL: string;
begin
  AEntity.UpdatedAt := Now;
  
  LSQL := 'UPDATE ' + FTableName + ' SET ' +
    'status = $1, current_step = $2, context = $3, completed_at = $4, ' +
    'updated_at = NOW() WHERE id = $5';
    
  SetLength(LParams, 5);
  LParams[0] := TQueryParam.Create('$1', AEntity.Status);
  LParams[1] := TQueryParam.Create('$2', AEntity.CurrentStep);
  LParams[2] := TQueryParam.Create('$3', AEntity.Context.ToJSON);
  if AEntity.CompletedAt > 0 then
    LParams[3] := TQueryParam.Create('$4', DateToISO8601(AEntity.CompletedAt))
  else
    LParams[3] := TQueryParam.Create('$4', Null);
  LParams[4] := TQueryParam.Create('$5', AEntity.Id);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute(LSQL, LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSessionRepository.Delete(const AId: string);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
begin
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute('DELETE FROM ' + FTableName + ' WHERE id = $1', LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSessionRepository.DeleteByConditions(const AConditions: TFilterConditions);
begin
  // 实现�?WorkflowRepository
end;

function TSessionRepository.Exists(const AId: string): Boolean;
var
  LConn: IDbConnection;
  LParams: TQueryParams;
begin
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar(
      'SELECT COUNT(*) FROM ' + FTableName + ' WHERE id = $1', LParams) > 0;
  finally
    FPool.Release(LConn);
  end;
end;

{==========================================================================}
{  TSkillRepository                                                        }
{==========================================================================}

constructor TSkillRepository.Create(APool: TConnectionPool; const ATenantId: string);
begin
  inherited Create;
  FPool := APool;
  FTableName := 'skills';
  FTenantId := ATenantId;
end;

function TSkillRepository.FindById(const AId: string): TSkillEntity;
var
  LConn: IDbConnection;
  LResult: TResultSet;
  LParams: TQueryParams;
begin
  Result := nil;
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    LResult := LConn.Execute('SELECT * FROM ' + FTableName + ' WHERE id = $1', LParams);
    try
      if not LResult.IsEmpty then
      begin
        Result := TSkillEntity.Create;
        Result.Id := LResult[0].GetString('id');
        Result.Name := LResult[0].GetString('name');
        Result.Description := LResult[0].GetString('description');
        Result.Runtime := LResult[0].GetString('runtime');
        Result.Code := LResult[0].GetString('code');
        Result.Category := LResult[0].GetString('category');
        Result.Enabled := LResult[0].GetBoolean('enabled');
      end;
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

function TSkillRepository.FindAll(APagination: TPagination): TObjectList<TSkillEntity>;
begin
  Result := FindByConditions([], APagination);
end;

function TSkillRepository.FindByConditions(const AConditions: TFilterConditions;
  APagination: TPagination): TObjectList<TSkillEntity>;
begin
  Result := TObjectList<TSkillEntity>.Create(True);
end;

function TSkillRepository.FindByName(const AName: string): TSkillEntity;
begin
  Result := nil;
end;

function TSkillRepository.FindByCategory(const ACategory: string;
  APagination: TPagination): TObjectList<TSkillEntity>;
begin
  Result := TObjectList<TSkillEntity>.Create(True);
end;

function TSkillRepository.FindEnabled: TObjectList<TSkillEntity>;
begin
  Result := TObjectList<TSkillEntity>.Create(True);
end;

function TSkillRepository.Count: Int64;
var
  LConn: IDbConnection;
begin
  LConn := FPool.Acquire;
  try
    Result := LConn.ExecuteScalar('SELECT COUNT(*) FROM ' + FTableName, []);
  finally
    FPool.Release(LConn);
  end;
end;

function TSkillRepository.CountByConditions(const AConditions: TFilterConditions): Int64;
begin
  Result := 0;
end;

procedure TSkillRepository.Insert(AEntity: TSkillEntity);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
  LSQL: string;
begin
  LSQL := 'INSERT INTO ' + FTableName + 
    ' (id, tenant_id, name, description, runtime, code, input_schema, output_schema, category, enabled) ' +
    'VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)';
    
  SetLength(LParams, 10);
  LParams[0] := TQueryParam.Create('$1', AEntity.Id);
  LParams[1] := TQueryParam.Create('$2', AEntity.TenantId);
  LParams[2] := TQueryParam.Create('$3', AEntity.Name);
  LParams[3] := TQueryParam.Create('$4', AEntity.Description);
  LParams[4] := TQueryParam.Create('$5', AEntity.Runtime);
  LParams[5] := TQueryParam.Create('$6', AEntity.Code);
  LParams[6] := TQueryParam.Create('$7', AEntity.InputSchema.ToJSON);
  LParams[7] := TQueryParam.Create('$8', AEntity.OutputSchema.ToJSON);
  LParams[8] := TQueryParam.Create('$9', AEntity.Category);
  LParams[9] := TQueryParam.Create('$10', AEntity.Enabled);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute(LSQL, LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSkillRepository.Update(AEntity: TSkillEntity);
begin
end;

procedure TSkillRepository.Delete(const AId: string);
var
  LConn: IDbConnection;
  LParams: TQueryParams;
begin
  SetLength(LParams, 1);
  LParams[0] := TQueryParam.Create('$1', AId);
  
  LConn := FPool.Acquire;
  try
    LConn.Execute('DELETE FROM ' + FTableName + ' WHERE id = $1', LParams).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSkillRepository.DeleteByConditions(const AConditions: TFilterConditions);
begin
end;

function TSkillRepository.Exists(const AId: string): Boolean;
begin
  Result := False;
end;

{==========================================================================}
{  TPostgreSQLStorageBackend                                               }
{==========================================================================}

constructor TPostgreSQLStorageBackend.Create(const AConfig: TPostgreSQLConfig;
  const ARestEndpoint: string);
begin
  inherited Create;
  FConfig := AConfig;
  FRestEndpoint := ARestEndpoint;
  FPool := TConnectionPool.Create(AConfig, ARestEndpoint);
  FWorkflowRepo := TWorkflowRepository.Create(FPool);
  FSessionRepo := TSessionRepository.Create(FPool);
  FSkillRepo := TSkillRepository.Create(FPool);
  FInitialized := False;
end;

destructor TPostgreSQLStorageBackend.Destroy;
begin
  FSkillRepo.Free;
  FSessionRepo.Free;
  FWorkflowRepo.Free;
  FPool.Free;
  inherited;
end;

procedure TPostgreSQLStorageBackend.Initialize;
begin
  if FInitialized then Exit;
  CreateSchema;
  FInitialized := True;
end;

procedure TPostgreSQLStorageBackend.CreateSchema;
var
  LConn: IDbConnection;
begin
  LConn := FPool.Acquire;
  try
    LConn.Execute(SQL_CREATE_MIGRATIONS, []).Free;
    LConn.Execute(SQL_CREATE_WORKFLOWS, []).Free;
    LConn.Execute(SQL_CREATE_SESSIONS, []).Free;
    LConn.Execute(SQL_CREATE_SKILLS, []).Free;
    LConn.Execute(SQL_CREATE_INDEXES, []).Free;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TPostgreSQLStorageBackend.DropSchema;
var
  LConn: IDbConnection;
begin
  LConn := FPool.Acquire;
  try
    LConn.Execute('DROP TABLE IF EXISTS sessions CASCADE', []).Free;
    LConn.Execute('DROP TABLE IF EXISTS workflows CASCADE', []).Free;
    LConn.Execute('DROP TABLE IF EXISTS skills CASCADE', []).Free;
    LConn.Execute('DROP TABLE IF EXISTS schema_migrations CASCADE', []).Free;
  finally
    FPool.Release(LConn);
  end;
  
  FInitialized := False;
end;

procedure TPostgreSQLStorageBackend.MigrateSchema(ATargetVersion: Integer);
var
  LMigrator: TSchemaMigrator;
begin
  LMigrator := TSchemaMigrator.Create(FPool, FConfig.Schema);
  try
    LMigrator.Migrate(ATargetVersion);
  finally
    LMigrator.Free;
  end;
end;

function TPostgreSQLStorageBackend.GetStatistics: TStorageStatistics;
begin
  Result.TotalWorkflows := FWorkflowRepo.Count;
  Result.TotalSessions := FSessionRepo.Count;
  Result.TotalSkills := FSkillRepo.Count;
  Result.ActiveSessions := FSessionRepo.CountActive;
  Result.StorageSizeBytes := 0;
  Result.LastUpdated := Now;
end;

{==========================================================================}
{  TSchemaMigrator                                                         }
{==========================================================================}

constructor TSchemaMigrator.Create(APool: TConnectionPool; const ASchema: string);
begin
  inherited Create;
  FPool := APool;
  FSchema := ASchema;
  FMigrations := TList<TSchemaMigration>.Create;
end;

destructor TSchemaMigrator.Destroy;
begin
  FMigrations.Free;
  inherited;
end;

function TSchemaMigrator.GetCurrentVersion: Integer;
var
  LConn: IDbConnection;
begin
  LConn := FPool.Acquire;
  try
    try
      Result := LConn.ExecuteScalar(
        'SELECT COALESCE(MAX(version), 0) FROM schema_migrations', []);
    except
      Result := 0;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSchemaMigrator.SetCurrentVersion(AVersion: Integer);
begin
  // 实现版本记录
end;

procedure TSchemaMigrator.AddMigration(AVersion: Integer; const AName, AUpSQL, ADownSQL: string);
var
  LMigration: TSchemaMigration;
begin
  LMigration.Version := AVersion;
  LMigration.Name := AName;
  LMigration.UpSQL := AUpSQL;
  LMigration.DownSQL := ADownSQL;
  FMigrations.Add(LMigration);
end;

procedure TSchemaMigrator.ExecuteMigration(const AMigration: TSchemaMigration; AUp: Boolean);
var
  LConn: IDbConnection;
  LSQL: string;
  LParams: TQueryParams;
begin
  if AUp then
    LSQL := AMigration.UpSQL
  else
    LSQL := AMigration.DownSQL;
    
  LConn := FPool.Acquire;
  try
    LConn.BeginTransaction;
    try
      LConn.Execute(LSQL, []).Free;
      
      if AUp then
      begin
        SetLength(LParams, 2);
        LParams[0] := TQueryParam.Create('$1', AMigration.Version);
        LParams[1] := TQueryParam.Create('$2', AMigration.Name);
        LConn.Execute(
          'INSERT INTO schema_migrations (version, name) VALUES ($1, $2)', LParams).Free;
      end
      else
      begin
        SetLength(LParams, 1);
        LParams[0] := TQueryParam.Create('$1', AMigration.Version);
        LConn.Execute(
          'DELETE FROM schema_migrations WHERE version = $1', LParams).Free;
      end;
      
      LConn.Commit;
    except
      LConn.Rollback;
      raise;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

procedure TSchemaMigrator.Migrate(ATargetVersion: Integer);
var
  LCurrentVersion: Integer;
  I: Integer;
begin
  LCurrentVersion := GetCurrentVersion;
  
  if ATargetVersion < 0 then
    ATargetVersion := FMigrations.Count;
    
  for I := 0 to FMigrations.Count - 1 do
  begin
    if (FMigrations[I].Version > LCurrentVersion) and 
       (FMigrations[I].Version <= ATargetVersion) then
      ExecuteMigration(FMigrations[I], True);
  end;
end;

procedure TSchemaMigrator.Rollback(ATargetVersion: Integer);
var
  LCurrentVersion: Integer;
  I: Integer;
begin
  LCurrentVersion := GetCurrentVersion;
  
  for I := FMigrations.Count - 1 downto 0 do
  begin
    if (FMigrations[I].Version <= LCurrentVersion) and 
       (FMigrations[I].Version > ATargetVersion) then
      ExecuteMigration(FMigrations[I], False);
  end;
end;

function TSchemaMigrator.GetAppliedMigrations: TArray<Integer>;
var
  LConn: IDbConnection;
  LResult: TResultSet;
  I: Integer;
begin
  LConn := FPool.Acquire;
  try
    LResult := LConn.Execute('SELECT version FROM schema_migrations ORDER BY version', []);
    try
      SetLength(Result, LResult.Count);
      for I := 0 to LResult.Count - 1 do
        Result[I] := LResult[I].GetInteger('version');
    finally
      LResult.Free;
    end;
  finally
    FPool.Release(LConn);
  end;
end;

end.
