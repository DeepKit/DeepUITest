program WxDecryptProbe;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.PSAPI,
  Winapi.TlHelp32,
  Winapi.ShlObj;

{ ═══════════════════════════════════════════════════════════════
  WxDecryptProbe v0.2 — BCrypt Edition (Zero external DLL)

  Key recovery: ReadProcessMemory → entropy scan → key candidates
  Key derivation: BCrypt PBKDF2-HMAC-SHA1
  Decryption: BCrypt AES-256-CBC per-page (SQLCipher-compatible)
  Integrity: BCrypt HMAC-SHA1

  Build: dcc64 WxDecryptProbe.dpr
  ═══════════════════════════════════════════════════════════════ }

const
  WECHAT_PROCESS = 'Weixin.exe';
  WECHAT_DLL     = 'Weixin.dll';
  SQLITE_HEADER  = 'SQLite format 3'#0; // length = 16
  PAGE_SIZE      = 4096;
  KEY_SIZE       = 32;
  PBKDF2_ITER    = 64000;
  IV_SIZE        = 16;
  HMAC_SHA1_SIZE = 20;
  AES_BLOCK      = 16;

type
  TScanResult = record
    Path: string;
    AccountId: string;
    Version: string;
    DbFiles: TArray<string>;
    KeyFound: Boolean;
    KeyHex: string;
  end;

  TKeyCandidate = record
    Key: TBytes;
    Address: UInt64;
    Entropy: Double;
  end;

  { ─── BCrypt API (from bcrypt.h, built into Windows) ─── }
  BCRYPT_ALG_HANDLE = THandle;
  BCRYPT_HASH_HANDLE = THandle;
  BCRYPT_KEY_HANDLE = THandle;
  NTSTATUS = Cardinal;

const
  bcrypt = 'bcrypt.dll';

  BCRYPT_SHA1_ALGORITHM       = 'SHA1';
  BCRYPT_AES_ALGORITHM        = 'AES';
  BCRYPT_CHAIN_MODE_CBC       = 'ChainingModeCBC';
  BCRYPT_OBJECT_LENGTH        = 'ObjectLength';
  BCRYPT_HASH_LENGTH          = 'HashDigestLength';
  BCRYPT_CHAINING_MODE        = 'ChainingMode';

  BCRYPT_ALG_HANDLE_HMAC_FLAG = $00000008;

  TH32CS_SNAPMODULE32 = $00000010;

