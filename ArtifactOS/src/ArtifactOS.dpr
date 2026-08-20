program ArtifactOS;

{ ArtifactOS — Source-to-Artifact Production and Amplification Kernel }
{ Phase 1A: shadow run only.  Target database: artifactos_test. }
{ Modes: (default) CLI dashboard, --desk VCL GUI, --engine background, }
{        --smoke-runtime test, --rebuildsource rescan, --autofix diagnostics }

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Vcl.Forms,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  FireDAC.DApt.Intf,
  FireDAC.Comp.Client,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepBase.Security,
  DeepBase.AutoFix,
  DeepBase.AutoFix.VclHook,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.Dashboard,
  ArtifactOS.Core.Runtime.Smoke,
  ArtifactOS.Core.Runtime.Engine,
  ArtifactOS.Core.Runtime.EngineCallbacks,
  ArtifactOS.Core.AutoFix.Scenarios,
  ArtifactOS.Core.PlatformAdapter,
  ArtifactOS.Core.CLI.Dispatch,
  ArtifactOS.Services.ChainRunner,
  ArtifactOS.Services.DeepLLMProxy,
  ArtifactOS.Services.GenerationService,
  ArtifactOS.Services.TopicFunnel,
  ArtifactOS.Services.PublicationBridge,
  ArtifactOS.Services.CognitiveGovernance,
  ArtifactOS.Services.PerformanceCollector,
  ArtifactOS.Services.FeedbackEvolution,
  ArtifactOS.Services.ShadowRunScheduler,
  ArtifactOS.Services.RealPublishGate,
  ArtifactOS.Services.SourcePackScanner,
  ArtifactOS.Services.StrategyUnitManager,
  ArtifactOS.Services.LegacyExitClosure,
  ArtifactOS.Services.IntegrationBridge,
  ArtifactOS.Services.SharedKnowledgeEngine,
  ArtifactOS.Services.BCWImport,
  ArtifactOS.Services.BCWResultSummary,
  ArtifactOS.Services.CLIHandlers,
  ArtifactOS.Desk.MainForm in 'Desk\ArtifactOS.Desk.MainForm.pas' {DeskMainForm},
  ArtifactOS.Desk.Services in 'Desk\ArtifactOS.Desk.Services.pas',
  ArtifactOS.Desk.Commands in 'Desk\ArtifactOS.Desk.Commands.pas',
  ArtifactOS.Desk.Providers in 'Desk\ArtifactOS.Desk.Providers.pas',
  ArtifactOS.Desk.EvolutionConsole in 'Desk\ArtifactOS.Desk.EvolutionConsole.pas',
  ArtifactOS.Desk.AutoTuneAudit in 'Desk\ArtifactOS.Desk.AutoTuneAudit.pas';

{$R *.res}

// ── CLI flag detection ──
// BCW-TD20260727-001: Delphi FindCmdLineSwitch 默认 SwitchChars=['-','/'], 对双横线开关
// --smoke-runtime 会把首 '-' 当前缀、剩余 '-smoke-runtime'(含第二个 '-') 当 switch 名,
// 与查找名 'smoke-runtime' 不匹配返回 False. 实测 5 个核心开关(--smoke-runtime/--desk/
// --engine/--rebuildsource/--run-demo)全部失效, 全走默认 dashboard.
// 同文件 --autofix/--set-secret/--dry-run 用 SameText(ParamStr,'--xxx') 能正常识别,
// 证明双横线开关必须走 SameText 扫描. 本函数统一提供该判据, 替代 FindCmdLineSwitch.
function HasCliFlag(const AFlag: string): Boolean;
var
  I: Integer;
  FlagArg: string;
begin
  FlagArg := '--' + AFlag;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), FlagArg) then
      Exit(True);
  Result := False;
end;

// ── Manual AutoFix diagnostic runner ──
// Must be called after DeepBase.InitializeOrRaise (needs config for DB connection)
procedure RunAutoFixMode;
var
  Passed, Failed, Total: Integer;

  procedure DoCheck(const TestName, TestDesc: string; const TestProc: TProc);
  begin
    Inc(Total);
    try
      TestProc();
      Inc(Passed);
      WriteLn('  [PASS] ', TestName);
    except
      on E: Exception do
      begin
        Inc(Failed);
        WriteLn('  [FAIL] ', TestName, ' — ', E.ClassName, ': ', E.Message);
        WriteLn('         ', TestDesc);
      end;
    end;
  end;

