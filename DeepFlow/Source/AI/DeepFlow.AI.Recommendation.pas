unit UniFlow.AI.Recommendation;

{*******************************************************************************
  UniFlow 智能工作流推荐系�?
  
  功能:
  - 基于历史执行数据推荐工作流模�?
  - 基于用户行为分析推荐优化建议
  - 相似工作流匹�?
  - 性能优化建议
  - 错误模式分析与预防建�?
  
  作�? UniFlow Team
  日期: 2024-01
*******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.JSON, System.Math, System.DateUtils, System.SyncObjs;

type
  {$REGION '推荐类型定义'}
  
  /// <summary>推荐类型</summary>
  TRecommendationType = (
    rtWorkflowTemplate,      // 工作流模板推�?
    rtSkillSuggestion,       // Skill 建议
    rtOptimization,          // 优化建议
    rtErrorPrevention,       // 错误预防
    rtPerformance,           // 性能优化
    rtSimilarWorkflow        // 相似工作�?
  );
  
  /// <summary>推荐置信�?/summary>
  TConfidenceLevel = (
    clLow,      // < 50%
    clMedium,   // 50-75%
    clHigh,     // 75-90%
    clVeryHigh  // > 90%
  );
  
  /// <summary>推荐�?/summary>
  TRecommendation = class
  private
    FId: string;
    FType: TRecommendationType;
    FTitle: string;
    FDescription: string;
    FScore: Double;
    FConfidence: TConfidenceLevel;
    FMetadata: TDictionary<string, string>;
    FActions: TStringList;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    
    function ToJSON: TJSONObject;
    class function FromJSON(AJSON: TJSONObject): TRecommendation;
    
    property Id: string read FId write FId;
    property RecommendationType: TRecommendationType read FType write FType;
    property Title: string read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    property Score: Double read FScore write FScore;
    property Confidence: TConfidenceLevel read FConfidence write FConfidence;
    property Metadata: TDictionary<string, string> read FMetadata;
    property Actions: TStringList read FActions;
    property CreatedAt: TDateTime read FCreatedAt;
  end;
  
  /// <summary>用户行为事件</summary>
  TUserBehaviorEvent = record
    UserId: string;
    EventType: string;
    WorkflowId: string;
    SkillId: string;
    Timestamp: TDateTime;
    Duration: Integer;
    Success: Boolean;
    Metadata: string;
  end;
  
  /// <summary>工作流执行统�?/summary>
  TWorkflowStats = record
    WorkflowId: string;
    WorkflowName: string;
    TotalExecutions: Int64;
    SuccessCount: Int64;
    FailureCount: Int64;
    AvgDurationMS: Double;
    P95DurationMS: Double;
    LastExecuted: TDateTime;
    PopularityScore: Double;
  end;
  
  /// <summary>用户偏好</summary>
  TUserPreferences = class
  private
    FUserId: string;
    FPreferredSkills: TStringList;
    FPreferredCategories: TStringList;
    FRecentWorkflows: TStringList;
    FSkillUsageCount: TDictionary<string, Integer>;
    FLastUpdated: TDateTime;
  public
    constructor Create(const AUserId: string);
    destructor Destroy; override;
    
    procedure UpdateFromBehavior(const AEvent: TUserBehaviorEvent);
    function GetTopSkills(ACount: Integer): TArray<string>;
    function GetTopCategories(ACount: Integer): TArray<string>;
    
    property UserId: string read FUserId;
    property PreferredSkills: TStringList read FPreferredSkills;
    property PreferredCategories: TStringList read FPreferredCategories;
    property RecentWorkflows: TStringList read FRecentWorkflows;
  end;
  
  {$ENDREGION}
  
  {$REGION '特征提取'}
  
  /// <summary>工作流特征向�?/summary>
  TWorkflowFeatures = record
    WorkflowId: string;
    SkillCount: Integer;
    HasConditional: Boolean;
    HasLoop: Boolean;
    HasParallel: Boolean;
    HasErrorHandler: Boolean;
    AvgSkillComplexity: Double;
    CategoryVector: TArray<Double>;
    SkillTypeVector: TArray<Double>;
    
    function ToVector: TArray<Double>;
    function CosineSimilarity(const AOther: TWorkflowFeatures): Double;
  end;
  
  /// <summary>特征提取�?/summary>
  TFeatureExtractor = class
  private
    FCategoryIndex: TDictionary<string, Integer>;
    FSkillTypeIndex: TDictionary<string, Integer>;
    FVectorSize: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure BuildIndex(const AWorkflows: TArray<TJSONObject>);
    function ExtractFeatures(AWorkflow: TJSONObject): TWorkflowFeatures;
    function ExtractSkillFeatures(ASkill: TJSONObject): TArray<Double>;
    
    property VectorSize: Integer read FVectorSize;
  end;
  
  {$ENDREGION}
  
  {$REGION '推荐引擎'}
  
  /// <summary>协同过滤推荐�?/summary>
  TCollaborativeFilter = class
  private
    FUserItemMatrix: TDictionary<string, TDictionary<string, Double>>;
    FItemSimilarity: TDictionary<string, TDictionary<string, Double>>;
    FLock: TCriticalSection;
    
    function ComputeItemSimilarity(const AItem1, AItem2: string): Double;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddInteraction(const AUserId, AItemId: string; ARating: Double);
    procedure BuildSimilarityMatrix;
    function Recommend(const AUserId: string; ATopN: Integer): TArray<TPair<string, Double>>;
    function GetSimilarItems(const AItemId: string; ATopN: Integer): TArray<TPair<string, Double>>;
  end;
  
  /// <summary>内容推荐�?/summary>
  TContentBasedRecommender = class
  private
    FFeatureExtractor: TFeatureExtractor;
    FWorkflowFeatures: TDictionary<string, TWorkflowFeatures>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure IndexWorkflow(const AWorkflowId: string; AWorkflow: TJSONObject);
    procedure RemoveWorkflow(const AWorkflowId: string);
    function FindSimilar(const AWorkflowId: string; ATopN: Integer): TArray<TPair<string, Double>>;
    function FindByFeatures(const AFeatures: TWorkflowFeatures; ATopN: Integer): TArray<TPair<string, Double>>;
  end;
  
  /// <summary>混合推荐�?/summary>
  THybridRecommender = class
  private
    FCollaborative: TCollaborativeFilter;
    FContentBased: TContentBasedRecommender;
    FCollaborativeWeight: Double;
    FContentWeight: Double;
  public
    constructor Create(ACollaborativeWeight: Double = 0.6; AContentWeight: Double = 0.4);
    destructor Destroy; override;
    
    function Recommend(const AUserId: string; const AContext: TJSONObject;
      ATopN: Integer): TArray<TRecommendation>;
  end;
  
  {$ENDREGION}
  
  {$REGION '优化建议生成�?}
  
  /// <summary>优化类型</summary>
  TOptimizationType = (
    otParallelize,        // 并行�?
    otCaching,            // 添加缓存
    otBatching,           // 批处�?
    otErrorHandling,      // 错误处理
    otTimeout,            // 超时设置
    otRetry,              // 重试策略
    otSkillReplacement,   // Skill 替换
    otRemoveRedundant     // 移除冗余
  );
  
  /// <summary>优化建议</summary>
  TOptimizationSuggestion = record
    OptType: TOptimizationType;
    TargetStepId: string;
    Description: string;
    ExpectedImprovement: Double;
    Priority: Integer;
    AutoApplicable: Boolean;
  end;
  
  /// <summary>优化分析�?/summary>
  TOptimizationAnalyzer = class
  private
    function AnalyzeParallelization(AWorkflow: TJSONObject): TArray<TOptimizationSuggestion>;
    function AnalyzeCaching(AWorkflow: TJSONObject; AStats: TWorkflowStats): TArray<TOptimizationSuggestion>;
    function AnalyzeErrorHandling(AWorkflow: TJSONObject): TArray<TOptimizationSuggestion>;
    function AnalyzePerformance(AWorkflow: TJSONObject; AStats: TWorkflowStats): TArray<TOptimizationSuggestion>;
    function AnalyzeRedundancy(AWorkflow: TJSONObject): TArray<TOptimizationSuggestion>;
  public
    function Analyze(AWorkflow: TJSONObject; AStats: TWorkflowStats): TArray<TOptimizationSuggestion>;
    function GenerateRecommendations(const ASuggestions: TArray<TOptimizationSuggestion>): TArray<TRecommendation>;
  end;
  
  {$ENDREGION}
  
  {$REGION '错误模式分析'}
  
  /// <summary>错误模式</summary>
  TErrorPattern = record
    PatternId: string;
    ErrorType: string;
    Frequency: Integer;
    AffectedSteps: TArray<string>;
    CommonCauses: TArray<string>;
    SuggestedFixes: TArray<string>;
    PreventionTips: TArray<string>;
  end;
  
  /// <summary>错误模式分析�?/summary>
  TErrorPatternAnalyzer = class
  private
    FPatterns: TDictionary<string, TErrorPattern>;
    FErrorHistory: TList<TJSONObject>;
    FMaxHistory: Integer;
    FLock: TCriticalSection;
    
    function ClusterErrors: TArray<TArray<TJSONObject>>;
    function ExtractPattern(const ACluster: TArray<TJSONObject>): TErrorPattern;
  public
    constructor Create(AMaxHistory: Integer = 10000);
    destructor Destroy; override;
    
    procedure RecordError(AError: TJSONObject);
    procedure AnalyzePatterns;
    function GetPatterns: TArray<TErrorPattern>;
    function MatchPattern(AError: TJSONObject): TErrorPattern;
    function GeneratePreventionRecommendations(const AWorkflowId: string): TArray<TRecommendation>;
  end;
  
  {$ENDREGION}
  
  {$REGION '推荐服务'}
  
  /// <summary>推荐上下�?/summary>
  TRecommendationContext = record
    UserId: string;
    CurrentWorkflowId: string;
    CurrentStep: string;
    RecentErrors: TArray<string>;
    SessionDuration: Integer;
    Intent: string;
  end;
  
  /// <summary>推荐服务</summary>
  TRecommendationService = class
  private
    FHybridRecommender: THybridRecommender;
    FOptimizationAnalyzer: TOptimizationAnalyzer;
    FErrorPatternAnalyzer: TErrorPatternAnalyzer;
    FUserPreferences: TDictionary<string, TUserPreferences>;
    FWorkflowStats: TDictionary<string, TWorkflowStats>;
    FEnabled: Boolean;
    FLock: TCriticalSection;
    
    function GetUserPreferences(const AUserId: string): TUserPreferences;
    function GetWorkflowStats(const AWorkflowId: string): TWorkflowStats;
  public
    constructor Create;
    destructor Destroy; override;
    
    // 推荐获取
    function GetTemplateRecommendations(const AContext: TRecommendationContext;
      AMaxResults: Integer = 5): TArray<TRecommendation>;
    function GetSkillRecommendations(const AContext: TRecommendationContext;
      AMaxResults: Integer = 5): TArray<TRecommendation>;
    function GetOptimizationRecommendations(const AWorkflowId: string;
      AMaxResults: Integer = 5): TArray<TRecommendation>;
    function GetErrorPreventionRecommendations(const AWorkflowId: string;
      AMaxResults: Integer = 5): TArray<TRecommendation>;
    function GetSimilarWorkflows(const AWorkflowId: string;
      AMaxResults: Integer = 5): TArray<TRecommendation>;
    
    // 综合推荐
    function GetAllRecommendations(const AContext: TRecommendationContext;
      AMaxResults: Integer = 10): TArray<TRecommendation>;
    
    // 数据录入
    procedure RecordUserBehavior(const AEvent: TUserBehaviorEvent);
    procedure RecordWorkflowExecution(const AWorkflowId: string;
      ADurationMS: Integer; ASuccess: Boolean);
    procedure RecordError(const AWorkflowId, AStepId, AErrorType, AErrorMessage: string);
    
    // 索引管理
    procedure IndexWorkflow(const AWorkflowId: string; AWorkflow: TJSONObject);
    procedure RemoveWorkflow(const AWorkflowId: string);
    procedure RebuildIndex;
    
    // 反馈
    procedure RecordFeedback(const ARecommendationId: string; AAccepted: Boolean;
      const AFeedback: string = '');
    
    property Enabled: Boolean read FEnabled write FEnabled;
  end;
  
  {$ENDREGION}
  
  {$REGION '模板推荐�?}
  
  /// <summary>工作流模�?/summary>
  TWorkflowTemplate = record
    TemplateId: string;
    Name: string;
    Description: string;
    Category: string;
    Tags: TArray<string>;
    Complexity: Integer;
    UsageCount: Int64;
    Rating: Double;
    Definition: TJSONObject;
  end;
  
  /// <summary>模板推荐�?/summary>
  TTemplateRecommender = class
  private
    FTemplates: TDictionary<string, TWorkflowTemplate>;
    FFeatureExtractor: TFeatureExtractor;
    FPopularTemplates: TArray<string>;
    FLock: TCriticalSection;
    
    function ScoreTemplate(const ATemplate: TWorkflowTemplate;
      const AContext: TRecommendationContext; APrefs: TUserPreferences): Double;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure RegisterTemplate(const ATemplate: TWorkflowTemplate);
    procedure UnregisterTemplate(const ATemplateId: string);
    procedure UpdatePopularity;
    
    function RecommendByContext(const AContext: TRecommendationContext;
      APrefs: TUserPreferences; AMaxResults: Integer): TArray<TRecommendation>;
    function RecommendByIntent(const AIntent: string;
      AMaxResults: Integer): TArray<TRecommendation>;
    function RecommendPopular(AMaxResults: Integer): TArray<TRecommendation>;
    function SearchTemplates(const AQuery: string;
      AMaxResults: Integer): TArray<TRecommendation>;
  end;
  
  {$ENDREGION}

implementation

uses
  System.Hash, System.StrUtils;

{$REGION 'TRecommendation'}

constructor TRecommendation.Create;
begin
  inherited Create;
  FId := TGUID.NewGuid.ToString;
  FMetadata := TDictionary<string, string>.Create;
  FActions := TStringList.Create;
  FCreatedAt := Now;
  FScore := 0;
  FConfidence := clMedium;
end;

destructor TRecommendation.Destroy;
begin
  FActions.Free;
  FMetadata.Free;
  inherited;
end;

function TRecommendation.ToJSON: TJSONObject;
var
  MetaObj: TJSONObject;
  ActionsArr: TJSONArray;
  Key: string;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('type', Integer(FType));
  Result.AddPair('title', FTitle);
  Result.AddPair('description', FDescription);
  Result.AddPair('score', FScore);
  Result.AddPair('confidence', Integer(FConfidence));
  Result.AddPair('createdAt', DateTimeToStr(FCreatedAt));
  
  MetaObj := TJSONObject.Create;
  for Key in FMetadata.Keys do
    MetaObj.AddPair(Key, FMetadata[Key]);
  Result.AddPair('metadata', MetaObj);
  
  ActionsArr := TJSONArray.Create;
  for I := 0 to FActions.Count - 1 do
    ActionsArr.Add(FActions[I]);
  Result.AddPair('actions', ActionsArr);
end;

class function TRecommendation.FromJSON(AJSON: TJSONObject): TRecommendation;
var
  MetaObj: TJSONObject;
  ActionsArr: TJSONArray;
  Pair: TJSONPair;
  I: Integer;
begin
  Result := TRecommendation.Create;
  Result.FId := AJSON.GetValue<string>('id', Result.FId);
  Result.FType := TRecommendationType(AJSON.GetValue<Integer>('type', 0));
  Result.FTitle := AJSON.GetValue<string>('title', '');
  Result.FDescription := AJSON.GetValue<string>('description', '');
  Result.FScore := AJSON.GetValue<Double>('score', 0);
  Result.FConfidence := TConfidenceLevel(AJSON.GetValue<Integer>('confidence', 1));
  
  if AJSON.TryGetValue<TJSONObject>('metadata', MetaObj) then
  begin
    for Pair in MetaObj do
      Result.FMetadata.Add(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;
  
  if AJSON.TryGetValue<TJSONArray>('actions', ActionsArr) then
  begin
    for I := 0 to ActionsArr.Count - 1 do
      Result.FActions.Add(ActionsArr.Items[I].Value);
  end;
end;

{$ENDREGION}

{$REGION 'TUserPreferences'}

constructor TUserPreferences.Create(const AUserId: string);
begin
  inherited Create;
  FUserId := AUserId;
  FPreferredSkills := TStringList.Create;
  FPreferredCategories := TStringList.Create;
  FRecentWorkflows := TStringList.Create;
  FSkillUsageCount := TDictionary<string, Integer>.Create;
  FLastUpdated := Now;
end;

destructor TUserPreferences.Destroy;
begin
  FSkillUsageCount.Free;
  FRecentWorkflows.Free;
  FPreferredCategories.Free;
  FPreferredSkills.Free;
  inherited;
end;

procedure TUserPreferences.UpdateFromBehavior(const AEvent: TUserBehaviorEvent);
var
  Count: Integer;
begin
  // 更新 Skill 使用计数
  if AEvent.SkillId <> '' then
  begin
    if FSkillUsageCount.TryGetValue(AEvent.SkillId, Count) then
      FSkillUsageCount[AEvent.SkillId] := Count + 1
    else
      FSkillUsageCount.Add(AEvent.SkillId, 1);
  end;
  
  // 更新最近工作流
  if AEvent.WorkflowId <> '' then
  begin
    if FRecentWorkflows.IndexOf(AEvent.WorkflowId) >= 0 then
      FRecentWorkflows.Delete(FRecentWorkflows.IndexOf(AEvent.WorkflowId));
    FRecentWorkflows.Insert(0, AEvent.WorkflowId);
    while FRecentWorkflows.Count > 20 do
      FRecentWorkflows.Delete(FRecentWorkflows.Count - 1);
  end;
  
  FLastUpdated := Now;
end;

function TUserPreferences.GetTopSkills(ACount: Integer): TArray<string>;
var
  Sorted: TList<TPair<string, Integer>>;
  Pair: TPair<string, Integer>;
  I: Integer;
begin
  Sorted := TList<TPair<string, Integer>>.Create;
  try
    for Pair in FSkillUsageCount do
      Sorted.Add(Pair);
    
    Sorted.Sort(TComparer<TPair<string, Integer>>.Construct(
      function(const L, R: TPair<string, Integer>): Integer
      begin
        Result := R.Value - L.Value;
      end
    ));
    
    SetLength(Result, Min(ACount, Sorted.Count));
    for I := 0 to High(Result) do
      Result[I] := Sorted[I].Key;
  finally
    Sorted.Free;
  end;
end;

function TUserPreferences.GetTopCategories(ACount: Integer): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Min(ACount, FPreferredCategories.Count));
  for I := 0 to High(Result) do
    Result[I] := FPreferredCategories[I];
end;

{$ENDREGION}

{$REGION 'TWorkflowFeatures'}

function TWorkflowFeatures.ToVector: TArray<Double>;
var
  BaseLen, TotalLen, I: Integer;
begin
  BaseLen := 6; // 基础特征�?
  TotalLen := BaseLen + Length(CategoryVector) + Length(SkillTypeVector);
  SetLength(Result, TotalLen);
  
  Result[0] := SkillCount / 20.0; // 归一�?
  Result[1] := IfThen(HasConditional, 1.0, 0.0);
  Result[2] := IfThen(HasLoop, 1.0, 0.0);
  Result[3] := IfThen(HasParallel, 1.0, 0.0);
  Result[4] := IfThen(HasErrorHandler, 1.0, 0.0);
  Result[5] := AvgSkillComplexity / 10.0;
  
  for I := 0 to High(CategoryVector) do
    Result[BaseLen + I] := CategoryVector[I];
    
  for I := 0 to High(SkillTypeVector) do
    Result[BaseLen + Length(CategoryVector) + I] := SkillTypeVector[I];
end;

function TWorkflowFeatures.CosineSimilarity(const AOther: TWorkflowFeatures): Double;
var
  V1, V2: TArray<Double>;
  DotProduct, Norm1, Norm2: Double;
  I: Integer;
begin
  V1 := ToVector;
  V2 := AOther.ToVector;
  
  if Length(V1) <> Length(V2) then
    Exit(0);
    
  DotProduct := 0;
  Norm1 := 0;
  Norm2 := 0;
  
  for I := 0 to High(V1) do
  begin
    DotProduct := DotProduct + V1[I] * V2[I];
    Norm1 := Norm1 + V1[I] * V1[I];
    Norm2 := Norm2 + V2[I] * V2[I];
  end;
  
  if (Norm1 = 0) or (Norm2 = 0) then
    Result := 0
  else
    Result := DotProduct / (Sqrt(Norm1) * Sqrt(Norm2));
end;

{$ENDREGION}

{$REGION 'TFeatureExtractor'}

constructor TFeatureExtractor.Create;
begin
  inherited Create;
  FCategoryIndex := TDictionary<string, Integer>.Create;
  FSkillTypeIndex := TDictionary<string, Integer>.Create;
  FVectorSize := 0;
end;

destructor TFeatureExtractor.Destroy;
begin
  FSkillTypeIndex.Free;
  FCategoryIndex.Free;
  inherited;
end;

procedure TFeatureExtractor.BuildIndex(const AWorkflows: TArray<TJSONObject>);
var
  Workflow, Step: TJSONObject;
  Steps: TJSONArray;
  Category, SkillType: string;
  I, J: Integer;
begin
  FCategoryIndex.Clear;
  FSkillTypeIndex.Clear;
  
  for Workflow in AWorkflows do
  begin
    // 提取类别
    Category := Workflow.GetValue<string>('category', 'default');
    if not FCategoryIndex.ContainsKey(Category) then
      FCategoryIndex.Add(Category, FCategoryIndex.Count);
    
    // 提取 Skill 类型
    if Workflow.TryGetValue<TJSONArray>('steps', Steps) then
    begin
      for J := 0 to Steps.Count - 1 do
      begin
        Step := Steps.Items[J] as TJSONObject;
        SkillType := Step.GetValue<string>('skillType', 'unknown');
        if not FSkillTypeIndex.ContainsKey(SkillType) then
          FSkillTypeIndex.Add(SkillType, FSkillTypeIndex.Count);
      end;
    end;
  end;
  
  FVectorSize := 6 + FCategoryIndex.Count + FSkillTypeIndex.Count;
end;

function TFeatureExtractor.ExtractFeatures(AWorkflow: TJSONObject): TWorkflowFeatures;
var
  Steps: TJSONArray;
  Step: TJSONObject;
  Category, SkillType, StepType: string;
  I, Idx: Integer;
  TotalComplexity: Double;
begin
  Result.WorkflowId := AWorkflow.GetValue<string>('id', '');
  Result.SkillCount := 0;
  Result.HasConditional := False;
  Result.HasLoop := False;
  Result.HasParallel := False;
  Result.HasErrorHandler := False;
  Result.AvgSkillComplexity := 0;
  
  // 初始化向�?
  SetLength(Result.CategoryVector, FCategoryIndex.Count);
  SetLength(Result.SkillTypeVector, FSkillTypeIndex.Count);
  
  // 类别向量
  Category := AWorkflow.GetValue<string>('category', 'default');
  if FCategoryIndex.TryGetValue(Category, Idx) then
    Result.CategoryVector[Idx] := 1.0;
  
  // 分析步骤
  TotalComplexity := 0;
  if AWorkflow.TryGetValue<TJSONArray>('steps', Steps) then
  begin
    Result.SkillCount := Steps.Count;
    
    for I := 0 to Steps.Count - 1 do
    begin
      Step := Steps.Items[I] as TJSONObject;
      StepType := Step.GetValue<string>('type', '');
      
      // 检测特殊步骤类�?
      if StepType = 'condition' then Result.HasConditional := True
      else if StepType = 'loop' then Result.HasLoop := True
      else if StepType = 'parallel' then Result.HasParallel := True
      else if StepType = 'error_handler' then Result.HasErrorHandler := True;
      
      // Skill 类型向量
      SkillType := Step.GetValue<string>('skillType', 'unknown');
      if FSkillTypeIndex.TryGetValue(SkillType, Idx) then
        Result.SkillTypeVector[Idx] := Result.SkillTypeVector[Idx] + 1;
      
      // 复杂度估�?
      TotalComplexity := TotalComplexity + Step.GetValue<Double>('complexity', 1.0);
    end;
    
    if Result.SkillCount > 0 then
      Result.AvgSkillComplexity := TotalComplexity / Result.SkillCount;
      
    // 归一�?Skill 类型向量
    for I := 0 to High(Result.SkillTypeVector) do
      if Result.SkillCount > 0 then
        Result.SkillTypeVector[I] := Result.SkillTypeVector[I] / Result.SkillCount;
  end;
end;

function TFeatureExtractor.ExtractSkillFeatures(ASkill: TJSONObject): TArray<Double>;
begin
  // 简化实�?
  SetLength(Result, 10);
  Result[0] := ASkill.GetValue<Double>('complexity', 1.0) / 10.0;
  Result[1] := ASkill.GetValue<Integer>('inputCount', 0) / 10.0;
  Result[2] := ASkill.GetValue<Integer>('outputCount', 0) / 10.0;
  Result[3] := IfThen(ASkill.GetValue<Boolean>('async', False), 1.0, 0.0);
  Result[4] := IfThen(ASkill.GetValue<Boolean>('cacheable', False), 1.0, 0.0);
end;

{$ENDREGION}

{$REGION 'TCollaborativeFilter'}

constructor TCollaborativeFilter.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FUserItemMatrix := TDictionary<string, TDictionary<string, Double>>.Create;
  FItemSimilarity := TDictionary<string, TDictionary<string, Double>>.Create;
end;

destructor TCollaborativeFilter.Destroy;
var
  Dict: TDictionary<string, Double>;
begin
  for Dict in FUserItemMatrix.Values do
    Dict.Free;
  FUserItemMatrix.Free;
  
  for Dict in FItemSimilarity.Values do
    Dict.Free;
  FItemSimilarity.Free;
  
  FLock.Free;
  inherited;
end;

procedure TCollaborativeFilter.AddInteraction(const AUserId, AItemId: string; ARating: Double);
var
  UserItems: TDictionary<string, Double>;
begin
  FLock.Enter;
  try
    if not FUserItemMatrix.TryGetValue(AUserId, UserItems) then
    begin
      UserItems := TDictionary<string, Double>.Create;
      FUserItemMatrix.Add(AUserId, UserItems);
    end;
    UserItems.AddOrSetValue(AItemId, ARating);
  finally
    FLock.Leave;
  end;
end;

function TCollaborativeFilter.ComputeItemSimilarity(const AItem1, AItem2: string): Double;
var
  UserId: string;
  UserItems: TDictionary<string, Double>;
  Rating1, Rating2: Double;
  Sum, Count: Double;
begin
  Sum := 0;
  Count := 0;
  
  for UserId in FUserItemMatrix.Keys do
  begin
    UserItems := FUserItemMatrix[UserId];
    if UserItems.TryGetValue(AItem1, Rating1) and UserItems.TryGetValue(AItem2, Rating2) then
    begin
      Sum := Sum + Rating1 * Rating2;
      Count := Count + 1;
    end;
  end;
  
  if Count > 0 then
    Result := Sum / Count
  else
    Result := 0;
end;

procedure TCollaborativeFilter.BuildSimilarityMatrix;
var
  Items: TList<string>;
  UserItems: TDictionary<string, Double>;
  ItemId: string;
  I, J: Integer;
  Similarity: Double;
  SimilarItems: TDictionary<string, Double>;
begin
  FLock.Enter;
  try
    // 收集所有物�?
    Items := TList<string>.Create;
    try
      for UserItems in FUserItemMatrix.Values do
        for ItemId in UserItems.Keys do
          if Items.IndexOf(ItemId) < 0 then
            Items.Add(ItemId);
      
      // 清空旧的相似度矩�?
      for SimilarItems in FItemSimilarity.Values do
        SimilarItems.Free;
      FItemSimilarity.Clear;
      
      // 计算相似�?
      for I := 0 to Items.Count - 1 do
      begin
        SimilarItems := TDictionary<string, Double>.Create;
        FItemSimilarity.Add(Items[I], SimilarItems);
        
        for J := 0 to Items.Count - 1 do
        begin
          if I <> J then
          begin
            Similarity := ComputeItemSimilarity(Items[I], Items[J]);
            if Similarity > 0.1 then
              SimilarItems.Add(Items[J], Similarity);
          end;
        end;
      end;
    finally
      Items.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TCollaborativeFilter.Recommend(const AUserId: string; ATopN: Integer): TArray<TPair<string, Double>>;
var
  UserItems: TDictionary<string, Double>;
  Scores: TDictionary<string, Double>;
  ItemId, SimilarItem: string;
  Rating, Similarity, Score: Double;
  SimilarItems: TDictionary<string, Double>;
  SortedScores: TList<TPair<string, Double>>;
  I: Integer;
begin
  SetLength(Result, 0);
  
  FLock.Enter;
  try
    if not FUserItemMatrix.TryGetValue(AUserId, UserItems) then
      Exit;
    
    Scores := TDictionary<string, Double>.Create;
    try
      // 基于用户已交互物品的相似物品计算分数
      for ItemId in UserItems.Keys do
      begin
        Rating := UserItems[ItemId];
        if FItemSimilarity.TryGetValue(ItemId, SimilarItems) then
        begin
          for SimilarItem in SimilarItems.Keys do
          begin
            if not UserItems.ContainsKey(SimilarItem) then
            begin
              Similarity := SimilarItems[SimilarItem];
              if Scores.TryGetValue(SimilarItem, Score) then
                Scores[SimilarItem] := Score + Rating * Similarity
              else
                Scores.Add(SimilarItem, Rating * Similarity);
            end;
          end;
        end;
      end;
      
      // 排序
      SortedScores := TList<TPair<string, Double>>.Create;
      try
        for ItemId in Scores.Keys do
          SortedScores.Add(TPair<string, Double>.Create(ItemId, Scores[ItemId]));
        
        SortedScores.Sort(TComparer<TPair<string, Double>>.Construct(
          function(const L, R: TPair<string, Double>): Integer
          begin
            if R.Value > L.Value then Result := 1
            else if R.Value < L.Value then Result := -1
            else Result := 0;
          end
        ));
        
        SetLength(Result, Min(ATopN, SortedScores.Count));
        for I := 0 to High(Result) do
          Result[I] := SortedScores[I];
      finally
        SortedScores.Free;
      end;
    finally
      Scores.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TCollaborativeFilter.GetSimilarItems(const AItemId: string; ATopN: Integer): TArray<TPair<string, Double>>;
var
  SimilarItems: TDictionary<string, Double>;
  SortedItems: TList<TPair<string, Double>>;
  ItemId: string;
  I: Integer;
begin
  SetLength(Result, 0);
  
  FLock.Enter;
  try
    if not FItemSimilarity.TryGetValue(AItemId, SimilarItems) then
      Exit;
    
    SortedItems := TList<TPair<string, Double>>.Create;
    try
      for ItemId in SimilarItems.Keys do
        SortedItems.Add(TPair<string, Double>.Create(ItemId, SimilarItems[ItemId]));
      
      SortedItems.Sort(TComparer<TPair<string, Double>>.Construct(
        function(const L, R: TPair<string, Double>): Integer
        begin
          if R.Value > L.Value then Result := 1
          else if R.Value < L.Value then Result := -1
          else Result := 0;
        end
      ));
      
      SetLength(Result, Min(ATopN, SortedItems.Count));
      for I := 0 to High(Result) do
        Result[I] := SortedItems[I];
    finally
      SortedItems.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'TContentBasedRecommender'}

constructor TContentBasedRecommender.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFeatureExtractor := TFeatureExtractor.Create;
  FWorkflowFeatures := TDictionary<string, TWorkflowFeatures>.Create;
end;

destructor TContentBasedRecommender.Destroy;
begin
  FWorkflowFeatures.Free;
  FFeatureExtractor.Free;
  FLock.Free;
  inherited;
end;

procedure TContentBasedRecommender.IndexWorkflow(const AWorkflowId: string; AWorkflow: TJSONObject);
var
  Features: TWorkflowFeatures;
begin
  FLock.Enter;
  try
    Features := FFeatureExtractor.ExtractFeatures(AWorkflow);
    FWorkflowFeatures.AddOrSetValue(AWorkflowId, Features);
  finally
    FLock.Leave;
  end;
end;

procedure TContentBasedRecommender.RemoveWorkflow(const AWorkflowId: string);
begin
  FLock.Enter;
  try
    FWorkflowFeatures.Remove(AWorkflowId);
  finally
    FLock.Leave;
  end;
end;

function TContentBasedRecommender.FindSimilar(const AWorkflowId: string; ATopN: Integer): TArray<TPair<string, Double>>;
var
  TargetFeatures, Features: TWorkflowFeatures;
  Similarities: TList<TPair<string, Double>>;
  WorkflowId: string;
  Similarity: Double;
  I: Integer;
begin
  SetLength(Result, 0);
  
  FLock.Enter;
  try
    if not FWorkflowFeatures.TryGetValue(AWorkflowId, TargetFeatures) then
      Exit;
    
    Similarities := TList<TPair<string, Double>>.Create;
    try
      for WorkflowId in FWorkflowFeatures.Keys do
      begin
        if WorkflowId <> AWorkflowId then
        begin
          Features := FWorkflowFeatures[WorkflowId];
          Similarity := TargetFeatures.CosineSimilarity(Features);
          if Similarity > 0.1 then
            Similarities.Add(TPair<string, Double>.Create(WorkflowId, Similarity));
        end;
      end;
      
      Similarities.Sort(TComparer<TPair<string, Double>>.Construct(
        function(const L, R: TPair<string, Double>): Integer
        begin
          if R.Value > L.Value then Result := 1
          else if R.Value < L.Value then Result := -1
          else Result := 0;
        end
      ));
      
      SetLength(Result, Min(ATopN, Similarities.Count));
      for I := 0 to High(Result) do
        Result[I] := Similarities[I];
    finally
      Similarities.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TContentBasedRecommender.FindByFeatures(const AFeatures: TWorkflowFeatures; ATopN: Integer): TArray<TPair<string, Double>>;
var
  Features: TWorkflowFeatures;
  Similarities: TList<TPair<string, Double>>;
  WorkflowId: string;
  Similarity: Double;
  I: Integer;
begin
  SetLength(Result, 0);
  
  FLock.Enter;
  try
    Similarities := TList<TPair<string, Double>>.Create;
    try
      for WorkflowId in FWorkflowFeatures.Keys do
      begin
        Features := FWorkflowFeatures[WorkflowId];
        Similarity := AFeatures.CosineSimilarity(Features);
        if Similarity > 0.1 then
          Similarities.Add(TPair<string, Double>.Create(WorkflowId, Similarity));
      end;
      
      Similarities.Sort(TComparer<TPair<string, Double>>.Construct(
        function(const L, R: TPair<string, Double>): Integer
        begin
          if R.Value > L.Value then Result := 1
          else if R.Value < L.Value then Result := -1
          else Result := 0;
        end
      ));
      
      SetLength(Result, Min(ATopN, Similarities.Count));
      for I := 0 to High(Result) do
        Result[I] := Similarities[I];
    finally
      Similarities.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

{$ENDREGION}

{$REGION 'THybridRecommender'}

constructor THybridRecommender.Create(ACollaborativeWeight, AContentWeight: Double);
begin
  inherited Create;
  FCollaborative := TCollaborativeFilter.Create;
  FContentBased := TContentBasedRecommender.Create;
  FCollaborativeWeight := ACollaborativeWeight;
  FContentWeight := AContentWeight;
end;

destructor THybridRecommender.Destroy;
begin
  FContentBased.Free;
  FCollaborative.Free;
  inherited;
end;

function THybridRecommender.Recommend(const AUserId: string; const AContext: TJSONObject;
  ATopN: Integer): TArray<TRecommendation>;
var
  CollabResults, ContentResults: TArray<TPair<string, Double>>;
  CombinedScores: TDictionary<string, Double>;
  Pair: TPair<string, Double>;
  Score: Double;
  SortedResults: TList<TPair<string, Double>>;
  Rec: TRecommendation;
  I: Integer;
begin
  SetLength(Result, 0);
  
  // 获取协同过滤结果
  CollabResults := FCollaborative.Recommend(AUserId, ATopN * 2);
  
  // 获取基于内容的结�?
  if Assigned(AContext) and AContext.TryGetValue<string>('currentWorkflowId', Score) then
    ContentResults := FContentBased.FindSimilar(AContext.GetValue<string>('currentWorkflowId'), ATopN * 2)
  else
    SetLength(ContentResults, 0);
  
  // 合并分数
  CombinedScores := TDictionary<string, Double>.Create;
  try
    for Pair in CollabResults do
    begin
      if CombinedScores.TryGetValue(Pair.Key, Score) then
        CombinedScores[Pair.Key] := Score + Pair.Value * FCollaborativeWeight
      else
        CombinedScores.Add(Pair.Key, Pair.Value * FCollaborativeWeight);
    end;
    
    for Pair in ContentResults do
    begin
      if CombinedScores.TryGetValue(Pair.Key, Score) then
        CombinedScores[Pair.Key] := Score + Pair.Value * FContentWeight
      else
        CombinedScores.Add(Pair.Key, Pair.Value * FContentWeight);
    end;
    
    // 排序并生成推�?
    SortedResults := TList<TPair<string, Double>>.Create;
    try
      for Pair.Key in CombinedScores.Keys do
        SortedResults.Add(TPair<string, Double>.Create(Pair.Key, CombinedScores[Pair.Key]));
      
      SortedResults.Sort(TComparer<TPair<string, Double>>.Construct(
        function(const L, R: TPair<string, Double>): Integer
        begin
          if R.Value > L.Value then Result := 1
          else if R.Value < L.Value then Result := -1
          else Result := 0;
        end
      ));
      
      SetLength(Result, Min(ATopN, SortedResults.Count));
      for I := 0 to High(Result) do
      begin
        Rec := TRecommendation.Create;
        Rec.RecommendationType := rtWorkflowTemplate;
        Rec.Title := 'Recommended Workflow';
        Rec.Metadata.Add('workflowId', SortedResults[I].Key);
        Rec.Score := SortedResults[I].Value;
        
        if Rec.Score > 0.9 then Rec.Confidence := clVeryHigh
        else if Rec.Score > 0.75 then Rec.Confidence := clHigh
        else if Rec.Score > 0.5 then Rec.Confidence := clMedium
        else Rec.Confidence := clLow;
        
        Result[I] := Rec;
      end;
    finally
      SortedResults.Free;
    end;
  finally
    CombinedScores.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TOptimizationAnalyzer'}

function TOptimizationAnalyzer.AnalyzeParallelization(AWorkflow: TJSONObject): TArray<TOptimizationSuggestion>;
var
  Steps: TJSONArray;
  Step: TJSONObject;
  Dependencies: TDictionary<string, TStringList>;
  StepId, DepId: string;
  DepArr: TJSONArray;
  IndependentSteps: TStringList;
  I, J: Integer;
  Suggestion: TOptimizationSuggestion;
  ResultList: TList<TOptimizationSuggestion>;
begin
  SetLength(Result, 0);
  
  if not AWorkflow.TryGetValue<TJSONArray>('steps', Steps) then
    Exit;
  
  Dependencies := TDictionary<string, TStringList>.Create;
  IndependentSteps := TStringList.Create;
  ResultList := TList<TOptimizationSuggestion>.Create;
  try
    // 构建依赖�?
    for I := 0 to Steps.Count - 1 do
    begin
      Step := Steps.Items[I] as TJSONObject;
      StepId := Step.GetValue<string>('id', '');
      Dependencies.Add(StepId, TStringList.Create);
      
      if Step.TryGetValue<TJSONArray>('dependencies', DepArr) then
      begin
        for J := 0 to DepArr.Count - 1 do
          Dependencies[StepId].Add(DepArr.Items[J].Value);
      end;
    end;
    
    // 找出可并行的步骤�?
    for StepId in Dependencies.Keys do
    begin
      if Dependencies[StepId].Count = 0 then
        IndependentSteps.Add(StepId);
    end;
    
    // 如果有多个独立步骤，建议并行�?
    if IndependentSteps.Count > 1 then
    begin
      Suggestion.OptType := otParallelize;
      Suggestion.TargetStepId := '';
      Suggestion.Description := Format('可并行执�?%d 个独立步骤以提升性能', [IndependentSteps.Count]);
      Suggestion.ExpectedImprovement := (IndependentSteps.Count - 1) * 0.3;
      Suggestion.Priority := 1;
      Suggestion.AutoApplicable := True;
      ResultList.Add(Suggestion);
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
    IndependentSteps.Free;
    for StepId in Dependencies.Keys do
      Dependencies[StepId].Free;
    Dependencies.Free;
  end;
end;

function TOptimizationAnalyzer.AnalyzeCaching(AWorkflow: TJSONObject; AStats: TWorkflowStats): TArray<TOptimizationSuggestion>;
var
  Steps: TJSONArray;
  Step: TJSONObject;
  SkillType: string;
  CacheableSkills: TStringList;
  I: Integer;
  Suggestion: TOptimizationSuggestion;
  ResultList: TList<TOptimizationSuggestion>;
begin
  SetLength(Result, 0);
  
  if not AWorkflow.TryGetValue<TJSONArray>('steps', Steps) then
    Exit;
  
  CacheableSkills := TStringList.Create;
  ResultList := TList<TOptimizationSuggestion>.Create;
  try
    // 找出可缓存的步骤
    for I := 0 to Steps.Count - 1 do
    begin
      Step := Steps.Items[I] as TJSONObject;
      SkillType := Step.GetValue<string>('skillType', '');
      
      // 检查是否为可缓存的操作
      if (SkillType = 'http_request') or (SkillType = 'database_query') or
         (SkillType = 'file_read') then
      begin
        if not Step.GetValue<Boolean>('cached', False) then
          CacheableSkills.Add(Step.GetValue<string>('id', ''));
      end;
    end;
    
    // 如果执行频繁且有可缓存步�?
    if (AStats.TotalExecutions > 100) and (CacheableSkills.Count > 0) then
    begin
      Suggestion.OptType := otCaching;
      Suggestion.TargetStepId := CacheableSkills[0];
      Suggestion.Description := Format('�?%d 个步骤添加缓存可减少重复计算', [CacheableSkills.Count]);
      Suggestion.ExpectedImprovement := 0.4;
      Suggestion.Priority := 2;
      Suggestion.AutoApplicable := True;
      ResultList.Add(Suggestion);
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
    CacheableSkills.Free;
  end;
end;

function TOptimizationAnalyzer.AnalyzeErrorHandling(AWorkflow: TJSONObject): TArray<TOptimizationSuggestion>;
var
  Steps: TJSONArray;
  Step: TJSONObject;
  StepsWithoutHandler: TStringList;
  I: Integer;
  Suggestion: TOptimizationSuggestion;
  ResultList: TList<TOptimizationSuggestion>;
begin
  SetLength(Result, 0);
  
  if not AWorkflow.TryGetValue<TJSONArray>('steps', Steps) then
    Exit;
  
  StepsWithoutHandler := TStringList.Create;
  ResultList := TList<TOptimizationSuggestion>.Create;
  try
    for I := 0 to Steps.Count - 1 do
    begin
      Step := Steps.Items[I] as TJSONObject;
      if not Step.GetValue<Boolean>('hasErrorHandler', False) then
        StepsWithoutHandler.Add(Step.GetValue<string>('id', ''));
    end;
    
    if StepsWithoutHandler.Count > 0 then
    begin
      Suggestion.OptType := otErrorHandling;
      Suggestion.TargetStepId := '';
      Suggestion.Description := Format('%d 个步骤缺少错误处理器，建议添加以提高稳定�?, [StepsWithoutHandler.Count]);
      Suggestion.ExpectedImprovement := 0.2;
      Suggestion.Priority := 3;
      Suggestion.AutoApplicable := False;
      ResultList.Add(Suggestion);
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
    StepsWithoutHandler.Free;
  end;
end;

function TOptimizationAnalyzer.AnalyzePerformance(AWorkflow: TJSONObject; AStats: TWorkflowStats): TArray<TOptimizationSuggestion>;
var
  Suggestion: TOptimizationSuggestion;
  ResultList: TList<TOptimizationSuggestion>;
begin
  ResultList := TList<TOptimizationSuggestion>.Create;
  try
    // P95 延迟过高
    if AStats.P95DurationMS > AStats.AvgDurationMS * 3 then
    begin
      Suggestion.OptType := otTimeout;
      Suggestion.TargetStepId := '';
      Suggestion.Description := Format('P95 延迟 (%.0fms) 远高于平均�?(%.0fms)，建议添加超时控�?,
        [AStats.P95DurationMS, AStats.AvgDurationMS]);
      Suggestion.ExpectedImprovement := 0.3;
      Suggestion.Priority := 2;
      Suggestion.AutoApplicable := True;
      ResultList.Add(Suggestion);
    end;
    
    // 失败率高
    if (AStats.TotalExecutions > 10) and
       (AStats.FailureCount / AStats.TotalExecutions > 0.1) then
    begin
      Suggestion.OptType := otRetry;
      Suggestion.TargetStepId := '';
      Suggestion.Description := Format('失败�?%.1f%% 较高，建议添加重试策�?,
        [AStats.FailureCount / AStats.TotalExecutions * 100]);
      Suggestion.ExpectedImprovement := 0.5;
      Suggestion.Priority := 1;
      Suggestion.AutoApplicable := True;
      ResultList.Add(Suggestion);
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

function TOptimizationAnalyzer.AnalyzeRedundancy(AWorkflow: TJSONObject): TArray<TOptimizationSuggestion>;
var
  Steps: TJSONArray;
  Step: TJSONObject;
  SkillCounts: TDictionary<string, Integer>;
  SkillType: string;
  Count: Integer;
  Suggestion: TOptimizationSuggestion;
  ResultList: TList<TOptimizationSuggestion>;
  I: Integer;
begin
  SetLength(Result, 0);
  
  if not AWorkflow.TryGetValue<TJSONArray>('steps', Steps) then
    Exit;
  
  SkillCounts := TDictionary<string, Integer>.Create;
  ResultList := TList<TOptimizationSuggestion>.Create;
  try
    for I := 0 to Steps.Count - 1 do
    begin
      Step := Steps.Items[I] as TJSONObject;
      SkillType := Step.GetValue<string>('skillType', '');
      
      if SkillCounts.TryGetValue(SkillType, Count) then
        SkillCounts[SkillType] := Count + 1
      else
        SkillCounts.Add(SkillType, 1);
    end;
    
    for SkillType in SkillCounts.Keys do
    begin
      if SkillCounts[SkillType] > 2 then
      begin
        Suggestion.OptType := otRemoveRedundant;
        Suggestion.TargetStepId := '';
        Suggestion.Description := Format('检测到 %d 个相同类型的 %s 步骤，考虑合并或批处理',
          [SkillCounts[SkillType], SkillType]);
        Suggestion.ExpectedImprovement := 0.2;
        Suggestion.Priority := 4;
        Suggestion.AutoApplicable := False;
        ResultList.Add(Suggestion);
      end;
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
    SkillCounts.Free;
  end;
end;

function TOptimizationAnalyzer.Analyze(AWorkflow: TJSONObject; AStats: TWorkflowStats): TArray<TOptimizationSuggestion>;
var
  AllSuggestions: TList<TOptimizationSuggestion>;
  Suggestions: TArray<TOptimizationSuggestion>;
  S: TOptimizationSuggestion;
begin
  AllSuggestions := TList<TOptimizationSuggestion>.Create;
  try
    Suggestions := AnalyzeParallelization(AWorkflow);
    for S in Suggestions do AllSuggestions.Add(S);
    
    Suggestions := AnalyzeCaching(AWorkflow, AStats);
    for S in Suggestions do AllSuggestions.Add(S);
    
    Suggestions := AnalyzeErrorHandling(AWorkflow);
    for S in Suggestions do AllSuggestions.Add(S);
    
    Suggestions := AnalyzePerformance(AWorkflow, AStats);
    for S in Suggestions do AllSuggestions.Add(S);
    
    Suggestions := AnalyzeRedundancy(AWorkflow);
    for S in Suggestions do AllSuggestions.Add(S);
    
    // 按优先级排序
    AllSuggestions.Sort(TComparer<TOptimizationSuggestion>.Construct(
      function(const L, R: TOptimizationSuggestion): Integer
      begin
        Result := L.Priority - R.Priority;
      end
    ));
    
    Result := AllSuggestions.ToArray;
  finally
    AllSuggestions.Free;
  end;
end;

function TOptimizationAnalyzer.GenerateRecommendations(
  const ASuggestions: TArray<TOptimizationSuggestion>): TArray<TRecommendation>;
var
  I: Integer;
  Rec: TRecommendation;
begin
  SetLength(Result, Length(ASuggestions));
  
  for I := 0 to High(ASuggestions) do
  begin
    Rec := TRecommendation.Create;
    Rec.RecommendationType := rtOptimization;
    Rec.Title := '优化建议: ' + ASuggestions[I].Description;
    Rec.Description := ASuggestions[I].Description;
    Rec.Score := ASuggestions[I].ExpectedImprovement;
    Rec.Metadata.Add('optimizationType', IntToStr(Ord(ASuggestions[I].OptType)));
    Rec.Metadata.Add('targetStep', ASuggestions[I].TargetStepId);
    Rec.Metadata.Add('autoApplicable', BoolToStr(ASuggestions[I].AutoApplicable, True));
    
    if ASuggestions[I].ExpectedImprovement > 0.4 then
      Rec.Confidence := clHigh
    else if ASuggestions[I].ExpectedImprovement > 0.2 then
      Rec.Confidence := clMedium
    else
      Rec.Confidence := clLow;
    
    Result[I] := Rec;
  end;
end;

{$ENDREGION}

{$REGION 'TErrorPatternAnalyzer'}

constructor TErrorPatternAnalyzer.Create(AMaxHistory: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPatterns := TDictionary<string, TErrorPattern>.Create;
  FErrorHistory := TList<TJSONObject>.Create;
  FMaxHistory := AMaxHistory;
end;

destructor TErrorPatternAnalyzer.Destroy;
var
  Obj: TJSONObject;
begin
  for Obj in FErrorHistory do
    Obj.Free;
  FErrorHistory.Free;
  FPatterns.Free;
  FLock.Free;
  inherited;
end;

procedure TErrorPatternAnalyzer.RecordError(AError: TJSONObject);
begin
  FLock.Enter;
  try
    FErrorHistory.Add(AError.Clone as TJSONObject);
    while FErrorHistory.Count > FMaxHistory do
    begin
      FErrorHistory[0].Free;
      FErrorHistory.Delete(0);
    end;
  finally
    FLock.Leave;
  end;
end;

function TErrorPatternAnalyzer.ClusterErrors: TArray<TArray<TJSONObject>>;
var
  Clusters: TDictionary<string, TList<TJSONObject>>;
  Error: TJSONObject;
  ErrorType: string;
  ClusterList: TList<TJSONObject>;
  Key: string;
  I: Integer;
begin
  Clusters := TDictionary<string, TList<TJSONObject>>.Create;
  try
    // 简单按错误类型聚类
    for Error in FErrorHistory do
    begin
      ErrorType := Error.GetValue<string>('errorType', 'unknown');
      if not Clusters.TryGetValue(ErrorType, ClusterList) then
      begin
        ClusterList := TList<TJSONObject>.Create;
        Clusters.Add(ErrorType, ClusterList);
      end;
      ClusterList.Add(Error);
    end;
    
    SetLength(Result, Clusters.Count);
    I := 0;
    for Key in Clusters.Keys do
    begin
      Result[I] := Clusters[Key].ToArray;
      Clusters[Key].Free;
      Inc(I);
    end;
  finally
    Clusters.Free;
  end;
end;

function TErrorPatternAnalyzer.ExtractPattern(const ACluster: TArray<TJSONObject>): TErrorPattern;
var
  Error: TJSONObject;
  StepIds: TStringList;
  Causes: TStringList;
begin
  if Length(ACluster) = 0 then
    Exit;
  
  Result.PatternId := TGUID.NewGuid.ToString;
  Result.ErrorType := ACluster[0].GetValue<string>('errorType', 'unknown');
  Result.Frequency := Length(ACluster);
  
  StepIds := TStringList.Create;
  Causes := TStringList.Create;
  try
    StepIds.Sorted := True;
    StepIds.Duplicates := dupIgnore;
    Causes.Sorted := True;
    Causes.Duplicates := dupIgnore;
    
    for Error in ACluster do
    begin
      StepIds.Add(Error.GetValue<string>('stepId', ''));
      Causes.Add(Error.GetValue<string>('cause', ''));
    end;
    
    SetLength(Result.AffectedSteps, StepIds.Count);
    SetLength(Result.CommonCauses, Causes.Count);
    
    for var I := 0 to StepIds.Count - 1 do
      Result.AffectedSteps[I] := StepIds[I];
    for var I := 0 to Causes.Count - 1 do
      Result.CommonCauses[I] := Causes[I];
    
    // 生成建议修复方案
    SetLength(Result.SuggestedFixes, 1);
    Result.SuggestedFixes[0] := '检�?' + Result.ErrorType + ' 相关配置';
    
    SetLength(Result.PreventionTips, 1);
    Result.PreventionTips[0] := '添加输入验证和错误处�?;
  finally
    Causes.Free;
    StepIds.Free;
  end;
end;

procedure TErrorPatternAnalyzer.AnalyzePatterns;
var
  Clusters: TArray<TArray<TJSONObject>>;
  Cluster: TArray<TJSONObject>;
  Pattern: TErrorPattern;
begin
  FLock.Enter;
  try
    FPatterns.Clear;
    Clusters := ClusterErrors;
    
    for Cluster in Clusters do
    begin
      if Length(Cluster) >= 3 then // 至少3次才算模�?
      begin
        Pattern := ExtractPattern(Cluster);
        FPatterns.Add(Pattern.PatternId, Pattern);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TErrorPatternAnalyzer.GetPatterns: TArray<TErrorPattern>;
var
  PatternList: TList<TErrorPattern>;
  Pattern: TErrorPattern;
begin
  FLock.Enter;
  try
    PatternList := TList<TErrorPattern>.Create;
    try
      for Pattern in FPatterns.Values do
        PatternList.Add(Pattern);
      Result := PatternList.ToArray;
    finally
      PatternList.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TErrorPatternAnalyzer.MatchPattern(AError: TJSONObject): TErrorPattern;
var
  ErrorType: string;
  Pattern: TErrorPattern;
begin
  FLock.Enter;
  try
    ErrorType := AError.GetValue<string>('errorType', '');
    for Pattern in FPatterns.Values do
    begin
      if Pattern.ErrorType = ErrorType then
      begin
        Result := Pattern;
        Exit;
      end;
    end;
    Result.PatternId := '';
  finally
    FLock.Leave;
  end;
end;

function TErrorPatternAnalyzer.GeneratePreventionRecommendations(
  const AWorkflowId: string): TArray<TRecommendation>;
var
  Patterns: TArray<TErrorPattern>;
  Pattern: TErrorPattern;
  Rec: TRecommendation;
  I, J: Integer;
  ResultList: TList<TRecommendation>;
begin
  ResultList := TList<TRecommendation>.Create;
  try
    Patterns := GetPatterns;
    
    for Pattern in Patterns do
    begin
      Rec := TRecommendation.Create;
      Rec.RecommendationType := rtErrorPrevention;
      Rec.Title := Format('错误预防: %s (出现 %d �?', [Pattern.ErrorType, Pattern.Frequency]);
      Rec.Description := '常见原因: ' + String.Join(', ', Pattern.CommonCauses);
      Rec.Score := Min(1.0, Pattern.Frequency / 10);
      Rec.Confidence := clMedium;
      
      for J := 0 to High(Pattern.SuggestedFixes) do
        Rec.Actions.Add(Pattern.SuggestedFixes[J]);
      
      for J := 0 to High(Pattern.PreventionTips) do
        Rec.Metadata.Add('tip' + IntToStr(J), Pattern.PreventionTips[J]);
      
      ResultList.Add(Rec);
    end;
    
    Result := ResultList.ToArray;
  finally
    ResultList.Free;
  end;
end;

{$ENDREGION}

{$REGION 'TRecommendationService'}

constructor TRecommendationService.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FHybridRecommender := THybridRecommender.Create;
  FOptimizationAnalyzer := TOptimizationAnalyzer.Create;
  FErrorPatternAnalyzer := TErrorPatternAnalyzer.Create;
  FUserPreferences := TDictionary<string, TUserPreferences>.Create;
  FWorkflowStats := TDictionary<string, TWorkflowStats>.Create;
  FEnabled := True;
end;

destructor TRecommendationService.Destroy;
var
  Prefs: TUserPreferences;
begin
  for Prefs in FUserPreferences.Values do
    Prefs.Free;
  FUserPreferences.Free;
  FWorkflowStats.Free;
  FErrorPatternAnalyzer.Free;
  FOptimizationAnalyzer.Free;
  FHybridRecommender.Free;
  FLock.Free;
  inherited;
end;

function TRecommendationService.GetUserPreferences(const AUserId: string): TUserPreferences;
begin
  FLock.Enter;
  try
    if not FUserPreferences.TryGetValue(AUserId, Result) then
    begin
      Result := TUserPreferences.Create(AUserId);
      FUserPreferences.Add(AUserId, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TRecommendationService.GetWorkflowStats(const AWorkflowId: string): TWorkflowStats;
begin
  FLock.Enter;
  try
    if not FWorkflowStats.TryGetValue(AWorkflowId, Result) then
    begin
      Result.WorkflowId := AWorkflowId;
      Result.TotalExecutions := 0;
      Result.SuccessCount := 0;
      Result.FailureCount := 0;
      Result.AvgDurationMS := 0;
      Result.P95DurationMS := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRecommendationService.GetTemplateRecommendations(
  const AContext: TRecommendationContext; AMaxResults: Integer): TArray<TRecommendation>;
var
  Context: TJSONObject;
begin
  if not FEnabled then
    Exit(nil);
    
  Context := TJSONObject.Create;
  try
    Context.AddPair('currentWorkflowId', AContext.CurrentWorkflowId);
    Context.AddPair('intent', AContext.Intent);
    Result := FHybridRecommender.Recommend(AContext.UserId, Context, AMaxResults);
  finally
    Context.Free;
  end;
end;

function TRecommendationService.GetSkillRecommendations(
  const AContext: TRecommendationContext; AMaxResults: Integer): TArray<TRecommendation>;
var
  Prefs: TUserPreferences;
  TopSkills: TArray<string>;
  Rec: TRecommendation;
  I: Integer;
begin
  if not FEnabled then
    Exit(nil);
    
  Prefs := GetUserPreferences(AContext.UserId);
  TopSkills := Prefs.GetTopSkills(AMaxResults);
  
  SetLength(Result, Length(TopSkills));
  for I := 0 to High(TopSkills) do
  begin
    Rec := TRecommendation.Create;
    Rec.RecommendationType := rtSkillSuggestion;
    Rec.Title := '常用 Skill: ' + TopSkills[I];
    Rec.Description := '基于您的使用习惯推荐';
    Rec.Score := 1 - (I / Length(TopSkills));
    Rec.Confidence := clHigh;
    Rec.Metadata.Add('skillId', TopSkills[I]);
    Result[I] := Rec;
  end;
end;

function TRecommendationService.GetOptimizationRecommendations(
  const AWorkflowId: string; AMaxResults: Integer): TArray<TRecommendation>;
begin
  // 需要工作流定义，这里返回空
  SetLength(Result, 0);
end;

function TRecommendationService.GetErrorPreventionRecommendations(
  const AWorkflowId: string; AMaxResults: Integer): TArray<TRecommendation>;
begin
  if not FEnabled then
    Exit(nil);
    
  Result := FErrorPatternAnalyzer.GeneratePreventionRecommendations(AWorkflowId);
  if Length(Result) > AMaxResults then
    SetLength(Result, AMaxResults);
end;

function TRecommendationService.GetSimilarWorkflows(
  const AWorkflowId: string; AMaxResults: Integer): TArray<TRecommendation>;
begin
  // 通过内容推荐器获�?
  SetLength(Result, 0);
end;

function TRecommendationService.GetAllRecommendations(
  const AContext: TRecommendationContext; AMaxResults: Integer): TArray<TRecommendation>;
var
  AllRecs: TList<TRecommendation>;
  Recs: TArray<TRecommendation>;
  Rec: TRecommendation;
begin
  AllRecs := TList<TRecommendation>.Create;
  try
    // 获取各类推荐
    Recs := GetTemplateRecommendations(AContext, 3);
    for Rec in Recs do AllRecs.Add(Rec);
    
    Recs := GetSkillRecommendations(AContext, 3);
    for Rec in Recs do AllRecs.Add(Rec);
    
    Recs := GetErrorPreventionRecommendations(AContext.CurrentWorkflowId, 2);
    for Rec in Recs do AllRecs.Add(Rec);
    
    // 按分数排�?
    AllRecs.Sort(TComparer<TRecommendation>.Construct(
      function(const L, R: TRecommendation): Integer
      begin
        if R.Score > L.Score then Result := 1
        else if R.Score < L.Score then Result := -1
        else Result := 0;
      end
    ));
    
    // 限制数量
    while AllRecs.Count > AMaxResults do
      AllRecs.Delete(AllRecs.Count - 1);
    
    Result := AllRecs.ToArray;
  finally
    AllRecs.Free;
  end;
end;

procedure TRecommendationService.RecordUserBehavior(const AEvent: TUserBehaviorEvent);
var
  Prefs: TUserPreferences;
begin
  Prefs := GetUserPreferences(AEvent.UserId);
  Prefs.UpdateFromBehavior(AEvent);
  
  // 更新协同过滤
  if AEvent.WorkflowId <> '' then
    FHybridRecommender.FCollaborative.AddInteraction(
      AEvent.UserId, AEvent.WorkflowId, IfThen(AEvent.Success, 1.0, 0.5));
end;

procedure TRecommendationService.RecordWorkflowExecution(const AWorkflowId: string;
  ADurationMS: Integer; ASuccess: Boolean);
var
  Stats: TWorkflowStats;
begin
  FLock.Enter;
  try
    Stats := GetWorkflowStats(AWorkflowId);
    Stats.TotalExecutions := Stats.TotalExecutions + 1;
    if ASuccess then
      Stats.SuccessCount := Stats.SuccessCount + 1
    else
      Stats.FailureCount := Stats.FailureCount + 1;
    
    // 更新平均�?
    Stats.AvgDurationMS := (Stats.AvgDurationMS * (Stats.TotalExecutions - 1) + ADurationMS) / Stats.TotalExecutions;
    Stats.LastExecuted := Now;
    
    FWorkflowStats.AddOrSetValue(AWorkflowId, Stats);
  finally
    FLock.Leave;
  end;
end;

procedure TRecommendationService.RecordError(const AWorkflowId, AStepId, AErrorType, AErrorMessage: string);
var
  ErrorObj: TJSONObject;
begin
  ErrorObj := TJSONObject.Create;
  ErrorObj.AddPair('workflowId', AWorkflowId);
  ErrorObj.AddPair('stepId', AStepId);
  ErrorObj.AddPair('errorType', AErrorType);
  ErrorObj.AddPair('errorMessage', AErrorMessage);
  ErrorObj.AddPair('timestamp', DateTimeToStr(Now));
  
  FErrorPatternAnalyzer.RecordError(ErrorObj);
  ErrorObj.Free;
end;

procedure TRecommendationService.IndexWorkflow(const AWorkflowId: string; AWorkflow: TJSONObject);
begin
  FHybridRecommender.FContentBased.IndexWorkflow(AWorkflowId, AWorkflow);
end;

procedure TRecommendationService.RemoveWorkflow(const AWorkflowId: string);
begin
  FHybridRecommender.FContentBased.RemoveWorkflow(AWorkflowId);
end;

procedure TRecommendationService.RebuildIndex;
begin
  FHybridRecommender.FCollaborative.BuildSimilarityMatrix;
  FErrorPatternAnalyzer.AnalyzePatterns;
end;

procedure TRecommendationService.RecordFeedback(const ARecommendationId: string;
  AAccepted: Boolean; const AFeedback: string);
begin
  // 记录反馈用于改进推荐算法
  // TODO: 实现反馈学习
end;

{$ENDREGION}

{$REGION 'TTemplateRecommender'}

constructor TTemplateRecommender.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FTemplates := TDictionary<string, TWorkflowTemplate>.Create;
  FFeatureExtractor := TFeatureExtractor.Create;
end;

destructor TTemplateRecommender.Destroy;
begin
  FFeatureExtractor.Free;
  FTemplates.Free;
  FLock.Free;
  inherited;
end;

procedure TTemplateRecommender.RegisterTemplate(const ATemplate: TWorkflowTemplate);
begin
  FLock.Enter;
  try
    FTemplates.AddOrSetValue(ATemplate.TemplateId, ATemplate);
  finally
    FLock.Leave;
  end;
end;

procedure TTemplateRecommender.UnregisterTemplate(const ATemplateId: string);
begin
  FLock.Enter;
  try
    FTemplates.Remove(ATemplateId);
  finally
    FLock.Leave;
  end;
end;

procedure TTemplateRecommender.UpdatePopularity;
var
  SortedTemplates: TList<TPair<string, Double>>;
  Template: TWorkflowTemplate;
  I: Integer;
begin
  FLock.Enter;
  try
    SortedTemplates := TList<TPair<string, Double>>.Create;
    try
      for Template in FTemplates.Values do
        SortedTemplates.Add(TPair<string, Double>.Create(Template.TemplateId, Template.UsageCount));
      
      SortedTemplates.Sort(TComparer<TPair<string, Double>>.Construct(
        function(const L, R: TPair<string, Double>): Integer
        begin
          if R.Value > L.Value then Result := 1
          else if R.Value < L.Value then Result := -1
          else Result := 0;
        end
      ));
      
      SetLength(FPopularTemplates, Min(10, SortedTemplates.Count));
      for I := 0 to High(FPopularTemplates) do
        FPopularTemplates[I] := SortedTemplates[I].Key;
    finally
      SortedTemplates.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TTemplateRecommender.ScoreTemplate(const ATemplate: TWorkflowTemplate;
  const AContext: TRecommendationContext; APrefs: TUserPreferences): Double;
var
  Score: Double;
  I: Integer;
begin
  Score := 0;
  
  // 使用频率加分
  Score := Score + Min(1.0, ATemplate.UsageCount / 1000) * 0.3;
  
  // 评分加分
  Score := Score + ATemplate.Rating * 0.3;
  
  // 类别匹配加分
  for I := 0 to APrefs.PreferredCategories.Count - 1 do
    if ATemplate.Category = APrefs.PreferredCategories[I] then
    begin
      Score := Score + 0.2;
      Break;
    end;
  
  // 意图匹配加分
  if (AContext.Intent <> '') and (Pos(LowerCase(AContext.Intent), LowerCase(ATemplate.Name)) > 0) then
    Score := Score + 0.2;
  
  Result := Min(1.0, Score);
end;

function TTemplateRecommender.RecommendByContext(const AContext: TRecommendationContext;
  APrefs: TUserPreferences; AMaxResults: Integer): TArray<TRecommendation>;
var
  ScoredTemplates: TList<TPair<TWorkflowTemplate, Double>>;
  Template: TWorkflowTemplate;
  Score: Double;
  Rec: TRecommendation;
  I: Integer;
begin
  FLock.Enter;
  try
    ScoredTemplates := TList<TPair<TWorkflowTemplate, Double>>.Create;
    try
      for Template in FTemplates.Values do
      begin
        Score := ScoreTemplate(Template, AContext, APrefs);
        ScoredTemplates.Add(TPair<TWorkflowTemplate, Double>.Create(Template, Score));
      end;
      
      ScoredTemplates.Sort(TComparer<TPair<TWorkflowTemplate, Double>>.Construct(
        function(const L, R: TPair<TWorkflowTemplate, Double>): Integer
        begin
          if R.Value > L.Value then Result := 1
          else if R.Value < L.Value then Result := -1
          else Result := 0;
        end
      ));
      
      SetLength(Result, Min(AMaxResults, ScoredTemplates.Count));
      for I := 0 to High(Result) do
      begin
        Template := ScoredTemplates[I].Key;
        Rec := TRecommendation.Create;
        Rec.RecommendationType := rtWorkflowTemplate;
        Rec.Title := Template.Name;
        Rec.Description := Template.Description;
        Rec.Score := ScoredTemplates[I].Value;
        Rec.Confidence := clHigh;
        Rec.Metadata.Add('templateId', Template.TemplateId);
        Rec.Metadata.Add('category', Template.Category);
        Result[I] := Rec;
      end;
    finally
      ScoredTemplates.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TTemplateRecommender.RecommendByIntent(const AIntent: string;
  AMaxResults: Integer): TArray<TRecommendation>;
var
  MatchedTemplates: TList<TWorkflowTemplate>;
  Template: TWorkflowTemplate;
  Rec: TRecommendation;
  I: Integer;
  IntentLower: string;
begin
  IntentLower := LowerCase(AIntent);
  
  FLock.Enter;
  try
    MatchedTemplates := TList<TWorkflowTemplate>.Create;
    try
      for Template in FTemplates.Values do
      begin
        if (Pos(IntentLower, LowerCase(Template.Name)) > 0) or
           (Pos(IntentLower, LowerCase(Template.Description)) > 0) then
          MatchedTemplates.Add(Template);
      end;
      
      SetLength(Result, Min(AMaxResults, MatchedTemplates.Count));
      for I := 0 to High(Result) do
      begin
        Template := MatchedTemplates[I];
        Rec := TRecommendation.Create;
        Rec.RecommendationType := rtWorkflowTemplate;
        Rec.Title := Template.Name;
        Rec.Description := Template.Description;
        Rec.Score := 0.8;
        Rec.Confidence := clMedium;
        Rec.Metadata.Add('templateId', Template.TemplateId);
        Result[I] := Rec;
      end;
    finally
      MatchedTemplates.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TTemplateRecommender.RecommendPopular(AMaxResults: Integer): TArray<TRecommendation>;
var
  Template: TWorkflowTemplate;
  Rec: TRecommendation;
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, Min(AMaxResults, Length(FPopularTemplates)));
    for I := 0 to High(Result) do
    begin
      if FTemplates.TryGetValue(FPopularTemplates[I], Template) then
      begin
        Rec := TRecommendation.Create;
        Rec.RecommendationType := rtWorkflowTemplate;
        Rec.Title := '热门: ' + Template.Name;
        Rec.Description := Template.Description;
        Rec.Score := 1 - (I / Length(FPopularTemplates));
        Rec.Confidence := clVeryHigh;
        Rec.Metadata.Add('templateId', Template.TemplateId);
        Rec.Metadata.Add('usageCount', IntToStr(Template.UsageCount));
        Result[I] := Rec;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TTemplateRecommender.SearchTemplates(const AQuery: string;
  AMaxResults: Integer): TArray<TRecommendation>;
begin
  Result := RecommendByIntent(AQuery, AMaxResults);
end;

{$ENDREGION}

end.
