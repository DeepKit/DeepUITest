# 实施计划：AIErrorHandler 全工作区铺开（aierrorhandler-rollout）

## 概述

本任务清单把 `02Business/.kiro/specs/aierrorhandler-rollout/design.md` 中的设计转换成一系列由 code-generation LLM 增量执行的实施步骤。每个任务可由独立 sub-agent 执行；任务之间增量推进，互不悬空。所有任务只涉及代码与测试改动。

## 约定

- 任务编号采用最多两级（X、X.Y）
- 子任务后缀 `*` 表示**可选**（测试类，跳过不影响发布）
- 每个任务结尾的 `_Requirements:_` 引用 `requirements.md` 中的具体条款
- 每个属性测试任务都引用 design.md 中的具体 Property 编号
- 涉及到的路径全部以 `02Business/` 为根

---

## 任务清单

### 阶段一：核心单元就位

- [x] 1. 修复并扩展 `DeepBase.AIErrorHandler.pas`（加性修改）
  - 核心目标：让该单元能独立 dcc64 通过、与既有 Logging API 对齐、为 Bootstrap 落地准备好链式挂钩与 SilentMode
  - 任何对外可见的方法签名（`Install` / `SetAICallback` / `Handle` / `SafeRun`）都不允许改动；只允许：(a) 在 `TAIErrorConfig` 末尾追加 `SilentMode: Boolean`、(b) 添加私有 `FOldAppException` 字段、(c) 改 `Install` 与 `DoApplicationException` 实现以链式调用旧回调、(d) 修正 `DeepBase.Logging` 调用形式
  - _Requirements: 5.1, 5.2, 5.3, 3.1_

  - [x] 1.1 修正 `DeepBase.Logging` 调用形式
    - 阅读 `02Business/DeepBase/Core/DeepBase.Logging.pas` 的 interface 段，确认实际可用的全局/静态日志入口与 `TLogLevel` 常量名（如 `llError`、`llWarn`、`llWarning`）
    - 把 AIErrorHandler.pas 中所有 `DeepBase.Logging.Log(ltError, …)` / `DeepBase.Logging.Log(ltWarning, …)` 调用换成实际可解析的形式（推荐通过 `TDeepBaseLogger` 的全局实例或新增的薄包装）
    - 不改对外签名，只改实现
    - _Requirements: 5.2_

  - [x] 1.2 在 `TAIErrorConfig` 末尾追加 `SilentMode: Boolean` 字段
    - 修改 `TAIErrorConfig` record 与 `TAIErrorConfig.Default` 类方法
    - `Default` 中将该字段初始化为 `False`
    - _Requirements: 2.1, 7.2_

  - [x] 1.3 为 `TAIErrorHandler` 增加 `FOldAppException` 字段并改造 `Install` 为链式
    - 在 `class var` 中增加 `FOldAppException: TExceptionEvent`
    - `Install(const AConfig)` 实现中：先 `FOldAppException := Application.OnException;`，再 `Application.OnException := DoApplicationException;`
    - `DoApplicationException` 中：`Handle(E)` 之后 `if Assigned(FOldAppException) then FOldAppException(Sender, E);`
    - _Requirements: 3.1, 3.2_

  - [x] 1.4 在 `Handle` 中根据 `SilentMode` 切换 MessageDlg 与 Halt 行为
    - `elAIAnalyze` 分支：`if not FConfig.SilentMode then MessageDlg(…);` 包裹
    - `elFatal` 分支：`SilentMode = True` 时 `ExitCode := 1; Halt(1);` 替代 `Application.Terminate`；`SilentMode = False` 时维持 `MessageDlg + Application.Terminate`
    - 日志写入与降级文案构造逻辑保持不变
    - _Requirements: 2.1, 2.2, 7.2, 7.3_

  - [ ]* 1.5 编写 SilentMode 行为属性测试
    - 测试单元：`02Business/DeepBase/Tests/Test.DeepBase.AIErrorHandler.SilentMode.pas`
    - **Property 2: Test_Mode 静默不阻塞**
    - **Validates: Requirements 2.1, 2.5, 7.2**
    - 用 mock `MessageDlg` 接缝（或在 `Handle` 中插入可注入的 `TUserMessageProc` 钩子）验证 SilentMode=True 时不调用
    - 至少 100 轮随机异常输入

  - [ ]* 1.6 编写 Fatal 退出码属性测试
    - 测试单元：同 1.5 测试单元（追加测试方法）
    - **Property 3: Fatal 异常以非零退出码终止**
    - **Validates: Requirements 2.2, 7.3**
    - 用 mock `TerminateProc` 接缝替换 `Halt`/`Application.Terminate`，断言被调用一次且 `ExitCode = 1`

  - [ ]* 1.7 编写日志写入属性测试
    - **Property 13: 任意被处理异常都写一条日志**
    - **Validates: Requirements 5.2**
    - 用 mock 日志收集器，断言对任意非 `elIgnore` 异常都恰好产生一条记录

