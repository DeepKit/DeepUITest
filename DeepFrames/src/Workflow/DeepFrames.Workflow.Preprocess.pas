unit DeepFrames.Workflow.Preprocess;

interface

uses
  DeepFrames.Domain.Types;

type
  TPreprocessWorkflow = class
  public
    class function BuildLogicalKey(const ProjectId, ContentUnitId,
      SourceDocumentId, ScriptPolicyHash: string): string; static;
    class function RunPreprocess(const ProjectId, ContentUnitId,
      SourceDocumentId: string; const ScriptPolicyHash: string = 'phase1-local'): TDeepFramesJob; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepBase.DB.JobQueue,
  DeepFrames.Persistence.Repository,
  DeepFrames.Shared.Consts;

class function TPreprocessWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, SourceDocumentId, ScriptPolicyHash: string): string;
begin
  Result := Format('preprocess:%s:%s:%s:%s',
    [ProjectId, ContentUnitId, SourceDocumentId, ScriptPolicyHash]);
end;

class function TPreprocessWorkflow.RunPreprocess(const ProjectId, ContentUnitId,
  SourceDocumentId, ScriptPolicyHash: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Payload: TJSONObject;
  Task: TTaskRec;
  Step: TDeepFramesJobStep;
  LogicalKey: string;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, SourceDocumentId, ScriptPolicyHash);

  Repo := TDeepFramesRepository.Create;
  try
    if not Repo.FindJobByLogicalKey(LogicalKey, Result) then
    begin
      Result.JobId := NewUuidString;
      Result.ProjectId := ProjectId;
      Result.ContentUnitId := ContentUnitId;
      Result.JobType := JOB_TYPE_PREPROCESS;
      Result.LogicalKey := LogicalKey;
      Result.JobQueueTaskId := '';
      Result.Status := STATUS_PENDING;
      Repo.InsertJob(Result);

      Step.StepId := NewUuidString;
      Step.JobId := Result.JobId;
      Step.StepType := STEP_TYPE_PREPROCESS_MAIN;
      Step.StepKey := LogicalKey + ':main';
      Step.Status := STATUS_PENDING;
      Repo.InsertJobStep(Step);
    end;

    Payload := TJSONObject.Create;
    try
      Payload.AddPair('schema_version', APP_SCHEMA_VERSION);
      Payload.AddPair('project_id', ProjectId);
      Payload.AddPair('content_unit_id', ContentUnitId);
      Payload.AddPair('source_document_id', SourceDocumentId);
      Payload.AddPair('script_policy_hash', ScriptPolicyHash);
      TJobQueue.Enqueue(QUEUE_DEEPFRAMES_PREPROCESS, LogicalKey, Payload);
    finally
      Payload.Free;
    end;

    if TJobQueue.Dequeue(QUEUE_DEEPFRAMES_PREPROCESS, Task) then
    try
      Result.JobQueueTaskId := Task.TaskID;
      Repo.UpdateJobQueueTaskId(Result.JobId, Task.TaskID);
      Repo.UpdateJobStatus(Result.JobId, STATUS_RUNNING);
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

      // Phase 1 validates the queue/state path only. Real preprocessing belongs
      // to later document-chain phases and must produce new versions, not mutate.
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);
      Repo.UpdateJobStatus(Result.JobId, STATUS_DONE);
      TJobQueue.Complete(Task.TaskID);
      Result.Status := STATUS_DONE;
    except
      on E: Exception do
      begin
        Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED);
        Repo.UpdateJobStatus(Result.JobId, STATUS_FAILED);
        TJobQueue.Fail(Task.TaskID, E.Message, False);
        raise;
      end;
    end;
  finally
    Task.Clear;
    Repo.Free;
  end;
end;

end.
