(*******************************************************************************
                                                                               
  UniFlow Skill Types                                                          
  Type definitions for Skill service integration                               
                                                                               
  Features:                                                                    
  - Skill request/response types                                               
  - Skill metadata types                                                       
  - LLM message types                                                          
  - Status and error types                                                     
                                                                               
*******************************************************************************)

unit UniFlow.Skill.Types;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  System.JSON;

type
  //----------------------------------------------------------------------------
  // Enums
  //----------------------------------------------------------------------------

  /// <summary>Skill execution status</summary>
  TSkillStatus = (
    ssSuccess,
    ssError,
    ssTimeout,
    ssCancelled,
    ssPending
  );

  /// <summary>Skill category</summary>
  TSkillCategory = (
    scCode,
    scLLM,
    scData,
    scIO,
    scUtility,
    scCustom
  );

  //----------------------------------------------------------------------------
  // Helper functions
  //----------------------------------------------------------------------------

  TSkillStatusHelper = record helper for TSkillStatus
    function ToString: string;
    class function FromString(const AValue: string): TSkillStatus; static;
  end;

  TSkillCategoryHelper = record helper for TSkillCategory
    function ToString: string;
    class function FromString(const AValue: string): TSkillCategory; static;
  end;

  //----------------------------------------------------------------------------
  // Forward declarations
  //----------------------------------------------------------------------------

