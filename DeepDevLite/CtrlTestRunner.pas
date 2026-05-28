unit CtrlTestRunner;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Threading,
  uModels, HelperFiles;

type
  TTestRunner = class
  private
    FTimeoutSec: Integer;
    function BuildRunCommand(Lang: TSourceLanguage; const ScriptPath: string): string;
    function ExecuteCommand(const Command: string; out Output: string): Integer;
    function ParseTestOutput(const Output: string): TTestResults;
  public
    constructor Create;
    
    function GenerateTestScript(const AContract: TContract;
      const SourceCode: string; ModelLevel: TAIRetryLevel): string;
    function RunTestScript(const ScriptCode: string;
      ALang: TSourceLanguage): TTestResults;
    function RunTestScriptAsync(const ScriptCode: string;
      ALang: TSourceLanguage; OnComplete: TProc<TTestResults>): ITask;
    
    property TimeoutSec: Integer read FTimeoutSec write FTimeoutSec;
  end;

function TestRunner: TTestRunner;

implementation

uses
  System.SyncObjs, {$IFDEF MSWINDOWS} Winapi.Windows, {$ENDIF}
  CtrlAIAdapter, uConstants;

var
  GTestRunner: TTestRunner = nil;

function TestRunner: TTestRunner;
begin
  if not Assigned(GTestRunner) then
    GTestRunner := TTestRunner.Create;
  Result := GTestRunner;
end;

{ TTestRunner }

constructor TTestRunner.Create;
begin
  inherited;
  FTimeoutSec := TEST_TIMEOUT_SEC;
end;

function TTestRunner.BuildRunCommand(Lang: TSourceLanguage; const ScriptPath: string): string;
begin
  case Lang of
    slPython: Result := Format('python "%s"', [ScriptPath]);
    slJavaScript: Result := Format('node "%s"', [ScriptPath]);
    slTypeScript: Result := Format('ts-node "%s"', [ScriptPath]);
    slGo: Result := Format('go run "%s"', [ScriptPath]);
    slJava: Result := Format('java "%s"', [ChangeFileExt(ScriptPath, '')]);
    slCSharp: Result := Format('dotnet script "%s"', [ScriptPath]);
    slRuby: Result := Format('ruby "%s"', [ScriptPath]);
    slPHP: Result := Format('php "%s"', [ScriptPath]);
    slSwift: Result := Format('swift "%s"', [ScriptPath]);
    slRust: Result := Format('cargo script "%s"', [ScriptPath]);
    slDart: Result := Format('dart "%s"', [ScriptPath]);
  else
    Result := '';
  end;
end;

function TTestRunner.ExecuteCommand(const Command: string; out Output: string): Integer;
{$IFDEF MSWINDOWS}
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  SecAttr: TSecurityAttributes;
  hReadPipe, hWritePipe: THandle;
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  StartTime: Cardinal;
  TimeOut: Boolean;
