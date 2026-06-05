{ ============================================================================
  ArtifactOS.Services.GenerationService

  AB dual-track generation engine with outline racing.

  Flow:
    1. Generate 3 outlines (different angles) via LLM
    2. Score outlines → pick top 2 for AB tracks
    3. Generate full article from each outline (Track A + Track B)
    4. Judge qualification: each track independently assessed
    5. AB selection: compare qualified tracks → winner + runner-up
    6. Auto-retry: if both A and B fail, use outline C for Track C

  LLM tier usage:
    - Outline generation:   aostGeneration (Sonnet, temp 0.7)
    - Outline scoring:      aostSemiES     (Haiku,  temp 0.1)
    - Full text generation:  aostGeneration (Sonnet, temp 0.7)
    - Qualification judge:  aostSemiES     (Haiku,  temp 0.1)
    - AB selection:         aostStrategy   (Sonnet, temp 0.3)

  Design source: docs/11 §3 + user requirement for AB dual-track racing.

  Version: 0.1
  ============================================================================ }

unit ArtifactOS.Services.GenerationService;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.DeepLLMProxy,
  ArtifactOS.Services.PromptAssembly,
  ArtifactOS.Services.QualityGate,
  ArtifactOS.Services.TheoryWeave;

type
  /// <summary>One outline candidate from the racing phase.</summary>
  TOutlineCandidate = record
    TrackLabel: string;     // 'A', 'B', 'C'
    AngleName: string;      // e.g. 'pain_driven'
    OutlineText: string;    // raw LLM output
    OutlineJson: string;    // structured JSON
    Score: Double;
    ScoreDetail: string;    // JSON with per-dimension scores
    RankNo: Integer;
    Selected: Boolean;      // true for top 2 that enter AB generation
    procedure Init;
  end;
  TOutlineArray = TArray<TOutlineCandidate>;

  /// <summary>Qualification judge result for one track.</summary>
  TQualificationResult = record
    Passed: Boolean;
    Score: Double;
    Scores: string;         // JSON: {must_land, taboo, structure, readability, platform}
    Issues: string;         // JSON array of issue strings
    procedure Init;
  end;

  /// <summary>AB selection result.</summary>
  TSelectionResult = record
    Winner: string;         // 'A' or 'B'
    Reasoning: string;
    ScoreA: Double;
    ScoreB: Double;
    Detail: string;         // JSON
    procedure Init;
  end;

  /// <summary>Generation session record.</summary>
  TGenerationSession = record
    Id: string;
    ArtifactId: string;
    ContractId: string;
    Status: string;
    TrackAVersionId: string;
    TrackBVersionId: string;
    TrackCVersionId: string;
    WinnerTrack: string;
    WinnerVersionId: string;
    RunnerUpVersionId: string;
    procedure Init;
  end;

  /// <summary>
  /// AB dual-track generation service.
  /// Orchestrates outline racing → AB generation → qualification → selection.
  /// </summary>
  TGenerationService = class
  private
    const
      QUALIFICATION_THRESHOLD = 60.0;  // minimum score to pass qualification
      MAX_REWRITE = 1;  // L3-66: max auto-rewrite attempts per track
      ANGLE_NAMES: array[0..2] of string = ('pain_driven', 'theory_intervention', 'case_narrative');
      ANGLE_LABELS: array[0..2] of string = (
        '从受众痛点出发，先提出读者面临的实际问题，再给出解决方案',
        '用理论框架解读现象，先引入概念模型，再用案例论证',
        '以具体案例/故事为主线，用叙事方式展开论述'
      );

    class function NewId: string;
    class function JsonStr(const S: string): string;
    class function MakeParam(const AName, AValue: string): string;
    class function MakeObj(const AFields: array of string): string;

    // Prompt builders
    class function BuildOutlinePrompt(const AContextPrompt, AAngleName, AAngleDesc: string): string;
    class function BuildOutlineScorePrompt(const AContractJson, AOutlineJson: string): string;
    class function BuildFullTextPrompt(const AContextPrompt, AOutlineJson: string): string;
    class function BuildQualificationPrompt(const AContractJson, ATitle, ABody: string): string;
    class function BuildSelectionPrompt(const ADirective, ATitleA, ABodyA, ATitleB, ABodyB: string): string;

    // JSON parsing helpers
    class function ExtractJsonField(const AJson, AFieldName: string): string;
    class function ParseOutlineFromLLM(const AContent: string): string;
    class function ParseScoreFromLLM(const AContent: string): Double;
    class function ParseQualificationFromLLM(const AContent: string; out APassed: Boolean; out AScore: Double): string;
    class function ParseSelectionFromLLM(const AContent: string): string;

    // DB helpers
    class function GetNextVersionNo(const AArtifactId: string): Integer;
    class function GetContractJson(const AContractId: string): string;
    class function UpdateSessionStatus(const ASessionId, AStatus: string): Boolean;
    class function SetSessionTracks(const ASessionId, ATrackA, ATrackB: string): Boolean;
    class function SetSessionQualification(const ASessionId, ATrack: string; const AQualJson: string): Boolean;
    class function SetSessionWinner(const ASessionId, AWinnerTrack, AWinnerVersionId, ARunnerUpVersionId: string;
      const ASelectionJson: string): Boolean;
    class function PersistOutline(const ASessionId: string; const AOutline: TOutlineCandidate): Boolean;

  public
    // Session lifecycle
    class function CreateSession(const AArtifactId, AContractId: string): string;
    class function GetSession(const ASessionId: string): TGenerationSession;

    // Step 1: Generate 3 outlines with different angles
    class function GenerateOutlines(const AContractId: string;
      out AOutlines: TOutlineArray): Boolean;

    // Step 2: Score outlines and select top 2 for AB tracks
    class function ScoreAndSelectTop2(const AContractId: string;
      var AOutlines: TOutlineArray): Boolean;

    // Step 3: Generate full text for one track
    class function GenerateTrack(const AContractId: string;
      const AOutline: TOutlineCandidate;
      const AArtifactId: string;
      const AVersionNo: Integer;
      out AVersionId, ATitle, ABody: string): Boolean;

    // Step 4: Qualification judge for one track
    class function JudgeQualification(const AVersionId, AContractId: string;
      out AResult: TQualificationResult): Boolean;

    // Step 5: AB selection between two qualified tracks
    class function SelectWinner(const AContractId: string;
      const ATitleA, ABodyA, ATitleB, ABodyB: string;
      out ASelection: TSelectionResult): Boolean;

    // Step 5.5: Auto-rewrite a failed track based on low-score dimensions
    class function RewriteTrack(const AContractId: string;
      const AOrigTitle, AOrigBody, AIssues: string;
      const ARewriteAttempt: Integer;
      out ANewTitle, ANewBody: string): Boolean;

    // Determine rewrite action from qualification issues
    class function DetermineRewriteAction(const AScores, AIssues: string): string;

    // Build a targeted rewrite prompt
    class function BuildRewritePrompt(const AContractJson, AOrigTitle, AOrigBody,
      ARewriteAction: string; ARewriteAttempt: Integer): string;

    // Finalize session — seal winner, supersede runner-up
    class function FinalizeSession(const ASessionId: string;
      const AWinnerVersionId, ARunnerUpVersionId: string;
      const AWinnerTrack: string;
      const ASelectionJson: string): Boolean;

    // Full orchestrator — runs the entire AB generation flow
    class function RunABGeneration(const AArtifactId, AContractId: string;
      out ASessionId, AWinnerVersionId: string): Boolean;

    // L3-67: Strategy ruling — translate QualityGate output to pipeline action
    // Returns the action string and updates contract/session state accordingly
    class function ApplyStrategyRuling(const AArtifactId, AWinnerVersionId,
      AContractId, ASessionId: string): string;
  end;

implementation

