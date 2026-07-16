# 墨韵 Ink v2 — 踩坑修复对照清单（Shot 中心历史基线）

> **状态**：重构对照清单（2026-07-03），对应 `design-v2.md`
> **用途**：旧系统 94 个 bugfix 里，提炼出"修复逻辑本身是领域知识结晶"的条目。从 0 构建时**必须在新代码里仍成立**——不是保留旧代码，是保留那个判断/阈值/状态转移。
> **用法**：每写一个 `core/` 模块，对照本清单逐条核对"该 bugfix 的修复逻辑在新代码里是否仍成立"。不成立 = 重构引入回归。
> **来源**：旧 `inkflow/docs/bugfix.md` B1-B94 + 旧 `inkflow/docs/history.md` v3.x 生产验证史（仅作领域知识参考，不作继承来源）。
> **Scene-first 迁移规则**：涉及 shot 正文、shot 封版和 shot current revision 的不变量必须提升到 Scene Revision / Chapter Snapshot；内部 shot 只能继承局部幂等、重试和诊断规则，不得继承正式正文权威。

---

## P1. 必须原样保留的修复逻辑（15 条）

### 1. B19 — current revision 硬一致性约束（物理隔离强化）
- **修复逻辑**：`writing_shot_revisions.is_current` 是**封版标记**（不是"当前 winner"）。未封版读 `MAX(revision_sequence)`，已封版读 `is_current=1`。`is_current` 只在封版时设一次。
- **为什么是领域知识**：正文真相源必须区分"最新生成"和"已封版"。混淆会导致重写覆盖已审稿正文。
- **新架构落点**：`core/text_repository.py`，函数 `read_current_text(shot_id, run_id)`
- **物理隔离强化**（铁律 5，评审 #3 修订）：`writing_shot_revisions` 表三重约束——
  1. **Python import 边界**：`writing_shot_revisions` 的 SQL 访问函数只暴露在 `core/text_repository.py`；`contract/generated/` 不生成 `ShotRevision` dataclass 公开加载器
  2. **DB VIEW `v_current_text`**：封版逻辑封进 view——`ROW_NUMBER() OVER (PARTITION BY shot_id ORDER BY is_current DESC, revision_sequence DESC) = 1` 优先级单行返回（每 shot_id 恰好一行）。**禁 OR 并集写法**（`is_current=1 OR revision_sequence=MAX` 在 redo/崩溃重跑同 shot 既封版又有更高未封版行时返回两行，违反单条不变量，评审 P0-3）
  3. **CI sqlparse lint**：`codegen/sql_access_lint.py` 解析所有 `execute()` 的 SQL token，断言只有 `core/text_repository.py` 含 `writing_shot_revisions` 表名（白名单 migration/schema/test）；动态表名构造、f-string 拼接 SQL 一律禁
- **接口最小化**：text_repository 只暴露 `read_current_text` / `write_revision` / `is_hard_sealed` 三个方法，**禁止** `get_text_by_revision_id` 类直查后门（旧系统用这类后门跳过封版判断）
- **诚实声明**：SQLite 无 RLS，物理隔离是三重软约束（Python import + DB VIEW + sqlparse CI），非 DB 层硬隔离。需真物理隔离要迁移 PostgreSQL + RLS
- **核对**：封版前读 MAX(revision_sequence)，封版后读 is_current=1 行；**P0-3 后走 v_current_text VIEW 的 ROW_NUMBER() 单行判定**（业务模块只读到唯一一行当前正文，无 OR 多行 bug）；is_current 硬封版时把同 shot 旧行置 0；全代码库只有 text_repository 直接访问该表；无直查后门接口 ✓

### 2. B29 — resume 跳过已完成 shot
- **修复逻辑**：循环开头检查 `shot_status IN (done_green, done_yellow)` 直接 skip，不重新生成。
- **为什么是领域知识**：崩溃恢复不能覆盖已有成果，这是生产可恢复性的最低要求。
- **新架构落点**：`core/resume.py`，`ResumeManager.RESUME_MAP`（14 态 → resume 行为映射矩阵，评审 #5 + 质量硬门禁）：
  - **done 类 skip**：`soft_sealed`/`hard_sealed`/`failed`
  - **generating 类幂等重跑**（已落库行按 `(shot_id, run_id)` / `(draft_id, judge_model)` 去重，P0-4）：`drafting`/`hard_gate1`/`hard_gate2`/`jury_scoring`/`winner_selected`
  - **pre-drafting 类重跑**（靠 `superseded_at` 幂等，旧行打戳写新行）：`outline_draft`/`outline_confirmed`/`task_card_compiled`/`prompt_compiled`
  - **`pending`**：start_from_scratch
