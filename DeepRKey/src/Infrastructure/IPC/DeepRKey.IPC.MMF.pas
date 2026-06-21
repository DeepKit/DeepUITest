unit DeepRKey.IPC.MMF;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  DeepRKey.HookShared,
  DeepRKey.SecurityHelper;

type
  /// <summary>MMF 环形缓冲器异常</summary>
  EMMFError = class(Exception);

  /// <summary>MMF 环形缓冲器 — 主进程读端</summary>
  TRKeyMMFRingBuffer = class
  private
    FMMFHandle: THandle;
    FMMFView: Pointer;
    FHeader: ^TRKeyMMFHeader;
    FSlots: PByte;
    FMMFName: string;
    FReadIndex: UInt32;
    FGUID: string;
    FSecurity: TUserSecurityDescriptor;  // T-433: 统一安全描述符管理
    FMutexHandle: THandle;  // BUG-H6 修复：命名 Mutex 替代自旋锁
    function GetMMFSize: UInt32; inline;
    procedure EnsureMMFValid;
  public
    constructor Create(const AGUID: string);
    destructor Destroy; override;

    /// <summary>创建 MMF（主进程启动时调用）</summary>
    procedure CreateMMF(const AuthCookie: TGUID);

    /// <summary>打开现有 MMF（Helper 进程调用）</summary>
    procedure OpenMMF(const AuthCookie: TGUID);

    /// <summary>读取事件（非阻塞，无事件时返回 False）</summary>
    function ReadEvent(out Event: TRKeyIpcEvent): Boolean;

    /// <summary>更新心跳时间戳</summary>
    procedure UpdateHeartbeat;

    /// <summary>读取普通事件丢弃计数</summary>
    function GetDroppedEventCount: UInt64;

    /// <summary>读取命令事件丢弃计数</summary>
    function GetCommandDropCount: UInt64;

    /// <summary>检查 AuthCookie 是否匹配</summary>
    function CheckAuthCookie(const AuthCookie: TGUID): Boolean;

    /// <summary>获取 MMF 名称</summary>
    property MMFName: string read FMMFName;

    /// <summary>GUID 标识</summary>
    property GUID: string read FGUID;
  end;

implementation

{ TRKeyMMFRingBuffer }

constructor TRKeyMMFRingBuffer.Create(const AGUID: string);
begin
  FGUID := AGUID;
  FMMFName := Format('%s%s', [RK_MMF_PREFIX, AGUID]);
  FMMFHandle := 0;
  FMMFView := nil;
  FReadIndex := 0;
  FMutexHandle := 0;  // BUG-H6: 初始化 Mutex 句柄
  // T-433: 使用统一安全辅助类
  FSecurity := TUserSecurityDescriptor.Create;
  FSecurity.Initialize;
end;

destructor TRKeyMMFRingBuffer.Destroy;
begin
  FreeAndNil(FSecurity);
  // BUG-H6: 关闭命名 Mutex
  if FMutexHandle <> 0 then
    CloseHandle(FMutexHandle);
  if FMMFView <> nil then
    UnmapViewOfFile(FMMFView);
  if FMMFHandle <> 0 then
    CloseHandle(FMMFHandle);
  inherited;
end;

function TRKeyMMFRingBuffer.GetMMFSize: UInt32;
begin
  Result := RK_MMF_HEADER_SIZE + RK_MMF_SLOT_COUNT * RK_MMF_SLOT_SIZE;
end;

procedure TRKeyMMFRingBuffer.EnsureMMFValid;
begin
  if FMMFView = nil then
    raise EMMFError.Create('MMF not initialized');
end;


procedure TRKeyMMFRingBuffer.CreateMMF(const AuthCookie: TGUID);
begin
  // 关闭旧 MMF（如果存在）
  if FMMFView <> nil then
  begin
    UnmapViewOfFile(FMMFView);
    FMMFView := nil;
  end;
  if FMMFHandle <> 0 then
  begin
    CloseHandle(FMMFHandle);
    FMMFHandle := 0;
  end;
  // BUG-H6: 关闭旧 Mutex（如果存在）
  if FMutexHandle <> 0 then
  begin
    CloseHandle(FMutexHandle);
    FMutexHandle := 0;
  end;

  var mmfSize := GetMMFSize;

  // BUG-C1 修复：使用用户级 DACL 替代默认 nil，阻止其他本地进程访问
  // T-433: 使用统一安全辅助类
  FMMFHandle := CreateFileMapping(
    INVALID_HANDLE_VALUE,
    FSecurity.GetSecurityAttributes,  // 用户级安全描述符（若未初始化则为 nil 回退）
    PAGE_READWRITE,
    0, mmfSize,
    PChar(FMMFName));

  if FMMFHandle = 0 then
    raise EMMFError.CreateFmt('CreateFileMapping failed: %s (error %d)',
      [FMMFName, GetLastError]);

  FMMFView := MapViewOfFile(FMMFHandle, FILE_MAP_ALL_ACCESS, 0, 0, mmfSize);
  if FMMFView = nil then
  begin
    CloseHandle(FMMFHandle);
    FMMFHandle := 0;
    raise EMMFError.CreateFmt('MapViewOfFile failed: %s (error %d)',
      [FMMFName, GetLastError]);
  end;

  // BUG-H6 修复：创建命名 Mutex 替代自旋锁（OS 自动释放崩溃进程的锁）
  // T-433: 使用用户级 DACL 保护 Mutex（与 MMF 相同安全策略）
  var mutexName := FMMFName + '_Mutex';
  FMutexHandle := CreateMutex(FSecurity.GetSecurityAttributes, False, PChar(mutexName));
  if FMutexHandle = 0 then
    OutputDebugString(PChar('[DeepRKey] Failed to create Mutex: ' + mutexName));

  // 初始化 Header
  ZeroMemory(FMMFView, mmfSize);
  FHeader := FMMFView;
  FHeader.Version := 1;
  FHeader.EventCount := RK_MMF_SLOT_COUNT;
  FHeader.WriteIndex := 0;
  FHeader.ReadIndex := 0;
  FHeader.DroppedEventCount := 0;
  FHeader.CommandDropCount := 0;
  FHeader.AuthCookie := AuthCookie;
  FHeader.HeartbeatTick := GetTickCount64;
  FHeader.WriteLock := SPINLOCK_IDLE;

  FSlots := PByte(NativeUInt(FMMFView) + RK_MMF_HEADER_SIZE);
  FReadIndex := 0;

  OutputDebugString(PChar(Format('[DeepRKey] MMF created: %s (%d bytes)',
    [FMMFName, mmfSize])));
