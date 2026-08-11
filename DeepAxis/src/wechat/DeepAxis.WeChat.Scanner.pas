unit DeepAxis.WeChat.Scanner;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.DateUtils,
  System.StrUtils,
  Winapi.Windows, Winapi.ShellAPI, Winapi.TlHelp32,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Config,
  DeepAxis.Core.KeyExtractor,
  DeepAxis.WeChat.Decrypt,
  DeepAxis.WeChat.KeyExtractors;

type
  TModuleEntry = record
    Name: string; Path: string; Base: UInt64; Size: Cardinal;
  end;

  TWeChatScannerStateEvent = procedure(const AState: TWeChatProcessState) of object;

  TWeChatScanner = class
  private
    FState: TWeChatProcessState;
    FOnStateChanged: TWeChatScannerStateEvent;
    FWeChatPid: Cardinal;
    FWeChatPath: string;
    FKeyManager: TKeyManager;
    FWeChatDataDir: string;
    FDecryptedContactPath: string;
    FDecryptedMessage0Path: string;
    FDecryptedSessionPath: string;
    FHybridTapPath: string;
    FHybridTapDumpDir: string;
    FHybridTapProcess: THandle;
    function FindWeChatExe: string;
    function FindHybridTapExe: string;
    function KillWeChat: Boolean;
    function WaitForProcess(const ATimeoutMs: Cardinal): Boolean;
    function WaitForProcessExit(const ATimeoutMs: Cardinal): Boolean;
    function ScanMemoryForKey: TWeChatKeyCaptureResult;
    function SaveCapturedKey(const AResult: TWeChatKeyCaptureResult): Boolean;
    procedure VerifyAndActivate(const AResult: TWeChatKeyCaptureResult);
    procedure SetState(const AState: TWeChatProcessState);
    function EnumerateModules(const APid: Cardinal): TArray<TModuleEntry>;
    function TrySavedKeys: Boolean;
    function TryHybridTapCapture: Boolean;
    function LaunchHybridTap: Boolean;
    function WaitForHybridTapDump(const ATimeoutMs: Cardinal): Boolean;
    function LoadCapturedKeysFromDump: Boolean;
    procedure CleanupHybridTap;
    function ScanMemoryEntropy(const AProcess: THandle; const AModules: TArray<TModuleEntry>): TWeChatKeyCaptureResult;
    function ReadContactDbPage1: TBytes;
  public
    constructor Create;
    destructor Destroy; override;
    function StartScan(AAllowRestartWeChat: Boolean = False): TWeChatKeyCaptureResult;
    function TrySavedKeysOnly: Boolean;
    /// <summary>BUG-052 #91: 用提取链 (saved_keys → version_specific → entropy) 获取密钥。</summary>
    function TryExtractWithChain: TWeChatKeyCaptureResult;
    function GetState: TWeChatProcessState;
    function LaunchWeChat: Boolean;
    function FindWeChatProcess: Cardinal;
    function FindSavedKeysPath: string;
    function FindWeChatDataDir: string;
    property OnStateChanged: TWeChatScannerStateEvent read FOnStateChanged write FOnStateChanged;
    property KeyManager: TKeyManager read FKeyManager;
    property WeChatDataDir: string read FWeChatDataDir;
    property DecryptedContactPath: string read FDecryptedContactPath;
    property DecryptedMessage0Path: string read FDecryptedMessage0Path;
    property DecryptedSessionPath: string read FDecryptedSessionPath;
  end;

const
  // BUG-052: Decrypt 单元的 PAGE_SIZE 在 implementation 区不可见, 此处本地定义
  SCAN_PAGE_SIZE = 4096;

implementation

function CalcEntropy(const AData: TBytes): Double;
var
  Freq: array[0..255] of Integer;
  I: Integer;
  P: Double;
begin
  FillChar(Freq, SizeOf(Freq), 0);
  for I := 0 to Length(AData) - 1 do
    Inc(Freq[AData[I]]);
  Result := 0;
  for I := 0 to 255 do
    if Freq[I] > 0 then
    begin
      P := Freq[I] / Length(AData);
      Result := Result - P * Ln(P) / Ln(2);
    end;
end;

function IsHexByte(C: Byte): Boolean; inline;
begin
  Result := ((C >= Ord('0')) and (C <= Ord('9'))) or
            ((C >= Ord('a')) and (C <= Ord('f'))) or
            ((C >= Ord('A')) and (C <= Ord('F')));
end;

