unit DeepFrames.Workflow.AssetRetention;

/// <summary>
/// 102C asset retention strategy enforcement for DeepFrames.
///
/// Per docs/06.dist-内容分发-distribution.md and docs/12.db-state:
///   C1 — long-term retention: final candidate packages, manifests
///   C2 — short-term retention: final video, cover, merged audio (30 days)
///   C3 — cleanup-eligible: intermediate snapshots, previews, temp files
///   C4 — immediate cleanup: failed/partial assets, worker temp
///
/// Protection rules:
///   - Assets referenced by candidate_package.source_trace are NEVER cleaned
///   - Cascade protection: if an asset is protected, its upstream deps are too
///   - Failed/partial assets: never registered as ready, deleted immediately
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Domain.Types;

type
  /// <summary>Cleanup eligibility verdict for one asset.</summary>
  TCleanupVerdict = record
    AssetId: string;
    RetentionClass: string;
    CanCleanup: Boolean;
    ProtectedUntil: string;     // ISO 8601 date
    Reason: string;
    ReferencedByPackages: TArray<string>;
  end;

  /// <summary>Batch cleanup plan.</summary>
  TCleanupPlan = record
    TotalAssets: Integer;
    CleanupEligible: Integer;
    Protected: Integer;
    Verdicts: TArray<TCleanupVerdict>;
    TotalBytesEligible: Int64;
    TotalBytesProtected: Int64;
  end;

  /// <summary>102C asset retention strategy.</summary>
  TAssetRetention = class
  public
    /// <summary>Get default retention period for a class (days). C1=forever(0), C2=30, C3=7, C4=0.</summary>
    class function RetentionDays(const ARetentionClass: string): Integer; static;

    /// <summary>Compute protected_until timestamp for a retention class.</summary>
    class function ComputeProtectedUntil(const ARetentionClass: string): string; static;

    /// <summary>
    /// Determine if an asset is protected by candidate package references.
    /// Returns list of package IDs that reference this asset.
    /// </summary>
    class function GetPackageReferences(const AAssetId: string;
      const APackages: TArray<TCandidatePackage>): TArray<string>; static;

    /// <summary>
    /// Check if an asset should be cascade-protected because another
    /// protected asset depends on it.
    /// </summary>
    class function IsCascadeProtected(const AAssetId: string;
      const AProtectedAssetIds: TArray<string>;
      const ADependencyMap: TJSONObject): Boolean; static;

    /// <summary>
    /// Generate a full cleanup plan for a project's assets.
    /// Evaluates each asset's retention class, package references,
    /// and cascade protection.
    /// </summary>
    class function GenerateCleanupPlan(
      const AAssets: TArray<TAssetRecord>;
      const APackages: TArray<TCandidatePackage>;
      const ADependencyMap: TJSONObject): TCleanupPlan; static;

    /// <summary>
    /// Build a dependency map from candidate package source traces.
    /// Key = asset_id, Value = [dependent_asset_ids].
    /// </summary>
    class function BuildDependencyMap(
      const APackages: TArray<TCandidatePackage>): TJSONObject; static;

    /// <summary>
    /// Register an asset with the correct retention class based on its type.
    /// </summary>
    class function ClassifyAsset(const AAssetType, AAssetCategory: string;
      AIsFailed: Boolean): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  DeepFrames.Shared.Consts;

{ TAssetRetention }

class function TAssetRetention.RetentionDays(const ARetentionClass: string): Integer;
begin
  if SameText(ARetentionClass, RETENTION_CLASS_C1) then
    Result := 0       // forever
  else if SameText(ARetentionClass, RETENTION_CLASS_C2) then
    Result := 30      // 30 days
  else if SameText(ARetentionClass, RETENTION_CLASS_C3) then
    Result := 7       // 7 days
  else if SameText(ARetentionClass, RETENTION_CLASS_C4) then
    Result := 0       // immediate
  else
    Result := 7;      // default C3
end;

class function TAssetRetention.ComputeProtectedUntil(const ARetentionClass: string): string;
var
  Days: Integer;
  DT: TDateTime;
begin
  Days := RetentionDays(ARetentionClass);
  if Days = 0 then
    Result := '9999-12-31T23:59:59Z' // forever
  else
  begin
    DT := Now + Days;
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', DT);
  end;
