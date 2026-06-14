program WxDecryptProbe;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.Math,
  Winapi.Windows,
  Winapi.PSAPI,
  Winapi.TlHelp32,
  Winapi.ShellAPI,
  Winapi.ShlObj;

const
  WECHAT_DATA_ROOT = '\Documents\WeChat Files\';
  WECHAT_PROCESS    = 'WeChat.exe';
  WECHAT_DLL        = 'WeChatWin.dll';
  SQLITE_HEADER     = 'SQLite format 3'#0;
  PAGE_SIZE         = 4096;
  KEY_SIZE          = 32;
  PBKDF2_ITER       = 64000;
  IV_SIZE           = 16;
  HMAC_SIZE         = 20;
  AES_BLOCK         = 16;

type
  TScanResult = record
    Path: string;
    AccountId: string;
    WeChatVersion: string;
    DbFiles: TArray<string>;
    Readable: Boolean;
    FailureReason: string;
    KeyFound: Boolean;
    KeyHex: string;
  end;

  TKeyCandidate = record
    Key: TBytes;
    Address: UInt64;
    Entropy: Double;
  end;

{ ─── Process Memory ─── }

function GetProcessIdByName(const AName: string): DWORD;
var
  Snap: THandle;
  PE: TProcessEntry32;
begin
  Result := 0;
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
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
  Result := ReadProcessMemory(AHandle, Pointer(AAddr), @ABuf[0], ASize, NumRead)
    and (Integer(NumRead) = ASize);
end;

{ ─── Shannon Entropy ─── }

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

{ ─── Memory Scan for Key ─── }

function ScanForKeyInProcess(const AHandle: THandle; const ABase: UInt64;
  const ASize: NativeUInt): TArray<TKeyCandidate>;

  function IsHighEntropy(const B: TBytes): Boolean;
  begin
    Result := CalcEntropy(B) > 7.5;  // 8.0 = perfect random
  end;

  function LooksLikeKey(const B: TBytes): Boolean;
  var
    I, Zeros: Integer;
  begin
    // 32 bytes, high entropy, not all same byte
    if Length(B) <> KEY_SIZE then Exit(False);
    Zeros := 0;
    for I := 0 to KEY_SIZE - 1 do
      if B[I] = 0 then Inc(Zeros);
    Result := (Zeros < 24) and IsHighEntropy(B);
  end;

const
  BUF_SIZE = 65536;
var
  Buf: TBytes;
  Offset: NativeUInt;
  BytesRead: NativeUInt;
  Remaining: NativeUInt;
  I: Integer;
begin
  Result := [];
  SetLength(Buf, BUF_SIZE);
  Offset := 0;
  Remaining := ASize;

  while (Remaining > 0) and (Length(Result) < 20) do
  begin
    var ChunkSize := Min(BUF_SIZE, Remaining);
    if not ReadProcessMemory(AHandle, ABase + Offset, Buf, ChunkSize) then
      Break;

    for I := 0 to ChunkSize - KEY_SIZE do
    begin
      var Candidate := Copy(Buf, I, KEY_SIZE);
      if LooksLikeKey(Candidate) then
      begin
        var KC: TKeyCandidate;
        KC.Key := Candidate;
        KC.Address := ABase + Offset + UInt64(I);
        KC.Entropy := CalcEntropy(Candidate);
        Result := Result + [KC];
      end;
    end;

    Inc(Offset, ChunkSize - KEY_SIZE);
    Dec(Remaining, ChunkSize - KEY_SIZE);
  end;
end;

{ ─── Key Derivation: PBKDF2-HMAC-SHA1 ─── }

procedure DeriveSQLCipherKey(const ARawKey, ASalt: TBytes;
  out AKey, AMacKey: TBytes);
begin
  SetLength(AKey, KEY_SIZE);
  SetLength(AMacKey, KEY_SIZE);

  // PBKDF2-HMAC-SHA1(raw_key, salt, 64000) -> AES key
  PKCS5_PBKDF2_HMAC_SHA1(PAnsiChar(ARawKey), Length(ARawKey),
    @ASalt[0], Length(ASalt), PBKDF2_ITER, KEY_SIZE, @AKey[0]);

  // MAC salt = salt XOR 0x3A
  var MacSalt := Copy(ASalt);
  for var I := Low(MacSalt) to High(MacSalt) do
    MacSalt[I] := MacSalt[I] xor $3A;

  // PBKDF2-HMAC-SHA1(AES_key, mac_salt, 2) -> MAC key
  PKCS5_PBKDF2_HMAC_SHA1(PAnsiChar(AKey), Length(AKey),
    @MacSalt[0], Length(MacSalt), 2, KEY_SIZE, @AMacKey[0]);
