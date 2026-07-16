-- P0-3: Scene Contract dual-master review + amendment.
-- Idempotent. Stores reviewer independence evidence for blind audit.

CREATE TABLE IF NOT EXISTS writing_scene_contract_reviews (
    contract_review_id INTEGER PRIMARY KEY,
    scene_contract_id INTEGER NOT NULL,
    reviewer_model TEXT NOT NULL,
    reviewer_family TEXT NOT NULL,
    prompt_hash TEXT NOT NULL,
    blind_context_hash TEXT NOT NULL,
    visible_prior_reviews INTEGER NOT NULL DEFAULT 0 CHECK (visible_prior_reviews IN (0,1)),
    review_order INTEGER NOT NULL,
    verdict TEXT NOT NULL CHECK (verdict IN ('approve','revise','reject')),
    evidence_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (scene_contract_id)
        REFERENCES writing_scene_contracts(scene_contract_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_scene_contract_reviews_contract
    ON writing_scene_contract_reviews(scene_contract_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_scene_contract_review_unique_order
    ON writing_scene_contract_reviews(scene_contract_id, review_order);

CREATE TABLE IF NOT EXISTS writing_scene_contract_amendments (
    amendment_id INTEGER PRIMARY KEY,
    scene_contract_id INTEGER NOT NULL,
    amending_actor TEXT NOT NULL,
    amendment_reason TEXT NOT NULL,
    clause_changes_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (scene_contract_id)
        REFERENCES writing_scene_contracts(scene_contract_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_scene_contract_amendments
    ON writing_scene_contract_amendments(scene_contract_id, created_at);
