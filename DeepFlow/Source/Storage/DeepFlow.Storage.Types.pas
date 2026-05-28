unit UniFlow.Storage.Types;

{*******************************************************}
{                                                       }
{       UniFlow 存储后端类型定义                        }
{                                                       }
{       版权所�?(C) 2024 UniFlow                       }
{                                                       }
{*******************************************************}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.SyncObjs;

type
  {==========================================================================}
  {  存储后端类型                                                            }
  {==========================================================================}
  TStorageBackendType = (
    sbtFile,        // 文件存储
    sbtPostgreSQL,  // PostgreSQL
    sbtMySQL,       // MySQL
    sbtSQLite,      // SQLite
    sbtMongoDB,     // MongoDB
    sbtRedis,       // Redis
    sbtMemory       // 内存
  );

  {==========================================================================}
  {  数据库连接配�?                                                         }
  {==========================================================================}
  TDatabaseConfig = class
  private
    FHost: string;
    FPort: Integer;
    FDatabase: string;
    FUsername: string;
    FPassword: string;
    FSchema: string;
    FSSL: Boolean;
    FSSLMode: string;
    FPoolSize: Integer;
    FMinPoolSize: Integer;
    FMaxPoolSize: Integer;
    FConnectionTimeout: Integer;
    FCommandTimeout: Integer;
    FCharset: string;
    FTimezone: string;
  public
    constructor Create;
    
    function GetConnectionString: string; virtual;
    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);
    
    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property Database: string read FDatabase write FDatabase;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property Schema: string read FSchema write FSchema;
    property SSL: Boolean read FSSL write FSSL;
    property SSLMode: string read FSSLMode write FSSLMode;
    property PoolSize: Integer read FPoolSize write FPoolSize;
    property MinPoolSize: Integer read FMinPoolSize write FMinPoolSize;
    property MaxPoolSize: Integer read FMaxPoolSize write FMaxPoolSize;
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property CommandTimeout: Integer read FCommandTimeout write FCommandTimeout;
    property Charset: string read FCharset write FCharset;
    property Timezone: string read FTimezone write FTimezone;
  end;

  {==========================================================================}
  {  PostgreSQL 配置                                                         }
  {==========================================================================}
  TPostgreSQLConfig = class(TDatabaseConfig)
  private
    FApplicationName: string;
    FSearchPath: string;
    FStatementCacheSize: Integer;
  public
    constructor Create;
    function GetConnectionString: string; override;
    
    property ApplicationName: string read FApplicationName write FApplicationName;
    property SearchPath: string read FSearchPath write FSearchPath;
    property StatementCacheSize: Integer read FStatementCacheSize write FStatementCacheSize;
  end;

  {==========================================================================}
  {  查询参数                                                                }
  {==========================================================================}
  TQueryParam = record
    Name: string;
    Value: Variant;
    DataType: string;
    
    class function Create(const AName: string; AValue: Variant; 
      const ADataType: string = ''): TQueryParam; static;
  end;

  TQueryParams = TArray<TQueryParam>;

  {==========================================================================}
  {  查询结果�?                                                             }
  {==========================================================================}
  TResultRow = class
  private
    FFields: TDictionary<string, Variant>;
    function GetField(const AName: string): Variant;
    procedure SetField(const AName: string; const AValue: Variant);
  public
    constructor Create;
    destructor Destroy; override;
    
    function GetString(const AName: string; const ADefault: string = ''): string;
    function GetInteger(const AName: string; ADefault: Integer = 0): Integer;
    function GetInt64(const AName: string; ADefault: Int64 = 0): Int64;
    function GetDouble(const AName: string; ADefault: Double = 0): Double;
    function GetBoolean(const AName: string; ADefault: Boolean = False): Boolean;
    function GetDateTime(const AName: string): TDateTime;
    function GetJSON(const AName: string): TJSONValue;
    function IsNull(const AName: string): Boolean;
    
    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);
    
    property Fields[const AName: string]: Variant read GetField write SetField; default;
  end;

  {==========================================================================}
  {  查询结果�?                                                             }
  {==========================================================================}
  TResultSet = class
  private
    FRows: TObjectList<TResultRow>;
    FColumnNames: TArray<string>;
    FAffectedRows: Int64;
    FLastInsertId: Int64;
    function GetRow(AIndex: Integer): TResultRow;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Add: TResultRow;
    procedure Clear;
    function IsEmpty: Boolean;
    function First: TResultRow;
    function Last: TResultRow;
    
    function ToJSONArray: TJSONArray;
    
    property Rows[AIndex: Integer]: TResultRow read GetRow; default;
    property Count: Integer read GetCount;
    property ColumnNames: TArray<string> read FColumnNames write FColumnNames;
    property AffectedRows: Int64 read FAffectedRows write FAffectedRows;
    property LastInsertId: Int64 read FLastInsertId write FLastInsertId;
  end;

  {==========================================================================}
  {  分页参数                                                                }
  {==========================================================================}
  TPagination = record
    Page: Integer;
    PageSize: Integer;
    TotalCount: Int64;
    TotalPages: Integer;
    
    class function Create(APage, APageSize: Integer): TPagination; static;
    function Offset: Integer;
    function HasPrev: Boolean;
    function HasNext: Boolean;
  end;

  {==========================================================================}
  {  排序方向                                                                }
  {==========================================================================}
  TSortDirection = (sdAsc, sdDesc);

  {==========================================================================}
  {  排序字段                                                                }
  {==========================================================================}
  TSortField = record
    FieldName: string;
    Direction: TSortDirection;
    
    class function Create(const AField: string; ADir: TSortDirection = sdAsc): TSortField; static;
    function ToSQL: string;
  end;

  TSortFields = TArray<TSortField>;

  {==========================================================================}
  {  筛选操作符                                                              }
  {==========================================================================}
  TFilterOperator = (
    foEqual,
    foNotEqual,
    foGreater,
    foGreaterOrEqual,
    foLess,
    foLessOrEqual,
    foLike,
    foNotLike,
    foIn,
    foNotIn,
    foIsNull,
    foIsNotNull,
    foBetween,
    foContains,
    foStartsWith,
    foEndsWith
  );

  {==========================================================================}
  {  筛选条�?                                                               }
  {==========================================================================}
  TFilterCondition = record
    FieldName: string;
    Operator: TFilterOperator;
    Value: Variant;
    Value2: Variant;  // 用于 Between
    
    class function Create(const AField: string; AOp: TFilterOperator; 
      AValue: Variant): TFilterCondition; static;
    class function Between(const AField: string; AMin, AMax: Variant): TFilterCondition; static;
    function ToSQL(var AParams: TQueryParams; AParamIndex: Integer): string;
  end;

  TFilterConditions = TArray<TFilterCondition>;

  {==========================================================================}
  {  查询构建�?                                                             }
  {==========================================================================}
  TQueryBuilder = class
  private
    FTableName: string;
    FSelectFields: TArray<string>;
    FConditions: TFilterConditions;
    FSortFields: TSortFields;
    FPagination: TPagination;
    FGroupBy: TArray<string>;
    FHaving: string;
    FJoins: TArray<string>;
    FDistinct: Boolean;
  public
    constructor Create(const ATableName: string);
    
    function Select(const AFields: array of string): TQueryBuilder;
    function Where(const ACondition: TFilterCondition): TQueryBuilder;
    function AndWhere(const ACondition: TFilterCondition): TQueryBuilder;
    function OrderBy(const AField: string; ADir: TSortDirection = sdAsc): TQueryBuilder;
    function Limit(ACount: Integer): TQueryBuilder;
    function Offset(AOffset: Integer): TQueryBuilder;
    function Page(APage, APageSize: Integer): TQueryBuilder;
    function GroupBy(const AFields: array of string): TQueryBuilder;
    function Having(const ACondition: string): TQueryBuilder;
    function Join(const AJoinClause: string): TQueryBuilder;
    function LeftJoin(const ATable, ACondition: string): TQueryBuilder;
    function Distinct: TQueryBuilder;
    
    function BuildSelect(var AParams: TQueryParams): string;
    function BuildCount(var AParams: TQueryParams): string;
    function BuildInsert(const AFields: TArray<string>; var AParams: TQueryParams): string;
    function BuildUpdate(const AFields: TArray<string>; var AParams: TQueryParams): string;
    function BuildDelete(var AParams: TQueryParams): string;
  end;

  {==========================================================================}
  {  事务隔离级别                                                            }
  {==========================================================================}
  TIsolationLevel = (
    ilReadUncommitted,
    ilReadCommitted,
    ilRepeatableRead,
    ilSerializable
  );

  {==========================================================================}
  {  存储实体基类                                                            }
  {==========================================================================}
  TStorageEntity = class
  private
    FId: string;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    FVersion: Integer;
    FTenantId: string;
  public
    constructor Create; virtual;
    
    function ToJSON: TJSONObject; virtual;
    procedure FromJSON(AJSON: TJSONObject); virtual;
    
    property Id: string read FId write FId;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    property Version: Integer read FVersion write FVersion;
    property TenantId: string read FTenantId write FTenantId;
  end;

  {==========================================================================}
  {  工作流存储实�?                                                         }
  {==========================================================================}
  TWorkflowEntity = class(TStorageEntity)
  private
    FName: string;
    FDescription: string;
    FDefinition: TJSONObject;
    FStatus: string;
    FTags: TArray<string>;
  public
    constructor Create; override;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject; override;
    procedure FromJSON(AJSON: TJSONObject); override;
    
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Definition: TJSONObject read FDefinition;
    property Status: string read FStatus write FStatus;
    property Tags: TArray<string> read FTags write FTags;
  end;

  {==========================================================================}
  {  会话存储实体                                                            }
  {==========================================================================}
  TSessionEntity = class(TStorageEntity)
  private
    FWorkflowId: string;
    FUserId: string;
    FStatus: string;
    FCurrentStep: string;
    FContext: TJSONObject;
    FStartedAt: TDateTime;
    FCompletedAt: TDateTime;
  public
    constructor Create; override;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject; override;
    procedure FromJSON(AJSON: TJSONObject); override;
    
    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property UserId: string read FUserId write FUserId;
    property Status: string read FStatus write FStatus;
    property CurrentStep: string read FCurrentStep write FCurrentStep;
    property Context: TJSONObject read FContext;
    property StartedAt: TDateTime read FStartedAt write FStartedAt;
    property CompletedAt: TDateTime read FCompletedAt write FCompletedAt;
  end;

  {==========================================================================}
  {  技能存储实�?                                                           }
  {==========================================================================}
  TSkillEntity = class(TStorageEntity)
  private
    FName: string;
    FDescription: string;
    FRuntime: string;
    FCode: string;
    FInputSchema: TJSONObject;
    FOutputSchema: TJSONObject;
    FCategory: string;
    FEnabled: Boolean;
  public
    constructor Create; override;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject; override;
    procedure FromJSON(AJSON: TJSONObject); override;
    
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Runtime: string read FRuntime write FRuntime;
    property Code: string read FCode write FCode;
    property InputSchema: TJSONObject read FInputSchema;
    property OutputSchema: TJSONObject read FOutputSchema;
    property Category: string read FCategory write FCategory;
    property Enabled: Boolean read FEnabled write FEnabled;
  end;

  {==========================================================================}
  {  存储统计                                                                }
  {==========================================================================}
  TStorageStatistics = record
    TotalWorkflows: Int64;
    TotalSessions: Int64;
    TotalSkills: Int64;
    ActiveSessions: Int64;
    StorageSizeBytes: Int64;
    LastUpdated: TDateTime;
  end;

