(* ============================================================================
  UniFlow.Validation.Schema - JSON Schema Validator

  Version: 1.0
  Description: Validates JSON data against JSON Schema (Draft-07 subset)

  Supported Schema Keywords:
    - type: string, number, integer, boolean, array, object, null
    - required: array of required property names
    - properties: object property schemas
    - items: array item schema
    - minLength, maxLength: string length constraints
    - minimum, maximum: number range constraints
    - pattern: regex pattern for strings
    - enum: allowed values
    - minItems, maxItems: array length constraints
    - default: default value (for documentation)

  Usage:
    var Schema := TJSONSchema.LoadFromFile('schema.json');
    var Result := Schema.Validate(JSONData);
    if not Result.IsValid then
      ShowErrors(Result.Errors);
  ============================================================================ *)

unit UniFlow.Validation.Schema;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  DeepBase.Exceptions;

type
  /// <summary>
  /// Schema validation error
  /// </summary>
  TSchemaError = record
    Path: string;       // JSON path (e.g., "user.email", "items[0].name")
    Message: string;    // Error description
    Keyword: string;    // Schema keyword that failed (e.g., "required", "type")
    ExpectedValue: string;
    ActualValue: string;

    class function Create(const APath, AMessage, AKeyword: string): TSchemaError; static;
    function ToString: string;
  end;

  /// <summary>
  /// Schema validation result
  /// </summary>
  TSchemaValidationResult = record
  private
    FErrors: TArray<TSchemaError>;
    function GetIsValid: Boolean;
  public
    procedure AddError(const Error: TSchemaError);
    procedure AddErrors(const Errors: TArray<TSchemaError>);

    property IsValid: Boolean read GetIsValid;
    property Errors: TArray<TSchemaError> read FErrors;
    function GetErrorMessages: string;
  end;

  /// <summary>
  /// JSON Schema validator
  /// </summary>
  TJSONSchema = class
  private
    FSchema: TJSONObject;
    FOwnsSchema: Boolean;

    function ValidateValue(const Value: TJSONValue; const Schema: TJSONObject;
      const Path: string): TSchemaValidationResult;
    function ValidateType(const Value: TJSONValue; const ExpectedType: string;
      const Path: string): TSchemaError;
    function ValidateString(const Value: string; const Schema: TJSONObject;
      const Path: string): TSchemaValidationResult;
    function ValidateNumber(const Value: Double; const Schema: TJSONObject;
      const Path: string): TSchemaValidationResult;
    function ValidateArray(const Value: TJSONArray; const Schema: TJSONObject;
      const Path: string): TSchemaValidationResult;
    function ValidateObject(const Value: TJSONObject; const Schema: TJSONObject;
      const Path: string): TSchemaValidationResult;
    function ValidateEnum(const Value: TJSONValue; const EnumArray: TJSONArray;
      const Path: string): TSchemaError;

    function GetJSONType(const Value: TJSONValue): string;
  public
    constructor Create(ASchema: TJSONObject; AOwnsSchema: Boolean = True);
    destructor Destroy; override;

    /// <summary>
    /// Validate JSON value against schema
    /// </summary>
    function Validate(const Value: TJSONValue): TSchemaValidationResult; overload;

    /// <summary>
    /// Validate JSON string against schema
    /// </summary>
    function Validate(const JSONString: string): TSchemaValidationResult; overload;

    /// <summary>
    /// Load schema from JSON string
    /// </summary>
    class function LoadFromString(const SchemaJSON: string): TJSONSchema;

    /// <summary>
    /// Load schema from file
    /// </summary>
    class function LoadFromFile(const FileName: string): TJSONSchema;

    /// <summary>
    /// Create schema from TJSONObject (takes ownership)
    /// </summary>
    class function FromJSON(ASchema: TJSONObject): TJSONSchema;

    property Schema: TJSONObject read FSchema;
  end;

  /// <summary>
  /// Quick validation helper
  /// </summary>
  TSchemaValidator = class
  public
    class function ValidateJSON(const JSONString, SchemaString: string): TSchemaValidationResult;
    class function ValidateJSONFile(const JSONFile, SchemaFile: string): TSchemaValidationResult;
  end;

implementation

{ TSchemaError }

class function TSchemaError.Create(const APath, AMessage, AKeyword: string): TSchemaError;
begin
  Result.Path := APath;
  Result.Message := AMessage;
  Result.Keyword := AKeyword;
  Result.ExpectedValue := '';
  Result.ActualValue := '';