end;

{ ─── HMAC Verification ─── }

function VerifyPageHMAC(const AData: TBytes; const AMacKey: TBytes;
  APageNum: Integer; const AExpectedMac: TBytes): Boolean;
var
  PageNumBytes: array[0..3] of Byte;
  Computed: array[0..19] of Byte;
  CompLen: Cardinal;
begin
  PInteger(@PageNumBytes[0])^ := APageNum;
  CompLen := HMAC_SIZE;

  var Ctx: HMAC_CTX;
  HMAC_CTX_Init(Ctx);
  HMAC_Init_ex(Ctx, @AMacKey[0], Length(AMacKey), EVP_SHA1, nil);
  HMAC_Update(Ctx, @AData[0], Length(AData));
  HMAC_Update(Ctx, @PageNumBytes[0], SizeOf(PageNumBytes));
  HMAC_Final(Ctx, @Computed[0], CompLen);
  HMAC_CTX_Cleanup(Ctx);

  Result := CompareMem(@Computed[0], @AExpectedMac[0], HMAC_SIZE);
end;

{ ─── Page Decryption: AES-256-CBC ─── }

function DecryptPage(const AEncrypted: TBytes; const AKey: TBytes;
  const AIV: TBytes; APageNum: Integer): TBytes;
var
  Ctx: PEVP_CIPHER_CTX;
  OutLen, TmpLen, Total: Integer;
  Reserve: Integer;
  Offset: Integer;
begin
  Reserve := IV_SIZE + HMAC_SIZE;
  Reserve := ((Reserve mod AES_BLOCK) = 0) and Reserve
    or ((Reserve div AES_BLOCK) + 1) * AES_BLOCK;

  SetLength(Result, PAGE_SIZE);

  if APageNum = 1 then
  begin
    // First page keeps SQLite header
    Move(PAnsiChar(SQLITE_HEADER)^, Result[0], 16);
    Offset := 16;
  end
  else
    Offset := 0;

  Ctx := EVP_CIPHER_CTX_new;
  try
    EVP_CipherInit_ex(Ctx, EVP_aes_256_cbc, nil, nil, nil, 0);
    EVP_CIPHER_CTX_set_padding(Ctx, 0);
    EVP_CipherInit_ex(Ctx, nil, nil, @AKey[0], @AIV[0], 0);
    EVP_CipherUpdate(Ctx, @Result[Offset], @OutLen,
      @AEncrypted[Offset], PAGE_SIZE - Reserve - Offset);
    Total := OutLen;
    EVP_CipherFinal_ex(Ctx, @Result[Offset + OutLen], @TmpLen);
    Inc(Total, TmpLen);
  finally
    EVP_CIPHER_CTX_free(Ctx);
  end;

  // Copy reserve area (IV + HMAC, kept as-is like SQLCipher)
  Move(AEncrypted[PAGE_SIZE - Reserve], Result[PAGE_SIZE - Reserve], Reserve);
end;

{ ─── Database Decryption ─── }

function TryDecryptDB(const ADbPath, AOutPath: string;
  const AKey, AMacKey: TBytes): Boolean;
var
  InStream, OutStream: TFileStream;
  FileSize: Int64;
  Salt, PageBuf, DecPage: TBytes;
  I, NumPages: Integer;
  IV: TBytes;
  Reserve: Integer;
  DataLen: Integer;
  ExpectedMac: TBytes;
