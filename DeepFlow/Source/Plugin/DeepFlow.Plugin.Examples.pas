(*******************************************************************************
                                                                               
  UniFlow Plugin Examples                                                      
  Example plugins demonstrating how to create custom extensions                
                                                                               
  Features:                                                                    
  - TCustomActionPlugin: Custom action executor example                        
    - 'delay' action: Delays execution for specified milliseconds              
    - 'email' action: Mock email sending                                       
  - TCustomValidatorPlugin: Custom validator example                           
    - 'china_phone': Chinese mobile phone number validation                    
    - 'id_card': Chinese ID card number validation                             
                                                                               
  Usage:                                                                       
  To export as BPL plugin, add this function to your package:                  
                                                                               
    function GetUniFlowPlugin: IUniFlowPlugin; stdcall;                        
    begin                                                                      
      Result := TCustomActionsPlugin.Create;                                   
    end;                                                                       
                                                                               
    exports                                                                    
      GetUniFlowPlugin;                                                        
                                                                               
*******************************************************************************)

unit UniFlow.Plugin.Examples;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.RegularExpressions,
  System.DateUtils,
  System.Generics.Collections,
  UniFlow.Plugin.Intf;

type
  //============================================================================
  // Custom Action Executors
  //============================================================================
  
  /// <summary>Delay action executor - delays execution for specified time</summary>
  TDelayActionExecutor = class(TInterfacedObject, IPluginActionExecutor)
  private
    FInfo: TActionExecutorInfo;
  public
    constructor Create;
    
    // IPluginActionExecutor
    function GetInfo: TActionExecutorInfo;
    function CanHandle(const ActionType: string): Boolean;
    function Execute(const ActionType: string; Params: TJSONObject; 
      Context: IPluginContext): TPluginResult;
    function ValidateParams(const ActionType: string; Params: TJSONObject): TPluginResult;
  end;
  
  /// <summary>Mock email action executor</summary>
  TEmailActionExecutor = class(TInterfacedObject, IPluginActionExecutor)
  private
    FInfo: TActionExecutorInfo;
  public
    constructor Create;
    
    // IPluginActionExecutor
    function GetInfo: TActionExecutorInfo;
    function CanHandle(const ActionType: string): Boolean;
    function Execute(const ActionType: string; Params: TJSONObject; 
      Context: IPluginContext): TPluginResult;
    function ValidateParams(const ActionType: string; Params: TJSONObject): TPluginResult;
  end;
  
  /// <summary>HTTP GET action executor</summary>
  THttpGetActionExecutor = class(TInterfacedObject, IPluginActionExecutor)
  private
    FInfo: TActionExecutorInfo;
  public
    constructor Create;
    
    // IPluginActionExecutor
    function GetInfo: TActionExecutorInfo;
    function CanHandle(const ActionType: string): Boolean;
    function Execute(const ActionType: string; Params: TJSONObject; 
      Context: IPluginContext): TPluginResult;
    function ValidateParams(const ActionType: string; Params: TJSONObject): TPluginResult;
  end;
  
  //============================================================================
  // Custom Validators
  //============================================================================
  
  /// <summary>Chinese phone number validator</summary>
  TChinaPhoneValidator = class(TInterfacedObject, IPluginValidator)
  private
    FInfo: TValidatorInfo;
  public
    constructor Create;
    
    // IPluginValidator
    function GetInfo: TValidatorInfo;
    function CanHandle(const ValidatorType: string): Boolean;
    function Validate(const ValidatorType: string; Value: TJSONValue; 
      Config: TJSONObject = nil): TValidationResult;
  end;
  
  /// <summary>Chinese ID card validator</summary>
  TIDCardValidator = class(TInterfacedObject, IPluginValidator)
  private
    FInfo: TValidatorInfo;
    function ValidateIDCard(const IDNumber: string): TValidationResult;
    function CalculateChecksum(const ID17: string): Char;
  public
    constructor Create;
    
    // IPluginValidator
    function GetInfo: TValidatorInfo;
    function CanHandle(const ValidatorType: string): Boolean;
    function Validate(const ValidatorType: string; Value: TJSONValue; 
      Config: TJSONObject = nil): TValidationResult;
  end;
  
  /// <summary>Email format validator</summary>
  TEmailValidator = class(TInterfacedObject, IPluginValidator)
  private
    FInfo: TValidatorInfo;
  public
    constructor Create;
    
    // IPluginValidator
    function GetInfo: TValidatorInfo;
    function CanHandle(const ValidatorType: string): Boolean;
    function Validate(const ValidatorType: string; Value: TJSONValue; 
      Config: TJSONObject = nil): TValidationResult;
  end;
  
  //============================================================================
  // Example Plugins
  //============================================================================
  
  /// <summary>Custom Actions Plugin - provides delay and email actions</summary>
  TCustomActionsPlugin = class(TBaseUniFlowPlugin)
  public
    constructor Create;
    function Initialize(Context: IPluginContext): Boolean; override;
  end;
  
  /// <summary>Custom Validators Plugin - provides china_phone and id_card validators</summary>
  TCustomValidatorsPlugin = class(TBaseUniFlowPlugin)
  public
    constructor Create;
    function Initialize(Context: IPluginContext): Boolean; override;
  end;
  
  /// <summary>Combined Plugin - provides all custom actions and validators</summary>
  TCombinedExamplePlugin = class(TBaseUniFlowPlugin)
  public
    constructor Create;
    function Initialize(Context: IPluginContext): Boolean; override;
  end;
  
  //============================================================================
  // Helper functions
  //============================================================================
  
  /// <summary>Create a custom actions plugin instance</summary>
  function CreateCustomActionsPlugin: IUniFlowPlugin;
  /// <summary>Create a custom validators plugin instance</summary>
  function CreateCustomValidatorsPlugin: IUniFlowPlugin;
  /// <summary>Create a combined example plugin instance</summary>
  function CreateCombinedExamplePlugin: IUniFlowPlugin;

