unit ArtifactOS.Services.SourcePackScanner;

interface

uses
  System.SysUtils, System.Generics.Collections, System.IOUtils,
  ArtifactOS.Core.DB.Connection;

type
  TSourcePackScanResult = record
    SourcePackId: string;
    DisplayRoot: string;
    TotalFiles: Integer;
    IndexedFiles: Integer;
    SkippedFiles: Integer;
    LayerCounts: TDictionary<string, Integer>;
    Errors: TArray<string>;
    procedure Init;
  end;

  /// <summary>
  ///   Scans a SourcePack directory tree and indexes file metadata into
  ///   artifactos.source_inventory_candidate.  Directories are mapped to
  ///   source_layer values via the AA-ZZ naming convention and top-level
  ///   directory numbers (see docs/07).
  ///
  ///   Usage:  TSourcePackScanner.RebuildIndex('D:\_Progs\一元论')
  /// </summary>
  TSourcePackScanner = class
  public
    /// <summary>  Full rebuild: upserts source_pack row, clears old inventory,
    ///            rescans directory, returns stats.  </summary>
    class function RebuildIndex(const ASourceRoot: string;
      const ADisplayName: string = ''): TSourcePackScanResult;

    /// <summary>  Returns the current source_pack row id, or '' if none.  </summary>
    class function GetActiveSourcePackId: string;

    /// <summary>  Returns indexed file count for the active source pack.  </summary>
    class function GetIndexedFileCount: Integer;
  private
    const
      VALID_EXTENSIONS: array[0..21] of string = (
        '.md', '.txt', '.py', '.yaml', '.yml', '.json',
        '.pdf', '.docx', '.tex', '.html', '.csv',
        '.png', '.jpg', '.jpeg', '.gif', '.svg',
        '.zip', '.ps1', '.bat', '.sql', '.js', '.ts');

      /// AA-ZZ sub-layer prefix → source_layer mapping (docs/07 §六)
      /// Each theory layer (10-65) has AA-HH/ZZ sub-directories.
    class function LayerFromSubDir(const ASubDirName: string): string;
    class function LayerFromTopDir(const ATopDirName: string): string;
    class function ContentKindFromExt(const AExt: string): string;
    class function ClaimStrengthFromLayer(const ALayer: string): string;
    class function PublishPolicyFromLayer(const ALayer: string): string;
    class function IsValidExtension(const AExt: string): Boolean;
  end;

implementation

uses
  FireDAC.Comp.Client, System.Hash, System.DateUtils, System.StrUtils;

{ ---------- helpers ---------- }

