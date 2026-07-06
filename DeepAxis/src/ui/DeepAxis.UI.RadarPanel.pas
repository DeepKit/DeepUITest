unit DeepAxis.UI.RadarPanel;

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, System.Math, System.JSON,
  System.Generics.Collections, System.Generics.Defaults,
  Winapi.Windows,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Forms,
  DeepBase.AIErrorHandler,
  DeepAxis.Core.Base, DeepAxis.Core.DataTypes, DeepAxis.Core.Contracts,
  DeepAxis.Pipeline.Privacy,
  DeepAxis.WeChat.MsgParser;

type
  /// <summary>
  ///   Background thread for incremental WeChat SQLite polling.
  ///   Polls at foreground (5s) or background (60s) intervals.
  ///   Triggers the full pipeline: Reader → Metrics → Radar → Evidence → Tags.
  /// </summary>
  TDBPollerDataEvent = procedure(Sender: TObject; const AData: TPollResult) of object;

  TDBPollerThread = class(TThread)
  private
    FReader: IWxReader;
    FMetricCalc: IMetricCalculator;
    FRadarEngine: IRadarEngine;
    FEvidenceBuilder: IEvidenceBuilder;
    FTagEngine: ITagEngine;
    FIdleFunnel: IIdleFunnel;
    FIntervalForeground: Integer;
    FIntervalBackground: Integer;
    FIsForeground: Boolean;
    FOnDataReady: TDBPollerDataEvent;
    FScanCursors: TScanCursorArray;
    FLastPollResult: TPollResult;
    FOldMetrics: TArray<TInteractionMetric>;
    FPauseEvent: THandle;
    FForcePollEvent: THandle;
    procedure DoPoll;
    procedure DoPollInner;
    procedure NotifyMainThread;
    function GenerateMessagePreview(const AMessages: TArray<TMessageMeta>): string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AReader: IWxReader; const AMetricCalc: IMetricCalculator;
      const ARadarEngine: IRadarEngine; const AEvidenceBuilder: IEvidenceBuilder;
      const ATagEngine: ITagEngine; const AIdleFunnel: IIdleFunnel);
    destructor Destroy; override;
    procedure ForcePoll;
    procedure SetForeground(AValue: Boolean);
    property OnDataReady: TDBPollerDataEvent read FOnDataReady write FOnDataReady;
    property LastPollResult: TPollResult read FLastPollResult;
  end;

  /// <summary>
  ///   280px vertical strip panel — the primary DeepAxis user interface.
  ///   Three zones: ① top stats, ② contact list, ③ detail panel.
  ///   Docked to the right of the WeChat window.
  /// </summary>
  TDeepAxisRadarPanel = class(TPanel)
  private
    // Zone ①: Top stats
    FTitleLabel: TLabel;
    FStatsPanel: TPanel;
    FFollowUpLabel: TLabel;
    FReplyLabel: TLabel;
    FCoolingLabel: TLabel;
    FIdleLabel: TLabel;
    FStatusLabel: TLabel;

    // Zone ②: Separator
    FSeparator: TPanel;

    // Zone ③: Bottom container
    FBottomPanel: TPanel;
    FSearchPanel: TPanel;              // Search bar container
    FSearchEdit: TEdit;                // Contact search/filter
    FSearchClearBtn: TButton;          // Clear search
    FContactListBox: TListBox;
    FDetailPanel: TPanel;

    // Detail panel contents
    FContactNameLabel: TLabel;
    FHintTypeLabel: TLabel;
    FLastInteractionLabel: TLabel;
    FConfidenceLabel: TLabel;
    FEvidenceMemo: TMemo;

    // Data
    FCurrentData: TPollResult;
    FSelectedContactIndex: Integer;
    FListBoxRowToHintIndex: TArray<Integer>;  // maps list row → hint index
    FWeChatConnected: Boolean;
    FEmptyGuideLabel: TLabel;  // shown when no hints/contacts

    procedure BuildUI;
    procedure UpdateStats;
    procedure UpdateContactList;
    procedure UpdateDetail;
    procedure OnContactListClick(Sender: TObject);
    procedure OnSearchChange(Sender: TObject);
    procedure OnSearchClear(Sender: TObject);
    procedure OnStatsLabelClick(Sender: TObject);
    function GetSearchFilter: string;
    function GetHintTypeColor(const AHintType: TRadarHintType): TColor;
    function GetHintTypeEmoji(const AHintType: TRadarHintType): string;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetData(const AData: TPollResult);
    procedure SetWeChatConnected(AConnected: Boolean);
    procedure Clear;
    procedure FocusSearch;
    function TryGetSelectedContact(out AContact: TContact): Boolean;
    function IsConnected: Boolean;
    property SelectedContactIndex: Integer read FSelectedContactIndex;
  end;

implementation

{ TDBPollerThread }

