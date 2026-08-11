# DeepSpec 开发历史

> 已完成的任务归档于此。按时间倒序排列。

---

## 2026-08-06 SPW 发布审计 + 修复（bugfix.md #15）

### SPW 审计（首次为 DeepSpec 建立门禁）
- [x] 新建 `spw-manifest.json`（delphi_gui 画像，H1-H4 确定性门禁 + 3 条项目 H4 旁路模式 + GLM/StepFun 异构观察）
- [x] H1 resource-locks：DeepBase 依赖就位、src 引用全部可解析；**确认 BUG-6b 未修**（非 submodule 非 vendored）
- [x] H2 compile-build：主程序 47369 lines 0 error；H2 unit-tests：97/97
- [x] H3 encoding-guard / runtime-autofix：PASS（27 文件 UTF-8 干净；AutoFix 链完整）
- [x] **H3 deep-ui-test FAIL → 新缺陷**：bundles 页 Accept/Reject All 死按钮（`bundle-accept`/`bundle-reject` 无主机处理器，bugfix #14 同类）
- [x] H4 bypass 扫描 13 命中 → 分类：真实缺陷 5 项 + by-design 命中
- [x] H5 在线观察：GLM-5.2 身份校验通过但 schema 越权（`protected_asset_note` 未知字段）整份无效；StepFun 502 漏产 → `degraded`（网关侧，非项目缺陷）

### 修复（bugfix.md #15，6 个 src 文件）
- [x] `MainView.pas`：`TBundleActionProc` 第三闭包 + `HandleWebMessage` 分发 `bundle-*`（解析 `bundle_id`）
- [x] `Providers.pas`：`RegisterAllProviders` 第三闭包 → `AController.ApplyBundleDecisions`
- [x] `Controller.pas`：抽 `ApplyAllTreeTransitions` 共用；新增 `ApplyBundleDecisions`（一条正式人类决策覆盖全部锚点节点 → 全树迁移 → RenderAll）
- [x] `Decisions.pas`：`ApplyNodeStatusTransitions` 两变体守卫修复——**dsRejected 决策现在生效**（Reject All / node-reject 语义修复）
- [x] `SpecStore.pas`：public static `AtomicWriteTextFile`（bugfix #5 逻辑提升共享）；`Decisions.Save` 与 `AppendPendingDecision` 改走原子写
- [x] `MainForm.pas`：AutoFix 'open-project' 硬编码 `D:\_Progs\02Business\DeepSpec` → `DEEPSPEC_AUTOFIX_PROJECT` 环境变量
- [x] 主程序 47514 lines 0 error；测试 97/97 无回归；SPW 重跑 `H3.deep-ui-test → PASS`、`H4.HARDCODED_ABS_PATH → 0 命中`

### 发布判定（审计后）
- [ ] **不可发布**：BUG-6b（DeepBase 不入库，换机无法编译）+ BUG-7（dpr 静默初始化失败/未签名/VerInfo 空，boundary.json 禁改 *.dpr，需用户会话）+ 完整 GUI 实跑验证待用户确认
- [x] 待修清单更新至 `tasks.md`；H4 剩余命中已分类为 by-design（HTML 审阅面/导出物/原子写 .tmp）

---

## 2026-08-06/07 第二批：i18n + CLI + 原子写崩溃 + Visualize（bugfix.md #17）

### i18n 集成（DeepBase 框架）
- [x] 新单元 `DeepSpec.Localization.pas`：`DeepSpecDetectLocale`（DetectSystemLocale 归一化 zh-CN/zh-TW/en-US）+ `DeepSpecApplyLocale`（21 键 × 2 中文表 + DeepShell 默认表注册、SetLocale 自动切换、Manager.CurrentLanguage 镜像）
- [x] 启动自动检测 Windows 语言并切换（RegisterServices 调 DeepSpecApplyLocale）；9 个命令 + LLM 设置对话框 + 状态消息全走 ShellText
- [x] 踩坑归档：.pas 内禁跨行字符串拼接/行尾中文注释（GBK 解码破坏 tokenizer）；#$ 转义后禁多余 `'`

