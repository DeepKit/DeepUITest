@echo off
REM ArtifactOS Phase 1A Build Script
REM Uses Delphi 13.1 (Compiler 37.0) + DeepBase source link
REM Usage:
REM   build.bat            — compile main ArtifactOS.exe
REM   build.bat --run      — compile + run smoke test
REM   build.bat --tests    — compile test runner ArtifactOSTests.exe
REM   build.bat --all      — compile both main + tests

set BDS=C:\Program Files (x86)\Embarcadero\Studio\37.0
if exist "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\dcc64.exe" set BDS=D:\Program Files (x86)\Embarcadero\Studio\37.0

set DCC64=%BDS%\bin64\dcc64.exe
set DEEPBASE=..\DeepBase
set DCU=dcu\Win64\Debug
set BIN=bin\Win64\Debug

set UNITS=%DEEPBASE%\Core;%DEEPBASE%\Services;%DEEPBASE%\Persistence;%DEEPBASE%\Governance;%DEEPBASE%\VCL;%DEEPBASE%\AutoFix;%DEEPBASE%\Features;src\core;src\services;src\Desk
set TEST_UNITS=%DEEPBASE%\Core;%DEEPBASE%\Services;%DEEPBASE%\Persistence;%DEEPBASE%\Governance;%DEEPBASE%\Features;src\core;src\services;tests
set TEST_DCU=dcu\Win64\TestDebug
set TEST_BIN=bin\Win64\TestDebug

echo ========================================
echo ArtifactOS Phase 1A Build
echo ========================================
echo.

if not exist "%DCC64%" (
    echo ERROR: dcc64.exe not found at %DCC64%
    exit /b 1
)

echo Delphi: %DCC64%
echo DeepBase: %DEEPBASE%
echo.

if "%~1"=="--tests" goto :build_tests
if "%~1"=="--all" goto :build_all

:build_main
if not exist "%DCU%" mkdir "%DCU%"
if not exist "%BIN%" mkdir "%BIN%"

echo Compiling ArtifactOS.dpr ...
"%DCC64%" -B -Q ^
  "-U%UNITS%" ^
  "-I%UNITS%" ^
  "-E%BIN%" ^
  "-N0%DCU%" ^
  src\ArtifactOS.dpr

if %errorlevel% neq 0 (
    echo BUILD FAILED
    exit /b 1
)

echo.
echo BUILD OK — %BIN%\ArtifactOS.exe
echo.

if "%~1"=="--run" goto :run_smoke
if "%~1"=="--all" goto :build_tests
goto :end

:run_smoke
echo Running smoke test...
if "%ARTIFACTOS_DB_USER%"=="" set ARTIFACTOS_DB_USER=fuyi01
"%BIN%\ArtifactOS.exe"
if %errorlevel% neq 0 (
    echo RUNTIME FAILED
    exit /b 1
)
echo RUNTIME OK
goto :end

:build_all
call :build_main
if %errorlevel% neq 0 goto :end

:build_tests
if not exist "%TEST_DCU%" mkdir "%TEST_DCU%"
if not exist "%TEST_BIN%" mkdir "%TEST_BIN%"

echo.
echo Compiling ArtifactOSTests.dpr ...
echo   (DUnitX test runner — target: artifactos_test)
echo.

"%DCC64%" -B -Q ^
  "-U%TEST_UNITS%" ^
  "-I%TEST_UNITS%" ^
  "-E%TEST_BIN%" ^
  "-N0%TEST_DCU%" ^
  tests\ArtifactOSTests.dpr

if %errorlevel% neq 0 (
    echo TEST BUILD FAILED
    exit /b 1
)

echo.
echo TEST BUILD OK — %TEST_BIN%\ArtifactOSTests.exe
echo.
echo Run tests with: %TEST_BIN%\ArtifactOSTests.exe
echo.

goto :end

:end
echo Done.
