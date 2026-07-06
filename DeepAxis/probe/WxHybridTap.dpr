program WxHybridTap;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.DateUtils,
  System.Generics.Collections, System.Hash, System.JSON,
  Winapi.Windows, Winapi.ShellAPI, Winapi.TlHelp32;

function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL;
  dwThreadId: DWORD): THandle; stdcall; external kernel32;

const
  PAGE_SZ = 4096;
  KEY_SIZE = 32;
  HMAC_SHA512_SIZE = 64;
  RESERVE_SIZE = 80;

  // From bugfix.md — verified static analysis of Weixin.dll 4.1.10.30-53
  RVA_HYBRID_ECDH_DECRYPT   = $0DEE300;
  RVA_AES_GCM_DECRYPT       = $29F3520;
  RVA_UNCOMPRESSED_OUTPUT   = $29F3BEE;
  RVA_SQLCIPHER_KEY_DBNAME  = $984BDDA0;
  RVA_SQLCIPHER_KEY_DBINDEX = $984BDB00;
  RVA_SQLCIPHER_CODEC_KEY   = $9671C380;

type
  TBreakpoint = record
    Name: string;
    Rva: UInt64;
    AbsAddr: UInt64;
    OriginalByte: Byte;
    Hit: Boolean;
  end;

  TDBFile = record
    RelPath: string;
    AbsPath: string;
    Page1: TBytes;
  end;

  TKeyMatch = record
    RelPath: string;
    KeyHex: string;
    SaltHex: string;
  end;

var
  GTimeoutMs: Integer = 90000;
  GDumpDir: string = '';

function HexToBytes(const AHex: string): TBytes;
var I, L: Integer;
begin
  L := Length(AHex) div 2;
  SetLength(Result, L);
  for I := 0 to L - 1 do
    Result[I] := Byte(StrToInt('$' + Copy(AHex, I * 2 + 1, 2)));
end;

function BytesToHex(const AData: TBytes): string;
var I: Integer;
begin
  Result := '';
  for I := 0 to Length(AData) - 1 do
    Result := Result + IntToHex(AData[I], 2);
end;

function ReadProcMem(AHandle: THandle; AAddr: UInt64; ASize: Integer): TBytes;
var LRead: SIZE_T;
begin
  SetLength(Result, ASize);
  if not ReadProcessMemory(AHandle, Pointer(NativeUInt(AAddr)), @Result[0], ASize, LRead) then
    Exit(nil);
  SetLength(Result, LRead);
end;

function VerifyKeyBytes(const AKey: TBytes; const APage1: TBytes): Boolean;
var
  LSalt, LMacSalt, LData, LStoredHmac: TBytes;
  LSHA: THashSHA2;
  LKeyStr: string;
  LDataStr: string;
  LMacKey: TBytes;
  I: Integer;
  LPageNum: Cardinal;
  LHMAC: TBytes;
begin
  Result := False;
  if (Length(AKey) <> KEY_SIZE) or (Length(APage1) < PAGE_SZ) then Exit;

  LSalt := Copy(APage1, 0, 16);
  SetLength(LMacSalt, 16);
  for I := 0 to 15 do LMacSalt[I] := LSalt[I] xor $3A;

  // PBKDF2-HMAC-SHA512(AKey, MacSalt, 2 iters) → 32B MAC key
  LKeyStr := TEncoding.UTF8.GetString(AKey);
  LMacKey := THashSHA2.GetHMACAsBytes(
    TEncoding.UTF8.GetString(LMacSalt), LKeyStr, THashSHA2.TSHA2Version.SHA512);
  SetLength(LMacKey, KEY_SIZE);

  // HMAC data = page1[16 : PAGE_SZ - RESERVE_SIZE + 16] = page1[16 : 4032]
  LData := Copy(APage1, 16, PAGE_SZ - RESERVE_SIZE);

  // Stored HMAC = page1[PAGE_SZ - 64 : PAGE_SZ]
  LStoredHmac := Copy(APage1, PAGE_SZ - HMAC_SHA512_SIZE, HMAC_SHA512_SIZE);

  // Compute HMAC(mac_key, data || page_num_LE)
  LPageNum := 1;
  var LFullData: TBytes;
  SetLength(LFullData, Length(LData) + 4);
  Move(LData[0], LFullData[0], Length(LData));
  Move(LPageNum, LFullData[Length(LData)], 4);

  LDataStr := TEncoding.UTF8.GetString(LFullData);
  LHMAC := THashSHA2.GetHMACAsBytes(
    LDataStr, TEncoding.UTF8.GetString(LMacKey), THashSHA2.TSHA2Version.SHA512);

  Result := CompareMem(@LHMAC[0], @LStoredHmac[0], HMAC_SHA512_SIZE);
