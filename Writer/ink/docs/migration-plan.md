# 实施计划 — 从 0 构建完整生产版 M0-M6

> **状态**：v2（2026-07-04，质量硬门禁修订），对应 `design-v2.md`
> **定位**：**从 0 构建完整生产版**，不基于旧 `inkflow/` 改造。无工期、无双轨并行、无旧系统迁移、无 MVP 裁剪。
> **原则**：旧系统仅作"领域知识参考库"，取其踩坑结晶与领域设计，弃其架构病土壤。每个里程碑完成后对照 `pitfall-checklist.md` 逐条核对。

---

## 0. 核心原则

### 0.1 从 0 构建
- 新代码在 `ink/src/ink/`，不修改旧 `inkflow/`
- DB schema 重新设计（40 张生产表），不沿用旧 56 表
- 编排层重写，不沿用旧 cli.py

### 0.2 无工期
- 不记录时间计划、周期估计、里程碑排期
- M0-M6 按依赖顺序推进，完成一个再开始下一个
- 不设截止日期

### 0.3 无双轨
- 不做"新系统与旧系统并行运行"的过渡期
- 不做"逐步迁移旧功能到新系统"
- 新系统独立构建，完成即替代

### 0.4 旧系统作为知识参考
- 旧 `inkflow/docs/bugfix.md` B1-B94：提炼为 `pitfall-checklist.md` 的 15 条结晶
- 旧 `inkflow/docs/design.md`：领域设计参考（三棵树/悬疑引擎/契约状态机）
- 旧 `inkflow/tests/` 557 个用例：行为规约参考，入参签名可改，断言不可弱化

### 0.5 完整生产功能
- 不使用 MVP 概念，不以“后续再补”裁剪功能。
- M0-M6 可以按依赖顺序实现，但 schema、审计、人工决策、导入账本、checkpoint、测试追踪矩阵必须从设计阶段完整存在。
- 写作质量是硬门禁：shot/chapter/book 任一层未达标，不得 accepted/export；human accept 不得覆盖硬失败。
- 质量证明是阶段门禁：至少一个完整章节/关键片段必须通过盲评、继续阅读、must_land 追溯、返工质量提升验证后，才允许把并行、批量和导出视为生产能力完成。
- 质量门禁必须保护文学活力：`productive` 偏离不得被 `polish_revision` 自动磨平；`neutral` 偏离必须进入人工 review。
- 每个里程碑完成定义见 `invariant-traceability.md`。

---

## M0. 基础设施层

### 目标
搭好新系统的骨架：DB schema、代码生成、类型检查、字段消费 lint。

### 任务
1. **DB schema 落地**（`implementation-contract-v1.md §2`）
   - 建 40 张生产表的 DDL（契约/执行/评审/悬疑/篇级检测/运行审计/人工决策/导入账本）
   - shot 契约核心字段拆 5 张结构化表（must_land/anti_write/scene_contract/persona_assignment/soft_constraints）
   - jury 评分拆 raw_scores + aggregates 2 张表（方案 B）
   - 建 CHECK 约束（含 `draft_count <= pool`、`jury_pool >= 3`、信息差 6 态枚举、winner 必须 quality_gate_passed、accepted 必须章级 7 维达标）、FK ON DELETE CASCADE、唯一索引（is_winner、accepted canonical、jury winner）
   - 建 DB VIEW `v_current_text`（封版逻辑封装，必须投影 revision_id/source_revision_id）
   - 建 `writing_ai_call_attempts`、`writing_runtime_events`、`writing_llm_failure_streaks`
   - 建 `writing_human_decisions`（含 quality_report_json 与 hard_quality_override=0）、`writing_session_checkpoints`
   - 建 `writing_contract_clauses`、`writing_contract_changelog`、`writing_fact_anchors`、`writing_context_snapshots`
   - 建 `writing_import_runs`、`writing_import_manifests`、`writing_import_questions`、`writing_import_decisions`
   - 定义 `QualityReport` JSON schema：`evidence_class`（ES/SEMI_ES/NES）、`defect_class`（destructive/productive/neutral）、盲评、继续阅读、blocking_items、productive_deviations、neutral_issues、smart_model_required
   - 单一 migration 文件（无历史 migration，从 0 建）