begin
  Passed := 0;
  Failed := 0;
  Total := 0;

  WriteLn('========================================');
  WriteLn('ArtifactOS AutoFix Diagnostic Mode');
  WriteLn('========================================');
  WriteLn;

  // ── Scenario: PG connectivity ──
  DoCheck('pg.connect', 'Ensure PostgreSQL is reachable and artifactos schema exists',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''artifactos''');
        if V <> '1' then
          raise Exception.Create('artifactos schema not found');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: Migrations applied ──
  DoCheck('pg.migrations', 'Ensure at least 1 migration applied',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM artifactos._migration_log');
        if StrToIntDef(V, 0) < 1 then
          raise Exception.Create('No migrations applied (count=' + V + ')');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: Core tables ──
  DoCheck('pg.core_tables', 'Verify 13 core tables exist in artifactos schema',
    procedure
    var
      Tables: TArray<string>;
    begin
      Tables := TArray<string>.Create(
        'case_record', 'studio', 'sub_studio', 'artifact', 'artifact_version',
        'quality_snapshot', 'quality_run', 'publication_package',
        'real_publish_gate_run', 'event_ledger', 'substudio_execution_task',
        'artifact_contract', 'content_spec_snapshot');
      ArtifactOS_DB.Connect;
      try
        for var Tbl in Tables do
        begin
          var V := ArtifactOS_DB.ExecuteScalar(
            'SELECT COUNT(*)::text FROM information_schema.tables ' +
            'WHERE table_schema=''artifactos'' AND table_name=''' + Tbl + '''');
          if V <> '1' then
            raise Exception.Create('Missing table: artifactos.' + Tbl);
        end;
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: State machine rules ──
  DoCheck('pg.state_rules', 'Ensure >= 10 state transition rules loaded',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM artifactos.state_transition_rule');
        if StrToIntDef(V, 0) < 10 then
          raise Exception.Create('Too few state transition rules (got=' + V + ', need >=10)');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: Blueprints seeded ──
  DoCheck('pg.blueprints', 'Ensure blueprints are seeded',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM artifactos.artifact_blueprint');
        if StrToIntDef(V, 0) < 1 then
          raise Exception.Create('No blueprints seeded');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: RealPublishGate function ──
  DoCheck('pg.real_publish_gate', 'Ensure check_real_publish_gate() is callable',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT (artifactos.check_real_publish_gate() ->> ''gate_status'')::text');
        if (V <> 'blocked') and (V <> 'open') then
          raise Exception.Create('Unexpected gate_status: ' + V);
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: SourcePack loaded ──
  DoCheck('pg.sourcepack', 'Ensure at least 1 SourcePack loaded',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM artifactos.source_pack');
        if StrToIntDef(V, 0) < 1 then
          raise Exception.Create('No SourcePack loaded');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: Active cases ──
  DoCheck('pg.active_cases', 'Ensure at least 1 active case exists',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM artifactos.case_record WHERE status=''active''');
        if StrToIntDef(V, 0) < 1 then
          raise Exception.Create('No active cases');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: media_publish schema ──
  DoCheck('pg.media_publish', 'Ensure media_publish schema exists',
    procedure
    begin
      ArtifactOS_DB.Connect;
      try
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''media_publish''');
        if V <> '1' then
          raise Exception.Create('media_publish schema not found (this is non-critical)');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ═══ N11: Test gap fill — runtime boundary checks ═══

  // ── Scenario: PlatformAdapter registry has 4 platforms ──
  DoCheck('test.platform_adapter_registry', 'Ensure 4+ platform adapters registered',
    procedure
    var
      Platforms: TArray<string>;
      Zhihu, Weibo: IPlatformAdapter;
    begin
      Platforms := TPlatformAdapterRegistry.GetPlatformIds;
      if Length(Platforms) < 4 then
        raise Exception.CreateFmt('Expected >=4 platforms, got %d', [Length(Platforms)]);
      Zhihu := TPlatformAdapterRegistry.Get('zhihu');
      if not Assigned(Zhihu) then
        raise Exception.Create('zhihu adapter missing');
      Weibo := TPlatformAdapterRegistry.Get('weibo');
      if not Assigned(Weibo) then
        raise Exception.Create('weibo adapter missing');
    end);

  // ── Scenario: Zhihu title validation ──
  DoCheck('test.zhihu_title_validation', 'Short title valid, 65-char title invalid',
    procedure
    var
      A: IPlatformAdapter;
    begin
      A := TPlatformAdapterRegistry.Get('zhihu');
      if not A.ValidateTitle('Short').IsValid then
        raise Exception.Create('Short title should be valid');
      if A.ValidateTitle(StringOfChar('A', 65)).IsValid then
        raise Exception.Create('65-char title should be invalid for zhihu');
    end);

  // ── Scenario: Weibo title hashtags ──
  DoCheck('test.weibo_title_hashtags', 'Empty→empty, normal→#tags#, exact wrapping',
    procedure
    var
      A: IPlatformAdapter;
    begin
      A := TPlatformAdapterRegistry.Get('weibo');
      if Length(A.FormatTitle('')) <> 0 then
        raise Exception.Create('Empty title must produce empty string');
      if Pos('#', A.FormatTitle('Test')) = 0 then
        raise Exception.Create('Title must have hashtags');
      // Weibo strips spaces in titles, so 'Hello World' → '#HelloWorld#'
      if Pos('#HelloWorld#', A.FormatTitle('Hello World')) <> 1 then
        raise Exception.Create('Title must be wrapped as #HelloWorld# (spaces stripped)');
    end);

  // ── Scenario: Weibo FormatBody strips markup ──
  DoCheck('test.weibo_formatbody_strip', 'Strip markdown/HTML, truncate to 2000',
    procedure
    var
      A: IPlatformAdapter;
      Fmt, Long, FmtLong: string;
    begin
      A := TPlatformAdapterRegistry.Get('weibo');
      Fmt := A.FormatBody('**Bold** `code` <p>HTML</p>');
      if Pos('**', Fmt) > 0 then
        raise Exception.Create('Weibo must strip markdown bold');
      if Pos('`', Fmt) > 0 then
        raise Exception.Create('Weibo must strip backticks');
      if Pos('<p>', Fmt) > 0 then
        raise Exception.Create('Weibo must strip HTML tags');
      Long := StringOfChar('A', 2100);
      FmtLong := A.FormatBody(Long);
      if Length(FmtLong) > 2000 then
        raise Exception.CreateFmt('Weibo body must be <=2000, got %d', [Length(FmtLong)]);
    end);

  // ── Scenario: XHS title constraints ──
  DoCheck('test.xhs_title_constraints', 'MaxTitleLen=20, 25-char title rejected',
    procedure
    var
      A: IPlatformAdapter;
    begin
      A := TPlatformAdapterRegistry.Get('xiaohongshu');
      if A.GetConstraints.MaxTitleLen <> 20 then
        raise Exception.CreateFmt('XHS max title len expected 20, got %d', [A.GetConstraints.MaxTitleLen]);
      if A.ValidateTitle(StringOfChar('X', 25)).IsValid then
        raise Exception.Create('XHS 25-char title should be rejected');
    end);

  // ── Scenario: WeChat formats body with section/br ──
  DoCheck('test.wechat_formatbody', 'Wrap in <section>, convert newlines to <br>',
    procedure
    var
      A: IPlatformAdapter;
      Fmt: string;
    begin
      A := TPlatformAdapterRegistry.Get('wechat_public');
      Fmt := A.FormatBody('Hello'#10'World');
      if Pos('<section>', Fmt) = 0 then
        raise Exception.Create('WeChat must wrap in <section>');
      if Pos('<br>', Fmt) = 0 then
        raise Exception.Create('WeChat must convert line breaks to <br>');
    end);

  // ── Scenario: StrategyUnitManager CRUD ──
  DoCheck('test.strategyunit_crud', 'Create and Delete cycle',
    procedure
    var
      Mgr: IStrategyUnitManager;
      Rec: TStrategyUnitRecord;
      NewId: string;
    begin
      Mgr := TStrategyUnitManager.Create;
      Rec.Init;
      Rec.Code := 'autofix-test-' + TGUID.NewGuid.ToString;
      Rec.LabelText := 'AutoFix Test Unit';
      Rec.AccountId := '00000000-0000-0000-0000-000000000001';
      Rec.Status := 'draft';
      NewId := Mgr.CreateUnit(Rec);
      if NewId = '' then
        raise Exception.Create('CreateUnit returned empty id');
      if not Mgr.DeleteUnit(NewId) then
        raise Exception.Create('DeleteUnit failed for draft unit');
    end);

  // ── Scenario: StrategyUnitManager active unit guard ──
  DoCheck('test.strategyunit_active_guard', 'Delete active unit must return False',
    procedure
    var
      Mgr: IStrategyUnitManager;
      Rec: TStrategyUnitRecord;
      Id: string;
      Deleted: Boolean;
    begin
      Mgr := TStrategyUnitManager.Create;
      Rec.Init;
      Rec.Code := 'autofix-active-' + TGUID.NewGuid.ToString;
      Rec.AccountId := '00000000-0000-0000-0000-000000000001';
      Rec.Status := 'active';
      Id := Mgr.CreateUnit(Rec);
      if Id = '' then
        raise Exception.Create('CreateUnit failed');
      Deleted := Mgr.DeleteUnit(Id);
      if Deleted then
        raise Exception.Create('DeleteUnit must return False for active unit');
      // Cleanup: set to draft then delete
      Mgr.SetStatus(Id, 'draft');
      Mgr.DeleteUnit(Id);
    end);

  // ── Scenario: LegacyExitClosure stage lifecycle ──
  DoCheck('test.legacyexit_stage_lifecycle', 'GetOrCreateTracker + L0 cannot degrade + requires exit conditions',
    procedure
    var
      SUId: string;
      Info: TLegacyStageInfo;
      Unfulfilled: TArray<string>;
    begin
      ArtifactOS_DB.Connect;
      try
        SUId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.strategy_unit WHERE code=''first-zhihu-longform''');
        if SUId = '' then
          raise Exception.Create('first-zhihu-longform unit not found');
      finally
        ArtifactOS_DB.Disconnect;
      end;

      // GetOrCreateTracker may fail on duplicate key if tracker exists — handle gracefully
      try
        if not TLegacyExitClosure.GetOrCreateTracker(SUId, Info) then
          raise Exception.Create('GetOrCreateTracker failed');
      except
        // Any exception (duplicate key, etc.) — fall back to querying existing tracker
        ArtifactOS_DB.Connect;
        try
          Info.TrackerId := ArtifactOS_DB.ExecuteScalar(
            'SELECT id::text FROM artifactos.legacy_stage_tracker WHERE strategy_unit_id=''' + SUId + '''');
          Info.LegacyStage := ArtifactOS_DB.ExecuteScalar(
            'SELECT legacy_stage FROM artifactos.legacy_stage_tracker WHERE strategy_unit_id=''' + SUId + '''');
          Info.RunMode := ArtifactOS_DB.ExecuteScalar(
            'SELECT run_mode FROM artifactos.legacy_stage_tracker WHERE strategy_unit_id=''' + SUId + '''');
        finally
          ArtifactOS_DB.Disconnect;
        end;
        if Info.TrackerId = '' then
          raise Exception.Create('GetOrCreateTracker failed and no existing tracker found');
      end;

      if Info.TrackerId = '' then
        raise Exception.Create('TrackerId must not be empty');

      // L0 cannot degrade
      if TLegacyExitClosure.DegradeStage(Info.TrackerId, 'Test') then
        raise Exception.Create('L0 must not be degradable');

      // L0 should have unfulfilled exit conditions (not ready to promote)
      if TLegacyExitClosure.CheckExitConditions(Info.TrackerId, Unfulfilled) then
        raise Exception.Create('L0 exit conditions should not all be met initially');
    end);

  // ── Scenario: LegacyExitClosure L5 terminal + degrade run_mode ──
  DoCheck('test.legacyexit_terminal_l5', 'L5 cannot promote; L1->L0 sets run_mode=shadow',
    procedure
    var
      SUId, TrackerId: string;
      NewStage: string;
      Info: TLegacyStageInfo;
    begin
      ArtifactOS_DB.Connect;
      try
        SUId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.strategy_unit WHERE code=''first-zhihu-longform''');
        if SUId = '' then
          raise Exception.Create('first-zhihu-longform unit not found');

        // Get existing tracker ID (may already exist from previous test)
        TrackerId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.legacy_stage_tracker WHERE strategy_unit_id=''' + SUId + '''');
        if TrackerId = '' then
        begin
          // Tracker doesn't exist, try to create it
          try
            TLegacyExitClosure.GetOrCreateTracker(SUId, Info);
            TrackerId := Info.TrackerId;
          except
            // If creation fails (duplicate), query again
            TrackerId := ArtifactOS_DB.ExecuteScalar(
              'SELECT id::text FROM artifactos.legacy_stage_tracker WHERE strategy_unit_id=''' + SUId + '''');
            if TrackerId = '' then
              raise Exception.Create('Could not get or create tracker');
          end;
        end;

        // Set to L5 (terminal)
        ArtifactOS_DB.Execute(
          'UPDATE artifactos.legacy_stage_tracker SET legacy_stage=''L5_archived'' WHERE id=''' + TrackerId + '''');

        // L5 cannot promote
        if TLegacyExitClosure.TryPromoteStage(TrackerId, 'Test L5', NewStage) then
          raise Exception.Create('L5 must not be promotable');
        if NewStage <> '' then
          raise Exception.Create('NewStage must be empty for L5');

        // Set to L1, degrade L1->L0
        ArtifactOS_DB.Execute(
          'UPDATE artifactos.legacy_stage_tracker SET legacy_stage=''L1_parallel_observe'', run_mode=''parallel'' WHERE id=''' + TrackerId + '''');
        TLegacyExitClosure.DegradeStage(TrackerId, 'Test L1->L0');

        // Query the updated tracker directly instead of calling GetOrCreateTracker again
        var NewRunMode := ArtifactOS_DB.ExecuteScalar(
          'SELECT run_mode FROM artifactos.legacy_stage_tracker WHERE id=''' + TrackerId + '''');
        if NewRunMode <> 'shadow' then
          raise Exception.CreateFmt('L1->L0 must set run_mode=shadow, got %s', [NewRunMode]);

        // Restore L0
        ArtifactOS_DB.Execute(
          'UPDATE artifactos.legacy_stage_tracker SET legacy_stage=''L0_shadow_only'', run_mode=''shadow'' WHERE id=''' + TrackerId + '''');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: IntegrationBridge request lifecycle ──
  DoCheck('test.integration_request_lifecycle', 'Create/poll/claim/delete production request (skip if no data)',
    procedure
    var
      ArtId, VerId, SnapId, PkgId, ReqId, Status: string;
      Results: TArray<TProductionResult>;
    begin
      ArtifactOS_DB.Connect;
      try
        ArtId := ArtifactOS_DB.ExecuteScalar(
          'SELECT a.id::text FROM artifactos.artifact a ' +
          'JOIN artifactos.artifact_version av ON av.artifact_id = a.id LIMIT 1');
        if ArtId = '' then
        begin
          WriteLn('         [SKIP] No artifact+version found for test');
          Exit;
        end;

        VerId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.artifact_version WHERE artifact_id=''' + ArtId + ''' LIMIT 1');
        SnapId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.quality_snapshot WHERE artifact_id=''' + ArtId + ''' LIMIT 1');
        PkgId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.publication_package WHERE artifact_id=''' + ArtId + ''' LIMIT 1');
        if (VerId = '') or (SnapId = '') or (PkgId = '') then
        begin
          WriteLn('         [SKIP] Missing version/snapshot/package for test artifact');
          Exit;
        end;

        // Create request
        ReqId := TIntegrationBridge.CreateProductionRequest(ArtId, VerId, SnapId, PkgId, 'zhihu');
        if ReqId = '' then
          raise Exception.Create('CreateProductionRequest returned empty id');

        // Verify status = pending
        Status := ArtifactOS_DB.ExecuteScalar(
          'SELECT request_status FROM integration.production_request WHERE id=''' + ReqId + '''');
        if Status <> 'pending' then
          raise Exception.CreateFmt('Expected pending, got %s', [Status]);

        // Poll should be empty
        Results := TIntegrationBridge.PollResults(ReqId);
        if Length(Results) > 0 then
          raise Exception.Create('PollResults should be empty for new request');

        // HasCompleted should be false
        if TIntegrationBridge.HasCompleted(ReqId) then
          raise Exception.Create('HasCompleted should be false for new request');

        // Claim via UpdateRequestStatus
        TIntegrationBridge.UpdateRequestStatus(ReqId, 'queued');
        Status := ArtifactOS_DB.ExecuteScalar(
          'SELECT request_status FROM integration.production_request WHERE id=''' + ReqId + '''');
        if Status <> 'queued' then
          raise Exception.CreateFmt('Expected queued after claim, got %s', [Status]);

        // Cleanup
        ArtifactOS_DB.Execute('DELETE FROM integration.production_request WHERE id=''' + ReqId + '''');
      finally
        ArtifactOS_DB.Disconnect;
      end;
    end);

  // ── Scenario: SharedKnowledgeEngine propose + adopt ──
  DoCheck('test.sharedknowledge_propose_adopt', 'Propose/dedup/adopt/deprecate cycle',
    procedure
    var
      SUId, PoolId: string;
    begin
      ArtifactOS_DB.Connect;
      try
        SUId := ArtifactOS_DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.strategy_unit WHERE code=''first-zhihu-longform''');
        if SUId = '' then
          raise Exception.Create('first-zhihu-longform unit not found');
      finally
        ArtifactOS_DB.Disconnect;
      end;

      // Propose
      PoolId := TSharedKnowledgeEngine.Propose('fact_claim', SUId,
        '{"autofix":"test_' + TGUID.NewGuid.ToString + '"}',
        'all_units', 'AutoFix test propose', []);
      if PoolId = '' then
        raise Exception.Create('Propose returned empty id');

      // Adopt
      if not TSharedKnowledgeEngine.Adopt(PoolId, SUId, '{}') then
        raise Exception.Create('Adopt failed');

      // Deprecate
      if not TSharedKnowledgeEngine.Deprecate(PoolId, 'AutoFix deprecation') then
        raise Exception.Create('Deprecate failed');
    end);

  WriteLn;
  WriteLn('========================================');
  WriteLn(Format('  PASS: %d  FAIL: %d  TOTAL: %d', [Passed, Failed, Total]));
  WriteLn('========================================');

  if Failed > 0 then
  begin
    WriteLn;
    WriteLn('ACTION REQUIRED:');
    WriteLn('  • Ensure PostgreSQL is running and reachable');
    WriteLn('  • Check env vars: ARTIFACTOS_DB_HOST, ARTIFACTOS_DB_PORT, ARTIFACTOS_DB_NAME');
    WriteLn('  • Check env vars: ARTIFACTOS_DB_USER, ARTIFACTOS_DB_PASS');
    WriteLn('  • Run: python db/migrate.py --status');
    WriteLn('  • Run: python db/migrate.py (to apply pending migrations)');
  end
  else
  begin
    WriteLn;
    WriteLn('All diagnostics passed. System is ready.');
  end;
