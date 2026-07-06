# 优化设计评审结论

> **状态**：v2（2026-07-04，Pre-M0 开工门禁修订）
> **定位**：记录 5 个专家视角对 InkFlow v2 完整生产重构文档的评审结论。本文不是实施计划替代品；所有结论必须回落到 `design-v2.md`、`implementation-contract-v1.md`、`migration-plan.md`、`pitfall-checklist.md`、`author-workflow-contract.md` 与 `invariant-traceability.md`。

---

## 1. 总结论

当前设计可以作为 **完整生产版实现基线**。它不是 MVP，也不是旧系统的增量迁移；它的优化目标不是表数量最少或最快上线，而是：

1. 契约信号不能在 DB、编排、prompt、draft、jury、export 之间静默丢失。
2. 正文真相源不能被普通业务 SQL 绕过。
3. 写作质量不能只作为建议分；shot/chapter/book 任一层硬质量失败都不得 accepted/export。
4. 高质量不能只靠总分证明；必须有盲评、继续阅读、ES/SEMI_ES/NES 证据分层、destructive/productive/neutral 缺陷分类和 productive_deviation 保护。
5. AI 调用、失败、人工决策、崩溃恢复、导入与导出都可审计、可恢复、可测试。
6. 旧系统反复复发的 bug 必须转成新系统的不变量和 CI 门禁。

按这个目标，当前文档已经从“方向正确”收敛为“可作为生产实现基线”。但这不等于带条件进入业务开发；专家审查发现的 DDL、jury 升级轮、orchestrator 入口、resume SQL、字段消费 lint 边界等 P0 可执行性问题，必须先在 Pre-M0 开工门禁全部清掉，再进入 M0 正常开发。是否真正达到最优，取决于 M0-M6 实现后 invariant 测试是否全部通过；文档层面不再接受用 MVP、双轨、共享旧库或后续补齐来降低范围。

---

## 2. 五个专家视角

### 2.1 架构专家

**结论**：架构主线成立。`DB 唯一真相源 + 代码生成 dataclass + 字段消费 AST lint + orchestrator 入口只收 id + text_repository 隔离` 能直接针对旧系统的契约丢失病根。

**已收敛点**：
- 旧 `inkflow/` 只作为领域知识参考，不继承 schema、CLI 或双轨逻辑。
- 契约核心字段拆 5 张结构化表，避免 JSON blob 成为第二真相源。
- 每个里程碑可以分批实现，但不得裁剪最终生产能力。

**仍需执行验证**：M0 必须先落代码生成器、字段消费 lint、SQL 访问 lint、状态更新 lint；否则六条铁律只停留在文字。

### 2.2 数据库与状态机专家

**结论**：40 张生产内核表 + 1 个 `v_current_text` 视图能够承载 M0-M6 生产闭环；v1.1 主编台/源文档产品化扩展新增 9 张表，总计 49 张生产表。

**已收敛点**：
- `writing_soft_gate_counters` 是 soft gate N 的唯一权威源，`writing_shots.soft_fail_counts_snapshot` 只做审计快照。
- `soft_sealed` 不回退到 `winner_selected`；`soft_gate_redo_n`（默认 2）翻盘只允许在 `winner_selected` 进入 `polish_revision` 之前完成。
- `v_current_text` 用 `ROW_NUMBER()` 保证每 shot 恰一行，并投影 `revision_id/source_revision_id` 支撑 stale 检测。
- `writing_chapter_reviews` 的 accepted canonical 唯一索引保证正式导出只认已接受版本。
- `writing_jury_aggregates`、`writing_chapter_reviews`、`writing_book_check_results`、`writing_human_decisions` 已具备 shot/chapter/book/human 四层硬质量阻断字段。

**仍需执行验证**：M0/M1 必须补 `PRAGMA foreign_key_check`、`v_current_text` 单行测试、状态转移矩阵测试、N=2 翻盘事务原子性测试。

### 2.3 产品与作者工作流专家

**结论**：作者闭环已补齐，不再是“能写一章”的局部工具。

**已收敛点**：
- CLI 契约覆盖 `init/setup/confirm-contract/write/review/revise/reject/accept/export/import/resume`。
- 人工动作全部落 `writing_human_decisions`，并保存前置条件与原因。
- 已有稿导入是正式流程：dry-run、source hash、低置信问题、人类裁决、finalize 原子落库。
- M6 验收要求至少 6 章全流程，覆盖 revise/reject/import/export/resume，而不是单章样例。

**仍需执行验证**：`accept/export/import finalize` 必须强制 human decision；没有 accepted canonical 的章节不得进入导出或后续正式上下文。

### 2.4 测试与可靠性专家

**结论**：测试策略已经从“迁移 557 个旧用例”改成“不变量追踪”，方向正确。

**已收敛点**：
- `invariant-traceability.md` 将旧 bugfix、架构决策和新生产能力映射到新测试/lint。
- 旧测试三桶分流：A 桶重写为新 invariant，B 桶不迁移旧架构绑定，C 桶转写端到端行为规约。
- AI 调用、LLM failure streak、checkpoint、runtime events 都有落库表和对应门禁。

**仍需执行验证**：每个 M0-M6 完成前必须确认对应 invariant 已接入 CI；不能只写测试占位。

