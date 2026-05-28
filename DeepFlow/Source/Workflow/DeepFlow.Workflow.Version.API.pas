unit UniFlow.Workflow.Version.API;
(*
  UniFlow Workflow Version API
  ============================
  TASK-2010: 工作流版本控�?- REST API �?
  
  提供版本管理�?HTTP API 接口:
  - GET    /api/workflows/{id}/versions         - 获取版本列表
  - GET    /api/workflows/{id}/versions/{ver}   - 获取指定版本
  - POST   /api/workflows/{id}/versions         - 创建新版�?
  - PUT    /api/workflows/{id}/versions/{ver}   - 更新版本状�?
  - DELETE /api/workflows/{id}/versions/{ver}   - 删除版本
  - GET    /api/workflows/{id}/versions/diff    - 版本比较
  - POST   /api/workflows/{id}/versions/rollback - 回滚版本
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  UniFlow.Workflow.Version, UniFlow.Workflow.Definition;

type
  // ============================================================================
  // API 请求/响应类型
  // ============================================================================
  
  TVersionListRequest = record
    WorkflowId: string;
    Page: Integer;
    PageSize: Integer;
    Status: string;       // 筛选状�? all, draft, active, archived, deprecated
    SortBy: string;       // version, created_at
    SortOrder: string;    // asc, desc
    
    class function FromJSON(AJson: TJSONObject): TVersionListRequest; static;
  end;
  
  TVersionListResponse = class
  private
    FVersions: TList<TWorkflowVersion>;
    FTotal: Integer;
    FPage: Integer;
    FPageSize: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    
    property Versions: TList<TWorkflowVersion> read FVersions;
    property Total: Integer read FTotal write FTotal;
    property Page: Integer read FPage write FPage;
    property PageSize: Integer read FPageSize write FPageSize;
  end;
  
  TCreateVersionRequest = record
    WorkflowId: string;
    Definition: TJSONObject;
    Comment: string;
    CreatedBy: string;
    IsDraft: Boolean;
    Tags: TArray<string>;
    
    class function FromJSON(AJson: TJSONObject): TCreateVersionRequest; static;
  end;
  
  TUpdateVersionRequest = record
    VersionId: string;
    Status: string;       // draft, active, archived, deprecated
    Comment: string;
    Tags: TArray<string>;
    
    class function FromJSON(AJson: TJSONObject): TUpdateVersionRequest; static;
  end;
  
  TDiffRequest = record
    WorkflowId: string;
    FromVersion: string;  // 版本号或 version_id
    ToVersion: string;
    Format: string;       // json, markdown, text
    
    class function FromJSON(AJson: TJSONObject): TDiffRequest; static;
  end;
  
  TRollbackRequest = record
    WorkflowId: string;
    TargetVersion: string;
    Comment: string;
    CreatedBy: string;
    
    class function FromJSON(AJson: TJSONObject): TRollbackRequest; static;
  end;
  
  // ============================================================================
  // API 响应封装
  // ============================================================================
  
  TAPIResponse = class
  private
    FSuccess: Boolean;
    FMessage: string;
    FData: TJSONValue;
    FErrorCode: Integer;
    FErrorDetails: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    class function OK(AData: TJSONValue = nil; const AMessage: string = ''): TAPIResponse; static;
    class function Error(ACode: Integer; const AMessage: string; ADetails: TJSONObject = nil): TAPIResponse; static;
    
    function ToJSON: TJSONObject;
    
    property Success: Boolean read FSuccess write FSuccess;
    property Message: string read FMessage write FMessage;
    property Data: TJSONValue read FData write FData;
    property ErrorCode: Integer read FErrorCode write FErrorCode;
    property ErrorDetails: TJSONObject read FErrorDetails write FErrorDetails;
  end;
  
  // ============================================================================
  // 版本 API 服务
  // ============================================================================
  
  TVersionAPIService = class
  private
    FVersionManager: TVersionManager;
    FOwnsManager: Boolean;
    
    function ResolveVersion(const AWorkflowId, AVersionRef: string): TWorkflowVersion;
    function FilterVersionsByStatus(AVersions: TList<TWorkflowVersion>; 
      const AStatus: string): TList<TWorkflowVersion>;
    procedure SortVersions(AVersions: TList<TWorkflowVersion>;
      const ASortBy, ASortOrder: string);
  public
    constructor Create(AVersionManager: TVersionManager = nil);
    destructor Destroy; override;
    
    /// <summary>获取版本列表</summary>
    function GetVersionList(const ARequest: TVersionListRequest): TAPIResponse;
    
    /// <summary>获取单个版本</summary>
    function GetVersion(const AWorkflowId, AVersionRef: string): TAPIResponse;
    
    /// <summary>创建新版�?/summary>
    function CreateVersion(const ARequest: TCreateVersionRequest): TAPIResponse;
    
    /// <summary>更新版本</summary>
    function UpdateVersion(const ARequest: TUpdateVersionRequest): TAPIResponse;
    
    /// <summary>删除版本</summary>
    function DeleteVersion(const AWorkflowId, AVersionRef: string): TAPIResponse;
    
    /// <summary>版本比较</summary>
    function DiffVersions(const ARequest: TDiffRequest): TAPIResponse;
    
    /// <summary>回滚版本</summary>
    function RollbackVersion(const ARequest: TRollbackRequest): TAPIResponse;
    
    /// <summary>获取活动版本</summary>
    function GetActiveVersion(const AWorkflowId: string): TAPIResponse;
    
    /// <summary>激活版�?/summary>
    function ActivateVersion(const AWorkflowId, AVersionRef: string): TAPIResponse;
    
    /// <summary>添加标签</summary>
    function AddTag(const AVersionId, ATag: string): TAPIResponse;
    
    /// <summary>移除标签</summary>
    function RemoveTag(const AVersionId, ATag: string): TAPIResponse;
    
    /// <summary>按标签查�?/summary>
    function FindByTag(const AWorkflowId, ATag: string): TAPIResponse;
    
    property VersionManager: TVersionManager read FVersionManager;
  end;
  
  // ============================================================================
  // API 错误�?
  // ============================================================================
  
const
  ERR_OK = 0;
  ERR_NOT_FOUND = 404;
  ERR_INVALID_REQUEST = 400;
  ERR_CONFLICT = 409;
  ERR_INTERNAL = 500;
  
  MSG_VERSION_NOT_FOUND = 'Version not found';
  MSG_WORKFLOW_NOT_FOUND = 'FlowDefinition not found';
  MSG_INVALID_VERSION = 'Invalid version format';
  MSG_VERSION_EXISTS = 'Version already exists';
  MSG_CANNOT_DELETE_ACTIVE = 'Cannot delete active version';
  MSG_ROLLBACK_FAILED = 'Rollback failed';
  MSG_INVALID_STATUS = 'Invalid status';

implementation

uses
  System.StrUtils, System.Math;

// ============================================================================
// TVersionListRequest Implementation
// ============================================================================

class function TVersionListRequest.FromJSON(AJson: TJSONObject): TVersionListRequest;
begin
  Result.WorkflowId := AJson.GetValue<string>('workflow_id', '');
  Result.Page := AJson.GetValue<Integer>('page', 1);
  Result.PageSize := AJson.GetValue<Integer>('page_size', 20);
  Result.Status := AJson.GetValue<string>('status', 'all');
  Result.SortBy := AJson.GetValue<string>('sort_by', 'version');
  Result.SortOrder := AJson.GetValue<string>('sort_order', 'desc');
end;

// ============================================================================
// TVersionListResponse Implementation
// ============================================================================

constructor TVersionListResponse.Create;
begin
  inherited Create;
  FVersions := TList<TWorkflowVersion>.Create;
end;

destructor TVersionListResponse.Destroy;
begin
  FVersions.Free;
  inherited;
end;

function TVersionListResponse.ToJSON: TJSONObject;
var
  LVersionsArray: TJSONArray;
  LVersion: TWorkflowVersion;
begin
  Result := TJSONObject.Create;
  
  LVersionsArray := TJSONArray.Create;
  for LVersion in FVersions do
    LVersionsArray.Add(LVersion.ToJSON);
  
  Result.AddPair('versions', LVersionsArray);
  Result.AddPair('total', TJSONNumber.Create(FTotal));
  Result.AddPair('page', TJSONNumber.Create(FPage));
  Result.AddPair('page_size', TJSONNumber.Create(FPageSize));
  Result.AddPair('total_pages', TJSONNumber.Create(Ceil(FTotal / Max(FPageSize, 1))));
end;

// ============================================================================
// TCreateVersionRequest Implementation
// ============================================================================

class function TCreateVersionRequest.FromJSON(AJson: TJSONObject): TCreateVersionRequest;
var
  LTagsArray: TJSONArray;
  I: Integer;
begin
  Result.WorkflowId := AJson.GetValue<string>('workflow_id', '');
  Result.Definition := AJson.GetValue<TJSONObject>('definition', nil);
  Result.Comment := AJson.GetValue<string>('comment', '');
  Result.CreatedBy := AJson.GetValue<string>('created_by', '');
  Result.IsDraft := AJson.GetValue<Boolean>('is_draft', False);
  
  SetLength(Result.Tags, 0);
  if AJson.TryGetValue<TJSONArray>('tags', LTagsArray) then
  begin
    SetLength(Result.Tags, LTagsArray.Count);
    for I := 0 to LTagsArray.Count - 1 do
      Result.Tags[I] := LTagsArray.Items[I].Value;
  end;
end;

// ============================================================================
// TUpdateVersionRequest Implementation
// ============================================================================

class function TUpdateVersionRequest.FromJSON(AJson: TJSONObject): TUpdateVersionRequest;
var
  LTagsArray: TJSONArray;
  I: Integer;
begin
  Result.VersionId := AJson.GetValue<string>('version_id', '');
  Result.Status := AJson.GetValue<string>('status', '');
  Result.Comment := AJson.GetValue<string>('comment', '');
  
  SetLength(Result.Tags, 0);
  if AJson.TryGetValue<TJSONArray>('tags', LTagsArray) then
  begin
    SetLength(Result.Tags, LTagsArray.Count);
    for I := 0 to LTagsArray.Count - 1 do
      Result.Tags[I] := LTagsArray.Items[I].Value;
  end;
end;

// ============================================================================
// TDiffRequest Implementation
// ============================================================================

class function TDiffRequest.FromJSON(AJson: TJSONObject): TDiffRequest;
begin
  Result.WorkflowId := AJson.GetValue<string>('workflow_id', '');
  Result.FromVersion := AJson.GetValue<string>('from_version', '');
  Result.ToVersion := AJson.GetValue<string>('to_version', '');
  Result.Format := AJson.GetValue<string>('format', 'json');
end;

// ============================================================================
// TRollbackRequest Implementation
// ============================================================================

class function TRollbackRequest.FromJSON(AJson: TJSONObject): TRollbackRequest;
begin
  Result.WorkflowId := AJson.GetValue<string>('workflow_id', '');
  Result.TargetVersion := AJson.GetValue<string>('target_version', '');
  Result.Comment := AJson.GetValue<string>('comment', '');
  Result.CreatedBy := AJson.GetValue<string>('created_by', '');
end;

// ============================================================================
// TAPIResponse Implementation
// ============================================================================

constructor TAPIResponse.Create;
begin
  inherited Create;
  FSuccess := True;
  FErrorCode := ERR_OK;
end;

destructor TAPIResponse.Destroy;
begin
  FData.Free;
  FErrorDetails.Free;
  inherited;
end;

class function TAPIResponse.OK(AData: TJSONValue; const AMessage: string): TAPIResponse;
begin
  Result := TAPIResponse.Create;
  Result.Success := True;
  Result.Message := AMessage;
  Result.Data := AData;
  Result.ErrorCode := ERR_OK;
end;

class function TAPIResponse.Error(ACode: Integer; const AMessage: string; 
  ADetails: TJSONObject): TAPIResponse;
begin
  Result := TAPIResponse.Create;
  Result.Success := False;
  Result.Message := AMessage;
  Result.ErrorCode := ACode;
  Result.ErrorDetails := ADetails;
end;

function TAPIResponse.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(FSuccess));
  Result.AddPair('message', FMessage);
  
  if Assigned(FData) then
    Result.AddPair('data', FData.Clone as TJSONValue)
  else
    Result.AddPair('data', TJSONNull.Create);
  
  if not FSuccess then
  begin
    Result.AddPair('error_code', TJSONNumber.Create(FErrorCode));
    if Assigned(FErrorDetails) then
      Result.AddPair('error_details', FErrorDetails.Clone as TJSONObject);
  end;