end;

function TSchemaError.ToString: string;
begin
  if Path.IsEmpty then
    Result := Message
  else
    Result := Format('%s: %s', [Path, Message]);
end;

{ TSchemaValidationResult }

function TSchemaValidationResult.GetIsValid: Boolean;
begin
  Result := Length(FErrors) = 0;
end;

procedure TSchemaValidationResult.AddError(const Error: TSchemaError);
begin
  SetLength(FErrors, Length(FErrors) + 1);
  FErrors[High(FErrors)] := Error;
end;

procedure TSchemaValidationResult.AddErrors(const Errors: TArray<TSchemaError>);
var
  I, Start: Integer;
begin
  Start := Length(FErrors);
  SetLength(FErrors, Start + Length(Errors));
  for I := 0 to High(Errors) do
    FErrors[Start + I] := Errors[I];
end;

function TSchemaValidationResult.GetErrorMessages: string;
var
  SB: TStringBuilder;
  E: TSchemaError;
begin
  SB := TStringBuilder.Create;
  try
    for E in FErrors do
    begin
      if SB.Length > 0 then
        SB.AppendLine;
      SB.Append(E.ToString);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TJSONSchema }

constructor TJSONSchema.Create(ASchema: TJSONObject; AOwnsSchema: Boolean);
begin
  inherited Create;
  FSchema := ASchema;
  FOwnsSchema := AOwnsSchema;
end;

destructor TJSONSchema.Destroy;
begin
  if FOwnsSchema and Assigned(FSchema) then
    FSchema.Free;
  inherited;
end;

class function TJSONSchema.LoadFromString(const SchemaJSON: string): TJSONSchema;
var
  Schema: TJSONObject;
begin
  Schema := TJSONObject.ParseJSONValue(SchemaJSON) as TJSONObject;
  if Schema = nil then
    raise EOperationException.Create('Invalid JSON schema');
  Result := TJSONSchema.Create(Schema, True);
end;

class function TJSONSchema.LoadFromFile(const FileName: string): TJSONSchema;
var
  Content: string;
begin
  Content := TFile.ReadAllText(FileName, TEncoding.UTF8);
  Result := LoadFromString(Content);
end;

class function TJSONSchema.FromJSON(ASchema: TJSONObject): TJSONSchema;
begin
  Result := TJSONSchema.Create(ASchema, True);
end;

function TJSONSchema.Validate(const Value: TJSONValue): TSchemaValidationResult;
begin
  SetLength(Result.FErrors, 0);
  if not Assigned(FSchema) then
  begin
    Result.AddError(TSchemaError.Create('', 'Schema not loaded', 'schema'));
    Exit;
  end;
  Result := ValidateValue(Value, FSchema, '');
end;

function TJSONSchema.Validate(const JSONString: string): TSchemaValidationResult;
var
  Value: TJSONValue;
begin
  SetLength(Result.FErrors, 0);
  try
    Value := TJSONObject.ParseJSONValue(JSONString);
    if Value = nil then
    begin
      Result.AddError(TSchemaError.Create('', 'Invalid JSON', 'parse'));
      Exit;
    end;
    try
      Result := Validate(Value);
    finally
      Value.Free;
    end;
  except
    on E: Exception do
    begin
      Result.AddError(TSchemaError.Create('', 'JSON parse error: ' + E.Message, 'parse'));
    end;
  end;
end;

function TJSONSchema.GetJSONType(const Value: TJSONValue): string;
begin
  if Value = nil then
    Result := 'null'
  else if Value is TJSONNull then
    Result := 'null'
  else if Value is TJSONBool then
    Result := 'boolean'
  else if Value is TJSONNumber then
  begin
    // Check if it's an integer
    if Frac(TJSONNumber(Value).AsDouble) = 0 then
      Result := 'integer'
    else
      Result := 'number';
  end
  else if Value is TJSONString then
    Result := 'string'
  else if Value is TJSONArray then
    Result := 'array'
  else if Value is TJSONObject then
    Result := 'object'
  else
    Result := 'unknown';
end;

function TJSONSchema.ValidateValue(const Value: TJSONValue; const Schema: TJSONObject;
  const Path: string): TSchemaValidationResult;
