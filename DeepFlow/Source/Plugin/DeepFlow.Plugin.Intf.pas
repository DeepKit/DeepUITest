(*******************************************************************************
                                                                               
  UniFlow Plugin Interface                                                     
  Plugin system interface definitions for UniFlow                              
                                                                               
  Features:                                                                    
  - IUniFlowPlugin: Main plugin interface                                      
  - IPluginActionExecutor: Custom action executor extension                    
  - IPluginValidator: Custom validator extension                               
  - IPluginEventHandler: Event handler extension                               
  - TPluginContext: Runtime context for plugins                                
                                                                               
  Design Principles:                                                           
  - Minimal invasion: plugins don't modify core code                           
  - Safe isolation: plugin errors don't crash host                             
  - Version compatibility: interfaces are versioned                            
  - Hot loading: runtime load/unload support                                   
  - Dependency injection: services provided via Context                        
                                                                               
*******************************************************************************)

unit UniFlow.Plugin.Intf;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.Rtti;

const
  /// <summary>Plugin interface version - used for compatibility checks</summary>
  UNIFLOW_PLUGIN_VERSION = 1;
  
  /// <summary>Minimum supported plugin interface version</summary>
  UNIFLOW_PLUGIN_MIN_VERSION = 1;

type
  //----------------------------------------------------------------------------
  // Forward declarations
  //----------------------------------------------------------------------------
  
  IPluginContext = interface;
  IPluginLogger = interface;
  IPluginConfig = interface;
  IPluginServices = interface;
  IUniFlowPlugin = interface;
  IPluginActionExecutor = interface;
  IPluginValidator = interface;
  IPluginEventHandler = interface;
  IPluginTransformer = interface;

  //----------------------------------------------------------------------------
  // Plugin capability flags
  //----------------------------------------------------------------------------
  
  TPluginCapability = (
    pcActionExecutor,    // Plugin provides action executors
    pcValidator,         // Plugin provides validators
    pcEventHandler,      // Plugin provides event handlers
    pcTransformer,       // Plugin provides data transformers
    pcFilter,            // Plugin provides filters
    pcMiddleware         // Plugin provides middleware
  );
  TPluginCapabilities = set of TPluginCapability;
  
  //----------------------------------------------------------------------------
  // Plugin status
  //----------------------------------------------------------------------------
  
  TPluginStatus = (
    psUnloaded,      // Not loaded
    psLoaded,        // Loaded but not initialized
    psInitializing,  // Being initialized
    psActive,        // Active and running
    psFailed,        // Failed to initialize
    psDisabled,      // Manually disabled
    psUnloading      // Being unloaded
  );
  
  //----------------------------------------------------------------------------
  // Plugin metadata
  //----------------------------------------------------------------------------
  
  TPluginInfo = record
    /// <summary>Unique plugin identifier</summary>
    Id: string;
    /// <summary>Display name</summary>
    Name: string;
    /// <summary>Version string (semver recommended)</summary>
    Version: string;
    /// <summary>Author/vendor</summary>
    Author: string;
    /// <summary>Plugin description</summary>
    Description: string;
    /// <summary>Plugin website/documentation URL</summary>
    URL: string;
    /// <summary>Plugin capabilities</summary>
    Capabilities: TPluginCapabilities;
    /// <summary>Dependencies (plugin IDs)</summary>
    Dependencies: TArray<string>;
    /// <summary>Interface version this plugin requires</summary>
    InterfaceVersion: Integer;
    /// <summary>Plugin file path</summary>
    FilePath: string;
    /// <summary>Plugin status</summary>
    Status: TPluginStatus;
    /// <summary>Error message if failed</summary>
    ErrorMessage: string;
    
    class function Create(const AId, AName, AVersion: string): TPluginInfo; static;
    function ToString: string;
    function ToJSON: TJSONObject;
    class function FromJSON(AJSON: TJSONObject): TPluginInfo; static;
  end;
  
  //----------------------------------------------------------------------------
  // Plugin execution result
  //----------------------------------------------------------------------------
  
  TPluginResult = record
    Success: Boolean;
    Output: TJSONValue;
    ErrorCode: string;
    ErrorMessage: string;
    
    class function OK(AOutput: TJSONValue = nil): TPluginResult; static;
    class function Fail(const ACode, AMessage: string): TPluginResult; static;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginLogger - Logging interface for plugins
  //----------------------------------------------------------------------------
  
  TPluginLogLevel = (pllTrace, pllDebug, pllInfo, pllWarning, pllError, pllFatal);
  
  IPluginLogger = interface
    ['{F1A2B3C4-D5E6-47F8-9A0B-1C2D3E4F5A6B}']
    procedure Log(Level: TPluginLogLevel; const Message: string); overload;
    procedure Log(Level: TPluginLogLevel; const Format: string; const Args: array of const); overload;
    procedure Trace(const Message: string);
    procedure Debug(const Message: string);
    procedure Info(const Message: string);
    procedure Warning(const Message: string);
    procedure Error(const Message: string);
    
    function GetMinLevel: TPluginLogLevel;
    procedure SetMinLevel(Value: TPluginLogLevel);
    property MinLevel: TPluginLogLevel read GetMinLevel write SetMinLevel;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginConfig - Configuration interface for plugins
  //----------------------------------------------------------------------------
  
  IPluginConfig = interface
    ['{A1B2C3D4-E5F6-4789-0ABC-DEF123456789}']
    function GetString(const Key: string; const Default: string = ''): string;
    function GetInteger(const Key: string; Default: Integer = 0): Integer;
    function GetBoolean(const Key: string; Default: Boolean = False): Boolean;
    function GetFloat(const Key: string; Default: Double = 0.0): Double;
    function GetJSON(const Key: string): TJSONValue;
    function HasKey(const Key: string): Boolean;
    function GetAllKeys: TArray<string>;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginServices - Service locator for plugins
  //----------------------------------------------------------------------------
  
  IPluginServices = interface
    ['{B2C3D4E5-F6A7-4890-1BCD-EF2345678901}']
    function GetService(const ServiceId: string): IInterface;
    function HasService(const ServiceId: string): Boolean;
    procedure RegisterService(const ServiceId: string; Service: IInterface);
    procedure UnregisterService(const ServiceId: string);
  end;
  
  //----------------------------------------------------------------------------
  // IPluginContext - Runtime context for plugins
  //----------------------------------------------------------------------------
  
  IPluginContext = interface
    ['{C3D4E5F6-A7B8-4901-2CDE-F34567890123}']
    /// <summary>Get plugin logger</summary>
    function GetLogger: IPluginLogger;
    /// <summary>Get plugin configuration</summary>
    function GetConfig: IPluginConfig;
    /// <summary>Get service locator</summary>
    function GetServices: IPluginServices;
    /// <summary>Get host application directory</summary>
    function GetAppDir: string;
    /// <summary>Get plugin data directory</summary>
    function GetPluginDataDir: string;
    /// <summary>Get workflow context variables (read-only snapshot)</summary>
    function GetWorkflowVariables: TJSONObject;
    /// <summary>Set workflow context variable</summary>
    procedure SetWorkflowVariable(const Name: string; Value: TJSONValue);
    
    property Logger: IPluginLogger read GetLogger;
    property Config: IPluginConfig read GetConfig;
    property Services: IPluginServices read GetServices;
    property AppDir: string read GetAppDir;
    property PluginDataDir: string read GetPluginDataDir;
  end;
  
  //----------------------------------------------------------------------------
  // IUniFlowPlugin - Main plugin interface
  //----------------------------------------------------------------------------
  
  IUniFlowPlugin = interface
    ['{D4E5F6A7-B8C9-4012-3DEF-456789012345}']
    /// <summary>Get plugin information</summary>
    function GetInfo: TPluginInfo;
    /// <summary>Get interface version this plugin implements</summary>
    function GetInterfaceVersion: Integer;
    
    /// <summary>Initialize plugin with context</summary>
    /// <returns>True if initialization succeeded</returns>
    function Initialize(Context: IPluginContext): Boolean;
    /// <summary>Finalize plugin (cleanup)</summary>
    procedure Finalize;
    
    /// <summary>Get action executors provided by this plugin</summary>
    function GetActionExecutors: TArray<IPluginActionExecutor>;
    /// <summary>Get validators provided by this plugin</summary>
    function GetValidators: TArray<IPluginValidator>;
    /// <summary>Get event handlers provided by this plugin</summary>
    function GetEventHandlers: TArray<IPluginEventHandler>;
    /// <summary>Get transformers provided by this plugin</summary>
    function GetTransformers: TArray<IPluginTransformer>;
    
    property Info: TPluginInfo read GetInfo;
    property InterfaceVersion: Integer read GetInterfaceVersion;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginActionExecutor - Custom action executor interface
  //----------------------------------------------------------------------------
  
  TActionExecutorInfo = record
    /// <summary>Action type name (e.g., 'email', 'delay', 'custom')</summary>
    ActionType: string;
    /// <summary>Display name</summary>
    DisplayName: string;
    /// <summary>Description</summary>
    Description: string;
    /// <summary>Parameter schema (JSON Schema)</summary>
    ParamSchema: TJSONObject;
    /// <summary>Output schema (JSON Schema)</summary>
    OutputSchema: TJSONObject;
    /// <summary>Whether this action is async</summary>
    IsAsync: Boolean;
    /// <summary>Default timeout in milliseconds</summary>
    DefaultTimeoutMs: Integer;
    
    class function Create(const AActionType, ADisplayName: string): TActionExecutorInfo; static;
  end;
  
  IPluginActionExecutor = interface
    ['{E5F6A7B8-C9D0-4123-4EF0-567890123456}']
    /// <summary>Get executor information</summary>
    function GetInfo: TActionExecutorInfo;
    /// <summary>Check if this executor can handle the action type</summary>
    function CanHandle(const ActionType: string): Boolean;
    /// <summary>Execute the action</summary>
    /// <param name="ActionType">Action type name</param>
    /// <param name="Params">Action parameters (JSON object)</param>
    /// <param name="Context">Plugin context</param>
    /// <returns>Execution result</returns>
    function Execute(const ActionType: string; Params: TJSONObject; 
      Context: IPluginContext): TPluginResult;
    /// <summary>Validate parameters before execution</summary>
    function ValidateParams(const ActionType: string; Params: TJSONObject): TPluginResult;
    
    property Info: TActionExecutorInfo read GetInfo;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginValidator - Custom validator interface
  //----------------------------------------------------------------------------
  
  TValidatorInfo = record
    /// <summary>Validator type name (e.g., 'china_phone', 'id_card')</summary>
    ValidatorType: string;
    /// <summary>Display name</summary>
    DisplayName: string;
    /// <summary>Description</summary>
    Description: string;
    /// <summary>Configuration schema (JSON Schema)</summary>
    ConfigSchema: TJSONObject;
    
    class function Create(const AValidatorType, ADisplayName: string): TValidatorInfo; static;
  end;
  
  TValidationResult = record
    IsValid: Boolean;
    Errors: TArray<string>;
    
    class function Valid: TValidationResult; static;
    class function Invalid(const AErrors: TArray<string>): TValidationResult; static;
    class function InvalidSingle(const AError: string): TValidationResult; static;
  end;
  
  IPluginValidator = interface
    ['{F6A7B8C9-D0E1-4234-5F01-678901234567}']
    /// <summary>Get validator information</summary>
    function GetInfo: TValidatorInfo;
    /// <summary>Check if this validator can handle the type</summary>
    function CanHandle(const ValidatorType: string): Boolean;
    /// <summary>Validate a value</summary>
    /// <param name="ValidatorType">Validator type name</param>
    /// <param name="Value">Value to validate (as JSON)</param>
    /// <param name="Config">Validator configuration (optional)</param>
    /// <returns>Validation result</returns>
    function Validate(const ValidatorType: string; Value: TJSONValue; 
      Config: TJSONObject = nil): TValidationResult;
    
    property Info: TValidatorInfo read GetInfo;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginEventHandler - Event handler interface
  //----------------------------------------------------------------------------
  
  TEventHandlerInfo = record
    /// <summary>Event type names this handler subscribes to</summary>
    EventTypes: TArray<string>;
    /// <summary>Display name</summary>
    DisplayName: string;
    /// <summary>Description</summary>
    Description: string;
    /// <summary>Priority (lower = higher priority)</summary>
    Priority: Integer;
    
    class function Create(const AEventTypes: TArray<string>; const ADisplayName: string): TEventHandlerInfo; static;
  end;
  
  TPluginEvent = record
    /// <summary>Event type</summary>
    EventType: string;
    /// <summary>Event timestamp</summary>
    Timestamp: TDateTime;
    /// <summary>Event source</summary>
    Source: string;
    /// <summary>Event data</summary>
    Data: TJSONObject;
    /// <summary>Correlation ID for tracing</summary>
    CorrelationId: string;
    
    class function Create(const AEventType: string; AData: TJSONObject = nil): TPluginEvent; static;
  end;
  
  IPluginEventHandler = interface
    ['{A7B8C9D0-E1F2-4345-6012-789012345678}']
    /// <summary>Get handler information</summary>
    function GetInfo: TEventHandlerInfo;
    /// <summary>Check if this handler can handle the event type</summary>
    function CanHandle(const EventType: string): Boolean;
    /// <summary>Handle an event</summary>
    /// <param name="Event">The event to handle</param>
    /// <param name="Context">Plugin context</param>
    /// <returns>True if event was handled (stop propagation)</returns>
    function Handle(const Event: TPluginEvent; Context: IPluginContext): Boolean;
    
    property Info: TEventHandlerInfo read GetInfo;
  end;
  
  //----------------------------------------------------------------------------
  // IPluginTransformer - Data transformer interface
  //----------------------------------------------------------------------------
  
  TTransformerInfo = record
    /// <summary>Transformer type name (e.g., 'json_to_xml', 'encrypt')</summary>
    TransformerType: string;
    /// <summary>Display name</summary>
    DisplayName: string;
    /// <summary>Description</summary>
    Description: string;
    /// <summary>Input schema (JSON Schema)</summary>
    InputSchema: TJSONObject;
    /// <summary>Output schema (JSON Schema)</summary>
    OutputSchema: TJSONObject;
    
    class function Create(const ATransformerType, ADisplayName: string): TTransformerInfo; static;
  end;
  
  IPluginTransformer = interface
    ['{B8C9D0E1-F2A3-4456-7123-890123456789}']
    /// <summary>Get transformer information</summary>
    function GetInfo: TTransformerInfo;
    /// <summary>Check if this transformer can handle the type</summary>
    function CanHandle(const TransformerType: string): Boolean;
    /// <summary>Transform data</summary>
    /// <param name="TransformerType">Transformer type name</param>
    /// <param name="Input">Input data</param>
    /// <param name="Config">Transformer configuration (optional)</param>
    /// <returns>Transformation result</returns>
    function Transform(const TransformerType: string; Input: TJSONValue; 
      Config: TJSONObject = nil): TPluginResult;
    
    property Info: TTransformerInfo read GetInfo;
  end;
  
  //----------------------------------------------------------------------------
  // Plugin export function type
  //----------------------------------------------------------------------------
  
  /// <summary>
  /// Plugin export function signature for DLL plugins.
  /// DLL must export a function named 'GetUniFlowPlugin' with this signature.
  /// </summary>
  TGetUniFlowPluginFunc = function: IUniFlowPlugin; stdcall;

  //----------------------------------------------------------------------------
  // Base implementation helpers
  //----------------------------------------------------------------------------
  
  /// <summary>Base class for plugin implementations</summary>
  TBaseUniFlowPlugin = class(TInterfacedObject, IUniFlowPlugin)
  protected
    FInfo: TPluginInfo;
    FContext: IPluginContext;
    FActionExecutors: TList<IPluginActionExecutor>;
    FValidators: TList<IPluginValidator>;
    FEventHandlers: TList<IPluginEventHandler>;
    FTransformers: TList<IPluginTransformer>;
  public
    constructor Create(const AId, AName, AVersion: string);
    destructor Destroy; override;
    
    // IUniFlowPlugin
    function GetInfo: TPluginInfo;
    function GetInterfaceVersion: Integer;
    function Initialize(Context: IPluginContext): Boolean; virtual;
    procedure Finalize; virtual;
    function GetActionExecutors: TArray<IPluginActionExecutor>;
    function GetValidators: TArray<IPluginValidator>;
    function GetEventHandlers: TArray<IPluginEventHandler>;
    function GetTransformers: TArray<IPluginTransformer>;
    
    // Registration helpers
    procedure RegisterActionExecutor(Executor: IPluginActionExecutor);
    procedure RegisterValidator(Validator: IPluginValidator);
    procedure RegisterEventHandler(Handler: IPluginEventHandler);
    procedure RegisterTransformer(Transformer: IPluginTransformer);
    
    property Info: TPluginInfo read FInfo;
    property Context: IPluginContext read FContext;
  end;

  //----------------------------------------------------------------------------
  // Helper functions
  //----------------------------------------------------------------------------

