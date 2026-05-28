@echo off
REM ===== Delphi 12.3 Athens 环境变量（回退用）=====
REM 路径：02Business/scripts/env/delphi-12.3.bat

set BDS=D:\Program Files (x86)\Embarcadero\Studio\23.0
set BDSVERSION=23.0
set BDSCOMMONDIR=%PUBLIC%\Documents\Embarcadero\Studio\23.0
set FrameworkDir=C:\Windows\Microsoft.NET\Framework\v4.0.30319

call "%BDS%\bin\rsvars.bat"

set DCC64="%BDS%\bin\dcc64.exe"
set DCC32="%BDS%\bin\dcc32.exe"
set MSBUILD="%FrameworkDir%\msbuild.exe"

set DEEPBASE_ROOT=d:\_Progs\02Business\DeepBase
set DEEPBASE_BPL=%DEEPBASE_ROOT%\dcu
set DEEPBASE_DCP=%DEEPBASE_ROOT%\dcu

echo [ENV] Delphi 12.3 Athens (BDS 23.0) loaded (FALLBACK).
