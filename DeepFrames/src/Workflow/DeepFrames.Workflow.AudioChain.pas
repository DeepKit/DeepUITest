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
  DeepFrames.Shared.Consts;

// Fake TTS provider: returns stub audio metadata
function FakeTtsOutput: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('format', 'wav');
    Obj.AddPair('sample_rate', TJSONNumber.Create(24000));
    Obj.AddPair('channels', TJSONNumber.Create(1));
    Obj.AddPair('duration_sec', TJSONNumber.Create(3.5));
    Obj.AddPair('voice', 'cixingnansheng');
    Obj.AddPair('instruction', '平静沉稳，语速偏慢');
    Obj.AddPair('char_count', TJSONNumber.Create(42));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

// Fake ASR provider: returns stub word-level timestamps
function FakeAsrOutput: string;
var
  Obj: TJSONObject;
  WordsArr: TJSONArray;
  WordObj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('duration_sec', TJSONNumber.Create(3.5));
    WordsArr := TJSONArray.Create;
    for var I := 0 to 4 do
    begin
      WordObj := TJSONObject.Create;
      WordObj.AddPair('word', '词' + IntToStr(I + 1));
      WordObj.AddPair('start_sec', TJSONNumber.Create(I * 0.7));
      WordObj.AddPair('end_sec', TJSONNumber.Create(I * 0.7 + 0.6));
      WordsArr.AddElement(WordObj);
    end;
    Obj.AddPair('words', WordsArr);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

