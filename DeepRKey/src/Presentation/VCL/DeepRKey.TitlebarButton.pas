unit DeepRKey.TitlebarButton;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.UITypes, System.Types,
  Vcl.Graphics, Vcl.Themes,
  DeepRKey.Types,
  DeepRKey.MenuModel;

type
  /// <summary>
  /// Small overlay button floating on the active window's title bar.
  /// Clicking it shows the DeepRKey fallback popup menu.
  /// </summary>
  TTitlebarButton = class
  private
    FButtonWnd: HWND;
    FOldWndProc: LONG_PTR;
    FTargetHwnd: HWND;
    FVisible: Boolean;
    FEnabled: Boolean;
    FOnShowMenu: TProc<HWND>;
    procedure CreateButtonWindow;
    procedure DestroyButtonWindow;
    procedure UpdatePosition;
    procedure RenderToLayered;
    procedure SetTargetHwnd(hWnd: HWND);
    procedure HookWndProc;
    procedure UnhookWndProc;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure SetTarget(hWnd: HWND);
    procedure SetMenuCallback(ACallback: TProc<HWND>);
    property Enabled: Boolean read FEnabled;
    property TargetHwnd: HWND read FTargetHwnd;
  end;

implementation

const
  BTN_SIZE = 18;
  BTN_MARGIN_RIGHT = 6;
  BTN_MARGIN_TOP = 4;
  BTN_TIMER_TRACK = 1;
  BTN_TIMER_INTERVAL = 100;

type
  PButtonData = ^TButtonData;
  TButtonData = record
    Self: TTitlebarButton;
  end;

function ButtonWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  pData: PButtonData;
begin
  pData := PButtonData(GetWindowLongPtr(hWnd, 0));
  case Msg of
    WM_LBUTTONDOWN:
    begin
      if (pData <> nil) and (pData^.Self <> nil) and
         Assigned(pData^.Self.FOnShowMenu) and (pData^.Self.FTargetHwnd <> 0) then
        pData^.Self.FOnShowMenu(pData^.Self.FTargetHwnd);
      Result := 0;
    end;
    WM_TIMER:
    begin
      if wParam = BTN_TIMER_TRACK then
      begin
        if (pData <> nil) and (pData^.Self <> nil) then
          pData^.Self.UpdatePosition;
      end;
      Result := 0;
    end;
    WM_NCHITTEST:
    begin
      Result := HTCLIENT;
    end;
  else
    Result := DefWindowProc(hWnd, Msg, wParam, lParam);
  end;
end;

{ TTitlebarButton }

constructor TTitlebarButton.Create;
begin
  inherited Create;
  FButtonWnd := 0;
  FOldWndProc := 0;
  FTargetHwnd := 0;
  FVisible := False;
  FEnabled := False;
end;

destructor TTitlebarButton.Destroy;
begin
  Stop;
  inherited;
end;

procedure TTitlebarButton.CreateButtonWindow;
var
  wc: TWNDClassEx;
  pData: PButtonData;
begin
  if FButtonWnd <> 0 then Exit;

  // Register window class with cbWndExtra for pointer storage
  if not GetClassInfoEx(HInstance, 'DeepRKeyTitlebarBtn', wc) then
  begin
    FillChar(wc, SizeOf(wc), 0);
    wc.cbSize := SizeOf(wc);
    wc.lpfnWndProc := @DefWindowProc;  // we'll subclass after creation
    wc.hInstance := HInstance;
    wc.hCursor := LoadCursor(0, IDC_HAND);
    wc.cbWndExtra := SizeOf(Pointer);
    wc.lpszClassName := 'DeepRKeyTitlebarBtn';
    RegisterClassEx(wc);
  end;

  FButtonWnd := CreateWindowEx(
    WS_EX_LAYERED or WS_EX_TOPMOST or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE,
    'DeepRKeyTitlebarBtn',
    '',
    WS_POPUP,
    -100, -100, BTN_SIZE, BTN_SIZE,  // offscreen initially
    0, 0, HInstance, nil);

  if FButtonWnd = 0 then Exit;

  // Store our pointer in the extra window bytes
  pData := AllocMem(SizeOf(TButtonData));
  pData^.Self := Self;
  SetWindowLongPtr(FButtonWnd, 0, LPARAM(pData));

  // Subclass with our window procedure
  HookWndProc;

  // Set up layered window with per-pixel alpha
  RenderToLayered;
