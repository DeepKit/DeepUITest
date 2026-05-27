program ArtifactOSTests;

{ ArtifactOS DUnitX test runner. }

uses
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  ArtifactOS.Tests.E2EChain;

begin
  TDUnitX.Run([TArtifactOSE2EChain]);
end.