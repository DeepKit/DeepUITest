program DeepFlowG01_GoldPathDemo;

(*
  DeepFlow MVP P0 - 金路径端到端演示
  ===================================
  
  目标:
    1. 验证 insight 决策金路径完整闭环
    2. Workflow 定义 → Delphi 引擎 → Skills 服务六角色 → LLM → 聚合 → 胶片
    3. 记录响应时间 <30s，产出胶片文件
  
  前置条件:
    - Skills 服务运行在 http://127.0.0.1:8001
    - 编译本程序并执行
  
  验收标准:
    ✓ 六个角色依次调用 (coach/critic/mirror/observer/aggregator/film_generator)
    ✓ 最终产出胶片文件到 D:/_Progs/02Business/DeepFlow/outputs/film_{timestamp}.md
    ✓ 总响应时间 <30 秒
*)

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.DateTimes,
  System.IOUtils,
  DeepFlow.Skill.Client,
  DeepFlow.Skill.Types,
  DeepFlow.Workflow.Definition,
  DeepFlow.Workflow.Executor;

const
  SKILL_BASE_URL = 'http://127.0.0.1:8001';
  OUTPUT_DIR = 'D:\_Progs\02Business\DeepFlow\outputs';

type
  TGoldPathDemo = class
  private
    FSkillClient: TSkillClient;
    FStartTime: TDateTime;
    FElapsedTimeMs: Integer;
    
    procedure WriteHeader;
    procedure WriteLine(const AText: string);
    procedure Log(const AText: string);
    function CallSkill(const ASkillName: string; const AParams: TJSONObject): TJSONObject;
    function AggregateViews(
      const ACoach: TJSONObject; const ACritic: TJSONObject;
      const AMirror: TJSONObject; const AObserver: TJSONObject): TJSONObject;
    function GenerateFilm(const AProblem: string; const AAggregated: TJSONObject): TJSONObject;
    procedure SaveFilm(const AFilm: TJSONObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

{ TGoldPathDemo }

constructor TGoldPathDemo.Create;
begin
  inherited Create;
  FSkillClient := TSkillClient.Create(SKILL_BASE_URL);
  FStartTime := Now;
  FElapsedTimeMs := 0;
end;

destructor TGoldPathDemo.Destroy;
begin
  if Assigned(FSkillClient) then
    FSkillClient.Free;
  inherited Destroy;
end;

procedure TGoldPathDemo.WriteHeader;
begin
  Writeln '';
  Writeln('==============================================================================');
  Writeln('           DeepFlow MVP P0 - 洞察·决策推演金路径端到端演示');
  Writeln('==============================================================================');
  Writeln(Format('启动时间：%s', [DateTimeToStr(Now)]));
  Writeln(Format('Skills 服务：%s', [SKILL_BASE_URL]));
  Writeln('');
end;

procedure TGoldPathDemo.WriteLine(const AText: string);
begin
  Writeln(AText);
end;

procedure TGoldPathDemo.Log(const AText: string);
begin
  Writeln(Format('[%.3fs] %s', [(SecondsBetween(Now, FStartTime) * 1000) / 1000, AText]));
end;

function TGoldPathDemo.CallSkill(const ASkillName: string; const AParams: TJSONObject): TJSONObject;
var
  LRequest: TSkillRequest;
  LResponse: TSkillResponse;
  LJsonStr: string;
  LElapsedMs: Single;
begin
  LElapsedMs := SecondsBetween(Now, FStartTime) * 1000;
  Log(Format('▶ 调用技能：%s (参数：%s)', [ASkillName, AParams.AsJSON]));
  
  LRequest := TSkillRequest.Create;
  try
    LRequest.SkillName := ASkillName;
    LRequest.TimeoutMs := 25000; // 25 秒超时
    
    (* 遍历参数 *)
    if Assigned(AParams) then
    begin
      for var i := 0 to AParams.Count - 1 do
      begin
        var LPair := APairs[AParams]^[i];
        case LPair.Value.JsonType of
          jtString: LRequest.SetParamStr(LPair.Name, LPair.Value.AsString);
          jtNumber: LRequest.SetParamFloat(LPair.Name, LPair.Value.AsNumber);
          jtBoolean: LRequest.SetParamBool(LPair.Name, LPair.Value.AsBool);
          jtObject: LRequest.SetParamJson(LPair.Name, LPair.Value);
          jtArray: LRequest.SetParamJson(LPair.Name, LPair.Value);
        end;
      end;
    end;
    
    LResponse := FSkillClient.ExecuteSkill(LRequest);
    try
      if not LResponse.IsSuccess then
        raise Exception.CreateFmt('技能调用失败 (%s): %s', [ASkillName, LResponse.Error]);
      
      Result := TJSONObject.ParseJSONValue(LResponse.Result as TStringStream).AsObject;
      
      LElapsedMs := SecondsBetween(Now, FStartTime) * 1000;
      Log(Format('✔ %s完成 (%.3fs, %.2fms)', [ASkillName, SecondsBetween(FStartTime, Now), LElapsedMs]));
    finally
      LResponse.Free;
    end;
  finally
    LRequest.Free;
  end;
end;

function TGoldPathDemo.AggregateViews(
  const ACoach: TJSONObject; const ACritic: TJSONObject;
  const AMirror: TJSONObject; const AObserver: TJSONObject): TJSONObject;
begin
  (* 调用 decision_aggregator *)
  var LInputs := TJSONObject.Create;
  try
    LInputs.AddPair('coach_view', ACoach);
    LInputs.AddPair('critic_view', ACritic);
    LInputs.AddPair('mirror_view', AMirror);
    LInputs.AddPair('observer_view', AObserver);
    Result := CallSkill('decision_aggregator', LInputs);
  finally
    LInputs.Free;
  end;
end;

function TGoldPathDemo.GenerateFilm(const AProblem: string; const AAggregated: TJSONObject): TJSONObject;
begin
  (* 调用 film_generator *)
  var LInputs := TJSONObject.Create;
  try
    LInputs.AddPair('problem', TJString.create(AProblem));
    LInputs.AddPair('aggregated', AAggregated);
    Result := CallSkill('film_generator', LInputs);
  finally
    LInputs.Free;
  end;
end;

procedure TGoldPathDemo.SaveFilm(const AFilm: TJSONObject);
var
  LTimestamp: string;
  LFilePath: string;
  LMarkdown: TStringBuilder;
  LContent: TJSONValue;
begin
  (* 从胶片输出提取 markdown 内容 *)
  LContent := AFilm.Get('markdown');
  if not Assigned(LContent) or (LContent is not TJString) then
    raise Exception.Create('胶片输出中没有 markdown 字段');
  
  LTimestamp := FormatDateTime('YYYYMMDD_HHMMSS', Now);
  LFilePath := IncludeTrailingPathDelimiter(OUTPUT_DIR) + 'film_' + LTimestamp + '.md';
  
  (* 确保目录存在 *)
  if not DirectoryExists(OUTPUT_DIR) then
    CreateDirectory(OUTPUT_DIR);
  
  (* 写入 Markdown 文件 *)
  LMarkdown := TStringBuilder.Create;
  try
    LMarkdown.AppendLine('# 决策思维显影胶片');
    LMarkdown.AppendLine('');
    LMarkdown.AppendLine(Format('生成时间：%s', [DateTimeToStr(Now)]));
    LMarkdown.AppendLine(Format('问题：%s', [AFilm.Get('problem').AsString]));
    LMarkdown.AppendLine('');
    LMarkdown.AppendLine('---');
    LMarkdown.AppendLine('');
    LMarkdown.AppendLine(LContent.AsString);
    LMarkdown.AppendLine('');
    LMarkdown.AppendLine('---');
    LMarkdown.AppendLine('');
    LMarkdown.AppendLine('## 自我提问');
    LMarkdown.AppendLine('');
    
    (* 添加自我提问列表 *)
    var LSelfQuestions := AFilm.GetValueJSONArray('self_questions');
    if Assigned(LSelfQuestions) then
      for var LQ in LSelfQuestions do
        LMarkdown.AppendLine('- ' + LQ.AsString);
    
    LMarkdown.AppendLine();
    LMarkdown.AppendLine('## 多视角分析');
    LMarkdown.AppendLn();
    
    (* 添加聚合视图摘要 *)
    var LViews := AFilm.GetValueJSONArray('views');
    if Assigned(LViews) then
      for var LV in LViews do
        LMarkdown.AppendLine('- ' + LV.AsString);
    
    (* 保存文件 *)
    TFile.WriteAllText(LFilePath, LMarkdown.ToString, TEncoding.UTF8);
    
    Log(Format('💾 胶片已保存到：%s', [LFilePath]));
    WriteLn(Format('💾 胶片已保存到：%s', [LFilePath]));
  finally
    LMarkdown.Free;
  end;
end;

procedure TGoldPathDemo.Run;
var
  LProblem: string;
  LInputs: TJSONObject;
  LCoachView: TJSONObject;
  LCriticView: TJSONObject;
  LMirrorView: TJSONObject;
  LObserverView: TJSONObject;
  LAggregated: TJSONObject;
  LFilm: TJSONObject;
  LTotalTime: Single;
begin
  (* 初始化 *)
  WriteHeader;
  
  (* 设定测试用决策问题 *)
  LProblem := '我在职业发展中面临选择：是继续在当前公司深耕技术路线成为专家，还是跳槽到创业公司担任技术负责人？请帮我进行系统性的决策分析。';
  WriteLn('【步骤 1】接收决策问题');
  WriteLn(Format('问题：%s', [LProblem]));
  WriteLn('');
  
  (* 并行调用四个视角角色 *)
  WriteLn('【步骤 2】多视角推演（教练/批评者/镜像/观察者）');
  WriteLn('---');
  
  (* coach 视角 *)
  LInputs := TJSONObject.Create;
  try
    LInputs.AddPair('problem', TJString.Create(LProblem));
    LInputs.AddPair('context', TJSONObject.Create);
    LCoachView := CallSkill('decision_coach', LInputs);
  finally
    LInputs.Free;
  end;
  
  (* critic 视角 *)
  LInputs := TJSONObject.Create;
  try
    LInputs.AddPair('problem', TJString.Create(LProblem));
    LInputs.AddPair('context', TJSONObject.Create);
    LCriticView := CallSkill('decision_critic', LInputs);
  finally
    LInputs.Free;
  end;
  
  (* mirror 视角 *)
  LInputs := TJSONObject.Create;
  try
    LInputs.AddPair('problem', TJString.Create(LProblem));
    LInputs.AddPair('context', TJSONObject.Create);
    LMirrorView := CallSkill('decision_mirror', LInputs);
  finally
    LInputs.Free;
  end;
  
  (* observer 视角 *)
  LInputs := TJSONObject.Create;
  try
    LInputs.AddPair('problem', TJString.Create(LProblem));
    LInputs.AddPair('context', TJSONObject.Create);
    LObserverView := CallSkill('decision_observer', LInputs);
  finally
    LInputs.Free;
  end;
  
  WriteLn('---');
  WriteLn('');
  
  (* 聚合四视角 *)
  WriteLn('【步骤 3】聚合多视角洞察');
  LAggregated := AggregateViews(LCoachView, LCriticView, LMirrorView, LObserverView);
  WriteLn('');
  
  (* 生成胶片 *)
  WriteLn('【步骤 4】生成决策胶片');
  LFilm := GenerateFilm(LProblem, LAggregated);
  WriteLn('');
  
  (* 保存胶片 *)
  SaveFilm(LFilm);
  
  (* 统计总耗时 *)
  LTotalTime := SecondsBetween(Now, FStartTime) * 1000;
  
  (* 输出总结 *)
  WriteLn('==============================================================================');
  WriteLn('                         金路径演示结果汇总');
  WriteLn('==============================================================================');
  WriteLn(Format('总耗时：%.3f 秒 (%.3f ms)', [LTotalTime / 1000, LTotalTime]));
  WriteLn(Format('状态：%s', [IfThen(LTotalTime < 30000, '✅ 通过 (<30s)', '❌ 未通过 (>=30s)']));
  WriteLn('胶片产出：✅ 已保存至 outputs/');
  WriteLn('');
  WriteLn('==============================================================================');
  WriteLn('                           演示完成');
  WriteLn('==============================================================================');
end;

var
  Demo: TGoldPathDemo;
begin
  try
    Demo := TGoldPathDemo.Create;
    try
      Demo.Run;
    finally
      Demo.Free;
    end;
  except
    on E:Exception do
    begin
      WriteLn('❌ 错误：' + E.Message);
      WriteLn(E.StackTrace);
    end;
  end;
  
  WriteLn('');
  WriteLn('按 Enter 键退出...');
  ReadLn;
end.