- [x] 2. 新增 LLMBridge 单元 `DeepBase.AIErrorHandler.LLMBridge.pas`
  - 路径：`02Business/DeepBase/Core/DeepBase.AIErrorHandler.LLMBridge.pas`
  - 接口：`procedure InstallLLMBridge;`
  - 实现：构造一个匿名 `TAIAnalysisCallback`，内部 try..except 调 `DeepBase.LLM.Service.LLM().Chat(<small tier>, APrompt)`，成功取 `Content`，失败/异常返回空串；调 `TAIErrorHandler.SetAICallback(LCallback)`
  - tier 选用：阅读 `02Business/DeepBase/Core/DeepBase.LLM.Types.pas` 找出代表"小模型/对话级"的 `TModelTier` 成员（如 `mtSmall`/`mtChat`），写到一个常量并 TODO 注释说明依据
  - 不依赖 GUI 单元，不直接触达 HTTP 层
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 10.1_

  - [x] 2.1 实现 LLMBridge 主体并 dcc64 单独编译验证
    - 创建文件、写完 interface + implementation
    - 用 dcc64 编译该单元（`-U` 加 DeepBase Core/Features 路径）确认 ExitCode=0
    - _Requirements: 4.1, 4.4_

  - [ ]* 2.2 编写 LLMBridge 透传成功结果属性测试
    - 测试单元：`02Business/DeepBase/Tests/Test.DeepBase.AIErrorHandler.LLMBridge.pas`
    - **Property 7: LLMBridge 透传成功结果**
    - **Validates: Requirements 4.1**
    - 通过测试时把 `LLM` 工厂换成 mock；mock 返回随机 `TChatResult{Success: True; Content: c}`；断言桥接回调输出 = c

  - [ ]* 2.3 编写 LLMBridge 失败降级属性测试
    - 同 2.2 测试单元
    - **Property 8: LLM 失败 / 缓存损坏 → 空串与降级**
    - **Validates: Requirements 4.2, 10.1, 10.4**
    - 覆盖 5 种失败模式：抛异常、Success=False、Content=''、服务不可用、FCache=nil

  - [ ]* 2.4 编写 LLMBridge tier 常量断言示例测试
    - 同 2.2 测试单元
    - **Validates: Requirements 4.3 / Example E1**
    - mock 捕获 `Chat` 调用的 `ATier` 参数，断言等于设计选定常量

