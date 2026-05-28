(*******************************************************************************
                                                                               
  UniFlow Plugin Loader                                                        
  Dynamic plugin loading for BPL and DLL plugins                               
                                                                               
  Features:                                                                    
  - TBPLPluginLoader: Load Delphi BPL packages                                 
  - TDLLPluginLoader: Load native DLLs                                         
  - TPluginLoader: Unified loader for all plugin types                         
  - TPluginContext: Runtime context implementation                             
  - Directory scanning for auto-discovery                                      
                                                                               
  Security:                                                                    
  - Version compatibility checking                                             
  - Exception isolation                                                        
  - Resource cleanup on failure                                                
                                                                               
*******************************************************************************)

unit UniFlow.Plugin.Loader;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  System.SyncObjs,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  UniFlow.Plugin.Intf;

type
  //----------------------------------------------------------------------------
  // Load result
  //----------------------------------------------------------------------------
  
  TPluginLoadResult = record
    Success: Boolean;
    Plugin: IUniFlowPlugin;
    FilePath: string;
    ErrorMessage: string;
    
    class function OK(APlugin: IUniFlowPlugin; const APath: string): TPluginLoadResult; static;
    class function Fail(const APath, AError: string): TPluginLoadResult; static;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginLogger - Default logger implementation
  //----------------------------------------------------------------------------
  
  TPluginLogger = class(TInterfacedObject, IPluginLogger)
  private
    FPluginId: string;
    FMinLevel: TPluginLogLevel;
    FOnLog: TProc<TPluginLogLevel, string>;
  public
    constructor Create(const APluginId: string);
    
    // IPluginLogger
    procedure Log(Level: TPluginLogLevel; const Message: string); overload;
    procedure Log(Level: TPluginLogLevel; const Format: string; const Args: array of const); overload;
    procedure Trace(const Message: string);
    procedure Debug(const Message: string);
    procedure Info(const Message: string);
    procedure Warning(const Message: string);
    procedure Error(const Message: string);
    function GetMinLevel: TPluginLogLevel;
    procedure SetMinLevel(Value: TPluginLogLevel);
    
    property OnLog: TProc<TPluginLogLevel, string> read FOnLog write FOnLog;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginConfig - Default configuration implementation
  //----------------------------------------------------------------------------
  
  TPluginConfig = class(TInterfacedObject, IPluginConfig)
  private
    FData: TJSONObject;
    FOwnsData: Boolean;
  public
    constructor Create(AData: TJSONObject = nil; AOwnsData: Boolean = True);
    destructor Destroy; override;
    
    // IPluginConfig
    function GetString(const Key: string; const Default: string = ''): string;
    function GetInteger(const Key: string; Default: Integer = 0): Integer;
    function GetBoolean(const Key: string; Default: Boolean = False): Boolean;
    function GetFloat(const Key: string; Default: Double = 0.0): Double;
    function GetJSON(const Key: string): TJSONValue;
    function HasKey(const Key: string): Boolean;
    function GetAllKeys: TArray<string>;
    
    // Additional methods
    procedure SetValue(const Key: string; Value: TJSONValue);
    procedure SetString(const Key, Value: string);
    procedure SetInteger(const Key: string; Value: Integer);
    procedure SetBoolean(const Key: string; Value: Boolean);
    procedure LoadFromFile(const FileName: string);
    procedure SaveToFile(const FileName: string);
    
    property Data: TJSONObject read FData;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginServices - Default service locator implementation
  //----------------------------------------------------------------------------
  
  TPluginServices = class(TInterfacedObject, IPluginServices)
  private
    FServices: TDictionary<string, IInterface>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    // IPluginServices
    function GetService(const ServiceId: string): IInterface;
    function HasService(const ServiceId: string): Boolean;
    procedure RegisterService(const ServiceId: string; Service: IInterface);
    procedure UnregisterService(const ServiceId: string);
  end;
  
  //----------------------------------------------------------------------------
  // TPluginContextImpl - Runtime context implementation
  //----------------------------------------------------------------------------
  
  TPluginContextImpl = class(TInterfacedObject, IPluginContext)
  private
    FPluginId: string;
    FLogger: IPluginLogger;
    FConfig: IPluginConfig;
    FServices: IPluginServices;
    FAppDir: string;
    FPluginDataDir: string;
    FWorkflowVars: TJSONObject;
    FOnSetVariable: TProc<string, TJSONValue>;
  public
    constructor Create(const APluginId: string);
    destructor Destroy; override;
    
    // IPluginContext
    function GetLogger: IPluginLogger;
    function GetConfig: IPluginConfig;
    function GetServices: IPluginServices;
    function GetAppDir: string;
    function GetPluginDataDir: string;
    function GetWorkflowVariables: TJSONObject;
    procedure SetWorkflowVariable(const Name: string; Value: TJSONValue);
    
    // Configuration
    procedure SetLogger(ALogger: IPluginLogger);
    procedure SetConfig(AConfig: IPluginConfig);
    procedure SetServices(AServices: IPluginServices);
    procedure SetAppDir(const ADir: string);
    procedure SetPluginDataDir(const ADir: string);
    procedure SetWorkflowVars(AVars: TJSONObject);
    
    property OnSetVariable: TProc<string, TJSONValue> read FOnSetVariable write FOnSetVariable;
  end;
  
  //----------------------------------------------------------------------------
  // TLoadedPlugin - Container for loaded plugin
  //----------------------------------------------------------------------------
  
  TLoadedPlugin = class
  private
    FPlugin: IUniFlowPlugin;
    FFilePath: string;
    FHandle: THandle;  // BPL/DLL handle
    FLoadType: string; // 'bpl' or 'dll'
    FContext: IPluginContext;
    FLoadTime: TDateTime;
  public
    constructor Create(APlugin: IUniFlowPlugin; const APath: string; 
      AHandle: THandle; const ALoadType: string);
    destructor Destroy; override;
    
    property Plugin: IUniFlowPlugin read FPlugin;
    property FilePath: string read FFilePath;
    property Handle: THandle read FHandle;
    property LoadType: string read FLoadType;
    property Context: IPluginContext read FContext write FContext;
    property LoadTime: TDateTime read FLoadTime;
  end;
  
  //----------------------------------------------------------------------------
  // TBPLPluginLoader - Delphi BPL package loader
  //----------------------------------------------------------------------------
  
  TBPLPluginLoader = class
  private
    FLoadedPackages: TDictionary<string, THandle>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>Load a BPL package</summary>
    function LoadPackage(const PackagePath: string): TPluginLoadResult;
    /// <summary>Unload a BPL package</summary>
    procedure UnloadPackage(const PackagePath: string);
    /// <summary>Check if package is loaded</summary>
    function IsPackageLoaded(const PackagePath: string): Boolean;
    /// <summary>Get handle for loaded package</summary>
    function GetPackageHandle(const PackagePath: string): THandle;
  end;
  
  //----------------------------------------------------------------------------
  // TDLLPluginLoader - Native DLL loader
  //----------------------------------------------------------------------------
  
  TDLLPluginLoader = class
  private
    FLoadedDLLs: TDictionary<string, THandle>;
    FLock: TCriticalSection;
    
    const EXPORT_FUNC_NAME = 'GetUniFlowPlugin';
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>Load a DLL plugin</summary>
    function LoadDLL(const DLLPath: string): TPluginLoadResult;
    /// <summary>Unload a DLL plugin</summary>
    procedure UnloadDLL(const DLLPath: string);
    /// <summary>Check if DLL is loaded</summary>
    function IsDLLLoaded(const DLLPath: string): Boolean;
    /// <summary>Get handle for loaded DLL</summary>
    function GetDLLHandle(const DLLPath: string): THandle;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginLoader - Unified plugin loader
  //----------------------------------------------------------------------------
  
  TPluginLoaderConfig = record
    /// <summary>Plugin directory path</summary>
    PluginDir: string;
    /// <summary>Plugin data directory</summary>
    DataDir: string;
    /// <summary>Auto-discover plugins on start</summary>
    AutoDiscover: Boolean;
    /// <summary>Plugin file patterns (e.g., '*.bpl', '*.dll')</summary>
    FilePatterns: TArray<string>;
    /// <summary>Minimum required interface version</summary>
    MinInterfaceVersion: Integer;
    /// <summary>Shared services for all plugins</summary>
    SharedServices: IPluginServices;
    
    class function Default: TPluginLoaderConfig; static;
  end;
  
  TOnPluginEvent = procedure(Sender: TObject; const PluginId: string) of object;
  TOnPluginError = procedure(Sender: TObject; const PluginId, ErrorMessage: string) of object;
  
  TPluginLoader = class
  private
    FConfig: TPluginLoaderConfig;
    FBPLLoader: TBPLPluginLoader;
    FDLLLoader: TDLLPluginLoader;
    FLoadedPlugins: TObjectDictionary<string, TLoadedPlugin>;
    FLock: TCriticalSection;
    
    FOnPluginLoaded: TOnPluginEvent;
    FOnPluginUnloaded: TOnPluginEvent;
    FOnPluginError: TOnPluginError;
    
    function CreateContextForPlugin(const PluginId, PluginPath: string): IPluginContext;
    function GetPluginFileType(const FilePath: string): string;
    function CheckInterfaceVersion(APlugin: IUniFlowPlugin): Boolean;
    procedure DoPluginLoaded(const PluginId: string);
    procedure DoPluginUnloaded(const PluginId: string);
    procedure DoPluginError(const PluginId, ErrorMessage: string);
  public
    constructor Create(const AConfig: TPluginLoaderConfig);
    destructor Destroy; override;
    
    /// <summary>Load a plugin from file</summary>
    function LoadPlugin(const FilePath: string): TPluginLoadResult;
    /// <summary>Unload a plugin by ID</summary>
    procedure UnloadPlugin(const PluginId: string);
    /// <summary>Unload all plugins</summary>
    procedure UnloadAll;
    
    /// <summary>Scan directory for plugins</summary>
    function ScanDirectory(const Directory: string = ''): TArray<TPluginLoadResult>;
    /// <summary>Discover and load all plugins</summary>
    function DiscoverPlugins: Integer;
    
    /// <summary>Get loaded plugin by ID</summary>
    function GetPlugin(const PluginId: string): IUniFlowPlugin;
    /// <summary>Get all loaded plugins</summary>
    function GetAllPlugins: TArray<IUniFlowPlugin>;
    /// <summary>Get plugin info list</summary>
    function GetPluginInfoList: TArray<TPluginInfo>;
    /// <summary>Check if plugin is loaded</summary>
    function IsPluginLoaded(const PluginId: string): Boolean;
    /// <summary>Get plugin count</summary>
    function GetPluginCount: Integer;
    
    /// <summary>Get all action executors from all plugins</summary>
    function GetAllActionExecutors: TArray<IPluginActionExecutor>;
    /// <summary>Get all validators from all plugins</summary>
    function GetAllValidators: TArray<IPluginValidator>;
    /// <summary>Get all event handlers from all plugins</summary>
    function GetAllEventHandlers: TArray<IPluginEventHandler>;
    /// <summary>Get all transformers from all plugins</summary>
    function GetAllTransformers: TArray<IPluginTransformer>;
    
    /// <summary>Find action executor by type</summary>
    function FindActionExecutor(const ActionType: string): IPluginActionExecutor;
    /// <summary>Find validator by type</summary>
    function FindValidator(const ValidatorType: string): IPluginValidator;
    
    property Config: TPluginLoaderConfig read FConfig;
    property PluginCount: Integer read GetPluginCount;
    
    // Events
    property OnPluginLoaded: TOnPluginEvent read FOnPluginLoaded write FOnPluginLoaded;
    property OnPluginUnloaded: TOnPluginEvent read FOnPluginUnloaded write FOnPluginUnloaded;
    property OnPluginError: TOnPluginError read FOnPluginError write FOnPluginError;
  end;

