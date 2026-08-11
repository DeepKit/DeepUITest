@echo off
REM ============================================================================
REM  DeepSpec test/aux build script (Delphi 13.1 / Win64)
REM
REM  Parameterized (bugfix.md BUG-6):
REM    BDS            - Embarcadero Studio install dir (env override, else default)
REM    DEEPBASE_HOME  - DeepBase source root (env override, else default)
REM    %1             - .dpr name to compile (default: DeepSpec.Tests),
REM                     so diagnostic programs (_debug_parser, etc.) build too.
REM ============================================================================

if "%BDS%"=="" set "BDS=d:\Program Files (x86)\Embarcadero\Studio\37.0"
if "%DEEPBASE_HOME%"=="" set "DEEPBASE_HOME=D:\_Progs\02Business\DeepBase"
set "PATH=%BDS%\bin;%PATH%"

set "ROOT=%~dp0"
cd /d "%ROOT%"
if not exist dcu mkdir dcu

set "DPR=DeepSpec.Tests"
if not "%~1"=="" set "DPR=%~1"

dcc64 -B -NSSystem;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win -U"..\src\core;..\src\models;..\src\services;..\src\controllers;..\src\providers;..\src\app;..\dcu;%DEEPBASE_HOME%\Core;%DEEPBASE_HOME%\VCL;%DEEPBASE_HOME%\Persistence;%DEEPBASE_HOME%\Features;%DEEPBASE_HOME%\Governance;%DEEPBASE_HOME%\CloudServices;%DEEPBASE_HOME%\Libs;%DEEPBASE_HOME%\doQry;%DEEPBASE_HOME%\Tools;%DEEPBASE_HOME%\DeepFlow;%DEEPBASE_HOME%\ThirdParty" -E. -N.\dcu -DDEBUG %DPR%.dpr
