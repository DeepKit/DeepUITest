program DeepFlowSkillE2E;

(*
  DeepFlow Skill Service 端到端演示 (E2E)
  ========================================
  验证 Delphi 客户端 ↔ Python FastAPI Skill Service 真实联调。

  前置条件:
    1. 启动 Python Skill 服务:
       cd Skills && python -m uvicorn src.main:app --host 127.0.0.1 --port 8000
    2. 编译本程序并运行

  演示内容:
    1. Health Check (GET /health)
    2. 列出可用 Skills (GET /skills)
    3. 沙箱代码执行 (POST /skills/execute) - 计算 1..100 求和
    4. 安全拦截验证 - import os 应被拒绝
*)

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  DeepFlow.Skill.Client,
  DeepFlow.Skill.Types;

const
  SKILL_BASE_URL = 'http://127.0.0.1:8000';

procedure Demo1_HealthCheck(AClient: TSkillClient);
var
  Health: THealthResponse;
begin
  Writeln('');
  Writeln('=== Demo 1: Health Check ===');
  Health := AClient.CheckHealth;
  try
    Writeln(Format('Status   : %s', [Health.Status]));
    Writeln(Format('Version  : %s', [Health.Version]));
    Writeln(Format('Env      : %s', [Health.Environment]));
    Writeln(Format('Skills   : %d', [Health.SkillsLoaded]));
    Writeln(Format('Healthy  : %s', [BoolToStr(Health.IsHealthy, True)]));
  finally
    Health.Free;
  end;
end;

procedure Demo2_ListSkills(AClient: TSkillClient);
var
  Skills: TObjectList<TSkillInfo>;
  SkillInfo: TSkillInfo;
begin
  Writeln('');
  Writeln('=== Demo 2: List Skills ===');
  Skills := AClient.ListSkills;
  try
    if Skills.Count = 0 then
      Writeln('(no skills registered)')
    else
      for SkillInfo in Skills do
        Writeln(Format('  - %s v%s: %s',
          [SkillInfo.Name, SkillInfo.Version, SkillInfo.Description]));
  finally
    Skills.Free;
  end;
end;

procedure Demo3_ExecuteCode(AClient: TSkillClient);
var
  Request: TSkillRequest;
  Response: TSkillResponse;
  ResultValue: TJSONValue;
begin
  Writeln('');
  Writeln('=== Demo 3: Sandbox Code Execution ===');

  Request := TSkillRequest.Create;
  try
    Request.SkillName := 'code_executor';
    Request.TimeoutMs := 15000;
    Request.SetParamStr('code',
      'result = sum(range(1, 101))' + sLineBreak +
      'print("computed sum")');
    Request.SetParamStr('return_var', 'result');

    Response := AClient.ExecuteSkill(Request);
    try
      if Response.IsSuccess then
      begin
        Writeln(Format('Status   : %s', [Response.Status.ToString]));
        // 提取 result.value
        ResultValue := Response.Result;
        if Assigned(ResultValue) then
          Writeln(Format('Result   : %s', [ResultValue.ToString]))
        else
          Writeln('Result   : (null)');
        Writeln(Format('Time     : %d ms', [Response.ExecutionTimeMs]));
      end
      else
        Writeln(Format('FAILED   : %s', [Response.Error]));
    finally
      Response.Free;
    end;
  finally
    Request.Free;
  end;
end;

procedure Demo4_SecurityBlock(AClient: TSkillClient);
var
  Request: TSkillRequest;
  Response: TSkillResponse;
begin
  Writeln('');
  Writeln('=== Demo 4: Security Block (import os should fail) ===');

  Request := TSkillRequest.Create;
  try
    Request.SkillName := 'code_executor';
    Request.TimeoutMs := 15000;
    Request.SetParamStr('code',
      'import os' + sLineBreak +
      'result = os.listdir(".")');

    Response := AClient.ExecuteSkill(Request);
    try
      if Response.IsSuccess then
        Writeln('FAIL     : dangerous code was NOT blocked!')
      else
        Writeln(Format('BLOCKED  : %s', [Response.Error]));
    finally
      Response.Free;
    end;
  finally
    Request.Free;
  end;
end;

var
  Client: TSkillClient;
begin
  Writeln('DeepFlow Skill Service E2E Demo');
  Writeln('================================');
  Writeln(Format('Target   : %s', [SKILL_BASE_URL]));
  Writeln(Format('Time     : %s', [DateTimeToStr(Now)]));

  Client := TSkillClient.Create(SKILL_BASE_URL);
  try
    Demo1_HealthCheck(Client);
    Demo2_ListSkills(Client);
    Demo3_ExecuteCode(Client);
    Demo4_SecurityBlock(Client);

    Writeln('');
    Writeln('=== All demos completed ===');
  finally
    Client.Free;
  end;

  Writeln('');
  Write('Press Enter to exit...');
  Readln;
end.
