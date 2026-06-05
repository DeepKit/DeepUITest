{ ============================================================================
  ArtifactOS.Services.ShadowRunScheduler

  P2-80: 7-day shadow run auto-scheduler.

  Responsibilities:
    - Advance a planned ShadowRun day-by-day through 7 days.
    - Per-day: mark day 'generated', collect observations, check attention budget,
      transition through evening/morning/simulating/reported states.
    - On day 7 close-out: compute review metrics + final_report_payload, set
      run status='completed'.
    - Idempotent: re-running for the same day detects existing day record and
      resumes from the next pending state.

  Roadmap reference: 03.[蓝图]-实施路线图-Roadmap.md §5.2 影子闭合.
  ============================================================================ }

unit ArtifactOS.Services.ShadowRunScheduler;

interface

uses
  System.SysUtils, System.JSON, System.DateUtils,
  ArtifactOS.Core.DB.Connection;

type
  /// <summary>
  /// Per-day processing outcome. Mirrors shadow_run_day.status transitions.
  /// </summary>
  TDayAdvanceOutcome = (
    daoCreated,             // day row created (status=planned)
    daoGenerated,           // artifacts produced for the day (status=generated)
    daoEveningReviewed,     // evening review collected (status=evening_reviewing)
    daoSimulated,           // simulation executed (status=simulating)
    daoReported,            // daily report sealed (status=reported)
    daoAlreadyComplete,     // day already status=closed
    daoSkipped              // attention budget exceeded or manual skip
  );

  /// <summary>
  /// Final 7-day close-out bundle. Returned by CloseOutRun.
  /// </summary>
  TShadowRunCloseOut = record
    RunId: string;
    DaysCompleted: Integer;
    DaysSkipped: Integer;
    TotalObservations: Integer;
    TotalHumanReviewMinutes: Integer;
    AttentionBudgetOverflows: Integer;
    FinalStatus: string;          // completed | partial | aborted
    ReportPath: string;           // JSON path in final_report_payload
  end;

  TShadowRunScheduler = class
  public
    // High-level orchestration
    class function StartSevenDayRun(const AStrategyUnitId, ARunCode, APlatform: string;
      out ARunId: string): string;

    class function AdvanceDay(const ARunId: string; out AOutcome: TDayAdvanceOutcome): string;
    class function CloseOutRun(const ARunId: string): TShadowRunCloseOut;

    // Query helpers
    class function GetCurrentDayIndex(const ARunId: string): Integer;
    class function GetRunStatus(const ARunId: string): string;
    class function GetDayStatus(const ARunId: string; ADayIndex: Integer): string;
  end;

implementation

uses
  FireDAC.Comp.Client;

const
  SEVEN_DAY_TARGET = 7;
  DEFAULT_TENANT_ID = '00000000-0000-0000-0000-000000000001';
  DEFAULT_CREATED_BY = '00000000-0000-0000-0000-000000000001';
  ATTENTION_BUDGET_MINUTES_PER_DAY = 30;  // P1 attention budget cap

{ ── TShadowRunScheduler ──────────────────────────────────────────── }

class function TShadowRunScheduler.StartSevenDayRun(
  const AStrategyUnitId, ARunCode, APlatform: string;
  out ARunId: string): string;
