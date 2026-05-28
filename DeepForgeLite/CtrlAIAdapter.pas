unit CtrlAIAdapter;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Net.HttpClient,
  System.Net.URLClient, System.Threading, uModels;

type
  TAIResponse = record
    Success: Boolean;
    Content: string;
    ErrorMsg: string;
    InputTokens: Integer;
    OutputTokens: Integer;
    procedure Clear;
  end;

  TAIAdapter = class
  private
    FConfig: TAIConfig;
    FHTTP: THTTPClient;
    function BuildRequestBody(const Prompt, Model: string): string;
    function ParseResponse(const ResponseText: string): TAIResponse;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure SetConfig(const AConfig: TAIConfig);
    function CallAI(const Prompt: string; ModelLevel: TAIRetryLevel = rlTier1): TAIResponse;
    function CallAIAsync(const Prompt: string; ModelLevel: TAIRetryLevel;
      OnComplete: TProc<TAIResponse>): ITask;
    
    property Config: TAIConfig read FConfig write FConfig;
  end;

function AIAdapter: TAIAdapter;

implementation

var
  GAIAdapter: TAIAdapter = nil;

function AIAdapter: TAIAdapter;
begin
  if not Assigned(GAIAdapter) then
    GAIAdapter := TAIAdapter.Create;
  Result := GAIAdapter;
end;

{ TAIResponse }

procedure TAIResponse.Clear;
begin
  Success := False;
  Content := '';
  ErrorMsg := '';
  InputTokens := 0;
  OutputTokens := 0;
end;

{ TAIAdapter }

constructor TAIAdapter.Create;
begin
  inherited;
  FHTTP := THTTPClient.Create;
  FHTTP.ConnectionTimeout := 30000;
  FHTTP.ResponseTimeout := 180000;
  
  FConfig.Clear;
  FConfig.Provider := 'anthropic';
  FConfig.APIKey := 'fuyi-kiro-17781158558';
  FConfig.BaseURL := 'http://localhost:8000';
  FConfig.ModelTier1 := 'claude-sonnet-4-6';
  FConfig.ModelTier2 := 'claude-sonnet-4-6';
  FConfig.ModelTier3 := 'claude-sonnet-4-6';
end;

destructor TAIAdapter.Destroy;
begin
  FHTTP.Free;
  inherited;
end;

procedure TAIAdapter.SetConfig(const AConfig: TAIConfig);
begin
  FConfig := AConfig;
end;

function TAIAdapter.BuildRequestBody(const Prompt, Model: string): string;
var
  JSON: TJSONObject;
  MsgArray: TJSONArray;
  MsgObj: TJSONObject;
begin
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('model', Model);
    JSON.AddPair('max_tokens', TJSONNumber.Create(4096));
    
    MsgArray := TJSONArray.Create;
    MsgObj := TJSONObject.Create;
    MsgObj.AddPair('role', 'user');
    MsgObj.AddPair('content', Prompt);
    MsgArray.Add(MsgObj);
    JSON.AddPair('messages', MsgArray);
    
    Result := JSON.ToString;
  finally
    JSON.Free;
  end;
end;

function TAIAdapter.ParseResponse(const ResponseText: string): TAIResponse;
var
  JSON: TJSONObject;
  ContentArray: TJSONArray;
  ContentObj: TJSONObject;
  UsageObj: TJSONObject;
  I: Integer;
  TextContent: string;
begin
  Result.Clear;
  
  JSON := TJSONObject.ParseJSONValue(ResponseText) as TJSONObject;
  if not Assigned(JSON) then
  begin
    Result.ErrorMsg := 'Failed to parse response';
    Exit;
  end;
  
  try
    if JSON.GetValue<string>('type', '') = 'error' then
    begin
      Result.ErrorMsg := JSON.GetValue<string>('error.message', 'Unknown error');
      Exit;
    end;
    
    ContentArray := JSON.GetValue<TJSONArray>('content');
    if Assigned(ContentArray) then
    begin
      TextContent := '';
      for I := 0 to ContentArray.Count - 1 do
      begin
        ContentObj := ContentArray.Items[I] as TJSONObject;
        if ContentObj.GetValue<string>('type', '') = 'text' then
        begin
          TextContent := TextContent + ContentObj.GetValue<string>('text', '');
        end;
      end;
      Result.Content := TextContent;
      Result.Success := True;
    end;
    
    UsageObj := JSON.GetValue<TJSONObject>('usage');
    if Assigned(UsageObj) then
    begin
      Result.InputTokens := UsageObj.GetValue<Integer>('input_tokens', 0);
      Result.OutputTokens := UsageObj.GetValue<Integer>('output_tokens', 0);
    end;
    
  finally
    JSON.Free;
  end;
end;

function TAIAdapter.CallAI(const Prompt: string; ModelLevel: TAIRetryLevel): TAIResponse;
var
  RequestBody: string;
  Response: IHTTPResponse;
  Model: string;
  URL: string;
  RequestStream: TStringStream;
begin
  Result.Clear;
  
  Model := FConfig.GetModelForLevel(ModelLevel);
  URL := FConfig.BaseURL + '/v1/messages';
  
  RequestBody := BuildRequestBody(Prompt, Model);
  RequestStream := TStringStream.Create(RequestBody, TEncoding.UTF8);
  try
    try
      FHTTP.CustomHeaders['Authorization'] := 'Bearer ' + FConfig.APIKey;
      FHTTP.CustomHeaders['anthropic-version'] := '2023-06-01';
      FHTTP.ContentType := 'application/json';
      
      Response := FHTTP.Post(URL, RequestStream);
      
      if Response.StatusCode = 200 then
        Result := ParseResponse(Response.ContentAsString)
      else
        Result.ErrorMsg := Format('HTTP Error %d: %s', [Response.StatusCode, Response.ContentAsString]);
        
    except
      on E: Exception do
        Result.ErrorMsg := 'Exception: ' + E.Message;
    end;
  finally
    RequestStream.Free;
  end;
end;

function TAIAdapter.CallAIAsync(const Prompt: string; ModelLevel: TAIRetryLevel;
  OnComplete: TProc<TAIResponse>): ITask;
begin
  Result := TTask.Create(
    procedure
    var
      R: TAIResponse;
    begin
      R := CallAI(Prompt, ModelLevel);
      if Assigned(OnComplete) then
        OnComplete(R);
    end);
  Result.Start;
end;

end.
