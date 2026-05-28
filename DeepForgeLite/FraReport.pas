unit FraReport;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.Objects, FMX.Edit, uModels;

type
  TFrameReport = class(TFrame)
    LayoutRoot: TLayout;
    Rectangle1: TRectangle;
    LayoutHeader: TLayout;
    LayoutVerdict: TLayout;
    LayoutScenarios: TLayout;
    LayoutEvidence: TLayout;
    LayoutFooter: TLayout;
    LblReportId: TLabel;
    LblProjectName: TLabel;
    LblVerifiedAt: TLabel;
    LblStatus: TLabel;
    LblPassRate: TLabel;
    ScrlBoxScenarios: TVertScrollBox;
    LblSealHash: TLabel;
    LblAIModel: TLabel;
    BtnExportPDF: TButton;
    BtnExportPNG: TButton;
    procedure BtnExportPDFClick(Sender: TObject);
    procedure BtnExportPNGClick(Sender: TObject);
  private
    FReport: TVerificationReport;
    procedure UpdateUI;
    procedure AddScenarioCard(const AScenario: TContractScenario);
  public
    procedure SetReport(const AReport: TVerificationReport);
    property Report: TVerificationReport read FReport;
  end;

implementation

uses
  System.IOUtils;

{$R *.fmx}

procedure TFrameReport.BtnExportPDFClick(Sender: TObject);
begin
  ShowMessage('PDF 导出功能待实现');
end;

procedure TFrameReport.BtnExportPNGClick(Sender: TObject);
begin
  ShowMessage('PNG 导出功能待实现');
end;

procedure TFrameReport.SetReport(const AReport: TVerificationReport);
begin
  FReport := AReport;
  UpdateUI;
end;

procedure TFrameReport.UpdateUI;
var
  S: TContractScenario;
begin
  LblReportId.Text := FReport.ReportID;
  LblProjectName.Text := FReport.ProjectNameZH;
  LblVerifiedAt.Text := FormatDateTime('yyyy-mm-dd hh:nn:ss', FReport.VerifiedAt);
  
  if FReport.GetPassRate = 100 then
  begin
    LblStatus.Text := '验证通过 · VERIFIED';
    LblStatus.TextSettings.FontColor := $FF00E5A0;
  end
  else
  begin
    LblStatus.Text := '部分通过 · PARTIAL';
    LblStatus.TextSettings.FontColor := $FFFFA500;
  end;
  
  LblPassRate.Text := Format('%d/%d', [FReport.GetPassCount, FReport.GetTotalCount]);
  LblSealHash.Text := FReport.SealHash;
  LblAIModel.Text := FReport.AIModel;
  
  while ScrlBoxScenarios.Content.ChildrenCount > 0 do
    ScrlBoxScenarios.Content.Children[0].DisposeOf;
  
  for S in FReport.Scenarios do
    AddScenarioCard(S);
end;

procedure TFrameReport.AddScenarioCard(const AScenario: TContractScenario);
var
  Card: TRectangle;
  Layout: TLayout;
  Lbl: TLabel;
begin
  Card := TRectangle.Create(ScrlBoxScenarios);
  Card.Parent := ScrlBoxScenarios;
  Card.Align := TAlignLayout.Top;
  Card.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  Card.Height := 60;
  Card.Fill.Color := $FFFAFCFB;
  Card.Stroke.Color := $FFE2EAE7;
  Card.XRadius := 8;
  Card.YRadius := 8;
  
  Layout := TLayout.Create(Card);
  Layout.Parent := Card;
  Layout.Align := TAlignLayout.Client;
  Layout.Margins.Rect := TRectF.Create(8, 8, 8, 8);
  
  Lbl := TLabel.Create(Layout);
  Lbl.Parent := Layout;
  Lbl.Align := TAlignLayout.Top;
  case AScenario.Status of
    ssPass: Lbl.Text := '✅ ' + AScenario.Desc;
    ssFail: Lbl.Text := '❌ ' + AScenario.Desc;
  else
    Lbl.Text := '⏭️ ' + AScenario.Desc;
  end;
  Lbl.TextSettings.Font.Size := 13;
  
  Lbl := TLabel.Create(Layout);
  Lbl.Parent := Layout;
  Lbl.Align := TAlignLayout.Bottom;
  Lbl.Text := Format('%s · %dms', [AScenario.ID, AScenario.ResponseMS]);
  Lbl.TextSettings.Font.Size := 11;
  Lbl.TextSettings.FontColor := $FF7A9088;
end;

end.
