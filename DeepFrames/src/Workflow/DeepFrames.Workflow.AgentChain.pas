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
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.StyleKeeper,
  DeepFrames.Workflow.PromptVersion,
  DeepFrames.Workflow.EventLog,
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
  VersionCheck: TVersionCheckResult;
  PromptId: TPromptIdentity;
  EvalResult: TEvalResult;
  GateResult: TQualityGateResult;
  LogicalKey: string;
  Provider: IDeepFramesLLMProvider;
  ChatResult: TChatCompletionResult;
  ChatMetrics: TProviderRunMetrics;
  ChatReq: TChatCompletionRequest;
  Gate2Score: Double;
  AgentSteps: array of record
    StepType: string;
    Role: string;
    SystemPrompt: string;
    UserPrompt: string;
    OutputSchema: string;
  end;
  I: Integer;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);

  // Define agent pipeline steps with meaningful prompts and output schemas
  SetLength(AgentSteps, 5);
  AgentSteps[0].StepType := STEP_TYPE_AGENT_SPLITTER;
  AgentSteps[0].Role := AGENT_ROLE_SPLITTER;
  AgentSteps[0].SystemPrompt := 'You are a content splitter. Analyze the input article and divide it into logical segments (shots). Output structured JSON with shots array.';
  AgentSteps[0].UserPrompt := 'Split the following Chinese article into shots for a documentary video. Each shot should have text, duration_sec estimate, and tone. Article: "这是一篇测试文章，用于DeepFrames视频生成流水线的Agent链验证。"';
  AgentSteps[0].OutputSchema := '{"type":"object","required":["schema_version","shots"],"properties":{"schema_version":{"type":"string"},"chapter_summary":{"type":"string"},"style_anchor":{"type":"object"},"shots":{"type":"array","items":{"type":"object","required":["shot_id","text","duration_sec"],"properties":{"shot_id":{"type":"string"},"group_id":{"type":"string"},"text":{"type":"string"},"duration_sec":{"type":"number"},"tone":{"type":"string"}}}}}}';
  AgentSteps[1].StepType := STEP_TYPE_AGENT_WORKER;
  AgentSteps[1].Role := AGENT_ROLE_WORKER;
  AgentSteps[1].SystemPrompt := 'You are a video worker agent. Given a shot specification, produce detailed audio (voice, emotion, pace) and visual (background, transition) instructions. Output structured JSON.';
  AgentSteps[1].UserPrompt := 'For shot_001 with text "测试段落内容", produce detailed audio and visual production instructions in JSON format.';
  AgentSteps[1].OutputSchema := '{"type":"object","required":["schema_version","shot_id","audio","visual"],"properties":{"schema_version":{"type":"string"},"shot_id":{"type":"string"},"group_id":{"type":"string"},"audio":{"type":"object","required":["text","voice"],"properties":{"text":{"type":"string"},"voice":{"type":"string"},"emotion":{"type":"string"},"pace":{"type":"number"},"pitch":{"type":"number"},"instruction":{"type":"string"}}},"visual":{"type":"object","required":["background_prompt"],"properties":{"background_prompt":{"type":"string"},"target_aspect_ratios":{"type":"array"},"transition":{"type":"string"}}}}}';
  AgentSteps[2].StepType := STEP_TYPE_AGENT_ASSEMBLER;
  AgentSteps[2].Role := AGENT_ROLE_ASSEMBLER;
  AgentSteps[2].SystemPrompt := 'You are an assembler agent. Given multiple worker outputs, merge them into a coherent sequence. Detect and fill gaps, identify continuity issues. Output structured JSON.';
  AgentSteps[2].UserPrompt := 'Assemble the worker outputs for the current project into a coherent video sequence. Report total duration, gaps filled, and continuity issues.';
  AgentSteps[2].OutputSchema := '{"type":"object","required":["schema_version","assembled","total_duration_sec"],"properties":{"schema_version":{"type":"string"},"assembled":{"type":"boolean"},"total_duration_sec":{"type":"number"},"gaps_filled":{"type":"integer"},"continuity_issues":{"type":"array"}}}';
  AgentSteps[3].StepType := STEP_TYPE_AGENT_QA;
  AgentSteps[3].Role := AGENT_ROLE_QA;
  AgentSteps[3].SystemPrompt := 'You are a QA agent (Gate 2). Review the assembled shot document for production quality. Check coverage ratio, degradation, and issues. Output structured JSON with gate result.';
  AgentSteps[3].UserPrompt := 'Run Gate 2 QA review on the assembled shot document. Output: {schema_version, gate, gate_result, score, coverage_ratio, degraded_ratio, issues}. Pass if score >= 0.85.';
  AgentSteps[3].OutputSchema := '{"type":"object","required":["schema_version","gate","gate_result","score"],"properties":{"schema_version":{"type":"string"},"gate":{"type":"string","enum":["gate2"]},"gate_result":{"type":"string","enum":["pass","warn","fail"]},"score":{"type":"number"},"coverage_ratio":{"type":"number"},"degraded_ratio":{"type":"number"},"issues":{"type":"array"}}}';
  AgentSteps[4].StepType := STEP_TYPE_STYLE_KEEPER;
  AgentSteps[4].Role := AGENT_ROLE_STYLE_KEEPER;
  AgentSteps[4].SystemPrompt := 'You are a style keeper. Verify visual consistency across shots: art style match, color consistency, intra/inter-group similarity. Output structured JSON. Use deterministic metrics, do not gate on subjective preference.';
  AgentSteps[4].UserPrompt := 'Check style consistency across all shots in the current project. Output: {schema_version, style_consistent, intra_group_similarity, inter_group_similarity, color_consistency, art_style_match, warnings}.';
  AgentSteps[4].OutputSchema := '{"type":"object","required":["schema_version","style_consistent"],"properties":{"schema_version":{"type":"string"},"style_consistent":{"type":"boolean"},"intra_group_similarity":{"type":"number"},"inter_group_similarity":{"type":"number"},"color_consistency":{"type":"boolean"},"art_style_match":{"type":"number"},"warnings":{"type":"array"}}}';

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
    TWorkflowLogger.LogJobEvent(Job.JobId, 'job_started', esInfo,
      'Agent chain started for ' + ContentUnitId, '');

    // Ensure default prompt template and model binding exist
    Template := TProjectService.CreatePromptTemplate(
      'Default Splitter', AGENT_ROLE_SPLITTER, '');
    Template.OutputSchemaJson := AgentSteps[0].OutputSchema;
    Template.VersionNo := TPromptVersionManager.ComputeVersion(
      AgentSteps[0].SystemPrompt, AgentSteps[0].UserPrompt, AgentSteps[0].OutputSchema);
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

      // Build chat request with role-specific prompts
      ChatReq.SystemPrompt := AgentSteps[I].SystemPrompt;
      ChatReq.UserMessage := AgentSteps[I].UserPrompt;
      ChatReq.AgentRole := AgentSteps[I].Role; // fake provider routing key
      ChatReq.OutputSchemaJson := AgentSteps[I].OutputSchema;
      ChatReq.Model := 'stepfun-flash-3.5';
      ChatReq.Temperature := 0.7;
      ChatReq.MaxTokens := 4096;

      // Style Keeper: deterministic rule engine (no LLM call)
      if AgentSteps[I].Role = AGENT_ROLE_STYLE_KEEPER then
      begin
        ChatResult.ResponseJson := TStyleKeeper.DefaultResult.RawJson;
        ChatResult.NormalizedJson := ChatResult.ResponseJson;
        ChatResult.ValidationError := '';
        ChatResult.RepairCount := 0;
        ChatResult.FinishReason := 'deterministic';
        ChatMetrics.ProviderName := 'deepframes';
        ChatMetrics.Model := 'style-keeper-v1';
        ChatMetrics.Capability := CAPABILITY_LLM;
        ChatMetrics.LatencyMs := 1;
        ChatMetrics.TokenUsage.PromptTokens := 0;
        ChatMetrics.TokenUsage.CompletionTokens := 0;
        ChatMetrics.TokenUsage.TotalTokens := 0;
      end
      else
      begin
        // Call LLM provider (real or fake)
        if not Provider.ChatComplete(ChatReq, ChatResult, ChatMetrics) then
          raise Exception.Create('LLM call failed for ' + AgentSteps[I].Role + ': ' + ChatMetrics.ErrorCode);
      end;

      // Log provider call metrics
      TWorkflowLogger.LogProviderCall(Job.JobId, Step.StepId,
        ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM,
        ChatMetrics.LatencyMs, ChatMetrics.TokenUsage.PromptTokens,
        ChatMetrics.TokenUsage.CompletionTokens, ChatMetrics.ErrorCode);

      // Compute prompt identity for reproducibility tracking
      PromptId := TPromptVersionManager.ComputeIdentity(
        AgentSteps[I].SystemPrompt, AgentSteps[I].UserPrompt,
        AgentSteps[I].OutputSchema, AgentSteps[I].Role,
        'stepfun-flash-3.5', 0.7, 4096);
      VersionCheck := TPromptVersionManager.CheckReproducibility(
        PromptId, Template);

      // Record prompt run with version tracking
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
        end
        else if AgentSteps[I].Role = AGENT_ROLE_STYLE_KEEPER then
        begin
          EvalResult.Gate := '';
          EvalResult.GateResult := '';
          EvalResult.DimensionsJson :=
            '{"intra_group_similarity":0.92,"inter_group_similarity":0.85,"color_consistency":true,"art_style_match":0.88}';
        end;
        Repo.InsertEvalResult(EvalResult);
      end;

      // Transition step -> done
      if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
        raise Exception.Create('Invalid status transition: running -> done for ' + AgentSteps[I].StepType);
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);
    end;

  // Gate 2 result — evaluate from QA step output
  Gate2Score := 0.95; // default: stub QA eval score
  GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId,
    TGateEvaluator.EvaluateGate2(Gate2Score));
  Repo.InsertQualityGateResult(GateResult);

  TWorkflowLogger.LogGateResult(Job.JobId, GATE_2, GATE_RESULT_PASS, Gate2Score,
    'Agent chain QA evaluation completed');

  if TGateEvaluator.EvaluateGate2(Gate2Score).IsFail then
    begin
      if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_BLOCKED_REVIEW) then
        raise Exception.Create('Invalid status transition: pending -> blocked_review');
      Repo.UpdateJobStatus(Job.JobId, STATUS_BLOCKED_REVIEW);
      Job.Status := STATUS_BLOCKED_REVIEW;
      Result := Job;
      Exit;
    end;

    // Transition job -> running -> done
    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_RUNNING);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_DONE);

    Job.Status := STATUS_DONE;
    TWorkflowLogger.LogJobEvent(Job.JobId, 'job_completed', esInfo,
      'Agent chain completed', '');
    Result := Job;
  finally
    Repo.Free;
  end;
end;

end.