unit ArtifactOS.Services.ShadowRun;

interface

uses
  System.SysUtils,
  ArtifactOS.Core.DB.Connection;

type
  TShadowRunService = class
  public
    class function CreateRun(const ARunCode: string;
      const AStartDate, AEndDate: string; const APlatform: string): string;
    class function CreateDay(const ARunId: string; const ARunDate: string;
      ADayIndex: Integer): string;
    class function CreateObservation(const ARunId, AShadowRunDayId, AObsType: string;
      const AArtifactOSRef, ALegacyRef: string; ADeviationType, ASeverity: string): string;
    class function StartRun(const ARunId: string): string;
    class function CompleteRun(const ARunId: string): string;
    class function AbortRun(const ARunId: string; const AReason: string): string;
  end;

implementation

uses
  FireDAC.Comp.Client;

function InsertAndReturnId(const SQL: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnId(SQL);
end;

class function TShadowRunService.CreateRun(const ARunCode: string;
  const AStartDate, AEndDate: string; const APlatform: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.shadow_run (run_code, status, start_date, end_date, primary_platform, audience_stage_scope, theory_visibility, run_goal_payload) ' +
      'VALUES (''' + ARunCode + ''', ''planned'', ''' + AStartDate + ''', ''' + AEndDate + ''', ''' + APlatform + ''', ' +
      '''{S1,S2,S3}'', ''medium'', ''{"goal":"Phase 1A shadow run"}'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunService.StartRun(const ARunId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute('UPDATE artifactos.shadow_run SET status=''running'' WHERE id=''' + ARunId + ''' AND status=''planned''');
    Result := ARunId;
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunService.CompleteRun(const ARunId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute('UPDATE artifactos.shadow_run SET status=''completed'' WHERE id=''' + ARunId + ''' AND status=''running''');
    Result := ARunId;
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunService.AbortRun(const ARunId: string; const AReason: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.shadow_run SET status=:status, final_report_payload=:payload::jsonb WHERE id=:id',
      Format('{"status":"aborted","payload":{"abort_reason":"%s"},"id":"%s"}', [AReason, ARunId]));
    Result := ARunId;
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunService.CreateDay(const ARunId: string; const ARunDate: string;
  ADayIndex: Integer): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.shadow_run_day (shadow_run_id, run_date, day_index, status) ' +
      'VALUES (''' + ARunId + ''', ''' + ARunDate + ''', ' + IntToStr(ADayIndex) + ', ''planned'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TShadowRunService.CreateObservation(const ARunId, AShadowRunDayId, AObsType: string;
  const AArtifactOSRef, ALegacyRef: string; ADeviationType, ASeverity: string): string;
var
  DB: TArtifactDB;
  SQL: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    SQL := 'INSERT INTO artifactos.shadow_run_observation (shadow_run_id, shadow_run_day_id, observation_type, artifactos_ref, legacy_ref, deviation_type, severity) ' +
           'VALUES (''' + ARunId + ''', ''' + AShadowRunDayId + ''', ''' + AObsType + ''', ''' + AArtifactOSRef + ''', ''' + ALegacyRef + ''', ''' + ADeviationType + ''', ''' + ASeverity + ''') ' +
           'RETURNING id';
    Result := DB.InsertAndReturnId(SQL);
  finally
    DB.Disconnect;
  end;
end;

end.