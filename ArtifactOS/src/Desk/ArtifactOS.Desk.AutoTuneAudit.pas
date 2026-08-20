{ ============================================================================
  ArtifactOS.Desk.AutoTuneAudit

  P2-82: AutoTune audit panel + yellow-light negotiation entry.

  Shows auto_tune_event history with parameter path, before/after values,
  risk level, and human review status. Provides yellow-light negotiation
  entry point where human can confirm/reject/modify proposed parameter changes.

  Roadmap reference: 03.[蓝图]-实施路线图-Roadmap.md §5.4 进化控制台.
  ============================================================================ }

unit ArtifactOS.Desk.AutoTuneAudit;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Forms, Vcl.Grids,
  DeepBase.VCL.DeepShell.Types,
  DeepBase.VCL.DeepShell.Intf,
  ArtifactOS.Core.DB.Connection;

type
  TAutoTuneAuditFrame = class(TFrame)
  private
    FHeader: TPanel;
    FTitleLabel: TLabel;
    FRefreshBtn: TButton;
    FFilterCombo: TComboBox;
    FGrid: TStringGrid;
    FActionPanel: TPanel;
    FApproveBtn: TButton;
    FRejectBtn: TButton;
    FNegotiateBtn: TButton;
    FStatusBar: TPanel;
    FStatusText: TLabel;
    // Yellow-light negotiation panel
    FNegotiationPanel: TPanel;
    FNegotiationMemo: TMemo;
    FNegotiationSubmitBtn: TButton;
    FNegotiationCancelBtn: TButton;
    FCurrentEventId: string;

    procedure SetupControls;
    procedure LoadAutoTuneEvents;
    procedure RefreshBtnClick(Sender: TObject);
    procedure FilterComboChange(Sender: TObject);
    procedure ApproveBtnClick(Sender: TObject);
    procedure RejectBtnClick(Sender: TObject);
    procedure NegotiateBtnClick(Sender: TObject);
    procedure NegotiationSubmitBtnClick(Sender: TObject);
    procedure NegotiationCancelBtnClick(Sender: TObject);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    function GetSelectedEventId: string;
    procedure ShowNegotiationPanel;
    procedure HideNegotiationPanel;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TAutoTuneAuditProvider = class(TInterfacedObject, IShellMainViewProvider)
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
  ArtifactOS.Core.AutoTune;

{ ── TAutoTuneAuditFrame ──────────────────────────────────────────── }

constructor TAutoTuneAuditFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetupControls;
  LoadAutoTuneEvents;
end;