implementation

uses
  System.DateUtils,
  System.StrUtils;

//------------------------------------------------------------------------------
// TPluginLoadResult
//------------------------------------------------------------------------------

class function TPluginLoadResult.OK(APlugin: IUniFlowPlugin; const APath: string): TPluginLoadResult;
begin
  Result := Default(TPluginLoadResult);
  Result.Success := True;
  Result.Plugin := APlugin;
  Result.FilePath := APath;
end;

class function TPluginLoadResult.Fail(const APath, AError: string): TPluginLoadResult;
begin
  Result := Default(TPluginLoadResult);
  Result.Success := False;
  Result.FilePath := APath;
  Result.ErrorMessage := AError;
end;

//------------------------------------------------------------------------------
// TPluginLogger
//------------------------------------------------------------------------------

constructor TPluginLogger.Create(const APluginId: string);
begin
  inherited Create;
  FPluginId := APluginId;
  FMinLevel := pllInfo;
end;

procedure TPluginLogger.Log(Level: TPluginLogLevel; const Message: string);
begin
  if Ord(Level) >= Ord(FMinLevel) then
  begin
    if Assigned(FOnLog) then
      FOnLog(Level, Format('[%s] %s', [FPluginId, Message]))
    else
      Writeln(Format('[%s][%s] %s', [
        FormatDateTime('hh:nn:ss.zzz', Now),
        PluginLogLevelToStr(Level),
        Message
      ]));
  end;
