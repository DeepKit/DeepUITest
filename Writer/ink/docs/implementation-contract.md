# Ink v2 Scene-first 实现契约

> 状态：P0 实现法源
> 日期：2026-07-14
> 对应设计：`design.md`

## 0. 当前实现状态

| 能力 | 当前真实状态 |
|---|---|
| 12张Scene-first表、FK、唯一索引和不可变trigger | 已在`sql/schema.sql`落地，仅作影子层 |
| Scene/Contract/Clause/Revision基础Repository | 已实现 |
| Branch-local expected parent与合法分叉 | 已实现并测试 |
| Branch Version基础冻结与content hash | 已实现；完整Scene集合、Fact和质量门尚未接入 |
| Snapshot封口、固定Revision序列、Chapter Head CAS | 已实现并测试 |
| Selection/Human Decision、Runtime Event、质量/伦理硬门 | 未接入Scene-first Accept |
| Generation Round有界状态机 | 已完成：固定2+条件补3、0篇终止、≥3/实质差异/文学绝对门槛、预算熔断、CAS、恢复、全部终态及真实模型ports均已实现并测试（Scene-first影子层，未接CLI、未投产） |
| 契约双师、盲审和actor权限 | 尚未实现 |
| 正式CLI、accept、export、context、repair切换 | 尚未切换，旧Shot路径仍是唯一生产权威 |
| 既有生产库迁移脚本和回填 | 尚未实现 |

本文件后续章节同时包含“已实现底座”和“必须达到的最终契约”。不得仅凭DDL或
Repository存在就宣称对应生产能力完成。

## 1. 数据库实体

### 1.1 Scene

```sql
writing_scenes(
  scene_id,
  project_id,
  chapter_id,
  logical_scene_key,
  scene_order,
  created_at
)
```

Scene 是稳定身份，不保存正文，不保存全局 current revision。

### 1.2 Scene Contract

```sql
writing_scene_contracts(
  scene_contract_id,
  scene_id,
  version,
  status,
  contract_hash,
  parent_contract_id,
  source_bundle_hash,
  created_by,
  created_at,
  activated_at,
  superseded_at
)
```

状态：

```text
draft
self_checked
under_review
revision_required
human_resolution_required
approved
active
superseded
```

同一 Scene 最多一个 active Contract。

### 1.3 Contract Clause

```sql
writing_scene_contract_clauses(
  clause_id,
  scene_contract_id,
  layer,
  clause_key,
  clause_text,
  severity,
  source_asset_id,
  source_anchor,
  authority_rank,
  confidence,
  risk_if_removed,
  supersedes_clause_id,
  created_at
)
```

`layer`：

```text
hard_constraint
source_dna
soft_goal
creative_opening
```

### 1.4 Scene Revision

```sql
writing_scene_revisions(
  scene_revision_id,
  scene_id,
  parent_revision_id,
  scene_contract_id,
  generation_task_id,
  repair_task_id,
  context_snapshot_id,
  text,
  text_hash,
  actor_type,
  actor_id,
  change_reason,
  created_at
)
```

约束：

- `text` 创建后禁止 UPDATE；
- 被 Branch/Snapshot 引用后禁止 DELETE；
- AI 只能 INSERT candidate revision；
- Revision 不保存 `is_current`；
- Canonical 由 Chapter Snapshot 决定。

### 1.5 Internal Shot

```sql
writing_scene_internal_shots(
  internal_shot_id,
  scene_revision_id,
  shot_order,
  purpose,
  text_start,
  text_end,
  created_at
)
```

Internal Shot 不能被 accepted、sealed 或 export。

### 1.6 Generation Round

```sql
writing_chapter_generation_rounds(
  generation_round_id,
  project_id,
  chapter_id,
  outline_version_id,
  chapter_contract_version_id,
  round_number,
  status,
  initial_target_count,
  supplement_target_count,
  eligible_count,
  call_count,
  failure_reason,
  created_at,
  updated_at
)
```

### 1.7 Candidate Branch

```sql
writing_chapter_candidate_branches(
  branch_id,
  generation_round_id,
  candidate_index,
  writer_model,
  generation_strategy,
  status,
  created_at
)
```

### 1.8 Branch Version

```sql
writing_chapter_candidate_branch_versions(
  branch_version_id,
  branch_id,
  version,
  parent_branch_version_id,
  outline_version_id,
  chapter_contract_version_id,
  world_snapshot_id,
  fact_snapshot_id,
  content_hash,
  status,
  created_at,
  frozen_at
)
```

当前`status`只有`building`和`frozen`。`frozen_at`在唯一一次冻结时写入；
冻结后禁止修改。