procedure TAutoTuneAuditFrame.SetupControls;
begin
  // Header
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
  FTitleLabel.Caption := 'AutoTune Audit';

  FFilterCombo := TComboBox.Create(FHeader);
  FFilterCombo.Parent := FHeader;
  FFilterCombo.Left := 200;
  FFilterCombo.Top := 10;
  FFilterCombo.Width := 160;
  FFilterCombo.Style := csDropDownList;
  FFilterCombo.Items.Add('All');
  FFilterCombo.Items.Add('Review Required');
  FFilterCombo.Items.Add('Digest');
  FFilterCombo.Items.Add('Low Risk');
  FFilterCombo.Items.Add('Medium Risk');
  FFilterCombo.Items.Add('High Risk');
  FFilterCombo.ItemIndex := 0;
  FFilterCombo.OnChange := FilterComboChange;

  FRefreshBtn := TButton.Create(FHeader);
  FRefreshBtn.Parent := FHeader;
  FRefreshBtn.AlignWithMargins := True;
  FRefreshBtn.Align := alRight;
  FRefreshBtn.Width := 80;
  FRefreshBtn.Caption := 'Refresh';
  FRefreshBtn.OnClick := RefreshBtnClick;

  // Grid — AutoTune events
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

  FGrid.Cells[0, 0] := 'Risk';
  FGrid.Cells[1, 0] := 'Parameter';
  FGrid.Cells[2, 0] := 'Before';
  FGrid.Cells[3, 0] := 'After';
  FGrid.Cells[4, 0] := 'Visible';
  FGrid.Cells[5, 0] := 'Target';
  FGrid.Cells[6, 0] := 'Time';
  FGrid.Cells[7, 0] := 'Status';
  FGrid.ColWidths[0] := 60;
  FGrid.ColWidths[1] := 220;
  FGrid.ColWidths[2] := 80;
  FGrid.ColWidths[3] := 80;
  FGrid.ColWidths[4] := 80;
  FGrid.ColWidths[5] := 120;
  FGrid.ColWidths[6] := 140;
  FGrid.ColWidths[7] := 80;

  // Action panel
  FActionPanel := TPanel.Create(Self);
  FActionPanel.Parent := Self;
  FActionPanel.Align := alBottom;
  FActionPanel.Height := 44;
  FActionPanel.BevelOuter := bvNone;

  FApproveBtn := TButton.Create(FActionPanel);
  FApproveBtn.Parent := FActionPanel;
  FApproveBtn.Left := 12;
  FApproveBtn.Top := 8;
  FApproveBtn.Width := 100;
  FApproveBtn.Height := 28;
  FApproveBtn.Caption := 'Approve';
  FApproveBtn.Enabled := False;
  FApproveBtn.OnClick := ApproveBtnClick;

  FRejectBtn := TButton.Create(FActionPanel);
  FRejectBtn.Parent := FActionPanel;
  FRejectBtn.Left := 120;
  FRejectBtn.Top := 8;
  FRejectBtn.Width := 100;
  FRejectBtn.Height := 28;
  FRejectBtn.Caption := 'Reject';
  FRejectBtn.Enabled := False;
  FRejectBtn.OnClick := RejectBtnClick;

  FNegotiateBtn := TButton.Create(FActionPanel);
  FNegotiateBtn.Parent := FActionPanel;
  FNegotiateBtn.Left := 228;
  FNegotiateBtn.Top := 8;
  FNegotiateBtn.Width := 120;
  FNegotiateBtn.Height := 28;
  FNegotiateBtn.Caption := 'Negotiate';
  FNegotiateBtn.Enabled := False;
  FNegotiateBtn.OnClick := NegotiateBtnClick;

  // Negotiation panel (initially hidden)
  FNegotiationPanel := TPanel.Create(Self);
  FNegotiationPanel.Parent := Self;
  FNegotiationPanel.Align := alBottom;
  FNegotiationPanel.Height := 120;
  FNegotiationPanel.BevelOuter := bvNone;
  FNegotiationPanel.Visible := False;

  FNegotiationMemo := TMemo.Create(FNegotiationPanel);
  FNegotiationMemo.Parent := FNegotiationPanel;
  FNegotiationMemo.Align := alClient;
  FNegotiationMemo.Lines.Clear;
  FNegotiationMemo.Text := 'Enter your feedback or proposed adjustment...';

  FNegotiationSubmitBtn := TButton.Create(FNegotiationPanel);
  FNegotiationSubmitBtn.Parent := FNegotiationPanel;
  FNegotiationSubmitBtn.Align := alRight;
  FNegotiationSubmitBtn.Width := 80;
  FNegotiationSubmitBtn.Caption := 'Submit';
  FNegotiationSubmitBtn.OnClick := NegotiationSubmitBtnClick;

  FNegotiationCancelBtn := TButton.Create(FNegotiationPanel);
  FNegotiationCancelBtn.Parent := FNegotiationPanel;
  FNegotiationCancelBtn.Align := alRight;
  FNegotiationCancelBtn.Width := 80;
  FNegotiationCancelBtn.Caption := 'Cancel';
  FNegotiationCancelBtn.OnClick := NegotiationCancelBtnClick;

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

