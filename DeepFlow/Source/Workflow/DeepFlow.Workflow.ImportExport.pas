unit UniFlow.Workflow.ImportExport;
(*
  UniFlow Workflow Import/Export
  ==============================
  TASK-2013: 工作流导�?导出
  
  功能:
  - 工作�?JSON 导出 (单个/批量)
  - 工作�?JSON 导入 (验证/冲突处理)
  - 跨系统迁移支�?
  - 导出包打�?(多工作流 + 依赖)
  - 导入兼容性检�?
*)

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.IOUtils, System.Zip, System.DateUtils, System.Hash,
  UniFlow.Workflow.Definition,
  DeepBase.Exceptions;

type
  // ============================================================================
  // 导出格式
  // ============================================================================
  
  TExportFormat = (
    efJSON,           // 单个 JSON 文件
    efJSONPretty,     // 格式�?JSON
    efPackage,        // 打包格式 (多文�?ZIP)
    efYAML            // YAML 格式 (需要转�?
  );
  
  // ============================================================================
  // 导入冲突策略
  // ============================================================================
  
  TConflictStrategy = (
    csSkip,           // 跳过已存�?
    csOverwrite,      // 覆盖
    csRename,         // 重命�?
    csVersion,        // 创建新版�?
    csAsk             // 询问用户
  );
  
  // ============================================================================
  // 导入结果状�?
  // ============================================================================
  
  TImportStatus = (
    isSuccess,        // 成功
    isSkipped,        // 跳过
    isOverwritten,    // 已覆�?
    isRenamed,        // 已重命名
    isVersioned,      // 创建新版�?
    isFailed          // 失败
  );
  
  // ============================================================================
  // 导出选项
  // ============================================================================
  
  TExportOptions = record
    Format: TExportFormat;
    IncludeMetadata: Boolean;       // 包含元数�?
    IncludeVersionHistory: Boolean; // 包含版本历史
    IncludeStats: Boolean;          // 包含统计信息
    IncludeDependencies: Boolean;   // 包含依赖的子工作�?
    CompressOutput: Boolean;        // 压缩输出
    PrettyPrint: Boolean;           // 格式化输�?
    
    class function Default: TExportOptions; static;
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TExportOptions; static;
  end;
  
  // ============================================================================
  // 导入选项
  // ============================================================================
  
  TImportOptions = record
    ConflictStrategy: TConflictStrategy;
    ValidateBeforeImport: Boolean;  // 导入前验�?
    PreserveIds: Boolean;           // 保留�?ID
    ImportVersions: Boolean;        // 导入版本历史
    DryRun: Boolean;               // 试运�?(不实际导�?
    TargetTenantId: string;        // 目标租户 (跨租户迁�?
    
    class function Default: TImportOptions; static;
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TImportOptions; static;
  end;
  
  // ============================================================================
  // 导出结果
  // ============================================================================
  
  TExportResult = class
  private
    FSuccess: Boolean;
    FWorkflowIds: TList<string>;
    FOutputPath: string;
    FOutputSize: Int64;
    FExportedAt: TDateTime;
    FChecksum: string;
    FErrorMessage: string;
    FWarnings: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    
    property Success: Boolean read FSuccess write FSuccess;
    property WorkflowIds: TList<string> read FWorkflowIds;
    property OutputPath: string read FOutputPath write FOutputPath;
    property OutputSize: Int64 read FOutputSize write FOutputSize;
    property ExportedAt: TDateTime read FExportedAt write FExportedAt;
    property Checksum: string read FChecksum write FChecksum;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property Warnings: TStringList read FWarnings;
  end;
  
  // ============================================================================
  // 导入项结�?
  // ============================================================================
  
  TImportItemResult = record
    WorkflowId: string;
    WorkflowName: string;
    Status: TImportStatus;
    NewId: string;          // �?ID (如果重命�?
    Message: string;
    
    function ToJSON: TJSONObject;
  end;
  
  // ============================================================================
  // 导入结果
  // ============================================================================
  
  TImportResult = class
  private
    FSuccess: Boolean;
    FTotalCount: Integer;
    FSuccessCount: Integer;
    FSkippedCount: Integer;
    FFailedCount: Integer;
    FItems: TList<TImportItemResult>;
    FImportedAt: TDateTime;
    FErrorMessage: string;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddItem(const AItem: TImportItemResult);
    function ToJSON: TJSONObject;
    
    property Success: Boolean read FSuccess write FSuccess;
    property TotalCount: Integer read FTotalCount;
    property SuccessCount: Integer read FSuccessCount;
    property SkippedCount: Integer read FSkippedCount;
    property FailedCount: Integer read FFailedCount;
    property Items: TList<TImportItemResult> read FItems;
    property ImportedAt: TDateTime read FImportedAt write FImportedAt;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
  end;
  
  // ============================================================================
  // 导出�?
  // ============================================================================
  
  TExportPackage = class
  private
    FVersion: string;
    FExportedAt: TDateTime;
    FExportedBy: string;
    FSourceSystem: string;
    FWorkflows: TObjectList<TWorkflowDefinition>;
    FDependencies: TDictionary<string, TWorkflowDefinition>;
    FMetadata: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddWorkflow(AWorkflow: TWorkflowDefinition);
    procedure AddDependency(const AId: string; AWorkflow: TWorkflowDefinition);
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJson: TJSONObject): TExportPackage; static;
    
    function SaveToFile(const APath: string; ACompressed: Boolean = False): Boolean;
    class function LoadFromFile(const APath: string): TExportPackage; static;
    
    property Version: string read FVersion write FVersion;
    property ExportedAt: TDateTime read FExportedAt write FExportedAt;
    property ExportedBy: string read FExportedBy write FExportedBy;
    property SourceSystem: string read FSourceSystem write FSourceSystem;
    property Workflows: TObjectList<TWorkflowDefinition> read FWorkflows;
    property Dependencies: TDictionary<string, TWorkflowDefinition> read FDependencies;
    property Metadata: TJSONObject read FMetadata write FMetadata;
  end;
  
  // ============================================================================
  // 验证结果
  // ============================================================================
  
  TValidationIssue = record
    WorkflowId: string;
    Severity: string;  // error, warning, info
    Code: string;
    Message: string;
    Path: string;
  end;
  
  TValidationResult = class
  private
    FValid: Boolean;
    FIssues: TList<TValidationIssue>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddIssue(const AIssue: TValidationIssue);
    function ToJSON: TJSONObject;
    
    property Valid: Boolean read FValid write FValid;
    property Issues: TList<TValidationIssue> read FIssues;
  end;
  
  // ============================================================================
  // 工作流导入导出服�?
  // ============================================================================
  
  IWorkflowStore = interface
    ['{A1B2C3D4-E5F6-4789-8012-3456789ABCDE}']
    function GetWorkflow(const AId: string): TWorkflowDefinition;
    function SaveWorkflow(AWorkflow: TWorkflowDefinition): Boolean;
    function WorkflowExists(const AId: string): Boolean;
    function GetAllWorkflows: TList<TWorkflowDefinition>;
  end;
  
  TWorkflowImportExport = class
  private
    FStore: IWorkflowStore;
    
    function ValidateWorkflow(AWorkflow: TWorkflowDefinition): TValidationResult;
    function GenerateNewId(const AOriginalId: string): string;
    function CalculateChecksum(const AContent: string): string;
    procedure CollectDependencies(AWorkflow: TWorkflowDefinition; 
      ADeps: TDictionary<string, TWorkflowDefinition>);
  public
    constructor Create(AStore: IWorkflowStore);
    destructor Destroy; override;
    
    /// <summary>导出单个工作�?/summary>
    function ExportWorkflow(const AWorkflowId: string; 
      const AOptions: TExportOptions): TExportResult;
    
    /// <summary>批量导出</summary>
    function ExportWorkflows(const AWorkflowIds: TArray<string>;
      const AOptions: TExportOptions): TExportResult;
    
    /// <summary>导出到文�?/summary>
    function ExportToFile(const AWorkflowId, APath: string;
      const AOptions: TExportOptions): TExportResult;
    
    /// <summary>批量导出到文�?/summary>
    function ExportToPackage(const AWorkflowIds: TArray<string>;
      const APath: string; const AOptions: TExportOptions): TExportResult;
    
    /// <summary>导入单个工作�?/summary>
    function ImportWorkflow(const AJson: TJSONObject;
      const AOptions: TImportOptions): TImportResult;
    
    /// <summary>�?JSON 字符串导�?/summary>
    function ImportFromJSON(const AJsonStr: string;
      const AOptions: TImportOptions): TImportResult;
    
    /// <summary>从文件导�?/summary>
    function ImportFromFile(const APath: string;
      const AOptions: TImportOptions): TImportResult;
    
    /// <summary>从导出包导入</summary>
    function ImportFromPackage(const APath: string;
      const AOptions: TImportOptions): TImportResult;
    
    /// <summary>验证导入数据</summary>
    function ValidateImport(const AJson: TJSONObject): TValidationResult;
    
    /// <summary>预览导入 (不实际执�?</summary>
    function PreviewImport(const AJson: TJSONObject): TImportResult;
    
    property Store: IWorkflowStore read FStore;
  end;
  
  // ============================================================================
  // 辅助函数
  // ============================================================================
  
