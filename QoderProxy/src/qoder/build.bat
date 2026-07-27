@echo off
setlocal EnableDelayedExpansion

echo ========================================
echo QoderProxy v2.2 Compilation Script
echo Using Delphi 13.1 Compiler (bcc64.exe)
echo ========================================
echo.

cd /d "%~dp0"

echo Compiler path: "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\bcc64.exe"
echo Working directory: %CD%
echo.

REM Check if compiler exists
if not exist "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\bcc64.exe" (
    echo ERROR: Compiler not found!
    pause
    exit /b 1
)

REM Remove old compiled files
echo Cleaning previous build artifacts...
del /q *.dcu *.obj *.exe 2>nul

echo Starting compilation...
echo.

"D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\bcc64.exe" -B"." "..\node_modules" "..\DeepBase\Source" QokerProxy.v2_2.dpr

if errorlevel 1 (
    echo.
    echo COMPILATION FAILED!
    pause
    exit /b 1
) else (
    echo.
    echo ========================================
    echo ✅ COMPILATION SUCCESSFUL!
    echo Output: QokerProxy.v2_2.exe
    echo ========================================
)

pause
