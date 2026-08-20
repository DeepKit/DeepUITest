unit ArtifactOS.Services.PromptAssembly;

{ P6-48: Prompt Assembly v0.
  Context assembly engine with 10 slots (S00-S09), pipeline mode resolution,
  selective slot injection, and 3-tier cache ordering.

  Design source: docs/11.[流程]-写作流水线-Writing-Pipeline.md §3.1 }

interface

uses
  System.SysUtils, System.Generics.Collections,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.TheoryWeave;

type
  // Pipeline mode: determines which slots to inject
  TPipelineMode = (
    pmFast,
    pmStandard,
    pmHeavy
  );

  // Slot tier for cache ordering
  TSlotTier = (
    stSteadyState,   // Layer 1: monthly cache, highest hit rate
    stStrategy,      // Layer 2: daily/weekly cache
    stTask           // Layer 3: per-invocation, no cache
  );

  // ODD tracking records
  TOddRecord = record
    Actor: string;
    ActorClassification: string;    // human / ai / system
    BoundaryCondition: string;      // JSON
    BoundaryVersion: string;
    EvidenceRef: string;
  end;

  // ASTO tracking record
  TAstoRecord = record
    State: string;
    ConditionDescription: string;
    Timestamp: string;
  end;

  // A single context slot
  TPromptSlot = record
    SlotId: string;          // S00-S09
    DisplayLabel: string;
    Content: string;         // The injected text content
    ContentJson: string;     // Full source JSON for diagnostics
    Tier: TSlotTier;
    IsMandatory: Boolean;
    IsInjected: Boolean;
    InjectionMode: string;   // 'full','summary','skip','boundary_only','rework_only','theory_stance'
    SourceVersion: string;
    SourceFrozenAt: string;
  end;

  TPromptSlotList = TArray<TPromptSlot>;

  // Full assembly metadata
  TAssemblyMeta = record
    ContextPackId: string;
    PipelineMode: string;         // text form of TPipelineMode
    GenerationMode: string;       // 'co_edit','delegate','request_more','explore'
    TheoryInterventionLevel: string;
    IsRework: Boolean;
    ContractId: string;
    ContractVersion: Integer;
    FrozenVersions: string;       // JSON map
    CacheTierOrder: string;       // JSON description of tier layout
    SlotMap: string;              // JSON: which slots injected and why
    TokenEstimate: Integer;
    SlotCount: Integer;
    InjectedSlots: Integer;
    SkippedSlots: Integer;
    Asto: string;                 // JSON
    Odd: string;                  // JSON
  end;

  // Complete assembly result
  TAssemblyResult = record
    Success: Boolean;
    ErrorMessage: string;
    Meta: TAssemblyMeta;
    PromptText: string;           // The final assembled prompt
    Slots: TPromptSlotList;
  end;

  TPromptAssemblyService = class
  public
    // Pipeline mode resolution
    class function ResolvePipelineMode(
      const AContractType: string;
      const AMaturity: string;
      const ATheoryInterventionLevel: string;
      const AExplicitMode: string
    ): TPipelineMode;

    // Generation mode resolution
    class function ResolveGenerationMode(
      const AContractType: string;
      const ATargetPlatform: string;
      const AExplicitMode: string;
      const AWordCountMax: Integer
    ): string;

    // Context assembly (v0: source data from contract pipeline DB)
    class function AssembleContext(
      const AContractId: string;
      const APipelineMode: TPipelineMode;
      const AIsRework: Boolean;
      const AReworkContext: string;
      var AResult: TAssemblyResult
    ): Boolean;

    // Build final prompt from assembled slots
    class function BuildPrompt(
      const ASlots: TPromptSlotList;
      const AMode: TPipelineMode;
      const AIsRework: Boolean
    ): string;

    // Slot injection decision
    class function ShouldInjectSlot(
      const ASlotId: string;
      const AMode: TPipelineMode;
      const AIsRework: Boolean;
      const ATheoryInterventionLevel: string;
      var AInjectionMode: string
    ): Boolean;

    // Tier assignment
    class function SlotTier(const ASlotId: string): TSlotTier;

    // Serialization helpers
    class function PipelineModeToString(const AMode: TPipelineMode): string;
    class function TierToString(const ATier: TSlotTier): string;
    class function SlotsToJson(const ASlots: TPromptSlotList): string;
    class function MetaToJson(const AMeta: TAssemblyMeta): string;
    class function ResultToJson(const AResult: TAssemblyResult): string;
  end;

