unit DeepRKey.SystemMenu;

interface

uses
  Winapi.Windows, Winapi.MultiMon,
  System.SysUtils, System.StrUtils,
  System.Generics.Collections,
  DeepRKey.Types,
  DeepRKey.MenuModel;

type
  TSystemMenuInjector = class
  private
    FRegistry: TRKeyMenuRegistry;
    FInjectedWindows: TList<NativeUInt>;
    FMenuHandlerMap: TDictionary<UInt32, TRKeyMenuItem>;
    FDimmedWindows: TDictionary<NativeUInt, Boolean>;
    FHiddenAltTabWindows: TDictionary<NativeUInt, Boolean>;
    FForcedResizableWindows: TDictionary<NativeUInt, Boolean>;
    /// <summary>BUG-H1 修复：跟踪每窗口创建的 popup HMENU，CleanupMenu 中显式 DestroyMenu</summary>
    FWindowPopups: TDictionary<NativeUInt, TList<NativeUInt>>;
    FCanUndo: Boolean;
    FCanRedo: Boolean;
    FResizePresets: string;
    procedure RegisterHandler(Item: TRKeyMenuItem);
    function HasSentryItem(hWnd: HWND): Boolean;
    procedure DeleteDeepRKeyItems(hWnd: HWND);
    function BuildPopupMenu(hWnd: HWND; hMenu: HMENU;
      const Items: TObjectList<TRKeyMenuItem>): Integer;
    function GetMonitorCount: Integer;
    function GetMonitorName(Index: Integer): string;
    procedure InjectMoveToMonitors(hWnd: HWND; hMenu: HMENU; var Pos: Integer);
    procedure InjectResizePresets(hWnd: HWND; hMenu: HMENU; var Pos: Integer);
    /// <summary>记录 popup HMENU 到窗口跟踪字典</summary>
    procedure TrackPopup(hWnd: HWND; hPopup: HMENU);
    /// <summary>销毁指定窗口的所有跟踪 popup</summary>
    procedure DestroyTrackedPopups(hWnd: HWND);
  public
    constructor Create(ARegistry: TRKeyMenuRegistry);
    destructor Destroy; override;
    procedure PreInject(hWnd: HWND);
    procedure RefreshMenuState(hWnd: HWND);
    procedure CleanupMenu(hWnd: HWND);
    procedure ShowFallbackMenu(hWnd: HWND; X, Y: Integer);
    function FindHandler(CommandId: UInt32): TRKeyMenuItem;
    /// <summary>Record that a window's dimmer overlay is active.</summary>
    procedure UpdateDimmerState(hWnd: HWND; Active: Boolean);
    /// <summary>Record that a window has been hidden from Alt+Tab.</summary>
    procedure UpdateAltTabHidden(hWnd: HWND; Hidden: Boolean);
    /// <summary>Record that a window has been force-made resizable.</summary>
    procedure UpdateResizableState(hWnd: HWND; Resizable: Boolean);
    /// <summary>Update whether Undo/Redo are currently available (enable/disable).</summary>
    procedure UpdateUndoRedoState(CanUndo, CanRedo: Boolean);
    /// <summary>Set resize presets from config (semicolon-separated like "800x600;1024x768").</summary>
    procedure SetResizePresets(const Presets: string);
    /// <summary>BUG-H7 修复：窗口销毁时清理所有状态字典，防止内存泄漏</summary>
    procedure NotifyWindowDestroyed(hWnd: HWND);
    /// <summary>BUG-H7 修复：定期扫描清理无效窗口句柄（安全网）</summary>
    procedure PurgeInvalidWindows;
    /// <summary>Current resize presets string.</summary>
    property ResizePresets: string read FResizePresets;
  end;

implementation

uses
  Winapi.DwmApi,  // BUG-H9: 延迟 DWM cloaked 检查
  DeepRKey.Bootstrap;

type
  TMonitorEnumData = record
    TargetIdx, CurrentIdx: Integer;
    MonRect: TRect;
    IsPrimary: Boolean;
    Found: Boolean;
  end;

function MonitorNameEnumProc(hMonitor: HMONITOR; hdc: HDC;
  lprc: PRect; dwData: LPARAM): BOOL; stdcall;
