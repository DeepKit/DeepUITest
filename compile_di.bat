@echo off
cd /d d:\_Progs\02Business
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" -E"d:\_Progs\02Business\DeepInput\bin" -U"d:\_Progs\02Business\DeepInput\src;d:\ProgramData\delphi\Skia4Delphi;d:\ProgramData\delphi\SynEdit-master;d:\ProgramData\delphi\VirtualTreeView-master" "d:\_Progs\02Business\DeepInput\src\DeepInput.dpr" > d:\_Progs\02Business\compile_di.txt 2>&1
echo EXIT=%ERRORLEVEL% >> d:\_Progs\02Business\compile_di.txt