function LooksLikeRawKey(const ABuf: TBytes): Boolean;
var
  Freq: array[0..255] of Integer;
  I, Zeros, Unique, MaxFreq: Integer;
begin
  Result := False;
  if Length(ABuf) <> 32 then Exit;
  FillChar(Freq, SizeOf(Freq), 0);
  Zeros := 0;
  for I := 0 to 31 do
  begin
    if ABuf[I] = 0 then Inc(Zeros);
    Inc(Freq[ABuf[I]]);
  end;
  Unique := 0;
  MaxFreq := 0;
  for I := 0 to 255 do
    if Freq[I] > 0 then
    begin
      Inc(Unique);
      if Freq[I] > MaxFreq then MaxFreq := Freq[I];
    end;
  Result := (Zeros <= 3) and (Unique >= 24) and (MaxFreq <= 4) and
            (CalcEntropy(ABuf) >= 4.55);
end;

function ReadProcMem(AHandle: THandle; AAddr: UInt64; ASize: Integer): TBytes;
var
  LRead: SIZE_T;
begin
  Result := nil;
  SetLength(Result, ASize);
  if not ReadProcessMemory(AHandle, Pointer(NativeUInt(AAddr)), @Result[0], ASize, LRead) then
    Exit(nil);
  if LRead <> ASize then
    SetLength(Result, LRead);
end;

{ TWeChatScanner }

constructor TWeChatScanner.Create;
begin
  inherited Create;
  FState := wpsNotFound;
  FWeChatPid := 0;
  FKeyManager := TKeyManager.Create;
  FHybridTapProcess := 0;
end;

destructor TWeChatScanner.Destroy;
begin
  CleanupHybridTap;
  FKeyManager.Free;
  inherited;
end;

function TWeChatScanner.GetState: TWeChatProcessState;
begin
  Result := FState;
end;

procedure TWeChatScanner.SetState(const AState: TWeChatProcessState);
begin
  FState := AState;
  if Assigned(FOnStateChanged) then
    FOnStateChanged(AState);
end;

function TWeChatScanner.FindHybridTapExe: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\probe\WxHybridTap.exe');
  if TFile.Exists(Result) then Exit;
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'WxHybridTap.exe');
  if TFile.Exists(Result) then Exit;
  Result := '';
end;

function TWeChatScanner.FindWeChatExe: string;
begin
  Result := TDeepAxisConfig.GetWeChatPath;
  if (Result <> '') and TFile.Exists(Result) then Exit;
  if TFile.Exists('D:\Program Files\Tencent\Weixin\Weixin.exe') then
    Exit('D:\Program Files\Tencent\Weixin\Weixin.exe');
  if TFile.Exists('C:\Program Files\Tencent\WeChat\Weixin.exe') then
    Exit('C:\Program Files\Tencent\WeChat\Weixin.exe');
  Result := '';
end;

function TWeChatScanner.FindSavedKeysPath: string;
begin
  // 委托给 TDeepAxisConfig.GetKeysFilePath — 密钥路径的唯一真相源。
  // 此前 SetupForm 与本方法各自硬编码，导致向导显示状态与连接流程实际
  // 使用的密钥路径不一致 (BUG-030)。
  Result := TDeepAxisConfig.GetKeysFilePath;
end;

function TWeChatScanner.FindWeChatDataDir: string;
var
  LBase: string;
  LDirs: TArray<string>;
  LDir: string;
  LMsgDir: string;
begin
  Result := TDeepAxisConfig.GetWeChatDataPath;
  if (Result <> '') and TDirectory.Exists(Result) then Exit;
  LBase := 'D:\xwechat_files';
  if TDirectory.Exists(LBase) then
  begin
    LDirs := TDirectory.GetDirectories(LBase, 'db_storage', TSearchOption.soAllDirectories);
    for LDir in LDirs do
    begin
      LMsgDir := TPath.Combine(LDir, 'message');
      if TDirectory.Exists(LMsgDir) then
      begin
        // 返回 db_storage 目录，不是它的父目录
        Result := LDir;
        TDeepAxisConfig.SetWeChatDataPath(Result);
        Exit;
      end;
    end;
  end;
end;

function TWeChatScanner.TrySavedKeys: Boolean;
var
  LKeysPath: string;
  LDataDir: string;
  LBase: string;
  LDirs: TArray<string>;
  LDir: string;

  function TryDecryptDir(const ADir: string): Boolean;
  begin
    Result := False;
    if (ADir = '') or (not TDirectory.Exists(ADir)) then Exit;
    try
      Result := TWeChatDecryptor.AutoDecrypt(ADir, FKeyManager,
        FDecryptedContactPath, FDecryptedMessage0Path, FDecryptedSessionPath);
    except
      Result := False;
    end;
    if Result then
    begin
      FWeChatDataDir := ADir;
      TDeepAxisConfig.SetWeChatDataPath(ADir);
      SetState(wpsKeyVerified);
    end;
  end;