end;

procedure TTitlebarButton.DestroyButtonWindow;
var
  pData: PButtonData;
begin
  if FButtonWnd = 0 then Exit;
  UnhookWndProc;
  pData := PButtonData(GetWindowLongPtr(FButtonWnd, 0));
  if pData <> nil then
  begin
    pData^.Self := nil;
    FreeMem(pData);
    SetWindowLongPtr(FButtonWnd, 0, 0);
  end;
  DestroyWindow(FButtonWnd);
  FButtonWnd := 0;
end;

procedure TTitlebarButton.HookWndProc;
begin
  if FButtonWnd = 0 then Exit;
  FOldWndProc := SetWindowLongPtr(FButtonWnd, GWLP_WNDPROC, LONG_PTR(@ButtonWndProc));
end;

procedure TTitlebarButton.UnhookWndProc;
begin
  if (FButtonWnd <> 0) and (FOldWndProc <> 0) then
  begin
    SetWindowLongPtr(FButtonWnd, GWLP_WNDPROC, FOldWndProc);
    FOldWndProc := 0;
  end;
end;

procedure TTitlebarButton.RenderToLayered;
var
  screenDC, memDC: HDC;
  bmp: HBITMAP;
  bits: PRGBQuad;
  bmi: TBitmapInfo;
  x, y: Integer;
  pixel: PRGBQuad;
  ptDst: TPoint;
  sz: TSize;
  bf: TBlendFunction;
  isDarkMode: Boolean;
begin
  if FButtonWnd = 0 then Exit;

  // T-304: Detect dark theme for color adjustment
  isDarkMode := (TStyleManager.ActiveStyle <> nil) and
    (Pos('Dark', TStyleManager.ActiveStyle.Name) > 0) or
    (Pos('Carbon', TStyleManager.ActiveStyle.Name) > 0) or
    (Pos('Obsidian', TStyleManager.ActiveStyle.Name) > 0);

  screenDC := GetDC(0);
  memDC := CreateCompatibleDC(screenDC);

  FillChar(bmi, SizeOf(bmi), 0);
  bmi.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  bmi.bmiHeader.biWidth := BTN_SIZE;
  bmi.bmiHeader.biHeight := -BTN_SIZE;  // top-down
  bmi.bmiHeader.biPlanes := 1;
  bmi.bmiHeader.biBitCount := 32;
  bmi.bmiHeader.biCompression := BI_RGB;

  bmp := CreateDIBSection(memDC, bmi, DIB_RGB_COLORS, Pointer(bits), 0, 0);
  SelectObject(memDC, bmp);

  // Draw each pixel with premultiplied alpha BGRA
  for y := 0 to BTN_SIZE - 1 do
    for x := 0 to BTN_SIZE - 1 do
    begin
      pixel := PRGBQuad(NativeInt(bits) + (y * BTN_SIZE + x) * 4);

      // Round rectangle mask: 2px radius
      var inRect := (x >= 1) and (x <= BTN_SIZE - 2) and
                    (y >= 1) and (y <= BTN_SIZE - 2);

      if inRect then
      begin
        // Hamburger menu icon: 3 horizontal lines
        var isLine := ((y >= 4) and (y <= 5) and (x >= 4) and (x <= BTN_SIZE - 5)) or
                      ((y >= 8) and (y <= 9) and (x >= 4) and (x <= BTN_SIZE - 5)) or
                      ((y >= 12) and (y <= 13) and (x >= 4) and (x <= BTN_SIZE - 5));

        if isLine then
        begin
          // Icon lines: white in light mode, light gray in dark mode
          if isDarkMode then
          begin
            pixel^.rgbBlue := 220;
            pixel^.rgbGreen := 220;
            pixel^.rgbRed := 220;
          end
          else
          begin
            pixel^.rgbBlue := 255;
            pixel^.rgbGreen := 255;
            pixel^.rgbRed := 255;
          end;
          pixel^.rgbReserved := 255;  // alpha
        end
        else
        begin
          // Background: dark blue (light mode) or dark gray (dark mode)
          // BGRA premultiplied: color * alpha/255
          var alpha: Byte := 200;
          if isDarkMode then
          begin
            pixel^.rgbBlue := Round(60 * alpha / 255);    // B
            pixel^.rgbGreen := Round(60 * alpha / 255);   // G
            pixel^.rgbRed := Round(60 * alpha / 255);     // R
          end
          else
          begin
            pixel^.rgbBlue := Round(180 * alpha / 255);   // B
            pixel^.rgbGreen := Round(100 * alpha / 255);  // G
            pixel^.rgbRed := Round(60 * alpha / 255);     // R
          end;
          pixel^.rgbReserved := alpha;                     // A
        end;
      end
      else
      begin
        // Outside rounded rect: fully transparent
        pixel^.rgbBlue := 0;
        pixel^.rgbGreen := 0;
        pixel^.rgbRed := 0;
        pixel^.rgbReserved := 0;
      end;
    end;

  ptDst := Point(0, 0);
  sz.cx := BTN_SIZE;
  sz.cy := BTN_SIZE;
  bf.BlendOp := AC_SRC_OVER;
  bf.BlendFlags := 0;
  bf.SourceConstantAlpha := 255;
  bf.AlphaFormat := AC_SRC_ALPHA;

  UpdateLayeredWindow(FButtonWnd, screenDC, nil, @sz,
    memDC, @ptDst, 0, @bf, ULW_ALPHA);

  DeleteObject(bmp);
  DeleteDC(memDC);
  ReleaseDC(0, screenDC);
