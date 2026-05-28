(* ============================================================================
  UniFlow.Roles.Commander - Request Entry Point and Workflow Router

  Version: 1.0
  Description: Commander role handles incoming requests, recognizes intent,
               routes to appropriate workflow, and assembles responses

  Features:
    - Request entry point
    - Intent recognition (rule-based + LLM fallback)
    - Workflow routing
    - Response assembly
    - Error handling

  Usage:
    var Commander := TCommander.Create(SessionManager, WorkflowRegistry);
    Commander.RegisterRoute('greeting', 'workflow_greeting');
    var Response := Commander.ProcessRequest(Request);
  ============================================================================ *)

unit UniFlow.Roles.Commander;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  System.SyncObjs,
  UniFlow.Session.Types,
  UniFlow.Session.Manager,
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Context,
  UniFlow.Workflow.Executor,
  DeepBase.Exceptions;

type
  // ============================================================================
  // Request Types
  // ============================================================================

  /// <summary>
  /// User request containing message and metadata
  /// </summary>
  TUserRequest = class
  private
    FSessionId: string;
    FUserId: string;
    FMessage: string;
    FMetadata: TJSONObject;
    FTimestamp: TDateTime;
    FRequestId: string;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    procedure LoadFromJSON(AJson: TJSONObject);

    property SessionId: string read FSessionId write FSessionId;
    property UserId: string read FUserId write FUserId;
    property Message: string read FMessage write FMessage;
    property Metadata: TJSONObject read FMetadata;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property RequestId: string read FRequestId write FRequestId;
  end;

  /// <summary>
  /// Response status
  /// </summary>
  TResponseStatus = (
    rsSuccess,
    rsError,
    rsPartial,
    rsNeedsInput
  );

  /// <summary>
  /// Commander response
  /// </summary>
  TCommanderResponse = class
  private
    FRequestId: string;
    FSessionId: string;
    FStatus: TResponseStatus;
    FMessage: string;
    FData: TJSONObject;
    FErrorCode: string;
    FErrorMessage: string;
    FTimestamp: TDateTime;
    FSuggestedActions: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;

    class function Success(const AMessage: string; AData: TJSONObject = nil): TCommanderResponse;
    class function Error(const ACode, AMessage: string): TCommanderResponse;
    class function NeedsInput(const APrompt: string): TCommanderResponse;

    function ToJSON: TJSONObject;

    property RequestId: string read FRequestId write FRequestId;
    property SessionId: string read FSessionId write FSessionId;
    property Status: TResponseStatus read FStatus write FStatus;
    property Message: string read FMessage write FMessage;
    property Data: TJSONObject read FData write FData;
    property ErrorCode: string read FErrorCode write FErrorCode;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property SuggestedActions: TList<string> read FSuggestedActions;
  end;

  // ============================================================================
  // Intent Recognition
  // ============================================================================

  /// <summary>
  /// Recognized intent
  /// </summary>
  TIntent = class
  private
    FName: string;
    FConfidence: Double;
    FEntities: TJSONObject;
    FMatchedPattern: string;
  public
    constructor Create;
    destructor Destroy; override;

    property Name: string read FName write FName;
    property Confidence: Double read FConfidence write FConfidence;
    property Entities: TJSONObject read FEntities;
    property MatchedPattern: string read FMatchedPattern write FMatchedPattern;
  end;

  /// <summary>
  /// Intent pattern definition
  /// </summary>
  TIntentPattern = record
    IntentName: string;
    Patterns: TArray<string>;  // Regex patterns
    Keywords: TArray<string>;  // Simple keyword matching
    Priority: Integer;         // Higher priority wins on tie
  end;

  /// <summary>
  /// Intent recognizer
  /// </summary>
  TIntentRecognizer = class
  private
    FPatterns: TList<TIntentPattern>;
    FDefaultIntent: string;
    FMinConfidence: Double;
    FLock: TCriticalSection;

    function MatchPatterns(const AText: string; const APatternDef: TIntentPattern): Double;
    function MatchKeywords(const AText: string; const APatternDef: TIntentPattern): Double;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Register intent pattern
    /// </summary>
    procedure RegisterIntent(const AIntentName: string;
      const APatterns, AKeywords: TArray<string>;
      APriority: Integer = 0);

    /// <summary>
    /// Recognize intent from text
    /// </summary>
    function Recognize(const AText: string): TIntent;

    /// <summary>
    /// Recognize multiple possible intents
    /// </summary>
    function RecognizeAll(const AText: string; AMaxResults: Integer = 3): TArray<TIntent>;

    property DefaultIntent: string read FDefaultIntent write FDefaultIntent;
    property MinConfidence: Double read FMinConfidence write FMinConfidence;
  end;

  // ============================================================================
  // Workflow Route
  // ============================================================================

  /// <summary>
  /// Route definition
  /// </summary>
  TWorkflowRoute = record
    IntentName: string;
    WorkflowId: string;
    RequiresAuth: Boolean;
    Metadata: TJSONObject;
  end;

  /// <summary>
  /// Workflow registry interface
  /// </summary>
  IWorkflowRegistry = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F23456789012}']
    function GetWorkflow(const AWorkflowId: string): TWorkflowDefinition;
    function WorkflowExists(const AWorkflowId: string): Boolean;
    function GetAllWorkflowIds: TArray<string>;
  end;

  // ============================================================================
  // Commander
  // ============================================================================

  TOnRequestReceived = reference to procedure(Request: TUserRequest);
  TOnResponseSent = reference to procedure(Response: TCommanderResponse);
  TOnIntentRecognized = reference to procedure(Intent: TIntent);

  /// <summary>
  /// Commander - Request entry point and workflow router
  /// </summary>
  TCommander = class
  private
    FSessionManager: TSessionManager;
    FWorkflowRegistry: IWorkflowRegistry;
    FIntentRecognizer: TIntentRecognizer;
    FRoutes: TDictionary<string, TWorkflowRoute>;
    FDefaultWorkflowId: string;
    FLock: TCriticalSection;

    // Events
    FOnRequestReceived: TOnRequestReceived;
    FOnResponseSent: TOnResponseSent;
    FOnIntentRecognized: TOnIntentRecognized;

    // Config
    FRequireSession: Boolean;
    FAutoCreateSession: Boolean;
    FMaxMessageLength: Integer;

    function GetOrCreateSession(Request: TUserRequest): TSession;
    function RouteToWorkflow(Intent: TIntent; Session: TSession): TWorkflowDefinition;
    function ExecuteWorkflow(Workflow: TWorkflowDefinition;
      Request: TUserRequest; Session: TSession): TCommanderResponse;
    function AssembleResponse(const ARequestId, ASessionId: string;
      ExecutorResult: TStepResult): TCommanderResponse;
    function ValidateRequest(Request: TUserRequest): TCommanderResponse;
  public
    constructor Create(ASessionManager: TSessionManager;
      AWorkflowRegistry: IWorkflowRegistry = nil);
    destructor Destroy; override;

    /// <summary>
    /// Register workflow route
    /// </summary>
    procedure RegisterRoute(const AIntentName, AWorkflowId: string;
      ARequiresAuth: Boolean = False);

    /// <summary>
    /// Register intent pattern
    /// </summary>
    procedure RegisterIntent(const AIntentName: string;
      const APatterns, AKeywords: TArray<string>;
      APriority: Integer = 0);

    /// <summary>
    /// Process incoming request
    /// </summary>
    function ProcessRequest(Request: TUserRequest): TCommanderResponse;

    /// <summary>
    /// Process raw message (creates request internally)
    /// </summary>
    function ProcessMessage(const ASessionId, AMessage: string): TCommanderResponse;

    /// <summary>
    /// Get available intents
    /// </summary>
    function GetAvailableIntents: TArray<string>;

    /// <summary>
    /// Get route info
    /// </summary>
    function GetRouteInfo(const AIntentName: string): TWorkflowRoute;

    property SessionManager: TSessionManager read FSessionManager;
    property WorkflowRegistry: IWorkflowRegistry read FWorkflowRegistry write FWorkflowRegistry;
    property IntentRecognizer: TIntentRecognizer read FIntentRecognizer;
    property DefaultWorkflowId: string read FDefaultWorkflowId write FDefaultWorkflowId;
    property RequireSession: Boolean read FRequireSession write FRequireSession;
    property AutoCreateSession: Boolean read FAutoCreateSession write FAutoCreateSession;
    property MaxMessageLength: Integer read FMaxMessageLength write FMaxMessageLength;

    // Events
    property OnRequestReceived: TOnRequestReceived read FOnRequestReceived write FOnRequestReceived;
    property OnResponseSent: TOnResponseSent read FOnResponseSent write FOnResponseSent;
    property OnIntentRecognized: TOnIntentRecognized read FOnIntentRecognized write FOnIntentRecognized;
  end;

  // ============================================================================
  // Simple Workflow Registry Implementation
  // ============================================================================

  /// <summary>
  /// Simple in-memory workflow registry
  /// </summary>
  TSimpleWorkflowRegistry = class(TInterfacedObject, IWorkflowRegistry)
  private
    FWorkflows: TObjectDictionary<string, TWorkflowDefinition>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterWorkflow(Workflow: TWorkflowDefinition);
    procedure RegisterWorkflowFromFile(const AFilePath: string);
    procedure UnregisterWorkflow(const AWorkflowId: string);

    function GetWorkflow(const AWorkflowId: string): TWorkflowDefinition;
    function WorkflowExists(const AWorkflowId: string): Boolean;
    function GetAllWorkflowIds: TArray<string>;
  end;

