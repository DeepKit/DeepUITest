unit ArtifactOS.Tests.ShadowRun;

interface

uses
  DUnitX.TestFramework,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.ShadowRun,
  ArtifactOS.Services.Notification;

type
  [TestFixture]
  TShadowRunTests = class
  public
    [Test]
    procedure ShadowRun_CreateStartComplete_ValidLifecycle;

    [Test]
    procedure ShadowRun_CreateDayAndObservation;

    [Test]
    procedure ShadowRun_AbortPreservesState;

    [Test]
    procedure DailyReport_CreateAndNotify;
  end;

implementation

uses
  System.SysUtils;

procedure TShadowRunTests.ShadowRun_CreateStartComplete_ValidLifecycle;
var
  DB: TArtifactDB;
  RunId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var RunCode := 'lifecycle_test_' + IntToStr(Random(MaxInt));
    RunId := TShadowRunService.CreateRun(RunCode, '2026-06-01', '2026-06-07', 'zhihu');
    Assert.IsNotEmpty(RunId);

    var Status := DB.ExecuteScalar('SELECT status FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
    Assert.AreEqual('planned', Status);

    TShadowRunService.StartRun(RunId);
    Status := DB.ExecuteScalar('SELECT status FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
    Assert.AreEqual('running', Status);

    TShadowRunService.CompleteRun(RunId);
    Status := DB.ExecuteScalar('SELECT status FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
    Assert.AreEqual('completed', Status);

    DB.Execute('DELETE FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
  finally
    DB.Disconnect;
  end;
end;

procedure TShadowRunTests.ShadowRun_CreateDayAndObservation;
var
  DB: TArtifactDB;
  RunId, DayId, ObsId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    RunId := TShadowRunService.CreateRun('day_test_' + IntToStr(Random(MaxInt)), '2026-06-01', '2026-06-07', 'zhihu');
    TShadowRunService.StartRun(RunId);

    DayId := TShadowRunService.CreateDay(RunId, '2026-06-01', 1);
    Assert.IsNotEmpty(DayId);

    ObsId := TShadowRunService.CreateObservation(RunId, DayId, 'no_material_deviation',
      '{"artifactos":"generated"}', '{"legacy":"not available"}', 'simulated', 'none');
    Assert.IsNotEmpty(ObsId);

    var Count := DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.shadow_run_observation WHERE id=''' + ObsId + '''');
    Assert.AreEqual('1', Count);

    DB.Execute('DELETE FROM artifactos.shadow_run_observation WHERE shadow_run_id=''' + RunId + '''');
    DB.Execute('DELETE FROM artifactos.shadow_run_day WHERE shadow_run_id=''' + RunId + '''');
    DB.Execute('DELETE FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
  finally
    DB.Disconnect;
  end;
end;

procedure TShadowRunTests.ShadowRun_AbortPreservesState;
var
  DB: TArtifactDB;
  RunId, DayId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    RunId := TShadowRunService.CreateRun('abort_test_' + IntToStr(Random(MaxInt)), '2026-06-01', '2026-06-07', 'zhihu');
    TShadowRunService.StartRun(RunId);
    DayId := TShadowRunService.CreateDay(RunId, '2026-06-01', 1);
    TShadowRunService.AbortRun(RunId, 'Test aborted by human');

    var Status := DB.ExecuteScalar('SELECT status FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
    Assert.AreEqual('aborted', Status);

    var DayStatus := DB.ExecuteScalar('SELECT status FROM artifactos.shadow_run_day WHERE id=''' + DayId + '''');
    Assert.AreEqual('planned', DayStatus, 'Day should remain planned after run abort');

    DB.Execute('DELETE FROM artifactos.shadow_run_observation WHERE shadow_run_id=''' + RunId + '''');
    DB.Execute('DELETE FROM artifactos.shadow_run_day WHERE shadow_run_id=''' + RunId + '''');
    DB.Execute('DELETE FROM artifactos.shadow_run WHERE id=''' + RunId + '''');
  finally
    DB.Disconnect;
  end;
end;

procedure TShadowRunTests.DailyReport_CreateAndNotify;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var CaseId := DB.ExecuteScalar('SELECT id::text FROM artifactos.case_record WHERE case_type=''day'' LIMIT 1');
    var ReportId := TNotificationService.SendDailyReport(CaseId, '2026-06-01',
      'Shadow run day 1 complete', '{}', '{}', 'Day 2 plan');
    Assert.IsNotEmpty(ReportId);

    var Status := DB.ExecuteScalar('SELECT status FROM artifactos.daily_report WHERE id=''' + ReportId + '''');
    Assert.AreEqual('prepared', Status);

    TNotificationService.MarkNotified(ReportId);
    Status := DB.ExecuteScalar('SELECT status FROM artifactos.daily_report WHERE id=''' + ReportId + '''');
    Assert.AreEqual('notified', Status);

    TNotificationService.MarkOpened(ReportId);
    Status := DB.ExecuteScalar('SELECT status FROM artifactos.daily_report WHERE id=''' + ReportId + '''');
    Assert.AreEqual('opened', Status);

    TNotificationService.MarkCompleted(ReportId);
    Status := DB.ExecuteScalar('SELECT status FROM artifactos.daily_report WHERE id=''' + ReportId + '''');
    Assert.AreEqual('completed', Status);

    DB.Execute('DELETE FROM artifactos.daily_report_entry_card WHERE daily_report_id=''' + ReportId + '''');
    DB.Execute('DELETE FROM artifactos.daily_report WHERE id=''' + ReportId + '''');
  finally
    DB.Disconnect;
  end;
end;

initialization

end.