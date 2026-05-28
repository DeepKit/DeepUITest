(*******************************************************************************
                                                                               
  UniFlow Plugin Registry                                                      
  Central plugin management and lifecycle control                              
                                                                               
  Features:                                                                    
  - TPluginRegistry: Central plugin manager                                    
  - TPluginDependencyResolver: Dependency resolution                           
  - TPluginLifecycleManager: Lifecycle management                              
  - Enable/Disable plugins at runtime                                          
  - Query plugins by capability                                                
                                                                               
*******************************************************************************)

unit UniFlow.Plugin.Registry;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.SyncObjs,
  UniFlow.Plugin.Intf,
  UniFlow.Plugin.Loader;

type
  //----------------------------------------------------------------------------
  // Forward declarations
  //----------------------------------------------------------------------------
  
  TPluginRegistry = class;
  TPluginDependencyResolver = class;
  TPluginLifecycleManager = class;
  
  //----------------------------------------------------------------------------
  // Plugin entry in registry
  //----------------------------------------------------------------------------
  
  TPluginEntry = class
  private
    FPlugin: IUniFlowPlugin;
    FInfo: TPluginInfo;
    FEnabled: Boolean;
    FLoadTime: TDateTime;
    FContext: IPluginContext;
  public
    constructor Create(APlugin: IUniFlowPlugin);
    
    property Plugin: IUniFlowPlugin read FPlugin;
    property Info: TPluginInfo read FInfo write FInfo;
    property Enabled: Boolean read FEnabled write FEnabled;
    property LoadTime: TDateTime read FLoadTime;
    property Context: IPluginContext read FContext write FContext;
  end;
  
  //----------------------------------------------------------------------------
  // Dependency graph node
  //----------------------------------------------------------------------------
  
  TDependencyNode = class
  private
    FPluginId: string;
    FDependencies: TList<string>;
    FDependents: TList<string>;
    FVisited: Boolean;
    FInStack: Boolean;
  public
    constructor Create(const APluginId: string);
    destructor Destroy; override;
    
    property PluginId: string read FPluginId;
    property Dependencies: TList<string> read FDependencies;
    property Dependents: TList<string> read FDependents;
    property Visited: Boolean read FVisited write FVisited;
    property InStack: Boolean read FInStack write FInStack;
  end;
  
  //----------------------------------------------------------------------------
  // Dependency resolution result
  //----------------------------------------------------------------------------
  
  TDependencyResult = record
    Success: Boolean;
    Order: TArray<string>;       // Topologically sorted plugin IDs
    MissingDeps: TArray<string>; // Missing dependencies
    CircularDeps: TArray<string>; // Plugins in circular dependency
    ErrorMessage: string;
    
    class function OK(const AOrder: TArray<string>): TDependencyResult; static;
    class function Fail(const AMessage: string): TDependencyResult; static;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginDependencyResolver - Resolves plugin dependencies
  //----------------------------------------------------------------------------
  
  TPluginDependencyResolver = class
  private
    FNodes: TObjectDictionary<string, TDependencyNode>;
    FMissing: TList<string>;
    FCircular: TList<string>;
    
    procedure BuildGraph(const Plugins: TArray<TPluginInfo>);
    procedure Reset;
    function TopologicalSort: TArray<string>;
    function DetectCycle(Node: TDependencyNode; var Cycle: TList<string>): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>Resolve dependencies and return load order</summary>
    function Resolve(const Plugins: TArray<TPluginInfo>): TDependencyResult;
    /// <summary>Check if a specific plugin's dependencies are satisfied</summary>
    function CheckDependencies(const PluginInfo: TPluginInfo; 
      const LoadedPlugins: TArray<string>): TDependencyResult;
    /// <summary>Get dependent plugins (plugins that depend on the given plugin)</summary>
    function GetDependents(const PluginId: string): TArray<string>;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginLifecycleManager - Manages plugin lifecycle
  //----------------------------------------------------------------------------
  
  TLifecycleState = (lsUnknown, lsLoaded, lsInitializing, lsActive, lsFinalizing, lsUnloaded);
  
  TPluginLifecycleEvent = procedure(Sender: TObject; const PluginId: string; 
    OldState, NewState: TLifecycleState) of object;
  
  TPluginLifecycleManager = class
  private
    FStates: TDictionary<string, TLifecycleState>;
    FInitOrder: TList<string>;
    FLock: TCriticalSection;
    FOnStateChange: TPluginLifecycleEvent;
    
    procedure SetState(const PluginId: string; NewState: TLifecycleState);
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>Register a plugin for lifecycle management</summary>
    procedure Register(const PluginId: string);
    /// <summary>Unregister a plugin</summary>
    procedure Unregister(const PluginId: string);
    
    /// <summary>Mark plugin as initializing</summary>
    procedure BeginInitialize(const PluginId: string);
    /// <summary>Mark plugin as active (initialized successfully)</summary>
    procedure EndInitialize(const PluginId: string; Success: Boolean);
    /// <summary>Mark plugin as finalizing</summary>
    procedure BeginFinalize(const PluginId: string);
    /// <summary>Mark plugin as unloaded</summary>
    procedure EndFinalize(const PluginId: string);
    
    /// <summary>Get current state of a plugin</summary>
    function GetState(const PluginId: string): TLifecycleState;
    /// <summary>Get initialization order</summary>
    function GetInitOrder: TArray<string>;
    /// <summary>Get finalization order (reverse of init order)</summary>
    function GetFinalizeOrder: TArray<string>;
    
    property OnStateChange: TPluginLifecycleEvent read FOnStateChange write FOnStateChange;
  end;
  
  //----------------------------------------------------------------------------
  // TPluginRegistry - Central plugin manager
  //----------------------------------------------------------------------------
  
  TPluginQueryResult = record
    Success: Boolean;
    Plugins: TArray<IUniFlowPlugin>;
    ErrorMessage: string;
  end;
  
  TPluginRegistryConfig = record
    /// <summary>Enable automatic dependency resolution</summary>
    AutoResolveDependencies: Boolean;
    /// <summary>Allow plugins with missing dependencies to load</summary>
    AllowMissingDependencies: Boolean;
    /// <summary>Config directory for plugin configurations</summary>
    ConfigDir: string;
    /// <summary>Shared plugin context services</summary>
    SharedServices: IPluginServices;
    
    class function Default: TPluginRegistryConfig; static;
  end;
  
  TOnRegistryEvent = procedure(Sender: TObject; const PluginId: string) of object;
  TOnRegistryError = procedure(Sender: TObject; const PluginId, ErrorMessage: string) of object;
  
  TPluginRegistry = class
  private
    FConfig: TPluginRegistryConfig;
    FPlugins: TObjectDictionary<string, TPluginEntry>;
    FLoader: TPluginLoader;
    FDependencyResolver: TPluginDependencyResolver;
    FLifecycleManager: TPluginLifecycleManager;
    FLock: TCriticalSection;
    FOwnsLoader: Boolean;
    
    FOnPluginRegistered: TOnRegistryEvent;
    FOnPluginUnregistered: TOnRegistryEvent;
    FOnPluginEnabled: TOnRegistryEvent;
    FOnPluginDisabled: TOnRegistryEvent;
    FOnError: TOnRegistryError;
    
    procedure DoPluginRegistered(const PluginId: string);
    procedure DoPluginUnregistered(const PluginId: string);
    procedure DoPluginEnabled(const PluginId: string);
    procedure DoPluginDisabled(const PluginId: string);
    procedure DoError(const PluginId, ErrorMessage: string);
    
    function GetPluginEntry(const PluginId: string): TPluginEntry;
  public
    constructor Create(const AConfig: TPluginRegistryConfig); overload;
    constructor Create(ALoader: TPluginLoader; AOwnsLoader: Boolean = False); overload;
    destructor Destroy; override;
    
    /// <summary>Register a plugin</summary>
    function RegisterPlugin(Plugin: IUniFlowPlugin; Context: IPluginContext = nil): Boolean;
    /// <summary>Unregister a plugin by ID</summary>
    procedure UnregisterPlugin(const PluginId: string);
    /// <summary>Unregister all plugins</summary>
    procedure UnregisterAll;
    
    /// <summary>Load and register plugin from file</summary>
    function LoadAndRegister(const FilePath: string): Boolean;
    /// <summary>Discover and register all plugins from directory</summary>
    function DiscoverAndRegister(const Directory: string = ''): Integer;
    
    /// <summary>Get plugin by ID</summary>
    function GetPlugin(const PluginId: string): IUniFlowPlugin;
    /// <summary>Get all registered plugins</summary>
    function GetAllPlugins: TArray<IUniFlowPlugin>;
    /// <summary>Get all enabled plugins</summary>
    function GetEnabledPlugins: TArray<IUniFlowPlugin>;
    /// <summary>Get plugin info list</summary>
    function GetPluginInfoList: TArray<TPluginInfo>;
    
    /// <summary>Check if plugin is registered</summary>
    function IsRegistered(const PluginId: string): Boolean;
    /// <summary>Check if plugin is enabled</summary>
    function IsEnabled(const PluginId: string): Boolean;
    /// <summary>Get plugin count</summary>
    function GetPluginCount: Integer;
    
    /// <summary>Enable a plugin</summary>
    function EnablePlugin(const PluginId: string): Boolean;
    /// <summary>Disable a plugin</summary>
    function DisablePlugin(const PluginId: string): Boolean;
    
    /// <summary>Query plugins by capability</summary>
    function GetPluginsByCapability(Capability: TPluginCapability): TArray<IUniFlowPlugin>;
    /// <summary>Get all action executors</summary>
    function GetActionExecutors: TArray<IPluginActionExecutor>;
    /// <summary>Get all validators</summary>
    function GetValidators: TArray<IPluginValidator>;
    /// <summary>Get all event handlers</summary>
    function GetEventHandlers: TArray<IPluginEventHandler>;
    /// <summary>Get all transformers</summary>
    function GetTransformers: TArray<IPluginTransformer>;
    
    /// <summary>Find action executor by type</summary>
    function FindActionExecutor(const ActionType: string): IPluginActionExecutor;
    /// <summary>Find validator by type</summary>
    function FindValidator(const ValidatorType: string): IPluginValidator;
    
    /// <summary>Get dependency resolver</summary>
    property DependencyResolver: TPluginDependencyResolver read FDependencyResolver;
    /// <summary>Get lifecycle manager</summary>
    property LifecycleManager: TPluginLifecycleManager read FLifecycleManager;
    /// <summary>Get plugin loader</summary>
    property Loader: TPluginLoader read FLoader;
    
    // Events
    property OnPluginRegistered: TOnRegistryEvent read FOnPluginRegistered write FOnPluginRegistered;
    property OnPluginUnregistered: TOnRegistryEvent read FOnPluginUnregistered write FOnPluginUnregistered;
    property OnPluginEnabled: TOnRegistryEvent read FOnPluginEnabled write FOnPluginEnabled;
    property OnPluginDisabled: TOnRegistryEvent read FOnPluginDisabled write FOnPluginDisabled;
    property OnError: TOnRegistryError read FOnError write FOnError;
  end;
  
  //----------------------------------------------------------------------------
  // Global registry instance
  //----------------------------------------------------------------------------
  
  /// <summary>Get global plugin registry instance</summary>
  function PluginRegistry: TPluginRegistry;
  /// <summary>Initialize global plugin registry</summary>
  procedure InitializePluginRegistry(const Config: TPluginRegistryConfig);
  /// <summary>Finalize global plugin registry</summary>
  procedure FinalizePluginRegistry;

