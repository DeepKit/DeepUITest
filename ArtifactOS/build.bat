@echo off
REM ArtifactOS Phase 1A Build Script
REM Uses Delphi 13.1 (Compiler 37.0) + DeepBase source link

set BDS=C:\Program Files (x86)\Embarcadero\Studio\37.0
if exist "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\dcc64.exe" set BDS=D:\Program Files (x86)\Embarcadero\Studio\37.0

set DCC64=%BDS%\bin64\dcc64.exe
set DEEPBASE=..\..\DeepBase
set DCU=dcu\Win64\Debug
set BIN=bin\Win64\Debug

set UNITS=%DEEPBASE%\Core;%DEEPBASE%\Services;%DEEPBASE%\Persistence;%DEEPBASE%\Governance;src\core;src\services

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

if not "%1"=="--run" goto :end

echo Running smoke test...
if "%ARTIFACTOS_DB_USER%"=="" set ARTIFACTOS_DB_USER=fuyi01
"%BIN%\ArtifactOS.exe"
if %errorlevel% neq 0 (
    echo RUNTIME FAILED
    exit /b 1
)
echo RUNTIME OK

:end
echo Done.