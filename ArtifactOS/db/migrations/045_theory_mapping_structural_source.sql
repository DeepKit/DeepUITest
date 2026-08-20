-- ArtifactOS S08 structural source mapping (TheoryWeave v0)
-- Stores theory mappings with causal primitives, required/forbidden relations.
-- Used by: PromptAssembly S08 slot, QualityGate ES-07 + SES-05 fidelity check.
--
-- Design from docs/11 §3.3a + §3.1d

begin;

-- 1. theory_mapping — one per contract's source mapping invocation
create table if not exists artifactos.theory_mapping (
  id              uuid primary key default gen_random_uuid(),
  contract_id     uuid not null references artifactos.artifact_contract(id),
  topic           text not null,
  entry_mode      text not null default 'hotspot_driven',  -- hotspot_driven | theory_driven
  intervention    text not null default 'low',              -- low | medium | high
  mapping_kind    text not null default 'theory',           -- theory | source | mixed

  -- Output fields (populated after LLM mapping)
  mapping_json    jsonb,              -- full structured output (activated_concepts, thesis_path, expression_policy)
  fidelity_score  double precision,   -- 0-100 source fidelity score (populated by quality gate)

  frozen_at       timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists idx_theory_mapping_contract on artifactos.theory_mapping(contract_id);

-- 2. causal_primitive — structured causal building blocks
create table if not exists artifactos.causal_primitive (
  id              uuid primary key default gen_random_uuid(),
  mapping_id      uuid not null references artifactos.theory_mapping(id),
  prim_id         text not null,       -- cp_001 style logical ID (unique within mapping)
  prim_type       text not null,       -- stage | attribute | causation | sequence
  subject         text not null,
  operator        text not null default 'must_pass_through',
  object          text not null,
  source_ref      text,                -- theory source reference
  description     text,
  sort_order      int not null default 0,
  created_at      timestamptz not null default now(),
  unique(mapping_id, prim_id)
);
create index if not exists idx_causal_primitive_mapping on artifactos.causal_primitive(mapping_id);

-- 3. theory_relation — required and forbidden structural relations
create table if not exists artifactos.theory_relation (
  id              uuid primary key default gen_random_uuid(),
  mapping_id      uuid not null references artifactos.theory_mapping(id),
  rel_id          text,                -- rr_001 / fr_001 style logical ID
  rel_category    text not null,       -- required | forbidden
  rel_type        text not null,       -- stage | attribute | causation | sequence | no_override | no_reinterpret | no_omit
  from_concept    text,                -- subject / from (required relations)
  to_concept      text,                -- object / to (required relations)
  subject_pattern text,                -- glob pattern (forbidden relations)
  relation        text,                -- relation verb (forbidden: overrides / reinterprets / omits)
  object_pattern  text,                -- glob pattern (forbidden relations)
  source          text,                -- originating principle ID
  description     text,
  immutable       boolean not null default false,  -- from core principles with immutable:true
  created_at      timestamptz not null default now()
);
create index if not exists idx_theory_relation_mapping on artifactos.theory_relation(mapping_id);
create index if not exists idx_theory_relation_category on artifactos.theory_relation(mapping_id, rel_category);

-- 4. allowed_translation — platform expression adaptation rules
create table if not exists artifactos.allowed_translation (
  id              uuid primary key default gen_random_uuid(),
  mapping_id      uuid not null references artifactos.theory_mapping(id),
  from_expr       text not null,       -- original expression
  to_expr         text not null,       -- adapted expression
  platform        text not null,       -- target platform
  created_at      timestamptz not null default now()
);
create index if not exists idx_allowed_translation_mapping on artifactos.allowed_translation(mapping_id);

-- 5. theory_resource — raw theory material used to generate mapping
create table if not exists artifactos.theory_resource (
  id              uuid primary key default gen_random_uuid(),
  mapping_id      uuid not null references artifactos.theory_mapping(id),
  resource_type   text not null,       -- core_principle | explanation_model | causal_mechanism | application_case
  content         text not null,
  sort_order      int not null default 0,
  created_at      timestamptz not null default now()
);
create index if not exists idx_theory_resource_mapping on artifactos.theory_resource(mapping_id);

-- 6. source_fidelity_check — structural fidelity gate result
create table if not exists artifactos.source_fidelity_check (
  id              uuid primary key default gen_random_uuid(),
  mapping_id      uuid not null references artifactos.theory_mapping(id),
  artifact_id     text,
  check_type      text not null default 'structure',  -- structure | semantic
  consistency     text not null default 'pass',       -- pass | warn | fail
  missing_required text[],             -- array of missing required relation IDs
  violated_forbidden text[],           -- array of violated forbidden relation IDs
  out_of_bounds   text[],              -- array of out-of-bounds translation IDs
  score           double precision,
  evidence        jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists idx_source_fidelity_mapping on artifactos.source_fidelity_check(mapping_id);

commit;