begin
  Result := False;
  LKeysPath := FindSavedKeysPath;
  if LKeysPath = '' then Exit;
  if not FKeyManager.LoadFromJSON(LKeysPath) then Exit;
  if not FKeyManager.HasKeys then Exit;

  // 1) 先试配置/自动探测到的账号目录
  LDataDir := FindWeChatDataDir;
  if TryDecryptDir(LDataDir) then Exit(True);

  // 2) BUG-046 修复: 配置账号与已存密钥不匹配时(账号错位, 或微信升级/换号导致
  //    ini 里的 WeChatDataPath 过期), 遍历 D:\xwechat_files 下所有 db_storage,
  //    用已存密钥能实际解开的那个账号目录。只要密钥库里有当前登录账号的密钥,
  //    就无需实时抓取(与微信版本无关), 从根本上规避断点 RVA 版本失配问题。
  LBase := 'D:\xwechat_files';
  if TDirectory.Exists(LBase) then
  begin
    LDirs := TDirectory.GetDirectories(LBase, 'db_storage', TSearchOption.soAllDirectories);
    for LDir in LDirs do
      if not SameText(LDir, LDataDir) then
        if TryDecryptDir(LDir) then Exit(True);
  end;
end;

function TWeChatScanner.TrySavedKeysOnly: Boolean;
begin
  Result := TrySavedKeys;
end;

// ── HybridTap capture ────────────────────────────────────────────

function TWeChatScanner.TryHybridTapCapture: Boolean;
var
  LDataDir: string;
begin
  Result := False;
  FHybridTapPath := FindHybridTapExe;
  if FHybridTapPath = '' then Exit;
  FHybridTapDumpDir := TPath.Combine(TPath.GetTempPath, 'DeepAxis_HybridTap');
  if TDirectory.Exists(FHybridTapDumpDir) then
    TDirectory.Delete(FHybridTapDumpDir, True);
  TDirectory.CreateDirectory(FHybridTapDumpDir);
  SetState(wpsLaunching);
  KillWeChat;
  Sleep(2000);
  if not LaunchWeChat then Exit;
  Sleep(1000);
  if not WaitForProcess(15000) then Exit;
  SetState(wpsRunning);
  Sleep(500);
  SetState(wpsScanning);
  if not LaunchHybridTap then Exit;
  if not WaitForHybridTapDump(95000) then
  begin
    CleanupHybridTap;
    Exit;
  end;
  if not LoadCapturedKeysFromDump then Exit;
  LDataDir := FindWeChatDataDir;
  if LDataDir = '' then
  begin
    CleanupHybridTap;
    Exit;
  end;
  FWeChatDataDir := LDataDir;
  if TWeChatDecryptor.AutoDecrypt(LDataDir, FKeyManager,
    FDecryptedContactPath, FDecryptedMessage0Path, FDecryptedSessionPath) then
  begin
    TDeepAxisConfig.SetWeChatDataPath(LDataDir);
    SetState(wpsKeyVerified);
    Result := True;
  end;
  CleanupHybridTap;
end;

function TWeChatScanner.LaunchHybridTap: Boolean;
var
  LSI: TStartupInfo;
  LPI: TProcessInformation;
  LCmdLine: string;
begin
  Result := False;
  if FHybridTapPath = '' then Exit;
  FillChar(LSI, SizeOf(LSI), 0);
  LSI.cb := SizeOf(LSI);
  FillChar(LPI, SizeOf(LPI), 0);
  LCmdLine := Format('"%s" --timeout-ms=95000 --dump-dir=%s',
    [FHybridTapPath, FHybridTapDumpDir]);
  Result := CreateProcess(nil, PChar(LCmdLine), nil, nil, False,
    CREATE_NO_WINDOW, nil, PChar(TPath.GetDirectoryName(FHybridTapPath)), LSI, LPI);
  if Result then
  begin
    FHybridTapProcess := LPI.hProcess;
    CloseHandle(LPI.hThread);
  end;
end;

function TWeChatScanner.WaitForHybridTapDump(const ATimeoutMs: Cardinal): Boolean;
var
  LStart: Cardinal;
  LExitCode: DWORD;
  LKeysFile: string;
  LBinFiles: TArray<string>;
