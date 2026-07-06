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
  WxDecryptProbe v0.3 — Weixin 4.x diagnostic edition

  Key recovery: ReadProcessMemory → entropy scan → key candidates
  Scope: module inventory + readable process memory + hex key strings
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
  MAX_KEY_CANDIDATES = 1024;
  RAW_KEY_ENTROPY_MIN = 4.55; // 32-byte sample max is log2(32)=5.0
  MEM_SCAN_MAX_BYTES: UInt64 = UInt64(1536) * 1024 * 1024;

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
    Source: string;
  end;

  TModuleEntry = record
    Name: string;
    Path: string;
    Base: UInt64;
    Size: Cardinal;
  end;

  TMemoryScanStats = record
    RegionsSeen: Integer;
    RegionsScanned: Integer;
    BytesScanned: UInt64;
    ReadFailures: Integer;
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

function BytesToHex(const AData: TBytes; AMaxBytes: Integer = MaxInt): string;
var
  I, N: Integer;
begin
  Result := '';
  N := Min(Length(AData), AMaxBytes);
  for I := 0 to N - 1 do
    Result := Result + IntToHex(AData[I], 2);
end;

function BytesToSpacedHex(const AData: TBytes; AMaxBytes: Integer): string;
var
  I, N: Integer;
begin
  Result := '';
  N := Min(Length(AData), AMaxBytes);
  for I := 0 to N - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToHex(AData[I], 2);
  end;
end;

function BytesToAsciiPreview(const AData: TBytes; AMaxBytes: Integer): string;
var
  I, N: Integer;
begin
  Result := '';
  N := Min(Length(AData), AMaxBytes);
  for I := 0 to N - 1 do
    if (AData[I] >= 32) and (AData[I] <= 126) then
      Result := Result + Char(AData[I])
    else
      Result := Result + '.';
end;

function IsHexByte(C: Byte): Boolean; inline;
begin
  Result := ((C >= Ord('0')) and (C <= Ord('9'))) or
            ((C >= Ord('a')) and (C <= Ord('f'))) or
            ((C >= Ord('A')) and (C <= Ord('F')));
end;

function HexNibble(C: Byte): Byte; inline;
begin
  if (C >= Ord('0')) and (C <= Ord('9')) then
    Result := C - Ord('0')
  else if (C >= Ord('a')) and (C <= Ord('f')) then
    Result := C - Ord('a') + 10
  else
    Result := C - Ord('A') + 10;
end;

function Hex64ToBytes(const AData: TBytes; AOffset: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, KEY_SIZE);
  for I := 0 to KEY_SIZE - 1 do
    Result[I] := (HexNibble(AData[AOffset + I * 2]) shl 4) or
                 HexNibble(AData[AOffset + I * 2 + 1]);
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

function EnumerateProcessModules(const APid: DWORD): TArray<TModuleEntry>;
var
  Snap: THandle;
  ME: TModuleEntry32;
  M: TModuleEntry;
begin
  Result := [];
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPMODULE or TH32CS_SNAPMODULE32, APid);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
    FillChar(ME, SizeOf(ME), 0);
    ME.dwSize := SizeOf(ME);
    if Module32First(Snap, ME) then
      repeat
        M.Name := ME.szModule;
        M.Path := ME.szExePath;
        M.Base := UInt64(ME.modBaseAddr);
        M.Size := ME.modBaseSize;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := M;
      until not Module32Next(Snap, ME);
  finally
    CloseHandle(Snap);
  end;
end;

function FindModuleByName(const AModules: TArray<TModuleEntry>;
  const AName: string; out AModule: TModuleEntry): Boolean;
var
  I: Integer;
begin
  Result := False;
  AModule.Name := '';
  AModule.Path := '';
  AModule.Base := 0;
  AModule.Size := 0;
  for I := 0 to High(AModules) do
    if SameText(AModules[I].Name, AName) then
    begin
      AModule := AModules[I];
      Exit(True);
    end;
end;

procedure PrintModuleInventory(const AModules: TArray<TModuleEntry>);
var
  I, J: Integer;
  Sorted: TArray<TModuleEntry>;
  Tmp: TModuleEntry;
