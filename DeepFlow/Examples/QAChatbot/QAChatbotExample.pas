{ ============================================================================
  Q&A Chatbot Example

  Demonstrates:
    - Setting up Commander with intents
    - Loading workflow from JSON
    - Processing user requests
    - Managing sessions

  Usage:
    1. Configure LLM provider in DeepBase
    2. Run the application
    3. Type questions, get answers
  ============================================================================ }

program QAChatbotExample;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  UniFlow.Workflow.Definition,
  UniFlow.Workflow.Context,
  UniFlow.Workflow.Executor,
  UniFlow.Session.Types,
  UniFlow.Session.Manager,
  UniFlow.Roles.Commander,
  UniFlow.AI.Adapter;

var
  SessionManager: TSessionManager;
  WorkflowRegistry: TSimpleWorkflowRegistry;
  Commander: TCommander;

procedure SetupCommander;
begin
  // Create session manager
  SessionManager := TSessionManager.Create;
  SessionManager.Config.MaxMessageHistory := 50;
  SessionManager.Config.SessionTimeoutMinutes := 60;

  // Create workflow registry
  WorkflowRegistry := TSimpleWorkflowRegistry.Create;

  // Load Q&A workflow
  WorkflowRegistry.RegisterWorkflowFromFile(
    ExtractFilePath(ParamStr(0)) + 'workflow_qa.json'
  );

  // Create commander
  Commander := TCommander.Create(SessionManager, WorkflowRegistry);

  // Register intents
  Commander.RegisterIntent('question',
    ['what|how|why|when|where|who|which|can|could|would|is|are|do|does'],
    ['what', 'how', 'why', 'explain', 'tell me', 'help'],
    10);

  Commander.RegisterIntent('greeting',
    ['hello|hi|hey|greetings'],
    ['hello', 'hi', 'hey', 'good morning', 'good afternoon'],
    5);

  Commander.RegisterIntent('goodbye',
    ['bye|goodbye|exit|quit'],
    ['bye', 'goodbye', 'see you', 'exit', 'quit'],
    5);

  // Route intents to workflows
  Commander.RegisterRoute('question', 'workflow_qa');
  Commander.RegisterRoute('greeting', 'workflow_qa');

  // Default workflow for unknown intents
  Commander.DefaultWorkflowId := 'workflow_qa';

  // Configure
  Commander.AutoCreateSession := True;
  Commander.MaxMessageLength := 5000;

  // Register LLM executor
  RegisterLLMExecutor;

  // Event handlers
  Commander.OnIntentRecognized := procedure(Intent: TIntent)
  begin
    WriteLn(Format('  [Intent: %s, Confidence: %.2f]',
      [Intent.Name, Intent.Confidence]));
  end;
end;

procedure RunChatLoop;
var
  Input: string;
  Response: TCommanderResponse;
  SessionId: string;
begin
  SessionId := '';  // Will be auto-created

  WriteLn('');
  WriteLn('Q&A Chatbot');
  WriteLn('===========');
  WriteLn('Type your questions. Type "exit" to quit.');
  WriteLn('');

  repeat
    Write('You: ');
    ReadLn(Input);

    if (LowerCase(Trim(Input)) = 'exit') or
       (LowerCase(Trim(Input)) = 'quit') then
    begin
      WriteLn('Goodbye!');
      Break;
    end;

    if Trim(Input) = '' then
      Continue;

    try
      Response := Commander.ProcessMessage(SessionId, Input);
      try
        // Update session ID
        if SessionId = '' then
          SessionId := Response.SessionId;

        // Display response
        case Response.Status of
          rsSuccess:
            WriteLn('Bot: ' + Response.Message);
          rsError:
            WriteLn('Error: ' + Response.ErrorMessage);
          rsNeedsInput:
            WriteLn('Bot: ' + Response.Message);
        end;
      finally
        Response.Free;
      end;
    except
      on E: Exception do
        WriteLn('Error: ' + E.Message);
    end;

    WriteLn('');
  until False;
end;

procedure Cleanup;
begin
  Commander.Free;
  WorkflowRegistry.Free;
  SessionManager.Free;
end;

begin
  try
    SetupCommander;
    try
      RunChatLoop;
    finally
      Cleanup;
    end;
  except
    on E: Exception do
    begin
      WriteLn('Fatal error: ' + E.Message);
      ReadLn;
    end;
  end;
end.
