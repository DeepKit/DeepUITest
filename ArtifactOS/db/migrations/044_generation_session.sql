-- ArtifactOS AB dual-track generation session
-- Stores outline racing results + AB generation session with judge/selection flow.
--
-- Flow: 3 outlines → score → pick top 2 → generate A+B → judge qualification → select winner
-- Retry: if both A and B fail qualification, generate from outline C automatically.

begin;

-- 1. Generation session — one per AB generation attempt
create table if not exists artifactos.generation_session (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  artifact_id uuid not null references artifactos.artifact(id),
  contract_id uuid not null references artifactos.artifact_contract(id),

  -- Track version pointers (FK to artifact_version)
  track_a_version_id uuid references artifactos.artifact_version(id),
  track_b_version_id uuid references artifactos.artifact_version(id),
  track_c_version_id uuid references artifactos.artifact_version(id),   -- retry track

  -- Judge results (JSONB)
  qualification_a jsonb not null default '{}'::jsonb,   -- {passed, score, dimensions:{}, issues:[]}
  qualification_b jsonb not null default '{}'::jsonb,
  qualification_c jsonb not null default '{}'::jsonb,   -- retry track

  -- Selection result (JSONB)
  selection_result jsonb not null default '{}'::jsonb,  -- {winner, reasoning, scores:{a:,b:}, detail:{}}

  -- Final outcome
  winner_track text check (winner_track in ('A', 'B', 'C')),
  winner_version_id uuid references artifactos.artifact_version(id),
  runner_up_version_id uuid references artifactos.artifact_version(id),

  -- Status lifecycle:
  --   created → outlining → generating → qualifying → selecting → completed
  --   qualifying → failed (both A+B failed, and C retry also failed)
  --   any → abandoned (human intervention)
  status text not null default 'created'
    check (status in (
      'created',      -- session just created
      'outlining',    -- generating 3 outlines
      'generating',   -- generating AB full text
      'qualifying',   -- judge running qualification
      'selecting',    -- AB comparison in progress
      'completed',    -- winner selected and sealed
      'failed',       -- all tracks failed qualification
      'abandoned'     -- human abandoned
    )),

  -- Generation metadata (model, tokens, timing, etc.)
  generation_meta jsonb not null default '{}'::jsonb,

  created_by uuid not null default '00000000-0000-0000-0000-000000000001',
  updated_by uuid not null default '00000000-0000-0000-0000-000000000001',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_gen_session_artifact
  on artifactos.generation_session (artifact_id, status);
create index if not exists idx_gen_session_contract
  on artifactos.generation_session (contract_id);

-- 2. Generation outline — stores the 3 outline candidates per session
create table if not exists artifactos.generation_outline (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default '00000000-0000-0000-0000-000000000001',
  session_id uuid not null references artifactos.generation_session(id),

  track_label text not null check (track_label in ('A', 'B', 'C')),
  angle_name text not null,          -- e.g. 'pain_driven', 'theory_intervention', 'case_narrative'
  outline_text text not null,        -- raw LLM output
  outline_json jsonb not null default '{}'::jsonb,   -- structured: {title, sections[], conclusion_direction}

  score double precision not null default 0,
  score_detail jsonb not null default '{}'::jsonb,   -- per-dimension scores
  rank_no integer,
  selected boolean not null default false,            -- true for top 2 that enter AB generation

  created_at timestamptz not null default now()
);

create index if not exists idx_gen_outline_session
  on artifactos.generation_outline (session_id, track_label);

-- 3. Guard: generation_session cannot be completed without a winner version
create or replace function artifactos.fn_guard_generation_session_winner()
returns trigger language plpgsql as $$
begin
  if new.status = 'completed' and new.winner_version_id is null then
    raise exception 'generation_session cannot reach completed without a winner_version_id';
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_generation_session_winner on artifactos.generation_session;
create trigger trg_guard_generation_session_winner
  before insert or update on artifactos.generation_session
  for each row execute function artifactos.fn_guard_generation_session_winner();

-- 4. Updated_at auto-touch
create or replace function artifactos.fn_touch_generation_session()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_touch_generation_session on artifactos.generation_session;
create trigger trg_touch_generation_session
  before update on artifactos.generation_session
  for each row execute function artifactos.fn_touch_generation_session();

commit;
