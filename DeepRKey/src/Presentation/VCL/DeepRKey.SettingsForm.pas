unit DeepRKey.SettingsForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes, System.StrUtils, System.UITypes,
  System.Win.Registry,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Themes;

type
  TfrmSettings = class(TForm)
    pgcMain: TPageControl;
    tsStatus: TTabSheet;
    tsGeneral: TTabSheet;
    tsMenu: TTabSheet;
    tsAdvanced: TTabSheet;
    lblStatusHook: TLabel;
    lblStatusWindows: TLabel;
    lblStatusThreads: TLabel;
    lblStatusMMF: TLabel;
    lblStatusGUID: TLabel;
    chkAutoStart: TCheckBox;
    chkStartMinimized: TCheckBox;
    chkShowTopMost: TCheckBox;
    chkShowTransparency: TCheckBox;
    chkShowMoveToMonitor: TCheckBox;
    chkShowAlign: TCheckBox;
    chkShowResize: TCheckBox;
    chkShowRollUp: TCheckBox;
    rgSnapStrategy: TRadioGroup;
    btnOK: TButton;
    btnCancel: TButton;
    btnApply: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    // T-449: 使用 ScrollBox 承载菜单复选框，防止控件越界
    sbMenuScroll: TScrollBox;
    chkShowSendToBottom: TCheckBox;
    chkShowClickThrough: TCheckBox;
    chkShowInformation: TCheckBox;
    chkShowDimmer: TCheckBox;
    chkShowHideAltTab: TCheckBox;
    chkShowScreenshot: TCheckBox;
    chkShowDragByMouse: TCheckBox;
    chkShowResizable: TCheckBox;
    chkShowUndo: TCheckBox;
    chkShowRedo: TCheckBox;
    chkShowTitlebarButton: TCheckBox;
    // Layout snapshot controls
    cmbLayoutSlot: TComboBox;
    btnLayoutSave: TButton;
    btnLayoutRestore: TButton;
    btnLayoutDelete: TButton;
    edtResizePresets: TEdit;
    lblResizePresets: TLabel;
    // T-304: Theme controls
    lblTheme: TLabel;
    cboTheme: TComboBox;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure RefreshStatus;
    procedure SetAutoStart(Enable: Boolean);
    function GetAutoStart: Boolean;
    procedure ApplyMenuVisibility;
    procedure CreateExtraMenuCheckboxes;
    procedure CreateLayoutControls;
    procedure CreateResizePresetsEditor;
    procedure CreateThemeControls;  // T-304
    procedure RefreshLayoutInfo;
    procedure OnLayoutSlotChange(Sender: TObject);
    procedure OnLayoutSaveClick(Sender: TObject);
    procedure OnLayoutRestoreClick(Sender: TObject);
    procedure OnLayoutDeleteClick(Sender: TObject);
  public
    class procedure ShowSettings;
  end;

implementation

{$R *.dfm}

uses
  DeepRKey.Bootstrap,
  DeepRKey.Coordinator,
  DeepRKey.LayoutManager;

{ TfrmSettings }

class procedure TfrmSettings.ShowSettings;
begin
  var frm := TfrmSettings.Create(nil);
  try
    frm.ShowModal;
  finally
    frm.Free;
  end;
end;

procedure TfrmSettings.FormCreate(Sender: TObject);
begin
  CreateExtraMenuCheckboxes;
  CreateLayoutControls;
  CreateResizePresetsEditor;
  CreateThemeControls;  // T-304
  LoadSettings;
end;

procedure TfrmSettings.CreateExtraMenuCheckboxes;
  procedure PlaceCheck(var Cb: TCheckBox; ATop: Integer; const ACaption: string);
  begin
    Cb := TCheckBox.Create(Self);
    Cb.Parent := sbMenuScroll;  // T-449: 放入 ScrollBox
    Cb.Top := ATop;
    Cb.Left := 0;  // T-449: 相对于 ScrollBox
    Cb.Caption := ACaption;
    Cb.Width := 400;
  end;
