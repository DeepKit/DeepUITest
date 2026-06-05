# DeepFrames Bugfix Log

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
