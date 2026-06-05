unit DeepFrames.Workflow.PackageExporter;

/// <summary>
/// Candidate package exporter for DeepFrames Phase 6.
///
/// Writes self-contained candidate packages to disk that downstream
/// publishing systems (ArtifactOS, manual upload) can consume without
/// understanding DeepFrames internal tables.
///
/// Package structure:
///   packages/{package_id}/{platform}/
///     manifest.json          — full asset listing, source trace, quality snapshot
///     video/                 — final video file (video packages)
///     audio/                 — final audio file (audio packages)
///     cover.png              — platform cover image
///     subtitles/zh.srt       — subtitle file
///     metadata.json          — title, description, tags per platform
///     quality.json           — gate results summary
///
/// Source trace (P6.4):
///   Each package manifest includes a complete provenance chain:
///   source_document → script_document → accuracy_report → variant_document
///   → shot_document → audio_manifest → video_ir → prompt_runs → gate_results
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Domain.Types;

type
  /// <summary>Result of a package export operation.</summary>
  TPackageExportResult = record
    Success: Boolean;
    PackageId: string;
    OutputDir: string;
    ManifestFile: string;
    FilesExported: Integer;
    TotalSizeBytes: Int64;
    ErrorMessage: string;
    /// <summary>True if source trace is complete and verifiable.</summary>
    SourceTraceComplete: Boolean;
    SourceTraceIssues: TArray<string>;
  end;

  /// <summary>Metadata for a B站 video package.</summary>
  TBilibiliMetadata = record
    Title: string;
    Description: string;
    Tags: TArray<string>;
    Category: string;
    IsOriginal: Boolean;
    CoverPrompt: string;
  end;

  /// <summary>Package exporter.</summary>
  TPackageExporter = class
  public
    /// <summary>Export an audio-only candidate package.</summary>
    class function ExportAudioPackage(
      const APackage: TCandidatePackage;
      const AManifest: TAudioManifest;
      const AAssets: TArray<TAssetRecord>;
      const ABaseDir: string): TPackageExportResult; static;

    /// <summary>Export a B站 video candidate package.</summary>
    class function ExportBilibiliPackage(
      const APackage: TCandidatePackage;
      const AManifest: TAudioManifest;
      const AVideoIR: TVideoIR;
      const AVideoJob: TVideoJob;
      const AAssets: TArray<TAssetRecord>;
      const AMetadata: TBilibiliMetadata;
      const ABaseDir: string): TPackageExportResult; static;

    /// <summary>Build a complete package manifest JSON.</summary>
    class function BuildPackageManifest(
      const APackage: TCandidatePackage;
      const AAssetList: TArray<string>;
      const AOutputDir: string): string; static;

    /// <summary>Build B站 metadata JSON.</summary>
    class function BuildBilibiliMetadata(const AData: TBilibiliMetadata): string; static;

    /// <summary>
    /// Verify source trace completeness for a package.
    /// Returns True if all fields are present and linkable.
    /// </summary>
    class function VerifySourceTrace(const APackage: TCandidatePackage;
      out AIssues: TArray<string>): Boolean; static;

    /// <summary>
    /// Write a file with content to the package output directory.
    /// Creates directories as needed.
    /// </summary>
    class function WritePackageFile(const ABaseDir, ARelativePath,
      AContent: string): string; static;

    /// <summary>Default B站 metadata for a package.</summary>
    class function DefaultBilibiliMetadata(const ATitleHint: string): TBilibiliMetadata; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  DeepFrames.Shared.Consts;

{ TPackageExporter }

class function TPackageExporter.WritePackageFile(const ABaseDir, ARelativePath,
  AContent: string): string;
begin
  Result := TPath.Combine(ABaseDir, ARelativePath);
  ForceDirectories(TPath.GetDirectoryName(Result));
  TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

class function TPackageExporter.VerifySourceTrace(const APackage: TCandidatePackage;
  out AIssues: TArray<string>): Boolean;
var
  Issues: TArray<string>;
