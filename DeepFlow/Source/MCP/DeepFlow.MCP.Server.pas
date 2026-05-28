unit UniFlow.MCP.Server;
(*
  UniFlow MCP Server
  ==================
  TASK-2020: MCP 协议完整支持
  
  实现 MCP Server 端，�?UniFlow 能力暴露给外�?LLM/Agent
  
  功能:
  - JSON-RPC 2.0 消息处理
  - Tool/Resource/Prompt 注册与发�?
  - 请求路由与响�?
  - 会话管理
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.DateUtils,
  UniFlow.MCP.Types;

type
  // ============================================================================
  // MCP Server 配置
  // ============================================================================
  
  TMCPServerConfig = record
    ServerName: string;
    ServerVersion: string;
    Instructions: string;          // 服务器使用说�?
    MaxRequestSize: Integer;       // 最大请求大�?(字节)
    RequestTimeoutMs: Integer;     // 请求超时
    EnableLogging: Boolean;
    
    class function Default: TMCPServerConfig; static;
  end;
  
  // ============================================================================
  // Tool 处理器接�?
  // ============================================================================
  
  IMCPToolHandler = interface
    ['{B1C2D3E4-F5A6-4789-8012-3456789ABCDE}']
    function GetTool: TMCPTool;
    function Execute(const AArguments: TJSONObject): TMCPToolResult;
  end;
  
  // ============================================================================
  // Resource 提供器接�?
  // ============================================================================
  
  IMCPResourceProvider = interface
    ['{C2D3E4F5-A6B7-4890-8123-456789ABCDEF}']
    function GetResources: TArray<TMCPResource>;
    function ReadResource(const AUri: string): TMCPResourceContents;
    function SupportsUri(const AUri: string): Boolean;
  end;
  
  // ============================================================================
  // Prompt 提供器接�?
  // ============================================================================
  
  IMCPPromptProvider = interface
    ['{D3E4F5A6-B7C8-4901-8234-56789ABCDEF0}']
    function GetPrompts: TArray<TMCPPrompt>;
    function GetPrompt(const AName: string; const AArguments: TJSONObject): TGetPromptResult;
    function SupportsPrompt(const AName: string): Boolean;
  end;
  
  // ============================================================================
  // MCP 会话
  // ============================================================================
  
  TMCPSession = class
  private
    FSessionId: string;
    FClientInfo: TMCPImplementation;
    FCapabilities: TMCPClientCapabilities;
    FCreatedAt: TDateTime;
    FLastActivityAt: TDateTime;
    FInitialized: Boolean;
  public
    constructor Create(const ASessionId: string);
    
    procedure UpdateActivity;
    
    property SessionId: string read FSessionId;
    property ClientInfo: TMCPImplementation read FClientInfo write FClientInfo;
    property Capabilities: TMCPClientCapabilities read FCapabilities write FCapabilities;
    property CreatedAt: TDateTime read FCreatedAt;
    property LastActivityAt: TDateTime read FLastActivityAt;
    property Initialized: Boolean read FInitialized write FInitialized;
  end;
  
  // ============================================================================
  // MCP Server
  // ============================================================================
  
  TMCPServer = class
  private
    FConfig: TMCPServerConfig;
    FTools: TDictionary<string, IMCPToolHandler>;
    FResourceProviders: TList<IMCPResourceProvider>;
    FPromptProviders: TList<IMCPPromptProvider>;
    FSessions: TObjectDictionary<string, TMCPSession>;
    FLock: TCriticalSection;
    FRequestId: Int64;
    
    // JSON-RPC 处理
    function CreateResponse(const AId: TJsonRpcId; const AResult: TJSONValue): TJSONObject;
    function CreateErrorResponse(const AId: TJsonRpcId; const AError: TJsonRpcError): TJSONObject;
    function CreateNotification(const AMethod: string; const AParams: TJSONObject): TJSONObject;
    
    // 请求处理
    function HandleInitialize(ASession: TMCPSession; const AParams: TJSONObject): TJSONValue;
    function HandleListTools(const AParams: TJSONObject): TJSONValue;
    function HandleCallTool(const AParams: TJSONObject): TJSONValue;
    function HandleListResources(const AParams: TJSONObject): TJSONValue;
    function HandleReadResource(const AParams: TJSONObject): TJSONValue;
    function HandleListPrompts(const AParams: TJSONObject): TJSONValue;
    function HandleGetPrompt(const AParams: TJSONObject): TJSONValue;
    function HandlePing: TJSONValue;
    
  public
    constructor Create(const AConfig: TMCPServerConfig);
    destructor Destroy; override;
    
    /// <summary>注册 Tool 处理�?/summary>
    procedure RegisterTool(AHandler: IMCPToolHandler);
    
    /// <summary>注销 Tool</summary>
    procedure UnregisterTool(const AName: string);
    
    /// <summary>注册 Resource 提供�?/summary>
    procedure RegisterResourceProvider(AProvider: IMCPResourceProvider);
    
    /// <summary>注册 Prompt 提供�?/summary>
    procedure RegisterPromptProvider(AProvider: IMCPPromptProvider);
    
    /// <summary>处理 JSON-RPC 请求</summary>
    function HandleRequest(const ASessionId: string; const ARequest: TJSONObject): TJSONObject;
    
    /// <summary>处理 JSON-RPC 请求 (字符�?</summary>
    function HandleRequestString(const ASessionId, ARequestJson: string): string;
    
    /// <summary>获取或创建会�?/summary>
    function GetOrCreateSession(const ASessionId: string): TMCPSession;
    
    /// <summary>关闭会话</summary>
    procedure CloseSession(const ASessionId: string);
    
    /// <summary>获取服务器能�?/summary>
    function GetCapabilities: TMCPServerCapabilities;
    
    /// <summary>获取服务器信�?/summary>
    function GetServerInfo: TMCPImplementation;
    
    /// <summary>获取已注册的 Tool 列表</summary>
    function GetTools: TArray<TMCPTool>;
    
    property Config: TMCPServerConfig read FConfig;
  end;
  
  // ============================================================================
  // 简�?Tool 处理器基�?
  // ============================================================================
  
  TMCPToolHandlerBase = class(TInterfacedObject, IMCPToolHandler)
  private
    FTool: TMCPTool;
  protected
    function DoExecute(const AArguments: TJSONObject): TMCPToolResult; virtual; abstract;
  public
    constructor Create(const AName, ADescription: string; AInputSchema: TJSONObject);
    destructor Destroy; override;
    
    function GetTool: TMCPTool;
    function Execute(const AArguments: TJSONObject): TMCPToolResult;
  end;
  
  // ============================================================================
  // Lambda Tool 处理�?
  // ============================================================================
  
  TMCPToolExecuteFunc = reference to function(const AArguments: TJSONObject): TMCPToolResult;
  
  TLambdaToolHandler = class(TMCPToolHandlerBase)
  private
    FExecuteFunc: TMCPToolExecuteFunc;
  protected
    function DoExecute(const AArguments: TJSONObject): TMCPToolResult; override;
  public
    constructor Create(const AName, ADescription: string; 
      AInputSchema: TJSONObject; AExecuteFunc: TMCPToolExecuteFunc);
  end;

implementation

// ============================================================================
// TMCPServerConfig
// ============================================================================

class function TMCPServerConfig.Default: TMCPServerConfig;
begin
  Result.ServerName := 'UniFlow MCP Server';
  Result.ServerVersion := '1.0.0';
  Result.Instructions := 'UniFlow Workflow Engine MCP Server';
  Result.MaxRequestSize := 10 * 1024 * 1024; // 10MB
  Result.RequestTimeoutMs := 30000;
  Result.EnableLogging := True;
end;

// ============================================================================
// TMCPSession
// ============================================================================

constructor TMCPSession.Create(const ASessionId: string);
begin
  inherited Create;
  FSessionId := ASessionId;
  FCreatedAt := Now;
  FLastActivityAt := Now;
  FInitialized := False;
end;

procedure TMCPSession.UpdateActivity;
begin
  FLastActivityAt := Now;
end;

// ============================================================================
// TMCPServer
// ============================================================================

constructor TMCPServer.Create(const AConfig: TMCPServerConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FTools := TDictionary<string, IMCPToolHandler>.Create;
  FResourceProviders := TList<IMCPResourceProvider>.Create;
  FPromptProviders := TList<IMCPPromptProvider>.Create;
  FSessions := TObjectDictionary<string, TMCPSession>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FRequestId := 0;
end;

destructor TMCPServer.Destroy;
begin
  FLock.Free;
  FSessions.Free;
  FPromptProviders.Free;
  FResourceProviders.Free;
  FTools.Free;
  inherited;
end;

procedure TMCPServer.RegisterTool(AHandler: IMCPToolHandler);
var
  LTool: TMCPTool;
begin
  FLock.Enter;
  try
    LTool := AHandler.GetTool;
    FTools.AddOrSetValue(LTool.Name, AHandler);
  finally
    FLock.Leave;
  end;
end;

procedure TMCPServer.UnregisterTool(const AName: string);
begin
  FLock.Enter;
  try
    FTools.Remove(AName);
  finally
    FLock.Leave;
  end;
end;

procedure TMCPServer.RegisterResourceProvider(AProvider: IMCPResourceProvider);
begin
  FLock.Enter;
  try
    FResourceProviders.Add(AProvider);
  finally
    FLock.Leave;
  end;
end;

procedure TMCPServer.RegisterPromptProvider(AProvider: IMCPPromptProvider);
begin
  FLock.Enter;
  try
    FPromptProviders.Add(AProvider);
  finally
    FLock.Leave;
  end;
end;

function TMCPServer.GetOrCreateSession(const ASessionId: string): TMCPSession;
begin
  FLock.Enter;
  try
    if not FSessions.TryGetValue(ASessionId, Result) then
    begin
      Result := TMCPSession.Create(ASessionId);
      FSessions.Add(ASessionId, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMCPServer.CloseSession(const ASessionId: string);
begin
  FLock.Enter;
  try
    FSessions.Remove(ASessionId);
  finally
    FLock.Leave;
  end;
end;

function TMCPServer.GetCapabilities: TMCPServerCapabilities;
begin
  Result.Experimental := nil;
  Result.Logging := nil;
  Result.Prompts.ListChanged := True;
  Result.Resources.Subscribe := False;
  Result.Resources.ListChanged := True;
  Result.Tools.ListChanged := True;
end;

function TMCPServer.GetServerInfo: TMCPImplementation;
begin
  Result.Name := FConfig.ServerName;
  Result.Version := FConfig.ServerVersion;
end;

function TMCPServer.GetTools: TArray<TMCPTool>;
var
  LHandler: IMCPToolHandler;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FTools.Count);
    I := 0;
    for LHandler in FTools.Values do
    begin
      Result[I] := LHandler.GetTool;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

function TMCPServer.CreateResponse(const AId: TJsonRpcId; const AResult: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', AId.ToJSON);
  Result.AddPair('result', AResult);
end;

function TMCPServer.CreateErrorResponse(const AId: TJsonRpcId; const AError: TJsonRpcError): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('id', AId.ToJSON);
  Result.AddPair('error', AError.ToJSON);
end;

function TMCPServer.CreateNotification(const AMethod: string; const AParams: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('method', AMethod);
  if Assigned(AParams) then
    Result.AddPair('params', AParams);
end;

function TMCPServer.HandleRequest(const ASessionId: string; const ARequest: TJSONObject): TJSONObject;
var
  LMethod: string;
  LId: TJsonRpcId;
  LIdValue: TJSONValue;
  LParams: TJSONObject;
  LSession: TMCPSession;
  LResult: TJSONValue;
  LError: TJsonRpcError;
begin
  Result := nil;
  
  // 获取会话
  LSession := GetOrCreateSession(ASessionId);
  LSession.UpdateActivity;
  
  // 解析请求
  if not ARequest.TryGetValue<string>('method', LMethod) then
  begin
    LError.Code := TJsonRpcErrorCode.InvalidRequest;
    LError.Message := 'Missing method';
    LError.Data := nil;
    Result := CreateErrorResponse(TJsonRpcId.FromNumber(0), LError);
    Exit;
  end;
  
  // 获取 ID (可选，通知没有 ID)
  if ARequest.TryGetValue<TJSONValue>('id', LIdValue) then
    LId := TJsonRpcId.FromJSON(LIdValue)
  else
  begin
    // 这是一个通知，不需要响�?
    Exit;
  end;
  
  // 获取参数
  if not ARequest.TryGetValue<TJSONObject>('params', LParams) then
    LParams := nil;
  
  try
    // 路由请求
    if LMethod = 'initialize' then
      LResult := HandleInitialize(LSession, LParams)
    else if LMethod = 'ping' then
      LResult := HandlePing
    else if LMethod = 'tools/list' then
      LResult := HandleListTools(LParams)
    else if LMethod = 'tools/call' then
      LResult := HandleCallTool(LParams)
    else if LMethod = 'resources/list' then
      LResult := HandleListResources(LParams)
    else if LMethod = 'resources/read' then
      LResult := HandleReadResource(LParams)
    else if LMethod = 'prompts/list' then
      LResult := HandleListPrompts(LParams)
    else if LMethod = 'prompts/get' then
      LResult := HandleGetPrompt(LParams)
    else
    begin
      LError.Code := TJsonRpcErrorCode.MethodNotFound;
      LError.Message := 'Method not found: ' + LMethod;
      LError.Data := nil;
      Result := CreateErrorResponse(LId, LError);
      Exit;
    end;
    
    Result := CreateResponse(LId, LResult);
  except
    on E: Exception do
    begin
      LError.Code := TJsonRpcErrorCode.InternalError;
      LError.Message := E.Message;
      LError.Data := nil;
      Result := CreateErrorResponse(LId, LError);
    end;
  end;
end;

function TMCPServer.HandleRequestString(const ASessionId, ARequestJson: string): string;
var
  LRequest, LResponse: TJSONObject;
begin
  LRequest := TJSONObject.ParseJSONValue(ARequestJson) as TJSONObject;
  try
    LResponse := HandleRequest(ASessionId, LRequest);
    try
      if Assigned(LResponse) then
        Result := LResponse.ToJSON
      else
        Result := '';
    finally
      LResponse.Free;
    end;
  finally
    LRequest.Free;
  end;
end;

function TMCPServer.HandleInitialize(ASession: TMCPSession; const AParams: TJSONObject): TJSONValue;
var
  LRequest: TInitializeRequest;
  LResult: TInitializeResult;
begin
  LRequest := TInitializeRequest.FromJSON(AParams);
  
  // 保存客户端信�?
  ASession.ClientInfo := LRequest.ClientInfo;
  ASession.Capabilities := LRequest.Capabilities;
  ASession.Initialized := True;
  
  // 构建响应
  LResult.ProtocolVersion := TMCPProtocolVersion.CURRENT;
  LResult.Capabilities := GetCapabilities;
  LResult.ServerInfo := GetServerInfo;
  LResult.Instructions := FConfig.Instructions;
  
  Result := LResult.ToJSON;
end;

function TMCPServer.HandlePing: TJSONValue;
begin
  Result := TJSONObject.Create;
end;

function TMCPServer.HandleListTools(const AParams: TJSONObject): TJSONValue;
var
  LResult: TListToolsResult;
  LHandler: IMCPToolHandler;
begin
  LResult.Tools := TObjectList<TMCPTool>.Create(False);
  try
    FLock.Enter;
    try
      for LHandler in FTools.Values do
        LResult.Tools.Add(LHandler.GetTool);
    finally
      FLock.Leave;
    end;
    
    LResult.NextCursor := '';
    Result := LResult.ToJSON;
  finally
    LResult.Tools.Free;
  end;
end;

function TMCPServer.HandleCallTool(const AParams: TJSONObject): TJSONValue;
var
  LRequest: TCallToolRequest;
  LHandler: IMCPToolHandler;
  LToolResult: TMCPToolResult;
  LError: TJsonRpcError;
begin
  LRequest := TCallToolRequest.FromJSON(AParams);
  
  FLock.Enter;
  try
    if not FTools.TryGetValue(LRequest.Name, LHandler) then
    begin
      // Tool 不存�?
      SetLength(LToolResult.Content, 1);
      LToolResult.Content[0] := TMCPTextContent.Create('Tool not found: ' + LRequest.Name).ToJSON;
      LToolResult.IsError := True;
      Result := LToolResult.ToJSON;
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  
  // 执行 Tool
  try
    LToolResult := LHandler.Execute(LRequest.Arguments);
    Result := LToolResult.ToJSON;
  except
    on E: Exception do
    begin
      SetLength(LToolResult.Content, 1);
      LToolResult.Content[0] := TMCPTextContent.Create('Tool execution failed: ' + E.Message).ToJSON;
      LToolResult.IsError := True;
      Result := LToolResult.ToJSON;
    end;
  end;
end;

function TMCPServer.HandleListResources(const AParams: TJSONObject): TJSONValue;
var
  LResult: TListResourcesResult;
  LProvider: IMCPResourceProvider;
  LResources: TArray<TMCPResource>;
  LRes: TMCPResource;
begin
  LResult.Resources := TObjectList<TMCPResource>.Create(False);
  try
    FLock.Enter;
    try
      for LProvider in FResourceProviders do
      begin
        LResources := LProvider.GetResources;
        for LRes in LResources do
          LResult.Resources.Add(LRes);
      end;
    finally
      FLock.Leave;
    end;
    
    LResult.NextCursor := '';
    Result := LResult.ToJSON;
  finally
    LResult.Resources.Free;
  end;
end;

function TMCPServer.HandleReadResource(const AParams: TJSONObject): TJSONValue;
var
  LRequest: TReadResourceRequest;
  LProvider: IMCPResourceProvider;
  LContents: TMCPResourceContents;
  LResult: TReadResourceResult;
  LFound: Boolean;
begin
  LRequest := TReadResourceRequest.FromJSON(AParams);
  LFound := False;
  
  FLock.Enter;
  try
    for LProvider in FResourceProviders do
    begin
      if LProvider.SupportsUri(LRequest.Uri) then
      begin
        LContents := LProvider.ReadResource(LRequest.Uri);
        LFound := True;
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
  
  if LFound then
  begin
    SetLength(LResult.Contents, 1);
    LResult.Contents[0] := LContents;
  end
  else
  begin
    SetLength(LResult.Contents, 0);
  end;
  
  Result := LResult.ToJSON;
end;

function TMCPServer.HandleListPrompts(const AParams: TJSONObject): TJSONValue;
var
  LResult: TListPromptsResult;
  LProvider: IMCPPromptProvider;
  LPrompts: TArray<TMCPPrompt>;
  LPrompt: TMCPPrompt;
begin
  LResult.Prompts := TObjectList<TMCPPrompt>.Create(False);
  try
    FLock.Enter;
    try
      for LProvider in FPromptProviders do
      begin
        LPrompts := LProvider.GetPrompts;
        for LPrompt in LPrompts do
          LResult.Prompts.Add(LPrompt);
      end;
    finally
      FLock.Leave;
    end;
    
    LResult.NextCursor := '';
    Result := LResult.ToJSON;
  finally
    LResult.Prompts.Free;
  end;
end;

function TMCPServer.HandleGetPrompt(const AParams: TJSONObject): TJSONValue;
var
  LRequest: TGetPromptRequest;
  LProvider: IMCPPromptProvider;
  LPromptResult: TGetPromptResult;
  LFound: Boolean;
begin
  LRequest := TGetPromptRequest.FromJSON(AParams);
  LFound := False;
  
  FLock.Enter;
  try
    for LProvider in FPromptProviders do
    begin
      if LProvider.SupportsPrompt(LRequest.Name) then
      begin
        LPromptResult := LProvider.GetPrompt(LRequest.Name, LRequest.Arguments);
        LFound := True;
        Break;
      end;
    end;
  finally
    FLock.Leave;
  end;
  
  if LFound then
    Result := LPromptResult.ToJSON
  else
  begin
    LPromptResult.Description := 'Prompt not found: ' + LRequest.Name;
    SetLength(LPromptResult.Messages, 0);
    Result := LPromptResult.ToJSON;
  end;
end;

// ============================================================================
// TMCPToolHandlerBase
// ============================================================================

constructor TMCPToolHandlerBase.Create(const AName, ADescription: string; AInputSchema: TJSONObject);
begin
  inherited Create;
  FTool := TMCPTool.Create;
  FTool.Name := AName;
  FTool.Description := ADescription;
  FTool.InputSchema := AInputSchema;
end;

destructor TMCPToolHandlerBase.Destroy;
begin
  FTool.Free;
  inherited;
end;

function TMCPToolHandlerBase.GetTool: TMCPTool;
begin
  Result := FTool;
end;

function TMCPToolHandlerBase.Execute(const AArguments: TJSONObject): TMCPToolResult;
begin
  Result := DoExecute(AArguments);
end;

// ============================================================================
// TLambdaToolHandler
// ============================================================================

constructor TLambdaToolHandler.Create(const AName, ADescription: string;
  AInputSchema: TJSONObject; AExecuteFunc: TMCPToolExecuteFunc);
begin
  inherited Create(AName, ADescription, AInputSchema);
  FExecuteFunc := AExecuteFunc;
end;

function TLambdaToolHandler.DoExecute(const AArguments: TJSONObject): TMCPToolResult;
begin
  if Assigned(FExecuteFunc) then
    Result := FExecuteFunc(AArguments)
  else
  begin
    SetLength(Result.Content, 1);
    Result.Content[0] := TMCPTextContent.Create('No execute function defined').ToJSON;
    Result.IsError := True;
  end;
end;

end.
