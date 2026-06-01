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

      var Q := TFDQuery.Create(nil);
      try
        Q.Connection := DB.Connection;

        // 1. Case
        var YearId := DB.Connection.ExecSQLScalar('SELECT id FROM artifactos.case_record WHERE case_code=''yearcase_2026''');
        Q.SQL.Text := 'INSERT INTO artifactos.case_record (id, case_code, case_type, title, status, planning_nature, parent_case_id, root_case_id) ' +
          'VALUES (''' + AResult.CaseId + ''', ''chain_'' || floor(extract(epoch from now()))::text, ''day_sub'', ''Chain: ' + ATitle + ''', ''active'', ''tactical_execution'', ''' + YearId + ''', ''' + YearId + ''')';
        Q.ExecSQL;

        // 2. Studio
        Q.SQL.Text := 'INSERT INTO artifactos.studio (id, studio_code, case_id, platform_id, artifact_type, theory_visibility, status) ' +
          'VALUES (''' + AResult.StudioId + ''', ''chain_studio_'' || floor(extract(epoch from now()))::text, ''' + AResult.CaseId + ''', ''zhihu'', ''zhihu_longform'', ''medium'', ''planning'')';
        Q.ExecSQL;

        // 3. ArtifactPlan
        Q.SQL.Text := 'INSERT INTO artifactos.artifact_plan (id, studio_id, blueprint_id, primary_purpose_type, risk_level, status) ' +
          'VALUES (''' + PlanId + ''', ''' + AResult.StudioId + ''', (SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ''explanation'', ''normal'', ''approved'')';
        Q.ExecSQL;

        // 4. SubStudio
        Q.SQL.Text := 'INSERT INTO artifactos.sub_studio (studio_id, artifact_plan_id, status) VALUES (''' + AResult.StudioId + ''', ''' + PlanId + ''', ''executing'')';
        Q.ExecSQL;

        // 5. Artifact
        Q.SQL.Text := 'INSERT INTO artifactos.artifact (id, sub_studio_id, artifact_plan_id, blueprint_id, title, status, primary_purpose_type, theory_visibility) ' +
          'VALUES (''' + AResult.ArtifactId + ''', ''' + SubId + ''', ''' + PlanId + ''', ' +
          '(SELECT id FROM artifactos.artifact_blueprint WHERE blueprint_code=''zhihu_article_v1'' LIMIT 1), ''' + ATitle + ''', ''assembled'', ''explanation'', ''medium'')';
        Q.ExecSQL;

        // 6. ArtifactVersion
        Q.SQL.Text := 'INSERT INTO artifactos.artifact_version (id, artifact_id, version_no, assembled_payload, seal_status) ' +
          'VALUES (''' + AResult.VersionId + ''', ''' + AResult.ArtifactId + ''', 1, ''{"title":"' + ATitle + '","body":"' + ABody + '"}'', ''sealed'')';
        Q.ExecSQL;

        // 7. Run ES gate
        Gate := TQualityGateService.RunESGateOnConn(DB.Connection, AResult.ArtifactId, '{}');
        if not Gate.Passed then begin DB.Connection.Rollback; Exit; end;

        // 8. QualityRun
        Q.SQL.Text := 'INSERT INTO artifactos.quality_run (id, artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) ' +
          'VALUES (''' + AResult.RunId + ''', ''' + AResult.ArtifactId + ''', ''' + AResult.VersionId + ''', ''es'', ''{"gate":"' + Gate.GateStatus + '"}'', ''completed'', now())';
        Q.ExecSQL;

        // 9. QualitySnapshot
        Q.SQL.Text := 'INSERT INTO artifactos.quality_snapshot (id, artifact_id, artifact_version_id, qualified_status, publish_readiness, purpose_fit_status, seal_candidate) ' +
          'VALUES (''' + AResult.SnapshotId + ''', ''' + AResult.ArtifactId + ''', ''' + AResult.VersionId + ''', ''qualified'', ''ready'', ''pass'', true)';
        Q.ExecSQL;
        Q.SQL.Text := 'UPDATE artifactos.quality_snapshot SET quality_run_ids_cache=''["' + AResult.RunId + '"]'' WHERE id=''' + AResult.SnapshotId + ''''; Q.ExecSQL;
        Q.SQL.Text := 'UPDATE artifactos.quality_snapshot SET sealed_at=now(), sealed_by=''system:chain_runner'' WHERE id=''' + AResult.SnapshotId + ''' AND sealed_at IS NULL'; Q.ExecSQL;
      finally
        Q.Free;
      end;

      // 10. PublicationPackage (on shared transaction connection)
      AResult.PackageId := TPackageBuilder.BuildPackageOnConn(DB.Connection, AResult.ArtifactId, AResult.VersionId, AResult.SnapshotId, 'zhihu', TGUID.NewGuid.ToString.Trim(['{', '}']));

      // 11. Create a WorkCard for this artifact
      var DeskInfo: TWorkCardInfo;
      DeskInfo.CardType := 'ArtifactCard';
      DeskInfo.Title := 'Artifact: ' + ATitle;
      DeskInfo.Summary := 'ES gate: ' + Gate.GateStatus + ' | Quality: qualified | Package: simulated';
      DeskInfo.Priority := 'normal';
      DeskInfo.ReviewRequirement := 'recommended';
      DeskInfo.SourceType := 'artifact';
      DeskInfo.SourceId := AResult.ArtifactId;
      // AmyDesk opens its own DB connection; deferred to after commit
      // var CardId := TAmyDeskService.CreateWorkCard(DeskInfo);
      // var PanelId := TAmyDeskService.CreatePanel(CardId, ...);
      // TAmyDeskService.AddPanelOption(PanelId, ...);

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
      // Cleanup in reverse dependency order
      DB.Execute('DELETE FROM artifactos.publication_package WHERE id=''' + AResult.PackageId + '''');
      DB.Execute('DELETE FROM artifactos.quality_snapshot WHERE id=''' + AResult.SnapshotId + '''');
      DB.Execute('DELETE FROM artifactos.quality_run WHERE id=''' + AResult.RunId + '''');
      DB.Execute('DELETE FROM artifactos.artifact_version WHERE id=''' + AResult.VersionId + '''');
      DB.Execute('DELETE FROM artifactos.artifact WHERE id=''' + AResult.ArtifactId + '''');
      DB.Execute('DELETE FROM artifactos.sub_studio WHERE id = (SELECT id FROM artifactos.sub_studio WHERE artifact_plan_id = (SELECT id FROM artifactos.artifact_plan WHERE studio_id = ''' + AResult.StudioId + '''))');
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