### 1.9 Branch Scene Binding

```sql
writing_branch_scenes(
  branch_version_id,
  scene_order,
  scene_id,
  scene_revision_id
)
```

唯一约束：

```text
UNIQUE(branch_version_id, scene_order)
UNIQUE(branch_version_id, scene_id)
```

### 1.10 Chapter Snapshot

```sql
writing_chapter_snapshots(
  snapshot_id,
  project_id,
  chapter_id,
  source_branch_version_id,
  chapter_contract_version_id,
  world_snapshot_id,
  fact_snapshot_id,
  snapshot_hash,
  accepted_decision_id,
  created_at,
  sealed_at
)
```

`sealed_at` 只作同一 Accept 事务内的构造闩锁：先创建 Snapshot、复制绑定，
再执行唯一一次 `NULL → timestamp` 封口。封口后 Snapshot 禁止 UPDATE/DELETE，
且禁止继续插入、修改或删除绑定；业务上仍视为一次原子创建。

### 1.11 Snapshot Scene Binding

```sql
writing_chapter_snapshot_scenes(
  snapshot_id,
  scene_order,
  scene_id,
  scene_revision_id
)
```

### 1.12 Chapter Head

```sql
writing_chapter_heads(
  project_id,
  chapter_id,
  active_snapshot_id,
  version,
  updated_at
)
```

同一章节只有一个 Head。

## 2. 核心事务

### 2.1 创建 Scene Revision

输入：

```text
scene_id
branch_version_id
expected_parent_revision_id
scene_contract_id
text
actor
reason
```

校验：

1. Contract 是 active；
2. Branch 未冻结；
3. expected parent 等于 Branch-local Scene 绑定；
4. AI必须且只能携带一个generation/repair task ID；generation task须对应当前候选Branch且未被拒绝，repair task须存在于`writing_scene_repair_tasks`、作用域/父Revision/Contract一致且状态为planned或running；
5. text hash 未重复。

只 INSERT，不激活 Canonical。

### 2.2 冻结 Branch Version

最终校验：

- 所有必要 Scene 存在；
- Scene Contract/Fact 门通过；
- Scene 顺序唯一；
- content hash 可重算；
- Branch Version 尚未冻结。

当前Repository已经实现“至少一个Scene、顺序唯一、hash可重算、尚未冻结”；
必要Scene完整性、Scene Contract/Fact/质量门仍在`tasks.md`。冻结后绑定不可修改；
局部返工创建新Branch Version。

### 2.3 Accept Chapter

以下是最终生产事务。当前 Scene-first Repository 已把 Selection Decision、
Human Decision、Snapshot、Chapter Head CAS 与 Runtime Event 纳入同一事务，并由
human actor 门保护；Scene/Chapter/Book 硬门仍未全部接入，因此不得据此宣称投产完成。

使用 `BEGIN IMMEDIATE`（SQLite）或章节级事务锁（PostgreSQL）。

步骤：

1. 读取并锁定 Chapter Head；
2. 校验 expected head version；
3. 校验 Branch Version 冻结且被选中；
4. 校验 Scene/Chapter/Book 硬门；
5. 创建 Snapshot；
6. 复制有序 Branch Scene 绑定到 Snapshot；
7. 计算并校验 Snapshot hash；
8. 写 Selection Decision 和 Human Decision；
9. CAS 更新 Chapter Head；
10. 写 Runtime Event；
11. 提交。

任一步失败全部回滚。

### 2.4 Export

唯一合法查询路径：

```text
ChapterHead.active_snapshot_id
→ ChapterSnapshotScenes
→ SceneRevisions.text
```

禁止从：

- legacy `v_current_text`；
- latest Scene Revision；
- run 下所有 Shot；
- accepted review 后动态拼接；

生成正式导出。

## 3. 状态机

### 3.1 Generation Round

合法主线：

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

异常：

```text
initial_zero_pass
candidate_shortage
diversity_shortage
failed
superseded
```

0 篇首批过线直接结束当前生产轮；不在同轮无限补稿。

实现（Scene-first 影子层，`ChapterSnapshotRepository`，见
`docs/superpowers/specs/2026-07-14-generation-round-state-machine-design.md`）：

- **唯一状态写入口** `transition_generation_round`；`mark_initial_zero_pass`/
  `mark_candidate_shortage`/`mark_diversity_shortage`/`mark_failed`/
  `mark_superseded`/`start_supplement`/`begin_selection`/`complete_selection`
  均为薄封装，内部委托 transition，自身不含 UPDATE SQL。