constructor TDBPollerThread.Create(const AReader: IWxReader;
  const AMetricCalc: IMetricCalculator; const ARadarEngine: IRadarEngine;
  const AEvidenceBuilder: IEvidenceBuilder; const ATagEngine: ITagEngine;
  const AIdleFunnel: IIdleFunnel);
begin
  inherited Create(True); // create suspended
  FReader := AReader;
  FMetricCalc := AMetricCalc;
  FRadarEngine := ARadarEngine;
  FEvidenceBuilder := AEvidenceBuilder;
  FTagEngine := ATagEngine;
  FIdleFunnel := AIdleFunnel;
  FIntervalForeground := POLL_INTERVAL_FOREGROUND;
  FIntervalBackground := POLL_INTERVAL_BACKGROUND;
  FIsForeground := True;
  FreeOnTerminate := False;
  FPauseEvent := CreateEvent(nil, True, False, nil);
  FForcePollEvent := CreateEvent(nil, True, False, nil);
end;

destructor TDBPollerThread.Destroy;
begin
  CloseHandle(FPauseEvent);
  CloseHandle(FForcePollEvent);
  inherited;
end;

procedure TDBPollerThread.SetForeground(AValue: Boolean);
begin
  FIsForeground := AValue;
end;

procedure TDBPollerThread.ForcePoll;
begin
  SetEvent(FForcePollEvent);
end;

function TDBPollerThread.GenerateMessagePreview(const AMessages: TArray<TMessageMeta>): string;
var
  LMsg: TMessageMeta;
  LParsed: TParsedMessage;
  LPreview: string;
  LCount: Integer;
begin
  Result := '';
  LCount := 0;

  // Take last 3 messages for preview
  for LMsg in AMessages do
  begin
    if LCount >= 3 then Break;

    LParsed := TMessageParser.Parse(LMsg);

    case LParsed.ContentType of
      pctText:
        LPreview := Copy(LParsed.TextBody, 1, 50);
      pctImage:
        LPreview := '[图片]';
      pctVideo:
        LPreview := '[视频]';
      pctVoice:
        LPreview := '[语音]';
      pctLink:
        LPreview := '[链接] ' + Copy(LParsed.Link.Title, 1, 30);
      pctEmoji:
        LPreview := '[表情]';
      pctSystem:
        LPreview := Copy(LParsed.TextBody, 1, 50);
      pctLocation:
        LPreview := '[位置] ' + Copy(LParsed.Location.LocationLabel, 1, 30);
      pctContactCard:
        LPreview := '[名片] ' + Copy(LParsed.ContactCard.Nickname, 1, 30);
      pctRecall:
        LPreview := '[撤回]';
    else
      LPreview := '[消息]';
    end;

    // Add direction indicator
    if LMsg.Direction = dOutbound then
      LPreview := '→ ' + LPreview
    else if LMsg.Direction = dInbound then
      LPreview := '← ' + LPreview;

    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + LPreview;
    Inc(LCount);
  end;
end;

procedure TDBPollerThread.DoPoll;
begin
  SafeRun('轮询数据', DoPollInner);
end;

procedure TDBPollerThread.DoPollInner;
var
  LContacts: TArray<TContact>;
  LAllMessages: TArray<TMessageMeta>;
  LMetrics: TArray<TInteractionMetric>;
  LHints: TArray<TRadarHint>;
  LEvidence: TArray<TEvidenceRecord>;
  LTaggedContacts: TArray<TContact>;
  LResult: TPollResult;
  LContact: TContact;
  LCursor: TScanCursor;
  LContactMessages: TArray<TMessageMeta>;
  LMsg: TMessageMeta;
  I: Integer;
  LCursorFound: Boolean;
