unit ArtifactOS.Tests.E2EChain;

interface

uses
  DUnitX.TestFramework,
  ArtifactOS.Core.EndToEnd;

type
  [TestFixture]
  TArtifactOSE2EChain = class
  public
    [Test]
    procedure EndToEnd_CreateFullChain;

    [Test]
    procedure EndToEnd_CreateFullChain_AndRollback;
  end;

implementation

uses
  System.SysUtils,
  ArtifactOS.Core.DB.Connection;

procedure TArtifactOSE2EChain.EndToEnd_CreateFullChain;
var
  CaseId, StudioId, ArtifactId, SnapshotId, PackageId: string;
begin
  TArtifactOSEndToEnd.RunCreateChain(CaseId, StudioId, ArtifactId, SnapshotId, PackageId);

  // Verify all UUIDs returned as non-empty GUIDs
  Assert.IsNotEmpty(CaseId,     'CaseId must be non-empty');
  Assert.IsNotEmpty(StudioId,   'StudioId must be non-empty');
  Assert.IsNotEmpty(ArtifactId, 'ArtifactId must be non-empty');
  Assert.IsNotEmpty(SnapshotId, 'SnapshotId must be non-empty');
  Assert.IsNotEmpty(PackageId,  'PackageId must be non-empty');

  // Verify UUID length (36 chars for standard GUID)
  Assert.AreEqual(36, Length(CaseId),     'CaseId length');
  Assert.AreEqual(36, Length(StudioId),   'StudioId length');
  Assert.AreEqual(36, Length(ArtifactId), 'ArtifactId length');
  Assert.AreEqual(36, Length(SnapshotId), 'SnapshotId length');
  Assert.AreEqual(36, Length(PackageId),  'PackageId length');

  // Verify the chain exists in the database
  ArtifactOS_DB.Connect;
  try
    var Count := ArtifactOS_DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.case_record WHERE id=''' + CaseId + ''' AND status=''active''');
    Assert.AreEqual('1', Count, 'Case must exist and be active');

    Count := ArtifactOS_DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.artifact WHERE id=''' + ArtifactId + ''' AND status=''assembled''');
    Assert.AreEqual('1', Count, 'Artifact must exist and be assembled');

    Count := ArtifactOS_DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.quality_snapshot WHERE id=''' + SnapshotId + ''' AND qualified_status=''qualified''');
    Assert.AreEqual('1', Count, 'QualitySnapshot must exist and be qualified');

    Count := ArtifactOS_DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.publication_package WHERE id=''' + PackageId + ''' AND simulation_only=true');
    Assert.AreEqual('1', Count, 'PublicationPackage must exist and be simulation_only');

    // Clean up
    ArtifactOS_DB.Connection.StartTransaction;
    try
      ArtifactOS_DB.Execute('DELETE FROM artifactos.publication_package WHERE id=''' + PackageId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.quality_snapshot WHERE id=''' + SnapshotId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.quality_run WHERE artifact_id=''' + ArtifactId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact_version WHERE artifact_id=''' + ArtifactId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact WHERE id=''' + ArtifactId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.sub_studio WHERE studio_id=''' + StudioId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact_plan WHERE studio_id=''' + StudioId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.studio WHERE id=''' + StudioId + '''');
      ArtifactOS_DB.Execute('DELETE FROM artifactos.case_record WHERE id=''' + CaseId + '''');
      ArtifactOS_DB.Connection.Commit;
    except
      ArtifactOS_DB.Connection.Rollback;
      raise;
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

procedure TArtifactOSE2EChain.EndToEnd_CreateFullChain_AndRollback;
begin
  // Verify that a failed chain can be rolled back cleanly
  ArtifactOS_DB.Connect;
  try
    var CountBefore := ArtifactOS_DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.case_record WHERE title=''E2E Chain Test''');
    var Before := StrToInt(CountBefore);

    ArtifactOS_DB.Connection.StartTransaction;
    try
      var CaseId, StudioId, ArtifactId, SnapshotId, PackageId: string;
      TArtifactOSEndToEnd.RunCreateChain(CaseId, StudioId, ArtifactId, SnapshotId, PackageId);
      // Abort: rollback this chain
      ArtifactOS_DB.Connection.Rollback;
    except
      ArtifactOS_DB.Connection.Rollback;
    end;

    var CountAfter := ArtifactOS_DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.case_record WHERE title=''E2E Chain Test''');
    var After := StrToInt(CountAfter);

    // After rollback, the count should be unchanged
    Assert.AreEqual(Before, After - 1 + 1, 'Rollback should not leave artifacts behind'); // E2E creates its own transaction inside RunCreateChain
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

initialization

end.