var
  // BUG-P1 修复：使用显式指针解引用替代 absolute 映射
  // absolute 在 64-bit 下仅覆盖 LPARAM 参数（8 字节），
  // 而 TMonitorEnumData 记录体远大于此，会读取未初始化栈内存
  D: ^TMonitorEnumData;
  mi: TMonitorInfo;
begin
  D := Pointer(dwData);
  if D.CurrentIdx = D.TargetIdx then
  begin
    mi.cbSize := SizeOf(mi);
    if GetMonitorInfo(hMonitor, @mi) then
    begin
      D.MonRect := mi.rcMonitor;
      D.IsPrimary := (mi.dwFlags and MONITORINFOF_PRIMARY) <> 0;
      D.Found := True;
    end;
    Result := False;
  end
  else
  begin
    Inc(D.CurrentIdx);
    Result := True;
  end;
end;

{ TSystemMenuInjector }

constructor TSystemMenuInjector.Create(ARegistry: TRKeyMenuRegistry);
begin
  FRegistry := ARegistry;
  FInjectedWindows := TList<NativeUInt>.Create;
  FMenuHandlerMap := TDictionary<UInt32, TRKeyMenuItem>.Create;
  FDimmedWindows := TDictionary<NativeUInt, Boolean>.Create;
  FHiddenAltTabWindows := TDictionary<NativeUInt, Boolean>.Create;
  FForcedResizableWindows := TDictionary<NativeUInt, Boolean>.Create;
  FWindowPopups := TDictionary<NativeUInt, TList<NativeUInt>>.Create;
  FCanUndo := False;
  FCanRedo := False;
  FResizePresets := '800x600;1024x768;1280x720;1920x1080';

  for var item in FRegistry.GetItems do
    RegisterHandler(item);
end;

destructor TSystemMenuInjector.Destroy;
begin
  // BUG-H1 修复：析构时销毁所有残留 popup
  for var pair in FWindowPopups do
  begin
    for var h in pair.Value do
      DestroyMenu(HMENU(h));
    pair.Value.Free;
  end;
  FWindowPopups.Free;
  FForcedResizableWindows.Free;
  FHiddenAltTabWindows.Free;
  FDimmedWindows.Free;
  FMenuHandlerMap.Free;
  FInjectedWindows.Free;
  inherited;
end;

procedure TSystemMenuInjector.RegisterHandler(Item: TRKeyMenuItem);
begin
  FMenuHandlerMap.AddOrSetValue(Item.CommandId, Item);
  for var child in Item.Children do
    RegisterHandler(child);
end;

procedure TSystemMenuInjector.TrackPopup(hWnd: HWND; hPopup: HMENU);
var
  key: NativeUInt;
  lst: TList<NativeUInt>;
begin
  key := NativeUInt(hWnd);
  if not FWindowPopups.TryGetValue(key, lst) then
  begin
    lst := TList<NativeUInt>.Create;
    FWindowPopups.Add(key, lst);
  end;
  lst.Add(NativeUInt(hPopup));
end;

procedure TSystemMenuInjector.DestroyTrackedPopups(hWnd: HWND);
var
  key: NativeUInt;
  lst: TList<NativeUInt>;
begin
  key := NativeUInt(hWnd);
  if FWindowPopups.TryGetValue(key, lst) then
  begin
    for var h in lst do
      DestroyMenu(HMENU(h));
    lst.Free;
    FWindowPopups.Remove(key);
  end;
end;

function TSystemMenuInjector.HasSentryItem(hWnd: HWND): Boolean;
begin
  var hMenu := GetSystemMenu(hWnd, False);
  if hMenu = 0 then Exit(False);
  Result := (GetMenuState(hMenu, RK_SC_BASE, MF_BYCOMMAND) <> UInt32(-1));
end;

procedure TSystemMenuInjector.DeleteDeepRKeyItems(hWnd: HWND);
var
  hMenu, hSubMenu: Cardinal;
  itemCount, i: Integer;
  menuInfo: TMenuItemInfo;
