@echo off
title QokerProxy v2.2 Build (Delphi 13.1)
chcp 65001 >nul

echo ========================================
echo Building QokerProxy v2.2 with Delphi 13.1
echo ========================================
echo.

cd /d "D:\_Progs\02Business\QoderProxy\src\qoder"

REM Clean old files
echo Cleaning...
del /q *.dcu *.obj *.exe *.tds 2>nul

echo Starting compiler...
echo.

"D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe" -B -Q -U".;..\..\node_modules;D:\_Progs\02Business\DeepBase\Core;D:\_Progs\02Business\DeepBase\Persistence;D:\_Progs\02Business\DeepBase\VCL;D:\_Progs\02Business\DeepBase\Features" -O".;..\..\node_modules;D:\_Progs\02Business\DeepBase\Core;D:\_Progs\02Business\DeepBase\Persistence;D:\_Progs\02Business\DeepBase\VCL;D:\_Progs\02Business\DeepBase\Features" -I".;..\..\node_modules;D:\_Progs\02Business\DeepBase\Core;D:\_Progs\02Business\DeepBase\Persistence;D:\_Progs\02Business\DeepBase\VCL;D:\_Progs\02Business\DeepBase\Features" QokerProxy.v2_2.dpr

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo SUCCESS! Build complete.
    echo Output: QokerProxy.v2_2.exe
    echo ========================================
) else (
    echo.
    echo FAILED with error code: %ERRORLEVEL%
)

echo.
pause
