unit FraCardGenerator;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.Objects, FMX.Edit, uModels;

type
  TFrameCardGenerator = class(TFrame)
    LayoutRoot: TLayout;
    LayoutControl: TLayout;
    LayoutPreview: TLayout;
    LblModule: TLabel;
    EdtModule: TEdit;
    LblAudience: TLabel;
    LayoutAudience: TLayout;
    BtnGirlfriend: TButton;
    BtnBoss: TButton;
    BtnPeer: TButton;
    BtnSelf: TButton;
    LblMood: TLabel;
    LayoutMood: TLayout;
    BtnSatisfied: TButton;
    BtnProud: TButton;
    BtnTired: TButton;
    BtnFocused: TButton;
    LblTheme: TLabel;
    LayoutTheme: TLayout;
    RectTheme1: TRectangle;
    RectTheme2: TRectangle;
    RectTheme3: TRectangle;
    RectTheme4: TRectangle;
    CardPreview: TRectangle;
    LblIcon: TLabel;
    LblTag: TLabel;
    LblHeadline: TLabel;
    LblSubText: TLabel;
    LayoutStats: TLayout;
    LblStatPass: TLabel;
    LblStatMS: TLabel;
    LblStatCoverage: TLabel;
    LayoutBottom: TLayout;
    BtnShuffle: TButton;
    BtnGenerate: TButton;
    BtnSavePNG: TButton;
    BtnSavePDF: TButton;
    procedure BtnGenerateClick(Sender: TObject);
    procedure BtnShuffleClick(Sender: TObject);
    procedure BtnSavePNGClick(Sender: TObject);
    procedure BtnSavePDFClick(Sender: TObject);
    procedure AudienceBtnClick(Sender: TObject);
    procedure MoodBtnClick(Sender: TObject);
    procedure ThemeRectClick(Sender: TObject);
  private
    FConfig: TCardConfig;
    procedure UpdatePreview;
    procedure SetAudience(AValue: TAudience);
    procedure SetMood(AValue: TMood);
    procedure SetTheme(AValue: TCardTheme);
  public
    procedure SetConfig(const AConfig: TCardConfig);
    property Config: TCardConfig read FConfig;
  end;

implementation

uses
  CtrlCardGenerator;

{$R *.fmx}

procedure TFrameCardGenerator.AudienceBtnClick(Sender: TObject);
begin
  if Sender = BtnGirlfriend then SetAudience(auGirlfriend)
  else if Sender = BtnBoss then SetAudience(auBoss)
  else if Sender = BtnPeer then SetAudience(auPeer)
  else if Sender = BtnSelf then SetAudience(auSelf);
end;

procedure TFrameCardGenerator.MoodBtnClick(Sender: TObject);
begin
  if Sender = BtnSatisfied then SetMood(mdSatisfied)
  else if Sender = BtnProud then SetMood(mdProud)
  else if Sender = BtnTired then SetMood(mdTired)
  else if Sender = BtnFocused then SetMood(mdFocused);
end;

procedure TFrameCardGenerator.ThemeRectClick(Sender: TObject);
begin
  if Sender = RectTheme1 then SetTheme(ctDark)
  else if Sender = RectTheme2 then SetTheme(ctLight)
  else if Sender = RectTheme3 then SetTheme(ctNight)
  else if Sender = RectTheme4 then SetTheme(ctWarm);
end;

procedure TFrameCardGenerator.BtnGenerateClick(Sender: TObject);
begin
  FConfig.ModuleName := EdtModule.Text;
  CardGeneratorController.GenerateCard(FConfig);
  UpdatePreview;
end;

procedure TFrameCardGenerator.BtnShuffleClick(Sender: TObject);
begin
  CardGeneratorController.ShuffleHeadline(FConfig);
  UpdatePreview;
end;

procedure TFrameCardGenerator.BtnSavePNGClick(Sender: TObject);
var
  SaveDlg: TSaveDialog;
begin
  SaveDlg := TSaveDialog.Create(nil);
  try
    SaveDlg.Filter := 'PNG 图片|*.png';
    SaveDlg.DefaultExt := 'png';
    SaveDlg.FileName := Format('DeepDevLite_Card_%s', [FormatDateTime('yyyymmdd', Now)]);
    
    if SaveDlg.Execute then
    begin
      if CardGeneratorController.ExportToPNG(FConfig, SaveDlg.FileName) then
        ShowMessage('保存成功')
      else
        ShowMessage('保存失败');
    end;
  finally
    SaveDlg.Free;
  end;
