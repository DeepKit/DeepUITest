unit DeepRKey.HookController;

{ T-500: Thread-Level Hook Architecture

  Replaces the global WH_CALLWNDPROC hook (threadId=0, intercepts ALL GUI messages
  system-wide) with per-thread hooks installed only for threads that own eligible windows.

  Key design:
  - WinEventProc detects eligible windows → calls EnsureThreadHook(hWnd)
  - For 64-bit threads: direct SetWindowsHookEx via worker thread (5s timeout)
  - For 32-bit threads: pipe command to Helper32 process
  - SweepCheck (called from 30s purge timer) uninstalls hooks for idle threads
  - Hot cache (LRU 8) prevents sweep churn on active threads
  - Idle TTL = 120s before uninstall }

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  DeepRKey.Types,
  DeepRKey.WindowTracker,
  DeepRKey.HelperManager;

type
  THookProc = function(code: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;

  THookThreadEntry = record
    HookHandle: HHOOK;
    State: THookThreadState;
    RefCount: Integer;
    WindowSet: TList<NativeUInt>;
    LastActiveTick: UInt64;
    ProcessId: DWORD;
    Is32Bit: Boolean;
    procedure Init;
    procedure Free;
  end;

  THookInstallRequest = record
    ThreadId: DWORD;
    Hwnd: HWND;
    ProcessId: DWORD;
    Is32Bit: Boolean;
    Valid: Boolean;
  end;

  // Simple thread-safe queue (TThreadedQueue constructor incompatible in Delphi 13.1)
  THookInstallQueue = class
  private
    FQueue: TQueue<THookInstallRequest>;
    FCS: TCriticalSection;
    FEvent: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const AItem: THookInstallRequest);
    function Dequeue(out AItem: THookInstallRequest; TimeoutMs: Cardinal): Boolean;
  end;

  THookInstallWorker = class(TThread)
  private
    FController: TObject;
    FQueue: THookInstallQueue;
  protected
    procedure Execute; override;
  public
    constructor Create(AController: TObject; AQueue: THookInstallQueue);
  end;

  THookController = class
  private
    FCS: TCriticalSection;
    FThreads: TDictionary<DWORD, THookThreadEntry>;
    FHotThreadSet: TList<DWORD>;
    FWindowTracker: TWindowTracker;
    FHelperManager: THelperManager;
    FInstallQueue: THookInstallQueue;
    FWorkers: array of THookInstallWorker;
    FHookDllModule: HMODULE;
    FHookProc: THookProc;
    FIsSweepPaused: Boolean;
    function GetThreadCount: Integer;
    function GetActiveHookCount: Integer;
    procedure UpdateHotCache(ThreadId: DWORD);
    procedure DoSweepIdleHooks;
  public
    constructor Create(AWindowTracker: TWindowTracker; AHelperManager: THelperManager);
    destructor Destroy; override;

    /// <summary>Load hook DLL and prepare for installation</summary>
    procedure Initialize(const AHookDllPath: string);

    /// <summary>Ensure a hook is installed for the thread owning hWnd</summary>
    procedure EnsureThreadHook(hWnd: HWND);

    /// <summary>Called when a window is destroyed — decrements ref count</summary>
    procedure NotifyWindowDestroyed(hWnd: HWND);

    /// <summary>Periodic sweep — called from purge timer (30s)</summary>
    procedure SweepCheck;

    /// <summary>Called by worker thread after successful 64-bit hook install</summary>
    procedure CompleteHookInstall(ThreadId: DWORD; HookHandle: HHOOK);

    /// <summary>Called after 32-bit hook install via Helper32</summary>
    procedure CompleteHookInstall32(ThreadId: DWORD);

    /// <summary>Mark a thread's hook install as pending (retry later)</summary>
    procedure MarkHookInstallPending(ThreadId: DWORD);

    /// <summary>Uninstall all hooks and clean up</summary>
    procedure UnloadAllHooks;

    /// <summary>Diagnostics for CLI --diagnostics</summary>
    function GetDiagnosticsSnapshot: THookDiagnosticsSnapshot;

    /// <summary>Reset state for unit testing</summary>
    procedure ResetForTesting;

    property ThreadCount: Integer read GetThreadCount;
    property ActiveHookCount: Integer read GetActiveHookCount;
    property HookDllModule: HMODULE read FHookDllModule;
    property HookProc: THookProc read FHookProc;
  end;

