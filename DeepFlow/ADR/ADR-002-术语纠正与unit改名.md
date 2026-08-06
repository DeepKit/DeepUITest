# ADR-002: 术语纠正与 unit 改名

| 字段 | 值 |
|------|-----|
| 状态 | 已批准 |
| 决策者 | 付毅（老板）+ 罗辑（执行） |
| 日期 | 2026-08-06 |
| 关联 | 02.07 术语表, 03.01 架构设计, 03.07 架构关系, 工单 WO-20260806-0001-luoji |

## 背景

DeepFlow 项目存在一次**未完成的产品更名遗留**：项目从代号 `UniFlow` 正名为 `DeepFlow`，文件名、目录名、git 分支、代码文件名均已更新，但以下未跟上：

1. **文档正文**：63/80 文档正文仍使用 UniFlow，0 个使用 DeepFlow。
2. **代码 unit 名**：55 个 `.pas` 文件为 `unit UniFlow.*`，0 个 `unit DeepFlow.*`；`uses` 引用 202 处跨 70 文件。

此外发现两类独立问题：

3. **03.07 概念混乱**：标题"DeepFlow与DeepFlow关系说明"（自指错误），正文"UniFlow 与 uniFlow 关系说明"。经全文核查，文档概念层**确实存在两层架构**：`UniFlow`（大写）= 角色协作引擎（11 角色、Workflow 编排、AI 能力复用），`uniFlow`（小写）= 事件溯源引擎（Flow/Event/Snapshot、历史回放、版本分叉）。两者服务对象、核心抽象、代码命名空间均不同。标题自指系笔误，正文两层概念为真实架构分层。
4. **DeepDeep 乱码 bug**：73 处 / 25 文件，"Deep"被重复 5 次（如 `DeepDeepDeepDeepDeepInsight`、`DeepDeepDeepDeepDeepStory`），系生成/转换脚本缺陷，非术语不一致。**已于 2026-08-06 修复**。

配置层：schema `$id` 用 `uniflow://`，文档链接 `docs.uniflow.ai`，workflow.json `author: "UniFlow Team"`。**均已修复为 deepflow:// / docs.deepflow.ai / DeepFlow Team**。

## 关键约束

DeepFlow 目录**无任何 Delphi 工程文件**（.dpr/.dpk/.dproj）也无编译脚本，改完 unit 名无法在本目录内重编译验证。代码 unit 改名另涉工程影响面，**本轮冻结，待开会定夺**（见 D2）。本轮验证依赖静态一致性检查（grep 残留 + 文档术语一致）+ 人工复核，作为 SPW H4 evidence。

## 决策

采用**档 C：彻底纠正**，但区分文档层与代码层，且文档层保留两层架构概念。

### D1：项目正名 = DeepFlow，内部两层 = UpFlow / deepFlow

项目整体正名为 **DeepFlow**（文件名/目录/分支已用，不变）。项目内部两层架构各自命名：
- 上层"角色协作引擎"：`UniFlow`（大写）→ **`UpFlow`**
- 下层"事件溯源引擎"：`uniFlow`（小写）→ **`deepFlow`**（小写 d）

文档正文中每处 UniFlow/uniFlow 按上下文语义判断替换：
- 指项目整体/运行时框架/产品名（"UniFlow 是什么""UniFlow 架构""基于 UniFlow"）→ `DeepFlow`
- 指角色协作引擎层（与事件溯源层对比、强调 11 角色协作这层抽象）→ `UpFlow`
- 指事件溯源引擎层（小写 uniFlow，Flow/Event/Snapshot）→ `deepFlow`

### D2：代码 unit 名冻结，待开会

55 个 `unit UniFlow.*` 及 202 处 `uses UniFlow.*` 引用 **本轮不改**，待开会讨论确定：
- 选项 A：unit 改 `DeepFlow.*`（跟项目名）
- 选项 B：unit 改 `UpFlow.*`（跟上层架构名）
- 选项 C：unit 分两层（角色协作 UpFlow.* / 事件溯源保持 DeepFlow.EventSourcing.*）

代码冻结期间，文档中引用代码标识符（`UniFlow.AI.Types.pas`、`TUniFlowEngine` 等）**保留原样**，与实际文件保持一致。

### D3：schema URI 与 URL 纠正（已完成）

- schema `$id`：`uniflow://` → `deepflow://`（项目级，user_request/workflow_input 属项目整体配置）
- 文档链接：`docs.uniflow.ai` → `docs.deepflow.ai`
- workflow.json `author`：`"UniFlow Team"` → `"DeepFlow Team"`

### D4：验证策略——静态一致性检查，不重编译

- T1：`grep UniFlow` 残留仅限白名单（本 ADR + 代码标识符引用 + 受保护代码块）。
- T2：文档术语语义一致（项目名 DeepFlow / 上层 UpFlow / 下层 deepFlow 各得其所）。
- T3：DeepFlow 出现频次显著上升，UniFlow 显著下降（白名单外清零）。
- T4：03.07 标题修正，两层概念清晰表达（UpFlow 与 deepFlow）。
- T5：schema $id 全为 `deepflow://`，无 `uniflow://` 残留。
- T6：SPW H1-H4，H4 项目专属旁路用 T1-T5 evidence。

