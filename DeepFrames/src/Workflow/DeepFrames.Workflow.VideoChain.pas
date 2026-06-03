unit DeepFrames.Workflow.VideoChain;

interface

uses
  DeepFrames.Domain.Types;

type
  TVideoChainWorkflow = class
  public
    class function BuildLogicalKey(const ProjectId, ContentUnitId,
      ShotDocumentId: string): string; static;
    class function RunChain(const ProjectId, ContentUnitId,
      ShotDocumentId, AudioManifestId: string): TDeepFramesJob; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Shared.Consts;

// Fake HyperFrames compile: generates stub Video IR timeline
function FakeVideoIRTimeline: string;
var
  Arr: TJSONArray;
  Scene: TJSONObject;
begin
  Arr := TJSONArray.Create;
  try
    Scene := TJSONObject.Create;
    Scene.AddPair('scene_id', 'scene_001');
    Scene.AddPair('template', 'narration');
    Scene.AddPair('duration_sec', TJSONNumber.Create(3.5));
    Scene.AddPair('layers', TJSONObject.Create
      .AddPair('background', TJSONObject.Create
        .AddPair('type', 'image')
        .AddPair('prompt', 'A calm study room with warm lighting'))
      .AddPair('subtitle', TJSONObject.Create
        .AddPair('text', 'First subtitle line')
        .AddPair('position', 'bottom_center')));
    Scene.AddPair('transitions', TJSONObject.Create
      .AddPair('in', 'fade')
      .AddPair('out', 'fade'));
    Arr.AddElement(Scene);

    Scene := TJSONObject.Create;
    Scene.AddPair('scene_id', 'scene_002');
    Scene.AddPair('template', 'narration');
    Scene.AddPair('duration_sec', TJSONNumber.Create(4.0));
    Scene.AddPair('layers', TJSONObject.Create
      .AddPair('background', TJSONObject.Create
        .AddPair('type', 'image')
        .AddPair('prompt', 'Mountain landscape at dawn'))
      .AddPair('subtitle', TJSONObject.Create
        .AddPair('text', 'Second subtitle line')
        .AddPair('position', 'bottom_center')));
    Scene.AddPair('transitions', TJSONObject.Create
      .AddPair('in', 'crossfade')
      .AddPair('out', 'fade'));
    Arr.AddElement(Scene);

    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

// Fake lint result
function FakeLintResult: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('passed', TJSONBool.Create(True));
    Obj.AddPair('warnings', TJSONArray.Create);
    Obj.AddPair('errors', TJSONArray.Create);
    Obj.AddPair('checked_layers', TJSONNumber.Create(4));
    Obj.AddPair('safe_zone_violations', TJSONNumber.Create(0));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

// Fake render metrics
function FakeRenderMetrics: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('render_backend', 'hyperframes');
    Obj.AddPair('frames_rendered', TJSONNumber.Create(225));  // 7.5s * 30fps
    Obj.AddPair('render_time_ms', TJSONNumber.Create(3200));
    Obj.AddPair('output_width', TJSONNumber.Create(1920));
    Obj.AddPair('output_height', TJSONNumber.Create(1080));
    Obj.AddPair('output_fps', TJSONNumber.Create(30));
    Obj.AddPair('output_codec', 'h264');
    Obj.AddPair('file_size_bytes', TJSONNumber.Create(5242880));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TVideoChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, ShotDocumentId: string): string;
begin
  Result := JOB_TYPE_VIDEO + ':' + ProjectId + ':' + ContentUnitId +
    ':' + ShotDocumentId;
end;