begin
  if not FReader.IsOpen then
    Exit;

  LResult := Default(TPollResult);

  try
    // Step 1: Read contacts
    LContacts := FReader.ReadContacts;

    // Step 1.5: 隐私分类 — 过滤 PRIVATE/UNKNOWN 联系人
    var LPrivacy := TPrivacyClassifier.Create;
    try
      LContacts := LPrivacy.ClassifyBatch(LContacts, nil);
    finally
      LPrivacy.Free;
    end;

    // Step 2: Read new messages for each contact (incremental)
    SetLength(LAllMessages, 0);
    for LContact in LContacts do
    begin
      LCursor := Default(TScanCursor);
      LCursor.ContactId := LContact.ContactId;
      // Find existing cursor
      LCursorFound := False;
      for I := 0 to Length(FScanCursors) - 1 do
        if FScanCursors[I].ContactId = LContact.ContactId then
        begin
          LCursor := FScanCursors[I];
          LCursorFound := True;
          Break;
        end;

      LContactMessages := FReader.ReadMessages(LContact.ContactId, LCursor);
      for LMsg in LContactMessages do
      begin
        SetLength(LAllMessages, Length(LAllMessages) + 1);
        LAllMessages[High(LAllMessages)] := LMsg;
      end;

      // Update cursor
      if Length(LContactMessages) > 0 then
      begin
        LCursor.LastLocalId := LContactMessages[High(LContactMessages)].SourceRowRef.ToInt64;
        LCursor.LastCreateTime := DateTimeToUnix(LContactMessages[High(LContactMessages)].SentAt);
        // Update in cursors array
        for I := 0 to Length(FScanCursors) - 1 do
          if FScanCursors[I].ContactId = LContact.ContactId then
          begin
            FScanCursors[I] := LCursor;
            LCursorFound := True;
            Break;
          end;
        if not LCursorFound then
        begin
          SetLength(FScanCursors, Length(FScanCursors) + 1);
          FScanCursors[High(FScanCursors)] := LCursor;
        end;
      end;
    end;

    // Step 3: Compute metrics and build per-contact message dictionary
    SetLength(LMetrics, Length(LContacts));
    var LMsgDict := TDictionary<string, TArray<TMessageMeta>>.Create;
    try
      for I := 0 to Length(LContacts) - 1 do
      begin
        LContactMessages := nil;
        for LMsg in LAllMessages do
          if LMsg.ContactId = LContacts[I].ContactId then
          begin
            SetLength(LContactMessages, Length(LContactMessages) + 1);
            LContactMessages[High(LContactMessages)] := LMsg;
          end;
        LMetrics[I] := FMetricCalc.Compute(LContactMessages,
          Default(TInteractionMetric));
        LMetrics[I].ContactId := LContacts[I].ContactId;

        // Store for tag derivation
        if Length(LContactMessages) > 0 then
        begin
          LMsgDict.AddOrSetValue(LContacts[I].ContactId, LContactMessages);
          // Generate message preview for UI display
          LContacts[I].MessagePreview := GenerateMessagePreview(LContactMessages);
        end;
      end;

      // Step 4: Derive tags with message content
      LTaggedContacts := FTagEngine.DeriveTagsBatch(LContacts, LMetrics, LMsgDict);
    finally
      LMsgDict.Free;
    end;

    // Step 5: Classify idle funnel
    LTaggedContacts := FIdleFunnel.ClassifyContacts(LTaggedContacts);

    // Step 6: Generate radar hints (with historical metrics for cooling/reactivated)
    LHints := FRadarEngine.Generate(LMetrics, LTaggedContacts, FOldMetrics);

    // Save metrics as history for next poll cycle
    FOldMetrics := Copy(LMetrics);

    // Step 7: Build evidence
    SetLength(LEvidence, 0);
    for I := 0 to Length(LHints) - 1 do
    begin
      var LHintEvidence := FEvidenceBuilder.Build(LHints[I], LMetrics);
      for var LE in LHintEvidence do
      begin
        SetLength(LEvidence, Length(LEvidence) + 1);
        LEvidence[High(LEvidence)] := LE;
      end;
    end;

    // Build result
    LResult.Contacts := LTaggedContacts;
    LResult.Metrics := LMetrics;
    LResult.Hints := LHints;
    LResult.EvidenceRecords := LEvidence;
    LResult.NewMessageCount := Length(LAllMessages);
    LResult.UpdatedAt := Now;

    FLastPollResult := LResult;
  except
    on E: Exception do
    begin
      LResult.NewMessageCount := -1;
      FLastPollResult := LResult;
      TThread.Queue(Self,
        procedure
        begin
          if (not Terminated) and Assigned(FOnDataReady) then
            FOnDataReady(Self, LResult);
        end);
    end;
  end;
end;

procedure TDBPollerThread.NotifyMainThread;
var
  LCopy: TPollResult;
begin
  if not Assigned(FOnDataReady) then Exit;
  // 深拷贝快照，切断与后台线程的引用共享
  LCopy.Contacts := Copy(FLastPollResult.Contacts);
  LCopy.Metrics := Copy(FLastPollResult.Metrics);
  LCopy.Hints := Copy(FLastPollResult.Hints);
  LCopy.EvidenceRecords := Copy(FLastPollResult.EvidenceRecords);
  LCopy.AuditEvents := Copy(FLastPollResult.AuditEvents);
  LCopy.NewMessageCount := FLastPollResult.NewMessageCount;
  LCopy.UpdatedAt := FLastPollResult.UpdatedAt;
  TThread.Queue(Self,
    procedure
    begin
      if (not Terminated) and Assigned(FOnDataReady) then
        FOnDataReady(Self, LCopy);
    end);
end;

procedure TDBPollerThread.Execute;
var
  LInterval: Integer;
  LHandles: array[0..1] of THandle;
  LWaitResult: Cardinal;
