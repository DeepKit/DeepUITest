unit HelperJson;

interface

uses
  System.SysUtils, System.JSON, System.Variants;

function GetJSONString(const JSON: TJSONObject; const Key: string; const Default: string = ''): string;
function GetJSONInteger(const JSON: TJSONObject; const Key: string; const Default: Integer = 0): Integer;
function GetJSONBool(const JSON: TJSONObject; const Key: string; const Default: Boolean = False): Boolean;
function GetJSONFloat(const JSON: TJSONObject; const Key: string; const Default: Double = 0.0): Double;
function GetJSONObject(const JSON: TJSONObject; const Key: string): TJSONObject;
function GetJSONArray(const JSON: TJSONObject; const Key: string): TJSONArray;
function ParseJSON(const S: string): TJSONObject;
function SafeVarToStr(const V: Variant): string;

implementation

function GetJSONString(const JSON: TJSONObject; const Key: string; const Default: string): string;
begin
  Result := Default;
  if not Assigned(JSON) then Exit;

  var Val := JSON.FindValue(Key);
  if Assigned(Val) and not Val.Null then
    Result := Val.Value;
end;

function GetJSONInteger(const JSON: TJSONObject; const Key: string; const Default: Integer): Integer;
begin
  Result := Default;
  if not Assigned(JSON) then Exit;

  var Val := JSON.FindValue(Key);
  if Assigned(Val) and not Val.Null and (Val is TJSONNumber) then
    Result := TJSONNumber(Val).AsInt;
end;

function GetJSONBool(const JSON: TJSONObject; const Key: string; const Default: Boolean): Boolean;
begin
  Result := Default;
  if not Assigned(JSON) then Exit;

  var Val := JSON.FindValue(Key);
  if Assigned(Val) and not Val.Null then
  begin
    if Val is TJSONBool then
      Result := TJSONBool(Val).AsBoolean
    else if Val is TJSONString then
      Result := LowerCase(Val.Value) = 'true';
  end;
end;

function GetJSONFloat(const JSON: TJSONObject; const Key: string; const Default: Double): Double;
begin
  Result := Default;
  if not Assigned(JSON) then Exit;

  var Val := JSON.FindValue(Key);
  if Assigned(Val) and not Val.Null and (Val is TJSONNumber) then
    Result := TJSONNumber(Val).AsDouble;
end;

function GetJSONObject(const JSON: TJSONObject; const Key: string): TJSONObject;
begin
  Result := nil;
  if not Assigned(JSON) then Exit;

  var Val := JSON.FindValue(Key);
  if Assigned(Val) and (Val is TJSONObject) then
    Result := TJSONObject(Val);
end;

function GetJSONArray(const JSON: TJSONObject; const Key: string): TJSONArray;
begin
  Result := nil;
  if not Assigned(JSON) then Exit;

  var Val := JSON.FindValue(Key);
  if Assigned(Val) and (Val is TJSONArray) then
    Result := TJSONArray(Val);
end;

function ParseJSON(const S: string): TJSONObject;
begin
  Result := nil;
  if S = '' then Exit;

  try
    var Val := TJSONObject.ParseJSONValue(S);
    if Assigned(Val) and (Val is TJSONObject) then
      Result := TJSONObject(Val)
    else if Assigned(Val) then
      Val.Free;
  except
    Result := nil;
  end;
end;

function SafeVarToStr(const V: Variant): string;
begin
  if VarIsNull(V) or VarIsEmpty(V) then Result := '' else Result := VarToStr(V);
end;

end.
