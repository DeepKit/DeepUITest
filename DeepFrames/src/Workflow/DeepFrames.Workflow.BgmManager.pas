unit DeepFrames.Workflow.BgmManager;

/// <summary>
/// BGM library manager for DeepFrames audio pipeline.
///
/// Per docs/05.audio-音频流水线-audio-pipeline.md:
///   - BGM is optional, disabled by default on the first production chain.
///   - When enabled, BGM is mixed AFTER TTS + loudnorm, not before.
///   - License validation is mandatory before downstream publishing.
///
/// Features:
///   - Search by mood/genre/duration range
///   - License validation (royalty_free, creative_commons, custom)
///   - Fade in/out curve configuration
///   - Loop/one-shot selection
///   - Mix volume setting
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Domain.Types;

type
  /// <summary>Mood tags used for BGM search (genre-agnostic).</summary>
  TBgmMood = (bmCalm, bmEnergetic, bmSomber, bmSuspense, bmUplifting,
    bmMelancholic, bmEpic, bmAmbient, bmNeutral);

  /// <summary>License type constraint for downstream publishing.</summary>
  TBgmLicenseType = (blRoyaltyFree, blCreativeCommons, blCustom, blUnknown);

  /// <summary>BGM fade configuration.</summary>
  TBgmFadeConfig = record
    FadeInSec: Double;
    FadeOutSec: Double;
    FadeInCurve: string;   // 'linear', 'logarithmic', 'exponential'
    FadeOutCurve: string;
  end;

  /// <summary>BGM mix configuration.</summary>
  TBgmMixConfig = record
    TrackId: string;
    Volume: Double;        // 0.0 = silent, 1.0 = full
    StartOffsetSec: Double; // delay before BGM starts
    LoopEnabled: Boolean;
    FadeConfig: TBgmFadeConfig;
    LicenseType: TBgmLicenseType;
    LicenseUri: string;
  end;

  /// <summary>BGM search query.</summary>
  TBgmSearchQuery = record
    Mood: TBgmMood;
    Genre: string;
    MinDurationSec: Double;
    MaxDurationSec: Double;
    BpmMin: Integer;
    BpmMax: Integer;
    LicenseTypes: TArray<TBgmLicenseType>; // empty = any
  end;

  /// <summary>BGM track with full metadata.</summary>
  TBgmTrackInfo = record
    Track: TBgmTrack;
    LibraryName: string;
    Moods: TArray<string>;
    LicenseType: TBgmLicenseType;
    function DurationStr: string;
  end;

  /// <summary>BGM library manager.</summary>
  TBgmManager = class
  public
    /// <summary>Mood enum to string tag.</summary>
    class function MoodToStr(AMood: TBgmMood): string; static;

    /// <summary>String tag to mood enum.</summary>
    class function StrToMood(const AStr: string): TBgmMood; static;

    /// <summary>License type from string.</summary>
    class function LicenseFromStr(const AStr: string): TBgmLicenseType; static;

    /// <summary>License type to string.</summary>
    class function LicenseToStr(ALicense: TBgmLicenseType): string; static;

    /// <summary>Is the license valid for platform publishing?</summary>
    class function IsLicenseValidForPublishing(ALicense: TBgmLicenseType;
      const APlatform: string): Boolean; static;

    /// <summary>Default fade config (1s fade in, 2s fade out, linear).</summary>
    class function DefaultFadeConfig: TBgmFadeConfig; static;

    /// <summary>
    /// Match a BGM track against a search query.
    /// Returns True if the track matches.
    /// </summary>
    class function MatchTrack(const ATrack: TBgmTrack;
      const AQuery: TBgmSearchQuery): Boolean; static;

    /// <summary>
    /// Select the best matching BGM track from a list.
    /// Preferred: exact mood + genre match, closest duration.
    /// </summary>
    class function SelectBestTrack(const ATracks: TArray<TBgmTrack>;
      const AQuery: TBgmSearchQuery): TBgmTrack; static;

    /// <summary>
    /// Build a BGM mix config from a track with reasonable defaults.
    /// </summary>
    class function BuildMixConfig(const ATrack: TBgmTrack;
      ADurationSec: Double; AVolume: Double = 0.3): TBgmMixConfig; static;

    /// <summary>
    /// Compute FFmpeg amix parameters for BGM overlay.
    /// Returns the filter_complex string for ffmpeg.
    /// </summary>
    class function BuildFFmpegBgmFilter(const AMainAudioUri, ABgmUri: string;
      const AConfig: TBgmMixConfig; AMainDurationSec: Double): string; static;

    /// <summary>All supported moods.</summary>
    class function SupportedMoods: TArray<string>; static;

    /// <summary>Compatible moods — which moods pair well together.</summary>
    class function CompatibleMoods(AMood: TBgmMood): TArray<TBgmMood>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  DeepFrames.Shared.Consts;

{ TBgmTrackInfo }

function TBgmTrackInfo.DurationStr: string;
begin
  Result := Format('%.1fs', [Track.DurationSec]);
end;

{ TBgmManager }

