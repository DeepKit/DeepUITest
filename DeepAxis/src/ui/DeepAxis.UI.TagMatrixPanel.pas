unit DeepAxis.UI.TagMatrixPanel;

{*******************************************************************************
  标签矩阵面板 — 真实化 (docs/03 §3.1 §2.6)

  列: 联系人 | 身份 | 广告计数 | 关联产品 | 闲人 | 保留
  - 广告计数: Contact.AdCount / AD_MAX_COUNT (BUG-044 参数化, 替代 TagProfile JSON)
  - 关联产品: Contact.ProductCount (0=闲人)
  - 闲人: Contact.IsIdle
  - 保留: Contact.IsUserPreserved (PRESERVE_TAG)
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Grids, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes;

type
  TDeepAxisTagMatrixPanel = class(TPanel)
  private
    FGrid: TStringGrid;
    FTitleLabel: TLabel;
    FEmptyLabel: TLabel;
    FContactCount: Integer;
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

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.Caption := '标签矩阵';
  FTitleLabel.Height := 24;

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 2;
  FGrid.ColCount := 6;
  FGrid.Cells[0, 0] := '联系人';
  FGrid.Cells[1, 0] := '身份';
  FGrid.Cells[2, 0] := '广告计数';
  FGrid.Cells[3, 0] := '关联产品';
  FGrid.Cells[4, 0] := '闲人';
  FGrid.Cells[5, 0] := '保留';
  FGrid.ColWidths[0] := 90;
  FGrid.ColWidths[1] := 70;
  FGrid.ColWidths[2] := 220;
  FGrid.ColWidths[3] := 70;
  FGrid.ColWidths[4] := 50;
  FGrid.ColWidths[5] := 50;
  FGrid.Options := FGrid.Options + [goColSizing, goRowSelect];

  FEmptyLabel := TLabel.Create(Self);
  FEmptyLabel.Parent := Self;
  FEmptyLabel.Align := alBottom;
  FEmptyLabel.Caption := '无联系人数据';
  FEmptyLabel.Alignment := taCenter;
end;

procedure TDeepAxisTagMatrixPanel.SetContacts(const AContacts: TArray<TContact>);
var
  I: Integer;
  LC: TContact;
  LIdentity, LIdle, LPreserve: string;
begin
  FContactCount := Length(AContacts);
  FGrid.RowCount := FContactCount + 1;
  for I := 0 to FContactCount - 1 do
  begin
    LC := AContacts[I];
    FGrid.Cells[0, I + 1] := LC.DisplayNameRedacted;

    if LC.IsBusiness then LIdentity := '业务'
    else if LC.IsPrivate then LIdentity := '私域'
    else LIdentity := '未知';
    FGrid.Cells[1, I + 1] := LIdentity;

    FGrid.Cells[2, I + 1] := '广告 ' + IntToStr(LC.AdCount) + '/' + IntToStr(AD_MAX_COUNT);
    FGrid.Cells[3, I + 1] := IntToStr(LC.ProductCount);

    if LC.IsIdle then LIdle := '✓' else LIdle := '';
    FGrid.Cells[4, I + 1] := LIdle;

    if LC.IsUserPreserved then LPreserve := '🔒' else LPreserve := '';
    FGrid.Cells[5, I + 1] := LPreserve;
  end;
  FEmptyLabel.Visible := (FContactCount = 0);
end;

procedure TDeepAxisTagMatrixPanel.Clear;
var
  C: Integer;
begin
  FContactCount := 0;
  FGrid.RowCount := 2;
  for C := 0 to FGrid.ColCount - 1 do
    FGrid.Cells[C, 1] := '';
  FEmptyLabel.Visible := True;
end;

end.
