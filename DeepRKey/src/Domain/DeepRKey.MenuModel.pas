unit DeepRKey.MenuModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DeepRKey.Types;

type
  /// <summary>菜单项类型</summary>
  TRKeyMenuItemKind = (
    mikAction,      // 直接执行操作
    mikSubMenu,     // 子菜单入口
    mikToggle,      // 开关状态
    mikSeparator    // 分隔线
  );

  /// <summary>菜单项声明式模型</summary>
  TRKeyMenuItem = class
  private
    FCommandId: UInt32;
    FKind: TRKeyMenuItemKind;
    FTextKey: string;       // i18n key
    FDefaultText: string;   // 默认文本（英文）
    FOp: TRKeyWindowOp;
    FChildren: TObjectList<TRKeyMenuItem>;
    FEnabled: Boolean;
    FVisible: Boolean;
    FChecked: Boolean;
    FSortOrder: Integer;
    function GetChildren: TObjectList<TRKeyMenuItem>;
  public
    constructor Create(ACommandId: UInt32; AKind: TRKeyMenuItemKind;
      const ATextKey, ADefaultText: string; AOp: TRKeyWindowOp);
    destructor Destroy; override;

    property CommandId: UInt32 read FCommandId;
    property Kind: TRKeyMenuItemKind read FKind;
    property TextKey: string read FTextKey;
    property DefaultText: string read FDefaultText;
    property Op: TRKeyWindowOp read FOp;
    property Children: TObjectList<TRKeyMenuItem> read GetChildren;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Visible: Boolean read FVisible write FVisible;
    property Checked: Boolean read FChecked write FChecked;
    property SortOrder: Integer read FSortOrder write FSortOrder;
  end;

  /// <summary>菜单注册表：声明式菜单定义 + ID→Handler 映射 + 冲突检测</summary>
  TRKeyMenuRegistry = class
  private
    FItems: TObjectList<TRKeyMenuItem>;
    FCommandIdMap: TDictionary<UInt32, TRKeyMenuItem>;
    function BuildDefaultMenu: TObjectList<TRKeyMenuItem>;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>注册菜单项，检测 ID 冲突</summary>
    procedure RegisterItem(AItem: TRKeyMenuItem);

    /// <summary>按 CommandId 查找</summary>
    function FindByCommandId(CommandId: UInt32): TRKeyMenuItem;

    /// <summary>获取所有菜单项</summary>
    function GetItems: TObjectList<TRKeyMenuItem>;

    /// <summary>冲突检测：返回所有重复的 ID</summary>
    function DetectConflicts: TArray<UInt32>;
  end;

implementation

{ TRKeyMenuItem }

constructor TRKeyMenuItem.Create(ACommandId: UInt32; AKind: TRKeyMenuItemKind;
  const ATextKey, ADefaultText: string; AOp: TRKeyWindowOp);
begin
  FCommandId := ACommandId;
  FKind := AKind;
  FTextKey := ATextKey;
  FDefaultText := ADefaultText;
  FOp := AOp;
  FChildren := TObjectList<TRKeyMenuItem>.Create(True);
  FEnabled := True;
  FVisible := True;
  FChecked := False;
  FSortOrder := 0;
end;

destructor TRKeyMenuItem.Destroy;
begin
  FChildren.Free;
  inherited;
end;

function TRKeyMenuItem.GetChildren: TObjectList<TRKeyMenuItem>;
begin
  Result := FChildren;
end;

{ TRKeyMenuRegistry }

constructor TRKeyMenuRegistry.Create;
begin
  FItems := BuildDefaultMenu;
  FCommandIdMap := TDictionary<UInt32, TRKeyMenuItem>.Create(64);
  for var item in FItems do
    FCommandIdMap.AddOrSetValue(item.CommandId, item);
end;

destructor TRKeyMenuRegistry.Destroy;
begin
  FItems.Free;
  FCommandIdMap.Free;
  inherited;
end;

