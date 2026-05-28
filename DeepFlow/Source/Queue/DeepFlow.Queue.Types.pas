unit UniFlow.Queue.Types;

{*******************************************************}
{                                                       }
{       UniFlow 消息队列类型定义                        }
{                                                       }
{       版权所�?(C) 2024 UniFlow                       }
{                                                       }
{*******************************************************}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.SyncObjs;

type
  {==========================================================================}
  {  消息优先�?                                                             }
  {==========================================================================}
  TMessagePriority = (
    mpLowest    = 0,
    mpLow       = 1,
    mpNormal    = 2,
    mpHigh      = 3,
    mpHighest   = 4,
    mpCritical  = 5
  );

  {==========================================================================}
  {  消息状�?                                                               }
  {==========================================================================}
  TMessageStatus = (
    msPending,      // 待处�?
    msProcessing,   // 处理�?
    msCompleted,    // 已完�?
    msFailed,       // 失败
    msDeadLetter,   // 死信
    msExpired,      // 已过�?
    msRetrying      // 重试�?
  );

  {==========================================================================}
  {  消息投递模�?                                                           }
  {==========================================================================}
  TDeliveryMode = (
    dmAtMostOnce,   // 最多一次（可能丢失�?
    dmAtLeastOnce,  // 至少一次（可能重复�?
    dmExactlyOnce   // 恰好一次（事务性）
  );

  {==========================================================================}
  {  交换类型 (RabbitMQ)                                                     }
  {==========================================================================}
  TExchangeType = (
    etDirect,       // 直连
    etFanout,       // 扇出
    etTopic,        // 主题
    etHeaders       // 头匹�?
  );

  {==========================================================================}
  {  消息�?                                                                 }
  {==========================================================================}
  TMessageHeaders = class
  private
    FItems: TDictionary<string, string>;
    function GetItem(const AKey: string): string;
    procedure SetItem(const AKey, AValue: string);
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(const AKey, AValue: string);
    procedure Remove(const AKey: string);
    function Contains(const AKey: string): Boolean;
    function TryGetValue(const AKey: string; out AValue: string): Boolean;
    procedure Clear;

    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);

    property Items[const AKey: string]: string read GetItem write SetItem; default;
    property Count: Integer read GetCount;
  end;

  {==========================================================================}
  {  队列消息                                                                }
  {==========================================================================}
  TQueueMessage = class
  private
    FMessageId: string;
    FCorrelationId: string;
    FReplyTo: string;
    FContentType: string;
    FContentEncoding: string;
    FBody: TBytes;
    FHeaders: TMessageHeaders;
    FPriority: TMessagePriority;
    FTimestamp: TDateTime;
    FExpiration: Int64;           // 过期时间（毫秒）
    FDeliveryTag: UInt64;
    FRedelivered: Boolean;
    FExchange: string;
    FRoutingKey: string;
    FRetryCount: Integer;
    FStatus: TMessageStatus;
    FErrorMessage: string;
  public
    constructor Create;
    destructor Destroy; override;

    // 消息体辅助方�?
    procedure SetBodyAsString(const AValue: string; AEncoding: TEncoding = nil);
    function GetBodyAsString(AEncoding: TEncoding = nil): string;
    procedure SetBodyAsJSON(AValue: TJSONValue);
    function GetBodyAsJSON: TJSONValue;

    // 序列�?
    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);
    function Clone: TQueueMessage;

    // 属�?
    property MessageId: string read FMessageId write FMessageId;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
    property ReplyTo: string read FReplyTo write FReplyTo;
    property ContentType: string read FContentType write FContentType;
    property ContentEncoding: string read FContentEncoding write FContentEncoding;
    property Body: TBytes read FBody write FBody;
    property Headers: TMessageHeaders read FHeaders;
    property Priority: TMessagePriority read FPriority write FPriority;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property Expiration: Int64 read FExpiration write FExpiration;
    property DeliveryTag: UInt64 read FDeliveryTag write FDeliveryTag;
    property Redelivered: Boolean read FRedelivered write FRedelivered;
    property Exchange: string read FExchange write FExchange;
    property RoutingKey: string read FRoutingKey write FRoutingKey;
    property RetryCount: Integer read FRetryCount write FRetryCount;
    property Status: TMessageStatus read FStatus write FStatus;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
  end;

  {==========================================================================}
  {  队列配置                                                                }
  {==========================================================================}
  TQueueConfig = class
  private
    FName: string;
    FDurable: Boolean;            // 持久�?
    FExclusive: Boolean;          // 排他
    FAutoDelete: Boolean;         // 自动删除
    FMaxLength: Integer;          // 最大消息数
    FMaxLengthBytes: Int64;       // 最大字节数
    FMessageTTL: Int64;           // 消息 TTL（毫秒）
    FDeadLetterExchange: string;  // 死信交换
    FDeadLetterRoutingKey: string;
    FArguments: TDictionary<string, Variant>;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);

    property Name: string read FName write FName;
    property Durable: Boolean read FDurable write FDurable;
    property Exclusive: Boolean read FExclusive write FExclusive;
    property AutoDelete: Boolean read FAutoDelete write FAutoDelete;
    property MaxLength: Integer read FMaxLength write FMaxLength;
    property MaxLengthBytes: Int64 read FMaxLengthBytes write FMaxLengthBytes;
    property MessageTTL: Int64 read FMessageTTL write FMessageTTL;
    property DeadLetterExchange: string read FDeadLetterExchange write FDeadLetterExchange;
    property DeadLetterRoutingKey: string read FDeadLetterRoutingKey write FDeadLetterRoutingKey;
    property Arguments: TDictionary<string, Variant> read FArguments;
  end;

  {==========================================================================}
  {  交换配置                                                                }
  {==========================================================================}
  TExchangeConfig = class
  private
    FName: string;
    FExchangeType: TExchangeType;
    FDurable: Boolean;
    FAutoDelete: Boolean;
    FInternal: Boolean;
    FArguments: TDictionary<string, Variant>;
  public
    constructor Create(const AName: string; AType: TExchangeType = etDirect);
    destructor Destroy; override;

    function GetTypeString: string;
    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);

    property Name: string read FName write FName;
    property ExchangeType: TExchangeType read FExchangeType write FExchangeType;
    property Durable: Boolean read FDurable write FDurable;
    property AutoDelete: Boolean read FAutoDelete write FAutoDelete;
    property Internal: Boolean read FInternal write FInternal;
    property Arguments: TDictionary<string, Variant> read FArguments;
  end;

  {==========================================================================}
  {  绑定配置                                                                }
  {==========================================================================}
  TBindingConfig = class
  private
    FSourceExchange: string;
    FDestQueue: string;
    FDestExchange: string;
    FRoutingKey: string;
    FArguments: TDictionary<string, Variant>;
  public
    constructor Create;
    destructor Destroy; override;

    property SourceExchange: string read FSourceExchange write FSourceExchange;
    property DestQueue: string read FDestQueue write FDestQueue;
    property DestExchange: string read FDestExchange write FDestExchange;
    property RoutingKey: string read FRoutingKey write FRoutingKey;
    property Arguments: TDictionary<string, Variant> read FArguments;
  end;

  {==========================================================================}
  {  消费者配�?                                                             }
  {==========================================================================}
  TConsumerConfig = class
  private
    FConsumerTag: string;
    FAutoAck: Boolean;            // 自动确认
    FExclusive: Boolean;          // 排他
    FPrefetchCount: Word;         // 预取数量
    FPrefetchSize: Cardinal;      // 预取大小
    FGlobalPrefetch: Boolean;     // 全局预取
  public
    constructor Create;

    property ConsumerTag: string read FConsumerTag write FConsumerTag;
    property AutoAck: Boolean read FAutoAck write FAutoAck;
    property Exclusive: Boolean read FExclusive write FExclusive;
    property PrefetchCount: Word read FPrefetchCount write FPrefetchCount;
    property PrefetchSize: Cardinal read FPrefetchSize write FPrefetchSize;
    property GlobalPrefetch: Boolean read FGlobalPrefetch write FGlobalPrefetch;
  end;

  {==========================================================================}
  {  连接配置                                                                }
  {==========================================================================}
  TQueueConnectionConfig = class
  private
    FHost: string;
    FPort: Integer;
    FVirtualHost: string;
    FUsername: string;
    FPassword: string;
    FSSL: Boolean;
    FConnectionTimeout: Integer;
    FHeartbeat: Integer;
    FReconnectDelay: Integer;
    FMaxReconnectAttempts: Integer;
  public
    constructor Create;

    function GetConnectionString: string;

    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property VirtualHost: string read FVirtualHost write FVirtualHost;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property SSL: Boolean read FSSL write FSSL;
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property Heartbeat: Integer read FHeartbeat write FHeartbeat;
    property ReconnectDelay: Integer read FReconnectDelay write FReconnectDelay;
    property MaxReconnectAttempts: Integer read FMaxReconnectAttempts write FMaxReconnectAttempts;
  end;

  {==========================================================================}
  {  Kafka 分区策略                                                          }
  {==========================================================================}
  TPartitionStrategy = (
    psRoundRobin,     // 轮询
    psKeyHash,        // 键哈�?
    psSticky,         // 粘�?
    psManual          // 手动
  );

  {==========================================================================}
  {  Kafka 主题配置                                                          }
  {==========================================================================}
  TKafkaTopicConfig = class
  private
    FName: string;
    FPartitions: Integer;
    FReplicationFactor: Integer;
    FRetentionMs: Int64;
    FRetentionBytes: Int64;
    FCleanupPolicy: string;
    FCompressionType: string;
  public
    constructor Create(const AName: string);

    property Name: string read FName write FName;
    property Partitions: Integer read FPartitions write FPartitions;
    property ReplicationFactor: Integer read FReplicationFactor write FReplicationFactor;
    property RetentionMs: Int64 read FRetentionMs write FRetentionMs;
    property RetentionBytes: Int64 read FRetentionBytes write FRetentionBytes;
    property CleanupPolicy: string read FCleanupPolicy write FCleanupPolicy;
    property CompressionType: string read FCompressionType write FCompressionType;
  end;

  {==========================================================================}
  {  Kafka 消费者配�?                                                       }
  {==========================================================================}
  TKafkaConsumerConfig = class
  private
    FGroupId: string;
    FAutoCommit: Boolean;
    FAutoCommitIntervalMs: Integer;
    FSessionTimeoutMs: Integer;
    FMaxPollRecords: Integer;
    FOffsetReset: string;         // earliest, latest, none
  public
    constructor Create(const AGroupId: string);

    property GroupId: string read FGroupId write FGroupId;
    property AutoCommit: Boolean read FAutoCommit write FAutoCommit;
    property AutoCommitIntervalMs: Integer read FAutoCommitIntervalMs write FAutoCommitIntervalMs;
    property SessionTimeoutMs: Integer read FSessionTimeoutMs write FSessionTimeoutMs;
    property MaxPollRecords: Integer read FMaxPollRecords write FMaxPollRecords;
    property OffsetReset: string read FOffsetReset write FOffsetReset;
  end;

  {==========================================================================}
  {  Kafka 消息记录                                                          }
  {==========================================================================}
  TKafkaRecord = class
  private
    FTopic: string;
    FPartition: Integer;
    FOffset: Int64;
    FKey: TBytes;
    FValue: TBytes;
    FHeaders: TMessageHeaders;
    FTimestamp: TDateTime;
    FTimestampType: string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure SetKeyAsString(const AValue: string);
    function GetKeyAsString: string;
    procedure SetValueAsString(const AValue: string);
    function GetValueAsString: string;
    procedure SetValueAsJSON(AValue: TJSONValue);
    function GetValueAsJSON: TJSONValue;

    property Topic: string read FTopic write FTopic;
    property Partition: Integer read FPartition write FPartition;
    property Offset: Int64 read FOffset write FOffset;
    property Key: TBytes read FKey write FKey;
    property Value: TBytes read FValue write FValue;
    property Headers: TMessageHeaders read FHeaders;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property TimestampType: string read FTimestampType write FTimestampType;
  end;

  {==========================================================================}
  {  消息处理结果                                                            }
  {==========================================================================}
  TMessageProcessResult = (
    mprAck,           // 确认成功
    mprNack,          // 否定确认（重新入队）
    mprReject,        // 拒绝（不重新入队�?
    mprDefer          // 延迟处理
  );

  {==========================================================================}
  {  消息处理回调                                                            }
  {==========================================================================}
  TMessageHandler = reference to procedure(const AMessage: TQueueMessage;
    var AResult: TMessageProcessResult);

  TKafkaRecordHandler = reference to procedure(const ARecord: TKafkaRecord;
    var AResult: TMessageProcessResult);

  TBatchMessageHandler = reference to procedure(const AMessages: TArray<TQueueMessage>;
    var AResults: TArray<TMessageProcessResult>);

  {==========================================================================}
  {  队列统计                                                                }
  {==========================================================================}
  TQueueStatistics = record
    QueueName: string;
    MessageCount: Int64;
    ConsumerCount: Integer;
    PublishRate: Double;          // 消息/�?
    DeliverRate: Double;
    AckRate: Double;
    UnackedCount: Int64;
    ReadyCount: Int64;
    MemoryUsage: Int64;
    DiskUsage: Int64;
    LastUpdated: TDateTime;
  end;

  {==========================================================================}
  {  连接状�?                                                               }
  {==========================================================================}
  TConnectionState = (
    csDisconnected,
    csConnecting,
    csConnected,
    csReconnecting,
    csClosing,
    csClosed,
    csError
  );

  {==========================================================================}
  {  连接事件                                                                }
  {==========================================================================}
  TConnectionStateEvent = reference to procedure(Sender: TObject;
    AState: TConnectionState; const AMessage: string);

  TMessageReceivedEvent = reference to procedure(Sender: TObject;
    const AMessage: TQueueMessage);

  TErrorEvent = reference to procedure(Sender: TObject;
    const AErrorCode: Integer; const AErrorMessage: string);

  {==========================================================================}
  {  工作流触发消�?                                                         }
  {==========================================================================}
  TWorkflowTriggerMessage = class(TQueueMessage)
  private
    FWorkflowId: string;
    FTriggerType: string;
    FPayload: TJSONObject;
    FScheduledTime: TDateTime;
    FContext: TDictionary<string, Variant>;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    procedure FromJSON(AJSON: TJSONObject);

    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property TriggerType: string read FTriggerType write FTriggerType;
    property Payload: TJSONObject read FPayload;
    property ScheduledTime: TDateTime read FScheduledTime write FScheduledTime;
    property Context: TDictionary<string, Variant> read FContext;
  end;

