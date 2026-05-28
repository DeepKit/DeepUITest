@echo off
REM ===== Delphi 13.1 Florence 环境变量 =====
REM 所有 compile_*.bat 首行统一调用本文件
REM 路径：02Business/scripts/env/delphi-13.1.bat

set BDS=D:\Program Files (x86)\Embarcadero\Studio\37.0
set BDSVERSION=37.0
set BDSCOMMONDIR=%PUBLIC%\Documents\Embarcadero\Studio\37.0
set FrameworkDir=C:\Windows\Microsoft.NET\Framework\v4.0.30319

call "%BDS%\bin\rsvars.bat"

set DCC64="%BDS%\bin\dcc64.exe"
set DCC32="%BDS%\bin\dcc32.exe"
set MSBUILD="%FrameworkDir%\msbuild.exe"

REM ===== DeepBase 13.1 BPL/DCP/DCU 输出路径 =====
REM DeepBase 分支: upgrade/delphi-13
REM 输出结构:
REM   TestResults\bpl32  - Win32 BPL (runtime + designtime)
REM   TestResults\bpl64  - Win64 BPL (runtime + designtime)
REM   TestResults\dcp32  - Win32 DCP (接口文件，下游引用)
REM   TestResults\dcp64  - Win64 DCP
REM   TestResults\dcu32  - Win32 DCU (静态链接时使用)
REM   TestResults\dcu64  - Win64 DCU

set DEEPBASE_ROOT=D:\_Progs\02Business\DeepBase
set DEEPBASE_BPL32=%DEEPBASE_ROOT%\TestResults\bpl32
set DEEPBASE_BPL64=%DEEPBASE_ROOT%\TestResults\bpl64
set DEEPBASE_DCP32=%DEEPBASE_ROOT%\TestResults\dcp32
set DEEPBASE_DCP64=%DEEPBASE_ROOT%\TestResults\dcp64
set DEEPBASE_DCU32=%DEEPBASE_ROOT%\TestResults\dcu32
set DEEPBASE_DCU64=%DEEPBASE_ROOT%\TestResults\dcu64

REM 兼容别名（旧脚本可能仍使用 DEEPBASE_BPL/DEEPBASE_DCP）
set DEEPBASE_BPL=%DEEPBASE_BPL64%
set DEEPBASE_DCP=%DEEPBASE_DCP64%

REM DeepBase 源码路径（部分项目直接引用源码，而非 DCU）
set DEEPBASE_CORE=%DEEPBASE_ROOT%\Core
set DEEPBASE_FMX=%DEEPBASE_ROOT%\FMX
set DEEPBASE_VCL=%DEEPBASE_ROOT%\VCL
set DEEPBASE_PERSISTENCE=%DEEPBASE_ROOT%\Persistence
set DEEPBASE_FEATURES=%DEEPBASE_ROOT%\Features
set DEEPBASE_SERVICES=%DEEPBASE_ROOT%\Services

echo [ENV] Delphi 13.1 Florence (BDS 37.0) loaded.
echo [ENV] DeepBase DCU: %DEEPBASE_DCU64%