- **N=2 局部重写的崩溃恢复**（评审 #6）：`writing_shots.redo_in_progress` 子状态标记。崩溃恢复时——`redo_in_progress=1` 且无新候选 draft = 重跑局部重写；有新候选但无新评分 = 重跑评分。N 计数绑 `logical_shot_id + gate_name`（跨 run 累积），不随崩溃重跑归零。
- **核对**：done 类 skip；generating 类幂等重跑去重；pre-drafting 类 supersede 幂等；redo_in_progress 子状态正确恢复；N 计数跨 run 不丢 ✓

### 3. B44 — aborted/crashed session 显式绑定
- **修复逻辑**：resume 显式绑定指定 `session_id`，不委托 run 重新选最新；异常路径标记 `session_status=crashed`。
- **为什么是领域知识**：多 session 并存时"恢复最新"会串到错对象。
- **新架构落点**：`core/resume.py` + `core/session_manager.py`。`resume_point` 结构化 JSON `{phase, chapter_id, dimension_index}`（评审 #17）：phase 标崩溃所在步骤，dimension_index 标多维度步骤（如 jury 12 维）崩溃到哪一维，恢复时从该维度续跑而非整步骤重跑。
- **核对**：resume 必须带 session_id 参数，不自动选最新；resume_point 结构化可定位到维度 ✓

### 4. B59 — RetryBudget 熔断（两层，评审 P0-5 拆分）
- **修复逻辑**：**先计算 next_count 再判断阈值**（不是先判再算，否则第 4 次才触发）。同类失败连续 3 次 → `done_red_permanent`。失败类型切换时连续计数归零（不叠加）。
- **两层预算（评审 P0-5 拆分，原"8 次上限"语义不清）**：
  1. **重试失败熔断 `max_calls_per_shot`（默认 8）**（B59 原义）：同类失败连续 `consecutive_failure_circuit_break`（默认 3）次熔断；失败类型切换归零；shot 内重试调用 ≤ `max_calls_per_shot`。粒度是"同一失败类型的连续重试"。
  2. **shot 总调用硬上限 `max_total_llm_calls`（默认 40）**（P0-5 新增）：整个 shot 生命周期（draft + gate2 模型核验 + jury 3 裁判 + redo 重写 + 章级审核）所有 LLM 调用总和上限。防"每类失败都不足 3 次、但 12 类失败各重试 2 次 = 24 次 + 正常调用"绕过第 1 层烧穿。耗尽 → `transition(status,'failed')` 终态，不自动重试（需新建 run）。
- **参数化**：以上阈值均在 `writing_projects` 表，运行时可调不改代码。
- **调用类型维度**：计数带 `call_type ∈ {'draft','gate2','jury','chapter_review'}`，第 1 层熔断按 `(shot_id, call_type, failure_type)` 三元组计数连续失败；第 2 层按 `shot_id` 总和。
- **计数落 DB**：总量落 `writing_shots.llm_call_count` + `llm_call_breakdown`；连续失败落 `writing_llm_failure_streaks(shot_id, call_type, failure_type)`；每次调用明细落 `writing_ai_call_attempts`；状态变化落 `writing_runtime_events`。`LLMCallBudget.check_circuit(shot_id)` 无状态读 DB。
- **为什么是领域知识**：无意义重试会烧穿成本 + 污染上下文。不同类型失败不叠加，避免误杀。两层分离：第 1 层防同类死循环，第 2 层防类型分散绕过。
- **新架构落点**：`core/retry_budget.py`，`LLMCallBudget.check_circuit(shot_id)` / `record_call(shot_id, call_type, success, failure_type=None)`
- **核对**：先算 next_count 再判阈值；类型切换归零；3 次熔断；8 次/类型上限；40 次总量上限；AI attempt 和 failure streak 落 DB；耗尽转 failed 终态 ✓

### 5. B62 — shot_id = {logical}@{run} 隔离
- **修复逻辑**：`logical_shot_id` 用于契约定位（跨 run 稳定），生产 `shot_id = f'{logical}@{run_id}'` 用于执行外键。同章重写必须新建 run attempt shot 行，禁止复用旧正文。
- **为什么是领域知识**：同一故事位置多次执行时，逻辑身份和执行身份必须分离，否则跨 run 复用旧正文。
- **新架构落点**：`core/session_manager.py`，函数 `make_attempt_shot_id(logical, run_id)`
- **核对**：shot_id 含 run_id 后缀；同章重写新建行不复用 ✓

