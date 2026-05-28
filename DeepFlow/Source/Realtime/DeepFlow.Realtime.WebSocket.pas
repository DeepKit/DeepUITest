{******************************************************************************}
{                                                                              }
{  UniFlow WebSocket Real-time Push                                            }
{  Real-time workflow status notifications via WebSocket                       }
{                                                                              }
{  Features:                                                                   }
{  - WebSocket server for real-time push notifications                         }
{  - Topic-based subscription (workflow/session/user)                          }
{  - Automatic heartbeat and reconnection handling                             }
{  - Message queuing for offline clients                                       }
{  - Broadcast and targeted messaging                                          }
{  - JSON message protocol                                                     }
{                                                                              }
{  Architecture:                                                               }
{  - TWebSocketServer: Main server handling connections                        }
{  - TWebSocketClient: Client connection wrapper                               }
{  - TSubscriptionManager: Topic subscription management                       }
{  - TMessageBroker: Message routing and delivery                              }
{  - TWorkflowEventBridge: Bridge between workflow events and WebSocket        }
{                                                                              }
{  Message Protocol:                                                           }
{  - Client -> Server: subscribe, unsubscribe, ping                            }
{  - Server -> Client: event, subscribed, unsubscribed, pong, error            }
{                                                                              }
{  Usage:                                                                       }
{    var Server := TWebSocketServer.Create(8080);                              }
{    Server.Start;                                                             }
{    // Publish events                                                         }
{    Server.Broker.Publish('workflow:wf123', EventData);                       }
{                                                                              }
{******************************************************************************}

unit UniFlow.Realtime.WebSocket;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.SyncObjs,
  System.DateUtils,
  System.Hash,
  System.RegularExpressions,
  DeepBase.Exceptions;

type
  //----------------------------------------------------------------------------
  // Forward declarations
  //----------------------------------------------------------------------------
  
  TWebSocketServer = class;
  TWebSocketClient = class;
  TSubscriptionManager = class;
  TMessageBroker = class;
  
  //----------------------------------------------------------------------------
  // Enums and Types
  //----------------------------------------------------------------------------
  
  /// <summary>
  /// WebSocket connection state
  /// </summary>
  TConnectionState = (
    csConnecting,
    csOpen,
    csClosing,
    csClosed
  );
  
  /// <summary>
  /// Message type for protocol
  /// </summary>
  TWSMessageType = (
    // Client to Server
    mtSubscribe,
    mtUnsubscribe,
    mtPing,
    mtMessage,
    
    // Server to Client
    mtEvent,
    mtSubscribed,
    mtUnsubscribed,
    mtPong,
    mtError,
    mtWelcome
  );
  
  /// <summary>
  /// Event types for workflow notifications
  /// </summary>
  TWorkflowEventType = (
    wetWorkflowStarted,
    wetWorkflowCompleted,
    wetWorkflowFailed,
    wetWorkflowPaused,
    wetWorkflowResumed,
    wetWorkflowCancelled,
    wetStepStarted,
    wetStepCompleted,
    wetStepFailed,
    wetStepSkipped,
    wetVariableChanged,
    wetMessageAdded,
    wetProgressUpdate,
    wetCustom
  );
  
  /// <summary>
  /// Topic type for subscriptions
  /// </summary>
  TTopicType = (
    ttWorkflow,    // workflow:{workflowId}
    ttSession,     // session:{sessionId}
    ttUser,        // user:{userId}
    ttAll,         // all (admin only)
    ttCustom       // custom:{name}
  );
  
  //----------------------------------------------------------------------------
  // Helper records
  //----------------------------------------------------------------------------
  
  TWSMessageTypeHelper = record helper for TWSMessageType
    function ToString: string;
    class function FromString(const AValue: string): TWSMessageType; static;
  end;
  
  TWorkflowEventTypeHelper = record helper for TWorkflowEventType
    function ToString: string;
    class function FromString(const AValue: string): TWorkflowEventType; static;
  end;
  
  //----------------------------------------------------------------------------
  // TWSMessage - WebSocket message structure
  //----------------------------------------------------------------------------
  
  TWSMessage = class
  private
    FId: string;
    FType: TWSMessageType;
    FTopic: string;
    FPayload: TJSONObject;
    FTimestamp: TDateTime;
    FCorrelationId: string;
  public
    constructor Create(AType: TWSMessageType);
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TWSMessage; static;
    class function Parse(const AText: string): TWSMessage; static;
    
    function Clone: TWSMessage;
    
    property Id: string read FId write FId;
    property MessageType: TWSMessageType read FType write FType;
    property Topic: string read FTopic write FTopic;
    property Payload: TJSONObject read FPayload;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
  end;
  
  //----------------------------------------------------------------------------
  // TWorkflowEvent - Workflow event notification
  //----------------------------------------------------------------------------
  
  TWorkflowEvent = class
  private
    FEventType: TWorkflowEventType;
    FWorkflowId: string;
    FWorkflowName: string;
    FSessionId: string;
    FUserId: string;
    FStepId: string;
    FStepName: string;
    FMessage: string;
    FProgress: Integer;       // 0-100
    FData: TJSONObject;
    FTimestamp: TDateTime;
    FCorrelationId: string;
  public
    constructor Create(AEventType: TWorkflowEventType);
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    function ToWSMessage: TWSMessage;
    function GetTopics: TArray<string>;
    
    property EventType: TWorkflowEventType read FEventType write FEventType;
    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property WorkflowName: string read FWorkflowName write FWorkflowName;
    property SessionId: string read FSessionId write FSessionId;
    property UserId: string read FUserId write FUserId;
    property StepId: string read FStepId write FStepId;
    property StepName: string read FStepName write FStepName;
    property Message: string read FMessage write FMessage;
    property Progress: Integer read FProgress write FProgress;
    property Data: TJSONObject read FData;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property CorrelationId: string read FCorrelationId write FCorrelationId;
  end;
  
  //----------------------------------------------------------------------------
  // TSubscription - Single subscription record
  //----------------------------------------------------------------------------
  
  TSubscription = class
  private
    FId: string;
    FTopic: string;
    FTopicType: TTopicType;
    FClientId: string;
    FCreatedAt: TDateTime;
    FFilter: string;          // Optional JSON filter expression
  public
    constructor Create(const ATopic, AClientId: string);
    
    function Matches(const AEventTopic: string): Boolean;
    
    property Id: string read FId;
    property Topic: string read FTopic;
    property TopicType: TTopicType read FTopicType;
    property ClientId: string read FClientId;
    property CreatedAt: TDateTime read FCreatedAt;
    property Filter: string read FFilter write FFilter;
  end;
  
  //----------------------------------------------------------------------------
  // TWebSocketClient - Client connection wrapper
  //----------------------------------------------------------------------------
  
  TClientEventProc = reference to procedure(Client: TWebSocketClient; const AData: string);
  
  TWebSocketClient = class
  private
    FId: string;
    FState: TConnectionState;
    FConnectedAt: TDateTime;
    FLastActivityAt: TDateTime;
    FLastPingAt: TDateTime;
    FUserId: string;
    FSessionId: string;
    FMetadata: TDictionary<string, string>;
    FSubscriptions: TObjectList<TSubscription>;
    FMessageQueue: TObjectList<TWSMessage>;
    FMaxQueueSize: Integer;
    FLock: TCriticalSection;
    
    // Callback for sending data (injected by server)
    FOnSend: TClientEventProc;
    
    procedure TrimMessageQueue;
  public
    constructor Create(const AClientId: string);
    destructor Destroy; override;
    
    procedure Send(AMessage: TWSMessage);
    procedure SendText(const AText: string);
    procedure SendJSON(const AJSON: TJSONObject);
    procedure SendEvent(const ATopic: string; APayload: TJSONObject);
    procedure SendError(const ACode, AMessage: string);
    procedure SendPong;
    procedure SendWelcome;
    
    procedure AddSubscription(ASub: TSubscription);
    procedure RemoveSubscription(const ATopic: string);
    function HasSubscription(const ATopic: string): Boolean;
    function GetSubscriptions: TArray<TSubscription>;
    
    procedure QueueMessage(AMessage: TWSMessage);
    procedure FlushQueue;
    
    procedure Touch;
    function IsStale(ATimeoutSeconds: Integer): Boolean;
    
    property Id: string read FId;
    property State: TConnectionState read FState write FState;
    property ConnectedAt: TDateTime read FConnectedAt;
    property LastActivityAt: TDateTime read FLastActivityAt;
    property LastPingAt: TDateTime read FLastPingAt write FLastPingAt;
    property UserId: string read FUserId write FUserId;
    property SessionId: string read FSessionId write FSessionId;
    property Metadata: TDictionary<string, string> read FMetadata;
    property MaxQueueSize: Integer read FMaxQueueSize write FMaxQueueSize;
    property OnSend: TClientEventProc read FOnSend write FOnSend;
  end;
  
  //----------------------------------------------------------------------------
  // TSubscriptionManager - Manages topic subscriptions
  //----------------------------------------------------------------------------
  
  TSubscriptionManager = class
  private
    FSubscriptions: TObjectDictionary<string, TList<TSubscription>>;
    FClientSubscriptions: TDictionary<string, TList<string>>;
    FLock: TCriticalSection;
    
    function ParseTopicType(const ATopic: string): TTopicType;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Subscribe(const AClientId, ATopic: string; const AFilter: string = ''): TSubscription;
    procedure Unsubscribe(const AClientId, ATopic: string);
    procedure UnsubscribeAll(const AClientId: string);
    
    function GetSubscribers(const ATopic: string): TArray<string>;
    function GetMatchingSubscribers(const ATopics: TArray<string>): TArray<string>;
    function GetClientSubscriptions(const AClientId: string): TArray<string>;
    
    function IsSubscribed(const AClientId, ATopic: string): Boolean;
    function GetSubscriptionCount: Integer;
    function GetTopicCount: Integer;
    
    function GetStats: TJSONObject;
  end;
  
  //----------------------------------------------------------------------------
  // TMessageBroker - Routes messages to subscribers
  //----------------------------------------------------------------------------
  
  TMessageDeliveryProc = reference to procedure(const AClientId: string; AMessage: TWSMessage);
  
  TMessageBroker = class
  private
    FSubscriptionManager: TSubscriptionManager;
    FOnDeliver: TMessageDeliveryProc;
    FMessageHistory: TObjectList<TWSMessage>;
    FMaxHistorySize: Integer;
    FLock: TCriticalSection;
    
    // Statistics
    FTotalPublished: Int64;
    FTotalDelivered: Int64;
    FTotalFailed: Int64;
    
    procedure AddToHistory(AMessage: TWSMessage);
  public
    constructor Create(ASubscriptionManager: TSubscriptionManager);
    destructor Destroy; override;
    
    procedure Publish(const ATopic: string; APayload: TJSONObject; const ACorrelationId: string = '');
    procedure PublishEvent(AEvent: TWorkflowEvent);
    procedure Broadcast(AMessage: TWSMessage);
    procedure SendToClient(const AClientId: string; AMessage: TWSMessage);
    procedure SendToUser(const AUserId: string; AMessage: TWSMessage);
    
    function GetRecentMessages(ACount: Integer): TArray<TWSMessage>;
    function GetStats: TJSONObject;
    
    property SubscriptionManager: TSubscriptionManager read FSubscriptionManager;
    property OnDeliver: TMessageDeliveryProc read FOnDeliver write FOnDeliver;
    property MaxHistorySize: Integer read FMaxHistorySize write FMaxHistorySize;
  end;
  
  //----------------------------------------------------------------------------
  // TWebSocketServerConfig - Server configuration
  //----------------------------------------------------------------------------
  
  TWebSocketServerConfig = class
  private
    FPort: Integer;
    FHost: string;
    FMaxClients: Integer;
    FPingIntervalMs: Integer;
    FPongTimeoutMs: Integer;
    FMaxMessageSize: Integer;
    FMaxQueuePerClient: Integer;
    FEnableCompression: Boolean;
    FAllowAnonymous: Boolean;
    FRequireAuth: Boolean;
    FAuthToken: string;
  public
    constructor Create;
    
    property Port: Integer read FPort write FPort;
    property Host: string read FHost write FHost;
    property MaxClients: Integer read FMaxClients write FMaxClients;
    property PingIntervalMs: Integer read FPingIntervalMs write FPingIntervalMs;
    property PongTimeoutMs: Integer read FPongTimeoutMs write FPongTimeoutMs;
    property MaxMessageSize: Integer read FMaxMessageSize write FMaxMessageSize;
    property MaxQueuePerClient: Integer read FMaxQueuePerClient write FMaxQueuePerClient;
    property EnableCompression: Boolean read FEnableCompression write FEnableCompression;
    property AllowAnonymous: Boolean read FAllowAnonymous write FAllowAnonymous;
    property RequireAuth: Boolean read FRequireAuth write FRequireAuth;
    property AuthToken: string read FAuthToken write FAuthToken;
  end;
  
  //----------------------------------------------------------------------------
  // TWebSocketServer - Main WebSocket server
  //----------------------------------------------------------------------------
  
  TServerEventProc = reference to procedure(Server: TWebSocketServer);
  TClientConnectProc = reference to procedure(Client: TWebSocketClient);
  TClientMessageProc = reference to procedure(Client: TWebSocketClient; AMessage: TWSMessage);
  
  TWebSocketServer = class
  private
    FConfig: TWebSocketServerConfig;
    FOwnsConfig: Boolean;
    FClients: TObjectDictionary<string, TWebSocketClient>;
    FUserClients: TDictionary<string, TList<string>>;
    FSubscriptionManager: TSubscriptionManager;
    FBroker: TMessageBroker;
    FLock: TCriticalSection;
    FRunning: Boolean;
    FStartedAt: TDateTime;
    
    // Background threads
    FPingThread: TThread;
    FCleanupThread: TThread;
    
    // Event handlers
    FOnClientConnect: TClientConnectProc;
    FOnClientDisconnect: TClientConnectProc;
    FOnClientMessage: TClientMessageProc;
    FOnError: TClientMessageProc;
    FOnStart: TServerEventProc;
    FOnStop: TServerEventProc;
    
    // Statistics
    FTotalConnections: Int64;
    FTotalMessages: Int64;
    
    procedure StartPingThread;
    procedure StopPingThread;
    procedure StartCleanupThread;
    procedure StopCleanupThread;
    procedure DoPingClients;
    procedure DoCleanupStaleClients;
    
    procedure HandleClientMessage(AClient: TWebSocketClient; const AText: string);
    procedure HandleSubscribe(AClient: TWebSocketClient; AMessage: TWSMessage);
    procedure HandleUnsubscribe(AClient: TWebSocketClient; AMessage: TWSMessage);
    procedure HandlePing(AClient: TWebSocketClient; AMessage: TWSMessage);
    
    procedure DeliverMessage(const AClientId: string; AMessage: TWSMessage);
    
    function GenerateClientId: string;
  public
    constructor Create(APort: Integer); overload;
    constructor Create(AConfig: TWebSocketServerConfig; AOwnsConfig: Boolean = True); overload;
    destructor Destroy; override;
    
    procedure Start;
    procedure Stop;
    
    // Client management
    function AddClient(const AUserId: string = ''; const ASessionId: string = ''): TWebSocketClient;
    procedure ReDeepMoveClient(const AClientId: string);
    function GetClient(const AClientId: string): TWebSocketClient;
    function GetClientsByUser(const AUserId: string): TArray<TWebSocketClient>;
    function GetAllClients: TArray<TWebSocketClient>;
    function GetClientCount: Integer;
    
    // Authentication
    function AuthenticateClient(AClient: TWebSocketClient; const AToken: string): Boolean;
    
    // Messaging
    procedure SendToClient(const AClientId: string; AMessage: TWSMessage);
    procedure SendToUser(const AUserId: string; AMessage: TWSMessage);
    procedure SendToAll(AMessage: TWSMessage);
    procedure PublishEvent(AEvent: TWorkflowEvent);
    
    // Simulate receiving a message (for testing without real WebSocket)
    procedure SimulateReceive(const AClientId: string; const AText: string);
    
    // Statistics
    function GetStats: TJSONObject;
    function IsRunning: Boolean;
    
    property Config: TWebSocketServerConfig read FConfig;
    property Broker: TMessageBroker read FBroker;
    property SubscriptionManager: TSubscriptionManager read FSubscriptionManager;
    
    // Events
    property OnClientConnect: TClientConnectProc read FOnClientConnect write FOnClientConnect;
    property OnClientDisconnect: TClientConnectProc read FOnClientDisconnect write FOnClientDisconnect;
    property OnClientMessage: TClientMessageProc read FOnClientMessage write FOnClientMessage;
    property OnError: TClientMessageProc read FOnError write FOnError;
    property OnStart: TServerEventProc read FOnStart write FOnStart;
    property OnStop: TServerEventProc read FOnStop write FOnStop;
  end;
  
  //----------------------------------------------------------------------------
  // TWorkflowEventBridge - Bridges workflow events to WebSocket
  //----------------------------------------------------------------------------
  
  TWorkflowEventBridge = class
  private
    FServer: TWebSocketServer;
    FEnabled: Boolean;
    FIncludeStepEvents: Boolean;
    FIncludeVariableEvents: Boolean;
    FLock: TCriticalSection;
  public
    constructor Create(AServer: TWebSocketServer);
    destructor Destroy; override;
    
    // Call these from workflow executor hooks
    procedure OnWorkflowStarted(const AWorkflowId, AWorkflowName, ASessionId, AUserId: string);
    procedure OnWorkflowCompleted(const AWorkflowId, AWorkflowName, ASessionId, AUserId: string; ADurationMs: Integer);
    procedure OnWorkflowFailed(const AWorkflowId, AWorkflowName, ASessionId, AUserId, AError: string);
    procedure OnWorkflowPaused(const AWorkflowId, AWorkflowName, ASessionId, AUserId: string);
    procedure OnWorkflowResumed(const AWorkflowId, AWorkflowName, ASessionId, AUserId: string);
    procedure OnWorkflowCancelled(const AWorkflowId, AWorkflowName, ASessionId, AUserId: string);
    
    procedure OnStepStarted(const AWorkflowId, AStepId, AStepName: string; AStepIndex, ATotalSteps: Integer);
    procedure OnStepCompleted(const AWorkflowId, AStepId, AStepName: string; ADurationMs: Integer);
    procedure OnStepFailed(const AWorkflowId, AStepId, AStepName, AError: string);
    
    procedure OnProgressUpdate(const AWorkflowId: string; AProgress: Integer; const AMessage: string);
    procedure OnCustomEvent(const AWorkflowId, AEventName: string; AData: TJSONObject);
    
    property Enabled: Boolean read FEnabled write FEnabled;
    property IncludeStepEvents: Boolean read FIncludeStepEvents write FIncludeStepEvents;
    property IncludeVariableEvents: Boolean read FIncludeVariableEvents write FIncludeVariableEvents;
  end;
  
  //----------------------------------------------------------------------------
  // Factory functions
  //----------------------------------------------------------------------------
  
  function CreateWorkflowEvent(AEventType: TWorkflowEventType; const AWorkflowId: string): TWorkflowEvent;
  function CreateWSMessage(AType: TWSMessageType; const ATopic: string = ''): TWSMessage;

implementation

uses
  System.StrUtils;

//------------------------------------------------------------------------------
// TWSMessageTypeHelper
//------------------------------------------------------------------------------

function TWSMessageTypeHelper.ToString: string;
begin
  case Self of
    mtSubscribe:    Result := 'subscribe';
    mtUnsubscribe:  Result := 'unsubscribe';
    mtPing:         Result := 'ping';
    mtMessage:      Result := 'message';
    mtEvent:        Result := 'event';
    mtSubscribed:   Result := 'subscribed';
    mtUnsubscribed: Result := 'unsubscribed';
    mtPong:         Result := 'pong';
    mtError:        Result := 'error';
    mtWelcome:      Result := 'welcome';
  else
    Result := 'unknown';
  end;
end;

class function TWSMessageTypeHelper.FromString(const AValue: string): TWSMessageType;
var
  Lower: string;
begin
  Lower := AValue.ToLower;
  if Lower = 'subscribe' then Result := mtSubscribe
  else if Lower = 'unsubscribe' then Result := mtUnsubscribe
  else if Lower = 'ping' then Result := mtPing
  else if Lower = 'message' then Result := mtMessage
  else if Lower = 'event' then Result := mtEvent
  else if Lower = 'subscribed' then Result := mtSubscribed
  else if Lower = 'unsubscribed' then Result := mtUnsubscribed
  else if Lower = 'pong' then Result := mtPong
  else if Lower = 'error' then Result := mtError
  else if Lower = 'welcome' then Result := mtWelcome
  else Result := mtMessage;
end;

//------------------------------------------------------------------------------
// TWorkflowEventTypeHelper
//------------------------------------------------------------------------------

function TWorkflowEventTypeHelper.ToString: string;
begin
  case Self of
    wetWorkflowStarted:   Result := 'workflow.started';
    wetWorkflowCompleted: Result := 'workflow.completed';
    wetWorkflowFailed:    Result := 'workflow.failed';
    wetWorkflowPaused:    Result := 'workflow.paused';
    wetWorkflowResumed:   Result := 'workflow.resumed';
    wetWorkflowCancelled: Result := 'workflow.cancelled';
    wetStepStarted:       Result := 'step.started';
    wetStepCompleted:     Result := 'step.completed';
    wetStepFailed:        Result := 'step.failed';
    wetStepSkipped:       Result := 'step.skipped';
    wetVariableChanged:   Result := 'variable.changed';
    wetMessageAdded:      Result := 'message.added';
    wetProgressUpdate:    Result := 'progress.update';
    wetCustom:            Result := 'custom';
  else
    Result := 'unknown';
  end;
end;

class function TWorkflowEventTypeHelper.FromString(const AValue: string): TWorkflowEventType;
var
  Lower: string;
begin
  Lower := AValue.ToLower;
  if Lower = 'workflow.started' then Result := wetWorkflowStarted
  else if Lower = 'workflow.completed' then Result := wetWorkflowCompleted
  else if Lower = 'workflow.failed' then Result := wetWorkflowFailed
  else if Lower = 'workflow.paused' then Result := wetWorkflowPaused
  else if Lower = 'workflow.resumed' then Result := wetWorkflowResumed
  else if Lower = 'workflow.cancelled' then Result := wetWorkflowCancelled
  else if Lower = 'step.started' then Result := wetStepStarted
  else if Lower = 'step.completed' then Result := wetStepCompleted
  else if Lower = 'step.failed' then Result := wetStepFailed
  else if Lower = 'step.skipped' then Result := wetStepSkipped
  else if Lower = 'variable.changed' then Result := wetVariableChanged
  else if Lower = 'message.added' then Result := wetMessageAdded
  else if Lower = 'progress.update' then Result := wetProgressUpdate
  else Result := wetCustom;
end;

//------------------------------------------------------------------------------
// TWSMessage
//------------------------------------------------------------------------------

constructor TWSMessage.Create(AType: TWSMessageType);
var
  GUID: TGUID;
begin
  inherited Create;
  CreateGUID(GUID);
  FId := Copy(GUIDToString(GUID), 2, 36).Replace('-', '', [rfReplaceAll]).ToLower;
  FType := AType;
  FPayload := TJSONObject.Create;
  FTimestamp := Now;
end;

destructor TWSMessage.Destroy;
begin
  FPayload.Free;
  inherited Destroy;
end;

function TWSMessage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('type', FType.ToString);
  if FTopic <> '' then
    Result.AddPair('topic', FTopic);
  if FCorrelationId <> '' then
    Result.AddPair('correlationId', FCorrelationId);
  Result.AddPair('timestamp', DateToISO8601(FTimestamp, False));
  if FPayload.Count > 0 then
    Result.AddPair('payload', FPayload.Clone as TJSONObject);
end;

class function TWSMessage.FromJSON(const AJSON: TJSONObject): TWSMessage;
var
  TypeStr: string;
  PayloadObj: TJSONObject;
begin
  TypeStr := AJSON.GetValue<string>('type', 'message');
  Result := TWSMessage.Create(TWSMessageType.FromString(TypeStr));
  Result.FId := AJSON.GetValue<string>('id', Result.FId);
  Result.FTopic := AJSON.GetValue<string>('topic', '');
  Result.FCorrelationId := AJSON.GetValue<string>('correlationId', '');
  
  if AJSON.TryGetValue<TJSONObject>('payload', PayloadObj) then
  begin
    Result.FPayload.Free;
    Result.FPayload := PayloadObj.Clone as TJSONObject;
  end;
end;

class function TWSMessage.Parse(const AText: string): TWSMessage;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.ParseJSONValue(AText) as TJSONObject;
  if not Assigned(JSON) then
    raise EOperationException.Create('Invalid JSON message');
  try
    Result := FromJSON(JSON);
  finally
    JSON.Free;
  end;
end;

function TWSMessage.Clone: TWSMessage;
begin
  Result := TWSMessage.Create(FType);
  Result.FId := FId;
  Result.FTopic := FTopic;
  Result.FCorrelationId := FCorrelationId;
  Result.FTimestamp := FTimestamp;
  Result.FPayload.Free;
  Result.FPayload := FPayload.Clone as TJSONObject;
end;

//------------------------------------------------------------------------------
// TWorkflowEvent
//------------------------------------------------------------------------------

constructor TWorkflowEvent.Create(AEventType: TWorkflowEventType);
begin
  inherited Create;
  FEventType := AEventType;
  FData := TJSONObject.Create;
  FTimestamp := Now;
  FProgress := -1;
end;

destructor TWorkflowEvent.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

function TWorkflowEvent.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('eventType', FEventType.ToString);
  Result.AddPair('timestamp', DateToISO8601(FTimestamp, False));
  
  if FWorkflowId <> '' then
    Result.AddPair('workflowId', FWorkflowId);
  if FWorkflowName <> '' then
    Result.AddPair('workflowName', FWorkflowName);
  if FSessionId <> '' then
    Result.AddPair('sessionId', FSessionId);
  if FUserId <> '' then
    Result.AddPair('userId', FUserId);
  if FStepId <> '' then
    Result.AddPair('stepId', FStepId);
  if FStepName <> '' then
    Result.AddPair('stepName', FStepName);
  if FMessage <> '' then
    Result.AddPair('message', FMessage);
  if FProgress >= 0 then
    Result.AddPair('progress', TJSONNumber.Create(FProgress));
  if FCorrelationId <> '' then
    Result.AddPair('correlationId', FCorrelationId);
  if FData.Count > 0 then
    Result.AddPair('data', FData.Clone as TJSONObject);
end;

function TWorkflowEvent.ToWSMessage: TWSMessage;
begin
  Result := TWSMessage.Create(mtEvent);
  Result.Topic := 'workflow:' + FWorkflowId;
  Result.CorrelationId := FCorrelationId;
  Result.FPayload.Free;
  Result.FPayload := ToJSON;
end;

function TWorkflowEvent.GetTopics: TArray<string>;
var
  Topics: TList<string>;
begin
  Topics := TList<string>.Create;
  try
    // Always include workflow topic
    if FWorkflowId <> '' then
      Topics.Add('workflow:' + FWorkflowId);
    
    // Include session topic
    if FSessionId <> '' then
      Topics.Add('session:' + FSessionId);
    
    // Include user topic
    if FUserId <> '' then
      Topics.Add('user:' + FUserId);
    
    // Include all topic for admin/monitors
    Topics.Add('all');
    
    Result := Topics.ToArray;
  finally
    Topics.Free;
  end;
end;

//------------------------------------------------------------------------------
// TSubscription
//------------------------------------------------------------------------------

constructor TSubscription.Create(const ATopic, AClientId: string);
var
  GUID: TGUID;
  Parts: TArray<string>;
begin
  inherited Create;
  CreateGUID(GUID);
  FId := Copy(GUIDToString(GUID), 2, 8);
  FTopic := ATopic;
  FClientId := AClientId;
  FCreatedAt := Now;
  
  // Parse topic type
  Parts := ATopic.Split([':']);
  if Length(Parts) > 0 then
  begin
    if Parts[0] = 'workflow' then FTopicType := ttWorkflow
    else if Parts[0] = 'session' then FTopicType := ttSession
    else if Parts[0] = 'user' then FTopicType := ttUser
    else if Parts[0] = 'all' then FTopicType := ttAll
    else FTopicType := ttCustom;
  end
  else
    FTopicType := ttCustom;
end;

function TSubscription.Matches(const AEventTopic: string): Boolean;
begin
  // Exact match
  if FTopic = AEventTopic then
    Exit(True);
  
  // Wildcard match (e.g., "workflow:*" matches "workflow:123")
  if FTopic.EndsWith('*') then
  begin
    Result := AEventTopic.StartsWith(FTopic.Substring(0, FTopic.Length - 1));
    Exit;
  end;
  
  // "all" matches everything
  if FTopic = 'all' then
    Exit(True);
  
  Result := False;
end;

//------------------------------------------------------------------------------
// TWebSocketClient
//------------------------------------------------------------------------------

constructor TWebSocketClient.Create(const AClientId: string);
begin
  inherited Create;
  FId := AClientId;
  FState := csConnecting;
  FConnectedAt := Now;
  FLastActivityAt := Now;
  FMetadata := TDictionary<string, string>.Create;
  FSubscriptions := TObjectList<TSubscription>.Create(True);
  FMessageQueue := TObjectList<TWSMessage>.Create(True);
  FMaxQueueSize := 100;
  FLock := TCriticalSection.Create;
end;

destructor TWebSocketClient.Destroy;
begin
  FLock.Free;
  FMessageQueue.Free;
  FSubscriptions.Free;
  FMetadata.Free;
  inherited Destroy;
end;

procedure TWebSocketClient.TrimMessageQueue;
begin
  while FMessageQueue.Count > FMaxQueueSize do
    FMessageQueue.Delete(0);
end;

procedure TWebSocketClient.Send(AMessage: TWSMessage);
var
  JSON: TJSONObject;
begin
  if FState <> csOpen then
  begin
    QueueMessage(AMessage.Clone);
    Exit;
  end;
  
  FLock.Enter;
  try
    JSON := AMessage.ToJSON;
    try
      if Assigned(FOnSend) then
        FOnSend(Self, JSON.ToString);
    finally
      JSON.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketClient.SendText(const AText: string);
begin
  if Assigned(FOnSend) and (FState = csOpen) then
    FOnSend(Self, AText);
end;

procedure TWebSocketClient.SendJSON(const AJSON: TJSONObject);
begin
  SendText(AJSON.ToString);
end;

procedure TWebSocketClient.SendEvent(const ATopic: string; APayload: TJSONObject);
var
  Msg: TWSMessage;
begin
  Msg := TWSMessage.Create(mtEvent);
  try
    Msg.Topic := ATopic;
    if Assigned(APayload) then
    begin
      Msg.FPayload.Free;
      Msg.FPayload := APayload.Clone as TJSONObject;
    end;
    Send(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TWebSocketClient.SendError(const ACode, AMessage: string);
var
  Msg: TWSMessage;
begin
  Msg := TWSMessage.Create(mtError);
  try
    Msg.Payload.AddPair('code', ACode);
    Msg.Payload.AddPair('message', AMessage);
    Send(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TWebSocketClient.SendPong;
var
  Msg: TWSMessage;
begin
  Msg := TWSMessage.Create(mtPong);
  try
    Send(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TWebSocketClient.SendWelcome;
var
  Msg: TWSMessage;
begin
  Msg := TWSMessage.Create(mtWelcome);
  try
    Msg.Payload.AddPair('clientId', FId);
    Msg.Payload.AddPair('serverTime', DateToISO8601(Now, False));
    Send(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TWebSocketClient.AddSubscription(ASub: TSubscription);
begin
  FLock.Enter;
  try
    if not HasSubscription(ASub.Topic) then
      FSubscriptions.Add(ASub);
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketClient.RemoveSubscription(const ATopic: string);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FSubscriptions.Count - 1 downto 0 do
      if FSubscriptions[I].Topic = ATopic then
      begin
        FSubscriptions.Delete(I);
        Break;
      end;
  finally
    FLock.Leave;
  end;
end;

function TWebSocketClient.HasSubscription(const ATopic: string): Boolean;
var
  Sub: TSubscription;
begin
  Result := False;
  FLock.Enter;
  try
    for Sub in FSubscriptions do
      if Sub.Topic = ATopic then
        Exit(True);
  finally
    FLock.Leave;
  end;
end;

function TWebSocketClient.GetSubscriptions: TArray<TSubscription>;
begin
  FLock.Enter;
  try
    Result := FSubscriptions.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketClient.QueueMessage(AMessage: TWSMessage);
begin
  FLock.Enter;
  try
    FMessageQueue.Add(AMessage);
    TrimMessageQueue;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketClient.FlushQueue;
var
  Msg: TWSMessage;
begin
  if FState <> csOpen then Exit;
  
  FLock.Enter;
  try
    while FMessageQueue.Count > 0 do
    begin
      Msg := FMessageQueue.Extract(FMessageQueue[0]);
      try
        Send(Msg);
      finally
        Msg.Free;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TWebSocketClient.Touch;
begin
  FLastActivityAt := Now;
end;

function TWebSocketClient.IsStale(ATimeoutSeconds: Integer): Boolean;
begin
  Result := SecondsBetween(Now, FLastActivityAt) > ATimeoutSeconds;
end;

//------------------------------------------------------------------------------
// TSubscriptionManager
//------------------------------------------------------------------------------

constructor TSubscriptionManager.Create;
begin
  inherited Create;
  FSubscriptions := TObjectDictionary<string, TList<TSubscription>>.Create([doOwnsValues]);
  FClientSubscriptions := TDictionary<string, TList<string>>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TSubscriptionManager.Destroy;
var
  ClientList: TList<string>;
begin
  for ClientList in FClientSubscriptions.Values do
    ClientList.Free;
  FClientSubscriptions.Free;
  FSubscriptions.Free;
  FLock.Free;
  inherited Destroy;
end;

function TSubscriptionManager.ParseTopicType(const ATopic: string): TTopicType;
var
  Parts: TArray<string>;
begin
  Parts := ATopic.Split([':']);
  if Length(Parts) > 0 then
  begin
    if Parts[0] = 'workflow' then Result := ttWorkflow
    else if Parts[0] = 'session' then Result := ttSession
    else if Parts[0] = 'user' then Result := ttUser
    else if Parts[0] = 'all' then Result := ttAll
    else Result := ttCustom;
  end
  else
    Result := ttCustom;
end;

function TSubscriptionManager.Subscribe(const AClientId, ATopic: string; 
  const AFilter: string): TSubscription;
var
  SubList: TList<TSubscription>;
  ClientTopics: TList<string>;
begin
  Result := TSubscription.Create(ATopic, AClientId);
  Result.Filter := AFilter;
  
  FLock.Enter;
  try
    // Add to topic subscriptions
    if not FSubscriptions.TryGetValue(ATopic, SubList) then
    begin
      SubList := TList<TSubscription>.Create;
      FSubscriptions.Add(ATopic, SubList);
    end;
    SubList.Add(Result);
    
    // Add to client subscriptions
    if not FClientSubscriptions.TryGetValue(AClientId, ClientTopics) then
    begin
      ClientTopics := TList<string>.Create;
      FClientSubscriptions.Add(AClientId, ClientTopics);
    end;
    if not ClientTopics.Contains(ATopic) then
      ClientTopics.Add(ATopic);
  finally
    FLock.Leave;
  end;
end;

procedure TSubscriptionManager.Unsubscribe(const AClientId, ATopic: string);
var
  SubList: TList<TSubscription>;
  ClientTopics: TList<string>;
  I: Integer;
begin
  FLock.Enter;
  try
    // Remove from topic subscriptions
    if FSubscriptions.TryGetValue(ATopic, SubList) then
    begin
      for I := SubList.Count - 1 downto 0 do
        if SubList[I].ClientId = AClientId then
        begin
          SubList[I].Free;
          SubList.Delete(I);
        end;
    end;
    
    // Remove from client subscriptions
    if FClientSubscriptions.TryGetValue(AClientId, ClientTopics) then
      ClientTopics.Remove(ATopic);
  finally
    FLock.Leave;
  end;
end;

procedure TSubscriptionManager.UnsubscribeAll(const AClientId: string);
var
  ClientTopics: TList<string>;
  Topic: string;
  SubList: TList<TSubscription>;
  I: Integer;
begin
  FLock.Enter;
  try
    if FClientSubscriptions.TryGetValue(AClientId, ClientTopics) then
    begin
      for Topic in ClientTopics do
      begin
        if FSubscriptions.TryGetValue(Topic, SubList) then
        begin
          for I := SubList.Count - 1 downto 0 do
            if SubList[I].ClientId = AClientId then
            begin
              SubList[I].Free;
              SubList.Delete(I);
            end;
        end;
      end;
      ClientTopics.Clear;
    end;
  finally
    FLock.Leave;
  end;
end;

function TSubscriptionManager.GetSubscribers(const ATopic: string): TArray<string>;
var
  SubList: TList<TSubscription>;
  Sub: TSubscription;
  Clients: TList<string>;
begin
  Clients := TList<string>.Create;
  try
    FLock.Enter;
    try
      if FSubscriptions.TryGetValue(ATopic, SubList) then
        for Sub in SubList do
          if not Clients.Contains(Sub.ClientId) then
            Clients.Add(Sub.ClientId);
    finally
      FLock.Leave;
    end;
    Result := Clients.ToArray;
  finally
    Clients.Free;
  end;
end;

function TSubscriptionManager.GetMatchingSubscribers(const ATopics: TArray<string>): TArray<string>;
var
  Topic, SubTopic: string;
  SubList: TList<TSubscription>;
  Sub: TSubscription;
  Clients: TList<string>;
begin
  Clients := TList<string>.Create;
  try
    FLock.Enter;
    try
      for Topic in ATopics do
      begin
        // Exact match
        if FSubscriptions.TryGetValue(Topic, SubList) then
          for Sub in SubList do
            if not Clients.Contains(Sub.ClientId) then
              Clients.Add(Sub.ClientId);
        
        // Check wildcard subscriptions
        for SubTopic in FSubscriptions.Keys do
        begin
          if SubTopic.EndsWith('*') then
          begin
            if Topic.StartsWith(SubTopic.Substring(0, SubTopic.Length - 1)) then
            begin
              if FSubscriptions.TryGetValue(SubTopic, SubList) then
                for Sub in SubList do
                  if not Clients.Contains(Sub.ClientId) then
                    Clients.Add(Sub.ClientId);
            end;
          end;
        end;
      end;
    finally
      FLock.Leave;
    end;
    Result := Clients.ToArray;
  finally
    Clients.Free;
  end;
end;

function TSubscriptionManager.GetClientSubscriptions(const AClientId: string): TArray<string>;
var
  ClientTopics: TList<string>;
begin
  FLock.Enter;
  try
    if FClientSubscriptions.TryGetValue(AClientId, ClientTopics) then
      Result := ClientTopics.ToArray
    else
      SetLength(Result, 0);
  finally
    FLock.Leave;
  end;
end;

function TSubscriptionManager.IsSubscribed(const AClientId, ATopic: string): Boolean;
var
  ClientTopics: TList<string>;
begin
  FLock.Enter;
  try
    if FClientSubscriptions.TryGetValue(AClientId, ClientTopics) then
      Result := ClientTopics.Contains(ATopic)
    else
      Result := False;
  finally
    FLock.Leave;
  end;
end;

function TSubscriptionManager.GetSubscriptionCount: Integer;
var
  SubList: TList<TSubscription>;
begin
  Result := 0;
  FLock.Enter;
  try
    for SubList in FSubscriptions.Values do
      Inc(Result, SubList.Count);
  finally
    FLock.Leave;
  end;
end;

function TSubscriptionManager.GetTopicCount: Integer;
begin
  FLock.Enter;
  try
    Result := FSubscriptions.Count;
  finally
    FLock.Leave;
  end;
end;

function TSubscriptionManager.GetStats: TJSONObject;
var
  TopicStats: TJSONObject;
  Topic: string;
  SubList: TList<TSubscription>;
begin
  Result := TJSONObject.Create;
  TopicStats := TJSONObject.Create;
  
  FLock.Enter;
  try
    Result.AddPair('totalSubscriptions', TJSONNumber.Create(GetSubscriptionCount));
    Result.AddPair('totalTopics', TJSONNumber.Create(FSubscriptions.Count));
    Result.AddPair('totalClients', TJSONNumber.Create(FClientSubscriptions.Count));
    
    for Topic in FSubscriptions.Keys do
    begin
      if FSubscriptions.TryGetValue(Topic, SubList) then
        TopicStats.AddPair(Topic, TJSONNumber.Create(SubList.Count));
    end;
    Result.AddPair('topicSubscribers', TopicStats);
  finally
    FLock.Leave;
  end;
end;

//------------------------------------------------------------------------------
// TMessageBroker
//------------------------------------------------------------------------------

constructor TMessageBroker.Create(ASubscriptionManager: TSubscriptionManager);
begin
  inherited Create;
  FSubscriptionManager := ASubscriptionManager;
  FMessageHistory := TObjectList<TWSMessage>.Create(True);
  FMaxHistorySize := 1000;
  FLock := TCriticalSection.Create;
  FTotalPublished := 0;
  FTotalDelivered := 0;
  FTotalFailed := 0;
end;

destructor TMessageBroker.Destroy;
begin
  FMessageHistory.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TMessageBroker.AddToHistory(AMessage: TWSMessage);
begin
  FLock.Enter;
  try
    FMessageHistory.Add(AMessage.Clone);
    while FMessageHistory.Count > FMaxHistorySize do
      FMessageHistory.Delete(0);
  finally
    FLock.Leave;
  end;
end;

procedure TMessageBroker.Publish(const ATopic: string; APayload: TJSONObject; 
  const ACorrelationId: string);
var
  Msg: TWSMessage;
  Subscribers: TArray<string>;
  ClientId: string;
begin
  Msg := TWSMessage.Create(mtEvent);
  try
    Msg.Topic := ATopic;
    Msg.CorrelationId := ACorrelationId;
    if Assigned(APayload) then
    begin
      Msg.FPayload.Free;
      Msg.FPayload := APayload.Clone as TJSONObject;
    end;
    
    AddToHistory(Msg);
    Inc(FTotalPublished);
    
    // Find subscribers
    Subscribers := FSubscriptionManager.GetMatchingSubscribers([ATopic]);
    
    // Deliver to each subscriber
    for ClientId in Subscribers do
    begin
      if Assigned(FOnDeliver) then
      begin
        try
          FOnDeliver(ClientId, Msg);
          Inc(FTotalDelivered);
        except
          Inc(FTotalFailed);
        end;
      end;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TMessageBroker.PublishEvent(AEvent: TWorkflowEvent);
var
  Msg: TWSMessage;
  Topics: TArray<string>;
  Subscribers: TArray<string>;
  ClientId: string;
begin
  Msg := AEvent.ToWSMessage;
  try
    AddToHistory(Msg);
    Inc(FTotalPublished);
    
    // Get all relevant topics
    Topics := AEvent.GetTopics;
    
    // Find all subscribers
    Subscribers := FSubscriptionManager.GetMatchingSubscribers(Topics);
    
    // Deliver to each subscriber
    for ClientId in Subscribers do
    begin
      if Assigned(FOnDeliver) then
      begin
        try
          FOnDeliver(ClientId, Msg);
          Inc(FTotalDelivered);
        except
          Inc(FTotalFailed);
        end;
      end;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TMessageBroker.Broadcast(AMessage: TWSMessage);
var
  Subscribers: TArray<string>;
  ClientId: string;
begin
  AddToHistory(AMessage);
  Inc(FTotalPublished);
  
  Subscribers := FSubscriptionManager.GetSubscribers('all');
  
  for ClientId in Subscribers do
  begin
    if Assigned(FOnDeliver) then
    begin
      try
        FOnDeliver(ClientId, AMessage);
        Inc(FTotalDelivered);
      except
        Inc(FTotalFailed);
      end;
    end;
  end;
end;

procedure TMessageBroker.SendToClient(const AClientId: string; AMessage: TWSMessage);
begin
  Inc(FTotalPublished);
  if Assigned(FOnDeliver) then
  begin
    try
      FOnDeliver(AClientId, AMessage);
      Inc(FTotalDelivered);
    except
      Inc(FTotalFailed);
    end;
  end;
end;

procedure TMessageBroker.SendToUser(const AUserId: string; AMessage: TWSMessage);
var
  Subscribers: TArray<string>;
  ClientId: string;
begin
  Subscribers := FSubscriptionManager.GetSubscribers('user:' + AUserId);
  
  for ClientId in Subscribers do
  begin
    if Assigned(FOnDeliver) then
    begin
      try
        FOnDeliver(ClientId, AMessage);
        Inc(FTotalDelivered);
      except
        Inc(FTotalFailed);
      end;
    end;
  end;
end;

function TMessageBroker.GetRecentMessages(ACount: Integer): TArray<TWSMessage>;
var
  I, StartIdx: Integer;
begin
  FLock.Enter;
  try
    if ACount >= FMessageHistory.Count then
      StartIdx := 0
    else
      StartIdx := FMessageHistory.Count - ACount;
    
    SetLength(Result, FMessageHistory.Count - StartIdx);
    for I := StartIdx to FMessageHistory.Count - 1 do
      Result[I - StartIdx] := FMessageHistory[I];
  finally
    FLock.Leave;
  end;
end;

function TMessageBroker.GetStats: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('totalPublished', TJSONNumber.Create(FTotalPublished));
  Result.AddPair('totalDelivered', TJSONNumber.Create(FTotalDelivered));
  Result.AddPair('totalFailed', TJSONNumber.Create(FTotalFailed));
  Result.AddPair('hiDeepStorySize', TJSONNumber.Create(FMessageHistory.Count));
  Result.AddPair('subscriptions', FSubscriptionManager.GetStats);
end;

//------------------------------------------------------------------------------
// TWebSocketServerConfig
//------------------------------------------------------------------------------

constructor TWebSocketServerConfig.Create;
begin
  inherited Create;
  FPort := 8080;
  FHost := '0.0.0.0';
  FMaxClients := 1000;
  FPingIntervalMs := 30000;     // 30 seconds
  FPongTimeoutMs := 10000;      // 10 seconds
  FMaxMessageSize := 65536;     // 64KB
  FMaxQueuePerClient := 100;
  FEnableCompression := False;
  FAllowAnonymous := True;
  FRequireAuth := False;
  FAuthToken := '';
end;

//------------------------------------------------------------------------------
// TWebSocketServer
//------------------------------------------------------------------------------

constructor TWebSocketServer.Create(APort: Integer);
var
  Config: TWebSocketServerConfig;
begin
  Config := TWebSocketServerConfig.Create;
  Config.Port := APort;
  Create(Config, True);
end;

constructor TWebSocketServer.Create(AConfig: TWebSocketServerConfig; AOwnsConfig: Boolean);
begin
  inherited Create;
  FConfig := AConfig;
  FOwnsConfig := AOwnsConfig;
  FClients := TObjectDictionary<string, TWebSocketClient>.Create([doOwnsValues]);
  FUserClients := TDictionary<string, TList<string>>.Create;
  FSubscriptionManager := TSubscriptionManager.Create;
  FBroker := TMessageBroker.Create(FSubscriptionManager);
  FLock := TCriticalSection.Create;
  FRunning := False;
  FTotalConnections := 0;
  FTotalMessages := 0;
  
  // Wire up message delivery
  FBroker.OnDeliver := DeliverMessage;
end;

destructor TWebSocketServer.Destroy;
var
  ClientList: TList<string>;
begin
  Stop;
  
  for ClientList in FUserClients.Values do
    ClientList.Free;
  FUserClients.Free;
  
  FBroker.Free;
  FSubscriptionManager.Free;
  FClients.Free;
  FLock.Free;
  
  if FOwnsConfig then
    FConfig.Free;
  
  inherited Destroy;
end;

function TWebSocketServer.GenerateClientId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'ws_' + Copy(GUIDToString(GUID), 2, 8).ToLower;
end;

procedure TWebSocketServer.Start;
begin
  if FRunning then Exit;
  
  FRunning := True;
  FStartedAt := Now;
  
  StartPingThread;
  StartCleanupThread;
  
  if Assigned(FOnStart) then
    FOnStart(Self);
end;

procedure TWebSocketServer.Stop;
begin
  if not FRunning then Exit;
  
  FRunning := False;
  
  StopPingThread;
  StopCleanupThread;
  
  // Close all clients
  FLock.Enter;
  try
    FClients.Clear;
  finally
    FLock.Leave;
  end;
  
  if Assigned(FOnStop) then
    FOnStop(Self);
end;

procedure TWebSocketServer.StartPingThread;
begin
  FPingThread := TThread.CreateAnonymousThread(
    procedure
    begin
      while FRunning do
      begin
        Sleep(FConfig.PingIntervalMs);
        if FRunning then
          DoPingClients;
      end;
    end);
  FPingThread.FreeOnTerminate := False;
  FPingThread.Start;
end;

procedure TWebSocketServer.StopPingThread;
begin
  if Assigned(FPingThread) then
  begin
    FPingThread.Terminate;
    FPingThread.WaitFor;
    FreeAndNil(FPingThread);
  end;
end;

procedure TWebSocketServer.StartCleanupThread;
begin
  FCleanupThread := TThread.CreateAnonymousThread(
    procedure
    begin
      while FRunning do
      begin
        Sleep(60000);  // Every minute
        if FRunning then
          DoCleanupStaleClients;
      end;
    end);
  FCleanupThread.FreeOnTerminate := False;
  FCleanupThread.Start;
end;

procedure TWebSocketServer.StopCleanupThread;
begin
  if Assigned(FCleanupThread) then
  begin
    FCleanupThread.Terminate;
    FCleanupThread.WaitFor;
    FreeAndNil(FCleanupThread);
  end;
end;

procedure TWebSocketServer.DoPingClients;
var
  Client: TWebSocketClient;
  Msg: TWSMessage;
begin
  Msg := TWSMessage.Create(mtPing);
  try
    FLock.Enter;
    try
      for Client in FClients.Values do
      begin
        if Client.State = csOpen then
        begin
          Client.Send(Msg);
          Client.LastPingAt := Now;
        end;
      end;
    finally
      FLock.Leave;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TWebSocketServer.DoCleanupStaleClients;
var
  ClientIds: TList<string>;
  ClientId: string;
  Client: TWebSocketClient;
  TimeoutSecs: Integer;
begin
  TimeoutSecs := (FConfig.PingIntervalMs + FConfig.PongTimeoutMs) div 1000 * 2;
  ClientIds := TList<string>.Create;
  try
    FLock.Enter;
    try
      for Client in FClients.Values do
        if Client.IsStale(TimeoutSecs) then
          ClientIds.Add(Client.Id);
    finally
      FLock.Leave;
    end;
    
    for ClientId in ClientIds do
      ReDeepMoveClient(ClientId);
  finally
    ClientIds.Free;
  end;
end;

function TWebSocketServer.AddClient(const AUserId: string; const ASessionId: string): TWebSocketClient;
var
  UserClients: TList<string>;
begin
  Result := TWebSocketClient.Create(GenerateClientId);
  Result.UserId := AUserId;
  Result.SessionId := ASessionId;
  Result.State := csOpen;
  Result.MaxQueueSize := FConfig.MaxQueuePerClient;
  
  // Set up send callback (in real impl, this would use actual WebSocket)
  Result.OnSend := procedure(Client: TWebSocketClient; const AData: string)
    begin
      // In production, this would send via the actual WebSocket connection
      // For now, this is a placeholder
    end;
  
  FLock.Enter;
  try
    FClients.Add(Result.Id, Result);
    Inc(FTotalConnections);
    
    // Track user clients
    if AUserId <> '' then
    begin
      if not FUserClients.TryGetValue(AUserId, UserClients) then
      begin
        UserClients := TList<string>.Create;
        FUserClients.Add(AUserId, UserClients);
      end;
      UserClients.Add(Result.Id);
    end;
  finally
    FLock.Leave;
  end;
  
  // Send welcome message
  Result.SendWelcome;
  
  if Assigned(FOnClientConnect) then
    FOnClientConnect(Result);
end;

procedure TWebSocketServer.ReDeepMoveClient(const AClientId: string);
var
  Client: TWebSocketClient;
  UserClients: TList<string>;
begin
  FLock.Enter;
  try
    if FClients.TryGetValue(AClientId, Client) then
    begin
      // Remove from user clients
      if Client.UserId <> '' then
      begin
        if FUserClients.TryGetValue(Client.UserId, UserClients) then
          UserClients.Remove(AClientId);
      end;
      
      // Unsubscribe from all topics
      FSubscriptionManager.UnsubscribeAll(AClientId);
      
      if Assigned(FOnClientDisconnect) then
        FOnClientDisconnect(Client);
      
      FClients.Remove(AClientId);
    end;
  finally
    FLock.Leave;
  end;
end;

function TWebSocketServer.GetClient(const AClientId: string): TWebSocketClient;
begin
  FLock.Enter;
  try
    if not FClients.TryGetValue(AClientId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TWebSocketServer.GetClientsByUser(const AUserId: string): TArray<TWebSocketClient>;
var
  UserClients: TList<string>;
  Clients: TList<TWebSocketClient>;
  ClientId: string;
  Client: TWebSocketClient;
begin
  Clients := TList<TWebSocketClient>.Create;
  try
    FLock.Enter;
    try
      if FUserClients.TryGetValue(AUserId, UserClients) then
      begin
        for ClientId in UserClients do
          if FClients.TryGetValue(ClientId, Client) then
            Clients.Add(Client);
      end;
    finally
      FLock.Leave;
    end;
    Result := Clients.ToArray;
  finally
    Clients.Free;
  end;
end;

function TWebSocketServer.GetAllClients: TArray<TWebSocketClient>;
var
  Clients: TList<TWebSocketClient>;
  Client: TWebSocketClient;
begin
  Clients := TList<TWebSocketClient>.Create;
  try
    FLock.Enter;
    try
      for Client in FClients.Values do
        Clients.Add(Client);
    finally
      FLock.Leave;
    end;
    Result := Clients.ToArray;
  finally
    Clients.Free;
  end;
end;

function TWebSocketServer.GetClientCount: Integer;
begin
  FLock.Enter;
  try
    Result := FClients.Count;
  finally
    FLock.Leave;
  end;
end;

function TWebSocketServer.AuthenticateClient(AClient: TWebSocketClient; 
  const AToken: string): Boolean;
begin
  if not FConfig.RequireAuth then
    Exit(True);
  
  Result := AToken = FConfig.AuthToken;
end;

procedure TWebSocketServer.HandleClientMessage(AClient: TWebSocketClient; const AText: string);
var
  Msg: TWSMessage;
begin
  AClient.Touch;
  Inc(FTotalMessages);
  
  try
    Msg := TWSMessage.Parse(AText);
    try
      case Msg.MessageType of
        mtSubscribe:    HandleSubscribe(AClient, Msg);
        mtUnsubscribe:  HandleUnsubscribe(AClient, Msg);
        mtPing:         HandlePing(AClient, Msg);
        mtPong:         AClient.Touch;  // Just update activity
        mtMessage:
          begin
            if Assigned(FOnClientMessage) then
              FOnClientMessage(AClient, Msg);
          end;
      end;
    finally
      Msg.Free;
    end;
  except
    on E: Exception do
      AClient.SendError('PARSE_ERROR', E.Message);
  end;
end;

procedure TWebSocketServer.HandleSubscribe(AClient: TWebSocketClient; AMessage: TWSMessage);
var
  Topic, Filter: string;
  Sub: TSubscription;
  Response: TWSMessage;
begin
  Topic := AMessage.Payload.GetValue<string>('topic', '');
  Filter := AMessage.Payload.GetValue<string>('filter', '');
  
  if Topic = '' then
  begin
    AClient.SendError('INVALID_TOPIC', 'Topic is required');
    Exit;
  end;
  
  // Check authorization for "all" topic
  if (Topic = 'all') and not FConfig.AllowAnonymous and (AClient.UserId = '') then
  begin
    AClient.SendError('UNAUTHORIZED', 'Authentication required for "all" topic');
    Exit;
  end;
  
  Sub := FSubscriptionManager.Subscribe(AClient.Id, Topic, Filter);
  AClient.AddSubscription(Sub);
  
  Response := TWSMessage.Create(mtSubscribed);
  try
    Response.Topic := Topic;
    Response.CorrelationId := AMessage.Id;
    AClient.Send(Response);
  finally
    Response.Free;
  end;
end;

procedure TWebSocketServer.HandleUnsubscribe(AClient: TWebSocketClient; AMessage: TWSMessage);
var
  Topic: string;
  Response: TWSMessage;
begin
  Topic := AMessage.Payload.GetValue<string>('topic', '');
  
  if Topic = '' then
  begin
    AClient.SendError('INVALID_TOPIC', 'Topic is required');
    Exit;
  end;
  
  FSubscriptionManager.Unsubscribe(AClient.Id, Topic);
  AClient.RemoveSubscription(Topic);
  
  Response := TWSMessage.Create(mtUnsubscribed);
  try
    Response.Topic := Topic;
    Response.CorrelationId := AMessage.Id;
    AClient.Send(Response);
  finally
    Response.Free;
  end;
end;

procedure TWebSocketServer.HandlePing(AClient: TWebSocketClient; AMessage: TWSMessage);
begin
  AClient.SendPong;
end;

procedure TWebSocketServer.DeliverMessage(const AClientId: string; AMessage: TWSMessage);
var
  Client: TWebSocketClient;
begin
  Client := GetClient(AClientId);
  if Assigned(Client) then
    Client.Send(AMessage);
end;

procedure TWebSocketServer.SendToClient(const AClientId: string; AMessage: TWSMessage);
begin
  FBroker.SendToClient(AClientId, AMessage);
end;

procedure TWebSocketServer.SendToUser(const AUserId: string; AMessage: TWSMessage);
begin
  FBroker.SendToUser(AUserId, AMessage);
end;

procedure TWebSocketServer.SendToAll(AMessage: TWSMessage);
begin
  FBroker.Broadcast(AMessage);
end;

procedure TWebSocketServer.PublishEvent(AEvent: TWorkflowEvent);
begin
  FBroker.PublishEvent(AEvent);
end;

procedure TWebSocketServer.SimulateReceive(const AClientId: string; const AText: string);
var
  Client: TWebSocketClient;
begin
  Client := GetClient(AClientId);
  if Assigned(Client) then
    HandleClientMessage(Client, AText);
end;

function TWebSocketServer.GetStats: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('running', TJSONBool.Create(FRunning));
  if FRunning then
    Result.AddPair('uptime', TJSONNumber.Create(SecondsBetween(Now, FStartedAt)));
  Result.AddPair('port', TJSONNumber.Create(FConfig.Port));
  Result.AddPair('clientCount', TJSONNumber.Create(GetClientCount));
  Result.AddPair('totalConnections', TJSONNumber.Create(FTotalConnections));
  Result.AddPair('totalMessages', TJSONNumber.Create(FTotalMessages));
  Result.AddPair('broker', FBroker.GetStats);
end;

function TWebSocketServer.IsRunning: Boolean;
begin
  Result := FRunning;
end;

//------------------------------------------------------------------------------
// TWorkflowEventBridge
//------------------------------------------------------------------------------

constructor TWorkflowEventBridge.Create(AServer: TWebSocketServer);
begin
  inherited Create;
  FServer := AServer;
  FEnabled := True;
  FIncludeStepEvents := True;
  FIncludeVariableEvents := False;
  FLock := TCriticalSection.Create;
end;

destructor TWorkflowEventBridge.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TWorkflowEventBridge.OnWorkflowStarted(const AWorkflowId, AWorkflowName, 
  ASessionId, AUserId: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetWorkflowStarted);
  try
    Event.WorkflowId := AWorkflowId;
    Event.WorkflowName := AWorkflowName;
    Event.SessionId := ASessionId;
    Event.UserId := AUserId;
    Event.Message := 'Workflow started';
    Event.Progress := 0;
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnWorkflowCompleted(const AWorkflowId, AWorkflowName, 
  ASessionId, AUserId: string; ADurationMs: Integer);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetWorkflowCompleted);
  try
    Event.WorkflowId := AWorkflowId;
    Event.WorkflowName := AWorkflowName;
    Event.SessionId := ASessionId;
    Event.UserId := AUserId;
    Event.Message := 'Workflow completed';
    Event.Progress := 100;
    Event.Data.AddPair('durationMs', TJSONNumber.Create(ADurationMs));
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnWorkflowFailed(const AWorkflowId, AWorkflowName, 
  ASessionId, AUserId, AError: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetWorkflowFailed);
  try
    Event.WorkflowId := AWorkflowId;
    Event.WorkflowName := AWorkflowName;
    Event.SessionId := ASessionId;
    Event.UserId := AUserId;
    Event.Message := AError;
    Event.Data.AddPair('error', AError);
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnWorkflowPaused(const AWorkflowId, AWorkflowName, 
  ASessionId, AUserId: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetWorkflowPaused);
  try
    Event.WorkflowId := AWorkflowId;
    Event.WorkflowName := AWorkflowName;
    Event.SessionId := ASessionId;
    Event.UserId := AUserId;
    Event.Message := 'Workflow paused';
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnWorkflowResumed(const AWorkflowId, AWorkflowName, 
  ASessionId, AUserId: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetWorkflowResumed);
  try
    Event.WorkflowId := AWorkflowId;
    Event.WorkflowName := AWorkflowName;
    Event.SessionId := ASessionId;
    Event.UserId := AUserId;
    Event.Message := 'Workflow resumed';
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnWorkflowCancelled(const AWorkflowId, AWorkflowName, 
  ASessionId, AUserId: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetWorkflowCancelled);
  try
    Event.WorkflowId := AWorkflowId;
    Event.WorkflowName := AWorkflowName;
    Event.SessionId := ASessionId;
    Event.UserId := AUserId;
    Event.Message := 'Workflow cancelled';
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnStepStarted(const AWorkflowId, AStepId, AStepName: string;
  AStepIndex, ATotalSteps: Integer);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled or not FIncludeStepEvents then Exit;
  
  Event := TWorkflowEvent.Create(wetStepStarted);
  try
    Event.WorkflowId := AWorkflowId;
    Event.StepId := AStepId;
    Event.StepName := AStepName;
    Event.Message := Format('Step %d/%d: %s', [AStepIndex + 1, ATotalSteps, AStepName]);
    if ATotalSteps > 0 then
      Event.Progress := Round((AStepIndex / ATotalSteps) * 100);
    Event.Data.AddPair('stepIndex', TJSONNumber.Create(AStepIndex));
    Event.Data.AddPair('totalSteps', TJSONNumber.Create(ATotalSteps));
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnStepCompleted(const AWorkflowId, AStepId, AStepName: string;
  ADurationMs: Integer);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled or not FIncludeStepEvents then Exit;
  
  Event := TWorkflowEvent.Create(wetStepCompleted);
  try
    Event.WorkflowId := AWorkflowId;
    Event.StepId := AStepId;
    Event.StepName := AStepName;
    Event.Message := Format('Step completed: %s (%dms)', [AStepName, ADurationMs]);
    Event.Data.AddPair('durationMs', TJSONNumber.Create(ADurationMs));
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnStepFailed(const AWorkflowId, AStepId, AStepName, AError: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled or not FIncludeStepEvents then Exit;
  
  Event := TWorkflowEvent.Create(wetStepFailed);
  try
    Event.WorkflowId := AWorkflowId;
    Event.StepId := AStepId;
    Event.StepName := AStepName;
    Event.Message := Format('Step failed: %s - %s', [AStepName, AError]);
    Event.Data.AddPair('error', AError);
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnProgressUpdate(const AWorkflowId: string; 
  AProgress: Integer; const AMessage: string);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetProgressUpdate);
  try
    Event.WorkflowId := AWorkflowId;
    Event.Progress := AProgress;
    Event.Message := AMessage;
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

procedure TWorkflowEventBridge.OnCustomEvent(const AWorkflowId, AEventName: string;
  AData: TJSONObject);
var
  Event: TWorkflowEvent;
begin
  if not FEnabled then Exit;
  
  Event := TWorkflowEvent.Create(wetCustom);
  try
    Event.WorkflowId := AWorkflowId;
    Event.Message := AEventName;
    if Assigned(AData) then
    begin
      Event.FData.Free;
      Event.FData := AData.Clone as TJSONObject;
    end;
    FServer.PublishEvent(Event);
  finally
    Event.Free;
  end;
end;

//------------------------------------------------------------------------------
// Factory functions
//------------------------------------------------------------------------------

function CreateWorkflowEvent(AEventType: TWorkflowEventType; const AWorkflowId: string): TWorkflowEvent;
begin
  Result := TWorkflowEvent.Create(AEventType);
  Result.WorkflowId := AWorkflowId;
end;

function CreateWSMessage(AType: TWSMessageType; const ATopic: string): TWSMessage;
begin
  Result := TWSMessage.Create(AType);
  Result.Topic := ATopic;
end;

end.
