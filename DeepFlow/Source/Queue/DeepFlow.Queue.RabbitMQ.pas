unit UniFlow.Queue.RabbitMQ;

{*******************************************************}
{                                                       }
{       UniFlow RabbitMQ 消息队列集成                   }
{                                                       }
{       版权所�?(C) 2024 UniFlow                       }
{                                                       }
{*******************************************************}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.SyncObjs, System.Threading, System.Net.HttpClient,
  System.NetEncoding, UniFlow.Queue.Types,
  DeepBase.Exceptions;

type
  {==========================================================================}
  {  RabbitMQ 连接接口                                                       }
  {==========================================================================}
  IRabbitMQConnection = interface
    ['{E8A1B2C3-D4E5-F6A7-B8C9-D0E1F2A3B4C5}']
    function GetState: TConnectionState;
    function GetConfig: TQueueConnectionConfig;
    
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    
    function CreateChannel: IRabbitMQChannel;
    
    property State: TConnectionState read GetState;
    property Config: TQueueConnectionConfig read GetConfig;
  end;

  {==========================================================================}
  {  RabbitMQ 通道接口                                                       }
  {==========================================================================}
  IRabbitMQChannel = interface
    ['{F9B2C3D4-E5F6-A7B8-C9D0-E1F2A3B4C5D6}']
    function GetChannelId: Integer;
    
    // 交换声明
    procedure ExchangeDeclare(const AConfig: TExchangeConfig);
    procedure ExchangeDelete(const AName: string; AIfUnused: Boolean = False);
    
    // 队列声明
    function QueueDeclare(const AConfig: TQueueConfig): string;
    procedure QueueDelete(const AName: string; AIfUnused: Boolean = False; AIfEmpty: Boolean = False);
    procedure QueuePurge(const AName: string);
    function QueueBind(const AQueue, AExchange, ARoutingKey: string): Boolean;
    procedure QueueUnbind(const AQueue, AExchange, ARoutingKey: string);
    
    // 发布
    procedure BasicPublish(const AExchange, ARoutingKey: string; const AMessage: TQueueMessage;
      AMandatory: Boolean = False; AImmediate: Boolean = False);
    
    // 消费
    function BasicConsume(const AQueue: string; const AConfig: TConsumerConfig;
      AHandler: TMessageHandler): string;
    procedure BasicCancel(const AConsumerTag: string);
    
    // 确认
    procedure BasicAck(ADeliveryTag: UInt64; AMultiple: Boolean = False);
    procedure BasicNack(ADeliveryTag: UInt64; AMultiple: Boolean = False; ARequeue: Boolean = True);
    procedure BasicReject(ADeliveryTag: UInt64; ARequeue: Boolean = True);
    
    // QoS
    procedure BasicQos(APrefetchSize: Cardinal; APrefetchCount: Word; AGlobal: Boolean);
    
    // 事务
    procedure TxSelect;
    procedure TxCommit;
    procedure TxRollback;
    
    // 关闭
    procedure Close;
    
    property ChannelId: Integer read GetChannelId;
  end;

  {==========================================================================}
  {  RabbitMQ 连接实现                                                       }
  {==========================================================================}
  TRabbitMQConnection = class(TInterfacedObject, IRabbitMQConnection)
  private
    FConfig: TQueueConnectionConfig;
    FState: TConnectionState;
    FLock: TCriticalSection;
    FChannels: TList<IRabbitMQChannel>;
    FNextChannelId: Integer;
    FHttpClient: THTTPClient;
    FOnStateChange: TConnectionStateEvent;
    FOnError: TErrorEvent;
    FReconnectTimer: TThread;
    FReconnectAttempts: Integer;
    
    procedure SetState(AState: TConnectionState; const AMessage: string = '');
    procedure DoReconnect;
    function GetManagementUrl: string;
  protected
    function GetState: TConnectionState;
    function GetConfig: TQueueConnectionConfig;
  public
    constructor Create(const AConfig: TQueueConnectionConfig);
    destructor Destroy; override;
    
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    function CreateChannel: IRabbitMQChannel;
    
    // Management API
    function GetQueueStatistics(const AQueueName: string): TQueueStatistics;
    function ListQueues: TArray<string>;
    function ListExchanges: TArray<string>;
    
    property State: TConnectionState read GetState;
    property Config: TQueueConnectionConfig read GetConfig;
    property OnStateChange: TConnectionStateEvent read FOnStateChange write FOnStateChange;
    property OnError: TErrorEvent read FOnError write FOnError;
  end;

  {==========================================================================}
  {  RabbitMQ 通道实现                                                       }
  {==========================================================================}
  TRabbitMQChannel = class(TInterfacedObject, IRabbitMQChannel)
  private
    FConnection: TRabbitMQConnection;
    FChannelId: Integer;
    FConsumers: TDictionary<string, TMessageHandler>;
    FConsumerThreads: TDictionary<string, TThread>;
    FLock: TCriticalSection;
    FHttpClient: THTTPClient;
    FClosed: Boolean;
    
    function GetApiUrl(const APath: string): string;
    function DoApiRequest(const AMethod, APath: string; ABody: TJSONObject = nil): TJSONValue;
  protected
    function GetChannelId: Integer;
  public
    constructor Create(AConnection: TRabbitMQConnection; AChannelId: Integer);
    destructor Destroy; override;
    
    // 交换声明
    procedure ExchangeDeclare(const AConfig: TExchangeConfig);
    procedure ExchangeDelete(const AName: string; AIfUnused: Boolean = False);
    
    // 队列声明
    function QueueDeclare(const AConfig: TQueueConfig): string;
    procedure QueueDelete(const AName: string; AIfUnused: Boolean = False; AIfEmpty: Boolean = False);
    procedure QueuePurge(const AName: string);
    function QueueBind(const AQueue, AExchange, ARoutingKey: string): Boolean;
    procedure QueueUnbind(const AQueue, AExchange, ARoutingKey: string);
    
    // 发布
    procedure BasicPublish(const AExchange, ARoutingKey: string; const AMessage: TQueueMessage;
      AMandatory: Boolean = False; AImmediate: Boolean = False);
    
    // 消费
    function BasicConsume(const AQueue: string; const AConfig: TConsumerConfig;
      AHandler: TMessageHandler): string;
    procedure BasicCancel(const AConsumerTag: string);
    
    // 确认
    procedure BasicAck(ADeliveryTag: UInt64; AMultiple: Boolean = False);
    procedure BasicNack(ADeliveryTag: UInt64; AMultiple: Boolean = False; ARequeue: Boolean = True);
    procedure BasicReject(ADeliveryTag: UInt64; ARequeue: Boolean = True);
    
    // QoS
    procedure BasicQos(APrefetchSize: Cardinal; APrefetchCount: Word; AGlobal: Boolean);
    
    // 事务
    procedure TxSelect;
    procedure TxCommit;
    procedure TxRollback;
    
    // 关闭
    procedure Close;
    
    property ChannelId: Integer read GetChannelId;
  end;

  {==========================================================================}
  {  RabbitMQ 生产�?                                                        }
  {==========================================================================}
  TRabbitMQProducer = class
  private
    FConnection: IRabbitMQConnection;
    FChannel: IRabbitMQChannel;
    FDefaultExchange: string;
    FDefaultRoutingKey: string;
    FConfirmMode: Boolean;
    FLock: TCriticalSection;
  public
    constructor Create(AConnection: IRabbitMQConnection);
    destructor Destroy; override;
    
    procedure SetDefaultExchange(const AExchange: string);
    procedure SetDefaultRoutingKey(const ARoutingKey: string);
    
    // 发送消�?
    procedure Publish(const AMessage: TQueueMessage); overload;
    procedure Publish(const AExchange, ARoutingKey: string; const AMessage: TQueueMessage); overload;
    procedure PublishJSON(const ARoutingKey: string; AJSON: TJSONValue);
    procedure PublishString(const ARoutingKey, AContent: string);
    
    // 批量发�?
    procedure PublishBatch(const AMessages: TArray<TQueueMessage>);
    
    // 延迟消息
    procedure PublishDelayed(const AMessage: TQueueMessage; ADelayMs: Integer);
    
    property DefaultExchange: string read FDefaultExchange write FDefaultExchange;
    property DefaultRoutingKey: string read FDefaultRoutingKey write FDefaultRoutingKey;
    property ConfirmMode: Boolean read FConfirmMode write FConfirmMode;
  end;

  {==========================================================================}
  {  RabbitMQ 消费�?                                                        }
  {==========================================================================}
  TRabbitMQConsumer = class
  private
    FConnection: IRabbitMQConnection;
    FChannel: IRabbitMQChannel;
    FQueueName: string;
    FConsumerTag: string;
    FConfig: TConsumerConfig;
    FHandler: TMessageHandler;
    FRunning: Boolean;
    FLock: TCriticalSection;
    FOnError: TErrorEvent;
    FProcessedCount: Int64;
    FFailedCount: Int64;
  public
    constructor Create(AConnection: IRabbitMQConnection; const AQueueName: string);
    destructor Destroy; override;
    
    procedure Start(AHandler: TMessageHandler);
    procedure Stop;
    function IsRunning: Boolean;
    
    property QueueName: string read FQueueName;
    property ConsumerTag: string read FConsumerTag;
    property Config: TConsumerConfig read FConfig;
    property ProcessedCount: Int64 read FProcessedCount;
    property FailedCount: Int64 read FFailedCount;
    property OnError: TErrorEvent read FOnError write FOnError;
  end;

  {==========================================================================}
  {  RabbitMQ 工作流触发器                                                   }
  {==========================================================================}
  TRabbitMQWorkflowTrigger = class
  private
    FConnection: IRabbitMQConnection;
    FExchange: string;
    FQueue: string;
    FConsumer: TRabbitMQConsumer;
    FProducer: TRabbitMQProducer;
    FOnWorkflowTrigger: TProc<TWorkflowTriggerMessage>;
    
    procedure HandleMessage(const AMessage: TQueueMessage; var AResult: TMessageProcessResult);
  public
    constructor Create(AConnection: IRabbitMQConnection);
    destructor Destroy; override;
    
    procedure Initialize(const AExchange, AQueue: string);
    procedure Start;
    procedure Stop;
    
    // 触发工作�?
    procedure TriggerWorkflow(const AWorkflowId: string; APayload: TJSONObject = nil);
    procedure ScheduleWorkflow(const AWorkflowId: string; AScheduledTime: TDateTime;
      APayload: TJSONObject = nil);
    
    property OnWorkflowTrigger: TProc<TWorkflowTriggerMessage> read FOnWorkflowTrigger 
      write FOnWorkflowTrigger;
  end;

  {==========================================================================}
  {  RabbitMQ 连接�?                                                        }
  {==========================================================================}
  TRabbitMQConnectionPool = class
  private
    FConfig: TQueueConnectionConfig;
    FConnections: TList<IRabbitMQConnection>;
    FAvailable: TList<IRabbitMQConnection>;
    FLock: TCriticalSection;
    FMinConnections: Integer;
    FMaxConnections: Integer;
    
    procedure CreateConnection;
  public
    constructor Create(const AConfig: TQueueConnectionConfig;
      AMinConnections: Integer = 2; AMaxConnections: Integer = 10);
    destructor Destroy; override;
    
    function Acquire: IRabbitMQConnection;
    procedure Release(AConnection: IRabbitMQConnection);
    
    function GetActiveCount: Integer;
    function GetAvailableCount: Integer;
    
    property MinConnections: Integer read FMinConnections;
    property MaxConnections: Integer read FMaxConnections;
  end;