### 6. B66 — eligibility 先于文学 jury（两道硬门槛强化）
- **修复逻辑**：硬门槛在文学评分前执行，违约稿 `eligible=False`，**不进入文学评分**。
- **为什么是领域知识**：先判资格再 PK 文学，否则"顺滑但违约"的稿会晋级（第 3 章真实发生）。
- **新架构落点**：2 道硬门槛
  - 第一道（`jury/hard_rule_gate.py`，规则为主）：契约合规/禁区/容量下限/基础可读
  - 第二道（`jury/hard_rule_gate2.py`，模型为主）：事实锚点/场景契约对齐/POV 合规/结构骨架
- **性能诱惑禁止**：hard gate 必须在任何 literary/cultural LLM 调用之前完成。不得"先算 literary 分再判 hard eligibility"以节省 LLM 调用——这破坏 B66。
- **核对**：两道门槛的 eligible=False 的 draft 不进 `literary_jury.score` 入参；hard gate 在 literary LLM 调用前 ✓

### 7. B77 — 大纲幻觉 drift 检测
- **修复逻辑**：大纲重生成后，与原始大纲做 CJK bigram overlap 计算。overlap < 0.20 → 拒绝这版再生。
- **为什么是领域知识**：大纲重生成有幻觉风险（曾产出"1979 工厂→安保机器人"这种完全无关的内容），必须相似度校验。
- **新架构落点**：`pipeline/outline_orchestrator.py`，落 `writing_outline_specs.drift_score`（0-1 越高越接近）。**`drift_rejected` 不再存列**（评审 #23，铁律 2"一个信号只存一处"）：派生自 `drift_score < writing_projects.outline_drift_threshold`（默认 0.20，运营可调），消费端实时计算，避免列与列不一致。`is_winner` 加唯一约束保证大纲 PK 只选一个 winner。
- **核对**：CJK bigram overlap < 0.2 拒绝；drift_score 落库；drift_rejected 派生不存列；is_winner 唯一索引 ✓

### 8. B87 — outline_has_incomplete_tail
- **修复逻辑**：检查大纲/task card 文本是否以完整句子结尾（句法落地）。半句 → 拒绝，writer 不执行。
- **为什么是领域知识**：模型可能产出半句结尾，writer 忠实执行后反复截断，必须在 task card 层拦截。
- **新架构落点**：`core/outline_integrity.py`，函数 `outline_has_incomplete_tail(text)`
- **核对**：task card 编译后调用此函数，半句拒绝落库 ✓

### 9. B88 — prompt cache 软覆盖（ON CONFLICT 语义）
- **修复逻辑**：同一 `(run, shot, persona)` 二次编译 prompt 时，**旧行打 `superseded_at` + 写新行**，不用 `ON CONFLICT DO UPDATE` 原地改（保留历史版本用于审计）。resume 拿到的总是最新未覆盖版。
- **为什么是领域知识**：prompt 缓存必须可更新（代码修复后要用新 prompt），但原地改会丢审计历史。
- **新架构落点**：`contract/prompt_spec.py` + `writing_prompt_snapshots` 表，`superseded_at` 机制；同样适用于 `writing_shot_task_cards`
- **核对**：二次编译写新行 + 旧行打戳；resume 读 `superseded_at IS NULL` ✓

### 10. B92 — 上游 revision stale 时下游不跳过
- **修复逻辑**：resume 对已完成 shot，检测上游 `source_revision_id` 的时间戳是否 stale。上游重写后（targeted redo），下游**不静默跳过**，需要重新生成。
- **为什么是领域知识**：targeted redo 后，下游 shot 依赖的上游文本已变，继续用旧 revision 会导致上下文断裂。
- **新架构落点**（评审 #12/#21）：`core/resume.py` 的 `should_skip(shot)` 内检查上游 revision 时间戳。DB 支撑：
  - `writing_shot_revisions.source_revision_id`：跨 run 指向上游 revision，redo 后新 revision 行的 source 指向更新
  - `writing_drafts.source_revision_id`：draft 封版时指向对应 revision，下游读 draft 时比对 source_revision_id 是否仍为 v_current_text 当前行的 revision_id（P0-3 后"当前"由 ROW_NUMBER 单行判定，非裸 is_current=1）
  - 不一致 = 上游已 redo，下游 done 状态不 skip，重跑
- **核对**：上游 revision 更新后，下游 done 状态不 skip；source_revision_id 列正确落库与比对（比对基准 = v_current_text 当前行 revision_id）✓

### 11. B61 — accepted canonical 状态机
- **修复逻辑**：`--accept` 必须 ① latest run completed ② 全 shot 封板 ③ 章级审核通过。`--revise`/`--reject` 退回 redo。默认导出只认 accepted。`writing_chapter_reviews` 的 `WHERE status='accepted'` 唯一索引保证同章只一个 accepted。
- **为什么是领域知识**：人工审稿是正式正文唯一入口，未 accepted 的不能进入后续上下文（否则 rejected 正文污染正式导出）。
- **新架构落点**：`core/session_manager.py` + `pipeline/export_orchestrator.py` + `pipeline/chapter_review_orchestrator.py`
- **核对**：accept 前置三条件；导出只认 accepted；唯一索引 ✓

