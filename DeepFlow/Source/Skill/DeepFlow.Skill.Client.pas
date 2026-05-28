(*******************************************************************************
                                                                               
  UniFlow Skill Client                                                         
  HTTP client for communicating with Python Skill service                      
                                                                               
  Features:                                                                    
  - Synchronous and asynchronous HTTP calls                                    
  - Connection pooling and retry logic                                         
  - Timeout handling                                                           
  - Health check support                                                       
                                                                               
*******************************************************************************)

unit UniFlow.Skill.Client;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Threading,
  UniFlow.Skill.Types;

type
  //----------------------------------------------------------------------------
  // TSkillClientConfig - Client configuration
  //----------------------------------------------------------------------------

  /// <summary>认证类型 (SEC-004)</summary>
  TSkillAuthType = (
    satNone,       // 无认�?
    satApiKey,     // API Key 认证
    satBearer,     // Bearer Token 认证
    satBasic       // Basic 认证
  );

  /// <summary>
  /// Skill 客户端配�?
  /// CODE-004: 所有超�?重试参数均可配置
  /// SEC-004: 支持多种认证方式
  /// </summary>
  TSkillClientConfig = class
  private
    FBaseURL: string;
    FTimeoutMs: Integer;
    FMaxRetries: Integer;
    FRetryDelayMs: Integer;
    FConnectTimeoutMs: Integer;
    // SEC-004: 认证配置
    FAuthType: TSkillAuthType;
    FApiKey: string;
    FApiKeyHeader: string;      // 默认 'X-API-Key'
    FBearerToken: string;
    FBasicUsername: string;
    FBasicPassword: string;
    // CODE-004: 高级配置
    FRetryBackoffMultiplier: Double;  // 退避乘�?
    FMaxRetryDelayMs: Integer;        // 最大重试延�?
    FEnableRetryOnTimeout: Boolean;   // 超时时重�?
    FEnableRetryOn5xx: Boolean;       // 5xx 时重�?
  public
    constructor Create;

    /// <summary>�?JSON 加载配置</summary>
    procedure LoadFromJSON(AJson: TJSONObject);
    /// <summary>导出�?JSON</summary>
    function ToJSON: TJSONObject;
    /// <summary>从文件加�?/summary>
    procedure LoadFromFile(const AFilePath: string);
    /// <summary>保存到文�?/summary>
    procedure SaveToFile(const AFilePath: string);

    // 基本配置
    property BaseURL: string read FBaseURL write FBaseURL;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;
    property RetryDelayMs: Integer read FRetryDelayMs write FRetryDelayMs;
    property ConnectTimeoutMs: Integer read FConnectTimeoutMs write FConnectTimeoutMs;
    // SEC-004: 认证配置
    property AuthType: TSkillAuthType read FAuthType write FAuthType;
    property ApiKey: string read FApiKey write FApiKey;
    property ApiKeyHeader: string read FApiKeyHeader write FApiKeyHeader;
    property BearerToken: string read FBearerToken write FBearerToken;
    property BasicUsername: string read FBasicUsername write FBasicUsername;
    property BasicPassword: string read FBasicPassword write FBasicPassword;
    // CODE-004: 高级重试配置
    property RetryBackoffMultiplier: Double read FRetryBackoffMultiplier write FRetryBackoffMultiplier;
    property MaxRetryDelayMs: Integer read FMaxRetryDelayMs write FMaxRetryDelayMs;
    property EnableRetryOnTimeout: Boolean read FEnableRetryOnTimeout write FEnableRetryOnTimeout;
    property EnableRetryOn5xx: Boolean read FEnableRetryOn5xx write FEnableRetryOn5xx;
  end;

  //----------------------------------------------------------------------------
  // TSkillClient - HTTP client for Skill service
  //----------------------------------------------------------------------------

  TSkillClientCallback = reference to procedure(const AResponse: TSkillResponse);
  TLLMClientCallback = reference to procedure(const AResponse: TLLMResponse);
  THealthCallback = reference to procedure(const AResponse: THealthResponse);
  TErrorCallback = reference to procedure(const AError: string);

  TSkillClient = class
  private
    FConfig: TSkillClientConfig;
    FHttpClient: THTTPClient;
    FOwnsConfig: Boolean;

    function BuildURL(const AEndpoint: string): string;
    procedure ApplyAuthentication;  // SEC-004: 应用认证�?
    function CalculateRetryDelay(AAttempt: Integer): Integer;  // CODE-004: 计算重试延迟
    function ShouldRetry(AStatusCode: Integer; const AError: string): Boolean;  // CODE-004: 判断是否重试
    function DoRequest(const AMethod, AEndpoint: string;
      const ABody: TJSONObject = nil): TJSONObject;
    procedure DoRequestAsync(const AMethod, AEndpoint: string;
      const ABody: TJSONObject;
      const AOnSuccess: TProc<TJSONObject>;
      const AOnError: TErrorCallback);

    function ParseSkillResponse(const AJSON: TJSONObject): TSkillResponse;
    function ParseLLMResponse(const AJSON: TJSONObject): TLLMResponse;
    function ParseHealthResponse(const AJSON: TJSONObject): THealthResponse;
  public
    constructor Create(const ABaseURL: string); overload;
    constructor Create(AConfig: TSkillClientConfig; AOwnsConfig: Boolean = True); overload;
    destructor Destroy; override;

    //--------------------------------------------------------------------------
    // Health Check
    //--------------------------------------------------------------------------

    /// <summary>Check service health (sync)</summary>
    function CheckHealth: THealthResponse;

    /// <summary>Check service health (async)</summary>
    procedure CheckHealthAsync(const AOnSuccess: THealthCallback;
      const AOnError: TErrorCallback);

    /// <summary>Check if service is available</summary>
    function IsAvailable: Boolean;

    //--------------------------------------------------------------------------
    // Skill Operations
    //--------------------------------------------------------------------------

    /// <summary>List all available Skills (sync)</summary>
    function ListSkills: TObjectList<TSkillInfo>;

    /// <summary>Get Skill info by name (sync)</summary>
    function GetSkill(const ASkillName: string): TSkillInfo;

    /// <summary>Execute a Skill (sync)</summary>
    function ExecuteSkill(const ARequest: TSkillRequest): TSkillResponse; overload;
    function ExecuteSkill(const ASkillName: string;
      const AParams: TJSONObject = nil): TSkillResponse; overload;

    /// <summary>Execute a Skill (async)</summary>
    procedure ExecuteSkillAsync(const ARequest: TSkillRequest;
      const AOnSuccess: TSkillClientCallback;
      const AOnError: TErrorCallback); overload;
    procedure ExecuteSkillAsync(const ASkillName: string;
      const AParams: TJSONObject;
      const AOnSuccess: TSkillClientCallback;
      const AOnError: TErrorCallback); overload;

    //--------------------------------------------------------------------------
    // LLM Operations
    //--------------------------------------------------------------------------

    /// <summary>Chat completion (sync)</summary>
    function Chat(const ARequest: TLLMRequest): TLLMResponse; overload;
    function Chat(const AMessages: array of TLLMMessage;
      const AModel: string = ''): TLLMResponse; overload;

    /// <summary>Simple chat with single message (sync)</summary>
    function SimpleChat(const AUserMessage: string;
      const ASystemPrompt: string = '';
      const AModel: string = ''): string;

    /// <summary>Chat completion (async)</summary>
    procedure ChatAsync(const ARequest: TLLMRequest;
      const AOnSuccess: TLLMClientCallback;
      const AOnError: TErrorCallback);

    //--------------------------------------------------------------------------
    // Properties
    //--------------------------------------------------------------------------

    property Config: TSkillClientConfig read FConfig;
  end;

  //----------------------------------------------------------------------------
  // TSkillClientPool - Connection pool for multiple clients
  //----------------------------------------------------------------------------

  TSkillClientPool = class
  private
    FClients: TObjectList<TSkillClient>;
    FConfig: TSkillClientConfig;
    FPoolSize: Integer;
    FCurrentIndex: Integer;
    FLock: TObject;

    function GetClient: TSkillClient;
  public
    constructor Create(const ABaseURL: string; APoolSize: Integer = 4);
    destructor Destroy; override;

    /// <summary>Execute with pooled client</summary>
    function Execute(const ARequest: TSkillRequest): TSkillResponse;

    property PoolSize: Integer read FPoolSize;
  end;

