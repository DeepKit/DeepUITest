unit ArtifactOS.Core.AutoTune;

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection;

type
  TAutoTuneResult = record
    Allowed: Boolean;
    Reason: string;
    HumanVisibleLevel: string; // digest / review_required
  end;

  TAutoTuneService = class
  private
    class function IsDenyListed(const AParamPath: string): Boolean;
    class function IsAllowListed(const AParamPath: string): Boolean;
    class function CrossesBand(const AParamPath, ABefore, AAfter: string): Boolean;
  public
    class function TryAutoTune(const ATargetType, ATargetId, AParamPath, ABefore, AAfter: string;
      const ATriggerRefs: string): TAutoTuneResult;
    class function GetAutoTuneHistory(const ATargetType, ATargetId: string): TArray<string>;
  end;

implementation

uses
  FireDAC.Comp.Client;

function InsertAndReturnId(const SQL: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnId(SQL);
end;

class function TAutoTuneService.IsDenyListed(const AParamPath: string): Boolean;
const
  DenyList: array[0..14] of string = (
    'source_pack.core',
    'canonical_text',
    'core_principles',
    'lighthouse_strategy',
    'case_objective.major',
    'account_long_term_positioning',
    'purpose_portfolio.major_ratio',
    'theory_visibility.level',
    'auto_publish_permission',
    'high_risk_topic_frequency',
    'redline_boundary',
    'commercial_commitment',
    'cross_platform_resource',
    'strategy_unit_maturity.upgrade',
    'delegation_policy.expand'
  );
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(DenyList) do
  begin
    if AParamPath.StartsWith(DenyList[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class function TAutoTuneService.IsAllowListed(const AParamPath: string): Boolean;
const
  AllowList: array[0..11] of string = (
    'publish_time.window_minor',
    'title_length.preference',
    'title.template_order',
    'opening_hook.template_order',
    'closing.template_order',
    'tag_count.max',
    'carousel_page_count',
    'summary_length',
    'paragraph_density',
    'sampling_rate.low_risk_up',
    'format_adapter_strategy',
    'expression_template_order.non_core'
  );
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(AllowList) do
  begin
    if AParamPath.StartsWith(AllowList[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class function TAutoTuneService.CrossesBand(const AParamPath, ABefore, AAfter: string): Boolean;
begin
  // Simplified band check: numeric params must stay within +/-20% range
  var BeforeVal: Double;
  var AfterVal: Double;
  if TryStrToFloat(ABefore, BeforeVal) and TryStrToFloat(AAfter, AfterVal) then
  begin
    if (AfterVal > BeforeVal * 1.2) or (AfterVal < BeforeVal * 0.8) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

class function TAutoTuneService.TryAutoTune(const ATargetType, ATargetId, AParamPath, ABefore, AAfter: string;
  const ATriggerRefs: string): TAutoTuneResult;
var
  DB: TArtifactDB;
  NeedsReview: Boolean;
begin
  Result.Allowed := True;
  Result.Reason := '';
  Result.HumanVisibleLevel := 'digest';

  // 1. DenyList check
  if IsDenyListed(AParamPath) then
  begin
    Result.Allowed := False;
    Result.Reason := 'Parameter is on AutoTune DenyList: ' + AParamPath;
    Result.HumanVisibleLevel := 'review_required';
    Exit;
  end;

  // 2. AllowList check
  if not IsAllowListed(AParamPath) then
  begin
    Result.Allowed := True; // not deny-listed but also not explicitly allowlisted — allow with review
    Result.HumanVisibleLevel := 'review_required';
    Result.Reason := 'Parameter not on explicit AutoTune AllowList: ' + AParamPath;
    Exit;
  end;

  // 3. Band check
  if CrossesBand(AParamPath, ABefore, AAfter) then
  begin
    Result.HumanVisibleLevel := 'review_required';
    Result.Reason := 'Parameter crosses AutoTune Band threshold: ' + AParamPath;
  end;

  // 4. Record event
  NeedsReview := Result.HumanVisibleLevel = 'review_required';
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute(
      'INSERT INTO artifactos.auto_tune_event (target_type, target_id, parameter_path, before_value, after_value, ' +
      'trigger_signal_refs, risk_level, requires_human_review, human_visible_level) ' +
      'VALUES (''' + ATargetType + ''', ''' + ATargetId + ''', ''' + AParamPath + ''', ''' + ABefore + ''', ''' + AAfter + ''', ' +
      '''' + ATriggerRefs + ''', ''low'', ' + LowerCase(BoolToStr(NeedsReview, True)) + ', ''' + Result.HumanVisibleLevel + ''')');
  finally
    DB.Disconnect;
  end;
end;

class function TAutoTuneService.GetAutoTuneHistory(const ATargetType, ATargetId: string): TArray<string>;
var
  DB: TArtifactDB;
  Q: TFDQuery;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Q := DB.Query(
      'SELECT parameter_path || '': '' || before_value || '' → '' || after_value ' +
      'FROM artifactos.auto_tune_event ' +
      'WHERE target_type=''' + ATargetType + ''' AND target_id=''' + ATargetId + ''' ORDER BY created_at DESC LIMIT 20');
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