begin
  try
    while not Terminated do
    begin
      LInterval := 2000;
      if FIsForeground then
        LInterval := FIntervalForeground
      else
        LInterval := FIntervalBackground;

    LHandles[0] := FForcePollEvent;
    LHandles[1] := FPauseEvent;

    LWaitResult := WaitForMultipleObjects(2, @LHandles[0], False, LInterval);

    if Terminated then
      Break;

    case LWaitResult of
      WAIT_OBJECT_0: // Force poll
        begin
          ResetEvent(FForcePollEvent);
          DoPoll;
          NotifyMainThread;
        end;
      WAIT_OBJECT_0 + 1: // Pause
        begin
          ResetEvent(FPauseEvent);
          Continue;
        end;
      WAIT_TIMEOUT: // Regular poll interval
        begin
          DoPoll;
          NotifyMainThread;
        end;
    end;
  end;
  except
    on E: Exception do
      TThread.Queue(Self, procedure begin end);
  end;
end;

{ TDeepAxisRadarPanel }

constructor TDeepAxisRadarPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedContactIndex := -1;
  FWeChatConnected := False;
  BuildUI;
end;

function TDeepAxisRadarPanel.GetHintTypeColor(const AHintType: TRadarHintType): TColor;
begin
  case AHintType of
    rhtCooling:          Result := $0080C0FF; // orange-ish
    rhtLongSilence:      Result := $006060FF; // red-ish
    rhtReactivated:      Result := $0080FF80; // green-ish
    rhtOutboundHeavy:    Result := $00FFB0B0; // pink-ish
    rhtDataInsufficient: Result := clGray;
    rhtHighLinkSharing:  Result := $00FFD080; // blue-ish (link sharing)
    rhtMarketingPattern: Result := $00C080FF; // purple-ish (marketing)
  else
    Result := clGray;
  end;
end;

function TDeepAxisRadarPanel.GetHintTypeEmoji(const AHintType: TRadarHintType): string;
begin
  case AHintType of
    rhtCooling:          Result := '🟡';
    rhtLongSilence:      Result := '🔴';
    rhtReactivated:      Result := '🟢';
    rhtOutboundHeavy:    Result := '🟠';
    rhtDataInsufficient: Result := '⚪';
    rhtHighLinkSharing:  Result := '🔗';
    rhtMarketingPattern: Result := '📢';
  else
    Result := '';
  end;
end;

