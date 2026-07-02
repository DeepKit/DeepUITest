# InkFlow v3.9 — 开发历史

> 记录已完成的修复和里程碑

---

## v3.24 CONFIG-ENFORCE 全线落地 (2026-07-02)

本轮把“DB 字段级线束”从方案推进到运行链路：AI 生成的关键配置不再只停留在 JSON blob 中，必须写入结构化表并接受 DB 约束；`layers_json` 保留为审计快照和兼容 fallback。

### 核心实现

- Schema v23 已落地 6 张元契约结构化表：`writing_project_identity`、`writing_hard_boundaries`、`writing_narrative_voice`、`writing_style_locks`、`writing_suspense_blueprint`、`writing_chapter_tension_arc`。
- Schema v24 新增 3 张 shot 契约结构化表：`writing_shot_must_land`、`writing_shot_anti_write`、`writing_shot_narrative_params`，承接 `must_land_json`、`anti_write_json`、`contract_json` 中 AI 写入的核心字段。
- `confirm-contract` 增加 `validate_contract_schema()` 预检，通过后写入结构化元契约表；Python 层快速失败，DB 层用 NOT NULL / CHECK / FK 硬拦。
- `ContractCompiler.compile_shot_contracts()` 在保留原 JSON 字段的同时写入 v24 三张 shot 表。
- 消费端改为优先读取结构化表：`architect_gate` 读角色/别名边界，`exporter` 读项目标题，`run` prompt 读 shot must_land / anti_write / narrative params；没有结构化行时回退旧 JSON。
- `init` 生成的 `contract-draft.yaml` 补齐 `identity.author`、`identity.era`、`identity.language`、`identity.total_chapters`、`identity.genre_tags`，避免新建项目在 v23 约束下无法确认契约。
- `.models` 修复 B81：`get_jury_config()` 校验 `roles.jury.primary_model` 与 `jury_config.models`，冲突时 warning，并以 `jury_config.models` 为权威。
- 从项目文档自动提取 `suspense_blueprint` 和章末钩子 fallback，减少悬疑配置留空。

### 当前口径

CONFIG-ENFORCE 已完成代码路径和测试覆盖。正式放量生产仍不打开；下一步用《白灯法则》第 3 章返工验证新门禁，再决定第 4 章首跑。

### 验证

- 目标测试：13 passed
- 全量回归：506 passed, 4 warnings

---

## v3.23 《白灯法则》第 2 章生产验证与管线修复 (2026-07-01)

本轮用《白灯法则》第 2 章做真实生产验证，发现并修复多个管线缺陷，同时完成悬疑约束架构决策。

### 管线修复

- **TITLE-FIX-1**：导出管线标题泄漏修复。`_extract_bullet_chapter_events` 中硬编码结构标签（`冲突1`、`章末钩子`）替换为 `_derive_event_title()` 从事件内容首句首分句提取有意义的短标题；8 个单元测试通过。
- **OUTLINE-HALLUCINATION-1**：大纲评估器重新生成时产生幻觉（1979 年工厂故事变成科幻内容"安保机器人"）。新增 `_outline_drift_too_large()` 双字漂移检测（CJK character bigram overlap），更新合约时校验新大纲与原始大纲的重叠率 ≥ 20%。
- **OUTLINE-PARSE-1**：大纲评估响应含推理前缀时解析失败，原返回固定 50 分。改为返回 `parse_error: True` 标记 + 阈值分数，不再把不可解析响应当作有效评分。
- **L3-GATE-FP-1**：L3 门禁 `chapter_hook_weak` 假阴性（只看末句分类为 sensory_detail，忽略前文未完结动作）和 `character_absence` 假阳性（前几章 POV 角色缺席属正常）。改为非阻断 warning。
- **L3-DENSITY-1**：L3 有标题 shot 最低字数从 450/500 下调为 350/400，适配短 shot 场景。

### 模型配置调整

- 《白灯法则》`.models` 配置：writer 主模型改为 `bailian/qwen3.7-plus`（避免 agnes-2.0-flash 写正文时出现 prompt  artifacts）；jury 主模型改为 `agnes/agnes-2.0-flash`；architect/repair 主模型改为 `deepseek/deepseek-v4-pro`（直连，避免 opencode 429 限流）。
- 移除 `jury_config.models` 中的 opencode/deepseek-v4-flash。

### 架构决策

- 悬疑/紧张度约束方案讨论完成，决定采用 **DB 字段级线束**：所有 AI 生成的配置项必须有结构化 DB 表接收，DB NOT NULL + CHECK + FK 硬拦，AI 无法绕过。JSON blob 仅保留给日志/快照/审计。
- 配置强制化方案已设计，待实施：新增 `writing_project_identity` / `writing_hard_boundaries` / `writing_narrative_voice` / `writing_style_locks` / `writing_suspense_blueprint` / `writing_chapter_tension_arc` 等结构化表。

### CONFIG-ENFORCE-1 落地

- Schema v22 → v23：新增 6 张元契约结构化表
  - `writing_project_identity`：title/author/genre/era/language（NOT NULL + CHECK length > 0）
  - `writing_hard_boundaries`：forbidden_phrases/deprecated_aliases/world_rules/characters_alive（NOT NULL）
  - `writing_narrative_voice`：pov_mode/pov_characters/tense/narrator_type（CHECK 枚举值）
  - `writing_style_locks`：max_paragraph_chars/dialogue_ratio/anti_patterns（CHECK 范围）
  - `writing_suspense_blueprint`：preset（5 选 1 CHECK）/global_question（CHECK length > 5）
  - `writing_chapter_tension_arc`：tension_target（CHECK 0-100）/suspense_role（枚举 CHECK）/blueprint_id FK
- 新增 8 个约束测试（TestV23ConfigEnforcement）+ 1 个迁移测试
- 修复 `test_l3_fails_when_chapter_hook_is_closed` 以适配 B79 非阻断改动
- 全量回归：495 passed, 4 warnings

验证：

- `rtk proxy python -m pytest tests/test_cli.py -v`：68 passed（含 8 个新增 TITLE-FIX 测试）。
- `rtk proxy python -m pytest -q`：495 passed, 4 warnings（含 8 个 v23 约束测试 + 1 个 v22→v23 迁移测试）。

---

## v3.21/v3.22 全程审计与契约审计半重构 (2026-06-29)

本轮结论：不完全推倒重来，改为半重构。保留现有 DB、Session、Contract、Prompt、Writer、Jury、Gate、Export 边界，新增统一审计层，让生产流程从 setup 到 review 可追因。

本轮第二阶段补齐 contract-first 第一版：不推倒现有服务边界，在 setup/run/prompt/jury 前增加横切资格门禁。

已完成：

- Schema v21：新增 `writing_audit_events`、`writing_setup_snapshots`、`writing_draft_eligibility`、`writing_failure_attributions`。
- Schema v22：`writing_audit_events.stage` 增加 `contract`，用于契约审计师复审事件。
- 真实《分流》库已迁移到 `_schema_meta.version=22`，`ink status "分流"` 正常返回。
- `model_attempts` 新增 `request_prompt_text`、`response_text`，模型调用不再只靠 hash 审计。
- `setup` 生成完整 setup snapshot；`run` 加载 setup 时写审计事件。
- Prompt 编译写入 `writing_context_snaps`，记录前文、事实锚点、意象任务和反样本上下文。
- Writer、Gate1、Jury、Gate2、Outline、L3/L4、Retry、Review、Export 均开始写统一 audit event 或 failure attribution。
- 修复 Gate1 通过稿 `gate1_result_json` 被 `mark_draft_usable()` 清空的问题。
- `setup --chapter` 生成 `inkflow.fact_manifest.v1`，包含废弃角色名、禁词、未授权事实扩写、hook 要求和每 shot authorized corpus。
- `run --chapter` 在大纲评估后执行 outline fact gate；失败时写 `outline_gate` audit event 和 failure attribution，不进入正文写作。
- 合格大纲编译为 `inkflow.shot_task_card.v1`，进入写手 prompt 和 `writing_audit_events`。
- Gate1 通过后、jury 前执行草稿 hard fact gate；不合格稿写入 `writing_draft_eligibility(hard_rule)` 和 failure attribution，不进入文学 PK。
- 修复 Gate1 后候选集未收窄的问题，避免机械检查失败稿继续进入 jury。
- RetryBudget 新增 `hard_rule_violation` 类型；新增 `ink audit-report` 汇总 run 审计链。
- `run --chapter` 在创建 session 前执行 setup linter，拦截 must_land 命中 forbidden phrases、POV 不一致、未知类型职责、章节 hook 缺失等 setup 自相矛盾问题；失败归因到 `contract_conflict`。
- `shot_task_card` 增加完整性检查；缺失 must_land、POV、hard_facts、hook duty 或 outline 时归因到 `task_card_gap`，不得进入正文写作。
- `confirm-contract` 增加契约审计师两轮复审：结构完整性复审和生产就绪复审；两轮通过后才创建 confirmed 元契约，失败写 contract audit report、DB audit event 和 `contract_conflict` 归因，并打回架构师和人类继续讨论。

验证：

- `python -m py_compile ...` 通过。
- 全量回归：`449 passed, 4 warnings`。

仍未完成：

- `gate_false_positive` 仍需通过真实章节失败样本继续细化自动归因规则。
- 新门禁尚未用《分流》第 3 章返工和第 4 章首跑验证，不能宣布正式投产。

---

## 第一轮 专家审查修复 (2026-06-17)

> 5 位专家审查 → 44 项问题 → 全部修复 → 170 tests pass

### 🔴 Critical — 8/8 ✅

| ID | 问题 | 修复方式 |
|----|------|----------|
| C1 | smart_redo permanent_red 不可达 | Schema `CHECK BETWEEN 0 AND 3` |
| C2 | import-baseline 重复运行数据翻倍 | `_import_shot` 查重 + `import_chapter` 复用 run_id |
| C3 | run 硬编码 8 个 shot | 从 baseline 动态读�� + `--shot-count` 选项 |
| C4 | 30+ FK 约束缺失 | schema.sql 全面重写，添加所有 REFERENCES |
| C5 | Migration 失败后强制标记版本 | 删除 force-mark + SAVEPOINT 包裹 |
| C6 | Backup 使用 shutil.copy2 不安全 | 改用 SQLite Online Backup API |
| C7 | 写操作缺少事务保护 | SAVEPOINT 事务保护 migration |
| C8 | project_config UNIQUE 约束崩溃 | 改用 INSERT OR REPLACE |

### 🟡 Important — 12/12 ✅

| ID | 问题 | 修复方式 |
|----|------|----------|
| I1 | --writer-count 无范围校验 | click.IntRange(2, 4) |
| I2 | 畸形 .models YAML 崩溃 | try/except yaml.YAMLError |
| I3 | _build_previous_shots 边界错误 | len(window) 替代 len(original) |
| I4 | detect_conflicts 不过滤 run_id | 查询加 AND run_id = ? |
| I5 | generate_motif_task 忽略 min_shot_gap | 检查 shot_index 间距 |
| I6 | 缺少高频查询列索引 | 添加 5 个索引 |
| I7 | writing_jury_scores 缺 UNIQUE | 复合 UNIQUE 约束 |
| I8 | _execute_schema 不处理内联注释 | _strip_inline_comment() |
| I9 | split_by_scene_headers 丢弃前言 | 保留 "前言" prologue shot |
| I10 | --file 相对路径解析错误 | 按 story_dir 解析 |
| I11 | setup 硬编码 "分流" | f-string 动态项目名 |
| I12 | types.py TypedDict 未导出 | models/__init__.py 导出 |

### 🧪 测试缺口 — 9/9 ✅

| ID | 测试 | 新增测试数 |
|----|------|-----------|
| T1 | smart_redo 耗尽路径 | TestSmartRedoExhaustion (4) |
| T2 | detect_conflicts 冲突路径 | TestDetectConflicts (2) |
| T3 | CLI 命令实际执行 | TestStatusSmoke + TestImportBaselineSmoke (2) |
| T4 | 端到端 pipeline 集成 | TestPipelineE2E (1) |
| T5 | gate1 边界值 | TestGate1BoundaryValues (3) |
| T6 | finalize_shot 黄/红路径 | TestFinalizeShotPaths (2) |
| T7 | determine_light 精确边界 | TestDetermineLightBoundary (6) |
| T8 | _activate_dynamic_jury | TestActivateDynamicJury (6) |
| T9 | gate1_result_json 持久化 | TestGate1ResultPersistence (2) |

### 🔵 Minor — 15/15 ✅

| ID | 问题 | 修复方式 |
|----|------|----------|
| M1 | busy_timeout 未设置 | PRAGMA busy_timeout=5000 加入 open_db() |
| M2 | _estimate_tokens 中文偏低 | /1.5 → /1.2 |
| M3 | _has_excessive_repetition 仅 trigram | 扩展为 2-6 gram |
| M4 | _split_statements 不处理字符串内分号 | 追踪 in_string 状态 + '' 转义 |
| M5 | auto_select_writer_count 对话比例 | 实现 dialogue_ratio > 0.4 → 3 |
| M6 | register_motif 不验证必需字段 | 添加 name/density/variants 必需检查 |
| M7 | temperature 列无范围 CHECK | CHECK (BETWEEN 0.0 AND 2.0) |
| M8 | min_shot_gap 无非负 CHECK | CHECK (min_shot_gap >= 0) |
| M9 | _rotate_backups 按 mtime 排序 | 改为按文件名排序 |
| M10 | services/__init__.py 全量导入 | __getattr__ lazy import |
| M11 | pyproject.toml 缺 dev 工具 | 添加 mypy/ruff/black |
| M12 | load_env 无测试 | TestLoadEnv (2 tests) |
| M13 | 原始字符串用于状态转换 | 接受 str | Enum 并自动转换 |
| M14 | baseline_importer 硬编码 snapshot_hash | 改用 text_hash_normalized() |
| M15 | sessions list/abort 全目录扫描 | 添加可选 project 参数 |

