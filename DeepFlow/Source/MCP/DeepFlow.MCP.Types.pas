unit UniFlow.MCP.Types;
(*
  UniFlow MCP Types
  =================
  TASK-2020: MCP 协议完整支持
  
  基于 Model Context Protocol Specification 2024-11-05
  
  核心概念:
  - Tools: 可调用的函数/工具
  - Resources: 可访问的资源 (文件/数据)
  - Prompts: 预定义的提示模板
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections;

type
  // ============================================================================
  // MCP 协议版本
  // ============================================================================
  
  TMCPProtocolVersion = record
    const CURRENT = '2024-11-05';
    const SUPPORTED: array[0..1] of string = ('2024-11-05', '2024-10-07');
  end;
  
  // ============================================================================
  // JSON-RPC 基础类型
  // ============================================================================
  
  TJsonRpcId = record
    IsNumber: Boolean;
    NumberValue: Int64;
    StringValue: string;
    
    class function FromNumber(AValue: Int64): TJsonRpcId; static;
    class function FromString(const AValue: string): TJsonRpcId; static;
    function ToJSON: TJSONValue;
    class function FromJSON(AValue: TJSONValue): TJsonRpcId; static;
  end;
  
  TJsonRpcError = record
    Code: Integer;
    Message: string;
    Data: TJSONValue;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TJsonRpcError; static;
  end;
  
  // JSON-RPC 错误�?
  TJsonRpcErrorCode = class
  public
    const ParseError = -32700;
    const InvalidRequest = -32600;
    const MethodNotFound = -32601;
    const InvalidParams = -32602;
    const InternalError = -32603;
    // MCP 扩展错误�?
    const MCPToolNotFound = -32001;
    const MCPResourceNotFound = -32002;
    const MCPPromptNotFound = -32003;
    const MCPAuthFailed = -32010;
    const MCPRateLimited = -32011;
  end;
  
  // ============================================================================
  // MCP Server/Client 信息
  // ============================================================================
  
  TMCPImplementation = record
    Name: string;
    Version: string;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPImplementation; static;
  end;
  
  TMCPClientCapabilities = record
    Experimental: TJSONObject;
    Roots: record
      ListChanged: Boolean;
    end;
    Sampling: TJSONObject;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPClientCapabilities; static;
  end;
  
  TMCPServerCapabilities = record
    Experimental: TJSONObject;
    Logging: TJSONObject;
    Prompts: record
      ListChanged: Boolean;
    end;
    Resources: record
      Subscribe: Boolean;
      ListChanged: Boolean;
    end;
    Tools: record
      ListChanged: Boolean;
    end;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPServerCapabilities; static;
  end;
  
  // ============================================================================
  // MCP Tool 定义
  // ============================================================================
  
  TMCPTool = class
  private
    FName: string;
    FDescription: string;
    FInputSchema: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPTool; static;
    function Clone: TMCPTool;
    
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property InputSchema: TJSONObject read FInputSchema write FInputSchema;
  end;
  
  TMCPToolCall = record
    Name: string;
    Arguments: TJSONObject;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPToolCall; static;
  end;
  
  TMCPToolResult = record
    Content: TArray<TJSONObject>;  // TextContent/ImageContent/EmbeddedResource
    IsError: Boolean;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPToolResult; static;
  end;
  
  // ============================================================================
  // MCP Resource 定义
  // ============================================================================
  
  TMCPResource = class
  private
    FUri: string;
    FName: string;
    FDescription: string;
    FMimeType: string;
  public
    constructor Create;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPResource; static;
    function Clone: TMCPResource;
    
    property Uri: string read FUri write FUri;
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property MimeType: string read FMimeType write FMimeType;
  end;
  
  TMCPResourceTemplate = class
  private
    FUriTemplate: string;
    FName: string;
    FDescription: string;
    FMimeType: string;
  public
    constructor Create;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPResourceTemplate; static;
    
    property UriTemplate: string read FUriTemplate write FUriTemplate;
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property MimeType: string read FMimeType write FMimeType;
  end;
  
  TMCPResourceContents = record
    Uri: string;
    MimeType: string;
    Text: string;          // 文本内容
    Blob: string;          // Base64 二进�?
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPResourceContents; static;
  end;
  
  // ============================================================================
  // MCP Prompt 定义
  // ============================================================================
  
  TMCPPromptArgument = record
    Name: string;
    Description: string;
    Required: Boolean;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPPromptArgument; static;
  end;
  
  TMCPPrompt = class
  private
    FName: string;
    FDescription: string;
    FArguments: TList<TMCPPromptArgument>;
  public
    constructor Create;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPPrompt; static;
    function Clone: TMCPPrompt;
    
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Arguments: TList<TMCPPromptArgument> read FArguments;
  end;
  
  // Prompt 消息角色
  TMCPRole = (mrUser, mrAssistant);
  
  TMCPPromptMessage = record
    Role: TMCPRole;
    Content: TJSONValue;  // TextContent/ImageContent/EmbeddedResource
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TMCPPromptMessage; static;
  end;
  
  // ============================================================================
  // MCP Content 类型
  // ============================================================================
  
  TMCPTextContent = record
    ContentType: string;  // 'text'
    Text: string;
    
    class function Create(const AText: string): TMCPTextContent; static;
    function ToJSON: TJSONObject;
  end;
  
  TMCPImageContent = record
    ContentType: string;  // 'image'
    Data: string;         // Base64
    MimeType: string;
    
    class function Create(const AData, AMimeType: string): TMCPImageContent; static;
    function ToJSON: TJSONObject;
  end;
  
  TMCPEmbeddedResource = record
    ContentType: string;  // 'resource'
    Resource: TMCPResourceContents;
    
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // MCP 请求/响应消息
  // ============================================================================
  
  // Initialize
  TInitializeRequest = record
    ProtocolVersion: string;
    Capabilities: TMCPClientCapabilities;
    ClientInfo: TMCPImplementation;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TInitializeRequest; static;
  end;
  
  TInitializeResult = record
    ProtocolVersion: string;
    Capabilities: TMCPServerCapabilities;
    ServerInfo: TMCPImplementation;
    Instructions: string;
    
    function ToJSON: TJSONObject;
  end;
  
  // Tools
  TListToolsRequest = record
    Cursor: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TListToolsResult = record
    Tools: TObjectList<TMCPTool>;
    NextCursor: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TCallToolRequest = record
    Name: string;
    Arguments: TJSONObject;
    
    class function FromJSON(AJson: TJSONObject): TCallToolRequest; static;
  end;
  
  // Resources
  TListResourcesRequest = record
    Cursor: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TListResourcesResult = record
    Resources: TObjectList<TMCPResource>;
    NextCursor: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TReadResourceRequest = record
    Uri: string;
    
    class function FromJSON(AJson: TJSONObject): TReadResourceRequest; static;
  end;
  
  TReadResourceResult = record
    Contents: TArray<TMCPResourceContents>;
    
    function ToJSON: TJSONObject;
  end;
  
  // Prompts
  TListPromptsRequest = record
    Cursor: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TListPromptsResult = record
    Prompts: TObjectList<TMCPPrompt>;
    NextCursor: string;
    
    function ToJSON: TJSONObject;
  end;
  
  TGetPromptRequest = record
    Name: string;
    Arguments: TJSONObject;
    
    class function FromJSON(AJson: TJSONObject): TGetPromptRequest; static;
  end;
  
  TGetPromptResult = record
    Description: string;
    Messages: TArray<TMCPPromptMessage>;
    
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // MCP 通知
  // ============================================================================
  
  TMCPNotificationType = (
    ntInitialized,
    ntProgress,
    ntToolsListChanged,
    ntResourcesListChanged,
    ntPromptsListChanged,
    ntResourceUpdated,
    ntCancelled
  );
  
  TMCPProgressNotification = record
    ProgressToken: string;
    Progress: Double;
    Total: Double;
    
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
function MCPRoleToString(ARole: TMCPRole): string;
function StringToMCPRole(const AStr: string): TMCPRole;
function MCPNotificationTypeToMethod(AType: TMCPNotificationType): string;

implementation

// ============================================================================
// TJsonRpcId
// ============================================================================

class function TJsonRpcId.FromNumber(AValue: Int64): TJsonRpcId;
begin
  Result.IsNumber := True;
  Result.NumberValue := AValue;
  Result.StringValue := '';
end;

class function TJsonRpcId.FromString(const AValue: string): TJsonRpcId;
begin
  Result.IsNumber := False;
  Result.NumberValue := 0;
  Result.StringValue := AValue;
end;

function TJsonRpcId.ToJSON: TJSONValue;
begin
  if IsNumber then
    Result := TJSONNumber.Create(NumberValue)
  else
    Result := TJSONString.Create(StringValue);
end;

class function TJsonRpcId.FromJSON(AValue: TJSONValue): TJsonRpcId;
begin
  if AValue is TJSONNumber then
    Result := FromNumber(TJSONNumber(AValue).AsInt64)
  else
    Result := FromString(AValue.Value);
end;

// ============================================================================
// TJsonRpcError
// ============================================================================

function TJsonRpcError.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('code', TJSONNumber.Create(Code));
  Result.AddPair('message', Message);
  if Assigned(Data) then
    Result.AddPair('data', Data.Clone as TJSONValue);
end;

class function TJsonRpcError.FromJSON(AJson: TJSONObject): TJsonRpcError;
begin
  Result.Code := AJson.GetValue<Integer>('code', 0);
  Result.Message := AJson.GetValue<string>('message', '');
  if AJson.TryGetValue<TJSONValue>('data', Result.Data) then
    Result.Data := Result.Data.Clone as TJSONValue
  else
    Result.Data := nil;
end;

// ============================================================================
// TMCPImplementation
// ============================================================================

function TMCPImplementation.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('version', Version);
end;

class function TMCPImplementation.FromJSON(AJson: TJSONObject): TMCPImplementation;
begin
  Result.Name := AJson.GetValue<string>('name', '');
  Result.Version := AJson.GetValue<string>('version', '');
end;

// ============================================================================
// TMCPClientCapabilities
// ============================================================================

function TMCPClientCapabilities.ToJSON: TJSONObject;
var
  LRoots: TJSONObject;
begin
  Result := TJSONObject.Create;
  
  if Assigned(Experimental) then
    Result.AddPair('experimental', Experimental.Clone as TJSONObject);
  
  if Roots.ListChanged then
  begin
    LRoots := TJSONObject.Create;
    LRoots.AddPair('listChanged', TJSONBool.Create(True));
    Result.AddPair('roots', LRoots);
  end;
  
  if Assigned(Sampling) then
    Result.AddPair('sampling', Sampling.Clone as TJSONObject);
end;

class function TMCPClientCapabilities.FromJSON(AJson: TJSONObject): TMCPClientCapabilities;
var
  LRoots: TJSONObject;
begin
  Result.Experimental := nil;
  Result.Roots.ListChanged := False;
  Result.Sampling := nil;
  
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<TJSONObject>('experimental', Result.Experimental) then
    Result.Experimental := Result.Experimental.Clone as TJSONObject;
  
  if AJson.TryGetValue<TJSONObject>('roots', LRoots) then
    Result.Roots.ListChanged := LRoots.GetValue<Boolean>('listChanged', False);
  
  if AJson.TryGetValue<TJSONObject>('sampling', Result.Sampling) then
    Result.Sampling := Result.Sampling.Clone as TJSONObject;
end;

// ============================================================================
// TMCPServerCapabilities
// ============================================================================

function TMCPServerCapabilities.ToJSON: TJSONObject;
var
  LPrompts, LResources, LTools: TJSONObject;
begin
  Result := TJSONObject.Create;
  
  if Assigned(Experimental) then
    Result.AddPair('experimental', Experimental.Clone as TJSONObject);
  
  if Assigned(Logging) then
    Result.AddPair('logging', Logging.Clone as TJSONObject);
  
  // Prompts
  LPrompts := TJSONObject.Create;
  if Prompts.ListChanged then
    LPrompts.AddPair('listChanged', TJSONBool.Create(True));
  Result.AddPair('prompts', LPrompts);
  
  // Resources
  LResources := TJSONObject.Create;
  if Resources.Subscribe then
    LResources.AddPair('subscribe', TJSONBool.Create(True));
  if Resources.ListChanged then
    LResources.AddPair('listChanged', TJSONBool.Create(True));
  Result.AddPair('resources', LResources);
  
  // Tools
  LTools := TJSONObject.Create;
  if Tools.ListChanged then
    LTools.AddPair('listChanged', TJSONBool.Create(True));
  Result.AddPair('tools', LTools);
end;

class function TMCPServerCapabilities.FromJSON(AJson: TJSONObject): TMCPServerCapabilities;
var
  LPrompts, LResources, LTools: TJSONObject;
begin
  Result.Experimental := nil;
  Result.Logging := nil;
  Result.Prompts.ListChanged := False;
  Result.Resources.Subscribe := False;
  Result.Resources.ListChanged := False;
  Result.Tools.ListChanged := False;
  
  if AJson = nil then Exit;
  
  if AJson.TryGetValue<TJSONObject>('prompts', LPrompts) then
    Result.Prompts.ListChanged := LPrompts.GetValue<Boolean>('listChanged', False);
  
  if AJson.TryGetValue<TJSONObject>('resources', LResources) then
  begin
    Result.Resources.Subscribe := LResources.GetValue<Boolean>('subscribe', False);
    Result.Resources.ListChanged := LResources.GetValue<Boolean>('listChanged', False);
  end;
  
  if AJson.TryGetValue<TJSONObject>('tools', LTools) then
    Result.Tools.ListChanged := LTools.GetValue<Boolean>('listChanged', False);
end;

// ============================================================================
// TMCPTool
// ============================================================================

constructor TMCPTool.Create;
begin
  inherited Create;
end;

destructor TMCPTool.Destroy;
begin
  FInputSchema.Free;
  inherited;
end;

function TMCPTool.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  if not FDescription.IsEmpty then
    Result.AddPair('description', FDescription);
  if Assigned(FInputSchema) then
    Result.AddPair('inputSchema', FInputSchema.Clone as TJSONObject);
end;

class function TMCPTool.FromJSON(AJson: TJSONObject): TMCPTool;
begin
  Result := TMCPTool.Create;
  Result.FName := AJson.GetValue<string>('name', '');
  Result.FDescription := AJson.GetValue<string>('description', '');
  if AJson.TryGetValue<TJSONObject>('inputSchema', Result.FInputSchema) then
    Result.FInputSchema := Result.FInputSchema.Clone as TJSONObject;
end;

function TMCPTool.Clone: TMCPTool;
begin
  Result := TMCPTool.Create;
  Result.FName := FName;
  Result.FDescription := FDescription;
  if Assigned(FInputSchema) then
    Result.FInputSchema := FInputSchema.Clone as TJSONObject;
end;

// ============================================================================
// TMCPToolCall
// ============================================================================

function TMCPToolCall.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  if Assigned(Arguments) then
    Result.AddPair('arguments', Arguments.Clone as TJSONObject);
end;

class function TMCPToolCall.FromJSON(AJson: TJSONObject): TMCPToolCall;
begin
  Result.Name := AJson.GetValue<string>('name', '');
  if AJson.TryGetValue<TJSONObject>('arguments', Result.Arguments) then
    Result.Arguments := Result.Arguments.Clone as TJSONObject
  else
    Result.Arguments := nil;
end;

// ============================================================================
// TMCPToolResult
// ============================================================================

function TMCPToolResult.ToJSON: TJSONObject;
var
  LContent: TJSONArray;
  LItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  
  LContent := TJSONArray.Create;
  for LItem in Content do
    LContent.Add(LItem.Clone as TJSONObject);
  Result.AddPair('content', LContent);
  
  if IsError then
    Result.AddPair('isError', TJSONBool.Create(True));
end;

class function TMCPToolResult.FromJSON(AJson: TJSONObject): TMCPToolResult;
var
  LContent: TJSONArray;
  I: Integer;
begin
  Result.IsError := AJson.GetValue<Boolean>('isError', False);
  
  if AJson.TryGetValue<TJSONArray>('content', LContent) then
  begin
    SetLength(Result.Content, LContent.Count);
    for I := 0 to LContent.Count - 1 do
      Result.Content[I] := LContent.Items[I].Clone as TJSONObject;
  end
  else
    SetLength(Result.Content, 0);
end;

// ============================================================================
// TMCPResource
// ============================================================================

constructor TMCPResource.Create;
begin
  inherited Create;
end;

function TMCPResource.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', FUri);
  Result.AddPair('name', FName);
  if not FDescription.IsEmpty then
    Result.AddPair('description', FDescription);
  if not FMimeType.IsEmpty then
    Result.AddPair('mimeType', FMimeType);
end;

class function TMCPResource.FromJSON(AJson: TJSONObject): TMCPResource;
begin
  Result := TMCPResource.Create;
  Result.FUri := AJson.GetValue<string>('uri', '');
  Result.FName := AJson.GetValue<string>('name', '');
  Result.FDescription := AJson.GetValue<string>('description', '');
  Result.FMimeType := AJson.GetValue<string>('mimeType', '');
end;

function TMCPResource.Clone: TMCPResource;
begin
  Result := TMCPResource.Create;
  Result.FUri := FUri;
  Result.FName := FName;
  Result.FDescription := FDescription;
  Result.FMimeType := FMimeType;
end;

// ============================================================================
// TMCPResourceTemplate
// ============================================================================

constructor TMCPResourceTemplate.Create;
begin
  inherited Create;
end;

function TMCPResourceTemplate.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uriTemplate', FUriTemplate);
  Result.AddPair('name', FName);
  if not FDescription.IsEmpty then
    Result.AddPair('description', FDescription);
  if not FMimeType.IsEmpty then
    Result.AddPair('mimeType', FMimeType);
end;

class function TMCPResourceTemplate.FromJSON(AJson: TJSONObject): TMCPResourceTemplate;
begin
  Result := TMCPResourceTemplate.Create;
  Result.FUriTemplate := AJson.GetValue<string>('uriTemplate', '');
  Result.FName := AJson.GetValue<string>('name', '');
  Result.FDescription := AJson.GetValue<string>('description', '');
  Result.FMimeType := AJson.GetValue<string>('mimeType', '');
end;

// ============================================================================
// TMCPResourceContents
// ============================================================================

function TMCPResourceContents.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', Uri);
  if not MimeType.IsEmpty then
    Result.AddPair('mimeType', MimeType);
  if not Text.IsEmpty then
    Result.AddPair('text', Text)
  else if not Blob.IsEmpty then
    Result.AddPair('blob', Blob);
end;

class function TMCPResourceContents.FromJSON(AJson: TJSONObject): TMCPResourceContents;
begin
  Result.Uri := AJson.GetValue<string>('uri', '');
  Result.MimeType := AJson.GetValue<string>('mimeType', '');
  Result.Text := AJson.GetValue<string>('text', '');
  Result.Blob := AJson.GetValue<string>('blob', '');
end;

// ============================================================================
// TMCPPromptArgument
// ============================================================================

function TMCPPromptArgument.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  if not Description.IsEmpty then
    Result.AddPair('description', Description);
  if Required then
    Result.AddPair('required', TJSONBool.Create(True));
end;

class function TMCPPromptArgument.FromJSON(AJson: TJSONObject): TMCPPromptArgument;
begin
  Result.Name := AJson.GetValue<string>('name', '');
  Result.Description := AJson.GetValue<string>('description', '');
  Result.Required := AJson.GetValue<Boolean>('required', False);
end;

// ============================================================================
// TMCPPrompt
// ============================================================================

constructor TMCPPrompt.Create;
begin
  inherited Create;
  FArguments := TList<TMCPPromptArgument>.Create;
end;

destructor TMCPPrompt.Destroy;
begin
  FArguments.Free;
  inherited;
end;

function TMCPPrompt.ToJSON: TJSONObject;
var
  LArgsArray: TJSONArray;
  LArg: TMCPPromptArgument;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  if not FDescription.IsEmpty then
    Result.AddPair('description', FDescription);
  
  if FArguments.Count > 0 then
  begin
    LArgsArray := TJSONArray.Create;
    for LArg in FArguments do
      LArgsArray.Add(LArg.ToJSON);
    Result.AddPair('arguments', LArgsArray);
  end;
end;

class function TMCPPrompt.FromJSON(AJson: TJSONObject): TMCPPrompt;
var
  LArgsArray: TJSONArray;
  I: Integer;
begin
  Result := TMCPPrompt.Create;
  Result.FName := AJson.GetValue<string>('name', '');
  Result.FDescription := AJson.GetValue<string>('description', '');
  
  if AJson.TryGetValue<TJSONArray>('arguments', LArgsArray) then
  begin
    for I := 0 to LArgsArray.Count - 1 do
      Result.FArguments.Add(TMCPPromptArgument.FromJSON(LArgsArray.Items[I] as TJSONObject));
  end;
end;

function TMCPPrompt.Clone: TMCPPrompt;
var
  LArg: TMCPPromptArgument;
begin
  Result := TMCPPrompt.Create;
  Result.FName := FName;
  Result.FDescription := FDescription;
  for LArg in FArguments do
    Result.FArguments.Add(LArg);
end;

// ============================================================================
// TMCPPromptMessage
// ============================================================================

function TMCPPromptMessage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('role', MCPRoleToString(Role));
  if Assigned(Content) then
    Result.AddPair('content', Content.Clone as TJSONValue);
end;

class function TMCPPromptMessage.FromJSON(AJson: TJSONObject): TMCPPromptMessage;
begin
  Result.Role := StringToMCPRole(AJson.GetValue<string>('role', 'user'));
  if AJson.TryGetValue<TJSONValue>('content', Result.Content) then
    Result.Content := Result.Content.Clone as TJSONValue
  else
    Result.Content := nil;
end;

// ============================================================================
// TMCPTextContent
// ============================================================================

class function TMCPTextContent.Create(const AText: string): TMCPTextContent;
begin
  Result.ContentType := 'text';
  Result.Text := AText;
end;

function TMCPTextContent.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'text');
  Result.AddPair('text', Text);