implementation

uses
  System.Variants, System.StrUtils;

{==========================================================================}
{  TDatabaseConfig                                                         }
{==========================================================================}

constructor TDatabaseConfig.Create;
begin
  inherited Create;
  FHost := 'localhost';
  FPort := 5432;
  FDatabase := 'uniflow';
  FUsername := 'postgres';
  FPassword := '';
  FSchema := 'public';
  FSSL := False;
  FSSLMode := 'prefer';
  FPoolSize := 10;
  FMinPoolSize := 2;
  FMaxPoolSize := 20;
  FConnectionTimeout := 30;
  FCommandTimeout := 30;
  FCharset := 'UTF8';
  FTimezone := 'UTC';
end;

function TDatabaseConfig.GetConnectionString: string;
begin
  Result := Format('host=%s port=%d dbname=%s user=%s password=%s',
    [FHost, FPort, FDatabase, FUsername, FPassword]);
end;

function TDatabaseConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('host', FHost);
  Result.AddPair('port', TJSONNumber.Create(FPort));
  Result.AddPair('database', FDatabase);
  Result.AddPair('username', FUsername);
  Result.AddPair('schema', FSchema);
  Result.AddPair('ssl', TJSONBool.Create(FSSL));
  Result.AddPair('sslMode', FSSLMode);
  Result.AddPair('poolSize', TJSONNumber.Create(FPoolSize));
  Result.AddPair('connectionTimeout', TJSONNumber.Create(FConnectionTimeout));
  Result.AddPair('charset', FCharset);
