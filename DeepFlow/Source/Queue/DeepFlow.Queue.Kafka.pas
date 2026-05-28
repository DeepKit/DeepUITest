unit UniFlow.Queue.Kafka;

{*******************************************************}
{                                                       }
{       UniFlow Kafka 消息队列集成                      }
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
  {  Kafka 连接配置                                                          }
  {==========================================================================}
  TKafkaConnectionConfig = class
  private
    FBootstrapServers: string;
    FClientId: string;
    FAcks: string;                 // 0, 1, all
    FRetries: Integer;
    FRetryBackoffMs: Integer;
    FRequestTimeoutMs: Integer;
    FSecurityProtocol: string;    // PLAINTEXT, SSL, SASL_PLAINTEXT, SASL_SSL
    FSaslMechanism: string;       // PLAIN, SCRAM-SHA-256, SCRAM-SHA-512
    FSaslUsername: string;
    FSaslPassword: string;
    FSSLCaLocation: string;
    FSSLCertLocation: string;
    FSSLKeyLocation: string;
  public
    constructor Create;
    
    property BootstrapServers: string read FBootstrapServers write FBootstrapServers;
    property ClientId: string read FClientId write FClientId;
    property Acks: string read FAcks write FAcks;
    property Retries: Integer read FRetries write FRetries;
    property RetryBackoffMs: Integer read FRetryBackoffMs write FRetryBackoffMs;
    property RequestTimeoutMs: Integer read FRequestTimeoutMs write FRequestTimeoutMs;
    property SecurityProtocol: string read FSecurityProtocol write FSecurityProtocol;
    property SaslMechanism: string read FSaslMechanism write FSaslMechanism;
    property SaslUsername: string read FSaslUsername write FSaslUsername;
    property SaslPassword: string read FSaslPassword write FSaslPassword;
    property SSLCaLocation: string read FSSLCaLocation write FSSLCaLocation;
    property SSLCertLocation: string read FSSLCertLocation write FSSLCertLocation;
    property SSLKeyLocation: string read FSSLKeyLocation write FSSLKeyLocation;
  end;

  {==========================================================================}
  {  Kafka 生产者配�?                                                       }
  {==========================================================================}
  TKafkaProducerConfig = class
  private
    FBatchSize: Integer;
    FLingerMs: Integer;
    FBufferMemory: Int64;
    FMaxBlockMs: Integer;
    FCompressionType: string;     // none, gzip, snappy, lz4, zstd
    FIdempotence: Boolean;
    FTransactionalId: string;
  public
    constructor Create;
    
    property BatchSize: Integer read FBatchSize write FBatchSize;
    property LingerMs: Integer read FLingerMs write FLingerMs;
    property BufferMemory: Int64 read FBufferMemory write FBufferMemory;
    property MaxBlockMs: Integer read FMaxBlockMs write FMaxBlockMs;
    property CompressionType: string read FCompressionType write FCompressionType;
    property Idempotence: Boolean read FIdempotence write FIdempotence;
    property TransactionalId: string read FTransactionalId write FTransactionalId;
  end;

  {==========================================================================}
  {  Kafka 生产者接�?                                                       }
  {==========================================================================}
  IKafkaProducer = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    procedure Send(const ATopic: string; const ARecord: TKafkaRecord);
    procedure SendAsync(const ATopic: string; const ARecord: TKafkaRecord;
      ACallback: TProc<Boolean, string>);
    procedure Flush;
    procedure Close;
  end;

  {==========================================================================}
  {  Kafka 消费者接�?                                                       }
  {==========================================================================}
  IKafkaConsumer = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    procedure Subscribe(const ATopics: TArray<string>);
    procedure Unsubscribe;
    function Poll(ATimeoutMs: Integer): TArray<TKafkaRecord>;
    procedure Commit;
    procedure CommitAsync(ACallback: TProc<Boolean, string>);
    procedure Seek(const ATopic: string; APartition: Integer; AOffset: Int64);
    procedure Close;
  end;

  {==========================================================================}
  {  Kafka 管理接口                                                          }
  {==========================================================================}
  IKafkaAdmin = interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']
    procedure CreateTopic(const AConfig: TKafkaTopicConfig);
    procedure DeleteTopic(const ATopic: string);
    function ListTopics: TArray<string>;
    function DescribeTopic(const ATopic: string): TKafkaTopicConfig;
    procedure CreatePartitions(const ATopic: string; ANumPartitions: Integer);
  end;

  {==========================================================================}
  {  Kafka 生产者实�?(HTTP REST Proxy)                                      }
  {==========================================================================}
  TKafkaProducer = class(TInterfacedObject, IKafkaProducer)
  private
    FConfig: TKafkaConnectionConfig;
    FProducerConfig: TKafkaProducerConfig;
    FHttpClient: THTTPClient;
    FRestProxyUrl: string;
    FLock: TCriticalSection;
    FPendingRecords: TList<TKafkaRecord>;
    
    function GetRestUrl(const APath: string): string;
  public
    constructor Create(const AConfig: TKafkaConnectionConfig;
      const ARestProxyUrl: string);
    destructor Destroy; override;
    
    procedure Send(const ATopic: string; const ARecord: TKafkaRecord);
    procedure SendAsync(const ATopic: string; const ARecord: TKafkaRecord;
      ACallback: TProc<Boolean, string>);
    procedure Flush;
    procedure Close;
    
    property Config: TKafkaConnectionConfig read FConfig;
    property ProducerConfig: TKafkaProducerConfig read FProducerConfig;
  end;

  {==========================================================================}
  {  Kafka 消费者实�?(HTTP REST Proxy)                                      }
  {==========================================================================}
  TKafkaConsumer = class(TInterfacedObject, IKafkaConsumer)
  private
    FConfig: TKafkaConnectionConfig;
    FConsumerConfig: TKafkaConsumerConfig;
    FHttpClient: THTTPClient;
    FRestProxyUrl: string;
    FConsumerId: string;
    FInstanceId: string;
    FSubscribedTopics: TList<string>;
    FLock: TCriticalSection;
    
    function GetRestUrl(const APath: string): string;
    procedure CreateConsumerInstance;
    procedure DeleteConsumerInstance;
  public
    constructor Create(const AConfig: TKafkaConnectionConfig;
      const AConsumerConfig: TKafkaConsumerConfig;
      const ARestProxyUrl: string);
    destructor Destroy; override;
    
    procedure Subscribe(const ATopics: TArray<string>);
    procedure Unsubscribe;
    function Poll(ATimeoutMs: Integer): TArray<TKafkaRecord>;
    procedure Commit;
    procedure CommitAsync(ACallback: TProc<Boolean, string>);
    procedure Seek(const ATopic: string; APartition: Integer; AOffset: Int64);
    procedure Close;
    
    property Config: TKafkaConnectionConfig read FConfig;
    property ConsumerConfig: TKafkaConsumerConfig read FConsumerConfig;
  end;

  {==========================================================================}
  {  Kafka 管理实现 (HTTP REST Proxy)                                        }
  {==========================================================================}
  TKafkaAdmin = class(TInterfacedObject, IKafkaAdmin)
  private
    FConfig: TKafkaConnectionConfig;
    FHttpClient: THTTPClient;
    FRestProxyUrl: string;
    
    function GetRestUrl(const APath: string): string;
  public
    constructor Create(const AConfig: TKafkaConnectionConfig;
      const ARestProxyUrl: string);
    destructor Destroy; override;
    
    procedure CreateTopic(const AConfig: TKafkaTopicConfig);
    procedure DeleteTopic(const ATopic: string);
    function ListTopics: TArray<string>;
    function DescribeTopic(const ATopic: string): TKafkaTopicConfig;
    procedure CreatePartitions(const ATopic: string; ANumPartitions: Integer);
  end;

  {==========================================================================}
  {  Kafka 工作流触发器                                                      }
  {==========================================================================}
  TKafkaWorkflowTrigger = class
  private
    FProducer: IKafkaProducer;
    FConsumer: IKafkaConsumer;
    FTopic: string;
    FConsumerThread: TThread;
    FRunning: Boolean;
    FOnWorkflowTrigger: TProc<TWorkflowTriggerMessage>;
    
    procedure ConsumerLoop;
  public
    constructor Create(AProducer: IKafkaProducer; AConsumer: IKafkaConsumer);
    destructor Destroy; override;
    
    procedure Initialize(const ATopic: string);
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
  {  Kafka 流处理器                                                          }
  {==========================================================================}
  TKafkaStreamProcessor = class
  private
    FConsumer: IKafkaConsumer;
    FProducer: IKafkaProducer;
    FInputTopics: TArray<string>;
    FOutputTopic: string;
    FProcessThread: TThread;
    FRunning: Boolean;
    FProcessor: TFunc<TKafkaRecord, TKafkaRecord>;
    FFilter: TFunc<TKafkaRecord, Boolean>;
  public
    constructor Create(AConsumer: IKafkaConsumer; AProducer: IKafkaProducer);
    destructor Destroy; override;
    
    // 配置
    procedure SetInputTopics(const ATopics: TArray<string>);
    procedure SetOutputTopic(const ATopic: string);
    procedure SetProcessor(AProcessor: TFunc<TKafkaRecord, TKafkaRecord>);
    procedure SetFilter(AFilter: TFunc<TKafkaRecord, Boolean>);
    
    // 控制
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
  end;

  {==========================================================================}
  {  消息队列管理�?                                                         }
  {==========================================================================}
  TMessageQueueManager = class
  private
    FRabbitMQConnections: TDictionary<string, IRabbitMQConnection>;
    FKafkaProducers: TDictionary<string, IKafkaProducer>;
    FKafkaConsumers: TDictionary<string, IKafkaConsumer>;
    FLock: TCriticalSection;
    class var FInstance: TMessageQueueManager;
  public
    constructor Create;
    destructor Destroy; override;
    
    class function Instance: TMessageQueueManager;
    
    // RabbitMQ
    procedure RegisterRabbitMQ(const AName: string; AConnection: IRabbitMQConnection);
    function GetRabbitMQ(const AName: string): IRabbitMQConnection;
    
    // Kafka
    procedure RegisterKafkaProducer(const AName: string; AProducer: IKafkaProducer);
    procedure RegisterKafkaConsumer(const AName: string; AConsumer: IKafkaConsumer);
    function GetKafkaProducer(const AName: string): IKafkaProducer;
    function GetKafkaConsumer(const AName: string): IKafkaConsumer;
    
    // 统一发送接�?
    procedure SendMessage(const AQueueName, ATopic: string; const AMessage: TQueueMessage);
    procedure SendKafkaRecord(const AProducerName, ATopic: string; const ARecord: TKafkaRecord);
  end;

  // 引入 RabbitMQ 接口
  IRabbitMQConnection = UniFlow.Queue.RabbitMQ.IRabbitMQConnection;

