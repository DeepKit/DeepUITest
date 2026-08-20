# DeepFrames workers

Phase 1 does not run external workers. The desktop host owns DB1/DB2 access and validates the application shell, configuration, DB2 migration, source import, and local `preprocess` job flow.

Future worker protocol v0 uses a per-job working directory with:

- `request.json` — versioned request written by the Delphi host.
- `progress.json` — heartbeat/progress summary written by the worker.
- `result.json` — versioned result manifest read by the Delphi host.

Workers must not read DB1/DB2 directly and must not read DeepFrames business tables. They communicate only through the file contract and process status.
