unit DeepFrames.Workflow.ArtifactOSBridge;

/// <summary>
/// ArtifactOS publishing bridge — connects DeepFrames candidate packages
/// to the ArtifactOS publishing runtime via PostgreSQL contract tables.
///
/// DeepFrames produces candidate packages → writes publish_intent to DB
/// ArtifactOS polling reads publish_intent → executes publishing
/// ArtifactOS writes publish_status back to DB → DeepFrames reads status
/// </summary>

interface

uses
  System.JSON,
  DeepFrames.Domain.Types;

type
  TPublishPlatform = (ppBilibili, ppDouyin, ppKuaishou, ppXiaohongshu,
    ppWechatVideo, ppYouTube, ppXimalaya);

  TPublishIntent = record
    IntentId: string;
    PackageId: string;
    ProjectId: string;
    Platform: string;
    DeliveryType: string;
    ManifestUri: string;
    Title: string;
    Description: string;
    Tags: TArray<string>;
    CoverUri: string;
    ScheduledAt: string;
    Priority: Integer;
    Status: string;
    CreatedAt: string;
  end;

  TPublishStatus = record
    StatusId: string;
    IntentId: string;
    Platform: string;
    Status: string;
    ProgressPercent: Integer;
    Message: string;
    PlatformPostId: string;
    PlatformUrl: string;
    PublishedAt: string;
    ErrorCode: string;
    UpdatedAt: string;
  end;

  TPublishSummary = record
    PackageId: string;
    IntentCount: Integer;
    PublishedCount: Integer;
    FailedCount: Integer;
    PendingCount: Integer;
    HasPending: Boolean;
    HasFailures: Boolean;
  end;

  TArtifactOSBridge = class
  public
    class function PlatformToString(APlatform: TPublishPlatform): string; static;
    class function StringToPlatform(const AStr: string): TPublishPlatform; static;
    class function BuildIntent(const APackage: TCandidatePackage;
      const ATitle, ADescription: string; const ATags: TArray<string>;
      APriority: Integer = 5): TPublishIntent; static;
    class function IntentToJson(const AIntent: TPublishIntent): string; static;
    class function JsonToStatus(const AJson: string): TPublishStatus; static;
    class function StatusToJson(const AStatus: TPublishStatus): string; static;
    class function Summarize(const AStatuses: TArray<TPublishStatus>;
      const APackageId: string): TPublishSummary; static;
    class function IsPlatformSupported(const APlatform: string): Boolean; static;
    class function SupportedPlatforms: TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  DeepFrames.Shared.Consts;

class function TArtifactOSBridge.PlatformToString(APlatform: TPublishPlatform): string;
begin
  case APlatform of
    ppBilibili:     Result := PLATFORM_BILIBILI;
    ppDouyin:       Result := PLATFORM_DOUYIN;
    ppKuaishou:     Result := PLATFORM_KUAISHOU;
    ppXiaohongshu:  Result := PLATFORM_XIAOHONGSHU;
    ppWechatVideo:  Result := PLATFORM_WECHAT_VIDEO;
    ppYouTube:      Result := PLATFORM_YOUTUBE;
    ppXimalaya:     Result := PLATFORM_XIMALAYA;
  else Result := PLATFORM_BILIBILI;
  end;
end;

class function TArtifactOSBridge.StringToPlatform(const AStr: string): TPublishPlatform;
begin
  if SameText(AStr, PLATFORM_BILIBILI) then Result := ppBilibili
  else if SameText(AStr, PLATFORM_DOUYIN) then Result := ppDouyin
  else if SameText(AStr, PLATFORM_KUAISHOU) then Result := ppKuaishou
  else if SameText(AStr, PLATFORM_XIAOHONGSHU) then Result := ppXiaohongshu
  else if SameText(AStr, PLATFORM_WECHAT_VIDEO) then Result := ppWechatVideo
  else if SameText(AStr, PLATFORM_YOUTUBE) then Result := ppYouTube
  else if SameText(AStr, PLATFORM_XIMALAYA) then Result := ppXimalaya
  else Result := ppBilibili;
end;

class function TArtifactOSBridge.IsPlatformSupported(const APlatform: string): Boolean;
begin
  Result := SameText(APlatform, PLATFORM_BILIBILI) or
    SameText(APlatform, PLATFORM_DOUYIN) or SameText(APlatform, PLATFORM_KUAISHOU) or
    SameText(APlatform, PLATFORM_XIAOHONGSHU) or SameText(APlatform, PLATFORM_WECHAT_VIDEO) or
    SameText(APlatform, PLATFORM_YOUTUBE) or SameText(APlatform, PLATFORM_XIMALAYA);
end;

class function TArtifactOSBridge.SupportedPlatforms: TArray<string>;
begin
  Result := [PLATFORM_BILIBILI, PLATFORM_DOUYIN, PLATFORM_KUAISHOU,
    PLATFORM_XIAOHONGSHU, PLATFORM_WECHAT_VIDEO, PLATFORM_YOUTUBE, PLATFORM_XIMALAYA];
