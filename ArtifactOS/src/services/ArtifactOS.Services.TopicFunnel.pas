{ ============================================================================
  ArtifactOS.Services.TopicFunnel

  Topic funnel scoring engine v0.
  Implements the three-layer funnel from docs/08:
    Layer 1: Signal capture (manual input → signal record)
    Layer 2: Vertical filtering (4-dimension scoring + strategy matrix)
    Layer 3: Boundary decision (write/store/experiment/don't write/research)

  Phase 1 scope:
    - Manual signal input (7 signal types)
    - 4-dimension basic scoring (coverage, pain, spread, verified)
    - Strategy matrix 10-dimension scoring
    - Write/don't-write/store/experiment/research judgment
    - Persistence to artifactos schema tables
    - LLM-assisted scoring via DeepLLMProxy (Semi-ES tier)

  ============================================================================ }

unit ArtifactOS.Services.TopicFunnel;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  { Signal types from docs/08 §3.1 }
  TAOSTopicSignalType = (
    aostsTrending,      // 热点信号
    aostsAnomaly,       // 异常信号
    aostsTheory,        // 理论命题
    aostsEvergreen,     // 常青信号
    aostsViralHit,      // 爆款信号
    aostsMaterial,      // 素材信号
    aostsFalsification  // 反证信号
  );

  { Boundary decision from docs/08 §4.6 }
  TAOSBoundaryDecision = (
    aobdWriteNow,         // 立即进入 RSC/CTF
    aobdStoreCandidate,   // 存入候选池
    aobdExperiment,       // 实验策略
    aobdDoNotWrite,       // 不写
    aobdResearchQuestion, // 转研究问题
    aobdDraftOnly         // 只生成草稿
  );

  { 4-dimension basic scores from docs/08 §4.1 }
  TAOSBasicScore = record
    Coverage: Double;     // 覆盖人群 (0-10)
    PainPoint: Double;    // 痛点强度 (0-10)
    Spread: Double;       // 传播属性 (0-10)
    Verified: Double;     // 已验证性 (0-10)
    function Composite: Double;
    class function Make(ACoverage, APain, ASpread, AVerified: Double): TAOSBasicScore; static;
  end;

  { Strategy matrix 10-dimension scores from docs/08 §4.5 }
  TAOSStrategyScore = record
    StrategyUnitFit: Double;
    TheoryFit: Double;
    TheoryInterventionLevel: Double;
    TrafficPotential: Double;
    TheoryLevel: Double;
    Readability: Double;
    RiskLevel: Double;
    OperationGoalFit: Double;
    ClaimPotential: Double;
    ResearchValue: Double;
    function Composite(const AWeights: array of Double): Double;
    class function DefaultWeights: TArray<Double>; static;
  end;

  { Signal input for the funnel }
  TAOSSignalInput = record
    SignalType: TAOSTopicSignalType;
    Source: string;
    Title: string;
    Description: string;
    Metadata: string;       // JSON blob (heat_index, keywords, etc.)
    ExpiresAt: TDateTime;
    StrategyUnitId: string; // optional: which strategy unit to evaluate against
  end;

  { Full funnel result for one signal }
  TAOSTopicFunnelResult = record
    SignalId: string;
    BasicScore: TAOSBasicScore;
    BasicComposite: Double;
    StrategyScore: TAOSStrategyScore;
    StrategyComposite: Double;
    Decision: TAOSBoundaryDecision;
    DecisionReason: string;
    Confidence: string;     // low / medium / high
    EnteredLayer3: Boolean;
  end;

  { The scoring engine }
  TAOSTopicFunnelEngine = class
  private
    class procedure RuleBasedScore(const AInput: TAOSSignalInput;
      out AResult: TAOSTopicFunnelResult);
    class procedure PersistScore(const AResult: TAOSTopicFunnelResult;
      const AStrategyUnitId: string);
  public
    { Layer 1: Create a signal record in DB, return signal_id }
    class function CaptureSignal(const AInput: TAOSSignalInput;
      out ASignalId: string): Boolean;

    { Layer 2: Score a signal by ID — uses LLM if available }
    class function ScoreSignal(const ASignalId: string;
      out AResult: TAOSTopicFunnelResult): Boolean;

    { Layer 2 direct: Score without DB lookup, for in-memory evaluation }
    class function ScoreDirect(const AInput: TAOSSignalInput;
      out AResult: TAOSTopicFunnelResult): Boolean;

    { Layer 3: Make boundary decision based on scores }
    class function DecideBoundary(const ABasic: TAOSBasicScore;
      const AStrategy: TAOSStrategyScore;
      const ASignalType: TAOSTopicSignalType): TAOSBoundaryDecision;

    { Get candidates that passed Layer 2 for 10-3-1 selection }
    class function GetCandidatesForFocus(
      out ACandidates: TArray<TAOSTopicFunnelResult>): Boolean;

    { Single-pass chain: scored signal → RSC → CTF → ContractCandidate }
    class function RunSinglePassChain(const ASignalId: string;
      out AContractId: string; out AChainJson: string): Boolean;

    { Utility: display names }
    class function SignalTypeName(AType: TAOSTopicSignalType): string;
    class function DecisionName(ADecision: TAOSBoundaryDecision): string;
  end;

implementation

uses
  FireDAC.Comp.Client, FireDAC.Stan.Param,
  DeepBase.LLM,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.DeepLLMProxy,
  ArtifactOS.Services.ContractPipeline;

{ TAOSBasicScore }

class function TAOSBasicScore.Make(ACoverage, APain, ASpread,
  AVerified: Double): TAOSBasicScore;
begin
  Result.Coverage := ACoverage;
  Result.PainPoint := APain;
  Result.Spread := ASpread;
  Result.Verified := AVerified;
end;

function TAOSBasicScore.Composite: Double;
begin
  // 覆盖人群×0.3 + 痛点强度×0.3 + 传播属性×0.2 + 已验证性×0.2
  Result := Coverage * 0.3 + PainPoint * 0.3 + Spread * 0.2 + Verified * 0.2;
end;

{ TAOSStrategyScore }

class function TAOSStrategyScore.DefaultWeights: TArray<Double>;
begin
  // Default equal weights; strategy units can override via DB config
  SetLength(Result, 10);
  Result[0] := 0.15;  // strategy_unit_fit
  Result[1] := 0.15;  // theory_fit
  Result[2] := 0.05;  // theory_intervention_level
  Result[3] := 0.10;  // traffic_potential
  Result[4] := 0.05;  // theory_level
  Result[5] := 0.05;  // readability
  Result[6] := 0.15;  // risk_level (inverted: high risk = lower score)
  Result[7] := 0.10;  // operation_goal_fit
  Result[8] := 0.10;  // claim_potential
  Result[9] := 0.10;  // research_value
end;

function TAOSStrategyScore.Composite(
  const AWeights: array of Double): Double;
begin
  Result :=
    StrategyUnitFit * AWeights[0] +
    TheoryFit * AWeights[1] +
    TheoryInterventionLevel * AWeights[2] +
    TrafficPotential * AWeights[3] +
    TheoryLevel * AWeights[4] +
    Readability * AWeights[5] +
    (10 - RiskLevel) * AWeights[6] +  // inverted: lower risk = higher score
    OperationGoalFit * AWeights[7] +
    ClaimPotential * AWeights[8] +
    ResearchValue * AWeights[9];
end;

{ TAOSTopicFunnelEngine }

class function TAOSTopicFunnelEngine.SignalTypeName(
  AType: TAOSTopicSignalType): string;
const
  Names: array[TAOSTopicSignalType] of string = (
    'trending', 'anomaly', 'theory', 'evergreen',
    'viral_hit', 'material', 'falsification');
begin
  Result := Names[AType];
end;

class function TAOSTopicFunnelEngine.DecisionName(
  ADecision: TAOSBoundaryDecision): string;
const
  Names: array[TAOSBoundaryDecision] of string = (
    'write_now', 'store_candidate', 'experiment',
    'do_not_write', 'research_question', 'draft_only');
begin
  Result := Names[ADecision];
end;

class function TAOSTopicFunnelEngine.CaptureSignal(
  const AInput: TAOSSignalInput;
  out ASignalId: string): Boolean;
var
  Q: TFDQuery;
begin
  Result := False;
  ASignalId := '';

  try
    ArtifactOS_DB.Connect;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := ArtifactOS_DB.Connection;
        Q.SQL.Text :=
          'INSERT INTO artifactos.event_signal (' +
          '  signal_type, source, title, description, metadata_json, ' +
          '  captured_at, expires_at, signal_status' +
          ') VALUES (' +
          '  :stype, :source, :title, :desc, :meta, ' +
          '  now(), :expires, ''captured''' +
          ') RETURNING id::text';
        Q.ParamByName('stype').AsString := SignalTypeName(AInput.SignalType);
        Q.ParamByName('source').AsString := AInput.Source;
        Q.ParamByName('title').AsString := AInput.Title;
        Q.ParamByName('desc').AsString := AInput.Description;
        Q.ParamByName('meta').AsString := AInput.Metadata;
        if AInput.ExpiresAt > 0 then
          Q.ParamByName('expires').AsDateTime := AInput.ExpiresAt
        else
          Q.ParamByName('expires').Clear;
        Q.Open;
        if not Q.Eof then
        begin
          ASignalId := Q.Fields[0].AsString;
          Result := True;
        end;
      finally
        Q.Free;
      end;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    // DB unavailable
  end;
end;

class function TAOSTopicFunnelEngine.ScoreSignal(const ASignalId: string;
  out AResult: TAOSTopicFunnelResult): Boolean;
var
  Input: TAOSSignalInput;
  SignalTypeStr: string;
  Q: TFDQuery;
begin
  Result := False;

  try
    ArtifactOS_DB.Connect;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := ArtifactOS_DB.Connection;
        Q.SQL.Text :=
          'SELECT signal_type, source, title, description, metadata_json, expires_at ' +
          'FROM artifactos.event_signal WHERE id = :id::uuid';
        Q.ParamByName('id').AsString := ASignalId;
        Q.Open;
        if Q.Eof then Exit;

        SignalTypeStr := Q.FieldByName('signal_type').AsString;
        Input.Source := Q.FieldByName('source').AsString;
        Input.Title := Q.FieldByName('title').AsString;
        Input.Description := Q.FieldByName('description').AsString;
        Input.Metadata := Q.FieldByName('metadata_json').AsString;
        if not Q.FieldByName('expires_at').IsNull then
          Input.ExpiresAt := Q.FieldByName('expires_at').AsDateTime
        else
          Input.ExpiresAt := 0;

        // Parse signal type
        if SignalTypeStr = 'trending' then Input.SignalType := aostsTrending
        else if SignalTypeStr = 'anomaly' then Input.SignalType := aostsAnomaly
        else if SignalTypeStr = 'theory' then Input.SignalType := aostsTheory
        else if SignalTypeStr = 'evergreen' then Input.SignalType := aostsEvergreen
        else if SignalTypeStr = 'viral_hit' then Input.SignalType := aostsViralHit
        else if SignalTypeStr = 'material' then Input.SignalType := aostsMaterial
        else if SignalTypeStr = 'falsification' then Input.SignalType := aostsFalsification
        else Input.SignalType := aostsTrending;
      finally
        Q.Free;
      end;

      AResult.SignalId := ASignalId;
      Result := ScoreDirect(Input, AResult);
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    // DB unavailable
  end;
end;

class function TAOSTopicFunnelEngine.ScoreDirect(const AInput: TAOSSignalInput;
  out AResult: TAOSTopicFunnelResult): Boolean;

  function Clamp(const V: Double): Double;
  begin
    if V < 0 then Result := 0
    else if V > 10 then Result := 10
    else Result := V;
  end;

var
  LLM: TArtifactOSLLMProxy;
  LLMResult: TAOSLLMResult;
  Prompt: string;
  Msg: TLLMMessages;
  StrategyWeights: TArray<Double>;
  JSON: TJSONObject;
begin
  Result := True;
  AResult.SignalId := '';

  // Try LLM-assisted scoring first (Semi-ES tier: lightweight reasoning)
  LLM := ArtifactOS_LLM;
  if LLM.IsAvailable then
  begin
    Prompt :=
      'You are a topic scoring engine for a content strategy system. ' +
      'Score the following topic on a 0-10 scale for each dimension.' +
      sLineBreak + sLineBreak +
      'Signal type: ' + SignalTypeName(AInput.SignalType) + sLineBreak +
      'Source: ' + AInput.Source + sLineBreak +
      'Title: ' + AInput.Title + sLineBreak +
      'Description: ' + AInput.Description + sLineBreak + sLineBreak +
      'Respond in this exact JSON format (no other text):' + sLineBreak +
      '{"coverage":N,"pain":N,"spread":N,"verified":N,' +
      '"strategy_fit":N,"theory_fit":N,"theory_intervention":N,' +
      '"traffic":N,"theory_level":N,"readability":N,' +
      '"risk":N,"op_goal_fit":N,"claim_potential":N,"research":N,' +
      '"confidence":"low|medium|high","reason":"brief reason"}' + sLineBreak +
      'Replace N with a number 0-10. risk: 10=extremely risky, 0=no risk.';

    SetLength(Msg, 1);
    Msg[0].Role := 'user';
    Msg[0].Content := Prompt;

    LLMResult := LLM.ChatMultiTurn(aostSemiES, Msg, 500);

    if LLMResult.Success then
    begin
      // Parse JSON response
      try
        JSON := TJSONObject.ParseJSONValue(LLMResult.Content) as TJSONObject;
        if Assigned(JSON) then
        try
          AResult.BasicScore.Coverage := Clamp(JSON.GetValue<Double>('coverage'));
          AResult.BasicScore.PainPoint := Clamp(JSON.GetValue<Double>('pain'));
          AResult.BasicScore.Spread := Clamp(JSON.GetValue<Double>('spread'));
          AResult.BasicScore.Verified := Clamp(JSON.GetValue<Double>('verified'));

          AResult.StrategyScore.StrategyUnitFit := Clamp(JSON.GetValue<Double>('strategy_fit'));
          AResult.StrategyScore.TheoryFit := Clamp(JSON.GetValue<Double>('theory_fit'));
          AResult.StrategyScore.TheoryInterventionLevel := Clamp(JSON.GetValue<Double>('theory_intervention'));
          AResult.StrategyScore.TrafficPotential := Clamp(JSON.GetValue<Double>('traffic'));
          AResult.StrategyScore.TheoryLevel := Clamp(JSON.GetValue<Double>('theory_level'));
          AResult.StrategyScore.Readability := Clamp(JSON.GetValue<Double>('readability'));
          AResult.StrategyScore.RiskLevel := Clamp(JSON.GetValue<Double>('risk'));
          AResult.StrategyScore.OperationGoalFit := Clamp(JSON.GetValue<Double>('op_goal_fit'));
          AResult.StrategyScore.ClaimPotential := Clamp(JSON.GetValue<Double>('claim_potential'));
          AResult.StrategyScore.ResearchValue := Clamp(JSON.GetValue<Double>('research'));

          AResult.Confidence := JSON.GetValue<string>('confidence');
          AResult.DecisionReason := JSON.GetValue<string>('reason');

          AResult.BasicComposite := AResult.BasicScore.Composite;
          StrategyWeights := TAOSStrategyScore.DefaultWeights;
          AResult.StrategyComposite := AResult.StrategyScore.Composite(StrategyWeights);
          AResult.Decision := DecideBoundary(AResult.BasicScore,
            AResult.StrategyScore, AInput.SignalType);
          AResult.EnteredLayer3 := AResult.BasicComposite >= 7.0;

          // Persist result
          PersistScore(AResult, AInput.StrategyUnitId);
          Exit;
        finally
          JSON.Free;
        end;
      except
        // JSON parse failed, fall through to rule-based scoring
      end;
    end;
  end;

  // Rule-based fallback scoring (ES tier)
  RuleBasedScore(AInput, AResult);
  AResult.BasicComposite := AResult.BasicScore.Composite;
  StrategyWeights := TAOSStrategyScore.DefaultWeights;
  AResult.StrategyComposite := AResult.StrategyScore.Composite(StrategyWeights);
  AResult.Decision := DecideBoundary(AResult.BasicScore,
    AResult.StrategyScore, AInput.SignalType);
  AResult.EnteredLayer3 := AResult.BasicComposite >= 7.0;
  AResult.Confidence := 'low';

  // Persist result
  PersistScore(AResult, AInput.StrategyUnitId);
end;

class function TAOSTopicFunnelEngine.DecideBoundary(
  const ABasic: TAOSBasicScore;
  const AStrategy: TAOSStrategyScore;
  const ASignalType: TAOSTopicSignalType): TAOSBoundaryDecision;
var
  BasicComp: Double;
begin
  BasicComp := ABasic.Composite;

  // Layer 2 threshold
  if BasicComp < 5.0 then
  begin
    // Check if it has research value despite low传播
    if AStrategy.ResearchValue >= 7.0 then
      Exit(aobdResearchQuestion);
    Exit(aobdDoNotWrite);
  end;

  // High risk → draft only or don't write
  if AStrategy.RiskLevel >= 8.0 then
  begin
    if AStrategy.ResearchValue >= 6.0 then
      Exit(aobdResearchQuestion);
    Exit(aobdDoNotWrite);
  end;

  // Falsification signals always become research questions
  if ASignalType = aostsFalsification then
    Exit(aobdResearchQuestion);

  // Anomaly signals → research or experiment
  if ASignalType = aostsAnomaly then
  begin
    if AStrategy.TheoryFit >= 7.0 then
      Exit(aobdWriteNow);
    Exit(aobdResearchQuestion);
  end;

  // 5.0-6.9: store candidate
  if BasicComp < 7.0 then
    Exit(aobdStoreCandidate);

  // >= 7.0 and low risk: write now
  if AStrategy.RiskLevel <= 3.0 then
    Exit(aobdWriteNow);

  // Medium risk: experiment
  if AStrategy.RiskLevel <= 6.0 then
    Exit(aobdExperiment);

  // High risk but above threshold: draft only
  Exit(aobdDraftOnly);
end;

class function TAOSTopicFunnelEngine.GetCandidatesForFocus(
  out ACandidates: TArray<TAOSTopicFunnelResult>): Boolean;
var
  Q: TFDQuery;
  List: TArray<TAOSTopicFunnelResult>;
  Item: TAOSTopicFunnelResult;
  DecStr: string;
begin
  Result := False;
  SetLength(ACandidates, 0);
  SetLength(List, 0);

  try
    ArtifactOS_DB.Connect;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := ArtifactOS_DB.Connection;
        Q.SQL.Text :=
          'SELECT es.id::text, es.signal_type, es.title, ' +
          '  ts.basic_composite, ts.strategy_composite, ts.boundary_decision, ' +
          '  ts.coverage_score, ts.pain_score, ts.spread_score, ts.verified_score ' +
          'FROM artifactos.topic_score ts ' +
          'JOIN artifactos.event_signal es ON es.id = ts.signal_id ' +
          'WHERE ts.boundary_decision IN (''write_now'', ''experiment'', ''draft_only'') ' +
          '  AND ts.basic_composite >= 7.0 ' +
          'ORDER BY ts.strategy_composite DESC ' +
          'LIMIT 10';
        Q.Open;
        while not Q.Eof do
        begin
          Item := Default(TAOSTopicFunnelResult);
          Item.SignalId := Q.FieldByName('id').AsString;
          Item.BasicComposite := Q.FieldByName('basic_composite').AsFloat;
          Item.StrategyComposite := Q.FieldByName('strategy_composite').AsFloat;
          Item.BasicScore.Coverage := Q.FieldByName('coverage_score').AsFloat;
          Item.BasicScore.PainPoint := Q.FieldByName('pain_score').AsFloat;
          Item.BasicScore.Spread := Q.FieldByName('spread_score').AsFloat;
          Item.BasicScore.Verified := Q.FieldByName('verified_score').AsFloat;
          Item.EnteredLayer3 := True;
          Item.DecisionReason := '';

          // Parse boundary decision
          DecStr := Q.FieldByName('boundary_decision').AsString;
          if DecStr = 'write_now' then Item.Decision := aobdWriteNow
          else if DecStr = 'experiment' then Item.Decision := aobdExperiment
          else if DecStr = 'draft_only' then Item.Decision := aobdDraftOnly
          else Item.Decision := aobdStoreCandidate;

          SetLength(List, Length(List) + 1);
          List[High(List)] := Item;
          Q.Next;
        end;
      finally
        Q.Free;
      end;

      ACandidates := List;
      Result := Length(List) > 0;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    // DB unavailable
  end;
end;

{ Rule-based fallback scoring (ES tier) }

class procedure TAOSTopicFunnelEngine.RuleBasedScore(
  const AInput: TAOSSignalInput; out AResult: TAOSTopicFunnelResult);
begin
  AResult := Default(TAOSTopicFunnelResult);

  // Conservative defaults based on signal type
  case AInput.SignalType of
    aostsTrending:
    begin
      AResult.BasicScore := TAOSBasicScore.Make(7, 6, 7, 5);
      AResult.StrategyScore.StrategyUnitFit := 5;
      AResult.StrategyScore.TheoryFit := 4;
      AResult.StrategyScore.TrafficPotential := 8;
      AResult.StrategyScore.RiskLevel := 3;
      AResult.StrategyScore.ResearchValue := 3;
    end;
    aostsTheory:
    begin
      AResult.BasicScore := TAOSBasicScore.Make(4, 5, 5, 6);
      AResult.StrategyScore.StrategyUnitFit := 7;
      AResult.StrategyScore.TheoryFit := 9;
      AResult.StrategyScore.TrafficPotential := 4;
      AResult.StrategyScore.RiskLevel := 2;
      AResult.StrategyScore.ResearchValue := 8;
    end;
    aostsAnomaly:
    begin
      AResult.BasicScore := TAOSBasicScore.Make(5, 6, 5, 3);
      AResult.StrategyScore.StrategyUnitFit := 5;
      AResult.StrategyScore.TheoryFit := 6;
      AResult.StrategyScore.TrafficPotential := 6;
      AResult.StrategyScore.RiskLevel := 4;
      AResult.StrategyScore.ResearchValue := 9;
    end;
    aostsViralHit:
    begin
      AResult.BasicScore := TAOSBasicScore.Make(8, 7, 8, 9);
      AResult.StrategyScore.StrategyUnitFit := 6;
      AResult.StrategyScore.TheoryFit := 4;
      AResult.StrategyScore.TrafficPotential := 9;
      AResult.StrategyScore.RiskLevel := 3;
      AResult.StrategyScore.ResearchValue := 3;
    end;
    aostsEvergreen:
    begin
      AResult.BasicScore := TAOSBasicScore.Make(6, 8, 5, 7);
      AResult.StrategyScore.StrategyUnitFit := 6;
      AResult.StrategyScore.TheoryFit := 5;
      AResult.StrategyScore.TrafficPotential := 5;
      AResult.StrategyScore.RiskLevel := 1;
      AResult.StrategyScore.ResearchValue := 5;
    end;
    aostsFalsification:
    begin
      AResult.BasicScore := TAOSBasicScore.Make(3, 4, 4, 8);
      AResult.StrategyScore.StrategyUnitFit := 5;
      AResult.StrategyScore.TheoryFit := 8;
      AResult.StrategyScore.TrafficPotential := 3;
      AResult.StrategyScore.RiskLevel := 5;
      AResult.StrategyScore.ResearchValue := 10;
    end;
  else
    // aostsMaterial or unknown
    AResult.BasicScore := TAOSBasicScore.Make(4, 4, 4, 4);
    AResult.StrategyScore.StrategyUnitFit := 5;
    AResult.StrategyScore.TheoryFit := 4;
    AResult.StrategyScore.TrafficPotential := 4;
    AResult.StrategyScore.RiskLevel := 2;
    AResult.StrategyScore.ResearchValue := 4;
  end;

  // Fill remaining strategy dimensions with neutral defaults
  AResult.StrategyScore.TheoryInterventionLevel := 5;
  AResult.StrategyScore.TheoryLevel := 5;
  AResult.StrategyScore.Readability := 6;
  AResult.StrategyScore.OperationGoalFit := 5;
  AResult.StrategyScore.ClaimPotential := 5;

  AResult.DecisionReason := 'Rule-based fallback (no LLM available)';
  AResult.Confidence := 'low';
end;

{ Persist score to database }

class procedure TAOSTopicFunnelEngine.PersistScore(
  const AResult: TAOSTopicFunnelResult;
  const AStrategyUnitId: string);
var
  Q: TFDQuery;
begin
  if AResult.SignalId = '' then Exit;

  try
    ArtifactOS_DB.Connect;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := ArtifactOS_DB.Connection;
        Q.SQL.Text :=
          'INSERT INTO artifactos.topic_score (' +
          '  signal_id, strategy_unit_id, ' +
          '  coverage_score, pain_score, spread_score, verified_score, basic_composite, ' +
          '  strategy_fit, theory_fit, theory_intervention, traffic_potential, ' +
          '  theory_level, readability, risk_level, operation_goal_fit, ' +
          '  claim_potential, research_value, strategy_composite, ' +
          '  boundary_decision, decision_reason, confidence, scored_at' +
          ') VALUES (' +
          '  :sig_id::uuid, :su_id, ' +
          '  :cov, :pain, :sprd, :verf, :basic, ' +
          '  :sfit, :tfit, :tint, :traf, ' +
          '  :tlvl, :read, :risk, :ogfit, ' +
          '  :clmp, :resv, :strat, ' +
          '  :dec, :reason, :conf, now()' +
          ')';
        Q.ParamByName('sig_id').AsString := AResult.SignalId;
        Q.ParamByName('su_id').AsString := AStrategyUnitId;

        Q.ParamByName('cov').AsFloat := AResult.BasicScore.Coverage;
        Q.ParamByName('pain').AsFloat := AResult.BasicScore.PainPoint;
        Q.ParamByName('sprd').AsFloat := AResult.BasicScore.Spread;
        Q.ParamByName('verf').AsFloat := AResult.BasicScore.Verified;
        Q.ParamByName('basic').AsFloat := AResult.BasicComposite;

        Q.ParamByName('sfit').AsFloat := AResult.StrategyScore.StrategyUnitFit;
        Q.ParamByName('tfit').AsFloat := AResult.StrategyScore.TheoryFit;
        Q.ParamByName('tint').AsFloat := AResult.StrategyScore.TheoryInterventionLevel;
        Q.ParamByName('traf').AsFloat := AResult.StrategyScore.TrafficPotential;
        Q.ParamByName('tlvl').AsFloat := AResult.StrategyScore.TheoryLevel;
        Q.ParamByName('read').AsFloat := AResult.StrategyScore.Readability;
        Q.ParamByName('risk').AsFloat := AResult.StrategyScore.RiskLevel;
        Q.ParamByName('ogfit').AsFloat := AResult.StrategyScore.OperationGoalFit;
        Q.ParamByName('clmp').AsFloat := AResult.StrategyScore.ClaimPotential;
        Q.ParamByName('resv').AsFloat := AResult.StrategyScore.ResearchValue;
        Q.ParamByName('strat').AsFloat := AResult.StrategyComposite;

        Q.ParamByName('dec').AsString := DecisionName(AResult.Decision);
        Q.ParamByName('reason').AsString := AResult.DecisionReason;
        Q.ParamByName('conf').AsString := AResult.Confidence;

        Q.ExecSQL;
      finally
        Q.Free;
      end;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    // DB unavailable — scores computed but not persisted
  end;
end;

{ Single-pass chain: Scored signal → RSC → CTF → ContractCandidate }

class function TAOSTopicFunnelEngine.RunSinglePassChain(
  const ASignalId: string;
  out AContractId: string;
  out AChainJson: string): Boolean;
var
  FunnelResult: TAOSTopicFunnelResult;
  Q: TFDQuery;
  SignalTitle, SignalSource, SignalTypeStr: string;
  EntryMode: string;
  RfId, SpecId, CandidateId: string;
begin
  Result := False;
  AContractId := '';
  AChainJson := '';

  // Step 1: Score the signal
  if not ScoreSignal(ASignalId, FunnelResult) then
    Exit;

  // Only proceed if boundary decision is write_now, experiment, or draft_only
  if not (FunnelResult.Decision in [aobdWriteNow, aobdExperiment, aobdDraftOnly]) then
    Exit;

  // Step 2: Fetch signal metadata for the chain
  SignalTitle := '';
  SignalSource := '';
  SignalTypeStr := '';
  try
    ArtifactOS_DB.Connect;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := ArtifactOS_DB.Connection;
        Q.SQL.Text :=
          'SELECT title, source, signal_type FROM artifactos.event_signal WHERE id = :id::uuid';
        Q.ParamByName('id').AsString := ASignalId;
        Q.Open;
        if not Q.Eof then
        begin
          SignalTitle := Q.FieldByName('title').AsString;
          SignalSource := Q.FieldByName('source').AsString;
          SignalTypeStr := Q.FieldByName('signal_type').AsString;
        end;
      finally
        Q.Free;
      end;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  except
    Exit;
  end;

  if SignalTitle = '' then Exit;

  // Determine entry mode from signal type
  if SignalTypeStr = 'trending' then EntryMode := 'hotspot_driven'
  else if SignalTypeStr = 'theory' then EntryMode := 'theory_driven'
  else if SignalTypeStr = 'anomaly' then EntryMode := 'anomaly_driven'
  else if SignalTypeStr = 'viral_hit' then EntryMode := 'viral_deconstruction'
  else if SignalTypeStr = 'falsification' then EntryMode := 'research_driven'
  else EntryMode := 'manual';

  // Step 3: RSC — RequirementFrame
  RfId := TContractPipelineService.CreateRequirementFrame(
    SignalTitle,
    Format('Auto-generated from signal [%s]: %s', [SignalTypeStr, SignalTitle]),
    '{"status":"candidate","value":"auto"}',
    '{"status":"candidate","value":"auto"}',
    EntryMode,
    FunnelResult.Confidence,
    'Auto-detected from funnel scoring',
    Format('Score %.1f/10 composite, confidence %s', [FunnelResult.BasicComposite, FunnelResult.Confidence]),
    Format('["%s","funnel_auto"]', [SignalTitle]),
    '[]',
    '[]',
    Format('{"signal_id":"%s","basic_composite":%.2f,"strategy_composite":%.2f,"decision":"%s","confidence":"%s"}',
      [ASignalId, FunnelResult.BasicComposite, FunnelResult.StrategyComposite,
       DecisionName(FunnelResult.Decision), FunnelResult.Confidence]));

  if RfId = '' then Exit;

  // Step 4: CTF — ContentSpecSnapshot
  var NowStr := FormatDateTime('yyyymmddhhnnss', Now);
  SpecId := TContractPipelineService.CreateContentSpecSnapshot(
    RfId,
    'provisional',
    FunnelResult.BasicComposite / 10.0,  // normalize to 0-1
    Format('[{"bundle_id":"bnd_%s","label":"%s","evidence_status":"partial","review_status":"pending"}]',
      [NowStr, SignalTitle]),
    Format('sha256:funnel_%s_%s', [ASignalId, NowStr]),
    Format('["sig_%s:sha256:auto"]', [ASignalId]),
    Format('{"source":"topic_funnel_single_pass","signal_type":"%s"}', [SignalTypeStr]));

  if SpecId = '' then Exit;

  // Step 5: ContractCandidate
  CandidateId := TContractPipelineService.CreateContractCandidate(
    SpecId,
    Format('["%s"]', [SignalTitle]),
    '[]',
    '[500,2000]',
    'auto_funnel_draft',
    Format('{"action":"%s","autonomy_level":"AL2","max_rewrite":1,"publish_policy":"store_draft","confidence":"%s"}',
      [DecisionName(FunnelResult.Decision), FunnelResult.Confidence]),
    Format('{"funnel_single_pass":true,"signal_id":"%s"}', [ASignalId]));

  if CandidateId = '' then Exit;

  // Build chain result
  AChainJson := Format(
    '{"rf_id":"%s","spec_id":"%s","candidate_id":"%s","signal_id":"%s","decision":"%s","basic_score":%.2f,"strategy_score":%.2f}',
    [RfId, SpecId, CandidateId, ASignalId,
     DecisionName(FunnelResult.Decision),
     FunnelResult.BasicComposite, FunnelResult.StrategyComposite]);

  // The chain stops at ContractCandidate — ArtifactContract requires human review
  AContractId := CandidateId;
  Result := True;
end;

end.