end;

// ============================================================================
// TMCPImageContent
// ============================================================================

class function TMCPImageContent.Create(const AData, AMimeType: string): TMCPImageContent;
begin
  Result.ContentType := 'image';
  Result.Data := AData;
  Result.MimeType := AMimeType;
end;

function TMCPImageContent.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'image');
  Result.AddPair('data', Data);
  Result.AddPair('mimeType', MimeType);
end;

// ============================================================================
// TMCPEmbeddedResource
// ============================================================================

function TMCPEmbeddedResource.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'resource');
  Result.AddPair('resource', Resource.ToJSON);
end;

// ============================================================================
// TInitializeRequest
// ============================================================================

function TInitializeRequest.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', ProtocolVersion);
  Result.AddPair('capabilities', Capabilities.ToJSON);
  Result.AddPair('clientInfo', ClientInfo.ToJSON);
end;

class function TInitializeRequest.FromJSON(AJson: TJSONObject): TInitializeRequest;
var
  LCaps, LInfo: TJSONObject;
begin
  Result.ProtocolVersion := AJson.GetValue<string>('protocolVersion', '');
  if AJson.TryGetValue<TJSONObject>('capabilities', LCaps) then
    Result.Capabilities := TMCPClientCapabilities.FromJSON(LCaps);
  if AJson.TryGetValue<TJSONObject>('clientInfo', LInfo) then
    Result.ClientInfo := TMCPImplementation.FromJSON(LInfo);
