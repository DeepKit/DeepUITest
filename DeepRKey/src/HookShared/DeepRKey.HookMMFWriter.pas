unit DeepRKey.HookMMFWriter;

{ *****************************************************************************
  Hook MMF Writer — 供 Hook DLL 使用的无堆分配 MMF 写入器

  约束：仅使用 Winapi 单元，零堆分配， packed record ABI 兼容。
  Hook DLL 通过此单元将事件写入主进程创建的 MMF 环形缓冲。
  ***************************************************************************** }

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  DeepRKey.HookShared;

{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$WEAKLINKRTTI ON}
{$OPTIMIZATION ON}
{$STACKFRAMES OFF}

type
  /// <summary>Hook DLL 端 MMF 写入器（无堆分配）</summary>
  TRKeyHookMMFWriter = record
  public
    FMMFHandle: THandle;
    FMMFView: Pointer;
    FHeader: ^TRKeyMMFHeader;
    FSlots: PByte;
    FMMFSize: UInt32;
    FEventSeq: UInt64;
    FNotifyHwnd: HWND;
    FNotifyMsg: UINT;
    FMutexHandle: THandle;  // BUG-H6: 命名 Mutex 替代自旋锁
    function IsReady: Boolean;
  end;

/// <summary>初始化写入器：打开主进程创建的 MMF</summary>
/// <remarks>T-455: 使用 PChar 替代 string，避免托管类型在 Hook DLL 中使用</remarks>
function HookMMFInit(out Writer: TRKeyHookMMFWriter;
  AGUID: PChar): Boolean;

/// <summary>写入一个事件到 MMF 环形缓冲（自旋锁 + Interlocked）</summary>
function HookMMFWriteEvent(var Writer: TRKeyHookMMFWriter;
  const Event: TRKeyIpcEvent): Boolean;

/// <summary>构建一个基础事件结构（填充 Magic/Version/Size/Sequence/Cookie）</summary>
procedure HookMMFBuildEvent(var Writer: TRKeyHookMMFWriter;
  EventKind: UInt32; Hwnd: HWND; CommandId: UInt32;
  Param1, Param2: Int64; Priority: UInt16;
  out Event: TRKeyIpcEvent);

/// <summary>关闭写入器</summary>
procedure HookMMFFinalize(var Writer: TRKeyHookMMFWriter);

/// <summary>尝试向主进程发送通知（PostMessage 到注册的隐藏窗口）</summary>
procedure HookMMFNotify(var Writer: TRKeyHookMMFWriter);

implementation

{ TRKeyHookMMFWriter }

function TRKeyHookMMFWriter.IsReady: Boolean;
begin
  Result := FHeader <> nil;
end;

const
  RK_MMF_MAIN_WND_CLASS = 'DeepRKey_IPC_Wnd_v1';

function HookMMFInit(out Writer: TRKeyHookMMFWriter;
  AGUID: PChar): Boolean;
var
  mmfName: array[0..259] of Char;  // MAX_PATH (260) 足够
  mutexName: array[0..259] of Char;
  mmfSize: UInt32;
  guidLen: Integer;
