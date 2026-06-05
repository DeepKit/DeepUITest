unit DeepFrames.Workflow.AudioProcessor;

/// <summary>
/// FFmpeg-based audio processing utility for the DeepFrames audio pipeline.
///
/// Handles: WAV/PCM concat, resample (24kHz→48kHz), loudnorm two-pass.
/// All operations are external process calls to ffmpeg — no in-process audio
/// decoding in Delphi.
///
/// Loudnorm two-pass (per docs/05.audio-音频流水线-audio-pipeline.md):
///   Pass 1: measure — ffmpeg -i input.wav -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null NUL
///   Pass 2: apply — ffmpeg -i input.wav -af loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=X:... output.wav
///   Gate 3a: verify measured_lufs within ±1 of target (-16 LUFS)
/// </summary>

interface

uses
  System.JSON;

type
  /// <summary>Result of audio concatenation.</summary>
  TConcatResult = record
    Success: Boolean;
    OutputFile: string;
    DurationSec: Double;
    SampleRate: Integer;
    Channels: Integer;
    DeltaMs: Double;       // expected vs actual duration delta
    ErrorMessage: string;
  end;

  /// <summary>Result of audio resampling.</summary>
  TResampleResult = record
    Success: Boolean;
    OutputFile: string;
    FromSampleRate: Integer;
    ToSampleRate: Integer;
    OutputSizeBytes: Int64;
    DurationSec: Double;
    ErrorMessage: string;
  end;

  /// <summary>Loudnorm pass 1 (measurement) result.</summary>
  TLoudnormMeasurement = record
    Success: Boolean;
    InputI: Double;        // integrated loudness
    InputTp: Double;       // true peak
    InputLra: Double;      // loudness range
    InputThresh: Double;   // threshold
    TargetOffset: Double;  // required gain to reach target
    RawJson: string;       // full ffmpeg loudnorm JSON output
    ErrorMessage: string;
  end;

  /// <summary>Loudnorm pass 2 (apply) result.</summary>
  TLoudnormApplyResult = record
    Success: Boolean;
    OutputFile: string;
    OutputI: Double;       // measured integrated
    OutputTp: Double;      // measured true peak
    OutputLra: Double;     // measured LRA
    OutputThresh: Double;
    TargetLufs: Double;
    OutputSizeBytes: Int64;
    RawJson: string;
    ErrorMessage: string;
  end;

  /// <summary>FFmpeg-based audio processor.</summary>
  TAudioProcessor = class
  public
    /// <summary>Find ffmpeg executable. Searches PATH and common install locations.</summary>
    class function FindFFmpeg: string; static;

    /// <summary>
    /// Concatenate multiple WAV audio files into a single WAV.
    /// Uses ffmpeg concat demuxer via a temp file list.
    /// </summary>
    class function Concat(const AInputFiles: TArray<string>;
      const AOutputFile: string): TConcatResult; static;

    /// <summary>
    /// Resample an audio file to a target sample rate.
    /// Channels are also normalized to stereo (2) for downstream mixing.
    /// </summary>
    class function Resample(const AInputFile, AOutputFile: string;
      AFromRate, AToRate: Integer; AToChannels: Integer = 2): TResampleResult; static;

    /// <summary>
    /// Loudnorm pass 1: measure loudness of input file.
    /// Returns measured values for pass 2.
    /// </summary>
    class function LoudnormMeasure(const AInputFile: string;
      ATargetLufs: Double = -16.0; ATruePeakLimit: Double = -1.5;
      ALra: Double = 11.0): TLoudnormMeasurement; static;

    /// <summary>
    /// Loudnorm pass 2: apply normalization using measured values from pass 1.
    /// </summary>
    class function LoudnormApply(const AInputFile, AOutputFile: string;
      const AMeasurement: TLoudnormMeasurement;
      ATargetLufs: Double = -16.0; ATruePeakLimit: Double = -1.5;
      ALra: Double = 11.0): TLoudnormApplyResult; static;

    /// <summary>
    /// Full loudnorm pipeline: measure → apply → measure again for verification.
    /// Returns the apply result + verification measurement.
    /// </summary>
    class function LoudnormTwoPass(const AInputFile, AOutputFile: string;
      out AVerifyMeasurement: TLoudnormMeasurement;
      ATargetLufs: Double = -16.0; ATruePeakLimit: Double = -1.5;
      ALra: Double = 11.0): TLoudnormApplyResult; static;

    /// <summary>
    /// Convert FFmpeg loudnorm JSON output to a TLoudnormMeasurement.
    /// </summary>
    class function ParseLoudnormJson(const AJson: string): TLoudnormMeasurement; static;

    /// <summary>
    /// Get audio duration in seconds using ffprobe.
    /// </summary>
    class function GetDuration(const AFile: string): Double; static;

    /// <summary>
    /// Get audio file info (sample rate, channels, duration).
    /// </summary>
    class function GetFileInfo(const AFile: string;
      out ASampleRate: Integer; out AChannels: Integer;
      out ADurationSec: Double): Boolean; static;

    /// <summary>Execute an arbitrary ffmpeg command and get exit code + stdout.
    /// Used by VideoChain for video+audio mux and other non-audio FFmpeg tasks.
    /// </summary>
    class function Execute(const AArgs: string; out AStdOut: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  DeepFrames.Shared.Consts;

function RunFFmpeg(const AArgs: string; out AStdOut, AStdErr: string): Integer;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  TmpBytes: TBytes;
  CmdLine: string;
  OutStr: TStringBuilder;
  WaitRes: DWORD;
begin
  Result := -1;
  AStdOut := '';
  AStdErr := '';
  OutStr := TStringBuilder.Create;
  try
    // Create pipe for stdout capture
    Security.nLength := SizeOf(TSecurityAttributes);
    Security.bInheritHandle := True;
    Security.lpSecurityDescriptor := nil;

    if not CreatePipe(ReadPipe, WritePipe, @Security, 0) then
      Exit;

    try
      // Ensure the write end is inherited by the child process
      SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

      FillChar(StartInfo, SizeOf(TStartupInfo), 0);
      StartInfo.cb := SizeOf(TStartupInfo);
      StartInfo.hStdOutput := WritePipe;
      StartInfo.hStdError := WritePipe;
      StartInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
      StartInfo.wShowWindow := SW_HIDE;

      CmdLine := '"' + TAudioProcessor.FindFFmpeg + '" ' + AArgs;

      if CreateProcess(nil, PChar(CmdLine), nil, nil, True,
        CREATE_NO_WINDOW or NORMAL_PRIORITY_CLASS, nil, nil, StartInfo, ProcInfo) then
      begin
        try
          // Close write end so ReadFile gets EOF when process exits
          CloseHandle(WritePipe);
          WritePipe := 0;

          // Read stdout
          repeat
            WaitRes := WaitForSingleObject(ProcInfo.hProcess, 60000);
            if WaitRes = WAIT_TIMEOUT then
            begin
              TerminateProcess(ProcInfo.hProcess, 1);
              Exit;
            end;

            if PeekNamedPipe(ReadPipe, nil, 0, nil, @BytesRead, nil) and (BytesRead > 0) then
            begin
              ReadFile(ReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil);
              Buffer[BytesRead] := 0;
              SetLength(TmpBytes, BytesRead);
              Move(Buffer[0], TmpBytes[0], BytesRead);
              OutStr.Append(TEncoding.UTF8.GetString(TmpBytes));
            end;
          until WaitRes = WAIT_OBJECT_0;

          // Drain remaining
          while PeekNamedPipe(ReadPipe, nil, 0, nil, @BytesRead, nil) and (BytesRead > 0) do
          begin
            ReadFile(ReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil);
            Buffer[BytesRead] := 0;
            SetLength(TmpBytes, BytesRead);
            Move(Buffer[0], TmpBytes[0], BytesRead);
            OutStr.Append(TEncoding.UTF8.GetString(TmpBytes));
          end;

          GetExitCodeProcess(ProcInfo.hProcess, Cardinal(Result));
        finally
          CloseHandle(ProcInfo.hProcess);
          CloseHandle(ProcInfo.hThread);
        end;
      end;
    finally
      CloseHandle(ReadPipe);
      if WritePipe <> 0 then
        CloseHandle(WritePipe);
    end;
  finally
    AStdOut := OutStr.ToString;
    OutStr.Free;
  end;
end;

{ TAudioProcessor }

class function TAudioProcessor.FindFFmpeg: string;
const
  KnownPaths: array[0..3] of string = (
    'ffmpeg.exe',
    'C:\tools\ffmpeg\bin\ffmpeg.exe',
    'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
    'D:\tools\ffmpeg\bin\ffmpeg.exe'
  );
var
  I: Integer;
begin
  for I := 0 to High(KnownPaths) do
    if FileExists(KnownPaths[I]) then
      Exit(KnownPaths[I]);
  // Default: assume in PATH
  Result := 'ffmpeg';
end;

class function TAudioProcessor.Concat(const AInputFiles: TArray<string>;
  const AOutputFile: string): TConcatResult;
var
  ListFile: string;
  ListContent: TStringList;
  I: Integer;
  ExitCode: Integer;
  Output, Error: string;
begin
  Result.Success := False;
  Result.OutputFile := AOutputFile;
  Result.ErrorMessage := '';

  if Length(AInputFiles) = 0 then
  begin
    Result.ErrorMessage := 'No input files for concat';
    Exit;
  end;

  if Length(AInputFiles) = 1 then
  begin
    // Single file: just copy
    TFile.Copy(AInputFiles[0], AOutputFile, True);
    GetFileInfo(AOutputFile, Result.SampleRate, Result.Channels, Result.DurationSec);
    Result.DeltaMs := 0;
    Result.Success := True;
    Exit;
  end;

  // Write ffmpeg concat list file
  ListFile := TPath.GetTempFileName;
  ListContent := TStringList.Create;
  try
    for I := 0 to High(AInputFiles) do
      ListContent.Add(Format('file ''%s''', [AInputFiles[I]]));
    ListContent.SaveToFile(ListFile, TEncoding.UTF8);

    // Ensure output directory
    ForceDirectories(TPath.GetDirectoryName(AOutputFile));

    ExitCode := RunFFmpeg(
      Format('-f concat -safe 0 -i "%s" -c copy "%s" -y', [ListFile, AOutputFile]),
      Output, Error);

    if ExitCode = 0 then
    begin
      GetFileInfo(AOutputFile, Result.SampleRate, Result.Channels, Result.DurationSec);

      // Compute expected duration from inputs
      var ExpectedDur: Double := 0;
      for I := 0 to High(AInputFiles) do
        ExpectedDur := ExpectedDur + GetDuration(AInputFiles[I]);
      Result.DeltaMs := (Result.DurationSec - ExpectedDur) * 1000;
      Result.Success := True;
    end
    else
      Result.ErrorMessage := Format('ffmpeg concat failed (exit %d): %s', [ExitCode, Output]);
  finally
    ListContent.Free;
    if FileExists(ListFile) then
      TFile.Delete(ListFile);
  end;
end;

class function TAudioProcessor.Resample(const AInputFile, AOutputFile: string;
  AFromRate, AToRate: Integer; AToChannels: Integer): TResampleResult;
var
  ExitCode: Integer;
  Output, Error: string;
begin
  Result.Success := False;
  Result.OutputFile := AOutputFile;
  Result.FromSampleRate := AFromRate;
  Result.ToSampleRate := AToRate;
  Result.ErrorMessage := '';

  ForceDirectories(TPath.GetDirectoryName(AOutputFile));

  ExitCode := RunFFmpeg(
    Format('-i "%s" -ar %d -ac %d -sample_fmt s16 "%s" -y',
      [AInputFile, AToRate, AToChannels, AOutputFile]),
    Output, Error);

  if ExitCode = 0 then
  begin
    Result.Success := True;
    if FileExists(AOutputFile) then
    begin
      var F: TFileStream;
      try
        F := TFileStream.Create(AOutputFile, fmOpenRead or fmShareDenyWrite);
        Result.OutputSizeBytes := F.Size;
        F.Free;
      except
        Result.OutputSizeBytes := 0;
      end;
      Result.DurationSec := GetDuration(AOutputFile);
    end;
  end
  else
    Result.ErrorMessage := Format('ffmpeg resample failed (exit %d): %s', [ExitCode, Output]);
end;

class function TAudioProcessor.LoudnormMeasure(const AInputFile: string;
  ATargetLufs, ATruePeakLimit, ALra: Double): TLoudnormMeasurement;
var
  ExitCode: Integer;
  Output, Error: string;
begin
  Result.Success := False;
  Result.ErrorMessage := '';

  ExitCode := RunFFmpeg(
    Format(
      '-i "%s" -af loudnorm=I=%.1f:TP=%.1f:LRA=%.1f:print_format=json -f null NUL',
      [AInputFile, ATargetLufs, ATruePeakLimit, ALra]),
    Output, Error);

  if ExitCode = 0 then
  begin
    Result := ParseLoudnormJson(Output);
    Result.Success := True;
  end
  else
    Result.ErrorMessage := Format('loudnorm measure failed (exit %d): %s', [ExitCode, Output]);
end;

class function TAudioProcessor.LoudnormApply(const AInputFile, AOutputFile: string;
  const AMeasurement: TLoudnormMeasurement;
  ATargetLufs, ATruePeakLimit, ALra: Double): TLoudnormApplyResult;
var
  ExitCode: Integer;
  Output, Error: string;
  Args: string;
begin
  Result.Success := False;
  Result.OutputFile := AOutputFile;
  Result.TargetLufs := ATargetLufs;
  Result.ErrorMessage := '';

  ForceDirectories(TPath.GetDirectoryName(AOutputFile));

  Args := Format(
    '-i "%s" -af loudnorm=I=%.1f:TP=%.1f:LRA=%.1f:measured_I=%.2f:measured_TP=%.2f:measured_LRA=%.2f:measured_thresh=%.2f:offset=%.2f:print_format=json -ar 48000 "%s" -y',
    [AInputFile, ATargetLufs, ATruePeakLimit, ALra,
     AMeasurement.InputI, AMeasurement.InputTp, AMeasurement.InputLra,
     AMeasurement.InputThresh, AMeasurement.TargetOffset, AOutputFile]);

  ExitCode := RunFFmpeg(Args, Output, Error);

  if ExitCode = 0 then
  begin
    // Parse the output JSON to get final measurements
    var Measured := ParseLoudnormJson(Output);
    Result.OutputI := Measured.InputI;
    Result.OutputTp := Measured.InputTp;
    Result.OutputLra := Measured.InputLra;
    Result.OutputThresh := Measured.InputThresh;
    Result.RawJson := Output;

    if FileExists(AOutputFile) then
    begin
      var F: TFileStream;
      try
        F := TFileStream.Create(AOutputFile, fmOpenRead or fmShareDenyWrite);
        Result.OutputSizeBytes := F.Size;
        F.Free;
      except
        Result.OutputSizeBytes := 0;
      end;
    end;
    Result.Success := True;
  end
  else
    Result.ErrorMessage := Format('loudnorm apply failed (exit %d): %s', [ExitCode, Output]);
end;

class function TAudioProcessor.LoudnormTwoPass(const AInputFile, AOutputFile: string;
  out AVerifyMeasurement: TLoudnormMeasurement;
  ATargetLufs, ATruePeakLimit, ALra: Double): TLoudnormApplyResult;
var
  Measurement: TLoudnormMeasurement;
begin
  // Pass 1: measure
  Measurement := LoudnormMeasure(AInputFile, ATargetLufs, ATruePeakLimit, ALra);
  if not Measurement.Success then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'Loudnorm pass 1 failed: ' + Measurement.ErrorMessage;
    Exit;
  end;

  // Pass 2: apply with measured values
  Result := LoudnormApply(AInputFile, AOutputFile, Measurement,
    ATargetLufs, ATruePeakLimit, ALra);

  // Verify: measure again after pass 2
  if Result.Success and FileExists(AOutputFile) then
    AVerifyMeasurement := LoudnormMeasure(AOutputFile, ATargetLufs, ATruePeakLimit, ALra)
  else
    AVerifyMeasurement.Success := False;
end;

class function TAudioProcessor.ParseLoudnormJson(const AJson: string): TLoudnormMeasurement;
var
  Obj: TJSONObject;
  StartPos: Integer;
  JsonStr: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RawJson := AJson;

  // ffmpeg loudnorm JSON is embedded in stderr mixed with other output
  // Find the JSON block
  StartPos := Pos('{', AJson);
  if StartPos = 0 then
    Exit;

  JsonStr := Copy(AJson, StartPos, MaxInt);

  // Find the matching closing brace for the main object
  var BraceCount := 0;
  for var I := 1 to Length(JsonStr) do
  begin
    if JsonStr[I] = '{' then Inc(BraceCount)
    else if JsonStr[I] = '}' then
    begin
      Dec(BraceCount);
      if BraceCount = 0 then
      begin
        JsonStr := Copy(JsonStr, 1, I);
        Break;
      end;
    end;
  end;

  Obj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if Obj = nil then
    Exit;
  try
    Obj.TryGetValue<Double>('input_i', Result.InputI);
    Obj.TryGetValue<Double>('input_tp', Result.InputTp);
    Obj.TryGetValue<Double>('input_lra', Result.InputLra);
    Obj.TryGetValue<Double>('input_thresh', Result.InputThresh);
    Obj.TryGetValue<Double>('target_offset', Result.TargetOffset);
    Result.RawJson := JsonStr;
  finally
    Obj.Free;
  end;
end;

class function TAudioProcessor.GetDuration(const AFile: string): Double;
var
  ExitCode: Integer;
  Output, Error: string;
begin
  Result := 0;
  if not FileExists(AFile) then
    Exit;

  ExitCode := RunFFmpeg(
    Format('-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%s"',
      [AFile]),
    Output, Error);

  if ExitCode = 0 then
    TryStrToFloat(Trim(Output), Result);
end;

class function TAudioProcessor.GetFileInfo(const AFile: string;
  out ASampleRate: Integer; out AChannels: Integer;
  out ADurationSec: Double): Boolean;
var
  ExitCode: Integer;
  Output, Error: string;
  Lines: TArray<string>;
  Line: string;
begin
  Result := False;
  ASampleRate := 0;
  AChannels := 0;
  ADurationSec := 0;

  if not FileExists(AFile) then
    Exit;

  ExitCode := RunFFmpeg(
    Format('-v error -show_entries stream=sample_rate,channels,duration -of default=noprint_wrappers=1:nokey=1 "%s"',
      [AFile]),
    Output, Error);

  if ExitCode <> 0 then
    Exit;

  Lines := Output.Split([#10]);
  for Line in Lines do
  begin
    var Val := Trim(Line);
    if Val = '' then
      Continue;
    if ASampleRate = 0 then
      TryStrToInt(Val, ASampleRate)
    else if AChannels = 0 then
      TryStrToInt(Val, AChannels)
    else
      TryStrToFloat(Val, ADurationSec);
  end;
  Result := True;
end;

class function TAudioProcessor.Execute(const AArgs: string;
  out AStdOut: string): Integer;
var
  Dummy: string;
begin
  Result := RunFFmpeg(AArgs, AStdOut, Dummy);
end;

end.