implementation

uses
  System.JSON,
  ArtifactOS.Core.Common.JsonBuilder;

// ── Helpers ──

function JsonParamInt(const AName: string; AValue: Integer): string;
begin
  Result := Format('"%s":%d', [AName, AValue]);
end;

// ── Pipeline Mode Resolution ──

class function TPromptAssemblyService.PipelineModeToString(const AMode: TPipelineMode): string;
begin
  case AMode of
    pmFast:     Result := 'fast';
    pmStandard: Result := 'standard';
    pmHeavy:    Result := 'heavy';
  else
    Result := 'standard';
  end;
end;

class function TPromptAssemblyService.TierToString(const ATier: TSlotTier): string;
begin
  case ATier of
    stSteadyState: Result := 'steady_state';
    stStrategy:    Result := 'strategy';
    stTask:        Result := 'task';
  else
    Result := 'task';
  end;
end;

class function TPromptAssemblyService.ResolvePipelineMode(
  const AContractType: string;
  const AMaturity: string;
  const ATheoryInterventionLevel: string;
  const AExplicitMode: string
): TPipelineMode;
begin
  // Explicit mode takes precedence
  if SameText(AExplicitMode, 'fast') then Exit(pmFast);
  if SameText(AExplicitMode, 'heavy') then Exit(pmHeavy);
  if SameText(AExplicitMode, 'standard') then Exit(pmStandard);

  // Heavy: high theory intervention, high maturity
  if (SameText(ATheoryInterventionLevel, 'high')) or
     (SameText(AMaturity, 'production')) or
     (SameText(AMaturity, 'verified')) then
    Exit(pmHeavy);

  // Fast: seed_contract, explore mode, or low maturity
  if (SameText(AContractType, 'seed_contract')) or
     (SameText(AMaturity, 'seed')) or
     (SameText(AMaturity, 'draft')) then
    Exit(pmFast);

  // Default: standard
  Result := pmStandard;
end;

class function TPromptAssemblyService.ResolveGenerationMode(
  const AContractType: string;
  const ATargetPlatform: string;
  const AExplicitMode: string;
  const AWordCountMax: Integer
): string;
begin
  // Explicit
  if AExplicitMode <> '' then Exit(AExplicitMode);

  // Seed → explore
  if SameText(AContractType, 'seed_contract') then Exit('explore');

  // Xiaohongshu → request_more
  if SameText(ATargetPlatform, 'xiaohongshu') then Exit('request_more');

  // Long narrative → co_edit
  if (AWordCountMax >= 2000) and SameText(ATargetPlatform, 'zhihu') then Exit('co_edit');

  // Default
  Result := 'delegate';
end;

// ── Slot Tier ──

class function TPromptAssemblyService.SlotTier(const ASlotId: string): TSlotTier;
begin
  // Layer 1 (steady-state): S05 platform rules
  if ASlotId = 'S05' then Exit(stSteadyState);

  // Layer 2 (strategy): S00 strategy unit, S08 source mapping, S02 account profile, S07 feedback
  if (ASlotId = 'S00') or (ASlotId = 'S08') or (ASlotId = 'S02') or (ASlotId = 'S07') then
    Exit(stStrategy);

  // Layer 3 (task): S01 contract, S03 materials, S04 viral templates, S06 rework, S09 cognition
  Result := stTask;
end;

// ── Slot Injection Decision ──