begin
  Result := False;
  if FHybridTapProcess = 0 then Exit;
  LStart := GetTickCount;
  while True do
  begin
    if WaitForSingleObject(FHybridTapProcess, 500) = WAIT_OBJECT_0 then
    begin
      GetExitCodeProcess(FHybridTapProcess, LExitCode);
      CloseHandle(FHybridTapProcess);
      FHybridTapProcess := 0;
      LKeysFile := TPath.Combine(FHybridTapDumpDir, 'all_keys.json');
      Result := TFile.Exists(LKeysFile);
      if not Result then
      begin
        LBinFiles := TDirectory.GetFiles(FHybridTapDumpDir, '*.bin');
        Result := Length(LBinFiles) > 0;
      end;
      Exit;
    end;
    LKeysFile := TPath.Combine(FHybridTapDumpDir, 'all_keys.json');
    if TFile.Exists(LKeysFile) then
    begin
      Sleep(3000);
      TerminateProcess(FHybridTapProcess, 0);
      CloseHandle(FHybridTapProcess);
      FHybridTapProcess := 0;
      Result := True;
      Exit;
    end;
    if (GetTickCount - LStart) >= ATimeoutMs then
    begin
      TerminateProcess(FHybridTapProcess, 0);
      CloseHandle(FHybridTapProcess);
      FHybridTapProcess := 0;
      Exit;
    end;
  end;
end;

function TWeChatScanner.LoadCapturedKeysFromDump: Boolean;
var
  LKeysFile: string;
begin
  LKeysFile := TPath.Combine(FHybridTapDumpDir, 'all_keys.json');
  Result := TFile.Exists(LKeysFile) and FKeyManager.LoadFromJSON(LKeysFile);
end;

procedure TWeChatScanner.CleanupHybridTap;
begin
  if FHybridTapProcess <> 0 then
  begin
    TerminateProcess(FHybridTapProcess, 0);
    CloseHandle(FHybridTapProcess);
    FHybridTapProcess := 0;
  end;
  if (FHybridTapDumpDir <> '') and TDirectory.Exists(FHybridTapDumpDir) then
    try
      TDirectory.Delete(FHybridTapDumpDir, True);
    except
    end;
end;

// ── Process management ───────────────────────────────────────────

function TWeChatScanner.KillWeChat: Boolean;
var
  LPid: Cardinal;
  LProc: THandle;
begin
  Result := True;
  LPid := FindWeChatProcess;
  if LPid = 0 then Exit;
  LProc := OpenProcess(PROCESS_TERMINATE, False, LPid);
  if LProc = 0 then Exit(False);
  Result := TerminateProcess(LProc, 0);
  CloseHandle(LProc);
  if Result then
    WaitForProcessExit(10000);
end;

function TWeChatScanner.WaitForProcessExit(const ATimeoutMs: Cardinal): Boolean;
var
  LStart: Cardinal;
begin
  LStart := GetTickCount;
  repeat
    if FindWeChatProcess = 0 then Exit(True);
    Sleep(200);
  until (GetTickCount - LStart) >= ATimeoutMs;
  Result := False;
end;

function TWeChatScanner.LaunchWeChat: Boolean;
var
  LPath: string;
begin
  LPath := FindWeChatExe;
  if LPath = '' then
  begin
    SetState(wpsFailed);
    Exit(False);
  end;
  FWeChatPath := LPath;
  Result := ShellExecute(0, 'open', PChar(LPath), nil, nil, SW_SHOW) > 32;
  if Result then
    SetState(wpsLaunching)
  else
    SetState(wpsFailed);
end;

function TWeChatScanner.FindWeChatProcess: Cardinal;
var
  LSnapshot: THandle;
  LEntry: TProcessEntry32;
  LProc: THandle;
  LMods: TArray<TModuleEntry>;
  LMod: TModuleEntry;
