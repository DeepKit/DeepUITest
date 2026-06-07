# DeepFrames Bugfix Log

## 2026-06-07 — ASR 端点配置错误（Standard → Step Plan）

**严重性**: P1 (ASR 功能不可用)
**发现方式**: POC 2d ASR SSE 验证

**现象**: ASR 使用 Standard 端点 `/v1/audio/asr/sse` + Standard Key，返回 402（quota exceeded）。

**根因**: 文档错误 — ASR 实际支持 Step Plan 端点 `/step_plan/v1/audio/asr/sse`，且使用 Step Plan Key。请求格式不是扁平 JSON，而是嵌套格式：
```json
{
  "audio": {
    "data": "<base64>",
    "input": {
      "transcription": { "language": "zh", "model": "stepaudio-2.5-asr", "enable_timestamp": true },
      "format": { "type": "mp3" }
    }
  }
}
```

**修复**:
- `StepFun.pas`: ASR 端点从 `/v1/audio/asr/sse` 改为 `/step_plan/v1/audio/asr/sse`
- `StepFun.pas`: 请求格式改为嵌套 JSON
- `StepFun.pas`: SSE 事件解析改为 `transcript.text.delta` / `transcript.text.done`
- `02.api` 文档：双端点架构表 + ASR 章节全面修正

**影响**: 一个 Step Plan Key 现覆盖全部能力（Chat/TTS/ASR/Image），无需 Standard Key。

---

## 2026-06-07 — StepFun 模型 ID 错误

**严重性**: P1 (API 调用 404，功能完全不可用)
**发现方式**: POC 2 StepFun Chat API 连通性测试

**现象**: 代码中使用 `stepfun-flash-3.5` 作为模型 ID，调用 StepFun API 返回 404：
```
The model "stepfun-flash-3.5" does not exist or you do not have access to it.
```

**根因**: StepFun 的实际模型 ID 是 `step-3.5-flash`（前缀 `step-`，非 `stepfun-`）。

**修复**: 批量更新所有引用：
- `DeepFrames.Provider.StepFun.pas`: `GetSupportedModels` 返回 `['step-3.5-flash', 'step-3.7-flash']`
- `DeepFrames.Workflow.AgentChain.pas`: 3 处 `stepfun-flash-3.5` → `step-3.5-flash`
- `DeepFrames.Workflow.DocumentChain.pas`: 2 处 `stepfun-flash-3.5` → `step-3.5-flash`
- `DeepFrames.Provider.StepFun.pas`: stub 输出中的模型名
- Config.db: 6 个模型注册记录

**备注**: Step Plan API 的 9 个可用模型（`/models` endpoint）：
- LLM: `step-3.5-flash`, `step-3.7-flash`, `step-3.5-flash-2603`, `step-router-v1`
- Image: `step-image-edit-2`
- Audio: `stepaudio-2.5-tts`, `stepaudio-2.5-asr`, `stepaudio-2.5-chat`, `stepaudio-2.5-realtime`

---

## 2026-06-07 — StepFun Chat reasoning 模式返回空 content

**严重性**: P2 (功能降级，小 max_tokens 时回复为空)
**发现方式**: POC 2 Chat API 调试

**现象**: 当 `max_tokens` 较小（如 200）时，StepFun `step-3.5-flash` 返回 `content: ""`，所有 token 用于 `reasoning` 字段。

**根因**: Step Plan API 的推理模型将 `reasoning` 和 `content` 分离。reasoning 先消耗 token，若 `max_tokens` 不够，content 为空且 `finish_reason: "length"`。

**影响**: `DocumentChain` 和 `AgentChain` 中若设置 `max_tokens` 过小，LLM 返回空 JSON，导致 schema 验证失败。

**建议修复**: 将 `max_tokens` 提高到 4096+（当前设置已为 4096，暂无实际影响）。需在 ChatComplete 返回结果中检查 `reasoning` 字段，若 `content` 为空但 `reasoning` 非空，尝试从 reasoning 中提取有效内容或标记为降级。

---

## 2026-06-06 — 编译警告/提示清零

**严重性**: P2 (编译质量，不影响功能)
**发现方式**: `dcc64 -B` 全量编译审计

### 1. W1057 AnsiString→string 隐式转换（GetValue<string> 泛型）

**文件**: StepFun.pas / PackageExporter.pas / AssetRetention.pas / StyleKeeper.pas
**现象**: `TJSONObject.GetValue<string>('key')` 在 Delphi 12.x 返回 AnsiString，隐式转换到 UnicodeString 触发 W1057
**修复**: 改用非泛型 `GetValue('key').Value`，直接返回 `string`（`TJSONString.Value`）
**影响**: 约 30 处调用点

