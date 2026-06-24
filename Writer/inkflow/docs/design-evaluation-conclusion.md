# InkFlow 设计评估结论

> 评估日期：2026-06-16
> 最近复核：2026-06-24
> 评估范围：inkflow/docs/design.md、flow.md、role-system.md、module-v3.6.md、implementation-contract-v0.md
> 评估方法：四轮专家审阅（本地审计 + 4 + 3 + 3 + 3 位专家，共 13 人次）

## 核心结论

**经过四轮评估，InkFlow v3.6 的完整架构达到 near-optimal；2026-06-17 开发目标已收敛为 P0 单书纵向闭环。**

2026-06-24 复核结论：P0 纵向闭环、三棵树、正文真相源、D-25 部分能力和 L0 全书宪法已经落地，当前实现为 Schema v9 / 35 张业务表。设计仍不需要推倒重做；下一步最优路径是补齐 L0.5 Volume Rhythm 和 D-25 可靠性闭环，而不是继续增加孤立检查项。

第一轮（4 专家）：needs fix — 方向正确，工程规格未冻结。
第二轮（3 专家）：发现 30 跨文档不一致，确立 9 条人类决策。
第三轮（3 专家）：发现 46 问题，全部进入 tasks.md 并修复。
第四轮（3 专家）：near-optimal，10 项终审修复全部完成。

## 9 条人类决策

| # | 决策 | 来源 |
|---|------|------|
| 1 | 完整架构（Phase 1 保持完整，不做 MVP 切片） | 第一轮 |
| 2 | 完全无人（生产期不做人类中断点） | 第一轮 |
| 3 | Setup 必须多轮交互确认；关键创作缺项不得由 AI 擅自补完 | 2026-06-17 目标重校准 |
| 4 | 成本不作为开发和运行约束；只记录 usage，不设成本确认门 | 2026-06-17 目标重校准 |
| 5 | Phase 2 未来会做（表结构预留字段） | 第一轮 |
| 6 | 合并 3 组服务（16→13） | 第二轮 |
| 7 | 合并异常表；DDL 以 implementation-contract-v0.md 和 `src/inkflow/db/schema.sql` 的当前 Schema v9 为准 | 2026-06-24 复核 |
| 8 | 精简文档体系（design.md 唯一权威） | 第二轮 |
| 9 | InkFlow/Chesil 数据库独立，不共享 | 迁移 |

## 被正确否决的专家建议

| 专家 | 建议 | 否决理由 |
|------|------|---------|
| 产品专家 | Phase 1 MVP 切片（砍到 8 服务） | 16 服务强耦合，砍掉后半段无法验证 repair/红灯连续性 |
| LLM 专家 | Smart-Redo 成本硬封顶 | 硬上限变成另一种人类中断，与"完全无人"冲突 |

## 被采纳的专家建议

| 专家 | 建议 | 状态 |
|------|------|:---:|
| 架构专家 | 检查点独立存储路径 | ✅ |
| 架构专家 | 红灯占位上下文注入标记 | ✅ |
| 数据专家 | anchor_type 9 类枚举对齐 | ✅ |
| 数据专家 | pov_dependent → pov_scope TEXT | ✅ |
| LLM 专家 | Fact Anchor 置信度分层 | ✅ |
| LLM 专家 | Prompt Caching >4096 降级策略 | ✅ |

## 最终状态

- **implementation-contract-v0.md**：当前实现对齐版，DDL（35 张业务表，Schema v9）、状态机、idempotency_key、JSON 协议、并发控制、Caching 降级口径已记录；P0 以《分流》第 1 章导入、第 2 章生成为验收闭环
- **tasks.md**：10 条验收标准，7 个待编码时细化的议题（非阻塞）
- **文档卫生**：CLI 统一为 `ink`、L2 Opus 移除、编码修复、日期修正、旧表述替换全部完成
- **Phase 1 编码可以开工**

---

## 2026-06-18 P0 纵向闭环实现完成

**设计 near-optimal 的判断已被实现验证**：P0 全部 8 个阻塞项已修复，184 → 212 tests pass。

### 修复清单

| Bug | 修复 | 新增测试 |
|-----|------|---------|
| B13 | 新增 `ink confirm-contract` CLI 命令 | 4 |
| B14 | ModelClient 协议 + LocalDefaultGenerator | 7 |
| B15 | Jury 分制统一 0-100；score_override | 7 |
| B16 | 删除黄灯二次覆盖 | 1 |
| B17 | Fact Anchor 3 类提取 + prompt 注入 | 8 |
| P0-7 | 章完成最小 scope report | 1 |
| P0-8 | Chesil read-only 导入 InkFlow DB | 4 |

### 结论

P0 链路 `import-baseline → setup → confirm-contract → run → scope report → Chesil 导入` 全链路打通。
进入 P1 阶段：数据一致性（DB-1~7）、LLM 质量控制（LLM-1~6）、CLI E2E（CLI-1~5）、文档同步（DOC-2~4）。

---

## 2026-06-24 复审：当前是否为最优设计

结论：**near-optimal，但不是“所有层都已闭合”的最终设计。**

保持现设计的理由：

1. DB3 真相源 + `shot_revisions.text` 正文唯一真相源，已经解决“正文复制到多处导致漂移”的核心风险。
2. 三棵树把契约、故事状态、执行记录拆开，方向正确；后续 L0.5 不应再引入一套互相竞争的契约来源。
3. L0/L1/L2/L3 的分层治理能表达“约束下限 + 留白上限”，比单纯加 gate 更适合长篇文学生成。
4. D-25 悬疑引擎选择“Jury 第四维度 + 信息差生命周期”，避免新增独立 LLM extractor，成本和复杂度更可控。

当前非最优点：

| 问题 | 风险 | 处理 |
|------|------|------|
| L0.5 Volume Rhythm 未实现 | L0 全书宪法到 L1 章级节奏之间缺少战术层，长卷会让 chapter rhythm 过度局部化 | ARCH-5 列为下一编码优先级 |
| D-25 全局重试预算/熔断器未实现 | red/redo 策略可能在局部失败上消耗过多调用，失败原因不可聚合 | D25-R1 列为 P0 剩余可靠性任务 |
| Prompt caching 仍是 warning 级降级 | 长契约项目会失去缓存收益和上下文稳定性 | B23-P1 |
| 文档曾有版本/表数漂移 | 后续开发可能围绕旧口径实现 | 已同步并归档到 history |