### CLI 落地（Phase 5 B-P0）
- [x] `cli/DeepSpec.CLI.dpr` + `_build_cli.bat`：init / scan / generate / validate / render（复用 src/ 服务，无 GUI 依赖）；validate 错误 exit 1
- [x] 自测闭环：fresh 项目 init→scan→re-scan→validate→坏节点注入(exit 1)→重扫修复→generate→render 6 HTML
- [x] CI workflow 增加 CLI 构建步骤

### 原子写崩溃（CLI 自测抓到 bugfix #5 隐藏缺陷）
- [x] `TFile.Replace(..., '')` RTL 对备份名执行 `TPath.DoGetFullPath('')` → "Path is empty"；首次扫描走 Move 分支从未暴露，**重扫/覆盖必崩**
- [x] `AtomicWriteTextFile` 改 `Winapi.ReplaceFileW`（backup=nil）+ 失败回退 delete+move——GUI 重扫项目从此不再崩

### Visualize 修复
- [x] 按钮启用条件放宽（任何有效目录）；扫描后不再永久禁用；`FScanLogMemo` 实时写入扫描统计（原为死占位 "(scan log)"）

### 验证
- [x] 主程序 47893 lines 0 error；测试 97/97；SPW H1-H3 全 PASS（H1 门禁正则改最长前缀解析，修属性链误报）；H4 14 条 by-design
- [ ] **待用户**：GUI 实跑（Visualize 重扫 + 界面中文 + 看板/ticket/bundles）

---

## 2026-08-06 BUG-7 收尾（bugfix.md #16）

- [x] `DeepSpec.dpr:69-71`：`InitializeEx` 失败 `OutputDebugString` → `ShowMessage` 弹窗（含影响范围说明，仍继续运行）
- [x] `DeepSpec.dproj`：两处 `VerInfo_Keys` 补 `CompanyName=DeepKit` + `LegalCopyright=Copyright (c) 2026 DeepKit`；msbuild 重建 `DeepSpec.res`（IDE 版本资源随 dproj 更新）
- [x] 新建 `DeepSpec.ico`（16/32/48 三尺寸）——修复 `Icon_MainIcon` 引用缺失文件导致的 msbuild 构建失败（该文件从未入库，顺带修复 IDE 构建缺口）
- [x] 验证：msbuild 0 error；exe VerInfo 生效（DeepKit / ©2026）；图标提取 32x32 有效；97/97 测试无回归；SPW 重跑 H4 对 dpr:70 命中清除
- [ ] **剩余**：exe 数字签名需证书（signtool）；GUI 实跑验证；BUG-6b 仓库结构决策

---

## 2026-07-08 Fog 探索模型落地 + 编译修复 + 发布就绪度评估

### 质量加固（P0 续）
- [x] **BUG-4 测试假绿修复**（bugfix.md #4）：`FailsOnNoAsserts:=True`；7 零断言测试（`InvalidNodeStatus`/`InvalidConfidence`/`HumanDecidedBy`/`InvalidYAML`/`InvalidPrefix`/`DuplicateId`/`ExtensionKind`）补真断言；4 双分支 `Assert.Pass`（`MissingParentRef`/`CircularParent`/`InvalidGenStatus`/`InvalidReviewStatus`）改单分支 `Assert.IsTrue`；4 `ValidXxx_NoError` 加兜底 `Assert.IsFalse(R.HasErrors)`。关键核实：用当前源码重编诊断程序实测，YAML 解析器 block sequence 完全正常，"parser limitation" 注释是过时二进制误判。
- [x] **BUG-5 SpecStore 原子写 + 备份**（bugfix.md #5）：`WriteYamlFile` 改 `.tmp` + `TFile.Replace` 原子写；新增 `BackupTreeFileIfExisting` 在 `WriteTreeFile` 覆盖前滚动备份到 `snapshots/`；`CreateDirectoryStructure` 加 `snapshots` 目录。
- [x] **BUG-6a 构建脚本参数化**（bugfix.md #6a）：`_build.bat`/`tests/_build_tests.bat` 改 `BDS`/`DEEPBASE_HOME` 环境变量（带默认回退）+ `%~dp0` 可移植工作目录；测试脚本支持传工程名参数（诊断 dpr 可编译）。submodule/CI 留待用户决策。
- [x] **BUG-10 data-tree 链接条件输出**（bugfix.md #7）：`RenderIndex` 加 `AHasDataTree` 参数，Controller 三处按真实 DataNodes/LData 计数传入，消除非 Delphi 项目 404。
- [x] **BUG-12 Fog 命名一致性**（bugfix.md #8）：新增 `FogStateCssClass` 把下划线转连字符（保 `FogStateToStr` 的 YAML 值不变）；CSS 定义与 badge 生成点同步；`LFogTarget`→`AFogTarget`。
- [x] **BUG-13 清死代码**（bugfix.md #9）：删 `Decisions` 未读 `LChanged` + 空 `Settings.SaveToStore`；`Context.EstimateTokens` 经审查保留并加注释。

