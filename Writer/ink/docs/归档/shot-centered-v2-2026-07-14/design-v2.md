# 墨韵 Ink v2 — 完全重构技术设计（Shot 中心历史基线）

> **状态**：设计稿 v2；2026-07-14 Scene-first 修正案已生效
> **定位**：**从 0 构建完整生产版**，不基于旧 `inkflow/` 改造。旧系统的 56 表/26 轮迁移/23679 行代码/557 测试**不是要保留或迁移的对象**，而是"可借鉴的领域知识库"——取其踩坑结晶与领域设计，弃其架构病土壤。
> **起因**：旧系统修了 94 个 bug 仍不能稳定生产。根因不是代码质量，是**传递链缺少结构化保证**——契约字段从 DB 到正文经多次隐式 dict 传递，任何一层漏字段都不报错（`forbidden_facts` 就这么丢的）。每加一个字段就多一个可能丢失的接缝，这是架构病，不是实现病。
> **本文件**：是 ink/ 新系统的权威设计。旧 `inkflow/docs/design.md` 仅作领域知识参考，不作继承来源。
>
> **强制修正**：以 [scene-first-authority-amendment.md](scene-first-authority-amendment.md) 为最高优先级。本文尚存的 shot 中心表名、状态机和流程用于描述 2026-07-14 前的当前实现或迁移来源；目标架构中 Scene 是最小正式生成、修改、评审、版本、回滚和封版单位，Shot 仅为 Scene 内部非权威工作切片。

---

## 0. 重构目标与边界

### 0.0 2026-07-14 Scene-first 权威修正

- 当前工程目录是 `ink/`，不是旧 `inkflow/`。
- 数据库保存正式稿；文件和导出物不得反向覆盖数据库。
- Scene 是正文最小权威原子；Chapter Candidate Branch 是文学选优单位；Chapter Snapshot 是封版与导出权威。
- 现有 `writing_shot_*` schema 不得被解释为目标架构已经完成；它是待迁移的当前实现。
- 新增或修改设计时不得继续扩大 shot 级正式封版、shot 级文学选优或逐 shot 拼优。
- 详细契约、候选、返工、样本和数据模型见 Scene-first 修正案。

### 0.1 目标
让"架构师契约分析正确 → 正文质量硬门禁达标 → 强制精修 → 人类审稿确认 → 正式导出/重构落库"成为**可由类型系统 + 代码生成 + DB 约束 + 审计链保证**的完整生产闭环，而非靠人记字段。

本系统没有 MVP 概念。里程碑只是实现顺序，不是功能裁剪边界。任何里程碑都不得用“后续补齐”作为理由删除完整生产能力的 schema、接口、审计或测试入口。

### 0.2 借鉴自旧系统的领域结晶（取其知识，不取其代码）
- **状态机枚举**（shot_status 10 态、契约 draft→confirmed→locked、信息差生命周期）
- **领域规则**（`is_current` 封版读取、`retry_budget` 熔断、`outline_has_incomplete_tail`、`shot_id={logical}@{run}` 隔离、accepted canonical 唯一索引）
- **三棵树 + 8 层层级 + 悬疑引擎设计**（作为领域模型参考）
- **角色体系**（架构师/叙事分析师/写手 persona/jury/人类 review 边界）
- **踩坑修复逻辑**（15 条结晶，见 pitfall-checklist.md）

### 0.3 从 0 构建的新架构（弃其架构病）
- DB schema **重新设计**：49 张生产表（非旧 56 张；40 张生产内核表 + 9 张 v1.1 主编台/源文档产品化表），保留领域必需 + 踩坑结晶 + 完整生产所需的 AI 调用审计、运行时事件、人工决策、导入账本、checkpoint 与测试可追踪性支撑
- 契约传递用**代码生成**（pydantic schema → dataclass + `unpack()` 访问器 + AST `ast.Attribute` 字段消费检查），非手写 dataclass
- 正文表**物理隔离**（`shot_revisions` 只 `core/text_repository` 可 import + DB VIEW + sqlparse CI lint 三重约束）
- 编排层 orchestrator **入口物理隔离**（签名只收 `(shot_id, run_id)`，禁止传上游 dataclass）
- persona = **强度调音器**（每篇都是完整稿，5 维都涉及，只强度配比不同）
- 产稿 = **同 persona + 同 prompt + 换写手模型**（多样性来自模型，非 persona 分工）
- 评审 = **2 道硬门槛 + 3 裁判全评 12 维 trimmed mean + 章级 7 维 + 篇级滚动检测**（方案 B：3 裁判都评全部 12 维，每维去极值，消除"每裁判只评 4 维无法 trim"的数学矛盾）
- 质量硬门禁 = **项目级质量标杆 + shot 级质量地板 + 裁判分歧阻断 + 盲评/继续阅读证明 + polish_revision 精修 + 章级/篇级 blocking issue 阻断**；质量失败不得用 soft/diagnostic 放行
- gate **hard/soft/diagnostic 三层分类 + soft gate 3 级状态机**（N 计数 DB 权威 + 无状态读 + 跨 run 累积）；质量类 gate 最高只能升级为 `QUALITY_BLOCKING`，不得 N=3 放行
- 崩溃恢复 **shot_status 14 态 → resume 行为映射矩阵**（done 类 skip / generating 类幂等重跑 / pre-drafting 类 superseded_at 幂等）
- AI 调用统一经 **LLMGateway**：所有 prompt/response/hash/token/error/failure streak/runtime event 落库，可恢复、可审计、可成本追踪
- 人工动作经 **human_decisions**：setup confirm、contract confirm、review accept/revise/reject、abort 都有 actor/reason/前置条件审计
- 主编台交互经 **DecisionSession 专表**：自然语言、AI 解析、回读、1-8/0/9 选项集、确认结果和断点续接全部持久化；未确认意见不进入 prompt 或 canonical
- 源文档先经 **SourceNormalizer** 合并、去重、拆矛盾、原子化；source coverage 采用原子条款 × contract field 矩阵，AI 抽取采用双模型交叉 + coverage gate；`better.md` 等过程文件只作抽取输入，处理后必须清空，只保留 processed manifest/hash 审计
- 已有稿重构经 **import ledger**：dry-run、source hash、低置信问题、人类裁决、finalize 原子落库

### 0.4 不做
- 不沿用旧 56 表 schema（重新设计 49 张生产表）
- 不沿用旧 cli.py 的编排逻辑（重写编排层）
- 不做双轨并行/迁移（从 0 构建，不管旧系统）
- 不讨论工期/时间计划（不在本文件及下游文档记录时间）
- 当前版本不做多用户/多租户/团队协作权限模型；产品形态先定位为单作者本地生产工具。

### 0.4a 参数化原则（运营参数 vs 架构不变量）

**原则**：凡是"改变后系统行为变化但正确性不变"的值，都应该是 `writing_projects` 表中的运营参数，运行时可调，不改代码。"改变后系统正确性也变了"的值（状态机转移矩阵、铁律、DB CHECK 绝对底线）保持硬编码。

**运营参数**（全部在 `writing_projects` 表，`init` 时设定，之后可 `UPDATE`）：
- 产稿参数：`draft_count`, `creative_shot_extra`, `writer_model_pool`, `jury_model_pool`, `jury_model_pool_min`, `min_eligible_outlines`, `min_eligible_candidates`, `redo_candidate_count`, `escalated_jury_count`
- 质量运营阈值（原 `quality_bar` JSON，已拆为 `writing_projects` 独立字段以支持 DB 层约束）：`shot_quality_floor`（默认 80）, `dimension_floor`（默认 65）, `chapter_quality_floor`（默认 75）, `book_quality_floor`（默认 75）, `judge_disagreement_max`（默认 25）, `reader_pull_floor`（默认 75）, `blind_review_min_passes`（默认 2）
- 熔断预算：`max_calls_per_shot`（默认 8）, `max_total_llm_calls`（默认 40）, `consecutive_failure_circuit_break`（默认 3）
- soft gate 升级阈值：`soft_gate_redo_n`（默认 2）, `soft_gate_fail_n`（默认 3）
- 自动重试（A'+A'' 机制）：`auto_retry_on_hard_failure`（默认 TRUE）, `max_retries_per_gate`（默认 2）, `retry_strategy`（默认 'change_model'）
- 大纲与容量：`outline_drift_threshold`（默认 0.20）, `capacity_floor_titled_shot`（默认 1200）, `capacity_floor_chapter_end`（默认 1500）
- 多样性与场景：`scene_fingerprint_min_diversity`（默认 3）, `suspense_shot_min_intensity`（默认 5）
- 归档与恢复：`prompt_archive_size_bytes`（默认 65536）, `checkpoint_max_retention`（默认 3）
- 篇级检测：`chapter_rolling_check_interval`（默认 5）

**架构不变量**（硬编码，不可参数化）：
- shot_status 合法转移矩阵（14 态穷举）
- `is_winner=1 → quality_gate_passed=1`（DB CHECK）
- `hard_quality_override=0`（DB CHECK）
- 信息差 6 态转移合法性（DB CHECK）
- `v_current_text` 每 shot 恰一行（DB VIEW）
- text_repository 三重隔离（代码 + CI lint）
- 字段消费 AST lint（CI lint）
- 基础裁判数 = 3、12 维评分、5 persona（设计常量）；分歧升级裁判数由 `writing_projects.escalated_jury_count` 参数化

