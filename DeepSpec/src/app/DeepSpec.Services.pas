{ ============================================================================
  DeepSpec.Services

  Re-exports service types for convenience.
  Actual registration happens in TDeepSpecMainForm.RegisterServices.
  ============================================================================ }

unit DeepSpec.Services;

interface

uses
  DeepSpec.Services.Project,
  DeepSpec.Services.Scan,
  DeepSpec.Services.SpecStore;

type
  TProjectService = DeepSpec.Services.Project.TDeepSpecProjectService;
  TScanService = DeepSpec.Services.Scan.TDeepSpecScanService;
  TSpecStoreService = DeepSpec.Services.SpecStore.TDeepSpecStoreService;

implementation

end.