implementation

uses
  System.DateUtils,
  System.IOUtils;

{ TUserRequest }

constructor TUserRequest.Create;
begin
  inherited;
  FMetadata := TJSONObject.Create;
  FTimestamp := Now;
  FRequestId := TGUID.NewGuid.ToString;
end;

destructor TUserRequest.Destroy;
begin
  FMetadata.Free;
  inherited;
end;

function TUserRequest.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('request_id', FRequestId);
  Result.AddPair('session_id', FSessionId);
  Result.AddPair('user_id', FUserId);
  Result.AddPair('message', FMessage);
  Result.AddPair('timestamp', DateTimeToStr(FTimestamp));
  if Assigned(FMetadata) then
    Result.AddPair('metadata', FMetadata.Clone as TJSONObject);
end;

procedure TUserRequest.LoadFromJSON(AJson: TJSONObject);
begin
  if AJson.GetValue('request_id') <> nil then
    FRequestId := AJson.GetValue<string>('request_id');
  if AJson.GetValue('session_id') <> nil then
    FSessionId := AJson.GetValue<string>('session_id');
  if AJson.GetValue('user_id') <> nil then
    FUserId := AJson.GetValue<string>('user_id');
  if AJson.GetValue('message') <> nil then
    FMessage := AJson.GetValue<string>('message');