end;

// ============================================================================
// TInitializeResult
// ============================================================================

function TInitializeResult.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', ProtocolVersion);
  Result.AddPair('capabilities', Capabilities.ToJSON);
  Result.AddPair('serverInfo', ServerInfo.ToJSON);
  if not Instructions.IsEmpty then
    Result.AddPair('instructions', Instructions);
end;

// ============================================================================
// TListToolsRequest / TListToolsResult
// ============================================================================

function TListToolsRequest.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if not Cursor.IsEmpty then
    Result.AddPair('cursor', Cursor);
end;

function TListToolsResult.ToJSON: TJSONObject;
var
  LToolsArray: TJSONArray;
  LTool: TMCPTool;
begin
  Result := TJSONObject.Create;
  
  LToolsArray := TJSONArray.Create;
  if Assigned(Tools) then
    for LTool in Tools do
      LToolsArray.Add(LTool.ToJSON);
  Result.AddPair('tools', LToolsArray);
  
  if not NextCursor.IsEmpty then
    Result.AddPair('nextCursor', NextCursor);
end;

// ============================================================================
// TCallToolRequest
// ============================================================================

class function TCallToolRequest.FromJSON(AJson: TJSONObject): TCallToolRequest;
begin
  Result.Name := AJson.GetValue<string>('name', '');
  if AJson.TryGetValue<TJSONObject>('arguments', Result.Arguments) then
    Result.Arguments := Result.Arguments.Clone as TJSONObject
  else
    Result.Arguments := nil;
