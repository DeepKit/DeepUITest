unit DeepRKey.WindowOps;

interface

uses
  Winapi.Windows, Winapi.MultiMon,
  System.SysUtils, System.StrUtils, System.JSON, System.IOUtils,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Clipbrd,
  DeepRKey.Types;

type
  /// <summary>Saved window state for undo/redo.</summary>
  TWindowState = record
    Hwnd: HWND;
    Rect: TRect;
    ExStyle: Longint;
    Style: Longint;
  end;

  /// <summary>Global undo/redo stack for window operations.</summary>
  TWindowUndoManager = class
  private
    FUndoStack: TList<TWindowState>;
    FRedoStack: TList<TWindowState>;
    FMaxEntries: Integer;
  public
    constructor Create(AMaxEntries: Integer = 30);
    destructor Destroy; override;
    procedure Push(const State: TWindowState);
    function  CanUndo: Boolean;
    function  CanRedo: Boolean;
    function  Undo: TWindowState;
    function  Redo: TWindowState;
    procedure Clear;
    property MaxEntries: Integer read FMaxEntries;
  end;

  /// <summary>Semi-transparent black overlay window for the Dimmer feature.</summary>
  TDimmerOverlay = class
  private
    FOverlayHwnd: HWND;
    FTargetHwnd: HWND;
  public
    class function Create(TargetHwnd: HWND; AlphaPercent: Integer): TDimmerOverlay;
    destructor Destroy; override;
    procedure UpdatePosition;
    property OverlayHwnd: HWND read FOverlayHwnd;
    property TargetHwnd: HWND read FTargetHwnd;
  end;

  TWindowCommandService = class
  private
    FAuthCookie: TGUID;
    FIsProcessingOwnOperation: Boolean;
    FDimmerOverlays: TDictionary<HWND, TDimmerOverlay>;
    FHiddenAltTabWindows: TList<HWND>;
    FForcedResizableWindows: TList<NativeUInt>;
    FOriginalExStyle: TDictionary<NativeUInt, Longint>;  // T-444: 保存原始 exstyle
    FOriginalStyle: TDictionary<NativeUInt, Longint>;    // T-444: 保存原始 style
    FOriginalAlpha: TDictionary<NativeUInt, Byte>;       // T-444: 保存原始 alpha
    FUndoManager: TWindowUndoManager;
    function ValidateWindow(hWnd: HWND): Boolean;
  public
    constructor Create(const AAuthCookie: TGUID);
    destructor Destroy; override;
    procedure SetTopMost(hWnd: HWND; Enable: Boolean);
    procedure SetTransparency(hWnd: HWND; Alpha: Byte);
    procedure MoveToMonitor(hWnd: HWND; MonitorIndex: Integer);
    procedure AlignWindow(hWnd: HWND; Align: TRKeyAlignment);
    procedure ResizeWindow(hWnd: HWND; Width, Height: Integer);
    procedure RollUp(hWnd: HWND);
    procedure SendToBottom(hWnd: HWND);
    procedure ToggleClickThrough(hWnd: HWND);
    procedure ToggleDimmer(hWnd: HWND; AlphaPercent: Integer);
    procedure TurnOffDimmer(hWnd: HWND);
    procedure ToggleHideAltTab(hWnd: HWND);
    function  SaveWindowScreenshot(hWnd: HWND; ToFile: Boolean): string;
    procedure UpdateDimmerPosition(hWnd: HWND);
    procedure ToggleResizable(hWnd: HWND);
    function  IsForcedResizable(hWnd: HWND): Boolean;
    procedure RecordWindowState(hWnd: HWND);
    procedure PerformUndo;
    procedure PerformRedo;
    procedure CleanupAll;
    function  IsDimmed(hWnd: HWND): Boolean;
    function  IsHiddenAltTab(hWnd: HWND): Boolean;
    property UndoManager: TWindowUndoManager read FUndoManager;
    property IsProcessingOwnOperation: Boolean read FIsProcessingOwnOperation
      write FIsProcessingOwnOperation;
  end;

  TWindowOps = class
  public
    class function GetWindowRect(hWnd: HWND): TRect;
    class function GetWorkArea: TRect;
    class function GetMonitorWorkArea(MonitorIndex: Integer): TRect;
    class function IsWindowArranged(hWnd: HWND): Boolean;
    class function GetMonitorCount: Integer;
    class function GetWindowInfoText(hWnd: HWND): string;
    class function SaveLayout: string;    // returns path to saved file
    class function RestoreLayout: Integer; // returns count of restored windows
  end;

implementation

type
  TMonitorEnumData = record
    TargetIndex: Integer;
    CurrentIndex: Integer;
    WorkArea: TRect;
    Found: Boolean;
  end;