implementation

uses
  System.DateUtils,
  System.NetEncoding,
  System.IOUtils,
  System.Math;

//------------------------------------------------------------------------------
// TSkillClientConfig
//------------------------------------------------------------------------------

constructor TSkillClientConfig.Create;
begin
  inherited Create;
  // CODE-004: 默认配置
  FBaseURL := 'http://localhost:8000';
  FTimeoutMs := 30000;
  FMaxRetries := 3;
  FRetryDelayMs := 1000;
  FConnectTimeoutMs := 5000;
  // SEC-004: 默认无认�?
  FAuthType := satNone;
  FApiKeyHeader := 'X-API-Key';
  // CODE-004: 高级重试配置
  FRetryBackoffMultiplier := 2.0;
  FMaxRetryDelayMs := 30000;
  FEnableRetryOnTimeout := True;
  FEnableRetryOn5xx := True;
end;

procedure TSkillClientConfig.LoadFromJSON(AJson: TJSONObject);
var
  AuthStr: string;
begin
  if AJson = nil then Exit;
  
  // 基本配置
  AJson.TryGetValue<string>('baseUrl', FBaseURL);
  AJson.TryGetValue<Integer>('timeoutMs', FTimeoutMs);
  AJson.TryGetValue<Integer>('maxRetries', FMaxRetries);
  AJson.TryGetValue<Integer>('retryDelayMs', FRetryDelayMs);
  AJson.TryGetValue<Integer>('connectTimeoutMs', FConnectTimeoutMs);
  
  // SEC-004: 认证配置
  if AJson.TryGetValue<string>('authType', AuthStr) then
  begin
    if SameText(AuthStr, 'apiKey') then FAuthType := satApiKey
    else if SameText(AuthStr, 'bearer') then FAuthType := satBearer
    else if SameText(AuthStr, 'basic') then FAuthType := satBasic
    else FAuthType := satNone;
  end;
  AJson.TryGetValue<string>('apiKey', FApiKey);
  AJson.TryGetValue<string>('apiKeyHeader', FApiKeyHeader);
  AJson.TryGetValue<string>('bearerToken', FBearerToken);
  AJson.TryGetValue<string>('basicUsername', FBasicUsername);
  AJson.TryGetValue<string>('basicPassword', FBasicPassword);
  
  // CODE-004: 高级重试配置
  AJson.TryGetValue<Double>('retryBackoffMultiplier', FRetryBackoffMultiplier);
  AJson.TryGetValue<Integer>('maxRetryDelayMs', FMaxRetryDelayMs);
  AJson.TryGetValue<Boolean>('enableRetryOnTimeout', FEnableRetryOnTimeout);
  AJson.TryGetValue<Boolean>('enableRetryOn5xx', FEnableRetryOn5xx);
