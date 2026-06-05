unit DeepFrames.Workflow.SubtitleEngine;

/// <summary>
/// Subtitle layout engine for DeepFrames video production.
///
/// Generates timed subtitle lines from ASR word-level timestamps,
/// with safe zone calculation, character-based line wrapping
/// for Chinese text, and export to SRT/VTT/JSON formats.
///
/// Safe zone (per docs/04.video-视频流水线-video-pipeline.md):
///   - B站 1920×1080, 16:9
///   - Bottom-center: 80% bottom margin, 10% horizontal padding each side
///   - Max chars per line: ~20 for Chinese at default font size
///   - Max 2 lines per subtitle
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Provider.Types;

type
  /// <summary>Single subtitle cue with timing and layout.</summary>
  TSubtitleCue = record
    Index: Integer;
    StartSec: Double;
    EndSec: Double;
    Text: string;
    Lines: TArray<string>;        // wrapped lines
    LineCount: Integer;
    IsSafe: Boolean;              // fits within safe zone
  end;

  /// <summary>Safe zone layout parameters for a platform.</summary>
  TSafeZone = record
    CanvasWidth: Integer;
    CanvasHeight: Integer;
    MarginBottomPercent: Double;  // 0-100, from bottom edge
    MarginHorizontalPercent: Double; // 0-100, from each side
    MaxCharsPerLine: Integer;
    MaxLines: Integer;
    FontSizePt: Integer;
  end;

  /// <summary>Subtitle export format.</summary>
  TSubtitleFormat = (sfSRT, sfVTT, sfHyperFramesTimeline);

  /// <summary>Subtitle engine.</summary>
  TSubtitleEngine = class
  public
    /// <summary>B站 1920×1080 default safe zone.</summary>
    class function BilibiliSafeZone: TSafeZone; static;

    /// <summary>Douyin (抖音) 1080×1920 vertical safe zone — larger bottom margin for UI.</summary>
    class function DouyinSafeZone: TSafeZone; static;

    /// <summary>Generic safe zone from platform dimensions.</summary>
    class function SafeZoneFor(const AWidth, AHeight: Integer;
      ABottomPct, AHorizPct: Double; AFontSize: Integer): TSafeZone; static;

    /// <summary>Build subtitle cues from ASR word-level timestamps.</summary>
    class function BuildCues(const AWords: TArray<TAsrWordTimestamp>;
      AMaxCharsPerLine: Integer = 20; AMaxLines: Integer = 2;
      AMinGapMs: Integer = 200): TArray<TSubtitleCue>; static;

    /// <summary>
    /// Group words into subtitle lines with natural splits.
    /// Chinese: character-based, punctuation-aware breaks.
    /// </summary>
    class function GroupWordsIntoLines(const AWords: TArray<TAsrWordTimestamp>;
      AMaxCharsPerLine: Integer): TArray<TArray<TAsrWordTimestamp>>; static;

    /// <summary>Check if a subtitle text fits within the safe zone.</summary>
    class function IsWithinSafeZone(const AText: string;
      const AZone: TSafeZone): Boolean; static;

    /// <summary>Export subtitle cues to SRT format string.</summary>
    class function ToSRT(const ACues: TArray<TSubtitleCue>): string; static;

    /// <summary>Export subtitle cues to WebVTT format string.</summary>
    class function ToVTT(const ACues: TArray<TSubtitleCue>): string; static;

    /// <summary>
    /// Export subtitle cues to HyperFrames timeline JSON (scene-level).
    /// One scene per cue, with subtitle layer inline.
    /// </summary>
    class function ToHyperFramesTimeline(const ACues: TArray<TSubtitleCue>;
      const AZone: TSafeZone): string; static;

    /// <summary>Format seconds as SRT timestamp (HH:MM:SS,mmm).</summary>
    class function FormatSRTTimestamp(ASec: Double): string; static;

    /// <summary>Format seconds as VTT timestamp (HH:MM:SS.mmm).</summary>
    class function FormatVTTTimestamp(ASec: Double): string; static;

    /// <summary>
    /// Split Chinese text into display lines respecting character boundaries
    /// and punctuation-aware breaks.
    /// </summary>
    class function SplitLines(const AText: string;
      AMaxCharsPerLine: Integer): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  DeepFrames.Shared.Consts;

