unit FraSettings;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.Edit, uModels;

type
  TFrameSettings = class(TFrame)
    LayoutRoot: TLayout;
    LayoutAPI: TLayout;
    LblAPI: TLabel;
    EdtAPIKey: TEdit;
    LblBaseURL: TLabel;
    EdtBaseURL: TEdit;
    LayoutModels: TLayout;
    LblModels: TLabel;
    LblTier1: TLabel;
    EdtModelTier1: TEdit;
    LblTier2: TLabel;
    EdtModelTier2: TEdit;
    LblTier3: TLabel;
    EdtModelTier3: TEdit;
    LayoutButtons: TLayout;
    BtnSave: TButton;
    BtnTest: TButton;
    BtnReset: TButton;
    LblStatus: TLabel;
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnTestClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
  private
    FConfig: TAIConfig;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure UpdateUI;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

uses
  CtrlAIAdapter;

{$R *.fmx}

constructor TFrameSettings.Create(AOwner: TComponent);
begin
  inherited;
  LoadSettings;
  UpdateUI;
end;

procedure TFrameSettings.BtnSaveClick(Sender: TObject);
begin
  FConfig.APIKey := EdtAPIKey.Text;
  FConfig.BaseURL := EdtBaseURL.Text;
  FConfig.ModelTier1 := EdtModelTier1.Text;
  FConfig.ModelTier2 := EdtModelTier2.Text;
  FConfig.ModelTier3 := EdtModelTier3.Text;
  
  SaveSettings;
  AIAdapter.SetConfig(FConfig);
  
  LblStatus.Text := '设置已保存';
end;

procedure TFrameSettings.BtnTestClick(Sender: TObject);
var
  Response: TAIResponse;
begin
  FConfig.APIKey := EdtAPIKey.Text;
  FConfig.BaseURL := EdtBaseURL.Text;
  AIAdapter.SetConfig(FConfig);
  
  LblStatus.Text := '测试中...';
  
  Response := AIAdapter.CallAI('Say OK', rlTier1);
  
  if Response.Success then
    LblStatus.Text := '连接成功！'
  else
    LblStatus.Text := '连接失败: ' + Response.ErrorMsg;
end;

procedure TFrameSettings.BtnResetClick(Sender: TObject);
begin
  FConfig.Clear;
  UpdateUI;
end;

procedure TFrameSettings.LoadSettings;
begin
  FConfig := AIAdapter.Config;
end;

procedure TFrameSettings.SaveSettings;
begin
  AIAdapter.SetConfig(FConfig);
end;

procedure TFrameSettings.UpdateUI;
begin
  EdtAPIKey.Text := FConfig.APIKey;
  EdtBaseURL.Text := FConfig.BaseURL;
  EdtModelTier1.Text := FConfig.ModelTier1;
  EdtModelTier2.Text := FConfig.ModelTier2;
  EdtModelTier3.Text := FConfig.ModelTier3;
end;

end.
