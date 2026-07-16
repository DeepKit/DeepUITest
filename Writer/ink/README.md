# Ink v2 — Scene-first 小说生产系统

> 当前工程：`ink/`
> 目标架构：Scene-first
> 当前状态：Shot 中心代码迁移中，Scene-first 尚未宣称投产

## 核心权威

1. 数据库是正式事实、契约、正文、评审和决策的唯一真相源。
2. Scene 是最小正式生成、修改、评审、版本和返工单位。
3. Shot 只作为 Scene 内部非权威工作切片。
4. 完整 Chapter Candidate Branch 是文学选优单位。
5. Chapter Snapshot 是正式章节和导出权威。
6. AI 只能创建候选 Revision，不能原地改稿、激活或 Accept。

## 文档

从 `docs/README.md` 开始阅读。

| 文档 | 作用 |
|---|---|
| `docs/scene-first-authority-amendment.md` | 作者裁定与最高原则 |
| `docs/design.md` | Scene-first 总体设计 |
| `docs/implementation-contract.md` | DDL、状态机、事务与权限 |
| `docs/author-workflow-contract.md` | 作者工作流 |
| `docs/interactive-contract-workflow.md` | 主编台和契约双师 |
| `docs/migration-plan.md` | Shot→Scene 安全迁移 |
| `docs/invariant-traceability.md` | 不变量与测试门禁 |
| `docs/pitfall-checklist.md` | 防复发清单 |
| `docs/personal-production-runbook.md` | 个人生产与切换 |
| `docs/postgresql-rls-adapter-boundary.md` | 并发和权限边界 |
| `tasks.md` | 未完成任务 |
| `history.md` | 已完成记录 |
| `bugfix.md` | 缺陷和防回归 |

旧 Shot 中心开发文档位于：

`docs/归档/shot-centered-v2-2026-07-14/`

归档不再是新增实现的规范来源。

## 开发原则

- 新功能不得继续扩展 Shot canonical 路径；
- Scene-first实现必须先有DDL、不变量和测试；
- 影子回填不等于双权威；
- Accept和Export切换必须原子完成；
- 真实模型质量证据不由mock替代；
- 不在文档、代码、测试或日志中保存真实密钥。

## 当前测试

```powershell
cd D:\_Progs\02Business\Writer\ink
python -m pytest -q
```

Scene-first新测试完成前，旧测试通过只表示历史Shot实现未回归，不表示新架构已经完成。