class function TPromptAssemblyService.ShouldInjectSlot(
  const ASlotId: string;
  const AMode: TPipelineMode;
  const AIsRework: Boolean;
  const ATheoryInterventionLevel: string;
  var AInjectionMode: string
): Boolean;
begin
  if ASlotId = 'S00' then // Strategy unit — always mandatory
  begin
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S01' then // Contract — always mandatory
  begin
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S02' then // Account profile — always mandatory
  begin
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S03' then // Reference materials
  begin
    if AMode = pmFast then
    begin
      AInjectionMode := 'summary';
      Exit(True); // fast: inject summary only
    end;
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S04' then // Viral templates
  begin
    if AMode = pmFast then
    begin
      AInjectionMode := 'skip';
      Exit(False);
    end;
    if AMode = pmHeavy then
    begin
      if SameText(ATheoryInterventionLevel, 'low') then
      begin
        AInjectionMode := 'full';
        Exit(True);
      end;
      AInjectionMode := 'skip';
      Exit(False);
    end;
    // standard: inject
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S05' then // Platform rules — always mandatory
  begin
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S06' then // Rework feedback
  begin
    if AIsRework then
    begin
      AInjectionMode := 'full';
      Exit(True);
    end;
    AInjectionMode := 'skip';
    Exit(False);
  end;

  if ASlotId = 'S07' then // Feedback knowledge (retained patterns)
  begin
    if AMode = pmFast then
    begin
      AInjectionMode := 'skip';
      Exit(False);
    end;
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S08' then // Source mapping
  begin
    if AMode = pmFast then
    begin
      AInjectionMode := 'boundary_only';
      Exit(True);
    end;
    if AMode = pmHeavy then
    begin
      AInjectionMode := 'theory_stance';
      Exit(True);
    end;
    AInjectionMode := 'full';
    Exit(True);
  end;

  if ASlotId = 'S09' then // Cognition trace
  begin
    if AMode = pmFast then
    begin
      AInjectionMode := 'skip';
      Exit(False);
    end;
    if AIsRework then
    begin
      AInjectionMode := 'full';
      Exit(True);
    end;
    // heavy: first round output alternative — inject as decision input
    if AMode = pmHeavy then
    begin
      AInjectionMode := 'first_round_alternative';
      Exit(True);
    end;
    AInjectionMode := 'skip';
    Exit(False);
  end;

  AInjectionMode := 'unknown_slot';
  Result := False;
end;

// ── Build Prompt ──

class function TPromptAssemblyService.BuildPrompt(
  const ASlots: TPromptSlotList;
  const AMode: TPipelineMode;
  const AIsRework: Boolean
): string;
var
  SB: TStringBuilder;
  I: Integer;
  TierLabel: string;
begin
  SB := TStringBuilder.Create;
  try
    // ── Tier 1: Steady-state prefix (cached monthly) ──
    SB.AppendLine('=== SYSTEM ROLE ===');
    SB.AppendLine('You are the ArtifactOS Writing Pipeline. You generate content according to a contract.');
    SB.AppendLine;

    for I := 0 to High(ASlots) do
      if (ASlots[I].IsInjected) and (ASlots[I].Tier = stSteadyState) then
      begin
        TierLabel := ASlots[I].DisplayLabel;
        SB.AppendLine(Format('=== %s (%s) ===', [TierLabel, ASlots[I].SlotId]));
        SB.AppendLine(ASlots[I].Content);
        SB.AppendLine;
      end;

    // ── Tier 2: Strategy prefix (cached daily/weekly) ──
    SB.AppendLine('=== STRATEGY CONTEXT ===');
    for I := 0 to High(ASlots) do
      if (ASlots[I].IsInjected) and (ASlots[I].Tier = stStrategy) then
      begin
        TierLabel := ASlots[I].DisplayLabel;
        SB.AppendLine(Format('--- %s (%s) ---', [TierLabel, ASlots[I].SlotId]));
        SB.AppendLine(ASlots[I].Content);
        SB.AppendLine;
      end;

    // ── Tier 3: Task suffix (per invocation, not cached) ──
    SB.AppendLine('=== TASK ===');
    for I := 0 to High(ASlots) do
      if (ASlots[I].IsInjected) and (ASlots[I].Tier = stTask) then
      begin
        TierLabel := ASlots[I].DisplayLabel;
        SB.AppendLine(Format('--- %s (%s) ---', [TierLabel, ASlots[I].SlotId]));
        SB.AppendLine(ASlots[I].Content);
        SB.AppendLine;
      end;

    if AIsRework then
      SB.AppendLine('Note: This is a REWORK cycle. Apply the rework feedback (S06) above.');

    SB.AppendLine('Generate the content now according to the contract above.');
    if AMode = pmHeavy then
      SB.AppendLine('Heavy mode: provide a decision JSON first, then the full draft.');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ── Slot labels ──

function SlotLabel(const ASlotId: string): string;
begin
  if ASlotId = 'S00' then Exit('Strategy Unit');
  if ASlotId = 'S01' then Exit('Contract');
  if ASlotId = 'S02' then Exit('Account Profile');
  if ASlotId = 'S03' then Exit('Reference Materials');
  if ASlotId = 'S04' then Exit('Viral Templates');
  if ASlotId = 'S05' then Exit('Platform Rules');
  if ASlotId = 'S06' then Exit('Rework Feedback');
  if ASlotId = 'S07' then Exit('Retained Patterns');
  if ASlotId = 'S08' then Exit('Source Mapping');
  if ASlotId = 'S09' then Exit('Cognition Trace');
  Result := 'Unknown Slot';
