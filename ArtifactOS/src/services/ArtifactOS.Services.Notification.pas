unit ArtifactOS.Services.Notification;

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection;

type
  TNotificationService = class
  public
    class function CreateChannel(const ACode, AType: string): string;
    class function BindWeixin(const AChannelId: string): string;
    class function SendDailyReport(const ADayCaseId, AReportDate: string;
      const ASummary, ADecisions, ARisks, ATomorrowRec: string): string;
    class function MarkNotified(const AReportId: string): string;
    class function MarkOpened(const AReportId: string): string;
    class function MarkCompleted(const AReportId: string): string;
    class function GetReportsForDate(const ADate: string): TArray<string>;
  end;

implementation

uses
  FireDAC.Comp.Client;

function InsertAndReturnId(const SQL: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnId(SQL);
end;

class function TNotificationService.CreateChannel(const ACode, AType: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.notification_channel (channel_code, channel_type, channel_name, status) ' +
      'VALUES (''' + ACode + ''', ''' + AType + ''', ''Amy ' + AType + ' Channel'', ''binding'') ' +
      'ON CONFLICT (tenant_id, channel_code) DO UPDATE SET last_seen_at=now() ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TNotificationService.BindWeixin(const AChannelId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.amy_weixin_channel (notification_channel_id, binding_status) ' +
      'VALUES (''' + AChannelId + ''', ''qr_pending'') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TNotificationService.SendDailyReport(const ADayCaseId, AReportDate: string;
  const ASummary, ADecisions, ARisks, ATomorrowRec: string): string;
var
  DB: TArtifactDB;
  ChannelId: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Ensure we have a channel
    ChannelId := DB.ExecuteScalar(
      'SELECT id::text FROM artifactos.notification_channel WHERE channel_type=''weixin'' LIMIT 1');
    if ChannelId = '' then
      ChannelId := CreateChannel('weixin_channel_01', 'weixin');

    // Create daily report
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.daily_report (report_date, day_case_id, summary_text, completed_summary, decision_summary, risk_summary, tomorrow_recommendation) ' +
      'VALUES (''' + AReportDate + ''', ''' + ADayCaseId + ''', ''' + ASummary + ''', ' +
      '''{"completed":0}'', ''' + ADecisions + ''', ''' + ARisks + ''', ''' + ATomorrowRec + ''') ' +
      'ON CONFLICT (tenant_id, report_date, day_case_id) DO UPDATE SET ' +
      'summary_text=''' + ASummary + ''', decision_summary=''' + ADecisions + ''', risk_summary=''' + ARisks + ''', tomorrow_recommendation=''' + ATomorrowRec + '''' +
      'RETURNING id');

    // Create entry card (for WeChat delivery)
    DB.InsertAndReturnId('INSERT INTO artifactos.daily_report_entry_card (daily_report_id, notification_event_id, prepared_action_panel_id, headline, summary_payload) ' +
      'VALUES (''' + Result + ''', NULL, NULL, ''Daily Report: ' + AReportDate + ''', ''{"summary":"' + ASummary + '"}'') ' +
      'ON CONFLICT (tenant_id, daily_report_id) DO NOTHING');
  finally
    DB.Disconnect;
  end;
end;

class function TNotificationService.MarkNotified(const AReportId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.daily_report SET status=''notified'', notified_at=now() WHERE id=:id',
      '{"id":"' + AReportId + '"}');
    Result := AReportId;
  finally
    DB.Disconnect;
  end;
end;

class function TNotificationService.MarkOpened(const AReportId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.daily_report SET status=''opened'' WHERE id=:id AND status IN (''prepared'',''notified'')',
      '{"id":"' + AReportId + '"}');
    Result := AReportId;
  finally
    DB.Disconnect;
  end;
end;

class function TNotificationService.MarkCompleted(const AReportId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.daily_report SET status=''completed'' WHERE id=:id AND status=''opened''',
      '{"id":"' + AReportId + '"}');
    Result := AReportId;
  finally
    DB.Disconnect;
  end;
end;

class function TNotificationService.GetReportsForDate(const ADate: string): TArray<string>;
var
  DB: TArtifactDB;
  Q: TFDQuery;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Q := DB.Query('SELECT id::text FROM artifactos.daily_report WHERE report_date=''' + ADate + ''' ORDER BY created_at');
    try
      SetLength(Result, 0);
      while not Q.Eof do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Q.Fields[0].AsString;
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

end.