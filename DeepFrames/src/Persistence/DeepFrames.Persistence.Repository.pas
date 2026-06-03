unit DeepFrames.Persistence.Repository;

interface

uses
  System.Generics.Collections,
  FireDAC.Comp.Client,
  DeepFrames.Domain.Types;

type
  TDeepFramesRepository = class
  private
    FConnection: TFDConnection;
    FOwnsConnection: Boolean;
    function NewQuery: TFDQuery;
  public
    constructor Create; overload;
    constructor Create(AConnection: TFDConnection; AOwnsConnection: Boolean = False); overload;
    destructor Destroy; override;

    procedure InsertProject(const Project: TProjectInfo);
    function ListProjects: TArray<TProjectInfo>;

    procedure InsertContentUnit(const UnitInfo: TContentUnitInfo);
    function ListContentUnits(const ProjectId: string): TArray<TContentUnitInfo>;

    procedure InsertSourceDocument(const Doc: TSourceDocumentVersion);
    function ListSourceDocuments(const ProjectId: string): TArray<TSourceDocumentVersion>;

    procedure InsertJob(const Job: TDeepFramesJob);
    procedure UpdateJobQueueTaskId(const JobId, TaskId: string);
    procedure UpdateJobStatus(const JobId, NewStatus: string);
    function ListJobs: TArray<TDeepFramesJob>;
    function FindJobByLogicalKey(const LogicalKey: string; out Job: TDeepFramesJob): Boolean;

    procedure InsertJobStep(const Step: TDeepFramesJobStep);
    procedure UpdateJobStepStatus(const StepId, NewStatus: string);
    function ListJobSteps(const JobId: string): TArray<TDeepFramesJobStep>;

    // Phase 2: Script document
    procedure InsertScriptDocument(const Doc: TScriptDocumentVersion);
    function ListScriptDocuments(const ProjectId: string): TArray<TScriptDocumentVersion>;
    function FindLatestScriptVersion(const ContentUnitId: string; out VersionNo: Integer): Boolean;

    // Phase 2: Accuracy report
    procedure InsertAccuracyReport(const Report: TAccuracyReport);
    function ListAccuracyReports(const ScriptDocumentId: string): TArray<TAccuracyReport>;

    // Phase 2: Variant document
    procedure InsertVariantDocument(const Doc: TVariantDocumentVersion);
    function ListVariantDocuments(const ContentUnitId: string): TArray<TVariantDocumentVersion>;

    // Phase 2: Shot document
    procedure InsertShotDocument(const Doc: TShotDocumentVersion);
    function ListShotDocuments(const ContentUnitId: string): TArray<TShotDocumentVersion>;

    // Phase 2: Asset
    procedure InsertAsset(const Asset: TAssetRecord);
    procedure UpdateAssetStatus(const AssetId, NewStatus: string);
    function ListAssets(const ContentUnitId: string): TArray<TAssetRecord>;

    // Phase 2: Quality gate result
    procedure InsertQualityGateResult(const AGateResult: TQualityGateResult);
    function ListQualityGateResults(const JobId: string): TArray<TQualityGateResult>;
    procedure UpdateQualityGateHumanReview(const ResultId, HumanReviewStatus, ReviewerNote: string);

    // Phase 3: Prompt template
    procedure InsertPromptTemplate(const Template: TPromptTemplate);
    function ListPromptTemplates(const AgentRole: string): TArray<TPromptTemplate>;
    function FindPromptTemplate(const TemplateId: string; out Template: TPromptTemplate): Boolean;

    // Phase 3: Model binding
    procedure InsertModelBinding(const Binding: TModelBinding);
    function ListModelBindings(const AgentRole: string): TArray<TModelBinding>;

    // Phase 3: Prompt run
    procedure InsertPromptRun(const Run: TPromptRun);
    function ListPromptRuns(const JobId: string): TArray<TPromptRun>;

    // Phase 3: Eval result
    procedure InsertEvalResult(const Eval: TEvalResult);
    function ListEvalResults(const JobId: string): TArray<TEvalResult>;

    // Phase 4: Audio manifest
    procedure InsertAudioManifest(const Manifest: TAudioManifest);
    procedure UpdateAudioManifestStatus(const ManifestId, NewStatus: string);
    procedure UpdateAudioManifestAssets(const ManifestId, AudioAssetId,
      TimestampsAssetId, MergedAudioAssetId: string);
    procedure UpdateAudioManifestLoudnorm(const ManifestId: string;
      MeasuredLufs, MeasuredTp, MeasuredLra: Double;
      const Pass1Json, Pass2Json: string);
    procedure UpdateAudioManifestDuration(const ManifestId: string;
      DurationSec, ConcatDeltaMs: Double);
    function ListAudioManifests(const ContentUnitId: string): TArray<TAudioManifest>;
    function FindAudioManifestByShot(const ShotDocumentId: string; out Manifest: TAudioManifest): Boolean;

    // Phase 5: Platform spec
    procedure InsertPlatformSpec(const Spec: TPlatformSpec);
    function ListPlatformSpecs: TArray<TPlatformSpec>;
    function FindPlatformSpecByPlatform(const APlatform: string; out Spec: TPlatformSpec): Boolean;

    // Phase 5: Video IR
    procedure InsertVideoIR(const VIR: TVideoIR);
    procedure UpdateVideoIRStatus(const VideoIRId, NewStatus: string);
    procedure UpdateVideoIRDuration(const VideoIRId: string; Estimated, Actual: Double);
    function ListVideoIRs(const ContentUnitId: string): TArray<TVideoIR>;

    // Phase 5: Video job
    procedure InsertVideoJob(const VJob: TVideoJob);
    procedure UpdateVideoJobStatus(const VideoJobId, NewStatus: string);
    function ListVideoJobs(const VideoIRId: string): TArray<TVideoJob>;

    // Phase 5: Video step
    procedure InsertVideoStep(const VStep: TVideoStep);
    procedure UpdateVideoStepStatus(const VideoStepId, NewStatus: string);
    function ListVideoSteps(const VideoJobId: string): TArray<TVideoStep>;

    // Phase 5: Video asset
    procedure InsertVideoAsset(const VAsset: TVideoAsset);
    function ListVideoAssets(const VideoJobId: string): TArray<TVideoAsset>;

    // Phase 6: Candidate package
    procedure InsertCandidatePackage(const Pkg: TCandidatePackage);
    procedure UpdateCandidatePackageStatus(const PackageId, NewStatus: string);
    function ListCandidatePackages(const ProjectId: string): TArray<TCandidatePackage>;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Stan.Param,
  DeepFrames.Persistence.Connection,
  DeepFrames.Shared.Consts;

constructor TDeepFramesRepository.Create;
begin
  Create(TDeepFramesDB2Connection.CreateConnection(True), True);
end;

constructor TDeepFramesRepository.Create(AConnection: TFDConnection;
  AOwnsConnection: Boolean);
begin
  inherited Create;
  FConnection := AConnection;
  FOwnsConnection := AOwnsConnection;
end;

destructor TDeepFramesRepository.Destroy;
begin
  if FOwnsConnection then
    FConnection.Free;
  inherited;
end;

function TDeepFramesRepository.NewQuery: TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := FConnection;
end;

procedure TDeepFramesRepository.InsertProject(const Project: TProjectInfo);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_project ' +
      '(project_id, title, content_type, source_uri, status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:project_id, :title, :content_type, :source_uri, :status, :schema_version, 1, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (project_id) DO NOTHING';
    Q.ParamByName('project_id').AsString := Project.ProjectId;
    Q.ParamByName('title').AsString := Project.Title;
    Q.ParamByName('content_type').AsString := Project.ContentType;
    Q.ParamByName('source_uri').AsString := Project.SourceUri;
    Q.ParamByName('status').AsString := Project.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListProjects: TArray<TProjectInfo>;
var
  Q: TFDQuery;
  List: TList<TProjectInfo>;
  Item: TProjectInfo;
begin
  List := TList<TProjectInfo>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT project_id, title, content_type, source_uri, status FROM deepframes_project ORDER BY created_at DESC';
    Q.Open;
    while not Q.Eof do
    begin
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.Title := Q.FieldByName('title').AsString;
      Item.ContentType := Q.FieldByName('content_type').AsString;
      Item.SourceUri := Q.FieldByName('source_uri').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

procedure TDeepFramesRepository.InsertContentUnit(const UnitInfo: TContentUnitInfo);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_content_unit ' +
      '(content_unit_id, project_id, unit_type, display_label, order_index, status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:content_unit_id, :project_id, :unit_type, :display_label, :order_index, :status, :schema_version, 1, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (content_unit_id) DO NOTHING';
    Q.ParamByName('content_unit_id').AsString := UnitInfo.ContentUnitId;
    Q.ParamByName('project_id').AsString := UnitInfo.ProjectId;
    Q.ParamByName('unit_type').AsString := UnitInfo.UnitType;
    Q.ParamByName('display_label').AsString := UnitInfo.DisplayLabel;
    Q.ParamByName('order_index').AsInteger := UnitInfo.OrderIndex;
    Q.ParamByName('status').AsString := UnitInfo.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListContentUnits(
  const ProjectId: string): TArray<TContentUnitInfo>;
var
  Q: TFDQuery;
  List: TList<TContentUnitInfo>;
  Item: TContentUnitInfo;
begin
  List := TList<TContentUnitInfo>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT content_unit_id, project_id, unit_type, display_label, order_index, status FROM deepframes_content_unit WHERE project_id = :project_id ORDER BY order_index';
    Q.ParamByName('project_id').AsString := ProjectId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.UnitType := Q.FieldByName('unit_type').AsString;
      Item.DisplayLabel := Q.FieldByName('display_label').AsString;
      Item.OrderIndex := Q.FieldByName('order_index').AsInteger;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

procedure TDeepFramesRepository.InsertSourceDocument(
  const Doc: TSourceDocumentVersion);
var
  Q: TFDQuery;
  Payload: TJSONObject;
