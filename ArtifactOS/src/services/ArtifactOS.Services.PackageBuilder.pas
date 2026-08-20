unit ArtifactOS.Services.PackageBuilder;

interface

uses
  System.SysUtils, FireDAC.Comp.Client,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.PlatformAdapter;

type
  TPackageBuilder = class
  public
    // Multi-platform build: validates content against platform adapter
    class function BuildPackage(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
      const APlatform, AAccountId: string): string;

    // Low-level: direct connection (used by ChainRunner in transactions)
    class function BuildPackageOnConn(AConn: TFDConnection; const AArtifactId, AArtifactVersionId, ASnapshotId: string;
      const APlatform, AAccountId: string): string;

    // Build a real (non-simulation) publication package for auto-publish
    class function BuildRealPackage(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
      const APlatform, AAccountId: string): string;

    // Multi-platform convenience: build for all registered platforms
    class function BuildForAllPlatforms(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
      out APackages: TArray<string>): Boolean;

    // Package lifecycle
    class function MarkSimulated(const APackageId: string): string;
    class function MarkHeld(const APackageId: string; const AReason: string): string;
    class function GetPackageStatus(const APackageId: string): string;
  end;

implementation

uses
  System.DateUtils, System.Generics.Collections;

function InsertAndReturnId(const SQL: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnId(SQL);
end;

class function TPackageBuilder.BuildPackage(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
  const APlatform, AAccountId: string): string;
var
  DB: TArtifactDB;
  IdemKey: string;
begin
  // Validate platform adapter exists
  var Adapter := TPlatformAdapterRegistry.Get(APlatform);
  if Adapter = nil then
    raise Exception.CreateFmt('Unknown platform: %s. Available: %s',
      [APlatform, string.Join(', ', TPlatformAdapterRegistry.GetPlatformIds)]);

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var SnapshotStatus := DB.ExecuteScalar(
      'SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=''' + ASnapshotId + '''');
    if SnapshotStatus <> 'qualified' then
      raise Exception.Create('Cannot build package: quality_snapshot is not qualified (status=' + SnapshotStatus + ')');

    // Use adapter to generate idempotency key
    IdemKey := Adapter.MakeIdempotencyKey(AArtifactId);

    Result := DB.InsertAndReturnId(
      'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, ' +
      'platform, account_id, idempotency_key, simulation_only, run_mode, status) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + ASnapshotId + ''', ' +
      '''' + APlatform + ''', ''' + AAccountId + ''', ''' + IdemKey + ''', true, ''shadow'', ''simulated'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TPackageBuilder.BuildPackageOnConn(AConn: TFDConnection; const AArtifactId, AArtifactVersionId, ASnapshotId: string;
  const APlatform, AAccountId: string): string;
var
  IdemKey: string;
begin
  with TFDQuery.Create(nil) do
  try
    Connection := AConn;
    SQL.Text := 'SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=''' + ASnapshotId + '''';
    Open; var SnapshotStatus := Fields[0].AsString; Close;
    if SnapshotStatus <> 'qualified' then
      raise Exception.Create('Cannot build package: quality_snapshot is not qualified (status=' + SnapshotStatus + ')');
  finally
    Free;
  end;

  IdemKey := 'pkg_' + AArtifactId + '_' + APlatform + '_' + IntToStr(DateTimeToUnix(Now));
  with TFDQuery.Create(nil) do
  try
    Connection := AConn;
    SQL.Text := 'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, ' +
      'platform, account_id, idempotency_key, simulation_only, run_mode, status) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + ASnapshotId + ''', ' +
      '''' + APlatform + ''', ''' + AAccountId + ''', ''' + IdemKey + ''', true, ''shadow'', ''simulated'') ' +
      'RETURNING id';
    Open; Result := Fields[0].AsString; Close;
  finally
    Free;
  end;
end;

class function TPackageBuilder.BuildRealPackage(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
  const APlatform, AAccountId: string): string;
var
  DB: TArtifactDB;
  IdemKey: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var SnapshotStatus := DB.ExecuteScalar(
      'SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=''' + ASnapshotId + '''');
    if SnapshotStatus <> 'qualified' then
      raise Exception.Create('Cannot build real package: quality_snapshot is not qualified (status=' + SnapshotStatus + ')');

    IdemKey := 'pub_' + AArtifactId + '_' + APlatform + '_' + IntToStr(DateTimeToUnix(Now));
    Result := DB.InsertAndReturnId(
      'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, ' +
      'platform, account_id, idempotency_key, simulation_only, run_mode, status) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + ASnapshotId + ''', ' +
      '''' + APlatform + ''', ''' + AAccountId + ''', ''' + IdemKey + ''', false, ''auto_publish'', ''pending'') ' +
      'RETURNING id');
    WriteLn('[PackageBuilder] Real package created: id=', Result, ' platform=', APlatform, ' mode=auto_publish');
  finally
    DB.Disconnect;
  end;
end;

class function TPackageBuilder.BuildForAllPlatforms(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
  out APackages: TArray<string>): Boolean;
var
  PlatformIds: TArray<string>;
  PkgList: TList<string>;
  P: string;
begin
  PlatformIds := TPlatformAdapterRegistry.GetPlatformIds;
  PkgList := TList<string>.Create;
  try
    Result := True;
    for P in PlatformIds do
    begin
      try
        var PkgId := BuildPackage(AArtifactId, AArtifactVersionId, ASnapshotId, P, 'default');
        PkgList.Add(PkgId);
      except
        on E: Exception do
        begin
          WriteLn('[PackageBuilder] Skipped ' + P + ': ' + E.Message);
          Result := False;
        end;
      end;
    end;
    APackages := PkgList.ToArray;
  finally
    PkgList.Free;
  end;
end;

class function TPackageBuilder.MarkSimulated(const APackageId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.publication_package SET status=''simulated'', simulation_only=true WHERE id=:id AND simulation_only=true',
      '{"id":"' + APackageId + '"}');
    Result := APackageId;
  finally
    DB.Disconnect;
  end;
end;

class function TPackageBuilder.MarkHeld(const APackageId: string; const AReason: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.publication_package SET status=''held'', metadata=jsonb_set(metadata, ''{hold_reason}'', :reason::jsonb) WHERE id=:id',
      Format('{"reason":"%s","id":"%s"}', [AReason, APackageId]));
    Result := APackageId;
  finally
    DB.Disconnect;
  end;
end;

class function TPackageBuilder.GetPackageStatus(const APackageId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalarJson(
      'SELECT status FROM artifactos.publication_package WHERE id=:id',
      '{"id":"' + APackageId + '"}');
  finally
    DB.Disconnect;
  end;
end;

end.
