unit DeepFrames.Workflow.Resume;

/// <summary>
/// Workflow retry and resume utility.
///
/// P2.9: Supports retrying failed/blocked_review jobs from the last
/// incomplete step without re-running completed steps or producing
/// duplicate business objects.
///
/// Key behaviors:
/// 1. Idempotency: logical_key prevents duplicate job creation
/// 2. Retry: only retries jobs in failed/blocked_review/cancelled states
/// 3. Skip: done/skipped jobs are never retried
/// 4. Resume: finds the last incomplete step and resumes from there
/// 5. Max retries: configurable per-job-type limit
/// </summary>

interface

uses
  DeepFrames.Domain.Types;

type
  /// <summary>Result of a retry attempt.</summary>
  TRetryResult = record
    CanRetry: Boolean;
    Reason: string;           // why can/cannot retry
    ResumedJob: TDeepFramesJob;
    ResumeFromStepIndex: Integer; // 0-based index of first incomplete step, -1 if all done
    PreviousStepCount: Integer;
    RemainingSteps: TArray<string>; // step_types still to run
  end;

  /// <summary>Workflow retry/resume utility.</summary>
  TWorkflowResume = class
  public
    /// <summary>
    /// Check if a job can be retried. Returns TRetryResult with details.
    /// Only retryable: failed, blocked_review, cancelled.
    /// Never retry: done, skipped, running.
    /// </summary>
    class function CanRetryJob(const AJobId: string): TRetryResult; static;

    /// <summary>
    /// Check if a logical key already has a retryable job.
    /// Returns True and fills AJob if an existing retryable job is found.
    /// </summary>
    class function FindRetryableJob(const ALogicalKey: string;
      out AJob: TDeepFramesJob; out AReason: string): Boolean; static;

    /// <summary>
    /// Get the list of step statuses for a job, ordered by creation.
    /// Returns step_types and their current statuses.
    /// </summary>
    class function GetStepStatuses(const AJobId: string;
      out AStepTypes: TArray<string>;
      out AStepStatuses: TArray<string>): Boolean; static;

    /// <summary>
    /// Check if a job status is retryable.
    /// </summary>
    class function IsRetryableStatus(const AStatus: string): Boolean; static;

    /// <summary>
    /// Check if a job status should be skipped on retry.
    /// </summary>
    class function IsSkipStatus(const AStatus: string): Boolean; static;

    /// <summary>
    /// Build a retry logical key suffix for version tracking.
    /// Appends retry count to the base key to produce a new key
    /// that doesn't collide with the original.
    /// </summary>
    class function BuildRetryKey(const ABaseLogicalKey: string;
      ARetryCount: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  DeepFrames.Persistence.Repository,
  DeepFrames.Shared.Consts;

class function TWorkflowResume.CanRetryJob(const AJobId: string): TRetryResult;
var
  Repo: TDeepFramesRepository;
  Jobs: TArray<TDeepFramesJob>;
  Steps: TArray<TDeepFramesJobStep>;
  I: Integer;
  Job: TDeepFramesJob;
  JobFound: Boolean;
  IncompleteCount: Integer;
begin
  Result.CanRetry := False;
  Result.Reason := '';
  Result.ResumeFromStepIndex := -1;
  Result.PreviousStepCount := 0;
  Result.RemainingSteps := nil;

  Repo := TDeepFramesRepository.Create;
  try
    // Find the job
    Jobs := Repo.ListJobs;
    JobFound := False;
    for I := 0 to High(Jobs) do
      if SameText(Jobs[I].JobId, AJobId) then
      begin
        Job := Jobs[I];
        JobFound := True;
        Break;
      end;

    if not JobFound then
    begin
      Result.Reason := 'Job not found';
      Exit;
    end;

    // Check status
    if IsSkipStatus(Job.Status) then
    begin
      Result.Reason := Format('Job status ''%s'' cannot be retried (already done or skipped)', [Job.Status]);
      Exit;
    end;

    if not IsRetryableStatus(Job.Status) and not SameText(Job.Status, STATUS_PENDING) then
    begin
      Result.Reason := Format('Job status ''%s'' is not retryable', [Job.Status]);
      Exit;
    end;

    // Get step statuses
    Steps := Repo.ListJobSteps(AJobId);
    Result.PreviousStepCount := Length(Steps);

    IncompleteCount := 0;
    for I := 0 to High(Steps) do
    begin
      if SameText(Steps[I].Status, STATUS_DONE) or SameText(Steps[I].Status, STATUS_SKIPPED) then
        Continue;

      if IncompleteCount = 0 then
        Result.ResumeFromStepIndex := I;

      Inc(IncompleteCount);
      SetLength(Result.RemainingSteps, IncompleteCount);
      Result.RemainingSteps[IncompleteCount - 1] := Steps[I].StepType;
    end;

    if IncompleteCount = 0 then
    begin
      // All steps done — job should be marked done
      if not SameText(Job.Status, STATUS_DONE) then
      begin
        Result.CanRetry := True;
        Result.Reason := 'All steps done, job status should be updated to done';
        Result.ResumeFromStepIndex := -1;
      end
      else
      begin
        Result.Reason := 'All steps already completed';
        Exit;
      end;
    end
    else
    begin
      Result.CanRetry := True;
      Result.Reason := Format('Resuming from step %d of %d (%d steps remaining)',
        [Result.ResumeFromStepIndex + 1, Result.PreviousStepCount, IncompleteCount]);
    end;

    Result.ResumedJob := Job;
  finally
    Repo.Free;
  end;
end;

class function TWorkflowResume.FindRetryableJob(const ALogicalKey: string;
  out AJob: TDeepFramesJob; out AReason: string): Boolean;
var
  Repo: TDeepFramesRepository;
begin
  Result := False;
  AReason := '';

  Repo := TDeepFramesRepository.Create;
  try
    if Repo.FindJobByLogicalKey(ALogicalKey, AJob) then
    begin
      if IsSkipStatus(AJob.Status) then
      begin
        AReason := Format('Existing job %s is %s — cannot retry', [AJob.JobId, AJob.Status]);
        Exit;
      end;

      if IsRetryableStatus(AJob.Status) then
      begin
        Result := True;
        AReason := Format('Found retryable job %s with status %s', [AJob.JobId, AJob.Status]);
      end
      else
      begin
        AReason := Format('Existing job %s is %s — not retryable', [AJob.JobId, AJob.Status]);
      end;
    end
    else
    begin
      AReason := 'No existing job found for this logical key';
    end;
  finally
    Repo.Free;
  end;
end;

class function TWorkflowResume.GetStepStatuses(const AJobId: string;
  out AStepTypes: TArray<string>; out AStepStatuses: TArray<string>): Boolean;
var
  Repo: TDeepFramesRepository;
  Steps: TArray<TDeepFramesJobStep>;
  I: Integer;
begin
  Result := False;
  AStepTypes := nil;
  AStepStatuses := nil;

  Repo := TDeepFramesRepository.Create;
  try
    Steps := Repo.ListJobSteps(AJobId);
    if Length(Steps) = 0 then
      Exit;

    SetLength(AStepTypes, Length(Steps));
    SetLength(AStepStatuses, Length(Steps));
    for I := 0 to High(Steps) do
    begin
      AStepTypes[I] := Steps[I].StepType;
      AStepStatuses[I] := Steps[I].Status;
    end;
    Result := True;
  finally
    Repo.Free;
  end;
end;

class function TWorkflowResume.IsRetryableStatus(const AStatus: string): Boolean;
begin
  Result := SameText(AStatus, STATUS_FAILED) or
    SameText(AStatus, STATUS_BLOCKED_REVIEW) or
    SameText(AStatus, STATUS_CANCELLED);
end;

class function TWorkflowResume.IsSkipStatus(const AStatus: string): Boolean;
begin
  Result := SameText(AStatus, STATUS_DONE) or
    SameText(AStatus, STATUS_SKIPPED);
end;

class function TWorkflowResume.BuildRetryKey(const ABaseLogicalKey: string;
  ARetryCount: Integer): string;
begin
  Result := ABaseLogicalKey + ':retry:' + IntToStr(ARetryCount);
end;

end.