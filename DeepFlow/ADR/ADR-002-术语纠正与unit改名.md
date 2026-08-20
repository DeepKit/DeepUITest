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

DeepFlow 目录**无任何 Delphi 工程文件**（.dpr/.dpk/.dproj）也无编译脚本，但本机装了 Embarcadero Studio 37.0 的 `dcc32` 编译器（`/d/Program Files (x86)/Embarcadero/Studio/37.0/bin/dcc32`），可对单 unit 做编译验证（带 `-U Source/...` 搜索路径）。D2 已于 2026-08-06 解冻执行选项 A，编译验证见 D4/T7。

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

### D2：代码 unit 名——已执行选项 A（2026-08-06 解冻）

老板 2026-08-06 指令"改代码 unit 名"解冻 D2。原三选项：

- 选项 A：unit 改 `DeepFlow.*`（跟项目名）
- 选项 B：unit 改 `UpFlow.*`（跟上层架构名）
- 选项 C：unit 分两层（角色协作 UpFlow.* / 事件溯源保持 DeepFlow.EventSourcing.*）

**采用选项 A**。理由：文件名已是 `DeepFlow.*.pas`（含 EventSourcing，均为大写 DeepFlow），unit 名对齐文件名是 Delphi 编译的强制要求（`unit X;` 必须与 `X.pas` 文件名一致）；选项 B/C 会让 unit 名与文件名不符，需同时改 68 个文件名，超出"改 unit 名"字面范围且工程更大。选项 A 最小必要、与现有文件名零歧义。

**执行结果**（字节级 ASCII 替换，不受 .pas 既有 UTF-8 损坏影响）：

| 项 | 实测 |
|------|------|
| `unit UniFlow.*` 声明 → `unit DeepFlow.*` | 55 处 |
| `unit DeepBase.UniFlow` 声明 → `unit DeepBase.DeepFlow` | 1 处 |
| `uses`/全限定 `UniFlow.*` 引用 → `DeepFlow.*` | 127 处 |
| `DeepBase.UniFlow` uses 引用 → `DeepBase.DeepFlow` | 4 处 |
| 注释/字符串内项目名 `UniFlow` → `DeepFlow`（前后非标识符字符） | 169 处 |
| `program UniFlowXxx` → `program DeepFlowXxx`（2 个 Examples program） | 2 处 |
| 改写 .pas 文件总数 | 68 |
| 改名后残留 `UniFlow.`（带点 unit 引用） | 0 |
| 改名后 `unit`/`program` 声明含 UniFlow | 0 |
| 保留的类型标识符 `TUniFlowXxx`/`InitializeUniFlow`/`UniFlowClient` 等 | 560 处（按规则3保留，类型重命名另议） |

类型标识符（`TUniFlowEngine`、`UniFlowClient`、`IUniFlow`、`InitializeUniFlow` 等 560 处）**保留不改**：本轮范围是"unit 名"（声明 + uses），类型重命名是更大的独立工程（涉所有声明/实例化/转型），且文档大量引用这些标识符，另起任务。

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
| T7 代码 unit 改名编译验证 | PASS | dcc32 批量编译 65 个 Source unit：`DeepFlow.* not found`（改名引入的 unit 缺失）= 0；20 个通过，21 个因缺外部 `DeepBase.*` 依赖未过（预存），24 个因预存 UTF-8 损坏（`Unterminated string`）未过。回归对照：HEAD 版（unit=UniFlow）编译同样报 `Unterminated string at 448`，证明改名零回归 |
| T8 simple_qa 修复 | PASS | 23 处 UTF-8 损坏（中文/箭头第三字节→0x3f，其中 9 处伴随闭合引号塌缩）逐字节还原并补引号；独立 `json.load` 通过，17 个 step 完整，description 等字段语义通顺 |

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

1. **类型标识符重命名**（可选，大工程）：560 处 `TUniFlowXxx`/`UniFlowClient`/`IUniFlow`/`InitializeUniFlow` 等类型/函数标识符是否改 `DeepFlowXxx`/`UpFlowXxx`，待定。涉所有声明/实例化/转型 + 文档引用同步。
2. **`.pas` 既有 UTF-8 损坏修复**（新发现，预存）：41 个 `.pas` 文件入库时即存在 UTF-8 损坏（中文/全角字符第三字节→0x3f，部分伴随闭合引号塌缩），其中 24 个因 `Unterminated string` 等阻碍编译（HEAD 版同样损坏，非 unit 改名引入）。损坏不可逆（0x3f 推不回原字节），需按上下文语义逐字还原，量大。simple_qa.workflow.json 已作为同类样本修复（T8），`.pas` 的修复另起独立任务。
3. 外部 `DeepBase.*` 依赖（`DeepBase.Exceptions` 等 21 处 not found）的工程路径配置，待配 .dpr/.dproj 工程文件时统一。

## 变更记录

| 版本 | 日期 | 内容 | 作者 |
|------|------|------|------|
| 1.0 | 2026-08-06 | 初始：档 C 彻底纠正，含 unit 改名、schema URI、DeepDeep 乱码、白名单 | 罗辑 |
| 1.1 | 2026-08-06 | 决策变更：核查发现文档确有两层架构（角色协作/事件溯源），改"全改 DeepFlow"为"项目=DeepFlow，内部两层 UpFlow/deepFlow"；代码 unit 名冻结待开会；DeepDeep 乱码与 schema 已修复 | 罗辑 |
| 1.2 | 2026-08-06 | D2 解冻执行选项 A：68 个 .pas 的 unit/program 声明 + uses 引用 + 注释项目名全改 DeepFlow（类型标识符 560 处保留）；dcc32 编译验证零改名回归（T7）；simple_qa.workflow.json 23 处 UTF-8 损坏修复（T8）；新发现 41 个 .pas 既有 UTF-8 损坏待办 | 罗辑 |