**DB CHECK 绝对底线 vs 运营阈值**：
`jury_aggregates` 等表的 CHECK 约束（如 `final_score >= 80`）是**绝对底线**——任何项目的运营阈值不得低于此。运营阈值已拆为 `writing_projects` 表的独立字段（`shot_quality_floor`、`dimension_floor` 等），并在 `writing_projects` 表级 CHECK 约束中保证运营阈值不低于 DB 绝对底线。应用层直接读取 `writing_projects` 表的运营阈值执行。这样既允许项目提高标准，又防止项目误设过低阈值导致质量失控。

### 0.4b 自动重试机制（A'+A'' 机制，减少编辑工作量）

**设计目标**：尽量不让编辑在 hard quality failure 时介入。系统自动重试，直到预算耗尽才上报。

**机制**：
- 当 hard gate 或 quality floor 失败时，若 `auto_retry_on_hard_failure=TRUE`，系统自动重试。
- 每次重试按 `retry_strategy` 调整策略：
  - `change_model`：换不同写手模型重新产稿
  - `adjust_intensity`：调整 persona 5 维强度配比
  - `relax_soft`：放宽 soft_constraints（仅限 deviant 或重试后期）
- 每层 gate 最多重试 `max_retries_per_gate` 次。
- 重试预算受 `max_total_llm_calls` 约束，耗尽后转 `failed`。
- `failed` 状态才上报编辑，动作是项目级资源决策（换模型池 / 调阈值 / 放弃该 shot），不是审美判断。

**编辑工作量**：accept 路径上编辑零动作。reject 也是按钮级操作。只有 `failed` 才需要编辑介入——且频率应该是罕见事件。

### 0.4c 战略实现边界（2026-07-04 决策）

- **实现路线**：生产内核优先。M0/M1 必须先做实 schema、lint、状态机、LLMGateway、text_repository、resume 等防错机制；随后用 1 章质量证明校准，再扩展到 M2-M6 全流程。
- **数据库路线**：SQLite 先行，但 repository、DDL、事务和时间格式按未来 PostgreSQL 迁移预留；需要数据库层 RLS/advisory lock 时再迁移。
- **质量门禁策略**：M4-M6 验收期从严；稳定后低风险项可以参数化调节，但 hard gate、quality floor、human accept 不可覆盖硬失败这些架构不变量不得降级。

### 0.5 质量证明与系统边界

**质量证明门禁**：本系统没有 MVP，但有质量证明硬门禁。扩展生产能力之前，必须先用完整链路证明至少一个章节/关键片段达到 `StyleQualityProfile` 定义的目标水平：读起来像人写的、角色声音可辨、must_land 可追溯、盲评通过、`would_continue_reading` 达标、返工后质量确实提升。若当前模型、上下文或门禁无法达到该水平，不允许用更多自动化、并行或导出能力掩盖质量天花板。

**系统边界声明**：硬门禁只管可证明的质量风险，不替作者决定文学上限。系统有意不做：

- 不预测所有读者的私人联想。
- 不替作者解释终极意图；`intuition_notes` 只保留和注入，不被系统强行归纳成标准答案。
- 不把单一审美偏好伪装成客观规则。
- 不因句式、节奏、粗粝感“不规整”就自动判为质量失败。

**质量判定分层**：

| 层级 | 定义 | 典型项目 | 裁决权 |
|------|------|---------|--------|
| `ES` | 可机械或 DB 事实判定 | 禁词、字数、事实锚点、POV、已死角色出现 | 规则/DB 可直接硬阻断 |
| `SEMI_ES` | 有客观锚点但需语义判断 | must_land 覆盖、角色声音、hook 存在、信息泄露改写 | 模型判断 + 证据位置；低置信升级复核 |
| `NES` | 文学体验和审美判断 | 是否想继续读、情感是否打中、留白是否有效、原创性 | 聪明模型提供报告，人类/盲评校准；不得伪装成纯客观事实 |

**缺陷三分法**：

| 类别 | 定义 | 处理 |
|------|------|------|
| `destructive` | 破坏事实、契约、可读性或目标读者体验的缺陷 | 强制修复；可触发 `QUALITY_BLOCKING` |
| `productive` | 有意或高置信度有效的偏离、粗粝、留白、反常句式 | 保护；写入 `quality_report_json.productive_deviations`，`polish_revision` 不得磨平 |
| `neutral` | 效果不确定的偏离或低置信问题 | 进入人工 review，不自动判死，也不自动保护 |

**粗糙度保护**：`polish_revision` 的目标是消除毁灭性缺陷，不是把文本磨成平均、平滑、安全的 AI 腔。若局部精修导致角色声线、叙事棱角、有效留白或故意粗糙显著下降，必须回退到上一版或提交人类裁决。

---

## 1. 六条架构铁律

重构的全部技术决策都从这六条派生。前五条保证系统不绕过契约，第六条保证"通过"必须代表写作质量达标。

### 铁律 1：契约字段传递用代码生成的 dataclass 链 + 强制字段消费检查

**病根**：旧系统的 `shot_context_payload` 是 dict，`prompt_compiler.py:421` 只读 `pov_only/forbidden` 不读 `forbidden_facts`——加了字段不消费，不报错。这是 B28→B48→B67→B87→B92 五个 bug 反复复发的同一模式："契约信号逐层弱化丢失"。

**更深病根**：不是"用了 dict"，是"生产者和消费者之间没有契约"。dict/dataclass 都只是载体，载体换了，契约缺失的问题换形式存在。真正的病灶是**"消费者必须证明它消费了上游每个字段"的强制机制缺失**。

**铁律**：
```
MetaContract → ShotContract → OutlineSpec → TaskCard → PromptSpec → DraftSpec → JuryInput
```
- 传递链每个环节用 **pydantic schema 定义** → 代码生成 `@dataclass(frozen=True)`（字段必填，无默认值除非语义允许）
- **强制字段消费检查**（两道防线）：
  1. **生成器产出强类型访问器 API**：每个上游 dataclass 生成一个 `unpack()` 方法，返回所有字段的解构元组（如 `must_land, anti_write, scene = shot_contract.unpack()`）。消费端**必须**用 `unpack()` 或具名属性访问（`ast.Attribute` 节点），**禁止** `getattr(x, "field")` / `vars(x)` / `x.__dict__` / `dataclasses.asdict(x)` / `**spread` 等动态访问。
  2. **AST lint 校验显式消费**：动态访问禁令全代码库生效；“每个上游字段都必须被消费”的强检查只作用于契约边界函数（contract compiler、prompt compiler、gate input builder、jury input builder、shot 级 orchestrator 入口）或显式标注 `@requires_full_field_consumption` 的函数。普通 helper 不应直接接收 generated dataclass；需要部分字段时用收窄 DTO 或显式字段参数。边界函数未引用字段 = 编译失败。
- `pyright --strict` 全量启用，任何类型不匹配 = 编译不过
- **dataclass 是 DB 的只读投影，不是新的真相源**（见铁律 2）

**为什么是代码生成 + 访问器 API 而非手写**：手写 dataclass + pyright 只保证"字段存在"，不保证"字段被消费"。词法匹配（"字段名出现在源码中"）治标不治本——字段名出现在注释/f-string/log 文本里就通过，但逻辑上未读；动态访问（getattr/asdict）又会被误判。生成器产出 `unpack()` + AST 校验 `ast.Attribute` 节点，把"字段消费矩阵"从词法猜测变成可执行的结构化检查——这是治本。

### 铁律 2：DB 是唯一真相源，编排步骤入口物理隔离

**病根**：旧系统的 `outline_evaluator._update_contract` 只 UPDATE JSON blob 列，但 CLI 从结构化表读 beats 覆盖 blob——写 A 读 B，大纲再生无效循环。这是"传递层多个真相源互相覆盖"的病。

**铁律**：
- shot 级 orchestrator 的**入口签名只收 `(shot_id, run_id)`**，**物理上禁止传上游 dataclass**——这样跨步骤复用不可能发生
- chapter/book/import/export 等非 shot 级 orchestrator 可以收自己的业务 ID（如 `project_id, chapter_id, run_id`），但同样禁止传上游 dataclass，入口必须从 DB 重新加载所需投影
- **一个契约信号只存一处**：结构化表是真相源，JSON blob 仅作审计快照，永不被消费端读取
- **契约核心字段必须结构化**：`must_land`/`anti_write`/`scene_contract`/`persona_assignment`/`soft_constraints` 拆为 5 张独立表（见 §7.1），每字段独立列 + NOT NULL + CHECK，消费端从结构化列读，可建索引。旧系统已结构化过，新系统不倒退。
- **"写操作必须带完整上下文校验"的可执行定义**：任何写操作（落 draft、写 jury 分、封版 revision）的函数签名必须收 `(shot_id, run_id, ...)` + 从 DB reload 当前 shot 状态 + 校验状态机允许该写（如：drafting 状态才允许落 draft，jury_scoring 状态才允许写 score）。**不信任入参 dataclass 的"已处理"状态**——入参只携带待写内容，合法性由 DB 当前状态判定。lint 校验写操作函数体内含 `SELECT status FROM writing_shots WHERE shot_id=?` 调用。

