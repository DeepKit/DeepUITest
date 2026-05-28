# 需求文档：AIErrorHandler 全工作区铺开（aierrorhandler-rollout）

## 简介

`02Business\DeepBase\Core\DeepBase.AIErrorHandler.pas` 已经实现了一个 AI 自动处理运行时错误的部件。它能：

- 全局接管 `Application.OnException`
- 把异常分成 4 级（`elIgnore` / `elAutoFix` / `elAIAnalyze` / `elFatal`）
- 通过 `SetAICallback` 接 LLM，给最终用户出友好提示
- 自带 50 条 LLM 响应缓存与 8000ms 超时
- 提供 `SafeRun(context, proc)` 包裹业务代码

本 spec 的任务是把这个部件**铺开到 02Business 工作区中所有 .dpr 入口程序**（约 90 个），覆盖：

- 全部主程序（DeepSpec、DeepDev、DeepSync、DeepClip、DeepStory、DeepInsight、DeepSVG、DeepDevLite、DeepCharset、DeepConfig、DeepMoveC、DeepCompare、DeepInput、DeepShine、Assayer、DeepBase 自带工具等）
- 全部测试 / Smoke / Behavior / Governance 入口（约 60 个）

铺开过程必须保证：

1. 不破坏当前编译干净状态（已有 15 个主程序 + AssayerProxy + DeepShine 编译通过）
2. 不与 DeepSpec 等程序中已经存在的 `TAutoFixErrorRecorderVCL.HookApplication` 冲突（两者都接管 `Application.OnException`，必须串接而不是互相覆盖）
3. 测试程序运行时不会因为 `MessageDlg` 弹窗而卡住自动化运行器
4. LLM 调用通过现有 `DeepBase.LLM.Service.LLM().Chat` 进入，不重复造轮子

## 术语表

- **AIErrorHandler**：现有部件 `DeepBase.AIErrorHandler.pas`，导出 `TAIErrorHandler` 类与 `SafeRun` 过程
- **AutoFix_Recorder**：现有部件 `DeepBase.AutoFix.ErrorRecorder.pas` 与 `DeepBase.AutoFix.ErrorRecorder.VCL.pas`，把异常写到 JSONL 供 AutoFix 流水线消费
- **Bootstrap_Unit**：本 spec 新增单元 `DeepBase.AIErrorHandler.Bootstrap.pas`，对外暴露一行调用的 `InstallAIErrorHandler` 系列入口
- **LLM_Bridge**：本 spec 新增辅助单元 `DeepBase.AIErrorHandler.LLMBridge.pas`，把 `TAIAnalysisCallback` 桥接到 `DeepBase.LLM.Service.LLM().Chat`
- **Entry_Program**：02Business 工作区下任意 `.dpr` 文件，编译产物为可执行入口
- **Main_Program**：发布给最终用户的 `Entry_Program`（如 DeepSpec、DeepDev、DeepClip 等）
- **Tool_Program**：DeepBase 自带的 CLI 与辅助工具（如 DeepBase CLI、DeepPublisher、SeedTool、UpdaterHelper 等）
- **Test_Program**：用于测试 / Smoke / Behavior / Governance 的 `Entry_Program`，路径或文件名含 `Test`、`Smoke`、`Behavior`、`Governance` 中的任一关键字
- **Test_Mode**：Bootstrap_Unit 的运行模式之一，AIAnalyze 路径**不**调用 `MessageDlg`，仅写日志；遇到 `elFatal` 时以非零退出码退出
- **Production_Mode**：Bootstrap_Unit 的默认运行模式，行为与现有 `TAIErrorHandler.Handle` 一致（含 `MessageDlg`）
- **Deep_LLM_Service**：现有 LLM 门面，调用形式 `DeepBase.LLM.Service.LLM().Chat(ATier, ASystemPrompt, AUserPrompt)`，返回 `TChatResult`

## 需求清单

### 需求 1：提供 Bootstrap 一行入口

**用户故事**：作为 DeepBase 维护者，我希望每个 `.dpr` 只用一行代码就能装上 AIErrorHandler，这样 90 个入口的铺开成本可控、未来升级也能集中改一处。