### 12. B58 — L4/L3 前移为硬 gate
- **修复逻辑**：L4 在 shot finalize 前执行，L3 在 session complete 和导出前执行。未通过 → `ClickException` 停止，不 complete session 不自动导出。
- **为什么是领域知识**：gate 在 finalize 之后执行等于没有 gate（曾导致 L4/L3 失败仍 complete + 导出）。
- **新架构落点**：`pipeline/gate_orchestrator.py`，gate 按硬/软/诊断三层分类（铁律 4）
- **核对**：L4 在 finalize 前；L3 在 complete/export 前；fail 抛异常停止 ✓

### 13. B54 — timeout 不当 50 分
- **修复逻辑**：`_score_single()` 返回 `failed=True`，类型/文学层跳过该 draft 的失败分，不当 50 分进均分。
- **为什么是领域知识**：基础设施失败不能当作品低分，否则供应商抖动会压低质量分并触发无效重写。
- **新架构落点**：`jury/literary_jury.py`，degraded draft 在硬门槛已排除（铁律3），不会进评分
- **核对**：timeout 的 draft `degraded=True`，不进 jury 候选池 ✓

### 14. B93 — 字数口径用 UTF-8 bytes
- **修复逻辑**：titled shot ≥ `capacity_floor_titled_shot`（默认 1200）bytes，章末 ≥ `capacity_floor_chapter_end`（默认 1500）bytes，用 `len(text.encode("utf-8"))` 统一口径。不让 AI 自计汉字。阈值在 `writing_projects` 可调。
- **为什么是领域知识**：AI 无法可靠自计汉字，程序侧统一 bytes 口径。
- **新架构落点**：`gates/capacity.py`，函数 `check_bytes(text, min_bytes)`（第一道硬门槛的子项）
- **核对**：UTF-8 bytes；阈值从 `writing_projects.capacity_floor_titled_shot`（默认 1200）/`capacity_floor_chapter_end`（默认 1500）读取，运行时可调；不问 AI ✓

### 15. B19+B62+B61 合并 — 四层执行隔离
- **修复逻辑**：`logical_shot_id`（逻辑身份）+ `run_id`（执行身份）+ `accepted`（审稿状态）+ `is_current`（封版状态）是**正交的四个维度**，缺任何一个都会导致旧产出混入新产出。
- **为什么是领域知识**：执行身份、逻辑身份、审稿状态、封版状态正交，这是"旧 run 污染新产出"类 bug（B6/B16/B45/B60/B61/B62/B91）的总根因。
- **新架构落点**：`core/` 整体（session_manager + text_repository + resume）
- **核对**：四个维度独立查询，不互相推导 ✓

---

## P2. 新架构新增的踩坑防御（12 条）

这些是从 3 专家评审发现的"旧系统没有、新架构必须防御"的设计缺陷：

### N1. reading_fluency 双重惩罚消除
- **问题**：旧系统门槛层和文学层都有 `reading_fluency`，draft 得 70 分（过门槛但低）会进文学层又拉低 trimmed mean——同一维度被罚两次。
- **新架构落点**：
  - 门槛层用 `基础可读`（`gates/capacity.py` 的机械检查：句长/标点/重复率），纯规则
  - 文学层用 `可读流畅`（`jury/literary_jury.py` 的 reading_fluency 维度），模型评质感
  - 两者名称不同、层不同、口径不同
- **核对**：门槛层"基础可读"是机械规则；文学层"可读流畅"是模型质感；不重名不重叠 ✓

### N2. soft gate 3 级状态机（防死循环，但质量类不放行）
- **问题**：旧系统 soft gate 阻断封板不 redo，会卡死（exposition_drift 失败时"注入下一 shot"不解决当前 shot 封板）。
- **新架构落点**：`core/retry_budget.py` 的 `SoftGateCounter`，同一 logical_shot_id 同一 soft gate 连续失败 N 次：
  - N=1：阻断封板，标记问题，不 redo
  - N=`soft_gate_redo_n`（默认 2）：触发该 shot 局部重写（换模型产 **≥2 篇**新候选，与原 winner 候选池合并重新评分选优，评审 #11）
  - N=`soft_gate_fail_n`（默认 3）：非质量 SOFT 可降级为 diagnostic 放行；`QUALITY_BLOCKING` 不得放行，必须 revise/reject 新建 run 或 failed