type
  TSkillParameter = class;
  TSkillInfo = class;
  TSkillRequest = class;
  TSkillResponse = class;
  TLLMMessage = class;
  TLLMRequest = class;
  TLLMResponse = class;
  TLLMUsage = class;

  //----------------------------------------------------------------------------
  // TSkillParameter - Skill parameter definition
  //----------------------------------------------------------------------------

  TSkillParameter = class
  private
    FName: string;
    FParamType: string;
    FDescription: string;
    FRequired: Boolean;
    FDefault: TValue;
  public
    constructor Create; overload;
    constructor Create(const AName, AType, ADescription: string;
      ARequired: Boolean = True); overload;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TSkillParameter; static;

    property Name: string read FName write FName;
    property ParamType: string read FParamType write FParamType;
    property Description: string read FDescription write FDescription;
    property Required: Boolean read FRequired write FRequired;
    property DefaultValue: TValue read FDefault write FDefault;
  end;

  //----------------------------------------------------------------------------
  // TSkillInfo - Skill metadata
  //----------------------------------------------------------------------------

  TSkillInfo = class
  private
    FName: string;
    FDescription: string;
    FVersion: string;
    FCategory: TSkillCategory;
    FParameters: TObjectList<TSkillParameter>;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TSkillInfo; static;

    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property Version: string read FVersion write FVersion;
    property Category: TSkillCategory read FCategory write FCategory;
    property Parameters: TObjectList<TSkillParameter> read FParameters;
  end;

  //----------------------------------------------------------------------------
  // TSkillRequest - Request to execute a Skill
  //----------------------------------------------------------------------------

  TSkillRequest = class
  private
    FSkillName: string;
    FParams: TJSONObject;
    FContext: TJSONObject;
    FTimeoutMs: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TSkillRequest; static;

    /// <summary>Set a parameter value</summary>
    procedure SetParam(const AName: string; const AValue: TValue);
    procedure SetParamStr(const AName, AValue: string);
    procedure SetParamInt(const AName: string; AValue: Integer);
    procedure SetParamBool(const AName: string; AValue: Boolean);
    procedure SetParamFloat(const AName: string; AValue: Double);
    procedure SetParamJSON(const AName: string; AValue: TJSONValue);

    property SkillName: string read FSkillName write FSkillName;
    property Params: TJSONObject read FParams;
    property Context: TJSONObject read FContext;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
  end;

  //----------------------------------------------------------------------------
  // TSkillResponse - Response from Skill execution
  //----------------------------------------------------------------------------

  TSkillResponse = class
  private
    FSkillName: string;
    FStatus: TSkillStatus;
    FResult: TJSONValue;
    FError: string;
    FExecutionTimeMs: Integer;
    FTimestamp: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TSkillResponse; static;

    /// <summary>Check if execution was successful</summary>
    function IsSuccess: Boolean;

    /// <summary>Get result as specific type</summary>
    function GetResultStr: string;
    function GetResultInt: Integer;
    function GetResultBool: Boolean;
    function GetResultFloat: Double;
    function GetResultJSON: TJSONValue;

    property SkillName: string read FSkillName write FSkillName;
    property Status: TSkillStatus read FStatus write FStatus;
    property Result: TJSONValue read FResult write FResult;
    property Error: string read FError write FError;
    property ExecutionTimeMs: Integer read FExecutionTimeMs write FExecutionTimeMs;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
  end;

  //----------------------------------------------------------------------------
  // TLLMMessage - Chat message for LLM
  //----------------------------------------------------------------------------

  TLLMRole = (lrSystem, lrUser, lrAssistant, lrFunction);

  TLLMRoleHelper = record helper for TLLMRole
    function ToString: string;
    class function FromString(const AValue: string): TLLMRole; static;
  end;

  TLLMMessage = class
  private
    FRole: TLLMRole;
    FContent: string;
    FName: string;
  public
    constructor Create; overload;
    constructor Create(ARole: TLLMRole; const AContent: string); overload;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TLLMMessage; static;

    class function System(const AContent: string): TLLMMessage; static;
    class function User(const AContent: string): TLLMMessage; static;
    class function Assistant(const AContent: string): TLLMMessage; static;

    property Role: TLLMRole read FRole write FRole;
    property Content: string read FContent write FContent;
    property Name: string read FName write FName;
  end;

  //----------------------------------------------------------------------------
  // TLLMUsage - Token usage statistics
  //----------------------------------------------------------------------------

  TLLMUsage = class
  private
    FPromptTokens: Integer;
    FCompletionTokens: Integer;
    FTotalTokens: Integer;
  public
    constructor Create;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TLLMUsage; static;

    property PromptTokens: Integer read FPromptTokens write FPromptTokens;
    property CompletionTokens: Integer read FCompletionTokens write FCompletionTokens;
    property TotalTokens: Integer read FTotalTokens write FTotalTokens;
  end;

  //----------------------------------------------------------------------------
  // TLLMRequest - Request for LLM chat completion
  //----------------------------------------------------------------------------

  TLLMRequest = class
  private
    FModel: string;
    FMessages: TObjectList<TLLMMessage>;
    FTemperature: Double;
    FMaxTokens: Integer;
    FStream: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TLLMRequest; static;

    /// <summary>Add a message to the conversation</summary>
    procedure AddMessage(AMessage: TLLMMessage); overload;
    procedure AddMessage(ARole: TLLMRole; const AContent: string); overload;
    procedure AddSystemMessage(const AContent: string);
    procedure AddUserMessage(const AContent: string);
    procedure AddAssistantMessage(const AContent: string);

    property Model: string read FModel write FModel;
    property Messages: TObjectList<TLLMMessage> read FMessages;
    property Temperature: Double read FTemperature write FTemperature;
    property MaxTokens: Integer read FMaxTokens write FMaxTokens;
    property Stream: Boolean read FStream write FStream;
  end;

  //----------------------------------------------------------------------------
  // TLLMResponse - Response from LLM chat completion
  //----------------------------------------------------------------------------

  TLLMResponse = class
  private
    FContent: string;
    FModel: string;
    FUsage: TLLMUsage;
    FFinishReason: string;
  public
    constructor Create;
    destructor Destroy; override;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): TLLMResponse; static;

    property Content: string read FContent write FContent;
    property Model: string read FModel write FModel;
    property Usage: TLLMUsage read FUsage;
    property FinishReason: string read FFinishReason write FFinishReason;
  end;

  //----------------------------------------------------------------------------
  // THealthResponse - Health check response
  //----------------------------------------------------------------------------

  THealthResponse = class
  private
    FStatus: string;
    FVersion: string;
    FEnvironment: string;
    FTimestamp: TDateTime;
    FSkillsLoaded: Integer;
  public
    constructor Create;

    function ToJSON: TJSONObject;
    class function FromJSON(const AJSON: TJSONObject): THealthResponse; static;

    function IsHealthy: Boolean;

    property Status: string read FStatus write FStatus;
    property Version: string read FVersion write FVersion;
    property Environment: string read FEnvironment write FEnvironment;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property SkillsLoaded: Integer read FSkillsLoaded write FSkillsLoaded;
  end;

  //----------------------------------------------------------------------------
  // Exceptions
  //----------------------------------------------------------------------------

  ESkillException = class(Exception);
  ESkillNotFound = class(ESkillException);
  ESkillTimeout = class(ESkillException);
  ESkillConnectionError = class(ESkillException);
  ESkillValidationError = class(ESkillException);