2. **代码生成器**（`ink/src/ink/codegen/`）
   - `generate.py`：读 `contract/schemas/*.py` pydantic schema → 生成 `contract/generated/*.py` dataclass + `unpack()` 访问器
   - `field_usage_lint.py`：两道防线——访问器 API 强制（禁动态访问）+ AST `ast.Attribute` 节点可达性扫描（铁律 1，评审 #2）
   - `sql_access_lint.py`：sqlparse 解析 SQL token，断言只有 `core/text_repository.py` 含 `writing_shot_revisions`（铁律 5，评审 #3）
3. **pyright strict + lint 配置**
   - `pyproject.toml` 配置 pyright strict
   - CI 集成：`generate` → `field_usage_lint` → `sql_access_lint` → `state_update_lint` → `llm_access_lint` → `pyright --strict`
4. **text_repository 物理隔离**（铁律 5，三重约束）
   - `core/text_repository.py`：唯一可访问 `writing_shot_revisions`，只暴露 `read_current_text`/`write_revision`/`is_hard_sealed` 三方法（无直查后门）
   - 内部走 DB VIEW `v_current_text`
   - CI sqlparse lint 扫描全代码库

5. **测试与审计追踪矩阵**
   - 落 `invariant-traceability.md` 中 M0 阻断项
   - 每个旧 bugfix / 决策条目必须有 invariant ID 或明确废弃理由

### 验证清单
- [ ] 40 张生产表 DDL 在内存 SQLite 执行成功，CHECK/FK/索引/VIEW 齐全
- [ ] 契约 5 张拆表 + jury 2 张拆表结构正确
- [ ] MetaContract 含 QualityBar / StyleQualityProfile；quality_bar/style_quality_profile 落 `writing_meta_contracts`
- [ ] QualityBar 含 `reader_pull_floor`、`blind_review_min_passes`；StyleQualityProfile 含 `reader_pull_target`、`blind_review_policy`、`protected_roughness`、`voice_anti_samples`
- [ ] `quality_report_json` schema 校验：缺 `evidence_class`、缺 `defect_class`、缺盲评/继续阅读字段均失败
- [ ] DDL 阻断：`is_winner=1 AND quality_gate_passed=0`、`accepted` 章级任一维低于 75、`book_check quality_gate_passed=1 AND blocking_issue_count>0` 全部失败
- [ ] **soft_gate_counters 拆表 + persona intensity 5 维 CHECK + information_gaps 转移 CASE CHECK + chapter_reviews 7 维 CHECK(0-100) + eligibility 8 维 CHECK（medium）**
- [ ] **ON DELETE CASCADE 矩阵：从属子表级联、审计指针（source_revision_id/shots.shot_contract_id）不级联（见 implementation-contract §2.9）**
- [ ] `python -m ink.codegen.generate` 生成 7 个 dataclass + unpack 访问器
- [ ] `field_usage_lint` 对故意漏字段的测试用例报错；对 `getattr`/`vars` 动态访问报错
- [ ] `sql_access_lint` 对非 text_repository 模块访问 `writing_shot_revisions` 报错
- [ ] `state_update_lint` 对非 `core/state_machine.py` 直接更新 `writing_shots.status` 报错
- [ ] `llm_access_lint` 对非 `core/llm_gateway.py` 直接调用供应商 SDK 报错
- [ ] **lint 元测试（medium §4.3/§4.4）：sql_access_lint 检出动态表名/ORM/f-string 拼接；field_usage_lint 检出注释不算消费/getattr 动态访问**
- [ ] `pyright --strict` 全量通过
- [ ] `invariant-traceability.md` 中 M0 blocking 项全部有真实测试/lint 实现并接入 CI；占位不算完成
- [ ] text_repository 物理隔离 lint 通过
- [ ] 对照 `pitfall-checklist.md` P1.1（B19）、P1.15（四层隔离）、P2.N5（字段消费）、P2.N6（状态机）、P2.N7（并发）核对

---

## M1. 核心机制层

### 目标
搭好 `core/` 的状态机、熔断、会话隔离、崩溃恢复。

### 任务
1. `core/session_manager.py`
   - `shot_id = {logical}@{run}` 隔离（B62）
   - session/run/attempt 三层（B44）