implementation

uses
  UniFlow.Queue.RabbitMQ;

{==========================================================================}
{  TKafkaConnectionConfig                                                  }
{==========================================================================}

constructor TKafkaConnectionConfig.Create;
begin
  inherited Create;
  FBootstrapServers := 'localhost:9092';
  FClientId := 'uniflow-client';
  FAcks := 'all';
  FRetries := 3;
  FRetryBackoffMs := 100;
  FRequestTimeoutMs := 30000;
  FSecurityProtocol := 'PLAINTEXT';
end;

{==========================================================================}
{  TKafkaProducerConfig                                                    }
{==========================================================================}

constructor TKafkaProducerConfig.Create;
begin
  inherited Create;
  FBatchSize := 16384;
  FLingerMs := 0;
  FBufferMemory := 33554432;      // 32 MB
  FMaxBlockMs := 60000;
  FCompressionType := 'none';
  FIdempotence := False;
end;

{==========================================================================}
{  TKafkaProducer                                                          }
{==========================================================================}

constructor TKafkaProducer.Create(const AConfig: TKafkaConnectionConfig;
  const ARestProxyUrl: string);
begin
  inherited Create;
  FConfig := AConfig;
  FProducerConfig := TKafkaProducerConfig.Create;
  FRestProxyUrl := ARestProxyUrl;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ContentType := 'application/vnd.kafka.json.v2+json';
  FLock := TCriticalSection.Create;
  FPendingRecords := TList<TKafkaRecord>.Create;
