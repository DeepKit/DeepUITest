unit DeepRKey.IPCRouter;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  DeepRKey.HookShared,
  DeepRKey.IPC.MMF,
  DeepRKey.Types;

type
  /// <summary>IPC 路由器：异步消息路由（PostMessage + MMF 读）</summary>
  TRKeyIPCRouter = class
  private
    FMMFReader: TRKeyMMFRingBuffer;
    FMainWndHandle: HWND;
    FEventMessageId: UINT;
    FAuthCookie: TGUID;
    // BUG-M4 修复：每个注入 DLL 独立从 1 开始计数，Router 须按进程 ID 跟踪序列
    FPerProcessSeq: TDictionary<UInt32, UInt64>;
    FPendingEvents: TQueue<TRKeyIpcEvent>;
    procedure DispatchEvent(const Event: TRKeyIpcEvent);
    function ValidateEvent(const Event: TRKeyIpcEvent): Boolean;
  public
    constructor Create(const AGUID: string; AMainWndHandle: HWND;
      const AAuthCookie: TGUID);
    destructor Destroy; override;

    /// <summary>创建 MMF 和注册消息</summary>
    procedure Initialize;

    /// <summary>处理 PostMessage 通知 — 从 MMF 读取事件</summary>
    procedure ProcessNotification;

    /// <summary>更新心跳时间戳</summary>
    procedure UpdateHeartbeat;

    /// <summary>读取所有待处理事件</summary>
    function ReadAllEvents: TArray<TRKeyIpcEvent>;

    /// <summary>获取 MMF 读取器</summary>
    property MMFReader: TRKeyMMFRingBuffer read FMMFReader;

    /// <summary>获取已注册的消息 ID</summary>
    property EventMessageId: UINT read FEventMessageId;
  end;

implementation

{ TRKeyIPCRouter }

constructor TRKeyIPCRouter.Create(const AGUID: string; AMainWndHandle: HWND;
  const AAuthCookie: TGUID);
begin
  FMMFReader := TRKeyMMFRingBuffer.Create(AGUID);
  FMainWndHandle := AMainWndHandle;
  FAuthCookie := AAuthCookie;
  // BUG-M4 修复：每个注入 DLL 独立从 1 开始计数，按进程 ID 跟踪序列
  FPerProcessSeq := TDictionary<UInt32, UInt64>.Create;
  FPendingEvents := TQueue<TRKeyIpcEvent>.Create;
end;

destructor TRKeyIPCRouter.Destroy;
begin
  FPendingEvents.Free;
  // BUG-M4: 清理按进程序列号字典
  FPerProcessSeq.Free;
  FMMFReader.Free;
  inherited;
end;

procedure TRKeyIPCRouter.Initialize;
begin
  // 注册动态消息 ID
  FEventMessageId := RegisterWindowMessage(PChar(RK_MMF_PREFIX + 'Event_v1'));

  // 创建 MMF
  FMMFReader.CreateMMF(FAuthCookie);

  OutputDebugString(PChar(Format('[DeepRKey] IPC Router initialized: MMF=%s, MsgID=%d',
    [FMMFReader.MMFName, FEventMessageId])));
end;

function TRKeyIPCRouter.ValidateEvent(const Event: TRKeyIpcEvent): Boolean;
var
  lastSeq: UInt64;
begin
  Result := False;

  // 验证 Magic
  if Event.Magic <> RK_EVENT_MAGIC then
    Exit;

  // 验证 AuthCookie
  if not CompareMem(@Event.AuthCookie, @FAuthCookie, SizeOf(TGUID)) then
    Exit;

  // BUG-M4 修复：按进程 ID 跟踪序列号，每个注入 DLL 独立从 1 开始计数
  // 多进程注入时，全局序列号会拒绝合法多进程事件
  if not FPerProcessSeq.TryGetValue(Event.ProcessId, lastSeq) then
    lastSeq := 0;

  // 验证 Sequence 单调性（同一进程内）
  if Event.Sequence <= lastSeq then
    Exit;

  Result := True;
end;

procedure TRKeyIPCRouter.DispatchEvent(const Event: TRKeyIpcEvent);
begin
  if not ValidateEvent(Event) then
  begin
    OutputDebugString('[DeepRKey] IPC: event validation failed');
    Exit;
  end;

  // BUG-M4 修复：按进程 ID 更新序列号
  FPerProcessSeq.AddOrSetValue(Event.ProcessId, Event.Sequence);

  // 暂存事件，由主线程处理
  FPendingEvents.Enqueue(Event);

  // 通知主窗口
  PostMessage(FMainWndHandle, FEventMessageId, 0, 0);
end;

procedure TRKeyIPCRouter.ProcessNotification;
begin
  // 从 MMF 读取所有事件
  var event: TRKeyIpcEvent;
  while FMMFReader.ReadEvent(event) do
    DispatchEvent(event);
end;

procedure TRKeyIPCRouter.UpdateHeartbeat;
begin
  FMMFReader.UpdateHeartbeat;
end;

function TRKeyIPCRouter.ReadAllEvents: TArray<TRKeyIpcEvent>;
begin
  SetLength(Result, FPendingEvents.Count);
  var i := 0;
  while FPendingEvents.Count > 0 do
  begin
    Result[i] := FPendingEvents.Dequeue;
    Inc(i);
  end;
end;

end.