begin
  SetLength(Issues, 0);

  if APackage.VariantDocumentId = '' then
  begin
    SetLength(Issues, Length(Issues) + 1);
    Issues[High(Issues)] := 'Missing variant_document_id';
  end;

  if APackage.AudioManifestId = '' then
  begin
    SetLength(Issues, Length(Issues) + 1);
    Issues[High(Issues)] := 'Missing audio_manifest_id';
  end;

  if APackage.VideoIRId = '' then
  begin
    // Audio-only packages may not have a video IR
    if SameText(APackage.DeliveryType, DELIVERY_TYPE_VIDEO) then
    begin
      SetLength(Issues, Length(Issues) + 1);
      Issues[High(Issues)] := 'Missing video_ir_id for video delivery package';
    end;
  end;

  if APackage.SourceTraceJson = '' then
  begin
    SetLength(Issues, Length(Issues) + 1);
    Issues[High(Issues)] := 'Empty source_trace_json';
  end
  else
  begin
    // Verify source_trace JSON structure
    var TraceObj := TJSONObject.ParseJSONValue(APackage.SourceTraceJson) as TJSONObject;
    if TraceObj = nil then
    begin
      SetLength(Issues, Length(Issues) + 1);
      Issues[High(Issues)] := 'source_trace_json is not valid JSON';
    end
    else
    begin
      if TraceObj.GetValue('variant_document_id').Value = '' then
      begin
        SetLength(Issues, Length(Issues) + 1);
        Issues[High(Issues)] := 'source_trace: missing variant_document_id';
      end;
      if TraceObj.GetValue('audio_manifest_id').Value = '' then
      begin
        SetLength(Issues, Length(Issues) + 1);
        Issues[High(Issues)] := 'source_trace: missing audio_manifest_id';
      end;
      if TraceObj.GetValue('video_ir_id').Value = '' then
      begin
        if SameText(APackage.DeliveryType, DELIVERY_TYPE_VIDEO) then
        begin
          SetLength(Issues, Length(Issues) + 1);
          Issues[High(Issues)] := 'source_trace: missing video_ir_id';
        end;
      end;
      TraceObj.Free;
    end;
  end;

  AIssues := Issues;
  Result := Length(Issues) = 0;
end;

class function TPackageExporter.BuildPackageManifest(
  const APackage: TCandidatePackage;
  const AAssetList: TArray<string>;
  const AOutputDir: string): string;
var
  Obj: TJSONObject;
  AssetsArr: TJSONArray;
  S: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('package_id', APackage.PackageId);
    Obj.AddPair('project_id', APackage.ProjectId);
    Obj.AddPair('content_unit_id', APackage.ContentUnitId);
    Obj.AddPair('label', APackage.&Label);
    Obj.AddPair('target_platform', APackage.TargetPlatform);
    Obj.AddPair('delivery_type', APackage.DeliveryType);
    Obj.AddPair('version_no', TJSONNumber.Create(APackage.VersionNo));
    Obj.AddPair('output_dir', AOutputDir);

    // Asset listing
    AssetsArr := TJSONArray.Create;
    for S in AAssetList do
      AssetsArr.Add(S);
    Obj.AddPair('assets', AssetsArr);

    // Embed source trace and quality snapshot
    if APackage.SourceTraceJson <> '' then
      Obj.AddPair('source_trace',
        TJSONObject.ParseJSONValue(APackage.SourceTraceJson) as TJSONValue)
    else
      Obj.AddPair('source_trace', TJSONObject.Create);

    if APackage.QualitySnapshotJson <> '' then
      Obj.AddPair('quality_snapshot',
        TJSONObject.ParseJSONValue(APackage.QualitySnapshotJson) as TJSONValue)
    else
      Obj.AddPair('quality_snapshot', TJSONObject.Create);

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TPackageExporter.BuildBilibiliMetadata(
  const AData: TBilibiliMetadata): string;