end;

destructor TKafkaProducer.Destroy;
begin
  Close;
  FPendingRecords.Free;
  FProducerConfig.Free;
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

function TKafkaProducer.GetRestUrl(const APath: string): string;
begin
  Result := FRestProxyUrl + APath;
end;

procedure TKafkaProducer.Send(const ATopic: string; const ARecord: TKafkaRecord);
var
  LBody, LRecordObj: TJSONObject;
  LRecords: TJSONArray;
  LResponse: IHTTPResponse;
  LStream: TStringStream;
begin
  FLock.Enter;
  try
    LBody := TJSONObject.Create;
    try
      LRecords := TJSONArray.Create;
      
      LRecordObj := TJSONObject.Create;
      if Length(ARecord.Key) > 0 then
        LRecordObj.AddPair('key', TNetEncoding.Base64.EncodeBytesToString(ARecord.Key));
      LRecordObj.AddPair('value', TNetEncoding.Base64.EncodeBytesToString(ARecord.Value));
      if ARecord.Partition >= 0 then
        LRecordObj.AddPair('partition', TJSONNumber.Create(ARecord.Partition));
        
      LRecords.AddElement(LRecordObj);
      LBody.AddPair('records', LRecords);
      
      LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
      try
        LResponse := FHttpClient.Post(GetRestUrl('/topics/' + ATopic), LStream);
        
        if LResponse.StatusCode >= 400 then
          raise EOperationException.CreateFmt('Kafka 发送失�? %d %s', 
            [LResponse.StatusCode, LResponse.StatusText]);
      finally
        LStream.Free;
      end;
    finally
      LBody.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TKafkaProducer.SendAsync(const ATopic: string; const ARecord: TKafkaRecord;
  ACallback: TProc<Boolean, string>);