#### 验收准则

1. THE Bootstrap_Unit SHALL 导出过程 `InstallAIErrorHandler`，该过程在内部完成 AIErrorHandler 安装、LLM_Bridge 接线、AutoFix_Recorder 协同三步。
2. THE Bootstrap_Unit SHALL 导出过程 `InstallAIErrorHandlerForTests`，等价于以 Test_Mode 调用 `InstallAIErrorHandler`。
3. WHEN `InstallAIErrorHandler` 被同一进程调用多次，THE Bootstrap_Unit SHALL 仅生效首次调用，后续调用必须直接返回且不报错。
4. THE Bootstrap_Unit SHALL 不依赖任何 GUI 单元，使其可被纯控制台 `Entry_Program` 引用而不强行引入 `Vcl.Forms`。
5. WHERE 调用方传入自定义 `TAIErrorConfig`，THE Bootstrap_Unit SHALL 用该配置初始化 AIErrorHandler；未传入时使用 `TAIErrorConfig.Default`。

### 需求 2：Test_Mode 必须非交互

**用户故事**：作为运行测试的开发者，我希望测试程序在抛出未处理异常时不会被 `MessageDlg` 弹窗卡死，而是直接记录并以非零退出码结束，这样 CI 与本地批量测试都能继续推进。

#### 验收准则

1. WHILE Bootstrap_Unit 处于 Test_Mode，THE Bootstrap_Unit SHALL 阻止 AIErrorHandler 调用 `MessageDlg`，对所有 `elAIAnalyze` 与 `elFatal` 级别异常仅写日志。
2. WHEN Test_Mode 下捕获到 `elFatal` 级别异常，THE Bootstrap_Unit SHALL 把进程的 `ExitCode` 设置为 1 并调用 `Halt(1)` 或等价机制结束进程。
3. THE Bootstrap_Unit SHALL 通过环境变量 `DEEP_AIEH_MODE=test` 与编译指令 `{$DEFINE DEEPBASE_AIEH_TEST}` 两种途径之一触发 Test_Mode；任一条件命中即视为进入 Test_Mode。
4. WHEN `InstallAIErrorHandlerForTests` 被调用，THE Bootstrap_Unit SHALL 强制进入 Test_Mode，与上述环境变量、编译指令的状态无关。
5. IF 在 Test_Mode 下 LLM_Bridge 调用失败或超时，THEN THE Bootstrap_Unit SHALL 记录降级日志并继续运行，不向标准输出/错误输出写入未指定的内容。

### 需求 3：与 AutoFix_Recorder 共存不冲突

**用户故事**：作为 DeepSpec 等已经接入 AutoFix 流水线的程序的维护者，我希望铺开 AIErrorHandler 之后，AutoFix_Recorder 仍能拿到全部异常记录，AutoFix JSONL 不能丢数据。

#### 验收准则

1. WHEN Bootstrap_Unit 安装 AIErrorHandler 时检测到 `Application.OnException` 已被赋值，THE Bootstrap_Unit SHALL 在覆盖前保存原回调，并在自身处理完成后调用原回调。
2. WHEN Bootstrap_Unit 与 `TAutoFixErrorRecorderVCL.HookApplication` 在同一 `.dpr` 内被调用，THE Bootstrap_Unit SHALL 保证两者无论调用顺序，最终 `Application.OnException` 触发时 AutoFix_Recorder 与 AIErrorHandler 都被执行恰好一次。
3. IF AutoFix_Recorder 已经把异常归类为可恢复（`elAutoFix` 等价语义），THEN THE Bootstrap_Unit SHALL 仍允许 AIErrorHandler 按其自有分类继续处理，不强制提前返回。
4. THE Bootstrap_Unit SHALL 不修改 `System.ExceptProc`，把全局未处理异常通道留给 AutoFix_Recorder。

### 需求 4：LLM 桥接复用现有服务