implementation

uses
  System.DateUtils;

//------------------------------------------------------------------------------
// TSkillStatusHelper
//------------------------------------------------------------------------------

function TSkillStatusHelper.ToString: string;
begin
  case Self of
    ssSuccess:   Result := 'success';
    ssError:     Result := 'error';
    ssTimeout:   Result := 'timeout';
    ssCancelled: Result := 'cancelled';
    ssPending:   Result := 'pending';
  else
    Result := 'unknown';
  end;
end;

class function TSkillStatusHelper.FromString(const AValue: string): TSkillStatus;
begin
  if AValue = 'success' then
    Result := ssSuccess
  else if AValue = 'error' then
    Result := ssError
  else if AValue = 'timeout' then
    Result := ssTimeout
  else if AValue = 'cancelled' then
    Result := ssCancelled
  else if AValue = 'pending' then
    Result := ssPending
  else
    Result := ssError;
end;

//------------------------------------------------------------------------------
// TSkillCategoryHelper
//------------------------------------------------------------------------------

function TSkillCategoryHelper.ToString: string;
begin
  case Self of
    scCode:    Result := 'code';
    scLLM:     Result := 'llm';
    scData:    Result := 'data';
    scIO:      Result := 'io';
    scUtility: Result := 'utility';
    scCustom:  Result := 'custom';
  else
    Result := 'custom';
  end;
end;

class function TSkillCategoryHelper.FromString(const AValue: string): TSkillCategory;
begin
  if AValue = 'code' then
    Result := scCode
  else if AValue = 'llm' then
    Result := scLLM
  else if AValue = 'data' then
    Result := scData
  else if AValue = 'io' then
    Result := scIO
  else if AValue = 'utility' then
    Result := scUtility
  else
    Result := scCustom;
end;

//------------------------------------------------------------------------------
// TLLMRoleHelper
//------------------------------------------------------------------------------

function TLLMRoleHelper.ToString: string;
begin
  case Self of
    lrSystem:    Result := 'system';
    lrUser:      Result := 'user';
    lrAssistant: Result := 'assistant';
    lrFunction:  Result := 'function';
  else
    Result := 'user';
  end;
end;

class function TLLMRoleHelper.FromString(const AValue: string): TLLMRole;
begin
  if AValue = 'system' then
    Result := lrSystem
  else if AValue = 'user' then
    Result := lrUser
  else if AValue = 'assistant' then
    Result := lrAssistant
  else if AValue = 'function' then
    Result := lrFunction
  else
    Result := lrUser;
end;

//------------------------------------------------------------------------------
// TSkillParameter
//------------------------------------------------------------------------------

constructor TSkillParameter.Create;
begin
  inherited Create;
  FRequired := True;
end;

constructor TSkillParameter.Create(const AName, AType, ADescription: string;
  ARequired: Boolean);
begin
  Create;
  FName := AName;
  FParamType := AType;
  FDescription := ADescription;
  FRequired := ARequired;
end;

destructor TSkillParameter.Destroy;
begin
  inherited Destroy;