implementation

{==========================================================================}
{  TMessageHeaders                                                         }
{==========================================================================}

constructor TMessageHeaders.Create;
begin
  inherited Create;
  FItems := TDictionary<string, string>.Create;
end;

destructor TMessageHeaders.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TMessageHeaders.GetItem(const AKey: string): string;
begin
  if not FItems.TryGetValue(AKey, Result) then
    Result := '';
end;

procedure TMessageHeaders.SetItem(const AKey, AValue: string);
begin
  FItems.AddOrSetValue(AKey, AValue);
end;

function TMessageHeaders.GetCount: Integer;
begin
  Result := FItems.Count;
end;

procedure TMessageHeaders.Add(const AKey, AValue: string);
begin
  FItems.Add(AKey, AValue);
end;

procedure TMessageHeaders.Remove(const AKey: string);
begin
  FItems.Remove(AKey);
end;

function TMessageHeaders.Contains(const AKey: string): Boolean;
begin
  Result := FItems.ContainsKey(AKey);
end;

function TMessageHeaders.TryGetValue(const AKey: string; out AValue: string): Boolean;
begin
  Result := FItems.TryGetValue(AKey, AValue);
end;

procedure TMessageHeaders.Clear;
begin
  FItems.Clear;
end;

function TMessageHeaders.ToJSON: TJSONObject;
var
  LPair: TPair<string, string>;
