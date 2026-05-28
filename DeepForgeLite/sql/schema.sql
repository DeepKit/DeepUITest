-- DeepDevLite SQLite Schema
-- Version: 1.0.0
-- Date: 2026-02-20

-- Contracts table
CREATE TABLE IF NOT EXISTS contracts (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    language TEXT,
    purpose TEXT,
    source_file TEXT,
    source_code TEXT,
    status TEXT DEFAULT 'draft',
    created_at TEXT,
    confirmed_at TEXT,
    sealed_at TEXT,
    rework_count INTEGER DEFAULT 0,
    extra TEXT
);

-- Tasks table
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    contract_id TEXT,
    title TEXT,
    description TEXT,
    scenario_id TEXT,
    status TEXT DEFAULT 'pending',
    artifact_type TEXT,
    artifact_path TEXT,
    input_spec TEXT,
    output_spec TEXT,
    test_result TEXT,
    created_at TEXT,
    updated_at TEXT,
    extra TEXT
);

-- Test results table
CREATE TABLE IF NOT EXISTS test_results (
    id TEXT PRIMARY KEY,
    contract_id TEXT,
    task_id TEXT,
    scenario_id TEXT,
    passed INTEGER DEFAULT 0,
    detail TEXT,
    execution_ms INTEGER,
    raw_output TEXT,
    created_at TEXT
);

-- Reports table
CREATE TABLE IF NOT EXISTS reports (
    id TEXT PRIMARY KEY,
    contract_id TEXT,
    project_name TEXT,
    source_file TEXT,
    language TEXT,
    ai_model TEXT,
    seal_hash TEXT,
    is_sealed INTEGER DEFAULT 0,
    created_at TEXT,
    extra TEXT
);

-- Seal records table
CREATE TABLE IF NOT EXISTS seal_records (
    id TEXT PRIMARY KEY,
    report_id TEXT,
    source_file TEXT,
    source_hash TEXT,
    seal_hash TEXT,
    model_used TEXT,
    retry_count INTEGER,
    contract_file TEXT,
    sealed_at TEXT
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_contracts_status ON contracts(status);
CREATE INDEX IF NOT EXISTS idx_tasks_contract ON tasks(contract_id);
CREATE INDEX IF NOT EXISTS idx_test_results_contract ON test_results(contract_id);
CREATE INDEX IF NOT EXISTS idx_reports_sealed ON reports(is_sealed);