class function TBgmManager.MoodToStr(AMood: TBgmMood): string;
begin
  case AMood of
    bmCalm:        Result := 'calm';
    bmEnergetic:   Result := 'energetic';
    bmSomber:      Result := 'somber';
    bmSuspense:    Result := 'suspense';
    bmUplifting:   Result := 'uplifting';
    bmMelancholic: Result := 'melancholic';
    bmEpic:        Result := 'epic';
    bmAmbient:     Result := 'ambient';
    bmNeutral:     Result := 'neutral';
  else Result := 'neutral';
  end;
end;

class function TBgmManager.StrToMood(const AStr: string): TBgmMood;
begin
  if SameText(AStr, 'calm') then Result := bmCalm
  else if SameText(AStr, 'energetic') then Result := bmEnergetic
  else if SameText(AStr, 'somber') then Result := bmSomber
  else if SameText(AStr, 'suspense') then Result := bmSuspense
  else if SameText(AStr, 'uplifting') then Result := bmUplifting
  else if SameText(AStr, 'melancholic') then Result := bmMelancholic
  else if SameText(AStr, 'epic') then Result := bmEpic
  else if SameText(AStr, 'ambient') then Result := bmAmbient
  else Result := bmNeutral;
end;

class function TBgmManager.LicenseFromStr(const AStr: string): TBgmLicenseType;
begin
  if SameText(AStr, BGM_LICENSE_ROYALTY_FREE) then Result := blRoyaltyFree
  else if SameText(AStr, BGM_LICENSE_CREATIVE_COMMONS) then Result := blCreativeCommons
  else if SameText(AStr, BGM_LICENSE_CUSTOM) then Result := blCustom
  else Result := blUnknown;
end;

class function TBgmManager.LicenseToStr(ALicense: TBgmLicenseType): string;
begin
  case ALicense of
    blRoyaltyFree:     Result := BGM_LICENSE_ROYALTY_FREE;
    blCreativeCommons: Result := BGM_LICENSE_CREATIVE_COMMONS;
    blCustom:          Result := BGM_LICENSE_CUSTOM;
  else Result := 'unknown';
  end;
end;

class function TBgmManager.IsLicenseValidForPublishing(
  ALicense: TBgmLicenseType; const APlatform: string): Boolean;
begin
  // Royalty-free: valid everywhere
  if ALicense = blRoyaltyFree then
    Exit(True);

  // Creative Commons: valid for non-commercial platforms (bilibili ok, youtube needs attribution)
  if ALicense = blCreativeCommons then
    Exit(SameText(APlatform, PLATFORM_BILIBILI) or
      SameText(APlatform, PLATFORM_WECHAT_VIDEO) or
      SameText(APlatform, PLATFORM_DOUYIN));

  // Custom: valid only if license_uri is present
  if ALicense = blCustom then
    Exit(True); // caller must verify license_uri

  Result := False;
end;

class function TBgmManager.DefaultFadeConfig: TBgmFadeConfig;
begin
  Result.FadeInSec := 1.0;
  Result.FadeOutSec := 2.0;
  Result.FadeInCurve := 'linear';
  Result.FadeOutCurve := 'linear';
end;

class function TBgmManager.SupportedMoods: TArray<string>;
begin
  Result := ['calm', 'energetic', 'somber', 'suspense', 'uplifting',
    'melancholic', 'epic', 'ambient', 'neutral'];
end;

class function TBgmManager.CompatibleMoods(AMood: TBgmMood): TArray<TBgmMood>;
begin
  case AMood of
    bmCalm:        Result := [bmCalm, bmAmbient, bmUplifting, bmNeutral];
    bmEnergetic:   Result := [bmEnergetic, bmUplifting, bmEpic];
    bmSomber:      Result := [bmSomber, bmMelancholic, bmAmbient];
    bmSuspense:    Result := [bmSuspense, bmSomber, bmAmbient];
    bmUplifting:   Result := [bmUplifting, bmEnergetic, bmCalm, bmEpic];
    bmMelancholic: Result := [bmMelancholic, bmSomber, bmAmbient];
    bmEpic:        Result := [bmEpic, bmUplifting, bmEnergetic];
    bmAmbient:     Result := [bmAmbient, bmCalm, bmSomber, bmNeutral];
    bmNeutral:     Result := [bmNeutral, bmCalm, bmAmbient];
  end;
end;

class function TBgmManager.MatchTrack(const ATrack: TBgmTrack;
  const AQuery: TBgmSearchQuery): Boolean;
var
  MoodsArr: TJSONArray;
  I: Integer;
  TrackMood: string;
  QueryMoodStr: string;
