
{ ============================================================================
  DeepSpec.Providers.MainView

  Main view provider - hosts a TEdgeBrowser (WebView2) for HTML rendering.
  Falls back to a label if WebView2 runtime is not available.

  JS Bridge: HTML pages can post decision messages back via
    window.chrome.webview.postMessage(JSON.stringify(payload))
  where payload has fields:
    - action     : "node-confirm" or "node-reject"
    - node_id    : the spec node id
    - node_title : the spec node title (for traceability)
  Each accepted message is appended to
    <project>/.deepspec/decisions/pending-decisions.yaml
  for later review by the DeepSpec UI.
  ============================================================================ }

unit DeepSpec.Providers.MainView;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Edge,
  DeepBase.VCL.DeepShell.Intf,
  DeepBase.VCL.DeepShell.Types,
  DeepSpec.Services.Project;

type
  /// <summary>JS Bridge callback for creating an exploration ticket from a
  /// fog node (BUG-11 step 2). The host (Controller.CreateTicket) defogs the
  /// node one step, validates, and persists the ticket.</summary>
  TCreateTicketProc = reference to procedure(
    const ANodeId, ANodeTitle: string);

  /// <summary>JS Bridge callback for exporting an optimization prompt
  /// from the index dashboard (BUG-9 §2.3.4). No args — the host
  /// (Controller.ExportOptimizationPrompt) computes metrics + writes file.</summary>
  TExportOptPromptProc = reference to procedure;

  /// <summary>JS Bridge callback for batch bundle review (Accept All /
  /// Reject All on bundles.html). AAction is 'bundle-accept' or
  /// 'bundle-reject'; ABundleId is the bundle id. The host
  /// (Controller.ApplyBundleDecisions) records one formal decision and
  /// applies state transitions to all anchored nodes.</summary>
  TBundleActionProc = reference to procedure(
    const AAction, ABundleId: string);

  /// <summary>
  /// Holds a target URL and navigates the browser when it becomes ready.
  /// Also handles incoming postMessage events from the page (JS Bridge).
  /// Owned by the browser via component lifecycle.
  /// </summary>
  TBrowserNavigator = class(TComponent)
  private
    FTargetUrl: string;
    FProjectService: TDeepSpecProjectService;
    FOnCreateTicket: TCreateTicketProc;
    FOnExportOptPrompt: TExportOptPromptProc;
    FOnBundleAction: TBundleActionProc;
    procedure HandleCreated(Sender: TCustomEdgeBrowser; AResult: HResult);
    procedure HandleWebMessage(Sender: TCustomEdgeBrowser;
      Args: TWebMessageReceivedEventArgs);
    procedure AppendPendingDecision(const AAction, ANodeId, ANodeTitle: string);
    function YamlEscape(const S: string): string;
  public
    constructor CreateFor(AOwner: TComponent; const ATargetUrl: string;
      AProjectService: TDeepSpecProjectService;
      AOnCreateTicket: TCreateTicketProc;
      AOnExportOptPrompt: TExportOptPromptProc;
      AOnBundleAction: TBundleActionProc);
  end;

  TDeepSpecMainViewProvider = class(TInterfacedObject, IShellMainViewProvider)
  private
    FProjectService: TDeepSpecProjectService;
    FOnCreateTicket: TCreateTicketProc;
    FOnExportOptPrompt: TExportOptPromptProc;
    FOnBundleAction: TBundleActionProc;
    function GetIndexHtmlPath: string;
  public
    constructor Create(AProjectService: TDeepSpecProjectService;
      AOnCreateTicket: TCreateTicketProc;
      AOnExportOptPrompt: TExportOptPromptProc;
      AOnBundleAction: TBundleActionProc);
    function ProviderId: string;
    function CanOpen(const ARef: TShellObjectRef): Boolean;
    function GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
    function CreateViewControl(AOwner: TComponent;
      const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  Winapi.ActiveX,
  Winapi.WebView2,
  DeepSpec.Services.SpecStore;

{ TBrowserNavigator }

constructor TBrowserNavigator.CreateFor(AOwner: TComponent; const ATargetUrl: string;
  AProjectService: TDeepSpecProjectService;
  AOnCreateTicket: TCreateTicketProc;
  AOnExportOptPrompt: TExportOptPromptProc;
  AOnBundleAction: TBundleActionProc);
begin
  inherited Create(AOwner);
  FTargetUrl := ATargetUrl;
  FProjectService := AProjectService;
  FOnCreateTicket := AOnCreateTicket;
  FOnExportOptPrompt := AOnExportOptPrompt;
  FOnBundleAction := AOnBundleAction;
end;

procedure TBrowserNavigator.HandleCreated(Sender: TCustomEdgeBrowser; AResult: HResult);
begin
  // Winapi HRESULT >= 0 means success
  if AResult >= 0 then
    TEdgeBrowser(Sender).Navigate(FTargetUrl);
end;

procedure TBrowserNavigator.HandleWebMessage(Sender: TCustomEdgeBrowser;
  Args: TWebMessageReceivedEventArgs);
var
  LArgsIntf: ICoreWebView2WebMessageReceivedEventArgs;
  LRaw: PWideChar;
  LMessage, LAction, LNodeId, LNodeTitle, LBundleId: string;
  LJson: TJSONValue;
  LObj: TJSONObject;
begin
  if (FProjectService = nil) or not FProjectService.IsOpen then Exit;

  LArgsIntf := Args.ArgsInterface;
  if LArgsIntf = nil then Exit;

  LRaw := nil;
  // Prefer string form; fall back to JSON if it's an object literal.
  if LArgsIntf.TryGetWebMessageAsString(LRaw) <> S_OK then
  begin
    if LArgsIntf.Get_webMessageAsJson(LRaw) <> S_OK then Exit;
  end;
  if LRaw = nil then Exit;

  LMessage := string(LRaw);
  CoTaskMemFree(LRaw);
  if LMessage = '' then Exit;

  LJson := nil;
  try
    LJson := TJSONObject.ParseJSONValue(LMessage);
    if not (LJson is TJSONObject) then Exit;
    LObj := TJSONObject(LJson);

    LAction := LObj.GetValue<string>('action', '');
    LNodeId := LObj.GetValue<string>('node_id', '');
    LNodeTitle := LObj.GetValue<string>('node_title', '');
    LBundleId := LObj.GetValue<string>('bundle_id', '');

    if (LAction = 'node-confirm') or (LAction = 'node-reject') then
      AppendPendingDecision(LAction, LNodeId, LNodeTitle)
    else if LAction = 'ticket-create' then
    begin
      // BUG-11 step 2: open an exploration ticket for the fog node.
      if Assigned(FOnCreateTicket) then
        FOnCreateTicket(LNodeId, LNodeTitle);
    end
    else if LAction = 'export-optimization-prompt' then
    begin
      // BUG-9 §2.3.4: host computes health metrics + writes a prompt file.
      if Assigned(FOnExportOptPrompt) then
        FOnExportOptPrompt;
    end
    else if (LAction = 'bundle-accept') or (LAction = 'bundle-reject') then
    begin
      // Batch bundle review: record one formal decision for all anchored
      // nodes and apply state transitions (dead-button fix, bundles.html).
      if Assigned(FOnBundleAction) then
        FOnBundleAction(LAction, LBundleId);
    end;
  finally
    LJson.Free;
  end;
end;

function TBrowserNavigator.YamlEscape(const S: string): string;
begin
  // Wrap in double quotes and escape `"` and `\` for safe single-line YAML
  Result := '"' + S.Replace('\', '\\').Replace('"', '\"')
    .Replace(#13, ' ').Replace(#10, ' ') + '"';
end;

procedure TBrowserNavigator.AppendPendingDecision(const AAction, ANodeId,
  ANodeTitle: string);
var
  LDir, LPath, LBlock: string;
  LIsNew: Boolean;
begin
  LDir := TPath.Combine(FProjectService.DeepSpecPath, 'decisions');
  if not TDirectory.Exists(LDir) then
    TDirectory.CreateDirectory(LDir);

  LPath := TPath.Combine(LDir, 'pending-decisions.yaml');
  LIsNew := not TFile.Exists(LPath);

  LBlock := '';
  if LIsNew then
    LBlock := 'version: "1.0"' + sLineBreak +
              'pending_decisions:' + sLineBreak;

  LBlock := LBlock +
    '  - received_at: ' + YamlEscape(DateToISO8601(Now, False)) + sLineBreak +
    '    action: ' + YamlEscape(AAction) + sLineBreak +
    '    node_id: ' + YamlEscape(ANodeId) + sLineBreak +
    '    node_title: ' + YamlEscape(ANodeTitle) + sLineBreak;

  // Atomic read-modify-write (bugfix.md BUG-5 path): never bare-append to
  // the pending file — a crash mid-append would leave a truncated block.
  var LFullContent := '';
  if TFile.Exists(LPath) then
    LFullContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
  TDeepSpecStoreService.AtomicWriteTextFile(LPath, LFullContent + LBlock);
end;

{ TDeepSpecMainViewProvider }

constructor TDeepSpecMainViewProvider.Create(AProjectService: TDeepSpecProjectService;
  AOnCreateTicket: TCreateTicketProc; AOnExportOptPrompt: TExportOptPromptProc;
  AOnBundleAction: TBundleActionProc);
begin
  inherited Create;
  FProjectService := AProjectService;
  FOnCreateTicket := AOnCreateTicket;
  FOnExportOptPrompt := AOnExportOptPrompt;
  FOnBundleAction := AOnBundleAction;
end;

function TDeepSpecMainViewProvider.ProviderId: string;
begin
  Result := 'deepspec.mainview';
end;

function TDeepSpecMainViewProvider.CanOpen(const ARef: TShellObjectRef): Boolean;
begin
  Result := ARef.Id.StartsWith('root-') or ARef.Id.StartsWith('func-')
         or ARef.Id.StartsWith('mod-') or ARef.Id.StartsWith('view-')
         or ARef.Id.StartsWith('index-') or (ARef.Kind = 'html');
end;

function TDeepSpecMainViewProvider.GetViewForObject(const ARef: TShellObjectRef): TShellViewInfo;
begin
  Result := TShellViewInfo.Make('deepspec.view.' + ARef.Id, svkControl, ARef.DisplayName, '');
end;

function TDeepSpecMainViewProvider.GetIndexHtmlPath: string;
begin
  Result := '';
  if (FProjectService <> nil) and FProjectService.IsOpen then
    Result := TPath.Combine(FProjectService.DeepSpecPath, 'html\index.html');
end;

function TDeepSpecMainViewProvider.CreateViewControl(AOwner: TComponent;
  const ARef: TShellObjectRef; const AInfo: TShellViewInfo): TControl;
var
  LBrowser: TEdgeBrowser;
  LIndexPath, LUrl: string;
  LFallback: TLabel;
  LNavigator: TBrowserNavigator;
begin
  // Try WebView2 first
  try
    LBrowser := TEdgeBrowser.Create(AOwner);
    LBrowser.Align := alClient;
    LBrowser.UserDataFolder := TPath.Combine(TPath.GetTempPath, 'DeepSpec-WebView2');

    LIndexPath := GetIndexHtmlPath;
    if (LIndexPath <> '') and TFile.Exists(LIndexPath) then
      LUrl := 'file:///' + LIndexPath.Replace('\', '/')
    else
      LUrl := 'about:blank';

    // Navigator gets owned by the browser, freed automatically.
    LNavigator := TBrowserNavigator.CreateFor(LBrowser, LUrl, FProjectService,
      FOnCreateTicket, FOnExportOptPrompt, FOnBundleAction);
    LBrowser.OnCreateWebViewCompleted := LNavigator.HandleCreated;
    LBrowser.OnWebMessageReceived := LNavigator.HandleWebMessage;

    Result := LBrowser;
  except
    on E: Exception do
    begin
      // WebView2 runtime not installed - fallback to label
      LFallback := TLabel.Create(AOwner);
      LFallback.Caption := 'WebView2 not available: ' + E.Message + sLineBreak +
        'Install Microsoft Edge WebView2 Runtime to enable HTML preview.';
      LFallback.Align := alClient;
      LFallback.Alignment := taCenter;
      LFallback.Layout := tlCenter;
      LFallback.WordWrap := True;
      Result := LFallback;
    end;
  end;
end;

end.