2. `core/retry_budget.py`
   - `LLMCallBudget`：每 shot ≤ 8 次 LLM 调用熔断（B59）
   - `SoftGateCounter`：soft gate 3 级状态机（N1/N2/N3）（铁律 4）；质量类 N=3 转 QUALITY_BLOCKING，不降级放行
   - 连续失败计数权威源为 `writing_llm_failure_streaks`
   - soft gate N 计数权威源为 `writing_soft_gate_counters`
3. `core/llm_gateway.py`
   - 所有 AI 调用唯一入口
   - 调用前检查 budget；调用后落 `writing_ai_call_attempts`、`writing_runtime_events`、failure streak
   - 支持 idempotency_key，崩溃恢复不重复计费/不重复落库
4. `core/resume.py`
   - `ResumeManager.RESUME_MAP`：shot_status 14 态 → resume 行为映射矩阵（评审 #5）
     - done 类 skip：`soft_sealed`/`hard_sealed`/`failed`
     - generating 类幂等重跑：`drafting`/`hard_gate1`/`hard_gate2`/`jury_scoring`/`winner_selected`/`polish_revision`
     - pre-drafting 类 supersede 幂等重跑：`outline_draft`/`outline_confirmed`/`task_card_compiled`/`prompt_compiled`
     - `pending` start_from_scratch
   - `redo_in_progress` 子状态崩溃恢复（评审 #6）：无新候选重跑局部重写，有候选无评分重跑评分
   - 上游 `source_revision_id` stale 检测（B92）
   - `resume_point` 结构化 JSON `{phase, chapter_id, dimension_index}`（评审 #17）
   - resume 显式绑定 session_id（B44）
   - 读取 `writing_session_checkpoints`，每个稳定阶段最多保留最近 3 个 checkpoint
5. `core/text_repository.py`（完整实现）
   - `read_current_text`：封版规则（B19）
   - `write_revision`：软封版 / 硬封版
   - `is_hard_sealed`
6. `core/outline_integrity.py`
   - `outline_has_incomplete_tail`（B87）

### 验证清单
- [ ] shot_id 隔离测试：同 logical 不同 run 不串
- [ ] retry_budget 测试：第 3 次熔断，类型切换归零，8 次/类型上限，**40 次总量上限转 failed 终态（P0-5）**，计数落 DB 崩溃恢复
- [ ] LLMGateway 测试：所有调用落 ai_call_attempts/runtime_events；直接 SDK 调用被 lint 拦截
- [ ] soft gate 3 级测试：N=1 阻断、N=2 产 ≥2 篇局部重写、非质量 N=3 可降级；质量类 N=3 转 QUALITY_BLOCKING 不放行
- [ ] N 计数崩溃恢复测试：DB 权威、无状态读、跨 run 累积不归零
- [ ] resume 14 态映射测试：done skip / generating 幂等重跑去重 / pre-drafting supersede 幂等 / polish_revision 重跑质量门禁
- [ ] redo_in_progress 崩溃恢复测试：无候选重跑重写、有候选无评分重跑评分
- [ ] resume 测试：上游 stale 不 skip、显式 session_id、resume_point 结构化定位
- [ ] checkpoint 测试：drafting/jury/soft_gate/chapter_review 崩溃后从 checkpoint 恢复，不覆盖已封板文本
- [ ] text_repository 测试：封版前读 MAX、封版后读 is_current、无直查后门
- [ ] **shot 状态机 14 态转移矩阵测试（P0-2）**：非法转移抛 IllegalTransitionError、终态 hard_sealed/failed 无出边抛 TerminalStateError、failed 不 `→pending` 需新建 run；winner_selected 必须经 polish_revision 才能 soft_sealed
- [ ] **乐观锁 CAS 测试（P0-2）**：并发改同 shot status 抛 ConcurrentModificationError（affected_rows=0 检测）、不自动重试
- [ ] **N=2 winner 翻盘测试（P0-2）**：新候选 final_score > 原 winner 且通过 quality floor 时事务内 is_winner 翻转；该流程只允许在 winner_selected，进入 polish_revision/soft_sealed 后必须新建 run；未翻盘则 N 不清零继续累积
- [ ] **并发模型测试（P0-2）**：同 session 无并发 shot（gate_orchestrator 串行）、跨 session 同 logical shot 并发时 N 累加原子（UPDATE SET count=count+1）
- [ ] 对照 `pitfall-checklist.md` P1.2-5、P1.10、P2.N2、P2.N6（状态机）、P2.N7（并发）核对

