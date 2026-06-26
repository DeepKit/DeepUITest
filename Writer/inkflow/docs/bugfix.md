# InkFlow v3.12 — Bug 记录

> 记录开发过程中发现和修复的 bug
> ARCH-13（2026-06-24）补充：`shot_revisions.is_current` 字段语义更新为"封版标记"（见 B19 注）
> ARCH-4（2026-06-24）：Schema v8→v9，新增 `writing_book_constitutions` 表 + `writing_meta_contract.constitution_version_id` 指针列
> 2026-06-26 VAL/QUAL/JURY 修复：新增 B43/B44/B45/B46/B47/B48/B49；开放实现任务见 `../tasks.md`

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
