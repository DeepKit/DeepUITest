unit ArtifactOS.Core.Dashboard;

interface

type
  TArtifactOSDashboard = class
  public
    class procedure Run;
  end;

implementation

uses
  System.SysUtils,
  ArtifactOS.Core.DB.Connection;

class procedure TArtifactOSDashboard.Run;

  function S(const Q: string): string; inline;
  begin
    Result := ArtifactOS_DB.ExecuteScalar(Q);
  end;

  procedure Hdr(const Title: string);
  begin
    WriteLn;
    WriteLn('── ', Title, ' ──');
  end;

begin
  ArtifactOS_DB.Connect;
  try
    WriteLn('Connected to: ', ArtifactOS_DB.DatabaseName);
    WriteLn('Schema:       ', ArtifactOS_DB.Schema);
    WriteLn;
    WriteLn('PG version:   ', S('SELECT version()'));

    // ── SourcePack ──
    Hdr('SourcePack');
    WriteLn('  source_pack:         ', S('SELECT display_name FROM artifactos.source_pack WHERE status=''candidate'' LIMIT 1'));
    WriteLn('  loading_level:        ', S('SELECT loading_level FROM artifactos.source_pack LIMIT 1'));
    WriteLn('  inventory files:      ', S('SELECT COUNT(*)::text FROM artifactos.source_inventory_candidate'));
    WriteLn('  canonical_candidates: ', S('SELECT COUNT(*)::text FROM artifactos.source_inventory_candidate WHERE source_layer=''canonical_candidate'''));

    // ── Case ──
    Hdr('Case');
    WriteLn('  cases: ', S('SELECT COUNT(*)::text FROM artifactos.case_record'));
    WriteLn('  active: ', S('SELECT COUNT(*)::text FROM artifactos.case_record WHERE status=''active'''));

    // ── Blueprint ──
    Hdr('Blueprint');
    WriteLn('  blueprints: ', S('SELECT COUNT(*)::text FROM artifactos.artifact_blueprint'));

    // ── State Machine ──
    Hdr('State Machine');
    WriteLn('  transition rules: ', S('SELECT COUNT(*)::text FROM artifactos.state_transition_rule'));
    WriteLn('  active:            ', S('SELECT COUNT(*)::text FROM artifactos.state_transition_rule WHERE is_active=true'));

    // ── Amy Workbench ──
    Hdr('Amy Workbench');
    WriteLn('  work_card tables:     ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''artifactos'' AND table_name IN (''work_card'',''prepared_action_panel'',''prepared_action_option'')'));
    WriteLn('  notification tables:  ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''artifactos'' AND table_name IN (''notification_channel'',''notification_policy'',''notification_event'',''work_report'',''daily_report'')'));
    WriteLn('  attention budget:     ', S('SELECT COUNT(*)::text FROM artifactos.human_attention_budget WHERE status=''active'''));
    WriteLn('  meeting protocols:    ', S('SELECT COUNT(*)::text FROM artifactos.meeting_protocol WHERE status=''active'''));

    // ── Publication Gate ──
    Hdr('Publication');
    WriteLn('  publication_packages:', S('SELECT COUNT(*)::text FROM artifactos.publication_package'));
    WriteLn('  quality_snapshots:    ', S('SELECT COUNT(*)::text FROM artifactos.quality_snapshot'));
    WriteLn('  RealPublishGate:      ', S('SELECT gate_status::text FROM artifactos.check_real_publish_gate()'));

    // ── Shadow Run ──
    Hdr('Shadow Run');
    WriteLn('  shadow_runs: ', S('SELECT COUNT(*)::text FROM artifactos.shadow_run'));

    // ── Legacy Bridge ──
    Hdr('Legacy & External');
    WriteLn('  legacy_bridge tables: ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''legacy_bridge'''));
    WriteLn('  media_publish tables:  ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''media_publish'''));

  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

end.