begin
  TTask.Run(
    procedure
    begin
      try
        Send(ATopic, ARecord);
        if Assigned(ACallback) then
          TThread.Queue(nil,
            procedure
            begin
              ACallback(True, '');
            end);
      except
        on E: Exception do
          if Assigned(ACallback) then
            TThread.Queue(nil,
              procedure
              begin
                ACallback(False, E.Message);
              end);
      end;
    end);
end;

procedure TKafkaProducer.Flush;
begin
  // REST Proxy 是同步的，无需 flush
end;

procedure TKafkaProducer.Close;
begin
  Flush;
end;

{==========================================================================}
{  TKafkaConsumer                                                          }
{==========================================================================}

constructor TKafkaConsumer.Create(const AConfig: TKafkaConnectionConfig;
  const AConsumerConfig: TKafkaConsumerConfig;
  const ARestProxyUrl: string);
begin
  inherited Create;
  FConfig := AConfig;
  FConsumerConfig := AConsumerConfig;
  FRestProxyUrl := ARestProxyUrl;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ContentType := 'application/vnd.kafka.v2+json';
  FSubscribedTopics := TList<string>.Create;
  FLock := TCriticalSection.Create;
  
  CreateConsumerInstance;
end;

destructor TKafkaConsumer.Destroy;
begin
  Close;
  FSubscribedTopics.Free;
  FHttpClient.Free;
  FLock.Free;
  inherited;
end;

function TKafkaConsumer.GetRestUrl(const APath: string): string;
begin
  Result := FRestProxyUrl + APath;
end;

procedure TKafkaConsumer.CreateConsumerInstance;
var
  LBody: TJSONObject;
  LResponse: IHTTPResponse;
  LResult: TJSONObject;
  LStream: TStringStream;
begin
  FInstanceId := 'uniflow_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '');
  
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('name', FInstanceId);
    LBody.AddPair('format', 'json');
    LBody.AddPair('auto.offset.reset', FConsumerConfig.OffsetReset);
    LBody.AddPair('auto.commit.enable', TJSONBool.Create(FConsumerConfig.AutoCommit));
    
    LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
    try
      LResponse := FHttpClient.Post(
        GetRestUrl('/consumers/' + FConsumerConfig.GroupId), LStream);
      
      if LResponse.StatusCode = 200 then
      begin
        LResult := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
        try
          FConsumerId := LResult.GetValue<string>('instance_id', FInstanceId);
        finally
          LResult.Free;
        end;
      end
      else
        raise EOperationException.CreateFmt('创建 Kafka 消费者失�? %d', [LResponse.StatusCode]);
    finally
      LStream.Free;
    end;
  finally
    LBody.Free;
  end;
end;

procedure TKafkaConsumer.DeleteConsumerInstance;
var
  LResponse: IHTTPResponse;
begin
  if FConsumerId = '' then Exit;
  
  LResponse := FHttpClient.Delete(
    GetRestUrl(Format('/consumers/%s/instances/%s', 
      [FConsumerConfig.GroupId, FConsumerId])));
      
  FConsumerId := '';
end;

procedure TKafkaConsumer.Subscribe(const ATopics: TArray<string>);
var
  LBody: TJSONObject;
  LTopics: TJSONArray;
  LTopic: string;
  LResponse: IHTTPResponse;
  LStream: TStringStream;
begin
  FLock.Enter;
  try
    FSubscribedTopics.Clear;
    
    LBody := TJSONObject.Create;
    try
      LTopics := TJSONArray.Create;
      for LTopic in ATopics do
      begin
        LTopics.Add(LTopic);
        FSubscribedTopics.Add(LTopic);
      end;
      LBody.AddPair('topics', LTopics);
      
      LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
      try
        LResponse := FHttpClient.Post(
          GetRestUrl(Format('/consumers/%s/instances/%s/subscription',
            [FConsumerConfig.GroupId, FConsumerId])), LStream);
            
        if LResponse.StatusCode >= 400 then
          raise EOperationException.CreateFmt('订阅失败: %d', [LResponse.StatusCode]);
      finally
        LStream.Free;
      end;
    finally
      LBody.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TKafkaConsumer.Unsubscribe;
var
  LResponse: IHTTPResponse;
begin
  FLock.Enter;
  try
    LResponse := FHttpClient.Delete(
      GetRestUrl(Format('/consumers/%s/instances/%s/subscription',
        [FConsumerConfig.GroupId, FConsumerId])));
        
    FSubscribedTopics.Clear;
  finally
    FLock.Leave;
  end;
end;

