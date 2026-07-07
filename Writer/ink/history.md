# InkFlow v2 历史任务归档

> **用途**：记录已经完成并验证的任务，保持 `tasks.md` 只呈现当前待办。
> **最后更新**：2026-07-07

---

## 2026-07-07 接入 iFLYTEK Coding Plan 真实 LLM

**里程碑**：InkFlow 首次跑通真实 LLM provider，14 个讯飞模型全部可达。

新增：
- `tests/test_iflytek_integration.py`（5 测试：连通性 + Gateway + 子句抽取；无 `IFLYTEK_API_KEY` 时 skip）
- `docs/iflytek-model-config.md`（模型分类、推荐池配置、已知限制）
- `.env.iflytek.example`（环境变量模板）

验证结论：
- 端点 `https://maas-coding-api.cn-huabei-1.xf-yun.com/v2`，鉴权用整串 `appId:apiKey` 作 Bearer token
- 14/14 模型可达：11 标准模型直接产 content，3 推理模型（MiniMax-M2.5 / Spark-X2 / Spark-X2-Flash）需 `max_tokens≥500`
- `OpenAICompatibleProvider` + `LLMGateway.call()` + `LLMExtractionAdapter` 全链路通过
- 全量 298 测试（295 离线 + 4 联网通过 + 1 联网 skip）

修复：
- `tests/test_debug_view.py::TestStaleChain` fixture 重复插入 project_id=1 导致 UNIQUE 冲突，移除冗余 `_insert_project` 调用

验证命令：

```bash
# 离线全量
cd ink && python -m pytest -p no:rtk --ignore=tests/test_iflytek_integration.py
# 联网集成（需真实 API key）
set IFLYTEK_API_KEY=<appId:apiKey整串>
cd ink && python -m pytest tests/test_iflytek_integration.py -v -p no:rtk
```

---

## 2026-07-06 完成 6 项架构增强（Task #21-#26）

验证命令：

```bash
cd ink && python -m compileall -q src tests
cd ink && python -m pytest tests/ -o "addopts="
```

最近一次验收结果：

- 全量测试：`295 passed`（257 基线 + 38 新增）
- Schema：51 tables, 62 indexes, 2 triggers, 1 view

### 已完成：Task #21 专家模式可展开审计

- `src/ink/debug_view.py`：实现 `DebugView` 类和 4 个审计视图 dataclass（`SessionAudit` / `ContractTimelineEntry` / `ShotTrace` / `StaleChain`）。
- 4 个查询方法：
  - `show_session_audit(session_id)`：聚合 session 事件 + patches + contract versions。
  - `show_contract_timeline(project_id, scope_type, scope_id)`：聚合版本事件 + session 事件为时间线。
  - `show_shot_full_trace(shot_id)`：追踪 shot 的 prompt → draft → review → runtime events。
  - `show_stale_chain(project_id)`：查询所有 stale 标记的传播链。
- CLI `debug` 子命令组：`audit` / `timeline` / `trace` / `stale`，handler 输出 JSON envelope。
- 测试：`tests/test_debug_view.py` +6（session audit、contract timeline、shot trace、stale chain）。

### 已完成：Task #22 强事件溯源（轻量 append-only event log）

- `sql/schema.sql` 新增 2 张表：
  - `writing_decision_session_events`：session 级事件（created/ai_parsed/option_set_created/option_selected/confirmed/cancelled/stale）。
  - `writing_contract_version_events`：版本级事件（created/confirmed/locked/superseded/stale）。
- `src/ink/event_log.py`：实现 `EventLog` 类，提供 `log_session_event` / `log_version_event` / `replay_session` / `replay_version` / `latest_session_event` / `count_*` 方法。
- `src/ink/decision_sessions.py` 集成：在 `start()` / `record_ai_parse()` / `create_option_set()` / `select_option()` / `confirm_and_apply()` 中追加 event log 写入（不改现有 UPDATE 逻辑）。
- 修复 `_load_session_for_confirm` 缺少 `scope_type` / `scope_id` 列，导致 `confirm_and_apply` KeyError。
- 测试：`tests/test_event_log.py` +13（session events、version events、validation、counts）。

### 已完成：Task #23 接入真实 LLM Gateway

- `src/ink/source_normalizer.py` 新增 `LLMExtractionAdapter`：
  - 接收 `LLMGateway`，构造抽取 prompt，解析 LLM 返回的 JSON 数组。
  - 支持 markdown 代码块剥离、回退 JSON 数组提取、字段规范化。
  - `__call__(content, filename)` 签名兼容 `SourceNormalizer.extraction_fn`。
- `sql/schema.sql`：`writing_ai_call_attempts.call_type` CHECK 新增 `'source_extraction'`。
- 测试：`tests/test_llm_integration.py` +8（响应解析、markdown 剥离、gateway 调用、集成到 SourceNormalizer）。
- Fixture：`tests/fixtures/llm_extraction_response.json`。

### 已完成：Task #24 真实写作指南目录

