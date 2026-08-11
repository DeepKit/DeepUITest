unit DeepAxis.WeChat.Decrypt;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.JSON;

type
  /// <summary>
  ///   Full SQLCipher 4 decryption pipeline using BCrypt APIs.
  ///   Ported from probe/WxDecryptProbe.dpr (validated against WeChat 4.1.10.53).
  ///
  ///   Algorithm:
  ///   1. captured enc_key is the direct 32-byte AES-256 key
  ///   2. salt XOR 0x3a → mac_salt
  ///   3. PBKDF2-HMAC-SHA512(AES_key, mac_salt, 2 iters) → 32-byte HMAC key
  ///   4. verify each page HMAC-SHA512 (4096-byte pages, 80-byte reserve)
  ///   5. Page 1: first 16 encrypted bytes are salt; output uses SQLite header
  /// </summary>

  TKeyEntry = record
    DbRelPath: string;   // e.g. "message\message_0.db"
    EncKey: string;      // 64-char hex = 32 bytes raw key
    Salt: string;        // 32-char hex = 16 bytes salt
  end;

  TKeyManager = class
  private
    FKeys: TDictionary<string, TKeyEntry>; // key = db_rel_path
    FLoaded: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function LoadFromJSON(const AJsonPath: string): Boolean;
    function TryGetKey(const ADbRelPath: string; out AEntry: TKeyEntry): Boolean;
    function HasKeys: Boolean;
    function GetKeyCount: Integer;
    function FindKeysForDir(const ADirPath: string): TArray<TKeyEntry>;
  end;

  TWeChatDecryptor = class
  private
    class var FTempDir: string;
    class function GetTempDir: string; static;
  public
    /// <summary>Initialize temp directory for decrypted DBs</summary>
    class constructor Create;
    class destructor Destroy;

    /// <summary>Use captured AES key directly and derive HMAC-SHA512 key from salt</summary>
    class function DeriveKeys(const ARawKeyHex, ASaltHex: string;
      out AAesKey, AMacKey: TBytes): Boolean;

    /// <summary>字节版密钥派生：原始 32 字节密钥 + 16 字节 salt → AES 密钥 + MAC 密钥。
    ///   与 DeriveKeys 相同算法，但接受原始字节 (供实时抓取的候选密钥校验用)。</summary>
    class function DeriveKeysFromBytes(const ARawKey, ASalt: TBytes;
      out AAesKey, AMacKey: TBytes): Boolean;

    /// <summary>用数据库第一页 (完整 4096 字节) 校验候选原始密钥字节。
    ///   salt 取自 APage1 前 16 字节。校验通过说明该 32 字节即为正确 enc_key。
    ///   算法与 probe_v4.py verify_key_bytes 一致 (PBKDF2-HMAC-SHA512 2 轮 + 页 HMAC)。</summary>
    class function VerifyKeyBytesAgainstPage1(const AKeyBytes, APage1: TBytes): Boolean;

    /// <summary>Verify a key by decrypting and checking first page</summary>
    class function VerifyKey(const ADbPath: string;
      const AKeyHex, ASaltHex: string): Boolean;

    /// <summary>Decrypt entire database to temp file. Returns temp file path, or '' on failure.</summary>
    class function DecryptToTemp(const ASourcePath: string;
      const AKeyHex, ASaltHex: string): string;

    /// <summary>Decrypt database to specific output path</summary>
    class function DecryptToFile(const ASourcePath, ADestPath: string;
      const AKeyHex, ASaltHex: string): Boolean;

    /// <summary>Auto-detect WeChat data dir and return decrypted temp paths for key DBs</summary>
    class function AutoDecrypt(const AWeChatDataDir: string;
      const AKeyManager: TKeyManager; out AContactPath, AMessage0Path,
      ASessionPath: string): Boolean;

    /// <summary>Clean up temp decrypted files</summary>
    class procedure Cleanup;
  end;

implementation

uses
  Winapi.Windows;

