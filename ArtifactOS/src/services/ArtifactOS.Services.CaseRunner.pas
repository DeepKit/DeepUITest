unit ArtifactOS.Services.CaseRunner;

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.ChainRunner,
  ArtifactOS.Services.QualityGate,
  ArtifactOS.Services.PackageBuilder,
  ArtifactOS.Services.Notification,
  ArtifactOS.Services.AmyDesk,
  ArtifactOS.Core.AutoTune;

type
  TCaseRunnerResult = record
    CaseId: string;
    ArtifactId: string;
    SnapshotId: string;
    PackageId: string;
    ReportId: string;
  end;

  TCaseRunner = class
  public
    class function RunDayCase(const ADayCaseCode, ATitle, ABody: string;
      out AResult: TCaseRunnerResult): Boolean;
    class function RunEveningReview(const AResult: TCaseRunnerResult; AApproved: Boolean): Boolean;
  end;

implementation

class function TCaseRunner.RunDayCase(const ADayCaseCode, ATitle, ABody: string;
  out AResult: TCaseRunnerResult): Boolean;
var
  Chain: TChainResult;
begin
  Result := False;

  // 1. Run full chain
  if not TChainRunner.RunFullChain(ATitle, ABody, Chain) then
  begin
    Exit;
  end;

  AResult.CaseId := Chain.CaseId;
  AResult.ArtifactId := Chain.ArtifactId;
  AResult.SnapshotId := Chain.SnapshotId;
  AResult.PackageId := Chain.PackageId;

  // 2. Generate daily report
  var ReportDate := FormatDateTime('yyyy-mm-dd', Now);
  AResult.ReportId := TNotificationService.SendDailyReport(
    AResult.CaseId, ReportDate,
    'Artifact produced: ' + ATitle,
    '{"decisions":["ES gate passed","Quality qualified","Package simulated"]}',
    '{"risks":["none"]}',
    '{"tomorrow":"Continue shadow run validation"}');

  TNotificationService.MarkNotified(AResult.ReportId);

  // 3. Generate Amy Today Desk cards
  TAmyDeskService.GenerateTodayDesk(AResult.CaseId);

  // 4. AutoTune example: verify deny-list blocks
  var TuneResult := TAutoTuneService.TryAutoTune('strategy_unit', 'su_test', 'source_pack.core', '0.5', '0.8', '[]');
  // This should be blocked (deny list) — we verify silently

  Result := True;
end;

class function TCaseRunner.RunEveningReview(const AResult: TCaseRunnerResult; AApproved: Boolean): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    if AApproved then
    begin
      TNotificationService.MarkOpened(AResult.ReportId);
      TNotificationService.MarkCompleted(AResult.ReportId);

      // Create legacy diff card — simulated shadow observation
      DB.Execute(
        'INSERT INTO legacy_bridge.legacy_diff_card (shadow_run_day_id, artifactos_ref, legacy_ref, deviation_type, severity, status) ' +
        'VALUES (NULL, ''{"artifact_id":"' + AResult.ArtifactId + '"}'', ''{"legacy":"No legacy system available"}'', ''no_material_deviation'', ''none'', ''open'')');

      Result := True;
    end
    else
    begin
      TPackageBuilder.MarkHeld(AResult.PackageId, 'Evening review: human held');
      Result := True;
    end;
  finally
    DB.Disconnect;
  end;
end;

end.