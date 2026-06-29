# InkFlow v3.12 — Bug 记录

> 记录开发过程中发现和修复的 bug
> ARCH-13（2026-06-24）补充：`shot_revisions.is_current` 字段语义更新为"封版标记"（见 B19 注）
> ARCH-4（2026-06-24）：Schema v8→v9，新增 `writing_book_constitutions` 表 + `writing_meta_contract.constitution_version_id` 指针列
> 2026-06-26/27 VAL/QUAL/JURY 修复：新增 B43-B54；2026-06-29 contract-first 设计缺陷归因：新增 B65-B69；开放实现任务见 `../tasks.md`

---

## 第十轮：v21 全程审计半重构（2026-06-29）

### B70. Gate1 通过稿审计结果被清空 ✅ 已修复
- **严重性**: Critical
- **根因**: `QualityController.gate1_check()` 先写入 `gate1_result_json`，随后 `WriterDispatcher.mark_draft_usable()` 在未传入 gate1_result 时把该字段覆盖为 NULL。
- **影响**: 真实库中大量 `is_usable=1` 的草稿无法审计 Gate1 当时是否通过以及通过原因。
- **修复**: `mark_draft_usable()` 只更新 `is_usable`；只有显式传入 gate1_result 时才更新 JSON。
- **文件**: `writer_dispatcher.py`, `tests/test_core_services.py`

### B71. 只有分散业务表，缺少统一阶段事件链 ✅ 已修复
- **严重性**: Critical
- **根因**: 契约、prompt、draft、jury、gate 各自有表，但没有统一事件表连接阶段输入、输出、状态和失败类别。
- **影响**: 能看到末端失败，不能稳定还原“setup → outline → prompt → writer → jury → gate → review”的因果链。
- **修复**: Schema v21 新增 `writing_audit_events`，关键阶段开始写事件。
- **文件**: `schema.sql`, `migration.py`, `audit_recorder.py`, `cli.py`, `architect_gate.py`, `jury_service.py`, `prompt_compiler.py`, `writer_dispatcher.py`

### B72. setup 包和上下文注入不是一等审计记录 ✅ 已修复
- **严重性**: Important
- **根因**: run snapshot 只保存 setup 路径和概要；`writing_context_snaps` 表存在但没有写入路径。
- **影响**: 质量差时无法确认是否因章前校准包、前文上下文或事实锚点注入导致写偏。
- **修复**: 新增 `writing_setup_snapshots`；Prompt 编译时写 `writing_context_snaps`；setup/run 记录 setup 快照事件。
- **文件**: `schema.sql`, `migration.py`, `audit_recorder.py`, `cli.py`, `prompt_compiler.py`

### B73. model_attempts 只存 hash，无法完整复盘模型调用 ✅ 已修复
- **严重性**: Important
- **根因**: `model_attempts` 只记录 prompt/response hash 和 usage。
- **影响**: jury 误判、模型输出异常、prompt 漂移无法从 DB 直接复现。
- **修复**: Schema v21 为 `model_attempts` 新增 `request_prompt_text` 和 `response_text`；远端与本地模型调用统一写完整文本。
- **文件**: `schema.sql`, `migration.py`, `model_client.py`, `tests/test_model_client.py`

### B74. 被拒稿和失败重试缺少结构化归因 ✅ 已修复
- **严重性**: Critical
- **根因**: jury 返回的 rejected score 和 retry failure signature 主要停留在运行期 JSON/控制台输出，缺少一等 DB 归因表。
- **影响**: “质量不好”时只能看到分数或 L4 问题，不能稳定区分 outline_gap、writer_drift、jury_failure、model_failure 等。
- **修复**: 新增 `writing_draft_eligibility` 与 `writing_failure_attributions`；Gate1/Gate2/Jury/Outline/L3/L4/Retry 写入资格记录和失败归因。
- **文件**: `schema.sql`, `migration.py`, `audit_recorder.py`, `quality_controller.py`, `jury_service.py`, `outline_evaluator.py`, `architect_gate.py`, `retry_budget.py`

---

## 第一轮 (2026-06-17)

### B1. smart_redo permanent_red 不可达
- **严重性**: Critical
- **发现**: 服务专家 + 架构专家 + QA专家 (3 人重复发现)
- **根因**: `schema.sql` CHECK 约束 `redo_attempt BETWEEN 0 AND 2`，代码检查 `current_attempt >= 3`，永远 False
- **修复**: CHECK 改为 `BETWEEN 0 AND 3`
- **文件**: `schema.sql`, `quality_controller.py`

### B2. import-baseline 重复运行数据翻倍
- **严重性**: Critical
- **发现**: CLI专家
- **根因**: `_import_shot` 无条件 INSERT，不检查已有 shot；`import_chapter` 每次生成新 run_id
- **修复**: `_import_shot` 添加 `(run_id, layer_key, shot_index)` 查重；`import_chapter` 复用已有 run_id
- **文件**: `baseline_importer.py`

### B3. Migration 失败后 force-mark 到当前版本
- **严重性**: Critical
- **发现**: DB专家
- **根因**: 迁移失败后 `set_schema_version(conn, SCHEMA_VERSION)` 强制标记，部分执行状态被标记为"已完成"
- **修复**: 删除强制标记逻辑，保留在最后一个成功版本
- **文件**: `migration.py`

### B4. Backup 使用 shutil.copy2 对 WAL 不安全
- **严重性**: Critical
- **发现**: DB专家
- **根因**: WAL 模式数据分布在 .db, .db-wal, .db-shm，shutil.copy2 仅拷贝 .db
- **修复**: 改用 SQLite Online Backup API (`src.backup(dst)`)
- **文件**: `backup.py`

### B5. _build_previous_shots 边界计算错误
- **严重性**: Important
- **发现**: 服务专家
- **根因**: 使用 `len(original)` 而非 `len(window)` 判断摘要/全文边界；>5 shots 时最近 2 个也只显示摘要
- **修复**: `i >= len(window) - 2`
- **文件**: `prompt_compiler.py`

### B6. detect_conflicts 不过滤 run_id
- **严重性**: Important
- **发现**: 服务专家
- **根因**: 同 anchor_key 不同 run 的值被误报为 explicit_contradiction
- **修复**: 查询加 `AND run_id = ?`
- **文件**: `fact_anchor_extractor.py`

### B7. _execute_schema 不处理内联注释
- **严重性**: Important
- **发现**: DB专家
- **根因**: 仅过滤行首 `--`，行内 `col TEXT, -- comment` 破坏 SQL
- **修复**: 添加 `_strip_inline_comment()` 函数
- **文件**: `connection.py`

### B8. open_db 不设置 row_factory
- **严重性**: Important
- **发现**: 测试失败排查
- **根因**: `open_db()` 不设 `row_factory = sqlite3.Row`，通过 `open_db` 打开的连接返回 tuple 而非 Row
- **修复**: 在 `open_db()` 中添加 `conn.row_factory = sqlite3.Row`
- **文件**: `connection.py`

### B9. _split_statements 不处理字符串内分号
- **严重性**: Minor
- **发现**: DB专家
- **根因**: 仅追踪括号深度，不追踪字符串边界
- **修复**: 添加 `in_string` 状态追踪 + `''` 转义处理
- **文件**: `connection.py`

### B10. baseline_importer 硬编码 snapshot_hash
- **严重性**: Minor
- **发现**: 架构专家
- **根因**: `snapshot_hash = 'baseline_hash'` 硬编码，破坏完整性验证
- **修复**: 改用 `text_hash_normalized(shot["text"])`
- **文件**: `baseline_importer.py`

