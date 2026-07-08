# InkFlow v2 当前任务队列

> **状态**：v1.1 主编台产品化全链路 + iFLYTEK 真实 LLM 接入 + 真实 6 章实跑链路打通。**当前重心：质量门真实化——jury 已真实化（阶段 A/B/C 完成），下一步 chapter_review + book_check 桩换真实 gateway.call（阶段 D）。**
> **最后更新**：2026-07-08

---

## 当前开发原则

- `tasks.md` 只保留未完成任务和下一步开发队列。
- 已完成里程碑、决策和验收证据移入 `history.md`。
- 开发中发现的缺陷、原因、修复和防回归测试记录到 `bugfix.md`。
- 默认本地验收命令：`cd ink && python -m pytest`。

---

## P0 当前任务：质量门真实化 + 模型角色主备兜底

> 设计 plan：`C:\Users\Administrator\.claude\plans\effervescent-pondering-puzzle.md`。用户硬要求：每个 `call_type` 的 LLM 角色都必须配「主/备/兜底」三模型，尽量跨供应商，独立模块管理；调用失败(provider 重试耗尽)才主→备→兜底逐个切，三都失败才判失败并提示调供应商/api-key。

- ~~**阶段 4 实跑验证真实 6 章生产**~~ ✅ 已完成（见 history.md 2026-07-08）。
- ~~**阶段 A 模型角色配置模块（主备兜底）**~~ ✅ 已完成（见 history.md 2026-07-08）。
- ~~**阶段 B gateway 接 failover（不污染熔断）**~~ ✅ 已完成（见 history.md 2026-07-08）。
- ~~**阶段 C jury 真实化 + LLM 失败分流**~~ ✅ 已完成（见 history.md 2026-07-08）。
- **阶段 D chapter_review + book_check 真实化**：桩换成真实 gateway.call，解析维度分 + issues，blocking 即拦 accept。当前 `chapter_review`/`book_check` 仍用桩评分，需对齐 jury 的真实化模式（3 tier failover + 维度解析 + 失败分流）。
- **阶段 E task_card 注入 book 层上下文**：loader 新增 `load_book_context` 查 `writing_meta_contracts` + `writing_atomic_source_clauses`（character/world confirmed），task_card 渲染注入 World/Character/Narrative/Motif 段喂 writer（修正：book 层无实体表，走 atomic clauses）。
- **阶段 F 实跑验证 + 文档对齐**：配跨供应商 role-config，真实跑 6 章验证；造 failover 验证主备切换 + 全失败抛「调供应商」；tasks→history 归档，bugfix 记桩评分 + 死代码缺陷。

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
2. ~~**6 章流水线真实模型跑通**~~ ✅ 已完成（`tests/test_e2e_real_models.py`:真实 iFLYTEK provider 驱动 outline/write/polish;避开太卡的 `xopglm52`,writer 池 `xopglm51`/`xopdeepseekv4pro`/`xopkimik26`;`smart-polish` 别名经 `LLMGateway` 正式路由(不再用测试侧 `_RemappingProvider`);provider 退避重试扛 iFLYTEK 429/503 限流(BFX-031);outline drift 阈值放宽至 0.02 适配真实模型(BFX-032);网关间歇错误/drift 全拒时优雅 skip;见 history.md 2026-07-08）
3. ~~**推理模型 max_tokens 适配**~~ ✅ 已完成（`_is_reasoning_model` 自动注入 max_tokens=2000；`content` 空时回退 `reasoning_content`；`--llm-max-tokens` / `INK_LLM_MAX_TOKENS` 全局覆盖）
4. ~~**DecisionSession 并发控制**~~ ✅ 已完成（scope 级 partial unique index + start 自动填 before_hash + confirm 冲突检测 + session 标 stale + 生产迁移脚本）
5. ~~**Stale 传播自动触发**~~ ✅ 已完成（`confirm_and_apply(stale_manager=...)` 在 SAVEPOINT 释放后自动调用；CLI `confirm-contract` 默认接入，`--no-auto-stale` 可关闭）
6. ~~**Coverage gate 可视化**~~ ✅ 已完成（`SourceWorkflowStore.list_coverage_gaps` + CLI `coverage-gaps` 子命令，返回 gap/conflict 字段明细 + 建议源条款）
7. ~~**`init` 命令支持自定义模型池**~~ ✅ 已完成（`--writer-models`/`--jury-models` 逗号分隔，去重保序，默认池兜底）

> 离线基线核对：`357 passed, 7 skipped`（2026-07-08，含 jury 真实化 + role-config failover + max_calls_per_shot 预算自调；7 skipped 为需 `IFLYTEK_API_KEY` 的联网集成测试）。

### P2 可扩展性

8. **PostgreSQL adapter 落地**：边界文档已就位（`docs/postgresql-rls-adapter-boundary.md`，见 history.md 2026-07-06 P2），剩余是实现 `DBAdapter` 接口并把 SQLite 测试在 PG 上跑通。
9. **Event log replay UI**：`EventLog.replay_session/replay_version` 已有（见 history.md Task #22），缺 replay UI 层，从 append-only event log 重建任意时刻的 session/contract 状态。
10. **Shot 级 coverage 追踪**：把 source clause 追踪粒度从 chapter 细化到 shot。
11. **Jury escalation 策略**：3 裁不一致时的升级机制（加裁判 / 加维度 / 人工裁决）。
12. ~~**`smart-polish` 模型别名正式路由**~~ ✅ 已完成（`LLMGateway.call` 从 `writing_projects.model_aliases` 懒加载别名映射,翻译别名调 provider、返回前 `dataclasses.replace` 还原别名保持 soft seal 契约;生产 CLI `init`/`setup` 写入 `model_aliases`;BFX-030 生产侧待办落实。drift 算法待办见 BFX-032）

### P3 产品化打磨

12. **CLI 交互式 TUI**：用 curses/textual 构建终端 UI，替代纯 JSON 输出。
13. **写作指南导入向导**：引导用户放置文件、自动推断 kind、预览抽取结果。
14. **契约 diff 可视化**：对比两个版本的 contract payload，高亮变更字段。
15. **批量 chapter review**：一次 review 多章，汇总报告。
