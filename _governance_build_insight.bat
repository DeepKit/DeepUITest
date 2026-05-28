@echo off
set DCC="d:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe"
set DB=d:\_Progs\02Business\DeepBase
%DCC% -E"DeepInsight\bin" -U"%DB%\Core;%DB%\FMX;%DB%\Persistence;%DB%\Features;%DB%\Governance;DeepInsight;DeepInsight\backend;DeepInsight\src" "DeepInsight\DeepInsightApp.dpr"
