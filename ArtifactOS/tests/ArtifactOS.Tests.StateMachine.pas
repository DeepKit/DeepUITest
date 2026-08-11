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
      var Caught := False;
      try
        DB.Execute(
          'INSERT INTO artifactos.substudio_execution_task (sub_studio_id, artifact_plan_id, artifact_id, ' +
          'pipeline_status, quality_status, publish_status) ' +
          'VALUES (NULL, NULL, NULL, ''drafting'', ''published'', ''pending'')');
        DB.Connection.Commit;
      except
        Caught := True;
        DB.Connection.Rollback;
      end;
      Assert.IsTrue(Caught, 'Illegal combo should be rejected');
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
  IdemKey: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      IdemKey := 'test_shadow_guard_' + IntToStr(Trunc(Now * 86400));
      DB.Execute(
        'INSERT INTO artifactos.publication_package (idempotency_key, platform, simulation_only, run_mode, status) ' +
        'VALUES (''' + IdemKey + ''', ''zhihu'', true, ''shadow'', ''simulated'')');

      var Caught := False;
      try
        DB.Execute(
          'UPDATE artifactos.publication_package SET status=''queued'' WHERE run_mode=''shadow'' AND status=''simulated''');
      except
        Caught := True;
        DB.Connection.Rollback;
      end;
      Assert.IsTrue(Caught, 'Shadow package must never enter queued');

      DB.Execute('DELETE FROM artifactos.publication_package WHERE idempotency_key=''' + IdemKey + '''');
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
  IdemKey: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      IdemKey := 'test_qs_bind_' + IntToStr(Trunc(Now * 86400));
      DB.Execute(
        'INSERT INTO artifactos.publication_package (idempotency_key, platform, simulation_only, run_mode, status, quality_snapshot_id) ' +
        'VALUES (''' + IdemKey + ''', ''zhihu'', true, ''shadow'', ''simulated'', NULL)');

      var Caught := False;
      try
        DB.Execute(
          'UPDATE artifactos.publication_package SET status=''queued'' WHERE quality_snapshot_id IS NULL AND status=''simulated''');
      except
        Caught := True;
        DB.Connection.Rollback;
      end;
      Assert.IsTrue(Caught, 'Package must bind quality_snapshot before queued');

      DB.Execute('DELETE FROM artifactos.publication_package WHERE idempotency_key=''' + IdemKey + '''');
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
    var GateResult := DB.ExecuteScalar('SELECT (artifactos.check_real_publish_gate() ->> ''gate_status'')::text');
    Assert.AreEqual('blocked', GateResult, 'RealPublishGate must always be blocked');

    var Reason := DB.ExecuteScalar('SELECT (artifactos.check_real_publish_gate() ->> ''reason'')::text');
    Assert.IsTrue((Pos('Phase 1A', Reason) > 0) or (Pos('Shadow run mode', Reason) > 0),
      'Block reason should mention Phase 1A or Shadow run mode');
  finally
    DB.Disconnect;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStateMachineTests);
end.
