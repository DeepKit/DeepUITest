unit DeepFrames.Workflow.WorkerProtocol;

/// <summary>
/// Worker protocol v0 for DeepFrames external tool processes.
///
/// Per docs/13.worker-Worker协议-worker-contract.md:
///   - Main program creates worker work directory, writes request.json,
///     launches the worker process, monitors progress.json heartbeat,
///     and reads result.json on completion.
///   - Cancel: main channel is CTRL-BREAK; cancel_file is auxiliary signal.
///   - Worker must NOT access DB1/DB2 or read shot_document directly.
///   - Partial assets from forcibly terminated workers are never registered as ready.
///
/// File contract:
///   {workdir}/request.json    — task input (main program writes)
///   {workdir}/progress.json   — heartbeat + progress % (worker writes)
///   {workdir}/result.json     — final output (worker writes on completion)
///   {workdir}/cancel          — auxiliary cancel signal file
/// </summary>

interface

uses
  System.JSON;

type
  /// <summary>Worker task type enumeration.</summary>
  TWorkerTaskType = (
    wtRender,       // HyperFrames or Remotion render
    wtTTS,          // TTS synthesis batch
    wtImageGen,     // Image generation (background, cover)
    wtSubtitle,     // Subtitle rendering
    wtFFmpeg,       // FFmpeg processing (encode, mux, concat)
    wtCustom        // Generic custom task
  );

  /// <summary>Worker request (request.json).</summary>
  TWorkerRequest = record
    TaskId: string;
    TaskType: string;          // render / tts / image_gen / subtitle / ffmpeg / custom
    InputManifest: string;     // path to compiled input manifest JSON
    OutputDir: string;
    Params: string;            // task-specific parameters JSON
    HeartbeatIntervalMs: Integer; // how often the worker should update progress (ms)
  end;

  /// <summary>Worker progress update (progress.json).</summary>
  TWorkerProgress = record
    TaskId: string;
    Status: string;            // running / done / failed / cancelled
    ProgressPercent: Integer;  // 0-100
    CurrentStep: string;
    Message: string;
    FilesProduced: TArray<string>;
    UpdatedAt: string;         // ISO 8601 timestamp
  end;

  /// <summary>Worker result (result.json).</summary>
  TWorkerResult = record
    TaskId: string;
    Success: Boolean;
    OutputFiles: TArray<string>;
    Metrics: string;           // JSON metrics blob
    ErrorMessage: string;
    DurationMs: Integer;
    CompletedAt: string;
  end;

  /// <summary>Worker protocol manager.</summary>
  TWorkerProtocol = class
  public
    /// <summary>Worker task type to string.</summary>
    class function TaskTypeToString(const ATaskType: TWorkerTaskType): string; static;

    /// <summary>String to worker task type.</summary>
    class function StringToTaskType(const AStr: string): TWorkerTaskType; static;

    /// <summary>Create a worker work directory and write request.json.</summary>
    class function CreateWorkDir(const ABaseDir, ATaskId: string): string; static;

    /// <summary>Write request.json to the work directory.</summary>
    class procedure WriteRequest(const AWorkDir: string;
      const ARequest: TWorkerRequest); static;

    /// <summary>Build request JSON from fields.</summary>
    class function BuildRequest(const ATaskId, ATaskType, AInputManifest,
      AOutputDir, AParams: string; AHeartbeatMs: Integer = 5000): TWorkerRequest; static;

    /// <summary>Serialize a worker request to JSON.</summary>
    class function RequestToJson(const AReq: TWorkerRequest): string; static;

    /// <summary>Serialize worker progress to JSON.</summary>
    class function ProgressToJson(const AProgress: TWorkerProgress): string; static;

    /// <summary>Write progress.json (heartbeat) to the work directory.
    /// Worker-side call: invoke every HeartbeatIntervalMs so the host's
    /// WaitForWorker sees a fresh mtime and does not flag heartbeat_timeout.</summary>
    class procedure WriteProgress(const AWorkDir: string;
      const AProgress: TWorkerProgress); static;

    /// <summary>Deserialize worker progress from JSON.</summary>
    class function JsonToProgress(const AJson: string): TWorkerProgress; static;

    /// <summary>Serialize worker result to JSON.</summary>
    class function ResultToJson(const AResult: TWorkerResult): string; static;

    /// <summary>Deserialize worker result from JSON.</summary>
    class function JsonToResult(const AJson: string): TWorkerResult; static;

    /// <summary>Read progress.json from work directory. Returns empty progress if not found.</summary>
    class function ReadProgress(const AWorkDir: string): TWorkerProgress; static;

    /// <summary>Read result.json from work directory.</summary>
    class function ReadResult(const AWorkDir: string; out AResult: TWorkerResult): Boolean; static;

    /// <summary>Check if cancel signal is set.</summary>
    class function IsCancelSignaled(const AWorkDir: string): Boolean; static;

    /// <summary>Signal cancellation.</summary>
    class procedure SignalCancel(const AWorkDir: string); static;

    /// <summary>Clean up work directory (delete all files).</summary>
    class procedure Cleanup(const AWorkDir: string); static;

    /// <summary>Verify that result.json is complete and valid (not partial).</summary>
    class function IsResultValid(const AWorkDir: string): Boolean; static;

    /// <summary>Launch a worker executable in its work directory.</summary>
    class function LaunchWorker(const AWorkDir, AExecutable, AArgs: string;
      out AProcessHandle: THandle; ATimeoutMs: Integer = 300000): Boolean; static;

    /// <summary>Wait for worker to finish, monitoring heartbeat and cancel signals.</summary>
    class function WaitForWorker(const AWorkDir: string; AProcessHandle: THandle;
      AHeartbeatTimeoutMs: Integer = 120000): TWorkerProgress; static;

    /// <summary>Force-terminate a worker process.</summary>
    class procedure TerminateWorker(AProcessHandle: THandle); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  Winapi.Windows,
  DeepFrames.Shared.Consts;

