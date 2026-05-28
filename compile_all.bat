@echo off
set DCC64="d:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe"

REM ???? bin ??
mkdir "d:\_Progs\02Business\DeepBase\Tools\CLI\bin" 2>nul
mkdir "d:\_Progs\02Business\DeepBase\DeepBaseRun\bin" 2>nul
mkdir "d:\_Progs\02Business\DeepBase\Tools\Tray\bin" 2>nul
mkdir "d:\_Progs\02Business\DeepCompare\delphi\bin" 2>nul
mkdir "d:\_Progs\02Business\DeepInput\bin" 2>nul

REM ?? DeepBase CLI
echo === DeepBase CLI === > d:\_Progs\02Business\compile_all.log
%DCC64% -E"d:\_Progs\02Business\DeepBase\Tools\CLI\bin" -U"d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Persistence;d:\_Progs\02Business\DeepBase\Features" "d:\_Progs\02Business\DeepBase\Tools\CLI\DeepBase.dpr" >> d:\_Progs\02Business\compile_all.log 2>&1
echo EXIT: %ERRORLEVEL% >> d:\_Progs\02Business\compile_all.log

echo. >> d:\_Progs\02Business\compile_all.log
echo === DeepBaseRun === >> d:\_Progs\02Business\compile_all.log
%DCC64% -E"d:\_Progs\02Business\DeepBase\DeepBaseRun\bin" -U"d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Features" "d:\_Progs\02Business\DeepBase\DeepBaseRun\DeepBaseRun.dpr" >> d:\_Progs\02Business\compile_all.log 2>&1
echo EXIT: %ERRORLEVEL% >> d:\_Progs\02Business\compile_all.log

echo. >> d:\_Progs\02Business\compile_all.log
echo === DeepBaseTray === >> d:\_Progs\02Business\compile_all.log
%DCC64% -E"d:\_Progs\02Business\DeepBase\Tools\Tray\bin" -U"d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Features;d:\_Progs\02Business\DeepBase\Tools\Tray;d:\_Progs\02Business\DeepBase\Tools\Tray\Frames;d:\_Progs\02Business\DeepBase\Tools\Tray\Forms;d:\_Progs\02Business\DeepBase\Tools\Tray\Automation" "d:\_Progs\02Business\DeepBase\Tools\Tray\DeepBaseTray.dpr" >> d:\_Progs\02Business\compile_all.log 2>&1
echo EXIT: %ERRORLEVEL% >> d:\_Progs\02Business\compile_all.log

echo. >> d:\_Progs\02Business\compile_all.log
echo === DeepCompare === >> d:\_Progs\02Business\compile_all.log
%DCC64% -E"d:\_Progs\02Business\DeepCompare\delphi\bin" -U"d:\_Progs\02Business\DeepCompare\delphi\Core;d:\_Progs\02Business\DeepCompare\delphi\DeepCompare;d:\_Progs\02Business\DeepCompare\delphi\DeepCompareU;d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Persistence;d:\_Progs\02Business\DeepBase\Features;d:\_Progs\02Business\DeepBase\Governance;d:\ProgramData\delphi\Skia4Delphi;d:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source;d:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source\Highlighters;d:\ProgramData\delphi\VirtualTreeView-master;d:\ProgramData\delphi\WebView4Delphi\source" -I"d:\ProgramData\delphi\SynEdit-master\Source" -NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC "d:\_Progs\02Business\DeepCompare\delphi\DeepCompare.dpr" >> d:\_Progs\02Business\compile_all.log 2>&1
echo EXIT: %ERRORLEVEL% >> d:\_Progs\02Business\compile_all.log

echo. >> d:\_Progs\02Business\compile_all.log
echo === DeepInput === >> d:\_Progs\02Business\compile_all.log
%DCC64% -E"d:\_Progs\02Business\DeepInput\bin" -U"d:\_Progs\02Business\DeepInput\src;d:\_Progs\02Business\DeepBase\Core;d:\_Progs\02Business\DeepBase\VCL;d:\_Progs\02Business\DeepBase\Persistence;d:\_Progs\02Business\DeepBase\Features;d:\ProgramData\delphi\Skia4Delphi;d:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source;d:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source\Highlighters;d:\ProgramData\delphi\VirtualTreeView-master" "d:\_Progs\02Business\DeepInput\src\DeepInput.dpr" >> d:\_Progs\02Business\compile_all.log 2>&1
echo EXIT: %ERRORLEVEL% >> d:\_Progs\02Business\compile_all.log
