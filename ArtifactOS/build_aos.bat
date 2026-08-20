@echo off
cd /d D:\_Progs\02Business\ArtifactOS
echo BUILD_START > build_out.txt
"D:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\dcc64.exe" -B -Q "-U..\DeepBase\Core;..\DeepBase\Services;..\DeepBase\Persistence;..\DeepBase\Governance;..\DeepBase\VCL;..\DeepBase\Features;src\core;src\services;src\Desk" "-I..\DeepBase\Core;..\DeepBase\Services;..\DeepBase\Persistence;..\DeepBase\Governance;..\DeepBase\VCL;..\DeepBase\Features;src\core;src\services;src\Desk" "-Ebin\Win64\Debug" "-N0dcu\Win64\Debug" src\ArtifactOS.dpr >> build_out.txt 2>&1
echo EXITCODE=%errorlevel% >> build_out.txt
echo BUILD_END >> build_out.txt