end;

procedure TTitlebarButton.UpdatePosition;
var
  rc: TRect;
  x, y: Integer;
  target: HWND;
begin
  if FButtonWnd = 0 then Exit;

  target := FTargetHwnd;
  if (target = 0) or not IsWindow(target) or not IsWindowVisible(target) then
  begin
    if FVisible then
    begin
      ShowWindow(FButtonWnd, SW_HIDE);
      FVisible := False;
    end;
    Exit;
  end;

  // Don't show on our own windows
  if target = FButtonWnd then Exit;

  if not GetWindowRect(target, rc) then Exit;

  // Position at top-right of title bar
  x := rc.Right - BTN_SIZE - BTN_MARGIN_RIGHT;
  y := rc.Top + BTN_MARGIN_TOP;

  // Only reposition if actually moved
  var curRect: TRect;
  GetWindowRect(FButtonWnd, curRect);
  if (curRect.Left = x) and (curRect.Top = y) then Exit;

  SetWindowPos(FButtonWnd, HWND_TOPMOST, x, y, BTN_SIZE, BTN_SIZE,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);

  if not FVisible then
  begin
    FVisible := True;
  end;
end;

procedure TTitlebarButton.SetTargetHwnd(hWnd: HWND);
begin
  if FTargetHwnd = hWnd then Exit;
  FTargetHwnd := hWnd;
  if FEnabled and (hWnd <> 0) and IsWindow(hWnd) then
    UpdatePosition
  else
  begin
    if FVisible then
    begin
      ShowWindow(FButtonWnd, SW_HIDE);
      FVisible := False;
    end;
  end;
end;

procedure TTitlebarButton.SetMenuCallback(ACallback: TProc<HWND>);
begin
  FOnShowMenu := ACallback;
end;

procedure TTitlebarButton.Start;
begin
  CreateButtonWindow;
  FEnabled := True;
end;

procedure TTitlebarButton.Stop;
begin
  FEnabled := False;
  if FButtonWnd <> 0 then
    KillTimer(FButtonWnd, BTN_TIMER_TRACK);
  DestroyButtonWindow;
  FTargetHwnd := 0;
  FVisible := False;
end;

procedure TTitlebarButton.SetTarget(hWnd: HWND);
begin
  SetTargetHwnd(hWnd);
end;

end.