begin
  Result := False;
  if not TFile.Exists(ADbPath) then Exit;

  InStream := TFileStream.Create(ADbPath, fmOpenRead or fmShareDenyNone);
  try
    FileSize := InStream.Size;

    // Read salt (first 16 bytes)
    SetLength(Salt, 16);
    InStream.Read(Salt[0], 16);

    // Calculate reserve area size
    Reserve := IV_SIZE + HMAC_SIZE;
    Reserve := ((Reserve mod AES_BLOCK) = 0) and Reserve
      or ((Reserve div AES_BLOCK) + 1) * AES_BLOCK;

    if FileSize mod PAGE_SIZE <> 0 then
    begin
      WriteLn('  WARNING: File size not multiple of page size (', FileSize, ')');
      Exit;
    end;

    NumPages := FileSize div PAGE_SIZE;
    InStream.Position := 0;

    SetLength(PageBuf, PAGE_SIZE);
    SetLength(IV, IV_SIZE);
    SetLength(ExpectedMac, HMAC_SIZE);
    DataLen := PAGE_SIZE - Reserve;

    OutStream := TFileStream.Create(AOutPath, fmCreate);
    try
      for var Page := 1 to NumPages do
      begin
        InStream.Read(PageBuf[0], PAGE_SIZE);

        // Extract IV from page trailer
        Move(PageBuf[PAGE_SIZE - Reserve], IV[0], IV_SIZE);

        // Verify HMAC
        Move(PageBuf[PAGE_SIZE - Reserve + IV_SIZE], ExpectedMac[0], HMAC_SIZE);
        if not VerifyPageHMAC(
          Copy(PageBuf, 0, DataLen),   // page data (without reserved area)
          AMacKey, Page, ExpectedMac) then
        begin
          WriteLn('  HMAC verification failed on page ', Page);
          Exit;
        end;

        // Decrypt
        DecPage := DecryptPage(PageBuf, AKey, IV, Page);
        OutStream.Write(DecPage[0], PAGE_SIZE);

        if Page mod 50 = 0 then
          Write('  Page ', Page, '/', NumPages, #13);
      end;

      WriteLn('  Page ', NumPages, '/', NumPages, ' - Done');
      Result := True;
    finally
      OutStream.Free;
    end;
  finally
    InStream.Free;
  end;
end;

{ ─── Test Key Against Database ─── }

function TryKeyOnDB(const ADbPath, AOutPath: string;
  const ARawKey, ASalt: TBytes; var OutKey, OutMacKey: TBytes): Boolean;
var
  Key, MacKey: TBytes;
begin
  DeriveSQLCipherKey(ARawKey, ASalt, Key, MacKey);
  Result := TryDecryptDB(ADbPath, AOutPath, Key, MacKey);
  if Result then
  begin
    OutKey := Key;
    OutMacKey := MacKey;
  end;
end;

{ ─── PBKDF2-HMAC-SHA1 Delphi Implementation ─── }

// Delphi 13.1 doesn't have built-in PBKDF2-HMAC-SHA1 in the RTL.
// We use OpenSSL via external declarations.
function EVP_sha1: Pointer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_sha1';
function EVP_aes_256_cbc: Pointer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_aes_256_cbc';
function HMAC_CTX_new: Pointer; cdecl; external 'libcrypto-3-x64.dll' name 'HMAC_CTX_new';
procedure HMAC_CTX_free(ctx: Pointer); cdecl; external 'libcrypto-3-x64.dll' name 'HMAC_CTX_free';
function HMAC_Init_ex(ctx: Pointer; const key: PByte; key_len: Integer;
  const md: Pointer; impl: Pointer): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'HMAC_Init_ex';
function HMAC_Update(ctx: Pointer; const data: PByte; len: Integer): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'HMAC_Update';
function HMAC_Final(ctx: Pointer; md: PByte; len: PCardinal): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'HMAC_Final';
function PKCS5_PBKDF2_HMAC_SHA1(const pass: PAnsiChar; passlen: Integer;
  const salt: PByte; saltlen: Integer; iter: Integer; keylen: Integer;
  out_key: PByte): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'PKCS5_PBKDF2_HMAC_SHA1';
function EVP_CIPHER_CTX_new: Pointer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_CIPHER_CTX_new';
procedure EVP_CIPHER_CTX_free(ctx: Pointer); cdecl; external 'libcrypto-3-x64.dll' name 'EVP_CIPHER_CTX_free';
function EVP_CipherInit_ex(ctx: Pointer; const cipher: Pointer;
  const impl: Pointer; const key: PByte; const iv: PByte;
  enc: Integer): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_CipherInit_ex';
function EVP_CIPHER_CTX_set_padding(ctx: Pointer; padding: Integer): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_CIPHER_CTX_set_padding';
function EVP_CipherUpdate(ctx: Pointer; out_: PByte; outl: PInteger;
  const in_: PByte; inl: Integer): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_CipherUpdate';
function EVP_CipherFinal_ex(ctx: Pointer; outm: PByte; outl: PInteger): Integer; cdecl; external 'libcrypto-3-x64.dll' name 'EVP_CipherFinal_ex';

{ ─── User Directory ─── }

function GetUserDocumentsPath: string;
begin
  Result := TPath.GetDocumentsPath;
end;

{ ─── Scan WeChat Data ─── }

function ScanWeChatData: TArray<TScanResult>;
var
  DataRoot: string;
  Dirs: TArray<string>;
  Dir: string;
begin
  Result := [];
  DataRoot := GetUserDocumentsPath + WECHAT_DATA_ROOT;

  if not TDirectory.Exists(DataRoot) then
  begin
    WriteLn('WeChat data directory not found: ', DataRoot);
    Exit;
  end;

  WriteLn('Scanning: ', DataRoot);
  Dirs := TDirectory.GetDirectories(DataRoot);

  for Dir in Dirs do
  begin
    var AccountId := TPath.GetFileName(Dir);
    // Skip non-account directories
    if AccountId.StartsWith('.') or AccountId.Contains('All Users') or
       AccountId.Contains('config') then
      Continue;

    var MsgDir := Dir + '\Msg';
    if not TDirectory.Exists(MsgDir) then Continue;

    var SR: TScanResult;
    SR.Path := Dir;
    SR.AccountId := AccountId;
    SR.Readable := False;

    // Find all .db files
    var AllDBs := TDirectory.GetFiles(MsgDir, '*.db', TSearchOption.soAllDirectories);
    var RelevantDBs: TArray<string>;
    for var DB in AllDBs do
    begin
      var DBName := TPath.GetFileName(DB).ToLower;
      if DBName.Contains('msg') or DBName.Contains('contact') or
         DBName.Contains('micro') or DBName.Contains('chat') then
        RelevantDBs := RelevantDBs + [DB];
    end;
    SR.DbFiles := RelevantDBs;

    WriteLn;
    WriteLn('Account: ', AccountId);
    WriteLn('  Path: ', Dir);
    WriteLn('  DB Files: ', Length(RelevantDBs));

    Result := Result + [SR];
  end;
end;

{ ─── Main ─── }

procedure RunProbe;
var
  Accounts: TArray<TScanResult>;
  Pid: DWORD;
  HProcess: THandle;
  DllBase: UInt64;
  Keys: TArray<TKeyCandidate>;
  DecryptDir: string;
  Salt: TBytes;
  OutKey, OutMacKey: TBytes;
begin
  WriteLn('═══════════════════════════════════════════');
  WriteLn('  DeepAxis WxDecryptProbe v0.1');
  WriteLn('  WeChat SQLCipher Database Probe');
  WriteLn('═══════════════════════════════════════════');
  WriteLn;

  // Step 1: Find WeChat data
  WriteLn('[A0] Scanning for WeChat data...');
  Accounts := ScanWeChatData;
  if Length(Accounts) = 0 then
  begin
    WriteLn('ERROR: No WeChat data directories found.');
    WriteLn('Manual path input not yet supported.');
    Exit;
  end;

  // Step 2: Find WeChat process
  WriteLn;
  WriteLn('[A1] Locating WeChat process...');
  Pid := GetProcessIdByName(WECHAT_PROCESS);
  if Pid = 0 then
  begin
    WriteLn('ERROR: WeChat.exe is not running.');
    WriteLn('Please start WeChat and try again.');
    Exit;
  end;

  HProcess := OpenProcess(PROCESS_VM_READ or PROCESS_QUERY_INFORMATION, False, Pid);
  if HProcess = 0 then
  begin
    WriteLn('ERROR: Cannot open WeChat process (admin privileges needed).');
    WriteLn('Try running as Administrator.');
    Exit;
  end;
  WriteLn('  WeChat PID: ', Pid);

  // Step 3: Get WeChatWin.dll base
  DllBase := GetModuleBaseAddress(Pid, WECHAT_DLL);
  if DllBase = 0 then
  begin
    WriteLn('ERROR: Cannot find WeChatWin.dll in WeChat process.');
    CloseHandle(HProcess);
    Exit;
  end;
  WriteLn('  WeChatWin.dll base: 0x', IntToHex(DllBase, 16));

  // Step 4: Memory scan for key candidates
  WriteLn;
  WriteLn('[A2] Scanning WeChat memory for key candidates...');

  var ModInfo: TModuleInfo;
  if not GetModuleInformation(HProcess, Pointer(DllBase), @ModInfo, SizeOf(ModInfo)) then
  begin
    WriteLn('ERROR: Cannot get WeChatWin.dll module info.');
    CloseHandle(HProcess);
    Exit;
  end;

  WriteLn('  Module size: ', ModInfo.SizeOfImage div 1024, ' KB');
  WriteLn('  Scanning memory... (this may take a few seconds)');

  Keys := ScanForKeyInProcess(HProcess, DllBase, ModInfo.SizeOfImage);
  WriteLn('  Found ', Length(Keys), ' high-entropy 32-byte candidates');

  if Length(Keys) = 0 then
  begin
    // Fallback: try common offset patterns
    WriteLn('  Fallback: trying known offset patterns...');
    var KnownOffsets: TArray<UInt64> := [
      $1131B64,   // v2.6.6.25
      $1A3D000,   // v3.x
      $1F30000,   // v3.9.x
      $2100000,   // v4.x
    ];
    for var Off in KnownOffsets do
    begin
      var Buf: TBytes;
      if ReadProcessBytes(HProcess, DllBase + Off, Buf, KEY_SIZE) then
      begin
        var KC: TKeyCandidate;
        KC.Key := Buf;
        KC.Address := DllBase + Off;
        KC.Entropy := CalcEntropy(Buf);
        Keys := Keys + [KC];
      end;
    end;
    WriteLn('  Fallback found ', Length(Keys), ' additional candidates');
  end;

  CloseHandle(HProcess);

  // Step 5: Try each key on the first MicroMsg.db
  WriteLn;
  WriteLn('[A3] Testing key candidates on database...');

  DecryptDir := TPath.GetTempPath + 'DeepAxisProbe\';
  ForceDirectories(DecryptDir);

  for var Acct in Accounts do
  begin
    var TargetDB := '';
    for var DB in Acct.DbFiles do
      if TPath.GetFileName(DB).ToLower.Contains('msg') and
         TPath.GetFileName(DB).ToLower.Contains('micro') then
      begin
        TargetDB := DB;
        Break;
      end;

    if TargetDB = '' then
    begin
      WriteLn('  No MicroMsg.db found for account ', Acct.AccountId);
      Continue;
    end;

    WriteLn('  Trying account: ', Acct.AccountId);
    WriteLn('  Database: ', TargetDB);

    // Read salt
    var FStream := TFileStream.Create(TargetDB, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Salt, 16);
      FStream.Read(Salt[0], 16);
    finally
      FStream.Free;
    end;

    var Found := False;
    for var I := 0 to Length(Keys) - 1 do
    begin
      Write('  Testing key ', I+1, '/', Length(Keys),
        ' (addr=0x', IntToHex(Keys[I].Address, 16),
        ', entropy=', Keys[I].Entropy:4:2, ') ... ');

      var OutFile := DecryptDir + 'MicroMsg_' + Acct.AccountId + '_decrypted.db';
      if TFile.Exists(OutFile) then TFile.Delete(OutFile);

      var Key, MacKey: TBytes;
      DeriveSQLCipherKey(Keys[I].Key, Salt, Key, MacKey);

      if TryDecryptDB(TargetDB, OutFile, Key, MacKey) then
      begin
        WriteLn('SUCCESS!');
        Acct.KeyFound := True;
        Acct.KeyHex := '';
        for var B in Keys[I].Key do
          Acct.KeyHex := Acct.KeyHex + IntToHex(B, 2);
        Acct.Readable := True;

        // Show schema
        WriteLn;
        WriteLn('  ═══ Database Schema (decrypted) ═══');

        // We could use FireDAC here, but for now just show file info
        var FInfo := TFile.GetSize(OutFile);
        WriteLn('  Decrypted size: ', FInfo div 1024, ' KB');
        WriteLn('  Output: ', OutFile);

        Found := True;
        Break;
      end
      else
      begin
        WriteLn('FAILED (HMAC mismatch)');
      end;
    end;

    if not Found then
    begin
      WriteLn;
      WriteLn('  ✗ FAILED: No valid key found for account ', Acct.AccountId);
      WriteLn('  Possible causes:');
      WriteLn('    - WeChat version not supported (key at unknown offset)');
      WriteLn('    - Database uses a different encryption scheme');
      WriteLn('    - Not running as Administrator');
    end;
  end;

  // Summary
  WriteLn;
  WriteLn('═══════════════════════════════════════════');
  WriteLn('  PROBE RESULTS');
  WriteLn('═══════════════════════════════════════════');
  for var Acct in Accounts do
  begin
    if Acct.KeyFound then
      WriteLn('  ✅ ', Acct.AccountId, ' - DECRYPTED (key: ', Acct.KeyHex, ')')
    else
      WriteLn('  ❌ ', Acct.AccountId, ' - FAILED');
  end;
  WriteLn;
  WriteLn('Decrypted DBs in: ', DecryptDir);
end;

begin
  try
    RunProbe;
    WriteLn;
    Write('Press Enter to exit...');
    ReadLn;
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('FATAL ERROR: ', E.Message);
      WriteLn(E.StackTrace);
      ReadLn;
    end;
  end;
end.