### 结果

| 指标 | 值 |
|------|-----|
| 总问题 | 44 |
| 已修复 | 44 |
| 测试数 | 139 → 170 (+31) |
| 涉及文件 | 30+ |

---

## 第二轮 专家审查修复 (2026-06-17)

> 5 位专家审查 → 58 项问题 → 全部修复 → 184 tests pass

### 完成统计

| 分类 | 已完成 |
|------|--------|
| Critical | 16/16 |
| Important | 22/22 |
| Minor | 20/20 |
| 总计 | 58/58 |

### 最后一批修复

| ID | 修复内容 |
|----|----------|
| I19 | `load_env` 无路径时发出警告 |
| I20 | 创建异常层次，`contract_compiler` 采用 `ContractError` |
| I21 | `load_models_config` 验证 `primary` 字段 |
| M4 | `review-shots` 命令添加 `--help` + smoke test |
| M5 | `setup` 命令添加 smoke test |
| M6 | `auto_select_writer_count` 添加 `dialogue_ratio` / `pov_count` 测试 |
| M7 | `idempotent_import` 验证 DB count 不重复 |
| M9 | `_split_statements` 处理块注释 `/* ... */` |
| M16 | 添加 `inkflow.logger` (`logging.NullHandler`) |

### 测试增长

| 阶段 | 测试数 |
|------|--------|
| 初始 | 139 |
| 第一轮修复后 | 170 |
| 第二轮修复后 | 184 |

### 结果

| 指标 | 值 |
|------|-----|
| 总问题 | 58 |
| 已修复 | 58 |
| 累计修复 | 102 |
| 测试结果 | 184 passed |

---

## 第三轮 P0 设计/实现审阅 (2026-06-18)

> 4 个专家视角审阅当前开发文档与实现。结论：文档设计接近最优，但当前程序实现仍未完成 P0 纵向闭环。

### 已完成动作

| 项 | 结果 |
|----|------|
| 文档审阅 | `design.md` / `flow.md` / `role-system.md` / `implementation-contract-v0.md` 已核对 |
| 实现审阅 | CLI、schema、contract/session/writer/jury/gate/fact-anchor 等核心模块已核对 |
| 测试复核 | `pytest -q` 通过，结果为 184 passed / 2 warnings |
| 新任务归档 | 新的 P0 阻塞项已转入 `TASKS.md` |
| 新 bug 记录 | 新发现问题已转入 `docs/bugfix.md` 第三轮 |

---

## P0 纵向闭环实现 (2026-06-18)

> 实现 P0 全部 8 个阻塞项。测试结果从 184 → 212 passed。

### 已完成修复

| Bug | 修复内容 | 新增测试 |
|-----|----------|---------|
| B13 | 新增 `ink confirm-contract` CLI 命令 + `--lock` 选项 | 4 tests (TestConfirmContract) |
| B14 | 新增 `ModelClient` 协议 + `LocalDefaultGenerator` 确定性生成器；`WriterDispatcher` 接入 | 7 tests (TestLocalDefaultGenerator, TestCreateModelClient) |
| B15 | Jury 分制统一为 0-100；新增 `score_override` 支持测试构造三种 verdict | 7 tests (TestJuryScoreScale) |
| B16 | 删除 `cli.py` 二次覆盖 `done_green` 的代码，由 `finalize_shot` 统一处理 | 1 test (test_yellow_status_preserved) |
| B17 | Fact Anchor 实现 3 类关键词提取 (character_state/object_location/event_occurred)；CLI 集成提取 + 注入 | 8 tests (TestFactAnchorExtraction, TestFactAnchorInjection) |
| B17-P0-7 | 新增 `_print_scope_report` 章完成摘要（绿/黄/红统计 + 锚点数 + 平均分） | 1 test (TestScopeReport) |
| B17-P0-8 | Chesil 新增 `InkFlowImporter`，read-only 导入 InkFlow DB | 4 tests (TestInkFlowImporter) |

### 新增文件

| 文件 | 说明 |
|------|------|
| `src/inkflow/services/model_client.py` | ModelClient 协议 + LocalDefaultGenerator |
| `tests/test_model_client.py` | ModelClient 测试 |
| `tests/test_jury_scoring.py` | Jury 分制与灯色阈值测试 |
| `tests/test_fact_anchor.py` | Fact Anchor 提取+注入测试 |
| `tests/test_scope_report.py` | Scope Report 测试 |
| `chesil/chisel/ingest/inkflow_importer.py` | Chesil read-only 导入 InkFlow DB |
| `chesil/tests/test_inkflow_importer.py` | Chesil 导入测试 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `src/inkflow/cli.py` | 新增 confirm-contract 命令；修复黄灯状态覆盖；集成 fact anchor 提取+注入；新增 scope report |
| `src/inkflow/services/writer_dispatcher.py` | 接入 ModelClient，替换占位文本 |
| `src/inkflow/services/jury_service.py` | 统一 0-100 分制；新增 score_override |
| `src/inkflow/services/fact_anchor_extractor.py` | 实现 3 类关键词提取 |
| `src/inkflow/db/schema.sql` | score 约束从 0-10 改为 0-100 |
| `src/inkflow/services/__init__.py` | 导出 ModelClient 系列 |
| `tests/test_schema.py` | 更新 score 范围测试 |
| `tests/test_cli.py` | 新增 confirm-contract 和 yellow status 测试 |

### 测试结果

| 阶段 | 测试数 |
|------|--------|
| 第三轮审阅后 | 184 |
| P0 实现后 | **212** (+28) |

---

## P1 数据一致性 + LLM + CLI 修复 (2026-06-18)

### 已完成

| Bug | 修复内容 | 新增测试 |
|-----|----------|---------|
| B18 (DB-1) | baseline shot 增加 `is_baseline=1` 标记；`write_revision` 拒绝覆盖 | 2 tests (TestBaselineProtection) |
| B19 (DB-2/3) | partial unique index `idx_revisions_one_current`；服务层校验 | 1 test (TestCurrentRevisionConstraint) |
| B21 (DB-5) | fact anchor 唯一键改为 `(project_id, anchor_key, source_revision_id)` | - |
| B22 (DB-6) | 新增 `model_attempts` 审计表 + idempotency_key | 3 tests (TestModelAttemptsAudit) |
| B14/B22 (LLM-1) | `ModelClient.generate()` 自动写入 audit 表 | - |
| B15 (LLM-4) | Gate2 不再把 yellow 标记为 `below_green_threshold` | - |
| B23 (LLM-5) | `compile_static_prefix` 超限时 emit warning + `cacheable` 标志 | - |
| CLI-4 | `repair` 使用真实 run_id 而非空字符串 | - |
| CLI-5 | 所有硬编码 `D:\\_Progs\\.Story` 替换为 `_STORY_BASE` | - |

### Schema 变更

| 变更 | 说明 |
|------|------|
| `writing_shots.is_baseline` | 新增列，baseline 标记 |
| `idx_revisions_one_current` | partial unique index |
| `model_attempts` | 新增 26 号表（模型调用审计） |
| `writing_fact_anchors` unique key | 改为 `(project_id, anchor_key, source_revision_id)` |
| SCHEMA_VERSION | 1 → 2 |

### 迁移

`@register_migration(1, 2)` 处理所有 schema 变更（含 fact anchor 表重建）。

### 测试结果

| 阶段 | 测试数 |
|------|--------|
| P0 实现后 | 212 |
| P1 实现后 | **218** (+6) |


---


基于第 01-03 章阅读发现的问题，映射到 7 个管线改动。

### 文学问题 → 代码改动映射

| ID | 文学问题 | 改动 | 涉及文件 | 优先级 | 状态 |
|----|---------|------|----------|:---:|:---:|
| OPT-1 | 段落膨胀（Ch02 多段 >1000 字） | L4 新增 `_check_paragraph_length()` | `architect_gate.py` | 🔴 P0 | ✅ |
| OPT-2 | 感官密度平铺（每段都有冷/湿/锈/霉） | per-shot `sensory_pressure` + `dominant_sense` | `contract_compiler.py` + `prompt_compiler.py` + YAML | 🔴 P0 | ✅ |
| OPT-3 | 叙述者越位（"她不是在…她是在…"） | 扩展 `_NARRATOR_INTRUSION_PATTERNS` | `architect_gate.py` + `jury_service.py` | 🔴 P0 | ✅ |
| OPT-4 | 角色消失（郑坤 Ch02/03 隐身） | L3 新增 `_check_character_presence()` | `architect_gate.py` | 🟡 P1 | ✅ |
| OPT-5 | 缺少精确细节（无"破"点） | jury `reading_fluency` 增加 precision detail 加分 | `jury_service.py` + `prompt_compiler.py` | 🟡 P1 | ✅ |
| OPT-6 | Shot 间情绪降速太快 | shot contract 增加 `entry_mood` | `prompt_compiler.py` + YAML | 🟡 P1 | ✅ |
| OPT-7 | 系统被过度解释（环境→解剖对象） | L4 新增 `_check_system_voice()` | `architect_gate.py` | 🟢 P2 | ✅ |

### 实施完成报告

**修改文件清单**：
- `src/inkflow/services/architect_gate.py` — 新增 3 个 L4 检查方法 + L3 角色存在感检查
- `src/inkflow/services/prompt_compiler.py` — 新增感官密度指令 + 精确细节要求 + 情绪入口
- `src/inkflow/services/contract_compiler.py` — shot contract 透传新字段 (sensory_pressure, dominant_sense, entry_mood)
- `src/inkflow/cli.py` — 从 YAML 提取新字段传入 shot contract
- `src/inkflow/services/jury_service.py` — reading_fluency 维度增加精确细节评分规则
- `tests/test_schema.py` — 修复 pre-existing 失败（添加 writing_information_gaps 表）

**测试结果**：全部 260 个测试通过 ✅

### 各 OPT 详细说明

**OPT-1 段落长度强制**
- `architect_gate.py` 新增 `_check_paragraph_length(text, max_chars=800)`
- 按 
 分割段落，检查每段字符数
- 超标段落记录 paragraph_index, char_count, overshoot, preview
- 结果纳入 suspense_summary 评分（0 违规=100分，≤2=60分，>2 线性递减）

**OPT-2 感官密度动态化**
- `contract_compiler.py` compile_shot_contracts 从 shot dict 提取 sensory_pressure/dominant_sense 写入 contract_json
- `prompt_compiler.py` _build_shot_context 读取这两个字段，生成分级指令：
  - 高：每段至少叠加两种感官，营造压迫感
  - 中：每段一到两种感官
  - 低：空旷安静留白，沉默本身成为感官
- `cli.py` 从 YAML chapter events 提取这两个字段传入 shot_data

**OPT-3 叙述者越位检测**
- `architect_gate.py` 新增 `_NARRATOR_INTRUSION_PATTERNS`（13 条正则）
- 捕获 "她不是在…她是在" / "问题不在于…而在于" / "他其实是" 等模式
- 新增 `_check_narrator_intrusion()` 方法
- severity=high，单独计数
- `jury_service.py` reading_fluency prompt 追加精确细节加分规则

**OPT-4 角色存在感追踪**
- L3 evaluate_l3 新增 Check 4
- 从 meta_contract 读取 pov_characters 列表
- 对比本章 pov_counts，找出缺席角色
- 新增 `_check_cross_chapter_absence()` 方法：查询前一章 POV，判断是否连续缺席
- 连续两章缺席核心角色时发出警告

**OPT-5 精确细节奖励**
- `prompt_compiler.py` _build_style_locks 追加"精确细节"要求段，含 4 个示例
- `jury_service.py` reading_fluency 维度说明中追加精确细节加分规则（有则 +5，无则 cap 80）

**OPT-6 情绪过渡桥接**
- `contract_compiler.py` 从 shot dict 提取 entry_mood 写入 contract_json
- `prompt_compiler.py` _build_shot_context 读取 entry_mood，注入 ## 情绪入口 段落
- `cli.py` 从 YAML chapter events 提取 entry_mood 字段传入 shot_data

**OPT-7 系统声音分离**
- `architect_gate.py` 新增 `_SYSTEM_DIRECT_PATTERNS`（3 条）和 `_SYSTEM_INTERPRETIVE_PATTERNS`（5 条）
- 新增 `_check_system_voice()` 方法
- 当 interpretive > direct 且 interpretive >= 2 时触发 warning
- 结果纳入 suspense_summary 评分（warning=30, 仅 interpretive=60, 仅 direct=100）

---

## 十二、AI 架构师·全书节奏统筹 — 2026-06-21

> 灵感来源：DeepStory（长篇小说工厂）的留白哲学与抽卡机制
> 核心洞察：**留白是全局决策，不是局部决策**。当前 InkFlow 对每个 shot 施加相同的约束粒度，导致"情节起伏机械化"。

### 核心公式（来自 DeepStory）

```
契约保下限 → 留白出上限 → 抽卡找高光 → 评价筛候选 → 人类定审美 → 系统学偏好
```