const
  PUNCTUATION_BREAK_CHARS = '，。！？；：、,.!?;:  ～…—）】」』)]';

{ TSubtitleEngine }

class function TSubtitleEngine.BilibiliSafeZone: TSafeZone;
begin
  Result.CanvasWidth := 1920;
  Result.CanvasHeight := 1080;
  Result.MarginBottomPercent := 10.0;
  Result.MarginHorizontalPercent := 10.0;
  Result.MaxCharsPerLine := 20;
  Result.MaxLines := 2;
  Result.FontSizePt := 36;
end;

class function TSubtitleEngine.DouyinSafeZone: TSafeZone;
begin
  Result.CanvasWidth := 1080;
  Result.CanvasHeight := 1920;
  Result.MarginBottomPercent := 15.0;   // larger — UI elements (likes, comments, profile) at bottom
  Result.MarginHorizontalPercent := 5.0;
  Result.MaxCharsPerLine := 16;         // narrower canvas → fewer chars per line
  Result.MaxLines := 2;
  Result.FontSizePt := 32;
end;

class function TSubtitleEngine.SafeZoneFor(const AWidth, AHeight: Integer;
  ABottomPct, AHorizPct: Double; AFontSize: Integer): TSafeZone;
begin
  Result.CanvasWidth := AWidth;
  Result.CanvasHeight := AHeight;
  Result.MarginBottomPercent := ABottomPct;
  Result.MarginHorizontalPercent := AHorizPct;
  // Scale max chars per line by canvas width relative to 1920
  Result.MaxCharsPerLine := Round((AWidth / 1920.0) * 20);
  if Result.MaxCharsPerLine < 10 then
    Result.MaxCharsPerLine := 10;
  Result.MaxLines := 2;
  Result.FontSizePt := AFontSize;
end;

class function TSubtitleEngine.SplitLines(const AText: string;
  AMaxCharsPerLine: Integer): TArray<string>;
var
  Chars: TArray<Char>;
  LineStart, Idx, CharCount: Integer;
  LastBreakPos: Integer;
begin
  Result := nil;
  if Length(AText) = 0 then
    Exit;

  Idx := 1;
  LineStart := 1;
  CharCount := 0;
  LastBreakPos := 0;

  while Idx <= Length(AText) do
  begin
    // Track punctuation positions as natural break points
    if System.Pos(AText[Idx], PUNCTUATION_BREAK_CHARS) > 0 then
      LastBreakPos := Idx;

    Inc(CharCount);

    // Need to break
    if CharCount >= AMaxCharsPerLine then
    begin
      var BreakAt: Integer;
      if LastBreakPos > LineStart then
        BreakAt := LastBreakPos // break at punctuation
      else
        BreakAt := Idx;         // hard break at limit

      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(AText, LineStart, BreakAt - LineStart + 1).Trim;

      LineStart := BreakAt + 1;
      CharCount := Idx - LineStart + 1;
      LastBreakPos := 0;
    end;

    Inc(Idx);
  end;

  // Remaining text
  if LineStart <= Length(AText) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(AText, LineStart, MaxInt).Trim;
  end;

  // Limit to MaxLines
  if Length(Result) > 2 then
  begin
    // Join overflow lines into the last line with ellipsis
    SetLength(Result, 2);
    Result[1] := Result[1] + '…';
  end;
end;

class function TSubtitleEngine.GroupWordsIntoLines(
  const AWords: TArray<TAsrWordTimestamp>;
  AMaxCharsPerLine: Integer): TArray<TArray<TAsrWordTimestamp>>;
var
  Groups: TArray<TArray<TAsrWordTimestamp>>;
  CurrentGroup: TArray<TAsrWordTimestamp>;
  CurrentCharCount: Integer;
  I: Integer;
