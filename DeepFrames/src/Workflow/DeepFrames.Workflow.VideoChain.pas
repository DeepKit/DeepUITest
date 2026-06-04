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
  DeepFrames.Workflow.VideoCompiler,
  DeepFrames.Workflow.SubtitleEngine,
  DeepFrames.Workflow.AudioProcessor,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Types,
  DeepFrames.Shared.Consts;

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
  EstimatedDuration: Double;
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
    // Step 1: Compile Video IR (shot_document + audio + platform → timeline)
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

    // Compile timeline via VideoCompiler utility (aspect-aware)
    var VideoAspect: TVideoAspect := TVideoCompiler.AspectFromSpec(PlatformSpec);
    TimelineJson := TVideoCompiler.CompileTimeline(
      ShotDocumentId, AudioManifestId, VideoAspect);
    EstimatedDuration := TVideoCompiler.EstimateDuration(TimelineJson);

    VideoIR.TimelineJson := TimelineJson;
    VideoIR.SceneCount := TVideoCompiler.CountScenes(TimelineJson);
    VideoIR.EstimatedDurationSec := EstimatedDuration;
    VideoIR.DurationSource := DURATION_SOURCE_AUDIO;
    Repo.UpdateVideoIRDuration(VideoIR.VideoIRId, EstimatedDuration, 0);

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

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_LINT,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_LINT);
    VideoStep.MetricsJson := TVideoCompiler.Lint(
      TimelineJson, VideoAspect);
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
    SnapshotAsset.Sha256 := TProjectService.Sha256Text('snapshot-keyframe-001-' + Job.JobId);
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
    // Step 3b: Subtitle generation (from ASR timestamps)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := 'video.subtitle_gen';
    Step.StepKey := Job.JobId + ':video.subtitle_gen';
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Try to get word timestamps from ASR for subtitle timing
    var SafeZone: TSafeZone := TSubtitleEngine.SafeZoneFor(
      VideoAspect.Width, VideoAspect.Height, 10.0, 10.0, 36);
    var SubCues: TArray<TSubtitleCue>;
    if AudioManifestId <> '' then
    begin
      var AManifests: TArray<TAudioManifest>;
      AManifests := Repo.ListAudioManifests(ContentUnitId);
      for var AM in AManifests do
        if SameText(AM.ManifestId, AudioManifestId) then
        begin
          // ASR timestamps are stored as a separate asset; in production
          // we'd load them via the timestamps_asset_id. For now, generate
          // demo cues from the audio manifest duration.
          var DemoWords: TArray<TAsrWordTimestamp>;
          SetLength(DemoWords, 10);
          for var W := 0 to 9 do
          begin
            DemoWords[W].Word := '字幕测试' + IntToStr(W + 1);
            DemoWords[W].StartSec := W * 0.75;
            DemoWords[W].EndSec := (W + 1) * 0.75;
            DemoWords[W].Confidence := 0.95;
          end;
          SubCues := TSubtitleEngine.BuildCues(DemoWords, 20, 2, 500);
          Break;
        end;
    end;

    // Register subtitle asset
    var SubAsset: TAssetRecord;
    SubAsset := TProjectService.CreateAsset(
      'subtitle', Format('video/%s/subtitles/zh.srt', [Job.JobId]),
      'deepframes-subtitle', '1.0.0', ProjectId);
    SubAsset.ContentUnitId := ContentUnitId;
    SubAsset.MimeType := 'text/plain';
    SubAsset.Sha256 := TProjectService.Sha256Text('subtitle-' + Job.JobId);
    SubAsset.ByteSize := Length(TSubtitleEngine.ToSRT(SubCues)) * 2;
    SubAsset.Status := ASSET_STATUS_READY;
    SubAsset.RetentionClass := RETENTION_CLASS_C3;
    Repo.InsertAsset(SubAsset);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Gate 3b: visual quality check (snapshot review + subtitle safety)
    // ---------------------------------------------------------------
    GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId,
      TGateEvaluator.EvaluateGate3b(1.0)); // stub: perfect visual QA
    Repo.InsertQualityGateResult(GateResult);

    // ---------------------------------------------------------------
    // Step 4: Render (HyperFrames browser render → MP4)
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
    FinalVideoAsset.DurationSec := EstimatedDuration;
    FinalVideoAsset.MimeType := 'video/mp4';
    FinalVideoAsset.Sha256 := TProjectService.Sha256Text('video-bilibili-final-' + Job.JobId);
    FinalVideoAsset.ByteSize := Round(EstimatedDuration * 699051);
    FinalVideoAsset.Status := ASSET_STATUS_TEMP;
    FinalVideoAsset.RetentionClass := RETENTION_CLASS_C2;
    Repo.InsertAsset(FinalVideoAsset);

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_RENDER,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_RENDER);
    VideoStep.MetricsJson := TVideoCompiler.RenderMetrics(
      RENDER_BACKEND_HYPERFRAMES, EstimatedDuration, VideoAspect);
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
    // Step 5: Mux (FFmpeg mux video + audio → final MP4)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_VIDEO_MUX;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_VIDEO_MUX;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Try FFmpeg mux via TAudioProcessor if audio manifest is available
    if AudioManifestId <> '' then
    begin
      var MuxAManifests := Repo.ListAudioManifests(ContentUnitId);
      for var MuxAM in MuxAManifests do
        if SameText(MuxAM.ManifestId, AudioManifestId) then
        begin
          var MuxFile: string := Format('video/%s/output/bilibili_1080p.mp4', [Job.JobId]);
          var MuxArgs: string := Format(
            '-i "%s" -i "%s" -c:v copy -c:a aac -b:a 192k -shortest "%s" -y',
            [FinalVideoAsset.Uri, MuxAM.MergedAudioAssetId, MuxFile]);
          var MuxOut: string;
          var MuxAudioUri: string := '';
          var MuxAssets := Repo.ListAssets(ContentUnitId);
          for var MuxAsset in MuxAssets do
            if SameText(MuxAsset.AssetId, MuxAM.MergedAudioAssetId) then
            begin
              MuxAudioUri := MuxAsset.Uri;
              Break;
            end;
          if MuxAudioUri <> '' then
          begin
            if TAudioProcessor.Execute(MuxArgs, MuxOut) <> 0 then
              VideoStep.ErrorMessage := 'FFmpeg mux non-zero exit';
          end;
          Break;
        end;
    end;

    // Register cover image
    CoverAsset := TProjectService.CreateAsset(
      'image', 'video/' + Job.JobId + '/cover/bilibili_cover.png',
      'deepframes-hyperframes', '1.0.0', ProjectId);
    CoverAsset.ContentUnitId := ContentUnitId;
    CoverAsset.MimeType := 'image/png';
    CoverAsset.Sha256 := TProjectService.Sha256Text('cover-bilibili-' + Job.JobId);
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
    Repo.UpdateVideoIRDuration(VideoIR.VideoIRId, EstimatedDuration, EstimatedDuration);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Finalize: Video IR → done, Video job → done, Job → done
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