begin
  hMenu := GetSystemMenu(hWnd, False);
  if hMenu = 0 then Exit;

  // T-445 修复：先按位置删除 MF_POPUP 项（子菜单句柄不在命令 ID 范围内）
  // 从末尾向前遍历，避免删除后索引偏移
  itemCount := GetMenuItemCount(hMenu);
  for i := itemCount - 1 downto 0 do
  begin
    FillChar(menuInfo, SizeOf(menuInfo), 0);
    menuInfo.cbSize := SizeOf(menuInfo);
    menuInfo.fMask := MIIM_FTYPE or MIIM_SUBMENU;
    if GetMenuItemInfo(hMenu, i, True, menuInfo) and
       ((menuInfo.fType and MFT_SEPARATOR) = 0) then
    begin
      hSubMenu := menuInfo.hSubMenu;
      if hSubMenu <> 0 then
      begin
        // 先从父菜单移除，再销毁子菜单（防止 Windows 仍持有引用）
        RemoveMenu(hMenu, i, MF_BYPOSITION);
        DestroyMenu(hSubMenu);
      end;
    end;
  end;

  // 然后按命令 ID 删除范围内的普通项
  var cmd := RK_SC_BASE;
  while cmd <= RK_SC_MAX do
  begin
    DeleteMenu(hMenu, cmd, MF_BYCOMMAND);
    Inc(cmd, RK_SC_STEP);
  end;
  DrawMenuBar(hWnd);
  FInjectedWindows.Remove(NativeUInt(hWnd));
end;

function TSystemMenuInjector.BuildPopupMenu(hWnd: HWND; hMenu: HMENU;
  const Items: TObjectList<TRKeyMenuItem>): Integer;
begin
  Result := 0;
  for var item in Items do
  begin
    if not item.Visible then Continue;
    var flags: UINT := MF_STRING;
    if item.Checked then flags := flags or MF_CHECKED;
    if not item.Enabled then flags := flags or MF_GRAYED;
    if item.Kind = mikSeparator then
    begin
      AppendMenu(hMenu, MF_SEPARATOR, 0, nil);
      Inc(Result);
      Continue;
    end;
    var text := TBootstrap.I18n.T(item.DefaultText, item.DefaultText);
    if item.Children.Count > 0 then
    begin
      var subMenu := CreatePopupMenu;
      BuildPopupMenu(hWnd, subMenu, item.Children);
      AppendMenu(hMenu, flags or MF_POPUP, subMenu, PChar(text));
    end
    else
      AppendMenu(hMenu, flags, item.CommandId, PChar(text));
    Inc(Result);
  end;
end;

procedure TSystemMenuInjector.InjectMoveToMonitors(hWnd: HWND; hMenu: HMENU;
  var Pos: Integer);
begin
  var count := GetMonitorCount;
  if count <= 1 then Exit;
  var subMenu := CreatePopupMenu;
  TrackPopup(hWnd, subMenu);
  for var i := 0 to count - 1 do
  begin
    var name := GetMonitorName(i);
    AppendMenu(subMenu, MF_STRING, UInt32(RK_SC_MOVE_TO + UInt32(i + 1) * RK_SC_STEP),
      PChar(Format('Monitor %d (%s)', [i + 1, name])));
  end;
  InsertMenu(hMenu, Pos, MF_BYPOSITION or MF_POPUP, subMenu,
    PChar(TBootstrap.I18n.T('Move To Monitor', 'Move To Monitor')));
  Inc(Pos);
end;

procedure TSystemMenuInjector.InjectResizePresets(hWnd: HWND; hMenu: HMENU;
  var Pos: Integer);
begin
  var subMenu := CreatePopupMenu;
  TrackPopup(hWnd, subMenu);
  var presets := FResizePresets.Split([';']);
  var itemIdx := 0;
  for var preset in presets do
  begin
    var trimmed := preset.Trim;
    if trimmed = '' then Continue;
    AppendMenu(subMenu, MF_STRING, UInt32(RK_SC_RESIZE + (itemIdx + 1) * $010),
      PChar(trimmed));
    Inc(itemIdx);
  end;
  InsertMenu(hMenu, Pos, MF_BYPOSITION or MF_POPUP, subMenu,
    PChar(TBootstrap.I18n.T('Resize', 'Resize')));
  Inc(Pos);