- 新增 3 个 fixture 文件，覆盖全部 source_kind：
  - `tests/fixtures/sample_guides/world_setting.md`（world kind）
  - `tests/fixtures/sample_guides/process_scratch.md`（process_scratch kind）
  - `tests/fixtures/sample_guides/style_reference.txt`（other kind）
- 目录现在 6 个文件，覆盖 guide/outline/character/world/process_scratch/other 全部 6 种 source_kind。
- E2E 测试 `registered_source_ids >= 2` 断言仍通过。

### 已完成：Task #25 volume/part 层级精确化

- `sql/schema.sql`：
  - `writing_shots` 新增 `volume_id TEXT` / `part_id TEXT` 列。
  - `writing_chapter_specs` 新增 `volume_id TEXT` / `part_id TEXT` 列。
  - 新增索引 `idx_shots_volume` / `idx_shots_part`。
- `src/ink/stale_propagation.py`：
  - 新增 `_find_chapters_in_volume()` / `_find_chapters_in_part()`：精确查询 `writing_shots.volume_id/part_id`。
  - 新增 `_mark_prompts_for_chapters()` / `_mark_drafts_for_chapters()` / `_mark_reviews_for_chapters()`（plural）：遍历多章调用单章标记方法。
  - volume/part scope 不再退化为全部，按 volume_id/part_id 精确筛选。
- 测试：`tests/test_stale_propagation.py` 更新 volume/part 测试（精确筛选 + 无匹配返回空 + book_check 全书级标记）。

### 已完成：Task #26 ShotContract 字段 schema 扩展

- `src/ink/contract/fields.py`：
  - `CONTRACT_FIELD_SCHEMAS` 新增 `"shot"` 键，对齐 5 张结构化子表：
    - `must_land`：events / beats / information_releases
    - `anti_write`：forbidden_facts / forbidden_words / pov_only
    - `scene_contract`：location / time_of_day / characters_present / character_positions
    - `persona`：persona / intensity / is_creative_shot / is_suspense_shot
    - `soft_constraints`：relaxable_rules / deviation_budget
  - 更新模块文档。
- 测试：`tests/test_contract_field_projection.py` +9（5 子表路径校验、payload 校验、未知字段拒绝）。

### 关键成果

- **全量测试**：295 passed（257 基线 + 38 新增）
- **Schema 扩展**：49 → 51 表，58 → 62 索引
- **6 项架构增强全部完成**：事件溯源、专家审计、LLM Gateway、volume/part 精确化、Shot 字段、真实指南目录

## 2026-07-06 完成 P1 DecisionSession/source coverage 持久化基础层

验证命令：

```bash
cd ink && python -m pytest tests/test_schema_contract.py tests/test_decision_source_workflow.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- Decision/source workflow 定向测试：`13 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`119 passed`

### 已完成：v1.1 持久化边界

- 扩展 `sql/schema.sql` 到 49 张生产表，新增 source documents、atomic source clauses、source extraction runs、DecisionSession、option sets、contract versions、contract patches、source coverage matrix、process file manifests。
- 新增 `DecisionSessionStore`，支持同 target 单 active session、AI parsed、awaiting_confirm、1-8 选择、`0` 返回、`9` 重生成 option set、confirmed 终态。
- 新增 `SourceWorkflowStore`，支持源文档注册、原子条款、primary/crosscheck 抽取 run、coverage gap/conflict、coverage resolve、`better.md` 清空后 process manifest。
- 更新 schema 契约测试到 49 表 / 58 索引，并补 v1.1 表存在性测试。
- 新增 `tests/test_decision_source_workflow.py`，覆盖 active session 唯一性、option set 恢复语义、coverage gate 阻断与解除、process manifest 不保存过程文件正文/摘要。

## 2026-07-06 完成 source coverage 战略决策归档

验证命令：

```bash
docs-only change; no runtime tests required
```

### 已完成：覆盖率与抽取完整性口径定版

- 将 source coverage 粒度定为“原子条款 × contract field”矩阵；必填字段没有 confirmed clause 或人工空值理由时，coverage gate 阻断契约确认。
- 将 AI 抽取完整性定为 primary/crosscheck 双模型交叉抽取；不一致、漏抽、冲突和低置信项进入 coverage gap/conflict。
- 将 `better.md` 清空后的 manifest 定为只记录 hash、处理时间、抽取条款 ID、contract patch ID 和 DecisionSession ID，不保留过程文件正文或摘要。
- 更新 `docs/interactive-contract-workflow.md`、`docs/implementation-contract-v1.md`、`docs/author-workflow-contract.md`、`docs/design-v2.md`、`README.md` 和 `tasks.md`，把上述口径从讨论项改为开发约束。

## 2026-07-06 完成源文档规范化与选择式对话文档化

验证命令：

```bash
docs-only change; no runtime tests required
```

### 已完成：主编台细则收敛

