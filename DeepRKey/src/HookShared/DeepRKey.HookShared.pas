unit DeepRKey.HookShared;

interface

{ *****************************************************************************
  HookShared 包 — 跨进程 ABI 契约

  约束（详见 docs/02.技术方案.md §9）：
  - 仅允许 Winapi 单元
  - 纯 POD packed record + 固定宽度整数
  - 禁止字符串、托管类型、Object
  - 禁止堆分配（GetMem/AllocMem/VirtualAlloc/New）
  - 禁止 System.SysUtils, System.Generics.Collections, System.Classes
  - 禁止 DLL initialization / finalization 段
  - $RTTI EXPLICIT + $OPTIMIZATION ON + $STACKFRAMES OFF
  ***************************************************************************** }

uses
  Winapi.Windows,
  Winapi.Messages;

{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$WEAKLINKRTTI ON}
{$OPTIMIZATION ON}
{$STACKFRAMES OFF}

const
  // IPC 消息标识
  WM_DEEPRKEY_HOOK_EVENT_NAME = 'DeepRKey_HookEvent_v1';

  // MMF 命名前缀
  RK_MMF_PREFIX = 'Local\DeepRKey_MMF_';
  RK_PIPE_PREFIX = '\\.\pipe\DeepRKey_';

  // 环形缓冲器常量
  RK_MMF_SLOT_COUNT = 128;
  RK_MMF_SLOT_SIZE  = 128;   // 字节
  RK_MMF_HEADER_SIZE = 64;   // 字节

  // 事件优先级
  RK_EVENT_PRIORITY_NORMAL  = 0;  // 可丢弃
  RK_EVENT_PRIORITY_COMMAND = 1;  // 不允许静默丢弃

  // 事件标志
  RK_EVENT_FLAG_RESERVED = 0;

  // 事件 Magic
  RK_EVENT_MAGIC = $594B5244;  // 'DRKY' (little-endian)

  // 管道帧 Magic
  RK_PIPE_MAGIC = $504B5244;  // 'DRKP' (little-endian)

  // 自旋锁常量
  SPINLOCK_IDLE = 0;
  SPINLOCK_LOCKED = 1;
  SPINLOCK_MAX_RETRIES = 3;

  // CRC32 查找表（编译期常量，避免运行时初始化）
  CRC32Table: array[0..255] of UInt32 = (
    $00000000, $77073096, $EE0E612C, $990951BA, $076DC419, $706AF48F,
    $E963A535, $9E6495A3, $0EDB8832, $79DCB8A4, $E0D5E91E, $97D2D988,
    $09B64C2B, $7EB17CBD, $E7B82D07, $90BF1D91, $1DB71064, $6AB020F2,
    $F3B97148, $84BE41DE, $1ADAD47D, $6DDDE4EB, $F4D4B551, $83D385C7,
    $136C9856, $646BA8C0, $FD62F97A, $8A65C9EC, $14015C4F, $63066CD9,
    $FA0F3D63, $8D080DF5, $3B6E20C8, $4C69105E, $D56041E4, $A2677172,
    $3C03E4D1, $4B04D447, $D20D85FD, $A50AB56B, $35B5A8FA, $42B2986C,
    $DBBBC9D6, $ACBCF940, $32D86CE3, $45DF5C75, $DCD60DCF, $ABD13D59,
    $26D930AC, $51DE003A, $C8D75180, $BFD06116, $21B4F4B5, $56B3C423,
    $CFBA9599, $B8BDA50F, $2802B89E, $5F058808, $C60CD9B2, $B10CB924,
    $2F6F7C87, $58684C11, $C1611DAB, $B6662D3D, $76DC4190, $01DB7106,
    $98D220BC, $EFD5102A, $71B18589, $06B6B51F, $9FBFE4A5, $E8B8D433,
    $7807C9A2, $0F00F934, $9609A88E, $E10E9818, $7F6A0DBB, $086D3D2D,
    $91646C97, $E6635C01, $6B6B51F4, $1C6C6162, $856530D8, $F262004E,
    $6C0695ED, $1B01A57B, $8208F4C1, $F50FC457, $65B0D9C6, $12B7E950,
    $8BBEB8EA, $FCB9887C, $62DD1DDF, $15DA2D49, $8CD37CF3, $FBD44C65,
    $4DB26158, $3AB551CE, $A3BC0074, $D4BB30E2, $4ADFA541, $3DD895D7,
    $A4D1C46D, $D3D6F4FB, $4369E96A, $346ED9FC, $AD678846, $DA60B8D0,
    $44042D73, $33031DE5, $AA0A4C5F, $DD0D7CC9, $5005713C, $270241AA,
    $BE0B1010, $C90C2086, $5768B525, $206F85B3, $B966D409, $CE61E49F,
    $5EDEF90E, $29D9C998, $B0D09822, $C7D7A8B4, $59B33D17, $2EB40D81,
    $B7BD5C3B, $C0BA6CAD, $EDB88320, $9ABFB3B6, $03B6E20C, $74B1D29A,
    $EAD54739, $9DD277AF, $04DB2615, $73DC1683, $E3630B12, $94643B84,
    $0D6D6A3E, $7A6A5AA8, $E40ECF0B, $9309FF9D, $0A00AE27, $7D079EB1,
    $F00F9344, $8708A3D2, $1E01F268, $6906C2FE, $F762575D, $806567CB,
    $196C3671, $6E6B06E7, $FED41B76, $89D32BE0, $10DA7A5A, $67DD4ACC,
    $F9B9DF6F, $8EBEEFF9, $17B7BE43, $60B08ED5, $D6D6A3E8, $A1D1937E,
    $38D8C2C4, $4FDFF252, $D1BB67F1, $A6BC5767, $3FB506DD, $48B2364B,
    $D80D2BDA, $AF0A1B4C, $36034AF6, $41047A60, $DF60EFC3, $A867DF55,
    $316E8EEF, $4669BE79, $CB61B38C, $BC66831A, $256FD2A0, $5268E236,
    $CC0C7795, $BB0B4703, $220216B9, $5505262F, $C5BA3BBE, $B2BD0B28,
    $2BB45A92, $5CB36A04, $C2D7FFA7, $B5D0CF31, $2CD99E8B, $5BDEAE1D,
    $9B64C2B0, $EC63F226, $756AA39C, $026D930A, $9C0906A9, $EB0E363F,
    $72076785, $05005713, $95BF4A82, $E2B87A14, $7BB12BAE, $0CB61B38,
    $92D28E9B, $E5D5BE0D, $7CDCEFB7, $0BDBDF21, $86D3D2D4, $F1D4E242,
    $68DDB3F8, $1FDA836E, $81BE16CD, $F6B9265B, $6FB077E1, $18B74777,
    $88085AE6, $FF0F6A70, $66063BCA, $11010B5C, $8F659EFF, $F862AE69,
    $616BFFD3, $166CCF45, $A00AE278, $D70DD2EE, $4E048354, $3903B3C2,
    $A7672661, $D06016F7, $4969474D, $3E6E77DB, $AED16A4A, $D9D65ADC,
    $40DF0B66, $37D83BF0, $A9BCAE53, $DEBB9EC5, $47B2CF7F, $30B5FFE9,
    $BDBDF21C, $CABAC28A, $53B39330, $24B4A3A6, $BAD03605, $CDD70693,
    $54DE5729, $23D967BF, $B3667A2E, $C4614AB8, $5D681B02, $2A6F2B94,
    $B40BBE37, $C30C8EA1, $5A05DF1B, $2D02EF8D
  );