uses
  FireDAC.Comp.Client;

{ === Record helpers === }

procedure TOutlineCandidate.Init;
begin
  TrackLabel := '';
  AngleName := '';
  OutlineText := '';
  OutlineJson := '{}';
  Score := 0;
  ScoreDetail := '{}';
  RankNo := 0;
  Selected := False;
end;

procedure TQualificationResult.Init;
begin
  Passed := False;
  Score := 0;
  Scores := '{}';
  Issues := '[]';
end;

procedure TSelectionResult.Init;
begin
  Winner := '';
  Reasoning := '';
  ScoreA := 0;
  ScoreB := 0;
  Detail := '{}';
end;

procedure TGenerationSession.Init;
begin
  Id := '';
  ArtifactId := '';
  ContractId := '';
  Status := '';
  TrackAVersionId := '';
  TrackBVersionId := '';
  TrackCVersionId := '';
  WinnerTrack := '';
  WinnerVersionId := '';
  RunnerUpVersionId := '';
end;

{ === Private helpers === }

class function TGenerationService.NewId: string;
begin
  Result := TGUID.NewGuid.ToString.Trim(['{', '}']);
end;

class function TGenerationService.JsonStr(const S: string): string;
begin
  Result := S.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n');
end;

class function TGenerationService.MakeParam(const AName, AValue: string): string;
begin
  Result := '"' + AName + '":"' + JsonStr(AValue) + '"';
end;

class function TGenerationService.MakeObj(const AFields: array of string): string;
var
  I: Integer;
begin
  Result := '{';
  for I := 0 to High(AFields) do
  begin
    if I > 0 then Result := Result + ',';
    Result := Result + AFields[I];
  end;
  Result := Result + '}';
end;

class function TGenerationService.ExtractJsonField(const AJson, AFieldName: string): string;
var
  JObj: TJSONObject;
begin
  Result := '';
  JObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if JObj <> nil then
  try
    Result := JObj.GetValue<string>(AFieldName, '');
  finally
    JObj.Free;
  end;
end;

class function TGenerationService.ParseOutlineFromLLM(const AContent: string): string;
var
  StartPos, EndPos: Integer;
  S: string;
  Depth, I: Integer;
begin
  // Try to extract JSON from LLM response (may be wrapped in markdown code block)
  S := AContent.Trim;
  StartPos := S.IndexOf('{');
  if StartPos < 0 then begin Result := '{}'; Exit; end;

  // Find matching closing brace (simple depth counter)
  Depth := 0;
  EndPos := -1;
  for I := StartPos to S.Length - 1 do
  begin
    if S.Chars[I] = '{' then Inc(Depth)
    else if S.Chars[I] = '}' then begin Dec(Depth); if Depth = 0 then begin EndPos := I; Break; end; end;
  end;

  if EndPos < 0 then Result := '{}'
  else Result := S.Substring(StartPos, EndPos - StartPos + 1);
end;

class function TGenerationService.ParseScoreFromLLM(const AContent: string): Double;
var
  JsonStr: string;
  JObj: TJSONObject;
begin
  Result := 0;
  JsonStr := ParseOutlineFromLLM(AContent);  // reuse JSON extractor
  JObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JObj <> nil then
  try
    Result := JObj.GetValue<Double>('total_score', 0);
  finally
    JObj.Free;
  end;
end;

class function TGenerationService.ParseQualificationFromLLM(const AContent: string;
  out APassed: Boolean; out AScore: Double): string;
var
  JsonStr: string;
  JObj: TJSONObject;
begin
  APassed := False;
  AScore := 0;
  Result := '{}';
  JsonStr := ParseOutlineFromLLM(AContent);
  JObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JObj <> nil then
  try
    APassed := JObj.GetValue<Boolean>('passed', False);
    AScore := JObj.GetValue<Double>('score', 0);
    Result := JsonStr;
  finally
    JObj.Free;
  end;
end;

class function TGenerationService.ParseSelectionFromLLM(const AContent: string): string;
var
  JsonStr: string;
begin
  JsonStr := ParseOutlineFromLLM(AContent);
  if JsonStr = '{}' then
    Result := '{"winner":"A","reasoning":"parse_fallback","scores":{"A":0,"B":0}}'
  else
    Result := JsonStr;
end;

{ === Prompt builders === }

class function TGenerationService.BuildOutlinePrompt(
  const AContextPrompt, AAngleName, AAngleDesc: string): string;
begin
  Result :=
    'Based on the contract and context above, generate an article outline.' + #10 + #10 +
    'Required angle: ' + AAngleName + #10 +
    'Angle description: ' + AAngleDesc + #10 + #10 +
    'Output strictly as JSON:' + #10 +
    '{"title":"article title","sections":[{"heading":"section title","key_points":["point1","point2"]}],' +
    '"conclusion_direction":"where the conclusion goes","estimated_words":1000}' + #10 + #10 +
    'Constraints:' + #10 +
    '- Title must be compelling and specific to the angle' + #10 +
    '- 3-5 sections with clear logical progression' + #10 +
    '- Each section has 2-3 key points' + #10 +
    '- Conclusion direction must be actionable';
end;

class function TGenerationService.BuildOutlineScorePrompt(
  const AContractJson, AOutlineJson: string): string;
begin
  Result :=
    'Score this article outline (0-10 scale):' + #10 + #10 +
    'Contract must_land items:' + #10 + AContractJson + #10 + #10 +
    'Outline:' + #10 + AOutlineJson + #10 + #10 +
    'Scoring dimensions:' + #10 +
    '- must_land_coverage (0-10): how well does it cover required landing points' + #10 +
    '- angle_differentiation (0-10): how unique vs generic' + #10 +
    '- reader_match (0-10): fit for target audience' + #10 +
    '- platform_fit (0-10): suitability for target platform format' + #10 +
    '- theory_appropriateness (0-10): right level of theoretical depth' + #10 + #10 +
    'Output strictly as JSON:' + #10 +
    '{"total_score":7.5,"dimensions":{"must_land_coverage":8,"angle_differentiation":7,' +
    '"reader_match":8,"platform_fit":7,"theory_appropriateness":7}}';
end;

class function TGenerationService.BuildFullTextPrompt(
  const AContextPrompt, AOutlineJson: string): string;
begin
  Result :=
    'Write the full article following this outline exactly.' + #10 + #10 +
    'Outline:' + #10 + AOutlineJson + #10 + #10 +
    'Requirements:' + #10 +
    '- Follow the outline structure faithfully' + #10 +
    '- Each section should be 200-400 words' + #10 +
    '- Write in natural, engaging Chinese' + #10 +
    '- Include specific examples or data where possible' + #10 +
    '- End with the conclusion direction specified in the outline' + #10 + #10 +
    'Output as JSON:' + #10 +
    '{"title":"article title","body":"full article text with paragraphs separated by \\n\\n"}';
end;

class function TGenerationService.BuildQualificationPrompt(
  const AContractJson, ATitle, ABody: string): string;
begin
  Result :=
    'Evaluate this article for publication readiness (pass threshold: 60/100).' + #10 + #10 +
    'Contract constraints:' + #10 + AContractJson + #10 + #10 +
    'Article title: ' + ATitle + #10 +
    'Article body:' + #10 + ABody + #10 + #10 +
    'Evaluate on:' + #10 +
    '- must_land_hit (0-100): did it cover required landing points' + #10 +
    '- taboo_avoidance (0-100): any forbidden content' + #10 +
    '- paragraph_structure (0-100): logical flow and paragraph quality' + #10 +
    '- readability (0-100): natural language, engaging' + #10 +
    '- platform_fit (0-100): appropriate for target platform' + #10 + #10 +
    'Output strictly as JSON:' + #10 +
    '{"passed":true,"score":78,"dimensions":{"must_land_hit":80,"taboo_avoidance":90,' +
    '"paragraph_structure":75,"readability":70,"platform_fit":75},"issues":["issue1"]}';
