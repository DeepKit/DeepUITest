unit UniFlow.Workflow.Errors;
(*
  UniFlow Workflow Error Helpers
  ==============================
  UX-001: 提供友好的错误信�?
  
  功能:
  - 错误代码到友好消息的映射
  - 多语言支持 (�?�?
  - 错误诊断建议
  - 错误上下文信�?
  
  错误码格�?
  - 统一格式: {Source}/{Category}/{Specific}
  - 示例: UniFlow/Validation/InvalidWorkflow, Skill/Network/ConnectionFailed
  - 参�? docs/AI编程低熵约束指南.md
*)

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON;

type
  // ============================================================================
  // 错误来源 (Source)
  // ============================================================================
  
  TErrorSource = (
    esSoIs,         // SoIs 代理 (需求澄�?
    esSayDone,      // SayDone 代理 (代码生成)
    esDevDirector,  // DevDirector 代理 (流程协调)
    esUniFlow,      // UniFlow 流程引擎
    esSkill,        // 外部 Skill 插件
    esUser,         // 用户手动操作
    esSystem,       // 系统自动触发
    esExternal      // 外部系统集成
  );
  
  // ============================================================================
  // 错误严重级别
  // ============================================================================
  
  TErrorSeverity = (
    esInfo,       // 信息
    esWarning,    // 警告
    esError,      // 错误
    esCritical    // 严重错误
  );
  
  // ============================================================================
  // 错误分类 (Category)
  // ============================================================================
  
  TErrorCategory = (
    ecValidation,   // 验证错误
    ecTimeout,      // 超时错误
    ecLLM,          // LLM 调用错误
    ecSkill,        // Skill 执行错误
    ecNetwork,      // 网络错误
    ecInternal,     // 内部错误
    ecExternal,     // 外部依赖错误
    ecExecution,    // 执行错误 (v1 兼容)
    ecConfiguration,// 配置错误 (v1 兼容)
    ecPermission,   // 权限错误 (v1 兼容)
    ecResource      // 资源错误 (v1 兼容)
  );
  
  // ============================================================================
  // 语言设置
  // ============================================================================
  
  TErrorLanguage = (elEnglish, elChinese);
  
  // ============================================================================
  // 友好错误信息
  // ============================================================================
  
  // ============================================================================
  // 错误码解析器 - 支持 {Source}/{Category}/{Specific} 格式
  // ============================================================================
  
  TErrorCode = record
    Source: string;         // 来源: SoIs, SayDone, DevDirector, UniFlow, Skill, User, System, External
    Category: string;       // 分类: Validation, Timeout, LLM, Skill, Network, Internal, External
    Specific: string;       // 具体错误: InvalidWorkflow, StepTimeout, ConnectionFailed �?
    
    /// <summary>从字符串解析错误�?/summary>
    class function Parse(const ACode: string): TErrorCode; static;
    
    /// <summary>生成错误码字符串</summary>
    function ToString: string;
    
    /// <summary>是否为新格式错误�?(Source/Category/Specific)</summary>
    class function IsNewFormat(const ACode: string): Boolean; static;
    
    /// <summary>快速创建错误码</summary>
    class function Make(const ASource, ACategory, ASpecific: string): string; static;
  end;
  
  TFriendlyError = record
    Code: string;
    Category: TErrorCategory;
    Severity: TErrorSeverity;
    Title: string;          // 简短标�?
    Message: string;        // 详细消息
    Suggestion: string;     // 建议解决方案
    DocLink: string;        // 文档链接
  end;
  
  // ============================================================================
  // 错误消息助手�?
  // ============================================================================
  
  TErrorHelper = class
  private
    class var FLanguage: TErrorLanguage;
    class var FMessages: TDictionary<string, TFriendlyError>;
    class procedure InitMessages;
    class procedure AddMessage(const ACode: string; ACategory: TErrorCategory;
      ASeverity: TErrorSeverity; const ATitleEn, AMessageEn, ASuggestionEn: string;
      const ATitleZh, AMessageZh, ASuggestionZh: string; const ADocLink: string = '');
  public
    class constructor Create;
    class destructor Destroy;
    
    /// <summary>获取友好错误信息</summary>
    class function GetFriendlyError(const ACode: string): TFriendlyError;
    
    /// <summary>格式化错误消�?(用于显示)</summary>
    class function FormatError(const ACode: string; const AContext: string = ''): string;
    
    /// <summary>格式化错误消�?(用于日志)</summary>
    class function FormatErrorForLog(const ACode, AMessage: string; 
      AContext: TJSONObject = nil): string;
    
    /// <summary>获取错误建议</summary>
    class function GetSuggestion(const ACode: string): string;
    
    /// <summary>获取错误分类</summary>
    class function GetCategory(const ACode: string): TErrorCategory;
    
    /// <summary>获取错误严重级别</summary>
    class function GetSeverity(const ACode: string): TErrorSeverity;
    
    /// <summary>是否为可恢复错误</summary>
    class function IsRecoverable(const ACode: string): Boolean;
    
    /// <summary>是否应该重试</summary>
    class function ShouldRetry(const ACode: string): Boolean;
    
    /// <summary>当前语言设置</summary>
    class property Language: TErrorLanguage read FLanguage write FLanguage;
  end;
  
  // ============================================================================
  // 常用错误代码常量 - 新格�?{Source}/{Category}/{Specific}
  // ============================================================================

const
  // === UniFlow/Validation/* - 验证错误 ===
  ERR_INVALID_WORKFLOW = 'UniFlow/Validation/InvalidWorkflow';
  ERR_INVALID_STEP = 'UniFlow/Validation/InvalidStep';
  ERR_INVALID_EXPRESSION = 'UniFlow/Validation/InvalidExpression';
  ERR_MISSING_REQUIRED = 'UniFlow/Validation/MissingRequired';
  ERR_TYPE_MISMATCH = 'UniFlow/Validation/TypeMismatch';
  
  // === UniFlow/Timeout/* - 超时错误 ===
  ERR_STEP_TIMEOUT = 'UniFlow/Timeout/StepTimeout';
  ERR_CONNECTION_TIMEOUT = 'UniFlow/Timeout/ConnectionTimeout';
  
  // === UniFlow/Execution/* - 执行错误 ===
  ERR_EXECUTION_FAILED = 'UniFlow/Execution/Failed';
  ERR_CANCELLED = 'UniFlow/Execution/Cancelled';
  ERR_PARALLEL_FAILED = 'UniFlow/Execution/ParallelFailed';
  ERR_LOOP_EXCEEDED = 'UniFlow/Execution/LoopExceeded';
  ERR_CONDITION_ERROR = 'UniFlow/Execution/ConditionError';
  
  // === UniFlow/Internal/* - 内部错误 ===
  ERR_CONFIG_INVALID = 'UniFlow/Internal/ConfigInvalid';
  ERR_NO_EXECUTOR = 'UniFlow/Internal/NoExecutor';
  ERR_SUBWORKFLOW_NOT_FOUND = 'UniFlow/Internal/SubworkflowNotFound';
  ERR_INTERNAL = 'UniFlow/Internal/Error';
  ERR_NOT_IMPLEMENTED = 'UniFlow/Internal/NotImplemented';
  ERR_UNKNOWN = 'UniFlow/Internal/Unknown';
  
  // === Skill/* - Skill 相关错误 ===
  ERR_SKILL_NOT_FOUND = 'Skill/Validation/NotFound';
  ERR_SKILL_EXECUTION_FAILED = 'Skill/Execution/Failed';
  
  // === UniFlow/Network/* - 网络错误 ===
  ERR_CONNECTION_FAILED = 'UniFlow/Network/ConnectionFailed';
  ERR_SERVICE_UNAVAILABLE = 'UniFlow/Network/ServiceUnavailable';
  ERR_RATE_LIMITED = 'UniFlow/Network/RateLimited';
  
  // === UniFlow/Permission/* - 权限错误 ===
  ERR_AUTH_REQUIRED = 'UniFlow/Permission/AuthRequired';
  ERR_ACCESS_DENIED = 'UniFlow/Permission/AccessDenied';
  ERR_QUOTA_EXCEEDED = 'UniFlow/Permission/QuotaExceeded';
  ERR_TENANT_INVALID = 'UniFlow/Permission/TenantInvalid';
  
  // === UniFlow/Resource/* - 资源错误 ===
  ERR_RESOURCE_NOT_FOUND = 'UniFlow/Resource/NotFound';
  ERR_RESOURCE_LOCKED = 'UniFlow/Resource/Locked';
  ERR_OUT_OF_MEMORY = 'UniFlow/Resource/OutOfMemory';
  
  // === LLM 相关错误 ===
  ERR_LLM_CALL_FAILED = 'UniFlow/LLM/CallFailed';
  ERR_LLM_TOKEN_EXCEEDED = 'UniFlow/LLM/TokenExceeded';
  ERR_LLM_RATE_LIMITED = 'UniFlow/LLM/RateLimited';
  
  // === 外部系统集成错误 ===
  ERR_EXTERNAL_SERVICE_FAILED = 'External/Execution/ServiceFailed';
  ERR_EXTERNAL_TIMEOUT = 'External/Timeout/ServiceTimeout';
  
  // === UniFlow/Guard/* - Guard 校验错误 (ENTROPY-010) ===
  ERR_GUARD_REQUIRED = 'UniFlow/Guard/Required';
  ERR_GUARD_MIN_LENGTH = 'UniFlow/Guard/MinLength';
  ERR_GUARD_MAX_LENGTH = 'UniFlow/Guard/MaxLength';
  ERR_GUARD_PATTERN = 'UniFlow/Guard/Pattern';
  
  // === UniFlow/Execution/* - 执行错误补充 (ENTROPY-010) ===
  ERR_ALREADY_RUNNING = 'UniFlow/Execution/AlreadyRunning';
  ERR_UNKNOWN_STEP_TYPE = 'UniFlow/Execution/UnknownStepType';
  ERR_ACTION_NOT_HANDLED = 'UniFlow/Execution/ActionNotHandled';
  ERR_INVALID_COLLECTION = 'UniFlow/Execution/InvalidCollection';
  ERR_PARALLEL_ERROR = 'UniFlow/Execution/ParallelError';
  ERR_SUBWORKFLOW_ERROR = 'UniFlow/Execution/SubworkflowError';
  
  // === UniFlow/Internal/* - 未实现错�?===
  ERR_SKILL_NOT_IMPLEMENTED = 'UniFlow/Internal/SkillNotImplemented';
  ERR_LLM_NOT_IMPLEMENTED = 'UniFlow/Internal/LLMNotImplemented';
  ERR_HTTP_NOT_IMPLEMENTED = 'UniFlow/Internal/HTTPNotImplemented';
  ERR_SCRIPT_NOT_IMPLEMENTED = 'UniFlow/Internal/ScriptNotImplemented';
  
  // === v1 兼容 (deprecated, 将在未来版本移除) ===
  ERR_INVALID_WORKFLOW_V1 = 'INVALID_WORKFLOW' deprecated 'Use ERR_INVALID_WORKFLOW';
  ERR_STEP_TIMEOUT_V1 = 'STEP_TIMEOUT' deprecated 'Use ERR_STEP_TIMEOUT';

implementation

{ TErrorCode }

class function TErrorCode.Parse(const ACode: string): TErrorCode;
var
  Parts: TArray<string>;
begin
  Result.Source := '';
  Result.Category := '';
  Result.Specific := '';
  
  if IsNewFormat(ACode) then
  begin
    Parts := ACode.Split(['/']);
    if Length(Parts) >= 1 then Result.Source := Parts[0];
    if Length(Parts) >= 2 then Result.Category := Parts[1];
    if Length(Parts) >= 3 then Result.Specific := Parts[2];
  end
  else
  begin
    // v1 兼容: 旧格式错误码映射到新格式
    Result.Source := 'UniFlow';
    Result.Category := 'Internal';
    Result.Specific := ACode;
  end;
end;

function TErrorCode.ToString: string;
begin
  Result := Source + '/' + Category + '/' + Specific;
end;

class function TErrorCode.IsNewFormat(const ACode: string): Boolean;
var
  SlashCount: Integer;
  I: Integer;
begin
  SlashCount := 0;
  for I := 1 to Length(ACode) do
    if ACode[I] = '/' then
      Inc(SlashCount);
  Result := SlashCount >= 2;
end;

class function TErrorCode.Make(const ASource, ACategory, ASpecific: string): string;
begin
  Result := ASource + '/' + ACategory + '/' + ASpecific;
end;

{ TErrorHelper }

class constructor TErrorHelper.Create;
begin
  FLanguage := elChinese;  // 默认中文
  FMessages := TDictionary<string, TFriendlyError>.Create;
  InitMessages;
end;

class destructor TErrorHelper.Destroy;
begin
  FMessages.Free;
end;

class procedure TErrorHelper.AddMessage(const ACode: string; ACategory: TErrorCategory;
  ASeverity: TErrorSeverity; const ATitleEn, AMessageEn, ASuggestionEn: string;
  const ATitleZh, AMessageZh, ASuggestionZh: string; const ADocLink: string);
var
  Err: TFriendlyError;
begin
  Err.Code := ACode;
  Err.Category := ACategory;
  Err.Severity := ASeverity;
  Err.DocLink := ADocLink;
  
  // 根据语言选择消息
  if FLanguage = elChinese then
  begin
    Err.Title := ATitleZh;
    Err.Message := AMessageZh;
    Err.Suggestion := ASuggestionZh;
  end
  else
  begin
    Err.Title := ATitleEn;
    Err.Message := AMessageEn;
    Err.Suggestion := ASuggestionEn;
  end;
  
  FMessages.AddOrSetValue(ACode, Err);
end;

class procedure TErrorHelper.InitMessages;
begin
  // === 验证错误 ===
  AddMessage(ERR_INVALID_WORKFLOW, ecValidation, esError,
    'Invalid FlowDefinition', 'The FlowDefinition is invalid or corrupted.',
    'Check the FlowDefinition JSON format and required fields.',
    '流程定义无效', '流程定义格式错误或已损坏�?,
    '请检查流程定�?JSON 格式和必填字段�?,
    'docs/workflow-definition.md');
    
  AddMessage(ERR_INVALID_STEP, ecValidation, esError,
    'Invalid Step', 'The step configuration is invalid.',
    'Verify the step type and required properties.',
    '步骤无效', '步骤配置不正确�?,
    '请检查步骤类型和必需属性�?);
    
  AddMessage(ERR_INVALID_EXPRESSION, ecValidation, esError,
    'Invalid Expression', 'The expression syntax is incorrect.',
    'Check the expression format: ${vars.name} or ${steps.id.output}',
    '表达式无�?, '表达式语法错误�?,
    '请检查表达式格式: ${vars.name} �?${steps.id.output}');
    
  AddMessage(ERR_MISSING_REQUIRED, ecValidation, esError,
    'Missing Required Field', 'A required field is missing.',
    'Provide all required fields in the configuration.',
    '缺少必填字段', '配置中缺少必需的字段�?,
    '请提供所有必填字段�?);
    
  AddMessage(ERR_TYPE_MISMATCH, ecValidation, esError,
    'Type Mismatch', 'The value type does not match the expected type.',
    'Check the data type of the value.',
    '类型不匹�?, '值的类型与期望类型不符�?,
    '请检查数据类型是否正确�?);
  
  // === 执行错误 ===
  AddMessage(ERR_EXECUTION_FAILED, ecExecution, esError,
    'Execution Failed', 'The step execution failed.',
    'Check the step configuration and input data.',
    '执行失败', '步骤执行失败�?,
    '请检查步骤配置和输入数据�?);
    
  AddMessage(ERR_STEP_TIMEOUT, ecExecution, esError,
    'Step Timeout', 'The step execution timed out.',
    'Increase timeout or optimize the step operation.',
    '步骤超时', '步骤执行超时�?,
    '请增加超时时间或优化步骤操作�?);
    
  AddMessage(ERR_CANCELLED, ecExecution, esWarning,
    'Execution Cancelled', 'The execution was cancelled by user.',
    'Restart the workflow if needed.',
    '执行已取�?, '执行被用户取消�?,
    '如需继续，请重新启动工作流�?);
    
  AddMessage(ERR_PARALLEL_FAILED, ecExecution, esError,
    'Parallel Execution Failed', 'One or more parallel branches failed.',
    'Check the failed branch for details.',
    '并行执行失败', '一个或多个并行分支执行失败�?,
    '请检查失败分支的详细错误信息�?);
    
  AddMessage(ERR_LOOP_EXCEEDED, ecExecution, esWarning,
    'Loop Limit Exceeded', 'The maximum iteration count was reached.',
    'Check loop condition or increase maxIterations.',
    '循环次数超限', '已达到最大迭代次数�?,
    '请检查循环条件或增加 maxIterations 配置�?);
    
  AddMessage(ERR_CONDITION_ERROR, ecExecution, esError,
    'Condition Evaluation Error', 'Failed to evaluate the condition expression.',
    'Check the condition expression syntax and variable values.',
    '条件求值错�?, '条件表达式求值失败�?,
    '请检查条件表达式语法和变量值�?);
  
  // === 配置错误 ===
  AddMessage(ERR_CONFIG_INVALID, ecConfiguration, esError,
    'Invalid Configuration', 'The configuration is invalid.',
    'Review the configuration settings.',
    '配置无效', '配置设置不正确�?,
    '请检查配置项设置�?);
    
  AddMessage(ERR_SKILL_NOT_FOUND, ecConfiguration, esError,
    'Skill Not Found', 'The specified skill is not registered.',
    'Register the skill or check the skill ID.',
    'Skill 未找�?, '指定�?Skill 未注册�?,
    '请注�?Skill 或检�?Skill ID 是否正确�?,
    'docs/skills-development.md');
    
  AddMessage(ERR_NO_EXECUTOR, ecConfiguration, esError,
    'No Executor', 'No executor registered for this action type.',
    'Register an executor for the action type.',
    '无执行器', '此动作类型没有注册执行器�?,
    '请为该动作类型注册执行器�?);
    
  AddMessage(ERR_SUBWORKFLOW_NOT_FOUND, ecConfiguration, esError,
    'SubWorkflow Not Found', 'The referenced sub-workflow does not exist.',
    'Check the sub-workflow ID and ensure it is deployed.',
    '子工作流未找�?, '引用的子工作流不存在�?,
    '请检查子工作�?ID 并确保已部署�?);
  
  // === 网络错误 ===
  AddMessage(ERR_CONNECTION_FAILED, ecNetwork, esError,
    'Connection Failed', 'Failed to connect to the remote service.',
    'Check network connectivity and service availability.',
    '连接失败', '无法连接到远程服务�?,
    '请检查网络连接和服务可用性�?);
    
  AddMessage(ERR_CONNECTION_TIMEOUT, ecNetwork, esError,
    'Connection Timeout', 'Connection to the service timed out.',
    'Try again or check network conditions.',
    '连接超时', '连接服务超时�?,
    '请稍后重试或检查网络状况�?);
    
  AddMessage(ERR_SERVICE_UNAVAILABLE, ecNetwork, esError,
    'Service Unavailable', 'The service is temporarily unavailable.',
    'Wait and retry, or contact the service provider.',
    '服务不可�?, '服务暂时不可用�?,
    '请等待后重试，或联系服务提供商�?);
    
  AddMessage(ERR_RATE_LIMITED, ecNetwork, esWarning,
    'Rate Limited', 'Request rate limit exceeded.',
    'Slow down request rate or upgrade service plan.',
    '请求频率超限', '请求频率超过限制�?,
    '请降低请求频率或升级服务套餐�?);
  
  // === 权限错误 ===
  AddMessage(ERR_AUTH_REQUIRED, ecPermission, esError,
    'Authentication Required', 'Authentication is required for this operation.',
    'Provide valid credentials.',
    '需要认�?, '此操作需要身份认证�?,
    '请提供有效的认证凭据�?);
    
  AddMessage(ERR_ACCESS_DENIED, ecPermission, esError,
    'Access Denied', 'You do not have permission for this operation.',
    'Contact administrator for access.',
    '访问被拒�?, '您没有执行此操作的权限�?,
    '请联系管理员获取访问权限�?);
    
  AddMessage(ERR_QUOTA_EXCEEDED, ecPermission, esWarning,
    'Quota Exceeded', 'Resource usage quota exceeded.',
    'Wait for quota reset or upgrade your plan.',
    '配额超限', '资源使用配额已超出�?,
    '请等待配额重置或升级套餐�?);
    
  AddMessage(ERR_TENANT_INVALID, ecPermission, esError,
    'Invalid Tenant', 'The tenant ID is invalid or not found.',
    'Check the tenant configuration.',
    '租户无效', '租户 ID 无效或不存在�?,
    '请检查租户配置�?);
  
  // === 资源错误 ===
  AddMessage(ERR_RESOURCE_NOT_FOUND, ecResource, esError,
    'Resource Not Found', 'The requested resource was not found.',
    'Check the resource identifier.',
    '资源未找�?, '请求的资源不存在�?,
    '请检查资源标识符�?);
    
  AddMessage(ERR_RESOURCE_LOCKED, ecResource, esWarning,
    'Resource Locked', 'The resource is locked by another process.',
    'Wait for the resource to be released.',
    '资源被锁�?, '资源被其他进程锁定�?,
    '请等待资源释放�?);
    
  AddMessage(ERR_OUT_OF_MEMORY, ecResource, esCritical,
    'Out of Memory', 'Insufficient memory to complete the operation.',
    'Free up memory or reduce data size.',
    '内存不足', '内存不足，无法完成操作�?,
    '请释放内存或减少数据量�?);
  
  // === 内部错误 ===
  AddMessage(ERR_INTERNAL, ecInternal, esCritical,
    'Internal Error', 'An internal error occurred.',
    'Please report this issue to support.',
    '内部错误', '发生内部错误�?,
    '请向技术支持报告此问题�?);
    
  AddMessage(ERR_NOT_IMPLEMENTED, ecInternal, esError,
    'Not Implemented', 'This feature is not yet implemented.',
    'Check for updates or use alternative approach.',
    '功能未实�?, '此功能尚未实现�?,
    '请关注更新或使用替代方案�?);
    
  AddMessage(ERR_UNKNOWN, ecInternal, esError,
    'Unknown Error', 'An unknown error occurred.',
    'Check logs for details.',
    '未知错误', '发生未知错误�?,
    '请查看日志获取详细信息�?);
end;

class function TErrorHelper.GetFriendlyError(const ACode: string): TFriendlyError;
begin
  if not FMessages.TryGetValue(ACode, Result) then
  begin
    // 返回默认未知错误
    FMessages.TryGetValue(ERR_UNKNOWN, Result);
    Result.Code := ACode;
  end;
end;

class function TErrorHelper.FormatError(const ACode: string; const AContext: string): string;
var
  Err: TFriendlyError;
begin
  Err := GetFriendlyError(ACode);
  
  if FLanguage = elChinese then
  begin
    Result := Format('[%s] %s'#13#10'%s', [ACode, Err.Title, Err.Message]);
    if AContext <> '' then
      Result := Result + #13#10'上下�? ' + AContext;
    if Err.Suggestion <> '' then
      Result := Result + #13#10'建议: ' + Err.Suggestion;
    if Err.DocLink <> '' then
      Result := Result + #13#10'文档: ' + Err.DocLink;
  end
  else
  begin
    Result := Format('[%s] %s'#13#10'%s', [ACode, Err.Title, Err.Message]);
    if AContext <> '' then
      Result := Result + #13#10'Context: ' + AContext;
    if Err.Suggestion <> '' then
      Result := Result + #13#10'Suggestion: ' + Err.Suggestion;
    if Err.DocLink <> '' then
      Result := Result + #13#10'Documentation: ' + Err.DocLink;
  end;
end;

class function TErrorHelper.FormatErrorForLog(const ACode, AMessage: string;
  AContext: TJSONObject): string;
var
  Err: TFriendlyError;
begin
  Err := GetFriendlyError(ACode);
  Result := Format('[%s][%s] %s - %s', [
    DateTimeToStr(Now),
    ACode,
    Err.Title,
    AMessage
  ]);
  if AContext <> nil then
    Result := Result + ' | Context: ' + AContext.ToString;
end;

class function TErrorHelper.GetSuggestion(const ACode: string): string;
begin
  Result := GetFriendlyError(ACode).Suggestion;
end;

class function TErrorHelper.GetCategory(const ACode: string): TErrorCategory;
begin
  Result := GetFriendlyError(ACode).Category;
end;

class function TErrorHelper.GetSeverity(const ACode: string): TErrorSeverity;
begin
  Result := GetFriendlyError(ACode).Severity;
end;

class function TErrorHelper.IsRecoverable(const ACode: string): Boolean;
var
  Cat: TErrorCategory;
begin
  Cat := GetCategory(ACode);
  Result := Cat in [ecValidation, ecConfiguration];
end;

class function TErrorHelper.ShouldRetry(const ACode: string): Boolean;
var
  Cat: TErrorCategory;
begin
  Cat := GetCategory(ACode);
  // 网络错误和部分资源错误可以重�?
  Result := Cat in [ecNetwork, ecResource];
  
  // 特殊情况
  if ACode = ERR_RATE_LIMITED then
    Result := True;
end;

end.