- **CAS**：`UPDATE ... SET status=? WHERE generation_round_id=? AND status=?`，
  rowcount!=1 抛 `ConcurrentModificationError`。非法跳转抛 `IllegalTransitionError`，
  终态锁抛 `TerminalStateError`。`superseded`/`failed` 只能从非终态进入。
- **eligible_count**：`record_eligible_branch` 在 branch CAS
  `validating→eligible` 的同一 `BEGIN IMMEDIATE` 事务内对 round.eligible_count
  做 `+=1` 的 rowcount CAS；branch CAS 失败则整事务回滚，计数不变。
- **补稿唯一性**：由状态拓扑保证——`supplementing` 唯一前置 `validating_initial`，
  且 `supplementing` 后只能去 `validating_supplement`、不可回流，无需额外标记列。
- **call_count与预算**：`increment_call_count` 事务内单调非减记账；驱动器配置
  `call_budget` 时，达到上限立即进入 `failed`，禁止继续生成。
- **恢复点**：`get_generation_round_state` 返回 `RoundState`
  (status/eligible_count/call_count/failure_reason/initial_target_count/
  supplement_target_count/updated_at)，不存在 id 抛 `DataIntegrityError`；生成/验证/选优按
  当前状态与已有候选恢复，不重复首批。
- **驱动器**：`GenerationRoundDriver` 固定首批2篇；首批0篇进入
  `initial_zero_pass`；首批1—2篇只补一次默认3篇；补后不足3篇进入
  `candidate_shortage`；port异常统一封入`failed`合法终态。
- **真实模型ports**：`RealGenerationPort`只写Scene-first Branch/Revision并要求active
  Scene Contract；`RealValidationPort`执行七维资格门；`RealSelectionPort`盲判实质差异并按
  项目文学绝对门槛选优。JSON不可解析一律fail-closed，不伪造通过分数。
- **状态写所有权**：ports只生成证据或返回决策；branch选择与round迁移只由驱动器通过
  Repository执行。模型调用幂等键按round/step/branch稳定生成，支持崩溃恢复。
- **门槛边界**：Repository保证计数正确与跳转合法；`begin_selection`硬守
  `eligible_count≥3`，实质差异与文学绝对门槛由真实SelectionPort判定。
- **生产边界**：上述能力仍是Scene-first影子层；未接CLI，未改变旧Shot生产权威。

### 3.2 Candidate Branch

```text
generating
→ validating
→ eligible
→ literary_review
→ selected | rejected
```

**状态迁移原语（CAS，INV-ROUND-018/019）：**
- `start_validating_branch(branch_id)`：`generating → validating`。预期状态硬守 `generating`，非 `generating` 拒（`ConcurrentModificationError`）。
- `advance_to_literary_review(branch_id)`：`eligible → literary_review`。预期状态硬守 `eligible`，非 `eligible` 拒。

`record_eligible_branch`（`validating → eligible`，同事务 round.eligible_count CAS，INV-ROUND-008）与 `select_branch`（`→ selected`）签名不变，见 §3.1/§4。

### 3.3 Contract

见 1.2。架构师 actor 不得同时作为最终批准 actor。

## 4. 评审独立性

契约和文学评审必须保存：

```text
reviewer_model
reviewer_family
prompt_hash
blind_context_hash
visible_prior_reviews = false
review_order
verdict
evidence_json
```

同一门至少三个不同模型家族；一个家族一票。

## 5. AI 权限

AI 可以：

- 起草契约；
- 创建候选 Revision；
- 生成评审意见；
- 提交修正案。

AI 不可以：

- UPDATE Scene Revision；
- 激活 Contract；
- 冻结 Branch；
- Accept Chapter；
- 更新 Chapter Head；
- 覆盖 Human Decision。

## 6. SQLite 实现要求

- `PRAGMA foreign_keys=ON`；
- WAL；
- `busy_timeout`；
- 写入串行队列；
- `BEGIN IMMEDIATE` 用于 Accept/Cutover；
- trigger 阻断不可变表 UPDATE/DELETE；
- partial unique index 保证 active Contract；
- 所有事务写 Runtime Event。

## 7. PostgreSQL 实现要求

- Scene/Branch 写入使用行锁或 advisory lock；
- Chapter Accept 锁 `project_id + chapter_id`；
- RLS 区分 AI writer、reviewer、human accept；
- 只允许受控函数更新 Chapter Head；
- Snapshot/Revision 表撤销 UPDATE 权限。

## 8. Legacy 兼容

旧 `writing_shot_*` 表在迁移完成前只作当前实现和回填来源。Cutover 后：

- 禁止 accepted/export 读取旧表；
- 旧表只读；
- `shot_id` 映射为 `legacy_shot` 或 Scene Internal Shot；
- 不物理删除历史审计数据。