end;

{ TCommanderResponse }

constructor TCommanderResponse.Create;
begin
  inherited;
  FData := TJSONObject.Create;
  FSuggestedActions := TList<string>.Create;
  FTimestamp := Now;
  FStatus := rsSuccess;
end;

destructor TCommanderResponse.Destroy;
begin
  FData.Free;
  FSuggestedActions.Free;
  inherited;
end;

class function TCommanderResponse.Success(const AMessage: string;
  AData: TJSONObject): TCommanderResponse;
begin
  Result := TCommanderResponse.Create;
  Result.FStatus := rsSuccess;
  Result.FMessage := AMessage;
  if Assigned(AData) then
  begin
    Result.FData.Free;
    Result.FData := AData.Clone as TJSONObject;
  end;
end;

class function TCommanderResponse.Error(const ACode, AMessage: string): TCommanderResponse;
begin
  Result := TCommanderResponse.Create;
  Result.FStatus := rsError;
  Result.FErrorCode := ACode;
  Result.FErrorMessage := AMessage;
  Result.FMessage := AMessage;
end;

class function TCommanderResponse.NeedsInput(const APrompt: string): TCommanderResponse;
begin
  Result := TCommanderResponse.Create;
  Result.FStatus := rsNeedsInput;
  Result.FMessage := APrompt;
