@echo off
cd /d d:\_Progs\02Business
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" -E"d:\_Progs\02Business\DeepCompare\delphi\bin" -U"d:\_Progs\02Business\DeepCompare\delphi\Core;d:\_Progs\02Business\DeepCompare\delphi\DeepCompare;d:\_Progs\02Business\DeepCompare\delphi\DeepCompareU;d:\ProgramData\delphi\Skia4Delphi;d:\ProgramData\delphi\SynEdit-master;d:\ProgramData\delphi\VirtualTreeView-master;d:\ProgramData\delphi\WebView4Delphi" "d:\_Progs\02Business\DeepCompare\delphi\DeepCompare.dpr" > d:\_Progs\02Business\compile_dc.txt 2>&1
echo EXIT=%ERRORLEVEL% >> d:\_Progs\02Business\compile_dc.txt
