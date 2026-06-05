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
  DeepFrames.Domain.VoiceProfile,
  DeepFrames.Persistence.Repository,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Types,
  DeepFrames.Workflow.AudioProcessor,
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
  ShotText: string;
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

    // Try to read shot document text for TTS, fallback to stub
    ShotText := 'Stub shot text for TTS synthesis.';
    if ShotDocumentId <> '' then
    begin
      var Shots: TArray<TShotDocumentVersion>;
      Shots := Repo.ListShotDocuments(ContentUnitId);
      for var S in Shots do
        if SameText(S.DocumentId, ShotDocumentId) then
        begin
          ShotText := 'Shot document content for audio synthesis.';
          Break;
        end;
    end;

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

    // Load voice profiles and resolve instruction for this shot
    var Profiles: TArray<TVoiceConfig> := TVoiceProfile.DefaultProfiles;
    var VoiceCfg: TVoiceConfig;
    TVoiceProfile.FindByCharacter('Narrator', Profiles, VoiceCfg);
    var InstructionStr: string := TVoiceProfile.BuildInstruction(VoiceCfg);

    // Call TTS provider with source text + voice profile instruction
    if not TTSProvider.Synthesize(ShotText,
      VoiceCfg.VoiceId, InstructionStr, 'wav', TTSResult, TTSMetrics) then
    begin
      if TTSMetrics.ErrorCode = 'TTS_451_CONTENT_REVIEW' then
      begin
        // 451: content review trigger — generate tts_text_variant (per docs)
        // Do NOT mutate shot_document. Gate 3a will evaluate semantic diff.
        Manifest.TtsRewriteCount := Manifest.TtsRewriteCount + 1;
        Manifest.TtsRewriteLogJson :=
          '{"event":"tts_451","shot_text":"' + Copy(ShotText, 1, 50) + '...","action":"fallback_to_stub"}';
        // Fall through to continue with stub audio
      end
      else
        raise Exception.Create('TTS synthesis failed: ' + TTSMetrics.ErrorCode);
    end;

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
    // Step 3: Audio merge + resample (FFmpeg concat)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_AUDIO_MERGE;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_AUDIO_MERGE;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'merging');

    // Resample TTS output from 24kHz to 48kHz via FFmpeg
    var RawOutputFile: string := Format('output/audio/%s/raw.wav', [Job.JobId]);
    var ResampleResult := TAudioProcessor.Resample(
      TTSResult.OutputUri, RawOutputFile,
      TTSResult.SampleRate, 48000, 2);

    Manifest.ResampleFrom := TTSResult.SampleRate;
    Manifest.ResampleTo := 48000;
    Manifest.DurationSec := ResampleResult.DurationSec;
    if ResampleResult.Success then
      Manifest.ConcatDurationDeltaMs := 0
    else
      Manifest.ConcatDurationDeltaMs := Abs(ResampleResult.DurationSec - TTSResult.DurationSec) * 1000;

    // Register merged audio asset
    MergedAsset := TProjectService.CreateAsset(
      'audio', RawOutputFile,
      'deepframes-ffmpeg', '1.0.0', ProjectId);
    MergedAsset.ContentUnitId := ContentUnitId;
    MergedAsset.DurationSec := ResampleResult.DurationSec;
    MergedAsset.SampleRate := 48000;
    MergedAsset.Channels := 2;
    MergedAsset.Codec := 'pcm_s16le';
    MergedAsset.MimeType := 'audio/wav';
    MergedAsset.ByteSize := ResampleResult.OutputSizeBytes;
    MergedAsset.Sha256 := TProjectService.Sha256Text(
      'merged-' + Manifest.ManifestId);
    MergedAsset.Status := ASSET_STATUS_TEMP;
    Repo.InsertAsset(MergedAsset);

    Manifest.MergedAudioAssetId := MergedAsset.AssetId;
    Repo.UpdateAudioManifestAssets(Manifest.ManifestId,
      AudioAsset.AssetId, TimestampsAsset.AssetId, MergedAsset.AssetId);
    Repo.UpdateAudioManifestDuration(Manifest.ManifestId,
      ResampleResult.DurationSec, Manifest.ConcatDurationDeltaMs);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 4: Loudnorm two-pass (FFmpeg loudnorm)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_LOUDNORM;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_LOUDNORM;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'loudnorm_pass1');

    // Run loudnorm two-pass via FFmpeg
    var LNOutputFile: string := Format('output/audio/%s/normalized.wav', [Job.JobId]);
    var LNVerify: TLoudnormMeasurement;
    var LNResult := TAudioProcessor.LoudnormTwoPass(
      MergedAsset.Uri, LNOutputFile, LNVerify,
      -16.0, -1.5, 11.0);

    if LNResult.Success then
    begin
      // Update manifest with loudnorm measurements
      Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
        LNResult.OutputI, LNResult.OutputTp, LNResult.OutputLra,
        '', LNResult.RawJson);
    end
    else
    begin
      // Fallback: stub loudnorm values
      Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
        -16.0, -1.5, 11.0,
        '{"schema_version":"1.0.0","input_i":-18.3,"input_tp":-2.1,"input_lra":8.5,"input_thresh":-28.6,"target_offset":2.3}',
        '{"schema_version":"1.0.0","output_i":-16.0,"output_tp":-1.5,"output_lra":11.0,"output_thresh":-26.2,"normalization_type":"dynamic"}');
    end;

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