---

## M2. 契约层 + 大纲编排

### 目标
契约 dataclass 链落地，大纲生成与 PK 选优跑通。

### 任务
1. **契约 schema 完整定义**（`contract/schemas/`）
   - MetaContract / ShotContract / OutlineSpec / TaskCard / PromptSpec / DraftSpec / JuryInput
   - 运行 `generate.py` 生成 dataclass
2. **契约 DB 加载器**（`contract/*.py`）
   - 每个 dataclass 对应一个 `load_from_db(shot_id, run_id)` 函数
   - ShotContract 加载需 JOIN 5 张拆表（must_land/anti_write/scene_contract/persona_assignment/soft_constraints）拼装
   - 加载器是 DB 的只读投影（铁律 2）
3. `pipeline/outline_orchestrator.py`
   - `evaluate_and_select(shot_id, run_id) -> OutlineSpec`
   - 生成 ≥2 份大纲，每份过合格线
   - CJK bigram overlap drift 检测（B77），落 `drift_score`
   - `drift_rejected` 派生自 `drift_score < 0.20`，不存列（评审 #23）
   - PK 选优 → `is_winner`（唯一索引约束，评审 #30）
4. `contract_compiler/task_card_compiler.py`
   - 由 must_land 生成 TaskCard
   - `outline_has_incomplete_tail` 拦截（B87）
   - `superseded_at` 机制（B88），旧 prompt 不删供审计

### 验证清单
- [ ] 7 个 dataclass 生成成功 + unpack 访问器，字段消费 lint 通过
- [ ] 契约加载器 JOIN 5 张拆表正确加载 ShotContract（不传 dataclass 跨步骤）
- [ ] 大纲生成 ≥2 份，PK 选优正确，is_winner 唯一
- [ ] drift 检测：overlap < 0.2 拒绝；drift_rejected 派生不存列
- [ ] task card 半句拒绝
- [ ] task card 二次编译：旧行打戳 + 写新行，旧 prompt 保留
- [ ] orchestrator 入口只收 `(shot_id, run_id)`（铁律 2 物理隔离）
- [ ] 对照 `pitfall-checklist.md` P1.7-9 核对

---

## M3. 写手层 + 产稿

### 目标
"同 persona + 同 prompt + 换模型"产稿机制跑通，含 deviant 沙盒。

### 任务
1. `writers/model_pool.py`
   - 从 `writing_projects.writer_model_pool` 读模型池
   - X 篇按池轮换/随机分配模型
2. `writers/quad_dispatcher.py`
   - `produce_drafts(shot_id, run_id) -> list[DraftSpec]`
   - 同 persona（契约指定）+ 同 prompt + 换模型，产 X 篇（创意 shot X+creative_shot_extra）
   - DB CHECK 保证 `draft_count <= len(writer_model_pool)`（评审 #25）
   - deviant 独立产 1 篇（`relaxed_soft=True`，`is_deviant=True`）
   - N=2 局部重写时产 ≥2 篇新候选，与原 winner 候选池合并评分（评审 #11）
3. `writers/local_fallback.py`
   - LLM 失败时产占位稿，`degraded=True`（铁律 3）
   - 不进 jury 候选池
4. `contract_compiler/prompt_compiler.py`
   - 每个 persona 独立 PromptSpec（B57）
   - 5 维强度配比写入 prompt（契约强度目标）
   - QualityBar / StyleQualityProfile 写入 prompt 与裁判输入（目标读者、文体标杆、正/反例、禁用俗套、密度目标、盲评策略、继续阅读目标、protected_roughness、voice_anti_samples）
   - 上下文包必须包含：角色声音样本、反面声音样本、失败原因纠正反馈、事实锚点、禁区、目标读者；裁剪时记录原因到 context snapshot
   - deviant 的 `relaxed_soft=True` 仅对 deviant 生效（N3）