procedure TDeepAxisRadarPanel.BuildUI;
begin
  Self.BevelOuter := bvNone;
  Self.Width := DEEPAXIS_STRIP_WIDTH;
  Self.Caption := '';

  // ── Zone ①: Top stats ─────────────────────────────────────────

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.Caption := APP_TITLE + ' ' + APP_TITLE_ZH;
  FTitleLabel.Height := 24;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alTop;
  FStatusLabel.Caption := '未连接微信';
  FStatusLabel.Height := 16;

  FStatsPanel := TPanel.Create(Self);
  FStatsPanel.Parent := Self;
  FStatsPanel.Align := alTop;
  FStatsPanel.Height := 120;
  FStatsPanel.BevelOuter := bvNone;

  FFollowUpLabel := TLabel.Create(FStatsPanel);
  FFollowUpLabel.Parent := FStatsPanel;
  FFollowUpLabel.Align := alTop;
  FFollowUpLabel.Caption := '待跟进: 0人';
  FFollowUpLabel.Height := 28;
  FFollowUpLabel.Cursor := crHandPoint;
  FFollowUpLabel.Tag := 10;  // filter: cooling + long_silence
  FFollowUpLabel.OnClick := OnStatsLabelClick;
  FFollowUpLabel.Hint := '点击筛选待跟进联系人';
  FFollowUpLabel.ShowHint := True;

  FReplyLabel := TLabel.Create(FStatsPanel);
  FReplyLabel.Parent := FStatsPanel;
  FReplyLabel.Align := alTop;
  FReplyLabel.Caption := '待回复: 0人';
  FReplyLabel.Height := 20;
  FReplyLabel.Cursor := crHandPoint;
  FReplyLabel.Tag := 11;  // filter: reactivated
  FReplyLabel.OnClick := OnStatsLabelClick;
  FReplyLabel.Hint := '点击筛选待回复联系人';
  FReplyLabel.ShowHint := True;

  FCoolingLabel := TLabel.Create(FStatsPanel);
  FCoolingLabel.Parent := FStatsPanel;
  FCoolingLabel.Align := alTop;
  FCoolingLabel.Caption := '降温预警: 0人';
  FCoolingLabel.Height := 20;
  FCoolingLabel.Cursor := crHandPoint;
  FCoolingLabel.Tag := 12;  // filter: cooling only
  FCoolingLabel.OnClick := OnStatsLabelClick;
  FCoolingLabel.Hint := '点击筛选降温预警联系人';
  FCoolingLabel.ShowHint := True;

  FIdleLabel := TLabel.Create(FStatsPanel);
  FIdleLabel.Parent := FStatsPanel;
  FIdleLabel.Align := alTop;
  FIdleLabel.Caption := '闲人可广告: 0人';
  FIdleLabel.Height := 20;
  FIdleLabel.Cursor := crHandPoint;
  FIdleLabel.Tag := 13;  // filter: idle
  FIdleLabel.OnClick := OnStatsLabelClick;
  FIdleLabel.Hint := '点击筛选空闲联系人';
  FIdleLabel.ShowHint := True;

  // ── Separator ──────────────────────────────────────────────────

  FSeparator := TPanel.Create(Self);
  FSeparator.Parent := Self;
  FSeparator.Align := alTop;
  FSeparator.Height := 2;
  FSeparator.BevelOuter := bvLowered;

  // ── Zone ③: Bottom panel ──────────────────────────────────────

  FBottomPanel := TPanel.Create(Self);
  FBottomPanel.Parent := Self;
  FBottomPanel.Align := alClient;
  FBottomPanel.BevelOuter := bvNone;

  // Contact list (left ~126px)
  FContactListBox := TListBox.Create(FBottomPanel);
  FContactListBox.Parent := FBottomPanel;
  FContactListBox.Align := alLeft;
  FContactListBox.Width := 126;
  FContactListBox.OnClick := OnContactListClick;

  // Search panel (above contact list)
  FSearchPanel := TPanel.Create(FBottomPanel);
  FSearchPanel.Parent := FBottomPanel;
  FSearchPanel.Align := alTop;
  FSearchPanel.Height := 24;
  FSearchPanel.BevelOuter := bvNone;
  FSearchPanel.Padding.Left := 2;
  FSearchPanel.Padding.Right := 2;
  FSearchPanel.Padding.Top := 1;

  FSearchEdit := TEdit.Create(FSearchPanel);
  FSearchEdit.Parent := FSearchPanel;
  FSearchEdit.Align := alClient;
  FSearchEdit.Top := 1;
  FSearchEdit.Left := 2;
  FSearchEdit.Height := 22;
  FSearchEdit.TextHint := '搜索联系人...';
  FSearchEdit.OnChange := OnSearchChange;
  FSearchEdit.TabStop := False;

  FSearchClearBtn := TButton.Create(FSearchPanel);
  FSearchClearBtn.Parent := FSearchPanel;
  FSearchClearBtn.Align := alRight;
  FSearchClearBtn.Top := 1;
  FSearchClearBtn.Width := 22;
  FSearchClearBtn.Height := 22;
  FSearchClearBtn.Caption := '×';
  FSearchClearBtn.Hint := '清除搜索';
  FSearchClearBtn.ShowHint := True;
  FSearchClearBtn.OnClick := OnSearchClear;
  FSearchClearBtn.TabStop := False;
  FSearchClearBtn.Visible := False;

  // Detail panel (right ~154px)
  FDetailPanel := TPanel.Create(FBottomPanel);
  FDetailPanel.Parent := FBottomPanel;
  FDetailPanel.Align := alClient;
  FDetailPanel.BevelOuter := bvNone;

  FContactNameLabel := TLabel.Create(FDetailPanel);
  FContactNameLabel.Parent := FDetailPanel;
  FContactNameLabel.Align := alTop;
  FContactNameLabel.Caption := '选择联系人查看详情';
  FContactNameLabel.Height := 22;

  FHintTypeLabel := TLabel.Create(FDetailPanel);
  FHintTypeLabel.Parent := FDetailPanel;
  FHintTypeLabel.Align := alTop;
  FHintTypeLabel.Caption := '';
  FHintTypeLabel.Height := 18;

  FLastInteractionLabel := TLabel.Create(FDetailPanel);
  FLastInteractionLabel.Parent := FDetailPanel;
  FLastInteractionLabel.Align := alTop;
  FLastInteractionLabel.Caption := '';
  FLastInteractionLabel.Height := 16;

  FConfidenceLabel := TLabel.Create(FDetailPanel);
  FConfidenceLabel.Parent := FDetailPanel;
  FConfidenceLabel.Align := alTop;
  FConfidenceLabel.Caption := '';
  FConfidenceLabel.Height := 16;

  FEvidenceMemo := TMemo.Create(FDetailPanel);
  FEvidenceMemo.Parent := FDetailPanel;
  FEvidenceMemo.Align := alClient;
  FEvidenceMemo.ReadOnly := True;
  FEvidenceMemo.ScrollBars := ssVertical;
  FEvidenceMemo.Visible := False;

  // Empty state guide (overlay on bottom panel when no data)
  FEmptyGuideLabel := TLabel.Create(FBottomPanel);
  FEmptyGuideLabel.Parent := FBottomPanel;
  FEmptyGuideLabel.Align := alClient;
  FEmptyGuideLabel.Alignment := taCenter;
  FEmptyGuideLabel.Layout := tlCenter;
  FEmptyGuideLabel.WordWrap := True;
  FEmptyGuideLabel.Font.Size := 11;
  FEmptyGuideLabel.Font.Color := clGray;
  FEmptyGuideLabel.Caption := '正在等待数据...';
  FEmptyGuideLabel.Visible := True;
end;