function PluginLogLevelToStr(Level: TPluginLogLevel): string;
function StrToPluginLogLevel(const S: string): TPluginLogLevel;
function PluginStatusToStr(Status: TPluginStatus): string;
function StrToPluginStatus(const S: string): TPluginStatus;
function PluginCapabilityToStr(Cap: TPluginCapability): string;
function CapabilitiesToStr(Caps: TPluginCapabilities): string;

implementation

uses
  System.DateUtils;

//------------------------------------------------------------------------------
// Helper functions
//------------------------------------------------------------------------------

function PluginLogLevelToStr(Level: TPluginLogLevel): string;
const
  Names: array[TPluginLogLevel] of string = (
    'trace', 'debug', 'info', 'warning', 'error', 'fatal'
  );
begin
  Result := Names[Level];
end;

function StrToPluginLogLevel(const S: string): TPluginLogLevel;
var
  L: TPluginLogLevel;
begin
  Result := pllInfo;
  for L := Low(TPluginLogLevel) to High(TPluginLogLevel) do
    if SameText(PluginLogLevelToStr(L), S) then
      Exit(L);
end;

function PluginStatusToStr(Status: TPluginStatus): string;
const
  Names: array[TPluginStatus] of string = (
    'unloaded', 'loaded', 'initializing', 'active', 'failed', 'disabled', 'unloading'
  );