begin
  // BUG-052 fix: 微信 4.x 有多个 Weixin.exe 进程 (主进程 + 辅助进程)。
  // 遍历所有 Weixin.exe, 优先选**加载了 Weixin.dll 的** (主进程) —
  // 旧实现返回枚举到的第一个, 可能是空的辅助进程 → 读不到密钥。
  Result := 0;
  LSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if LSnapshot = INVALID_HANDLE_VALUE then Exit;
  LEntry.dwSize := SizeOf(LEntry);
  if Process32First(LSnapshot, LEntry) then
    repeat
      if SameText(LEntry.szExeFile, WECHAT_PROCESS_NAME) then
      begin
        // 验证该进程是否加载 Weixin.dll (主进程特征)
        LProc := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False,
          LEntry.th32ProcessID);
        if LProc <> 0 then
        begin
          try
            LMods := EnumerateModules(LEntry.th32ProcessID);
            for LMod in LMods do
              if SameText(LMod.Name, WECHAT_DLL_NAME) then
              begin
                Result := LEntry.th32ProcessID;
                Break;
              end;
          finally
            CloseHandle(LProc);
          end;
          if Result <> 0 then
            Break;
        end;
      end;
    until not Process32Next(LSnapshot, LEntry);
  CloseHandle(LSnapshot);

  // 兜底: 未找到带 Weixin.dll 的进程, 返回第一个 Weixin.exe (至少能检测到运行)
  if Result = 0 then
  begin
    LSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if LSnapshot <> INVALID_HANDLE_VALUE then
    begin
      LEntry.dwSize := SizeOf(LEntry);
      if Process32First(LSnapshot, LEntry) then
        repeat
          if SameText(LEntry.szExeFile, WECHAT_PROCESS_NAME) then
          begin
            Result := LEntry.th32ProcessID;
            Break;
          end;
        until not Process32Next(LSnapshot, LEntry);
      CloseHandle(LSnapshot);
    end;
  end;
end;

function TWeChatScanner.WaitForProcess(const ATimeoutMs: Cardinal): Boolean;
var
  LStart: Cardinal;
  LPid: Cardinal;
begin
  LStart := GetTickCount;
  repeat
    LPid := FindWeChatProcess;
    if LPid <> 0 then
    begin
      FWeChatPid := LPid;
      SetState(wpsRunning);
      Exit(True);
    end;
    Sleep(500);
  until (GetTickCount - LStart) >= ATimeoutMs;
  Exit(False);
end;

function TWeChatScanner.EnumerateModules(const APid: Cardinal): TArray<TModuleEntry>;
var
  LSnapshot: THandle;
  LEntry: TModuleEntry32;
  LMod: TModuleEntry;
begin
  Result := nil;
  LSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, APid);
  if LSnapshot = INVALID_HANDLE_VALUE then Exit;
  LEntry.dwSize := SizeOf(LEntry);
  if Module32First(LSnapshot, LEntry) then
    repeat
      LMod.Name := string(LEntry.szModule);
      LMod.Path := string(LEntry.szExePath);
      LMod.Base := UInt64(LEntry.modBaseAddr);
      LMod.Size := LEntry.modBaseSize;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LMod;
    until not Module32Next(LSnapshot, LEntry);
  CloseHandle(LSnapshot);
end;

// ── Full memory entropy scanner ──────────────────────────────────

type
  TKeyCandidate = record
    Key: TBytes;
    Addr: UInt64;
    Entropy: Double;
  end;

function TWeChatScanner.ScanMemoryEntropy(const AProcess: THandle;
  const AModules: TArray<TModuleEntry>): TWeChatKeyCaptureResult;
const
  BUF_SIZE = 1048576;
  MAX_CANDIDATES = 256;
var
  LMod: TModuleEntry;
  LI, LJ: Integer;
  LAddr, LRegionBase, LRegionSize, LNextAddr: UInt64;
  LMBI: TMemoryBasicInformation;
  LBuf: TBytes;
  LBytesRead: SIZE_T;
  LChunkSize, LOffset: NativeUInt;
  LCandidates: array of TKeyCandidate;
  LCount: Integer;
  LKeyIdx: Integer;
  LWeixinDll: UInt64;
  LCandidate: TBytes;
  LEntropy: Double;
  LFound: Boolean;
  LBest: Integer;
  LKOffs: array[0..4] of UInt64;
  LKAddr: UInt64;
  LKMem: TBytes;
  LKnownFound: Boolean;
  LHex: string;