### B11. _estimate_tokens 中文估算偏低
- **严重性**: Minor
- **发现**: 服务专家
- **根因**: 中文按 `/1.5` 估算，实际约 `/1.2`
- **修复**: 改为 `/1.2`
- **文件**: `prompt_compiler.py`

### B12. _has_excessive_repetition 仅检查 trigram
- **严重性**: Minor
- **发现**: 服务专家
- **根因**: docstring 说 2-6 字符，但代码仅检查 3-gram
- **修复**: 扩展为 `range(2, 7)` 循环检查
- **文件**: `quality_controller.py`

---

## 第二轮 (2026-06-17)

> 5 位专家审查发现 58 项问题，已全部修复。摘要见 `docs/history.md` 第二轮记录。

---

## 第三轮 P0 纵向闭环审阅 (2026-06-18)

> 4 个专家视角审阅当前开发文档与实现。结论：设计接近最优，但实现仍有 P0 阻塞 bug。

### B13. setup 无法形成 confirmed 契约
- **严重性**: Critical
- **发现**: 架构/运行期审阅
- **根因**: `ink setup` 只创建 `draft` 元契约并提示人工确认，但 CLI 没有提供确认命令；`ink run` 又要求 confirmed/locked 契约。
- **影响**: 标准用户路径 `import-baseline → setup → run` 会停在契约未确认状态，P0 无法端到端执行。
- **修复建议**: 增加 `ink confirm-contract <project>`，或在 P0 setup 中完成最小确认流程并记录审计。
- **文件**: `cli.py`, `contract_compiler.py`
- **✅ 已修复**: 新增 `ink confirm-contract <project>` 命令，支持 `--lock` 选项。4 tests added.

### B14. writer race 仍是短占位文本，Gate1 必然失败
- **严重性**: Critical
- **发现**: LLM/质量审阅
- **根因**: `WriterDispatcher.dispatch_race()` 生成 `"[{persona} 生成中...]"`，而 Gate1 要求正文至少 50 字。
- **影响**: `ink run` 无法产出可用正文，只会进入 Smart-Redo；P0 第 2 章生成闭环不可交付。
- **修复建议**: 增加最小 `ModelClient` 适配层，P0 支持 `local-default` 可控长文本生成；真实模型调用后续接入同一接口。
- **文件**: `writer_dispatcher.py`, `quality_controller.py`
- **✅ 已修复**: 新增 ModelClient 协议 + LocalDefaultGenerator（≥200字确定性输出），WriterDispatcher 接入。7 tests added.

### B15. Jury 分制与灯色阈值冲突
- **严重性**: Critical
- **发现**: LLM/质量审阅
- **根因**: `writing_jury_scores.score` schema 为 0-10，`JuryService` stub 固定给 7 分，但灯色阈值使用 green≥85 / yellow≥65。
- **影响**: 即使候选通过 Gate1，也会因分制不一致被判 red。
- **修复建议**: 统一为 0-100 总分，或将阈值改为 8.5/6.5 并调整类型与文档。
- **文件**: `schema.sql`, `jury_service.py`, `quality_controller.py`, `models/enums.py`, `implementation-contract-v0.md`
- **✅ 已修复**: Schema 改为 0-100；JuryService 默认 70 分；新增 score_override 支持测试构造三种 verdict。7 tests added.

### B16. `run` 将黄灯也覆盖成 `done_green`
- **严重性**: Critical
- **发现**: 运行期审阅
- **根因**: `quality_controller.finalize_shot()` 已根据 gate2 设置 done_green/done_yellow/placeholder，随后 CLI 又调用 `mgr.update_shot_status(shot_id, "done_green", light_status=light)`。
- **影响**: DB 可出现 `shot_status='done_green'` 且 `light_status='yellow'` 的不一致状态。
- **修复建议**: 删除 CLI 二次覆盖，或用 `light_status` 映射正确状态。
- **文件**: `cli.py`
- **✅ 已修复**: 删除 cli.py 中二次覆盖代码，统一由 finalize_shot 处理状态。1 test added (test_yellow_status_preserved).

### B17. Fact Anchor 提取仍为空实现
- **严重性**: Critical
- **发现**: 数据/一致性审阅
- **根因**: `FactAnchorExtractor.extract()` 直接返回空列表。
- **影响**: 文档要求的绿/黄 Shot 自动提取 9 类事实锚点不存在；后续 prompt 事实约束、冲突检测、Chesil 导入都缺数据。
- **修复建议**: P0 先实现三类最小锚点（人物状态、地点/物品、事件），并在下一 Shot prompt 注入。
- **文件**: `fact_anchor_extractor.py`, `cli.py`, `prompt_compiler.py`
- **✅ 已修复**: 实现 3 类关键词提取；CLI 集成提取（绿/黄 shot）+ 下一 shot 注入。8 tests added.

### B18. locked human_baseline 只有约定，没有防改保护
- **严重性**: Important
- **发现**: 数据/一致性审阅
- **根因**: baseline 导入把 revision 标记为 `writer_persona='human_baseline'` 和 `gate_result_json.locked=true`，但 DB 和服务层没有阻止后续 current revision 被替换。
- **影响**: 第 1 章人工样章可能被后续代码误改，违反 P0 边界。
- **修复建议**: 为 baseline 增加应用层保护和审计；必要时扩展 revision operation 为 `human_baseline`。
- **文件**: `baseline_importer.py`, `session_manager.py`, `schema.sql`

### B19. current revision 缺少硬一致性约束
- **严重性**: Important
- **发现**: 数据/一致性审阅
- **根因**: `writing_shots.current_revision_id` 没有 FK，`shot_revisions` 没有 `shot_id WHERE is_current=1` 唯一约束。
- **影响**: 可能出现 current 指向不存在 revision，或同一 shot 多个 current revision。
- **修复建议**: 增加 partial unique index，并在服务层校验 `current_revision_id`。
- **文件**: `schema.sql`, `session_manager.py`
- **ARCH-13 更新 (2026-06-24)**: 字段 `is_current` 语义已重新定义为**封版标记**（不是"当前 winner"）——只在封版时设置一次，之后不再随新生成而更新。未封版时正文通过 `MAX(revision_sequence)` 查询；封版后通过 `is_current=1` 查询。详见 `design-3tree-architecture.md` §8。

### B20. implementation-contract 与 schema/tests 已漂移
- **严重性**: Important
- **发现**: 架构/数据审阅
- **根因**: `implementation-contract-v0.md` 仍有旧约束，如 `redo_attempt BETWEEN 0 AND 2`，实际 schema 为 0-3；`writing_meta_contract.project_id`、`writing_project_config.project_id` 的 UNIQUE 口径也不一致。
- **影响**: 后续迁移和测试会围绕不同权威口径反复冲突。
- **修复建议**: 先确定 schema 权威，再同步 implementation contract、tests、history。
- **文件**: `implementation-contract-v0.md`, `schema.sql`, `tests/test_schema.py`

### B21. fact anchor 唯一键与 POV/更新语义冲突
- **严重性**: Important
- **发现**: 数据/一致性审阅
- **根因**: `UNIQUE(project_id, anchor_key, run_id)` 会阻止同一 run 同 key 的后续事实更新或 POV 差异记录。
- **影响**: 设计中的“新增锚点 / 更新锚点 / 确认锚点 / POV-dependent 冲突”难以落库。
- **修复建议**: 为 fact anchor 增加版本/状态语义，或把唯一键调整为更贴合 source/pov/revision 的组合。
- **文件**: `schema.sql`, `fact_anchor_extractor.py`

