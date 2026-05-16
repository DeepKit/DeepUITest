{ ============================================================================
  DeepSpec.Hash

  SHA-256 utilities for content_hash and relation_hash computation.
  Implements the hashing algorithm from protocol §4.3.
  ============================================================================ }

unit DeepSpec.Hash;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  DeepSpec.Models;

type
  TSpecHash = class
  public
    /// <summary>
    /// Compute SHA-256 hex digest of a string.
    /// </summary>
    class function Sha256Hex(const AInput: string): string; static;

    /// <summary>
    /// Compute SHA-256 hex digest of a file.
    /// Returns empty string for files larger than AMaxBytes (default 10MB).
    /// </summary>
    class function FileSha256Hex(const APath: string;
      AMaxBytes: Int64 = 10 * 1024 * 1024): string; static;

    /// <summary>
    /// Compute content_hash for a node per protocol §4.3.
    /// Includes: id, title, kind, parent_id, summary, status, confidence,
    /// source_refs (sorted by ref_id), source_layer, acceptance_criteria,
    /// not_doing.
    /// </summary>
    class function NodeContentHash(const ANode: TSpecNode): string; static;

    /// <summary>
    /// Compute relation_hash for a node per protocol §4.3.
    /// Includes: decision_refs, issue_refs, related_*, tags.
    /// </summary>
    class function NodeRelationHash(const ANode: TSpecNode): string; static;
  end;

implementation

uses
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

class function TSpecHash.Sha256Hex(const AInput: string): string;
begin
  Result := LowerCase(THashSHA2.GetHashString(AInput, THashSHA2.TSHA2Version.SHA256));
end;

class function TSpecHash.FileSha256Hex(const APath: string; AMaxBytes: Int64): string;
begin
  if not TFile.Exists(APath) then
    Exit('');

  var LSize := TFile.GetSize(APath);
  if LSize > AMaxBytes then
    Exit('');

  var LStream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    Result := LowerCase(THashSHA2.GetHashString(LStream, THashSHA2.TSHA2Version.SHA256));
  finally
    LStream.Free;
  end;
end;

class function TSpecHash.NodeContentHash(const ANode: TSpecNode): string;
var
  LSb: TStringBuilder;
  LRefs: TArray<TSourceRef>;
begin
  LSb := TStringBuilder.Create;
  try
    // Field order matters for hash stability
    LSb.Append('id=').Append(ANode.Id).Append('|');
    LSb.Append('title=').Append(ANode.Title).Append('|');
    LSb.Append('kind=').Append(ANode.Kind).Append('|');
    LSb.Append('parent_id=').Append(ANode.ParentId).Append('|');
    LSb.Append('summary=').Append(ANode.Summary).Append('|');
    LSb.Append('status=').Append(TSpecEnums.NodeStatusToStr(ANode.Status)).Append('|');
    LSb.Append('confidence=').Append(TSpecEnums.ConfidenceToStr(ANode.Confidence)).Append('|');
    LSb.Append('source_layer=').Append(TSpecEnums.SourceLayerToStr(ANode.SourceLayer)).Append('|');

    // Sort source_refs by ref_id alphabetically (per §4.3)
    LRefs := Copy(ANode.SourceRefs);
    TArray.Sort<TSourceRef>(LRefs,
      TComparer<TSourceRef>.Construct(
        function(const A, B: TSourceRef): Integer
        begin
          Result := CompareStr(A.RefId, B.RefId);
        end));

    LSb.Append('source_refs=[');
    for var I := 0 to High(LRefs) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(LRefs[I].RefId);
      if LRefs[I].Relevance <> '' then
        LSb.Append(':').Append(LRefs[I].Relevance);
    end;
    LSb.Append(']|');

    LSb.Append('acceptance_criteria=[');
    for var I := 0 to High(ANode.AcceptanceCriteria) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.AcceptanceCriteria[I]);
    end;
    LSb.Append(']|');

    LSb.Append('not_doing=[');
    for var I := 0 to High(ANode.NotDoing) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.NotDoing[I]);
    end;
    LSb.Append(']');

    Result := Sha256Hex(LSb.ToString);
  finally
    LSb.Free;
  end;
end;

class function TSpecHash.NodeRelationHash(const ANode: TSpecNode): string;
var
  LSb: TStringBuilder;
begin
  LSb := TStringBuilder.Create;
  try
    LSb.Append('decision_refs=[');
    for var I := 0 to High(ANode.DecisionRefs) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.DecisionRefs[I]);
    end;
    LSb.Append(']|');

    LSb.Append('issue_refs=[');
    for var I := 0 to High(ANode.IssueRefs) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.IssueRefs[I]);
    end;
    LSb.Append(']|');

    LSb.Append('related_functions=[');
    for var I := 0 to High(ANode.RelatedFunctions) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.RelatedFunctions[I]);
    end;
    LSb.Append(']|');

    LSb.Append('related_modules=[');
    for var I := 0 to High(ANode.RelatedModules) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.RelatedModules[I]);
    end;
    LSb.Append(']|');

    LSb.Append('related_views=[');
    for var I := 0 to High(ANode.RelatedViews) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.RelatedViews[I]);
    end;
    LSb.Append(']|');

    LSb.Append('tags=[');
    for var I := 0 to High(ANode.Tags) do
    begin
      if I > 0 then LSb.Append(',');
      LSb.Append(ANode.Tags[I]);
    end;
    LSb.Append(']');

    Result := Sha256Hex(LSb.ToString);
  finally
    LSb.Free;
  end;
end;

end.