begin
  Result := Default(TWeChatKeyCaptureResult);
  Result.State := wpsFailed;
  LCount := 0;
  LWeixinDll := 0;

  for LI := 0 to Length(AModules) - 1 do
    if SameText(AModules[LI].Name, WECHAT_DLL_NAME) then
    begin
      LWeixinDll := AModules[LI].Base;
      Break;
    end;

  if LWeixinDll = 0 then
  begin
    Result.ErrorMessage := 'Weixin.dll not found';
    Exit;
  end;

  SetLength(LBuf, BUF_SIZE);

  for LMod in AModules do
  begin
    LAddr := LMod.Base;
    while True do
    begin
      FillChar(LMBI, SizeOf(LMBI), 0);
      if VirtualQueryEx(AProcess, Pointer(NativeUInt(LAddr)), LMBI, SizeOf(LMBI)) = 0 then
        Break;
      LRegionBase := UInt64(LMBI.BaseAddress);
      LRegionSize := LMBI.RegionSize;
      LNextAddr := LRegionBase + LRegionSize;
      if LNextAddr <= LAddr then Break;

      if (LMBI.State = MEM_COMMIT) and (LMBI.Type_9 = MEM_PRIVATE) then
      begin
        LOffset := 0;
        while LOffset < LRegionSize do
        begin
          LChunkSize := LRegionSize - LOffset;
          if LChunkSize > BUF_SIZE then LChunkSize := BUF_SIZE;
          LBytesRead := 0;
          if ReadProcessMemory(AProcess, Pointer(NativeUInt(LRegionBase + LOffset)),
            @LBuf[0], LChunkSize, LBytesRead) and (LBytesRead >= 32) then
          begin
            for LJ := 0 to Integer(LBytesRead) - 32 do
            begin
              if LJ mod 8 <> 0 then Continue;
              LCandidate := Copy(LBuf, LJ, 32);
              if LooksLikeRawKey(LCandidate) then
              begin
                LFound := False;
                for LKeyIdx := 0 to LCount - 1 do
                  if CompareMem(@LCandidates[LKeyIdx].Key[0], @LCandidate[0], 32) then
                  begin
                    LFound := True;
                    Break;
                  end;
                if LFound then Continue;

                LEntropy := CalcEntropy(LCandidate);
                if LCount < MAX_CANDIDATES then
                begin
                  SetLength(LCandidates, LCount + 1);
                  LCandidates[LCount].Key := LCandidate;
                  LCandidates[LCount].Addr := LRegionBase + LOffset + UInt64(LJ);
                  LCandidates[LCount].Entropy := LEntropy;
                  Inc(LCount);
                end;
              end;
            end;
          end;
          LOffset := LOffset + LChunkSize;
        end;
      end;
      LAddr := LNextAddr;
    end;
  end;

  // Known offsets
  LKOffs[0] := $1131B64; LKOffs[1] := $1A30000;
  LKOffs[2] := $1F0B000; LKOffs[3] := $1F30000;
  LKOffs[4] := $2100000;
  for LI := 0 to 4 do
  begin
    LKAddr := LWeixinDll + LKOffs[LI];
    LKMem := ReadProcMem(AProcess, LKAddr, 32);
    if (LKMem <> nil) and (Length(LKMem) = 32) then
    begin
      LKnownFound := False;
      for LKeyIdx := 0 to LCount - 1 do
        if CompareMem(@LCandidates[LKeyIdx].Key[0], @LKMem[0], 32) then
        begin
          LKnownFound := True;
          Break;
        end;
      if (not LKnownFound) and LooksLikeRawKey(LKMem) and (LCount < MAX_CANDIDATES) then
      begin
        SetLength(LCandidates, LCount + 1);
        LCandidates[LCount].Key := LKMem;
        LCandidates[LCount].Addr := LKAddr;
        LCandidates[LCount].Entropy := CalcEntropy(LKMem);
        Inc(LCount);
      end;
    end;
  end;

  if LCount > 0 then
  begin
    // BUG-052: 用真实 contact.db 页 1 验证候选密钥 (HMAC), 不只看熵。
    // 版本无关 — 只要候选里含真密钥就能挑出, 不依赖已知偏移。
    var LVerified := False;
    var LPage1 := ReadContactDbPage1;
    if (LPage1 <> nil) and (Length(LPage1) >= SCAN_PAGE_SIZE) then
    begin
      for LI := 0 to LCount - 1 do
        if TWeChatDecryptor.VerifyKeyBytesAgainstPage1(LCandidates[LI].Key, LPage1) then
        begin
          LBest := LI;
          LVerified := True;
          Break;
        end;
    end;

    if not LVerified then
    begin
      // 无 DB 可验证或全部候选未通过: 回退熵最高候选 (旧行为)
      LBest := 0;
      for LI := 1 to LCount - 1 do
        if LCandidates[LI].Entropy > LCandidates[LBest].Entropy then
          LBest := LI;
    end;

    Result.State := wpsKeyFound;
    LHex := '';
    for LI := 0 to 31 do
      LHex := LHex + IntToHex(LCandidates[LBest].Key[LI], 2);
    Result.KeyHex := LHex;
    Result.KeyBytes := LCandidates[LBest].Key;
    Result.WeChatPid := FWeChatPid;
    Result.WeChatVersion := '4.x (memory scan' + IfThen(LVerified, ' + verified', ' + entropy') + ')';
  end
  else
    Result.ErrorMessage := Format('No key candidates found (%d regions scanned)', [LCount]);