### B22. 缺少 idempotency_key / usage 审计落库
- **严重性**: Important
- **发现**: 架构/数据审阅
- **根因**: 文档要求所有外部模型调用和 DB 写入有 `attempt_id` / `idempotency_key`，且成本只记录 usage；当前 schema 只有分散的 `attempt_id`，没有统一调用审计。
- **影响**: 恢复、重放、费用追踪和模型调用排障不可审计。
- **修复建议**: 增加 `model_attempts` 或等价审计表，记录 idempotency_key、phase、model、request/response hash、usage。
- **文件**: `schema.sql`, `writer_dispatcher.py`, `jury_service.py`, `fact_anchor_extractor.py`

### B23. Prompt 编译缓存降级策略未真正实现
- **严重性**: Minor
- **发现**: LLM/提示词审阅
- **根因**: `compile_static_prefix()` 只返回 `cacheable` 标志；超过 4096 tokens 时没有按文档拆分缓存段或摘要模式。
- **影响**: 长契约项目会失去文档承诺的 Prompt Caching 行为。
- **修复建议**: P0 可先记录 warning；Phase 1 再实现拆段与摘要降级。
- **文件**: `prompt_compiler.py`

---

## 第四轮 (2026-06-21)

### B24. repair 命令 SELECT 缺少 `redo_attempt` 列 ✅ 已修复
- **严重性**: Critical
- **发现**: 代码审查
- **根因**: `cli.py` repair 命令只 SELECT 了 `shot_id, shot_index, layer_key, light_status` 4 列，但后面访问 `shot["redo_attempt"]` 导致 KeyError。
- **修复**: 查询增加 `redo_attempt` 列。
- **文件**: `cli.py`

### B25. `compile_static_prefix()` 返回 dict 有重复 `"cacheable"` key ✅ 已修复
- **严重性**: Minor
- **发现**: 代码审查
- **根因**: 返回 dict 中 `"cacheable"` 写了两次，第一次用局部变量 `cacheable`，第二次用表达式 `prefix_length <= CACHE_BREAKPOINT_LIMIT`。第二个覆盖第一个，语义等价但代码意图不清晰。
- **修复**: 删除重复行，直接使用 `CACHE_BREAKPOINT_LIMIT` 常量。
- **文件**: `prompt_compiler.py`

### B26. test_llm6_context_window_order 断言与当前 prompt 格式不匹配 ✅ 已修复
- **严重性**: Minor
- **发现**: 测试失败排查
- **根因**: 测试查找 "当前 Shot 契约" / "前文上下文" 但代码使用 "必须落地" / "前文摘要"。section 标题变更后测试未同步更新。
- **修复**: 更新测试断言匹配当前 prompt 格式；移除已废弃的 N-3~N-5 摘要排序断言。
- **文件**: `tests/test_prompt_compiler.py`

### B27. test_all_tables_exist 缺少 `writing_outline_evaluations` ✅ 已修复
- **严重性**: Minor
- **发现**: 测试失败排查
- **根因**: v4 migration 新增了 `writing_outline_evaluations` 表但 `ALL_TABLES` 列表未更新。
- **修复**: 添加 `writing_outline_evaluations` 到 `ALL_TABLES`。
- **文件**: `tests/test_schema.py`

---

## 第五轮 (2026-06-21) — 生产流水线评估修复

### B28. previous_shots 只用 baseline，忽略已生成内容 ✅ 已修复
- **严重性**: Critical
- **发现**: 生产流水线全面评估
- **根因**: `_run_project_inner` 中 prompt 编译的 `previous_shots` 始终硬编码为 `baseline_shots[:2]`，不管当前 run 已生成了几个 shot。Shot 3 看不到 Shot 2 的内容，跨 shot 叙事连贯性完全断裂。
- **修复**: 新增 `_build_previous_context()` 函数，优先从当前 run 的已完成 shot 中取最后 2 个 revision 文本，首 shot 回退到 baseline 末尾。
- **文件**: `cli.py`

### B29. resume 不跳过已完成 shot → 覆盖已有成果 ✅ 已修复
- **严重性**: Critical
- **发现**: 生产流水线全面评估
- **根因**: `_run_project_inner` 的 per-shot 循环没有任何 shot 状态检查。崩溃后 resume 会重新生成已 `done_green`/`done_yellow` 的 shot，覆盖已有 revision。
- **修复**: 在循环开头添加 shot 状态检查，`done_green`/`done_yellow` 直接 skip。
- **文件**: `cli.py`

### B30. MotifTracker 密度追踪完全未集成 ✅ 已修复
- **严重性**: Critical
- **发现**: 生产流水线全面评估
- **根因**: `generate_motif_task()` 被调用了，但 `record_instance()` 和 `update_density_after_shot()` 从未被调用。所有 motif 的 `density_status` 永远是 gray，`current_count` 永远是 0。
- **修复**: 新增 `MotifTracker.scan_and_record()` 方法，在生成文本中扫描 motif 关键词并自动记录；在 main loop 的锚点提取之后集成调用。
- **文件**: `motif_tracker.py`, `cli.py`

### B31. motif_tracker.py 三重 import + 双重常量 ✅ 已修复
- **严重性**: Minor
- **发现**: 代码审查
- **根因**: `from inkflow.models.enums import EvolutionPhase, DensityStatus` 写了 3 次，`DEFAULT_MOTIF_DENSITY_PER_100 = 10` 写了 2 次。
- **修复**: 删除重复，保留各 1 份。
- **文件**: `motif_tracker.py`

### B32. brilliance_level / badsmell_level 从未填充 ✅ 已修复
- **严重性**: Medium
- **发现**: 生产流水线全面评估
- **根因**: `finalize_shot()` 调用时 `brilliance_level` 和 `badsmell_level` 始终为 None，schema 中这两个字段闲置。
- **修复**: 新增 `_compute_brilliance_level()` 和 `_compute_badsmell_level()` 映射函数，从 jury score 自动计算。
- **文件**: `cli.py`

### B33. _generate_contract_draft 在 db.close() 之后调用 ✅ 已修复
- **严重性**: Minor
- **发现**: 代码审查
- **根因**: `setup` 命令中 `db.close()` 在 `_generate_contract_draft()` 之前，如果未来 contract draft 生成需要访问 DB 会崩。
- **修复**: 移动 `db.close()` 到 `_generate_contract_draft()` 调用之后。
- **文件**: `cli.py`

### B34. 大纲评估异常处理过于宽泛 ✅ 已修复
- **严重性**: Minor
- **发现**: 代码审查
- **根因**: `except Exception` 捕获所有异常（包括编程错误如 `AttributeError`），应只捕获可恢复的异常。
- **修复**: 改为 `except (ModelCallError, ValueError, KeyError)`。
- **文件**: `cli.py`

---

## 第六轮 (2026-06-24) — 任务/文档对齐审阅

### B35. `ink constitution <project>` 已有宪法默认展示路径崩溃 ✅ 已修复
- **严重性**: Critical
- **发现**: 任务与开发文档对齐审阅
- **根因**: `cli.py` 默认分支中调用 `_print_constitution(conststitution)`，变量名拼写错误；当项目已有 `writing_book_constitutions` 记录且用户直接运行 `ink constitution "分流"` 时会触发 `NameError`。
- **影响**: L0 全书宪法 CLI 的“已有则展示”路径不可用，ARCH-4 的人工复核流程会中断。
- **修复**: 改为 `_print_constitution(constitution)`；新增 CLI smoke test 覆盖已有宪法展示。
- **文件**: `src/inkflow/cli.py`, `tests/test_cli.py`

