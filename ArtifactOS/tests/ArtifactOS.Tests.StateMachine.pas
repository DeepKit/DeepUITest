unit ArtifactOS.Tests.StateMachine;

interface

uses
  DUnitX.TestFramework,
  ArtifactOS.Core.DB.Connection;

type
  [TestFixture]
  TStateMachineTests = class
  public
    [Test]
    procedure ValidStateCombo_Accepts_ApprovedPassedPending;

    [Test]
    procedure ValidStateCombo_Rejects_DraftingPublishedPending;

    [Test]
    procedure ShadowPackage_CannotEnterRealPublishing;

    [Test]
    procedure PublicationPackage_RequiresQualitySnapshot;

    [Test]
    procedure RunModeShadow_RealPublishGateAlwaysBlocked;
  end;

implementation

uses
  System.SysUtils;

procedure TStateMachineTests.ValidStateCombo_Accepts_ApprovedPassedPending;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      // This is a legal combo — should succeed
      DB.Execute(
        'INSERT INTO artifactos.substudio_execution_task (sub_studio_id, artifact_plan_id, artifact_id, ' +
        'pipeline_status, quality_status, publish_status) ' +
        'VALUES (NULL, NULL, NULL, ''approved'', ''passed'', ''pending'')');

      var Count := StrToInt(DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.substudio_execution_task WHERE pipeline_status=''approved'' AND quality_status=''passed'' AND publish_status=''pending'''));
      Assert.AreEqual(1, Count, 'Legal combo should be accepted');

      DB.Execute('DELETE FROM artifactos.substudio_execution_task WHERE sub_studio_id IS NULL AND artifact_plan_id IS NULL AND artifact_id IS NULL');
      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

procedure TStateMachineTests.ValidStateCombo_Rejects_DraftingPublishedPending;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      Assert.WillRaise(
        procedure
        begin
          DB.Execute(
            'INSERT INTO artifactos.substudio_execution_task (sub_studio_id, artifact_plan_id, artifact_id, ' +
            'pipeline_status, quality_status, publish_status) ' +
            'VALUES (NULL, NULL, NULL, ''drafting'', ''published'', ''pending'')');
        end,
        Exception);

      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

procedure TStateMachineTests.ShadowPackage_CannotEnterRealPublishing;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      // Insert a simulated package
      DB.Execute(
        'INSERT INTO artifactos.publication_package (idempotency_key, platform, simulation_only, run_mode, status) ' +
        'VALUES (''test_shadow_guard_'' || floor(extract(epoch from now()))::text, ''zhihu'', true, ''shadow'', ''simulated'')');

      // Try to transition it to queued — should be blocked by shadow guard
      Assert.WillRaise(
        procedure
        begin
          DB.Execute(
            'UPDATE artifactos.publication_package SET status=''queued'' WHERE run_mode=''shadow'' AND status=''simulated''');
        end,
        Exception, 'Shadow package must never enter queued');

      DB.Execute('DELETE FROM artifactos.publication_package WHERE idempotency_key LIKE ''test_shadow_guard_%''');
      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

procedure TStateMachineTests.PublicationPackage_RequiresQualitySnapshot;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      // Insert a package without quality_snapshot
      DB.Execute(
        'INSERT INTO artifactos.publication_package (idempotency_key, platform, simulation_only, run_mode, status, quality_snapshot_id) ' +
        'VALUES (''test_qs_bind_'' || floor(extract(epoch from now()))::text, ''zhihu'', true, ''shadow'', ''simulated'', NULL)');

      // Try to transition to queued without quality_snapshot
      Assert.WillRaise(
        procedure
        begin
          DB.Execute(
            'UPDATE artifactos.publication_package SET status=''queued'' WHERE quality_snapshot_id IS NULL AND status=''simulated''');
        end,
        Exception, 'Package must bind quality_snapshot before queued');

      DB.Execute('DELETE FROM artifactos.publication_package WHERE idempotency_key LIKE ''test_qs_bind_%''');
      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

procedure TStateMachineTests.RunModeShadow_RealPublishGateAlwaysBlocked;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var GateResult := DB.ExecuteScalar('SELECT gate_status::text FROM artifactos.check_real_publish_gate()');
    Assert.AreEqual('blocked', GateResult, 'RealPublishGate must always be blocked in Phase 1A shadow');

    var Reason := DB.ExecuteScalar('SELECT reason::text FROM artifactos.check_real_publish_gate()');
    Assert.IsTrue(Pos('Phase 1A', Reason) > 0, 'Block reason should mention Phase 1A');
  finally
    DB.Disconnect;
  end;
end;

initialization

end.