unit ArtifactOS.Services.ChainRunner;

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.QualityGate,
  ArtifactOS.Services.PackageBuilder,
  ArtifactOS.Services.AmyDesk;

type
  TChainResult = record
    CaseId: string;
    StudioId: string;
    ArtifactId: string;
    VersionId: string;
    RunId: string;
    SnapshotId: string;
    PackageId: string;
  end;

  TChainRunner = class
  public
    class function RunFullChain(const ATitle, ABody: string; out AResult: TChainResult): Boolean;
    class procedure CleanupChain(const AResult: TChainResult);
  end;

implementation

uses
  FireDAC.Comp.Client;

function JsonStr(const S: string): string;
begin
  Result := S.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n');
end;

function JsonParam(const AName, AValue: string): string;
begin
  Result := '"' + AName + '":"' + JsonStr(AValue) + '"';
end;

function JsonObj(const AFields: array of string): string;
var
  I: Integer;
begin
  Result := '{';
  for I := 0 to High(AFields) do
  begin
    if I > 0 then Result := Result + ',';
    Result := Result + AFields[I];
  end;
  Result := Result + '}';
end;

class function TChainRunner.RunFullChain(const ATitle, ABody: string; out AResult: TChainResult): Boolean;
var
  DB: TArtifactDB;
  Gate: TGateResult;
begin
  Result := False;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      // Pre-generate all UUIDs client-side to avoid FireDAC transaction visibility issues
      // NOTE: TGUID.ToString returns {braced} format; strip braces for PG ::uuid
      AResult.CaseId     := TGUID.NewGuid.ToString.Trim(['{', '}']);
      AResult.StudioId   := TGUID.NewGuid.ToString.Trim(['{', '}']);
      var PlanId         := TGUID.NewGuid.ToString.Trim(['{', '}']);
      var SubId          := TGUID.NewGuid.ToString.Trim(['{', '}']);
      AResult.ArtifactId := TGUID.NewGuid.ToString.Trim(['{', '}']);
      AResult.VersionId  := TGUID.NewGuid.ToString.Trim(['{', '}']);
      AResult.RunId      := TGUID.NewGuid.ToString.Trim(['{', '}']);
      AResult.SnapshotId := TGUID.NewGuid.ToString.Trim(['{', '}']);

      var YearId := DB.ExecuteScalarJson(
        'SELECT id::text FROM artifactos.case_record WHERE case_code=''yearcase_2026'' LIMIT 1', '');

      // 1. Case — parameterized INSERT
      DB.ExecuteJson(
        'INSERT INTO artifactos.case_record (id, case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
        'VALUES (' +
        '  :case_id::uuid, ''chain_'' || floor(extract(epoch from now()))::text, ''day_sub'', :title, ' +
        '  ''active'', ''tactical_execution'', :year_id::uuid, :year_id::uuid' +
        ')',
        JsonObj([JsonParam('case_id', AResult.CaseId), JsonParam('title', 'Chain: ' + ATitle), JsonParam('year_id', YearId)]));

      // 2. Studio
      DB.ExecuteJson(
        'INSERT INTO artifactos.studio (id, studio_code, case_id, platform_id, artifact_type, theory_visibility, status) ' +
        'VALUES (:id::uuid, ''chain_studio_'' || floor(extract(epoch from now()))::text, :case_id::uuid, ''zhihu'', ''zhihu_longform'', ''medium'', ''planning'')',
        JsonObj([JsonParam('id', AResult.StudioId), JsonParam('case_id', AResult.CaseId)]));

      // 3. ArtifactPlan
      DB.ExecuteJson(
        'INSERT INTO artifactos.artifact_plan (id, studio_id, blueprint_id, primary_purpose_type, risk_level, status) ' +
        'VALUES (:id::uuid, :studio_id::uuid, (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ''explanation'', ''normal'', ''approved'')',
        JsonObj([JsonParam('id', PlanId), JsonParam('studio_id', AResult.StudioId)]));

      // 4. SubStudio
      DB.ExecuteJson(
        'INSERT INTO artifactos.sub_studio (studio_id, artifact_plan_id, status) VALUES (:studio_id::uuid, :plan_id::uuid, ''executing'')',
        JsonObj([JsonParam('studio_id', AResult.StudioId), JsonParam('plan_id', PlanId)]));

      // 5. Artifact
      DB.ExecuteJson(
        'INSERT INTO artifactos.artifact (id, sub_studio_id, artifact_plan_id, blueprint_id, title, status, primary_purpose_type, theory_visibility) ' +
        'VALUES (:id::uuid, :sub_id::uuid, :plan_id::uuid, (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), :title, ''assembled'', ''explanation'', ''medium'')',
        JsonObj([JsonParam('id', AResult.ArtifactId), JsonParam('sub_id', SubId), JsonParam('plan_id', PlanId), JsonParam('title', ATitle)]));

      // 6. ArtifactVersion — with JSON payload
      var PayloadJson := '{"title":"' + JsonStr(ATitle) + '","body":"' + JsonStr(ABody) + '"}';
      DB.ExecuteJson(
        'INSERT INTO artifactos.artifact_version (id, artifact_id, version_no, assembled_payload, seal_status) ' +
        'VALUES (:id::uuid, :artifact_id::uuid, 1, :payload::jsonb, ''sealed'')',
        JsonObj([JsonParam('id', AResult.VersionId), JsonParam('artifact_id', AResult.ArtifactId), '"payload":' + PayloadJson]));

      // 7. Run ES gate
      Gate := TQualityGateService.RunESGateOnConn(DB.Connection, AResult.ArtifactId, '{}');
      if not Gate.Passed then begin DB.Connection.Rollback; Exit; end;

      // 8. QualityRun
      var GateEvidence := '{"gate":"' + JsonStr(Gate.GateStatus) + '"}';
      DB.ExecuteJson(
        'INSERT INTO artifactos.quality_run (id, artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) ' +
        'VALUES (:id::uuid, :artifact_id::uuid, :version_id::uuid, ''es'', :evidence::jsonb, ''completed'', now())',
        JsonObj([JsonParam('id', AResult.RunId), JsonParam('artifact_id', AResult.ArtifactId), JsonParam('version_id', AResult.VersionId), '"evidence":' + GateEvidence]));

      // 9. QualitySnapshot
      DB.ExecuteJson(
        'INSERT INTO artifactos.quality_snapshot (id, artifact_id, artifact_version_id, qualified_status, publish_readiness, purpose_fit_status, seal_candidate) ' +
        'VALUES (:id::uuid, :artifact_id::uuid, :version_id::uuid, ''qualified'', ''ready'', ''pass'', true)',
        JsonObj([JsonParam('id', AResult.SnapshotId), JsonParam('artifact_id', AResult.ArtifactId), JsonParam('version_id', AResult.VersionId)]));

      var CacheJson := '["' + AResult.RunId + '"]';
      DB.ExecuteJson(
        'UPDATE artifactos.quality_snapshot SET quality_run_ids_cache=:cache::jsonb WHERE id=:id::uuid',
        JsonObj(['"cache":' + CacheJson, JsonParam('id', AResult.SnapshotId)]));

      DB.ExecuteJson(
        'UPDATE artifactos.quality_snapshot SET sealed_at=now(), sealed_by=''system:chain_runner'' WHERE id=:id::uuid AND sealed_at IS NULL',
        JsonObj([JsonParam('id', AResult.SnapshotId)]));

      // 10. PublicationPackage (on shared transaction connection)
      AResult.PackageId := TPackageBuilder.BuildPackageOnConn(DB.Connection, AResult.ArtifactId, AResult.VersionId, AResult.SnapshotId, 'zhihu', TGUID.NewGuid.ToString.Trim(['{', '}']));

      DB.Connection.Commit;
      Result := True;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