### 验证清单
- [ ] X 篇候选来自不同写手模型（多样性来源正确）
- [ ] 同 persona 同 prompt（只有模型变）
- [ ] 创意 shot 产 X+creative_shot_extra 篇
- [ ] DB CHECK 阻止 draft_count > pool 大小
- [ ] deviant 产 1 篇，`is_deviant=True`，`relaxed_soft=True`
- [ ] LLM 失败 → `degraded=True`，不进 jury
- [ ] 5 维强度配比在 prompt 中体现
- [ ] 角色声音样本、反面样本、纠正反馈、目标读者进入 context snapshot；被裁剪项有审计原因
- [ ] 没有 `reader_pull_target` / `blind_review_policy` / `protected_roughness` 不得 confirm-contract
- [ ] N=2 局部重写产 ≥2 篇，与原候选池合并评分
- [ ] orchestrator 入口只收 `(shot_id, run_id)`
- [ ] 对照 `pitfall-checklist.md` P2.N3、P3.B57 核对

---

## M4. 评审层（2 道硬门槛 + 3 裁判 12 维）

### 目标
完整评审流水线跑通：2 道硬门槛 → 3 裁判 12 维 trimmed mean → winner 选择。

### 任务
1. `jury/hard_rule_gate.py`（第一道，规则为主）
   - 契约合规（must_land 出现，规则+模型核验）
   - 禁区检查（forbidden_words/facts，字符串+语义改写）
   - 容量下限（UTF-8 bytes，B93）
   - 基础可读（句长/标点/重复率，机械，N1 治双重惩罚）
2. `jury/hard_rule_gate2.py`（第二道，模型为主）
   - 事实锚点（hard_facts 违约/幻觉）
   - 场景契约对齐
   - POV 合规
   - 结构骨架（beat 顺序/逻辑）
3. `jury/literary_jury.py`（3 裁判全评 12 维，方案 B，评审 #1/#4）
   - 裁判池独立于写手池（N4），DB CHECK 保证 `jury_model_pool >= 3`
   - **3 裁判都评全部 12 维**（NOT NULL，无稀疏），各有"主视角"（prompt 强调主视角维度详细 reasoning）
     - 裁判1（text 主视角）：画面/节奏/对话/悬疑
     - 裁判2（literary 主视角）：语言/情感/人物/结构
     - 裁判3（cross_shot 主视角）：可读/母题/章续/创意边界
   - 每维去 1 高 1 低取 trimmed mean（剩中位数）——方案 B 消除"每裁判只评 4 维无法 trim"的数学矛盾
   - 低分维度硬筛选（某维 3 裁判均分 < dimension_floor 的 draft 淘汰，不允许降权后胜出）
   - 按契约 5 维强度配比加权 → final_score
   - quality floor：final_score >= shot_quality_floor、所有核心维度 >= dimension_floor、judge_disagreement_max <= 阈值、合格候选 >=2、`would_continue_reading_score >= reader_pull_floor`、盲评通过
   - 每条质量问题输出 `evidence_class` 与 `defect_class`；`destructive` 可硬阻断，`productive` 进入保护清单，`neutral` 进入人工 review
   - 文学体验评审、盲评排序、边界复核、返工指导、polish 使用 smart 模型；smart 不可用时阻断，不降级
   - 通过 quality floor 的最高分才可 winner
   - raw 分落 `jury_raw_scores`，trim+质量门禁+加权结果落 `jury_aggregates`
   - 创意 shot：通过第一道门槛的 deviant 稿经 `JuryInput.deviant_reference` 注入给裁判团作创意边界参考（裁判3 评 creative_boundary 时参考）；**无独立 creative_jury**
4. `pipeline/polish_orchestrator.py`
   - winner 后强制 polish_revision，不新增事实，不改变 must_land/POV/scene_contract
   - polish 输入必须包含 QualityReport；只修 destructive，保护 productive_deviations，neutral_issues 交 review
   - polish 后必须验证 productive_deviations 仍可定位，丢失则回退或阻断
   - polish 后重新过 hard gates + quality floor
5. 淘汰后 <2 篇 → 补写（同 persona 同 prompt 换模型）

