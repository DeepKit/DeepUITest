# Progee Lite 开发指�?
> 对外产品名：`Progee Lite`
> 系列主产品：`ProgramEasy` / `代码易`

> **目标**：让新同�?0分钟内上手开�?> **前置要求**：Delphi 12 + FMX 基础
> **项目路径**：`D:\_Progs\02Business\DeepDevLite`

---

## 1. 快速开�?
### 1.1 编译运行

```bash
# �?Delphi 12 打开项目
# 文件 �?打开 �?DeepDevLite.dproj

# 编译输出
bin\DeepDevLite.exe
```

### 1.2 核心流程�?分钟理解�?
```
代码输入 �?AI分析契约 �?用户确认 �?生成测试 �?本地执行 �?[3轮自动修复] �?封存输出
     �?          �?           �?          �?           �?             �? 拖拽/粘贴    Prompt调用   确认YAML    Prompt调用   进程执行      模型升级
```

### 1.3 文件结构

```
DeepDevLite/
├── ViewMain.pas           # 主窗体，状态机控制
├── CtrlContracts.pas       # 契约控制�?├── CtrlAIAdapter.pas      # AI调用封装
├── CtrlTestRunner.pas     # 测试执行�?├── CtrlReport.pas         # 报告生成
├── CtrlCardGenerator.pas  # 朋友圈卡�?├── uModels.pas            # 数据模型（TContract, TTask等）
├── uConstants.pas         # 常量定义
├── uDM.pas                # 数据模块
├── Fra*.pas               # Frame组件（UI模块�?├── prompts/               # AI提示词模�?�?  ├── analyze_contract.txt
�?  ├── generate_test.txt
�?  └── fix_code.txt
├── sql/                   # 数据库脚�?├── Backend/               # FastAPI徽章服务
└── docs/                 # 规格文档
```

---

## 2. 核心概念

### 2.1 状态机

```pascal
TVerifyState = (
  vsIdle,           // 空闲
  vsFileLoaded,     // 文件已加�?  vsAnalyzing,      // AI分析�?  vsContractReady,  // 契约待确�?  vsConfirmed,      // 契约已确�?  vsGeneratingTest, // 生成测试
  vsRunningTest,    // 执行测试
  vsFixing,         // AI修复�?  vsPassed,        // 验证通过
  vsFailed,         // 验证失败
  vsOutputting      // 输出�?);
```

**状态转换规�?*�?- `vsIdle` �?加载文件 �?`vsFileLoaded`
- `vsFileLoaded` �?调用AI分析 �?`vsAnalyzing`
- `vsAnalyzing` �?分析完成 �?`vsContractReady`
- `vsContractReady` �?用户确认 �?`vsConfirmed`
- `vsConfirmed` �?生成测试 �?`vsGeneratingTest`
- `vsRunningTest` �?通过 �?`vsPassed`，失�?�?`vsFixing`（最�?轮）

### 2.2 契约结构

```pascal
TContract = record
  Title     : string;           // 功能标题
  Language  : TSourceLanguage;  // 语言
  Purpose   : string;           // 功能描述
  Scenarios : array of TContractScenario;
end;

TContractScenario = record
  ID       : string;            // S001, S002...
  Desc     : string;            // 中文描述
  ScenType : (stNormal, stEdge, stError);  // 场景类型
  Input    : string;            // 输入
  Expected : string;            // 期望输出
end;
```

### 2.3 三轮自动修复（智能赛马）

```pascal
const
  MODEL_TIER1 = 'claude-haiku-4-5';   // 快速，便宜
  MODEL_TIER2 = 'claude-sonnet-4';   // 标准
  MODEL_TIER3 = 'claude-opus-4';     // 最�?
// 修复逻辑
case RetryCount of
  1: FixAndRetry(MODEL_TIER1);  // 第一轮修�?  2: FixAndRetry(MODEL_TIER2);  // 升级模型
  3: FixAndRetry(MODEL_TIER3);  // 最强模�?else
  ShowFailureReport;  // 3轮后仍失�?end;
```

---

## 3. 模块开发清�?
### 3.1 已完成模块（可直接使用）

| 模块 | 文件 | 说明 |
|------|------|------|
| 主窗�?| ViewMain.pas | 5-Zone布局，状态机控制 |
| 文件输入 | FraDropZone.pas | 拖拽/粘贴/选择 |
| AI适配�?| CtrlAIAdapter.pas | 统一AI调用接口 |
| 契约解析 | CtrlContracts.pas | YAML解析 |
| 测试执行 | CtrlTestRunner.pas | 本地进程调用 |
| 报告生成 | CtrlReport.pas | 验证报告 |
| 卡片生成 | CtrlCardGenerator.pas | 朋友圈卡�?|
| 徽章服务 | Backend/main.py | FastAPI |

