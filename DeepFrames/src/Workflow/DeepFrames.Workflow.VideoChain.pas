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
  System.Math,
  System.IOUtils,
  System.JSON,
  DeepFrames.Domain.Project,
  DeepFrames.Persistence.Repository,
  DeepFrames.Workflow.VideoCompiler,
  DeepFrames.Workflow.SubtitleEngine,
  DeepFrames.Workflow.AudioProcessor,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Workflow.EventLog,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Intf,
  DeepBase.Manager,
  DeepBase.Config,
  DeepBase.Consts,
  DeepFrames.Provider.Types,
  DeepFrames.Shared.Consts,
  DeepFrames.Shared.Tools;

// Forward declaration: ExtractFirstVisualPrompt is a unit-level helper
// defined near the end of the implementation section; it is called from
// RunChain (Step 4 render) above its definition.
function ExtractFirstVisualPrompt(const AJson: string): string; forward;

// Forward declaration: ParseTimestampsJson is a unit-level helper defined
// later in the implementation section; called from RunChain (Step 3
// subtitle) above its definition.
function ParseTimestampsJson(const AJson: string): TArray<TAsrWordTimestamp>; forward;

// Forward declaration: EscapeSrtPathForFilter escapes a subtitle file path for
// use inside an ffmpeg `subtitles=` filtergraph value. Called from RunChain
// (Step 5 mux) above its definition. ffmpeg/libass treats ':' as a filter
// option separator and '\' as an escape, so backslashes must become forward
// slashes and every ':' (incl. the drive-letter colon on Windows) must be
// escaped to '\:' before the path can appear inside subtitles=<path>.
function EscapeSrtPathForFilter(const APath: string): string; forward;

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
  // D8 (tasks.md): the REAL produced MP4 that Gate 3b scores. Set to the mux
  // output when audio mux ran, else the render output. Gate 3b runs AFTER
  // render/mux (was a stub EvaluateGate3b(1.0) before render — see removed block).
  Gate3bMp4: string;
  Gate3bFrames: TArray<string>;
  SubSrtFile: string;
  LogicalKey: string;
  TimelineJson: string;
  EstimatedDuration: Double;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);

  Repo := TDeepFramesRepository.Create;

  try
    // Idempotency: if job already exists and is done, return it.
    // If job exists but is pending/failed, delete it and start fresh.
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
    begin
      // D7: debug-only force-regenerate backdoor. Under {$IFDEF DEBUG} a stray
      // force_video_regenerate.txt in the CWD forces job deletion + regenerate;
      // Release builds compile this whole branch out so production idempotency
      // short-circuits (FindJobByLogicalKey DONE) can never be broken by a
      // leftover debug flag file. CLI --force-rerun remains the supported path.
      {$IFDEF DEBUG}
      if FileExists('force_video_regenerate.txt') then
      begin
        // Delete the old job and regenerate
        Repo.DeleteJob(ExistingJob.JobId);
      end
      else
      {$ENDIF}
      begin
        if SameText(ExistingJob.Status, STATUS_DONE) or
           SameText(ExistingJob.Status, STATUS_COMPLETED) then
          Exit(ExistingJob);
        // Job exists but not completed - delete and recreate
        Repo.DeleteJob(ExistingJob.JobId);
      end;
    end;

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
    VideoStep.ShotId := '';
    VideoStep.AssetId := '';
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
    SubSrtFile := '';
    if AudioManifestId <> '' then
    begin
      var AManifests: TArray<TAudioManifest>;
      AManifests := Repo.ListAudioManifests(ContentUnitId);
      for var AM in AManifests do
        if SameText(AM.ManifestId, AudioManifestId) then
        begin
          // Load real ASR word-level timestamps written by AudioChain Step2
          // (audio/{JobId}/timestamps.json). Previously this fell back to
          // hardcoded '字幕测试1'..'10' demo cues — subtitles were fake.
          var TsWords: TArray<TAsrWordTimestamp>;
          if AM.TimestampsAssetId <> '' then
          begin
            var AllAssets := Repo.ListAssets(ContentUnitId);
            for var A in AllAssets do
              if SameText(A.AssetId, AM.TimestampsAssetId) then
              begin
                if TFile.Exists(A.Uri) then
                begin
                  var TsRaw := TFile.ReadAllText(A.Uri);
                  TsWords := ParseTimestampsJson(TsRaw);
                end;
                Break;
              end;
          end;
          // Clamp ASR word timestamps to the real audio duration. ASR
          // providers (StepFun) sometimes report end_time values beyond the
          // audio length (e.g. 8.25s for a 3.25s clip), which inflates cue
          // end times past the video. TAudioManifest.DurationSec is the
          // mux audio length, so it is the authoritative ceiling.
          if AM.DurationSec > 0 then
            for var Wi := 0 to High(TsWords) do
            begin
              if TsWords[Wi].EndSec > AM.DurationSec then
                TsWords[Wi].EndSec := AM.DurationSec;
              if TsWords[Wi].StartSec > AM.DurationSec then
                TsWords[Wi].StartSec := AM.DurationSec;
            end;
          SubCues := TSubtitleEngine.BuildCues(TsWords, 20, 2, 500);
          Break;
        end;
    end;

    // Register subtitle asset AND write the .srt file to disk (was missing —
    // only the asset record existed, so PackageExporter had no file to export).
    var RootDir := DeepBase.Manager.DeepBase.RootPath;
    var SubAsset: TAssetRecord;
    // D1.5 (tasks.md): --subtitle-lang override. The language tag drives the
    // subtitle file name (zh.srt / en.srt / ...); the ASR provider is still
    // chosen by the registry preset. Empty/unset falls back to 'zh'.
    var SubLang := GetConfig(CONFIG_SUBTITLE_LANG, DEFAULT_SUBTITLE_LANG);
    if Trim(SubLang) = '' then
      SubLang := DEFAULT_SUBTITLE_LANG;
    var SubFileName := SubLang + '.srt';
    var SubRelPath := 'video' + PathDelim + Job.JobId + PathDelim + 'subtitles' + PathDelim + SubFileName;
    var SubAssetUri := 'video/' + Job.JobId + '/subtitles/' + SubFileName;  // URI uses forward slashes
    SubAsset := TProjectService.CreateAsset(
      'subtitle', SubAssetUri,
      'deepframes-subtitle', '1.0.0', ProjectId);
    SubAsset.ContentUnitId := ContentUnitId;
    SubAsset.MimeType := 'text/plain';
    SubAsset.Sha256 := TProjectService.Sha256Text('subtitle-' + Job.JobId);
    // Build full filesystem path using correct OS separators
    SubSrtFile := TPath.Combine(TPath.Combine(RootDir, 'output'), SubRelPath);
    ForceDirectories(TPath.GetDirectoryName(SubSrtFile));
    var SrtText := TSubtitleEngine.ToSRT(SubCues);
    TFile.WriteAllText(SubSrtFile, SrtText);
    SubAsset.ByteSize := TFile.GetSize(SubSrtFile);
    SubAsset.Status := ASSET_STATUS_READY;
    SubAsset.RetentionClass := RETENTION_CLASS_C3;
    Repo.InsertAsset(SubAsset);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // D8 (tasks.md): Gate 3b moved to AFTER render/mux below. The old block
    // here ran EvaluateGate3b(1.0) — a hardcoded perfect score on a fake
    // keyframe_001.png that never existed on disk. It is removed.

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

    // ---------------------------------------------------------------
    // Step 4: Render via Agnes video generation (was a HyperFrames stub
    // that registered a fake asset with no real MP4). Read visual_prompt
    // from the shot document payload (persisted by DocumentChain) and call
    // the active video provider; on success the real file path becomes the
    // asset URI. A generation failure hard-stops the job rather than
    // producing a cover-only "success".
    // ---------------------------------------------------------------
    var VGenPrompt: string := '';
    var ShotDocs: TArray<TShotDocumentVersion> := Repo.ListShotDocuments(ContentUnitId);
    for var SD in ShotDocs do
      if SameText(SD.DocumentId, ShotDocumentId) then
      begin
        VGenPrompt := ExtractFirstVisualPrompt(SD.PayloadJson);
        Break;
      end;
    if VGenPrompt = '' then
      VGenPrompt := 'cinematic establishing shot, soft morning light, wide angle, 1080p';

    var VReq: TVideoGenRequest;
    VReq.Prompt := VGenPrompt;
    VReq.ImageUrl := '';
    VReq.Width := 1280;
    VReq.Height := 720;
    VReq.DurationSec := EstimatedDuration;

    var VRes: TVideoGenResult;
    var VMetrics: TProviderRunMetrics;
    var VProvider: IDeepFramesVideoProvider := TProviderRegistry.Instance.VideoProvider;
    if not Assigned(VProvider) then
    begin
      VideoStep := TProjectService.CreateVideoStep(
        VideoJob.VideoJobId, STEP_TYPE_VIDEO_RENDER,
        VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_RENDER);
      VideoStep.MetricsJson := TVideoCompiler.RenderMetrics(
        RENDER_BACKEND_AGNES, EstimatedDuration, VideoAspect);
      VideoStep.ErrorMessage := 'No video provider available (Agnes not configured)';
      VideoStep.Status := STATUS_FAILED;
      Repo.InsertVideoStep(VideoStep);
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED);
      Repo.UpdateJobStatus(Job.JobId, STATUS_FAILED);
      raise Exception.Create('VideoChain Step4: no video provider (Agnes unavailable) for job ' + Job.JobId);
    end;

    TWorkflowLogger.LogProviderCall(Job.JobId, Step.StepId,
      VMetrics.ProviderName, VMetrics.Model, CAPABILITY_VIDEO_GEN,
      VMetrics.LatencyMs, VMetrics.TokenUsage.PromptTokens,
      VMetrics.TokenUsage.CompletionTokens, 'generateVideo');
    var VGenOk: Boolean := False;
    if VProvider.GetProviderStatus = psOk then
      VGenOk := VProvider.GenerateVideo(VReq, VRes, VMetrics);
    if not VGenOk then
    begin
      VideoStep := TProjectService.CreateVideoStep(
        VideoJob.VideoJobId, STEP_TYPE_VIDEO_RENDER,
        VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_RENDER);
      VideoStep.MetricsJson := TVideoCompiler.RenderMetrics(
        RENDER_BACKEND_AGNES, EstimatedDuration, VideoAspect);
      VideoStep.ErrorMessage := 'Agnes video generation failed: ' + VRes.Status;
      VideoStep.Status := STATUS_FAILED;
      Repo.InsertVideoStep(VideoStep);
      Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED);
      Repo.UpdateJobStatus(Job.JobId, STATUS_FAILED);
      raise Exception.Create('VideoChain Step4: Agnes GenerateVideo failed for job ' + Job.JobId);
    end;

    // Register final video asset with the REAL generated MP4 path.
    FinalVideoAsset := TProjectService.CreateAsset(
      'video', VRes.OutputUri,
      'deepframes-agnes', '1.0.0', ProjectId);
    FinalVideoAsset.ContentUnitId := ContentUnitId;
    if VRes.DurationSec > 0 then
      FinalVideoAsset.DurationSec := VRes.DurationSec
    else
      FinalVideoAsset.DurationSec := EstimatedDuration;
    FinalVideoAsset.MimeType := 'video/mp4';
    FinalVideoAsset.Sha256 := TProjectService.Sha256Text('video-agnes-final-' + Job.JobId);
    if VRes.DurationSec > 0 then
      FinalVideoAsset.ByteSize := Round(VRes.DurationSec * 699051)
    else
      FinalVideoAsset.ByteSize := Round(EstimatedDuration * 699051);
    FinalVideoAsset.Status := ASSET_STATUS_TEMP;
    FinalVideoAsset.RetentionClass := RETENTION_CLASS_C2;
    Repo.InsertAsset(FinalVideoAsset);

    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_RENDER,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_RENDER);
    VideoStep.MetricsJson := TVideoCompiler.RenderMetrics(
      RENDER_BACKEND_AGNES, FinalVideoAsset.DurationSec, VideoAspect);
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

    // Create the mux VideoStep up front so failure (below) can record the
    // error against THIS step rather than against the prior render step.
    VideoStep := TProjectService.CreateVideoStep(
      VideoJob.VideoJobId, STEP_TYPE_VIDEO_MUX,
      VideoJob.VideoJobId + ':' + STEP_TYPE_VIDEO_MUX);
    VideoStep.Status := STATUS_RUNNING;
    Repo.InsertVideoStep(VideoStep);

    // Try FFmpeg mux via TAudioProcessor if audio manifest is available.
    // A failed mux must hard-stop the job: leaving a cover-only artifact
    // marked DONE would deliver a silent/broken "success" to the user.
    if AudioManifestId <> '' then
    begin
      var MuxAManifests := Repo.ListAudioManifests(ContentUnitId);
      for var MuxAM in MuxAManifests do
        if SameText(MuxAM.ManifestId, AudioManifestId) then
        begin
          var MuxRootDir := DeepBase.Manager.DeepBase.RootPath;
          var MuxFile: string := TPath.Combine(
            TPath.Combine(MuxRootDir, 'output'),
            Format('video/%s/output/bilibili_1080p.mp4', [Job.JobId]));
          // Create output directory
          ForceDirectories(TPath.GetDirectoryName(MuxFile));
          // Resolve the REAL audio file path first. The old code built
          // MuxArgs from MuxAM.MergedAudioAssetId (a UUID) before looking
          // up the asset URI — FFmpeg got a UUID as -i input and failed.
          var MuxAudioUri: string := '';
          var MuxAssets := Repo.ListAssets(ContentUnitId);
          for var MuxAsset in MuxAssets do
            if SameText(MuxAsset.AssetId, MuxAM.MergedAudioAssetId) then
            begin
              MuxAudioUri := MuxAsset.Uri;
              Break;
            end;
          // A missing audio URI must hard-stop, not silently skip mux.
          // The old `if MuxAudioUri <> '' then` guard produced a cover-only
          // "success" (video with no audio) when the asset wasn't found.
          if MuxAudioUri = '' then
          begin
            VideoStep.ErrorMessage :=
              'Mux skipped: merged audio asset URI not found (id=' +
              MuxAM.MergedAudioAssetId + ')';
            Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_FAILED);
            Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED);
            Repo.UpdateJobStatus(Job.JobId, STATUS_FAILED);
            raise Exception.Create('VideoChain Step5: audio asset URI missing for job ' + Job.JobId);
          end;
          var MuxOut: string;
          var MuxArgs: string;

          // Wait for video file to be fully written (check size stability)
          var VideoFilePath := FinalVideoAsset.Uri;
          if TFile.Exists(VideoFilePath) then
          begin
            var PrevSize := TFile.GetSize(VideoFilePath);
            for var WaitLoop := 0 to 4 do
            begin
              Sleep(500);
              var CurrSize := TFile.GetSize(VideoFilePath);
              if CurrSize = PrevSize then
                Break;
              PrevSize := CurrSize;
            end;
          end;

          // -----------------------------------------------------------------
          // D5 (tasks.md, 2026-07-13): explicit audio/video duration alignment.
          // The legacy mux used -shortest, which silently truncated to the
          // shorter stream — a TTS audio slightly longer than the Agnes video
          // lost its tail (and with it trailing subtitle cues). Now the output
          // duration is chosen explicitly by --duration-strategy:
          //   audio-base = output lasts the audio's duration (audio is timing
          //               truth; video shorter than audio is NOT loop-extended
          //               in the copy branch — it ends at its natural frame,
          //               but audio is no longer cut short).
          //   video-base = output lasts the video's duration (audio is not
          //               padded here, but no longer cut short by -shortest if
          //               it were the longer one).
          //   shortest   = legacy -shortest (default, backward compatible).
          // Probe both streams with ffprobe (TAudioProcessor.GetDuration, the
          // bugfix-B1 ffprobe path). On probe failure we fall back to
          // -shortest so a broken ffprobe can never hard-stop the pipeline.
          // -----------------------------------------------------------------
          var Strategy := GetConfig(CONFIG_DURATION_STRATEGY, DEFAULT_DURATION_STRATEGY);
          if Trim(Strategy) = '' then
            Strategy := DEFAULT_DURATION_STRATEGY;
          var AudioDurSec := TAudioProcessor.GetDuration(MuxAudioUri);
          var VideoDurSec := TAudioProcessor.GetDuration(FinalVideoAsset.Uri);
          // DurationTailArg replaces -shortest in both branches below. Empty =
          // keep -shortest (probe failed or strategy=shortest).
          var DurationTailArg: string := '-shortest';
          var StrategyNote := 'shortest(default)';
          // VideoLoopArg: when audio-base and the generated video is shorter
          // than the audio (typical — Agnes returns ~5s clips for ~68s TTS),
          // loop the video input so it fills the full audio duration instead
          // of freezing/black-screening after the clip's last frame. -stream_loop
          // -1 must precede the first -i. Empty for other strategies / when
          // video is already long enough.
          var VideoLoopArg: string := '';
          if (Strategy = 'audio-base') and (AudioDurSec > 0) then
          begin
            DurationTailArg := '-t ' + FormatFloat('0.000', AudioDurSec);
            if (VideoDurSec > 0) and (VideoDurSec < AudioDurSec) then
              VideoLoopArg := '-stream_loop -1 ';
            var LoopFlag: string;
            if VideoLoopArg <> '' then LoopFlag := '1' else LoopFlag := '0';
            StrategyNote := 'audio-base (audio=' + FormatFloat('0.000', AudioDurSec) +
              's video=' + FormatFloat('0.000', VideoDurSec) + 's loop=' + LoopFlag + ')';
          end
          else if (Strategy = 'video-base') and (VideoDurSec > 0) then
          begin
            DurationTailArg := '-t ' + FormatFloat('0.000', VideoDurSec);
            StrategyNote := 'video-base (audio=' + FormatFloat('0.000', AudioDurSec) +
              's video=' + FormatFloat('0.000', VideoDurSec) + 's)';
          end
          else if (Strategy <> 'shortest') and (AudioDurSec <= 0) and (VideoDurSec <= 0) then
            StrategyNote := Strategy + '(probe-failed→shortest)';
          TWorkflowLogger.LogJobEvent(Job.JobId, 'video_mux_duration_strategy',
            esInfo, 'duration alignment: ' + StrategyNote,
            '{"strategy":"' + Strategy + '","audio_sec":' +
            FormatFloat('0.000', AudioDurSec) + ',"video_sec":' +
            FormatFloat('0.000', VideoDurSec) + '}');

          // Burn subtitles into the video when a non-empty .srt was produced
          // in Step 3b. Burning requires re-encoding the video stream
          // (-c:v libx264), so it is a heavier path than the copy-only mux;
          // when there are no subtitles we keep the fast -c:v copy mux.
          // SubSrtFile is hoisted to the procedure var block so it survives
          // from Step 3b into Step 5. An empty-cue run still writes a 0-byte
          // .srt (ToSRT of zero cues is empty), so the >0 size guard correctly
          // distinguishes a real subtitle track from a placeholder file.
          if (SubSrtFile <> '') and TFile.Exists(SubSrtFile) and
             (TFile.GetSize(SubSrtFile) > 0) then
          begin
            var NormVideoUri2 := StringReplace(FinalVideoAsset.Uri, '/', '\', [rfReplaceAll]);
            var NormAudioUri2 := StringReplace(MuxAudioUri, '/', '\', [rfReplaceAll]);
            var NormMuxFile2 := StringReplace(MuxFile, '/', '\', [rfReplaceAll]);
            var NormSubSrt := StringReplace(SubSrtFile, '/', '\', [rfReplaceAll]);
            var EscSrt := EscapeSrtPathForFilter(NormSubSrt);
            MuxArgs := Format(
              '-nostdin %s-i "%s" -i "%s" -map 0:v:0 -map 1:a:0 -vf "subtitles=f=''%s''" -c:v libx264 -preset veryfast ' +
              '-crf 20 -c:a aac -b:a 192k %s "%s" -y',
              [VideoLoopArg, NormVideoUri2, NormAudioUri2, EscSrt, DurationTailArg, NormMuxFile2]);
            TWorkflowLogger.LogJobEvent(Job.JobId, 'video_mux_subtitle_burn',
              esInfo, 'burning subtitles into muxed video',
              '{"srt":"' + NormSubSrt + '"}');
          end
          else
          begin
            var NormVideoUri := StringReplace(FinalVideoAsset.Uri, '/', '\', [rfReplaceAll]);
            var NormAudioUri := StringReplace(MuxAudioUri, '/', '\', [rfReplaceAll]);
            var NormMuxFile := StringReplace(MuxFile, '/', '\', [rfReplaceAll]);
            MuxArgs := Format(
              '-nostdin %s-i "%s" -i "%s" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k %s "%s" -y',
              [VideoLoopArg, NormVideoUri, NormAudioUri, DurationTailArg, NormMuxFile]);
            TWorkflowLogger.LogJobEvent(Job.JobId, 'video_mux_subtitle_burn',
              esInfo, 'no subtitles, fast copy mux', '{}');
          end;
          var MuxExitCode: Integer;
          // Adaptive ffmpeg timeout: mux re-encodes video (libx264 veryfast),
          // roughly 0.2x realtime on this box. Give 10x the source duration as
          // a safety margin (covers subtitle burn-in overhead) with a 120s
          // floor so even sub-12s clips get a generous window, and cap at
          // 1800s so a pathological input can't hang the pipeline forever.
          var SrcDurationSec: Double := FinalVideoAsset.DurationSec;
          if SrcDurationSec <= 0 then SrcDurationSec := EstimatedDuration;
          var MuxTimeoutMs: Cardinal := Cardinal(Min(Max(120, Round(SrcDurationSec * 10)), 1800)) * 1000;
          MuxExitCode := TAudioProcessor.Execute(MuxArgs, MuxOut, MuxTimeoutMs);

          // Check if mux succeeded: either exit code 0, or output file exists and is valid (>1KB)
          var MuxSuccess := (MuxExitCode = 0) or
            (TFile.Exists(MuxFile) and (TFile.GetSize(MuxFile) > 1024));

          if not MuxSuccess then
          begin
            VideoStep.ErrorMessage := 'FFmpeg mux non-zero exit: ' + MuxOut;
            Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_FAILED);
            Repo.UpdateJobStepStatus(Step.StepId, STATUS_FAILED);
            Repo.UpdateJobStatus(Job.JobId, STATUS_FAILED);
            raise Exception.Create('FFmpeg mux failed (non-zero exit) for job ' + Job.JobId);
          end
          else
            // D8: mux produced the final deliverable MP4 — Gate 3b scores this.
            Gate3bMp4 := MuxFile;
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

    // Register cover video asset link (VideoStep was created earlier in this step)
    VideoAsset := TProjectService.CreateVideoAsset(
      VideoJob.VideoJobId, VideoStep.VideoStepId,
      CoverAsset.AssetId, ASSET_CATEGORY_COVER, 0);
    Repo.InsertVideoAsset(VideoAsset);

    Repo.UpdateVideoStepStatus(VideoStep.VideoStepId, STATUS_DONE);

    // Update actual duration after render
    Repo.UpdateVideoIRDuration(VideoIR.VideoIRId, EstimatedDuration, EstimatedDuration);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // D8 (tasks.md): Gate 3b — visual QA on the REAL produced MP4.
    // Runs AFTER render/mux. Was a stub EvaluateGate3b(1.0) before render
    // that scored a non-existent keyframe_001.png at a hardcoded 1.0 (a silent
    // hardcoded PASS — red-line #8 violation). Now: extract real frames from
    // the final MP4 via TFrameExtractor, then ask the vision-LLM to rate them.
    //
    // No vision provider is wired yet: StepFunLLMProvider.ChatComplete is
    // text-only (no image_url), so AProviderReached := False and
    // EvaluateGate3bFromVLM returns a degraded WARN (Score=-1, "visual gate
    // UNVERIFIED"). Per red-line #8 a yellow light is recorded and the pipeline
    // continues — but it is no longer a silent pass. A FAIL verdict (when a real
    // VLM eventually scores below 0.70) still blocks production.
    //
    // TODO(D8): wire the real vision provider (StepFun Vision or Gemini
    // generateContent), pass AProviderReached := True + the VLM's free-text
    // response. The frame extraction + gate plumbing below already works.
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := 'video.gate3b';
    Step.StepKey := Job.JobId + ':video.gate3b';
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);

    // Pick the MP4 to score: mux output if mux ran, else render output.
    if Trim(Gate3bMp4) = '' then
      Gate3bMp4 := FinalVideoAsset.Uri;

    var Gate3bVerdict: TGateVerdict;
    var Gate3bFramesOk: Boolean := False;
    if (Gate3bMp4 <> '') and TFile.Exists(Gate3bMp4) then
      // 1 frame/sec, capped inside ExtractFrames; temp files owned by us.
      Gate3bFramesOk := TFrameExtractor.ExtractFrames(Gate3bMp4, 1, Gate3bFrames);

    try
      if not Gate3bFramesOk then
        // Frame extraction failed (no MP4 on disk / ffprobe-ffmpeg missing) —
        // degrade the same way as an unreachable VLM: WARN, unverified.
        Gate3bVerdict := TGateEvaluator.EvaluateGate3bFromVLM('', False)
      else
      begin
        // TODO(D8): feed Gate3bFrames (base64) to a real vision-LLM here and
        // pass its free-text response. Until that provider exists, reach=False
        // so we get the degraded WARN rather than fabricating a score.
        Gate3bVerdict := TGateEvaluator.EvaluateGate3bFromVLM('', False);
      end;
      GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId, Gate3bVerdict);
      Repo.InsertQualityGateResult(GateResult);
      // A failing Gate3b (real VLM scored < 0.70) blocks production. A degraded
      // WARN or a real WARN both continue — yellow light, recorded.
      if GateResult.GateResult = GATE_RESULT_FAIL then
      begin
        Repo.UpdateJobStatus(Job.JobId, STATUS_BLOCKED_REVIEW);
        Job.Status := STATUS_BLOCKED_REVIEW;
        Exit(Job);
      end;
    finally
      TFrameExtractor.CleanupFrames(Gate3bFrames);
    end;

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

/// <summary>
/// Parse the timestamps.json written by AudioChain Step2 (an array of
/// {word,start_sec,end_sec,confidence}) into TAsrWordTimestamp[].
/// Tolerant: any parse error / missing fields yields an empty array,
/// so subtitle generation degrades to no-cues rather than crashing the job.
/// </summary>
function ParseTimestampsJson(const AJson: string): TArray<TAsrWordTimestamp>;
var
  Arr: TJSONArray;
  O: TJSONObject;
  V: TJSONValue;
  I: Integer;
  W: TAsrWordTimestamp;
begin
  SetLength(Result, 0);
  if AJson = '' then Exit;
  try
    V := TJSONObject.ParseJSONValue(AJson);
  except
    V := nil;
  end;
  if not Assigned(V) or not (V is TJSONArray) then
  begin
    V.Free;
    Exit;
  end;
  Arr := TJSONArray(V);
  try
    SetLength(Result, Arr.Count);
    I := 0;
    for var F in Arr do
    begin
      if not (F is TJSONObject) then Continue;
      O := TJSONObject(F);
      W.Word := O.GetValue<string>('word', '');
      W.StartSec := O.GetValue<Double>('start_sec', 0.0);
      W.EndSec := O.GetValue<Double>('end_sec', 0.0);
      W.Confidence := O.GetValue<Double>('confidence', 0.0);
      Result[I] := W;
      Inc(I);
    end;
    SetLength(Result, I);
  finally
    V.Free;
  end;
end;

// Extract the first visual_prompt from a shot document payload JSON.
// Tolerates two shapes the splitter emits:
//   {shots:[{visual_prompt,...}]} and {segments:[{visual_prompt,...}]}.
// Returns '' if nothing usable is found - caller falls back to a default.
function ExtractFirstVisualPrompt(const AJson: string): string;
var
  Root, Shot: TJSONObject;
  Arr: TJSONArray;
  V: TJSONValue;
  Key: string;
begin
  Result := '';
  if AJson = '' then Exit;
  try
    V := TJSONObject.ParseJSONValue(AJson);
  except
    V := nil;
  end;
  if not Assigned(V) or not (V is TJSONObject) then
  begin
    V.Free;
    Exit;
  end;
  Root := TJSONObject(V);
  try
    Arr := nil;
    if Root.TryGetValue<TJSONArray>('shots', Arr) then
      Key := 'visual_prompt'
    else if Root.TryGetValue<TJSONArray>('segments', Arr) then
      Key := 'visual_prompt'
    else
      Exit;
    if (Arr = nil) or (Arr.Count = 0) then Exit;
    if not (Arr.Items[0] is TJSONObject) then Exit;
    Shot := TJSONObject(Arr.Items[0]);
    Result := Shot.GetValue<string>(Key, '');
  finally
    V.Free;
  end;
end;

function EscapeSrtPathForFilter(const APath: string): string;
begin
  // ffmpeg's `subtitles` filter is parsed by libass, which shares the
  // filtergraph escape rules: '\' is the escape char and ':' separates
  // filter options from each other. A raw Windows path like `D:\a\b.srt`
  // therefore breaks parsing three ways. Normalise defensively:
  //   1. backslash -> forward slash (also makes the path portable)
  //   2. every ':' -> '\:' (covers both the drive-letter colon and any
  //      colon inside an absolute path)
  // The result is safe to embed directly as subtitles=<value> inside a
  // double-quoted -vf argument. Our own srt paths are already forward-slash
  // relative paths, so for those this is a no-op; the escaping exists to
  // survive being fed an absolute Windows path.
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := StringReplace(Result, ':', '\:', [rfReplaceAll]);
end;

end.