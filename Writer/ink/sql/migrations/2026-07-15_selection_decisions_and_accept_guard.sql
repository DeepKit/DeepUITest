-- P0-2: Selection decisions + Accept guard.
-- Idempotent (IF NOT EXISTS). Mirrors the append in schema.sql.

CREATE TABLE IF NOT EXISTS writing_selection_decisions (
    selection_decision_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    generation_round_id INTEGER NOT NULL,
    selected_branch_id INTEGER NOT NULL,
    decision_type TEXT NOT NULL CHECK (decision_type IN (
        'auto_selected','human_override','minority_champion'
    )),
    evidence_json TEXT NOT NULL,
    actor TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (generation_round_id)
        REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE,
    FOREIGN KEY (selected_branch_id)
        REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_selection_decisions_round
    ON writing_selection_decisions(generation_round_id);
