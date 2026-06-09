{ ============================================================================
  ArtifactOS.Desk.Commands

  Command registration for ArtifactOS Desk shell.
  Phase 1: navigation commands for Case, Artifact, Package, Contract views.

  Updated: 2026-06-05 — added tools.sourcepack.rebuild for directory re-index.
  ============================================================================ }

unit ArtifactOS.Desk.Commands;

interface

uses
  DeepBase.VCL.DeepShell,
  DeepBase.VCL.DeepShell.Commands;

procedure RegisterDeskCommands(const ACommands: IShellCommandManager;
  const AStatus: IShellStatusManager);

implementation

uses
  System.SysUtils,
  DeepBase.VCL.DeepShell.Types,
  ArtifactOS.Services.SourcePackScanner;

procedure RegisterDeskCommands(const ACommands: IShellCommandManager;
  const AStatus: IShellStatusManager);
begin
  // Navigation group
  ACommands.RegisterCommand(
    ShellCommand('nav.today', 'Today')
      .Category('Navigation')
      .Hint('Open Today desk view')
      .Shortcut('Ctrl+T')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.nav', 'Navigating to Today view');
        end));

  ACommands.RegisterCommand(
    ShellCommand('nav.week', 'Week Overview')
      .Category('Navigation')
      .Hint('Open weekly governance chain overview')
      .Shortcut('Ctrl+W')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.nav', 'Navigating to Week view');
        end));

  ACommands.RegisterCommand(
    ShellCommand('nav.cases', 'Cases')
      .Category('Navigation')
      .Hint('Browse active and historical cases')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.nav', 'Navigating to Cases view');
        end));

  ACommands.RegisterCommand(
    ShellCommand('nav.packages', 'Publication Packages')
      .Category('Navigation')
      .Hint('Browse publication packages and verify status')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.nav', 'Navigating to Packages view');
        end));

  ACommands.RegisterCommand(
    ShellCommand('nav.contracts', 'Contracts')
      .Category('Navigation')
      .Hint('Browse contract pipeline status')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.nav', 'Navigating to Contracts view');
        end));

  // Actions group
  ACommands.RegisterCommand(
    ShellCommand('action.run.shadow', 'Shadow Run')
      .Category('Actions')
      .Hint('Start a shadow run to test the full chain')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.action', 'Shadow run initiated');
        end));

  ACommands.RegisterCommand(
    ShellCommand('action.engine.start', 'Start Engine')
      .Category('Actions')
      .Hint('Start ArtifactOS Engine in background')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.action', 'Engine start requested');
        end));

  // Tools group
  ACommands.RegisterCommand(
    ShellCommand('tools.migrations', 'Migration Status')
      .Category('Tools')
      .Hint('Show database migration status')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.tools', 'Migration status requested');
        end));

  ACommands.RegisterCommand(
    ShellCommand('tools.quality.gate', 'Quality Gate')
      .Category('Tools')
      .Hint('Run quality gate checks on selected artifact')
      .OnExecute(
        procedure
        begin
          AStatus.Info('desk.tools', 'Quality gate check requested');
        end));

  ACommands.RegisterCommand(
    ShellCommand('tools.sourcepack.rebuild', 'Rebuild Source Index')
      .Category('Tools')
      .Hint('Rescan SourcePack directory and rebuild file inventory')
      .OnExecute(
        procedure
        var
          SourceRoot, PackId: string;
          R: TSourcePackScanResult;
        begin
          PackId := TSourcePackScanner.GetActiveSourcePackId;
          if PackId <> '' then
          begin
            // Rebuild existing pack — fetch its source_root
            AStatus.Info('desk.tools', 'Rebuilding source index...');
            Exit;  // TODO: fetch root from DB and call RebuildIndex
          end;

          // First time: prompt for SourcePack root directory
          // For now use the known default path
          SourceRoot := 'D:\_Progs\一元论';
          if not System.SysUtils.DirectoryExists(SourceRoot) then
          begin
            AStatus.Info('desk.tools', 'SourcePack directory not found: ' + SourceRoot);
            Exit;
          end;

          AStatus.Info('desk.tools', 'Scanning SourcePack: ' + SourceRoot);
          R := TSourcePackScanner.RebuildIndex(SourceRoot);
          AStatus.Info('desk.tools',
            Format('Source index rebuilt: %d files indexed (%d skipped) SPL updated',
              [R.IndexedFiles, R.SkippedFiles]));
        end));
end;

end.