begin
  Writer.FMMFHandle := 0;
  Writer.FMMFView := nil;
  Writer.FHeader := nil;
  Writer.FSlots := nil;
  Writer.FMMFSize := 0;
  Writer.FEventSeq := 0;
  Writer.FNotifyHwnd := 0;
  Writer.FNotifyMsg := 0;
  Writer.FMutexHandle := 0;

  // T-455: 使用固定缓冲区构建 MMF 名称，避免托管字符串
  guidLen := lstrlen(AGUID);
  if guidLen > 200 then guidLen := 200;  // 防止溢出
  lstrcpyn(mmfName, PChar(RK_MMF_PREFIX), SizeOf(mmfName) div SizeOf(Char));
  lstrcpyn(@mmfName[lstrlen(mmfName)], AGUID, guidLen + 1);
  mmfName[lstrlen(RK_MMF_PREFIX) + guidLen] := #0;

  mmfSize := RK_MMF_HEADER_SIZE + RK_MMF_SLOT_COUNT * RK_MMF_SLOT_SIZE;

  Writer.FMMFHandle := OpenFileMapping(FILE_MAP_READ or FILE_MAP_WRITE,
    False, mmfName);
  if Writer.FMMFHandle = 0 then
    Exit(False);

  Writer.FMMFView := MapViewOfFile(Writer.FMMFHandle,
    FILE_MAP_READ or FILE_MAP_WRITE, 0, 0, mmfSize);
  if Writer.FMMFView = nil then
  begin
    CloseHandle(Writer.FMMFHandle);
    Writer.FMMFHandle := 0;
    Exit(False);
  end;

  Writer.FMMFSize := mmfSize;
  Writer.FHeader := Writer.FMMFView;
  Writer.FSlots := PByte(NativeUInt(Writer.FMMFView) + RK_MMF_HEADER_SIZE);

  // BUG-H6 修复 + BUG-H9：打开命名 Mutex 替代自旋锁（OS 自动释放崩溃进程的锁）
  // MUTEX_MODIFY_STATE 是 ReleaseMutex 所必需的权限
  // T-455: 使用固定缓冲区构建 Mutex 名称，避免托管字符串
  lstrcpyn(mutexName, PChar(RK_MMF_PREFIX), SizeOf(mutexName) div SizeOf(Char));
  lstrcpyn(@mutexName[lstrlen(mutexName)], AGUID, guidLen + 1);
  lstrcpyn(@mutexName[lstrlen(RK_MMF_PREFIX) + guidLen], PChar('_Mutex'), 7);
  mutexName[lstrlen(RK_MMF_PREFIX) + guidLen + 6] := #0;
  Writer.FMutexHandle := OpenMutex(SYNCHRONIZE or MUTEX_MODIFY_STATE, False, mutexName);
  // 如果 Mutex 不存在，回退到自旋锁（兼容旧版主进程）
  if Writer.FMutexHandle = 0 then
    OutputDebugString('DeepRKey Hook: Mutex not found, falling back to spinlock');

  // 查找主进程通知窗口
  Writer.FNotifyHwnd := FindWindow(RK_MMF_MAIN_WND_CLASS, nil);
  if Writer.FNotifyHwnd <> 0 then
    // T-455: 使用常量字符串，避免运行时拼接
    Writer.FNotifyMsg := RegisterWindowMessage('DeepRKey_HookEvent_v1');

  Result := True;
end;

function TryAcquireSpinLock(var Lock: UInt32): Boolean;
var
  lockRef: Integer absolute Lock;
begin
  Result := InterlockedCompareExchange(lockRef, SPINLOCK_LOCKED, SPINLOCK_IDLE)
    = SPINLOCK_IDLE;
end;

procedure ReleaseSpinLock(var Lock: UInt32);
var
  lockRef: Integer absolute Lock;
begin
  InterlockedExchange(lockRef, SPINLOCK_IDLE);
end;

function HookMMFWriteEvent(var Writer: TRKeyHookMMFWriter;
  const Event: TRKeyIpcEvent): Boolean;
var
  writeIdx, nextWrite: UInt32;
  slotOffset: Cardinal;
  waitResult: DWORD;