const
  CANCEL_FILE = 'cancel';

{ TWorkerProtocol }

class function TWorkerProtocol.TaskTypeToString(const ATaskType: TWorkerTaskType): string;
begin
  case ATaskType of
    wtRender:    Result := 'render';
    wtTTS:       Result := 'tts';
    wtImageGen:  Result := 'image_gen';
    wtSubtitle:  Result := 'subtitle';
    wtFFmpeg:    Result := 'ffmpeg';
    wtCustom:    Result := 'custom';
  else
    Result := 'custom';
  end;
end;

class function TWorkerProtocol.StringToTaskType(const AStr: string): TWorkerTaskType;
begin
  if SameText(AStr, 'render') then Result := wtRender
  else if SameText(AStr, 'tts') then Result := wtTTS
  else if SameText(AStr, 'image_gen') then Result := wtImageGen
  else if SameText(AStr, 'subtitle') then Result := wtSubtitle
  else if SameText(AStr, 'ffmpeg') then Result := wtFFmpeg
  else Result := wtCustom;
end;

class function TWorkerProtocol.CreateWorkDir(const ABaseDir, ATaskId: string): string;
begin
  Result := TPath.Combine(ABaseDir, 'work_' + ATaskId);
  ForceDirectories(Result);
end;

class procedure TWorkerProtocol.WriteRequest(const AWorkDir: string;
  const ARequest: TWorkerRequest);
var
  Json: string;
begin
  Json := RequestToJson(ARequest);
  TFile.WriteAllText(TPath.Combine(AWorkDir, 'request.json'), Json, TEncoding.UTF8);
end;

class function TWorkerProtocol.BuildRequest(const ATaskId, ATaskType,
  AInputManifest, AOutputDir, AParams: string;
  AHeartbeatMs: Integer): TWorkerRequest;
begin
  Result.TaskId := ATaskId;
  Result.TaskType := ATaskType;
  Result.InputManifest := AInputManifest;
  Result.OutputDir := AOutputDir;
  Result.Params := AParams;
  Result.HeartbeatIntervalMs := AHeartbeatMs;
end;

class function TWorkerProtocol.RequestToJson(const AReq: TWorkerRequest): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('task_id', AReq.TaskId);
    Obj.AddPair('task_type', AReq.TaskType);
    Obj.AddPair('input_manifest', AReq.InputManifest);
    Obj.AddPair('output_dir', AReq.OutputDir);
    Obj.AddPair('params', AReq.Params);
    Obj.AddPair('heartbeat_interval_ms', TJSONNumber.Create(AReq.HeartbeatIntervalMs));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TWorkerProtocol.ProgressToJson(const AProgress: TWorkerProgress): string;