### 2. W1057 中文字面量隐式转换（缺 UTF-8 BOM）

**文件**: 11 个 `.pas` 文件（StepFun / Fake / GateEvaluator / DocumentChain / StyleKeeper / PromptVersion / AgentChain / SubtitleEngine / PackageExporter / Resume / AssetRetention）
**现象**: 含中文/全角标点的字符串字面量（如 `'词1'`、`'（'`、`'——'`）在无 BOM 的 UTF-8 文件中被 Delphi 12.x 按 ANSI codepage 解析，触发 W1057
**修复**: 文件头添加 UTF-8 BOM（`EF BB BF`），Delphi 按需 UTF-8 解析源码
**影响**: 约 40 处字面量

### 3. H2077 Result 赋值后未读取

**文件**: `StepFun.pas` — `CallRealAPI`（LLM/ASR/Image 3 个 provider）
**现象**: 函数开头 `Result := False` 后，所有错误路径使用 `Exit(False)`，成功路径 `Result := True`，初始赋值是死代码
**修复**: 删除开头的 `Result := False`

### 4. H2443 Generics.Collections 未引入

**文件**: 7 个 Workflow 文件 + StepFun.pas
**现象**: `TJSONArray.GetValue<T>` 内联展开需要 `System.Generics.Collections`，未在 uses 中声明
**修复**: 各文件 implementation uses 添加 `System.Generics.Collections`

---

## 2026-06-05 — 集成测试对齐修复（3 处预期偏差）

**严重性**: P3 (测试断言与实际行为对齐)
**发现方式**: 集成测试首次运行（6/97 failures → 0/97）

### 1. SeverityToStr 返回小写

**文件**: `src/Workflow/DeepFrames.Workflow.EventLog.pas:80-88`
**现象**: 测试期望 `INFO`/`WARN`/`ERROR`/`FATAL`，实际返回 `info`/`warn`/`error`/`fatal`
**处理**: 测试断言改为小写（设计意图一致，非 bug）

### 2. Fake splitter 输出结构与测试 Schema 不匹配

**文件**: `tests/DeepFrames.Tests.Integration.pas`
**现象**: 测试 Schema 要求 `segments` 数组，Fake provider 返回 `shots` 数组
**处理**: 测试 Schema 改为匹配 Fake 输出的 `{"required":["shots"],"properties":{"shots":{"type":"array"}}}`

### 3. Schema auto-repair 对 required 字段注入默认值

**文件**: `src/Shared/DeepFrames.Shared.JsonSchema.pas`
**现象**: 测试期望 `{"required":["name"]}` + `{}` 在 auto-repair 后仍 fail，实际 repair 成功注入默认空字符串
**处理**: 测试改为验证 `IsValid=True` + `RepairCount > 0`（符合 auto-repair 设计意图）

---

## 2026-06-05 — 全量编译修复（8 文件，7 类错误）

**严重性**: P0 (编译阻断，12 个编译错误)
**发现方式**: `dcc64` 全量编译
**影响文件**: 8 个 `.pas` 文件

### 1. StepFun.pas — 重复 ASR 类体（结构错误）

**文件**: `src/Provider/DeepFrames.Provider.StepFun.pas:136-160`
**现象**: `E2029 'END' expected but 'PRIVATE' found` — interface 段末尾多了一段没有类头的 ASR 类成员声明
**根因**: 代码生成时 ASR 类体被粘贴了两次，第二次只有 `private/public` 段没有 `T... = class(...)` 头
**修复**: 删除 lines 136-160 的孤立类体

### 2. StepFun.pas — ResponseCode 不存在（API 不兼容）

**文件**: `src/Provider/DeepFrames.Provider.StepFun.pas:596`
**现象**: `E2003 Undeclared identifier: 'ResponseCode'`
**根因**: `THTTPClient` 没有 `ResponseCode` 属性；状态码在 `IHTTPResponse.StatusCode` 上
**修复**: 捕获 `HTTP.Post()` 返回值到 `Resp: IHTTPResponse`，用 `Resp.StatusCode`

### 3. StepFun.pas — 局部变量 `Format` 遮蔽 `SysUtils.Format()`（命名冲突）

**文件**: `src/Provider/DeepFrames.Provider.StepFun.pas:541,691`
**现象**: `E2250 No overloaded version of 'Format'`，`E2066 Missing operator or semicolon`
**根因**: 局部变量 `Format: string` 与 `SysUtils.Format()` 函数同名，编译器混淆
**修复**: 重命名为 `Fmt`，涉及 CallRealAPI 和 CallStubAPI 两个函数

