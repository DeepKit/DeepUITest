unit DeepFrames.App.Services;

interface

uses
  DeepFrames.Domain.Types;

type
  /// <summary>Per-phase progress callback for async pipeline (DBA-4). Fires on
  /// the worker thread after each phase completes.</summary>
  TPipelineProgressEvent = reference to procedure(const APhase: string; const AJob: TDeepFramesJob);

  /// <summary>Completion callback for async pipeline (DBA-4). Fires on the
  /// worker thread with the final (package) job. Callers touching VCL must
  /// marshal via TThread.Queue(nil, ...).</summary>
  TPipelineCompleteEvent = reference to procedure(const AFinalJob: TDeepFramesJob);

  /// <summary>Snapshot of an async pipeline job's state (DBA-4).</summary>
  TPipelineStatus = record
    JobId: string;
    Status: string;        // running | completed | failed
    IsTerminal: Boolean;
    FinalJob: TDeepFramesJob;
    CurrentPhase: string;
  end;

  /// <summary>
  /// Application service mediating between UI and persistence.
  /// All UI code must call this service; direct Repository access from UI
  /// violates Red Line 3 (ENGINEERING_HANDOFF.md section 6).
  /// </summary>
  TDeepFramesAppService = class
  public
    /// <summary>Create a new project with a default content unit.</summary>
    class function CreateProject(const ATitle: string): TProjectInfo; static;

    /// <summary>Import markdown text as a source_document under the first project's first content unit.</summary>
    class function ImportMarkdown(const AFileName: string): TSourceDocumentVersion; static;

    /// <summary>Run the Phase 1 preprocess workflow for the first available source document.</summary>
    class function RunPreprocess: TDeepFramesJob; static;

    /// <summary>Return all projects.</summary>
    class function ListProjects: TArray<TProjectInfo>; static;

    /// <summary>Return content units for a given project.</summary>
    class function ListContentUnits(const AProjectId: string): TArray<TContentUnitInfo>; static;

    /// <summary>Return source documents for a given project.</summary>
    class function ListSourceDocuments(const AProjectId: string): TArray<TSourceDocumentVersion>; static;

    /// <summary>Return all jobs.</summary>
    class function ListJobs: TArray<TDeepFramesJob>; static;

    /// <summary>Return steps for a given job.</summary>
    class function ListJobSteps(const AJobId: string): TArray<TDeepFramesJobStep>; static;

    /// <summary>Test DB2 PostgreSQL connection.</summary>
    class function TestDb2Connection(out AError: string): Boolean; static;

    /// <summary>Run DB2 PostgreSQL migrations.</summary>
    class function RunDb2Migrations(out AApplied, ASkipped: Integer; out AError: string): Boolean; static;

    // Phase 2: Document chain
    /// <summary>Run the Phase 2 document chain workflow (stub data).</summary>
    class function RunDocumentChain: TDeepFramesJob; static;

    /// <summary>Return script documents for a given project.</summary>
    class function ListScriptDocuments(const AProjectId: string): TArray<TScriptDocumentVersion>; static;

    /// <summary>Return accuracy reports for a given script document.</summary>
    class function ListAccuracyReports(const AScriptDocumentId: string): TArray<TAccuracyReport>; static;

    /// <summary>Return variant documents for a given content unit.</summary>
    class function ListVariantDocuments(const AContentUnitId: string): TArray<TVariantDocumentVersion>; static;

    /// <summary>Return shot documents for a given content unit.</summary>
    class function ListShotDocuments(const AContentUnitId: string): TArray<TShotDocumentVersion>; static;

    /// <summary>Return assets for a given content unit.</summary>
    class function ListAssets(const AContentUnitId: string): TArray<TAssetRecord>; static;

    /// <summary>Return quality gate results for a given job.</summary>
    class function ListQualityGateResults(const AJobId: string): TArray<TQualityGateResult>; static;

    /// <summary>Record human review on a quality gate result.</summary>
    class procedure RecordHumanReview(const AResultId, AAction, ANote: string); static;

    // Phase 3: Agent chain
    /// <summary>Run the Phase 3 agent chain workflow (fake provider).</summary>
    class function RunAgentChain: TDeepFramesJob; static;

    /// <summary>Return prompt templates, optionally filtered by agent role.</summary>
    class function ListPromptTemplates(const AAgentRole: string): TArray<TPromptTemplate>; static;

    /// <summary>Return model bindings, optionally filtered by agent role.</summary>
    class function ListModelBindings(const AAgentRole: string): TArray<TModelBinding>; static;

    /// <summary>Return prompt runs for a given job.</summary>
    class function ListPromptRuns(const AJobId: string): TArray<TPromptRun>; static;

    /// <summary>Return eval results for a given job.</summary>
    class function ListEvalResults(const AJobId: string): TArray<TEvalResult>; static;

    // Phase 4: Audio chain
    /// <summary>Run the Phase 4 audio chain workflow (fake TTS/ASR).</summary>
    class function RunAudioChain: TDeepFramesJob; static;

    /// <summary>Return audio manifests for a given content unit.</summary>
    class function ListAudioManifests(const AContentUnitId: string): TArray<TAudioManifest>; static;

    // Phase 5: Video chain
    /// <summary>Run the Phase 5 video chain workflow (fake HyperFrames).</summary>
    class function RunVideoChain: TDeepFramesJob; static;

    /// <summary>Return video IRs for a given content unit.</summary>
    class function ListVideoIRs(const AContentUnitId: string): TArray<TVideoIR>; static;

    /// <summary>Return video jobs for a given video IR.</summary>
    class function ListVideoJobs(const AVideoIRId: string): TArray<TVideoJob>; static;

    /// <summary>Return video steps for a given video job.</summary>
    class function ListVideoSteps(const AVideoJobId: string): TArray<TVideoStep>; static;

    /// <summary>Return video assets for a given video job.</summary>
    class function ListVideoAssets(const AVideoJobId: string): TArray<TVideoAsset>; static;

    /// <summary>Return all platform specs.</summary>
    class function ListPlatformSpecs: TArray<TPlatformSpec>; static;

    // Phase 6: Candidate package
    /// <summary>Run the Phase 6 candidate package workflow.</summary>
    class function RunPackageChain: TDeepFramesJob; static;

    /// <summary>Run the entire pipeline end-to-end: preprocess → document →
    /// agent → audio → video → package. Each phase persists its output to
    /// the repository and the next phase resolves it fresh from the DB, so
    /// the pipeline is a sequential composition of the per-phase Run*
    /// methods. Stops at the first phase whose job status is not done/
    /// completed and returns that job (carrying STATUS_FAILED /
    /// STATUS_BLOCKED_REVIEW), so callers can inspect which phase broke.
    /// Returns the final (package) job on success.</summary>
    class function RunFullPipeline(const ForceRerun: Boolean = False): TDeepFramesJob; static;

    /// <summary>Synchronous pipeline core (DBA-4). Shared body of the blocking
    /// RunFullPipeline wrapper and the worker-thread handler. AOnProgress fires
    /// after each phase (caller thread). Internal — prefer RunFullPipeline /
    /// RunFullPipelineAsync from outside.</summary>
    class function RunFullPipelineSync(const ForceRerun: Boolean;
      const AOnProgress: TPipelineProgressEvent): TDeepFramesJob; static;

    /// <summary>Run the full pipeline asynchronously via DeepBase TWorkerQueue,
    /// so the GUI main thread / CLI prompt is not blocked. Returns the internal
    /// TJob.Id immediately (the pipeline runs on a worker thread). AOnProgress
    /// fires after each phase completes (worker thread — callers touching VCL
    /// must marshal via TThread.Queue). AOnComplete fires with the final job on
    /// the worker thread. DBA-4 (tasks.md line 78: 编排走 ExecuteAsync/Scheduler).
    /// Idempotency/断点续传 relies on the per-phase Run* FindJobByLogicalKey
    /// short-circuit (续9/13 already verified); no DependsOn chain (excluded:
    /// in-memory TWorkerQueue loses jobs on crash — DB state still drives resume).</summary>
    class function RunFullPipelineAsync(
      const ForceRerun: Boolean = False;
      const AOnProgress: TPipelineProgressEvent = nil;
      const AOnComplete: TPipelineCompleteEvent = nil): string; static;

    /// <summary>Poll the async pipeline job started by RunFullPipelineAsync.
    /// Returns the current TJob status + the final TDeepFramesJob once terminal.
    /// Used by CLI --run-pipeline poll loop and GUI status display.</summary>
    class function GetPipelineStatus(const APipelineJobId: string): TPipelineStatus; static;

    /// <summary>Return candidate packages for a given project.</summary>
    class function ListCandidatePackages(const AProjectId: string): TArray<TCandidatePackage>; static;

    // Phase 7: Extension capabilities
    /// <summary>Run the Phase 7 extension chain workflow.</summary>
    class function RunExtensionChain: TDeepFramesJob; static;

    /// <summary>Return all BGM libraries.</summary>
    class function ListBgmLibraries: TArray<TBgmLibrary>; static;

    /// <summary>Return BGM tracks for a given library.</summary>
    class function ListBgmTracks(const ALibraryId: string): TArray<TBgmTrack>; static;

    /// <summary>Return all content type adapters.</summary>
    class function ListContentTypeAdapters: TArray<TContentTypeAdapter>; static;

    /// <summary>Return readiness reports for a given adapter.</summary>
    class function ListReadinessReports(const AAdapterId: string): TArray<TReadinessReport>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  System.IOUtils,
  Winapi.Windows,
  DeepBase.DB.Migrations,
  DeepBase.Logging,
  DeepBase.WorkerQueue,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Connection,
  DeepFrames.Persistence.Migrations,
  DeepFrames.Persistence.Repository,
  DeepFrames.Workflow.Preprocess,
  DeepFrames.Workflow.DocumentChain,
  DeepFrames.Workflow.AgentChain,
  DeepFrames.Workflow.AudioChain,
  DeepFrames.Workflow.VideoChain,
  DeepFrames.Workflow.PackageChain,
  DeepFrames.Workflow.ExtensionChain,
  DeepFrames.Shared.Consts;