end;

// ============================================================================
// TVersionAPIService Implementation
// ============================================================================

constructor TVersionAPIService.Create(AVersionManager: TVersionManager);
begin
  inherited Create;
  if Assigned(AVersionManager) then
  begin
    FVersionManager := AVersionManager;
    FOwnsManager := False;
  end
  else
  begin
    FVersionManager := TVersionManager.Create;
    FOwnsManager := True;
  end;
end;

destructor TVersionAPIService.Destroy;
begin
  if FOwnsManager then
    FVersionManager.Free;
  inherited;
end;

function TVersionAPIService.ResolveVersion(const AWorkflowId, AVersionRef: string): TWorkflowVersion;
var
  LSemVer: TSemVer;
begin
  Result := nil;
  
  // 尝试作为 version_id 查找
  if AVersionRef.StartsWith('ver_') then
  begin
    Result := FVersionManager.Store.GetVersion(AVersionRef);
    Exit;
  end;
  
  // 特殊关键�?
  if SameText(AVersionRef, 'latest') then
  begin
    Result := FVersionManager.GetLatestVersion(AWorkflowId);
    Exit;
  end;
  
  if SameText(AVersionRef, 'active') then
  begin
    Result := FVersionManager.GetActiveVersion(AWorkflowId);
    Exit;
  end;
  
  // 尝试解析为版本号
  LSemVer := TSemVer.Parse(AVersionRef);
  if LSemVer.IsValid then
    Result := FVersionManager.GetByVersion(AWorkflowId, LSemVer);