end;

function TSystemMenuInjector.GetMonitorCount: Integer;
begin
  Result := GetSystemMetrics(SM_CMONITORS);
end;

function TSystemMenuInjector.GetMonitorName(Index: Integer): string;
var
  Data: TMonitorEnumData;
  W, H: Integer;
  PrimaryTag: string;
begin
  Data.TargetIdx := Index;
  Data.CurrentIdx := 0;
  Data.Found := False;
  EnumDisplayMonitors(0, nil, @MonitorNameEnumProc, LPARAM(@Data));

  if Data.Found then
  begin
    W := Data.MonRect.Right - Data.MonRect.Left;
    H := Data.MonRect.Bottom - Data.MonRect.Top;
    if Data.IsPrimary then PrimaryTag := ' (primary)' else PrimaryTag := '';
    Result := Format('%dx%d%s', [W, H, PrimaryTag]);
  end
  else
    Result := Format('Display %d', [Index + 1]);
end;

procedure TSystemMenuInjector.PreInject(hWnd: HWND);
begin
  if HasSentryItem(hWnd) then Exit;

  // BUG-H9 修复：延迟 DWM cloaked 检查到此处（菜单实际需要时），
  // 避免在 EVENT_OBJECT_CREATE 回调中同步调用跨进程 DWM API
  var cloaked: DWORD := 0;
  if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, @cloaked, SizeOf(cloaked)) = S_OK)
     and (cloaked <> 0) then
    Exit;  // Cloaked window, skip injection

  var hMenu := GetSystemMenu(hWnd, False);
  if hMenu = 0 then Exit;

  // Verify the menu is valid before modifying
  var itemCount := GetMenuItemCount(hMenu);
  if itemCount < 0 then Exit;  // Invalid menu, don't proceed

  AppendMenu(hMenu, MF_SEPARATOR, 0, nil);
  var pos := GetMenuItemCount(hMenu);
  if pos < 0 then Exit;  // AppendMenu failed

  for var item in FRegistry.GetItems do
  begin
    if not item.Visible then Continue;
    // Skip dynamic submenus - they're created by InjectXxx methods
    if (item.CommandId = RK_SC_MOVE_TO) or (item.CommandId = RK_SC_RESIZE) then
      Continue;
    if item.Children.Count > 0 then
    begin
      var subMenu := CreatePopupMenu;
      TrackPopup(hWnd, subMenu);
      BuildPopupMenu(hWnd, subMenu, item.Children);
      var text := TBootstrap.I18n.T(item.DefaultText, item.DefaultText);
      if InsertMenu(hMenu, pos, MF_BYPOSITION or MF_POPUP or MF_STRING,
        subMenu, PChar(text)) = False then
      begin
        DestroyMenu(subMenu);
        Continue;  // InsertMenu failed, skip this item
      end;
    end
    else
    begin
      var text := TBootstrap.I18n.T(item.DefaultText, item.DefaultText);
      if InsertMenu(hMenu, pos, MF_BYPOSITION or MF_STRING,
        item.CommandId, PChar(text)) = False then
        Continue;  // InsertMenu failed, skip this item
    end;
    Inc(pos);
  end;
  InjectMoveToMonitors(hWnd, hMenu, pos);
  InjectResizePresets(hWnd, hMenu, pos);
  DrawMenuBar(hWnd);
  FInjectedWindows.Add(NativeUInt(hWnd));
end;