implementation

uses
  System.StrUtils, System.Math;

{==========================================================================}
{  TRabbitMQConnection                                                     }
{==========================================================================}

constructor TRabbitMQConnection.Create(const AConfig: TQueueConnectionConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FState := csDisconnected;
  FLock := TCriticalSection.Create;
  FChannels := TList<IRabbitMQChannel>.Create;
  FNextChannelId := 1;
  FHttpClient := THTTPClient.Create;
  FReconnectAttempts := 0;
end;

destructor TRabbitMQConnection.Destroy;
begin
  Disconnect;
  FHttpClient.Free;
  FChannels.Free;
  FLock.Free;
  inherited;
end;

function TRabbitMQConnection.GetState: TConnectionState;
begin
  FLock.Enter;
  try
    Result := FState;
  finally
    FLock.Leave;
  end;
end;

function TRabbitMQConnection.GetConfig: TQueueConnectionConfig;
begin
  Result := FConfig;
end;

procedure TRabbitMQConnection.SetState(AState: TConnectionState; const AMessage: string);
begin
  FLock.Enter;
  try
    FState := AState;
  finally
    FLock.Leave;
  end;
  
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, AState, AMessage);
end;

function TRabbitMQConnection.GetManagementUrl: string;
var
  LPort: Integer;