end;

procedure TDatabaseConfig.FromJSON(AJSON: TJSONObject);
begin
  if not Assigned(AJSON) then Exit;
  
  FHost := AJSON.GetValue<string>('host', FHost);
  FPort := AJSON.GetValue<Integer>('port', FPort);
  FDatabase := AJSON.GetValue<string>('database', FDatabase);
  FUsername := AJSON.GetValue<string>('username', FUsername);
  FPassword := AJSON.GetValue<string>('password', FPassword);
  FSchema := AJSON.GetValue<string>('schema', FSchema);
  FSSL := AJSON.GetValue<Boolean>('ssl', FSSL);
  FSSLMode := AJSON.GetValue<string>('sslMode', FSSLMode);
  FPoolSize := AJSON.GetValue<Integer>('poolSize', FPoolSize);
  FConnectionTimeout := AJSON.GetValue<Integer>('connectionTimeout', FConnectionTimeout);
  FCharset := AJSON.GetValue<string>('charset', FCharset);
end;

{==========================================================================}
{  TPostgreSQLConfig                                                       }
{==========================================================================}

constructor TPostgreSQLConfig.Create;
begin
  inherited Create;
  FApplicationName := 'UniFlow';
  FSearchPath := 'public';
  FStatementCacheSize := 100;
