unit DeepRKey.LayoutManager;

interface

uses
  Winapi.Windows, Winapi.MultiMon, Winapi.PsAPI,
  System.SysUtils, System.StrUtils, System.JSON, System.IOUtils,
  System.Generics.Collections,
  DeepRKey.Types;

type
  TLayoutWindowEntry = record
    Hwnd: UInt64;
    ClassName: string;
    Title: string;
    ProcessName: string;
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Height: Integer;
    MonitorIndex: Integer;
    IsTopMost: Boolean;
    DpiAwareness: TRKeyDpiAwareness;
    procedure FromJSON(const Obj: TJSONObject);
    function ToJSON: TJSONObject;
    function IdentityHash: string;
  end;

  TLayoutMonitorInfo = record
    Index: Integer;
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Height: Integer;
    WorkLeft: Integer;
    WorkTop: Integer;
    WorkWidth: Integer;
    WorkHeight: Integer;
    DpiX: Integer;
    DpiY: Integer;
    IsPrimary: Boolean;
    Name: string;
    procedure FromJSON(const Obj: TJSONObject);
    function ToJSON: TJSONObject;
  end;

  TLayoutSnapshot = class
  private
    FSlotName: string;
    FTimestamp: TDateTime;
    FMonitorCount: Integer;
    FMonitors: TArray<TLayoutMonitorInfo>;
    FWindows: TArray<TLayoutWindowEntry>;
  public
    constructor Create(const ASlotName: string);
    procedure Save(const AWindows: TArray<TLayoutWindowEntry>;
      const AMonitors: TArray<TLayoutMonitorInfo>);
    function ToJSON: TJSONObject;
    procedure FromJSON(const Obj: TJSONObject);
    function HasMonitorLayoutChanged(
      const CurrentMonitors: TArray<TLayoutMonitorInfo>): Boolean;
    function FindWindow(const IdentityHash: string;
      out Entry: TLayoutWindowEntry): Boolean;
    property SlotName: string read FSlotName;
    property Timestamp: TDateTime read FTimestamp;
    property MonitorCount: Integer read FMonitorCount;
    property Monitors: TArray<TLayoutMonitorInfo> read FMonitors;
    property Windows: TArray<TLayoutWindowEntry> read FWindows;
  end;

  TLayoutManager = class
  private
    FSlots: TObjectList<TLayoutSnapshot>;
    FActiveSlotIndex: Integer;
    FDataDir: string;
    const MAX_SLOTS = 5;
    function GetSlotFileName(Index: Integer): string;
    procedure LoadAllSlots;
    procedure SaveSlot(Index: Integer);
    procedure SaveAllSlots;
    function GetActiveSlot: TLayoutSnapshot;
    function GetSlot(Index: Integer): TLayoutSnapshot;
    function GetSlotCount: Integer;
  public
    constructor Create(const ADataDir: string);
    destructor Destroy; override;
    function Capture: TLayoutSnapshot;
    function Restore: Integer;
    procedure SetActiveSlot(Index: Integer);
    procedure DeleteSlot(Index: Integer);
    function GetSlotNames: TArray<string>;
    property ActiveSlot: TLayoutSnapshot read GetActiveSlot;
    property Slots[Index: Integer]: TLayoutSnapshot read GetSlot;
    property SlotCount: Integer read GetSlotCount;
    property ActiveSlotIndex: Integer read FActiveSlotIndex;
  end;

implementation

{ TLayoutWindowEntry }

function TLayoutWindowEntry.IdentityHash: string;
begin
  var combined := ProcessName + '|' + ClassName;
  var hash: UInt64 := 14695981039346656037;
  for var i := 1 to Length(combined) do
  begin
    hash := hash xor UInt64(Ord(combined[i]));
    hash := hash * UInt64(1099511628211);
  end;
  Result := IntToHex(Int64(hash), 16);
end;