begin
  // Management API 默认端口 15672
  if FConfig.SSL then
    LPort := 15671
  else
    LPort := 15672;
    
  Result := Format('http://%s:%d/api', [FConfig.Host, LPort]);
end;

procedure TRabbitMQConnection.Connect;
var
  LResponse: IHTTPResponse;
  LUrl: string;
begin
  if IsConnected then Exit;
  
  SetState(csConnecting, '正在连接...');
  
  try
    // 通过 Management API 测试连接
    LUrl := GetManagementUrl + '/overview';
    FHttpClient.CustomHeaders['Authorization'] := 'Basic ' +
      TNetEncoding.Base64.Encode(FConfig.Username + ':' + FConfig.Password);
    
    LResponse := FHttpClient.Get(LUrl);
    
    if LResponse.StatusCode = 200 then
    begin
      SetState(csConnected, '连接成功');
      FReconnectAttempts := 0;
    end
    else
      raise EOperationException.CreateFmt('连接失败: %d %s', [LResponse.StatusCode, LResponse.StatusText]);
  except
    on E: Exception do
    begin
      SetState(csError, E.Message);
      if Assigned(FOnError) then
        FOnError(Self, -1, E.Message);
        
      // 自动重连
      if FConfig.MaxReconnectAttempts > 0 then
        DoReconnect;
    end;
  end;
end;

procedure TRabbitMQConnection.Disconnect;
var
  LChannel: IRabbitMQChannel;
begin
  if FState = csDisconnected then Exit;
  
  SetState(csClosing, '正在断开...');
  
  FLock.Enter;
  try
    // 关闭所有通道
    for LChannel in FChannels do
      LChannel.Close;
    FChannels.Clear;
  finally
    FLock.Leave;
  end;
  
  if Assigned(FReconnectTimer) then
  begin
    FReconnectTimer.Terminate;
    FReconnectTimer := nil;
  end;
  
  SetState(csDisconnected, '已断开');
end;

function TRabbitMQConnection.IsConnected: Boolean;
begin
  Result := GetState = csConnected;
end;

function TRabbitMQConnection.CreateChannel: IRabbitMQChannel;
var
  LChannel: TRabbitMQChannel;
begin
  if not IsConnected then
    raise EOperationException.Create('未连接到 RabbitMQ');
    
  FLock.Enter;
  try
    LChannel := TRabbitMQChannel.Create(Self, FNextChannelId);
    Inc(FNextChannelId);
    FChannels.Add(LChannel);
    Result := LChannel;
  finally
    FLock.Leave;
  end;
end;

procedure TRabbitMQConnection.DoReconnect;
begin
  if FReconnectAttempts >= FConfig.MaxReconnectAttempts then
  begin
    SetState(csError, '达到最大重连次�?);
    Exit;
  end;
  
  Inc(FReconnectAttempts);
  SetState(csReconnecting, Format('重连�?(%d/%d)...', 
    [FReconnectAttempts, FConfig.MaxReconnectAttempts]));
  
  FReconnectTimer := TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(FConfig.ReconnectDelay);
      if not TThread.CheckTerminated then
        TThread.Queue(nil,
          procedure
          begin
            Connect;
          end);
    end);
  FReconnectTimer.FreeOnTerminate := True;
  FReconnectTimer.Start;
end;

function TRabbitMQConnection.GetQueueStatistics(const AQueueName: string): TQueueStatistics;
var
  LResponse: IHTTPResponse;
  LJSON: TJSONObject;
  LUrl: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.QueueName := AQueueName;
  
  LUrl := Format('%s/queues/%s/%s', [GetManagementUrl, 
    TNetEncoding.URL.Encode(FConfig.VirtualHost), 
    TNetEncoding.URL.Encode(AQueueName)]);
    
  LResponse := FHttpClient.Get(LUrl);
  
  if LResponse.StatusCode = 200 then
  begin
    LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      Result.MessageCount := LJSON.GetValue<Int64>('messages', 0);
      Result.ConsumerCount := LJSON.GetValue<Integer>('consumers', 0);
      Result.UnackedCount := LJSON.GetValue<Int64>('messages_unacknowledged', 0);
      Result.ReadyCount := LJSON.GetValue<Int64>('messages_ready', 0);
      Result.MemoryUsage := LJSON.GetValue<Int64>('memory', 0);
      Result.LastUpdated := Now;
    finally
      LJSON.Free;
    end;
  end;
