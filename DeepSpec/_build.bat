@echo off
set BDS=d:\Program Files (x86)\Embarcadero\Studio\37.0
set PATH=%BDS%\bin;%PATH%

cd /d D:\_Progs\02Business\DeepSpec
if not exist dcu mkdir dcu
if not exist bin mkdir bin

dcc64 -B -NSSystem;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win -U"src\app;src\services;src\providers;src\controllers;src\core;src\models;D:\_Progs\02Business\DeepBase\Core;D:\_Progs\02Business\DeepBase\VCL;D:\_Progs\02Business\DeepBase\Persistence;D:\_Progs\02Business\DeepBase\Features;D:\_Progs\02Business\DeepBase\Governance;D:\_Progs\02Business\DeepBase\CloudServices;D:\_Progs\02Business\DeepBase\Libs;D:\_Progs\02Business\DeepBase\doQry;D:\_Progs\02Business\DeepBase\Tools;D:\_Progs\02Business\DeepBase\DeepFlow;D:\_Progs\02Business\DeepBase\ThirdParty" -E".\bin" -N".\dcu" -DDEBUG DeepSpec.dpr