var
  DB: TArtifactDB;
  StartDate: TDate;
  EndDate: TDate;
  I: Integer;
  DayId: string;
  RunDateStr: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    StartDate := Date;
    EndDate := StartDate + (SEVEN_DAY_TARGET - 1);

    // Create run header
    ARunId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.shadow_run ' +
      '(run_code, status, start_date, end_date, primary_platform, ' +
      ' audience_stage_scope, theory_visibility, strategy_unit_id, run_goal_payload) ' +
      'VALUES (''' + ARunCode + ''', ''planned', ''' +
      FormatDateTime('YYYY-MM-DD', StartDate) + ''', ''' +
      FormatDateTime('YYYY-MM-DD', EndDate) + ''', ''' + APlatform + ''', ' +
      '''{S1,S2,S3}'', ''medium'', ' +
      IfThen(AStrategyUnitId <> '', '''' + AStrategyUnitId + '''', 'NULL') + ', ' +
      '''{"goal":"7-day Phase 2 shadow run","platform":"' + APlatform + '"}'') ' +
      'RETURNING id');

    // Pre-create 7 day rows (status=planned)
    for I := 0 to SEVEN_DAY_TARGET - 1 do
    begin
      RunDateStr := FormatDateTime('YYYY-MM-DD', StartDate + I);
      DayId := DB.InsertAndReturnId(
        'INSERT INTO artifactos.shadow_run_day ' +
        '(shadow_run_id, run_date, day_index, status, required_work_card_count) ' +
        'VALUES (''' + ARunId + ''', ''' + RunDateStr + ''', ' + IntToStr(I) + ', ' +
        '''planned'', 3) RETURNING id');
    end;

    // Transition run to running
    DB.Execute(
      'UPDATE artifactos.shadow_run SET status=''running'' ' +
      'WHERE id=''' + ARunId + ''' AND status=''planned''');

    Result := ARunId;
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunScheduler.AdvanceDay(
  const ARunId: string; out AOutcome: TDayAdvanceOutcome): string;
var
  DB: TArtifactDB;
  CurrentDayIndex: Integer;
  CurrentDayId, CurrentStatus: string;
  ReviewMinutes: Integer;
  BudgetExceeded: Boolean;
  NextStatus: string;