end;

function TVersionAPIService.FilterVersionsByStatus(AVersions: TList<TWorkflowVersion>;
  const AStatus: string): TList<TWorkflowVersion>;
var
  LVersion: TWorkflowVersion;
  LTargetStatus: TVersionStatus;
begin
  Result := TList<TWorkflowVersion>.Create;
  
  if SameText(AStatus, 'all') or AStatus.IsEmpty then
  begin
    for LVersion in AVersions do
      Result.Add(LVersion);
    Exit;
  end;
  
  LTargetStatus := StringToVersionStatus(AStatus);
  for LVersion in AVersions do
  begin
    if LVersion.Status = LTargetStatus then
      Result.Add(LVersion);
  end;
end;

procedure TVersionAPIService.SortVersions(AVersions: TList<TWorkflowVersion>;
  const ASortBy, ASortOrder: string);
var
  LAscending: Boolean;
begin
  LAscending := SameText(ASortOrder, 'asc');
  
  if SameText(ASortBy, 'created_at') then
  begin
    AVersions.Sort(TComparer<TWorkflowVersion>.Construct(
      function(const A, B: TWorkflowVersion): Integer
      begin
        if A.CreatedAt < B.CreatedAt then
          Result := IfThen(LAscending, -1, 1)
        else if A.CreatedAt > B.CreatedAt then
          Result := IfThen(LAscending, 1, -1)
        else
          Result := 0;
      end));
  end
  else // version
  begin
    AVersions.Sort(TComparer<TWorkflowVersion>.Construct(
      function(const A, B: TWorkflowVersion): Integer
      begin
        Result := A.Version.Compare(B.Version);
        if not LAscending then
          Result := -Result;
      end));
  end;