**用户故事**：作为 DeepBase LLM 子系统的维护者，我希望 AIErrorHandler 调用 LLM 时走我已经测试好的门面 `LLM().Chat`，不要绕开统一计费、统一缓存、统一容错。

#### 验收准则

1. THE LLM_Bridge SHALL 把传入的 prompt 字符串通过 `DeepBase.LLM.Service.LLM().Chat` 调用，并把返回的 `TChatResult` 中的文本字段返回给 AIErrorHandler。
2. WHEN `LLM().Chat` 抛出异常或返回失败状态，THE LLM_Bridge SHALL 返回空字符串，不向上抛出，使 AIErrorHandler 走降级文案分支。
3. THE LLM_Bridge SHALL 在调用 `LLM().Chat` 时使用 `TModelTier` 中代表"日常对话/小模型"的等级；具体等级名称由设计阶段确定，需求阶段不强制。
4. WHEN Deep_LLM_Service 因依赖单元未链接而无法解析，THE LLM_Bridge SHALL 通过条件编译或运行时探测保持自身可编译；找不到 LLM 服务时回退到空字符串行为。

### 需求 5：保证 AIErrorHandler 自身可编译

**用户故事**：作为铺开任务的执行者，我希望在把 AIErrorHandler 加到 90 个 `.dpr` 之前，先确认它本身能编译通过，不要在 90 个项目里同时报同一种错。

#### 验收准则

1. THE rollout 流程 SHALL 在试点植入前对 `DeepBase.AIErrorHandler.pas` 执行一次独立编译验证。
2. IF `DeepBase.AIErrorHandler.pas` 当前对 `DeepBase.Logging` 的调用形式与 Logging 单元的实际公开 API 不匹配，THEN THE rollout 流程 SHALL 在 Bootstrap_Unit 落地前修正该不匹配，使 AIErrorHandler 单独编译通过。
3. THE rollout 流程 SHALL 不修改 AIErrorHandler 的对外签名（`Install` / `SetAICallback` / `Handle` / `SafeRun` 的形参与可见性），仅允许修复内部实现细节与 uses 子句。
4. WHEN AIErrorHandler 内部修复完成，THE rollout 流程 SHALL 重新跑全部既有编译干净项目（15 主程序 + AssayerProxy + DeepShine）以确认未引入回归。

### 需求 6：覆盖所有 Main_Program 与 Tool_Program

**用户故事**：作为最终用户，我希望我用到的每个 DeepBase 系列程序遇到崩溃时都能给我一句友好的话，而不是冷冰冰的英文异常框。

#### 验收准则

1. THE rollout 流程 SHALL 在 02Business 工作区每一个具备 `.dpr` 的 Main_Program 中调用一次 `Bootstrap_Unit.InstallAIErrorHandler`。
2. THE rollout 流程 SHALL 在 02Business 工作区每一个 Tool_Program（DeepBase CLI、DeepBaseTray、DeepPublisher、SeedTool、UpdaterHelper、Studio 入口等）中调用一次 `Bootstrap_Unit.InstallAIErrorHandler`。
3. WHEN Main_Program 或 Tool_Program 已存在 `Application.OnException` 安装语句（如 `TAutoFixErrorRecorderVCL.HookApplication`），THE rollout 流程 SHALL 把 `InstallAIErrorHandler` 调用放在 `Application.Initialize` 之后、原有 hook 之前或之后均可，但必须满足需求 3 的链式调用语义。
4. WHERE Main_Program 是纯控制台或 FMX 程序而非标准 VCL，THE rollout 流程 SHALL 仍调用 `InstallAIErrorHandler`，由 Bootstrap_Unit 内部判断 `Application` 是否可用并选择合适的安装路径。
5. THE rollout 流程 SHALL 排除当前没有 `.dpr` 入口的搁置项目（DeepAssist、DeepFlow、DeepGuide、DeepJourney、DeepUITest、DeepUse），不向其凭空增加 `.dpr`。

### 需求 7：覆盖所有 Test_Program

**用户故事**：作为做自动化测试的开发者，我希望测试运行过程中冒出来的运行时异常也能被 AI 帮我看一眼，给出诊断思路写进日志，方便我事后查。