begin
  Result := nil;
  if Length(AWords) = 0 then
    Exit;

  SetLength(CurrentGroup, 0);
  CurrentCharCount := 0;
  SetLength(Groups, 0);

  for I := 0 to High(AWords) do
  begin
    var WordLen := Length(AWords[I].Word);
    if CurrentCharCount + WordLen > AMaxCharsPerLine then
    begin
      // Flush current group
      if Length(CurrentGroup) > 0 then
      begin
        SetLength(Groups, Length(Groups) + 1);
        Groups[High(Groups)] := CurrentGroup;
        SetLength(CurrentGroup, 0);
        CurrentCharCount := 0;
      end;
    end;

    SetLength(CurrentGroup, Length(CurrentGroup) + 1);
    CurrentGroup[High(CurrentGroup)] := AWords[I];
    Inc(CurrentCharCount, WordLen);
  end;

  // Flush remaining
  if Length(CurrentGroup) > 0 then
  begin
    SetLength(Groups, Length(Groups) + 1);
    Groups[High(Groups)] := CurrentGroup;
  end;

  Result := Groups;
end;

class function TSubtitleEngine.IsWithinSafeZone(const AText: string;
  const AZone: TSafeZone): Boolean;
var
  Lines: TArray<string>;
begin
  Lines := SplitLines(AText, AZone.MaxCharsPerLine);
  Result := Length(Lines) <= AZone.MaxLines;
end;

class function TSubtitleEngine.FormatSRTTimestamp(ASec: Double): string;
var
  H, M, S, Ms: Integer;
begin
  H := Trunc(ASec) div 3600;
  M := (Trunc(ASec) mod 3600) div 60;
  S := Trunc(ASec) mod 60;
  Ms := Trunc((ASec - Trunc(ASec)) * 1000);
  Result := Format('%.2d:%.2d:%.2d,%.3d', [H, M, S, Ms]);
end;

class function TSubtitleEngine.FormatVTTTimestamp(ASec: Double): string;
var
  H, M, S, Ms: Integer;
begin
  H := Trunc(ASec) div 3600;
  M := (Trunc(ASec) mod 3600) div 60;
  S := Trunc(ASec) mod 60;
  Ms := Trunc((ASec - Trunc(ASec)) * 1000);
  Result := Format('%.2d:%.2d:%.2d.%.3d', [H, M, S, Ms]);
end;

class function TSubtitleEngine.BuildCues(const AWords: TArray<TAsrWordTimestamp>;
  AMaxCharsPerLine, AMaxLines, AMinGapMs: Integer): TArray<TSubtitleCue>;
var
  Cues: TArray<TSubtitleCue>;
  CurrentStart: Double;
  CurrentText: string;
  CurrentCharCount: Integer;
  LastWordEnd: Double;
  I: Integer;
  GapMs: Double;
begin
  Result := nil;
  if Length(AWords) = 0 then
    Exit;

  SetLength(Cues, 0);
  CurrentStart := AWords[0].StartSec;
  CurrentText := '';
  CurrentCharCount := 0;
  LastWordEnd := AWords[0].EndSec;

  for I := 0 to High(AWords) do
  begin
    // Check for natural gap (sentence break)
    if I > 0 then
    begin
      GapMs := (AWords[I].StartSec - LastWordEnd) * 1000;
      if GapMs > AMinGapMs then
      begin
        // Flush current cue
        if CurrentCharCount > 0 then
        begin
          SetLength(Cues, Length(Cues) + 1);
          Cues[High(Cues)].Index := Length(Cues);
          Cues[High(Cues)].StartSec := CurrentStart;
          Cues[High(Cues)].EndSec := LastWordEnd;
          Cues[High(Cues)].Text := CurrentText.Trim;
          Cues[High(Cues)].Lines := SplitLines(CurrentText.Trim, AMaxCharsPerLine);
          Cues[High(Cues)].LineCount := Length(Cues[High(Cues)].Lines);
          Cues[High(Cues)].IsSafe := Cues[High(Cues)].LineCount <= AMaxLines;
        end;
        // Start new cue
        CurrentStart := AWords[I].StartSec;
        CurrentText := '';
        CurrentCharCount := 0;
      end;
    end;

    CurrentText := CurrentText + AWords[I].Word;
    Inc(CurrentCharCount, Length(AWords[I].Word));
    LastWordEnd := AWords[I].EndSec;

    // Force break if line too long
    if CurrentCharCount >= AMaxCharsPerLine * AMaxLines then
    begin
      SetLength(Cues, Length(Cues) + 1);
      Cues[High(Cues)].Index := Length(Cues);
      Cues[High(Cues)].StartSec := CurrentStart;
      Cues[High(Cues)].EndSec := LastWordEnd;
      Cues[High(Cues)].Text := CurrentText.Trim;
      Cues[High(Cues)].Lines := SplitLines(CurrentText.Trim, AMaxCharsPerLine);
      Cues[High(Cues)].LineCount := Length(Cues[High(Cues)].Lines);
      Cues[High(Cues)].IsSafe := Cues[High(Cues)].LineCount <= AMaxLines;

      CurrentStart := LastWordEnd;
      CurrentText := '';
      CurrentCharCount := 0;
    end;
  end;

  // Flush remaining
  if CurrentCharCount > 0 then
  begin
    SetLength(Cues, Length(Cues) + 1);
    Cues[High(Cues)].Index := Length(Cues);
    Cues[High(Cues)].StartSec := CurrentStart;
    Cues[High(Cues)].EndSec := LastWordEnd;
    Cues[High(Cues)].Text := CurrentText.Trim;
    Cues[High(Cues)].Lines := SplitLines(CurrentText.Trim, AMaxCharsPerLine);
    Cues[High(Cues)].LineCount := Length(Cues[High(Cues)].Lines);
    Cues[High(Cues)].IsSafe := Cues[High(Cues)].LineCount <= AMaxLines;
  end;

  Result := Cues;
