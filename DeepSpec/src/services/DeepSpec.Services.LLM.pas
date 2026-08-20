
{ ============================================================================
  DeepSpec.Services.LLM

  Wraps DeepBase.LLM for DeepSpec's specific use cases:
  - A → B generation (calls LLM with Context Pack + generation prompt)
  - Single node refinement
  - Decision write-back

  This service does NOT handle API key management - that flows through
  DeepBase.Security and DeepBase.LLM's existing infrastructure. The user
  configures their LLM provider in DeepBase settings.

  Falls back gracefully if DeepBase LLM is not configured: writes a note
  to the candidate output explaining how to configure manually.
  ============================================================================ }

unit DeepSpec.Services.LLM;

interface

uses
  System.SysUtils,
  System.Classes,
  DeepBase.LLM;

type
  TDeepSpecLLMResult = record
    Success: Boolean;
    Content: string;
    ErrorMessage: string;
    DurationMs: Int64;
    InputTokens: Integer;
    OutputTokens: Integer;
  end;

  TDeepSpecLLMService = class(TInterfacedObject)
  private
    FLLM: TDeepBaseLLM;
    FConfigName: string;
    FOwnsLLM: Boolean;
  public
    constructor Create(ALLM: TDeepBaseLLM = nil; AOwnsLLM: Boolean = False);
    destructor Destroy; override;

    /// <summary>
    /// Configure which DeepBase LLM config to use (default: 'Default').
    /// </summary>
    procedure SetConfig(const AConfigName: string);

    /// <summary>
    /// Test if the configured LLM is available.
    /// </summary>
    function IsAvailable: Boolean;

    /// <summary>
    /// Generate B from a prompt. Returns the LLM response.
    /// If LLM is not configured, returns a Result with Success=False and
    /// a helpful error message.
    /// </summary>
    function Generate(const APrompt: string): TDeepSpecLLMResult;

    /// <summary>
    /// Send a system + user message pair.
    /// </summary>
    function GenerateWithSystem(const ASystemPrompt, AUserPrompt: string): TDeepSpecLLMResult;

    property ConfigName: string read FConfigName;
  end;

implementation

constructor TDeepSpecLLMService.Create(ALLM: TDeepBaseLLM; AOwnsLLM: Boolean);
begin
  inherited Create;
  FLLM := ALLM;
  FOwnsLLM := AOwnsLLM;
  FConfigName := 'Default';
end;

destructor TDeepSpecLLMService.Destroy;
begin
  if FOwnsLLM then
    FLLM.Free;
  inherited;
end;

procedure TDeepSpecLLMService.SetConfig(const AConfigName: string);
begin
  FConfigName := AConfigName;
end;

function TDeepSpecLLMService.IsAvailable: Boolean;
begin
  Result := False;
  if FLLM = nil then Exit;
  try
    var LCfg := FLLM.GetConfig(FConfigName);
    Result := LCfg.IsEnabled and (LCfg.ApiKey <> '');
  except
    Result := False;
  end;
end;

function TDeepSpecLLMService.Generate(const APrompt: string): TDeepSpecLLMResult;
var
  LResp: TLLMChatResponse;
begin
  Result := Default(TDeepSpecLLMResult);

  if FLLM = nil then
  begin
    Result.Success := False;
    Result.ErrorMessage :=
      'DeepBase LLM is not configured. Configure your LLM provider in ' +
      'DeepBase settings, or copy the prompt from .deepspec/prompts/ to ' +
      'your external AI tool manually.';
    Exit;
  end;

  try
    if FLLM.Chat(APrompt, LResp, FConfigName) then
    begin
      Result.Success := LResp.Success;
      Result.Content := LResp.Content;
      Result.DurationMs := LResp.DurationMs;
      Result.InputTokens := LResp.InputTokens;
      Result.OutputTokens := LResp.OutputTokens;
      Result.ErrorMessage := LResp.ErrorMessage;
    end
    else
    begin
      Result.Success := False;
      Result.ErrorMessage := LResp.ErrorMessage;
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

function TDeepSpecLLMService.GenerateWithSystem(const ASystemPrompt,
  AUserPrompt: string): TDeepSpecLLMResult;
var
  LResp: TLLMChatResponse;
  LMessages: TLLMMessages;
begin
  Result := Default(TDeepSpecLLMResult);

  if FLLM = nil then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'DeepBase LLM is not configured.';
    Exit;
  end;

  SetLength(LMessages, 2);
  LMessages[0] := TLLMMessage.System(ASystemPrompt);
  LMessages[1] := TLLMMessage.User(AUserPrompt);

  try
    if FLLM.ChatWithMessages(LMessages, LResp, FConfigName) then
    begin
      Result.Success := LResp.Success;
      Result.Content := LResp.Content;
      Result.DurationMs := LResp.DurationMs;
      Result.InputTokens := LResp.InputTokens;
      Result.OutputTokens := LResp.OutputTokens;
      Result.ErrorMessage := LResp.ErrorMessage;
    end
    else
    begin
      Result.Success := False;
      Result.ErrorMessage := LResp.ErrorMessage;
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

end.
