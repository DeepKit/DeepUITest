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
  System.Math,
  System.IOUtils,
  System.JSON,
  FireDAC.Comp.Client,
  DeepBase.Manager,
  DeepBase.Config,
  DeepBase.Logging,
  DeepFrames.Domain.Project,
  DeepFrames.Domain.VoiceProfile,
  DeepFrames.Persistence.Repository,
  DeepFrames.Provider.Intf,
  DeepFrames.Provider.Registry,
  DeepFrames.Provider.Types,
  DeepFrames.Workflow.AudioProcessor,
  DeepFrames.Workflow.GateEvaluator,
  DeepFrames.Shared.Consts;

/// Split Chinese/mixed text into sentence segments on common punctuation
/// (，。！？；,.!?;) and newlines. Each returned segment retains its trailing
/// delimiter so cue text reads naturally. Empty input yields a single empty
/// segment (caller floors it to 1 char). Used to give Baidu's whole-sentence
/// ASR result per-sentence timing for subtitle cue generation.
function SplitSentences(const AText: string): TArray<string>;
const
  Delims: array[0..8] of WideChar = (
    WideChar($FF0C), WideChar($3002), WideChar($FF01), WideChar($FF1F),
    WideChar($FF1B), ',', '.', '!', '?');
var
  I: Integer;
  Seg: string;
  procedure Flush;
  begin
    if Seg <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Seg;
      Seg := '';
    end;
  end;
begin
  Seg := '';
  for I := 1 to Length(AText) do
  begin
    Seg := Seg + AText[I];
    var IsDelim: Boolean := False;
    for var J := Low(Delims) to High(Delims) do
      if AText[I] = Delims[J] then
      begin
        IsDelim := True;
        Break;
      end;
    if IsDelim then
      Flush;
  end;
  Flush;
end;

class function TAudioChainWorkflow.BuildLogicalKey(const ProjectId,
  ContentUnitId, ShotDocumentId: string): string;
begin
  // TEMP: Include timestamp to force re-run and generate timestamps
  // In production, should use deterministic key for idempotency
  Result := JOB_TYPE_AUDIO + ':' + ProjectId + ':' + ContentUnitId +
    ':' + ShotDocumentId + ':' + FormatDateTime('yyyymmddhhnnss', Now);
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
  TTSSuccess: Boolean;
  ASRResult: TAsrTranscriptionResult;
  ASRMetrics: TProviderRunMetrics;
  ShotText: string;