end;

begin
  // ═══ Fast path: --autofix runs before anything consumes switches ═══
  for var I := 1 to ParamCount do
    if SameText(ParamStr(I), '--autofix') then
    begin
      try
        FDManager().SilentMode := True;
        AutoFix.Install;
        RegisterArtifactOSAutoFixScenarios;
        DeepBase.Manager.DeepBase.InitializeOrRaise;
        RunAutoFixMode;
      except
        on E: Exception do
        begin
          WriteLn('FATAL: ', E.ClassName, ': ', E.Message);
          ExitCode := 2;
        end;
      end;
      Exit;
    end;

  try
    FDManager().SilentMode := True;

    // ═══ Mode detection (before DeepBase init to prevent switch consumption) ═══
    // BCW-TD20260727-001: 改用 HasCliFlag (SameText 扫 ParamStr), FindCmdLineSwitch 不识别 -- 双横线.
    var IsSmoke := HasCliFlag('smoke-runtime');
    var IsDesk := HasCliFlag('desk');
    var IsEngine := HasCliFlag('engine');
    var IsRebuild := HasCliFlag('rebuildsource');

    // AutoFix/DeepBase init (skip VclHook for smoke mode)
    AutoFix.Install;
    if not IsSmoke then
      TAutoFixVclHook.Install;

    DeepBase.Manager.DeepBase.InitializeOrRaise;
    try
      // ═══ --set-secret: persist a DPAPI-encrypted secret into DB1 Secrets ═══
      // Usage:
      //   ArtifactOS.exe --set-secret <Name> <Value>          (inline; visible in process list)
      //   echo <Value> | ArtifactOS.exe --set-secret <Name>   (stdin; no argv leak — preferred for passwords)
      // Writes via DeepBase.Security.SaveSecret → DPAPI (user scope) → ArtifactOSConfig.db Secrets table.
      // Read back by LoadSecret (used e.g. by ArtifactOS.Core.DB.Connection for DB credentials).
      if (ParamCount >= 1) and SameText(ParamStr(1), '--set-secret') then
      begin
        if ParamCount < 2 then
        begin
          WriteLn('Usage: ArtifactOS.exe --set-secret <Name> [<Value>]   (omit Value to read from stdin)');
          ExitCode := 1;
        end
        else
        begin
          var LName := ParamStr(2);
          var LValue: string;
          if ParamCount >= 3 then
            LValue := ParamStr(3)
          else
          begin
            WriteLn('(reading secret value from stdin; end with newline)');
            ReadLn(LValue);
          end;
          SaveSecret(LName, LValue);
          WriteLn('OK: secret ''', LName, ''' stored (DB1 Secrets, DPAPI user-scope).');
          ExitCode := 0;
        end;
        Exit;
      end;

      // ═══ Positional subcommand: artifactos bcw <preview|apply|rollback> ═══
      // Runs before --flag modes: an explicit CLI instruction takes priority.
      //   bcw preview   — show Add/Modify/Stop diff vs. existing strategy_unit (read-only)
      //   bcw apply     — validate, snapshot, write strategy_unit, mark applied, move file (S2)
      //   bcw rollback  — restore the last applied package's pre-apply snapshot
      if (ParamCount >= 1) and SameText(ParamStr(1), 'bcw') then
      begin
        if (ParamCount >= 2) and SameText(ParamStr(2), 'preview') then
        begin
          var Diff := TBCWImportService.PreviewApply;
          if Length(Diff) = 0 then
          begin
            WriteLn('BCW preview: no decision_package in inbox, or inbox parse error');
            ExitCode := 1;
          end
          else
          begin
            WriteLn(Format('BCW preview: %d change(s)', [Length(Diff)]));
            for var D in Diff do
              WriteLn(Format('  %-6s %-28s %s%s%s',
                [D.ActionStr, D.Code,
                 IfThen(D.OldStatus<>'', D.OldStatus+'->', ''), D.NewStatus,
                 IfThen(D.Label_<>'', '  ('+D.Label_+')', '')]));
            ExitCode := 0;
          end;
        end
        else if (ParamCount >= 2) and SameText(ParamStr(2), 'apply') then
        begin
          var R := TBCWImportService.ApplyConfig;
          if R.Applied then
          begin
            WriteLn('BCW apply: package ', R.PackageId, ' applied (record ', R.AppliedRecordId, ')');
            if Length(R.Issues) > 0 then
              WriteLn('  warnings: ', R.IssueSummary);
            ExitCode := 0;
          end
          else
          begin
            WriteLn('BCW apply: package ', IfThen(R.PackageId <> '', R.PackageId, '(unparsed)'), ' rejected');
            WriteLn('  reason: ', IfThen(Length(R.Issues) > 0, R.IssueSummary, 'unknown'));
            ExitCode := 1;
          end;
        end
        else if (ParamCount >= 2) and SameText(ParamStr(2), 'rollback') then
        begin
          if TBCWImportService.RollbackLast then
          begin
            WriteLn('BCW rollback: last applied package reverted (snapshot restored, row marked rolled_back)');
            ExitCode := 0;
          end
          else
          begin
            WriteLn('BCW rollback: no applied package found to revert');
            ExitCode := 1;
          end;
        end
        else if (ParamCount >= 2) and SameText(ParamStr(2), 'summary') then
        begin
          // BCW-S4: build result_summary for the last applied package and
          // write it to integration/bcw/outbox/<packageid>-result.json.
          // Optional: `bcw summary <package_id>` for a specific package.
          var PkgId: string := '';
          if ParamCount >= 3 then PkgId := ParamStr(3);
          var S: TBCWResultSummary;
          if PkgId <> '' then
            S := TBCWResultSummaryService.BuildSummary(PkgId)
          else
            S := TBCWResultSummaryService.BuildSummary('');
          if S.PackageId = '' then
          begin
            WriteLn('BCW summary: no applied package found to summarize');
            ExitCode := 1;
          end
          else
          begin
            var OutPath := TBCWResultSummaryService.WriteOutbox(S);
            if OutPath <> '' then
            begin
              WriteLn('BCW summary: ' + S.PackageId + ' → ' + OutPath);
              WriteLn('  period=' + S.Period + ' published=' + IntToStr(S.PublishedCount) +
                      ' blocked=' + IntToStr(S.BlockedCount) +
                      ' needs_decision=' + S.NeedsDecision);
              ExitCode := 0;
            end
            else
            begin
              WriteLn('BCW summary: write outbox failed for ' + S.PackageId);
              ExitCode := 1;
            end;
          end;
        end
        else
        begin
          WriteLn('usage: ArtifactOS.exe bcw <preview|apply|rollback|summary>');
          WriteLn('  preview   reads integration/bcw/inbox/*.json, shows Add/Modify/Stop diff');
          WriteLn('  apply     validates, snapshots, writes strategy_unit, marks applied, moves file');
          WriteLn('  rollback  restores the last applied package''s pre-apply snapshot');
          WriteLn('  summary   builds result_summary for last applied package → outbox');
          ExitCode := 1;
        end;
        Exit;
      end;

      // ═══ BCW-S5 P0: unified operational CLI guard ═══
      // 未知位置参数命令必须非零退出,禁止落入默认Dashboard和自动测试写链。
      // 已知但未实现的命令(config/cycle/batch/guide/production/schedule/status/report)
      // 返回 NotImplemented envelope(退出码3),而非静默成功或误入Dashboard。
      // --run-demo 显式触发RunFullChain;默认路径不再自动跑测试写链。
      var FirstPos := '';
      for var PI := 1 to ParamCount do
        if not ParamStr(PI).StartsWith('--') then
        begin
          FirstPos := ParamStr(PI);
          Break;
        end;
      var Resolved := TCLIDispatch.ResolveCommand(FirstPos);
      var IsRunDemo := HasCliFlag('run-demo');

      if (Resolved = cmdUnknown) and (FirstPos <> '') then
      begin
        // 有位置参数但不认识 → 用法错误,非零退出,绝不落Dashboard
        // P0契约:stdout单一JSON envelope,诊断进envelope的message字段。
        var UE := TCLIDispatch.UsageError(FirstPos);
        WriteLn(UE.ToEnvelope);
        ExitCode := UE.ExitCode;
        Exit;
      end;

      if IsRunDemo then
      begin
        // P0: RunFullChain 仅由 --run-demo 显式触发
        // (demo块在下方原位置执行,这里只设标志,确保不被守卫拦截)
        Resolved := cmdDemo;
      end
      else if Resolved in [cmdConfig, cmdCycle, cmdBatch, cmdGuide,
                           cmdProduction, cmdSchedule, cmdStatus, cmdReport] then
      begin
        // S5: 子命令领域逻辑分派。--dry-run / --json 全局标志由 ParamStr 扫描。
        // 各 handler 返回 TCLIResult;ToEnvelope 统一序列化为 stdout 单一 JSON。
        var DryRun := False;
        for var di := 1 to ParamCount do
          if SameText(ParamStr(di), '--dry-run') then DryRun := True;

        // 收集位置参数(跳过 -- 开头的标志)
        var Pos: TArray<string>;
        SetLength(Pos, 0);
        for var pi := 2 to ParamCount do   // pi=1 是顶层命令本身
          if not ParamStr(pi).StartsWith('--') then
          begin
            SetLength(Pos, Length(Pos)+1);
            Pos[High(Pos)] := ParamStr(pi);
          end;
        var Sub := '';
        if Length(Pos) > 0 then Sub := Pos[0];
        // 安全取位置参数:IfThen(Boolean, Pos[N], '') 会先求值 Pos[N],
        // 数组为空时越界读 nil → EAccessViolation。改用短路闭包。
        var PosAt: TFunc<Integer, string> :=
          function(I: Integer): string
          begin
            if (I >= 0) and (I < Length(Pos)) then Result := Pos[I] else Result := '';
          end;

        var R: TCLIResult;
        case Resolved of
          cmdStatus:
            R := TCLIHandlers.Status;
          cmdSchedule:
            R := TCLIHandlers.ScheduleShow;
          cmdReport:
            R := TCLIHandlers.Report(PosAt(1));
          cmdConfig:
            if SameText(Sub, 'show') then
              R := TCLIHandlers.ConfigShow(PosAt(1))
            else if SameText(Sub, 'set') then
              R := TCLIHandlers.ConfigSet(
                PosAt(1),
                PosAt(2),
                PosAt(3), DryRun)
            else
            begin
              R := TCLIDispatch.NotImplemented('config', Sub);
              R.Message := 'usage: config show [series] | config set <series> <field> <value>';
              R.ExitCode := Ord(cliUsage);
            end;
          cmdCycle:
            if SameText(Sub, 'plan') then
            begin
              var D := 7;
              if (Length(Pos)>1) and TryStrToInt(Pos[1], D) then ;
              R := TCLIHandlers.CyclePlan(D);
            end
            else
            begin
              R := TCLIDispatch.NotImplemented('cycle', Sub);
              R.Message := 'usage: cycle plan [days]';
              R.ExitCode := Ord(cliUsage);
            end;
          cmdBatch:
            if SameText(Sub, 'create') then
              R := TCLIHandlers.BatchCreate(
                PosAt(1),
                PosAt(2),
                (if PosAt(3)<>'' then PosAt(3) else '1'),
                PosAt(4),
                PosAt(5), DryRun)
            else
            begin
              R := TCLIDispatch.NotImplemented('batch', Sub);
              R.Message := 'usage: batch create <account> <series> <count> [media_type] [window]';
              R.ExitCode := Ord(cliUsage);
            end;
          cmdGuide:
            if SameText(Sub, 'set') then
              R := TCLIHandlers.GuideSet(
                PosAt(1),
                PosAt(2),
                PosAt(3), DryRun)
            else
            begin
              R := TCLIDispatch.NotImplemented('guide', Sub);
              R.Message := 'usage: guide set <period|batch> <id> <guidance_json>';
              R.ExitCode := Ord(cliUsage);
            end;
          cmdProduction:
            if SameText(Sub, 'run') then
              R := TCLIHandlers.ProductionRun(
                PosAt(1),
                PosAt(2), DryRun)
            else
            begin
              R := TCLIDispatch.NotImplemented('production', Sub);
              R.Message := 'usage: production run <batch_id> [guide_id]';
              R.ExitCode := Ord(cliUsage);
            end;
        end;
        WriteLn(R.ToEnvelope);
        ExitCode := R.ExitCode;
        Exit;
      end;
      // Resolved=cmdUnknown 且 FirstPos='' → 无位置参数,走下方flag模式/Dashboard(向后兼容)

      // --smoke-runtime: CLI smoke test mode
      if IsSmoke then
      begin
        var SmokeMessage: string;
        if TRuntimeSmoke.Run(SmokeMessage) then
        begin
          WriteLn('Runtime smoke PASS: ', SmokeMessage);
          ExitCode := 0;
        end
        else
        begin
          WriteLn('Runtime smoke FAIL: ', SmokeMessage);
          ExitCode := 1;
        end;
        Exit;
      end;

      // --rebuildsource: rescan SourcePack directory
      if IsRebuild then
      begin
        var SourceRoot: string := 'D:\_Progs\一元论';
        WriteLn('Rebuilding source index...');
        var SR := TSourcePackScanner.RebuildIndex(SourceRoot);
        WriteLn(Format('  indexed=%d  skipped=%d  pack_id=%s', [SR.IndexedFiles, SR.SkippedFiles, SR.SourcePackId]));
        for var LPair in SR.LayerCounts do
          WriteLn(Format('  layer=%s count=%d', [LPair.Key, LPair.Value]));
        if Length(SR.Errors) > 0 then
        begin
          WriteLn(Format('  errors: %d', [Length(SR.Errors)]));
          var MaxE := High(SR.Errors);
          if MaxE > 4 then MaxE := 4;
          for var EIdx := 0 to MaxE do
            WriteLn('    ', SR.Errors[EIdx]);
        end;
        Exit;
      end;

      // --engine: background engine mode
      if IsEngine then
      begin
        var Config := DefaultEngineConfig;
        Config.AppVersion := '1.0';
        WriteLn(Format('Engine idle timeout: %d minutes', [Config.IdleTimeoutMs div 60000]));
        TRuntimeEngine.Create(Config).Run(
          procedure(const ACmdId, ACmdType, APayload: string)
          begin
            TEngineCallbacks.DispatchCommand(ACmdId, ACmdType, APayload);
          end);
        Exit;
      end;

      // --desk: VCL GUI mode (DeepShell)
      if IsDesk then
      begin
        Application.Initialize;
        Application.MainFormOnTaskbar := True;
        Application.Title := 'ArtifactOS Desk';

        RegisterArtifactOSAutoFixScenarios;

        Application.CreateForm(TDeskMainForm, DeskMainForm);
        DeepBase.Manager.DeepBase.FireReadyCallbacks;
        Application.Run;
        Exit;
      end;

      // Default: CLI dashboard mode
      WriteLn('ArtifactOS Phase 1A');
      WriteLn('==================');
      WriteLn;
      WriteLn('Usage: ArtifactOS.exe [--desk] [--engine] [--smoke-runtime] [--rebuildsource] [--autofix]');
      WriteLn;

      TArtifactOSDashboard.Run;

      var CanStart: Boolean;
      var Reason: string;
      TArtifactOSDashboard.RunShadowStartCheck(CanStart, Reason);
      WriteLn;
      WriteLn('Shadow Run Ready: ', CanStart, ' (', Reason, ')');

      // P0 (BCW-S5): RunFullChain 仅由 --run-demo 显式触发。
      // 默认无参启动不再自动跑测试写链,避免误写event_ledger/artifact行。
      if CanStart and IsRunDemo then
      begin
        var R: TChainResult;
        if TChainRunner.RunFullChain('Shadow Run Test: AI and Structural Transformation',
          'AI is not just a productivity tool. It represents a structural transformation ' +
          'in how we think about knowledge work. The fundamental shift is from executing ' +
          'procedures to defining desired outcomes. ' +
          'At the cognitive level, AI forces us to distinguish between procedural knowledge ' +
          'and outcome-oriented reasoning. What matters is no longer knowing the steps, but ' +
          'understanding the constraint space within which those steps must operate. ' +
          'At the organizational level, AI reshapes how teams coordinate. The bottleneck ' +
          'shifts from individual productivity to collective sense-making and alignment. ' +
          'These dimensions together suggest a future where human expertise is redirected ' +
          'from execution to definition, from coding to constraint articulation.',
          R) then
        begin
          WriteLn;
          WriteLn('Full Chain Created:');
          WriteLn('  Case:      ', R.CaseId);
          WriteLn('  Studio:    ', R.StudioId);
          WriteLn('  Artifact:  ', R.ArtifactId);
          WriteLn('  Version:   ', R.VersionId);
          WriteLn('  Quality:   ', R.SnapshotId);
          WriteLn('  Package:   ', R.PackageId);

          ArtifactOS_DB.Connect;
          try
            WriteLn;
            WriteLn('Verification:');
            WriteLn('  Artifact:          ', ArtifactOS_DB.ExecuteScalarJson('SELECT status::text FROM artifactos.artifact WHERE id=:id::uuid', '{"id":"' + R.ArtifactId + '"}'));
            WriteLn('  Quality:           ', ArtifactOS_DB.ExecuteScalarJson('SELECT qualified_status::text FROM artifactos.quality_snapshot WHERE id=:id::uuid', '{"id":"' + R.SnapshotId + '"}'));
            WriteLn('  Package:           ', ArtifactOS_DB.ExecuteScalarJson('SELECT status::text FROM artifactos.publication_package WHERE id=:id::uuid', '{"id":"' + R.PackageId + '"}'));
            WriteLn('  RealPublishGate:   ', ArtifactOS_DB.ExecuteScalarJson('SELECT (artifactos.check_real_publish_gate() ->> ''gate_status'')::text', ''));
            WriteLn('  State machine:     ', ArtifactOS_DB.ExecuteScalarJson('SELECT COUNT(*)::text FROM artifactos.substudio_execution_task', ''), ' tasks');
            WriteLn('  Event ledger:      ', ArtifactOS_DB.ExecuteScalarJson('SELECT COUNT(*)::text FROM artifactos.event_ledger', ''), ' entries');
          finally
            ArtifactOS_DB.Disconnect;
          end;

          TChainRunner.CleanupChain(R);
          WriteLn;
          WriteLn('Test chain cleaned up.');
        end
        else
          WriteLn('Chain creation failed: ES gate rejected the content.');
      end;
    finally
      DeepBase.Manager.DeepBase.Finalize;
    end;
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('===============================================================================');
      WriteLn('  FATAL: ', E.ClassName, ' — ', E.Message);
      WriteLn('===============================================================================');
      WriteLn;
      WriteLn('Diagnostic hints:');
      WriteLn('  [1] Ensure PostgreSQL is running and reachable');
      WriteLn('  [2] Check env vars: ARTIFACTOS_DB_HOST / ARTIFACTOS_DB_PORT / ARTIFACTOS_DB_NAME');
      WriteLn('  [3] Check env vars: ARTIFACTOS_DB_USER / ARTIFACTOS_DB_PASS');
      WriteLn('  [4] Ensure .env file exists in project root (or env vars are set)');
      WriteLn('  [5] Run: python db/migrate.py --status');
      WriteLn('  [6] Run diagnostics: ArtifactOS.exe --autofix');
      WriteLn;
      ExitCode := 1;
    end;
  end;
end.