### 验证清单
- [ ] 第一道门槛 4 维度全跑，规则为主
- [ ] 第二道门槛 4 维度全跑，模型为主
- [ ] eligible=False 的 draft 不进 literary_jury（B66）
- [ ] hard gate 在 literary LLM 调用前（性能诱惑禁止）
- [ ] 3 裁判全评 12 维（NOT NULL，无稀疏），主视角分工正确
- [ ] 裁判模型 ≠ 写手模型（N4）
- [ ] trimmed mean 每 3 个分数去 1 高 1 低
- [ ] 加权按契约 5 维强度配比
- [ ] final_score < shot_quality_floor 不得 winner；任一核心维度低于 dimension_floor 不得 winner
- [ ] `would_continue_reading_score < reader_pull_floor` 或盲评未通过不得 winner
- [ ] destructive 缺陷未清零不得 quality_gate_passed；productive 偏离不得被自动扣成 hard failure
- [ ] smart_model_required 任务不可降级；smart 不可用时阻断而不是用 fast/balanced 继续
- [ ] judge_disagreement_max 超阈值不得 quality_gate_passed
- [ ] raw_scores 与 aggregates 分表落库，is_winner 唯一索引，winner 必须 quality_gate_passed
- [ ] winner 未经过 polish_revision 不得 soft_sealed；polish 后重新过 hard gates + quality floor
- [ ] polish 不得磨平 protected_roughness / productive_deviations；相关测试能检测丢失并阻断
- [ ] deviant 不进 jury 候选池；deviant_reference 注入 literary_jury 评 creative_boundary
- [ ] 无 creative_jury 模块
- [ ] 淘汰后 <2 篇触发补写
- [ ] 对照 `pitfall-checklist.md` P1.6（B66）、P1.13（B54）、P2.N1/N3/N4、P3.B49 核对

---

## M5. Gate 层 + 章级审核

### 目标
quality blocking gate、章级 7 维硬质量门禁、accepted canonical 跑通。

### 任务
1. `gates/` 各 gate 模块（每条显式归 hard/soft/diagnostic，铁律 4）
   - `fact_manifest.py`（hard）
   - `capacity.py`（hard）
   - `l4_scene.py`（hard）
   - `l3_diversity.py`（hard，场景指纹 ≥3，B92/B94）
   - `chapter_hook.py`（QUALITY_BLOCKING，3 级状态机但 N=3 不放行）
   - `exposition_drift.py`（按项目配置可为 SOFT 或 QUALITY_BLOCKING）
   - `intent_drift.py`（diagnostic）
2. `pipeline/gate_orchestrator.py`
   - `run_soft_gates(shot_id, run_id) -> GateResult`
   - 调用 `SoftGateCounter` 实现 3 级升级
3. `pipeline/chapter_review_orchestrator.py`
   - `review_chapter(project_id, chapter_id, run_id) -> ChapterReview`
   - 章级 7 维全部是 accepted 前硬质量门禁：不过返工
   - 信息差 6 态状态机（pending/active/reinforced/revealed/resolved/abandoned，评审 #9）
   - accepted canonical 唯一索引（B61）
4. `writing_failure_attributions` 扩展审计链（评审 #16）
   - 记录 failure_level（draft/hard_gate1/hard_gate2/jury/soft_gate/chapter_review/book_check）
   - 记录 contract_clause_id，支撑条款级审计
   - soft_gate_n 记录第 N 级，injected_to_shot_id 记录问题注入去向
5. `pipeline/human_decision_orchestrator.py`
   - setup_confirm / contract_confirm / accept / revise / reject / abort 全部写 `writing_human_decisions`
   - accept 前置条件结构化写 preconditions_json + quality_report_json；hard_quality_override 固定为 0
   - accept 必须检查 QualityReport：无 destructive blocking、盲评通过、继续阅读达标、productive_deviations 已保护、neutral_issues 已有人类裁决或记录
6. shot 软封版 → 章级审核 → 人工 review → 硬封版流转