procedure TSystemMenuInjector.RefreshMenuState(hWnd: HWND);
begin
  if not HasSentryItem(hWnd) then PreInject(hWnd);
  var hMenu := GetSystemMenu(hWnd, False);
  if hMenu = 0 then Exit;
  var exStyle := GetWindowLong(hWnd, GWL_EXSTYLE);
  var isTopMost := (exStyle and WS_EX_TOPMOST) <> 0;
  var topMostFlag: UINT;
  if isTopMost then topMostFlag := MF_CHECKED else topMostFlag := MF_UNCHECKED;
  CheckMenuItem(hMenu, RK_SC_TOPMOST, MF_BYCOMMAND or topMostFlag);

  var alpha: Byte := 255;
  if (exStyle and WS_EX_LAYERED) <> 0 then
  begin
    // BUG-M2 修复：查询实际 alpha 值，而非假设 WS_EX_LAYERED = 200
    var crKey: COLORREF := 0;
    var flags: DWORD := 0;
    if GetLayeredWindowAttributes(hWnd, crKey, alpha, flags) then
    begin
      // alpha is now the actual value (0-255)
    end
    else
      alpha := 200;  // API failed, assume semi-transparent
  end;
  var transFlag: UINT;
  if alpha = 255 then transFlag := MF_CHECKED else transFlag := MF_UNCHECKED;
  CheckMenuItem(hMenu, RK_SC_TRANS_100,
    MF_BYCOMMAND or transFlag);

  // ClickThrough (WS_EX_TRANSPARENT)
  var ctFlag: UINT;
  if (exStyle and WS_EX_TRANSPARENT) <> 0 then ctFlag := MF_CHECKED else ctFlag := MF_UNCHECKED;
  CheckMenuItem(hMenu, RK_SC_CLICK_THROUGH, MF_BYCOMMAND or ctFlag);

  // Dimmer: check our internal state map
  var isDimmed := FDimmedWindows.ContainsKey(NativeUInt(hWnd));
  var dimmerFlag: UINT;
  if isDimmed then dimmerFlag := MF_CHECKED else dimmerFlag := MF_UNCHECKED;
  CheckMenuItem(hMenu, RK_SC_DIMMER, MF_BYCOMMAND or dimmerFlag);

  // Hide from Alt+Tab: check our internal state map
  var isHidden := FHiddenAltTabWindows.ContainsKey(NativeUInt(hWnd));
  var hideFlag: UINT;
  if isHidden then hideFlag := MF_CHECKED else hideFlag := MF_UNCHECKED;
  CheckMenuItem(hMenu, RK_SC_HIDE_FOR_ALT_TAB, MF_BYCOMMAND or hideFlag);

  // Force Resizable: check our internal state map
  var isResizable := FForcedResizableWindows.ContainsKey(NativeUInt(hWnd));
  var resFlag: UINT;
  if isResizable then resFlag := MF_CHECKED else resFlag := MF_UNCHECKED;
  CheckMenuItem(hMenu, RK_SC_RESIZABLE, MF_BYCOMMAND or resFlag);

  // Undo/Redo: enable/disable based on stack availability
  var undoFlag: UINT;
  if FCanUndo then undoFlag := MF_ENABLED else undoFlag := MF_GRAYED;
  EnableMenuItem(hMenu, RK_SC_UNDO, MF_BYCOMMAND or undoFlag);

  var redoFlag: UINT;
  if FCanRedo then redoFlag := MF_ENABLED else redoFlag := MF_GRAYED;
  EnableMenuItem(hMenu, RK_SC_REDO, MF_BYCOMMAND or redoFlag);
end;

procedure TSystemMenuInjector.CleanupMenu(hWnd: HWND);
begin
  // BUG-H1 修复：先销毁跟踪的 popup HMENU，再删除命令项
  DestroyTrackedPopups(hWnd);
  // Use DeleteDeepRKeyItems instead of GetSystemMenu(hWnd, True)
  // to avoid destroying the window's default system menu
  DeleteDeepRKeyItems(hWnd);
  FDimmedWindows.Remove(NativeUInt(hWnd));
  FHiddenAltTabWindows.Remove(NativeUInt(hWnd));
  FForcedResizableWindows.Remove(NativeUInt(hWnd));
end;

procedure TSystemMenuInjector.ShowFallbackMenu(hWnd: HWND; X, Y: Integer);
begin
  var hMenu := CreatePopupMenu;
  BuildPopupMenu(hWnd, hMenu, FRegistry.GetItems);
  TrackPopupMenu(hMenu, TPM_LEFTALIGN or TPM_TOPALIGN, X, Y, 0, hWnd, nil);
  DestroyMenu(hMenu);
end;

function TSystemMenuInjector.FindHandler(CommandId: UInt32): TRKeyMenuItem;
begin
  if not FMenuHandlerMap.TryGetValue(CommandId, Result) then
    Result := nil;