class function TVideoChainWorkflow.RunChain(const ProjectId, ContentUnitId,
  ShotDocumentId, AudioManifestId: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  PlatformSpec: TPlatformSpec;
  VideoIR: TVideoIR;
  VideoJob: TVideoJob;
  VideoStep: TVideoStep;
  VideoAsset: TVideoAsset;
  GateResult: TQualityGateResult;
  SnapshotAsset: TAssetRecord;
  FinalVideoAsset: TAssetRecord;
  CoverAsset: TAssetRecord;
  LogicalKey: string;
  TimelineJson: string;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency: if job already exists, return it
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

    // Resolve bilibili platform spec
    if not Repo.FindPlatformSpecByPlatform(PLATFORM_BILIBILI, PlatformSpec) then
      raise Exception.Create('No bilibili platform spec found. Run migrations first.');

    // Create video job
    Job.JobId := NewUuidString;
    Job.ProjectId := ProjectId;
    Job.ContentUnitId := ContentUnitId;
    Job.JobType := JOB_TYPE_VIDEO;
    Job.LogicalKey := LogicalKey;
    Job.JobQueueTaskId := '';
    Job.Status := STATUS_PENDING;
    Repo.InsertJob(Job);

    // Create Video IR record
    VideoIR := TProjectService.CreateVideoIR(
      ProjectId, ContentUnitId, ShotDocumentId, AudioManifestId,
      PlatformSpec.PlatformSpecId, RENDER_BACKEND_HYPERFRAMES);
    VideoIR.Status := STATUS_PENDING;
    Repo.InsertVideoIR(VideoIR);

    // Create video pipeline job
    VideoJob := TProjectService.CreateVideoJob(
      Job.JobId, VideoIR.VideoIRId, PlatformSpec.PlatformSpecId,
      RENDER_BACKEND_HYPERFRAMES, VIDEO_MODE_FINAL_WITH_AUDIO);
    Repo.InsertVideoJob(VideoJob);

    // ---------------------------------------------------------------
    // Step 1: Compile Video IR (shot_document + audio + platform -> timeline)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_VIDEO_COMPILE;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_VIDEO_COMPILE;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for compile_ir');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateVideoIRStatus(VideoIR.VideoIRId, STATUS_RUNNING);

    // Fake compile: generate timeline JSON
    TimelineJson := FakeVideoIRTimeline;
    VideoIR.TimelineJson := TimelineJson;
    VideoIR.SceneCount := 2;
    VideoIR.EstimatedDurationSec := 7.5;
    VideoIR.DurationSource := DURATION_SOURCE_AUDIO;
    // Update IR with computed values
    Repo.UpdateVideoIRDuration(VideoIR.VideoIRId, 7.5, 0);

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_COMPILE,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_COMPILE);
    VideoStep.Status := STATUS_RUNNING;
    Repo.InsertVideoStep(VideoStep);
    Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_DONE);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for compile_ir');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 2: Lint (validate Video IR composition)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_VIDEO_LINT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_VIDEO_LINT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Fake lint: always passes
    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_LINT,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_LINT);
    VideoStep.MetricsJson := FakeLintResult;
    VideoStep.Status := STATUS_RUNNING;
    Repo.InsertVideoStep(VideoStep);
    Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_DONE);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 3: Snapshot (generate keyframe thumbnails for Gate 3b)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_VIDEO_SNAPSHOT;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_VIDEO_SNAPSHOT;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Register snapshot asset
    SnapshotAsset := TProjectService.CreateAsset(
      'image', 'video/' + Job.JobId + '/snapshots/keyframe_001.png',
      'deepframes-hyperframes', '1.0.0', ProjectId);
    SnapshotAsset.ContentUnitId := ContentUnitId;
    SnapshotAsset.MimeType := 'image/png';
    SnapshotAsset.Sha256 := TProjectService.Sha256Text('stub-snapshot-keyframe-001');
    SnapshotAsset.ByteSize := 512000;
    SnapshotAsset.Status := ASSET_STATUS_READY;
    SnapshotAsset.RetentionClass := RETENTION_CLASS_C3;
    Repo.InsertAsset(SnapshotAsset);

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_SNAPSHOT,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_SNAPSHOT);
    VideoStep.AssetId := SnapshotAsset.AssetId;
    VideoStep.Status := STATUS_RUNNING;
    Repo.InsertVideoStep(VideoStep);

    // Register video asset link
    VideoAsset := TProjectService.CreateVideoAsset(
      VideoJob.VideoJobId, VideoStep.VideoStepId,
      SnapshotAsset.AssetId, ASSET_CATEGORY_SNAPSHOT, 0);
    Repo.InsertVideoAsset(VideoAsset);

    Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_DONE);
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Gate 3b: visual quality check (snapshot review)
    // ---------------------------------------------------------------
    GateResult := TProjectService.CreateQualityGateResult(
      Job.JobId, GATE_3B, GATE_RESULT_PASS, 1.0);
    Repo.InsertQualityGateResult(GateResult);

    // ---------------------------------------------------------------
    // Step 4: Render (HyperFrames browser render -> MP4)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_VIDEO_RENDER;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_VIDEO_RENDER;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateVideoJobStatus(VideoJob.VideoJobId, STATUS_RUNNING);

    // Register final video asset
    FinalVideoAsset := TProjectService.CreateAsset(
      'video', 'video/' + Job.JobId + '/output/bilibili_1920x1080.mp4',
      'deepframes-hyperframes', '1.0.0', ProjectId);
    FinalVideoAsset.ContentUnitId := ContentUnitId;
    FinalVideoAsset.DurationSec := 7.5;
    FinalVideoAsset.MimeType := 'video/mp4';
    FinalVideoAsset.Sha256 := TProjectService.Sha256Text('stub-video-bilibili-final');
    FinalVideoAsset.ByteSize := 5242880;
    FinalVideoAsset.Status := ASSET_STATUS_TEMP;
    FinalVideoAsset.RetentionClass := RETENTION_CLASS_C2;
    Repo.InsertAsset(FinalVideoAsset);

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_RENDER,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_RENDER);
    VideoStep.MetricsJson := FakeRenderMetrics;
    VideoStep.AssetId := FinalVideoAsset.AssetId;
    VideoStep.Status := STATUS_RUNNING;
    Repo.InsertVideoStep(VideoStep);

    // Register video asset link
    VideoAsset := TProjectService.CreateVideoAsset(
      VideoJob.VideoJobId, VideoStep.VideoStepId,
      FinalVideoAsset.AssetId, ASSET_CATEGORY_FINAL, 0);
    Repo.InsertVideoAsset(VideoAsset);

    // Promote video to ready after render
    if not TProjectService.IsAssetStatusTransitionValid(ASSET_STATUS_TEMP, ASSET_STATUS_READY) then
      raise Exception.Create('Invalid asset status transition: temp -> ready');
    Repo.UpdateAssetStatus(FinalVideoAsset.AssetId, ASSET_STATUS_READY);

    Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_DONE);
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 5: Mux (fake FFmpeg mux video + audio)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_VIDEO_MUX;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_VIDEO_MUX;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Register cover image
    CoverAsset := TProjectService.CreateAsset(
      'image', 'video/' + Job.JobId + '/cover/bilibili_cover.png',
      'deepframes-hyperframes', '1.0.0', ProjectId);
    CoverAsset.ContentUnitId := ContentUnitId;
    CoverAsset.MimeType := 'image/png';
    CoverAsset.Sha256 := TProjectService.Sha256Text('stub-cover-bilibili');
    CoverAsset.ByteSize := 256000;
    CoverAsset.Status := ASSET_STATUS_READY;
    CoverAsset.RetentionClass := RETENTION_CLASS_C2;
    Repo.InsertAsset(CoverAsset);

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_MUX,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_MUX);
    VideoStep.Status := STATUS_RUNNING;
    Repo.InsertVideoStep(VideoStep);

    // Register cover video asset link
    VideoAsset := TProjectService.CreateVideoAsset(
      VideoJob.VideoJobId, VideoStep.VideoStepId,
      CoverAsset.AssetId, ASSET_CATEGORY_COVER, 0);
    Repo.InsertVideoAsset(VideoAsset);

    Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_DONE);

    // Update actual duration after render
    Repo.UpdateVideoIRDuration(VideoIR.VideoIRId, 7.5, 7.5);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Finalize: Video IR -> done, Video job -> done, Job -> done
    // ---------------------------------------------------------------
    Repo.UpdateVideoIRStatus(VideoIR.VideoIRId, STATUS_DONE);
    Repo.UpdateVideoJobStatus(VideoJob.VideoJobId, STATUS_DONE);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for video job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_RUNNING);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for video job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_DONE);

    Job.Status := STATUS_DONE;
    Result := Job;
  finally
    Repo.Free;
  end;
end;

end.