implementation

uses
  System.DateUtils;

var
  GPluginRegistry: TPluginRegistry = nil;
  GRegistryLock: TCriticalSection = nil;

//------------------------------------------------------------------------------
// Global functions
//------------------------------------------------------------------------------

function PluginRegistry: TPluginRegistry;
begin
  if GPluginRegistry = nil then
  begin
    GRegistryLock.Enter;
    try
      if GPluginRegistry = nil then
        GPluginRegistry := TPluginRegistry.Create(TPluginRegistryConfig.Default);
    finally
      GRegistryLock.Leave;
    end;
  end;
  Result := GPluginRegistry;
end;

procedure InitializePluginRegistry(const Config: TPluginRegistryConfig);
begin
  GRegistryLock.Enter;
  try
    FreeAndNil(GPluginRegistry);
    GPluginRegistry := TPluginRegistry.Create(Config);
  finally
    GRegistryLock.Leave;
  end;
end;

procedure FinalizePluginRegistry;
begin
  GRegistryLock.Enter;
  try
    FreeAndNil(GPluginRegistry);
  finally
    GRegistryLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TPluginEntry
//------------------------------------------------------------------------------

constructor TPluginEntry.Create(APlugin: IUniFlowPlugin);
begin
  inherited Create;
  FPlugin := APlugin;
  FInfo := APlugin.Info;
  FEnabled := True;
  FLoadTime := Now;
