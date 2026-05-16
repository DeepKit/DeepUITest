{ ============================================================================
  DeepSpec.Services.Project

  Manages the currently open project: path, type, scan state.
  ============================================================================ }

unit DeepSpec.Services.Project;

interface

uses
  System.SysUtils,
  System.Classes;

type
  TDeepSpecProjectService = class(TInterfacedObject)
  private
    FProjectPath: string;
    FProjectName: string;
    FProjectType: string;
    FIsOpen: Boolean;
  public
    constructor Create;
    procedure OpenProject(const APath: string);
    procedure CloseProject;
    procedure SetProjectType(const AType: string);
    function DeepSpecPath: string;
    property ProjectPath: string read FProjectPath;
    property ProjectName: string read FProjectName;
    property ProjectType: string read FProjectType;
    property IsOpen: Boolean read FIsOpen;
  end;

implementation

uses
  System.IOUtils;

constructor TDeepSpecProjectService.Create;
begin
  inherited Create;
  FIsOpen := False;
end;

procedure TDeepSpecProjectService.OpenProject(const APath: string);
begin
  if not TDirectory.Exists(APath) then
    raise Exception.CreateFmt('Project path does not exist: %s', [APath]);

  FProjectPath := APath;
  FProjectName := TPath.GetFileName(APath);
  FProjectType := 'unknown';
  FIsOpen := True;
end;

procedure TDeepSpecProjectService.CloseProject;
begin
  FProjectPath := '';
  FProjectName := '';
  FProjectType := '';
  FIsOpen := False;
end;

procedure TDeepSpecProjectService.SetProjectType(const AType: string);
begin
  FProjectType := AType;
end;

function TDeepSpecProjectService.DeepSpecPath: string;
begin
  Result := TPath.Combine(FProjectPath, '.deepspec');
end;

end.
