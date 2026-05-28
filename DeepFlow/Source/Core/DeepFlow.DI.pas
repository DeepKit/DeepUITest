unit UniFlow.DI;
(*
  UniFlow Dependency Injection Container
  ======================================
  ARCH-001: 轻量级依赖注入支�?
  
  功能:
  - 单例与瞬态生命周�?
  - 接口到实现的注册
  - 工厂函数支持
  - 自动解析依赖
  - 线程安全
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Rtti,
  System.SyncObjs, System.TypInfo,
  DeepBase.Exceptions;

type
  // ============================================================================
  // 生命周期
  // ============================================================================
  
  TServiceLifetime = (
    slTransient,   // 每次请求创建新实�?
    slSingleton,   // 全局单例
    slScoped       // 作用域单�?(每个 Scope 一个实�?
  );
  
  // ============================================================================
  // 服务描述�?
  // ============================================================================
  
  TServiceDescriptor = class
  private
    FServiceType: PTypeInfo;
    FImplementationType: PTypeInfo;
    FLifetime: TServiceLifetime;
    FFactory: TFunc<TObject>;
    FSingletonInstance: TObject;
    FOwnsSingleton: Boolean;
  public
    constructor Create(AServiceType: PTypeInfo; ALifetime: TServiceLifetime);
    destructor Destroy; override;
    
    property ServiceType: PTypeInfo read FServiceType;
    property ImplementationType: PTypeInfo read FImplementationType write FImplementationType;
    property Lifetime: TServiceLifetime read FLifetime write FLifetime;
    property Factory: TFunc<TObject> read FFactory write FFactory;
    property SingletonInstance: TObject read FSingletonInstance write FSingletonInstance;
    property OwnsSingleton: Boolean read FOwnsSingleton write FOwnsSingleton;
  end;
  
  // ============================================================================
  // 服务集合 (用于配置)
  // ============================================================================
  
  TServiceCollection = class;
  
  IServiceProvider = interface
    ['{D1E2F3A4-B5C6-4D7E-8F9A-0B1C2D3E4F5A}']
    function GetService(AServiceType: PTypeInfo): TObject;
    function GetRequiredService(AServiceType: PTypeInfo): TObject;
  end;
  
  TServiceCollection = class
  private
    FDescriptors: TObjectList<TServiceDescriptor>;
    FLock: TCriticalSection;
    
    function FindDescriptor(AServiceType: PTypeInfo): TServiceDescriptor;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>注册单例服务</summary>
    function AddSingleton<TService: class>: TServiceCollection; overload;
    function AddSingleton<TService: class>(AInstance: TService): TServiceCollection; overload;
    function AddSingleton<TService: class>(AFactory: TFunc<TObject>): TServiceCollection; overload;
    function AddSingleton<TService: IInterface; TImpl: class>: TServiceCollection; overload;
    
    /// <summary>注册瞬态服�?/summary>
    function AddTransient<TService: class>: TServiceCollection; overload;
    function AddTransient<TService: class>(AFactory: TFunc<TObject>): TServiceCollection; overload;
    function AddTransient<TService: IInterface; TImpl: class>: TServiceCollection; overload;
    
    /// <summary>注册作用域服�?/summary>
    function AddScoped<TService: class>: TServiceCollection; overload;
    function AddScoped<TService: class>(AFactory: TFunc<TObject>): TServiceCollection; overload;
    
    /// <summary>构建服务提供�?/summary>
    function BuildServiceProvider: IServiceProvider;
    
    property Descriptors: TObjectList<TServiceDescriptor> read FDescriptors;
  end;
  
  // ============================================================================
  // 服务提供�?
  // ============================================================================
  
  TServiceProvider = class(TInterfacedObject, IServiceProvider)
  private
    FDescriptors: TObjectList<TServiceDescriptor>;
    FSingletons: TDictionary<PTypeInfo, TObject>;
    FLock: TCriticalSection;
    FOwnsDescriptors: Boolean;
    FRttiContext: TRttiContext;
    
    function CreateInstance(ADescriptor: TServiceDescriptor): TObject;
    function ResolveConstructorParams(AType: TRttiType): TArray<TValue>;
  public
    constructor Create(ADescriptors: TObjectList<TServiceDescriptor>; AOwnsDescriptors: Boolean);
    destructor Destroy; override;
    
    function GetService(AServiceType: PTypeInfo): TObject;
    function GetRequiredService(AServiceType: PTypeInfo): TObject;
    
    /// <summary>泛型获取服务</summary>
    function Resolve<T: class>: T;
    function TryResolve<T: class>(out AInstance: T): Boolean;
  end;
  
  // ============================================================================
  // 服务作用�?
  // ============================================================================
  
  TServiceScope = class
  private
    FProvider: TServiceProvider;
    FScopedInstances: TDictionary<PTypeInfo, TObject>;
    FLock: TCriticalSection;
  public
    constructor Create(AProvider: TServiceProvider);
    destructor Destroy; override;
    
    function GetService(AServiceType: PTypeInfo): TObject;
    function Resolve<T: class>: T;
  end;
  
  // ============================================================================
  // 全局容器 (便捷访问)
  // ============================================================================
  
  TContainer = class
  private
    class var FInstance: TServiceCollection;
    class var FProvider: IServiceProvider;
  public
    class constructor Create;
    class destructor Destroy;
    
    class function Services: TServiceCollection;
    class function Provider: IServiceProvider;
    class procedure Build;
    class procedure Reset;
    
    class function Resolve<T: class>: T;
  end;

implementation

{ TServiceDescriptor }

constructor TServiceDescriptor.Create(AServiceType: PTypeInfo; ALifetime: TServiceLifetime);
begin
  inherited Create;
  FServiceType := AServiceType;
  FImplementationType := AServiceType;
  FLifetime := ALifetime;
  FSingletonInstance := nil;
  FOwnsSingleton := False;
end;

destructor TServiceDescriptor.Destroy;
begin
  if FOwnsSingleton and (FSingletonInstance <> nil) then
    FSingletonInstance.Free;
  inherited;
end;

{ TServiceCollection }

constructor TServiceCollection.Create;
begin
  inherited Create;
  FDescriptors := TObjectList<TServiceDescriptor>.Create(True);
  FLock := TCriticalSection.Create;
end;

destructor TServiceCollection.Destroy;
begin
  FDescriptors.Free;
  FLock.Free;
  inherited;
end;

function TServiceCollection.FindDescriptor(AServiceType: PTypeInfo): TServiceDescriptor;
begin
  Result := nil;
  for var Desc in FDescriptors do
  begin
    if Desc.ServiceType = AServiceType then
      Exit(Desc);
  end;
end;

function TServiceCollection.AddSingleton<TService>: TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slSingleton);
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddSingleton<TService>(AInstance: TService): TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slSingleton);
    Desc.SingletonInstance := AInstance;
    Desc.OwnsSingleton := False;  // 外部提供的实例，不拥有所有权
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddSingleton<TService>(AFactory: TFunc<TObject>): TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slSingleton);
    Desc.Factory := AFactory;
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddSingleton<TService, TImpl>: TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slSingleton);
    Desc.ImplementationType := TypeInfo(TImpl);
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddTransient<TService>: TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slTransient);
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddTransient<TService>(AFactory: TFunc<TObject>): TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slTransient);
    Desc.Factory := AFactory;
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddTransient<TService, TImpl>: TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slTransient);
    Desc.ImplementationType := TypeInfo(TImpl);
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddScoped<TService>: TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slScoped);
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.AddScoped<TService>(AFactory: TFunc<TObject>): TServiceCollection;
var
  Desc: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Desc := TServiceDescriptor.Create(TypeInfo(TService), slScoped);
    Desc.Factory := AFactory;
    FDescriptors.Add(Desc);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function TServiceCollection.BuildServiceProvider: IServiceProvider;