end;

procedure TPluginLogger.Log(Level: TPluginLogLevel; const Format: string; const Args: array of const);
begin
  Log(Level, System.SysUtils.Format(Format, Args));
end;

procedure TPluginLogger.Trace(const Message: string);
begin
  Log(pllTrace, Message);
end;

procedure TPluginLogger.Debug(const Message: string);
begin
  Log(pllDebug, Message);
end;

procedure TPluginLogger.Info(const Message: string);
begin
  Log(pllInfo, Message);
end;

procedure TPluginLogger.Warning(const Message: string);
begin
  Log(pllWarning, Message);
end;

procedure TPluginLogger.Error(const Message: string);
begin
  Log(pllError, Message);
end;

function TPluginLogger.GetMinLevel: TPluginLogLevel;
begin
  Result := FMinLevel;
end;

procedure TPluginLogger.SetMinLevel(Value: TPluginLogLevel);
begin
  FMinLevel := Value;
end;

//------------------------------------------------------------------------------
// TPluginConfig
//------------------------------------------------------------------------------

constructor TPluginConfig.Create(AData: TJSONObject; AOwnsData: Boolean);
begin
  inherited Create;
  FOwnsData := AOwnsData;
  if AData <> nil then
    FData := AData
  else
  begin
    FData := TJSONObject.Create;
    FOwnsData := True;
  end;
end;

destructor TPluginConfig.Destroy;
begin
  if FOwnsData then
    FData.Free;
  inherited;
end;

function TPluginConfig.GetString(const Key: string; const Default: string): string;
begin
  if not FData.TryGetValue<string>(Key, Result) then
    Result := Default;
end;

function TPluginConfig.GetInteger(const Key: string; Default: Integer): Integer;
begin
  if not FData.TryGetValue<Integer>(Key, Result) then
    Result := Default;
end;

function TPluginConfig.GetBoolean(const Key: string; Default: Boolean): Boolean;
begin
  if not FData.TryGetValue<Boolean>(Key, Result) then
    Result := Default;
end;

function TPluginConfig.GetFloat(const Key: string; Default: Double): Double;
begin
  if not FData.TryGetValue<Double>(Key, Result) then
    Result := Default;
end;

function TPluginConfig.GetJSON(const Key: string): TJSONValue;
begin
  Result := FData.GetValue(Key);
end;

function TPluginConfig.HasKey(const Key: string): Boolean;
begin
  Result := FData.GetValue(Key) <> nil;
end;

function TPluginConfig.GetAllKeys: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FData.Count);
  for I := 0 to FData.Count - 1 do
    Result[I] := FData.Pairs[I].JsonString.Value;
end;

procedure TPluginConfig.SetValue(const Key: string; Value: TJSONValue);
begin
  FData.RemovePair(Key);
  if Value <> nil then
    FData.AddPair(Key, Value.Clone as TJSONValue);
end;

procedure TPluginConfig.SetString(const Key, Value: string);
begin
  FData.RemovePair(Key);
  FData.AddPair(Key, Value);
end;

procedure TPluginConfig.SetInteger(const Key: string; Value: Integer);
begin
  FData.RemovePair(Key);
  FData.AddPair(Key, TJSONNumber.Create(Value));
end;

procedure TPluginConfig.SetBoolean(const Key: string; Value: Boolean);
begin
  FData.RemovePair(Key);
  FData.AddPair(Key, TJSONBool.Create(Value));