**为什么是物理隔离而非约定**：铁律 2 靠开发者自律会退化（最自然的写法是传上游 dataclass）。shot 级入口签名只收 `(shot_id, run_id)` 是物理约束；非 shot 级入口只收业务 ID，不收 dataclass，同样避免跨步骤复用。

### 铁律 3：兜底必须显式 `degraded` 标记，不参与质量判定

**病根**：旧系统的 `writer_dispatcher.py:525-544` 单条 persona 失败时静默降级到 `LocalDefaultGenerator` 占位文本，dispatch 永远返回 4 份但可能含占位稿，jury 在评 <4 份真实稿却无告警。B14/B47/B48/B54/B55 反复出现。

**铁律**：
- local-default 生成、LLM timeout、JSON 解析失败 → draft 标 `degraded=True` + `failure_category`
- **`degraded=True` 的 draft 不进 jury 候选池**，不参与 trimmed mean
- jury 候选不足 2 份 → 触发补写，不静默放行
- 所有降级必须写 `writing_failure_attributions` 审计事件

### 铁律 4：gate 三层分类 hard / soft / diagnostic，soft gate 有 3 级状态机

**病根**：旧系统的 `architect_gate.py:1018` 调用 `_check_chapter_end_hook` 但结果不追加到 `issues`——隐性软警告，章末 hook 质量差不拦。B79/B80/B89/B90/B92/B94 反复出现"该拦的不拦、不该拦的误杀"。

**铁律**：每条 gate 规则**必须显式归入一类**，代码里用 `GateClass` 枚举标注：

| 类别 | 行为 | 适用维度 |
|------|------|---------|
| `HARD` | 不过 = 停止，ClickException，不 finalize/封版 | 事实锚点、契约合规、禁区、容量下限、POV、场景契约 |
| `SOFT` | 阻断封板，但**有 3 级状态机**（见下），不直接 redo；仅限可由后续上下文补偿且不影响当前正文质量的项 | 非质量阻断的轻微 exposition_drift |
| `QUALITY_BLOCKING` | 不过 = 不能 soft seal / hard seal / accept；N=2 后仍失败则新建 revise，不得降级放行 | 章末 hook、节奏曲线、母题密度、信息差生命周期、语言质感、人物可信、结构落地 |
| `DIAGNOSTIC` | 告警不阻断，记审计 | intent_drift、成本异常、非质量观察项 |

**soft gate 3 级状态机**（治"soft gate 死循环"）：

同一 shot 的同一 soft gate 连续失败次数 N：
- **N=1**：阻断封板，标记问题，不 redo
- **N=soft_gate_redo_n（默认 2）**：仍失败 → 触发**该 shot 局部重写**（换模型产 >= `redo_candidate_count`（默认 2）篇新候选，重新走硬门槛+评分+soft gate，与原 winner 候选池一起重新评分选优）
- **N=soft_gate_fail_n（默认 3）**：仍失败 → 按 gate 类别分流：
  - 非质量 SOFT：可降级为 diagnostic 放行，问题记审计并注入下一 shot 上下文。
  - `QUALITY_BLOCKING`：转 `failed` 或要求 `revise/reject` 新建 run；不得 hard seal、不得 accepted、不得 export。

**N 计数语义**（崩溃恢复关键）：
- **权威源是 DB 结构化表**：`writing_soft_gate_counters`，每个 `(project_id, logical_shot_id, gate_name)` 一行。每次 soft gate 判定后**立即原子累加**（不是封版时才落）。
- `writing_shots.soft_fail_counts_snapshot` 只允许作为审计快照，不允许业务读取；任何读 N 的逻辑必须查 `writing_soft_gate_counters`。
- `core/retry_budget.SoftGateCounter` **无状态**：`get_level(project_id, logical_shot_id, gate_name)` 从 DB 读，不维护内存计数。崩溃后计数不丢。
- **N 绑定 `logical_shot_id + gate_name`**（跨 run 累积）：同一 logical shot 在不同 run 重跑，soft gate 计数延续——否则崩溃重跑就归零，soft gate 状态机失效。
- **N=2 局部重写的幂等性**：`writing_shots` 加 `redo_in_progress` 子状态标记。崩溃恢复时：检测到 `redo_in_progress` 但无对应新候选 draft = 重跑局部重写；有新候选但无新评分 = 重跑评分。
- N=3 对非质量 SOFT 降级时 winner 仍为原 winner，只标记软约束未达标；质量类失败没有降级 winner。

**多 soft gate 叠加的预算保护**：同一 shot 多个 soft gate 同时触发 N=2，合并为 1 次局部重写（不是每个 gate 各产 2 篇），`retry_budget` 按 shot 汇总 LLM 调用。

**两层 LLM 熔断预算（评审 P0-5，B59 拆分）**：
1. **重试失败熔断 `max_calls_per_shot`（默认 8）**（B59 原义）：同类失败连续 `consecutive_failure_circuit_break`（默认 3）次熔断，失败类型切换归零，单 call_type 调用 ≤ `max_calls_per_shot`。
2. **shot 总调用硬上限 `max_total_llm_calls`（默认 40）**（P0-5 新增）：整个 shot 生命周期所有 LLM 调用总和上限，防类型分散绕过第 1 层。耗尽 → `transition(status,'failed')` 终态，不自动重试（需新建 run）。
以上参数均在 `writing_projects` 表，运行时可调不改代码。
总调用计数落 `writing_shots.llm_call_count` + `llm_call_breakdown`（JSON）；连续失败计数落 `writing_llm_failure_streaks`，每次调用明细落 `writing_ai_call_attempts`，运行时状态变化落 `writing_runtime_events`。`LLMCallBudget` 无状态读 DB。详见 implementation-contract §3.3。

### 铁律 5：正文真相源物理隔离

**病根**：旧系统的 `is_current` 封版规则（未封版读 MAX(revision_sequence)，已封版读 is_current=1）只在 Python 层约定，任何模块直接 `SELECT text FROM shot_revisions` 就绕过。B19 的封版规则在 94 个 bugfix 面前太脆弱。

**铁律**：
- `writing_shot_revisions` 表**只允许 `core/text_repository` 模块 import**
- 通过 Python 包结构 + `__init__.py` 控制：`shot_revisions` 表的 SQL 访问函数只暴露在 `core/text_repository`，其他模块 import 不到
- **DB 层加 VIEW `v_current_text`**：封版逻辑封进 view——`ROW_NUMBER() OVER (PARTITION BY shot_id ORDER BY is_current DESC, revision_sequence DESC) = 1` 的优先级单行返回（is_current=1 优先；同为未封版时 revision_sequence 高者优先），保证每 shot_id 恰好一行。VIEW 必须投影 `revision_id`、`source_revision_id`，供 B92 stale 检测比对。业务模块查 view 而非原表。**禁用 `WHERE is_current=1 OR revision_sequence=MAX` 的 OR 并集写法**——同 shot 既有封版行又有更高未封版行（redo/崩溃重跑场景）时会返回两行，违反单条不变量（评审 P0-3）。
- **CI lint 用 sqlparse 解析**所有 `execute()` 调用的 SQL 字面量 token，断言只有 `core/text_repository.py` 的 SQL 含 `writing_shot_revisions` 表名（白名单 migration/schema/test 模块）。动态构造表名（`'writing_'+t`）、f-string 拼接 SQL 一律禁。
- **text_repository 接口最小化**：只暴露 `read_current_text(shot_id, run_id)` / `write_revision(shot_id, run_id, text, ...)` / `is_hard_sealed(shot_id, run_id)` 三个方法。**禁止** `get_text_by_revision_id` / `get_text_by_sequence` 类直查接口（旧系统正是用这类后门跳过封版判断）。
- 所有正文读取（context_assembler 取前文、fact_anchor_extractor 取源文、export 取正文）**必须**过 `text_repository.read_current_text(shot_id, run_id)`

**诚实声明**：SQLite 无 RLS（行级安全），所谓"物理隔离"是 **Python import 边界 + DB VIEW + CI sqlparse lint 三重约束**，不是 DB 层 RLS。三重约束把绕过成本抬到"必须同时突破 import、写裸 SQL、绕过 CI"，比旧系统单层 Python 约定强得多，但不是理论上不可绕过。若生产部署要求数据库层行级安全，需要使用 PostgreSQL + RLS 配置。

### 铁律 6：高质量写作是硬门禁，不是建议分

**病根**：旧系统和早期设计都可能出现"烂稿里选最高分"、"软维度欠账注入后文"、"人工 accept 覆盖质量失败"的问题。对生产写作而言，"最高分"不等于"可发表"，"已审计"也不等于"已达标"。