end;

procedure TSystemMenuInjector.UpdateDimmerState(hWnd: HWND; Active: Boolean);
begin
  if Active then
    FDimmedWindows.AddOrSetValue(NativeUInt(hWnd), True)
  else
    FDimmedWindows.Remove(NativeUInt(hWnd));
end;

procedure TSystemMenuInjector.UpdateAltTabHidden(hWnd: HWND; Hidden: Boolean);
begin
  if Hidden then
    FHiddenAltTabWindows.AddOrSetValue(NativeUInt(hWnd), True)
  else
    FHiddenAltTabWindows.Remove(NativeUInt(hWnd));
end;

procedure TSystemMenuInjector.UpdateResizableState(hWnd: HWND; Resizable: Boolean);
begin
  if Resizable then
    FForcedResizableWindows.AddOrSetValue(NativeUInt(hWnd), True)
  else
    FForcedResizableWindows.Remove(NativeUInt(hWnd));
end;

procedure TSystemMenuInjector.UpdateUndoRedoState(CanUndo, CanRedo: Boolean);
begin
  FCanUndo := CanUndo;
  FCanRedo := CanRedo;
end;

procedure TSystemMenuInjector.SetResizePresets(const Presets: string);
begin
  if Presets <> '' then
    FResizePresets := Presets;
end;

/// <summary>BUG-H7 修复：窗口销毁时清理所有状态字典</summary>
procedure TSystemMenuInjector.NotifyWindowDestroyed(hWnd: HWND);
var
  key: NativeUInt;
begin
  key := NativeUInt(hWnd);
  // 清理所有跟踪字典
  FDimmedWindows.Remove(key);
  FHiddenAltTabWindows.Remove(key);
  FForcedResizableWindows.Remove(key);
  FInjectedWindows.Remove(key);
  // popup HMENU 也一并清理
  DestroyTrackedPopups(hWnd);
end;

/// <summary>BUG-H7 修复：扫描所有字典，移除无效窗口句柄（安全网）</summary>
procedure TSystemMenuInjector.PurgeInvalidWindows;
var
  key: NativeUInt;
  toRemove: TArray<NativeUInt>;
begin
  // 收集 FInjectedWindows 中无效句柄
  SetLength(toRemove, 0);
  for key in FInjectedWindows do
  begin
    if not IsWindow(THandle(key)) then
    begin
      SetLength(toRemove, Length(toRemove) + 1);
      toRemove[High(toRemove)] := key;
    end;
  end;
  for key in toRemove do
    NotifyWindowDestroyed(THandle(key));

  // 清理其他字典中可能残留的无效句柄
  SetLength(toRemove, 0);
  for key in FDimmedWindows.Keys do
    if not IsWindow(THandle(key)) then
    begin
      SetLength(toRemove, Length(toRemove) + 1);
      toRemove[High(toRemove)] := key;
    end;
  for key in toRemove do
    FDimmedWindows.Remove(key);

  SetLength(toRemove, 0);
  for key in FHiddenAltTabWindows.Keys do
    if not IsWindow(THandle(key)) then
    begin
      SetLength(toRemove, Length(toRemove) + 1);
      toRemove[High(toRemove)] := key;
    end;
  for key in toRemove do
    FHiddenAltTabWindows.Remove(key);

  SetLength(toRemove, 0);
  for key in FForcedResizableWindows.Keys do
    if not IsWindow(THandle(key)) then
    begin
      SetLength(toRemove, Length(toRemove) + 1);
      toRemove[High(toRemove)] := key;
    end;
  for key in toRemove do
    FForcedResizableWindows.Remove(key);

  SetLength(toRemove, 0);
  for key in FWindowPopups.Keys do
    if not IsWindow(THandle(key)) then
    begin
      SetLength(toRemove, Length(toRemove) + 1);
      toRemove[High(toRemove)] := key;
    end;
  for key in toRemove do
  begin
    var lst := FWindowPopups[key];
    for var h in lst do
      DestroyMenu(HMENU(h));
    lst.Free;
    FWindowPopups.Remove(key);
  end;
end;

end.