function ExportFormatToString(AFormat: TExportFormat): string;
function StringToExportFormat(const AStr: string): TExportFormat;
function ConflictStrategyToString(AStrategy: TConflictStrategy): string;
function StringToConflictStrategy(const AStr: string): TConflictStrategy;
function ImportStatusToString(AStatus: TImportStatus): string;

implementation

uses
  System.NetEncoding;

const
  PACKAGE_VERSION = '1.0';
  PACKAGE_MAGIC = 'UNIFLOW';

// ============================================================================
// TExportOptions Implementation
// ============================================================================

class function TExportOptions.Default: TExportOptions;
begin
  Result.Format := efJSONPretty;
  Result.IncludeMetadata := True;
  Result.IncludeVersionHistory := False;
  Result.IncludeStats := False;
  Result.IncludeDependencies := True;
  Result.CompressOutput := False;
  Result.PrettyPrint := True;
end;

function TExportOptions.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', ExportFormatToString(Format));
  Result.AddPair('include_metadata', TJSONBool.Create(IncludeMetadata));
  Result.AddPair('include_version_hiDeepStory', TJSONBool.Create(IncludeVersionHistory));
  Result.AddPair('include_stats', TJSONBool.Create(IncludeStats));
  Result.AddPair('include_dependencies', TJSONBool.Create(IncludeDependencies));
  Result.AddPair('compress_output', TJSONBool.Create(CompressOutput));
  Result.AddPair('pretty_print', TJSONBool.Create(PrettyPrint));