implementation

uses
  System.StrUtils,
  System.Math,
  System.Net.HttpClient,
  System.Net.URLClient;

//==============================================================================
// TDelayActionExecutor
//==============================================================================

constructor TDelayActionExecutor.Create;
begin
  inherited Create;
  FInfo := TActionExecutorInfo.Create('delay', 'Delay Execution');
  FInfo.Description := 'Delays workflow execution for specified milliseconds';
  FInfo.DefaultTimeoutMs := 60000;
  FInfo.IsAsync := False;
  
  // Parameter schema
  FInfo.ParamSchema := TJSONObject.Create;
  FInfo.ParamSchema.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  var MsObj := TJSONObject.Create;
  MsObj.AddPair('type', 'integer');
  MsObj.AddPair('minimum', TJSONNumber.Create(0));
  MsObj.AddPair('maximum', TJSONNumber.Create(60000));
  MsObj.AddPair('description', 'Delay duration in milliseconds');
  Props.AddPair('milliseconds', MsObj);
  FInfo.ParamSchema.AddPair('properties', Props);
  FInfo.ParamSchema.AddPair('required', TJSONArray.Create.Add('milliseconds'));
end;

function TDelayActionExecutor.GetInfo: TActionExecutorInfo;
begin
  Result := FInfo;
end;

function TDelayActionExecutor.CanHandle(const ActionType: string): Boolean;
begin
  Result := SameText(ActionType, 'delay');
end;

function TDelayActionExecutor.Execute(const ActionType: string; Params: TJSONObject;
  Context: IPluginContext): TPluginResult;
var
  Milliseconds: Integer;
  StartTime: TDateTime;
  Output: TJSONObject;