**铁律**：
- `writing_projects` 必须包含项目级质量阈值字段：`shot_quality_floor`、`dimension_floor`、`chapter_quality_floor`、`book_quality_floor`、`judge_disagreement_max`、`reader_pull_floor`、`blind_review_min_passes`。
- `MetaContract.style_quality_profile` 必须包含目标读者、文体标杆、正例片段、反例片段、禁止俗套、水文模式、语言/对白/悬疑/母题密度目标、盲评策略、继续阅读目标、protected_roughness 与 voice_anti_samples；没有这些质量锚点不得 `confirm-contract`。
- 所有质量报告必须标注 `evidence_class`（`ES`/`SEMI_ES`/`NES`）与 `defect_class`（`destructive`/`productive`/`neutral`），并给出证据位置、失败原因和可执行修复指令。
- 3 裁判评分后先跑 **quality floor**，再选 winner：`final_score` 低于项目阈值、任一核心维度低于阈值、裁判分歧过大、合格候选不足 `min_eligible_candidates`（默认 2）篇，均不得 winner。
- winner 后必须进入 `polish_revision`：只允许局部润色，不允许新增事实；polish 后重新过 hard gates、quality floor、chapter review，才能 soft seal。
- `polish_revision` 必须保护 `productive_deviations`：不得删除有效粗粝、角色声线、留白、非常规节奏；中性偏离只能标记给人类 review，不得自动磨平。
- 章级 7 维全部是 accept 前硬门禁；允许记录问题注入下一章，但注入不能替代本章质量达标。
- 篇级滚动检测产生 blocking issue 时，禁止后续 accept 与 export，直到 revise/reject 修复并重新检测通过。
- human accept 不得覆盖硬质量失败；`human_decisions.preconditions_json` 必须包含结构化质量报告，任何 hard failure 只能 `revise/reject`。人类可以保护 `productive` 偏离，但不能把 `destructive` 硬失败改成通过。

---

## 2. 角色体系

### 2.1 角色边界

| 角色 | 职责 | 阶段 |
|------|------|------|
| **架构师** | 读元契约 → 生成大纲 → 生成 shot 契约（含 persona 指定 + 强度配比） | Init/Setup |
| **叙事分析师** | 诊断叙事健康（信息差生命周期、节奏曲线、角色弧光），可选审查 | 全程 |
| **写手池** | 5 维度 persona + 1 deviant 沙盒，按契约指定产稿 | 写作 |
| **裁判团** | 3 裁判 × 12 维 trimmed mean 评分 | 评审 |
| **硬门槛官** | 2 道硬门槛（规则快 + 模型深）资格筛选 | 评审 |
| **章级审核官** | 章级 7 维硬质量审核 | 封版 |
| **篇级检测官** | 滚动全书级维度检测（每 N 章跑一次） | 封版 |
| **人类 review** | accept / revise / reject 正式正文 | 封版 |

### 2.1a 主编台与后台生产角色

作者前台只面对 **InkFlow 主编台**。主编台负责引导自然语言交互、回读系统理解、提示待确认事项和恢复中断会话；作者不需要选择内部模块或编辑结构化卡片。

后台必须保留清晰角色边界：

| 后台角色 | 代码名 | 边界 |
|----------|--------|------|
| 流程主持人 | `WorkflowConductor` | 只读取状态、选择下一步角色、提交状态机；不得直接改契约、accept 正文或写 canonical |
| 决策会话主持人 | `DecisionSessionHost` | 持久化自然语言意见、AI 解析、回读文本、确认状态和断点续接 |
| 源料管理员 | `SourceLibrarian` | 导入指南/大纲/素材，计算 source hash，记录来源优先级和 stale |
| 源文档规范员 | `SourceNormalizer` | 合并、去重、拆矛盾、原子化源文档条款，处理 `better.md` 等过程文件生命周期 |
| 契约抽取员 | `ContractExtractor` | 生成 proposed contract patch，不得 confirmed |
| 契约管家 | `ContractSteward` | 管理元契约、卷/部、章、shot 契约版本、状态和变更历史 |
| 闸门守卫 | `Gatekeeper` | 做 schema、必填字段、禁区、质量阈值和状态机硬校验 |
| 真相保管员 | `CanonicalKeeper` | 维护 confirmed/locked 契约与 accepted 正文的唯一真相源 |
| 审计账本 | `AuditLedger` | 追加记录 AI 调用、人类决策、契约变更、运行事件和失败原因 |
| 断点续接器 | `RecoveryManager` | 从 DB 恢复未完成的 DecisionSession、resume point、import finalize 和 AI job |

`WorkflowConductor` 必须是薄调度层或表驱动状态机，不能成为上帝对象。所有生产性写入必须经过 `Gatekeeper` 校验、`ContractSteward` 版本管理、`CanonicalKeeper` 真相源边界和 `AuditLedger` 追加审计。

主编台默认使用选择式对话：每个裁决给 1-8 个编号选项，`0` 返回，`9` 重新生成选项。自由文本只作为补充意见保存，再进入下一轮选项生成；恢复时必须回放原 option set，不能依赖聊天上下文或重新生成一组漂移选项。

### 2.2 写手 persona = 强度调音器（非分工切片）

**核心定义**：persona 不是"只写一个侧面"的分工，是"同一篇完整稿的不同强度配比调音"。每一篇稿都是完整稿（5 维都涉及），只是强度侧重不同。

**5 维度 persona**（对应文学质感的 5 个正交面）：

| persona | 注意力侧重 | 强度侧重 |
|---------|-----------|---------|
| 意象师 | 画面感、感官细节、具象 | 画面维度强度高 |
| 节奏师 | 张弛、长短句、呼吸感 | 节奏维度强度高 |
| 对话师 | 潜台词、信息差、人物声音 | 对话维度强度高 |
| 结构师 | 承转、must_land 落地、骨架 | 结构维度强度高 |
| 悬疑官 | 读者情绪、信息差压住、威胁感知 | 悬疑维度强度高 |

**维度正交性**：前 4 个是"文本侧维度"（文本本身写得好不好），悬疑官是"读者侧维度"（读者此刻情绪状态）。一个 shot 可能文本侧全优秀但读者侧零紧张——悬疑官的注意力正是补这个正交面。

**压迫紧张合并进悬疑官**：压迫紧张（威胁驱动）和悬疑（信息差驱动）是同一读者侧维度的两种形态，合到一个 persona，按 shot 类型在 prompt 里调侧重。

### 2.3 deviant 沙盒（非第 6 维度 persona）

**定义**：deviant 不是"第 6 个维度 persona"，是"探索软约束偏离边界"的沙盒。它的职责不是补一个维度，而是故意偏离 soft_constraints 看会怎样。

**约束**：
- deviant 独立于 X 篇候选之外，单独产 1 篇做参考
- deviant 产稿**走第一道硬门槛**（规则检查，防严重违约），但**不走第二道硬门槛和 3 裁判评分**（它是参考，不进 winner 候选池）
- deviant 失败 → `degraded=True`，不返写，记审计
- deviant 稿经 **`JuryInput.deviant_reference`** 注入给裁判团作"创意边界参考"（裸文本，不评分）——裁判评 `creative_boundary` 维度时可参考该文本，理解"这个 shot 的软约束偏离到什么程度是可行的"。deviant 失败稿不注入（只注入通过第一道门槛的 deviant）。
- `relaxed_soft=True` 字段**仅对 persona=deviant 生效**，其他 persona 必须忽略此字段

---

## 3. 契约系统

### 3.0 源文档规范化

契约抽取前必须先规范化源文档：

- 权威源文档保留原文、path、hash、优先级和来源引用。
- `better.md` 等过程文件只作为 `process_scratch` 输入；抽取完成后，已解决内容合并进原子条款或 confirmed contract，并清空过程文件，只保留 processed manifest/hash 审计。
- 重复条款合并 source_refs；冲突条款生成主编台选择题；含混条款拆成一个个可验证原子条款。
- 原子条款必须包含 stable id、scope、clause_type、severity、source_refs、source_hash 和 status。
- source coverage 固定按原子条款 × contract field 建矩阵；必填字段没有 confirmed clause 或人工空值理由时，不得封板。
- AI 抽取完整性固定采用 primary/crosscheck 双模型交叉抽取；不一致、漏抽、冲突和低置信项进入 coverage gap/conflict，并由主编台选择式裁决。
- 未原子化条款不得进入 contract patch；未 confirmed 条款不得进入 prompt。

### 3.1 契约层级（dataclass 链）

```
MetaContract（元契约，全书级）
  ├─ ProjectIdentity（项目身份）
  ├─ NarrativeVoice（叙事声音）
  ├─ HardBoundaries（硬边界：forbidden_facts/forbidden_words/pov_only）
  ├─ StyleLocks（风格锁）
  ├─ WorldKnowledge（世界知识）
  ├─ MotifSystem（母题系统）
  └─ CreativeZones（创意区）

ShotContract（shot 契约，单 shot 级）
  ├─ MustLand（必须落地：事件/beat/信息释放）
  ├─ AntiWrite（禁区：forbidden_facts/forbidden_words/pov_only）
  ├─ SceneContract（场景/时间/人物位置）
  ├─ PersonaAssignment（persona 指定 + 5 维强度配比）
  └─ SoftConstraints（软约束：可酌情偏离）

OutlineSpec（大纲评估结果：evaluated_outline_text + drift_score）
TaskCard（编译后的 prompt 指令，superseded_at 机制）
PromptSpec（完整 prompt 文本，每 persona 独立，superseded_at）
DraftSpec（产出稿，含 degraded/model/persona/retry_count）
```

