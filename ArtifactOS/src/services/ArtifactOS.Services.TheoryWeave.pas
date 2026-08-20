unit ArtifactOS.Services.TheoryWeave;

{
  S08 Structural Source Mapping — TheoryWeave v0
  Implements docs/11 §3.3a + §3.1d theory mapping pipeline.

  Responsibilities:
  1. Load theory resources from DB or input
  2. Call LLM (via DeepLLMProxy SemiES tier) to produce structured mapping
  3. Parse causal_primitives, required_relations, forbidden_relations
  4. Persist mapping + relations to theory_mapping / causal_primitive / theory_relation
  5. Provide S08 content injection for PromptAssembly
  6. Provide structural fidelity check for QualityGate ES-07 + SES-05

  DB pattern: TArtifactDB (Pattern A) — DB.Connect → TFDQuery/ExecuteScalar → DB.Disconnect
}

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  FireDAC.Comp.Client,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Services.DeepLLMProxy;

type
  TCausalPrimitive = record
    PrimId: string;       // cp_001 style
    PrimType: string;     // stage | attribute | causation | sequence
    Subject: string;
    Operator: string;
    Object_: string;
    SourceRef: string;
    Description: string;
    SortOrder: Integer;
  end;

  TTheoryRelation = record
    RelId: string;         // rr_001 / fr_001 style
    RelCategory: string;   // required | forbidden
    RelType: string;       // stage | attribute | causation | sequence | no_override | no_reinterpret | no_omit
    FromConcept: string;
    ToConcept: string;
    SubjectPattern: string;
    Relation: string;
    ObjectPattern: string;
    Source: string;
    Description: string;
    Immutable: Boolean;
  end;

  TAllowedTranslation = record
    FromExpr: string;
    ToExpr: string;
    Platform: string;
  end;

  TTheoryMapping = record
    Id: string;
    ContractId: string;
    Topic: string;
    EntryMode: string;      // hotspot_driven | theory_driven
    Intervention: string;   // low | medium | high
    MappingKind: string;    // theory | source | mixed
    ActivatedConcepts: TArray<string>;
    ThesisPath: TArray<string>;
    ExpressionPolicy: string;  // explicit | implicit | translated
    CausalPrimitives: TArray<TCausalPrimitive>;
    RequiredRelations: TArray<TTheoryRelation>;
    ForbiddenRelations: TArray<TTheoryRelation>;
    AllowedTranslations: TArray<TAllowedTranslation>;
    NonNegotiablePrinciples: TArray<string>;
    FidelityScore: Double;
  end;

  TFidelityResult = record
    Consistency: string;      // pass | warn | fail
    MissingRequired: TArray<string>;
    ViolatedForbidden: TArray<string>;
    OutOfBounds: TArray<string>;
    Score: Double;
    Evidence: string;
  end;

  TTheoryWeaveService = class
  public
    /// Generate theory mapping from contract + topic (calls LLM + persists)
    class function GenerateMapping(const AContractId, ATopic: string;
      AIntervention: string = 'medium'): TTheoryMapping;

    /// Load existing mapping from DB by mapping ID
    class function LoadMapping(const AMappingId: string): TTheoryMapping;

    /// Load latest mapping for a contract
    class function LoadMappingForContract(const AContractId: string): TTheoryMapping;

    /// Format S08 content for PromptAssembly injection
    class function FormatS08Content(const AMapping: TTheoryMapping;
      const AInjectionMode: string): string;

    /// Structural fidelity check (ES-07 + SES-05)
    class function CheckStructuralFidelity(const AMappingId, AArtifactBody: string): TFidelityResult;

    /// Persist mapping to DB (sets AMapping.Id on insert)
    class function PersistMapping(var AMapping: TTheoryMapping): string;

    /// Quick check: does contract have a theory mapping?
    class function HasTheoryMapping(const AContractId: string): Boolean;

  private
    class function BuildMappingPrompt(const ATopic, AEntryMode, AIntervention: string;
      const AResources: TArray<string>): string;
    class function ParseMappingResponse(const AContent: string;
      out AMapping: TTheoryMapping): Boolean;
    class function MatchPattern(const APattern, AValue: string): Boolean;
    class procedure PersistRelation(const AMappingId: string; ARel: TTheoryRelation);
    class procedure PersistFidelityCheck(const AMappingId: string; const AResult: TFidelityResult);
    class function Escape(const S: string): string;
  end;

implementation

uses
  FireDAC.Stan.Param;

{ Helper }

function BoolToStr(B: Boolean): string;
begin
  if B then Result := 'TRUE' else Result := 'FALSE';
end;

{ TTheoryWeaveService }

class function TTheoryWeaveService.Escape(const S: string): string;
begin
  Result := QuotedStr(S);
end;

// =============================================================================
// GenerateMapping — produce a theory mapping via LLM
// =============================================================================

class function TTheoryWeaveService.GenerateMapping(const AContractId, ATopic: string;
  AIntervention: string): TTheoryMapping;
var
  Prompt, Response: string;
  Resources: TArray<string>;
  I: Integer;
  DB: TArtifactDB;
  Q: TFDQuery;
