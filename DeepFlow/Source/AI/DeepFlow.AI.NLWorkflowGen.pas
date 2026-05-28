unit UniFlow.AI.NLWorkflowGen;

{*******************************************************************************
  UniFlow 自然语言工作流生成器
  
  功能:
  - 自然语言意图解析
  - 工作流结构生�?
  - Skill 自动匹配
  - 参数推断
  - 工作流优化建�?
  
  作�? UniFlow Team
  日期: 2024-01
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.RegularExpressions, System.StrUtils;

type
  {$REGION '意图解析类型'}
  
  /// <summary>意图类型</summary>
  TIntentType = (
    itDataProcessing,     // 数据处理
    itAPIIntegration,     // API 集成
    itNotification,       // 通知发�?
    itFileOperation,      // 文件操作
    itDatabaseQuery,      // 数据库查�?
    itScheduledTask,      // 定时任务
    itConditionalLogic,   // 条件逻辑
    itDataTransform,      // 数据转换
    itValidation,         // 数据验证
    itAggregation,        // 数据聚合
    itWebhook,            // Webhook 处理
    itLLMChat,            // LLM 对话
    itUnknown             // 未知
  );
  
  /// <summary>实体类型</summary>
  TEntityType = (
    etDataSource,         // 数据�?
    etDataTarget,         // 数据目标
    etCondition,          // 条件
    etAction,             // 动作
    etParameter,          // 参数
    etTime,               // 时间
    etFormat,             // 格式
    etPerson,             // 人员
    etChannel             // 渠道
  );
  
  /// <summary>识别的实�?/summary>
  TEntity = record
    EntityType: TEntityType;
    Value: string;
    StartPos: Integer;
    EndPos: Integer;
    Confidence: Double;
  end;
  
  /// <summary>解析的意�?/summary>
  TParsedIntent = record
    IntentType: TIntentType;
    Confidence: Double;
    Entities: TArray<TEntity>;
    OriginalText: string;
    NormalizedText: string;
  end;
  
  /// <summary>Skill 匹配结果</summary>
  TSkillMatch = record
    SkillId: string;
    SkillType: string;
    SkillName: string;
    MatchScore: Double;
    RequiredParams: TArray<string>;
    InferredParams: TDictionary<string, string>;
  end;
  
  {$ENDREGION}
  
  {$REGION '工作流生成类�?}
  
  /// <summary>生成的步�?/summary>
  TGeneratedStep = record
    StepId: string;
    StepName: string;
    SkillMatch: TSkillMatch;
    Inputs: TDictionary<string, string>;
    Outputs: TArray<string>;
    Dependencies: TArray<string>;
    Condition: string;
  end;
  
  /// <summary>生成的工作流</summary>
  TGeneratedWorkflow = record
    WorkflowId: string;
    Name: string;
    Description: string;
    Steps: TArray<TGeneratedStep>;
    Variables: TDictionary<string, string>;
    Triggers: TArray<string>;
    Confidence: Double;
    Warnings: TArray<string>;
    Suggestions: TArray<string>;
  end;
  
  /// <summary>生成选项</summary>
  TGenerationOptions = record
    MaxSteps: Integer;
    AllowLLMCalls: Boolean;
    PreferredSkills: TArray<string>;
    ExcludedSkills: TArray<string>;
    OptimizeForPerformance: Boolean;
    AddErrorHandlers: Boolean;
    AddLogging: Boolean;
  end;
  
  {$ENDREGION}
  
  {$REGION '意图解析�?}
  
  /// <summary>意图解析�?/summary>
  TIntentParser = class
  private
    FPatterns: TDictionary<TIntentType, TArray<string>>;
    FEntityPatterns: TDictionary<TEntityType, string>;
    FStopWords: TStringList;
    
    procedure InitializePatterns;
    procedure InitializeEntityPatterns;
    function NormalizeText(const AText: string): string;
    function ExtractEntities(const AText: string): TArray<TEntity>;
    function MatchIntent(const AText: string): TPair<TIntentType, Double>;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Parse(const AText: string): TParsedIntent;
    function ParseMultiple(const AText: string): TArray<TParsedIntent>;
  end;
  
  {$ENDREGION}
  
  {$REGION 'Skill 匹配�?}
  
  /// <summary>Skill 定义</summary>
  TSkillDefinition = record
    SkillId: string;
    SkillType: string;
    Name: string;
    Description: string;
    Keywords: TArray<string>;
    RequiredInputs: TArray<string>;
    OptionalInputs: TArray<string>;
    Outputs: TArray<string>;
    Category: string;
  end;
  
  /// <summary>Skill 匹配�?/summary>
  TSkillMatcher = class
  private
    FSkills: TDictionary<string, TSkillDefinition>;
    FKeywordIndex: TDictionary<string, TList<string>>;
    
    function ComputeMatchScore(const ASkill: TSkillDefinition;
      const AIntent: TParsedIntent): Double;
    function InferParameters(const ASkill: TSkillDefinition;
      const AEntities: TArray<TEntity>): TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure RegisterSkill(const ASkill: TSkillDefinition);
    procedure UnregisterSkill(const ASkillId: string);
    procedure BuildIndex;
    
    function FindMatches(const AIntent: TParsedIntent;
      AMaxResults: Integer = 5): TArray<TSkillMatch>;
    function FindByKeyword(const AKeyword: string): TArray<TSkillDefinition>;
  end;
  
  {$ENDREGION}
  
  {$REGION '工作流生成器'}
  
  /// <summary>工作流生成器</summary>
  TWorkflowGenerator = class
  private
    FIntentParser: TIntentParser;
    FSkillMatcher: TSkillMatcher;
    FStepCounter: Integer;
    
    function GenerateStepId: string;
    function CreateStep(const AIntent: TParsedIntent;
      const ASkillMatch: TSkillMatch): TGeneratedStep;
    function DetermineStepOrder(const ASteps: TArray<TGeneratedStep>): TArray<TGeneratedStep>;
    function InferDependencies(const ASteps: TArray<TGeneratedStep>): TArray<TGeneratedStep>;
    function AddErrorHandlers(const ASteps: TArray<TGeneratedStep>): TArray<TGeneratedStep>;
    function GenerateWorkflowName(const AIntents: TArray<TParsedIntent>): string;
    function GenerateDescription(const AOriginalText: string;
      const AIntents: TArray<TParsedIntent>): string;
  public
    constructor Create;
    destructor Destroy; override;
    
    function Generate(const ANaturalLanguage: string;
      const AOptions: TGenerationOptions): TGeneratedWorkflow;
    function GenerateFromTemplate(const ATemplate: string;
      const AParams: TDictionary<string, string>): TGeneratedWorkflow;
    function ToJSON(const AWorkflow: TGeneratedWorkflow): TJSONObject;
    function Validate(const AWorkflow: TGeneratedWorkflow): TArray<string>;
    
    property IntentParser: TIntentParser read FIntentParser;
    property SkillMatcher: TSkillMatcher read FSkillMatcher;
  end;
  
  {$ENDREGION}
  
  {$REGION 'LLM 增强生成�?}
  
  /// <summary>LLM 生成请求</summary>
  TLLMGenerationRequest = record
    UserPrompt: string;
    SystemPrompt: string;
    AvailableSkills: TArray<TSkillDefinition>;
    Examples: TArray<TPair<string, TJSONObject>>;
    MaxTokens: Integer;
    Temperature: Double;
  end;
  
  /// <summary>LLM 生成响应</summary>
  TLLMGenerationResponse = record
    Success: Boolean;
    WorkflowJSON: TJSONObject;
    Explanation: string;
    Confidence: Double;
    Warnings: TArray<string>;
  end;
  
  /// <summary>LLM 增强生成�?/summary>
  TLLMWorkflowGenerator = class
  private
    FBaseGenerator: TWorkflowGenerator;
    FLLMEndpoint: string;
    FAPIKey: string;
    FModel: string;
    FSystemPrompt: string;
    
    function BuildPrompt(const ARequest: TLLMGenerationRequest): string;
    function ParseLLMResponse(const AResponse: string): TLLMGenerationResponse;
    function CallLLM(const APrompt: string): string;
  public
    constructor Create(const AEndpoint, AAPIKey, AModel: string);
    destructor Destroy; override;
    
    function Generate(const ANaturalLanguage: string): TGeneratedWorkflow;
    function Refine(const AWorkflow: TGeneratedWorkflow;
      const AFeedback: string): TGeneratedWorkflow;
    function Explain(const AWorkflow: TGeneratedWorkflow): string;
    
    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;
  end;
  
  {$ENDREGION}
  
  {$REGION '对话式工作流构建�?}
  
  /// <summary>对话状�?/summary>
  TConversationState = (
    csInitial,
    csGatheringRequirements,
    csConfirmingSteps,
    csConfirmingParameters,
    csReviewing,
    csComplete
  );
  
  /// <summary>对话消息</summary>
  TConversationMessage = record
    Role: string;  // user, assistant, system
    Content: string;
    Timestamp: TDateTime;
  end;
  
  /// <summary>对话式构建器</summary>
  TConversationalBuilder = class
  private
    FGenerator: TLLMWorkflowGenerator;
    FState: TConversationState;
    FHistory: TList<TConversationMessage>;
    FCurrentWorkflow: TGeneratedWorkflow;
    FPendingQuestions: TStringList;
    FUserResponses: TDictionary<string, string>;
    
    function GenerateQuestion: string;
    function ProcessUserInput(const AInput: string): string;
    function ShouldTransitionState: Boolean;
    procedure TransitionState;
  public
    constructor Create(AGenerator: TLLMWorkflowGenerator);
    destructor Destroy; override;
    
    function Start(const AInitialPrompt: string): string;
    function Continue(const AUserInput: string): string;
    function GetCurrentWorkflow: TGeneratedWorkflow;
    function IsComplete: Boolean;
    procedure Reset;
    
    property State: TConversationState read FState;
    property History: TList<TConversationMessage> read FHistory;
  end;
  
  {$ENDREGION}
  
  {$REGION '工作流模�?}
  
  /// <summary>模板变量</summary>
  TTemplateVariable = record
    Name: string;
    Description: string;
    DefaultValue: string;
    Required: Boolean;
    ValidationType: string;
  end;
  
  /// <summary>工作流模�?/summary>
  TWorkflowTemplate = record
    TemplateId: string;
    Name: string;
    Description: string;
    Category: string;
    Variables: TArray<TTemplateVariable>;
    WorkflowJSON: TJSONObject;
    Examples: TArray<string>;
  end;
  
  /// <summary>模板管理�?/summary>
  TTemplateManager = class
  private
    FTemplates: TDictionary<string, TWorkflowTemplate>;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure RegisterTemplate(const ATemplate: TWorkflowTemplate);
    procedure UnregisterTemplate(const ATemplateId: string);
    function GetTemplate(const ATemplateId: string): TWorkflowTemplate;
    function FindTemplates(const AQuery: string): TArray<TWorkflowTemplate>;
    function InstantiateTemplate(const ATemplateId: string;
      const AVariables: TDictionary<string, string>): TJSONObject;
  end;
  
  {$ENDREGION}

implementation

uses
  System.NetEncoding, System.Net.HttpClient, System.Net.URLClient;

{$REGION 'TIntentParser'}

constructor TIntentParser.Create;
begin
  inherited Create;
  FPatterns := TDictionary<TIntentType, TArray<string>>.Create;
  FEntityPatterns := TDictionary<TEntityType, string>.Create;
  FStopWords := TStringList.Create;
  
  InitializePatterns;
  InitializeEntityPatterns;
end;

destructor TIntentParser.Destroy;
begin
  FStopWords.Free;
  FEntityPatterns.Free;
  FPatterns.Free;
  inherited;
end;

procedure TIntentParser.InitializePatterns;
begin
  // 数据处理模式
  FPatterns.Add(itDataProcessing, [
    '处理.*数据', '转换.*格式', '解析.*文件', '提取.*信息',
    'process.*data', 'transform.*format', 'parse.*file', 'extract.*info',
    '清洗数据', '数据清理', '格式�?, '标准�?
  ]);
  
  // API 集成模式
  FPatterns.Add(itAPIIntegration, [
    '调用.*API', '请求.*接口', '获取.*数据', '发�?*请求',
    'call.*api', 'request.*endpoint', 'fetch.*data', 'send.*request',
    'HTTP', 'REST', 'GraphQL', 'webhook'
  ]);
  
  // 通知发送模�?
  FPatterns.Add(itNotification, [
    '发�?*通知', '发�?*邮件', '发�?*消息', '通知.*用户',
    'send.*notification', 'send.*email', 'send.*message', 'notify.*user',
    '短信', 'SMS', '推�?, 'push', '钉钉', '微信', 'Slack'
  ]);
  
  // 文件操作模式
  FPatterns.Add(itFileOperation, [
    '读取.*文件', '写入.*文件', '上传.*文件', '下载.*文件',
    'read.*file', 'write.*file', 'upload.*file', 'download.*file',
    '保存', '存储', '导出', '导入', 'CSV', 'Excel', 'JSON'
  ]);
  
  // 数据库查询模�?
  FPatterns.Add(itDatabaseQuery, [
    '查询.*数据�?, '查询.*�?, '插入.*记录', '更新.*数据',
    'query.*database', 'select.*from', 'insert.*into', 'update.*table',
    'SQL', 'MySQL', 'PostgreSQL', 'MongoDB'
  ]);
  
  // 定时任务模式
  FPatterns.Add(itScheduledTask, [
    '定时.*执行', '�?*运行', '计划.*任务', '周期.*执行',
    'schedule.*task', 'run.*every', 'cron', 'periodic',
    '每天', '每小�?, '每周', 'daily', 'hourly', 'weekly'
  ]);
  
  // 条件逻辑模式
  FPatterns.Add(itConditionalLogic, [
    '如果.*�?, '�?*�?, '条件.*判断', '根据.*决定',
    'if.*then', 'when.*do', 'condition', 'switch',
    '判断', '分支', '选择'
  ]);
  
  // 数据转换模式
  FPatterns.Add(itDataTransform, [
    '转换.*�?, '映射.*�?, '格式�?*�?, '编码.*解码',
    'convert.*to', 'map.*to', 'format.*as', 'encode.*decode',
    'JSON', 'XML', 'CSV', 'Base64'
  ]);
  
  // 数据验证模式
  FPatterns.Add(itValidation, [
    '验证.*数据', '校验.*格式', '检�?*有效', '确认.*正确',
    'validate.*data', 'verify.*format', 'check.*valid', 'confirm.*correct',
    '校验', '验证', '检�?
  ]);
  
  // 数据聚合模式
  FPatterns.Add(itAggregation, [
    '汇�?*数据', '统计.*结果', '聚合.*信息', '合并.*数据',
    'aggregate.*data', 'summarize.*result', 'combine.*info', 'merge.*data',
    '求和', '平均', '计数', 'sum', 'avg', 'count'
  ]);
  
  // Webhook 处理模式
  FPatterns.Add(itWebhook, [
    '接收.*webhook', '处理.*回调', '监听.*事件', '响应.*请求',
    'receive.*webhook', 'handle.*callback', 'listen.*event', 'respond.*request'
  ]);
  
  // LLM 对话模式
  FPatterns.Add(itLLMChat, [
    '使用.*AI', '调用.*LLM', '生成.*文本', '智能.*处理',
    'use.*ai', 'call.*llm', 'generate.*text', 'intelligent.*process',
    'GPT', 'Claude', 'Gemini', '大模�?, '智能助手'
  ]);
end;

procedure TIntentParser.InitializeEntityPatterns;
begin
  // 数据源实�?
  FEntityPatterns.Add(etDataSource, 
    '(从|from)\s*([^\s,，]+)');
  
  // 数据目标实体
  FEntityPatterns.Add(etDataTarget,
    '(到|发送到|保存到|to|into)\s*([^\s,，]+)');
  
  // 条件实体
  FEntityPatterns.Add(etCondition,
    '(如果|当|若|if|when|where)\s*(.+?)(则|时|就|then|do)');
  
  // 时间实体
  FEntityPatterns.Add(etTime,
    '(每|every)\s*(天|日|小时|分钟|周|月|day|hour|minute|week|month)');
  
  // 格式实体
  FEntityPatterns.Add(etFormat,
    '(JSON|XML|CSV|Excel|PDF|HTML|Markdown|YAML)');
  
  // 渠道实体
  FEntityPatterns.Add(etChannel,
    '(邮件|短信|微信|钉钉|Slack|Teams|email|sms|wechat)');
end;

function TIntentParser.NormalizeText(const AText: string): string;
begin
  Result := LowerCase(Trim(AText));
  // 移除多余空格
  Result := TRegEx.Replace(Result, '\s+', ' ');
  // 标准化标�?
  Result := StringReplace(Result, '�?, ',', [rfReplaceAll]);
  Result := StringReplace(Result, '�?, '.', [rfReplaceAll]);
end;

function TIntentParser.ExtractEntities(const AText: string): TArray<TEntity>;
var
  EntityType: TEntityType;
  Pattern: string;
  Matches: TMatchCollection;
  Match: TMatch;
  Entity: TEntity;
  EntityList: TList<TEntity>;
begin
  EntityList := TList<TEntity>.Create;
  try
    for EntityType in FEntityPatterns.Keys do
    begin
      Pattern := FEntityPatterns[EntityType];
      Matches := TRegEx.Matches(AText, Pattern, [roIgnoreCase]);
      
      for Match in Matches do
      begin
        Entity.EntityType := EntityType;
        Entity.Value := Match.Value;
        Entity.StartPos := Match.Index;
        Entity.EndPos := Match.Index + Match.Length;
        Entity.Confidence := 0.8;
        EntityList.Add(Entity);
      end;
    end;
    
    Result := EntityList.ToArray;
  finally
    EntityList.Free;
  end;
end;

function TIntentParser.MatchIntent(const AText: string): TPair<TIntentType, Double>;
var
  IntentType: TIntentType;
  Patterns: TArray<string>;
  Pattern: string;
  BestIntent: TIntentType;
  BestScore, Score: Double;
  MatchCount: Integer;
begin
  BestIntent := itUnknown;
  BestScore := 0;
  
  for IntentType in FPatterns.Keys do
  begin
    Patterns := FPatterns[IntentType];
    MatchCount := 0;
    
    for Pattern in Patterns do
    begin
      if TRegEx.IsMatch(AText, Pattern, [roIgnoreCase]) then
        Inc(MatchCount);
    end;
    
    if Length(Patterns) > 0 then
    begin
      Score := MatchCount / Length(Patterns);
      if Score > BestScore then
      begin
        BestScore := Score;
        BestIntent := IntentType;
      end;
    end;
  end;
  
  // 调整置信�?
  if BestScore > 0 then
    BestScore := Min(0.95, BestScore * 1.5);
  
  Result := TPair<TIntentType, Double>.Create(BestIntent, BestScore);
end;

function TIntentParser.Parse(const AText: string): TParsedIntent;
var
  NormalizedText: string;
  IntentMatch: TPair<TIntentType, Double>;
begin
  NormalizedText := NormalizeText(AText);
  IntentMatch := MatchIntent(NormalizedText);
  
  Result.IntentType := IntentMatch.Key;
  Result.Confidence := IntentMatch.Value;
  Result.Entities := ExtractEntities(NormalizedText);
  Result.OriginalText := AText;
  Result.NormalizedText := NormalizedText;
end;

function TIntentParser.ParseMultiple(const AText: string): TArray<TParsedIntent>;
var
  Sentences: TArray<string>;
  Sentence: string;
  IntentList: TList<TParsedIntent>;
  Intent: TParsedIntent;
begin
  // 按句子分�?
  Sentences := TRegEx.Split(AText, '[�?;；]');
  
  IntentList := TList<TParsedIntent>.Create;
  try
    for Sentence in Sentences do
    begin
      if Trim(Sentence) <> '' then
      begin
        Intent := Parse(Sentence);
        if Intent.IntentType <> itUnknown then
          IntentList.Add(Intent);
      end;
    end;
    
    Result := IntentList.ToArray;
  finally
    IntentList.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TSkillMatcher'}

constructor TSkillMatcher.Create;
begin
  inherited Create;
  FSkills := TDictionary<string, TSkillDefinition>.Create;
  FKeywordIndex := TDictionary<string, TList<string>>.Create;
end;

destructor TSkillMatcher.Destroy;
var
  List: TList<string>;
begin
  for List in FKeywordIndex.Values do
    List.Free;
  FKeywordIndex.Free;
  FSkills.Free;
  inherited;
end;

procedure TSkillMatcher.RegisterSkill(const ASkill: TSkillDefinition);
begin
  FSkills.AddOrSetValue(ASkill.SkillId, ASkill);
end;

procedure TSkillMatcher.UnregisterSkill(const ASkillId: string);
begin
  FSkills.Remove(ASkillId);
end;

procedure TSkillMatcher.BuildIndex;
var
  Skill: TSkillDefinition;
  Keyword: string;
  SkillList: TList<string>;
begin
  // 清空旧索�?
  for SkillList in FKeywordIndex.Values do
    SkillList.Free;
  FKeywordIndex.Clear;
  
  // 重建索引
  for Skill in FSkills.Values do
  begin
    for Keyword in Skill.Keywords do
    begin
      if not FKeywordIndex.TryGetValue(LowerCase(Keyword), SkillList) then
      begin
        SkillList := TList<string>.Create;
        FKeywordIndex.Add(LowerCase(Keyword), SkillList);
      end;
      if SkillList.IndexOf(Skill.SkillId) < 0 then
        SkillList.Add(Skill.SkillId);
    end;
  end;
end;

function TSkillMatcher.ComputeMatchScore(const ASkill: TSkillDefinition;
  const AIntent: TParsedIntent): Double;
var
  Score: Double;
  Keyword: string;
  MatchedKeywords: Integer;
begin
  Score := 0;
  MatchedKeywords := 0;
  
  // 关键词匹�?
  for Keyword in ASkill.Keywords do
  begin
    if Pos(LowerCase(Keyword), AIntent.NormalizedText) > 0 then
      Inc(MatchedKeywords);
  end;
  
  if Length(ASkill.Keywords) > 0 then
    Score := Score + (MatchedKeywords / Length(ASkill.Keywords)) * 0.5;
  
  // 意图类型匹配
  case AIntent.IntentType of
    itAPIIntegration:
      if (ASkill.SkillType = 'http_request') or (ASkill.Category = 'api') then
        Score := Score + 0.3;
    itNotification:
      if (ASkill.SkillType = 'email') or (ASkill.SkillType = 'sms') or
         (ASkill.Category = 'notification') then
        Score := Score + 0.3;
    itDatabaseQuery:
      if (ASkill.SkillType = 'database') or (ASkill.Category = 'database') then
        Score := Score + 0.3;
    itFileOperation:
      if (ASkill.SkillType = 'file') or (ASkill.Category = 'file') then
        Score := Score + 0.3;
    itDataTransform:
      if (ASkill.SkillType = 'transform') or (ASkill.Category = 'transform') then
        Score := Score + 0.3;
    itLLMChat:
      if (ASkill.SkillType = 'llm') or (ASkill.Category = 'ai') then
        Score := Score + 0.3;
  end;
  
  // 描述匹配
  if Pos(AIntent.NormalizedText, LowerCase(ASkill.Description)) > 0 then
    Score := Score + 0.2;
  
  Result := Min(1.0, Score);
end;

function TSkillMatcher.InferParameters(const ASkill: TSkillDefinition;
  const AEntities: TArray<TEntity>): TDictionary<string, string>;
var
  Entity: TEntity;
  ParamName: string;
begin
  Result := TDictionary<string, string>.Create;
  
  for Entity in AEntities do
  begin
    case Entity.EntityType of
      etDataSource:
        if IndexStr('source', ASkill.RequiredInputs) >= 0 then
          Result.Add('source', Entity.Value)
        else if IndexStr('url', ASkill.RequiredInputs) >= 0 then
          Result.Add('url', Entity.Value);
          
      etDataTarget:
        if IndexStr('target', ASkill.RequiredInputs) >= 0 then
          Result.Add('target', Entity.Value)
        else if IndexStr('destination', ASkill.RequiredInputs) >= 0 then
          Result.Add('destination', Entity.Value);
          
      etFormat:
        if IndexStr('format', ASkill.RequiredInputs) >= 0 then
          Result.Add('format', Entity.Value);
          
      etChannel:
        if IndexStr('channel', ASkill.RequiredInputs) >= 0 then
          Result.Add('channel', Entity.Value);
          
      etTime:
        if IndexStr('schedule', ASkill.RequiredInputs) >= 0 then
          Result.Add('schedule', Entity.Value);
    end;
  end;
end;

function TSkillMatcher.FindMatches(const AIntent: TParsedIntent;
  AMaxResults: Integer): TArray<TSkillMatch>;
var
  Skill: TSkillDefinition;
  Match: TSkillMatch;
  MatchList: TList<TSkillMatch>;
  Score: Double;
begin
  MatchList := TList<TSkillMatch>.Create;
  try
    for Skill in FSkills.Values do
    begin
      Score := ComputeMatchScore(Skill, AIntent);
      if Score > 0.1 then
      begin
        Match.SkillId := Skill.SkillId;
        Match.SkillType := Skill.SkillType;
        Match.SkillName := Skill.Name;
        Match.MatchScore := Score;
        Match.RequiredParams := Skill.RequiredInputs;
        Match.InferredParams := InferParameters(Skill, AIntent.Entities);
        MatchList.Add(Match);
      end;
    end;
    
    // 按分数排�?
    MatchList.Sort(TComparer<TSkillMatch>.Construct(
      function(const L, R: TSkillMatch): Integer
      begin
        if R.MatchScore > L.MatchScore then Result := 1
        else if R.MatchScore < L.MatchScore then Result := -1
        else Result := 0;
      end
    ));
    
    // 限制结果数量
    while MatchList.Count > AMaxResults do
      MatchList.Delete(MatchList.Count - 1);
    
    Result := MatchList.ToArray;
  finally
    MatchList.Free;
  end;
end;

function TSkillMatcher.FindByKeyword(const AKeyword: string): TArray<TSkillDefinition>;
var
  SkillList: TList<string>;
  SkillId: string;
  Skill: TSkillDefinition;
  ResultList: TList<TSkillDefinition>;
begin
  ResultList := TList<TSkillDefinition>.Create;
  try
    if FKeywordIndex.TryGetValue(LowerCase(AKeyword), SkillList) then
    begin
      for SkillId in SkillList do
      begin
        if FSkills.TryGetValue(SkillId, Skill) then
          ResultList.Add(Skill);
      end;
    end;
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TWorkflowGenerator'}

constructor TWorkflowGenerator.Create;
begin
  inherited Create;
  FIntentParser := TIntentParser.Create;
  FSkillMatcher := TSkillMatcher.Create;
  FStepCounter := 0;
  
  // 注册内置 Skills
  RegisterBuiltinSkills;
end;

destructor TWorkflowGenerator.Destroy;
begin
  FSkillMatcher.Free;
  FIntentParser.Free;
  inherited;
end;

procedure RegisterBuiltinSkills;
var
  Skill: TSkillDefinition;
begin
  // HTTP 请求
  Skill.SkillId := 'http_request';
  Skill.SkillType := 'http_request';
  Skill.Name := 'HTTP 请求';
  Skill.Description := '发�?HTTP 请求到指�?URL';
  Skill.Keywords := ['http', 'api', '请求', '调用', 'get', 'post', 'request', 'fetch'];
  Skill.RequiredInputs := ['url', 'method'];
  Skill.OptionalInputs := ['headers', 'body', 'timeout'];
  Skill.Outputs := ['response', 'status_code'];
  Skill.Category := 'api';
  // FSkillMatcher.RegisterSkill(Skill);
  
  // 更多内置 Skills...
end;

function TWorkflowGenerator.GenerateStepId: string;
begin
  Inc(FStepCounter);
  Result := 'step_' + IntToStr(FStepCounter);
end;

function TWorkflowGenerator.CreateStep(const AIntent: TParsedIntent;
  const ASkillMatch: TSkillMatch): TGeneratedStep;
var
  Key: string;
begin
  Result.StepId := GenerateStepId;
  Result.StepName := ASkillMatch.SkillName;
  Result.SkillMatch := ASkillMatch;
  Result.Inputs := TDictionary<string, string>.Create;
  
  // 复制推断的参�?
  for Key in ASkillMatch.InferredParams.Keys do
    Result.Inputs.Add(Key, ASkillMatch.InferredParams[Key]);
  
  Result.Outputs := ['output'];
  SetLength(Result.Dependencies, 0);
  Result.Condition := '';
end;

function TWorkflowGenerator.DetermineStepOrder(
  const ASteps: TArray<TGeneratedStep>): TArray<TGeneratedStep>;
begin
  // 简单实现：保持原顺�?
  Result := ASteps;
end;

function TWorkflowGenerator.InferDependencies(
  const ASteps: TArray<TGeneratedStep>): TArray<TGeneratedStep>;
var
  I: Integer;
begin
  Result := ASteps;
  
  // 简单实现：线性依�?
  for I := 1 to High(Result) do
  begin
    SetLength(Result[I].Dependencies, 1);
    Result[I].Dependencies[0] := Result[I-1].StepId;
  end;
end;

function TWorkflowGenerator.AddErrorHandlers(
  const ASteps: TArray<TGeneratedStep>): TArray<TGeneratedStep>;
var
  I: Integer;
  ErrorStep: TGeneratedStep;
  NewSteps: TList<TGeneratedStep>;
begin
  NewSteps := TList<TGeneratedStep>.Create;
  try
    for I := 0 to High(ASteps) do
    begin
      NewSteps.Add(ASteps[I]);
      
      // 为关键步骤添加错误处�?
      if ASteps[I].SkillMatch.SkillType in ['http_request', 'database', 'file'] then
      begin
        ErrorStep.StepId := ASteps[I].StepId + '_error_handler';
        ErrorStep.StepName := '错误处理: ' + ASteps[I].StepName;
        ErrorStep.SkillMatch.SkillType := 'error_handler';
        ErrorStep.Condition := 'error';
        SetLength(ErrorStep.Dependencies, 1);
        ErrorStep.Dependencies[0] := ASteps[I].StepId;
        NewSteps.Add(ErrorStep);
      end;
    end;
    
    Result := NewSteps.ToArray;
  finally
    NewSteps.Free;
  end;
end;

function TWorkflowGenerator.GenerateWorkflowName(
  const AIntents: TArray<TParsedIntent>): string;
var
  Intent: TParsedIntent;
  Parts: TStringList;
begin
  Parts := TStringList.Create;
  try
    for Intent in AIntents do
    begin
      case Intent.IntentType of
        itDataProcessing: Parts.Add('数据处理');
        itAPIIntegration: Parts.Add('API集成');
        itNotification: Parts.Add('通知');
        itFileOperation: Parts.Add('文件操作');
        itDatabaseQuery: Parts.Add('数据库查�?);
        itScheduledTask: Parts.Add('定时任务');
        itDataTransform: Parts.Add('数据转换');
        itLLMChat: Parts.Add('AI处理');
      end;
    end;
    
    if Parts.Count > 0 then
      Result := Parts[0] + '工作�?
    else
      Result := '自动生成工作�?;
  finally
    Parts.Free;
  end;
end;

function TWorkflowGenerator.GenerateDescription(const AOriginalText: string;
  const AIntents: TArray<TParsedIntent>): string;
begin
  Result := '基于自然语言描述自动生成: ' + AOriginalText;
end;

function TWorkflowGenerator.Generate(const ANaturalLanguage: string;
  const AOptions: TGenerationOptions): TGeneratedWorkflow;
var
  Intents: TArray<TParsedIntent>;
  Intent: TParsedIntent;
  SkillMatches: TArray<TSkillMatch>;
  Step: TGeneratedStep;
  Steps: TList<TGeneratedStep>;
  StepsArray: TArray<TGeneratedStep>;
  Warnings: TList<string>;
begin
  FStepCounter := 0;
  Steps := TList<TGeneratedStep>.Create;
  Warnings := TList<string>.Create;
  try
    // 解析意图
    Intents := FIntentParser.ParseMultiple(ANaturalLanguage);
    
    if Length(Intents) = 0 then
    begin
      Warnings.Add('无法识别有效的工作流意图');
      Result.Confidence := 0;
      Result.Warnings := Warnings.ToArray;
      Exit;
    end;
    
    // 为每个意图匹�?Skill 并创建步�?
    for Intent in Intents do
    begin
      SkillMatches := FSkillMatcher.FindMatches(Intent, 1);
      
      if Length(SkillMatches) > 0 then
      begin
        Step := CreateStep(Intent, SkillMatches[0]);
        Steps.Add(Step);
      end
      else
        Warnings.Add('无法为意图找到匹配的 Skill: ' + Intent.OriginalText);
      
      if Steps.Count >= AOptions.MaxSteps then
        Break;
    end;
    
    // 确定步骤顺序和依�?
    StepsArray := Steps.ToArray;
    StepsArray := DetermineStepOrder(StepsArray);
    StepsArray := InferDependencies(StepsArray);
    
    // 添加错误处理�?
    if AOptions.AddErrorHandlers then
      StepsArray := AddErrorHandlers(StepsArray);
    
    // 构建结果
    Result.WorkflowId := TGUID.NewGuid.ToString;
    Result.Name := GenerateWorkflowName(Intents);
    Result.Description := GenerateDescription(ANaturalLanguage, Intents);
    Result.Steps := StepsArray;
    Result.Variables := TDictionary<string, string>.Create;
    SetLength(Result.Triggers, 0);
    Result.Warnings := Warnings.ToArray;
    
    // 计算整体置信�?
    Result.Confidence := 0;
    for Intent in Intents do
      Result.Confidence := Result.Confidence + Intent.Confidence;
    if Length(Intents) > 0 then
      Result.Confidence := Result.Confidence / Length(Intents);
    
    // 生成建议
    SetLength(Result.Suggestions, 0);
    if Result.Confidence < 0.7 then
    begin
      SetLength(Result.Suggestions, 1);
      Result.Suggestions[0] := '建议添加更详细的描述以提高准确�?;
    end;
  finally
    Warnings.Free;
    Steps.Free;
  end;
end;

function TWorkflowGenerator.GenerateFromTemplate(const ATemplate: string;
  const AParams: TDictionary<string, string>): TGeneratedWorkflow;
begin
  // 模板生成实现
  Result.WorkflowId := TGUID.NewGuid.ToString;
  Result.Name := '模板工作�?;
  Result.Confidence := 1.0;
end;

function TWorkflowGenerator.ToJSON(const AWorkflow: TGeneratedWorkflow): TJSONObject;
var
  StepsArr: TJSONArray;
  StepObj: TJSONObject;
  Step: TGeneratedStep;
  InputsObj: TJSONObject;
  DepsArr, OutputsArr, WarningsArr, SuggestionsArr: TJSONArray;
  Key: string;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AWorkflow.WorkflowId);
  Result.AddPair('name', AWorkflow.Name);
  Result.AddPair('description', AWorkflow.Description);
  Result.AddPair('confidence', TJSONNumber.Create(AWorkflow.Confidence));
  
  // 步骤
  StepsArr := TJSONArray.Create;
  for Step in AWorkflow.Steps do
  begin
    StepObj := TJSONObject.Create;
    StepObj.AddPair('id', Step.StepId);
    StepObj.AddPair('name', Step.StepName);
    StepObj.AddPair('skillType', Step.SkillMatch.SkillType);
    StepObj.AddPair('skillId', Step.SkillMatch.SkillId);
    
    // 输入
    InputsObj := TJSONObject.Create;
    if Assigned(Step.Inputs) then
      for Key in Step.Inputs.Keys do
        InputsObj.AddPair(Key, Step.Inputs[Key]);
    StepObj.AddPair('inputs', InputsObj);
    
    // 输出
    OutputsArr := TJSONArray.Create;
    for I := 0 to High(Step.Outputs) do
      OutputsArr.Add(Step.Outputs[I]);
    StepObj.AddPair('outputs', OutputsArr);
    
    // 依赖
    DepsArr := TJSONArray.Create;
    for I := 0 to High(Step.Dependencies) do
      DepsArr.Add(Step.Dependencies[I]);
    StepObj.AddPair('dependencies', DepsArr);
    
    if Step.Condition <> '' then
      StepObj.AddPair('condition', Step.Condition);
    
    StepsArr.Add(StepObj);
  end;
  Result.AddPair('steps', StepsArr);
  
  // 警告
  WarningsArr := TJSONArray.Create;
  for I := 0 to High(AWorkflow.Warnings) do
    WarningsArr.Add(AWorkflow.Warnings[I]);
  Result.AddPair('warnings', WarningsArr);
  
  // 建议
  SuggestionsArr := TJSONArray.Create;
  for I := 0 to High(AWorkflow.Suggestions) do
    SuggestionsArr.Add(AWorkflow.Suggestions[I]);
  Result.AddPair('suggestions', SuggestionsArr);
end;

function TWorkflowGenerator.Validate(const AWorkflow: TGeneratedWorkflow): TArray<string>;
var
  Errors: TList<string>;
  Step: TGeneratedStep;
  ParamName: string;
begin
  Errors := TList<string>.Create;
  try
    // 检查是否有步骤
    if Length(AWorkflow.Steps) = 0 then
      Errors.Add('工作流没有任何步�?);
    
    // 检查每个步�?
    for Step in AWorkflow.Steps do
    begin
      // 检查必需参数
      for ParamName in Step.SkillMatch.RequiredParams do
      begin
        if not Assigned(Step.Inputs) or not Step.Inputs.ContainsKey(ParamName) then
          Errors.Add(Format('步骤 %s 缺少必需参数: %s', [Step.StepName, ParamName]));
      end;
    end;
    
    Result := Errors.ToArray;
  finally
    Errors.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TLLMWorkflowGenerator'}

constructor TLLMWorkflowGenerator.Create(const AEndpoint, AAPIKey, AModel: string);
begin
  inherited Create;
  FBaseGenerator := TWorkflowGenerator.Create;
  FLLMEndpoint := AEndpoint;
  FAPIKey := AAPIKey;
  FModel := AModel;
  
  FSystemPrompt := 
    '你是一个工作流生成专家。根据用户的自然语言描述，生成结构化的工作流定义�? + #13#10 +
    '输出必须是有效的 JSON 格式，包含以下字段：' + #13#10 +
    '- name: 工作流名�? + #13#10 +
    '- description: 工作流描�? + #13#10 +
    '- steps: 步骤数组，每个步骤包�?id, name, skillType, inputs, outputs, dependencies' + #13#10 +
    '只输�?JSON，不要有其他说明�?;
end;

destructor TLLMWorkflowGenerator.Destroy;
begin
  FBaseGenerator.Free;
  inherited;
end;

function TLLMWorkflowGenerator.BuildPrompt(const ARequest: TLLMGenerationRequest): string;
var
  SkillsDesc: string;
  Skill: TSkillDefinition;
begin
  SkillsDesc := '';
  for Skill in ARequest.AvailableSkills do
    SkillsDesc := SkillsDesc + Format('- %s (%s): %s'#13#10, 
      [Skill.Name, Skill.SkillType, Skill.Description]);
  
  Result := Format(
    '可用�?Skill 类型�?#13#10'%s'#13#10 +
    '用户需求：%s'#13#10 +
    '请生成工作流 JSON�?,
    [SkillsDesc, ARequest.UserPrompt]
  );
end;

function TLLMWorkflowGenerator.ParseLLMResponse(const AResponse: string): TLLMGenerationResponse;
var
  JSONStart, JSONEnd: Integer;
  JSONStr: string;
begin
  Result.Success := False;
  Result.Confidence := 0;
  SetLength(Result.Warnings, 0);
  
  // 提取 JSON
  JSONStart := Pos('{', AResponse);
  JSONEnd := LastDelimiter('}', AResponse);
  
  if (JSONStart > 0) and (JSONEnd > JSONStart) then
  begin
    JSONStr := Copy(AResponse, JSONStart, JSONEnd - JSONStart + 1);
    try
      Result.WorkflowJSON := TJSONObject.ParseJSONValue(JSONStr) as TJSONObject;
      if Assigned(Result.WorkflowJSON) then
      begin
        Result.Success := True;
        Result.Confidence := 0.85;
      end;
    except
      SetLength(Result.Warnings, 1);
      Result.Warnings[0] := 'LLM 响应解析失败';
    end;
  end
  else
  begin
    SetLength(Result.Warnings, 1);
    Result.Warnings[0] := 'LLM 响应中未找到有效�?JSON';
  end;
end;

function TLLMWorkflowGenerator.CallLLM(const APrompt: string): string;
var
  HttpClient: THTTPClient;
  RequestBody: TJSONObject;
  MessagesArr: TJSONArray;
  Response: IHTTPResponse;
  ResponseJSON: TJSONObject;
  Content: string;
begin
  Result := '';
  HttpClient := THTTPClient.Create;
  try
    HttpClient.ContentType := 'application/json';
    HttpClient.CustomHeaders['Authorization'] := 'Bearer ' + FAPIKey;
    
    RequestBody := TJSONObject.Create;
    try
      RequestBody.AddPair('model', FModel);
      RequestBody.AddPair('max_tokens', TJSONNumber.Create(2000));
      RequestBody.AddPair('temperature', TJSONNumber.Create(0.3));
      
      MessagesArr := TJSONArray.Create;
      MessagesArr.Add(TJSONObject.Create
        .AddPair('role', 'system')
        .AddPair('content', FSystemPrompt));
      MessagesArr.Add(TJSONObject.Create
        .AddPair('role', 'user')
        .AddPair('content', APrompt));
      RequestBody.AddPair('messages', MessagesArr);
      
      try
        Response := HttpClient.Post(FLLMEndpoint,
          TStringStream.Create(RequestBody.ToJSON, TEncoding.UTF8), nil);
        
        if Response.StatusCode = 200 then
        begin
          ResponseJSON := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
          try
            if Assigned(ResponseJSON) then
              Result := ResponseJSON.GetValue<string>('choices[0].message.content', '');
          finally
            ResponseJSON.Free;
          end;
        end;
      except
        // 忽略网络错误
      end;
    finally
      RequestBody.Free;
    end;
  finally
    HttpClient.Free;
  end;
end;

function TLLMWorkflowGenerator.Generate(const ANaturalLanguage: string): TGeneratedWorkflow;
var
  Request: TLLMGenerationRequest;
  Prompt: string;
  LLMResponse: string;
  ParsedResponse: TLLMGenerationResponse;
begin
  // 首先尝试基础生成�?
  var Options: TGenerationOptions;
  Options.MaxSteps := 10;
  Options.AddErrorHandlers := True;
  Result := FBaseGenerator.Generate(ANaturalLanguage, Options);
  
  // 如果置信度低，使�?LLM 增强
  if (Result.Confidence < 0.6) and (FLLMEndpoint <> '') then
  begin
    Request.UserPrompt := ANaturalLanguage;
    Request.SystemPrompt := FSystemPrompt;
    Request.MaxTokens := 2000;
    Request.Temperature := 0.3;
    
    Prompt := BuildPrompt(Request);
    LLMResponse := CallLLM(Prompt);
    
    if LLMResponse <> '' then
    begin
      ParsedResponse := ParseLLMResponse(LLMResponse);
      if ParsedResponse.Success then
      begin
        // �?LLM 响应重建工作�?
        Result.WorkflowId := TGUID.NewGuid.ToString;
        Result.Name := ParsedResponse.WorkflowJSON.GetValue<string>('name', Result.Name);
        Result.Description := ParsedResponse.WorkflowJSON.GetValue<string>('description', Result.Description);
        Result.Confidence := ParsedResponse.Confidence;
      end;
    end;
  end;
end;

function TLLMWorkflowGenerator.Refine(const AWorkflow: TGeneratedWorkflow;
  const AFeedback: string): TGeneratedWorkflow;
var
  Prompt: string;
  LLMResponse: string;
begin
  Result := AWorkflow;
  
  if FLLMEndpoint = '' then
    Exit;
  
  Prompt := Format(
    '当前工作流：'#13#10'%s'#13#10#13#10 +
    '用户反馈�?s'#13#10#13#10 +
    '请根据反馈优化工作流，输出新�?JSON�?,
    [FBaseGenerator.ToJSON(AWorkflow).ToJSON, AFeedback]
  );
  
  LLMResponse := CallLLM(Prompt);
  if LLMResponse <> '' then
  begin
    var ParsedResponse := ParseLLMResponse(LLMResponse);
    if ParsedResponse.Success then
    begin
      Result.Name := ParsedResponse.WorkflowJSON.GetValue<string>('name', Result.Name);
      Result.Description := ParsedResponse.WorkflowJSON.GetValue<string>('description', Result.Description);
    end;
  end;
end;

function TLLMWorkflowGenerator.Explain(const AWorkflow: TGeneratedWorkflow): string;
var
  Prompt: string;
begin
  if FLLMEndpoint = '' then
  begin
    Result := '工作�?"' + AWorkflow.Name + '" 包含 ' + 
      IntToStr(Length(AWorkflow.Steps)) + ' 个步骤�?;
    Exit;
  end;
  
  Prompt := Format(
    '请用简洁的中文解释以下工作流的功能�?#13#10'%s',
    [FBaseGenerator.ToJSON(AWorkflow).ToJSON]
  );
  
  Result := CallLLM(Prompt);
  if Result = '' then
    Result := AWorkflow.Description;
end;

{$ENDREGION}

{$REGION 'TConversationalBuilder'}

constructor TConversationalBuilder.Create(AGenerator: TLLMWorkflowGenerator);
begin
  inherited Create;
  FGenerator := AGenerator;
  FState := csInitial;
  FHistory := TList<TConversationMessage>.Create;
  FPendingQuestions := TStringList.Create;
  FUserResponses := TDictionary<string, string>.Create;
end;

destructor TConversationalBuilder.Destroy;
begin
  FUserResponses.Free;
  FPendingQuestions.Free;
  FHistory.Free;
  inherited;
end;

function TConversationalBuilder.GenerateQuestion: string;
begin
  case FState of
    csGatheringRequirements:
      Result := '请描述您想要创建的工作流的主要功能是什么？';
    csConfirmingSteps:
      Result := '我为您生成了以下步骤，是否需要修改？'#13#10 +
        '1. ' + FCurrentWorkflow.Steps[0].StepName;
    csConfirmingParameters:
      Result := '请确认以下参数是否正确？';
    csReviewing:
      Result := '工作流已生成，是否需要调整？输入 "完成" 结束�?;
  else
    Result := '请继续描述您的需求�?;
  end;
end;

function TConversationalBuilder.ProcessUserInput(const AInput: string): string;
var
  Msg: TConversationMessage;
begin
  // 记录用户输入
  Msg.Role := 'user';
  Msg.Content := AInput;
  Msg.Timestamp := Now;
  FHistory.Add(Msg);
  
  case FState of
    csInitial, csGatheringRequirements:
      begin
        // 生成工作�?
        FCurrentWorkflow := FGenerator.Generate(AInput);
        if FCurrentWorkflow.Confidence > 0.5 then
        begin
          FState := csConfirmingSteps;
          Result := Format('我理解您想要�?s'#13#10#13#10'生成�?%d 个步骤。是否确认？',
            [FCurrentWorkflow.Description, Length(FCurrentWorkflow.Steps)]);
        end
        else
        begin
          Result := '抱歉，我没有完全理解。能否更详细地描述一下？';
        end;
      end;
    
    csConfirmingSteps:
      begin
        if (Pos('确认', AInput) > 0) or (Pos('�?, AInput) > 0) or 
           (Pos('yes', LowerCase(AInput)) > 0) then
        begin
          FState := csReviewing;
          Result := '很好！工作流已准备就绪。输�?"完成" 确认，或描述需要修改的地方�?;
        end
        else
        begin
          // 根据反馈优化
          FCurrentWorkflow := FGenerator.Refine(FCurrentWorkflow, AInput);
          Result := '已根据您的反馈调整。请再次确认�?;
        end;
      end;
    
    csReviewing:
      begin
        if (Pos('完成', AInput) > 0) or (Pos('确认', AInput) > 0) or
           (Pos('done', LowerCase(AInput)) > 0) then
        begin
          FState := csComplete;
          Result := '工作流创建完成！';
        end
        else
        begin
          FCurrentWorkflow := FGenerator.Refine(FCurrentWorkflow, AInput);
          Result := '已更新。还需要其他修改吗�?;
        end;
      end;
  else
    Result := '对话已结束�?;
  end;
  
  // 记录助手响应
  Msg.Role := 'assistant';
  Msg.Content := Result;
  Msg.Timestamp := Now;
  FHistory.Add(Msg);
end;

function TConversationalBuilder.ShouldTransitionState: Boolean;
begin
  Result := False;
end;

procedure TConversationalBuilder.TransitionState;
begin
  // 状态转换逻辑
end;

function TConversationalBuilder.Start(const AInitialPrompt: string): string;
begin
  Reset;
  FState := csGatheringRequirements;
  
  if AInitialPrompt <> '' then
    Result := ProcessUserInput(AInitialPrompt)
  else
    Result := '您好！我可以帮您创建工作流。请描述您想要自动化的任务�?;
end;

function TConversationalBuilder.Continue(const AUserInput: string): string;
begin
  Result := ProcessUserInput(AUserInput);
end;

function TConversationalBuilder.GetCurrentWorkflow: TGeneratedWorkflow;
begin
  Result := FCurrentWorkflow;
end;

function TConversationalBuilder.IsComplete: Boolean;
begin
  Result := FState = csComplete;
end;

procedure TConversationalBuilder.Reset;
begin
  FState := csInitial;
  FHistory.Clear;
  FPendingQuestions.Clear;
  FUserResponses.Clear;
end;

{$ENDREGION}

{$REGION 'TTemplateManager'}

constructor TTemplateManager.Create;
begin
  inherited Create;
  FTemplates := TDictionary<string, TWorkflowTemplate>.Create;
end;

destructor TTemplateManager.Destroy;
begin
  FTemplates.Free;
  inherited;
end;

procedure TTemplateManager.RegisterTemplate(const ATemplate: TWorkflowTemplate);
begin
  FTemplates.AddOrSetValue(ATemplate.TemplateId, ATemplate);
end;

procedure TTemplateManager.UnregisterTemplate(const ATemplateId: string);
begin
  FTemplates.Remove(ATemplateId);
end;

function TTemplateManager.GetTemplate(const ATemplateId: string): TWorkflowTemplate;
begin
  if not FTemplates.TryGetValue(ATemplateId, Result) then
    Result.TemplateId := '';
end;

function TTemplateManager.FindTemplates(const AQuery: string): TArray<TWorkflowTemplate>;
var
  Template: TWorkflowTemplate;
  Results: TList<TWorkflowTemplate>;
  QueryLower: string;
begin
  QueryLower := LowerCase(AQuery);
  Results := TList<TWorkflowTemplate>.Create;
  try
    for Template in FTemplates.Values do
    begin
      if (Pos(QueryLower, LowerCase(Template.Name)) > 0) or
         (Pos(QueryLower, LowerCase(Template.Description)) > 0) or
         (Pos(QueryLower, LowerCase(Template.Category)) > 0) then
        Results.Add(Template);
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

function TTemplateManager.InstantiateTemplate(const ATemplateId: string;
  const AVariables: TDictionary<string, string>): TJSONObject;
var
  Template: TWorkflowTemplate;
  JSONStr: string;
  VarName, VarValue: string;
begin
  Result := nil;
  
  if not FTemplates.TryGetValue(ATemplateId, Template) then
    Exit;
  
  if not Assigned(Template.WorkflowJSON) then
    Exit;
  
  JSONStr := Template.WorkflowJSON.ToJSON;
  
  // 替换变量
  for VarName in AVariables.Keys do
  begin
    VarValue := AVariables[VarName];
    JSONStr := StringReplace(JSONStr, '{{' + VarName + '}}', VarValue, [rfReplaceAll]);
  end;
  
  Result := TJSONObject.ParseJSONValue(JSONStr) as TJSONObject;
end;

{$ENDREGION}

end.