### 编译修复（预存 bug）
- [x] `LLMConfig.pas` uses 加 `DeepBase.LLM.Types` — 修复 `lpOpenAI` 未声明（bugfix.md #1）
- [x] `git checkout -- DeepSpec.res` 恢复被删资源文件（bugfix.md #2）

### Fog 探索模型（本次新增）
- [x] `Models.pas`：`TFogState` 枚举（clear/misty/foggy/unknown_unknowns）+ `CanTransitionFog` 单向收敛状态机 + `FogStateToStr`/`FogStateFromStr`；`TSpecNode` 加 `FogState`/`HasFogState` 字段；`TIssueType` 加 `itFogUnknown`
- [x] `Validation.pas`：`ValidateFogState` 规则（非法 `fog_state` 值报 `invalid_fog_state` error），在 `ValidateTreeFile` 调用
- [x] `Render.pas`：fog 徽章（非 clear 时渲染）+ Fog Map 分区（problems.html，遍历 unknown_unknowns/foggy/misty）+ `ScanNodes` fog 探测 + `EmitFogNodes` 局部过程
- [x] **数据流补完**（bugfix.md #3）：`SpecStore.ReadTreeFile` 加读 `fog_state`；`Yaml.Writer.WriteNode` 加写 `fog_state`（round-trip）；`TreeBuilder` 给 function 根节点默认标 `fsUnknownUnknowns`（首次扫描即有雾区可见）

### 测试加固
- [x] 新增 `Test.DeepSpec.Models.pas`：13 个测试覆盖 `CanTransitionFog`（单向收敛合法、逆向非法、clear 终态、same-state no-op、跨级收敛）+ `FogState` round-trip
- [x] DUnitX 测试 63/63 通过（50 原有 + 13 新增）
- [x] 主程序编译干净（0 error / 0 fatal）

### 发布就绪度评估（3 专家并行）
- 综合分 **3.3/10**，结论：当前为 0.1.0 原型，**不可对外发布**
- 已识别 10 项待修缺陷 → 见 `bugfix.md` BUG-4 至 BUG-13
- 已修缺陷 3 项 → 见 `bugfix.md` #1 #2 #3

### BUG-8 闭环：GenerateB 回写地图（bugfix.md #10）
- [x] SpecStore 抽 `ParseTreeNodes` 公共核心（修掉原内联空表泄漏 bug），供 LLM 输出沙盒复用
- [x] 新建 `DeepSpec.Services.CandidateIngest` 强类型沙盒：`SplitDocuments`（多文档流切分）→ `Ingest`+`ValidateNode`（id 前缀 / parent_id 外键 / 禁冒充 human_decision / 禁自确认 confirmed / 强制 unreviewed）→ `MergeInto`（覆盖语义字段、**保留人审 review_status/decision_refs**、gen_status 推进、function 根 summary 实变退雾一步���
- [x] `Controller.GenerateB` 接闭环：写盘后 Ingest→Merge→WriteTreeFile(三树)→RenderAll，try/except 兜底，TaskFinish 带 ingested/merged/fog-cleared/rejected 计数
- [x] `Prompts` 输出契约改多文档：§6/§7/§8 指示单响应 YAML 多文档流（`---` 分隔 + `# file:` 路由），约束与沙盒校验一一对应
- [x] 新增 `Test.DeepSpec.CandidateIngest.pas` 18 例单测；踩坑 `ValidateNode` 值参数 vs 引用参数（`Inc(AResult.Rejected)` 不回传，改 `var` 修复，单测第一时间捕获）
- [x] DUnitX 测试 **81/81**（63 + 18）；主程序 45939 lines 编译干净
- 范围边界：仅 function/module/view 三树合入；data/evidence/issues 留 TODO；fog 只收敛一步（unknown_unknowns → foggy）

