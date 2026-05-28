unit TestHelperJson;

interface

uses
  DUnitX.TestFramework, System.JSON, HelperJson;

type
  [TestFixture]
  TTestHelperJson = class
  public
    [Test]
    procedure Test_GetJSONString_Valid;
    [Test]
    procedure Test_GetJSONString_Missing;
    [Test]
    procedure Test_GetJSONString_NullJSON;
    [Test]
    procedure Test_GetJSONInteger_Valid;
    [Test]
    procedure Test_GetJSONInteger_Missing;
    [Test]
    procedure Test_GetJSONBool_True;
    [Test]
    procedure Test_GetJSONBool_False;
    [Test]
    procedure Test_GetJSONBool_StringTrue;
    [Test]
    procedure Test_GetJSONFloat_Valid;
    [Test]
    procedure Test_GetJSONObject_Valid;
    [Test]
    procedure Test_GetJSONArray_Valid;
    [Test]
    procedure Test_ParseJSON_Valid;
    [Test]
    procedure Test_ParseJSON_Invalid;
    [Test]
    procedure Test_ParseJSON_Empty;
  end;

implementation

procedure TTestHelperJson.Test_GetJSONString_Valid;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('name', 'TestValue');
    Assert.AreEqual('TestValue', GetJSONString(JSON, 'name'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONString_Missing;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    Assert.AreEqual('', GetJSONString(JSON, 'missing'));
    Assert.AreEqual('default', GetJSONString(JSON, 'missing', 'default'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONString_NullJSON;
begin
  Assert.AreEqual('', GetJSONString(nil, 'key'));
  Assert.AreEqual('def', GetJSONString(nil, 'key', 'def'));
end;

procedure TTestHelperJson.Test_GetJSONInteger_Valid;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('count', TJSONNumber.Create(42));
    Assert.AreEqual(42, GetJSONInteger(JSON, 'count'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONInteger_Missing;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    Assert.AreEqual(0, GetJSONInteger(JSON, 'missing'));
    Assert.AreEqual(99, GetJSONInteger(JSON, 'missing', 99));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONBool_True;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('flag', TJSONBool.Create(True));
    Assert.IsTrue(GetJSONBool(JSON, 'flag'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONBool_False;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('flag', TJSONBool.Create(False));
    Assert.IsFalse(GetJSONBool(JSON, 'flag'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONBool_StringTrue;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('flag', 'true');
    Assert.IsTrue(GetJSONBool(JSON, 'flag'));
    
    JSON.RemovePair('flag');
    JSON.AddPair('flag', 'TRUE');
    Assert.IsTrue(GetJSONBool(JSON, 'flag'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONFloat_Valid;
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('value', TJSONNumber.Create(3.14));
    Assert.AreEqual(3.14, GetJSONFloat(JSON, 'value'), 0.001);
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONObject_Valid;
var
  JSON, Inner: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    Inner := TJSONObject.Create;
    Inner.AddPair('innerKey', 'innerValue');
    JSON.AddPair('outer', Inner);
    
    Assert.IsNotNull(GetJSONObject(JSON, 'outer'));
    Assert.AreEqual('innerValue', GetJSONObject(JSON, 'outer').GetValue<string>('innerKey'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_GetJSONArray_Valid;
var
  JSON: TJSONObject;
  Arr: TJSONArray;
begin
  JSON := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Arr.Add('item1');
    Arr.Add('item2');
    JSON.AddPair('items', Arr);
    
    Assert.IsNotNull(GetJSONArray(JSON, 'items'));
    Assert.AreEqual(2, GetJSONArray(JSON, 'items').Count);
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_ParseJSON_Valid;
var
  JSON: TJSONObject;
begin
  JSON := ParseJSON('{"name":"test","value":123}');
  try
    Assert.IsNotNull(JSON);
    Assert.AreEqual('test', GetJSONString(JSON, 'name'));
    Assert.AreEqual(123, GetJSONInteger(JSON, 'value'));
  finally
    JSON.Free;
  end;
end;

procedure TTestHelperJson.Test_ParseJSON_Invalid;
var
  JSON: TJSONObject;
begin
  JSON := ParseJSON('not valid json');
  Assert.IsNull(JSON);
end;

procedure TTestHelperJson.Test_ParseJSON_Empty;
var
  JSON: TJSONObject;
begin
  JSON := ParseJSON('');
  Assert.IsNull(JSON);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHelperJson);

end.