end;

class function TAssetRetention.GetPackageReferences(const AAssetId: string;
  const APackages: TArray<TCandidatePackage>): TArray<string>;
var
  Refs: TArray<string>;
  I: Integer;
  TraceObj: TJSONObject;
  TraceStr: string;
begin
  Result := nil;
  SetLength(Refs, 0);
  for I := 0 to High(APackages) do
  begin
    TraceStr := APackages[I].SourceTraceJson;
    if TraceStr = '' then
      Continue;
    TraceObj := TJSONObject.ParseJSONValue(TraceStr) as TJSONObject;
    if TraceObj = nil then
      Continue;
    try
      // Check if any trace field matches this asset
      if (TraceObj.GetValue<string>('audio_manifest_id') = AAssetId) or
         (TraceObj.GetValue<string>('video_ir_id') = AAssetId) or
         (TraceObj.GetValue<string>('variant_document_id') = AAssetId) or
         (TraceObj.GetValue<string>('manifest_asset_id') = AAssetId) then
      begin
        SetLength(Refs, Length(Refs) + 1);
        Refs[High(Refs)] := APackages[I].PackageId;
      end;
    finally
      TraceObj.Free;
    end;
  end;
  Result := Refs;
end;

class function TAssetRetention.IsCascadeProtected(const AAssetId: string;
  const AProtectedAssetIds: TArray<string>;
  const ADependencyMap: TJSONObject): Boolean;
var
  Deps: TJSONArray;
  I: Integer;
  DepId: string;
begin
  if ADependencyMap = nil then
    Exit(False);

  Deps := ADependencyMap.GetValue(AAssetId) as TJSONArray;
  if Deps = nil then
    Exit(False);

  for I := 0 to Deps.Count - 1 do
  begin
    DepId := Deps.Items[I].Value;
    for var ProtectedId in AProtectedAssetIds do
      if SameText(DepId, ProtectedId) then
        Exit(True);
  end;
  Result := False;
end;

class function TAssetRetention.GenerateCleanupPlan(
  const AAssets: TArray<TAssetRecord>;
  const APackages: TArray<TCandidatePackage>;
  const ADependencyMap: TJSONObject): TCleanupPlan;
var
  Plan: TCleanupPlan;
  Verdicts: TArray<TCleanupVerdict>;
  ProtectedIds: TArray<string>;
  Asset: TAssetRecord;
  I: Integer;
  PackageRefs: TArray<string>;
  IsFailed: Boolean;