end;

function ScanBufferForKey(const ABuf: TBytes; const ADBFiles: TArray<TDBFile>;
  var AFoundKeys: TDictionary<string, TKeyMatch>): Integer;
var
  LI, LJ: Integer;
  LCandidate: TBytes;
  LDB: TDBFile;
  LKey: TKeyMatch;
  LUnique: Integer;
  LSeen: array[0..255] of Boolean;
  LSaltHex: string;
begin
  Result := 0;
  if Length(ABuf) < 32 then Exit;

  for LI := 0 to Length(ABuf) - 32 do
  begin
    if LI mod 8 <> 0 then Continue;
    LCandidate := Copy(ABuf, LI, 32);

    LUnique := 0;
    FillChar(LSeen, SizeOf(LSeen), 0);
    for LJ := 0 to 31 do
      if not LSeen[LCandidate[LJ]] then
      begin
        LSeen[LCandidate[LJ]] := True;
        Inc(LUnique);
      end;
    if LUnique < 20 then Continue;

    for LDB in ADBFiles do
    begin
      LSaltHex := BytesToHex(Copy(LDB.Page1, 0, 16));
      if AFoundKeys.ContainsKey(LSaltHex) then Continue;
      if VerifyKeyBytes(LCandidate, LDB.Page1) then
      begin
        LKey.RelPath := LDB.RelPath;
        LKey.KeyHex := BytesToHex(LCandidate);
        LKey.SaltHex := LSaltHex;
        AFoundKeys.Add(LSaltHex, LKey);
        WriteLn(Format('  KEY: %s = %s', [LDB.RelPath, LKey.KeyHex]));
        Inc(Result);
      end;
    end;
  end;
end;

function FindWeChatProcess: Cardinal;
var LSnap: THandle; LEntry: TProcessEntry32;
begin
  Result := 0;
  LSnap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if LSnap = INVALID_HANDLE_VALUE then Exit;
  LEntry.dwSize := SizeOf(LEntry);
  if Process32First(LSnap, LEntry) then
    repeat
      if SameText(LEntry.szExeFile, 'Weixin.exe') then
      begin Result := LEntry.th32ProcessID; Break; end;
    until not Process32Next(LSnap, LEntry);
  CloseHandle(LSnap);
end;

function FindWeixinDllBase(APid: Cardinal): UInt64;
var LSnap: THandle; LEntry: TModuleEntry32;
begin
  Result := 0;
  LSnap := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, APid);
  if LSnap = INVALID_HANDLE_VALUE then Exit;
  LEntry.dwSize := SizeOf(LEntry);
  if Module32First(LSnap, LEntry) then
    repeat
      if SameText(LEntry.szModule, 'Weixin.dll') then
      begin Result := UInt64(LEntry.modBaseAddr); Break; end;
    until not Module32Next(LSnap, LEntry);
  CloseHandle(LSnap);
end;

procedure CollectDBFiles(const ADataDir: string; out AFiles: TArray<TDBFile>);
var
  LFiles: TArray<string>;
  LFile: string;
  LDB: TDBFile;
  LStream: TFileStream;
