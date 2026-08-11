
{ ============================================================================
  DeepSpec.Services.Render

  HTML rendering service. Generates static HTML from .deepspec data
  for human review in WebView2 (P2) or external browser (P1).
  ============================================================================ }

unit DeepSpec.Services.Render;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Services.Scan,
  DeepSpec.Models;

type
  /// <summary>Health metrics for the index dashboard (BUG-9 §2.2).
  /// Pure computation over node lists (+ optional issues).</summary>
  THealthMetrics = record
    TotalNodes: Integer;
    ConfirmedNodes: Integer;   // GenStatus = gsConfirmed
    CoveragePct: Double;       // ConfirmedNodes / TotalNodes * 100 (0 if none)
    AvgConfidence: Double;     // low=0.3 / medium=0.7 / high=1.0, mean
    DecisionBacklog: Integer;  // issues with Status = issOpen
    FogCount: Integer;         // nodes with HasFogState and FogState <> fsClear
    HighRiskOpen: Integer;     // issues Status=issOpen and Severity in (isCritical,isHigh)
  end;

  TDeepSpecRenderService = class(TInterfacedObject)
  private
    FBasePath: string;
    FLocale: string;
    function HtmlEscape(const S: string): string;
    function PageHeader(const ATitle: string): string;
    function PageFooter: string;
    function StatusBadge(const AStatus: string): string;
    function ConfidenceBadge(const AConf: string): string;
    function SourceLayerBadge(const ALayer: string): string;
    // CSS slug for a fog state: underscores -> hyphens (bugfix.md BUG-12),
    // so badge-fog-unknown-unknowns matches the hyphen style of badge-fog-misty.
    function FogStateCssClass(AFog: DeepSpec.Models.TFogState): string;
    /// <summary>Locale-aware UI text: returns AZh when the review pages are
    ///  rendered for a Chinese Windows locale, else AEn. Only used for
    ///  human-visible chrome (titles/buttons/hints), never for YAML keys.</summary>
    function T(const AEn, AZh: string): string;
  public
    procedure Initialize(const ADeepSpecPath: string);
    procedure RenderScanReport(AScan: TDeepSpecScanService;
      const AProjectName, AProjectType: string);
    procedure RenderIndex(const AProjectName: string; ATotalFiles: Integer;
      AFunc, AModule, AView, AData: TList<TSpecNode>;
      AIssues: TList<TSpecIssue>; AHasDataTree: Boolean = True);
    procedure RenderTree(const ATreeName, ATreeTitle: string;
      ANodes: System.Generics.Collections.TList<DeepSpec.Models.TSpecNode>);
    procedure RenderProblemsPage(
      AFuncNodes, AModuleNodes, AViewNodes, ADataNodes: TList<TSpecNode>;
      AIssues: TList<TSpecIssue>);
    procedure RenderBundlesPage(
      ABundles: TList<TSemanticBundle>;
      AFuncNodes, AModuleNodes, AViewNodes, ADataNodes: TList<TSpecNode>);
    /// <summary>Render a single-node detail page (node-detail.html) shown
    ///  in the main view when the user clicks a tree node.</summary>
    procedure RenderNodeDetail(const ANode: TSpecNode);
    /// <summary>Compute health metrics over 4 trees (+ optional issues).
    /// nil lists are treated as empty. Pure — no IO.</summary>
    class function ComputeHealthMetrics(AFunc, AModule, AView, AData: TList<TSpecNode>;
      AIssues: TList<TSpecIssue> = nil): THealthMetrics; static;
    /// <summary>Count broken cross-tree references (orphan refs).
    /// Shared by RenderIndex summary and RenderProblemsPage detail.</summary>
    class function CountCrossTreeConflicts(AFunc, AModule, AView, AData: TList<TSpecNode>): Integer; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.StrUtils,
  System.Generics.Defaults,
  Winapi.Windows;

procedure TDeepSpecRenderService.Initialize(const ADeepSpecPath: string);
begin
  FBasePath := TPath.Combine(ADeepSpecPath, 'html');
  if not TDirectory.Exists(FBasePath) then
    TDirectory.CreateDirectory(FBasePath);

  // Detect the Windows UI language once so review pages render localized
  // chrome (titles/buttons/hints). Same normalization as the desktop shell.
  FLocale := 'en-US';
  var LLocale: array[0..84] of WideChar;
  if GetUserDefaultLocaleName(LLocale, Length(LLocale)) > 1 then
  begin
    var LL := string(PWideChar(@LLocale[0])).ToLower;
    if LL.StartsWith('zh-hans') or LL.StartsWith('zh-cn')
       or LL.StartsWith('zh-sg') or (LL = 'zh') then
      FLocale := 'zh-CN'
    else if LL.StartsWith('zh-hant') or LL.StartsWith('zh-tw')
            or LL.StartsWith('zh-hk') or LL.StartsWith('zh-mo') then
      FLocale := 'zh-TW';
  end;
end;

function TDeepSpecRenderService.T(const AEn, AZh: string): string;
begin
  if FLocale = 'zh-CN' then
    Result := AZh
  else
    Result := AEn;
end;

function TDeepSpecRenderService.HtmlEscape(const S: string): string;
begin
  Result := S
    .Replace('&', '&amp;')
    .Replace('<', '&lt;')
    .Replace('>', '&gt;')
    .Replace('"', '&quot;');
end;

function TDeepSpecRenderService.PageHeader(const ATitle: string): string;
begin
  Result :=
    '<!DOCTYPE html>' + sLineBreak +
    '<html lang="en">' + sLineBreak +
    '<head>' + sLineBreak +
    '  <meta charset="UTF-8">' + sLineBreak +
    '  <title>' + HtmlEscape(ATitle) + ' - DeepSpec</title>' + sLineBreak +
    '  <style>' + sLineBreak +
    '    body { font-family: -apple-system, "Segoe UI", sans-serif; margin: 2em; color: #333; }' + sLineBreak +
    '    h1 { border-bottom: 2px solid #4a90e2; padding-bottom: 0.5em; }' + sLineBreak +
    '    h2 { color: #4a90e2; margin-top: 1.5em; }' + sLineBreak +
    '    .stat { display: inline-block; margin: 0.5em 1em 0.5em 0; padding: 0.5em 1em;' + sLineBreak +
    '            background: #f0f4f8; border-left: 3px solid #4a90e2; }' + sLineBreak +
    '    .stat strong { display: block; font-size: 1.5em; color: #4a90e2; }' + sLineBreak +
    '    .file-list { background: #f9f9f9; padding: 1em; border-radius: 4px; max-height: 400px; overflow-y: auto; }' + sLineBreak +
    '    .file-list code { display: block; padding: 0.2em 0; font-size: 0.9em; }' + sLineBreak +
    '    .badge { display: inline-block; padding: 0.2em 0.6em; border-radius: 3px;' + sLineBreak +
    '             font-size: 0.85em; margin-right: 0.5em; }' + sLineBreak +
    '    .badge-doc { background: #e3f2fd; color: #1976d2; }' + sLineBreak +
    '    .badge-code { background: #f3e5f5; color: #7b1fa2; }' + sLineBreak +
    '    .badge-ui { background: #fff3e0; color: #f57c00; }' + sLineBreak +
    '    .badge-config { background: #e8f5e9; color: #388e3c; }' + sLineBreak +
    '    .badge-ai { background: #fce4ec; color: #c2185b; }' + sLineBreak +
    '    footer { margin-top: 3em; padding-top: 1em; border-top: 1px solid #eee;' + sLineBreak +
    '             color: #999; font-size: 0.85em; }' + sLineBreak +
    '  </style>' + sLineBreak +
    '</head>' + sLineBreak +
    '<body>' + sLineBreak;
end;

function TDeepSpecRenderService.PageFooter: string;
begin
  Result :=
    '<footer>' + sLineBreak +
    '  Generated by DeepSpec at ' +
    HtmlEscape(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)) + sLineBreak +
    '</footer>' + sLineBreak +
    '</body>' + sLineBreak +
    '</html>' + sLineBreak;
end;

procedure TDeepSpecRenderService.RenderScanReport(AScan: TDeepSpecScanService;
  const AProjectName, AProjectType: string);
var
  LSb: TStringBuilder;

  procedure AppendCategory(const ATitle, ABadgeClass: string;
    AFiles: TArray<string>);
  begin
    LSb.AppendLine('<h2><span class="badge ' + ABadgeClass + '">' +
      HtmlEscape(ATitle) + '</span> ' + Length(AFiles).ToString + '</h2>');
    if Length(AFiles) = 0 then
      LSb.AppendLine('<p><em>' + T('No files in this category.', '此类别没有文件。') +
        '</em></p>')
    else
    begin
      LSb.AppendLine('<div class="file-list">');
      for var LFile in AFiles do
        LSb.AppendLine('<code>' + HtmlEscape(LFile) + '</code>');
      LSb.AppendLine('</div>');
    end;
  end;