end;

function TVersionAPIService.GetVersionList(const ARequest: TVersionListRequest): TAPIResponse;
var
  LAllVersions, LFiltered: TList<TWorkflowVersion>;
  LResponse: TVersionListResponse;
  I, LStart, LEnd: Integer;
begin
  LAllVersions := FVersionManager.GetHistory(ARequest.WorkflowId);
  try
    LFiltered := FilterVersionsByStatus(LAllVersions, ARequest.Status);
    try
      SortVersions(LFiltered, ARequest.SortBy, ARequest.SortOrder);
      
      LResponse := TVersionListResponse.Create;
      LResponse.Total := LFiltered.Count;
      LResponse.Page := ARequest.Page;
      LResponse.PageSize := ARequest.PageSize;
      
      // Pagination
      LStart := (ARequest.Page - 1) * ARequest.PageSize;
      LEnd := Min(LStart + ARequest.PageSize - 1, LFiltered.Count - 1);
      
      for I := LStart to LEnd do
        LResponse.Versions.Add(LFiltered[I]);
      
      Result := TAPIResponse.OK(LResponse.ToJSON);
      LResponse.Free;
    finally
      LFiltered.Free;
    end;
  finally
    LAllVersions.Free;
  end;
end;

function TVersionAPIService.GetVersion(const AWorkflowId, AVersionRef: string): TAPIResponse;
var
  LVersion: TWorkflowVersion;
