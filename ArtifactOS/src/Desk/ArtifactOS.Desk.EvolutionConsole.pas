{ ============================================================================
  ArtifactOS.Desk.EvolutionConsole

  L4-75: Evolution console — strategy unit list + traffic light + downgrade.
  ============================================================================ }

unit ArtifactOS.Desk.EvolutionConsole;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Forms, Vcl.Grids,
  DeepBase.VCL.DeepShell.Types,
  DeepBase.VCL.DeepShell.Intf,
  ArtifactOS.Core.DB.Connection;

type
  TEvolutionConsoleFrame = class(TFrame)
  private
    FHeader: TPanel;
    FTitleLabel: TLabel;
    FRefreshBtn: TButton;
    FGrid: TStringGrid;
    FActionPanel: TPanel;
    FDowngradeBtn: TButton;
    FFreezeBtn: TButton;
    FEscalateBtn: TButton;
    FStatusBar: TPanel;
    FStatusText: TLabel;
    procedure SetupControls;
    procedure LoadStrategyUnits;
    procedure RefreshBtnClick(Sender: TObject);
    procedure DowngradeBtnClick(Sender: TObject);
    procedure FreezeBtnClick(Sender: TObject);
    procedure EscalateBtnClick(Sender: TObject);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    function GetSelectedArtifactId: string;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TEvolutionViewProvider = class(TInterfacedObject, IShellMainViewProvider)
  public
    function ProviderId: string;
    function CanOpen(const ARef: TShellObjectRef): Boolean;
    function GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
    function CreateViewControl(AOwner: TComponent;
      const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
  end;

implementation

uses
  System.JSON,
  ArtifactOS.Services.FeedbackEvolution,
  ArtifactOS.Services.CognitiveGovernance;

{ ── TEvolutionConsoleFrame ───────────────────────────────────────── }

constructor TEvolutionConsoleFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetupControls;
  LoadStrategyUnits;
end;

procedure TEvolutionConsoleFrame.SetupControls;
begin
  // Header panel
  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.Height := 44;
  FHeader.BevelOuter := bvNone;
  FHeader.Color := clWhite;

  FTitleLabel := TLabel.Create(FHeader);
  FTitleLabel.Parent := FHeader;
  FTitleLabel.Left := 12;
  FTitleLabel.Top := 12;
  FTitleLabel.Font.Size := 14;
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Caption := 'Evolution Console';

  FRefreshBtn := TButton.Create(FHeader);
  FRefreshBtn.Parent := FHeader;
  FRefreshBtn.AlignWithMargins := True;
  FRefreshBtn.Align := alRight;
  FRefreshBtn.Width := 100;
  FRefreshBtn.Caption := 'Refresh';
  FRefreshBtn.OnClick := RefreshBtnClick;

  // Grid
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.ColCount := 8;
  FGrid.RowCount := 2;
  FGrid.DefaultRowHeight := 28;
  FGrid.Options := FGrid.Options + [goRowSelect, goThumbTracking];
  FGrid.OnSelectCell := GridSelectCell;

  FGrid.Cells[0, 0] := 'Light';
  FGrid.Cells[1, 0] := 'Artifact';
  FGrid.Cells[2, 0] := 'Platform';
  FGrid.Cells[3, 0] := 'Quality';
  FGrid.Cells[4, 0] := 'Engage';
  FGrid.Cells[5, 0] := 'Cal.Delta';
  FGrid.Cells[6, 0] := 'Misses';
  FGrid.Cells[7, 0] := 'Status';
  FGrid.ColWidths[0] := 60;
  FGrid.ColWidths[1] := 260;
  FGrid.ColWidths[2] := 80;
  FGrid.ColWidths[3] := 70;
  FGrid.ColWidths[4] := 80;
  FGrid.ColWidths[5] := 80;
  FGrid.ColWidths[6] := 60;
  FGrid.ColWidths[7] := 120;

  // Action panel
  FActionPanel := TPanel.Create(Self);
  FActionPanel.Parent := Self;
  FActionPanel.Align := alBottom;
  FActionPanel.Height := 44;
  FActionPanel.BevelOuter := bvNone;

  FDowngradeBtn := TButton.Create(FActionPanel);
  FDowngradeBtn.Parent := FActionPanel;
  FDowngradeBtn.Left := 12;
  FDowngradeBtn.Top := 8;
  FDowngradeBtn.Width := 120;
  FDowngradeBtn.Height := 28;
  FDowngradeBtn.Caption := 'Downgrade';
  FDowngradeBtn.Enabled := False;
  FDowngradeBtn.OnClick := DowngradeBtnClick;

  FFreezeBtn := TButton.Create(FActionPanel);
  FFreezeBtn.Parent := FActionPanel;
  FFreezeBtn.Left := 140;
  FFreezeBtn.Top := 8;
  FFreezeBtn.Width := 120;
  FFreezeBtn.Height := 28;
  FFreezeBtn.Caption := 'Freeze';
  FFreezeBtn.Enabled := False;
  FFreezeBtn.OnClick := FreezeBtnClick;

  FEscalateBtn := TButton.Create(FActionPanel);
  FEscalateBtn.Parent := FActionPanel;
  FEscalateBtn.Left := 268;
  FEscalateBtn.Top := 8;
  FEscalateBtn.Width := 120;
  FEscalateBtn.Height := 28;
  FEscalateBtn.Caption := 'Escalate';
  FEscalateBtn.Enabled := False;
  FEscalateBtn.OnClick := EscalateBtnClick;

  // Status bar
  FStatusBar := TPanel.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.Height := 24;
  FStatusBar.BevelOuter := bvLowered;

  FStatusText := TLabel.Create(FStatusBar);
  FStatusText.Parent := FStatusBar;
  FStatusText.Left := 8;
  FStatusText.Top := 4;
  FStatusText.Caption := 'Ready';
end;

procedure TEvolutionConsoleFrame.LoadStrategyUnits;
var
  DB: TArtifactDB;
  Row, MissCount, I: Integer;
  Rows: string;
  JArr: TJSONArray;
  JObj: TJSONObject;
  CalDelta: Double;
  Light: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Use json_agg to get all rows as a JSON array string
    Rows := DB.ExecuteScalarJson(
      'SELECT COALESCE(json_agg(row_to_json(t))::text, ''[]'') FROM (' +
      'SELECT a.id::text as artifact_id, a.title, ' +
      '  COALESCE(po.platform, ''-'') as platform, ' +
      '  COALESCE(qs.es_score, 0)::text as quality, ' +
      '  COALESCE(po.engagement_rate, 0)::text as engagement, ' +
      '  COALESCE(cl.calibration_delta, 0)::text as cal_delta, ' +
      '  COALESCE(cl.consecutive_miss_count, 0)::text as misses, ' +
      '  COALESCE(cl.resolution_status, ''-'') as cal_status ' +
      'FROM artifactos.artifact a ' +
      'LEFT JOIN LATERAL (SELECT platform, engagement_rate FROM artifactos.performance_observation WHERE artifact_id=a.id ORDER BY observed_at DESC LIMIT 1) po ON true ' +
      'LEFT JOIN LATERAL (SELECT es_score FROM artifactos.quality_snapshot WHERE artifact_id=a.id ORDER BY created_at DESC LIMIT 1) qs ON true ' +
      'LEFT JOIN LATERAL (SELECT calibration_delta, consecutive_miss_count, resolution_status FROM artifactos.calibration_ledger WHERE artifact_id=a.id ORDER BY observed_at DESC LIMIT 1) cl ON true ' +
      'ORDER BY a.created_at DESC LIMIT 50' +
      ') t', '{}');

    JArr := TJSONObject.ParseJSONValue(Rows) as TJSONArray;
    if (JArr = nil) or (JArr.Count = 0) then
    begin
      if JArr <> nil then JArr.Free;
      FGrid.RowCount := 2;
      FGrid.Cells[0, 1] := '-';
      FGrid.Cells[1, 1] := '(no data)';
      FStatusText.Caption := 'No strategy units found';
      Exit;
    end;

    try
      FGrid.RowCount := JArr.Count + 1;
      for I := 0 to JArr.Count - 1 do
      begin
        JObj := JArr.Items[I] as TJSONObject;
        Row := I + 1;

        MissCount := StrToIntDef(JObj.GetValue<string>('misses', '0'), 0);
        CalDelta := StrToFloatDef(JObj.GetValue<string>('cal_delta', '0'), 0);

        if MissCount >= 3 then Light := 'RED'
        else if CalDelta > 0.5 then Light := 'ORANGE'
        else if CalDelta > 0.25 then Light := 'YELLOW'
        else if CalDelta > 0 then Light := 'GREEN'
        else Light := '-';

        FGrid.Cells[0, Row] := Light;
        FGrid.Cells[1, Row] := Copy(JObj.GetValue<string>('title', '(untitled)'), 1, 40);
        FGrid.Cells[2, Row] := JObj.GetValue<string>('platform', '-');
        FGrid.Cells[3, Row] := JObj.GetValue<string>('quality', '0');
        FGrid.Cells[4, Row] := JObj.GetValue<string>('engagement', '0');
        FGrid.Cells[5, Row] := JObj.GetValue<string>('cal_delta', '0');
        FGrid.Cells[6, Row] := JObj.GetValue<string>('misses', '0');
        FGrid.Cells[7, Row] := JObj.GetValue<string>('cal_status', '-');
      end;
      FStatusText.Caption := IntToStr(JArr.Count) + ' strategy units loaded';
    finally
      JArr.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

procedure TEvolutionConsoleFrame.RefreshBtnClick(Sender: TObject);
begin
  FStatusText.Caption := 'Refreshing...';
  LoadStrategyUnits;
end;

function TEvolutionConsoleFrame.GetSelectedArtifactId: string;
var
  Title: string;
  DB: TArtifactDB;
begin
  Result := '';
  if FGrid.Row < 1 then Exit;

  Title := FGrid.Cells[1, FGrid.Row];
  if Title = '(untitled)' then Exit;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalar(
      'SELECT id::text FROM artifactos.artifact ' +
      'WHERE title LIKE ''' + Copy(Title, 1, 40) + '%'' ' +
      'ORDER BY created_at DESC LIMIT 1');
  finally
    DB.Disconnect;
  end;
end;

procedure TEvolutionConsoleFrame.GridSelectCell(Sender: TObject;
  ACol, ARow: Integer; var CanSelect: Boolean);
begin
  FDowngradeBtn.Enabled := ARow >= 1;
  FFreezeBtn.Enabled := ARow >= 1;
  FEscalateBtn.Enabled := ARow >= 1;
end;

procedure TEvolutionConsoleFrame.DowngradeBtnClick(Sender: TObject);
var
  ArtId, ProposalId: string;
begin
  ArtId := GetSelectedArtifactId;
  if ArtId = '' then begin
    FStatusText.Caption := 'No artifact selected';
    Exit;
  end;

  TFeedbackEvolution.CreateProposal(
    'human_override',
    'Manual downgrade: ' + Copy(FGrid.Cells[1, FGrid.Row], 1, 40),
    'Operator-initiated downgrade from Evolution Console',
    '{"action":"downgrade_trust","artifact_id":"' + ArtId + '"}',
    'medium',
    ProposalId);

  FStatusText.Caption := 'Downgrade proposal created: ' + Copy(ProposalId, 1, 8);
end;

procedure TEvolutionConsoleFrame.FreezeBtnClick(Sender: TObject);
var
  ArtId: string;
begin
  ArtId := GetSelectedArtifactId;
  if ArtId = '' then begin
    FStatusText.Caption := 'No artifact selected';
    Exit;
  end;

  TCognitiveGovernance.FreezeArtifact(ArtId,
    'Manual freeze from Evolution Console: ' + FGrid.Cells[1, FGrid.Row]);

  FStatusText.Caption := 'Artifact frozen: ' + Copy(ArtId, 1, 8);
  LoadStrategyUnits;
end;

procedure TEvolutionConsoleFrame.EscalateBtnClick(Sender: TObject);
var
  ArtId, EventId: string;
begin
  ArtId := GetSelectedArtifactId;
  if ArtId = '' then begin
    FStatusText.Caption := 'No artifact selected';
    Exit;
  end;

  TCognitiveGovernance.RecordDisturbance(ArtId, '',
    'human_override', 'high',
    '{"source":"evolution_console"}',
    EventId);

  FStatusText.Caption := 'Escalated: disturbance ' + Copy(EventId, 1, 8);
end;

{ ── TEvolutionViewProvider ───────────────────────────────────────── }

function TEvolutionViewProvider.ProviderId: string;
begin
  Result := 'evolution';
end;

function TEvolutionViewProvider.CanOpen(const ARef: TShellObjectRef): Boolean;
begin
  Result := (ARef.Kind = 'view') and (ARef.Id = 'evolution');
end;

function TEvolutionViewProvider.GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
begin
  Result := TShellViewInfo.Make('evolution', svkControl, 'Evolution Console', '');
end;

function TEvolutionViewProvider.CreateViewControl(AOwner: TComponent;
  const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
begin
  Result := TEvolutionConsoleFrame.Create(AOwner);
end;

end.
