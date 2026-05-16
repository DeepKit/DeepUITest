{ ============================================================================
  DeepSpec.Providers

  Registers DeepSpec providers into DeepShell.
  ============================================================================ }

unit DeepSpec.Providers;

interface

uses
  DeepBase.VCL.DeepShell.MainForm,
  DeepBase.VCL.DeepShell.Intf,
  DeepSpec.Services.Project;

procedure RegisterAllProviders(AForm: TDeepMainForm;
  AProjectService: TDeepSpecProjectService);

implementation

uses
  DeepSpec.Providers.Structure,
  DeepSpec.Providers.MainView,
  DeepSpec.Providers.Inspector;

type
  /// <summary>
  /// Helper to access protected registration methods from outside the class.
  /// </summary>
  TDeepMainFormAccess = class(TDeepMainForm);

procedure RegisterAllProviders(AForm: TDeepMainForm;
  AProjectService: TDeepSpecProjectService);
begin
  TDeepMainFormAccess(AForm).RegisterStructureProvider(TDeepSpecStructureProvider.Create);
  TDeepMainFormAccess(AForm).RegisterMainViewProvider(
    TDeepSpecMainViewProvider.Create(AProjectService));
  TDeepMainFormAccess(AForm).RegisterInspectorProvider(TDeepSpecInspectorProvider.Create);
end;

end.