function TKafkaConsumer.Poll(ATimeoutMs: Integer): TArray<TKafkaRecord>;
var
  LResponse: IHTTPResponse;
  LJSON: TJSONArray;
  LItem: TJSONValue;
  LObj: TJSONObject;
  LRecord: TKafkaRecord;
  LRecords: TList<TKafkaRecord>;
begin
  FLock.Enter;
  try
    FHttpClient.CustomHeaders['Accept'] := 'application/vnd.kafka.json.v2+json';
    
    LResponse := FHttpClient.Get(
      GetRestUrl(Format('/consumers/%s/instances/%s/records?timeout=%d',
        [FConsumerConfig.GroupId, FConsumerId, ATimeoutMs])));
        
    LRecords := TList<TKafkaRecord>.Create;
    try
      if LResponse.StatusCode = 200 then
      begin
        LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONArray;
        try
          for LItem in LJSON do
          begin
            LObj := LItem as TJSONObject;
            LRecord := TKafkaRecord.Create;
            LRecord.Topic := LObj.GetValue<string>('topic', '');
            LRecord.Partition := LObj.GetValue<Integer>('partition', 0);
            LRecord.Offset := LObj.GetValue<Int64>('offset', 0);
            
            if LObj.GetValue('key') <> nil then
              LRecord.SetKeyAsString(LObj.GetValue<string>('key', ''));
            if LObj.GetValue('value') <> nil then
              LRecord.SetValueAsString(LObj.GetValue('value').ToJSON);
              
            LRecords.Add(LRecord);
          end;
        finally
          LJSON.Free;
        end;
      end;
      
      Result := LRecords.ToArray;
    finally
      LRecords.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TKafkaConsumer.Commit;
var
  LResponse: IHTTPResponse;
begin
  LResponse := FHttpClient.Post(
    GetRestUrl(Format('/consumers/%s/instances/%s/offsets',
      [FConsumerConfig.GroupId, FConsumerId])), nil);
      
  if LResponse.StatusCode >= 400 then
    raise EOperationException.CreateFmt('提交偏移量失�? %d', [LResponse.StatusCode]);
end;

procedure TKafkaConsumer.CommitAsync(ACallback: TProc<Boolean, string>);
begin
  TTask.Run(
    procedure
    begin
      try
        Commit;
        if Assigned(ACallback) then
          TThread.Queue(nil,
            procedure
            begin
              ACallback(True, '');
            end);
      except
        on E: Exception do
          if Assigned(ACallback) then
            TThread.Queue(nil,
              procedure
              begin
                ACallback(False, E.Message);
              end);
      end;
    end);
end;

procedure TKafkaConsumer.Seek(const ATopic: string; APartition: Integer; AOffset: Int64);
var
  LBody: TJSONObject;
  LPartitions: TJSONArray;
  LPartObj: TJSONObject;
  LResponse: IHTTPResponse;
  LStream: TStringStream;
begin
  LBody := TJSONObject.Create;
  try
    LPartitions := TJSONArray.Create;
    LPartObj := TJSONObject.Create;
    LPartObj.AddPair('topic', ATopic);
    LPartObj.AddPair('partition', TJSONNumber.Create(APartition));
    LPartObj.AddPair('offset', TJSONNumber.Create(AOffset));
    LPartitions.AddElement(LPartObj);
    LBody.AddPair('offsets', LPartitions);
    
    LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
    try
      LResponse := FHttpClient.Post(
        GetRestUrl(Format('/consumers/%s/instances/%s/positions',
          [FConsumerConfig.GroupId, FConsumerId])), LStream);
    finally
      LStream.Free;
    end;
  finally
    LBody.Free;
  end;
end;

procedure TKafkaConsumer.Close;
begin
  Unsubscribe;
  DeleteConsumerInstance;
end;

{==========================================================================}
{  TKafkaAdmin                                                             }
{==========================================================================}

constructor TKafkaAdmin.Create(const AConfig: TKafkaConnectionConfig;
  const ARestProxyUrl: string);
begin
  inherited Create;
  FConfig := AConfig;
  FRestProxyUrl := ARestProxyUrl;
  FHttpClient := THTTPClient.Create;
  FHttpClient.ContentType := 'application/json';
end;

destructor TKafkaAdmin.Destroy;
begin
  FHttpClient.Free;
  inherited;
end;

function TKafkaAdmin.GetRestUrl(const APath: string): string;
begin
  Result := FRestProxyUrl + APath;
end;

procedure TKafkaAdmin.CreateTopic(const AConfig: TKafkaTopicConfig);
var
  LBody, LConfigs: TJSONObject;
  LResponse: IHTTPResponse;
  LStream: TStringStream;
