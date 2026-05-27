program ArtifactOSTests;

{ ArtifactOS DUnitX test runner. }

uses
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  ArtifactOS.Tests.E2EChain,
  ArtifactOS.Tests.QualityGate,
  ArtifactOS.Tests.StateMachine,
  ArtifactOS.Tests.ShadowRun,
  ArtifactOS.Tests.LegacyImport;

begin
  TDUnitX.Run([TArtifactOSE2EChain, TQualityGateTests, TStateMachineTests, TShadowRunTests, TLegacyImportTests]);
end.