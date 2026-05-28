unit FraContractEditor;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.Edit, FMX.ScrollBox, FMX.Memo, FMX.Objects,
  uModels;

type
  TOnContractConfirmed = procedure(const AContract: TContract) of object;
  TOnContractCancelled = procedure of object;
  
  TFrameContractEditor = class(TFrame)
    LayoutRoot: TLayout;
    LayoutHeader: TLayout;
    LblTitle: TLabel;
    EdtTitle: TEdit;
    LayoutPurpose: TLayout;
    LblPurpose: TLabel;
    MmoPurpose: TMemo;
    LayoutScenarios: TLayout;
    LblScenarios: TLabel;
    ScrlBoxScenarios: TVertScrollBox;
    LayoutButtons: TLayout;
    BtnConfirm: TButton;
    BtnCancel: TButton;
    BtnReanalyze: TButton;
    BtnAddScenario: TButton;
    procedure BtnConfirmClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure BtnReanalyzeClick(Sender: TObject);
    procedure BtnAddScenarioClick(Sender: TObject);
  private
    FContract: TContract;
    FOnContractConfirmed: TOnContractConfirmed;
    FOnContractCancelled: TOnContractCancelled;
    procedure UpdateUI;
    procedure ReadFromUI;
    procedure AddScenarioCard(const AScenario: TContractScenario; AIndex: Integer);
  public
    procedure SetContract(const AContract: TContract);
    property Contract: TContract read FContract;
    property OnContractConfirmed: TOnContractConfirmed read FOnContractConfirmed write FOnContractConfirmed;
    property OnContractCancelled: TOnContractCancelled read FOnContractCancelled write FOnContractCancelled;
  end;

implementation

{$R *.fmx}

procedure TFrameContractEditor.BtnConfirmClick(Sender: TObject);
begin
  ReadFromUI;
  FContract.IsConfirmed := True;
  FContract.ConfirmedAt := Now;
  
  if Assigned(FOnContractConfirmed) then
    FOnContractConfirmed(FContract);
end;

procedure TFrameContractEditor.BtnCancelClick(Sender: TObject);
begin
  if Assigned(FOnContractCancelled) then
    FOnContractCancelled;
end;

procedure TFrameContractEditor.BtnReanalyzeClick(Sender: TObject);
begin
end;

procedure TFrameContractEditor.BtnAddScenarioClick(Sender: TObject);
var
  NewScenario: TContractScenario;
begin
  NewScenario.Clear;
  NewScenario.ID := 'S' + FormatDateTime('hhnnss', Now);
  NewScenario.ScenType := stNormal;
  
  SetLength(FContract.Scenarios, Length(FContract.Scenarios) + 1);
  FContract.Scenarios[High(FContract.Scenarios)] := NewScenario;
  
  AddScenarioCard(NewScenario, High(FContract.Scenarios));
end;

procedure TFrameContractEditor.SetContract(const AContract: TContract);
begin
  FContract := AContract;
  UpdateUI;
end;

procedure TFrameContractEditor.UpdateUI;
var
  I: Integer;
begin
  EdtTitle.Text := FContract.Title;
  MmoPurpose.Text := FContract.Purpose;
  
  for I := 0 to ScrlBoxScenarios.Content.ChildrenCount - 1 do
    ScrlBoxScenarios.Content.Children[I].DisposeOf;
  
  for I := 0 to High(FContract.Scenarios) do
    AddScenarioCard(FContract.Scenarios[I], I);
end;

procedure TFrameContractEditor.ReadFromUI;
begin
  FContract.Title := EdtTitle.Text;
  FContract.Purpose := MmoPurpose.Text;
end;

procedure TFrameContractEditor.AddScenarioCard(const AScenario: TContractScenario;
  AIndex: Integer);
var
  Card: TRectangle;
  Layout: TLayout;
  LblId, LblDesc, LblType: TLabel;
  EdtDesc: TEdit;
begin
  Card := TRectangle.Create(ScrlBoxScenarios);
  Card.Parent := ScrlBoxScenarios;
  Card.Align := TAlignLayout.Top;
  Card.Margins.Rect := TRectF.Create(4, 4, 4, 4);
  Card.Height := 80;
  Card.Fill.Color := $FFFAFCFB;
  Card.Stroke.Color := $FFE2EAE7;
  Card.XRadius := 8;
  Card.YRadius := 8;
  
  Layout := TLayout.Create(Card);
  Layout.Parent := Card;
  Layout.Align := TAlignLayout.Client;
  Layout.Margins.Rect := TRectF.Create(8, 8, 8, 8);
  
  LblId := TLabel.Create(Layout);
  LblId.Parent := Layout;
  LblId.Position.X := 0;
  LblId.Position.Y := 0;
  LblId.Text := AScenario.ID;
  LblId.TextSettings.Font.Size := 12;
  LblId.TextSettings.Font.Style := [TFontStyle.fsBold];
  
  LblType := TLabel.Create(Layout);
  LblType.Parent := Layout;
  LblType.Position.X := 60;
  LblType.Position.Y := 0;
  case AScenario.ScenType of
    stNormal: LblType.Text := '正常';
    stEdge: LblType.Text := '边界';
    stError: LblType.Text := '异常';
  end;
  LblType.TextSettings.Font.Size := 11;
  LblType.TextSettings.FontColor := $FF7A9088;
  
  LblDesc := TLabel.Create(Layout);
  LblDesc.Parent := Layout;
  LblDesc.Position.X := 0;
  LblDesc.Position.Y := 24;
  LblDesc.Width := 300;
  LblDesc.Text := AScenario.Desc;
  LblDesc.TextSettings.Font.Size := 13;
  
  LblDesc := TLabel.Create(Layout);
  LblDesc.Parent := Layout;
  LblDesc.Position.X := 0;
  LblDesc.Position.Y := 48;
  LblDesc.Width := 300;
  LblDesc.Text := 'Input: ' + AScenario.Input + ' → Expected: ' + AScenario.Expected;
  LblDesc.TextSettings.Font.Size := 11;
  LblDesc.TextSettings.FontColor := $FF7A9088;
end;

end.