end;

function TSkillParameter.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('type', FParamType);
  Result.AddPair('description', FDescription);
  Result.AddPair('required', TJSONBool.Create(FRequired));
end;

class function TSkillParameter.FromJSON(const AJSON: TJSONObject): TSkillParameter;
begin
  Result := TSkillParameter.Create;
  Result.Name := AJSON.GetValue<string>('name', '');
  Result.ParamType := AJSON.GetValue<string>('type', 'string');
  Result.Description := AJSON.GetValue<string>('description', '');
  Result.Required := AJSON.GetValue<Boolean>('required', True);
end;

//------------------------------------------------------------------------------
// TSkillInfo
//------------------------------------------------------------------------------

constructor TSkillInfo.Create;
begin
  inherited Create;
  FParameters := TObjectList<TSkillParameter>.Create(True);
  FVersion := '1.0.0';
  FCategory := scCustom;
end;

destructor TSkillInfo.Destroy;
begin
  FParameters.Free;
  inherited Destroy;
end;

function TSkillInfo.ToJSON: TJSONObject;
var
  ParamsArray: TJSONArray;
  Param: TSkillParameter;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', FName);
  Result.AddPair('description', FDescription);
  Result.AddPair('version', FVersion);
  Result.AddPair('category', FCategory.ToString);

  ParamsArray := TJSONArray.Create;
  for Param in FParameters do
    ParamsArray.Add(Param.ToJSON);
  Result.AddPair('parameters', ParamsArray);
end;

class function TSkillInfo.FromJSON(const AJSON: TJSONObject): TSkillInfo;
var
  ParamsArray: TJSONArray;
  I: Integer;
begin
  Result := TSkillInfo.Create;
  Result.Name := AJSON.GetValue<string>('name', '');
  Result.Description := AJSON.GetValue<string>('description', '');
  Result.Version := AJSON.GetValue<string>('version', '1.0.0');
  Result.Category := TSkillCategory.FromString(AJSON.GetValue<string>('category', 'custom'));

  if AJSON.TryGetValue<TJSONArray>('parameters', ParamsArray) then
  begin
    for I := 0 to ParamsArray.Count - 1 do
      Result.Parameters.Add(TSkillParameter.FromJSON(ParamsArray.Items[I] as TJSONObject));
  end;
end;

//------------------------------------------------------------------------------
// TSkillRequest
//------------------------------------------------------------------------------

constructor TSkillRequest.Create;
begin
  inherited Create;
  FParams := TJSONObject.Create;
  FContext := TJSONObject.Create;
  FTimeoutMs := 30000;  // Default 30 seconds
end;

destructor TSkillRequest.Destroy;
begin
  FParams.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure TSkillRequest.SetParam(const AName: string; const AValue: TValue);
begin
  case AValue.Kind of
    tkInteger, tkInt64:
      SetParamInt(AName, AValue.AsInteger);
    tkFloat:
      SetParamFloat(AName, AValue.AsExtended);
    tkString, tkUString, tkWString, tkLString:
      SetParamStr(AName, AValue.AsString);
    tkEnumeration:
      if AValue.TypeInfo = TypeInfo(Boolean) then
        SetParamBool(AName, AValue.AsBoolean)
      else
        SetParamStr(AName, AValue.ToString);
  else
    SetParamStr(AName, AValue.ToString);
  end;
end;

procedure TSkillRequest.SetParamStr(const AName, AValue: string);
begin
  FParams.RemovePair(AName);
  FParams.AddPair(AName, AValue);
end;

procedure TSkillRequest.SetParamInt(const AName: string; AValue: Integer);
begin
  FParams.RemovePair(AName);
  FParams.AddPair(AName, TJSONNumber.Create(AValue));
end;

procedure TSkillRequest.SetParamBool(const AName: string; AValue: Boolean);
begin
  FParams.RemovePair(AName);
  FParams.AddPair(AName, TJSONBool.Create(AValue));
end;

