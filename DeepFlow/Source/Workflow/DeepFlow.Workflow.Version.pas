unit UniFlow.Workflow.Version;
(*
  UniFlow Workflow Version Control
  =================================
  TASK-2010: 工作流版本控�?
  
  功能:
  - 工作流多版本并存
  - 版本切换与激�?
  - 版本比较 (Diff)
  - 版本回滚
  - 版本历史查询
  - 语义化版本号 (SemVer)
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.DateUtils, System.RegularExpressions, System.Hash,
  UniFlow.Workflow.Definition;

type
  // ============================================================================
  // 版本�?(语义化版�?
  // ============================================================================
  
  TSemVer = record
    Major: Integer;
    Minor: Integer;
    Patch: Integer;
    PreRelease: string;  // alpha, beta, rc.1
    BuildMeta: string;   // build metadata
    
    class function Parse(const AVersion: string): TSemVer; static;
    class function Create(AMajor, AMinor, APatch: Integer): TSemVer; static;
    
    function ToString: string;
    function ToShortString: string;  // Major.Minor.Patch only
    function Compare(const AOther: TSemVer): Integer;
    
    function IncrementMajor: TSemVer;
    function IncrementMinor: TSemVer;
    function IncrementPatch: TSemVer;
    
    function IsPreRelease: Boolean;
    function IsValid: Boolean;
    
    class operator Equal(const A, B: TSemVer): Boolean;
    class operator NotEqual(const A, B: TSemVer): Boolean;
    class operator LessThan(const A, B: TSemVer): Boolean;
    class operator GreaterThan(const A, B: TSemVer): Boolean;
  end;
  
  // ============================================================================
  // 版本状�?
  // ============================================================================
  
  TVersionStatus = (
    vsDraft,      // 草稿
    vsActive,     // 激�?(当前使用)
    vsArchived,   // 归档
    vsDeprecated  // 废弃
  );
  
  // ============================================================================
  // 变更类型
  // ============================================================================
  
  TChangeType = (
    ctAdded,      // 新增
    ctModified,   // 修改
    ctRemoved,    // 删除
    ctRenamed     // 重命�?
  );
  
  // ============================================================================
  // 变更记录
  // ============================================================================
  
  TChangeRecord = record
    ChangeType: TChangeType;
    Path: string;           // JSON Path: steps[0].action.config.prompt
    OldValue: string;
    NewValue: string;
    Description: string;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TChangeRecord; static;
  end;
  
  // ============================================================================
  // 版本差异
  // ============================================================================
  
  TVersionDiff = class
  private
    FFromVersion: string;
    FToVersion: string;
    FChanges: TList<TChangeRecord>;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddChange(const AChange: TChangeRecord);
    procedure Clear;
    
    function ToJSON: TJSONObject;
    function ToMarkdown: string;
    function ToText: string;
    
    property FromVersion: string read FFromVersion write FFromVersion;
    property ToVersion: string read FToVersion write FToVersion;
    property Changes: TList<TChangeRecord> read FChanges;
    property CreatedAt: TDateTime read FCreatedAt;
  end;
  
  // ============================================================================
  // 工作流版�?
  // ============================================================================
  
  TWorkflowVersion = class
  private
    FVersionId: string;
    FWorkflowId: string;
    FVersion: TSemVer;
    FStatus: TVersionStatus;
    FDefinition: TWorkflowDefinition;
    FDefinitionHash: string;
    FCreatedAt: TDateTime;
    FCreatedBy: string;
    FComment: string;
    FTags: TStringList;
    FParentVersionId: string;
    
    procedure CalculateHash;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Clone: TWorkflowVersion;
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TWorkflowVersion; static;
    
    property VersionId: string read FVersionId write FVersionId;
    property WorkflowId: string read FWorkflowId write FWorkflowId;
    property Version: TSemVer read FVersion write FVersion;
    property Status: TVersionStatus read FStatus write FStatus;
    property Definition: TWorkflowDefinition read FDefinition write FDefinition;
    property DefinitionHash: string read FDefinitionHash;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property CreatedBy: string read FCreatedBy write FCreatedBy;
    property Comment: string read FComment write FComment;
    property Tags: TStringList read FTags;
    property ParentVersionId: string read FParentVersionId write FParentVersionId;
  end;
  
  // ============================================================================
  // 版本比较�?
  // ============================================================================
  
  TVersionComparator = class
  private
    class function CompareJSON(const APath: string; AOld, ANew: TJSONValue;
      AChanges: TList<TChangeRecord>): Boolean; static;
    class function CompareObject(const APath: string; AOld, ANew: TJSONObject;
      AChanges: TList<TChangeRecord>): Boolean; static;
    class function CompareArray(const APath: string; AOld, ANew: TJSONArray;
      AChanges: TList<TChangeRecord>): Boolean; static;
  public
    class function Compare(AFrom, ATo: TWorkflowVersion): TVersionDiff; static;
    class function CompareDefinitions(AFrom, ATo: TWorkflowDefinition): TVersionDiff; static;
  end;
  
  // ============================================================================
  // 版本存储接口
  // ============================================================================
  
  IVersionStore = interface
    ['{F1E2D3C4-B5A6-4789-8012-3456789ABCDEF}']
    function SaveVersion(AVersion: TWorkflowVersion): Boolean;
    function GetVersion(const AVersionId: string): TWorkflowVersion;
    function GetVersionByNumber(const AWorkflowId: string; const AVersion: TSemVer): TWorkflowVersion;
    function GetLatestVersion(const AWorkflowId: string): TWorkflowVersion;
    function GetActiveVersion(const AWorkflowId: string): TWorkflowVersion;
    function GetVersionHistory(const AWorkflowId: string): TList<TWorkflowVersion>;
    function DeleteVersion(const AVersionId: string): Boolean;
    function VersionExists(const AWorkflowId: string; const AVersion: TSemVer): Boolean;
  end;
  
  // ============================================================================
  // 内存版本存储
  // ============================================================================
  
  TMemoryVersionStore = class(TInterfacedObject, IVersionStore)
  private
    FVersions: TObjectDictionary<string, TWorkflowVersion>;
    FWorkflowVersions: TDictionary<string, TList<string>>;  // WorkflowId -> VersionIds
  public
    constructor Create;
    destructor Destroy; override;
    
    function SaveVersion(AVersion: TWorkflowVersion): Boolean;
    function GetVersion(const AVersionId: string): TWorkflowVersion;
    function GetVersionByNumber(const AWorkflowId: string; const AVersion: TSemVer): TWorkflowVersion;
    function GetLatestVersion(const AWorkflowId: string): TWorkflowVersion;
    function GetActiveVersion(const AWorkflowId: string): TWorkflowVersion;
    function GetVersionHistory(const AWorkflowId: string): TList<TWorkflowVersion>;
    function DeleteVersion(const AVersionId: string): Boolean;
    function VersionExists(const AWorkflowId: string; const AVersion: TSemVer): Boolean;
  end;
  
  // ============================================================================
  // 版本管理�?
  // ============================================================================
  
  TVersionManager = class
  private
    FStore: IVersionStore;
  public
    constructor Create(AStore: IVersionStore = nil);
    destructor Destroy; override;
    
    /// <summary>创建新版�?/summary>
    function CreateVersion(const AWorkflowId: string; ADefinition: TWorkflowDefinition;
      const AComment: string = ''; const ACreatedBy: string = ''): TWorkflowVersion;
    
    /// <summary>创建草稿版本</summary>
    function CreateDraft(const AWorkflowId: string; ADefinition: TWorkflowDefinition): TWorkflowVersion;
    
    /// <summary>发布草稿</summary>
    function PublishDraft(const AVersionId: string; const AComment: string = ''): TWorkflowVersion;
    
    /// <summary>激活版�?/summary>
    function ActivateVersion(const AVersionId: string): Boolean;
    
    /// <summary>归档版本</summary>
    function ArchiveVersion(const AVersionId: string): Boolean;
    
    /// <summary>废弃版本</summary>
    function DeprecateVersion(const AVersionId: string): Boolean;
    
    /// <summary>回滚到指定版�?/summary>
    function Rollback(const AWorkflowId: string; const ATargetVersion: TSemVer): TWorkflowVersion;
    
    /// <summary>比较两个版本</summary>
    function CompareVersions(const AFromVersionId, AToVersionId: string): TVersionDiff;
    
    /// <summary>获取版本历史</summary>
    function GetHistory(const AWorkflowId: string): TList<TWorkflowVersion>;
    
    /// <summary>获取当前激活版�?/summary>
    function GetActiveVersion(const AWorkflowId: string): TWorkflowVersion;
    
    /// <summary>获取最新版�?/summary>
    function GetLatestVersion(const AWorkflowId: string): TWorkflowVersion;
    
    /// <summary>按版本号获取</summary>
    function GetByVersion(const AWorkflowId: string; const AVersion: TSemVer): TWorkflowVersion;
    
    /// <summary>添加标签</summary>
    procedure AddTag(const AVersionId, ATag: string);
    
    /// <summary>移除标签</summary>
    procedure RemoveTag(const AVersionId, ATag: string);
    
    /// <summary>按标签查�?/summary>
    function FindByTag(const AWorkflowId, ATag: string): TList<TWorkflowVersion>;
    
    property Store: IVersionStore read FStore;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
function VersionStatusToString(AStatus: TVersionStatus): string;
function StringToVersionStatus(const AStr: string): TVersionStatus;
function ChangeTypeToString(AType: TChangeType): string;
function GenerateVersionId: string;

implementation

// ============================================================================
// TSemVer Implementation
// ============================================================================

class function TSemVer.Parse(const AVersion: string): TSemVer;
var
  LMatch: TMatch;
  LParts: TArray<string>;
  LCore, LExtra: string;
begin
  Result.Major := 0;
  Result.Minor := 0;
  Result.Patch := 0;
  Result.PreRelease := '';
  Result.BuildMeta := '';
  
  if AVersion.IsEmpty then Exit;
  
  // Split by + for build metadata
  LParts := AVersion.Split(['+']);
  LCore := LParts[0];
  if Length(LParts) > 1 then
    Result.BuildMeta := LParts[1];
  
  // Split by - for pre-release
  LParts := LCore.Split(['-']);
  LCore := LParts[0];
  if Length(LParts) > 1 then
    Result.PreRelease := LParts[1];
  
  // Parse core version
  LParts := LCore.Split(['.']);
  if Length(LParts) >= 1 then
    TryStrToInt(LParts[0], Result.Major);
  if Length(LParts) >= 2 then
    TryStrToInt(LParts[1], Result.Minor);
  if Length(LParts) >= 3 then
    TryStrToInt(LParts[2], Result.Patch);
end;

class function TSemVer.Create(AMajor, AMinor, APatch: Integer): TSemVer;
begin
  Result.Major := AMajor;
  Result.Minor := AMinor;
  Result.Patch := APatch;
  Result.PreRelease := '';
  Result.BuildMeta := '';
end;

function TSemVer.ToString: string;
begin
  Result := Format('%d.%d.%d', [Major, Minor, Patch]);
  if not PreRelease.IsEmpty then
    Result := Result + '-' + PreRelease;
  if not BuildMeta.IsEmpty then
    Result := Result + '+' + BuildMeta;
end;

function TSemVer.ToShortString: string;
begin
  Result := Format('%d.%d.%d', [Major, Minor, Patch]);
end;

function TSemVer.Compare(const AOther: TSemVer): Integer;
begin
  Result := Major - AOther.Major;
  if Result <> 0 then Exit;
  
  Result := Minor - AOther.Minor;
  if Result <> 0 then Exit;
  
  Result := Patch - AOther.Patch;
  if Result <> 0 then Exit;
  
  // Pre-release versions have lower precedence
  if PreRelease.IsEmpty and not AOther.PreRelease.IsEmpty then
    Result := 1
  else if not PreRelease.IsEmpty and AOther.PreRelease.IsEmpty then
    Result := -1
  else
    Result := CompareStr(PreRelease, AOther.PreRelease);
end;

function TSemVer.IncrementMajor: TSemVer;
begin
  Result := TSemVer.Create(Major + 1, 0, 0);
end;

function TSemVer.IncrementMinor: TSemVer;
begin
  Result := TSemVer.Create(Major, Minor + 1, 0);
end;

function TSemVer.IncrementPatch: TSemVer;
begin
  Result := TSemVer.Create(Major, Minor, Patch + 1);
end;

function TSemVer.IsPreRelease: Boolean;
begin
  Result := not PreRelease.IsEmpty;
end;

function TSemVer.IsValid: Boolean;
begin
  Result := (Major >= 0) and (Minor >= 0) and (Patch >= 0);
end;

class operator TSemVer.Equal(const A, B: TSemVer): Boolean;
begin
  Result := A.Compare(B) = 0;
end;

class operator TSemVer.NotEqual(const A, B: TSemVer): Boolean;
begin
  Result := A.Compare(B) <> 0;
end;

class operator TSemVer.LessThan(const A, B: TSemVer): Boolean;
begin
  Result := A.Compare(B) < 0;
end;

class operator TSemVer.GreaterThan(const A, B: TSemVer): Boolean;
begin
  Result := A.Compare(B) > 0;
end;

// ============================================================================
// TChangeRecord Implementation
// ============================================================================

function TChangeRecord.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', ChangeTypeToString(ChangeType));
  Result.AddPair('path', Path);
  Result.AddPair('old_value', OldValue);
  Result.AddPair('new_value', NewValue);
  Result.AddPair('description', Description);
end;

class function TChangeRecord.FromJSON(AJson: TJSONObject): TChangeRecord;
begin
  Result.ChangeType := ctModified;
  Result.Path := AJson.GetValue<string>('path', '');
  Result.OldValue := AJson.GetValue<string>('old_value', '');
  Result.NewValue := AJson.GetValue<string>('new_value', '');
  Result.Description := AJson.GetValue<string>('description', '');
  
  var LTypeStr := AJson.GetValue<string>('type', 'modified');
  if LTypeStr = 'added' then Result.ChangeType := ctAdded
  else if LTypeStr = 'removed' then Result.ChangeType := ctRemoved
  else if LTypeStr = 'renamed' then Result.ChangeType := ctRenamed;
end;

// ============================================================================
// TVersionDiff Implementation
// ============================================================================

constructor TVersionDiff.Create;
begin
  inherited Create;
  FChanges := TList<TChangeRecord>.Create;
  FCreatedAt := Now;
end;

destructor TVersionDiff.Destroy;
begin
  FChanges.Free;
  inherited;
end;

procedure TVersionDiff.AddChange(const AChange: TChangeRecord);
begin
  FChanges.Add(AChange);
end;

procedure TVersionDiff.Clear;
begin
  FChanges.Clear;
end;

function TVersionDiff.ToJSON: TJSONObject;
var
  LChangesArray: TJSONArray;
  LChange: TChangeRecord;
begin
  Result := TJSONObject.Create;
  Result.AddPair('from_version', FFromVersion);
  Result.AddPair('to_version', FToVersion);
  Result.AddPair('created_at', DateTimeToStr(FCreatedAt));
  Result.AddPair('change_count', TJSONNumber.Create(FChanges.Count));
  
  LChangesArray := TJSONArray.Create;
  for LChange in FChanges do
    LChangesArray.Add(LChange.ToJSON);
  Result.AddPair('changes', LChangesArray);
end;

function TVersionDiff.ToMarkdown: string;
var
  LSB: TStringBuilder;
  LChange: TChangeRecord;
begin
  LSB := TStringBuilder.Create;
  try
    LSB.AppendLine('# Version Diff');
    LSB.AppendLine;
    LSB.AppendFormat('**From:** %s', [FFromVersion]).AppendLine;
    LSB.AppendFormat('**To:** %s', [FToVersion]).AppendLine;
    LSB.AppendFormat('**Changes:** %d', [FChanges.Count]).AppendLine;
    LSB.AppendLine;
    
    for LChange in FChanges do
    begin
      case LChange.ChangeType of
        ctAdded: LSB.AppendFormat('+ **Added** `%s`', [LChange.Path]).AppendLine;
        ctRemoved: LSB.AppendFormat('- **Removed** `%s`', [LChange.Path]).AppendLine;
        ctModified: LSB.AppendFormat('~ **Modified** `%s`', [LChange.Path]).AppendLine;
        ctRenamed: LSB.AppendFormat('> **Renamed** `%s`', [LChange.Path]).AppendLine;
      end;
      if not LChange.Description.IsEmpty then
        LSB.AppendFormat('  %s', [LChange.Description]).AppendLine;
    end;
    
    Result := LSB.ToString;
  finally
    LSB.Free;
  end;
end;

function TVersionDiff.ToText: string;
var
  LSB: TStringBuilder;
  LChange: TChangeRecord;
begin
  LSB := TStringBuilder.Create;
  try
    LSB.AppendFormat('Diff: %s -> %s (%d changes)', [FFromVersion, FToVersion, FChanges.Count]).AppendLine;
    LSB.AppendLine('----------------------------------------');
    
    for LChange in FChanges do
    begin
      LSB.AppendFormat('[%s] %s', [ChangeTypeToString(LChange.ChangeType), LChange.Path]).AppendLine;
      if not LChange.OldValue.IsEmpty then
        LSB.AppendFormat('  - %s', [LChange.OldValue]).AppendLine;
      if not LChange.NewValue.IsEmpty then
        LSB.AppendFormat('  + %s', [LChange.NewValue]).AppendLine;
    end;
    
    Result := LSB.ToString;
  finally
    LSB.Free;
  end;
end;

// ============================================================================
// TWorkflowVersion Implementation
// ============================================================================

constructor TWorkflowVersion.Create;
begin
  inherited Create;
  FVersionId := GenerateVersionId;
  FVersion := TSemVer.Create(1, 0, 0);
  FStatus := vsDraft;
  FCreatedAt := Now;
  FTags := TStringList.Create;
  FTags.Duplicates := dupIgnore;
end;

destructor TWorkflowVersion.Destroy;
begin
  FTags.Free;
  FDefinition.Free;
  inherited;
end;

procedure TWorkflowVersion.CalculateHash;
var
  LJson: TJSONObject;
begin
  if Assigned(FDefinition) then
  begin
    LJson := FDefinition.ToJSON;
    try
      FDefinitionHash := THashSHA2.GetHashString(LJson.ToJSON);
    finally
      LJson.Free;
    end;
  end
  else
    FDefinitionHash := '';
end;

function TWorkflowVersion.Clone: TWorkflowVersion;
begin
  Result := TWorkflowVersion.Create;
  Result.FVersionId := GenerateVersionId;
  Result.FWorkflowId := FWorkflowId;
  Result.FVersion := FVersion;
  Result.FStatus := vsDraft;
  Result.FCreatedAt := Now;
  Result.FCreatedBy := FCreatedBy;
  Result.FComment := '';
  Result.FParentVersionId := FVersionId;
  Result.FTags.Assign(FTags);
  
  if Assigned(FDefinition) then
    Result.FDefinition := FDefinition.Clone;
end;

function TWorkflowVersion.ToJSON: TJSONObject;
var
  LTagsArray: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('version_id', FVersionId);
  Result.AddPair('workflow_id', FWorkflowId);
  Result.AddPair('version', FVersion.ToString);
  Result.AddPair('status', VersionStatusToString(FStatus));
  Result.AddPair('definition_hash', FDefinitionHash);
  Result.AddPair('created_at', DateTimeToStr(FCreatedAt));
  Result.AddPair('created_by', FCreatedBy);
  Result.AddPair('comment', FComment);
  Result.AddPair('parent_version_id', FParentVersionId);
  
  LTagsArray := TJSONArray.Create;
  for I := 0 to FTags.Count - 1 do
    LTagsArray.Add(FTags[I]);
  Result.AddPair('tags', LTagsArray);
  
  if Assigned(FDefinition) then
    Result.AddPair('definition', FDefinition.ToJSON);
end;

class function TWorkflowVersion.FromJSON(AJson: TJSONObject): TWorkflowVersion;
var
  LTagsArray: TJSONArray;
  I: Integer;
  LDefJson: TJSONObject;
begin
  Result := TWorkflowVersion.Create;
  Result.FVersionId := AJson.GetValue<string>('version_id', Result.FVersionId);
  Result.FWorkflowId := AJson.GetValue<string>('workflow_id', '');
  Result.FVersion := TSemVer.Parse(AJson.GetValue<string>('version', '1.0.0'));
  Result.FStatus := StringToVersionStatus(AJson.GetValue<string>('status', 'draft'));
  Result.FDefinitionHash := AJson.GetValue<string>('definition_hash', '');
  Result.FCreatedBy := AJson.GetValue<string>('created_by', '');
  Result.FComment := AJson.GetValue<string>('comment', '');
  Result.FParentVersionId := AJson.GetValue<string>('parent_version_id', '');
  
  if AJson.TryGetValue<TJSONArray>('tags', LTagsArray) then
  begin
    for I := 0 to LTagsArray.Count - 1 do
      Result.FTags.Add(LTagsArray.Items[I].Value);
  end;
  
  if AJson.TryGetValue<TJSONObject>('definition', LDefJson) then
    Result.FDefinition := TWorkflowDefinition.FromJSON(LDefJson);
end;

// ============================================================================
// TVersionComparator Implementation
// ============================================================================

class function TVersionComparator.Compare(AFrom, ATo: TWorkflowVersion): TVersionDiff;
begin
  Result := CompareDefinitions(AFrom.Definition, ATo.Definition);
  Result.FFromVersion := AFrom.Version.ToString;
  Result.FToVersion := ATo.Version.ToString;
end;

class function TVersionComparator.CompareDefinitions(AFrom, ATo: TWorkflowDefinition): TVersionDiff;
var
  LFromJson, LToJson: TJSONObject;
begin
  Result := TVersionDiff.Create;
  
  LFromJson := AFrom.ToJSON;
  LToJson := ATo.ToJSON;
  try
    CompareObject('', LFromJson, LToJson, Result.FChanges);
  finally
    LToJson.Free;
    LFromJson.Free;
  end;
end;

class function TVersionComparator.CompareJSON(const APath: string; AOld, ANew: TJSONValue;
  AChanges: TList<TChangeRecord>): Boolean;
var
  LChange: TChangeRecord;
begin
  Result := False;
  
  // Type changed
  if AOld.ClassType <> ANew.ClassType then
  begin
    LChange.ChangeType := ctModified;
    LChange.Path := APath;
    LChange.OldValue := AOld.ToJSON;
    LChange.NewValue := ANew.ToJSON;
    LChange.Description := 'Type changed';
    AChanges.Add(LChange);
    Result := True;
    Exit;
  end;
  
  // Compare based on type
  if AOld is TJSONObject then
    Result := CompareObject(APath, TJSONObject(AOld), TJSONObject(ANew), AChanges)
  else if AOld is TJSONArray then
    Result := CompareArray(APath, TJSONArray(AOld), TJSONArray(ANew), AChanges)
  else
  begin
    // Primitive value comparison
    if AOld.ToJSON <> ANew.ToJSON then
    begin
      LChange.ChangeType := ctModified;
      LChange.Path := APath;
      LChange.OldValue := AOld.Value;
      LChange.NewValue := ANew.Value;
      LChange.Description := '';
      AChanges.Add(LChange);
      Result := True;
    end;
  end;
end;

class function TVersionComparator.CompareObject(const APath: string; AOld, ANew: TJSONObject;
  AChanges: TList<TChangeRecord>): Boolean;
var
  LPair: TJSONPair;
  LKey, LNewPath: string;
  LChange: TChangeRecord;
begin
  Result := False;
  
  // Check for removed keys
  for LPair in AOld do
  begin
    LKey := LPair.JsonString.Value;
    LNewPath := IfThen(APath.IsEmpty, LKey, APath + '.' + LKey);
    
    if ANew.GetValue(LKey) = nil then
    begin
      LChange.ChangeType := ctRemoved;
      LChange.Path := LNewPath;
      LChange.OldValue := LPair.JsonValue.ToJSON;
      LChange.NewValue := '';
      LChange.Description := '';
      AChanges.Add(LChange);
      Result := True;
    end;
  end;
  
  // Check for added and modified keys
  for LPair in ANew do
  begin
    LKey := LPair.JsonString.Value;
    LNewPath := IfThen(APath.IsEmpty, LKey, APath + '.' + LKey);
    
    if AOld.GetValue(LKey) = nil then
    begin
      LChange.ChangeType := ctAdded;
      LChange.Path := LNewPath;
      LChange.OldValue := '';
      LChange.NewValue := LPair.JsonValue.ToJSON;
      LChange.Description := '';
      AChanges.Add(LChange);
      Result := True;
    end
    else if CompareJSON(LNewPath, AOld.GetValue(LKey), LPair.JsonValue, AChanges) then
      Result := True;
  end;
end;

class function TVersionComparator.CompareArray(const APath: string; AOld, ANew: TJSONArray;
  AChanges: TList<TChangeRecord>): Boolean;
var
  I: Integer;
  LChange: TChangeRecord;
  LNewPath: string;
begin
  Result := False;
  
  // Simple length comparison
  if AOld.Count <> ANew.Count then
  begin
    LChange.ChangeType := ctModified;
    LChange.Path := APath;
    LChange.OldValue := Format('Array[%d]', [AOld.Count]);
    LChange.NewValue := Format('Array[%d]', [ANew.Count]);
    LChange.Description := 'Array size changed';
    AChanges.Add(LChange);
    Result := True;
  end;
  
  // Compare each element
  for I := 0 to Min(AOld.Count, ANew.Count) - 1 do
  begin
    LNewPath := Format('%s[%d]', [APath, I]);
    if CompareJSON(LNewPath, AOld.Items[I], ANew.Items[I], AChanges) then
      Result := True;
  end;
end;

// ============================================================================
// TMemoryVersionStore Implementation
// ============================================================================

constructor TMemoryVersionStore.Create;
begin
  inherited Create;
  FVersions := TObjectDictionary<string, TWorkflowVersion>.Create([doOwnsValues]);
  FWorkflowVersions := TDictionary<string, TList<string>>.Create;
end;

destructor TMemoryVersionStore.Destroy;
var
  LList: TList<string>;
begin
  for LList in FWorkflowVersions.Values do
    LList.Free;
  FWorkflowVersions.Free;
  FVersions.Free;
  inherited;
end;

function TMemoryVersionStore.SaveVersion(AVersion: TWorkflowVersion): Boolean;
var
  LVersionList: TList<string>;
begin
  Result := False;
  if not Assigned(AVersion) then Exit;
  
  FVersions.AddOrSetValue(AVersion.VersionId, AVersion);
  
  if not FWorkflowVersions.TryGetValue(AVersion.WorkflowId, LVersionList) then
  begin
    LVersionList := TList<string>.Create;
    FWorkflowVersions.Add(AVersion.WorkflowId, LVersionList);
  end;
  
  if not LVersionList.Contains(AVersion.VersionId) then
    LVersionList.Add(AVersion.VersionId);
  
  Result := True;
end;

function TMemoryVersionStore.GetVersion(const AVersionId: string): TWorkflowVersion;
begin
  if not FVersions.TryGetValue(AVersionId, Result) then
    Result := nil;
end;

function TMemoryVersionStore.GetVersionByNumber(const AWorkflowId: string; const AVersion: TSemVer): TWorkflowVersion;
var
  LVersionList: TList<string>;
  LVersionId: string;
  LVersion: TWorkflowVersion;
begin
  Result := nil;
  
  if not FWorkflowVersions.TryGetValue(AWorkflowId, LVersionList) then Exit;
  
  for LVersionId in LVersionList do
  begin
    if FVersions.TryGetValue(LVersionId, LVersion) then
    begin
      if LVersion.Version = AVersion then
      begin
        Result := LVersion;
        Exit;
      end;
    end;
  end;
end;

function TMemoryVersionStore.GetLatestVersion(const AWorkflowId: string): TWorkflowVersion;
var
  LVersionList: TList<string>;
  LVersionId: string;
  LVersion: TWorkflowVersion;
begin
  Result := nil;
  
  if not FWorkflowVersions.TryGetValue(AWorkflowId, LVersionList) then Exit;
  
  for LVersionId in LVersionList do
  begin
    if FVersions.TryGetValue(LVersionId, LVersion) then
    begin
      if (Result = nil) or (LVersion.Version > Result.Version) then
        Result := LVersion;
    end;
  end;
end;

function TMemoryVersionStore.GetActiveVersion(const AWorkflowId: string): TWorkflowVersion;
var
  LVersionList: TList<string>;
  LVersionId: string;
  LVersion: TWorkflowVersion;
begin
  Result := nil;
  
  if not FWorkflowVersions.TryGetValue(AWorkflowId, LVersionList) then Exit;
  
  for LVersionId in LVersionList do
  begin
    if FVersions.TryGetValue(LVersionId, LVersion) then
    begin
      if LVersion.Status = vsActive then
      begin
        Result := LVersion;
        Exit;
      end;
    end;
  end;
end;

function TMemoryVersionStore.GetVersionHistory(const AWorkflowId: string): TList<TWorkflowVersion>;
var
  LVersionList: TList<string>;
  LVersionId: string;
  LVersion: TWorkflowVersion;
begin
  Result := TList<TWorkflowVersion>.Create;
  
  if not FWorkflowVersions.TryGetValue(AWorkflowId, LVersionList) then Exit;
  
  for LVersionId in LVersionList do
  begin
    if FVersions.TryGetValue(LVersionId, LVersion) then
      Result.Add(LVersion);
  end;
  
  // Sort by version descending
  Result.Sort(TComparer<TWorkflowVersion>.Construct(
    function(const A, B: TWorkflowVersion): Integer
    begin
      Result := -A.Version.Compare(B.Version);
    end));
end;

function TMemoryVersionStore.DeleteVersion(const AVersionId: string): Boolean;
var
  LVersion: TWorkflowVersion;
  LVersionList: TList<string>;
begin
  Result := False;
  
  if not FVersions.TryGetValue(AVersionId, LVersion) then Exit;
  
  if FWorkflowVersions.TryGetValue(LVersion.WorkflowId, LVersionList) then
    LVersionList.Remove(AVersionId);
  
  FVersions.Remove(AVersionId);
  Result := True;
end;

function TMemoryVersionStore.VersionExists(const AWorkflowId: string; const AVersion: TSemVer): Boolean;
begin
  Result := GetVersionByNumber(AWorkflowId, AVersion) <> nil;
end;

// ============================================================================
// TVersionManager Implementation
// ============================================================================

constructor TVersionManager.Create(AStore: IVersionStore);
begin
  inherited Create;
  if Assigned(AStore) then
    FStore := AStore
  else
    FStore := TMemoryVersionStore.Create;
end;

destructor TVersionManager.Destroy;
begin
  FStore := nil;
  inherited;
end;

function TVersionManager.CreateVersion(const AWorkflowId: string; ADefinition: TWorkflowDefinition;
  const AComment: string; const ACreatedBy: string): TWorkflowVersion;
var
  LLatest: TWorkflowVersion;
begin
  Result := TWorkflowVersion.Create;
  Result.WorkflowId := AWorkflowId;
  Result.Definition := ADefinition.Clone;
  Result.Comment := AComment;
  Result.CreatedBy := ACreatedBy;
  Result.Status := vsActive;
  
  // Determine next version number
  LLatest := FStore.GetLatestVersion(AWorkflowId);
  if Assigned(LLatest) then
  begin
    Result.Version := LLatest.Version.IncrementPatch;
    Result.ParentVersionId := LLatest.VersionId;
    
    // Deactivate previous active version
    var LActive := FStore.GetActiveVersion(AWorkflowId);
    if Assigned(LActive) then
      LActive.Status := vsArchived;
  end
  else
    Result.Version := TSemVer.Create(1, 0, 0);
  
  Result.CalculateHash;
  FStore.SaveVersion(Result);
end;

function TVersionManager.CreateDraft(const AWorkflowId: string; ADefinition: TWorkflowDefinition): TWorkflowVersion;
var
  LLatest: TWorkflowVersion;
begin
  Result := TWorkflowVersion.Create;
  Result.WorkflowId := AWorkflowId;
  Result.Definition := ADefinition.Clone;
  Result.Status := vsDraft;
  
  LLatest := FStore.GetLatestVersion(AWorkflowId);
  if Assigned(LLatest) then
  begin
    Result.Version := LLatest.Version.IncrementPatch;
    Result.Version.PreRelease := 'draft';
    Result.ParentVersionId := LLatest.VersionId;
  end
  else
  begin
    Result.Version := TSemVer.Create(1, 0, 0);
    Result.Version.PreRelease := 'draft';
  end;
  
  Result.CalculateHash;
  FStore.SaveVersion(Result);
end;

function TVersionManager.PublishDraft(const AVersionId: string; const AComment: string): TWorkflowVersion;
var
  LDraft: TWorkflowVersion;
begin
  Result := nil;
  LDraft := FStore.GetVersion(AVersionId);
  if not Assigned(LDraft) or (LDraft.Status <> vsDraft) then Exit;
  
  // Remove pre-release tag
  LDraft.Version.PreRelease := '';
  LDraft.Status := vsActive;
  LDraft.Comment := AComment;
  
  // Deactivate previous active version
  var LActive := FStore.GetActiveVersion(LDraft.WorkflowId);
  if Assigned(LActive) and (LActive.VersionId <> LDraft.VersionId) then
    LActive.Status := vsArchived;
  
  FStore.SaveVersion(LDraft);
  Result := LDraft;
end;

function TVersionManager.ActivateVersion(const AVersionId: string): Boolean;
var
  LVersion, LCurrentActive: TWorkflowVersion;
begin
  Result := False;
  LVersion := FStore.GetVersion(AVersionId);
  if not Assigned(LVersion) then Exit;
  
  // Deactivate current active
  LCurrentActive := FStore.GetActiveVersion(LVersion.WorkflowId);
  if Assigned(LCurrentActive) then
    LCurrentActive.Status := vsArchived;
  
  LVersion.Status := vsActive;
  FStore.SaveVersion(LVersion);
  Result := True;
end;

function TVersionManager.ArchiveVersion(const AVersionId: string): Boolean;
var
  LVersion: TWorkflowVersion;
begin
  Result := False;
  LVersion := FStore.GetVersion(AVersionId);
  if not Assigned(LVersion) then Exit;
  
  LVersion.Status := vsArchived;
  FStore.SaveVersion(LVersion);
  Result := True;
end;

function TVersionManager.DeprecateVersion(const AVersionId: string): Boolean;
var
  LVersion: TWorkflowVersion;
begin
  Result := False;
  LVersion := FStore.GetVersion(AVersionId);
  if not Assigned(LVersion) then Exit;
  
  LVersion.Status := vsDeprecated;
  FStore.SaveVersion(LVersion);
  Result := True;
end;

function TVersionManager.Rollback(const AWorkflowId: string; const ATargetVersion: TSemVer): TWorkflowVersion;
var
  LTarget: TWorkflowVersion;
begin
  Result := nil;
  LTarget := FStore.GetVersionByNumber(AWorkflowId, ATargetVersion);
  if not Assigned(LTarget) then Exit;
  
  // Create new version from target
  Result := CreateVersion(AWorkflowId, LTarget.Definition, 
    Format('Rollback to %s', [ATargetVersion.ToString]), '');
  Result.Tags.Add('rollback');
end;

function TVersionManager.CompareVersions(const AFromVersionId, AToVersionId: string): TVersionDiff;
var
  LFrom, LTo: TWorkflowVersion;
begin
  Result := nil;
  
  LFrom := FStore.GetVersion(AFromVersionId);
  LTo := FStore.GetVersion(AToVersionId);
  
  if Assigned(LFrom) and Assigned(LTo) then
    Result := TVersionComparator.Compare(LFrom, LTo);
end;

function TVersionManager.GetHistory(const AWorkflowId: string): TList<TWorkflowVersion>;
begin
  Result := FStore.GetVersionHistory(AWorkflowId);
end;

function TVersionManager.GetActiveVersion(const AWorkflowId: string): TWorkflowVersion;
begin
  Result := FStore.GetActiveVersion(AWorkflowId);
end;

function TVersionManager.GetLatestVersion(const AWorkflowId: string): TWorkflowVersion;
begin
  Result := FStore.GetLatestVersion(AWorkflowId);
end;

function TVersionManager.GetByVersion(const AWorkflowId: string; const AVersion: TSemVer): TWorkflowVersion;
begin
  Result := FStore.GetVersionByNumber(AWorkflowId, AVersion);
end;

procedure TVersionManager.AddTag(const AVersionId, ATag: string);
var
  LVersion: TWorkflowVersion;
begin
  LVersion := FStore.GetVersion(AVersionId);
  if Assigned(LVersion) then
  begin
    LVersion.Tags.Add(ATag);
    FStore.SaveVersion(LVersion);
  end;
end;

procedure TVersionManager.RemoveTag(const AVersionId, ATag: string);
var
  LVersion: TWorkflowVersion;
  LIndex: Integer;
begin
  LVersion := FStore.GetVersion(AVersionId);
  if Assigned(LVersion) then
  begin
    LIndex := LVersion.Tags.IndexOf(ATag);
    if LIndex >= 0 then
    begin
      LVersion.Tags.Delete(LIndex);
      FStore.SaveVersion(LVersion);
    end;
  end;
end;

function TVersionManager.FindByTag(const AWorkflowId, ATag: string): TList<TWorkflowVersion>;
var
  LHistory: TList<TWorkflowVersion>;
  LVersion: TWorkflowVersion;
begin
  Result := TList<TWorkflowVersion>.Create;
  LHistory := GetHistory(AWorkflowId);
  try
    for LVersion in LHistory do
    begin
      if LVersion.Tags.IndexOf(ATag) >= 0 then
        Result.Add(LVersion);
    end;
  finally
    LHistory.Free;
  end;
end;

// ============================================================================
// Helper Functions
// ============================================================================

function VersionStatusToString(AStatus: TVersionStatus): string;
begin
  case AStatus of
    vsDraft: Result := 'draft';
    vsActive: Result := 'active';
    vsArchived: Result := 'archived';
    vsDeprecated: Result := 'deprecated';
  else
    Result := 'unknown';
  end;
end;

function StringToVersionStatus(const AStr: string): TVersionStatus;
begin
  if AStr = 'draft' then Result := vsDraft
  else if AStr = 'active' then Result := vsActive
  else if AStr = 'archived' then Result := vsArchived
  else if AStr = 'deprecated' then Result := vsDeprecated
  else Result := vsDraft;
end;

function ChangeTypeToString(AType: TChangeType): string;
begin
  case AType of
    ctAdded: Result := 'added';
    ctModified: Result := 'modified';
    ctRemoved: Result := 'removed';
    ctRenamed: Result := 'renamed';
  else
    Result := 'unknown';
  end;
end;

function GenerateVersionId: string;
var
  LGUID: TGUID;
begin
  CreateGUID(LGUID);
  Result := 'ver_' + GUIDToString(LGUID).Replace('{', '').Replace('}', '').Replace('-', '').ToLower;
end;

end.
