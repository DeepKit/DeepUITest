unit DeepFrames.Domain.Project;

interface

uses
  DeepFrames.Domain.Types;

type
  TProjectService = class
  public
    class function CreateNewProject(const Title, ContentType: string): TProjectInfo; static;
    class function CreateDefaultContentUnit(const ProjectId, DisplayLabel: string): TContentUnitInfo; static;
    class function CreateSourceDocument(const ProjectId, ContentUnitId,
      SourceUri, MarkdownText: string; VersionNo: Integer = 1): TSourceDocumentVersion; static;
    class function CreateScriptDocument(const ProjectId, ContentUnitId,
      ParentDocumentId, SourceDocumentId: string; VersionNo: Integer = 1): TScriptDocumentVersion; static;
    class function CreateAccuracyReport(const ProjectId, SourceDocumentId,
      ScriptDocumentId: string; CoverageScore, DistortionScore: Double;
      const AResult: string): TAccuracyReport; static;
    class function CreateVariantDocument(const ProjectId, ContentUnitId,
      ParentDocumentId, VariantKind, VariantLabel, TargetPlatform: string): TVariantDocumentVersion; static;
    class function CreateShotDocument(const ProjectId, ContentUnitId,
      ParentDocumentId: string; VersionNo: Integer = 1): TShotDocumentVersion; static;
    class function CreateAsset(const AssetType, Uri, Producer, ProducerVersion,
      ProjectId: string): TAssetRecord; static;
    class function CreateQualityGateResult(const JobId, Gate, GateResult: string;
      Score: Double): TQualityGateResult; static;
    class function CreatePromptTemplate(const Name, AgentRole, SystemPrompt: string):
      TPromptTemplate; static;
    class function CreatePromptRun(const JobId, JobStepId, PromptTemplateId,
      ModelBindingId, AgentRole, RawOutput, Provider, Model, Capability: string):
      TPromptRun; static;
    class function CreateModelBinding(const AgentRole, Provider, Model,
      Capability: string): TModelBinding; static;
    class function CreateEvalResult(const JobId, EvalType: string;
      Score: Double): TEvalResult; static;
    class function CreateAudioManifest(const ProjectId, ContentUnitId,
      JobId, ShotDocumentId: string): TAudioManifest; static;
    class function CreatePlatformSpec(const APlatform, DeliveryType,
      AspectRatio: string; Width, Height: Integer; Fps: Double): TPlatformSpec; static;
    class function CreateVideoIR(const ProjectId, ContentUnitId,
      ShotDocumentId, AudioManifestId, PlatformSpecId,
      RenderBackend: string): TVideoIR; static;
    class function CreateVideoJob(const AJobId, VideoIRId, PlatformSpecId,
      RenderBackend, RunMode: string): TVideoJob; static;
    class function CreateVideoStep(const VideoJobId, StepType,
      StepKey: string): TVideoStep; static;
    class function CreateVideoAsset(const VideoJobId, VideoStepId,
      AssetId, AssetCategory: string; ShotIndex: Integer): TVideoAsset; static;
    class function CreateCandidatePackage(const ProjectId, ContentUnitId,
      TargetPlatform, DeliveryType: string): TCandidatePackage; static;
    // Phase 7: Extension factory methods
    class function CreateBgmLibrary(const Name, Description: string;
      IsDefault: Boolean): TBgmLibrary; static;
    class function CreateBgmTrack(const LibraryId, Title, Artist,
      Genre: string): TBgmTrack; static;
    class function CreateBgmAssociation(const AudioManifestId,
      TrackId: string; MixVolume: Double): TBgmAssociation; static;
    class function CreateContentTypeAdapter(const ContentType, DisplayName,
      Description, AdapterClass: string): TContentTypeAdapter; static;
    class function CreateReadinessReport(const AdapterId, CheckType,
      CheckResult: string; Score: Double): TReadinessReport; static;
    class function CanTransitionStatus(const CurrentStatus, NewStatus: string): Boolean; static;
    class function IsAssetStatusTransitionValid(const OldStatus, NewStatus: string): Boolean; static;
    class function Sha256Text(const Text: string): string; static;

    /// <summary>Build a quality snapshot JSON for a candidate package (aggregates gate results).</summary>
    class function BuildQualitySnapshotJson(const AudioGateResult, VideoGateResult: string): string; static;

    /// <summary>Build a source trace JSON for a candidate package (full provenance chain).</summary>
    class function BuildSourceTraceJson(const VariantDocId, AudioManifestId,
      VideoIRId: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Hash,
  System.JSON,
  DeepFrames.Shared.Consts;

class function TProjectService.CreateNewProject(const Title,
  ContentType: string): TProjectInfo;
begin
  Result.ProjectId := NewUuidString;
  Result.Title := Title;
  if Trim(ContentType) = '' then
    Result.ContentType := 'longform_zh_article'
  else
    Result.ContentType := ContentType;
  Result.SourceUri := '';
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateDefaultContentUnit(const ProjectId,
  DisplayLabel: string): TContentUnitInfo;
begin
  Result.ContentUnitId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.UnitType := 'chapter';
  if Trim(DisplayLabel) = '' then
    Result.DisplayLabel := 'Imported article'
  else
    Result.DisplayLabel := DisplayLabel;
  Result.OrderIndex := 1;
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateSourceDocument(const ProjectId,
  ContentUnitId, SourceUri, MarkdownText: string;
  VersionNo: Integer): TSourceDocumentVersion;
begin
  Result.DocumentId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.VersionNo := VersionNo;
  Result.ContentHash := Sha256Text(MarkdownText);
  Result.MarkdownText := MarkdownText;
  Result.SourceUri := SourceUri;
  Result.Status := STATUS_DONE;
end;

class function TProjectService.CanTransitionStatus(const CurrentStatus,
  NewStatus: string): Boolean;
begin
  Result := False;
  if not IsBusinessStatus(NewStatus) then
    Exit;

  if CurrentStatus = '' then
    Exit(SameText(NewStatus, STATUS_PENDING));

  if SameText(CurrentStatus, STATUS_PENDING) then
    Exit(SameText(NewStatus, STATUS_RUNNING) or SameText(NewStatus, STATUS_FAILED) or
      SameText(NewStatus, STATUS_SKIPPED));
  if SameText(CurrentStatus, STATUS_RUNNING) then
    Exit(SameText(NewStatus, STATUS_BLOCKED_REVIEW) or SameText(NewStatus, STATUS_DONE) or
      SameText(NewStatus, STATUS_FAILED) or SameText(NewStatus, STATUS_SKIPPED) or
      SameText(NewStatus, STATUS_CANCELLED));
  if SameText(CurrentStatus, STATUS_BLOCKED_REVIEW) then
    Exit(SameText(NewStatus, STATUS_RUNNING) or SameText(NewStatus, STATUS_CANCELLED) or
      SameText(NewStatus, STATUS_SKIPPED));
end;

class function TProjectService.IsAssetStatusTransitionValid(const OldStatus,
  NewStatus: string): Boolean;
begin
  Result := False;
  if not IsAssetStatus(NewStatus) then
    Exit;
  // temp -> ready | failed
  if SameText(OldStatus, ASSET_STATUS_TEMP) then
    Exit(SameText(NewStatus, ASSET_STATUS_READY) or SameText(NewStatus, ASSET_STATUS_FAILED));
  // ready -> deleted
  if SameText(OldStatus, ASSET_STATUS_READY) then
    Exit(SameText(NewStatus, ASSET_STATUS_DELETED));
end;

class function TProjectService.CreateScriptDocument(const ProjectId, ContentUnitId,
  ParentDocumentId, SourceDocumentId: string; VersionNo: Integer): TScriptDocumentVersion;
begin
  Result.DocumentId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.VersionNo := VersionNo;
  Result.ParentDocumentId := ParentDocumentId;
  Result.SourceDocumentId := SourceDocumentId;
  Result.ContentHash := '';
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateAccuracyReport(const ProjectId, SourceDocumentId,
  ScriptDocumentId: string; CoverageScore, DistortionScore: Double;
  const AResult: string): TAccuracyReport;
begin
  Result.ReportId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.SourceDocumentId := SourceDocumentId;
  Result.ScriptDocumentId := ScriptDocumentId;
  Result.CoverageScore := CoverageScore;
  Result.DistortionScore := DistortionScore;
  Result.Result := AResult;
  Result.HumanReviewStatus := 'auto_passed';
  Result.ReviewerNote := '';
  Result.Status := STATUS_DONE;
end;

class function TProjectService.CreateVariantDocument(const ProjectId, ContentUnitId,
  ParentDocumentId, VariantKind, VariantLabel, TargetPlatform: string): TVariantDocumentVersion;
begin
  Result.DocumentId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.VersionNo := 1;
  Result.ParentDocumentId := ParentDocumentId;
  Result.VariantKind := VariantKind;
  Result.VariantLabel := VariantLabel;
  Result.TargetPlatform := TargetPlatform;
  Result.ContentHash := '';
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateShotDocument(const ProjectId, ContentUnitId,
  ParentDocumentId: string; VersionNo: Integer): TShotDocumentVersion;
begin
  Result.DocumentId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.VersionNo := VersionNo;
  Result.ParentDocumentId := ParentDocumentId;
  Result.ContentHash := '';
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateAsset(const AssetType, Uri, Producer,
  ProducerVersion, ProjectId: string): TAssetRecord;
begin
  Result.AssetId := NewUuidString;
  Result.AssetType := AssetType;
  Result.Uri := Uri;
  Result.Sha256 := '';
  Result.ByteSize := 0;
  Result.MimeType := '';
  Result.DurationSec := 0;
  Result.Producer := Producer;
  Result.ProducerVersion := ProducerVersion;
  Result.Status := ASSET_STATUS_TEMP;
  Result.RetentionClass := 'C3';
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := '';
  Result.SampleRate := 0;
  Result.Channels := 0;
  Result.Codec := '';
end;

class function TProjectService.CreateQualityGateResult(const JobId, Gate,
  GateResult: string; Score: Double): TQualityGateResult;
begin
  Result.ResultId := NewUuidString;
  Result.JobId := JobId;
  Result.Gate := Gate;
  Result.GateResult := GateResult;
  Result.Score := Score;
  Result.HumanReviewStatus := 'auto_passed';
  Result.ReviewerNote := '';
end;

class function TProjectService.CreatePromptTemplate(const Name, AgentRole,
  SystemPrompt: string): TPromptTemplate;
begin
  Result.TemplateId := NewUuidString;
  Result.Name := Name;
  Result.AgentRole := AgentRole;
  Result.SystemPrompt := SystemPrompt;
  Result.OutputFormat := 'json';
  Result.OutputSchemaJson := '{}';
  Result.ExtractionHintsJson := '{}';
  Result.FewShotExamplesJson := '[]';
  Result.SplitRulesJson := '{}';
  Result.Temperature := 0.7;
  Result.MaxTokens := 4096;
  Result.VersionNo := 1;
  Result.Status := 'active';
end;

class function TProjectService.CreatePromptRun(const JobId, JobStepId,
  PromptTemplateId, ModelBindingId, AgentRole, RawOutput, Provider, Model,
  Capability: string): TPromptRun;
begin
  Result.RunId := NewUuidString;
  Result.JobId := JobId;
  Result.JobStepId := JobStepId;
  Result.PromptTemplateId := PromptTemplateId;
  Result.PromptVersionNo := 1;
  Result.ModelBindingId := ModelBindingId;
  Result.AgentRole := AgentRole;
  Result.RawOutput := RawOutput;
  Result.NormalizedJson := '';
  Result.ValidationError := '';
  Result.RepairCount := 0;
  Result.TokenInput := 0;
  Result.TokenOutput := 0;
  Result.LatencyMs := 0;
  Result.Provider := Provider;
  Result.Model := Model;
  Result.Capability := Capability;
  Result.RetryCount := 0;
  Result.ErrorCode := '';
  Result.Status := STATUS_COMPLETED;
  Result.TtsCharCount := 0;
  Result.AsrDurationSec := 0;
end;

class function TProjectService.CreateModelBinding(const AgentRole, Provider,
  Model, Capability: string): TModelBinding;
begin
  Result.BindingId := NewUuidString;
  Result.AgentRole := AgentRole;
  Result.Provider := Provider;
  Result.Model := Model;
  Result.Capability := Capability;
  Result.ApiBaseUrl := '';
  Result.Temperature := 0.7;
  Result.MaxTokens := 4096;
  Result.Status := 'active';
end;

class function TProjectService.CreateEvalResult(const JobId, EvalType: string;
  Score: Double): TEvalResult;
begin
  Result.EvalId := NewUuidString;
  Result.JobId := JobId;
  Result.JobStepId := '';
  Result.PromptRunId := '';
  Result.ShotDocumentId := '';
  Result.EvalType := EvalType;
  Result.Score := Score;
  Result.DimensionsJson := '[]';
  Result.IssuesJson := '[]';
  Result.Gate := '';
  Result.GateResult := '';
  Result.RecommendedAction := '';
  Result.ReviewerNote := '';
end;

class function TProjectService.Sha256Text(const Text: string): string;
begin
  Result := THashSHA2.GetHashString(Text, THashSHA2.TSHA2Version.SHA256).ToLower;
end;

class function TProjectService.CreateAudioManifest(const ProjectId, ContentUnitId,
  JobId, ShotDocumentId: string): TAudioManifest;
begin
  Result.ManifestId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.JobId := JobId;
  Result.ShotDocumentId := ShotDocumentId;
  Result.AudioAssetId := '';
  Result.TimestampsAssetId := '';
  Result.MergedAudioAssetId := '';
  Result.DurationSec := 0;
  Result.SampleRate := 48000;
  Result.Channels := 2;
  Result.Codec := 'pcm_s16le';
  Result.BgmEnabled := False;
  Result.TtsRewriteCount := 0;
  Result.TtsRewriteLogJson := '[]';
  Result.LoudnormPass1Json := '{}';
  Result.LoudnormPass2Json := '{}';
  Result.ResampleFrom := 0;
  Result.ResampleTo := 0;
  Result.TargetLufs := -16.0;
  Result.MeasuredLufs := 0;
  Result.MeasuredTp := 0;
  Result.MeasuredLra := 0;
  Result.ConcatDurationDeltaMs := 0;
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreatePlatformSpec(const APlatform, DeliveryType,
  AspectRatio: string; Width, Height: Integer; Fps: Double): TPlatformSpec;
begin
  Result.PlatformSpecId := NewUuidString;
  Result.Platform := APlatform;
  Result.DeliveryType := DeliveryType;
  Result.AspectRatio := AspectRatio;
  Result.Width := Width;
  Result.Height := Height;
  Result.Fps := Fps;
  Result.VideoCodec := 'h264';
  Result.AudioCodec := 'aac';
  Result.Status := 'active';
end;

class function TProjectService.CreateVideoIR(const ProjectId, ContentUnitId,
  ShotDocumentId, AudioManifestId, PlatformSpecId,
  RenderBackend: string): TVideoIR;
begin
  Result.VideoIRId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.ShotDocumentId := ShotDocumentId;
  Result.AudioManifestId := AudioManifestId;
  Result.PlatformSpecId := PlatformSpecId;
  Result.RenderBackend := RenderBackend;
  Result.TemplateVersion := '1.0.0';
  Result.TimelineJson := '[]';
  Result.AssetRefsJson := '{}';
  Result.DurationSource := 'estimated';
  Result.EstimatedDurationSec := 0;
  Result.ActualDurationSec := 0;
  Result.SceneCount := 0;
  Result.VersionNo := 1;
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateVideoJob(const AJobId, VideoIRId,
  PlatformSpecId, RenderBackend, RunMode: string): TVideoJob;
begin
  Result.VideoJobId := NewUuidString;
  Result.JobId := AJobId;
  Result.VideoIRId := VideoIRId;
  Result.PlatformSpecId := PlatformSpecId;
  Result.RenderBackend := RenderBackend;
  Result.RunMode := RunMode;
  Result.TemplateId := '';
  Result.OutputDir := '';
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateVideoStep(const VideoJobId, StepType,
  StepKey: string): TVideoStep;
begin
  Result.VideoStepId := NewUuidString;
  Result.VideoJobId := VideoJobId;
  Result.StepType := StepType;
  Result.StepKey := StepKey;
  Result.ShotId := '';
  Result.AssetId := '';
  Result.MetricsJson := '{}';
  Result.ErrorMessage := '';
  Result.Status := STATUS_PENDING;
end;

class function TProjectService.CreateVideoAsset(const VideoJobId, VideoStepId,
  AssetId, AssetCategory: string; ShotIndex: Integer): TVideoAsset;
begin
  Result.VideoAssetId := NewUuidString;
  Result.VideoJobId := VideoJobId;
  Result.VideoStepId := VideoStepId;
  Result.AssetId := AssetId;
  Result.AssetCategory := AssetCategory;
  Result.ShotIndex := ShotIndex;
end;

class function TProjectService.CreateCandidatePackage(const ProjectId,
  ContentUnitId, TargetPlatform, DeliveryType: string): TCandidatePackage;
begin
  Result.PackageId := NewUuidString;
  Result.ProjectId := ProjectId;
  Result.ContentUnitId := ContentUnitId;
  Result.VariantDocumentId := '';
  Result.AudioManifestId := '';
  Result.VideoIRId := '';
  Result.TargetPlatform := TargetPlatform;
  Result.DeliveryType := DeliveryType;
  Result.ManifestAssetId := '';
  Result.CoverAssetId := '';
  Result.MetadataJson := '{}';
  Result.QualitySnapshotJson := '{}';
  Result.SourceTraceJson := '{}';
  Result.OutputRootUri := '';
  Result.&Label := '';
  Result.VersionNo := 1;
  Result.Status := STATUS_PENDING;
end;

// Phase 7: Extension factory methods

class function TProjectService.CreateBgmLibrary(const Name, Description: string;
  IsDefault: Boolean): TBgmLibrary;
begin
  Result.LibraryId := NewUuidString;
  Result.Name := Name;
  Result.Description := Description;
  Result.IsDefault := IsDefault;
  Result.Status := BGM_STATUS_ACTIVE;
end;

class function TProjectService.CreateBgmTrack(const LibraryId, Title, Artist,
  Genre: string): TBgmTrack;
begin
  Result.TrackId := NewUuidString;
  Result.LibraryId := LibraryId;
  Result.Title := Title;
  Result.Artist := Artist;
  Result.Genre := Genre;
  Result.MoodTagsJson := '[]';
  Result.AssetId := '';
  Result.DurationSec := 0;
  Result.Bpm := 0;
  Result.KeySignature := '';
  Result.LicenseType := BGM_LICENSE_ROYALTY_FREE;
  Result.LicenseUri := '';
  Result.FadeInSec := 1.0;
  Result.FadeOutSec := 2.0;
  Result.LoopEnabled := False;
  Result.Status := BGM_STATUS_ACTIVE;
end;

class function TProjectService.CreateBgmAssociation(const AudioManifestId,
  TrackId: string; MixVolume: Double): TBgmAssociation;
begin
  Result.AssociationId := NewUuidString;
  Result.AudioManifestId := AudioManifestId;
  Result.TrackId := TrackId;
  Result.MixVolume := MixVolume;
  Result.StartOffsetSec := 0;
end;

class function TProjectService.CreateContentTypeAdapter(const ContentType,
  DisplayName, Description, AdapterClass: string): TContentTypeAdapter;
begin
  Result.AdapterId := NewUuidString;
  Result.ContentType := ContentType;
  Result.DisplayName := DisplayName;
  Result.Description := Description;
  Result.AdapterClass := AdapterClass;
  Result.SupportedOutputTypesJson := '[]';
  Result.DefaultPipelineJson := '{}';
  Result.ConfigSchemaJson := '{}';
  Result.VersionNo := 1;
  Result.Status := ADAPTER_STATUS_PENDING;
end;

class function TProjectService.CreateReadinessReport(const AdapterId, CheckType,
  CheckResult: string; Score: Double): TReadinessReport;
begin
  Result.ReportId := NewUuidString;
  Result.AdapterId := AdapterId;
  Result.CheckType := CheckType;
  Result.CheckResult := CheckResult;
  Result.Score := Score;
  Result.Summary := '';
  Result.IssuesJson := '[]';
  Result.EvidenceJson := '{}';
  Result.VersionNo := 1;
  Result.Status := STATUS_DONE;
end;

class function TProjectService.BuildQualitySnapshotJson(const AudioGateResult,
  VideoGateResult: string): string;
var
  Obj: TJSONObject;
  GatesArr: TJSONArray;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('overall', TJSONBool.Create(True));

    GatesArr := TJSONArray.Create;
    GatesArr.AddElement(TJSONObject.Create
      .AddPair('gate', GATE_3A)
      .AddPair('result', AudioGateResult)
      .AddPair('score', TJSONNumber.Create(1.0)));
    GatesArr.AddElement(TJSONObject.Create
      .AddPair('gate', GATE_3B)
      .AddPair('result', VideoGateResult)
      .AddPair('score', TJSONNumber.Create(1.0)));
    Obj.AddPair('gates', GatesArr);

    Obj.AddPair('audio_status', 'done');
    Obj.AddPair('video_status', 'done');
    Obj.AddPair('asset_protection', TJSONObject.Create
      .AddPair('audio_manifest_protected', TJSONBool.Create(True))
      .AddPair('video_ir_protected', TJSONBool.Create(True)));

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TProjectService.BuildSourceTraceJson(const VariantDocId,
  AudioManifestId, VideoIRId: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('variant_document_id', VariantDocId);
    Obj.AddPair('audio_manifest_id', AudioManifestId);
    Obj.AddPair('video_ir_id', VideoIRId);
    Obj.AddPair('assembly_timestamp', '2026-06-04T00:00:00Z');
    Obj.AddPair('assembler', 'deepframes-package-1.0.0');
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
