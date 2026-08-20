unit ArtifactOS.Services.CognitiveGovernance;

// L3-69/70/71/72/73: Cognitive governance layer
// Manages cognition traces, boundary decisions, publication seals,
// recall cards, and cognitive disturbance events.

interface

uses
  System.SysUtils, System.JSON, System.Math, System.StrUtils,
  ArtifactOS.Core.DB.Connection;

type
  TCognitionState = (csWrite, csNotWrite, csPublish, csFreeze);

  TBoundaryDecision = (
    bdWriteFreely, bdWriteCautious, bdDraftOnly,
    bdRestrictedPublish, bdNotWrite, bdFreeze
  );

  TCognitiveGovernance = class
  public
    // L3-70: Record a cognition trace
    class function RecordCognitionTrace(const AArtifactId, AVersionId: string;
      ATraceType: TCognitionState; const AContext, APredictions, ARationale: string;
      out ATraceId: string): Boolean;

    // L3-71: Make a boundary decision
    class function MakeBoundaryDecision(const AArtifactId, ACognitionTraceId: string;
      ADecision: TBoundaryDecision; const AFactors: string;
      out ADecisionId: string): Boolean;

    // L3-72: Create a publication seal
    class function CreatePublicationSeal(const AArtifactId, AVersionId, APackageId: string;
      out ASealId: string): Boolean;

    // L3-72: Create a recall card
    class function CreateRecallCard(const ASealId, AArtifactId: string;
      ARecallType: string; const AReason: string;
      out ACardId: string): Boolean;

    // L3-69: Record a cognitive disturbance event
    class function RecordDisturbance(const AArtifactId, ATraceId: string;
      ADisturbanceType, ASeverity: string; const ADetails: string;
      out AEventId: string): Boolean;

    // L3-73: Freeze an artifact (mark frozen state)
    class function FreezeArtifact(const AArtifactId, AReason: string): Boolean;

    // L3-73: Unfreeze an artifact
    class function UnfreezeArtifact(const AArtifactId, AJustification: string): Boolean;

    // Helper: CognitionState to string
    class function CognitionStateToStr(AState: TCognitionState): string;
    class function BoundaryDecisionToStr(ADecision: TBoundaryDecision): string;
  end;

implementation

{ TCognitiveGovernance }

class function TCognitiveGovernance.CognitionStateToStr(AState: TCognitionState): string;
begin
  case AState of
    csWrite:     Result := 'write';
    csNotWrite:  Result := 'not_write';
    csPublish:   Result := 'publish';
    csFreeze:    Result := 'freeze';
  else
    Result := 'unknown';
  end;
end;

class function TCognitiveGovernance.BoundaryDecisionToStr(ADecision: TBoundaryDecision): string;
begin
  case ADecision of
    bdWriteFreely:       Result := 'write_freely';
    bdWriteCautious:     Result := 'write_cautious';
    bdDraftOnly:         Result := 'draft_only';
    bdRestrictedPublish: Result := 'restricted_publish';
    bdNotWrite:          Result := 'not_write';
    bdFreeze:            Result := 'freeze';
  else
    Result := 'unknown';
  end;
end;