end;

class function TExportOptions.FromJSON(AJson: TJSONObject): TExportOptions;
begin
  Result := Default;
  if AJson = nil then Exit;
  
  Result.Format := StringToExportFormat(AJson.GetValue<string>('format', 'json_pretty'));
  Result.IncludeMetadata := AJson.GetValue<Boolean>('include_metadata', True);
  Result.IncludeVersionHistory := AJson.GetValue<Boolean>('include_version_hiDeepStory', False);
  Result.IncludeStats := AJson.GetValue<Boolean>('include_stats', False);
  Result.IncludeDependencies := AJson.GetValue<Boolean>('include_dependencies', True);
  Result.CompressOutput := AJson.GetValue<Boolean>('compress_output', False);
  Result.PrettyPrint := AJson.GetValue<Boolean>('pretty_print', True);
end;

// ============================================================================
// TImportOptions Implementation
// ============================================================================

class function TImportOptions.Default: TImportOptions;
begin
  Result.ConflictStrategy := csSkip;
  Result.ValidateBeforeImport := True;
  Result.PreserveIds := False;
  Result.ImportVersions := False;
  Result.DryRun := False;
  Result.TargetTenantId := '';
end;

function TImportOptions.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('conflict_strategy', ConflictStrategyToString(ConflictStrategy));
  Result.AddPair('validate_before_import', TJSONBool.Create(ValidateBeforeImport));
  Result.AddPair('preserve_ids', TJSONBool.Create(PreserveIds));
  Result.AddPair('import_versions', TJSONBool.Create(ImportVersions));
  Result.AddPair('dry_run', TJSONBool.Create(DryRun));
  Result.AddPair('target_tenant_id', TargetTenantId);
end;

class function TImportOptions.FromJSON(AJson: TJSONObject): TImportOptions;
begin
  Result := Default;
  if AJson = nil then Exit;
  
  Result.ConflictStrategy := StringToConflictStrategy(AJson.GetValue<string>('conflict_strategy', 'skip'));
  Result.ValidateBeforeImport := AJson.GetValue<Boolean>('validate_before_import', True);
  Result.PreserveIds := AJson.GetValue<Boolean>('preserve_ids', False);
  Result.ImportVersions := AJson.GetValue<Boolean>('import_versions', False);
  Result.DryRun := AJson.GetValue<Boolean>('dry_run', False);
  Result.TargetTenantId := AJson.GetValue<string>('target_tenant_id', '');
end;

// ============================================================================
// TExportResult Implementation
// ============================================================================

constructor TExportResult.Create;
begin
  inherited Create;
  FWorkflowIds := TList<string>.Create;
  FWarnings := TStringList.Create;
  FExportedAt := Now;
end;

destructor TExportResult.Destroy;
begin
  FWarnings.Free;
  FWorkflowIds.Free;
  inherited;
end;

function TExportResult.ToJSON: TJSONObject;
var
  LIdsArray: TJSONArray;
  LWarningsArray: TJSONArray;
  LId: string;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(FSuccess));
  Result.AddPair('output_path', FOutputPath);
  Result.AddPair('output_size', TJSONNumber.Create(FOutputSize));
  Result.AddPair('exported_at', DateTimeToStr(FExportedAt));
  Result.AddPair('checksum', FChecksum);
  
  if not FSuccess then
    Result.AddPair('error', FErrorMessage);
  
  LIdsArray := TJSONArray.Create;
  for LId in FWorkflowIds do
    LIdsArray.Add(LId);
  Result.AddPair('workflow_ids', LIdsArray);
  
  if FWarnings.Count > 0 then
  begin
    LWarningsArray := TJSONArray.Create;
    for I := 0 to FWarnings.Count - 1 do
      LWarningsArray.Add(FWarnings[I]);
    Result.AddPair('warnings', LWarningsArray);
  end;