const
  bcrypt = 'bcrypt.dll';

  BCRYPT_SHA512_ALGORITHM = 'SHA512';
  BCRYPT_AES_ALGORITHM  = 'AES';
  BCRYPT_CHAIN_MODE_CBC = 'ChainingModeCBC';
  BCRYPT_ALG_HANDLE_HMAC_FLAG = $00000008;

  KEY_SIZE       = 32;
  SALT_SIZE      = 16;
  IV_SIZE        = 16;
  HMAC_SHA512_SIZE = 64;
  RESERVE_SIZE   = 80;
  AES_BLOCK      = 16;
  PBKDF2_MAC_ITER = 2;
  PAGE_SIZE      = 4096;
  SQLITE_HEADER  = 'SQLite format 3'#0;

type
  BCRYPT_ALG_HANDLE = THandle;
  BCRYPT_HASH_HANDLE = THandle;
  BCRYPT_KEY_HANDLE = THandle;
  NTSTATUS = Cardinal;

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

function HexToBytes(const AHex: string): TBytes;
var
  I, L: Integer;
begin
  L := Length(AHex) div 2;
  SetLength(Result, L);
  for I := 0 to L - 1 do
    Result[I] := Byte(StrToInt('$' + Copy(AHex, I * 2 + 1, 2)));
end;

function VerifyPageHmac(const APageBuf, AMacKey: TBytes; APageNum: Integer): Boolean;
var
  hSha512: BCRYPT_ALG_HANDLE;
  hHash: BCRYPT_HASH_HANDLE;
  LComputedMac: TBytes;
  LHmacOffset, LHmacLen: Integer;
  LPageNoLE: Cardinal;
begin
  Result := False;
  if (Length(APageBuf) <> PAGE_SIZE) or (Length(AMacKey) <> KEY_SIZE) then
    Exit;

  if APageNum = 1 then
    LHmacOffset := SALT_SIZE
  else
    LHmacOffset := 0;
  LHmacLen := PAGE_SIZE - HMAC_SHA512_SIZE - LHmacOffset;
  LPageNoLE := Cardinal(APageNum);

  if not IsNTSTATUS_Success(
    BCryptOpenAlgorithmProvider(hSha512, BCRYPT_SHA512_ALGORITHM, nil,
      BCRYPT_ALG_HANDLE_HMAC_FLAG)) then
    Exit;
  try
    SetLength(LComputedMac, HMAC_SHA512_SIZE);
    if not IsNTSTATUS_Success(
      BCryptCreateHash(hSha512, hHash, nil, 0, @AMacKey[0], KEY_SIZE, 0)) then
      Exit;
    try
      if not IsNTSTATUS_Success(
        BCryptHashData(hHash, @APageBuf[LHmacOffset], LHmacLen, 0)) then
        Exit;
      if not IsNTSTATUS_Success(
        BCryptHashData(hHash, @LPageNoLE, SizeOf(LPageNoLE), 0)) then
        Exit;
      if not IsNTSTATUS_Success(
        BCryptFinishHash(hHash, @LComputedMac[0], HMAC_SHA512_SIZE, 0)) then
        Exit;
    finally
      BCryptDestroyHash(hHash);
    end;
  finally
    BCryptCloseAlgorithmProvider(hSha512, 0);
  end;

  Result := CompareMem(@LComputedMac[0],
    @APageBuf[PAGE_SIZE - HMAC_SHA512_SIZE], HMAC_SHA512_SIZE);
end;

{ TKeyManager }

constructor TKeyManager.Create;
begin
  inherited Create;
  FKeys := TDictionary<string, TKeyEntry>.Create;
  FLoaded := False;
end;

destructor TKeyManager.Destroy;
begin
  FKeys.Free;
  inherited;
end;

function TKeyManager.LoadFromJSON(const AJsonPath: string): Boolean;
var
  LJSON: string;
  LObj: TJSONObject;
  LPair: TJSONPair;
  LKey: TKeyEntry;