InkFlow 当前状态：
- ✅ 契约保下限（meta-contract + shot contract + L4 gate）
- ⚠️ 生成（2 路赛马，但差异化不足）
- ✅ 评价（9 评委）
- ❌ 留白出上限（无 deviation_budget、无叙事相位、无三层偏离分类）
- ❌ 系统学偏好（无风格偏好学习闭环）

### 关键设计原则（来自 DeepStory）

1. **"留白不是少给硬事实。留白是少给过细表达指令。"**
   - must_land.beats 当前把"写什么"和"怎么写"混在一起
   - 必须分离：硬事实（不可偏离）vs 软约束（可偏离后记录）vs 参考层（仅供灵感）

2. **任何新功能如果只强化约束一端而不考虑自由一端，就是设计缺陷。**
   - 现有 OPT 全是加法（更多检查），需要补充减法（不干预声明、留白空间）

3. **AI 是演奏者，不是作曲者。**
   - 人类作曲（契约）→ AI 演奏（生成）→ 机器验证（gate）
   - 但演奏需要"表现空间"——当前 prompt 没有给这个空间

### 架构位置：5 层治理体系

```
┌───────────────────────────────────────────────────────────┐
│  L0: Book Constitution（全书宪法）                        │
│  执行频率: 每项目 1 次    LLM: 80% / 规则: 20%           │
│  人工介入: 必须确认       输出: rhythm_constitution（不可变）│
├───────────────────────────────────────────────────────────┤
│  L0.5: Volume Rhythm（卷部节奏）           ← 中间翻译层   │
│  执行频率: 每卷 1 次      LLM: 70% / 规则: 30%           │
│  人工介入: 无（冲突上报 L0）                               │
│  输出: volume_rhythm_map（章角色 + 章张力预算）            │
├───────────────────────────────────────────────────────────┤
│  L1: Chapter Rhythm（章级节奏）                           │
│  执行频率: 每章 1 次      LLM: 60% / 规则: 40%           │
│  人工介入: 无（冲突上报 L0.5）                             │
│  输出: chapter_rhythm_map（shot 级 phase + budget）        │
├───────────────────────────────────────────────────────────┤
│  L2: Shot Enrichment（Shot 契约富化）                     │
│  执行频率: 每 Shot 1 次   LLM: 30% / 规则: 70%           │
│  人工介入: 无                                             │
│  输出: enriched_shot_contract（三层偏离结构）              │
├───────────────────────────────────────────────────────────┤
│  L3: Prompt Assembly（Prompt 组装）                       │
│  执行频率: 每 Shot × 每 Persona          LLM: 0%（模板）  │
│  人工介入: 无                                             │
│  输出: final_prompt_text                                  │
└───────────────────────────────────────────────────────────┘

setup → confirm-contract → [L0 全书宪法] → [L0.5 卷部节奏] →
[L1 章级节奏] → [L2 Shot 富化 + compile] → [L3 Prompt 组装] → run → gate
```

**为什么需要 L0.5 卷部级**：
- 一本书 20+ 章时，全书架构师 context window 会爆，决策质量下降
- 卷部级做中间翻译：把全书战略分解为卷部战术，再下发到章级
- 每卷有自己的 mini-arc（起承转合），同时服从全书 arc
- 经典分层控制：战略（L0）→ 战术（L0.5）→ 执行（L1/L2/L3）

### 任务清单

| ID | 任务 | 治理层 | 描述 | 涉及文件 | 优先级 | 状态 |
|----|------|:---:|------|----------|:---:|:---:|
| ARCH-1 | **三层偏离分类** | L2 | shot contract 拆分为 hard_facts / soft_constraints / reference 三层，prompt 注入时区别对待 | `contract_compiler.py` + `prompt_compiler.py` + `cli.py` + YAML schema | 🔴 P0 | ✅ |
| ARCH-2 | **deviation_budget 参数** | L1→L2 | 每个 shot 携带 0.0-1.0 的留白预算，控制表达自由度 | `contract_compiler.py` + `prompt_compiler.py` | 🔴 P0 | ✅ |
| ARCH-3 | **叙事相位分类** | L1 | 6 相位（chaos/pulse/ripple/sediment/fold/sublime），自动推导 paragraph_length、sensory_pressure、deviation_budget | `contract_compiler.py` + `prompt_compiler.py` + YAML schema | 🔴 P0 | ✅ |
| ARCH-4 | **Book Constitution 服务** | L0 | 新建 `book_constitution.py`：读取全书大纲 + meta-contract，用 LLM 生成全书宪法（arc_shape、章角色分组、motif 生命周期、全局 deviation 范围），规则引擎验证，人类确认后锁定 | `services/book_constitution.py`（新建） | 🔴 P0 | ⏳ |
| ARCH-5 | **Volume Rhythm 服务** | L0.5 | 新建 `volume_rhythm.py`：读取 L0 宪法 + 本卷所有章 events，为每章分配卷内角色（起承转合）+ 张力预算 + deviation_budget 范围，规则引擎验证卷内 mini-arc 完整性 | `services/volume_rhythm.py`（新建） | 🔴 P0 | ⏳ |
| ARCH-6 | **Chapter Rhythm 服务** | L1 | 新建 `chapter_rhythm.py`：读取 L0.5 卷节奏 + 本章 events，为每个 shot 分配 narrative_phase + deviation_budget，规则引擎验证 5 条节奏规则 | `services/chapter_rhythm.py`（新建）+ `db/migration.py` v6→v7 | 🔴 P0 | ✅ |
| ARCH-7 | **CLI 集成** | L0+L0.5+L1 | L1 已集成到 run 循环；L0/L0.5 CLI 命令待实现 | `cli.py` | 🟡 P1 | ⏳ |
| ARCH-8 | **4 路赛马 + 风格方向** | L3 下消 | writer_dispatcher 从 2 路扩展到 4 路：意象师(诗意/0.95) + 节奏师(克制/0.75) + 对话师(生活化/0.85) + 结构师(极简/0.60) | `writer_dispatcher.py` + `cli.py` | 🟡 P1 | ✅ |
| ARCH-9 | **不干预声明** | L3 | prompt static prefix 新增"不干预声明"段，明确告知 AI 哪些维度不在系统检查范围内 | `prompt_compiler.py` | 🟡 P1 | ✅ |
| ARCH-10 | **风格偏好学习** | 跨层反馈 | jury 选出获胜草稿后，记录其 persona/model/temperature/style_direction，反馈 L0.5/L1 调整后续 shot | `jury_service.py` + `prompt_compiler.py` + 新表 | 🟢 P2 | ⏳ |
| ARCH-11 | **反契约沙盒** | L2 变体 | 允许 1 路赛马故意偏离契约，用"意外价值"标准评估；如果明显更好，触发人类裁决 | `writer_dispatcher.py` + `architect_gate.py` | 🟢 P2 | ⏳ |
| ARCH-12 | **三棵树架构** | 跨层 | 数据库从扁平结构升��为三棵树（契约树/故事树/执行树），4 张新表（`tree_nodes`/`contract_versions`/`story_content`/`execution_records`），8 层标准金字塔统一，Schema v7→v8，详见 `docs/design-3tree-architecture.md` | `db/schema.sql` + `db/migration.py` + `docs/design-3tree-architecture.md` | 🔴 P0 | ✅ |
| ARCH-12 | **三棵树架构** | 跨层 | 数据库从扁平结构升级为三棵树，4 张新表（tree_nodes/contract_versions/story_content/execution_records），8 层标准金字塔统一，Schema v7-v8，详见 docs/design-3tree-architecture.md | db/schema.sql + db/migration.py + docs/design-3tree-architecture.md | P0 | + |
| ARCH-13 | **正文真相源锚定** | 跨层 | shot_revisions.text 确认为正文唯一真相源（未封版=MAX(seq)，已封版=is_current=1）；execution_records 加 revision_id FK-shot_revisions；三棵树为索引非正文 | db/schema.sql + db/migration.py + 4 design docs | P0 | + |

### L0 全书宪法算法（ARCH-4 详解）

```
输入：
  - 已确认 meta-contract（identity.character_arcs, suspense_config, foreshadow_tracker）
  - 全书所有章节的 chapter_X_events
  - motif_definitions

步骤 1：LLM 分析全书结构
  - 全书 arc_shape（slow_build → crisis → resolution / 三幕式 / 五幕式 / ...）
  - 张力峰值位置（哪一章是全书高潮）
  - 张力谷值位置（哪里需要喘息）

步骤 2：LLM 分组卷部（如果章节数 > 5）
  - 将连续章节分组为卷/部
  - 每卷 3-7 章
  - 分组依据：场景集中度、POV 角色群、时间线连续性
  - 输出：volume_chapter_map

步骤 3：LLM 规划 motif 生命周期
  - 每个 motif：planted_at → developed_at[] → resolved_at
  - 规则引擎验证：每个 motif 至少 planted + resolved

步骤 4：LLM 设定全局留白基调
  - global_deviation_mean（���书留白均值）
  - global_deviation_range（允许的偏差范围）

步骤 5：规则引擎验证
  ✓ 所有章节都被分配到卷部
  ✓ 张力弧有且仅有 1 个峰值
  ✓ 每个 motif 的 lifecycle 完整
  ✓ character_arcs 的转折点在高潮章之前有铺垫
  ✓ 卷部数量合理（2-6 个）

步骤 6：人类确认 → 锁定为 constitution（不可变）

输出：rhythm_constitution.json
```

### L0.5 卷部节奏算法（ARCH-5 详解）

```
输入：
  - L0 constitution（本卷的角色：铺垫卷/升级卷/高潮卷/收束卷）
  - 本卷所有章的 chapter_events
  - 前一卷的 volume_rhythm_map（如有，用于跨卷衔接）

步骤 1：LLM 设计卷内 mini-arc
  - 本卷有自己的起承转合（不是全书 arc 的简单复制）
  - 例如高潮卷：起（紧张积累）→ 承（冲突爆发）→ 转（反转/顿悟）→ 合（余波）
  - 输出：volume_arc_shape

步骤 2：LLM 为每章分配卷内角色
  - 每章的角色：establishment / rising / climax / falling / bridge
  - bridge = 连接下一卷的过渡章（末尾必须有跨卷钩子）
  - 规则引擎验证：
    ✓ 每卷至少 1 个 rising + 1 个 climax
    ✓ 如果是最后一卷，至少 1 个 falling/resolution
    ✓ 如果有后续卷，最后一章角色为 bridge

步骤 3：LLM 分配每章的张力预算
  - 每章获得 chapter_tension_budget（0.0-1.0）
  - 高潮章 → 高张力（0.7-0.9）
  - 铺垫章 → 低张力（0.3-0.5）
  - 过渡章 → 中张力（0.4-0.6）

步骤 4：LLM 分配每章的 deviation_budget 范围
  - 每章获得 [min_budget, max_budget]
  - 高潮章：范围窄且低（[0.15, 0.45]）→ 需要精确控制
  - 铺垫章：范围宽且高（[0.45, 0.80]）→ 允许自由发挥
  - 规则引擎验证：
    ✓ 每章范围在 L0 全局范围内
    ✓ 卷内 deviation 均值接近 L0 的全局均值（±0.1）

步骤 5：LLM 规划本卷的 motif 推进
  - 本卷哪些 motif 被植入/发展/回收
  - 跨卷 motif 的延续（从上一卷接什么）

步骤 6：LLM 设计跨卷衔接点
  - 本卷最后一章的 hook → 下一卷的第一章必须承接
  - 输出：volume_transition（{exit_hook, entry_expectation}）

步骤 7：规则引擎验证
  ✓ mini-arc 完整性（有起有收）
  ✓ 张力曲线不是一条直线（至少 2 个拐点）
  ✓ 跨卷衔接点存在
  ✓ 与前一卷的 exit_hook 兼容
  ✓ 违规 → LLM 重试（最多 3 轮）→ 仍失败则上报 L0 人类

输出：volume_rhythm_map.json
```

### L1 章级节奏算法（ARCH-6 详解）

```
输入：
  - L0.5 volume_rhythm_map（本章的角色 + 张力预算 + deviation 范围）
  - 本章的 chapter_events（shot 列表）
  - 前一章的 chapter_rhythm_map（用于跨章衔接）

步骤 1：标记"锚点 shot"（低 deviation_budget）
  - foreshadow recovery 所在 shot → 锚点（motif 回收必须精确）
  - 章末钩子 shot → 锚点（hook 必须落地）
  - character_arc 转折点 → 锚点（认知断裂/觉醒时刻）
  - 锚点 deviation_budget: 0.2 ~ 0.35
  - 约束：预算必须在 L0.5 给定的 [min, max] 范围内

步骤 2：标记"呼吸 shot"（高 deviation_budget）
  - 两个锚点之间的过渡 → 呼吸
  - 日常场景、环境描写、次要人物互动 → 呼吸
  - 呼吸 deviation_budget: 0.6 ~ 0.8

步骤 3：推导叙事相位（narrative_phase）
  - 锚点根据事件类型：
    - 对抗/冲突 → pulse
    - 揭示/反转 → chaos
    - 顿悟/告别/认知断裂 → sublime
  - 呼吸根据上下文：
    - 锚点后 → ripple（余波）
    - 日常场景 → sediment（沉积）
    - 涉及时间跳跃/多视角交织 → fold（折叠）

步骤 4：推导衍生参数
  - pulse: paragraph_length [200,400], sensory_pressure 高
  - ripple: paragraph_length [400,600], sensory_pressure 中
  - sediment: paragraph_length [500,800], sensory_pressure 低
  - chaos: paragraph_length [300,500], sensory_pressure 高
  - fold: paragraph_length [400,600], sensory_pressure 中
  - sublime: paragraph_length [300,600], sensory_pressure 中偏高

步骤 5：节奏规则验证（规则引擎，非 LLM）
  - 相邻 shot 的 deviation_budget 不能连续 3 个相同
  - 相邻 shot 的 narrative_phase 不能连续 3 个相同
  - 每章至少 1 个呼吸 shot（budget > 0.5）
  - 每章至少 1 个锚点 shot（budget < 0.4）
  - 本章 deviation_budget 均值必须在 L0.5 给定的范围内
  - 如果违反规则 → LLM 重新调整 → 最多 3 轮
  - 3 轮仍违规 → 上报 L0.5（请求调整本章张力预算）

步骤 6：跨章衔接检查
  - 本章第一个 shot 的 entry_mood 与前一章最后一个 shot 的 exit_mood 兼容
  - 如果不兼容 → 调整 entry_mood 或上报

输出：chapter_rhythm_map.json
```

