@echo off
"d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" -E"d:\_Progs\02Business\DeepBase\Tools\CLI\bin" -U"d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Persistence;d:\_Progs\02Business\DeepBase\Features" "d:\_Progs\02Business\DeepBase\Tools\CLI\DeepBase.dpr" > d:\_Progs\02Business\compile_cli.bat.log 2>&1