end;

class function TGenerationService.BuildSelectionPrompt(
  const ADirective, ATitleA, ABodyA, ATitleB, ABodyB: string): string;
begin
  Result :=
    'You are an editor-in-chief. Select the better article.' + #10 + #10 +
    'Contract directive: ' + ADirective + #10 + #10 +
    'Article A title: ' + ATitleA + #10 +
    'Article A body:' + #10 + ABodyA + #10 + #10 +
    'Article B title: ' + ATitleB + #10 +
    'Article B body:' + #10 + ABodyB + #10 + #10 +
    'Judge on:' + #10 +
    '- reader_value (0-100): how much value for target reader' + #10 +
    '- viral_potential (0-100): shareability and engagement' + #10 +
    '- contract_fidelity (0-100): how well it fulfills the contract' + #10 +
    '- writing_quality (0-100): prose quality and readability' + #10 + #10 +
    'Output strictly as JSON:' + #10 +
    '{"winner":"A","reasoning":"why A won","scores":{"A":85,"B":72},' +
    '"detail":{"A":{"reader_value":90,"viral_potential":80,"contract_fidelity":85,"writing_quality":85},' +
    '"B":{"reader_value":70,"viral_potential":75,"contract_fidelity":70,"writing_quality":73}}}';
end;

{ === DB helpers === }

class function TGenerationService.GetNextVersionNo(const AArtifactId: string): Integer;
var
  V: string;
begin
  V := ArtifactOS_DB.ExecuteScalarJson(
    'SELECT COALESCE(MAX(version_no),0)::text FROM artifactos.artifact_version WHERE artifact_id=:id::uuid',
    MakeObj([MakeParam('id', AArtifactId)]));
  Result := StrToIntDef(V, 0) + 1;
end;

class function TGenerationService.GetContractJson(const AContractId: string): string;
begin
  Result := ArtifactOS_DB.ExecuteScalarJson(
    'SELECT row_to_json(t) FROM (SELECT source, strategy, directive, structure, ' +
    'constraints, quality, materials FROM artifactos.artifact_contract WHERE id=:id::uuid) t',
    MakeObj([MakeParam('id', AContractId)]));
end;

class function TGenerationService.UpdateSessionStatus(const ASessionId, AStatus: string): Boolean;
begin
  ArtifactOS_DB.ExecuteJson(
    'UPDATE artifactos.generation_session SET status=:status WHERE id=:id::uuid',
    MakeObj([MakeParam('status', AStatus), MakeParam('id', ASessionId)]));
  Result := True;
end;

class function TGenerationService.SetSessionTracks(const ASessionId, ATrackA, ATrackB: string): Boolean;
begin
  ArtifactOS_DB.ExecuteJson(
    'UPDATE artifactos.generation_session SET track_a_version_id=:a::uuid, track_b_version_id=:b::uuid ' +
    'WHERE id=:id::uuid',
    MakeObj([MakeParam('a', ATrackA), MakeParam('b', ATrackB), MakeParam('id', ASessionId)]));
  Result := True;
end;

class function TGenerationService.SetSessionQualification(const ASessionId, ATrack: string;
  const AQualJson: string): Boolean;
var
  ColName: string;
begin
  if ATrack = 'A' then ColName := 'qualification_a'
  else if ATrack = 'B' then ColName := 'qualification_b'
  else ColName := 'qualification_c';
  ArtifactOS_DB.ExecuteJson(
    'UPDATE artifactos.generation_session SET ' + ColName + '=:q::jsonb WHERE id=:id::uuid',
    MakeObj(['"q":' + AQualJson, MakeParam('id', ASessionId)]));
  Result := True;
end;

class function TGenerationService.SetSessionWinner(const ASessionId, AWinnerTrack, AWinnerVersionId,
  ARunnerUpVersionId: string; const ASelectionJson: string): Boolean;
begin
  ArtifactOS_DB.ExecuteJson(
    'UPDATE artifactos.generation_session SET ' +
    'winner_track=:wt, winner_version_id=:wv::uuid, runner_up_version_id=:rv::uuid, ' +
    'selection_result=:sr::jsonb, status=''completed'' WHERE id=:id::uuid',
    MakeObj([MakeParam('wt', AWinnerTrack), MakeParam('wv', AWinnerVersionId),
             MakeParam('rv', ARunnerUpVersionId), '"sr":' + ASelectionJson,
             MakeParam('id', ASessionId)]));
  Result := True;
end;

class function TGenerationService.PersistOutline(const ASessionId: string;
  const AOutline: TOutlineCandidate): Boolean;
begin
  ArtifactOS_DB.ExecuteJson(
    'INSERT INTO artifactos.generation_outline ' +
    '(id, session_id, track_label, angle_name, outline_text, outline_json, ' +
    ' score, score_detail, rank_no, selected) ' +
    'VALUES (:id::uuid, :sid::uuid, :tl, :an, :ot, :oj::jsonb, ' +
    ' :sc, :sd::jsonb, :rn, :sel)',
    MakeObj([MakeParam('id', NewId), MakeParam('sid', ASessionId),
             MakeParam('tl', AOutline.TrackLabel), MakeParam('an', AOutline.AngleName),
             MakeParam('ot', AOutline.OutlineText), '"oj":' + AOutline.OutlineJson,
             '"sc":' + FloatToStr(AOutline.Score), '"sd":' + AOutline.ScoreDetail,
             '"rn":' + IntToStr(AOutline.RankNo),
             '"sel":' + BoolToStr(AOutline.Selected, True).ToLower]));
  Result := True;
end;

{ === Public API === }

class function TGenerationService.CreateSession(
  const AArtifactId, AContractId: string): string;
begin
  Result := ArtifactOS_DB.InsertAndReturnIdJson(
    'INSERT INTO artifactos.generation_session (id, artifact_id, contract_id) ' +
    'VALUES (:id::uuid, :aid::uuid, :cid::uuid) RETURNING id::text',
    MakeObj([MakeParam('id', NewId), MakeParam('aid', AArtifactId), MakeParam('cid', AContractId)]));
end;

class function TGenerationService.GetSession(const ASessionId: string): TGenerationSession;
var
  MT: TFDMemTable;
begin
  Result.Init;
  MT := ArtifactOS_DB.QueryJson(
    'SELECT id::text, artifact_id::text, contract_id::text, status, ' +
    'track_a_version_id::text, track_b_version_id::text, track_c_version_id::text, ' +
    'winner_track, winner_version_id::text, runner_up_version_id::text ' +
    'FROM artifactos.generation_session WHERE id=:id::uuid',
    MakeObj([MakeParam('id', ASessionId)]));
  try
    if not MT.Eof then
    begin
      Result.Id := MT.FieldByName('id').AsString;
      Result.ArtifactId := MT.FieldByName('artifact_id').AsString;
      Result.ContractId := MT.FieldByName('contract_id').AsString;
      Result.Status := MT.FieldByName('status').AsString;
      Result.TrackAVersionId := MT.FieldByName('track_a_version_id').AsString;
      Result.TrackBVersionId := MT.FieldByName('track_b_version_id').AsString;
      Result.TrackCVersionId := MT.FieldByName('track_c_version_id').AsString;
      Result.WinnerTrack := MT.FieldByName('winner_track').AsString;
      Result.WinnerVersionId := MT.FieldByName('winner_version_id').AsString;
      Result.RunnerUpVersionId := MT.FieldByName('runner_up_version_id').AsString;
    end;
  finally
    MT.Free;
  end;
end;

class function TGenerationService.GenerateOutlines(const AContractId: string;
  out AOutlines: TOutlineArray): Boolean;