### L2 Shot 富化算法（ARCH-1 详解）

```
输入：
  - 现有 shot contract（must_land + anti_write）
  - L1 chapter_rhythm_map（本 shot 的 phase + budget）

步骤 1：规则引擎分类 must_land beats（70%）
  - 涉及具体事件动作（到达/发现/弹出/看见）→ hard_facts
  - 涉及情绪/氛围/叙事距离 → soft_constraints
  - 分类规则：可量化/可验证 → hard，主观判断 → soft

步骤 2：LLM 生成 reference 层（30%）
  - style_direction：根据 narrative_phase 推荐
  - example_text：如果前一 shot 有获胜草稿，从中摘取风格参考
  - motif_connection：当前 shot 与 motif 生命周期的关系

步骤 3：规则引擎后验
  ✓ hard_facts 覆盖原 must_land 的所有事件性 beats
  ✓ deviation_budget 与 L1 分配一致
  ✓ narrative_phase 与 L1 分配一致
  ✓ reference 层不为空（至少有 style_direction）

输出：enriched_shot_contract（三层结构 + phase + budget）
```

### 三层偏离分类示例（ARCH-1 详解）

当前 InkFlow 的 shot contract：
```json
{
  "must_land": {"beats": "- 郑坤到达太古里\n- 发现收件人换地方\n- 系统弹出配送失败\n- 玻璃幕墙看见自己的倒影\n- 保鲜膜从裤腿露出来..."},
  "anti_write": {"pov_only": "只写郑坤", "forbidden": "不要写其他人的活动"}
}
```

改造后的三层结构：
```json
{
  "hard_facts": [
    "郑坤到达太古里",
    "收件人换了地方（IFS）",
    "系统弹出'配送失败'",
    "玻璃幕墙前看见自己的倒影，保鲜膜从裤腿露出来"
  ],
  "soft_constraints": [
    "情绪基调：羞耻 + 被困",
    "至少两种感官叠加（温度 + 触觉）",
    "叙事距离：贴身，不离开郑坤的身体"
  ],
  "reference": {
    "style_direction": "粗粝",
    "example_text": "玻璃里面是暖黄色的灯光。玻璃外面是十二月的雨。",
    "motif_connection": "保鲜膜第三次出现——从生存工具变成可见的标记"
  },
  "deviation_budget": 0.25,
  "narrative_phase": "pulse",
  "anti_write": {"pov_only": "只写郑坤", "forbidden": "不要写其他人的活动"}
}
```

Prompt 注入方式：
```
## 硬事实（不可偏离）
- 郑坤到达太古里
- 收件人换了地方
...

## 软约束（建议遵守，允许表达偏离）
- 情绪基调：羞耻 + 被困
...
以上约束你可以偏离——如果你的偏离产生了更好的文本。偏离不需要解释。

## 灵感参考（不检查，不约束）
- 风格方向：粗粝
- 示例："玻璃里面是暖黄色的灯光..."

## 不干预声明
以下维度不在系统检查范围，完全由你决定：
- 读者的个人联想
- 审美偏好
- 具体的意象选择（只要不违反硬事实）
- 句子的节奏和长度变化
```

### 4 路赛马风格方向设计（ARCH-6 详解）

| Persona | 温度 | 风格方向 | 差异化重点 | deviation_multiplier |
|---|---|---|---|---|
| 意象师 | 0.95 | 诗意 | 感官密度最高，隐喻最多，允许跳跃性思维 | 1.2x |
| 节奏师 | 0.75 | 克制 | 句长变化最大，长短交替，信息释放节奏最讲究 | 0.8x |
| 对话师 | 0.85 | 生活化 | 对话占比最高，潜台词，成都方言最多 | 1.0x |
| 结构师 | 0.60 | 极简 | 情节推进最快，零废话，硬事实覆盖率最高 | 0.6x |

4 路共用同一个 shot contract（相同的 hard_facts），但 prompt 的"灵感参考"和"风格方向"不同，temperature 不同，deviation_budget 被 multiplier 调整。

Jury 从 4 份差异显著的草稿中选择，而不是从 2 份相似草稿中选择。

### 实施顺序

```
Phase 1（核心留白机制）：ARCH-1 + ARCH-2 + ARCH-3
  → 让 shot contract 有三层结构和留白预算
  → 预计改动量：~200 行（contract_compiler + prompt_compiler + cli）

Phase 2（分层 AI 架构师）：ARCH-4 + ARCH-5 + ARCH-6 + ARCH-7
  → L0 全书宪法 → L0.5 卷部节奏 → L1 章级节奏
  → 预计改动量：~500 行
    · book_constitution.py（L0）~150 行
    · volume_rhythm.py（L0.5）~150 行
    · chapter_rhythm.py（L1）~120 行
    · CLI 集成（ARCH-7）~80 行

Phase 3（赛马升级）：ARCH-8 + ARCH-9
  → 4 路赛马 + 不干预声明
  → 预计改动量：~150 行（writer_dispatcher + prompt_compiler）

Phase 4（学习闭环）：ARCH-10 + ARCH-11
  → 风格偏好学习 + 反契约沙盒
  → 预计改动量：~200 行 + 新表
```

### 数据库变更（更新版）

```sql
-- L0: 全书宪法
CREATE TABLE writing_book_constitutions (
    constitution_id    TEXT PRIMARY KEY,
    project_id         TEXT NOT NULL REFERENCES projects(project_id),
    arc_shape          TEXT NOT NULL,
    volume_map_json    TEXT NOT NULL,      -- 卷部→章节的映射
    chapter_roles_json TEXT NOT NULL,      -- 每章的全书级角色
    motif_lifecycle_json TEXT NOT NULL,    -- motif 的 planted/developed/resolved
    global_deviation_mean REAL NOT NULL,
    global_deviation_range_json TEXT NOT NULL,
    confirmed_at       TEXT,               -- 人类确认时间（NULL=未确认）
    created_at         TEXT DEFAULT (datetime('now'))
);

-- L0.5: 卷部节奏
CREATE TABLE writing_volume_rhythms (
    volume_rhythm_id   TEXT PRIMARY KEY,
    project_id         TEXT NOT NULL REFERENCES projects(project_id),
    constitution_id    TEXT NOT NULL REFERENCES writing_book_constitutions(constitution_id),
    volume_key         TEXT NOT NULL,       -- 卷标识（如 "vol_01"）
    volume_arc_shape   TEXT NOT NULL,       -- 卷内 mini-arc
    chapter_rhythms_json TEXT NOT NULL,     -- 每章的 {role, tension_budget, deviation_range}
    motif_progress_json TEXT,               -- 本卷的 motif 推进计划
    volume_transition_json TEXT,            -- 跨卷衔接点
    validation_log     TEXT,
    created_at         TEXT DEFAULT (datetime('now'))
);

-- L1: 章级节奏（原 writing_rhythm_maps 拆分）
CREATE TABLE writing_chapter_rhythms (
    chapter_rhythm_id  TEXT PRIMARY KEY,
    project_id         TEXT NOT NULL REFERENCES projects(project_id),
    volume_rhythm_id   TEXT NOT NULL REFERENCES writing_volume_rhythms(volume_rhythm_id),
    chapter_key        TEXT NOT NULL,
    shot_rhythms_json  TEXT NOT NULL,       -- 每 shot 的 {phase, budget, paragraph_length, sensory_pressure}
    chapter_tension_curve TEXT,
    validation_log     TEXT,
    created_at         TEXT DEFAULT (datetime('now'))
);

-- L2/L3: 风格偏好（跨层反馈）
CREATE TABLE writing_style_preferences (
    preference_id       TEXT PRIMARY KEY,
    project_id          TEXT NOT NULL REFERENCES projects(project_id),
    shot_id             TEXT NOT NULL,
    winning_persona     TEXT NOT NULL,
    winning_model       TEXT NOT NULL,
    winning_temperature REAL,
    winning_style_dir   TEXT,
    created_at          TEXT DEFAULT (datetime('now'))
);
```

### 《分流》5 层治理示例

#### L0 全书宪法输出

```json
{
  "arc_shape": "slow_build → crisis → revelation",
  "volumes": {
    "vol_01": {
      "name": "V01·膝盖与螺丝刀",
      "chapters": ["ch01", "ch02", "ch03", "ch04", "ch05"],
      "role": "establishment + first_crack",
      "description": "建立四人世界观，第一道裂缝出现"
    }
  },
  "chapter_roles": {
    "ch01": "establishment",
    "ch02": "rising",
    "ch03": "rising",
    "ch04": "climax",
    "ch05": "bridge_to_vol2"
  },
  "motif_lifecycles": {
    "保鲜膜":     {"planted": "ch01", "developed": ["ch02","ch03"], "resolved": "ch04"},
    "太阳神鸟":   {"planted": "ch01", "developed": ["ch03"],        "resolved": "vol_02"},
    "34分健康积分":{"planted": "ch01", "developed": ["ch02"],        "resolved": "ch04"},
    "四份通知":   {"planted": "ch01", "developed": ["ch02","ch03"], "resolved": "ch05"}
  },
  "global_deviation_mean": 0.5,
  "global_deviation_range": [0.25, 0.75]
}
```

#### L0.5 卷部节奏输出（V01）

```json
{
  "volume_key": "vol_01",
  "volume_arc_shape": "grounding → unease → fracture → aftershock",
  "chapter_rhythms": [
    {
      "chapter": "ch01",
      "role": "grounding",
      "tension_budget": 0.35,
      "deviation_range": [0.45, 0.75],
      "notes": "建立基调，允许大量留白让 AI 自由构建世界"
    },
    {
      "chapter": "ch02",
      "role": "rising",
      "tension_budget": 0.55,
      "deviation_range": [0.35, 0.65],
      "notes": "张力开始上升，留白收窄"
    },
    {
      "chapter": "ch03",
      "role": "rising",
      "tension_budget": 0.60,
      "deviation_range": [0.30, 0.65],
      "notes": "苏然和韩教授的章节，认知裂缝加深"
    },
    {
      "chapter": "ch04",
      "role": "climax",
      "tension_budget": 0.85,
      "deviation_range": [0.15, 0.45],
      "notes": "V01 高潮，motif 回收，必须精确落地"
    },
    {
      "chapter": "ch05",
      "role": "bridge",
      "tension_budget": 0.50,
      "deviation_range": [0.40, 0.70],
      "notes": "收束 V01 + 钩住 V02，四份通知的余波"
    }
  ],
  "motif_progress": {
    "保鲜膜": "ch02=变形(从工具到标记), ch03=扩散(他人也看到)",
    "四份通知": "ch02=第二份, ch03=第三份, ch05=第四份+余波"
  },
  "volume_transition": {
    "exit_hook": "ch05 末尾：郑坤手机上弹出第五条通知——来自一个不该存在的号码",
    "entry_expectation": "V02 ch01 必须承接这个号码的身份悬念"
  },
  "validation": {
    "mini_arc_complete": true,
    "tension_inflection_points": 2,
    "all_chapters_assigned": true,
    "cross_volume_hook_present": true
  }
}
```

#### L1 章级节奏输出（ch03·rising）

```json
{
  "chapter": "ch03",
  "volume_role": "rising",
  "l05_budget_range": [0.30, 0.65],
  "shots": [
    {"shot": "glass_knee",      "phase": "ripple",   "budget": 0.35, "note": "锚点：保鲜膜 motif 在玻璃中的变形"},
    {"shot": "four_notices",    "phase": "sediment", "budget": 0.60, "note": "呼吸：通知的累积，日常中的异常"},
    {"shot": "pencil_question", "phase": "ripple",   "budget": 0.65, "note": "呼吸：苏然的铅笔——允许 AI 自由探索"},
    {"shot": "three_year_log",  "phase": "sublime",  "budget": 0.25, "note": "锚点：认知断裂时刻，必须精确"},
    {"shot": "slow_down",       "phase": "sediment", "budget": 0.55, "note": "呼吸：减速，为 ch04 高潮蓄力"}
  ],
  "validation": {
    "rule_1_pass": true,
    "rule_2_pass": true,
    "rule_3_pass": true,
    "rule_4_pass": true,
    "rule_5_pass": true,
    "mean_budget": 0.48,
    "l05_range": [0.30, 0.65],
    "mean_in_range": true
  }
}
```

**注意约束链的传递**：
- L0 说 ch03 是 "rising"，deviation_range [0.30, 0.65]
- L0.5 说 V01 是 "establishment + first_crack"，ch03 张力 0.60
- L1 根据 L0.5 的 [0.30, 0.65] 给每个 shot 分配 budget
- 锚点 shot (three_year_log) 的 0.25 低于 L0.5 下限 0.30
  → 规则引擎报警 → L1 LLM 调整到 0.30 或上报 L0.5 请求降低下限
  → 最终决定：0.30（规则引擎赢了）

