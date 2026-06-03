unit DeepFrames.App.Services;

interface

uses
  DeepFrames.Domain.Types;

type
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

    /// <summary>Return candidate packages for a given project.</summary>
    class function ListCandidatePackages(const AProjectId: string): TArray<TCandidatePackage>; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DeepBase.DB.Migrations,
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
    Repo.InsertProject(Result);
    Repo.InsertContentUnit(UnitInfo);
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
    // Find audio manifest for the shot
    if (Length(Shots) > 0) and
       Repo.FindAudioManifestByShot(Shots[0].DocumentId, Manifests[0]) then
      AudioManifestId := Manifests[0].ManifestId
    else
    begin
      Manifests := Repo.ListAudioManifests(Units[0].ContentUnitId);
      if Length(Manifests) > 0 then
        AudioManifestId := Manifests[0].ManifestId
      else
        AudioManifestId := '';
    end;
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

end.