begin
  Result := TJSONObject.Create;
  for LPair in FItems do
    Result.AddPair(LPair.Key, LPair.Value);
end;

procedure TMessageHeaders.FromJSON(AJSON: TJSONObject);
var
  LPair: TJSONPair;
begin
  FItems.Clear;
  if Assigned(AJSON) then
    for LPair in AJSON do
      FItems.AddOrSetValue(LPair.JsonString.Value, LPair.JsonValue.Value);
end;

{==========================================================================}
{  TQueueMessage                                                           }
{==========================================================================}

constructor TQueueMessage.Create;
begin
  inherited Create;
  FMessageId := TGUID.NewGuid.ToString;
  FHeaders := TMessageHeaders.Create;
  FPriority := mpNormal;
  FTimestamp := Now;
  FStatus := msPending;
  FContentType := 'application/json';
  FContentEncoding := 'utf-8';
end;

destructor TQueueMessage.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TQueueMessage.SetBodyAsString(const AValue: string; AEncoding: TEncoding);
begin
  if AEncoding = nil then
    AEncoding := TEncoding.UTF8;
  FBody := AEncoding.GetBytes(AValue);
end;

function TQueueMessage.GetBodyAsString(AEncoding: TEncoding): string;
begin
  if AEncoding = nil then
    AEncoding := TEncoding.UTF8;
  Result := AEncoding.GetString(FBody);