---

## 2026-05-24 Phase 2~4 完成 (working tree)

### Phase 2: 正交状态 + 单元测试

#### C-P0：节点正交状态维度
- [x] TSpecNode 增加 `GenStatus: TGenStatus`（draft / generated / confirmed / skipped）
- [x] TSpecNode 增加 `ReviewStatus: TReviewStatus`（unreviewed / accepted / rejected / deferred）
- [x] `TSpecEnums` 增加序列化/反序列化方法
- [x] 旧 `Status: TNodeStatus` 映射逻辑：gen_status + review_status 组合兼容旧 status
- [x] YAML Writer 输出新字段（gen_status, review_status），旧 status 保留用于向后兼容
- [x] YAML Parser 读取新字段，回填旧 status
- [x] SpecStore.ReadTreeFile 向后兼容映射（旧 YAML 缺 gen_status/review_status 时从 status 派生）
- [x] Render HTML 展示双状态徽章（gen: / rev:）

#### A-P0：YAML Parser 单元测试
- [x] 创建 `tests/Test.DeepSpec.Yaml.Parser.pas`（DUnitX）
- [x] 测试用例：解析空树 / 单节点 / 嵌套子节点 / data-tree 专属字段 / 旧格式兼容
- [x] 边界：非法 YAML / 缺失字段 / 未知字段忽略
- [x] 编译并通过测试（41/41 pass）

#### A-P0：Validation 单元测试
- [x] 创建 `tests/Test.DeepSpec.Validation.pas`（DUnitX）
- [x] INV-1: ID 格式校验（前缀匹配树类型）
- [x] INV-3: Kind 受控词表校验（x_ 扩展）
- [x] 编译并通过测试（41/41 pass）

### Phase 3: 认知干预

#### D-P0：问题优先呈现
- [x] Render 新增 `RenderProblemsPage`：扫描所有树的问题列表
- [x] 问题类型：低置信度 / 无证据 / 未审阅 / 不确定 / 孤立节点
- [x] 跨树一致性检测：断裂的 cross-tree 引用（broken ref）
- [x] index.html 导航增加 "Problems" 链接
- [x] 连接到 RenderAll / RunScan / RefreshFromYaml

#### D-P0：信任信号体系
- [x] 节点卡片信任信号折叠展示（`<details>` 默认收起）
- [x] 信号内容：证据源 (source_refs) / 跨树引用 (related_*) / 决策历史 (decision_refs)
- [x] 各信号类型颜色区分 CSS

### Phase 4: 上下文管线 + 语义束 + 状态机

#### A-P1：上下文组装管线
- [x] `IContextSource` 可插拔接口 + `TContextChunk` 记录
- [x] `TContextAssembler`：优先级排序 + token 预算动态裁剪
- [x] 内置源：`TTreeContextSource` / `TDecisionContextSource` / `TStringContextSource`
- [x] 新单元 `DeepSpec.Services.Context.pas`

#### C-P1：语义束
- [x] Models 增加 `TSemanticBundle` 记录
- [x] SpecStore 增加 `WriteBundlesFile` / `ReadBundlesFile` 读写 bundles.yaml
- [x] Render problems 页面跨树引用断裂检测

#### C-P1：决策写回状态机
- [x] `TSpecEnums.CanTransitionGen` / `CanTransitionReview` 状态迁移合法性校验
- [x] `TSpecEnums.TryTransitionGen` / `TryTransitionReview` 原子迁移 + 错误提示
- [x] GenStatus 状态机：draft→generated→confirmed, draft/generated→skipped（confirmed/skipped 终态）
- [x] ReviewStatus 状态机：unreviewed→accepted/rejected/deferred, deferred→accepted/rejected（accepted/rejected 终态）
- [x] `ApplyNodeStatusTransitions`：accepted 决策自动传播到树 YAML 节点
- [x] Controller `PromotePendingDecisions` 集成自动状态迁移

