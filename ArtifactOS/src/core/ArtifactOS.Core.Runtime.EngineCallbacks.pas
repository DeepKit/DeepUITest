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
  System.SysUtils,
  ArtifactOS.Services.ContractPipeline;

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
  else if SameText(ACommandType, 'contract_pipeline.create_minimal') then
  begin
    WriteLn('dispatch: contract_pipeline.create_minimal (', ACommandId, ')');
    var ContractId: string;
    var ChainJson: string;
    if TContractPipelineService.RunMinimalContractPipeline(
      'Smoke: Contract Pipeline', 'Verify minimal contract chain creation from the Delphi runtime.',
      'zhihu', 'sub', 'theory_driven', ContractId, ChainJson) then
    begin
      WriteLn('  contract_id=', ContractId);
      WriteLn('  chain=', ChainJson);
      Result := True;
    end
    else
      WriteLn(ErrOutput, '  FAILED: contract pipeline creation failed');
  end
  else if SameText(ACommandType, 'contract_pipeline.validate') then
  begin
    WriteLn('dispatch: contract_pipeline.validate (', ACommandId, ')');
    // Parse contract_id from payload
    var ContractId := APayloadJson;
    if TContractPipelineService.ValidateContractChain(ContractId) then
    begin
      WriteLn('  chain valid: ', ContractId);
      Result := True;
    end
    else
      WriteLn(ErrOutput, '  chain broken: ', ContractId);
  end
  else
  begin
    WriteLn(ErrOutput, 'dispatch: unknown command type ', ACommandType, ' (', ACommandId, ')');
  end;
end;

end.