end;

// ============================================================================
// TImportItemResult Implementation
// ============================================================================

function TImportItemResult.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('workflow_id', WorkflowId);
  Result.AddPair('workflow_name', WorkflowName);
  Result.AddPair('status', ImportStatusToString(Status));
  if not NewId.IsEmpty then
    Result.AddPair('new_id', NewId);
  if not Message.IsEmpty then
    Result.AddPair('message', Message);
end;

// ============================================================================
// TImportResult Implementation
// ============================================================================

constructor TImportResult.Create;
begin
  inherited Create;
  FItems := TList<TImportItemResult>.Create;
  FImportedAt := Now;
end;

destructor TImportResult.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TImportResult.AddItem(const AItem: TImportItemResult);
begin
  FItems.Add(AItem);
  Inc(FTotalCount);
  
  case AItem.Status of
    isSuccess, isOverwritten, isRenamed, isVersioned:
      Inc(FSuccessCount);
    isSkipped:
      Inc(FSkippedCount);
    isFailed:
      Inc(FFailedCount);
  end;
end;

function TImportResult.ToJSON: TJSONObject;
var
  LItemsArray: TJSONArray;
  LItem: TImportItemResult;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(FSuccess));
  Result.AddPair('total_count', TJSONNumber.Create(FTotalCount));
  Result.AddPair('success_count', TJSONNumber.Create(FSuccessCount));
  Result.AddPair('skipped_count', TJSONNumber.Create(FSkippedCount));
  Result.AddPair('failed_count', TJSONNumber.Create(FFailedCount));
  Result.AddPair('imported_at', DateTimeToStr(FImportedAt));
  
  if not FSuccess and not FErrorMessage.IsEmpty then
    Result.AddPair('error', FErrorMessage);
  
  LItemsArray := TJSONArray.Create;
  for LItem in FItems do
    LItemsArray.Add(LItem.ToJSON);
  Result.AddPair('items', LItemsArray);
end;

// ============================================================================
// TExportPackage Implementation
// ============================================================================

constructor TExportPackage.Create;
begin
  inherited Create;
  FVersion := PACKAGE_VERSION;
  FExportedAt := Now;
  FWorkflows := TObjectList<TWorkflowDefinition>.Create(False);
  FDependencies := TDictionary<string, TWorkflowDefinition>.Create;
end;

destructor TExportPackage.Destroy;
begin
  FDependencies.Free;
  FWorkflows.Free;
  FMetadata.Free;
  inherited;
end;

procedure TExportPackage.AddWorkflow(AWorkflow: TWorkflowDefinition);
begin
  FWorkflows.Add(AWorkflow);
end;

procedure TExportPackage.AddDependency(const AId: string; AWorkflow: TWorkflowDefinition);
begin
  if not FDependencies.ContainsKey(AId) then
    FDependencies.Add(AId, AWorkflow);
end;

function TExportPackage.ToJSON: TJSONObject;
var
  LWorkflowsArray, LDepsArray: TJSONArray;
  LWorkflow: TWorkflowDefinition;
  LPair: TPair<string, TWorkflowDefinition>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('magic', PACKAGE_MAGIC);
  Result.AddPair('version', FVersion);
  Result.AddPair('exported_at', DateTimeToStr(FExportedAt));
  Result.AddPair('exported_by', FExportedBy);
  Result.AddPair('source_system', FSourceSystem);
  
  LWorkflowsArray := TJSONArray.Create;
  for LWorkflow in FWorkflows do
    LWorkflowsArray.Add(LWorkflow.ToJSON);
  Result.AddPair('workflows', LWorkflowsArray);
  
  LDepsArray := TJSONArray.Create;
  for LPair in FDependencies do
    LDepsArray.Add(LPair.Value.ToJSON);
  Result.AddPair('dependencies', LDepsArray);
  
  if Assigned(FMetadata) then
    Result.AddPair('metadata', FMetadata.Clone as TJSONObject);
end;

class function TExportPackage.FromJSON(AJson: TJSONObject): TExportPackage;
var
  LWorkflowsArray, LDepsArray: TJSONArray;
  I: Integer;
  LWorkflow: TWorkflowDefinition;