- 更新 `docs/interactive-contract-workflow.md`，定义 `better.md` 过程文件生命周期、源文档合并/去重/原子化、1-8/0/9 选择式对话、契约字段标准和 stale 传播矩阵。
- 更新 `docs/implementation-contract-v1.md`，补充 v1.1 专表原则、DecisionSession option set、source documents、atomic clauses、contract versions、contract patches 的 schema revision 草案。
- 更新 `docs/author-workflow-contract.md`，把选择式对话、过程文件清空处理、先封全书基线再跑前 6 章灰度生成纳入用户侧流程。
- 更新 `docs/design-v2.md` 与 `README.md`，把 SourceNormalizer、过程文件不作真相源、选择式对话和层级契约字段边界纳入权威设计摘要。
- 更新 `tasks.md`，将下一批开发队列收敛为 DecisionSession 专表、选择式对话引擎、源文档规范化、过程文件处理、字段 schema revision、stale 传播和前 6 章生成验收。

## 2026-07-06 完成主编台交互机制文档化

验证命令：

```bash
docs-only change; no runtime tests required
```

### 已完成：产品化交互设计归档

- 新增 `docs/interactive-contract-workflow.md`，定义 InkFlow 主编台、前台/后台角色边界、DecisionSession、ScopedDecisionSession、AI 到程序的防卡约束和验收口径。
- 更新 `README.md` 文档索引和核心原则，明确未确认意见不得进入 prompt 或 accepted canonical。
- 更新 `docs/design-v2.md`，将主编台/后台生产角色纳入角色体系，将全书基线封板与局部作用域修订纳入契约系统。
- 更新 `docs/author-workflow-contract.md`，定义自然语言交互标准回合、断点恢复、全书基线封板和局部修订。
- 更新 `docs/implementation-contract-v1.md`，记录 v1.1 产品化扩展接口与状态机边界，不混入当前 40 表基线。

## 2026-07-06 完成非 shot 级 resume baseline

验证命令：

```bash
cd ink && python -m pytest tests/test_resume_handler_registry.py tests/test_m1_core_mechanisms.py tests/test_m6_import.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- 定向恢复测试：`21 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`99 passed`

### 已完成：P0 非 shot 恢复调度

- 实现非 shot 级 resume handler registry，覆盖 `chapter_review`、`book_check`、`import_finalize` 的结构化恢复调度。
- 扩展 `ResumeManager`，支持 `import_finalize` phase、JSON 对象校验、通用 `execute_resume_point()` dispatch。
- 扩展 CLI `resume`：先保持原 shot 级恢复循环，再执行 `writing_sessions.resume_point` 中的 session 级恢复点，成功后清空 `crashed/resume_point`。
- 将 `ImportOrchestrator.finalize()` 做成幂等恢复：同一 `import_run_id` 已有 finalize 决策时返回既有结果，不重复写 human decision。
- 补充防回归测试：chapter review 重跑、book check 重跑、import finalize 重跑、非法 payload 阻断、CLI session resume 执行与清空。

## 2026-07-06 完成 P1 真实 LLM provider 配置入口

验证命令：

```bash
cd ink && python -m pytest tests/test_m0_core_contracts.py tests/test_cli.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- Provider/CLI 定向测试：`11 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`101 passed`

### 已完成：P1 provider 配置入口

- 增加 `LLMProviderConfig`、`load_llm_provider_config()`、`build_model_provider()`，默认配置仍为 `mock`。
- 增加 `OpenAICompatibleProvider`，使用标准库 HTTP 调用 `/chat/completions`，不引入真实 provider SDK 依赖。
- 扩展 `LLMGateway`，支持记录实际 `model_provider`，默认构造仍走 mock provider。
- 扩展 CLI 全局参数：`--llm-provider`、`--llm-base-url`、`--llm-api-key-env`、`--llm-timeout`；CLI 默认仍为 deterministic provider，避免默认测试触发真实网络。
- 补 fake HTTP provider 测试，验证请求体、鉴权头、idempotency key、token usage 和审计记录。

## 2026-07-06 完成 P1 nightly/manual LLM 验收记录

验证命令：

```bash
cd ink && python -m pytest tests/test_manual_acceptance.py tests/test_m0_core_contracts.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- Manual acceptance 定向测试：`12 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`104 passed`

### 已完成：P1 manual LLM 验收记录

- `LLMGateway` 写入 `writing_ai_call_attempts.latency_ms`，补齐已有审计字段。
- 新增 `ink.manual_acceptance.build_llm_acceptance_record()`，聚合真实或 mock LLM 调用的尝试数、成功数、失败率、token、估算成本、平均耗时和 p95 耗时。
- 新增质量证明样例采集，从 accept human decision 中抽取 `quality_report_json` 与前置条件。
- 新增 JSONL 追加入口 `append_jsonl_record()`。
- 新增 console script `ink-record-llm-acceptance`，用于 nightly/manual 汇总指定 DB 并追加记录；默认测试只验证 mock/失败调用和记录格式，不触发真实网络。

## 2026-07-06 完成 P1 参数化 setup

验证命令：

```bash
cd ink && python -m pytest tests/test_cli.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- CLI 定向测试：`3 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`105 passed`

### 已完成：P1 setup 输入增强

