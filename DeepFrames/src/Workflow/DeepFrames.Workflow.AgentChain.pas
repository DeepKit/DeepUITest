unit DeepFrames.Workflow.AgentChain;

interface

uses
  DeepFrames.Domain.Types;

type
  TAgentChainWorkflow = class
  public
    class function BuildLogicalKey(const ProjectId, ContentUnitId,
      ShotDocumentId: string): string; static;
    class function RunChain(const ProjectId, ContentUnitId,
      ShotDocumentId: string): TDeepFramesJob; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Types,
  DeepFrames.Shared.Consts;

class function TAgentChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, ShotDocumentId: string): string;
begin
  Result := JOB_TYPE_AGENT + ':agent_chain:' + ProjectId + ':' +
    ContentUnitId + ':' + ShotDocumentId;
end;

class function TAgentChainWorkflow.RunChain(const ProjectId, ContentUnitId,
  ShotDocumentId: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  Template: TPromptTemplate;
  Binding: TModelBinding;
  PromptRun: TPromptRun;
  EvalResult: TEvalResult;
  GateResult: TQualityGateResult;
  LogicalKey: string;
  Provider: IDeepFramesLLMProvider;
  ChatResult: TChatCompletionResult;
  ChatMetrics: TProviderRunMetrics;
  ChatReq: TChatCompletionRequest;
  AgentSteps: array of record
    StepType: string;
    Role: string;
  end;
  I: Integer;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);

  // Define agent pipeline steps
  SetLength(AgentSteps, 5);
  AgentSteps[0].StepType := STEP_TYPE_AGENT_SPLITTER;
  AgentSteps[0].Role := AGENT_ROLE_SPLITTER;
  AgentSteps[1].StepType := STEP_TYPE_AGENT_WORKER;
  AgentSteps[1].Role := AGENT_ROLE_WORKER;
  AgentSteps[2].StepType := STEP_TYPE_AGENT_ASSEMBLER;
  AgentSteps[2].Role := AGENT_ROLE_ASSEMBLER;
  AgentSteps[3].StepType := STEP_TYPE_AGENT_QA;
  AgentSteps[3].Role := AGENT_ROLE_QA;
  AgentSteps[4].StepType := STEP_TYPE_STYLE_KEEPER;
  AgentSteps[4].Role := AGENT_ROLE_STYLE_KEEPER;

  // Get LLM provider
  Provider := TProviderRegistry.Instance.LLMProvider;

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency: if job already exists, return it
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

    // Create agent chain job
    Job.JobId := NewUuidString;
    Job.ProjectId := ProjectId;
    Job.ContentUnitId := ContentUnitId;
    Job.JobType := JOB_TYPE_AGENT;
    Job.LogicalKey := LogicalKey;
    Job.JobQueueTaskId := '';
    Job.Status := STATUS_PENDING;
    Repo.InsertJob(Job);

    // Ensure default prompt template and model binding exist
    Template := TProjectService.CreatePromptTemplate(
      'Default Splitter', AGENT_ROLE_SPLITTER, '');
    Repo.InsertPromptTemplate(Template);

    Binding := TProjectService.CreateModelBinding(
      AGENT_ROLE_SPLITTER, Provider.GetProviderName,
      'stepfun-flash-3.5', CAPABILITY_LLM);
    Repo.InsertModelBinding(Binding);

    // Run each agent step through LLM provider
    for I := 0 to High(AgentSteps) do
    begin
      // Create step
      Step.StepId := NewUuidString;
      Step.JobId := Job.JobId;
      Step.StepType := AgentSteps[I].StepType;
      Step.StepKey := Job.JobId + ':' + AgentSteps[I].StepType + ':' + IntToStr(I + 1);
      Step.Status := STATUS_PENDING;
      Repo.InsertJobStep(Step);

      // Transition step -> running
      if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
        raise Exception.Create('Invalid status transition: pending -> running for ' + AgentSteps[I].StepType);
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

      // Build chat request — system prompt carries agent role for fake provider routing
      ChatReq.SystemPrompt := AgentSteps[I].Role;
      ChatReq.UserMessage := 'Execute agent step: ' + AgentSteps[I].StepType;
      ChatReq.OutputSchemaJson := '{}';
      ChatReq.Model := 'stepfun-flash-3.5';
      ChatReq.Temperature := 0.7;
      ChatReq.MaxTokens := 4096;

      // Call LLM provider
      if not Provider.ChatComplete(ChatReq, ChatResult, ChatMetrics) then
        raise Exception.Create('LLM call failed for ' + AgentSteps[I].Role + ': ' + ChatMetrics.ErrorCode);

      // Record prompt run
      PromptRun := TProjectService.CreatePromptRun(
        Job.JobId, Step.StepId, Template.TemplateId, Binding.BindingId,
        AgentSteps[I].Role, ChatResult.ResponseJson,
        ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM);
      PromptRun.NormalizedJson := ChatResult.NormalizedJson;
      PromptRun.ValidationError := ChatResult.ValidationError;
      PromptRun.RepairCount := ChatResult.RepairCount;
      PromptRun.TokenInput := ChatMetrics.TokenUsage.PromptTokens;
      PromptRun.TokenOutput := ChatMetrics.TokenUsage.CompletionTokens;
      PromptRun.LatencyMs := ChatMetrics.LatencyMs;
      Repo.InsertPromptRun(PromptRun);

      // Create eval result for QA and Style Keeper steps
      if (AgentSteps[I].Role = AGENT_ROLE_QA) or
         (AgentSteps[I].Role = AGENT_ROLE_STYLE_KEEPER) then
      begin
        EvalResult := TProjectService.CreateEvalResult(
          Job.JobId, AgentSteps[I].Role, 0.95);
        EvalResult.JobStepId := Step.StepId;
        EvalResult.PromptRunId := PromptRun.RunId;
        if AgentSteps[I].Role = AGENT_ROLE_QA then
        begin
          EvalResult.Gate := GATE_2;
          EvalResult.GateResult := GATE_RESULT_PASS;
        end;
        Repo.InsertEvalResult(EvalResult);
      end;

      // Transition step -> done
      if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
        raise Exception.Create('Invalid status transition: running -> done for ' + AgentSteps[I].StepType);
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);
    end;

    // Gate 2 result
    GateResult := TProjectService.CreateQualityGateResult(
      Job.JobId, GATE_2, GATE_RESULT_PASS, 0.95);
    Repo.InsertQualityGateResult(GateResult);

    // Transition job -> running -> done
    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_RUNNING);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_DONE);

    Job.Status := STATUS_DONE;
    Result := Job;
  finally
    Repo.Free;
  end;
end;

end.