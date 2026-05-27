program ArtifactOSTests;

{ ArtifactOS DUnitX test runner. }

uses
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  ArtifactOS.Tests.E2EChain,
  ArtifactOS.Tests.QualityGate,
  ArtifactOS.Tests.StateMachine;

begin
  TDUnitX.Run([TArtifactOSE2EChain, TQualityGateTests, TStateMachineTests]);
end.