- `ink setup` 增加 `--shots-per-chapter`，支持每章生成多个结构化 shot。
- `ink setup` 增加 meta contract JSON 参数，覆盖 identity、narrative voice、hard boundaries、style locks、world knowledge、motif system、creative zones 和 style quality profile。
- `ink setup` 增加章节规格参数：`--rhythm-json`、`--hook-target`、`--motif-density`。
- `ink setup` 增加 shot 契约参数：must-land events、beats、information releases、forbidden facts/words、POV、scene、characters、persona intensity、creative shot、relaxable rules 和 deviation budget。
- 保持默认 setup 兼容旧 CLI 流程；补多 shot 和作者输入落库测试。

## 2026-07-06 完成 P1 CLI 易用性

验证命令：

```bash
cd ink && python -m pytest tests/test_cli.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- CLI 定向测试：`5 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`107 passed`

### 已完成：P1 CLI JSON / dry-run

- CLI 成功输出统一为 `{"ok": true, "command": "...", "data": ...}`。
- CLI handler 错误统一输出 JSON error envelope 到 stderr，并返回非 0 状态。
- `setup/write/review/accept/revise/reject/resume/export/confirm-contract` 增加 `--dry-run` 预检；`import --dry-run` 保留原导入清单语义。
- dry-run 预检不会提交 DB 写入；补 setup dry-run 不落库测试。
- 补错误 JSON 测试，避免重新退回裸异常输出。

## 2026-07-06 完成 P1 阈值调参回放记录

验证命令：

```bash
cd ink && python -m pytest tests/test_threshold_replay.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- 阈值回放定向测试：`2 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`109 passed`

### 已完成：P1 threshold replay

- 新增 `ink.threshold_replay.build_threshold_replay_record()`，离线读取 DB 并生成阈值候选回放记录。
- 回放覆盖 shot quality floor、dimension floor、chapter quality floor、book quality floor、reader pull、blind review pass count、soft gate redo/fail N。
- 新增 `ink-replay-thresholds` console script，支持将回放结果追加到 JSONL。
- 回放只读业务表，不修改项目阈值和生产数据。
- 补阈值回放记录和命令入口测试。

## 2026-07-06 完成 P2 PostgreSQL/RLS 适配边界

验证命令：

```bash
cd ink && python -m pytest tests/test_postgres_rls_boundary.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- PostgreSQL/RLS 边界定向测试：`2 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`111 passed`

### 已完成：P2 DB adapter boundary

- 新增 `docs/postgresql-rls-adapter-boundary.md`，明确当前 SQLite 权威边界、未来 adapter contract、RLS/auth context、并发锁和 SQL 方言迁移边界。
- 补文档关键词测试，防止 RLS/advisory lock/SQL 方言边界说明丢失。
- 补最小兼容测试：`connect()` 返回 mapping-style row，`transaction()` 正常提交、异常回滚。

## 2026-07-06 完成 P2 共享测试工厂

验证命令：

```bash
cd ink && python -m pytest tests/test_schema_contract.py tests/test_m1_core_mechanisms.py tests/test_threshold_replay.py tests/test_manual_acceptance.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- 工厂迁移定向测试：`23 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`111 passed`

### 已完成：P2 test factories

- 新增 `tests/factories.py`，集中 `NOW`、`SCORE_COLUMNS`、`make_schema_db()`、`insert_minimal_draft()`、`insert_raw_score()`。
- 将测试文件从 `test_schema_contract` helper 导入迁移到共享工厂。
- `test_schema_contract.py` 收缩为 schema 契约测试，不再承载跨文件 fixture/builder 实现。

## 2026-07-06 完成 P2 性能基线

验证命令：

```bash
cd ink && python -m pytest tests/test_performance_baselines.py
python -m compileall -q src tests
python -m pytest
```

最近一次验收结果：

- 性能基线定向测试：`3 passed`
- `python -m compileall -q src tests`：通过
- `python -m pytest`：`114 passed`

### 已完成：P2 performance baselines

- 新增 mock/deterministic 性能基线测试。
- 覆盖单 shot pipeline、6 章 workflow smoke、CLI 一章流程。
- 阈值设置为宽松上限，用于发现明显性能退化，不触发真实 LLM 或网络。

## 2026-07-05 完成本地 baseline 验收

验证命令：

```bash
cd ink && python -m pytest
python -m compileall -q src tests
```

最近一次验收结果：

- `python -m pytest`：`93 passed`
- `python -m compileall -q src tests`：通过

### 已完成：Pre-M0 开工门禁

- 建立新源码骨架：`ink/src/ink/`、`ink/tests/`、`ink/sql/`、基础 `pyproject.toml`。
- 从 `implementation-contract-v1.md` 抽取正式 `schema.sql` 到版本控制。
- 添加 `test_schema_executes_all_ddl`，验证 40 张生产表、索引、触发器、视图可在内存 SQLite 执行。
- 添加 schema 元测试：禁止旧 jury role 唯一约束、禁止 runtime event 旧时间字段、禁止从 shot 表按 session 直查。
- 添加 jury round、自评阻断、orchestrator 入口签名、字段消费 lint、resume SQL 契约测试。
- 统一 Pre-M0 开工策略：Pre-M0 未完成不进入 M0。