### 2.5 实现落地专家

**结论**：实现顺序可执行，Pre-M0 先清掉开工阻断项，M0 再固化“禁止犯错的机制”，之后进入业务层，是当前风险最低的路径。

**已收敛点**：
- Pre-M0 先做 DDL 可执行性、jury 升级轮 schema、orchestrator 入口口径、resume SQL、字段消费 lint 边界和 schema smoke 测试。
- M0 再做 schema、代码生成、lint、CI、text_repository 隔离。
- M1 再做状态机、LLMGateway、retry budget、resume。
- M2-M6 依赖顺序清晰，最终以完整生产流验收。

**仍需执行验证**：CI 必须包含 schema smoke test、字段消费元测试、SQL lint 元测试、状态更新 lint、LLM access lint、pyright strict。

---

## 3. P0 结论

当前文档层面没有保留以下 P0 旧路线：

- 没有 MVP 阶段。
- 没有旧库共享。
- 没有双轨并行。
- 没有 3 表增量迁移。
- 没有“先局部可用，后续再补生产能力”的范围裁剪。

文档层面仍要求 Pre-M0/M0 阻断的 P0 项：

- DDL smoke test 必须稳定通过。
- `v_current_text` 必须每 shot 恰一行。
- `soft_gate_counters` 必须是唯一 N 权威源。
- winner 必须通过 quality floor，且必须经过 `polish_revision`。
- 盲评未通过、继续阅读未达标、productive_deviation 被 polish 磨平时不得 accepted/export。
- 文学体验评审、盲评排序、返工指导、polish 必须使用 smart 模型；不可用时阻断，不降级。
- 章级 7 维与篇级 blocking issue 必须硬阻断 accepted/export。
- human accept 不得 override 硬质量失败。
- `degraded` draft 不得进入 jury。
- 所有 AI 调用必须经 `LLMGateway` 并落库。
- 所有人工决策必须落 `writing_human_decisions`。
- 非 `text_repository` 不得直接访问 `writing_shot_revisions`。
- 非 `state_machine` 不得直接更新 `writing_shots.status`。

---

## 4. P1 优化项

这些不是推翻设计的理由，但必须在实现中落实：

- 对低频审计 FK 不机械建索引；只给关键 FK 与高频查询列显式索引，避免写放大。
- 裁判自评防线必须是配置层无交集校验 + 每 draft 动态排除 + 落库后 JOIN 审计；不能声称 DB 单表约束可完成。
- `chapter_reviews.rejected` 必须允许保留完整评分与拒绝理由，便于人工复核与审计。
- import finalize 必须校验 dry-run 后 source hash 未变化。
- checkpoint 恢复不得覆盖已 hard sealed 文本。
- 项目级质量标杆必须在 setup 时收集或生成；没有 `writing_projects` 质量阈值字段（`shot_quality_floor` 等）/ `style_quality_profile` 不得 confirm-contract。
- `quality_report_json` 必须采用统一 QualityReport schema，含 `evidence_class`、`defect_class`、盲评、继续阅读、productive_deviations 与 neutral_issues。
- `polish_revision` 必须证明 protected_roughness 仍可定位，不能只证明分数提升。
- **参数化原则落实**：所有运营阈值（熔断预算、soft gate 升级 N、drift 阈值、容量下限、自动重试策略）必须存入 `writing_projects` 表，运行时可调不改代码。DB CHECK 约束保留为绝对底线，应用层取 `max(项目阈值, 绝对底线)` 执行。详见 design-v2.md §0.4a。
- **自动重试机制（A'+A''）**：hard gate / quality floor 失败后，系统按 `retry_strategy` 自动重试，减少编辑工作量。编辑只在 `failed` 状态介入做项目级资源决策。详见 design-v2.md §0.4b。
- **quality_bar JSON 拆为独立字段**：原 `writing_meta_contracts.quality_bar` JSON 已拆为 `writing_projects` 表的 7 个独立字段（`shot_quality_floor`、`dimension_floor`、`chapter_quality_floor`、`book_quality_floor`、`judge_disagreement_max`、`reader_pull_floor`、`blind_review_min_passes`），支持 DB 层约束和索引。`writing_projects` 表级 CHECK 保证运营阈值不低于 DB 绝对底线。详见 implementation-contract-v1.md §2.1。
- **checkpoint 崩溃恢复幂等性设计**：`writing_session_checkpoints` 表增加 `payload_checksum`（SHA-256）字段，写入时原子写入 payload + checksum；恢复时先校验 checksum，损坏则回退到上一个有效 checkpoint；全部损坏则从头扫描 `shot_status` 恢复。`CHECKPOINT_CORRUPTED` 事件记录到 `writing_runtime_events`。详见 implementation-contract-v1.md §3.8。

---

## 5. 最终判定

以“完整生产、写作质量硬门禁、文学活力保护、可审计、可恢复、可测试、防旧病复发”为标准，当前设计是可执行的优化设计。下一步不是继续讨论 MVP 或旧系统迁移，而是按 `migration-plan.md` 先完成 Pre-M0 开工门禁，再进入 M0；每个里程碑都必须用 `invariant-traceability.md` 阻断未被测试证明的能力。