end;

//------------------------------------------------------------------------------
// TDependencyNode
//------------------------------------------------------------------------------

constructor TDependencyNode.Create(const APluginId: string);
begin
  inherited Create;
  FPluginId := APluginId;
  FDependencies := TList<string>.Create;
  FDependents := TList<string>.Create;
  FVisited := False;
  FInStack := False;
end;

destructor TDependencyNode.Destroy;
begin
  FDependents.Free;
  FDependencies.Free;
  inherited;
end;

//------------------------------------------------------------------------------
// TDependencyResult
//------------------------------------------------------------------------------

class function TDependencyResult.OK(const AOrder: TArray<string>): TDependencyResult;
begin
  Result := Default(TDependencyResult);
  Result.Success := True;
  Result.Order := AOrder;
end;

class function TDependencyResult.Fail(const AMessage: string): TDependencyResult;
begin
  Result := Default(TDependencyResult);
  Result.Success := False;
  Result.ErrorMessage := AMessage;
end;

//------------------------------------------------------------------------------
// TPluginDependencyResolver
//------------------------------------------------------------------------------

constructor TPluginDependencyResolver.Create;
begin
  inherited Create;
  FNodes := TObjectDictionary<string, TDependencyNode>.Create([doOwnsValues]);
  FMissing := TList<string>.Create;
  FCircular := TList<string>.Create;