begin
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('topic_name', AConfig.Name);
    LBody.AddPair('partitions_count', TJSONNumber.Create(AConfig.Partitions));
    LBody.AddPair('replication_factor', TJSONNumber.Create(AConfig.ReplicationFactor));
    
    LConfigs := TJSONObject.Create;
    LConfigs.AddPair('retention.ms', IntToStr(AConfig.RetentionMs));
    if AConfig.RetentionBytes > 0 then
      LConfigs.AddPair('retention.bytes', IntToStr(AConfig.RetentionBytes));
    LConfigs.AddPair('cleanup.policy', AConfig.CleanupPolicy);
    LConfigs.AddPair('compression.type', AConfig.CompressionType);
    LBody.AddPair('configs', LConfigs);
    
    LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
    try
      LResponse := FHttpClient.Post(GetRestUrl('/v3/clusters/kafka/topics'), LStream);
      
      if LResponse.StatusCode >= 400 then
        raise EOperationException.CreateFmt('创建主题失败: %d %s',
          [LResponse.StatusCode, LResponse.StatusText]);
    finally
      LStream.Free;
    end;
  finally
    LBody.Free;
  end;
end;

procedure TKafkaAdmin.DeleteTopic(const ATopic: string);
var
  LResponse: IHTTPResponse;
begin
  LResponse := FHttpClient.Delete(
    GetRestUrl('/v3/clusters/kafka/topics/' + TNetEncoding.URL.Encode(ATopic)));
    
  if LResponse.StatusCode >= 400 then
    raise EOperationException.CreateFmt('删除主题失败: %d', [LResponse.StatusCode]);
end;

function TKafkaAdmin.ListTopics: TArray<string>;
var
  LResponse: IHTTPResponse;
  LJSON: TJSONObject;
  LData: TJSONArray;
  LItem: TJSONValue;
  LTopics: TList<string>;
begin
  LResponse := FHttpClient.Get(GetRestUrl('/v3/clusters/kafka/topics'));
  
  LTopics := TList<string>.Create;
  try
    if LResponse.StatusCode = 200 then
    begin
      LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
      try
        if LJSON.TryGetValue<TJSONArray>('data', LData) then
          for LItem in LData do
            LTopics.Add((LItem as TJSONObject).GetValue<string>('topic_name', ''));
      finally
        LJSON.Free;
      end;
    end;
    
    Result := LTopics.ToArray;
  finally
    LTopics.Free;
  end;
end;

function TKafkaAdmin.DescribeTopic(const ATopic: string): TKafkaTopicConfig;
var
  LResponse: IHTTPResponse;
  LJSON: TJSONObject;
begin
  Result := TKafkaTopicConfig.Create(ATopic);
  
  LResponse := FHttpClient.Get(
    GetRestUrl('/v3/clusters/kafka/topics/' + TNetEncoding.URL.Encode(ATopic)));
    
  if LResponse.StatusCode = 200 then
  begin
    LJSON := TJSONObject.ParseJSONValue(LResponse.ContentAsString) as TJSONObject;
    try
      Result.Partitions := LJSON.GetValue<Integer>('partitions_count', 1);
      Result.ReplicationFactor := LJSON.GetValue<Integer>('replication_factor', 1);
    finally
      LJSON.Free;
    end;
  end;
end;

procedure TKafkaAdmin.CreatePartitions(const ATopic: string; ANumPartitions: Integer);
var
  LBody: TJSONObject;
  LResponse: IHTTPResponse;
  LStream: TStringStream;
begin
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('partitions_count', TJSONNumber.Create(ANumPartitions));
    
    LStream := TStringStream.Create(LBody.ToJSON, TEncoding.UTF8);
    try
      LResponse := FHttpClient.Post(
        GetRestUrl('/v3/clusters/kafka/topics/' + 
          TNetEncoding.URL.Encode(ATopic) + '/partitions'), LStream);
    finally
      LStream.Free;
    end;
  finally
    LBody.Free;
  end;
end;

{==========================================================================}
{  TKafkaWorkflowTrigger                                                   }
{==========================================================================}

constructor TKafkaWorkflowTrigger.Create(AProducer: IKafkaProducer;
  AConsumer: IKafkaConsumer);
begin
  inherited Create;
  FProducer := AProducer;
  FConsumer := AConsumer;
  FTopic := 'uniflow-workflow-trigger';
  FRunning := False;
end;

destructor TKafkaWorkflowTrigger.Destroy;
begin
  Stop;
  inherited;
end;

procedure TKafkaWorkflowTrigger.Initialize(const ATopic: string);
begin
  FTopic := ATopic;
  FConsumer.Subscribe([FTopic]);
end;

procedure TKafkaWorkflowTrigger.ConsumerLoop;
var
  LRecords: TArray<TKafkaRecord>;
  LRecord: TKafkaRecord;
  LTrigger: TWorkflowTriggerMessage;
  LJSON: TJSONObject;