procedure TLayoutWindowEntry.FromJSON(const Obj: TJSONObject);
begin
  Hwnd := Obj.GetValue<UInt64>('hwnd', 0);
  ClassName := Obj.GetValue<string>('class', '');
  Title := Obj.GetValue<string>('title', '');
  ProcessName := Obj.GetValue<string>('process', '');
  Left := Obj.GetValue<Integer>('left', 0);
  Top := Obj.GetValue<Integer>('top', 0);
  Width := Obj.GetValue<Integer>('width', 0);
  Height := Obj.GetValue<Integer>('height', 0);
  MonitorIndex := Obj.GetValue<Integer>('monitor', 0);
  IsTopMost := Obj.GetValue<Boolean>('topmost', False);
  DpiAwareness := TRKeyDpiAwareness(Obj.GetValue<Integer>('dpi_aware', 0));
end;

function TLayoutWindowEntry.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('hwnd', TJSONNumber.Create(Hwnd));
  Result.AddPair('class', ClassName);
  Result.AddPair('title', Title);
  Result.AddPair('process', ProcessName);
  Result.AddPair('left', TJSONNumber.Create(Left));
  Result.AddPair('top', TJSONNumber.Create(Top));
  Result.AddPair('width', TJSONNumber.Create(Width));
  Result.AddPair('height', TJSONNumber.Create(Height));
  Result.AddPair('monitor', TJSONNumber.Create(MonitorIndex));
  Result.AddPair('topmost', TJSONNumber.Create(Ord(IsTopMost)));
  Result.AddPair('dpi_aware', TJSONNumber.Create(Ord(DpiAwareness)));
end;

{ TLayoutMonitorInfo }

procedure TLayoutMonitorInfo.FromJSON(const Obj: TJSONObject);
begin
  Index := Obj.GetValue<Integer>('index', 0);
  Left := Obj.GetValue<Integer>('left', 0);
  Top := Obj.GetValue<Integer>('top', 0);
  Width := Obj.GetValue<Integer>('width', 0);
  Height := Obj.GetValue<Integer>('height', 0);
  WorkLeft := Obj.GetValue<Integer>('work_left', 0);
  WorkTop := Obj.GetValue<Integer>('work_top', 0);
  WorkWidth := Obj.GetValue<Integer>('work_width', 0);
  WorkHeight := Obj.GetValue<Integer>('work_height', 0);
  DpiX := Obj.GetValue<Integer>('dpi_x', 96);
  DpiY := Obj.GetValue<Integer>('dpi_y', 96);
  IsPrimary := Obj.GetValue<Boolean>('primary', False);
  Name := Obj.GetValue<string>('name', '');
end;

function TLayoutMonitorInfo.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(Index));
  Result.AddPair('left', TJSONNumber.Create(Left));
  Result.AddPair('top', TJSONNumber.Create(Top));
  Result.AddPair('width', TJSONNumber.Create(Width));
  Result.AddPair('height', TJSONNumber.Create(Height));
  Result.AddPair('work_left', TJSONNumber.Create(WorkLeft));
  Result.AddPair('work_top', TJSONNumber.Create(WorkTop));
  Result.AddPair('work_width', TJSONNumber.Create(WorkWidth));
  Result.AddPair('work_height', TJSONNumber.Create(WorkHeight));
  Result.AddPair('dpi_x', TJSONNumber.Create(DpiX));
  Result.AddPair('dpi_y', TJSONNumber.Create(DpiY));
  Result.AddPair('primary', TJSONNumber.Create(Ord(IsPrimary)));
  Result.AddPair('name', Name);
end;

{ TLayoutSnapshot }

constructor TLayoutSnapshot.Create(const ASlotName: string);
begin
  FSlotName := ASlotName;
  FTimestamp := 0;
  FMonitorCount := 0;
  FMonitors := [];
  FWindows := [];
end;

procedure TLayoutSnapshot.Save(const AWindows: TArray<TLayoutWindowEntry>;
  const AMonitors: TArray<TLayoutMonitorInfo>);
begin
  FWindows := AWindows;
  FMonitors := AMonitors;
  FMonitorCount := Length(AMonitors);
  FTimestamp := Now;
end;

function TLayoutSnapshot.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('slot_name', FSlotName);
  Result.AddPair('timestamp', FormatDateTime('yyyy-mm-dd hh:nn:ss', FTimestamp));
  Result.AddPair('monitor_count', TJSONNumber.Create(FMonitorCount));

  var monArr := TJSONArray.Create;
  for var m in FMonitors do
    monArr.AddElement(m.ToJSON);
  Result.AddPair('monitors', monArr);

  var winArr := TJSONArray.Create;
  for var w in FWindows do
    winArr.AddElement(w.ToJSON);
  Result.AddPair('windows', winArr);