### 已完成：M0 基础设施

- 落地 40 张生产表、`v_current_text`、jury 自评 trigger、索引和 FK。
- 实现 DB 连接与 schema 初始化入口，默认开启 `PRAGMA foreign_keys=ON`。
- 实现 UTC ISO 时间源 `now_utc_iso()`。
- 实现 schema/dataclass 代码生成器和生成 DTO。
- 实现 `ProjectConfigValidator`、`TextRepository`、状态机入口、`LLMGateway`。
- 接入字段消费 lint、SQL 访问 lint、状态更新 lint、LLM 访问 lint。
- 建立 `invariant-traceability.md` 到测试文件的追踪检查。

### 已完成：M1 核心机制

- 实现 14 态状态机、终态阻断、CAS stale 更新阻断。
- 实现 `SoftGateCounter`、`LLMCallBudget`、`ResumeManager`、`CheckpointManager`。
- 接入 M2-M4 shot 级 resume handlers。
- 实现 LLM 调用预算与 `LLMGateway.call()` 集成。

### 已完成：M2 contract + outline baseline

- 扩展契约 DTO 生成器覆盖 MetaContract / ShotContract / OutlineSpec / TaskCard / PromptSpec / DraftSpec / JuryInput。
- 实现 `load_shot_contract(conn, shot_id, run_id)`，从 DB reload 完整投影。
- 实现 task card 半句拒绝、supersede、prompt snapshot 二次编译。
- 实现 CJK bigram drift 检测、outline 候选落库、winner 唯一。
- 将 outline/task/prompt 接入 `PreDraftingOrchestrator` 与 resume。

### 已完成：M3 writer baseline

- 实现模型池读取和候选模型轮换。
- 实现同 persona + 同 prompt + 换模型产稿。
- 实现 creative extra、deviant sandbox、local fallback degraded 标记。
- 实现 N=2 redo 候选产稿与 jury 翻盘事务。
- 写入 prompt context snapshot 和裁剪原因。

### 已完成：M4 review baseline

- 实现两道 hard gate 与 `writing_draft_eligibility`。
- 阻断 degraded / deviant 正式进入 jury。
- 实现 3 裁判全评 12 维、raw scores 与 aggregates 分表。
- 实现 writer/jury 隔离、winner 唯一、quality floor、dimension floor、judge disagreement 阻断。
- 实现 hard failure 自动重试、polish_revision、polish 后重新过 hard gates + quality floor。
- 实现 smart polish 不可降级、fact anchor gate、contract clause attribution、productive deviation 保护。

### 已完成：M5 chapter review + human seal baseline

- 实现章级 7 维 review 和硬质量门禁。
- 实现 human accept 审计、不可覆盖硬质量失败、chapter hard seal。
- 实现 human reject / revise：写 human decision，新建 run/shot contract/shot，旧 run 留档。
- 补盲评/继续阅读失败不得 accepted 的防回归测试。

### 已完成：M6 book/export/import baseline

- 实现 book rolling check、blocking issue 阻断 accept/export。
- 实现 export 只读 accepted canonical / hard-sealed 正文并清理结构标签。
- 实现 import dry-run / finalize、source hash 校验和 human decision 审计。
- 实现 6 章 workflow smoke，覆盖 write/review/reject/revise/accept/book check/export/import。
- 实现 CLI 薄壳：`init/setup/confirm-contract/write/review/revise/reject/accept/resume/import/export`。
- 补 CLI 集成测试和最终 invariant 收口测试。

### 已完成：P0 决策归档

- D1 模型池 JSON 校验：DB 底线 + `ProjectConfigValidator` 完整校验。
- D2 checkpoint `shot_id` 允许 NULL；非 NULL 必须含 run 后缀并满足 FK。
- D3 jury raw scores 阻断裁判模型等于写手模型。
- D4 仅 `TextRepository` 硬封版设置 `is_current=1`，partial unique index 保证唯一 current。
- D5 所有业务时间字段统一 UTC ISO 8601。
- E1 `ProjectConfig = WritingProject + MetaContract + ChapterSpecs`。
- E2 shot 级 orchestrator 入口只收 `(shot_id, run_id)`。
- E3 `TextRepository` 只公开 `read_current_text` / `write_revision` / `is_hard_sealed`。
- E4 统一错误层级。
- F1 测试分层：unit / integration / e2e。
- F2 使用 builder/factory fixture + mock LLM。
- F3 默认 CI 只测 mock 性能，真实 LLM 成本进手动/nightly。
- F4 安全测试覆盖 SQL/lint/正文隔离/SDK 直连/import/export。

### 已完成：Task #3 DecisionSession 主编台集成

