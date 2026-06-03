unit ArtifactOS.Services.ContractPipeline;

{ P6-47: RSC/CTF/Contract Delphi service skeleton.
  Provides the minimum Delphi-side contract pipeline:
    RequirementFrame -> ContentSpecSnapshot -> ContractCandidate -> ArtifactContract
  Python only for testing/diagnostics, not as formal runtime. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection;

type
  TRequirementFrameInfo = record
    Id: string;
    Topic: string;
    Intent: string;
    RscStatus: string;
    ReviewStatus: string;
    Confidence: string;
    CreatedAt: string;
  end;

  TContentSpecSnapshotInfo = record
    Id: string;
    RequirementFrameId: string;
    SnapshotStatus: string;
    AcceptLevel: string;
    EvidenceCoverage: Double;
    StaleStatus: string;
    CreatedAt: string;
  end;

  TContractCandidateInfo = record
    Id: string;
    SourceSpecSnapshotId: string;
    Status: string;
    SuggestedWordCount: string;  // JSON array
    SuggestedStyle: string;
    CreatedAt: string;
  end;

  TArtifactContractInfo = record
    Id: string;
    ContractCode: string;
    ContractType: string;
    Maturity: string;
    VersionNo: Integer;
    Status: string;
    CreatedAt: string;
  end;

  TContractPipelineService = class
  public
    // Create
    class function CreateRequirementFrame(
      const ATopic, AIntent: string;
      const ATargetAccountJson, ATargetPlatformJson: string;
      const AEntryMode: string;
      const ATheoryInterventionLevel: string;
      const ATargetReader: string;
      const ASuccessResult: string;
      const AInScopeJson: string;
      const ANonGoalsJson: string;
      const AUnresolvedJson: string;
      const APayloadJson: string
    ): string;

    class function CreateContentSpecSnapshot(
      const ARequirementFrameId: string;
      const AAcceptLevel: string;
      const AEvidenceCoverage: Double;
      const ASemanticBundlesJson: string;
      const AContentHash: string;
      const ASourceHashesJson: string;
      const APayloadJson: string
    ): string;

    class function CreateContractCandidate(
      const ASourceSpecSnapshotId: string;
      const ASuggestedMustLandJson: string;
      const ASuggestedTaboosJson: string;
      const ASuggestedWordCountJson: string;
      const ASuggestedStyle: string;
      const AStrategyRecommendationJson: string;
      const APayloadJson: string
    ): string;

    class function CreateArtifactContract(
      const AContractCode: string;
      const AContractType: string;
      const AMaturity: string;
      const AVersionNo: Integer;
      const AStatus: string;
      const ARequirementFrameId: string;
      const ASourceSpecSnapshotId: string;
      const AContractCandidateId: string;
      const ASourceJson: string;
      const AStrategyJson: string;
      const ADirectiveJson: string;
      const AStructureJson: string;
      const AConstraintsJson: string;
      const AQualityJson: string;
      const AAstoJson: string;
      const AOddJson: string;
      const APayloadJson: string
    ): string;

    // Read
    class function GetRequirementFrame(const AId: string): TRequirementFrameInfo;
    class function GetContentSpecSnapshot(const AId: string): TContentSpecSnapshotInfo;
    class function GetContractCandidate(const AId: string): TContractCandidateInfo;
    class function GetArtifactContract(const AId: string): TArtifactContractInfo;

    class function GetLatestSnapshotForFrame(const ARequirementFrameId: string): TContentSpecSnapshotInfo;
    class function GetLatestCandidateForSnapshot(const ASnapshotId: string): TContractCandidateInfo;
    class function GetLatestContractForCandidate(const ACandidateId: string): TArtifactContractInfo;

    // Link task to contract chain & validate
    class function LinkTaskToContract(
      const ATaskId: string;
      const ARequirementFrameId: string;
      const ASpecSnapshotId: string;
      const AContractCandidateId: string;
      const AArtifactContractId: string
    ): Boolean;

    class function ValidateContractChain(
      const AContractId: string
    ): Boolean;  // returns True if chain is traceable

    // Status transitions
    class function AdvanceRequirementFrame(const AId: string; const ANewRscStatus: string): Boolean;
    class function AdvanceContractCandidate(const AId: string; const ANewStatus: string): Boolean;
    class function ActivateContract(const AId: string): Boolean;
    class function CompleteContract(const AId: string): Boolean;

    // Full pipeline
    class function RunMinimalContractPipeline(
      const ATopic, AIntent: string;
      const ATargetPlatform, ATargetAccount: string;
      const AEntryMode: string;
      var AContractId: string;
      var AChain: string  // JSON: {rf_id, spec_id, candidate_id, contract_id}
    ): Boolean;
  end;

implementation

uses
  System.JSON;

function JsonStr(const S: string): string;
begin
  Result := S.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n');
end;

function JsonParam(const AName, AValue: string): string;
begin
  Result := '"' + AName + '":"' + JsonStr(AValue) + '"';
end;

function JsonObj(const AFields: array of string): string;
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

// ── Create ──

class function TContractPipelineService.CreateRequirementFrame(
  const ATopic, AIntent: string;
  const ATargetAccountJson, ATargetPlatformJson: string;
  const AEntryMode: string;
  const ATheoryInterventionLevel: string;
  const ATargetReader: string;
  const ASuccessResult: string;
  const AInScopeJson: string;
  const ANonGoalsJson: string;
  const AUnresolvedJson: string;
  const APayloadJson: string
): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnIdJson(
      'INSERT INTO artifactos.requirement_frame (' +
      '  topic, intent, target_account, target_platform, entry_mode,' +
      '  theory_intervention_level, target_reader, success_result,' +
      '  in_scope, non_goals, unresolved, rsc_status, review_status, payload' +
      ') VALUES (' +
      '  :topic, :intent, :target_account::jsonb, :target_platform::jsonb, :entry_mode,' +
      '  :theory_level, :target_reader, :success_result,' +
      '  :in_scope::jsonb, :non_goals::jsonb, :unresolved::jsonb, ''ready_for_ctf'', ''accepted'', :payload::jsonb' +
      ') RETURNING id::text',
      JsonObj([
        JsonParam('topic', ATopic),
        JsonParam('intent', AIntent),
        '"target_account":' + ATargetAccountJson,
        '"target_platform":' + ATargetPlatformJson,
        JsonParam('entry_mode', AEntryMode),
        JsonParam('theory_level', ATheoryInterventionLevel),
        JsonParam('target_reader', ATargetReader),
        JsonParam('success_result', ASuccessResult),
        '"in_scope":' + AInScopeJson,
        '"non_goals":' + ANonGoalsJson,
        '"unresolved":' + AUnresolvedJson,
        '"payload":' + APayloadJson
      ]));
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.CreateContentSpecSnapshot(
  const ARequirementFrameId: string;
  const AAcceptLevel: string;
  const AEvidenceCoverage: Double;
  const ASemanticBundlesJson: string;
  const AContentHash: string;
  const ASourceHashesJson: string;
  const APayloadJson: string
): string;
var
  DB: TArtifactDB;
  CoverageStr: string;
begin
  CoverageStr := FormatFloat('0.000', AEvidenceCoverage);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnIdJson(
      'INSERT INTO artifactos.content_spec_snapshot (' +
      '  requirement_frame_id, gen_status, review_status, snapshot_status,' +
      '  semantic_bundles, content_hash, source_hashes, accept_level,' +
      '  evidence_coverage, stale_status, payload' +
      ') VALUES (' +
      '  :rf_id::uuid, ''generated'', ''accepted'', ''frozen'',' +
      '  :bundles::jsonb, :content_hash, :source_hashes::jsonb, :accept_level,' +
      '  :coverage, ''fresh'', :payload::jsonb' +
      ') RETURNING id::text',
      JsonObj([
        JsonParam('rf_id', ARequirementFrameId),
        '"bundles":' + ASemanticBundlesJson,
        JsonParam('content_hash', AContentHash),
        '"source_hashes":' + ASourceHashesJson,
        JsonParam('accept_level', AAcceptLevel),
        JsonParam('coverage', CoverageStr),
        '"payload":' + APayloadJson
      ]));
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.CreateContractCandidate(
  const ASourceSpecSnapshotId: string;
  const ASuggestedMustLandJson: string;
  const ASuggestedTaboosJson: string;
  const ASuggestedWordCountJson: string;
  const ASuggestedStyle: string;
  const AStrategyRecommendationJson: string;
  const APayloadJson: string
): string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnIdJson(
      'INSERT INTO artifactos.contract_candidate (' +
      '  source_spec_snapshot_id, status, suggested_must_land,' +
      '  suggested_taboos, suggested_word_count, suggested_style,' +
      '  strategy_recommendation, payload' +
      ') VALUES (' +
      '  :spec_id::uuid, ''ready'', :must_land::jsonb,' +
      '  :taboos::jsonb, :word_count::jsonb, :style,' +
      '  :strategy::jsonb, :payload::jsonb' +
      ') RETURNING id::text',
      JsonObj([
        JsonParam('spec_id', ASourceSpecSnapshotId),
        '"must_land":' + ASuggestedMustLandJson,
        '"taboos":' + ASuggestedTaboosJson,
        '"word_count":' + ASuggestedWordCountJson,
        JsonParam('style', ASuggestedStyle),
        '"strategy":' + AStrategyRecommendationJson,
        '"payload":' + APayloadJson
      ]));
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.CreateArtifactContract(
  const AContractCode: string;
  const AContractType: string;
  const AMaturity: string;
  const AVersionNo: Integer;
  const AStatus: string;
  const ARequirementFrameId: string;
  const ASourceSpecSnapshotId: string;
  const AContractCandidateId: string;
  const ASourceJson: string;
  const AStrategyJson: string;
  const ADirectiveJson: string;
  const AStructureJson: string;
  const AConstraintsJson: string;
  const AQualityJson: string;
  const AAstoJson: string;
  const AOddJson: string;
  const APayloadJson: string
): string;
var
  DB: TArtifactDB;
  VersionStr: string;
begin
  VersionStr := IntToStr(AVersionNo);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.InsertAndReturnIdJson(
      'INSERT INTO artifactos.artifact_contract (' +
      '  contract_code, contract_type, maturity, version_no, status,' +
      '  requirement_frame_id, source_spec_snapshot_id, contract_candidate_id,' +
      '  source, strategy, directive, structure, constraints_json, quality, asto, odd, payload' +
      ') VALUES (' +
      '  :code, :contract_type, :maturity, :version::int, :status,' +
      '  :rf_id::uuid, :spec_id::uuid, :candidate_id::uuid,' +
      '  :source::jsonb, :strategy::jsonb, :directive::jsonb, :structure::jsonb,' +
      '  :constraints::jsonb, :quality::jsonb, :asto::jsonb, :odd::jsonb, :payload::jsonb' +
      ') RETURNING id::text',
      JsonObj([
        JsonParam('code', AContractCode),
        JsonParam('contract_type', AContractType),
        JsonParam('maturity', AMaturity),
        JsonParam('version', VersionStr),
        JsonParam('status', AStatus),
        JsonParam('rf_id', ARequirementFrameId),
        JsonParam('spec_id', ASourceSpecSnapshotId),
        JsonParam('candidate_id', AContractCandidateId),
        '"source":' + ASourceJson,
        '"strategy":' + AStrategyJson,
        '"directive":' + ADirectiveJson,
        '"structure":' + AStructureJson,
        '"constraints":' + AConstraintsJson,
        '"quality":' + AQualityJson,
        '"asto":' + AAstoJson,
        '"odd":' + AOddJson,
        '"payload":' + APayloadJson
      ]));
  finally
    DB.Disconnect;
  end;
end;

// ── Read ──

class function TContractPipelineService.GetRequirementFrame(const AId: string): TRequirementFrameInfo;
var
  DB: TArtifactDB;
  Json: string;
  J: TJSONObject;
begin
  FillChar(Result, SizeOf(Result), 0);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Json := DB.ExecuteScalarJson(
      'SELECT row_to_json(r)::text FROM (SELECT id::text, topic, intent, rsc_status, review_status, confidence, created_at::text FROM artifactos.requirement_frame WHERE id=:id::uuid) r',
      '{"id":"' + AId + '"}');
    if Json = '' then Exit;
    J := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    if J = nil then Exit;
    try
      Result.Id := J.GetValue<string>('id', '');
      Result.Topic := J.GetValue<string>('topic', '');
      Result.Intent := J.GetValue<string>('intent', '');
      Result.RscStatus := J.GetValue<string>('rsc_status', '');
      Result.ReviewStatus := J.GetValue<string>('review_status', '');
      Result.Confidence := J.GetValue<string>('confidence', '');
      Result.CreatedAt := J.GetValue<string>('created_at', '');
    finally
      J.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.GetContentSpecSnapshot(const AId: string): TContentSpecSnapshotInfo;
var
  DB: TArtifactDB;
  Json: string;
  J: TJSONObject;
begin
  FillChar(Result, SizeOf(Result), 0);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Json := DB.ExecuteScalarJson(
      'SELECT row_to_json(r)::text FROM (SELECT id::text, requirement_frame_id::text, snapshot_status, accept_level, evidence_coverage, stale_status, created_at::text FROM artifactos.content_spec_snapshot WHERE id=:id::uuid) r',
      '{"id":"' + AId + '"}');
    if Json = '' then Exit;
    J := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    if J = nil then Exit;
    try
      Result.Id := J.GetValue<string>('id', '');
      Result.RequirementFrameId := J.GetValue<string>('requirement_frame_id', '');
      Result.SnapshotStatus := J.GetValue<string>('snapshot_status', '');
      Result.AcceptLevel := J.GetValue<string>('accept_level', '');
      Result.EvidenceCoverage := J.GetValue<Double>('evidence_coverage', 0);
      Result.StaleStatus := J.GetValue<string>('stale_status', '');
      Result.CreatedAt := J.GetValue<string>('created_at', '');
    finally
      J.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.GetContractCandidate(const AId: string): TContractCandidateInfo;
var
  DB: TArtifactDB;
  Json: string;
  J: TJSONObject;
begin
  FillChar(Result, SizeOf(Result), 0);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Json := DB.ExecuteScalarJson(
      'SELECT row_to_json(r)::text FROM (SELECT id::text, source_spec_snapshot_id::text, status, suggested_word_count::text, suggested_style, created_at::text FROM artifactos.contract_candidate WHERE id=:id::uuid) r',
      '{"id":"' + AId + '"}');
    if Json = '' then Exit;
    J := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    if J = nil then Exit;
    try
      Result.Id := J.GetValue<string>('id', '');
      Result.SourceSpecSnapshotId := J.GetValue<string>('source_spec_snapshot_id', '');
      Result.Status := J.GetValue<string>('status', '');
      Result.SuggestedWordCount := J.GetValue<string>('suggested_word_count', '');
      Result.SuggestedStyle := J.GetValue<string>('suggested_style', '');
      Result.CreatedAt := J.GetValue<string>('created_at', '');
    finally
      J.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.GetArtifactContract(const AId: string): TArtifactContractInfo;
var
  DB: TArtifactDB;
  Json: string;
  J: TJSONObject;
begin
  FillChar(Result, SizeOf(Result), 0);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Json := DB.ExecuteScalarJson(
      'SELECT row_to_json(r)::text FROM (SELECT id::text, contract_code, contract_type, maturity, version_no, status, created_at::text FROM artifactos.artifact_contract WHERE id=:id::uuid) r',
      '{"id":"' + AId + '"}');
    if Json = '' then Exit;
    J := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    if J = nil then Exit;
    try
      Result.Id := J.GetValue<string>('id', '');
      Result.ContractCode := J.GetValue<string>('contract_code', '');
      Result.ContractType := J.GetValue<string>('contract_type', '');
      Result.Maturity := J.GetValue<string>('maturity', '');
      Result.VersionNo := J.GetValue<Integer>('version_no', 0);
      Result.Status := J.GetValue<string>('status', '');
      Result.CreatedAt := J.GetValue<string>('created_at', '');
    finally
      J.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.GetLatestSnapshotForFrame(const ARequirementFrameId: string): TContentSpecSnapshotInfo;
var
  DB: TArtifactDB;
  Id: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Id := DB.ExecuteScalarJson(
      'SELECT id::text FROM artifactos.content_spec_snapshot WHERE requirement_frame_id=:rf_id::uuid ORDER BY created_at DESC LIMIT 1',
      '{"rf_id":"' + ARequirementFrameId + '"}');
    if Id = '' then Exit;
    Result := GetContentSpecSnapshot(Id);
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.GetLatestCandidateForSnapshot(const ASnapshotId: string): TContractCandidateInfo;
var
  DB: TArtifactDB;
  Id: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Id := DB.ExecuteScalarJson(
      'SELECT id::text FROM artifactos.contract_candidate WHERE source_spec_snapshot_id=:spec_id::uuid ORDER BY created_at DESC LIMIT 1',
      '{"spec_id":"' + ASnapshotId + '"}');
    if Id = '' then Exit;
    Result := GetContractCandidate(Id);
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.GetLatestContractForCandidate(const ACandidateId: string): TArtifactContractInfo;
var
  DB: TArtifactDB;
  Id: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Id := DB.ExecuteScalarJson(
      'SELECT id::text FROM artifactos.artifact_contract WHERE contract_candidate_id=:candidate_id::uuid ORDER BY created_at DESC LIMIT 1',
      '{"candidate_id":"' + ACandidateId + '"}');
    if Id = '' then Exit;
    Result := GetArtifactContract(Id);
  finally
    DB.Disconnect;
  end;
end;

// ── Link Task to Contract ──

class function TContractPipelineService.LinkTaskToContract(
  const ATaskId: string;
  const ARequirementFrameId: string;
  const ASpecSnapshotId: string;
  const AContractCandidateId: string;
  const AArtifactContractId: string
): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.substudio_execution_task SET ' +
      '  requirement_frame_id=:rf_id::uuid,' +
      '  spec_snapshot_id=:spec_id::uuid,' +
      '  contract_candidate_id=:candidate_id::uuid,' +
      '  artifact_contract_id=:contract_id::uuid,' +
      '  contract_id=:contract_id::uuid,' +
      '  spec_status=''contracted''' +
      ' WHERE id=:task_id::uuid',
      JsonObj([
        JsonParam('rf_id', ARequirementFrameId),
        JsonParam('spec_id', ASpecSnapshotId),
        JsonParam('candidate_id', AContractCandidateId),
        JsonParam('contract_id', AArtifactContractId),
        JsonParam('task_id', ATaskId)
      ]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.ValidateContractChain(
  const AContractId: string
): Boolean;
var
  DB: TArtifactDB;
  Count: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Check that the contract has a complete traceable chain:
    //   requirement_frame -> content_spec_snapshot -> contract_candidate -> artifact_contract
    Count := DB.ExecuteScalarJson(
      'SELECT COUNT(*)::text FROM artifactos.artifact_contract ac ' +
      'JOIN artifactos.contract_candidate cc ON ac.contract_candidate_id = cc.id ' +
      'JOIN artifactos.content_spec_snapshot css ON ac.source_spec_snapshot_id = css.id ' +
      'JOIN artifactos.requirement_frame rf ON ac.requirement_frame_id = rf.id ' +
      'WHERE ac.id=:id::uuid',
      '{"id":"' + AContractId + '"}');
    Result := Count <> '0';
  finally
    DB.Disconnect;
  end;
end;

// ── Status Transitions ──

class function TContractPipelineService.AdvanceRequirementFrame(const AId: string; const ANewRscStatus: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.requirement_frame SET rsc_status=:status, updated_at=now() WHERE id=:id::uuid',
      JsonObj([JsonParam('status', ANewRscStatus), JsonParam('id', AId)]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.AdvanceContractCandidate(const AId: string; const ANewStatus: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.contract_candidate SET status=:status, updated_at=now() WHERE id=:id::uuid',
      JsonObj([JsonParam('status', ANewStatus), JsonParam('id', AId)]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.ActivateContract(const AId: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.artifact_contract SET status=''active'', updated_at=now() WHERE id=:id::uuid AND status IN (''draft'',''agreed'',''approved'')',
      JsonObj([JsonParam('id', AId)]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

class function TContractPipelineService.CompleteContract(const AId: string): Boolean;
var
  DB: TArtifactDB;
begin
  Result := False;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.ExecuteJson(
      'UPDATE artifactos.artifact_contract SET status=''completed'', updated_at=now() WHERE id=:id::uuid AND status IN (''active'',''executing'')',
      JsonObj([JsonParam('id', AId)]));
    Result := True;
  finally
    DB.Disconnect;
  end;
end;

// ── Full Pipeline ──

class function TContractPipelineService.RunMinimalContractPipeline(
  const ATopic, AIntent: string;
  const ATargetPlatform, ATargetAccount: string;
  const AEntryMode: string;
  var AContractId: string;
  var AChain: string
): Boolean;
var
  RfId, SpecId, CandidateId, ContractCode: string;
  NowStr: string;
begin
  Result := False;
  NowStr := FormatDateTime('yyyymmddhhnnss', Now);

  // 1. RequirementFrame
  RfId := CreateRequirementFrame(
    ATopic, AIntent,
    Format('{"status":"confirmed","value":"%s"}', [ATargetAccount]),
    Format('{"status":"confirmed","value":"%s"}', [ATargetPlatform]),
    AEntryMode, 'medium', 'ArtifactOS developer',
    'Contract chain is fully traceable from raw idea to approved contract.',
    Format('["%s","contract pipeline","traceability"]', [ATopic]),
    '["real publishing","external network calls"]',
    '[]',
    Format('{"raw_idea":"%s","pipeline":"minimal contract chain"}', [ATopic]));

  if RfId = '' then Exit;

  // 2. ContentSpecSnapshot
  SpecId := CreateContentSpecSnapshot(
    RfId, 'release', 0.750,
    Format('[{"bundle_id":"bnd_%s","label":"%s","evidence_status":"sufficient","review_status":"accepted"}]', [NowStr, ATopic]),
    Format('sha256:minimal_%s', [NowStr]),
    Format('["rf:sha256:minimal_%s"]', [NowStr]),
    Format('{"snapshot":"minimal release spec for %s"}', [ATopic]));

  if SpecId = '' then Exit;

  // 3. ContractCandidate
  CandidateId := CreateContractCandidate(
    SpecId,
    '["Explain RSC","Explain CTF","Explain ArtifactContract"]',
    '["Do not publish","Do not call external services"]',
    '[800,1200]',
    'clear_engineering_note',
    '{"action":"write_now","autonomy_level":"AL2","max_rewrite":1,"publish_policy":"store_draft"}',
    Format('{"candidate":"minimal ready contract candidate for %s"}', [ATopic]));

  if CandidateId = '' then Exit;

  // 4. ArtifactContract
  ContractCode := Format('ctr_minimal_%s', [NowStr]);
  AContractId := CreateArtifactContract(
    ContractCode, 'full_contract', 'agreed', 1, 'approved',
    RfId, SpecId, CandidateId,
    Format('{"requirement_frame_id":"%s","source_spec_snapshot_id":"%s","contract_candidate_id":"%s","contract_candidate_status":"ready","accept_level":"release","evidence_coverage":0.75,"stale_status":"fresh"}', [RfId, SpecId, CandidateId]),
    Format('{"autonomy_level":"AL2","generation_mode":"delegate","entry_mode":"%s","max_rewrite":1,"on_pass":"store_draft"}', [AEntryMode]),
    Format('{"topic":"%s","target_platform":"%s","target_account":"%s"}', [ATopic, ATargetPlatform, ATargetAccount]),
    '{"must_land":["RSC","CTF","ArtifactContract"],"suggested_structure":"problem -> chain -> verification"}',
    '{"word_count":{"min":800,"max":1200}}',
    '{"acceptance_criteria":["contract chain is traceable"]}',
    '{"state":"draft","actor":"system"}',
    '{"validation_gates":["schema_check"],"seal_required_before_publish":true}',
    Format('{"contract":"minimal approved contract for %s"}', [ATopic]));

  if AContractId = '' then Exit;

  // Build chain JSON
  AChain := Format('{"rf_id":"%s","spec_id":"%s","candidate_id":"%s","contract_id":"%s"}',
    [RfId, SpecId, CandidateId, AContractId]);

  Result := True;
end;

end.