var
  Obj: TJSONObject;
  FilesArr: TJSONArray;
  S: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('task_id', AProgress.TaskId);
    Obj.AddPair('status', AProgress.Status);
    Obj.AddPair('progress_percent', TJSONNumber.Create(AProgress.ProgressPercent));
    Obj.AddPair('current_step', AProgress.CurrentStep);
    Obj.AddPair('message', AProgress.Message);
    FilesArr := TJSONArray.Create;
    for S in AProgress.FilesProduced do
      FilesArr.Add(S);
    Obj.AddPair('files_produced', FilesArr);
    Obj.AddPair('updated_at', AProgress.UpdatedAt);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TWorkerProtocol.JsonToProgress(const AJson: string): TWorkerProgress;
var
  Obj: TJSONObject;
  FilesArr: TJSONArray;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Obj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Obj = nil then
    Exit;
  try
    Result.TaskId := Obj.GetValue<string>('task_id');
    Result.Status := Obj.GetValue<string>('status');
    Result.ProgressPercent := Obj.GetValue<Integer>('progress_percent');
    Result.CurrentStep := Obj.GetValue<string>('current_step');
    Result.Message := Obj.GetValue<string>('message');
    Result.UpdatedAt := Obj.GetValue<string>('updated_at');
    FilesArr := Obj.GetValue('files_produced') as TJSONArray;
    if FilesArr <> nil then
    begin
      SetLength(Result.FilesProduced, FilesArr.Count);
      for I := 0 to FilesArr.Count - 1 do
        Result.FilesProduced[I] := FilesArr.Items[I].Value;
    end;
  finally
    Obj.Free;
  end;
end;

class function TWorkerProtocol.ResultToJson(const AResult: TWorkerResult): string;
var
  Obj: TJSONObject;
  FilesArr: TJSONArray;
  S: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('task_id', AResult.TaskId);
    Obj.AddPair('success', TJSONBool.Create(AResult.Success));
    FilesArr := TJSONArray.Create;
    for S in AResult.OutputFiles do
      FilesArr.Add(S);
    Obj.AddPair('output_files', FilesArr);
    Obj.AddPair('metrics', AResult.Metrics);
    Obj.AddPair('error_message', AResult.ErrorMessage);
    Obj.AddPair('duration_ms', TJSONNumber.Create(AResult.DurationMs));
    Obj.AddPair('completed_at', AResult.CompletedAt);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TWorkerProtocol.JsonToResult(const AJson: string): TWorkerResult;
var
  Obj: TJSONObject;
  FilesArr: TJSONArray;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Obj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Obj = nil then
    Exit;
  try
    Result.TaskId := Obj.GetValue<string>('task_id');
    Result.Success := Obj.GetValue<Boolean>('success');
    Result.Metrics := Obj.GetValue<string>('metrics');
    Result.ErrorMessage := Obj.GetValue<string>('error_message');
    Result.DurationMs := Obj.GetValue<Integer>('duration_ms');
    Result.CompletedAt := Obj.GetValue<string>('completed_at');
    FilesArr := Obj.GetValue('output_files') as TJSONArray;
    if FilesArr <> nil then
    begin
      SetLength(Result.OutputFiles, FilesArr.Count);
      for I := 0 to FilesArr.Count - 1 do
        Result.OutputFiles[I] := FilesArr.Items[I].Value;
    end;
  finally
    Obj.Free;
  end;
end;

class procedure TWorkerProtocol.WriteProgress(const AWorkDir: string;
  const AProgress: TWorkerProgress);
var
  Json: string;
  FilePath: string;
begin
  FilePath := TPath.Combine(AWorkDir, 'progress.json');
  Json := ProgressToJson(AProgress);
  // Atomic-ish write: write to a temp file then rename, so the host never
  // reads a half-written progress.json (which would corrupt the heartbeat).
  TFile.WriteAllText(FilePath + '.tmp', Json, TEncoding.UTF8);
  if FileExists(FilePath) then
    TFile.Delete(FilePath);
  RenameFile(FilePath + '.tmp', FilePath);
end;

class function TWorkerProtocol.ReadProgress(const AWorkDir: string): TWorkerProgress;
var
  Json: string;
  FilePath: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  FilePath := TPath.Combine(AWorkDir, 'progress.json');
  if not FileExists(FilePath) then
    Exit;

  Json := TFile.ReadAllText(FilePath, TEncoding.UTF8);
  Result := JsonToProgress(Json);
end;