begin
  SetLength(AFiles, 0);
  if not TDirectory.Exists(ADataDir) then Exit;
  LFiles := TDirectory.GetFiles(ADataDir, '*.db', TSearchOption.soAllDirectories);
  for LFile in LFiles do
  begin
    if LFile.Contains('-wal') or LFile.Contains('-shm') then Continue;
    LStream := TFileStream.Create(LFile, fmOpenRead or fmShareDenyNone);
    try
      if LStream.Size < PAGE_SZ then Continue;
      LDB.RelPath := LFile.Replace(ADataDir + '\', '').Replace('\', '/');
      LDB.AbsPath := LFile;
      SetLength(LDB.Page1, PAGE_SZ);
      LStream.Read(LDB.Page1[0], PAGE_SZ);
      SetLength(AFiles, Length(AFiles) + 1);
      AFiles[High(AFiles)] := LDB;
    finally
      LStream.Free;
    end;
  end;
end;

function FindWeChatDataDir: string;
var LBase: string; LDirs: TArray<string>; LDir: string;
begin
  LBase := 'D:\xwechat_files';
  if TDirectory.Exists(LBase) then
  begin
    LDirs := TDirectory.GetDirectories(LBase, 'db_storage', TSearchOption.soAllDirectories);
    for LDir in LDirs do Exit(LDir);
  end;
  Result := '';
end;

function SaveResults(const AFoundKeys: TDictionary<string, TKeyMatch>;
  const ADumpDir: string): Boolean;
var LJSON: TJSONObject; LEntry: TJSONObject; LKey: TKeyMatch; LPath: string;
begin
  Result := False;
  if AFoundKeys.Count = 0 then Exit;
  LJSON := TJSONObject.Create;
  try
    for LKey in AFoundKeys.Values do
    begin
      LEntry := TJSONObject.Create;
      LEntry.AddPair('enc_key', LKey.KeyHex);
      LEntry.AddPair('salt', LKey.SaltHex);
      LJSON.AddPair(LKey.RelPath, LEntry);
    end;
    LPath := TPath.Combine(ADumpDir, 'all_keys.json');
    TFile.WriteAllText(LPath, LJSON.ToJSON, TEncoding.UTF8);
    WriteLn(Format('Saved %d keys to %s', [AFoundKeys.Count, LPath]));
    Result := True;
  finally
    LJSON.Free;
  end;
end;

procedure ParseArgs;
var I: Integer; LArg: string;
begin
  for I := 1 to ParamCount do
  begin
    LArg := ParamStr(I);
    if LArg.StartsWith('--timeout-ms=') then
      GTimeoutMs := StrToIntDef(LArg.Substring(13), 90000)
    else if LArg.StartsWith('--dump-dir=') then
      GDumpDir := LArg.Substring(11)
    else if LArg = '--help' then
    begin
      WriteLn('DeepAxis WxHybridTap v2.0');
      WriteLn('Usage: WxHybridTap.exe [--timeout-ms=<ms>] [--dump-dir=<path>]');
      Halt(0);
    end;
  end;
  if GDumpDir = '' then
    GDumpDir := TPath.Combine(TPath.GetTempPath, 'DeepAxisWxHybridTap');
end;

// ── Main ─────────────────────────────────────────────────────────

var
  LDataDir, LDumpDir: string;
  LDBFiles: TArray<TDBFile>;
  LFoundKeys: TDictionary<string, TKeyMatch>;
  LPid: Cardinal;
  LDllBase: UInt64;
  LProcHandle: THandle;
  LBreakpoints: array[0..5] of TBreakpoint;
  LBPNames: array[0..5] of string;
  LBPOffsets: array[0..5] of UInt64;
  LStartTime: TDateTime;
  LEvent: TDebugEvent;
  LContinue: DWORD;
  LTh: THandle;
  LCtx: TContext;
  LMem: TBytes;
  LI, LJ: Integer;
  LHit: Integer;
  LOrig: Byte;
  LWritten: SIZE_T;
  LInt3: Byte;
  LMs: Integer;
  LExcAddr: UInt64;
  LExcCode: DWORD;
  LFoundIdx: Integer;
  LDebugWait: BOOL;
  LWeChatPath: string;
begin
  ParseArgs;

  WriteLn('DeepAxis WxHybridTap v2.0');
  WriteLn('  Timeout: ', GTimeoutMs, 'ms  Dump: ', GDumpDir);
  WriteLn('');

  LDataDir := FindWeChatDataDir;
  if LDataDir <> '' then
  begin
    WriteLn('[1/7] Collecting DB files from: ', LDataDir);
    CollectDBFiles(LDataDir, LDBFiles);
    WriteLn(Format('  Found %d DB files', [Length(LDBFiles)]));
  end
  else
    WriteLn('WARNING: No WeChat data dir found');

  WriteLn('[2/7] Killing WeChat...');
  LPid := FindWeChatProcess;
  if LPid <> 0 then
  begin
    LProcHandle := OpenProcess(PROCESS_TERMINATE, False, LPid);
    if LProcHandle <> 0 then
    begin
      TerminateProcess(LProcHandle, 0);
      CloseHandle(LProcHandle);
      Sleep(3000);
    end;
  end;
  WriteLn('  Done');

  WriteLn('[3/7] Launching WeChat...');
  LWeChatPath := 'D:\Program Files\Tencent\Weixin\Weixin.exe';
  if not TFile.Exists(LWeChatPath) then
    LWeChatPath := 'C:\Program Files\Tencent\WeChat\Weixin.exe';
  if not TFile.Exists(LWeChatPath) then
  begin
    WriteLn('ERROR: Weixin.exe not found');
    ReadLn; Exit;
  end;
  ShellExecute(0, 'open', PChar(LWeChatPath), nil, nil, SW_SHOW);

  WriteLn('[4/7] Waiting for Weixin.dll...');
  LPid := 0; LDllBase := 0;
  LStartTime := Now;
  while SecondsBetween(Now, LStartTime) < 60 do
  begin
    LPid := FindWeChatProcess;
    if LPid <> 0 then
    begin
      LDllBase := FindWeixinDllBase(LPid);
      if LDllBase <> 0 then Break;
    end;
    Sleep(200);
  end;
  if (LPid = 0) or (LDllBase = 0) then
  begin
    WriteLn('ERROR: Weixin.dll not found');
    ReadLn; Exit;
  end;
  WriteLn(Format('  PID=%d, DLL=0x%x', [LPid, LDllBase]));

  WriteLn('[5/7] Attaching debugger + setting breakpoints...');
  if not DebugActiveProcess(LPid) then
  begin
    WriteLn(Format('ERROR: DebugActiveProcess failed (0x%x)', [GetLastError]));
    ReadLn; Exit;
  end;

  LProcHandle := OpenProcess(PROCESS_ALL_ACCESS, False, LPid);
  if LProcHandle = 0 then
  begin
    WriteLn('ERROR: OpenProcess failed');
    DebugActiveProcessStop(LPid);
    ReadLn; Exit;
  end;

  LBPNames[0] := 'HybridEcdhDecrypt';     LBPOffsets[0] := RVA_HYBRID_ECDH_DECRYPT;
  LBPNames[1] := 'AesGcmDecrypt';          LBPOffsets[1] := RVA_AES_GCM_DECRYPT;
  LBPNames[2] := 'UncompressedOutput';     LBPOffsets[2] := RVA_UNCOMPRESSED_OUTPUT;
  LBPNames[3] := 'SQLCipherKeyDbName';     LBPOffsets[3] := RVA_SQLCIPHER_KEY_DBNAME;
  LBPNames[4] := 'SQLCipherKeyDbIndex';    LBPOffsets[4] := RVA_SQLCIPHER_KEY_DBINDEX;
  LBPNames[5] := 'SQLCipherCodecKey';      LBPOffsets[5] := RVA_SQLCIPHER_CODEC_KEY;

  for LI := 0 to 5 do
  begin
    LBreakpoints[LI].Name := LBPNames[LI];
    LBreakpoints[LI].Rva := LBPOffsets[LI];
    LBreakpoints[LI].AbsAddr := LDllBase + LBPOffsets[LI];
    LBreakpoints[LI].Hit := False;

    LMem := ReadProcMem(LProcHandle, LBreakpoints[LI].AbsAddr, 1);
    if LMem = nil then
    begin
      WriteLn(Format('  SKIP %s (unreadable)', [LBPNames[LI]]));
      Continue;
    end;
    LBreakpoints[LI].OriginalByte := LMem[0];

    LInt3 := $CC;
    WriteProcessMemory(LProcHandle, Pointer(NativeUInt(LBreakpoints[LI].AbsAddr)),
      @LInt3, 1, LWritten);
    FlushInstructionCache(LProcHandle, Pointer(NativeUInt(LBreakpoints[LI].AbsAddr)), 1);
    WriteLn(Format('  BP: %s @ 0x%x', [LBPNames[LI], LBreakpoints[LI].AbsAddr]));
  end;

  WriteLn('');
  WriteLn('[6/7] Waiting for breakpoints — SCAN QR CODE NOW');
  WriteLn(Format('  Timeout: %d seconds', [GTimeoutMs div 1000]));
  WriteLn('');

  LFoundKeys := TDictionary<string, TKeyMatch>.Create;
  try
    LHit := 0;
    LStartTime := Now;

    while True do
    begin
      LMs := MilliSecondsBetween(Now, LStartTime);
      if LMs >= GTimeoutMs then
      begin
        WriteLn(Format('Timeout after %d ms', [LMs]));
        Break;
      end;

      LDebugWait := WaitForDebugEvent(LEvent, 1000);
      if not LDebugWait then
      begin
        if (LMs mod 15000 < 1000) and (LMs > 0) then
          WriteLn(Format('  [%ds] hits=%d keys=%d', [LMs div 1000, LHit, LFoundKeys.Count]));
        Continue;
      end;

      LContinue := DBG_CONTINUE;

      if LEvent.dwDebugEventCode = EXCEPTION_DEBUG_EVENT then
      begin
        LExcAddr := UInt64(LEvent.Exception.ExceptionRecord.ExceptionAddress);
        LExcCode := LEvent.Exception.ExceptionRecord.ExceptionCode;

        if LExcCode = EXCEPTION_BREAKPOINT then
        begin
          LFoundIdx := -1;
          for LJ := 0 to 5 do
            if (LExcAddr = LBreakpoints[LJ].AbsAddr) or
               (LExcAddr = LBreakpoints[LJ].AbsAddr + 1) then
            begin LFoundIdx := LJ; Break; end;

          if LFoundIdx >= 0 then
          begin
            Inc(LHit);
            LTh := OpenThread($8 or $10,
              False, LEvent.dwThreadId);
            if LTh <> 0 then
            begin
              FillChar(LCtx, SizeOf(LCtx), 0);
              LCtx.ContextFlags := CONTEXT_FULL;
              GetThreadContext(LTh, LCtx);

              WriteLn(Format('[%d] %s RCX=0x%x RDX=0x%x',
                [LHit, LBreakpoints[LFoundIdx].Name, LCtx.Rcx, LCtx.Rdx]));

              // Scan RDX memory
              if LCtx.Rdx > $10000 then
              begin
                LMem := ReadProcMem(LProcHandle, LCtx.Rdx, 4096);
                if LMem <> nil then
                  ScanBufferForKey(LMem, LDBFiles, LFoundKeys);
              end;
              // Scan RCX memory
              if LCtx.Rcx > $10000 then
              begin
                LMem := ReadProcMem(LProcHandle, LCtx.Rcx, 4096);
                if LMem <> nil then
                  ScanBufferForKey(LMem, LDBFiles, LFoundKeys);
              end;
              // Scan RSP memory
              if LCtx.Rsp > $10000 then
              begin
                LMem := ReadProcMem(LProcHandle, LCtx.Rsp, 1024);
                if LMem <> nil then
                  ScanBufferForKey(LMem, LDBFiles, LFoundKeys);
              end;

              if LFoundKeys.Count > 0 then
                SaveResults(LFoundKeys, GDumpDir);

              // Restore original byte
              if LBreakpoints[LFoundIdx].OriginalByte <> 0 then
              begin
                WriteProcessMemory(LProcHandle,
                  Pointer(NativeUInt(LBreakpoints[LFoundIdx].AbsAddr)),
                  @LBreakpoints[LFoundIdx].OriginalByte, 1, LWritten);
                FlushInstructionCache(LProcHandle,
                  Pointer(NativeUInt(LBreakpoints[LFoundIdx].AbsAddr)), 1);
              end;

              // Single-step: set RIP back, enable TF
              LCtx.Rip := LBreakpoints[LFoundIdx].AbsAddr;
              LCtx.EFlags := LCtx.EFlags or $100;
              SetThreadContext(LTh, LCtx);
              CloseHandle(LTh);
            end;
          end;
        end
        else if LExcCode = EXCEPTION_SINGLE_STEP then
        begin
          // Re-arm all breakpoints
          for LJ := 0 to 5 do
          begin
            LInt3 := $CC;
            WriteProcessMemory(LProcHandle,
              Pointer(NativeUInt(LBreakpoints[LJ].AbsAddr)),
              @LInt3, 1, LWritten);
            FlushInstructionCache(LProcHandle,
              Pointer(NativeUInt(LBreakpoints[LJ].AbsAddr)), 1);
          end;
        end;
      end;

      ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId, LContinue);
    end;

    WriteLn('');
    WriteLn('[7/7] Saving results...');
    if LFoundKeys.Count > 0 then
    begin
      SaveResults(LFoundKeys, GDumpDir);
      WriteLn(Format('SUCCESS: %d keys captured', [LFoundKeys.Count]));
    end
    else
      WriteLn('No keys captured. Breakpoints did not fire.');
    WriteLn(Format('  Total hits: %d', [LHit]));

  finally
    LFoundKeys.Free;
    DebugActiveProcessStop(LPid);
    CloseHandle(LProcHandle);
  end;

  WriteLn(Format('Dump directory: %s', [GDumpDir]));
end.