end;

procedure TQueueMessage.SetBodyAsJSON(AValue: TJSONValue);
begin
  if Assigned(AValue) then
    SetBodyAsString(AValue.ToJSON)
  else
    SetLength(FBody, 0);
end;

function TQueueMessage.GetBodyAsJSON: TJSONValue;
begin
  if Length(FBody) > 0 then
    Result := TJSONObject.ParseJSONValue(GetBodyAsString)
  else
    Result := nil;
end;

function TQueueMessage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('messageId', FMessageId);
  Result.AddPair('correlationId', FCorrelationId);
  Result.AddPair('replyTo', FReplyTo);
  Result.AddPair('contentType', FContentType);
  Result.AddPair('contentEncoding', FContentEncoding);
  Result.AddPair('body', TNetEncoding.Base64.EncodeBytesToString(FBody));
  Result.AddPair('headers', FHeaders.ToJSON);
  Result.AddPair('priority', TJSONNumber.Create(Ord(FPriority)));
  Result.AddPair('timestamp', DateToISO8601(FTimestamp));
  Result.AddPair('expiration', TJSONNumber.Create(FExpiration));
  Result.AddPair('exchange', FExchange);
  Result.AddPair('routingKey', FRoutingKey);
  Result.AddPair('retryCount', TJSONNumber.Create(FRetryCount));
  Result.AddPair('status', TJSONNumber.Create(Ord(FStatus)));
  Result.AddPair('errorMessage', FErrorMessage);