begin
  Result := Names[Status];
end;

function StrToPluginStatus(const S: string): TPluginStatus;
var
  PS: TPluginStatus;
begin
  Result := psUnloaded;
  for PS := Low(TPluginStatus) to High(TPluginStatus) do
    if SameText(PluginStatusToStr(PS), S) then
      Exit(PS);
end;

function PluginCapabilityToStr(Cap: TPluginCapability): string;
const
  Names: array[TPluginCapability] of string = (
    'actionExecutor', 'validator', 'eventHandler', 'transformer', 'filter', 'middleware'
  );
begin
  Result := Names[Cap];
end;

function CapabilitiesToStr(Caps: TPluginCapabilities): string;
var
  Cap: TPluginCapability;
  First: Boolean;
begin
  Result := '';
  First := True;
  for Cap := Low(TPluginCapability) to High(TPluginCapability) do
  begin
    if Cap in Caps then
    begin
      if not First then
        Result := Result + ', ';
      Result := Result + PluginCapabilityToStr(Cap);
      First := False;
    end;
  end;
end;

//------------------------------------------------------------------------------
// TPluginInfo
//------------------------------------------------------------------------------

class function TPluginInfo.Create(const AId, AName, AVersion: string): TPluginInfo;
begin
  Result := Default(TPluginInfo);
  Result.Id := AId;
  Result.Name := AName;
  Result.Version := AVersion;
  Result.InterfaceVersion := UNIFLOW_PLUGIN_VERSION;
  Result.Status := psUnloaded;
