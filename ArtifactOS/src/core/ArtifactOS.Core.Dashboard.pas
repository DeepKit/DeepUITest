unit ArtifactOS.Core.Dashboard;

interface

type
  TArtifactOSDashboard = class
  public
    class procedure Run;
    class procedure RunShadowStartCheck(out CanStart: Boolean; out Reason: string);
  end;

implementation

uses
  System.SysUtils,
  ArtifactOS.Core.DB.Connection,
  ArtifactOS.Core.EndToEnd,
  ArtifactOS.Services.ShadowRun;

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
    WriteLn;

    Hdr('SourcePack');
    WriteLn('  source_pack:         ', S('SELECT display_name FROM artifactos.source_pack LIMIT 1'));
    WriteLn('  loading_level:        ', S('SELECT loading_level FROM artifactos.source_pack LIMIT 1'));
    WriteLn('  inventory files:      ', S('SELECT COUNT(*)::text FROM artifactos.source_inventory_candidate'));
    WriteLn('  canonical_candidates: ', S('SELECT COUNT(*)::text FROM artifactos.source_inventory_candidate WHERE source_layer=''canonical_candidate'''));

    Hdr('Case');
    WriteLn('  cases:  ', S('SELECT COUNT(*)::text FROM artifactos.case_record'));
    WriteLn('  active: ', S('SELECT COUNT(*)::text FROM artifactos.case_record WHERE status=''active'''));

    Hdr('Blueprint');
    WriteLn('  blueprints: ', S('SELECT COUNT(*)::text FROM artifactos.artifact_blueprint'));

    Hdr('State Machine');
    WriteLn('  rules:  ', S('SELECT COUNT(*)::text FROM artifactos.state_transition_rule'));
    WriteLn('  active: ', S('SELECT COUNT(*)::text FROM artifactos.state_transition_rule WHERE is_active=true'));

    Hdr('Workbench');
    WriteLn('  work_card tables:    ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''artifactos'' AND table_name IN (''work_card'',''prepared_action_panel'',''prepared_action_option'')'));
    WriteLn('  notification tables: ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''artifactos'' AND table_name IN (''notification_channel'',''notification_policy'',''notification_event'',''work_report'',''daily_report'')'));
    WriteLn('  meeting protocols:   ', S('SELECT COUNT(*)::text FROM artifactos.meeting_protocol WHERE status=''active'''));
    WriteLn('  attention budget:    ', S('SELECT COUNT(*)::text FROM artifactos.human_attention_budget WHERE status=''active'''));

    Hdr('Publication Gate');
    WriteLn('  packages:     ', S('SELECT COUNT(*)::text FROM artifactos.publication_package'));
    WriteLn('  snapshots:    ', S('SELECT COUNT(*)::text FROM artifactos.quality_snapshot'));
    WriteLn('  gate status:  ', S('SELECT gate_status::text FROM artifactos.check_real_publish_gate()'));

    Hdr('Shadow Run');
    WriteLn('  shadow_runs: ', S('SELECT COUNT(*)::text FROM artifactos.shadow_run'));

    Hdr('Legacy Bridge');
    WriteLn('  legacy_bridge tables: ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''legacy_bridge'''));
    WriteLn('  media_publish tables:  ', S('SELECT COUNT(*)::text FROM information_schema.tables WHERE table_schema=''media_publish'''));
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

class procedure TArtifactOSDashboard.RunShadowStartCheck(out CanStart: Boolean; out Reason: string);
begin
  CanStart := True;
  Reason := '';
  ArtifactOS_DB.Connect;
  try
    // SourcePack check
    if ArtifactOS_DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.source_pack') = '0' then
    begin
      CanStart := False;
      Reason := 'No SourcePack loaded';
      Exit;
    end;

    // Blueprint check
    if ArtifactOS_DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.artifact_blueprint') = '0' then
    begin
      CanStart := False;
      Reason := 'No ArtifactBlueprint seeded';
      Exit;
    end;

    // Meeting protocol check
    if ArtifactOS_DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.meeting_protocol') = '0' then
    begin
      CanStart := False;
      Reason := 'No MeetingProtocol seeded';
      Exit;
    end;

    // Case check
    if ArtifactOS_DB.ExecuteScalar('SELECT COUNT(*)::text FROM artifactos.case_record WHERE status=''active''') = '0' then
    begin
      CanStart := False;
      Reason := 'No active Case';
      Exit;
    end;

    Reason := 'All checks passed';
  finally
    ArtifactOS_DB.Disconnect;
  end;
end;

end.