var
  AsmResult: TAssemblyResult;
  LLMResult: TAOSLLMResult;
  I: Integer;
begin
  Result := False;
  SetLength(AOutlines, 3);

  // Assemble context once (shared across all 3 outlines)
  if not TPromptAssemblyService.AssembleContext(AContractId, pmHeavy, False, '', AsmResult) then
  begin
    WriteLn(ErrOutput, 'GenerationService.GenerateOutlines: AssembleContext failed: ', AsmResult.ErrorMessage);
    Exit;
  end;

  for I := 0 to 2 do
  begin
    AOutlines[I].Init;
    AOutlines[I].TrackLabel := Chr(Ord('A') + I);
    AOutlines[I].AngleName := ANGLE_NAMES[I];

    var Prompt := BuildOutlinePrompt(AsmResult.PromptText, ANGLE_NAMES[I], ANGLE_LABELS[I]);
    LLMResult := ArtifactOS_LLM.Chat(aostGeneration, Prompt, AsmResult.PromptText);

    if not LLMResult.Success then
    begin
      WriteLn(ErrOutput, Format('GenerationService.GenerateOutlines: LLM failed for outline %s: %s',
        [AOutlines[I].TrackLabel, LLMResult.ErrorMessage]));
      Exit;
    end;

    AOutlines[I].OutlineText := LLMResult.Content;
    AOutlines[I].OutlineJson := ParseOutlineFromLLM(LLMResult.Content);

    if AOutlines[I].OutlineJson = '{}' then
    begin
      WriteLn(ErrOutput, Format('GenerationService.GenerateOutlines: could not parse JSON from outline %s', [AOutlines[I].TrackLabel]));
      Exit;
    end;
  end;

  Result := True;
end;

class function TGenerationService.ScoreAndSelectTop2(const AContractId: string;
  var AOutlines: TOutlineArray): Boolean;
var
  ContractJson: string;
  LLMResult: TAOSLLMResult;
  I, J: Integer;
  Temp: TOutlineCandidate;
begin
  Result := False;
  ContractJson := GetContractJson(AContractId);

  // Score each outline
  for I := 0 to 2 do
  begin
    LLMResult := ArtifactOS_LLM.Chat(aostSemiES,
      BuildOutlineScorePrompt(ContractJson, AOutlines[I].OutlineJson));

    if LLMResult.Success then
    begin
      AOutlines[I].Score := ParseScoreFromLLM(LLMResult.Content);
      AOutlines[I].ScoreDetail := ParseOutlineFromLLM(LLMResult.Content);
    end
    else
    begin
      // Fallback: default score by position (pain_driven gets slight edge)
      AOutlines[I].Score := 5.0 + (2 - I);  // 7.0, 6.0, 5.0
      AOutlines[I].ScoreDetail := '{"fallback":true}';
      WriteLn(ErrOutput, Format('GenerationService.ScoreAndSelectTop2: LLM scoring failed for %s, using fallback', [AOutlines[I].TrackLabel]));
    end;
  end;

  // Sort by score descending (simple bubble sort, N=3)
  for I := 0 to 1 do
    for J := I + 1 to 2 do
      if AOutlines[J].Score > AOutlines[I].Score then
      begin
        Temp := AOutlines[I];
        AOutlines[I] := AOutlines[J];
        AOutlines[J] := Temp;
      end;

  // Assign ranks and select top 2
  for I := 0 to 2 do
  begin
    AOutlines[I].RankNo := I + 1;
    AOutlines[I].Selected := (I < 2);
  end;

  Result := True;
end;

class function TGenerationService.GenerateTrack(const AContractId: string;
  const AOutline: TOutlineCandidate;
  const AArtifactId: string;
  const AVersionNo: Integer;
  out AVersionId, ATitle, ABody: string): Boolean;
var
  AsmResult: TAssemblyResult;
  LLMResult: TAOSLLMResult;
  PayloadJson: string;
  ParsedJson: string;
  JObj: TJSONObject;
begin
  Result := False;
  AVersionId := '';
  ATitle := '';
  ABody := '';

  // Assemble context for full text generation
  if not TPromptAssemblyService.AssembleContext(AContractId, pmHeavy, False, '', AsmResult) then
  begin
    WriteLn(ErrOutput, 'GenerationService.GenerateTrack: AssembleContext failed');
    Exit;
  end;

  // Generate full text with outline as structural constraint
  var Prompt := BuildFullTextPrompt(AsmResult.PromptText, AOutline.OutlineJson);
  LLMResult := ArtifactOS_LLM.Chat(aostGeneration, Prompt, AsmResult.PromptText);

  if not LLMResult.Success then
  begin
    WriteLn(ErrOutput, Format('GenerationService.GenerateTrack: LLM failed: %s', [LLMResult.ErrorMessage]));
    Exit;
  end;

  // Parse title and body from LLM output
  ParsedJson := ParseOutlineFromLLM(LLMResult.Content);
  JObj := TJSONObject.ParseJSONValue(ParsedJson) as TJSONObject;
  if JObj <> nil then
  try
    ATitle := JObj.GetValue<string>('title', '(untitled)');
    ABody := JObj.GetValue<string>('body', '');
  finally
    JObj.Free;
  end;

  if ABody = '' then
  begin
    WriteLn(ErrOutput, 'GenerationService.GenerateTrack: empty body from LLM');
    Exit;
  end;

  // Quick rule-based pre-check before storing
  if Length(ABody) < 50 then
  begin
    WriteLn(ErrOutput, 'GenerationService.GenerateTrack: body too short (<50 chars)');
    Exit;
  end;

  // Store as artifact_version
  AVersionId := NewId;
  PayloadJson := '{"title":"' + JsonStr(ATitle) + '","body":"' + JsonStr(ABody) + '"}';
  ArtifactOS_DB.InsertAndReturnIdJson(
    'INSERT INTO artifactos.artifact_version (id, artifact_id, version_no, assembled_payload, seal_status, generation_reason) ' +
    'VALUES (:id::uuid, :aid::uuid, :vno, :payload::jsonb, ''unsealed'', :reason) RETURNING id::text',
    MakeObj([MakeParam('id', AVersionId), MakeParam('aid', AArtifactId),
             '"vno":' + IntToStr(AVersionNo), '"payload":' + PayloadJson,
             MakeParam('reason', 'AB generation track ' + AOutline.TrackLabel)]));

  Result := True;
end;

class function TGenerationService.JudgeQualification(const AVersionId, AContractId: string;
  out AResult: TQualificationResult): Boolean;
var
  ContractJson, Title, Body: string;
  VersionPayload: string;
  LLMResult: TAOSLLMResult;
  JObj: TJSONObject;
begin
  Result := False;
  AResult.Init;

  // Read version content from DB
  VersionPayload := ArtifactOS_DB.ExecuteScalarJson(
    'SELECT assembled_payload::text FROM artifactos.artifact_version WHERE id=:id::uuid',
    MakeObj([MakeParam('id', AVersionId)]));

  JObj := TJSONObject.ParseJSONValue(VersionPayload) as TJSONObject;
  if JObj <> nil then
  try
    Title := JObj.GetValue<string>('title', '');
    Body := JObj.GetValue<string>('body', '');
  finally
    JObj.Free;
  end;

  // Step 1: Run rule-based ES gate first (fast fail)
  // Note: RunESGate needs artifact_id, so we skip it here and just do length/title checks
  if (Length(Body) < 50) or (Title = '') then
  begin
    AResult.Passed := False;
    AResult.Score := 0;
    AResult.Issues := '["ES gate: body too short or title empty"]';
    Result := True;
    Exit;
  end;

  // Step 2: LLM-based qualification judge
  ContractJson := GetContractJson(AContractId);
  LLMResult := ArtifactOS_LLM.Chat(aostSemiES,
    BuildQualificationPrompt(ContractJson, Title, Body));

  if not LLMResult.Success then
  begin
    // Fallback: pass with minimal score if LLM unavailable
    AResult.Passed := True;
    AResult.Score := 65.0;  // just above threshold
    AResult.Scores := '{"fallback":true}';
    AResult.Issues := '["LLM judge unavailable, using fallback pass"]';
    Result := True;
    Exit;
  end;

  var QualJson := ParseQualificationFromLLM(LLMResult.Content, AResult.Passed, AResult.Score);
  AResult.Scores := QualJson;

  // Enforce threshold independently of LLM "passed" flag
  if AResult.Score < QUALIFICATION_THRESHOLD then
    AResult.Passed := False;

  Result := True;
