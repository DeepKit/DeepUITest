@echo off
call "%~dp0scripts\env\delphi-13.1.bat"
set DB=d:\_Progs\02Business\DeepBase
set LLMSRC=d:\_Progs\02Business\DeepLLM\src

%DCC64% -E"DeepLLM\bin" -U"%DB%\Core;%DB%\Persistence;%DB%\Features;%LLMSRC%;%LLMSRC%\core\proxy;%LLMSRC%\core\security;D:\ProgramData\mORMot2-2.4-stable\src;D:\ProgramData\mORMot2-2.4-stable\src\core;D:\ProgramData\mORMot2-2.4-stable\src\net;D:\ProgramData\mORMot2-2.4-stable\src\lib;D:\ProgramData\mORMot2-2.4-stable\src\app" "%LLMSRC%\DeepLLMProxy.dpr" > compile_llmproxy.log 2>&1
echo Exit code: %ERRORLEVEL% >> compile_llmproxy.log
