@echo off
call "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "D:\_Progs\02Business\DeepFrames\src"
echo === Compiling with Delphi 37.0 ===

REM DeepBase paths
set DB_ROOT=D:\_Progs\02Business\DeepBase
set DB_PATHS=%DB_ROOT%\Core;%DB_ROOT%\Persistence;%DB_ROOT%\VCL;%DB_ROOT%\Governance;%DB_ROOT%\Features;%DB_ROOT%\Services;%DB_ROOT%\Libs;%DB_ROOT%\CloudServices;%DB_ROOT%\DeepFlow

REM DeepFrames paths
set DF_SRC=D:\_Progs\02Business\DeepFrames\src
set DF_PATHS=%DF_SRC%;%DF_SRC%\App;%DF_SRC%\Shared;%DF_SRC%\Domain;%DF_SRC%\Persistence;%DF_SRC%\Workflow;%DF_SRC%\Provider;%DF_SRC%\UI

dcc64 -B -U"%DF_PATHS%;%DB_PATHS%" DeepFrames.dpr
echo === EXIT CODE: %ERRORLEVEL% ===