end;

function TSkillClientConfig.ToJSON: TJSONObject;
const
  AuthNames: array[TSkillAuthType] of string = ('none', 'apiKey', 'bearer', 'basic');
begin
  Result := TJSONObject.Create;
  // 基本配置
  Result.AddPair('baseUrl', FBaseURL);
  Result.AddPair('timeoutMs', TJSONNumber.Create(FTimeoutMs));
  Result.AddPair('maxRetries', TJSONNumber.Create(FMaxRetries));
  Result.AddPair('retryDelayMs', TJSONNumber.Create(FRetryDelayMs));
  Result.AddPair('connectTimeoutMs', TJSONNumber.Create(FConnectTimeoutMs));
  // SEC-004: 认证配置 (不导出敏感信�?
  Result.AddPair('authType', AuthNames[FAuthType]);
  Result.AddPair('apiKeyHeader', FApiKeyHeader);
  // CODE-004: 高级重试配置
  Result.AddPair('retryBackoffMultiplier', TJSONNumber.Create(FRetryBackoffMultiplier));
  Result.AddPair('maxRetryDelayMs', TJSONNumber.Create(FMaxRetryDelayMs));
  Result.AddPair('enableRetryOnTimeout', TJSONBool.Create(FEnableRetryOnTimeout));
  Result.AddPair('enableRetryOn5xx', TJSONBool.Create(FEnableRetryOn5xx));
end;

procedure TSkillClientConfig.LoadFromFile(const AFilePath: string);
var
  Json: TJSONObject;
  Content: string;
begin
  if not TFile.Exists(AFilePath) then Exit;
  Content := TFile.ReadAllText(AFilePath);
  Json := TJSONObject.ParseJSONValue(Content) as TJSONObject;
  if Json <> nil then
  try
    LoadFromJSON(Json);
  finally
    Json.Free;
  end;
