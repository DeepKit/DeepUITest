unit DeepAxis.WeChat.Zstd;

interface

uses
  System.SysUtils, System.Classes;

type
  /// <summary>
  ///   zstd (Zstandard) decompression wrapper.
  ///   Dynamically loads zstd.dll and provides decompression for WCDB message content.
  ///   WCDB uses zstd compression (WCDB_CT=4) for message_content and source fields.
  /// </summary>
  TZstdDecompressor = class
  private
    FLibHandle: THandle;
    FLoaded: Boolean;
    // Function pointers
    FZSTD_decompress: function(dst: Pointer; dstCapacity: NativeUInt;
      src: Pointer; compressedSize: NativeUInt): NativeUInt; cdecl;
    FZSTD_getFrameContentSize: function(src: Pointer; srcSize: NativeUInt): UInt64; cdecl;
    FZSTD_isError: function(result: NativeUInt): Cardinal; cdecl;
    FZSTD_getErrorName: function(result: NativeUInt): PAnsiChar; cdecl;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Load zstd.dll from the application directory or system path.</summary>
    function LoadLibrary: Boolean;

    /// <summary>Check if the library is loaded and ready.</summary>
    function IsLoaded: Boolean;

    /// <summary>
    ///   Decompress zstd-compressed data.
    ///   Returns the decompressed bytes.
    ///   Raises EZstdDecompressError on failure.
    /// </summary>
    function Decompress(const ACompressed: TBytes): TBytes;

    /// <summary>
    ///   Decompress zstd-compressed data and convert to UTF-8 string.
    ///   Auto-detects encoding: uses UTF-8 if valid, falls back to GBK (codepage 936).
    ///   WeChat's type=1 text messages are traditionally GBK-encoded.
    /// </summary>
    function DecompressToString(const ACompressed: TBytes): string;

    /// <summary>
    ///   Check if data starts with zstd magic number (28 B5 2F FD).
    /// </summary>
    class function IsZstdData(const AData: TBytes): Boolean; static;

    /// <summary>
    ///   Strict UTF-8 validation. Returns False if bytes contain sequences
    ///   that are invalid in UTF-8 (suggesting a legacy codepage like GBK).
    /// </summary>
    class function IsValidUtf8(const ABytes: TBytes): Boolean; static;

    /// <summary>
    ///   Decode bytes to string, auto-detecting UTF-8 vs GBK.
    ///   If bytes are valid UTF-8, uses UTF-8. Otherwise uses GBK (codepage 936).
    /// </summary>
    class function SmartDecode(const ABytes: TBytes): string; static;
  end;

  EZstdDecompressError = class(Exception);

const
  /// <summary>zstd frame magic number (4 bytes, little-endian).</summary>
  ZSTD_MAGIC_NUMBER: UInt32 = $FD2FB528;
  /// <summary>Returned by ZSTD_getFrameContentSize when size cannot be determined.</summary>
  ZSTD_CONTENTSIZE_UNKNOWN: UInt64 = UInt64(-1);  // 0xFFFFFFFFFFFFFFFF
  /// <summary>Returned by ZSTD_getFrameContentSize when an error occurred.</summary>
  ZSTD_CONTENTSIZE_ERROR: UInt64 = UInt64(-2);    // 0xFFFFFFFFFFFFFFFE

implementation

uses
  System.IOUtils, Winapi.Windows;

{ TZstdDecompressor }

constructor TZstdDecompressor.Create;
begin
  inherited Create;
  FLibHandle := 0;
  FLoaded := False;
end;

destructor TZstdDecompressor.Destroy;
begin
  if FLibHandle <> 0 then
    FreeLibrary(FLibHandle);
  inherited;
end;

function TZstdDecompressor.LoadLibrary: Boolean;
var
  LDllPath: string;
begin
  if FLoaded then
    Exit(True);

  // Try multiple locations for zstd.dll
  // 1. Application directory
  LDllPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'zstd.dll');
  if not TFile.Exists(LDllPath) then
  begin
    // 2. Try 'libzstd.dll' name (msys64 naming)
    LDllPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'libzstd.dll');
  end;
  if not TFile.Exists(LDllPath) then
  begin
    // 3. System path
    LDllPath := 'zstd.dll';
  end;

  FLibHandle := Winapi.Windows.LoadLibrary(PChar(LDllPath));
  if FLibHandle = 0 then
    Exit(False);

  // Load function pointers
  @FZSTD_decompress := GetProcAddress(FLibHandle, 'ZSTD_decompress');
  @FZSTD_getFrameContentSize := GetProcAddress(FLibHandle, 'ZSTD_getFrameContentSize');
  @FZSTD_isError := GetProcAddress(FLibHandle, 'ZSTD_isError');
  @FZSTD_getErrorName := GetProcAddress(FLibHandle, 'ZSTD_getErrorName');

  FLoaded := Assigned(FZSTD_decompress) and Assigned(FZSTD_getFrameContentSize)
    and Assigned(FZSTD_isError) and Assigned(FZSTD_getErrorName);

  Result := FLoaded;
end;

