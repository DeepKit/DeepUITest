program WxHybridTap;

{$APPTYPE CONSOLE}

// ─────────────────────────────────────────────────────────────────
//  DeepAxis WxHybridTap v3.0
//  微信 4.x SQLCipher 密钥实时抓取 (INT3 断点)。
//
//  本版本是 probe/probe_v4.py (已验证成功链路) 的忠实 Delphi 移植：
//    · 断点仅两个：CfgHandler / Verify3 (probe_v4 实测可命中并取到密钥)
//    · 密钥校验复用 DeepAxis.WeChat.Decrypt (已验证正确，解密 17 库靠它)
//    · Verify3 命中后额外走 codec 链 (Rcx→btree→pager→codec) 深挖密钥
//    · x64 CONTEXT 强制 16 字节对齐，避免 GetThreadContext 静默失败
//
//  历史 bug (v2.0)：
//    1. 断点 RVA 全错——3 个 RVA >2GB，超出 Weixin.dll 模块大小，断点根本
//       无法写入 (ReadProcMem 返回 nil → SKIP)，其余 RVA 也非取密钥函数。
//    2. VerifyKeyBytes 把原始 32 字节密钥 UTF8 转字符串 (有损) 且只做单次
//       HMAC 而非 PBKDF2(2 轮)，即便断点命中拿到正确密钥也无法通过校验。
//  → 两处叠加导致 “Key capture failed”。本版已修复。
//
//  注意：断点 RVA 与具体 Weixin.dll 构建版本绑定。此处沿用 probe_v4 验证过
//  的 4.1.10.x 偏移；若目标微信版本不同需重新静态分析定位。
// ─────────────────────────────────────────────────────────────────

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.DateUtils,
  System.Generics.Collections, System.Hash, System.JSON,
  Winapi.Windows, Winapi.ShellAPI, Winapi.TlHelp32,
  DeepAxis.WeChat.Decrypt;

function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL;
  dwThreadId: DWORD): THandle; stdcall; external kernel32;

const
  PAGE_SZ = 4096;
  KEY_SIZE = 32;

  // ── 已验证断点 RVA (probe_v4.py 实测命中并取到密钥) ──────────────
  //   CfgHandler / Verify3 是 SQLCipher key 流经的两个点。
  RVA_CFG_HANDLER = $5032E70;
  RVA_VERIFY3     = $5034DF3;

type
  TBreakpoint = record
    Name: string;
    Rva: UInt64;
    AbsAddr: UInt64;
    OriginalByte: Byte;
    Valid: Boolean;
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

function ReadQWord(AHandle: THandle; AAddr: UInt64): UInt64;
var LBuf: TBytes;
begin
  Result := 0;
  LBuf := ReadProcMem(AHandle, AAddr, 8);
  if (LBuf <> nil) and (Length(LBuf) = 8) then
    Move(LBuf[0], Result, 8);
end;

function IsUserPtr(AAddr: UInt64): Boolean; inline;
begin
  Result := (AAddr > $100000000) and (AAddr < $7FFFFFFFFFFF);
end;

// ── 用第一页校验候选 32 字节密钥；命中则登记 ──────────────────────
function ScanBufferForKey(AHandle: THandle; const ABuf: TBytes;
  const ADBFiles: TArray<TDBFile>;
  const AFoundKeys: TDictionary<string, TKeyMatch>): Integer;
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
  if Length(ABuf) < KEY_SIZE then Exit;

  LI := 0;
  while LI <= Length(ABuf) - KEY_SIZE do
  begin
    LCandidate := Copy(ABuf, LI, KEY_SIZE);

    // 快速去噪：唯一字节数过低的一定不是高熵密钥
    LUnique := 0;
    FillChar(LSeen, SizeOf(LSeen), 0);
    for LJ := 0 to KEY_SIZE - 1 do
      if not LSeen[LCandidate[LJ]] then
      begin
        LSeen[LCandidate[LJ]] := True;
        Inc(LUnique);
      end;
    if LUnique >= 22 then
    begin
      for LDB in ADBFiles do
      begin
        LSaltHex := BytesToHex(Copy(LDB.Page1, 0, 16));
        if AFoundKeys.ContainsKey(LSaltHex) then Continue;
        // 复用已验证正确的 SQLCipher 校验 (PBKDF2-HMAC-SHA512 2 轮 + 页 HMAC)
        if TWeChatDecryptor.VerifyKeyBytesAgainstPage1(LCandidate, LDB.Page1) then
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
    Inc(LI, 8); // 8 字节对齐步进，与 probe_v4 一致
  end;
