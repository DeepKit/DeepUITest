unit DeepRKey.SecurityHelper;

interface

uses
  Winapi.Windows, Winapi.AccCtrl, Winapi.AclAPI,
  System.SysUtils;

type
  // 本地声明以避开 Windows 单元 PTokenUser 解析问题
  TRTokenUser = record
    User: SID_AND_ATTRIBUTES;
  end;
  PRTokenUser = ^TRTokenUser;

  /// <summary>
  /// 用户级安全描述符辅助类 — 封装 DACL 创建逻辑
  /// 确保内核对象（MMF、Mutex 等）仅对当前用户可访问
  /// T-433: 从 IPC.MMF.pas 提取，统一安全描述符创建
  /// </summary>
  TUserSecurityDescriptor = class
  private
    FSecDesc: SECURITY_DESCRIPTOR;
    FSecAttr: SECURITY_ATTRIBUTES;
    FSecInitialized: Boolean;
    FDACL: PACL;
    FUserSid: PSID;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>初始化用户级 DACL — 仅授权当前用户 GENERIC_ALL</summary>
    /// <returns>True=成功, False=失败（回退到默认安全）</returns>
    function Initialize: Boolean;

    /// <summary>获取 SECURITY_ATTRIBUTES 指针（用于 CreateFileMapping/CreateMutex 等）</summary>
    function GetSecurityAttributes: PSecurityAttributes;

    /// <summary>安全描述符是否已初始化</summary>
    property Initialized: Boolean read FSecInitialized;
  end;

/// <summary>获取当前进程用户的 SID</summary>
/// <returns>True=成功（调用方需用 FreeMem 释放 pSid）</returns>
function GetCurrentProcessUserSID(out pSid: PSID): Boolean;

implementation

uses
  DeepRKey.Bootstrap;

function GetCurrentProcessUserSID(out pSid: PSID): Boolean;
var
  hToken: THandle;
  dwSize: DWORD;
  pBuf: Pointer;
  pTokenUser: PRTokenUser;
begin
  Result := False;
  pSid := nil;

  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, hToken) then Exit;
  try
    // 第一次调用获取所需缓冲区大小
    if not GetTokenInformation(hToken, TokenUser, nil, 0, dwSize) and
       (GetLastError <> ERROR_INSUFFICIENT_BUFFER) then Exit;

    GetMem(pBuf, dwSize);
    pTokenUser := PRTokenUser(pBuf);
    try
      if not GetTokenInformation(hToken, TokenUser, pBuf, dwSize, dwSize) then Exit;

      // 复制 SID（长度动态：SID 结构 + SubAuthorityCount × 4 字节）
      dwSize := GetLengthSid(pTokenUser.User.Sid);
      GetMem(pSid, dwSize);
      if not CopySid(dwSize, pSid, pTokenUser.User.Sid) then
      begin
        FreeMem(pSid);
        pSid := nil;
        Exit;
      end;
      Result := True;
    finally
      FreeMem(pBuf);
    end;
  finally
    CloseHandle(hToken);
  end;
end;

{ TUserSecurityDescriptor }

constructor TUserSecurityDescriptor.Create;
begin
  inherited Create;
  FSecInitialized := False;
  FDACL := nil;
  FUserSid := nil;
  ZeroMemory(@FSecDesc, SizeOf(FSecDesc));
  ZeroMemory(@FSecAttr, SizeOf(FSecAttr));
end;

destructor TUserSecurityDescriptor.Destroy;
begin
  // 释放 DACL
  if FSecInitialized and (FDACL <> nil) then
  begin
    var bDaclPresent, bDaclDefaulted: BOOL;
    if GetSecurityDescriptorDacl(@FSecDesc, bDaclPresent, FDACL, bDaclDefaulted)
       and bDaclPresent and (FDACL <> nil) then
      LocalFree(HLOCAL(FDACL));
  end;

  // 释放 SID
  if FUserSid <> nil then
    FreeMem(FUserSid);

  inherited Destroy;
end;

function TUserSecurityDescriptor.Initialize: Boolean;
var
  ea: EXPLICIT_ACCESS_W;
begin
  Result := False;
  FSecInitialized := False;

  // 获取当前用户 SID
  if not GetCurrentProcessUserSID(FUserSid) then
  begin
    TBootstrap.Logger.Warn(
      'SecurityHelper: failed to get user SID, falling back to default DACL',
      'Security');
    Exit;
  end;

  // 设置 EXPLICIT_ACCESS：授权当前用户 GENERIC_ALL
  ZeroMemory(@ea, SizeOf(ea));
  ea.grfAccessPermissions := GENERIC_ALL;
  ea.grfAccessMode := GRANT_ACCESS;
  ea.grfInheritance := NO_INHERITANCE;
  ea.Trustee.pMultipleTrustee := nil;
  ea.Trustee.MultipleTrusteeOperation := NO_MULTIPLE_TRUSTEE;
  ea.Trustee.TrusteeForm := TRUSTEE_IS_SID;
  ea.Trustee.TrusteeType := TRUSTEE_IS_USER;
  ea.Trustee.ptstrName := PChar(FUserSid);

  // 创建 DACL
  if SetEntriesInAclW(1, @ea, nil, FDACL) <> ERROR_SUCCESS then
  begin
    TBootstrap.Logger.Warn(
      'SecurityHelper: SetEntriesInAclW failed',
      'Security');
    Exit;
  end;

  // 初始化 SECURITY_DESCRIPTOR
  if not InitializeSecurityDescriptor(@FSecDesc, SECURITY_DESCRIPTOR_REVISION) then
  begin
    LocalFree(HLOCAL(FDACL));
    FDACL := nil;
    Exit;
  end;

  // 设置 DACL 到 SECURITY_DESCRIPTOR
  if not SetSecurityDescriptorDacl(@FSecDesc, True, FDACL, False) then
  begin
    LocalFree(HLOCAL(FDACL));
    FDACL := nil;
    Exit;
  end;

  // 设置 SECURITY_ATTRIBUTES
  FSecAttr.nLength := SizeOf(SECURITY_ATTRIBUTES);
  FSecAttr.lpSecurityDescriptor := @FSecDesc;
  FSecAttr.bInheritHandle := False;
  FSecInitialized := True;

  TBootstrap.Logger.Info(
    'SecurityHelper: user-only DACL initialized',
    'Security');
  Result := True;
end;

function TUserSecurityDescriptor.GetSecurityAttributes: PSecurityAttributes;
begin
  if FSecInitialized then
    Result := @FSecAttr
  else
    Result := nil;
end;

end.