end;

function TPostgreSQLConfig.GetConnectionString: string;
begin
  Result := Format(
    'host=%s port=%d dbname=%s user=%s password=%s application_name=%s',
    [Host, Port, Database, Username, Password, FApplicationName]);
  if SSL then
    Result := Result + ' sslmode=' + SSLMode;
end;

{==========================================================================}
{  TQueryParam                                                             }
{==========================================================================}

class function TQueryParam.Create(const AName: string; AValue: Variant;
  const ADataType: string): TQueryParam;
begin
  Result.Name := AName;
  Result.Value := AValue;
  Result.DataType := ADataType;
end;

{==========================================================================}
{  TResultRow                                                              }
{==========================================================================}

constructor TResultRow.Create;
begin
  inherited Create;
  FFields := TDictionary<string, Variant>.Create;
end;

destructor TResultRow.Destroy;
begin
  FFields.Free;
  inherited;
end;

function TResultRow.GetField(const AName: string): Variant;
begin
  if not FFields.TryGetValue(AName, Result) then
    Result := Null;
end;

procedure TResultRow.SetField(const AName: string; const AValue: Variant);
begin
  FFields.AddOrSetValue(AName, AValue);
end;

function TResultRow.GetString(const AName: string; const ADefault: string): string;
var
  V: Variant;
begin
  V := GetField(AName);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ADefault
  else
    Result := VarToStr(V);
end;

function TResultRow.GetInteger(const AName: string; ADefault: Integer): Integer;
var
  V: Variant;
begin
  V := GetField(AName);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ADefault
  else
    Result := V;
end;

function TResultRow.GetInt64(const AName: string; ADefault: Int64): Int64;
var
  V: Variant;
begin
  V := GetField(AName);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ADefault
  else
    Result := V;
end;

function TResultRow.GetDouble(const AName: string; ADefault: Double): Double;
var
  V: Variant;
begin
  V := GetField(AName);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ADefault
  else
    Result := V;
end;

function TResultRow.GetBoolean(const AName: string; ADefault: Boolean): Boolean;
var
  V: Variant;
begin
  V := GetField(AName);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ADefault
  else
    Result := V;
end;

function TResultRow.GetDateTime(const AName: string): TDateTime;
var
  V: Variant;
begin
  V := GetField(AName);
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := 0
  else
    Result := VarToDateTime(V);
end;

function TResultRow.GetJSON(const AName: string): TJSONValue;
var
  S: string;
begin
  S := GetString(AName, '');
  if S <> '' then
    Result := TJSONObject.ParseJSONValue(S)
  else
    Result := nil;
end;

function TResultRow.IsNull(const AName: string): Boolean;
var
  V: Variant;
begin
  V := GetField(AName);
  Result := VarIsNull(V) or VarIsEmpty(V);
end;

function TResultRow.ToJSON: TJSONObject;
var
  LPair: TPair<string, Variant>;
begin
  Result := TJSONObject.Create;
  for LPair in FFields do
  begin
    if VarIsNull(LPair.Value) then
      Result.AddPair(LPair.Key, TJSONNull.Create)
    else if VarType(LPair.Value) = varBoolean then
      Result.AddPair(LPair.Key, TJSONBool.Create(LPair.Value))
    else if VarIsNumeric(LPair.Value) then
      Result.AddPair(LPair.Key, TJSONNumber.Create(Double(LPair.Value)))
    else
      Result.AddPair(LPair.Key, VarToStr(LPair.Value));
  end;
end;

procedure TResultRow.FromJSON(AJSON: TJSONObject);
var
  LPair: TJSONPair;
begin
  FFields.Clear;
  if not Assigned(AJSON) then Exit;
  
  for LPair in AJSON do
  begin
    if LPair.JsonValue is TJSONNull then
      FFields.AddOrSetValue(LPair.JsonString.Value, Null)
    else if LPair.JsonValue is TJSONBool then
      FFields.AddOrSetValue(LPair.JsonString.Value, TJSONBool(LPair.JsonValue).AsBoolean)
    else if LPair.JsonValue is TJSONNumber then
      FFields.AddOrSetValue(LPair.JsonString.Value, TJSONNumber(LPair.JsonValue).AsDouble)
    else
      FFields.AddOrSetValue(LPair.JsonString.Value, LPair.JsonValue.Value);
  end;
end;

{==========================================================================}
{  TResultSet                                                              }
{==========================================================================}

constructor TResultSet.Create;
begin
  inherited Create;
  FRows := TObjectList<TResultRow>.Create(True);
  FAffectedRows := 0;
  FLastInsertId := 0;
end;

destructor TResultSet.Destroy;
begin
  FRows.Free;
  inherited;