begin
  Sorted := Copy(AModules, 0, Length(AModules));
  for I := 0 to High(Sorted) - 1 do
    for J := I + 1 to High(Sorted) do
      if Sorted[J].Size > Sorted[I].Size then
      begin
        Tmp := Sorted[I];
        Sorted[I] := Sorted[J];
        Sorted[J] := Tmp;
      end;

  WriteLn('  Modules: ', Length(Sorted));
  for I := 0 to Min(High(Sorted), 24) do
    WriteLn('    ', Format('%6.1f MB  0x%s  %s',
      [Sorted[I].Size / 1024 / 1024, IntToHex(Sorted[I].Base, 16),
       Sorted[I].Name]));
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

function LooksLikeRawKey(const B: TBytes): Boolean;
var
  Freq: array[0..255] of Integer;
  I, Zeros, Unique, MaxFreq: Integer;
begin
  if Length(B) <> KEY_SIZE then Exit(False);
  FillChar(Freq, SizeOf(Freq), 0);
  Zeros := 0;
  for I := 0 to KEY_SIZE - 1 do
  begin
    if B[I] = 0 then Inc(Zeros);
    Inc(Freq[B[I]]);
  end;

  Unique := 0;
  MaxFreq := 0;
  for I := 0 to 255 do
    if Freq[I] > 0 then
    begin
      Inc(Unique);
      if Freq[I] > MaxFreq then
        MaxFreq := Freq[I];
    end;

  Result := (Zeros <= 3) and (Unique >= 24) and (MaxFreq <= 4) and
            (CalcEntropy(B) >= RAW_KEY_ENTROPY_MIN);
end;

procedure AddKeyCandidate(var AList: TArray<TKeyCandidate>; const AKey: TBytes;
  AAddress: UInt64; const ASource: string);
var
  KC: TKeyCandidate;
  I, MinIndex: Integer;
  MinEntropy: Double;
begin
  if not LooksLikeRawKey(AKey) then Exit;

  KC.Key := Copy(AKey, 0, Length(AKey));
  KC.Address := AAddress;
  KC.Entropy := CalcEntropy(AKey);
  KC.Source := ASource;

  for I := 0 to High(AList) do
    if (AList[I].Source = KC.Source) and
       (Abs(Int64(AList[I].Address) - Int64(KC.Address)) <= 64) then
    begin
      if KC.Entropy > AList[I].Entropy then
        AList[I] := KC;
      Exit;
    end;

  if Length(AList) < MAX_KEY_CANDIDATES then
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := KC;
    Exit;
  end;

  MinIndex := 0;
  MinEntropy := AList[0].Entropy;
  for I := 1 to High(AList) do
    if AList[I].Entropy < MinEntropy then
    begin
      MinEntropy := AList[I].Entropy;
      MinIndex := I;
    end;

  if KC.Entropy > MinEntropy then
    AList[MinIndex] := KC;
end;

function ScanBufferForKeys(const ABuf: TBytes; ABase: UInt64;
  const ASource: string; ARawStep: Integer): TArray<TKeyCandidate>;
var
  I, J: Integer;
  Candidate: TBytes;
  IsHexRun: Boolean;
begin
  Result := [];
  if ARawStep < 1 then
    ARawStep := 1;

  I := 0;
  while I <= Length(ABuf) - KEY_SIZE do
  begin
    Candidate := Copy(ABuf, I, KEY_SIZE);
    AddKeyCandidate(Result, Candidate, ABase + UInt64(I), ASource + ':raw32');
    Inc(I, ARawStep);
  end;

  I := 0;
  while I <= Length(ABuf) - KEY_SIZE * 2 do
  begin
    IsHexRun := True;
    for J := 0 to KEY_SIZE * 2 - 1 do
      if not IsHexByte(ABuf[I + J]) then
      begin
        IsHexRun := False;
        Break;
      end;

    if IsHexRun then
    begin
      Candidate := Hex64ToBytes(ABuf, I);
      AddKeyCandidate(Result, Candidate, ABase + UInt64(I), ASource + ':hex64');
      Inc(I, KEY_SIZE * 2);
    end
    else
      Inc(I);
  end;
end;

procedure AppendCandidates(var ADest: TArray<TKeyCandidate>;
  const ASource: TArray<TKeyCandidate>);
var
  I: Integer;
begin
  for I := 0 to High(ASource) do
    AddKeyCandidate(ADest, ASource[I].Key, ASource[I].Address, ASource[I].Source);