function TZstdDecompressor.IsLoaded: Boolean;
begin
  Result := FLoaded;
end;

function TZstdDecompressor.Decompress(const ACompressed: TBytes): TBytes;
var
  LDecompressedSize: UInt64;
  LResultSize: NativeUInt;
begin
  if not FLoaded then
  begin
    if not LoadLibrary then
      raise EZstdDecompressError.Create('zstd.dll not loaded. Ensure zstd.dll is in the application directory.');
  end;

  if Length(ACompressed) = 0 then
    Exit(nil);

  // Get the decompressed size from the frame header
  LDecompressedSize := FZSTD_getFrameContentSize(Pointer(ACompressed), Length(ACompressed));

  if LDecompressedSize = ZSTD_CONTENTSIZE_ERROR then
    raise EZstdDecompressError.Create('zstd: invalid frame (content size error)');

  if LDecompressedSize = ZSTD_CONTENTSIZE_UNKNOWN then
    raise EZstdDecompressError.Create(
      'zstd: decompressed size unknown (streaming mode required, not supported)');

  // Sanity check: limit to 256 MB
  if LDecompressedSize > 256 * 1024 * 1024 then
    raise EZstdDecompressError.CreateFmt(
      'zstd: decompressed size too large (%d bytes)', [LDecompressedSize]);

  SetLength(Result, LDecompressedSize);

  LResultSize := FZSTD_decompress(Pointer(Result), LDecompressedSize,
    Pointer(ACompressed), Length(ACompressed));

  if FZSTD_isError(LResultSize) <> 0 then
    raise EZstdDecompressError.CreateFmt('zstd decompress error: %s',
      [string(FZSTD_getErrorName(LResultSize))]);

  // Adjust actual size if different
  if LResultSize <> LDecompressedSize then
    SetLength(Result, LResultSize);
end;

function TZstdDecompressor.DecompressToString(const ACompressed: TBytes): string;
var
  LDecompressed: TBytes;
begin
  LDecompressed := Decompress(ACompressed);
  Result := SmartDecode(LDecompressed);
end;

class function TZstdDecompressor.IsValidUtf8(const ABytes: TBytes): Boolean;
var
  I, LNeeded, LLen: Integer;
  LB: Byte;
begin
  Result := False;
  LLen := Length(ABytes);
  I := 0;
  while I < LLen do
  begin
    LB := ABytes[I];
    if LB <= $7F then
    begin
      // ASCII
      Inc(I);
    end
    else if (LB and $E0) = $C0 then
    begin
      // 2-byte sequence: 110xxxxx 10xxxxxx
      LNeeded := 2;
      if I + LNeeded > LLen then Exit;
      if (ABytes[I+1] and $C0) <> $80 then Exit;
      // Overlong check: code point must be >= U+0080
      if LB < $C2 then Exit;
      Inc(I, LNeeded);
    end
    else if (LB and $F0) = $E0 then
    begin
      // 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
      LNeeded := 3;
      if I + LNeeded > LLen then Exit;
      if (ABytes[I+1] and $C0) <> $80 then Exit;
      if (ABytes[I+2] and $C0) <> $80 then Exit;
      // Overlong check: code point must be >= U+0800
      if (LB = $E0) and (ABytes[I+1] < $A0) then Exit;
      // Exclude surrogates U+D800..U+DFFF
      if (LB = $ED) and (ABytes[I+1] >= $A0) then Exit;
      Inc(I, LNeeded);
    end
    else if (LB and $F8) = $F0 then
    begin
      // 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      LNeeded := 4;
      if I + LNeeded > LLen then Exit;
      if (ABytes[I+1] and $C0) <> $80 then Exit;
      if (ABytes[I+2] and $C0) <> $80 then Exit;
      if (ABytes[I+3] and $C0) <> $80 then Exit;
      // Overlong check: code point must be >= U+10000
      if (LB = $F0) and (ABytes[I+1] < $90) then Exit;
      // Max check: code point must be <= U+10FFFF
      if (LB = $F4) and (ABytes[I+1] >= $90) then Exit;
      if LB > $F4 then Exit;
      Inc(I, LNeeded);
    end
    else
      Exit; // Invalid leading byte
  end;
  Result := True;
end;

class function TZstdDecompressor.SmartDecode(const ABytes: TBytes): string;
var
  LGbkEnc: TEncoding;
begin
  if Length(ABytes) = 0 then
    Exit('');
  if IsValidUtf8(ABytes) then
    Result := TEncoding.UTF8.GetString(ABytes)
  else
  begin
    // Fall back to GBK (Windows codepage 936)
    LGbkEnc := TEncoding.GetEncoding(936);
    try
      Result := LGbkEnc.GetString(ABytes);
    finally
      LGbkEnc.Free;
    end;
  end;
end;

class function TZstdDecompressor.IsZstdData(const AData: TBytes): Boolean;
begin
  if Length(AData) < 4 then
    Exit(False);
  Result := (AData[0] = $28) and (AData[1] = $B5) and
            (AData[2] = $2F) and (AData[3] = $FD);
end;

end.