end;

function TResultSet.GetRow(AIndex: Integer): TResultRow;
begin
  Result := FRows[AIndex];
end;

function TResultSet.GetCount: Integer;
begin
  Result := FRows.Count;
end;

function TResultSet.Add: TResultRow;
begin
  Result := TResultRow.Create;
  FRows.Add(Result);
end;

procedure TResultSet.Clear;
begin
  FRows.Clear;
end;

function TResultSet.IsEmpty: Boolean;
begin
  Result := FRows.Count = 0;
end;

function TResultSet.First: TResultRow;
begin
  if FRows.Count > 0 then
    Result := FRows[0]
  else
    Result := nil;
end;

function TResultSet.Last: TResultRow;
begin
  if FRows.Count > 0 then
    Result := FRows[FRows.Count - 1]
  else
    Result := nil;
end;

function TResultSet.ToJSONArray: TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to FRows.Count - 1 do
    Result.AddElement(FRows[I].ToJSON);
end;

{==========================================================================}
{  TPagination                                                             }
{==========================================================================}

class function TPagination.Create(APage, APageSize: Integer): TPagination;
begin
  Result.Page := APage;
  Result.PageSize := APageSize;
  Result.TotalCount := 0;
  Result.TotalPages := 0;
end;

function TPagination.Offset: Integer;
begin
  Result := (Page - 1) * PageSize;
end;

function TPagination.HasPrev: Boolean;
begin
  Result := Page > 1;
end;

function TPagination.HasNext: Boolean;
begin
  Result := Page < TotalPages;
end;

{==========================================================================}
{  TSortField                                                              }
{==========================================================================}

class function TSortField.Create(const AField: string; ADir: TSortDirection): TSortField;
begin
  Result.FieldName := AField;
  Result.Direction := ADir;
end;

function TSortField.ToSQL: string;
begin
  if Direction = sdAsc then
    Result := FieldName + ' ASC'
  else
    Result := FieldName + ' DESC';
end;

{==========================================================================}
{  TFilterCondition                                                        }
{==========================================================================}

class function TFilterCondition.Create(const AField: string; AOp: TFilterOperator;
  AValue: Variant): TFilterCondition;
begin
  Result.FieldName := AField;
  Result.Operator := AOp;
  Result.Value := AValue;
  Result.Value2 := Null;
end;

class function TFilterCondition.Between(const AField: string; AMin, AMax: Variant): TFilterCondition;
begin
  Result.FieldName := AField;
  Result.Operator := foBetween;
  Result.Value := AMin;
  Result.Value2 := AMax;
end;

function TFilterCondition.ToSQL(var AParams: TQueryParams; AParamIndex: Integer): string;
var
  LParamName: string;
begin
  LParamName := '$' + IntToStr(AParamIndex);
  
  case Operator of
    foEqual:
      Result := Format('%s = %s', [FieldName, LParamName]);
    foNotEqual:
      Result := Format('%s <> %s', [FieldName, LParamName]);
    foGreater:
      Result := Format('%s > %s', [FieldName, LParamName]);
    foGreaterOrEqual:
      Result := Format('%s >= %s', [FieldName, LParamName]);
    foLess:
      Result := Format('%s < %s', [FieldName, LParamName]);
    foLessOrEqual:
      Result := Format('%s <= %s', [FieldName, LParamName]);
    foLike:
      Result := Format('%s LIKE %s', [FieldName, LParamName]);
    foNotLike:
      Result := Format('%s NOT LIKE %s', [FieldName, LParamName]);
    foIn:
      Result := Format('%s = ANY(%s)', [FieldName, LParamName]);
    foNotIn:
      Result := Format('%s <> ALL(%s)', [FieldName, LParamName]);
    foIsNull:
      Result := Format('%s IS NULL', [FieldName]);
    foIsNotNull:
      Result := Format('%s IS NOT NULL', [FieldName]);
    foBetween:
      Result := Format('%s BETWEEN %s AND $%d', [FieldName, LParamName, AParamIndex + 1]);
    foContains:
      Result := Format('%s LIKE ''%%'' || %s || ''%%''', [FieldName, LParamName]);
    foStartsWith:
      Result := Format('%s LIKE %s || ''%%''', [FieldName, LParamName]);
    foEndsWith:
      Result := Format('%s LIKE ''%%'' || %s', [FieldName, LParamName]);
  end;
  
  if not (Operator in [foIsNull, foIsNotNull]) then
  begin
    SetLength(AParams, Length(AParams) + 1);
    AParams[High(AParams)] := TQueryParam.Create(LParamName, Value);
    
    if Operator = foBetween then
    begin
      SetLength(AParams, Length(AParams) + 1);
      AParams[High(AParams)] := TQueryParam.Create('$' + IntToStr(AParamIndex + 1), Value2);
    end;
  end;
