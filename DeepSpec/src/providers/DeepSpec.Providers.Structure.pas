{ ============================================================================
  DeepSpec.Providers.Structure

  Structure provider for the left tool window tree.
  Shows file classification tree and three requirement trees.
  ============================================================================ }

unit DeepSpec.Providers.Structure;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepBase.VCL.DeepShell.Intf,
  DeepBase.VCL.DeepShell.Types;

type
  TDeepSpecStructureProvider = class(TInterfacedObject, IShellStructureProvider)
  public
    function ProviderId: string;
    function GetTreeNames: TArray<string>;
    function GetRootNodes(const ATreeName: string): TArray<TShellObjectRef>;
    function HasChildren(const ANode: TShellObjectRef): Boolean;
    function GetChildren(const ANode: TShellObjectRef): TArray<TShellObjectRef>;
    function GetDisplayText(const ANode: TShellObjectRef): string;
  end;

implementation

function TDeepSpecStructureProvider.ProviderId: string;
begin
  Result := 'deepspec.structure';
end;

function TDeepSpecStructureProvider.GetTreeNames: TArray<string>;
begin
  Result := ['Files', 'Function Tree', 'Module Tree', 'View Tree'];
end;

function TDeepSpecStructureProvider.GetRootNodes(const ATreeName: string): TArray<TShellObjectRef>;
begin
  // P0: fake roots for demonstration
  if ATreeName = 'Files' then
  begin
    SetLength(Result, 1);
    Result[0] := TShellObjectRef.Make('root-files', 'folder', ProviderId, '(no project open)');
  end
  else if ATreeName = 'Function Tree' then
  begin
    SetLength(Result, 1);
    Result[0] := TShellObjectRef.Make('func-root', 'capability', ProviderId, '(scan to populate)');
  end
  else
    Result := [];
end;

function TDeepSpecStructureProvider.HasChildren(const ANode: TShellObjectRef): Boolean;
begin
  // P0: no real children yet
  Result := False;
end;

function TDeepSpecStructureProvider.GetChildren(const ANode: TShellObjectRef): TArray<TShellObjectRef>;
begin
  Result := [];
end;

function TDeepSpecStructureProvider.GetDisplayText(const ANode: TShellObjectRef): string;
begin
  Result := ANode.DisplayName;
end;

end.