end;

function TCommanderResponse.ToJSON: TJSONObject;
var
  StatusStr: string;
  ActionsArr: TJSONArray;
  Action: string;
begin
  case FStatus of
    rsSuccess: StatusStr := 'success';
    rsError: StatusStr := 'error';
    rsPartial: StatusStr := 'partial';
    rsNeedsInput: StatusStr := 'needs_input';
  end;

  Result := TJSONObject.Create;
  Result.AddPair('request_id', FRequestId);
  Result.AddPair('session_id', FSessionId);
  Result.AddPair('status', StatusStr);
  Result.AddPair('message', FMessage);
  Result.AddPair('timestamp', DateTimeToStr(FTimestamp));

  if FStatus = rsError then
  begin
    Result.AddPair('error_code', FErrorCode);
    Result.AddPair('error_message', FErrorMessage);
  end;

  if Assigned(FData) and (FData.Count > 0) then
    Result.AddPair('data', FData.Clone as TJSONObject);

  if FSuggestedActions.Count > 0 then
  begin
    ActionsArr := TJSONArray.Create;
    for Action in FSuggestedActions do
      ActionsArr.Add(Action);
    Result.AddPair('suggested_actions', ActionsArr);
  end;
end;

{ TIntent }

constructor TIntent.Create;
begin
  inherited;
  FEntities := TJSONObject.Create;
  FConfidence := 0;
end;

destructor TIntent.Destroy;
begin
  FEntities.Free;
  inherited;
end;

{ TIntentRecognizer }

constructor TIntentRecognizer.Create;
begin
  inherited;
  FPatterns := TList<TIntentPattern>.Create;
  FDefaultIntent := 'unknown';
  FMinConfidence := 0.3;
  FLock := TCriticalSection.Create;
end;

destructor TIntentRecognizer.Destroy;
begin
  FPatterns.Free;
  FLock.Free;
  inherited;
end;

procedure TIntentRecognizer.RegisterIntent(const AIntentName: string;
  const APatterns, AKeywords: TArray<string>; APriority: Integer);
var
  Pattern: TIntentPattern;
begin
  FLock.Enter;
  try
    Pattern.IntentName := AIntentName;
    Pattern.Patterns := APatterns;
    Pattern.Keywords := AKeywords;
    Pattern.Priority := APriority;
    FPatterns.Add(Pattern);
  finally
    FLock.Leave;
  end;
end;

function TIntentRecognizer.MatchPatterns(const AText: string;
  const APatternDef: TIntentPattern): Double;
var
  Pattern: string;
  Regex: TRegEx;
begin
  Result := 0;
  for Pattern in APatternDef.Patterns do
  begin
    try
      Regex := TRegEx.Create(Pattern, [roIgnoreCase]);
      if Regex.IsMatch(AText) then
      begin
        Result := 0.9;  // High confidence for regex match
        Exit;
      end;
    except
      // Invalid regex, skip
    end;
  end;
end;

function TIntentRecognizer.MatchKeywords(const AText: string;
  const APatternDef: TIntentPattern): Double;
var
  Keyword: string;
  LowerText: string;
  MatchCount: Integer;
begin
  Result := 0;
  if Length(APatternDef.Keywords) = 0 then
    Exit;

  LowerText := LowerCase(AText);
  MatchCount := 0;

  for Keyword in APatternDef.Keywords do
  begin
    if Pos(LowerCase(Keyword), LowerText) > 0 then
      Inc(MatchCount);
  end;

  if MatchCount > 0 then
    Result := 0.5 + (0.4 * MatchCount / Length(APatternDef.Keywords));