end;

procedure TFrameCardGenerator.BtnSavePDFClick(Sender: TObject);
begin
  ShowMessage('PDF 导出功能待实现');
end;

procedure TFrameCardGenerator.SetConfig(const AConfig: TCardConfig);
begin
  FConfig := AConfig;
  EdtModule.Text := AConfig.ModuleName;
  UpdatePreview;
end;

procedure TFrameCardGenerator.SetAudience(AValue: TAudience);
begin
  FConfig.Audience := AValue;
  
  BtnGirlfriend.TintColor := $00000000;
  BtnBoss.TintColor := $00000000;
  BtnPeer.TintColor := $00000000;
  BtnSelf.TintColor := $00000000;
  
  case AValue of
    auGirlfriend: BtnGirlfriend.TintColor := $FF0D5C4A;
    auBoss: BtnBoss.TintColor := $FF0D5C4A;
    auPeer: BtnPeer.TintColor := $FF0D5C4A;
    auSelf: BtnSelf.TintColor := $FF0D5C4A;
  end;
end;

procedure TFrameCardGenerator.SetMood(AValue: TMood);
begin
  FConfig.Mood := AValue;
  
  BtnSatisfied.TintColor := $00000000;
  BtnProud.TintColor := $00000000;
  BtnTired.TintColor := $00000000;
  BtnFocused.TintColor := $00000000;
  
  case AValue of
    mdSatisfied: BtnSatisfied.TintColor := $FF0D5C4A;
    mdProud: BtnProud.TintColor := $FF0D5C4A;
    mdTired: BtnTired.TintColor := $FF0D5C4A;
    mdFocused: BtnFocused.TintColor := $FF0D5C4A;
  end;
end;

procedure TFrameCardGenerator.SetTheme(AValue: TCardTheme);
begin
  FConfig.Theme := AValue;
  
  RectTheme1.Stroke.Color := $FFE0E8E4;
  RectTheme2.Stroke.Color := $FFE0E8E4;
  RectTheme3.Stroke.Color := $FFE0E8E4;
  RectTheme4.Stroke.Color := $FFE0E8E4;
  
  case AValue of
    ctDark:
    begin
      RectTheme1.Stroke.Color := $FFFFFFFF;
      CardPreview.Fill.Color := $FF0D5C4A;
    end;
    ctLight:
    begin
      RectTheme2.Stroke.Color := $FF0D5C4A;
      CardPreview.Fill.Color := $FFF7F9F8;
    end;
    ctNight:
    begin
      RectTheme3.Stroke.Color := $FFFFFFFF;
      CardPreview.Fill.Color := $FF0A0F0E;
    end;
    ctWarm:
    begin
      RectTheme4.Stroke.Color := $FF00E5A0;
      CardPreview.Fill.Color := $FF1A3C34;
    end;
  end;
  
  UpdatePreview;
end;

procedure TFrameCardGenerator.UpdatePreview;
begin
  LblIcon.Text := FConfig.Icon;
  LblTag.Text := UpperCase(FConfig.Tag);
  LblHeadline.Text := FConfig.Headline;
  LblSubText.Text := FConfig.SubText;
  LblStatPass.Text := FConfig.StatPass;
  LblStatMS.Text := FConfig.StatMS;
  LblStatCoverage.Text := FConfig.StatCoverage;
  
  case FConfig.Theme of
    ctDark, ctNight, ctWarm:
    begin
      LblIcon.TextSettings.FontColor := $FFFFFFFF;
      LblTag.TextSettings.FontColor := $FF00E5A0;
      LblHeadline.TextSettings.FontColor := $FFFFFFFF;
      LblSubText.TextSettings.FontColor := $aaFFFFFF;
    end;
    ctLight:
    begin
      LblIcon.TextSettings.FontColor := $FF0D5C4A;
      LblTag.TextSettings.FontColor := $FF0D5C4A;
      LblHeadline.TextSettings.FontColor := $FF0F1F1A;
      LblSubText.TextSettings.FontColor := $FF7A9088;
    end;
  end;
end;

end.
