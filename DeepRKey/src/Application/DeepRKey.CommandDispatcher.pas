unit DeepRKey.CommandDispatcher;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.StrUtils, System.Classes,
  Vcl.Dialogs,
  DeepRKey.Types,
  DeepRKey.WindowOps,
  DeepRKey.SystemMenu,
  DeepRKey.TransparencyForm;

type
  /// <summary>回调类型：处理需要 Coordinator 状态的特殊命令</summary>
  TSpecialCommandHandler = reference to function(hWnd: HWND; CommandId: UInt32): Boolean;

type
  /// <summary>
  /// 命令分发器 — 处理所有窗口命令（透明度、对齐、调整大小等）
  /// 从 Coordinator 提取，职责单一：命令解析和执行
  /// </summary>
  TCommandDispatcher = class
  private
    FWindowOps: TWindowCommandService;
    FMenuInjector: TSystemMenuInjector;
    FSpecialHandler: TSpecialCommandHandler;  // 处理需要 Coordinator 状态的命令
    procedure HandleTransparencyCommand(hWnd: HWND; CommandId: UInt32);
    procedure HandleAlignCommand(hWnd: HWND; CommandId: UInt32);
    procedure HandleResizeCommand(hWnd: HWND; CommandId: UInt32);
    procedure HandleMoveToMonitorCommand(hWnd: HWND; CommandId: UInt32);
  public
    constructor Create(AWindowOps: TWindowCommandService;
      AMenuInjector: TSystemMenuInjector);

    /// <summary>设置特殊命令处理器（ClickThrough/Layout/DragByMouse 等需要 Coordinator 状态的命令）</summary>
    procedure SetSpecialHandler(const AHandler: TSpecialCommandHandler);

    /// <summary>分发命令到具体处理器</summary>
    procedure DispatchCommand(hWnd: HWND; CommandId: UInt32);

    /// <summary>处理菜单初始化事件（刷新菜单状态）</summary>
    procedure DispatchInitMenuEvent(hWnd: HWND; var LastRefreshTick: UInt64);
  end;

implementation

uses
  DeepRKey.Bootstrap;

{ TCommandDispatcher }

constructor TCommandDispatcher.Create(AWindowOps: TWindowCommandService;
  AMenuInjector: TSystemMenuInjector);
begin
  inherited Create;
  FWindowOps := AWindowOps;
  FMenuInjector := AMenuInjector;
  FSpecialHandler := nil;
end;

procedure TCommandDispatcher.SetSpecialHandler(const AHandler: TSpecialCommandHandler);
begin
  FSpecialHandler := AHandler;
end;

procedure TCommandDispatcher.DispatchCommand(hWnd: HWND; CommandId: UInt32);
var
  isTopMost: Boolean;