begin
  while FRunning do
  begin
    try
      LRecords := FConsumer.Poll(1000);
      
      for LRecord in LRecords do
      begin
        try
          LJSON := TJSONObject.ParseJSONValue(LRecord.GetValueAsString) as TJSONObject;
          if Assigned(LJSON) then
          begin
            try
              LTrigger := TWorkflowTriggerMessage.Create;
              try
                LTrigger.FromJSON(LJSON);
                
                if Assigned(FOnWorkflowTrigger) then
                  FOnWorkflowTrigger(LTrigger);
              finally
                LTrigger.Free;
              end;
            finally
              LJSON.Free;
            end;
          end;
        finally
          LRecord.Free;
        end;
      end;
      
      FConsumer.Commit;
    except
      Sleep(1000);
    end;
  end;
end;

procedure TKafkaWorkflowTrigger.Start;
begin
  if FRunning then Exit;
  
  FRunning := True;
  FConsumerThread := TThread.CreateAnonymousThread(ConsumerLoop);
  FConsumerThread.FreeOnTerminate := False;
  FConsumerThread.Start;
end;

procedure TKafkaWorkflowTrigger.Stop;
begin
  if not FRunning then Exit;
  
  FRunning := False;
  
  if Assigned(FConsumerThread) then
  begin
    FConsumerThread.Terminate;
    FConsumerThread.WaitFor;
    FConsumerThread.Free;
    FConsumerThread := nil;
  end;
end;

procedure TKafkaWorkflowTrigger.TriggerWorkflow(const AWorkflowId: string;
  APayload: TJSONObject);
var
  LTrigger: TWorkflowTriggerMessage;
  LRecord: TKafkaRecord;
begin
  LTrigger := TWorkflowTriggerMessage.Create;
  try
    LTrigger.WorkflowId := AWorkflowId;
    LTrigger.TriggerType := 'immediate';
    if Assigned(APayload) then
      LTrigger.Payload.AddPair('data', APayload.Clone as TJSONObject);
      
    LRecord := TKafkaRecord.Create;
    try
      LRecord.SetKeyAsString(AWorkflowId);
      LRecord.SetValueAsJSON(LTrigger.ToJSON);
      
      FProducer.Send(FTopic, LRecord);
    finally
      LRecord.Free;
    end;
  finally
    LTrigger.Free;
  end;
end;

procedure TKafkaWorkflowTrigger.ScheduleWorkflow(const AWorkflowId: string;
  AScheduledTime: TDateTime; APayload: TJSONObject);
var
  LTrigger: TWorkflowTriggerMessage;
  LRecord: TKafkaRecord;
begin
  LTrigger := TWorkflowTriggerMessage.Create;
  try
    LTrigger.WorkflowId := AWorkflowId;
    LTrigger.TriggerType := 'scheduled';
    LTrigger.ScheduledTime := AScheduledTime;
    if Assigned(APayload) then
      LTrigger.Payload.AddPair('data', APayload.Clone as TJSONObject);
      
    LRecord := TKafkaRecord.Create;
    try
      LRecord.SetKeyAsString(AWorkflowId);
      LRecord.SetValueAsJSON(LTrigger.ToJSON);
      LRecord.Headers['X-Scheduled-Time'] := DateToISO8601(AScheduledTime);
      
      FProducer.Send(FTopic, LRecord);
    finally
      LRecord.Free;
    end;
  finally
    LTrigger.Free;
  end;
end;

{==========================================================================}
{  TKafkaStreamProcessor                                                   }
{==========================================================================}

constructor TKafkaStreamProcessor.Create(AConsumer: IKafkaConsumer;
  AProducer: IKafkaProducer);
begin
  inherited Create;
  FConsumer := AConsumer;
  FProducer := AProducer;
  FRunning := False;
end;

destructor TKafkaStreamProcessor.Destroy;
begin
  Stop;
  inherited;
end;

procedure TKafkaStreamProcessor.SetInputTopics(const ATopics: TArray<string>);
begin
  FInputTopics := ATopics;
end;

procedure TKafkaStreamProcessor.SetOutputTopic(const ATopic: string);
begin
  FOutputTopic := ATopic;
end;

procedure TKafkaStreamProcessor.SetProcessor(AProcessor: TFunc<TKafkaRecord, TKafkaRecord>);
begin
  FProcessor := AProcessor;
end;

procedure TKafkaStreamProcessor.SetFilter(AFilter: TFunc<TKafkaRecord, Boolean>);
begin
  FFilter := AFilter;
end;