end;

procedure TSkillClientConfig.SaveToFile(const AFilePath: string);
var
  Json: TJSONObject;
begin
  Json := ToJSON;
  try
    TFile.WriteAllText(AFilePath, Json.Format(2));
  finally
    Json.Free;
  end;
end;

//------------------------------------------------------------------------------
// TSkillClient
//------------------------------------------------------------------------------

constructor TSkillClient.Create(const ABaseURL: string);
begin
  FConfig := TSkillClientConfig.Create;
  FConfig.BaseURL := ABaseURL;
  FOwnsConfig := True;
  Create(FConfig, True);
end;

constructor TSkillClient.Create(AConfig: TSkillClientConfig; AOwnsConfig: Boolean);
begin
  inherited Create;
  FConfig := AConfig;
  FOwnsConfig := AOwnsConfig;

  FHttpClient := THTTPClient.Create;
  FHttpClient.ContentType := 'application/json';
  FHttpClient.Accept := 'application/json';
  FHttpClient.ResponseTimeout := FConfig.TimeoutMs;
  FHttpClient.ConnectionTimeout := FConfig.ConnectTimeoutMs;
  
  // SEC-004: 应用认证
  ApplyAuthentication;
end;

procedure TSkillClient.ApplyAuthentication;
var
  Credentials: string;
begin
  // SEC-004: 根据配置应用认证�?
  case FConfig.AuthType of
    satApiKey:
      if FConfig.ApiKey <> '' then
        FHttpClient.CustomHeaders[FConfig.ApiKeyHeader] := FConfig.ApiKey;
    satBearer:
      if FConfig.BearerToken <> '' then
        FHttpClient.CustomHeaders['Authorization'] := 'Bearer ' + FConfig.BearerToken;
    satBasic:
      if (FConfig.BasicUsername <> '') or (FConfig.BasicPassword <> '') then
      begin
        Credentials := TNetEncoding.Base64.Encode(
          FConfig.BasicUsername + ':' + FConfig.BasicPassword);
        FHttpClient.CustomHeaders['Authorization'] := 'Basic ' + Credentials;
      end;
  end;
end;

function TSkillClient.CalculateRetryDelay(AAttempt: Integer): Integer;
begin
  // CODE-004: 指数退避计�?
  Result := Round(FConfig.RetryDelayMs * Power(FConfig.RetryBackoffMultiplier, AAttempt - 1));
  // 限制最大延�?
  if Result > FConfig.MaxRetryDelayMs then
    Result := FConfig.MaxRetryDelayMs;
end;

function TSkillClient.ShouldRetry(AStatusCode: Integer; const AError: string): Boolean;
begin
  // CODE-004: 判断是否应该重试
  Result := False;
  
  // 5xx 服务器错�?
  if (AStatusCode >= 500) and (AStatusCode < 600) then
    Result := FConfig.EnableRetryOn5xx;
  
  // 超时错误
  if Pos('timeout', LowerCase(AError)) > 0 then
    Result := FConfig.EnableRetryOnTimeout;
  
  // 连接错误
  if Pos('connection', LowerCase(AError)) > 0 then
    Result := True;
end;

destructor TSkillClient.Destroy;
begin
  FHttpClient.Free;
  if FOwnsConfig then
    FConfig.Free;
  inherited Destroy;
end;

function TSkillClient.BuildURL(const AEndpoint: string): string;
begin
  Result := FConfig.BaseURL;
  if not Result.EndsWith('/') then
    Result := Result + '/';
  if AEndpoint.StartsWith('/') then
    Result := Result + AEndpoint.Substring(1)
  else
    Result := Result + AEndpoint;
end;

function TSkillClient.DoRequest(const AMethod, AEndpoint: string;
  const ABody: TJSONObject): TJSONObject;
var
  URL: string;
  Response: IHTTPResponse;
  RequestStream: TStringStream;
  ResponseStr: string;
  Attempt: Integer;
  LastError: string;
  LastStatusCode: Integer;
  DelayMs: Integer;