begin
  // Get parameters
  if not Params.TryGetValue<Integer>('milliseconds', Milliseconds) then
    Milliseconds := 1000;
  
  // Log
  if Context <> nil then
    Context.Logger.Info(Format('Delay action: waiting %d ms', [Milliseconds]));
  
  // Wait
  StartTime := Now;
  Sleep(Milliseconds);
  
  // Return result
  Output := TJSONObject.Create;
  Output.AddPair('delayed_ms', TJSONNumber.Create(Milliseconds));
  Output.AddPair('actual_ms', TJSONNumber.Create(MilliSecondsBetween(Now, StartTime)));
  
  Result := TPluginResult.OK(Output);
  Output.Free;
end;

function TDelayActionExecutor.ValidateParams(const ActionType: string; 
  Params: TJSONObject): TPluginResult;
var
  Milliseconds: Integer;
begin
  if Params = nil then
  begin
    Result := TPluginResult.Fail('INVALID_PARAMS', 'Parameters required');
    Exit;
  end;
  
  if not Params.TryGetValue<Integer>('milliseconds', Milliseconds) then
  begin
    Result := TPluginResult.Fail('MISSING_PARAM', 'milliseconds parameter required');
    Exit;
  end;
  
  if (Milliseconds < 0) or (Milliseconds > 60000) then
  begin
    Result := TPluginResult.Fail('INVALID_VALUE', 'milliseconds must be between 0 and 60000');
    Exit;
  end;
  
  Result := TPluginResult.OK;
end;

//==============================================================================
// TEmailActionExecutor
//==============================================================================

constructor TEmailActionExecutor.Create;
begin
  inherited Create;
  FInfo := TActionExecutorInfo.Create('email', 'Send Email');
  FInfo.Description := 'Sends an email (mock implementation)';
  FInfo.DefaultTimeoutMs := 30000;
  FInfo.IsAsync := False;
  
  // Parameter schema
  FInfo.ParamSchema := TJSONObject.Create;
  FInfo.ParamSchema.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  
  var ToObj := TJSONObject.Create;
  ToObj.AddPair('type', 'string');
  ToObj.AddPair('format', 'email');
  ToObj.AddPair('description', 'Recipient email address');
  Props.AddPair('to', ToObj);
  
  var SubjectObj := TJSONObject.Create;
  SubjectObj.AddPair('type', 'string');
  SubjectObj.AddPair('description', 'Email subject');
  Props.AddPair('subject', SubjectObj);
  
  var BodyObj := TJSONObject.Create;
  BodyObj.AddPair('type', 'string');
  BodyObj.AddPair('description', 'Email body');
  Props.AddPair('body', BodyObj);
  
  FInfo.ParamSchema.AddPair('properties', Props);
  FInfo.ParamSchema.AddPair('required', TJSONArray.Create.Add('to').Add('subject').Add('body'));
end;

function TEmailActionExecutor.GetInfo: TActionExecutorInfo;
begin
  Result := FInfo;
end;

function TEmailActionExecutor.CanHandle(const ActionType: string): Boolean;
begin
  Result := SameText(ActionType, 'email');
end;

function TEmailActionExecutor.Execute(const ActionType: string; Params: TJSONObject;
  Context: IPluginContext): TPluginResult;
var
  ToAddr, Subject, Body: string;
  Output: TJSONObject;
  MessageId: string;