begin
  // BUG-M5 修复：验证 CommandId 在有效范围内
  if (CommandId < RK_SC_BASE) or (CommandId > RK_SC_MAX) then
  begin
    TBootstrap.Logger.Warn(
      Format('Invalid CommandId: $%x (valid range: $%x-$%x)',
        [CommandId, RK_SC_BASE, RK_SC_MAX]), 'Dispatch');
    Exit;
  end;

  TBootstrap.Logger.Info(
    Format('Command: hwnd=$%x, cmd=$%x', [NativeUInt(hWnd), CommandId]),
    'Dispatch');

  // Record state BEFORE any window-modifying operation (for undo).
  // Skip: read-only ops, undo/redo (they manage their own stacks), layout save.
  case CommandId of
    RK_SC_INFORMATION, RK_SC_UNDO, RK_SC_REDO,
    RK_SC_LAYOUT_SAVE,
    RK_SCREENSHOT, RK_SC_SCREENSHOT_FILE, RK_SC_SCREENSHOT_CLIP:
      ;  // read-only — don't record
  else
    FWindowOps.RecordWindowState(hWnd);
  end;

  // Toggle-style commands
  if CommandId = RK_SC_TOPMOST then
  begin
    var exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
    isTopMost := (exStyle and WS_EX_TOPMOST) <> 0;
    FWindowOps.SetTopMost(hWnd, not isTopMost);
    Exit;
  end;

  // Transparency presets
  if (CommandId >= RK_SC_TRANS) and (CommandId < RK_SC_MOVE_TO) then
  begin
    HandleTransparencyCommand(hWnd, CommandId);
    Exit;
  end;

  // Move to monitor
  if (CommandId >= RK_SC_MOVE_TO) and (CommandId < RK_SC_ALIGN) then
  begin
    HandleMoveToMonitorCommand(hWnd, CommandId);
    Exit;
  end;

  // Align
  if (CommandId >= RK_SC_ALIGN) and (CommandId < RK_SC_ROLLUP) then
  begin
    HandleAlignCommand(hWnd, CommandId);
    Exit;
  end;

  // RollUp
  if CommandId = RK_SC_ROLLUP then
  begin
    FWindowOps.RollUp(hWnd);
    Exit;
  end;

  // Resize presets
  if (CommandId >= RK_SC_RESIZE) and (CommandId < RK_SC_LAYOUT_SNAPSHOT) then
  begin
    HandleResizeCommand(hWnd, CommandId);
    Exit;
  end;

  // v0.2 commands (defined in Types, dispatched here)
  if CommandId = RK_SC_SEND_TO_BOTTOM then
  begin
    FWindowOps.SendToBottom(hWnd);
    Exit;
  end;

  // Special commands that need Coordinator state (ClickThrough/Layout/DragByMouse)
  if Assigned(FSpecialHandler) then
  begin
    case CommandId of
      RK_SC_CLICK_THROUGH, RK_SC_DRAG_BY_MOUSE,
      RK_SC_LAYOUT_SAVE, RK_SC_LAYOUT_RESTORE:
      begin
        if FSpecialHandler(hWnd, CommandId) then
          Exit;
      end;
    end;
  end;

  if CommandId = RK_SC_CLICK_THROUGH then
  begin
    FWindowOps.ToggleClickThrough(hWnd);
    Exit;
  end;

  if CommandId = RK_SC_INFORMATION then
  begin
    var info := TWindowOps.GetWindowInfoText(hWnd);
    MessageBox(hWnd, PChar(info), 'DeepRKey — Window Information',
      MB_OK or MB_ICONINFORMATION);
    Exit;
  end;

  // === Phase 6: Dimmer / Hide Alt+Tab / Screenshot ===

  // Dimmer submenu children
  if (CommandId >= RK_SC_DIMMER) and (CommandId <= RK_SC_DIMMER_90) then
  begin
    var alphaPct: Integer;
    case CommandId of
      RK_SC_DIMMER_50: alphaPct := 50;
      RK_SC_DIMMER_70: alphaPct := 70;
      RK_SC_DIMMER_90: alphaPct := 90;
    else
      alphaPct := 70;  // RK_SC_DIMMER base — default 70%
    end;
    FWindowOps.ToggleDimmer(hWnd, alphaPct);
    FMenuInjector.UpdateDimmerState(hWnd, FWindowOps.IsDimmed(hWnd));
    TBootstrap.Logger.Info(
      Format('Dimmer %d%% on hwnd=$%x', [alphaPct, NativeUInt(hWnd)]),
      'Dispatcher');
    Exit;
  end;

  if CommandId = RK_SC_DIMMER_OFF then
  begin
    FWindowOps.TurnOffDimmer(hWnd);
    FMenuInjector.UpdateDimmerState(hWnd, False);
    TBootstrap.Logger.Info(
      Format('Dimmer off hwnd=$%x', [NativeUInt(hWnd)]), 'Dispatcher');
    Exit;
  end;

  // Hide from Alt+Tab (toggle with confirmation)
  if CommandId = RK_SC_HIDE_FOR_ALT_TAB then
  begin
    if not FWindowOps.IsHiddenAltTab(hWnd) then
    begin
      var mbResult := MessageBox(hWnd,
        'This will hide the window from Alt+Tab and the taskbar.' + sLineBreak +
        'Use the system menu again to restore it.',
        'DeepRKey — Hide from Alt+Tab',
        MB_OKCANCEL or MB_ICONWARNING);
      if mbResult <> IDOK then Exit;
    end;
    FWindowOps.ToggleHideAltTab(hWnd);
    FMenuInjector.UpdateAltTabHidden(hWnd, FWindowOps.IsHiddenAltTab(hWnd));
    TBootstrap.Logger.Info(
      Format('HideAltTab toggled hwnd=$%x hidden=%s',
        [NativeUInt(hWnd), BoolToStr(FWindowOps.IsHiddenAltTab(hWnd), True)]),
      'Dispatcher');
    Exit;
  end;

  // Screenshot submenu children
  if CommandId = RK_SC_SCREENSHOT_FILE then
  begin
    var path := FWindowOps.SaveWindowScreenshot(hWnd, True);
    if path <> '' then
    begin
      MessageBox(hWnd,
        PChar('Screenshot saved to:' + sLineBreak + path + sLineBreak +
              '(also copied to clipboard)'),
        'DeepRKey — Screenshot', MB_OK or MB_ICONINFORMATION);
      TBootstrap.Logger.Info(Format('Screenshot saved: %s', [path]),
        'Dispatcher');
    end;
    Exit;
  end;

  if CommandId = RK_SC_SCREENSHOT_CLIP then
  begin
    FWindowOps.SaveWindowScreenshot(hWnd, False);
    MessageBox(hWnd, 'Window copied to clipboard.',
      'DeepRKey — Screenshot', MB_OK or MB_ICONINFORMATION);
    TBootstrap.Logger.Info('Screenshot copied to clipboard', 'Dispatcher');
    Exit;
  end;

  // Force Resizable (toggle)
  if CommandId = RK_SC_RESIZABLE then
  begin
    FWindowOps.ToggleResizable(hWnd);
    FMenuInjector.UpdateResizableState(hWnd, FWindowOps.IsForcedResizable(hWnd));
    TBootstrap.Logger.Info(
      Format('Resizable toggled hwnd=$%x resizable=%s',
        [NativeUInt(hWnd), BoolToStr(FWindowOps.IsForcedResizable(hWnd), True)]),
      'Dispatcher');
    Exit;
  end;

  // Undo / Redo
  if CommandId = RK_SC_UNDO then
  begin
    FWindowOps.PerformUndo;
    TBootstrap.Logger.Info('Undo performed', 'Dispatcher');
    Exit;
  end;

  if CommandId = RK_SC_REDO then
  begin
    FWindowOps.PerformRedo;
    TBootstrap.Logger.Info('Redo performed', 'Dispatcher');
    Exit;
  end;

  TBootstrap.Logger.Warn(
    Format('Unhandled command: $%x', [CommandId]), 'Dispatch');