class procedure TChainRunner.CleanupChain(const AResult: TChainResult);
var
  DB: TArtifactDB;

  procedure SafeDelete(const ASQL, AId: string);
  begin
    DB.ExecuteJson(ASQL, JsonObj([JsonParam('id', AId)]));
  end;

begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      // Cleanup in reverse dependency order — all parameterized
      SafeDelete('DELETE FROM artifactos.publication_package WHERE id=:id::uuid', AResult.PackageId);
      SafeDelete('DELETE FROM artifactos.quality_snapshot WHERE id=:id::uuid', AResult.SnapshotId);
      SafeDelete('DELETE FROM artifactos.quality_run WHERE id=:id::uuid', AResult.RunId);
      SafeDelete('DELETE FROM artifactos.artifact_version WHERE id=:id::uuid', AResult.VersionId);
      SafeDelete('DELETE FROM artifactos.artifact WHERE id=:id::uuid', AResult.ArtifactId);
      SafeDelete('DELETE FROM artifactos.sub_studio WHERE id = (SELECT ss.id FROM artifactos.sub_studio ss JOIN artifactos.artifact_plan ap ON ss.artifact_plan_id = ap.id WHERE ap.studio_id=:id::uuid)', AResult.StudioId);
      SafeDelete('DELETE FROM artifactos.artifact_plan WHERE studio_id=:id::uuid', AResult.StudioId);
      SafeDelete('DELETE FROM artifactos.studio WHERE id=:id::uuid', AResult.StudioId);
      SafeDelete('DELETE FROM artifactos.case_record WHERE id=:id::uuid', AResult.CaseId);
      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

end.