end;

procedure TRKeyMMFRingBuffer.OpenMMF(const AuthCookie: TGUID);
begin
  FMMFHandle := OpenFileMapping(FILE_MAP_READ or FILE_MAP_WRITE, False,
    PChar(FMMFName));
  if FMMFHandle = 0 then
    raise EMMFError.CreateFmt('OpenFileMapping failed: %s (error %d)',
      [FMMFName, GetLastError]);

  FMMFView := MapViewOfFile(FMMFHandle, FILE_MAP_READ or FILE_MAP_WRITE,
    0, 0, GetMMFSize);
  if FMMFView = nil then
  begin
    CloseHandle(FMMFHandle);
    FMMFHandle := 0;
    raise EMMFError.CreateFmt('MapViewOfFile failed: %s (error %d)',
      [FMMFName, GetLastError]);
  end;

  FHeader := FMMFView;
  FSlots := PByte(NativeUInt(FMMFView) + RK_MMF_HEADER_SIZE);
  FReadIndex := 0;
end;

function TRKeyMMFRingBuffer.ReadEvent(out Event: TRKeyIpcEvent): Boolean;
var
  readIdx, writeIdx: Integer;
  computedCrc: UInt32;
  waitResult: DWORD;
begin
  Result := False;
  EnsureMMFValid;

  // BUG-H8 修复 + BUG-H9：使用 Mutex 保护 ReadIndex 修改，防止与写端推进 ReadIndex 的竞争
  // WAIT_ABANDONED_0 表示前持有者崩溃，OS 已将锁授予当前线程，故接受
  if FMutexHandle <> 0 then
  begin
    waitResult := WaitForSingleObject(FMutexHandle, 1000);
    if (waitResult <> WAIT_OBJECT_0) and (waitResult <> WAIT_ABANDONED_0) then
      Exit(False);
  end;

  try
    readIdx := Integer(FHeader.ReadIndex);
    writeIdx := Integer(FHeader.WriteIndex);

    if readIdx = writeIdx then
      Exit;

    // 读取 slot
    var slotOffset := Cardinal(RK_MMF_HEADER_SIZE + Cardinal(readIdx) * RK_MMF_SLOT_SIZE);
    Move(Pointer(NativeUInt(FMMFView) + slotOffset)^, Event, SizeOf(TRKeyIpcEvent));

    // 验证 Magic
    if Event.Magic <> RK_EVENT_MAGIC then
    begin
      FHeader.ReadIndex := UInt32((readIdx + 1) mod RK_MMF_SLOT_COUNT);
      Exit;
    end;

    // BUG-H3 修复：验证 CRC32（排除 Crc32 字段和 Padding 字段）
    computedCrc := ComputeCRC32(Event, SizeOf(TRKeyIpcEvent) - 52);
    if computedCrc <> Event.Crc32 then
    begin
      FHeader.ReadIndex := UInt32((readIdx + 1) mod RK_MMF_SLOT_COUNT);
      Exit;
    end;

    // 推进读指针
    FHeader.ReadIndex := UInt32((readIdx + 1) mod RK_MMF_SLOT_COUNT);

    Result := True;
  finally
    if FMutexHandle <> 0 then
      ReleaseMutex(FMutexHandle);
  end;
end;

procedure TRKeyMMFRingBuffer.UpdateHeartbeat;
begin
  EnsureMMFValid;
  InterlockedExchange64(Int64(FHeader.HeartbeatTick), Int64(GetTickCount64));
end;

function TRKeyMMFRingBuffer.GetDroppedEventCount: UInt64;
begin
  EnsureMMFValid;
  Result := InterlockedCompareExchange64(Int64(FHeader.DroppedEventCount), 0, 0);
end;

function TRKeyMMFRingBuffer.GetCommandDropCount: UInt64;
begin
  EnsureMMFValid;
  Result := InterlockedCompareExchange64(Int64(FHeader.CommandDropCount), 0, 0);
end;

function TRKeyMMFRingBuffer.CheckAuthCookie(const AuthCookie: TGUID): Boolean;
begin
  EnsureMMFValid;
  Result := CompareMem(@FHeader.AuthCookie, @AuthCookie, SizeOf(TGUID));
end;

end.