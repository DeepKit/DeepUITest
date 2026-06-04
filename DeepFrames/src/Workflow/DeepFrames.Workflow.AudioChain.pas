unit DeepFrames.Workflow.AudioChain;

interface

uses
  DeepFrames.Domain.Types;

type
  TAudioChainWorkflow = class
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
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Types,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Shared.Consts;

class function TAudioChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, ShotDocumentId: string): string;
begin
  Result := JOB_TYPE_AUDIO + ':' + ProjectId + ':' + ContentUnitId +
    ':' + ShotDocumentId;
end;

class function TAudioChainWorkflow.RunChain(const ProjectId, ContentUnitId,
  ShotDocumentId: string): TDeepFramesJob;
var
  Repo: TDeepFramesRepository;
  Job: TDeepFramesJob;
  Step: TDeepFramesJobStep;
  ExistingJob: TDeepFramesJob;
  Manifest: TAudioManifest;
  PromptRun: TPromptRun;
  GateResult: TQualityGateResult;
  AudioAsset: TAssetRecord;
  TimestampsAsset: TAssetRecord;
  MergedAsset: TAssetRecord;
  LogicalKey: string;
  TTSProvider: IDeepFramesTTSProvider;
  ASRProvider: IDeepFramesASRProvider;
  TTSResult: TTtsSynthesisResult;
  TTSMetrics: TProviderRunMetrics;
  ASRResult: TAsrTranscriptionResult;
  ASRMetrics: TProviderRunMetrics;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency: if job already exists, return it
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

    // Get provider instances from registry
    TTSProvider := TProviderRegistry.Instance.TTSProvider;
    ASRProvider := TProviderRegistry.Instance.ASRProvider;

    // Create audio job
    Job.JobId := NewUuidString;
    Job.ProjectId := ProjectId;
    Job.ContentUnitId := ContentUnitId;
    Job.JobType := JOB_TYPE_AUDIO;
    Job.LogicalKey := LogicalKey;
    Job.JobQueueTaskId := '';
    Job.Status := STATUS_PENDING;
    Repo.InsertJob(Job);

    // Create audio manifest
    Manifest := TProjectService.CreateAudioManifest(
      ProjectId, ContentUnitId, Job.JobId, ShotDocumentId);
    Repo.InsertAudioManifest(Manifest);

    // ---------------------------------------------------------------
    // Step 1: TTS synthesis
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_TTS_SYNTHESIS;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_TTS_SYNTHESIS;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for tts_synthesis');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'synthesizing');

    // Call TTS provider
    if not TTSProvider.Synthesize('Stub shot text for TTS synthesis.',
      'cixingnansheng', '平静沉稳，语速偏慢', 'wav', TTSResult, TTSMetrics) then
      raise Exception.Create('TTS synthesis failed: ' + TTSMetrics.ErrorCode);

    // Record prompt run for TTS
    PromptRun := TProjectService.CreatePromptRun(
      Job.JobId, Step.StepId, '', '', '',
      '', TTSMetrics.ProviderName, TTSMetrics.Model, CAPABILITY_TTS);
    PromptRun.LatencyMs := TTSMetrics.LatencyMs;
    PromptRun.TtsCharCount := TTSResult.CharCount;
    Repo.InsertPromptRun(PromptRun);

    // Register shot-level audio asset
    AudioAsset := TProjectService.CreateAsset(
      'audio', TTSResult.OutputUri,
      TTSMetrics.ProviderName, TTSMetrics.Model, ProjectId);
    AudioAsset.ContentUnitId := ContentUnitId;
    AudioAsset.DurationSec := TTSResult.DurationSec;
    AudioAsset.SampleRate := TTSResult.SampleRate;
    AudioAsset.Channels := TTSResult.Channels;
    AudioAsset.Codec := 'pcm_s16le';
    AudioAsset.MimeType := 'audio/' + TTSResult.Format;
    AudioAsset.ByteSize := TTSResult.OutputSizeBytes;
    AudioAsset.Sha256 := TProjectService.Sha256Text(
      'tts-' + TTSMetrics.ProviderName + '-' + TTSResult.OutputUri);
    AudioAsset.Status := ASSET_STATUS_READY;
    Repo.InsertAsset(AudioAsset);

    // Update manifest with audio asset reference
    Manifest.AudioAssetId := AudioAsset.AssetId;
    Manifest.SampleRate := TTSResult.SampleRate;
    Manifest.Channels := TTSResult.Channels;
    Manifest.DurationSec := TTSResult.DurationSec;
    Repo.UpdateAudioManifestAssets(Manifest.ManifestId,
      AudioAsset.AssetId, '', '');

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for tts_synthesis');
    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 2: ASR timestamps
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_ASR_TIMESTAMPS;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_ASR_TIMESTAMPS;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'asr_done');

    // Call ASR provider
    if not ASRProvider.Transcribe(AudioAsset.Uri, ASRResult, ASRMetrics) then
      raise Exception.Create('ASR transcription failed: ' + ASRMetrics.ErrorCode);

    // Record prompt run for ASR
    PromptRun := TProjectService.CreatePromptRun(
      Job.JobId, Step.StepId, '', '', '',
      '', ASRMetrics.ProviderName, ASRMetrics.Model, CAPABILITY_ASR);
    PromptRun.AsrDurationSec := ASRResult.DurationSec;
    PromptRun.LatencyMs := ASRMetrics.LatencyMs;
    Repo.InsertPromptRun(PromptRun);

    // Register timestamps asset
    TimestampsAsset := TProjectService.CreateAsset(
      'manifest', 'audio/' + Job.JobId + '/timestamps.json',
      'deepframes-asr', '1.0.0', ProjectId);
    TimestampsAsset.ContentUnitId := ContentUnitId;
    TimestampsAsset.MimeType := 'application/json';
    TimestampsAsset.Sha256 := TProjectService.Sha256Text(
      'asr-timestamps-' + ASRMetrics.ProviderName);
    TimestampsAsset.Status := ASSET_STATUS_READY;
    Repo.InsertAsset(TimestampsAsset);

    // Update manifest with timestamps asset
    Manifest.TimestampsAssetId := TimestampsAsset.AssetId;
    Repo.UpdateAudioManifestAssets(Manifest.ManifestId,
      AudioAsset.AssetId, TimestampsAsset.AssetId, '');

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 3: Audio merge (FFmpeg concat)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_AUDIO_MERGE;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_AUDIO_MERGE;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'merging');

    // Resample from 24000 to 48000
    Manifest.ResampleFrom := TTSResult.SampleRate;
    Manifest.ResampleTo := 48000;
    Manifest.DurationSec := TTSResult.DurationSec;
    Manifest.ConcatDurationDeltaMs := 0;

    // Register merged audio asset
    MergedAsset := TProjectService.CreateAsset(
      'audio', 'audio/' + Job.JobId + '/raw.wav',
      'deepframes-ffmpeg', '1.0.0', ProjectId);
    MergedAsset.ContentUnitId := ContentUnitId;
    MergedAsset.DurationSec := TTSResult.DurationSec;
    MergedAsset.SampleRate := 48000;
    MergedAsset.Channels := 2;
    MergedAsset.Codec := 'pcm_s16le';
    MergedAsset.MimeType := 'audio/wav';
    MergedAsset.ByteSize := Round(TTSResult.DurationSec * 48000 * 2 * 2);
    MergedAsset.Sha256 := TProjectService.Sha256Text(
      'merged-' + Manifest.ManifestId);
    MergedAsset.Status := ASSET_STATUS_TEMP;
    Repo.InsertAsset(MergedAsset);

    Manifest.MergedAudioAssetId := MergedAsset.AssetId;
    Repo.UpdateAudioManifestAssets(Manifest.ManifestId,
      AudioAsset.AssetId, TimestampsAsset.AssetId, MergedAsset.AssetId);
    Repo.UpdateAudioManifestDuration(Manifest.ManifestId,
      TTSResult.DurationSec, 0);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 4: Loudnorm two-pass
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_LOUDNORM;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_LOUDNORM;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'loudnorm_pass1');

    // Loudnorm pass 1: measurement (stub)
    Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
      -18.3, -2.1, 8.5,
      '{"schema_version":"1.0.0","input_i":-18.3,"input_tp":-2.1,"input_lra":8.5,"input_thresh":-28.6,"target_offset":2.3}',
      '');

    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'loudnorm_pass2');

    // Loudnorm pass 2: apply correction with measured_* params
    Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
      -16.0, -1.5, 11.0,
      '{"schema_version":"1.0.0","input_i":-18.3,"input_tp":-2.1,"input_lra":8.5,"input_thresh":-28.6,"target_offset":2.3}',
      '{"schema_version":"1.0.0","output_i":-16.0,"output_tp":-1.5,"output_lra":11.0,"output_thresh":-26.2,"normalization_type":"dynamic"}');

    // Promote merged asset to ready after loudnorm
    if not TProjectService.IsAssetStatusTransitionValid(ASSET_STATUS_TEMP, ASSET_STATUS_READY) then
      raise Exception.Create('Invalid asset status transition: temp -> ready');
    Repo.UpdateAssetStatus(MergedAsset.AssetId, ASSET_STATUS_READY);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Gate 3a: audio quality check
    // ---------------------------------------------------------------
    GateResult := TGateEvaluator.ToQualityGateResult(Job.JobId,
      TGateEvaluator.EvaluateGate3a(
        Manifest.MeasuredLufs, Manifest.TargetLufs, Manifest.ConcatDurationDeltaMs));
    Repo.InsertQualityGateResult(GateResult);

    // Transition manifest -> done
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, STATUS_DONE);

    // Transition job -> running -> done
    if not TProjectService.CanTransitionStatus(STATUS_PENDING, STATUS_RUNNING) then
      raise Exception.Create('Invalid status transition: pending -> running for audio job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_RUNNING);

    if not TProjectService.CanTransitionStatus(STATUS_RUNNING, STATUS_DONE) then
      raise Exception.Create('Invalid status transition: running -> done for audio job');
    Repo.UpdateJobStatus(Job.JobId, STATUS_DONE);

    Job.Status := STATUS_DONE;
    Result := Job;
  finally
    Repo.Free;
  end;
end;

end.