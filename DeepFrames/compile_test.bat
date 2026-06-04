@echo off
setlocal enabledelayedexpansion

set BDS=D:\Program Files (x86)\Embarcadero\Studio\37.0
set BDSVERSION=37.0
set BDSCOMMONDIR=%PUBLIC%\Documents\Embarcadero\Studio\37.0
set FrameworkDir=C:\Windows\Microsoft.NET\Framework\v4.0.30319

set DEEPBASE_ROOT=D:\_Progs\02Business\DeepBase
set DEEPBASE_DCU64=%DEEPBASE_ROOT%\TestResults\dcu64

echo [ENV] Delphi 13.1 (BDS 37.0) environment loaded.

set SRC=%~dp0src
set DEEPBASE=%DEEPBASE_ROOT%

set UNITPATH=%SRC%\App
set UNITPATH=%UNITPATH%;%SRC%\UI
set UNITPATH=%UNITPATH%;%SRC%\Domain
set UNITPATH=%UNITPATH%;%SRC%\Persistence
set UNITPATH=%UNITPATH%;%SRC%\Workflow
set UNITPATH=%UNITPATH%;%SRC%\Shared
set UNITPATH=%UNITPATH%;%SRC%\Provider
set UNITPATH=%UNITPATH%;%DEEPBASE%\Core
set UNITPATH=%UNITPATH%;%DEEPBASE%\Services
set UNITPATH=%UNITPATH%;%DEEPBASE%\Persistence
set UNITPATH=%UNITPATH%;%DEEPBASE%\Features
set UNITPATH=%UNITPATH%;%DEEPBASE%\VCL
set UNITPATH=%UNITPATH%;%DEEPBASE%\ThirdParty\DB
set UNITPATH=%UNITPATH%;%DEEPBASE_DCU64%

if not exist "%~dp0bin" mkdir "%~dp0bin"
if not exist "%~dp0bin\dcu" mkdir "%~dp0bin\dcu"

echo [COMPILE] Starting DeepFrames build (Delphi 13.1, 39 units)...
echo [COMPILE] BDS=%BDS%
echo [COMPILE] UNITPATH=%UNITPATH%

set DCC64=%BDS%\bin\dcc64.exe
if not exist "%DCC64%" (
    echo [ERROR] dcc64.exe not found at %DCC64%
    echo [INFO]  Delphi compiler is dcc64.exe, not bcc64.exe (that is C++ Builder)
    exit /b 2
)

echo [COMPILE] Running %DCC64%...
echo [COMPILE] Compiling src\DeepFrames.dpr

"%DCC64%" -B -Q -E"%~dp0bin" -N0"%~dp0bin\dcu" -U"%UNITPATH%" -NSSystem;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Datasnap;Xml;FireDAC;FireDAC.Comp;FireDAC.Stan;FireDAC.Phys;FireDAC.Phys.PG;FireDAC.Phys.SQLite;FireDAC.DApt;System.Net.HttpClient;System.Net.URLClient;System.NetEncoding "%SRC%\DeepFrames.dpr"

set BUILD_EC=%ERRORLEVEL%
if %BUILD_EC% equ 0 (
    echo [COMPILE] SUCCESS - DeepFrames.exe built in bin\
) else (
    echo [COMPILE] FAILED - exit code %BUILD_EC%
    echo [HINT]  Common issues:
    echo         1. DeepBase DCU path incorrect - check DEEPBASE_DCU64
    echo         2. Missing FireDAC PostgreSQL driver - install from GetIt
    echo         3. DeepBase unit not found - verify Library Path in IDE
)
exit /b %BUILD_EC%
