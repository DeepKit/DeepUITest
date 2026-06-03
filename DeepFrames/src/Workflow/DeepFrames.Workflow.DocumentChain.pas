unit DeepFrames.Workflow.DocumentChain;

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
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Shared.Consts;

class function TDocumentChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, SourceDocumentId: string): string;
begin
  Result := JOB_TYPE_AGENT + ':' + ProjectId + ':' + ContentUnitId +
    ':' + SourceDocumentId;
end;

class function TDocumentChainWorkflow.RunChain(const ProjectId, ContentUnitId,
  SourceDocumentId: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  ScriptDoc: TScriptDocumentVersion;
  AccuracyRep: TAccuracyReport;
  VariantDoc: TVariantDocumentVersion;
  ShotDoc: TShotDocumentVersion;
  GateResult: TQualityGateResult;
  LogicalKey: string;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, SourceDocumentId);

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency: if job already exists, return it
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

    // Create agent job
    Job.JobId := NewUuidString;
    Job.ProjectId := ProjectId;
    Job.ContentUnitId := ContentUnitId;
    Job.JobType := JOB_TYPE_AGENT;
    Job.LogicalKey := LogicalKey;
    Job.JobQueueTaskId := '';
    Job.Status := STATUS_PENDING;
    Repo.InsertJob(Job);

    // Step 1: build_script
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_BUILD_SCRIPT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    // Transition step -> running
    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for build_script');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Create stub script_document (Phase 2: no real LLM call)
    ScriptDoc := TProjectService.CreateScriptDocument(
      ProjectId, ContentUnitId, SourceDocumentId, SourceDocumentId, 1);
    ScriptDoc.ContentHash := TProjectService.Sha256Text('stub-script-v1');
    ScriptDoc.Status := STATUS_DONE;
    Repo.InsertScriptDocument(ScriptDoc);

    // Transition step -> done
    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for build_script');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // Step 2: accuracy_check
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_ACCURACY_CHECK;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Create stub accuracy report (perfect scores for Phase 2)
    AccuracyRep := TProjectService.CreateAccuracyReport(
      ProjectId, SourceDocumentId, ScriptDoc.DocumentId,
      1.0, 0.0, GATE_RESULT_PASS);
    Repo.InsertAccuracyReport(AccuracyRep);

    // Gate 1: pass
    GateResult := TProjectService.CreateQualityGateResult(
      Job.JobId, GATE_1, GATE_RESULT_PASS, 1.0);
    Repo.InsertQualityGateResult(GateResult);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // Step 3: build_variant
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_BUILD_VARIANT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Create main variant (bilibili platform)
    VariantDoc := TProjectService.CreateVariantDocument(
      ProjectId, ContentUnitId, ScriptDoc.DocumentId,
      VARIANT_KIND_MAIN, 'A - conservative', 'bilibili');
    VariantDoc.ContentHash := TProjectService.Sha256Text('stub-variant-main-v1');
    VariantDoc.Status := STATUS_DONE;
    Repo.InsertVariantDocument(VariantDoc);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // Step 4: build_shot
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := JOB_TYPE_AGENT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_BUILD_SHOT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Create stub shot document
    ShotDoc := TProjectService.CreateShotDocument(
      ProjectId, ContentUnitId, VariantDoc.DocumentId, 1);
    ShotDoc.ContentHash := TProjectService.Sha256Text('stub-shot-v1');
    ShotDoc.Status := STATUS_DONE;
    Repo.InsertShotDocument(ShotDoc);

    // Gate 2: pass
    GateResult := TProjectService.CreateQualityGateResult(
      Job.JobId, GATE_2, GATE_RESULT_PASS, 1.0);
    Repo.InsertQualityGateResult(GateResult);

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
end;

end.