function MonitorCountProc(hMonitor: HMONITOR; hdcMonitor: HDC;
  lprcMonitor: PRect; dwData: LPARAM): BOOL; stdcall;
begin
  Inc(PInteger(dwData)^);
  Result := True;
end;

function MonitorWorkAreaProc(hMonitor: HMONITOR; hdcMonitor: HDC;
  lprcMonitor: PRect; dwData: LPARAM): BOOL; stdcall;
var
  // BUG-P1 修复：使用显式指针解引用替代 absolute 映射
  data: ^TMonitorEnumData;
  mi: TMonitorInfo;
begin
  data := Pointer(dwData);
  if data.CurrentIndex = data.TargetIndex then
  begin
    mi.cbSize := SizeOf(mi);
    if GetMonitorInfo(hMonitor, @mi) then
    begin
      data.WorkArea := mi.rcWork;
      data.Found := True;
    end;
    Result := False;  // stop enumerating
  end
  else
  begin
    Inc(data.CurrentIndex);
    Result := True;   // continue
  end;
end;

{ TWindowCommandService }

constructor TWindowCommandService.Create(const AAuthCookie: TGUID);
begin
  FAuthCookie := AAuthCookie;
  FIsProcessingOwnOperation := False;
  FDimmerOverlays := TDictionary<HWND, TDimmerOverlay>.Create;
  FHiddenAltTabWindows := TList<HWND>.Create;
  FForcedResizableWindows := TList<NativeUInt>.Create;
  FOriginalExStyle := TDictionary<NativeUInt, Longint>.Create;
  FOriginalStyle := TDictionary<NativeUInt, Longint>.Create;
  FOriginalAlpha := TDictionary<NativeUInt, Byte>.Create;
  FUndoManager := TWindowUndoManager.Create(30);
end;

destructor TWindowCommandService.Destroy;
begin
  CleanupAll;
  FUndoManager.Free;
  FOriginalAlpha.Free;
  FOriginalStyle.Free;
  FOriginalExStyle.Free;
  FForcedResizableWindows.Free;
  FDimmerOverlays.Free;
  FHiddenAltTabWindows.Free;
  inherited;
end;

function TWindowCommandService.ValidateWindow(hWnd: HWND): Boolean;
begin
  Result := IsWindow(hWnd);
  if Result then
  begin
    var pid: DWORD;
    GetWindowThreadProcessId(hWnd, @pid);
    Result := pid <> 0;
  end;
end;

procedure TWindowCommandService.SetTopMost(hWnd: HWND; Enable: Boolean);
begin
  if not ValidateWindow(hWnd) then Exit;
  FIsProcessingOwnOperation := True;
  try
    if Enable then
      SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)
    else
      SetWindowPos(hWnd, HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.SetTransparency(hWnd: HWND; Alpha: Byte);
var
  exStyle: Longint;
  hKey: NativeUInt;
begin
  if not ValidateWindow(hWnd) then Exit;
  hKey := NativeUInt(hWnd);
  FIsProcessingOwnOperation := True;
  try
    exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
    if Alpha >= 255 then
    begin
      // T-444: 恢复原始 exstyle
      if FOriginalExStyle.TryGetValue(hKey, exStyle) then
      begin
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle);
        FOriginalExStyle.Remove(hKey);
      end
      else
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle and not WS_EX_LAYERED);
    end
    else
    begin
      // T-444: 保存原始 exstyle + alpha
      if not FOriginalExStyle.ContainsKey(hKey) then
        FOriginalExStyle.AddOrSetValue(hKey, exStyle);
      if not FOriginalAlpha.ContainsKey(hKey) then
      begin
        var currentAlpha: Byte;
        var colorRef: COLORREF := 0;
        var flags: DWORD := 0;
        if GetLayeredWindowAttributes(hWnd, colorRef, currentAlpha, flags) then
          FOriginalAlpha.AddOrSetValue(hKey, currentAlpha)
        else
          FOriginalAlpha.AddOrSetValue(hKey, 255);
      end;
      SetWindowLong(hWnd, GWL_EXSTYLE, exStyle or WS_EX_LAYERED);
      SetLayeredWindowAttributes(hWnd, 0, Alpha, LWA_ALPHA);
    end;
    SetWindowPos(hWnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_NOZORDER or SWP_FRAMECHANGED);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.MoveToMonitor(hWnd: HWND; MonitorIndex: Integer);
