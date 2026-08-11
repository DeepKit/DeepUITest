unit ArtifactOS.Core.EndToEnd;

interface

uses
  System.SysUtils,
  ArtifactOS.Core.DB.Connection;

type
  TArtifactOSEndToEnd = class
  public
    class procedure RunCreateChain(out CaseId, StudioId, ArtifactId, SnapshotId, PackageId: string);
  end;

implementation

uses
  FireDAC.Comp.Client;

class procedure TArtifactOSEndToEnd.RunCreateChain(out CaseId, StudioId, ArtifactId, SnapshotId, PackageId: string);

  function InsertReturningId(const SQL: string): string;
  begin
    Result := ArtifactOS_DB.InsertAndReturnId(SQL);
  end;

begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      // 1. Build full case hierarchy: year→quarter→month→week→day→day_sub
      var Chain := IntToStr(Random(MaxInt));
      var YearId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.case_record WHERE case_code=''yearcase_2026''');

      // Find or create quarter under year
      var QtrId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.case_record WHERE case_type=''quarter'' AND parent_case_id=''' + YearId + ''' LIMIT 1');
      if QtrId = '' then
        QtrId := InsertReturningId(
          'INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
          'VALUES (''e2e_qtr_' + Chain + ''', ''quarter'', ''E2E Quarter'', ''active'', ''tactical_execution'', ''' + YearId + ''', ''' + YearId + ''') RETURNING id');

      // Find or create month under quarter
      var MonId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.case_record WHERE case_type=''month'' AND parent_case_id=''' + QtrId + ''' LIMIT 1');
      if MonId = '' then
        MonId := InsertReturningId(
          'INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
          'VALUES (''e2e_mon_' + Chain + ''', ''month'', ''E2E Month'', ''active'', ''tactical_execution'', ''' + QtrId + ''', ''' + YearId + ''') RETURNING id');

      // Find or create week under month
      var WkId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.case_record WHERE case_type=''week'' AND parent_case_id=''' + MonId + ''' LIMIT 1');
      if WkId = '' then
        WkId := InsertReturningId(
          'INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
          'VALUES (''e2e_wk_' + Chain + ''', ''week'', ''E2E Week'', ''active'', ''tactical_execution'', ''' + MonId + ''', ''' + YearId + ''') RETURNING id');

      // Create day under week
      var DayId := InsertReturningId(
        'INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
        'VALUES (''e2e_day_' + Chain + ''', ''day'', ''E2E Day'', ''active'', ''tactical_execution'', ''' + WkId + ''', ''' + YearId + ''') RETURNING id');

      // Create day_sub under day (our actual artifact case)
      CaseId := InsertReturningId(
        'INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
        'VALUES (''e2e_' + Chain + ''', ''day_sub'', ''E2E Chain Test'', ''active'', ''tactical_execution'', ''' + DayId + ''', ''' + YearId + ''') ' +
        'RETURNING id');

      // 2. Create Studio
      StudioId := InsertReturningId(
        'INSERT INTO artifactos.studio (studio_code, case_id, platform_id, artifact_type, theory_visibility, status) ' +
        'VALUES (''e2e_' + IntToStr(Random(MaxInt)) + ''', ''' + CaseId + ''', ''zhihu'', ''zhihu_longform'', ''medium'', ''planning'') ' +
        'RETURNING id');

      // 3. Create ArtifactPlan + SubStudio
      var PlanId := InsertReturningId(
        'INSERT INTO artifactos.artifact_plan (studio_id, blueprint_id, primary_purpose_type, risk_level, status) ' +
        'VALUES (''' + StudioId + ''', (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ' +
        '''explanation'', ''normal'', ''approved'') ' +
        'RETURNING id');

      InsertReturningId(
        'INSERT INTO artifactos.sub_studio (studio_id, artifact_plan_id, status) ' +
        'VALUES (''' + StudioId + ''', ''' + PlanId + ''', ''executing'') ' +
        'RETURNING id');

      // 4. Create Artifact
      ArtifactId := InsertReturningId(
        'INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status, primary_purpose_type, theory_visibility) ' +
        'VALUES (' +
        '(SELECT id FROM artifactos.sub_studio WHERE artifact_plan_id=''' + PlanId + '''), ' +
        '''' + PlanId + ''', ' +
        '(SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ' +
        '''E2E Test: Source-to-Artifact Chain'', ''assembled'', ''explanation'', ''medium'') ' +
        'RETURNING id');

      // 5. Create ArtifactVersion (sealed)
      InsertReturningId(
        'INSERT INTO artifactos.artifact_version (artifact_id, version_no, assembled_payload, seal_status) ' +
        'VALUES (''' + ArtifactId + ''', 1, ''{"title":"E2E Chain Test","body":"Created end-to-end by ArtifactOS Phase 1A."}'', ''sealed'') ' +
        'RETURNING id');

      // 6. Create QualityRun + QualitySnapshot
      var RunId := InsertReturningId(
        'INSERT INTO artifactos.quality_run (artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) ' +
        'VALUES (''' + ArtifactId + ''', (SELECT id FROM artifactos.artifact_version WHERE artifact_id=''' + ArtifactId + ''' AND version_no=1), ' +
        '''es'', ''{"es_gate":"passed"}'', ''completed'', now()) ' +
        'RETURNING id');

      SnapshotId := InsertReturningId(
        'INSERT INTO artifactos.quality_snapshot (artifact_id, artifact_version_id, qualified_status, publish_readiness, purpose_fit_status, seal_candidate, sealed_at, sealed_by) ' +
        'VALUES (''' + ArtifactId + ''', (SELECT id FROM artifactos.artifact_version WHERE artifact_id=''' + ArtifactId + ''' AND version_no=1), ' +
        '''qualified'', ''ready'', ''pass'', true, null, null) ' +
        'RETURNING id');

      ArtifactOS_DB.Execute(
        'UPDATE artifactos.quality_snapshot SET quality_run_ids_cache = ''["' + RunId + '"]'' WHERE id=''' + SnapshotId + '''' + ' AND sealed_at IS NULL');
      ArtifactOS_DB.Execute(
        'UPDATE artifactos.quality_snapshot SET sealed_at = now(), sealed_by = ''system:e2e_test'' WHERE id = ''' + SnapshotId + '''' + ' AND sealed_at IS NULL');

      // 7. Create PublicationPackage (simulated)
      PackageId := InsertReturningId(
        'INSERT INTO artifactos.publication_package (artifact_id, artifact_version_id, quality_snapshot_id, platform, idempotency_key, simulation_only, run_mode, status) ' +
        'VALUES (''' + ArtifactId + ''', (SELECT id FROM artifactos.artifact_version WHERE artifact_id=''' + ArtifactId + ''' AND version_no=1), ' +
        '''' + SnapshotId + ''', ''zhihu'', ''e2e_pkg_' + Chain + ''', true, ''shadow'', ''simulated'') ' +
        'RETURNING id');

      ArtifactOS_DB.Connection.Commit;
    except
      ArtifactOS_DB.Connection.Rollback;
      raise;
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

end.
