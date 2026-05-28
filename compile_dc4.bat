@echo off
cd /d d:\_Progs\02Business
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" -E"d:\_Progs\02Business\DeepCompare\delphi\bin" -U"d:\_Progs\02Business\DeepCompare\delphi\Core;d:\_Progs\02Business\DeepCompare\delphi\DeepCompare;d:\_Progs\02Business\DeepCompare\delphi\DeepCompareU;d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\doQry;D:\ProgramData\delphi\Skia4Delphi\Library\RAD Studio 12 Athens\Win64\Release;D:\ProgramData\delphi\SynEdit-master\Source;D:\ProgramData\delphi\VirtualTreeView-master\Source;D:\ProgramData\delphi\WebView4Delphi\source" "d:\_Progs\02Business\DeepCompare\delphi\DeepCompare.dpr" > d:\_Progs\02Business\compile_dc4.txt 2>&1
echo EXIT=%ERRORLEVEL% >> d:\_Progs\02Business\compile_dc4.txt
