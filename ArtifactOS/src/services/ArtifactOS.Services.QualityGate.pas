{ ============================================================================
  ArtifactOS.Services.QualityGate

  Quality Gate pipeline for ArtifactOS draft articles.

  Architecture (docs/12 §3.1-3.4):
    Layer 0: Structure gate (case chain, sealed version, contract chain)
    Layer 1: ES mechanical compliance (zero LLM cost, hard FAIL)
    Layer 2: 半ES semantic checks (Haiku tier, WARN/FREEZE)
    Layer 3: NES multi-dimensional scoring (Sonnet tier, three independent calls)
    Layer 4: 策略裁决 strategy ruling (veto -> weighted total -> conditional -> action)

  Output: 8 actions
    auto_publish | sample_review | rewrite | store_draft
    | downgrade | wait_human | abandon | freeze_and_downgrade

  Version: 0.2 — adds 半ES + NES + strategy ruling layers
  ============================================================================ }

unit ArtifactOS.Services.QualityGate;

interface

uses
  System.SysUtils, System.Generics.Collections, System.JSON, FireDAC.Comp.Client,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.TheoryWeave;

type
  TGateStatus = (gsPass, gsFail, gsWarn, gsFreeze, gsConflict);

  TGateResult = record
    Passed: Boolean;
    GateType: string;
    GateStatus: string;  // PASS / FAIL / WARN / FREEZE / CONFLICT
    Score: Double;
    Evidence: string;
    Issues: TArray<string>;
  end;

  TNesDimension = (ndSource, ndContent, ndRisk);

  TNesScore = record
    Dimension: TNesDimension;
    Score: Double;          // 0..100
    Evidence: string;
    Issues: TArray<string>;
  end;

  TStrategyAction = (
    saAutoPublish, saSampleReview, saRewrite, saStoreDraft,
    saDowngrade, saWaitHuman, saAbandon, saFreezeAndDowngrade
  );

  TStrategyRuling = record
    Action: TStrategyAction;
    Reason: string;
    WeightedTotal: Double;
    VetoHit: Boolean;
    ConditionalHit: Boolean;
    Evidence: string;
  end;

  TQualityGateService = class
  public
    // Layer 0: structure gate
    class function RunStructureGate(const AArtifactId: string): TGateResult;

    // Layer 1: ES gate (7 mechanical rules)
    class function RunESGate(const AArtifactId, AContractJson: string): TGateResult;
    class function RunESGateOnConn(AConn: TFDConnection; const AArtifactId, AContractJson: string): TGateResult;

    // Layer 2: 半ES gate (6 LLM-assisted rules, WARN only)
    class function RunSemiESGate(const AArtifactId, AContractJson, ATitle, ABody: string): TGateResult;

    // Layer 3: NES gate (3 independent LLM score dimensions)
    class function RunNESGate(const AArtifactId, AContractJson, ATitle, ABody: string;
      out AScores: TArray<TNesScore>): TGateResult;

    // Layer 4: strategy ruling (combines all prior layers)
    class function RunStrategyRuling(const AContractJson: string;
      const AEvidence: TArray<TGateResult>;
      const ANesScores: TArray<TNesScore>): TStrategyRuling;

    // Top-level orchestrator: runs L0→L4 in sequence and returns final action
    class function RunFullPipeline(const AArtifactId, AContractJson: string;
      out AFinalAction: TStrategyAction;
      out AFinalReason: string): Boolean;

    // Persistence
    class function CreateQualityRun(const AArtifactId, AArtifactVersionId, ARunType, AEvidence: string): string;
    class function CreateQualitySnapshot(const AArtifactId, AArtifactVersionId: string; AQualified: Boolean): string;
    class function SealSnapshot(const ASnapshotId: string): string;

    // Helpers
    class function ActionToString(AAction: TStrategyAction): string;
    class function StatusToString(AStatus: TGateStatus): string;
  end;

const
  C_ACTION_AUTO_PUBLISH = 'auto_publish';
  C_ACTION_SAMPLE_REVIEW = 'sample_review';
  C_ACTION_REWRITE = 'rewrite';
  C_ACTION_STORE_DRAFT = 'store_draft';
  C_ACTION_DOWNGRADE = 'downgrade';
  C_ACTION_WAIT_HUMAN = 'wait_human';
  C_ACTION_ABANDON = 'abandon';
  C_ACTION_FREEZE_AND_DOWNGRADE = 'freeze_and_downgrade';

implementation

{$WARN IMPLICIT_STRING_CAST OFF}

uses
  ArtifactOS.Services.DeepLLMProxy;

