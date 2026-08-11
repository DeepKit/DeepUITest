unit DeepFrames.Domain.VoiceProfile;

/// <summary>
/// Voice profile management for DeepFrames audio pipeline.
///
/// Per docs/05.audio-音频流水线-audio-pipeline.md §1 音色映射:
///   - Character -> voice ID + structured emotion/pace/pitch
///   - Enum values mapped to Chinese instruction text
///   - voice_label not supported by stepaudio-2.5-tts
///   - Instruction always under 200 chars (StepFun TTS API limit)
/// </summary>

interface

type
  TTtsEmotion = (teCalm, teTense, teSad, teHappy, teAngry, teMysterious, teNeutral);
  TTtsPace = (tpSlow, tpNormal, tpFast);
  TTtsPitch = (tpHNormal, tpHHigh, tpHLow);

  TVoiceConfig = record
    CharacterName: string;
    VoiceId: string;
    DefaultEmotion: TTtsEmotion;
    DefaultPace: TTtsPace;
    DefaultPitch: TTtsPitch;
    IsClone: Boolean;
    CloneAssetId: string;
  end;

  TVoiceProfile = class
  public
    class function DefaultProfiles: TArray<TVoiceConfig>; static;
    class function FindByCharacter(const ACharacter: string;
      const AProfiles: TArray<TVoiceConfig>; out AConfig: TVoiceConfig): Boolean; static;
    class function BuildInstruction(AEmotion: TTtsEmotion; APace: TTtsPace;
      APitch: TTtsPitch): string; overload; static;
    class function BuildInstruction(const AConfig: TVoiceConfig): string; overload; static;
    class function EmotionToText(AEmotion: TTtsEmotion): string; static;
    class function PaceToText(APace: TTtsPace): string; static;
    class function PitchToText(APitch: TTtsPitch): string; static;
    class function BuiltInVoices: TArray<string>; static;
    class function IsInstructionValid(const AInstruction: string): Boolean; static;
    class function ToneToEmotion(const ATone: string): TTtsEmotion; static;
    class function BuildInstructionFromTone(const ATone: string): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TVoiceProfile.DefaultProfiles: TArray<TVoiceConfig>;
begin
  SetLength(Result, 4);
  Result[0].CharacterName := 'Narrator';
  Result[0].VoiceId := 'cixingnansheng';
  Result[0].DefaultEmotion := teCalm;
  Result[0].DefaultPace := tpSlow;
  Result[0].DefaultPitch := tpHNormal;
  Result[0].IsClone := False;

  Result[1].CharacterName := 'MainFemale';
  Result[1].VoiceId := 'wenrounvsheng';
  Result[1].DefaultEmotion := teCalm;
  Result[1].DefaultPace := tpNormal;
  Result[1].DefaultPitch := tpHNormal;
  Result[1].IsClone := False;

  Result[2].CharacterName := 'MainMale';
  Result[2].VoiceId := 'cixingnansheng';
  Result[2].DefaultEmotion := teNeutral;
  Result[2].DefaultPace := tpNormal;
  Result[2].DefaultPitch := tpHNormal;
  Result[2].IsClone := False;

  Result[3].CharacterName := 'Youth';
  Result[3].VoiceId := 'jizhiqingnian';
  Result[3].DefaultEmotion := teHappy;
  Result[3].DefaultPace := tpNormal;
  Result[3].DefaultPitch := tpHNormal;
  Result[3].IsClone := False;
end;

class function TVoiceProfile.FindByCharacter(const ACharacter: string;
  const AProfiles: TArray<TVoiceConfig>; out AConfig: TVoiceConfig): Boolean;
var
  P: TVoiceConfig;
begin
  for P in AProfiles do
    if SameText(P.CharacterName, ACharacter) then
    begin
      AConfig := P;
      Exit(True);
    end;
  if Length(AProfiles) > 0 then
  begin
    AConfig := AProfiles[0];
    Exit(True);
  end;
  AConfig.VoiceId := 'cixingnansheng';
  AConfig.DefaultEmotion := teCalm;
  AConfig.DefaultPace := tpSlow;
  AConfig.DefaultPitch := tpHNormal;
  Result := True;