end;

procedure TQueueMessage.FromJSON(AJSON: TJSONObject);
var
  LHeaders: TJSONObject;
begin
  if not Assigned(AJSON) then Exit;

  FMessageId := AJSON.GetValue<string>('messageId', FMessageId);
  FCorrelationId := AJSON.GetValue<string>('correlationId', '');
  FReplyTo := AJSON.GetValue<string>('replyTo', '');
  FContentType := AJSON.GetValue<string>('contentType', 'application/json');
  FContentEncoding := AJSON.GetValue<string>('contentEncoding', 'utf-8');
  FBody := TNetEncoding.Base64.DecodeStringToBytes(AJSON.GetValue<string>('body', ''));
  
  if AJSON.TryGetValue<TJSONObject>('headers', LHeaders) then
    FHeaders.FromJSON(LHeaders);
    
  FPriority := TMessagePriority(AJSON.GetValue<Integer>('priority', Ord(mpNormal)));
  FTimestamp := ISO8601ToDate(AJSON.GetValue<string>('timestamp', DateToISO8601(Now)));
  FExpiration := AJSON.GetValue<Int64>('expiration', 0);
  FExchange := AJSON.GetValue<string>('exchange', '');
  FRoutingKey := AJSON.GetValue<string>('routingKey', '');
  FRetryCount := AJSON.GetValue<Integer>('retryCount', 0);
  FStatus := TMessageStatus(AJSON.GetValue<Integer>('status', Ord(msPending)));
  FErrorMessage := AJSON.GetValue<string>('errorMessage', '');
end;

function TQueueMessage.Clone: TQueueMessage;
begin
  Result := TQueueMessage.Create;
  Result.FromJSON(Self.ToJSON);
end;

{==========================================================================}
{  TQueueConfig                                                            }
{==========================================================================}

constructor TQueueConfig.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FDurable := True;
  FExclusive := False;
  FAutoDelete := False;
  FMaxLength := 0;
  FMaxLengthBytes := 0;
  FMessageTTL := 0;
  FArguments := TDictionary<string, Variant>.Create;
end;

destructor TQueueConfig.Destroy;
begin
  FArguments.Free;
  inherited;
end;

function TQueueConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('durable', TJSONBool.Create(FDurable));
  Result.AddPair('exclusive', TJSONBool.Create(FExclusive));
  Result.AddPair('autoDelete', TJSONBool.Create(FAutoDelete));
  Result.AddPair('maxLength', TJSONNumber.Create(FMaxLength));
  Result.AddPair('maxLengthBytes', TJSONNumber.Create(FMaxLengthBytes));
  Result.AddPair('messageTTL', TJSONNumber.Create(FMessageTTL));
  Result.AddPair('deadLetterExchange', FDeadLetterExchange);
  Result.AddPair('deadLetterRoutingKey', FDeadLetterRoutingKey);
end;

procedure TQueueConfig.FromJSON(AJSON: TJSONObject);
begin
  if not Assigned(AJSON) then Exit;

  FName := AJSON.GetValue<string>('name', FName);
  FDurable := AJSON.GetValue<Boolean>('durable', True);
  FExclusive := AJSON.GetValue<Boolean>('exclusive', False);
  FAutoDelete := AJSON.GetValue<Boolean>('autoDelete', False);
  FMaxLength := AJSON.GetValue<Integer>('maxLength', 0);
  FMaxLengthBytes := AJSON.GetValue<Int64>('maxLengthBytes', 0);
  FMessageTTL := AJSON.GetValue<Int64>('messageTTL', 0);
  FDeadLetterExchange := AJSON.GetValue<string>('deadLetterExchange', '');
  FDeadLetterRoutingKey := AJSON.GetValue<string>('deadLetterRoutingKey', '');
end;

{==========================================================================}
{  TExchangeConfig                                                         }
{==========================================================================}

constructor TExchangeConfig.Create(const AName: string; AType: TExchangeType);
begin
  inherited Create;
  FName := AName;
  FExchangeType := AType;
  FDurable := True;
  FAutoDelete := False;
  FInternal := False;
  FArguments := TDictionary<string, Variant>.Create;
end;

destructor TExchangeConfig.Destroy;
begin
  FArguments.Free;
  inherited;
end;

function TExchangeConfig.GetTypeString: string;
begin
  case FExchangeType of
    etDirect:  Result := 'direct';
    etFanout:  Result := 'fanout';
    etTopic:   Result := 'topic';
    etHeaders: Result := 'headers';
  else
    Result := 'direct';
  end;
end;

function TExchangeConfig.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('type', GetTypeString);
  Result.AddPair('durable', TJSONBool.Create(FDurable));
  Result.AddPair('autoDelete', TJSONBool.Create(FAutoDelete));
  Result.AddPair('internal', TJSONBool.Create(FInternal));
end;

procedure TExchangeConfig.FromJSON(AJSON: TJSONObject);
var
  LType: string;
begin
  if not Assigned(AJSON) then Exit;

  FName := AJSON.GetValue<string>('name', FName);
  LType := AJSON.GetValue<string>('type', 'direct');
  if LType = 'fanout' then
    FExchangeType := etFanout
  else if LType = 'topic' then
    FExchangeType := etTopic
  else if LType = 'headers' then
    FExchangeType := etHeaders
  else
    FExchangeType := etDirect;
  FDurable := AJSON.GetValue<Boolean>('durable', True);
  FAutoDelete := AJSON.GetValue<Boolean>('autoDelete', False);
  FInternal := AJSON.GetValue<Boolean>('internal', False);
end;

{==========================================================================}
{  TBindingConfig                                                          }
{==========================================================================}

constructor TBindingConfig.Create;
begin
  inherited Create;
  FArguments := TDictionary<string, Variant>.Create;
end;

destructor TBindingConfig.Destroy;
begin
  FArguments.Free;
  inherited;
end;

{==========================================================================}
{  TConsumerConfig                                                         }
{==========================================================================}

constructor TConsumerConfig.Create;
begin
  inherited Create;
  FConsumerTag := '';
  FAutoAck := False;
  FExclusive := False;
  FPrefetchCount := 10;
  FPrefetchSize := 0;
  FGlobalPrefetch := False;
end;

{==========================================================================}
{  TQueueConnectionConfig                                                  }
{==========================================================================}

constructor TQueueConnectionConfig.Create;
begin
  inherited Create;
  FHost := 'localhost';
  FPort := 5672;
  FVirtualHost := '/';
  FUsername := 'guest';
  FPassword := 'guest';
  FSSL := False;
  FConnectionTimeout := 30000;
  FHeartbeat := 60;
  FReconnectDelay := 5000;
  FMaxReconnectAttempts := 10;