const
  RK_HOT_THREAD_MAX = 8;
  RK_THREAD_IDLE_TTL = 120000;       // 120 seconds before sweep uninstalls
  RK_HOOK_INSTALL_WORKER_COUNT = 2;
  RK_HOOK_INSTALL_TIMEOUT_MS = 5000; // 5s timeout per SetWindowsHookEx call

implementation

// IsWow64Process declaration — not available in older Delphi Windows unit
const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function IsWow64Process(hProcess: THandle; var Wow64Process: BOOL): BOOL; stdcall;
  external kernel32 name 'IsWow64Process';

/// <summary>Check if a process is 32-bit (WOW64) running on 64-bit Windows</summary>
function IsProcess32Bit(ProcessId: DWORD): Boolean;
var
  hProcess: THandle;
  isWow64: BOOL;
begin
  Result := False;
  hProcess := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, ProcessId);
  if hProcess = 0 then
    Exit;
  try
    isWow64 := False;
    if IsWow64Process(hProcess, isWow64) and isWow64 then
      Result := True;
  finally
    CloseHandle(hProcess);
  end;
end;

{ THookThreadEntry }

procedure THookThreadEntry.Init;
begin
  HookHandle := 0;
  State := hsPendingInstall;
  RefCount := 0;
  WindowSet := TList<NativeUInt>.Create;
  LastActiveTick := GetTickCount64;
  ProcessId := 0;
  Is32Bit := False;
end;

procedure THookThreadEntry.Free;
begin
  WindowSet.Free;
end;

{ THookInstallQueue }

constructor THookInstallQueue.Create;
begin
  inherited Create;
  FQueue := TQueue<THookInstallRequest>.Create;
  FCS := TCriticalSection.Create;
  FEvent := TEvent.Create(nil, False, False, '');
end;

destructor THookInstallQueue.Destroy;
begin
  FEvent.Free;
  FCS.Free;
  FQueue.Free;
  inherited;
end;

procedure THookInstallQueue.Enqueue(const AItem: THookInstallRequest);
begin
  FCS.Enter;
  try
    FQueue.Enqueue(AItem);
  finally
    FCS.Leave;
  end;
  FEvent.SetEvent;
end;

function THookInstallQueue.Dequeue(out AItem: THookInstallRequest; TimeoutMs: Cardinal): Boolean;
begin
  Result := False;
  if FEvent.WaitFor(TimeoutMs) = wrSignaled then
  begin
    FCS.Enter;
    try
      if FQueue.Count > 0 then
      begin
        AItem := FQueue.Dequeue;
        Result := True;
      end;
    finally
      FCS.Leave;
    end;
  end;
end;

{ THookInstallWorker }

constructor THookInstallWorker.Create(AController: TObject; AQueue: THookInstallQueue);
begin
  inherited Create(False);
  FController := AController;
  FQueue := AQueue;
  FreeOnTerminate := False;
end;