type
  /// <summary>IPC 事件契约（128 字节，两缓存行）</summary>
  TRKeyIpcEvent = packed record
    Magic: UInt32;              // 'DRKY'
    Version: UInt16;            // 当前为 1
    Size: UInt16;               // 结构尺寸 = 128
    Sequence: UInt64;           // 单调递增，防重放
    AuthCookie: TGUID;          // 完整 128-bit cookie
    ProcessId: UInt32;
    ThreadId: UInt32;
    Hwnd: UInt64;               // 统一按 UInt64 存储 HWND
    EventKind: UInt32;          // TRKeyEventKind
    CommandId: UInt32;          // DeepRKey 私有菜单 ID
    Param1: Int64;
    Param2: Int64;
    Priority: UInt16;           // RK_EVENT_PRIORITY_*
    Flags: UInt16;              // 保留
    Crc32: UInt32;
    _Padding: array[0..47] of Byte; // 填充到 128 字节
  end;

  /// <summary>MMF Header（64 字节，v0.6 ABI 固化）</summary>
  TRKeyMMFHeader = packed record
    Version: UInt32;            // Header 版本
    EventCount: UInt32;         // 槽位数量 = 128
    WriteIndex: UInt32;         // 原子写指针
    ReadIndex: UInt32;          // 主进程读指针
    DroppedEventCount: UInt64;  // 普通事件丢弃计数
    CommandDropCount: UInt64;   // 命令事件丢弃/争用计数
    AuthCookie: TGUID;          // 完整 128-bit cookie
    HeartbeatTick: UInt64;      // 主进程心跳
    WriteLock: UInt32;          // 跨进程写锁（0=空闲，1=锁定）
    Padding: UInt32;            // 填充到 64 字节
  end;

  /// <summary>命名管道帧头（32 字节）</summary>
  TPipeFrameHeader = packed record
    Magic: UInt32;              // 'DRKP'
    FrameLength: UInt32;        // 整个帧长度（含 header）
    MessageId: UInt32;          // 请求/响应 ID
    Sequence: UInt64;           // 关联的事件 sequence
    Command: UInt32;            // 命令类型
    Crc32: UInt32;
    _Padding: array[0..3] of Byte; // 32 字节对齐
  end;

  /// <summary>管道命令类型</summary>
  TPipeCommand = (
    pcInstallHook    = 0,
    pcUninstallHook  = 1,
    pcUninstallAll   = 2,
    pcShutdown       = 3,
    pcAck            = 4,
    pcNack           = 5,
    pcHeartbeat      = 6,
    pcHeartbeatAck   = 7,
    pcInstallGlobalHook = 8  // T-441: 32-bit global hook via Helper32
  );