### 3.2 旧实现：shot 的 5 维强度配比

> **迁移说明**：本节保留用于解释当前代码和历史评分数据。目标架构的强度、契约、候选和正式评审均提升到 Scene；内部 shot 的强度只能作为 Scene 生成器的局部提示，不能独立决定 winner 或正式封版。

契约里每个 shot 规定 5 维强度目标（画面/节奏/对话/结构/悬疑），用 0-10 整数表达：

- 悬疑高潮 shot：画面3/节奏3/对话2/结构3/悬疑9
- 过渡 shot：画面4/节奏4/对话3/结构2/悬疑1
- 对话重场 shot：画面3/节奏3/对话9/结构3/悬疑3

**强度配比的双重用途**：
1. 写手 persona 产稿时的强度调音目标（persona 有默认侧重，按契约强度目标在该侧重上调音）
2. 裁判团评分时的对标基线（评某篇稿的悬疑维度分，是和契约的悬疑强度目标比，不是绝对分）
3. **12 维加权权重的输入**（评审 P0-1）：`weight_map(intensity_5d)` 把 5 维强度映射为 12 维评分权重（见 §6.2 映射表），悬疑 shot 的悬疑紧张权重自然更高。winner 选择 = `Σ(median[d] × weight[d])`，权重由强度决定，非人工写死。

### 3.3 契约状态机

```
draft（草稿）→ confirmed（确认）→ locked（锁定）
```
- `draft`：契约生成后，可修改
- `confirmed`：Scene 开始正式执行后，契约冻结不可原地改
- `locked`：Scene 封版后，契约随 Scene Revision 一起锁定

### 3.3a 契约作用域与局部修订

全书契约不要求一次讨论到所有细节。第一次只封 `BookContract` 基线，后续通过带作用域的 `ScopedDecisionSession` 优化卷/部、章或 shot。

```
BookContract
  → VolumeContract
    → PartContract
      → ChapterContract
        → SceneContract
          → PromptSnapshot
          → Draft
          → AcceptedCanonical
```

规则：

- 全书红线、POV、类型定位、硬质量标准不能被章级或 Scene 级讨论覆盖。
- 局部修订必须带 `scope_type`、`scope_id`、`base_contract_version`、`change_type` 和 affected scopes。
- 局部修改必须做影响分析；例如第 25 章证据回收调整必须标记第 24/26 章和证据链 stale 风险。
- 已生成 prompt / draft / review 若依赖旧契约，必须标记 stale 并重编译或重跑。
- 已 accepted 正文不得原地改；必须新建 revise run，旧版本留档。

层级字段边界：

- `BookContract` 封全书身份、类型定位、叙事声音、硬边界、世界知识、人物小传、证据链、母题系统、风格锁、质量画像和禁止方向。
- `VolumeContract` 封卷功能、主冲突、进入/退出状态、证据推进、人物弧线增量、母题推进和节奏目标。
- `PartContract` 封局部目标、过渡功能、必需揭示、情绪曲线和依赖范围。
- `ChapterContract` 封章节功能、开场钩子、机构动作、角色代价、must_land、证据种植/回收、章末裂口、对白/感官锚点和反写清单。
- `SceneContract` 使用 hard_constraints、source_dna、soft_goals、creative_openings、entry/exit state；旧 shot 五表只作为迁移来源，内部 shot 卡由 SceneContract 编译。

stale 传播由程序执行：上层 contract 变化必须标记下游契约、prompt、draft、review、book check stale；已 accepted 正文只能通过 revise run 更新。

### 3.4 旧实现：shot 状态机（迁移保护）

> 该状态机在 Scene-first 迁移期间继续保护旧数据和旧运行；目标状态机应建立在 Scene 上，内部 shot 不再拥有独立 accepted 或正式封版终态。

`writing_shots.status` 14 态：`pending → outline_draft → outline_confirmed → task_card_compiled → prompt_compiled → drafting → hard_gate1 → hard_gate2 → jury_scoring → winner_selected → polish_revision → soft_sealed → hard_sealed`，外加终态 `failed`（任一非终态遇硬故障汇聚而来）。

**合法转移矩阵穷举**（未列出的一律非法，`transition()` 抛 `IllegalTransitionError`，完整矩阵见 implementation-contract §3.5a）：
- 主线单向前进链：pending→outline_draft→...→winner_selected→polish_revision→soft_sealed→hard_sealed
- 任一非终态 → failed（失败汇聚）
- `polish_revision` 是质量硬门禁阶段：winner 必须局部精修后重跑 hard gates + quality floor；不过不得进入 `soft_sealed`
- `soft_sealed` 不回退：N=2 翻盘只能发生在 `winner_selected` 进入 `polish_revision` 之前；若 `soft_sealed` 后发现问题，必须新建 run，不修改已软封板 attempt
- 终态 `hard_sealed` / `failed` 无出边（failed 需新建 run_id 重跑，旧 shot 留档）

**乐观锁 CAS**：所有 status 推进 `UPDATE ... WHERE status=:prev` 断言 `affected_rows=1`，并发改抛 `ConcurrentModificationError`（实现见 implementation-contract §3.5a `transition()`）。

### 3.5 并发模型与隔离边界（评审 P0-2）

- **单 session 串行**：一个 writing_sessions 同时只跑一个 shot 流水线，gate_orchestrator 串行推进。
- **多 session 隔离**：靠 `shot_id={logical}@{run}` 天然行级隔离，不同 run 的同 logical shot 是不同行。
- **未来多 worker**：当前 SQLite 单写者无需锁；迁移 PostgreSQL 后用 `pg_advisory_xact_lock(hashtext(shot_id))` 保证同 shot 串行、不同 shot 并行。预留接口 `gate_orchestrator.acquire_shot_lock()`（当前 no-op）。
- **跨 session 同 logical shot 并发**：N 计数绑 logical_shot_id 有竞态，缓解靠 N=2/N=3 动作幂等（重复触发只是多产候选/重复标记 degraded，jury 仍选最优）。详见 implementation-contract §3.7。

---

## 4. 生产流水线

### 4.1 旧实现生产线与 Scene-first 替代关系

> 下列逐 shot 流程用于说明当前实现，不再定义目标生产线。目标第9—14步以完整 Chapter Candidate Branch 为“稿件”，Scene 为最小正式权威；不得逐 shot 拼优。规范流程见 `scene-first-authority-amendment.md` 第8节。

```
1. 读契约（MetaContract）
2. 生成 >= `min_eligible_outlines`（默认 2）份合格大纲（每份先过合格线，不合格重来）
3. 大纲 PK，选优 → 定为 ShotContract 的 must_land
4. 由 must_land 生成写作契约（TaskCard），契约指定该 shot 的 persona + 5 维强度配比
5. 写手池按"同 persona + 同 prompt + 换写手模型"产 X 篇候选
   （X 是全局参数，人类写作前确定，架构写入 DB，默认 X=3）
   （创意 shot 稿件数 = X+3，即默认 6 篇）
6. 第一道硬门槛（规则为主，快）：契约合规/禁区/容量下限/基础可读
   → 不合格稿淘汰
7. 淘汰后 <2 篇 → 补写（同 persona + 同 prompt + 换模型）
8. 第二道硬门槛（模型为主，准）：事实锚点/场景契约对齐/POV 合规/结构骨架
   → 不合格稿淘汰
9. 淘汰后 <2 篇 → 补写
10. 对余下 ≥2 篇做 3 裁判 × 12 维文学评分
11. 低分维度硬筛选（任一核心维度低于项目阈值的 draft 直接淘汰，不允许降权后胜出）
12. 余下去 1 高 1 低取 median；裁判分歧超过阈值则升级 5 裁判或人工复核，不得直接 winner
13. 通过 quality floor 后才选 winner：`final_score >= shot_quality_floor` 且合格候选 >= `min_eligible_candidates`
14. winner 进入 `polish_revision`：局部润色，不新增事实；polish 后重新过 hard gates + quality floor
15. shot 级软封版（仅 polish 后质量达标的 winner 可 soft seal）
16. 一章所有 shot 完成 → 章级审核（7 维全部是 accept 前硬门禁）
    → 任一维未达项目阈值 → revise/reject 新建 run，不能 hard seal
    → 全 7 维达标 → 人工 review，可 hard seal（is_current=1）
17. 每写完 N 章 → 篇级滚动检测（长线悬念闭环/角色弧光/母题回响等）
    → blocking issue 未解决时禁止后续 accept / export

+ deviant 独立于 X 篇之外，同 persona + 同 prompt + 换模型产 1 篇做参考
  （走第一道硬门槛，不走第二道+3 裁判；不进 winner 候选池；通过第一道门槛的 deviant 稿经 JuryInput.deviant_reference 注入 literary_jury 作创意边界参考）
```

