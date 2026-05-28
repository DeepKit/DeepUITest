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
    FDataNodes: TList<TSpecNode>;
    FEvidenceList: TList<TSpecEvidence>;
    FProjectRootPath: string;
    FUsedIds: TDictionary<string, Integer>;
    function MakeSlug(const ATitle: string): string;
    function GetTopLevelDir(const APath: string): string;
    function MakeEvidenceForFile(const ARelPath: string): TSpecEvidence;
    function UniqueId(const ABaseId: string): string;
    procedure EnhanceFromDelphi(AScan: TDeepSpecScanService);
    procedure BuildDataTreeFromDelphi(AScan: TDeepSpecScanService);
    procedure SetGenStatusGenerated(ANodes: TList<TSpecNode>);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BuildFromScan(AScan: TDeepSpecScanService;
      const AProjectName, AProjectRootPath: string);
    function FindNodeById(const ANodeId: string): TSpecNode;
    property FunctionNodes: TList<TSpecNode> read FFunctionNodes;
    property ModuleNodes: TList<TSpecNode> read FModuleNodes;
    property ViewNodes: TList<TSpecNode> read FViewNodes;
    property DataNodes: TList<TSpecNode> read FDataNodes;
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
  FDataNodes := TList<TSpecNode>.Create;
  FEvidenceList := TList<TSpecEvidence>.Create;
  FUsedIds := TDictionary<string, Integer>.Create;
end;

destructor TDeepSpecTreeBuilder.Destroy;
begin
  FFunctionNodes.Free;
  FModuleNodes.Free;
  FViewNodes.Free;
  FDataNodes.Free;
  FEvidenceList.Free;
  FUsedIds.Free;
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

function TDeepSpecTreeBuilder.UniqueId(const ABaseId: string): string;
var
  LExisting: Integer;
begin
  if not FUsedIds.TryGetValue(ABaseId, LExisting) then
  begin
    Result := ABaseId;
    FUsedIds.Add(ABaseId, 0);
  end
  else
  begin
    var LCount := LExisting + 1;
    FUsedIds[ABaseId] := LCount;
    Result := ABaseId + '-' + IntToStr(LCount);
  end;
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

function TDeepSpecTreeBuilder.FindNodeById(const ANodeId: string): TSpecNode;
begin
  Result := Default(TSpecNode);
  for var I := 0 to FFunctionNodes.Count - 1 do
    if FFunctionNodes[I].Id = ANodeId then Exit(FFunctionNodes[I]);
  for var I := 0 to FModuleNodes.Count - 1 do
    if FModuleNodes[I].Id = ANodeId then Exit(FModuleNodes[I]);
  for var I := 0 to FViewNodes.Count - 1 do
    if FViewNodes[I].Id = ANodeId then Exit(FViewNodes[I]);
  for var I := 0 to FDataNodes.Count - 1 do
    if FDataNodes[I].Id = ANodeId then Exit(FDataNodes[I]);
end;

procedure TDeepSpecTreeBuilder.BuildFromScan(AScan: TDeepSpecScanService;
  const AProjectName, AProjectRootPath: string);
var
  LDirs: TDictionary<string, Boolean>;
begin
  FFunctionNodes.Clear;
  FModuleNodes.Clear;
  FViewNodes.Clear;
  FDataNodes.Clear;
  FEvidenceList.Clear;
  FUsedIds.Clear;
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
        var LDirId := UniqueId('mod-' + LDirSlug);
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
        var LId := UniqueId('view-' + LSlug);

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

  // ============ Data Tree: from Delphi published fields ============
  BuildDataTreeFromDelphi(AScan);

  // ============ Set gen_status = generated for all scan-built nodes ============
  SetGenStatusGenerated(FFunctionNodes);
  SetGenStatusGenerated(FModuleNodes);
  SetGenStatusGenerated(FViewNodes);
  SetGenStatusGenerated(FDataNodes);
end;

procedure TDeepSpecTreeBuilder.SetGenStatusGenerated(ANodes: TList<TSpecNode>);
begin
  for var I := 0 to ANodes.Count - 1 do
  begin
    var LNode := ANodes[I];
    LNode.GenStatus := gsGenerated;
    ANodes[I] := LNode;
  end;
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
        var LUnitId := UniqueId('mod-unit-' + LUnitSlug);

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
            var LItemKindStr: string;
            if LItem.Kind = pikInterface then LItemKindStr := 'interface' else LItemKindStr := 'class';
            var LItemSlug := MakeSlug(LItem.Name);
            var LItemId := UniqueId('mod-' + LItemKindStr + '-' + LItemSlug);

            var LItemNode := TSpecNode.MakeNew(LItemId, ttModule, LItem.Name, LItemKindStr);
            LItemNode.ParentId := LUnitId;
            if LItem.AncestorOrInterface <> '' then
              LItemNode.Summary := 'Inherits from ' + LItem.AncestorOrInterface
            else
              LItemNode.Summary := LItem.Name + ' declaration in ' + LInfo.UnitName;
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
        var LFormId := UniqueId('view-form-' + LFormSlug);

        var LFormNode := TSpecNode.MakeNew(LFormId, ttView, LDfm.Name, 'window');
        if LDfm.Caption <> '' then
          LFormNode.Summary := 'Form: ' + LDfm.Caption
        else
          LFormNode.Summary := LDfm.ClassName + ' defined in ' + LFile;
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
            var LCtrlId := UniqueId('view-ctrl-' + LCtrlSlug);

            var LCtrlNode := TSpecNode.MakeNew(LCtrlId, ttView, LCtrl.Name, 'control');
            LCtrlNode.ParentId := LFormId;
            if LCtrl.Caption <> '' then
              LCtrlNode.Summary := LCtrl.ClassName + ': "' + LCtrl.Caption + '"'
            else
              LCtrlNode.Summary := LCtrl.ClassName + ' control';
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

