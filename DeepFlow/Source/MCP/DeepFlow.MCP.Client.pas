unit UniFlow.MCP.Client;
(*
  UniFlow MCP Client
  ==================
  TASK-2020: MCP 协议完整支持
  
  实现 MCP Client 端，调用外部 MCP Server 的能�?
  
  功能:
  - 连接管理 (HTTP/SSE)
  - Tool 发现与调�?
  - Resource 访问
  - Prompt 获取
  - 自动重连与错误处�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.Net.HttpClient, System.Net.URLClient,
  UniFlow.MCP.Types,
  DeepBase.Exceptions;

type
  // ============================================================================
  // MCP Client 配置
  // ============================================================================
  
  TMCPTransportType = (ttHttp, ttSSE, ttStdio);
  
  TMCPClientConfig = record
    ServerUrl: string;               // HTTP 端点 URL
    TransportType: TMCPTransportType;
    ClientName: string;
    ClientVersion: string;
    ConnectTimeoutMs: Integer;
    RequestTimeoutMs: Integer;
    AutoReconnect: Boolean;
    MaxRetries: Integer;
    
    class function Default: TMCPClientConfig; static;
  end;
  
  // ============================================================================
  // MCP 连接状�?
  // ============================================================================
  
  TMCPConnectionState = (csDisconnected, csConnecting, csConnected, csError);
  
  // ============================================================================
  // MCP Client 事件
  // ============================================================================
  
  TMCPNotificationEvent = procedure(Sender: TObject; const AMethod: string; 
    const AParams: TJSONObject) of object;
  TMCPStateChangeEvent = procedure(Sender: TObject; AState: TMCPConnectionState) of object;
  TMCPErrorEvent = procedure(Sender: TObject; const AError: string) of object;
  
  // ============================================================================
  // MCP Client
  // ============================================================================
  
  TMCPClient = class
  private
    FConfig: TMCPClientConfig;
    FHttp: THTTPClient;
    FState: TMCPConnectionState;
    FLock: TCriticalSection;
    FRequestId: Int64;
    FServerInfo: TMCPImplementation;
    FServerCapabilities: TMCPServerCapabilities;
    FInitialized: Boolean;
    
    // 缓存
    FToolsCache: TObjectList<TMCPTool>;
    FResourcesCache: TObjectList<TMCPResource>;
    FPromptsCache: TObjectList<TMCPPrompt>;
    FCacheValid: Boolean;
    
    // 事件
    FOnNotification: TMCPNotificationEvent;
    FOnStateChange: TMCPStateChangeEvent;
    FOnError: TMCPErrorEvent;
    
    function GetNextRequestId: Int64;
    procedure SetState(AState: TMCPConnectionState);
    
    // HTTP 通信
    function SendRequest(const AMethod: string; const AParams: TJSONObject = nil): TJSONObject;
    function BuildRequest(const AMethod: string; const AParams: TJSONObject): TJSONObject;
    function ParseResponse(const AResponse: TJSONObject): TJSONValue;
    
  public
    constructor Create(const AConfig: TMCPClientConfig);
    destructor Destroy; override;
    
    /// <summary>连接�?MCP Server</summary>
    function Connect: Boolean;
    
    /// <summary>断开连接</summary>
    procedure Disconnect;
    
    /// <summary>发�?Ping</summary>
    function Ping: Boolean;
    
    /// <summary>获取 Tool 列表</summary>
    function ListTools(AForceRefresh: Boolean = False): TArray<TMCPTool>;
    
    /// <summary>调用 Tool</summary>
    function CallTool(const AName: string; const AArguments: TJSONObject): TMCPToolResult;
    
    /// <summary>获取 Resource 列表</summary>
    function ListResources(AForceRefresh: Boolean = False): TArray<TMCPResource>;
    
    /// <summary>读取 Resource</summary>
    function ReadResource(const AUri: string): TMCPResourceContents;
    
    /// <summary>获取 Prompt 列表</summary>
    function ListPrompts(AForceRefresh: Boolean = False): TArray<TMCPPrompt>;
    
    /// <summary>获取 Prompt</summary>
    function GetPrompt(const AName: string; const AArguments: TJSONObject = nil): TGetPromptResult;
    
    /// <summary>查找 Tool</summary>
    function FindTool(const AName: string): TMCPTool;
    
    /// <summary>检查是否支持某 Tool</summary>
    function HasTool(const AName: string): Boolean;
    
    /// <summary>清除缓存</summary>
    procedure ClearCache;
    
    property Config: TMCPClientConfig read FConfig;
    property State: TMCPConnectionState read FState;
    property ServerInfo: TMCPImplementation read FServerInfo;
    property ServerCapabilities: TMCPServerCapabilities read FServerCapabilities;
    property Initialized: Boolean read FInitialized;
    
    // 事件
    property OnNotification: TMCPNotificationEvent read FOnNotification write FOnNotification;
    property OnStateChange: TMCPStateChangeEvent read FOnStateChange write FOnStateChange;
    property OnError: TMCPErrorEvent read FOnError write FOnError;
  end;
  
  // ============================================================================
  // MCP Client 管理�?
  // ============================================================================
  
  TMCPClientManager = class
  private
    FClients: TObjectDictionary<string, TMCPClient>;
    FLock: TCriticalSection;
    class var FInstance: TMCPClientManager;
  public
    constructor Create;
    destructor Destroy; override;
    
    class function Instance: TMCPClientManager;
    class procedure FreeInstance;
    
    /// <summary>注册 MCP Server</summary>
    procedure RegisterServer(const AServerId: string; const AConfig: TMCPClientConfig);
    
    /// <summary>注销 MCP Server</summary>
    procedure UnregisterServer(const AServerId: string);
    
    /// <summary>获取 Client</summary>
    function GetClient(const AServerId: string): TMCPClient;
    
    /// <summary>获取所�?Server ID</summary>
    function GetServerIds: TArray<string>;
    
    /// <summary>连接所�?Server</summary>
    procedure ConnectAll;
    
    /// <summary>断开所有连�?/summary>
    procedure DisconnectAll;
  end;

implementation

// ============================================================================
// TMCPClientConfig
// ============================================================================

class function TMCPClientConfig.Default: TMCPClientConfig;
begin
  Result.ServerUrl := '';
  Result.TransportType := ttHttp;
  Result.ClientName := 'UniFlow MCP Client';
  Result.ClientVersion := '1.0.0';
  Result.ConnectTimeoutMs := 10000;
  Result.RequestTimeoutMs := 30000;
  Result.AutoReconnect := True;
  Result.MaxRetries := 3;
end;

// ============================================================================
// TMCPClient
// ============================================================================

constructor TMCPClient.Create(const AConfig: TMCPClientConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FHttp := THTTPClient.Create;
  FHttp.ConnectionTimeout := AConfig.ConnectTimeoutMs;
  FHttp.ResponseTimeout := AConfig.RequestTimeoutMs;
  FLock := TCriticalSection.Create;
  FState := csDisconnected;
  FRequestId := 0;
  FInitialized := False;
  
  FToolsCache := TObjectList<TMCPTool>.Create(True);
  FResourcesCache := TObjectList<TMCPResource>.Create(True);
  FPromptsCache := TObjectList<TMCPPrompt>.Create(True);
  FCacheValid := False;
end;

destructor TMCPClient.Destroy;
begin
  Disconnect;
  FPromptsCache.Free;
  FResourcesCache.Free;
  FToolsCache.Free;
  FLock.Free;
  FHttp.Free;
  inherited;
end;

function TMCPClient.GetNextRequestId: Int64;
begin
  FLock.Enter;
  try
    Inc(FRequestId);
    Result := FRequestId;
  finally
    FLock.Leave;
  end;
end;

procedure TMCPClient.SetState(AState: TMCPConnectionState);
begin
  if FState <> AState then
  begin
    FState := AState;
    if Assigned(FOnStateChange) then
      FOnStateChange(Self, AState);
  end;
end;

function TMCPClient.BuildRequest(const AMethod: string; const AParams: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', TJSONNumber.Create(GetNextRequestId));
  Result.AddPair('method', AMethod);
  if Assigned(AParams) then
    Result.AddPair('params', AParams.Clone as TJSONObject);
end;

function TMCPClient.SendRequest(const AMethod: string; const AParams: TJSONObject): TJSONObject;
var
  LRequest: TJSONObject;
  LRequestStr: string;
  LResponse: IHTTPResponse;
  LContent: TStringStream;
begin
  Result := nil;
  
  if FConfig.ServerUrl.IsEmpty then
    raise EOperationException.Create('Server URL not configured');
  
  LRequest := BuildRequest(AMethod, AParams);
  try
    LRequestStr := LRequest.ToJSON;
    
    LContent := TStringStream.Create(LRequestStr, TEncoding.UTF8);
    try
      LResponse := FHttp.Post(
        FConfig.ServerUrl,
        LContent,
        nil,
        [TNameValuePair.Create('Content-Type', 'application/json')]
      );
      
      if LResponse.StatusCode = 200 then
      begin
        Result := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      end
      else
      begin
        raise EOperationException.CreateFmt('HTTP error %d: %s', 
          [LResponse.StatusCode, LResponse.StatusText]);
      end;
    finally
      LContent.Free;
    end;
  finally
    LRequest.Free;
  end;
end;

function TMCPClient.ParseResponse(const AResponse: TJSONObject): TJSONValue;
var
  LError: TJSONObject;
  LErrorCode: Integer;
  LErrorMsg: string;
begin
  Result := nil;
  
  if AResponse.TryGetValue<TJSONObject>('error', LError) then
  begin
    LErrorCode := LError.GetValue<Integer>('code', 0);
    LErrorMsg := LError.GetValue<string>('message', 'Unknown error');
    raise EOperationException.CreateFmt('MCP Error %d: %s', [LErrorCode, LErrorMsg]);
  end;
  
  if not AResponse.TryGetValue<TJSONValue>('result', Result) then
    raise EOperationException.Create('Invalid response: missing result');
end;

function TMCPClient.Connect: Boolean;
var
  LParams: TJSONObject;
  LClientInfo, LCapabilities: TJSONObject;
  LResponse: TJSONObject;
  LResult: TJSONObject;
begin
  Result := False;
  
  if FState = csConnected then
  begin
    Result := True;
    Exit;
  end;
  
  SetState(csConnecting);
  
  try
    // 构建 initialize 请求
    LParams := TJSONObject.Create;
    LParams.AddPair('protocolVersion', TMCPProtocolVersion.CURRENT);
    
    LClientInfo := TJSONObject.Create;
    LClientInfo.AddPair('name', FConfig.ClientName);
    LClientInfo.AddPair('version', FConfig.ClientVersion);
    LParams.AddPair('clientInfo', LClientInfo);
    
    LCapabilities := TJSONObject.Create;
    LParams.AddPair('capabilities', LCapabilities);
    
    // 发送请�?
    LResponse := SendRequest('initialize', LParams);
    try
      LResult := ParseResponse(LResponse) as TJSONObject;
      
      // 解析服务器信�?
      var LServerInfo: TJSONObject;
      if LResult.TryGetValue<TJSONObject>('serverInfo', LServerInfo) then
        FServerInfo := TMCPImplementation.FromJSON(LServerInfo);
      
      var LServerCaps: TJSONObject;
      if LResult.TryGetValue<TJSONObject>('capabilities', LServerCaps) then
        FServerCapabilities := TMCPServerCapabilities.FromJSON(LServerCaps);
      
      FInitialized := True;
      SetState(csConnected);
      Result := True;
      
      // 发�?initialized 通知
      SendRequest('notifications/initialized', nil);
    finally
      LResponse.Free;
    end;
  except
    on E: Exception do
    begin
      SetState(csError);
      if Assigned(FOnError) then
        FOnError(Self, E.Message);
    end;
  end;
end;

procedure TMCPClient.Disconnect;
begin
  FInitialized := False;
  FCacheValid := False;
  SetState(csDisconnected);
end;

function TMCPClient.Ping: Boolean;
var
  LResponse: TJSONObject;
begin
  Result := False;
  try
    LResponse := SendRequest('ping', nil);
    try
      ParseResponse(LResponse);
      Result := True;
    finally
      LResponse.Free;
    end;
  except
    Result := False;
  end;
end;

function TMCPClient.ListTools(AForceRefresh: Boolean): TArray<TMCPTool>;
var
  LResponse: TJSONObject;
  LResult: TJSONObject;
  LToolsArray: TJSONArray;
  I: Integer;
  LTool: TMCPTool;
begin
  // 使用缓存
  if FCacheValid and not AForceRefresh and (FToolsCache.Count > 0) then
  begin
    SetLength(Result, FToolsCache.Count);
    for I := 0 to FToolsCache.Count - 1 do
      Result[I] := FToolsCache[I];
    Exit;
  end;
  
  LResponse := SendRequest('tools/list', nil);
  try
    LResult := ParseResponse(LResponse) as TJSONObject;
    
    FToolsCache.Clear;
    if LResult.TryGetValue<TJSONArray>('tools', LToolsArray) then
    begin
      SetLength(Result, LToolsArray.Count);
      for I := 0 to LToolsArray.Count - 1 do
      begin
        LTool := TMCPTool.FromJSON(LToolsArray.Items[I] as TJSONObject);
        FToolsCache.Add(LTool);
        Result[I] := LTool;
      end;
    end
    else
      SetLength(Result, 0);
    
    FCacheValid := True;
  finally
    LResponse.Free;
  end;
end;

function TMCPClient.CallTool(const AName: string; const AArguments: TJSONObject): TMCPToolResult;
var
  LParams: TJSONObject;
  LResponse: TJSONObject;
  LResult: TJSONObject;
begin
  LParams := TJSONObject.Create;
  try
    LParams.AddPair('name', AName);
    if Assigned(AArguments) then
      LParams.AddPair('arguments', AArguments.Clone as TJSONObject);
    
    LResponse := SendRequest('tools/call', LParams);
    try
      LResult := ParseResponse(LResponse) as TJSONObject;
      Result := TMCPToolResult.FromJSON(LResult);
    finally
      LResponse.Free;
    end;
  finally
    LParams.Free;
  end;
end;

function TMCPClient.ListResources(AForceRefresh: Boolean): TArray<TMCPResource>;
var
  LResponse: TJSONObject;
  LResult: TJSONObject;
  LArray: TJSONArray;
  I: Integer;
  LRes: TMCPResource;
begin
  // 使用缓存
  if FCacheValid and not AForceRefresh and (FResourcesCache.Count > 0) then
  begin
    SetLength(Result, FResourcesCache.Count);
    for I := 0 to FResourcesCache.Count - 1 do
      Result[I] := FResourcesCache[I];
    Exit;
  end;
  
  LResponse := SendRequest('resources/list', nil);
  try
    LResult := ParseResponse(LResponse) as TJSONObject;
    
    FResourcesCache.Clear;
    if LResult.TryGetValue<TJSONArray>('resources', LArray) then
    begin
      SetLength(Result, LArray.Count);
      for I := 0 to LArray.Count - 1 do
      begin
        LRes := TMCPResource.FromJSON(LArray.Items[I] as TJSONObject);
        FResourcesCache.Add(LRes);
        Result[I] := LRes;
      end;
    end
    else
      SetLength(Result, 0);
  finally
    LResponse.Free;
  end;
end;

function TMCPClient.ReadResource(const AUri: string): TMCPResourceContents;
var
  LParams: TJSONObject;
  LResponse: TJSONObject;
  LResult: TJSONObject;
  LContents: TJSONArray;
begin
  LParams := TJSONObject.Create;
  try
    LParams.AddPair('uri', AUri);
    
    LResponse := SendRequest('resources/read', LParams);
    try
      LResult := ParseResponse(LResponse) as TJSONObject;
      
      if LResult.TryGetValue<TJSONArray>('contents', LContents) and (LContents.Count > 0) then
        Result := TMCPResourceContents.FromJSON(LContents.Items[0] as TJSONObject)
      else
      begin
        Result.Uri := AUri;
        Result.Text := '';
        Result.Blob := '';
        Result.MimeType := '';
      end;
    finally
      LResponse.Free;
    end;
  finally
    LParams.Free;
  end;
end;

function TMCPClient.ListPrompts(AForceRefresh: Boolean): TArray<TMCPPrompt>;
var
  LResponse: TJSONObject;
  LResult: TJSONObject;
  LArray: TJSONArray;
  I: Integer;
  LPrompt: TMCPPrompt;
begin
  // 使用缓存
  if FCacheValid and not AForceRefresh and (FPromptsCache.Count > 0) then
  begin
    SetLength(Result, FPromptsCache.Count);
    for I := 0 to FPromptsCache.Count - 1 do
      Result[I] := FPromptsCache[I];
    Exit;
  end;
  
  LResponse := SendRequest('prompts/list', nil);
  try
    LResult := ParseResponse(LResponse) as TJSONObject;
    
    FPromptsCache.Clear;
    if LResult.TryGetValue<TJSONArray>('prompts', LArray) then
    begin
      SetLength(Result, LArray.Count);
      for I := 0 to LArray.Count - 1 do
      begin
        LPrompt := TMCPPrompt.FromJSON(LArray.Items[I] as TJSONObject);
        FPromptsCache.Add(LPrompt);
        Result[I] := LPrompt;
      end;
    end
    else
      SetLength(Result, 0);
  finally
    LResponse.Free;
  end;
end;

function TMCPClient.GetPrompt(const AName: string; const AArguments: TJSONObject): TGetPromptResult;
var
  LParams: TJSONObject;
  LResponse: TJSONObject;
  LResult: TJSONObject;
  LMessages: TJSONArray;
  I: Integer;
begin
  LParams := TJSONObject.Create;
  try
    LParams.AddPair('name', AName);
    if Assigned(AArguments) then
      LParams.AddPair('arguments', AArguments.Clone as TJSONObject);
    
    LResponse := SendRequest('prompts/get', LParams);
    try
      LResult := ParseResponse(LResponse) as TJSONObject;
      
      Result.Description := LResult.GetValue<string>('description', '');
      
      if LResult.TryGetValue<TJSONArray>('messages', LMessages) then
      begin
        SetLength(Result.Messages, LMessages.Count);
        for I := 0 to LMessages.Count - 1 do
          Result.Messages[I] := TMCPPromptMessage.FromJSON(LMessages.Items[I] as TJSONObject);
      end
      else
        SetLength(Result.Messages, 0);
    finally
      LResponse.Free;
    end;
  finally
    LParams.Free;
  end;
end;

function TMCPClient.FindTool(const AName: string): TMCPTool;
var
  LTools: TArray<TMCPTool>;
  LTool: TMCPTool;
begin
  Result := nil;
  LTools := ListTools;
  for LTool in LTools do
  begin
    if LTool.Name = AName then
    begin
      Result := LTool;
      Exit;
    end;
  end;
end;

function TMCPClient.HasTool(const AName: string): Boolean;
begin
  Result := FindTool(AName) <> nil;
end;

procedure TMCPClient.ClearCache;
begin
  FLock.Enter;
  try
    FToolsCache.Clear;
    FResourcesCache.Clear;
    FPromptsCache.Clear;
    FCacheValid := False;
  finally
    FLock.Leave;
  end;
end;

// ============================================================================
// TMCPClientManager
// ============================================================================

constructor TMCPClientManager.Create;
begin
  inherited Create;
  FClients := TObjectDictionary<string, TMCPClient>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
end;

destructor TMCPClientManager.Destroy;
begin
  FLock.Free;
  FClients.Free;
  inherited;
end;

class function TMCPClientManager.Instance: TMCPClientManager;
begin
  if not Assigned(FInstance) then
    FInstance := TMCPClientManager.Create;
  Result := FInstance;
end;

class procedure TMCPClientManager.FreeInstance;
begin
  FreeAndNil(FInstance);
end;

procedure TMCPClientManager.RegisterServer(const AServerId: string; const AConfig: TMCPClientConfig);
var
  LClient: TMCPClient;
begin
  FLock.Enter;
  try
    if not FClients.ContainsKey(AServerId) then
    begin
      LClient := TMCPClient.Create(AConfig);
      FClients.Add(AServerId, LClient);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMCPClientManager.UnregisterServer(const AServerId: string);
begin
  FLock.Enter;
  try
    FClients.Remove(AServerId);
  finally
    FLock.Leave;
  end;
end;

function TMCPClientManager.GetClient(const AServerId: string): TMCPClient;
begin
  FLock.Enter;
  try
    if not FClients.TryGetValue(AServerId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TMCPClientManager.GetServerIds: TArray<string>;
var
  LKey: string;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FClients.Count);
    I := 0;
    for LKey in FClients.Keys do
    begin
      Result[I] := LKey;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMCPClientManager.ConnectAll;
var
  LClient: TMCPClient;
begin
  FLock.Enter;
  try
    for LClient in FClients.Values do
      LClient.Connect;
  finally
    FLock.Leave;
  end;
end;

procedure TMCPClientManager.DisconnectAll;
var
  LClient: TMCPClient;
begin
  FLock.Enter;
  try
    for LClient in FClients.Values do
      LClient.Disconnect;
  finally
    FLock.Leave;
  end;
end;

end.