这就是分层治理的意义：**每一层的自由度被上一层约束，但不能被忽略**。

### 层间治理协议

**约束向下流动**：
```
L0 constitution → 约束 L0.5 的卷角色和张力范围
L0.5 volume_rhythm → 约束 L1 的章角色和 deviation 范围
L1 chapter_rhythm → 约束 L2 的 shot phase + budget
L2 enriched_contract → 约束 L3 的 prompt 内容
```

**冲突向上反馈**：
```
L1 发现 L0.5 的 budget 范围无法容纳锚点 shot
  → 生成 conflict_report 上报 L0.5
  → L0.5 LLM 评估：扩展范围 or 调整章角色
  → 如果超出 L0.5 权限 → 上报 L0 人类

每层最多 3 轮自动调整
```

**层间不可越级**：
```
L3 不能直接修改 L1 的 deviation_budget
L2 不能直接修改 L0.5 的章角色
L1 不能直接修改 L0 的 constitution
每一层只能修改自己的输出，不能修改其他层的输出
```

### 验证标准

**L0 全书宪法验证**：
1. ✅ 所有章节被分配到卷部
2. ✅ 张力弧有且仅有 1 个峰值
3. ✅ 每个 motif 的 lifecycle 完整（planted → resolved）
4. ✅ 人类确认后 constitution 不可变（二次写入报错）

**L0.5 卷部节奏验证**：
5. ✅ 卷内 mini-arc 完整性（有 rising + climax）
6. ✅ 张力曲线至少 2 个拐点
7. ✅ 跨卷衔接点（exit_hook）存在
8. ✅ 每章 deviation_range 在 L0 全局范围内

**L1 章级节奏验证**：
9. ✅ Shot 3（苏然·铅笔的问号）的 deviation_budget 应为 0.65（呼吸 shot）
10. ✅ Shot 4（苏然·三年前的记录）的 deviation_budget 应为 0.30（锚点 shot）
11. ✅ 两个苏然 shot 的 narrative_phase 不同（ripple vs sublime）
12. ✅ 每章至少 1 个锚点 + 1 个呼吸 shot
13. ✅ 本章 budget 均值在 L0.5 给定范围内

**L2/L3 验证**：
14. ✅ paragraph_length 随 phase 变化，不是全局 500-800
15. ✅ Jury 评审 4 份草稿而非 2 份，winner 风格与前一个 shot 不同
16. ✅ L4 gate 不再因"段落超 800 字"报警 pulse-phase 的短段落
17. ✅ 叙述者越位检测不会误判 soft_constraint 范围内的合理表达
18. ✅ 不干预声明出现在每个 prompt 中

### Phase 1+3 实施报告 — 2026-06-21

**完成的任务**：ARCH-1, ARCH-2, ARCH-3, ARCH-6, ARCH-8, ARCH-9（共 6 个）

**修改文件清单**：

| 文件 | 改动 | 行数 |
|------|------|------|
| `services/contract_compiler.py` | 新增 hard_facts/soft_constraints/reference/deviation_budget/narrative_phase 字段透传 | +20 |
| `services/prompt_compiler.py` | 重构 `_build_shot_context()` 支持三层偏离格式 + deviation 指令 + phase 指令 + 不干预声明 | +200 |
| `services/chapter_rhythm.py` | **新建**：L1 章级节奏架构师（LLM 分配 + 7 条规则验证 + fallback） | +380 |
| `services/writer_dispatcher.py` | 新增 `dispatch_quad_track()` + `QUAD_TRACK_PERSONAS` 配置 | +180 |
| `services/architect_gate.py` | L4 段落长度检查改为 phase-aware（6 相位不同阈值） | +40 |
| `cli.py` | 集成章级节奏分析到 run 循环 + 4 路赛马替换 2 路 + rhythm 参数透传 | +50 |
| `db/schema.sql` | 新增 `writing_chapter_rhythms` 表 | +12 |
| `db/migration.py` | v6→v7 迁移（新增 chapter_rhythms 表） | +30 |
| `tests/test_chapter_rhythm.py` | **新建**：8 个测试用例覆盖 L1 架构师 | +210 |
| `tests/test_schema.py` | 新增 chapter_rhythms 表 + 索引到 ALL_TABLES/EXPECTED_INDEXES | +3 |

**测试结果**：277 passed（新增 8 个）

**关键设计决策**：

1. **三层偏离分类（ARCH-1）**：
   - `hard_facts`：事件性 beats，不可偏离
   - `soft_constraints`：情绪/氛围/距离约束，允许偏离
   - `reference`：风格方向/示例/motif 关联，不检查不约束
   - **向后兼容**：如果 YAML 没有 hard_facts，自动降级为 must_land 格式

2. **deviation_budget 指令（ARCH-2）**：
   - 5 档描述：极低/低/中等/高/极高
   - 每档明确告知 AI 什么是可以做的、什么是不能做的

3. **叙事相位参数（ARCH-3）**：
   - 6 相位 × 3 参数：paragraph_length、sensory_pressure、phase_description
   - 直接注入 prompt，AI 根据相位调整写法

4. **章级节奏 L1 架构师（ARCH-6）**：
   - LLM 分配 narrative_phase + deviation_budget
   - 7 条规则验证（无连续相同、至少 1 锚点 + 1 呼吸、均值在范围内等）
   - 最多 3 轮 LLM 重试
   - 确定性 fallback（LLM 失败时的兜底）

5. **4 路赛马（ARCH-8）**：
   - 意象师(诗意/0.95) + 节奏师(克制/0.75) + 对话师(生活化/0.85) + 结构师(极简/0.60)
   - 每路有独立的 style_injection 注入到 prompt
   - deviation_budget 影响有效温度
   - Jury 从 4 份风格显著不同的草稿中选择

6. **不干预声明（ARCH-9）**：
   - 每个 prompt 末尾固定段
   - 明确列出 5 个不检查维度：读者联想、意象选择、句子节奏、审美偏好、感官组合

7. **Phase-aware L4 gate**：
   - pulse: max 500 chars
   - chaos: max 600 chars
   - sublime: max 700 chars
   - ripple/fold: max 800 chars
   - sediment: max 1000 chars

### ARCH-12 实施报告 — 2026-06-21

**任务**：三棵树架构（契约树/故事树/执行树），数据库从扁平结构升级为 3 棵树 × 8 层标准金字塔

**核心决策**：

1. **为什么 3 棵树**：
   - **契约树**（Contract Tree）：治理之树，"应该怎么写"。版本化，设计时产物，跨 run 稳定。
   - **故事树**（Story Tree）：内容之树，"这本书里有什么"。追加式，角色状态/伏笔/时间线。
   - **执行树**（Execution Tree）：生产之树，"这次 run 干了什么"。per-run，每次重新生成。
   - 三者正交：契约可升级而不影响故事，每次 run 记录执行但不污染设计。

2. **为什么 4 张表**：
   - `tree_nodes`：三棵树共用骨架（`tree_type` 区分），`parent_id` 构成树，`node_level` 标识 L0~L7
   - `contract_versions`：契约树正文，支持版本化（`version`），支持折叠继承（`is_collapsed`）
   - `story_content`：故事��正文，含角色状态/伏笔/时间线
   - `execution_records`：执行树正文，含 prompt/草稿/质量结果

3. **8 层统一，空则占位**：
   - 《分流》展开层：L0 全书 / L2 卷 / L4 章 / L6 场景
   - 《分流》折叠层：L1 部 / L3 弧 / L5 节 / L7 段落（`is_collapsed=1`，自动继承父层）

4. **不删现有表**：27 张旧表全部保留，`tree_nodes` 等 4 张新表平行存在；277 个旧测试不受影响。

**修改文件清单**：

| 文件 | 改动 |
|------|------|
| `docs/design-3tree-architecture.md` | **新建**：三棵树架构完整设计文档 |
| `docs/design-8layer-hierarchy.md` | 更新：加入 3 棵树引用，更新第 6 节数据库存储 |
| `docs/implementation-contract-v0.md` | 更新：§3 标题改为 31 表，新增 §3.4 v8 新增表 DDL |
| `db/schema.sql` | Schema v7→v8，新增 4 张表（`tree_nodes`/`contract_versions`/`story_content`/`execution_records`） |
| `db/migration.py` | SCHEMA_VERSION 7→8，新增 `_migrate_v7_to_v8()` |
| `tests/test_schema.py` | ALL_TABLES 新增 4 表，EXPECTED_INDEXES 新增 7 索引 |
| `tasks.md` | 新增 ARCH-12 任务条目 + 本实施报告 |

**验证**：
- ✅ 全新 DB 初始化：SCHEMA_VERSION=8，4 张新表全部创建
- ✅ v7→v8 迁移：4 张新表 + 7 个新索引全部正确创建
- ✅ test_schema.py：22 passed
- ✅ test_chapter_rhythm.py：8 passed（不受影响）

### ARCH-13 实施报告 — 2026-06-23

**任务**：正文真相源锚定 — 明确 `shot_revisions.text` 为正文唯一真相源，三棵树为索引

**核心决策**：

1. **正文唯一真相源 = `shot_revisions.text`**：
   - **未封版**：正文 = `shot_revisions` 中 `revision_sequence` 最大的行（最后一次生成的版本）
   - **已封版**：正文 = `shot_revisions` 中 `is_current=1` 的行（封版锁定的版本，不再更新）
   - `shot_revisions.is_current` 被重新定义为**封版标记**（不是"当前 winner"），仅在封版时设置一次
   - `writing_shots.current_revision_id` 始终指向最新 revision（未封版 = MAX(seq)，封版后 = 封版版本）

2. **三棵树是索引，不是正文**：
   - **契约树**（`contract_versions.contract_body_json`）：存契约约束（must_land / anti_write），不存正文
   - **故事树**（`story_content.content_body_json`）：存世界状态（角色/伏笔/时间线），不存正文
   - **执行树**（`execution_records.*`）：存执行元数据（draft_ids / selected_draft），通过 `revision_id` FK 指向 `shot_revisions`，不复制正文

3. **表结构变更**：
   - `execution_records` 新增 `revision_id TEXT REFERENCES shot_revisions(revision_id)` 指针
   - 执行树通过该 FK 成为"正文的访问路径"，不再尝试复制或冗余存储正文

**修改文件清单**：

| 文件 | 改动 |
|------|------|
| `docs/design-3tree-architecture.md` | 新增 §8 正文真相源规则；更新 §10 与现有表关系表；新增 T7 决策 |
| `docs/design.md` | 更新 §9.4：三棵树表格增加"正文关系"列，新增正文真相源规则段落 |
| `docs/implementation-contract-v0.md` | 更新 `execution_records` DDL 加入 `revision_id`；新增正文真相源规则说明 |
| `db/schema.sql` | 更新 `execution_records` 表加入 `revision_id` FK 列 |
| `db/migration.py` | 更新 `_migrate_v7_to_v8()` 中 `execution_records` 创建 DDL 加入 `revision_id` |
| `tests/test_schema.py` | 新增 `TestTreeArchitecture` 类（3 个测试）：revision_id 列存在性 + 未封版/封版真相源规则 |
| `tasks.md` | 新增 ARCH-13 任务条目 + 本实施报告 |

**验证**：
- ✅ test_schema.py：25 passed（新增 3 个）
- ✅ 全量测试集：280 passed（ARCH-13 无回归）

---

### ARCH-4 实施报告：L0 全书宪法服务（2026-06-24）

**目标**：实现 L0 全书节奏治理层，从大纲源文件生成全书宪法（arc_shape、volume_map、chapter_roles、motif_lifecycle、global_deviation），经规则引擎验证后由人类确认锁定。

**设计决策**：
- L0 宪法（`writing_book_constitutions`）与 meta-contract（`writing_meta_contract`）是**两个独立产物**：前者是节奏治理参数，后者是 10 层身份/声音/边界内容
- 两者通过 `writing_meta_contract.constitution_version_id` 指针关联
- 状态生命周期：`draft → human_review → confirmed → locked`（locked 不可变）
- LLM 80% + 规则引擎 20%：LLM 生成结构，规则引擎验证完整性
- 6 条验证规则：卷数(2-6)、章节分配完整性、单峰张力弧、motif 生命周期完整、deviation_mean∈[0,1]、deviation_range 合法性

**Schema v8 → v9**：

```sql
-- 新增表
CREATE TABLE writing_book_constitutions (
    constitution_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    version INTEGER NOT NULL DEFAULT 1,
    arc_shape TEXT,
    tension_peak_chapter TEXT,
    tension_valley_chapters_json JSON,
    volume_map_json JSON,
    chapter_roles_json JSON,
    motif_lifecycle_json JSON,
    global_deviation_mean REAL,
    global_deviation_range_json JSON,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','human_review','confirmed','locked')),
    confirmed_at TEXT, locked_at TEXT,
    source_outline_hash TEXT, llm_model_ref TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(project_id, version)
);

-- 新增指针列
ALTER TABLE writing_meta_contract
ADD COLUMN constitution_version_id TEXT REFERENCES writing_book_constitutions(constitution_id);
```