### B36. 任务/设计文档版本、表数与实施状态漂移 ✅ 已修复
- **严重性**: Important
- **发现**: 任务与开发文档对齐审阅
- **根因**: `tasks.md`、`inkflow/TASKS.md`、`design.md`、`implementation-contract-v0.md`、`suspense-engine.md` 分别停留在 v3.6/v3.9、Schema v3/v8、31/32/35 表、待实施/已实施等不同口径。
- **影响**: 后续开发可能把已完成 ARCH-4/12/13 当成待办，或按旧 Schema 表数实现迁移和测试。
- **修复**: 根任务文件和 InkFlow 任务文件重写为当前待办；设计/实现契约/悬疑引擎文档同步到 Schema v9 / 35 表 / 部分实施状态；完成项统一指向 `docs/history.md`。
- **文件**: `tasks.md`, `TASKS.md`, `docs/design.md`, `docs/implementation-contract-v0.md`, `docs/suspense-engine.md`, `docs/design-evaluation-conclusion.md`, `src/inkflow/db/schema.sql`

---

## 第七轮 (2026-06-25) — Schema v14 / CREATIVE 对齐

### B37. Schema 版本与表数口径再次漂移 ✅ 已修复
- **严重性**: Important
- **发现**: 任务对齐与全量验证复核
- **根因**: `migration.py` 已是 `SCHEMA_VERSION = 14`，但 `schema.sql` 文件头仍写 Schema v9 / 35 business tables；`tasks.md`、`design.md`、`implementation-contract-v0.md`、`design-evaluation-conclusion.md` 又写 Schema v13 / 39 张业务表。实际为 38 张业务表，加 `_schema_meta` 后 SQLite 用户表总数为 39。
- **影响**: 后续迁移、测试和文档会围绕不同表数实现，尤其容易把 `_schema_meta` 误算为业务表。
- **修复**: 统一文档和 schema 文件头为 Schema v14 / 38 张业务表 + `_schema_meta` 元表；`tasks.md` 改为当前待办入口；`tests/test_schema.py` 注释改为 38 张业务表。
- **文件**: `tasks.md`, `docs/history.md`, `docs/design.md`, `docs/implementation-contract-v0.md`, `docs/design-evaluation-conclusion.md`, `src/inkflow/db/schema.sql`, `tests/test_schema.py`

### B38. CREATIVE-1 与留白 shot 缺少直接回归测试 ✅ 已修复
- **严重性**: Minor
- **发现**: 后续开发入口复核
- **根因**: `unexpected_value` 已进入 Jury 维度和 Schema CHECK，CLI 也已实现每 5 个 shot 的留白 budget/temp 机制，但测试只间接覆盖，无法防止后续重构悄悄移除该能力。
- **影响**: 创作质量链路可能退回“只偏合规”的安全评分，或留白 shot 温度上限失效而无人发现。
- **修复**: 新增测试验证 `unexpected_value` 会落库、Schema CHECK 接受该维度、`dispatch_quad_track(blank_shot=True)` 会返回留白标记并将温度上限放宽到 1.4；同时把 v10/v12/v13 新增索引纳入 schema 回归。
- **文件**: `tests/test_core_services.py`, `tests/test_jury_scoring.py`, `tests/test_schema.py`

### B39. CREATIVE-3 已实现但权威文档仍停留在 CREATIVE-2 / 旧 Jury 维度 ✅ 已修复
- **严重性**: Important
- **发现**: CREATIVE-3 收尾复核
- **根因**: `jury_service.py` 已支持 `creative_review=True`、`creative_score` 和留白权重，但 `design.md`、`implementation-contract-v0.md`、`design-evaluation-conclusion.md` 未同步；实现契约中的 `writing_jury_scores.dimension` DDL 仍只列旧 9 维，模型协议示例仍写旧 0-10 评分。
- **影响**: 后续开发可能按旧 DDL/协议实现 Jury 或迁移，遗漏 `suspense_effectiveness`、`unexpected_value` 与 CREATIVE-3 选稿逻辑。
- **修复**: 更新设计、实现契约、评估结论和历史归档；实现契约改为当前 0-100、默认 3 模型 × 5 维评分口径，并记录留白 shot 使用 `creative_score` 选 winner。
- **文件**: `docs/design.md`, `docs/implementation-contract-v0.md`, `docs/design-evaluation-conclusion.md`, `docs/history.md`, `docs/role-system.md`, `src/inkflow/services/jury_service.py`, `src/inkflow/utils/config.py`, `tests/test_core_services.py`

### B40. 旧 `.models` 显式三维 Jury 配置会禁用 D-25/CREATIVE 维度 ✅ 已修复
- **严重性**: Important
- **发现**: VAL-1 真实项目验证前检查
- **根因**: `get_jury_config()` 直接信任 `jury_config.dimensions`。真实《分流》项目的 `.models` 仍显式配置 3 个旧维度，导致 `suspense_effectiveness` 和 `unexpected_value` 被覆盖掉。
- **影响**: 真实项目运行时 CREATIVE-1/3 和 D-25 悬疑评分不会参与 winner 选择，留白创意评审会退化成普通三维加权。
- **修复**: `get_jury_config()` 保留项目配置顺序，同时自动补齐当前必需 v4 维度并去重；新增回归测试覆盖旧三维配置和重复维度。
- **文件**: `src/inkflow/utils/config.py`, `tests/test_utils.py`, `docs/implementation-contract-v0.md`

### B41. 架构/大纲模型调用 phase 不在 `model_attempts` CHECK 中 ✅ 已修复
- **严重性**: Important
- **发现**: VAL-1 真实项目验证前审计
- **根因**: `ModelRequest.operation` 已使用 `outline_evaluate`、`constitution_generate`、`architect_chapter_rhythm`、`architect_volume_rhythm` 等 phase，但 `model_attempts.phase` CHECK 只接受 writer/jury/fact/repair/polish 等少数值；`_record_model_attempt()` 捕获异常后静默跳过。
- **影响**: 大纲评估、全书宪法、章级节奏、卷部节奏的模型调用不会进入审计表，导致 VAL-1 的 token/调用统计不完整。
- **修复**: Schema v16 扩展 `model_attempts.phase`，新增 v15→v16 迁移并补充回归测试，确保所有当前架构/大纲模型调用 phase 可落库。
- **文件**: `src/inkflow/db/schema.sql`, `src/inkflow/db/migration.py`, `tests/test_db_consistency.py`, `docs/design.md`, `docs/implementation-contract-v0.md`, `docs/design-evaluation-conclusion.md`

### B42. `setup` 只自动抽取第 2 章事件，VAL-1 后续章节缺契约 ✅ 已修复
- **严重性**: Important
- **发现**: VAL-1 真实项目验证前检查
- **根因**: `_generate_contract_draft()` 只调用 `_extract_chapter_2_events()`，即使真实大纲包含第 4 章及后续章节，`contract-draft.yaml` 也不会自动生成 `chapter_4_events` 等字段。
- **影响**: `ink run --chapter v01.c04` 会缺少 must_land 事件，退化为默认场景 prompt，污染真实项目验证结果。
- **修复**: 新增通用 `_extract_chapter_events(outline_text, chapter_number)`，`setup` 自动抽取第一卷第 2-8 章事件；保留 `_extract_chapter_2_events()` 兼容包装并新增测试。
- **文件**: `src/inkflow/cli.py`, `tests/test_cli.py`