---

## 2026-05-24 遗留 Validation + 语义束 UI (working tree)

### A-P0：Validation 剩余用例
- [x] INV-2: parent_id 引用存在性（invalid_parent_ref 规则 + 单元测试）
- [x] INV-4: gen_status / review_status 值合法性（invalid_gen_status / invalid_review_status 规则 + 单元测试）
- [x] INV-5: 循环依赖检测（circular_parent 规则 — 遍历 parent 链检测环 + 单元测试）
- [x] INV-6: content_hash 一致性（ValidateNodeHashes 方法，对 TSpecNode 列表校验）
- 关联公理：A2, A7

### C-P1：语义束审阅 UI
- [x] RenderBundlesPage 方法：读取 bundles → 展示各束 + 成员节点列表 + 状态/置信度徽章
- [x] Accept All / Reject All 按钮（data-action="bundle-accept/reject" + JS Bridge postMessage）
- [x] index.html 导航增加 "Bundles" 链接
- [x] Controller 三个渲染入口（OpenAndScan / RefreshFromYaml / RunScan）均接入 bundles 渲染
- 关联公理：A1

---

## 2026-05-20 Data-Tree 全链路实现 (commit `2a799fe`)

### DT-1：TreeBuilder 生成 data-tree 节点
- [x] TreeBuilder 增加 `FDataNodes: TList<TSpecNode>`
- [x] 新增 `BuildDataTreeFromDelphi` 方法：从 .pas 文件 published 段提取字段声明
- [x] 为每个 class 生成 entity 节点 + field 子节点（含 data_type）
- [x] 去重：`LEntitySlugs` 防止同名类重复
- [x] 暴露 `property DataNodes`
- [x] 编译通过：dcc64 零错误

### DT-2：Controller 集成 data-tree
- [x] `RenderAll` 增加 data-tree 渲染（有节点时）
- [x] `RefreshFromYaml` 读取 `data-tree.yaml` 并渲染
- [x] `RunScan` 写入 `data-tree.yaml` 后渲染
- [x] 日志消息增加 data 节点计数

### DT-3：Render 渲染 data-tree HTML
- [x] `index.html` 导航增加 "Data Tree" 链接
- [x] RenderNode 展示 data-tree 专属字段：data_type / risk_score / persistence 徽章
- [x] 新增 CSS 样式：badge-data-type / badge-risk-* / badge-persistence

### DT-4：Commands 注册 data-tree 命令
- [x] `deepspec.data.render` 命令注册

### DT-5：SpecStore 写入 data-tree
- [x] `WriteProjectSpec` 写入 `trees/data-tree.yaml`
- [x] `WriteEmptyTrees` 生成空 `data-tree.yaml`
- [x] `project-spec.yaml` 填充 `data_tree` 字段

---

## 2026-05-20 编译错误修复 (commit `2a799fe`)

### BUG-COMPILER-001：Models.pas 三处语法错误
- [x] `RiskLevelToStr` 缺 `class` 关键字
- [x] `DataKindFromStr` 缺 `=` 号（`'state'` 条件无法编译）
- [x] `RiskLevelToStr` 缺 `:` 冒号（`rlCritical` 分支）

### BUG-COMPILER-002：Writer.pas 四处语法错误
- [x] `WriteBoolKV` 使用了非法的 `if ... then` 表达式语法，改为 `IfThen()`
- [x] `WriteQuotedKVtarget_entity` 缺少左引号和左括号
- [x] `A.Cardinality` 应为 `ANode.Cardinality`
- [x] uses 缺少 `System.StrUtils`（`IfThen` 所在单元）

---

## 2026-05-20 文档与协议校正 (commit `5b7a2e6`)

- [x] 在 `D:\_Progs\02Business\DeepSpec` 初始化独立 Git 仓库
- [x] 新增根目录 `README.md` 和 `SPEC.md`
- [x] 新增 `docs/CTF.md`
- [x] 修复 `protocol/schemas/*.json` JSON 语法错误
- [x] 明确 v1.2-draft 四投影：function/module/view/data
- [x] 明确 `data-tree` 是第四树，`risk_score` 是字段
- [x] 明确 `execution_status` 不属于 CTF/DeepSpec
- [x] 明确新协议优先 `gen_status + review_status`，旧 `status` 兼容