begin
  Result := False;
  if not TFile.Exists(AJsonPath) then
    Exit;

  try
    LJSON := TFile.ReadAllText(AJsonPath, TEncoding.UTF8);
    LObj := TJSONObject.ParseJSONValue(LJSON) as TJSONObject;
    if LObj = nil then Exit;

    try
      for LPair in LObj do
      begin
        var LEntryObj := LPair.JsonValue as TJSONObject;
        if LEntryObj = nil then Continue;

        LKey.DbRelPath := LPair.JsonString.Value;
        LKey.EncKey := LEntryObj.GetValue<string>('enc_key', '');
        LKey.Salt := LEntryObj.GetValue<string>('salt', '');

        if (LKey.EncKey <> '') and (LKey.Salt <> '') then
        begin
          // Normalize path separators
          LKey.DbRelPath := LKey.DbRelPath.Replace('\', '/');
          FKeys.AddOrSetValue(LKey.DbRelPath.ToLower, LKey);
        end;
      end;

      FLoaded := True;
      Result := FKeys.Count > 0;
    finally
      LObj.Free;
    end;
  except
    Result := False;
  end;
end;

function TKeyManager.TryGetKey(const ADbRelPath: string; out AEntry: TKeyEntry): Boolean;
var
  LPath: string;
begin
  LPath := ADbRelPath.Replace('\', '/').ToLower;
  Result := FKeys.TryGetValue(LPath, AEntry);
  if not Result then
  begin
    // Fallback: 仅文件名匹配 (TDictionary 遍历顺序非确定性，同名文件取第一个匹配)
    var LName := TPath.GetFileName(ADbRelPath).ToLower;
    for var LK in FKeys.Values do
      if TPath.GetFileName(LK.DbRelPath).ToLower = LName then
      begin
        AEntry := LK;
        Exit(True);
      end;
  end;
end;

function TKeyManager.HasKeys: Boolean;
begin
  Result := FKeys.Count > 0;
end;

function TKeyManager.GetKeyCount: Integer;
begin
  Result := FKeys.Count;
end;

function TKeyManager.FindKeysForDir(const ADirPath: string): TArray<TKeyEntry>;
var
  LEntry: TKeyEntry;
begin
  Result := nil;
  for LEntry in FKeys.Values do
  begin
    var LFullPath := TPath.Combine(ADirPath, LEntry.DbRelPath.Replace('/', '\'));
    if TFile.Exists(LFullPath) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LEntry;
    end;
  end;
end;

{ TWeChatDecryptor }

class constructor TWeChatDecryptor.Create;
begin
  FTempDir := '';
end;

class destructor TWeChatDecryptor.Destroy;
begin
  Cleanup;
end;

class function TWeChatDecryptor.GetTempDir: string;
begin
  if FTempDir = '' then
  begin
    FTempDir := TPath.Combine(TPath.GetTempPath, 'DeepAxis_Decrypted');
    if not TDirectory.Exists(FTempDir) then
      TDirectory.CreateDirectory(FTempDir);
  end;
  Result := FTempDir;
end;

class function TWeChatDecryptor.DeriveKeysFromBytes(const ARawKey, ASalt: TBytes;
  out AAesKey, AMacKey: TBytes): Boolean;
var
  hSha512: BCRYPT_ALG_HANDLE;
  LMacSalt: TBytes;
  I: Integer;
begin
  Result := False;
  if (Length(ARawKey) <> KEY_SIZE) or (Length(ASalt) <> SALT_SIZE) then
    Exit;

  AAesKey := Copy(ARawKey);
  SetLength(AMacKey, KEY_SIZE);

  if not IsNTSTATUS_Success(
    BCryptOpenAlgorithmProvider(hSha512, BCRYPT_SHA512_ALGORITHM, nil,
      BCRYPT_ALG_HANDLE_HMAC_FLAG)) then
    Exit;

  try
    // MAC salt = salt XOR 0x3a
    SetLength(LMacSalt, Length(ASalt));
    for I := 0 to Length(ASalt) - 1 do
      LMacSalt[I] := ASalt[I] xor $3a;

    // PBKDF2-HMAC-SHA512(AES key, mac_salt, 2) → MAC key
    if not IsNTSTATUS_Success(
      BCryptDeriveKeyPBKDF2(hSha512, @AAesKey[0], Length(AAesKey),
        @LMacSalt[0], Length(LMacSalt), PBKDF2_MAC_ITER,
        @AMacKey[0], KEY_SIZE, 0)) then
      Exit;

    Result := True;
  finally
    BCryptCloseAlgorithmProvider(hSha512, 0);
  end;
end;

class function TWeChatDecryptor.VerifyKeyBytesAgainstPage1(
  const AKeyBytes, APage1: TBytes): Boolean;
var
  LAesKey, LMacKey, LSalt: TBytes;
begin
  Result := False;
  if (Length(AKeyBytes) <> KEY_SIZE) or (Length(APage1) < PAGE_SIZE) then
    Exit;
  LSalt := Copy(APage1, 0, SALT_SIZE);
  if not DeriveKeysFromBytes(AKeyBytes, LSalt, LAesKey, LMacKey) then
    Exit;
  Result := VerifyPageHmac(Copy(APage1, 0, PAGE_SIZE), LMacKey, 1);
end;

class function TWeChatDecryptor.DeriveKeys(const ARawKeyHex, ASaltHex: string;
  out AAesKey, AMacKey: TBytes): Boolean;
begin
  Result := False;
  if (Length(ARawKeyHex) <> 64) or (Length(ASaltHex) <> 32) then
    Exit;
  Result := DeriveKeysFromBytes(HexToBytes(ARawKeyHex), HexToBytes(ASaltHex),
    AAesKey, AMacKey);
end;

class function TWeChatDecryptor.VerifyKey(const ADbPath: string;
  const AKeyHex, ASaltHex: string): Boolean;
var
  LAesKey, LMacKey: TBytes;
  LStream: TFileStream;
  LPageBuf, LIV, LDecPage: TBytes;
  hAes: BCRYPT_ALG_HANDLE;
  hKey: BCRYPT_KEY_HANDLE;
  LOutLen: DWORD;
  LChainBytes: TBytes;
  LIVCopy: TBytes;
  LInLen: Integer;
  LOffset: Integer;
const
  ChainStr: string = 'ChainingModeCBC';
begin
  Result := False;
  if not TFile.Exists(ADbPath) then Exit;
  if not DeriveKeys(AKeyHex, ASaltHex, LAesKey, LMacKey) then Exit;

  LStream := TFileStream.Create(ADbPath, fmOpenRead or fmShareDenyNone);
  try
    if LStream.Size < PAGE_SIZE then Exit;

    SetLength(LPageBuf, PAGE_SIZE);
    SetLength(LIV, IV_SIZE);
    if LStream.Read(LPageBuf[0], PAGE_SIZE) <> PAGE_SIZE then Exit;

    if not VerifyPageHmac(LPageBuf, LMacKey, 1) then
      Exit;

    // Decrypt first page
    Move(LPageBuf[PAGE_SIZE - RESERVE_SIZE], LIV[0], IV_SIZE);

    if not IsNTSTATUS_Success(
      BCryptOpenAlgorithmProvider(hAes, BCRYPT_AES_ALGORITHM, nil, 0)) then Exit;
    try
      SetLength(LChainBytes, (Length(ChainStr) + 1) * SizeOf(Char));
      Move(PChar(ChainStr)^, LChainBytes[0], Length(ChainStr) * SizeOf(Char));
      if not IsNTSTATUS_Success(
        BCryptSetProperty(hAes, BCRYPT_CHAIN_MODE_CBC, @LChainBytes[0],
          Length(LChainBytes), 0)) then
        Exit;

      if not IsNTSTATUS_Success(
        BCryptGenerateSymmetricKey(hAes, hKey, nil, 0, @LAesKey[0], KEY_SIZE, 0)) then Exit;
      try
        LOffset := 16; // First 16 bytes of page 1 are unencrypted header
        LInLen := PAGE_SIZE - RESERVE_SIZE - LOffset;
        SetLength(LIVCopy, Length(LIV));
        Move(LIV[0], LIVCopy[0], Length(LIV));
        SetLength(LDecPage, PAGE_SIZE);
        FillChar(LDecPage[0], Length(LDecPage), 0);

        Move(PAnsiChar(SQLITE_HEADER)^, LDecPage[0], 16);
        LOutLen := 0;
        Result := IsNTSTATUS_Success(
          BCryptDecrypt(hKey, @LPageBuf[LOffset], LInLen, nil,
            @LIVCopy[0], Length(LIVCopy), @LDecPage[LOffset], LInLen,
            LOutLen, 0)) and (LOutLen = DWORD(LInLen));
      finally
        BCryptDestroyKey(hKey);
      end;
    finally
      BCryptCloseAlgorithmProvider(hAes, 0);
    end;
  finally
    LStream.Free;
  end;
end;

class function TWeChatDecryptor.DecryptToTemp(const ASourcePath: string;
  const AKeyHex, ASaltHex: string): string;
var
  LOutPath: string;
begin
  LOutPath := TPath.Combine(GetTempDir,
    TPath.GetFileName(ASourcePath) + '.decrypted');
  if DecryptToFile(ASourcePath, LOutPath, AKeyHex, ASaltHex) then
    Result := LOutPath
  else
    Result := '';
end;

class function TWeChatDecryptor.DecryptToFile(const ASourcePath, ADestPath: string;
  const AKeyHex, ASaltHex: string): Boolean;
var
  LAesKey, LMacKey: TBytes;
  LInStream, LOutStream: TFileStream;
  LFileSize: Int64;
  LNumPages, LPageNum: Integer;
  LPageBuf, LIV, LDecPage: TBytes;
  hAes: BCRYPT_ALG_HANDLE;
  hKey: BCRYPT_KEY_HANDLE;
  LOutLen: DWORD;
  LChainBytes: TBytes;
  LIVCopy: TBytes;
  LInLen: Integer;
  LOffset: Integer;
const
  ChainStr: string = 'ChainingModeCBC';
begin
  Result := False;
  if not TFile.Exists(ASourcePath) then Exit;
  if not DeriveKeys(AKeyHex, ASaltHex, LAesKey, LMacKey) then Exit;

  LInStream := TFileStream.Create(ASourcePath, fmOpenRead or fmShareDenyNone);
  try
    LFileSize := LInStream.Size;
    if (LFileSize < PAGE_SIZE) or ((LFileSize mod PAGE_SIZE) <> 0) then Exit;
    LNumPages := LFileSize div PAGE_SIZE;

    LOutStream := TFileStream.Create(ADestPath, fmCreate);
    try
      try
        SetLength(LPageBuf, PAGE_SIZE);
        SetLength(LDecPage, PAGE_SIZE);

        if not IsNTSTATUS_Success(
          BCryptOpenAlgorithmProvider(hAes, BCRYPT_AES_ALGORITHM, nil, 0)) then
          raise Exception.Create('BCrypt AES provider unavailable');
        try
          SetLength(LChainBytes, (Length(ChainStr) + 1) * SizeOf(Char));
          Move(PChar(ChainStr)^, LChainBytes[0], Length(ChainStr) * SizeOf(Char));
          if not IsNTSTATUS_Success(
            BCryptSetProperty(hAes, BCRYPT_CHAIN_MODE_CBC, @LChainBytes[0],
              Length(LChainBytes), 0)) then
            raise Exception.Create('BCryptSetProperty CBC failed');

          if not IsNTSTATUS_Success(
            BCryptGenerateSymmetricKey(hAes, hKey, nil, 0, @LAesKey[0], KEY_SIZE, 0)) then
            raise Exception.Create('BCryptGenerateSymmetricKey failed');
          try
            for LPageNum := 1 to LNumPages do
            begin
              if LInStream.Read(LPageBuf[0], PAGE_SIZE) <> PAGE_SIZE then
                raise Exception.Create('Short read while decrypting database');

              if not VerifyPageHmac(LPageBuf, LMacKey, LPageNum) then
                raise Exception.CreateFmt('HMAC verification failed on page %d', [LPageNum]);

              // Extract IV from reserve area
              SetLength(LIV, IV_SIZE);
              Move(LPageBuf[PAGE_SIZE - RESERVE_SIZE], LIV[0], IV_SIZE);
              FillChar(LDecPage[0], Length(LDecPage), 0);

              if LPageNum = 1 then
              begin
                // Page 1: first 16 bytes are SQLite header, not encrypted
                Move(PAnsiChar(SQLITE_HEADER)^, LDecPage[0], 16);
                LOffset := 16;
              end
              else
                LOffset := 0;

              LInLen := PAGE_SIZE - RESERVE_SIZE - LOffset;
              SetLength(LIVCopy, Length(LIV));
              Move(LIV[0], LIVCopy[0], Length(LIV));

              LOutLen := 0;
              if (not IsNTSTATUS_Success(
                BCryptDecrypt(hKey, @LPageBuf[LOffset], LInLen, nil,
                  @LIVCopy[0], Length(LIVCopy), @LDecPage[LOffset], LInLen,
                  LOutLen, 0))) or (LOutLen <> DWORD(LInLen)) then
                raise Exception.CreateFmt('AES decrypt failed on page %d', [LPageNum]);

              LOutStream.Write(LDecPage[0], PAGE_SIZE);
            end;
          finally
            BCryptDestroyKey(hKey);
          end;
        finally
          BCryptCloseAlgorithmProvider(hAes, 0);
        end;

        Result := True;
      except
        Result := False;
      end;
    finally
      LOutStream.Free;
    end;
  finally
    LInStream.Free;
  end;

  if (not Result) and TFile.Exists(ADestPath) then
    try TFile.Delete(ADestPath); except end;
end;

class function TWeChatDecryptor.AutoDecrypt(const AWeChatDataDir: string;
  const AKeyManager: TKeyManager; out AContactPath, AMessage0Path,
  ASessionPath: string): Boolean;
var
  LKeys: TArray<TKeyEntry>;
  LEntry: TKeyEntry;
  LSrcPath, LDecPath: string;
  LDecFiles: TArray<string>;
begin
  AContactPath := '';
  AMessage0Path := '';
  ASessionPath := '';
  Result := False;

  LKeys := AKeyManager.FindKeysForDir(AWeChatDataDir);
  if Length(LKeys) = 0 then
    Exit;

  for LEntry in LKeys do
  begin
    LSrcPath := TPath.Combine(AWeChatDataDir,
      LEntry.DbRelPath.Replace('/', '\'));

    if not TFile.Exists(LSrcPath) then
      Continue;

    LDecPath := DecryptToTemp(LSrcPath, LEntry.EncKey, LEntry.Salt);
    if LDecPath = '' then
      Continue;

    // 记录临时文件，用于失败时清理
    SetLength(LDecFiles, Length(LDecFiles) + 1);
    LDecFiles[High(LDecFiles)] := LDecPath;

    var LFileName := TPath.GetFileName(LEntry.DbRelPath).ToLower;
    if LFileName = 'contact.db' then AContactPath := LDecPath
    else if LFileName = 'message_0.db' then AMessage0Path := LDecPath
    else if LFileName = 'session.db' then ASessionPath := LDecPath;
  end;

  Result := (AContactPath <> '') and (AMessage0Path <> '');
  // 部分失败时清理非关键 DB 的临时文件
  if not Result then
    for var LFile in LDecFiles do
      try TFile.Delete(LFile); except end;
end;

class procedure TWeChatDecryptor.Cleanup;
begin
  if FTempDir <> '' then
  begin
    try
      if TDirectory.Exists(FTempDir) then
        TDirectory.Delete(FTempDir, True);
    except
    end;
    FTempDir := '';
  end;
end;

end.