end;

procedure TPluginConfig.LoadFromFile(const FileName: string);
var
  Content: string;
  JSON: TJSONValue;
begin
  if not TFile.Exists(FileName) then
    Exit;
    
  Content := TFile.ReadAllText(FileName, TEncoding.UTF8);
  JSON := TJSONObject.ParseJSONValue(Content);
  if JSON is TJSONObject then
  begin
    if FOwnsData then
      FData.Free;
    FData := TJSONObject(JSON);
    FOwnsData := True;
  end
  else
    JSON.Free;
end;

procedure TPluginConfig.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, FData.Format(2), TEncoding.UTF8);
end;

//------------------------------------------------------------------------------
// TPluginServices
//------------------------------------------------------------------------------

constructor TPluginServices.Create;
begin
  inherited Create;
  FServices := TDictionary<string, IInterface>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TPluginServices.Destroy;
begin
  FLock.Enter;
  try
    FServices.Clear;
  finally
    FLock.Leave;
  end;
  FServices.Free;
  FLock.Free;
  inherited;
end;

function TPluginServices.GetService(const ServiceId: string): IInterface;
begin
  FLock.Enter;
  try
    if not FServices.TryGetValue(ServiceId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TPluginServices.HasService(const ServiceId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FServices.ContainsKey(ServiceId);
  finally
    FLock.Leave;
  end;
end;

procedure TPluginServices.RegisterService(const ServiceId: string; Service: IInterface);
begin
  FLock.Enter;
  try
    FServices.AddOrSetValue(ServiceId, Service);
  finally
    FLock.Leave;
  end;
end;

procedure TPluginServices.UnregisterService(const ServiceId: string);
begin
  FLock.Enter;
  try
    FServices.Remove(ServiceId);
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TPluginContextImpl
//------------------------------------------------------------------------------

constructor TPluginContextImpl.Create(const APluginId: string);
begin
  inherited Create;
  FPluginId := APluginId;
  FLogger := TPluginLogger.Create(APluginId);
  FConfig := TPluginConfig.Create;
  FServices := TPluginServices.Create;
  FAppDir := ExtractFilePath(ParamStr(0));
  FPluginDataDir := TPath.Combine(FAppDir, 'PluginData');
  FPluginDataDir := TPath.Combine(FPluginDataDir, APluginId);
end;

destructor TPluginContextImpl.Destroy;
begin
  FWorkflowVars.Free;
  inherited;
end;

function TPluginContextImpl.GetLogger: IPluginLogger;
begin
  Result := FLogger;
end;

function TPluginContextImpl.GetConfig: IPluginConfig;
begin
  Result := FConfig;
end;

function TPluginContextImpl.GetServices: IPluginServices;
begin
  Result := FServices;
end;

function TPluginContextImpl.GetAppDir: string;
begin
  Result := FAppDir;
end;

function TPluginContextImpl.GetPluginDataDir: string;
begin
  Result := FPluginDataDir;
end;

function TPluginContextImpl.GetWorkflowVariables: TJSONObject;
begin
  if FWorkflowVars <> nil then
    Result := TJSONObject(FWorkflowVars.Clone)
  else
    Result := TJSONObject.Create;
end;

procedure TPluginContextImpl.SetWorkflowVariable(const Name: string; Value: TJSONValue);
begin
  if Assigned(FOnSetVariable) then
    FOnSetVariable(Name, Value);
end;

procedure TPluginContextImpl.SetLogger(ALogger: IPluginLogger);
begin
  FLogger := ALogger;
end;

procedure TPluginContextImpl.SetConfig(AConfig: IPluginConfig);
begin
  FConfig := AConfig;
end;

procedure TPluginContextImpl.SetServices(AServices: IPluginServices);
begin
  FServices := AServices;
end;

procedure TPluginContextImpl.SetAppDir(const ADir: string);
begin
  FAppDir := ADir;
end;

procedure TPluginContextImpl.SetPluginDataDir(const ADir: string);
begin
  FPluginDataDir := ADir;
end;

procedure TPluginContextImpl.SetWorkflowVars(AVars: TJSONObject);
begin
  FreeAndNil(FWorkflowVars);
  if AVars <> nil then
    FWorkflowVars := TJSONObject(AVars.Clone);
end;

//------------------------------------------------------------------------------
// TLoadedPlugin
//------------------------------------------------------------------------------

constructor TLoadedPlugin.Create(APlugin: IUniFlowPlugin; const APath: string;
  AHandle: THandle; const ALoadType: string);
begin
  inherited Create;
  FPlugin := APlugin;
  FFilePath := APath;
  FHandle := AHandle;
  FLoadType := ALoadType;
  FLoadTime := Now;
end;

destructor TLoadedPlugin.Destroy;
begin
  FPlugin := nil;
  FContext := nil;
  inherited;
end;

//------------------------------------------------------------------------------
// TBPLPluginLoader
//------------------------------------------------------------------------------

constructor TBPLPluginLoader.Create;
begin
  inherited Create;
  FLoadedPackages := TDictionary<string, THandle>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TBPLPluginLoader.Destroy;
var
  Handle: THandle;
begin
  FLock.Enter;
  try
    for Handle in FLoadedPackages.Values do
    begin
      {$IFDEF MSWINDOWS}
      try
        UnloadPackage(Handle);
      except
        on E: Exception do
        begin
          // ENTROPY-011: 记录卸载错误（析构时允许继续�?
          {$IFDEF DEBUG}
          OutputDebugString(PChar(Format('[PluginLoader] Package unload error: %s', [E.Message])));
          {$ENDIF}
        end;
      end;
      {$ENDIF}
    end;
    FLoadedPackages.Clear;
  finally
    FLock.Leave;
  end;
  FLoadedPackages.Free;
  FLock.Free;
  inherited;
end;

function TBPLPluginLoader.LoadPackage(const PackagePath: string): TPluginLoadResult;
{$IFDEF MSWINDOWS}
var
  Handle: THandle;
  GetPluginFunc: TGetUniFlowPluginFunc;
  Plugin: IUniFlowPlugin;
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(PackagePath);
  
  // Check if already loaded
  FLock.Enter;
  try
    if FLoadedPackages.ContainsKey(NormalizedPath) then
    begin
      Result := TPluginLoadResult.Fail(NormalizedPath, 'Package already loaded');
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  
  // Check file exists
  if not TFile.Exists(NormalizedPath) then
  begin
    Result := TPluginLoadResult.Fail(NormalizedPath, 'Package file not found');
    Exit;
  end;
  
  try
    // Load the package
    Handle := System.SysUtils.LoadPackage(NormalizedPath);
    if Handle = 0 then
    begin
      Result := TPluginLoadResult.Fail(NormalizedPath, 'Failed to load package');
      Exit;
    end;
    
    // Get the export function
    @GetPluginFunc := GetProcAddress(Handle, 'GetUniFlowPlugin');
    if not Assigned(GetPluginFunc) then
    begin
      UnloadPackage(Handle);
      Result := TPluginLoadResult.Fail(NormalizedPath, 'GetUniFlowPlugin function not found');
      Exit;
    end;
    
    // Get plugin instance
    try
      Plugin := GetPluginFunc();
      if Plugin = nil then
      begin
        UnloadPackage(Handle);
        Result := TPluginLoadResult.Fail(NormalizedPath, 'GetUniFlowPlugin returned nil');
        Exit;
      end;
    except
      on E: Exception do
      begin
        UnloadPackage(Handle);
        Result := TPluginLoadResult.Fail(NormalizedPath, 'Error calling GetUniFlowPlugin: ' + E.Message);
        Exit;
      end;
    end;
    
    // Store handle
    FLock.Enter;
    try
      FLoadedPackages.Add(NormalizedPath, Handle);
    finally
      FLock.Leave;
    end;
    
    Result := TPluginLoadResult.OK(Plugin, NormalizedPath);
    
  except
    on E: Exception do
      Result := TPluginLoadResult.Fail(NormalizedPath, 'Exception loading package: ' + E.Message);
  end;
end;
{$ELSE}
begin
  Result := TPluginLoadResult.Fail(PackagePath, 'BPL loading not supported on this platform');
end;
{$ENDIF}

procedure TBPLPluginLoader.UnloadPackage(const PackagePath: string);
{$IFDEF MSWINDOWS}
var
  Handle: THandle;
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(PackagePath);
  
  FLock.Enter;
  try
    if FLoadedPackages.TryGetValue(NormalizedPath, Handle) then
    begin
      FLoadedPackages.Remove(NormalizedPath);
      try
        System.SysUtils.UnloadPackage(Handle);
      except
        // Ignore unload errors
      end;
    end;
  finally
    FLock.Leave;
  end;
end;
{$ELSE}
begin
  // Not supported
end;
{$ENDIF}

function TBPLPluginLoader.IsPackageLoaded(const PackagePath: string): Boolean;
var
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(PackagePath);
  FLock.Enter;
  try
    Result := FLoadedPackages.ContainsKey(NormalizedPath);
  finally
    FLock.Leave;
  end;
end;

function TBPLPluginLoader.GetPackageHandle(const PackagePath: string): THandle;
var
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(PackagePath);
  FLock.Enter;
  try
    if not FLoadedPackages.TryGetValue(NormalizedPath, Result) then
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TDLLPluginLoader
//------------------------------------------------------------------------------

constructor TDLLPluginLoader.Create;
begin
  inherited Create;
  FLoadedDLLs := TDictionary<string, THandle>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TDLLPluginLoader.Destroy;
var
  Handle: THandle;
begin
  FLock.Enter;
  try
    for Handle in FLoadedDLLs.Values do
    begin
      {$IFDEF MSWINDOWS}
      try
        FreeLibrary(Handle);
      except
        // Ignore
      end;
      {$ENDIF}
    end;
    FLoadedDLLs.Clear;
  finally
    FLock.Leave;
  end;
  FLoadedDLLs.Free;
  FLock.Free;
  inherited;
end;

function TDLLPluginLoader.LoadDLL(const DLLPath: string): TPluginLoadResult;
{$IFDEF MSWINDOWS}
var
  Handle: THandle;
  GetPluginFunc: TGetUniFlowPluginFunc;
  Plugin: IUniFlowPlugin;
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(DLLPath);
  
  // Check if already loaded
  FLock.Enter;
  try
    if FLoadedDLLs.ContainsKey(NormalizedPath) then
    begin
      Result := TPluginLoadResult.Fail(NormalizedPath, 'DLL already loaded');
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  
  // Check file exists
  if not TFile.Exists(NormalizedPath) then
  begin
    Result := TPluginLoadResult.Fail(NormalizedPath, 'DLL file not found');
    Exit;
  end;
  
  try
    // Load the DLL
    Handle := LoadLibrary(PChar(NormalizedPath));
    if Handle = 0 then
    begin
      Result := TPluginLoadResult.Fail(NormalizedPath, 
        Format('Failed to load DLL: %s', [SysErrorMessage(GetLastError)]));
      Exit;
    end;
    
    // Get the export function
    @GetPluginFunc := GetProcAddress(Handle, EXPORT_FUNC_NAME);
    if not Assigned(GetPluginFunc) then
    begin
      FreeLibrary(Handle);
      Result := TPluginLoadResult.Fail(NormalizedPath, 
        Format('%s function not found in DLL', [EXPORT_FUNC_NAME]));
      Exit;
    end;
    
    // Get plugin instance
    try
      Plugin := GetPluginFunc();
      if Plugin = nil then
      begin
        FreeLibrary(Handle);
        Result := TPluginLoadResult.Fail(NormalizedPath, 'GetUniFlowPlugin returned nil');
        Exit;
      end;
    except
      on E: Exception do
      begin
        FreeLibrary(Handle);
        Result := TPluginLoadResult.Fail(NormalizedPath, 'Error calling GetUniFlowPlugin: ' + E.Message);
        Exit;
      end;
    end;
    
    // Store handle
    FLock.Enter;
    try
      FLoadedDLLs.Add(NormalizedPath, Handle);
    finally
      FLock.Leave;
    end;
    
    Result := TPluginLoadResult.OK(Plugin, NormalizedPath);
    
  except
    on E: Exception do
      Result := TPluginLoadResult.Fail(NormalizedPath, 'Exception loading DLL: ' + E.Message);
  end;
end;
{$ELSE}
begin
  Result := TPluginLoadResult.Fail(DLLPath, 'DLL loading not supported on this platform');
end;
{$ENDIF}

procedure TDLLPluginLoader.UnloadDLL(const DLLPath: string);
{$IFDEF MSWINDOWS}
var
  Handle: THandle;
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(DLLPath);
  
  FLock.Enter;
  try
    if FLoadedDLLs.TryGetValue(NormalizedPath, Handle) then
    begin
      FLoadedDLLs.Remove(NormalizedPath);
      try
        FreeLibrary(Handle);
      except
        // Ignore unload errors
      end;
    end;
  finally
    FLock.Leave;
  end;
end;
{$ELSE}
begin
  // Not supported
end;
{$ENDIF}

function TDLLPluginLoader.IsDLLLoaded(const DLLPath: string): Boolean;
var
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(DLLPath);
  FLock.Enter;
  try
    Result := FLoadedDLLs.ContainsKey(NormalizedPath);
  finally
    FLock.Leave;
  end;
end;

function TDLLPluginLoader.GetDLLHandle(const DLLPath: string): THandle;
var
  NormalizedPath: string;
begin
  NormalizedPath := TPath.GetFullPath(DLLPath);
  FLock.Enter;
  try
    if not FLoadedDLLs.TryGetValue(NormalizedPath, Result) then
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TPluginLoaderConfig
//------------------------------------------------------------------------------

class function TPluginLoaderConfig.Default: TPluginLoaderConfig;
begin
  Result := Default(TPluginLoaderConfig);
  Result.PluginDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Plugins');
  Result.DataDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'PluginData');
  Result.AutoDiscover := True;
  Result.FilePatterns := ['*.bpl', '*.dll'];
  Result.MinInterfaceVersion := UNIFLOW_PLUGIN_MIN_VERSION;
end;

//------------------------------------------------------------------------------
// TPluginLoader
//------------------------------------------------------------------------------

constructor TPluginLoader.Create(const AConfig: TPluginLoaderConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FBPLLoader := TBPLPluginLoader.Create;
  FDLLLoader := TDLLPluginLoader.Create;
  FLoadedPlugins := TObjectDictionary<string, TLoadedPlugin>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  
  // Ensure directories exist
  if not TDirectory.Exists(FConfig.PluginDir) then
    TDirectory.CreateDirectory(FConfig.PluginDir);
  if not TDirectory.Exists(FConfig.DataDir) then
    TDirectory.CreateDirectory(FConfig.DataDir);
end;

destructor TPluginLoader.Destroy;
begin
  UnloadAll;
  FLoadedPlugins.Free;
  FDLLLoader.Free;
  FBPLLoader.Free;
  FLock.Free;
  inherited;
end;

function TPluginLoader.CreateContextForPlugin(const PluginId, PluginPath: string): IPluginContext;
var
  Context: TPluginContextImpl;
  PluginDataDir: string;
  ConfigFile: string;
begin
  PluginDataDir := TPath.Combine(FConfig.DataDir, PluginId);
  if not TDirectory.Exists(PluginDataDir) then
    TDirectory.CreateDirectory(PluginDataDir);
  
  Context := TPluginContextImpl.Create(PluginId);
  Context.SetAppDir(ExtractFilePath(ParamStr(0)));
  Context.SetPluginDataDir(PluginDataDir);
  
  // Share services if configured
  if FConfig.SharedServices <> nil then
    Context.SetServices(FConfig.SharedServices);
  
  // Load plugin config if exists
  ConfigFile := TPath.Combine(PluginDataDir, 'config.json');
  if TFile.Exists(ConfigFile) then
    (Context.Config as TPluginConfig).LoadFromFile(ConfigFile);
  
  Result := Context;
end;

function TPluginLoader.GetPluginFileType(const FilePath: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FilePath));
  if Ext = '.bpl' then
    Result := 'bpl'
  else if Ext = '.dll' then
    Result := 'dll'
  else
    Result := '';
end;

function TPluginLoader.CheckInterfaceVersion(APlugin: IUniFlowPlugin): Boolean;
var
  Version: Integer;
begin
  Version := APlugin.GetInterfaceVersion;
  Result := (Version >= FConfig.MinInterfaceVersion) and (Version <= UNIFLOW_PLUGIN_VERSION);
end;

procedure TPluginLoader.DoPluginLoaded(const PluginId: string);
begin
  if Assigned(FOnPluginLoaded) then
    FOnPluginLoaded(Self, PluginId);
end;

procedure TPluginLoader.DoPluginUnloaded(const PluginId: string);
begin
  if Assigned(FOnPluginUnloaded) then
    FOnPluginUnloaded(Self, PluginId);
end;

procedure TPluginLoader.DoPluginError(const PluginId, ErrorMessage: string);
begin
  if Assigned(FOnPluginError) then
    FOnPluginError(Self, PluginId, ErrorMessage);
end;

function TPluginLoader.LoadPlugin(const FilePath: string): TPluginLoadResult;
var
  FileType: string;
  LoadResult: TPluginLoadResult;
  Handle: THandle;
  Context: IPluginContext;
  PluginId: string;
  LoadedPlugin: TLoadedPlugin;
begin
  FileType := GetPluginFileType(FilePath);
  if FileType = '' then
  begin
    Result := TPluginLoadResult.Fail(FilePath, 'Unsupported plugin file type');
    Exit;
  end;
  
  // Load based on type
  if FileType = 'bpl' then
  begin
    LoadResult := FBPLLoader.LoadPackage(FilePath);
    Handle := FBPLLoader.GetPackageHandle(FilePath);
  end
  else // dll
  begin
    LoadResult := FDLLLoader.LoadDLL(FilePath);
    Handle := FDLLLoader.GetDLLHandle(FilePath);
  end;
  
  if not LoadResult.Success then
  begin
    DoPluginError('', LoadResult.ErrorMessage);
    Result := LoadResult;
    Exit;
  end;
  
  // Check interface version
  if not CheckInterfaceVersion(LoadResult.Plugin) then
  begin
    // Unload
    if FileType = 'bpl' then
      FBPLLoader.UnloadPackage(FilePath)
    else
      FDLLLoader.UnloadDLL(FilePath);
    
    Result := TPluginLoadResult.Fail(FilePath, Format(
      'Incompatible interface version: %d (required: %d-%d)',
      [LoadResult.Plugin.GetInterfaceVersion, FConfig.MinInterfaceVersion, UNIFLOW_PLUGIN_VERSION]
    ));
    DoPluginError('', Result.ErrorMessage);
    Exit;
  end;
  
  PluginId := LoadResult.Plugin.Info.Id;
  
  // Check if already loaded
  FLock.Enter;
  try
    if FLoadedPlugins.ContainsKey(PluginId) then
    begin
      // Unload the new one
      if FileType = 'bpl' then
        FBPLLoader.UnloadPackage(FilePath)
      else
        FDLLLoader.UnloadDLL(FilePath);
      
      Result := TPluginLoadResult.Fail(FilePath, 'Plugin with same ID already loaded: ' + PluginId);
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  
  // Create context and initialize
  Context := CreateContextForPlugin(PluginId, FilePath);
  
  try
    if not LoadResult.Plugin.Initialize(Context) then
    begin
      // Unload
      if FileType = 'bpl' then
        FBPLLoader.UnloadPackage(FilePath)
      else
        FDLLLoader.UnloadDLL(FilePath);
      
      Result := TPluginLoadResult.Fail(FilePath, 'Plugin initialization failed');
      DoPluginError(PluginId, Result.ErrorMessage);
      Exit;
    end;
  except
    on E: Exception do
    begin
      // Unload
      if FileType = 'bpl' then
        FBPLLoader.UnloadPackage(FilePath)
      else
        FDLLLoader.UnloadDLL(FilePath);
      
      Result := TPluginLoadResult.Fail(FilePath, 'Plugin initialization exception: ' + E.Message);
      DoPluginError(PluginId, Result.ErrorMessage);
      Exit;
    end;
  end;
  
  // Store loaded plugin
  LoadedPlugin := TLoadedPlugin.Create(LoadResult.Plugin, FilePath, Handle, FileType);
  LoadedPlugin.Context := Context;
  
  FLock.Enter;
  try
    FLoadedPlugins.Add(PluginId, LoadedPlugin);
  finally
    FLock.Leave;
  end;
  
  DoPluginLoaded(PluginId);
  Result := TPluginLoadResult.OK(LoadResult.Plugin, FilePath);
end;

procedure TPluginLoader.UnloadPlugin(const PluginId: string);
var
  LoadedPlugin: TLoadedPlugin;
begin
  FLock.Enter;
  try
    if not FLoadedPlugins.TryGetValue(PluginId, LoadedPlugin) then
      Exit;
    
    // Finalize plugin
    try
      LoadedPlugin.Plugin.Finalize;
    except
      // Ignore finalization errors
    end;
    
    // Unload module
    if LoadedPlugin.LoadType = 'bpl' then
      FBPLLoader.UnloadPackage(LoadedPlugin.FilePath)
    else
      FDLLLoader.UnloadDLL(LoadedPlugin.FilePath);
    
    FLoadedPlugins.Remove(PluginId);
  finally
    FLock.Leave;
  end;
  
  DoPluginUnloaded(PluginId);
end;

procedure TPluginLoader.UnloadAll;
var
  PluginIds: TArray<string>;
  PluginId: string;
begin
  FLock.Enter;
  try
    SetLength(PluginIds, FLoadedPlugins.Count);
    var I := 0;
    for PluginId in FLoadedPlugins.Keys do
    begin
      PluginIds[I] := PluginId;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
  
  // Unload in reverse order
  for I := High(PluginIds) downto Low(PluginIds) do
    UnloadPlugin(PluginIds[I]);
end;

function TPluginLoader.ScanDirectory(const Directory: string): TArray<TPluginLoadResult>;
var
  SearchDir: string;
  Pattern: string;
  Files: TStringDynArray;
  FilePath: string;
  ResultList: TList<TPluginLoadResult>;
begin
  if Directory = '' then
    SearchDir := FConfig.PluginDir
  else
    SearchDir := Directory;
  
  if not TDirectory.Exists(SearchDir) then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  
  ResultList := TList<TPluginLoadResult>.Create;
  try
    for Pattern in FConfig.FilePatterns do
    begin
      Files := TDirectory.GetFiles(SearchDir, Pattern);
      for FilePath in Files do
        ResultList.Add(LoadPlugin(FilePath));
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginLoader.DiscoverPlugins: Integer;
var
  Results: TArray<TPluginLoadResult>;
  R: TPluginLoadResult;
begin
  Results := ScanDirectory(FConfig.PluginDir);
  Result := 0;
  for R in Results do
    if R.Success then
      Inc(Result);
end;

function TPluginLoader.GetPlugin(const PluginId: string): IUniFlowPlugin;
var
  LoadedPlugin: TLoadedPlugin;
begin
  FLock.Enter;
  try
    if FLoadedPlugins.TryGetValue(PluginId, LoadedPlugin) then
      Result := LoadedPlugin.Plugin
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TPluginLoader.GetAllPlugins: TArray<IUniFlowPlugin>;
var
  LoadedPlugin: TLoadedPlugin;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FLoadedPlugins.Count);
    I := 0;
    for LoadedPlugin in FLoadedPlugins.Values do
    begin
      Result[I] := LoadedPlugin.Plugin;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