{ TDeepFramesAppService }

class function TDeepFramesAppService.CreateProject(
  const ATitle: string): TProjectInfo;
var
  UnitInfo: TContentUnitInfo;
  Repo: TDeepFramesRepository;
begin
  Result := TProjectService.CreateNewProject(ATitle, 'longform_zh_article');
  UnitInfo := TProjectService.CreateDefaultContentUnit(Result.ProjectId, 'Imported article');

  Repo := TDeepFramesRepository.Create;
  try
    // Pool-backed TFDConnection does NOT auto-commit implicit transactions on
    // connection return — without an explicit commit, the inserted project/unit
    // stay uncommitted on the pooled connection and are invisible to a fresh
    // connection (e.g. the one ImportMarkdown opens next), causing a spurious
    // "Selected project has no content unit" failure. Wrap both inserts in one
    // explicit transaction and commit before the connection returns to the pool.
    Repo.BeginTransaction;
    try
      Repo.InsertProject(Result);
      Repo.InsertContentUnit(UnitInfo);
      Repo.CommitTransaction;
    except
      Repo.RollbackTransaction;
      raise;
    end;
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ImportMarkdown(
  const AFileName: string): TSourceDocumentVersion;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Text: string;
begin
  Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);

  Repo := TDeepFramesRepository.Create;
  try
    Projects := Repo.ListProjects;
    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before importing markdown');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);
    Logger.InfoFmt(
      'ImportMarkdown projects=%d proj0=%s units=%d',
      [Length(Projects), Projects[0].ProjectId, Length(Units)],
      'DeepFrames.App');
    if Length(Units) = 0 then
      raise Exception.Create('Selected project has no content unit');

    Result := TProjectService.CreateSourceDocument(
      Projects[0].ProjectId, Units[0].ContentUnitId, AFileName, Text, 1);
    Repo.InsertSourceDocument(Result);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.RunPreprocess: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Docs: TArray<TSourceDocumentVersion>;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Projects := Repo.ListProjects;
    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before running preprocess');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);
    Docs := Repo.ListSourceDocuments(Projects[0].ProjectId);
    if (Length(Units) = 0) or (Length(Docs) = 0) then
      raise Exception.Create('Import a source document before running preprocess');
  finally
    Repo.Free;
  end;

  Result := TPreprocessWorkflow.RunPreprocess(
    Projects[0].ProjectId, Units[0].ContentUnitId, Docs[0].DocumentId);