begin
  Result := TExportPackage.Create;
  
  // 验证 magic
  if AJson.GetValue<string>('magic', '') <> PACKAGE_MAGIC then
  begin
    Result.Free;
    raise EOperationException.Create('Invalid package format');
  end;
  
  Result.FVersion := AJson.GetValue<string>('version', '1.0');
  Result.FExportedBy := AJson.GetValue<string>('exported_by', '');
  Result.FSourceSystem := AJson.GetValue<string>('source_system', '');
  
  if AJson.TryGetValue<TJSONArray>('workflows', LWorkflowsArray) then
  begin
    for I := 0 to LWorkflowsArray.Count - 1 do
    begin
      LWorkflow := TWorkflowDefinition.Create;
      LWorkflow.LoadFromJSON(LWorkflowsArray.Items[I] as TJSONObject);
      Result.FWorkflows.Add(LWorkflow);
    end;
  end;
  
  if AJson.TryGetValue<TJSONArray>('dependencies', LDepsArray) then
  begin
    for I := 0 to LDepsArray.Count - 1 do
    begin
      LWorkflow := TWorkflowDefinition.Create;
      LWorkflow.LoadFromJSON(LDepsArray.Items[I] as TJSONObject);
      Result.FDependencies.Add(LWorkflow.Id, LWorkflow);
    end;
  end;
end;

function TExportPackage.SaveToFile(const APath: string; ACompressed: Boolean): Boolean;
var
  LJson: TJSONObject;
  LContent: string;
  LBytes: TBytes;
begin
  Result := False;
  LJson := ToJSON;
  try
    LContent := LJson.ToJSON;
    
    if ACompressed then
    begin
      // 简单压�?(实际应使�?ZIP)
      LBytes := TEncoding.UTF8.GetBytes(LContent);
      TFile.WriteAllBytes(APath, LBytes);
    end
    else
    begin
      TFile.WriteAllText(APath, LContent, TEncoding.UTF8);
    end;
    
    Result := True;
  finally
    LJson.Free;
  end;
end;

class function TExportPackage.LoadFromFile(const APath: string): TExportPackage;
var
  LContent: string;
  LJson: TJSONObject;
begin
  LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
  LJson := TJSONObject.ParseJSONValue(LContent) as TJSONObject;
  try
    Result := FromJSON(LJson);
  finally
    LJson.Free;
  end;
end;

// ============================================================================
// TValidationResult Implementation
// ============================================================================

constructor TValidationResult.Create;
begin
  inherited Create;
  FIssues := TList<TValidationIssue>.Create;
  FValid := True;
end;

destructor TValidationResult.Destroy;
begin
  FIssues.Free;
  inherited;
end;

procedure TValidationResult.AddIssue(const AIssue: TValidationIssue);
begin
  FIssues.Add(AIssue);
  if AIssue.Severity = 'error' then
    FValid := False;
end;

function TValidationResult.ToJSON: TJSONObject;
var
  LIssuesArray: TJSONArray;
  LIssue: TValidationIssue;
  LIssueObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('valid', TJSONBool.Create(FValid));
  Result.AddPair('issue_count', TJSONNumber.Create(FIssues.Count));
  
  LIssuesArray := TJSONArray.Create;
  for LIssue in FIssues do
  begin
    LIssueObj := TJSONObject.Create;
    LIssueObj.AddPair('workflow_id', LIssue.WorkflowId);
    LIssueObj.AddPair('severity', LIssue.Severity);
    LIssueObj.AddPair('code', LIssue.Code);
    LIssueObj.AddPair('message', LIssue.Message);
    LIssueObj.AddPair('path', LIssue.Path);
    LIssuesArray.Add(LIssueObj);
  end;
  Result.AddPair('issues', LIssuesArray);
end;

// ============================================================================
// TWorkflowImportExport Implementation
// ============================================================================

constructor TWorkflowImportExport.Create(AStore: IWorkflowStore);
begin
  inherited Create;
  FStore := AStore;
end;

destructor TWorkflowImportExport.Destroy;
begin
  FStore := nil;
  inherited;
end;

function TWorkflowImportExport.ValidateWorkflow(AWorkflow: TWorkflowDefinition): TValidationResult;
var
  LIssue: TValidationIssue;
begin
  Result := TValidationResult.Create;
  
  // 基本验证
  if AWorkflow.Id.IsEmpty then
  begin
    LIssue.WorkflowId := '';
    LIssue.Severity := 'error';
    LIssue.Code := 'MISSING_ID';
    LIssue.Message := 'FlowDefinition ID is required';
    LIssue.Path := 'id';
    Result.AddIssue(LIssue);
  end;
  
  if AWorkflow.Name.IsEmpty then
  begin
    LIssue.WorkflowId := AWorkflow.Id;
    LIssue.Severity := 'warning';
    LIssue.Code := 'MISSING_NAME';
    LIssue.Message := 'FlowDefinition name is empty';
    LIssue.Path := 'name';
    Result.AddIssue(LIssue);
  end;
  
  if AWorkflow.Steps.Count = 0 then
  begin
    LIssue.WorkflowId := AWorkflow.Id;
    LIssue.Severity := 'warning';
    LIssue.Code := 'NO_STEPS';
    LIssue.Message := 'FlowDefinition has no steps';
    LIssue.Path := 'steps';
    Result.AddIssue(LIssue);
  end;