begin
  if not ValidateWindow(hWnd) then Exit;
  var workArea := TWindowOps.GetMonitorWorkArea(MonitorIndex);
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(hWnd, 0, workArea.Left, workArea.Top, 0, 0,
      SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.AlignWindow(hWnd: HWND; Align: TRKeyAlignment);
begin
  if not ValidateWindow(hWnd) then Exit;
  var wRect := TWindowOps.GetWindowRect(hWnd);
  var workArea := TWindowOps.GetWorkArea;
  var w := wRect.Width;
  var h := wRect.Height;
  var x := 0;
  var y := 0;
  case Align of
    raTopLeft:     begin x := workArea.Left; y := workArea.Top; end;
    raTopRight:    begin x := workArea.Right - w; y := workArea.Top; end;
    raBottomLeft:  begin x := workArea.Left; y := workArea.Bottom - h; end;
    raBottomRight: begin x := workArea.Right - w; y := workArea.Bottom - h; end;
    raCenter:      begin x := workArea.Left + (workArea.Width - w) div 2;
                         y := workArea.Top + (workArea.Height - h) div 2; end;
    raSnapEdge:    begin x := workArea.Left; y := workArea.Top; end;
  end;
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(hWnd, 0, x, y, 0, 0,
      SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.ResizeWindow(hWnd: HWND; Width, Height: Integer);
begin
  if not ValidateWindow(hWnd) then Exit;
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(hWnd, 0, 0, 0, Width, Height,
      SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.RollUp(hWnd: HWND);
begin
  if not ValidateWindow(hWnd) then Exit;
  var wRect := TWindowOps.GetWindowRect(hWnd);
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(hWnd, 0, wRect.Left, wRect.Top, wRect.Width,
      GetSystemMetrics(SM_CYCAPTION) + GetSystemMetrics(SM_CYFRAME) * 2,
      SWP_NOZORDER or SWP_NOACTIVATE);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.SendToBottom(hWnd: HWND);
begin
  if not ValidateWindow(hWnd) then Exit;
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(hWnd, HWND_BOTTOM, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.ToggleClickThrough(hWnd: HWND);
var
  exStyle: Longint;
  hKey: NativeUInt;
begin
  if not ValidateWindow(hWnd) then Exit;
  hKey := NativeUInt(hWnd);
  FIsProcessingOwnOperation := True;
  try
    exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
    if (exStyle and WS_EX_TRANSPARENT) <> 0 then
    begin
      // T-444: 恢复原始 exstyle，而非仅清除 WS_EX_TRANSPARENT
      if FOriginalExStyle.TryGetValue(hKey, exStyle) then
      begin
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle);
        FOriginalExStyle.Remove(hKey);
      end
      else
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle and not WS_EX_TRANSPARENT);
    end
    else
    begin
      // T-444: 保存原始 exstyle 后再修改
      if not FOriginalExStyle.ContainsKey(hKey) then
        FOriginalExStyle.AddOrSetValue(hKey, exStyle);
      SetWindowLong(hWnd, GWL_EXSTYLE,
        exStyle or WS_EX_TRANSPARENT or WS_EX_LAYERED);
      SetLayeredWindowAttributes(hWnd, 0, 1, LWA_ALPHA);
    end;
    SetWindowPos(hWnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

{ TWindowUndoManager }

constructor TWindowUndoManager.Create(AMaxEntries: Integer);
begin
  FUndoStack := TList<TWindowState>.Create;
  FRedoStack := TList<TWindowState>.Create;
  FMaxEntries := AMaxEntries;
end;

destructor TWindowUndoManager.Destroy;
begin
  FUndoStack.Free;
  FRedoStack.Free;
  inherited;
end;

procedure TWindowUndoManager.Push(const State: TWindowState);
begin
  FUndoStack.Add(State);
  while FUndoStack.Count > FMaxEntries do
    FUndoStack.Delete(0);
  // Any new operation invalidates the redo stack
  FRedoStack.Clear;
end;

function TWindowUndoManager.CanUndo: Boolean;
begin
  Result := FUndoStack.Count > 0;
end;

function TWindowUndoManager.CanRedo: Boolean;
begin
  Result := FRedoStack.Count > 0;
end;

function TWindowUndoManager.Undo: TWindowState;
begin
  if FUndoStack.Count = 0 then
    raise Exception.Create('Undo stack is empty');
  Result := FUndoStack.Last;
  FUndoStack.Delete(FUndoStack.Count - 1);
end;

function TWindowUndoManager.Redo: TWindowState;
begin
  if FRedoStack.Count = 0 then
    raise Exception.Create('Redo stack is empty');
  Result := FRedoStack.Last;
  FRedoStack.Delete(FRedoStack.Count - 1);
end;

procedure TWindowUndoManager.Clear;
begin
  FUndoStack.Clear;
  FRedoStack.Clear;
end;

{ TDimmerOverlay }

class function TDimmerOverlay.Create(TargetHwnd: HWND; AlphaPercent: Integer): TDimmerOverlay;
var
  dcMem: HDC;
  bmi: TBitmapInfo;
  buf: Pointer;
  p: PCardinal;
  i, total: Integer;
  hBmp, hOldBmp: HBITMAP;
  ptDst: TPoint;
  ptSrc: TPoint;
  sz: TSize;
  blendFunc: TBlendFunction;
  w, h: Integer;
  r: TRect;
  alpha: Byte;
const
  BGRA_BLACK = $00000000;  // RGB=0 → B=0 G=0 R=0; A filled separately
begin
  Result := inherited Create;
  Result.FTargetHwnd := TargetHwnd;

  Winapi.Windows.GetWindowRect(TargetHwnd, r);
  w := r.Width;
  h := r.Height;
  if (w <= 0) or (h <= 0) then
  begin
    Result.Free;
    Result := nil;
    Exit;
  end;

  if AlphaPercent <= 0  then alpha := 1   else
  if AlphaPercent >= 100 then alpha := 255 else
    alpha := Byte(Round(AlphaPercent * 2.55));

  // Create 32-bit top-down DIB; fill every pixel with BGRA=(0,0,0,alpha)
  dcMem := CreateCompatibleDC(0);
  ZeroMemory(@bmi, SizeOf(bmi));
  bmi.bmiHeader.biSize        := SizeOf(TBitmapInfoHeader);
  bmi.bmiHeader.biWidth       := w;
  bmi.bmiHeader.biHeight      := -h;   // top-down
  bmi.bmiHeader.biPlanes      := 1;
  bmi.bmiHeader.biBitCount    := 32;
  bmi.bmiHeader.biCompression := BI_RGB;

  total := w * h;
  GetMem(buf, total * SizeOf(Cardinal));
  try
    p := buf;
    for i := 0 to total - 1 do
    begin
      p^ := BGRA_BLACK or (Cardinal(alpha) shl 24);
      Inc(p);
    end;

    hBmp := CreateCompatibleBitmap(dcMem, w, h);
    SetDIBits(dcMem, hBmp, 0, h, buf, bmi, DIB_RGB_COLORS);
  finally
    FreeMem(buf);
  end;

  // Layered window: borderless, tool-window (no taskbar), always-on-top
  Result.FOverlayHwnd := CreateWindowEx(
    WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_TRANSPARENT or WS_EX_TOPMOST,
    'Static', '', WS_POPUP,
    0, 0, w, h, 0, 0, HInstance, nil);

  hOldBmp := SelectObject(dcMem, hBmp);

  ptDst := TPoint.Create(r.Left, r.Top);
  ptSrc := TPoint.Create(0, 0);
  sz.cx := w;
  sz.cy := h;
  blendFunc.BlendOp := AC_SRC_OVER;
  blendFunc.BlendFlags := 0;
  blendFunc.SourceConstantAlpha := 255;
  blendFunc.AlphaFormat := AC_SRC_ALPHA;

  UpdateLayeredWindow(Result.FOverlayHwnd, dcMem, @ptDst, @sz,
    dcMem, @ptSrc, 0, @blendFunc, ULW_ALPHA);

  SelectObject(dcMem, hOldBmp);
  DeleteObject(hBmp);
  DeleteDC(dcMem);

  ShowWindow(Result.FOverlayHwnd, SW_SHOWNOACTIVATE);
end;

destructor TDimmerOverlay.Destroy;
begin
  if FOverlayHwnd <> 0 then
  begin
    DestroyWindow(FOverlayHwnd);
    FOverlayHwnd := 0;
  end;
end;

procedure TDimmerOverlay.UpdatePosition;
var
  r: TRect;
begin
  if (FOverlayHwnd = 0) or (FTargetHwnd = 0) then Exit;
  if not IsWindow(FTargetHwnd) then Exit;
  Winapi.Windows.GetWindowRect(FTargetHwnd, r);
  SetWindowPos(FOverlayHwnd, 0, r.Left, r.Top, r.Width, r.Height,
    SWP_NOZORDER or SWP_NOACTIVATE);
end;

{ TWindowCommandService — Phase 6 methods }

function TWindowCommandService.IsDimmed(hWnd: HWND): Boolean;
begin
  Result := FDimmerOverlays.ContainsKey(hWnd);
end;

function TWindowCommandService.IsHiddenAltTab(hWnd: HWND): Boolean;
begin
  Result := FHiddenAltTabWindows.Contains(hWnd);
end;

procedure TWindowCommandService.ToggleDimmer(hWnd: HWND; AlphaPercent: Integer);
var
  overlay: TDimmerOverlay;
begin
  if not ValidateWindow(hWnd) then Exit;

  // If already dimmed, remove existing overlay first
  if FDimmerOverlays.TryGetValue(hWnd, overlay) then
  begin
    FDimmerOverlays.Remove(hWnd);
    overlay.Free;
  end;

  // AlphaPercent=0 means "off" — nothing to create
  if AlphaPercent <= 0 then Exit;

  FIsProcessingOwnOperation := True;
  try
    overlay := TDimmerOverlay.Create(hWnd, AlphaPercent);
    if overlay <> nil then
      FDimmerOverlays.AddOrSetValue(hWnd, overlay);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.TurnOffDimmer(hWnd: HWND);
var
  overlay: TDimmerOverlay;
begin
  if FDimmerOverlays.TryGetValue(hWnd, overlay) then
  begin
    FDimmerOverlays.Remove(hWnd);
    overlay.Free;
  end;
end;

procedure TWindowCommandService.UpdateDimmerPosition(hWnd: HWND);
var
  overlay: TDimmerOverlay;
begin
  if FDimmerOverlays.TryGetValue(hWnd, overlay) then
    overlay.UpdatePosition;
end;

procedure TWindowCommandService.ToggleHideAltTab(hWnd: HWND);
var
  exStyle: Longint;
  wasHidden: Boolean;
  hKey: NativeUInt;
begin
  if not ValidateWindow(hWnd) then Exit;
  wasHidden := FHiddenAltTabWindows.Contains(hWnd);
  hKey := NativeUInt(hWnd);

  FIsProcessingOwnOperation := True;
  try
    exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
    if wasHidden then
    begin
      // T-444: 恢复原始 exstyle，而非仅移除 WS_EX_TOOLWINDOW
      if FOriginalExStyle.TryGetValue(hKey, exStyle) then
      begin
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle);
        FOriginalExStyle.Remove(hKey);
      end
      else
        SetWindowLong(hWnd, GWL_EXSTYLE, exStyle and not WS_EX_TOOLWINDOW);
      FHiddenAltTabWindows.Remove(hWnd);
    end
    else
    begin
      // T-444: 保存原始 exstyle 后再修改
      if not FOriginalExStyle.ContainsKey(hKey) then
        FOriginalExStyle.AddOrSetValue(hKey, exStyle);
      SetWindowLong(hWnd, GWL_EXSTYLE,
        exStyle or WS_EX_TOOLWINDOW or WS_EX_APPWINDOW);
      FHiddenAltTabWindows.Add(hWnd);
    end;
    // Force the shell to refresh the frame / taskbar entry
    SetWindowPos(hWnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOACTIVATE or SWP_FRAMECHANGED);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

function TWindowCommandService.SaveWindowScreenshot(hWnd: HWND;
  ToFile: Boolean): string;
var
  wRect: TRect;
  wDC, memDC: HDC;
  bmp: TBitmap;
  dir, filePath: string;
  ts: string;
begin
  Result := '';
  if not ValidateWindow(hWnd) then Exit;

  wRect := TWindowOps.GetWindowRect(hWnd);
  if (wRect.Width <= 0) or (wRect.Height <= 0) then Exit;

  wDC := GetWindowDC(hWnd);
  if wDC = 0 then Exit;
  try
    memDC := CreateCompatibleDC(wDC);
    try
      bmp := TBitmap.Create;
      try
        bmp.Width  := wRect.Width;
        bmp.Height := wRect.Height;
        bmp.PixelFormat := pf32bit;
        BitBlt(bmp.Canvas.Handle, 0, 0, wRect.Width, wRect.Height,
          wDC, 0, 0, SRCCOPY);

        if ToFile then
        begin
          dir := TPath.GetTempPath + 'DeepRKey_screenshots';
          ForceDirectories(dir);
          // Build a filename safe for NTFS: replace ':' and ' ' from time stamp
          ts := FormatDateTime('yyyymmdd_hhnnss', Now);
          filePath := TPath.Combine(dir, 'screenshot_' + ts + '.bmp');
          bmp.SaveToFile(filePath);
          Result := filePath;
        end;

        // Always push to clipboard so the data is immediately usable
        Clipboard.Assign(bmp);
      finally
        bmp.Free;
      end;
    finally
      DeleteDC(memDC);
    end;
  finally
    ReleaseDC(hWnd, wDC);
  end;
end;

procedure TWindowCommandService.ToggleResizable(hWnd: HWND);
var
  style: Longint;
  wasForced: Boolean;
  hKey: NativeUInt;
begin
  if not ValidateWindow(hWnd) then Exit;
  wasForced := FForcedResizableWindows.Contains(NativeUInt(hWnd));
  hKey := NativeUInt(hWnd);

  FIsProcessingOwnOperation := True;
  try
    style := GetWindowLong(hWnd, GWL_STYLE);
    if wasForced then
    begin
      // T-444: 恢复原始 style，而非仅移除 WS_THICKFRAME/WS_MAXIMIZEBOX
      if FOriginalStyle.TryGetValue(hKey, style) then
      begin
        SetWindowLong(hWnd, GWL_STYLE, style);
        FOriginalStyle.Remove(hKey);
      end
      else
        SetWindowLong(hWnd, GWL_STYLE, style and not (WS_THICKFRAME or WS_MAXIMIZEBOX));
      FForcedResizableWindows.Remove(hKey);
    end
    else
    begin
      // T-444: 保存原始 style 后再修改
      if not FOriginalStyle.ContainsKey(hKey) then
        FOriginalStyle.AddOrSetValue(hKey, style);
      SetWindowLong(hWnd, GWL_STYLE, style or WS_THICKFRAME or WS_MAXIMIZEBOX);
      FForcedResizableWindows.Add(hKey);
    end;
    SetWindowPos(hWnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOACTIVATE or SWP_FRAMECHANGED);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

function TWindowCommandService.IsForcedResizable(hWnd: HWND): Boolean;
begin
  Result := FForcedResizableWindows.Contains(NativeUInt(hWnd));
end;

procedure TWindowCommandService.RecordWindowState(hWnd: HWND);
var
  State: TWindowState;
begin
  if not IsWindow(hWnd) then Exit;
  State.Hwnd := hWnd;
  Winapi.Windows.GetWindowRect(hWnd, State.Rect);
  State.ExStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
  State.Style := GetWindowLong(hWnd, GWL_STYLE);
  FUndoManager.Push(State);
end;

procedure TWindowCommandService.PerformUndo;
var
  prevState, currentState: TWindowState;
begin
  if not FUndoManager.CanUndo then Exit;

  prevState := FUndoManager.Undo;
  if not IsWindow(prevState.Hwnd) then Exit;

  // Save current state to redo stack
  currentState.Hwnd := prevState.Hwnd;
  Winapi.Windows.GetWindowRect(prevState.Hwnd, currentState.Rect);
  currentState.ExStyle := GetWindowLong(prevState.Hwnd, GWL_EXSTYLE);
  currentState.Style := GetWindowLong(prevState.Hwnd, GWL_STYLE);
  FUndoManager.FRedoStack.Add(currentState);

  // Restore previous state
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(prevState.Hwnd, 0,
      prevState.Rect.Left, prevState.Rect.Top,
      prevState.Rect.Width, prevState.Rect.Height,
      SWP_NOZORDER or SWP_NOACTIVATE);
    SetWindowLong(prevState.Hwnd, GWL_EXSTYLE, prevState.ExStyle);
    SetWindowLong(prevState.Hwnd, GWL_STYLE, prevState.Style);
    SetWindowPos(prevState.Hwnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOACTIVATE or SWP_FRAMECHANGED);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.PerformRedo;
var
  nextState, currentState: TWindowState;
begin
  if not FUndoManager.CanRedo then Exit;

  nextState := FUndoManager.Redo;
  if not IsWindow(nextState.Hwnd) then Exit;

  // Save current state to undo stack
  currentState.Hwnd := nextState.Hwnd;
  Winapi.Windows.GetWindowRect(nextState.Hwnd, currentState.Rect);
  currentState.ExStyle := GetWindowLong(nextState.Hwnd, GWL_EXSTYLE);
  currentState.Style := GetWindowLong(nextState.Hwnd, GWL_STYLE);
  FUndoManager.FUndoStack.Add(currentState);

  // Apply next state
  FIsProcessingOwnOperation := True;
  try
    SetWindowPos(nextState.Hwnd, 0,
      nextState.Rect.Left, nextState.Rect.Top,
      nextState.Rect.Width, nextState.Rect.Height,
      SWP_NOZORDER or SWP_NOACTIVATE);
    SetWindowLong(nextState.Hwnd, GWL_EXSTYLE, nextState.ExStyle);
    SetWindowLong(nextState.Hwnd, GWL_STYLE, nextState.Style);
    SetWindowPos(nextState.Hwnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOACTIVATE or SWP_FRAMECHANGED);
  finally
    FIsProcessingOwnOperation := False;
  end;
end;

procedure TWindowCommandService.CleanupAll;
var
  overlays: TArray<TDimmerOverlay>;
  overlay: TDimmerOverlay;
  h: NativeUInt;
  target: HWND;
  pair: TPair<NativeUInt, Longint>;
begin
  // Destroy all dimmer overlays
  overlays := FDimmerOverlays.Values.ToArray;
  FDimmerOverlays.Clear;
  for overlay in overlays do
    overlay.Free;

  // T-444: 恢复所有被修改过的窗口 exstyle
  for pair in FOriginalExStyle do
  begin
    target := HWND(pair.Key);
    if IsWindow(target) then
    begin
      SetWindowLong(target, GWL_EXSTYLE, pair.Value);
      SetWindowPos(target, 0, 0, 0, 0, 0,
        SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
        SWP_NOACTIVATE or SWP_FRAMECHANGED);
    end;
  end;
  FOriginalExStyle.Clear;

  // T-444: 恢复所有被修改过的窗口 style
  for pair in FOriginalStyle do
  begin
    target := HWND(pair.Key);
    if IsWindow(target) then
    begin
      SetWindowLong(target, GWL_STYLE, pair.Value);
      SetWindowPos(target, 0, 0, 0, 0, 0,
        SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
        SWP_NOACTIVATE or SWP_FRAMECHANGED);
    end;
  end;
  FOriginalStyle.Clear;

  // T-444: 恢复所有被修改过的窗口 alpha
  var alphaPair: TPair<NativeUInt, Byte>;
  for alphaPair in FOriginalAlpha do
  begin
    target := HWND(alphaPair.Key);
    if IsWindow(target) then
      SetLayeredWindowAttributes(target, 0, alphaPair.Value, LWA_ALPHA);
  end;
  FOriginalAlpha.Clear;

  FHiddenAltTabWindows.Clear;
  FForcedResizableWindows.Clear;
end;

class function TWindowOps.GetWindowRect(hWnd: HWND): TRect;
begin
  Winapi.Windows.GetWindowRect(hWnd, Result);
end;

class function TWindowOps.GetWorkArea: TRect;
begin
  SystemParametersInfo(SPI_GETWORKAREA, 0, @Result, 0);
end;

class function TWindowOps.GetMonitorWorkArea(MonitorIndex: Integer): TRect;
var
  data: TMonitorEnumData;
begin
  // Default to primary work area
  SystemParametersInfo(SPI_GETWORKAREA, 0, @Result, 0);
  if MonitorIndex < 0 then Exit;

  data.TargetIndex := MonitorIndex;
  data.CurrentIndex := 0;
  data.Found := False;
  EnumDisplayMonitors(0, nil, @MonitorWorkAreaProc, LPARAM(@data));
  if data.Found then
    Result := data.WorkArea;
end;

class function TWindowOps.IsWindowArranged(hWnd: HWND): Boolean;
begin
  Result := False;
  // v0.1 MVP: always return False — IsWindowArranged is Win11+ only
  // Phase 4: dynamic import from user32.dll
end;

class function TWindowOps.GetMonitorCount: Integer;
begin
  Result := 0;
  EnumDisplayMonitors(0, nil, @MonitorCountProc, LPARAM(@Result));
end;

class function TWindowOps.GetWindowInfoText(hWnd: HWND): string;
var
  pid, tid: DWORD;
  rect: TRect;
  className: array[0..255] of Char;
  titleText: array[0..255] of Char;
  exStyle: Longint;
begin
  tid := GetWindowThreadProcessId(hWnd, @pid);
  Winapi.Windows.GetClassName(hWnd, className, Length(className));
  GetWindowText(hWnd, titleText, Length(titleText));
  Winapi.Windows.GetWindowRect(hWnd, rect);
  exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);

  Result := Format(
    'Window: %s' + sLineBreak +
    'Class: %s' + sLineBreak +
    'HWND: $%x' + sLineBreak +
    'PID: %d  TID: %d' + sLineBreak +
    'Position: (%d, %d)  Size: %d x %d' + sLineBreak +
    'TopMost: %s' + sLineBreak +
    'Layered: %s' + sLineBreak +
    'ClickThrough: %s',
    [string(titleText), string(className), NativeUInt(hWnd),
     pid, tid,
     rect.Left, rect.Top, rect.Width, rect.Height,
     IfThen((exStyle and WS_EX_TOPMOST) <> 0, 'Yes', 'No'),
     IfThen((exStyle and WS_EX_LAYERED) <> 0, 'Yes', 'No'),
     IfThen((exStyle and WS_EX_TRANSPARENT) <> 0, 'Yes', 'No')]);
end;

type
  TLayoutSaveEnum = record
    Arr: TJSONArray;
  end;

function LayoutSaveEnumProc(hWnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  // BUG-P1 修复：使用显式指针解引用替代 absolute 映射
  Enum: ^TLayoutSaveEnum;
  ClassName, Title: array[0..255] of Char;
  Rect: TRect;
  Style, ExStyle: Longint;
  Obj: TJSONObject;
begin
  Enum := Pointer(lParam);
  // Only save visible, non-tool windows with a title or known class
  if not IsWindowVisible(hWnd) then begin Result := True; Exit; end;
  Style := GetWindowLong(hWnd, GWL_STYLE);
  if (Style and WS_CHILD) <> 0 then begin Result := True; Exit; end;

  Winapi.Windows.GetClassName(hWnd, ClassName, Length(ClassName));
  GetWindowText(hWnd, Title, Length(Title));
  if (string(Title) = '') and (string(ClassName) = '') then
  begin Result := True; Exit; end;

  Winapi.Windows.GetWindowRect(hWnd, Rect);
  ExStyle := GetWindowLong(hWnd, GWL_EXSTYLE);

  Obj := TJSONObject.Create;
  Obj.AddPair('class', string(ClassName));
  Obj.AddPair('title', string(Title));
  Obj.AddPair('left', TJSONNumber.Create(Rect.Left));
  Obj.AddPair('top', TJSONNumber.Create(Rect.Top));
  Obj.AddPair('width', TJSONNumber.Create(Rect.Right - Rect.Left));
  Obj.AddPair('height', TJSONNumber.Create(Rect.Bottom - Rect.Top));
  Obj.AddPair('topmost', TJSONNumber.Create(Ord((ExStyle and WS_EX_TOPMOST) <> 0)));
  Enum.Arr.AddElement(Obj);

  Result := True;
end;

class function TWindowOps.SaveLayout: string;
var
  Enum: TLayoutSaveEnum;
  Root: TJSONObject;
  Path: string;
begin
  Result := '';
  Enum.Arr := TJSONArray.Create;
  try
    EnumWindows(@LayoutSaveEnumProc, LPARAM(@Enum));

    Root := TJSONObject.Create;
    try
      Root.AddPair('timestamp', TJSONNumber.Create(GetTickCount64));
      Root.AddPair('monitor_count', TJSONNumber.Create(GetMonitorCount));
      Root.AddPair('windows', Enum.Arr);

      Path := TPath.GetTempPath + 'DeepRKey_layout.json';
      TFile.WriteAllText(Path, Root.ToString);
      Result := Path;
    finally
      Root.Free;
    end;
  except
    Enum.Arr.Free;
    raise;
  end;
end;

function LayoutRestoreMatchEnum(hWnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  // BUG-P1 修复：使用显式指针解引用替代 absolute 映射
  Target: ^TJSONObject;
  ClassName, Title: array[0..255] of Char;
  Cls, Ttl: string;
  Rect: TRect;
  SavedW, SavedH: Integer;
begin
  Target := Pointer(lParam);
  Winapi.Windows.GetClassName(hWnd, ClassName, Length(ClassName));
  GetWindowText(hWnd, Title, Length(Title));
  Cls := string(ClassName);
  Ttl := string(Title);

  if (Cls = Target.GetValue<string>('class')) and
     (Ttl = Target.GetValue<string>('title')) and
     IsWindowVisible(hWnd) then
  begin
    SavedW := Target.GetValue<Integer>('width');
    SavedH := Target.GetValue<Integer>('height');
    Rect.Left := Target.GetValue<Integer>('left');
    Rect.Top := Target.GetValue<Integer>('top');
    SetWindowPos(hWnd, 0, Rect.Left, Rect.Top, SavedW, SavedH,
      SWP_NOZORDER or SWP_NOACTIVATE);
  end;
  Result := True;
end;

class function TWindowOps.RestoreLayout: Integer;
var
  Path: string;
  Content: string;
  Root: TJSONObject;
  Arr: TJSONArray;
  I, Restored: Integer;
  WinObj: TJSONObject;
begin
  Result := 0;
  Path := TPath.GetTempPath + 'DeepRKey_layout.json';
  if not TFile.Exists(Path) then Exit;

  Content := TFile.ReadAllText(Path);
  Root := TJSONObject.ParseJSONValue(Content) as TJSONObject;
  if Root = nil then Exit;
  try
    if not Root.TryGetValue<TJSONArray>('windows', Arr) then Exit;
    Restored := 0;
    for I := 0 to Arr.Count - 1 do
    begin
      WinObj := Arr.Items[I] as TJSONObject;
      EnumWindows(@LayoutRestoreMatchEnum, LPARAM(WinObj));
      Inc(Restored);
    end;
    Result := Restored;
  finally
    Root.Free;
  end;
end;

end.