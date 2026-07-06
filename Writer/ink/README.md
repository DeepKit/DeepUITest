# 墨韵 InkFlow v2 — 完整生产重构

> **状态**：Pre-M0-M6 baseline、P1 产品化队列、P2 架构增强队列已完成本地验证（2026-07-06）
> **目标**：从 0 构建完整生产版 InkFlow，根治旧系统“契约信号逐层丢失、门禁假放行、正文真相源绕过、崩溃恢复不可审计”的架构病。

## 这是什么

`ink/` 是与旧 `inkflow/` 同级的新系统目录。旧系统只作为领域知识库和回归不变量来源；新系统不共用旧 schema，不做双轨补丁，不做 3 表增量迁移。

本重构没有 MVP 阶段。每个里程碑都必须向完整生产功能收敛，最终交付必须覆盖：

- 从零建库的完整生产 schema
- 契约生成、章节写作、评审、人工审稿、修订、导出
- 已有稿导入与重构
- AI 调用审计、运行时事件、崩溃恢复、测试追踪矩阵
- shot/chapter/book 三层写作质量硬门禁，人工不可覆盖硬失败
- 质量证明门禁：盲评、继续阅读、ES/SEMI_ES/NES 证据分层、destructive/productive/neutral 缺陷分类
- polish_revision 粗糙度保护：只修毁灭性缺陷，不磨平有效留白、角色声线和 productive deviation
- 至少 6 章全流程生产验证

**病根诊断**：旧系统修了大量 bug 仍不稳定，根因不是局部代码质量，而是缺少“契约不可逃逸的单向传递链”。契约字段从 DB 到正文经多层隐式 dict / JSON / service 传递，任一层漏字段都可能不报错。

**重构策略**：保留旧系统中已经验证过的领域知识，例如角色体系、三棵树/8 层、悬疑引擎、封版规则、重试熔断、accepted canonical、历史 bugfix 的不变量；丢弃旧 schema、旧 CLI 编排和隐式传递链。

## 文档索引

| 文档 | 作用 | 读者 |
|------|------|------|
| [design-v2.md](docs/design-v2.md) | 新架构权威设计：六条铁律、完整生产线、存储模型、模块骨架 | 所有人先读 |
| [implementation-contract-v1.md](docs/implementation-contract-v1.md) | dataclass、40 张生产表 DDL、模块接口、状态机、CI 门禁 | 实现者 |
| [author-workflow-contract.md](docs/author-workflow-contract.md) | 作者可执行工作流：init/setup/write/review/revise/accept/export/import | 产品与 CLI 实现者 |
| [invariant-traceability.md](docs/invariant-traceability.md) | 旧 bugfix / 架构决策到新测试和门禁的追踪矩阵 | 测试与验收负责人 |
| [optimization-review.md](docs/optimization-review.md) | 5 个专家视角的优化设计评审结论、P0/P1 收敛项 | 架构与实现负责人 |
| [pitfall-checklist.md](docs/pitfall-checklist.md) | 必须保留的踩坑修复与新增防御清单 | 写 core/ 模块前必读 |
| [migration-plan.md](docs/migration-plan.md) | Pre-M0 + M0-M6 完整实现顺序、验证清单、生产验收标准 | 执行者 |
| [postgresql-rls-adapter-boundary.md](docs/postgresql-rls-adapter-boundary.md) | 未来 PostgreSQL/RLS 迁移的适配层边界、RLS/auth context、并发锁和 SQL 方言说明 | 架构与实现负责人 |
| [tasks.md](tasks.md) | 当前未完成任务队列 | 执行者 |
| [history.md](history.md) | 已完成任务归档与验收记录 | 执行者 |
| [bugfix.md](bugfix.md) | 开发期缺陷、根因、修复和防回归测试 | 执行者 |

## 核心决策

1. **从 0 构建完整生产版**：不沿用旧 56 表 schema，不共用旧 DB，不做双轨。
2. **DB 是唯一真相源**：编排步骤入口只收 `(shot_id, run_id)`，从 DB 重新加载所需投影。
3. **契约不可逃逸**：pydantic schema 生成 frozen dataclass、`unpack()`、字段消费 AST lint、`pyright --strict`。
4. **失败必须可见**：`degraded` 不进 jury；AI 调用、失败 streak、运行时事件、人工决策全部落库。
5. **正文真相源受控**：`writing_shot_revisions` 只经 `text_repository` 和 `v_current_text` 读取。
6. **高质量是硬门禁**：winner 必须过 quality floor + 盲评/继续阅读证明 + polish_revision；章级 7 维和篇级 blocking issue 阻断 accepted/export；human accept 不可 override。
7. **硬门禁保护文学活力**：质量报告必须区分 ES/SEMI_ES/NES 和 destructive/productive/neutral；productive deviation 与 protected_roughness 不得被 polish 自动磨平。
8. **完整作者闭环**：公开 CLI 覆盖 `init/setup/write/review/revise/reject/accept/export/import/resume`，人工决策有审计。
9. **完整功能一次设计**：不以 MVP 降低范围；可以分里程碑实现，但每个里程碑不得删除最终生产能力。
10. **参数化原则**：运营阈值（熔断预算、soft gate N、质量地板、drift 阈值、容量下限、自动重试策略）全部存入 `writing_projects` 表，运行时可调不改代码。DB CHECK 约束为绝对底线，应用层取 `max(项目阈值, 绝对底线)` 执行。
11. **自动重试减少编辑工作量**：hard gate / quality floor 失败后，系统按 `retry_strategy` 自动重试，编辑只在 `failed` 状态介入做项目级资源决策，不在 accept 路径上介入审美判断。
12. **生产内核优先**：M0/M1 先做实 schema、lint、状态机、LLMGateway、text_repository、resume，再用 1 章质量证明校准，之后扩展到 M2-M6。
13. **当前产品边界**：单作者本地生产工具；SQLite 先行但按 PostgreSQL 迁移预留；真实 LLM 不进默认 CI，只进手动或 nightly 验收。

## 里程碑

```
Pre-M0 开工门禁收口
→
M0 schema+codegen+lint+审计骨架
→ M1 core 状态机+会话+熔断+恢复
→ M2 contract+outline
→ M3 writers+deviant+AI gateway
→ M4 hard gates+jury
→ M5 soft gates+chapter review+human decisions
→ M6 import+book rolling check+export+6 章生产验收
```

## 不做什么

- 不把旧 `inkflow` schema 当迁移目标。
- 不做“只加几张表”的局部补丁。
- 不做双轨并行或章节 diff 切换。
- 不让 local fallback、未审稿正文、失败 AI 调用静默进入“通过”结果。
- 不用“MVP”缩小最终功能；只允许按依赖顺序分批实现完整生产设计。

## 当前验收

默认本地验收命令：

```bash
cd ink && python -m pytest
```

当前 CLI 覆盖 `init/setup/confirm-contract/write/review/revise/reject/accept/resume/import/export`，成功/错误输出使用统一 JSON envelope，常用写入命令支持 `--dry-run` 预检。真实 LLM provider 可通过 `--llm-provider openai-compatible` 接入；nightly/manual 验收可用 `ink-record-llm-acceptance` 记录成本、耗时、失败率和质量样例；`ink-replay-thresholds` 可离线回放质量阈值候选；`setup` 已支持项目元契约、章节节奏、shot 数量和核心风格约束输入。PostgreSQL/RLS 迁移边界、共享测试工厂和性能基线也已补齐。