procedure TKafkaStreamProcessor.Start;
begin
  if FRunning then Exit;
  if not Assigned(FProcessor) then Exit;
  
  FRunning := True;
  FConsumer.Subscribe(FInputTopics);
  
  FProcessThread := TThread.CreateAnonymousThread(
    procedure
    var
      LRecords: TArray<TKafkaRecord>;
      LRecord, LOutput: TKafkaRecord;
    begin
      while FRunning do
      begin
        try
          LRecords := FConsumer.Poll(1000);
          
          for LRecord in LRecords do
          begin
            try
              // 应用过滤�?
              if Assigned(FFilter) and not FFilter(LRecord) then
                Continue;
                
              // 处理记录
              LOutput := FProcessor(LRecord);
              if Assigned(LOutput) then
              begin
                try
                  if FOutputTopic <> '' then
                    FProducer.Send(FOutputTopic, LOutput);
                finally
                  if LOutput <> LRecord then
                    LOutput.Free;
                end;
              end;
            finally
              LRecord.Free;
            end;
          end;
          
          FConsumer.Commit;
        except
          Sleep(1000);
        end;
      end;
    end);
    
  FProcessThread.FreeOnTerminate := False;
  FProcessThread.Start;
end;

procedure TKafkaStreamProcessor.Stop;
begin
  if not FRunning then Exit;
  
  FRunning := False;
  
  if Assigned(FProcessThread) then
  begin
    FProcessThread.Terminate;
    FProcessThread.WaitFor;
    FProcessThread.Free;
    FProcessThread := nil;
  end;
  
  FConsumer.Unsubscribe;
end;

function TKafkaStreamProcessor.IsRunning: Boolean;
begin
  Result := FRunning;
end;

{==========================================================================}
{  TMessageQueueManager                                                    }
{==========================================================================}

constructor TMessageQueueManager.Create;
begin
  inherited Create;
  FRabbitMQConnections := TDictionary<string, IRabbitMQConnection>.Create;
  FKafkaProducers := TDictionary<string, IKafkaProducer>.Create;
  FKafkaConsumers := TDictionary<string, IKafkaConsumer>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TMessageQueueManager.Destroy;
begin
  FRabbitMQConnections.Free;
  FKafkaProducers.Free;
  FKafkaConsumers.Free;
  FLock.Free;
  inherited;
end;

class function TMessageQueueManager.Instance: TMessageQueueManager;
begin
  if FInstance = nil then
    FInstance := TMessageQueueManager.Create;
  Result := FInstance;
end;

procedure TMessageQueueManager.RegisterRabbitMQ(const AName: string;
  AConnection: IRabbitMQConnection);
begin
  FLock.Enter;
  try
    FRabbitMQConnections.AddOrSetValue(AName, AConnection);
  finally
    FLock.Leave;
  end;
end;

function TMessageQueueManager.GetRabbitMQ(const AName: string): IRabbitMQConnection;
begin
  FLock.Enter;
  try
    if not FRabbitMQConnections.TryGetValue(AName, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TMessageQueueManager.RegisterKafkaProducer(const AName: string;
  AProducer: IKafkaProducer);
begin
  FLock.Enter;
  try
    FKafkaProducers.AddOrSetValue(AName, AProducer);
  finally
    FLock.Leave;
  end;
end;

procedure TMessageQueueManager.RegisterKafkaConsumer(const AName: string;
  AConsumer: IKafkaConsumer);
begin
  FLock.Enter;
  try
    FKafkaConsumers.AddOrSetValue(AName, AConsumer);
  finally
    FLock.Leave;
  end;
end;

function TMessageQueueManager.GetKafkaProducer(const AName: string): IKafkaProducer;
begin
  FLock.Enter;
  try
    if not FKafkaProducers.TryGetValue(AName, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TMessageQueueManager.GetKafkaConsumer(const AName: string): IKafkaConsumer;
begin
  FLock.Enter;
  try
    if not FKafkaConsumers.TryGetValue(AName, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TMessageQueueManager.SendMessage(const AQueueName, ATopic: string;
  const AMessage: TQueueMessage);
var
  LConnection: IRabbitMQConnection;
  LChannel: IRabbitMQChannel;
begin
  LConnection := GetRabbitMQ(AQueueName);
  if Assigned(LConnection) then
  begin
    LChannel := LConnection.CreateChannel;
    try
      LChannel.BasicPublish('', ATopic, AMessage);
    finally
      LChannel.Close;
    end;
  end;
end;

procedure TMessageQueueManager.SendKafkaRecord(const AProducerName, ATopic: string;
  const ARecord: TKafkaRecord);
var
  LProducer: IKafkaProducer;
begin
  LProducer := GetKafkaProducer(AProducerName);
  if Assigned(LProducer) then
    LProducer.Send(ATopic, ARecord);
end;

end.
