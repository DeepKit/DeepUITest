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
  // P0: Read-only — no auto-transition.
  // Returns current derived state. In P2+, this will apply state changes
  // based on triggers and confidence thresholds.
  Result := GetAxis1State(AContact);
end;

function TContactStateMachine.GetTransitionEvents(const AContact: TContact): TArray<string>;
begin
  // P0: No transition events are generated.
  // In P2+, this returns the list of Axis 2 events that triggered state changes.
  Result := nil;
end;

function TContactStateMachine.GetStateLabel(const AState: TAxis1State): string;
begin
  Result := Axis1StateToChinese(AState);
end;

end.