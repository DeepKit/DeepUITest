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
  System.SysUtils, System.JSON,
  ArtifactOS.Services.ContractPipeline,
  ArtifactOS.Services.PromptAssembly,
  ArtifactOS.Services.GenerationService;

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
  else if SameText(ACommandType, 'prompt.assemble') then
  begin
    WriteLn('dispatch: prompt.assemble (', ACommandId, ')');
    // Parse contract_id from payload: {"contract_id":"<uuid>"}
    var ContractId: string;
    var JObj := TJSONObject.ParseJSONValue(APayloadJson) as TJSONObject;
    if JObj <> nil then
    try
      ContractId := JObj.GetValue<string>('contract_id', '');
    finally
      JObj.Free;
    end;
    if ContractId = '' then
    begin
      WriteLn(ErrOutput, '  prompt.assemble: missing contract_id in payload');
      Exit;
    end;
    var Result_: TAssemblyResult;
    if TPromptAssemblyService.AssembleContext(ContractId, pmStandard, False, '', Result_) then
    begin
      WriteLn('  context_pack_id=', Result_.Meta.ContextPackId);
      WriteLn('  pipeline_mode=', Result_.Meta.PipelineMode);
      WriteLn('  generation_mode=', Result_.Meta.GenerationMode);
      WriteLn('  token_estimate=', Result_.Meta.TokenEstimate);
      WriteLn('  injected=', Result_.Meta.InjectedSlots, ' skipped=', Result_.Meta.SkippedSlots);
      WriteLn('  prompt_chars=', Length(Result_.PromptText));
      Result := True;
    end
    else
      WriteLn(ErrOutput, '  prompt.assemble FAILED: ', Result_.ErrorMessage);
  end
  else if SameText(ACommandType, 'generation.ab_run') then
  begin
    WriteLn('dispatch: generation.ab_run (', ACommandId, ')');
    var ArtifactId: string;
    var ContractId: string;
    var JObj := TJSONObject.ParseJSONValue(APayloadJson) as TJSONObject;
    if JObj <> nil then
    try
      ArtifactId := JObj.GetValue<string>('artifact_id', '');
      ContractId := JObj.GetValue<string>('contract_id', '');
    finally
      JObj.Free;
    end;
    if (ArtifactId = '') or (ContractId = '') then
    begin
      WriteLn(ErrOutput, '  generation.ab_run: missing artifact_id or contract_id in payload');
      Exit;
    end;
    var SessionId: string;
    var WinnerVersionId: string;
    if TGenerationService.RunABGeneration(ArtifactId, ContractId, SessionId, WinnerVersionId) then
    begin
      WriteLn('  session_id=', SessionId);
      WriteLn('  winner_version_id=', WinnerVersionId);
      Result := True;
    end
    else
      WriteLn(ErrOutput, '  generation.ab_run FAILED');
  end
  else
  begin
    WriteLn(ErrOutput, 'dispatch: unknown command type ', ACommandType, ' (', ACommandId, ')');
  end;
end;

end.