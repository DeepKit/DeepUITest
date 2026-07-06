unit DeepAxis.UI.SetupForm;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Win.Registry,
  Winapi.Windows, Winapi.ShlObj,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.FileCtrl, Vcl.Dialogs, Vcl.Graphics,
  DeepAxis.Core.Base, DeepAxis.Core.Config;

type
  /// <summary>
  ///   初始设置向导 — 引导用户选择微信数据目录。
  ///   首次启动自动弹出，也可通过菜单手动打开。
  /// </summary>
  TDeepAxisSetupForm = class(TForm)
  private
    FPathEdit: TEdit;
    FStatusLabel: TLabel;
    FDetailMemo: TMemo;
    FAutoDetectBtn: TButton;
    FBrowseBtn: TButton;
    FValidateBtn: TButton;
    FStatusImage: TLabel;
    procedure InitUI;
    procedure DoAutoDetect(Sender: TObject);
    procedure DoBrowse(Sender: TObject);
    procedure DoValidate(Sender: TObject);
    procedure DoOk(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure DoPathChange(Sender: TObject);
    procedure ValidatePath;
    function FindWeChatDataDirAuto: string;
    function CheckDatabaseFiles(const ADir: string): TArray<string>;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{ TDeepAxisSetupForm }

constructor TDeepAxisSetupForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Width := 560;
  Height := 420;
  Caption := 'DeepAxis ' + APP_TITLE_ZH + ' — 初始设置';
  InitUI;
end;

procedure TDeepAxisSetupForm.InitUI;
var
  LTopLabel, LDetailLabel: TLabel;
  LPanel: TPanel;
  LBtnPanel: TPanel;
  LOkBtn, LCancelBtn: TButton;
  LLeft: Integer;
begin
  // ── Title ──
  LTopLabel := TLabel.Create(Self);
  LTopLabel.Parent := Self;
  LTopLabel.Top := 12;
  LTopLabel.Left := 16;
  LTopLabel.Caption := '请选择微信数据目录';
  LTopLabel.Font.Size := 12;
  LTopLabel.Font.Style := [fsBold];

  // ── Path row ──
  LPanel := TPanel.Create(Self);
  LPanel.Parent := Self;
  LPanel.Top := 44;
  LPanel.Left := 12;
  LPanel.Width := 520;
  LPanel.Height := 36;
  LPanel.BevelOuter := bvNone;

  FPathEdit := TEdit.Create(LPanel);
  FPathEdit.Parent := LPanel;
  FPathEdit.Top := 4;
  FPathEdit.Left := 4;
  FPathEdit.Width := 390;
  FPathEdit.ReadOnly := True;
  FPathEdit.OnChange := DoPathChange;
  // Pre-fill with current config
  FPathEdit.Text := TDeepAxisConfig.GetWeChatDataPath;

  FBrowseBtn := TButton.Create(LPanel);
  FBrowseBtn.Parent := LPanel;
  FBrowseBtn.Top := 2;
  FBrowseBtn.Left := 400;
  FBrowseBtn.Width := 80;
  FBrowseBtn.Height := 30;
  FBrowseBtn.Caption := '浏览...';
  FBrowseBtn.OnClick := DoBrowse;

  FAutoDetectBtn := TButton.Create(LPanel);
  FAutoDetectBtn.Parent := LPanel;
  FAutoDetectBtn.Top := 2;
  FAutoDetectBtn.Left := 486;
  FAutoDetectBtn.Width := 30;
  FAutoDetectBtn.Height := 30;
  FAutoDetectBtn.Caption := '🔍';
  FAutoDetectBtn.Hint := '自动检测微信数据目录';
  FAutoDetectBtn.ShowHint := True;
  FAutoDetectBtn.OnClick := DoAutoDetect;

  // ── Status row ──
  FStatusImage := TLabel.Create(Self);
  FStatusImage.Parent := Self;
  FStatusImage.Top := 88;
  FStatusImage.Left := 16;
  FStatusImage.Caption := '';
  FStatusImage.Font.Size := 11;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Top := 88;
  FStatusLabel.Left := 36;
  FStatusLabel.Width := 500;
  FStatusLabel.Caption := '请浏览或自动检测微信数据目录';
  FStatusLabel.Font.Size := 10;

  // ── Detail section ──
  FValidateBtn := TButton.Create(Self);
  FValidateBtn.Parent := Self;
  FValidateBtn.Top := 116;
  FValidateBtn.Left := 16;
  FValidateBtn.Width := 90;
  FValidateBtn.Height := 28;
  FValidateBtn.Caption := '验证目录';
  FValidateBtn.OnClick := DoValidate;

  LDetailLabel := TLabel.Create(Self);
  LDetailLabel.Parent := Self;
  LDetailLabel.Top := 152;
  LDetailLabel.Left := 16;
  LDetailLabel.Caption := '── 检测详情 ──';
  LDetailLabel.Font.Color := clGray;

  FDetailMemo := TMemo.Create(Self);
  FDetailMemo.Parent := Self;
  FDetailMemo.Top := 172;
  FDetailMemo.Left := 16;
  FDetailMemo.Width := 512;
  FDetailMemo.Height := 150;
  FDetailMemo.ReadOnly := True;
  FDetailMemo.ScrollBars := ssVertical;
  FDetailMemo.Color := clBtnFace;
  FDetailMemo.Lines.Add('点击 "验证目录" 或 "自动检测" 查看详情');

  // ── Button row ──
  LBtnPanel := TPanel.Create(Self);
  LBtnPanel.Parent := Self;
  LBtnPanel.Top := 336;
  LBtnPanel.Left := 12;
  LBtnPanel.Width := 520;
  LBtnPanel.Height := 44;
  LBtnPanel.BevelOuter := bvNone;

  LCancelBtn := TButton.Create(LBtnPanel);
  LCancelBtn.Parent := LBtnPanel;
  LCancelBtn.Top := 6;
  LCancelBtn.Left := 330;
  LCancelBtn.Width := 80;
  LCancelBtn.Height := 32;
  LCancelBtn.Caption := '取消';
  LCancelBtn.ModalResult := mrCancel;
  LCancelBtn.OnClick := DoCancel;

  LOkBtn := TButton.Create(LBtnPanel);
  LOkBtn.Parent := LBtnPanel;
  LOkBtn.Top := 6;
  LOkBtn.Left := 420;
  LOkBtn.Width := 80;
  LOkBtn.Height := 32;
  LOkBtn.Caption := '确定';
  LOkBtn.Default := True;
  LOkBtn.ModalResult := mrOk;
  LOkBtn.OnClick := DoOk;

  // Initial validation if path is pre-filled
  if FPathEdit.Text <> '' then
    ValidatePath;
end;

// ── Auto-detect ────────────────────────────────────────────────────

function TDeepAxisSetupForm.FindWeChatDataDirAuto: string;
var
  LBase, LDir, LMsgDir: string;
  LDirs: TArray<string>;
  LReg: TRegistry;
  LDrives: array[0..2] of string;
  LDrive: string;
  LSearchPath: string;
  LUserInfo: string;
begin
  Result := '';

  // 1. Check current config
  Result := TDeepAxisConfig.GetWeChatDataPath;
  if (Result <> '') and TDirectory.Exists(Result) then Exit;

  // 2. Check registry
  try
    LReg := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
    try
      LReg.RootKey := HKEY_CURRENT_USER;
      if LReg.OpenKeyReadOnly('Software\Tencent\WeChat') then
      begin
        if LReg.ValueExists('FileSavePath') then
        begin
          LBase := LReg.ReadString('FileSavePath');
          if LBase <> '' then
          begin
            // FileSavePath might be the parent, look for db_storage inside
            if TDirectory.Exists(LBase) then
            begin
              LDirs := TDirectory.GetDirectories(LBase, 'db_storage', TSearchOption.soAllDirectories);
              for LDir in LDirs do
              begin
                LMsgDir := TPath.Combine(LDir, 'message');
                if TDirectory.Exists(LMsgDir) then
                begin
                  Result := LDir;
                  Exit;
                end;
              end;
            end;
          end;
        end;
        LReg.CloseKey;
      end;
    finally
      LReg.Free;
    end;
  except
    // Registry access failed, continue
  end;

  // 3. Check common paths
  LUserInfo := TPath.GetHomePath;
  LDrives[0] := TPath.Combine(LUserInfo, 'Documents');
  LDrives[1] := LUserInfo;
  LDrives[2] := '';

  for LDrive in LDrives do
  begin
    if LDrive = '' then
      LSearchPath := 'D:\xwechat_files'
    else
      LSearchPath := TPath.Combine(LDrive, 'xwechat_files');

    if TDirectory.Exists(LSearchPath) then
    begin
      LDirs := TDirectory.GetDirectories(LSearchPath, 'db_storage', TSearchOption.soAllDirectories);
      for LDir in LDirs do
      begin
        LMsgDir := TPath.Combine(LDir, 'message');
        if TDirectory.Exists(LMsgDir) then
        begin
          Result := LDir;
          Exit;
        end;
      end;
    end;
  end;

  // 4. Enumerate all drives
  for LDrive in ['C', 'D', 'E', 'F', 'G'] do
  begin
    LSearchPath := LDrive + ':\xwechat_files';
    if TDirectory.Exists(LSearchPath) then
    begin
      LDirs := TDirectory.GetDirectories(LSearchPath, 'db_storage', TSearchOption.soAllDirectories);
      for LDir in LDirs do
      begin
        LMsgDir := TPath.Combine(LDir, 'message');
        if TDirectory.Exists(LMsgDir) then
        begin
          Result := LDir;
          Exit;
        end;
      end;
    end;
  end;
end;

// ── Database file check ────────────────────────────────────────────

function TDeepAxisSetupForm.CheckDatabaseFiles(const ADir: string): TArray<string>;
var
  LResults: TStrings;
  LPath: string;
begin
  LResults := TStringList.Create;
  try
    // Contact DB
    LPath := TPath.Combine(ADir, 'contact.db');
    if TFile.Exists(LPath) then
      LResults.Add('✅ 联系人数据库: contact.db')
    else
    begin
      LPath := TPath.Combine(ADir, 'contact_contact.db');
      if TFile.Exists(LPath) then
        LResults.Add('✅ 联系人数据库: contact_contact.db')
      else
        LResults.Add('❌ 联系人数据库: 未找到 contact.db');
    end;

    // Message DB (in message/ subdirectory or root)
    LPath := TPath.Combine(ADir, 'message');
    if TDirectory.Exists(LPath) then
    begin
      var LMsgFile := TPath.Combine(LPath, 'message_0.db');
      if TFile.Exists(LMsgFile) then
        LResults.Add('✅ 消息数据库: message/message_0.db')
      else
        LResults.Add('❌ 消息数据库: 未找到 message/message_0.db');
    end
    else
    begin
      LPath := TPath.Combine(ADir, 'message_0.db');
      if TFile.Exists(LPath) then
        LResults.Add('✅ 消息数据库: message_0.db')
      else
        LResults.Add('❌ 消息数据库: 未找到 message_0.db');
    end;

    // Session DB
    LPath := TPath.Combine(ADir, 'session.db');
    if TFile.Exists(LPath) then
      LResults.Add('✅ 会话数据库: session.db')
    else
    begin
      LPath := TPath.Combine(ADir, 'session_session.db');
      if TFile.Exists(LPath) then
        LResults.Add('✅ 会话数据库: session_session.db')
      else
        LResults.Add('❌ 会话数据库: 未找到 session.db');
    end;

    // Key file
    LPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'DeCrypt\keys\all_keys.json');
    if TFile.Exists(LPath) then
      LResults.Add('✅ 密钥文件: ' + LPath)
    else
    begin
      LPath := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\DeCrypt\keys\all_keys.json');
      if TFile.Exists(LPath) then
        LResults.Add('✅ 密钥文件: ' + LPath)
      else
        LResults.Add('❌ 密钥文件: 未找到 all_keys.json（需先扫描密钥）');
    end;

    Result := LResults.ToStringArray;
  finally
    LResults.Free;
  end;