begin
  // Mood matching
  QueryMoodStr := MoodToStr(AQuery.Mood);
  MoodsArr := TJSONObject.ParseJSONValue(ATrack.MoodTagsJson) as TJSONArray;
  if MoodsArr <> nil then
  try
    Result := False;
    for I := 0 to MoodsArr.Count - 1 do
    begin
      TrackMood := MoodsArr.Items[I].Value;
      if SameText(TrackMood, QueryMoodStr) then
      begin
        Result := True;
        Break;
      end;
    end;
    if not Result then Exit(False);
  finally
    MoodsArr.Free;
  end
  else
    Exit(False);

  // Genre filtering
  if (AQuery.Genre <> '') and not SameText(ATrack.Genre, AQuery.Genre) then
    Exit(False);

  // Duration range
  if (AQuery.MinDurationSec > 0) and (ATrack.DurationSec < AQuery.MinDurationSec) then
    Exit(False);
  if (AQuery.MaxDurationSec > 0) and (ATrack.DurationSec > AQuery.MaxDurationSec) then
    Exit(False);

  // BPM range
  if (AQuery.BpmMin > 0) and (ATrack.Bpm < AQuery.BpmMin) then
    Exit(False);
  if (AQuery.BpmMax > 0) and (ATrack.Bpm > AQuery.BpmMax) then
    Exit(False);

  // License filter
  if Length(AQuery.LicenseTypes) > 0 then
  begin
    var TrackLicense := LicenseFromStr(ATrack.LicenseType);
    Result := False;
    for var Lic in AQuery.LicenseTypes do
      if Lic = TrackLicense then
      begin
        Result := True;
        Break;
      end;
    if not Result then Exit(False);
  end;

  Result := True;
end;

class function TBgmManager.SelectBestTrack(const ATracks: TArray<TBgmTrack>;
  const AQuery: TBgmSearchQuery): TBgmTrack;
var
  BestScore: Double;
  BestTrack: TBgmTrack;
  Score: Double;
  I: Integer;
begin
  BestScore := -1;
  BestTrack := Default(TBgmTrack);

  for I := 0 to High(ATracks) do
    if MatchTrack(ATracks[I], AQuery) then
    begin
      // Score: exact mood + genre match = higher, closer duration = higher
      Score := 0;

      var MoodsArr := TJSONObject.ParseJSONValue(ATracks[I].MoodTagsJson) as TJSONArray;
      if MoodsArr <> nil then
      try
        if MoodsArr.Count = 1 then
          Score := Score + 2.0; // exact single mood match
      finally
        MoodsArr.Free;
      end;

      if SameText(ATracks[I].Genre, AQuery.Genre) and (AQuery.Genre <> '') then
        Score := Score + 3.0;

      // Duration closeness bonus (prefer slightly longer than needed for looping)
      if (AQuery.MinDurationSec > 0) then
        Score := Score + 1.0 / (1.0 + Abs(ATracks[I].DurationSec - AQuery.MinDurationSec));

      if Score > BestScore then
      begin
        BestScore := Score;
        BestTrack := ATracks[I];
      end;
    end;

  Result := BestTrack;
end;

class function TBgmManager.BuildMixConfig(const ATrack: TBgmTrack;
  ADurationSec: Double; AVolume: Double): TBgmMixConfig;
begin
  Result.TrackId := ATrack.TrackId;
  Result.Volume := AVolume;
  Result.StartOffsetSec := 0;
  Result.LoopEnabled := ATrack.DurationSec < ADurationSec; // loop if shorter than main
  Result.FadeConfig := DefaultFadeConfig;
  Result.FadeConfig.FadeInSec := ATrack.FadeInSec;
  Result.FadeConfig.FadeOutSec := ATrack.FadeOutSec;
  Result.LicenseType := LicenseFromStr(ATrack.LicenseType);
  Result.LicenseUri := ATrack.LicenseUri;
end;

class function TBgmManager.BuildFFmpegBgmFilter(const AMainAudioUri,
  ABgmUri: string; const AConfig: TBgmMixConfig;
  AMainDurationSec: Double): string;
var
  Filter: string;
  BgmInput: string;
begin
  // FFmpeg filter_complex for BGM mixing:
  // 1. Trim BGM to match main duration (or loop it)
  // 2. Apply fade in/out
  // 3. Adjust volume
  // 4. Delay by start_offset
  // 5. Mix with main audio

  if AConfig.LoopEnabled then
    BgmInput := Format('[1:a]aloop=loop=-1:size=2e9,atrim=0:%.3f[bgm_trimmed]',
      [AMainDurationSec])
  else
    BgmInput := Format('[1:a]atrim=0:%.3f[bgm_trimmed]', [AMainDurationSec]);

  Filter := Format(
    '%s;' +
    '[bgm_trimmed]afade=t=in:d=%.3f:curve=%s,afade=t=out:st=%.3f:d=%.3f:curve=%s,' +
    'volume=%.2f,adelay=%d|%d[bgm_processed];' +
    '[0:a][bgm_processed]amix=inputs=2:duration=first:dropout_transition=2[out]',
    [BgmInput,
     AConfig.FadeConfig.FadeInSec, AConfig.FadeConfig.FadeInCurve,
     AMainDurationSec - AConfig.FadeConfig.FadeOutSec, AConfig.FadeConfig.FadeOutSec,
     AConfig.FadeConfig.FadeOutCurve,
     AConfig.Volume,
     Round(AConfig.StartOffsetSec * 1000), Round(AConfig.StartOffsetSec * 1000)]);

  Result := Filter;
end;

end.