var
  TypeValue: TJSONValue;
  TypeStr: string;
  TypeError: TSchemaError;
  EnumArray: TJSONArray;
  EnumError: TSchemaError;
begin
  SetLength(Result.FErrors, 0);

  // Check type
  if Schema.TryGetValue('type', TypeValue) then
  begin
    TypeStr := TypeValue.Value;
    TypeError := ValidateType(Value, TypeStr, Path);
    if not TypeError.Message.IsEmpty then
    begin
      Result.AddError(TypeError);
      Exit; // Type mismatch, skip further validation
    end;
  end;

  // Check enum
  if Schema.TryGetValue<TJSONArray>('enum', EnumArray) then
  begin
    EnumError := ValidateEnum(Value, EnumArray, Path);
    if not EnumError.Message.IsEmpty then
      Result.AddError(EnumError);
  end;

  // Type-specific validation
  if Value is TJSONString then
    Result.AddErrors(ValidateString(TJSONString(Value).Value, Schema, Path).Errors)
  else if Value is TJSONNumber then
    Result.AddErrors(ValidateNumber(TJSONNumber(Value).AsDouble, Schema, Path).Errors)
  else if Value is TJSONArray then
    Result.AddErrors(ValidateArray(TJSONArray(Value), Schema, Path).Errors)
  else if Value is TJSONObject then
    Result.AddErrors(ValidateObject(TJSONObject(Value), Schema, Path).Errors);
end;

function TJSONSchema.ValidateType(const Value: TJSONValue; const ExpectedType: string;
  const Path: string): TSchemaError;
var
  ActualType: string;
  IsValid: Boolean;
begin
  Result.Path := '';
  Result.Message := '';
  Result.Keyword := '';

  ActualType := GetJSONType(Value);
  IsValid := (ActualType = ExpectedType);

  // Special case: integer is also a valid number
  if not IsValid and (ExpectedType = 'number') and (ActualType = 'integer') then
    IsValid := True;

  if not IsValid then
  begin
    Result := TSchemaError.Create(Path,
      Format('Expected %s but got %s', [ExpectedType, ActualType]),
      'type');
    Result.ExpectedValue := ExpectedType;
    Result.ActualValue := ActualType;
  end;
end;

function TJSONSchema.ValidateString(const Value: string; const Schema: TJSONObject;
  const Path: string): TSchemaValidationResult;
var
  MinLen, MaxLen: Integer;
  Pattern: string;
begin
  SetLength(Result.FErrors, 0);

  // minLength
  if Schema.TryGetValue<Integer>('minLength', MinLen) then
  begin
    if Length(Value) < MinLen then
      Result.AddError(TSchemaError.Create(Path,
        Format('String length %d is less than minimum %d', [Length(Value), MinLen]),
        'minLength'));
  end;

  // maxLength
  if Schema.TryGetValue<Integer>('maxLength', MaxLen) then
  begin
    if Length(Value) > MaxLen then
      Result.AddError(TSchemaError.Create(Path,
        Format('String length %d exceeds maximum %d', [Length(Value), MaxLen]),
        'maxLength'));
  end;

  // pattern
  if Schema.TryGetValue<string>('pattern', Pattern) then
  begin
    if not TRegEx.IsMatch(Value, Pattern) then
      Result.AddError(TSchemaError.Create(Path,
        Format('String does not match pattern "%s"', [Pattern]),
        'pattern'));
  end;
end;

function TJSONSchema.ValidateNumber(const Value: Double; const Schema: TJSONObject;
  const Path: string): TSchemaValidationResult;
var
  Min, Max: Double;
begin
  SetLength(Result.FErrors, 0);

  // minimum
  if Schema.TryGetValue<Double>('minimum', Min) then
  begin
    if Value < Min then
      Result.AddError(TSchemaError.Create(Path,
        Format('Value %.2f is less than minimum %.2f', [Value, Min]),
        'minimum'));
  end;

  // maximum
  if Schema.TryGetValue<Double>('maximum', Max) then
  begin
    if Value > Max then
      Result.AddError(TSchemaError.Create(Path,
        Format('Value %.2f exceeds maximum %.2f', [Value, Max]),
        'maximum'));
  end;
end;

function TJSONSchema.ValidateArray(const Value: TJSONArray; const Schema: TJSONObject;
  const Path: string): TSchemaValidationResult;
var
  MinItems, MaxItems, I: Integer;
  ItemsSchema: TJSONObject;
  ItemPath: string;