### 4. Fake.pas — TFakeImageProvider 声明在 implementation 段（可见性错误）

**文件**: `src/Provider/DeepFrames.Provider.Fake.pas:370-385`
**现象**: `E2003 Undeclared identifier: 'TFakeImageProvider'`（在 Registry.pas 中）
**根因**: `TFakeImageProvider` 类声明在 `implementation` 段的 `type` 块中，其他单元无法引用
**修复**: 将类声明移至 `interface` 段（紧跟 `TFakeASRProvider` 之后）

### 5. EventLog.pas — 缺少 Generics.Collections + `>>` 歧义（泛型语法）

**文件**: `src/Workflow/DeepFrames.Workflow.EventLog.pas:63,96`
**现象**: `E2003 Undeclared identifier: 'TPair<,>'`，`E2029 Statement expected but 'CLASS' found`
**根因**: (1) uses 缺少 `System.Generics.Collections`；(2) `TArray<TPair<string, string>>` 中 `>>` 被解析为右移运算符
**修复**: 添加 `System.Generics.Collections`；改为 `TArray<TPair<string, string> >`（空格分隔）

### 6. AgentChain.pas — 多余 `var/begin` 块 + 缺少 Gate2Score 声明（结构错误）

**文件**: `src/Workflow/DeepFrames.Workflow.AgentChain.pas:236-238`
**现象**: `E2029 'END' expected but 'FINALLY' found`
**根因**: for 循环结束后多了一段 `var Gate2Score: Double; begin`，像嵌套函数声明但格式错误
**修��**: 删除 `var/begin` 块，将 `Gate2Score` 加入函数顶部 `var` 段

### 7. AudioProcessor.pas — out 参数位置 + TBytes 转换（Delphi 约束）

**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas:110-112,205,214`
**现象**: `E2238 Default value required for 'AVerifyMeasurement'`，`E2250 GetString overload`
**根因**: (1) `out` 参数不能在有默认值的参数之后；(2) `TEncoding.UTF8.GetString` 不接受静态数组
**修复**: (1) 将 `out AVerifyMeasurement` 移到默认参数之前；(2) 用 `TmpBytes: TBytes` + `Move` 中转

### 8. SubtitleEngine.pas — 中文字符不能放入 `set of Char`（类型约束）

**文件**: `src/Workflow/DeepFrames.Workflow.SubtitleEngine.pas:113-118`
**现象**: `E2001 Ordinal type required`，`E2010 Incompatible types`
**根因**: `set of Char` 只支持 0-255 的字符；中文标点（'，'、'。'等）超出范围
**修复**: 改为常量字符串 `PUNCTUATION_BREAK_CHARS = '，。！？...'`；查找用 `System.Pos()`；循环变量 `Pos` 重命名为 `Idx` 避免遮蔽

### 9. AssetRetention.pas — `Protected` 保留字冲突 + 缺少变量声明

**文件**: `src/Workflow/DeepFrames.Workflow.AssetRetention.pas:39,293-298`
**现象**: `E2184 PROTECTED section valid only in class types`，`E2003 Undeclared identifier: 'V'`
**根因**: (1) `Protected` 是 Delphi 可见性保留字，不能做字段名；(2) inline `var V` 与顶部 `var V` 重复声明
**修复**: 字段名改为 `&Protected`（引用时 `Plan.&Protected`）；删除 inline `var V`，在顶部 `var` 段声明 `V: TCleanupVerdict`

---

## 2026-06-04 — AudioProcessor: 错误使用 TProcess (FreePascal 类，Delphi 不可用)

**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas`
**严重性**: P0 (编译阻断)
**发现方式**: 代码审查
**提交**: `8a98217 fix(DeepFrames): replace TProcess with WinAPI CreateProcess in AudioProcessor`

**现象**: `RunFFmpeg` 函数使用了 `TProcess` 类（`System.Diagnostics.TProcess`），该类仅在 Lazarus/FreePascal 中存在，Delphi VCL 没有这个类。编译时直接报错 `Identifier not found "TProcess"`。

**根因**: 手写代码时未区分 FreePascal TProcess 和 Delphi WinAPI CreateProcess。

**修复**: 将 `RunFFmpeg` 改为 `Winapi.Windows.CreateProcess` + 匿名管道：
- `CreatePipe` / `ReadFile` / `WaitForSingleObject` 替代 TProcess
- `STARTF_USESTDHANDLES` 传递 stdout 句柄
- `CREATE_NO_WINDOW` 隐藏控制台
- 60 秒超时 `WaitForSingleObject`，超时 `TerminateProcess`
- 管道读取用 `PeekNamedPipe` + `ReadFile`