begin
  // T-449: 创建 ScrollBox 承载所有菜单复选框，防止控件越界
  sbMenuScroll := TScrollBox.Create(Self);
  sbMenuScroll.Parent := tsMenu;
  sbMenuScroll.Left := 8;
  sbMenuScroll.Top := 8;
  sbMenuScroll.Width := 430;
  sbMenuScroll.Height := 300;
  sbMenuScroll.BorderStyle := bsNone;
  sbMenuScroll.AutoScroll := True;

  // 原有控件移入 ScrollBox
  chkShowTopMost.Parent := sbMenuScroll;
  chkShowTopMost.Left := 0;
  chkShowTransparency.Parent := sbMenuScroll;
  chkShowTransparency.Left := 0;
  chkShowMoveToMonitor.Parent := sbMenuScroll;
  chkShowMoveToMonitor.Left := 0;
  chkShowAlign.Parent := sbMenuScroll;
  chkShowAlign.Left := 0;
  chkShowResize.Parent := sbMenuScroll;
  chkShowResize.Left := 0;
  chkShowRollUp.Parent := sbMenuScroll;
  chkShowRollUp.Left := 0;

  PlaceCheck(chkShowSendToBottom, 160, 'Send to Bottom');
  PlaceCheck(chkShowClickThrough, 184, 'Click Through');
  PlaceCheck(chkShowInformation, 208, 'Window Information');

  // Phase 6 checkboxes
  PlaceCheck(chkShowDimmer, 232, 'Window Dimmer');
  PlaceCheck(chkShowHideAltTab, 256, 'Hide from Alt+Tab');
  PlaceCheck(chkShowScreenshot, 280, 'Screenshot');
  PlaceCheck(chkShowDragByMouse, 304, 'Drag by Mouse');
  PlaceCheck(chkShowResizable, 328, 'Force Resizable');
  PlaceCheck(chkShowUndo, 352, 'Undo');
  PlaceCheck(chkShowRedo, 376, 'Redo');
  PlaceCheck(chkShowTitlebarButton, 400, 'Titlebar Button (overlay)');
end;

procedure TfrmSettings.FormShow(Sender: TObject);
begin
  Self.ScaleForPPI(GetDpiForWindow(Self.Handle));
  RefreshStatus;
end;

procedure TfrmSettings.LoadSettings;
begin
  chkAutoStart.Checked := GetAutoStart;
  chkStartMinimized.Checked := TBootstrap.Config.ReadBool('General.StartMinimized', True);
  chkShowTopMost.Checked := TBootstrap.Config.ReadBool('Menu.ShowTopMost', True);
  chkShowTransparency.Checked := TBootstrap.Config.ReadBool('Menu.ShowTransparency', True);
  chkShowMoveToMonitor.Checked := TBootstrap.Config.ReadBool('Menu.ShowMoveToMonitor', True);
  chkShowAlign.Checked := TBootstrap.Config.ReadBool('Menu.ShowAlign', True);
  chkShowResize.Checked := TBootstrap.Config.ReadBool('Menu.ShowResize', True);
  chkShowRollUp.Checked := TBootstrap.Config.ReadBool('Menu.ShowRollUp', True);
  chkShowSendToBottom.Checked := TBootstrap.Config.ReadBool('Menu.ShowSendToBottom', True);
  chkShowClickThrough.Checked := TBootstrap.Config.ReadBool('Menu.ShowClickThrough', True);
  chkShowInformation.Checked := TBootstrap.Config.ReadBool('Menu.ShowInformation', True);
  chkShowDimmer.Checked := TBootstrap.Config.ReadBool('Menu.ShowDimmer', True);
  chkShowHideAltTab.Checked := TBootstrap.Config.ReadBool('Menu.ShowHideAltTab', True);
  chkShowScreenshot.Checked := TBootstrap.Config.ReadBool('Menu.ShowScreenshot', True);
  chkShowDragByMouse.Checked := TBootstrap.Config.ReadBool('Menu.ShowDragByMouse', True);
  chkShowResizable.Checked := TBootstrap.Config.ReadBool('Menu.ShowResizable', True);
  chkShowUndo.Checked := TBootstrap.Config.ReadBool('Menu.ShowUndo', True);
  chkShowRedo.Checked := TBootstrap.Config.ReadBool('Menu.ShowRedo', True);
  chkShowTitlebarButton.Checked := TBootstrap.Config.ReadBool('Menu.ShowTitlebarButton', False);
  rgSnapStrategy.ItemIndex := TBootstrap.Config.ReadInteger('Advanced.SnapStrategy', 0);
  if edtResizePresets <> nil then
    edtResizePresets.Text := TBootstrap.Config.ReadString('Menu.ResizePresets',
      '800x600;1024x768;1280x720;1920x1080');
  if cboTheme <> nil then
  begin
    var themeName := TBootstrap.Config.ReadString('UI.Theme', 'System');
    if cboTheme.Items.IndexOf(themeName) >= 0 then
      cboTheme.ItemIndex := cboTheme.Items.IndexOf(themeName)
    else
      cboTheme.ItemIndex := 0;
  end;