end;

// ── Event handlers ─────────────────────────────────────────────────

procedure TDeepAxisSetupForm.DoAutoDetect(Sender: TObject);
var
  LDetected: string;
begin
  FStatusLabel.Caption := '正在自动检测...';
  FStatusImage.Caption := '⏳';
  Application.ProcessMessages;

  LDetected := FindWeChatDataDirAuto;
  if LDetected <> '' then
  begin
    FPathEdit.Text := LDetected;
    ValidatePath;
  end
  else
  begin
    FStatusLabel.Caption := '未自动找到微信数据目录，请手动浏览';
    FStatusImage.Caption := '❌';
    FDetailMemo.Lines.Clear;
    FDetailMemo.Lines.Add('自动检测未找到微信数据目录。');
    FDetailMemo.Lines.Add('');
    FDetailMemo.Lines.Add('支持的目录格式: .../db_storage');
    FDetailMemo.Lines.Add('搜索范围: 注册表、用户文档、D盘 xwechat_files');
    FDetailMemo.Lines.Add('');
    FDetailMemo.Lines.Add('请确保微信已安装并至少登录过一次。');
  end;
end;

procedure TDeepAxisSetupForm.DoBrowse(Sender: TObject);
var
  LDialog: TFileOpenDialog;
  LPath: string;