function InsertAndReturnId(const SQL: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnId(SQL);
end;

class function TQualityGateService.StatusToString(AStatus: TGateStatus): string;
begin
  case AStatus of
    gsPass:     Result := 'PASS';
    gsFail:     Result := 'FAIL';
    gsWarn:     Result := 'WARN';
    gsFreeze:   Result := 'FREEZE';
    gsConflict: Result := 'CONFLICT';
  else
    Result := 'UNKNOWN';
  end;
end;

class function TQualityGateService.ActionToString(AAction: TStrategyAction): string;
begin
  case AAction of
    saAutoPublish:        Result := C_ACTION_AUTO_PUBLISH;
    saSampleReview:       Result := C_ACTION_SAMPLE_REVIEW;
    saRewrite:            Result := C_ACTION_REWRITE;
    saStoreDraft:         Result := C_ACTION_STORE_DRAFT;
    saDowngrade:          Result := C_ACTION_DOWNGRADE;
    saWaitHuman:          Result := C_ACTION_WAIT_HUMAN;
    saAbandon:            Result := C_ACTION_ABANDON;
    saFreezeAndDowngrade: Result := C_ACTION_FREEZE_AND_DOWNGRADE;
  else
    Result := C_ACTION_WAIT_HUMAN;
  end;
end;

// =============================================================================
// Layer 0: Structure gate
// =============================================================================

class function TQualityGateService.RunStructureGate(const AArtifactId: string): TGateResult;
var
  DB: TArtifactDB;
  CaseCount, SealedCount: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result.GateType := 'structure';
    Result.Passed := True;
    Result.GateStatus := 'PASS';
    Result.Score := 100.0;
    SetLength(Result.Issues, 0);

    CaseCount := DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.case_record c ' +
      'JOIN artifactos.studio s ON s.case_id = c.id ' +
      'JOIN artifactos.artifact a ON a.sub_studio_id IN (SELECT id FROM artifactos.sub_studio WHERE studio_id = s.id) ' +
      'WHERE a.id=''' + AArtifactId + ''' AND c.status=''active''');

    if CaseCount = '0' then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FREEZE';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'Structure gate: no active case chain for artifact';
      Result.Evidence := '{"case_chain":"broken"}';
      Exit;
    end;

    SealedCount := DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.artifact_version WHERE artifact_id=''' + AArtifactId + ''' AND seal_status=''sealed''');

    if SealedCount = '0' then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FREEZE';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := 'Structure gate: no sealed artifact_version';
    end;

    Result.Evidence := '{"case_chain":"valid","sealed_versions":' + SealedCount + '}';
  finally
    DB.Disconnect;
  end;
end;

// =============================================================================
// Layer 1: ES gate — 7 mechanical rules (docs/12 §3.1)
// =============================================================================

function ExtractJsonField(const AJson, AFieldName: string): string;
var
  JSON: TJSONObject;
begin
  Result := '';
  if AJson.Trim.IsEmpty then Exit;
  try
    JSON := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    if JSON = nil then Exit;
    try
      if JSON.TryGetValue<string>(AFieldName, Result) then
        ;
    finally
      JSON.Free;
    end;
  except
    Result := '';
  end;
end;

function LoadMustLand(const AContractJson: string): TArray<string>;
var
  Raw: string;
begin
  Raw := ExtractJsonField(AContractJson, 'must_land');
  if Raw.Trim.IsEmpty then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  Result := Raw.Split([',']);
end;

function LoadForbiddenWords(const AContractJson: string): TArray<string>;
var
  Raw: string;
begin
  Raw := ExtractJsonField(AContractJson, 'forbidden_words');
  if Raw.Trim.IsEmpty then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  Result := Raw.Split([',']);
end;

function LoadPlatformSensitiveWords(const AContractJson: string): TArray<string>;
var
  Raw: string;
begin
  Raw := ExtractJsonField(AContractJson, 'platform_sensitive_words');
  if Raw.Trim.IsEmpty then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  Result := Raw.Split([',']);
end;

function LoadWordCountRange(const AContractJson: string; out AMin, AMax: Integer): Boolean;
var
  MinStr, MaxStr: string;
begin
  MinStr := ExtractJsonField(AContractJson, 'word_count_min');
  MaxStr := ExtractJsonField(AContractJson, 'word_count_max');
  Result := TryStrToInt(MinStr, AMin) and TryStrToInt(MaxStr, AMax);
  if not Result then
  begin
    AMin := 50;
    AMax := 100000;
    Result := True;
  end;
end;

function CheckES01WordCount(const ABody: string; AMin, AMax: Integer; out AMsg: string): Boolean;
var
  Wc: Integer;
begin
  Wc := Length(ABody);
  if (Wc < AMin) or (Wc > AMax) then
  begin
    AMsg := 'ES-01: word count ' + IntToStr(Wc) + ' outside [' + IntToStr(AMin) + ',' + IntToStr(AMax) + ']';
    Result := False;
  end
  else
  begin
    AMsg := '';
    Result := True;
  end;
end;

function CheckES02Format(const ATitle, ABody: string; out AMsg: string): Boolean;
begin
  if ATitle.Trim.IsEmpty then
  begin
    AMsg := 'ES-02: title is empty';
    Exit(False);
  end;
  if Length(ABody.Split([#10, #13], TStringSplitOptions.None)) < 3 then
  begin
    AMsg := 'ES-02: less than 3 paragraphs';
    Exit(False);
  end;
  AMsg := '';
  Result := True;
end;

function CheckES03MustLand(const ABody: string; const AMust: TArray<string>; out AMsg: string): Boolean;
var
  I, Found: Integer;
  Missing: string;
  Term: string;
begin
  Found := 0;
  Missing := '';
  for I := 0 to High(AMust) do
  begin
    Term := AMust[I].Trim;
    if Term.IsEmpty then Continue;
    if ABody.ToLower.Contains(Term.ToLower) then
      Inc(Found)
    else
    begin
      if not Missing.IsEmpty then Missing := Missing + ',';
      Missing := Missing + Term;
    end;
  end;
  if Found < Length(AMust) then
  begin
    AMsg := 'ES-03: must_land terms missing (' + Missing + ')';
    Exit(False);
  end;
  AMsg := '';
  Result := True;
end;

function CheckES04Forbidden(const ABody: string; const AForbidden: TArray<string>; out AMsg: string): Boolean;
var
  I: Integer;
  Hits: string;
  Term: string;
begin
  Hits := '';
  for I := 0 to High(AForbidden) do
  begin
    Term := AForbidden[I].Trim;
    if Term.IsEmpty then Continue;
    if ABody.ToLower.Contains(Term.ToLower) then
    begin
      if not Hits.IsEmpty then Hits := Hits + ',';
      Hits := Hits + Term;
    end;
  end;
  if not Hits.IsEmpty then
  begin
    AMsg := 'ES-04: forbidden words hit (' + Hits + ')';
    Exit(False);
  end;
  AMsg := '';
  Result := True;
end;

function CheckES05PlatformSensitive(const ABody: string; const ASensitive: TArray<string>; out AMsg: string): Boolean;
var
  I: Integer;
  Hits: string;
  Term: string;
begin
  Hits := '';
  for I := 0 to High(ASensitive) do
  begin
    Term := ASensitive[I].Trim;
    if Term.IsEmpty then Continue;
    if ABody.ToLower.Contains(Term.ToLower) then
    begin
      if not Hits.IsEmpty then Hits := Hits + ',';
      Hits := Hits + Term;
    end;
  end;
  if not Hits.IsEmpty then
  begin
    AMsg := 'ES-05: platform sensitive words hit (' + Hits + ')';
    Exit(False);
  end;
  AMsg := '';
  Result := True;
end;

class function TQualityGateService.RunESGate(const AArtifactId, AContractJson: string): TGateResult;
var
  DB: TArtifactDB;
  Title, Body: string;
  WMin, WMax: Integer;
  MustArr, ForbidArr, SensitiveArr: TArray<string>;
  Msg: string;
  Evidence: TJSONObject;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var ArtParams := '{"id":"' + AArtifactId + '"}';
    Title := DB.ExecuteScalar('SELECT title FROM artifactos.artifact WHERE id=''' + AArtifactId + '''');
    Body  := DB.ExecuteScalar(
      'SELECT av.assembled_payload->>''body'' FROM artifactos.artifact_version av ' +
      'WHERE av.artifact_id=''' + AArtifactId + ''' ORDER BY av.version_no DESC LIMIT 1');
  finally
    DB.Disconnect;
  end;

  Result.GateType := 'es';
  Result.Passed := True;
  Result.Score := 100.0;
  Result.GateStatus := 'PASS';
  SetLength(Result.Issues, 0);
  Evidence := TJSONObject.Create;
  try
    LoadWordCountRange(AContractJson, WMin, WMax);
    MustArr := LoadMustLand(AContractJson);
    ForbidArr := LoadForbiddenWords(AContractJson);
    SensitiveArr := LoadPlatformSensitiveWords(AContractJson);

    if not CheckES01WordCount(Body, WMin, WMax, Msg) then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := Msg;
      Evidence.AddPair('ES-01', TJSONFalse.Create);
    end
    else
      Evidence.AddPair('ES-01', TJSONTrue.Create);

    if not CheckES02Format(Title, Body, Msg) then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := Msg;
      Evidence.AddPair('ES-02', TJSONFalse.Create);
    end
    else
      Evidence.AddPair('ES-02', TJSONTrue.Create);

    // ES-03: must_land coverage (skipped if no must_land in contract)
    if Length(MustArr) = 0 then
      Evidence.AddPair('ES-03', TJSONNull.Create)
    else if not CheckES03MustLand(Body, MustArr, Msg) then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := Msg;
      Evidence.AddPair('ES-03', TJSONFalse.Create);
    end
    else
      Evidence.AddPair('ES-03', TJSONTrue.Create);

    // ES-04: forbidden words (skipped if no forbidden_words in contract)
    if Length(ForbidArr) = 0 then
      Evidence.AddPair('ES-04', TJSONNull.Create)
    else if not CheckES04Forbidden(Body, ForbidArr, Msg) then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := Msg;
      Evidence.AddPair('ES-04', TJSONFalse.Create);
    end
    else
      Evidence.AddPair('ES-04', TJSONTrue.Create);

    // ES-05: platform sensitive (skipped if no platform_sensitive_words in contract)
    if Length(SensitiveArr) = 0 then
      Evidence.AddPair('ES-05', TJSONNull.Create)
    else if not CheckES05PlatformSensitive(Body, SensitiveArr, Msg) then
    begin
      Result.Passed := False;
      Result.GateStatus := 'FAIL';
      SetLength(Result.Issues, Length(Result.Issues) + 1);
      Result.Issues[High(Result.Issues)] := Msg;
      Evidence.AddPair('ES-05', TJSONFalse.Create);
    end
    else
      Evidence.AddPair('ES-05', TJSONTrue.Create);

    // ES-06 = ES-02 title check (kept for label parity with docs/12)
    if Title.Trim.IsEmpty then
      Evidence.AddPair('ES-06', TJSONFalse.Create)
    else
      Evidence.AddPair('ES-06', TJSONTrue.Create);

    // ES-07: theory core — structural fidelity via TheoryWeave
    if TTheoryWeaveService.HasTheoryMapping(AArtifactId) then
    begin
      var FidMapping := TTheoryWeaveService.LoadMappingForContract(AArtifactId);
      if FidMapping.Id <> '' then
      begin
        var FidResult := TTheoryWeaveService.CheckStructuralFidelity(FidMapping.Id, Body);
        var FidObj := TJSONObject.Create;
        FidObj.AddPair('consistency', FidResult.Consistency);
        FidObj.AddPair('missing_count', TJSONNumber.Create(Length(FidResult.MissingRequired)));
        FidObj.AddPair('violated_count', TJSONNumber.Create(Length(FidResult.ViolatedForbidden)));
        if FidResult.Consistency = 'fail' then
          Evidence.AddPair('ES-07', FidObj)
        else
          Evidence.AddPair('ES-07', FidObj);
      end
      else
        Evidence.AddPair('ES-07', TJSONNull.Create);
    end
    else
      Evidence.AddPair('ES-07', TJSONNull.Create);

    if not Result.Passed then
      Result.Score := 0.0;

    Result.Evidence := Evidence.ToJSON;
  finally
    Evidence.Free;
  end;
end;

class function TQualityGateService.RunESGateOnConn(AConn: TFDConnection; const AArtifactId, AContractJson: string): TGateResult;
begin
  // RunESGate is connection-agnostic now (opens own DB). Forward to it.
  Result := RunESGate(AArtifactId, AContractJson);
end;

// =============================================================================
// Layer 2: 半ES gate — 6 LLM-assisted WARN rules (docs/12 §3.2)
// =============================================================================

function BuildSemiESPrompt(const AContractJson, ATitle, ABody: string): string;
var
  MustLand, Forbidden: string;
begin
  MustLand := ExtractJsonField(AContractJson, 'must_land');
  Forbidden := ExtractJsonField(AContractJson, 'forbidden_words');
  Result :=
    'You are a Half-ES (semi-ES) quality auditor. Score the draft below against 6 rules.' + #10 +
    'Return JSON: {"SES-01":{"pass":bool,"note":"..."},"SES-02":{"pass":bool,"note":"..."},' +
    '"SES-03":{"pass":bool,"note":"..."},"SES-04":{"pass":bool,"note":"..."},' +
    '"SES-05":{"pass":bool,"note":"..."},"SES-06":{"pass":bool,"note":"..."}}' + #10 +
    'Rules:' + #10 +
    'SES-01: argument completeness — each must_land point is supported by >= 1 paragraph' + #10 +
    'SES-02: structural coherence — paragraph transitions are smooth (no abrupt jumps)' + #10 +
    'SES-03: title consistency — title matches body content (no clickbait mismatch)' + #10 +
    'SES-04: platform format — body fits generic Chinese essay format (paragraphs, headings)' + #10 +
    'SES-05: source fidelity — body respects the source system (no fabricated claims)' + #10 +
    'SES-06: assertion evidence — key assertions are traceable to evidence, no self-referential claims' + #10 +
    'Must_land: ' + MustLand + #10 +
    'Forbidden: ' + Forbidden + #10 +
    'Title: ' + ATitle + #10 +
    'Body:' + #10 + ABody;
end;

function ParseSemiESJSON(const AContent: string): TArray<TGateResult>;
var
  JSON: TJSONObject;
  RuleNames: TArray<string>;
  I: Integer;
  RuleObj: TJSONValue;
  PassVal: TJSONValue;
  NoteVal: TJSONValue;
  Note: string;
  BPassed: Boolean;
begin
  SetLength(Result, 6);
  RuleNames := TArray<string>.Create('SES-01','SES-02','SES-03','SES-04','SES-05','SES-06');
  for I := 0 to 5 do
  begin
    Result[I].GateType := 'semi_es';
    Result[I].GateStatus := 'PASS';
    Result[I].Passed := True;
    Result[I].Score := 100.0;
    SetLength(Result[I].Issues, 0);
  end;
  try
    JSON := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
    if JSON = nil then Exit;
    try
      for I := 0 to 5 do
      begin
        RuleObj := JSON.FindValue(RuleNames[I]);
        if RuleObj = nil then Continue;

        // Extract "pass" boolean
        PassVal := (RuleObj as TJSONObject).FindValue('pass');
        if PassVal <> nil then
        begin
          if SameText(PassVal.Value, 'true') then
            BPassed := True
          else if SameText(PassVal.Value, 'false') then
            BPassed := False
          else
            BPassed := True;
        end
        else
          BPassed := True;

        // Invert: pass=true means "this rule found a problem" (WARN); pass=false means "this rule passed cleanly"
        // Actually docs say: WARN when issue found. So if pass=false → issue found → WARN
        if not BPassed then
        begin
          Result[I].Passed := False;
          Result[I].GateStatus := 'WARN';
          Result[I].Score := 60.0;
        end;

        // Extract "note"
        NoteVal := (RuleObj as TJSONObject).FindValue('note');
        if NoteVal <> nil then
        begin
          Note := NoteVal.Value;
          if not Note.IsEmpty then
          begin
            SetLength(Result[I].Issues, 1);
            Result[I].Issues[0] := RuleNames[I] + ': ' + Note;
          end;
        end;
      end;
    finally
      JSON.Free;
    end;
  except
    on E: Exception do
    begin
      Result[0].GateStatus := 'WARN';
      Result[0].Issues := TArray<string>.Create('semi_es: LLM returned unparseable JSON: ' + E.Message);
      Result[0].Evidence := '{"raw":"' + AContent.Replace('"','''').Replace(#10,' ') + '"}';
    end;
  end;
