@echo off
cd /d D:\_Progs\02Business\DeepFrames

if not exist bin mkdir bin
if not exist bin\dcu mkdir bin\dcu

echo [COMPILE] Delphi 13.1 dcc64 DeepFrames...
echo.

set DCC="D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe"
set UNITPATH=src\App;src\UI;src\Domain;src\Persistence;src\Workflow;src\Shared;src\Provider
set UNITPATH=%UNITPATH%;..\..\02Business\DeepBase\Core;..\..\02Business\DeepBase\Persistence
set UNITPATH=%UNITPATH%;..\..\02Business\DeepBase\VCL;..\..\02Business\DeepBase\ThirdParty\DB
set UNITPATH=%UNITPATH%;..\..\02Business\DeepBase\Features
set NAMESPACES=System;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Datasnap;Xml;FireDAC;FireDAC.Comp;FireDAC.Stan;FireDAC.Phys;FireDAC.Phys.PG;FireDAC.Phys.SQLite;FireDAC.DApt;System.Net.HttpClient;System.Net.URLClient;System.NetEncoding

%DCC% -B -Q -Ebin -N0bin\dcu -U"%UNITPATH%" -NS%NAMESPACES% src\DeepFrames.dpr

if %ERRORLEVEL% equ 0 (
    echo.
    echo [SUCCESS] DeepFrames compiled successfully.
) else (
    echo.
    echo [FAILED] Exit code: %ERRORLEVEL%
)

exit /b %ERRORLEVEL%