end;

// ============================================================================
// TListResourcesRequest / TListResourcesResult
// ============================================================================

function TListResourcesRequest.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if not Cursor.IsEmpty then
    Result.AddPair('cursor', Cursor);
end;

function TListResourcesResult.ToJSON: TJSONObject;
var
  LArray: TJSONArray;
  LRes: TMCPResource;
begin
  Result := TJSONObject.Create;
  
  LArray := TJSONArray.Create;
  if Assigned(Resources) then
    for LRes in Resources do
      LArray.Add(LRes.ToJSON);
  Result.AddPair('resources', LArray);
  
  if not NextCursor.IsEmpty then
    Result.AddPair('nextCursor', NextCursor);
end;

// ============================================================================
// TReadResourceRequest / TReadResourceResult
// ============================================================================

class function TReadResourceRequest.FromJSON(AJson: TJSONObject): TReadResourceRequest;
begin
  Result.Uri := AJson.GetValue<string>('uri', '');
end;

function TReadResourceResult.ToJSON: TJSONObject;
var
  LArray: TJSONArray;
  LContent: TMCPResourceContents;
begin
  Result := TJSONObject.Create;
  
  LArray := TJSONArray.Create;
  for LContent in Contents do
    LArray.Add(LContent.ToJSON);
  Result.AddPair('contents', LArray);
