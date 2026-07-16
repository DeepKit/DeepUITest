# Ink v2 Scene-first 技术设计

> 状态：当前目标设计
> 日期：2026-07-14
> 上位法源：`scene-first-authority-amendment.md`

## 1. 设计目标

Ink 同时保障：

1. 事实、人物、因果和长篇连续性的质量下限；
2. 人物临场反应、语言发现、留白和意外价值的文学上限；
3. 数据库权威、不可变版本、可恢复编排和防 AI 乱改；
4. 失败可归因、返工有界、契约可修订但不膨胀。

系统不承诺用流程制造伟大文学；系统的目标是避免坏稿混入正式稿，并提高优秀候选被发现和保留的概率。

## 2. 权威层级

```text
SourceAssetVersion
→ AtomicSourceClause
→ ContractVersion(Book/Volume/Part/Chapter/Scene)
→ ChapterGenerationRound
→ ChapterCandidateBranchVersion
→ ordered SceneRevision bindings
→ SelectionDecision
→ ChapterSnapshot
→ ChapterHead.active_snapshot_id
→ ExportArtifact
```

### 2.1 Scene

Scene 是稳定的故事逻辑身份，不直接等于某一版正文。

Scene Revision 保存完整场景文本，创建后不可修改。

### 2.2 Internal Shot

Internal Shot 可用于：

- 分段生成；
- 上下文窗口；
- 局部诊断；
- 流式断点；
- 局部修复定位。

Internal Shot 不拥有 accepted、canonical、winner、seal 或 export 权限。修改内部 Shot 后必须形成新的完整 Scene Revision，并重跑 Scene 级检查。

### 2.3 Chapter Candidate Branch

一篇候选稿是完整章节分支，绑定确定的 Scene Revision 序列。选优比较完整分支，不逐 Scene 或逐 Shot 拼优。

### 2.4 Chapter Snapshot

Chapter Snapshot 冻结：

- 所选 Branch Version；
- Scene Revision ID 和顺序；
- 契约、事实、世界状态版本；
- 内容 hash；
- 接受决策。

正式导出只读取 Chapter Head 指向的 active Snapshot。

## 3. 契约体系

### 3.1 Scene Contract 四层

| 层 | 作用 | 违反处理 |
|---|---|---|
| hard_constraints | 事实、状态、知情边界、必要因果、红线 | 失败 |
| source_dna | 原稿创作机制，不复制具体骨架 | 评估传递质量 |
| soft_goals | 场景功能、人物/关系变化、情绪与信息策略 | 允许优秀偏离 |
| creative_openings | 明确留给正文发现的空间 | 不得预先锁死 |

### 3.2 契约角色

- 契约架构师：抽取、分层、减法、起草和修订；
- 契约复审师：独立核源、发现冲突和过度约束，只给结构化意见；
- 程序编排器：校验独立性、聚合意见、执行状态迁移；
- 作者：仅处理高影响、不可自动消解的冲突。

### 3.3 契约版本

同一 Scene 同一时刻最多一个 active Scene Contract。候选必须绑定具体契约版本，契约变化后旧 Prompt、候选和评审标记 stale。

## 4. 第9—14步候选生产

### 4.1 Generation Round

```text
planned
→ generating_initial
→ validating_initial
→ supplementing
→ validating_supplement
→ ready_for_selection
→ selecting
→ selected
```

异常状态：

```text
initial_zero_pass
candidate_shortage
diversity_shortage
failed
superseded
```

### 4.2 数量规则

1. 首批生成两个完整章节候选。
2. 0 篇过线：不进入补稿，当前生产轮失败并按有界回退处理。
3. 1—2 篇过线：补充生成默认 3 篇，每轮只补一次。
4. 同一大纲和契约作用域累计有效候选不少于 3，才可选优。
5. 数量、实质差异和绝对文学门槛必须同时满足。

### 4.3 有效候选

完整候选必须：

