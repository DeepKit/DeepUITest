unit DeepFrames.Workflow.DocumentExport;

/// <summary>
/// Document export manager for DeepFrames.
///
/// Exports source_document, script_document, and shot_document content
/// to human-readable formats (JSON, text) for review and downstream consumption.
///
/// Each export preserves the full version chain — no old versions are overwritten.
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Domain.Types;

type
  TExportFormat = (efJSON, efText, efMarkdown);

  TExportResult = record
    Success: Boolean;
    OutputFile: string;
    Format: TExportFormat;
    SizeBytes: Int64;
    ErrorMessage: string;
  end;

  TDocumentExport = class
  public
    /// <summary>Export a source document to a file.</summary>
    class function ExportSourceDocument(const ADoc: TSourceDocumentVersion;
      const AOutputDir: string; AFormat: TExportFormat): TExportResult; static;

    /// <summary>Export a script document with its accuracy report.</summary>
    class function ExportScriptDocument(const AScript: TScriptDocumentVersion;
      const AAccuracy: TAccuracyReport; const AOutputDir: string;
      AFormat: TExportFormat): TExportResult; static;

    /// <summary>Export a shot document as a production script.</summary>
    class function ExportShotDocument(const AShot: TShotDocumentVersion;
      const AOutputDir: string; AFormat: TExportFormat): TExportResult; static;

    /// <summary>Export the full document chain for a project.</summary>
    class function ExportDocumentChain(
      const ASource: TSourceDocumentVersion;
      const AScripts: TArray<TScriptDocumentVersion>;
      const AAccuracyReports: TArray<TAccuracyReport>;
      const AVariants: TArray<TVariantDocumentVersion>;
      const AShots: TArray<TShotDocumentVersion>;
      const AOutputDir: string): TArray<TExportResult>; static;

    /// <summary>Build a document chain summary JSON (all versions linked).</summary>
    class function BuildChainSummary(
      const ASource: TSourceDocumentVersion;
      const AScripts: TArray<TScriptDocumentVersion>;
      const AAccuracy: TArray<TAccuracyReport>;
      const AVariants: TArray<TVariantDocumentVersion>;
      const AShots: TArray<TShotDocumentVersion>): string; static;

    /// <summary>Write content to file, creating directories as needed.</summary>
    class function WriteFile(const AOutputDir, AFilename, AContent: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DeepFrames.Shared.Consts;

class function TDocumentExport.WriteFile(const AOutputDir, AFilename,
  AContent: string): string;
begin
  Result := TPath.Combine(AOutputDir, AFilename);
  ForceDirectories(TPath.GetDirectoryName(Result));
  TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

class function TDocumentExport.ExportSourceDocument(
  const ADoc: TSourceDocumentVersion; const AOutputDir: string;
  AFormat: TExportFormat): TExportResult;
var
  Content: string;
  FileName: string;
begin
  Result.Format := AFormat;
  Result.ErrorMessage := '';

  case AFormat of
    efJSON:
      begin
        var Obj := TJSONObject.Create;
        try
          Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
          Obj.AddPair('document_id', ADoc.DocumentId);
          Obj.AddPair('project_id', ADoc.ProjectId);
          Obj.AddPair('content_unit_id', ADoc.ContentUnitId);
          Obj.AddPair('version_no', TJSONNumber.Create(ADoc.VersionNo));
          Obj.AddPair('content_hash', ADoc.ContentHash);
          Obj.AddPair('source_uri', ADoc.SourceUri);
          Obj.AddPair('status', ADoc.Status);
          Obj.AddPair('markdown_text', ADoc.MarkdownText);
          Content := Obj.ToJSON;
        finally
          Obj.Free;
        end;
        FileName := Format('source_v%d.json', [ADoc.VersionNo]);
      end;

    efText:
      begin
        Content := ADoc.MarkdownText;
        FileName := Format('source_v%d.txt', [ADoc.VersionNo]);
      end;

    efMarkdown:
      begin
        Content := '# Source Document v' + IntToStr(ADoc.VersionNo) + sLineBreak +
          sLineBreak + '**ID**: ' + ADoc.DocumentId + sLineBreak +
          '**Source**: ' + ADoc.SourceUri + sLineBreak +
          '**Status**: ' + ADoc.Status + sLineBreak +
          sLineBreak + ADoc.MarkdownText;
        FileName := Format('source_v%d.md', [ADoc.VersionNo]);
      end;
  else
    begin
      Content := ADoc.MarkdownText;
      FileName := Format('source_v%d.txt', [ADoc.VersionNo]);
    end;
  end;

  try
    Result.OutputFile := WriteFile(AOutputDir, FileName, Content);
    Result.SizeBytes := Length(Content);
    Result.Success := True;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

class function TDocumentExport.ExportScriptDocument(
  const AScript: TScriptDocumentVersion; const AAccuracy: TAccuracyReport;
  const AOutputDir: string; AFormat: TExportFormat): TExportResult;
var
  Content: string;
  FileName: string;
begin
  Result.Format := AFormat;

  var Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('document_id', AScript.DocumentId);
    Obj.AddPair('project_id', AScript.ProjectId);
    Obj.AddPair('content_unit_id', AScript.ContentUnitId);
    Obj.AddPair('version_no', TJSONNumber.Create(AScript.VersionNo));
    Obj.AddPair('parent_document_id', AScript.ParentDocumentId);
    Obj.AddPair('source_document_id', AScript.SourceDocumentId);
    Obj.AddPair('content_hash', AScript.ContentHash);
    Obj.AddPair('status', AScript.Status);

    if AAccuracy.ReportId <> '' then
    begin
      var AccObj := TJSONObject.Create;
      AccObj.AddPair('coverage_score', TJSONNumber.Create(AAccuracy.CoverageScore));
      AccObj.AddPair('distortion_score', TJSONNumber.Create(AAccuracy.DistortionScore));
      AccObj.AddPair('result', AAccuracy.Result);
      Obj.AddPair('accuracy_report', AccObj);
    end;

    Content := Obj.ToJSON;
  finally
    Obj.Free;
  end;

  FileName := Format('script_v%d.json', [AScript.VersionNo]);
  try
    Result.OutputFile := WriteFile(AOutputDir, FileName, Content);
    Result.SizeBytes := Length(Content);
    Result.Success := True;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

class function TDocumentExport.ExportShotDocument(
  const AShot: TShotDocumentVersion; const AOutputDir: string;
  AFormat: TExportFormat): TExportResult;
var
  Content: string;
  FileName: string;
begin
  Result.Format := AFormat;

  var Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('document_id', AShot.DocumentId);
    Obj.AddPair('project_id', AShot.ProjectId);
    Obj.AddPair('content_unit_id', AShot.ContentUnitId);
    Obj.AddPair('version_no', TJSONNumber.Create(AShot.VersionNo));
    Obj.AddPair('parent_document_id', AShot.ParentDocumentId);
    Obj.AddPair('content_hash', AShot.ContentHash);
    Obj.AddPair('status', AShot.Status);
    Content := Obj.ToJSON;
  finally
    Obj.Free;
  end;

  FileName := Format('shot_v%d.json', [AShot.VersionNo]);
  try
    Result.OutputFile := WriteFile(AOutputDir, FileName, Content);
    Result.SizeBytes := Length(Content);
    Result.Success := True;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

class function TDocumentExport.BuildChainSummary(
  const ASource: TSourceDocumentVersion;
  const AScripts: TArray<TScriptDocumentVersion>;
  const AAccuracy: TArray<TAccuracyReport>;
  const AVariants: TArray<TVariantDocumentVersion>;
  const AShots: TArray<TShotDocumentVersion>): string;
var
  Obj: TJSONObject;
  ItemsArr: TJSONArray;
  ItemObj: TJSONObject;
  I: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('source_document_id', ASource.DocumentId);
    Obj.AddPair('source_version_no', TJSONNumber.Create(ASource.VersionNo));
    Obj.AddPair('exported_at', '2026-06-04T00:00:00Z');

    ItemsArr := TJSONArray.Create;

    // Source
    ItemObj := TJSONObject.Create;
    ItemObj.AddPair('type', 'source_document');
    ItemObj.AddPair('id', ASource.DocumentId);
    ItemObj.AddPair('version', TJSONNumber.Create(ASource.VersionNo));
    ItemsArr.AddElement(ItemObj);

    // Scripts
    for I := 0 to High(AScripts) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('type', 'script_document');
      ItemObj.AddPair('id', AScripts[I].DocumentId);
      ItemObj.AddPair('version', TJSONNumber.Create(AScripts[I].VersionNo));
      ItemObj.AddPair('parent_id', AScripts[I].ParentDocumentId);
      ItemsArr.AddElement(ItemObj);
    end;

    // Accuracy reports
    for I := 0 to High(AAccuracy) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('type', 'accuracy_report');
      ItemObj.AddPair('id', AAccuracy[I].ReportId);
      ItemObj.AddPair('coverage', TJSONNumber.Create(AAccuracy[I].CoverageScore));
      ItemObj.AddPair('distortion', TJSONNumber.Create(AAccuracy[I].DistortionScore));
      ItemsArr.AddElement(ItemObj);
    end;

    // Variants
    for I := 0 to High(AVariants) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('type', 'variant_document');
      ItemObj.AddPair('id', AVariants[I].DocumentId);
      ItemObj.AddPair('variant_kind', AVariants[I].VariantKind);
      ItemObj.AddPair('target_platform', AVariants[I].TargetPlatform);
      ItemsArr.AddElement(ItemObj);
    end;

    // Shots
    for I := 0 to High(AShots) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('type', 'shot_document');
      ItemObj.AddPair('id', AShots[I].DocumentId);
      ItemObj.AddPair('version', TJSONNumber.Create(AShots[I].VersionNo));
      ItemsArr.AddElement(ItemObj);
    end;

    Obj.AddPair('chain', ItemsArr);
    Obj.AddPair('total_items', TJSONNumber.Create(ItemsArr.Count));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TDocumentExport.ExportDocumentChain(
  const ASource: TSourceDocumentVersion;
  const AScripts: TArray<TScriptDocumentVersion>;
  const AAccuracyReports: TArray<TAccuracyReport>;
  const AVariants: TArray<TVariantDocumentVersion>;
  const AShots: TArray<TShotDocumentVersion>;
  const AOutputDir: string): TArray<TExportResult>;
var
  Results: TArray<TExportResult>;
  I: Integer;
  ChainFile: string;
begin
  SetLength(Results, 0);

  // Export source document
  var SrcResult := ExportSourceDocument(ASource, AOutputDir, efJSON);
  SetLength(Results, Length(Results) + 1);
  Results[High(Results)] := SrcResult;

  // Export script documents with accuracy
  for I := 0 to High(AScripts) do
  begin
    var Acc: TAccuracyReport;
    for var A in AAccuracyReports do
      if SameText(A.ScriptDocumentId, AScripts[I].DocumentId) then
      begin
        Acc := A;
        Break;
      end;
    var ScriptResult := ExportScriptDocument(AScripts[I], Acc, AOutputDir, efJSON);
    SetLength(Results, Length(Results) + 1);
    Results[High(Results)] := ScriptResult;
  end;

  // Export chain summary
  var Summary := BuildChainSummary(ASource, AScripts, AAccuracyReports, AVariants, AShots);
  ChainFile := WriteFile(AOutputDir, 'chain_summary.json', Summary);
  SetLength(Results, Length(Results) + 1);
  with Results[High(Results)] do
  begin
    Success := True;
    OutputFile := ChainFile;
    Format := efJSON;
    SizeBytes := Length(Summary);
  end;
end;

end.