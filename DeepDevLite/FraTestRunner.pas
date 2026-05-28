unit FraTestRunner;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls,
  FMX.Layouts, FMX.ScrollBox, FMX.Memo, uModels;

type
  TFrameTestRunner = class(TFrame)
    LayoutRoot: TLayout;
    LayoutHeader: TLayout;
    LblStatus: TLabel;
    MmoLog: TMemo;
    LayoutProgress: TLayout;
    PrgProgress: TProgressBar;
  private
    FTestResults: TTestResults;
  public
    procedure SetResults(const AResults: TTestResults);
    procedure AppendLog(const AMsg: string);
    procedure SetProgress(AValue: Single);
  end;

implementation

{$R *.fmx}

procedure TFrameTestRunner.SetResults(const AResults: TTestResults);
begin
  FTestResults := AResults;
  MmoLog.Text := AResults.RawOutput;
  
  if AResults.OverallPassed then
    LblStatus.Text := Format('验证通过 (%d/%d)', [AResults.GetPassCount, AResults.GetTotalCount])
  else
    LblStatus.Text := Format('验证失败 (%d/%d)', [AResults.GetPassCount, AResults.GetTotalCount]);
end;

procedure TFrameTestRunner.AppendLog(const AMsg: string);
begin
  MmoLog.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

procedure TFrameTestRunner.SetProgress(AValue: Single);
begin
  PrgProgress.Value := AValue;
end;

end.
