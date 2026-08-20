unit DeepAxis.Pipeline.StateMachine;

interface

uses
  System.SysUtils, System.DateUtils,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts;

type
  /// <summary>
  ///   Dual-axis state machine for contact lifecycle.
  ///   Axis 1 (0-9): Fact state — derived from metadata (P0 covers 0-3).
  ///   Axis 2: Transition events — detected from signal changes.
  ///   P0: Read-only. No auto-transition. Only derive state from metadata.
  /// </summary>
  TContactStateMachine = class(TInterfacedObject, IStateMachine)
  private
    function DeriveStateFromMetadata(const AContact: TContact): TAxis1State;
    function GetDaysSinceLastInteraction(const AContact: TContact): Integer;
  public
    function GetAxis1State(const AContact: TContact): TAxis1State;
    function TransitState(const AContact: TContact;
      const ATrigger: string): TAxis1State;
    function GetTransitionEvents(const AContact: TContact): TArray<string>;
    function GetStateLabel(const AState: TAxis1State): string;
  end;

implementation

{ TContactStateMachine }

function TContactStateMachine.GetDaysSinceLastInteraction(const AContact: TContact): Integer;
begin
  if AContact.LastSeen = 0 then
    Result := 999
  else
    Result := DaysBetween(Now, AContact.LastSeen);
end;

function TContactStateMachine.DeriveStateFromMetadata(const AContact: TContact): TAxis1State;
var
  LDaysSince: Integer;
begin
  // P0: Only states 0-3 are derivable from metadata alone.
  // States 4-9 require M1 content analysis or user confirmation.

  if AContact.IsPrivate or AContact.IsUnknown then
    Exit(9); // 不适用

  LDaysSince := GetDaysSinceLastInteraction(AContact);

  if LDaysSince = 999 then
    Exit(0); // 关联未激活: never interacted

  if LDaysSince > 90 then
    Exit(8); // 已流失: extreme long silence

  if LDaysSince > 30 then
    Exit(7); // 降温中: in decline

  if LDaysSince <= 7 then
    Exit(2); // 培育中: active interaction

  Exit(0); // Default: 关联未激活
end;

function TContactStateMachine.GetAxis1State(const AContact: TContact): TAxis1State;
begin
  Result := DeriveStateFromMetadata(AContact);
end;

function TContactStateMachine.TransitState(const AContact: TContact;
  const ATrigger: string): TAxis1State;
begin
  // BUG-051 #86: 触发信号驱动的状态推进 (P1.5 规则, 非纯只读)。
  // 规则: 信号 → 状态, 仅当证据充分时推进; 不自动降级人工确认过的状态。
  Result := DeriveStateFromMetadata(AContact);

  if ATrigger = '' then
    Exit;

  // 已成交 (ProductCount>0) + 活跃 → 首购/复购带
  if AContact.ProductCount > 0 then
  begin
    if GetDaysSinceLastInteraction(AContact) <= 7 then
      Result := 5  // 首单 (有活跃产品关联)
    else
      Result := 7; // 降温中 (有产品但长期沉默)
    Exit;
  end;

  // 触发信号: 意向/洽谈类 (M1 关键词或人工确认)
  if (Pos('interest', ATrigger) > 0) or (Pos('意向', ATrigger) > 0) then
    Exit(3); // 有兴趣
  if (Pos('negotiate', ATrigger) > 0) or (Pos('洽谈', ATrigger) > 0) then
    Exit(4); // 洽谈中

  // 营销关键词命中 → 潜在产品关联信号 (状态 1: 知道)
  if (Pos('marketing', ATrigger) > 0) and (AContact.MarketingKeywordHitCount > 0) then
    Exit(1);
end;

function TContactStateMachine.GetTransitionEvents(const AContact: TContact): TArray<string>;
begin
  // BUG-051 #86: 返回派生出的 Axis 2 事件 (供 UI/审计展示)。
  Result := nil;

  // 降温信号 (7)
  if (GetDaysSinceLastInteraction(AContact) > 30) and
     (GetDaysSinceLastInteraction(AContact) <= 90) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'cooldown:days>' + IntToStr(30);
  end;

  // 流失风险 (8)
  if GetDaysSinceLastInteraction(AContact) > 90 then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'churn_risk:days>' + IntToStr(90);
  end;

  // 营销关键词命中 → 意向候选
  if AContact.MarketingKeywordHitCount > 0 then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'marketing_hit:count=' + IntToStr(AContact.MarketingKeywordHitCount);
  end;

  // 广告计数达上限 → 删除候选信号
  if AContact.AdCount >= AD_MAX_COUNT then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'ad_exhausted:count=' + IntToStr(AContact.AdCount);
  end;
end;

function TContactStateMachine.GetStateLabel(const AState: TAxis1State): string;
begin
  Result := Axis1StateToChinese(AState);
end;

end.