end;

procedure TfrmSettings.SaveSettings;
begin
  SetAutoStart(chkAutoStart.Checked);
  TBootstrap.Config.WriteBool('General.AutoStart', chkAutoStart.Checked);
  TBootstrap.Config.WriteBool('General.StartMinimized', chkStartMinimized.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowTopMost', chkShowTopMost.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowTransparency', chkShowTransparency.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowMoveToMonitor', chkShowMoveToMonitor.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowAlign', chkShowAlign.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowResize', chkShowResize.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowRollUp', chkShowRollUp.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowSendToBottom', chkShowSendToBottom.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowClickThrough', chkShowClickThrough.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowInformation', chkShowInformation.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowDimmer', chkShowDimmer.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowHideAltTab', chkShowHideAltTab.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowScreenshot', chkShowScreenshot.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowDragByMouse', chkShowDragByMouse.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowResizable', chkShowResizable.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowUndo', chkShowUndo.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowRedo', chkShowRedo.Checked);
  TBootstrap.Config.WriteBool('Menu.ShowTitlebarButton', chkShowTitlebarButton.Checked);
  if edtResizePresets <> nil then
    TBootstrap.Config.WriteString('Menu.ResizePresets', edtResizePresets.Text);
  TBootstrap.Config.WriteInteger('Advanced.SnapStrategy', rgSnapStrategy.ItemIndex);
  if cboTheme <> nil then
    TBootstrap.Config.WriteString('UI.Theme', cboTheme.Text);
  TBootstrap.Config.Apply;
  TBootstrap.Logger.Info('Settings saved', 'UI');
  ApplyMenuVisibility;
  if GCoordinator <> nil then
    GCoordinator.TitlebarButtonEnabled := chkShowTitlebarButton.Checked;
end;

procedure TfrmSettings.btnOKClick(Sender: TObject);
begin
  SaveSettings;
  Close;
end;

procedure TfrmSettings.btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmSettings.btnApplyClick(Sender: TObject);
begin
  SaveSettings;
end;

procedure TfrmSettings.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    Close;
end;

procedure TfrmSettings.CreateResizePresetsEditor;
begin
  lblResizePresets := TLabel.Create(Self);
  lblResizePresets.Parent := tsAdvanced;
  lblResizePresets.Top := 170;
  lblResizePresets.Left := 16;
  lblResizePresets.Caption := 'Resize presets (WxH;WxH;...):';

  edtResizePresets := TEdit.Create(Self);
  edtResizePresets.Parent := tsAdvanced;
  edtResizePresets.Top := 190;
  edtResizePresets.Left := 16;
  edtResizePresets.Width := 420;
end;

procedure TfrmSettings.CreateThemeControls;
var
  i: Integer;
  styleNames: TArray<string>;