end;

class function TDeepFramesAppService.ListProjects: TArray<TProjectInfo>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListProjects;
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListContentUnits(
  const AProjectId: string): TArray<TContentUnitInfo>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListContentUnits(AProjectId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListSourceDocuments(
  const AProjectId: string): TArray<TSourceDocumentVersion>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListSourceDocuments(AProjectId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListJobs: TArray<TDeepFramesJob>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListJobs;
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListJobSteps(
  const AJobId: string): TArray<TDeepFramesJobStep>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListJobSteps(AJobId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.TestDb2Connection(
  out AError: string): Boolean;
begin
  Result := TDeepFramesDB2Connection.TestConnection(AError);
end;

class function TDeepFramesAppService.RunDb2Migrations(out AApplied,
  ASkipped: Integer; out AError: string): Boolean;
var
  ResultInfo: TMigrationResult;
begin
  AApplied := 0;
  ASkipped := 0;
  AError := '';
  ResultInfo := TDeepFramesMigrations.RunMigrations;
  AApplied := ResultInfo.AppliedCount;
  ASkipped := ResultInfo.SkippedCount;
  if not ResultInfo.Success then
    AError := ResultInfo.LastError;
  Result := ResultInfo.Success;
end;

class function TDeepFramesAppService.RunDocumentChain: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Docs: TArray<TSourceDocumentVersion>;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Projects := Repo.ListProjects;
    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before running document chain');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);
    Docs := Repo.ListSourceDocuments(Projects[0].ProjectId);
    if (Length(Units) = 0) or (Length(Docs) = 0) then
      raise Exception.Create('Import a source document before running document chain');
  finally
    Repo.Free;
  end;

  Result := TDocumentChainWorkflow.RunChain(
    Projects[0].ProjectId, Units[0].ContentUnitId, Docs[0].DocumentId);
end;

class function TDeepFramesAppService.ListScriptDocuments(
  const AProjectId: string): TArray<TScriptDocumentVersion>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListScriptDocuments(AProjectId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListAccuracyReports(
  const AScriptDocumentId: string): TArray<TAccuracyReport>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListAccuracyReports(AScriptDocumentId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListVariantDocuments(
  const AContentUnitId: string): TArray<TVariantDocumentVersion>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListVariantDocuments(AContentUnitId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListShotDocuments(
  const AContentUnitId: string): TArray<TShotDocumentVersion>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListShotDocuments(AContentUnitId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListAssets(
  const AContentUnitId: string): TArray<TAssetRecord>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListAssets(AContentUnitId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListQualityGateResults(
  const AJobId: string): TArray<TQualityGateResult>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListQualityGateResults(AJobId);
  finally
    Repo.Free;
  end;
end;

class procedure TDeepFramesAppService.RecordHumanReview(const AResultId,
  AAction, ANote: string);
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Repo.UpdateQualityGateHumanReview(AResultId, AAction, ANote);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.RunAgentChain: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Shots: TArray<TShotDocumentVersion>;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Projects := Repo.ListProjects;
    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before running agent chain');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);
    if Length(Units) = 0 then
      raise Exception.Create('No content unit available');
    Shots := Repo.ListShotDocuments(Units[0].ContentUnitId);
  finally
    Repo.Free;
  end;

  // Use first shot document if available, otherwise empty string
  if Length(Shots) > 0 then
    Result := TAgentChainWorkflow.RunChain(
      Projects[0].ProjectId, Units[0].ContentUnitId, Shots[0].DocumentId)
  else
    Result := TAgentChainWorkflow.RunChain(
      Projects[0].ProjectId, Units[0].ContentUnitId, '');
end;

class function TDeepFramesAppService.ListPromptTemplates(
  const AAgentRole: string): TArray<TPromptTemplate>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListPromptTemplates(AAgentRole);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListModelBindings(
  const AAgentRole: string): TArray<TModelBinding>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListModelBindings(AAgentRole);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListPromptRuns(
  const AJobId: string): TArray<TPromptRun>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListPromptRuns(AJobId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListEvalResults(
  const AJobId: string): TArray<TEvalResult>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListEvalResults(AJobId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.RunAudioChain: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Shots: TArray<TShotDocumentVersion>;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Projects := Repo.ListProjects;
    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before running audio chain');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);
    if Length(Units) = 0 then
      raise Exception.Create('No content unit available');
    Shots := Repo.ListShotDocuments(Units[0].ContentUnitId);
  finally
    Repo.Free;
  end;

  // Use first shot document if available
  if Length(Shots) > 0 then
    Result := TAudioChainWorkflow.RunChain(
      Projects[0].ProjectId, Units[0].ContentUnitId, Shots[0].DocumentId)
  else
    Result := TAudioChainWorkflow.RunChain(
      Projects[0].ProjectId, Units[0].ContentUnitId, '');
end;

class function TDeepFramesAppService.ListAudioManifests(
  const AContentUnitId: string): TArray<TAudioManifest>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListAudioManifests(AContentUnitId);
  finally
    Repo.Free;
  end;
end;

{ Phase 5: Video chain }

class function TDeepFramesAppService.RunVideoChain: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Shots: TArray<TShotDocumentVersion>;
  Manifests: TArray<TAudioManifest>;
  AudioManifestId: string;
begin
  Repo := TDeepFramesRepository.Create;

  try
    Projects := Repo.ListProjects;

    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before running video chain');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);

    if Length(Units) = 0 then
      raise Exception.Create('No content unit available');
    Shots := Repo.ListShotDocuments(Units[0].ContentUnitId);

    // Skip FindAudioManifestByShot due to AV bug - use ListAudioManifests instead
    Manifests := Repo.ListAudioManifests(Units[0].ContentUnitId);

    if Length(Manifests) > 0 then
      AudioManifestId := Manifests[0].ManifestId
    else
      AudioManifestId := '';
  finally
    Repo.Free;
  end;

  if Length(Shots) > 0 then
    Result := TVideoChainWorkflow.RunChain(
      Projects[0].ProjectId, Units[0].ContentUnitId, Shots[0].DocumentId,
      AudioManifestId)
  else
    Result := TVideoChainWorkflow.RunChain(
      Projects[0].ProjectId, Units[0].ContentUnitId, '', AudioManifestId);
end;

class function TDeepFramesAppService.ListVideoIRs(
  const AContentUnitId: string): TArray<TVideoIR>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListVideoIRs(AContentUnitId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListVideoJobs(
  const AVideoIRId: string): TArray<TVideoJob>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListVideoJobs(AVideoIRId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListVideoSteps(
  const AVideoJobId: string): TArray<TVideoStep>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListVideoSteps(AVideoJobId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListVideoAssets(
  const AVideoJobId: string): TArray<TVideoAsset>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListVideoAssets(AVideoJobId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListPlatformSpecs: TArray<TPlatformSpec>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListPlatformSpecs;
  finally
    Repo.Free;
  end;
end;

{ Phase 6: Candidate package }

class function TDeepFramesAppService.RunPackageChain: TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Projects: TArray<TProjectInfo>;
  Units: TArray<TContentUnitInfo>;
  Variants: TArray<TVariantDocumentVersion>;
  Manifests: TArray<TAudioManifest>;
  VideoIRs: TArray<TVideoIR>;
  VariantDocId, AudioManifestId, VideoIRId: string;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Projects := Repo.ListProjects;
    if Length(Projects) = 0 then
      raise Exception.Create('Create a project before running package chain');
    Units := Repo.ListContentUnits(Projects[0].ProjectId);
    if Length(Units) = 0 then
      raise Exception.Create('No content unit available');

    // Resolve variant document
    Variants := Repo.ListVariantDocuments(Units[0].ContentUnitId);
    if Length(Variants) > 0 then
      VariantDocId := Variants[0].DocumentId
    else
      VariantDocId := '';

    // Resolve audio manifest
    Manifests := Repo.ListAudioManifests(Units[0].ContentUnitId);
    if Length(Manifests) > 0 then
      AudioManifestId := Manifests[0].ManifestId
    else
      AudioManifestId := '';

    // Resolve video IR
    VideoIRs := Repo.ListVideoIRs(Units[0].ContentUnitId);
    if Length(VideoIRs) > 0 then
      VideoIRId := VideoIRs[0].VideoIRId
    else
      VideoIRId := '';
  finally
    Repo.Free;
  end;

  Result := TPackageChainWorkflow.RunChain(
    Projects[0].ProjectId, Units[0].ContentUnitId,
    VariantDocId, AudioManifestId, VideoIRId, PLATFORM_BILIBILI);
end;

{ Full pipeline: sequential composition of every per-phase Run* method.
  Data flows between phases through the repository, not through the
  returned TDeepFramesJob (which carries only JobId/Status, no artifact
  IDs), so each Run* re-resolves its inputs from the DB. We therefore just
  call them in order and inspect each returned job's Status. A phase that
  ends in STATUS_DONE / STATUS_COMPLETED lets the pipeline proceed; any
  other status (failed, blocked_review, cancelled) halts and is returned
  so the caller knows which phase broke. The success path returns the
  final package-chain job. }

function IsPhaseComplete(const AStatus: string): Boolean;
begin
  Result := SameText(AStatus, STATUS_DONE) or
            SameText(AStatus, STATUS_COMPLETED);
end;

{ DBA-4: async pipeline bookkeeping. A single DeepFrames-owned TWorkerQueue
  runs pipeline jobs on worker threads (registered handler per JobType).
  Per-instance caller callbacks (AOnProgress/AOnComplete) are stashed in
  GPipelineCallbacks keyed by JobId, since TWorkerQueue's handler signature
  only carries the TJob. Terminal results land in GPipelineResults so the
  poll-based GetPipelineStatus can report the final TDeepFramesJob even after
  the OnComplete callback has fired. Both maps are guarded by GPipelineLock. }

type
  TPipelineCallbacks = record
    Progress: TPipelineProgressEvent;
    Complete: TPipelineCompleteEvent;
    ForceRerun: Boolean;
  end;

var
  GPipelineQueue: TWorkerQueue = nil;
  GPipelineHandlerRegistered: Boolean = False;
  GPipelineCallbacks: TDictionary<string, TPipelineCallbacks> = nil;
  GPipelineResults: TDictionary<string, TPipelineStatus> = nil;
  GPipelineLock: TCriticalSection = nil;

procedure EnsurePipelineQueue;
const
  PIPELINE_JOB_TYPE = 'deepframes.pipeline';
begin
  if GPipelineLock = nil then
    GPipelineLock := TCriticalSection.Create;
  GPipelineLock.Enter;
  try
    if GPipelineQueue = nil then
    begin
      GPipelineQueue := TWorkerQueue.Create('deepframes-pipeline', 2);
      GPipelineCallbacks := TDictionary<string, TPipelineCallbacks>.Create;
      GPipelineResults := TDictionary<string, TPipelineStatus>.Create;
    end;
    if not GPipelineHandlerRegistered then
    begin
      // One global handler per JobType. Each pipeline instance is distinguished
      // by AJob.Id; its ForceRerun + caller callbacks are recovered from
      // GPipelineCallbacks. Runs on the worker thread — VCL callers must marshal.
      GPipelineQueue.RegisterHandler(PIPELINE_JOB_TYPE,
        procedure(const AJob: TJob)
        var
          Cb: TPipelineCallbacks;
          FinalJob: TDeepFramesJob;
          St: TPipelineStatus;
          HasCb: Boolean;
        begin
          HasCb := False;
          GPipelineLock.Enter;
          try
            HasCb := GPipelineCallbacks.TryGetValue(AJob.Id, Cb);
          finally GPipelineLock.Leave; end;
          if not HasCb then
            Exit; // orphaned job (process restart lost the in-memory callback map)
          FinalJob := TDeepFramesAppService.RunFullPipelineSync(Cb.ForceRerun, Cb.Progress);
          St.JobId := AJob.Id;
          St.Status := FinalJob.Status;
          St.IsTerminal := True;
          St.FinalJob := FinalJob;
          St.CurrentPhase := 'P6-done';
          GPipelineLock.Enter;
          try
            GPipelineResults.AddOrSetValue(AJob.Id, St);
            GPipelineCallbacks.Remove(AJob.Id);
          finally GPipelineLock.Leave; end;
          if Assigned(Cb.Complete) then
            Cb.Complete(FinalJob);
        end);
      GPipelineHandlerRegistered := True;
    end;
    if not GPipelineQueue.IsShuttingDown then
      GPipelineQueue.Start;
  finally GPipelineLock.Leave; end;
end;

class function TDeepFramesAppService.RunFullPipeline(const ForceRerun: Boolean): TDeepFramesJob;
begin
  // Synchronous wrapper retained for callers that still want blocking behavior
  // (e.g. tests, legacy entry points). DBA-4 async callers use RunFullPipelineAsync.
  Result := RunFullPipelineSync(ForceRerun, nil);
end;

class function TDeepFramesAppService.RunFullPipelineAsync(
  const ForceRerun: Boolean;
  const AOnProgress: TPipelineProgressEvent;
  const AOnComplete: TPipelineCompleteEvent): string;
const
  PIPELINE_JOB_TYPE = 'deepframes.pipeline';
var
  Job: TJob;
  Cb: TPipelineCallbacks;
begin
  EnsurePipelineQueue;
  Job := GPipelineQueue.CreateJob(PIPELINE_JOB_TYPE);
  Cb.Progress := AOnProgress;
  Cb.Complete := AOnComplete;
  Cb.ForceRerun := ForceRerun;
  GPipelineLock.Enter;
  try
    GPipelineCallbacks.AddOrSetValue(Job.Id, Cb);
  finally GPipelineLock.Leave; end;
  GPipelineQueue.Enqueue(Job);
  Result := Job.Id;
end;

class function TDeepFramesAppService.GetPipelineStatus(
  const APipelineJobId: string): TPipelineStatus;
var
  Job: TJob;
  St: TPipelineStatus;
  Found: Boolean;
begin
  Result := Default(TPipelineStatus);
  Result.JobId := APipelineJobId;
  GPipelineLock.Enter;
  try
    Found := GPipelineResults.TryGetValue(APipelineJobId, St);
  finally GPipelineLock.Leave; end;
  if Found then
  begin
    Result := St;
    Exit;
  end;
  // Still running — reflect the live TWorkerQueue job state. FinalJob is empty
  // until terminal; callers poll until IsTerminal.
  if GPipelineQueue <> nil then
  begin
    Job := GPipelineQueue.GetJob(APipelineJobId);
    if Job <> nil then
    begin
      case Job.Status of
        jsPending:   Result.Status := 'pending';
        jsRunning:   Result.Status := 'running';
        jsCompleted: Result.Status := 'completed';
        jsFailed:   Result.Status := 'failed';
        jsCancelled: Result.Status := 'cancelled';
      else
        Result.Status := 'unknown';
      end;
      Result.IsTerminal := (Job.Status = jsCompleted) or (Job.Status = jsFailed) or
                           (Job.Status = jsCancelled);
    end;
  end;
end;

class function TDeepFramesAppService.RunFullPipelineSync(const ForceRerun: Boolean;
  const AOnProgress: TPipelineProgressEvent): TDeepFramesJob;
  procedure Mark(const S: string);
  begin
    // Phase progress must use the standard logger because this service also
    // runs inside the VCL GUI process, where bare WriteLn can raise EInOutError.
    // The CLI pipeline keeps its own explicit TextFile log in DeepFrames.dpr.
    Logger.Info('[phase] ' + S, 'DeepFrames.Pipeline');
    OutputDebugString(PChar('[DeepFrames] ' + S));
  end;
  procedure Notify(const APhase: string; const AJob: TDeepFramesJob);
  begin
    // DBA-4: forward per-phase progress to the async caller. Runs on the
    // worker thread — AOnProgress must marshal to the UI thread itself.
    if Assigned(AOnProgress) then
      AOnProgress(APhase, AJob);
  end;
begin
  // Force-rerun: purge every existing job for the current project (cascades to
  // job_step via FK) so each phase's FindJobByLogicalKey finds nothing and
  // creates a fresh job, breaking the idempotent short-circuit that otherwise
  // returns the stale completed job without running any real step.
  if ForceRerun then
  begin
    Mark('P0-force-rerun: purging old jobs');
    var PurgeRepo := TDeepFramesRepository.Create;
    try
      var Projs := PurgeRepo.ListProjects;
      if Length(Projs) > 0 then
      begin
        var AllJobs := PurgeRepo.ListJobs;
        for var J in AllJobs do
          if SameText(J.ProjectId, Projs[0].ProjectId) then
            PurgeRepo.DeleteJob(J.JobId);
      end;
      // JobQueue rows are never deleted by Enqueue/Dequeue (status-only), so a
      // prior run's row with the same (queue_name, logical_key) would block
      // Enqueue's ON CONFLICT DO NOTHING and leave Dequeue without a pending row.
      PurgeRepo.PurgeDeepFramesJobQueue;
      // audio_manifest rows also survive DeleteJob; without this, the next
      // run reuses a stale manifest whose TimestampsAssetId dangles at a
      // purged asset → empty .srt (no cues to burn).
      if Length(Projs) > 0 then
        PurgeRepo.PurgeAudioManifestsByProject(Projs[0].ProjectId);
    finally PurgeRepo.Free; end;
  end;

  // Phase 1 — preprocess (produces the source document the document chain
  // resolves via ListSourceDocuments[0]).
  Mark('P1-preprocess');
  Result := RunPreprocess;
  Notify('P1-preprocess', Result);
  if not IsPhaseComplete(Result.Status) then Exit;

  // Phase 2 — document chain (produces variant_document + shot_document).
  Mark('P2-docchain');
  Result := RunDocumentChain;
  Notify('P2-docchain', Result);
  if not IsPhaseComplete(Result.Status) then Exit;

  // Phase 3 — agent chain (consumes shot_document).
  Mark('P3-agentchain');
  Result := RunAgentChain;
  Notify('P3-agentchain', Result);
  if not IsPhaseComplete(Result.Status) then Exit;

  // Phase 4 — audio chain (consumes shot_document, produces audio_manifest).
  Mark('P4-audiochain');
  Result := RunAudioChain;
  Notify('P4-audiochain', Result);
  if not IsPhaseComplete(Result.Status) then Exit;

  // Phase 5 — video chain (consumes shot_document + audio_manifest, produces
  // video_IR; burns subtitles via -vf subtitles=).
  Mark('P5-videochain');
  Result := RunVideoChain;
  Notify('P5-videochain', Result);
  if not IsPhaseComplete(Result.Status) then Exit;

  // Phase 6 — package chain (consumes variant_document + audio_manifest +
  // video_IR; assembles the deliverable).
  Mark('P6-packagechain');
  Result := RunPackageChain;
  Notify('P6-packagechain', Result);
  Mark('P6-done');
end;

class function TDeepFramesAppService.ListCandidatePackages(
  const AProjectId: string): TArray<TCandidatePackage>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListCandidatePackages(AProjectId);
  finally
    Repo.Free;
  end;
end;

// Phase 7: Extension capabilities

class function TDeepFramesAppService.RunExtensionChain: TDeepFramesJob;
begin
  Result := TExtensionChainWorkflow.RunExtensionChain;
end;

class function TDeepFramesAppService.ListBgmLibraries: TArray<TBgmLibrary>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListBgmLibraries;
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListBgmTracks(
  const ALibraryId: string): TArray<TBgmTrack>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListBgmTracks(ALibraryId);
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListContentTypeAdapters: TArray<TContentTypeAdapter>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListContentTypeAdapters;
  finally
    Repo.Free;
  end;
end;

class function TDeepFramesAppService.ListReadinessReports(
  const AAdapterId: string): TArray<TReadinessReport>;
var
  Repo: TDeepFramesRepository;
begin
  Repo := TDeepFramesRepository.Create;
  try
    Result := Repo.ListReadinessReports(AAdapterId);
  finally
    Repo.Free;
  end;
end;

end.