end;

function TPluginInfo.ToString: string;
begin
  Result := Format('%s v%s (%s) [%s]', [Name, Version, Id, PluginStatusToStr(Status)]);
end;

function TPluginInfo.ToJSON: TJSONObject;
var
  DepsArray: TJSONArray;
  CapsArray: TJSONArray;
  S: string;
  Cap: TPluginCapability;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', Id);
  Result.AddPair('name', Name);
  Result.AddPair('version', Version);
  Result.AddPair('author', Author);
  Result.AddPair('description', Description);
  Result.AddPair('url', URL);
  Result.AddPair('interfaceVersion', TJSONNumber.Create(InterfaceVersion));
  Result.AddPair('filePath', FilePath);
  Result.AddPair('status', PluginStatusToStr(Status));
  Result.AddPair('errorMessage', ErrorMessage);
  
  DepsArray := TJSONArray.Create;
  for S in Dependencies do
    DepsArray.Add(S);
  Result.AddPair('dependencies', DepsArray);
  
  CapsArray := TJSONArray.Create;
  for Cap := Low(TPluginCapability) to High(TPluginCapability) do
    if Cap in Capabilities then
      CapsArray.Add(PluginCapabilityToStr(Cap));
  Result.AddPair('capabilities', CapsArray);
end;