- **参数化**：以上 N 阈值在 `writing_projects` 表，运行时可调不改代码。
- **N 计数语义**（评审 #6，崩溃恢复关键）：
  - **权威源是 DB 结构化表**：`writing_soft_gate_counters(project_id, logical_shot_id, gate_name)`，每次 soft gate 判定后**立即原子累加**（非封版时才落）
  - `writing_shots.soft_fail_counts_snapshot` 只做审计快照，不允许业务读取
  - `SoftGateCounter` **无状态**：`get_level(project_id, logical_shot_id, gate_name)` 从 DB 读，不维护内存计数，崩溃不丢
  - **N 绑 `logical_shot_id + gate_name`**（跨 run 累积）：同一 logical shot 重跑计数延续，否则崩溃重跑归零致状态机失效
  - `redo_in_progress` 子状态标记 N=2 局部重写进度，崩溃恢复据此续跑（见 B29）
  - **多 soft gate 叠加预算保护**：同 shot 多 gate 同时 N=2，合并为 1 次局部重写，按 shot 汇总 LLM 调用
- **核对**：3 级升级；N=2 局部重写产 ≥2 篇且仅在 winner_selected 阶段翻盘；soft_sealed 后新建 run；非质量 N=3 降级不卡死；质量类 N=3 不放行；N 计数 DB 权威 + 无状态读 + 跨 run 累积；多 gate 叠加合并重写 ✓

### N3. deviant 评审流程隔离
- **问题**：deviant 是参考沙盒，不能进 winner 选择，但也不能完全不审（否则可能违反 forbidden_facts）。
- **新架构落点**（评审 #4，方案 B）：
  - deviant 产稿走**第一道硬门槛**（规则检查，防严重违约）
  - deviant **不走第二道硬门槛和 3 裁判评分**（不进 winner 候选池）
  - **无独立 creative_jury**：创意 shot 也走 `literary_jury`。通过第一道门槛的 deviant 稿经 `JuryInput.deviant_reference` 注入给裁判团作"创意边界参考"（裸文本不评分），裁判评 `creative_boundary` 维度时参考该文本理解软约束偏离的可行边界。deviant 失败稿不注入。
  - deviant 失败 → `degraded=True`，不返写，记审计
  - `relaxed_soft=True` 字段仅对 `persona=deviant` 生效，其他 persona 必须忽略
- **核对**：deviant 只过第一道门槛；不进 jury 候选池；deviant_reference 注入 literary_jury；无独立 creative_jury；relaxed_soft 仅 deviant 生效 ✓

### N4. 裁判池与写手池隔离（防自评偏见）
- **问题**：若裁判模型和写手模型重合，写手模型评自己的稿有自评偏见。
- **新架构落点**：`writing_projects.jury_model_pool` 独立于 `writer_model_pool`。3 裁判从 jury_model_pool 取，X 篇候选从 writer_model_pool 取。
- **隔离强度（评审 P0-4 升级，两层）**：
  1. **配置层强校验**：`ProjectConfigValidator` 要求 writer_model_pool 与 jury_model_pool 无交集；若供应商有限必须重叠，则要求“排除该 draft 的 writer_model 后仍至少 3 个 jury model”。SQLite CHECK 不支持跨 `json_each` 子查询，不能把该约束伪装成 DB CHECK。
  2. **按 draft 动态排除（必走）**：`literary_jury.dispatch` 为每个 draft 选 3 裁判时，从 jury_model_pool 中**动态排除产出该 draft 的那个 writer_model**（`writing_drafts.writer_model`），保证"裁判模型 ≠ 产出该 draft 的写手模型"。粒度是**按 draft** 而非按 shot——同一 shot 的不同候选稿由不同写手模型产出，各自排除各自的写手模型。
- **审计**：`writing_jury_raw_scores` 落库时 `judge_model` 与该 draft 的 `writing_drafts.writer_model` 比对，断言不相等（应用层 post-write 校验）。
- **核对**：(1) 配置层模型池隔离校验通过；(2) 按 draft 动态排除生效；(3) `SELECT judge_model FROM writing_jury_raw_scores r JOIN writing_drafts d ON r.draft_id=d.draft_id WHERE r.judge_model=d.writer_model` 返回空 ✓

### N5. 字段消费完整性（铁律 1 的强制机制，评审 #2 修订）
- **问题**：旧系统 pyright 只保证"字段存在"不保证"字段被消费"，forbidden_facts 就这么丢的。
- **新架构落点**：`ink/src/ink/codegen/field_usage_lint.py`，CI 强制运行。两道防线：
  1. **访问器 API 强制**：生成器为每个 dataclass 产出 `unpack()` 方法，消费端用 `unpack()` 解构或具名属性访问（`ast.Attribute` 节点）。**禁止**动态访问：`getattr`/`vars`/`__dict__`/`dataclasses.asdict`/`**x` 一律报错
  2. **字段消费可达性扫描**：动态访问禁令扫描所有 import 了 generated dataclass 的模块；全字段消费只作用于契约边界函数（contract compiler、prompt compiler、gate input builder、jury input builder、shot 级 orchestrator 入口）和显式标注 `@requires_full_field_consumption` 的函数。**不再用"字段名出现在源码字符串"的词法匹配**（治误报：字段名在注释/f-string/log 里不算消费；治漏报：动态访问被防线 1 拦截）