- [x] 3. 新增 Bootstrap 单元 `DeepBase.AIErrorHandler.Bootstrap.pas`
  - 路径：`02Business/DeepBase/Core/DeepBase.AIErrorHandler.Bootstrap.pas`
  - 接口：`InstallAIErrorHandler` (含 overload)、`InstallAIErrorHandlerForTests`、`IsTestMode`、`TAIErrorBootstrapMode` 类型
  - 实现：解析 mode（环境变量 `DEEP_AIEH_MODE` + 编译指令 `{$DEFINE DEEPBASE_AIEH_TEST}`）→ 构造 `TAIErrorConfig`（Test_Mode 时 `SilentMode := True`）→ 调 `TAIErrorHandler.Install(LConfig)` → 调 `LLMBridge.InstallLLMBridge` → 全过程 try..except 包裹，异常写 `OutputDebugString`；幂等 class var FInstalled
  - interface uses 段**不**引入 `Vcl.Dialogs`、`Vcl.Controls`、`FMX.Dialogs`、`FMX.Controls`
  - 不修改 `System.ExceptProc`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.3, 2.4, 10.2_

  - [x] 3.1 实现 Bootstrap 主体
    - 编写完整 interface + implementation
    - 在 `IsTestMode` 中实现真值表：`SameText(GetEnvironmentVariable('DEEP_AIEH_MODE'), 'test') OR {$IFDEF DEEPBASE_AIEH_TEST} True {$ELSE} False {$ENDIF}`
    - `InstallAIErrorHandler` 重复调用幂等：通过 class var `FInstalled` 守卫
    - _Requirements: 1.1, 1.2, 1.3, 1.5_

  - [x] 3.2 dcc64 单独编译验证 Bootstrap 单元
    - 编译命令：`dcc64 -U"<Core paths>" DeepBase.AIErrorHandler.Bootstrap.pas`
    - 断言 ExitCode=0
    - _Requirements: 1.4_

  - [ ]* 3.3 编写 Install 后置条件属性测试
    - 测试单元：`02Business/DeepBase/Tests/Test.DeepBase.AIErrorHandler.Bootstrap.pas`
    - **Property 1: Install 后置条件**
    - **Validates: Requirements 1.1, 1.5, 5.3**
    - 任意 `TAIErrorConfig` 输入 + 任意 `TAIErrorBootstrapMode` 取值，安装后断言：`Application.OnException` 已赋、`TAIErrorHandler.Config` 字段级相等、`FAICallback` 已设

  - [ ]* 3.4 编写 IsTestMode 真值表属性测试
    - **Property 4: IsTestMode 真值表**
    - **Validates: Requirements 2.3, 2.4**
    - 模拟 4 组（环境变量×编译指令）真值表，断言输出等于 OR

  - [ ]* 3.5 编写 Bootstrap 幂等属性测试
    - **Property 10: Bootstrap 重复调用幂等**
    - **Validates: Requirements 1.3, 9.3**
    - 任意自然数 n ≥ 1 与任意 mode，连续调用 n 次后状态等于调用 1 次；首次返回 True、后续 False

  - [ ]* 3.6 编写 Bootstrap 自身异常吞掉属性测试
    - **Property 11: Bootstrap 自身异常被吞掉**
    - **Validates: Requirements 10.2**
    - 在测试中替换 `LLMBridge.InstallLLMBridge` 为抛异常版本，断言 `InstallAIErrorHandler` 仍返回不抛

  - [ ]* 3.7 编写 Bootstrap 静态约束属性测试
    - **Property 6: Bootstrap 静态约束**
    - **Validates: Requirements 1.4, 3.4**
    - 用 `TFile.ReadAllText` 读 Bootstrap.pas 源码，断言 interface 段不出现禁用 unit 名、不出现 `ExceptProc` 赋值

  - [ ]* 3.8 编写 AutoFix 共存合流属性测试
    - **Property 5: 与既有 OnException Hook 的合流（Confluence）**
    - **Validates: Requirements 3.1, 3.2, 3.3**
    - 构造任意计数器 closure 作为旧回调集合 + 引入 `TAutoFixErrorRecorderVCL.HookApplication`，两种安装顺序、任意异常输入，断言所有回调各被调用一次

  - [ ]* 3.9 编写 AutoFix 状态透明属性测试
    - **Property 12: AutoFix 状态对 Bootstrap 透明**
    - **Validates: Requirements 10.3**
    - 在 `TAutoFixErrorRecorder.Active = True/False` 两种状态下 Install，对比 Bootstrap 自身后置条件相同