procedure THookInstallWorker.Execute;
begin
  while not Terminated do
  begin
    var item: THookInstallRequest;
    if FQueue.Dequeue(item, 1000) then
    begin
      if not item.Valid then
        Continue;

      var controller := THookController(FController);

      // 32-bit threads are handled by Helper32 — skip direct install
      if item.Is32Bit then
      begin
        // For 32-bit, the HelperManager.InstallHook call was already made
        // by EnsureThreadHook before queuing. Just mark as active.
        controller.CompleteHookInstall32(item.ThreadId);
        Continue;
      end;

      // 64-bit: direct SetWindowsHookEx via timeout-protected helper thread
      var hookDllModule := controller.HookDllModule;
      var hookProcLocal: THookProc;
      hookProcLocal := controller.HookProc;
      var threadIdLocal := item.ThreadId;

      if (hookDllModule = 0) or (not Assigned(hookProcLocal)) then
      begin
        controller.MarkHookInstallPending(item.ThreadId);
        Continue;
      end;

      var installDone: Boolean := False;
      var fHook: HHOOK := 0;

      var helperThread := TThread.CreateAnonymousThread(
        procedure
        begin
          fHook := SetWindowsHookEx(WH_CALLWNDPROC, @hookProcLocal,
            hookDllModule, threadIdLocal);
          installDone := True;
        end);
      helperThread.FreeOnTerminate := False;
      helperThread.Start;

      var helperHandle := helperThread.Handle;
      var waitResult := WaitForSingleObject(helperHandle,
        RK_HOOK_INSTALL_TIMEOUT_MS);

      if waitResult = WAIT_OBJECT_0 then
      begin
        controller.CompleteHookInstall(item.ThreadId, fHook);
        helperThread.Free;
      end
      else
      begin
        // Timeout — thread may be stuck, abandon it
        controller.MarkHookInstallPending(item.ThreadId);
        helperThread.FreeOnTerminate := True;
      end;
    end;
  end;
end;

{ THookController }

constructor THookController.Create(AWindowTracker: TWindowTracker;
  AHelperManager: THelperManager);
begin
  FCS := TCriticalSection.Create;
  FThreads := TDictionary<DWORD, THookThreadEntry>.Create(64);
  FHotThreadSet := TList<DWORD>.Create;
  FWindowTracker := AWindowTracker;
  FHelperManager := AHelperManager;
  FInstallQueue := THookInstallQueue.Create;
  FHookDllModule := 0;
  FHookProc := nil;
  FIsSweepPaused := False;

  SetLength(FWorkers, RK_HOOK_INSTALL_WORKER_COUNT);
  for var i := 0 to RK_HOOK_INSTALL_WORKER_COUNT - 1 do
    FWorkers[i] := THookInstallWorker.Create(Self, FInstallQueue);
end;

destructor THookController.Destroy;
begin
  for var i := 0 to Length(FWorkers) - 1 do
  begin
    FWorkers[i].Terminate;
    FWorkers[i].WaitFor;
    FWorkers[i].Free;
  end;

  UnloadAllHooks;

  if FHookDllModule <> 0 then
  begin
    FreeLibrary(FHookDllModule);
    FHookDllModule := 0;
  end;

  FInstallQueue.Free;
  FHotThreadSet.Free;
  FThreads.Free;
  FCS.Free;
  inherited;
end;

procedure THookController.Initialize(const AHookDllPath: string);
begin
  FHookDllModule := LoadLibrary(PChar(AHookDllPath));
  if FHookDllModule = 0 then
    raise Exception.CreateFmt('Failed to load Hook DLL: %s (error %d)',
      [AHookDllPath, GetLastError]);

  FHookProc := THookProc(GetProcAddress(FHookDllModule, 'HookProc'));
  if not Assigned(FHookProc) then
    raise Exception.CreateFmt('HookProc not found in %s', [AHookDllPath]);
end;

procedure THookController.EnsureThreadHook(hWnd: HWND);
var
  threadId, processId: DWORD;
  is32: Boolean;