end;

procedure TCommandDispatcher.HandleTransparencyCommand(hWnd: HWND;
  CommandId: UInt32);
var
  alpha: Byte;
begin
  alpha := 255;
  case CommandId of
    RK_SC_TRANS_100:   alpha := 255;
    RK_SC_TRANS_75:    alpha := 191;
    RK_SC_TRANS_50:    alpha := 128;
    RK_SC_TRANS_25:    alpha := 64;
    RK_SC_TRANS_10:    alpha := 26;
    RK_SC_TRANS_CUSTOM:
  begin
    var customAlpha := 200;
    if TfrmTransparency.ShowDialog(customAlpha) then
      FWindowOps.SetTransparency(hWnd, customAlpha);
    Exit;
  end;
  end;
  FWindowOps.SetTransparency(hWnd, alpha);
end;

procedure TCommandDispatcher.HandleAlignCommand(hWnd: HWND; CommandId: UInt32);
var
  align: TRKeyAlignment;
begin
  align := raCenter;
  case CommandId of
    RK_SC_ALIGN_TOP_LEFT:     align := raTopLeft;
    RK_SC_ALIGN_TOP_RIGHT:    align := raTopRight;
    RK_SC_ALIGN_BOTTOM_LEFT:  align := raBottomLeft;
    RK_SC_ALIGN_BOTTOM_RIGHT: align := raBottomRight;
    RK_SC_ALIGN_CENTER:       align := raCenter;
    RK_SC_ALIGN_SNAP_EDGE:    align := raSnapEdge;
  end;
  FWindowOps.AlignWindow(hWnd, align);
end;

procedure TCommandDispatcher.HandleResizeCommand(hWnd: HWND; CommandId: UInt32);
var
  offset: UInt32;
  idx: Integer;
  w, h: Integer;
  presets: TArray<string>;
begin
  offset := CommandId - RK_SC_RESIZE;
  if offset < $010 then Exit;
  idx := Integer(offset div $010) - 1;

  // Parse presets from the menu injector
  presets := FMenuInjector.ResizePresets.Split([';']);
  if (idx >= 0) and (idx < Length(presets)) then
  begin
    var parts := presets[idx].Trim.Split(['x', 'X']);
    if Length(parts) >= 2 then
    begin
      if TryStrToInt(parts[0].Trim, w) and TryStrToInt(parts[1].Trim, h) then
      begin
        FWindowOps.ResizeWindow(hWnd, w, h);
        Exit;
      end;
    end;
  end;

  // Fallback to hardcoded defaults
  case offset of
    $010: begin w := 800;  h := 600;  end;
    $020: begin w := 1024; h := 768;  end;
    $030: begin w := 1280; h := 720;  end;
    $040: begin w := 1920; h := 1080; end;
  else
    Exit;
  end;
  FWindowOps.ResizeWindow(hWnd, w, h);
end;

procedure TCommandDispatcher.HandleMoveToMonitorCommand(hWnd: HWND;
  CommandId: UInt32);
var
  offset: UInt32;
  monitorIdx: Integer;
begin
  offset := CommandId - RK_SC_MOVE_TO;
  if (offset mod RK_SC_STEP) <> 0 then Exit;
  monitorIdx := Integer(offset div RK_SC_STEP) - 1;
  if monitorIdx < 0 then Exit;
  FWindowOps.MoveToMonitor(hWnd, monitorIdx);
end;

procedure TCommandDispatcher.DispatchInitMenuEvent(hWnd: HWND;
  var LastRefreshTick: UInt64);
begin
  // BUG-M4 修复：节流菜单刷新，100ms 内不重复刷新
  var now := GetTickCount64;
  if (LastRefreshTick <> 0) and (now - LastRefreshTick < 100) then
    Exit;

  // WM_INITMENUPOPUP: refresh menu check/enable state
  if FMenuInjector <> nil then
  begin
    // Update Undo/Redo enable state from the undo manager
    if FWindowOps <> nil then
      FMenuInjector.UpdateUndoRedoState(
        FWindowOps.UndoManager.CanUndo,
        FWindowOps.UndoManager.CanRedo);
    FMenuInjector.RefreshMenuState(hWnd);
  end;
  LastRefreshTick := now;
end;

end.