// Fake loudnorm measurement output
function FakeLoudnormPass1: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('input_i', TJSONNumber.Create(-18.3));
    Obj.AddPair('input_tp', TJSONNumber.Create(-2.1));
    Obj.AddPair('input_lra', TJSONNumber.Create(8.5));
    Obj.AddPair('input_thresh', TJSONNumber.Create(-28.6));
    Obj.AddPair('target_offset', TJSONNumber.Create(2.3));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function FakeLoudnormPass2: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', '1.0.0');
    Obj.AddPair('output_i', TJSONNumber.Create(-16.0));
    Obj.AddPair('output_tp', TJSONNumber.Create(-1.5));
    Obj.AddPair('output_lra', TJSONNumber.Create(11.0));
    Obj.AddPair('output_thresh', TJSONNumber.Create(-26.2));
    Obj.AddPair('normalization_type', 'dynamic');
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

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
  TtsRaw, AsrRaw: string;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);

  Repo := TDeepFramesRepository.Create;
  try
    // Idempotency: if job already exists, return it
    if Repo.FindJobByLogicalKey(LogicalKey, ExistingJob) then
      Exit(ExistingJob);

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

    // Fake TTS call
    TtsRaw := FakeTtsOutput;

    // Record prompt run for TTS
    PromptRun := TProjectService.CreatePromptRun(
      Job.JobId, Step.StepId, '', '', '',
      TtsRaw, 'stepfun', 'stepaudio-2.5-tts', CAPABILITY_TTS);
    PromptRun.NormalizedJson := TtsRaw;
    PromptRun.LatencyMs := 350;
    PromptRun.TtsCharCount := 42;
    Repo.InsertPromptRun(PromptRun);

    // Register shot-level audio asset
    AudioAsset := TProjectService.CreateAsset(
      'audio', 'audio/' + Job.JobId + '/shots/shot_001.wav',
      'stepfun-tts', 'stepaudio-2.5', ProjectId);
    AudioAsset.ContentUnitId := ContentUnitId;
    AudioAsset.DurationSec := 3.5;
    AudioAsset.SampleRate := 24000;
    AudioAsset.Channels := 1;
    AudioAsset.Codec := 'pcm_s16le';
    AudioAsset.MimeType := 'audio/wav';
    AudioAsset.ByteSize := 336000; // 3.5s * 24000Hz * 2ch * 2bytes
    AudioAsset.Sha256 := TProjectService.Sha256Text('stub-tts-shot-001');
    AudioAsset.Status := ASSET_STATUS_READY;
    Repo.InsertAsset(AudioAsset);

    // Update manifest with audio asset reference
    Manifest.AudioAssetId := AudioAsset.AssetId;
    Manifest.SampleRate := 24000;
    Manifest.Channels := 1;
    Manifest.DurationSec := 3.5;
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

    // Fake ASR call
    AsrRaw := FakeAsrOutput;

    // Record prompt run for ASR
    PromptRun := TProjectService.CreatePromptRun(
      Job.JobId, Step.StepId, '', '', '',
      AsrRaw, 'stepfun', 'stepfun-asr', CAPABILITY_ASR);
    PromptRun.NormalizedJson := AsrRaw;
    PromptRun.AsrDurationSec := 3.5;
    PromptRun.LatencyMs := 500;
    Repo.InsertPromptRun(PromptRun);

    // Register timestamps asset
    TimestampsAsset := TProjectService.CreateAsset(
      'manifest', 'audio/' + Job.JobId + '/timestamps.json',
      'deepframes-asr', '1.0.0', ProjectId);
    TimestampsAsset.ContentUnitId := ContentUnitId;
    TimestampsAsset.MimeType := 'application/json';
    TimestampsAsset.Sha256 := TProjectService.Sha256Text('stub-timestamps');
    TimestampsAsset.Status := ASSET_STATUS_READY;
    Repo.InsertAsset(TimestampsAsset);

    // Update manifest with timestamps asset
    Manifest.TimestampsAssetId := TimestampsAsset.AssetId;
    Repo.UpdateAudioManifestAssets(Manifest.ManifestId,
      AudioAsset.AssetId, TimestampsAsset.AssetId, '');

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 3: Audio merge (fake FFmpeg concat)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_AUDIO_MERGE;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_AUDIO_MERGE;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'merging');

    // Fake merge: resample from 24000 to 48000
    Manifest.ResampleFrom := 24000;
    Manifest.ResampleTo := 48000;
    Manifest.DurationSec := 3.5;
    // Concat duration delta: 0ms (single shot, no gap)
    Manifest.ConcatDurationDeltaMs := 0;

    // Register merged audio asset
    MergedAsset := TProjectService.CreateAsset(
      'audio', 'audio/' + Job.JobId + '/raw.wav',
      'deepframes-ffmpeg', '1.0.0', ProjectId);
    MergedAsset.ContentUnitId := ContentUnitId;
    MergedAsset.DurationSec := 3.5;
    MergedAsset.SampleRate := 48000;
    MergedAsset.Channels := 2;
    MergedAsset.Codec := 'pcm_s16le';
    MergedAsset.MimeType := 'audio/wav';
    MergedAsset.ByteSize := 1344000; // 3.5s * 48000Hz * 2ch * 2bytes
    MergedAsset.Sha256 := TProjectService.Sha256Text('stub-merged-raw');
    MergedAsset.Status := ASSET_STATUS_TEMP;
    Repo.InsertAsset(MergedAsset);

    Manifest.MergedAudioAssetId := MergedAsset.AssetId;
    Repo.UpdateAudioManifestAssets(Manifest.ManifestId,
      AudioAsset.AssetId, TimestampsAsset.AssetId, MergedAsset.AssetId);
    Repo.UpdateAudioManifestDuration(Manifest.ManifestId, 3.5, 0);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Step 4: Loudnorm two-pass (fake)
    // ---------------------------------------------------------------
    Step.StepId := NewUuidString;
    Step.JobId := Job.JobId;
    Step.StepType := STEP_TYPE_LOUDNORM;
    Step.StepKey := Job.JobId + ':' + STEP_TYPE_LOUDNORM;
    Step.Status := STATUS_PENDING;
    Repo.InsertJobStep(Step);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_RUNNING);
    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'loudnorm_pass1');

    // Fake loudnorm pass 1 measurement
    Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
      -18.3, -2.1, 8.5, FakeLoudnormPass1, '');

    Repo.UpdateAudioManifestStatus(Manifest.ManifestId, 'loudnorm_pass2');

    // Fake loudnorm pass 2 (apply correction with measured_* params)
    Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
      -16.0, -1.5, 11.0, FakeLoudnormPass1, FakeLoudnormPass2);

    // Promote merged asset to ready after loudnorm
    if not TProjectService.IsAssetStatusTransitionValid(ASSET_STATUS_TEMP, ASSET_STATUS_READY) then
      raise Exception.Create('Invalid asset status transition: temp -> ready');
    Repo.UpdateAssetStatus(MergedAsset.AssetId, ASSET_STATUS_READY);

    Repo.UpdateJobStepStatus(Step.StepId, STATUS_DONE);

    // ---------------------------------------------------------------
    // Gate 3a: audio quality check
    // ---------------------------------------------------------------
    GateResult := TProjectService.CreateQualityGateResult(
      Job.JobId, GATE_3A, GATE_RESULT_PASS, 1.0);
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