procedure TAutoTuneAuditFrame.LoadAutoTuneEvents;
var
  DB: TArtifactDB;
  Rows: string;
  JArr: TJSONArray;
  JObj: TJSONObject;
  I, Row: Integer;
  FilterClause: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    case FFilterCombo.ItemIndex of
      1: FilterClause := 'WHERE requires_human_review=true';
      2: FilterClause := 'WHERE human_visible_level=''digest''';
      3: FilterClause := 'WHERE risk_level=''low''';
      4: FilterClause := 'WHERE risk_level=''medium''';
      5: FilterClause := 'WHERE risk_level=''high''';
    else
      FilterClause := '';
    end;

    Rows := DB.ExecuteScalarJson(
      'SELECT COALESCE(json_agg(row_to_json(t))::text, ''[]'') FROM (' +
      'SELECT id::text, risk_level, parameter_path, before_value, after_value, ' +
      '  human_visible_level, target_type || '':'' || COALESCE(target_id::text,''-'') as target, ' +
      '  to_char(effective_from, ''YYYY-MM-DD HH24:MI'') as time, ' +
      '  CASE WHEN effective_to IS NULL THEN ''active'' ELSE ''expired'' END as status ' +
      'FROM artifactos.auto_tune_event ' + FilterClause +
      ' ORDER BY created_at DESC LIMIT 50' +
      ') t', '{}');

    JArr := TJSONObject.ParseJSONValue(Rows) as TJSONArray;
    if (JArr = nil) or (JArr.Count = 0) then
    begin
      if JArr <> nil then JArr.Free;
      FGrid.RowCount := 2;
      FGrid.Cells[0, 1] := '-';
      FGrid.Cells[1, 1] := '(no auto-tune events)';
      FStatusText.Caption := 'No auto-tune events';
      Exit;
    end;

    try
      FGrid.RowCount := JArr.Count + 1;
      for I := 0 to JArr.Count - 1 do
      begin
        JObj := JArr.Items[I] as TJSONObject;
        Row := I + 1;
        FGrid.Cells[0, Row] := JObj.GetValue<string>('risk_level', 'low');
        FGrid.Cells[1, Row] := JObj.GetValue<string>('parameter_path', '');
        FGrid.Cells[2, Row] := JObj.GetValue<string>('before_value', '');
        FGrid.Cells[3, Row] := JObj.GetValue<string>('after_value', '');
        FGrid.Cells[4, Row] := JObj.GetValue<string>('human_visible_level', '');
        FGrid.Cells[5, Row] := JObj.GetValue<string>('target', '');
        FGrid.Cells[6, Row] := JObj.GetValue<string>('time', '');
        FGrid.Cells[7, Row] := JObj.GetValue<string>('status', '');
        // Store event ID in a hidden convention: tag the row
        FGrid.Objects[0, Row] := TObject(Pointer(NativeUInt(I)));
      end;
      FStatusText.Caption := IntToStr(JArr.Count) + ' auto-tune events loaded';
    finally
      JArr.Free;
    end;
  finally
    DB.Disconnect;
  end;
end;

procedure TAutoTuneAuditFrame.RefreshBtnClick(Sender: TObject);
begin
  FStatusText.Caption := 'Refreshing...';
  LoadAutoTuneEvents;
end;

procedure TAutoTuneAuditFrame.FilterComboChange(Sender: TObject);
begin
  LoadAutoTuneEvents;
end;

function TAutoTuneAuditFrame.GetSelectedEventId: string;
var
  DB: TArtifactDB;
  ParamPath: string;
begin
  Result := '';
  if FGrid.Row < 1 then Exit;
  ParamPath := FGrid.Cells[1, FGrid.Row];

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var Params := '{"path":"' + ParamPath + '"}';
    Result := DB.ExecuteScalarJson(
      'SELECT id::text FROM artifactos.auto_tune_event ' +
      'WHERE parameter_path=:path ' +
      'ORDER BY created_at DESC LIMIT 1', Params);
  finally
    DB.Disconnect;
  end;
end;

procedure TAutoTuneAuditFrame.GridSelectCell(Sender: TObject;
  ACol, ARow: Integer; var CanSelect: Boolean);
begin
  FApproveBtn.Enabled := ARow >= 1;
  FRejectBtn.Enabled := ARow >= 1;
  FNegotiateBtn.Enabled := ARow >= 1;
end;

procedure TAutoTuneAuditFrame.ApproveBtnClick(Sender: TObject);
var
  DB: TArtifactDB;
  EventId: string;
begin
  EventId := GetSelectedEventId;
  if EventId = '' then begin
    FStatusText.Caption := 'No event selected';
    Exit;
  end;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var Params := '{"id":"' + EventId + '"}';
    // Confirm the auto-tune — mark as reviewed, keep effective
    DB.ExecuteJson(
      'UPDATE artifactos.auto_tune_event SET ' +
      '  requires_human_review=false, ' +
      '  human_visible_level=''digest'', ' +
      '  metadata=jsonb_set(COALESCE(metadata,''{}''), ''{human_action}'', ''"approved"'') ' +
      'WHERE id=:id::uuid', Params);
  finally
    DB.Disconnect;
  end;

  FStatusText.Caption := 'Approved: ' + Copy(EventId, 1, 8);
  LoadAutoTuneEvents;