end;

function TWorkflowImportExport.GenerateNewId(const AOriginalId: string): string;
var
  LGUID: TGUID;
begin
  CreateGUID(LGUID);
  Result := AOriginalId + '_' + FormatDateTime('yyyymmddhhnnss', Now);
end;

function TWorkflowImportExport.CalculateChecksum(const AContent: string): string;
begin
  Result := THashSHA2.GetHashString(AContent);
end;

procedure TWorkflowImportExport.CollectDependencies(AWorkflow: TWorkflowDefinition;
  ADeps: TDictionary<string, TWorkflowDefinition>);
var
  LStep: TWorkflowStep;
  LSubId: string;
  LSubWorkflow: TWorkflowDefinition;
begin
  for LStep in AWorkflow.Steps do
  begin
    if LStep.StepType = stSubWorkflow then
    begin
      LSubId := LStep.SubWorkflowId;
      if not LSubId.IsEmpty and not ADeps.ContainsKey(LSubId) then
      begin
        LSubWorkflow := FStore.GetWorkflow(LSubId);
        if Assigned(LSubWorkflow) then
        begin
          ADeps.Add(LSubId, LSubWorkflow);
          CollectDependencies(LSubWorkflow, ADeps); // 递归
        end;
      end;
    end;
  end;
end;

function TWorkflowImportExport.ExportWorkflow(const AWorkflowId: string;
  const AOptions: TExportOptions): TExportResult;
var
  LWorkflow: TWorkflowDefinition;
  LJson: TJSONObject;
begin
  Result := TExportResult.Create;
  
  LWorkflow := FStore.GetWorkflow(AWorkflowId);
  if not Assigned(LWorkflow) then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'FlowDefinition not found: ' + AWorkflowId;
    Exit;
  end;
  
  try
    LJson := LWorkflow.ToJSON;
    try
      Result.Success := True;
      Result.WorkflowIds.Add(AWorkflowId);
      Result.Checksum := CalculateChecksum(LJson.ToJSON);
      Result.OutputSize := Length(LJson.ToJSON);
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

function TWorkflowImportExport.ExportWorkflows(const AWorkflowIds: TArray<string>;
  const AOptions: TExportOptions): TExportResult;
var
  LId: string;
  LWorkflow: TWorkflowDefinition;
  LPackage: TExportPackage;
  LDeps: TDictionary<string, TWorkflowDefinition>;
begin
  Result := TExportResult.Create;
  LPackage := TExportPackage.Create;
  LDeps := TDictionary<string, TWorkflowDefinition>.Create;
  try
    for LId in AWorkflowIds do
    begin
      LWorkflow := FStore.GetWorkflow(LId);
      if Assigned(LWorkflow) then
      begin
        LPackage.AddWorkflow(LWorkflow);
        Result.WorkflowIds.Add(LId);
        
        if AOptions.IncludeDependencies then
          CollectDependencies(LWorkflow, LDeps);
      end
      else
        Result.Warnings.Add('FlowDefinition not found: ' + LId);
    end;
    
    // 添加依赖
    for var LPair in LDeps do
      LPackage.AddDependency(LPair.Key, LPair.Value);
    
    Result.Success := Result.WorkflowIds.Count > 0;
  finally
    LDeps.Free;
    LPackage.Free;
  end;
end;

function TWorkflowImportExport.ExportToFile(const AWorkflowId, APath: string;
  const AOptions: TExportOptions): TExportResult;
var
  LWorkflow: TWorkflowDefinition;
  LJson: TJSONObject;
  LContent: string;
begin
  Result := TExportResult.Create;
  
  LWorkflow := FStore.GetWorkflow(AWorkflowId);
  if not Assigned(LWorkflow) then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'FlowDefinition not found';
    Exit;
  end;
  
  try
    LJson := LWorkflow.ToJSON;
    try
      if AOptions.PrettyPrint then
        LContent := LJson.Format(2)
      else
        LContent := LJson.ToJSON;
      
      TFile.WriteAllText(APath, LContent, TEncoding.UTF8);
      
      Result.Success := True;
      Result.WorkflowIds.Add(AWorkflowId);
      Result.OutputPath := APath;
      Result.OutputSize := TFile.GetSize(APath);
      Result.Checksum := CalculateChecksum(LContent);
    finally
      LJson.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