begin
  threadId := GetWindowThreadProcessId(hWnd, @processId);
  if (threadId = 0) or (processId = 0) then
    Exit;

  is32 := IsProcess32Bit(processId);

  FCS.Enter;
  try
    var entry: THookThreadEntry;
    if FThreads.TryGetValue(threadId, entry) then
    begin
      // Thread already tracked — just update
      if not entry.WindowSet.Contains(NativeUInt(hWnd)) then
        entry.WindowSet.Add(NativeUInt(hWnd));
      InterlockedIncrement(entry.RefCount);
      entry.LastActiveTick := GetTickCount64;
      if entry.State = hsIdle then
        entry.State := hsActive;
      FThreads.AddOrSetValue(threadId, entry);
      UpdateHotCache(threadId);
      Exit;
    end;

    // New thread — create entry and queue install
    var newEntry: THookThreadEntry;
    newEntry.Init;
    newEntry.State := hsPendingInstall;
    newEntry.WindowSet.Add(NativeUInt(hWnd));
    newEntry.RefCount := 1;
    newEntry.ProcessId := processId;
    newEntry.Is32Bit := is32;
    newEntry.LastActiveTick := GetTickCount64;
    FThreads.Add(threadId, newEntry);
    FCS.Leave;

    try
      if is32 then
      begin
        // 32-bit: route through Helper32
        if (FHelperManager <> nil) and FHelperManager.InstallHook(threadId) then
          CompleteHookInstall32(threadId)
        else
          MarkHookInstallPending(threadId);
      end
      else
      begin
        // 64-bit: queue for worker thread
        var req: THookInstallRequest;
        req.ThreadId := threadId;
        req.Hwnd := hWnd;
        req.ProcessId := processId;
        req.Is32Bit := False;
        req.Valid := True;
        FInstallQueue.Enqueue(req);
      end;
    finally
      FCS.Enter;
    end;
  finally
    FCS.Leave;
  end;
end;

procedure THookController.NotifyWindowDestroyed(hWnd: HWND);
begin
  FCS.Enter;
  try
    for var pair in FThreads do
    begin
      var threadId := pair.Key;
      var entry := pair.Value;
      if entry.WindowSet.Contains(NativeUInt(hWnd)) then
      begin
        entry.WindowSet.Remove(NativeUInt(hWnd));
        InterlockedDecrement(entry.RefCount);
        entry.LastActiveTick := GetTickCount64;
        FThreads.AddOrSetValue(threadId, entry);
        Exit;
      end;
    end;
  finally
    FCS.Leave;
  end;
end;

procedure THookController.CompleteHookInstall(ThreadId: DWORD; HookHandle: HHOOK);
begin
  FCS.Enter;
  try
    var entry: THookThreadEntry;
    if not FThreads.TryGetValue(ThreadId, entry) then
      Exit;
    entry.HookHandle := HookHandle;
    if HookHandle <> 0 then
      entry.State := hsActive
    else
      entry.State := hsIdle;
    FThreads.AddOrSetValue(ThreadId, entry);
  finally
    FCS.Leave;
  end;
end;

procedure THookController.CompleteHookInstall32(ThreadId: DWORD);
begin
  // For 32-bit threads, we don't get an HHOOK back (Helper32 owns it).
  // Mark as active so sweep doesn't try to uninstall it directly.
  FCS.Enter;
  try
    var entry: THookThreadEntry;
    if not FThreads.TryGetValue(ThreadId, entry) then
      Exit;
    entry.HookHandle := 0; // Helper32 owns the actual handle
    entry.State := hsActive;
    FThreads.AddOrSetValue(ThreadId, entry);
  finally
    FCS.Leave;
  end;
end;

procedure THookController.MarkHookInstallPending(ThreadId: DWORD);
begin
  FCS.Enter;
  try
    var entry: THookThreadEntry;
    if not FThreads.TryGetValue(ThreadId, entry) then
      Exit;
    entry.State := hsPendingInstall;
    FThreads.AddOrSetValue(ThreadId, entry);
  finally
    FCS.Leave;
  end;
end;

procedure THookController.UpdateHotCache(ThreadId: DWORD);
begin
  FHotThreadSet.Remove(ThreadId);
  FHotThreadSet.Insert(0, ThreadId);
  while FHotThreadSet.Count > RK_HOT_THREAD_MAX do
    FHotThreadSet.Delete(FHotThreadSet.Count - 1);
end;

procedure THookController.SweepCheck;
begin
  if FIsSweepPaused then
    Exit;
  DoSweepIdleHooks;