begin
  Result := nil;
  URL := BuildURL(AEndpoint);
  LastError := '';
  LastStatusCode := 0;

  for Attempt := 1 to FConfig.MaxRetries do
  begin
    try
      RequestStream := nil;
      try
        if Assigned(ABody) then
          RequestStream := TStringStream.Create(ABody.ToString, TEncoding.UTF8);

        if SameText(AMethod, 'GET') then
          Response := FHttpClient.Get(URL)
        else if SameText(AMethod, 'POST') then
          Response := FHttpClient.Post(URL, RequestStream)
        else if SameText(AMethod, 'PUT') then
          Response := FHttpClient.Put(URL, RequestStream)
        else if SameText(AMethod, 'DELETE') then
          Response := FHttpClient.Delete(URL)
        else
          raise ESkillException.CreateFmt('Unsupported HTTP method: %s', [AMethod]);

        LastStatusCode := Response.StatusCode;
        
        if Response.StatusCode >= 200 then
        begin
          if Response.StatusCode < 300 then
          begin
            ResponseStr := Response.ContentAsString(TEncoding.UTF8);
            if ResponseStr <> '' then
              Result := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject
            else
              Result := TJSONObject.Create;
            Exit;
          end
          // SEC-004: 401/403 认证错误不重�?
          else if Response.StatusCode = 401 then
            raise ESkillException.Create('Authentication required (401)')
          else if Response.StatusCode = 403 then
            raise ESkillException.Create('Access forbidden (403)')
          else if Response.StatusCode = 404 then
            raise ESkillNotFound.CreateFmt('Resource not found: %s', [AEndpoint])
          else if Response.StatusCode >= 500 then
            LastError := Format('Server error: %d - %s',
              [Response.StatusCode, Response.StatusText])
          else
            raise ESkillException.CreateFmt('HTTP error: %d - %s',
              [Response.StatusCode, Response.StatusText]);
        end;

      finally
        RequestStream.Free;
      end;

    except
      on E: ESkillNotFound do
        raise;
      on E: ESkillException do
      begin
        // SEC-004: 认证错误不重�?
        if (Pos('401', E.Message) > 0) or (Pos('403', E.Message) > 0) then
          raise;
        LastError := E.Message;
      end;
      on E: Exception do
      begin
        LastError := E.Message;
      end;
    end;
    
    // CODE-004: 判断是否重试
    if (Attempt < FConfig.MaxRetries) and ShouldRetry(LastStatusCode, LastError) then
    begin
      DelayMs := CalculateRetryDelay(Attempt);
      Sleep(DelayMs);
    end
    else if Attempt >= FConfig.MaxRetries then
      Break;
  end;

  raise ESkillConnectionError.CreateFmt('Request failed after %d attempts: %s',
    [FConfig.MaxRetries, LastError]);
end;

procedure TSkillClient.DoRequestAsync(const AMethod, AEndpoint: string;
  const ABody: TJSONObject;
  const AOnSuccess: TProc<TJSONObject>;
  const AOnError: TErrorCallback);
begin
  TTask.Run(
    procedure
    var
      Response: TJSONObject;
    begin
      try
        Response := DoRequest(AMethod, AEndpoint, ABody);
        TThread.Synchronize(nil,
          procedure
          begin
            if Assigned(AOnSuccess) then
              AOnSuccess(Response);
          end);
      except
        on E: Exception do
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              if Assigned(AOnError) then
                AOnError(E.Message);
            end);
        end;
      end;
    end);
end;

function TSkillClient.ParseSkillResponse(const AJSON: TJSONObject): TSkillResponse;
begin
  Result := TSkillResponse.FromJSON(AJSON);
end;

function TSkillClient.ParseLLMResponse(const AJSON: TJSONObject): TLLMResponse;
begin
  Result := TLLMResponse.FromJSON(AJSON);
end;

function TSkillClient.ParseHealthResponse(const AJSON: TJSONObject): THealthResponse;
begin
  Result := THealthResponse.FromJSON(AJSON);
end;

//------------------------------------------------------------------------------
// Health Check
//------------------------------------------------------------------------------

function TSkillClient.CheckHealth: THealthResponse;
var
  ResponseJSON: TJSONObject;
begin
  ResponseJSON := DoRequest('GET', '/health');
  try
    Result := ParseHealthResponse(ResponseJSON);
  finally
    ResponseJSON.Free;
  end;
end;

procedure TSkillClient.CheckHealthAsync(const AOnSuccess: THealthCallback;
  const AOnError: TErrorCallback);