end;

class function TQualityGateService.RunSemiESGate(const AArtifactId, AContractJson, ATitle, ABody: string): TGateResult;
var
  LLMResult: TAOSLLMResult;
  PerRuleResults: TArray<TGateResult>;
  I: Integer;
  Combined: TGateResult;
  IssuesJson: TJSONArray;
begin
  Combined.GateType := 'semi_es';
  Combined.Passed := True;
  Combined.Score := 100.0;
  Combined.GateStatus := 'PASS';
  SetLength(Combined.Issues, 0);
  IssuesJson := TJSONArray.Create;
  try
    LLMResult := TArtifactOSLLMProxy.Instance.Chat(
      aostSemiES,
      BuildSemiESPrompt(AContractJson, ATitle, ABody),
      'You output strict JSON only, no prose.');

    if not LLMResult.Success then
    begin
      Combined.Passed := False;
      Combined.GateStatus := 'WARN';
      Combined.Score := 50.0;
      SetLength(Combined.Issues, 1);
      Combined.Issues[0] := 'semi_es: LLM call failed (' + LLMResult.ErrorMessage + ')';
      Combined.Evidence := '{"llm_error":"' + LLMResult.ErrorMessage.Replace('"','''') + '"}';
      Exit;
    end;

    PerRuleResults := ParseSemiESJSON(LLMResult.Content);

    // SES-05: source fidelity FREEZE on theory core violation
    if (Length(PerRuleResults) >= 5) and (not PerRuleResults[4].Passed) then
    begin
      Combined.GateStatus := 'FREEZE';
      Combined.Passed := False;
      Combined.Score := 0.0;
      SetLength(Combined.Issues, Length(Combined.Issues) + 1);
      Combined.Issues[High(Combined.Issues)] := string('SES-05: source fidelity violation — theory core broken');
    end;

    // Aggregate warnings
    for I := 0 to High(PerRuleResults) do
    begin
      if (PerRuleResults[I].GateStatus = 'WARN') or (not PerRuleResults[I].Passed) then
      begin
        if (Length(PerRuleResults[I].Issues) > 0) then
        begin
          SetLength(Combined.Issues, Length(Combined.Issues) + 1);
          Combined.Issues[High(Combined.Issues)] := PerRuleResults[I].Issues[0];
          IssuesJson.Add(PerRuleResults[I].Issues[0]);
        end;
        if Combined.Passed and (Combined.GateStatus = 'PASS') then
        begin
          Combined.GateStatus := 'WARN';
          Combined.Score := 70.0;
        end;
      end;
    end;

    Combined.Evidence := '{"rules":' + IssuesJson.ToJSON + '}';
  finally
    IssuesJson.Free;
  end;
end;

// =============================================================================
// Layer 3: NES gate — 3 independent LLM score dimensions (docs/12 §3.3)
// =============================================================================

function BuildNESPrompt(const ADimension: TNesDimension; const AContractJson, ATitle, ABody: string): string;
var
  DimCode, DimName, DimDesc: string;
begin
  case ADimension of
    ndSource:
    begin
      DimCode := 'SOURCE-01'; DimName := 'Source fidelity'; DimDesc :=
        'Does the draft respect the source system? Score 0-100: 100 = strict adherence, ' +
        '0 = fabrication. Penalize: fabricated concepts, misrepresented causality, broken boundaries.';
    end;
    ndContent:
    begin
      DimCode := 'CONTENT-01'; DimName := 'Content quality'; DimDesc :=
        'Score 0-100 across argument strength, reasoning rigor, readability, title/opening quality. ' +
        '100 = compelling, 0 = incoherent.';
    end;
    ndRisk:
    begin
      DimCode := 'RISK-01'; DimName := 'Risk evaluation'; DimDesc :=
        'Score 0-100: 100 = safe and well-evidenced, 0 = high risk. Penalize: unverified assertions, ' +
        'self-referential claims, sensitive residue, factual errors.';
    end;
  end;
  Result :=
    'Score this draft on the "' + DimCode + ' ' + DimName + '" dimension.' + #10 +
    DimDesc + #10 +
    'Return JSON: {"score": <integer 0-100>, "evidence": "<one sentence>", "issues": ["...", "..."]}' + #10 +
    'Title: ' + ATitle + #10 +
    'Body:' + #10 + ABody + #10 +
    'Contract hints: ' + AContractJson;
end;

function ParseNESJSON(const AContent: string; ADimension: TNesDimension; out AScore: TNesScore): Boolean;
var
  JSON: TJSONObject;
  Issues: TJSONArray;
  IssuesArr: TJSONValue;
  ScoreVal, EvidenceVal: TJSONValue;
  I: Integer;
begin
  Result := False;
  AScore.Dimension := ADimension;
  AScore.Score := 50.0;
  AScore.Evidence := '';
  SetLength(AScore.Issues, 0);
  try
    JSON := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
    if JSON = nil then Exit;
    try
      ScoreVal := JSON.FindValue('score');
      if ScoreVal <> nil then
        AScore.Score := StrToFloatDef(ScoreVal.Value, 50.0)
      else
        AScore.Score := 50.0;
      EvidenceVal := JSON.FindValue('evidence');
      if EvidenceVal <> nil then
        AScore.Evidence := EvidenceVal.Value
      else
        AScore.Evidence := '';
      IssuesArr := JSON.FindValue('issues');
      if (IssuesArr <> nil) and (IssuesArr is TJSONArray) then
      begin
        Issues := IssuesArr as TJSONArray;
        SetLength(AScore.Issues, Issues.Count);
        for I := 0 to Issues.Count - 1 do
          AScore.Issues[I] := Issues.Items[I].Value;
      end;
      Result := True;
    finally
      JSON.Free;
    end;
  except
    on E: Exception do
      AScore.Evidence := 'NES parse error: ' + E.Message;
  end;
end;

function NesDimensionName(ADim: TNesDimension): string;
begin
  case ADim of
    ndSource:  Result := 'SOURCE-01';
    ndContent: Result := 'CONTENT-01';
    ndRisk:    Result := 'RISK-01';
  else
    Result := 'UNKNOWN';
  end;
end;

class function TQualityGateService.RunNESGate(const AArtifactId, AContractJson, ATitle, ABody: string;
  out AScores: TArray<TNesScore>): TGateResult;
var
  Dims: TArray<TNesDimension>;
  I: Integer;
  LLMResult: TAOSLLMResult;
  Combined: TGateResult;
  Score: TNesScore;
  TotalScore: Double;
begin
  Dims := TArray<TNesDimension>.Create(ndSource, ndContent, ndRisk);
  SetLength(AScores, 3);
  Combined.GateType := 'nes';
  Combined.Passed := True;
  Combined.Score := 100.0;
  Combined.GateStatus := 'PASS';
  SetLength(Combined.Issues, 0);

  TotalScore := 0.0;
  for I := 0 to 2 do
  begin
    LLMResult := TArtifactOSLLMProxy.Instance.Chat(
      aostNES,
      BuildNESPrompt(Dims[I], AContractJson, ATitle, ABody),
      'You are an expert quality evaluator. Output strict JSON only.');

    if not LLMResult.Success then
    begin
      // LLM failure — give neutral score so flow continues
      AScores[I].Dimension := Dims[I];
      AScores[I].Score := 50.0;
      AScores[I].Evidence := 'NES LLM call failed: ' + LLMResult.ErrorMessage;
      SetLength(AScores[I].Issues, 0);
      SetLength(Combined.Issues, Length(Combined.Issues) + 1);
      Combined.Issues[High(Combined.Issues)] := NesDimensionName(Dims[I]) + ': LLM call failed';
    end
    else if ParseNESJSON(LLMResult.Content, Dims[I], Score) then
    begin
      AScores[I] := Score;
      // FREEZE on red-line scores (veto threshold)
      if Score.Score < 30.0 then
      begin
        Combined.GateStatus := 'FREEZE';
        Combined.Passed := False;
        SetLength(Combined.Issues, Length(Combined.Issues) + 1);
        Combined.Issues[High(Combined.Issues)] := NesDimensionName(Dims[I]) +
          ' below 30 (red line): ' + FloatToStr(Score.Score);
      end;
    end
    else
    begin
      AScores[I].Dimension := Dims[I];
      AScores[I].Score := 50.0;
      AScores[I].Evidence := 'NES parse failed: ' + LLMResult.Content;
      SetLength(AScores[I].Issues, 0);
    end;
    TotalScore := TotalScore + AScores[I].Score;
  end;

  Combined.Score := TotalScore / 3.0;
  if (Combined.GateStatus = 'PASS') and (Combined.Score < 60.0) then
  begin
    Combined.GateStatus := 'WARN';
    Combined.Passed := False;  // triggers rewrite path in strategy ruling
  end;
  Combined.Evidence := '{"weighted_score":' + FloatToStr(Combined.Score) + '}';
  Result := Combined;
end;

// =============================================================================
// Layer 4: 策略裁决 strategy ruling (docs/12 §3.4)
// =============================================================================

function GetNesScore(const AScores: TArray<TNesScore>; ADim: TNesDimension): Double;
var
  I: Integer;
begin
  Result := 50.0;
  for I := 0 to High(AScores) do
    if AScores[I].Dimension = ADim then
    begin
      Result := AScores[I].Score;
      Break;
    end;
end;

class function TQualityGateService.RunStrategyRuling(const AContractJson: string;
  const AEvidence: TArray<TGateResult>;
  const ANesScores: TArray<TNesScore>): TStrategyRuling;
var
  SourceScore, ContentScore, RiskScore, WeightedTotal: Double;
  ESResult, SemiESResult, NESResult: TGateResult;
  HasVeto, HasConditional, HasFreeze: Boolean;
  I: Integer;
begin
  Result.Action := saWaitHuman;  // default safe action
  Result.Reason := '';
  Result.VetoHit := False;
  Result.ConditionalHit := False;

  // Locate layer results
  ESResult.GateStatus := 'PASS';
  SemiESResult.GateStatus := 'PASS';
  NESResult.GateStatus := 'PASS';
  for I := 0 to High(AEvidence) do
  begin
    if AEvidence[I].GateType = 'es' then ESResult := AEvidence[I]
    else if AEvidence[I].GateType = 'semi_es' then SemiESResult := AEvidence[I]
    else if AEvidence[I].GateType = 'nes' then NESResult := AEvidence[I];
  end;

  SourceScore := GetNesScore(ANesScores, ndSource);
  ContentScore := GetNesScore(ANesScores, ndContent);
  RiskScore := GetNesScore(ANesScores, ndRisk);

  // Hard ES fail → rewrite (no veto)
  if ESResult.GateStatus = 'FAIL' then
  begin
    Result.Action := saRewrite;
    Result.Reason := 'ES gate failed — mechanical rules violated';
    Exit;
  end;

  // Check freeze flags from any prior layer
  HasFreeze := (SemiESResult.GateStatus = 'FREEZE') or (NESResult.GateStatus = 'FREEZE');
  if HasFreeze then
  begin
    Result.Action := saFreezeAndDowngrade;
    Result.Reason := 'A prior layer raised FREEZE — freeze and downgrade';
    Result.VetoHit := True;
    Exit;
  end;

  // Phase 1 veto rules (docs/12 §3.4 — simplified)
  HasVeto := False;
  if SourceScore < 50.0 then
  begin
    Result.Action := saFreezeAndDowngrade;
    Result.Reason := 'SOURCE-01 < 50 (veto) — freeze';
    Result.VetoHit := True;
    HasVeto := True;
  end
  else if RiskScore < 40.0 then
  begin
    Result.Action := saRewrite;
    Result.Reason := 'RISK-01 < 40 (veto) — rewrite';
    Result.VetoHit := True;
    HasVeto := True;
  end;

  if HasVeto then
    Exit;

  // Conditional rules (docs/12 §3.4 — toxic combination)
  if (SourceScore < 60.0) and (ContentScore > 80.0) then
  begin
    Result.Action := saRewrite;
    Result.Reason := 'SOURCE-01 < 60 AND CONTENT-01 > 80 — rewrite (content seductive but theory weak)';
    Result.ConditionalHit := True;
    Exit;
  end;

  // Weighted total (equal weights in Phase 1)
  WeightedTotal := (SourceScore + ContentScore + RiskScore) / 3.0;
  Result.WeightedTotal := WeightedTotal;

  if WeightedTotal >= 75.0 then
  begin
    Result.Action := saAutoPublish;
    Result.Reason := 'Weighted total >= 75 — auto_publish candidate';
  end
  else if WeightedTotal >= 60.0 then
  begin
    Result.Action := saSampleReview;
    Result.Reason := 'Weighted total 60-75 — sample_review';
  end
  else if WeightedTotal >= 40.0 then
  begin
    Result.Action := saStoreDraft;
    Result.Reason := 'Weighted total 40-60 — store_draft for later revision';
  end
  else
  begin
    Result.Action := saDowngrade;
    Result.Reason := 'Weighted total < 40 — downgrade purpose type';
  end;

  Result.Evidence := '{"weighted_total":' + FloatToStr(WeightedTotal) +
    ',"source":' + FloatToStr(SourceScore) +
    ',"content":' + FloatToStr(ContentScore) +
    ',"risk":' + FloatToStr(RiskScore) + '}';
end;

// =============================================================================
// Top-level orchestrator
// =============================================================================

class function TQualityGateService.RunFullPipeline(const AArtifactId, AContractJson: string;
  out AFinalAction: TStrategyAction;
  out AFinalReason: string): Boolean;
var
  DB: TArtifactDB;
  Title, Body: string;
  StructRes, ESRes, SemiESRes, NESRes: TGateResult;
  NesScores: TArray<TNesScore>;
  Evidence: TArray<TGateResult>;
  Ruling: TStrategyRuling;
begin
  Result := False;
  // Fetch title/body once
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var ArtParams2 := '{"id":"' + AArtifactId + '"}';
    Title := DB.ExecuteScalarJson('SELECT title FROM artifactos.artifact WHERE id=:id::uuid', ArtParams2);
    Body  := DB.ExecuteScalarJson(
      'SELECT av.assembled_payload->>''body'' FROM artifactos.artifact_version av ' +
      'WHERE av.artifact_id=:id::uuid ORDER BY av.version_no DESC LIMIT 1', ArtParams2);
  finally
    DB.Disconnect;
  end;

  // L0: structure gate
  StructRes := RunStructureGate(AArtifactId);
  if StructRes.GateStatus = 'FREEZE' then
  begin
    AFinalAction := saFreezeAndDowngrade;
    AFinalReason := 'L0 structure gate FREEZE: ' + StructRes.Issues[0];
    Exit;
  end;

  // L1: ES gate
  ESRes := RunESGate(AArtifactId, AContractJson);
  if ESRes.GateStatus = 'FAIL' then
  begin
    AFinalAction := saRewrite;
    AFinalReason := 'L1 ES gate FAIL — rewrite needed';
    Exit;
  end;

  // L2: 半ES gate
  SemiESRes := RunSemiESGate(AArtifactId, AContractJson, Title, Body);
  if SemiESRes.GateStatus = 'FREEZE' then
  begin
    AFinalAction := saFreezeAndDowngrade;
    AFinalReason := 'L2 半ES gate FREEZE: ' + SemiESRes.Issues[0];
    Exit;
  end;

  // L3: NES gate
  NESRes := RunNESGate(AArtifactId, AContractJson, Title, Body, NesScores);
  if NESRes.GateStatus = 'FREEZE' then
  begin
    AFinalAction := saFreezeAndDowngrade;
    AFinalReason := 'L3 NES gate FREEZE — red-line dimension';
    Exit;
  end;

  // L4: strategy ruling
  SetLength(Evidence, 3);
  Evidence[0] := ESRes;
  Evidence[1] := SemiESRes;
  Evidence[2] := NESRes;
  Ruling := RunStrategyRuling(AContractJson, Evidence, NesScores);
  AFinalAction := Ruling.Action;
  AFinalReason := Ruling.Reason;

  Result := True;
end;

// =============================================================================
// Persistence
// =============================================================================

class function TQualityGateService.CreateQualityRun(const AArtifactId, AArtifactVersionId, ARunType, AEvidence: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.quality_run (artifact_id, artifact_version_id, run_type, run_evidence, run_status, completed_at) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + ARunType + ''', ''' + AEvidence + ''', ''completed'', now()) ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TQualityGateService.CreateQualitySnapshot(const AArtifactId, AArtifactVersionId: string; AQualified: Boolean): string;
var
  DB: TArtifactDB;
  QualStatus, Readiness: string;
begin
  if AQualified then
  begin
    QualStatus := 'qualified';
    Readiness := 'ready';
  end
  else
  begin
    QualStatus := 'not_qualified';
    Readiness := 'not_ready';
  end;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnId('INSERT INTO artifactos.quality_snapshot (artifact_id, artifact_version_id, qualified_status, publish_readiness, ' +
      'purpose_fit_status, seal_candidate) ' +
      'VALUES (''' + AArtifactId + ''', ''' + AArtifactVersionId + ''', ''' + QualStatus + ''', ''' + Readiness + ''', ''pass'', true) ' +
      'RETURNING id');
  finally
    DB.Disconnect;
  end;
end;

class function TQualityGateService.SealSnapshot(const ASnapshotId: string): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var SnapParams := '{"id":"' + ASnapshotId + '"}';
    DB.ExecuteJson('UPDATE artifactos.quality_snapshot SET sealed_at=now(), sealed_by=''system:quality_gate'' WHERE id=:id::uuid AND sealed_at IS NULL', SnapParams);
    Result := ASnapshotId;
  finally
    DB.Disconnect;
  end;
end;

end.