end;

function TRabbitMQConnection.ListQueues: TArray<string>;
var
  LResponse: IHTTPResponse;
  LJSON: TJSONArray;
  LItem: TJSONValue;
  LUrl: string;
  LList: TList<string>;
begin
  LUrl := Format('%s/queues/%s', [GetManagementUrl, 
    TNetEncoding.URL.Encode(FConfig.VirtualHost)]);
    
  LResponse := FHttpClient.Get(LUrl);
  
  LList := TList<string>.Create;
  try
    if LResponse.StatusCode = 200 then
    begin
      LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONArray;
      try
        for LItem in LJSON do
          LList.Add((LItem as TJSONObject).GetValue<string>('name', ''));
      finally
        LJSON.Free;
      end;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TRabbitMQConnection.ListExchanges: TArray<string>;
var
  LResponse: IHTTPResponse;
  LJSON: TJSONArray;
  LItem: TJSONValue;
  LUrl: string;
  LList: TList<string>;
begin
  LUrl := Format('%s/exchanges/%s', [GetManagementUrl, 
    TNetEncoding.URL.Encode(FConfig.VirtualHost)]);
    
  LResponse := FHttpClient.Get(LUrl);
  
  LList := TList<string>.Create;
  try
    if LResponse.StatusCode = 200 then
    begin
      LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONArray;
      try
        for LItem in LJSON do
          LList.Add((LItem as TJSONObject).GetValue<string>('name', ''));
      finally
        LJSON.Free;
      end;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

{==========================================================================}
{  TRabbitMQChannel                                                        }
{==========================================================================}

constructor TRabbitMQChannel.Create(AConnection: TRabbitMQConnection; AChannelId: Integer);
begin
  inherited Create;
  FConnection := AConnection;
  FChannelId := AChannelId;
  FConsumers := TDictionary<string, TMessageHandler>.Create;
  FConsumerThreads := TDictionary<string, TThread>.Create;
  FLock := TCriticalSection.Create;
  FHttpClient := THTTPClient.Create;
  FHttpClient.CustomHeaders['Authorization'] := 'Basic ' +
    TNetEncoding.Base64.Encode(FConnection.Config.Username + ':' + FConnection.Config.Password);
  FHttpClient.ContentType := 'application/json';
  FClosed := False;
end;

destructor TRabbitMQChannel.Destroy;
begin
  Close;
  FConsumerThreads.Free;
  FConsumers.Free;
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

function TRabbitMQChannel.GetChannelId: Integer;
begin
  Result := FChannelId;
end;

function TRabbitMQChannel.GetApiUrl(const APath: string): string;
begin
  Result := Format('http://%s:15672/api%s', [FConnection.Config.Host, APath]);
end;

function TRabbitMQChannel.DoApiRequest(const AMethod, APath: string; 
  ABody: TJSONObject): TJSONValue;
var
  LResponse: IHTTPResponse;
  LUrl: string;
  LStream: TStringStream;
begin
  Result := nil;
  LUrl := GetApiUrl(APath);
  
  if ABody <> nil then
  begin
    LStream := TStringStream.Create(ABody.ToJSON, TEncoding.UTF8);
    try
      if AMethod = 'PUT' then
        LResponse := FHttpClient.Put(LUrl, LStream)
      else if AMethod = 'POST' then
        LResponse := FHttpClient.Post(LUrl, LStream)
      else if AMethod = 'DELETE' then
        LResponse := FHttpClient.Delete(LUrl);
    finally
      LStream.Free;
    end;
  end
  else
  begin
    if AMethod = 'GET' then
      LResponse := FHttpClient.Get(LUrl)
    else if AMethod = 'DELETE' then
      LResponse := FHttpClient.Delete(LUrl)
    else if AMethod = 'PUT' then
      LResponse := FHttpClient.Put(LUrl);
  end;
  
  if (LResponse.StatusCode >= 200) and (LResponse.StatusCode < 300) then
  begin
    if LResponse.ContentAsString <> '' then
      Result := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
  end
  else if LResponse.StatusCode >= 400 then
    raise EOperationException.CreateFmt('API 错误: %d %s', [LResponse.StatusCode, LResponse.StatusText]);
end;

procedure TRabbitMQChannel.ExchangeDeclare(const AConfig: TExchangeConfig);
var
  LBody: TJSONObject;
  LPath: string;
begin
  LPath := Format('/exchanges/%s/%s', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AConfig.Name)]);
    
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('type', AConfig.GetTypeString);
    LBody.AddPair('durable', TJSONBool.Create(AConfig.Durable));
    LBody.AddPair('auto_delete', TJSONBool.Create(AConfig.AutoDelete));
    LBody.AddPair('internal', TJSONBool.Create(AConfig.Internal));
    
    DoApiRequest('PUT', LPath, LBody);
  finally
    LBody.Free;
  end;
end;

procedure TRabbitMQChannel.ExchangeDelete(const AName: string; AIfUnused: Boolean);
var
  LPath: string;
