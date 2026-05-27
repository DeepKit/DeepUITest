-- ArtifactOS rendition + asset_file Phase 1A draft
-- Target: artifactos_test first, then progee_db.artifactos after review.
-- publication_package was created in 006 with relaxed FK; this migration
-- hardens it by adding FK references to artifact, artifact_version, rendition,
-- and quality_snapshot (when they exist).

begin;

-- 1. AssetFile — physical file embedded in an artifact
create table if not exists artifactos.asset_file (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid references artifactos.artifact(id),
  artifact_part_id uuid references artifactos.artifact_part(id),
  file_role text not null,
  file_path text not null,
  mime_type text,
  file_size_bytes bigint,
  checksum text,
  width integer,
  height integer,
  duration_ms integer,
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_asset_file_artifact
  on artifactos.asset_file (artifact_id, artifact_part_id);

-- 2. Rendition — platform-specific rendered version
create table if not exists artifactos.rendition (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid not null references artifactos.artifact(id),
  artifact_version_id uuid references artifactos.artifact_version(id),
  target_platform_id text not null default 'zhihu',
  rendition_type text not null,
  rendered_payload jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_rendition_artifact
  on artifactos.rendition (artifact_id, artifact_version_id, status);

-- 3. Harden publication_package — add FK columns that 006 deferred
-- These columns may already exist; the ADD COLUMN IF NOT EXISTS
-- syntax is not natively supported in PG 15, so we use a helper block.
do $$
begin
  -- Add FK target columns if they don't exist yet
  if not exists (select 1 from information_schema.columns where table_schema='artifactos' and table_name='publication_package' and column_name='artifact_id') then
    alter table artifactos.publication_package add column artifact_id uuid references artifactos.artifact(id);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='artifactos' and table_name='publication_package' and column_name='artifact_version_id') then
    alter table artifactos.publication_package add column artifact_version_id uuid references artifactos.artifact_version(id);
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='artifactos' and table_name='publication_package' and column_name='rendition_id') then
    alter table artifactos.publication_package add column rendition_id uuid references artifactos.rendition(id);
  end if;
  if exists (select 1 from information_schema.columns where table_schema='artifactos' and table_name='publication_package' and column_name='representation_id') then
    alter table artifactos.publication_package drop column representation_id;
  end if;

  -- Add extra guard indexes
  if not exists (select 1 from pg_indexes where schemaname='artifactos' and tablename='publication_package' and indexname='idx_publication_package_artifact') then
    create index idx_publication_package_artifact on artifactos.publication_package (artifact_id, artifact_version_id);
  end if;
  if not exists (select 1 from pg_indexes where schemaname='artifactos' and tablename='publication_package' and indexname='idx_publication_package_rendition') then
    create index idx_publication_package_rendition on artifactos.publication_package (rendition_id);
  end if;

  -- Harden quality_snapshot FK
  if not exists (select 1 from information_schema.columns where table_schema='artifactos' and table_name='quality_snapshot' and column_name='publication_package_id') then
    alter table artifactos.quality_snapshot add column publication_package_id uuid references artifactos.publication_package(id);
  end if;
end $$;

commit;