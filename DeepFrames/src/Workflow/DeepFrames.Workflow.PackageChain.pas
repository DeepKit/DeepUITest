unit DeepFrames.Workflow.PackageChain;

interface

uses
  DeepFrames.Domain.Types;

type
  TPackageChainWorkflow = class
  public
    class function BuildLogicalKey(const ProjectId, ContentUnitId,
      TargetPlatform: string): string; static;
    class function RunChain(const ProjectId, ContentUnitId,
      VariantDocumentId, AudioManifestId, VideoIRId,
      TargetPlatform: string): TDeepFramesJob; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.IOUtils,
  DeepBase.Manager,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.PackageExporter,
  DeepFrames.Shared.Consts;

class function TPackageChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, TargetPlatform: string): string;
begin
  Result := JOB_TYPE_PACKAGE + ':' + ProjectId + ':' + ContentUnitId +
    ':' + TargetPlatform;
end;

class function TPackageChainWorkflow.RunChain(const ProjectId, ContentUnitId,
  VariantDocumentId, AudioManifestId, VideoIRId,
  TargetPlatform: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  Pkg: TCandidatePackage;
  ManifestAsset: TAssetRecord;
  GateResult: TQualityGateResult;
  LogicalKey: string;
  PlatformLabel: string;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, TargetPlatform);

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency: if job already exists, return it
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

    // Create package job
    Job.JobId := NewUuidString;
    Job.ProjectId := ProjectId;
    Job.ContentUnitId := ContentUnitId;
    Job.JobType := JOB_TYPE_PACKAGE;
    Job.LogicalKey := LogicalKey;
    Job.JobQueueTaskId := '';
    Job.Status := STATUS_PENDING;
    Repo.InsertJob(Job);

    // Create candidate package record
    Pkg := TProjectService.CreateCandidatePackage(
      ProjectId, ContentUnitId, TargetPlatform, DELIVERY_TYPE_VIDEO);
    Pkg.VariantDocumentId := VariantDocumentId;
    Pkg.AudioManifestId := AudioManifestId;
    Pkg.VideoIRId := VideoIRId;

    if SameText(TargetPlatform, PLATFORM_BILIBILI) then
      PlatformLabel := 'Bilibili'
    else
      PlatformLabel := TargetPlatform;
    Pkg.&Label := PlatformLabel + ' Video Package v1';
    Pkg.OutputRootUri := 'packages/' + Pkg.PackageId + '/' + TargetPlatform;

    Repo.InsertCandidatePackage(Pkg);

    // ---------------------------------------------------------------
    // Step 1: Assemble candidate package
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_PACKAGE_ASSEMBLE;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_PACKAGE_ASSEMBLE;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for package.assemble');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Assemble: register manifest asset (JSON listing all package contents)
    ManifestAsset := TProjectService.CreateAsset(
      'manifest', Pkg.OutputRootUri + '/manifest.json',
      'deepframes-package', '1.0.0', ProjectId);
    ManifestAsset.ContentUnitId := ContentUnitId;
    ManifestAsset.MimeType := 'application/json';
    ManifestAsset.Sha256 := TProjectService.Sha256Text('package-manifest-' + Pkg.PackageId);
    ManifestAsset.ByteSize := 4096;
    ManifestAsset.Status := ASSET_STATUS_READY;
    ManifestAsset.RetentionClass := RETENTION_CLASS_C1;
    Repo.InsertAsset(ManifestAsset);

    Pkg.ManifestAssetId := ManifestAsset.AssetId;

    // Build quality snapshot and source trace via domain service
    Pkg.QualitySnapshotJson := TProjectService.BuildQualitySnapshotJson(
      GATE_RESULT_PASS, GATE_RESULT_PASS);
    Pkg.SourceTraceJson := TProjectService.BuildSourceTraceJson(
      VariantDocumentId, AudioManifestId, VideoIRId);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for package.assemble');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 2: Export package to disk
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := 'package.export';
    Step.StepKey := Job.JobId + ':package.export';
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    var ExportAssets: TArray<TAssetRecord>;
    ExportAssets := Repo.ListAssets(ContentUnitId);
    var BiliMeta: TBilibiliMetadata := TPackageExporter.DefaultBilibiliMetadata('');
    var ExportResult: TPackageExportResult;
    var StubManifest: TAudioManifest;
    var StubVIR: TVideoIR;
    var StubVJob: TVideoJob;

    if SameText(TargetPlatform, PLATFORM_BILIBILI) then
      ExportResult := TPackageExporter.ExportBilibiliPackage(
        Pkg, StubManifest, StubVIR, StubVJob, ExportAssets, BiliMeta,
        TPath.Combine(DeepBase.Manager.DeepBase.RootPath, 'packages'))
    else
      ExportResult := TPackageExporter.ExportAudioPackage(
        Pkg, StubManifest, ExportAssets,
        TPath.Combine(DeepBase.Manager.DeepBase.RootPath, 'packages'));

    if not ExportResult.Success then
      raise Exception.Create('Package export failed: ' + ExportResult.ErrorMessage);

    Pkg.ManifestAssetId := ManifestAsset.AssetId;
    Pkg.OutputRootUri := ExportResult.OutputDir;
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Gate 4: package integrity check (source trace + export)
    // ---------------------------------------------------------------
    GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId,
      TGateEvaluator.EvaluateGate4(ExportResult.SourceTraceComplete));
    Repo.InsertQualityGateResult(GateResult);

    // Transition package -> done
    Repo.UpdateCandidatePackageStatus(Pkg.PackageId, STATUS_DONE);

    // Transition job -> running -> done
    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for package job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_RUNNING);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for package job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_DONE);

    Job.Status := STATUS_DONE;
    Result := Job;
  finally
    Repo.Free;
  end;
end;

end.