- [x] 4. 检查点：核心单元独立编译 + 既有项目回归
  - 全部通过后才能进入阶段二
  - _Requirements: 5.1, 5.4_

  - [x] 4.1 dcc64 单独编译三个核心单元
    - `DeepBase.AIErrorHandler.pas`
    - `DeepBase.AIErrorHandler.LLMBridge.pas`
    - `DeepBase.AIErrorHandler.Bootstrap.pas`
    - 断言三个 ExitCode=0；输出存到 `02Business/.kiro/specs/aierrorhandler-rollout/exec-log/checkpoint-4.1.md`

  - [x] 4.2 全量回归既有 15 个主程序 + AssayerProxy + DeepShine
    - 跑 `02Business/compile_all.bat` 与 `02Business/tasks.md` 中列出的独立编译命令
    - 断言全部 ExitCode=0；输出存到 `02Business/.kiro/specs/aierrorhandler-rollout/exec-log/checkpoint-4.2.md`
    - 失败则停止，回到任务 1/2/3 排查

  - [x] 4.3 检查点 - 确保所有测试通过，遇到问题询问用户
    - 如果阶段一选了任何 `*` 子任务，运行所属测试套件
    - 确保所有测试通过，遇到问题询问用户

---

### 阶段二：清单与试点

- [x] 5. 扫描全工作区生成 .dpr 清单与分组
  - 产物路径：`02Business/.kiro/specs/aierrorhandler-rollout/dpr-inventory.md`
  - 用 `Get-ChildItem -Path d:\_Progs\02Business -Recurse -Filter *.dpr` 拿全集
  - 排除：搁置项目（DeepAssist、DeepFlow、DeepGuide、DeepJourney、DeepUITest、DeepUse）、`__history` 路径、本期 FMX 出范围（DeepDev、DeepDevLite，单独标注待后续 spec 处理）
  - 按"产品归属 + 是否 Test_Program"分组：每组 ≤ 8 个，标注分组号 G1..GN
  - 每个 .dpr 标注：`Type ∈ {Pilot, Main, Tool, Test}`、是否已含 AutoFix Hook
  - _Requirements: 6.1, 6.2, 6.4, 6.5, 7.1, 8.1_

  - [x] 5.1 扫描全集并落盘
    - 生成清单 markdown，每行：`| 组号 | 路径 | Type | 已有 AutoFix |`
    - 末尾包含 FMX 出范围列表与搁置项目列表（注明未编入分组的原因）

  - [ ]* 5.2 编写清单结构属性测试
    - 测试单元：`02Business/DeepBase/Tests/Test.DeepBase.AIErrorHandler.Rollout.pas`
    - **Property 16: 分组清单结构约束**
    - **Validates: Requirements 8.1**
    - 解析 dpr-inventory.md，断言每组 ≤ 8 个、并集 == 扫描全集（减去出范围与搁置项）

- [x] 6. 试点：DeepSpec 植入 + 端到端验证
  - 唯一文件：`02Business/DeepSpec/DeepSpec.dpr`
  - 该程序既有 `TAutoFixErrorRecorder.Install + TAutoFixErrorRecorderVCL.HookApplication`，是验证 confluence 的最佳试点
  - _Requirements: 6.1, 6.3, 8.5_

  - [x] 6.1 修改 DeepSpec.dpr：新增 1 行 uses + 1 行调用
    - uses 段新增：`DeepBase.AIErrorHandler.Bootstrap,`（紧邻 `DeepBase.AutoFix.ErrorRecorder.VCL,`）
    - `begin..end.` 起始处新增：`InstallAIErrorHandler;`（建议放在 `TAutoFixErrorRecorder.Install;` 之前）
    - 不删除任何既有行
    - _Requirements: 9.1, 9.2_

  - [x] 6.2 编译 DeepSpec
    - 用 tasks.md 中给出的 dcc64 命令（参考 `compile_all.bat`）
    - 断言 ExitCode=0；输出存到 `exec-log/pilot-deepspec.md`

  - [x] 6.3 端到端烟测：运行 DeepSpec 并注入测试异常
    - 启动 DeepSpec（带或不带 `--autofix-mode`），通过菜单/钩子触发一次 `EConvertError` 与一次普通 `Exception`
    - 验证：(a) 看到 AIErrorHandler 的友好提示弹窗（Production_Mode）、(b) AutoFix JSONL 仍有写入
    - 输出存到 `exec-log/pilot-deepspec-smoke.md`
    - _Requirements: 3.2, 3.3_

  - [x] 6.4 检查点 - 试点通过后才进入阶段三
    - 试点失败则回到任务 1/3 修复，再重跑试点

