@echo off
cd /d D:\_Progs\02Business\ArtifactOS
echo SMOKE_START > smoke_out.txt
bin\Win64\Debug\ArtifactOS.exe --smoke-runtime >> smoke_out.txt 2>&1
echo EXITCODE=%errorlevel% >> smoke_out.txt
echo SMOKE_END >> smoke_out.txt
