-- P0-4: Pareto frontier + minority champion for literary selection.
-- Idempotent.

CREATE TABLE IF NOT EXISTS writing_pareto_frontier (
    pareto_entry_id INTEGER PRIMARY KEY,
    generation_round_id INTEGER NOT NULL,
    branch_id INTEGER NOT NULL,
    dimension_scores_json TEXT NOT NULL,
    is_dominated INTEGER NOT NULL DEFAULT 0 CHECK (is_dominated IN (0,1)),
    created_at TEXT NOT NULL,
    FOREIGN KEY (generation_round_id)
        REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_id)
        REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_pareto_frontier_round
    ON writing_pareto_frontier(generation_round_id, is_dominated);

CREATE TABLE IF NOT EXISTS writing_minority_champions (
    champion_id INTEGER PRIMARY KEY,
    generation_round_id INTEGER NOT NULL,
    branch_id INTEGER NOT NULL,
    champion_model TEXT NOT NULL,
    champion_dimension TEXT NOT NULL,
    score INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (generation_round_id)
        REFERENCES writing_chapter_generation_rounds(generation_round_id) ON DELETE CASCADE,
    FOREIGN KEY (branch_id)
        REFERENCES writing_chapter_candidate_branches(branch_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_minority_champions_round
    ON writing_minority_champions(generation_round_id);