function BCryptOpenAlgorithmProvider(out hAlg: BCRYPT_ALG_HANDLE;
  const pszAlgId: LPCWSTR; pszImpl: LPCWSTR; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptCloseAlgorithmProvider(hAlg: BCRYPT_ALG_HANDLE;
  dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptGetProperty(hObject: THandle; const pszProperty: LPCWSTR;
  pbOutput: PBYTE; cbOutput: DWORD; var pcbResult: DWORD;
  dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptSetProperty(hObject: THandle; const pszProperty: LPCWSTR;
  pbInput: PBYTE; cbInput: DWORD; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptCreateHash(hAlg: BCRYPT_ALG_HANDLE;
  out hHash: BCRYPT_HASH_HANDLE; pbHashObject: PBYTE; cbHashObject: DWORD;
  pbSecret: PBYTE; cbSecret: DWORD; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptHashData(hHash: BCRYPT_HASH_HANDLE; pbInput: PBYTE;
  cbInput: DWORD; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptFinishHash(hHash: BCRYPT_HASH_HANDLE; pbOutput: PBYTE;
  cbOutput: DWORD; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptDestroyHash(hHash: BCRYPT_HASH_HANDLE): NTSTATUS; stdcall; external bcrypt;
function BCryptGenerateSymmetricKey(hAlg: BCRYPT_ALG_HANDLE;
  out hKey: BCRYPT_KEY_HANDLE; pbKeyObject: PBYTE; cbKeyObject: DWORD;
  pbSecret: PBYTE; cbSecret: DWORD; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptDestroyKey(hKey: BCRYPT_KEY_HANDLE): NTSTATUS; stdcall; external bcrypt;
function BCryptDecrypt(hKey: BCRYPT_KEY_HANDLE; pbInput: PBYTE; cbInput: DWORD;
  pPaddingInfo: Pointer; pbIV: PBYTE; cbIV: DWORD; pbOutput: PBYTE;
  cbOutput: DWORD; var pcbResult: DWORD; dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;
function BCryptDeriveKeyPBKDF2(hPrf: BCRYPT_ALG_HANDLE;
  pbPassword: PBYTE; cbPassword: DWORD; pbSalt: PBYTE; cbSalt: DWORD;
  cIterations: UInt64; pbDerivedKey: PBYTE; cbDerivedKey: DWORD;
  dwFlags: DWORD): NTSTATUS; stdcall; external bcrypt;

function IsNTSTATUS_Success(Status: NTSTATUS): Boolean; inline;
begin
  Result := (Status and $80000000) = 0;
end;

procedure CheckNTSTATUS(Status: NTSTATUS; const Msg: string);
begin
  if not IsNTSTATUS_Success(Status) then
    raise Exception.CreateFmt('%s (0x%x)', [Msg, Status]);
end;

{ ─── Process ─── }

function GetProcessIdByName(const AName: string): DWORD;
var
  Snap: THandle;
  PE: TProcessEntry32;
begin
  Result := 0;
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
    FillChar(PE, SizeOf(PE), 0);
    PE.dwSize := SizeOf(PE);
    if Process32First(Snap, PE) then
      repeat
        if SameText(PE.szExeFile, AName) then
          Exit(PE.th32ProcessID);
      until not Process32Next(Snap, PE);
  finally
    CloseHandle(Snap);
  end;
end;

function GetModuleBaseAddress(const APid: DWORD; const AModule: string): UInt64;
var
  Snap: THandle;
  ME: TModuleEntry32;
begin
  Result := 0;
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE or TH32CS_SNAPMODULE32, APid);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
    FillChar(ME, SizeOf(ME), 0);
    ME.dwSize := SizeOf(ME);
    if Module32First(Snap, ME) then
      repeat
        if SameText(ME.szModule, AModule) then
          Exit(UInt64(ME.modBaseAddr));
      until not Module32Next(Snap, ME);
  finally
    CloseHandle(Snap);
  end;
end;

function ReadProcessBytes(const AHandle: THandle; const AAddr: UInt64;
  out ABuf: TBytes; const ASize: Integer): Boolean;
var
  NumRead: NativeUInt;
begin
  SetLength(ABuf, ASize);
  NumRead := 0;
  Result := ReadProcessMemory(AHandle, Pointer(NativeUInt(AAddr)),
    @ABuf[0], ASize, NumRead) and (Integer(NumRead) = ASize);
end;

{ ─── Entropy ─── }

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
      Result := Result - P * Log2(P);
    end;
end;

{ ─── Memory Scan ─── }

function ScanForKeyInProcess(const AHandle: THandle; const ABase: UInt64;
  const ASize: NativeUInt): TArray<TKeyCandidate>;

  function LooksLikeKey(const B: TBytes): Boolean;
  var
    Zeros, I: Integer;
  begin
    if Length(B) <> KEY_SIZE then Exit(False);
    Zeros := 0;
    for I := 0 to KEY_SIZE - 1 do
      if B[I] = 0 then Inc(Zeros);
    Result := (Zeros < 24) and (CalcEntropy(B) > 7.0);
  end;

const
  BUF_SIZE = 262144;  // 256KB chunks for speed
var
  Buf: TBytes;
  Offset, Remaining, ChunkSize: NativeUInt;
  I, StepSize, CandidatesPerChunk: Integer;
  Pct, LastPct: Integer;
begin
  Result := [];
  SetLength(Buf, BUF_SIZE);
  Offset := 0;
  Remaining := ASize;
  LastPct := -1;

  // Step through every 8th byte for speed (key alignment doesn't matter for entropy)
  StepSize := 8;

  while (Remaining > 0) and (Length(Result) < 10) do
  begin
    ChunkSize := Min(NativeUInt(BUF_SIZE), Remaining);
    if not ReadProcessBytes(AHandle, ABase + Offset, Buf, Integer(ChunkSize)) then
      Break;

    CandidatesPerChunk := 0;
    I := 0;
    while (I <= Integer(ChunkSize) - KEY_SIZE) and (Length(Result) < 10) do
    begin
      var Candidate := Copy(Buf, I, KEY_SIZE);
      if LooksLikeKey(Candidate) then
      begin
        var KC: TKeyCandidate;
        KC.Key := Candidate;
        KC.Address := ABase + Offset + UInt64(I);
        KC.Entropy := CalcEntropy(Candidate);
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := KC;
        Inc(CandidatesPerChunk);
      end;
      Inc(I, StepSize);
    end;

    Inc(Offset, ChunkSize);
    if ChunkSize < Remaining then
      Dec(Remaining, ChunkSize)
    else
      Remaining := 0;

    Pct := Trunc((Offset / ASize) * 100);
    if (Pct <> LastPct) and (Pct mod 10 = 0) then
    begin
      Write(#13'  Scanning: ', Pct, '% (', Length(Result), ' candidates) ');
      LastPct := Pct;
    end;
  end;
  Write(#13'  Scanning: 100% (', Length(Result), ' candidates)   ');
end;

{ ─── BCrypt Key Derivation ─── }

procedure DeriveSQLCipherKey(const ARawKey, ASalt: TBytes;
  out AKey, AMacKey: TBytes);
var
  hSha1: BCRYPT_ALG_HANDLE;
  I: Integer;
  MacSalt: TBytes;
begin
  SetLength(AKey, KEY_SIZE);
  SetLength(AMacKey, KEY_SIZE);

  // Step 1: Open SHA1 algorithm provider
  CheckNTSTATUS(
    BCryptOpenAlgorithmProvider(hSha1, BCRYPT_SHA1_ALGORITHM, nil, 0),
    'BCryptOpenAlgorithmProvider(SHA1)');

  try
    // PBKDF2-HMAC-SHA1(raw_key, salt, 64000) -> AES key
    CheckNTSTATUS(
      BCryptDeriveKeyPBKDF2(hSha1, @ARawKey[0], Length(ARawKey),
        @ASalt[0], Length(ASalt), PBKDF2_ITER, @AKey[0], KEY_SIZE, 0),
      'BCryptDeriveKeyPBKDF2 (key)');

    // MAC salt = salt XOR 0x3a
    SetLength(MacSalt, Length(ASalt));
    for I := 0 to Length(ASalt) - 1 do
      MacSalt[I] := ASalt[I] xor $3a;

    // PBKDF2-HMAC-SHA1(AES_key, mac_salt, 2) -> MAC key
    CheckNTSTATUS(
      BCryptDeriveKeyPBKDF2(hSha1, @AKey[0], Length(AKey),
        @MacSalt[0], Length(MacSalt), 2, @AMacKey[0], KEY_SIZE, 0),
      'BCryptDeriveKeyPBKDF2 (mac_key)');
  finally
    BCryptCloseAlgorithmProvider(hSha1, 0);
  end;
end;

{ ─── BCrypt HMAC-SHA1 ─── }

function ComputeHMAC(const AData: TBytes; const AMacKey: TBytes;
  APageNum: Integer): TBytes;
var
  hSha1: BCRYPT_ALG_HANDLE;
  hHash: BCRYPT_HASH_HANDLE;
  PageLE: Integer;
begin
  SetLength(Result, HMAC_SHA1_SIZE);

  CheckNTSTATUS(
    BCryptOpenAlgorithmProvider(hSha1, BCRYPT_SHA1_ALGORITHM, nil,
      BCRYPT_ALG_HANDLE_HMAC_FLAG),
    'BCryptOpenAlgorithmProvider(SHA1 HMAC)');

  try
    CheckNTSTATUS(
      BCryptCreateHash(hSha1, hHash, nil, 0, @AMacKey[0], Length(AMacKey), 0),
      'BCryptCreateHash');
    try
      CheckNTSTATUS(BCryptHashData(hHash, @AData[0], Length(AData), 0),
        'BCryptHashData');
      PageLE := APageNum;
      CheckNTSTATUS(BCryptHashData(hHash, @PageLE, SizeOf(PageLE), 0),
        'BCryptHashData(page)');
      CheckNTSTATUS(BCryptFinishHash(hHash, @Result[0], HMAC_SHA1_SIZE, 0),
        'BCryptFinishHash');
    finally
      BCryptDestroyHash(hHash);
    end;
  finally
    BCryptCloseAlgorithmProvider(hSha1, 0);
  end;
end;

{ ─── BCrypt AES-256-CBC Decrypt ─── }

function DecryptPage(const AEncrypted: TBytes; const AKey: TBytes;
  const AIV: TBytes; APageNum, AReserve: Integer): TBytes;
var
  hAes: BCRYPT_ALG_HANDLE;
  hKey: BCRYPT_KEY_HANDLE;
  OutLen: DWORD;
  Offset: Integer;
  ChainBytes: TBytes;
  IVCopy: TBytes;
  InLen: Integer;
const
  ChainStr: string = 'ChainingModeCBC';
begin
  SetLength(Result, PAGE_SIZE);

  if APageNum = 1 then
  begin
    Move(PAnsiChar(SQLITE_HEADER)^, Result[0], 16);
    Offset := 16;
  end
  else
    Offset := 0;

  CheckNTSTATUS(
    BCryptOpenAlgorithmProvider(hAes, BCRYPT_AES_ALGORITHM, nil, 0),
    'AES open');
  try
    SetLength(ChainBytes, (Length(ChainStr) + 1) * SizeOf(Char));
    Move(PChar(ChainStr)^, ChainBytes[0], Length(ChainStr) * SizeOf(Char));

    CheckNTSTATUS(
      BCryptSetProperty(hAes, BCRYPT_CHAINING_MODE,
        @ChainBytes[0], Length(ChainBytes), 0),
      'CBC mode');

    CheckNTSTATUS(
      BCryptGenerateSymmetricKey(hAes, hKey, nil, 0,
        @AKey[0], KEY_SIZE, 0),
      'GenKey');
    try
      InLen := PAGE_SIZE - AReserve - Offset;
      SetLength(IVCopy, Length(AIV));
      Move(AIV[0], IVCopy[0], Length(AIV));

      OutLen := 0;
      CheckNTSTATUS(
        BCryptDecrypt(hKey, @AEncrypted[Offset], InLen, nil,
          @IVCopy[0], Length(IVCopy), @Result[Offset], InLen, OutLen, 0),
        'Decrypt');

      Move(AEncrypted[PAGE_SIZE - AReserve], Result[PAGE_SIZE - AReserve], AReserve);
    finally
      BCryptDestroyKey(hKey);
    end;
  finally
    BCryptCloseAlgorithmProvider(hAes, 0);
  end;
end;

{ ─── Database Decryption ─── }

function TryDecryptDB(const ADbPath, AOutPath: string;
  const AKey, AMacKey: TBytes): Boolean;
var
  InStream, OutStream: TFileStream;
  FileSize: Int64;
  Salt: TBytes;
  PageBuf, ExpectedMac, ComputedMac, IV: TBytes;
  NumPages, Reserve, DataLen, Page: Integer;
  DecPage: TBytes;
begin
  Result := False;
  if not TFile.Exists(ADbPath) then Exit;

  InStream := TFileStream.Create(ADbPath, fmOpenRead or fmShareDenyNone);
  try
    FileSize := InStream.Size;

    // Read salt (first 16 bytes)
    SetLength(Salt, 16);
    InStream.Read(Salt[0], 16);

    Reserve := IV_SIZE + HMAC_SHA1_SIZE;
    if (Reserve mod AES_BLOCK) <> 0 then
      Reserve := ((Reserve div AES_BLOCK) + 1) * AES_BLOCK;

    NumPages := FileSize div PAGE_SIZE;
    InStream.Position := 0;

    SetLength(PageBuf, PAGE_SIZE);
    SetLength(ExpectedMac, HMAC_SHA1_SIZE);
    SetLength(IV, IV_SIZE);
    DataLen := PAGE_SIZE - Reserve;

    OutStream := TFileStream.Create(AOutPath, fmCreate);
    try
      for Page := 1 to NumPages do
      begin
        InStream.Read(PageBuf[0], PAGE_SIZE);

        // Extract expected HMAC from page trailer
        Move(PageBuf[PAGE_SIZE - Reserve + IV_SIZE], ExpectedMac[0], HMAC_SHA1_SIZE);

        // Verify HMAC
        var DataForHMAC := Copy(PageBuf, 0, DataLen);
        ComputedMac := ComputeHMAC(DataForHMAC, AMacKey, Page);
        if not CompareMem(@ComputedMac[0], @ExpectedMac[0], HMAC_SHA1_SIZE) then
          Exit; // HMAC verification failed

        // Extract IV
        Move(PageBuf[PAGE_SIZE - Reserve], IV[0], IV_SIZE);

        // Decrypt page
        DecPage := DecryptPage(PageBuf, AKey, IV, Page, Reserve);
        OutStream.Write(DecPage[0], PAGE_SIZE);

        if Page mod 200 = 0 then
          Write(#13'  ', Page, '/', NumPages);
      end;

      WriteLn(#13'  ', NumPages, '/', NumPages, ' OK');
      Result := True;
    finally
      OutStream.Free;
    end;
  finally
    InStream.Free;
  end;
end;

{ ─── User Profile Scan ─── }

function FindWeChatDataRoots: TArray<string>;
var
  Docs: string;
  Alt: TArray<string>;
  I: Integer;
begin
  SetLength(Result, 0);
  // WeChat 4.x: D:\xwechat_files\
  if TDirectory.Exists('D:\xwechat_files\') then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'D:\xwechat_files\';
  end;
  // WeChat 3.x: Documents\WeChat Files\
  Docs := TPath.GetDocumentsPath + '\WeChat Files\';
  if TDirectory.Exists(Docs) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Docs;
  end;
  // Alternative
  SetLength(Alt, 3);
  Alt[0] := 'E:\xwechat_files\';  Alt[1] := 'C:\xwechat_files\';
  Alt[2] := 'E:\WeChat Files\';
  for I := 0 to High(Alt) do
    if TDirectory.Exists(Alt[I]) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Alt[I];
    end;
end;

function ScanWeChatData: TArray<TScanResult>;
var
  Roots, Dirs, AllDBs: TArray<string>;
  Root, Dir, AccountId, MsgDir, DB: string;
  SR: TScanResult;
  RelevantDBs: TList<string>;
  I: Integer;
  DBName: string;
begin
  SetLength(Result, 0);
  Roots := FindWeChatDataRoots;

  for Root in Roots do
  begin
    WriteLn('Scanning: ', Root);
    Dirs := TDirectory.GetDirectories(Root);

    for Dir in Dirs do
    begin
      AccountId := TPath.GetFileName(Dir);
      // Skip system dirs
      if AccountId.StartsWith('.') then Continue;
      if SameText(AccountId, 'All Users') then Continue;
      if SameText(AccountId, 'config') then Continue;

      MsgDir := Dir + '\Msg';
      if TDirectory.Exists(MsgDir) then
      begin
        AllDBs := TDirectory.GetFiles(MsgDir, '*.db', TSearchOption.soAllDirectories);
      end else
      begin
        // WeChat 4.x: db_storage/
        MsgDir := Dir + '\db_storage';
        if TDirectory.Exists(MsgDir) then
          AllDBs := TDirectory.GetFiles(MsgDir, '*.db', TSearchOption.soAllDirectories);
      end;

      if Length(AllDBs) = 0 then Continue;
      RelevantDBs := TList<string>.Create;
      try
        for DB in AllDBs do
        begin
          DBName := TPath.GetFileName(DB).ToLower;
          if DBName.Contains('msg') or DBName.Contains('contact') or
             DBName.Contains('micro') or DBName.Contains('chat') then
            RelevantDBs.Add(DB);
        end;

        if RelevantDBs.Count = 0 then Continue;

        FillChar(SR, SizeOf(SR), 0);
        SR.Path := Dir;
        SR.AccountId := AccountId;
        SR.DbFiles := RelevantDBs.ToArray;
        SR.KeyFound := False;

        WriteLn('  Account: ', AccountId, ' (', RelevantDBs.Count, ' DBs)');
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := SR;
      finally
        RelevantDBs.Free;
      end;
    end;
  end;
end;

{ ─── Main ─── }

procedure RunProbe;
var
  Accounts: TArray<TScanResult>;
  Pid: DWORD;
  HProcess: THandle;
  DllBase: UInt64;
  KeyList: TArray<TKeyCandidate>;
  DecryptDir, TargetDB, DBName: string;
  Salt, AesKey, MacKey: TBytes;
  FS: TFileStream;
  Found: Boolean;
  I, J, K: Integer;
  KeyBuf: TBytes;
  KnownOffsets: TArray<UInt64>;
  ModInfo: TModuleInfo;
begin
  WriteLn('═══════════════════════════════════════════');
  WriteLn('  DeepAxis WxDecryptProbe v0.2 (BCrypt)');
  WriteLn('  WeChat SQLCipher Probe - No ext deps');
  WriteLn('═══════════════════════════════════════════');
  WriteLn;

  // A0: Find WeChat data
  WriteLn('[A0] Scanning for WeChat data...');
  Accounts := ScanWeChatData;
  if Length(Accounts) = 0 then
  begin
    WriteLn('ERROR: No WeChat data directories found.');
    WriteLn('Looked in: %USERPROFILE%\Documents\WeChat Files\');
    WriteLn('           D:\WeChat Files\');
    Exit;
  end;

  // A1: Locate WeChat process
  WriteLn;
  WriteLn('[A1] Locating WeChat process...');
  Pid := GetProcessIdByName(WECHAT_PROCESS);
  if Pid = 0 then
  begin
    WriteLn('ERROR: Weixin.exe (WeChat 4.x) is not running.');
    WriteLn('Start WeChat and re-run.');
    Exit;
  end;

  HProcess := OpenProcess(PROCESS_VM_READ or PROCESS_QUERY_INFORMATION, False, Pid);
  if HProcess = 0 then
  begin
    WriteLn('ERROR: Cannot open WeChat process. Run as Administrator.');
    Exit;
  end;
  WriteLn('  WeChat PID: ', Pid);

  DllBase := GetModuleBaseAddress(Pid, WECHAT_DLL);
  if DllBase = 0 then
  begin
    WriteLn('ERROR: Cannot find WeChatWin.dll.');
    CloseHandle(HProcess);
    Exit;
  end;
  WriteLn('  WeChatWin.dll base: 0x', IntToHex(DllBase, 16));

  // A2: Memory scan
  WriteLn;
  WriteLn('[A2] Scanning WeChat memory for key...');
  FillChar(ModInfo, SizeOf(ModInfo), 0);
  if not GetModuleInformation(HProcess, THandle(DllBase), @ModInfo,
    SizeOf(ModInfo)) then
  begin
    WriteLn('ERROR: Cannot get WeChatWin.dll module info.');
    CloseHandle(HProcess);
    Exit;
  end;

  WriteLn('  Module size: ', ModInfo.SizeOfImage div 1024, ' KB');
  Write('  Scanning... ');
  KeyList := ScanForKeyInProcess(HProcess, DllBase, ModInfo.SizeOfImage);
  WriteLn(Length(KeyList), ' high-entropy 32B candidates found');

  if Length(KeyList) = 0 then
  begin
    WriteLn('  Attempting known offsets...');
    KnownOffsets := TArray<UInt64>.Create(
      $1131B64,    // v2.6.6.25
      $1A30000,    // v3.0-3.6
      $1F0B000,    // v3.9.0-3.9.5
      $1F30000,    // v3.9.6-3.9.12
      $2100000     // v4.0.x
    );
    for I := 0 to High(KnownOffsets) do
    begin
      if ReadProcessBytes(HProcess, DllBase + KnownOffsets[I], KeyBuf, KEY_SIZE) then
      begin
        var KC: TKeyCandidate;
        KC.Key := KeyBuf;
        KC.Address := DllBase + KnownOffsets[I];
        KC.Entropy := CalcEntropy(KeyBuf);
        SetLength(KeyList, Length(KeyList) + 1);
        KeyList[High(KeyList)] := KC;
      end;
    end;
    WriteLn('  Fallback: ', Length(KeyList), ' candidates');
  end;

  CloseHandle(HProcess);

  if Length(KeyList) = 0 then
  begin
    WriteLn;
    WriteLn('  FAILED: No key candidates found.');
    WriteLn('  WeChat version may be unsupported.');
    Exit;
  end;

  // Sort by entropy (highest first)
  TArray.Sort<TKeyCandidate>(KeyList,
    TComparer<TKeyCandidate>.Construct(
      function(const A, B: TKeyCandidate): Integer
      begin
        if B.Entropy > A.Entropy then Result := 1
        else if B.Entropy < A.Entropy then Result := -1
        else Result := 0;
      end));

  // A3: Try key on MicroMsg.db
  WriteLn;
  WriteLn('[A3] Testing keys against databases...');
  DecryptDir := TPath.GetTempPath + 'DeepAxisProbe\';
  ForceDirectories(DecryptDir);

  for I := 0 to High(Accounts) do
  begin
    TargetDB := '';
    for J := 0 to High(Accounts[I].DbFiles) do
    begin
      DBName := TPath.GetFileName(Accounts[I].DbFiles[J]).ToLower;
      // WeChat 4.x: message_0.db + contact.db, WeChat 3.x: MicroMsg.db
      if (DBName = 'message_0.db') or (DBName = 'contact.db') or (DBName = 'microMsg.db') then
      begin
        TargetDB := Accounts[I].DbFiles[J];
        Break;
      end;
    end;

    if TargetDB = '' then
    begin
      WriteLn('  No MicroMsg.db for ', Accounts[I].AccountId);
      Continue;
    end;

    WriteLn;
    WriteLn('  Account: ', Accounts[I].AccountId);
    WriteLn('  DB: ', TargetDB);
    WriteLn('  Size: ', TFile.GetSize(TargetDB) div 1024, ' KB');

    // Read salt
    SetLength(Salt, 16);
    FS := TFileStream.Create(TargetDB, fmOpenRead or fmShareDenyNone);
    try
      FS.Read(Salt[0], 16);
    finally
      FS.Free;
    end;

    Found := False;
    var MaxTest := Length(KeyList);
    if MaxTest > 10 then MaxTest := 10;

    for K := 0 to MaxTest - 1 do
    begin
      Write('    Key[', K+1, '] 0x', IntToHex(KeyList[K].Address, 16),
        ' E=', KeyList[K].Entropy:4:2, ' ... ');

      var OutFile := DecryptDir + 'MicroMsg_' + Accounts[I].AccountId + '_decrypted.db';
      if TFile.Exists(OutFile) then TFile.Delete(OutFile);

      DeriveSQLCipherKey(KeyList[K].Key, Salt, AesKey, MacKey);

      if TryDecryptDB(TargetDB, OutFile, AesKey, MacKey) then
      begin
        WriteLn('OK');
        WriteLn('    Key addr: 0x', IntToHex(KeyList[K].Address, 16));
        Write('    Raw key: ');
        for var B in KeyList[K].Key do
          Write(IntToHex(B, 2));
        WriteLn;
        WriteLn('    Decrypted: ', OutFile,
          ' (', TFile.GetSize(OutFile) div 1024, ' KB)');

        Accounts[I].KeyFound := True;
        Accounts[I].KeyHex := '';
        for var B in KeyList[K].Key do
          Accounts[I].KeyHex := Accounts[I].KeyHex + IntToHex(B, 2);
        Found := True;
        Break;
      end;
      WriteLn('no match');
    end;

    if not Found then
      WriteLn('    FAILED: No valid key found');
  end;

  // Results
  WriteLn;
  WriteLn('═══════════════════════════════════════════');
  WriteLn('  RESULTS');
  WriteLn('═══════════════════════════════════════════');
  for I := 0 to High(Accounts) do
  begin
    if Accounts[I].KeyFound then
      WriteLn('  + ', Accounts[I].AccountId, ' - DECRYPTED')
    else
      WriteLn('  - ', Accounts[I].AccountId, ' - FAILED');
  end;
  WriteLn;
  WriteLn('  Decrypted in: ', DecryptDir);
end;

begin
  try
    RunProbe;
    WriteLn;
    Write('Press Enter...');
    ReadLn;
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('FATAL: ', E.Message);
      WriteLn(E.ClassName);
      ReadLn;
    end;
  end;
end.