begin
  SetLength(Verdicts, 0);
  SetLength(ProtectedIds, 0);
  Plan.TotalBytesEligible := 0;
  Plan.TotalBytesProtected := 0;

  // First pass: identify package-protected assets
  for Asset in AAssets do
  begin
    PackageRefs := GetPackageReferences(Asset.AssetId, APackages);
    if Length(PackageRefs) > 0 then
    begin
      SetLength(ProtectedIds, Length(ProtectedIds) + 1);
      ProtectedIds[High(ProtectedIds)] := Asset.AssetId;
    end;
  end;

  // Second pass: evaluate each asset
  for Asset in AAssets do
  begin
    var V: TCleanupVerdict;
    V.AssetId := Asset.AssetId;
    V.RetentionClass := Asset.RetentionClass;

    IsFailed := SameText(Asset.Status, ASSET_STATUS_FAILED) or
      SameText(Asset.Status, ASSET_STATUS_DELETED);

    if IsFailed then
    begin
      // Failed/partial assets: immediate cleanup (C4)
      V.CanCleanup := True;
      V.ProtectedUntil := '';
      V.Reason := Format('Failed asset (status=%s) — immediate cleanup', [Asset.Status]);
    end
    else if SameText(Asset.RetentionClass, RETENTION_CLASS_C1) then
    begin
      V.CanCleanup := False;
      V.ProtectedUntil := ComputeProtectedUntil(RETENTION_CLASS_C1);
      V.Reason := 'C1 — long-term retention, never cleaned';
    end
    else if SameText(Asset.RetentionClass, RETENTION_CLASS_C2) then
    begin
      V.ReferencedByPackages := PackageRefs;
      if Length(PackageRefs) > 0 then
      begin
        V.CanCleanup := False;
        V.ProtectedUntil := ComputeProtectedUntil(RETENTION_CLASS_C1);
        V.Reason := Format('C2 asset referenced by %d candidate package(s) — cascade protected',
          [Length(PackageRefs)]);
      end
      else
      begin
        V.CanCleanup := True;
        V.ProtectedUntil := ComputeProtectedUntil(RETENTION_CLASS_C2);
        V.Reason := Format('C2 — cleanup eligible after %s', [V.ProtectedUntil]);
      end;
    end
    else if SameText(Asset.RetentionClass, RETENTION_CLASS_C3) then
    begin
      if IsCascadeProtected(Asset.AssetId, ProtectedIds, ADependencyMap) then
      begin
        V.CanCleanup := False;
        V.ProtectedUntil := ComputeProtectedUntil(RETENTION_CLASS_C2);
        V.Reason := 'C3 — cascade protected (protected asset depends on this)';
      end
      else
      begin
        V.CanCleanup := True;
        V.ProtectedUntil := ComputeProtectedUntil(RETENTION_CLASS_C3);
        V.Reason := Format('C3 — cleanup eligible after %s', [V.ProtectedUntil]);
      end;
    end
    else
    begin
      V.CanCleanup := True;
      V.ProtectedUntil := '';
      V.Reason := Format('C4 — immediate cleanup eligible', []);
    end;

    if V.CanCleanup then
      Inc(Plan.TotalBytesEligible, Asset.ByteSize)
    else
      Inc(Plan.TotalBytesProtected, Asset.ByteSize);

    SetLength(Verdicts, Length(Verdicts) + 1);
    Verdicts[High(Verdicts)] := V;
  end;

  Plan.TotalAssets := Length(AAssets);
  Plan.CleanupEligible := Plan.TotalAssets;
  Plan.Protected := 0;
  for V in Verdicts do
    if not V.CanCleanup then
    begin
      Dec(Plan.CleanupEligible);
      Inc(Plan.Protected);
    end;
  Plan.Verdicts := Verdicts;
  Result := Plan;
end;

class function TAssetRetention.BuildDependencyMap(
  const APackages: TArray<TCandidatePackage>): TJSONObject;
var
  Map: TJSONObject;
  I: Integer;
  TraceObj: TJSONObject;
  Keys: TArray<string>;
  Key: string;
begin
  Map := TJSONObject.Create;
  Keys := ['audio_manifest_id', 'video_ir_id', 'variant_document_id',
    'manifest_asset_id', 'cover_asset_id'];

  for I := 0 to High(APackages) do
  begin
    if APackages[I].SourceTraceJson = '' then
      Continue;
    TraceObj := TJSONObject.ParseJSONValue(APackages[I].SourceTraceJson) as TJSONObject;
    if TraceObj = nil then
      Continue;
    try
      for Key in Keys do
      begin
        var Val := TraceObj.GetValue<string>(Key);
        if Val <> '' then
        begin
          var Arr := Map.GetValue(Val) as TJSONArray;
          if Arr = nil then
          begin
            Arr := TJSONArray.Create;
            Map.AddPair(Val, Arr);
          end;
          Arr.Add(APackages[I].PackageId);
        end;
      end;
    finally
      TraceObj.Free;
    end;
  end;
  Result := Map;
end;

class function TAssetRetention.ClassifyAsset(const AAssetType,
  AAssetCategory: string; AIsFailed: Boolean): string;
begin
  if AIsFailed then
    Result := RETENTION_CLASS_C4
  else if SameText(AAssetType, 'manifest') then
    Result := RETENTION_CLASS_C1
  else if SameText(AAssetCategory, ASSET_CATEGORY_FINAL) or
    SameText(AAssetCategory, ASSET_CATEGORY_COVER) then
    Result := RETENTION_CLASS_C2
  else if SameText(AAssetCategory, ASSET_CATEGORY_SNAPSHOT) or
    SameText(AAssetCategory, ASSET_CATEGORY_PREVIEW) then
    Result := RETENTION_CLASS_C3
  else
    Result := RETENTION_CLASS_C3; // default: intermediate
end;

end.