end;

{==========================================================================}
{  TQueryBuilder                                                           }
{==========================================================================}

constructor TQueryBuilder.Create(const ATableName: string);
begin
  inherited Create;
  FTableName := ATableName;
  FDistinct := False;
  FPagination := TPagination.Create(1, 100);
end;

function TQueryBuilder.Select(const AFields: array of string): TQueryBuilder;
var
  I: Integer;
begin
  SetLength(FSelectFields, Length(AFields));
  for I := 0 to High(AFields) do
    FSelectFields[I] := AFields[I];
  Result := Self;
end;

function TQueryBuilder.Where(const ACondition: TFilterCondition): TQueryBuilder;
begin
  SetLength(FConditions, 1);
  FConditions[0] := ACondition;
  Result := Self;
end;

function TQueryBuilder.AndWhere(const ACondition: TFilterCondition): TQueryBuilder;
begin
  SetLength(FConditions, Length(FConditions) + 1);
  FConditions[High(FConditions)] := ACondition;
  Result := Self;
end;

function TQueryBuilder.OrderBy(const AField: string; ADir: TSortDirection): TQueryBuilder;
begin
  SetLength(FSortFields, Length(FSortFields) + 1);
  FSortFields[High(FSortFields)] := TSortField.Create(AField, ADir);
  Result := Self;
end;

function TQueryBuilder.Limit(ACount: Integer): TQueryBuilder;
begin
  FPagination.PageSize := ACount;
  Result := Self;
end;

function TQueryBuilder.Offset(AOffset: Integer): TQueryBuilder;
begin
  FPagination.Page := (AOffset div FPagination.PageSize) + 1;
  Result := Self;
end;

function TQueryBuilder.Page(APage, APageSize: Integer): TQueryBuilder;
begin
  FPagination.Page := APage;
  FPagination.PageSize := APageSize;
  Result := Self;
end;

function TQueryBuilder.GroupBy(const AFields: array of string): TQueryBuilder;
var
  I: Integer;
begin
  SetLength(FGroupBy, Length(AFields));
  for I := 0 to High(AFields) do
    FGroupBy[I] := AFields[I];
  Result := Self;
end;

function TQueryBuilder.Having(const ACondition: string): TQueryBuilder;
begin
  FHaving := ACondition;
  Result := Self;
end;

function TQueryBuilder.Join(const AJoinClause: string): TQueryBuilder;
begin
  SetLength(FJoins, Length(FJoins) + 1);
  FJoins[High(FJoins)] := AJoinClause;
  Result := Self;
end;

function TQueryBuilder.LeftJoin(const ATable, ACondition: string): TQueryBuilder;
begin
  Result := Join(Format('LEFT JOIN %s ON %s', [ATable, ACondition]));
end;

function TQueryBuilder.Distinct: TQueryBuilder;
begin
  FDistinct := True;
  Result := Self;
end;

function TQueryBuilder.BuildSelect(var AParams: TQueryParams): string;
var
  I, LParamIdx: Integer;
  LFields, LWhere, LOrder, LJoins: string;
begin
  if Length(FSelectFields) > 0 then
    LFields := String.Join(', ', FSelectFields)
  else
    LFields := '*';
    
  if FDistinct then
    Result := 'SELECT DISTINCT ' + LFields
  else
    Result := 'SELECT ' + LFields;
    
  Result := Result + ' FROM ' + FTableName;
  
  // Joins
  for I := 0 to High(FJoins) do
    Result := Result + ' ' + FJoins[I];
  
  // Where
  LParamIdx := 1;
  if Length(FConditions) > 0 then
  begin
    LWhere := '';
    for I := 0 to High(FConditions) do
    begin
      if I > 0 then LWhere := LWhere + ' AND ';
      LWhere := LWhere + FConditions[I].ToSQL(AParams, LParamIdx);
      Inc(LParamIdx);
      if FConditions[I].Operator = foBetween then
        Inc(LParamIdx);
    end;
    Result := Result + ' WHERE ' + LWhere;
  end;
  
  // Group By
  if Length(FGroupBy) > 0 then
    Result := Result + ' GROUP BY ' + String.Join(', ', FGroupBy);
    
  // Having
  if FHaving <> '' then
    Result := Result + ' HAVING ' + FHaving;
  
  // Order By
  if Length(FSortFields) > 0 then
  begin
    LOrder := '';
    for I := 0 to High(FSortFields) do
    begin
      if I > 0 then LOrder := LOrder + ', ';
      LOrder := LOrder + FSortFields[I].ToSQL;
    end;
    Result := Result + ' ORDER BY ' + LOrder;
  end;
  
  // Pagination
  Result := Result + Format(' LIMIT %d OFFSET %d', 
    [FPagination.PageSize, FPagination.Offset]);
end;

