# Ink v2 开发文档权威索引

> 状态：Scene-first 开发基线
> 日期：2026-07-14
> 当前工程：`ink/`
> 历史工程：`inkflow/`，只作领域知识和回归参考

## 1. 文档分类

| 类型 | 文档 | 权威范围 |
|---|---|---|
| Normative | `scene-first-authority-amendment.md` | 作者裁定、正文原子、候选与封版原则 |
| Normative | `design.md` | Scene-first 总体技术设计 |
| Normative | `implementation-contract.md` | DDL、状态机、事务、接口与权限 |
| Normative | `author-workflow-contract.md` | 作者可执行生产流程 |
| Normative | `interactive-contract-workflow.md` | 主编台、契约架构师与复审师 |
| Migration | `migration-plan.md` | Shot 中心生产库到 Scene-first 的安全切换 |
| Verification | `invariant-traceability.md` | P0/P1 不变量与测试门禁 |
| Verification | `pitfall-checklist.md` | 必须防止复发的架构病 |
| Operations | `personal-production-runbook.md` | 当前迁移期和切换后的操作规范 |
| Infrastructure | `postgresql-rls-adapter-boundary.md` | SQLite/PostgreSQL 并发与权限边界 |
| Infrastructure | `iflytek-model-config.md` | 模型配置；不得包含真实凭据 |

## 2. 权威矩阵

| 主题 | 当前实现事实 | 目标设计 | 迁移法源 |
|---|---|---|---|
| 正文存储 | Scene-first 正式库已重建（2026-07-17，见下注），legacy Shot 库已归档只读 | Scene Revision | `migration-plan.md` |
| 正式章节 | Chapter Snapshot/Head 表已落地并接入；等待③重产填充首条数据 | Chapter Snapshot + Chapter Head | Snapshot backfill/cutover |
| 契约 | 旧 Shot 五表 | Scene Contract 四层 | 条款映射表 |
| 候选 | 逐 Shot 候选 | 完整 Chapter Candidate Branch | 影子生成与导出对比 |
| 状态机 | 旧 Shot 状态机 | Scene/Generation Round/Snapshot 状态机 | 写入冻结与一次切换 |
| 导出 | 旧 `v_current_text` 路径 | active Chapter Snapshot | 导出 hash parity |

## 3. 强制解释规则

1. Scene 是最小正式正文原子。
2. Shot 只表示 Scene 内部工作切片；出现 `shot` 不等于正式权威。
3. Scene Revision 不可变；候选分支和 Chapter Snapshot 冻结后不可变。
4. “通过 Scene 门”不等于 canonical；只有 accepted Chapter Snapshot 是正式稿。
5. 生产期不得同时存在 Shot 和 Scene 两个正文真相源。
6. `docs/归档/` 中的文档不得被新实现引用为规范。

## 4. 归档

旧 Shot 中心文档已移至：

`docs/归档/shot-centered-v2-2026-07-14/`

归档只用于：

- 理解现有代码；
- 回归历史不变量；
- 迁移旧数据库；
- 追溯旧决策。

归档不得用于新增功能设计或作为 accepted/export 的目标规范。

> **2026-07-17 库重建注记**：正式库 `baideng_prod.db` 已从 legacy 全新建库替换
> （`rebuild_prod_db.py --apply --force`，自动备份 legacy 为 `.bak`）。新库带齐 8 张
> 新表（stale_marks 三表 + gate 证据/fact 绑定/repair/schema_migrations），排除
> BFX-093 游离表 `writing_schema_authority`。迁移机制为统一 `migrate_db` 按
> `sql/migrations/` 文件名序幂等应用 + `schema_migrations` 注册表（BFX-092）。
> 详见 `migration-plan.md` 与 `history.md` 黄金闭环②段。