begin
  LPath := Format('/exchanges/%s/%s', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AName)]);
    
  if AIfUnused then
    LPath := LPath + '?if-unused=true';
    
  DoApiRequest('DELETE', LPath);
end;

function TRabbitMQChannel.QueueDeclare(const AConfig: TQueueConfig): string;
var
  LBody, LArgs: TJSONObject;
  LPath: string;
begin
  Result := AConfig.Name;
  
  LPath := Format('/queues/%s/%s', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AConfig.Name)]);
    
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('durable', TJSONBool.Create(AConfig.Durable));
    LBody.AddPair('auto_delete', TJSONBool.Create(AConfig.AutoDelete));
    LBody.AddPair('exclusive', TJSONBool.Create(AConfig.Exclusive));
    
    LArgs := TJSONObject.Create;
    if AConfig.MaxLength > 0 then
      LArgs.AddPair('x-max-length', TJSONNumber.Create(AConfig.MaxLength));
    if AConfig.MaxLengthBytes > 0 then
      LArgs.AddPair('x-max-length-bytes', TJSONNumber.Create(AConfig.MaxLengthBytes));
    if AConfig.MessageTTL > 0 then
      LArgs.AddPair('x-message-ttl', TJSONNumber.Create(AConfig.MessageTTL));
    if AConfig.DeadLetterExchange <> '' then
      LArgs.AddPair('x-dead-letter-exchange', AConfig.DeadLetterExchange);
    if AConfig.DeadLetterRoutingKey <> '' then
      LArgs.AddPair('x-dead-letter-routing-key', AConfig.DeadLetterRoutingKey);
      
    LBody.AddPair('arguments', LArgs);
    
    DoApiRequest('PUT', LPath, LBody);
  finally
    LBody.Free;
  end;
end;

procedure TRabbitMQChannel.QueueDelete(const AName: string; AIfUnused, AIfEmpty: Boolean);
var
  LPath: string;
  LParams: string;
begin
  LPath := Format('/queues/%s/%s', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AName)]);
    
  LParams := '';
  if AIfUnused then
    LParams := 'if-unused=true';
  if AIfEmpty then
  begin
    if LParams <> '' then LParams := LParams + '&';
    LParams := LParams + 'if-empty=true';
  end;
  if LParams <> '' then
    LPath := LPath + '?' + LParams;
    
  DoApiRequest('DELETE', LPath);
end;

procedure TRabbitMQChannel.QueuePurge(const AName: string);
var
  LPath: string;
begin
  LPath := Format('/queues/%s/%s/contents', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AName)]);
    
  DoApiRequest('DELETE', LPath);
end;

function TRabbitMQChannel.QueueBind(const AQueue, AExchange, ARoutingKey: string): Boolean;
var
  LBody: TJSONObject;
  LPath: string;
begin
  Result := False;
  
  LPath := Format('/bindings/%s/e/%s/q/%s', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AExchange),
    TNetEncoding.URL.Encode(AQueue)]);
    
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('routing_key', ARoutingKey);
    
    DoApiRequest('POST', LPath, LBody);
    Result := True;
  finally
    LBody.Free;
  end;
end;

procedure TRabbitMQChannel.QueueUnbind(const AQueue, AExchange, ARoutingKey: string);
var
  LPath: string;
begin
  LPath := Format('/bindings/%s/e/%s/q/%s/%s', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AExchange),
    TNetEncoding.URL.Encode(AQueue),
    TNetEncoding.URL.Encode(ARoutingKey)]);
    
  DoApiRequest('DELETE', LPath);
end;

procedure TRabbitMQChannel.BasicPublish(const AExchange, ARoutingKey: string;
  const AMessage: TQueueMessage; AMandatory, AImmediate: Boolean);
var
  LBody, LProps: TJSONObject;
  LPath: string;
begin
  LPath := Format('/exchanges/%s/%s/publish', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
    TNetEncoding.URL.Encode(AExchange)]);
    
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('routing_key', ARoutingKey);
    LBody.AddPair('payload', TNetEncoding.Base64.EncodeBytesToString(AMessage.Body));
    LBody.AddPair('payload_encoding', 'base64');
    
    LProps := TJSONObject.Create;
    LProps.AddPair('content_type', AMessage.ContentType);
    LProps.AddPair('content_encoding', AMessage.ContentEncoding);
    LProps.AddPair('message_id', AMessage.MessageId);
    LProps.AddPair('correlation_id', AMessage.CorrelationId);
    LProps.AddPair('reply_to', AMessage.ReplyTo);
    LProps.AddPair('priority', TJSONNumber.Create(Ord(AMessage.Priority)));
    LProps.AddPair('delivery_mode', TJSONNumber.Create(2)); // persistent
    if AMessage.Expiration > 0 then
      LProps.AddPair('expiration', IntToStr(AMessage.Expiration));
    LProps.AddPair('headers', AMessage.Headers.ToJSON);
    
    LBody.AddPair('properties', LProps);
    
    DoApiRequest('POST', LPath, LBody);
  finally
    LBody.Free;
  end;
end;

function TRabbitMQChannel.BasicConsume(const AQueue: string;
  const AConfig: TConsumerConfig; AHandler: TMessageHandler): string;
var
  LConsumerTag: string;
  LThread: TThread;