begin
  lblTheme := TLabel.Create(Self);
  lblTheme.Parent := tsGeneral;
  lblTheme.Top := 72;
  lblTheme.Left := 16;
  lblTheme.Caption := 'Theme:';

  cboTheme := TComboBox.Create(Self);
  cboTheme.Parent := tsGeneral;
  cboTheme.Top := 68;
  cboTheme.Left := 60;
  cboTheme.Width := 180;
  cboTheme.Style := csDropDownList;

  // Fixed entries
  cboTheme.Items.Add('System');
  cboTheme.Items.Add('Light');

  // Available VCL styles (skip Windows which is the default light)
  styleNames := TStyleManager.StyleNames;
  for i := 0 to Length(styleNames) - 1 do
  begin
    if not SameText(styleNames[i], 'Windows') then
      cboTheme.Items.Add(styleNames[i]);
  end;

  cboTheme.ItemIndex := 0;
end;

procedure TfrmSettings.RefreshStatus;
begin
  if GCoordinator <> nil then
  begin
    if GCoordinator.HookController <> nil then
      lblStatusHook.Caption := Format('Hook: %d threads (%d active)',
        [GCoordinator.HookController.ThreadCount, GCoordinator.HookController.ActiveHookCount])
    else
      lblStatusHook.Caption := 'Hook: Not initialized';
    lblStatusWindows.Caption := Format('Tracked windows: %d',
      [GCoordinator.WindowTracker.WindowCount]);
    lblStatusThreads.Caption := Format('Tracked threads: %d',
      [GCoordinator.WindowTracker.ThreadCount]);
    if GCoordinator.Router <> nil then
    begin
      var dropped := GCoordinator.Router.MMFReader.GetDroppedEventCount;
      var cmdDropped := GCoordinator.Router.MMFReader.GetCommandDropCount;
      lblStatusMMF.Caption := Format('MMF drops: %d normal, %d command',
        [dropped, cmdDropped]);
    end;
    lblStatusGUID.Caption := Format('Session GUID: %s', [GCoordinator.SessionGUID]);
  end
  else
  begin
    lblStatusHook.Caption := 'Hook: Coordinator not started';
    lblStatusWindows.Caption := 'Tracked windows: 0';
    lblStatusThreads.Caption := 'Tracked threads: 0';
    lblStatusMMF.Caption := 'MMF: N/A';
    lblStatusGUID.Caption := 'Session GUID: N/A';
  end;
end;

const
  RUN_KEY_PATH = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run';
  RUN_VALUE_NAME = 'DeepRKey';

function TfrmSettings.GetAutoStart: Boolean;
var
  reg: TRegistry;
begin
  Result := False;
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly(RUN_KEY_PATH) then
    begin
      Result := reg.ValueExists(RUN_VALUE_NAME);
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

procedure TfrmSettings.SetAutoStart(Enable: Boolean);
var
  reg: TRegistry;
  exePath: string;
begin
  reg := TRegistry.Create(KEY_WRITE);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if not reg.OpenKey(RUN_KEY_PATH, True) then
    begin
      TBootstrap.Logger.Error('Failed to open Run registry key', 'Settings');
      Exit;
    end;
    if Enable then
    begin
      exePath := ParamStr(0);
      // T-449: 路径含空格时需要加引号，否则 Windows 启动时会解析错误
      if Pos(' ', exePath) > 0 then
        exePath := '"' + exePath + '"';
      reg.WriteString(RUN_VALUE_NAME, exePath);
      TBootstrap.Logger.Info(
        Format('AutoStart enabled: %s', [exePath]), 'Settings');
    end
    else
    begin
      reg.DeleteValue(RUN_VALUE_NAME);
      TBootstrap.Logger.Info('AutoStart disabled', 'Settings');
    end;
    reg.CloseKey;
  finally
    reg.Free;
  end;
end;

procedure TfrmSettings.ApplyMenuVisibility;
begin
  if GCoordinator = nil then Exit;
  GCoordinator.ApplyMenuVisibility;
  GCoordinator.RefreshAllMenus;
  TBootstrap.Logger.Info('Menu visibility applied to all windows', 'Settings');
end;