- `DecisionSessionStore.confirm_and_apply()`：在单个 SAVEPOINT 内按 implementation-contract-v1 §3.6a 写入规则 7-8 原子写入完整 confirmed 审计链——coverage gate 检查 → `writing_human_decisions`（`decision_type='contract_confirm'`）→ `writing_contract_versions`（新版本，`status='confirmed'`，关联 `created_from_decision_session_id`）→ `writing_contract_patches`（`status='confirmed'`，链接 base/target version）→ `writing_contract_changelog`（old/new hash + human_decision_id）→ DecisionSession 置 `confirmed` + after_hash。任一写入失败整体回滚，不允许半状态。
- coverage gate 阻断：`confirm_and_apply` 接受可选 `coverage_gate` 参数（`SourceWorkflowStore`），blocking gap 未清空时抛 `DataIntegrityError` 且不写任何审计行。
- 契约版本递增：`_next_contract_version` 按 `(project_id, scope_type, scope_id)` 递增；`_resolve_base_contract_version_id` 把上一次 confirmed/locked 版本作为 patch base，首次确认为 NULL。
- CLI `confirm-contract --decision-session-id`：新增 `--scope-type/--scope-id/--contract-json/--source-clause-ids/--source-hashes`，走 `confirm_and_apply` 路径；不传 `--decision-session-id` 时保留旧的直接写 human_decision 行为，保持冒烟测试兼容。
- 测试：`test_decision_source_workflow.py` +4（原子写入、二次确认 base 链接、coverage gate 阻断、非 awaiting 拒绝）；`test_cli.py` +1（CLI 端到端审计链）。全量 124 passed。

### 已完成：Task #4 选择式对话 CLI/API

- CLI `decision-session` 子命令族：`start` / `parse` / `options` / `select` / `show` / `regenerate`，对应 implementation-contract-v1 §3.6a 选择式对话协议——`start` 收 human_text 置 `collecting`；`parse` 收 AI 解析的 patch + readback + source_hashes 置 `ai_parsed`；`options` 收 1-8 编号选项置 `awaiting_confirm`；`select N` 收作者选择（`0` 返回 `collecting` 并 cancel option set，`1-8` 置 `selected`，`9` 必须先 `regenerate`）。
- 活跃 option set 回放：`show` 回放当前活跃 option set 的 options / recommended_option / regenerate_count，恢复时不依赖模型重新想一版，避免恢复点漂移。cancelled option set 不再活跃。
- `regenerate`：生成新 option set 并把旧 set 置 superseded，`regenerate_count` 递增；`select 9` 在未先 regenerate 时返回非零退出码。
- 测试：`test_cli.py` +3（start→parse→options→select→show 协议、select 0 返回 collecting、select 9 必须 regenerate）。全量 127 passed。

### 已完成：Task #5 source coverage gate 集成

- `confirm-contract --decision-session-id` 默认接入 `SourceWorkflowStore` 作为 coverage gate：blocking gap（`coverage_status IN ('gap','conflict')`）未清空时抛 `DataIntegrityError` 阻断确认，不写任何审计行。
- `--skip-coverage-gate` 逃生阀：仅在无 source documents 记录时才真正无影响；有 gap 时仍按默认阻断。
- CLI 输出统一 `{"ok": True/False, "command":..., "data":...}` 包装，测试通过 `_run_and_capture` 解析 `data` 字段断言。
- 测试：`test_cli.py` +1（gate 阻断 → resolve → 放行端到端）。全量 128 passed。

### 已完成：Task #6 双模型抽取执行器

- `SourceExtractionOrchestrator.extract_dual()`：primary 与 crosscheck 两路独立调用 `LLMGateway` 抽取同一 source document，分别写 `writing_source_extraction_runs`（`extractor_slot='primary'/'crosscheck'`，记录 model_provider/model_name/source_hash/extracted_clause_ids/low_confidence_refs）。
- 差异比对 `diff_extractions()`：按位置 key（clause_type + scope + 首个 source_ref，不含文本）去重——primary 独有 → primary run 的 low_confidence_refs 标 `primary_only:`；crosscheck 独有 → crosscheck run 标 `crosscheck_only:`；同位置不同文本 → 写 `writing_source_coverage_matrix`（`coverage_status='conflict'`，evidence 记两路文本）。
- 两路一致的条款各写一条 `writing_atomic_source_clauses`（status=proposed），供后续 coverage 比对。
- `DefaultSourceExtractionProtocol`：要求 LLM 输出 JSON 数组，容忍前后噪声；`clause_type` 默认 `style`（受 schema CHECK 约束）。
- 测试：`test_source_extraction_orchestrator.py` +4（一致条款、crosscheck 漏抽 low_confidence、文本 conflict 写 coverage、primary 漏抽 low_confidence）。全量 132 passed。

### 已完成：Task #7 过程文件清空执行器

- `ProcessFileClearingOrchestrator.clear_process_file()`：将 `better.md` 等 process_scratch 文件作为抽取输入，在抽取并合并完成后清空磁盘文件内容（写空字节），写 `writing_process_file_manifests`（content_hash + processed_hash=空内容 sha256 + extracted_clause_ids/contract_patch_ids/decision_session_ids），并把 source document 置 `status='cleared'`。
- `SourceWorkflowStore.is_process_file_cleared()`：查询某路径是否已清空（status='cleared' 且有 manifest），供 prompt/contract 写入点阻断直接引用已清空过程文件。
- 幂等保护：重复清空同一文件抛 `DataIntegrityError`；相对路径拒绝（要求绝对路径）。
- 清空只清磁盘 + 写 manifest，不删除已抽取的 atomic clauses / coverage 记录——保证 gate 仍能查到 gap。
- 测试：`test_process_file_clearing.py` +4（清空写 manifest、相对路径拒绝、重复清空阻断、清空后引用阻断）。全量 136 passed。