- **核对**：CI 跑 field_usage_lint；契约边界函数的上游字段被 ast.Attribute 引用；普通 helper 不直接接收 generated dataclass；无动态访问后门 ✓

### N6. shot 状态机 14 态合法转移矩阵（评审 P0-2）
- **问题**：无显式转移矩阵时，status 推进靠散落在各 orchestrator 的 `UPDATE ... SET status=?`，非法转移（如 `hard_sealed → drafting`）无法在 DB 层拦截，并发改也无人守。
- **新架构落点**：`core/state_machine.py` 的 `LEGAL_TRANSITIONS` 集合穷举 14 态合法转移（见 implementation-contract §3.5b 矩阵表）。`transition(shot_id, run_id, prev, next)` 统一入口，乐观锁 CAS：`UPDATE ... WHERE status=:prev` 断言 `affected_rows=1`。`winner_selected` 必须先进 `polish_revision`，不得直接 `soft_sealed`。终态 `hard_sealed`/`failed` 无出边，`failed` 需新建 run_id 重跑（旧 failed shot 留档审计，不 `→pending`）。
- **核对**：(1) 非法转移抛 `IllegalTransitionError`；(2) 并发改抛 `ConcurrentModificationError`（不自动重试）；(3) 终态出边抛 `TerminalStateError` ✓

### N7. 并发模型与隔离边界（评审 P0-2）
- **问题**：多 run 同 logical shot 并发时 N 计数（绑 logical_shot_id）有竞态；同 session 内多 shot 并发会破坏 N 计数/redo 状态机一致性。
- **新架构落点**：当前**单 session 串行**假设（gate_orchestrator 串行推进，无同 session 多 shot 并发）；多 session 靠 `shot_id={logical}@{run}` 行级隔离。跨 session 同 logical shot 并发的 N 计数竞态，靠 N=2/N=3 动作幂等缓解（重复触发只是多产候选/重复标记 degraded，jury 仍选最优）。未来多 worker 预留 `pg_advisory_xact_lock`（迁移 PostgreSQL 后）。
- **核对**：(1) gate_orchestrator 无同 session 并发 shot；(2) `transition()` CAS 守护所有 status 改写；(3) N 累加用 `UPDATE SET count=count+1` 原子操作 ✓

### N8. AI 调用必须可审计与可恢复
- **问题**：只存 shot 级计数无法恢复连续失败 streak，也无法追溯 prompt/response/token/error。
- **新架构落点**：`core/llm_gateway.py` 是唯一 AI 调用入口；每次调用写 `writing_ai_call_attempts`，状态变化写 `writing_runtime_events`，连续失败写 `writing_llm_failure_streaks`。
- **核对**：供应商 SDK 只允许在 `core/llm_gateway.py` 出现；每次调用都有 idempotency_key；失败后崩溃重启仍能读到 streak ✓

### N9. 人工决策必须结构化
- **问题**：accept/revise/reject 若只改表状态，无法解释谁在什么条件下做了什么决定。
- **新架构落点**：`writing_human_decisions`，记录 actor、reason、target session/run/chapter/shot、preconditions_json。
- **核对**：setup confirm、contract confirm、accept、revise、reject、abort、import_finalize 都必须写 human_decisions；没有 human decision 不得 hard seal / finalize import ✓

### N10. 契约可审计性必须到条款级
- **问题**：failure attribution 只有自由文本时，无法追踪违反了哪条契约，也无法做 D-23 的条款级仪表盘。
- **新架构落点**：`writing_contract_clauses`、`writing_contract_changelog`、`writing_failure_attributions.contract_clause_id`。
- **核对**：每个 hard/soft/diagnostic gate issue 必须能关联 clause_id 或显式标注 `unmapped_reason`；契约修改必须写 changelog ✓

### N11. checkpoint 是崩溃恢复的生产能力
- **问题**：仅靠 status + resume_point 不足以证明恢复不会覆盖已完成成果。
- **新架构落点**：`writing_session_checkpoints`，每个稳定阶段写 checkpoint，按 session 保留最近 `checkpoint_max_retention`（默认 3）个稳定点。
- **核对**：drafting/jury/soft_gate/chapter_review/import_finalize 崩溃恢复测试必须通过；已 hard_sealed 文本不可被恢复流程覆盖 ✓