end;

// ── Verify3 codec 链：Rcx→[+0x48]btree→pager→codec，深挖密钥 ───────
procedure ScanVerify3Chain(AHandle: THandle; ARcx: UInt64;
  const ADBFiles: TArray<TDBFile>;
  const AFoundKeys: TDictionary<string, TKeyMatch>);
var
  LBtree, LPager, LCodec: UInt64;
  LPageOff, LCodecOff: Integer;
  LBt, LPg, LCd: TBytes;
begin
  if not IsUserPtr(ARcx) then Exit;
  LBtree := ReadQWord(AHandle, ARcx + $48);
  if not IsUserPtr(LBtree) then Exit;
  LBt := ReadProcMem(AHandle, LBtree, 256);
  if LBt = nil then Exit;

  LPageOff := 0;
  while LPageOff <= 248 - 8 do
  begin
    Move(LBt[LPageOff], LPager, 8);
    if IsUserPtr(LPager) then
    begin
      LPg := ReadProcMem(AHandle, LPager, 512);
      if LPg <> nil then
      begin
        LCodecOff := 0;
        while LCodecOff <= 504 - 8 do
        begin
          Move(LPg[LCodecOff], LCodec, 8);
          if IsUserPtr(LCodec) then
          begin
            LCd := ReadProcMem(AHandle, LCodec, 512);
            if LCd <> nil then
              ScanBufferForKey(AHandle, LCd, ADBFiles, AFoundKeys);
          end;
          Inc(LCodecOff, 8);
        end;
      end;
    end;
    Inc(LPageOff, 8);
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
      WriteLn('DeepAxis WxHybridTap v3.0');
      WriteLn('Usage: WxHybridTap.exe [--timeout-ms=<ms>] [--dump-dir=<path>]');
      Halt(0);
    end;
  end;
  if GDumpDir = '' then
    GDumpDir := TPath.Combine(TPath.GetTempPath, 'DeepAxisWxHybridTap');
end;

// ── Main ─────────────────────────────────────────────────────────

var
  LDataDir: string;
  LDBFiles: TArray<TDBFile>;
  LFoundKeys: TDictionary<string, TKeyMatch>;
  LPid: Cardinal;
  LDllBase: UInt64;
  LProcHandle: THandle;
  LBreakpoints: array[0..1] of TBreakpoint;
  LStartTime: TDateTime;
  LEvent: TDebugEvent;
  LContinue: DWORD;
  LTh: THandle;
  LMem: TBytes;
  LI: Integer;
  LHit: Integer;
  LWritten: SIZE_T;
  LInt3: Byte;
  LMs: Integer;
  LExcAddr: UInt64;
  LExcCode: DWORD;
  LFoundIdx: Integer;
  LPending: Integer;      // 单步后需重新武装的断点下标 (-1 = 无)
  LWeChatPath: string;
  // x64 CONTEXT 需 16 字节对齐，否则 GetThreadContext 会静默失败
  LCtxBuf: array[0..SizeOf(TContext) + 15] of Byte;
  LCtx: PContext;