function TPluginLoader.GetPluginInfoList: TArray<TPluginInfo>;
var
  LoadedPlugin: TLoadedPlugin;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FLoadedPlugins.Count);
    I := 0;
    for LoadedPlugin in FLoadedPlugins.Values do
    begin
      Result[I] := LoadedPlugin.Plugin.Info;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

function TPluginLoader.IsPluginLoaded(const PluginId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FLoadedPlugins.ContainsKey(PluginId);
  finally
    FLock.Leave;
  end;
end;

function TPluginLoader.GetPluginCount: Integer;
begin
  FLock.Enter;
  try
    Result := FLoadedPlugins.Count;
  finally
    FLock.Leave;
  end;
end;

function TPluginLoader.GetAllActionExecutors: TArray<IPluginActionExecutor>;
var
  LoadedPlugin: TLoadedPlugin;
  Executors: TArray<IPluginActionExecutor>;
  ResultList: TList<IPluginActionExecutor>;
  Executor: IPluginActionExecutor;
begin
  ResultList := TList<IPluginActionExecutor>.Create;
  try
    FLock.Enter;
    try
      for LoadedPlugin in FLoadedPlugins.Values do
      begin
        Executors := LoadedPlugin.Plugin.GetActionExecutors;
        for Executor in Executors do
          ResultList.Add(Executor);
      end;
    finally
      FLock.Leave;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginLoader.GetAllValidators: TArray<IPluginValidator>;
var
  LoadedPlugin: TLoadedPlugin;
  Validators: TArray<IPluginValidator>;
  ResultList: TList<IPluginValidator>;
  Validator: IPluginValidator;
begin
  ResultList := TList<IPluginValidator>.Create;
  try
    FLock.Enter;
    try
      for LoadedPlugin in FLoadedPlugins.Values do
      begin
        Validators := LoadedPlugin.Plugin.GetValidators;
        for Validator in Validators do
          ResultList.Add(Validator);
      end;
    finally
      FLock.Leave;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginLoader.GetAllEventHandlers: TArray<IPluginEventHandler>;
var
  LoadedPlugin: TLoadedPlugin;
  Handlers: TArray<IPluginEventHandler>;
  ResultList: TList<IPluginEventHandler>;
  Handler: IPluginEventHandler;
begin
  ResultList := TList<IPluginEventHandler>.Create;
  try
    FLock.Enter;
    try
      for LoadedPlugin in FLoadedPlugins.Values do
      begin
        Handlers := LoadedPlugin.Plugin.GetEventHandlers;
        for Handler in Handlers do
          ResultList.Add(Handler);
      end;
    finally
      FLock.Leave;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginLoader.GetAllTransformers: TArray<IPluginTransformer>;
var
  LoadedPlugin: TLoadedPlugin;
  Transformers: TArray<IPluginTransformer>;
  ResultList: TList<IPluginTransformer>;
  Transformer: IPluginTransformer;
begin
  ResultList := TList<IPluginTransformer>.Create;
  try
    FLock.Enter;
    try
      for LoadedPlugin in FLoadedPlugins.Values do
      begin
        Transformers := LoadedPlugin.Plugin.GetTransformers;
        for Transformer in Transformers do
          ResultList.Add(Transformer);
      end;
    finally
      FLock.Leave;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginLoader.FindActionExecutor(const ActionType: string): IPluginActionExecutor;
var
  Executors: TArray<IPluginActionExecutor>;
  Executor: IPluginActionExecutor;
begin
  Result := nil;
  Executors := GetAllActionExecutors;
  for Executor in Executors do
    if Executor.CanHandle(ActionType) then
      Exit(Executor);
end;

function TPluginLoader.FindValidator(const ValidatorType: string): IPluginValidator;
var
  Validators: TArray<IPluginValidator>;
  Validator: IPluginValidator;
begin
  Result := nil;
  Validators := GetAllValidators;
  for Validator in Validators do
    if Validator.CanHandle(ValidatorType) then
      Exit(Validator);
end;

end.