class function TPluginInfo.FromJSON(AJSON: TJSONObject): TPluginInfo;
var
  DepsArray, CapsArray: TJSONArray;
  I: Integer;
  S: string;
  Cap: TPluginCapability;
begin
  Result := Default(TPluginInfo);
  if AJSON = nil then Exit;
  
  AJSON.TryGetValue<string>('id', Result.Id);
  AJSON.TryGetValue<string>('name', Result.Name);
  AJSON.TryGetValue<string>('version', Result.Version);
  AJSON.TryGetValue<string>('author', Result.Author);
  AJSON.TryGetValue<string>('description', Result.Description);
  AJSON.TryGetValue<string>('url', Result.URL);
  AJSON.TryGetValue<Integer>('interfaceVersion', Result.InterfaceVersion);
  AJSON.TryGetValue<string>('filePath', Result.FilePath);
  AJSON.TryGetValue<string>('errorMessage', Result.ErrorMessage);
  
  if AJSON.TryGetValue<string>('status', S) then
    Result.Status := StrToPluginStatus(S);
    
  if AJSON.TryGetValue<TJSONArray>('dependencies', DepsArray) then
  begin
    SetLength(Result.Dependencies, DepsArray.Count);
    for I := 0 to DepsArray.Count - 1 do
      Result.Dependencies[I] := DepsArray.Items[I].Value;
  end;
  
  if AJSON.TryGetValue<TJSONArray>('capabilities', CapsArray) then
  begin
    Result.Capabilities := [];
    for I := 0 to CapsArray.Count - 1 do
    begin
      S := CapsArray.Items[I].Value;
      for Cap := Low(TPluginCapability) to High(TPluginCapability) do
        if SameText(PluginCapabilityToStr(Cap), S) then
        begin
          Include(Result.Capabilities, Cap);
          Break;
        end;
    end;
  end;