### 验证清单
- [ ] 每条 gate 显式标注 GateClass（hard/soft/quality_blocking/diagnostic）
- [ ] quality blocking gate N=3 不放行
- [ ] 章级 7 维任一不过 → 返工，不得 accepted
- [ ] 信息差 6 态状态机正确流转，abandoned 终态合法
- [ ] failure_attributions 记录完整审计链（level/gate_name/n/injected_to）
- [ ] failure_attributions 能关联 contract_clause_id
- [ ] accept/revise/reject/abort 全部写 human_decisions，且 preconditions_json 可审计
- [ ] accept 写 quality_report_json；hard_quality_override 不可为 1
- [ ] accept 前 quality_report_json 必须含 ES/SEMI_ES/NES 与 destructive/productive/neutral 分类
- [ ] 盲评未通过、继续阅读未达标、productive_deviations 丢失时不得 accepted
- [ ] accepted canonical 唯一索引：同章只一个 accepted
- [ ] accept 前置三条件（latest run completed + 全 shot 封板 + 章级审核通过）
- [ ] 对照 `pitfall-checklist.md` P1.11（B61）、P1.12（B58）、P2.N2 核对

---

## M6. 篇级检测 + 导出 + 收尾

### 目标
篇级滚动检测、已有稿导入/重构、导出器、CLI 薄壳、全流程生产验收。

### 任务
1. `pipeline/book_rolling_check_orchestrator.py`
   - 每写完 N 章跑一次（N 从 `writing_projects.chapter_rolling_check_interval` 读，默认 5）
   - 6 维：长线悬念闭环/角色弧光/母题回响/主题升华/全书节奏曲线/伏笔回收
   - 结果落 `writing_book_check_results`（check_run_id + chapter_range + 6 维 + issues，评审 #18）
   - **增量检测**：第 k 次只对 `[上次截止章+1, 当前章]` 区间跑"增量维度"（母题密度/伏笔/悬念 resolved 率可累计），"全局维度"（弧光/主题/全书节奏）全量跑但用上次结果作 baseline 对比，降 LLM 成本
   - 问题注入 `writing_chapter_specs.injected_issues`，早发现不等全书完稿
   - blocking issue 未解决时禁止后续 accept 与 export
2. `pipeline/export_orchestrator.py`
   - 只认 accepted canonical（B61）
   - 结构标签正则清理（B76）
   - 正文通过 text_repository 读取（铁律 5）
3. `cli.py`（薄壳 < 500 行）
   - 命令：init / setup / confirm-contract / write / review / resume / accept / revise / reject / import / export
   - 仅调度 orchestrator，不含业务逻辑
4. `pipeline/import_orchestrator.py`
   - `import --dry-run` 生成 import_run/manifests/questions，不写正式项目数据
   - `import --finalize` 要求 human_decision，校验 source_hash 未变化，原子落库
5. **全流程联调 ≥6 章**（评审 #37，M6 验收硬指标）
   - init → setup×6 → confirm-contract → write×6 → review×6 → 至少一次 revise/reject → 篇级滚动检测（N=5 时第 5 章触发首次）→ accept×6 → export → import dry-run/finalize
   - **为何 ≥6 章而非单章**：第 2 章验证史（P5）证明单章/2 章"通过"可能是 local-default 兜底假象。≥6 章才能触发首次篇级滚动检测、验证章续衔接跨章累积、暴露多章叠加的上下文断裂。单章跑通不等于系统可用。
   - 联调全程禁 local-fallback 占位稿计入"通过"（铁律 3，degraded 不进 jury）

### 验证清单
- [ ] 篇级检测每 N 章触发一次（≥6 章联调中第 5 章触发首次）
- [ ] 篇级 6 维度全跑，结果落 book_check_results
- [ ] 篇级 blocking_issue_count > 0 时不得 accept/export
- [ ] 增量检测：第 k 次只检测新增区间，全局维度用 baseline 对比
- [ ] 问题正确注入 chapter_specs.injected_issues
- [ ] 导出只认 accepted
- [ ] 导出文本无结构标签残留
- [ ] 导出正文通过 text_repository 读取
- [ ] cli.py < 500 行
- [ ] import dry-run 不写正式数据；finalize 必须 human_decision + source_hash 校验
- [ ] **≥6 章全流程联调跑通**：init→setup×6→confirm-contract→write×6→review×6→revise/reject→篇级检测→accept×6→export→import dry-run/finalize，无 local-fallback 假象通过，无质量硬门禁失败被 accepted/export
- [ ] **质量证明门禁跑通**：至少一个完整章节/关键片段通过盲评、继续阅读、must_land 追溯、返工质量提升、productive_deviation 保护验证
- [ ] 对照 `pitfall-checklist.md` 全部条目最终核对