var
  Obj: TJSONObject;
  TagsArr: TJSONArray;
  Tag: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('title', AData.Title);
    Obj.AddPair('description', AData.Description);
    TagsArr := TJSONArray.Create;
    for Tag in AData.Tags do
      TagsArr.Add(Tag);
    Obj.AddPair('tags', TagsArr);
    Obj.AddPair('category', AData.Category);
    Obj.AddPair('is_original', TJSONBool.Create(AData.IsOriginal));
    Obj.AddPair('cover_prompt', AData.CoverPrompt);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TPackageExporter.DefaultBilibiliMetadata(
  const ATitleHint: string): TBilibiliMetadata;
begin
  if Trim(ATitleHint) <> '' then
    Result.Title := ATitleHint
  else
    Result.Title := 'DeepFrames 自动生成视频';
  Result.Description := '由 DeepFrames 自动生成的视频内容。';
  Result.Tags := ['DeepFrames', 'AI生成', '知识分享'];
  Result.Category := '知识';
  Result.IsOriginal := True;
  Result.CoverPrompt := 'Clean, modern cover design with title text overlay';
end;

class function TPackageExporter.ExportAudioPackage(
  const APackage: TCandidatePackage;
  const AManifest: TAudioManifest;
  const AAssets: TArray<TAssetRecord>;
  const ABaseDir: string): TPackageExportResult;
var
  OutputDir: string;
  AssetList: TArray<string>;
  ManifestJson: string;
  Metadata: string;
  I: Integer;
begin
  Result.PackageId := APackage.PackageId;
  Result.FilesExported := 0;
  Result.TotalSizeBytes := 0;
  Result.ErrorMessage := '';

  OutputDir := TPath.Combine(ABaseDir, APackage.PackageId);
  OutputDir := TPath.Combine(OutputDir, APackage.TargetPlatform);
  Result.OutputDir := OutputDir;

  // Verify source trace
  Result.SourceTraceComplete := VerifySourceTrace(APackage, Result.SourceTraceIssues);

  // Build asset list
  SetLength(AssetList, Length(AAssets));
  for I := 0 to High(AAssets) do
    AssetList[I] := AAssets[I].Uri;

  // Write manifest
  ManifestJson := BuildPackageManifest(APackage, AssetList, OutputDir);
  Result.ManifestFile := WritePackageFile(ABaseDir,
    Format('%s/%s/manifest.json', [APackage.PackageId, APackage.TargetPlatform]),
    ManifestJson);
  Inc(Result.FilesExported);

  // Write audio metadata
  var AudioMeta := TJSONObject.Create;
  try
    AudioMeta.AddPair('schema_version', APP_SCHEMA_VERSION);
    AudioMeta.AddPair('duration_sec', TJSONNumber.Create(AManifest.DurationSec));
    AudioMeta.AddPair('sample_rate', TJSONNumber.Create(AManifest.SampleRate));
    AudioMeta.AddPair('channels', TJSONNumber.Create(AManifest.Channels));
    AudioMeta.AddPair('codec', AManifest.Codec);
    AudioMeta.AddPair('bgm_enabled', TJSONBool.Create(AManifest.BgmEnabled));
    AudioMeta.AddPair('measured_lufs', TJSONNumber.Create(AManifest.MeasuredLufs));
    AudioMeta.AddPair('target_lufs', TJSONNumber.Create(AManifest.TargetLufs));
    Metadata := AudioMeta.ToJSON;
  finally
    AudioMeta.Free;
  end;

  WritePackageFile(ABaseDir,
    Format('%s/%s/metadata.json', [APackage.PackageId, APackage.TargetPlatform]),
    Metadata);
  Inc(Result.FilesExported);

  // Write quality snapshot
  if APackage.QualitySnapshotJson <> '' then
  begin
    WritePackageFile(ABaseDir,
      Format('%s/%s/quality.json', [APackage.PackageId, APackage.TargetPlatform]),
      APackage.QualitySnapshotJson);
    Inc(Result.FilesExported);
  end;

  // Write source trace
  if APackage.SourceTraceJson <> '' then
  begin
    WritePackageFile(ABaseDir,
      Format('%s/%s/source_trace.json', [APackage.PackageId, APackage.TargetPlatform]),
      APackage.SourceTraceJson);
    Inc(Result.FilesExported);
  end;

  // Compute total size from assets
  for I := 0 to High(AAssets) do
    Inc(Result.TotalSizeBytes, AAssets[I].ByteSize);

  Result.Success := True;
