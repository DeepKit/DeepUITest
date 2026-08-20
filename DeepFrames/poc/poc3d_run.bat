@echo off
setlocal enabledelayedexpansion

REM POC 3d: Compile and run DB2 PostgreSQL connection verification
REM Requires: Delphi 13.1 (dcc64), PostgreSQL running with DeepFrames DB
REM
REM Usage:  cd poc  &&  poc3d_run.bat

set BDS=D:\Program Files (x86)\Embarcadero\Studio\37.0
set BDSVERSION=37.0
set BDSCOMMONDIR=%PUBLIC%\Documents\Embarcadero\Studio\37.0
set FrameworkDir=C:\Windows\Microsoft.NET\Framework\v4.0.30319

set DEEPBASE_ROOT=D:\_Progs\02Business\DeepBase
set DEEPBASE_DCU64=%DEEPBASE_ROOT%\TestResults\dcu64

set REPO=%~dp0..
set SRC=%REPO%\src
set DEEPBASE=%DEEPBASE_ROOT%
set OUTPUT=%REPO%\bin

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

if not exist "%OUTPUT%" mkdir "%OUTPUT%"
if not exist "%OUTPUT%\dcu_poc3d" mkdir "%OUTPUT%\dcu_poc3d"

set DCC64=%BDS%\bin\dcc64.exe
if not exist "%DCC64%" (
    echo [ERROR] dcc64.exe not found at %DCC64%
    exit /b 2
)

echo === Compiling poc3d_db2_test.dpr ===

"%DCC64%" -B -Q -E"%OUTPUT%" -N0"%OUTPUT%\dcu_poc3d" -U"%UNITPATH%" -NSSystem;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Datasnap;Xml;FireDAC;FireDAC.Comp;FireDAC.Stan;FireDAC.Phys;FireDAC.Phys.PG;FireDAC.Phys.SQLite;FireDAC.DApt;System.Net.HttpClient;System.Net.URLClient;System.NetEncoding poc3d_db2_test.dpr

if errorlevel 1 (
    echo.
    echo === COMPILE FAILED ===
    exit /b 1
)

echo.
echo === Running poc3d_db2_test ===
echo.

"%OUTPUT%\poc3d_db2_test.exe"

set RUN_EC=%ERRORLEVEL%
echo.
if %RUN_EC% equ 0 (
    echo === ALL TESTS PASSED ===
) else (
    echo === TESTS FAILED (exit code %RUN_EC%) ===
)
endlocal
exit /b %RUN_EC%
