{ ============================================================================
  ArtifactOS.Core.AutoFix.Scenarios

  AutoFix smoke scenarios for ArtifactOS runtime verification.
  These scenarios run when the app is launched with --autofix-mode.

  Registered in DPR for both Desk and Engine modes.
  ============================================================================ }

unit ArtifactOS.Core.AutoFix.Scenarios;

// ◆ Architecture: autofix scenarios are the application diagnostic bridge layer.
//   They intentionally import both core + services to run end-to-end boundary checks.
//   This is the ONLY unit in core/ allowed to reference services/ — rule #3 exception.

interface

uses
  System.SysUtils,
  DeepBase.AutoFix;

procedure RegisterArtifactOSAutoFixScenarios;

implementation

uses
  System.Generics.Collections,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.PlatformAdapter,
  ArtifactOS.Services.IntegrationBridge,
  ArtifactOS.Services.LegacyExitClosure,
  ArtifactOS.Services.SharedKnowledgeEngine,
  ArtifactOS.Services.StrategyUnitManager;

procedure RegisterArtifactOSAutoFixScenarios;
begin
  { Scenario: PG connectivity }
  AutoFix.RegisterScenario('pg.connect', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''artifactos''');
      if V <> '1' then
        raise Exception.Create('artifactos schema not found in database');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Migrations applied }
  AutoFix.RegisterScenario('pg.migrations', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos._migration_log');
      if StrToIntDef(V, 0) < 1 then
        raise Exception.Create('No migrations applied to artifactos schema');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Core tables exist }
  AutoFix.RegisterScenario('pg.core_tables', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var Tables: TArray<string> := [
        'case_record', 'studio', 'sub_studio', 'artifact', 'artifact_version',
        'quality_snapshot', 'quality_run', 'publication_package',
        'real_publish_gate_run', 'event_ledger', 'substudio_execution_task',
        'artifact_contract', 'content_spec_snapshot'
      ];
      for var T in Tables do
      begin
        var V := ArtifactOS_DB.ExecuteScalar(
          'SELECT COUNT(*)::text FROM information_schema.tables ' +
          'WHERE table_schema=''artifactos'' AND table_name=''' + T + '''');
        if V <> '1' then
          raise Exception.Create('Required table missing: artifactos.' + T);
      end;
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: State machine rules loaded }
  AutoFix.RegisterScenario('pg.state_rules', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.state_transition_rule');
      if StrToIntDef(V, 0) < 10 then
        raise Exception.Create('Too few state transition rules: ' + V + ' (expected >= 10)');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Blueprint seeds exist }
  AutoFix.RegisterScenario('pg.blueprints', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.blueprint');
      if StrToIntDef(V, 0) < 1 then
        raise Exception.Create('No blueprints seeded');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: RealPublishGate function callable }
  AutoFix.RegisterScenario('pg.real_publish_gate', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT (artifactos.check_real_publish_gate() ->> ''gate_status'')::text');
      if (V <> 'blocked') and (V <> 'open') then
        raise Exception.Create('Unexpected RealPublishGate status: ' + V);
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Contract pipeline tables accessible }
  AutoFix.RegisterScenario('pg.contracts', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      // Basic table existence
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.requirement_frame');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.content_spec_snapshot');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.contract_candidate');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.artifact_contract');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Media publish schema exists }
  AutoFix.RegisterScenario('pg.media_publish', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      var V := ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM information_schema.schemata WHERE schema_name=''media_publish''');
      if V <> '1' then
        raise Exception.Create('media_publish schema not found');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { Scenario: Generation session tables accessible }
  AutoFix.RegisterScenario('pg.generation_session', procedure
  begin
    ArtifactOS_DB.Connect;
    try
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.generation_session');
      ArtifactOS_DB.ExecuteScalar(
        'SELECT COUNT(*)::text FROM artifactos.generation_outline');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  // ═══ N11: Test gap fill — runtime boundary checks ═══

  { N11: PlatformAdapter registry — 4 platforms }
  AutoFix.RegisterScenario('test.platform_adapter_registry', procedure
  begin
    var Platforms := TPlatformAdapterRegistry.GetPlatformIds;
    if Length(Platforms) < 4 then
      raise Exception.CreateFmt('Expected >=4 platforms, got %d', [Length(Platforms)]);

    var Zhihu := TPlatformAdapterRegistry.Get('zhihu');
    if not Assigned(Zhihu) then
      raise Exception.Create('zhihu adapter missing');

    var Weibo := TPlatformAdapterRegistry.Get('weibo');
    if not Assigned(Weibo) then
      raise Exception.Create('weibo adapter missing');
  end);

  { N11: Zhihu validates title length }
  AutoFix.RegisterScenario('test.zhihu_title_validation', procedure
  begin
    var A := TPlatformAdapterRegistry.Get('zhihu');
    if not A.ValidateTitle('Short').IsValid then
      raise Exception.Create('Short title should be valid');
    if A.ValidateTitle(StringOfChar('A', 65)).IsValid then
      raise Exception.Create('65-char title should be invalid for zhihu');
  end);

  { N11: Weibo FormatTitle edge cases }
  AutoFix.RegisterScenario('test.weibo_title_hashtags', procedure
  begin
    var A := TPlatformAdapterRegistry.Get('weibo');
    // Empty title
    if Length(A.FormatTitle('')) <> 0 then
      raise Exception.Create('Empty title must produce empty string');
    // Normal title gets hashtags
    if Pos('#', A.FormatTitle('Test')) = 0 then
      raise Exception.Create('Title must have hashtags');
    // Weibo strips spaces in titles, so 'Hello World' → '#HelloWorld#'
    if Pos('#HelloWorld#', A.FormatTitle('Hello World')) <> 1 then
      raise Exception.Create('Title must be wrapped as #HelloWorld# (spaces stripped)');
  end);

  { N11: Weibo FormatBody strips markup }
  AutoFix.RegisterScenario('test.weibo_formatbody_strip', procedure
  begin
    var A := TPlatformAdapterRegistry.Get('weibo');
    var Fmt := A.FormatBody('**Bold** `code` <p>HTML</p>');
    if Pos('**', Fmt) > 0 then
      raise Exception.Create('Weibo must strip markdown bold');
    if Pos('`', Fmt) > 0 then
      raise Exception.Create('Weibo must strip backticks');
    if Pos('<p>', Fmt) > 0 then
      raise Exception.Create('Weibo must strip HTML tags');
    // Long body truncation
    var Long := StringOfChar('A', 2100);
    var FmtLong := A.FormatBody(Long);
    if Length(FmtLong) > 2000 then
      raise Exception.CreateFmt('Weibo body must be <=2000, got %d', [Length(FmtLong)]);
  end);

  { N11: XHS title constraints }
  AutoFix.RegisterScenario('test.xhs_title_constraints', procedure
  begin
    var A := TPlatformAdapterRegistry.Get('xiaohongshu');
    if A.GetConstraints.MaxTitleLen <> 20 then
      raise Exception.CreateFmt('XHS max title len expected 20, got %d', [A.GetConstraints.MaxTitleLen]);
    if A.ValidateTitle(StringOfChar('X', 25)).IsValid then
      raise Exception.Create('XHS 25-char title should be rejected');
  end);

  { N11: WeChat formats body with section/br tags }
  AutoFix.RegisterScenario('test.wechat_formatbody', procedure
  begin
    var A := TPlatformAdapterRegistry.Get('wechat_public');
    var Fmt := A.FormatBody('Hello'#10'World');
    if Pos('<section>', Fmt) = 0 then
      raise Exception.Create('WeChat must wrap in <section>');
    if Pos('<br>', Fmt) = 0 then
      raise Exception.Create('WeChat must convert line breaks to <br>');
  end);

  { N11: StrategyUnitManager — CRUD + edge cases }
  AutoFix.RegisterScenario('test.strategyunit_crud', procedure
  begin
    var Mgr: IStrategyUnitManager;
    Mgr := TStrategyUnitManager.Create;

    // Create
    var Rec: TStrategyUnitRecord;
    Rec.Init;
    Rec.Code := 'autofix-test-' + TGUID.NewGuid.ToString;
    Rec.LabelText := 'AutoFix Test Unit';
    Rec.Status := 'draft';
    var NewId := Mgr.CreateUnit(Rec);
    if NewId = '' then
      raise Exception.Create('CreateUnit returned empty id');

    // Get
    var OutRec: TStrategyUnitRecord;
    if not Mgr.GetUnit(NewId, OutRec) then
      raise Exception.Create('GetUnit failed for created unit');

    // Update
    Rec.LabelText := 'AutoFix Test Updated';
    if not Mgr.UpdateUnit(NewId, Rec) then
      raise Exception.Create('UpdateUnit failed');

    // Delete non-existent returns False
    if Mgr.DeleteUnit('00000000-0000-0000-0000-000000000000') then
      raise Exception.Create('DeleteUnit should return False for non-existent');

    // SetStatus non-existent returns False
    if Mgr.SetStatus('00000000-0000-0000-0000-000000000000', 'paused') then
      raise Exception.Create('SetStatus non-existent should return False');

    // Delete draft unit
    if not Mgr.DeleteUnit(NewId) then
      raise Exception.Create('DeleteUnit failed for draft unit');
  end);

  { N11: StrategyUnitManager — active unit guard }
  AutoFix.RegisterScenario('test.strategyunit_active_guard', procedure
  begin
    var Mgr: IStrategyUnitManager;
    Mgr := TStrategyUnitManager.Create;

    var Rec: TStrategyUnitRecord;
    Rec.Init;
    Rec.Code := 'autofix-active-' + TGUID.NewGuid.ToString;
    Rec.Status := 'active';
    var Id := Mgr.CreateUnit(Rec);
    if Id = '' then
      raise Exception.Create('CreateUnit failed');

    // Delete active unit must return False
    if Mgr.DeleteUnit(Id) then
      raise Exception.Create('DeleteUnit must return False for active unit');

    // Cleanup: set to draft then delete
    Mgr.SetStatus(Id, 'draft');
    Mgr.DeleteUnit(Id);
  end);

  { N11: LegacyExitClosure — stage lifecycle }
  AutoFix.RegisterScenario('test.legacyexit_stage_lifecycle', procedure
  var
    SUId: string;
    Info: TLegacyStageInfo;
    Unfulfilled: TArray<string>;
  begin
    ArtifactOS_DB.Connect;
    try
      SUId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.strategy_unit WHERE code=''first-zhihu-longform''');
      if SUId = '' then Exit;
    finally
      ArtifactOS_DB.Disconnect;
    end;

    // GetOrCreateTracker
    if not TLegacyExitClosure.GetOrCreateTracker(SUId, Info) then
      raise Exception.Create('GetOrCreateTracker failed');
    if Info.TrackerId = '' then
      raise Exception.Create('TrackerId must not be empty');
    if Info.LegacyStage = '' then
      raise Exception.Create('LegacyStage must not be empty');

    // L0 cannot degrade
    if TLegacyExitClosure.DegradeStage(Info.TrackerId, 'Test') then
      raise Exception.Create('L0 must not be degradable');

    // L0 needs 7 shadow days
    if not TLegacyExitClosure.CheckExitConditions(Info.TrackerId, Unfulfilled) then
    begin
      var HasShadowReq: Boolean := False;
      for var I := 0 to High(Unfulfilled) do
        if Pos('shadow days', Unfulfilled[I]) > 0 then
          HasShadowReq := True;
      if not HasShadowReq then
        raise Exception.Create('L0 must require shadow days');
    end;
  end);

  { N11: LegacyExitClosure — L5 terminal + degrade run_mode }
  AutoFix.RegisterScenario('test.legacyexit_terminal_l5', procedure
  var
    SUId, TrackerId: string;
    NewStage: string;
    OutInfo: TLegacyStageInfo;
  begin
    ArtifactOS_DB.Connect;
    try
      SUId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.strategy_unit WHERE code=''first-zhihu-longform''');
      if SUId = '' then Exit;

      var Info: TLegacyStageInfo;
      TLegacyExitClosure.GetOrCreateTracker(SUId, Info);
      TrackerId := Info.TrackerId;

      // Set to L5 (terminal)
      ArtifactOS_DB.Execute(
        'UPDATE artifactos.legacy_stage_tracker SET legacy_stage=''L5_archived'' WHERE id=''' + TrackerId + '''');

      // L5 cannot promote
      if TLegacyExitClosure.TryPromoteStage(TrackerId, 'Test L5', NewStage) then
        raise Exception.Create('L5 must not be promotable');
      if NewStage <> '' then
        raise Exception.Create('NewStage must be empty for L5');

      // Set to L1, test degrade L1->L0 run_mode
      ArtifactOS_DB.Execute(
        'UPDATE artifactos.legacy_stage_tracker SET legacy_stage=''L1_parallel_observe'', run_mode=''parallel'' WHERE id=''' + TrackerId + '''');
      TLegacyExitClosure.DegradeStage(TrackerId, 'Test L1->L0');
      TLegacyExitClosure.GetOrCreateTracker(SUId, OutInfo);
      if OutInfo.RunMode <> 'shadow' then
        raise Exception.CreateFmt('L1->L0 must set run_mode=shadow, got %s', [OutInfo.RunMode]);

      // Restore L0
      ArtifactOS_DB.Execute(
        'UPDATE artifactos.legacy_stage_tracker SET legacy_stage=''L0_shadow_only'', run_mode=''shadow'' WHERE id=''' + TrackerId + '''');
      TLegacyExitClosure.GetOrCreateTracker(SUId, OutInfo);
      if OutInfo.LegacyStage <> 'L0_shadow_only' then
        raise Exception.Create('Failed to restore L0');
    finally
      ArtifactOS_DB.Disconnect;
    end;
  end);

  { N11: IntegrationBridge — create/poll/claim request }
  AutoFix.RegisterScenario('test.integration_request_lifecycle', procedure
  var
    ArtId, VerId, SnapId, PkgId, ReqId, Status: string;
  begin
    ArtifactOS_DB.Connect;
    try
      ArtId := ArtifactOS_DB.ExecuteScalar(
        'SELECT a.id::text FROM artifactos.artifact a ' +
        'JOIN artifactos.artifact_version av ON av.artifact_id = a.id LIMIT 1');
      if ArtId = '' then Exit;

      VerId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.artifact_version WHERE artifact_id=''' + ArtId + ''' LIMIT 1');
      SnapId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.quality_snapshot WHERE artifact_id=''' + ArtId + ''' LIMIT 1');
      PkgId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.publication_package WHERE artifact_id=''' + ArtId + ''' LIMIT 1');
      if (VerId = '') or (SnapId = '') or (PkgId = '') then Exit;

      // Create request
      ReqId := TIntegrationBridge.CreateProductionRequest(ArtId, VerId, SnapId, PkgId, 'zhihu');
      if ReqId = '' then
        raise Exception.Create('CreateProductionRequest returned empty id');

      // Verify status = pending
      Status := ArtifactOS_DB.ExecuteScalar(
        'SELECT request_status FROM integration.production_request WHERE id=''' + ReqId + '''');
      if Status <> 'pending' then
        raise Exception.CreateFmt('Expected pending, got %s', [Status]);

      // Poll (should be empty initially)
      var Results := TIntegrationBridge.PollResults(ReqId);
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

  { N11: SharedKnowledgeEngine — propose + adopt + rate }
  AutoFix.RegisterScenario('test.sharedknowledge_propose_adopt', procedure
  var
    SUId, PoolId: string;
    Count: Integer;
    AvgRating: Double;
  begin
    ArtifactOS_DB.Connect;
    try
      SUId := ArtifactOS_DB.ExecuteScalar(
        'SELECT id::text FROM artifactos.strategy_unit WHERE code=''first-zhihu-longform''');
    finally
      ArtifactOS_DB.Disconnect;
    end;
    if SUId = '' then Exit;

    // Propose
    PoolId := TSharedKnowledgeEngine.Propose('fact_claim', SUId,
      '{"autofix":"test_' + TGUID.NewGuid.ToString + '"}',
      'all_units', 'AutoFix test propose', []);
    if PoolId = '' then
      raise Exception.Create('Propose returned empty id');

    // Dedup
    var PoolId2 := TSharedKnowledgeEngine.Propose('fact_claim', SUId,
      '{"autofix":"duplicate_test"}', 'all_units', 'Dedup test 1', []);
    var PoolId3 := TSharedKnowledgeEngine.Propose('fact_claim', SUId,
      '{"autofix":"duplicate_test"}', 'all_units', 'Dedup test 2', []);
    if PoolId2 <> PoolId3 then
      raise Exception.Create('Dedup must return same pool id for same content');

    // Adopt
    if not TSharedKnowledgeEngine.Adopt(PoolId, SUId, '{}') then
      raise Exception.Create('Adopt failed');

    // Rate
    if not TSharedKnowledgeEngine.Rate(PoolId, SUId, 8) then
      raise Exception.Create('Rate failed');

    // Stats
    if TSharedKnowledgeEngine.GetAdoptionStats(PoolId, Count, AvgRating) then
    begin
      if AvgRating < 7.0 then
        raise Exception.CreateFmt('Expected avg rating >=7, got %.1f', [AvgRating]);
    end;

    // Deprecate
    if not TSharedKnowledgeEngine.Deprecate(PoolId, 'AutoFix deprecation') then
      raise Exception.Create('Deprecate failed');
  end);
end;

end.