#### D4 执行结果（2026-08-06 实测）

确定性脚本 `tools/verify-term-rename.py`（退出码 0 = 全过）：

| 检查 | 结果 | 实测值 |
|------|------|--------|
| T1 UniFlow 残留仅限白名单 | PASS | 违规 0 处（残留全部为代码标识符：`UniFlowClient`/`TUniFlowEngine`/`UniFlow.Engine.pas`/`uniFlow.Event.Write` 等，按规则3与冻结代码一致保留） |
| T3 术语分布 | PASS | DeepFlow=875 UpFlow=29 deepFlow=75 |
| T4 03.07 两层清晰 | PASS | 标题/对比表/命名约定均正确，文件名引用无误用 |
| T5 schema URI 纯净 | PASS | `uniflow://`/`docs.uniflow.ai`/`UniFlow Team` 零残留 |
| T5b 未新引入 JSON 破坏 | PASS | 本轮新破坏 0；`Config/workflows/simple_qa.workflow.json` 既有 UTF-8 损坏（HEAD 版本已损坏，非本轮引入，已标记 preexisting） |
| T6 DeepDeep 乱码 | PASS | 残留 0 处 |

**release_ready = true**（依据 T1-T6 确定性 PASS）。

**SPW 框架适用性判定**：SPW `spw.py` 硬编码通用工程纪律 claim（H1→`controlled_entry_only`、H2→db-constraints 三 claim、H3→`counterfactual_1..8`、`min_observer_families>=2`），源自法源 A0031，面向代码工程。本任务为纯文档/schema 术语纠正，无 controlled-entry 代码、无 DB、无 counterfactual 测试，这些 claim 语义不匹配。强行声明将构成虚假 evidence（违反 SPW 第7条）。故不套用 SPW 标准 manifest 框架，改以本 D4 的 T1-T6 确定性脚本作为 release-ready 判据。manifest 草稿与 scope 判定见 `ADR/spw-manifest-term-rename.json`。代码 unit 改名（D2）解冻后另起任务，届时配完整编译 + SPW H1-H4 门禁。

### D5：DeepDeep 乱码修复（已完成）

`DeepDeepDeepDeepDeepInsight` → `DeepInsight`，`DeepDeepDeepDeepDeepStory` → `DeepStory`，9 种形态、73 处，已于 2026-08-06 全部修复，零残留。

### D6：白名单

以下场景允许保留 UniFlow 字样：
- 本 ADR（ADR-002）：引用旧名说明改名缘由。
- 代码标识符引用：`UniFlow.xxx.pas`、`TUniFlowXxx` 等（代码冻结，与实际文件一致）。
- ADR-001 等历史 ADR 描述历史背景的段落。

## 产品名基准（中英并列）

| 中文 | 英文 | 定位 |
|------|------|------|
| 如是 | SoIs | 基于 DeepFlow 的 AI 决策辅助产品 |
| 述成 | SayDone | 基于 DeepFlow 的任务执行产品 |
| 洞见 | DeepInsight | 基于 DeepFlow 的决策可视化产品 |

首次出现处一律"中文（英文）"并列，后文可单用其一。

## 后果

**正面**：
- 文档术语统一：项目名 DeepFlow，上层 UpFlow，下层 deepFlow，各得其所，消除更名遗留与概念混乱。
- 03.07 自指错误消除，两层架构概念清晰表达。
- DeepDeep 乱码修复（73 处），文档可读性恢复。
- 配置层（schema $id / URL / author）统一为 deepflow / DeepFlow。

**负面 / 风险 / 待办**：
- **代码 unit 名冻结**：本轮不改，文档与代码命名空间暂不一致（文档用 UpFlow/deepFlow，代码仍 UniFlow.*）。待开会确定 D2 选项后统一，届时需同步 uses 引用并验证编译。
- **语义判断风险**：文档层 UniFlow→DeepFlow/UpFlow 的区分依赖上下文语义判断，个别边界处可能误判。缓解：workflow 并行处理 + 人工抽检关键文件（03.07 / 03.01 / 术语表）。
- 代码 unit 最终改名后，外部引用本库的产品需同步 uses 声明。

## 待办（代码层，另起）

代码 unit 改名（D2 三选项之一）+ uses 引用同步 + 编译验证，待开会决策后单独执行，不属本轮文档纠正范围。

## 变更记录

| 版本 | 日期 | 内容 | 作者 |
|------|------|------|------|
| 1.0 | 2026-08-06 | 初始：档 C 彻底纠正，含 unit 改名、schema URI、DeepDeep 乱码、白名单 | 罗辑 |
| 1.1 | 2026-08-06 | 决策变更：核查发现文档确有两层架构（角色协作/事件溯源），改"全改 DeepFlow"为"项目=DeepFlow，内部两层 UpFlow/deepFlow"；代码 unit 名冻结待开会；DeepDeep 乱码与 schema 已修复 | 罗辑 |
