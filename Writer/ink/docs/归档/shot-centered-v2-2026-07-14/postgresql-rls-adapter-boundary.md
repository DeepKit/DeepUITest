# PostgreSQL / RLS Adapter Boundary（Shot 中心历史基线）

> **Status**: adapter boundary implemented on 2026-07-11; the current production
> runtime remains SQLite until a PostgreSQL schema migration and live RLS
> integration suite are completed.
>
> **Scene-first amendment (2026-07-14)**: references below to shot locks and
> shot canonical rows describe the current implementation baseline. The target
> authority and lock scope is Scene Revision / Chapter Snapshot; internal shots
> may retain local work locks but must not become a second canonical text source.

## Current Authority

- SQLite is the only implemented database backend.
- `ink.database.connect()` is the application entry point for file-backed runtime connections.
- `ink.schema.initialize_schema()` is the schema initialization boundary for local SQLite tests and tools.
- Application code may use `sqlite3.Connection.execute()` today, but SQL must stay static and parameterized; dynamic table names and ORM access remain forbidden by lint.

## Adapter Contract

`ink.database` now provides `DBAdapter`, `SQLiteAdapter`,
`PostgreSQLAdapter`, mapping/index compatible rows, safe qmark placeholder
translation, transaction-local auth context, and advisory shot locks. These
runtime semantics must remain preserved before PostgreSQL can replace SQLite:

- `connect(...)` returns rows addressable by column name, matching current `sqlite3.Row` behavior.
- `transaction(conn)` commits on normal exit and rolls back on exception.
- Foreign key and integrity checks must remain enabled at the database layer.
- All business timestamps still come from `now_utc_iso()`; database-local time functions must not become business time sources.
- Text truth-source access remains through `TextRepository` and `v_current_text`; PostgreSQL must not create a second write path for canonical text.
- SQL remains explicit and parameterized; no ORM abstraction is introduced as part of the adapter.

## RLS Boundary

SQLite has no database-level RLS. The current isolation model is Python import boundaries, SQL lint, and constrained views.

A PostgreSQL migration may add RLS only at the adapter/session boundary:

- The adapter must set an auth context for each transaction, for example project/session identifiers used by RLS policies.
- Application orchestrators must not manually inject tenant predicates as a replacement for RLS.
- RLS policies must protect project/session scoped tables, human decisions, runtime events, LLM attempts, and canonical text views.
- Tests must prove that a connection scoped to one project cannot read or mutate another project's rows.

## Concurrency Boundary

SQLite is currently treated as a single-writer local runtime. A PostgreSQL adapter may introduce concurrent workers only if it preserves shot/run consistency:

- Same `shot_id` and `run_id` work must be serialized.
- PostgreSQL may use `pg_advisory_xact_lock(hashtext(shot_id || ':' || run_id))` inside `transaction(conn)`.
- Different shots may run concurrently only when they do not share a mutable counter or canonical text row.
- Soft gate counters remain DB-authoritative and must use atomic increments.

## SQL Dialect Boundary

The schema is SQLite-first today. PostgreSQL migration must have an explicit translation layer for:

- `INTEGER PRIMARY KEY` identity semantics.
- Partial unique indexes.
- JSON validation and JSON path checks.
- Triggers that enforce jury self-judging and current text invariants.
- Views such as `v_current_text`.
- Conflict/upsert syntax.

No business module should contain PostgreSQL-only SQL until the adapter boundary and migration tests exist.

## Minimum Migration Tests

Before enabling a PostgreSQL backend, tests must cover:

- Schema migration creates all production tables, indexes, triggers, and views.
- `connect()` returns mapping-style rows.
- `transaction()` commit and rollback semantics match SQLite.
- RLS denies cross-project reads and writes.
- Advisory lock behavior serializes same-shot work.
- Existing invariant traceability tests pass unchanged against the adapter.

Current automated evidence:

- Fake-driver adapter tests prove mapping rows, placeholder translation,
  commit/rollback, transaction-local auth context, and advisory lock SQL.
- Existing SQLite boundary tests continue to prove mapping rows and transaction
  parity.
- Still required: PostgreSQL schema translation/migration plus live-server RLS,
  advisory-lock concurrency, and invariant traceability integration tests.