---

### 阶段三：Main_Program 分批铺开

> 每个分组任务的执行规程相同，命名后续以"X 组 Z"区分。每组任务都需要：
> 1. 对组内每个 .dpr 应用模板：1 行 uses + 1 行 `InstallAIErrorHandler;`
> 2. 跳过已含 Bootstrap 引用的文件
> 3. 编译该组每个 .dpr，输出到 `exec-log/group-<组号>.md`
> 4. 任一编译失败 → 该组回滚，停止后续

- [x] 7. 第 G2 组：DeepCharset、DeepConfig、DeepMoveC、DeepClip、DeepSync
  - 对应 5 个独立 dcc64 命令在 `02Business/tasks.md` 中已给出
  - _Requirements: 6.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 7.1 修改 5 个 .dpr 文件
    - 路径列表由任务 5 的清单提供
    - 模板：植入模板 4.1（标准 VCL）

  - [x] 7.2 dcc64 编译该组
    - 输出存到 `exec-log/group-G2.md`；任一失败即回滚停下

- [x] 8. 第 G3 组：DeepStory、DeepInsight、DeepSVG、DeepShine（4 个）
  - 注意 DeepDevLite 已被 FMX 出范围列表移除
  - _Requirements: 6.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 8.1 修改 4 个 .dpr 文件
  - [x] 8.2 dcc64 编译该组，输出 `exec-log/group-G3.md`

- [x] 9. 第 G4 组：DeepCompare 系列、DeepInput 系列、Assayer、AssayerProxy
  - DeepCompare 与 DeepInput 各自有多个 .dpr，需视清单实际分布；如总数 > 8 则拆成 G4a / G4b
  - _Requirements: 6.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 9.1 修改组内 .dpr 文件
  - [x] 9.2 dcc64 编译该组，输出 `exec-log/group-G4.md`

- [x] 10. 检查点 - Main 组全部完成后回归
  - 重跑 `02Business/compile_all.bat`，输出存到 `exec-log/checkpoint-10.md`
  - 确保所有测试通过，遇到问题询问用户
  - _Requirements: 5.4, 8.3_

---

### 阶段四：Tool_Program 分批铺开

- [x] 11. 第 G5 组：DeepBase CLI、DeepBaseRun、DeepBaseTray、DeepPublisher
  - 这些是 DeepBase 自家工具；多数为 VCL Console，使用模板 4.3
  - _Requirements: 6.2, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 11.1 修改 4 个 .dpr 文件
  - [x] 11.2 dcc64 编译该组，输出 `exec-log/group-G5.md`

- [x] 12. 第 G6 组：SeedTool、UpdaterHelper、Studio 入口及其余 DeepBase 工具
  - 总数视任务 5 清单决定；> 8 则拆 G6a/G6b
  - _Requirements: 6.2, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 12.1 修改组内 .dpr 文件
  - [x] 12.2 dcc64 编译该组，输出 `exec-log/group-G6.md`

---

### 阶段五：Test_Program 分批铺开

