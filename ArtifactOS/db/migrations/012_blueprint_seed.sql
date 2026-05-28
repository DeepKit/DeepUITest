-- ArtifactOS ArtifactBlueprint seed Phase 1A
-- Target: artifactos_test first, then artifactos production after review.
-- Defines the three canonical blueprints: Zhihu longform, WeChat article, Xiaohongshu note.
-- Blueprint FK references are intentionally loose for Phase 1A.

begin;

-- 1. Blueprint registry table
create table if not exists artifactos.artifact_blueprint (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  blueprint_code text not null,
  artifact_type text not null,
  platform_id text not null,
  version integer not null default 1,
  required_parts jsonb not null default '[]'::jsonb,
  optional_parts jsonb not null default '[]'::jsonb,
  assembly_rules jsonb not null default '{}'::jsonb,
  gate_rules jsonb not null default '{}'::jsonb,
  rendition_rules jsonb not null default '{}'::jsonb,
  publication_package_rules jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status in ('active','draft','retired')),
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, blueprint_code, version)
);

-- 2. Zhihu longform article blueprint
insert into artifactos.artifact_blueprint (blueprint_code, artifact_type, platform_id,
  required_parts, optional_parts, assembly_rules, gate_rules, rendition_rules, publication_package_rules)
values ('zhihu_article_v1', 'zhihu_longform', 'zhihu',
  '["title","body","tags"]'::jsonb,
  '["cover_image","summary","topic_entry"]'::jsonb,
  '{}'::jsonb,
  '{"part_gate":["title","body","tags"],"assembly_gate":"title non-empty; body paragraph >= 3; tags >= 1","artifact_gate":"ES+SES+NES+SourceFidelity","package_gate":"zhihu required + idempotency + account"}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb)
on conflict (tenant_id, blueprint_code, version) do nothing;

-- 3. WeChat article blueprint
insert into artifactos.artifact_blueprint (blueprint_code, artifact_type, platform_id,
  required_parts, optional_parts, assembly_rules, gate_rules, rendition_rules, publication_package_rules)
values ('wechat_article_v1', 'wechat_article', 'wechat',
  '["title","body","cover_image"]'::jsonb,
  '["summary","author_signature","guide_follow","read_original_link"]'::jsonb,
  '{}'::jsonb,
  '{"part_gate":["title","body","cover_image"],"assembly_gate":"title <= 64 chars; body WeChat compatible","artifact_gate":"ES+SES+NES+SourceFidelity+PlatformRisk","package_gate":"wechat required + rich media"}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb)
on conflict (tenant_id, blueprint_code, version) do nothing;

-- 4. Xiaohongshu note blueprint
insert into artifactos.artifact_blueprint (blueprint_code, artifact_type, platform_id,
  required_parts, optional_parts, assembly_rules, gate_rules, rendition_rules, publication_package_rules)
values ('xhs_note_v1', 'xhs_note', 'xiaohongshu',
  '["cover_image","carousel_image","caption","hashtag_set"]'::jsonb,
  '["video"]'::jsonb,
  '{}'::jsonb,
  '{"part_gate":["cover_image","carousel_image","caption","hashtag_set"],"assembly_gate":"image >= 1; caption <= 1000 chars; hashtag >= 1","artifact_gate":"ES+SES+NES+SourceFidelity+VisualCoherence","package_gate":"xhs required + image size + account"}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb)
on conflict (tenant_id, blueprint_code, version) do nothing;

-- 5. Back-link: artifact.blueprint_id FK to artifact_blueprint
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema='artifactos' and table_name='artifact' and column_name='blueprint_id') then
    alter table artifactos.artifact add column blueprint_id uuid references artifactos.artifact_blueprint(id);
  end if;
end $$;

commit;