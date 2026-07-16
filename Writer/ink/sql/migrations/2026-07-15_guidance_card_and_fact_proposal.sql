-- P0-5: Guidance cards + Fact proposals (real iFLYTEK, one-step).
-- Idempotent.

CREATE TABLE IF NOT EXISTS writing_guidance_cards (
    guidance_card_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    scene_id INTEGER,
    card_type TEXT NOT NULL CHECK (card_type IN (
        'continuity_warning','character_pressure','foreshadow_reminder',
        'pacing_adjustment','fact_contradiction'
    )),
    trigger_context TEXT NOT NULL,
    guidance_text TEXT NOT NULL,
    model_name TEXT NOT NULL,
    prompt_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','dismissed','applied','stale')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_guidance_cards_chapter
    ON writing_guidance_cards(project_id, chapter_id, status);

CREATE TABLE IF NOT EXISTS writing_fact_proposals (
    fact_proposal_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    scene_id INTEGER,
    proposed_fact TEXT NOT NULL,
    fact_type TEXT NOT NULL CHECK (fact_type IN (
        'character_state','world_rule','event','causality','timeline'
    )),
    source_text TEXT NOT NULL,
    source_revision_id INTEGER,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    status TEXT NOT NULL DEFAULT 'proposed'
        CHECK (status IN ('proposed','confirmed','rejected','superseded','stale')),
    model_name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (source_revision_id)
        REFERENCES writing_scene_revisions(scene_revision_id)
);
CREATE INDEX IF NOT EXISTS idx_fact_proposals_status
    ON writing_fact_proposals(project_id, status);