begin
  LConsumerTag := AConfig.ConsumerTag;
  if LConsumerTag = '' then
    LConsumerTag := 'consumer_' + TGUID.NewGuid.ToString;
    
  FLock.Enter;
  try
    FConsumers.Add(LConsumerTag, AHandler);
  finally
    FLock.Leave;
  end;
  
  // 创建消费者线�?
  LThread := TThread.CreateAnonymousThread(
    procedure
    var
      LResponse: IHTTPResponse;
      LPath: string;
      LBody, LJSON, LMsg: TJSONObject;
      LMessages: TJSONArray;
      LItem: TJSONValue;
      LMessage: TQueueMessage;
      LResult: TMessageProcessResult;
      LPayload: string;
    begin
      while not TThread.CheckTerminated and not FClosed do
      begin
        try
          LPath := Format('/queues/%s/%s/get', [
            TNetEncoding.URL.Encode(FConnection.Config.VirtualHost),
            TNetEncoding.URL.Encode(AQueue)]);
            
          LBody := TJSONObject.Create;
          try
            LBody.AddPair('count', TJSONNumber.Create(AConfig.PrefetchCount));
            LBody.AddPair('ackmode', 'ack_requeue_true');
            LBody.AddPair('encoding', 'base64');
            
            LJSON := DoApiRequest('POST', LPath, LBody) as TJSONObject;
            if Assigned(LJSON) then
            begin
              try
                LMessages := LJSON as TJSONArray;
                for LItem in LMessages do
                begin
                  LMsg := LItem as TJSONObject;
                  LMessage := TQueueMessage.Create;
                  try
                    LPayload := LMsg.GetValue<string>('payload', '');
                    LMessage.Body := TNetEncoding.Base64.DecodeStringToBytes(LPayload);
                    LMessage.DeliveryTag := LMsg.GetValue<UInt64>('delivery_tag', 0);
                    LMessage.Exchange := LMsg.GetValue<string>('exchange', '');
                    LMessage.RoutingKey := LMsg.GetValue<string>('routing_key', '');
                    LMessage.Redelivered := LMsg.GetValue<Boolean>('redelivered', False);
                    
                    LResult := mprAck;
                    AHandler(LMessage, LResult);
                    
                    case LResult of
                      mprAck: BasicAck(LMessage.DeliveryTag);
                      mprNack: BasicNack(LMessage.DeliveryTag, False, True);
                      mprReject: BasicReject(LMessage.DeliveryTag, False);
                    end;
                  finally
                    LMessage.Free;
                  end;
                end;
              finally
                LJSON.Free;
              end;
            end;
          finally
            LBody.Free;
          end;
          
          Sleep(100); // 轮询间隔
        except
          on E: Exception do
            Sleep(1000); // 错误后等�?
        end;
      end;
    end);
    
  LThread.FreeOnTerminate := False;
  
  FLock.Enter;
  try
    FConsumerThreads.Add(LConsumerTag, LThread);
  finally
    FLock.Leave;
  end;
  
  LThread.Start;
  Result := LConsumerTag;
end;

procedure TRabbitMQChannel.BasicCancel(const AConsumerTag: string);
var
  LThread: TThread;
begin
  FLock.Enter;
  try
    if FConsumerThreads.TryGetValue(AConsumerTag, LThread) then
    begin
      LThread.Terminate;
      LThread.WaitFor;
      LThread.Free;
      FConsumerThreads.Remove(AConsumerTag);
    end;
    FConsumers.Remove(AConsumerTag);
  finally
    FLock.Leave;
  end;
end;

procedure TRabbitMQChannel.BasicAck(ADeliveryTag: UInt64; AMultiple: Boolean);
var
  LBody: TJSONObject;
  LPath: string;
begin
  LPath := Format('/queues/%s/ack', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost)]);
    
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('delivery_tag', TJSONNumber.Create(ADeliveryTag));
    LBody.AddPair('multiple', TJSONBool.Create(AMultiple));
    
    DoApiRequest('POST', LPath, LBody);
  finally
    LBody.Free;
  end;
end;

procedure TRabbitMQChannel.BasicNack(ADeliveryTag: UInt64; AMultiple, ARequeue: Boolean);
var
  LBody: TJSONObject;
  LPath: string;
begin
  LPath := Format('/queues/%s/nack', [
    TNetEncoding.URL.Encode(FConnection.Config.VirtualHost)]);
    
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('delivery_tag', TJSONNumber.Create(ADeliveryTag));
    LBody.AddPair('multiple', TJSONBool.Create(AMultiple));
    LBody.AddPair('requeue', TJSONBool.Create(ARequeue));
    
    DoApiRequest('POST', LPath, LBody);
  finally
    LBody.Free;
  end;
end;

procedure TRabbitMQChannel.BasicReject(ADeliveryTag: UInt64; ARequeue: Boolean);
begin
  BasicNack(ADeliveryTag, False, ARequeue);
end;

procedure TRabbitMQChannel.BasicQos(APrefetchSize: Cardinal; APrefetchCount: Word; AGlobal: Boolean);
begin
  // Management API 不直接支�?QoS，通过消费时的 count 参数控制
end;