**新建文件**：
- `src/inkflow/services/book_constitution.py` — `BookConstitutionService`（~330 行）
  - `generate_constitution(story_dir)` — 读源文件 → LLM → 解析 → 验证 → 存储
  - `validate_constitution(data)` — 6 条规则引擎验证
  - `update_status(id, status)` — 状态机转换
  - `lock_constitution(id)` — 锁定（不可变）
  - `get_latest_constitution()` / `get_locked_constitution()` — 查询
  - `_collect_source_materials()` — 读取 5 个 .md 源文件
  - `_build_generation_prompt()` — 构造 LLM prompt
  - `_parse_llm_response()` — 从 markdown 包裹中提取 JSON

**CLI 命令**：`ink constitution <project>`
- 默认：生成或显示已有宪法
- `--show`：仅显示当前宪法摘要
- `--confirm`：确认草稿
- `--lock`：确认并锁定

**修改文件清单**：

| 文件 | 改动 |
|------|------|
| `db/schema.sql` | 新增 `writing_book_constitutions` DDL（Layer 2）；`writing_meta_contract` 加 `constitution_version_id` 列；header 更新为 Schema v9（35 表） |
| `db/migration.py` | `SCHEMA_VERSION=9`；新增 `_migrate_v8_to_v9()` |
| `services/book_constitution.py` | 新建，~330 行 |
| `services/__init__.py` | 导出 `BookConstitutionService` |
| `cli.py` | 新增 `ink constitution` 命令（含 `_print_constitution` 格式化输出） |
| `tests/test_book_constitution.py` | 新建，28 个测试（4 类：Validation/Status/Query/Generation） |
| `tests/test_schema.py` | `ALL_TABLES` 加入 `writing_book_constitutions`；`EXPECTED_INDEXES` 加入 `idx_book_constitutions_project` |
| `docs/implementation-contract-v0.md` | DDL 段加入 `writing_book_constitutions` + `constitution_version_id` |
| `docs/design-3tree-architecture.md` | §10.1 表更新 constitution_version_id 注释 |

**验证**：
- ✅ test_book_constitution.py：28 passed（新建）
- ✅ test_schema.py：25 passed（含 `writing_book_constitutions` 存在性验证）
- ✅ Schema v9：35 张用户表 + `_schema_meta` = 36 total

---

## 文档对齐与 B35 修复 — 2026-06-24

**目标**：按当前 InkFlow 实现状态重写任务入口，把已完成任务从待办清单移入历史记录，并同步开发文档中漂移的版本、表数和实施状态。

### 已完成

| 项 | 内容 |
|----|------|
| 任务清单对齐 | 根 `tasks.md` 与 `inkflow/TASKS.md` 改为 InkFlow-only 当前待办，完成项仅保留归档索引 |
| 完成项归档 | P0、DB/LLM/CLI 修复、OPT-1~7、ARCH-1/2/3/4/6/8/9/12/13 均指向本 history |
| Bug 记录 | `docs/bugfix.md` 新增 B35/B36 |
| B35 修复 | 修复 `ink constitution <project>` 已有宪法默认展示路径的 `conststitution` 拼写错误 |
| 测试补强 | 新增 CLI smoke test 覆盖已有 L0 宪法展示路径 |
| 设计文档同步 | `design.md` 更新到 v3.12 / Schema v9 / 35 张业务表 |
| 实现契约同步 | `implementation-contract-v0.md` 顶部口径更新为 Schema v9 / 35 张业务表 |
| 悬疑引擎同步 | `suspense-engine.md` 从“待实施”改为“部分实施”，标注可靠性与 benchmark 未完成 |

### 当前设计复审结论

当前设计仍是 near-optimal，不建议推倒重做。下一步最优路径是补齐 L0.5 Volume Rhythm 和 D-25 全局重试预算/熔断器；同时避免在三棵树之外继续添加互相竞争的契约来源。

### 验证

- ✅ `tests/test_cli.py::TestConstitutionCommand`：1 passed
- ✅ `tests/test_book_constitution.py tests/test_schema.py`：53 passed
- ✅ 全量 `python -m pytest -q`：309 passed, 4 warnings

---

## 任务对齐与 CREATIVE-1 回归补强 — 2026-06-25

**目标**：对齐 `tasks.md`，把已完成的 ARCH/D25/TS/CREATIVE 项从待办区移入历史，修正 Schema 版本和表数口径，并为“产出优秀作品”的下一阶段开发补上回归测试。

### 已完成归档

| ID | 内容 | 实现位置 |
|----|------|----------|
| ARCH-5 | L0.5 `VolumeRhythmService`，生成卷部 mini-arc、章节角色、张力预算和 deviation range | `services/volume_rhythm.py`, `writing_volume_rhythms` |
| ARCH-7R | Runtime 将 L0.5 约束传入 L1 `ChapterRhythmArchitect.analyze_chapter()` | `cli.py` |
| D25-R1 | 悬疑可靠性闭环：`RetryBudgetService` + failure signature + 熔断 | `services/retry_budget.py`, `quality_controller.py`, `cli.py` |
| D25-R2 | 悬疑 benchmark：8 个人工标注样本 + jury 维度验证 | `tests/fixtures/suspense_benchmark`, `tests/test_suspense_benchmark.py` |
| B23-P1 | Prompt caching 上下文降级：完整 -> 摘要 -> 事件 -> drop + token budget 裁剪 | `services/prompt_compiler.py`, `tests/test_prompt_caching.py` |
| TS-1 | `TextRepository` 统一正文真相源读取，替换 exporter/cli/session_manager 散落 SQL | `services/text_repository.py` |
| ARCH-10 | 风格偏好学习：记录 winner persona/model/temperature/style_direction | `services/style_preference.py`, `writing_style_preferences` |
| ARCH-11 | 反契约沙盒：记录 soft-constraint 偏离的意外价值与人类裁决 | `services/anti_contract.py`, `writing_anti_contract_reviews` |
| CREATIVE-1 | Jury 新增 `unexpected_value` 意外价值维度，Schema v14 CHECK 约束同步 | `jury_service.py`, `models/enums.py`, `migration.py`, `schema.sql` |

### 本轮新增测试

| 测试 | 覆盖 |
|------|------|
| `test_blank_shot_quad_track_caps_temperature` | 留白 shot 会携带 `blank_shot=True`，且四线赛马温度上限放宽到 1.4 但不越界 |
| `test_unexpected_value_dimension_is_persisted` | 默认 Jury 评分会写入 `unexpected_value` 维度 |
| `test_jury_unexpected_value_dimension_valid` | DB CHECK 接受 `writing_jury_scores.dimension='unexpected_value'` |
| `test_indexes_exist` 扩展 | v10/v12/v13 新增索引纳入 schema 回归 |

### 文档与 Schema 口径

| 项 | 旧口径 | 新口径 |
|----|--------|--------|
| Schema 版本 | 文档混用 v9/v13，代码为 v14 | 统一为 Schema v14 |
| 表数 | 文档写 39 张业务表，测试注释写 35/37 | 统一为 38 张业务表 + `_schema_meta` 元表 |
| 当前待办 | 已完成 ARCH-5/10/11/D25 仍残留在待办描述 | `tasks.md` 只保留 CREATIVE-2/3、实战验证和评估类任务 |

### 下一阶段入口

| ID | 任务 |
|----|------|
| CREATIVE-2 | 二次精修 `polish` 阶段：基于 winner 生成精修 revision，并保留原 winner 审计链 |
| CREATIVE-3 | 留白 shot 独立创意评审：避免常规 Jury 因合规偏好压掉高光稿 |
| VAL-1 | 用真实项目跑完 `ink run`，收集文本质量、重试预算和 prompt token 数据 |

### 验证

- 目标测试：4 passed
- 全量测试：347 passed, 4 warnings

---

## CREATIVE-2 二次精修阶段 — 2026-06-25

**目标**：在 Jury winner 之后增加非阻塞 `polish` 后处理阶段。原 winner revision 必须保留；精修结果若有效，则作为 `write_polish` 子 revision 写入，并通过 `parent_revision_id` 指回原 winner。

### 核心实现

| 项 | 内容 |
|----|------|
| Schema v15 | `shot_revisions.operation` 新增 `write_polish`；`model_attempts.phase` 新增 `polish` |
| 迁移 | 新增 v14→v15，重建 `shot_revisions` 与 `model_attempts` CHECK 约束并保留旧数据 |
| 服务 | 新增 `PolishService`，执行保守精修：规范空白/标点间距、长段落按句界切分 |
| 审计链 | `write_polish` revision 的 `parent_revision_id` 指向原 `write_generate` winner revision |
| CLI 集成 | `ink run` 在绿/黄 winner 写入后尝试 polish；失败或无变化不阻塞原 winner |
| 后续读取 | 事实锚点提取和 motif 扫描使用最终 revision 文本（polish 成功则用精修文本） |

### 安全边界

- polish 不新增情节、不补硬事实、不改人物关系。
- 只有精修文本非空、长度达标且显示文本发生变化时才写新 revision。
- 原 winner revision 永远保留；polish 只是当前 revision 的子版本。
- 本轮采用本地保守精修，不依赖外部模型调用，便于稳定验证。

### 新增测试

| 测试 | 覆盖 |
|------|------|
| `tests/test_polish_service.py` | 保守精修、子 revision 写入、no-op 跳过 |
| `test_revision_operation_write_polish_valid` | Schema CHECK 接受 `write_polish` |
| `test_polish_phase_is_valid` | `model_attempts.phase` 接受 `polish` |

### 当前待办变化

CREATIVE-2 从待办移入历史。下一项高优先级为 CREATIVE-3：留白 shot 独立创意评审。

### 验证

- 目标测试：6 passed
- 全量测试：352 passed, 4 warnings

---

## CREATIVE-3 留白创意评审 — 2026-06-25

**目标**：让每 5 个 shot 的留白创作不再被常规 Jury 的合规偏好压低。留白 shot 仍写入逐维评分审计，但 winner 选择改用创意权重，提高 `unexpected_value` 与悬疑效果的影响。

### 核心实现

| 项 | 内容 |
|----|------|
| 创意权重 | 新增 `CREATIVE_BLANK_WEIGHTS`：contract 0.10、forbidden 0.10、fluency 0.20、suspense 0.25、unexpected 0.35 |
| 评分结果 | 每个 draft 保留 `trimmed_mean`、`dimension_means`、`creative_score` 和原始分 |
| winner 选择 | 标准 shot 继续按 `trimmed_mean`；留白 shot 使用 `score_key='creative_score'`、`review_mode='creative_blank'` |
| CLI 集成 | `ink run` 对留白 shot 传入 `creative_review=True`，第二轮重写也保留留白 budget、温度上限和创意评审 |
| 审计边界 | 不新增 DDL；`writing_jury_scores` 仍保存逐模型逐维评分，创意加权只影响本轮 winner 选择 |

### 新增测试

| 测试 | 覆盖 |
|------|------|
| `test_creative_review_can_choose_less_safe_high_value_draft` | 常规均分选择安全稿；留白创意评审选择更高意外价值稿 |

### 当前待办变化

CREATIVE-3 从待办移入历史。后续不再继续放宽留白机制，优先进入真实项目验证：比较标准 winner 与 creative winner 的高光率、合规风险和人工偏好。

### 验证

- 目标测试：2 passed
- 全量测试：353 passed, 4 warnings

---

## B40 Jury 配置兼容修复 — 2026-06-25

**目标**：进入 VAL-1 真实项目验证前，确保旧 `.models` 显式配置的三维 Jury 不会覆盖当前必需的 D-25/CREATIVE 维度。

### 核心实现

| 项 | 内容 |
|----|------|
| 配置兼容 | `get_jury_config()` 保留项目配置维度顺序，同时追加缺失的当前 v4 必需维度 |
| 去重 | 配置中重复出现的维度只保留第一次 |
| 真实项目影响 | 《分流》旧三维 `.models` 会在运行时自动补齐 `suspense_effectiveness` 与 `unexpected_value` |

### 新增测试

| 测试 | 覆盖 |
|------|------|
| `test_jury_config_appends_required_current_dimensions` | 旧三维配置自动补齐当前必需维度 |
| `test_jury_config_deduplicates_dimensions` | 重复维度不会重复写入 Jury 维度列表 |

### 验证

- 目标测试：2 passed
- 全量测试：355 passed, 4 warnings

---

## B41 模型调用审计 phase 扩展 — 2026-06-25

**目标**：进入 VAL-1 前确保 `model_attempts` 能覆盖所有当前真实模型调用，避免 token/调用统计缺口。

### 核心实现

| 项 | 内容 |
|----|------|
| Schema v16 | `model_attempts.phase` 新增大纲评估、全书宪法、章级节奏、卷部节奏及 retry phase |
| 迁移 | 新增 v15→v16，重建 `model_attempts` CHECK 约束并保留旧审计数据 |
| 测试 | 参数化验证所有当前架构/大纲模型调用 phase 均可插入 |

### 新增 phase

`outline_evaluate` / `constitution_generate` / `architect_chapter_rhythm` / `architect_chapter_rhythm_retry` / `architect_volume_rhythm` / `architect_volume_rhythm_retry`

### 验证

- 目标测试：14 passed, 3 warnings
- 全量测试：361 passed, 4 warnings

---

## B42 后续章节契约抽取 — 2026-06-25

**目标**：为 VAL-1 后续章节真实运行准备可靠的 `chapter_N_events`，避免第 4 章以后缺少 must_land 事件。

### 核心实现

| 项 | 内容 |
|----|------|
| 通用抽取 | 新增 `_extract_chapter_events(outline_text, chapter_number)` |
| setup 集成 | 自动抽取第一卷第 2-8 章事件，写入 `chapter_2_events` 到 `chapter_8_events` |
| 兼容 | `_extract_chapter_2_events()` 保留为包装函数 |