end;

destructor TPluginDependencyResolver.Destroy;
begin
  FCircular.Free;
  FMissing.Free;
  FNodes.Free;
  inherited;
end;

procedure TPluginDependencyResolver.BuildGraph(const Plugins: TArray<TPluginInfo>);
var
  Info: TPluginInfo;
  Node, DepNode: TDependencyNode;
  DepId: string;
begin
  FNodes.Clear;
  FMissing.Clear;
  
  // Create nodes for all plugins
  for Info in Plugins do
  begin
    Node := TDependencyNode.Create(Info.Id);
    FNodes.Add(Info.Id, Node);
  end;
  
  // Build edges
  for Info in Plugins do
  begin
    Node := FNodes[Info.Id];
    for DepId in Info.Dependencies do
    begin
      Node.Dependencies.Add(DepId);
      
      if FNodes.TryGetValue(DepId, DepNode) then
        DepNode.Dependents.Add(Info.Id)
      else if not FMissing.Contains(DepId) then
        FMissing.Add(DepId);
    end;
  end;
end;

procedure TPluginDependencyResolver.Reset;
var
  Node: TDependencyNode;
begin
  for Node in FNodes.Values do
  begin
    Node.Visited := False;
    Node.InStack := False;
  end;
  FCircular.Clear;
end;

function TPluginDependencyResolver.DetectCycle(Node: TDependencyNode; 
  var Cycle: TList<string>): Boolean;
var
  DepId: string;
  DepNode: TDependencyNode;
begin
  Result := False;
  Node.Visited := True;
  Node.InStack := True;
  
  for DepId in Node.Dependencies do
  begin
    if FNodes.TryGetValue(DepId, DepNode) then
    begin
      if not DepNode.Visited then
      begin
        if DetectCycle(DepNode, Cycle) then
        begin
          if Cycle.Contains(Node.PluginId) then
            Exit(True);
          Cycle.Add(Node.PluginId);
          Exit(True);
        end;
      end
      else if DepNode.InStack then
      begin
        // Cycle detected
        Cycle.Add(DepId);
        Cycle.Add(Node.PluginId);
        Exit(True);
      end;
    end;
  end;
  
  Node.InStack := False;
end;

function TPluginDependencyResolver.TopologicalSort: TArray<string>;
var
  ResultList: TList<string>;
  Node: TDependencyNode;
  Changed: Boolean;
  Processed: TDictionary<string, Boolean>;
  AllDepsProcessed: Boolean;
  DepId: string;
begin
  ResultList := TList<string>.Create;
  Processed := TDictionary<string, Boolean>.Create;
  try
    // Initialize
    for Node in FNodes.Values do
      Processed.Add(Node.PluginId, False);
    
    // Kahn's algorithm
    repeat
      Changed := False;
      for Node in FNodes.Values do
      begin
        if Processed[Node.PluginId] then
          Continue;
        
        // Check if all dependencies are processed
        AllDepsProcessed := True;
        for DepId in Node.Dependencies do
        begin
          if FNodes.ContainsKey(DepId) and not Processed[DepId] then
          begin
            AllDepsProcessed := False;
            Break;
          end;
        end;
        
        if AllDepsProcessed then
        begin
          ResultList.Add(Node.PluginId);
          Processed[Node.PluginId] := True;
          Changed := True;
        end;
      end;
    until not Changed;
    
    Result := ResultList.ToArray;
  finally
    Processed.Free;
    ResultList.Free;
  end;
end;

function TPluginDependencyResolver.Resolve(const Plugins: TArray<TPluginInfo>): TDependencyResult;
var
  Node: TDependencyNode;
  Cycle: TList<string>;
  Order: TArray<string>;
begin
  BuildGraph(Plugins);
  
  // Check for missing dependencies
  if FMissing.Count > 0 then
  begin
    Result := TDependencyResult.Fail('Missing dependencies: ' + string.Join(', ', FMissing.ToArray));
    Result.MissingDeps := FMissing.ToArray;
    Exit;
  end;
  
  // Check for circular dependencies
  Reset;
  Cycle := TList<string>.Create;
  try
    for Node in FNodes.Values do
    begin
      if not Node.Visited then
      begin
        if DetectCycle(Node, Cycle) then
        begin
          Result := TDependencyResult.Fail('Circular dependency detected: ' + 
            string.Join(' -> ', Cycle.ToArray));
          Result.CircularDeps := Cycle.ToArray;
          Exit;
        end;
      end;
    end;
  finally
    Cycle.Free;
  end;
  
  // Topological sort
  Reset;
  Order := TopologicalSort;
  
  if Length(Order) <> Length(Plugins) then
  begin
    Result := TDependencyResult.Fail('Could not resolve all dependencies');
    Exit;
  end;
  
  Result := TDependencyResult.OK(Order);