begin
  LSb := TStringBuilder.Create;
  try
    LSb.Append(PageHeader(T('Scan Report', '扫描报告')));

    LSb.AppendLine('<h1>' + T('Scan Report', '扫描报告') + ': ' +
      HtmlEscape(AProjectName) + '</h1>');
    LSb.AppendLine('<p>' + T('Project type:', '项目类型：') +
      ' <strong>' + HtmlEscape(AProjectType) + '</strong></p>');

    LSb.AppendLine('<h2>' + T('Summary', '汇总') + '</h2>');
    LSb.AppendLine('<div class="stat"><strong>' + AScan.TotalFiles.ToString +
      '</strong>' + T('Total files', '文件总数') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + AScan.CategoryCount(fcDocuments).ToString +
      '</strong>' + T('Documents', '文档') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + AScan.CategoryCount(fcCode).ToString +
      '</strong>' + T('Code', '代码') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + AScan.CategoryCount(fcUI).ToString +
      '</strong>' + T('UI', '界面') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + AScan.CategoryCount(fcConfig).ToString +
      '</strong>' + T('Config', '配置') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + AScan.CategoryCount(fcAiRules).ToString +
      '</strong>' + T('AI Rules', 'AI 规则') + '</div>');

    AppendCategory(T('Documents', '文档'), 'badge-doc',
      AScan.GetFilesByCategory(fcDocuments));
    AppendCategory(T('Code', '代码'), 'badge-code',
      AScan.GetFilesByCategory(fcCode));
    AppendCategory(T('UI', '界面'), 'badge-ui',
      AScan.GetFilesByCategory(fcUI));
    AppendCategory(T('Config', '配置'), 'badge-config',
      AScan.GetFilesByCategory(fcConfig));
    AppendCategory(T('AI Rules', 'AI 规则'), 'badge-ai',
      AScan.GetFilesByCategory(fcAiRules));

    LSb.Append(PageFooter);

    TFile.WriteAllText(TPath.Combine(FBasePath, 'scan-report.html'),
      LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecRenderService.RenderIndex(const AProjectName: string;
  ATotalFiles: Integer; AFunc, AModule, AView, AData: TList<TSpecNode>;
  AIssues: TList<TSpecIssue>; AHasDataTree: Boolean);
var
  LSb: TStringBuilder;
  LM: THealthMetrics;
  LConflicts: Integer;
  LHighShown, LIdx: Integer;
  LI: TSpecIssue;
  LSorted: TList<TSpecIssue>;
  LCovStr, LConfStr: string;
begin
  LSb := TStringBuilder.Create;
  LSorted := nil;
  try
    LSb.Append(PageHeader(T('Index', '索引')));
    LSb.AppendLine('<h1>DeepSpec: ' + HtmlEscape(AProjectName) + '</h1>');
    LSb.AppendLine('<p>项目规格健康度看板（BUG-9）。</p>');

    // --- §2.3.1 文档健康度（4 stat 卡片）---
    LM := ComputeHealthMetrics(AFunc, AModule, AView, AData, AIssues);
    LConflicts := CountCrossTreeConflicts(AFunc, AModule, AView, AData);
    LCovStr := FormatFloat('0.0', LM.CoveragePct);
    LConfStr := FormatFloat('0', LM.AvgConfidence * 100.0);

    LSb.AppendLine('<h2>文档健康度</h2>');
    LSb.AppendLine('<div class="stat"><strong>' + LCovStr + '%</strong>覆盖率' +
      '<small style="display:block;color:#6c757d;">已确认节点占比。文档够不够 AI 开发用。</small></div>');
    LSb.AppendLine('<div class="stat"><strong>' + LConfStr + '%</strong>平均置信度' +
      '<small style="display:block;color:#6c757d;">low=30 / medium=70 / high=100</small></div>');
    LSb.AppendLine('<div class="stat"><strong>' + LM.DecisionBacklog.ToString +
      '</strong>决策积压<small style="display:block;color:#6c757d;">未决 issue 数（status=open）</small></div>');
    LSb.AppendLine('<div class="stat"><strong>' + LM.FogCount.ToString +
      '</strong>雾区数<small style="display:block;color:#6c757d;">处于迷雾中的节点（fog≠clear）</small></div>');

    // --- §2.3.2 高风险问题（top 5）---
    LSb.AppendLine('<h2>高风险问题</h2>');
    LSorted := TList<TSpecIssue>.Create;
    if AIssues <> nil then
      for LI in AIssues do
        if (LI.Status = issOpen) and ((LI.Severity = isCritical) or (LI.Severity = isHigh)) then
          LSorted.Add(LI);
    // sort by severity asc (critical=0 < high=1) so most severe first
    LSorted.Sort(TComparer<TSpecIssue>.Construct(
      function(const A, B: TSpecIssue): Integer
      begin
        Result := Ord(A.Severity) - Ord(B.Severity);
      end));
    LHighShown := 0;
    LSb.AppendLine('<ul style="padding-left: 0;">');
    for LIdx := 0 to LSorted.Count - 1 do
    begin
      if LHighShown >= 5 then Break;
      LI := LSorted[LIdx];
      Inc(LHighShown);
      LSb.AppendLine('<li class="problem"><span class="badge badge-conf-low">' +
        HtmlEscape(TSpecEnums.IssueSeverityToStr(LI.Severity)) + '</span> ' +
        '<a href="problems.html">' + HtmlEscape(LI.Title) + '</a>' +
        ' <code>' + HtmlEscape(LI.Id) + '</code></li>');
    end;
    LSb.AppendLine('</ul>');
    if LHighShown = 0 then
      LSb.AppendLine('<p><em>当前无高风险未决问题。</em></p>');

    // --- §2.3.3 冲突摘要 ---
    LSb.AppendLine('<h2>冲突摘要</h2>');
    LSb.AppendLine('<p>跨树断引用：' + LConflicts.ToString + ' 处。' +
      ' <a href="problems.html">查看详情</a></p>');

    // --- §2.3.4 优化 Prompt 入口 ---
    LSb.AppendLine('<h2>优化 Prompt</h2>');
    LSb.AppendLine('<p>依据当前健康度导出一段优化 Prompt，拷给原 AI 工具优化底层文件（旁路工具原则）。</p>');
    LSb.AppendLine('<button class="btn-ticket" data-action="export-optimization-prompt">' +
      '导出优化 Prompt</button>');

    // --- 原有页面列表 ---
    LSb.AppendLine('<h2>Pages</h2>');
    LSb.AppendLine('<ul>');
    LSb.AppendLine('  <li><a href="scan-report.html">Scan Report</a> (' +
      ATotalFiles.ToString + ' files)</li>');
    LSb.AppendLine('  <li><a href="problems.html">Problems</a></li>');
    LSb.AppendLine('  <li><a href="bundles.html">Bundles</a></li>');
    LSb.AppendLine('  <li><a href="function-tree.html">Function Tree</a></li>');
    LSb.AppendLine('  <li><a href="module-tree.html">Module Tree</a></li>');
    LSb.AppendLine('  <li><a href="view-tree.html">View Tree</a></li>');
    // Only link data-tree.html when it was actually rendered; otherwise the
    // link 404s on non-Delphi projects (bugfix.md BUG-10).
    if AHasDataTree then
      LSb.AppendLine('  <li><a href="data-tree.html">Data Tree</a></li>');
    LSb.AppendLine('</ul>');

    // JS Bridge: forward export-optimization-prompt clicks to the WebView2 host.
    // (Index page has no other data-action buttons, so a focused script suffices.
    // Falls back to a visible alert when opened in a regular browser.)
    LSb.AppendLine('<script>');
    LSb.AppendLine('(function() {');
    LSb.AppendLine('  var hasBridge = !!(window.chrome && window.chrome.webview && window.chrome.webview.postMessage);');
    LSb.AppendLine('  document.addEventListener("click", function(e) {');
    LSb.AppendLine('    var t = e.target;');
    LSb.AppendLine('    if (!(t instanceof HTMLElement)) return;');
    LSb.AppendLine('    if (t.getAttribute("data-action") !== "export-optimization-prompt") return;');
    LSb.AppendLine('    if (t.classList.contains("posted")) return;');
    LSb.AppendLine('    if (hasBridge) {');
    LSb.AppendLine('      try { window.chrome.webview.postMessage(JSON.stringify({action: "export-optimization-prompt"})); }');
    LSb.AppendLine('      catch (err) { console.error("DeepSpec bridge:", err); return; }');
    LSb.AppendLine('      t.classList.add("posted");');
    LSb.AppendLine('      t.textContent = "✓ Prompt 已导出 (见 prompts/optimization-prompt.md)";');
    LSb.AppendLine('    } else {');
    LSb.AppendLine('      alert("DeepSpec bridge unavailable. Open this page inside DeepSpec to export the prompt.");');
    LSb.AppendLine('    }');
    LSb.AppendLine('  });');
    LSb.AppendLine('})();');
    LSb.AppendLine('</script>');

    LSb.Append(PageFooter);

    TFile.WriteAllText(TPath.Combine(FBasePath, 'index.html'),
      LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
    if LSorted <> nil then LSorted.Free;
  end;
end;

function TDeepSpecRenderService.StatusBadge(const AStatus: string): string;
begin
  Result := '<span class="badge badge-' + AStatus + '">' +
    HtmlEscape(AStatus) + '</span>';
end;

function TDeepSpecRenderService.ConfidenceBadge(const AConf: string): string;
begin
  Result := '<span class="badge badge-conf-' + AConf + '">' +
    HtmlEscape(AConf) + '</span>';
end;

function TDeepSpecRenderService.SourceLayerBadge(const ALayer: string): string;
begin
  Result := '<span class="badge badge-source">' + HtmlEscape(ALayer) + '</span>';
end;

function TDeepSpecRenderService.FogStateCssClass(
  AFog: DeepSpec.Models.TFogState): string;
begin
  // FogStateToStr returns YAML-style 'unknown_unknowns'; CSS class slugs use
  // hyphens to match badge-fog-misty / badge-fog-foggy.
  Result := DeepSpec.Models.TSpecEnums.FogStateToStr(AFog).Replace('_', '-');
end;

procedure TDeepSpecRenderService.RenderTree(const ATreeName, ATreeTitle: string;
  ANodes: System.Generics.Collections.TList<DeepSpec.Models.TSpecNode>);
var
  LSb: TStringBuilder;
  LNodeMap: TDictionary<string, DeepSpec.Models.TSpecNode>;

  procedure RenderNode(const ANodeId: string; ADepth: Integer);
  begin
    var LNode: DeepSpec.Models.TSpecNode;
    if not LNodeMap.TryGetValue(ANodeId, LNode) then Exit;

    var LStatus := DeepSpec.Models.TSpecEnums.NodeStatusToStr(LNode.Status);

    LSb.AppendLine('<li class="node node-depth-' + ADepth.ToString + '" data-node-id="' +
      HtmlEscape(LNode.Id) + '">');
    LSb.Append('<div class="node-header">');
    LSb.Append('<span class="node-title">' + HtmlEscape(LNode.Title) + '</span> ');
    LSb.Append('<span class="node-kind">' + HtmlEscape(LNode.Kind) + '</span> ');
    LSb.Append(StatusBadge(LStatus));
    LSb.Append(' <span class="badge badge-gen-' +
      DeepSpec.Models.TSpecEnums.GenStatusToStr(LNode.GenStatus) + '">gen:' +
      HtmlEscape(DeepSpec.Models.TSpecEnums.GenStatusToStr(LNode.GenStatus)) + '</span>');
    LSb.Append(' <span class="badge badge-review-' +
      DeepSpec.Models.TSpecEnums.ReviewStatusToStr(LNode.ReviewStatus) + '">rev:' +
      HtmlEscape(DeepSpec.Models.TSpecEnums.ReviewStatusToStr(LNode.ReviewStatus)) + '</span>');
    LSb.Append(' ');
    LSb.Append(ConfidenceBadge(DeepSpec.Models.TSpecEnums.ConfidenceToStr(LNode.Confidence)));
    LSb.Append(' ');
    LSb.Append(SourceLayerBadge(DeepSpec.Models.TSpecEnums.SourceLayerToStr(LNode.SourceLayer)));

    // Fog badge (only when fog_state is explicitly set and not clear)
    if LNode.HasFogState and (LNode.FogState <> DeepSpec.Models.fsClear) then
    begin
      var LFog := DeepSpec.Models.TSpecEnums.FogStateToStr(LNode.FogState);
      LSb.Append(' <span class="badge badge-fog-' + FogStateCssClass(LNode.FogState) +
        '" title="Requirement endpoint is in the fog">fog: ' +
        HtmlEscape(LFog) + '</span>');
    end;

    // Decision buttons for candidate nodes (JS Bridge writes back via WebView2 postMessage)
    if LStatus = 'candidate' then
    begin
      LSb.Append(' <span class="decision-toolbar">');
      LSb.Append('<button class="btn-confirm" data-action="node-confirm" data-node-id="' +
        HtmlEscape(LNode.Id) + '" data-node-title="' + HtmlEscape(LNode.Title) +
        '" title="Confirm this node">'#$2713' Confirm</button>');
      LSb.Append('<button class="btn-reject" data-action="node-reject" data-node-id="' +
        HtmlEscape(LNode.Id) + '" data-node-title="' + HtmlEscape(LNode.Title) +
        '" title="Reject this node">'#$2715' Reject</button>');
      LSb.Append('</span>');
    end;

    LSb.AppendLine('</div>');

    if LNode.Summary <> '' then
      LSb.AppendLine('<div class="node-summary">' + HtmlEscape(LNode.Summary) + '</div>');

    // Data-tree specific badges
    if LNode.Tree = ttData then
    begin
      if LNode.DataType <> '' then
        LSb.AppendLine('<div class="node-data-type"><span class="badge badge-data-type">' +
          HtmlEscape(LNode.DataType) + '</span></div>');
      if LNode.HasRiskScore then
        LSb.AppendLine('<div class="node-risk"><span class="badge badge-risk-' +
          DeepSpec.Models.TSpecEnums.RiskLevelToStr(LNode.RiskScore) + '">' +
          'risk: ' + HtmlEscape(DeepSpec.Models.TSpecEnums.RiskLevelToStr(LNode.RiskScore)) +
          '</span></div>');
      if LNode.Persistence <> '' then
        LSb.AppendLine('<div class="node-persistence"><span class="badge badge-persistence">' +
          HtmlEscape(LNode.Persistence) + '</span></div>');
    end;

    if Length(LNode.AcceptanceCriteria) > 0 then
    begin
      LSb.AppendLine('<details class="node-criteria"><summary>Acceptance Criteria</summary><ul>');
      for var LCrit in LNode.AcceptanceCriteria do
        LSb.AppendLine('<li>' + HtmlEscape(LCrit) + '</li>');
      LSb.AppendLine('</ul></details>');
    end;

    // Trust signals (collapsible)
    if (Length(LNode.SourceRefs) > 0) or (Length(LNode.DecisionRefs) > 0) or
      (Length(LNode.RelatedFunctions) > 0) or (Length(LNode.RelatedModules) > 0) or
      (Length(LNode.RelatedViews) > 0) or (Length(LNode.RelatedData) > 0) then
    begin
      LSb.AppendLine('<details class="trust-signals"><summary>Trust Signals</summary>');
      LSb.AppendLine('<div class="trust-signal-body">');

      // Evidence sources
      if Length(LNode.SourceRefs) > 0 then
      begin
        LSb.AppendLine('<div class="trust-section"><strong>Evidence:</strong>');
        for var LRef in LNode.SourceRefs do
        begin
          LSb.Append('<span class="trust-item trust-ref">');
          LSb.Append(HtmlEscape(LRef.RefId));
          if LRef.Relevance <> '' then
            LSb.Append(' <span class="trust-relevance">' + HtmlEscape(LRef.Relevance) + '</span>');
          LSb.AppendLine('</span>');
        end;
        LSb.AppendLine('</div>');
      end;

      // Cross-tree references
      var LHasCross := False;
      if Length(LNode.RelatedFunctions) > 0 then begin LHasCross := True;
        LSb.AppendLine('<div class="trust-section"><strong>Functions:</strong>');
        for var LRef in LNode.RelatedFunctions do
          LSb.Append('<span class="trust-item trust-func">' + HtmlEscape(LRef) + '</span>');
        LSb.AppendLine('</div>');
      end;
      if Length(LNode.RelatedModules) > 0 then begin
        LSb.AppendLine('<div class="trust-section"><strong>Modules:</strong>');
        for var LRef in LNode.RelatedModules do
          LSb.Append('<span class="trust-item trust-mod">' + HtmlEscape(LRef) + '</span>');
        LSb.AppendLine('</div>');
      end;
      if Length(LNode.RelatedViews) > 0 then begin
        LSb.AppendLine('<div class="trust-section"><strong>Views:</strong>');
        for var LRef in LNode.RelatedViews do
          LSb.Append('<span class="trust-item trust-view">' + HtmlEscape(LRef) + '</span>');
        LSb.AppendLine('</div>');
      end;
      if Length(LNode.RelatedData) > 0 then begin
        LSb.AppendLine('<div class="trust-section"><strong>Data:</strong>');
        for var LRef in LNode.RelatedData do
          LSb.Append('<span class="trust-item trust-data">' + HtmlEscape(LRef) + '</span>');
        LSb.AppendLine('</div>');
      end;

      // Decision history
      if Length(LNode.DecisionRefs) > 0 then
      begin
        LSb.AppendLine('<div class="trust-section"><strong>Decisions:</strong>');
        for var LRef in LNode.DecisionRefs do
          LSb.Append('<span class="trust-item trust-dec">' + HtmlEscape(LRef) + '</span>');
        LSb.AppendLine('</div>');
      end;

      LSb.AppendLine('</div></details>');
    end;

    if Length(LNode.Children) > 0 then
    begin
      LSb.AppendLine('<ul class="node-children">');
      for var LChildId in LNode.Children do
        RenderNode(LChildId, ADepth + 1);
      LSb.AppendLine('</ul>');
    end;

    LSb.AppendLine('</li>');
  end;

begin
  LSb := TStringBuilder.Create;
  LNodeMap := TDictionary<string, DeepSpec.Models.TSpecNode>.Create;
  try
    for var LNode in ANodes do
      LNodeMap.AddOrSetValue(LNode.Id, LNode);

    // Localize the tree page title by file key (function-tree/module-tree/...)
    var LTitle := ATreeTitle;
    if FLocale = 'zh-CN' then
    begin
      if ATreeName = 'function-tree' then LTitle := '功能树'
      else if ATreeName = 'module-tree' then LTitle := '模块树'
      else if ATreeName = 'view-tree' then LTitle := '界面树'
      else if ATreeName = 'data-tree' then LTitle := '数据树';
    end;
    LSb.Append(PageHeader(LTitle));

    // Tree-specific styles
    LSb.AppendLine('<style>');
    LSb.AppendLine('  .node { list-style: none; margin: 0.5em 0; }');
    LSb.AppendLine('  .node-header { padding: 0.4em; border-radius: 4px;');
    LSb.AppendLine('                 background: #f8f9fa; cursor: pointer; }');
    LSb.AppendLine('  .node-header:hover { background: #e9ecef; }');
    LSb.AppendLine('  .node-title { font-weight: 600; }');
    LSb.AppendLine('  .node-kind { color: #6c757d; font-size: 0.9em; font-style: italic; }');
    LSb.AppendLine('  .node-summary { padding: 0.3em 0.4em; color: #495057; font-size: 0.95em; }');
    LSb.AppendLine('  .node-children { padding-left: 1.5em; border-left: 2px solid #dee2e6; }');
    LSb.AppendLine('  .badge-candidate { background: #fff3cd; color: #856404; }');
    LSb.AppendLine('  .badge-confirmed { background: #d4edda; color: #155724; }');
    LSb.AppendLine('  .badge-uncertain { background: #f8d7da; color: #721c24; }');
    LSb.AppendLine('  .badge-rejected { background: #d6d8db; color: #383d41; }');
    LSb.AppendLine('  .badge-superseded { background: #d6d8db; color: #383d41; }');
    LSb.AppendLine('  .badge-conf-low { background: #f8d7da; color: #721c24; }');
    LSb.AppendLine('  .badge-conf-medium { background: #fff3cd; color: #856404; }');
    LSb.AppendLine('  .badge-conf-high { background: #d4edda; color: #155724; }');
    LSb.AppendLine('  .badge-fog-misty { background: #fff3cd; color: #856404; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-fog-foggy { background: #ffe0b2; color: #e65100; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-fog-unknown-unknowns { background: #455a64; color: #fff; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-source { background: #cce5ff; color: #004085; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-gen-draft { background: #e2e3e5; color: #383d41; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-gen-generated { background: #cce5ff; color: #004085; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-gen-confirmed { background: #d4edda; color: #155724; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-gen-skipped { background: #d6d8db; color: #6c757d; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-review-unreviewed { background: #e2e3e5; color: #383d41; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-review-accepted { background: #d4edda; color: #155724; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-review-rejected { background: #f8d7da; color: #721c24; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-review-deferred { background: #fff3cd; color: #856404; font-size: 0.75em; }');
    LSb.AppendLine('  .badge-data-type { background: #e2d9f3; color: #4a2d8a; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-risk-low { background: #d4edda; color: #155724; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-risk-medium { background: #fff3cd; color: #856404; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-risk-high { background: #f8d7da; color: #721c24; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-risk-critical { background: #721c24; color: #fff; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-persistence { background: #d1ecf1; color: #0c5460; font-size: 0.8em; }');
    LSb.AppendLine('  details summary { cursor: pointer; color: #4a90e2; padding: 0.3em 0.4em; }');
    LSb.AppendLine('  .decision-toolbar { margin-left: 0.5em; }');
    LSb.AppendLine('  .decision-toolbar button { font-size: 0.8em; margin-left: 0.25em;');
    LSb.AppendLine('    padding: 0.15em 0.5em; border: 1px solid #ced4da; border-radius: 3px;');
    LSb.AppendLine('    background: #fff; cursor: pointer; }');
    LSb.AppendLine('  .decision-toolbar .btn-confirm { color: #155724; border-color: #c3e6cb; }');
    LSb.AppendLine('  .decision-toolbar .btn-confirm:hover { background: #d4edda; }');
    LSb.AppendLine('  .decision-toolbar .btn-reject { color: #721c24; border-color: #f5c6cb; }');
    LSb.AppendLine('  .decision-toolbar .btn-reject:hover { background: #f8d7da; }');
    LSb.AppendLine('  .decision-toolbar button.posted { opacity: 0.5; cursor: default; }');
    LSb.AppendLine('  .trust-signals summary { cursor: pointer; color: #6c757d; font-size: 0.85em;');
    LSb.AppendLine('    padding: 0.2em 0.4em; border-top: 1px solid #dee2e6; margin-top: 0.3em; }');
    LSb.AppendLine('  .trust-signal-body { padding: 0.4em; font-size: 0.9em; }');
    LSb.AppendLine('  .trust-section { margin: 0.3em 0; }');
    LSb.AppendLine('  .trust-section strong { color: #495057; font-size: 0.85em; }');
    LSb.AppendLine('  .trust-item { display: inline-block; margin: 0.1em 0.3em;');
    LSb.AppendLine('    padding: 0.1em 0.4em; border-radius: 3px; font-size: 0.85em; }');
    LSb.AppendLine('  .trust-ref { background: #d1ecf1; color: #0c5460; }');
    LSb.AppendLine('  .trust-func { background: #d4edda; color: #155724; }');
    LSb.AppendLine('  .trust-mod { background: #cce5ff; color: #004085; }');
    LSb.AppendLine('  .trust-view { background: #fff3cd; color: #856404; }');
    LSb.AppendLine('  .trust-data { background: #e2d9f3; color: #4a2d8a; }');
    LSb.AppendLine('  .trust-dec { background: #f5d0e8; color: #8b4572; }');
    LSb.AppendLine('  .trust-relevance { color: #6c757d; font-size: 0.9em; }');
    LSb.AppendLine('</style>');

    LSb.AppendLine('<h1>' + HtmlEscape(LTitle) + '</h1>');
    LSb.AppendLine('<p><a href="index.html">'#$2190' Back to index</a></p>');

    if ANodes.Count = 0 then
      LSb.AppendLine('<p><em>This tree is empty. Run LLM generation to populate.</em></p>')
    else
    begin
      LSb.AppendLine('<ul class="tree-root" style="padding-left: 0;">');
      // Render roots first (no parent_id)
      for var LRoot in ANodes do
        if LRoot.ParentId = '' then
          RenderNode(LRoot.Id, 0);
      LSb.AppendLine('</ul>');
    end;

    // JS Bridge: forward decision-button clicks to the WebView2 host.
    // Falls back to a no-op (with visible warning) when opened in a regular browser.
    LSb.AppendLine('<script>');
    LSb.AppendLine('(function() {');
    LSb.AppendLine('  var hasBridge = !!(window.chrome && window.chrome.webview && window.chrome.webview.postMessage);');
    LSb.AppendLine('  document.addEventListener("click", function(e) {');
    LSb.AppendLine('    var t = e.target;');
    LSb.AppendLine('    if (!(t instanceof HTMLElement)) return;');
    LSb.AppendLine('    var action = t.getAttribute("data-action");');
    LSb.AppendLine('    if (!action) return;');
    LSb.AppendLine('    if (t.classList.contains("posted")) return;');
    LSb.AppendLine('    var msg = {');
    LSb.AppendLine('      action: action,');
    LSb.AppendLine('      node_id: t.getAttribute("data-node-id") || "",');
    LSb.AppendLine('      node_title: t.getAttribute("data-node-title") || ""');
    LSb.AppendLine('    };');
    LSb.AppendLine('    if (hasBridge) {');
    LSb.AppendLine('      try { window.chrome.webview.postMessage(JSON.stringify(msg)); }');
    LSb.AppendLine('      catch (err) { console.error("DeepSpec bridge:", err); return; }');
    LSb.AppendLine('      t.classList.add("posted");');
    LSb.AppendLine('      t.textContent = (action === "node-confirm" ? "'#$2713' posted" : "'#$2715' posted");');
    LSb.AppendLine('    } else {');
    LSb.AppendLine('      alert("DeepSpec bridge unavailable. Open this page inside DeepSpec to record decisions.");');
    LSb.AppendLine('    }');
    LSb.AppendLine('  });');
    LSb.AppendLine('})();');
    LSb.AppendLine('</script>');

    LSb.Append(PageFooter);

    TFile.WriteAllText(TPath.Combine(FBasePath, ATreeName + '.html'),
      LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
    LNodeMap.Free;
  end;
end;

procedure TDeepSpecRenderService.RenderProblemsPage(
  AFuncNodes, AModuleNodes, AViewNodes, ADataNodes: TList<TSpecNode>;
  AIssues: TList<TSpecIssue>);
var
  LSb: TStringBuilder;
  LAllIds: TDictionary<string, Boolean>;

  procedure ScanNodes(const ATreeLabel: string; ANodes: TList<TSpecNode>);
  begin
    if ANodes = nil then Exit;
    for var LNode in ANodes do
    begin
      // Low confidence
      if LNode.Confidence = clLow then
        LSb.AppendLine('<li class="problem problem-low-confidence">' +
          '<span class="badge badge-conf-low">' + T('low confidence', '低置信度') + '</span> ' +
          HtmlEscape(LNode.Title) +
          ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span>' +
          ' <code>' + HtmlEscape(LNode.Id) + '</code>' +
          '</li>');

      // No evidence (no source_refs and not generated/confirmed)
      if (Length(LNode.SourceRefs) = 0)
        and (LNode.GenStatus in [gsDraft, gsGenerated])
        and (LNode.SourceLayer = slAiInferred) then
        LSb.AppendLine('<li class="problem problem-no-evidence">' +
          '<span class="badge badge-prob-no-evidence">' + T('no evidence', '无证据') + '</span> ' +
          HtmlEscape(LNode.Title) +
          ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span>' +
          ' <code>' + HtmlEscape(LNode.Id) + '</code>' +
          '</li>');

      // Candidate/unreviewed node (needs human review)
      if (LNode.Status = nsCandidate) and (LNode.ReviewStatus = rsUnreviewed) then
        LSb.AppendLine('<li class="problem problem-unreviewed">' +
          '<span class="badge badge-prob-unreviewed">' + T('unreviewed', '未审阅') + '</span> ' +
          HtmlEscape(LNode.Title) +
          ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span>' +
          ' <code>' + HtmlEscape(LNode.Id) + '</code>' +
          '</li>');

      // Uncertain node
      if LNode.Status = nsUncertain then
        LSb.AppendLine('<li class="problem problem-uncertain">' +
          '<span class="badge badge-uncertain">' + T('uncertain', '不确定') + '</span> ' +
          HtmlEscape(LNode.Title) +
          ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span>' +
          ' <code>' + HtmlEscape(LNode.Id) + '</code>' +
          '</li>');

      // Fog: node whose requirement endpoint is in the fog (foggy or unknown_unknowns)
      if LNode.HasFogState and (LNode.FogState in [
        DeepSpec.Models.fsFoggy, DeepSpec.Models.fsUnknownUnknowns]) then
      begin
        var LFog := DeepSpec.Models.TSpecEnums.FogStateToStr(LNode.FogState);
        LSb.AppendLine('<li class="problem problem-fog">' +
          '<span class="badge badge-fog-' + FogStateCssClass(LNode.FogState) + '">fog: ' + HtmlEscape(LFog) + '</span> ' +
          HtmlEscape(LNode.Title) +
          ' <a href="#fog-map" class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</a>' +
          ' <code>' + HtmlEscape(LNode.Id) + '</code>' +
          '</li>');
      end;

      // Orphan: has parent_id but parent not found in any tree
      if LNode.ParentId <> '' then
      begin
        var LFound := False;
        for var LN in AFuncNodes do
          if LN.Id = LNode.ParentId then begin LFound := True; Break; end;
        if not LFound then
          for var LN in AModuleNodes do
            if LN.Id = LNode.ParentId then begin LFound := True; Break; end;
        if not LFound then
          for var LN in AViewNodes do
            if LN.Id = LNode.ParentId then begin LFound := True; Break; end;
        if not LFound then
          for var LN in ADataNodes do
            if LN.Id = LNode.ParentId then begin LFound := True; Break; end;
        if not LFound then
          LSb.AppendLine('<li class="problem problem-orphan">' +
            '<span class="badge badge-prob-orphan">' + T('orphan', '孤立') + '</span> ' +
            HtmlEscape(LNode.Title) +
            ' — parent <code>' + HtmlEscape(LNode.ParentId) + '</code> not found' +
            ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span>' +
            '</li>');
      end;
    end;
  end;

  procedure CheckNodeRefs(const ATreeLabel: string; ANodes: TList<TSpecNode>);
  begin
    if ANodes = nil then Exit;
    for var LN in ANodes do
    begin
      for var LRef in LN.RelatedFunctions do
        if (LAllIds <> nil) and not LAllIds.ContainsKey(LRef) then
          LSb.AppendLine('<li class="problem problem-orphan">' +
            '<span class="badge badge-prob-orphan">' + T('broken ref', '断裂引用') + '</span> ' +
            HtmlEscape(LN.Title) + ' '#8594' func <code>' + HtmlEscape(LRef) + '</code> (not found)' +
            ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span></li>');
      for var LRef in LN.RelatedModules do
        if (LAllIds <> nil) and not LAllIds.ContainsKey(LRef) then
          LSb.AppendLine('<li class="problem problem-orphan">' +
            '<span class="badge badge-prob-orphan">' + T('broken ref', '断裂引用') + '</span> ' +
            HtmlEscape(LN.Title) + ' '#8594' mod <code>' + HtmlEscape(LRef) + '</code> (not found)' +
            ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span></li>');
      for var LRef in LN.RelatedViews do
        if (LAllIds <> nil) and not LAllIds.ContainsKey(LRef) then
          LSb.AppendLine('<li class="problem problem-orphan">' +
            '<span class="badge badge-prob-orphan">' + T('broken ref', '断裂引用') + '</span> ' +
            HtmlEscape(LN.Title) + ' '#8594' view <code>' + HtmlEscape(LRef) + '</code> (not found)' +
            ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span></li>');
      for var LRef in LN.RelatedData do
        if (LAllIds <> nil) and not LAllIds.ContainsKey(LRef) then
          LSb.AppendLine('<li class="problem problem-orphan">' +
            '<span class="badge badge-prob-orphan">' + T('broken ref', '断裂引用') + '</span> ' +
            HtmlEscape(LN.Title) + ' '#8594' data <code>' + HtmlEscape(LRef) + '</code> (not found)' +
            ' <span class="problem-tree">(' + HtmlEscape(ATreeLabel) + ')</span></li>');
    end;
  end;

  // Emit nodes whose fog_state equals AFogTarget into the current Fog Map group.
  // Captures LSb, LFoundAny, LHasFog from the enclosing scope.
  procedure EmitFogNodes(const ALabel: string; ANodes: TList<TSpecNode>;
    AFogTarget: DeepSpec.Models.TFogState; var LFoundAny, LHasFogOut: Boolean);
  begin
    if ANodes = nil then Exit;
    for var LN in ANodes do
      if LN.HasFogState and (LN.FogState = AFogTarget) then
      begin
        LFoundAny := True;
        LHasFogOut := True;
        LSb.AppendLine('<div class="fog-node">' +
          '<span class="problem-tree">(' + HtmlEscape(ALabel) + ')</span> ' +
          HtmlEscape(LN.Title) + ' <code>' + HtmlEscape(LN.Id) + '</code>' +
          ' <button class="btn-ticket" data-action="ticket-create"' +
          ' data-node-id="' + HtmlEscape(LN.Id) + '"' +
          ' data-node-title="' + HtmlEscape(LN.Title) + '">＋ ' + T('ticket', '开票') + '</button></div>');
      end;
  end;

begin
  LSb := TStringBuilder.Create;
  LAllIds := nil;
  try
    LSb.Append(PageHeader(T('Problems', '问题')));

    LSb.AppendLine('<style>');
    LSb.AppendLine('  .problem { list-style: none; padding: 0.4em 0.6em; margin: 0.3em 0;' +
      ' border-radius: 4px; border-left: 3px solid #dc3545; background: #fff5f5; }');
    LSb.AppendLine('  .problem-low-confidence { border-left-color: #ffc107; background: #fffdf5; }');
    LSb.AppendLine('  .problem-no-evidence { border-left-color: #17a2b8; background: #f5fdff; }');
    LSb.AppendLine('  .problem-unreviewed { border-left-color: #6c757d; background: #f8f9fa; }');
    LSb.AppendLine('  .problem-uncertain { border-left-color: #dc3545; background: #fff5f5; }');
    LSb.AppendLine('  .problem-orphan { border-left-color: #e83e8c; background: #fdf5ff; }');
    LSb.AppendLine('  .problem-fog { border-left-color: #e65100; background: #fff8f0; }');
    LSb.AppendLine('  .problem-tree { color: #6c757d; font-size: 0.85em; }');
    LSb.AppendLine('  .problem code { font-size: 0.85em; color: #495057; }');
    LSb.AppendLine('  .badge-prob-no-evidence { background: #d1ecf1; color: #0c5460; }');
    LSb.AppendLine('  .badge-prob-unreviewed { background: #e2e3e5; color: #383d41; }');
    LSb.AppendLine('  .badge-prob-orphan { background: #f5d0e8; color: #8b4572; }');
    LSb.AppendLine('  .badge-fog-misty { background: #fff3cd; color: #856404; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-fog-foggy { background: #ffe0b2; color: #e65100; font-size: 0.8em; }');
    LSb.AppendLine('  .badge-fog-unknown-unknowns { background: #455a64; color: #fff; font-size: 0.8em; }');
    LSb.AppendLine('  .fog-group { margin: 0.5em 0; }');
    LSb.AppendLine('  .fog-group-title { font-weight: 600; color: #495057; margin-bottom: 0.3em; }');
    LSb.AppendLine('  .fog-node { padding: 0.3em 0.6em; margin: 0.2em 0; border-radius: 3px; background: #f8f9fa; }');
    LSb.AppendLine('  .ticket { padding: 0.4em 0.6em; margin: 0.3em 0; border-radius: 4px;' +
      ' border-left: 3px solid #4a90e2; background: #f0f4f8; }');
    LSb.AppendLine('  .ticket code { font-size: 0.85em; color: #495057; }');
    LSb.AppendLine('  .btn-ticket { font-size: 0.8em; margin-left: 0.5em; cursor: pointer;' +
      ' background: #e3f2fd; border: 1px solid #90caf9; color: #1565c0; border-radius: 3px; }');
    LSb.AppendLine('  .btn-ticket:hover { background: #bbdefb; }');
    LSb.AppendLine('  .ticket-meta { color: #6c757d; font-size: 0.85em; margin-left: 0.5em; }');
    LSb.AppendLine('  .prob-section { margin-top: 1.5em; }');
    LSb.AppendLine('  .prob-summary { display: inline-block; margin: 0.5em 1em 0.5em 0;' +
      ' padding: 0.5em 1em; background: #f0f4f8; border-left: 3px solid #4a90e2; }');
    LSb.AppendLine('  .prob-summary strong { display: block; font-size: 1.5em; color: #4a90e2; }');
    LSb.AppendLine('</style>');

    LSb.AppendLine('<h1>' + T('Problems', '问题') + '</h1>');
    LSb.AppendLine('<p><a href="index.html">'#$2190' ' +
      T('Back to index', '返回索引') + '</a></p>');

    // Summary
    LSb.AppendLine('<h2>' + T('Summary', '汇总') + '</h2>');
    var LFC: Integer := 0; if AFuncNodes <> nil then LFC := AFuncNodes.Count;
    var LMC: Integer := 0; if AModuleNodes <> nil then LMC := AModuleNodes.Count;
    var LVC: Integer := 0; if AViewNodes <> nil then LVC := AViewNodes.Count;
    var LDC: Integer := 0; if ADataNodes <> nil then LDC := ADataNodes.Count;
    LSb.AppendLine('<div class="prob-summary"><strong>' + LFC.ToString +
      '</strong>' + T('Function nodes', '功能节点') + '</div>');
    LSb.AppendLine('<div class="prob-summary"><strong>' + LMC.ToString +
      '</strong>' + T('Module nodes', '模块节点') + '</div>');
    LSb.AppendLine('<div class="prob-summary"><strong>' + LVC.ToString +
      '</strong>' + T('View nodes', '界面节点') + '</div>');
    LSb.AppendLine('<div class="prob-summary"><strong>' + LDC.ToString +
      '</strong>' + T('Data nodes', '数据节点') + '</div>');

    // Problem list
    LSb.AppendLine('<h2>' + T('Issues', '问题列表') + '</h2>');
    LSb.AppendLine('<ul style="padding-left: 0;">');
    ScanNodes(T('Function', '功能'), AFuncNodes);
    ScanNodes(T('Module', '模块'), AModuleNodes);
    ScanNodes(T('View', '界面'), AViewNodes);
    ScanNodes(T('Data', '数据'), ADataNodes);
    LSb.AppendLine('</ul>');

    // Cross-tree consistency: detect broken cross-tree references
    LSb.AppendLine('<h2>Cross-Tree Consistency</h2>');
    // 总数复用共享 helper（DRY，与 index.html 看板一致）
    LSb.AppendLine('<p>跨树断引用共 ' +
      CountCrossTreeConflicts(AFuncNodes, AModuleNodes, AViewNodes, ADataNodes).ToString +
      ' 处：</p>');
    LAllIds := TDictionary<string, Boolean>.Create;
    try
      if AFuncNodes <> nil then for var LN in AFuncNodes do LAllIds.AddOrSetValue(LN.Id, True);
      if AModuleNodes <> nil then for var LN in AModuleNodes do LAllIds.AddOrSetValue(LN.Id, True);
      if AViewNodes <> nil then for var LN in AViewNodes do LAllIds.AddOrSetValue(LN.Id, True);
      if ADataNodes <> nil then for var LN in ADataNodes do LAllIds.AddOrSetValue(LN.Id, True);

      LSb.AppendLine('<ul style="padding-left: 0;">');
      CheckNodeRefs(T('Function', '功能'), AFuncNodes);
      CheckNodeRefs(T('Module', '模块'), AModuleNodes);
      CheckNodeRefs(T('View', '界面'), AViewNodes);
      CheckNodeRefs(T('Data', '数据'), ADataNodes);
      LSb.AppendLine('</ul>');
    finally
      LAllIds.Free;
      LAllIds := nil;
    end;

    // Fog Map: nodes grouped by fog_state (the growing/shrinking map of foggy endpoints)
    LSb.AppendLine('<h2 id="fog-map">' + T('Fog Map', '雾区地图') + '</h2>');
    LSb.AppendLine('<p>Requirement endpoints still in the fog. Converges one-way: ' +
      '<code>unknown_unknowns</code> '#8594' <code>foggy</code> '#8594' ' +
      '<code>misty</code> '#8594' <code>clear</code>. ' +
      'Resolve each via an open exploration ticket.</p>');

    var LHasFog := False;
    for var LState in [DeepSpec.Models.fsUnknownUnknowns,
                       DeepSpec.Models.fsFoggy,
                       DeepSpec.Models.fsMisty] do
    begin
      var LStateStr := DeepSpec.Models.TSpecEnums.FogStateToStr(LState);
      var LFoundAny := False;
      LSb.AppendLine('<div class="fog-group">');
      LSb.AppendLine('<div class="fog-group-title"><span class="badge badge-fog-' +
        FogStateCssClass(LState) + '">fog: ' + HtmlEscape(LStateStr) + '</span></div>');

      EmitFogNodes(T('Function', '功能'), AFuncNodes, LState, LFoundAny, LHasFog);
      EmitFogNodes(T('Module', '模块'), AModuleNodes, LState, LFoundAny, LHasFog);
      EmitFogNodes(T('View', '界面'), AViewNodes, LState, LFoundAny, LHasFog);
      EmitFogNodes(T('Data', '数据'), ADataNodes, LState, LFoundAny, LHasFog);

      LSb.AppendLine('</div>');
    end;

    if not LHasFog then
      LSb.AppendLine('<p><em>No nodes in the fog. All requirement endpoints are clear.</em></p>');

    // Open Tickets: exploration tickets persisted in issues/doc-issues.yaml.
    // Only open tickets of the four exploration types are shown here.
    LSb.AppendLine('<h2 id="open-tickets">' + T('Open Tickets', '开放 Ticket') + '</h2>');
    var LTicketCount := 0;
    if AIssues <> nil then
    begin
      for var LI in AIssues do
      begin
        if LI.Status <> DeepSpec.Models.issOpen then Continue;
        if not (LI.IssueType in [DeepSpec.Models.itResearchTicket,
                                 DeepSpec.Models.itPrototypeTicket,
                                 DeepSpec.Models.itGrillingTicket,
                                 DeepSpec.Models.itFogUnknown]) then Continue;
        Inc(LTicketCount);
        var LTypeStr := DeepSpec.Models.TSpecEnums.IssueTypeToStr(LI.IssueType);
        var LSevStr := DeepSpec.Models.TSpecEnums.IssueSeverityToStr(LI.Severity);
        LSb.AppendLine('<div class="ticket">' +
          '<span class="badge">' + HtmlEscape(LTypeStr) + '</span> ' +
          '<span class="badge">' + HtmlEscape(LSevStr) + '</span> ' +
          HtmlEscape(LI.Title) +
          ' <code>' + HtmlEscape(LI.Id) + '</code>');
        if Length(LI.AffectedNodes) > 0 then
        begin
          LSb.Append(' <span class="ticket-meta">affects: ');
          for var J := 0 to High(LI.AffectedNodes) do
          begin
            if J > 0 then LSb.Append(', ');
            LSb.Append('<code>' + HtmlEscape(LI.AffectedNodes[J]) + '</code>');
          end;
          LSb.AppendLine('</span>');
        end
        else
          LSb.AppendLine('');
        if LI.HasRequiresHuman then
        begin
          var LHumanity := 'AFK';
          if LI.RequiresHuman then LHumanity := 'HITL';
          LSb.AppendLine(' <span class="ticket-meta">' + LHumanity + '</span>');
        end;
        LSb.AppendLine('</div>');
      end;
    end;
    if LTicketCount = 0 then
      LSb.AppendLine('<p><em>No open exploration tickets. Open one from a fog node above.</em></p>');

    // JS Bridge: forward ticket-create button clicks to the WebView2 host.
    // Mirrors the tree-page handler. Ticket buttons are NOT greyed-out after a
    // click (a node may open multiple tickets), so the handler skips the
    // .posted swap for data-action="ticket-create".
    LSb.AppendLine('<script>');
    LSb.AppendLine('(function() {');
    LSb.AppendLine('  var hasBridge = !!(window.chrome && window.chrome.webview && window.chrome.webview.postMessage);');
    LSb.AppendLine('  document.addEventListener("click", function(e) {');
    LSb.AppendLine('    var t = e.target;');
    LSb.AppendLine('    if (!(t instanceof HTMLElement)) return;');
    LSb.AppendLine('    var action = t.getAttribute("data-action");');
    LSb.AppendLine('    if (!action) return;');
    LSb.AppendLine('    if (t.classList.contains("posted")) return;');
    LSb.AppendLine('    var msg = {');
    LSb.AppendLine('      action: action,');
    LSb.AppendLine('      node_id: t.getAttribute("data-node-id") || "",');
    LSb.AppendLine('      node_title: t.getAttribute("data-node-title") || ""');
    LSb.AppendLine('    };');
    LSb.AppendLine('    if (hasBridge) {');
    LSb.AppendLine('      try { window.chrome.webview.postMessage(JSON.stringify(msg)); }');
    LSb.AppendLine('      catch (err) { console.error("DeepSpec bridge:", err); return; }');
    LSb.AppendLine('      // Ticket buttons stay re-clickable; only decision buttons grey out.');
    LSb.AppendLine('      if (action !== "ticket-create") {');
    LSb.AppendLine('        t.classList.add("posted");');
    LSb.AppendLine('        t.textContent = (action === "node-confirm" ? "'#$2713' posted" : "'#$2715' posted");');
    LSb.AppendLine('      }');
    LSb.AppendLine('    } else {');
    LSb.AppendLine('      alert("DeepSpec bridge unavailable. Open this page inside DeepSpec to create tickets.");');
    LSb.AppendLine('    }');
    LSb.AppendLine('  });');
    LSb.AppendLine('})();');
    LSb.AppendLine('</script>');

    LSb.Append(PageFooter);

    TFile.WriteAllText(TPath.Combine(FBasePath, 'problems.html'),
      LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
  end;
end;

procedure TDeepSpecRenderService.RenderBundlesPage(
  ABundles: TList<TSemanticBundle>;
  AFuncNodes, AModuleNodes, AViewNodes, ADataNodes: TList<TSpecNode>);
var
  LSb: TStringBuilder;
  LAllNodes: TDictionary<string, TSpecNode>;
begin
  LAllNodes := TDictionary<string, TSpecNode>.Create;
  LSb := TStringBuilder.Create;
  try
    // Build node lookup
    if AFuncNodes <> nil then for var N in AFuncNodes do LAllNodes.AddOrSetValue(N.Id, N);
    if AModuleNodes <> nil then for var N in AModuleNodes do LAllNodes.AddOrSetValue(N.Id, N);
    if AViewNodes <> nil then for var N in AViewNodes do LAllNodes.AddOrSetValue(N.Id, N);
    if ADataNodes <> nil then for var N in ADataNodes do LAllNodes.AddOrSetValue(N.Id, N);

    LSb.Append(PageHeader(T('Semantic Bundles', '语义束')));

    LSb.AppendLine('<style>');
    LSb.AppendLine('  .bundle { margin: 1em 0; padding: 0.8em; border: 1px solid #dee2e6; border-radius: 6px; }');
    LSb.AppendLine('  .bundle-title { font-size: 1.1em; font-weight: 600; margin-bottom: 0.3em; }');
    LSb.AppendLine('  .bundle-desc { color: #6c757d; font-size: 0.9em; margin-bottom: 0.5em; }');
    LSb.AppendLine('  .bundle-nodes { list-style: none; padding-left: 0; }');
    LSb.AppendLine('  .bundle-node { padding: 0.3em 0.5em; margin: 0.2em 0; border-radius: 3px; background: #f8f9fa; }');
    LSb.AppendLine('  .bundle-actions { margin-top: 0.5em; }');
    LSb.AppendLine('  .bundle-actions button { margin-right: 0.5em; padding: 0.3em 0.8em; cursor: pointer; }');
    LSb.AppendLine('  .btn-accept-all { background: #d4edda; border-color: #c3e6cb; color: #155724; }');
    LSb.AppendLine('  .btn-reject-all { background: #f8d7da; border-color: #f5c6cb; color: #721c24; }');
    LSb.AppendLine('</style>');

    LSb.AppendLine('<h1>Semantic Bundles</h1>');
    LSb.AppendLine('<p><a href="index.html">'#$2190' Back to index</a></p>');

    if (ABundles = nil) or (ABundles.Count = 0) then
      LSb.AppendLine('<p><em>' + T('No bundles defined. Bundles group related nodes for batch review.', '未定义语义束。语义束将相关节点分组供批量审阅。') + '</em></p>')
    else
    begin
      for var I := 0 to ABundles.Count - 1 do
      begin
        var LB := ABundles[I];
        LSb.AppendLine('<div class="bundle">');
        LSb.AppendLine('<div class="bundle-title">' + HtmlEscape(LB.Title) + '</div>');
        if LB.Description <> '' then
          LSb.AppendLine('<div class="bundle-desc">' + HtmlEscape(LB.Description) + '</div>');
        LSb.AppendLine('<ul class="bundle-nodes">');

        for var NId in LB.NodeIds do
        begin
          var LNode: TSpecNode;
          if LAllNodes.TryGetValue(NId, LNode) then
            LSb.AppendLine('<li class="bundle-node">' +
              StatusBadge(DeepSpec.Models.TSpecEnums.NodeStatusToStr(LNode.Status)) + ' ' +
              ConfidenceBadge(DeepSpec.Models.TSpecEnums.ConfidenceToStr(LNode.Confidence)) + ' ' +
              HtmlEscape(LNode.Title) +
              ' <code>' + HtmlEscape(NId) + '</code></li>')
          else
            LSb.AppendLine('<li class="bundle-node" style="color:#dc3545;">' +
              HtmlEscape(NId) + ' (not found)</li>');
        end;

        LSb.AppendLine('</ul>');
        LSb.AppendLine('<div class="bundle-actions">');
        LSb.AppendLine('<button class="btn-accept-all" data-action="bundle-accept" data-bundle-id="' +
          HtmlEscape(LB.Id) + '">' + T('Accept All', '全部接受') + '</button>');
        LSb.AppendLine('<button class="btn-reject-all" data-action="bundle-reject" data-bundle-id="' +
          HtmlEscape(LB.Id) + '">' + T('Reject All', '全部拒绝') + '</button>');
        LSb.AppendLine('</div>');
        LSb.AppendLine('</div>');
      end;
    end;

    // JS Bridge for bundle actions
    LSb.AppendLine('<script>');
    LSb.AppendLine('(function() {');
    LSb.AppendLine('  var hasBridge = !!(window.chrome && window.chrome.webview && window.chrome.webview.postMessage);');
    LSb.AppendLine('  document.addEventListener("click", function(e) {');
    LSb.AppendLine('    var t = e.target;');
    LSb.AppendLine('    if (!(t instanceof HTMLElement)) return;');
    LSb.AppendLine('    var action = t.getAttribute("data-action");');
    LSb.AppendLine('    if (!action) return;');
    LSb.AppendLine('    var bundleId = t.getAttribute("data-bundle-id") || "";');
    LSb.AppendLine('    var msg = {');
    LSb.AppendLine('      action: action,');
    LSb.AppendLine('      bundle_id: bundleId');
    LSb.AppendLine('    };');
    LSb.AppendLine('    if (hasBridge) {');
    LSb.AppendLine('      try { window.chrome.webview.postMessage(JSON.stringify(msg)); }');
    LSb.AppendLine('      catch (err) { console.error("DeepSpec bridge:", err); return; }');
    LSb.AppendLine('      t.textContent = "posted"; t.disabled = true;');
    LSb.AppendLine('    } else {');
    LSb.AppendLine('      alert("DeepSpec bridge unavailable.");');
    LSb.AppendLine('    }');
    LSb.AppendLine('  });');
    LSb.AppendLine('})();');
    LSb.AppendLine('</script>');

    LSb.Append(PageFooter);

    TFile.WriteAllText(TPath.Combine(FBasePath, 'bundles.html'),
      LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
    LAllNodes.Free;
  end;
end;

procedure TDeepSpecRenderService.RenderNodeDetail(const ANode: TSpecNode);
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.Append(PageHeader(ANode.Title));
    LSb.AppendLine('<p><a href="index.html">'#$2190' ' +
      T('Back to index', '返回索引') + '</a></p>');
    LSb.AppendLine('<h1>' + HtmlEscape(ANode.Title) + '</h1>');

    LSb.AppendLine('<div class="stat"><strong>' + HtmlEscape(ANode.Id) +
      '</strong>' + T('Node ID', '节点 ID') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + HtmlEscape(
      DeepSpec.Models.TSpecEnums.NodeStatusToStr(ANode.Status)) +
      '</strong>' + T('Status', '状态') + '</div>');
    LSb.AppendLine('<div class="stat"><strong>' + HtmlEscape(
      DeepSpec.Models.TSpecEnums.ConfidenceToStr(ANode.Confidence)) +
      '</strong>' + T('Confidence', '置信度') + '</div>');

    if ANode.Summary <> '' then
    begin
      LSb.AppendLine('<h2>' + T('Summary', '摘要') + '</h2>');
      LSb.AppendLine('<p>' + HtmlEscape(ANode.Summary) + '</p>');
    end;

    if (ANode.GenStatus <> gsDraft) or (ANode.ReviewStatus <> rsUnreviewed) then
    begin
      LSb.AppendLine('<h2>' + T('Review state', '审阅状态') + '</h2>');
      LSb.AppendLine('<p><span class="badge">gen: ' + HtmlEscape(
        DeepSpec.Models.TSpecEnums.GenStatusToStr(ANode.GenStatus)) +
        '</span><span class="badge">rev: ' + HtmlEscape(
        DeepSpec.Models.TSpecEnums.ReviewStatusToStr(ANode.ReviewStatus)) +
        '</span></p>');
    end;

    if Length(ANode.SourceRefs) > 0 then
    begin
      LSb.AppendLine('<h2>' + T('Evidence', '证据') + '</h2>');
      LSb.AppendLine('<ul>');
      for var LR in ANode.SourceRefs do
        LSb.AppendLine('<li><code>' + HtmlEscape(LR.RefId) + '</code> (' +
          HtmlEscape(LR.Relevance) + ')</li>');
      LSb.AppendLine('</ul>');
    end;

    if ANode.HasFogState then
    begin
      LSb.AppendLine('<h2>' + T('Fog state', '雾状态') + '</h2>');
      LSb.AppendLine('<p>' + HtmlEscape(
        DeepSpec.Models.TSpecEnums.FogStateToStr(ANode.FogState)) + '</p>');
    end;

    LSb.Append(PageFooter);
    TFile.WriteAllText(TPath.Combine(FBasePath, 'node-detail.html'),
      LSb.ToString, TEncoding.UTF8);
  finally
    LSb.Free;
  end;
end;

class function TDeepSpecRenderService.ComputeHealthMetrics(AFunc, AModule, AView,
  AData: TList<TSpecNode>; AIssues: TList<TSpecIssue>): THealthMetrics;
var
  LConfSum: Double;
  LCount: Integer;
  LI: TSpecIssue;

  procedure Scan(ANodes: TList<TSpecNode>);
  var
    LN2: TSpecNode;
    LCV: Double;
  begin
    if ANodes = nil then Exit;
    for LN2 in ANodes do
    begin
      Inc(Result.TotalNodes);
      case LN2.Confidence of
        clLow:    LCV := 0.3;
        clMedium: LCV := 0.7;
        clHigh:   LCV := 1.0;
      else
        LCV := 0.7;
      end;
      LConfSum := LConfSum + LCV;
      Inc(LCount);
      if LN2.GenStatus = gsConfirmed then
        Inc(Result.ConfirmedNodes);
      if LN2.HasFogState and (LN2.FogState <> fsClear) then
        Inc(Result.FogCount);
    end;
  end;

begin
  Result := Default(THealthMetrics);
  LConfSum := 0; LCount := 0;
  Scan(AFunc);
  Scan(AModule);
  Scan(AView);
  Scan(AData);
  if LCount > 0 then
    Result.AvgConfidence := LConfSum / LCount;
  if Result.TotalNodes > 0 then
    Result.CoveragePct := (Result.ConfirmedNodes / Result.TotalNodes) * 100.0;
  if AIssues <> nil then
    for LI in AIssues do
    begin
      if LI.Status = issOpen then
      begin
        Inc(Result.DecisionBacklog);
        if (LI.Severity = isCritical) or (LI.Severity = isHigh) then
          Inc(Result.HighRiskOpen);
      end;
    end;
end;

class function TDeepSpecRenderService.CountCrossTreeConflicts(AFunc, AModule,
  AView, AData: TList<TSpecNode>): Integer;
var
  LAllIds: TDictionary<string, Boolean>;

  procedure ScanRefs(ANodes: TList<TSpecNode>);
  var
    LN: TSpecNode;
    LRef: string;
  begin
    if ANodes = nil then Exit;
    for LN in ANodes do
    begin
      for LRef in LN.RelatedModules do
        if not LAllIds.ContainsKey(LRef) then Inc(Result);
      for LRef in LN.RelatedViews do
        if not LAllIds.ContainsKey(LRef) then Inc(Result);
      for LRef in LN.RelatedData do
        if not LAllIds.ContainsKey(LRef) then Inc(Result);
    end;
  end;

var
  LN: TSpecNode;
begin
  Result := 0;
  LAllIds := TDictionary<string, Boolean>.Create;
  try
    if AFunc   <> nil then for LN in AFunc   do LAllIds.AddOrSetValue(LN.Id, True);
    if AModule <> nil then for LN in AModule do LAllIds.AddOrSetValue(LN.Id, True);
    if AView   <> nil then for LN in AView   do LAllIds.AddOrSetValue(LN.Id, True);
    if AData   <> nil then for LN in AData   do LAllIds.AddOrSetValue(LN.Id, True);
    ScanRefs(AFunc);
    ScanRefs(AModule);
    ScanRefs(AView);
    ScanRefs(AData);
  finally
    LAllIds.Free;
  end;
end;

end.
