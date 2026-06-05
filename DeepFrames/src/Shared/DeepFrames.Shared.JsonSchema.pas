unit DeepFrames.Shared.JsonSchema;

/// <summary>
/// Pragmatic JSON Schema validator for LLM structured output.
///
/// Validates a JSON document against a JSON Schema (Draft-07 subset) and
/// attempts auto-repair for common issues:
///   - Missing required fields → add with default values
///   - Type mismatches → coerce if possible (string→number, etc.)
///   - Extra fields → trim (configurable)
///
/// Supports: type, required, properties, enum, items, nested objects/arrays.
/// Unsupported: $ref, oneOf/anyOf/allOf, pattern, format, min/max constraints.
///
/// Usage:
///   var V: TSchemaValidationResult;
///   V := TJsonSchemaValidator.Validate(SchemaJson, DocumentJson);
///   if V.IsValid then ...  // DocumentJson may have been repaired (V.RepairedJson)
/// </summary>

interface

uses
  System.JSON;

type
  /// <summary>Result of schema validation with optional repair.</summary>
  TSchemaValidationResult = record
    IsValid: Boolean;
    ErrorCount: Integer;
    RepairCount: Integer;
    Errors: TArray<string>;
    RepairedJson: string;       // repaired document (same as input if no repairs)
    OriginalJson: string;       // original input for comparison
    function HasErrors: Boolean;
    function HasRepairs: Boolean;
  end;

  /// <summary>Pragmatic JSON Schema validator for LLM output quality control.</summary>
  TJsonSchemaValidator = class
  public
    /// <summary>
    /// Validate DocumentJson against SchemaJson.
    /// If EnableAutoRepair is True (default), attempts to fix common issues.
    /// Returns the validation result with repaired JSON when applicable.
    /// </summary>
    class function Validate(const SchemaJson, DocumentJson: string;
      EnableAutoRepair: Boolean = True): TSchemaValidationResult; static;

    /// <summary>
    /// Validate with pre-parsed schema and document objects.
    /// </summary>
    class function ValidateObjects(const Schema, Document: TJSONObject;
      EnableAutoRepair: Boolean = True): TSchemaValidationResult; static;

    /// <summary>
    /// Quick check: does the document pass schema validation?
    /// </summary>
    class function IsValid(const SchemaJson, DocumentJson: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TValidationContext = class
  strict private
    FErrors: TList<string>;
    FRepairs: Integer;
    FAutoRepair: Boolean;
    FDocument: TJSONObject;  // mutable copy for repair
  public
    constructor Create(ADocument: TJSONObject; AEnableAutoRepair: Boolean);
    destructor Destroy; override;
    procedure AddError(const AMessage: string);
    procedure AddRepair(const AMessage: string);
    function GetRepairedJson: string;
    property Errors: TList<string> read FErrors;
    property Repairs: Integer read FRepairs;
    property AutoRepair: Boolean read FAutoRepair;
    property Document: TJSONObject read FDocument;
  end;

{ TValidationContext }

constructor TValidationContext.Create(ADocument: TJSONObject; AEnableAutoRepair: Boolean);
begin
  inherited Create;
  FErrors := TList<string>.Create;
  FRepairs := 0;
  FAutoRepair := AEnableAutoRepair;
  // Clone the document so repairs don't mutate the original
  FDocument := TJSONObject.ParseJSONValue(ADocument.ToJSON) as TJSONObject;
end;

destructor TValidationContext.Destroy;
begin
  FDocument.Free;
  FErrors.Free;
  inherited;
end;

procedure TValidationContext.AddError(const AMessage: string);
begin
  FErrors.Add(AMessage);
end;

procedure TValidationContext.AddRepair(const AMessage: string);
begin
  Inc(FRepairs);
end;

function TValidationContext.GetRepairedJson: string;
begin
  Result := FDocument.ToJSON;
end;

{ TSchemaValidationResult }

function TSchemaValidationResult.HasErrors: Boolean;
begin
  Result := ErrorCount > 0;
end;

function TSchemaValidationResult.HasRepairs: Boolean;
begin
  Result := RepairCount > 0;
end;

{ TJsonSchemaValidator }

// Forward declarations
procedure ValidateObject(const AInstance: TJSONObject; const ASchema: TJSONObject;
  const APath: string; ACtx: TValidationContext); forward;

function GetSchemaType(const ASchema: TJSONObject): string;
var
  TypeVal: TJSONValue;
begin
  TypeVal := ASchema.GetValue('type');
  if (TypeVal is TJSONString) then
    Result := TJSONString(TypeVal).Value
  else if (TypeVal is TJSONArray) and (TJSONArray(TypeVal).Count > 0) then
    Result := TJSONArray(TypeVal).Items[0].Value  // use first type for simplicity
  else
    Result := '';
end;

function GetRequiredFields(const ASchema: TJSONObject): TArray<string>;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := nil;
  Arr := ASchema.GetValue('required') as TJSONArray;
  if Arr = nil then
    Exit;
  SetLength(Result, Arr.Count);
  for I := 0 to Arr.Count - 1 do
    Result[I] := Arr.Items[I].Value;
end;

function GetPropertySchema(const ASchema: TJSONObject; const APropertyName: string): TJSONObject;
var
  Props: TJSONObject;
begin
  Result := nil;
  Props := ASchema.GetValue('properties') as TJSONObject;
  if Props = nil then
    Exit;
  Result := Props.GetValue(APropertyName) as TJSONObject;
end;

function GetEnumValues(const ASchema: TJSONObject): TArray<string>;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := nil;
  Arr := ASchema.GetValue('enum') as TJSONArray;
  if Arr = nil then
    Exit;
  SetLength(Result, Arr.Count);
  for I := 0 to Arr.Count - 1 do
    Result[I] := Arr.Items[I].Value;
end;

function MatchesEnum(const AValue: string; const AEnumValues: TArray<string>): Boolean;
var
  S: string;
begin
  for S in AEnumValues do
    if SameText(S, AValue) then
      Exit(True);
  Result := False;
end;

function CoerceValue(const AValue: TJSONValue; const ATargetType: string;
  out AResult: TJSONValue): Boolean;
begin
  Result := False;
  AResult := nil;

  if ATargetType = 'string' then
  begin
    if AValue is TJSONString then
      AResult := TJSONString.Create(TJSONString(AValue).Value)
    else
      AResult := TJSONString.Create(AValue.ToString);
    Exit(True);
  end;

  if ATargetType = 'number' then
  begin
    if AValue is TJSONNumber then
      AResult := TJSONNumber.Create(TJSONNumber(AValue).AsDouble)
    else if AValue is TJSONString then
    begin
      var D: Double;
      if TryStrToFloat(TJSONString(AValue).Value, D) then
      begin
        AResult := TJSONNumber.Create(D);
        Exit(True);
      end;
    end;
    Exit(False);
  end;

  if ATargetType = 'integer' then
  begin
    if AValue is TJSONNumber then
      AResult := TJSONNumber.Create(TJSONNumber(AValue).AsInt)
    else if AValue is TJSONString then
    begin
      var I: Integer;
      if TryStrToInt(TJSONString(AValue).Value, I) then
      begin
        AResult := TJSONNumber.Create(I);
        Exit(True);
      end;
    end;
    Exit(False);
  end;

  if ATargetType = 'boolean' then
  begin
    if AValue is TJSONBool then
      AResult := TJSONBool.Create(TJSONBool(AValue).AsBoolean)
    else if AValue is TJSONString then
    begin
      var S: string := TJSONString(AValue).Value;
      if SameText(S, 'true') or SameText(S, '1') then
        AResult := TJSONBool.Create(True)
      else if SameText(S, 'false') or SameText(S, '0') then
        AResult := TJSONBool.Create(False)
      else
        Exit(False);
      Exit(True);
    end
    else if AValue is TJSONNumber then
    begin
      AResult := TJSONBool.Create(TJSONNumber(AValue).AsInt <> 0);
      Exit(True);
    end;
    Exit(False);
  end;

  if ATargetType = 'object' then
  begin
    if AValue is TJSONObject then
      AResult := TJSONObject.ParseJSONValue(AValue.ToJSON) as TJSONValue
    else
    begin
      // Try to parse string as JSON object
      var Obj: TJSONObject := TJSONObject.ParseJSONValue(AValue.ToString) as TJSONObject;
      if Obj <> nil then
        AResult := Obj
      else
        Exit(False);
    end;
    Exit(True);
  end;

  if ATargetType = 'array' then
  begin
    if AValue is TJSONArray then
      AResult := TJSONArray.ParseJSONValue(AValue.ToJSON) as TJSONValue
    else
      Exit(False);
    Exit(True);
  end;
end;

function GetDefaultValue(const AType: string): TJSONValue;
begin
  if AType = 'string' then
    Result := TJSONString.Create('')
  else if (AType = 'number') or (AType = 'integer') then
    Result := TJSONNumber.Create(0)
  else if AType = 'boolean' then
    Result := TJSONBool.Create(False)
  else if AType = 'object' then
    Result := TJSONObject.Create
  else if AType = 'array' then
    Result := TJSONArray.Create
  else
    Result := TJSONString.Create('');
end;

procedure ValidateTypeMatch(const AValue: TJSONValue; const ASchema: TJSONObject;
  const APath: string; ACtx: TValidationContext; var AOutValue: TJSONValue);
var
  SchemaType: string;
  IsMatch: Boolean;
begin
  AOutValue := nil;
  SchemaType := GetSchemaType(ASchema);
  if SchemaType = '' then
    Exit; // no type constraint — skip

  IsMatch := False;
  case SchemaType[1] of
    's': IsMatch := (AValue is TJSONString);                    // string
    'n': IsMatch := (AValue is TJSONNumber);                    // number
    'i': IsMatch := (AValue is TJSONNumber);                    // integer
    'b': IsMatch := (AValue is TJSONBool);                      // boolean
    'o': IsMatch := (AValue is TJSONObject);                    // object
    'a': IsMatch := (AValue is TJSONArray);                     // array
  end;

  if not IsMatch and ACtx.AutoRepair then
  begin
    if CoerceValue(AValue, SchemaType, AOutValue) then
    begin
      ACtx.AddRepair(Format('%s: coerced value from %s to %s',
        [APath, AValue.ClassName, SchemaType]));
    end
    else
    begin
      ACtx.AddError(Format('%s: expected type %s, got %s, cannot coerce',
        [APath, SchemaType, AValue.ClassName]));
    end;
  end
  else if not IsMatch then
  begin
    ACtx.AddError(Format('%s: expected type %s, got %s',
      [APath, SchemaType, AValue.ClassName]));
  end;
end;

procedure ValidateObject(const AInstance: TJSONObject; const ASchema: TJSONObject;
  const APath: string; ACtx: TValidationContext);
var
  RequiredFields: TArray<string>;
  PropSchema: TJSONObject;
  PropValue: TJSONValue;
  DefaultValue: TJSONValue;
  FieldName: string;
  EnumValues: TArray<string>;
  CoercedValue: TJSONValue;
  InnerSchema: TJSONObject;
  InnerArray: TJSONArray;
  I: Integer;
begin
  // 1. Check required fields
  RequiredFields := GetRequiredFields(ASchema);
  for FieldName in RequiredFields do
  begin
    if AInstance.GetValue(FieldName) = nil then
    begin
      if ACtx.AutoRepair then
      begin
        PropSchema := GetPropertySchema(ASchema, FieldName);
        DefaultValue := GetDefaultValue(GetSchemaType(PropSchema));
        ACtx.Document.AddPair(FieldName, DefaultValue);
        ACtx.AddRepair(Format('%s.%s: added missing required field with default',
          [APath, FieldName]));
      end
      else
        ACtx.AddError(Format('%s.%s: missing required field', [APath, FieldName]));
    end;
  end;

  // 2. Validate each property against its schema
  InnerSchema := ASchema.GetValue('properties') as TJSONObject;
  if InnerSchema = nil then
    Exit;

  for I := 0 to AInstance.Count - 1 do
  begin
    FieldName := AInstance.Pairs[I].JsonString.Value;
    PropValue := AInstance.Pairs[I].JsonValue;
    PropSchema := InnerSchema.GetValue(FieldName) as TJSONObject;
    if PropSchema = nil then
      Continue; // no schema for this field — skip

    var FieldPath := APath + '.' + FieldName;

    // 2a. Type check
    CoercedValue := nil;
    ValidateTypeMatch(PropValue, PropSchema, FieldPath, ACtx, CoercedValue);
    if CoercedValue <> nil then
    begin
      // Replace the value in the document with the coerced version
      AInstance.RemovePair(FieldName);
      AInstance.AddPair(FieldName, CoercedValue);
      PropValue := CoercedValue;
    end;

    // 2b. Enum check
    EnumValues := GetEnumValues(PropSchema);
    if Length(EnumValues) > 0 then
    begin
      if (PropValue is TJSONString) and not MatchesEnum(TJSONString(PropValue).Value, EnumValues) then
      begin
        if ACtx.AutoRepair then
        begin
          // Auto-repair: use first enum value
          AInstance.RemovePair(FieldName);
          AInstance.AddPair(FieldName, TJSONString.Create(EnumValues[0]));
          ACtx.AddRepair(Format('%s: reset from ''%s'' to enum default ''%s''',
            [FieldPath, TJSONString(PropValue).Value, EnumValues[0]]));
        end
        else
          ACtx.AddError(Format('%s: value ''%s'' not in enum [%s]',
            [FieldPath, TJSONString(PropValue).Value, string.Join(', ', EnumValues)]));
      end;
    end;

    // 2c. Nested object validation
    if (PropValue is TJSONObject) and (GetSchemaType(PropSchema) = 'object') then
      ValidateObject(TJSONObject(PropValue), PropSchema, FieldPath, ACtx);

    // 2d. Array items validation
    if (PropValue is TJSONArray) and (GetSchemaType(PropSchema) = 'array') then
    begin
      var ItemsSchema: TJSONObject := PropSchema.GetValue('items') as TJSONObject;
      if ItemsSchema <> nil then
      begin
        InnerArray := TJSONArray(PropValue);
        for var J := 0 to InnerArray.Count - 1 do
        begin
          if InnerArray.Items[J] is TJSONObject then
            ValidateObject(TJSONObject(InnerArray.Items[J]), ItemsSchema,
              Format('%s[%d]', [FieldPath, J]), ACtx);
        end;
      end;
    end;
  end;
end;

class function TJsonSchemaValidator.Validate(const SchemaJson,
  DocumentJson: string; EnableAutoRepair: Boolean): TSchemaValidationResult;
var
  SchemaObj, DocObj: TJSONObject;
begin
  Result.OriginalJson := DocumentJson;
  Result.RepairedJson := DocumentJson;
  Result.IsValid := True;
  Result.ErrorCount := 0;
  Result.RepairCount := 0;
  Result.Errors := nil;

  // Parse schema
  SchemaObj := TJSONObject.ParseJSONValue(SchemaJson) as TJSONObject;
  if SchemaObj = nil then
  begin
    Result.IsValid := False;
    Result.ErrorCount := 1;
    Result.Errors := ['Schema JSON parse error'];
    Exit;
  end;

  // Parse document
  DocObj := TJSONObject.ParseJSONValue(DocumentJson) as TJSONObject;
  if DocObj = nil then
  begin
    Result.IsValid := False;
    Result.ErrorCount := 1;
    Result.Errors := ['Document JSON parse error'];
    SchemaObj.Free;
    Exit;
  end;

  try
    Result := ValidateObjects(SchemaObj, DocObj, EnableAutoRepair);
  finally
    SchemaObj.Free;
    DocObj.Free;
  end;
end;

class function TJsonSchemaValidator.ValidateObjects(const Schema,
  Document: TJSONObject; EnableAutoRepair: Boolean): TSchemaValidationResult;
var
  Ctx: TValidationContext;
begin
  Result.OriginalJson := Document.ToJSON;
  Result.RepairedJson := Document.ToJSON;
  Result.IsValid := True;
  Result.ErrorCount := 0;
  Result.RepairCount := 0;
  Result.Errors := nil;

  Ctx := TValidationContext.Create(Document, EnableAutoRepair);
  try
    ValidateObject(Ctx.Document, Schema, '$', Ctx);

    Result.ErrorCount := Ctx.Errors.Count;
    Result.RepairCount := Ctx.Repairs;
    Result.Errors := Ctx.Errors.ToArray;
    Result.IsValid := (Result.ErrorCount = 0);
    Result.RepairedJson := Ctx.GetRepairedJson;
  finally
    Ctx.Free;
  end;
end;

class function TJsonSchemaValidator.IsValid(const SchemaJson,
  DocumentJson: string): Boolean;
var
  V: TSchemaValidationResult;
begin
  V := Validate(SchemaJson, DocumentJson, False);
  Result := V.IsValid;
end;

end.