---

## 第八轮 (2026-06-26) — VAL-1 恢复、Gate 与真实链路

### B43. 章末钩子只在 L4 弱检查，章节级 L3 没有硬门槛 ✅ 已修复
- **严重性**: Important
- **发现**: 第 2 章重写链路投产前检查
- **根因**: `_check_closing_sentence()` 已能判断 `hook_quality` / `is_unfinished`，但 `evaluate_l3()` 未读取最后一个 shot 正文，也不会把章节末尾必须留悬念纳入章节 gate。
- **影响**: 单个 shot 可通过 L4，但整章最后一句仍可能是解释/收束，章节钩子不明显的问题无法被 gate 拦截。
- **修复**: L3 新增 `chapter_hook` 硬检查，读取最后一个 shot 当前正文，要求最后一句为未完成动作/打断；失败时记录 `chapter_hook_weak`。
- **文件**: `src/inkflow/services/architect_gate.py`, `tests/test_architect_gate.py`

### B44. aborted/crashed session 恢复与失败归因不收敛 ✅ 已修复
- **严重性**: Important
- **发现**: 真实《分流》库存在大量 aborted session
- **根因**: `sessions list` 只展示 active/paused/crashed；`ink resume <session_id>` 会先打印指定 session，却委托给 `run --resume` 重新选择最新 session，可能恢复错对象；失败签名没有 session 级摘要。
- **影响**: 人工无法判断 aborted session 为何失败，显式恢复也不可靠。
- **修复**: 增加 session failure summary，`sessions list` 展示 aborted/crashed 归因；显式 resume 绑定指定 session；异常路径标记 crashed；L3/L4 失败写入 `failure_signature_json`。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/session_manager.py`, `src/inkflow/services/retry_budget.py`, `tests/test_session_manager.py`, `tests/test_cli_happy_path.py`, `tests/test_retry_budget.py`

### B45. 第 2 章重写链路不能安全复跑 ✅ 已修复
- **严重性**: Critical
- **发现**: VAL-1 第 2 章重写
- **根因**: shot_id 为章节复合 ID，新 run 会复用旧 shot；run snapshot 和 shot contract 插入不幂等；`repair` 只能修红/黄，不能整章重写或清掉旧 L3/L4 gate。
- **影响**: `ink run --chapter v01.c02` 看似新跑，实际可能缺 contract、跳过旧 shot 或撞唯一约束，无法验证“重写链路”。
- **修复**: `repair --chapter <key> --all` 支持整章重写、激活原 session、清理旧 L3/L4 gate；run snapshot 和 contract 编译改为幂等；`run --local-jury` 支持不改 `.models` 的本地评审验证。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/session_manager.py`, `src/inkflow/services/contract_compiler.py`, `tests/test_cli_happy_path.py`

### B46. 模型调用失败缺少错误审计，远端 Jury 会拖住生产链路 ✅ 已修复
- **严重性**: Important
- **发现**: VAL-1 真实运行中 stepfun 无有效订阅、qwen 读超时
- **根因**: 远端模型异常只抛出 `ModelCallError`，成功调用才写 `model_attempts`；真实 `.models` 显式远端 jury 时，评分阶段会逐模型逐维度串行等待。
- **影响**: 生产链路长时间停在评分阶段，且 DB 中看不到具体供应商错误。
- **修复**: 模型异常也写入 `model_attempts.error_message`；jury 单次调用默认 45 秒、默认不额外重试；无显式 jury models 时默认 local-default；新增 `--local-jury` 运行开关。
- **文件**: `src/inkflow/services/model_client.py`, `src/inkflow/services/jury_service.py`, `src/inkflow/utils/config.py`, `src/inkflow/cli.py`, `tests/test_model_client.py`, `tests/test_utils.py`, `tests/test_core_services.py`

### B47. `--local-jury` 在存在 providers 时仍误走远端/LLM 评分路径 ✅ 已修复
- **严重性**: Critical
- **发现**: QUAL-1 第 2 章复跑后，local-default 评委输出非 JSON 散文化文本，分数被解析为默认 50，导致可用稿件被低估。
- **根因**: `JuryService.score_candidates()` 只检查 `.models.providers` 是否存在；即使 jury models 全部是 `local-default`，也会进入 LLM scoring 分支。
- **影响**: `run --local-jury` 不能真正隔离远端配置；真实项目有 providers 时，本地验证结果不稳定，且可能把工程链路误判为质量失败。
- **修复**: `use_llm` 增加模型检查：只有存在非 `local-default` jury model 时才调用 LLM；全本地评委走启发式评分且不写远端 `model_attempts`。
- **文件**: `src/inkflow/services/jury_service.py`, `tests/test_jury_scoring.py`

### B48. 本地兜底写手忽略 prompt 的 opening/POV/must_land ✅ 已修复
- **严重性**: Critical
- **发现**: QUAL-1 第 2 章复跑中，生成文本反复出现与《分流》无关的“那封信/窗棂”等 filler，L4 失败集中为 `must_land events may not be fully covered`。
- **根因**: `LocalDefaultGenerator.generate()` 只按 persona 模板生成通用段落，没有读取 prompt 中的第一句、视角人物、场景要点和必须落地事件。
- **影响**: 本地兜底无法验证真实章节契约，repair/resume/gate 虽然可跑完，但输出必然偏离 must_land，导致第 2 章全红。
- **修复**: 本地写手解析 prompt opening、POV 和 beats，并按这些要点组织正文；`jury_score` operation 改为 JSON 启发式评分；最后 shot 保留未完成动作式章末钩子。
- **文件**: `src/inkflow/services/model_client.py`, `tests/test_model_client.py`

### B49. 裁判混合硬规则、类型职责和文学评分，平均分语义不清 ✅ 已修复
- **严重性**: Important
- **发现**: 生产线设计复盘中确认：悬疑/留白不是每个 shot 都需要；硬规则也不能和文学表现混合平均，否则可能去掉最低分时把硬事实错误一起丢掉。
- **根因**: 旧 Jury 将契约、悬疑、意外价值、流畅度等混在同一分组中计算 winner；CREATIVE-3 通过 `creative_score` 调权，但没有明确“硬规则先过、类型职责按需启用、文学 9 维 trimmed mean”的层级。
- **影响**: 普通 shot 可能被不需要的悬疑/留白维度误伤；硬规则问题可能被文学高分掩盖；候选稿只有一个过线时仍可能推进，存在“矮子里拔高个”风险。
- **修复**: Schema v17 扩展 jury 维度；`JuryService` 改为硬规则 → 类型职责 → 文学 9 维；文学分只对 9 个文学维度去最高/最低取均分；默认至少 2 个候选稿过阈值；CLI 支持已有过线稿时单线返写。
- **文件**: `src/inkflow/services/jury_service.py`, `src/inkflow/services/writer_dispatcher.py`, `src/inkflow/cli.py`, `src/inkflow/models/enums.py`, `src/inkflow/utils/config.py`, `src/inkflow/db/schema.sql`, `src/inkflow/db/migration.py`, `tests/test_jury_scoring.py`, `tests/test_utils.py`, `tests/test_schema.py`