end;

procedure TLayoutSnapshot.FromJSON(const Obj: TJSONObject);
begin
  FSlotName := Obj.GetValue<string>('slot_name', '');
  var ts := Obj.GetValue<string>('timestamp', '');
  if ts <> '' then
    FTimestamp := StrToDateTimeDef(ts, 0, TFormatSettings.Invariant);

  FMonitorCount := Obj.GetValue<Integer>('monitor_count', 0);

  var monArr: TJSONArray;
  if Obj.TryGetValue<TJSONArray>('monitors', monArr) then
  begin
    SetLength(FMonitors, monArr.Count);
    for var i := 0 to monArr.Count - 1 do
      FMonitors[i].FromJSON(monArr.Items[i] as TJSONObject);
  end;

  var winArr: TJSONArray;
  if Obj.TryGetValue<TJSONArray>('windows', winArr) then
  begin
    SetLength(FWindows, winArr.Count);
    for var i := 0 to winArr.Count - 1 do
      FWindows[i].FromJSON(winArr.Items[i] as TJSONObject);
  end;
end;

function TLayoutSnapshot.HasMonitorLayoutChanged(
  const CurrentMonitors: TArray<TLayoutMonitorInfo>): Boolean;
begin
  if Length(CurrentMonitors) <> Length(FMonitors) then
    Exit(True);

  for var i := 0 to High(FMonitors) do
  begin
    if (FMonitors[i].Width <> CurrentMonitors[i].Width) or
       (FMonitors[i].Height <> CurrentMonitors[i].Height) or
       (FMonitors[i].DpiX <> CurrentMonitors[i].DpiX) then
      Exit(True);
  end;
  Result := False;
end;

function TLayoutSnapshot.FindWindow(const IdentityHash: string;
  out Entry: TLayoutWindowEntry): Boolean;
begin
  for var w in FWindows do
    if w.IdentityHash = IdentityHash then
    begin
      Entry := w;
      Exit(True);
    end;
  FillChar(Entry, SizeOf(Entry), 0);
  Result := False;
end;

{ TLayoutManager }

constructor TLayoutManager.Create(const ADataDir: string);
begin
  FDataDir := ADataDir;
  FSlots := TObjectList<TLayoutSnapshot>.Create(True);
  FActiveSlotIndex := 0;

  for var i := 0 to MAX_SLOTS - 1 do
    FSlots.Add(TLayoutSnapshot.Create(Format('Slot %d', [i + 1])));

  LoadAllSlots;
end;

destructor TLayoutManager.Destroy;
begin
  SaveAllSlots;
  FSlots.Free;
  inherited;
end;

function TLayoutManager.GetSlotFileName(Index: Integer): string;
begin
  Result := TPath.Combine(FDataDir, Format('layout_slot_%d.json', [Index]));
end;

procedure TLayoutManager.LoadAllSlots;
begin
  for var i := 0 to MAX_SLOTS - 1 do
  begin
    var fileName := GetSlotFileName(i);
    if TFile.Exists(fileName) then
    begin
      try
        var content := TFile.ReadAllText(fileName);
        var root := TJSONObject.ParseJSONValue(content) as TJSONObject;
        if root <> nil then
        try
          FSlots[i].FromJSON(root);
        finally
          root.Free;
        end;
      except
      end;
    end;
  end;
end;

procedure TLayoutManager.SaveSlot(Index: Integer);
begin
  var snapshot := FSlots[Index];
  if snapshot.Timestamp <= 0 then Exit;

  var root := snapshot.ToJSON;
  try
    var fileName := GetSlotFileName(Index);
    TFile.WriteAllText(fileName, root.ToString);
  finally
    root.Free;
  end;
end;

procedure TLayoutManager.SaveAllSlots;
begin
  for var i := 0 to MAX_SLOTS - 1 do
    SaveSlot(i);
end;

{ Window enumeration state }