end;

function ScanForKeyInProcess(const AHandle: THandle; const ABase: UInt64;
  const ASize: NativeUInt): TArray<TKeyCandidate>;
const
  BUF_SIZE = 1048576;  // 1MB chunks
var
  Buf: TBytes;
  Offset, Remaining, ChunkSize: NativeUInt;
  Pct, LastPct: Integer;
begin
  Result := [];
  SetLength(Buf, BUF_SIZE);
  Offset := 0;
  Remaining := ASize;
  LastPct := -1;

  while (Remaining > 0) and (Length(Result) < MAX_KEY_CANDIDATES) do
  begin
    ChunkSize := Min(NativeUInt(BUF_SIZE), Remaining);
    if not ReadProcessBytes(AHandle, ABase + Offset, Buf, Integer(ChunkSize)) then
      Break;

    AppendCandidates(Result, ScanBufferForKeys(Copy(Buf, 0, Integer(ChunkSize)),
      ABase + Offset, 'module', 4));

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

function IsReadableProtect(AProtect: DWORD): Boolean;
var
  BaseProtect: DWORD;
begin
  if (AProtect and PAGE_GUARD) <> 0 then Exit(False);
  if (AProtect and PAGE_NOACCESS) <> 0 then Exit(False);

  BaseProtect := AProtect and $FF;
  Result := BaseProtect in [
    PAGE_READONLY,
    PAGE_READWRITE,
    PAGE_WRITECOPY,
    PAGE_EXECUTE_READ,
    PAGE_EXECUTE_READWRITE,
    PAGE_EXECUTE_WRITECOPY
  ];
end;

function IsWritableProtect(AProtect: DWORD): Boolean;
var
  BaseProtect: DWORD;
begin
  if (AProtect and PAGE_GUARD) <> 0 then Exit(False);
  if (AProtect and PAGE_NOACCESS) <> 0 then Exit(False);

  BaseProtect := AProtect and $FF;
  Result := BaseProtect in [
    PAGE_READWRITE,
    PAGE_WRITECOPY,
    PAGE_EXECUTE_READWRITE,
    PAGE_EXECUTE_WRITECOPY
  ];
end;

function ScanReadableMemoryForKeys(const AHandle: THandle;
  out AStats: TMemoryScanStats): TArray<TKeyCandidate>;
const
  BUF_SIZE = 1048576;
var
  MBI: TMemoryBasicInformation;
  Addr, NextAddr, RegionBase, RegionSize, RegionOffset, ChunkSize: UInt64;
  Buf: TBytes;
  BytesRead: NativeUInt;
begin
  Result := [];
  FillChar(AStats, SizeOf(AStats), 0);
  Addr := 0;
  SetLength(Buf, BUF_SIZE);

  while (Addr < High(NativeUInt)) and
        (AStats.BytesScanned < MEM_SCAN_MAX_BYTES) do
  begin
    if VirtualQueryEx(AHandle, Pointer(NativeUInt(Addr)), MBI, SizeOf(MBI)) = 0 then
      Break;

    Inc(AStats.RegionsSeen);
    RegionBase := UInt64(NativeUInt(MBI.BaseAddress));
    RegionSize := UInt64(MBI.RegionSize);
    NextAddr := RegionBase + RegionSize;
    if NextAddr <= Addr then
      Break;

    if (MBI.State = MEM_COMMIT) and (MBI.Type_9 = MEM_PRIVATE) and
       IsWritableProtect(MBI.Protect) then
    begin
      Inc(AStats.RegionsScanned);
      RegionOffset := 0;
      while (RegionOffset < RegionSize) and
            (AStats.BytesScanned < MEM_SCAN_MAX_BYTES) do
      begin
        ChunkSize := Min(UInt64(BUF_SIZE), RegionSize - RegionOffset);
        if AStats.BytesScanned + ChunkSize > MEM_SCAN_MAX_BYTES then
          ChunkSize := MEM_SCAN_MAX_BYTES - AStats.BytesScanned;

        BytesRead := 0;
        if ReadProcessMemory(AHandle, Pointer(NativeUInt(RegionBase + RegionOffset)),
          @Buf[0], NativeUInt(ChunkSize), BytesRead) and (BytesRead > 0) then
        begin
          AppendCandidates(Result, ScanBufferForKeys(Copy(Buf, 0, Integer(BytesRead)),
            RegionBase + RegionOffset, 'mem', 8));
          Inc(AStats.BytesScanned, BytesRead);
        end
        else
        begin
          Inc(AStats.ReadFailures);
          Inc(AStats.BytesScanned, ChunkSize);
        end;

        Inc(RegionOffset, ChunkSize);
      end;
    end;

    Addr := NextAddr;
  end;
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
    BCryptOpenAlgorithmProvider(hSha1, BCRYPT_SHA1_ALGORITHM, nil,
      BCRYPT_ALG_HANDLE_HMAC_FLAG),
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
  const AIV: TBytes; APageNum, AReserve, APageSize: Integer): TBytes;
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
  SetLength(Result, APageSize);

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
      InLen := APageSize - AReserve - Offset;
      SetLength(IVCopy, Length(AIV));
      Move(AIV[0], IVCopy[0], Length(AIV));

      OutLen := 0;
      CheckNTSTATUS(
        BCryptDecrypt(hKey, @AEncrypted[Offset], InLen, nil,
          @IVCopy[0], Length(IVCopy), @Result[Offset], InLen, OutLen, 0),
        'Decrypt');

      Move(AEncrypted[APageSize - AReserve], Result[APageSize - AReserve], AReserve);
    finally
      BCryptDestroyKey(hKey);
    end;
  finally
    BCryptCloseAlgorithmProvider(hAes, 0);
  end;