begin
  Payload := TJSONObject.Create;
  try
    Payload.AddPair('markdown', Doc.MarkdownText);
    Payload.AddPair('source_uri', Doc.SourceUri);
    Q := NewQuery;
    try
      Q.SQL.Text :=
        'INSERT INTO deepframes_source_document ' +
        '(document_id, project_id, content_unit_id, document_kind, content_hash, source_uri, status, schema_version, version_no, payload_json, extra_json) ' +
        'VALUES (:document_id, :project_id, :content_unit_id, ''source'', :content_hash, :source_uri, :status, :schema_version, :version_no, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
        'ON CONFLICT (document_id) DO NOTHING';
      Q.ParamByName('document_id').AsString := Doc.DocumentId;
      Q.ParamByName('project_id').AsString := Doc.ProjectId;
      Q.ParamByName('content_unit_id').AsString := Doc.ContentUnitId;
      Q.ParamByName('content_hash').AsString := Doc.ContentHash;
      Q.ParamByName('source_uri').AsString := Doc.SourceUri;
      Q.ParamByName('status').AsString := Doc.Status;
      Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
      Q.ParamByName('version_no').AsInteger := Doc.VersionNo;
      Q.ParamByName('payload_json').AsString := Payload.ToJSON;
      Q.ParamByName('extra_json').AsString := '{}';
      Q.ExecSQL;
    finally
      Q.Free;
    end;
  finally
    Payload.Free;
  end;
end;

function TDeepFramesRepository.ListSourceDocuments(
  const ProjectId: string): TArray<TSourceDocumentVersion>;
var
  Q: TFDQuery;
  List: TList<TSourceDocumentVersion>;
  Item: TSourceDocumentVersion;
  PayloadStr: string;
  Payload: TJSONObject;