var
  DescriptorsCopy: TObjectList<TServiceDescriptor>;
  Desc, NewDesc: TServiceDescriptor;
begin
  // 创建描述符副本给 Provider
  DescriptorsCopy := TObjectList<TServiceDescriptor>.Create(True);
  
  FLock.Enter;
  try
    for Desc in FDescriptors do
    begin
      NewDesc := TServiceDescriptor.Create(Desc.ServiceType, Desc.Lifetime);
      NewDesc.ImplementationType := Desc.ImplementationType;
      NewDesc.Factory := Desc.Factory;
      NewDesc.SingletonInstance := Desc.SingletonInstance;
      NewDesc.OwnsSingleton := Desc.OwnsSingleton;
      DescriptorsCopy.Add(NewDesc);
    end;
  finally
    FLock.Leave;
  end;
  
  Result := TServiceProvider.Create(DescriptorsCopy, True);
end;

{ TServiceProvider }

constructor TServiceProvider.Create(ADescriptors: TObjectList<TServiceDescriptor>; AOwnsDescriptors: Boolean);
begin
  inherited Create;
  FDescriptors := ADescriptors;
  FOwnsDescriptors := AOwnsDescriptors;
  FSingletons := TDictionary<PTypeInfo, TObject>.Create;
  FLock := TCriticalSection.Create;
  FRttiContext := TRttiContext.Create;
end;

destructor TServiceProvider.Destroy;
begin
  // 释放单例
  for var Obj in FSingletons.Values do
    Obj.Free;
  FSingletons.Free;
  
  if FOwnsDescriptors then
    FDescriptors.Free;
  
  FLock.Free;
  FRttiContext.Free;
  inherited;
end;

function TServiceProvider.CreateInstance(ADescriptor: TServiceDescriptor): TObject;
var
  RttiType: TRttiType;
  RttiMethod: TRttiMethod;
  Params: TArray<TValue>;