end;

function TIntentRecognizer.Recognize(const AText: string): TIntent;
var
  PatternDef: TIntentPattern;
  PatternScore, KeywordScore, BestScore, Score: Double;
  BestIntent: string;
  BestPattern: string;
begin
  Result := TIntent.Create;
  BestScore := 0;
  BestIntent := FDefaultIntent;
  BestPattern := '';

  FLock.Enter;
  try
    for PatternDef in FPatterns do
    begin
      PatternScore := MatchPatterns(AText, PatternDef);
      KeywordScore := MatchKeywords(AText, PatternDef);
      Score := Max(PatternScore, KeywordScore);

      // Apply priority bonus
      Score := Score + (PatternDef.Priority * 0.01);

      if Score > BestScore then
      begin
        BestScore := Score;
        BestIntent := PatternDef.IntentName;
        if PatternScore > KeywordScore then
          BestPattern := 'pattern'
        else
          BestPattern := 'keyword';
      end;
    end;
  finally
    FLock.Leave;
  end;

  if BestScore >= FMinConfidence then
  begin
    Result.FName := BestIntent;
    Result.FConfidence := BestScore;
    Result.FMatchedPattern := BestPattern;
  end
  else
  begin
    Result.FName := FDefaultIntent;
    Result.FConfidence := 0;
    Result.FMatchedPattern := '';
  end;
end;

function TIntentRecognizer.RecognizeAll(const AText: string;
  AMaxResults: Integer): TArray<TIntent>;
var
  PatternDef: TIntentPattern;
  PatternScore, KeywordScore, Score: Double;
  Intent: TIntent;
  ResultList: TList<TIntent>;
  I, J: Integer;
  Temp: TIntent;
begin
  ResultList := TList<TIntent>.Create;
  try
    FLock.Enter;
    try
      for PatternDef in FPatterns do
      begin
        PatternScore := MatchPatterns(AText, PatternDef);
        KeywordScore := MatchKeywords(AText, PatternDef);
        Score := Max(PatternScore, KeywordScore);

        if Score >= FMinConfidence then
        begin
          Intent := TIntent.Create;
          Intent.FName := PatternDef.IntentName;
          Intent.FConfidence := Score + (PatternDef.Priority * 0.01);
          Intent.FMatchedPattern := IfThen(PatternScore > KeywordScore, 'pattern', 'keyword');
          ResultList.Add(Intent);
        end;
      end;
    finally
      FLock.Leave;
    end;

    // Sort by confidence (descending)
    for I := 0 to ResultList.Count - 2 do
      for J := I + 1 to ResultList.Count - 1 do
        if ResultList[J].Confidence > ResultList[I].Confidence then
        begin
          Temp := ResultList[I];
          ResultList[I] := ResultList[J];
          ResultList[J] := Temp;
        end;

    // Return top N
    SetLength(Result, Min(AMaxResults, ResultList.Count));
    for I := 0 to High(Result) do
      Result[I] := ResultList[I];

    // Clean up extras
    for I := Length(Result) to ResultList.Count - 1 do
      ResultList[I].Free;
  finally
    ResultList.Free;
  end;
end;

{ TCommander }

constructor TCommander.Create(ASessionManager: TSessionManager;
  AWorkflowRegistry: IWorkflowRegistry);
begin
  inherited Create;
  FSessionManager := ASessionManager;
  FWorkflowRegistry := AWorkflowRegistry;
  FIntentRecognizer := TIntentRecognizer.Create;
  FRoutes := TDictionary<string, TWorkflowRoute>.Create;
  FLock := TCriticalSection.Create;

  // Defaults
  FRequireSession := False;
  FAutoCreateSession := True;
  FMaxMessageLength := 10000;
  FDefaultWorkflowId := '';
end;