begin
  // Initialize result
  Result := Default(TTheoryMapping);
  Result.ContractId := AContractId;
  Result.Topic := ATopic;
  Result.EntryMode := 'hotspot_driven';
  Result.Intervention := AIntervention;
  Result.MappingKind := 'theory';
  Result.FidelityScore := -1;
  Result.ExpressionPolicy := 'explicit';

  // Load theory resources from DB if available (Pattern C)
  Resources := nil;
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := DB.Connection;
      Q.SQL.Text :=
        'SELECT content FROM artifactos.theory_resource ' +
        'WHERE mapping_id = (' +
        '  SELECT id FROM artifactos.theory_mapping WHERE contract_id = :cid ' +
        '  ORDER BY created_at DESC LIMIT 1) ' +
        'ORDER BY resource_type, sort_order';
      Q.ParamByName('cid').AsString := AContractId;
      Q.Open;
      while not Q.Eof do
      begin
        SetLength(Resources, Length(Resources) + 1);
        Resources[High(Resources)] := Q.FieldByName('content').AsString;
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    DB.Disconnect;
  end;

  // Build prompt
  Prompt := BuildMappingPrompt(ATopic, Result.EntryMode, AIntervention, Resources);

  // Call LLM via DeepLLMProxy (SemiES tier)
  var LLMResult := TArtifactOSLLMProxy.Instance.Chat(
    aostSemiES,
    Prompt,
    'You are a theory mapping analyst. Generate a structured source mapping in the exact JSON schema requested.');
  Response := LLMResult.Content;

  // Parse response
  if not ParseMappingResponse(Response, Result) then
  begin
    // Fallback: minimal mapping (no primitives/relations)
    Result.ExpressionPolicy := 'explicit';
  end;

  // Persist
  PersistMapping(Result);
end;

// =============================================================================
// LoadMapping — full mapping from DB by ID (Pattern C)
// =============================================================================

class function TTheoryWeaveService.LoadMapping(const AMappingId: string): TTheoryMapping;
var
  DB: TArtifactDB;
  Q: TFDQuery;
  MJ: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Prim: TCausalPrimitive;
  Rel: TTheoryRelation;
  Trans: TAllowedTranslation;
  Val: TJSONValue;
