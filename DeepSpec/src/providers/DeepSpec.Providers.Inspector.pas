{ ============================================================================
  DeepSpec.Providers.Inspector

  Inspector provider - shows properties of the selected node in the
  right tool window.
  ============================================================================ }

unit DeepSpec.Providers.Inspector;

interface

uses
  System.SysUtils,
  DeepBase.VCL.DeepShell.Intf,
  DeepBase.VCL.DeepShell.Types;

type
  TDeepSpecInspectorProvider = class(TInterfacedObject, IShellInspectorProvider)
  public
    function ProviderId: string;
    function CanInspect(const ARef: TShellObjectRef): Boolean;
    function GetProperties(const ARef: TShellObjectRef): TArray<TShellProperty>;
    function GetRelations(const ARef: TShellObjectRef): TArray<TShellRelation>;
    function GetIssues(const ARef: TShellObjectRef): TArray<TShellIssue>;
  end;

implementation

function TDeepSpecInspectorProvider.ProviderId: string;
begin
  Result := 'deepspec.inspector';
end;

function TDeepSpecInspectorProvider.CanInspect(const ARef: TShellObjectRef): Boolean;
begin
  Result := True;
end;

function TDeepSpecInspectorProvider.GetProperties(const ARef: TShellObjectRef): TArray<TShellProperty>;
begin
  // P0: basic properties from the object ref itself
  SetLength(Result, 3);

  Result[0].Name := 'ID';
  Result[0].Value := ARef.Id;

  Result[1].Name := 'Kind';
  Result[1].Value := ARef.Kind;

  Result[2].Name := 'Status';
  Result[2].Value := 'candidate';
end;

function TDeepSpecInspectorProvider.GetRelations(const ARef: TShellObjectRef): TArray<TShellRelation>;
begin
  Result := [];
end;

function TDeepSpecInspectorProvider.GetIssues(const ARef: TShellObjectRef): TArray<TShellIssue>;
begin
  Result := [];
end;

end.