procedure TDeepSpecTreeBuilder.BuildDataTreeFromDelphi(AScan: TDeepSpecScanService);
var
  LPasParser: TPasParser;
  LEntitySlugs: TDictionary<string, Boolean>;
begin
  var LHasDelphi := False;
  for var LFile in AScan.GetFilesByCategory(fcCode) do
    if LFile.EndsWith('.pas') or LFile.EndsWith('.dpr') then
    begin
      LHasDelphi := True;
      Break;
    end;
  if not LHasDelphi then Exit;

  LEntitySlugs := TDictionary<string, Boolean>.Create;
  LPasParser := TPasParser.Create;
  try
    var LCount := 0;
    for var LFile in AScan.GetFilesByCategory(fcCode) do
    begin
      if LCount >= 30 then Break;
      if not (LFile.EndsWith('.pas') or LFile.EndsWith('.dpr')) then Continue;

      var LFullPath := TPath.Combine(FProjectRootPath, LFile.Replace('/', '\'));
      if not TFile.Exists(LFullPath) then Continue;

      var LInfo := LPasParser.ParseFile(LFullPath);
      if LInfo = nil then Continue;
      try
        // For each class, create an entity node and scan published fields
        for var LItem in LInfo.Items do
        begin
          if LItem.Kind <> pikClass then Continue;

          var LEntitySlug := MakeSlug(LItem.Name);
          if LEntitySlugs.ContainsKey(LEntitySlug) then Continue;
          LEntitySlugs.Add(LEntitySlug, True);

          var LEntityId := UniqueId('data-entity-' + LEntitySlug);
          var LEntityNode := TSpecNode.MakeNew(LEntityId, ttData,
            LItem.Name, 'entity');
          LEntityNode.Summary := 'Data entity from class ' + LItem.Name +
            ' in ' + LFile;
          LEntityNode.Status := nsCandidate;
          LEntityNode.Confidence := clMedium;
          LEntityNode.SourceLayer := slParsedFromA;

          var LEv := MakeEvidenceForFile(LFile);
          FEvidenceList.Add(LEv);
          var LRef: TSourceRef;
          LRef.RefId := LEv.Id;
          LRef.Relevance := 'primary';
          LEntityNode.SourceRefs := [LRef];

          // Scan published fields from source file
          var LFieldList: TList<string>;
          LFieldList := TList<string>.Create;
          try
            var LLines := TFile.ReadAllLines(LFullPath, TEncoding.UTF8);
            var LInPublished := False;
            var LFieldCount := 0;
            for var LI := 0 to High(LLines) do
            begin
              var LLine := LLines[LI].Trim;
              if LLine = '' then Continue;

              // Detect section boundaries
              if LLine.StartsWith('published') then
              begin
                LInPublished := True;
                Continue;
              end;
              if LLine.StartsWith('private') or LLine.StartsWith('protected') or
                 LLine.StartsWith('public') or LLine.StartsWith('strict private') or
                 LLine.StartsWith('strict protected') then
              begin
                LInPublished := False;
                Continue;
              end;
              if LLine.StartsWith('end;') then
              begin
                LInPublished := False;
                Continue;
              end;

              if not LInPublished then Continue;
              if LFieldCount >= 50 then Break;

              // Match field declarations: Name: Type;
              var LColonPos := LLine.IndexOf(':');
              if LColonPos < 0 then Continue;
              var LName := LLine.Substring(0, LColonPos).Trim;
              if LName = '' then Continue;
              // Skip property declarations, we want field declarations
              if LName.StartsWith('property ') then Continue;
              if LName.StartsWith('function ') then Continue;
              if LName.StartsWith('procedure ') then Continue;
              if LName.StartsWith('constructor ') then Continue;
              if LName.StartsWith('destructor ') then Continue;
              if LName.StartsWith('class ') then Continue;

              var LTypeRaw := LLine.Substring(LColonPos + 1);
              var LSemiPos := LTypeRaw.IndexOf(';');
              if LSemiPos >= 0 then
                LTypeRaw := LTypeRaw.Substring(0, LSemiPos);
              LTypeRaw := LTypeRaw.Trim;

              var LFieldSlug := MakeSlug(LName);
              var LFieldId := UniqueId('data-field-' + LEntitySlug + '-' + LFieldSlug);

              var LFieldNode := TSpecNode.MakeNew(LFieldId, ttData,
                LName, 'field');
              LFieldNode.ParentId := LEntityId;
              LFieldNode.DataType := LTypeRaw;
              LFieldNode.Summary := LName + ': ' + LTypeRaw;
              LFieldNode.Status := nsCandidate;
              LFieldNode.Confidence := clMedium;
              LFieldNode.SourceLayer := slParsedFromA;
              LFieldNode.SourceRefs := [LRef];
              LFieldNode.ContentHash := TSpecHash.NodeContentHash(LFieldNode);
              LFieldNode.RelationHash := TSpecHash.NodeRelationHash(LFieldNode);
              FDataNodes.Add(LFieldNode);
              LFieldList.Add(LFieldId);
              Inc(LFieldCount);
            end;

            LEntityNode.Children := LFieldList.ToArray;
          finally
            LFieldList.Free;
          end;

          LEntityNode.ContentHash := TSpecHash.NodeContentHash(LEntityNode);
          LEntityNode.RelationHash := TSpecHash.NodeRelationHash(LEntityNode);
          FDataNodes.Add(LEntityNode);
        end;

        Inc(LCount);
      finally
        LInfo.Free;
      end;
    end;
  finally
    LPasParser.Free;
    LEntitySlugs.Free;
  end;
end;

end.