end;

function TPluginDependencyResolver.CheckDependencies(const PluginInfo: TPluginInfo;
  const LoadedPlugins: TArray<string>): TDependencyResult;
var
  DepId: string;
  LoadedSet: TDictionary<string, Boolean>;
  Missing: TList<string>;
begin
  LoadedSet := TDictionary<string, Boolean>.Create;
  Missing := TList<string>.Create;
  try
    for DepId in LoadedPlugins do
      LoadedSet.Add(DepId, True);
    
    for DepId in PluginInfo.Dependencies do
    begin
      if not LoadedSet.ContainsKey(DepId) then
        Missing.Add(DepId);
    end;
    
    if Missing.Count > 0 then
    begin
      Result := TDependencyResult.Fail('Missing dependencies: ' + string.Join(', ', Missing.ToArray));
      Result.MissingDeps := Missing.ToArray;
    end
    else
      Result := TDependencyResult.OK([]);
  finally
    Missing.Free;
    LoadedSet.Free;
  end;
end;

function TPluginDependencyResolver.GetDependents(const PluginId: string): TArray<string>;
var
  Node: TDependencyNode;
begin
  if FNodes.TryGetValue(PluginId, Node) then
    Result := Node.Dependents.ToArray
  else
    SetLength(Result, 0);
end;

//------------------------------------------------------------------------------
// TPluginLifecycleManager
//------------------------------------------------------------------------------

constructor TPluginLifecycleManager.Create;
begin
  inherited Create;
  FStates := TDictionary<string, TLifecycleState>.Create;
  FInitOrder := TList<string>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TPluginLifecycleManager.Destroy;
begin
  FLock.Free;
  FInitOrder.Free;
  FStates.Free;
  inherited;
end;

procedure TPluginLifecycleManager.SetState(const PluginId: string; NewState: TLifecycleState);
var
  OldState: TLifecycleState;
begin
  FLock.Enter;
  try
    if not FStates.TryGetValue(PluginId, OldState) then
      OldState := lsUnknown;
    FStates.AddOrSetValue(PluginId, NewState);
  finally
    FLock.Leave;
  end;
  
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, PluginId, OldState, NewState);
end;

procedure TPluginLifecycleManager.Register(const PluginId: string);
begin
  FLock.Enter;
  try
    FStates.AddOrSetValue(PluginId, lsLoaded);
  finally
    FLock.Leave;
  end;
end;

procedure TPluginLifecycleManager.Unregister(const PluginId: string);
begin
  FLock.Enter;
  try
    FStates.Remove(PluginId);
    FInitOrder.Remove(PluginId);
  finally
    FLock.Leave;
  end;
end;

procedure TPluginLifecycleManager.BeginInitialize(const PluginId: string);
begin
  SetState(PluginId, lsInitializing);
end;

procedure TPluginLifecycleManager.EndInitialize(const PluginId: string; Success: Boolean);
begin
  if Success then
  begin
    SetState(PluginId, lsActive);
    FLock.Enter;
    try
      if not FInitOrder.Contains(PluginId) then
        FInitOrder.Add(PluginId);
    finally
      FLock.Leave;
    end;
  end
  else
    SetState(PluginId, lsLoaded);
end;

procedure TPluginLifecycleManager.BeginFinalize(const PluginId: string);
begin
  SetState(PluginId, lsFinalizing);
end;

procedure TPluginLifecycleManager.EndFinalize(const PluginId: string);
begin
  SetState(PluginId, lsUnloaded);
  FLock.Enter;
  try
    FInitOrder.Remove(PluginId);
  finally
    FLock.Leave;
  end;
end;

function TPluginLifecycleManager.GetState(const PluginId: string): TLifecycleState;
begin
  FLock.Enter;
  try
    if not FStates.TryGetValue(PluginId, Result) then
      Result := lsUnknown;
  finally
    FLock.Leave;
  end;
end;

function TPluginLifecycleManager.GetInitOrder: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FInitOrder.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TPluginLifecycleManager.GetFinalizeOrder: TArray<string>;
var
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FInitOrder.Count);
    for I := 0 to FInitOrder.Count - 1 do
      Result[I] := FInitOrder[FInitOrder.Count - 1 - I];
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TPluginRegistryConfig
//------------------------------------------------------------------------------