destructor TCommander.Destroy;
begin
  FRoutes.Free;
  FIntentRecognizer.Free;
  FLock.Free;
  inherited;
end;

procedure TCommander.RegisterRoute(const AIntentName, AWorkflowId: string;
  ARequiresAuth: Boolean);
var
  Route: TWorkflowRoute;
begin
  FLock.Enter;
  try
    Route.IntentName := AIntentName;
    Route.WorkflowId := AWorkflowId;
    Route.RequiresAuth := ARequiresAuth;
    Route.Metadata := nil;
    FRoutes.AddOrSetValue(AIntentName, Route);
  finally
    FLock.Leave;
  end;
end;

procedure TCommander.RegisterIntent(const AIntentName: string;
  const APatterns, AKeywords: TArray<string>; APriority: Integer);
begin
  FIntentRecognizer.RegisterIntent(AIntentName, APatterns, AKeywords, APriority);
end;

function TCommander.GetOrCreateSession(Request: TUserRequest): TSession;
begin
  Result := nil;

  if Request.SessionId <> '' then
    Result := FSessionManager.GetSession(Request.SessionId);

  if (Result = nil) and FAutoCreateSession then
    Result := FSessionManager.CreateSession(Request.UserId);
end;

function TCommander.ValidateRequest(Request: TUserRequest): TCommanderResponse;
begin
  Result := nil;

  // Check message length
  if Length(Request.Message) > FMaxMessageLength then
  begin
    Result := TCommanderResponse.Error('MSG_TOO_LONG',
      Format('Message exceeds maximum length of %d characters', [FMaxMessageLength]));
    Exit;
  end;

  // Check message not empty
  if Trim(Request.Message) = '' then
  begin
    Result := TCommanderResponse.Error('MSG_EMPTY', 'Message cannot be empty');
    Exit;
  end;
end;

function TCommander.RouteToWorkflow(Intent: TIntent;
  Session: TSession): TWorkflowDefinition;
var
  Route: TWorkflowRoute;
  WorkflowId: string;
begin
  Result := nil;
  WorkflowId := '';

  FLock.Enter;
  try
    if FRoutes.TryGetValue(Intent.Name, Route) then
      WorkflowId := Route.WorkflowId
    else if FDefaultWorkflowId <> '' then
      WorkflowId := FDefaultWorkflowId;
  finally
    FLock.Leave;
  end;

  if (WorkflowId <> '') and Assigned(FWorkflowRegistry) then
  begin
    if FWorkflowRegistry.WorkflowExists(WorkflowId) then
      Result := FWorkflowRegistry.GetWorkflow(WorkflowId);
  end;
end;

function TCommander.ExecuteWorkflow(Workflow: TWorkflowDefinition;
  Request: TUserRequest; Session: TSession): TCommanderResponse;
var
  Context: TWorkflowContext;
  Executor: TWorkflowExecutor;
  StepResult: TStepResult;
begin
  Context := TWorkflowContext.Create(Workflow.Id, TGUID.NewGuid.ToString);
  try
    // Set up context
    Context.SetVariable('user_message', Request.Message);
    Context.SetVariable('user_id', Request.UserId);
    Context.SetVariable('session_id', Request.SessionId);
    Context.SetVariable('request_id', Request.RequestId);

    // Add session hiDeepStory if available
    if Assigned(Session) then
    begin
      Context.SetVariable('session_context', Session.ToJSON);
      Context.SetVariable('message_count', IntToStr(Session.Messages.Count));
    end;

    Executor := TWorkflowExecutor.Create(Workflow, Context);
    try
      StepResult := Executor.Start;
      Result := AssembleResponse(Request.RequestId, Request.SessionId, StepResult);
    finally
      Executor.Free;
    end;
  finally
    Context.Free;
  end;
end;

function TCommander.AssembleResponse(const ARequestId, ASessionId: string;
  ExecutorResult: TStepResult): TCommanderResponse;
var
  OutputStr: string;