type
  TLayoutCaptureState = record
    Windows: TList<TLayoutWindowEntry>;
    Monitors: TList<TLayoutMonitorInfo>;
    CurrentMonitorIdx: Integer;
  end;

  TLayoutRestoreCtx = record
    Snapshot: TLayoutSnapshot;
    CurrentMonitors: TArray<TLayoutMonitorInfo>;
    Count: Integer;
  end;
  PLayoutRestoreCtx = ^TLayoutRestoreCtx;

function MonitorEnumProc(hMonitor: HMONITOR; hdc: HDC;
  lprc: PRect; dwData: LPARAM): BOOL; stdcall;
var
  // BUG-P1 修复：使用显式指针解引用替代 absolute 映射
  State: ^TLayoutCaptureState;
  mi: TMonitorInfoEx;
  info: TLayoutMonitorInfo;
begin
  State := Pointer(dwData);
  FillChar(mi, SizeOf(mi), 0);
  mi.cbSize := SizeOf(mi);
  if not GetMonitorInfo(hMonitor, @mi) then
  begin
    Result := True;
    Exit;
  end;

  info.Index := State.CurrentMonitorIdx;
  info.Left := mi.rcMonitor.Left;
  info.Top := mi.rcMonitor.Top;
  info.Width := mi.rcMonitor.Right - mi.rcMonitor.Left;
  info.Height := mi.rcMonitor.Bottom - mi.rcMonitor.Top;
  info.WorkLeft := mi.rcWork.Left;
  info.WorkTop := mi.rcWork.Top;
  info.WorkWidth := mi.rcWork.Right - mi.rcWork.Left;
  info.WorkHeight := mi.rcWork.Bottom - mi.rcWork.Top;
  info.IsPrimary := (mi.dwFlags and MONITORINFOF_PRIMARY) <> 0;
  info.Name := string(mi.szDevice);

  var dpiX, dpiY: UINT;
  var dc := CreateDC('DISPLAY', PChar(info.Name), nil, nil);
  if dc <> 0 then
  begin
    dpiX := GetDeviceCaps(dc, LOGPIXELSX);
    dpiY := GetDeviceCaps(dc, LOGPIXELSY);
    DeleteDC(dc);
  end
  else
  begin
    dpiX := 96;
    dpiY := 96;
  end;
  info.DpiX := Integer(dpiX);
  info.DpiY := Integer(dpiY);

  State.Monitors.Add(info);
  Inc(State.CurrentMonitorIdx);
  Result := True;
end;

function WindowCaptureEnumProc(hWnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  // BUG-P1 修复：使用显式指针解引用替代 absolute 映射
  State: ^TLayoutCaptureState;
  Entry: TLayoutWindowEntry;
  ClassName: array[0..255] of Char;
  Title: array[0..255] of Char;
  Rect: TRect;
  Style: Longint;
  ExStyle: Longint;
  Monitor: HMONITOR;
  MonInfo: TMonitorInfo;
  Pid: DWORD;
  hProc: THandle;
  ProcName: array[0..MAX_PATH] of Char;
begin
  State := Pointer(lParam);
  if not IsWindowVisible(hWnd) then
  begin Result := True; Exit; end;

  Style := GetWindowLong(hWnd, GWL_STYLE);
  if (Style and WS_CHILD) <> 0 then
  begin Result := True; Exit; end;

  ExStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
  if (ExStyle and WS_EX_TOOLWINDOW) <> 0 then
  begin Result := True; Exit; end;

  Winapi.Windows.GetClassName(hWnd, ClassName, Length(ClassName));
  GetWindowText(hWnd, Title, Length(Title));

  var cls := string(ClassName);
  var ttl := string(Title);
  if (cls = '') and (ttl = '') then
  begin Result := True; Exit; end;
  if cls = 'DeepRKeyTitlebarBtn' then
  begin Result := True; Exit; end;

  Winapi.Windows.GetWindowRect(hWnd, Rect);

  Monitor := MonitorFromRect(@Rect, MONITOR_DEFAULTTONEAREST);
  FillChar(MonInfo, SizeOf(MonInfo), 0);
  MonInfo.cbSize := SizeOf(MonInfo);
  GetMonitorInfo(Monitor, @MonInfo);

  var monIdx := 0;
  for var i := 0 to State.Monitors.Count - 1 do
    if (State.Monitors[i].Left = MonInfo.rcMonitor.Left) and
       (State.Monitors[i].Top = MonInfo.rcMonitor.Top) then
    begin
      monIdx := i;
      Break;
    end;

  GetWindowThreadProcessId(hWnd, @Pid);
  ProcName[0] := #0;
  if Pid <> 0 then
  begin
    hProc := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, Pid);
    if hProc <> 0 then
    begin
      var len: DWORD := MAX_PATH;
      if GetModuleFileNameEx(hProc, 0, ProcName, len) = 0 then
        ProcName[0] := #0;
      CloseHandle(hProc);
    end;
  end;

  Entry.Hwnd := UInt64(hWnd);
  Entry.ClassName := cls;
  Entry.Title := ttl;
  Entry.ProcessName := ExtractFileName(string(ProcName));
  Entry.Left := Rect.Left;
  Entry.Top := Rect.Top;
  Entry.Width := Rect.Right - Rect.Left;
  Entry.Height := Rect.Bottom - Rect.Top;
  Entry.MonitorIndex := monIdx;
  Entry.IsTopMost := (ExStyle and WS_EX_TOPMOST) <> 0;
  Entry.DpiAwareness := rdaUnknown;

  State.Windows.Add(Entry);
  Result := True;