end;

class function TSubtitleEngine.ToSRT(const ACues: TArray<TSubtitleCue>): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(ACues) do
    begin
      if I > 0 then
        SB.AppendLine;
      SB.AppendLine(IntToStr(ACues[I].Index));
      SB.AppendLine(FormatSRTTimestamp(ACues[I].StartSec) + ' --> ' +
        FormatSRTTimestamp(ACues[I].EndSec));
      SB.AppendLine(ACues[I].Text);
    end;
    // Append final blank line per SRT spec
    if Length(ACues) > 0 then
      SB.AppendLine;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSubtitleEngine.ToVTT(const ACues: TArray<TSubtitleCue>): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('WEBVTT');
    SB.AppendLine;
    for I := 0 to High(ACues) do
    begin
      if I > 0 then
        SB.AppendLine;
      SB.AppendLine(IntToStr(ACues[I].Index));
      SB.AppendLine(FormatVTTTimestamp(ACues[I].StartSec) + ' --> ' +
        FormatVTTTimestamp(ACues[I].EndSec));
      // Multi-line subtitles
      for var L in ACues[I].Lines do
        SB.AppendLine(L);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TSubtitleEngine.ToHyperFramesTimeline(const ACues: TArray<TSubtitleCue>;
  const AZone: TSafeZone): string;
var
  Arr: TJSONArray;
  SceneObj: TJSONObject;
  SubLayer: TJSONObject;
  Cue: TSubtitleCue;
  I: Integer;
begin
  Arr := TJSONArray.Create;
  try
    for I := 0 to High(ACues) do
    begin
      Cue := ACues[I];
      SceneObj := TJSONObject.Create;
      SceneObj.AddPair('scene_id', Format('sub_%d', [Cue.Index]));
      SceneObj.AddPair('template', 'subtitle_only');
      SceneObj.AddPair('start_sec', TJSONNumber.Create(Cue.StartSec));
      SceneObj.AddPair('end_sec', TJSONNumber.Create(Cue.EndSec));
      SceneObj.AddPair('duration_sec', TJSONNumber.Create(Cue.EndSec - Cue.StartSec));

      SubLayer := TJSONObject.Create;
      SubLayer.AddPair('type', 'subtitle');
      SubLayer.AddPair('text', Cue.Text);
      SubLayer.AddPair('position', 'bottom_center');
      SubLayer.AddPair('font_size_pt', TJSONNumber.Create(AZone.FontSizePt));
      SubLayer.AddPair('safe_zone', TJSONBool.Create(Cue.IsSafe));
      SubLayer.AddPair('line_count', TJSONNumber.Create(Cue.LineCount));

      SceneObj.AddPair('layers', TJSONObject.Create
        .AddPair('subtitle', SubLayer));
      SceneObj.AddPair('transitions', TJSONObject.Create
        .AddPair('in', 'fade')
        .AddPair('out', 'fade'));

      Arr.AddElement(SceneObj);
    end;
    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

end.