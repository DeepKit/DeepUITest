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
  System.SysUtils, System.DateUtils;

procedure TQualityGateTests.ESGate_RejectsShortBody;
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      // Create minimal artifact with short body
      var Q := ArtifactOS_DB.Query(
        'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status) ' +
        'VALUES (NULL, NULL, NULL, ''Short Test'', ''drafting'') RETURNING id');
      var ArtId := Q.Fields[0].AsString;
      Q.Free;

      var Result := TQualityGateService.RunESGate(ArtId, '{}');

      Assert.IsFalse(Result.Passed, 'Short body should fail ES gate');
      Assert.AreEqual('FAIL', Result.GateStatus);

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
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      // Create full-chain artifact with valid content
      var Q := ArtifactOS_DB.Query(
        'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status) ' +
        'VALUES (NULL, NULL, NULL, ''Valid Title'', ''drafting'') RETURNING id');
      var ArtId := Q.Fields[0].AsString;
      Q.Free;

      // Create a sealed version with long body
      ArtifactOS_DB.Execute(
        'INSERT INTO artifactos.artifact_version (artifact_id, version_no, assembled_payload, seal_status) ' +
        'VALUES (''' + ArtId + ''', 1, ''{"title":"Valid Title","body":"' +
        'This is a substantial body of text that should pass the ES gate. ' +
        'It contains multiple sentences with adequate length to satisfy the ' +
        'minimum requirements. The argument is developed across several ' +
        'coherent paragraphs. This ensures the word count check passes. ' +
        'Additional sentences here to make sure we have enough content. ' +
        'And even more words to pad the length beyond 50 characters. ' +
        'This should be more than sufficient for the gate to pass. ' +
        'In fact, this paragraph alone is well over fifty characters. ' +
        'The ES gate checks for minimum thresholds and this content exceeds them."}'', ''sealed'')');

      var Result := TQualityGateService.RunESGate(ArtId, '{}');
      Assert.IsTrue(Result.Passed, 'Valid content should pass ES gate: ' + string.Join(', ', Result.Issues));

      ArtifactOS_DB.Execute('DELETE FROM artifactos.artifact_version WHERE artifact_id=''' + ArtId + '''');
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

procedure TQualityGateTests.StructureGate_RequiresActiveCaseChain;
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      // Create artifact without case chain
      var Q := ArtifactOS_DB.Query(
        'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status) ' +
        'VALUES (NULL, NULL, NULL, ''Orphan Artifact'', ''drafting'') RETURNING id');
      var ArtId := Q.Fields[0].AsString;
      Q.Free;

      var Result := TQualityGateService.RunStructureGate(ArtId);
      Assert.IsFalse(Result.Passed, 'Orphan artifact should fail structure gate');
      Assert.AreEqual('FREEZE', Result.GateStatus, 'Should freeze orphan artifacts');

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
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      var SnapId := TQualityGateService.CreateQualitySnapshot(
        (ArtifactOS_DB.ExecuteScalar('SELECT id::text FROM artifactos.artifact LIMIT 1')), '', True);
      TQualityGateService.SealSnapshot(SnapId);

      // Attempt to modify a sealed snapshot
      Assert.WillRaise(
        procedure
        begin
          ArtifactOS_DB.Execute('UPDATE artifactos.quality_snapshot SET qualified_status=''not_qualified'' WHERE id=''' + SnapId + '''');
        end,
        Exception, 'Sealed quality_snapshot must reject modification');

      ArtifactOS_DB.Execute('DELETE FROM artifactos.quality_snapshot WHERE id=''' + SnapId + '''');
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
begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      // Create a not_qualified snapshot
      var SnapId := TQualityGateService.CreateQualitySnapshot(
        (ArtifactOS_DB.ExecuteScalar('SELECT id::text FROM artifactos.artifact LIMIT 1')), '', False);

      Assert.WillRaise(
        procedure
        begin
          TPackageBuilder.BuildPackage(
            ArtifactOS_DB.ExecuteScalar('SELECT id::text FROM artifactos.artifact LIMIT 1'), '', SnapId, 'zhihu', 'test');
        end,
        Exception, 'PackageBuilder must reject unqualified snapshots');

      ArtifactOS_DB.Execute('DELETE FROM artifactos.quality_snapshot WHERE id=''' + SnapId + '''');
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

end.