class function TPluginRegistryConfig.Default: TPluginRegistryConfig;
begin
  Result := System.Default(TPluginRegistryConfig);
  Result.AutoResolveDependencies := True;
  Result.AllowMissingDependencies := False;
  Result.ConfigDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'PluginConfig');
end;

//------------------------------------------------------------------------------
// TPluginRegistry
//------------------------------------------------------------------------------

constructor TPluginRegistry.Create(const AConfig: TPluginRegistryConfig);
var
  LoaderConfig: TPluginLoaderConfig;
begin
  inherited Create;
  FConfig := AConfig;
  FPlugins := TObjectDictionary<string, TPluginEntry>.Create([doOwnsValues]);
  FDependencyResolver := TPluginDependencyResolver.Create;
  FLifecycleManager := TPluginLifecycleManager.Create;
  FLock := TCriticalSection.Create;
  
  // Create loader
  LoaderConfig := TPluginLoaderConfig.Default;
  LoaderConfig.SharedServices := FConfig.SharedServices;
  FLoader := TPluginLoader.Create(LoaderConfig);
  FOwnsLoader := True;
  
  // Ensure config directory exists
  if not TDirectory.Exists(FConfig.ConfigDir) then
    TDirectory.CreateDirectory(FConfig.ConfigDir);
end;

constructor TPluginRegistry.Create(ALoader: TPluginLoader; AOwnsLoader: Boolean);
begin
  inherited Create;
  FConfig := TPluginRegistryConfig.Default;
  FPlugins := TObjectDictionary<string, TPluginEntry>.Create([doOwnsValues]);
  FDependencyResolver := TPluginDependencyResolver.Create;
  FLifecycleManager := TPluginLifecycleManager.Create;
  FLock := TCriticalSection.Create;
  FLoader := ALoader;
  FOwnsLoader := AOwnsLoader;
end;

destructor TPluginRegistry.Destroy;
begin
  UnregisterAll;
  FLock.Free;
  FLifecycleManager.Free;
  FDependencyResolver.Free;
  FPlugins.Free;
  if FOwnsLoader then
    FLoader.Free;
  inherited;
end;

procedure TPluginRegistry.DoPluginRegistered(const PluginId: string);
begin
  if Assigned(FOnPluginRegistered) then
    FOnPluginRegistered(Self, PluginId);
end;

procedure TPluginRegistry.DoPluginUnregistered(const PluginId: string);
begin
  if Assigned(FOnPluginUnregistered) then
    FOnPluginUnregistered(Self, PluginId);
end;

procedure TPluginRegistry.DoPluginEnabled(const PluginId: string);
begin
  if Assigned(FOnPluginEnabled) then
    FOnPluginEnabled(Self, PluginId);
end;

procedure TPluginRegistry.DoPluginDisabled(const PluginId: string);
begin
  if Assigned(FOnPluginDisabled) then
    FOnPluginDisabled(Self, PluginId);
end;

procedure TPluginRegistry.DoError(const PluginId, ErrorMessage: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, PluginId, ErrorMessage);
end;

function TPluginRegistry.GetPluginEntry(const PluginId: string): TPluginEntry;
begin
  FLock.Enter;
  try
    if not FPlugins.TryGetValue(PluginId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TPluginRegistry.RegisterPlugin(Plugin: IUniFlowPlugin; Context: IPluginContext): Boolean;
var
  Entry: TPluginEntry;
  PluginId: string;
  DepResult: TDependencyResult;
  LoadedIds: TArray<string>;
begin
  Result := False;
  if Plugin = nil then
    Exit;
  
  PluginId := Plugin.Info.Id;
  
  // Check if already registered
  FLock.Enter;
  try
    if FPlugins.ContainsKey(PluginId) then
    begin
      DoError(PluginId, 'Plugin already registered');
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  
  // Check dependencies if enabled
  if FConfig.AutoResolveDependencies then
  begin
    LoadedIds := GetLoadedPluginIds;
    DepResult := FDependencyResolver.CheckDependencies(Plugin.Info, LoadedIds);
    if not DepResult.Success then
    begin
      if not FConfig.AllowMissingDependencies then
      begin
        DoError(PluginId, DepResult.ErrorMessage);
        Exit;
      end;
    end;
  end;
  
  // Create entry
  Entry := TPluginEntry.Create(Plugin);
  Entry.Context := Context;
  
  FLock.Enter;
  try
    FPlugins.Add(PluginId, Entry);
  finally
    FLock.Leave;
  end;
  
  // Register with lifecycle manager
  FLifecycleManager.Register(PluginId);
  FLifecycleManager.EndInitialize(PluginId, True);
  
  DoPluginRegistered(PluginId);
  Result := True;
end;

function TPluginRegistry.GetLoadedPluginIds: TArray<string>;
var
  Entry: TPluginEntry;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FPlugins.Count);
    I := 0;
    for Entry in FPlugins.Values do
    begin
      Result[I] := Entry.Info.Id;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TPluginRegistry.UnregisterPlugin(const PluginId: string);