end;

function TWeChatScanner.ReadContactDbPage1: TBytes;
var
  LDataDir: string;
  LContactDb: string;
  LStream: TFileStream;
  LRead: Integer;
begin
  // BUG-052: 读取真实 contact.db 第 1 页 (4096+ 字节) 供密钥候选验证。
  // 微信 4.x 数据目录: D:\xwechat_files\<account>\db_storage\message\contact.db
  Result := nil;
  LDataDir := FindWeChatDataDir;
  if LDataDir = '' then Exit;

  LContactDb := TPath.Combine(LDataDir, 'message\contact.db');
  if not TFile.Exists(LContactDb) then
  begin
    // 兼容 3.x: db_storage 下直接有 contact.db
    LContactDb := TPath.Combine(LDataDir, 'contact.db');
    if not TFile.Exists(LContactDb) then Exit;
  end;

  try
    LStream := TFileStream.Create(LContactDb, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, SCAN_PAGE_SIZE + 256);  // 页 1 + salt 区
      LRead := LStream.Read(Result[0], Length(Result));
      SetLength(Result, LRead);
    finally
      LStream.Free;
    end;
  except
    Result := nil;
  end;
end;

function TWeChatScanner.ScanMemoryForKey: TWeChatKeyCaptureResult;
var
  LProcess: THandle;
  LModules: TArray<TModuleEntry>;
  LErr: DWORD;
begin
  Result := Default(TWeChatKeyCaptureResult);
  Result.State := wpsFailed;

  LProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, FWeChatPid);
  if LProcess = 0 then
  begin
    // BUG-052: 区分权限不足 vs 进程不存在
    LErr := GetLastError;
    if LErr = ERROR_ACCESS_DENIED then
      Result.ErrorMessage := '无法读取微信进程内存 (ERROR_ACCESS_DENIED)' +
        ' — 请以管理员身份运行 DeepAxis (读取进程内存需同权限或更高)'
    else
      Result.ErrorMessage := Format('Cannot open WeChat process (error %d)', [LErr]);
    Exit;
  end;
  try
    LModules := EnumerateModules(FWeChatPid);
    if Length(LModules) = 0 then
    begin
      Result.ErrorMessage := '无法枚举微信进程模块 (可能权限不足或进程已退出)';
      Exit;
    end;
    Result := ScanMemoryEntropy(LProcess, LModules);
    Result.WeChatPid := FWeChatPid;
  finally
    CloseHandle(LProcess);
  end;
end;

function TWeChatScanner.SaveCapturedKey(const AResult: TWeChatKeyCaptureResult): Boolean;
var
  LKeysPath: string;
  LKeys: string;
begin
  Result := False;
  if (not AResult.IsSuccess) or (AResult.KeyHex = '') then Exit;
  try
    // 保存密钥到 DeCrypt/keys/ 目录
    LKeysPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\captured_key.txt');
    ForceDirectories(TPath.GetDirectoryName(LKeysPath));
    LKeys := Format('enc_key=%s'#13#10'salt=%s'#13#10'pid=%d'#13#10'version=%s',
      [AResult.KeyHex, '00000000000000000000000000000000', AResult.WeChatPid, AResult.WeChatVersion]);
    TFile.WriteAllText(LKeysPath, LKeys);
    Result := True;
  except
  end;
end;

procedure TWeChatScanner.VerifyAndActivate(const AResult: TWeChatKeyCaptureResult);
var
  LDataPath: string;
begin
  LDataPath := FindWeChatDataDir;
  if LDataPath = '' then
  begin
    SetState(wpsFailed);
    Exit;
  end;
  SetState(wpsKeyVerified);
  TDeepAxisConfig.SetWeChatDataPath(LDataPath);
end;

function TWeChatScanner.TryExtractWithChain: TWeChatKeyCaptureResult;
var
  LChain: TKeyExtractorChain;
  LFingerprint: TWeChatVersionFingerprint;
  LKeyHex, LDiag: string;