end;

procedure THookController.DoSweepIdleHooks;
var
  pendingRemove: TList<DWORD>;
  now: UInt64;
begin
  pendingRemove := TList<DWORD>.Create;
  try
    FCS.Enter;
    try
      now := GetTickCount64;
      for var pair in FThreads do
      begin
        var threadId := pair.Key;
        var entry := pair.Value;

        // Skip hot-cached threads
        if FHotThreadSet.Contains(threadId) then
          Continue;
        // Skip recently active threads
        if (now - entry.LastActiveTick < RK_THREAD_IDLE_TTL) then
          Continue;
        // Skip threads that still have windows
        if entry.WindowSet.Count > 0 then
          Continue;
        // Skip threads with pending installs (may still succeed)
        if entry.State = hsPendingInstall then
          Continue;

        pendingRemove.Add(threadId);
      end;

      for var threadId in pendingRemove do
      begin
        var entry := FThreads[threadId];

        if entry.Is32Bit then
        begin
          // 32-bit: send uninstall command to Helper32
          if FHelperManager <> nil then
            FHelperManager.UninstallHook(threadId);
        end
        else
        begin
          // 64-bit: uninstall directly
          if entry.HookHandle <> 0 then
          begin
            UnhookWindowsHookEx(entry.HookHandle);
            entry.HookHandle := 0;
          end;
        end;

        entry.State := hsIdle;
        entry.Free;
        FThreads.Remove(threadId);
      end;
    finally
      FCS.Leave;
    end;
  finally
    pendingRemove.Free;
  end;
end;

procedure THookController.UnloadAllHooks;
begin
  FCS.Enter;
  try
    for var pair in FThreads do
    begin
      var entry := pair.Value;

      if entry.Is32Bit then
      begin
        // 32-bit: send uninstall to Helper32
        if (entry.State = hsActive) and (FHelperManager <> nil) then
          FHelperManager.UninstallHook(pair.Key);
      end
      else
      begin
        // 64-bit: uninstall directly
        if entry.HookHandle <> 0 then
        begin
          UnhookWindowsHookEx(entry.HookHandle);
          entry.HookHandle := 0;
        end;
      end;

      entry.Free;
    end;
    FThreads.Clear;
    FHotThreadSet.Clear;
  finally
    FCS.Leave;
  end;
end;

function THookController.GetDiagnosticsSnapshot: THookDiagnosticsSnapshot;
begin
  FCS.Enter;
  try
    SetLength(Result, FThreads.Count);
    var i := 0;
    for var pair in FThreads do
    begin
      Result[i].ThreadId := pair.Key;
      Result[i].RefCount := pair.Value.RefCount;
      Result[i].WindowCount := pair.Value.WindowSet.Count;
      Result[i].State := pair.Value.State;
      Result[i].LastActiveTick := pair.Value.LastActiveTick;
      Result[i].IsHotCache := FHotThreadSet.Contains(pair.Key);
      Inc(i);
    end;
  finally
    FCS.Leave;
  end;
end;

procedure THookController.ResetForTesting;
begin
  FCS.Enter;
  try
    for var pair in FThreads do
    begin
      if (not pair.Value.Is32Bit) and (pair.Value.HookHandle <> 0) then
        UnhookWindowsHookEx(pair.Value.HookHandle);
      pair.Value.Free;
    end;
    FThreads.Clear;
    FHotThreadSet.Clear;
    FIsSweepPaused := False;
  finally
    FCS.Leave;
  end;
end;

function THookController.GetThreadCount: Integer;
begin
  FCS.Enter;
  try
    Result := FThreads.Count;
  finally
    FCS.Leave;
  end;
end;

function THookController.GetActiveHookCount: Integer;
begin
  Result := 0;
  FCS.Enter;
  try
    for var pair in FThreads do
      if pair.Value.State = hsActive then
        Inc(Result);
  finally
    FCS.Leave;
  end;
end;

end.