end;

// ============================================================================
// TListPromptsRequest / TListPromptsResult
// ============================================================================

function TListPromptsRequest.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  if not Cursor.IsEmpty then
    Result.AddPair('cursor', Cursor);
end;

function TListPromptsResult.ToJSON: TJSONObject;
var
  LArray: TJSONArray;
  LPrompt: TMCPPrompt;
begin
  Result := TJSONObject.Create;
  
  LArray := TJSONArray.Create;
  if Assigned(Prompts) then
    for LPrompt in Prompts do
      LArray.Add(LPrompt.ToJSON);
  Result.AddPair('prompts', LArray);
  
  if not NextCursor.IsEmpty then
    Result.AddPair('nextCursor', NextCursor);
end;

// ============================================================================
// TGetPromptRequest / TGetPromptResult
// ============================================================================

class function TGetPromptRequest.FromJSON(AJson: TJSONObject): TGetPromptRequest;
begin
  Result.Name := AJson.GetValue<string>('name', '');
  if AJson.TryGetValue<TJSONObject>('arguments', Result.Arguments) then
    Result.Arguments := Result.Arguments.Clone as TJSONObject
  else
    Result.Arguments := nil;
end;

function TGetPromptResult.ToJSON: TJSONObject;
var
  LArray: TJSONArray;
  LMsg: TMCPPromptMessage;