end;

function RestoreLayoutEnumProc(hWnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  ctx: PLayoutRestoreCtx;
  Snapshot: TLayoutSnapshot;
  Entry: TLayoutWindowEntry;
  ClassName: array[0..255] of Char;
  Style: Longint;
  Pid: DWORD;
  hProc: THandle;
  ProcName: array[0..MAX_PATH] of Char;
  ProcNameStr: string;
  Cls: string;
  IdentityHash: string;
  MonInfo: TLayoutMonitorInfo;
  TargetLeft, TargetTop, TargetW, TargetH: Integer;
begin
  Result := True;
  ctx := PLayoutRestoreCtx(lParam);
  if ctx = nil then Exit;
  Snapshot := ctx.Snapshot;
  if Snapshot = nil then Exit;
  if Snapshot.Timestamp <= 0 then Exit;

  Style := GetWindowLong(hWnd, GWL_STYLE);
  if (Style and WS_CHILD) <> 0 then Exit;
  if not IsWindowVisible(hWnd) then Exit;

  Winapi.Windows.GetClassName(hWnd, ClassName, Length(ClassName));
  Cls := string(ClassName);
  if Cls = 'DeepRKeyTitlebarBtn' then Exit;

  GetWindowThreadProcessId(hWnd, @Pid);
  ProcNameStr := '';
  if Pid <> 0 then
  begin
    hProc := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, Pid);
    if hProc <> 0 then
    begin
      var len: DWORD := MAX_PATH;
      if GetModuleFileNameEx(hProc, 0, ProcName, len) > 0 then
        ProcNameStr := ExtractFileName(string(ProcName));
      CloseHandle(hProc);
    end;
  end;

  var tempEntry: TLayoutWindowEntry;
  tempEntry.ClassName := Cls;
  tempEntry.ProcessName := ProcNameStr;
  IdentityHash := tempEntry.IdentityHash;

  if not Snapshot.FindWindow(IdentityHash, Entry) then Exit;

  TargetLeft := Entry.Left;
  TargetTop := Entry.Top;
  TargetW := Entry.Width;
  TargetH := Entry.Height;

  if Snapshot.HasMonitorLayoutChanged(ctx.CurrentMonitors) then
  begin
    if (Entry.MonitorIndex >= 0) and
       (Entry.MonitorIndex < Length(Snapshot.Monitors)) then
    begin
      MonInfo := Snapshot.Monitors[Entry.MonitorIndex];
      var found := False;
      for var i := 0 to High(ctx.CurrentMonitors) do
      begin
        var curMon := ctx.CurrentMonitors[i];
        if (curMon.Width = MonInfo.Width) and
           (curMon.Height = MonInfo.Height) then
        begin
          TargetLeft := curMon.Left + (Entry.Left - MonInfo.Left);
          TargetTop := curMon.Top + (Entry.Top - MonInfo.Top);
          found := True;
          Break;
        end;
      end;
      if not found then
      begin
        var primaryMon := ctx.CurrentMonitors[0];
        TargetLeft := primaryMon.WorkLeft + 50;
        TargetTop := primaryMon.WorkTop + 50;
        if TargetW > primaryMon.WorkWidth - 100 then
          TargetW := primaryMon.WorkWidth - 100;
        if TargetH > primaryMon.WorkHeight - 100 then
          TargetH := primaryMon.WorkHeight - 100;
      end;
    end;
  end;

  SetWindowPos(hWnd, 0, TargetLeft, TargetTop, TargetW, TargetH,
    SWP_NOZORDER or SWP_NOACTIVATE);

  if Entry.IsTopMost then
    SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);

  Inc(ctx.Count);