function TQueryBuilder.BuildCount(var AParams: TQueryParams): string;
var
  I, LParamIdx: Integer;
  LWhere: string;
begin
  Result := 'SELECT COUNT(*) FROM ' + FTableName;
  
  // Where
  LParamIdx := 1;
  if Length(FConditions) > 0 then
  begin
    LWhere := '';
    for I := 0 to High(FConditions) do
    begin
      if I > 0 then LWhere := LWhere + ' AND ';
      LWhere := LWhere + FConditions[I].ToSQL(AParams, LParamIdx);
      Inc(LParamIdx);
    end;
    Result := Result + ' WHERE ' + LWhere;
  end;
end;

function TQueryBuilder.BuildInsert(const AFields: TArray<string>; var AParams: TQueryParams): string;
var
  I: Integer;
  LValues: string;
begin
  Result := Format('INSERT INTO %s (%s) VALUES (', 
    [FTableName, String.Join(', ', AFields)]);
    
  LValues := '';
  for I := 0 to High(AFields) do
  begin
    if I > 0 then LValues := LValues + ', ';
    LValues := LValues + '$' + IntToStr(I + 1);
  end;
  
  Result := Result + LValues + ') RETURNING id';
end;

function TQueryBuilder.BuildUpdate(const AFields: TArray<string>; var AParams: TQueryParams): string;
var
  I, LParamIdx: Integer;
  LSet, LWhere: string;
begin
  LSet := '';
  for I := 0 to High(AFields) do
  begin
    if I > 0 then LSet := LSet + ', ';
    LSet := LSet + AFields[I] + ' = $' + IntToStr(I + 1);
  end;
  
  Result := Format('UPDATE %s SET %s', [FTableName, LSet]);
  
  // Where
  LParamIdx := Length(AFields) + 1;
  if Length(FConditions) > 0 then
  begin
    LWhere := '';
    for I := 0 to High(FConditions) do
    begin
      if I > 0 then LWhere := LWhere + ' AND ';
      LWhere := LWhere + FConditions[I].ToSQL(AParams, LParamIdx);
      Inc(LParamIdx);
    end;
    Result := Result + ' WHERE ' + LWhere;
  end;
end;

function TQueryBuilder.BuildDelete(var AParams: TQueryParams): string;
var
  I, LParamIdx: Integer;
  LWhere: string;
begin
  Result := 'DELETE FROM ' + FTableName;
  
  // Where
  LParamIdx := 1;
  if Length(FConditions) > 0 then
  begin
    LWhere := '';
    for I := 0 to High(FConditions) do
    begin
      if I > 0 then LWhere := LWhere + ' AND ';
      LWhere := LWhere + FConditions[I].ToSQL(AParams, LParamIdx);
      Inc(LParamIdx);
    end;
    Result := Result + ' WHERE ' + LWhere;
  end;
end;

{==========================================================================}
{  TStorageEntity                                                          }
{==========================================================================}

constructor TStorageEntity.Create;
begin
  inherited Create;
  FId := TGUID.NewGuid.ToString;
  FCreatedAt := Now;
  FUpdatedAt := Now;
  FVersion := 1;
end;

function TStorageEntity.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('createdAt', DateToISO8601(FCreatedAt));
  Result.AddPair('updatedAt', DateToISO8601(FUpdatedAt));
  Result.AddPair('version', TJSONNumber.Create(FVersion));
  Result.AddPair('tenantId', FTenantId);
end;

procedure TStorageEntity.FromJSON(AJSON: TJSONObject);
begin
  if not Assigned(AJSON) then Exit;
  
  FId := AJSON.GetValue<string>('id', FId);
  FCreatedAt := ISO8601ToDate(AJSON.GetValue<string>('createdAt', DateToISO8601(FCreatedAt)));
  FUpdatedAt := ISO8601ToDate(AJSON.GetValue<string>('updatedAt', DateToISO8601(FUpdatedAt)));
  FVersion := AJSON.GetValue<Integer>('version', FVersion);
  FTenantId := AJSON.GetValue<string>('tenantId', FTenantId);
end;

{==========================================================================}
{  TWorkflowEntity                                                         }
{==========================================================================}

constructor TWorkflowEntity.Create;
begin
  inherited Create;
  FDefinition := TJSONObject.Create;
  FStatus := 'draft';
end;

destructor TWorkflowEntity.Destroy;
begin
  FDefinition.Free;
  inherited;
end;

function TWorkflowEntity.ToJSON: TJSONObject;
var
  LTags: TJSONArray;
  I: Integer;
begin
  Result := inherited ToJSON;
  Result.AddPair('name', FName);
  Result.AddPair('description', FDescription);
  Result.AddPair('definition', FDefinition.Clone as TJSONObject);
  Result.AddPair('status', FStatus);
  
  LTags := TJSONArray.Create;
  for I := 0 to High(FTags) do
    LTags.Add(FTags[I]);
  Result.AddPair('tags', LTags);
