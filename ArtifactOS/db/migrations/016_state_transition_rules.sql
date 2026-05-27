-- ArtifactOS state_transition_rule seed Phase 1A draft
-- Target:  artifactos_test first, then progee_db.artifactos after review.
-- Rules define valid transitions for the three-axis state machine (docs/06).
-- NOT all rules from docs/06 are seeded here — only the Phase 1A minimum set.

begin;

create table if not exists artifactos.state_transition_rule (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  rule_code text not null,
  target_type text not null,                     -- e.g.  SubStudioExecutionTask / Artifact / PublicationPackage
  from_state text not null,                     -- composite  pipeline_status x quality_status x publish_status
  to_state text not null,
  trigger_condition text not null,
  actor text not null default 'system' check (actor in ('system','human','amy','gate','publishing_adapter')),
  side_effect text,
  phase text not null default 'Phase1' check (phase in ('Phase1','Phase2','Phase3','Phase4','Phase5','Phase6')),
  is_active boolean not null default true,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, rule_code)
);

-- Seed Phase 1A minimum transitions

-- SubStudioExecutionTask  normal progression
insert into artifactos.state_transition_rule (rule_code, target_type, from_state, to_state, trigger_condition, actor, side_effect)
values
('task_pending_to_contracting', 'SubStudioExecutionTask', 'pending x pending x pending', 'contracting x pending x pending', 'Case activated + StrategyUnit assigned', 'system', 'spec_status=clarifying'),
('task_contracting_to_drafting',  'SubStudioExecutionTask', 'contracting x pending x pending', 'drafting x pending x pending',   'ContractCandidate ready',        'amy',    null),
('task_drafting_to_reviewing',    'SubStudioExecutionTask', 'drafting x pending x pending',   'reviewing x es_checking x pending',  'Draft generated',               'system', 'quality_status=es_checking'),
('task_reviewing_to_approved',    'SubStudioExecutionTask', 'reviewing x passed x pending',   'approved x passed x pending',     'Gate passed',                   'gate',   null),
('task_approved_to_publishing',   'SubStudioExecutionTask', 'approved x passed x pending',    'publishing x passed x publishing',  'PublicationPackage ready',      'system', 'publish_status=publishing'),
('task_publishing_to_published',  'SubStudioExecutionTask', 'publishing x passed x publishing', 'published x passed x published', 'PublicationAttempt confirmed',  'publishing_adapter', null),
('task_published_to_collecting',  'SubStudioExecutionTask', 'published x passed x published', 'collecting x passed x published', 'Data collection window',        'system', null),
('task_collecting_to_completed',  'SubStudioExecutionTask', 'collecting x passed x published', 'completed x passed x published', 'Feedback loop closed',          'system', null)
on conflict (tenant_id, rule_code) do nothing;

-- SubStudioExecutionTask  exception / governance
insert into artifactos.state_transition_rule (rule_code, target_type, from_state, to_state, trigger_condition, actor, side_effect)
values
('task_any_to_frozen',       'SubStudioExecutionTask', '* x * x *', 'frozen x * x *',             'FREEZE_OR_REDLINE',             'gate',   'human_override=true'),
('task_frozen_to_pending',   'SubStudioExecutionTask', 'frozen x * x *', 'pending x pending x pending',    'Human unseal',                  'human',  'frozen flag removed'),
('task_any_to_waiting_human','SubStudioExecutionTask', '* x * x *', 'waiting_human x * x *',       'human_override=true',           'system', null),
('task_any_to_abandoned',    'SubStudioExecutionTask', '* x * x *', 'abandoned x * x *',           'Human decision to terminate',   'human',  null),
('task_draft_to_stored',     'SubStudioExecutionTask', '* x * x *', 'stored x * x skipped',       'BoundaryDecision = draft_only',  'system', null)
on conflict (tenant_id, rule_code) do nothing;

-- PublicationPackage  transitions
insert into artifactos.state_transition_rule (rule_code, target_type, from_state, to_state, trigger_condition, actor, side_effect)
values
('pkg_draft_to_preflight','PublicationPackage','* x draft x *','* x preflight x *','Package assembled','system',null),
('pkg_preflight_to_queued','PublicationPackage','* x preflight x *','* x queued x *','PackageGate passed + QualitySnapshot bound','gate',null),
('pkg_queued_to_published','PublicationPackage','* x queued x *','* x published x *','PublicationAttempt succeeded','publishing_adapter','publication_url set'),
('pkg_any_to_failed',      'PublicationPackage','* x * x *','* x failed x *','PublicationAttempt failed_final','publishing_adapter','rollback_path verified'),
('pkg_any_to_recalled',    'PublicationPackage','* x * x *','* x recalled x *','Human recall decision','human','publication withdrawn'),
('pkg_any_to_held',        'PublicationPackage','* x * x *','* x held x *','Artifact frozen','system',null),
('pkg_held_to_superseded', 'PublicationPackage','* x held x *','* x superseded x *','Replaced by new Package','system',null)
on conflict (tenant_id, rule_code) do nothing;

-- Artifact  transitions
insert into artifactos.state_transition_rule (rule_code, target_type, from_state, to_state, trigger_condition, actor, side_effect)
values
('art_planned_to_drafting',  'Artifact','planned x * x *','drafting x * x *','Generation initiated','amy',null),
('art_drafting_to_assembled','Artifact','drafting x * x *','assembled x * x *','Parts assembled','system',null),
('art_assembled_to_gate',    'Artifact','assembled x * x *','gate_checking x * x *','QualityRun started','gate',null),
('art_gate_to_sealed',       'Artifact','gate_checking x * x *','sealed x * x *','QualitySnapshot sealed','gate','seal_id set'),
('art_sealed_to_published',  'Artifact','sealed x * x *','published x * x *','PublicationPackage published','publishing_adapter',null),
('art_any_to_frozen',        'Artifact','* x * x *','frozen x * x *','Redline or Freeze','gate','human_override=true'),
('art_frozen_to_rework',     'Artifact','frozen x * x *','rework x * x *','Human unseal','human',null),
('art_any_to_recalled',      'Artifact','* x * x *','recalled x * x *','Publication recalled','human',null)
on conflict (tenant_id, rule_code) do nothing;

commit;