end;

function TLayoutManager.Capture: TLayoutSnapshot;
var
  State: TLayoutCaptureState;
begin
  State.Windows := TList<TLayoutWindowEntry>.Create;
  State.Monitors := TList<TLayoutMonitorInfo>.Create;
  State.CurrentMonitorIdx := 0;
  try
    EnumDisplayMonitors(0, nil, @MonitorEnumProc, LPARAM(@State));
    EnumWindows(@WindowCaptureEnumProc, LPARAM(@State));

    var snapshot := FSlots[FActiveSlotIndex];
    snapshot.Save(State.Windows.ToArray, State.Monitors.ToArray);
    SaveSlot(FActiveSlotIndex);
    Result := snapshot;
  finally
    State.Windows.Free;
    State.Monitors.Free;
  end;
end;

function TLayoutManager.Restore: Integer;
begin
  Result := 0;
  var snapshot := FSlots[FActiveSlotIndex];
  if snapshot.Timestamp <= 0 then Exit;

  var currentMonitors: TList<TLayoutMonitorInfo> := TList<TLayoutMonitorInfo>.Create;
  var currentWindows: TList<TLayoutWindowEntry> := TList<TLayoutWindowEntry>.Create;
  try
    var capState: TLayoutCaptureState;
    capState.Windows := currentWindows;
    capState.Monitors := currentMonitors;
    capState.CurrentMonitorIdx := 0;
    EnumDisplayMonitors(0, nil, @MonitorEnumProc, LPARAM(@capState));

    var ctx: TLayoutRestoreCtx;
    ctx.Snapshot := snapshot;
    ctx.CurrentMonitors := currentMonitors.ToArray;
    ctx.Count := 0;

    EnumWindows(@RestoreLayoutEnumProc, LPARAM(@ctx));
    Result := ctx.Count;
  finally
    currentMonitors.Free;
    currentWindows.Free;
  end;
end;

function TLayoutManager.GetActiveSlot: TLayoutSnapshot;
begin
  Result := FSlots[FActiveSlotIndex];
end;

function TLayoutManager.GetSlot(Index: Integer): TLayoutSnapshot;
begin
  if (Index >= 0) and (Index < FSlots.Count) then
    Result := FSlots[Index]
  else
    Result := nil;
end;

function TLayoutManager.GetSlotCount: Integer;
begin
  Result := FSlots.Count;
end;

procedure TLayoutManager.SetActiveSlot(Index: Integer);
begin
  if (Index >= 0) and (Index < MAX_SLOTS) then
    FActiveSlotIndex := Index;
end;

procedure TLayoutManager.DeleteSlot(Index: Integer);
begin
  if (Index >= 0) and (Index < FSlots.Count) then
  begin
    FSlots[Index] := TLayoutSnapshot.Create(Format('Slot %d', [Index + 1]));
    var fileName := GetSlotFileName(Index);
    if TFile.Exists(fileName) then
      TFile.Delete(fileName);
  end;
end;

function TLayoutManager.GetSlotNames: TArray<string>;
begin
  SetLength(Result, FSlots.Count);
  for var i := 0 to FSlots.Count - 1 do
  begin
    var snap := FSlots[i];
    if snap.Timestamp > 0 then
      Result[i] := Format('%s [%s]',
        [snap.SlotName, FormatDateTime('hh:nn', snap.Timestamp)])
    else
      Result[i] := Format('%s (empty)', [snap.SlotName]);
  end;
end;

end.