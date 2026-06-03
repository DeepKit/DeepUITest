# DeepFrames tests

Phase 1 verification starts with build and manual functional smoke checks:

1. `cmd /c compile_test.bat`
2. Launch `bin/DeepFrames.exe`.
3. Configure DB2 PostgreSQL settings through DeepShell settings.
4. Run DB2 migration.
5. Create a project, import Markdown, run local preprocess.
6. Restart and confirm settings/window state plus DB2 project/job records remain available.

DUnitX tests should be added after the first compileable application skeleton is stable.
