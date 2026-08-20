{ ============================================================================
  ArtifactOS.Services.RealPublishGate

  P2-81: Delphi-side runner for the 12-condition RealPublishGate.

  The gate logic itself lives in PostgreSQL (migration 037). This unit is
  the Delphi facade that:
    - Sets run_mode / legacy_stage_rank / rollback_ready session settings.
    - Calls artifactos.check_real_publish_gate().
    - Parses the JSONB result into a typed record.
    - Emits a CognitiveDisturbanceEvent if any condition fails.
    - Logs the gate decision for audit.

  Roadmap reference: 03.[蓝图]-实施路线图-Roadmap.md §5.3 接管闭合.
  ============================================================================ }

unit ArtifactOS.Services.RealPublishGate;

interface

uses
  System.SysUtils, System.StrUtils, System.JSON,
  ArtifactOS.Core.DB.Connection;

type
  TGateStatus = (gsPassed, gsNeedsHuman, gsFailed, gsBlocked);

  TGateCondition = record
    Key: string;
    Passed: Boolean;
  end;

  TRealPublishGateResult = record
    Status: TGateStatus;
    Reason: string;
    PassCount: Integer;
    Conditions: TArray<TGateCondition>;
    RawJson: string;
    function StatusText: string;
  end;

  TRealPublishGateRunner = class
  public
    /// <summary>
    /// Configure session-level gate inputs before evaluation. Mirrors the
    /// real_publish_gate_inputs view defaults.
    /// </summary>
    class procedure ConfigureSession(ARunMode: string = 'shadow';
      ALegacyStageRank: Integer = 0; ARollbackReady: Boolean = False);

    /// <summary>
    /// Evaluate the 12 conditions for an optional publication package +
    /// quality snapshot. Returns parsed result.
    /// </summary>
    class function Evaluate(const APublicationPackageId, AQualitySnapshotId: string): TRealPublishGateResult;

    /// <summary>
    /// Convenience: evaluate without specific package context (uses global
    /// inputs view defaults).
    /// </summary>
    class function EvaluateGlobal: TRealPublishGateResult;

    /// <summary>
    /// On failure, emit CognitiveDisturbanceEvent so the strategy unit's
    /// traffic light escalates. Returns the new event id.
    /// </summary>
    class function EmitDisturbanceOnFailure(const AArtifactId: string;
      const AResult: TRealPublishGateResult): string;
  end;

implementation

uses
  FireDAC.Comp.Client,
  ArtifactOS.Services.CognitiveGovernance;

{ ── TRealPublishGateResult helpers ───────────────────────────────── }

function TRealPublishGateResult.StatusText: string;
begin
  case Status of
    gsPassed: Result := 'passed';
    gsNeedsHuman: Result := 'needs_human';
    gsFailed: Result := 'failed';
    gsBlocked: Result := 'blocked';
  else
    Result := 'unknown';
  end;
end;

{ ── TRealPublishGateRunner ───────────────────────────────────────── }

class procedure TRealPublishGateRunner.ConfigureSession(
  ARunMode: string; ALegacyStageRank: Integer; ARollbackReady: Boolean);
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Execute('SET LOCAL artifactos.run_mode = ''' + ARunMode + '''');
    DB.Execute('SET LOCAL artifactos.legacy_stage_rank = ''' + IntToStr(ALegacyStageRank) + '''');
    DB.Execute('SET LOCAL artifactos.rollback_ready = ''' + LowerCase(BoolToStr(ARollbackReady, True)) + '''');
  finally
    DB.Disconnect;
  end;
end;

class function TRealPublishGateRunner.Evaluate(
  const APublicationPackageId, AQualitySnapshotId: string): TRealPublishGateResult;
var
  DB: TArtifactDB;
  JsonText: string;
  JObj: TJSONObject;
  JCond: TJSONObject;
  I: Integer;
  Pair: TJSONPair;
  Cond: TGateCondition;
  StatusStr: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    if (APublicationPackageId = '') and (AQualitySnapshotId = '') then
      JsonText := DB.ExecuteScalarJson(
        'SELECT artifactos.check_real_publish_gate()::text', '{}')
    else
      JsonText := DB.ExecuteScalarJson(
        'SELECT artifactos.check_real_publish_gate(' +
        IfThen(APublicationPackageId <> '', '''' + APublicationPackageId + '''', 'NULL') + ', ' +
        IfThen(AQualitySnapshotId <> '', '''' + AQualitySnapshotId + '''', 'NULL') + ')::text', '{}');
  finally
    DB.Disconnect;
  end;

  Result.RawJson := JsonText;
  JObj := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
  if JObj = nil then
  begin
    Result.Status := gsBlocked;
    Result.Reason := 'Failed to parse gate result JSON';
    Result.PassCount := 0;
    SetLength(Result.Conditions, 0);
    Exit;
  end;

  try
    StatusStr := JObj.GetValue<string>('gate_status', 'blocked');
    if StatusStr = 'passed' then Result.Status := gsPassed
    else if StatusStr = 'needs_human' then Result.Status := gsNeedsHuman
    else if StatusStr = 'failed' then Result.Status := gsFailed
    else Result.Status := gsBlocked;

    Result.Reason := JObj.GetValue<string>('reason', '');
    Result.PassCount := JObj.GetValue<Integer>('pass_count', 0);

    JCond := JObj.GetValue<TJSONObject>('conditions');
    if JCond <> nil then
    begin
      SetLength(Result.Conditions, JCond.Count);
      I := 0;
      for Pair in JCond do
      begin
        Cond.Key := Pair.JsonString.Value;
        Cond.Passed := (Pair.JsonValue as TJSONBool).AsBoolean;
        Result.Conditions[I] := Cond;
        Inc(I);
      end;
    end;
  finally
    JObj.Free;
  end;
end;

class function TRealPublishGateRunner.EvaluateGlobal: TRealPublishGateResult;
begin
  Result := Evaluate('', '');
end;

class function TRealPublishGateRunner.EmitDisturbanceOnFailure(
  const AArtifactId: string; const AResult: TRealPublishGateResult): string;
var
  FailedKeys: string;
  Cond: TGateCondition;
begin
  Result := '';
  if AResult.Status = gsPassed then Exit;

  FailedKeys := '';
  for Cond in AResult.Conditions do
  begin
    if not Cond.Passed then
    begin
      if FailedKeys <> '' then FailedKeys := FailedKeys + ',';
      FailedKeys := FailedKeys + Cond.Key;
    end;
  end;

  TCognitiveGovernance.RecordDisturbance(
    AArtifactId,
    '',                              // strategy_unit_id (resolved by governance)
    'gate_failure',                  // disturbance_type
    IfThen(AResult.Status = gsFailed, 'high', 'medium'),  // severity
    '{"failed_conditions":[''' + FailedKeys + '''],"reason":' +
      TJSONString.Create(AResult.Reason).ToJSON + '}',
    Result);
end;

end.