end;

class function TVoiceProfile.EmotionToText(AEmotion: TTtsEmotion): string;
begin
  // Chinese instructions per docs/05.audio §1 — StepFun TTS is more stable with Chinese
  case AEmotion of
    teCalm:       Result := '平静沉稳';
    teTense:      Result := '紧张急迫';
    teSad:        Result := '低落伤感';
    teHappy:      Result := '欢快愉悦';
    teAngry:      Result := '愤怒激烈';
    teMysterious: Result := '神秘低沉';
    teNeutral:    Result := '中性平稳';
  else Result := '平静沉稳';
  end;
end;

class function TVoiceProfile.PaceToText(APace: TTtsPace): string;
begin
  case APace of
    tpSlow:   Result := '语速偏慢';
    tpNormal: Result := '正常语速';
    tpFast:   Result := '语速偏快';
  else Result := '正常语速';
  end;
end;

class function TVoiceProfile.PitchToText(APitch: TTtsPitch): string;
begin
  case APitch of
    tpHNormal: Result := '';
    tpHHigh:   Result := '音调偏高';
    tpHLow:    Result := '音调偏低';
  else Result := '';
  end;
end;

class function TVoiceProfile.BuildInstruction(AEmotion: TTtsEmotion;
  APace: TTtsPace; APitch: TTtsPitch): string;
var
  EmotionStr, PaceStr, PitchStr: string;
begin
  EmotionStr := EmotionToText(AEmotion);
  PaceStr := PaceToText(APace);
  PitchStr := PitchToText(APitch);
  Result := EmotionStr + ', ' + PaceStr;
  if PitchStr <> '' then
    Result := Result + ', ' + PitchStr;
  if Length(Result) > 200 then
    Result := Copy(Result, 1, 197) + '...';
end;

class function TVoiceProfile.BuildInstruction(const AConfig: TVoiceConfig): string;
begin
  Result := BuildInstruction(AConfig.DefaultEmotion, AConfig.DefaultPace,
    AConfig.DefaultPitch);
end;

class function TVoiceProfile.BuiltInVoices: TArray<string>;
begin
  Result := ['cixingnansheng', 'wenrounvsheng', 'jizhiqingnian'];
end;

class function TVoiceProfile.IsInstructionValid(const AInstruction: string): Boolean;
begin
  Result := Length(AInstruction) <= 200;
end;

class function TVoiceProfile.ToneToEmotion(const ATone: string): TTtsEmotion;
var LT: string;
begin
  LT := LowerCase(Trim(ATone));
  if (Pos('energetic',LT)>0) or (Pos('excited',LT)>0) or (Pos('dynamic',LT)>0) then Result := teHappy
  else if (Pos('tense',LT)>0) or (Pos('urgent',LT)>0) or (Pos('nervous',LT)>0) then Result := teTense
  else if (Pos('serious',LT)>0) or (Pos('official',LT)>0) or (Pos('solemn',LT)>0) then Result := teNeutral
  else if (Pos('warm',LT)>0) or (Pos('gentle',LT)>0) or (Pos('cozy',LT)>0) then Result := teCalm
  else if (Pos('sad',LT)>0) or (Pos('melancholy',LT)>0) then Result := teSad
  else if (Pos('angry',LT)>0) or (Pos('furious',LT)>0) then Result := teAngry
  else if (Pos('mysterious',LT)>0) or (Pos('eerie',LT)>0) then Result := teMysterious
  else Result := teCalm;
end;

class function TVoiceProfile.BuildInstructionFromTone(const ATone: string): string;
begin
  Result := BuildInstruction(ToneToEmotion(ATone), tpNormal, tpHNormal);
end;

end.