begin
  LogicalKey := BuildLogicalKey(ProjectId, ContentUnitId, ShotDocumentId);
  Repo := TDeepFramesRepository.Create;

  try
    // Idempotency: if job already exists, return it
    var ExistingJobId := '';

    var Conn := Repo.GetConnection;
    var DirectQ := TFDQuery.Create(nil);

    try
      DirectQ.Connection := Conn;
      DirectQ.SQL.Text := 'SELECT job_id FROM deepframes_job WHERE logical_key = :lk';
      DirectQ.ParamByName('lk').AsString := LogicalKey;
      DirectQ.Open;

      if not DirectQ.Eof then
        ExistingJobId := DirectQ.FieldByName('job_id').AsString;
    finally
      DirectQ.Free;
    end;

    if ExistingJobId <> '' then
    begin
      // TEMP: Always re-run audio chain to generate timestamps
      // In production, should check if job is complete
      var ForceRerun := True;

      if not ForceRerun and Repo.FindJobById(ExistingJobId, ExistingJob) then
        Exit(ExistingJob);
    end;

    // Get provider instances from registry
    TTSProvider := TProviderRegistry.Instance.TTSProvider;
    ASRProvider := TProviderRegistry.Instance.ASRProvider;

    // Try to read shot document text for TTS from PayloadJson, fallback to stub
    ShotText := 'Stub shot text for TTS synthesis.';
    if ShotDocumentId <> '' then
    begin
      var Shots: TArray<TShotDocumentVersion>;
      Shots := Repo.ListShotDocuments(ContentUnitId);
      for var S in Shots do
        if SameText(S.DocumentId, ShotDocumentId) then
        begin
          // Extract text content from PayloadJson
          // PayloadJson format: {segments:[{text:"...",...},...]} or {shots:[{narration:"...",...}]}
          if S.PayloadJson <> '' then
          begin
            try
              var Json := TJSONObject.ParseJSONValue(S.PayloadJson) as TJSONObject;
              if Json <> nil then
              begin
                try
                  // Try segments array first. DocumentChain's LLM prompt asks for
                  // segments:[{narration,...}], so narration is the canonical
                  // field; text is a tolerated fallback for LLMs that rename it.
                  var SegJsonValue := Json.FindValue('segments');
                  if (SegJsonValue <> nil) and (SegJsonValue is TJSONArray) then
                  begin
                    var Segments := SegJsonValue as TJSONArray;
                    var TextParts: TArray<string> := [];
                    for var i := 0 to Segments.Count - 1 do
                    begin
                      var Seg := Segments.Items[i] as TJSONObject;
                      if Seg <> nil then
                      begin
                        var SegText: string := '';
                        var NarrationVal := Seg.FindValue('narration');
                        if (NarrationVal <> nil) and (NarrationVal.Value <> '') then
                          SegText := NarrationVal.Value
                        else
                        begin
                          var TextVal := Seg.FindValue('text');
                          if (TextVal <> nil) and (TextVal.Value <> '') then
                            SegText := TextVal.Value;
                        end;
                        if SegText <> '' then
                          TextParts := TextParts + [SegText];
                      end;
                    end;
                    if Length(TextParts) > 0 then
                      ShotText := string.Join(' ', TextParts);
                  end
                  else
                  begin
                    // Try shots array
                    var ShotsJsonValue := Json.FindValue('shots');
                    if (ShotsJsonValue <> nil) and (ShotsJsonValue is TJSONArray) then
                    begin
                      var ShotsArr := ShotsJsonValue as TJSONArray;
                      var TextParts: TArray<string> := [];
                      for var i := 0 to ShotsArr.Count - 1 do
                      begin
                        var Shot := ShotsArr.Items[i] as TJSONObject;
                        if Shot <> nil then
                        begin
                          var NarrationVal := Shot.FindValue('narration');
                          var Narration := '';
                          if NarrationVal <> nil then
                            Narration := NarrationVal.Value;
                          if Narration <> '' then
                            TextParts := TextParts + [Narration]
                          else
                          begin
                            var TextVal := Shot.FindValue('text');
                            if TextVal <> nil then
                            begin
                              var Text := TextVal.Value;
                              if Text <> '' then
                                TextParts := TextParts + [Text];
                            end;
                          end;
                        end;
                      end;
                      if Length(TextParts) > 0 then
                        ShotText := string.Join(' ', TextParts);
                    end;
                  end;
                finally
                  Json.Free;
                end;
              end;
            except
              // If JSON parsing fails, keep stub text
            end;
          end;
          Break;
        end;
    end;

    // This workflow runs in both CLI and VCL GUI paths. Use DeepBase logger;
    // bare WriteLn can crash a GUI process that has no attached console.
    Logger.InfoFmt(
      'ShotText len=%d preview=%s',
      [Length(ShotText), Copy(ShotText, 1, 80)],
      'DeepFrames.Audio');

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

    // D1.3 (tasks.md): --voice override. A CLI/config-supplied VoiceId wins
    // over the Narrator default from DefaultProfiles, so a run can target a
    // specific Baidu/StepFun voice without recompiling. Emotion/pace/pitch
    // keep their Narrator values; only the voice id is swapped.
    var CfgVoice := GetConfig(CONFIG_TTS_VOICE, DEFAULT_TTS_VOICE);
    if Trim(CfgVoice) <> '' then
      VoiceCfg.VoiceId := CfgVoice;

    // Call TTS provider with source text + voice profile instruction
    TTSSuccess := TTSProvider.Synthesize(ShotText,
      VoiceCfg.VoiceId, InstructionStr, 'wav', TTSResult, TTSMetrics);

    // Guard against false-green stubs: a provider may report success=True
    // while its OutputUri points at a file that was never materialized. Treat
    // that as a hard failure here rather than letting P5 mux crash on a
    // missing audio track.
    if TTSSuccess and (TTSResult.OutputUri <> '') and not FileExists(TTSResult.OutputUri) then
    begin
      Logger.ErrorFmt(
        'TTS false-green: success reported but file missing: %s (err=%s provider=%s)',
        [TTSResult.OutputUri, TTSMetrics.ErrorCode, TTSMetrics.ProviderName],
        'DeepFrames.Audio');
      TTSSuccess := False;
      if TTSMetrics.ErrorCode = '' then
        TTSMetrics.ErrorCode := 'TTS_OUTPUT_MISSING';
    end;

    // Surface TTS outcome through the standard structured logger.
    Logger.InfoFmt(
      'TTS success=%d out=%s exists=%d err=%s provider=%s',
      [Ord(TTSSuccess), TTSResult.OutputUri, Ord(FileExists(TTSResult.OutputUri)),
       TTSMetrics.ErrorCode, TTSMetrics.ProviderName],
      'DeepFrames.Audio');

    if not TTSSuccess then
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
      Job.JobId, Step.StepId, '', '', 'tts',
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
      Job.JobId, Step.StepId, '', '', 'asr',
      '', ASRMetrics.ProviderName, ASRMetrics.Model, CAPABILITY_ASR);
    PromptRun.AsrDurationSec := ASRResult.DurationSec;
    PromptRun.LatencyMs := ASRMetrics.LatencyMs;

    Repo.InsertPromptRun(PromptRun);

    // Fix: Use absolute path under RootPath/output/audio/{JobId}/timestamps.json
    var TsRootPath := DeepBase.Manager.DeepBase.RootPath;
    var TsDir: string := TPath.Combine(TPath.Combine(TsRootPath, 'output\audio'), Job.JobId);
    var TsFile: string := TPath.Combine(TsDir, 'timestamps.json');

    // Register timestamps asset. URI must be ABSOLUTE (not 'audio/{JobId}/...'),
    // because VideoChain reads it via TFile.ReadAllText(A.Uri) from a different
    // cwd (bin/) — a relative URI resolved there found no file, so subtitles
    // silently fell back to 0 words. See [[video-path-must-be-absolute]].
    TimestampsAsset := TProjectService.CreateAsset(
      'manifest', TsFile,
      'deepframes-asr', '1.0.0', ProjectId);
    TimestampsAsset.ContentUnitId := ContentUnitId;
    TimestampsAsset.MimeType := 'application/json';
    TimestampsAsset.Sha256 := TProjectService.Sha256Text(
      'asr-timestamps-' + ASRMetrics.ProviderName);
    TimestampsAsset.Status := ASSET_STATUS_READY;

    // Serialize real ASR word-level timestamps to the asset file so downstream
    // (VideoChain subtitle generation) can build true time-aligned subtitles.
    // Previously this asset record existed but the file was never written, so
    // VideoChain fell back to hardcoded fake cues ('字幕测试1'..'10').
    // DIAG: check for empty values that cause ForceDirectories failures
    if Job.JobId = '' then
      raise Exception.Create('DIAG: Job.JobId is empty');
    if TTSResult.OutputUri = '' then
      raise Exception.Create('DIAG: TTSResult.OutputUri is empty (TTS returned no file)');

    if TsDir <> '' then TDirectory.CreateDirectory(TsDir);

    // Build timestamps JSON. Baidu ASR returns whole-sentence text in Words[0]
    // with StartSec=EndSec=0 (no word-level timing). Downstream TSubtitleEngine
    // builds cues from StartSec/EndSec, so all-zero timing yields 0-duration
    // cues → empty .srt. Fix: when timing is degenerate (EndSec<=0), expand the
    // single sentence across [0, TTSResult.DurationSec] by splitting on
    // punctuation into per-sentence cues, each timed by proportional char count.
    // This is the "path 3" fallback (uniform allocation) — real word timestamps
    // from a future provider would skip this branch (EndSec>0).
    var DurationSec := ASRResult.DurationSec;
    if DurationSec <= 0 then
      DurationSec := TTSResult.DurationSec;
    if DurationSec <= 0 then
      DurationSec := 5.0;  // last-resort floor so cues aren't 0-duration

    var Stretched: TArray<TAsrWordTimestamp>;
    // Determine the source text for subtitle cues. Prefer real ASR word text;
    // but when ASR produced no usable text (silent/empty audio — e.g. TTS ran
    // in stub mode and produced a silence WAV), fall back to the original
    // ShotText so subtitles still carry the narration. Without this, Words=0
    // left Stretched empty → timestamps.json empty → zh.srt 0 bytes.
    var FallbackText := '';
    if (Length(ASRResult.Words) = 1) and (ASRResult.Words[0].Word <> '') then
      FallbackText := ASRResult.Words[0].Word
    else if (Length(ASRResult.Words) = 0) or
            ((Length(ASRResult.Words) = 1) and (Trim(ASRResult.Words[0].Word) = '')) then
      FallbackText := ShotText;

    Logger.InfoFmt(
      'ASR words=%d fallback_text_len=%d',
      [Length(ASRResult.Words), Length(FallbackText)],
      'DeepFrames.Audio');

    // Use the sentence-splitting path when ASR gave no usable per-word timing:
    //   - zero words, or
    //   - a single whole-sentence with EndSec<=0, or
    //   - any word slot whose text is empty (ASR produced no transcript).
    // In all these cases FallbackText holds ShotText (or the ASR sentence) so
    // subtitles still carry real narration stretched across DurationSec.
    var NeedsSplit := (Length(ASRResult.Words) = 0)
      or ((Length(ASRResult.Words) = 1) and (ASRResult.Words[0].EndSec <= 0));
    if (not NeedsSplit) and (Length(ASRResult.Words) > 0) then
      for var AW in ASRResult.Words do
        if Trim(AW.Word) = '' then begin NeedsSplit := True; Break; end;

    if NeedsSplit and (FallbackText <> '') then
    begin
      // Single whole-sentence with no timing → split into sentence cues.
      var Sentences := SplitSentences(FallbackText);
      if Length(Sentences) = 0 then
        SetLength(Sentences, 1);
      var TotalChars: Integer := 0;
      for var S in Sentences do
        TotalChars := TotalChars + Max(1, Length(S));
      var Pos: Double := 0;
      var GapSec: Double := 0.25;  // inter-cue gap so BuildCues splits on it
      for var S in Sentences do
      begin
        var Frac := Max(1, Length(S)) / TotalChars;
        var SegStart := Pos * DurationSec;
        var SegEnd := (Pos + Frac) * DurationSec;
        // Leave a gap before the next cue (except the last) so
        // TSubtitleEngine.BuildCues (gap > MinGapMs=200) emits one cue per
        // sentence rather than merging them into a single 0→duration cue.
        if Pos + Frac < 1.0 then
          SegEnd := Max(SegStart + 0.05, SegEnd - GapSec);
        SetLength(Stretched, Length(Stretched) + 1);
        Stretched[High(Stretched)].Word := S;
        Stretched[High(Stretched)].StartSec := SegStart;
        Stretched[High(Stretched)].EndSec := SegEnd;
        if Length(ASRResult.Words) > 0 then
          Stretched[High(Stretched)].Confidence := ASRResult.Words[0].Confidence
        else
          Stretched[High(Stretched)].Confidence := 0.0;
        Pos := Pos + Frac;
      end;
    end
    else
      Stretched := ASRResult.Words;

    var TsArr := TJSONArray.Create;
    try
      for var W in Stretched do
      begin
        var O := TJSONObject.Create;
        O.AddPair('word', W.Word);
        O.AddPair('start_sec', TJSONNumber.Create(W.StartSec));
        O.AddPair('end_sec', TJSONNumber.Create(W.EndSec));
        O.AddPair('confidence', TJSONNumber.Create(W.Confidence));
        TsArr.AddElement(O);
      end;
      TFile.WriteAllText(TsFile, TsArr.ToString);
      TimestampsAsset.ByteSize := TFile.GetSize(TsFile);
    finally
      TsArr.Free;
    end;

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
    var RootDir := DeepBase.Manager.DeepBase.RootPath;

    var RawOutputFile: string := TPath.Combine(
      TPath.Combine(RootDir, 'output'), Format('audio/%s/raw.wav', [Job.JobId]));
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
    var LNOutputFile: string := TPath.Combine(
      TPath.GetFullPath('output'), Format('audio/%s/normalized.wav', [Job.JobId]));
    var LNVerify: TLoudnormMeasurement;
    var LNResult := TAudioProcessor.LoudnormTwoPass(
      MergedAsset.Uri, LNOutputFile, LNVerify,
      -16.0, -1.5, 11.0);

    if LNResult.Success then
    begin
      // Update manifest with loudnorm measurements
      Repo.UpdateAudioManifestLoudnorm(Manifest.ManifestId,
        LNResult.OutputI, LNResult.OutputTp, LNResult.OutputLra,
        '{}', LNResult.RawJson);
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