end;

class function TPackageExporter.ExportBilibiliPackage(
  const APackage: TCandidatePackage;
  const AManifest: TAudioManifest;
  const AVideoIR: TVideoIR;
  const AVideoJob: TVideoJob;
  const AAssets: TArray<TAssetRecord>;
  const AMetadata: TBilibiliMetadata;
  const ABaseDir: string): TPackageExportResult;
var
  OutputDir: string;
  AssetList: TArray<string>;
  ManifestJson: string;
  MetadataJson: string;
  I: Integer;
begin
  Result.PackageId := APackage.PackageId;
  Result.FilesExported := 0;
  Result.TotalSizeBytes := 0;
  Result.ErrorMessage := '';

  OutputDir := TPath.Combine(ABaseDir, APackage.PackageId);
  OutputDir := TPath.Combine(OutputDir, APackage.TargetPlatform);
  Result.OutputDir := OutputDir;

  // Verify source trace
  Result.SourceTraceComplete := VerifySourceTrace(APackage, Result.SourceTraceIssues);

  // Build asset list
  SetLength(AssetList, Length(AAssets));
  for I := 0 to High(AAssets) do
    AssetList[I] := AAssets[I].Uri;

  // Write manifest
  ManifestJson := BuildPackageManifest(APackage, AssetList, OutputDir);
  Result.ManifestFile := WritePackageFile(ABaseDir,
    Format('%s/%s/manifest.json', [APackage.PackageId, APackage.TargetPlatform]),
    ManifestJson);
  Inc(Result.FilesExported);

  // Write B站 metadata (title, desc, tags)
  MetadataJson := BuildBilibiliMetadata(AMetadata);
  WritePackageFile(ABaseDir,
    Format('%s/%s/metadata.json', [APackage.PackageId, APackage.TargetPlatform]),
    MetadataJson);
  Inc(Result.FilesExported);

  // Write quality snapshot
  if APackage.QualitySnapshotJson <> '' then
  begin
    WritePackageFile(ABaseDir,
      Format('%s/%s/quality.json', [APackage.PackageId, APackage.TargetPlatform]),
      APackage.QualitySnapshotJson);
    Inc(Result.FilesExported);
  end;

  // Write source trace
  if APackage.SourceTraceJson <> '' then
  begin
    WritePackageFile(ABaseDir,
      Format('%s/%s/source_trace.json', [APackage.PackageId, APackage.TargetPlatform]),
      APackage.SourceTraceJson);
    Inc(Result.FilesExported);
  end;

  // Write video IR summary
  var IRSummary := TJSONObject.Create;
  try
    IRSummary.AddPair('schema_version', APP_SCHEMA_VERSION);
    IRSummary.AddPair('render_backend', AVideoIR.RenderBackend);
    IRSummary.AddPair('estimated_duration_sec', TJSONNumber.Create(AVideoIR.EstimatedDurationSec));
    IRSummary.AddPair('actual_duration_sec', TJSONNumber.Create(AVideoIR.ActualDurationSec));
    IRSummary.AddPair('scene_count', TJSONNumber.Create(AVideoIR.SceneCount));
    IRSummary.AddPair('template_version', AVideoIR.TemplateVersion);
    MetadataJson := IRSummary.ToJSON;
  finally
    IRSummary.Free;
  end;
  WritePackageFile(ABaseDir,
    Format('%s/%s/video_ir.json', [APackage.PackageId, APackage.TargetPlatform]),
    MetadataJson);
  Inc(Result.FilesExported);

  // Compute total size from assets
  for I := 0 to High(AAssets) do
    Inc(Result.TotalSizeBytes, AAssets[I].ByteSize);

  Result.Success := True;
end;

end.