begin
  Result := Default(TTheoryMapping);
  Result.FidelityScore := -1;
  Result.ExpressionPolicy := 'explicit';

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // 1. Mapping header
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := DB.Connection;
      Q.SQL.Text :=
        'SELECT id, contract_id, topic, entry_mode, intervention, mapping_kind, ' +
        'mapping_json, fidelity_score FROM artifactos.theory_mapping WHERE id = :mid';
      Q.ParamByName('mid').AsString := AMappingId;
      Q.Open;
      if Q.Eof then Exit;

      Result.Id := Q.FieldByName('id').AsString;
      Result.ContractId := Q.FieldByName('contract_id').AsString;
      Result.Topic := Q.FieldByName('topic').AsString;
      Result.EntryMode := Q.FieldByName('entry_mode').AsString;
      Result.Intervention := Q.FieldByName('intervention').AsString;
      Result.MappingKind := Q.FieldByName('mapping_kind').AsString;
      if not Q.FieldByName('fidelity_score').IsNull then
        Result.FidelityScore := Q.FieldByName('fidelity_score').AsFloat;

      // Parse mapping_json
      MJ := TJSONObject.ParseJSONValue(Q.FieldByName('mapping_json').AsString) as TJSONObject;
    finally
      Q.Free;
    end;

    if MJ <> nil then
    try
      Arr := MJ.FindValue('activated_concepts') as TJSONArray;
      if Arr <> nil then
      begin
        SetLength(Result.ActivatedConcepts, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          Result.ActivatedConcepts[I] := Arr.Items[I].Value;
      end;

      Arr := MJ.FindValue('thesis_path') as TJSONArray;
      if Arr <> nil then
      begin
        SetLength(Result.ThesisPath, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          Result.ThesisPath[I] := Arr.Items[I].Value;
      end;

      Val := MJ.FindValue('expression_policy');
      if Val <> nil then
        Result.ExpressionPolicy := Val.Value;

      Arr := MJ.FindValue('non_negotiable_principles') as TJSONArray;
      if Arr <> nil then
      begin
        SetLength(Result.NonNegotiablePrinciples, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          Result.NonNegotiablePrinciples[I] := Arr.Items[I].Value;
      end;
    finally
      MJ.Free;
    end;

    // 2. Causal primitives
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := DB.Connection;
      Q.SQL.Text :=
        'SELECT prim_id, prim_type, subject, operator, object, source_ref, description, sort_order ' +
        'FROM artifactos.causal_primitive WHERE mapping_id = :mid ORDER BY sort_order';
      Q.ParamByName('mid').AsString := AMappingId;
      Q.Open;
      while not Q.Eof do
      begin
        Prim := Default(TCausalPrimitive);
        Prim.PrimId := Q.FieldByName('prim_id').AsString;
        Prim.PrimType := Q.FieldByName('prim_type').AsString;
        Prim.Subject := Q.FieldByName('subject').AsString;
        Prim.Operator := Q.FieldByName('operator').AsString;
        Prim.Object_ := Q.FieldByName('object').AsString;
        Prim.SourceRef := Q.FieldByName('source_ref').AsString;
        Prim.Description := Q.FieldByName('description').AsString;
        Prim.SortOrder := Q.FieldByName('sort_order').AsInteger;
        SetLength(Result.CausalPrimitives, Length(Result.CausalPrimitives) + 1);
        Result.CausalPrimitives[High(Result.CausalPrimitives)] := Prim;
        Q.Next;
      end;
    finally
      Q.Free;
    end;

    // 3. Relations (required + forbidden)
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := DB.Connection;
      Q.SQL.Text :=
        'SELECT rel_id, rel_category, rel_type, from_concept, to_concept, ' +
        'subject_pattern, relation, object_pattern, source, description, immutable ' +
        'FROM artifactos.theory_relation WHERE mapping_id = :mid ORDER BY rel_category, rel_id';
      Q.ParamByName('mid').AsString := AMappingId;
      Q.Open;
      while not Q.Eof do
      begin
        Rel := Default(TTheoryRelation);
        Rel.RelId := Q.FieldByName('rel_id').AsString;
        Rel.RelCategory := Q.FieldByName('rel_category').AsString;
        Rel.RelType := Q.FieldByName('rel_type').AsString;
        Rel.FromConcept := Q.FieldByName('from_concept').AsString;
        Rel.ToConcept := Q.FieldByName('to_concept').AsString;
        Rel.SubjectPattern := Q.FieldByName('subject_pattern').AsString;
        Rel.Relation := Q.FieldByName('relation').AsString;
        Rel.ObjectPattern := Q.FieldByName('object_pattern').AsString;
        Rel.Source := Q.FieldByName('source').AsString;
        Rel.Description := Q.FieldByName('description').AsString;
        Rel.Immutable := Q.FieldByName('immutable').AsBoolean;

        if SameText(Rel.RelCategory, 'required') then
        begin
          SetLength(Result.RequiredRelations, Length(Result.RequiredRelations) + 1);
          Result.RequiredRelations[High(Result.RequiredRelations)] := Rel;
        end
        else
        begin
          SetLength(Result.ForbiddenRelations, Length(Result.ForbiddenRelations) + 1);
          Result.ForbiddenRelations[High(Result.ForbiddenRelations)] := Rel;
        end;
        Q.Next;
      end;
    finally
      Q.Free;
    end;

    // 4. Allowed translations
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := DB.Connection;
      Q.SQL.Text :=
        'SELECT from_expr, to_expr, platform FROM artifactos.allowed_translation WHERE mapping_id = :mid';
      Q.ParamByName('mid').AsString := AMappingId;
      Q.Open;
      while not Q.Eof do
      begin
        Trans := Default(TAllowedTranslation);
        Trans.FromExpr := Q.FieldByName('from_expr').AsString;
        Trans.ToExpr := Q.FieldByName('to_expr').AsString;
        Trans.Platform := Q.FieldByName('platform').AsString;
        SetLength(Result.AllowedTranslations, Length(Result.AllowedTranslations) + 1);
        Result.AllowedTranslations[High(Result.AllowedTranslations)] := Trans;
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

// =============================================================================
// LoadMappingForContract — latest mapping for a contract (Pattern A)
// =============================================================================

class function TTheoryWeaveService.LoadMappingForContract(const AContractId: string): TTheoryMapping;
var
  DB: TArtifactDB;
  Mid: string;
begin
  Result := Default(TTheoryMapping);
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Mid := DB.ExecuteScalar(
      'SELECT id::text FROM artifactos.theory_mapping ' +
      'WHERE contract_id = ' + Escape(AContractId) + ' ORDER BY created_at DESC LIMIT 1');
  finally
    DB.Disconnect;
  end;

  if Mid <> '' then
    Result := LoadMapping(Mid);
end;

// =============================================================================
// HasTheoryMapping — quick check (Pattern A)
// =============================================================================

class function TTheoryWeaveService.HasTheoryMapping(const AContractId: string): Boolean;
var
  DB: TArtifactDB;
  V: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    V := DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.theory_mapping WHERE contract_id = ' +
      Escape(AContractId));
  finally
    DB.Disconnect;
  end;
  Result := (V <> '') and (StrToIntDef(V, 0) > 0);
end;

// =============================================================================
// FormatS08Content — format mapping for PromptAssembly injection
// =============================================================================

class function TTheoryWeaveService.FormatS08Content(const AMapping: TTheoryMapping;
  const AInjectionMode: string): string;
var
  SB: TStringBuilder;
  I: Integer;
  R: TTheoryRelation;
  P: TCausalPrimitive;
  T: TAllowedTranslation;
begin
  SB := TStringBuilder.Create;
  try
    if SameText(AInjectionMode, 'boundary_only') then
    begin
      // Minimal: just forbidden relations + non-negotiable principles
      SB.AppendLine('# Source Mapping (boundary constraints)');
      if Length(AMapping.ForbiddenRelations) > 0 then
      begin
        SB.AppendLine('## Forbidden (must not appear in draft)');
        for I := 0 to High(AMapping.ForbiddenRelations) do
        begin
          R := AMapping.ForbiddenRelations[I];
          if R.Description <> '' then
            SB.AppendLine('- [' + R.RelId + '] ' + R.Description)
          else
            SB.AppendLine('- [' + R.RelId + '] ' + R.SubjectPattern + ' ' + R.Relation + ' ' + R.ObjectPattern);
        end;
      end;
      if Length(AMapping.NonNegotiablePrinciples) > 0 then
      begin
        SB.AppendLine('## Non-negotiable Principles');
        for I := 0 to High(AMapping.NonNegotiablePrinciples) do
          SB.AppendLine('- ' + AMapping.NonNegotiablePrinciples[I]);
      end;
    end
    else if SameText(AInjectionMode, 'theory_stance') then
    begin
      // Heavy mode: full mapping with theory stance
      SB.AppendLine('# Source Mapping (with theory stance)');
      SB.AppendLine('## Theory Intervention: ' + UpperCase(AMapping.Intervention));
      SB.AppendLine('## Topic: ' + AMapping.Topic);
      if Length(AMapping.ActivatedConcepts) > 0 then
      begin
        SB.AppendLine('## Activated Concepts');
        for I := 0 to High(AMapping.ActivatedConcepts) do
          SB.AppendLine('- ' + AMapping.ActivatedConcepts[I]);
      end;
      if Length(AMapping.ThesisPath) > 0 then
      begin
        SB.AppendLine('## Thesis Path');
        for I := 0 to High(AMapping.ThesisPath) do
          SB.AppendLine(IntToStr(I + 1) + '. ' + AMapping.ThesisPath[I]);
      end;
      if Length(AMapping.CausalPrimitives) > 0 then
      begin
        SB.AppendLine('## Causal Primitives');
        for I := 0 to High(AMapping.CausalPrimitives) do
        begin
          P := AMapping.CausalPrimitives[I];
          SB.AppendLine('- [' + P.PrimId + '] ' + P.Subject + ' ' + P.Operator + ' ' + P.Object_);
        end;
      end;
      if Length(AMapping.RequiredRelations) > 0 then
      begin
        SB.AppendLine('## Required Relations');
        for I := 0 to High(AMapping.RequiredRelations) do
        begin
          R := AMapping.RequiredRelations[I];
          SB.AppendLine('- [' + R.RelId + '] ' + R.FromConcept + ' -> ' + R.ToConcept + ' (' + R.RelType + ')');
        end;
      end;
      if Length(AMapping.ForbiddenRelations) > 0 then
      begin
        SB.AppendLine('## Forbidden Relations');
        for I := 0 to High(AMapping.ForbiddenRelations) do
        begin
          R := AMapping.ForbiddenRelations[I];
          SB.AppendLine('- [' + R.RelId + '] ' + R.SubjectPattern + ' ' + R.Relation + ' ' + R.ObjectPattern);
        end;
      end;
      SB.AppendLine('## Expression Policy: ' + AMapping.ExpressionPolicy);
    end
    else
    begin
      // Full mode
      SB.AppendLine('# Source Mapping (full)');
      SB.AppendLine('Mapping ID: ' + AMapping.Id);
      SB.AppendLine('Entry Mode: ' + AMapping.EntryMode);
      SB.AppendLine('Intervention: ' + AMapping.Intervention);
      if Length(AMapping.ActivatedConcepts) > 0 then
      begin
        SB.AppendLine('## Activated Concepts');
        for I := 0 to High(AMapping.ActivatedConcepts) do
          SB.AppendLine('- ' + AMapping.ActivatedConcepts[I]);
      end;
      if Length(AMapping.ThesisPath) > 0 then
      begin
        SB.AppendLine('## Thesis Path');
        for I := 0 to High(AMapping.ThesisPath) do
          SB.AppendLine(IntToStr(I + 1) + '. ' + AMapping.ThesisPath[I]);
      end;
      if Length(AMapping.CausalPrimitives) > 0 then
      begin
        SB.AppendLine('## Causal Primitives');
        for I := 0 to High(AMapping.CausalPrimitives) do
        begin
          P := AMapping.CausalPrimitives[I];
          SB.AppendLine('- [' + P.PrimId + '/' + P.PrimType + '] ' +
            P.Subject + ' ' + P.Operator + ' ' + P.Object_);
          if P.Description <> '' then
            SB.AppendLine('  Description: ' + P.Description);
        end;
      end;
      if Length(AMapping.RequiredRelations) > 0 then
      begin
        SB.AppendLine('## Required Relations (must be preserved)');
        for I := 0 to High(AMapping.RequiredRelations) do
        begin
          R := AMapping.RequiredRelations[I];
          SB.AppendLine('- [' + R.RelId + '/' + R.RelType + '] ' +
            R.FromConcept + ' -> ' + R.ToConcept);
          if R.Description <> '' then
            SB.AppendLine('  Note: ' + R.Description);
        end;
      end;
      if Length(AMapping.ForbiddenRelations) > 0 then
      begin
        SB.AppendLine('## Forbidden Relations (must not appear)');
        for I := 0 to High(AMapping.ForbiddenRelations) do
        begin
          R := AMapping.ForbiddenRelations[I];
          SB.AppendLine('- [' + R.RelId + '/' + R.RelType + '] ' +
            R.SubjectPattern + ' ' + R.Relation + ' ' + R.ObjectPattern);
          if R.Description <> '' then
            SB.AppendLine('  Note: ' + R.Description);
        end;
      end;
      if Length(AMapping.AllowedTranslations) > 0 then
      begin
        SB.AppendLine('## Allowed Translations');
        for I := 0 to High(AMapping.AllowedTranslations) do
        begin
          T := AMapping.AllowedTranslations[I];
          SB.AppendLine('- ' + T.FromExpr + ' -> ' + T.ToExpr + ' [' + T.Platform + ']');
        end;
      end;
      if Length(AMapping.NonNegotiablePrinciples) > 0 then
      begin
        SB.AppendLine('## Non-negotiable Principles');
        for I := 0 to High(AMapping.NonNegotiablePrinciples) do
          SB.AppendLine('- ' + AMapping.NonNegotiablePrinciples[I]);
      end;
      SB.AppendLine('Expression Policy: ' + AMapping.ExpressionPolicy);
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// =============================================================================
// CheckStructuralFidelity — ES-07 + SES-05 structural fidelity gate
// =============================================================================

class function TTheoryWeaveService.CheckStructuralFidelity(
  const AMappingId, AArtifactBody: string): TFidelityResult;
var
  Mapping: TTheoryMapping;
  I: Integer;
  R: TTheoryRelation;
  Body: string;
  MissingCount, ViolatedCount: Integer;
begin
  Result.Consistency := 'pass';
  Result.Score := 100.0;
  Result.Evidence := '{}';

  Mapping := LoadMapping(AMappingId);
  if Mapping.Id = '' then Exit;

  Body := LowerCase(AArtifactBody);

  // Check required relations: from_concept and to_concept must both appear
  for I := 0 to High(Mapping.RequiredRelations) do
  begin
    R := Mapping.RequiredRelations[I];
    if (R.FromConcept <> '') and (R.ToConcept <> '') then
    begin
      if (not Body.Contains(LowerCase(R.FromConcept))) or
         (not Body.Contains(LowerCase(R.ToConcept))) then
      begin
        SetLength(Result.MissingRequired, Length(Result.MissingRequired) + 1);
        Result.MissingRequired[High(Result.MissingRequired)] := R.RelId;
      end;
    end;
  end;

  // Check forbidden relations: pattern matching
  for I := 0 to High(Mapping.ForbiddenRelations) do
  begin
    R := Mapping.ForbiddenRelations[I];
    if (R.SubjectPattern <> '*') and (R.ObjectPattern <> '*') then
    begin
      if MatchPattern(LowerCase(R.SubjectPattern), Body) and
         MatchPattern(LowerCase(R.ObjectPattern), Body) and
         (R.Relation <> '') and Body.Contains(LowerCase(R.Relation)) then
      begin
        SetLength(Result.ViolatedForbidden, Length(Result.ViolatedForbidden) + 1);
        Result.ViolatedForbidden[High(Result.ViolatedForbidden)] := R.RelId;
      end;
    end;
  end;

  // Determine overall consistency
  MissingCount := Length(Result.MissingRequired);
  ViolatedCount := Length(Result.ViolatedForbidden);

  if ViolatedCount > 0 then
  begin
    Result.Consistency := 'fail';
    Result.Score := 0.0;
  end
  else if MissingCount > 0 then
  begin
    Result.Consistency := 'warn';
    Result.Score := 100.0 - (MissingCount * 20.0);
    if Result.Score < 0 then Result.Score := 0;
  end;

  // Persist fidelity check
  PersistFidelityCheck(AMappingId, Result);

  // Build evidence JSON
  Result.Evidence :=
    '{"consistency":"' + Result.Consistency + '",' +
    '"missing_count":' + IntToStr(MissingCount) + ',' +
    '"violated_count":' + IntToStr(ViolatedCount) + '}';
end;

// =============================================================================
// PersistMapping — save mapping + primitives + relations to DB (Pattern A)
// =============================================================================

class function TTheoryWeaveService.PersistMapping(var AMapping: TTheoryMapping): string;
var
  DB: TArtifactDB;
  MJ: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Build mapping_json
    MJ := TJSONObject.Create;
    try
      Arr := TJSONArray.Create;
      for I := 0 to High(AMapping.ActivatedConcepts) do
        Arr.Add(AMapping.ActivatedConcepts[I]);
      MJ.AddPair('activated_concepts', Arr);

      Arr := TJSONArray.Create;
      for I := 0 to High(AMapping.ThesisPath) do
        Arr.Add(AMapping.ThesisPath[I]);
      MJ.AddPair('thesis_path', Arr);

      MJ.AddPair('expression_policy', AMapping.ExpressionPolicy);

      Arr := TJSONArray.Create;
      for I := 0 to High(AMapping.NonNegotiablePrinciples) do
        Arr.Add(AMapping.NonNegotiablePrinciples[I]);
      MJ.AddPair('non_negotiable_principles', Arr);

      // Insert or update mapping header
      if AMapping.Id = '' then
      begin
        AMapping.Id := DB.InsertAndReturnId(
          'INSERT INTO artifactos.theory_mapping (contract_id, topic, entry_mode, intervention, mapping_kind, mapping_json) ' +
          'VALUES (' + Escape(AMapping.ContractId) + ', ' + Escape(AMapping.Topic) + ', ' +
          Escape(AMapping.EntryMode) + ', ' + Escape(AMapping.Intervention) + ', ' +
          Escape(AMapping.MappingKind) + ', ' + Escape(MJ.ToJSON) + '::jsonb) ' +
          'RETURNING id::text');
      end
      else
      begin
        DB.Execute(
          'UPDATE artifactos.theory_mapping SET mapping_json = ' + Escape(MJ.ToJSON) + '::jsonb ' +
          'WHERE id = ' + Escape(AMapping.Id));
      end;
    finally
      MJ.Free;
    end;

    // Persist causal primitives (delete + re-insert)
    DB.Execute('DELETE FROM artifactos.causal_primitive WHERE mapping_id = ' + Escape(AMapping.Id));
    for I := 0 to High(AMapping.CausalPrimitives) do
    begin
      DB.Execute(
        'INSERT INTO artifactos.causal_primitive (mapping_id, prim_id, prim_type, subject, operator, object, source_ref, description, sort_order) ' +
        'VALUES (' + Escape(AMapping.Id) + ', ' + Escape(AMapping.CausalPrimitives[I].PrimId) + ', ' +
        Escape(AMapping.CausalPrimitives[I].PrimType) + ', ' + Escape(AMapping.CausalPrimitives[I].Subject) + ', ' +
        Escape(AMapping.CausalPrimitives[I].Operator) + ', ' + Escape(AMapping.CausalPrimitives[I].Object_) + ', ' +
        Escape(AMapping.CausalPrimitives[I].SourceRef) + ', ' + Escape(AMapping.CausalPrimitives[I].Description) + ', ' +
        IntToStr(AMapping.CausalPrimitives[I].SortOrder) + ')');
    end;

    // Persist relations (delete + re-insert)
    DB.Execute('DELETE FROM artifactos.theory_relation WHERE mapping_id = ' + Escape(AMapping.Id));
    for I := 0 to High(AMapping.RequiredRelations) do
      PersistRelation(AMapping.Id, AMapping.RequiredRelations[I]);
    for I := 0 to High(AMapping.ForbiddenRelations) do
      PersistRelation(AMapping.Id, AMapping.ForbiddenRelations[I]);

    // Persist translations (delete + re-insert)
    DB.Execute('DELETE FROM artifactos.allowed_translation WHERE mapping_id = ' + Escape(AMapping.Id));
    for I := 0 to High(AMapping.AllowedTranslations) do
    begin
      DB.Execute(
        'INSERT INTO artifactos.allowed_translation (mapping_id, from_expr, to_expr, platform) ' +
        'VALUES (' + Escape(AMapping.Id) + ', ' + Escape(AMapping.AllowedTranslations[I].FromExpr) + ', ' +
        Escape(AMapping.AllowedTranslations[I].ToExpr) + ', ' + Escape(AMapping.AllowedTranslations[I].Platform) + ')');
    end;

    Result := AMapping.Id;
  finally
    DB.Disconnect;
  end;
end;

// =============================================================================
// Private helpers
// =============================================================================

class procedure TTheoryWeaveService.PersistRelation(const AMappingId: string; ARel: TTheoryRelation);
begin
  ArtifactOS_DB.Execute(
    'INSERT INTO artifactos.theory_relation ' +
    '(mapping_id, rel_id, rel_category, rel_type, from_concept, to_concept, ' +
    'subject_pattern, relation, object_pattern, source, description, immutable) ' +
    'VALUES (' + Escape(AMappingId) + ', ' + Escape(ARel.RelId) + ', ' +
    Escape(ARel.RelCategory) + ', ' + Escape(ARel.RelType) + ', ' +
    Escape(ARel.FromConcept) + ', ' + Escape(ARel.ToConcept) + ', ' +
    Escape(ARel.SubjectPattern) + ', ' + Escape(ARel.Relation) + ', ' +
    Escape(ARel.ObjectPattern) + ', ' + Escape(ARel.Source) + ', ' +
    Escape(ARel.Description) + ', ' + BoolToStr(ARel.Immutable) + ')');
end;

class procedure TTheoryWeaveService.PersistFidelityCheck(const AMappingId: string;
  const AResult: TFidelityResult);
var
  I: Integer;
  MissingArr, ViolatedArr: string;
begin
  MissingArr := '{';
  for I := 0 to High(AResult.MissingRequired) do
  begin
    if I > 0 then MissingArr := MissingArr + ',';
    MissingArr := MissingArr + '"' + AResult.MissingRequired[I].Replace('"', '\"') + '"';
  end;
  MissingArr := MissingArr + '}';

  ViolatedArr := '{';
  for I := 0 to High(AResult.ViolatedForbidden) do
  begin
    if I > 0 then ViolatedArr := ViolatedArr + ',';
    ViolatedArr := ViolatedArr + '"' + AResult.ViolatedForbidden[I].Replace('"', '\"') + '"';
  end;
  ViolatedArr := ViolatedArr + '}';

  ArtifactOS_DB.Execute(
    'INSERT INTO artifactos.source_fidelity_check (mapping_id, check_type, consistency, ' +
    'missing_required, violated_forbidden, out_of_bounds, score, evidence) ' +
    'VALUES (' + Escape(AMappingId) + ', ''structure'', ' + Escape(AResult.Consistency) + ', ' +
    '''' + MissingArr + '''::text[], ' + '''' + ViolatedArr + '''::text[], ' +
    '''{}''::text[], ' + FloatToStr(AResult.Score) + ', ' +
    Escape(AResult.Evidence) + '::jsonb)');
end;

class function TTheoryWeaveService.BuildMappingPrompt(const ATopic, AEntryMode, AIntervention: string;
  const AResources: TArray<string>): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('Generate a structured theory source mapping for the following topic.');
    SB.AppendLine('');
    SB.AppendLine('Topic: ' + ATopic);
    SB.AppendLine('Entry Mode: ' + AEntryMode);
    SB.AppendLine('Theory Intervention Level: ' + AIntervention);
    SB.AppendLine('');

    if Length(AResources) > 0 then
    begin
      SB.AppendLine('## Available Theory Resources:');
      for I := 0 to High(AResources) do
        SB.AppendLine(AResources[I]);
      SB.AppendLine('');
    end;

    SB.AppendLine('## Required Output Format (JSON only):');
    SB.AppendLine('{');
    SB.AppendLine('  "activated_concepts": ["concept1", "concept2", ...],');
    SB.AppendLine('  "thesis_path": ["concept -> judgment -> claim path"],');

    if (AIntervention = 'medium') or (AIntervention = 'high') then
    begin
      SB.AppendLine('  "causal_primitives": [');
      SB.AppendLine('    {"prim_id": "cp_001", "prim_type": "stage|attribute|causation|sequence",');
      SB.AppendLine('     "subject": "...", "operator": "must_pass_through", "object": "...",');
      SB.AppendLine('     "source_ref": "...", "description": "..."}');
      SB.AppendLine('  ],');
    end;

    if AIntervention = 'high' then
    begin
      SB.AppendLine('  "required_relations": [');
      SB.AppendLine('    {"rel_id": "rr_001", "rel_type": "stage|attribute|causation|sequence",');
      SB.AppendLine('     "from": "concept", "to": "concept", "description": "..."}');
      SB.AppendLine('  ],');
      SB.AppendLine('  "forbidden_relations": [');
      SB.AppendLine('    {"id": "fr_001", "type": "no_override|no_reinterpret|no_omit",');
      SB.AppendLine('     "subject_pattern": "*", "relation": "overrides", "object_pattern": "theory_core_*",');
      SB.AppendLine('     "source": "...", "description": "..."}');
      SB.AppendLine('  ],');
      SB.AppendLine('  "non_negotiable_principles": ["principle1"],');
      SB.AppendLine('  "allowed_translations": [{"from": "original", "to": "adapted", "platform": "zhihu"}],');
    end;

    SB.AppendLine('  "expression_policy": "explicit|implicit|translated"');
    SB.AppendLine('}');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TTheoryWeaveService.ParseMappingResponse(const AContent: string;
  out AMapping: TTheoryMapping): Boolean;
var
  JSON: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Prim: TCausalPrimitive;
  Rel: TTheoryRelation;
  Trans: TAllowedTranslation;
  Val: TJSONValue;
begin
  Result := False;
  JSON := TJSONObject.ParseJSONValue(AContent) as TJSONObject;
  if JSON = nil then Exit;
  try
    // activated_concepts
    Arr := JSON.FindValue('activated_concepts') as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(AMapping.ActivatedConcepts, Arr.Count);
      for I := 0 to Arr.Count - 1 do
        AMapping.ActivatedConcepts[I] := Arr.Items[I].Value;
    end;

    // thesis_path
    Arr := JSON.FindValue('thesis_path') as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(AMapping.ThesisPath, Arr.Count);
      for I := 0 to Arr.Count - 1 do
        AMapping.ThesisPath[I] := Arr.Items[I].Value;
    end;

    // expression_policy
    Val := JSON.FindValue('expression_policy');
    if Val <> nil then
      AMapping.ExpressionPolicy := Val.Value
    else
      AMapping.ExpressionPolicy := 'explicit';

    // causal_primitives (medium+)
    Arr := JSON.FindValue('causal_primitives') as TJSONArray;
    if Arr <> nil then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I] as TJSONObject;
        Prim := Default(TCausalPrimitive);
        Val := Item.FindValue('prim_id');
        if Val <> nil then Prim.PrimId := Val.Value;
        Val := Item.FindValue('prim_type');
        if Val <> nil then Prim.PrimType := Val.Value;
        Val := Item.FindValue('subject');
        if Val <> nil then Prim.Subject := Val.Value;
        Val := Item.FindValue('operator');
        if Val <> nil then Prim.Operator := Val.Value;
        Val := Item.FindValue('object');
        if Val <> nil then Prim.Object_ := Val.Value;
        Val := Item.FindValue('source_ref');
        if Val <> nil then Prim.SourceRef := Val.Value;
        Val := Item.FindValue('description');
        if Val <> nil then Prim.Description := Val.Value;
        Prim.SortOrder := I;
        SetLength(AMapping.CausalPrimitives, Length(AMapping.CausalPrimitives) + 1);
        AMapping.CausalPrimitives[High(AMapping.CausalPrimitives)] := Prim;
      end;
    end;

    // required_relations (high)
    Arr := JSON.FindValue('required_relations') as TJSONArray;
    if Arr <> nil then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I] as TJSONObject;
        Rel := Default(TTheoryRelation);
        Rel.RelCategory := 'required';
        Val := Item.FindValue('rel_id');
        if Val <> nil then Rel.RelId := Val.Value;
        Val := Item.FindValue('rel_type');
        if Val <> nil then Rel.RelType := Val.Value;
        Val := Item.FindValue('from');
        if Val <> nil then Rel.FromConcept := Val.Value;
        Val := Item.FindValue('to');
        if Val <> nil then Rel.ToConcept := Val.Value;
        Val := Item.FindValue('description');
        if Val <> nil then Rel.Description := Val.Value;
        SetLength(AMapping.RequiredRelations, Length(AMapping.RequiredRelations) + 1);
        AMapping.RequiredRelations[High(AMapping.RequiredRelations)] := Rel;
      end;
    end;

    // forbidden_relations (high)
    Arr := JSON.FindValue('forbidden_relations') as TJSONArray;
    if Arr <> nil then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I] as TJSONObject;
        Rel := Default(TTheoryRelation);
        Rel.RelCategory := 'forbidden';
        Val := Item.FindValue('id');
        if Val <> nil then Rel.RelId := Val.Value;
        Val := Item.FindValue('type');
        if Val <> nil then Rel.RelType := Val.Value;
        Val := Item.FindValue('subject_pattern');
        if Val <> nil then Rel.SubjectPattern := Val.Value;
        Val := Item.FindValue('relation');
        if Val <> nil then Rel.Relation := Val.Value;
        Val := Item.FindValue('object_pattern');
        if Val <> nil then Rel.ObjectPattern := Val.Value;
        Val := Item.FindValue('source');
        if Val <> nil then Rel.Source := Val.Value;
        Val := Item.FindValue('description');
        if Val <> nil then Rel.Description := Val.Value;
        SetLength(AMapping.ForbiddenRelations, Length(AMapping.ForbiddenRelations) + 1);
        AMapping.ForbiddenRelations[High(AMapping.ForbiddenRelations)] := Rel;
      end;
    end;

    // non_negotiable_principles
    Arr := JSON.FindValue('non_negotiable_principles') as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(AMapping.NonNegotiablePrinciples, Arr.Count);
      for I := 0 to Arr.Count - 1 do
        AMapping.NonNegotiablePrinciples[I] := Arr.Items[I].Value;
    end;

    // allowed_translations
    Arr := JSON.FindValue('allowed_translations') as TJSONArray;
    if Arr <> nil then
    begin
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I] as TJSONObject;
        Trans := Default(TAllowedTranslation);
        Val := Item.FindValue('from');
        if Val <> nil then Trans.FromExpr := Val.Value;
        Val := Item.FindValue('to');
        if Val <> nil then Trans.ToExpr := Val.Value;
        Val := Item.FindValue('platform');
        if Val <> nil then Trans.Platform := Val.Value;
        SetLength(AMapping.AllowedTranslations, Length(AMapping.AllowedTranslations) + 1);
        AMapping.AllowedTranslations[High(AMapping.AllowedTranslations)] := Trans;
      end;
    end;

    Result := True;
  finally
    JSON.Free;
  end;
end;

class function TTheoryWeaveService.MatchPattern(const APattern, AValue: string): Boolean;
begin
  // Simple glob matching: * matches any substring
  if APattern = '*' then
    Result := True
  else if APattern.Contains('*') then
  begin
    if APattern.StartsWith('*') and APattern.EndsWith('*') then
      Result := AValue.Contains(APattern.Replace('*', ''))
    else if APattern.StartsWith('*') then
      Result := AValue.EndsWith(APattern.Replace('*', ''))
    else if APattern.EndsWith('*') then
      Result := AValue.StartsWith(APattern.Replace('*', ''))
    else
      Result := AValue.Contains(APattern.Replace('*', ''))
  end
  else
    Result := AValue.Contains(APattern);
end;

end.
