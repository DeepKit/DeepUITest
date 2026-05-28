{ ============================================================================
  UniFlow.AI.Adapter - LLM Adapter for Workflow Integration

  Version: 1.0
  Description: Lightweight adapter that bridges DeepBase.LLM with UniFlow
               Workflow Context. Does NOT duplicate DeepBase.LLM functionality.

  Usage:
    var Adapter := TUniFlowLLMAdapter.Create(DeepBaseLLM);
    try
      var Response := Adapter.ExecuteFromContext(WorkflowContext, StepConfig);
      // Response is written back to Context automatically
    finally
      Adapter.Free;
    end;
  ============================================================================ }

unit UniFlow.AI.Adapter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  DeepBase.LLM,
  DeepBase.Types,
  UniFlow.Workflow.Context,
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Executor;

type
  /// <summary>
  /// LLM execution options extracted from workflow step
  /// </summary>
  TLLMExecutionOptions = record
    ConfigName: string;       // DeepBase.LLM config name (e.g., 'Default', 'CodeGen')
    Model: string;            // Override model (optional)
    SystemPrompt: string;     // System prompt (supports {{ vars }})
    UserPrompt: string;       // User prompt (supports {{ vars }})
    MaxTokens: Integer;       // Override max tokens (0 = use config default)
    Temperature: Double;      // Override temperature (-1 = use config default)
    OutputVariable: string;   // Variable to store response content
    TokensVariable: string;   // Variable to store token usage (optional)
    // Response parsing
    ParseAsJson: Boolean;     // Try to parse response as JSON
    JsonOutputMap: TDictionary<string, string>;  // JSON path -> variable mapping

    procedure Init;
    class function FromJSON(const AJSON: TJSONObject): TLLMExecutionOptions; static;
  end;

  /// <summary>
  /// LLM execution result
  /// </summary>
  TLLMExecutionResult = record
    Success: Boolean;
    Content: string;
    InputTokens: Integer;
    OutputTokens: Integer;
    DurationMs: Int64;
    ErrorMessage: string;

    procedure Init;
  end;

  /// <summary>
  /// Adapter that bridges DeepBase.LLM with UniFlow Workflow
  /// </summary>
  TUniFlowLLMAdapter = class
  private
    FLLM: TDeepBaseLLM;
    FOwnsLLM: Boolean;

    function ResolveTemplate(const Template: string; Context: TWorkflowContext): string;
    function ExtractJsonValue(const JSON: TJSONObject; const Path: string): string;
  public
    constructor Create(ALLM: TDeepBaseLLM; AOwnsLLM: Boolean = False);
    destructor Destroy; override;

    /// <summary>
    /// Execute LLM call using options and write results to context
    /// </summary>
    function Execute(const Options: TLLMExecutionOptions;
      Context: TWorkflowContext): TLLMExecutionResult;

    /// <summary>
    /// Execute LLM call from workflow step action definition
    /// </summary>
    function ExecuteFromAction(const Action: TActionDefinition;
      Context: TWorkflowContext): TLLMExecutionResult;

    /// <summary>
    /// Quick chat without context (for simple use cases)
    /// </summary>
    function QuickChat(const SystemPrompt, UserPrompt: string;
      const ConfigName: string = 'Default'): string;

    property LLM: TDeepBaseLLM read FLLM;
  end;

  /// <summary>
  /// LLM Action Executor for TWorkflowExecutor
  /// Registers as handler for 'llm' action type
  /// </summary>
  TLLMActionExecutor = class(TInterfacedObject, IActionExecutor)
  private
    FAdapter: TUniFlowLLMAdapter;
    FOwnsAdapter: Boolean;
  public
    constructor Create(AAdapter: TUniFlowLLMAdapter; AOwnsAdapter: Boolean = False);
    destructor Destroy; override;

    function Execute(const Action: TActionDefinition; Context: TWorkflowContext): TStepResult;
    function GetActionType: TActionType;
  end;

/// <summary>
/// Helper function to create and register LLM executor with workflow executor
/// </summary>
procedure RegisterLLMExecutor(Executor: TWorkflowExecutor; LLM: TDeepBaseLLM);

implementation

uses
  System.StrUtils;

{ TLLMExecutionOptions }

procedure TLLMExecutionOptions.Init;
begin
  ConfigName := 'Default';
  Model := '';
  SystemPrompt := '';
  UserPrompt := '';
  MaxTokens := 0;
  Temperature := -1;
  OutputVariable := 'llm_response';
  TokensVariable := '';
  ParseAsJson := False;
  JsonOutputMap := nil;
end;

class function TLLMExecutionOptions.FromJSON(const AJSON: TJSONObject): TLLMExecutionOptions;
var
  MapObj: TJSONObject;
  Pair: TJSONPair;