procedure TRabbitMQChannel.TxSelect;
begin
  // Management API 不支持事�?
  raise EOperationException.Create('Management API 不支持事务，请使�?AMQP 客户�?);
end;

procedure TRabbitMQChannel.TxCommit;
begin
  raise EOperationException.Create('Management API 不支持事�?);
end;

procedure TRabbitMQChannel.TxRollback;
begin
  raise EOperationException.Create('Management API 不支持事�?);
end;

procedure TRabbitMQChannel.Close;
var
  LTag: string;
begin
  FClosed := True;
  
  FLock.Enter;
  try
    for LTag in FConsumerThreads.Keys do
      BasicCancel(LTag);
  finally
    FLock.Leave;
  end;
end;

{==========================================================================}
{  TRabbitMQProducer                                                       }
{==========================================================================}

constructor TRabbitMQProducer.Create(AConnection: IRabbitMQConnection);
begin
  inherited Create;
  FConnection := AConnection;
  FChannel := FConnection.CreateChannel;
  FDefaultExchange := '';
  FDefaultRoutingKey := '';
  FConfirmMode := False;
  FLock := TCriticalSection.Create;
end;

destructor TRabbitMQProducer.Destroy;
begin
  FChannel.Close;
  FLock.Free;
  inherited;
end;

procedure TRabbitMQProducer.SetDefaultExchange(const AExchange: string);
begin
  FDefaultExchange := AExchange;
end;

procedure TRabbitMQProducer.SetDefaultRoutingKey(const ARoutingKey: string);
begin
  FDefaultRoutingKey := ARoutingKey;
end;

procedure TRabbitMQProducer.Publish(const AMessage: TQueueMessage);
begin
  Publish(FDefaultExchange, FDefaultRoutingKey, AMessage);
end;

procedure TRabbitMQProducer.Publish(const AExchange, ARoutingKey: string;
  const AMessage: TQueueMessage);
begin
  FLock.Enter;
  try
    FChannel.BasicPublish(AExchange, ARoutingKey, AMessage);
  finally
    FLock.Leave;
  end;
end;

procedure TRabbitMQProducer.PublishJSON(const ARoutingKey: string; AJSON: TJSONValue);
var
  LMessage: TQueueMessage;
begin
  LMessage := TQueueMessage.Create;
  try
    LMessage.SetBodyAsJSON(AJSON);
    LMessage.ContentType := 'application/json';
    Publish(FDefaultExchange, ARoutingKey, LMessage);
  finally
    LMessage.Free;
  end;
end;

procedure TRabbitMQProducer.PublishString(const ARoutingKey, AContent: string);
var
  LMessage: TQueueMessage;
begin
  LMessage := TQueueMessage.Create;
  try
    LMessage.SetBodyAsString(AContent);
    LMessage.ContentType := 'text/plain';
    Publish(FDefaultExchange, ARoutingKey, LMessage);
  finally
    LMessage.Free;
  end;
end;

procedure TRabbitMQProducer.PublishBatch(const AMessages: TArray<TQueueMessage>);
var
  LMessage: TQueueMessage;
begin
  FLock.Enter;
  try
    for LMessage in AMessages do
      FChannel.BasicPublish(FDefaultExchange, FDefaultRoutingKey, LMessage);
  finally
    FLock.Leave;
  end;
end;

procedure TRabbitMQProducer.PublishDelayed(const AMessage: TQueueMessage; ADelayMs: Integer);
begin
  // 使用 TTL + 死信队列实现延迟消息
  AMessage.Expiration := ADelayMs;
  AMessage.Headers['x-delay'] := IntToStr(ADelayMs);
  Publish(AMessage);
end;

{==========================================================================}
{  TRabbitMQConsumer                                                       }
{==========================================================================}

constructor TRabbitMQConsumer.Create(AConnection: IRabbitMQConnection;
  const AQueueName: string);
begin
  inherited Create;
  FConnection := AConnection;
  FChannel := FConnection.CreateChannel;
  FQueueName := AQueueName;
  FConfig := TConsumerConfig.Create;
  FRunning := False;
  FLock := TCriticalSection.Create;
  FProcessedCount := 0;
  FFailedCount := 0;
end;

destructor TRabbitMQConsumer.Destroy;
begin
  Stop;
  FConfig.Free;
  FChannel.Close;
  FLock.Free;
  inherited;
end;

procedure TRabbitMQConsumer.Start(AHandler: TMessageHandler);
begin
  if FRunning then Exit;
  
  FHandler := AHandler;
  FRunning := True;
  
  FConsumerTag := FChannel.BasicConsume(FQueueName, FConfig,
    procedure(const AMessage: TQueueMessage; var AResult: TMessageProcessResult)
    begin
      try
        AHandler(AMessage, AResult);
        if AResult = mprAck then
          AtomicIncrement(FProcessedCount)
        else
          AtomicIncrement(FFailedCount);
      except
        on E: Exception do
        begin
          AtomicIncrement(FFailedCount);
          AResult := mprNack;
          if Assigned(FOnError) then
            FOnError(Self, -1, E.Message);
        end;
      end;
    end);
end;

procedure TRabbitMQConsumer.Stop;
begin
  if not FRunning then Exit;
  
  FRunning := False;
  
  if FConsumerTag <> '' then
  begin
    FChannel.BasicCancel(FConsumerTag);
    FConsumerTag := '';
  end;
end;

function TRabbitMQConsumer.IsRunning: Boolean;
begin
  Result := FRunning;
end;

{==========================================================================}
{  TRabbitMQWorkflowTrigger                                                }
{==========================================================================}

constructor TRabbitMQWorkflowTrigger.Create(AConnection: IRabbitMQConnection);
begin
  inherited Create;
  FConnection := AConnection;
  FExchange := 'uniflow.workflow';
  FQueue := 'uniflow.workflow.trigger';
end;

destructor TRabbitMQWorkflowTrigger.Destroy;
begin
  Stop;
  FProducer.Free;
  FConsumer.Free;
  inherited;
end;

procedure TRabbitMQWorkflowTrigger.Initialize(const AExchange, AQueue: string);
var
  LChannel: IRabbitMQChannel;
  LExchangeConfig: TExchangeConfig;
  LQueueConfig: TQueueConfig;
begin
  FExchange := AExchange;
  FQueue := AQueue;
  
  LChannel := FConnection.CreateChannel;
  try
    // 创建交换
    LExchangeConfig := TExchangeConfig.Create(FExchange, etTopic);
    try
      LExchangeConfig.Durable := True;
      LChannel.ExchangeDeclare(LExchangeConfig);
    finally
      LExchangeConfig.Free;
    end;
    
    // 创建队列
    LQueueConfig := TQueueConfig.Create(FQueue);
    try
      LQueueConfig.Durable := True;
      LChannel.QueueDeclare(LQueueConfig);
    finally
      LQueueConfig.Free;
    end;
    
    // 绑定
    LChannel.QueueBind(FQueue, FExchange, 'workflow.#');
  finally
    LChannel.Close;
  end;
  
  // 创建生产者和消费�?
  FProducer := TRabbitMQProducer.Create(FConnection);
  FProducer.DefaultExchange := FExchange;
  
  FConsumer := TRabbitMQConsumer.Create(FConnection, FQueue);
end;

procedure TRabbitMQWorkflowTrigger.HandleMessage(const AMessage: TQueueMessage;
  var AResult: TMessageProcessResult);
var
  LTrigger: TWorkflowTriggerMessage;
begin
  LTrigger := TWorkflowTriggerMessage.Create;
  try
    LTrigger.FromJSON(AMessage.GetBodyAsJSON as TJSONObject);
    
    if Assigned(FOnWorkflowTrigger) then
      FOnWorkflowTrigger(LTrigger);
      
    AResult := mprAck;
  finally
    LTrigger.Free;
  end;
end;

procedure TRabbitMQWorkflowTrigger.Start;
begin
  FConsumer.Start(HandleMessage);
end;

procedure TRabbitMQWorkflowTrigger.Stop;
begin
  if Assigned(FConsumer) then
    FConsumer.Stop;
end;

procedure TRabbitMQWorkflowTrigger.TriggerWorkflow(const AWorkflowId: string;
  APayload: TJSONObject);
var
  LTrigger: TWorkflowTriggerMessage;
begin
  LTrigger := TWorkflowTriggerMessage.Create;
  try
    LTrigger.WorkflowId := AWorkflowId;
    LTrigger.TriggerType := 'immediate';
    if Assigned(APayload) then
      LTrigger.Payload.AddPair('data', APayload.Clone as TJSONObject);
      
    LTrigger.SetBodyAsJSON(LTrigger.ToJSON);
    FProducer.Publish(FExchange, 'workflow.trigger.' + AWorkflowId, LTrigger);
  finally
    LTrigger.Free;
  end;
end;

procedure TRabbitMQWorkflowTrigger.ScheduleWorkflow(const AWorkflowId: string;
  AScheduledTime: TDateTime; APayload: TJSONObject);
var
  LTrigger: TWorkflowTriggerMessage;
  LDelayMs: Int64;
begin
  LTrigger := TWorkflowTriggerMessage.Create;
  try
    LTrigger.WorkflowId := AWorkflowId;
    LTrigger.TriggerType := 'scheduled';
    LTrigger.ScheduledTime := AScheduledTime;
    if Assigned(APayload) then
      LTrigger.Payload.AddPair('data', APayload.Clone as TJSONObject);
      
    LTrigger.SetBodyAsJSON(LTrigger.ToJSON);
    
    // 计算延迟时间
    LDelayMs := Round((AScheduledTime - Now) * MSecsPerDay);
    if LDelayMs > 0 then
      FProducer.PublishDelayed(LTrigger, LDelayMs)
    else
      FProducer.Publish(FExchange, 'workflow.trigger.' + AWorkflowId, LTrigger);
  finally
    LTrigger.Free;
  end;
end;

{==========================================================================}
{  TRabbitMQConnectionPool                                                 }
{==========================================================================}

constructor TRabbitMQConnectionPool.Create(const AConfig: TQueueConnectionConfig;
  AMinConnections, AMaxConnections: Integer);
var
  I: Integer;
begin
  inherited Create;
  FConfig := AConfig;
  FMinConnections := AMinConnections;
  FMaxConnections := AMaxConnections;
  FConnections := TList<IRabbitMQConnection>.Create;
  FAvailable := TList<IRabbitMQConnection>.Create;
  FLock := TCriticalSection.Create;
  
  // 初始化最小连接数
  for I := 1 to FMinConnections do
    CreateConnection;
end;

destructor TRabbitMQConnectionPool.Destroy;
var
  LConn: IRabbitMQConnection;
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

procedure TRabbitMQConnectionPool.CreateConnection;
var
  LConn: IRabbitMQConnection;
begin
  LConn := TRabbitMQConnection.Create(FConfig);
  LConn.Connect;
  
  FLock.Enter;
  try
    FConnections.Add(LConn);
    FAvailable.Add(LConn);
  finally
    FLock.Leave;
  end;
end;

function TRabbitMQConnectionPool.Acquire: IRabbitMQConnection;
begin
  FLock.Enter;
  try
    if FAvailable.Count > 0 then
    begin
      Result := FAvailable[0];
      FAvailable.Delete(0);
    end
    else if FConnections.Count < FMaxConnections then
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

procedure TRabbitMQConnectionPool.Release(AConnection: IRabbitMQConnection);
begin
  FLock.Enter;
  try
    if not FAvailable.Contains(AConnection) then
      FAvailable.Add(AConnection);
  finally
    FLock.Leave;
  end;
end;

function TRabbitMQConnectionPool.GetActiveCount: Integer;
begin
  FLock.Enter;
  try
    Result := FConnections.Count - FAvailable.Count;
  finally
    FLock.Leave;
  end;
end;

function TRabbitMQConnectionPool.GetAvailableCount: Integer;
begin
  FLock.Enter;
  try
    Result := FAvailable.Count;
  finally
    FLock.Leave;
  end;
end;

end.
