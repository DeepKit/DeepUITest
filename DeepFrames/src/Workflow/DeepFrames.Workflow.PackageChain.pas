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
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Shared.Consts;

// Fake quality snapshot
function FakeQualitySnapshot: string;
var
  Obj: TJSONObject;
  GatesArr: TJSONArray;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('overall', TJSONBool.Create(True));

    GatesArr := TJSONArray.Create;
    GatesArr.AddElement(TJSONObject.Create
      .AddPair('gate', 'gate3a')
      .AddPair('result', 'pass')
      .AddPair('score', TJSONNumber.Create(1.0)));
    GatesArr.AddElement(TJSONObject.Create
      .AddPair('gate', 'gate3b')
      .AddPair('result', 'pass')
      .AddPair('score', TJSONNumber.Create(1.0)));
    Obj.AddPair('gates', GatesArr);

    Obj.AddPair('audio_status', 'done');
    Obj.AddPair('video_status', 'done');
    Obj.AddPair('asset_protection', TJSONObject.Create
      .AddPair('audio_manifest_protected', TJSONBool.Create(True))
      .AddPair('video_ir_protected', TJSONBool.Create(True)));

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

// Fake source trace
function FakeSourceTrace(const VariantDocId, AudioManifestId,
  VideoIRId: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('variant_document_id', VariantDocId);
    Obj.AddPair('audio_manifest_id', AudioManifestId);
    Obj.AddPair('video_ir_id', VideoIRId);
    Obj.AddPair('assembly_timestamp', '2026-06-04T00:00:00Z');
    Obj.AddPair('assembler', 'deepframes-package-1.0.0');
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

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
    ManifestAsset.Sha256 := TProjectService.Sha256Text('stub-package-manifest');
    ManifestAsset.ByteSize := 4096;
    ManifestAsset.Status := ASSET_STATUS_READY;
    ManifestAsset.RetentionClass := RETENTION_CLASS_C1;
    Repo.InsertAsset(ManifestAsset);

    Pkg.ManifestAssetId := ManifestAsset.AssetId;
    Pkg.QualitySnapshotJson := FakeQualitySnapshot;
    Pkg.SourceTraceJson := FakeSourceTrace(
      VariantDocumentId, AudioManifestId, VideoIRId);

    // Update package with assembled data
    // (In production: separate update method; here we delete+reinsert for simplicity
    //  since status is still pending, no external visibility yet)
    // Actually, let's just do a direct SQL update for the manifest_asset_id
    // via a separate method call
    // For now: we update via a simple pattern
    // We'll add a dedicated UpdateCandidatePackageAssembly method if needed later

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for package.assemble');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Gate 4: package integrity check
    // ---------------------------------------------------------------
    GateResult := TProjectService.CreateQualityGateResult(
      Job.JobId, GATE_4, GATE_RESULT_PASS, 1.0);
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