### 新增测试

| 测试 | 覆盖 |
|------|------|
| `test_extracts_arbitrary_chapter_events` | 可从同一大纲中抽取任意章节事件 |
| `test_chapter_2_wrapper_uses_generic_extractor` | 旧第 2 章包装函数仍可用 |

### 验证

- 目标测试：2 passed
- 全量测试：363 passed, 4 warnings

---

## VAL-1 恢复与章节 Gate 补齐 — 2026-06-26

**目标**：立即补齐三项投产前缺口：第 2 章重写链路跑通一次、章末钩子/悬念强制检查落到 gate、aborted session 的恢复和失败归因再收敛一轮。

### 核心实现

| 项 | 内容 |
|----|------|
| L3 章末钩子 | `evaluate_l3()` 读取最后一个 shot 当前正文，要求章节末尾为未完成动作/打断；失败记录 `chapter_hook_weak` |
| 失败归因 | `RetryBudgetService` 新增 `l3_violation` / `chapter_hook_weak`；L3/L4 失败写回最终 shot 的 `failure_signature_json` |
| Session 诊断 | `SessionManager.get_session_failure_summary()` 聚合 shot 失败签名和 failed gates |
| 显式恢复 | `ink resume <session_id>` 绑定指定 session；`sessions list` 展示 aborted/crashed 与失败摘要 |
| 整章重写 | `repair --chapter <key> --all` 支持把整章置回 redo，清理旧 L3/L4 gate，并激活原 session |
| 幂等恢复 | run snapshot 与 shot contract 编译可复用既有记录，支持同一 run 反复 repair/resume |
| 模型审计 | 远端模型错误也写入 `model_attempts.error_message`；jury 调用默认 45 秒超时、0 次额外重试 |
| 本地评审 | 无显式 jury models 时默认 `local-default`；新增 `run --local-jury` 用于不改 `.models` 的稳定验证 |

### 真实《分流》第 2 章验证

命令：

```powershell
python -m inkflow.cli repair "分流" --chapter v01.c02 --all
python -m inkflow.cli run "分流" --chapter v01.c02 --resume --local-jury
```

结果：

| 指标 | 结果 |
|------|------|
| 链路状态 | 完整跑完 4/4 shots，session completed |
| Scope Report | Green 0 / Yellow 0 / Red/PH 4 |
| 主要失败 | `l4_violation: must_land events may not be fully covered` |
| L3 状态 | 未触发；原因是 L4 未全 passed |
| 结论 | 工程链路可恢复、可归因、可跑完；正文质量不能投产 |

### 新增/更新测试

| 测试 | 覆盖 |
|------|------|
| `test_l3_fails_when_chapter_hook_is_closed` | 最后一镜收束/解释会让 L3 失败 |
| `test_l3_passes_when_chapter_hook_is_unfinished_action` | 未完成动作式章末钩子可通过 L3 |
| `test_failure_summary_groups_signatures_and_failed_gates` | session 失败摘要聚合失败签名和 gate |
| `test_chapter_hook_failure_type_is_recorded` | `chapter_hook_weak` 可进入 retry budget |
| `test_resume_specific_aborted_session_reuses_requested_session` | 显式恢复 aborted session 不会串到其它 session |
| `test_record_model_error_writes_attempt` | 模型错误写入 `model_attempts.error_message` |
| `test_jury_config_defaults_to_local_model` | 未显式配置 jury models 时默认本地评委 |

### 验证

- 目标测试：101 passed, 1 warning
- 全量测试：376 passed, 4 warnings

---

## QUAL-1 本地兜底质量修复与 VAL-2 复跑 — 2026-06-26

**目标**：修复第 2 章真实复跑中 4 个 shot 全部 red/placeholder 的根因，使本地兜底链路能按 prompt 落地 must_land，并让 L3 章末钩子 gate 实际触发。

### 核心实现

| 项 | 内容 |
|----|------|
| 本地 jury 路由 | 当 jury models 全部为 `local-default` 时，即使 `.models` 存在 providers，也强制使用本地启发式评分，避免误走远端 LLM 路径 |
| 本地 jury 输出 | `LocalDefaultGenerator` 对 `jury_score` 返回 JSON：`score` + `comment`，不再返回散文化正文导致解析成默认 50 分 |
| prompt-bound 生成 | 本地写手从 prompt 中提取第一句 opening、POV 约束和场景要点/must_land beats，用这些信息生成正文 |
| 章末钩子 | 对 `.s04` 兜底生成保留未完成动作式尾钩，确保 L3 章末悬念有可验证文本基础 |
| 回归测试 | 增加本地写手使用 prompt beats、本地 jury JSON 输出、providers 存在时 local-default jury 仍走启发式评分的测试 |

### 真实《分流》第 2 章复跑

命令：

```powershell
python -m inkflow.cli repair "分流" --chapter v01.c02 --all
python -m inkflow.cli run "分流" --chapter v01.c02 --resume --local-jury
```

结果：

| 指标 | 结果 |
|------|------|
| 链路状态 | 完整跑完 4/4 shots，session completed |
| Shot 结果 | s01 yellow 70.0；s02 green 90.33；s03 yellow 77.0；s04 green 88.67 |
| Scope Report | Green 2 / Yellow 2 / Red/PH 0 |
| L3 状态 | 已触发并通过 |
| POV coverage | `郑坤` / `韩教授` / `白英` / `苏然` 各 1 |
| 结论 | 工程链路、恢复、归因、章节 gate 已可用于受控生产试跑；本地兜底不代表最终文学质量 |

### 验证

- 目标测试：20 passed
- 全量测试：379 passed, 4 warnings

---

## JURY-V5 分层裁判与单线返写 — 2026-06-26

**目标**：按生产讨论将裁判流程从“混合维度平均”升级为“硬规则先过、类型职责按需启用、文学 9 维再评分”，并降低重写成本和跑偏风险。

### 核心实现

| 项 | 内容 |
|----|------|
| Schema v17 | `writing_jury_scores.dimension` 新增 `hard_rule_compliance` 与文学 9 维 |
| 硬规则裁判 | `JuryService` 先执行规则硬检；失败稿不进入类型/文学评分 |
| 类型裁判 | `suspense_effectiveness` / `unexpected_value` / `hook_transition` 只在 shot_profile 启用对应职责时打分 |
| 文学 9 维 | `language_texture`、`reading_fluency`、`scene_specificity`、`emotional_progression`、`character_believability`、`dialogue_subtext`、`pacing_control`、`motif_theme_fit`、`chapter_continuity` |
| 打分聚合 | 对 9 个文学维度均值去最高/最低后取平均，得到 `literary_score` |
| 过线数量 | 默认 `min_passing_drafts=2`；少于 2 个过线稿时触发重写 |
| 单线返写 | 已有至少 1 个过线稿时，只返写一个低分/未过线 persona；完全无过线稿时才整批重写 |
| 配置兼容 | `quality_threshold: 8.5` 自动换算为 85；旧 `jury_config.dimensions` 不再污染文学 9 维 |

### 验证

- 目标测试：74 passed, 4 warnings
- 全量测试：382 passed, 4 warnings

---

## WORKFLOW-1 公开生产流简化 — 2026-06-26

**目标**：将人类可见工作流固定为 `init → setup --chapter → run --chapter → review --chapter`，避免 `setup` 同时承担全书启动和单章校准两种含义。

### 核心实现

| 项 | 内容 |
|----|------|
| `ink init` | 承接原全书初始化：建库、导入第 1 章样章、加载 `.models`、生成 `contract-draft.yaml` |
| `ink setup --chapter` | 改为单章生产前校准：生成 `.inkflow/chapter-setups/<chapter>.yaml`，包含 shot 列表、类型职责、章末钩子、禁止议论 gate |
| `ink run --chapter` | 强制要求存在 chapter setup 包；读取 setup 包进入 run snapshot，并把禁止议论/类型职责写入实际 prompt 与裁判 profile |
| `ink review --chapter` | 记录人工验收结论到 `.inkflow/chapter-reviews/<chapter>.yaml`，作为下一章 setup 的前文人工判断 |
| 自动导出 | `run --chapter` 完成后自动导出到 `D:\_Progs\.Story\《项目》\正文\项目_章节_导出.md` |
| 兼容命令 | `confirm-contract` 保留为 init 后确认契约的兼容/内部命令 |

### 验证

- 目标测试：43 passed
- 全量测试：390 passed, 4 warnings

---

## EXPORT-2 第 3 章导出小标题清理 — 2026-06-26

**目标**：第 3 章真实导出时，移除模型正文里重复生成的 Markdown 标题，只保留导出器根据契约生成的编辑稿小节标题。

### 核心实现

| 项 | 内容 |
|----|------|
| 标题清理 | `_format_prose_for_export()` 跳过正文中的 Markdown heading block |
| 版式边界 | 保留导出器生成的 `### shot title`，继续隐藏灯色、POV、评分等管线元数据 |
| 回归测试 | 新增导出测试覆盖 `# 玻璃里的保鲜膜` 不进入审稿稿 |

### 真实《分流》第 3 章导出

`run --local-jury` 完成 5/5 shots：Green 4 / Yellow 1 / Red 0，L3 章节 Gate 通过；导出路径为 `D:\_Progs\.Story\《分流》\正文\分流_v01.c03_导出.md`。

### 验证

- 全量测试：391 passed, 4 warnings

---

## JURY-B52 章节契约准入与 hard-rule 误杀收敛 — 2026-06-27

**目标**：把第 3 章远端 jury “全 0 / 无 winner”拆清为契约失效与软件规则误杀两类问题，并在软件层防止再次拖到评分阶段才暴露。

### 核心实现

| 项 | 内容 |
|----|------|
| 契约准入 | `setup --chapter` / `run --chapter` 检查当前契约是否仍含“只生成第 N 章”旧范围限制 |
| Setup 新鲜度 | `run` 校验 setup 包的 `source_contract.meta_contract_id` 必须等于当前元契约 |
| Shot 对齐 | `run` 校验 setup shots 数量与当前 `chapter_N_events` 数量一致 |
| 旧段落锁拦截 | 生产前拒绝 `500-800 字/段落，3-4 段/shot` 旧锁，要求改为导出层短段策略 |
| Hard-rule 边界 | 远端 hard-rule jury 只清零硬事实、POV、must_land、禁写、提前揭示、提示词残留、空文/重复 |
| 风格/瞬时失败误杀保护 | 段落长度、方言、感官密度、身体时刻开场、远端 timeout/解析失败、`characters_alive` 排他误读只作为 advisory，不再 `eligible=False` |
| 默认模板 | `init` 生成的 contract-draft 移除第 2 章 P0 限定，并写入内江/外江当前方向设定 |

### 结论

第 3 章远端全 0 的直接触发是锁定契约未按章节校准；软件缺陷是 run 缺少章节契约准入，且 hard-rule jury 把风格项和远端瞬时失败提升为资格清零项。本轮修复后，契约问题会在 setup/run 前失败，规则问题由 hard-rule 边界和 advisory 保护收敛。

### 验证

- 目标测试：49 passed
- 全量测试：396 passed, 4 warnings

---

## CHAPTER-3-REMOTE / JURY-B53 远端第 3 章验证与 Gate 归因修复 — 2026-06-27

**目标**：在 B52 修复后用真实远端 writer/jury 跑通《分流》第 3 章，并把剩余的 `均分: 0` 显示问题拆清为 gate 淘汰而非远端评分失败。

### 真实《分流》第 3 章远端结果

命令：

```powershell
python -m inkflow.cli setup "分流" --chapter v01.c03 --force
python -m inkflow.cli repair "分流" --chapter v01.c03 --all
python -m inkflow.cli run "分流" --chapter v01.c03 --resume
```

结果：

| 指标 | 结果 |
|------|------|
| 链路状态 | 完整跑完 5/5 shots，session completed |
| Scope Report | Green 5 / Yellow 0 / Red/PH 0 |
| 平均得分 | 88.3 |
| L3 状态 | 已触发并通过 |
| POV coverage | `郑坤` 1 / `白英` 1 / `苏然` 2 / `韩教授` 1 |
| 导出路径 | `D:\_Progs\.Story\《分流》\正文\分流_v01.c03_导出.md` |

### 归因结论

第 5 个 shot 第二轮中出现的局部 `均分: 0` 不是远端 jury 全 0，也不是契约错章；对应草稿已有远端原始分，但因 `unexpected_value` / `hook_transition` 等类型职责低于阈值，被判定为 `eligible=False`，未进入文学 9 维 winner 竞争。旧 CLI 把这种 gate 淘汰显示为 `均分: 0`，排障语义错误。

### 核心实现

| 项 | 内容 |
|----|------|
| 失败摘要 | `JuryService` 为 hard-rule/type gate 失败稿写入 `failure_summary`，包含 stage、标签和低于阈值的维度 |
| CLI 显示 | `run` 输出改为 `未入选: 硬规则未通过/类型职责未通过`，不再把不可用稿显示成文学均分 0 |
| 回归测试 | 增加类型 gate 失败摘要测试，以及 CLI 不输出 `均分: 0` 的格式测试 |

### 验证

- 目标测试：51 passed
- 全量测试：397 passed, 4 warnings

---

## JURY-B54 远端 Jury Timeout 归因与均分隔离 — 2026-06-27

**目标**：将远端供应商 timeout/解析失败从作品质量评分中剥离，避免把基础设施失败当成类型/文学低分，并在全维度不可评时停止生产而不是重写正文。

### 核心实现

