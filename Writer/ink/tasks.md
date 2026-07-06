# InkFlow v2 当前任务队列

> **状态**：当前生产内核开发队列已完成本地验证。新的主编台/DecisionSession 产品化交互设计已入文档，待进入下一批开发。
> **最后更新**：2026-07-06

---

## 当前开发原则

- `tasks.md` 只保留未完成任务和下一步开发队列。
- 已完成里程碑、决策和验收证据移入 `history.md`。
- 开发中发现的缺陷、原因、修复和防回归测试记录到 `bugfix.md`。
- 默认本地验收命令：`cd ink && python -m pytest`。

---

## P0 当前任务

- 当前无未完成 P0。

## P1 产品化任务

- **主编台交互层**：实现 `WorkflowConductor` 薄调度状态机，前台只暴露 InkFlow 主编台，后台调度 DecisionSession / ContractSteward / Gatekeeper / CanonicalKeeper / AuditLedger。
- **DecisionSession 持久化**：新增可恢复人类决策会话，支持 `collecting -> ai_parsed -> awaiting_confirm -> confirmed` 与 `needs_human/retryable_failed/stale/cancelled` 异常状态；恢复不得依赖聊天上下文。
- **自然语言到契约 patch**：AI 只能输出结构化 patch；程序负责 schema 校验、来源覆盖、冲突检查、回读确认、事务写库和写后审计。
- **ScopedDecisionSession**：支持 book / volume / part / chapter / shot 作用域修订，记录 affected scopes 和 stale downstream；已 accepted 正文必须走 revise run。
- **指南目录导入契约化**：实现 `SourceLibrarian` / `ImportCurator` 读取写作指南目录、计算 source hash、标记优先级、生成元契约/章契约/shot 契约草案和冲突清单。
- **防回归测试**：覆盖未确认 patch 不进 prompt、source hash 变化阻断确认、断点续接回读、同 target 单 active session、局部修订 stale 传播、AI 解析失败不污染生产契约。

## P2 后续架构增强

- **专家模式可展开审计**：默认隐藏后台角色，调试模式展示资料来源、契约版本、质检结果、审计记录。
- **强事件溯源评估**：评估是否将 DecisionSession、ContractPatch、ContractVersion 全量改为 append-only event stream。
- **交互式生成验收**：基于真实写作指南目录跑 6 章灰度生成，验证主编台交互负担、恢复点和局部修订链。