---

## 核对总表

每个里程碑完成后，对照 `pitfall-checklist.md` 逐条核对：

| 里程碑 | 核对条目 |
|--------|---------|
| M0 | P1.1（B19 三重隔离）、P1.15（四层隔离）、P2.N5（字段消费 AST + 访问器） |
| M1 | P1.2-5（B29 14 态/B44/B59/B62）、P1.10（B92 source_revision_id）、P2.N2（soft 3 级 + N 计数语义） |
| M2 | P1.7-9（B77 drift 派生/B87/B88 supersede） |
| M3 | P2.N3（deviant）、P3.B57（persona prompt） |
| M4 | P1.6（B66）、P1.13（B54）、P2.N1（双重惩罚）、P2.N4（裁判池隔离）、P3.B49（方案 B 数学修正） |
| M5 | P1.11（B61）、P1.12（B58）、P2.N2（soft 3 级）、信息差 6 态、failure_attributions 审计链 |
| M6 | 全部条目最终核对 + ≥6 章联调验收 |

---

## 7. 旧测试迁移方法论（557 用例三桶分流，评审 #38）

旧 `inkflow/tests/` 557 个用例不直接搬，按"领域知识是否仍适用"分三桶：

### 桶 A — 契约语义/阈值断言（迁，约 30%）
- **判据**：断言的是**领域不变量**（阈值、状态转移、封版规则、幂等性），与旧 schema/函数签名无关
- **示例**：drift overlap < 0.2 拒绝、第 3 次熔断、封版前读 MAX、shot_id 含 run_id 后缀、accepted 唯一
- **迁移方式**：重写为新 dataclass/新函数签名下的断言，断言值不弱化（铁律：入参签名可改，断言不可弱化）
- **落点**：对应 M0-M5 各里程碑验证清单

### 桶 B — 旧架构绑定（不迁，约 60%）
- **判据**：断言旧 56 表 schema、旧 cli.py 编排路径、旧 dict 传递链、旧双轨迁移逻辑
- **示例**：`assert shot_context_payload['forbidden_facts']`（旧 dict 访问）、旧双轨并行一致性检查
- **处理**：直接弃。新架构从 0 构建，旧架构绑定的断言无对应物。其领域知识已提炼进 `pitfall-checklist.md`

### 桶 C — 行为规约参考（人工转写为新集成测试，约 10%）
- **判据**：端到端行为规约（"写一章→审→导出"流程级断言），旧实现绑定中等但行为语义仍有效
- **示例**：导出文本无结构标签、accept 后正文不可篡改、resume 不覆盖已封版
- **迁移方式**：作为 M6 ≥6 章联调的集成测试场景，人工转写为新 orchestrator 接口下的端到端测试
- **落点**：M6 联调验证清单

### 迁移纪律
- **不机械搬运**：每个旧用例必须先判桶，A 桶重写断言、B 桶弃、C 桶转写集成测试
- **断言不弱化**：A 桶迁移时阈值/状态断言保持原值，若新架构语义变化需显式说明并记入 `pitfall-checklist.md`
- **覆盖率不下降**：A+C 桶迁移后，新测试覆盖的领域不变量数 ≥ 旧 557 用例覆盖的领域不变量数（按"不变量"计数，非用例数）
- **不追求用例数对等**：新架构用 dataclass + AST lint + pyright 替代了大量旧防御性测试，用例数会少很多，这是预期

---

## 下一步
- `design-v2.md`：架构设计与六条铁律
- `implementation-contract-v1.md`：40 张生产表 DDL + dataclass schema + unpack 访问器 + 模块接口 + resume 映射 + sqlparse lint
- `pitfall-checklist.md`：15 条踩坑结晶 + 14 条新增防御（含 jury 方案 B、resume 14 态、质量硬门禁、文学活力保护、字段消费 AST、AI 调用审计、人类决策、导入账本）
- M0 开工：40 张生产表 DDL + 代码生成器 + unpack 访问器 + 字段消费 lint + sqlparse lint + AI/状态 lint