#### 验收准则

1. THE rollout 流程 SHALL 在 02Business 工作区每一个 Test_Program 的 `.dpr` 中调用一次 `Bootstrap_Unit.InstallAIErrorHandlerForTests`。
2. WHILE Test_Program 运行，THE Bootstrap_Unit SHALL 把 AIAnalyze 与 Fatal 路径的输出全部写入日志，不弹任何 GUI 对话框。
3. WHEN Test_Program 因未处理 `elFatal` 异常退出，THE Bootstrap_Unit SHALL 让进程以非零退出码退出，便于测试运行器识别失败。
4. THE rollout 流程 SHALL 不修改 Test_Program 既有断言框架与测试入口逻辑，仅在 `begin..end.` 起始处插入一行 `InstallAIErrorHandlerForTests`。

### 需求 8：分批落地与编译验证

**用户故事**：作为本次铺开任务的执行者，我希望任务被切成可独立执行的小批次，每批做完都能编译验证一次，避免一锅端导致难以定位的回归。

#### 验收准则

1. THE rollout 流程 SHALL 把 `.dpr` 列表按产品/工具/测试维度切分成若干批次，每批不超过 8 个 `.dpr`。
2. WHEN 一个批次内的 `.dpr` 全部完成 Bootstrap_Unit 调用插入，THE rollout 流程 SHALL 至少触发一次该批次范围内的编译验证（独立 dcc64 命令或 `compile_all.bat` 子集）。
3. IF 任一批次编译失败，THEN THE rollout 流程 SHALL 在修复该批次之前不进入下一批次。
4. THE rollout 流程 SHALL 把每个批次的 `.dpr` 清单与编译结果写入 `02Business/.kiro/specs/aierrorhandler-rollout/` 下的执行记录文件，便于人工复核。
5. THE rollout 流程 SHALL 在第一批正式铺开前选择 1 个 Main_Program 作为试点（建议 DeepSpec），完成端到端验证（启动、人为抛异常、看到友好提示、AutoFix JSONL 仍写入）后再继续。

### 需求 9：植入修改的可逆性与可审计

**用户故事**：作为代码评审者，我希望每个 `.dpr` 的改动量小、改法统一，万一要回滚也能一眼看出。

#### 验收准则

1. THE rollout 流程 SHALL 对每个 `.dpr` 的修改限制为：在 uses 子句新增 1 个 unit 引用、在 `begin..end.` 块起始处新增 1 行调用，共 2 处变更。
2. THE rollout 流程 SHALL 不删除 `.dpr` 现有任何 uses 项与代码行。
3. WHEN 同一 `.dpr` 被反复执行铺开任务，THE rollout 流程 SHALL 检测已存在的 Bootstrap_Unit 引用并跳过该文件，不重复插入。
4. THE rollout 流程 SHALL 把修改前后的 `.dpr` 通过 git diff 留痕，确保任何一次改动都能用 `git revert` 单独回退。

### 需求 10：错误处理与降级

**用户故事**：作为最终用户，我不希望 AIErrorHandler 自己崩了反而把宿主程序也带崩。

#### 验收准则

1. IF LLM_Bridge 在调用 LLM 时抛出异常，THEN THE Bootstrap_Unit SHALL 吞掉该异常并使 AIErrorHandler 走降级文案分支。
2. IF Bootstrap_Unit 在 `InstallAIErrorHandler` 自身执行过程中发生异常，THEN THE Bootstrap_Unit SHALL 把异常吞掉并向 `OutputDebugString` 写一条诊断信息，不向上抛出，宿主程序应能继续 `Application.Run`。
3. WHEN AutoFix_Recorder 不可用（未 Install 或未激活），THE Bootstrap_Unit SHALL 仍能正常工作，不依赖 AutoFix_Recorder 的存在。
4. WHEN AIErrorHandler 的内部缓存被清空或损坏，THE Bootstrap_Unit SHALL 不因此中断异常处理流程，必要时让缓存命中失败、走 LLM 实时调用或降级文案。
