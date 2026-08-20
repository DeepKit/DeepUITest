@echo off
cd /d D:\_Progs\02Business\ArtifactOS
set ARTIFACTOS_DB_USER=postgres
set ARTIFACTOS_DB_PASS=postgres
echo RUNNING_SMOKE...
bin\Win64\Debug\ArtifactOS.exe --smoke-runtime
echo EXITCODE=%errorlevel%
echo DONE
