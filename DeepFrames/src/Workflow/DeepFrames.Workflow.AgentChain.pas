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
  DeepFrames.Shared.Consts;

// Fake provider: returns stub structured JSON per agent role
function FakeProviderOutput(const AgentRole: string): string;
var
  Obj: TJSONObject;
  ShotsArr: TJSONArray;
  ShotObj: TJSONObject;
  AudioObj: TJSONObject;
  VisualObj: TJSONObject;
begin
  if AgentRole = AGENT_ROLE_SPLITTER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', '1.0.0');
      Obj.AddPair('chapter_summary', 'Stub chapter summary');
      Obj.AddPair('style_anchor', TJSONObject.Create
        .AddPair('art_style', 'documentary')
        .AddPair('color_palette', TJSONArray.Create.Add('warm').Add('neutral'))
        .AddPair('mood', 'calm'));
      ShotsArr := TJSONArray.Create;
      ShotObj := TJSONObject.Create;
      ShotObj.AddPair('shot_id', 'shot_001');
      ShotObj.AddPair('group_id', 'group_01');
      ShotObj.AddPair('text', 'Stub shot text from splitter.');
      ShotObj.AddPair('duration_sec', TJSONNumber.Create(5.0));
      ShotsArr.AddElement(ShotObj);
      Obj.AddPair('shots', ShotsArr);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if AgentRole = AGENT_ROLE_WORKER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', '1.0.0');
      Obj.AddPair('shot_id', 'shot_001');
      Obj.AddPair('group_id', 'group_01');
      AudioObj := TJSONObject.Create;
      AudioObj.AddPair('text', 'Stub worker audio text.');
      AudioObj.AddPair('voice', 'default');
      AudioObj.AddPair('emotion', 'neutral');
      AudioObj.AddPair('pace', 1.0);
      AudioObj.AddPair('pitch', 0.0);
      AudioObj.AddPair('instruction', '');
      Obj.AddPair('audio', AudioObj);
      VisualObj := TJSONObject.Create;
      VisualObj.AddPair('background_prompt', 'Documentary warm neutral bg');
      VisualObj.AddPair('target_aspect_ratios', TJSONArray.Create.Add('16:9'));
      VisualObj.AddPair('transition', 'cut');
      Obj.AddPair('visual', VisualObj);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if AgentRole = AGENT_ROLE_ASSEMBLER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', '1.0.0');
      Obj.AddPair('assembled', True);
      Obj.AddPair('total_duration_sec', TJSONNumber.Create(5.0));
      Obj.AddPair('gaps_filled', TJSONNumber.Create(0));
      Obj.AddPair('continuity_issues', TJSONArray.Create);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if AgentRole = AGENT_ROLE_QA then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', '1.0.0');
      Obj.AddPair('gate', 'gate2');
      Obj.AddPair('gate_result', GATE_RESULT_PASS);
      Obj.AddPair('score', TJSONNumber.Create(0.95));
      Obj.AddPair('coverage_ratio', TJSONNumber.Create(0.97));
      Obj.AddPair('degraded_ratio', TJSONNumber.Create(0.0));
      Obj.AddPair('issues', TJSONArray.Create);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else if AgentRole = AGENT_ROLE_STYLE_KEEPER then
  begin
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('schema_version', '1.0.0');
      Obj.AddPair('style_consistent', True);
      Obj.AddPair('intra_group_similarity', TJSONNumber.Create(0.92));
      Obj.AddPair('inter_group_similarity', TJSONNumber.Create(0.85));
      Obj.AddPair('color_consistency', True);
      Obj.AddPair('art_style_match', TJSONNumber.Create(0.88));
      Obj.AddPair('warnings', TJSONArray.Create);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  end
  else
    Result := '{}';
end;

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
  RawOutput: string;
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
      AGENT_ROLE_SPLITTER, 'stepfun', 'stepfun-flash-3.5', CAPABILITY_LLM);
    Repo.InsertModelBinding(Binding);

    // Run each agent step
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

      // Fake provider call
      RawOutput := FakeProviderOutput(AgentSteps[I].Role);

      // Record prompt run
      PromptRun := TProjectService.CreatePromptRun(
        Job.JobId, Step.StepId, Template.TemplateId, Binding.BindingId,
        AgentSteps[I].Role, RawOutput, 'stepfun', 'stepfun-flash-3.5', CAPABILITY_LLM);
      PromptRun.NormalizedJson := RawOutput;
      PromptRun.TokenInput := 100;
      PromptRun.TokenOutput := 50;
      PromptRun.LatencyMs := 200;
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