begin
  LDialog := TFileOpenDialog.Create(Self);
  try
    LDialog.Title := '选择微信数据目录 (db_storage)';
    LDialog.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    LPath := FPathEdit.Text;
    if (LPath <> '') and TDirectory.Exists(LPath) then
      LDialog.DefaultFolder := LPath
    else
    begin
      LPath := TDeepAxisConfig.GetWeChatDataPath;
      if TDirectory.Exists(LPath) then
        LDialog.DefaultFolder := LPath;
    end;
    if LDialog.Execute then
    begin
      FPathEdit.Text := LDialog.FileName;
      ValidatePath;
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TDeepAxisSetupForm.DoValidate(Sender: TObject);
begin
  ValidatePath;
end;

procedure TDeepAxisSetupForm.DoPathChange(Sender: TObject);
begin
  // Light validation on path change
  if FPathEdit.Text = '' then
  begin
    FStatusLabel.Caption := '请浏览或自动检测微信数据目录';
    FStatusImage.Caption := '';
  end;
end;

procedure TDeepAxisSetupForm.ValidatePath;
var
  LPath: string;
  LDetails: TArray<string>;
  LDetail: string;
  LGoodCount: Integer;
begin
  LPath := FPathEdit.Text;
  FDetailMemo.Lines.Clear;

  if LPath = '' then
  begin
    FStatusLabel.Caption := '请选择目录';
    FStatusImage.Caption := '';
    Exit;
  end;

  if not TDirectory.Exists(LPath) then
  begin
    FStatusLabel.Caption := '目录不存在: ' + LPath;
    FStatusImage.Caption := '❌';
    FDetailMemo.Lines.Add('路径无效，请重新选择');
    Exit;
  end;

  LDetails := CheckDatabaseFiles(LPath);
  LGoodCount := 0;
  for LDetail in LDetails do
  begin
    FDetailMemo.Lines.Add(LDetail);
    if LDetail.StartsWith('✅') then
      Inc(LGoodCount);
  end;

  FDetailMemo.Lines.Add('');
  FDetailMemo.Lines.Add(Format('检测完成: %d/4 项通过', [LGoodCount]));

  if LGoodCount >= 3 then
  begin
    FStatusLabel.Caption := '✅ 有效 — 找到 ' + IntToStr(LGoodCount) + ' 个数据库';
    FStatusImage.Caption := '✅';
    FStatusLabel.Font.Color := clGreen;
  end
  else if LGoodCount >= 1 then
  begin
    FStatusLabel.Caption := '⚠️ 部分数据库缺失 (' + IntToStr(LGoodCount) + '/4)';
    FStatusImage.Caption := '⚠️';
    FStatusLabel.Font.Color := clOlive;
  end
  else
  begin
    FStatusLabel.Caption := '❌ 目录中未找到微信数据库';
    FStatusImage.Caption := '❌';
    FStatusLabel.Font.Color := clRed;
  end;
end;

procedure TDeepAxisSetupForm.DoOk(Sender: TObject);
begin
  if FPathEdit.Text = '' then
  begin
    MessageDlg('请先选择微信数据目录', mtWarning, [mbOK], 0);
    ModalResult := mrNone;
    Exit;
  end;

  if not TDirectory.Exists(FPathEdit.Text) then
  begin
    MessageDlg('所选目录不存在，请重新选择', mtWarning, [mbOK], 0);
    ModalResult := mrNone;
    Exit;
  end;

  // Save to config
  TDeepAxisConfig.SetWeChatDataPath(FPathEdit.Text);
end;

procedure TDeepAxisSetupForm.DoCancel(Sender: TObject);
begin
  // Allow cancel
end;

end.