end;

function TQueueConnectionConfig.GetConnectionString: string;
begin
  if FSSL then
    Result := Format('amqps://%s:%s@%s:%d%s',
      [FUsername, FPassword, FHost, FPort, FVirtualHost])
  else
    Result := Format('amqp://%s:%s@%s:%d%s',
      [FUsername, FPassword, FHost, FPort, FVirtualHost]);
end;

{==========================================================================}
{  TKafkaTopicConfig                                                       }
{==========================================================================}

constructor TKafkaTopicConfig.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FPartitions := 1;
  FReplicationFactor := 1;
  FRetentionMs := 604800000;       // 7 �?
  FRetentionBytes := -1;          // 无限�?
  FCleanupPolicy := 'delete';
  FCompressionType := 'producer';
end;

{==========================================================================}
{  TKafkaConsumerConfig                                                    }
{==========================================================================}

constructor TKafkaConsumerConfig.Create(const AGroupId: string);
begin
  inherited Create;
  FGroupId := AGroupId;
  FAutoCommit := True;
  FAutoCommitIntervalMs := 5000;
  FSessionTimeoutMs := 30000;
  FMaxPollRecords := 500;
  FOffsetReset := 'latest';
end;

{==========================================================================}
{  TKafkaRecord                                                            }
{==========================================================================}

constructor TKafkaRecord.Create;
begin
  inherited Create;
  FHeaders := TMessageHeaders.Create;
  FPartition := -1;
  FOffset := -1;
  FTimestamp := Now;
end;

destructor TKafkaRecord.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TKafkaRecord.SetKeyAsString(const AValue: string);
begin
  FKey := TEncoding.UTF8.GetBytes(AValue);
end;

function TKafkaRecord.GetKeyAsString: string;
begin
  Result := TEncoding.UTF8.GetString(FKey);
end;

procedure TKafkaRecord.SetValueAsString(const AValue: string);
begin
  FValue := TEncoding.UTF8.GetBytes(AValue);
end;

function TKafkaRecord.GetValueAsString: string;
begin
  Result := TEncoding.UTF8.GetString(FValue);
end;

procedure TKafkaRecord.SetValueAsJSON(AValue: TJSONValue);
begin
  if Assigned(AValue) then
    SetValueAsString(AValue.ToJSON)
  else
    SetLength(FValue, 0);
end;

function TKafkaRecord.GetValueAsJSON: TJSONValue;
begin
  if Length(FValue) > 0 then
    Result := TJSONObject.ParseJSONValue(GetValueAsString)
  else
    Result := nil;
end;

{==========================================================================}
{  TWorkflowTriggerMessage                                                 }
{==========================================================================}

constructor TWorkflowTriggerMessage.Create;
begin
  inherited Create;
  FPayload := TJSONObject.Create;
  FContext := TDictionary<string, Variant>.Create;
  FTriggerType := 'manual';
  ContentType := 'application/json';
  Headers['X-UniFlow-Type'] := 'WorkflowTrigger';
end;

destructor TWorkflowTriggerMessage.Destroy;
begin
  FPayload.Free;
  FContext.Free;
  inherited;
end;

function TWorkflowTriggerMessage.ToJSON: TJSONObject;
begin
  Result := inherited ToJSON;
  Result.AddPair('workflowId', FWorkflowId);
  Result.AddPair('triggerType', FTriggerType);
  Result.AddPair('payload', FPayload.Clone as TJSONObject);
  Result.AddPair('scheduledTime', DateToISO8601(FScheduledTime));
end;

procedure TWorkflowTriggerMessage.FromJSON(AJSON: TJSONObject);
var
  LPayload: TJSONObject;
begin
  inherited FromJSON(AJSON);
  
  if not Assigned(AJSON) then Exit;

  FWorkflowId := AJSON.GetValue<string>('workflowId', '');
  FTriggerType := AJSON.GetValue<string>('triggerType', 'manual');
  
  if AJSON.TryGetValue<TJSONObject>('payload', LPayload) then
  begin
    FPayload.Free;
    FPayload := LPayload.Clone as TJSONObject;
  end;
  
  FScheduledTime := ISO8601ToDate(AJSON.GetValue<string>('scheduledTime', DateToISO8601(Now)));
end;

end.
