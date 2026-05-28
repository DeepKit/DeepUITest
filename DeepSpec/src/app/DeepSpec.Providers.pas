{ ============================================================================
  DeepSpec.Providers

  Registers DeepSpec providers into DeepShell.
  ============================================================================ }

unit DeepSpec.Providers;

interface

uses
  DeepBase.VCL.DeepShell.MainForm,
  DeepBase.VCL.DeepShell.Intf,
  DeepSpec.Services.Project,
  DeepSpec.Services.Scan,
  DeepSpec.Services.TreeBuilder;

procedure RegisterAllProviders(AForm: TDeepMainForm;
  AProjectService: TDeepSpecProjectService;
  AScanService: TDeepSpecScanService;
  ATreeBuilder: TDeepSpecTreeBuilder);

implementation

uses
  DeepSpec.Models,
  DeepSpec.Providers.Structure,
  DeepSpec.Providers.MainView,
  DeepSpec.Providers.Inspector;

type
  TDeepMainFormAccess = class(TDeepMainForm);

procedure RegisterAllProviders(AForm: TDeepMainForm;
  AProjectService: TDeepSpecProjectService;
  AScanService: TDeepSpecScanService;
  ATreeBuilder: TDeepSpecTreeBuilder);
begin
  TDeepMainFormAccess(AForm).RegisterStructureProvider(
    TDeepSpecStructureProvider.Create(AScanService, ATreeBuilder));
  TDeepMainFormAccess(AForm).RegisterMainViewProvider(
    TDeepSpecMainViewProvider.Create(AProjectService));
  TDeepMainFormAccess(AForm).RegisterInspectorProvider(
    TDeepSpecInspectorProvider.Create(
      function(const ANodeId: string): TSpecNode
      begin
        Result := ATreeBuilder.FindNodeById(ANodeId);
      end));
end;

end.
