{ ============================================================================
  ArtifactOS.Desk.MainForm

  TDeskMainForm = class(TDeepMainForm). Main VCL desktop for ArtifactOS.

  Phase 1 scope:
  - Case/Studio/Artifact tree navigation
  - Quality snapshot dashboard
  - Publication package status
  - Contract pipeline status
  ============================================================================ }

unit ArtifactOS.Desk.MainForm;

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  DeepBase.VCL.DeepShell,
  ArtifactOS.Desk.Providers,
  ArtifactOS.Desk.Commands,
  ArtifactOS.Desk.Services;

type
  TDeskMainForm = class(TDeepMainForm)
  protected
    procedure RegisterServices; override;
    procedure RegisterCommands; override;
    procedure RegisterProviders; override;
    procedure AfterShellShown; override;
    procedure BeforeShellClose; override;
  end;

var
  DeskMainForm: TDeskMainForm;

implementation

uses
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Desk.EvolutionConsole;

{ TDeskMainForm }

procedure TDeskMainForm.RegisterServices;
begin
  inherited;
  // Register ArtifactOS-specific services on the shell registry
  Services.RegisterService('artifactos.db',
    TArtifactOSServiceImpl.Create as IInterface);
end;

procedure TDeskMainForm.RegisterCommands;
begin
  inherited;
  RegisterDeskCommands(Commands, Status);
end;

procedure TDeskMainForm.RegisterProviders;
begin
  inherited;
  RegisterStructureProvider(TDeskStructureProvider.Create);
  RegisterMainViewProvider(TDeskMainViewProvider.Create);
  RegisterInspectorProvider(TDeskInspectorProvider.Create);
  RegisterSettingsPageProvider(TDeskSettingsPageProvider.Create);
  RegisterMainViewProvider(TEvolutionViewProvider.Create);
end;

procedure TDeskMainForm.AfterShellShown;
begin
  inherited;
  Caption := 'ArtifactOS Desk';

  // Verify PG connectivity
  try
    ArtifactOS_DB.Connect;
    try
      var SchemaExists := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''artifactos''');
      if SchemaExists = '1' then
        Status.Info('desk.boot', 'ArtifactOS schema connected. Database ready.')
      else
        Status.Warning('desk.boot', 'artifactos schema not found. Run migrations first.');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    on E: Exception do
      Status.ShellError('desk.boot', 'Database connection failed: ' + E.Message, '');
  end;

  // Open default view: Today's Desk
  OpenView(TShellObjectRef.Make('today', 'desk', 'artifactos', 'Today'));
end;

procedure TDeskMainForm.BeforeShellClose;
begin
  inherited;
  Status.Info('desk.shutdown', 'ArtifactOS Desk closing.');
end;

end.