function TRKeyMenuRegistry.BuildDefaultMenu: TObjectList<TRKeyMenuItem>;
begin
  Result := TObjectList<TRKeyMenuItem>.Create(True);

  // 置顶
  Result.Add(TRKeyMenuItem.Create(RK_SC_TOPMOST, mikToggle,
    'menu.topmost', 'Always On Top', rwoTopMost));

  // 透明度子菜单
  var transMenu := TRKeyMenuItem.Create(RK_SC_TRANS, mikSubMenu,
    'menu.transparency', 'Transparency', rwoTransparency);
  transMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_TRANS_100, mikAction,
    'menu.trans.100', '100% (Opaque)', rwoTransparency));
  transMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_TRANS_75, mikAction,
    'menu.trans.75', '75%', rwoTransparency));
  transMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_TRANS_50, mikAction,
    'menu.trans.50', '50%', rwoTransparency));
  transMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_TRANS_25, mikAction,
    'menu.trans.25', '25%', rwoTransparency));
  transMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_TRANS_10, mikAction,
    'menu.trans.10', '10%', rwoTransparency));
  transMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_TRANS_CUSTOM, mikAction,
    'menu.trans.custom', 'Custom...', rwoTransparency));
  Result.Add(transMenu);

  // 移动到显示器（动态生成，仅注册 base）
  Result.Add(TRKeyMenuItem.Create(RK_SC_MOVE_TO, mikSubMenu,
    'menu.moveto', 'Move To Monitor', rwoMoveToMonitor));

  // 对齐子菜单
  var alignMenu := TRKeyMenuItem.Create(RK_SC_ALIGN, mikSubMenu,
    'menu.align', 'Align', rwoAlign);
  alignMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_ALIGN_TOP_LEFT, mikAction,
    'menu.align.topleft', 'Top Left', rwoAlign));
  alignMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_ALIGN_TOP_RIGHT, mikAction,
    'menu.align.topright', 'Top Right', rwoAlign));
  alignMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_ALIGN_BOTTOM_LEFT, mikAction,
    'menu.align.bottomleft', 'Bottom Left', rwoAlign));
  alignMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_ALIGN_BOTTOM_RIGHT, mikAction,
    'menu.align.bottomright', 'Bottom Right', rwoAlign));
  alignMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_ALIGN_CENTER, mikAction,
    'menu.align.center', 'Center', rwoAlign));
  alignMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_ALIGN_SNAP_EDGE, mikAction,
    'menu.align.snapedge', 'Snap to Edge', rwoAlign));
  Result.Add(alignMenu);

  // 预设尺寸（动态生成，仅注册 base）
  Result.Add(TRKeyMenuItem.Create(RK_SC_RESIZE, mikSubMenu,
    'menu.resize', 'Resize', rwoResize));

  // 卷起
  Result.Add(TRKeyMenuItem.Create(RK_SC_ROLLUP, mikAction,
    'menu.rollup', 'Roll Up', rwoRollUp));

  // v0.2 功能
  Result.Add(TRKeyMenuItem.Create(RK_SC_SEND_TO_BOTTOM, mikAction,
    'menu.sendtobottom', 'Send to Bottom', rwoSendToBottom));

  Result.Add(TRKeyMenuItem.Create(RK_SC_CLICK_THROUGH, mikToggle,
    'menu.clickthrough', 'Click Through', rwoClickThrough));

  Result.Add(TRKeyMenuItem.Create(RK_SC_INFORMATION, mikAction,
    'menu.information', 'Window Information...', rwoInformation));

  // Layout snapshot
  var layoutMenu := TRKeyMenuItem.Create(RK_SC_LAYOUT_SNAPSHOT, mikSubMenu,
    'menu.layout', 'Layout Snapshot', rwoLayoutSave);
  layoutMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_LAYOUT_SAVE, mikAction,
    'menu.layout.save', 'Save Current Layout', rwoLayoutSave));
  layoutMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_LAYOUT_RESTORE, mikAction,
    'menu.layout.restore', 'Restore Saved Layout', rwoLayoutRestore));
  Result.Add(layoutMenu);

  // v0.3 Phase 6 features

  // Dimmer submenu
  var dimmerMenu := TRKeyMenuItem.Create(RK_SC_DIMMER, mikSubMenu,
    'menu.dimmer', 'Window Dimmer', rwoDimmerOn);
  dimmerMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_DIMMER_50, mikAction,
    'menu.dimmer.50', '50% (Light)', rwoDimmerOn));
  dimmerMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_DIMMER_70, mikAction,
    'menu.dimmer.70', '70% (Medium)', rwoDimmerOn));
  dimmerMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_DIMMER_90, mikAction,
    'menu.dimmer.90', '90% (Dark)', rwoDimmerOn));
  dimmerMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_DIMMER_OFF, mikAction,
    'menu.dimmer.off', 'Off', rwoDimmerOff));
  Result.Add(dimmerMenu);

  // Hide from Alt+Tab (toggle)
  Result.Add(TRKeyMenuItem.Create(RK_SC_HIDE_FOR_ALT_TAB, mikToggle,
    'menu.hidealttab', 'Hide from Alt+Tab', rwoHideForAltTab));

  // Screenshot submenu
  var ssMenu := TRKeyMenuItem.Create(RK_SCREENSHOT, mikSubMenu,
    'menu.screenshot', 'Screenshot', rwoSaveScreenshot);
  ssMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_SCREENSHOT_FILE, mikAction,
    'menu.screenshot.file', 'Save to File', rwoSaveScreenshot));
  ssMenu.Children.Add(TRKeyMenuItem.Create(RK_SC_SCREENSHOT_CLIP, mikAction,
    'menu.screenshot.clip', 'Copy to Clipboard', rwoSaveScreenshot));
  Result.Add(ssMenu);

  // Drag by Mouse (toggle — Alt+click to drag when enabled)
  Result.Add(TRKeyMenuItem.Create(RK_SC_DRAG_BY_MOUSE, mikToggle,
    'menu.dragbymouse', 'Drag by Mouse (Alt+Click)', rwoDragByMouse));

  // Resizable (toggle — force WS_THICKFRAME)
  Result.Add(TRKeyMenuItem.Create(RK_SC_RESIZABLE, mikToggle,
    'menu.resizable', 'Force Resizable', rwoResizable));

  // Separator before undo/redo
  Result.Add(TRKeyMenuItem.Create(RK_SC_BASE + $8F0, mikSeparator,
    'menu.sep.undo', '-', rwoTopMost));

  // Undo / Redo
  Result.Add(TRKeyMenuItem.Create(RK_SC_UNDO, mikAction,
    'menu.undo', 'Undo', rwoUndo));
  Result.Add(TRKeyMenuItem.Create(RK_SC_REDO, mikAction,
    'menu.redo', 'Redo', rwoRedo));