begin
  Result := TCommanderResponse.Create;
  Result.FRequestId := ARequestId;
  Result.FSessionId := ASessionId;
  Result.FTimestamp := Now;

  if ExecutorResult.Success then
  begin
    Result.FStatus := rsSuccess;

    // Extract message from output
    if Assigned(ExecutorResult.Output) then
    begin
      if ExecutorResult.Output is TJSONString then
        Result.FMessage := (ExecutorResult.Output as TJSONString).Value
      else if ExecutorResult.Output is TJSONObject then
      begin
        OutputStr := (ExecutorResult.Output as TJSONObject).GetValue<string>('message', '');
        if OutputStr = '' then
          OutputStr := (ExecutorResult.Output as TJSONObject).GetValue<string>('response', '');
        if OutputStr = '' then
          OutputStr := (ExecutorResult.Output as TJSONObject).GetValue<string>('content', '');
        Result.FMessage := OutputStr;
        Result.FData.Free;
        Result.FData := ExecutorResult.Output.Clone as TJSONObject;
      end
      else
        Result.FMessage := ExecutorResult.Output.ToString;
    end
    else
      Result.FMessage := 'Workflow completed successfully';
  end
  else if ExecutorResult.NeedsWait then
  begin
    Result.FStatus := rsNeedsInput;
    Result.FMessage := 'Waiting for input';
    if Assigned(ExecutorResult.WaitData) then
    begin
      Result.FData.Free;
      Result.FData := ExecutorResult.WaitData.Clone as TJSONObject;
    end;
  end
  else
  begin
    Result.FStatus := rsError;
    Result.FErrorCode := ExecutorResult.ErrorCode;
    Result.FErrorMessage := ExecutorResult.ErrorMessage;
    Result.FMessage := ExecutorResult.ErrorMessage;
  end;
end;

function TCommander.ProcessRequest(Request: TUserRequest): TCommanderResponse;
var
  Session: TSession;
  Intent: TIntent;
  Workflow: TWorkflowDefinition;
  ValidationResult: TCommanderResponse;
begin
  // Fire event
  if Assigned(FOnRequestReceived) then
    FOnRequestReceived(Request);

  // Validate request
  ValidationResult := ValidateRequest(Request);
  if Assigned(ValidationResult) then
  begin
    Result := ValidationResult;
    if Assigned(FOnResponseSent) then
      FOnResponseSent(Result);
    Exit;
  end;

  // Get or create session
  Session := GetOrCreateSession(Request);
  if FRequireSession and (Session = nil) then
  begin
    Result := TCommanderResponse.Error('NO_SESSION', 'Valid session required');
    if Assigned(FOnResponseSent) then
      FOnResponseSent(Result);
    Exit;
  end;

  // Update request with session ID if auto-created
  if Assigned(Session) and (Request.SessionId = '') then
    Request.SessionId := Session.Id;

  // Add message to session hiDeepStory
  if Assigned(Session) then
    Session.AddUserMessage(Request.Message);

  // Recognize intent
  Intent := FIntentRecognizer.Recognize(Request.Message);
  try
    if Assigned(FOnIntentRecognized) then
      FOnIntentRecognized(Intent);

    // Route to workflow
    Workflow := RouteToWorkflow(Intent, Session);
    if Workflow = nil then
    begin
      // No workflow found - return default response
      Result := TCommanderResponse.Create;
      Result.FRequestId := Request.RequestId;
      Result.FSessionId := Request.SessionId;
      Result.FStatus := rsSuccess;
      Result.FMessage := Format('Intent recognized: %s (confidence: %.2f). No workflow configured.',
        [Intent.Name, Intent.Confidence]);
      Result.FData.AddPair('intent', Intent.Name);
      Result.FData.AddPair('confidence', TJSONNumber.Create(Intent.Confidence));
    end
    else
    begin
      // Execute workflow
      Result := ExecuteWorkflow(Workflow, Request, Session);
    end;

    // Add response to session
    if Assigned(Session) then
      Session.AddAssistantMessage(Result.Message);

    // Save session
    if Assigned(Session) then
      FSessionManager.SaveSession(Session);

    if Assigned(FOnResponseSent) then
      FOnResponseSent(Result);
  finally
    Intent.Free;
  end;