end;

procedure TWorkflowEntity.FromJSON(AJSON: TJSONObject);
var
  LDef: TJSONObject;
  LTags: TJSONArray;
  I: Integer;
begin
  inherited FromJSON(AJSON);
  if not Assigned(AJSON) then Exit;
  
  FName := AJSON.GetValue<string>('name', '');
  FDescription := AJSON.GetValue<string>('description', '');
  FStatus := AJSON.GetValue<string>('status', 'draft');
  
  if AJSON.TryGetValue<TJSONObject>('definition', LDef) then
  begin
    FDefinition.Free;
    FDefinition := LDef.Clone as TJSONObject;
  end;
  
  if AJSON.TryGetValue<TJSONArray>('tags', LTags) then
  begin
    SetLength(FTags, LTags.Count);
    for I := 0 to LTags.Count - 1 do
      FTags[I] := LTags.Items[I].Value;
  end;
end;

{==========================================================================}
{  TSessionEntity                                                          }
{==========================================================================}

constructor TSessionEntity.Create;
begin
  inherited Create;
  FContext := TJSONObject.Create;
  FStatus := 'pending';
end;

destructor TSessionEntity.Destroy;
begin
  FContext.Free;
  inherited;
end;

function TSessionEntity.ToJSON: TJSONObject;
begin
  Result := inherited ToJSON;
  Result.AddPair('workflowId', FWorkflowId);
  Result.AddPair('userId', FUserId);
  Result.AddPair('status', FStatus);
  Result.AddPair('currentStep', FCurrentStep);
  Result.AddPair('context', FContext.Clone as TJSONObject);
  Result.AddPair('startedAt', DateToISO8601(FStartedAt));
  if FCompletedAt > 0 then
    Result.AddPair('completedAt', DateToISO8601(FCompletedAt));
end;

procedure TSessionEntity.FromJSON(AJSON: TJSONObject);
var
  LCtx: TJSONObject;
begin
  inherited FromJSON(AJSON);
  if not Assigned(AJSON) then Exit;
  
  FWorkflowId := AJSON.GetValue<string>('workflowId', '');
  FUserId := AJSON.GetValue<string>('userId', '');
  FStatus := AJSON.GetValue<string>('status', 'pending');
  FCurrentStep := AJSON.GetValue<string>('currentStep', '');
  FStartedAt := ISO8601ToDate(AJSON.GetValue<string>('startedAt', ''));
  FCompletedAt := ISO8601ToDate(AJSON.GetValue<string>('completedAt', ''));
  
  if AJSON.TryGetValue<TJSONObject>('context', LCtx) then
  begin
    FContext.Free;
    FContext := LCtx.Clone as TJSONObject;
  end;
end;

{==========================================================================}
{  TSkillEntity                                                            }
{==========================================================================}

constructor TSkillEntity.Create;
begin
  inherited Create;
  FInputSchema := TJSONObject.Create;
  FOutputSchema := TJSONObject.Create;
  FRuntime := 'python';
  FEnabled := True;
end;

destructor TSkillEntity.Destroy;
begin
  FInputSchema.Free;
  FOutputSchema.Free;
  inherited;
end;

function TSkillEntity.ToJSON: TJSONObject;
begin
  Result := inherited ToJSON;
  Result.AddPair('name', FName);
  Result.AddPair('description', FDescription);
  Result.AddPair('runtime', FRuntime);
  Result.AddPair('code', FCode);
  Result.AddPair('inputSchema', FInputSchema.Clone as TJSONObject);
  Result.AddPair('outputSchema', FOutputSchema.Clone as TJSONObject);
  Result.AddPair('category', FCategory);
  Result.AddPair('enabled', TJSONBool.Create(FEnabled));
end;

procedure TSkillEntity.FromJSON(AJSON: TJSONObject);
var
  LSchema: TJSONObject;
begin
  inherited FromJSON(AJSON);
  if not Assigned(AJSON) then Exit;
  
  FName := AJSON.GetValue<string>('name', '');
  FDescription := AJSON.GetValue<string>('description', '');
  FRuntime := AJSON.GetValue<string>('runtime', 'python');
  FCode := AJSON.GetValue<string>('code', '');
  FCategory := AJSON.GetValue<string>('category', '');
  FEnabled := AJSON.GetValue<Boolean>('enabled', True);
  
  if AJSON.TryGetValue<TJSONObject>('inputSchema', LSchema) then
  begin
    FInputSchema.Free;
    FInputSchema := LSchema.Clone as TJSONObject;
  end;
  
  if AJSON.TryGetValue<TJSONObject>('outputSchema', LSchema) then
  begin
    FOutputSchema.Free;
    FOutputSchema := LSchema.Clone as TJSONObject;
  end;
end;

end.