class function TCognitiveGovernance.RecordCognitionTrace(const AArtifactId, AVersionId: string;
  ATraceType: TCognitionState; const AContext, APredictions, ARationale: string;
  out ATraceId: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  ATraceId := '';
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    ATraceId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.cognition_trace ' +
      '  (artifact_id, artifact_version_id, trace_type, context_snapshot, predictions, decision_rationale) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AVersionId + ''', ' +
      '  ''' + CognitionStateToStr(ATraceType) + ''', ' +
      '  $ctx$' + AContext + '$ctx$::jsonb, ' +
      '  $pred$' + APredictions + '$pred$::jsonb, ' +
      '  $rat$' + ARationale + '$rat$) ' +
      'RETURNING id::text');

    WriteLn(Format('[CognitionTrace] recorded: id=%s type=%s artifact=%s',
      [ATraceId, CognitionStateToStr(ATraceType), AArtifactId]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TCognitiveGovernance.MakeBoundaryDecision(const AArtifactId, ACognitionTraceId: string;
  ADecision: TBoundaryDecision; const AFactors: string;
  out ADecisionId: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  ADecisionId := '';
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    ADecisionId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.boundary_decision ' +
      '  (artifact_id, cognition_trace_id, decision, boundary_factors, decided_by) ' +
      'VALUES (''' + AArtifactId + ''', ' +
      '  ' + IfThen(ACognitionTraceId <> '', '''' + ACognitionTraceId + '''', 'NULL') + ', ' +
      '  ''' + BoundaryDecisionToStr(ADecision) + ''', ' +
      '  $factors$' + AFactors + '$factors$::jsonb, ' +
      '  ''ai'') ' +
      'RETURNING id::text');

    WriteLn(Format('[BoundaryDecision] recorded: id=%s decision=%s artifact=%s',
      [ADecisionId, BoundaryDecisionToStr(ADecision), AArtifactId]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TCognitiveGovernance.CreatePublicationSeal(const AArtifactId, AVersionId, APackageId: string;
  out ASealId: string): Boolean;
var
  DB: TArtifactDB;
  ContentHash: string;
  SealName: string;
  PackageRef: string;
begin
  Result := False;
  ASealId := '';
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Compute content hash from version payload
    ContentHash := DB.ExecuteScalar(
      'SELECT encode(digest(assembled_payload::text, ''sha256''), ''hex'') ' +
      'FROM artifactos.artifact_version WHERE id=''' + AVersionId + '''');

    if ContentHash = '' then
    begin
      WriteLn(ErrOutput, '[PubSeal] Cannot compute hash: version not found');
      Exit;
    end;

    // Generate seal name
    SealName := 'seal_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '_' + Copy(ContentHash, 1, 8);

    PackageRef := IfThen(APackageId <> ', ', '''' + APackageId + '''', 'NULL');

    ASealId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.publication_seal ' +
      '  (artifact_id, artifact_version_id, publication_package_id, seal_id, content_hash, sealed_by) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AVersionId + ''', ' + PackageRef + ', ' +
      '  ''' + SealName + ''', ''' + ContentHash + ''', ''system'') ' +
      'RETURNING id::text');

    WriteLn(Format('[PubSeal] created: id=%s seal=%s hash=%s', [ASealId, SealName, Copy(ContentHash, 1, 16)]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TCognitiveGovernance.CreateRecallCard(const ASealId, AArtifactId: string;
  ARecallType: string; const AReason: string;
  out ACardId: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  ACardId := '';
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    ACardId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.recall_card ' +
      '  (seal_id, artifact_id, recall_type, recall_reason, initiated_by) ' +
      'VALUES (''' + ASealId + ''', ''' + AArtifactId + ''', ' +
      '  ''' + ARecallType + ''', ' +
      '  $reason$' + AReason + '$reason$, ''system'') ' +
      'RETURNING id::text');

    // Mark seal as recalled
    DB.ExecuteJson(
      'UPDATE artifactos.publication_seal SET seal_status=''recalled'', recalled_at=now(), ' +
      '  recall_reason=$reason$' + AReason + '$reason$ WHERE id=:id',
      '{"id":"' + ASealId + '"}');

    WriteLn(Format('[RecallCard] created: id=%s seal=%s type=%s', [ACardId, ASealId, ARecallType]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TCognitiveGovernance.RecordDisturbance(const AArtifactId, ATraceId: string;
  ADisturbanceType, ASeverity: string; const ADetails: string;
  out AEventId: string): Boolean;
var
  DB: TArtifactDB;
  TraceRef: string;
begin
  Result := False;
  AEventId := '';
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    TraceRef := IfThen(ATraceId <> '', '''' + ATraceId + '''', 'NULL');

    AEventId := DB.InsertAndReturnId(
      'INSERT INTO artifactos.cognitive_disturbance_event ' +
      '  (artifact_id, cognition_trace_id, disturbance_type, severity, details) ' +
      'VALUES (' + IfThen(AArtifactId <> '', '''' + AArtifactId + '''', 'NULL') + ', ' +
      '  ' + TraceRef + ', ' +
      '  ''' + ADisturbanceType + ''', ''' + ASeverity + ''', ' +
      '  $det$' + ADetails + '$det$::jsonb) ' +
      'RETURNING id::text');

    WriteLn(Format('[CogDisturbance] recorded: id=%s type=%s severity=%s',
      [AEventId, ADisturbanceType, ASeverity]));

    // Auto-escalate if critical
    if ASeverity = 'critical' then
    begin
      DB.ExecuteJson(
        'UPDATE artifactos.cognitive_disturbance_event SET response_action=''freeze_pending'', ' +
        '  response_status=''executed'' WHERE id=:id',
        '{"id":"' + AEventId + '"}');

      // Freeze the artifact if specified
      if AArtifactId <> '' then
        FreezeArtifact(AArtifactId, 'Critical cognitive disturbance: ' + ADisturbanceType);
    end
    else if ASeverity = 'high' then
    begin
      DB.ExecuteJson(
        'UPDATE artifactos.cognitive_disturbance_event SET response_action=''escalate_human'', ' +
        '  response_status=''pending'' WHERE id=:id',
        '{"id":"' + AEventId + '"}');
    end;

    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TCognitiveGovernance.FreezeArtifact(const AArtifactId, AReason: string): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.artifact SET status=''frozen'', ' +
      '  frozen_reason=$reason$' + AReason + '$reason$, ' +
      '  frozen_at=now() WHERE id=:id::uuid',
      '{"id":"' + AArtifactId + '"}');

    // Record cognition trace for freeze
    var TraceId: string;
    RecordCognitionTrace(AArtifactId, '', csFreeze,
      '{}', '{}', AReason, TraceId);

    WriteLn('[CognitiveGov] Artifact frozen: ', AArtifactId, ' reason: ', Copy(AReason, 1, 80));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TCognitiveGovernance.UnfreezeArtifact(const AArtifactId, AJustification: string): Boolean;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Verify artifact is actually frozen
    var Status := DB.ExecuteScalar(
      'SELECT status FROM artifactos.artifact WHERE id=''' + AArtifactId + '''');
    if Status <> 'frozen' then
    begin
      WriteLn(ErrOutput, '[CognitiveGov] Cannot unfreeze: artifact status is ', Status);
      Result := False;
      Exit;
    end;

    DB.ExecuteJson(
      'UPDATE artifactos.artifact SET status=''assembled'', ' +
      '  frozen_reason=NULL, frozen_at=NULL, ' +
      '  unfreeze_justification=$just$' + AJustification + '$just$, ' +
      '  unfrozen_at=now() WHERE id=:id::uuid',
      '{"id":"' + AArtifactId + '"}');

    WriteLn('[CognitiveGov] Artifact unfrozen: ', AArtifactId);
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

end.