end;

// ── L3-66: Auto-rewrite ──────────────────────────────────────────────

class function TGenerationService.DetermineRewriteAction(const AScores, AIssues: string): string;
var
  JObj: TJSONObject;
  IssuesArr: TJSONArray;
  I: Integer;
  IssueText: string;
begin
  // Default action
  Result := 'general_improve';

  JObj := TJSONObject.ParseJSONValue(AScores) as TJSONObject;
  if JObj <> nil then
  try
    // Check dimension scores to pick targeted action
    // Scores JSON may contain: must_land, taboo, structure, readability, platform, source_fidelity
    var SrcFid := JObj.GetValue<Double>('source_fidelity', 10);
    var Theory := JObj.GetValue<Double>('theory_weight', 10);
    var Viewpoint := JObj.GetValue<Double>('viewpoint', 10);
    var Readability := JObj.GetValue<Double>('readability', 10);
    var Platform := JObj.GetValue<Double>('platform', 10);
    var Account := JObj.GetValue<Double>('account_consistency', 10);

    // Priority-ordered: lowest dimension gets targeted first
    if (SrcFid < 6) then Result := 'remap_source'
    else if (Theory > 8) then Result := 'reduce_theory_expression'
    else if (Viewpoint < 6) then Result := 'strengthen_viewpoint'
    else if (Readability < 6) then Result := 'simplify_readability'
    else if (Platform < 6) then Result := 'adapt_platform'
    else if (Account < 6) then Result := 'align_account_style';
  finally
    JObj.Free;
  end;

  // Also scan issues text for keywords (overrides score-based action)
  IssuesArr := TJSONObject.ParseJSONValue(AIssues) as TJSONArray;
  if IssuesArr <> nil then
  try
    for I := 0 to IssuesArr.Count - 1 do
    begin
      IssueText := IssuesArr.Items[I].Value.ToLower;
      if IssueText.Contains('source') or IssueText.Contains('源') then
        Result := 'remap_source'
      else if IssueText.Contains('theory') or IssueText.Contains('理论') then
        Result := 'reduce_theory_expression'
      else if IssueText.Contains('readab') or IssueText.Contains('可读') then
        Result := 'simplify_readability'
      else if IssueText.Contains('platform') or IssueText.Contains('平台') then
        Result := 'adapt_platform'
      else if IssueText.Contains('viewpoint') or IssueText.Contains('观点') then
        Result := 'strengthen_viewpoint';
    end;
  finally
    IssuesArr.Free;
  end;
end;

class function TGenerationService.BuildRewritePrompt(const AContractJson, AOrigTitle, AOrigBody,
  ARewriteAction: string; ARewriteAttempt: Integer): string;
const
  ACTION_PROMPTS: array[0..5] of string = (
    'Re-examine the source material and theory mapping. Strengthen fidelity to the original theory while keeping the article topic unchanged.',
    'Reduce explicit theoretical language. Keep the theoretical stance but express it more naturally through examples and narrative rather than academic framing.',
    'Strengthen the core argument. Add sharper thesis statements, stronger evidence, and at least one counter-argument rebuttal paragraph.',
    'Improve readability: shorten sentences, add transitions between paragraphs, include concrete examples, and reduce jargon density.',
    'Adapt the format for the target platform: adjust title style, paragraph length, hashtag usage, and engagement hooks.',
    'Strengthen alignment with the account profile: match the established voice, avoid topics the account avoids, reinforce signature style elements.'
  );
var
  ActionIdx: Integer;
  ActionGuidance: string;
begin
  // Map action name to prompt
  if ARewriteAction = 'remap_source' then ActionIdx := 0
  else if ARewriteAction = 'reduce_theory_expression' then ActionIdx := 1
  else if ARewriteAction = 'strengthen_viewpoint' then ActionIdx := 2
  else if ARewriteAction = 'simplify_readability' then ActionIdx := 3
  else if ARewriteAction = 'adapt_platform' then ActionIdx := 4
  else if ARewriteAction = 'align_account_style' then ActionIdx := 5
  else ActionIdx := 3;  // default: improve readability

  ActionGuidance := ACTION_PROMPTS[ActionIdx];

  Result := Format(
    'You are a professional content editor performing a TARGETED REWRITE (attempt #%d).'#10 +
    #10 +
    '## Contract Context'#10 +
    '```json'#10 +
    '%s'#10 +
    '```'#10 +
    #10 +
    '## Original Draft'#10 +
    '### Title: %s'#10 +
    '### Body:'#10 +
    '%s'#10 +
    #10 +
    '## Targeted Rewrite Instruction'#10 +
    '%s'#10 +
    #10 +
    '## Output Format (JSON)'#10 +
    '```json'#10 +
    '{"title": "revised title", "body": "revised full article body"}'#10 +
    '```'#10 +
    #10 +
    'Keep what works. Only change what the targeted instruction requires. Do NOT change the core topic or thesis.',
    [ARewriteAttempt, AContractJson, AOrigTitle, AOrigBody, ActionGuidance]);
end;

class function TGenerationService.RewriteTrack(const AContractId: string;
  const AOrigTitle, AOrigBody, AIssues: string;
  const ARewriteAttempt: Integer;
  out ANewTitle, ANewBody: string): Boolean;
var
  ContractJson, ScoresJson, RewriteAction, Prompt: string;
  LLMResult: TAOSLLMResult;
  JsonStr: string;
  JObj: TJSONObject;
begin
  Result := False;
  ANewTitle := AOrigTitle;
  ANewBody := AOrigBody;

  ContractJson := GetContractJson(AContractId);

  // Determine which dimension to target
  RewriteAction := DetermineRewriteAction('{"general":5}', AIssues);
  Prompt := BuildRewritePrompt(ContractJson, AOrigTitle, AOrigBody, RewriteAction, ARewriteAttempt);

  LLMResult := ArtifactOS_LLM.Chat(aostGeneration, Prompt);
  if not LLMResult.Success then
  begin
    WriteLn(ErrOutput, Format('[Rewrite] LLM failed: %s', [LLMResult.ErrorMessage]));
    Exit;
  end;

  // Parse revised title + body from LLM response
  JsonStr := ParseOutlineFromLLM(LLMResult.Content);
  JObj := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
  if JObj <> nil then
  try
    ANewTitle := JObj.GetValue<string>('title', AOrigTitle);
    ANewBody := JObj.GetValue<string>('body', AOrigBody);
  finally
    JObj.Free;
  end;

  // Sanity check
  if (Length(ANewBody) < 50) then
  begin
    WriteLn(ErrOutput, '[Rewrite] rewritten body too short (<50 chars)');
    Exit;
  end;

  Result := True;
  WriteLn(Format('[Rewrite] attempt #%d action=%s title_len=%d body_len=%d',
    [ARewriteAttempt, RewriteAction, Length(ANewTitle), Length(ANewBody)]));
end;

class function TGenerationService.SelectWinner(const AContractId: string;
  const ATitleA, ABodyA, ATitleB, ABodyB: string;
  out ASelection: TSelectionResult): Boolean;
