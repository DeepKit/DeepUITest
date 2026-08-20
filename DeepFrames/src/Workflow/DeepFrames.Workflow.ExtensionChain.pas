unit DeepFrames.Workflow.ExtensionChain;

interface

uses
  DeepFrames.Domain.Types;

type
  TExtensionChainWorkflow = class
  public
    /// <summary>Register a new content type adapter and run readiness checks.</summary>
    class function RegisterAdapter(const ContentType, DisplayName,
      Description, AdapterClass: string): TContentTypeAdapter; static;

    /// <summary>Run readiness validation for an existing adapter.</summary>
    class function RunReadinessCheck(const AdapterId: string): TReadinessReport; static;

    /// <summary>Create stub BGM track in the default library.</summary>
    class function CreateStubBgmTrack(const Title, Artist, Genre: string): TBgmTrack; static;

    /// <summary>Run the full extension chain (register + readiness + BGM stub).</summary>
    class function RunExtensionChain: TDeepFramesJob; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Workflow.ReadinessChecker,
  DeepFrames.Shared.Consts;

{ TExtensionChainWorkflow }

class function TExtensionChainWorkflow.RegisterAdapter(const ContentType,
  DisplayName, Description, AdapterClass: string): TContentTypeAdapter;
var
  Repo: TDeepFramesRepository;
  Existing: TContentTypeAdapter;
begin
  Repo := TDeepFramesRepository.Create;
  try
    // Check if adapter already exists
    if Repo.FindContentTypeAdapter(ContentType, Existing) then
      Exit(Existing);

    Result := TProjectService.CreateContentTypeAdapter(
      ContentType, DisplayName, Description, AdapterClass);
    Repo.InsertContentTypeAdapter(Result);
  finally
    Repo.Free;
  end;
end;

class function TExtensionChainWorkflow.RunReadinessCheck(
  const AdapterId: string): TReadinessReport;
var
  Repo: TDeepFramesRepository;
  Adapter: TContentTypeAdapter;
  Aggregate: TAggregateReadiness;
begin
  Repo := TDeepFramesRepository.Create;
  try
    // Load adapter from DB and run real readiness checks
    if Repo.FindContentTypeAdapter('', Adapter) then
    begin
      // FindContentTypeAdapter expects content_type string, not adapter_id.
      // Fall back to loading all adapters and matching by ID.
    end;
    var AllAdapters := Repo.ListContentTypeAdapters;
    for var A in AllAdapters do
      if SameText(A.AdapterId, AdapterId) then
      begin
        Adapter := A;
        Break;
      end;

    Aggregate := TReadinessChecker.Evaluate(Adapter);
    Result := TReadinessChecker.ToReadinessReport(AdapterId, Aggregate);
    Repo.InsertReadinessReport(Result);

    // Activate adapter after passing all readiness checks
    if Result.CheckResult = READINESS_RESULT_PASS then
      Repo.UpdateContentTypeAdapterStatus(AdapterId, ADAPTER_STATUS_ACTIVE);
  finally
    Repo.Free;
  end;
end;

class function TExtensionChainWorkflow.CreateStubBgmTrack(const Title, Artist,
  Genre: string): TBgmTrack;
var
  Repo: TDeepFramesRepository;
  Libraries: TArray<TBgmLibrary>;
  LibraryId: string;
begin
  Repo := TDeepFramesRepository.Create;
  try
    // Find default library
    Libraries := Repo.ListBgmLibraries;
    if Length(Libraries) > 0 then
      LibraryId := Libraries[0].LibraryId
    else
    begin
      // Create default library if none exists
      var Lib := TProjectService.CreateBgmLibrary('Default Library', 'Auto-created default BGM library', True);
      Repo.InsertBgmLibrary(Lib);
      LibraryId := Lib.LibraryId;
    end;

    Result := TProjectService.CreateBgmTrack(LibraryId, Title, Artist, Genre);
    Result.DurationSec := 120.0; // 2 minutes stub
    Result.Bpm := 90;
    Result.KeySignature := 'C major';
    Result.MoodTagsJson := '["calm", "ambient"]';
    Repo.InsertBgmTrack(Result);
  finally
    Repo.Free;
  end;
end;

class function TExtensionChainWorkflow.RunExtensionChain: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  Adapter: TContentTypeAdapter;
  Report: TReadinessReport;
  BgmTrack: TBgmTrack;
  LogicalKey: string;
begin
  LogicalKey := JOB_TYPE_EXTENSION + ':full_chain:1';

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

    // Create extension job
    Job.JobId := NewUuidString;
    Job.ProjectId := '';
    Job.ContentUnitId := '';
    Job.JobType := JOB_TYPE_EXTENSION;
    Job.LogicalKey := LogicalKey;
    Job.JobQueueTaskId := '';
    Job.Status := STATUS_PENDING;
    Repo.InsertJob(Job);

    // Step 1: Register a short_video_script adapter
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_ADAPTER_REGISTER;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_ADAPTER_REGISTER;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for adapter_register');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    Adapter := RegisterAdapter('short_video_script',
      'Short Video Script', 'Adapter for short-form video scripts (Douyin, Xiaohongshu)',
      'TShortVideoScriptAdapter');
    Adapter.SupportedOutputTypesJson := '["video"]';
    Adapter.DefaultPipelineJson :=
      '{"document_chain": true, "agent_chain": true, "video_chain": true, "package_chain": true}';

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for adapter_register');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // Step 2: Run readiness check
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_READINESS_CHECK;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_READINESS_CHECK;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for readiness_check');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    Report := RunReadinessCheck(Adapter.AdapterId);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for readiness_check');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // Step 3: Create stub BGM track
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_BGM_SELECT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_BGM_SELECT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for bgm_select');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    BgmTrack := CreateStubBgmTrack('Ambient Background', 'DeepFrames Studio', 'ambient');

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for bgm_select');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // Transition job -> running -> done
    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for extension job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_RUNNING);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for extension job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_DONE);

    Job.Status := STATUS_DONE;
    Result := Job;
  finally
    Repo.Free;
  end;
end;

end.