begin
  // Get parameters
  if not Params.TryGetValue<string>('to', ToAddr) then
    ToAddr := '';
  if not Params.TryGetValue<string>('subject', Subject) then
    Subject := '';
  if not Params.TryGetValue<string>('body', Body) then
    Body := '';
  
  // Log (mock implementation)
  if Context <> nil then
    Context.Logger.Info(Format('Email action: sending to %s, subject: %s', [ToAddr, Subject]));
  
  // Generate mock message ID
  MessageId := Format('MSG-%s-%d', [FormatDateTime('yyyymmddhhnnsszzz', Now), Random(9999)]);
  
  // Mock: In real implementation, send email via SMTP
  // For demo, just return success
  
  Output := TJSONObject.Create;
  Output.AddPair('success', TJSONBool.Create(True));
  Output.AddPair('message_id', MessageId);
  Output.AddPair('to', ToAddr);
  Output.AddPair('subject', Subject);
  Output.AddPair('sent_at', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
  
  Result := TPluginResult.OK(Output);
  Output.Free;
end;

function TEmailActionExecutor.ValidateParams(const ActionType: string; 
  Params: TJSONObject): TPluginResult;
var
  ToAddr, Subject, Body: string;
begin
  if Params = nil then
  begin
    Result := TPluginResult.Fail('INVALID_PARAMS', 'Parameters required');
    Exit;
  end;
  
  if not Params.TryGetValue<string>('to', ToAddr) or ToAddr.IsEmpty then
  begin
    Result := TPluginResult.Fail('MISSING_PARAM', 'to parameter required');
    Exit;
  end;
  
  if not Params.TryGetValue<string>('subject', Subject) or Subject.IsEmpty then
  begin
    Result := TPluginResult.Fail('MISSING_PARAM', 'subject parameter required');
    Exit;
  end;
  
  if not Params.TryGetValue<string>('body', Body) then
  begin
    Result := TPluginResult.Fail('MISSING_PARAM', 'body parameter required');
    Exit;
  end;
  
  // Basic email format check
  if not TRegEx.IsMatch(ToAddr, '^[^@]+@[^@]+\.[^@]+$') then
  begin
    Result := TPluginResult.Fail('INVALID_EMAIL', 'Invalid email format');
    Exit;
  end;
  
  Result := TPluginResult.OK;
end;

//==============================================================================
// THttpGetActionExecutor
//==============================================================================

constructor THttpGetActionExecutor.Create;
begin
  inherited Create;
  FInfo := TActionExecutorInfo.Create('http_get', 'HTTP GET Request');
  FInfo.Description := 'Performs an HTTP GET request';
  FInfo.DefaultTimeoutMs := 30000;
  FInfo.IsAsync := False;
end;

function THttpGetActionExecutor.GetInfo: TActionExecutorInfo;
begin
  Result := FInfo;
end;

function THttpGetActionExecutor.CanHandle(const ActionType: string): Boolean;
begin
  Result := SameText(ActionType, 'http_get');
end;

function THttpGetActionExecutor.Execute(const ActionType: string; Params: TJSONObject;
  Context: IPluginContext): TPluginResult;
var
  URL: string;
  TimeoutMs: Integer;
  Client: THTTPClient;
  Response: IHTTPResponse;
  Output: TJSONObject;
begin
  // Get parameters
  if not Params.TryGetValue<string>('url', URL) then
  begin
    Result := TPluginResult.Fail('MISSING_PARAM', 'url parameter required');
    Exit;
  end;
  
  if not Params.TryGetValue<Integer>('timeout_ms', TimeoutMs) then
    TimeoutMs := 30000;
  
  if Context <> nil then
    Context.Logger.Info(Format('HTTP GET: %s', [URL]));
  
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := TimeoutMs;
    Client.ResponseTimeout := TimeoutMs;
    
    try
      Response := Client.Get(URL);
      
      Output := TJSONObject.Create;
      Output.AddPair('status_code', TJSONNumber.Create(Response.StatusCode));
      Output.AddPair('status_text', Response.StatusText);
      Output.AddPair('content_type', Response.ContentType);
      Output.AddPair('body', Response.ContentAsString);
      
      if Response.StatusCode >= 400 then
        Result := TPluginResult.Fail('HTTP_ERROR', Format('HTTP %d: %s', 
          [Response.StatusCode, Response.StatusText]))
      else
        Result := TPluginResult.OK(Output);
      
      Output.Free;
    except
      on E: Exception do
        Result := TPluginResult.Fail('HTTP_EXCEPTION', E.Message);
    end;
  finally
    Client.Free;
  end;
end;

function THttpGetActionExecutor.ValidateParams(const ActionType: string; 
  Params: TJSONObject): TPluginResult;
var
  URL: string;
begin
  if Params = nil then
  begin
    Result := TPluginResult.Fail('INVALID_PARAMS', 'Parameters required');
    Exit;
  end;
  
  if not Params.TryGetValue<string>('url', URL) or URL.IsEmpty then
  begin
    Result := TPluginResult.Fail('MISSING_PARAM', 'url parameter required');
    Exit;
  end;
  
  if not (URL.StartsWith('http://') or URL.StartsWith('https://')) then
  begin
    Result := TPluginResult.Fail('INVALID_URL', 'URL must start with http:// or https://');
    Exit;
  end;
  
  Result := TPluginResult.OK;
end;

//==============================================================================
// TChinaPhoneValidator
//==============================================================================

constructor TChinaPhoneValidator.Create;
begin
  inherited Create;
  FInfo := TValidatorInfo.Create('china_phone', 'Chinese Phone Number');
  FInfo.Description := 'Validates Chinese mobile phone numbers (11 digits starting with 1)';
end;

function TChinaPhoneValidator.GetInfo: TValidatorInfo;
begin
  Result := FInfo;
end;

function TChinaPhoneValidator.CanHandle(const ValidatorType: string): Boolean;
begin
  Result := SameText(ValidatorType, 'china_phone');
end;

function TChinaPhoneValidator.Validate(const ValidatorType: string; Value: TJSONValue;
  Config: TJSONObject): TValidationResult;
var
  Phone: string;
  StrictMode: Boolean;
begin
  // Get value
  if Value is TJSONString then
    Phone := TJSONString(Value).Value
  else if Value is TJSONNumber then
    Phone := TJSONNumber(Value).ToString
  else
  begin
    Result := TValidationResult.InvalidSingle('Value must be a string or number');
    Exit;
  end;
  
  // Remove spaces and dashes
  Phone := StringReplace(Phone, ' ', '', [rfReplaceAll]);
  Phone := StringReplace(Phone, '-', '', [rfReplaceAll]);
  
  // Check strict mode
  StrictMode := False;
  if Config <> nil then
    Config.TryGetValue<Boolean>('strict', StrictMode);
  
  // Basic validation: 11 digits starting with 1
  if Length(Phone) <> 11 then
  begin
    Result := TValidationResult.InvalidSingle('Phone number must be 11 digits');
    Exit;
  end;
  
  if Phone[1] <> '1' then
  begin
    Result := TValidationResult.InvalidSingle('Phone number must start with 1');
    Exit;
  end;
  
  if not TRegEx.IsMatch(Phone, '^\d{11}$') then
  begin
    Result := TValidationResult.InvalidSingle('Phone number must contain only digits');
    Exit;
  end;
  
  // Strict mode: check carrier prefix
  if StrictMode then
  begin
    // Common Chinese mobile prefixes
    // China Mobile: 134-139, 147, 150-152, 157-159, 178, 182-184, 187-188
    // China Unicom: 130-132, 145, 155-156, 166, 175-176, 185-186
    // China Telecom: 133, 149, 153, 173-174, 177, 180-181, 189, 199
    var Prefix := Copy(Phone, 1, 3);
    var ValidPrefixes := '130,131,132,133,134,135,136,137,138,139,' +
      '145,147,149,150,151,152,153,155,156,157,158,159,' +
      '166,170,171,173,174,175,176,177,178,180,181,182,183,184,185,186,187,188,189,' +
      '191,199';
    if Pos(Prefix, ValidPrefixes) = 0 then
    begin
      Result := TValidationResult.InvalidSingle('Invalid carrier prefix: ' + Prefix);
      Exit;
    end;
  end;
  
  Result := TValidationResult.Valid;
end;

//==============================================================================
// TIDCardValidator
//==============================================================================

constructor TIDCardValidator.Create;
begin
  inherited Create;
  FInfo := TValidatorInfo.Create('id_card', 'Chinese ID Card');
  FInfo.Description := 'Validates Chinese ID card numbers (18 digits with checksum)';
end;

function TIDCardValidator.GetInfo: TValidatorInfo;
begin
  Result := FInfo;
end;

function TIDCardValidator.CanHandle(const ValidatorType: string): Boolean;
begin
  Result := SameText(ValidatorType, 'id_card');
end;

function TIDCardValidator.CalculateChecksum(const ID17: string): Char;
const
  // Weights for each position (1-17)
  Weights: array[0..16] of Integer = (7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2);
  // Checksum characters
  CheckChars: string = '10X98765432';
var
  Sum, I: Integer;
begin
  Sum := 0;
  for I := 0 to 16 do
    Sum := Sum + (Ord(ID17[I + 1]) - Ord('0')) * Weights[I];
  Result := CheckChars[Sum mod 11 + 1];
end;

function TIDCardValidator.ValidateIDCard(const IDNumber: string): TValidationResult;
var
  ID: string;
  Year, Month, Day: Integer;
  BirthDate: TDateTime;
begin
  ID := UpperCase(Trim(IDNumber));
  
  // Length check
  if Length(ID) <> 18 then
  begin
    Result := TValidationResult.InvalidSingle('ID card must be 18 characters');
    Exit;
  end;
  
  // First 17 digits must be numbers
  if not TRegEx.IsMatch(Copy(ID, 1, 17), '^\d{17}$') then
  begin
    Result := TValidationResult.InvalidSingle('First 17 characters must be digits');
    Exit;
  end;
  
  // Last character must be digit or X
  if not TRegEx.IsMatch(ID[18], '^[\dX]$') then
  begin
    Result := TValidationResult.InvalidSingle('Last character must be digit or X');
    Exit;
  end;
  
  // Extract and validate birth date (positions 7-14: YYYYMMDD)
  Year := StrToIntDef(Copy(ID, 7, 4), 0);
  Month := StrToIntDef(Copy(ID, 11, 2), 0);
  Day := StrToIntDef(Copy(ID, 13, 2), 0);
  
  if (Year < 1900) or (Year > YearOf(Now)) then
  begin
    Result := TValidationResult.InvalidSingle('Invalid birth year');
    Exit;
  end;
  
  if (Month < 1) or (Month > 12) then
  begin
    Result := TValidationResult.InvalidSingle('Invalid birth month');
    Exit;
  end;
  
  if (Day < 1) or (Day > 31) then
  begin
    Result := TValidationResult.InvalidSingle('Invalid birth day');
    Exit;
  end;
  
  // Try to encode as date
  try
    BirthDate := EncodeDate(Year, Month, Day);
    if BirthDate > Now then
    begin
      Result := TValidationResult.InvalidSingle('Birth date cannot be in the future');
      Exit;
    end;
  except
    Result := TValidationResult.InvalidSingle('Invalid birth date');
    Exit;
  end;
  
  // Validate checksum
  if ID[18] <> CalculateChecksum(Copy(ID, 1, 17)) then
  begin
    Result := TValidationResult.InvalidSingle('Invalid checksum');
    Exit;
  end;
  
  Result := TValidationResult.Valid;
end;

function TIDCardValidator.Validate(const ValidatorType: string; Value: TJSONValue;
  Config: TJSONObject): TValidationResult;
var
  IDNumber: string;
begin
  if Value is TJSONString then
    IDNumber := TJSONString(Value).Value
  else
  begin
    Result := TValidationResult.InvalidSingle('Value must be a string');
    Exit;
  end;
  
  Result := ValidateIDCard(IDNumber);
end;

//==============================================================================
// TEmailValidator
//==============================================================================

constructor TEmailValidator.Create;
begin
  inherited Create;
  FInfo := TValidatorInfo.Create('email', 'Email Address');
  FInfo.Description := 'Validates email address format';
end;

function TEmailValidator.GetInfo: TValidatorInfo;
begin
  Result := FInfo;
end;

function TEmailValidator.CanHandle(const ValidatorType: string): Boolean;
begin
  Result := SameText(ValidatorType, 'email');
end;

function TEmailValidator.Validate(const ValidatorType: string; Value: TJSONValue;
  Config: TJSONObject): TValidationResult;
var
  Email: string;
  AllowEmpty: Boolean;
begin
  if Value is TJSONString then
    Email := TJSONString(Value).Value
  else if Value is TJSONNull then
    Email := ''
  else
  begin
    Result := TValidationResult.InvalidSingle('Value must be a string');
    Exit;
  end;
  
  // Check allow_empty option
  AllowEmpty := False;
  if Config <> nil then
    Config.TryGetValue<Boolean>('allow_empty', AllowEmpty);
  
  if Email.IsEmpty then
  begin
    if AllowEmpty then
      Result := TValidationResult.Valid
    else
      Result := TValidationResult.InvalidSingle('Email address is required');
    Exit;
  end;
  
  // RFC 5322 simplified pattern
  if not TRegEx.IsMatch(Email, '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') then
  begin
    Result := TValidationResult.InvalidSingle('Invalid email format');
    Exit;
  end;
  
  Result := TValidationResult.Valid;
end;

//==============================================================================
// TCustomActionsPlugin
//==============================================================================

constructor TCustomActionsPlugin.Create;
begin
  inherited Create('uniflow.actions.custom', 'Custom Actions Plugin', '1.0.0');
  FInfo.Author := 'UniFlow Team';
  FInfo.Description := 'Provides custom action executors: delay, email, http_get';
end;

function TCustomActionsPlugin.Initialize(Context: IPluginContext): Boolean;
begin
  inherited Initialize(Context);
  
  // Register action executors
  RegisterActionExecutor(TDelayActionExecutor.Create);
  RegisterActionExecutor(TEmailActionExecutor.Create);
  RegisterActionExecutor(THttpGetActionExecutor.Create);
  
  if Context <> nil then
    Context.Logger.Info('Custom Actions Plugin initialized');
  
  Result := True;
end;

//==============================================================================
// TCustomValidatorsPlugin
//==============================================================================

constructor TCustomValidatorsPlugin.Create;
begin
  inherited Create('uniflow.validators.custom', 'Custom Validators Plugin', '1.0.0');
  FInfo.Author := 'UniFlow Team';
  FInfo.Description := 'Provides custom validators: china_phone, id_card, email';
end;

function TCustomValidatorsPlugin.Initialize(Context: IPluginContext): Boolean;
begin
  inherited Initialize(Context);
  
  // Register validators
  RegisterValidator(TChinaPhoneValidator.Create);
  RegisterValidator(TIDCardValidator.Create);
  RegisterValidator(TEmailValidator.Create);
  
  if Context <> nil then
    Context.Logger.Info('Custom Validators Plugin initialized');
  
  Result := True;
end;

//==============================================================================
// TCombinedExamplePlugin
//==============================================================================

constructor TCombinedExamplePlugin.Create;
begin
  inherited Create('uniflow.examples.combined', 'Combined Example Plugin', '1.0.0');
  FInfo.Author := 'UniFlow Team';
  FInfo.Description := 'Combined plugin with all custom actions and validators';
end;

function TCombinedExamplePlugin.Initialize(Context: IPluginContext): Boolean;
begin
  inherited Initialize(Context);
  
  // Register action executors
  RegisterActionExecutor(TDelayActionExecutor.Create);
  RegisterActionExecutor(TEmailActionExecutor.Create);
  RegisterActionExecutor(THttpGetActionExecutor.Create);
  
  // Register validators
  RegisterValidator(TChinaPhoneValidator.Create);
  RegisterValidator(TIDCardValidator.Create);
  RegisterValidator(TEmailValidator.Create);
  
  if Context <> nil then
    Context.Logger.Info('Combined Example Plugin initialized');
  
  Result := True;
end;

//==============================================================================
// Helper functions
//==============================================================================

function CreateCustomActionsPlugin: IUniFlowPlugin;
begin
  Result := TCustomActionsPlugin.Create;
end;

function CreateCustomValidatorsPlugin: IUniFlowPlugin;
begin
  Result := TCustomValidatorsPlugin.Create;
end;

function CreateCombinedExamplePlugin: IUniFlowPlugin;
begin
  Result := TCombinedExamplePlugin.Create;
end;

end.
