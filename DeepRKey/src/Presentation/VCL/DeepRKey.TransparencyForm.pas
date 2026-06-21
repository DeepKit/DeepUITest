unit DeepRKey.TransparencyForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ComCtrls, Vcl.ExtCtrls;

type
  TfrmTransparency = class(TForm)
    lblValue: TLabel;
    tbAlpha: TTrackBar;
    edtAlpha: TEdit;
    lblPreset: TLabel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure tbAlphaChange(Sender: TObject);
    procedure edtAlphaChange(Sender: TObject);
    procedure edtAlphaKeyPress(Sender: TObject; var Key: Char);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FAlphaValue: Integer;
    FUpdating: Boolean;
    procedure SetAlphaValue(Value: Integer);
    procedure UpdateDisplay;
  public
    class function ShowDialog(out AAlpha: Integer): Boolean;
    property AlphaValue: Integer read FAlphaValue;
  end;

implementation

{$R *.dfm}

{ TfrmTransparency }

class function TfrmTransparency.ShowDialog(out AAlpha: Integer): Boolean;
begin
  var frm := TfrmTransparency.Create(nil);
  try
    frm.SetAlphaValue(AAlpha);
    Result := frm.ShowModal = mrOk;
    if Result then
      AAlpha := frm.FAlphaValue;
  finally
    frm.Free;
  end;
end;

procedure TfrmTransparency.SetAlphaValue(Value: Integer);
begin
  if Value < 10 then Value := 10;
  if Value > 255 then Value := 255;
  FAlphaValue := Value;
  UpdateDisplay;
end;

procedure TfrmTransparency.UpdateDisplay;
begin
  FUpdating := True;
  try
    tbAlpha.Position := FAlphaValue;
    edtAlpha.Text := IntToStr(FAlphaValue);
    lblValue.Caption := Format('%d%%', [Round(FAlphaValue / 255 * 100)]);
  finally
    FUpdating := False;
  end;
end;

procedure TfrmTransparency.tbAlphaChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetAlphaValue(tbAlpha.Position);
end;

procedure TfrmTransparency.edtAlphaChange(Sender: TObject);
begin
  if FUpdating then Exit;
  var val: Integer;
  if TryStrToInt(edtAlpha.Text, val) then
    SetAlphaValue(val);
end;

procedure TfrmTransparency.edtAlphaKeyPress(Sender: TObject; var Key: Char);
begin
  if not (CharInSet(Key, ['0'..'9', #8, #13])) then
    Key := #0;
  if Key = #13 then
  begin
    btnOK.Click;
    Key := #0;
  end;
end;

procedure TfrmTransparency.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    btnCancel.Click;
end;

end.