begin
  Result := '';
  AOutcome := daoSkipped;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Find earliest non-closed, non-skipped day
    CurrentDayIndex := GetCurrentDayIndex(ARunId);
    if CurrentDayIndex < 0 then
    begin
      AOutcome := daoAlreadyComplete;
      Exit;
    end;

    // Read current day row
    CurrentDayId := DB.ExecuteScalar(
      'SELECT id::text FROM artifactos.shadow_run_day ' +
      'WHERE shadow_run_id=''' + ARunId + ''' AND day_index=' + IntToStr(CurrentDayIndex));
    if CurrentDayId = '' then
    begin
      AOutcome := daoSkipped;
      Exit;
    end;

    CurrentStatus := DB.ExecuteScalar(
      'SELECT status FROM artifactos.shadow_run_day WHERE id=''' + CurrentDayId + '''');

    // Compute next state via state machine
    if CurrentStatus = 'planned' then
    begin
      NextStatus := 'generated';
      AOutcome := daoGenerated;
    end
    else if CurrentStatus = 'generated' then
    begin
      NextStatus := 'evening_reviewing';
      AOutcome := daoEveningReviewed;
    end
    else if CurrentStatus = 'evening_reviewing' then
    begin
      NextStatus := 'simulating';
      AOutcome := daoSimulated;
    end
    else if CurrentStatus = 'simulating' then
    begin
      NextStatus := 'reported';
      AOutcome := daoReported;
    end
    else if CurrentStatus = 'reported' then
    begin
      NextStatus := 'closed';
      AOutcome := daoReported;
    end
    else
    begin
      // closed, skipped, etc.
      NextStatus := 'closed';
      AOutcome := daoAlreadyComplete;
    end;

    // Attention budget check
    ReviewMinutes := StrToIntDef(DB.ExecuteScalar(
      'SELECT COALESCE(human_review_minutes, 0) FROM artifactos.shadow_run_day ' +
      'WHERE id=''' + CurrentDayId + ''''), 0);

    BudgetExceeded := ReviewMinutes > ATTENTION_BUDGET_MINUTES_PER_DAY;
    if BudgetExceeded and (NextStatus = 'reported') then
    begin
      // Mark overflow but continue
      DB.Execute(
        'UPDATE artifactos.shadow_run_day SET attention_budget_overflow=true ' +
        'WHERE id=''' + CurrentDayId + '''');
    end;

    // Transition
    DB.Execute(
      'UPDATE artifactos.shadow_run_day SET status=''' + NextStatus + ''' ' +
      'WHERE id=''' + CurrentDayId + ''' AND status=''' + CurrentStatus + '''');

    Result := CurrentDayId;
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunScheduler.CloseOutRun(
  const ARunId: string): TShadowRunCloseOut;
var
  DB: TArtifactDB;
  Q: TFDQuery;
  FinalStatus: string;
  ReportPayload: TJSONObject;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Q := DB.Query(
      'SELECT ' +
      '  COUNT(*) FILTER (WHERE status IN (''closed'',''reported'')) AS days_completed, ' +
      '  COUNT(*) FILTER (WHERE status=''skipped'') AS days_skipped, ' +
      '  COALESCE(SUM(human_review_minutes), 0) AS total_minutes, ' +
      '  COUNT(*) FILTER (WHERE attention_budget_overflow) AS budget_overflows ' +
      'FROM artifactos.shadow_run_day ' +
      'WHERE shadow_run_id=''' + ARunId + '''');
    try
      Result.DaysCompleted := Q.FieldByName('days_completed').AsInteger;
      Result.DaysSkipped := Q.FieldByName('days_skipped').AsInteger;
      Result.TotalHumanReviewMinutes := Q.FieldByName('total_minutes').AsInteger;
      Result.AttentionBudgetOverflows := Q.FieldByName('budget_overflows').AsInteger;
    finally
      Q.Free;
    end;

    Q := DB.Query(
      'SELECT COUNT(*) AS obs_count FROM artifactos.shadow_run_observation ' +
      'WHERE shadow_run_id=''' + ARunId + '''');
    try
      Result.TotalObservations := Q.FieldByName('obs_count').AsInteger;
    finally
      Q.Free;
    end;

    // Determine final status
    if (Result.DaysCompleted >= SEVEN_DAY_TARGET) and (Result.AttentionBudgetOverflows < 3) then
      FinalStatus := 'completed'
    else if Result.DaysCompleted > 0 then
      FinalStatus := 'partial'
    else
      FinalStatus := 'aborted';

    Result.FinalStatus := FinalStatus;

    // Build final report payload
    ReportPayload := TJSONObject.Create;
    try
      ReportPayload.AddPair('days_completed', TJSONNumber.Create(Result.DaysCompleted));
      ReportPayload.AddPair('days_skipped', TJSONNumber.Create(Result.DaysSkipped));
      ReportPayload.AddPair('total_observations', TJSONNumber.Create(Result.TotalObservations));
      ReportPayload.AddPair('total_human_review_minutes', TJSONNumber.Create(Result.TotalHumanReviewMinutes));
      ReportPayload.AddPair('attention_budget_overflows', TJSONNumber.Create(Result.AttentionBudgetOverflows));
      ReportPayload.AddPair('final_status', FinalStatus);
      ReportPayload.AddPair('phase1a_recommendation',
        IfThen(FinalStatus = 'completed',
          'proceed_to_real_publish_gate',
          'extend_shadow_or_remediate'));

      DB.Execute(
        'UPDATE artifactos.shadow_run SET status=''' + FinalStatus + ''', ' +
        'final_report_payload=' + QuotedStr(ReportPayload.ToJSON) + '::jsonb ' +
        'WHERE id=''' + ARunId + '''');
    finally
      ReportPayload.Free;
    end;

    Result.RunId := ARunId;
    Result.ReportPath := 'shadow_run.final_report_payload';
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunScheduler.GetCurrentDayIndex(const ARunId: string): Integer;
var
  DB: TArtifactDB;
  Status: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Status := DB.ExecuteScalar(
      'SELECT day_index::text FROM artifactos.shadow_run_day ' +
      'WHERE shadow_run_id=''' + ARunId + ''' ' +
      '  AND status NOT IN (''closed'',''skipped'') ' +
      'ORDER BY day_index ASC LIMIT 1');
    Result := StrToIntDef(Status, -1);
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunScheduler.GetRunStatus(const ARunId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalar(
      'SELECT status FROM artifactos.shadow_run WHERE id=''' + ARunId + '''');
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunScheduler.GetDayStatus(
  const ARunId: string; ADayIndex: Integer): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalar(
      'SELECT status FROM artifactos.shadow_run_day ' +
      'WHERE shadow_run_id=''' + ARunId + ''' AND day_index=' + IntToStr(ADayIndex));
  finally
    DB.Disconnect;
  end;
end;

end.
