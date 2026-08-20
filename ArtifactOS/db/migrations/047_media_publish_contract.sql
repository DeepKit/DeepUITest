-- L3-68: media_publish contract schema
-- Creates media_publish.publish_task table for handoff from ArtifactOS to PublishingRuntime.
-- ArtifactOS writes intent here; PublishingRuntime (browser automation) consumes and acts.

begin;

-- Create schema if not exists
create schema if not exists media_publish;

-- Publish task contract — one row per publish intent
create table if not exists media_publish.publish_task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- Reference back to ArtifactOS publication package
  publication_package_id uuid not null references artifactos.publication_package(id),

  -- Target platform/account (determines which browser session to use)
  platform_id text not null,    -- 'zhihu' | 'wechat' | 'xiaohongshu' | 'weibo'
  account_id text not null,     -- 'main' | 'secondary' etc.

  -- Mode determines behavior
  mode text not null check (mode in (
    'manual_review',   -- open in browser, do not click publish
    'auto_publish',    -- fully automated, click publish
    'draft_only',      -- save as draft only
    'dry_run'          -- log only, no browser action
  )),

  -- Content to publish
  title text not null,
  body_md text not null,           -- markdown body
  asset_files jsonb default '[]'::jsonb,  -- image/video paths

  -- Idempotency
  idempotency_key text not null unique,

  -- Lifecycle
  status text not null default 'pending' check (status in (
    'pending',            -- task created, not yet picked up
    'submitted',          -- sent to browser, awaiting result
    'draft_saved',        -- saved as platform draft (not yet published)
    'published',          -- successfully published
    'failed_recoverable', -- failed, can retry
    'failed_final',       -- failed, cannot retry
    'unknown',            -- state could not be confirmed
    'canceled'            -- user/system canceled
  )),

  -- Result fields (filled by PublishingRuntime)
  finality text check (finality in ('confirmed', 'tentative', 'unknown')),
  external_draft_id text,
  published_url text,
  evidence jsonb default '[]'::jsonb,  -- screenshot paths etc.

  -- Error reporting
  error_code text,
  error_message text,

  -- Recovery support
  recovery_attempt_count integer not null default 0,
  last_recovery_at timestamptz,

  -- Timestamps
  picked_up_at timestamptz,
  submitted_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_pub_task_status
  on media_publish.publish_task (status, created_at);
create index if not exists idx_pub_task_platform
  on media_publish.publish_task (platform_id, account_id, status);
create index if not exists idx_pub_task_package
  on media_publish.publish_task (publication_package_id);

-- Auto-update updated_at
create or replace function media_publish.fn_touch_publish_task()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_touch_publish_task on media_publish.publish_task;
create trigger trg_touch_publish_task
  before update on media_publish.publish_task
  for each row execute function media_publish.fn_touch_publish_task();

commit;
