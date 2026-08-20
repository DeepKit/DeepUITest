unit ArtifactOS.Tests.QualityGate;

interface

uses
  DUnitX.TestFramework,
  ArtifactOS.Services.QualityGate,
  ArtifactOS.Services.PackageBuilder,
  ArtifactOS.Core.DB.Connection;

type
  [TestFixture]
  TQualityGateTests = class
  public
    [Test]
    procedure ESGate_RejectsShortBody;
    [Test]
    procedure ESGate_PassesValidContent;
    [Test]
    procedure StructureGate_RequiresActiveCaseChain;
    [Test]
    procedure QualitySnapshot_SealPreventsModification;
    [Test]
    procedure PackageBuilder_RejectsUnqualifiedSnapshot;
  end;

implementation

uses
  System.SysUtils,
  ArtifactOS.Core.EndToEnd;

// BuildArtifact creates a valid artifact with FK chain via E2E, returns (ArtifactId, SnapId, VerId).
procedure EnsureArtifactWithChain(out ArtId, SnapId, VerId: string);
var
  CaseId, StudioId, PkgId, ChainSuffix: string;
begin
  // Use a unique chain suffix to avoid studio_code unique constraint violations
  ChainSuffix := IntToStr(Random(MaxInt));
  // Override the chain suffix in E2E — E2E uses Random internally so we're fine
  TArtifactOSEndToEnd.RunCreateChain(CaseId, StudioId, ArtId, SnapId, PkgId);
  ArtifactOS_DB.Connect;
  try
    VerId := ArtifactOS_DB.ExecuteScalar(
      'SELECT id::text FROM artifactos.artifact_version WHERE artifact_id=''' + ArtId + ''' AND version_no=1');
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

procedure TQualityGateTests.ESGate_RejectsShortBody;
var ArtId: string;
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      ArtId := ArtifactOS_DB.InsertAndReturnId(
        'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status) ' +
        'VALUES (NULL, NULL, NULL, ''Short Test'', ''drafting'') RETURNING id');

      var R := TQualityGateService.RunESGate(ArtId, '{}');
      Assert.IsFalse(R.Passed, 'Short body should fail ES gate');
      Assert.AreEqual('FAIL', R.GateStatus);

      ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact WHERE id=''' + ArtId + '''');
      ArtifactOS_DB.Connection.Commit;
    except
      ArtifactOS_DB.Connection.Rollback;
      raise;
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

procedure TQualityGateTests.ESGate_PassesValidContent;
var
  ArtId: string;
begin
  // Create artifact+version outside any transaction so RunESGate sees them
  ArtifactOS_DB.Connect;
  ArtId := ArtifactOS_DB.InsertAndReturnId(
    'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status) ' +
    'VALUES (NULL, NULL, NULL, ''Valid Title'', ''drafting'') RETURNING id');

  ArtifactOS_DB.Execute(
    'INSERT INTO artifactos.artifact_version (artifact_id, version_no, assembled_payload, seal_status) ' +
    'VALUES (''' + ArtId + ''', 1, ''{"title":"Valid Title","body":"' +
    'Paragraph one with substantial content.\n' +
    'Paragraph two with more content here.\n' +
    'Paragraph three ensuring we pass ES-02.\n' +
    'Paragraph four for extra word count padding."}'', ''sealed'')');

  var R := TQualityGateService.RunESGate(ArtId, '{}');
  Assert.IsTrue(R.Passed, 'Valid content should pass ES gate');

  // Clean up — must reconnect because RunESGate called Disconnect
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact_version WHERE artifact_id=''' + ArtId + '''');
    ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact WHERE id=''' + ArtId + '''');
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

procedure TQualityGateTests.StructureGate_RequiresActiveCaseChain;
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      var ArtId := ArtifactOS_DB.InsertAndReturnId(
        'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status) ' +
        'VALUES (NULL, NULL, NULL, ''Orphan Artifact'', ''drafting'') RETURNING id');

      var R := TQualityGateService.RunStructureGate(ArtId);
      Assert.IsFalse(R.Passed, 'Orphan artifact should fail structure gate');
      Assert.AreEqual('FREEZE', R.GateStatus);

      ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact WHERE id=''' + ArtId + '''');
      ArtifactOS_DB.Connection.Commit;
    except
      ArtifactOS_DB.Connection.Rollback;
      raise;
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

procedure TQualityGateTests.QualitySnapshot_SealPreventsModification;
var ArtId, SnapId, VerId: string;
begin
  EnsureArtifactWithChain(ArtId, SnapId, VerId);
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      TQualityGateService.SealSnapshot(SnapId);

      var Caught := False;
      try
        ArtifactOS_DB.Execute('UPDATE artifactos.quality_snapshot SET qualified_status=''not_qualified'' WHERE id=''' + SnapId + '''');
        ArtifactOS_DB.Connection.Commit;
      except
        Caught := True;
        ArtifactOS_DB.Connection.Rollback;
      end;
      Assert.IsTrue(Caught, 'Sealed snapshot must reject modification');

      ArtifactOS_DB.Connection.Commit;
    except
      ArtifactOS_DB.Connection.Rollback;
      raise;
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

procedure TQualityGateTests.PackageBuilder_RejectsUnqualifiedSnapshot;
var ArtId, SnapId, VerId: string;
begin
  EnsureArtifactWithChain(ArtId, SnapId, VerId);
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      var UnqualId := ArtifactOS_DB.InsertAndReturnId(
        'INSERT INTO artifactos.quality_snapshot (artifact_id, artifact_version_id, qualified_status, publish_readiness, purpose_fit_status, seal_candidate) ' +
        'VALUES (''' + ArtId + ''', ''' + VerId + ''', ''not_qualified'', ''not_ready'', ''fail'', false) RETURNING id');

      var Caught := False;
      try
        TPackageBuilder.BuildPackage(ArtId, VerId, UnqualId, 'zhihu', 'test');
      except
        Caught := True;
        ArtifactOS_DB.Connection.Rollback;
      end;
      Assert.IsTrue(Caught, 'PackageBuilder must reject unqualified snapshots');

      ArtifactOS_DB.Execute('DELETE FROM artifactos.quality_snapshot WHERE id=''' + UnqualId + '''');
      ArtifactOS_DB.Connection.Commit;
    except
      ArtifactOS_DB.Connection.Rollback;
      raise;
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TQualityGateTests);
end.
