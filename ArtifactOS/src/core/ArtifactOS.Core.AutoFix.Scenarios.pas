{ ============================================================================
  ArtifactOS.Core.AutoFix.Scenarios

  AutoFix smoke scenarios for ArtifactOS runtime verification.
  These scenarios run when the app is launched with --autofix-mode.

  Registered in DPR for both Desk and Engine modes.
  ============================================================================ }

unit ArtifactOS.Core.AutoFix.Scenarios;

interface

uses
  System.SysUtils,
  DeepBase.AutoFix;

procedure RegisterArtifactOSAutoFixScenarios;

implementation

uses
  ArtifactOS.Core.DB.Connection;

procedure RegisterArtifactOSAutoFixScenarios;
begin
  { Scenario: PG connectivity }
  AutoFix.RegisterScenario('pg.connect', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''artifactos''');
      if V <> '1' then
        raise Exception.Create('artifactos schema not found in database');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Migrations applied }
  AutoFix.RegisterScenario('pg.migrations', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos._migration_log');
      if StrToIntDef(V, 0) < 1 then
        raise Exception.Create('No migrations applied to artifactos schema');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Core tables exist }
  AutoFix.RegisterScenario('pg.core_tables', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var Tables: TArray<string> := [
        'case_record', 'studio', 'sub_studio', 'artifact', 'artifact_version',
        'quality_snapshot', 'quality_run', 'publication_package',
        'real_publish_gate_run', 'event_ledger', 'substudio_execution_task',
        'artifact_contract', 'content_spec_snapshot'
      ];
      for var T in Tables do
      begin
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM information_schema.tables ' +
          'WHERE table_schema=''artifactos'' AND table_name=''' + T + '''');
        if V <> '1' then
          raise Exception.Create('Required table missing: artifactos.' + T);
      end;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: State machine rules loaded }
  AutoFix.RegisterScenario('pg.state_rules', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.state_transition_rule');
      if StrToIntDef(V, 0) < 10 then
        raise Exception.Create('Too few state transition rules: ' + V + ' (expected >= 10)');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Blueprint seeds exist }
  AutoFix.RegisterScenario('pg.blueprints', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.blueprint');
      if StrToIntDef(V, 0) < 1 then
        raise Exception.Create('No blueprints seeded');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: RealPublishGate function callable }
  AutoFix.RegisterScenario('pg.real_publish_gate', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT (artifactos.check_real_publish_gate() ->> ''gate_status'')::text');
      if (V <> 'blocked') and (V <> 'open') then
        raise Exception.Create('Unexpected RealPublishGate status: ' + V);
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Contract pipeline tables accessible }
  AutoFix.RegisterScenario('pg.contracts', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      // Basic table existence
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.requirement_frame');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.content_spec_snapshot');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.contract_candidate');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.artifact_contract');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Media publish schema exists }
  AutoFix.RegisterScenario('pg.media_publish', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''media_publish''');
      if V <> '1' then
        raise Exception.Create('media_publish schema not found');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Generation session tables accessible }
  AutoFix.RegisterScenario('pg.generation_session', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.generation_session');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.generation_outline');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);
end;

end.