---

## 2026-05-19 P0-P5 基线完成 (commit `1dc6451`)

### P0：DeepShell 壳接入
- [x] DeepSpec.dpr + MainForm 注册到 DeepShell
- [x] 命令面板注册所有命令

### P1：项目扫描和 .deepspec 落地
- [x] ScanService 扫描项目目录，分类文件（code/ui/config/doc/data）
- [x] ProjectService 管理 .deepspec/ 目录结构

### P2：三棵树 + 数据模型 + LLM
- [x] Models 定义 TSpecNode / TSpecEvidence / TSpecDecision
- [x] TreeBuilder 从扫描结果构建 function/module/view 树
- [x] SpecStore YAML 读写
- [x] LLM 服务集成（ModelScope/Qwen）

### P3：HTML 决策写回 + 提示词导出
- [x] RenderService 生成树形 HTML
- [x] JS Bridge：Confirm/Reject 按钮通过 WebView2 postMessage 写回
- [x] PromptsService 导出 context-pack / system-prompt

### P4：Delphi/VCL 增强
- [x] DFM Parser 提取表单控件结构
- [x] PAS Parser 提取类/接口声明
- [x] Delphi 增强：module tree 补充 unit/class 层级，view tree 补充 DFM 控件

### P5：质量加固 + JS Bridge
- [x] 决策服务：PromotePendingDecisions
- [x] Validation 框架
- [x] Hash 内容/关系哈希
- [x] 协议文件：schemas + invariants + state-machine + controlled-vocab

---

## 2026-07-08 三合一主线启动：雾→ticket→看板 (commits 进行中)

> 依据 wayfinder 文章对照分析（`docs/wayfinder-对DeepSpec的启发.md`）：DeepSpec 已内建 fog 四态 + 四类探索 ticket 的全部原语，但只建了数据模型、没建工作流。本日启动"一次解一个 ticket"主循环的三合一主线（BUG-11 + BUG-9 + 端到端），计划全文见 `plans/starry-baking-planet.md`。
> BUG-8 主循环闭环已归档于上方 2026-07-08 章节（bugfix #10）。

### BUG-11 第 1 步 数据层（bugfix #11，归档）
- [x] `Models.TSpecIssue` 加 `RequiresHuman` + `HasRequiresHuman`（HITL/AFK，沿用可选字段模式）
- [x] `TSpecEnums` 补 `IssueTypeFromStr`（14 值含 4 类 ticket）/ `IssueSeverityFromStr` / `IssueStatusFromStr`
- [x] `Yaml.Writer.WriteIssue` 补 `requires_human`（仅 `HasRequiresHuman` 时写）
- [x] `SpecStore` 加 `WriteIssuesFile` / `ReadIssuesFile`（照 Bundles 模板，复用 ParseTreeNodes 同款 StringList/ReadSourceRefs 内嵌函数）
- [x] 主程序 46121 lines 编译干净（0 error）

### BUG-11 第 1 步剩余 校验层（bugfix #12，归档）
- [x] `Validation.ValidateIssue` / `ValidateIssuesFile`（id 前缀 / 枚举合法性 / 非空 affected_nodes / requires_human 与 ticket 一致性，照 ValidateTreeFile 模板）
- [x] `Test.DeepSpec.Validation` 加 `TValidationIssuesTests` 8 例（合法无错 / 空 id / 非 issue- 前缀 / 非法 severity/type / 空 affected_nodes / research_ticket+requires_human 无错 / 非 ticket+requires_human 仅 warning）
- [x] 测试 89/89（原 81 + 新 8）；主程序 46272 lines 编译干净（0 error）