function TWorkflowImportExport.ExportToPackage(const AWorkflowIds: TArray<string>;
  const APath: string; const AOptions: TExportOptions): TExportResult;
var
  LPackage: TExportPackage;
  LId: string;
  LWorkflow: TWorkflowDefinition;
  LDeps: TDictionary<string, TWorkflowDefinition>;
begin
  Result := TExportResult.Create;
  LPackage := TExportPackage.Create;
  LDeps := TDictionary<string, TWorkflowDefinition>.Create;
  try
    LPackage.ExportedBy := 'UniFlow';
    LPackage.SourceSystem := 'UniFlow v1.0';
    
    for LId in AWorkflowIds do
    begin
      LWorkflow := FStore.GetWorkflow(LId);
      if Assigned(LWorkflow) then
      begin
        LPackage.AddWorkflow(LWorkflow);
        Result.WorkflowIds.Add(LId);
        
        if AOptions.IncludeDependencies then
          CollectDependencies(LWorkflow, LDeps);
      end;
    end;
    
    for var LPair in LDeps do
      LPackage.AddDependency(LPair.Key, LPair.Value);
    
    if LPackage.SaveToFile(APath, AOptions.CompressOutput) then
    begin
      Result.Success := True;
      Result.OutputPath := APath;
      Result.OutputSize := TFile.GetSize(APath);
    end
    else
    begin
      Result.Success := False;
      Result.ErrorMessage := 'Failed to save package';
    end;
  finally
    LDeps.Free;
    LPackage.Free;
  end;
end;

function TWorkflowImportExport.ImportWorkflow(const AJson: TJSONObject;
  const AOptions: TImportOptions): TImportResult;
var
  LWorkflow: TWorkflowDefinition;
  LValidation: TValidationResult;
  LItem: TImportItemResult;
begin
  Result := TImportResult.Create;
  
  try
    LWorkflow := TWorkflowDefinition.Create;
    LWorkflow.LoadFromJSON(AJson);
    try
      // 验证
      if AOptions.ValidateBeforeImport then
      begin
        LValidation := ValidateWorkflow(LWorkflow);
        try
          if not LValidation.Valid then
          begin
            LItem.WorkflowId := LWorkflow.Id;
            LItem.WorkflowName := LWorkflow.Name;
            LItem.Status := isFailed;
            LItem.Message := 'Validation failed';
            Result.AddItem(LItem);
            Result.Success := False;
            Exit;
          end;
        finally
          LValidation.Free;
        end;
      end;
      
      // 检查冲�?
      if FStore.WorkflowExists(LWorkflow.Id) then
      begin
        case AOptions.ConflictStrategy of
          csSkip:
          begin
            LItem.WorkflowId := LWorkflow.Id;
            LItem.WorkflowName := LWorkflow.Name;
            LItem.Status := isSkipped;
            LItem.Message := 'Already exists';
            Result.AddItem(LItem);
            Result.Success := True;
            Exit;
          end;
          
          csOverwrite:
          begin
            if not AOptions.DryRun then
              FStore.SaveWorkflow(LWorkflow);
            LItem.WorkflowId := LWorkflow.Id;
            LItem.WorkflowName := LWorkflow.Name;
            LItem.Status := isOverwritten;
            Result.AddItem(LItem);
          end;
          
          csRename:
          begin
            LItem.WorkflowId := LWorkflow.Id;
            LItem.NewId := GenerateNewId(LWorkflow.Id);
            LWorkflow.Id := LItem.NewId;
            if not AOptions.DryRun then
              FStore.SaveWorkflow(LWorkflow);
            LItem.WorkflowName := LWorkflow.Name;
            LItem.Status := isRenamed;
            Result.AddItem(LItem);
          end;
        end;
      end
      else
      begin
        if not AOptions.DryRun then
          FStore.SaveWorkflow(LWorkflow);
        LItem.WorkflowId := LWorkflow.Id;
        LItem.WorkflowName := LWorkflow.Name;
        LItem.Status := isSuccess;
        Result.AddItem(LItem);
      end;
      
      Result.Success := True;
    finally
      LWorkflow.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

function TWorkflowImportExport.ImportFromJSON(const AJsonStr: string;
  const AOptions: TImportOptions): TImportResult;
var
  LJson: TJSONValue;
begin
  LJson := TJSONObject.ParseJSONValue(AJsonStr);
  try
    if LJson is TJSONObject then
      Result := ImportWorkflow(TJSONObject(LJson), AOptions)
    else
    begin
      Result := TImportResult.Create;
      Result.Success := False;
      Result.ErrorMessage := 'Invalid JSON format';
    end;
  finally
    LJson.Free;
  end;
end;