| 项 | 内容 |
|----|------|
| 失败标记 | `_score_single()` 在最终 API/解析失败时返回 `failed=True` |
| 分数隔离 | 类型/文学评分跳过 `failed=True` 的远端结果，不写入 `writing_jury_scores`，不混入 `raw_scores` / `literary_score` |
| 硬规则兼容 | hard-rule 层仍记录失败 50，用于现有 advisory 误杀保护 |
| 缺维处理 | 若类型/文学必评维度没有任何有效远端评分，草稿标记为 `jury_unavailable`，并记录缺失维度 |
| run 中止 | 若所有候选均因 `jury_unavailable` 不可评，`run` 记录 retry 归因、抛出 `ClickException`，让 session 标记为 crashed |
| 恢复归因 | `RetryBudgetService` 新增 `jury_unavailable` failure type，session 列表可汇总该失败 |

### 验证

- 目标测试：57 passed
- 全量测试：401 passed, 4 warnings

---

## PROD-CORE-HARDENING 第一批生产内核硬化 — 2026-06-27

**目标**：落实专家审阅后的“推倒 40%，保留 60%”策略，先把容易造成假封板、假导出、假评分的生产内核问题收紧。当前结论调整为：方向成立，但只能受控试跑，不能正式批量无人值守生产。

### 核心实现

| 项 | 内容 |
|----|------|
| 远端 jury 路由 | 显式配置远端 jury 时，即使 providers 为空也不静默回落本地评分；缺 provider/key 会归因为 `jury_unavailable` |
| 留白 winner | `creative_review=True` 改用 `creative_score` 和 `creative_blank` 选优语义 |
| 大纲重写 | outline regeneration 后重新读取 shot contract，避免继续使用 stale contract |
| must_land 保留 | `_update_contract()` 只更新 beats，保留 title/event 等既有字段 |
| 四轨 prompt | 意象师/节奏师/对话师/结构师分别编译 persona prompt，避免身份指令冲突 |
| L4 硬 gate | L4 在 finalize 前执行；closing/explanation/narrator/system voice 等严重问题会阻止封板、completed 计数和导出 |
| L3 硬 gate | L3 在 session complete 和自动导出前执行；未通过则停止封板/导出 |
| 导出边界 | 自动导出传入当前 `run_id`，导出器只取 `done_green/done_yellow + current_revision_id` |
| 导出版式 | Markdown/纯文本导出都剥离模型生成标题，保留正文并拆分长段，shot 间保留分隔线 |
| RetryBudget | 同类失败第 N 次立即熔断；切换 failure type 重置连续计数 |

### 当时仍未解决的 P0（已由后续章节更新）

| ID | 原因 |
|----|------|
| CORE-1 | 当时 review/reject/abort 还没有成为 DB canonical 状态机；已在 CORE-1-V18 完成 |
| CORE-2 | stable `shot_id=layer_key.sNN` 的跨 run 复用问题需要 schema/迁移级改造 |
| EXPORT-4 | 当时默认导出还未 accepted-only；已在 CORE-1-V18 完成 |

### 验证

- 语法检查：`py_compile` 通过
- 目标测试：76 passed
- 全量测试：407 passed, 4 warnings

---

## CORE-1-V18 accepted canonical 状态机 — 2026-06-28

**目标**：把人工审稿从 YAML 记录提升为 DB canonical 状态，使未人工 accepted 的章节不能进入正式导出、跨章 previous context 和历史 fact anchors。

### 核心实现

| 项 | 内容 |
|----|------|
| Schema v18 | 新增 `writing_chapter_reviews` 表，记录 `accepted/needs_revision/rejected/superseded`；同一项目/章节只允许一个 accepted run |
| `ink review` | `--accept/--revise/--reject` 写 YAML 同时写 DB；`--accept` 要求 latest run completed、所有 shot 封板且 L3 通过 |
| revise/reject | 对应 run 本章 `done_green/done_yellow` shot 退回 `redo`，防止误当正式正文 |
| 默认导出 | `ink export` 默认 `accepted_only=True`；`--draft` 才导出未 accepted 的审稿稿 |
| 自动导出 | `run --chapter` 仍导出当前 run 审稿稿，供人工 review，不代表正式正文 |
| previous context | 只读取当前 run 前序 shot 或人工 accepted 历史章节 |
| fact anchors | 只读取当前 run、accepted 章节或 locked baseline，避免 rejected/aborted/unaccepted 历史 run 污染 |

### 剩余 P0

| ID | 原因 |
|----|------|
| CORE-2 | stable `shot_id=layer_key.sNN` 的跨 run 复用问题仍需 schema/迁移级改造 |
| VALID-1 | 需要对真实《分流》库做 Schema v18 迁移和 accepted-only 导出小样验证 |

### 验证

- 语法检查：`py_compile` 通过
- 目标测试：92 passed, 3 warnings
- 全量测试：414 passed, 4 warnings

---

## CORE-2-V19 run attempt shot identity — 2026-06-28

**目标**：修复同一章节多次重写时稳定 `shot_id` 跨 run 复用的问题，使新 run 不会跳过或引用旧 run 正文。

### 核心实现

| 项 | 内容 |
|----|------|
| Schema v19 | `writing_shots` 新增 `logical_shot_id`；生产 run 的 `shot_id` 改为 `{logical_shot_id}@{run_id}` |
| 身份规则 | `logical_shot_id` 用于契约/故事定位和排序；attempt `shot_id` 用于 drafts、jury、revision、repair 等执行外键 |
| baseline 兼容 | locked human baseline 保持 `shot_id == logical_shot_id`，避免破坏第 1 章人工样章 |
| 幂等边界 | `SessionManager.create_shots()` 只在同一 `run_id + logical_shot_id` 内幂等；新 run 必须创建新 shot 行 |
| 迁移 | v18→v19 回填 `logical_shot_id = shot_id`，并创建 `idx_shots_logical` 与 `idx_shots_run_logical_unique` |
| repair 边界 | `repair --chapter --all` 限定当前章节 latest run，避免多 run 同逻辑 shot 时误匹配旧 run |
| status 可视化 | `ink status` 显示章节 latest run 与 canonical 状态，帮助区分审稿稿和正式稿 |

### 结论

CORE-2 已完成。生产内核不再有已知 P0 代码阻塞；本轮已通过全量回归和真实《分流》库 v19 迁移/status 检查。后续正式正文仍以每章人工 accepted 为准。

### 验证

- 语法检查：`py_compile` 通过
- 目标测试：161 passed, 3 warnings
- 全量测试：428 passed, 4 warnings
- 真实库检查：`ink status "分流"` 通过；`_schema_meta.version=19`，`logical_shot_id` 无空值，`idx_shots_run_logical_unique` 存在

---

## BOOKRUN-1-V20 全书/整卷编排层 — 2026-06-28

**目标**：支持“一次启动全书/整卷生产，质量不好的章节后续集中返工”，但不走单 prompt 全书生成；内部继续复用既有逐章 `setup -> run -> gate -> export` 生产线。

### 核心实现

| 项 | 内容 |
|----|------|
| Schema v20 | 新增 `writing_book_runs` 与 `writing_book_run_chapters`，记录批次范围、逐章状态、run_id、失败原因和导出路径 |
| CLI | 新增 `ink run-book <project> --from v01.c04 --to v01.c32` 与 `ink book-report <project>` |
| 安全执行 | `run-book` 串行逐章执行；默认单章失败即停止，`--continue-on-fail` 才继续 |
| 计划模式 | `--plan-only` 只创建/显示批次计划，不调用模型 |
| 草稿上下文 | 同一 `book_run` 已完成的前序 draft 章节可作为后续章节临时上下文和 fact anchors |
| 正式边界 | 默认正式导出、跨批次上下文和正式事实仍只认 accepted canonical |
| 可视化 | `ink status` 展示最近 book run；`book-report` 列出待人工审稿和待返工章节 |

### 结论

已具备全书/整卷编排生产的工程骨架。后续真实投产建议先用 `run-book --plan-only` 检查章节范围，再小批量运行 2-3 章，确认模型成本、上下文连续和返工体验后扩展到整卷。

### 验证

- 语法检查：`py_compile` 通过
- 目标测试：101 passed, 3 warnings
- 全量测试：434 passed, 4 warnings
- 真实库检查：已备份 `inkflow.db.bak-v20-20260628`；`ink status "分流"` 通过；`_schema_meta.version=20`
- 真实 plan-only：`ink run-book "分流" --from v01.c04 --to v01.c06 --plan-only` 创建 book_run `01KW6JNB3ZR52F2036YH9BDAJB`，3 个 planned chapter；`book-report` 通过

---

## CONTENT-GATE-1 第 3 章审稿缺陷硬化 — 2026-06-28

**触发**：人工审阅第 3 章导出稿时发现四类问题：标题边界错位、废弃角色名“阿坤”、未经契约授权的医疗/请假/诊断细节、以及 `慢下来` 作为独立标题场景过短。

### 核心实现

| 项 | 内容 |
|----|------|
| 导出标题 | `export_markdown()` 从 `must_land_json.title`、beats 首行、`contract_json.must_land.title` 多级回退，避免 outline 重写后 title 丢失 |
| 角色名一致性 | 新增 `utils.character_names`；当正式角色为郑坤且阿坤不是正式角色时，`阿坤` 视为废弃旧称 |
| 契约准入 | `confirm-contract`、`setup/run` 前置检查会拒绝契约或 setup 包中的废弃旧称 |
| L4 gate | 正文中出现废弃旧称直接硬失败；医疗诊断、社区医院、请假、手术、派单量增长等高影响事实若未在契约中出现，也硬失败 |
| L3 gate | 有标题的 shot 必须具备最低场景重量；章末 hook 如果作为独立标题场景，过短则章节不通过 |
| 真实项目配置 | 已清理《分流》`contract-draft.yaml` 和 `chapter-setups/v01.c03.yaml` 中的“阿坤”残留 |

### 结论

第 3 章这版审稿稿不能 accept，应记录为退稿/返修后按新 gate 重跑。链路可运行不等于文学稿可投产；人工审稿发现的问题已下沉为程序不变量。

### 验证

- 语法检查：`py_compile` 通过
- 目标测试：68 passed
- 全量测试：440 passed, 4 warnings

---

## DESIGN-REVIEW-20260629 Contract-first 生产线重校准

**触发**：第 3 章人工审稿和“直写 vs 管线”对比复盘显示，旧管线跑通不代表质量可靠。大纲门禁没有真正拦住契约违规，赛马评估可能选出语言较顺但事实违约的稿。

### 核心结论

| 项 | 结论 |
|----|------|
| 设计是否推倒重来 | 不推倒 DB / CLI / accepted canonical / book_run / Jury 资产；重做上游 contract-first gate |
| 关键缺陷 | 先文学 PK、后发现硬事实问题，顺序错误 |
| 新原则 | 大纲和草稿先判资格，只有 eligible 才进入文学 PK |
| 投产口径 | 正式投产结论重新打开；P0 gate 落地并通过真实章节验证前只做受控试跑 |

### 新权威流程

```text
setup 编译 fact_manifest
  → Outline A/B 串行生成
  → Outline Hard Gate
  → eligible outline PK
  → winning outline 编译 shot task card
  → Draft 串行生成
  → Draft Eligibility Gate
  → eligible draft literary jury
  → L4/L3 gate
  → 导出审稿稿
  → 人工 review
```

### 新 P0 任务

| ID | 内容 |
|----|------|
| FACT-MANIFEST-1 | setup 生成 allowed facts、forbidden expansions、must_land anchors、POV 边界、数字锁、hook 要求和 editorial intent |
| OUTLINE-GATE-1 | 大纲硬门禁，不合格大纲不得进入 PK |
| TASK-CARD-1 | 从胜出大纲编译 shot task card |
| DRAFT-ELIGIBILITY-1 | 草稿资格门禁，不合格草稿不得进入文学 jury |
| FAIL-ATTR-2 | 统一失败归因为 contract_conflict / outline_gap / task_card_gap / writer_drift / gate_false_positive / model_failure |

---

## NOVELIX-RESEARCH-1 外部系统研究 — 2026-06-29

**目标**：学习 `github.com/zxerai/novelix`，提炼对 InkFlow 管线优化有用的设计。

### 观察

Novelix 的有价值部分不是 agent 数量，而是把章节生产拆成稳定工件：7 个 truth files、chapter memo、context package、rule stack、review/revise cycle、state validator、snapshot/rollback 和 Studio 观测面。

### 对 InkFlow 的启发

| Novelix 做法 | InkFlow 迁移建议 |
|--------------|------------------|
| 7 个 truth files | DB3 仍是真相源，但可生成可读 truth 投影 |
| chapter memo 每段必须在正文留下痕迹 | setup 输出 fact_manifest，must_land 改为可定位 anchor |
| ContextPackage 按相关性挑上下文 | previous context / accepted anchors / book_run draft context 合成可审计 context package |
| RuleStack 分 hard / soft / diagnostic | contract-first gate 明确硬事实、软表达、诊断提示三层 |
| audit → revise → reassess | outline/draft 重写要有轮次上限、净提升判断和失败归因 |
| state validator | 正文封板前检查状态变化是否被正文支持 |

### 产物

- 新增 `docs/research-novelix.md`
- 更新 `tasks.md`
- 更新 `docs/design.md`
- 更新 `docs/flow.md`
- 更新 `docs/setup-protocol.md`
- 更新 `docs/design-evaluation-conclusion.md`
- 更新 `docs/implementation-contract-v0.md`
- 更新 `docs/role-system.md`