end;

function TCommander.ProcessMessage(const ASessionId, AMessage: string): TCommanderResponse;
var
  Request: TUserRequest;
begin
  Request := TUserRequest.Create;
  try
    Request.SessionId := ASessionId;
    Request.Message := AMessage;
    Result := ProcessRequest(Request);
  finally
    Request.Free;
  end;
end;

function TCommander.GetAvailableIntents: TArray<string>;
var
  IntentList: TList<string>;
  Route: TWorkflowRoute;
begin
  IntentList := TList<string>.Create;
  try
    FLock.Enter;
    try
      for Route in FRoutes.Values do
        IntentList.Add(Route.IntentName);
    finally
      FLock.Leave;
    end;
    Result := IntentList.ToArray;
  finally
    IntentList.Free;
  end;
end;

function TCommander.GetRouteInfo(const AIntentName: string): TWorkflowRoute;
begin
  FLock.Enter;
  try
    if not FRoutes.TryGetValue(AIntentName, Result) then
    begin
      Result.IntentName := '';
      Result.WorkflowId := '';
      Result.RequiresAuth := False;
      Result.Metadata := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

{ TSimpleWorkflowRegistry }

constructor TSimpleWorkflowRegistry.Create;
begin
  inherited;
  FWorkflows := TObjectDictionary<string, TWorkflowDefinition>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
end;

destructor TSimpleWorkflowRegistry.Destroy;
begin
  FWorkflows.Free;
  FLock.Free;
  inherited;
end;

procedure TSimpleWorkflowRegistry.RegisterWorkflow(Workflow: TWorkflowDefinition);
begin
  FLock.Enter;
  try
    FWorkflows.AddOrSetValue(Workflow.Id, Workflow);
  finally
    FLock.Leave;
  end;
end;

procedure TSimpleWorkflowRegistry.RegisterWorkflowFromFile(const AFilePath: string);
var
  JsonStr: string;
  JsonObj: TJSONObject;
  Workflow: TWorkflowDefinition;
begin
  if not TFile.Exists(AFilePath) then
    raise EOperationException.CreateFmt('Workflow file not found: %s', [AFilePath]);

  JsonStr := TFile.ReadAllText(AFilePath);
  JsonObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JsonObj = nil then
    raise EOperationException.Create('Invalid JSON in workflow file');

  try
    Workflow := TWorkflowDefinition.Create;
    Workflow.LoadFromJSON(JsonObj);
    RegisterWorkflow(Workflow);
  finally
    JsonObj.Free;
  end;
end;

procedure TSimpleWorkflowRegistry.UnregisterWorkflow(const AWorkflowId: string);
begin
  FLock.Enter;
  try
    FWorkflows.Remove(AWorkflowId);
  finally
    FLock.Leave;
  end;
end;

function TSimpleWorkflowRegistry.GetWorkflow(const AWorkflowId: string): TWorkflowDefinition;
begin
  FLock.Enter;
  try
    if not FWorkflows.TryGetValue(AWorkflowId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TSimpleWorkflowRegistry.WorkflowExists(const AWorkflowId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FWorkflows.ContainsKey(AWorkflowId);
  finally
    FLock.Leave;
  end;
end;

function TSimpleWorkflowRegistry.GetAllWorkflowIds: TArray<string>;
var
  IdList: TList<string>;
  Id: string;
begin
  IdList := TList<string>.Create;
  try
    FLock.Enter;
    try
      for Id in FWorkflows.Keys do
        IdList.Add(Id);
    finally
      FLock.Leave;
    end;
    Result := IdList.ToArray;
  finally
    IdList.Free;
  end;
end;

end.
