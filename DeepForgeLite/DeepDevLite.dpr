program DeepDevLite;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Types,
  FMX.Dialogs,
  FireDAC.FMXUI.Wait,
  DeepBase.Manager in '..\DeepBase\Core\DeepBase.Manager.pas',
  DeepBase.Persistence.Manager.FireDAC in '..\DeepBase\Persistence\DeepBase.Persistence.Manager.FireDAC.pas',
  DeepBase.Config in '..\DeepBase\Core\DeepBase.Config.pas',
  DeepBase.Logging in '..\DeepBase\Core\DeepBase.Logging.pas',
  DeepBase.i18n in '..\DeepBase\Core\DeepBase.i18n.pas',
  DeepBase.DB.DoQry in '..\DeepBase\Persistence\DeepBase.DB.DoQry.pas',
  DeepBase.Security in '..\DeepBase\Core\DeepBase.Security.pas',
  DeepBase.AutoFix in '..\DeepBase\Core\DeepBase.AutoFix.pas',
  uDM in 'uDM.pas' {DM: TDataModule},
  uModels in 'uModels.pas',
  uConstants in 'uConstants.pas',
  ViewMain in 'ViewMain.pas' {FormMain},
  CtrlContracts in 'CtrlContracts.pas',
  CtrlTasks in 'CtrlTasks.pas',
  CtrlAIAdapter in 'CtrlAIAdapter.pas',
  CtrlTestRunner in 'CtrlTestRunner.pas',
  CtrlReport in 'CtrlReport.pas',
  CtrlCardGenerator in 'CtrlCardGenerator.pas',
  HelperJson in 'HelperJson.pas',
  HelperFiles in 'HelperFiles.pas',
  FraDropZone in 'FraDropZone.pas' {FrameDropZone: TFrame},
  FraContractEditor in 'FraContractEditor.pas' {FrameContractEditor: TFrame},
  FraTestRunner in 'FraTestRunner.pas' {FrameTestRunner: TFrame},
  FraReport in 'FraReport.pas' {FrameReport: TFrame},
  FraCardGenerator in 'FraCardGenerator.pas' {FrameCardGenerator: TFrame},
  FraSettings in 'FraSettings.pas' {FrameSettings: TFrame};

{$R *.res}

begin
  AutoFix.Install;  // AutoFix: cross-platform core
  Application.Initialize;

  if not DeepBase.Manager.DeepBase.Initialize then
  begin
    ShowMessage('DeepDevLite Init Failed: ' + DeepBase.Manager.DeepBase.LastError);
    Halt(1);
  end;

  Application.CreateForm(TDM, DM);
  Application.CreateForm(TFormMain, FormMain);
  
  DeepBase.Manager.DeepBase.FireReadyCallbacks;
  
  AutoFix.RegisterScenario('smoke',
    procedure
    begin
      // smoke: verify AutoFix infrastructure is alive
    end);

  Application.Run;
  
  DeepBase.Manager.DeepBase.Finalize;
end.