procedure TSkillRequest.SetParamFloat(const AName: string; AValue: Double);
begin
  FParams.RemovePair(AName);
  FParams.AddPair(AName, TJSONNumber.Create(AValue));
end;

procedure TSkillRequest.SetParamJSON(const AName: string; AValue: TJSONValue);
begin
  FParams.RemovePair(AName);
  FParams.AddPair(AName, AValue.Clone as TJSONValue);
end;

function TSkillRequest.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('skill_name', FSkillName);
  Result.AddPair('params', FParams.Clone as TJSONObject);
  Result.AddPair('context', FContext.Clone as TJSONObject);
  Result.AddPair('timeout_ms', TJSONNumber.Create(FTimeoutMs));
end;

class function TSkillRequest.FromJSON(const AJSON: TJSONObject): TSkillRequest;
var
  ParamsObj, ContextObj: TJSONObject;
begin
  Result := TSkillRequest.Create;
  Result.SkillName := AJSON.GetValue<string>('skill_name', '');
  Result.TimeoutMs := AJSON.GetValue<Integer>('timeout_ms', 30000);

  if AJSON.TryGetValue<TJSONObject>('params', ParamsObj) then
  begin
    Result.FParams.Free;
    Result.FParams := ParamsObj.Clone as TJSONObject;
  end;

  if AJSON.TryGetValue<TJSONObject>('context', ContextObj) then
  begin
    Result.FContext.Free;
    Result.FContext := ContextObj.Clone as TJSONObject;
  end;
end;

//------------------------------------------------------------------------------
// TSkillResponse
//------------------------------------------------------------------------------

constructor TSkillResponse.Create;
begin
  inherited Create;
  FStatus := ssPending;
  FTimestamp := Now;
end;

destructor TSkillResponse.Destroy;
begin
  FResult.Free;
  inherited Destroy;
end;

function TSkillResponse.IsSuccess: Boolean;
begin
  Result := FStatus = ssSuccess;
end;

function TSkillResponse.GetResultStr: string;
begin
  if Assigned(FResult) and (FResult is TJSONString) then
    Result := TJSONString(FResult).Value
  else if Assigned(FResult) then
    Result := FResult.ToString
  else
    Result := '';
end;

function TSkillResponse.GetResultInt: Integer;
begin
  if Assigned(FResult) and (FResult is TJSONNumber) then
    Result := TJSONNumber(FResult).AsInt
  else
    Result := 0;
end;

function TSkillResponse.GetResultBool: Boolean;
begin
  if Assigned(FResult) and (FResult is TJSONBool) then
    Result := TJSONBool(FResult).AsBoolean
  else
    Result := False;
end;

function TSkillResponse.GetResultFloat: Double;
begin
  if Assigned(FResult) and (FResult is TJSONNumber) then
    Result := TJSONNumber(FResult).AsDouble
  else
    Result := 0.0;
end;

function TSkillResponse.GetResultJSON: TJSONValue;
begin
  Result := FResult;
end;

function TSkillResponse.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('skill_name', FSkillName);
  Result.AddPair('status', FStatus.ToString);
  if Assigned(FResult) then
    Result.AddPair('result', FResult.Clone as TJSONValue);
  if FError <> '' then
    Result.AddPair('error', FError);
  Result.AddPair('execution_time_ms', TJSONNumber.Create(FExecutionTimeMs));
  Result.AddPair('timestamp', DateToISO8601(FTimestamp, False));
end;

class function TSkillResponse.FromJSON(const AJSON: TJSONObject): TSkillResponse;
var
  ResultValue: TJSONValue;
  TimestampStr: string;
begin
  Result := TSkillResponse.Create;
  Result.SkillName := AJSON.GetValue<string>('skill_name', '');
  Result.Status := TSkillStatus.FromString(AJSON.GetValue<string>('status', 'error'));
  Result.Error := AJSON.GetValue<string>('error', '');
  Result.ExecutionTimeMs := AJSON.GetValue<Integer>('execution_time_ms', 0);

  if AJSON.TryGetValue<TJSONValue>('result', ResultValue) then
    Result.FResult := ResultValue.Clone as TJSONValue;

  TimestampStr := AJSON.GetValue<string>('timestamp', '');
  if TimestampStr <> '' then
    Result.Timestamp := ISO8601ToDate(TimestampStr, False)
  else
    Result.Timestamp := Now;
