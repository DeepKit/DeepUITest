unit FraCodeInput;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.Layouts,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo, FMX.Edit;

type
  TFrameCodeInput = class(TFrame)
    LayoutRoot: TLayout;
    LayoutHeader: TLayout;
    LblTitle: TLabel;
    LblSubtitle: TLabel;
    
    LayoutInputArea: TLayout;
    LblPrompt: TLabel;
    MemoCode: TMemo;
    
    LayoutLanguage: TLayout;
    LblLanguage: TLabel;
    LblDetectedLang: TLabel;
    
    LayoutButtons: TLayout;
    BtnPaste: TButton;
    BtnStartVerify: TButton;
    
    procedure MemoCodeChange(Sender: TObject);
    procedure BtnPasteClick(Sender: TObject);
    procedure BtnStartVerifyClick(Sender: TObject);
  private
    FOnStartVerify: TNotifyEvent;
    FCodeText: string;
    FDetectedLang: string;
    procedure UpdateLanguageDisplay;
  public
    property OnStartVerify: TNotifyEvent read FOnStartVerify write FOnStartVerify;
    property CodeText: string read FCodeText;
    property DetectedLanguage: string read FDetectedLang;
    procedure Clear;
  end;

implementation

{$R *.fmx}

uses
  uModels, System.IOUtils;

procedure TFrameCodeInput.MemoCodeChange(Sender: TObject);
begin
  FCodeText := MemoCode.Text;
  
  if FCodeText.Trim <> '' then
  begin
    FDetectedLang := SourceLanguageToStr(slPython);
    UpdateLanguageDisplay;
  end
  else
  begin
    FDetectedLang := '';
    UpdateLanguageDisplay;
  end;
end;

procedure TFrameCodeInput.BtnPasteClick(Sender: TObject);
begin
  MemoCode.Text := '';
  FCodeText := '';
  FDetectedLang := '';
  UpdateLanguageDisplay;
end;

procedure TFrameCodeInput.BtnStartVerifyClick(Sender: TObject);
begin
  if FCodeText.Trim.IsEmpty then
  begin
    ShowMessage('请先粘贴代码');
    Exit;
  end;
  
  if Assigned(FOnStartVerify) then
    FOnStartVerify(Self);
end;

procedure TFrameCodeInput.UpdateLanguageDisplay;
begin
  if FDetectedLang <> '' then
  begin
    LblDetectedLang.Text := '检测到: ' + FDetectedLang;
    LblDetectedLang.Visible := True;
    BtnStartVerify.Enabled := True;
  end
  else
  begin
    LblDetectedLang.Text := '';
    LblDetectedLang.Visible := False;
    BtnStartVerify.Enabled := False;
  end;
end;

procedure TFrameCodeInput.Clear;
begin
  MemoCode.Text := '';
  FCodeText := '';
  FDetectedLang := '';
  UpdateLanguageDisplay;
end;

end.
