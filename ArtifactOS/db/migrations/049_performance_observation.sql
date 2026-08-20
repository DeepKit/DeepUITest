-- L4-74: Performance observation aggregation layer
-- Aggregates signal_event raw signals into per-artifact performance snapshots.
-- One row per (artifact_id, platform, observation_window).

begin;

-- Performance observation: aggregated metrics per artifact per platform
create table if not exists artifactos.performance_observation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',

  -- What is being observed
  artifact_id uuid not null references artifactos.artifact(id),
  artifact_version_id uuid references artifactos.artifact_version(id),
  publication_package_id uuid references artifactos.publication_package(id),

  -- Platform and account context
  platform text not null,          -- 'zhihu' | 'wechat' | 'xiaohongshu' | 'weibo'
  account_id text not null default 'main',

  -- Observation window
  observation_window text not null check (observation_window in (
    '24h', '48h', '72h', '7d', '30d', 'cumulative'
  )),
  observed_at timestamptz not null default now(),

  -- Core metrics (aggregated from signal_event)
  views integer not null default 0,
  likes integer not null default 0,
  favorites integer not null default 0,
  comments integer not null default 0,
  shares integer not null default 0,
  follows integer not null default 0,

  -- Computed rates
  engagement_rate double precision not null default 0,  -- (likes+faves+comments+shares) / views
  conversion_rate double precision not null default 0,  -- follows / views

  -- Platform benchmarks (population averages for same content type)
  benchmark_views double precision,
  benchmark_engagement double precision,

  -- Relative performance
  views_vs_avg double precision,      -- views / benchmark_views
  engagement_vs_avg double precision, -- engagement_rate / benchmark_engagement

  -- Signal source
  signal_source text not null default 'manual' check (signal_source in (
    'platform_api',     -- from platform API
    'browser_scrape',   -- from browser automation
    'manual',           -- manually entered
    'estimated'         -- AI estimated (for shadow run)
  )),

  -- Calibration link (for prediction vs actual)
  cognition_trace_id uuid references artifactos.cognition_trace(id),

  -- Metadata
  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_perf_obs_artifact
  on artifactos.performance_observation (artifact_id, platform, observation_window);
create index if not exists idx_perf_obs_package
  on artifactos.performance_observation (publication_package_id);
create index if not exists idx_perf_obs_time
  on artifactos.performance_observation (observed_at desc);

-- Updated_at auto-touch
create or replace function artifactos.fn_touch_performance_observation()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_touch_performance_observation on artifactos.performance_observation;
create trigger trg_touch_performance_observation
  before update on artifactos.performance_observation
  for each row execute function artifactos.fn_touch_performance_observation();

commit;
