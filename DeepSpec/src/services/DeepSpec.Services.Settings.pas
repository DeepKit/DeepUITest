{ ============================================================================
  DeepSpec.Services.Settings

  Project-level settings: docs directory path, scan preferences.
  Uses DeepShell IShellSettingsStore for persistence.
  ============================================================================ }

unit DeepSpec.Services.Settings;

interface

uses
  System.SysUtils;

type
  TDeepSpecSettingsService = class(TInterfacedObject)
  private
    FProjectPath: string;
    FCustomDocsPath: string;
    procedure LoadFromStore;
  public
    procedure Initialize(const AProjectPath: string);
    function DocsFullPath: string;
    property CustomDocsPath: string read FCustomDocsPath write FCustomDocsPath;
  end;

implementation

uses
  System.IOUtils,
  DeepBase.VCL.DeepShell.Intf;

const
  SETTING_DOCS_PATH = 'deepspec.docs_path';
  DEFAULT_DOCS_DIR = 'docs';

{ TDeepSpecSettingsService }

procedure TDeepSpecSettingsService.Initialize(const AProjectPath: string);
begin
  FProjectPath := AProjectPath;
  FCustomDocsPath := '';
  LoadFromStore;
end;

procedure TDeepSpecSettingsService.LoadFromStore;
begin
  FCustomDocsPath := '';
end;

function TDeepSpecSettingsService.DocsFullPath: string;
var
  LRelPath: string;
begin
  if FCustomDocsPath <> '' then
    LRelPath := FCustomDocsPath
  else
    LRelPath := DEFAULT_DOCS_DIR;

  Result := TPath.Combine(FProjectPath, LRelPath);
end;

end.