begin
  Result := -1;
  Output := '';
  
  SecAttr.nLength := SizeOf(TSecurityAttributes);
  SecAttr.bInheritHandle := True;
  SecAttr.lpSecurityDescriptor := nil;
  
  if not CreatePipe(hReadPipe, hWritePipe, @SecAttr, 0) then
    Exit;
  
  try
    ZeroMemory(@SI, SizeOf(TStartupInfo));
    SI.cb := SizeOf(TStartupInfo);
    SI.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := hWritePipe;
    SI.hStdError := hWritePipe;
    
    if not CreateProcess(nil, PChar('cmd /c ' + Command), nil, nil, True,
      CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      Result := GetLastError;
      Exit;
    end;
    
    CloseHandle(hWritePipe);
    hWritePipe := 0;
    
    StartTime := GetTickCount;
    TimeOut := False;
    
    while True do
    begin
      if not PeekNamedPipe(hReadPipe, nil, 0, nil, @BytesRead, nil) then
        Break;
      
      if BytesRead = 0 then
      begin
        if WaitForSingleObject(PI.hProcess, 100) = WAIT_OBJECT_0 then
          Break;
        
        if (GetTickCount - StartTime) > Cardinal(FTimeoutSec * 1000) then
        begin
          TimeOut := True;
          TerminateProcess(PI.hProcess, 1);
          Break;
        end;
        
        Continue;
      end;
      
      if ReadFile(hReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then
      begin
        Buffer[BytesRead] := #0;
        Output := Output + string(AnsiString(Buffer));
      end;
    end;
    
    if TimeOut then
    begin
      Output := Output + #13#10 + 'TIMEOUT: Process killed after ' + IntToStr(FTimeoutSec) + ' seconds';
      Result := -2;
    end
    else
    begin
      GetExitCodeProcess(PI.hProcess, DWORD(Result));
    end;
    
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
    
  finally
    CloseHandle(hReadPipe);
    if hWritePipe <> 0 then
      CloseHandle(hWritePipe);
  end;
end;
{$ELSE}
begin
  Result := -1;
  Output := 'Not implemented on this platform';
end;
{$ENDIF}

function TTestRunner.ParseTestOutput(const Output: string): TTestResults;
var
  Lines: TStringList;
  I: Integer;
  Line: string;
  SR: TScenarioResult;
begin
  Result.Clear;
  Result.RawOutput := Output;
  
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      
      if (Pos(': PASS', UpperCase(Line)) > 0) or
         (Pos(': FAIL', UpperCase(Line)) > 0) then
      begin
        SR.ID := Trim(Copy(Line, 1, Pos(':', Line) - 1));
        SR.Passed := Pos(': PASS', UpperCase(Line)) > 0;
        SR.Detail := Line;
        
        SetLength(Result.ScenarioResults, Length(Result.ScenarioResults) + 1);
        Result.ScenarioResults[High(Result.ScenarioResults)] := SR;
      end
      else if Pos('OVERALL:', UpperCase(Line)) > 0 then
      begin
        Result.OverallPassed := Pos('PASS', UpperCase(Line)) > 0;
      end;
    end;
    
    if Length(Result.ScenarioResults) = 0 then
    begin
      Result.OverallPassed := False;
    end;
    
  finally
    Lines.Free;
  end;
end;

function TTestRunner.GenerateTestScript(const AContract: TContract;
  const SourceCode: string; ModelLevel: TAIRetryLevel): string;
var
  Prompt: string;
  Response: TAIResponse;
  ContractYAML: string;
begin
  Result := '';
  
  ContractYAML := AContract.ToYAML;
  
  Prompt :=
    'Generate a runnable test script for the following ' + SourceLanguageToStr(AContract.Language) + ' code.' + #13#10 +
    #13#10 +
    'Contract to verify:' + #13#10 +
    ContractYAML + #13#10 +
    #13#10 +
    'Source code:' + #13#10 +
    '```' + SourceLanguageToStr(AContract.Language).ToLower + #13#10 +
    SourceCode + #13#10 +
    '```' + #13#10 +
    #13#10 +
    'Requirements:' + #13#10 +
    '1. Generate ONE self-contained test file' + #13#10 +
    '2. Test each scenario in the contract' + #13#10 +
    '3. Output PASS/FAIL for each scenario ID (e.g. S001: PASS)' + #13#10 +
    '4. Final line must be: OVERALL: PASS or OVERALL: FAIL' + #13#10 +
    '5. No external dependencies beyond standard library' + #13#10 +
    '6. Output ONLY the code, no explanation';

  Response := AIAdapter.CallAI(Prompt, ModelLevel);
  
  if Response.Success then
    Result := Response.Content
  else
    Result := '';
end;

function TTestRunner.RunTestScript(const ScriptCode: string;
  ALang: TSourceLanguage): TTestResults;
var
  ScriptPath: string;
  Output: string;
  ExitCode: Integer;
  Ext: string;
  StartTime: Cardinal;
begin
  Result.Clear;
  
  Ext := GetLangExt(ALang);
  if Ext = '' then
  begin
    Result.OverallPassed := False;
    Result.RawOutput := 'Unsupported language';
    Exit;
  end;
  
  ScriptPath := GetTempScriptPath(Ext);
  
  try
    if not WriteFileContent(ScriptPath, ScriptCode) then
    begin
      Result.OverallPassed := False;
      Result.RawOutput := 'Failed to write test script';
      Exit;
    end;
    
    StartTime := TThread.GetTickCount;
    ExitCode := ExecuteCommand(BuildRunCommand(ALang, ScriptPath), Output);
    Result.ExecutionMS := TThread.GetTickCount - StartTime;
    
    Result := ParseTestOutput(Output);
    
  finally
    CleanTempFile(ScriptPath);
  end;
end;

function TTestRunner.RunTestScriptAsync(const ScriptCode: string;
  ALang: TSourceLanguage; OnComplete: TProc<TTestResults>): ITask;
begin
  Result := TTask.Run(
    procedure
    var
      R: TTestResults;
    begin
      R := RunTestScript(ScriptCode, ALang);
      if Assigned(OnComplete) then
        TThread.Queue(nil, procedure begin OnComplete(R); end);
    end);
end;

end.