begin
  LVersion := ResolveVersion(AWorkflowId, AVersionRef);
  if not Assigned(LVersion) then
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_VERSION_NOT_FOUND)
  else
    Result := TAPIResponse.OK(LVersion.ToJSON);
end;

function TVersionAPIService.CreateVersion(const ARequest: TCreateVersionRequest): TAPIResponse;
var
  LDefinition: TWorkflowDefinition;
  LVersion: TWorkflowVersion;
  LTag: string;
begin
  try
    if not Assigned(ARequest.Definition) then
    begin
      Result := TAPIResponse.Error(ERR_INVALID_REQUEST, 'Definition is required');
      Exit;
    end;
    
    LDefinition := TWorkflowDefinition.FromJSON(ARequest.Definition);
    try
      if ARequest.IsDraft then
        LVersion := FVersionManager.CreateDraft(ARequest.WorkflowId, LDefinition)
      else
        LVersion := FVersionManager.CreateVersion(ARequest.WorkflowId, LDefinition, 
          ARequest.Comment, ARequest.CreatedBy);
      
      // Add tags
      for LTag in ARequest.Tags do
        LVersion.Tags.Add(LTag);
      
      Result := TAPIResponse.OK(LVersion.ToJSON, 'Version created');
    finally
      LDefinition.Free;
    end;
  except
    on E: Exception do
      Result := TAPIResponse.Error(ERR_INTERNAL, E.Message);
  end;
end;

function TVersionAPIService.UpdateVersion(const ARequest: TUpdateVersionRequest): TAPIResponse;
var
  LVersion: TWorkflowVersion;
  LNewStatus: TVersionStatus;
  LTag: string;
begin
  LVersion := FVersionManager.Store.GetVersion(ARequest.VersionId);
  if not Assigned(LVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_VERSION_NOT_FOUND);
    Exit;
  end;
  
  try
    // Update status
    if not ARequest.Status.IsEmpty then
    begin
      LNewStatus := StringToVersionStatus(ARequest.Status);
      
      case LNewStatus of
        vsActive:
          FVersionManager.ActivateVersion(ARequest.VersionId);
        vsArchived:
          FVersionManager.ArchiveVersion(ARequest.VersionId);
        vsDeprecated:
          FVersionManager.DeprecateVersion(ARequest.VersionId);
      end;
    end;
    
    // Update comment
    if not ARequest.Comment.IsEmpty then
      LVersion.Comment := ARequest.Comment;
    
    // Update tags
    if Length(ARequest.Tags) > 0 then
    begin
      LVersion.Tags.Clear;
      for LTag in ARequest.Tags do
        LVersion.Tags.Add(LTag);
    end;
    
    FVersionManager.Store.SaveVersion(LVersion);
    Result := TAPIResponse.OK(LVersion.ToJSON, 'Version updated');
  except
    on E: Exception do
      Result := TAPIResponse.Error(ERR_INTERNAL, E.Message);
  end;
end;

function TVersionAPIService.DeleteVersion(const AWorkflowId, AVersionRef: string): TAPIResponse;
var
  LVersion: TWorkflowVersion;
begin
  LVersion := ResolveVersion(AWorkflowId, AVersionRef);
  if not Assigned(LVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_VERSION_NOT_FOUND);
    Exit;
  end;
  
  // 不能删除激活版�?
  if LVersion.Status = vsActive then
  begin
    Result := TAPIResponse.Error(ERR_CONFLICT, MSG_CANNOT_DELETE_ACTIVE);
    Exit;
  end;
  
  if FVersionManager.Store.DeleteVersion(LVersion.VersionId) then
    Result := TAPIResponse.OK(nil, 'Version deleted')
  else
    Result := TAPIResponse.Error(ERR_INTERNAL, 'Failed to delete version');
end;

function TVersionAPIService.DiffVersions(const ARequest: TDiffRequest): TAPIResponse;
var
  LFromVersion, LToVersion: TWorkflowVersion;
  LDiff: TVersionDiff;
  LData: TJSONValue;