end;

// ── Estimate token count (rough: ~1.3 tokens per English char, ~0.5 per Chinese char) ──

function EstimateTokens(const AText: string): Integer;
var
  I: Integer;
  Ch: Char;
  Count: Double;
begin
  Count := 0;
  for I := 1 to Length(AText) do
  begin
    Ch := AText[I];
    if Word(Ch) > $007F then
      Count := Count + 0.5   // CJK / non-ASCII
    else
      Count := Count + 0.25; // ASCII
  end;
  Result := Round(Count);
end;

// ── Context Assembly ──

class function TPromptAssemblyService.AssembleContext(
  const AContractId: string;
  const APipelineMode: TPipelineMode;
  const AIsRework: Boolean;
  const AReworkContext: string;
  var AResult: TAssemblyResult
): Boolean;
var
  DB: TArtifactDB;
  ContractJson, RequirementJson, SnapshotJson: string;
  JContract, JRequirement, JSnapshot: TJSONObject;
  SlotIds: TArray<string>;
  SI: Integer;
  Slot: TPromptSlot;
  InjectionMode: string;
  TheoryLevel, ContractType, Maturity, TargetPlatform: string;
  GenerationMode, ContractCode: string;
begin
  FillChar(AResult, SizeOf(AResult), 0);
  AResult.Success := False;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // ═══ Fetch contract chain ═══
    ContractJson := DB.ExecuteScalarJson(
      'SELECT row_to_json(r)::text FROM (' +
      '  SELECT ac.id::text, ac.contract_code, ac.contract_type, ac.maturity, ac.version_no, ac.status,' +
      '    ac.source::text as source, ac.strategy::text as strategy, ac.directive::text as directive,' +
      '    ac.structure::text as structure, ac.constraints_json::text as constraints_json,' +
      '    ac.quality::text as quality, ac.asto::text as asto, ac.odd::text as odd,' +
      '    ac.requirement_frame_id::text, ac.source_spec_snapshot_id::text, ac.contract_candidate_id::text' +
      '  FROM artifactos.artifact_contract ac WHERE ac.id=:id::uuid' +
      ') r',
      '{"id":"' + AContractId + '"}}');

    if ContractJson = '' then
    begin
      AResult.ErrorMessage := Format('Contract not found: %s', [AContractId]);
      Result := False;
      Exit;
    end;

    JContract := TJSONObject.ParseJSONValue(ContractJson) as TJSONObject;
    if JContract = nil then
    begin
      AResult.ErrorMessage := 'Failed to parse contract JSON';
      Result := False;
      Exit;
    end;

    try
      ContractType := JContract.GetValue<string>('contract_type', 'full_contract');
      Maturity := JContract.GetValue<string>('maturity', 'draft');
      ContractCode := JContract.GetValue<string>('contract_code', '');

      // Fetch requirement frame for topic/intent/theory level
      RequirementJson := DB.ExecuteScalarJson(
        'SELECT row_to_json(r)::text FROM (' +
        '  SELECT topic, intent, target_platform::text, target_account::text,' +
        '    theory_intervention_level, entry_mode, rsc_status' +
        '  FROM artifactos.requirement_frame WHERE id=:rf_id::uuid' +
        ') r',
        '{"rf_id":"' + JContract.GetValue<string>('requirement_frame_id', '') + '"}}');

      TheoryLevel := 'medium';
      TargetPlatform := 'unknown';
      if RequirementJson <> '' then
      begin
        JRequirement := TJSONObject.ParseJSONValue(RequirementJson) as TJSONObject;
        if JRequirement <> nil then
        begin
          try
            TheoryLevel := JRequirement.GetValue<string>('theory_intervention_level', 'medium');
            TargetPlatform := JRequirement.GetValue<string>('target_platform', 'unknown');
          finally
            JRequirement.Free;
          end;
        end;
      end;

      // Resolve generation mode
      GenerationMode := ResolveGenerationMode(ContractType, TargetPlatform, '', 1200);

      // ═══ Build slot array ═══
      SlotIds := TArray<string>.Create('S00','S01','S02','S03','S04','S05','S06','S07','S08','S09');
      SetLength(AResult.Slots, Length(SlotIds));

      for SI := 0 to High(SlotIds) do
      begin
        FillChar(Slot, SizeOf(Slot), 0);
        Slot.SlotId := SlotIds[SI];
        Slot.DisplayLabel := SlotLabel(SlotIds[SI]);
        Slot.Tier := SlotTier(SlotIds[SI]);

        Slot.IsInjected := ShouldInjectSlot(SlotIds[SI], APipelineMode, AIsRework, TheoryLevel, InjectionMode);
        Slot.InjectionMode := InjectionMode;
        Slot.IsMandatory := (SlotIds[SI] = 'S00') or (SlotIds[SI] = 'S01') or
                            (SlotIds[SI] = 'S02') or (SlotIds[SI] = 'S05');

        // ═══ Fill slot content from DB or placeholders ═══
        if Slot.IsInjected then
        begin
          if SlotIds[SI] = 'S00' then
            Slot.Content := Format('# Strategy Unit (placeholder v0)\n- Theory intervention level: %s\n- Generation mode: %s\n- Pipeline mode: %s',
              [TheoryLevel, GenerationMode, PipelineModeToString(APipelineMode)])

          else if SlotIds[SI] = 'S01' then
            Slot.Content := Format('# Contract %s\n- Type: %s\n- Maturity: %s\n- See contract source for full terms.',
              [ContractCode, ContractType, Maturity])

          else if SlotIds[SI] = 'S02' then
            Slot.Content := '# Account Profile (placeholder v0)\nAccount profile data not yet available (S02 DB source not implemented).'

          else if SlotIds[SI] = 'S03' then
          begin
            if Slot.InjectionMode = 'summary' then
              Slot.Content := '# Reference Materials (summary)\nSummary mode: key points only.'
            else
              Slot.Content := '# Reference Materials (placeholder v0)\nNo materials linked to this contract.'
          end

          else if SlotIds[SI] = 'S04' then
            Slot.Content := '# Viral Templates (placeholder v0)\nNo historical viral templates loaded.'

          else if SlotIds[SI] = 'S05' then
            Slot.Content := Format('# Platform Rules for %s (placeholder v0)\n- Comply with platform content policy\n- No prohibited content\n- Follow platform formatting conventions',
              [TargetPlatform])

          else if SlotIds[SI] = 'S06' then
            Slot.Content := AReworkContext  // rework context passed in

          else if SlotIds[SI] = 'S07' then
            Slot.Content := '# Retained Patterns (placeholder v0)\nNo feedback patterns retained for this contract context.'

          else if SlotIds[SI] = 'S08' then
          begin
            // L2-65: wire TheoryWeave.FormatS08Content into S08 slot
            try
              if TTheoryWeaveService.HasTheoryMapping(AContractId) then
              begin
                var S08Mapping := TTheoryWeaveService.LoadMappingForContract(AContractId);
                if S08Mapping.Id <> '' then
                  Slot.Content := TTheoryWeaveService.FormatS08Content(S08Mapping, Slot.InjectionMode)
                else
                  Slot.Content := '# Source Mapping (empty)' + #10 +
                                  'Mapping record exists but contains no structural constraints.';
              end
              else
              begin
                if Slot.InjectionMode = 'boundary_only' then
                  Slot.Content := '# Source Mapping (no constraints)' + #10 +
                                  'No theory mapping attached — boundary mode inactive.'
                else if Slot.InjectionMode = 'theory_stance' then
                  Slot.Content := '# Source Mapping (theory-neutral)' + #10 +
                                  'No theory stance injected — generate freely from contract must_lands.'
                else
                  Slot.Content := '# Source Mapping (none)' + #10 +
                                  'Contract is theory-neutral; no S08 injection.';
              end;
            except
              on E: Exception do
                Slot.Content := '# Source Mapping (error)' + #10 +
                                'Failed to load mapping: ' + E.Message;
            end;
          end

          else if SlotIds[SI] = 'S09' then
          begin
            if Slot.InjectionMode = 'first_round_alternative' then
              Slot.Content := '# Cognition Trace (placeholder v0)\nFirst round output alternative for heavy mode 2nd pass.'
            else
              Slot.Content := '# Cognition Trace (placeholder v0)\nCognition trace data not yet available (S09 DB source not implemented).'
          end;
        end;

        Slot.SourceVersion := 'v0';
        AResult.Slots[SI] := Slot;
      end;

      // ═══ Build prompt text ═══
      AResult.PromptText := BuildPrompt(AResult.Slots, APipelineMode, AIsRework);

      // ═══ Fill meta ═══
      AResult.Meta.ContextPackId := Format('ctx_%s', [FormatDateTime('yyyymmddhhnnss', Now)]);
      AResult.Meta.PipelineMode := PipelineModeToString(APipelineMode);
      AResult.Meta.GenerationMode := GenerationMode;
      AResult.Meta.TheoryInterventionLevel := TheoryLevel;
      AResult.Meta.IsRework := AIsRework;
      AResult.Meta.ContractId := AContractId;
      AResult.Meta.ContractVersion := JContract.GetValue<Integer>('version_no', 1);
      AResult.Meta.FrozenVersions := '{}';  // v0: no version tracking yet
      AResult.Meta.CacheTierOrder := '[{"tier":"steady_state","slots":["S05"]},{"tier":"strategy","slots":["S00","S08","S02","S07"]},{"tier":"task","slots":["S01","S03","S04","S06","S09"]}]';
      AResult.Meta.SlotMap := SlotsToJson(AResult.Slots);
      AResult.Meta.TokenEstimate := EstimateTokens(AResult.PromptText);
      AResult.Meta.SlotCount := Length(AResult.Slots);

      // Count injected/skipped
      AResult.Meta.InjectedSlots := 0;
      AResult.Meta.SkippedSlots := 0;
      for SI := 0 to High(AResult.Slots) do
        if AResult.Slots[SI].IsInjected then
          Inc(AResult.Meta.InjectedSlots)
        else
          Inc(AResult.Meta.SkippedSlots);

      AResult.Meta.Asto := Format('{"state":"assembled","actor":"%s"}', ['system']);
      AResult.Meta.Odd := Format('{"boundary_condition":"contract_%s_v%d","evidence_ref":"%s"}',
        [AContractId, JContract.GetValue<Integer>('version_no', 1), AResult.Meta.ContextPackId]);

      AResult.Success := True;
      Result := True;

    finally
      JContract.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