### 4.2 产稿机制：同目的约束下的模型差异

> Scene-first 目标中，多样性比较发生在完整 Scene 和完整 Chapter Candidate Branch；内部 shot 可使用相同 persona/prompt 的模型赛马，但局部 winner 不能绕过 Scene 重组与复审进入正式稿。

**核心**：一个 shot 的 X 篇候选，persona 一样、强度配比一样、prompt 一样，多样性来自**换不同的写手模型**。

**设计依据**：
- persona 控制**写作侧重点**（不变）
- 模型控制**文风多样性**（变）
- 两个维度正交，不互相污染
- 同一 LLM 写两次也接受（LLM 本身有随机性）

**写手模型池**：在 `writing_projects` 配置，如 `[claude-opus, gpt-4o, gemini-2.5]`。X 篇按池轮换或随机分配。

### 4.3 X 参数（全局稿件数）

- **X 是全局参数**，人类写作前确定，架构写入 `writing_projects.draft_count`
- 默认 X=3
- 创意 shot 稿件数 = X+3（默认 6）
- X 影响所有 shot 的候选数量，不按 shot 类型单独设（除创意 shot 加成）

---

## 5. 悬疑引擎

### 5.1 信息差生命周期

```
pending → active → reinforced → revealed → resolved → (new gap)
                                                     或 → abandoned
```
- `pending`：信息差已埋设，未被读者感知
- `active`：读者开始感知到信息差
- `reinforced`：信息差被强化（威胁逼近/线索叠加）
- `revealed`：信息差揭示（读者获得信息）
- `resolved`：信息差完全解决（读者理解后果）
- `new gap`：解决后埋新信息差
- `abandoned`：信息差放弃（写作过程中发现该信息差不再需要，如情节调整后失效）——终态，不再转移

**转移合法性约束**（DB CHECK + 应用层校验）：
- 合法转移：`pending→active`、`active→reinforced`、`active→revealed`、`reinforced→revealed`、`revealed→resolved`、`resolved→(new gap 即新建另一行 pending)`、任意态→`abandoned`
- 非法转移（应用层拒绝）：`resolved→pending`、`abandoned→任意`、`revealed→pending`
- DB 列 `status` 加 CHECK 约束枚举 6 值；转移合法性由 `core/information_gap.py` 的 `transition(current, next)` 函数强制

### 5.2 章末钩子是质量阻断项

章末 hook 不达标时（`QUALITY_BLOCKING` gate 失败）：
- N=1：标记，不重写当前 shot
- N=2：局部重写当前 shot
- N=3：不得降级放行；必须 `revise/reject` 新建 run 或转 `failed`，旧 run 留档

**可注入但不替代达标**：问题可以注入下一 shot 的 must_land 作为修复提示，但注入不能替代当前章质量达标。

---

## 6. 评审系统

### 6.1 两道硬门槛

**第一道硬门槛**（产稿后即时，规则为主，快）：
1. 契约合规：must_land 的事件/beat 是否全部出现（规则：关键词/事件标记匹配 + 模型核验）
2. 禁区检查：forbidden_words / forbidden_facts 是否被违反（规则：字符串匹配 + 语义改写检测用模型）
3. 容量下限：UTF-8 bytes ≥ 阈值（纯规则，titled shot ≥ `capacity_floor_titled_shot`（默认 1200），章末 ≥ `capacity_floor_chapter_end`（默认 1500），参数在 `writing_projects` 可调）
4. 基础可读：句长/标点/重复率（纯规则，机械门槛，和文学层"质感"区分——治双重惩罚）

**第二道硬门槛**（文学评分前资格，模型为主，准）：
1. 事实锚点：hard_facts 是否被违反或幻觉（模型核验）
2. 场景契约对齐：场景/时间/人物位置是否符合 scene_contract（模型核验）
3. POV 合规：是否违反 pov_only 约束（模型核验）
4. 结构骨架：must_land 的 beat 顺序/逻辑是否落地（模型核验，比第一道"是否出现"更深）

**两道都过的稿才进 3 裁判评分**。任一道不过 = 淘汰，<2 篇补写。

### 6.2 3 裁判 × 12 维文学评分

**3 裁判**：3 个不同模型（裁判池独立于写手模型池）。**隔离强度（评审 P0-4）**：(1) 配置层强校验 writer_model_pool 与 jury_model_pool 无交集；若必须重叠，则要求排除该 draft 的 writer_model 后仍至少 3 个 jury model；(2) 按 draft 动态排除兜底——`literary_jury.dispatch` 为每个 draft 选 3 裁判时排除产出该 draft 的 `writing_drafts.writer_model`，粒度按 draft 非 shot。**3 裁判都评全部 12 维**（方案 B，治"每裁判只评 4 维 + trimmed mean"的数学矛盾——某维度只 1 裁判评，无法去极值）。

**12 维名单**：

| 维度 | 对应 persona | 说明 |
|------|-------------|------|
| 画面感官 | 意象师 | 场景特异、五感、画面感 |
| 节奏张弛 | 节奏师 | pacing、句长变化、呼吸感 |
| 对话潜台词 | 对话师 | dialogue_subtext、话轮、潜台词 |
| 悬疑紧张 | 悬疑官 | 信息差/威胁/读者揪心 |
| 结构落地 | 结构师 | beat 落地、叙事推进、骨架 |
| 语言质感 | — | 词句质地（文学基础） |
| 情感推进 | — | 情绪曲线是否真实递进（文学基础） |
| 人物可信 | — | 角色声音/行为一致（文学基础） |
| 可读流畅 | — | 机械流畅度（文学基础，但低于门槛"基础可读"则淘汰，治双重惩罚） |
| 母题主题贴合 | — | motif 融入（跨 shot） |
| 章续衔接 | — | 上下文连续（跨 shot） |
| 创意边界 | deviant | 创意 shot 启用，裁判参考 `JuryInput.deviant_reference` |

**裁判分工**（3 裁判全评 12 维，但各有"主视角"，prompt 里强调其主视角维度）：
- **裁判 1**（文本侧主视角）：画面感官、节奏张弛、对话潜台词、悬疑紧张 4 维为其主视角，其余 8 维作辅助评分
- **裁判 2**（文学基础主视角）：语言质感、情感推进、人物可信、结构落地 4 维为其主视角
- **裁判 3**（跨 shot + 创意主视角）：可读流畅、母题主题贴合、章续衔接、创意边界 4 维为其主视角，参考 deviant 稿评创意边界

> 主视角的意义：裁判 prompt 里对其主视角维度要求详细 reasoning，非主视角维度给快速评分。3 裁判全评 12 维保证每维都有 3 个分数可供 trimmed mean 去极值。

**评分流程**：
1. 3 裁判各评全部 12 维（每维 0-100 分，共 36 个分数/draft）
2. 低分维度硬筛选（某 draft 的任一核心维度 3 裁判均分低于 `dimension_floor`，默认 65 → 该 draft 淘汰，不允许降权后胜出）
3. 对每个 draft 的每维：3 个裁判分数去 1 高 1 低 = 剩 1 个中位数 = 该维得分。
   > **诚实声明（评审 P0-1）**：3 样本去 2 个剩 1 个，"trimmed mean"退化为中位数，方差/分歧度信息丢失（[90,80,70] 与 [80,80,80]都得 80）。aggregates 列名用 `*_median` 反映真实算法。final_score 的区分度完全依赖第 4 步的加权权重设计。未来可扩展为 5 裁判（去 2 高 2 低剩 1）或补存 IQR 区间报告反映分歧度。
4. 12 维得分按 `weight_map(intensity_5d)` 加权平均：

**5 维强度 → 12 维权重映射表（评审 P0-1 形式化，winner 选择的数学基础）**：

| 12 维 | 权重来源 | 基准 BASE | 说明 |
|------|---------|----------|------|
| scene_visual（画面） | 画面强度 | 0 | 直接对应 |
| rhythm_pacing（节奏） | 节奏强度 | 0 | 直接对应 |
| dialogue_subtext（对话） | 对话强度 | 0 | 直接对应 |
| suspense_tension（悬疑） | 悬疑强度 | 0 | 直接对应 |
| structure_landing（结构） | 结构强度 | 0 | 直接对应 |
| chapter_continuity（章续） | 结构强度×0.5 | 0 | 结构同源，半权 |
| info_gap_lifecycle（信息差章级） | 悬疑强度×0.5 | 0 | 悬疑同源，半权（章级信息差生命周期） |
| language_texture（语言质感） | 固定基准 | 0.5 | 文学基础维，非零下限 |
| emotional_progression（情感推进） | 固定基准 | 0.5 | 文学基础维 |
| character_believability（人物可信） | 固定基准 | 0.5 | 文学基础维 |
| reading_fluency（可读流畅） | 固定基准 | 0.5 | 跨 shot 维，非零下限 |
| motif_theme_fit（母题贴合） | 固定基准 | 0.5 | 跨 shot 维 |
| creative_boundary（创意边界） | 固定基准 | 0.3 | 创意 shot 启用 |

