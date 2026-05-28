@echo off
REM ===== DeepDevLite Build Script (Delphi 13.1) =====
call "%~dp0..\scripts\env\delphi-13.1.bat"

set DeepBase_CORE=D:\_Progs\02Business\DeepBase\Core
set DELPHI_LIB=%BDS%\lib\win32\release
if not exist bin mkdir bin
if not exist dcu mkdir dcu

cd /d "%~dp0"

echo Building DeepDevLite (Win32 FMX)...
%MSBUILD% DeepDevLite.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal

if errorlevel 1 (
  echo   Build FAILED!
  exit /b 1
) else (
  echo   Build Successful! Output: bin\DeepDevLite.exe
)