begin
  SetLength(Result.FErrors, 0);

  // minItems
  if Schema.TryGetValue<Integer>('minItems', MinItems) then
  begin
    if Value.Count < MinItems then
      Result.AddError(TSchemaError.Create(Path,
        Format('Array has %d items, minimum is %d', [Value.Count, MinItems]),
        'minItems'));
  end;

  // maxItems
  if Schema.TryGetValue<Integer>('maxItems', MaxItems) then
  begin
    if Value.Count > MaxItems then
      Result.AddError(TSchemaError.Create(Path,
        Format('Array has %d items, maximum is %d', [Value.Count, MaxItems]),
        'maxItems'));
  end;

  // items - validate each item against schema
  if Schema.TryGetValue<TJSONObject>('items', ItemsSchema) then
  begin
    for I := 0 to Value.Count - 1 do
    begin
      if Path.IsEmpty then
        ItemPath := Format('[%d]', [I])
      else
        ItemPath := Format('%s[%d]', [Path, I]);
      Result.AddErrors(ValidateValue(Value.Items[I], ItemsSchema, ItemPath).Errors);
    end;
  end;
end;

function TJSONSchema.ValidateObject(const Value: TJSONObject; const Schema: TJSONObject;
  const Path: string): TSchemaValidationResult;
var
  RequiredArray: TJSONArray;
  PropertiesObj, PropSchema: TJSONObject;
  PropName, PropPath: string;
  I: Integer;
  PropValue: TJSONValue;
begin
  SetLength(Result.FErrors, 0);

  // required - check all required properties exist
  if Schema.TryGetValue<TJSONArray>('required', RequiredArray) then
  begin
    for I := 0 to RequiredArray.Count - 1 do
    begin
      PropName := RequiredArray.Items[I].Value;
      if Value.GetValue(PropName) = nil then
      begin
        if Path.IsEmpty then
          PropPath := PropName
        else
          PropPath := Path + '.' + PropName;
        Result.AddError(TSchemaError.Create(PropPath,
          Format('Required property "%s" is missing', [PropName]),
          'required'));
      end;
    end;
  end;

  // properties - validate each property against its schema
  if Schema.TryGetValue<TJSONObject>('properties', PropertiesObj) then
  begin
    for I := 0 to PropertiesObj.Count - 1 do
    begin
      PropName := PropertiesObj.Pairs[I].JsonString.Value;
      PropValue := Value.GetValue(PropName);

      if Assigned(PropValue) then
      begin
        PropSchema := PropertiesObj.Pairs[I].JsonValue as TJSONObject;
        if Path.IsEmpty then
          PropPath := PropName
        else
          PropPath := Path + '.' + PropName;
        Result.AddErrors(ValidateValue(PropValue, PropSchema, PropPath).Errors);
      end;
    end;
  end;
end;

function TJSONSchema.ValidateEnum(const Value: TJSONValue; const EnumArray: TJSONArray;
  const Path: string): TSchemaError;
var
  I: Integer;
  Found: Boolean;
  EnumStr: string;
begin
  Result.Path := '';
  Result.Message := '';
  Result.Keyword := '';

  Found := False;
  for I := 0 to EnumArray.Count - 1 do
  begin
    if Value.ToString = EnumArray.Items[I].ToString then
    begin
      Found := True;
      Break;
    end;
  end;

  if not Found then
  begin
    EnumStr := EnumArray.ToString;
    Result := TSchemaError.Create(Path,
      Format('Value not in allowed enum: %s', [EnumStr]),
      'enum');
  end;
end;

{ TSchemaValidator }

class function TSchemaValidator.ValidateJSON(const JSONString, SchemaString: string): TSchemaValidationResult;
var
  Schema: TJSONSchema;
begin
  Schema := TJSONSchema.LoadFromString(SchemaString);
  try
    Result := Schema.Validate(JSONString);
  finally
    Schema.Free;
  end;
end;

class function TSchemaValidator.ValidateJSONFile(const JSONFile, SchemaFile: string): TSchemaValidationResult;
var
  JSONContent: string;
  Schema: TJSONSchema;
begin
  JSONContent := TFile.ReadAllText(JSONFile, TEncoding.UTF8);
  Schema := TJSONSchema.LoadFromFile(SchemaFile);
  try
    Result := Schema.Validate(JSONContent);
  finally
    Schema.Free;
  end;
end;

end.