### B50. `setup` 同时表示全书初始化和章前校准，生产入口语义冲突 ✅ 已修复
- **严重性**: Important
- **发现**: 第 3 章生产前流程复盘
- **根因**: 早期 CLI 中 `ink setup` 负责全书契约草稿生成；后续讨论又需要 `setup` 表示某章继写前校准。两个含义共用同一命令，导致新会话 AI 可能跳过章前校准，或把全书初始化误当成单章生产准备。
- **影响**: 第 3 章及后续章节可能直接 `run`，没有人工确认本章 shot、类型职责、章末钩子和禁止议论规则；也会让 `confirm-contract`、文档和 next steps 指向错误命令。
- **修复**: 新增 `ink init` 承接全书初始化；`ink setup <project> --chapter <key>` 只生成单章生产前校准包；`run --chapter` 强制读取 setup 包，并把禁止议论/类型职责注入 prompt 与裁判 profile；新增 `ink review` 记录生产后人工验收。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/prompt_compiler.py`, `tests/test_cli.py`, `tests/test_prompt_compiler.py`, `TASKS.md`, `docs/flow.md`, `docs/setup-protocol.md`, `docs/design.md`, `docs/implementation-contract-v0.md`, `docs/history.md`

### B51. 导出稿保留模型重复生成的 Markdown 小标题 ✅ 已修复
- **严重性**: Minor
- **发现**: 第 3 章真实导出审稿前检查
- **根因**: `export_markdown()` 已按契约输出 `### shot title`，但 `_format_prose_for_export()` 又保留模型正文里开头生成的 `# 标题` 块，导致审稿稿出现重复标题。
- **影响**: 编辑稿版式不干净，容易把模型提示痕迹误认为正文结构。
- **修复**: 导出层剥离正文中的 Markdown heading block，只保留导出器生成的契约标题；新增回归测试。
- **文件**: `src/inkflow/export/exporter.py`, `tests/test_cli.py`

### B52. 远端 hard-rule jury 把契约旧风格项误判为硬规则，导致全 0 / 无 winner ✅ 已修复
- **严重性**: Critical
- **发现**: 第 3 章远端 jury 链路中，模型调用成功且返回了原始分，但 `JuryService` 因 `hard_rule_compliance` 低于阈值把 `trimmed_mean` 清零，最终显示全 0 / 无 winner。
- **根因**: 锁定契约仍含旧章节限定（`P0 只生成第 2 章...`）和旧段落锁（`500-800 字/段落，3-4 段/shot`）；同时硬规则裁判摘要包含 `style_locks`，远端 LLM 将段落长度、方言、感官密度、身体时刻开场以及 `characters_alive` 名单误读为硬规则。
- **影响**: API 可用但候选稿被资格层误杀；本地 jury 可过，远端 jury 连续无 winner，真实生产验证失真。
- **修复**: `setup/run` 增加章节契约准入，拒绝旧章节限定、旧段落锁、过期 setup 包和 setup/contract shot 数不一致；hard-rule prompt 收窄为硬事实/POV/must_land/禁写/提示词残留等；风格类低分、远端 timeout/解析失败和 `characters_alive` 排他误读只作为 advisory，不再清零候选稿；`init` 默认契约模板移除第 2 章 P0 限定并改用导出层短段策略。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/jury_service.py`, `tests/test_cli.py`, `tests/test_jury_scoring.py`, `docs/flow.md`, `docs/setup-protocol.md`, `docs/design.md`, `docs/implementation-contract-v0.md`, `TASKS.md`, `docs/history.md`

### B53. Gate 失败稿在 CLI 中显示为 `均分: 0`，误导远端 jury 排障 ✅ 已修复
- **严重性**: Important
- **发现**: 第 3 章远端链路完成后，第 5 个 shot 的部分草稿因类型职责未过被置为 `eligible=False`，但 CLI 仍打印 `均分: 0`，看起来像远端评分全 0。
- **根因**: `JuryService` 对硬规则/类型 gate 失败稿只返回 `trimmed_mean=0`，缺少结构化 `failure_summary`；`run` 打印评分时不区分“未进入文学评分”和“文学均分为 0”。
- **影响**: 生产排障会把正常 gate 淘汰误判为 API 失败、契约错误或文学评分异常，干扰契约/规则归因。
- **修复**: gate 失败稿增加 `failure_summary`，包含 `stage`、显示标签和低于阈值的维度；CLI 打印改为 `未入选: 硬规则未通过/类型职责未通过`，不再把不可用稿显示成文学均分 0。
- **文件**: `src/inkflow/services/jury_service.py`, `src/inkflow/cli.py`, `tests/test_jury_scoring.py`, `tests/test_cli.py`, `TASKS.md`, `docs/history.md`

### B54. 远端 jury timeout 被当作类型/文学 50 分，污染作品均分 ✅ 已修复
- **严重性**: Important
- **发现**: 第 3 章真实远端运行中，`qwen3.7-plus` 偶发 read timeout，旧逻辑把失败响应解析为 `score=50` 并混入 `raw_scores`，降低候选稿的类型/文学均分。
- **根因**: `_score_single()` 对所有失败统一返回 50；`_score_dimension_group()` 无法区分“模型失败”和“评委给了低分”。硬规则层需要保留 advisory 低分判断，但类型/文学层不应把基础设施失败当作品缺陷。
- **影响**: 单个供应商抖动会不公平压低文本质量分；如果某个维度全部远端失败，旧流程可能触发正文重写，浪费预算且掩盖真实故障。
- **修复**: `_score_single()` 为最终失败返回 `failed=True`；类型/文学层跳过失败分并记录 `jury_failures`；必评维度没有任何有效评分时标记 `jury_unavailable`；`run` 遇到所有候选均为 `jury_unavailable` 时停止本章生产、记录 retry 归因并标记 session crashed。
- **文件**: `src/inkflow/services/jury_service.py`, `src/inkflow/cli.py`, `src/inkflow/services/retry_budget.py`, `tests/test_jury_scoring.py`, `tests/test_cli.py`, `tests/test_retry_budget.py`, `TASKS.md`, `docs/history.md`

---

## 第九轮 (2026-06-27) — 生产内核硬化

### B55. 显式远端 jury 在 providers 为空时静默回落本地评分 ✅ 已修复
- **严重性**: Critical
- **发现**: 生产管线专家审阅
- **根因**: `JuryService.score_candidates()` 同时用“是否有远端模型”和“providers 是否非空”判断是否调用 LLM。显式配置远端 jury 但 provider/key 缺失时，会走本地启发式评分，掩盖真实配置错误。
- **影响**: 远端评审验证可能是假通过；生产质量基线与 `.models` 配置不一致。
- **修复**: 显式远端 jury 一律进入远端评分路径；缺 provider/key 被 `_score_single()` 捕获为失败，类型/文学全维度不可评时归因为 `jury_unavailable`。
- **文件**: `src/inkflow/services/jury_service.py`, `tests/test_jury_scoring.py`

### B56. 留白创意评审计算了 `creative_score`，但 winner 仍按文学均分选择 ✅ 已修复
- **严重性**: Important
- **发现**: 生产管线专家审阅
- **根因**: `creative_review=True` 会计算 `creative_score`，但 `_select_winner()` 仍使用 `literary_score` 和 `typed_literary` 语义。
- **影响**: 留白 shot 仍偏向安全稿，`unexpected_value` 无法真正提高选优权重。
- **修复**: 留白创意评审使用 `score_key=creative_score` 和 `review_mode=creative_blank`。
- **文件**: `src/inkflow/services/jury_service.py`, `tests/test_jury_scoring.py`

### B57. 四轨写手共用“意象师”完整 prompt，persona 指令互相污染 ✅ 已修复
- **严重性**: Important
- **发现**: 生产管线专家审阅
- **根因**: CLI 只用“意象师”编译一份 assembled prompt，`WriterDispatcher` 再给节奏师/对话师/结构师追加风格尾巴。完整身份层仍是意象师。
- **影响**: 四轨赛马不是真正的四种写作策略，可能降低候选稿差异和 jury 选优价值。
- **修复**: CLI 为四个 persona 分别编译 prompt；`dispatch_quad_track()` / `dispatch_single_persona_track()` 支持 `persona_prompts`。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/writer_dispatcher.py`