- 所有必要 Scene 通过契约与事实门；
- 章节连续性通过；
- 无严重文学否决项；
- 与其他候选存在实质差异。

### 4.4 文学选优

采用：

- 匿名候选；
- 独立绝对门槛；
- Pairwise blind ranking；
- 文本证据；
- Pareto 非支配保留；
- 少数冠军保护。

不以平均分强迫选出“最不差”稿件。

## 5. 评审门

| 门 | 对象 | 目的 |
|---|---|---|
| 契约合理性 | Scene Contract | 契约是否可写、可执行、不过度约束 |
| 叙事潜力 | Contract/Outline | 是否留有悬疑、压力、留白和创意空间 |
| 契约符合性 | Scene Revision | 是否违反硬约束 |
| 事实一致性 | Scene Revision | 历史、人物关系、时间线、器物和知识边界 |
| Scene 文学门 | Scene Revision | 场景整体性、人物选择、情绪、潜台词 |
| Chapter 文学选优 | Candidate Branch | 绝对门槛、比较排序、少数冠军 |
| Volume/Book 审计 | Snapshot 序列 | 长程人物、伏笔、主题和节奏 |

同一门采用目的相近的专家，由不同模型家族产生判断差异。复审必须匿名、独立、记录模型家族和 Prompt hash。

## 6. 正文与版本

### 6.1 Canonical 与 Branch Head

- Canonical Head：当前 accepted Chapter Snapshot 指向的 Scene Revision；
- Branch-local Head：某候选分支当前绑定的 Scene Revision。

生成候选时校验 Branch-local expected parent，不能拿全局 Canonical Head 阻断合法分叉。

### 6.2 Scene Revision 状态

Revision 文本创建后不可变。质量和选择状态由关联记录表达：

```text
generated
→ contract_validated
→ fact_validated
→ scene_quality_validated
→ frozen_in_branch
→ selected_in_snapshot
→ canonical
```

### 6.3 Accept

Accept 是章节级事务，不是逐 Scene 改 current：

1. 校验 Branch、Scene、Chapter、Book 门；
2. 创建不可变 Snapshot；
3. 写有序 Scene 绑定；
4. 写 Selection/Human Decision；
5. CAS 更新 Chapter Head；
6. 写 Runtime Event。

## 7. 返工

快速归因每次执行，深度归因在重复失败或升级上游前执行。

| 根因 | 处理 |
|---|---|
| fact source | 修事实认定 |
| contract gap | 增补契约 |
| contract overconstraint | 删除/软化条款、增加开放口 |
| outline weakness | 回大纲 |
| writer drift | 改生成策略 |
| candidate similarity | 改多样化策略 |
| context compile | 修上下文编译 |
| reviewer false positive | 修评审器 |
| model failure | 换模型/熔断 |

返工创建新 Scene Revision 和新 Branch Version；旧 Snapshot 永远不变。

## 8. 样本与指导卡

- 正式稿不是默认 Prompt 样本；
- 正例蒸馏为 Guidance Card；
- 反例蒸馏为 Anti-pattern Card；
- 卡片按场景、故障签名检索；
- 记录来源、版本、适用边界、反照抄规则、最大使用次数、冷却和效果；
- 同一指导卡不得长期常驻 Prompt。

## 9. 当前实现与目标差异

当前代码是“旧Shot生产权威 + Scene-first影子基础层”：

- `sql/schema.sql`已经包含Scene、Contract、Revision、Branch、Snapshot和Head表；
- `SceneRepository`和`ChapterSnapshotRepository`已支持基础影子写入、冻结、Snapshot和CAS；
- 正式CLI、`HumanReviewOrchestrator`、export、context和repair仍走旧Shot路径；
- Generation Round、双师契约、文学选优、Decision/Event硬门和生产迁移尚未闭环。

Scene-first未完成前：

- 不宣布新架构投产；
- 不让 Scene 表和 Shot 表同时 accepted/export；
- 不删除旧数据；
- 只允许影子回填、导出对比和一次切换。
