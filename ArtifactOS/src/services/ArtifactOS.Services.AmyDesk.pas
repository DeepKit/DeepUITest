unit ArtifactOS.Services.AmyDesk;

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection;

type
  TWorkCardInfo = record
    CardType: string;
    Title: string;
    Summary: string;
    Priority: string;
    ReviewRequirement: string;
    SourceType: string;
    SourceId: string;
  end;

  TAmyDeskService = class
  public
    class function CreateWorkCard(const AInfo: TWorkCardInfo): string;
    class function CreatePanel(const AWorkCardId, APanelType, AContextType, AContextId: string): string;
    class function AddPanelOption(const APanelId, AOptionNo, ALabel, AActionType: string;
      ARecommended: Boolean = False): string;
    class function GenerateTodayDesk(const ADayCaseId: string): TArray<string>;
    class function MustHandleCount(const ABudgetDate: string): Integer;
    class function CanAddMustHandle(const ABudgetDate: string): Boolean;
  end;

implementation

uses
  FireDAC.Comp.Client;

function InsertId(const DB: TArtifactDB; const SQL: string): string;
var
  Q: TFDQuery;
begin
  Q := DB.Query(SQL);
  try
    Result := Q.Fields[0].AsString;
  finally
    Q.Free;
  end;
end;

class function TAmyDeskService.CreateWorkCard(const AInfo: TWorkCardInfo): string;
var
  DB: TArtifactDB;
  SQL: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    SQL := 'INSERT INTO artifactos.work_card (card_type, source_type, source_id, priority, review_requirement, title, summary, recommended_action_no) ' +
           'VALUES (''' + AInfo.CardType + ''', ''' + AInfo.SourceType + ''', ''' + AInfo.SourceId + ''', ''' + AInfo.Priority + ''', ''' + AInfo.ReviewRequirement + ''', ''' + AInfo.Title + ''', ''' + AInfo.Summary + ''', 1) ' +
           'RETURNING id';
    Result := InsertId(DB, SQL);
  finally
    DB.Disconnect;
  end;
end;

class function TAmyDeskService.CreatePanel(const AWorkCardId, APanelType, AContextType, AContextId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := InsertId(DB,
      'INSERT INTO artifactos.prepared_action_panel (work_card_id, panel_type, context_type, context_id) ' +
      'VALUES (''' + AWorkCardId + ''', ''' + APanelType + ''', ''' + AContextType + ''', ''' + AContextId + ''') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TAmyDeskService.AddPanelOption(const APanelId, AOptionNo, ALabel, AActionType: string;
  ARecommended: Boolean): string;
var
  DB: TArtifactDB;
  Reason: string;
  Role: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    if ARecommended then
      Reason := 'Recommended action'
    else
      Reason := 'Alternative';

    if AOptionNo = '9' then
      Role := 'regenerate'
    else if AOptionNo = '0' then
      Role := 'human_input'
    else
      Role := 'prepared';

    Result := InsertId(DB,
      'INSERT INTO artifactos.prepared_action_option (panel_id, option_no, option_role, label, action_type, recommendation_reason, risk_level, display_order) ' +
      'VALUES (''' + APanelId + ''', ''' + AOptionNo + ''', ''' + Role + ''', ''' + ALabel + ''', ''' + AActionType + ''', ''' + Reason + ''', ''normal'', ' + AOptionNo + ') ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TAmyDeskService.GenerateTodayDesk(const ADayCaseId: string): TArray<string>;
var
  DB: TArtifactDB;
  CardId, PanelId: string;
  Info: TWorkCardInfo;
  Cards: TArray<string>;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    SetLength(Cards, 0);

    // 1. Daily overview card
    Info.CardType := 'DailyOverviewCard';
    Info.Title := 'Today Summary';
    Info.Summary := 'Shadow Run Day ' + DB.ExecuteScalar('SELECT TO_CHAR(current_date, ''YYYY-MM-DD'')');
    Info.Priority := 'high';
    Info.ReviewRequirement := 'must_handle';
    Info.SourceType := 'case_record';
    Info.SourceId := ADayCaseId;
    CardId := CreateWorkCard(Info);
    PanelId := CreatePanel(CardId, 'daily_overview', 'case_record', ADayCaseId);
    AddPanelOption(PanelId, '1', 'Proceed with today plan', 'approve', True);
    AddPanelOption(PanelId, '6', 'Pause all', 'hold', False);
    AddPanelOption(PanelId, '8', 'Delegate to Amy', 'no_op', False);
    SetLength(Cards, Length(Cards) + 1);
    Cards[High(Cards)] := CardId;

    // 2. DailyCalibrationReview card (if candidates exist)
    var HasCandidate := DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.daily_calibration_review WHERE review_date=current_date AND status=''candidate''');
    if HasCandidate <> '0' then
    begin
      Info.CardType := 'DailyCalibrationReviewCard';
      Info.Title := 'Daily Calibration Review';
      Info.Summary := '1 artifact recommended for your review';
      Info.Priority := 'normal';
      Info.ReviewRequirement := 'recommended';
      Info.SourceType := 'daily_calibration_review';
      Info.SourceId := DB.ExecuteScalar('SELECT id::text FROM artifactos.daily_calibration_review WHERE review_date=current_date AND status=''candidate'' LIMIT 1');
      CardId := CreateWorkCard(Info);
      PanelId := CreatePanel(CardId, 'calibration_review', 'daily_calibration_review', Info.SourceId);
      AddPanelOption(PanelId, '1', 'Mark as positive example', 'approve', True);
      AddPanelOption(PanelId, '6', 'Skip today', 'no_op', False);
      AddPanelOption(PanelId, '7', 'Mark as negative example', 'reject', False);
      SetLength(Cards, Length(Cards) + 1);
      Cards[High(Cards)] := CardId;
    end;

    Result := Cards;
  finally
    DB.Disconnect;
  end;
end;

class function TAmyDeskService.MustHandleCount(const ABudgetDate: string): Integer;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := StrToIntDef(DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.work_card WHERE review_requirement=''must_handle'' AND status=''prepared'''), 0);
  finally
    DB.Disconnect;
  end;
end;

class function TAmyDeskService.CanAddMustHandle(const ABudgetDate: string): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var Used := StrToIntDef(DB.ExecuteScalar(
      'SELECT used_must_review FROM artifactos.human_attention_budget WHERE budget_date=''' + ABudgetDate + ''' AND status=''active'' LIMIT 1'), 0);
    var Max := StrToIntDef(DB.ExecuteScalar(
      'SELECT max_must_review FROM artifactos.human_attention_budget WHERE budget_date=''' + ABudgetDate + ''' AND status=''active'' LIMIT 1'), 3);
    Result := Used < Max;
  finally
    DB.Disconnect;
  end;
end;

end.