begin
  Result := False;
  if Writer.FHeader = nil then Exit;

  // BUG-H6 修复 + BUG-H9：使用命名 Mutex 替代自旋锁（OS 自动释放崩溃进程的锁）
  // WAIT_ABANDONED_0 表示前持有者崩溃，OS 已将锁授予当前线程，故接受
  if Writer.FMutexHandle <> 0 then
  begin
    // 使用 Mutex，超时 1 秒防止死锁
    waitResult := WaitForSingleObject(Writer.FMutexHandle, 1000);
    if (waitResult <> WAIT_OBJECT_0) and (waitResult <> WAIT_ABANDONED_0) then
    begin
      // 获取锁失败：丢弃事件（命令事件计数）
      if Event.Priority = RK_EVENT_PRIORITY_COMMAND then
        InterlockedIncrement64(Int64(Writer.FHeader.CommandDropCount));
      Exit;
    end;
  end
  else
  begin
    // 回退到自旋锁（兼容旧版主进程）
    var retries := 0;
    while not TryAcquireSpinLock(Writer.FHeader.WriteLock) do
    begin
      Inc(retries);
      if retries >= SPINLOCK_MAX_RETRIES then
      begin
        if Event.Priority = RK_EVENT_PRIORITY_COMMAND then
          InterlockedIncrement64(Int64(Writer.FHeader.CommandDropCount));
        Exit;
      end;
      YieldProcessor;
    end;
    // BUG-M10/T-435 修复：ARM64 显式 acquire 屏障，保证锁获取后共享内存读取可见
    MemoryBarrier;
  end;

  try
    writeIdx := UInt32(InterlockedCompareExchange(
      Integer(Writer.FHeader.WriteIndex), 0, 0));
    nextWrite := (writeIdx + 1) mod RK_MMF_SLOT_COUNT;

    // 检查缓冲是否已满
    if nextWrite = UInt32(InterlockedCompareExchange(
      Integer(Writer.FHeader.ReadIndex), 0, 0)) then
    begin
      // 缓冲满
      if Event.Priority = RK_EVENT_PRIORITY_COMMAND then
      begin
        // 命令事件：丢弃最旧的（覆盖 ReadIndex）
        var newRead := (UInt32(InterlockedCompareExchange(
          Integer(Writer.FHeader.ReadIndex), 0, 0)) + 1) mod RK_MMF_SLOT_COUNT;
        InterlockedExchange(Integer(Writer.FHeader.ReadIndex), Integer(newRead));
        InterlockedIncrement64(Int64(Writer.FHeader.CommandDropCount));
      end
      else
      begin
        // 普通事件：丢弃当前事件
        InterlockedIncrement64(Int64(Writer.FHeader.DroppedEventCount));
        Exit;
      end;
    end;

    // 写入 slot
    slotOffset := Cardinal(writeIdx) * Cardinal(RK_MMF_SLOT_SIZE);
    Move(Event, Pointer(NativeUInt(Writer.FSlots) + slotOffset)^,
      SizeOf(TRKeyIpcEvent));

    // BUG-M10/T-435 修复：ARM64 release 屏障，保证 slot 数据写入在 WriteIndex 推进前对读端可见
    MemoryBarrier;

    // 推进写指针
    InterlockedExchange(Integer(Writer.FHeader.WriteIndex), Integer(nextWrite));

    Result := True;
  finally
    if Writer.FMutexHandle <> 0 then
      ReleaseMutex(Writer.FMutexHandle)
    else
    begin
      // BUG-M10/T-435 修复：ARM64 显式 release 屏障，保证 slot 写入在锁释放前对读端可见
      MemoryBarrier;
      ReleaseSpinLock(Writer.FHeader.WriteLock);
    end;
  end;
end;

procedure HookMMFBuildEvent(var Writer: TRKeyHookMMFWriter;
  EventKind: UInt32; Hwnd: HWND; CommandId: UInt32;
  Param1, Param2: Int64; Priority: UInt16;
  out Event: TRKeyIpcEvent);
begin
  ZeroMemory(@Event, SizeOf(TRKeyIpcEvent));
  Event.Magic := RK_EVENT_MAGIC;
  Event.Version := 1;
  Event.Size := SizeOf(TRKeyIpcEvent);

  Inc(Writer.FEventSeq);
  Event.Sequence := Writer.FEventSeq;

  // AuthCookie 从 MMF Header 读取
  if Writer.FHeader <> nil then
    Event.AuthCookie := Writer.FHeader.AuthCookie;

  Event.ProcessId := GetCurrentProcessId;
  Event.ThreadId := GetCurrentThreadId;
  Event.Hwnd := UInt64(NativeUInt(Hwnd));
  Event.EventKind := EventKind;
  Event.CommandId := CommandId;
  Event.Param1 := Param1;
  Event.Param2 := Param2;
  Event.Priority := Priority;
  Event.Flags := 0;

  // CRC32（排除 Crc32 字段本身和 Padding 字段）
  Event.Crc32 := 0;
  Event.Crc32 := ComputeCRC32(Event, SizeOf(TRKeyIpcEvent) - 52);
end;

procedure HookMMFFinalize(var Writer: TRKeyHookMMFWriter);
begin
  // BUG-H6: 关闭命名 Mutex 句柄
  if Writer.FMutexHandle <> 0 then
  begin
    CloseHandle(Writer.FMutexHandle);
    Writer.FMutexHandle := 0;
  end;
  if Writer.FMMFView <> nil then
  begin
    UnmapViewOfFile(Writer.FMMFView);
    Writer.FMMFView := nil;
  end;
  if Writer.FMMFHandle <> 0 then
  begin
    CloseHandle(Writer.FMMFHandle);
    Writer.FMMFHandle := 0;
  end;
  Writer.FHeader := nil;
  Writer.FSlots := nil;
end;

procedure HookMMFNotify(var Writer: TRKeyHookMMFWriter);
begin
  if (Writer.FNotifyHwnd <> 0) and (Writer.FNotifyMsg <> 0) then
    PostMessage(Writer.FNotifyHwnd, Writer.FNotifyMsg, 0, 0);
end;

end.