end;

procedure TAutoTuneAuditFrame.RejectBtnClick(Sender: TObject);
var
  DB: TArtifactDB;
  EventId: string;
begin
  EventId := GetSelectedEventId;
  if EventId = '' then begin
    FStatusText.Caption := 'No event selected';
    Exit;
  end;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    var Params := '{"id":"' + EventId + '"}';
    // Set effective_to to now — disabling the auto-tune
    DB.ExecuteJson(
      'UPDATE artifactos.auto_tune_event SET ' +
      '  effective_to=now(), ' +
      '  metadata=jsonb_set(COALESCE(metadata,''{}''), ''{human_action}'', ''"rejected"'') ' +
      'WHERE id=:id::uuid', Params);
  finally
    DB.Disconnect;
  end;

  FStatusText.Caption := 'Rejected (rolled back): ' + Copy(EventId, 1, 8);
  LoadAutoTuneEvents;
end;

procedure TAutoTuneAuditFrame.NegotiateBtnClick(Sender: TObject);
begin
  FCurrentEventId := GetSelectedEventId;
  if FCurrentEventId = '' then begin
    FStatusText.Caption := 'No event selected';
    Exit;
  end;

  ShowNegotiationPanel;
  FStatusText.Caption := 'Negotiating: ' + Copy(FCurrentEventId, 1, 8);
end;

procedure TAutoTuneAuditFrame.NegotiationSubmitBtnClick(Sender: TObject);
var
  DB: TArtifactDB;
  Feedback: string;
begin
  Feedback := FNegotiationMemo.Text;
  if Feedback = '' then begin
    FStatusText.Caption := 'Please enter feedback';
    Exit;
  end;

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    // Store human negotiation feedback in metadata
    var Params := '{"id":"' + FCurrentEventId + '", "fb":"' + Feedback + '"}';
    DB.ExecuteJson(
      'UPDATE artifactos.auto_tune_event SET ' +
      '  requires_human_review=true, ' +
      '  metadata=jsonb_set(jsonb_set(COALESCE(metadata,''{}''), ' +
      '    ''{human_action}'', ''"negotiated"''), ' +
      '    ''{negotiation_feedback}'', to_jsonb(:fb::text)) ' +
      'WHERE id=:id::uuid', Params);
  finally
    DB.Disconnect;
  end;

  HideNegotiationPanel;
  FStatusText.Caption := 'Negotiation submitted for: ' + Copy(FCurrentEventId, 1, 8);
  FCurrentEventId := '';
  LoadAutoTuneEvents;
end;

procedure TAutoTuneAuditFrame.NegotiationCancelBtnClick(Sender: TObject);
begin
  HideNegotiationPanel;
  FCurrentEventId := '';
  FStatusText.Caption := 'Negotiation cancelled';
end;

procedure TAutoTuneAuditFrame.ShowNegotiationPanel;
begin
  FNegotiationPanel.Visible := True;
  FNegotiationMemo.SetFocus;
  FNegotiationMemo.SelectAll;
end;

procedure TAutoTuneAuditFrame.HideNegotiationPanel;
begin
  FNegotiationPanel.Visible := False;
  FNegotiationMemo.Lines.Clear;
end;

{ ── TAutoTuneAuditProvider ───────────────────────────────────────── }

function TAutoTuneAuditProvider.ProviderId: string;
begin
  Result := 'autotune_audit';
end;

function TAutoTuneAuditProvider.CanOpen(const ARef: TShellObjectRef): Boolean;
begin
  Result := (ARef.Kind = 'view') and (ARef.Id = 'autotune_audit');
end;

function TAutoTuneAuditProvider.GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
begin
  Result := TShellViewInfo.Make('autotune_audit', svkControl, 'AutoTune Audit', '');
end;

function TAutoTuneAuditProvider.CreateViewControl(AOwner: TComponent;
  const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
begin
  Result := TAutoTuneAuditFrame.Create(AOwner);
end;

end.