**归一化公式**：
```
raw[d] = 强度映射值（上表"权重来源"列，强度为 0-10 归一化为 0-1）
weight[d] = (raw[d] + BASE[d]) / Z
Z = Σ(raw[d'] + BASE[d'])   # 12 维求和
final_score = Σ(dimension_score[d] × weight[d])   # weight 已归一化，和为 1
```
**不变量**：(1) `Σ(weight) = 1`；(2) 文学基础维 `weight >= 0.5/Z > 0.05`（BASE 非零保证即便某强度为 0 该维不被忽略）；(3) 悬疑 shot 的 `weight[suspense_tension] > 过渡 shot 的 weight[suspense_tension]`（M4 单元测试断言）。

**`weight_used` JSON schema**（落 `jury_aggregates.weight_used`）：
```json
{"scene_visual":0.12,"rhythm_pacing":0.08,...,"_intensity_5d":{"画面":8,"节奏":5,"对话":6,"结构":7,"悬疑":9},"_Z":7.2}
```
5. quality floor 硬门禁：
   - `final_score >= shot_quality_floor`（默认 80）
   - 每个核心维度 median >= `dimension_floor`（默认 65；项目可提高，不可低于默认）
   - 任一维度 3 裁判最高分与最低分差 <= `judge_disagreement_max`（默认 25），否则开启新的 `jury_round` 并升级到 `escalated_jury_count`（默认 5）裁判，或进入人工复核
   - 合格候选数 >= `min_eligible_candidates`（默认 2）；不足则补写，耗尽预算则该 shot `failed`
   - `would_continue_reading_score >= reader_pull_floor`；盲评未通过不得 winner
   - `destructive` 缺陷为 0；`neutral` 缺陷可进入人工 review；`productive` 偏离必须被保护而非扣成硬失败
6. 加权平均分最高且通过 quality floor = winner；未通过 quality floor 的 draft 不得 `is_winner=1`
7. winner 进入 `polish_revision`，局部润色后重新执行 hard gates + quality floor；polish 不得新增事实、改变 must_land、改变 POV、磨平 `productive_deviations`

**DB schema**（见 implementation-contract §2.4）：
- `writing_jury_raw_scores`：1 行/裁判×draft×jury_round，12 维各一列（每个裁判全填，无稀疏 NULL；基础轮 3 裁判，分歧升级轮可为 `escalated_jury_count`）
- `writing_jury_aggregates`：1 行/draft，存所采用 jury_round 的 12 维聚合得分 + weight_used + final_score + quality_gate_passed + judge_disagreement_max + is_winner

### 6.3 章级审核（7 维）

审 **shot 级审不了的跨 shot 维度**：

**7 维全部为 accept 前硬门禁**（不过 = 不能 hard seal / accepted，返工重写某 shot 或整章）：
1. 章续衔接：上一章末 → 本章首；本章内 shot 之间过渡
2. POV 一致性：全章视角切换合规
3. 角色一致性：跨 shot 的角色声音/行为/动机一致
4. 章末钩子：hook 强度（soft gate 3 级状态机）
5. 章节节奏曲线：高低潮分布符合章节节奏契约
6. 母题密度：本章 motif 实例密度符合契约目标
7. 信息差生命周期：本章悬念的设置/强化/释放节奏合理

所有维度必须达到 `chapter_quality_floor`（默认 75）。问题可以注入下一章作为后续约束，但不能让当前章带着未达标质量进入 accepted canonical。

### 6.4 篇级滚动检测

**不做"全书完稿后一次性 Gate"**，做**滚动检测**——每写完 N 章跑一次全书级维度检测，问题早发现。

**篇级维度**：
1. 长线悬念闭环：第 1 章埋的悬念到第 N 章是否兑现（pending 悬念的 resolved 率）
2. 角色弧光完整：主角的成长/变化曲线是否真实完整
3. 母题回响：motif 在全书的分布密度是否合理（不堆积在某几章）
4. 主题升华：主题是否在全书递进升华
5. 节奏曲线（全书）：高低潮在全书 N 章的分布
6. 伏笔回收：埋的伏笔是否全部回收

**N 值**：在 `writing_projects` 配置，默认 N=5（每 5 章跑一次篇级检测）。

**落库与增量检测**：
- 结果落 `writing_book_check_results`（check_run_id + chapter_range + 6 维分数 + issues JSON）
- 每个 issue 必须标注 `severity`：`blocking` / `warning` / `diagnostic`。存在 blocking issue 时，禁止后续 `accept` 与 `export`，直到 revise/reject 修复并重新检测通过。
- **增量检测**：第 k 次检测只对 `[上次检测截止章+1, 当前章]` 区间的新增章节跑"增量维度"（母题密度/伏笔/悬念 resolved 率可增量累计），"全局维度"（角色弧光/主题升华/全书节奏）仍全量跑但用上次结果作 baseline 对比，降低 LLM 调用成本
- 问题标记到对应章节的 `writing_chapter_specs`（issues 注入），早发现不等到全书完稿

---

## 7. 存储模型（49 张生产表）

**设计原则**：
- 从 0 设计，不沿用旧 56 表
- 保留领域必需 + 踩坑结晶 + 完整生产运行审计
- 正文表物理隔离（铁律 5）
- 一个契约信号只存一处（铁律 2）
- **契约核心字段结构化**（铁律 2）：must_land/anti_write/scene_contract/persona_assignment/soft_constraints 拆为 5 张独立表，非 JSON blob
- **jury 评分拆 raw + aggregate**（方案 B）：raw_scores 存 3 裁判原始分，aggregates 存 trimmed mean + 加权结果，去冗余

### 7.1 旧实现表清单与迁移边界

> 本节列出的 `writing_shot_*` 是当前已实现 schema，不是 Scene-first 目标表。目标权威实体和迁移规则见 `scene-first-authority-amendment.md` 第11节；迁移后 shot 表只能作为内部切片或历史来源，不能与 Scene Revision、Chapter Snapshot 并列为正文真相源。

**第 1 层：项目元数据（3 张）**
1. `writing_projects` — 项目元信息（含 X 全局参数、persona 池配置、写手模型池、裁判模型池、N 篇级检测间隔；model_pool 加 CHECK 约束 `json_array_length(pool) >= draft_count`）
2. `writing_meta_contracts` — 元契约（identity/narrative_voice/hard_boundaries/style_locks/world_knowledge/motif_system/creative_zones/style_quality_profile；质量阈值已迁移至 writing_projects 表独立字段）
3. `writing_chapter_specs` — 章节节奏契约（每章的节奏曲线目标）

**第 2 层：契约链（9 张）** — shot 契约核心字段拆为 5 张结构化表
4. `writing_outline_specs` — 大纲评估结果（evaluated_outline_text + drift_score；**drift_rejected 派生自 drift_score < writing_projects.outline_drift_threshold（默认 0.20），不存列**；is_winner 加唯一约束保证大纲 PK 只选一个 winner）
5. `writing_shot_contracts` — shot 契约主表（shot_id + 契约状态 draft/confirmed/locked + 逻辑指针，不存核心字段 blob）
6. `writing_shot_must_land` — 必须落地（event/beat/info 释放，结构化列）
7. `writing_shot_anti_write` — 禁区（forbidden_facts/forbidden_words/pov_only，结构化列）
8. `writing_shot_scene_contract` — 场景契约（location/time/characters 位置，结构化列）
9. `writing_shot_persona_assignment` — persona 指定（persona + 5 维强度配比 + is_creative + is_suspense）
10. `writing_shot_soft_constraints` — 软约束（relaxable 项 + deviation_budget）
11. `writing_shot_task_cards` — task card（编译后的 prompt 指令，superseded_at 机制）
12. `writing_prompt_snapshots` — prompt 快照（每 persona 的完整 prompt 文本，superseded_at；full_prompt_text 加归档策略，超阈值迁移到独立文件）

**第 3 层：执行与产出（6 张）**
13. `writing_shots` — shot 执行状态（shot_id=logical@run 隔离，status 状态机 14 态，含 polish_revision 质量精修阶段，soft_fail_counts_snapshot 只读审计快照，redo_in_progress 子状态，resume_point 结构化 JSON，updated_at，llm_call_count + llm_call_breakdown 两层熔断计数 P0-5）
14. `writing_soft_gate_counters` — soft gate N 计数唯一权威源（每 project_id+logical_shot_id+gate_name 一行，原子累加）
15. `writing_runs` — run attempt 记录（session 隔离）
16. `writing_sessions` — session 记录（含 crashed 标记）
17. `writing_drafts` — 产出候选稿（含 degraded 标记、模型来源、persona、retry_count、is_deviant、source_revision_id 支撑 B92 stale 检测）
18. `writing_shot_revisions` — 正文封版（is_current 封版规则；source_revision_id 列支撑跨 run stale 检测；**物理隔离，只 core/text_repository 可访问**；DB VIEW v_current_text 封装封版逻辑）

