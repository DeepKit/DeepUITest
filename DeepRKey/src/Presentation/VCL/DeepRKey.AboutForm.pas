unit DeepRKey.AboutForm;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  TfrmAbout = class(TForm)
    pnlMain: TPanel;
    lblTitle: TLabel;
    lblVersion: TLabel;
    lblDescription: TLabel;
    lblTech: TLabel;
    lblCopyright: TLabel;
    lblLicense: TLabel;
    btnOK: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
  public
    class procedure ShowAbout;
  end;

implementation

{$R *.dfm}

{ TfrmAbout }

class procedure TfrmAbout.ShowAbout;
begin
  var frm := TfrmAbout.Create(nil);
  try
    frm.ShowModal;
  finally
    frm.Free;
  end;
end;

procedure TfrmAbout.FormCreate(Sender: TObject);
begin
  var year := FormatDateTime('yyyy', Now);
  lblTitle.Caption := 'DeepRKey';
  lblVersion.Caption := 'v0.1.0';
  lblDescription.Caption := 'Windows System Menu Enhancement Tool';
  lblTech.Caption := 'Delphi 13.1 + VCL + Win32 API';
  lblCopyright.Caption := Format('Copyright (c) %s', [year]);
  lblLicense.Caption := 'MIT License';
end;

procedure TfrmAbout.btnOKClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmAbout.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    Close;
end;

end.