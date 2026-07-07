# InkFlow v2 当前任务队列

> **状态**：v1.1 主编台产品化全链路 + 6 项架构增强 + iFLYTEK 真实 LLM 接入完成，全量 298 passed（含 4 联网集成测试）。
> **最后更新**：2026-07-07

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

- ~~**WorkflowConductor 薄调度状态机**~~ ✅ 已完成（见 history.md Task #15）
- ~~**DecisionSession 主编台集成**~~ ✅ 已完成（见 history.md Task #3）
- ~~**选择式对话 CLI/API**~~ ✅ 已完成（见 history.md Task #4）
- ~~**自然语言到契约 patch**~~ ✅ 已完成（见 history.md Task #9）
- ~~**ScopedDecisionSession**~~ ✅ 已完成（见 history.md Task #16）

### 2. 源文档规范化与覆盖

- ~~**源文档规范化算法**~~ ✅ 已完成（见 history.md Task #19）
- ~~**source coverage gate 集成**~~ ✅ 已完成（见 history.md Task #5）
- ~~**双模型抽取执行器**~~ ✅ 已完成（见 history.md Task #6）
- ~~**过程文件清空执行器**~~ ✅ 已完成（见 history.md Task #7）

### 3. 契约版本与 stale 传播

- ~~**契约字段投影集成**~~ ✅ 已完成（见 history.md Task #17）
- ~~**stale 传播实现**~~ ✅ 已完成（见 history.md Task #18）

### 4. 验收与防回归

- ~~**前 6 章生成验收**~~ ✅ 已完成（见 history.md Task #20）
- ~~**防回归测试**~~ ✅ 已完成（见 history.md Task #8）

## P2 架构增强（已完成）

- ~~**专家模式可展开审计**~~ ✅ 已完成（`DebugView` + CLI `debug` 子命令组；见 history.md Task #21）
- ~~**强事件溯源**~~ ✅ 已完成（append-only event log + 2 新表；见 history.md Task #22）
- ~~**接入真实 LLM Gateway**~~ ✅ 已完成（`LLMExtractionAdapter`；见 history.md Task #23）
- ~~**真实写作指南目录**~~ ✅ 已完成（+3 fixture 覆盖全部 source_kind；见 history.md Task #24）
- ~~**volume/part 层级精确化**~~ ✅ 已完成（volume_id/part_id 列 + 精确筛选；见 history.md Task #25）
- ~~**ShotContract 字段 schema 扩展**~~ ✅ 已完成（"shot" scope 5 子表投影；见 history.md Task #26）

---

## 下一步开发队列

### P1 主编台深化

1. ~~**真实 LLM 端到端集成测试**~~ ✅ 已完成（iFLYTEK 14 模型连通 + Gateway/抽取集成；见 history.md 2026-07-07）
2. **6 章流水线真实模型跑通**：用 iFLYTEK 标准模型池（`xopglm52`/`xopdeepseekv4pro`/`xopkimik26`）跑完整 6 章生成，验证抽取/回读/冲突检测在真实模型下的行为。
3. ~~**推理模型 max_tokens 适配**~~ ✅ 已完成（`_is_reasoning_model` 自动注入 max_tokens=2000；`content` 空时回退 `reasoning_content`；`--llm-max-tokens` / `INK_LLM_MAX_TOKENS` 全局覆盖）
4. **DecisionSession 并发控制**：多作者同时修订不同 scope 时的锁策略和冲突合并。
5. ~~**Stale 传播自动触发**~~ ✅ 已完成（`confirm_and_apply(stale_manager=...)` 在 SAVEPOINT 释放后自动调用；CLI `confirm-contract` 默认接入，`--no-auto-stale` 可关闭）
6. **Coverage gate 可视化**：CLI 输出未覆盖字段的明细和建议的 source clause。
7. ~~**`init` 命令支持自定义模型池**~~ ✅ 已完成（`--writer-models`/`--jury-models` 逗号分隔，去重保序，默认池兜底）

### P2 可扩展性

8. **PostgreSQL adapter 落地**：实现 `DBAdapter` 接口，将 SQLite 测试在 PG ��跑通。
9. **Event log replay UI**：从 append-only event log 重建任意时刻的 session/contract 状态。
10. **Shot 级 coverage 追踪**：把 source clause 追踪粒度从 chapter 细化到 shot。
11. **Jury escalation 策略**：3 裁不一致时的升级机制（加裁判 / 加维度 / 人工裁决）。

### P3 产品化打磨

12. **CLI 交互式 TUI**：用 curses/textual 构建终端 UI，替代纯 JSON 输出。
13. **写作指南导入向导**：引导用户放置文件、自动推断 kind、预览抽取结果。
14. **契约 diff 可视化**：对比两个版本的 contract payload，高亮变更字段。
15. **批量 chapter review**：一次 review 多章，汇总报告。