begin
  List := TList<TSourceDocumentVersion>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT document_id, project_id, content_unit_id, version_no, content_hash, source_uri, status, payload_json FROM deepframes_source_document WHERE project_id = :project_id ORDER BY created_at DESC';
    Q.ParamByName('project_id').AsString := ProjectId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.DocumentId := Q.FieldByName('document_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.VersionNo := Q.FieldByName('version_no').AsInteger;
      Item.ContentHash := Q.FieldByName('content_hash').AsString;
      Item.SourceUri := Q.FieldByName('source_uri').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      // Parse payload_json to extract markdown text
      PayloadStr := Q.FieldByName('payload_json').AsString;
      Payload := TJSONObject.ParseJSONValue(PayloadStr) as TJSONObject;
      try
        if Payload <> nil then
          Item.MarkdownText := Payload.GetValue<string>('markdown')
        else
          Item.MarkdownText := '';
      finally
        Payload.Free;
      end;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

procedure TDeepFramesRepository.InsertJob(const Job: TDeepFramesJob);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_job ' +
      '(job_id, project_id, content_unit_id, job_type, logical_key, job_queue_task_id, status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:job_id, :project_id, :content_unit_id, :job_type, :logical_key, :job_queue_task_id, :status, :schema_version, 1, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (logical_key) DO NOTHING';
    Q.ParamByName('job_id').AsString := Job.JobId;
    Q.ParamByName('project_id').AsString := Job.ProjectId;
    Q.ParamByName('content_unit_id').AsString := Job.ContentUnitId;
    Q.ParamByName('job_type').AsString := Job.JobType;
    Q.ParamByName('logical_key').AsString := Job.LogicalKey;
    Q.ParamByName('job_queue_task_id').AsString := Job.JobQueueTaskId;
    Q.ParamByName('status').AsString := Job.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateJobQueueTaskId(const JobId, TaskId: string);
begin
  FConnection.ExecSQL('UPDATE deepframes_job SET job_queue_task_id = :task_id, updated_at = NOW() WHERE job_id = :job_id', [TaskId, JobId]);
end;

procedure TDeepFramesRepository.UpdateJobStatus(const JobId, NewStatus: string);
begin
  FConnection.ExecSQL('UPDATE deepframes_job SET status = :status, updated_at = NOW() WHERE job_id = :job_id', [NewStatus, JobId]);
end;

function TDeepFramesRepository.FindJobByLogicalKey(const LogicalKey: string;
  out Job: TDeepFramesJob): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT job_id, project_id, content_unit_id, job_type, logical_key, job_queue_task_id, status FROM deepframes_job WHERE logical_key = :logical_key';
    Q.ParamByName('logical_key').AsString := LogicalKey;
    Q.Open;
    if not Q.Eof then
    begin
      Job.JobId := Q.FieldByName('job_id').AsString;
      Job.ProjectId := Q.FieldByName('project_id').AsString;
      Job.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Job.JobType := Q.FieldByName('job_type').AsString;
      Job.LogicalKey := Q.FieldByName('logical_key').AsString;
      Job.JobQueueTaskId := Q.FieldByName('job_queue_task_id').AsString;
      Job.Status := Q.FieldByName('status').AsString;
      Result := True;
    end;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListJobs: TArray<TDeepFramesJob>;
var
  Q: TFDQuery;
  List: TList<TDeepFramesJob>;
  Item: TDeepFramesJob;
begin
  List := TList<TDeepFramesJob>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT job_id, project_id, content_unit_id, job_type, logical_key, job_queue_task_id, status FROM deepframes_job ORDER BY created_at DESC';
    Q.Open;
    while not Q.Eof do
    begin
      Item.JobId := Q.FieldByName('job_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.JobType := Q.FieldByName('job_type').AsString;
      Item.LogicalKey := Q.FieldByName('logical_key').AsString;
      Item.JobQueueTaskId := Q.FieldByName('job_queue_task_id').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

procedure TDeepFramesRepository.InsertJobStep(const Step: TDeepFramesJobStep);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_job_step ' +
      '(step_id, job_id, step_type, step_key, status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:step_id, :job_id, :step_type, :step_key, :status, :schema_version, 1, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (step_key) DO NOTHING';
    Q.ParamByName('step_id').AsString := Step.StepId;
    Q.ParamByName('job_id').AsString := Step.JobId;
    Q.ParamByName('step_type').AsString := Step.StepType;
    Q.ParamByName('step_key').AsString := Step.StepKey;
    Q.ParamByName('status').AsString := Step.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateJobStepStatus(const StepId,
  NewStatus: string);
begin
  FConnection.ExecSQL('UPDATE deepframes_job_step SET status = :status, updated_at = NOW() WHERE step_id = :step_id', [NewStatus, StepId]);
end;

function TDeepFramesRepository.ListJobSteps(
  const JobId: string): TArray<TDeepFramesJobStep>;
var
  Q: TFDQuery;
  List: TList<TDeepFramesJobStep>;
  Item: TDeepFramesJobStep;
begin
  List := TList<TDeepFramesJobStep>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT step_id, job_id, step_type, step_key, status FROM deepframes_job_step WHERE job_id = :job_id ORDER BY created_at';
    Q.ParamByName('job_id').AsString := JobId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.StepId := Q.FieldByName('step_id').AsString;
      Item.JobId := Q.FieldByName('job_id').AsString;
      Item.StepType := Q.FieldByName('step_type').AsString;
      Item.StepKey := Q.FieldByName('step_key').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 2: Script document
procedure TDeepFramesRepository.InsertScriptDocument(const Doc: TScriptDocumentVersion);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_script_document ' +
      '(document_id, project_id, content_unit_id, document_kind, parent_document_id, ' +
      'source_document_id, content_hash, status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:document_id, :project_id, :content_unit_id, ''script'', :parent_document_id, ' +
      ':source_document_id, :content_hash, :status, :schema_version, :version_no, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (document_id) DO NOTHING';
    Q.ParamByName('document_id').AsString := Doc.DocumentId;
    Q.ParamByName('project_id').AsString := Doc.ProjectId;
    Q.ParamByName('content_unit_id').AsString := Doc.ContentUnitId;
    Q.ParamByName('parent_document_id').AsString := Doc.ParentDocumentId;
    Q.ParamByName('source_document_id').AsString := Doc.SourceDocumentId;
    Q.ParamByName('content_hash').AsString := Doc.ContentHash;
    Q.ParamByName('status').AsString := Doc.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('version_no').AsInteger := Doc.VersionNo;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListScriptDocuments(
  const ProjectId: string): TArray<TScriptDocumentVersion>;
var
  Q: TFDQuery;
  List: TList<TScriptDocumentVersion>;
  Item: TScriptDocumentVersion;
begin
  List := TList<TScriptDocumentVersion>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT document_id, project_id, content_unit_id, version_no, parent_document_id, ' +
      'source_document_id, content_hash, status ' +
      'FROM deepframes_script_document WHERE project_id = :project_id ORDER BY created_at DESC';
    Q.ParamByName('project_id').AsString := ProjectId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.DocumentId := Q.FieldByName('document_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.VersionNo := Q.FieldByName('version_no').AsInteger;
      Item.ParentDocumentId := Q.FieldByName('parent_document_id').AsString;
      Item.SourceDocumentId := Q.FieldByName('source_document_id').AsString;
      Item.ContentHash := Q.FieldByName('content_hash').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TDeepFramesRepository.FindLatestScriptVersion(
  const ContentUnitId: string; out VersionNo: Integer): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT MAX(version_no) AS max_ver FROM deepframes_script_document WHERE content_unit_id = :content_unit_id';
    Q.ParamByName('content_unit_id').AsString := ContentUnitId;
    Q.Open;
    if not Q.Eof and not Q.FieldByName('max_ver').IsNull then
    begin
      VersionNo := Q.FieldByName('max_ver').AsInteger;
      Result := True;
    end;
  finally
    Q.Free;
  end;
end;

// Phase 2: Accuracy report
procedure TDeepFramesRepository.InsertAccuracyReport(const Report: TAccuracyReport);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_accuracy_report ' +
      '(report_id, project_id, source_document_id, script_document_id, coverage_score, ' +
      'distortion_score, result, human_review_status, reviewer_note, status, schema_version, ' +
      'version_no, payload_json, extra_json) ' +
      'VALUES (:report_id, :project_id, :source_document_id, :script_document_id, :coverage_score, ' +
      ':distortion_score, :result, :human_review_status, :reviewer_note, :status, :schema_version, ' +
      '1, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (report_id) DO NOTHING';
    Q.ParamByName('report_id').AsString := Report.ReportId;
    Q.ParamByName('project_id').AsString := Report.ProjectId;
    Q.ParamByName('source_document_id').AsString := Report.SourceDocumentId;
    Q.ParamByName('script_document_id').AsString := Report.ScriptDocumentId;
    Q.ParamByName('coverage_score').AsFloat := Report.CoverageScore;
    Q.ParamByName('distortion_score').AsFloat := Report.DistortionScore;
    Q.ParamByName('result').AsString := Report.Result;
    Q.ParamByName('human_review_status').AsString := Report.HumanReviewStatus;
    Q.ParamByName('reviewer_note').AsString := Report.ReviewerNote;
    Q.ParamByName('status').AsString := Report.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListAccuracyReports(
  const ScriptDocumentId: string): TArray<TAccuracyReport>;
var
  Q: TFDQuery;
  List: TList<TAccuracyReport>;
  Item: TAccuracyReport;
begin
  List := TList<TAccuracyReport>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT report_id, project_id, source_document_id, script_document_id, ' +
      'coverage_score, distortion_score, result, human_review_status, reviewer_note, status ' +
      'FROM deepframes_accuracy_report WHERE script_document_id = :script_document_id ORDER BY created_at DESC';
    Q.ParamByName('script_document_id').AsString := ScriptDocumentId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.ReportId := Q.FieldByName('report_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.SourceDocumentId := Q.FieldByName('source_document_id').AsString;
      Item.ScriptDocumentId := Q.FieldByName('script_document_id').AsString;
      Item.CoverageScore := Q.FieldByName('coverage_score').AsFloat;
      Item.DistortionScore := Q.FieldByName('distortion_score').AsFloat;
      Item.Result := Q.FieldByName('result').AsString;
      Item.HumanReviewStatus := Q.FieldByName('human_review_status').AsString;
      Item.ReviewerNote := Q.FieldByName('reviewer_note').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 2: Variant document
procedure TDeepFramesRepository.InsertVariantDocument(const Doc: TVariantDocumentVersion);
var
  Q: TFDQuery;
  Payload: TJSONObject;
begin
  Payload := TJSONObject.Create;
  try
    Payload.AddPair('variant_kind', Doc.VariantKind);
    Payload.AddPair('variant_label', Doc.VariantLabel);
    Payload.AddPair('target_platform', Doc.TargetPlatform);
    Q := NewQuery;
    try
      Q.SQL.Text :=
        'INSERT INTO deepframes_variant_document ' +
        '(document_id, project_id, content_unit_id, document_kind, parent_document_id, ' +
        'variant_kind, variant_label, target_platform, content_hash, status, schema_version, ' +
        'version_no, payload_json, extra_json) ' +
        'VALUES (:document_id, :project_id, :content_unit_id, ''variant'', :parent_document_id, ' +
        ':variant_kind, :variant_label, :target_platform, :content_hash, :status, :schema_version, ' +
        ':version_no, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
        'ON CONFLICT (document_id) DO NOTHING';
      Q.ParamByName('document_id').AsString := Doc.DocumentId;
      Q.ParamByName('project_id').AsString := Doc.ProjectId;
      Q.ParamByName('content_unit_id').AsString := Doc.ContentUnitId;
      Q.ParamByName('parent_document_id').AsString := Doc.ParentDocumentId;
      Q.ParamByName('variant_kind').AsString := Doc.VariantKind;
      Q.ParamByName('variant_label').AsString := Doc.VariantLabel;
      Q.ParamByName('target_platform').AsString := Doc.TargetPlatform;
      Q.ParamByName('content_hash').AsString := Doc.ContentHash;
      Q.ParamByName('status').AsString := Doc.Status;
      Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
      Q.ParamByName('version_no').AsInteger := Doc.VersionNo;
      Q.ParamByName('payload_json').AsString := Payload.ToJSON;
      Q.ParamByName('extra_json').AsString := '{}';
      Q.ExecSQL;
    finally
      Q.Free;
    end;
  finally
    Payload.Free;
  end;
end;

function TDeepFramesRepository.ListVariantDocuments(
  const ContentUnitId: string): TArray<TVariantDocumentVersion>;
var
  Q: TFDQuery;
  List: TList<TVariantDocumentVersion>;
  Item: TVariantDocumentVersion;
begin
  List := TList<TVariantDocumentVersion>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT document_id, project_id, content_unit_id, version_no, parent_document_id, ' +
      'variant_kind, variant_label, target_platform, content_hash, status ' +
      'FROM deepframes_variant_document WHERE content_unit_id = :content_unit_id ORDER BY created_at DESC';
    Q.ParamByName('content_unit_id').AsString := ContentUnitId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.DocumentId := Q.FieldByName('document_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.VersionNo := Q.FieldByName('version_no').AsInteger;
      Item.ParentDocumentId := Q.FieldByName('parent_document_id').AsString;
      Item.VariantKind := Q.FieldByName('variant_kind').AsString;
      Item.VariantLabel := Q.FieldByName('variant_label').AsString;
      Item.TargetPlatform := Q.FieldByName('target_platform').AsString;
      Item.ContentHash := Q.FieldByName('content_hash').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 2: Shot document
procedure TDeepFramesRepository.InsertShotDocument(const Doc: TShotDocumentVersion);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_shot_document ' +
      '(document_id, project_id, content_unit_id, document_kind, parent_document_id, ' +
      'content_hash, status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:document_id, :project_id, :content_unit_id, ''shot'', :parent_document_id, ' +
      ':content_hash, :status, :schema_version, :version_no, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (document_id) DO NOTHING';
    Q.ParamByName('document_id').AsString := Doc.DocumentId;
    Q.ParamByName('project_id').AsString := Doc.ProjectId;
    Q.ParamByName('content_unit_id').AsString := Doc.ContentUnitId;
    Q.ParamByName('parent_document_id').AsString := Doc.ParentDocumentId;
    Q.ParamByName('content_hash').AsString := Doc.ContentHash;
    Q.ParamByName('status').AsString := Doc.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('version_no').AsInteger := Doc.VersionNo;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListShotDocuments(
  const ContentUnitId: string): TArray<TShotDocumentVersion>;
var
  Q: TFDQuery;
  List: TList<TShotDocumentVersion>;
  Item: TShotDocumentVersion;
begin
  List := TList<TShotDocumentVersion>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT document_id, project_id, content_unit_id, version_no, parent_document_id, ' +
      'content_hash, status ' +
      'FROM deepframes_shot_document WHERE content_unit_id = :content_unit_id ORDER BY created_at DESC';
    Q.ParamByName('content_unit_id').AsString := ContentUnitId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.DocumentId := Q.FieldByName('document_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.VersionNo := Q.FieldByName('version_no').AsInteger;
      Item.ParentDocumentId := Q.FieldByName('parent_document_id').AsString;
      Item.ContentHash := Q.FieldByName('content_hash').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 2: Asset
procedure TDeepFramesRepository.InsertAsset(const Asset: TAssetRecord);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_asset ' +
      '(asset_id, project_id, content_unit_id, asset_type, uri, sha256, byte_size, mime_type, ' +
      'producer, producer_version, status, retention_class, schema_version, payload_json, extra_json) ' +
      'VALUES (:asset_id, :project_id, :content_unit_id, :asset_type, :uri, :sha256, :byte_size, :mime_type, ' +
      ':producer, :producer_version, :status, :retention_class, :schema_version, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (asset_id) DO NOTHING';
    Q.ParamByName('asset_id').AsString := Asset.AssetId;
    Q.ParamByName('project_id').AsString := Asset.ProjectId;
    Q.ParamByName('content_unit_id').AsString := Asset.ContentUnitId;
    Q.ParamByName('asset_type').AsString := Asset.AssetType;
    Q.ParamByName('uri').AsString := Asset.Uri;
    Q.ParamByName('sha256').AsString := Asset.Sha256;
    Q.ParamByName('byte_size').AsLargeInt := Asset.ByteSize;
    Q.ParamByName('mime_type').AsString := Asset.MimeType;
    Q.ParamByName('producer').AsString := Asset.Producer;
    Q.ParamByName('producer_version').AsString := Asset.ProducerVersion;
    Q.ParamByName('status').AsString := Asset.Status;
    Q.ParamByName('retention_class').AsString := Asset.RetentionClass;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    // Phase 4: store audio metadata in extra_json
    if (Asset.SampleRate > 0) or (Asset.Channels > 0) or (Asset.Codec <> '') then
    begin
      var AssetExtra: TJSONObject;
      AssetExtra := TJSONObject.Create;
      try
        if Asset.SampleRate > 0 then
          AssetExtra.AddPair('sample_rate', TJSONNumber.Create(Asset.SampleRate));
        if Asset.Channels > 0 then
          AssetExtra.AddPair('channels', TJSONNumber.Create(Asset.Channels));
        if Asset.Codec <> '' then
          AssetExtra.AddPair('codec', Asset.Codec);
        if Asset.DurationSec > 0 then
          AssetExtra.AddPair('duration_sec', TJSONNumber.Create(Asset.DurationSec));
        Q.ParamByName('extra_json').AsString := AssetExtra.ToJSON;
      finally
        AssetExtra.Free;
      end;
    end
    else
      Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateAssetStatus(const AssetId, NewStatus: string);
begin
  FConnection.ExecSQL(
    'UPDATE deepframes_asset SET status = :status, updated_at = NOW() WHERE asset_id = :asset_id',
    [NewStatus, AssetId]);
end;

function TDeepFramesRepository.ListAssets(
  const ContentUnitId: string): TArray<TAssetRecord>;
var
  Q: TFDQuery;
  List: TList<TAssetRecord>;
  Item: TAssetRecord;
begin
  List := TList<TAssetRecord>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT asset_id, project_id, content_unit_id, asset_type, uri, sha256, byte_size, mime_type, ' +
      'producer, producer_version, status, retention_class ' +
      'FROM deepframes_asset WHERE content_unit_id = :content_unit_id ORDER BY created_at DESC';
    Q.ParamByName('content_unit_id').AsString := ContentUnitId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.AssetId := Q.FieldByName('asset_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.AssetType := Q.FieldByName('asset_type').AsString;
      Item.Uri := Q.FieldByName('uri').AsString;
      Item.Sha256 := Q.FieldByName('sha256').AsString;
      Item.ByteSize := Q.FieldByName('byte_size').AsLargeInt;
      Item.MimeType := Q.FieldByName('mime_type').AsString;
      Item.Producer := Q.FieldByName('producer').AsString;
      Item.ProducerVersion := Q.FieldByName('producer_version').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      Item.RetentionClass := Q.FieldByName('retention_class').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 2: Quality gate result
procedure TDeepFramesRepository.InsertQualityGateResult(
  const AGateResult: TQualityGateResult);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_quality_gate_result ' +
      '(result_id, job_id, gate, gate_result, score, human_review_status, reviewer_note, ' +
      'schema_version, payload_json, extra_json) ' +
      'VALUES (:result_id, :job_id, :gate, :gate_result, :score, :human_review_status, :reviewer_note, ' +
      ':schema_version, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (result_id) DO NOTHING';
    Q.ParamByName('result_id').AsString := AGateResult.ResultId;
    Q.ParamByName('job_id').AsString := AGateResult.JobId;
    Q.ParamByName('gate').AsString := AGateResult.Gate;
    Q.ParamByName('gate_result').AsString := AGateResult.GateResult;
    Q.ParamByName('score').AsFloat := AGateResult.Score;
    Q.ParamByName('human_review_status').AsString := AGateResult.HumanReviewStatus;
    Q.ParamByName('reviewer_note').AsString := AGateResult.ReviewerNote;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListQualityGateResults(
  const JobId: string): TArray<TQualityGateResult>;
var
  Q: TFDQuery;
  List: TList<TQualityGateResult>;
  Item: TQualityGateResult;
begin
  List := TList<TQualityGateResult>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT result_id, job_id, gate, gate_result, score, human_review_status, reviewer_note ' +
      'FROM deepframes_quality_gate_result WHERE job_id = :job_id ORDER BY created_at';
    Q.ParamByName('job_id').AsString := JobId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.ResultId := Q.FieldByName('result_id').AsString;
      Item.JobId := Q.FieldByName('job_id').AsString;
      Item.Gate := Q.FieldByName('gate').AsString;
      Item.GateResult := Q.FieldByName('gate_result').AsString;
      Item.Score := Q.FieldByName('score').AsFloat;
      Item.HumanReviewStatus := Q.FieldByName('human_review_status').AsString;
      Item.ReviewerNote := Q.FieldByName('reviewer_note').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateQualityGateHumanReview(const ResultId,
  HumanReviewStatus, ReviewerNote: string);
begin
  FConnection.ExecSQL(
    'UPDATE deepframes_quality_gate_result SET human_review_status = :status, ' +
    'reviewer_note = :note, updated_at = NOW() WHERE result_id = :result_id',
    [HumanReviewStatus, ReviewerNote, ResultId]);
end;

// Phase 3: Prompt template
procedure TDeepFramesRepository.InsertPromptTemplate(const Template: TPromptTemplate);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_prompt_template ' +
      '(template_id, name, agent_role, system_prompt, output_format, output_schema_json, ' +
      'extraction_hints, few_shot_examples, split_rules_json, temperature, max_tokens, ' +
      'status, schema_version, version_no, payload_json, extra_json) ' +
      'VALUES (:template_id, :name, :agent_role, :system_prompt, :output_format, ' +
      'CAST(:output_schema_json AS jsonb), CAST(:extraction_hints AS jsonb), ' +
      'CAST(:few_shot_examples AS jsonb), CAST(:split_rules_json AS jsonb), ' +
      ':temperature, :max_tokens, :status, :schema_version, :version_no, ' +
      'CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (template_id) DO NOTHING';
    Q.ParamByName('template_id').AsString := Template.TemplateId;
    Q.ParamByName('name').AsString := Template.Name;
    Q.ParamByName('agent_role').AsString := Template.AgentRole;
    Q.ParamByName('system_prompt').AsString := Template.SystemPrompt;
    Q.ParamByName('output_format').AsString := Template.OutputFormat;
    Q.ParamByName('output_schema_json').AsString := Template.OutputSchemaJson;
    Q.ParamByName('extraction_hints').AsString := Template.ExtractionHintsJson;
    Q.ParamByName('few_shot_examples').AsString := Template.FewShotExamplesJson;
    Q.ParamByName('split_rules_json').AsString := Template.SplitRulesJson;
    Q.ParamByName('temperature').AsFloat := Template.Temperature;
    Q.ParamByName('max_tokens').AsInteger := Template.MaxTokens;
    Q.ParamByName('status').AsString := Template.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('version_no').AsInteger := Template.VersionNo;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListPromptTemplates(
  const AgentRole: string): TArray<TPromptTemplate>;
var
  Q: TFDQuery;
  List: TList<TPromptTemplate>;
  Item: TPromptTemplate;
begin
  List := TList<TPromptTemplate>.Create;
  Q := NewQuery;
  try
    if AgentRole = '' then
      Q.SQL.Text :=
        'SELECT template_id, name, agent_role, system_prompt, output_format, ' +
        'output_schema_json, extraction_hints, few_shot_examples, split_rules_json, ' +
        'temperature, max_tokens, version_no, status ' +
        'FROM deepframes_prompt_template ORDER BY created_at DESC'
    else
    begin
      Q.SQL.Text :=
        'SELECT template_id, name, agent_role, system_prompt, output_format, ' +
        'output_schema_json, extraction_hints, few_shot_examples, split_rules_json, ' +
        'temperature, max_tokens, version_no, status ' +
        'FROM deepframes_prompt_template WHERE agent_role = :agent_role ORDER BY created_at DESC';
      Q.ParamByName('agent_role').AsString := AgentRole;
    end;
    Q.Open;
    while not Q.Eof do
    begin
      Item.TemplateId := Q.FieldByName('template_id').AsString;
      Item.Name := Q.FieldByName('name').AsString;
      Item.AgentRole := Q.FieldByName('agent_role').AsString;
      Item.SystemPrompt := Q.FieldByName('system_prompt').AsString;
      Item.OutputFormat := Q.FieldByName('output_format').AsString;
      Item.OutputSchemaJson := Q.FieldByName('output_schema_json').AsString;
      Item.ExtractionHintsJson := Q.FieldByName('extraction_hints').AsString;
      Item.FewShotExamplesJson := Q.FieldByName('few_shot_examples').AsString;
      Item.SplitRulesJson := Q.FieldByName('split_rules_json').AsString;
      Item.Temperature := Q.FieldByName('temperature').AsFloat;
      Item.MaxTokens := Q.FieldByName('max_tokens').AsInteger;
      Item.VersionNo := Q.FieldByName('version_no').AsInteger;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TDeepFramesRepository.FindPromptTemplate(const TemplateId: string;
  out Template: TPromptTemplate): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT template_id, name, agent_role, system_prompt, output_format, ' +
      'output_schema_json, extraction_hints, few_shot_examples, split_rules_json, ' +
      'temperature, max_tokens, version_no, status ' +
      'FROM deepframes_prompt_template WHERE template_id = :template_id';
    Q.ParamByName('template_id').AsString := TemplateId;
    Q.Open;
    if not Q.Eof then
    begin
      Template.TemplateId := Q.FieldByName('template_id').AsString;
      Template.Name := Q.FieldByName('name').AsString;
      Template.AgentRole := Q.FieldByName('agent_role').AsString;
      Template.SystemPrompt := Q.FieldByName('system_prompt').AsString;
      Template.OutputFormat := Q.FieldByName('output_format').AsString;
      Template.OutputSchemaJson := Q.FieldByName('output_schema_json').AsString;
      Template.ExtractionHintsJson := Q.FieldByName('extraction_hints').AsString;
      Template.FewShotExamplesJson := Q.FieldByName('few_shot_examples').AsString;
      Template.SplitRulesJson := Q.FieldByName('split_rules_json').AsString;
      Template.Temperature := Q.FieldByName('temperature').AsFloat;
      Template.MaxTokens := Q.FieldByName('max_tokens').AsInteger;
      Template.VersionNo := Q.FieldByName('version_no').AsInteger;
      Template.Status := Q.FieldByName('status').AsString;
      Result := True;
    end;
  finally
    Q.Free;
  end;
end;

// Phase 3: Model binding
procedure TDeepFramesRepository.InsertModelBinding(const Binding: TModelBinding);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_model_binding ' +
      '(binding_id, agent_role, provider, model, capability, api_base_url, ' +
      'temperature, max_tokens, status, schema_version, payload_json, extra_json) ' +
      'VALUES (:binding_id, :agent_role, :provider, :model, :capability, :api_base_url, ' +
      ':temperature, :max_tokens, :status, :schema_version, ' +
      'CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (binding_id) DO NOTHING';
    Q.ParamByName('binding_id').AsString := Binding.BindingId;
    Q.ParamByName('agent_role').AsString := Binding.AgentRole;
    Q.ParamByName('provider').AsString := Binding.Provider;
    Q.ParamByName('model').AsString := Binding.Model;
    Q.ParamByName('capability').AsString := Binding.Capability;
    Q.ParamByName('api_base_url').AsString := Binding.ApiBaseUrl;
    Q.ParamByName('temperature').AsFloat := Binding.Temperature;
    Q.ParamByName('max_tokens').AsInteger := Binding.MaxTokens;
    Q.ParamByName('status').AsString := Binding.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListModelBindings(
  const AgentRole: string): TArray<TModelBinding>;
var
  Q: TFDQuery;
  List: TList<TModelBinding>;
  Item: TModelBinding;
begin
  List := TList<TModelBinding>.Create;
  Q := NewQuery;
  try
    if AgentRole = '' then
      Q.SQL.Text :=
        'SELECT binding_id, agent_role, provider, model, capability, api_base_url, ' +
        'temperature, max_tokens, status ' +
        'FROM deepframes_model_binding ORDER BY created_at DESC'
    else
    begin
      Q.SQL.Text :=
        'SELECT binding_id, agent_role, provider, model, capability, api_base_url, ' +
        'temperature, max_tokens, status ' +
        'FROM deepframes_model_binding WHERE agent_role = :agent_role ORDER BY created_at DESC';
      Q.ParamByName('agent_role').AsString := AgentRole;
    end;
    Q.Open;
    while not Q.Eof do
    begin
      Item.BindingId := Q.FieldByName('binding_id').AsString;
      Item.AgentRole := Q.FieldByName('agent_role').AsString;
      Item.Provider := Q.FieldByName('provider').AsString;
      Item.Model := Q.FieldByName('model').AsString;
      Item.Capability := Q.FieldByName('capability').AsString;
      Item.ApiBaseUrl := Q.FieldByName('api_base_url').AsString;
      Item.Temperature := Q.FieldByName('temperature').AsFloat;
      Item.MaxTokens := Q.FieldByName('max_tokens').AsInteger;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 3: Prompt run
procedure TDeepFramesRepository.InsertPromptRun(const Run: TPromptRun);
var
  Q: TFDQuery;
  NormalizedParam: string;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_prompt_run ' +
      '(run_id, job_id, job_step_id, prompt_template_id, prompt_version_no, model_binding_id, ' +
      'agent_role, raw_output, normalized_json, validation_error, repair_count, ' +
      'token_input, token_output, latency_ms, provider, model, capability, ' +
      'retry_count, error_code, status, schema_version, payload_json, extra_json) ' +
      'VALUES (:run_id, :job_id, :job_step_id, :prompt_template_id, :prompt_version_no, ' +
      ':model_binding_id, :agent_role, :raw_output, CAST(:normalized_json AS jsonb), ' +
      ':validation_error, :repair_count, :token_input, :token_output, :latency_ms, ' +
      ':provider, :model, :capability, :retry_count, :error_code, :status, ' +
      ':schema_version, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (run_id) DO NOTHING';
    Q.ParamByName('run_id').AsString := Run.RunId;
    Q.ParamByName('job_id').AsString := Run.JobId;
    Q.ParamByName('job_step_id').AsString := Run.JobStepId;
    Q.ParamByName('prompt_template_id').AsString := Run.PromptTemplateId;
    Q.ParamByName('prompt_version_no').AsInteger := Run.PromptVersionNo;
    Q.ParamByName('model_binding_id').AsString := Run.ModelBindingId;
    Q.ParamByName('agent_role').AsString := Run.AgentRole;
    Q.ParamByName('raw_output').AsString := Run.RawOutput;
    NormalizedParam := Run.NormalizedJson;
    if NormalizedParam = '' then
      NormalizedParam := '{}';
    Q.ParamByName('normalized_json').AsString := NormalizedParam;
    Q.ParamByName('validation_error').AsString := Run.ValidationError;
    Q.ParamByName('repair_count').AsSmallInt := Run.RepairCount;
    Q.ParamByName('token_input').AsInteger := Run.TokenInput;
    Q.ParamByName('token_output').AsInteger := Run.TokenOutput;
    Q.ParamByName('latency_ms').AsInteger := Run.LatencyMs;
    Q.ParamByName('provider').AsString := Run.Provider;
    Q.ParamByName('model').AsString := Run.Model;
    Q.ParamByName('capability').AsString := Run.Capability;
    Q.ParamByName('retry_count').AsSmallInt := Run.RetryCount;
    Q.ParamByName('error_code').AsString := Run.ErrorCode;
    Q.ParamByName('status').AsString := Run.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    // Phase 4: store audio-specific fields in extra_json
    if (Run.TtsCharCount > 0) or (Run.AsrDurationSec > 0) then
    begin
      var ExtraObj: TJSONObject;
      ExtraObj := TJSONObject.Create;
      try
        if Run.TtsCharCount > 0 then
          ExtraObj.AddPair('tts_char_count', TJSONNumber.Create(Run.TtsCharCount));
        if Run.AsrDurationSec > 0 then
          ExtraObj.AddPair('asr_duration_sec', TJSONNumber.Create(Run.AsrDurationSec));
        Q.ParamByName('extra_json').AsString := ExtraObj.ToJSON;
      finally
        ExtraObj.Free;
      end;
    end
    else
      Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListPromptRuns(
  const JobId: string): TArray<TPromptRun>;
var
  Q: TFDQuery;
  List: TList<TPromptRun>;
  Item: TPromptRun;
begin
  List := TList<TPromptRun>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT run_id, job_id, job_step_id, prompt_template_id, prompt_version_no, ' +
      'model_binding_id, agent_role, raw_output, validation_error, repair_count, ' +
      'token_input, token_output, latency_ms, provider, model, capability, ' +
      'retry_count, error_code, status ' +
      'FROM deepframes_prompt_run WHERE job_id = :job_id ORDER BY created_at';
    Q.ParamByName('job_id').AsString := JobId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.RunId := Q.FieldByName('run_id').AsString;
      Item.JobId := Q.FieldByName('job_id').AsString;
      Item.JobStepId := Q.FieldByName('job_step_id').AsString;
      Item.PromptTemplateId := Q.FieldByName('prompt_template_id').AsString;
      Item.PromptVersionNo := Q.FieldByName('prompt_version_no').AsInteger;
      Item.ModelBindingId := Q.FieldByName('model_binding_id').AsString;
      Item.AgentRole := Q.FieldByName('agent_role').AsString;
      Item.RawOutput := Q.FieldByName('raw_output').AsString;
      Item.ValidationError := Q.FieldByName('validation_error').AsString;
      Item.RepairCount := Q.FieldByName('repair_count').AsInteger;
      Item.TokenInput := Q.FieldByName('token_input').AsInteger;
      Item.TokenOutput := Q.FieldByName('token_output').AsInteger;
      Item.LatencyMs := Q.FieldByName('latency_ms').AsInteger;
      Item.Provider := Q.FieldByName('provider').AsString;
      Item.Model := Q.FieldByName('model').AsString;
      Item.Capability := Q.FieldByName('capability').AsString;
      Item.RetryCount := Q.FieldByName('retry_count').AsInteger;
      Item.ErrorCode := Q.FieldByName('error_code').AsString;
      Item.Status := Q.FieldByName('status').AsString;
      Item.NormalizedJson := '';
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// Phase 3: Eval result
procedure TDeepFramesRepository.InsertEvalResult(const Eval: TEvalResult);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_eval_result ' +
      '(eval_id, job_id, job_step_id, prompt_run_id, shot_document_id, eval_type, ' +
      'score, dimensions_json, issues_json, gate, gate_result, recommended_action, ' +
      'reviewer_note, schema_version, payload_json, extra_json) ' +
      'VALUES (:eval_id, :job_id, :job_step_id, :prompt_run_id, :shot_document_id, ' +
      ':eval_type, :score, CAST(:dimensions_json AS jsonb), CAST(:issues_json AS jsonb), ' +
      ':gate, :gate_result, :recommended_action, :reviewer_note, ' +
      ':schema_version, CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)) ' +
      'ON CONFLICT (eval_id) DO NOTHING';
    Q.ParamByName('eval_id').AsString := Eval.EvalId;
    Q.ParamByName('job_id').AsString := Eval.JobId;
    Q.ParamByName('job_step_id').AsString := Eval.JobStepId;
    Q.ParamByName('prompt_run_id').AsString := Eval.PromptRunId;
    Q.ParamByName('shot_document_id').AsString := Eval.ShotDocumentId;
    Q.ParamByName('eval_type').AsString := Eval.EvalType;
    Q.ParamByName('score').AsFloat := Eval.Score;
    Q.ParamByName('dimensions_json').AsString := Eval.DimensionsJson;
    Q.ParamByName('issues_json').AsString := Eval.IssuesJson;
    Q.ParamByName('gate').AsString := Eval.Gate;
    Q.ParamByName('gate_result').AsString := Eval.GateResult;
    Q.ParamByName('recommended_action').AsString := Eval.RecommendedAction;
    Q.ParamByName('reviewer_note').AsString := Eval.ReviewerNote;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListEvalResults(
  const JobId: string): TArray<TEvalResult>;
var
  Q: TFDQuery;
  List: TList<TEvalResult>;
  Item: TEvalResult;
begin
  List := TList<TEvalResult>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT eval_id, job_id, job_step_id, prompt_run_id, shot_document_id, eval_type, ' +
      'score, dimensions_json, issues_json, gate, gate_result, recommended_action, reviewer_note ' +
      'FROM deepframes_eval_result WHERE job_id = :job_id ORDER BY created_at';
    Q.ParamByName('job_id').AsString := JobId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.EvalId := Q.FieldByName('eval_id').AsString;
      Item.JobId := Q.FieldByName('job_id').AsString;
      Item.JobStepId := Q.FieldByName('job_step_id').AsString;
      Item.PromptRunId := Q.FieldByName('prompt_run_id').AsString;
      Item.ShotDocumentId := Q.FieldByName('shot_document_id').AsString;
      Item.EvalType := Q.FieldByName('eval_type').AsString;
      Item.Score := Q.FieldByName('score').AsFloat;
      Item.DimensionsJson := Q.FieldByName('dimensions_json').AsString;
      Item.IssuesJson := Q.FieldByName('issues_json').AsString;
      Item.Gate := Q.FieldByName('gate').AsString;
      Item.GateResult := Q.FieldByName('gate_result').AsString;
      Item.RecommendedAction := Q.FieldByName('recommended_action').AsString;
      Item.ReviewerNote := Q.FieldByName('reviewer_note').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Phase 4: Audio manifest
// ---------------------------------------------------------------------------

procedure TDeepFramesRepository.InsertAudioManifest(const Manifest: TAudioManifest);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_audio_manifest ' +
      '(manifest_id, project_id, content_unit_id, job_id, shot_document_id, ' +
      'audio_asset_id, timestamps_asset_id, merged_audio_asset_id, ' +
      'duration_sec, sample_rate, channels, codec, bgm_enabled, ' +
      'tts_rewrite_count, tts_rewrite_log_json, ' +
      'loudnorm_pass1_json, loudnorm_pass2_json, ' +
      'resample_from, resample_to, target_lufs, ' +
      'measured_lufs, measured_tp, measured_lra, concat_duration_delta_ms, ' +
      'status, schema_version) VALUES (' +
      ':manifest_id, :project_id, :content_unit_id, :job_id, :shot_document_id, ' +
      ':audio_asset_id, :timestamps_asset_id, :merged_audio_asset_id, ' +
      ':duration_sec, :sample_rate, :channels, :codec, :bgm_enabled, ' +
      ':tts_rewrite_count, :tts_rewrite_log_json, ' +
      ':loudnorm_pass1_json, :loudnorm_pass2_json, ' +
      ':resample_from, :resample_to, :target_lufs, ' +
      ':measured_lufs, :measured_tp, :measured_lra, :concat_duration_delta_ms, ' +
      ':status, :schema_version)';
    Q.ParamByName('manifest_id').AsString := Manifest.ManifestId;
    Q.ParamByName('project_id').AsString := Manifest.ProjectId;
    Q.ParamByName('content_unit_id').AsString := Manifest.ContentUnitId;
    Q.ParamByName('job_id').AsString := Manifest.JobId;
    Q.ParamByName('shot_document_id').AsString := Manifest.ShotDocumentId;
    Q.ParamByName('audio_asset_id').AsString := Manifest.AudioAssetId;
    Q.ParamByName('timestamps_asset_id').AsString := Manifest.TimestampsAssetId;
    Q.ParamByName('merged_audio_asset_id').AsString := Manifest.MergedAudioAssetId;
    Q.ParamByName('duration_sec').AsFloat := Manifest.DurationSec;
    Q.ParamByName('sample_rate').AsInteger := Manifest.SampleRate;
    Q.ParamByName('channels').AsSmallInt := Manifest.Channels;
    Q.ParamByName('codec').AsString := Manifest.Codec;
    Q.ParamByName('bgm_enabled').AsBoolean := Manifest.BgmEnabled;
    Q.ParamByName('tts_rewrite_count').AsInteger := Manifest.TtsRewriteCount;
    Q.ParamByName('tts_rewrite_log_json').AsString := Manifest.TtsRewriteLogJson;
    Q.ParamByName('loudnorm_pass1_json').AsString := Manifest.LoudnormPass1Json;
    Q.ParamByName('loudnorm_pass2_json').AsString := Manifest.LoudnormPass2Json;
    if Manifest.ResampleFrom > 0 then
      Q.ParamByName('resample_from').AsInteger := Manifest.ResampleFrom
    else
      Q.ParamByName('resample_from').Clear;
    if Manifest.ResampleTo > 0 then
      Q.ParamByName('resample_to').AsInteger := Manifest.ResampleTo
    else
      Q.ParamByName('resample_to').Clear;
    Q.ParamByName('target_lufs').AsFloat := Manifest.TargetLufs;
    Q.ParamByName('measured_lufs').AsFloat := Manifest.MeasuredLufs;
    Q.ParamByName('measured_tp').AsFloat := Manifest.MeasuredTp;
    Q.ParamByName('measured_lra').AsFloat := Manifest.MeasuredLra;
    Q.ParamByName('concat_duration_delta_ms').AsFloat := Manifest.ConcatDurationDeltaMs;
    Q.ParamByName('status').AsString := Manifest.Status;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateAudioManifestStatus(const ManifestId,
  NewStatus: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'UPDATE deepframes_audio_manifest SET status = :status, updated_at = NOW() ' +
      'WHERE manifest_id = :manifest_id';
    Q.ParamByName('status').AsString := NewStatus;
    Q.ParamByName('manifest_id').AsString := ManifestId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateAudioManifestAssets(const ManifestId,
  AudioAssetId, TimestampsAssetId, MergedAudioAssetId: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'UPDATE deepframes_audio_manifest SET ' +
      'audio_asset_id = :audio_asset_id, ' +
      'timestamps_asset_id = :timestamps_asset_id, ' +
      'merged_audio_asset_id = :merged_audio_asset_id, ' +
      'updated_at = NOW() WHERE manifest_id = :manifest_id';
    Q.ParamByName('audio_asset_id').AsString := AudioAssetId;
    Q.ParamByName('timestamps_asset_id').AsString := TimestampsAssetId;
    Q.ParamByName('merged_audio_asset_id').AsString := MergedAudioAssetId;
    Q.ParamByName('manifest_id').AsString := ManifestId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateAudioManifestLoudnorm(const ManifestId: string;
  MeasuredLufs, MeasuredTp, MeasuredLra: Double;
  const Pass1Json, Pass2Json: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'UPDATE deepframes_audio_manifest SET ' +
      'measured_lufs = :measured_lufs, measured_tp = :measured_tp, ' +
      'measured_lra = :measured_lra, loudnorm_pass1_json = :pass1, ' +
      'loudnorm_pass2_json = :pass2, updated_at = NOW() ' +
      'WHERE manifest_id = :manifest_id';
    Q.ParamByName('measured_lufs').AsFloat := MeasuredLufs;
    Q.ParamByName('measured_tp').AsFloat := MeasuredTp;
    Q.ParamByName('measured_lra').AsFloat := MeasuredLra;
    Q.ParamByName('pass1').AsString := Pass1Json;
    Q.ParamByName('pass2').AsString := Pass2Json;
    Q.ParamByName('manifest_id').AsString := ManifestId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateAudioManifestDuration(const ManifestId: string;
  DurationSec, ConcatDeltaMs: Double);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'UPDATE deepframes_audio_manifest SET ' +
      'duration_sec = :duration_sec, concat_duration_delta_ms = :delta, ' +
      'updated_at = NOW() WHERE manifest_id = :manifest_id';
    Q.ParamByName('duration_sec').AsFloat := DurationSec;
    Q.ParamByName('delta').AsFloat := ConcatDeltaMs;
    Q.ParamByName('manifest_id').AsString := ManifestId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListAudioManifests(
  const ContentUnitId: string): TArray<TAudioManifest>;
var
  Q: TFDQuery;
  List: TList<TAudioManifest>;
  Item: TAudioManifest;
begin
  List := TList<TAudioManifest>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT manifest_id, project_id, content_unit_id, job_id, shot_document_id, ' +
      'audio_asset_id, timestamps_asset_id, merged_audio_asset_id, ' +
      'duration_sec, sample_rate, channels, codec, bgm_enabled, ' +
      'tts_rewrite_count, tts_rewrite_log_json, ' +
      'loudnorm_pass1_json, loudnorm_pass2_json, ' +
      'resample_from, resample_to, target_lufs, ' +
      'measured_lufs, measured_tp, measured_lra, concat_duration_delta_ms, status ' +
      'FROM deepframes_audio_manifest WHERE content_unit_id = :cuid ORDER BY created_at';
    Q.ParamByName('cuid').AsString := ContentUnitId;
    Q.Open;
    while not Q.Eof do
    begin
      Item.ManifestId := Q.FieldByName('manifest_id').AsString;
      Item.ProjectId := Q.FieldByName('project_id').AsString;
      Item.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Item.JobId := Q.FieldByName('job_id').AsString;
      Item.ShotDocumentId := Q.FieldByName('shot_document_id').AsString;
      Item.AudioAssetId := Q.FieldByName('audio_asset_id').AsString;
      Item.TimestampsAssetId := Q.FieldByName('timestamps_asset_id').AsString;
      Item.MergedAudioAssetId := Q.FieldByName('merged_audio_asset_id').AsString;
      Item.DurationSec := Q.FieldByName('duration_sec').AsFloat;
      Item.SampleRate := Q.FieldByName('sample_rate').AsInteger;
      Item.Channels := Q.FieldByName('channels').AsInteger;
      Item.Codec := Q.FieldByName('codec').AsString;
      Item.BgmEnabled := Q.FieldByName('bgm_enabled').AsBoolean;
      Item.TtsRewriteCount := Q.FieldByName('tts_rewrite_count').AsInteger;
      Item.TtsRewriteLogJson := Q.FieldByName('tts_rewrite_log_json').AsString;
      Item.LoudnormPass1Json := Q.FieldByName('loudnorm_pass1_json').AsString;
      Item.LoudnormPass2Json := Q.FieldByName('loudnorm_pass2_json').AsString;
      if Q.FieldByName('resample_from').IsNull then
        Item.ResampleFrom := 0
      else
        Item.ResampleFrom := Q.FieldByName('resample_from').AsInteger;
      if Q.FieldByName('resample_to').IsNull then
        Item.ResampleTo := 0
      else
        Item.ResampleTo := Q.FieldByName('resample_to').AsInteger;
      Item.TargetLufs := Q.FieldByName('target_lufs').AsFloat;
      Item.MeasuredLufs := Q.FieldByName('measured_lufs').AsFloat;
      Item.MeasuredTp := Q.FieldByName('measured_tp').AsFloat;
      Item.MeasuredLra := Q.FieldByName('measured_lra').AsFloat;
      Item.ConcatDurationDeltaMs := Q.FieldByName('concat_duration_delta_ms').AsFloat;
      Item.Status := Q.FieldByName('status').AsString;
      List.Add(Item);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TDeepFramesRepository.FindAudioManifestByShot(const ShotDocumentId: string;
  out Manifest: TAudioManifest): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'SELECT manifest_id, project_id, content_unit_id, job_id, shot_document_id, ' +
      'audio_asset_id, timestamps_asset_id, merged_audio_asset_id, ' +
      'duration_sec, sample_rate, channels, codec, bgm_enabled, ' +
      'tts_rewrite_count, tts_rewrite_log_json, ' +
      'loudnorm_pass1_json, loudnorm_pass2_json, ' +
      'resample_from, resample_to, target_lufs, ' +
      'measured_lufs, measured_tp, measured_lra, concat_duration_delta_ms, status ' +
      'FROM deepframes_audio_manifest WHERE shot_document_id = :shot_id ORDER BY created_at DESC LIMIT 1';
    Q.ParamByName('shot_id').AsString := ShotDocumentId;
    Q.Open;
    if not Q.Eof then
    begin
      Manifest.ManifestId := Q.FieldByName('manifest_id').AsString;
      Manifest.ProjectId := Q.FieldByName('project_id').AsString;
      Manifest.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Manifest.JobId := Q.FieldByName('job_id').AsString;
      Manifest.ShotDocumentId := Q.FieldByName('shot_document_id').AsString;
      Manifest.AudioAssetId := Q.FieldByName('audio_asset_id').AsString;
      Manifest.TimestampsAssetId := Q.FieldByName('timestamps_asset_id').AsString;
      Manifest.MergedAudioAssetId := Q.FieldByName('merged_audio_asset_id').AsString;
      Manifest.DurationSec := Q.FieldByName('duration_sec').AsFloat;
      Manifest.SampleRate := Q.FieldByName('sample_rate').AsInteger;
      Manifest.Channels := Q.FieldByName('channels').AsInteger;
      Manifest.Codec := Q.FieldByName('codec').AsString;
      Manifest.BgmEnabled := Q.FieldByName('bgm_enabled').AsBoolean;
      Manifest.TtsRewriteCount := Q.FieldByName('tts_rewrite_count').AsInteger;
      Manifest.TtsRewriteLogJson := Q.FieldByName('tts_rewrite_log_json').AsString;
      Manifest.LoudnormPass1Json := Q.FieldByName('loudnorm_pass1_json').AsString;
      Manifest.LoudnormPass2Json := Q.FieldByName('loudnorm_pass2_json').AsString;
      if Q.FieldByName('resample_from').IsNull then
        Manifest.ResampleFrom := 0
      else
        Manifest.ResampleFrom := Q.FieldByName('resample_from').AsInteger;
      if Q.FieldByName('resample_to').IsNull then
        Manifest.ResampleTo := 0
      else
        Manifest.ResampleTo := Q.FieldByName('resample_to').AsInteger;
      Manifest.TargetLufs := Q.FieldByName('target_lufs').AsFloat;
      Manifest.MeasuredLufs := Q.FieldByName('measured_lufs').AsFloat;
      Manifest.MeasuredTp := Q.FieldByName('measured_tp').AsFloat;
      Manifest.MeasuredLra := Q.FieldByName('measured_lra').AsFloat;
      Manifest.ConcatDurationDeltaMs := Q.FieldByName('concat_duration_delta_ms').AsFloat;
      Manifest.Status := Q.FieldByName('status').AsString;
      Result := True;
    end;
  finally
    Q.Free;
  end;
end;

{ Phase 5: Platform spec }

procedure TDeepFramesRepository.InsertPlatformSpec(const Spec: TPlatformSpec);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_platform_spec (platform_spec_id, platform, delivery_type, aspect_ratio, width, height, fps, video_codec, audio_codec, schema_version, status)' +
      ' VALUES (:platform_spec_id, :platform, :delivery_type, :aspect_ratio, :width, :height, :fps, :video_codec, :audio_codec, :schema_version, :status)';
    Q.ParamByName('platform_spec_id').AsString := Spec.PlatformSpecId;
    Q.ParamByName('platform').AsString := Spec.Platform;
    Q.ParamByName('delivery_type').AsString := Spec.DeliveryType;
    Q.ParamByName('aspect_ratio').AsString := Spec.AspectRatio;
    Q.ParamByName('width').AsInteger := Spec.Width;
    Q.ParamByName('height').AsInteger := Spec.Height;
    Q.ParamByName('fps').AsFloat := Spec.Fps;
    Q.ParamByName('video_codec').AsString := Spec.VideoCodec;
    Q.ParamByName('audio_codec').AsString := Spec.AudioCodec;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('status').AsString := Spec.Status;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListPlatformSpecs: TArray<TPlatformSpec>;
var
  Q: TFDQuery;
  List: TList<TPlatformSpec>;
  Spec: TPlatformSpec;
begin
  List := TList<TPlatformSpec>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_platform_spec ORDER BY platform, delivery_type';
    Q.Open;
    while not Q.Eof do
    begin
      Spec.PlatformSpecId := Q.FieldByName('platform_spec_id').AsString;
      Spec.Platform := Q.FieldByName('platform').AsString;
      Spec.DeliveryType := Q.FieldByName('delivery_type').AsString;
      Spec.AspectRatio := Q.FieldByName('aspect_ratio').AsString;
      Spec.Width := Q.FieldByName('width').AsInteger;
      Spec.Height := Q.FieldByName('height').AsInteger;
      Spec.Fps := Q.FieldByName('fps').AsFloat;
      Spec.VideoCodec := Q.FieldByName('video_codec').AsString;
      Spec.AudioCodec := Q.FieldByName('audio_codec').AsString;
      Spec.Status := Q.FieldByName('status').AsString;
      List.Add(Spec);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

function TDeepFramesRepository.FindPlatformSpecByPlatform(const APlatform: string;
  out Spec: TPlatformSpec): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_platform_spec WHERE platform = :platform AND status = ''active'' ORDER BY created_at DESC LIMIT 1';
    Q.ParamByName('platform').AsString := APlatform;
    Q.Open;
    if not Q.Eof then
    begin
      Spec.PlatformSpecId := Q.FieldByName('platform_spec_id').AsString;
      Spec.Platform := Q.FieldByName('platform').AsString;
      Spec.DeliveryType := Q.FieldByName('delivery_type').AsString;
      Spec.AspectRatio := Q.FieldByName('aspect_ratio').AsString;
      Spec.Width := Q.FieldByName('width').AsInteger;
      Spec.Height := Q.FieldByName('height').AsInteger;
      Spec.Fps := Q.FieldByName('fps').AsFloat;
      Spec.VideoCodec := Q.FieldByName('video_codec').AsString;
      Spec.AudioCodec := Q.FieldByName('audio_codec').AsString;
      Spec.Status := Q.FieldByName('status').AsString;
      Result := True;
    end;
  finally
    Q.Free;
  end;
end;

{ Phase 5: Video IR }

procedure TDeepFramesRepository.InsertVideoIR(const VIR: TVideoIR);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_video_ir (video_ir_id, project_id, content_unit_id, shot_document_id, audio_manifest_id, platform_spec_id,' +
      ' render_backend, template_version, timeline_json, asset_refs_json, duration_source,' +
      ' estimated_duration_sec, actual_duration_sec, scene_count,' +
      ' schema_version, version_no, status, payload_json, extra_json)' +
      ' VALUES (:video_ir_id, :project_id, :content_unit_id, :shot_document_id, :audio_manifest_id, :platform_spec_id,' +
      ' :render_backend, :template_version, :timeline_json, :asset_refs_json, :duration_source,' +
      ' :estimated_duration_sec, :actual_duration_sec, :scene_count,' +
      ' :schema_version, :version_no, :status, :payload_json, :extra_json)';
    Q.ParamByName('video_ir_id').AsString := VIR.VideoIRId;
    Q.ParamByName('project_id').AsString := VIR.ProjectId;
    Q.ParamByName('content_unit_id').AsString := VIR.ContentUnitId;
    Q.ParamByName('shot_document_id').AsString := VIR.ShotDocumentId;
    Q.ParamByName('audio_manifest_id').AsString := VIR.AudioManifestId;
    Q.ParamByName('platform_spec_id').AsString := VIR.PlatformSpecId;
    Q.ParamByName('render_backend').AsString := VIR.RenderBackend;
    Q.ParamByName('template_version').AsString := VIR.TemplateVersion;
    Q.ParamByName('timeline_json').AsString := VIR.TimelineJson;
    Q.ParamByName('asset_refs_json').AsString := VIR.AssetRefsJson;
    Q.ParamByName('duration_source').AsString := VIR.DurationSource;
    Q.ParamByName('estimated_duration_sec').AsFloat := VIR.EstimatedDurationSec;
    Q.ParamByName('actual_duration_sec').AsFloat := VIR.ActualDurationSec;
    Q.ParamByName('scene_count').AsInteger := VIR.SceneCount;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('version_no').AsInteger := VIR.VersionNo;
    Q.ParamByName('status').AsString := VIR.Status;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateVideoIRStatus(const VideoIRId, NewStatus: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text := 'UPDATE deepframes_video_ir SET status = :status, updated_at = NOW() WHERE video_ir_id = :id';
    Q.ParamByName('status').AsString := NewStatus;
    Q.ParamByName('id').AsString := VideoIRId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateVideoIRDuration(const VideoIRId: string;
  Estimated, Actual: Double);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text := 'UPDATE deepframes_video_ir SET estimated_duration_sec = :est, actual_duration_sec = :act, updated_at = NOW() WHERE video_ir_id = :id';
    Q.ParamByName('est').AsFloat := Estimated;
    Q.ParamByName('act').AsFloat := Actual;
    Q.ParamByName('id').AsString := VideoIRId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListVideoIRs(const ContentUnitId: string): TArray<TVideoIR>;
var
  Q: TFDQuery;
  List: TList<TVideoIR>;
  VIR: TVideoIR;
begin
  List := TList<TVideoIR>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_video_ir WHERE content_unit_id = :cuid ORDER BY created_at DESC';
    Q.ParamByName('cuid').AsString := ContentUnitId;
    Q.Open;
    while not Q.Eof do
    begin
      VIR.VideoIRId := Q.FieldByName('video_ir_id').AsString;
      VIR.ProjectId := Q.FieldByName('project_id').AsString;
      VIR.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      VIR.ShotDocumentId := Q.FieldByName('shot_document_id').AsString;
      VIR.AudioManifestId := Q.FieldByName('audio_manifest_id').AsString;
      VIR.PlatformSpecId := Q.FieldByName('platform_spec_id').AsString;
      VIR.RenderBackend := Q.FieldByName('render_backend').AsString;
      VIR.TemplateVersion := Q.FieldByName('template_version').AsString;
      VIR.DurationSource := Q.FieldByName('duration_source').AsString;
      VIR.EstimatedDurationSec := Q.FieldByName('estimated_duration_sec').AsFloat;
      VIR.ActualDurationSec := Q.FieldByName('actual_duration_sec').AsFloat;
      VIR.SceneCount := Q.FieldByName('scene_count').AsInteger;
      VIR.VersionNo := Q.FieldByName('version_no').AsInteger;
      VIR.Status := Q.FieldByName('status').AsString;
      List.Add(VIR);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

{ Phase 5: Video job }

procedure TDeepFramesRepository.InsertVideoJob(const VJob: TVideoJob);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_video_job (video_job_id, job_id, video_ir_id, platform_spec_id,' +
      ' render_backend, run_mode, template_id, output_dir, schema_version, status, payload_json, extra_json)' +
      ' VALUES (:video_job_id, :job_id, :video_ir_id, :platform_spec_id,' +
      ' :render_backend, :run_mode, :template_id, :output_dir, :schema_version, :status, :payload_json, :extra_json)';
    Q.ParamByName('video_job_id').AsString := VJob.VideoJobId;
    Q.ParamByName('job_id').AsString := VJob.JobId;
    Q.ParamByName('video_ir_id').AsString := VJob.VideoIRId;
    Q.ParamByName('platform_spec_id').AsString := VJob.PlatformSpecId;
    Q.ParamByName('render_backend').AsString := VJob.RenderBackend;
    Q.ParamByName('run_mode').AsString := VJob.RunMode;
    Q.ParamByName('template_id').AsString := VJob.TemplateId;
    Q.ParamByName('output_dir').AsString := VJob.OutputDir;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('status').AsString := VJob.Status;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateVideoJobStatus(const VideoJobId, NewStatus: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text := 'UPDATE deepframes_video_job SET status = :status, updated_at = NOW() WHERE video_job_id = :id';
    Q.ParamByName('status').AsString := NewStatus;
    Q.ParamByName('id').AsString := VideoJobId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListVideoJobs(const VideoIRId: string): TArray<TVideoJob>;
var
  Q: TFDQuery;
  List: TList<TVideoJob>;
  VJob: TVideoJob;
begin
  List := TList<TVideoJob>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_video_job WHERE video_ir_id = :vir_id ORDER BY created_at DESC';
    Q.ParamByName('vir_id').AsString := VideoIRId;
    Q.Open;
    while not Q.Eof do
    begin
      VJob.VideoJobId := Q.FieldByName('video_job_id').AsString;
      VJob.JobId := Q.FieldByName('job_id').AsString;
      VJob.VideoIRId := Q.FieldByName('video_ir_id').AsString;
      VJob.PlatformSpecId := Q.FieldByName('platform_spec_id').AsString;
      VJob.RenderBackend := Q.FieldByName('render_backend').AsString;
      VJob.RunMode := Q.FieldByName('run_mode').AsString;
      VJob.TemplateId := Q.FieldByName('template_id').AsString;
      VJob.OutputDir := Q.FieldByName('output_dir').AsString;
      VJob.Status := Q.FieldByName('status').AsString;
      List.Add(VJob);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

{ Phase 5: Video step }

procedure TDeepFramesRepository.InsertVideoStep(const VStep: TVideoStep);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_video_step (video_step_id, video_job_id, step_type, step_key,' +
      ' shot_id, asset_id, metrics_json, error_message, schema_version, status, payload_json, extra_json)' +
      ' VALUES (:video_step_id, :video_job_id, :step_type, :step_key,' +
      ' :shot_id, :asset_id, :metrics_json, :error_message, :schema_version, :status, :payload_json, :extra_json)';
    Q.ParamByName('video_step_id').AsString := VStep.VideoStepId;
    Q.ParamByName('video_job_id').AsString := VStep.VideoJobId;
    Q.ParamByName('step_type').AsString := VStep.StepType;
    Q.ParamByName('step_key').AsString := VStep.StepKey;
    Q.ParamByName('shot_id').AsString := VStep.ShotId;
    Q.ParamByName('asset_id').AsString := VStep.AssetId;
    Q.ParamByName('metrics_json').AsString := VStep.MetricsJson;
    Q.ParamByName('error_message').AsString := VStep.ErrorMessage;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('status').AsString := VStep.Status;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateVideoStepStatus(const VideoStepId, NewStatus: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text := 'UPDATE deepframes_video_step SET status = :status, updated_at = NOW() WHERE video_step_id = :id';
    Q.ParamByName('status').AsString := NewStatus;
    Q.ParamByName('id').AsString := VideoStepId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListVideoSteps(const VideoJobId: string): TArray<TVideoStep>;
var
  Q: TFDQuery;
  List: TList<TVideoStep>;
  VStep: TVideoStep;
begin
  List := TList<TVideoStep>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_video_step WHERE video_job_id = :vjob_id ORDER BY created_at';
    Q.ParamByName('vjob_id').AsString := VideoJobId;
    Q.Open;
    while not Q.Eof do
    begin
      VStep.VideoStepId := Q.FieldByName('video_step_id').AsString;
      VStep.VideoJobId := Q.FieldByName('video_job_id').AsString;
      VStep.StepType := Q.FieldByName('step_type').AsString;
      VStep.StepKey := Q.FieldByName('step_key').AsString;
      VStep.ShotId := Q.FieldByName('shot_id').AsString;
      VStep.AssetId := Q.FieldByName('asset_id').AsString;
      VStep.MetricsJson := Q.FieldByName('metrics_json').AsString;
      VStep.ErrorMessage := Q.FieldByName('error_message').AsString;
      VStep.Status := Q.FieldByName('status').AsString;
      List.Add(VStep);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

{ Phase 5: Video asset }

procedure TDeepFramesRepository.InsertVideoAsset(const VAsset: TVideoAsset);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_video_asset (video_asset_id, video_job_id, video_step_id,' +
      ' asset_id, asset_category, shot_index, schema_version, payload_json)' +
      ' VALUES (:video_asset_id, :video_job_id, :video_step_id,' +
      ' :asset_id, :asset_category, :shot_index, :schema_version, :payload_json)';
    Q.ParamByName('video_asset_id').AsString := VAsset.VideoAssetId;
    Q.ParamByName('video_job_id').AsString := VAsset.VideoJobId;
    Q.ParamByName('video_step_id').AsString := VAsset.VideoStepId;
    Q.ParamByName('asset_id').AsString := VAsset.AssetId;
    Q.ParamByName('asset_category').AsString := VAsset.AssetCategory;
    Q.ParamByName('shot_index').AsInteger := VAsset.ShotIndex;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListVideoAssets(const VideoJobId: string): TArray<TVideoAsset>;
var
  Q: TFDQuery;
  List: TList<TVideoAsset>;
  VAsset: TVideoAsset;
begin
  List := TList<TVideoAsset>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_video_asset WHERE video_job_id = :vjob_id ORDER BY shot_index';
    Q.ParamByName('vjob_id').AsString := VideoJobId;
    Q.Open;
    while not Q.Eof do
    begin
      VAsset.VideoAssetId := Q.FieldByName('video_asset_id').AsString;
      VAsset.VideoJobId := Q.FieldByName('video_job_id').AsString;
      VAsset.VideoStepId := Q.FieldByName('video_step_id').AsString;
      VAsset.AssetId := Q.FieldByName('asset_id').AsString;
      VAsset.AssetCategory := Q.FieldByName('asset_category').AsString;
      VAsset.ShotIndex := Q.FieldByName('shot_index').AsInteger;
      List.Add(VAsset);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

{ Phase 6: Candidate package }

procedure TDeepFramesRepository.InsertCandidatePackage(const Pkg: TCandidatePackage);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text :=
      'INSERT INTO deepframes_candidate_package (package_id, project_id, content_unit_id,' +
      ' variant_document_id, audio_manifest_id, video_ir_id, target_platform, delivery_type,' +
      ' manifest_asset_id, cover_asset_id, metadata_json, quality_snapshot_json,' +
      ' source_trace_json, output_root_uri, label, schema_version, version_no, status, payload_json, extra_json)' +
      ' VALUES (:package_id, :project_id, :content_unit_id,' +
      ' :variant_document_id, :audio_manifest_id, :video_ir_id, :target_platform, :delivery_type,' +
      ' :manifest_asset_id, :cover_asset_id, :metadata_json, :quality_snapshot_json,' +
      ' :source_trace_json, :output_root_uri, :label, :schema_version, :version_no, :status, :payload_json, :extra_json)';
    Q.ParamByName('package_id').AsString := Pkg.PackageId;
    Q.ParamByName('project_id').AsString := Pkg.ProjectId;
    Q.ParamByName('content_unit_id').AsString := Pkg.ContentUnitId;
    Q.ParamByName('variant_document_id').AsString := Pkg.VariantDocumentId;
    Q.ParamByName('audio_manifest_id').AsString := Pkg.AudioManifestId;
    Q.ParamByName('video_ir_id').AsString := Pkg.VideoIRId;
    Q.ParamByName('target_platform').AsString := Pkg.TargetPlatform;
    Q.ParamByName('delivery_type').AsString := Pkg.DeliveryType;
    Q.ParamByName('manifest_asset_id').AsString := Pkg.ManifestAssetId;
    Q.ParamByName('cover_asset_id').AsString := Pkg.CoverAssetId;
    Q.ParamByName('metadata_json').AsString := Pkg.MetadataJson;
    Q.ParamByName('quality_snapshot_json').AsString := Pkg.QualitySnapshotJson;
    Q.ParamByName('source_trace_json').AsString := Pkg.SourceTraceJson;
    Q.ParamByName('output_root_uri').AsString := Pkg.OutputRootUri;
    Q.ParamByName('label').AsString := Pkg.&Label;
    Q.ParamByName('schema_version').AsString := APP_SCHEMA_VERSION;
    Q.ParamByName('version_no').AsInteger := Pkg.VersionNo;
    Q.ParamByName('status').AsString := Pkg.Status;
    Q.ParamByName('payload_json').AsString := '{}';
    Q.ParamByName('extra_json').AsString := '{}';
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TDeepFramesRepository.UpdateCandidatePackageStatus(const PackageId, NewStatus: string);
var
  Q: TFDQuery;
begin
  Q := NewQuery;
  try
    Q.SQL.Text := 'UPDATE deepframes_candidate_package SET status = :status, updated_at = NOW() WHERE package_id = :id';
    Q.ParamByName('status').AsString := NewStatus;
    Q.ParamByName('id').AsString := PackageId;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function TDeepFramesRepository.ListCandidatePackages(const ProjectId: string): TArray<TCandidatePackage>;
var
  Q: TFDQuery;
  List: TList<TCandidatePackage>;
  Pkg: TCandidatePackage;
begin
  List := TList<TCandidatePackage>.Create;
  Q := NewQuery;
  try
    Q.SQL.Text := 'SELECT * FROM deepframes_candidate_package WHERE project_id = :pid ORDER BY created_at DESC';
    Q.ParamByName('pid').AsString := ProjectId;
    Q.Open;
    while not Q.Eof do
    begin
      Pkg.PackageId := Q.FieldByName('package_id').AsString;
      Pkg.ProjectId := Q.FieldByName('project_id').AsString;
      Pkg.ContentUnitId := Q.FieldByName('content_unit_id').AsString;
      Pkg.VariantDocumentId := Q.FieldByName('variant_document_id').AsString;
      Pkg.AudioManifestId := Q.FieldByName('audio_manifest_id').AsString;
      Pkg.VideoIRId := Q.FieldByName('video_ir_id').AsString;
      Pkg.TargetPlatform := Q.FieldByName('target_platform').AsString;
      Pkg.DeliveryType := Q.FieldByName('delivery_type').AsString;
      Pkg.ManifestAssetId := Q.FieldByName('manifest_asset_id').AsString;
      Pkg.CoverAssetId := Q.FieldByName('cover_asset_id').AsString;
      Pkg.MetadataJson := Q.FieldByName('metadata_json').AsString;
      Pkg.QualitySnapshotJson := Q.FieldByName('quality_snapshot_json').AsString;
      Pkg.SourceTraceJson := Q.FieldByName('source_trace_json').AsString;
      Pkg.OutputRootUri := Q.FieldByName('output_root_uri').AsString;
      Pkg.&Label := Q.FieldByName('label').AsString;
      Pkg.VersionNo := Q.FieldByName('version_no').AsInteger;
      Pkg.Status := Q.FieldByName('status').AsString;
      List.Add(Pkg);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;

end.
