@echo off
set BDS=d:\Program Files (x86)\Embarcadero\Studio\37.0
set PATH=%BDS%\bin;%PATH%

cd /d D:\_Progs\02Business\DeepSpec\tests
if not exist dcu mkdir dcu

dcc64 -B -NSSystem;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win -U"..\src\core;..\src\models;..\dcu;D:\_Progs\02Business\DeepBase\Core;D:\_Progs\02Business\DeepBase\Libs;D:\_Progs\02Business\DeepBase\ThirdParty" -E"." -N".\dcu" -DDEBUG DeepSpec.Tests.dpr
