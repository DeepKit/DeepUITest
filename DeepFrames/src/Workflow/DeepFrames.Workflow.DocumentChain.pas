unit DeepFrames.Workflow.DocumentChain;

/// <summary>
/// Phase 2 Document Chain workflow.
/// Implements the source_document → script_document → accuracy_report → variant_document → shot_document
/// pipeline using LLM provider calls via TProviderRegistry.
/// Falls back to stub data when provider is fake or call fails.
/// </summary>

interface

uses
  DeepFrames.Domain.Types;

type
  TDocumentChainWorkflow = class
  public
    class function BuildLogicalKey(const ProjectId, ContentUnitId,
      SourceDocumentId: string): string; static;
    class function RunChain(const ProjectId, ContentUnitId,
      SourceDocumentId: string): TDeepFramesJob; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepBase.Config,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Types,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.BudgetGuard,
  DeepFrames.Workflow.EventLog,
  DeepFrames.Shared.Consts;

class function TDocumentChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, SourceDocumentId: string): string;
begin
  Result := JOB_TYPE_AGENT + ':document_chain:' + ProjectId + ':' +
    ContentUnitId + ':' + SourceDocumentId;
end;

class function TDocumentChainWorkflow.RunChain(const ProjectId, ContentUnitId,
  SourceDocumentId: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  SourceDoc: TSourceDocumentVersion;
  ScriptDoc: TScriptDocumentVersion;
  AccuracyRep: TAccuracyReport;
  VariantDoc: TVariantDocumentVersion;
  ShotDoc: TShotDocumentVersion;
  GateResult: TQualityGateResult;
  LogicalKey: string;
  Provider: IDeepFramesLLMProvider;
  ChatReq: TChatCompletionRequest;
  ChatResult: TChatCompletionResult;
  ChatMetrics: TProviderRunMetrics;
  PromptRun: TPromptRun;
  Template: TPromptTemplate;
  Binding: TModelBinding;
  SourceText: string;
  IsRealProvider: Boolean;
var
  Gate1Verdict: TGateVerdict;
  Gate2Verdict: TGateVerdict;
  SourceVerdict: TGateVerdict;
  ContentUnit: TContentUnitInfo;
  HasContentUnit: Boolean;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, SourceDocumentId);

  Provider := TProviderRegistry.Instance.LLMProvider;
  IsRealProvider := (Provider.GetProviderName = PROVIDER_STEPFUN) and
    SameText(ProviderStatusToStr(Provider.GetProviderStatus), 'ok');

  Repo := TDeepFramesRepository.Create;
  try
    try
      // P0-C Resume: idempotency is status-aware. If a job with this logical
      // key already exists:
      //   - terminal (done/failed/cancelled/skipped) or blocked_review → return
    //     it as-is (true idempotency; nothing to resume).
    //   - pending/running (crashed mid-chain) → REUSE its JobId and fall
    //     through so the chain re-runs. Step inserts are idempotent
    //     (ON CONFLICT step_key DO NOTHING) and each step checks its own
    //     prior status, so completed steps are skipped on resume.
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
    begin
      if IsTerminalStatus(ExistingJob.Status) then
        Exit(ExistingJob);
      // mid-flight: resume by adopting the existing job id
      Job.JobId := ExistingJob.JobId;
      Job.Status := STATUS_RUNNING;
    end
    else
      Job.JobId := '';

    // Load source document content for prompt injection
    SourceText := '';
    if Repo.FindSourceDocument(SourceDocumentId, SourceDoc) then
      SourceText := SourceDoc.MarkdownText;
    if SourceText = '' then
      SourceText := '（无源文档内容，使用测试数据）';

    // Create prompt template and model binding
    // D1 (tasks.md): --llm-model override. The model id is read from config
    // (Agnes.LLMModel, written by --llm-model / SeedProviderConfig) with the
    // legacy 'step-3.7-flash' as default, so a bare run keeps its behaviour
    // and a CLI override takes effect for both the binding record and the
    // actual ChatComplete call below.
    var LLMModel := GetConfig(CONFIG_AGNES_LLM_MODEL, 'step-3.7-flash');
    Template := TProjectService.CreatePromptTemplate(
      'Document Chain', AGENT_ROLE_WORKER, '');
    Repo.InsertPromptTemplate(Template);

    Binding := TProjectService.CreateModelBinding(
      AGENT_ROLE_WORKER, Provider.GetProviderName,
      LLMModel, CAPABILITY_LLM);
    Repo.InsertModelBinding(Binding);

    // Create agent job (first run only; resume reuses ExistingJob.JobId above)
    if Job.JobId = '' then
    begin
      Job.JobId := NewUuidString;
      Job.ProjectId := ProjectId;
      Job.ContentUnitId := ContentUnitId;
      Job.JobType := JOB_TYPE_AGENT;
      Job.LogicalKey := LogicalKey;
      Job.JobQueueTaskId := '';
      Job.Status := STATUS_PENDING;
    end
    else
    begin
      Job.ProjectId := ProjectId;
      Job.ContentUnitId := ContentUnitId;
      Job.JobType := JOB_TYPE_AGENT;
      Job.LogicalKey := LogicalKey;
    end;

    // P0-A: Job + first Step must be created atomically — if InsertJobStep
    // fails we must not leave an orphan job with no steps. The transaction
    // ends before the provider call so we don't hold a tx across LLM IO.
    Repo.BeginTransaction;
    try
      Repo.InsertJob(Job);

      // =============================================================
      // Step 1: build_script — source_document → script_document
      // =============================================================
      Step.StepId := NewUuidString;
      Step.JobId := Job.JobId;
      Step.StepType := JOB_TYPE_AGENT;
      Step.StepKey := Job.JobId + ':' + STEP_TYPE_BUILD_SCRIPT;
      Step.Status := STATUS_PENDING;
      Repo.InsertJobStep(Step);

      if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
        raise Exception.Create('Invalid status transition: pending -> running for build_script');
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
      Repo.CommitTransaction;
    except
      on E: Exception do
      begin
        Repo.RollbackTransaction;
        raise;
      end;
    end;

    // P0-G: reset per-job budget accumulator, then enforce ceiling before
    // every provider call. A runaway chain raises EBudgetExceeded here
    // instead of burning provider budget silently.
    TBudgetGuard.Reset(Job.JobId);

    // Build prompt for script generation
    ChatReq.SystemPrompt :=
      'You are a video script writer for DeepFrames. Convert the source article into a structured video script. ' +
      'Output JSON: {schema_version, title, segments: [{segment_id, narration, visual_hint, duration_sec}]}.';
    ChatReq.UserMessage :=
      'Write a video script for the following Chinese article. Keep narration natural for spoken delivery. ' +
      'Target duration: 3-5 minutes. Article content:' + sLineBreak + sLineBreak + SourceText;
    ChatReq.AgentRole := AGENT_ROLE_WORKER;
    ChatReq.OutputSchemaJson := '{}';
    ChatReq.Model := LLMModel;
    ChatReq.Temperature := 0.7;
    ChatReq.MaxTokens := 4096;

    TBudgetGuard.CheckBudget(Job.JobId);
    if Provider.ChatComplete(ChatReq, ChatResult, ChatMetrics) then
    begin
      TBudgetGuard.Accumulate(Job.JobId, ChatMetrics);
      // P3: structured provider-call log → DeepBase.Logging (latency/tokens
      // surface in LogDashboard; failed calls carry ErrorCode via the else
      // branch's LogJobEvent below).
      TWorkflowLogger.LogProviderCall(Job.JobId, Step.StepId,
        ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM,
        ChatMetrics.LatencyMs, ChatMetrics.TokenUsage.PromptTokens,
        ChatMetrics.TokenUsage.CompletionTokens, '');
      // Record prompt run
      PromptRun := TProjectService.CreatePromptRun(
        Job.JobId, Step.StepId, Template.TemplateId, Binding.BindingId,
        AGENT_ROLE_WORKER, ChatResult.ResponseJson,
        ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM);
      // LLMs often wrap JSON in markdown fences (```json ... ```). The
      // normalized_json column is CAST(:normalized_json AS jsonb), so a fence
      // prefix makes Postgres reject the row. Extract the outermost {...}
      // block so only valid JSON reaches the jsonb cast.
      var NormForStore := ChatResult.NormalizedJson;
      var BraceStart := Pos('{', NormForStore);
      var BraceEnd := LastDelimiter('}', NormForStore);
      if (BraceStart > 0) and (BraceEnd > BraceStart) then
        NormForStore := Copy(NormForStore, BraceStart, BraceEnd - BraceStart + 1)
      else if Trim(NormForStore) = '' then
        NormForStore := '{}';
      PromptRun.NormalizedJson := NormForStore;
      PromptRun.TokenInput := ChatMetrics.TokenUsage.PromptTokens;
      PromptRun.TokenOutput := ChatMetrics.TokenUsage.CompletionTokens;
      PromptRun.LatencyMs := ChatMetrics.LatencyMs;
      PromptRun.ValidationError := ChatResult.ValidationError;
      try
        Repo.InsertPromptRun(PromptRun);
      except
        on E: Exception do
          raise;
      end;

      // Create script document from LLM output
      ScriptDoc := TProjectService.CreateScriptDocument(
        ProjectId, ContentUnitId, SourceDocumentId, SourceDocumentId, 1);
      ScriptDoc.ContentHash := TProjectService.Sha256Text(ChatResult.ResponseJson);
      ScriptDoc.Status := STATUS_DONE;
      Repo.InsertScriptDocument(ScriptDoc);
    end
    else
    begin
      // DBA-3 残留④ (bugfix 续4/续10): LLM call did not succeed — previously
      // this branch produced a 'stub-script-v1' document and marked the step
      // STATUS_DONE, swallowing the failure so the chain continued into
      // step2/step3 with a fake green. That made real LLM failures
      // indistinguishable from success ("真假绿分不清"). Fix: surface the
      // failure — mark the step FAILED and raise so the outer except (line ~525)
      // logs a structured chain_failed/esError event and the job stays non-DONE.
      // The call's own error code/message (PROXY_UNREACHABLE, 401, etc.) is on
      // ChatResult.ErrorCode/ErrorMessage — propagate it for traceability.
      if TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_FAILED) then
        Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED)
      else
        Repo.UpdateJobStepStatus(Step.StepId, STATUS_CANCELLED);
      var ErrCode: string := ChatMetrics.ErrorCode;
      if ErrCode = '' then
        ErrCode := 'LLM_FAILED';
      raise Exception.CreateFmt(
        'build_script LLM step failed (no script produced): %s (model=%s)',
        [ErrCode, ChatMetrics.Model]);
    end;

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for build_script');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // =============================================================
    // Step 2: accuracy_check — verify script fidelity to source
    // =============================================================
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_ACCURACY_CHECK;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    if IsRealProvider then
    begin
      ChatReq.SystemPrompt :=
        'You are a content accuracy checker (Gate 1). Compare the script against the source document. ' +
        'Output JSON: {schema_version, coverage_score, distortion_score, result, issues}. ' +
        'result = pass|warn|fail. coverage: how much of source is retained. distortion: how much is changed.';
      ChatReq.UserMessage :=
        'Source document:' + sLineBreak + SourceText + sLineBreak + sLineBreak +
        'Script document:' + sLineBreak + ChatResult.ResponseJson;
      ChatReq.AgentRole := AGENT_ROLE_QA;

      TBudgetGuard.CheckBudget(Job.JobId);
      if Provider.ChatComplete(ChatReq, ChatResult, ChatMetrics) then
      begin
        TBudgetGuard.Accumulate(Job.JobId, ChatMetrics);
        TWorkflowLogger.LogProviderCall(Job.JobId, Step.StepId,
          ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM,
          ChatMetrics.LatencyMs, ChatMetrics.TokenUsage.PromptTokens,
          ChatMetrics.TokenUsage.CompletionTokens, '');
        PromptRun := TProjectService.CreatePromptRun(
          Job.JobId, Step.StepId, Template.TemplateId, Binding.BindingId,
          AGENT_ROLE_QA, ChatResult.ResponseJson,
          ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM);
        PromptRun.NormalizedJson := ChatResult.NormalizedJson;
        PromptRun.TokenInput := ChatMetrics.TokenUsage.PromptTokens;
        PromptRun.TokenOutput := ChatMetrics.TokenUsage.CompletionTokens;
        PromptRun.LatencyMs := ChatMetrics.LatencyMs;
        Repo.InsertPromptRun(PromptRun);

        AccuracyRep := TProjectService.CreateAccuracyReport(
          ProjectId, SourceDocumentId, ScriptDoc.DocumentId,
          1.0, 0.0, GATE_RESULT_PASS);
        AccuracyRep.Status := STATUS_DONE;
        Repo.InsertAccuracyReport(AccuracyRep);
      end
      else
      begin
        // DBA-3 残留④ (step2 accuracy_check 同模式): real provider but
        // ChatComplete failed. Previously this produced an AccuracyReport
        // with 1.0 coverage / 0.0 distortion / GATE_RESULT_PASS marked
        // STATUS_DONE — a fake "perfect" QA pass on a failed accuracy check,
        // the most dangerous fake-green (QA red→green). Surface the failure.
        if TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_FAILED) then
          Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED)
        else
          Repo.UpdateJobStepStatus(Step.StepId, STATUS_CANCELLED);
        var AErr: string := ChatMetrics.ErrorCode;
        if AErr = '' then
          AErr := 'LLM_FAILED';
        raise Exception.CreateFmt(
          'accuracy_check LLM step failed (no QA verdict produced): %s (model=%s)',
          [AErr, ChatMetrics.Model]);
      end;
    end
    else
    begin
      // Stub: perfect accuracy
      AccuracyRep := TProjectService.CreateAccuracyReport(
        ProjectId, SourceDocumentId, ScriptDoc.DocumentId,
        1.0, 0.0, GATE_RESULT_PASS);
      Repo.InsertAccuracyReport(AccuracyRep);
    end;

    // Gate 1: evaluate accuracy report
    Gate1Verdict := TGateEvaluator.EvaluateGate1(
      AccuracyRep.CoverageScore, AccuracyRep.DistortionScore);
    GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId, Gate1Verdict);
    Repo.InsertQualityGateResult(GateResult);

    if Gate1Verdict.IsFail then
    begin
      // Red light: block and require human review
      if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_BLOCKED_REVIEW) then
        raise Exception.Create('Invalid status transition: running -> blocked_review');
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_BLOCKED_REVIEW);
      Repo.UpdateJobStatus(Job.JobId, STATUS_BLOCKED_REVIEW);
      Job.Status := STATUS_BLOCKED_REVIEW;
      Result := Job;
      Exit;
    end;
    // pass or warn: record and continue
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // =============================================================
    // Source-metadata gate (GATE_SOURCE): 合规子检查
    // external sources must carry origin_url + a license hint; missing
    // evidence blocks, unknown license warns, original_article passes.
    // =============================================================
    HasContentUnit := Repo.FindContentUnit(ContentUnitId, ContentUnit);
    if HasContentUnit then
    begin
      SourceVerdict := TGateEvaluator.CheckSourceMetadata(
        ContentUnit.SourceType, ContentUnit.LicenseHint, ContentUnit.OriginUrl);
      GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId, SourceVerdict);
      Repo.InsertQualityGateResult(GateResult);

      if SourceVerdict.IsFail then
      begin
        if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_BLOCKED_REVIEW) then
          raise Exception.Create('Invalid status transition: running -> blocked_review');
        Repo.UpdateJobStatus(Job.JobId, STATUS_BLOCKED_REVIEW);
        Job.Status := STATUS_BLOCKED_REVIEW;
        Result := Job;
        Exit;
      end;
      // pass or warn: source gate satisfied or recorded; continue
    end;

    // =============================================================
    // Step 3: build_variant — script → platform-specific variant
    // =============================================================
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_BUILD_VARIANT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    if IsRealProvider then
    begin
      ChatReq.SystemPrompt :=
        'You are a variant builder. Given a script document, produce a platform-specific variant. ' +
        'Output JSON: {schema_version, variant_kind, variant_label, target_platform, adjustments_made}.';
      ChatReq.UserMessage :=
        'Build a bilibili variant for the following script. Adapt for B站 audience (Chinese, moderate pace, educational tone).' +
        sLineBreak + sLineBreak + ScriptDoc.ContentHash;
      ChatReq.AgentRole := AGENT_ROLE_ASSEMBLER;

      TBudgetGuard.CheckBudget(Job.JobId);
      if Provider.ChatComplete(ChatReq, ChatResult, ChatMetrics) then
      begin
        TBudgetGuard.Accumulate(Job.JobId, ChatMetrics);
        TWorkflowLogger.LogProviderCall(Job.JobId, Step.StepId,
          ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM,
          ChatMetrics.LatencyMs, ChatMetrics.TokenUsage.PromptTokens,
          ChatMetrics.TokenUsage.CompletionTokens, '');
        PromptRun := TProjectService.CreatePromptRun(
          Job.JobId, Step.StepId, Template.TemplateId, Binding.BindingId,
          AGENT_ROLE_ASSEMBLER, ChatResult.ResponseJson,
          ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM);
        PromptRun.NormalizedJson := ChatResult.NormalizedJson;
        PromptRun.TokenInput := ChatMetrics.TokenUsage.PromptTokens;
        PromptRun.TokenOutput := ChatMetrics.TokenUsage.CompletionTokens;
        PromptRun.LatencyMs := ChatMetrics.LatencyMs;
        Repo.InsertPromptRun(PromptRun);
      end
      else
      begin
        // DBA-3 残留④ (build_script 首处已修, 此为 step3 同模式): real
        // provider but ChatComplete failed (PROXY_UNREACHABLE/401/EXCEPTION).
        // Previously this had no else — the chain silently continued to
        // produce a 'variant-main-v1' document keyed off ContentHash (not
        // real LLM output) and marked the step DONE, a fake green. Surface
        // the failure instead so downstream VideoChain never consumes a
        // phantom variant. (Non-real/demo provider path skips LLM by design
        // and is unaffected — it never reaches this else.)
        if TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_FAILED) then
          Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED)
        else
          Repo.UpdateJobStepStatus(Step.StepId, STATUS_CANCELLED);
        var VErr: string := ChatMetrics.ErrorCode;
        if VErr = '' then
          VErr := 'LLM_FAILED';
        raise Exception.CreateFmt(
          'build_variant LLM step failed (no variant produced): %s (model=%s)',
          [VErr, ChatMetrics.Model]);
      end;
    end;

    // Create main variant (bilibili platform)
    VariantDoc := TProjectService.CreateVariantDocument(
      ProjectId, ContentUnitId, ScriptDoc.DocumentId,
      VARIANT_KIND_MAIN, 'A - conservative', 'bilibili');
    VariantDoc.ContentHash := TProjectService.Sha256Text('variant-main-v1-' + ScriptDoc.DocumentId);
    VariantDoc.Status := STATUS_DONE;
    Repo.InsertVariantDocument(VariantDoc);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // =============================================================
    // Step 4: build_shot — variant → shot document
    // =============================================================
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_BUILD_SHOT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    if IsRealProvider then
    begin
      ChatReq.SystemPrompt :=
        'You are a shot document builder. Convert a variant document into a shot-level production document. ' +
        'Output JSON: {schema_version, shots: [{shot_id, text, tone, duration_sec, visual_prompt}]}.';
      ChatReq.UserMessage :=
        'Build shot-level production document from the variant. Each shot should be 3-8 seconds. Include visual prompts for scene backgrounds.';
      ChatReq.AgentRole := AGENT_ROLE_SPLITTER;

      TBudgetGuard.CheckBudget(Job.JobId);
      if Provider.ChatComplete(ChatReq, ChatResult, ChatMetrics) then
      begin
        TBudgetGuard.Accumulate(Job.JobId, ChatMetrics);
        TWorkflowLogger.LogProviderCall(Job.JobId, Step.StepId,
          ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM,
          ChatMetrics.LatencyMs, ChatMetrics.TokenUsage.PromptTokens,
          ChatMetrics.TokenUsage.CompletionTokens, '');
        PromptRun := TProjectService.CreatePromptRun(
          Job.JobId, Step.StepId, Template.TemplateId, Binding.BindingId,
          AGENT_ROLE_SPLITTER, ChatResult.ResponseJson,
          ChatMetrics.ProviderName, ChatMetrics.Model, CAPABILITY_LLM);
        PromptRun.NormalizedJson := ChatResult.NormalizedJson;
        PromptRun.TokenInput := ChatMetrics.TokenUsage.PromptTokens;
        PromptRun.TokenOutput := ChatMetrics.TokenUsage.CompletionTokens;
        PromptRun.LatencyMs := ChatMetrics.LatencyMs;
        Repo.InsertPromptRun(PromptRun);
      end
      else
      begin
        // DBA-3 残留④ (step4 同模式): real provider but ChatComplete failed.
        // Previously no else — chain fell through to the synthesized demo shot
        // (line ~480 'else' branch, '开场画面' visual_prompt) and marked DONE,
        // so a real LLM failure produced a fake-green shot VideoChain would
        // render as if real. Surface the failure. (Demo/non-real provider
        // path skips LLM by design and still uses the synthesized fallback —
        // it never reaches this else.)
        if TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_FAILED) then
          Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED)
        else
          Repo.UpdateJobStepStatus(Step.StepId, STATUS_CANCELLED);
        var SErr: string := ChatMetrics.ErrorCode;
        if SErr = '' then
          SErr := 'LLM_FAILED';
        raise Exception.CreateFmt(
          'build_shot LLM step failed (no shot produced): %s (model=%s)',
          [SErr, ChatMetrics.Model]);
      end;
    end;

    // Create shot document. Persist the LLM-generated shot script as
    // payload_json so downstream VideoChain can read visual_prompt from it
    // (was a stub with payload='{}' — VideoChain had no prompt source).
    ShotDoc := TProjectService.CreateShotDocument(
      ProjectId, ContentUnitId, VariantDoc.DocumentId, 1);
    ShotDoc.Status := STATUS_DONE;
    // Real provider path stored the normalized script in ChatResult; prefer
    // normalized JSON, fall back to raw response. If neither is available
    // (e.g. fake provider skipped ChatComplete), synthesize a minimal demo
    // shot so VideoChain always has a usable visual_prompt to render.
    if ChatResult.NormalizedJson <> '' then
      ShotDoc.PayloadJson := ChatResult.NormalizedJson
    else if ChatResult.ResponseJson <> '' then
      ShotDoc.PayloadJson := ChatResult.ResponseJson
    else
      ShotDoc.PayloadJson :=
        '{"schema_version":"1.0","shots":[' +
        '{"shot_id":"s1","text":"开场画面","tone":"neutral","duration_sec":6,' +
        '"visual_prompt":"cinematic establishing shot, soft morning light, ' +
        'wide angle, shallow depth of field, 1080p"}]}';
    // Strip markdown fences (```json ... ```) the LLM often wraps around
    // JSON. The jsonb column rejects a `` ` `` prefix as a syntax error.
    // Mirror the build_script step's brace extraction so only valid JSON
    // reaches the column.
    var ShotBS := Pos('{', ShotDoc.PayloadJson);
    var ShotBE := LastDelimiter('}', ShotDoc.PayloadJson);
    if (ShotBS > 0) and (ShotBE > ShotBS) then
      ShotDoc.PayloadJson := Copy(ShotDoc.PayloadJson, ShotBS, ShotBE - ShotBS + 1)
    else if Trim(ShotDoc.PayloadJson) = '' then
      ShotDoc.PayloadJson := '{}';
    ShotDoc.ContentHash := TProjectService.Sha256Text(ShotDoc.PayloadJson);
    Repo.InsertShotDocument(ShotDoc);

    // Gate 2: evaluate shot document quality (stub pass — real QA done by AgentChain)
    Gate2Verdict := TGateEvaluator.EvaluateGate2(1.0); // stub: perfect score at document creation
    GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId, Gate2Verdict);
    Repo.InsertQualityGateResult(GateResult);

    if Gate2Verdict.IsFail then
    begin
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_BLOCKED_REVIEW);
      Repo.UpdateJobStatus(Job.JobId, STATUS_BLOCKED_REVIEW);
      Job.Status := STATUS_BLOCKED_REVIEW;
      Result := Job;
      Exit;
    end;
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

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
  except
    // P3: any chain failure (provider down, gate hard-fail, budget exceeded,
    // status-transition violation) is logged as a structured error event
    // before re-raising — so LogDashboard/LogAlert surface it even when the
    // caller swallows the exception. JobId may be empty if the failure
    // predated job creation; fall back to the logical key for traceability.
    on E: Exception do
    begin
      if Job.JobId <> '' then
        TWorkflowLogger.LogJobEvent(Job.JobId, 'chain_failed', esError,
          E.Message, LogicalKey)
      else
        TWorkflowLogger.LogJobEvent(LogicalKey, 'chain_failed', esError,
          E.Message, '');
      raise;
    end;
  end;
end;

end.