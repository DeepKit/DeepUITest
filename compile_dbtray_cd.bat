@echo off
cd /d d:\_Progs\02Business\DeepBase\Tools\Tray
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" -E"bin" -U"..\..\Core;..\..\VCL;..\..\Features" DeepBaseTray.dpr > d:\_Progs\02Business\compile_dbtray_cd.txt 2>&1
echo EXIT=%ERRORLEVEL% >> d:\_Progs\02Business\compile_dbtray_cd.txt