end;

class function TArtifactOSBridge.BuildIntent(const APackage: TCandidatePackage;
  const ATitle, ADescription: string; const ATags: TArray<string>;
  APriority: Integer): TPublishIntent;
begin
  Result.IntentId := NewUuidString;
  Result.PackageId := APackage.PackageId;
  Result.ProjectId := APackage.ProjectId;
  Result.Platform := APackage.TargetPlatform;
  Result.DeliveryType := APackage.DeliveryType;
  Result.ManifestUri := APackage.OutputRootUri + '/manifest.json';
  Result.Title := ATitle;
  Result.Description := ADescription;
  Result.Tags := ATags;
  Result.CoverUri := APackage.OutputRootUri + '/cover.png';
  Result.ScheduledAt := '';
  Result.Priority := APriority;
  Result.Status := 'pending';
  Result.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Now);
end;

class function TArtifactOSBridge.IntentToJson(const AIntent: TPublishIntent): string;
var
  Obj: TJSONObject;
  TagsArr: TJSONArray;
  Tag: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('intent_id', AIntent.IntentId);
    Obj.AddPair('package_id', AIntent.PackageId);
    Obj.AddPair('project_id', AIntent.ProjectId);
    Obj.AddPair('platform', AIntent.Platform);
    Obj.AddPair('delivery_type', AIntent.DeliveryType);
    Obj.AddPair('manifest_uri', AIntent.ManifestUri);
    Obj.AddPair('title', AIntent.Title);
    Obj.AddPair('description', AIntent.Description);
    TagsArr := TJSONArray.Create;
    for Tag in AIntent.Tags do TagsArr.Add(Tag);
    Obj.AddPair('tags', TagsArr);
    Obj.AddPair('cover_uri', AIntent.CoverUri);
    Obj.AddPair('scheduled_at', AIntent.ScheduledAt);
    Obj.AddPair('priority', TJSONNumber.Create(AIntent.Priority));
    Obj.AddPair('status', AIntent.Status);
    Obj.AddPair('created_at', AIntent.CreatedAt);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TArtifactOSBridge.JsonToStatus(const AJson: string): TPublishStatus;
var
  Obj: TJSONObject;
begin
  FillChar(Result, SizeOf(Result), 0);
  Obj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Obj = nil then Exit;
  try
    Result.StatusId := Obj.GetValue<string>('status_id');
    Result.IntentId := Obj.GetValue<string>('intent_id');
    Result.Platform := Obj.GetValue<string>('platform');
    Result.Status := Obj.GetValue<string>('status');
    Result.ProgressPercent := Obj.GetValue<Integer>('progress_percent');
    Result.Message := Obj.GetValue<string>('message');
    Result.PlatformPostId := Obj.GetValue<string>('platform_post_id');
    Result.PlatformUrl := Obj.GetValue<string>('platform_url');
    Result.PublishedAt := Obj.GetValue<string>('published_at');
    Result.ErrorCode := Obj.GetValue<string>('error_code');
    Result.UpdatedAt := Obj.GetValue<string>('updated_at');
  finally
    Obj.Free;
  end;
end;

class function TArtifactOSBridge.StatusToJson(const AStatus: TPublishStatus): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', APP_SCHEMA_VERSION);
    Obj.AddPair('status_id', AStatus.StatusId);
    Obj.AddPair('intent_id', AStatus.IntentId);
    Obj.AddPair('platform', AStatus.Platform);
    Obj.AddPair('status', AStatus.Status);
    Obj.AddPair('progress_percent', TJSONNumber.Create(AStatus.ProgressPercent));
    Obj.AddPair('message', AStatus.Message);
    Obj.AddPair('platform_post_id', AStatus.PlatformPostId);
    Obj.AddPair('platform_url', AStatus.PlatformUrl);
    Obj.AddPair('published_at', AStatus.PublishedAt);
    Obj.AddPair('error_code', AStatus.ErrorCode);
    Obj.AddPair('updated_at', AStatus.UpdatedAt);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TArtifactOSBridge.Summarize(const AStatuses: TArray<TPublishStatus>;
  const APackageId: string): TPublishSummary;
var
  S: TPublishStatus;
begin
  Result.PackageId := APackageId;
  Result.IntentCount := Length(AStatuses);
  Result.PublishedCount := 0;
  Result.FailedCount := 0;
  Result.PendingCount := 0;
  for S in AStatuses do
  begin
    if SameText(S.Status, 'published') then Inc(Result.PublishedCount)
    else if SameText(S.Status, 'failed') then Inc(Result.FailedCount)
    else Inc(Result.PendingCount);
  end;
  Result.HasPending := Result.PendingCount > 0;
  Result.HasFailures := Result.FailedCount > 0;
end;

end.