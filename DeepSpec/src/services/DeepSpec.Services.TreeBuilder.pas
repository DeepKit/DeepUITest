{ ============================================================================
  DeepSpec.Services.TreeBuilder

  Builds basic three trees from scan results without LLM.
  This provides "Level 0 Scanner" value: a starting structure that the
  user (or LLM) can refine.

  Module tree   ← from code files (one node per top-level package/dir)
  View tree     ← from UI files (.dfm/.html/etc)
  Function tree ← stub root only (LLM needed for real semantic extraction)

  All generated nodes are marked status=candidate, source_layer=ai_inferred,
  confidence=low (since they're heuristic, not LLM-generated).
  ============================================================================ }

unit DeepSpec.Services.TreeBuilder;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DeepSpec.Models,
  DeepSpec.Services.Scan;

type
  TDeepSpecTreeBuilder = class(TInterfacedObject)
  private
    FFunctionNodes: TList<TSpecNode>;
    FModuleNodes: TList<TSpecNode>;
    FViewNodes: TList<TSpecNode>;
    FEvidenceList: TList<TSpecEvidence>;
    FProjectRootPath: string;
    function MakeSlug(const ATitle: string): string;
    function GetTopLevelDir(const APath: string): string;
    function MakeEvidenceForFile(const ARelPath: string): TSpecEvidence;
    procedure EnhanceFromDelphi(AScan: TDeepSpecScanService);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BuildFromScan(AScan: TDeepSpecScanService;
      const AProjectName, AProjectRootPath: string);
    property FunctionNodes: TList<TSpecNode> read FFunctionNodes;
    property ModuleNodes: TList<TSpecNode> read FModuleNodes;
    property ViewNodes: TList<TSpecNode> read FViewNodes;
    property EvidenceList: TList<TSpecEvidence> read FEvidenceList;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Character,
  DeepSpec.Hash,
  DeepSpec.Delphi.DfmParser,
  DeepSpec.Delphi.PasParser;

constructor TDeepSpecTreeBuilder.Create;
begin
  inherited Create;
  FFunctionNodes := TList<TSpecNode>.Create;
  FModuleNodes := TList<TSpecNode>.Create;
  FViewNodes := TList<TSpecNode>.Create;
  FEvidenceList := TList<TSpecEvidence>.Create;
end;

destructor TDeepSpecTreeBuilder.Destroy;
begin
  FFunctionNodes.Free;
  FModuleNodes.Free;
  FViewNodes.Free;
  FEvidenceList.Free;
  inherited;
end;

function TDeepSpecTreeBuilder.MakeSlug(const ATitle: string): string;
begin
  var LSb := TStringBuilder.Create;
  try
    var LLastDash := False;
    for var LCh in ATitle do
    begin
      if (LCh >= 'a') and (LCh <= 'z') then
      begin
        LSb.Append(LCh);
        LLastDash := False;
      end
      else if (LCh >= 'A') and (LCh <= 'Z') then
      begin
        LSb.Append(Char(Ord(LCh) + 32));
        LLastDash := False;
      end
      else if (LCh >= '0') and (LCh <= '9') then
      begin
        LSb.Append(LCh);
        LLastDash := False;
      end
      else if not LLastDash then
      begin
        LSb.Append('-');
        LLastDash := True;
      end;
    end;
    Result := LSb.ToString.Trim(['-']);
    if Result.Length > 40 then
      Result := Result.Substring(0, 40).Trim(['-']);
    if Result = '' then
      Result := 'unnamed';
  finally
    LSb.Free;
  end;
end;

function TDeepSpecTreeBuilder.GetTopLevelDir(const APath: string): string;
begin
  var LIdx := APath.IndexOf('/');
  if LIdx < 0 then
    LIdx := APath.IndexOf('\');
  if LIdx > 0 then
    Result := APath.Substring(0, LIdx)
  else
    Result := '';
end;

function TDeepSpecTreeBuilder.MakeEvidenceForFile(const ARelPath: string): TSpecEvidence;
begin
  Result := Default(TSpecEvidence);
  Result.Id := 'ev-' + MakeSlug(ARelPath);
  Result.SourceLayer := slParsedFromA;
  Result.Path := ARelPath;
  Result.Lines := '';
  Result.Excerpt := 'File: ' + ARelPath;
  Result.ExcerptTruncated := False;
  Result.Confidence := clHigh;
  Result.CreatedAt := Now;
  Result.UpdatedAt := Now;
  Result.IsStale := False;
end;

procedure TDeepSpecTreeBuilder.BuildFromScan(AScan: TDeepSpecScanService;
  const AProjectName, AProjectRootPath: string);
var
  LDirs: TDictionary<string, Boolean>;
begin
  FFunctionNodes.Clear;
  FModuleNodes.Clear;
  FViewNodes.Clear;
  FEvidenceList.Clear;
  FProjectRootPath := AProjectRootPath;

  // ============ Function Tree: stub root + doc-derived placeholders ============
  var LRootSlug := MakeSlug(AProjectName);
  if LRootSlug = '' then LRootSlug := 'project';

  var LFuncRoot := TSpecNode.MakeNew('func-' + LRootSlug, ttFunction,
    AProjectName, 'capability');
  LFuncRoot.Summary := 'Project root capability (stub - run LLM generation for semantic content)';
  LFuncRoot.Status := nsCandidate;
  LFuncRoot.Confidence := clLow;
  LFuncRoot.SourceLayer := slAiInferred;
  LFuncRoot.ContentHash := TSpecHash.NodeContentHash(LFuncRoot);
  LFuncRoot.RelationHash := TSpecHash.NodeRelationHash(LFuncRoot);
  FFunctionNodes.Add(LFuncRoot);

  // ============ Module Tree: from top-level code directories ============
  LDirs := TDictionary<string, Boolean>.Create;
  try
    for var LFile in AScan.GetFilesByCategory(fcCode) do
    begin
      var LTopDir := GetTopLevelDir(LFile);
      if (LTopDir <> '') and not LDirs.ContainsKey(LTopDir) then
        LDirs.Add(LTopDir, True);
    end;

    var LModRootId := 'mod-' + LRootSlug;
    var LModRoot := TSpecNode.MakeNew(LModRootId, ttModule,
      AProjectName + ' Modules', 'package');
    LModRoot.Summary := 'Top-level module structure derived from directory layout';
    LModRoot.Status := nsCandidate;
    LModRoot.Confidence := clMedium;
    LModRoot.SourceLayer := slParsedFromA;

    var LChildren: TList<string>;
    LChildren := TList<string>.Create;
    try
      // Children: each top-level directory
      for var LDir in LDirs.Keys do
      begin
        var LDirSlug := MakeSlug(LDir);
        var LDirId := 'mod-' + LDirSlug;
        LChildren.Add(LDirId);

        var LDirNode := TSpecNode.MakeNew(LDirId, ttModule, LDir, 'package');
        LDirNode.ParentId := LModRootId;
        LDirNode.Summary := 'Module rooted at ' + LDir + '/';
        LDirNode.Status := nsCandidate;
        LDirNode.Confidence := clMedium;
        LDirNode.SourceLayer := slParsedFromA;

        // Add evidence for this directory (use first file as evidence)
        for var LFile in AScan.GetFilesByCategory(fcCode) do
          if LFile.StartsWith(LDir + '/') or LFile.StartsWith(LDir + '\') then
          begin
            var LEv := MakeEvidenceForFile(LFile);
            LEv.Excerpt := 'Top-level directory: ' + LDir;
            FEvidenceList.Add(LEv);

            var LRef: TSourceRef;
            LRef.RefId := LEv.Id;
            LRef.Relevance := 'primary';
            LDirNode.SourceRefs := [LRef];
            Break;
          end;

        LDirNode.ContentHash := TSpecHash.NodeContentHash(LDirNode);
        LDirNode.RelationHash := TSpecHash.NodeRelationHash(LDirNode);
        FModuleNodes.Add(LDirNode);
      end;

      LModRoot.Children := LChildren.ToArray;
      LModRoot.ContentHash := TSpecHash.NodeContentHash(LModRoot);
      LModRoot.RelationHash := TSpecHash.NodeRelationHash(LModRoot);
      FModuleNodes.Insert(0, LModRoot);  // root first
    finally
      LChildren.Free;
    end;
  finally
    LDirs.Free;
  end;

  // ============ View Tree: from UI files ============
  var LUIFiles := AScan.GetFilesByCategory(fcUI);
  if Length(LUIFiles) > 0 then
  begin
    var LViewRootId := 'view-' + LRootSlug;
    var LViewRoot := TSpecNode.MakeNew(LViewRootId, ttView,
      AProjectName + ' Views', 'application');
    LViewRoot.Summary := 'UI structure derived from UI files';
    LViewRoot.Status := nsCandidate;
    LViewRoot.Confidence := clMedium;
    LViewRoot.SourceLayer := slParsedFromA;

    var LViewChildren: TList<string>;
    LViewChildren := TList<string>.Create;
    try
      // Limit to first 20 UI files to avoid bloat in P0
      var LCount := Length(LUIFiles);
      if LCount > 20 then LCount := 20;

      for var I := 0 to LCount - 1 do
      begin
        var LFile := LUIFiles[I];
        var LFileName := TPath.GetFileNameWithoutExtension(LFile);
        var LSlug := MakeSlug(LFileName);
        var LId := 'view-' + LSlug;

        // Determine view kind by extension
        var LExt := LowerCase(TPath.GetExtension(LFile));
        var LKind := 'window';
        if (LExt = '.dfm') or (LExt = '.fmx') then
          LKind := 'window'
        else if LExt = '.html' then
          LKind := 'page'
        else if (LExt = '.vue') or (LExt = '.jsx') or (LExt = '.tsx') then
          LKind := 'page'
        else if (LExt = '.xaml') then
          LKind := 'window';

        var LViewNode := TSpecNode.MakeNew(LId, ttView, LFileName, LKind);
        LViewNode.ParentId := LViewRootId;
        LViewNode.Summary := 'View defined in ' + LFile;
        LViewNode.Status := nsCandidate;
        LViewNode.Confidence := clMedium;
        LViewNode.SourceLayer := slParsedFromA;

        var LEv := MakeEvidenceForFile(LFile);
        FEvidenceList.Add(LEv);

        var LRef: TSourceRef;
        LRef.RefId := LEv.Id;
        LRef.Relevance := 'primary';
        LViewNode.SourceRefs := [LRef];

        LViewNode.ContentHash := TSpecHash.NodeContentHash(LViewNode);
        LViewNode.RelationHash := TSpecHash.NodeRelationHash(LViewNode);
        FViewNodes.Add(LViewNode);
        LViewChildren.Add(LId);
      end;

      LViewRoot.Children := LViewChildren.ToArray;
      LViewRoot.ContentHash := TSpecHash.NodeContentHash(LViewRoot);
      LViewRoot.RelationHash := TSpecHash.NodeRelationHash(LViewRoot);
      FViewNodes.Insert(0, LViewRoot);
    finally
      LViewChildren.Free;
    end;
  end;

  // ============ Delphi-specific enhancement ============
  EnhanceFromDelphi(AScan);
end;

procedure TDeepSpecTreeBuilder.EnhanceFromDelphi(AScan: TDeepSpecScanService);
begin
  // Only apply if we have .pas or .dfm files
  var LHasDelphi := False;
  for var LFile in AScan.GetFilesByCategory(fcCode) do
    if LFile.EndsWith('.pas') or LFile.EndsWith('.dpr') then
    begin
      LHasDelphi := True;
      Break;
    end;
  if not LHasDelphi then Exit;

  // Parse a sample of .pas files (limit to avoid bloat)
  var LPasParser := TPasParser.Create;
  try
    var LCount := 0;
    for var LFile in AScan.GetFilesByCategory(fcCode) do
    begin
      if LCount >= 30 then Break; // limit P0
      if not (LFile.EndsWith('.pas') or LFile.EndsWith('.dpr')) then Continue;

      var LFullPath := TPath.Combine(FProjectRootPath, LFile.Replace('/', '\'));
      if not TFile.Exists(LFullPath) then Continue;

      var LInfo := LPasParser.ParseFile(LFullPath);
      if LInfo = nil then Continue;
      try
        if LInfo.UnitName = '' then Continue;

        var LUnitSlug := MakeSlug(LInfo.UnitName);
        var LUnitId := 'mod-unit-' + LUnitSlug;

        var LUnitNode := TSpecNode.MakeNew(LUnitId, ttModule, LInfo.UnitName, 'unit');
        LUnitNode.Summary := 'Pascal unit declared in ' + LFile;
        LUnitNode.Status := nsCandidate;
        LUnitNode.Confidence := clHigh;
        LUnitNode.SourceLayer := slParsedFromA;

        // Add evidence
        var LEv := MakeEvidenceForFile(LFile);
        LEv.Excerpt := 'unit ' + LInfo.UnitName + ';';
        FEvidenceList.Add(LEv);
        var LRef: TSourceRef;
        LRef.RefId := LEv.Id;
        LRef.Relevance := 'primary';
        LUnitNode.SourceRefs := [LRef];

        // Add classes/interfaces as related items
        var LRelMods: TList<string>;
        LRelMods := TList<string>.Create;
        try
          for var LItem in LInfo.Items do
          begin
            var LItemKindStr := if LItem.Kind = pikInterface then 'interface' else 'class';
            var LItemSlug := MakeSlug(LItem.Name);
            var LItemId := 'mod-' + LItemKindStr + '-' + LItemSlug;

            var LItemNode := TSpecNode.MakeNew(LItemId, ttModule, LItem.Name, LItemKindStr);
            LItemNode.ParentId := LUnitId;
            LItemNode.Summary := if LItem.AncestorOrInterface <> '' then
              'Inherits from ' + LItem.AncestorOrInterface
            else
              LItem.Name + ' declaration in ' + LInfo.UnitName;
            LItemNode.Status := nsCandidate;
            LItemNode.Confidence := clHigh;
            LItemNode.SourceLayer := slParsedFromA;
            LItemNode.SourceRefs := [LRef];
            LItemNode.ContentHash := TSpecHash.NodeContentHash(LItemNode);
            LItemNode.RelationHash := TSpecHash.NodeRelationHash(LItemNode);
            FModuleNodes.Add(LItemNode);
            LRelMods.Add(LItemId);
          end;
          LUnitNode.Children := LRelMods.ToArray;
        finally
          LRelMods.Free;
        end;

        LUnitNode.ContentHash := TSpecHash.NodeContentHash(LUnitNode);
        LUnitNode.RelationHash := TSpecHash.NodeRelationHash(LUnitNode);
        FModuleNodes.Add(LUnitNode);
        Inc(LCount);
      finally
        LInfo.Free;
      end;
    end;
  finally
    LPasParser.Free;
  end;

  // Parse DFM files for view tree
  var LDfmParser := TDfmParser.Create;
  try
    var LCount := 0;
    for var LFile in AScan.GetFilesByCategory(fcUI) do
    begin
      if LCount >= 20 then Break;
      if not LFile.EndsWith('.dfm') then Continue;

      var LFullPath := TPath.Combine(FProjectRootPath, LFile.Replace('/', '\'));
      if not TFile.Exists(LFullPath) then Continue;

      var LDfm := LDfmParser.ParseFile(LFullPath);
      if LDfm = nil then Continue;
      try
        if LDfm.Name = '' then Continue;

        var LFormSlug := MakeSlug(LDfm.Name);
        var LFormId := 'view-form-' + LFormSlug;

        var LFormNode := TSpecNode.MakeNew(LFormId, ttView, LDfm.Name, 'window');
        LFormNode.Summary := if LDfm.Caption <> '' then
          'Form: ' + LDfm.Caption
        else
          LDfm.ClassName + ' defined in ' + LFile;
        LFormNode.Status := nsCandidate;
        LFormNode.Confidence := clHigh;
        LFormNode.SourceLayer := slParsedFromA;

        var LEv := MakeEvidenceForFile(LFile);
        LEv.Excerpt := 'object ' + LDfm.Name + ': ' + LDfm.ClassName;
        FEvidenceList.Add(LEv);
        var LRef: TSourceRef;
        LRef.RefId := LEv.Id;
        LRef.Relevance := 'primary';
        LFormNode.SourceRefs := [LRef];

        // Add up to 30 child controls
        var LChildList: TList<string>;
        LChildList := TList<string>.Create;
        try
          var LCtrlCount := 0;
          for var LCtrl in LDfm.Children do
          begin
            if LCtrlCount >= 30 then Break;
            if LCtrl.Name = '' then Continue;
            var LCtrlSlug := MakeSlug(LCtrl.Name);
            var LCtrlId := 'view-ctrl-' + LCtrlSlug;

            var LCtrlNode := TSpecNode.MakeNew(LCtrlId, ttView, LCtrl.Name, 'control');
            LCtrlNode.ParentId := LFormId;
            LCtrlNode.Summary := if LCtrl.Caption <> '' then
              LCtrl.ClassName + ': "' + LCtrl.Caption + '"'
            else
              LCtrl.ClassName + ' control';
            LCtrlNode.Status := nsCandidate;
            LCtrlNode.Confidence := clHigh;
            LCtrlNode.SourceLayer := slParsedFromA;
            LCtrlNode.SourceRefs := [LRef];
            LCtrlNode.ContentHash := TSpecHash.NodeContentHash(LCtrlNode);
            LCtrlNode.RelationHash := TSpecHash.NodeRelationHash(LCtrlNode);
            FViewNodes.Add(LCtrlNode);
            LChildList.Add(LCtrlId);
            Inc(LCtrlCount);
          end;
          LFormNode.Children := LChildList.ToArray;
        finally
          LChildList.Free;
        end;

        LFormNode.ContentHash := TSpecHash.NodeContentHash(LFormNode);
        LFormNode.RelationHash := TSpecHash.NodeRelationHash(LFormNode);
        FViewNodes.Add(LFormNode);
        Inc(LCount);
      finally
        LDfm.Free;
      end;
    end;
  finally
    LDfmParser.Free;
  end;
end;

end.