begin
  // 使用工厂
  if Assigned(ADescriptor.Factory) then
    Exit(ADescriptor.Factory());
  
  // 使用 RTTI 创建实例
  RttiType := FRttiContext.GetType(ADescriptor.ImplementationType);
  if RttiType = nil then
    raise EOperationException.CreateFmt('Cannot resolve type: %s', [string(ADescriptor.ImplementationType.Name)]);
  
  // 查找构造函�?
  for RttiMethod in RttiType.GetMethods do
  begin
    if RttiMethod.IsConstructor and (RttiMethod.Name = 'Create') then
    begin
      Params := ResolveConstructorParams(RttiType);
      if Length(Params) = Length(RttiMethod.GetParameters) then
      begin
        Result := RttiMethod.Invoke(RttiType.AsInstance.MetaclassType, Params).AsObject;
        Exit;
      end;
    end;
  end;
  
  // 默认无参构�?
  Result := RttiType.AsInstance.MetaclassType.Create;
end;

function TServiceProvider.ResolveConstructorParams(AType: TRttiType): TArray<TValue>;
var
  RttiMethod: TRttiMethod;
  Params: TArray<TRttiParameter>;
  ParamObj: TObject;
begin
  Result := [];
  
  // 查找有参构造函�?
  for RttiMethod in AType.GetMethods do
  begin
    if RttiMethod.IsConstructor and (RttiMethod.Name = 'Create') then
    begin
      Params := RttiMethod.GetParameters;
      if Length(Params) > 0 then
      begin
        SetLength(Result, Length(Params));
        for var I := 0 to High(Params) do
        begin
          ParamObj := GetService(Params[I].ParamType.Handle);
          if ParamObj <> nil then
            Result[I] := TValue.From<TObject>(ParamObj)
          else
            Result[I] := TValue.Empty;
        end;
        Exit;
      end;
    end;
  end;
end;

function TServiceProvider.GetService(AServiceType: PTypeInfo): TObject;
var
  Desc: TServiceDescriptor;
begin
  Result := nil;
  
  FLock.Enter;
  try
    // 查找描述�?
    Desc := nil;
    for var D in FDescriptors do
    begin
      if D.ServiceType = AServiceType then
      begin
        Desc := D;
        Break;
      end;
    end;
    
    if Desc = nil then
      Exit(nil);
    
    case Desc.Lifetime of
      slSingleton:
      begin
        // 检查已有实�?
        if Desc.SingletonInstance <> nil then
          Exit(Desc.SingletonInstance);
        
        if FSingletons.TryGetValue(AServiceType, Result) then
          Exit;
        
        // 创建新实�?
        Result := CreateInstance(Desc);
        FSingletons.Add(AServiceType, Result);
        Desc.SingletonInstance := Result;
      end;
      
      slTransient:
        Result := CreateInstance(Desc);
      
      slScoped:
        Result := CreateInstance(Desc);  // Scope �?TServiceScope 管理
    end;
  finally
    FLock.Leave;
  end;
end;

function TServiceProvider.GetRequiredService(AServiceType: PTypeInfo): TObject;
begin
  Result := GetService(AServiceType);
  if Result = nil then
    raise EOperationException.CreateFmt('Service not registered: %s', [string(AServiceType.Name)]);
end;

function TServiceProvider.Resolve<T>: T;
begin
  Result := T(GetRequiredService(TypeInfo(T)));
end;

function TServiceProvider.TryResolve<T>(out AInstance: T): Boolean;
var
  Obj: TObject;
begin
  Obj := GetService(TypeInfo(T));
  Result := Obj <> nil;
  if Result then
    AInstance := T(Obj)
  else
    AInstance := nil;
end;

{ TServiceScope }

constructor TServiceScope.Create(AProvider: TServiceProvider);
begin
  inherited Create;
  FProvider := AProvider;
  FScopedInstances := TDictionary<PTypeInfo, TObject>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TServiceScope.Destroy;
begin
  // 释放作用域内的实�?
  for var Obj in FScopedInstances.Values do
    Obj.Free;
  FScopedInstances.Free;
  FLock.Free;
  inherited;
end;

function TServiceScope.GetService(AServiceType: PTypeInfo): TObject;
begin
  FLock.Enter;
  try
    // 先检查作用域缓存
    if FScopedInstances.TryGetValue(AServiceType, Result) then
      Exit;
    
    // �?Provider 获取
    Result := FProvider.GetService(AServiceType);
    
    // 缓存 Scoped 实例
    if Result <> nil then
      FScopedInstances.Add(AServiceType, Result);
  finally
    FLock.Leave;
  end;
end;

function TServiceScope.Resolve<T>: T;
begin
  Result := T(GetService(TypeInfo(T)));
end;

{ TContainer }

class constructor TContainer.Create;
begin
  FInstance := TServiceCollection.Create;
  FProvider := nil;
end;

class destructor TContainer.Destroy;
begin
  FProvider := nil;
  FInstance.Free;
end;

class function TContainer.Services: TServiceCollection;
begin
  Result := FInstance;
end;

class function TContainer.Provider: IServiceProvider;
begin
  if FProvider = nil then
    Build;
  Result := FProvider;
end;

class procedure TContainer.Build;
begin
  FProvider := FInstance.BuildServiceProvider;
end;

class procedure TContainer.Reset;
begin
  FProvider := nil;
  FInstance.Free;
  FInstance := TServiceCollection.Create;
end;

class function TContainer.Resolve<T>: T;
begin
  Result := (Provider as TServiceProvider).Resolve<T>;
end;

end.