end;

{ ─── Database Decryption ─── }

function TryDecryptDB(const ADbPath, AOutPath: string;
  const AKey, AMacKey: TBytes; APageSize: Integer): Boolean;
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

    if (FileSize < APageSize) or ((FileSize mod APageSize) <> 0) then
      Exit;

    NumPages := FileSize div APageSize;
    InStream.Position := 0;

    SetLength(PageBuf, APageSize);
    SetLength(ExpectedMac, HMAC_SHA1_SIZE);
    SetLength(IV, IV_SIZE);
    DataLen := APageSize - Reserve;

    OutStream := TFileStream.Create(AOutPath, fmCreate);
    try
      for Page := 1 to NumPages do
      begin
        InStream.Read(PageBuf[0], APageSize);

        // Extract expected HMAC from page trailer
        Move(PageBuf[APageSize - Reserve + IV_SIZE], ExpectedMac[0], HMAC_SHA1_SIZE);

        // Verify HMAC
        var DataForHMAC := Copy(PageBuf, 0, DataLen);
        ComputedMac := ComputeHMAC(DataForHMAC, AMacKey, Page);
        if not CompareMem(@ComputedMac[0], @ExpectedMac[0], HMAC_SHA1_SIZE) then
          Exit; // HMAC verification failed

        // Extract IV
        Move(PageBuf[APageSize - Reserve], IV[0], IV_SIZE);

        // Decrypt page
        DecPage := DecryptPage(PageBuf, AKey, IV, Page, Reserve, APageSize);
        OutStream.Write(DecPage[0], APageSize);

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

function VerifySQLCipherFirstPage(const ADbPath: string; const AKey, AMacKey: TBytes;
  APageSize: Integer): Boolean;
var
  InStream: TFileStream;
  FileSize: Int64;
  PageBuf, ExpectedMac, ComputedMac, IV, DecPage: TBytes;
  Reserve, DataLen: Integer;
begin
  Result := False;
  if not TFile.Exists(ADbPath) then Exit;

  InStream := TFileStream.Create(ADbPath, fmOpenRead or fmShareDenyNone);
  try
    FileSize := InStream.Size;
    if (FileSize < APageSize) or ((FileSize mod APageSize) <> 0) then
      Exit;

    Reserve := IV_SIZE + HMAC_SHA1_SIZE;
    if (Reserve mod AES_BLOCK) <> 0 then
      Reserve := ((Reserve div AES_BLOCK) + 1) * AES_BLOCK;
    DataLen := APageSize - Reserve;

    SetLength(PageBuf, APageSize);
    SetLength(ExpectedMac, HMAC_SHA1_SIZE);
    SetLength(IV, IV_SIZE);
    InStream.Read(PageBuf[0], APageSize);

    Move(PageBuf[APageSize - Reserve + IV_SIZE], ExpectedMac[0], HMAC_SHA1_SIZE);
    ComputedMac := ComputeHMAC(Copy(PageBuf, 0, DataLen), AMacKey, 1);
    if not CompareMem(@ComputedMac[0], @ExpectedMac[0], HMAC_SHA1_SIZE) then
      Exit;

    Move(PageBuf[APageSize - Reserve], IV[0], IV_SIZE);
    DecPage := DecryptPage(PageBuf, AKey, IV, 1, Reserve, APageSize);
    Result := CompareMem(@DecPage[0], PAnsiChar(SQLITE_HEADER), Length(SQLITE_HEADER));
  finally
    InStream.Free;
  end;
