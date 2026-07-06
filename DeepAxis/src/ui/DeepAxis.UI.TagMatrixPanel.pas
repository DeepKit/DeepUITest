unit DeepAxis.UI.TagMatrixPanel;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Grids, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  DeepAxis.Core.DataTypes;

type
  /// <summary>
  ///   Placeholder panel for P1 tag matrix view.
  ///   P0: Shows a simple grid with contact identity and interaction state.
  /// </summary>
  TDeepAxisTagMatrixPanel = class(TPanel)
  private
    FGrid: TStringGrid;
    FTitleLabel: TLabel;
    FEmptyLabel: TLabel;
    procedure BuildUI;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetContacts(const AContacts: TArray<TContact>);
    procedure Clear;
  end;

implementation

{ TDeepAxisTagMatrixPanel }

constructor TDeepAxisTagMatrixPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildUI;
end;

procedure TDeepAxisTagMatrixPanel.BuildUI;
begin
  Self.BevelOuter := bvNone;
  Self.Caption := '';

  // Title
  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.Caption := '标签矩阵';
  FTitleLabel.Height := 24;

  // Grid
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 2;
  FGrid.ColCount := 4;
  FGrid.Cells[0, 0] := '联系人';
  FGrid.Cells[1, 0] := '身份';
  FGrid.Cells[2, 0] := '互动状态';
  FGrid.Cells[3, 0] := '渠道';
  FGrid.ColWidths[0] := 80;
  FGrid.ColWidths[1] := 60;
  FGrid.ColWidths[2] := 80;
  FGrid.ColWidths[3] := 80;
  FGrid.Options := FGrid.Options + [goColSizing];

  // Empty placeholder
  FEmptyLabel := TLabel.Create(Self);
  FEmptyLabel.Parent := Self;
  FEmptyLabel.Align := alBottom;
  FEmptyLabel.Caption := 'P1: 标签矩阵将在后续版本中启用';
  FEmptyLabel.Alignment := taCenter;
end;

procedure TDeepAxisTagMatrixPanel.SetContacts(const AContacts: TArray<TContact>);
var
  I: Integer;
begin
  FGrid.RowCount := Length(AContacts) + 1;
  for I := 0 to Length(AContacts) - 1 do
  begin
    FGrid.Cells[0, I + 1] := AContacts[I].DisplayNameRedacted;
    FGrid.Cells[1, I + 1] := '';
    FGrid.Cells[2, I + 1] := '';
    FGrid.Cells[3, I + 1] := '';
  end;
  FEmptyLabel.Visible := (Length(AContacts) = 0);
end;

procedure TDeepAxisTagMatrixPanel.Clear;
begin
  FGrid.RowCount := 2;
  FGrid.Cells[0, 1] := '';
  FGrid.Cells[1, 1] := '';
  FGrid.Cells[2, 1] := '';
  FGrid.Cells[3, 1] := '';
  FEmptyLabel.Visible := True;
end;

end.