end;

//------------------------------------------------------------------------------
// TPluginResult
//------------------------------------------------------------------------------

class function TPluginResult.OK(AOutput: TJSONValue): TPluginResult;
begin
  Result := Default(TPluginResult);
  Result.Success := True;
  if AOutput <> nil then
    Result.Output := AOutput.Clone as TJSONValue;
end;

class function TPluginResult.Fail(const ACode, AMessage: string): TPluginResult;
begin
  Result := Default(TPluginResult);
  Result.Success := False;
  Result.ErrorCode := ACode;
  Result.ErrorMessage := AMessage;
end;

//------------------------------------------------------------------------------
// TActionExecutorInfo
//------------------------------------------------------------------------------

class function TActionExecutorInfo.Create(const AActionType, ADisplayName: string): TActionExecutorInfo;
begin
  Result := Default(TActionExecutorInfo);
  Result.ActionType := AActionType;
  Result.DisplayName := ADisplayName;
  Result.DefaultTimeoutMs := 30000;
end;

//------------------------------------------------------------------------------
// TValidatorInfo
//------------------------------------------------------------------------------

class function TValidatorInfo.Create(const AValidatorType, ADisplayName: string): TValidatorInfo;
begin
  Result := Default(TValidatorInfo);
  Result.ValidatorType := AValidatorType;
  Result.DisplayName := ADisplayName;
end;

//------------------------------------------------------------------------------
// TValidationResult
//------------------------------------------------------------------------------

class function TValidationResult.Valid: TValidationResult;
begin
  Result := Default(TValidationResult);
  Result.IsValid := True;
end;

class function TValidationResult.Invalid(const AErrors: TArray<string>): TValidationResult;
begin
  Result := Default(TValidationResult);
  Result.IsValid := False;
  Result.Errors := AErrors;
end;