### B58. L4/L3 失败后仍可能 complete session 并自动导出 ✅ 已修复
- **严重性**: Critical
- **发现**: 生产管线专家审阅
- **根因**: L4 在 `finalize_shot()` 和 completed 计数之后才执行，L3 在 `complete_session()` 之后才执行；失败只打印告警，不阻止封板/导出。
- **影响**: 含解释性结尾、叙述者越界、章节钩子失败的文本可能被标为完成并进入导出稿。
- **修复**: L4 前移到 shot finalize 之前并成为硬 gate；L3 前移到 session complete 和自动导出之前；章节未完成或 L3 未通过时抛出 `ClickException`，停止封板/导出。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/architect_gate.py`, `tests/test_architect_gate.py`

### B59. RetryBudget 熔断第 4 次才触发，且换失败类型不重置连续计数 ✅ 已修复
- **严重性**: Important
- **发现**: 生产管线专家审阅
- **根因**: `record_failure()` 在写入本次失败前用旧 count 判断阈值；`_count_consecutive_failures()` 没检查 `last_failure_type` 是否等于本次类型。
- **影响**: 同类失败多跑一次才熔断；不同原因的失败可能误触发同类熔断。
- **修复**: 先计算 `next_count=count+1` 并记录本次 signature，再按 `next_count >= threshold` 熔断；failure type 切换时连续计数归零。
- **文件**: `src/inkflow/services/retry_budget.py`, `tests/test_retry_budget.py`

### B60. 自动导出可能混入旧 run 正文，纯文本导出保留模型标题 ✅ 已修复
- **严重性**: Important
- **发现**: 生产管线专家审阅
- **根因**: 导出按 `layer_key` 查询，不限定当前 run/gate 状态；纯文本导出没有走 `_format_prose_for_export()`，模型生成的 Markdown 标题可能泄漏。
- **影响**: 多次重写同章节时，审稿导出可能不是当前 run 的正文；给后续工具的纯文本仍带模型标题痕迹。
- **修复**: 自动导出传入 `run_id`；Markdown/纯文本导出都过滤 `done_green/done_yellow + current_revision_id`，并清理模型标题、拆分长段。
- **文件**: `src/inkflow/export/exporter.py`, `src/inkflow/cli.py`, `tests/test_cli.py`

### B61. 人工 review 只写 YAML，rejected/unaccepted 正文仍可能污染正式导出和后续上下文 ✅ 已修复
- **严重性**: Critical
- **发现**: 生产内核 CORE-1 审阅
- **根因**: `ink review --accept/--revise/--reject` 只写 `.inkflow/chapter-reviews/*.yaml`，DB 中没有章节级 canonical 状态；默认导出、previous context 和 fact anchors 无法区分 accepted、rejected、aborted 或未审稿 run。
- **影响**: 人工退稿/返修的正文仍可能被默认导出当作正式稿，或作为前文事实进入下一章 prompt，造成连续污染。
- **修复**: Schema v18 新增 `writing_chapter_reviews`；`review` 写 DB canonical 状态，`--accept` 必须 latest run completed、shot 全封板且 L3 passed；`--revise/--reject` 将该 run 本章绿/黄 shot 退回 `redo`；默认 `ink export` 改为 accepted-only，`--draft` 才导出审稿稿；previous context 和 fact anchors 只读取当前 run、accepted 章节或 locked baseline。
- **文件**: `src/inkflow/db/schema.sql`, `src/inkflow/db/migration.py`, `src/inkflow/cli.py`, `src/inkflow/export/exporter.py`, `src/inkflow/services/fact_anchor_extractor.py`, `tests/test_schema.py`, `tests/test_cli.py`, `tests/test_fact_anchor.py`

### B62. 同一章节重写复用稳定 `shot_id`，可能跳过旧正文或串到旧 run ✅ 已修复
- **严重性**: Critical
- **发现**: 生产内核 CORE-2 审阅
- **根因**: `writing_shots.shot_id` 同时承担“故事逻辑位置”和“本次执行主键”两种职责；`create_shots()` 以稳定 `v01.c02.s01` 查重，导致新 run 可能复用旧 shot 行，draft/revision/repair/export 难以区分本次重写与历史正文。
- **影响**: 同一章节返修、重写或生产恢复时，可能跳过应重新生成的 shot，或把旧 run 的正文、评分、修复状态带入新 run；accepted canonical 即使存在，也无法完全防止执行层污染。
- **修复**: Schema v19 新增 `logical_shot_id`；生产 run 的 `shot_id` 改为 `{logical_shot_id}@{run_id}`；baseline 保持 `shot_id == logical_shot_id`；`create_shots()` 只在同一 run 内幂等；v18→v19 迁移回填旧 rows，并建立 `idx_shots_logical` / `idx_shots_run_logical_unique`；`repair --chapter --all` 限定 latest run。
- **文件**: `src/inkflow/db/schema.sql`, `src/inkflow/db/migration.py`, `src/inkflow/utils/shot_id.py`, `src/inkflow/services/session_manager.py`, `src/inkflow/importers/baseline_importer.py`, `src/inkflow/cli.py`, `tests/test_schema.py`, `tests/test_migration.py`, `tests/test_shot_id.py`, `tests/test_session_manager.py`, `tests/test_baseline_importer.py`, `tests/test_cli.py`

### B63. 缺少全书/整卷编排层，无法一次启动多章生产后集中返工 ✅ 已修复
- **严重性**: Important
- **发现**: 用户要求“一次性全书生产，然后质量不好的章节再返工”
- **根因**: 现有生产线只有单章 `setup -> run -> review`，没有上层批次 ID 记录多个章节 run 的关系；若直接连续手工跑多章，后续无法区分同一批次草稿、失败章节、待审稿章节和返工入口。
- **影响**: 无法安全支持全书/整卷批处理；后续章节也不能读取同一批次前序 draft，只能读取 accepted 章节，导致“先全书草稿、后集中审稿”流程不成立。
- **修复**: Schema v20 新增 `writing_book_runs` / `writing_book_run_chapters`；新增 `ink run-book` 和 `ink book-report`；同一 `book_run` 已完成前序 draft 可作为后续章节临时上下文和 fact anchors；正式导出仍只认 accepted canonical；`ink status` 展示最近 book run。
- **文件**: `src/inkflow/db/schema.sql`, `src/inkflow/db/migration.py`, `src/inkflow/cli.py`, `src/inkflow/services/fact_anchor_extractor.py`, `tests/test_schema.py`, `tests/test_migration.py`, `tests/test_cli.py`, `tests/test_fact_anchor.py`

### B64. 第 3 章审稿发现标题边界、旧称、未授权事实扩写和短 hook 均被放过 ✅ 已修复
- **严重性**: Critical
- **发现**: 第 3 章人工审稿；`玻璃里的保鲜膜` 标题下混入白英 shot，`铅笔的问号` 中出现“阿坤/社区医院/髌骨软化”等未授权信息，`慢下来` 作为独立标题场景篇幅过薄。
- **根因**:
  - 导出器只读 `must_land_json.title`；大纲重写后 title 可能丢失，没有回退到完整 `contract_json.must_land.title`。
  - 真实契约和旧 setup 包仍残留废弃角色名“阿坤”，`confirm/setup/run/L4` 没有 canonical name gate。
  - L4 只抓泛化解释/系统解释，未拦截医疗诊断、请假、手术、派单量等高影响事实扩写。
  - L3 只检查章末钩子是否“未完成”，不检查有标题 shot 是否具备足够场景重量。
- **影响**: 远端 writer/jury 可给出 5/5 green，但审稿稿仍存在编辑层不可接受问题；若人工误 accept，会污染后续章节上下文。
- **修复**: 导出标题解析增加 contract fallback；新增角色名一致性工具，`confirm-contract`、`setup/run` 前置检查和 L4 均拦截废弃别名；L4 新增未授权医疗/制度事实扩写硬 gate；L3 新增 titled shot density gate；真实《分流》`contract-draft.yaml` 与 `v01.c03.yaml` 已清除“阿坤”。
- **文件**: `src/inkflow/export/exporter.py`, `src/inkflow/utils/character_names.py`, `src/inkflow/cli.py`, `src/inkflow/services/architect_gate.py`, `tests/test_cli.py`, `tests/test_architect_gate.py`
- **验证**: `python -m pytest -q`：440 passed, 4 warnings

---

## 第十轮 (2026-06-29) — Contract-first 设计缺陷归因

### B65. 大纲门禁没有强制 hard fact manifest，违约大纲仍进入写作 ✅ 已修复第一版
- **严重性**: Critical
- **发现**: 第 3 章人工审稿和管线复盘。
- **根因**: 大纲评估主要关注结构合理性和文学潜力，没有先把 `setup` 输出编译为 machine-checkable fact manifest，也没有要求大纲逐项覆盖 allowed facts、forbidden expansions、must_land anchors、POV 边界和 hook duty。
- **影响**: 写手从一开始就可能拿到违约大纲，后续 writer/jury/gate 只能补救，不能从源头阻断。
- **修复**: `setup --chapter` 生成 `inkflow.fact_manifest.v1`；`run --chapter` 在大纲评估后执行 outline fact gate，拦截空大纲、缺失契约信号、废弃角色名、禁词和未授权事实扩写；失败写入 `writing_audit_events(outline_gate)` 和 `writing_failure_attributions`，不进入正文写作。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/outline_evaluator.py`, `src/inkflow/services/contract_compiler.py`, `docs/design.md`, `tasks.md`

### B66. 草稿赛马把 eligibility 与文学评分混在一起，违约稿可能凭文笔晋级 ✅ 已修复第一版
- **严重性**: Critical
- **发现**: 第 3 章远端链路可给 5/5 green，但人工审稿仍发现不可接受的事实扩写和人物旧称问题。
- **根因**: draft 的硬事实资格检查未形成独立候选隔离层；部分问题被延后到 L4/L3 或人工审稿，文学评分可能先选出“顺滑但违约”的 winner。
- **影响**: 赛马花费更多算力，却可能选择更会写但更偏契约的稿，形成“管线不如直写”的直观结果。
- **修复**: Gate1 后立即执行 draft hard fact gate；废弃角色名、禁词、未授权医疗/请假扩写、章末解释性收束等确定违约稿写入 `writing_draft_eligibility(hard_rule, passed=0)` 和 failure attribution，不进入类型/文学 jury，也不能成为 winner；同时修复 Gate1 后候选集未收窄的问题。
- **文件**: `src/inkflow/services/jury_service.py`, `src/inkflow/services/quality_controller.py`, `src/inkflow/cli.py`, `tests/test_jury_scoring.py`

### B67. winning outline 到 shot prompt 缺少结构化 task card，硬事实可能在编译中丢失 ✅ 已修复第一版
- **严重性**: Important
- **发现**: 第 3 章复盘中发现 must_land 既有散文化表达，又可能被 outline 重写或 prompt 编译过程弱化。
- **根因**: 胜出大纲没有被编译成每个 shot 共用的 task card；写手 prompt、gate、jury 可能读取不同形态的自然语言描述。
- **影响**: 大纲合格也不能保证草稿 gate 检查同一套硬事实，容易出现“写手以为完成，gate 读不到”的错位。
- **修复**: `run` 将合格大纲编译为 `inkflow.shot_task_card.v1`，包含 title、POV、must_land、hard_facts、type_roles、hook_required、forbidden_phrases、outline；task card 进入写手 prompt 和 `writing_audit_events(prompt:shot_task_card_compiled)`，写手与门禁读取同一份结构化输入。
- **文件**: `src/inkflow/services/prompt_compiler.py`, `src/inkflow/services/contract_compiler.py`, `src/inkflow/cli.py`

### B68. setup 包自相矛盾时不能在 run 前失败 ✅ 已修复第一版
- **严重性**: Important
- **发现**: 当前 `v01.c03` setup 曾出现 must_land 含 forbidden phrase 的模式，说明 setup 自身需要 lint。
- **根因**: setup 人类可编辑后缺少严格 linter；must_land、forbidden_phrases、数字锁、hook duty、POV 边界之间的冲突未被系统化检查。
- **影响**: 契约问题会拖到 writer/jury 阶段才暴露，排障时容易误判为模型或规则问题。
- **修复**: `run --chapter` 在创建 session 前执行 setup linter；除要求 setup 包含 `fact_manifest` 且 shot 数一致外，还会拦截 `must_land` 命中 `forbidden_phrases`、POV 与契约/fact_manifest 不一致、POV 未声明、未知类型职责、章节要求 hook 但最后一个 shot 未标记 hook 等问题；失败写入 `writing_audit_events(setup)` 与 `writing_failure_attributions(contract_conflict)`。
- **剩余**: 数字锁与 POV known/unknown 的更细粒度一致性检查仍需后续基于真实 setup 字段扩展。
- **文件**: `src/inkflow/cli.py`, `src/inkflow/services/architect_gate.py`, `tests/test_cli.py`

### B69. 失败归因粒度不足，无法判断应重写大纲、修 task card 还是修规则 ◐ 部分修复
- **严重性**: Important
- **发现**: 第 3 章远端全 0 / 无 winner 排障中，契约问题与软件规则问题需要反复人工区分。
- **根因**: 现有 retry/failure 记录偏 gate 或模型调用结果，没有统一归因为 `contract_conflict/outline_gap/task_card_gap/writer_drift/gate_false_positive/model_failure`。
- **影响**: 管线失败后可能盲目重写正文，浪费 API 调用，也掩盖真正需要人类 setup 校准的问题。
- **修复**: 新增 `hard_rule_violation` 重试类型；outline fact gate、draft hard fact gate、jury/gate/retry 均写入 `writing_failure_attributions`；新增 `ink audit-report` 汇总 run 审计链、草稿资格、失败归因和模型调用覆盖；setup preflight 失败归为 `contract_conflict`；task card 缺字段归为 `task_card_gap`；草稿写偏归为 `writer_drift`。
- **剩余**: `gate_false_positive` 仍需通过真实章节失败样本继续细化，避免把规则误杀误判成写手漂移。
- **文件**: `src/inkflow/services/retry_budget.py`, `src/inkflow/services/session_manager.py`, `src/inkflow/cli.py`