// ── Serialization ──

class function TPromptAssemblyService.SlotsToJson(const ASlots: TPromptSlotList): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  SetLength(Parts, Length(ASlots));
  for I := 0 to High(ASlots) do
    Parts[I] := Format('{"slot":"%s","label":"%s","tier":"%s","injected":%s,"injection_mode":"%s","mandatory":%s,"content_len":%d}',
      [ASlots[I].SlotId,
       ASlots[I].DisplayLabel,
       TierToString(ASlots[I].Tier),
       BoolToStr(ASlots[I].IsInjected, True).ToLower,
       ASlots[I].InjectionMode,
       BoolToStr(ASlots[I].IsMandatory, True).ToLower,
       Length(ASlots[I].Content)]);

  Result := '[' + string.Join(',', Parts) + ']';
end;

class function TPromptAssemblyService.MetaToJson(const AMeta: TAssemblyMeta): string;
begin
  Result := MakeJsonObj([
    MakeJsonParam('context_pack_id', AMeta.ContextPackId),
    MakeJsonParam('pipeline_mode', AMeta.PipelineMode),
    MakeJsonParam('generation_mode', AMeta.GenerationMode),
    MakeJsonParam('theory_intervention_level', AMeta.TheoryInterventionLevel),
    Format('"is_rework":%s', [BoolToStr(AMeta.IsRework, True).ToLower]),
    MakeJsonParam('contract_id', AMeta.ContractId),
    JsonParamInt('contract_version', AMeta.ContractVersion),
    JsonParamInt('token_estimate', AMeta.TokenEstimate),
    JsonParamInt('slot_count', AMeta.SlotCount),
    JsonParamInt('injected_slots', AMeta.InjectedSlots),
    JsonParamInt('skipped_slots', AMeta.SkippedSlots),
    Format('"asto":%s', [AMeta.Asto]),
    Format('"odd":%s', [AMeta.Odd])
  ]);
end;

class function TPromptAssemblyService.ResultToJson(const AResult: TAssemblyResult): string;
var
  MetaStr, PromptSnippet: string;
begin
  MetaStr := MetaToJson(AResult.Meta);
  if Length(AResult.PromptText) > 200 then
    PromptSnippet := Copy(AResult.PromptText, 1, 200) + '...'
  else
    PromptSnippet := AResult.PromptText;

  Result := MakeJsonObj([
    Format('"success":%s', [BoolToStr(AResult.Success, True).ToLower]),
    MakeJsonParam('error_message', AResult.ErrorMessage),
    Format('"meta":%s', [MetaStr]),
    MakeJsonParam('prompt_snippet', PromptSnippet),
    JsonParamInt('prompt_total_chars', Length(AResult.PromptText)),
    Format('"slots":%s', [SlotsToJson(AResult.Slots)])
  ]);
end;

end.