end;

procedure TRKeyMenuRegistry.RegisterItem(AItem: TRKeyMenuItem);
begin
  if FCommandIdMap.ContainsKey(AItem.CommandId) then
    raise Exception.CreateFmt('Menu ID conflict: $%x', [AItem.CommandId]);
  FItems.Add(AItem);
  FCommandIdMap.Add(AItem.CommandId, AItem);
end;

function TRKeyMenuRegistry.FindByCommandId(CommandId: UInt32): TRKeyMenuItem;
begin
  if not FCommandIdMap.TryGetValue(CommandId, Result) then
    Result := nil;
end;

function TRKeyMenuRegistry.GetItems: TObjectList<TRKeyMenuItem>;
begin
  Result := FItems;
end;

function TRKeyMenuRegistry.DetectConflicts: TArray<UInt32>;
begin
  var conflicts := TList<UInt32>.Create;
  try
    var seen := TDictionary<UInt32, Integer>.Create;
    try
      for var item in FItems do
      begin
        if seen.ContainsKey(item.CommandId) then
          conflicts.Add(item.CommandId)
        else
          seen.Add(item.CommandId, 1);
      end;
      Result := conflicts.ToArray;
    finally
      seen.Free;
    end;
  finally
    conflicts.Free;
  end;
end;

end.