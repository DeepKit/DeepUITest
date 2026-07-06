# InkFlow v2 当前任务队列

> **状态**：v1.1 持久化基础层 + 主编台集成（选择式对话 CLI、双模型抽取、过程文件清空、source coverage gate、防回归测试）已完成，全量 139 passed。主编台产品化集成继续推进 WorkflowConductor 薄调度与 stale 传播。
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

### 1. 主编台调度与集成

- **WorkflowConductor 薄调度状态机**：前台只暴露 InkFlow 主编台，后台调度 DecisionSession / ContractSteward / Gatekeeper / CanonicalKeeper / AuditLedger。
- ~~**DecisionSession 主编台集成**：把 `DecisionSessionStore` 接入 `confirm-contract`、导入裁决和后续主编台入口；confirmed 时原子写 human decision、contract changelog、contract version。~~ ✅ 已完成（`confirm_and_apply` 原子审计链 + coverage gate 阻断 + CLI `--decision-session-id`；见 history.md Task #3）
- ~~**选择式对话 CLI/API**：把 1-8 编号选项、`0` 返回、`9` 重新生成接入用户可调用命令，并支持恢复展示原 option set。~~ ✅ 已完成（`decision-session start/parse/options/select/show/regenerate` CLI + 活跃 option set 回放；见 history.md Task #4）
- **自然语言到契约 patch**：AI 只能输出结构化 patch；程序负责 schema 校验、来源覆盖、冲突检查、回读确认、事务写库和写后审计。
- **ScopedDecisionSession**：支持 book / volume / part / chapter / shot 作用域修订，记录 affected scopes 和 stale downstream；已 accepted 正文必须走 revise run。

### 2. 源文档规范化与覆盖

- **源文档规范化算法**：实现 `SourceLibrarian` / `SourceNormalizer` / `ImportCurator` 读取写作指南目录、计算 source hash、合并去重、拆矛盾、原子化 source clauses，并生成冲突/遗漏选择题。（存储层 `SourceWorkflowStore` 已落，需实现读取/合并/去重/原子化算法和选择题生成逻辑。）
- ~~**source coverage gate 集成**：把原子条款 × contract field 覆盖矩阵接入契约确认；blocking gap 未解决时阻断 BookContract/局部契约确认。~~ ✅ 已完成（`confirm-contract` 默认接入 `SourceWorkflowStore` gate + `--skip-coverage-gate` 逃生阀；见 history.md Task #5）
- ~~**双模型抽取执行器**：接入 `LLMGateway` 执行 primary/crosscheck 抽取，对不一致、漏抽、冲突和低置信项生成 coverage gap/conflict。~~ ✅ 已完成（`SourceExtractionOrchestrator` + 同位置文本差异 conflict + low_confidence_refs；见 history.md Task #6）
- ~~**过程文件清空执行器**：将 `better.md` 作为 `process_scratch` 输入；抽取并合并完成后清空文件，写 processed manifest，禁止后续 prompt/contract 直接引用已处理过程文件。~~ ✅ 已完成（`ProcessFileClearingOrchestrator` + `is_process_file_cleared` 引用阻断；见 history.md Task #7）

### 3. 契约版本与 stale 传播

- **契约字段投影集成**：将 BookContract / VolumeContract / PartContract / ChapterContract / ShotContract 字段投影接入 contract versions、contract patches 和 source clause 追踪。
- **stale 传播实现**：契约或 source hash 变化后，按 book/volume/part/chapter/shot 层级标记下游 prompt、draft、review、book check stale；已 accepted 正文只允许 revise run。

### 4. 验收与防回归

- **前 6 章生成验收**：先封 `BookContract` 全书基线，再基于真实写作指南目录跑前 6 章灰度生成，验证交互负担、恢复点、契约抽取和质量门禁。
- ~~**防回归测试**：覆盖未确认 patch 不进 prompt、source hash 变化阻断确认、断点续接回读、局部修订 stale 传播、AI 解析失败不污染生产契约、`better.md` 清空后不再被直接引用。~~ ✅ 已完成（3 个跨模块集成防回归测试 + 10 CLI + 4 抽取 + 4 清空；见 history.md Task #8）

## P2 后续架构增强

- **专家模式可展开审计**：默认隐藏后台角色，调试模式展示资料来源、契约版本、质检结果、审计记录。
- **强事件溯源评估**：评估是否将 DecisionSession、ContractPatch、ContractVersion 全量改为 append-only event stream。
