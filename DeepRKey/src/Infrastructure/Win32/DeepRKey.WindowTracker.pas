unit DeepRKey.WindowTracker;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  DeepRKey.Types,
  DeepRKey.HookEligibilityPolicy;

type
  TWindowEntry = record
    Hwnd: HWND;
    ThreadId: DWORD;
    ProcessId: DWORD;
    CreateTick: UInt64;
  end;

  TWindowTracker = class
  private
    FCS: TCriticalSection;
    FCandidatesByHwnd: TDictionary<NativeUInt, TWindowEntry>;
    FThreadWindows: TDictionary<DWORD, TList<NativeUInt>>;
    FEligibilityPolicy: THookEligibilityPolicy;
    function GetWindowCount: Integer;
    function GetThreadCount: Integer;
  public
    constructor Create(APolicy: THookEligibilityPolicy);
    destructor Destroy; override;
    procedure OnWindowCreated(hWnd: HWND);
    procedure OnWindowDestroyed(hWnd: HWND);
    procedure OnForegroundChanged(hWnd: HWND);
    function GetWindowEntry(hWnd: HWND; out Entry: TWindowEntry): Boolean;
    function GetWindowsForThread(ThreadId: DWORD): TArray<NativeUInt>;
    function GetAllWindows: TArray<TWindowEntry>;
    procedure ReEnumerateWindows;
    procedure RemoveThread(ThreadId: DWORD);
    property WindowCount: Integer read GetWindowCount;
    property ThreadCount: Integer read GetThreadCount;
    property EligibilityPolicy: THookEligibilityPolicy read FEligibilityPolicy;
  end;

implementation

function EnumWindowsTrackerProc(hWnd: HWND; lParam: LPARAM): BOOL; stdcall;
begin
  TWindowTracker(lParam).OnWindowCreated(hWnd);
  Result := True;
end;

{ TWindowTracker }

constructor TWindowTracker.Create(APolicy: THookEligibilityPolicy);
begin
  FCS := TCriticalSection.Create;
  FCandidatesByHwnd := TDictionary<NativeUInt, TWindowEntry>.Create(256);
  FThreadWindows := TDictionary<DWORD, TList<NativeUInt>>.Create(64);
  FEligibilityPolicy := APolicy;
end;

destructor TWindowTracker.Destroy;
begin
  for var pair in FThreadWindows do
    pair.Value.Free;
  FThreadWindows.Free;
  FCandidatesByHwnd.Free;
  FCS.Free;
  inherited;
end;

function TWindowTracker.GetWindowCount: Integer;
begin
  FCS.Enter;
  try
    Result := FCandidatesByHwnd.Count;
  finally
    FCS.Leave;
  end;
end;

function TWindowTracker.GetAllWindows: TArray<TWindowEntry>;
begin
  FCS.Enter;
  try
    SetLength(Result, FCandidatesByHwnd.Count);
    var i := 0;
    for var pair in FCandidatesByHwnd do
    begin
      Result[i] := pair.Value;
      Inc(i);
    end;
  finally
    FCS.Leave;
  end;
end;

function TWindowTracker.GetThreadCount: Integer;
begin
  FCS.Enter;
  try
    Result := FThreadWindows.Count;
  finally
    FCS.Leave;
  end;
end;

procedure TWindowTracker.OnWindowCreated(hWnd: HWND);
begin
  if not FEligibilityPolicy.ShouldHookWindow(hWnd) then
    Exit;

  var threadId, processId: DWORD;
  threadId := GetWindowThreadProcessId(hWnd, @processId);
  if (threadId = 0) or (processId = 0) then
    Exit;

  var entry: TWindowEntry;
  entry.Hwnd := hWnd;
  entry.ThreadId := threadId;
  entry.ProcessId := processId;
  entry.CreateTick := GetTickCount64;

  FCS.Enter;
  try
    FCandidatesByHwnd.AddOrSetValue(NativeUInt(hWnd), entry);

    var list: TList<NativeUInt>;
    if not FThreadWindows.TryGetValue(threadId, list) then
    begin
      list := TList<NativeUInt>.Create;
      FThreadWindows.Add(threadId, list);
    end;
    if not list.Contains(NativeUInt(hWnd)) then
      list.Add(NativeUInt(hWnd));
  finally
    FCS.Leave;
  end;
end;

procedure TWindowTracker.OnWindowDestroyed(hWnd: HWND);
begin
  FCS.Enter;
  try
    var entry: TWindowEntry;
    if not FCandidatesByHwnd.TryGetValue(NativeUInt(hWnd), entry) then
      Exit;
    FCandidatesByHwnd.Remove(NativeUInt(hWnd));

    if FThreadWindows.ContainsKey(entry.ThreadId) then
    begin
      var list := FThreadWindows[entry.ThreadId];
      list.Remove(NativeUInt(hWnd));
      if list.Count = 0 then
      begin
        list.Free;
        FThreadWindows.Remove(entry.ThreadId);
      end;
    end;
  finally
    FCS.Leave;
  end;
end;

procedure TWindowTracker.OnForegroundChanged(hWnd: HWND);
begin
  var eligibility := FEligibilityPolicy.IsHookEligible(hWnd);
  if not eligibility.IsEligible then
    Exit;
  OnWindowCreated(hWnd);
end;

function TWindowTracker.GetWindowEntry(hWnd: HWND; out Entry: TWindowEntry): Boolean;
begin
  FCS.Enter;
  try
    Result := FCandidatesByHwnd.TryGetValue(NativeUInt(hWnd), Entry);
  finally
    FCS.Leave;
  end;
end;

function TWindowTracker.GetWindowsForThread(ThreadId: DWORD): TArray<NativeUInt>;
begin
  SetLength(Result, 0);
  FCS.Enter;
  try
    var list: TList<NativeUInt>;
    if FThreadWindows.TryGetValue(ThreadId, list) then
      Result := list.ToArray;
  finally
    FCS.Leave;
  end;
end;

procedure TWindowTracker.ReEnumerateWindows;
begin
  EnumWindows(@EnumWindowsTrackerProc, LPARAM(Self));
end;

procedure TWindowTracker.RemoveThread(ThreadId: DWORD);
begin
  FCS.Enter;
  try
    var list: TList<NativeUInt>;
    if not FThreadWindows.TryGetValue(ThreadId, list) then
      Exit;
    for var hwnd in list do
      FCandidatesByHwnd.Remove(hwnd);
    list.Free;
    FThreadWindows.Remove(ThreadId);
  finally
    FCS.Leave;
  end;
end;

end.