end;

function TryCandidateOnDB(const ADbPath: string; const ARawKey: TBytes;
  out AAesKey, AMacKey: TBytes; out APageSize: Integer): Boolean;
const
  PAGE_SIZES: array[0..3] of Integer = (1024, 2048, 4096, 8192);
var
  I: Integer;
  Salt: TBytes;
  FS: TFileStream;
begin
  Result := False;
  APageSize := 0;
  SetLength(Salt, 16);

  FS := TFileStream.Create(ADbPath, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size < 1024 then
      Exit;
    FS.Read(Salt[0], 16);
  finally
    FS.Free;
  end;

  DeriveSQLCipherKey(ARawKey, Salt, AAesKey, AMacKey);
  for I := Low(PAGE_SIZES) to High(PAGE_SIZES) do
    if VerifySQLCipherFirstPage(ADbPath, AAesKey, AMacKey, PAGE_SIZES[I]) then
    begin
      APageSize := PAGE_SIZES[I];
      Exit(True);
    end;
end;

procedure ReportDatabaseFingerprint(const ADbPath: string);
const
  PAGE_SIZES: array[0..5] of Integer = (512, 1024, 2048, 4096, 8192, 16384);
var
  FS: TFileStream;
  Header: TBytes;
  FileSize: Int64;
  I: Integer;
  Mods: string;
begin
  if not TFile.Exists(ADbPath) then Exit;

  FS := TFileStream.Create(ADbPath, fmOpenRead or fmShareDenyNone);
  try
    FileSize := FS.Size;
    SetLength(Header, Min(64, Integer(FileSize)));
    if Length(Header) > 0 then
      FS.Read(Header[0], Length(Header));
  finally
    FS.Free;
  end;

  Mods := '';
  for I := Low(PAGE_SIZES) to High(PAGE_SIZES) do
  begin
    if Mods <> '' then
      Mods := Mods + ', ';
    if (FileSize mod PAGE_SIZES[I]) = 0 then
      Mods := Mods + IntToStr(PAGE_SIZES[I]) + ':yes'
    else
      Mods := Mods + IntToStr(PAGE_SIZES[I]) + ':no';
  end;

  WriteLn('  Size: ', FileSize div 1024, ' KB');
  WriteLn('  Header hex: ', BytesToSpacedHex(Header, 32));
  WriteLn('  Header txt: ', BytesToAsciiPreview(Header, 32));
  WriteLn('  File mod page-size: ', Mods);
  if (Length(Header) >= 16) and
     CompareMem(@Header[0], PAnsiChar(SQLITE_HEADER), Length(SQLITE_HEADER)) then
    WriteLn('  Header verdict: plaintext SQLite')
  else
    WriteLn('  Header verdict: encrypted or non-SQLite container');
end;

function GetTargetDbPriority(const ADbPath: string): Integer;
var
  DBName: string;
begin
  DBName := TPath.GetFileName(ADbPath).ToLower;
  Result := 100;
  if DBName = 'message_0.db' then
    Result := 0
  else if DBName = 'micromsg.db' then
    Result := 1
  else if DBName = 'contact.db' then
    Result := 2
  else if DBName.StartsWith('message_') and DBName.EndsWith('.db') then
    Result := 3
  else if DBName.StartsWith('msg') and DBName.EndsWith('.db') then
    Result := 4
  else if DBName.Contains('chat') and DBName.EndsWith('.db') then
    Result := 5
  else if DBName = 'key_info.db' then
    Result := 20;
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
      AllDBs := nil;
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
      WriteLn('  Candidate: ', AccountId, ' (', Length(AllDBs), ' raw DBs)');
      RelevantDBs := TList<string>.Create;
      try
        for DB in AllDBs do
        begin
          DBName := TPath.GetFileName(DB).ToLower;
          if DBName.Contains('message') or DBName.Contains('msg') or
             DBName.Contains('contact') or DBName.Contains('micro') or
             DBName.Contains('chat') or SameText(DBName, 'key_info.db') then
            RelevantDBs.Add(DB);
        end;

        if RelevantDBs.Count = 0 then Continue;

        SR.Path := '';
        SR.AccountId := '';
        SR.Version := '';
        SR.DbFiles := nil;
        SR.KeyFound := False;
        SR.KeyHex := '';
        SR.Path := Dir;
        SR.AccountId := AccountId;
        SR.DbFiles := RelevantDBs.ToArray;

        WriteLn('  Account: ', AccountId, ' (', RelevantDBs.Count, ' DBs)');
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := SR;
      finally
        RelevantDBs.Free;
      end;
    end;

    if Root.ToLower.Contains('xwechat_files') then
    begin
      AllDBs := TDirectory.GetFiles(Root, '*.db', TSearchOption.soAllDirectories);
      RelevantDBs := TList<string>.Create;
      try
        for DB in AllDBs do
        begin
          DBName := TPath.GetFileName(DB).ToLower;
          if DBName.Contains('message') or DBName.Contains('msg') or
             DBName.Contains('contact') or DBName.Contains('micro') or
             DBName.Contains('chat') or SameText(DBName, 'key_info.db') then
            RelevantDBs.Add(DB);
        end;

        if RelevantDBs.Count > 0 then
        begin
          SR.Path := Root;
          SR.AccountId := 'xwechat_files';
          SR.Version := '4.x';
          SR.DbFiles := RelevantDBs.ToArray;
          SR.KeyFound := False;
          SR.KeyHex := '';
          WriteLn('  Aggregate: xwechat_files (', RelevantDBs.Count, ' DBs)');
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := SR;
        end;
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
  KeyList: TArray<TKeyCandidate>;
  MemKeyList: TArray<TKeyCandidate>;
  Modules: TArray<TModuleEntry>;
  MainModule: TModuleEntry;
  MemStats: TMemoryScanStats;
  DecryptDir, TargetDB: string;
  AesKey, MacKey: TBytes;
  Found, Has4xSource: Boolean;
  I, J, K, PageSize, MaxTest, TargetPriority, CandidatePriority: Integer;
  KeyBuf: TBytes;
  KnownOffsets: TArray<UInt64>;
  VerboseKey: Boolean;
begin
  WriteLn('═══════════════════════════════════════════');
  WriteLn('  DeepAxis WxDecryptProbe v0.3 (Weixin 4.x)');
  WriteLn('  SQLCipher/WCDB diagnostic probe - no ext deps');
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

  Modules := EnumerateProcessModules(Pid);
  PrintModuleInventory(Modules);
  if not FindModuleByName(Modules, WECHAT_DLL, MainModule) then
  begin
    WriteLn('ERROR: Cannot find ', WECHAT_DLL, '.');
    CloseHandle(HProcess);
    Exit;
  end;
  WriteLn('  ', WECHAT_DLL, ' base: 0x', IntToHex(MainModule.Base, 16),
    ' size: ', MainModule.Size div 1024, ' KB');

  // A2: Memory scan
  WriteLn;
  WriteLn('[A2] Static module candidate scan skipped by default.');
  WriteLn('  Reason: ', WECHAT_DLL,
    ' image produces high-entropy code/data false positives.');
  KeyList := [];

  WriteLn('  Adding known-offset probes...');
  KnownOffsets := TArray<UInt64>.Create(
    $1131B64,    // v2.6.6.25
    $1A30000,    // v3.0-3.6
    $1F0B000,    // v3.9.0-3.9.5
    $1F30000,    // v3.9.6-3.9.12
    $2100000     // v4.0.x
  );
  for I := 0 to High(KnownOffsets) do
  begin
    if ReadProcessBytes(HProcess, MainModule.Base + KnownOffsets[I], KeyBuf, KEY_SIZE) then
    begin
      var KC: TKeyCandidate;
      KC.Key := Copy(KeyBuf, 0, Length(KeyBuf));
      KC.Address := MainModule.Base + KnownOffsets[I];
      KC.Entropy := CalcEntropy(KeyBuf);
      KC.Source := 'known-offset';
      SetLength(KeyList, Length(KeyList) + 1);
      KeyList[High(KeyList)] := KC;
    end;
  end;

  WriteLn;
  WriteLn('[A2b] Scanning readable process memory for key candidates...');
  MemKeyList := ScanReadableMemoryForKeys(HProcess, MemStats);
  AppendCandidates(KeyList, MemKeyList);
  WriteLn('  Regions: ', MemStats.RegionsScanned, '/', MemStats.RegionsSeen,
    ' scanned, ', MemStats.ReadFailures, ' read failures');
  WriteLn('  Bytes scanned: ', MemStats.BytesScanned div 1024 div 1024, ' MB');
  WriteLn('  Memory candidates: ', Length(MemKeyList));
  WriteLn('  Total candidates: ', Length(KeyList));

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

  Has4xSource := False;
  for I := 0 to High(Accounts) do
    if SameText(Accounts[I].Version, '4.x') then
      Has4xSource := True;

  for I := 0 to High(Accounts) do
  begin
    if Has4xSource and not SameText(Accounts[I].Version, '4.x') then
    begin
      WriteLn('  Skipping legacy source while 4.x source is present: ',
        Accounts[I].AccountId);
      Continue;
    end;

    TargetDB := '';
    TargetPriority := MaxInt;
    for J := 0 to High(Accounts[I].DbFiles) do
    begin
      CandidatePriority := GetTargetDbPriority(Accounts[I].DbFiles[J]);
      if CandidatePriority < TargetPriority then
      begin
        TargetDB := Accounts[I].DbFiles[J];
        TargetPriority := CandidatePriority;
      end;
    end;

    if TargetDB = '' then
    begin
      WriteLn('  No supported message/contact DB for ', Accounts[I].AccountId);
      Continue;
    end;

    WriteLn;
    WriteLn('  Account: ', Accounts[I].AccountId);
    WriteLn('  DB: ', TargetDB);
    ReportDatabaseFingerprint(TargetDB);

    Found := False;
    MaxTest := Length(KeyList);

    for K := 0 to MaxTest - 1 do
    begin
      VerboseKey := (K < 20) or (((K + 1) mod 100) = 0) or (K = MaxTest - 1);
      if VerboseKey then
        Write('    Key[', K+1, '/', MaxTest, '] 0x',
          IntToHex(KeyList[K].Address, 16), ' E=', KeyList[K].Entropy:4:2,
          ' ', KeyList[K].Source, ' ... ');

      if TryCandidateOnDB(TargetDB, KeyList[K].Key, AesKey, MacKey, PageSize) then
      begin
        if not VerboseKey then
          Write('    Key[', K+1, '/', MaxTest, '] 0x',
            IntToHex(KeyList[K].Address, 16), ' E=', KeyList[K].Entropy:4:2,
            ' ', KeyList[K].Source, ' ... ');
        WriteLn('OK page=', PageSize);
        WriteLn('    Key addr: 0x', IntToHex(KeyList[K].Address, 16));

        var OutFile := DecryptDir + Accounts[I].AccountId + '_' +
          TPath.GetFileNameWithoutExtension(TargetDB) + '_decrypted.db';
        if TFile.Exists(OutFile) then TFile.Delete(OutFile);
        if TryDecryptDB(TargetDB, OutFile, AesKey, MacKey, PageSize) then
          WriteLn('    Decrypted: ', OutFile,
            ' (', TFile.GetSize(OutFile) div 1024, ' KB)')
        else
          WriteLn('    First page matched, full decrypt failed.');

        WriteLn('    Raw key: ', BytesToHex(KeyList[K].Key));
        WriteLn('    Source: ', KeyList[K].Source);

        Accounts[I].KeyFound := True;
        Accounts[I].KeyHex := BytesToHex(KeyList[K].Key);
        Found := True;
        Break;
      end;

      if VerboseKey then
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
    if FindCmdLineSwitch('pause', True) then
    begin
      WriteLn;
      Write('Press Enter...');
      ReadLn;
    end;
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('FATAL: ', E.Message);
      WriteLn(E.ClassName);
      if FindCmdLineSwitch('pause', True) then
        ReadLn;
    end;
  end;
end.