### BUG-11 第 2 步 ticket 创建双入口（bugfix #13，归档）
- [x] `RenderProblemsPage` +AIssues 参数 + Fog Map 节点旁 `ticket-create` 按钮（`.btn-ticket` CSS）+ Open Tickets 区（复用 `.ticket` CSS，只显示 open+四类探索 ticket）+ JS Bridge 事件转发（与 tree 页同形，ticket 按钮点击后不灰化以允许多开）
- [x] `MainView.HandleWebMessage` +`ticket-create` 分支（解析 `data-node-id`/`data-node-title`，转调注入的 `ATicketFactory` 闭包）
- [x] `Providers.RegisterAllProviders` +AController 参数；构造闭包 `procedure(ANodeId, ANodeTitle) → AController.CreateTicket`；`MainForm` 调用点传 `FController`
- [x] `Controller.CreateTicket`：定位节点 → `DefogOneStep` 退雾一步 → 组装 `TSpecIssue`（research_ticket / open / AFK / affected_nodes=该节点）→ `TYamlWriter.WriteIssuesFile` + `ValidateIssuesFile` 落盘前校验（有错则 LogError 不写）→ 持久化 issues.yaml + tree → `RenderAll` 重渲染（含 problems 页 Open Tickets）
- [x] `Controller.LoadIssuesForRender`：读 issues/doc-issues.yaml → `RenderAll` 把 issues 传给 `RenderProblemsPage`
- [x] 修复途中暴露的 3 处编译错误（见 bugfix #13）：`RenderProblemsPage` 实现签名漏 `AIssues` 参数、Delphi 无 `?:` 三元运算符（改 if/else）、`Controller` interface-uses 漏 `DeepSpec.Models`（`TSpecIssue`）、`LMsg.TrimEnd`→`TrimRight(LMsg)`
- [x] 测试 93/93（+4 DefogOneStep + 新增 issues 渲染相关）；主程序 0 error 编译干净

### BUG-11 第 3 步 / BUG-9 健康度看板（bugfix #14 + Task 1~3，归档）
- [x] `THealthMetrics` record（TotalNodes/ConfirmedNodes/CoveragePct/AvgConfidence/DecisionBacklog/FogCount/HighRiskOpen）
- [x] `TDeepSpecRenderService.ComputeHealthMetrics`（静态，4 树 + issues 聚合）+ `CountCrossTreeConflicts`（跨树断引用扫描）
- [x] `RenderIndex` 重构 — 4 张健康度卡片（覆盖率/平均置信度/决策积压/雾区数，各自带说明小字）+ 优化 Prompt 入口（`export-optimization-prompt` 按钮 + 旁路工具原则说明文案）+ 原有 Pages 列表保留
- [x] `TExportOptPromptProc` 回调类型；`TDeepSpecMainViewProvider` +`FOnExportOptPrompt` 字段 + 构造注入；`HandleWebMessage` +`export-optimization-prompt` 分支转调闭包
- [x] `Providers.RegisterAllProviders` 构造第二闭包 `procedure → AController.ExportOptimizationPrompt`
- [x] `Controller.ExportOptimizationPrompt`：复用 `LoadIssuesForRender` + `ComputeHealthMetrics` + `CountCrossTreeConflicts` → 组装 Markdown Prompt（快照 + 按积压/雾区/高风险/断引用/覆盖率条件触发优化目标 + 旁路要求）→ 写 `prompts/optimization-prompt.md`（UTF-8）→ 状态栏回报
- [x] **修复 bugfix #14**（端到端验证暴露）：`RenderIndex` 用 `PageFooter` 收尾但后者无 `<script>`，导致导出按钮在 index 页无 JS Bridge → 在 PageFooter 前加专用 bridge 脚本（仅匹配 export-optimization-prompt，成功改文案"✓ Prompt 已导出"，无桥 alert 兜底）
- [x] 测试 97/97（+4 渲染/健康度相关）；主程序 46992 lines 编译干净（0 error）

### 端到端验证（静态，归档）
- [x] 因 GUI/WebView2 无法在 AI 会话内 headless 实跑，改为静态验证：编译 0 error + 测试 97/97 + 逐文件审查 `RenderIndex` 输出 HTML（4 卡片 + 导出按钮 + 专用 JS Bridge 脚本就绪）。过程中发现并修复 bugfix #14。
- [ ] **遗留**：完整 runtime 验证（实跑扫描确认 Fog Map 非空 + 开 ticket 验证退雾落盘 + 看板数字变化）仍待用户在 GUI 中实跑确认（见 tasks.md「无法在 AI 会话独立完成的剩余工作」）。