begin
  ParseArgs;

  WriteLn('DeepAxis WxHybridTap v3.0');
  WriteLn('  Timeout: ', GTimeoutMs, 'ms  Dump: ', GDumpDir);
  WriteLn('');

  ForceDirectories(GDumpDir);

  LDataDir := FindWeChatDataDir;
  if LDataDir <> '' then
  begin
    WriteLn('[1/7] Collecting DB files from: ', LDataDir);
    CollectDBFiles(LDataDir, LDBFiles);
    WriteLn(Format('  Found %d DB files', [Length(LDBFiles)]));
  end
  else
    WriteLn('WARNING: No WeChat data dir found');

  if Length(LDBFiles) = 0 then
  begin
    WriteLn('ERROR: 无可校验的 DB 文件，无法确认捕获的密钥；终止。');
    Halt(2);
  end;

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
    Halt(3);
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
    Halt(4);
  end;
  WriteLn(Format('  PID=%d, DLL=0x%x', [LPid, LDllBase]));

  WriteLn('[5/7] Attaching debugger + setting breakpoints...');
  if not DebugActiveProcess(LPid) then
  begin
    WriteLn(Format('ERROR: DebugActiveProcess failed (0x%x)', [GetLastError]));
    Halt(5);
  end;

  LProcHandle := OpenProcess(PROCESS_ALL_ACCESS, False, LPid);
  if LProcHandle = 0 then
  begin
    WriteLn('ERROR: OpenProcess failed');
    DebugActiveProcessStop(LPid);
    Halt(5);
  end;

  LBreakpoints[0].Name := 'CfgHandler'; LBreakpoints[0].Rva := RVA_CFG_HANDLER;
  LBreakpoints[1].Name := 'Verify3';    LBreakpoints[1].Rva := RVA_VERIFY3;

  for LI := 0 to High(LBreakpoints) do
  begin
    LBreakpoints[LI].AbsAddr := LDllBase + LBreakpoints[LI].Rva;
    LBreakpoints[LI].Valid := False;

    LMem := ReadProcMem(LProcHandle, LBreakpoints[LI].AbsAddr, 1);
    if LMem = nil then
    begin
      WriteLn(Format('  SKIP %s @ 0x%x (unreadable — RVA 可能不匹配当前微信版本)',
        [LBreakpoints[LI].Name, LBreakpoints[LI].AbsAddr]));
      Continue;
    end;
    LBreakpoints[LI].OriginalByte := LMem[0];

    LInt3 := $CC;
    WriteProcessMemory(LProcHandle, Pointer(NativeUInt(LBreakpoints[LI].AbsAddr)),
      @LInt3, 1, LWritten);
    FlushInstructionCache(LProcHandle, Pointer(NativeUInt(LBreakpoints[LI].AbsAddr)), 1);
    LBreakpoints[LI].Valid := True;
    WriteLn(Format('  BP: %s @ 0x%x', [LBreakpoints[LI].Name, LBreakpoints[LI].AbsAddr]));
  end;

  WriteLn('');
  WriteLn('============================================================');
  WriteLn('[6/7] >>> 请立即扫码登录微信 (SCAN QR CODE NOW) <<<');
  WriteLn(Format('  Timeout: %d seconds', [GTimeoutMs div 1000]));
  WriteLn('============================================================');
  WriteLn('');

  // 16 字节对齐的 CONTEXT 指针
  LCtx := PContext((NativeUInt(@LCtxBuf[0]) + 15) and not NativeUInt(15));

  LFoundKeys := TDictionary<string, TKeyMatch>.Create;
  try
    LHit := 0;
    LPending := -1;
    LStartTime := Now;

    while True do
    begin
      LMs := MilliSecondsBetween(Now, LStartTime);
      if LMs >= GTimeoutMs then
      begin
        WriteLn(Format('Timeout after %d ms', [LMs]));
        Break;
      end;

      if not WaitForDebugEvent(LEvent, 1000) then
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
          for LI := 0 to High(LBreakpoints) do
            if LBreakpoints[LI].Valid and
               ((LExcAddr = LBreakpoints[LI].AbsAddr) or
                (LExcAddr = LBreakpoints[LI].AbsAddr + 1)) then
            begin LFoundIdx := LI; Break; end;

          if LFoundIdx >= 0 then
          begin
            Inc(LHit);
            LTh := OpenThread($8 or $10, False, LEvent.dwThreadId); // GET_CONTEXT|SET_CONTEXT
            if LTh <> 0 then
            begin
              FillChar(LCtx^, SizeOf(TContext), 0);
              LCtx^.ContextFlags := CONTEXT_FULL;
              if GetThreadContext(LTh, LCtx^) then
              begin
                WriteLn(Format('[%d] %s RCX=0x%x RDX=0x%x',
                  [LHit, LBreakpoints[LFoundIdx].Name, LCtx^.Rcx, LCtx^.Rdx]));

                // 扫 RDX 指向内存
                if LCtx^.Rdx > $10000 then
                begin
                  LMem := ReadProcMem(LProcHandle, LCtx^.Rdx, 4096);
                  if LMem <> nil then
                    ScanBufferForKey(LProcHandle, LMem, LDBFiles, LFoundKeys);
                end;
                // 扫 RCX 指向内存
                if LCtx^.Rcx > $10000 then
                begin
                  LMem := ReadProcMem(LProcHandle, LCtx^.Rcx, 4096);
                  if LMem <> nil then
                    ScanBufferForKey(LProcHandle, LMem, LDBFiles, LFoundKeys);
                end;
                // 扫栈
                if LCtx^.Rsp > $10000 then
                begin
                  LMem := ReadProcMem(LProcHandle, LCtx^.Rsp, 1024);
                  if LMem <> nil then
                    ScanBufferForKey(LProcHandle, LMem, LDBFiles, LFoundKeys);
                end;
                // Verify3: 额外走 codec 链
                if SameText(LBreakpoints[LFoundIdx].Name, 'Verify3') then
                  ScanVerify3Chain(LProcHandle, LCtx^.Rcx, LDBFiles, LFoundKeys);

                if LFoundKeys.Count > 0 then
                  SaveResults(LFoundKeys, GDumpDir);

                // 先临时恢复原字节，单步跨过该指令，再重新武装 (probe_v4 pending 模式)
                if LBreakpoints[LFoundIdx].Valid then
                begin
                  WriteProcessMemory(LProcHandle,
                    Pointer(NativeUInt(LBreakpoints[LFoundIdx].AbsAddr)),
                    @LBreakpoints[LFoundIdx].OriginalByte, 1, LWritten);
                  FlushInstructionCache(LProcHandle,
                    Pointer(NativeUInt(LBreakpoints[LFoundIdx].AbsAddr)), 1);
                end;

                LCtx^.Rip := LBreakpoints[LFoundIdx].AbsAddr;
                LCtx^.EFlags := LCtx^.EFlags or $100; // Trap Flag → 单步
                SetThreadContext(LTh, LCtx^);
                LPending := LFoundIdx;
              end;
              CloseHandle(LTh);
            end;
          end;
        end
        else if (LExcCode = EXCEPTION_SINGLE_STEP) and (LPending >= 0) then
        begin
          // 单步已跨过原指令，重新武装该断点
          if LBreakpoints[LPending].Valid then
          begin
            LInt3 := $CC;
            WriteProcessMemory(LProcHandle,
              Pointer(NativeUInt(LBreakpoints[LPending].AbsAddr)),
              @LInt3, 1, LWritten);
            FlushInstructionCache(LProcHandle,
              Pointer(NativeUInt(LBreakpoints[LPending].AbsAddr)), 1);
          end;
          LPending := -1;
        end;
      end;

      ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId, LContinue);

      if LFoundKeys.Count >= Length(LDBFiles) then
      begin
        WriteLn('All DB keys found!');
        Break;
      end;
      if LHit >= 500 then
      begin
        WriteLn('500 hits — stopping.');
        Break;
      end;
    end;

    WriteLn('');
    WriteLn('[7/7] Saving results...');
    // 收尾恢复原字节
    for LI := 0 to High(LBreakpoints) do
      if LBreakpoints[LI].Valid then
        WriteProcessMemory(LProcHandle,
          Pointer(NativeUInt(LBreakpoints[LI].AbsAddr)),
          @LBreakpoints[LI].OriginalByte, 1, LWritten);

    if LFoundKeys.Count > 0 then
    begin
      SaveResults(LFoundKeys, GDumpDir);
      WriteLn(Format('SUCCESS: %d keys captured', [LFoundKeys.Count]));
    end
    else
      WriteLn('No keys captured. Breakpoints did not fire (检查 RVA 是否匹配当前微信版本)。');
    WriteLn(Format('  Total hits: %d', [LHit]));

  finally
    LFoundKeys.Free;
    DebugActiveProcessStop(LPid);
    CloseHandle(LProcHandle);
  end;

  WriteLn(Format('Dump directory: %s', [GDumpDir]));
end.