begin
  LFromVersion := ResolveVersion(ARequest.WorkflowId, ARequest.FromVersion);
  LToVersion := ResolveVersion(ARequest.WorkflowId, ARequest.ToVersion);
  
  if not Assigned(LFromVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, 'From version not found');
    Exit;
  end;
  
  if not Assigned(LToVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, 'To version not found');
    Exit;
  end;
  
  LDiff := FVersionManager.CompareVersions(LFromVersion.VersionId, LToVersion.VersionId);
  try
    if not Assigned(LDiff) then
    begin
      Result := TAPIResponse.Error(ERR_INTERNAL, 'Failed to compare versions');
      Exit;
    end;
    
    if SameText(ARequest.Format, 'markdown') then
      LData := TJSONString.Create(LDiff.ToMarkdown)
    else if SameText(ARequest.Format, 'text') then
      LData := TJSONString.Create(LDiff.ToText)
    else
      LData := LDiff.ToJSON;
    
    Result := TAPIResponse.OK(LData);
  finally
    LDiff.Free;
  end;
end;

function TVersionAPIService.RollbackVersion(const ARequest: TRollbackRequest): TAPIResponse;
var
  LTargetSemVer: TSemVer;
  LNewVersion: TWorkflowVersion;
begin
  LTargetSemVer := TSemVer.Parse(ARequest.TargetVersion);
  if not LTargetSemVer.IsValid then
  begin
    Result := TAPIResponse.Error(ERR_INVALID_REQUEST, MSG_INVALID_VERSION);
    Exit;
  end;
  
  LNewVersion := FVersionManager.Rollback(ARequest.WorkflowId, LTargetSemVer);
  if not Assigned(LNewVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_ROLLBACK_FAILED);
    Exit;
  end;
  
  if not ARequest.Comment.IsEmpty then
    LNewVersion.Comment := ARequest.Comment;
  if not ARequest.CreatedBy.IsEmpty then
    LNewVersion.CreatedBy := ARequest.CreatedBy;
  
  Result := TAPIResponse.OK(LNewVersion.ToJSON, 'Rollback successful');
end;

function TVersionAPIService.GetActiveVersion(const AWorkflowId: string): TAPIResponse;
var
  LVersion: TWorkflowVersion;
begin
  LVersion := FVersionManager.GetActiveVersion(AWorkflowId);
  if not Assigned(LVersion) then
    Result := TAPIResponse.Error(ERR_NOT_FOUND, 'No active version found')
  else
    Result := TAPIResponse.OK(LVersion.ToJSON);
end;

function TVersionAPIService.ActivateVersion(const AWorkflowId, AVersionRef: string): TAPIResponse;
var
  LVersion: TWorkflowVersion;
begin
  LVersion := ResolveVersion(AWorkflowId, AVersionRef);
  if not Assigned(LVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_VERSION_NOT_FOUND);
    Exit;
  end;
  
  if FVersionManager.ActivateVersion(LVersion.VersionId) then
    Result := TAPIResponse.OK(LVersion.ToJSON, 'Version activated')
  else
    Result := TAPIResponse.Error(ERR_INTERNAL, 'Failed to activate version');
end;

function TVersionAPIService.AddTag(const AVersionId, ATag: string): TAPIResponse;
var
  LVersion: TWorkflowVersion;
begin
  LVersion := FVersionManager.Store.GetVersion(AVersionId);
  if not Assigned(LVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_VERSION_NOT_FOUND);
    Exit;
  end;
  
  FVersionManager.AddTag(AVersionId, ATag);
  Result := TAPIResponse.OK(nil, 'Tag added');
end;

function TVersionAPIService.RemoveTag(const AVersionId, ATag: string): TAPIResponse;
var
  LVersion: TWorkflowVersion;
begin
  LVersion := FVersionManager.Store.GetVersion(AVersionId);
  if not Assigned(LVersion) then
  begin
    Result := TAPIResponse.Error(ERR_NOT_FOUND, MSG_VERSION_NOT_FOUND);
    Exit;
  end;
  
  FVersionManager.RemoveTag(AVersionId, ATag);
  Result := TAPIResponse.OK(nil, 'Tag removed');
end;

function TVersionAPIService.FindByTag(const AWorkflowId, ATag: string): TAPIResponse;
var
  LVersions: TList<TWorkflowVersion>;
  LArray: TJSONArray;
  LVersion: TWorkflowVersion;
begin
  LVersions := FVersionManager.FindByTag(AWorkflowId, ATag);
  try
    LArray := TJSONArray.Create;
    for LVersion in LVersions do
      LArray.Add(LVersion.ToJSON);
    
    Result := TAPIResponse.OK(LArray);
  finally
    LVersions.Free;
  end;
end;

end.