const
  // === 事件类型（与 DeepRKey.Types.TRKeyEventKind 值对齐）===
  RK_EK_INIT_MENU    = 0;  // rekInitMenu
  RK_EK_SYS_COMMAND  = 1;  // rekSysCommand
  RK_EK_HOOK_READY   = 2;  // rekThreadHookReady
  RK_EK_HOOK_FAILED  = 3;  // rekThreadHookFailed

  // === 菜单 ID 范围（与 DeepRKey.Types 对齐）===
  RK_SC_BASE = $7000;
  RK_SC_MAX  = $7FF0;
  RK_SC_STEP = $0010;

/// <summary>CRC32 计算（查表实现）</summary>
function ComputeCRC32(const Data; Len: UInt32): UInt32;

/// <summary>T-442: 快速进程级 Hook 准入检查（Hook DLL 可在 HookProc 入口调用）</summary>
/// <returns>True=当前进程是正常 GUI 进程，可安全执行 Hook 逻辑</returns>
function IsHookProcessEligible: Boolean;

// ABI 尺寸验证（编译期门禁）
{$IFOPT C+}
{$IF SizeOf(TRKeyIpcEvent) <> 128}
  {$MESSAGE Fatal 'TRKeyIpcEvent must be 128 bytes'}
{$ENDIF}
{$IF SizeOf(TRKeyMMFHeader) <> 64}
  {$MESSAGE Fatal 'TRKeyMMFHeader must be 64 bytes'}
{$ENDIF}
{$IF SizeOf(TPipeFrameHeader) <> 32}
  {$MESSAGE Fatal 'TPipeFrameHeader must be 32 bytes'}
{$ENDIF}
{$ENDIF}

implementation

function ComputeCRC32(const Data; Len: UInt32): UInt32;
begin
  var crc: UInt32 := $FFFFFFFF;
  var p := PByte(@Data);
  for var i: UInt32 := 0 to Len - 1 do
  begin
    crc := ((crc shr 8) and $00FFFFFF) xor CRC32Table[(crc xor p^) and $FF];
    Inc(p);
  end;
  Result := crc xor $FFFFFFFF;
end;

function IsHookProcessEligible: Boolean;
const
  // 排除的系统进程（不区分大小写）
  EXCLUDED_PROC_COUNT = 8;
  ExcludedProcesses: array[0..EXCLUDED_PROC_COUNT - 1] of string = (
    'csrss.exe', 'smss.exe', 'winlogon.exe', 'lsass.exe',
    'services.exe', 'svchost.exe', 'System', 'Idle'
  );
var
  fullPath: array[0..MAX_PATH] of Char;
  len: DWORD;
  name: string;
  i, j: Integer;
  guiInfo: TGUIThreadInfo;
  ch: Char;
begin
  // 1. 检查进程名是否在排除列表中
  len := GetModuleFileName(0, fullPath, MAX_PATH);
  if len > 0 then
  begin
    // 从完整路径中提取文件名
    name := '';
    i := len;
    while (i > 0) and (fullPath[i - 1] <> '\') do
      Dec(i);
    for j := i to len - 1 do
      name := name + fullPath[j];

    // 手动大小写不敏感比较（HookShared 不能使用 SysUtils.LowerCase）
    for i := 0 to EXCLUDED_PROC_COUNT - 1 do
    begin
      if Length(name) <> Length(ExcludedProcesses[i]) then
        Continue;
      var match := True;
      for j := 1 to Length(name) do
      begin
        ch := name[j];
        if (ch >= 'A') and (ch <= 'Z') then
          ch := Char(Ord(ch) or 32);
        var ech := ExcludedProcesses[i][j];
        if (ech >= 'A') and (ech <= 'Z') then
          ech := Char(Ord(ech) or 32);
        if ch <> ech then
        begin
          match := False;
          Break;
        end;
      end;
      if match then
        Exit(False);
    end;
  end;

  // 2. 检查是否有 GUI 线程消息队列（fast path：无 GUI 的 CLI 进程无需 Hook）
  guiInfo.cbSize := SizeOf(guiInfo);
  if not GetGUIThreadInfo(0, guiInfo) then
    Exit(False);

  Result := True;
end;

end.