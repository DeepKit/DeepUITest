@echo off
cd /d d:\_Progs\02Business
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" -E"d:\_Progs\02Business\DeepBase\DeepBaseRun\bin" -U"d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Features" "d:\_Progs\02Business\DeepBase\DeepBaseRun\DeepBaseRun.dpr" > d:\_Progs\02Business\compile_dbrun2.txt 2>&1
echo EXIT=%ERRORLEVEL% >> d:\_Progs\02Business\compile_dbrun2.txt