procedure TDeepAxisRadarPanel.OnContactListClick(Sender: TObject);
var
  LRowIdx: Integer;
begin
  LRowIdx := FContactListBox.ItemIndex;
  // Map list row index to hint index using the pre-built mapping
  if (LRowIdx >= 0) and (LRowIdx < Length(FListBoxRowToHintIndex)) then
    FSelectedContactIndex := FListBoxRowToHintIndex[LRowIdx]
  else
    FSelectedContactIndex := -1;
  UpdateDetail;
end;

function TDeepAxisRadarPanel.GetSearchFilter: string;
begin
  Result := Trim(FSearchEdit.Text);
end;

procedure TDeepAxisRadarPanel.OnSearchChange(Sender: TObject);
begin
  FSearchClearBtn.Visible := (FSearchEdit.Text <> '');
  FSelectedContactIndex := -1;  // clear selection on filter change
  UpdateContactList;
  if FContactListBox.Items.Count > 0 then
  begin
    FContactListBox.ItemIndex := 0;
    OnContactListClick(FContactListBox);
  end;
end;

procedure TDeepAxisRadarPanel.OnSearchClear(Sender: TObject);
begin
  FSearchEdit.Text := '';
  OnSearchChange(Sender);
end;

procedure TDeepAxisRadarPanel.OnStatsLabelClick(Sender: TObject);
var
  LTag: Integer;
  LFilter: string;
begin
  LTag := TLabel(Sender).Tag;
  // Toggle: if search already has this filter, clear it
  case LTag of
    10: LFilter := '[跟进]';     // cooling + long_silence
    11: LFilter := '[回复]';     // reactivated
    12: LFilter := '[降温]';     // cooling only
    13: LFilter := '[闲人]';     // idle
  else
    LFilter := '';
  end;

  if FSearchEdit.Text = LFilter then
    FSearchEdit.Text := ''  // toggle off
  else
    FSearchEdit.Text := LFilter;
end;

procedure TDeepAxisRadarPanel.SetData(const AData: TPollResult);
begin
  FCurrentData := AData;
  UpdateStats;
  UpdateContactList;
  UpdateDetail;
end;

procedure TDeepAxisRadarPanel.SetWeChatConnected(AConnected: Boolean);
begin
  FWeChatConnected := AConnected;
  if AConnected then
    FStatusLabel.Caption := '微信已连接'
  else
    FStatusLabel.Caption := '未连接微信';
end;

function TDeepAxisRadarPanel.TryGetSelectedContact(out AContact: TContact): Boolean;
var
  LHint: TRadarHint;
  I: Integer;
begin
  Result := False;
  AContact := Default(TContact);
  if (FSelectedContactIndex < 0) or
     (FSelectedContactIndex >= Length(FCurrentData.Hints)) then
    Exit;

  LHint := FCurrentData.Hints[FSelectedContactIndex];
  for I := 0 to Length(FCurrentData.Contacts) - 1 do
    if FCurrentData.Contacts[I].ContactId = LHint.ContactId then
    begin
      AContact := FCurrentData.Contacts[I];
      Exit(True);
    end;
end;

function TDeepAxisRadarPanel.IsConnected: Boolean;
begin
  Result := FWeChatConnected;
end;

procedure TDeepAxisRadarPanel.UpdateStats;
var
  LHint: TRadarHint;
  LCooling, LLongSilence, LReactivated, LOutboundHeavy: Integer;
  LHighLinkSharing, LMarketingPattern: Integer;
  LIdle: Integer;
  LContact: TContact;
begin
  LCooling := 0;
  LLongSilence := 0;
  LReactivated := 0;
  LOutboundHeavy := 0;
  LHighLinkSharing := 0;
  LMarketingPattern := 0;
  LIdle := 0;

  for LHint in FCurrentData.Hints do
  begin
    case LHint.HintType of
      rhtCooling:          Inc(LCooling);
      rhtLongSilence:      Inc(LLongSilence);
      rhtReactivated:      Inc(LReactivated);
      rhtOutboundHeavy:    Inc(LOutboundHeavy);
      rhtHighLinkSharing:  Inc(LHighLinkSharing);
      rhtMarketingPattern: Inc(LMarketingPattern);
    end;
  end;

  // Count idle contacts
  for LContact in FCurrentData.Contacts do
    if LContact.IsIdle then
      Inc(LIdle);

  FFollowUpLabel.Caption := Format('待跟进: %d人', [LCooling + LLongSilence]);
  FReplyLabel.Caption := Format('待回复: %d人', [LReactivated]);
  FCoolingLabel.Caption := Format('降温预警: %d人 %s', [LCooling, '🟡']);
  FIdleLabel.Caption := Format('闲人可广告: %d人', [LIdle]);

  // Content-based warnings in status if any
  if (LHighLinkSharing > 0) or (LMarketingPattern > 0) then
    FStatusLabel.Caption := Format('微信已连接 | 🔗%d 📢%d',
      [LHighLinkSharing, LMarketingPattern]);