begin
  Result := TJSONObject.Create;
  if not Description.IsEmpty then
    Result.AddPair('description', Description);
  
  LArray := TJSONArray.Create;
  for LMsg in Messages do
    LArray.Add(LMsg.ToJSON);
  Result.AddPair('messages', LArray);
end;

// ============================================================================
// TMCPProgressNotification
// ============================================================================

function TMCPProgressNotification.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('progressToken', ProgressToken);
  Result.AddPair('progress', TJSONNumber.Create(Progress));
  if Total > 0 then
    Result.AddPair('total', TJSONNumber.Create(Total));
end;

// ============================================================================
// Helper Functions
// ============================================================================

function MCPRoleToString(ARole: TMCPRole): string;
begin
  case ARole of
    mrUser: Result := 'user';
    mrAssistant: Result := 'assistant';
  else
    Result := 'user';
  end;
end;

function StringToMCPRole(const AStr: string): TMCPRole;
begin
  if AStr = 'assistant' then
    Result := mrAssistant
  else
    Result := mrUser;
end;

function MCPNotificationTypeToMethod(AType: TMCPNotificationType): string;
begin
  case AType of
    ntInitialized: Result := 'notifications/initialized';
    ntProgress: Result := 'notifications/progress';
    ntToolsListChanged: Result := 'notifications/tools/list_changed';
    ntResourcesListChanged: Result := 'notifications/resources/list_changed';
    ntPromptsListChanged: Result := 'notifications/prompts/list_changed';
    ntResourceUpdated: Result := 'notifications/resources/updated';
    ntCancelled: Result := 'notifications/cancelled';
  else
    Result := 'notifications/unknown';
  end;
end;

end.