class function TValidationResult.InvalidSingle(const AError: string): TValidationResult;
begin
  Result := Invalid([AError]);
end;

//------------------------------------------------------------------------------
// TEventHandlerInfo
//------------------------------------------------------------------------------

class function TEventHandlerInfo.Create(const AEventTypes: TArray<string>; 
  const ADisplayName: string): TEventHandlerInfo;
begin
  Result := Default(TEventHandlerInfo);
  Result.EventTypes := AEventTypes;
  Result.DisplayName := ADisplayName;
  Result.Priority := 100;
end;

//------------------------------------------------------------------------------
// TPluginEvent
//------------------------------------------------------------------------------

class function TPluginEvent.Create(const AEventType: string; AData: TJSONObject): TPluginEvent;
begin
  Result := Default(TPluginEvent);
  Result.EventType := AEventType;
  Result.Timestamp := Now;
  if AData <> nil then
    Result.Data := TJSONObject(AData.Clone)
  else
    Result.Data := TJSONObject.Create;
end;

//------------------------------------------------------------------------------
// TTransformerInfo
//------------------------------------------------------------------------------

class function TTransformerInfo.Create(const ATransformerType, ADisplayName: string): TTransformerInfo;
begin
  Result := Default(TTransformerInfo);
  Result.TransformerType := ATransformerType;
  Result.DisplayName := ADisplayName;
end;

//------------------------------------------------------------------------------
// TBaseUniFlowPlugin
//------------------------------------------------------------------------------

constructor TBaseUniFlowPlugin.Create(const AId, AName, AVersion: string);
begin
  inherited Create;
  FInfo := TPluginInfo.Create(AId, AName, AVersion);
  FActionExecutors := TList<IPluginActionExecutor>.Create;
  FValidators := TList<IPluginValidator>.Create;
  FEventHandlers := TList<IPluginEventHandler>.Create;
  FTransformers := TList<IPluginTransformer>.Create;
end;

destructor TBaseUniFlowPlugin.Destroy;
begin
  FTransformers.Free;
  FEventHandlers.Free;
  FValidators.Free;
  FActionExecutors.Free;
  inherited;
end;

function TBaseUniFlowPlugin.GetInfo: TPluginInfo;
begin
  Result := FInfo;
end;

function TBaseUniFlowPlugin.GetInterfaceVersion: Integer;
begin
  Result := UNIFLOW_PLUGIN_VERSION;
end;

function TBaseUniFlowPlugin.Initialize(Context: IPluginContext): Boolean;
begin
  FContext := Context;
  FInfo.Status := psActive;
  Result := True;
end;

procedure TBaseUniFlowPlugin.Finalize;
begin
  FInfo.Status := psUnloaded;
  FContext := nil;
end;

function TBaseUniFlowPlugin.GetActionExecutors: TArray<IPluginActionExecutor>;
begin
  Result := FActionExecutors.ToArray;
end;

function TBaseUniFlowPlugin.GetValidators: TArray<IPluginValidator>;
begin
  Result := FValidators.ToArray;
end;

function TBaseUniFlowPlugin.GetEventHandlers: TArray<IPluginEventHandler>;
begin
  Result := FEventHandlers.ToArray;
end;

function TBaseUniFlowPlugin.GetTransformers: TArray<IPluginTransformer>;
begin
  Result := FTransformers.ToArray;
end;

procedure TBaseUniFlowPlugin.RegisterActionExecutor(Executor: IPluginActionExecutor);
begin
  FActionExecutors.Add(Executor);
  Include(FInfo.Capabilities, pcActionExecutor);
end;

procedure TBaseUniFlowPlugin.RegisterValidator(Validator: IPluginValidator);
begin
  FValidators.Add(Validator);
  Include(FInfo.Capabilities, pcValidator);
end;

procedure TBaseUniFlowPlugin.RegisterEventHandler(Handler: IPluginEventHandler);
begin
  FEventHandlers.Add(Handler);
  Include(FInfo.Capabilities, pcEventHandler);
end;

procedure TBaseUniFlowPlugin.RegisterTransformer(Transformer: IPluginTransformer);
begin
  FTransformers.Add(Transformer);
  Include(FInfo.Capabilities, pcTransformer);
end;

end.
