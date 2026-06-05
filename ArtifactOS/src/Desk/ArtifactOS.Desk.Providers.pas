{ ============================================================================
  ArtifactOS.Desk.Providers

  Shell providers for ArtifactOS Desk.
  Phase 1: fake providers that populate the shell with placeholder content.
  Real data binding follows in Phase 2.

  Updated: 2026-06-04 — aligned with DeepBase.VCL.DeepShell current API
    (TShellObjectRef.Kind/Id, IShellStructureProvider methods, etc.)
  ============================================================================ }

unit ArtifactOS.Desk.Providers;

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  DeepBase.VCL.DeepShell,
  DeepBase.VCL.DeepShell.Types;

type
  { Structure tree: Case > Studio > SubStudio > Artifact }
  TDeskStructureProvider = class(TInterfacedObject, IShellStructureProvider)
  public
    function ProviderId: string;
    function GetTreeNames: TArray<string>;
    function GetRootNodes(const ATreeName: string): TArray<TShellObjectRef>;
    function HasChildren(const ANode: TShellObjectRef): Boolean;
    function GetChildren(const ANode: TShellObjectRef): TArray<TShellObjectRef>;
    function GetDisplayText(const ANode: TShellObjectRef): string;
  end;

  { Main view: shows content for the selected object }
  TDeskMainViewProvider = class(TInterfacedObject, IShellMainViewProvider)
  public
    function ProviderId: string;
    function CanOpen(const ARef: TShellObjectRef): Boolean;
    function GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
    function CreateViewControl(AOwner: TComponent;
      const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
  end;

  { Inspector: shows properties of the selected object }
  TDeskInspectorProvider = class(TInterfacedObject, IShellInspectorProvider)
  public
    function ProviderId: string;
    function CanInspect(const ARef: TShellObjectRef): Boolean;
    function GetProperties(const ARef: TShellObjectRef): TArray<TShellProperty>;
    function GetRelations(const ARef: TShellObjectRef): TArray<TShellRelation>;
    function GetIssues(const ARef: TShellObjectRef): TArray<TShellIssue>;
  end;

  { Settings page: ArtifactOS connection settings }
  TDeskSettingsPageProvider = class(TInterfacedObject, ISettingsPageProvider)
  public
    function PageId: string;
    function Caption: string;
    function GroupName: string;
    function CreatePage(AOwner: TComponent): TControl;
    procedure Apply;
    procedure Cancel;
    procedure RestoreDefaults;
  end;

implementation

uses
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Desk.EvolutionConsole,
  ArtifactOS.Desk.AutoTuneAudit;

{ TDeskStructureProvider }

function TDeskStructureProvider.ProviderId: string;
begin
  Result := 'artifactos';
end;

function TDeskStructureProvider.GetTreeNames: TArray<string>;
begin
  SetLength(Result, 1);
  Result[0] := 'ArtifactOS';
end;

function TDeskStructureProvider.GetRootNodes(const ATreeName: string): TArray<TShellObjectRef>;
begin
  // Five root nodes: Cases, Packages, Contracts, Evolution Console, AutoTune Audit
  SetLength(Result, 5);
  Result[0] := TShellObjectRef.Make('', 'case_folder', ProviderId, 'Cases');
  Result[1] := TShellObjectRef.Make('', 'package_folder', ProviderId, 'Publication Packages');
  Result[2] := TShellObjectRef.Make('', 'contract_folder', ProviderId, 'Contracts');
  Result[3] := TShellObjectRef.Make('evolution', 'view', ProviderId, 'Evolution Console');
  Result[4] := TShellObjectRef.Make('autotune_audit', 'view', ProviderId, 'AutoTune Audit');
end;

function TDeskStructureProvider.HasChildren(const ANode: TShellObjectRef): Boolean;
begin
  Result := (ANode.Kind = 'case_folder') or (ANode.Kind = 'package_folder') or
    (ANode.Kind = 'contract_folder');
  // 'view' nodes (Evolution Console, AutoTune Audit) have no children
end;

function TDeskStructureProvider.GetChildren(const ANode: TShellObjectRef): TArray<TShellObjectRef>;
var
  List: TArray<TShellObjectRef>;
begin
  SetLength(Result, 0);

  if not ((ANode.Kind = 'case_folder') or (ANode.Kind = 'package_folder') or
    (ANode.Kind = 'contract_folder')) then
    Exit;

  try
    ArtifactOS_DB.Connect;
    try
      if ANode.Kind = 'case_folder' then
      begin
        var Q := ArtifactOS_DB.Query(
          'SELECT id::text, title, status FROM artifactos.case_record ' +
          'WHERE status=''active'' ORDER BY created_at DESC LIMIT 20');
        try
          while not Q.Eof do
          begin
            SetLength(List, Length(List) + 1);
            List[High(List)] := TShellObjectRef.Make(
              Q.FieldByName('id').AsString, 'case', ProviderId,
              Q.FieldByName('title').AsString);
            Q.Next;
          end;
        finally
          Q.Free;
        end;
      end
      else if ANode.Kind = 'package_folder' then
      begin
        var Q := ArtifactOS_DB.Query(
          'SELECT id::text, platform, status FROM artifactos.publication_package ' +
          'WHERE status IN (''draft'', ''preflight'', ''queued'', ''submitting'') ' +
          'ORDER BY created_at DESC LIMIT 20');
        try
          while not Q.Eof do
          begin
            SetLength(List, Length(List) + 1);
            List[High(List)] := TShellObjectRef.Make(
              Q.FieldByName('id').AsString, 'package', ProviderId,
              Q.FieldByName('platform').AsString + ' / ' + Q.FieldByName('status').AsString);
            Q.Next;
          end;
        finally
          Q.Free;
        end;
      end
      else if ANode.Kind = 'contract_folder' then
      begin
        var Q := ArtifactOS_DB.Query(
          'SELECT id::text, contract_type, contract_status FROM artifactos.artifact_contract ' +
          'ORDER BY created_at DESC LIMIT 20');
        try
          while not Q.Eof do
          begin
            SetLength(List, Length(List) + 1);
            List[High(List)] := TShellObjectRef.Make(
              Q.FieldByName('id').AsString, 'contract', ProviderId,
              Q.FieldByName('contract_type').AsString + ' / ' + Q.FieldByName('contract_status').AsString);
            Q.Next;
          end;
        finally
          Q.Free;
        end;
      end;

      Result := List;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    // DB not available — return empty
  end;
end;

function TDeskStructureProvider.GetDisplayText(const ANode: TShellObjectRef): string;
begin
  Result := ANode.DisplayName;
end;

{ TDeskMainViewProvider }

function TDeskMainViewProvider.ProviderId: string;
begin
  Result := 'artifactos';
end;

function TDeskMainViewProvider.CanOpen(const ARef: TShellObjectRef): Boolean;
begin
  Result := (ARef.Kind = 'desk') or (ARef.Kind = 'case') or
    (ARef.Kind = 'package') or (ARef.Kind = 'contract') or
    (ARef.Kind = 'case_folder') or (ARef.Kind = 'package_folder') or
    (ARef.Kind = 'contract_folder') or (ARef.Kind = 'view');
end;

function TDeskMainViewProvider.GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
begin
  Result.ViewKind := svkControl;
  Result.ViewId := ARef.Kind + '_' + ARef.Id;
  Result.Title := ARef.DisplayName;
end;

function TDeskMainViewProvider.CreateViewControl(AOwner: TComponent;
  const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
var
  Panel: TPanel;
  Title, Sub: TLabel;
begin
  // Route 'view' nodes to specialized providers
  if ARef.Kind = 'view' then
  begin
    if ARef.Id = 'evolution' then
    begin
      Result := TEvolutionConsoleFrame.Create(AOwner);
      (Result as TEvolutionConsoleFrame).Parent := TWinControl(AOwner);
      Exit;
    end;
    if ARef.Id = 'autotune_audit' then
    begin
      Result := TAutoTuneAuditFrame.Create(AOwner);
      (Result as TAutoTuneAuditFrame).Parent := TWinControl(AOwner);
      Exit;
    end;
  end;

  Panel := TPanel.Create(AOwner);
  Panel.Align := alClient;
  Panel.BevelOuter := bvNone;
  Panel.Padding.SetBounds(16, 16, 16, 16);

  Title := TLabel.Create(Panel);
  Title.Parent := Panel;
  Title.Align := alTop;
  Title.Font.Size := 14;
  Title.Font.Style := [fsBold];

  Sub := TLabel.Create(Panel);
  Sub.Parent := Panel;
  Sub.Align := alTop;
  Sub.Top := 30;
  Sub.Font.Size := 10;

  if (ARef.Kind = 'desk') or (ARef.Kind = 'case_folder') or
    (ARef.Kind = 'package_folder') or (ARef.Kind = 'contract_folder') then
  begin
    Title.Caption := 'ArtifactOS Today';
    Sub.Caption := 'Your daily work desk. Active cases, pending reviews, publication status.';
  end
  else if ARef.Kind = 'case' then
  begin
    Title.Caption := 'Case: ' + ARef.DisplayName;
    Sub.Caption := 'Case details and artifact overview. (Phase 1: placeholder view)';
  end
  else if ARef.Kind = 'package' then
  begin
    Title.Caption := 'Package: ' + ARef.DisplayName;
    Sub.Caption := 'Publication package details, quality evidence, verify status. (Phase 1: placeholder view)';
  end
  else if ARef.Kind = 'contract' then
  begin
    Title.Caption := 'Contract: ' + ARef.DisplayName;
    Sub.Caption := 'Contract pipeline status, requirement frame, content spec. (Phase 1: placeholder view)';
  end;

  Result := Panel;
end;

{ TDeskInspectorProvider }

function TDeskInspectorProvider.ProviderId: string;
begin
  Result := 'artifactos';
end;

function TDeskInspectorProvider.CanInspect(const ARef: TShellObjectRef): Boolean;
begin
  Result := (ARef.Kind = 'case') or (ARef.Kind = 'package') or (ARef.Kind = 'contract');
end;

function TDeskInspectorProvider.GetProperties(const ARef: TShellObjectRef): TArray<TShellProperty>;
var
  List: TArray<TShellProperty>;

  procedure AddProp(const AName, AValue, AGroup: string);
  begin
    SetLength(List, Length(List) + 1);
    List[High(List)].Name := AName;
    List[High(List)].Value := AValue;
    List[High(List)].Group := AGroup;
    List[High(List)].ReadOnly := True;
  end;

begin
  AddProp('Type', ARef.Kind, 'Object type');
  AddProp('ID', ARef.Id, 'Unique identifier');
  AddProp('Name', ARef.DisplayName, 'Display name');

  // Phase 1: add basic DB properties if connected
  try
    ArtifactOS_DB.Connect;
    try
      if ARef.Kind = 'case' then
      begin
        var Status := ArtifactOS_DB.ExecuteScalar(
          'SELECT status FROM artifactos.case_record WHERE id=''' + ARef.Id + '''');
        AddProp('Status', Status, 'Case status');
      end
      else if ARef.Kind = 'package' then
      begin
        var Status := ArtifactOS_DB.ExecuteScalar(
          'SELECT status FROM artifactos.publication_package WHERE id=''' + ARef.Id + '''');
        AddProp('Status', Status, 'Package status');
      end
      else if ARef.Kind = 'contract' then
      begin
        var Status := ArtifactOS_DB.ExecuteScalar(
          'SELECT contract_status FROM artifactos.artifact_contract WHERE id=''' + ARef.Id + '''');
        AddProp('Status', Status, 'Contract status');
      end;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    // Inspector stays with basic properties only
  end;

  Result := List;
end;

function TDeskInspectorProvider.GetRelations(const ARef: TShellObjectRef): TArray<TShellRelation>;
begin
  SetLength(Result, 0);
end;

function TDeskInspectorProvider.GetIssues(const ARef: TShellObjectRef): TArray<TShellIssue>;
begin
  SetLength(Result, 0);
end;

{ TDeskSettingsPageProvider }

function TDeskSettingsPageProvider.PageId: string;
begin
  Result := 'artifactos_connection';
end;

function TDeskSettingsPageProvider.Caption: string;
begin
  Result := 'ArtifactOS';
end;

function TDeskSettingsPageProvider.GroupName: string;
begin
  Result := 'Database';
end;

function TDeskSettingsPageProvider.CreatePage(AOwner: TComponent): TControl;
var
  Panel: TPanel;
  Label1, Label2: TLabel;
  Edit1: TEdit;
begin
  Panel := TPanel.Create(AOwner);
  Panel.Align := alClient;
  Panel.BevelOuter := bvNone;
  Panel.Padding.SetBounds(12, 12, 12, 12);

  Label1 := TLabel.Create(Panel);
  Label1.Parent := Panel;
  Label1.Align := alTop;
  Label1.Caption := 'PostgreSQL Connection';
  Label1.Font.Style := [fsBold];

  Label2 := TLabel.Create(Panel);
  Label2.Parent := Panel;
  Label2.Align := alTop;
  Label2.Top := 24;
  Label2.Caption := 'Database name (default: artifactos_test):';

  Edit1 := TEdit.Create(Panel);
  Edit1.Parent := Panel;
  Edit1.Align := alTop;
  Edit1.Top := 44;
  Edit1.Text := 'artifactos_test';

  Result := Panel;
end;

procedure TDeskSettingsPageProvider.Apply;
begin
  // Phase 1: no-op, settings are read from env vars
end;

procedure TDeskSettingsPageProvider.Cancel;
begin
  // Phase 1: no-op
end;

procedure TDeskSettingsPageProvider.RestoreDefaults;
begin
  // Phase 1: no-op
end;

end.