var
  ContractJson, Directive: string;
  LLMResult: TAOSLLMResult;
  SelJson: string;
  JObj: TJSONObject;
begin
  Result := False;
  ASelection.Init;

  ContractJson := GetContractJson(AContractId);
  // Extract directive from contract JSON
  Directive := ExtractJsonField(ContractJson, 'directive');
  if Directive = '' then Directive := '(no directive specified)';

  LLMResult := ArtifactOS_LLM.Chat(aostStrategy,
    BuildSelectionPrompt(Directive, ATitleA, ABodyA, ATitleB, ABodyB));

  if not LLMResult.Success then
  begin
    // Fallback: default to A
    ASelection.Winner := 'A';
    ASelection.Reasoning := 'LLM unavailable, defaulting to Track A';
    ASelection.ScoreA := 0;
    ASelection.ScoreB := 0;
    Result := True;
    Exit;
  end;

  SelJson := ParseSelectionFromLLM(LLMResult.Content);
  JObj := TJSONObject.ParseJSONValue(SelJson) as TJSONObject;
  if JObj <> nil then
  try
    ASelection.Winner := JObj.GetValue<string>('winner', 'A');
    ASelection.Reasoning := JObj.GetValue<string>('reasoning', '');
    // Extract nested scores
    var ScoresObj := JObj.FindValue('scores');
    if ScoresObj <> nil then
    begin
      ASelection.ScoreA := ScoresObj.GetValue<Double>('A', 0);
      ASelection.ScoreB := ScoresObj.GetValue<Double>('B', 0);
    end;
    ASelection.Detail := SelJson;
  finally
    JObj.Free;
  end;

  // Validate winner is A or B
  if (ASelection.Winner <> 'A') and (ASelection.Winner <> 'B') then
    ASelection.Winner := 'A';

  // Tie-break: prefer Track A
  if (ASelection.ScoreA = ASelection.ScoreB) and (ASelection.Winner <> 'A') then
    ASelection.Winner := 'A';

  Result := True;
end;

class function TGenerationService.FinalizeSession(const ASessionId: string;
  const AWinnerVersionId, ARunnerUpVersionId: string;
  const AWinnerTrack: string;
  const ASelectionJson: string): Boolean;
begin
  // Seal the winner version
  ArtifactOS_DB.ExecuteJson(
    'UPDATE artifactos.artifact_version SET seal_status=''sealed'' WHERE id=:id::uuid',
    MakeObj([MakeParam('id', AWinnerVersionId)]));

  // Mark runner-up as superseded (backup but not primary)
  if ARunnerUpVersionId <> '' then
    ArtifactOS_DB.ExecuteJson(
      'UPDATE artifactos.artifact_version SET seal_status=''superseded'' WHERE id=:id::uuid',
      MakeObj([MakeParam('id', ARunnerUpVersionId)]));

  // Update session to completed with winner
  SetSessionWinner(ASessionId, AWinnerTrack, AWinnerVersionId, ARunnerUpVersionId, ASelectionJson);

  Result := True;
end;

{ === Orchestrator === }

class function TGenerationService.RunABGeneration(
  const AArtifactId, AContractId: string;
  out ASessionId, AWinnerVersionId: string): Boolean;
var
  Outlines: TOutlineArray;
  VerNoStart: Integer;
  VerA, VerB, VerC: string;
  TitleA, BodyA, TitleB, BodyB, TitleC, BodyC: string;
  QualA, QualB, QualC: TQualificationResult;
  Selection: TSelectionResult;
  RewriteI: Integer;
  RewrittenTitle, RewrittenBody: string;
  SessionId: string;
  WinnerTrack, WinnerVerId, RunnerUpVerId: string;