begin
  DoRequestAsync('GET', '/health', nil,
    procedure(Response: TJSONObject)
    var
      HealthResponse: THealthResponse;
    begin
      try
        HealthResponse := ParseHealthResponse(Response);
        if Assigned(AOnSuccess) then
          AOnSuccess(HealthResponse);
      finally
        Response.Free;
        HealthResponse.Free;
      end;
    end,
    AOnError);
end;

function TSkillClient.IsAvailable: Boolean;
var
  Health: THealthResponse;
begin
  try
    Health := CheckHealth;
    try
      Result := Health.IsHealthy;
    finally
      Health.Free;
    end;
  except
    Result := False;
  end;
end;

//------------------------------------------------------------------------------
// Skill Operations
//------------------------------------------------------------------------------

function TSkillClient.ListSkills: TObjectList<TSkillInfo>;
var
  ResponseJSON: TJSONObject;
  SkillsArray: TJSONArray;
  I: Integer;
begin
  Result := TObjectList<TSkillInfo>.Create(True);
  try
    ResponseJSON := DoRequest('GET', '/skills');
    try
      // Check if response contains skills array
      if ResponseJSON.TryGetValue<TJSONArray>('skills', SkillsArray) then
      begin
        for I := 0 to SkillsArray.Count - 1 do
          Result.Add(TSkillInfo.FromJSON(SkillsArray.Items[I] as TJSONObject));
      end;
    finally
      ResponseJSON.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TSkillClient.GetSkill(const ASkillName: string): TSkillInfo;
var
  ResponseJSON: TJSONObject;
begin
  ResponseJSON := DoRequest('GET', '/skills/' + TNetEncoding.URL.Encode(ASkillName));
  try
    Result := TSkillInfo.FromJSON(ResponseJSON);
  finally
    ResponseJSON.Free;
  end;
end;

function TSkillClient.ExecuteSkill(const ARequest: TSkillRequest): TSkillResponse;
var
  RequestJSON, ResponseJSON: TJSONObject;
begin
  RequestJSON := ARequest.ToJSON;
  try
    ResponseJSON := DoRequest('POST', '/skills/execute', RequestJSON);
    try
      Result := ParseSkillResponse(ResponseJSON);
    finally
      ResponseJSON.Free;
    end;
  finally
    RequestJSON.Free;
  end;
end;

function TSkillClient.ExecuteSkill(const ASkillName: string;
  const AParams: TJSONObject): TSkillResponse;
var
  Request: TSkillRequest;
  Pair: TJSONPair;
begin
  Request := TSkillRequest.Create;
  try
    Request.SkillName := ASkillName;
    if Assigned(AParams) then
    begin
      for Pair in AParams do
        Request.SetParamJSON(Pair.JsonString.Value, Pair.JsonValue);
    end;
    Result := ExecuteSkill(Request);
  finally
    Request.Free;
  end;
end;

procedure TSkillClient.ExecuteSkillAsync(const ARequest: TSkillRequest;
  const AOnSuccess: TSkillClientCallback;
  const AOnError: TErrorCallback);
var
  RequestJSON: TJSONObject;
begin
  RequestJSON := ARequest.ToJSON;
  DoRequestAsync('POST', '/skills/execute', RequestJSON,
    procedure(Response: TJSONObject)
    var
      SkillResponse: TSkillResponse;
    begin
      RequestJSON.Free;
      try
        SkillResponse := ParseSkillResponse(Response);
        if Assigned(AOnSuccess) then
          AOnSuccess(SkillResponse);
      finally
        Response.Free;
        SkillResponse.Free;
      end;
    end,
    procedure(const Error: string)
    begin
      RequestJSON.Free;
      if Assigned(AOnError) then
        AOnError(Error);
    end);
end;

procedure TSkillClient.ExecuteSkillAsync(const ASkillName: string;
  const AParams: TJSONObject;
  const AOnSuccess: TSkillClientCallback;
  const AOnError: TErrorCallback);
var
  Request: TSkillRequest;
  Pair: TJSONPair;
  SuccessCallback: TSkillClientCallback;
  ErrorCallback: TErrorCallback;