### N12. 已有稿导入与重构是一等流程
- **问题**：没有导入账本时，已有稿重构只能靠外部脚本，无法 dry-run、低置信裁决、source hash 防漂移。
- **新架构落点**：`writing_import_runs`、`writing_import_manifests`、`writing_import_questions`、`writing_import_decisions`。
- **核对**：dry-run 不写正式数据；finalize 必须 human decision；source_hash 变化后旧 dry-run 不得 finalize ✓

### N13. 写作质量必须硬门禁
- **问题**："最高分"可能只是烂稿中相对最好；soft gate 注入后文也可能让当前章带病 accepted；人工 accept 若可 override 硬失败，会把质量问题变成审计文本而非阻断。
- **新架构落点**：
  - `writing_projects` 表的质量阈值字段（`shot_quality_floor`/`dimension_floor` 等）和 `style_quality_profile` 定义项目级"什么叫好"。
  - `writing_jury_aggregates.quality_gate_passed`、`judge_disagreement_max`、`quality_gate_reasons` 记录 shot 级硬门禁。
  - `polish_revision` 是 winner 后、soft seal 前的强制状态。
  - `writing_chapter_reviews.quality_gate_passed` 和 7 维阈值阻断 accepted。
  - `writing_book_check_results.blocking_issue_count` 阻断后续 accept/export。
  - `writing_human_decisions.quality_report_json` 记录质量报告，`hard_quality_override=0` 禁止人工覆盖硬失败。
- **核对**：final_score 低于阈值不得 winner；核心维度低于阈值不得 soft seal；裁判分歧过大不得直接 winner；winner 未 polish 不得 soft seal；章级 7 维不过不得 accept；篇级 blocking issue 不得 export；human accept 不能 override 硬失败 ✓

### N14. 硬门禁不能磨平文学性
- **问题**：质量门禁如果只追求平滑、规整、低风险，会把角色声线、有效留白、粗粝感和有价值的反常句式磨掉，最终产出“无错误但无生命力”的 AI 腔。
- **新架构落点**：
  - `QualityReport` 必须标注 `evidence_class`（ES/SEMI_ES/NES）和 `defect_class`（destructive/productive/neutral）。
  - `QualityBar.reader_pull_floor` 与 `blind_review_min_passes` 把“想继续读”和盲评写入质量证明。
  - `StyleQualityProfile.protected_roughness` / `voice_anti_samples` 定义必须保护的文学特征与反面样本。
  - `polish_revision` 只修 destructive；`productive_deviations` 必须保留，`neutral_issues` 进入人工 review。
  - 文学体验评审、盲评排序、返工指导、polish 标 `smart_model_required=True`，不可降级。
- **核对**：盲评未通过不得 accepted；`would_continue_reading_score` 低于阈值不得 winner；productive_deviation 被 polish 删除必须阻断；NES 项不得伪装成 ES 自动判死；smart 模型不可用时阻断而非降级 ✓

---

## P3. 重构时需注意但非原样保留的修复（5 条）

这些是"修复方向对，但实现要在新架构里重新设计"的：

### B49 — 分层裁判不可混合平均
- 旧修复：把硬规则/类型/文学拆成三阶段。
- 新架构（评审 #1 方案 B）：2 道硬门槛 → 3 裁判**全评** 12 维 trimmed mean。**3 裁判都填全部 12 维**（NOT NULL，无稀疏），保证每维有 3 个分数可去 1 高 1 低。旧设计"每裁判只评 4 维"有数学矛盾：某维只 1 裁判评无法去极值。每层结果不可混入其他层均分。
- 落库：raw 分落 `jury_raw_scores`（1 行/裁判×draft，12 维 NOT NULL），trim+加权结果落 `jury_aggregates`（1 行/draft，12 维 trimmed mean + weight_used + final_score）
- 核对：门槛层 `eligible` 不进 literary_jury 的 trimmed mean；3 裁判全评 12 维；raw 与 aggregate 分表 ✓

### B57 — persona prompt 不可互相污染
- 旧修复：4 persona 各用独立 prompt。
- 新架构：`contract/prompt_spec.py` 每个 persona 独立 `PromptSpec`，deviant 额外 `relaxed_soft=True`。一个 shot 只用一个 persona（契约指定），该 persona 产的 X 篇都用同一 PromptSpec。
- 核对：PromptSpec 独立编译落库；同 shot 的 X 篇共享同一 PromptSpec ✓

### B48 — 本地兜底不忽略 prompt
- 旧修复：local-default 生成器读取 prompt 的 must_land/opening/POV。
- 新架构：`writers/local_fallback.py` 标 `degraded=True`，**不进 jury**（铁律3），所以"是否忽略 prompt"不再影响质量判定——它只是占位。
- 核对：degraded draft 排除出 jury 候选池 ✓

