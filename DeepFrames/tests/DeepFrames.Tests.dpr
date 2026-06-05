program DeepFrames.Tests;

/// <summary>
/// DeepFrames unit test runner.
/// Compile: dcc64 -B -Q -U"..\src\App;..\src\Domain;..\src\Persistence;..\src\Workflow;..\src\Shared;..\src\Provider" DeepFrames.Tests.dpr
/// Run: DeepFrames.Tests.exe
/// </summary>

{$APPTYPE CONSOLE}

uses
  DeepFrames.Tests.Core in 'DeepFrames.Tests.Core.pas',
  DeepFrames.Tests.Integration in 'DeepFrames.Tests.Integration.pas';

begin
  WriteLn('All tests complete.');
end.