end;

//------------------------------------------------------------------------------
// TLLMMessage
//------------------------------------------------------------------------------

constructor TLLMMessage.Create;
begin
  inherited Create;
  FRole := lrUser;
end;

constructor TLLMMessage.Create(ARole: TLLMRole; const AContent: string);
begin
  Create;
  FRole := ARole;
  FContent := AContent;
end;

destructor TLLMMessage.Destroy;
begin
  inherited Destroy;
end;

class function TLLMMessage.System(const AContent: string): TLLMMessage;
begin
  Result := TLLMMessage.Create(lrSystem, AContent);
end;

class function TLLMMessage.User(const AContent: string): TLLMMessage;
begin
  Result := TLLMMessage.Create(lrUser, AContent);
end;

class function TLLMMessage.Assistant(const AContent: string): TLLMMessage;
begin
  Result := TLLMMessage.Create(lrAssistant, AContent);
end;

function TLLMMessage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('role', FRole.ToString);
  Result.AddPair('content', FContent);
  if FName <> '' then
    Result.AddPair('name', FName);
end;

class function TLLMMessage.FromJSON(const AJSON: TJSONObject): TLLMMessage;
begin
  Result := TLLMMessage.Create;
  Result.Role := TLLMRole.FromString(AJSON.GetValue<string>('role', 'user'));
  Result.Content := AJSON.GetValue<string>('content', '');
  Result.Name := AJSON.GetValue<string>('name', '');
end;

//------------------------------------------------------------------------------
// TLLMUsage
//------------------------------------------------------------------------------

constructor TLLMUsage.Create;
begin
  inherited Create;
end;

function TLLMUsage.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('prompt_tokens', TJSONNumber.Create(FPromptTokens));
  Result.AddPair('completion_tokens', TJSONNumber.Create(FCompletionTokens));
  Result.AddPair('total_tokens', TJSONNumber.Create(FTotalTokens));
end;

class function TLLMUsage.FromJSON(const AJSON: TJSONObject): TLLMUsage;
begin
  Result := TLLMUsage.Create;
  Result.PromptTokens := AJSON.GetValue<Integer>('prompt_tokens', 0);
  Result.CompletionTokens := AJSON.GetValue<Integer>('completion_tokens', 0);
  Result.TotalTokens := AJSON.GetValue<Integer>('total_tokens', 0);
end;

//------------------------------------------------------------------------------
// TLLMRequest
//------------------------------------------------------------------------------

constructor TLLMRequest.Create;
begin
  inherited Create;
  FMessages := TObjectList<TLLMMessage>.Create(True);
  FModel := 'gpt-4o-mini';
  FTemperature := 0.7;
  FMaxTokens := 4096;
  FStream := False;
end;

destructor TLLMRequest.Destroy;
begin
  FMessages.Free;
  inherited Destroy;
end;

procedure TLLMRequest.AddMessage(AMessage: TLLMMessage);
begin
  FMessages.Add(AMessage);
end;

procedure TLLMRequest.AddMessage(ARole: TLLMRole; const AContent: string);
begin
  AddMessage(TLLMMessage.Create(ARole, AContent));
end;

procedure TLLMRequest.AddSystemMessage(const AContent: string);
begin
  AddMessage(lrSystem, AContent);
end;

procedure TLLMRequest.AddUserMessage(const AContent: string);
begin
  AddMessage(lrUser, AContent);
end;

procedure TLLMRequest.AddAssistantMessage(const AContent: string);
begin
  AddMessage(lrAssistant, AContent);
end;