end;

procedure TDeepAxisRadarPanel.UpdateContactList;
var
  LHint: TRadarHint;
  LContact: TContact;
  I, LHintIdx: Integer;
  S, LPreview, LFilter: string;
  LCategoryFilter: string;
  LMatch: Boolean;
  LRowToHint: TArray<Integer>;
  LRowCount: Integer;
  LTargetRow: Integer;
  LMatchCount: Integer;
begin
  // Show empty guide if no hints
  if Length(FCurrentData.Hints) = 0 then
  begin
    FEmptyGuideLabel.Visible := True;
    if not FWeChatConnected then
      FEmptyGuideLabel.Caption := '未连接微信数据' + #13#10 + #13#10 +
        '请通过工具栏完成以下步骤:' + #13#10 +
        '1. 启动微信 → 2. 扫描密钥 → 3. 连接解密 → 4. 读取联系人' + #13#10 + #13#10 +
        '或点击 "设置" 配置微信数据目录'
    else
      FEmptyGuideLabel.Caption := '已连接，暂无雷达提示' + #13#10 + #13#10 +
        '正在分析联系人互动数据...' + #13#10 +
        '当检测到降温、沉默、回暖等情况时会在此显示';
    // Clear list
    FContactListBox.Items.Clear;
    SetLength(FListBoxRowToHintIndex, 0);
    FSelectedContactIndex := -1;
    Exit;
  end;

  // Has data — hide guide and populate list
  FEmptyGuideLabel.Visible := False;
  LFilter := LowerCase(GetSearchFilter);

  // Sort hints by urgency: cooling > long_silence > reactivated > others
  var LSortedHints := Copy(FCurrentData.Hints);
  TArray.Sort<TRadarHint>(LSortedHints,
    TComparer<TRadarHint>.Construct(
      function(const A, B: TRadarHint): Integer
      begin
        Result := Ord(A.HintType) - Ord(B.HintType);
        // rhtCooling=0, rhtLongSilence=1 — these are highest urgency
        // Others stay in default order
      end));

  FContactListBox.Items.BeginUpdate;
  try
    FContactListBox.Items.Clear;
    LRowCount := 0;
    LMatchCount := 0;
    SetLength(LRowToHint, 0);

    LHintIdx := 0;
    for LHint in LSortedHints do
    begin
      // Find contact name and preview
      S := '';
      LPreview := '';
      for LContact in FCurrentData.Contacts do
        if LContact.ContactId = LHint.ContactId then
        begin
          S := LContact.DisplayNameRedacted;
          LPreview := LContact.MessagePreview;
          Break;
        end;
      if S = '' then
        S := LHint.ContactId.Substring(0, 8);

      // Apply search filter
      if LFilter <> '' then
      begin
        // Category filter: [跟进] [回复] [降温] [闲人]
        if LFilter.StartsWith('[') and LFilter.EndsWith(']') then
        begin
          LCategoryFilter := Copy(LFilter, 2, Length(LFilter) - 2);
          LMatch := False;
          if LCategoryFilter = '跟进' then
            LMatch := LHint.HintType in [rhtCooling, rhtLongSilence]
          else if LCategoryFilter = '回复' then
            LMatch := LHint.HintType = rhtReactivated
          else if LCategoryFilter = '降温' then
            LMatch := LHint.HintType = rhtCooling
          else if LCategoryFilter = '闲人' then
          begin
            // Check if contact is idle
            for LContact in FCurrentData.Contacts do
              if LContact.ContactId = LHint.ContactId then
              begin
                LMatch := LContact.IsIdle;
                Break;
              end;
          end;
          if not LMatch then
          begin
            Inc(LHintIdx);
            Continue;
          end;
        end
        else if not (LowerCase(S).Contains(LFilter) or
                LowerCase(LPreview).Contains(LFilter) or
                LowerCase(LHint.ContactId).Contains(LFilter)) then
        begin
          Inc(LHintIdx);
          Continue;
        end;
      end;
      Inc(LMatchCount);

      // Add contact name with hint emoji — record the row→hint mapping
      FContactListBox.Items.Add(
        GetHintTypeEmoji(LHint.HintType) + ' ' + S);
      SetLength(LRowToHint, LRowCount + 1);
      LRowToHint[LRowCount] := LHintIdx;
      Inc(LRowCount);

      // Add message preview if available
      if LPreview <> '' then
      begin
        if Length(LPreview) > 60 then
          LPreview := Copy(LPreview, 1, 57) + '...';
        FContactListBox.Items.Add('  ' + LPreview);
        SetLength(LRowToHint, LRowCount + 1);
        LRowToHint[LRowCount] := LHintIdx;  // preview row maps to same hint
        Inc(LRowCount);
      end;

      Inc(LHintIdx);
    end;

    // Show filter-empty message if filter matched nothing
    if (LFilter <> '') and (LMatchCount = 0) then
    begin
      FContactListBox.Items.Add('(无匹配结果)');
      SetLength(LRowToHint, 1);
      LRowToHint[0] := -1;
    end;

    FListBoxRowToHintIndex := LRowToHint;

    // Restore selection: find the row that maps to FSelectedContactIndex
    if FContactListBox.Items.Count = 0 then
    begin
      FSelectedContactIndex := -1;
      FContactListBox.ItemIndex := -1;
    end
    else
    begin
      // Find first row that maps to the current FSelectedContactIndex
      LTargetRow := -1;
      for I := 0 to Length(FListBoxRowToHintIndex) - 1 do
        if FListBoxRowToHintIndex[I] = FSelectedContactIndex then
        begin
          LTargetRow := I;
          Break;
        end;
      if LTargetRow >= 0 then
        FContactListBox.ItemIndex := LTargetRow
      else
      begin
        FSelectedContactIndex := 0;
        FContactListBox.ItemIndex := 0;
      end;
    end;
  finally
    FContactListBox.Items.EndUpdate;
  end;
