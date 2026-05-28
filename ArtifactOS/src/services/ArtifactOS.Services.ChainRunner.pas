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

function InsertAndReturnId(const SQL: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnId(SQL);
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
      // 1. Case → Studio → ArtifactPlan (reuse the e2e chain pattern)
      AResult.CaseId := DB.InsertAndReturnId('INSERT INTO artifactos.case_record (case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
        'VALUES (''chain_'' || floor(extract(epoch from now()))::text, ''day_sub'', ''Chain: ' + ATitle + ''', ''active'', ''tactical_execution'', ' +
        '(SELECT id FROM artifactos.case_record WHERE case_code=''yearcase_2026''), (SELECT id FROM artifactos.case_record WHERE case_code=''yearcase_2026'')) ' +
        'RETURNING id');

      AResult.StudioId := DB.InsertAndReturnId('INSERT INTO artifactos.studio (studio_code, case_id, platform_id, artifact_type, theory_visibility, status) ' +
        'VALUES (''chain_studio_'' || floor(extract(epoch from now()))::text, ''' + AResult.CaseId + ''', ''zhihu'', ''zhihu_longform'', ''medium'', ''planning'') ' +
        'RETURNING id');

      var PlanId := DB.InsertAndReturnId('INSERT INTO artifactos.artifact_plan (studio_id, blueprint_id, primary_purpose_type, risk_level, status) ' +
        'VALUES (''' + AResult.StudioId + ''', (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ''explanation'', ''normal'', ''approved'') ' +
        'RETURNING id');

      DB.InsertAndReturnId('INSERT INTO artifactos.sub_studio (studio_id, artifact_plan_id, status) VALUES (''' + AResult.StudioId + ''', ''' + PlanId + ''', ''executing'') RETURNING id');

      // 2. Artifact
      AResult.ArtifactId := DB.InsertAndReturnId('INSERT INTO artifactos.artifact (sub_studio_id, artifact_plan_id, blueprint_id, title, status, primary_purpose_type, theory_visibility) ' +
        'VALUES ((SELECT id FROM artifactos.sub_studio WHERE artifact_plan_id=''' + PlanId + '''), ''' + PlanId + ''', ' +
        '(SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ''' + ATitle + ''', ''assembled'', ''explanation'', ''medium'') ' +
        'RETURNING id');

      // 3. ArtifactVersion (sealed)
      AResult.VersionId := DB.InsertAndReturnId('INSERT INTO artifactos.artifact_version (artifact_id, version_no, assembled_payload, seal_status) ' +
        'VALUES (''' + AResult.ArtifactId + ''', 1, ''{"title":"' + ATitle + '","body":"' + ABody + '"}'', ''sealed'') ' +
        'RETURNING id');

      // 4. Run ES gate
      Gate := TQualityGateService.RunESGate(AResult.ArtifactId, '{}');
      if not Gate.Passed then
      begin
        DB.Connection.Rollback;
        Exit;
      end;

      // 5. QualityRun + Snapshot
      AResult.RunId := DB.InsertAndReturnId('INSERT INTO artifactos.quality_run (artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) ' +
        'VALUES (''' + AResult.ArtifactId + ''', ''' + AResult.VersionId + ''', ''es'', ''{"gate":"' + Gate.GateStatus + '"}'', ''completed'', now()) ' +
        'RETURNING id');

      AResult.SnapshotId := DB.InsertAndReturnId('INSERT INTO artifactos.quality_snapshot (artifact_id, artifact_version_id, qualified_status, publish_readiness, purpose_fit_status, seal_candidate, sealed_at, sealed_by) ' +
        'VALUES (''' + AResult.ArtifactId + ''', ''' + AResult.VersionId + ''', ''qualified'', ''ready'', ''pass'', true, null, null) ' +
        'RETURNING id');

      DB.Execute('UPDATE artifactos.quality_snapshot SET quality_run_ids_cache=''["' + AResult.RunId + '"]'' WHERE id=''' + AResult.SnapshotId + '''');
      DB.Execute('UPDATE artifactos.quality_snapshot SET sealed_at=now(), sealed_by=''system:chain_runner'' WHERE id=''' + AResult.SnapshotId + ''' AND sealed_at IS NULL');

      // 6. PublicationPackage
      AResult.PackageId := TPackageBuilder.BuildPackage(AResult.ArtifactId, AResult.VersionId, AResult.SnapshotId, 'zhihu', 'test_account');

      // 7. Create a WorkCard for this artifact
      var DeskInfo: TWorkCardInfo;
      DeskInfo.CardType := 'ArtifactCard';
      DeskInfo.Title := 'Artifact: ' + ATitle;
      DeskInfo.Summary := 'ES gate: ' + Gate.GateStatus + ' | Quality: qualified | Package: simulated';
      DeskInfo.Priority := 'normal';
      DeskInfo.ReviewRequirement := 'recommended';
      DeskInfo.SourceType := 'artifact';
      DeskInfo.SourceId := AResult.ArtifactId;
      var CardId := TAmyDeskService.CreateWorkCard(DeskInfo);
      var PanelId := TAmyDeskService.CreatePanel(CardId, 'artifact_review', 'artifact', AResult.ArtifactId);
      TAmyDeskService.AddPanelOption(PanelId, '1', 'Approve', 'approve', True);
      TAmyDeskService.AddPanelOption(PanelId, '6', 'Hold', 'hold', False);

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
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      DB.Execute('DELETE FROM artifactos.publication_package WHERE id=''' + AResult.PackageId + '''');
      DB.Execute('DELETE FROM artifactos.quality_snapshot WHERE id=''' + AResult.SnapshotId + '''');
      DB.Execute('DELETE FROM artifactos.quality_run WHERE id=''' + AResult.RunId + '''');
      DB.Execute('DELETE FROM artifactos.artifact_version WHERE id=''' + AResult.VersionId + '''');
      DB.Execute('DELETE FROM artifactos.artifact WHERE id=''' + AResult.ArtifactId + '''');
      DB.Execute('DELETE FROM artifactos.sub_studio WHERE studio_id=''' + AResult.StudioId + '''');
      DB.Execute('DELETE FROM artifactos.artifact_plan WHERE studio_id=''' + AResult.StudioId + '''');
      DB.Execute('DELETE FROM artifactos.studio WHERE id=''' + AResult.StudioId + '''');
      DB.Execute('DELETE FROM artifactos.case_record WHERE id=''' + AResult.CaseId + '''');
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