function TLLMRequest.ToJSON: TJSONObject;
var
  MsgArray: TJSONArray;
  Msg: TLLMMessage;
begin
  Result := TJSONObject.Create;
  Result.AddPair('model', FModel);
  Result.AddPair('temperature', TJSONNumber.Create(FTemperature));
  Result.AddPair('max_tokens', TJSONNumber.Create(FMaxTokens));
  Result.AddPair('stream', TJSONBool.Create(FStream));

  MsgArray := TJSONArray.Create;
  for Msg in FMessages do
    MsgArray.Add(Msg.ToJSON);
  Result.AddPair('messages', MsgArray);
end;

class function TLLMRequest.FromJSON(const AJSON: TJSONObject): TLLMRequest;
var
  MsgArray: TJSONArray;
  I: Integer;
begin
  Result := TLLMRequest.Create;
  Result.Model := AJSON.GetValue<string>('model', 'gpt-4o-mini');
  Result.Temperature := AJSON.GetValue<Double>('temperature', 0.7);
  Result.MaxTokens := AJSON.GetValue<Integer>('max_tokens', 4096);
  Result.Stream := AJSON.GetValue<Boolean>('stream', False);

  if AJSON.TryGetValue<TJSONArray>('messages', MsgArray) then
  begin
    for I := 0 to MsgArray.Count - 1 do
      Result.Messages.Add(TLLMMessage.FromJSON(MsgArray.Items[I] as TJSONObject));
  end;
end;

//------------------------------------------------------------------------------
// TLLMResponse
//------------------------------------------------------------------------------

constructor TLLMResponse.Create;
begin
  inherited Create;
  FUsage := TLLMUsage.Create;
  FFinishReason := 'stop';
end;

destructor TLLMResponse.Destroy;
begin
  FUsage.Free;
  inherited Destroy;
end;

function TLLMResponse.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('content', FContent);
  Result.AddPair('model', FModel);
  Result.AddPair('usage', FUsage.ToJSON);
  Result.AddPair('finish_reason', FFinishReason);
end;

class function TLLMResponse.FromJSON(const AJSON: TJSONObject): TLLMResponse;
var
  UsageObj: TJSONObject;
begin
  Result := TLLMResponse.Create;
  Result.Content := AJSON.GetValue<string>('content', '');
  Result.Model := AJSON.GetValue<string>('model', '');
  Result.FinishReason := AJSON.GetValue<string>('finish_reason', 'stop');

  if AJSON.TryGetValue<TJSONObject>('usage', UsageObj) then
  begin
    Result.FUsage.Free;
    Result.FUsage := TLLMUsage.FromJSON(UsageObj);
  end;
end;

//------------------------------------------------------------------------------
// THealthResponse
//------------------------------------------------------------------------------

constructor THealthResponse.Create;
begin
  inherited Create;
  FStatus := 'unknown';
  FTimestamp := Now;
end;

function THealthResponse.IsHealthy: Boolean;
begin
  Result := SameText(FStatus, 'healthy');
end;

function THealthResponse.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', FStatus);
  Result.AddPair('version', FVersion);
  Result.AddPair('environment', FEnvironment);
  Result.AddPair('timestamp', DateToISO8601(FTimestamp, False));
  Result.AddPair('skills_loaded', TJSONNumber.Create(FSkillsLoaded));
end;

class function THealthResponse.FromJSON(const AJSON: TJSONObject): THealthResponse;
var
  TimestampStr: string;
begin
  Result := THealthResponse.Create;
  Result.Status := AJSON.GetValue<string>('status', 'unknown');
  Result.Version := AJSON.GetValue<string>('version', '');
  Result.Environment := AJSON.GetValue<string>('environment', '');
  Result.SkillsLoaded := AJSON.GetValue<Integer>('skills_loaded', 0);

  TimestampStr := AJSON.GetValue<string>('timestamp', '');
  if TimestampStr <> '' then
    Result.Timestamp := ISO8601ToDate(TimestampStr, False)
  else
    Result.Timestamp := Now;
end;

end.
