unit ArtifactOS.Core.Runtime.EngineCallbacks;

interface

uses
  ArtifactOS.Core.Runtime.Types;

type
  TEngineCallbacks = class
  public
    class function DispatchCommand(const ACommandId, ACommandType, APayloadJson: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

class function TEngineCallbacks.DispatchCommand(const ACommandId, ACommandType, APayloadJson: string): Boolean;
begin
  Result := False;

  if SameText(ACommandType, 'runtime.status.refresh') then
  begin
    WriteLn('dispatch: runtime.status.refresh (', ACommandId, ')');
    Result := True;
  end
  else if SameText(ACommandType, 'readiness.check') then
  begin
    WriteLn('dispatch: readiness.check (', ACommandId, ')');
    Result := True;
  end
  else if SameText(ACommandType, 'shadow_run.prepare_day') then
  begin
    WriteLn('dispatch: shadow_run.prepare_day (', ACommandId, ') - payload=', APayloadJson);
    Result := True;
  end
  else if SameText(ACommandType, 'daily_report.generate') then
  begin
    WriteLn('dispatch: daily_report.generate (', ACommandId, ') - payload=', APayloadJson);
    Result := True;
  end
  else if SameText(ACommandType, 'publish.intent.create') then
  begin
    WriteLn('dispatch: publish.intent.create (', ACommandId, ') - payload=', APayloadJson);
    Result := True;
  end
  else if SameText(ACommandType, 'engine.warmup') then
  begin
    WriteLn('dispatch: engine.warmup (', ACommandId, ')');
    Result := True;
  end
  else
  begin
    WriteLn(ErrOutput, 'dispatch: unknown command type ', ACommandType, ' (', ACommandId, ')');
  end;
end;

end.