procedure TfrmSettings.CreateLayoutControls;
  procedure PlaceCtrl(var Ctrl: TControl; ALeft, ATop, AWidth, AHeight: Integer);
  begin
    Ctrl.Parent := tsAdvanced;
    Ctrl.Left := ALeft;
    Ctrl.Top := ATop;
    Ctrl.Width := AWidth;
    Ctrl.Height := AHeight;
  end;
begin
  // Slot selector
  cmbLayoutSlot := TComboBox.Create(Self);
  PlaceCtrl(TControl(cmbLayoutSlot), 16, 100, 250, 23);
  cmbLayoutSlot.Style := csDropDownList;
  cmbLayoutSlot.OnChange := OnLayoutSlotChange;

  // Buttons
  btnLayoutSave := TButton.Create(Self);
  PlaceCtrl(TControl(btnLayoutSave), 16, 132, 80, 25);
  btnLayoutSave.Caption := 'Save Layout';
  btnLayoutSave.OnClick := OnLayoutSaveClick;

  btnLayoutRestore := TButton.Create(Self);
  PlaceCtrl(TControl(btnLayoutRestore), 105, 132, 80, 25);
  btnLayoutRestore.Caption := 'Restore';
  btnLayoutRestore.OnClick := OnLayoutRestoreClick;

  btnLayoutDelete := TButton.Create(Self);
  PlaceCtrl(TControl(btnLayoutDelete), 195, 132, 80, 25);
  btnLayoutDelete.Caption := 'Delete';
  btnLayoutDelete.OnClick := OnLayoutDeleteClick;

  RefreshLayoutInfo;
end;

procedure TfrmSettings.RefreshLayoutInfo;
begin
  if cmbLayoutSlot = nil then Exit;
  cmbLayoutSlot.OnChange := nil;
  try
    cmbLayoutSlot.Items.Clear;
    if GCoordinator <> nil then
    begin
      var names := GCoordinator.LayoutManager.GetSlotNames;
      for var i := 0 to High(names) do
        cmbLayoutSlot.Items.Add(Format('[%d] %s', [i + 1, names[i]]));
      cmbLayoutSlot.ItemIndex := GCoordinator.LayoutManager.ActiveSlotIndex;
    end
    else
    begin
      for var i := 1 to 5 do
        cmbLayoutSlot.Items.Add(Format('[%d] Slot %d (empty)', [i, i]));
      cmbLayoutSlot.ItemIndex := 0;
    end;
  finally
    cmbLayoutSlot.OnChange := OnLayoutSlotChange;
  end;
end;

procedure TfrmSettings.OnLayoutSlotChange(Sender: TObject);
begin
  if GCoordinator = nil then Exit;
  if cmbLayoutSlot.ItemIndex >= 0 then
    GCoordinator.LayoutManager.SetActiveSlot(cmbLayoutSlot.ItemIndex);
end;

procedure TfrmSettings.OnLayoutSaveClick(Sender: TObject);
begin
  if GCoordinator = nil then Exit;
  var snapshot := GCoordinator.LayoutManager.Capture;
  ShowMessage(Format('Layout saved to slot "%s"'#13#13'%d windows, %d monitors',
    [snapshot.SlotName, Length(snapshot.Windows), Length(snapshot.Monitors)]));
  RefreshLayoutInfo;
end;

procedure TfrmSettings.OnLayoutRestoreClick(Sender: TObject);
begin
  if GCoordinator = nil then Exit;
  var count := GCoordinator.LayoutManager.Restore;
  if count > 0 then
    ShowMessage(Format('Restored %d windows from slot "%s"',
      [count, GCoordinator.LayoutManager.ActiveSlot.SlotName]))
  else
    ShowMessage('No saved layout found or no matching windows.');
end;

procedure TfrmSettings.OnLayoutDeleteClick(Sender: TObject);
begin
  if GCoordinator = nil then Exit;
  var idx := GCoordinator.LayoutManager.ActiveSlotIndex;
  if MessageDlg(Format('Delete slot "%s"?',
    [GCoordinator.LayoutManager.ActiveSlot.SlotName]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    GCoordinator.LayoutManager.DeleteSlot(idx);
    RefreshLayoutInfo;
  end;
end;

end.