function SafeStr(const S: string): string;
begin
  Result := StringReplace(S, '''', '''''', [rfReplaceAll]);
end;

function BackslashToSlash(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
end;

{ TSourcePackScanResult }

procedure TSourcePackScanResult.Init;
begin
  SourcePackId := '';
  DisplayRoot := '';
  TotalFiles := 0;
  IndexedFiles := 0;
  SkippedFiles := 0;
  LayerCounts := TDictionary<string, Integer>.Create;
  SetLength(Errors, 0);
end;

{ TSourcePackScanner }

class function TSourcePackScanner.LayerFromSubDir(const ASubDirName: string): string;
var
  Prefix: string;
begin
  // Match AA-母版源层 → canonical, BB-通用表达层 → explanation, etc.
  if Length(ASubDirName) < 2 then Exit('evidence');
  Prefix := UpperCase(Copy(ASubDirName, 1, 2));

  if Prefix = 'AA' then Result := 'canonical'
  else if Prefix = 'BB' then Result := 'explanation'
  else if Prefix = 'CC' then Result := 'explanation'   // independent theory → explanation tier
  else if Prefix = 'DD' then Result := 'evidence'
  else if Prefix = 'EE' then Result := 'evidence'       // academic publication
  else if Prefix = 'FF' then Result := 'evidence'       // engineering output
  else if Prefix = 'GG' then Result := 'evidence'       // practical evidence
  else if Prefix = 'HH' then Result := 'expression'     // public expression
  else if Prefix = 'ZZ' then Result := 'archive'
  else Result := 'evidence';  // fallback: unknown sub-layer
end;

class function TSourcePackScanner.LayerFromTopDir(const ATopDirName: string): string;
var
  Upper: string;
begin
  Upper := UpperCase(ATopDirName);

  // 00-索引与导航 → governance
  if Upper.StartsWith('00') then Result := 'governance'
  // 85-发布管理 → governance
  else if Upper.StartsWith('85') then Result := 'governance'
  // 90-跨层组合 → expression (cross-layer combinations)
  else if Upper.StartsWith('90') then Result := 'expression'
  // 99-归档 → archive
  else if Upper.StartsWith('99') then Result := 'archive'
  // TEW → governance (theory engineering workbench)
  else if Upper = 'TEW' then Result := 'governance'
  // 工具-Tools → governance
  else if Upper.StartsWith('工具') or Upper.StartsWith('TOOLS') then Result := 'governance'
  // 80-学术论文 → evidence
  else if Upper.StartsWith('80') then Result := 'evidence'
  // history → archive
  else if Upper = 'HISTORY' then Result := 'archive'
  // url-to-markdown → evidence (external sources)
  else if Upper.StartsWith('URL') then Result := 'evidence'
  // 10-65 理论核心层: look for sub-layers inside
  // These are handled by LayerFromSubDir when recursing
  else Result := 'evidence';
end;

class function TSourcePackScanner.ContentKindFromExt(const AExt: string): string;
begin
  if AExt = '.md' then Result := 'document'
  else if AExt = '.txt' then Result := 'document'
  else if AExt = '.py' then Result := 'code'
  else if (AExt = '.yaml') or (AExt = '.yml') then Result := 'config'
  else if AExt = '.json' then Result := 'config'
  else if AExt = '.pdf' then Result := 'document'
  else if AExt = '.docx' then Result := 'document'
  else if AExt = '.tex' then Result := 'document'
  else if AExt = '.html' then Result := 'document'
  else if AExt = '.csv' then Result := 'data'
  else if AExt = '.png' then Result := 'image'
  else if (AExt = '.jpg') or (AExt = '.jpeg') then Result := 'image'
  else if AExt = '.svg' then Result := 'image'
  else if AExt = '.gif' then Result := 'image'
  else if AExt = '.zip' then Result := 'archive'
  else if (AExt = '.js') or (AExt = '.ts') then Result := 'code'
  else if (AExt = '.ps1') or (AExt = '.bat') then Result := 'code'
  else if AExt = '.sql' then Result := 'code'
  else Result := 'other';
end;

class function TSourcePackScanner.ClaimStrengthFromLayer(const ALayer: string): string;
begin
  // How strongly this layer's content speaks for the theory
  if ALayer = 'canonical' then Result := 'authoritative'
  else if ALayer = 'governance' then Result := 'binding'
  else if ALayer = 'explanation' then Result := 'representative'
  else if ALayer = 'expression' then Result := 'illustrative'
  else if ALayer = 'evidence' then Result := 'supporting'
  else if ALayer = 'archive' then Result := 'historical'
  else Result := 'unrated';
end;

class function TSourcePackScanner.PublishPolicyFromLayer(const ALayer: string): string;
begin
  // Whether content from this layer can appear in published artifacts
  if ALayer = 'canonical' then Result := 'quote_with_attribution'
  else if ALayer = 'governance' then Result := 'internal_only'
  else if ALayer = 'explanation' then Result := 'adapt_allowed'
  else if ALayer = 'expression' then Result := 'use_as_style_reference'
  else if ALayer = 'evidence' then Result := 'cite_with_source'
  else if ALayer = 'archive' then Result := 'excluded'
  else Result := 'needs_review';
end;

class function TSourcePackScanner.IsValidExtension(const AExt: string): Boolean;
var
  LExt: string;
  I: Integer;
begin
  LExt := LowerCase(AExt);
  for I := Low(VALID_EXTENSIONS) to High(VALID_EXTENSIONS) do
    if LExt = VALID_EXTENSIONS[I] then Exit(True);
  Result := False;
end;

{ ---------- main entry ---------- }

class function TSourcePackScanner.RebuildIndex(const ASourceRoot: string;
  const ADisplayName: string): TSourcePackScanResult;
var
  DB: TArtifactDB;
  PackId, DisplayName, RelPath, FileName, Ext, Layer, ContentKind,
    ClaimStr, PubPolicy, Hash: string;
  Files: TArray<string>;
  TopDir, SubDir: string;
  I: Integer;
  Size: Int64;
  MTime: TDateTime;
  LayerCount: Integer;
begin
  Result.Init;

  if not TDirectory.Exists(ASourceRoot) then
  begin
    SetLength(Result.Errors, 1);
    Result.Errors[0] := 'Directory not found: ' + ASourceRoot;
    Exit;
  end;

  DisplayName := ADisplayName;
  if DisplayName = '' then
    DisplayName := TPath.GetFileName(ASourceRoot);

  Result.DisplayRoot := ASourceRoot;

  // Collect files
  Files := TDirectory.GetFiles(ASourceRoot, '*.*', TSearchOption.soAllDirectories);
  Result.TotalFiles := Length(Files);

  DB := ArtifactOS_DB;
  DB.Connect;
  try
    DB.Connection.StartTransaction;
    try
      // ── Upsert source_pack row (outside transaction to avoid ON CONFLICT abort) ──
      DB.Connection.Commit;   // end the wrapping transaction temporarily

      // Try INSERT; if conflict, fetch existing id
      PackId := '';
      try
        DB.Execute(
          'INSERT INTO artifactos.source_pack (display_name, source_root, pack_type, loading_level, status) ' +
          'VALUES (''' + SafeStr(DisplayName) + ''', ''' + SafeStr(BackslashToSlash(ASourceRoot)) + ''', ' +
          '''theory_system'', ''SPL0'', ''active'') ' +
          'ON CONFLICT DO NOTHING');
        PackId := DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.source_pack WHERE source_root=''' +
          SafeStr(BackslashToSlash(ASourceRoot)) + ''' ORDER BY created_at DESC LIMIT 1');
      except
        on E: Exception do
          WriteLn('  scanner: source_pack upsert: ', Copy(E.Message, 1, 80));
      end;

      if PackId = '' then
      begin
        // Already exists — fetch existing id as text to avoid GUID byte-swap
        PackId := DB.ExecuteScalar(
          'SELECT id::text FROM artifactos.source_pack WHERE source_root=''' +
          SafeStr(BackslashToSlash(ASourceRoot)) + ''' ORDER BY created_at DESC LIMIT 1');
        // Update display name in case it changed
        DB.Execute('UPDATE artifactos.source_pack SET display_name=''' +
          SafeStr(DisplayName) + ''' WHERE id=''' + PackId + '''');
      end;

      // Strip {braces} from FireDAC Guid format for PG uuid compatibility
      PackId := PackId.Replace('{', '').Replace('}', '');

      DB.Connection.StartTransaction;  // restart transaction for bulk insert

      Result.SourcePackId := PackId;

      // ── Clear old inventory for this pack ──
      DB.Execute('DELETE FROM artifactos.source_inventory_candidate WHERE source_pack_id=''' + PackId + '''');

      // ── Scan files ──
      for I := 0 to High(Files) do
      begin
        if (I mod 5000 = 0) and (I > 0) then
          WriteLn('  progress ', I, '/', Length(Files), ' indexed=', Result.IndexedFiles, ' skipped=', Result.SkippedFiles);
        FileName := Files[I];

        try
        if FileName.Contains('/.git/') or FileName.Contains('\.git\') or
           FileName.Contains('/.claude/') or FileName.Contains('\.claude\') or
           FileName.Contains('/.atomcode/') or FileName.Contains('\.atomcode\') or
           FileName.Contains('/.hermes/') or FileName.Contains('\.hermes\') then
        begin
          Inc(Result.SkippedFiles);
          Continue;
        end;

        Ext := LowerCase(TPath.GetExtension(FileName));
        if not IsValidExtension(Ext) then
        begin
          Inc(Result.SkippedFiles);
          Continue;
        end;

        // ── Determine layer from directory structure ──
        // Extract top-level and sub-directory names from relative path
        RelPath := FileName.Substring(Length(ASourceRoot));
        if RelPath.StartsWith('\') or RelPath.StartsWith('/') then
          RelPath := RelPath.Substring(1);

        // Split into parts: ['10-哲学核心层（DM）', 'AA-母版源层', 'file.md']
        var Parts := RelPath.Split(['\', '/']);

        // Determine layer: try sub-layer first (AA-ZZ), then top-level
        Layer := 'evidence';  // default
        if Length(Parts) >= 2 then
        begin
          SubDir := Parts[Length(Parts) - 2];  // parent directory name
          if Length(SubDir) >= 2 then
          begin
            var Prefix := UpperCase(Copy(SubDir, 1, 2));
            if (Prefix >= 'AA') and (Prefix <= 'ZZ') and (Length(SubDir) > 2) and (SubDir[3] = '-') then
              Layer := LayerFromSubDir(SubDir)
            else
              Layer := LayerFromTopDir(Parts[0]);
          end;
        end
        else if Length(Parts) = 1 then
        begin
          // Root-level file → governance
          Layer := 'governance';
        end;

        // ── File metadata ──
        ContentKind := ContentKindFromExt(Ext);
        ClaimStr := ClaimStrengthFromLayer(Layer);
        PubPolicy := PublishPolicyFromLayer(Layer);

        Size := 0;
        try Size := TFile.GetSize(FileName); except end;
        MTime := 0;
        try MTime := TFile.GetLastWriteTime(FileName); except end;

        Hash := '';
        // Only hash text files under 1 MB
        if (ContentKind <> 'image') and (ContentKind <> 'archive') and (Size < 1048576) then
        begin
          try
            Hash := THashSHA2.GetHashString(TFile.ReadAllText(FileName),
              THashSHA2.TSHA2Version.SHA256).Substring(0, 32);
          except
            Hash := 'unreadable';
          end;
        end;

        // ── Insert inventory row ──
        try
          DB.Execute(
            'INSERT INTO artifactos.source_inventory_candidate ' +
            '(source_pack_id, file_path, content_kind, source_layer, ' +
            ' candidate_claim_strength, external_publish_policy, ' +
            ' human_review_status, file_size_bytes, file_mtime, file_hash) ' +
            'VALUES (''' + PackId + ''', ' +
            '''' + SafeStr(BackslashToSlash(FileName)) + ''', ' +
            '''' + ContentKind + ''', ' +
            '''' + Layer + ''', ' +
            '''' + ClaimStr + ''', ' +
            '''' + PubPolicy + ''', ' +
            '''approved'', ' +       // auto-approve for theory_system pack
            IntToStr(Size) + ', ' +
            '''' + FormatDateTime('yyyy-mm-dd hh:nn:ss', MTime) + ''', ' +
            '''' + Hash + ''')');
        except
          on E: Exception do
          begin
            // PG aborts the entire transaction on first error — must rollback + restart
            try DB.Connection.Rollback; except end;
            try
              DB.Connection.StartTransaction;
            except
              on E2: Exception do
              begin
                WriteLn('  scanner: StartTransaction failed: ', E2.Message);
                raise;
              end;
            end;
            SetLength(Result.Errors, Length(Result.Errors) + 1);
            Result.Errors[High(Result.Errors)] := FileName + ': ' + Copy(E.Message, 1, 120);
            Continue;
          end;
        end;

        Inc(Result.IndexedFiles);

        // Track layer counts (use AddOrSetValue — TDictionary[] setter may raise
        // EListError in certain Delphi builds after long-running loops)
        if not Result.LayerCounts.TryGetValue(Layer, LayerCount) then
          LayerCount := 0;
        Result.LayerCounts.AddOrSetValue(Layer, LayerCount + 1);

        except
          on E: Exception do
          begin
            WriteLn('  scanner: OUTER except at file #', I, ' name=', FileName,
              ' class=', E.ClassName, ' msg=', E.Message);
            raise;
          end;
        end;
      end;

      // ── Update SPL based on inventory ──
      var HasCanonical := Result.LayerCounts.ContainsKey('canonical') and (Result.LayerCounts['canonical'] > 0);
      var HasGovernance := Result.LayerCounts.ContainsKey('governance') and (Result.LayerCounts['governance'] > 0);
      var NewSPL: string;
      if HasCanonical and HasGovernance and (Result.IndexedFiles >= 100) then
        NewSPL := 'SPL2'   // manifest ready
      else if (Result.IndexedFiles >= 10) then
        NewSPL := 'SPL1'   // boundary identified
      else
        NewSPL := 'SPL0';  // raw corpus

      DB.Execute('UPDATE artifactos.source_pack SET loading_level=''' + NewSPL +
        ''', metadata = COALESCE(metadata, ''{}''::jsonb) || ''{"human_decision_id":"system:rebuild_index","human_decision_reason":"automated SPL update after full directory scan"}''::jsonb' +
        ' WHERE id=''' + PackId + '''');

      // ── Record loading decision ──
      DB.Execute(
        'INSERT INTO artifactos.source_pack_loading_decision ' +
        '(source_pack_id, decision_type, allow_production, decided_by, evidence) ' +
        'VALUES (''' + PackId + ''', ' +
        '''' + IfThen(NewSPL = 'SPL2', 'allow_trial_generation', 'allow_inventory') + ''', ' +
        IfThen(NewSPL >= 'SPL3', 'true', 'false') + ', ' +
        '''system:rebuild_index'', ' +
        '''{"total_files":' + IntToStr(Result.TotalFiles) +
        ', "indexed":' + IntToStr(Result.IndexedFiles) +
        ', "skipped":' + IntToStr(Result.SkippedFiles) +
        ', "spl":"' + NewSPL + '"}'')');

      DB.Connection.Commit;
    except
      DB.Connection.Rollback;
      raise;
    end;
  finally
    DB.Disconnect;
  end;
end;

class function TSourcePackScanner.GetActiveSourcePackId: string;
var
  DB: TArtifactDB;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Result := DB.ExecuteScalar(
      'SELECT id FROM artifactos.source_pack WHERE status=''active'' LIMIT 1');
  finally
    DB.Disconnect;
  end;
end;

class function TSourcePackScanner.GetIndexedFileCount: Integer;
var
  DB: TArtifactDB;
  Val: string;
begin
  DB := ArtifactOS_DB;
  DB.Connect;
  try
    Val := DB.ExecuteScalar(
      'SELECT COUNT(*)::text FROM artifactos.source_inventory_candidate sic ' +
      'JOIN artifactos.source_pack sp ON sp.id = sic.source_pack_id ' +
      'WHERE sp.status = ''active''');
    Result := StrToIntDef(Val, 0);
  finally
    DB.Disconnect;
  end;
end;

end.
