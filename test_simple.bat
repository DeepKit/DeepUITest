@echo off
cd /d d:\_Progs\02Business
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" "d:\_Progs\02Business\DeepBase\Tools\CLI\DeepBase.dpr" > d:\_Progs\02Business\test_simple.txt 2>&1
echo EXIT=%ERRORLEVEL% >> d:\_Progs\02Business\test_simple.txt