end;

procedure TDeepAxisRadarPanel.UpdateDetail;
var
  LHint: TRadarHint;
  LContact: TContact;
  LEvidence: TEvidenceRecord;
  I: Integer;
begin
  if (FSelectedContactIndex < 0) or
     (FSelectedContactIndex >= Length(FCurrentData.Hints)) then
  begin
    FContactNameLabel.Caption := '选择联系人查看详情';
    FHintTypeLabel.Caption := '';
    FLastInteractionLabel.Caption := '';
    FConfidenceLabel.Caption := '';
    FEvidenceMemo.Clear;
    FEvidenceMemo.Visible := False;
    Exit;
  end;

  LHint := FCurrentData.Hints[FSelectedContactIndex];

  // Find contact
  LContact := Default(TContact);
  for I := 0 to Length(FCurrentData.Contacts) - 1 do
    if FCurrentData.Contacts[I].ContactId = LHint.ContactId then
    begin
      LContact := FCurrentData.Contacts[I];
      Break;
    end;

  FContactNameLabel.Caption := LContact.DisplayNameRedacted;
  FHintTypeLabel.Caption := GetHintTypeEmoji(LHint.HintType) + ' ' +
    RadarHintTypeToChinese(LHint.HintType);

  // Last interaction and content stats
  for I := 0 to Length(FCurrentData.Metrics) - 1 do
    if FCurrentData.Metrics[I].ContactId = LHint.ContactId then
    begin
      if FCurrentData.Metrics[I].LastInteractionAt > 0 then
        FLastInteractionLabel.Caption := '上次互动: ' +
          DateTimeToStr(FCurrentData.Metrics[I].LastInteractionAt)
      else
        FLastInteractionLabel.Caption := '无互动记录';

      // Add content stats to evidence memo
      FEvidenceMemo.Clear;
      if FCurrentData.Metrics[I].LinkCount > 0 then
        FEvidenceMemo.Lines.Add(Format('链接消息: %d', [FCurrentData.Metrics[I].LinkCount]));
      if FCurrentData.Metrics[I].MediaCount > 0 then
        FEvidenceMemo.Lines.Add(Format('媒体消息: %d', [FCurrentData.Metrics[I].MediaCount]));
      if FCurrentData.Metrics[I].AvgTextLength > 0 then
        FEvidenceMemo.Lines.Add(Format('平均字数: %d', [FCurrentData.Metrics[I].AvgTextLength]));
      if FCurrentData.Metrics[I].HasMarketingKeywords then
        FEvidenceMemo.Lines.Add('检测到营销关键词');

      Break;
    end;

  FConfidenceLabel.Caption := Format('置信度: %.0f%%', [LHint.Confidence * 100]);

  // Evidence
  for LEvidence in FCurrentData.EvidenceRecords do
    if LEvidence.HintId = LHint.HintId then
    begin
      FEvidenceMemo.Lines.Add('');
      FEvidenceMemo.Lines.Add('--- 证据 ---');
      FEvidenceMemo.Lines.Add(LEvidence.Summary);
    end;
  FEvidenceMemo.Visible := FEvidenceMemo.Lines.Count > 0;
end;

procedure TDeepAxisRadarPanel.Clear;
begin
  FCurrentData := Default(TPollResult);
  FSelectedContactIndex := -1;
  UpdateStats;
  FContactListBox.Items.Clear;
  FContactNameLabel.Caption := '选择联系人查看详情';
  FHintTypeLabel.Caption := '';
  FLastInteractionLabel.Caption := '';
  FConfidenceLabel.Caption := '';
  FEvidenceMemo.Clear;
  FEvidenceMemo.Visible := False;
end;

procedure TDeepAxisRadarPanel.FocusSearch;
begin
  if FSearchEdit <> nil then
    FSearchEdit.SetFocus;
end;

end.