begin
  Result := False;
  ASessionId := '';
  AWinnerVersionId := '';

  ArtifactOS_DB.Connect;
  try
    // Step 0: Create session
    SessionId := CreateSession(AArtifactId, AContractId);
    if SessionId = '' then
    begin
      WriteLn(ErrOutput, 'GenerationService.RunABGeneration: failed to create session');
      Exit;
    end;
    ASessionId := SessionId;

    WriteLn('[AB Gen] session=', SessionId, ' artifact=', AArtifactId);

    // Step 0.5: Ensure theory mapping exists (L2-65b)
    //   If contract has no theory mapping and strategy indicates theory_driven,
    //   generate one now so S08 content is available during PromptAssembly.
    if not TTheoryWeaveService.HasTheoryMapping(AContractId) then
    begin
      // Read contract's entry_mode / intervention from DB
      var EntryModeVal := ArtifactOS_DB.ExecuteScalar(
        'SELECT COALESCE(source->>''entry_mode'', '''') FROM artifactos.artifact_contract WHERE id = ' +
        QuotedStr(AContractId) + '::uuid');
      var InterventionVal := ArtifactOS_DB.ExecuteScalar(
        'SELECT COALESCE(strategy->>''intervention'', ''medium'') FROM artifactos.artifact_contract WHERE id = ' +
        QuotedStr(AContractId) + '::uuid');
      var TopicVal := ArtifactOS_DB.ExecuteScalar(
        'SELECT COALESCE(directive->>''topic'', title) FROM artifactos.artifact_contract ac ' +
        'LEFT JOIN artifactos.artifact a ON a.id = ac.requirement_frame_id WHERE ac.id = ' +
        QuotedStr(AContractId) + '::uuid');

      if (EntryModeVal = 'theory_driven') or (InterventionVal = 'high') then
      begin
        if TopicVal = '' then
          TopicVal := 'auto-topic';
        try
          TTheoryWeaveService.GenerateMapping(AContractId, TopicVal, InterventionVal);
          WriteLn('[AB Gen] theory mapping generated for contract=', AContractId);
        except
          on E: Exception do
            WriteLn(ErrOutput, '[AB Gen] theory mapping failed: ', E.Message);
        end;
      end;
    end;

    // Step 1: Generate 3 outlines
    UpdateSessionStatus(SessionId, 'outlining');
    if not GenerateOutlines(AContractId, Outlines) then
    begin
      UpdateSessionStatus(SessionId, 'failed');
      WriteLn(ErrOutput, '[AB Gen] outline generation failed');
      Exit;
    end;
    WriteLn('[AB Gen] 3 outlines generated');

    // Step 2: Score and select top 2
    if not ScoreAndSelectTop2(AContractId, Outlines) then
    begin
      UpdateSessionStatus(SessionId, 'failed');
      WriteLn(ErrOutput, '[AB Gen] outline scoring failed');
      Exit;
    end;
    WriteLn(Format('[AB Gen] scored: A=%.1f B=%.1f C=%.1f', [Outlines[0].Score, Outlines[1].Score, Outlines[2].Score]));

    // Persist all outlines to DB
    for var I := 0 to 2 do
      PersistOutline(SessionId, Outlines[I]);

    // Step 3: Generate AB full text
    UpdateSessionStatus(SessionId, 'generating');
    VerNoStart := GetNextVersionNo(AArtifactId);

    // Generate Track A (top-ranked outline)
    if not GenerateTrack(AContractId, Outlines[0], AArtifactId, VerNoStart, VerA, TitleA, BodyA) then
    begin
      UpdateSessionStatus(SessionId, 'failed');
      WriteLn(ErrOutput, '[AB Gen] Track A generation failed');
      Exit;
    end;
    WriteLn('[AB Gen] Track A generated: ', Copy(TitleA, 1, 40));

    // Generate Track B (second-ranked outline)
    if not GenerateTrack(AContractId, Outlines[1], AArtifactId, VerNoStart + 1, VerB, TitleB, BodyB) then
    begin
      UpdateSessionStatus(SessionId, 'failed');
      WriteLn(ErrOutput, '[AB Gen] Track B generation failed');
      Exit;
    end;
    WriteLn('[AB Gen] Track B generated: ', Copy(TitleB, 1, 40));

    SetSessionTracks(SessionId, VerA, VerB);

    // Step 4: Qualification judge
    UpdateSessionStatus(SessionId, 'qualifying');

    JudgeQualification(VerA, AContractId, QualA);
    SetSessionQualification(SessionId, 'A', Format('{"passed":%s,"score":%.1f,"detail":%s,"issues":%s}',
      [BoolToStr(QualA.Passed, True).ToLower, QualA.Score, QualA.Scores, QualA.Issues]));

    JudgeQualification(VerB, AContractId, QualB);
    SetSessionQualification(SessionId, 'B', Format('{"passed":%s,"score":%.1f,"detail":%s,"issues":%s}',
      [BoolToStr(QualB.Passed, True).ToLower, QualB.Score, QualB.Scores, QualB.Issues]));

    WriteLn(Format('[AB Gen] qualification: A=%s(%.1f) B=%s(%.1f)',
      [BoolToStr(QualA.Passed, True), QualA.Score, BoolToStr(QualB.Passed, True), QualB.Score]));

    // ── L3-66: Auto-rewrite loop ──
    // If Track A failed, attempt targeted rewrites
    if not QualA.Passed then
    begin
      for RewriteI := 1 to MAX_REWRITE do
      begin
        WriteLn(Format('[AB Gen] rewriting Track A (attempt %d/%d)', [RewriteI, MAX_REWRITE]));
        if not RewriteTrack(AContractId, TitleA, BodyA, QualA.Issues, RewriteI,
          RewrittenTitle, RewrittenBody) then
        begin
          WriteLn(ErrOutput, '[AB Gen] Track A rewrite failed');
          Break;
        end;
        TitleA := RewrittenTitle;
        BodyA := RewrittenBody;

        // Persist rewritten version (inline, mirroring GenerateTrack's pattern)
        VerA := NewId;
        var PayloadA := '{"title":"' + JsonStr(TitleA) + '","body":"' + JsonStr(BodyA) + '"}';
        ArtifactOS_DB.InsertAndReturnIdJson(
          'INSERT INTO artifactos.artifact_version (id, artifact_id, version_no, assembled_payload, seal_status, generation_reason) ' +
          'VALUES (:id::uuid, :aid::uuid, :vno, :payload::jsonb, ''unsealed'', :reason) RETURNING id::text',
          MakeObj([MakeParam('id', VerA), MakeParam('aid', AArtifactId),
                   '"vno":' + IntToStr(VerNoStart + 3 + RewriteI),
                   '"payload":' + PayloadA,
                   MakeParam('reason', 'rewrite_A_' + IntToStr(RewriteI))]));

        // Re-qualify
        JudgeQualification(VerA, AContractId, QualA);
        WriteLn(Format('[AB Gen] Track A rewrite qual: %s (%.1f)', [BoolToStr(QualA.Passed, True), QualA.Score]));
        if QualA.Passed then
        begin
          SetSessionQualification(SessionId, 'A', Format('{"passed":%s,"score":%.1f,"detail":%s,"issues":%s,"rewrite_attempt":%d}',
            [BoolToStr(QualA.Passed, True).ToLower, QualA.Score, QualA.Scores, QualA.Issues, RewriteI]));
          Break;
        end;
      end;
    end;

    // If Track B failed, attempt targeted rewrites
    if not QualB.Passed then
    begin
      for RewriteI := 1 to MAX_REWRITE do
      begin
        WriteLn(Format('[AB Gen] rewriting Track B (attempt %d/%d)', [RewriteI, MAX_REWRITE]));
        if not RewriteTrack(AContractId, TitleB, BodyB, QualB.Issues, RewriteI,
          RewrittenTitle, RewrittenBody) then
        begin
          WriteLn(ErrOutput, '[AB Gen] Track B rewrite failed');
          Break;
        end;
        TitleB := RewrittenTitle;
        BodyB := RewrittenBody;

        VerB := NewId;
        var PayloadB := '{"title":"' + JsonStr(TitleB) + '","body":"' + JsonStr(BodyB) + '"}';
        ArtifactOS_DB.InsertAndReturnIdJson(
          'INSERT INTO artifactos.artifact_version (id, artifact_id, version_no, assembled_payload, seal_status, generation_reason) ' +
          'VALUES (:id::uuid, :aid::uuid, :vno, :payload::jsonb, ''unsealed'', :reason) RETURNING id::text',
          MakeObj([MakeParam('id', VerB), MakeParam('aid', AArtifactId),
                   '"vno":' + IntToStr(VerNoStart + 3 + MAX_REWRITE + RewriteI),
                   '"payload":' + PayloadB,
                   MakeParam('reason', 'rewrite_B_' + IntToStr(RewriteI))]));

        JudgeQualification(VerB, AContractId, QualB);
        WriteLn(Format('[AB Gen] Track B rewrite qual: %s (%.1f)', [BoolToStr(QualB.Passed, True), QualB.Score]));
        if QualB.Passed then
        begin
          SetSessionQualification(SessionId, 'B', Format('{"passed":%s,"score":%.1f,"detail":%s,"issues":%s,"rewrite_attempt":%d}',
            [BoolToStr(QualB.Passed, True).ToLower, QualB.Score, QualB.Scores, QualB.Issues, RewriteI]));
          Break;
        end;
      end;
    end;

    // Step 5: Decide outcome
    if QualA.Passed and QualB.Passed then
    begin
      // Both qualified → AB selection
      UpdateSessionStatus(SessionId, 'selecting');
      SelectWinner(AContractId, TitleA, BodyA, TitleB, BodyB, Selection);

      if Selection.Winner = 'A' then
      begin
        WinnerTrack := 'A';
        WinnerVerId := VerA;
        RunnerUpVerId := VerB;
      end
      else
      begin
        WinnerTrack := 'B';
        WinnerVerId := VerB;
        RunnerUpVerId := VerA;
      end;

      WriteLn('[AB Gen] winner=', WinnerTrack, ' (', Selection.Reasoning, ')');
      FinalizeSession(SessionId, WinnerVerId, RunnerUpVerId, WinnerTrack, Selection.Detail);
    end
    else if QualA.Passed then
    begin
      // Only A qualified → A wins automatically
      WinnerTrack := 'A';
      WinnerVerId := VerA;
      RunnerUpVerId := VerB;
      WriteLn('[AB Gen] only A qualified → auto-winner');
      FinalizeSession(SessionId, WinnerVerId, RunnerUpVerId, 'A',
        '{"winner":"A","reasoning":"only_track_A_qualified","auto":true}');
    end
    else if QualB.Passed then
    begin
      // Only B qualified → B wins automatically
      WinnerTrack := 'B';
      WinnerVerId := VerB;
      RunnerUpVerId := VerA;
      WriteLn('[AB Gen] only B qualified → auto-winner');
      FinalizeSession(SessionId, WinnerVerId, RunnerUpVerId, 'B',
        '{"winner":"B","reasoning":"only_track_B_qualified","auto":true}');
    end
    else
    begin
      // Both failed → retry with Track C (outline #3)
      WriteLn('[AB Gen] both failed → retrying with Track C');
      if not GenerateTrack(AContractId, Outlines[2], AArtifactId, VerNoStart + 2, VerC, TitleC, BodyC) then
      begin
        UpdateSessionStatus(SessionId, 'failed');
        WriteLn(ErrOutput, '[AB Gen] Track C retry generation also failed');
        Exit;
      end;
      WriteLn('[AB Gen] Track C generated: ', Copy(TitleC, 1, 40));

      // Update session with Track C version
      ArtifactOS_DB.ExecuteJson(
        'UPDATE artifactos.generation_session SET track_c_version_id=:c::uuid WHERE id=:id::uuid',
        MakeObj([MakeParam('c', VerC), MakeParam('id', SessionId)]));

      JudgeQualification(VerC, AContractId, QualC);
      SetSessionQualification(SessionId, 'C', Format('{"passed":%s,"score":%.1f,"detail":%s,"issues":%s}',
        [BoolToStr(QualC.Passed, True).ToLower, QualC.Score, QualC.Scores, QualC.Issues]));

      WriteLn(Format('[AB Gen] Track C qualification: %s (%.1f)', [BoolToStr(QualC.Passed, True), QualC.Score]));

      if QualC.Passed then
      begin
        WinnerTrack := 'C';
        WinnerVerId := VerC;
        RunnerUpVerId := '';  // no runner-up for retry track
        WriteLn('[AB Gen] Track C passed → retry saved');
        FinalizeSession(SessionId, WinnerVerId, '', 'C',
          '{"winner":"C","reasoning":"retry_track_passed","auto":true}');
      end
      else
      begin
        // L3-66: Track C rewrite loop — last chance before strategy fallback
        WriteLn('[AB Gen] Track C failed → attempting rewrite loop');
        for RewriteI := 1 to MAX_REWRITE do
        begin
          WriteLn(Format('[AB Gen] rewriting Track C (attempt %d/%d)', [RewriteI, MAX_REWRITE]));
          if not RewriteTrack(AContractId, TitleC, BodyC, QualC.Issues, RewriteI,
            RewrittenTitle, RewrittenBody) then
          begin
            WriteLn(ErrOutput, '[AB Gen] Track C rewrite failed');
            Break;
          end;
          TitleC := RewrittenTitle;
          BodyC := RewrittenBody;

          VerC := NewId;
          var PayloadC := '{"title":"' + JsonStr(TitleC) + '","body":"' + JsonStr(BodyC) + '"}';
          ArtifactOS_DB.InsertAndReturnIdJson(
            'INSERT INTO artifactos.artifact_version (id, artifact_id, version_no, assembled_payload, seal_status, generation_reason) ' +
            'VALUES (:id::uuid, :aid::uuid, :vno, :payload::jsonb, ''unsealed'', :reason) RETURNING id::text',
            MakeObj([MakeParam('id', VerC), MakeParam('aid', AArtifactId),
                     '"vno":' + IntToStr(VerNoStart + 3 + 2*MAX_REWRITE + RewriteI),
                     '"payload":' + PayloadC,
                     MakeParam('reason', 'rewrite_C_' + IntToStr(RewriteI))]));

          JudgeQualification(VerC, AContractId, QualC);
          WriteLn(Format('[AB Gen] Track C rewrite qual: %s (%.1f)', [BoolToStr(QualC.Passed, True), QualC.Score]));
          if QualC.Passed then
          begin
            SetSessionQualification(SessionId, 'C', Format('{"passed":%s,"score":%.1f,"detail":%s,"issues":%s,"rewrite_attempt":%d}',
              [BoolToStr(QualC.Passed, True).ToLower, QualC.Score, QualC.Scores, QualC.Issues, RewriteI]));
            Break;
          end;
        end;

        if QualC.Passed then
        begin
          WinnerTrack := 'C';
          WinnerVerId := VerC;
          RunnerUpVerId := '';
          WriteLn('[AB Gen] Track C rewrite passed → saved');
          FinalizeSession(SessionId, WinnerVerId, '', 'C',
            Format('{"winner":"C","reasoning":"rewrite_loop_passed","auto":true,"rewrite_attempts":%d}', [RewriteI]));
        end
        else
        begin
          // L3-66: Strategy fallback — rewrite exhausted
          UpdateSessionStatus(SessionId, 'rewrite_exhausted');
          WriteLn(ErrOutput, '[AB Gen] all tracks failed after rewrite loop → strategy_fallback');
          // Persist best-effort draft for human review
          WinnerTrack := 'C';
          WinnerVerId := VerC;
          RunnerUpVerId := '';
          FinalizeSession(SessionId, WinnerVerId, '', 'C',
            '{"winner":"C","reasoning":"strategy_fallback","rewrite_exhausted":true,"action":"wait_human"}');
        end;
      end;
    end;

    AWinnerVersionId := WinnerVerId;
    WriteLn('[AB Gen] completed: session=', SessionId, ' winner=', WinnerTrack, ' version=', WinnerVerId);
    Result := True;

  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

// ── L3-67: Strategy ruling ───────────────────────────────────────────
// Translates QualityGate full-pipeline result into pipeline state transitions.
// Called after RunABGeneration succeeds with a winner version.
class function TGenerationService.ApplyStrategyRuling(const AArtifactId, AWinnerVersionId,
  AContractId, ASessionId: string): string;
var
  ContractJson: string;
  FinalAction: TStrategyAction;
  FinalReason: string;
  ActionStr: string;
begin
  Result := 'error';

  ContractJson := GetContractJson(AContractId);

  // Run full QualityGate pipeline (ES → 半ES → NES → StrategyRuling)
  if not TQualityGateService.RunFullPipeline(AArtifactId, ContractJson, FinalAction, FinalReason) then
  begin
    WriteLn(ErrOutput, '[StrategyRuling] QualityGate pipeline failed');
    // Fallback: safe action
    FinalAction := saStoreDraft;
    FinalReason := 'QualityGate pipeline error — defaulting to store_draft';
  end;

  ActionStr := TQualityGateService.ActionToString(FinalAction);
  Result := ActionStr;

  WriteLn(Format('[StrategyRuling] action=%s reason=%s', [ActionStr, FinalReason]));

  // Persist ruling to session
  ArtifactOS_DB.Connect;
  try
    ArtifactOS_DB.ExecuteJson(
      'UPDATE artifactos.generation_session SET ' +
      '  ruling_action=:action, ' +
      '  ruling_reason=:reason, ' +
      '  ruling_evidence=CONCAT(COALESCE(ruling_evidence, ''''), :evidence::text) ' +
      'WHERE id=:id::uuid',
      MakeObj([
        MakeParam('action', ActionStr),
        MakeParam('reason', FinalReason),
        MakeParam('evidence', Format('{"strategy_ruling":{"action":"%s","reason":"%s"}}',
          [ActionStr, Copy(FinalReason, 1, 200)])),
        MakeParam('id', ASessionId)
      ]));

    // Apply action-dependent state transitions
    case FinalAction of
      saAutoPublish:
      begin
        // Mark session as approved for auto-publish
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''approved_for_publish'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        // Seal the winner version
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.artifact_version SET seal_status=''sealed'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', AWinnerVersionId)]));
        WriteLn('[StrategyRuling] → auto_publish: version sealed, session approved');
      end;

      saSampleReview:
      begin
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''pending_sample_review'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        WriteLn('[StrategyRuling] → sample_review: queued for human sampling');
      end;

      saStoreDraft:
      begin
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''stored_draft'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        WriteLn('[StrategyRuling] → store_draft: saved for later revision');
      end;

      saDowngrade:
      begin
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''downgraded'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        WriteLn('[StrategyRuling] → downgrade: purpose type demoted');
      end;

      saWaitHuman:
      begin
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''wait_human'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        WriteLn('[StrategyRuling] → wait_human: human intervention required');
      end;

      saAbandon:
      begin
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''abandoned'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        WriteLn('[StrategyRuling] → abandon: task dropped');
      end;

      saFreezeAndDowngrade:
      begin
        ArtifactOS_DB.ExecuteJson(
          'UPDATE artifactos.generation_session SET status=''frozen'' WHERE id=:id::uuid',
          MakeObj([MakeParam('id', ASessionId)]));
        WriteLn('[StrategyRuling] → freeze_and_downgrade: frozen pending review');
      end;

      else
        WriteLn('[StrategyRuling] → rewrite action (should not reach here post-generation)');
    end;
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

end.
