unit ArtifactOS.Services.PackageBuilder;

interface

uses
  System.SysUtils,
  ArtifactOS.Core.DB.Connection;

type
  TPackageBuilder = class
  public
    class function BuildPackage(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
      const APlatform, AAccountId: string): string;
    class function MarkSimulated(const APackageId: string): string;
    class function MarkHeld(const APackageId: string; const AReason: string): string;
    class function GetPackageStatus(const APackageId: string): string;
  end;

implementation

uses
  FireDAC.Comp.Client, System.DateUtils;

function InsertId(const DB: TArtifactDB; const SQL: string): string;
var
  Q: TFDQuery;
begin
  Q := DB.Query(SQL);
  try
    Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

class function TPackageBuilder.BuildPackage(const AArtifactId, AArtifactVersionId, ASnapshotId: string;
  const APlatform, AAccountId: string): string;
var
  DB: TArtifactDB;
  IdemKey: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Verify snapshot is qualified before building
    var SnapshotStatus := DB.ExecuteScalar(
      'SELECT qualified_status FROM artifactos.quality_snapshot WHERE id=''' + ASnapshotId + '''');

    if SnapshotStatus <> 'qualified' then
      raise Exception.Create('Cannot build package: quality_snapshot is not qualified (status=' + SnapshotStatus + ')');

    // Generate idempotent key
    IdemKey := 'pkg_' + AArtifactId + '_' + APlatform + '_' + IntToStr(DateTimeToUnix(Now));

    // Build package
    Result := InsertId(DB,
      'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, ' +
      'platform, account_id, idempotency_key, simulation_only, run_mode, status) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + ASnapshotId + ''', ' +
      '''' + APlatform + ''', ''' + AAccountId + ''', ''' + IdemKey + ''', true, ''shadow'', ''simulated'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TPackageBuilder.MarkSimulated(const APackageId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute('UPDATE artifactos.publication_package SET status=''simulated'', simulation_only=true WHERE id=''' + APackageId + ''' AND simulation_only=true');
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
    DB.Execute('UPDATE artifactos.publication_package SET status=''held'', metadata=jsonb_set(metadata, ''{hold_reason}'', ''"' + AReason + '"'') WHERE id=''' + APackageId + '''');
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
    Result := DB.ExecuteScalar('SELECT status FROM artifactos.publication_package WHERE id=''' + APackageId + '''');
  finally
    DB.Disconnect;
  end;
end;

end.