var
  Entry: TPluginEntry;
begin
  FLock.Enter;
  try
    if not FPlugins.TryGetValue(PluginId, Entry) then
      Exit;
    
    // Finalize lifecycle
    FLifecycleManager.BeginFinalize(PluginId);
    
    // Finalize plugin
    try
      Entry.Plugin.Finalize;
    except
      // Ignore finalization errors
    end;
    
    FLifecycleManager.EndFinalize(PluginId);
    FLifecycleManager.Unregister(PluginId);
    
    FPlugins.Remove(PluginId);
  finally
    FLock.Leave;
  end;
  
  DoPluginUnregistered(PluginId);
end;

procedure TPluginRegistry.UnregisterAll;
var
  FinalizeOrder: TArray<string>;
  PluginId: string;
begin
  // Get finalize order (reverse of init order)
  FinalizeOrder := FLifecycleManager.GetFinalizeOrder;
  
  // Unregister in order
  for PluginId in FinalizeOrder do
    UnregisterPlugin(PluginId);
  
  // Clear any remaining
  FLock.Enter;
  try
    FPlugins.Clear;
  finally
    FLock.Leave;
  end;
end;

function TPluginRegistry.LoadAndRegister(const FilePath: string): Boolean;
var
  LoadResult: TPluginLoadResult;
begin
  Result := False;
  LoadResult := FLoader.LoadPlugin(FilePath);
  if not LoadResult.Success then
  begin
    DoError('', LoadResult.ErrorMessage);
    Exit;
  end;
  
  Result := RegisterPlugin(LoadResult.Plugin);
end;

function TPluginRegistry.DiscoverAndRegister(const Directory: string): Integer;
var
  Results: TArray<TPluginLoadResult>;
  R: TPluginLoadResult;
begin
  Result := 0;
  
  if Directory = '' then
    Results := FLoader.ScanDirectory(FLoader.Config.PluginDir)
  else
    Results := FLoader.ScanDirectory(Directory);
  
  for R in Results do
  begin
    if R.Success then
    begin
      if RegisterPlugin(R.Plugin) then
        Inc(Result);
    end;
  end;
end;

function TPluginRegistry.GetPlugin(const PluginId: string): IUniFlowPlugin;
var
  Entry: TPluginEntry;
begin
  Entry := GetPluginEntry(PluginId);
  if Entry <> nil then
    Result := Entry.Plugin
  else
    Result := nil;
end;

function TPluginRegistry.GetAllPlugins: TArray<IUniFlowPlugin>;
var
  Entry: TPluginEntry;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FPlugins.Count);
    I := 0;
    for Entry in FPlugins.Values do
    begin
      Result[I] := Entry.Plugin;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

function TPluginRegistry.GetEnabledPlugins: TArray<IUniFlowPlugin>;
var
  Entry: TPluginEntry;
  ResultList: TList<IUniFlowPlugin>;
begin
  ResultList := TList<IUniFlowPlugin>.Create;
  try
    FLock.Enter;
    try
      for Entry in FPlugins.Values do
        if Entry.Enabled then
          ResultList.Add(Entry.Plugin);
    finally
      FLock.Leave;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginRegistry.GetPluginInfoList: TArray<TPluginInfo>;
var
  Entry: TPluginEntry;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FPlugins.Count);
    I := 0;
    for Entry in FPlugins.Values do
    begin
      Result[I] := Entry.Info;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