**第 4 层：评审（5 张）**
19. `writing_draft_eligibility` — 硬门槛结果（2 道门槛各 4 维度的 eligible 标记）
20. `writing_jury_raw_scores` — 3 裁判原始分（1 行/裁判×draft，12 维各一列，3 裁判全填无稀疏 NULL）
21. `writing_jury_aggregates` — 评分聚合（1 行/draft，12 维 median 得分 + weight_used + final_score + quality_gate_passed + judge_disagreement_max + is_winner；is_winner 要求质量门禁通过）
22. `writing_chapter_reviews` — 章级审核（accepted canonical 唯一索引；7 维度结果；accepted 要求 7 维全部达到 chapter_quality_floor）
23. `writing_failure_attributions` — 失败归因审计（degraded 的 failure_category + failure_level + gate_name + soft_gate_n + injected_to_shot_id，支撑质量阻断与非质量降级审计链）

**第 5 层：悬疑、一致性与篇级检测（3 张）**
24. `writing_information_gaps` — 信息差生命周期（6 态状态机 + abandoned 终态 + 转移合法性 CHECK）
25. `writing_motif_instances` — motif 密度追踪
26. `writing_shot_scene_fingerprints` — 场景指纹（L3 多样性 gate）

**篇级滚动检测落库**（新增，单独列出因跨章聚合）：
27. `writing_book_check_results` — 篇级检测结果（每 N 章跑一次的 6 维全书级检测落库，check_run_id + chapter_range + 6 维分数 + issues + blocking_issue_count + quality_gate_passed，支撑增量检测：下次只检测新增章节）

**第 6 层：运行时审计与恢复（5 张）**
28. `writing_ai_call_attempts` — 每次 AI 调用的幂等审计（call_type/model/prompt_hash/response_hash/token/error/retry_of）
29. `writing_runtime_events` — 状态机、gate、human decision、resume、export 的事件时间线
30. `writing_llm_failure_streaks` — `(shot_id, call_type, failure_type)` 连续失败计数权威源
31. `writing_session_checkpoints` — 崩溃恢复 checkpoint，含 `payload_checksum`（SHA-256）检测损坏，按 session/phase/shot 记录，最多保留最近 N 个稳定点（`checkpoint_max_retention`，默认 3）
32. `writing_human_decisions` — setup confirm、contract confirm、accept/revise/reject/abort 的 actor/reason/前置条件审计；accept 必须写 quality_report_json，且不可覆盖硬质量失败

**第 7 层：契约可审计性与事实锚点（4 张）**
33. `writing_contract_clauses` — 元契约和 shot 契约的条款级 ID，供 gate/failure attribution 精确引用
34. `writing_contract_changelog` — 契约变更历史，记录 old/new hash、actor、reason、human confirmation
35. `writing_fact_anchors` — fact anchor 抽取、核验、来源 revision、置信度和违反记录
36. `writing_context_snapshots` — 每次 prompt/context 组装的输入快照，支撑 replay、审计和 stale 检测

**第 8 层：已有稿导入与重构（4 张）**
37. `writing_import_runs` — 导入/重构 dry-run/finalize 批次
38. `writing_import_manifests` — 源文件/章节/shot 的 source hash 与映射计划
39. `writing_import_questions` — 低置信导入问题、人类裁决、resolution
40. `writing_import_decisions` — 导入 finalize 时的人类确认与原子落库审计

**第 9 层：主编台与源文档规范化（9 张）**
41. `writing_source_documents` — 源文档注册表，含 `better.md` 等过程文件状态
42. `writing_atomic_source_clauses` — 源文档原子条款
43. `writing_source_extraction_runs` — primary/crosscheck 抽取运行审计
44. `writing_decision_sessions` — 可恢复人类决策会话
45. `writing_decision_option_sets` — 1-8/0/9 选择式对话选项集
46. `writing_contract_versions` — 层级契约版本
47. `writing_contract_patches` — 契约 patch 与 stale 影响范围
48. `writing_source_coverage_matrix` — 原子条款 × contract field coverage gate
49. `writing_process_file_manifests` — 过程文件清空后的 manifest，不保存正文/摘要

### 7.2 不纳入 schema 的（dataclass/内存承载）
- prompt 中间对象（编译过程在内存；完整 prompt 和 hash 落 `writing_prompt_snapshots`）
- 裁判中间去极值计算（3 裁判原始分落 `jury_raw_scores`，median + 加权结果落 `jury_aggregates`）
- 临时格式化视图（报告 HTML/CLI 表格可重建，不作为真相源）

### 7.3 三棵树与正文存储

**三棵树（契约树/执行树/正文树）都是索引，不存正文**：
- 契约树：`writing_shot_contracts` 等，存契约约束的结构化投影（must_land/anti_write 是契约约束，不是正文）
- 执行树：`writing_shots`/`writing_drafts`，存执行状态与候选稿
- 正文树：`writing_shot_revisions`，**唯一正文真相源**（物理隔离）

---

## 8. 模块骨架

```
ink/src/ink/
├── contract/              # 契约层（代码生成 dataclass）
│   ├── schemas/           # pydantic schema 定义（代码生成源）
│   ├── generated/         # 生成的 dataclass（勿手改）
│   ├── meta_contract.py   # MetaContract DB 加载
│   ├── shot_contract.py   # ShotContract DB 加载
│   ├── outline_spec.py    # OutlineSpec DB 加载
│   ├── task_card.py       # TaskCard DB 加载
│   ├── prompt_spec.py     # PromptSpec DB 加载
│   └── draft_spec.py      # DraftSpec DB 加载
├── core/                  # 核心机制
│   ├── text_repository.py # 正文物理隔离（唯一可访问 shot_revisions）
│   ├── retry_budget.py    # 熔断 + soft gate 3 级计数
│   ├── session_manager.py # shot_id={logical}@{run} 隔离
│   ├── resume.py          # 崩溃恢复
│   └── outline_integrity.py # outline_has_incomplete_tail
├── writers/               # 写手层
│   ├── quad_dispatcher.py # 同 persona + 同 prompt + 换模型
│   ├── local_fallback.py  # degraded=True 占位
│   └── model_pool.py      # 写手模型池管理
├── jury/                  # 评审层
│   ├── hard_rule_gate.py  # 第一道硬门槛（规则为主）
│   ├── hard_rule_gate2.py # 第二道硬门槛（模型为主）
│   └── literary_jury.py   # 3 裁判 × 12 维 trimmed mean（创意 shot 也走此模块，deviant 经 JuryInput.deviant_reference 注入作创意边界参考，无独立 creative_jury）
├── gates/                 # gate 层（hard/soft/diagnostic）
│   ├── fact_manifest.py
│   ├── capacity.py
│   ├── l4_scene.py
│   ├── l3_diversity.py
│   ├── chapter_hook.py    # soft（3 级状态机）
│   ├── exposition_drift.py # soft
│   └── intent_drift.py    # diagnostic
├── pipeline/              # 编排层（shot 级入口只收 shot_id+run_id；非 shot 级入口只收业务 ID）
│   ├── outline_orchestrator.py
│   ├── write_orchestrator.py
│   ├── jury_orchestrator.py
│   ├── gate_orchestrator.py
│   ├── chapter_review_orchestrator.py
│   ├── book_rolling_check_orchestrator.py
│   └── export_orchestrator.py
├── contract_compiler/     # 契约编译（生成 prompt）
│   ├── task_card_compiler.py
│   └── prompt_compiler.py
└── cli.py                 # 薄壳 < 500 行
```

**orchestrator 物理隔离**（铁律 2）：shot 级 `pipeline/*_orchestrator.py` 入口只收 `(shot_id, run_id)`；chapter/book/import/export 入口只收自己的业务 ID。所有 orchestrator 都禁止传上游 dataclass，入口从 DB 重新加载所需投影。

---

## 9. 下游文档

- `implementation-contract-v1.md`：dataclass 完整定义（pydantic schema）、49 张生产表 DDL、模块接口契约、代码生成 + `unpack()` 访问器 + AST 字段消费 lint 配置、sqlparse SQL lint 配置、shot_status→resume 映射矩阵
- `pitfall-checklist.md`：15 条踩坑修复在新架构的落点 + 新增条目（B19 物理隔离、B66 两道门槛、reading_fluency 去重、soft gate 3 级、deviant 评审、B29/B44/B92 resume 语义、jury 方案 B 数学修正）
- `optimization-review.md`：5 个专家视角的优化设计评审结论，明确当前设计可作为完整生产版实现基线，并列出 P0/P1 收敛项
- `migration-plan.md`：从 0 构建的 M0-M6（无工期、无双轨、无迁移旧系统）；M6 联调 ≥6 章（覆盖跨章/篇级/崩溃恢复）；557 旧测试三桶迁移方法论
- `author-workflow-contract.md`：完整作者工作流契约（无 MVP，覆盖导入、setup、write、review、revise/reject/accept/export）
- `interactive-contract-workflow.md`：主编台、DecisionSession、ScopedDecisionSession、后台角色边界与自然语言交互防漂移机制
- `invariant-traceability.md`：旧 bugfix / 架构决策 / 新测试 / 里程碑阻断矩阵