### 已完成：Task #8 防回归测试补充

- `test_v1_1_integration_regression.py` +3 跨模块集成防回归测试，验证本次 v1.1 集成的关键不变量：
  1. 双模型抽取产生 text conflict → coverage matrix 记 conflict → `confirm_and_apply` 被 gate 阻断（不写审计行）。
  2. resolve conflict 后 gate 放行 → `confirm_and_apply` 成功写入审计链，且 human_decision 的 preconditions 记 `coverage_gate_checked=True`。
  3. 过程文件清空后，已抽取的 atomic clauses 与 coverage gap 仍存在，gate 仍阻断；resolve 后放行。
- 防回归点：抽取器 conflict 写入与 coverage gate 阻断查询的协同；清空执行器不污染已抽取条款；confirm 审计链记录 gate 检查痕迹。
- 全量 139 passed。

### 已完成：Task #9 自然语言到契约 patch（厚应用层 + JSON-Patch）

- `ContractPatchEngine` 厚应用层核心，实现 6 步校验流水线：
  0. **形态校验**（`validate_patch_shape`）：在 `record_ai_parse` 时提前拒绝格式非法 patch。
  1. **Schema 白名单校验**：严格校验 patch 的每个 path 是否在 scope_type 的白名单内。
  2. **Intra-conflict 检测**：同 patch 多个 op 改同 path → 报错。
  3. **加载 base contract**：从 `writing_contract_versions` 加载最新 confirmed/locked 版本。
  4. **应用 patch**：调 `apply_patch` 把 JSON-Patch 应用到 base payload。
  5. **必填字段检查**：确认新 payload 包含 scope 的所有必填字段。
  6. **回读一致性校验**（可选）：调 `ReadbackVerifier` 比对 readback 与 patch 语义一致性。
- RFC 6902 JSON-Patch 子集（`src/ink/contract/jsonpatch.py`）：支持 `add`/`remove`/`replace`/`move` 四操作，点分路径（如 `identity.title`，不用 `/` 前缀）。纯标准库实现。
- 层级契约字段 schema（`src/ink/contract/fields.py`）：定义 Book/Volume/Part/ChapterContract 的字段路径、类型、必填。严格白名单语义，对齐 `docs/implementation-contract-v1.md:2015-2018`。
- `ReadbackVerifier` 协议 + `LLMReadbackVerifier` 默认实现：调 `LLMGateway` 比对 readback 与 patch 语义一致性，仅输出 `true`/`false`。测试用 `_ScriptedReadbackVerifier` mock。
- `decision_sessions.py` 集成：
  - `record_ai_parse` 新增 `patch_engine` 参数，传入时调 `validate_patch_shape` 提前拒绝非法 patch。
  - `confirm_and_apply` 新增 `patch_engine` 参数，传入时自动派生 `contract_payload`（不要求调用方传），并在同一 SAVEPOINT 内更新 coverage matrix。
  - `_load_session_for_confirm` 扩展返回 `readback_text` 和 `source_hashes_json`，供 patch_engine 使用。
- `source_workflow.py` 新增 `update_coverage_for_patch`：批量把指定 field_paths 的 coverage 置 `covered`。
- 测试：`test_jsonpatch.py` +16（apply_patch 四操作边界 + patch_paths）；`test_contract_patch_engine.py` +35（形态校验、schema 白名单、intra-conflict、必填字段、6 步流水线、集成测试）。全量 190 passed。

## 2026-07-06 完成主编台产品化全链路（Task #15-#20）

验证命令：

```bash
cd ink && python -m pytest tests/ -o "addopts="
```

最近一次验收结果：

- 全量测试：`257 passed`（190 基线 + 67 新增）

### 已完成：Task #15 WorkflowConductor 薄调度状态机

- `src/ink/workflow_conductor.py`：实现 5 角色调度层（DecisionSessionHost / ContractSteward / Gatekeeper / CanonicalKeeper / AuditLedger）。
- `WorkflowConductor.step()` 状态机：`collecting → ai_parsed → awaiting_confirm → confirmed`，根据状态自动选择下一步角色方法。
- 角色职责分离：
  - `DecisionSessionHost.parse()`：解析 human_text 为 JSON-Patch（mock 模式或 LLM 模式）。
  - `ContractSteward.apply()`：写契约版本、patch、changelog，自动派生 contract_payload。
  - `Gatekeeper.validate()`：校验 schema、coverage gate、stale 状态。
  - `AuditLedger.record_event()`：追加审计记录到 `writing_runtime_events`。
- 测试：`test_workflow_conductor.py` +12（状态机推进、角色调度、审计记录）。

### 已完成：Task #16 ScopedDecisionSession 多作用域修订