### B76 — 导出器标题不泄漏结构标签
- 旧修复：导出时剥离 `（冲突1、章末钩子）` 等结构标签。
- 新架构：`pipeline/export_orchestrator.py` 统一剥离，泛化为"结构标签正则清理"。
- 核对：导出文本无结构标签残留 ✓

### B92/B94 — 场景多样性 gate
- 旧修复：加 distinct scene count 检查。
- 新架构：`gates/l3_diversity.py`（GateClass.HARD），场景指纹 >= `scene_fingerprint_min_diversity`（默认 3），落 `writing_shot_scene_fingerprints` 表。阈值在 `writing_projects` 可调。
- 核对：L3 多样性 gate 硬阻断；指纹表落库 ✓

---

## P4. 反复复发模式总览（重构根治目标）

这 5 个模式是"修了仍不稳定"的根因，新架构的六条铁律逐一对应：

| 反复复发模式 | 对应 bug | 新架构铁律 |
|-------------|---------|-----------|
| 契约信号逐层弱化丢失 | B28→B48→B67→B87→B92 | 铁律1（代码生成 + unpack 访问器 + AST 字段消费 lint） |
| 多真相源互相覆盖 | B16→B45→B60→B62 | 铁律2（DB 真相源 + orchestrator 物理隔离 + 契约字段拆表） |
| 静默降级掩盖故障 | B14→B47→B48→B54→B55 | 铁律3（显式 degraded） |
| 旧 run/旧契约残留污染 | B6→B16→B45→B60→B61→B62→B91 | 铁律2 + B19/B62/B61 四层隔离 + resume 14 态映射 |
| gate 假阳假阴反复 + soft 死循环 | B79→B80→B89→B90→B92→B94 | 铁律4（hard/soft/diagnostic + soft 3 级状态机，N 计数 DB 权威跨 run 累积） |
| 正文真相源被 SQL 绕过 | B19 | 铁律5（Python import + DB VIEW + sqlparse 三重隔离） |

---

## P5. 生产验证史（"修好了"又复发的证据）

### 第 2 章验证（QUAL-1, 2026-06-26）
- 声称：4/4 shots 全 green/yellow，L3 通过，可用于受控试跑。
- 复发：v3.18 第 3 章立刻暴露 B52/B53/B54。
- **教训**：第 2 章的"通过"是 local-default 兜底通过，不是真实质量通过。→ 铁律3 保证 degraded 不进 jury，"通过"必须基于真实 draft。

### 第 3 章远端（CHAPTER-3-REMOTE, 2026-06-27）
- 声称：5/5 green，均分 88.3，L3 通过。
- 复发：CONTENT-GATE-1（06-28）人工审稿发现标题边界错位、废弃角色名、未授权医疗事实、短 hook。
- **教训**：5/5 green 不等于可投产。jury 高分只因"语言顺滑"，不代表 must_land 落地。→ 铁律1 保证 must_land/forbidden_facts 字段真到 prompt（字段消费 lint）；B66 保证违约稿不晋级（两道硬门槛）。

### Contract-first 重校准（2026-06-29）
- 原话："旧管线跑通不代表质量可靠。大纲门禁没有真正拦住契约违规，赛马评估可能选出语言较顺但事实违约的稿。"
- **教训**：这是对前 3 轮"修好了"的直接否定。→ 新架构的 2 道硬门槛 + 3 裁判 12 维分层根治。

### B76-B94 第 3 章返工（2026-07-01）
- B90 刚加 titled shot 密度检查，B92/B94 又发现场景层面无 diversity gate。
- **教训**："gate 补一个洞、下一个洞又开"的循环。→ 铁律4 要求每条 gate 规则显式归 hard/soft/diagnostic，soft gate 有 3 级状态机不卡死。

---

## P6. 核对流程（每个里程碑执行）

1. 写 `core/` 模块前，先读本清单对应条目
2. 模块写完，逐条核对"修复逻辑在新代码里是否成立"
3. 不成立的条目 = 重构回归，必须改到成立
4. 核对结果记入 `docs/migration-plan.md` 的对应里程碑验证清单

---

## 下一步
- `migration-plan.md`：从 0 构建完整生产版的 M0-M6 步骤、验证清单（无工期、无双轨、无 MVP）；M6 联调 ≥6 章；557 旧测试三桶迁移方法论
- `design-v2.md`：架构设计与六条铁律
- `implementation-contract-v1.md`：49 张生产表 DDL + dataclass schema + unpack 访问器 + 模块接口 + resume 映射 + sqlparse lint
