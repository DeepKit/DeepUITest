@echo off
cd /d D:\_Progs\02Business\ArtifactOS
echo TEST_START > test_switch_out.txt
bin\Win64\Debug\ArtifactOS.exe /smoke-runtime >> test_switch_out.txt 2>&1
echo EXITCODE=%errorlevel% >> test_switch_out.txt
echo TEST_END >> test_switch_out.txt