- `src/ink/scoped_sessions.py`：实现 `ScopedDecisionPatch` dataclass 和 `ScopedDecisionSessionStore`。
- `start_scoped()`：启动带作用域的修订会话，支持 `parent_decision_session_id` 关联父会话。
- `record_affected_scopes()`：记录 `affected_scopes_json` 和 `stale_downstream_json` 到 `writing_contract_patches`。
- `create_scoped_decision_patch()`：辅助方法，构造 `ScopedDecisionPatch` 实例。
- 测试：`test_scoped_sessions.py` +6（多作用域启动、affected_scopes 记录、stale_downstream 记录）。

### 已完成：Task #17 契约字段投影集成

- `src/ink/contract/fields.py` 新增：
  - `validate_contract_payload(scope_type, payload)`：校验 payload 是否符合 schema，返回错误列表。
  - `extract_field_paths_from_payload(scope_type, payload)`：提取所有已定义的字段路径（用于追踪）。
- 集成到 `DecisionSessionStore.confirm_and_apply`：确认后调 `validate_contract_payload` 校验，不合规抛 `ContractPatchError`。
- 测试：`test_contract_field_projection.py` +13（payload 校验、字段路径提取、集成测试）。

### 已完成：Task #18 stale 传播实现

- `sql/schema.sql` 新增 `is_stale INTEGER NOT NULL DEFAULT 0` 字段：
  - `writing_prompt_snapshots`
  - `writing_drafts`
  - `writing_chapter_reviews`
  - `writing_book_check_results`
- `src/ink/stale_propagation.py`：实现 `StalePropagationManager` 和 `StaleMarkResult` dataclass。
- 传播矩阵：
  - `book` scope → 全部 prompt/draft/review/book_check
  - `volume` / `part` scope → 当前 schema 无分组列，退化为全部
  - `chapter` scope → 本章 prompt/draft/review + 全部 book_check
  - `source` 变化 → 通过 contract patches 关联的 decision sessions 传播
- `check_stale(shot_id)`：查询某 shot 是否 stale（用于 gate 阻断）。
- 标记幂等：重复调用不会重复计数。
- 测试：`test_stale_propagation.py` +14（book/chapter/volume/part scope、source 变化、check_stale 查询）。

### 已完成：Task #19 源文档规范化算法

- `src/ink/source_normalizer.py`：实现 `SourceNormalizer` 和相关 dataclass（`NormalizeResult` / `Conflict` / `ConflictQuestion`）。
- `normalize_source_directory()`：
  - 遍历目录中的 `.md` / `.txt` 文件
  - 计算 `content_hash`（SHA-256）
  - 推断 `source_kind`（从文件名关键词）
  - 注册为 `writing_source_documents`
  - 调用抽取器生成原子条款（默认规则抽取器或注入自定义抽取器）
  - 记录抽取运行到 `writing_source_extraction_runs`
- `merge_and_deduplicate()`：同 source_document 内 `clause_text` 完全相同的条款去重，保留最先出现的，其余标记为 `superseded`。
- `detect_conflicts()`：简化规则（同 scope + type + severity=hard 超过 1 条 → 标记冲突）。
- `generate_conflict_questions()`：为每个冲突生成 1 个 `DecisionSession`，4 个选项（保留 A / 保留 B / 合并 / 删除）。
- 测试：`test_source_normalizer.py` +17（目录读取、kind 推断、抽取、去重、冲突检测、选择题生成）。

### 已完成：Task #20 前 6 章端到端验收

- `tests/fixtures/sample_guides/`：创建测试用写作指南目录（`writing_guide.md` / `character_bible.md` / `outline_ch1-6.md`）。
- `tests/test_e2e_six_chapters.py`：5 个端到端集成测试：
  1. `test_full_pipeline`：完整流水线（注册 → 抽取 → 冲突检测 → 选择 → 确认 → 下游写入）。
  2. `test_stale_propagation_after_contract_change`：契约变更后标记下游 stale。
  3. `test_recovery_point`：模拟崩溃后恢复（从 DB 读取状态）。
  4. `test_interaction_burden`：验证交互负担（DecisionSession 数量 ≤ 预期）。
  5. `test_coverage_gate`：验证 coverage gate 阻断与解除。
- 验证点：
  - 源文档注册 + 原子条款抽取
  - 冲突检测 + 选择题生成 + 用户选择模拟
  - WorkflowConductor 状态机推进到 `confirmed`
  - 6 章的 prompt/draft/review 全部写入
  - 契约版本创建
  - stale 传播标记
  - 恢复点验证
  - 交互负担 ≤ 3 个 session
  - coverage gate 阻断与解除

### 关键成果

- **全量测试**：257 passed（190 基线 + 67 新增）
- **主编台产品化全链路完成**：
  - WorkflowConductor 薄调度（5 角色）
  - ScopedDecisionSession 多作用域修订
  - 契约字段投影校验
  - stale 传播矩阵
  - 源文档规范化算法
  - 前 6 章端到端验收
- **P1 任务全部完成**：所有计划内的 P1 产品化任务已实现并验证。
