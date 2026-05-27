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
  var
    Q: TFDQuery;
  begin
    Q := ArtifactOS_DB.Query(SQL);
    try
      Result := Q.Fields[0].AsString;
    finally
      Q.Free;
    end;
  end;

begin
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.Connection.StartTransaction;
    try
      // 1. Create a DaySubCase under yearcase_2026
      CaseId := InsertReturningId(
        'INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
        'VALUES (''e2e_'' || floor(extract(epoch from now()))::text, ''day_sub'', ''E2E Chain Test'', ''active'', ''tactical_execution'', ' +
        '(SELECT id FROM artifactos.case_record WHERE case_code=''yearcase_2026''), ' +
        '(SELECT id FROM artifactos.case_record WHERE case_code=''yearcase_2026'')) ' +
        'RETURNING id');

      // 2. Create Studio
      StudioId := InsertReturningId(
        'INSERT INTO artifactos.studio (studio_code, case_id, platform_id, artifact_type, theory_visibility, status) ' +
        'VALUES (''e2e_studio_'' || floor(extract(epoch from now()))::text, ''' + CaseId + ''', ''zhihu'', ''zhihu_longform'', ''medium'', ''planning'') ' +
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
        '''' + SnapshotId + ''', ''zhihu'', ''e2e_pkg_'' || floor(extract(epoch from now()))::text, true, ''shadow'', ''simulated'') ' +
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