function TWorkflowImportExport.ImportFromFile(const APath: string;
  const AOptions: TImportOptions): TImportResult;
var
  LContent: string;
begin
  if not TFile.Exists(APath) then
  begin
    Result := TImportResult.Create;
    Result.Success := False;
    Result.ErrorMessage := 'File not found: ' + APath;
    Exit;
  end;
  
  LContent := TFile.ReadAllText(APath, TEncoding.UTF8);
  Result := ImportFromJSON(LContent, AOptions);
end;

function TWorkflowImportExport.ImportFromPackage(const APath: string;
  const AOptions: TImportOptions): TImportResult;
var
  LPackage: TExportPackage;
  LWorkflow: TWorkflowDefinition;
  LJson: TJSONObject;
  LSubResult: TImportResult;
begin
  Result := TImportResult.Create;
  
  if not TFile.Exists(APath) then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'Package file not found';
    Exit;
  end;
  
  try
    LPackage := TExportPackage.LoadFromFile(APath);
    try
      // 先导入依�?
      for var LPair in LPackage.Dependencies do
      begin
        LJson := LPair.Value.ToJSON;
        try
          LSubResult := ImportWorkflow(LJson, AOptions);
          try
            for var LItem in LSubResult.Items do
              Result.AddItem(LItem);
          finally
            LSubResult.Free;
          end;
        finally
          LJson.Free;
        end;
      end;
      
      // 再导入主工作�?
      for LWorkflow in LPackage.Workflows do
      begin
        LJson := LWorkflow.ToJSON;
        try
          LSubResult := ImportWorkflow(LJson, AOptions);
          try
            for var LItem in LSubResult.Items do
              Result.AddItem(LItem);
          finally
            LSubResult.Free;
          end;
        finally
          LJson.Free;
        end;
      end;
      
      Result.Success := Result.FailedCount = 0;
    finally
      LPackage.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.ErrorMessage := E.Message;
    end;
  end;
end;

function TWorkflowImportExport.ValidateImport(const AJson: TJSONObject): TValidationResult;
var
  LWorkflow: TWorkflowDefinition;
begin
  try
    LWorkflow := TWorkflowDefinition.Create;
    try
      LWorkflow.LoadFromJSON(AJson);
      Result := ValidateWorkflow(LWorkflow);
    finally
      LWorkflow.Free;
    end;
  except
    on E: Exception do
    begin
      Result := TValidationResult.Create;
      var LIssue: TValidationIssue;
      LIssue.Severity := 'error';
      LIssue.Code := 'PARSE_ERROR';
      LIssue.Message := E.Message;
      Result.AddIssue(LIssue);
    end;
  end;
end;

function TWorkflowImportExport.PreviewImport(const AJson: TJSONObject): TImportResult;
var
  LOptions: TImportOptions;
begin
  LOptions := TImportOptions.Default;
  LOptions.DryRun := True;
  Result := ImportWorkflow(AJson, LOptions);
end;

// ============================================================================
// Helper Functions
// ============================================================================

function ExportFormatToString(AFormat: TExportFormat): string;
begin
  case AFormat of
    efJSON: Result := 'json';
    efJSONPretty: Result := 'json_pretty';
    efPackage: Result := 'package';
    efYAML: Result := 'yaml';
  else
    Result := 'json';
  end;
end;

function StringToExportFormat(const AStr: string): TExportFormat;
begin
  if AStr = 'json' then Result := efJSON
  else if AStr = 'json_pretty' then Result := efJSONPretty
  else if AStr = 'package' then Result := efPackage
  else if AStr = 'yaml' then Result := efYAML
  else Result := efJSON;
end;

function ConflictStrategyToString(AStrategy: TConflictStrategy): string;
begin
  case AStrategy of
    csSkip: Result := 'skip';
    csOverwrite: Result := 'overwrite';
    csRename: Result := 'rename';
    csVersion: Result := 'version';
    csAsk: Result := 'ask';
  else
    Result := 'skip';
  end;
end;

function StringToConflictStrategy(const AStr: string): TConflictStrategy;
begin
  if AStr = 'skip' then Result := csSkip
  else if AStr = 'overwrite' then Result := csOverwrite
  else if AStr = 'rename' then Result := csRename
  else if AStr = 'version' then Result := csVersion
  else if AStr = 'ask' then Result := csAsk
  else Result := csSkip;
end;

function ImportStatusToString(AStatus: TImportStatus): string;
begin
  case AStatus of
    isSuccess: Result := 'success';
    isSkipped: Result := 'skipped';
    isOverwritten: Result := 'overwritten';
    isRenamed: Result := 'renamed';
    isVersioned: Result := 'versioned';
    isFailed: Result := 'failed';
  else
    Result := 'unknown';
  end;
end;

end.