class function TWorkerProtocol.ReadResult(const AWorkDir: string;
  out AResult: TWorkerResult): Boolean;
var
  Json: string;
  FilePath: string;
begin
  Result := False;
  FilePath := TPath.Combine(AWorkDir, 'result.json');
  if not FileExists(FilePath) then
    Exit;

  Json := TFile.ReadAllText(FilePath, TEncoding.UTF8);
  AResult := JsonToResult(Json);
  Result := (AResult.TaskId <> '');
end;

class function TWorkerProtocol.IsCancelSignaled(const AWorkDir: string): Boolean;
begin
  Result := FileExists(TPath.Combine(AWorkDir, CANCEL_FILE));
end;

class procedure TWorkerProtocol.SignalCancel(const AWorkDir: string);
begin
  TFile.WriteAllText(TPath.Combine(AWorkDir, CANCEL_FILE), 'cancel');
end;

class procedure TWorkerProtocol.Cleanup(const AWorkDir: string);
begin
  if TDirectory.Exists(AWorkDir) then
    TDirectory.Delete(AWorkDir, True);
end;

class function TWorkerProtocol.IsResultValid(const AWorkDir: string): Boolean;
var
  Res: TWorkerResult;
begin
  Result := False;
  if not ReadResult(AWorkDir, Res) then
    Exit;
  // Result is valid only if: success=true, has output files, no error
  if not Res.Success then
    Exit;
  if Length(Res.OutputFiles) = 0 then
    Exit;
  if Res.ErrorMessage <> '' then
    Exit;
  Result := True;
end;

class function TWorkerProtocol.LaunchWorker(const AWorkDir, AExecutable,
  AArgs: string; out AProcessHandle: THandle; ATimeoutMs: Integer): Boolean;
var
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  CmdLine: string;
begin
  Result := False;
  AProcessHandle := 0;

  FillChar(StartInfo, SizeOf(TStartupInfo), 0);
  StartInfo.cb := SizeOf(TStartupInfo);
  StartInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartInfo.wShowWindow := SW_HIDE;

  CmdLine := Format('"%s" %s', [AExecutable, AArgs]);

  if CreateProcess(nil, PChar(CmdLine), nil, nil, False,
    CREATE_NO_WINDOW or NORMAL_PRIORITY_CLASS, nil,
    PChar(AWorkDir), StartInfo, ProcInfo) then
  begin
    CloseHandle(ProcInfo.hThread);
    AProcessHandle := ProcInfo.hProcess;
    Result := True;
  end;
end;

class function TWorkerProtocol.WaitForWorker(const AWorkDir: string;
  AProcessHandle: THandle; AHeartbeatTimeoutMs: Integer): TWorkerProgress;
var
  WaitRes: DWORD;
  LastProgressTick: TDateTime;
  ProgressFile: string;
begin
  LastProgressTick := Now;
  ProgressFile := TPath.Combine(AWorkDir, 'progress.json');

  while True do
  begin
    // Check cancel signal
    if IsCancelSignaled(AWorkDir) then
    begin
      Result.Status := 'cancelled';
      TerminateWorker(AProcessHandle);
      Exit;
    end;

    // Check heartbeat (progress.json modified time)
    if FileExists(ProgressFile) then
    begin
      LastProgressTick := TFile.GetLastWriteTime(ProgressFile);
      Result := ReadProgress(AWorkDir);

      // Worker reported completion
      if SameText(Result.Status, 'done') or SameText(Result.Status, 'failed') then
        Exit;
    end;

    // Heartbeat timeout
    if MilliSecondsBetween(Now, LastProgressTick) > AHeartbeatTimeoutMs then
    begin
      Result.Status := 'heartbeat_timeout';
      TerminateWorker(AProcessHandle);
      Exit;
    end;

    // Check process exit
    WaitRes := WaitForSingleObject(AProcessHandle, 2000); // 2s poll
    if WaitRes = WAIT_OBJECT_0 then
    begin
      // Process exited — read final progress/result
      if FileExists(ProgressFile) then
        Result := ReadProgress(AWorkDir);
      Exit;
    end;
  end;
end;

class procedure TWorkerProtocol.TerminateWorker(AProcessHandle: THandle);
begin
  if AProcessHandle <> 0 then
  begin
    TerminateProcess(AProcessHandle, 1);
    CloseHandle(AProcessHandle);
  end;
end;

end.