begin
  Result.Init;

  if AJSON = nil then
    Exit;

  if AJSON.TryGetValue<string>('config', Result.ConfigName) then;
  if AJSON.TryGetValue<string>('model', Result.Model) then;
  if AJSON.TryGetValue<string>('system_prompt', Result.SystemPrompt) then;
  if AJSON.TryGetValue<string>('user_prompt', Result.UserPrompt) then;
  if AJSON.TryGetValue<string>('prompt', Result.UserPrompt) then;  // Alias
  if AJSON.TryGetValue<Integer>('max_tokens', Result.MaxTokens) then;
  if AJSON.TryGetValue<Double>('temperature', Result.Temperature) then;
  if AJSON.TryGetValue<string>('output', Result.OutputVariable) then;
  if AJSON.TryGetValue<string>('output_variable', Result.OutputVariable) then;  // Alias
  if AJSON.TryGetValue<string>('tokens_variable', Result.TokensVariable) then;
  if AJSON.TryGetValue<Boolean>('parse_json', Result.ParseAsJson) then;

  // Parse JSON output mapping
  if AJSON.TryGetValue<TJSONObject>('json_map', MapObj) then
  begin
    Result.JsonOutputMap := TDictionary<string, string>.Create;
    for Pair in MapObj do
      Result.JsonOutputMap.Add(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;
end;

{ TLLMExecutionResult }

procedure TLLMExecutionResult.Init;
begin
  Success := False;
  Content := '';
  InputTokens := 0;
  OutputTokens := 0;
  DurationMs := 0;
  ErrorMessage := '';
end;

{ TUniFlowLLMAdapter }

constructor TUniFlowLLMAdapter.Create(ALLM: TDeepBaseLLM; AOwnsLLM: Boolean);
begin
  inherited Create;
  FLLM := ALLM;
  FOwnsLLM := AOwnsLLM;
end;

destructor TUniFlowLLMAdapter.Destroy;
begin
  if FOwnsLLM and Assigned(FLLM) then
    FLLM.Free;
  inherited;
end;

function TUniFlowLLMAdapter.ResolveTemplate(const Template: string;
  Context: TWorkflowContext): string;
begin
  // Use workflow context's expression evaluator to resolve {{ vars.xxx }}
  Result := Context.EvaluateExpression(Template);
end;

function TUniFlowLLMAdapter.ExtractJsonValue(const JSON: TJSONObject;
  const Path: string): string;
var
  Parts: TArray<string>;
  Current: TJSONValue;
  I: Integer;
begin
  Result := '';
  if JSON = nil then
    Exit;

  // Simple path like "data.content" or "result"
  Parts := Path.Split(['.']);
  Current := JSON;

  for I := 0 to High(Parts) do
  begin
    if Current is TJSONObject then
      Current := TJSONObject(Current).GetValue(Parts[I])
    else
      Exit;

    if Current = nil then
      Exit;
  end;

  if Current is TJSONString then
    Result := TJSONString(Current).Value
  else
    Result := Current.ToString;
end;

function TUniFlowLLMAdapter.Execute(const Options: TLLMExecutionOptions;
  Context: TWorkflowContext): TLLMExecutionResult;
var
  Messages: TLLMMessages;
  Response: TLLMChatResponse;
  ResolvedSystem, ResolvedUser: string;
  ParsedJSON: TJSONObject;
  Pair: TPair<string, string>;
begin
  Result.Init;

  if not Assigned(FLLM) then
  begin
    Result.ErrorMessage := 'LLM instance not available';
    Exit;
  end;

  // Resolve templates with context variables
  ResolvedSystem := ResolveTemplate(Options.SystemPrompt, Context);
  ResolvedUser := ResolveTemplate(Options.UserPrompt, Context);

  if ResolvedUser.IsEmpty then
  begin
    Result.ErrorMessage := 'User prompt is empty';
    Exit;
  end;

  // Build messages array
  SetLength(Messages, 0);
  if not ResolvedSystem.IsEmpty then
  begin
    SetLength(Messages, 1);
    Messages[0] := TLLMMessage.System(ResolvedSystem);
  end;
  SetLength(Messages, Length(Messages) + 1);
  Messages[High(Messages)] := TLLMMessage.User(ResolvedUser);

  // Execute LLM call via DeepBase.LLM
  try
    Response := FLLM.Chat(Messages, Options.ConfigName);

    Result.Success := Response.Success;
    Result.Content := Response.Content;
    Result.InputTokens := Response.InputTokens;
    Result.OutputTokens := Response.OutputTokens;
    Result.DurationMs := Response.DurationMs;
    Result.ErrorMessage := Response.ErrorMessage;

    // Write results to context
    if Response.Success then
    begin
      Context.SetVariable(Options.OutputVariable, Response.Content);

      // Optional: store token usage
      if not Options.TokensVariable.IsEmpty then
      begin
        Context.SetVariable(Options.TokensVariable + '.input', Response.InputTokens);
        Context.SetVariable(Options.TokensVariable + '.output', Response.OutputTokens);
        Context.SetVariable(Options.TokensVariable + '.total', Response.TotalTokens);
      end;

      // Optional: parse JSON response and map to variables
      if Options.ParseAsJson and Assigned(Options.JsonOutputMap) then
      begin
        try
          ParsedJSON := TJSONObject.ParseJSONValue(Response.Content) as TJSONObject;
          if Assigned(ParsedJSON) then
          try
            for Pair in Options.JsonOutputMap do
              Context.SetVariable(Pair.Value, ExtractJsonValue(ParsedJSON, Pair.Key));
          finally
            ParsedJSON.Free;
          end;
        except
          on E: Exception do
          begin
            // ENTROPY-011: 记录 JSON 解析失败
            {$IFDEF DEBUG}
            OutputDebugString(PChar(Format('[LLMAdapter] JSON output parsing failed: %s', [E.Message])));
            {$ENDIF}
          end;
        end;
      end;
    end
    else
    begin
      Context.SetVariable(Options.OutputVariable + '.error', Response.ErrorMessage);
    end;
  except
    on E: Exception do
    begin
      Result.ErrorMessage := E.Message;
      Context.SetVariable(Options.OutputVariable + '.error', E.Message);
    end;
  end;
end;

function TUniFlowLLMAdapter.ExecuteFromAction(const Action: TActionDefinition;
  Context: TWorkflowContext): TLLMExecutionResult;
var
  Options: TLLMExecutionOptions;
  ParamsJSON: TJSONObject;
begin
  Result.Init;

  // Extract options from action parameters
  Options.Init;

  // Parse action.Params (JSON string) to extract LLM options
  if not Action.Params.IsEmpty then
  begin
    try
      ParamsJSON := TJSONObject.ParseJSONValue(Action.Params) as TJSONObject;
      if Assigned(ParamsJSON) then
      try
        Options := TLLMExecutionOptions.FromJSON(ParamsJSON);
      finally
        ParamsJSON.Free;
      end;
    except
      on E: Exception do
      begin
        // ENTROPY-011: 记录参数解析失败，使用默认�?
        {$IFDEF DEBUG}
        OutputDebugString(PChar(Format('[LLMAdapter] Action params parsing failed: %s', [E.Message])));
        {$ENDIF}
      end;
    end;
  end;

  // Override with action-level settings if present
  if not Action.Skill.IsEmpty then
    Options.ConfigName := Action.Skill;

  // Execute
  Result := Execute(Options, Context);
end;

function TUniFlowLLMAdapter.QuickChat(const SystemPrompt, UserPrompt: string;
  const ConfigName: string): string;
var
  Messages: TLLMMessages;
  Response: TLLMChatResponse;
begin
  Result := '';

  if not Assigned(FLLM) then
    raise ELLMException.Create('LLM instance not available');

  SetLength(Messages, 0);
  if not SystemPrompt.IsEmpty then
  begin
    SetLength(Messages, 1);
    Messages[0] := TLLMMessage.System(SystemPrompt);
  end;
  SetLength(Messages, Length(Messages) + 1);
  Messages[High(Messages)] := TLLMMessage.User(UserPrompt);

  Response := FLLM.Chat(Messages, ConfigName);

  if Response.Success then
    Result := Response.Content
  else
    raise ELLMException.CreateFmt('LLM call failed: %s', [Response.ErrorMessage]);
end;

{ TLLMActionExecutor }

constructor TLLMActionExecutor.Create(AAdapter: TUniFlowLLMAdapter; AOwnsAdapter: Boolean);
begin
  inherited Create;
  FAdapter := AAdapter;
  FOwnsAdapter := AOwnsAdapter;
end;

destructor TLLMActionExecutor.Destroy;
begin
  if FOwnsAdapter and Assigned(FAdapter) then
    FAdapter.Free;
  inherited;
end;

function TLLMActionExecutor.Execute(const Action: TActionDefinition;
  Context: TWorkflowContext): TStepResult;
var
  LLMResult: TLLMExecutionResult;
begin
  Result.Init;
  Result.StepId := ''; // Will be set by executor

  if not Assigned(FAdapter) then
  begin
    Result.Status := esFailed;
    Result.ErrorMessage := 'LLM adapter not configured';
    Exit;
  end;

  LLMResult := FAdapter.ExecuteFromAction(Action, Context);

  if LLMResult.Success then
  begin
    Result.Status := esCompleted;
    // Store response in outputs
    Result.Outputs := TDictionary<string, TVariableValue>.Create;
    Result.Outputs.Add('content', TVariableValue.FromString(LLMResult.Content));
    Result.Outputs.Add('input_tokens', TVariableValue.FromInteger(LLMResult.InputTokens));
    Result.Outputs.Add('output_tokens', TVariableValue.FromInteger(LLMResult.OutputTokens));
    Result.Outputs.Add('duration_ms', TVariableValue.FromInteger(LLMResult.DurationMs));
  end
  else
  begin
    Result.Status := esFailed;
    Result.ErrorMessage := LLMResult.ErrorMessage;
  end;
end;

function TLLMActionExecutor.GetActionType: TActionType;
begin
  Result := atLLM;
end;

{ Helper }

procedure RegisterLLMExecutor(Executor: TWorkflowExecutor; LLM: TDeepBaseLLM);
var
  Adapter: TUniFlowLLMAdapter;
  LLMExecutor: TLLMActionExecutor;
begin
  Adapter := TUniFlowLLMAdapter.Create(LLM, False);
  LLMExecutor := TLLMActionExecutor.Create(Adapter, True);
  Executor.RegisterActionExecutor(LLMExecutor);
end;

end.