function TPluginRegistry.IsRegistered(const PluginId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FPlugins.ContainsKey(PluginId);
  finally
    FLock.Leave;
  end;
end;

function TPluginRegistry.IsEnabled(const PluginId: string): Boolean;
var
  Entry: TPluginEntry;
begin
  Entry := GetPluginEntry(PluginId);
  Result := (Entry <> nil) and Entry.Enabled;
end;

function TPluginRegistry.GetPluginCount: Integer;
begin
  FLock.Enter;
  try
    Result := FPlugins.Count;
  finally
    FLock.Leave;
  end;
end;

function TPluginRegistry.EnablePlugin(const PluginId: string): Boolean;
var
  Entry: TPluginEntry;
begin
  Result := False;
  Entry := GetPluginEntry(PluginId);
  if Entry = nil then
    Exit;
  
  if Entry.Enabled then
    Exit(True);
  
  Entry.Enabled := True;
  DoPluginEnabled(PluginId);
  Result := True;
end;

function TPluginRegistry.DisablePlugin(const PluginId: string): Boolean;
var
  Entry: TPluginEntry;
begin
  Result := False;
  Entry := GetPluginEntry(PluginId);
  if Entry = nil then
    Exit;
  
  if not Entry.Enabled then
    Exit(True);
  
  Entry.Enabled := False;
  DoPluginDisabled(PluginId);
  Result := True;
end;

function TPluginRegistry.GetPluginsByCapability(Capability: TPluginCapability): TArray<IUniFlowPlugin>;
var
  Entry: TPluginEntry;
  ResultList: TList<IUniFlowPlugin>;
begin
  ResultList := TList<IUniFlowPlugin>.Create;
  try
    FLock.Enter;
    try
      for Entry in FPlugins.Values do
        if Entry.Enabled and (Capability in Entry.Info.Capabilities) then
          ResultList.Add(Entry.Plugin);
    finally
      FLock.Leave;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginRegistry.GetActionExecutors: TArray<IPluginActionExecutor>;
var
  Plugins: TArray<IUniFlowPlugin>;
  Plugin: IUniFlowPlugin;
  Executors: TArray<IPluginActionExecutor>;
  Executor: IPluginActionExecutor;
  ResultList: TList<IPluginActionExecutor>;
begin
  ResultList := TList<IPluginActionExecutor>.Create;
  try
    Plugins := GetPluginsByCapability(pcActionExecutor);
    for Plugin in Plugins do
    begin
      Executors := Plugin.GetActionExecutors;
      for Executor in Executors do
        ResultList.Add(Executor);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginRegistry.GetValidators: TArray<IPluginValidator>;
var
  Plugins: TArray<IUniFlowPlugin>;
  Plugin: IUniFlowPlugin;
  Validators: TArray<IPluginValidator>;
  Validator: IPluginValidator;
  ResultList: TList<IPluginValidator>;
begin
  ResultList := TList<IPluginValidator>.Create;
  try
    Plugins := GetPluginsByCapability(pcValidator);
    for Plugin in Plugins do
    begin
      Validators := Plugin.GetValidators;
      for Validator in Validators do
        ResultList.Add(Validator);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginRegistry.GetEventHandlers: TArray<IPluginEventHandler>;
var
  Plugins: TArray<IUniFlowPlugin>;
  Plugin: IUniFlowPlugin;
  Handlers: TArray<IPluginEventHandler>;
  Handler: IPluginEventHandler;
  ResultList: TList<IPluginEventHandler>;
begin
  ResultList := TList<IPluginEventHandler>.Create;
  try
    Plugins := GetPluginsByCapability(pcEventHandler);
    for Plugin in Plugins do
    begin
      Handlers := Plugin.GetEventHandlers;
      for Handler in Handlers do
        ResultList.Add(Handler);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginRegistry.GetTransformers: TArray<IPluginTransformer>;
var
  Plugins: TArray<IUniFlowPlugin>;
  Plugin: IUniFlowPlugin;
  Transformers: TArray<IPluginTransformer>;
  Transformer: IPluginTransformer;
  ResultList: TList<IPluginTransformer>;
begin
  ResultList := TList<IPluginTransformer>.Create;
  try
    Plugins := GetPluginsByCapability(pcTransformer);
    for Plugin in Plugins do
    begin
      Transformers := Plugin.GetTransformers;
      for Transformer in Transformers do
        ResultList.Add(Transformer);
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TPluginRegistry.FindActionExecutor(const ActionType: string): IPluginActionExecutor;
var
  Executors: TArray<IPluginActionExecutor>;
  Executor: IPluginActionExecutor;
begin
  Result := nil;
  Executors := GetActionExecutors;
  for Executor in Executors do
    if Executor.CanHandle(ActionType) then
      Exit(Executor);
end;

function TPluginRegistry.FindValidator(const ValidatorType: string): IPluginValidator;
var
  Validators: TArray<IPluginValidator>;
  Validator: IPluginValidator;
begin
  Result := nil;
  Validators := GetValidators;
  for Validator in Validators do
    if Validator.CanHandle(ValidatorType) then
      Exit(Validator);
end;

function TPluginRegistry.GetLoadedPluginIds: TArray<string>;
var
  Entry: TPluginEntry;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FPlugins.Count);
    I := 0;
    for Entry in FPlugins.Values do
    begin
      Result[I] := Entry.Info.Id;
      Inc(I);
    end;
  finally
    FLock.Leave;
  end;
end;

initialization
  GRegistryLock := TCriticalSection.Create;

finalization
  FreeAndNil(GPluginRegistry);
  FreeAndNil(GRegistryLock);

end.