begin
  Request := TSkillRequest.Create;
  Request.SkillName := ASkillName;
  if Assigned(AParams) then
  begin
    for Pair in AParams do
      Request.SetParamJSON(Pair.JsonString.Value, Pair.JsonValue);
  end;

  SuccessCallback := procedure(const Response: TSkillResponse)
    begin
      Request.Free;
      if Assigned(AOnSuccess) then
        AOnSuccess(Response);
    end;

  ErrorCallback := procedure(const Error: string)
    begin
      Request.Free;
      if Assigned(AOnError) then
        AOnError(Error);
    end;

  ExecuteSkillAsync(Request, SuccessCallback, ErrorCallback);
end;

//------------------------------------------------------------------------------
// LLM Operations
//------------------------------------------------------------------------------

function TSkillClient.Chat(const ARequest: TLLMRequest): TLLMResponse;
var
  RequestJSON, ResponseJSON: TJSONObject;
begin
  RequestJSON := ARequest.ToJSON;
  try
    ResponseJSON := DoRequest('POST', '/llm/chat', RequestJSON);
    try
      Result := ParseLLMResponse(ResponseJSON);
    finally
      ResponseJSON.Free;
    end;
  finally
    RequestJSON.Free;
  end;
end;

function TSkillClient.Chat(const AMessages: array of TLLMMessage;
  const AModel: string): TLLMResponse;
var
  Request: TLLMRequest;
  Msg: TLLMMessage;
begin
  Request := TLLMRequest.Create;
  try
    if AModel <> '' then
      Request.Model := AModel;

    for Msg in AMessages do
      Request.Messages.Add(TLLMMessage.Create(Msg.Role, Msg.Content));

    Result := Chat(Request);
  finally
    Request.Free;
  end;
end;

function TSkillClient.SimpleChat(const AUserMessage: string;
  const ASystemPrompt: string;
  const AModel: string): string;
var
  Request: TLLMRequest;
  Response: TLLMResponse;
begin
  Request := TLLMRequest.Create;
  try
    if AModel <> '' then
      Request.Model := AModel;

    if ASystemPrompt <> '' then
      Request.AddSystemMessage(ASystemPrompt);

    Request.AddUserMessage(AUserMessage);

    Response := Chat(Request);
    try
      Result := Response.Content;
    finally
      Response.Free;
    end;
  finally
    Request.Free;
  end;
end;

procedure TSkillClient.ChatAsync(const ARequest: TLLMRequest;
  const AOnSuccess: TLLMClientCallback;
  const AOnError: TErrorCallback);
var
  RequestJSON: TJSONObject;
begin
  RequestJSON := ARequest.ToJSON;
  DoRequestAsync('POST', '/llm/chat', RequestJSON,
    procedure(Response: TJSONObject)
    var
      LLMResponse: TLLMResponse;
    begin
      RequestJSON.Free;
      try
        LLMResponse := ParseLLMResponse(Response);
        if Assigned(AOnSuccess) then
          AOnSuccess(LLMResponse);
      finally
        Response.Free;
        LLMResponse.Free;
      end;
    end,
    procedure(const Error: string)
    begin
      RequestJSON.Free;
      if Assigned(AOnError) then
        AOnError(Error);
    end);
end;

//------------------------------------------------------------------------------
// TSkillClientPool
//------------------------------------------------------------------------------

constructor TSkillClientPool.Create(const ABaseURL: string; APoolSize: Integer);
var
  I: Integer;
begin
  inherited Create;
  FLock := TObject.Create;
  FPoolSize := APoolSize;
  FCurrentIndex := 0;

  FConfig := TSkillClientConfig.Create;
  FConfig.BaseURL := ABaseURL;

  FClients := TObjectList<TSkillClient>.Create(True);
  for I := 1 to FPoolSize do
    FClients.Add(TSkillClient.Create(FConfig, False));
end;

destructor TSkillClientPool.Destroy;
begin
  FClients.Free;
  FConfig.Free;
  FLock.Free;
  inherited Destroy;
end;

function TSkillClientPool.GetClient: TSkillClient;
begin
  TMonitor.Enter(FLock);
  try
    Result := FClients[FCurrentIndex];
    FCurrentIndex := (FCurrentIndex + 1) mod FPoolSize;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSkillClientPool.Execute(const ARequest: TSkillRequest): TSkillResponse;
var
  Client: TSkillClient;
begin
  Client := GetClient;
  Result := Client.ExecuteSkill(ARequest);
end;

end.