> 全部使用模板 4.4：调 `InstallAIErrorHandlerForTests`（强制 Test_Mode）。

- [ ] 13. Test 组 G7：`02Business/DeepBase/Tests/` 下首批 ≤ 8 个 .dpr
  - 优先覆盖 LLM/Logging/Persistence 等核心测试入口
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 13.1 修改组内 .dpr 文件
  - [x] 13.2 dcc64 编译该组，输出 `exec-log/group-G7.md`

- [x] 14. Test 组 G8：DeepBase Smoke / Behavior 入口 ≤ 8 个
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 14.1 修改组内 .dpr 文件
  - [x] 14.2 dcc64 编译该组，输出 `exec-log/group-G8.md`

- [ ] 15. Test 组 G9：DeepBase Governance 入口 ≤ 8 个
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 15.1 修改组内 .dpr 文件
  - [ ] 15.2 dcc64 编译该组，输出 `exec-log/group-G9.md`

- [x] 16. Test 组 G10..GN：剩余各产品的 Tests/ 子目录 .dpr
  - 按产品（DeepCompare/DeepInput/DeepInsight 等）每组 ≤ 8 个；具体编号由任务 5 清单决定
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

  - [x] 16.1 按子组修改 .dpr 文件
  - [x] 16.2 按子组 dcc64 编译，每子组输出独立 `exec-log/group-G<n>.md`

---

### 阶段六：静态校验与最终检查点

- [ ] 17. 编写并运行铺开静态校验（一次性扫描整个清单）
  - _Requirements: 6.1, 6.2, 6.4, 7.1, 9.1, 9.2, 9.3_

  - [ ]* 17.1 编写 .dpr 改造覆盖属性测试
    - 测试单元：`02Business/DeepBase/Tests/Test.DeepBase.AIErrorHandler.Rollout.pas`（追加方法）
    - **Property 14: .dpr 清单内每个文件都被改造**
    - **Validates: Requirements 6.1, 6.2, 6.4, 7.1**
    - 解析 dpr-inventory.md 与每个 .dpr 文件，断言：Main/Tool 包含一处 `InstallAIErrorHandler` 调用；Test 包含一处 `InstallAIErrorHandlerForTests` 调用；两者不在同一个 .dpr 中

  - [ ]* 17.2 编写 .dpr 改动 diff 限制属性测试
    - 同 17.1 测试单元
    - **Property 15: .dpr 改动 diff 限制**
    - **Validates: Requirements 9.1, 9.2, 9.3**
    - 用 `git diff --numstat` 解析每个 .dpr 的 added/deleted 行数，断言 added=2、deleted=0
    - 同一文件第二次执行铺开应跳过（验证幂等）

- [ ] 18. 最终检查点 - 全工作区编译干净
  - 跑 `02Business/compile_all.bat` 全集 + 所有手写 dcc64 命令
  - 输出存到 `exec-log/checkpoint-18-final.md`
  - 确保所有测试通过，遇到问题询问用户
  - _Requirements: 5.4, 8.3_

---

## 注释

- 标 `*` 的子任务（共 16 个属性/示例测试相关项）可在 MVP 中跳过；核心植入与编译验证不可跳过
- 阶段三/四/五的分组数（G2..GN）以任务 5 输出的实际清单为准；本计划中 G7..G10 与 G6/G9 的具体子拆分允许在执行时按"≤ 8 个/组"原则微调
- 出范围项目（DeepDev、DeepDevLite 的 FMX 入口；DeepAssist、DeepFlow、DeepGuide、DeepJourney、DeepUITest、DeepUse 因无 .dpr）在任务 5 清单尾部以独立小节标注，不进入任务 7..16
- 所有 dcc64 输出与 git diff 结果都落盘到 `02Business/.kiro/specs/aierrorhandler-rollout/exec-log/` 下，便于事后审计
- 任何分组任务的失败处理：本批 `git checkout -- <files>` 回滚 → 修复阶段一/二的根因 → 重跑该批
