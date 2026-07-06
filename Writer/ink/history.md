# InkFlow v2 历史任务归档

> **用途**：记录已经完成并验证的任务，保持 `tasks.md` 只呈现当前待办。
> **最后更新**：2026-07-06

---

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