### 3.2 待完成模块（优先级排序）

| 优先�?| 任务 | 难度 | 预计工作�?|
|--------|------|------|-----------|
| P1 | 手动修改后重试功�?| �?| 2小时 |
| P2 | PDF导出（报�?卡片�?| �?| 4小时 |
| P2 | 本地环境检�?| �?| 2小时 |
| P3 | 主题切换 | �?| 2小时 |
| P3 | 多语言支持 | �?| 4小时 |

---

## 4. 开发规�?
### 4.1 命名约定

| 前缀 | 用�?| 示例 |
|------|------|------|
| `Ctrl` | 业务控制�?| CtrlContracts.pas |
| `Fra` | Frame组件 | FraCardGenerator.pas |
| `Helper` | 工具�?| HelperJson.pas |
| `u` | 数据模块/模型 | uDM.pas, uModels.pas |

### 4.2 状态管�?
所有状态变更必须通过 `SetState` 方法�?
```pascal
procedure TFormMain.SetState(NewState: TVerifyState);
begin
  if FCurrentState = NewState then Exit;
  
  // 状态变更前检�?  case NewState of
    vsConfirmed:
      if not FContract.IsConfirmed then Exit;
  end;
  
  FCurrentState := NewState;
  UpdateUI;  // 统一更新UI
end;
```

### 4.3 AI调用规范

```pascal
// 统一的AI调用方法
function TFormMain.CallAI(const Prompt: string; ModelName: string): string;
begin
  // 1. 显示加载状�?  ShowProgress('AI处理�?..');
  
  // 2. 调用适配�?  Result := FAIAdapter.Call(Prompt, ModelName);
  
  // 3. 错误处理
  if Result = '' then
    raise Exception.Create('AI调用失败');
end;
```

### 4.4 异步处理

耗时操作必须使用 `TTask.Run`，并在主线程更新UI�?
```pascal
TTask.Run(procedure
var
  Result: string;
begin
  Result := CallAI(Prompt, Model);
  
  TThread.Synchronize(nil, procedure
  begin
    // 在主线程更新UI
    ShowResult(Result);
  end);
end);
```

---

## 5. 调试技�?
### 5.1 查看AI输出

```pascal
// 在AI调用后添加日�?Result := CallAI(Prompt, Model);
Log(Format('AI Output: %s', [Result]));  // 调试�?```

### 5.2 跳过AI直接测试

```pascal
// 临时硬编码测试数�?procedure TFormMain.BtnTestClick(Sender: TObject);
begin
  FContract.Title := '测试契约';
  SetLength(FContract.Scenarios, 1);
  FContract.Scenarios[0].ID := 'S001';
  SetState(vsPassed);  // 直接跳过
end;
```

### 5.3 查看测试输出

```pascal
// 测试运行后显示原始输�?ShowMessage(FLastTestOutput);
```

---

## 6. 常见问题

### Q1: 编译报错"找不到文�?
- 检�?`tools` �?`options` �?`Delphi` �?`Library` �?`Library path`
- 确保包含 `$(BDSPROJECT)\lib\Win64\release` 等路�?
### Q2: AI调用超时
- 检查网络连�?- 调整 `CtrlAIAdapter` 中的 `TimeoutSec` 常量

### Q3: 测试执行失败
- 确认本地已安装对应语言的运行时（Python/Node等）
- 检�?`BuildRunCommand` 函数中的命令是否正确

### Q4: 卡片导出空白
- 检�?`TCanvas` 是否正确初始�?- 确认 `TBitmap` 尺寸设置正确�?080x1080�?
---

## 7. 相关文档

| 文档 | 内容 |
|------|------|
| `tasks.md` | 完整任务清单 |
| `DeepDevLite-Core-Spec.md` | 核心功能详细规格 |
| `DeepDevLite-Dev-Spec.md` | UI/报告/卡片详细规格 |
| `DeepDevLite-Badge-PG15.md` | 徽章服务API文档 |
| `313.ODD优化增强.md` | ODD理论优化建议 |

---

## 8. 快速交�?Checklist

新同事接收时检查：

- [ ] 能编译运�?`DeepDevLite.exe`
- [ ] 能拖拽文件并识别语言
- [ ] AI分析契约能返回YAML
- [ ] 契约确认界面能编�?- [ ] 测试能本地执�?- [ ] 3轮修复循环正常工�?- [ ] 报告能正常显�?- [ ] 卡片能生成PNG
- [ ] 徽章服务能启�?
如遇问题，参考本指南�?节调试技巧�?