begin
  // BUG-052 #91: 版本自适应密钥提取链。
  // 探测版本指纹 → 方法链依次尝试 → 候选密钥用 contact.db 页1 HMAC 自验证。
  Result := Default(TWeChatKeyCaptureResult);
  Result.State := wpsFailed;

  try
    RegisterDefaultKeyExtractors;
    LChain := GetKeyExtractorChain;
    LFingerprint := TWeChatVersionProbe.Detect(FWeChatPid);

    if LChain.Execute(LFingerprint, LKeyHex, LDiag) then
    begin
      Result.State := wpsKeyFound;
      Result.KeyHex := LKeyHex;
      SetLength(Result.KeyBytes, Length(LKeyHex) div 2);
      for var I := 0 to Length(Result.KeyBytes) - 1 do
        Result.KeyBytes[I] := Byte(StrToInt('$' + Copy(LKeyHex, I * 2 + 1, 2)));
      Result.WeChatPid := FWeChatPid;
      Result.WeChatVersion := LFingerprint.FileVersionStr;
    end
    else
      Result.ErrorMessage := LDiag;
  except
    on E: Exception do
      Result.ErrorMessage := '提取链异常: ' + E.ClassName + ': ' + E.Message;
  end;
end;

function TWeChatScanner.StartScan(AAllowRestartWeChat: Boolean): TWeChatKeyCaptureResult;
var
  LPid: Cardinal;
  LResult: TWeChatKeyCaptureResult;
begin
  Result := Default(TWeChatKeyCaptureResult);

  // 1. 首先尝试已保存的密钥
  if TrySavedKeys then
  begin
    Result.State := wpsKeyVerified;
    Result.WeChatVersion := '4.x (saved keys)';
    Exit;
  end;

  // 1.5 BUG-052 #91: 版本自适应提取链 (saved_keys → version_specific → entropy_scan)
  //     候选密钥用 contact.db 页1 HMAC 自验证, 不依赖单一版本偏移。
  LPid := FindWeChatProcess;
  if LPid <> 0 then
  begin
    FWeChatPid := LPid;
    SetState(wpsRunning);
    SetState(wpsScanning);
    LResult := TryExtractWithChain;
    if LResult.IsSuccess then
    begin
      SetState(wpsKeyFound);
      if SaveCapturedKey(LResult) then
        VerifyAndActivate(LResult);
      Result := LResult;
      Exit;
    end;
    // 链失败 → 回退到下面逻辑 (HybridTap 或报错)
  end;

  // 2. 检查微信是否已在运行
  if LPid = 0 then
    LPid := FindWeChatProcess;
  if LPid <> 0 then
  begin
    // 微信已运行，直接尝试内存扫描（不杀进程）
    FWeChatPid := LPid;
    SetState(wpsRunning);
    SetState(wpsScanning);
    LResult := ScanMemoryForKey;
    if LResult.IsSuccess then
    begin
      SetState(wpsKeyFound);
      if SaveCapturedKey(LResult) then
        VerifyAndActivate(LResult);
      Result := LResult;
      Exit;
    end;
    // 内存扫描失败

    // BUG-052 fix: 默认不自动重启微信 (HybridTap 会 KillWeChat + 重新启动,
    // 会打断用户已登录会话)。仅当调用方显式允许 (如用户确认后) 才走 HybridTap。
    if not AAllowRestartWeChat then
    begin
      Result.State := wpsFailed;
      Result.ErrorMessage := '内存扫描未找到密钥' +
        ' (可能需要管理员权限, 或微信版本偏移不匹配)' +
        ' — 如需 HybridTap 重启微信抓取请重试并确认';
      Exit;
    end;

    // 用户已确认: HybridTap (会杀进程并重启)
    if TryHybridTapCapture then
    begin
      Result.State := wpsKeyVerified;
      Result.WeChatVersion := '4.x (HybridTap)';
      Exit;
    end;

    Result.State := wpsFailed;
    Result.ErrorMessage := 'Key capture failed (memory scan and HybridTap both failed)';
    Exit;
  end;

  // 3. 微信未运行: 启动微信后内存扫描
  if not LaunchWeChat then
  begin
    Result.State := wpsFailed;
    Result.ErrorMessage := 'Cannot launch WeChat';
    Exit;
  end;
  if not WaitForProcess(30000) then
  begin
    Result.State := wpsFailed;
    Result.ErrorMessage := 'Startup timeout';
    Exit;
  end;
  SetState(wpsScanning);
  LResult := ScanMemoryForKey;
  if LResult.IsSuccess then
  begin
    SetState(wpsKeyFound);
    if SaveCapturedKey(LResult) then
      VerifyAndActivate(LResult);
  end
  else
    SetState(wpsFailed);
  Result := LResult;
end;

end.