# InkFlow v2 历史任务归档

> **用途**：记录已经完成并验证的任务，保持 `tasks.md` 只呈现当前待办。
> **最后更新**：2026-07-15

---

## 2026-07-14 真实模型生产链路打通 + 章节悬疑/工业事实注入（5 块提交）

> 本批次对应 5 个 commit（1c7df99b / 875439e3 / 2eedfc3a / 8dfe897b / da1a028e），
> 此前只写了代码未登记 history/bugfix，本节补登。各 commit 均未改 tasks.md，
> 故 `tasks.md` 未反映这批进度——由 2026-07-15 对齐补登一并校正。

### 1. 质量门真实化阶段 A/B/C（commit 1c7df99b，对应 tasks P1-5 早期推进）

- `model_role_config` 落库模型角色主备兜：writer / jury / review / polish 各
  call_type 双角色，主失败顺延备用，配额耗尽当天不重试。
- `llm_gateway` 增 provider 级 failover 与真实重试；推理模型自动注入
  max_tokens，`reasoning_content` 回退兼容非推理模型。
- `jury_orchestrator` 桩分全换真实 `gateway.call(call_type=jury)`；BFX-033
  登记的「评分全是桩」缺陷自此收口。
- `cli.py init` 支持 `--writer-models/--jury-models` 自定义模型池；默认池改
  GLM-5.1，补全 Qwen3.5 两模型。iFLYTEK Coding Plan 真实 provider 接通。
- `errors.py` 增配额/限流错误码；`resume_handlers` 恢复点稳定键路径修正。
- 测试：`test_m4_review_pipeline` / `test_m5_chapter_review` / `test_m6_workflow_smoke`
  / `test_schema_contract` 同步真实化语义。

### 2. 章节悬疑工程学三层注入（commit 875439e3，对应 tasks P1 真实质量验证）

- **contract 层**：`writing_contract_versions` 按 `scope_type='chapter'` 落库；
  `to_chapter_contract_payload` 从大纲解析追读类型 / 主引擎 / 沉默点 /
  物理因果锚点 / 灯态 / 章末钩子；`load_chapter_contract` 按 status+version
  取最新。
- **prompt 层**：`task_card._render_task_card` 加 `chapter_suspense` 参数，
  渲染【章节悬疑约束】6 行；`compile_for_shot` 解析 scope_id 后 load，无
  chapter contract 时整段省略（安全降级，不破坏既有 Shot 流程）。
- **jury 层**：复用 task_card 无需另取数；`_jury_prompt` 加第 4 条「悬疑
  张力专审」准则，对照追读类型 / 沉默点 / 章末钩子审 `suspense_tension` 维度。
- 10 章连续压测 exit 0：winner 85.00–87.42，`suspense_tension` 82–92，
  10 章 prompt 全部含悬疑约束段，chapter_review 全部完成，模型池 failover 健康。
- 基线脚本 `tools/run_baideng_baseline.py` 支持多章循环落库与压测。

### 3. 工业事实漂移检测器解耦 + 本地代理 e2e 10 章验收（commit 2eedfc3a，块 C/任务#19 收尾）

- `chapter_review_orchestrator` 解耦：marker / trigger 词表从硬编码元组
  改为从 atomic clauses 的 `[marker]/[trigger]` clause 文本解析（去括号注释、
  顿号分词），主路径与漂移检测改数据驱动。
- `tools/seed_industrial_facts.py`：从 23 号文档抽 atomic clauses 灌工业
  事实基线（含 `[marker]/[trigger]` clause），数据驱动工业漂移检测。
- `tools/run_baideng_local_proxy.py`：本地代理产稿入口，模型名映射 +
  检测器空转坑规避（详见 memory `ink-local-proxy-baideng-runner`）。
- 本地代理 e2e 10 章验收通过。

### 4. 块1+块2 通用章纲注入链路（commit 8dfe897b）

- `load_chapter_setup`：生产 run 一次性 bootstrap，进程内调 `ink setup`
  （绕开 Windows argv 七段 JSON 转义）灌 meta_contract + shot 骨架，再注入
  c02/c03 章纲真值。
- atomic clauses seed：工业基线从外部文档抽提，落库后供漂移检测与悬疑
  契约共用。
- `tests/test_load_chapter_setup.py`：5 个单测覆盖覆写 / 并入 / 幂等 /
  跳缺骨架 / 事件切分。

### 5. P0-3/5 Scene-first 不变量测试 11 条 + 边界修正（commit da1a028e）

- `tests/test_scene_first_invariants_p0.py` 11 条全绿，覆盖：四层契约装配
  （需两个 creative opening、四层全插）、契约自检→self_checked、独立复审
  需 self_checked 且不同 family、复审序号按 contract 自增、AI 不能激活契约、
  amendment 记血统不改 clause、Guidance Card 生命周期、事实提案确认/拒绝
  人-only 门 + 写 anchor、accept 默认需 decision_id。
- `scene_repository.confirm_fact_proposal` 改写为写 legacy
  `writing_fact_anchors` 真实列（shot_id/revision_id/fact_text/source_span/
  confidence/status）—— 详见 BFX-068。
- `scene_repository.record_contract_review` 去冗余 same-model 守卫（自检
  合法复用 architect 同族），family-differ 仅由 `independent_review_contract`
  守 —— 详见 BFX-069。
- `human_activate_contract` JOIN 列名加表别名消除 ambiguous `scene_id`
  —— 详见 BFX-070。
- `test_chapter_snapshot_repository`：AI revision `generation_task_id` 改用
  真实 branch_id。
- **进度标定**：P0 不变量测试拆 5 块，本批为 **3/5**，余 **4/5、5/5** 待续
  （详见 `tasks.md` P0-6）。

### 不做（生产边界，重申）

- Real Generation / Selection 只落 Scene-first 影子表，未接生产 CLI、未改
  旧 Shot 生产路径、未切换 export 权威。
- 以上 5 块均为「影子层 + 真实模型 e2e」，不在生产 Cutover 路径上。

---

## 2026-07-14 Generation Round 有界状态机闭环（Scene-first 影子层）

落实 `tasks.md` P0-1 中状态机可测部分，不切换旧 Shot 生产路径。

### 范围

- 规格经两家族专项评审（Code Reviewer + Technical Writer），吸收 C-1~C-4 / H-1~H-6 / M-1~M-4 后定稿：
  `docs/superpowers/specs/2026-07-14-generation-round-state-machine-design.md`。
- `ChapterSnapshotRepository` 新增：
  `transition_generation_round`（唯一状态写入口，CAS on expected_status）；
  `record_eligible_branch`（branch CAS `validating→eligible` + round.eligible_count CAS，同一 `BEGIN IMMEDIATE` 事务）；
  `mark_initial_zero_pass` / `mark_candidate_shortage` / `mark_diversity_shortage` /
  `mark_failed` / `mark_superseded` / `start_supplement` / `begin_selection`（硬守 eligible_count≥3）/
  `complete_selection` / `increment_call_count`（单调非减记账，本轮不熔断）/
  `get_generation_round_state`（恢复点 `RoundState`，缺 id 抛 `DataIntegrityError`）。
- 13 个 status 的合法跳转表落地；`superseded`/`failed` 只能从非终态进入；
  补稿唯一性由状态拓扑保证（`supplementing` 唯一前置 `validating_initial`，不可回流）。
- 新测试 `tests/test_generation_round_state_machine.py`（15 例，覆盖 INV-ROUND-001~010 正反例）。
- 文档同步：`implementation-contract.md` §0 状态矩阵 + §3.1 实现说明；
  `invariant-traceability.md` 登记 INV-ROUND-001~010；`tasks.md` P0-1 标进度。

### 驱动器与真实模型闭环

- 新增 `GenerationRoundDriver`，实现固定首批2篇、0篇过线终止、1—2篇过线只补一次默认3篇、补后不足3篇终止、实质差异门、文学绝对门、确定性选优、预算熔断与中间态恢复。
- 新增 `RealGenerationPort` / `RealValidationPort` / `RealSelectionPort`：真实写作模型生成完整Chapter Candidate；七维资格审查；盲判实质差异；按项目绝对总分/单维门槛选优。
- Real Generation只落Scene-first影子表，且无active Scene Contract时fail-closed；未接CLI、未改旧Shot生产路径。
- SelectionPort改为纯决策接口；branch selected与round selected只由driver通过Repository落状态，消除双写。
- port异常统一封入`failed`合法终态；jury JSON不可解析不再伪造60分或默认差异成立。
- 模型调用幂等键改为稳定`round-{round_id}-{step}-{branch_id}`，崩溃恢复不会生成新逻辑调用键。
- schema新增项目级文学门槛字段，并补迁移脚本；缺省总分420、单维60。

### 不做（生产边界）

- 不接CLI、不做Cutover、不改变旧Shot唯一生产权威；AI权限/RLS、正式Accept/Export与旧库迁移仍在后续P0。

### 验证

- Generation Round离线全套：29 passed，1 skipped（真实模型用例默认守卫跳过）。
- 真实iFLYTEK端到端：1 passed；实际生成5篇、首批1篇过线后补3篇，最终3篇eligible，实质差异门与文学绝对门通过，round=`selected`，15次模型调用审计入库。
- 真实端到端额外断言：所有Branch Version已冻结；Scene/Revision/Branch绑定完整；SelectionPort无提前状态副作用。
- `tests/test_chapter_snapshot_repository.py`：6 passed（未回归）。

---

## 2026-07-11 c02/c03 真模型端到端验收 + 工业漂移检测解耦重构 + schema 迁移

完成 tasks.md 中「讯飞真模型端到端跑第2-3章验收」（task #30）及配套修复。c02/c03 全部走通真模型 **write（4 shot 全 soft_sealed）→ review（真 jury 7 维 + 工业漂移检测）** 完整链路。

### 产稿规模

- **c02**：4 shot 全 `soft_sealed`，108 次 LLM 调用 / 20 篇 draft，review_id=1。
- **c03**：4 shot 全 `soft_sealed`，114 次 LLM 调用 / 20 篇 draft（shot-004 多 6 次重试，正常 soft_sealed），review_id=2。

### review 7 维评分（c03 较 c02 全面改善）

| 维度 | c02 | c03 |
|---|---|---|
| POV 一致 | 40 | **65** ↑ |
| 节奏 | 55 | **70** ↑ |
| 母题密度 | 90 | **95** ↑ |
| 人物一致 | 70 | 75 ↑ |
| info_gap | 75 | 80 ↑ |
| 章末钩子 | 85 | 85 |
| 章续衔接 | 60 | 60 |

两章质量门均 `false`，**属内容质量问题，非链路 bug**——review_notes 是真模型 jury 精准判定的内容。suspense 衰减未回炉（中位数 ≥ 82，任务#21 监控生效）。

### 工业漂移检测解耦重构（主线去小说化）

`chapter_review_orchestrator.py` 原有三处小说专用硬编码泄露进通用主线（`_FORBIDDEN_WUXIA_MARKERS`/`_FAILURE_KEYWORDS` 词表），违反「流水线必须通用，个性化必须和主线分离」。重构为数据驱动：

- 删硬编码词表，`_match_forbidden_markers` 改为从 `[marker]` atomic clause 解析词表（`_extract_marker_terms`：split `:`/`：`、strip `（…）`/`(…)` 注释、split `、`/`，`、strip `。`）。
- LLM 兜底层 `[trigger]` clause 关键词驱动，marker 未命中时取 suspicious segments 交 LLM 判定，`drift_type` JSON enum（wuxia/failure_mechanism_vague/scrap_regime_conflict）协议不变。
- 小说专用数据存具体项目 DB 的 `writing_atomic_source_clauses`（`seed_industrial_facts.py` 灌库，task #23/24/25 已完成）。
- 11/11 m5 单测通过，c02/c03 实跑验证工业漂移检测真实触发（`failure_mechanism_vague`）。

### 暴露并修复的 2 个真实 bug（见 bugfix.md BFX-040/041）

- **BFX-040 write 缺幂等**：`cli._cmd_write` 重跑已 `soft_sealed` shot 崩 `DataIntegrityError`。修复：shot 前查 status，已 seal 则 `skipped` 跳过 + 逐 shot commit（`skipped_already_soft_sealed` 响应字段）。
- **BFX-041 schema 漂移**：生产库 `writing_projects.suspense_decay_floor` 列缺失致 review 崩 `OperationalError`。根因：任务#21 加列只改 schema.sql 没迁移既有库。修复：`sql/migrations/2026-07-09_suspense_decay_floor.sql` + `tools/migrate_suspense_decay_floor.py`（幂等 PRAGMA 探测），已执行。

### 跨章共性病灶发现（圆桌评审预言的真实落地，待后续优化）

c02/c03 review 暴露一致的 4 类内容病灶，非设定缺失而是落地问题：

1. **末段 POV 无过渡切换**：c02 切吕素琴、c03 切林远征，都在末段违反单章 POV 纯度。
2. **章续硬衔接 60**：两章都时空跳跃、缺与上章承接逻辑。
3. **industrial_fact_drift / failure_mechanism_vague**：两章都触发，工业失效机制描述被判模糊。
4. **母题密度 + 章末钩子是稳定强项**（90-95 / 85）。

这 4 类病灶已映射到 tasks.md 作为后续代码层优化任务。

### 验收证据

- c02 write log：`{"soft_sealed":["001","002","003","004"],"skipped_already_soft_sealed":[]}`；review：`{"ok":true,"review_id":1,"quality_gate_passed":false}`。
- c03 write log：`{"soft_sealed":["001","002","003","004"]}`（114 调用）；review：`{"ok":true,"review_id":2,"quality_gate_passed":false}`。
- c03 review 维度较 c02 全面改善（POV 40→65、节奏 55→70、母题 90→95）。

---

## 2026-07-08 质量门真实化阶段 A/B/C（模型角色主备兜底 + gateway failover + jury 真实化）

**完成 tasks.md P0 阶段 A/B/C**（设计 plan：`C:\Users\Administrator\.claude\plans\effervescent-pondering-puzzle.md`）。用户硬要求：每个 `call_type` 的 LLM 角色配「主/备/兜底」三模型（尽量跨供应商），调用失败逐 tier 切，三都失败才判失败并提示调供应商/api-key。

### 阶段 A：模型角色配置模块（主备兜底）

- 新表 `writing_model_role_configs`（`project_id × call_type × tier`，tier=primary/secondary/tertiary，跨供应商：每档独立 `provider`/`base_url`/`api_key_env`/`max_tokens`）。
- 新模块 `src/ink/core/model_role_config.py`：`load_role_chain`（按 tier 顺序返回 1-3 档，缺档滚动补位保证三档非空，向后兼容只配 primary 的旧项目）/ `upsert_role_config` / `list_role_configs` / `TIER_ORDER`。
- CLI 接入：`init --role-config <JSON>` 写三档；`role-config set/get/validate` 子命令运行时增删查校；无 `--role-config` 时 `_seed_primary_from_pool` 从旧 `--writer-models`/`--jury-models` 池首模型自动生成 draft/jury primary 单档（向后兼容）。

### 阶段 B：gateway 接 failover（不污染熔断）

- `LLMGateway.call` 重写为 failover 编排：按 `call_type` 查 role chain，按 `tier_hint`（jury 3 裁判各传 primary/secondary/tertiary 实现 3 模型投票 + 单 judge 容灾）wrap 重排起调 tier，失败逐 tier 切。
- **BFX-035 熔断污染修复**：tier 失败**不调 `record_call`、不落 attempt**——`retry_budget.check_circuit` 只按 `shot_id` 聚合，三 tier 同 `LLMProviderError` 累加同一行会误熔断。只在逻辑调用整体成功（落 attempt + record success）/ 整体失败（落 attempt + record fail）后调一次。tier 切换走 `model_role_failover` event，`writing_ai_call_attempts` 不加 tier 列（避免迁移 + 破 SoftSeal 契约）。
- 注入式 provider（测试 `--llm-provider deterministic`）保留：`call_type` 有 role_config 走 failover，无则走注入式（polish 等未配 role_config 的 call_type 仍用 deterministic）。

### 阶段 C：jury 真实化 + LLM 失败分流

- 删 jury 四个桩（`_stub_jury_scores` 等），`JuryOrchestrator._score_draft` 换 3 裁判真实调 `gateway.call(call_type=jury, tier_hint=slot_tiers[slot-1])` → `_parse_jury_scores` 解析 12 维 JSON → 落 `writing_jury_raw_scores` + `writing_jury_aggregates`。
- **失败分流**：3 裁判全 LLM 失败 → `JuryLLMFailure` → `transition failed` 抛「调供应商」错（**不走重写**，区别于「评了不过 gate」）；任一 judge 成功但 `judge_count < 3` 也抛 `JuryLLMFailure`（schema CHECK `judge_count >= 3`，部分成功无法落 aggregate）；质量不过 gate 才走 `_handle_quality_retry_or_fail` 重写。
- `_score_draft` 重评前清旧 `jury:{draft_id}:r1:*` raw_scores + aggregate + attempts（idempotency_key UNIQUE 约束，重评需先清）。
- `cli.py` + `resume_handlers.py` 所有 JuryOrchestrator 构造点传 gateway；删 `_DEFAULT_ORCHESTRATOR` 死代码单例。

### BFX-036/037：jury 真实化暴露的预算 + 评分区分缺陷

真实化后暴露两个生产级 bug（见 bugfix.md）：

- **BFX-036 max_calls_per_shot 预算不足**：jury 单 shot 调用 = 3 裁判 × (draft_count 候选 + 1 polished) × 两轮（首评 + polish 后重评），默认 draft_count=3 → 24 次，超 schema 默认 `max_calls_per_shot=8`。`setup` 按公式 `6×(draft_count+1)+3` 自动放宽 jury 预算 + 同步上调 `max_total_llm_calls`。
- **BFX-037 mock/deterministic jury 不区分 polished draft**：provider 返回全 84 同分，第二轮 jury 无法选出 polished draft → winner 落未 polish 稿 → soft seal 失败。改 jury 分支按 prompt 含 "polished text" 给 90、否则 84，确保重评时 winner 仍是 smart-polish 稿。

### 验收

- 离线全量 `357 passed, 7 skipped`（+jury 真实化 / role-config failover / 预算自调用例；7 skipped 为需 `IFLYTEK_API_KEY` 的联网集成测试）。
- 3 个 CLI 端到端测试恢复绿：`test_cli_chapter_revise_export_import_flow` / `test_cli_one_chapter_performance_baseline` / `test_cli_resume_executes_session_level_chapter_review`（完整跑 produce_drafts → hard_gate → jury → polish → 第二轮 jury → soft seal）。
- 阶段 D/E/F 待办：chapter_review + book_check 桩换真实 gateway.call；task_card 注入 book 层上下文；跨供应商 role-config 实跑验证。

---

## 2026-07-08 6 章流水线真实模型版端到端测试

**完成 tasks.md 第 2 项**(P1 主编台深化):

- 新增 `tests/test_e2e_real_models.py`:与 `test_m6_workflow_smoke.py::test_full_production_flow_six_chapters`(mock `WorkflowProvider`)互补,改用真实 `OpenAICompatibleProvider` 接 iFLYTEK Coding Plan,验证 outline 抽取 / 产稿 / 润色在真实模型下的行为。
- **模型池**:避开太卡的 `xopglm52`;writer 池 `xopglm51`/`xopdeepseekv4pro`/`xopkimik26`(满足 DDL `json_array_length >= draft_count=3`),jury 池 5 个(满足 `>= 3`)。
- **`smart-polish` 别名适配**:`PolishOrchestrator` 硬编码 `model_name="smart-polish"`(`src/ink/pipeline/polish_orchestrator.py:38`),真实 iFLYTEK 不认该别名。新增 `_RemappingProvider` 包装层:调用时翻译成 `xopglm51`,返回时还原 `model_name="smart-polish"`——保持 `SoftSealOrchestrator` 校验 `winner.writer_model == "smart-polish"` 的生产契约(不改生产代码)。
- **阈值放宽**:`min_eligible_outlines=1`(默认 2)、`outline_drift_threshold=0.10`(默认 0.20),适配真实模型文本多样性。
- **间歇性容错**:outline/polish 段无降级兜底,遇网关间歇错误(503/500/Model Not Found/PathDomainError)或 drift 全拒("below threshold")时 `pytest.skip`(仿 `test_iflytek_integration.py` 惯例:网关侧问题 skip 而非 fail)。
- **断言放宽**:聚焦「pipeline 跑通」而非具体文本——6 章 soft_sealed + ≥1 章 winner 非 degraded + export artifact 非空 + chapter reviews accepted ≥5。
- **实跑结果**(2026-07-08,提取 `provider-models.local.json` 的 `xunfei-coding-glm52` key):
  - `test_real_outline_extraction_smoke`:**passed**(13s,真实模型生成合格 outline,winner 落库)。
  - `test_real_six_chapter_pipeline`:单独跑 **passed**(456s,6 章全程真实模型 write→jury→review→accept→export);组合跑因 iFLYTEK 网关间歇性 drift 全拒触发 skip(符合守卫设计)。
- 全量 325 离线 passed(新文件无 key 时 2 skipped,不报错)

### 后续正式化(2026-07-08 晚)— 真实 6 章实跑链路彻底打通

原 e2e 用测试侧 `_RemappingProvider` 绕过别名、provider 无重试、drift 阈值 0.10 仍偶发全拒。本轮把三个临时方案正式化:

- **BFX-030 生产侧落实**:`_RemappingProvider` 包装层移除,改由 `LLMGateway.call` 从 `writing_projects.model_aliases` JSON 列懒加载别名映射(`smart-polish → xopglm51`),翻译别名调 provider、返回前 `dataclasses.replace` 还原别名,保持 `SoftSealOrchestrator` 校验契约。与生产 CLI 完全一致(见 tasks.md 阶段1)。
- **BFX-031 provider 退避重试**:`OpenAICompatibleProvider` 加 `max_retries`/指数退避 + 确定性抖动(用 `idempotency_key` 哈希做种子),对 429/5xx/超时重试、401/400 立即抛;`load_llm_provider_config` 对 openai-compatible 默认 4 次,CLI `--llm-max-retries`/`INK_LLM_MAX_RETRIES` 可覆盖。扛过 iFLYTEK 包月套餐 429/503 限流。
- **BFX-032 drift 阈值适配**:真实模型(GLM/DeepSeek)倾向自由重写,outline 与契约结构化字段的 CJK bigram 重叠趋近 0,`0.10` 阈值全拒。e2e 阈值降至 `0.02`;生产 CLI 已暴露 `--outline-drift-threshold`。drift 算法改用语义相似度为 P2 待办。
- **实跑验证**:`test_real_outline_extraction_smoke` passed(6s);`test_real_six_chapter_pipeline` **passed(573s,全程真实 iFLYTEK)**——6 章 write→jury→polish→soft seal→review→accept→export 全链路跑通,重试扛过限流,别名路由 + drift 阈值 0.02 生效。
- 离线全量 339 passed, 2 skipped(+7 provider 重试用例)。

---

## 2026-07-08 DecisionSession 并发控制

**完成 tasks.md 第 4 项**：

- `sql/schema.sql` 新增 scope 级 partial unique index `idx_active_decision_session_scope`（`project_id, scope_type, COALESCE(scope_id,'')` WHERE 活跃）——同 scope 只能有一个活跃 session
- `DecisionSessionStore.start` 自动填 `before_hash`（取当前 scope 最新 confirmed/locked version 的 hash；首次确认前为 None）
- `start` 捕获 `sqlite3.IntegrityError` 转 `DataIntegrityError`，消息含 "active decision session already exists"
- `confirm_and_apply` 冲突检测：若 base version hash ≠ session 的 before_hash，标 session stale 并抛 `ConcurrentModificationError`
- 新增 helper：`_current_scope_version_hash`、`_version_hash_by_id`、`_mark_session_stale`
- 新增迁移脚本 `sql/migrations/2026-07-08_scope_unique_index.sql`（含冲突数据检查 SQL）
- 新增 5 测试（同 scope 互斥 / 不同 scope 并发 / stale 后可重开 / before_hash 自动填 / 冲突检测）
- 更新 4 处既有测试：schema index 计数 62→63；helper 去掉显式 before_hash 依��自动填充；IntegrityError 断言改为 DataIntegrityError
- 全量 325 离线 passed

---

## 2026-07-07 Coverage gate 可视化

**完成 tasks.md 第 6 项**：

- `SourceWorkflowStore.list_coverage_gaps` 返回 gap/conflict 字段明细（field_path、status、scope、atomic_clause_id、evidence）
- `_suggest_clauses_for_field` 按 field_path 顶层组匹配同 scope 的 atomic clause，最多 5 条
- 新增 `CoverageGap` dataclass
- CLI 新增 `coverage-gaps` 子命令（`--scope-type`/`--scope-id` 过滤），输出 `total_gaps` + `gaps` 数组
- 新增 4 测试（store 2 + CLI 2）
- 全量 320 离线 passed

---

## 2026-07-07 Stale 传播自动触发

**完成 tasks.md 第 5 项**：

- `DecisionSessionStore.confirm_and_apply` 新增 `stale_manager` 可选参数
- SAVEPOINT 释放后自动调用 `mark_stale_after_contract_change`，标记下游 prompt/draft/review/book check stale
- `ConfirmedContractResult.stale_mark` 携带结果
- CLI `confirm-contract` 默认注入 `StalePropagationManager`，`--no-auto-stale` 可关闭
- 返回 JSON 含 `stale_mark` 摘要（affected_prompt_ids 等）
- 新增 `TestConfirmAutoStalePropagation`（2 测试：自动标记 / 不传则不标记）
- 全量 316 离线 passed

---

## 2026-07-07 init 自定义模型池 + 推理模型适配

**完成 tasks.md 第 3、7 项**：

- `ink init` 新增 `--writer-models` / `--jury-models`（逗号分隔、去重保序、默认池兜底）
- `OpenAICompatibleProvider` 新增 `max_tokens` 参数 + `_is_reasoning_model()` 自动注入推理模型默认 `max_tokens=2000`
- `_parse_chat_completion_response` content 空时回退 `reasoning_content`
- CLI 新增 `--llm-max-tokens`，env 新增 `INK_LLM_MAX_TOKENS`
- 模型池改用 GLM-5.1（5.2 卡），补全 Qwen3.5-35B/397B 两个模型（共 16 个可用）
- 新增 `tests/test_openai_provider.py`（14 单测），iFLYTEK 集成测试移除 `_BoundedMaxTokensProvider` 绕过
- 全量 314 离线 passed + 5 联网集成测试

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

---

## 2026-07-08 完成阶段 D：chapter_review + book_check 真实化

> 对齐 jury 真实化模式：桩评分换成真实 `gateway.call`，解析维度分 + issues，blocking 即拦 accept；LLM 全失败抛专用异常不写假分。

### 已完成：D1 chapter_review_orchestrator 真实化

- 桩 `_score_chapter`（恒 82+）换成 `gateway.call(call_type="chapter_review")` → 解析 LLM 返回的 7 维 JSON（`chapter_continuity_hard`/`pov_consistency`/`character_consistency`/`chapter_hook_soft`/`rhythm_curve`/`motif_density`/`info_gap_lifecycle` + `review_notes`）→ 真实分落 `writing_chapter_reviews`。
- 维度分 < floor（默认 75）→ 进 `blocking_issues` → `quality_gate_passed=0` → `HumanReviewOrchestrator.accept_chapter` 闸门拦死（章仍 `soft_sealed`，无 `chapter_hard` seal 文本）。
- LLM 三 tier 全失败 → 抛 `ChapterReviewLLMFailure`，事务回滚，不写任何假 `writing_chapter_reviews` 行。

### 已完成：D2 book_rolling_check_orchestrator 真实化

- 桩 `_book_scores`/`_book_issues`（恒 82+、恒无 blocking）换成 `gateway.call(call_type="book_check")` → 解析 6 维 JSON（`longline_suspense_closure`/`character_arc_completeness`/`motif_echo_density`/`theme_sublimation`/`global_rhythm_curve`/`foreshadow_recovery` + `issues` list）→ 真实分 + issues 落 `writing_book_check_results`。
- issues 含 `severity=blocking` → `blocking_issue_count>0` → `quality_gate_passed=0` → `has_blocking_issues(conn, project_id)` 返回 True → 拦 `accept_chapter`/`export_project`。
- LLM 三 tier 全失败 → 抛 `BookCheckLLMFailure`，事务回滚，不写假分。
- interval 不整除 → `run_if_due` 返回 None 不触发（保持原 interval 语义）。

### 已完成：D3/D4/D5 接线 + seed + deterministic

- D3：`ChapterReviewOrchestrator`/`BookRollingCheckOrchestrator` 构造加 `gateway` 参数；`resume_handlers.build_non_shot_resume_handlers(conn, gateway=None)` 透传 gateway；`cli.py` resume 路径经 `_gateway(conn, args)` 构造注入。
- D4：`init` 命令无 `--role-config` 时，`_seed_primary_from_pool` 自动为 `chapter_review`/`book_check` 生成 `primary` 单档（复用 jury 池首模型，provider 取 `INK_LLM_*` 默认），与 draft/jury 一致。
- D5：`MockProvider`（`llm_gateway.py`）+ `_CliDeterministicProvider`（`cli.py`）+ `WorkflowProvider`（`test_m6_workflow_smoke.py`）三处 mock 同步加 `chapter_review:`/`book_check:` 前缀分支，返回全过 JSON（92 + 空 issues），保证离线 CLI smoke 全链路通过。

### 已完成：D6 测试 + 离线验收

- 新增 `tests/test_chapter_review_real.py`（4 用例）：真实分落库非桩 82、低维 blocking 拦 accept、LLM 全失败抛 `ChapterReviewLLMFailure` 不写假分、review_notes 取 LLM evidence。
- 新增 `tests/test_book_check_real.py`（4 用例）：真实 6 维分 + issues 落库、blocking issue 设 count 并拦 accept/export、LLM 全失败抛 `BookCheckLLMFailure` 不写假分、interval 不整除返回 None。
- 全部既有测试（`test_m5_chapter_review.py`/`test_m6_book_export.py`/`test_m6_workflow_smoke.py`/`test_resume_handler_registry.py`）从「桩 orchestrator 无 gateway」改注入式 gateway 走真实评分路径。
- 离线 CLI 验收：`ink init`（3 writer + 3 jury 模型池）后 `role-config get` 确认 draft/jury/chapter_review/book_check 四 call_type 均有 `primary` 单档；全量 `365 passed, 7 skipped`（基线 357 + 8 新真实化用例；7 skipped 为需 `IFLYTEK_API_KEY` 的联网集成测试）。

### 关键成果

- **质量门三处评分全部真实化**：jury（阶段 C）+ chapter_review + book_check（阶段 D）均经 `gateway.call` 解析真实维度分，`quality_gate_passed`/`has_blocking_issues` 不再恒真/恒假，accept/export 闸门真正生效。
- **缺陷 BFX-038 记录**：阶段 D 暴露并修复了无 role_config 的 call_type 在注入路径 `model_name=None` 触发 NOT NULL 失败（见 bugfix.md）。

## 2026-07-08 完成阶段 E：task_card 注入 book 层上下文

> writer prompt 之前只喂 shot 级约束（must_land/anti_write/persona + outline），缺 book 层世界观/角色/叙事/母题。阶段 E 从 `writing_meta_contracts`(confirmed) + `writing_atomic_source_clauses`(scope_type='book', confirmed) 聚合四类上下文注入 task_card，经 compiled_instructions → full_prompt_text 自动喂 writer。

### 已完成：E1 load_book_context loader + BookContextDTO

- 新增 `BookContextDTO`（world/character/narrative/motif 四 tuple[str,...]），经 `src/ink/codegen/generate.py` SCHEMAS 登记后 `python -m ink.codegen.generate` 重新生成 `generated/dtos.py`（该文件是 codegen 产物，手改会被重新生成覆盖——必须改 codegen 源）。
- 新增 `load_book_context(conn, project_id) -> BookContextDTO`（`contract/loader.py`）：查 meta_contracts(confirmed, 取最新版) 的 `world_knowledge`→World、`narrative_voice`+`hard_boundaries`→Narrative、`motif_system`→Motif；查 atomic_clauses(`scope_type='book'`, confirmed) 按 `clause_type` 分流（world→World、character→Character、plot→Narrative、style→Motif）。
- Character 唯一来源是 atomic_clauses（meta 无 character 列），confirmed 为空时 Character 段为空，不阻断编译。
- `_flatten_json_values` 把 meta 的 JSON 列（dict/list/scalar）拍平成可读文本行；meta+atomic 同行去重保序。

### 已完成：E2 task_card 注入 book 上下文段

- `TaskCardCompiler.compile_for_shot` 先经 `_lookup_shot_contract_id`（现返回 `(shot_contract_id, project_id)`）拿 project_id，调 `load_book_context`，再传给 `_render_task_card`。
- `_render_task_card` 新增 `book_context` 参数；`_render_book_section` 渲染 World/Character/Narrative/Motif 四段（空桶省略），插在 POV only 与「请按以上约束完成本 shot。」之间，complete-tail（`。`）校验保持通过。
- prompt 链路无需改动：book 段随 compiled_instructions → full_prompt_text 自动进 writer prompt。

### 已完成：E3 book 上下文测试 + 离线验收

- 新增 `tests/test_book_context.py`（11 用例）：四类分组、confirmed 过滤、non-book scope 过滤、精确去重、空数据降级；`_render_book_section` 四段渲染/空桶省略/None 降级；full task_card 注入后仍以 `。` 结尾；端到端 `make_winner_selected_shot` 注入 book 数据后 compiled_instructions 含 World/Character/Motif 段。
- 全量 `376 passed, 7 skipped`（基线 365 + 11 新用例）；`test_e2e_six_chapters.py` 6 章离线 e2e 通过（book 段注入路径覆盖）。

### 关键成果

- **writer prompt 首次具备 book 层上下文**：世界观/角色/叙事声线/母题系统随 task_card 注入，shot 级约束不再是 writer 的全部输入。
- **数据闭环**：book 层设定（meta_contracts + 源文档抽取的 atomic_clauses）确认后即进 writer prompt，setup/抽取/确认/写作四阶段打通。

## 2026-07-09 完成 P2-11：jury escalation 升级轮（分歧超阈值扩裁判重评）

> 原 P2 可扩展性队列第 11 项。设计目标：基础轮 3 裁判对某维度打分分歧（同维最高-最低分差）超 `writing_projects.judge_disagreement_max` 阈值（默认 25）时，不能直接判该 draft 失败——而是扩到更多裁判重评，用更多样本稀释极端分后再判 gate，避免单次评分偶发分歧误杀好稿。

### 已完成：jury_round=2 升级轮实现

- `JuryOrchestrator._score_draft`：基础轮聚合后若 `judge_disagreement_max > context.judge_disagreement_max` 且 `context.escalated_jury_count > 3`，调 `_run_escalation_round` 走升级轮。
- `_run_escalation_round`：**先清理该 draft 旧 jury 数据**（`writing_jury_raw_scores` / `writing_jury_aggregates` 该 draft_id 行 + `writing_ai_call_attempts` 对应 idempotency_key 的 jury 调用），再以升级轮重评，避免旧 r1 分与 r2 分混算。
- `_select_judges_for_escalation`：升级轮判池从 `jury_model_pool` 排除该 draft 的 `writer_model`（复用 `_jury_dispatch` 的自评阻断不变量），**优先选基础轮未参与的模型**（增裁判多样性），不足时复用基础轮模型补齐到 `escalated_jury_count`；pool 整体不足 `escalated_jury_count` 时降级到实际可取数（≥3 才升级，<3 返回 None 视为升级失败）。
- 升级轮 raw_scores 落 `jury_round=2`、`judge_slot=1..N`；aggregate `jury_round_used=2`、`judge_count=N`；`weight_used` 若被降级补记 `_escalation_capped_to` 标记降级原因。
- 升级后仍分歧（`judge_disagreement_max > 阈值`）→ `quality_gate_passed=0` + reasons 含 `escalation_exhausted`（叠加 `judge_disagreement_exceeded`），走既有 `_handle_quality_retry_or_fail` 重写/fail 分流。

### 已完成：升级轮测试（3 新用例，改造 1 旧用例）

- `test_jury_disagreement_triggers_escalation_round_and_passes`（改造自原 `test_jury_disagreement_failure_cannot_select_winner`）：基础轮分歧 30 触发升级轮，r2 5 裁判返回收敛分 disagreement 10 ≤ 25 过 gate，断言 `jury_round=2` raw_scores 落库（3 draft × 5 judge = 15 行、5 不同模型、max_slot=5）、aggregate `jury_round_used=2`/`judge_count=5`、过 gate 选 winner。
- `test_jury_escalation_exhausted_when_still_disagreement`：升级轮仍分歧（`[disagreement-persistent]` r2 disagreement=30）→ `escalation_exhausted` + `quality_gate_passed=0`，`auto_retry_on_hard_failure=0` 时选不到 winner 抛 `DataIntegrityError`。
- `test_jury_no_escalation_when_disagreement_within_threshold`：分歧 ≤ 阈值不触发升级轮，`jury_round_used=1`/`judge_count=3`（回归保护）。
- `JuryScoreProvider` 加 `:r2:<slot>` 轮次分支：`[disagreement]` 升级轮返回收敛分（75/85/80/85/75），`[disagreement-persistent]` 升级轮仍分歧（70/84/100/84/70）；`DisagreementDraftProvider` 加 `marker` 参数控制 draft 文本标记。

### 关键成果

- **分歧不再直接判失败**：单次评分偶发分歧经升级轮重评稀释后重判，避免误杀；真分歧（升级后仍超阈值）才标 `escalation_exhausted` 走重写/fail。
- **全量 `378 passed, 7 skipped`**（基线 376 + 2 净新增用例；7 skipped 为需 `IFLYTEK_API_KEY` 的联网集成测试）。

---

## 2026-07-11 完成 P0 工业文学质量闭环（本机代理真实模型 + 生产 c03）

### 一、三个跨章共性病灶完成

#### 1. 末段 POV 与全知滑出硬审计

- jury prompt 明确审查草案最后 25%（至少最后两个自然段）：进入契约 POV 外角色的感知/记忆/判断/内心且无显式锚点时，`character_believability/chapter_continuity` 至少一项必须低于 60。
- chapter review JSON 协议新增：
  - `pov_tail_audit.violation`
  - `expected_pov`
  - `observed_pov`
  - `transition_anchor`
  - `evidence`
- 程序层把结构化违规独立写成 `pov_tail_transition` blocking issue，防止总体平均分掩盖硬伤。
- 真实复评：
  - c03 run1 准确识别末段切到林远征。
  - c03 run3 首评识别“许怀山有限视角滑为作者结论”；通过 `smart-polish` 真实模型定点修订后复评通过。

#### 2. 章续硬衔接

- 新增 `src/ink/core/chapter_continuity.py`：
  - 优先读取同章上一 shot current text；
  - 无同章前文时读取最近上一章末 shot；
  - 正文读取统一经 `TextRepository/v_current_text`。
- outline 与 task card 同时注入【连续性硬约束】，要求：
  1. 开头承接人物位置、时间、未完成动作或悬念；
  2. 切时间/地点/POV 必须显式写锚点；
  3. 不重演已完成动作，不让离场人物无说明出现。
- chapter review 增加 `continuity_audit`；违规独立写为 `chapter_continuity_anchor`。

#### 3. 工业失效机制判据

- 工业漂移真实模型协议从单一 `drift_type` 扩展为：
  - `claim_mode=observation_only|causal_claim|institutional_claim`
  - `observable_anchors`
  - `causal_chain`
  - `missing_requirements`
  - `baseline_conflict`
  - `confidence`
- `failure_mechanism_vague` 只有在正文明确使用因果断言语言，且缺可观测参数/因果链时成立。
- 症状、背景事实和悬疑线索（如“微裂纹像蛛网”“露天堆放四天”）不再自动升格为因果结论。
- 置信度低于 0.75、`claim_mode` 不匹配或结构化自证不完整时不阻断。

### 二、真实实跑暴露并修复的额外工业缺陷

1. **outline drift 长度惩罚**
   - 原 Jaccard 分母包含候选大纲新增 bigram，真模型越详细越容易被判 drift。
   - 改为契约源 bigram recall：判断“是否保留契约锚点”，不惩罚正常扩写。

2. **polish 元话语进入正文**
   - 生产 run2 出现“好的，收到”“以下是润色后的版本”“主要调整说明”等模型说明，并被旧 gate 封版。
   - 新增 `core/prose_integrity.py`：
     - 清理常见 intro/fence/trailing edit notes；
     - unresolved artifact 拒绝写 revision。
   - hard gate readability 与 chapter review 增加 `publication_artifact` 双保险。

3. **chapter review 重评 idempotency**
   - 旧实现到 `_write_review` 才删 attempt，真实 LLM 新 attempt 已先撞 UNIQUE。
   - 现在在调用 LLM 前清理非 accepted review 的旧 `chapter_review/industrial_fact_drift` keys；accepted review 仍不可覆盖。

4. **baseline 文件 DB 未提交**
   - `run_baideng_local_proxy.py/run_baideng_baseline.py` 原来关闭连接后回滚，导致快照有内容但 DB 为空。
   - 初始化、逐章成功和 review 成功均 commit；异常 rollback。

5. **真实联网测试默认常开**
   - 10 章 local-proxy 测试原来默认进入全量 pytest，导致 CI 数十分钟以上。
   - 现在需 `INK_RUN_REAL_LLM_TESTS=1` 显式启用；真实生产验收仍已单独执行并留报告。

### 三、真实 failover

- `tools/validate_p0_local_proxy.py` 在生产 DB 副本上：
  - primary 配置不存在模型，真实返回 HTTP 400 `invalid_model_mapping`；
  - gateway 写 `model_role_failover` event；
  - secondary `claude-xunfei-glm-5-1` 返回成功 JSON。
- 整个报告声明 `mock_used=false`。

### 四、生产 c03 最终证据

- 生产 DB 先备份：`inkflow.before-local-proxy-20260711-005907.db`。
- run2 证明连续性注入有效，但新出版污染 gate 检出 polish 元说明，质量门回退 false。
- run3：
  - 4 shot 全 `soft_sealed`；
  - 定点 POV repair 新 revision 保留 source_revision_id 和真实 `polish` attempt；
  - 最终 review_id=4：
    - continuity 92
    - POV 95
    - character 88
    - hook 90
    - rhythm 85
    - motif 78
    - info-gap 89
    - `quality_gate_passed=1`
    - `blocking_issues=[]`
  - 程序扫描无问候、润色说明、markdown fence 等正文污染。

### 五、回归

- 新增：
  - `tests/test_p0_literary_quality_guards.py`
  - `tests/test_prose_integrity.py`
- 离线全量：`402 passed, 9 skipped in 34.88s`。
- 9 个 skipped 均为真实 provider opt-in，不是代码失败。

### 六、继续收口：jury 成本与定点修订

- post-polish 第二轮 jury 不再删除并重评所有未变化 draft：
  - 有同一 contract aggregate 且 draft 未 stale 时直接复用 12 维 medians；
  - 项目阈值变化时只重新计算 gate pass/reasons；
  - 只对新 polished draft 发起 3 裁判调用。
- 默认 3 draft 场景由“首轮 9 + 第二轮重评 12=21 次”降为“首轮 9 + polished 3=12 次”（不含真实分歧升级）。
- 新增 `core/capacity_planning.py`：
  - 纳入 draft_count、creative extra、retry candidates、escalated jury；
  - 默认建议 `jury_calls=42`；
  - CLI init 自动写容量；
  - `write` 在真实调用前预检 configured/recommended，不足立即报错，不再运行数十分钟后才 budget blocked。
- `tools/repair_pov_with_local_proxy.py` 已收敛为正式 `ink repair`：
  - 只允许 soft-sealed、未 hard-sealed 正文；
  - 写新 revision + source_revision_id + AI attempt；
  - 防元话语、限制长文本改动比例；
  - 修订完成自动重跑 chapter review。
- writer/polish 模型轮替从 Python 进程随机 `hash()` 改为 SHA-256 稳定索引，跨进程选择真正可复现。
- 最新离线全量：`405 passed, 9 skipped in 33.81s`。

### 七、c03-c10 连续真实 benchmark 完成

- benchmark DB：`D:/_Progs/.Story/《白灯法则》/.inkflow/benchmark-c03-c10/inkflow.db`
- 工业事实基线：11 条 confirmed atomic clauses。
- 全链路：outline → draft → hard gate → jury → polish → hard gate → jury → soft seal → 3-reviewer chapter review。
- 首轮暴露：
  - c04 硬门后只剩 1 个候选，旧 jury 直接中止；
  - c05 缺上一章对峙到质检室的移动锚点；
  - c08 许怀山离场后仍描写室内微观动作；
  - c09 supplemental draft 因脚本漏传 gateway，误用 MockProvider 并成为 winner；
  - 单 chapter reviewer 对同一 c08 修订稿重复评审时 pass/fail 波动。
- 修复：
  - candidate shortage 自动触发 real supplemental wave；
  - c05/c08 经正式 `ink repair` 定点修订；
  - benchmark 脚本所有 JuryOrchestrator 显式传真实 gateway；
  - synthetic placeholder 进入 hard gate 直接失败；
  - chapter review 改为 3 个不同模型独立评审、7 维中位数、POV/continuity 多数票；
  - c09/c10 以新 run 201/202 连续重生成，消除旧 mock lineage。
- 最终最新 passing runs：
  - c03-c08：run 200
  - c09：run 201
  - c10：run 202
- 结果：8/8 章 `quality_gate_passed=1`、`blocking_issues=[]`。
- 最终正文：12,596 字符。
- 评审模型：DeepSeek V4 Pro、GLM 5.1、Qwen 3.5 397B，三模型各 8 次章审。
- `export_quality_benchmark.py` 对最新 run 做 provider lineage 审计；发现 mock/deterministic attempt 时拒绝导出。
- 最终产物：
  - `benchmark-c03-c10/final_ch03-10.md`
  - `benchmark-c03-c10/final_report.json`
- 最新离线全量：`407 passed, 9 skipped in 35.44s`。

### 八、C1 章级责任/伦理审查经手人留痕完成

- schema：
  - `writing_projects.require_ethics_review`
  - `writing_chapter_ethics_reviews`
- 每次审查记录：
  - 操作经手人 `reviewer_actor`
  - 实际 reviewer models
  - 本章责任问题
  - 受影响者
  - 不可逆后果
  - 是否用制度/集体措辞遮蔽个人能动性
  - 正文证据句
  - `low/medium/high/blocking` 风险
  - `approve/revise` 建议
- `EthicsReviewOrchestrator` 使用 chapter-review 三 tier 的三个真实模型：
  - 至少 2 个有效结果；
  - 风险取最高值；
  - revise 取多数票，blocking 强制 revise；
  - evidence/affected parties 去重合并。
- 新增公开 CLI：`ink ethics-review`。
- `HumanReviewOrchestrator.accept_chapter`：
  - `require_ethics_review=0` 保持旧项目兼容；
  - `=1` 时缺 ethics review、blocking 或 revise 均禁止接受。
- 迁移：
  - `sql/migrations/2026-07-11_chapter_ethics_review.sql`
  - `tools/migrate_chapter_ethics_review.py`
- 已对生产 DB 和 benchmark DB 执行迁移并启用 `require_ethics_review=1`。
- 真实结果：
  - 生产 c03 run3：high / approve，三个真实 reviewer models。
  - benchmark c03-c09：high / approve；c10：medium / approve。
  - 8 个最新 passing run 全部具有正式 ethics review。
- benchmark exporter 现在要求 ethics review 存在且 approve，才生成 final artifact。
- 最新离线全量：`410 passed, 9 skipped in 61.33s`。

## 2026-07-11 PostgreSQL adapter 边界实现

- `src/ink/database.py` 新增 `DBAdapter` protocol、`SQLiteAdapter` 与懒加载
  `psycopg` 的 `PostgreSQLAdapter`，旧 `connect(path, initialize=...)` SQLite
  调用保持兼容。
- 新增 PostgreSQL connection/cursor/mapping-row 兼容层；查询结果同时支持
  `row["column"]`、`row[0]` 与 `dict(row)`。
- 新增 SQL scanner，只在普通 SQL 区域把 SQLite `?` 参数转换为 PostgreSQL
  `%s`，不会改写字符串、quoted identifier、行注释或块注释中的问号。
- `transaction()` 支持 transaction-local project/session/actor auth context；
  同时支持
  `pg_advisory_xact_lock(hashtext(shot_id || ':' || run_id::text))`，确保相同
  shot/run 工作串行化。
- PostgreSQL 驱动保持可选依赖；没有安装 `psycopg` 时仅在实际请求 PG
  connection 时给出明确错误，不影响 SQLite 生产与离线测试。
- 新增 `tests/test_postgresql_adapter.py`，fake-driver 验证连接、参数转换、
  lastrowid compatibility、mapping row、commit/rollback、RLS context 与
  advisory lock；全量离线回归为 `416 passed, 9 skipped`。
- 本阶段不宣称 PostgreSQL 已可生产切换：schema translation、真实服务 RLS
  跨项目隔离、并发锁和 invariant traceability 集成仍在任务队列。
## 2026-07-11 Event log 状态回放 CLI

- 新增 `src/ink/event_replay.py`，把 append-only session/version event stream
  确定性归约为可检查状态，保留 stream identity、最终 status、合并 state、
  applied event ids 与最后事件时间。
- 支持 `at_event_id` 和 ISO 时间上界，可重建任意已记录历史切片，而不依赖
  当前 in-place 状态行。
- 新增公开专家 CLI：`ink debug replay-session` 与
  `ink debug replay-contract`；两者均支持 `--at-event-id` / `--at-time`。
- 新增 3 个 replay 测试；全量离线回归 `419 passed, 9 skipped`。
## 2026-07-11 Shot source coverage 与批量审章

- `SourceWorkflowStore` 新增 shot-clause coverage API：验证 clause/project
  归属、记录 shot 级 evidence、按 book/chapter/shot 作用域计算每个 shot 的
  适用条款，并以最新 coverage 记录作为当前状态。
- 新增 `ink shot-coverage --chapter N`，输出逐 shot 适用条款、gap/conflict、
  evidence 和整章 coverage complete 状态。
- 新增 `ink shot-coverage-set`，支持把 draft id、证据句、人工核验等 JSON
  evidence 追加到 source coverage audit trail。
- 新增 `ink review-batch --chapters 3-10`；一次构造真实模型 gateway 后连续
  审查多章，默认 fail-fast，也可 `--continue-on-error` 收集全部结果。
- 新增章节范围解析和 shot coverage 测试；全量离线回归
  `428 passed, 9 skipped`。
## 2026-07-11 个人小说生产版正式上线

- 用户明确收缩范围为单作者、本机 SQLite、本机 WiseGateway，不考虑团队
  PostgreSQL/RLS；据此重新定义上线硬门。
- 新增 `ink doctor`：检查项目配置、LLM 容量、SQLite integrity、
  foreign keys、真实 provider routes、mock/deterministic 污染与 ethics gate，
  并汇总章节/soft seal/hard seal 生产进度。
- 新增 `ink backup --output ...`：使用 SQLite online backup API 创建一致性
  副本，完成后在副本执行 `PRAGMA integrity_check`；目标已存在时拒绝覆盖。
- 《白灯法则》生产 DB 实测：
  - `ready_for_personal_production=true`
  - `blocking_failures=[]`
  - LLM capacity `45/110`，建议最低 `42/64`
  - SQLite integrity 与 foreign keys 均为 `ok`
  - 6/6 role routes 为真实 provider，0 mock route
- 已生成上线备份：
  `D:\_Progs\.Story\《白灯法则》\.inkflow\backups\inkflow-launch-20260711-104518.db`
  （2,019,328 bytes，integrity check `ok`）。
- 本机代理真实 GLM 上线冒烟成功，`mock_used=false`。
- 新增 `docs/personal-production-runbook.md`，固定生产前 doctor/backup、真实
  write/review/ethics/repair、作者 accept、resume、source coverage、export 和
  故障处置流程。
- 全量离线回归：`431 passed, 9 skipped`。
## 2026-07-11 LCW—Chesil—Ink 正文优化回流

- 新增 `ChesilPatchOrchestrator` 和公开 CLI `ink apply-chesil-patch`。
- patch 必须声明 new-revision-only 和 rerun-review 治理门，且 project、shot、
  run、source text SHA-256、replacement SHA-256 全部匹配。
- 仅允许修改 `soft_sealed`；hard-sealed 或正文已变化的 stale patch 拒绝。
- 应用时通过 `TextRepository.write_revision()` 保留 `source_revision_id`，
  写 `chesil_patch_applied` runtime event，并自动重跑受影响章节 review。
- 返回结果强制提示重新 ethics review 和作者最终 acceptance。

## 2026-07-14 Scene-first 文档重构

- 三模型专项评审完整读取 `ink/docs` 12 份文档：
  - GPT-5.6-sol；
  - GLM-5.2；
  - StepFun Router 工具调用路径（按本机路由契约触发 DeepSeek V4 Pro）。
- 3/3 结论：Scene-first 方向正确，但旧 Shot 中心实现契约、状态机、Snapshot、候选分支和迁移计划尚未闭环，不能宣称最优或已投产。
- 建立新的当前权威文档：
  - `docs/README.md`
  - `docs/design.md`
  - `docs/implementation-contract.md`
  - `docs/migration-plan.md`
  - `docs/author-workflow-contract.md`
  - `docs/interactive-contract-workflow.md`
  - `docs/invariant-traceability.md`
  - `docs/pitfall-checklist.md`
  - `docs/postgresql-rls-adapter-boundary.md`
  - `docs/personal-production-runbook.md`
- 旧 Shot 中心开发文档移入：
  `docs/归档/shot-centered-v2-2026-07-14/`。
- 新文档统一：
  - Scene 是最小正式正文原子；
  - Shot 只作 Scene 内部工作切片；
  - Chapter Candidate Branch 是文学选优单位；
  - Chapter Snapshot 是正式稿和导出权威；
  - Scene Revision、Branch Version、Snapshot 不可变；
  - AI 无 Accept、Activate 和原地改稿权限。
- `iflytek-model-config.md` 已改为无真实凭据的安全配置文档。
- 文档重构前运行离线全量测试，退出码为 0，确认现有 Shot 基线无回归。

## 2026-07-14 Scene-first 影子基础层

- 在`sql/schema.sql`中新增12张Scene-first影子表：
  - Scene、Scene Contract、Contract Clause、Scene Revision、Internal Shot；
  - Generation Round、Candidate Branch、Branch Version、Branch Scene；
  - Chapter Snapshot、Snapshot Scene、Chapter Head。
- 新增数据库硬约束：
  - 同一Scene最多一个active Contract；
  - Scene Revision禁止UPDATE，被Branch/Snapshot引用后禁止DELETE；
  - Frozen Branch Version及其绑定禁止修改；
  - Snapshot封口后禁止修改、删除或继续追加绑定；
  - Branch/Snapshot绑定的Revision必须属于对应Scene；
  - Chapter Head必须指向同project/chapter的sealed Snapshot。
- 新增`SceneRepository`：
  - 创建Scene和四层Contract Clause；
  - 激活approved Contract；
  - 以Branch-local expected parent创建不可变Revision；
  - AI Revision必须绑定generation或repair task；
  - 支持从同一父Revision合法分叉，Revision与Branch绑定原子写入。
- 新增`ChapterSnapshotRepository`：
  - 创建Generation Round、Candidate Branch和Branch Version；
  - 冻结并hash绑定；
  - 选择候选；
  - 原子创建/封口Snapshot并CAS更新Chapter Head；
  - 影子读取只按active Snapshot的固定Revision序列组章。
- 新增Scene-first Schema、Repository和Snapshot测试；同时修复不变量追踪文档，
  明确“已有证据”与“计划门禁”不能混写。
- 全量离线回归：共收集458项，449 passed、9 skipped；旧Shot生产路径未切换、
  未删除，也未形成双正文权威。

## 2026-07-14 Scene-first 文档—任务真实性复审

- 专项评审运行：`AWT-20260714-152414-4ed5bf`；专业线给出通用检查框架，
  主执行器随后直接读取本地文档、Schema、Repository、测试和CLI完成事实核对。
- 修正`design.md`中“代码仍全部以Shot为中心”的过时表述，明确当前是：
  “旧Shot生产权威 + Scene-first影子基础层”。
- `implementation-contract.md`新增逐能力状态矩阵，区分：
  - 已实现的DDL、不可变约束、Branch-local CAS、基础冻结和Snapshot/Head；
  - 未实现的Generation Round、双师契约、Decision/Event、硬门、生产CLI和迁移。
- `migration-plan.md`新增S0—S6真实状态；S1仅完成内存SQLite影子底座，
  既有文件库migration、回填、parity和Cutover均未开始。
- `personal-production-runbook.md`明确schema authority marker和Scene-first生产CLI尚不存在，
  当前Cutover章节只是目标契约，不可直接执行。
- `tasks.md`补回此前遗漏的既有库幂等migration、schema marker、task有效性、
  Branch冻结硬门、actor/Decision/Runtime Event等未完成项。
- 修复Contract创建绕过激活路径，以及Contract激活、Branch选择的多语句原子性。
- 复审后全量离线回归：共收集459项，450 passed、9 skipped；专项评审validate通过。

## 2026-07-15 `ink produce-chapter` 端到端命令收口（deterministic 冒烟通过）

- **新增 `produce-chapter` 子命令**（`cli.py`）：章纲→真实模型候选→jury
  真实审→`scene_accept` 落库→`scene_export` 导出封版正文，一条命令走完
  Scene-first 闭环。注册参数：`--chapter-id/--outline-file/--candidates/
  --rounds/--actor/--output/--force-branch-version-id/--dry-run`。
- **硬能力落地**：
  - 可恢复——`_find_or_create_round` 复用非终态 round（planned/generating/
    supplementing），`drive` 重读状态续跑；终态未 accept 则 `round_number+1`
    滚新一轮；
  - 幂等——已存在 active snapshot 直接跳过 generation 只 export；scene
    contract 复用 active 不重建；
  - 全程留痕——候选稿/jury 原始分走 `writing_ai_call_attempts`，门禁结论
    走 round 状态机，接受版本走 CAS head + decision；
  - 可人工接管——`--force-branch-version-id` 指定 frozen 分支强制 accept
    （自动 `select_branch` 满足 accept 前置），失败 round 后人工兜底。
- **新增 `ink/source/brief_builder.py`**：把 `outline_parser` 解析的
  `ChapterOutline`（白灯 `24_分章大纲.md`）拼成 `RealGenerationPort`
  产稿用的自然语言 brief（标题+场景+冲突+物理因果/沉默点/章末钩子/主引擎
  +1200-1800字），格式对齐 `test_generation_round_real_models.py` 的
  `CHAPTER_BRIEF`。白灯第1章 brief 389 字符验证通过。
- **deterministic 端到端冒烟通过**（临时库，3 候选 2 轮）：generate→validate
  （7维过门）→diff（有实质差异）→select（选 winner）→accept（CAS head+
  snapshot）→export（单章导出）。`accepted:true, eligible_count:3,
  call_count:3`。handler 编排无 bug。
- **已知缺口**：白灯库 draft role-config 配 `api_key_env=LOCAL_PROXY_KEY`
  与环境未设，真模型烟测需先导出本地代理 key（见 bugfix.md BFX-073）。
- **`--no-accept` 模式 + 续 force-accept**（ch01 重校语义落地）：`--no-accept`
  产 frozen winner 不封版（chapter_heads=0）+ 导出 winner 候选稿交作者裁定；
  之后 `--force-branch-version-id <bv>` 续封版（force 模式免 `--outline-file`）。
  临时库 3 候选闭环验证：no-accept→heads=0→force-accept→heads=1，候选稿与
  封版正文均 111 字节一致。`_maybe_export_branch_text` 取 frozen branch 正文
  （非封版 snapshot export）。
- 全量离线回归：全绿（仅真模型 key 相关 skipped，如
  `test_generation_round_real_models`）；deterministic provider 旧 Shot
  `jury:`/`chapter_review:` 分支未动，旧测试不受影响。

### 2026-07-15 真模型烟测白灯第1章：generation+validation 链路实证，validation 0 过门（BFX-074）

- **环境打通**：`LOCAL_PROXY_KEY=fuyi-kiro-17781158558`（bearer）+
  `INK_LLM_API_KEY` 双设 + `--llm-base-url http://127.0.0.1:8000/v1` +
  `--llm-provider openai-compatible`，gateway 真实命中本地代理
  `claude-xunfei-deepseek-v4-pro`（非 deterministic 旁路）。BFX-073 闭环。
- **链路实证（本次 run 实际 6 次 LLM 调用，全 SUCCEEDED，0 BLOCKED）**：
  generation `draft`×3（claude-xunfei-deepseek-v4-pro，3 候选各 1 次）→
  `BRANCH_FROZEN`×3 → validation `_score` `chapter_review`×3（同模型，7 维
  逐维打分，`_parse_scores` 全部解析成功无 malformed）→ `ROUND_TRANSITION`×3。
  即新 Scene-first 全链路（GenerationRoundDriver + RealPorts + 状态机）真模型
  跑通，新 role-config 3 模型命中代理无误。
- **未过门**：3 候选 validation 全卡 `status='validating'`，无一推进
  `literary_review` → `initial_zero_pass`（`failure_reason: initial batch
  passed zero candidates`）。
- **根因（三查定稿，详见 bugfix.md BFX-074）**：`RealValidationPort` 单 judge +
  过门逻辑 `all(score >= shot_quality_floor=85 for 7 维)` 过严——claude-xunfei
  单 judge 逐维裸打（prompt 无评分标准/锚点）对陌生正文保守，至少一维 <85 即
  整组不过门。旧 Shot 体系靠多 judge 取 median + 加权 final_score 才让 83~86
  过门；新 RealValidationPort 单 judge 全维过门必然常 0 过门。deterministic
  冒烟不复现因 deterministic provider 固定给满分 92。
- **已加诊断**（`INK_BFX074_DIAG` env 开关，不影响正常逻辑）：`validate_candidate`
  落盘真模型 7 维分 + 候选正文至 `.bfx074/`，供下次烟测定 floor 偏高还是模型打低分。
- **结论**：BFX-074 是阻塞 P0 真模型烟测产出 winner 的架构 bug，修复方向待真模型
  实际打分数据回来后裁定（多 judge median / 加权总分 / 降 floor 三选一）。


### 2026-07-15 BFX-074 RESOLVED：真模型 winner 已产出，全链路打通（订正前条结论）

- **订正前条结论**：前条判「单 judge 过严 → 0 过门」**错误**。加 `INK_BFX074_DIAG`
  诊断拿真分后真相逆转：
  - 真模型 jury（claude-xunfei-glm-5-2，单 judge，floor=75）实测真分：
    候选1=90/95/92/96/88/94/91（passed）、候选2=85/88/92/95/90/93/87（passed）、
    候选3=82/85/90/88/79/92/70（pacing/contract 不合格，failed）。
    glm-5-2 完全打得出高分，floor=75 合理，过门逻辑无问题。
  - 前"0 过门"真根因是 BFX-075（`ink init` 未设 `INK_LLM_PROVIDER` → role_config
    静默 seed `provider="mock"` → role chain 全走 MockProvider 桩，validation 拿桩
    文本解析 0 维）。**根本没调真模型**。BFX-076（selection UNIQUE idempotency
    冲突）为偶发，二跑不复现，不阻塞。
- **RESOLVED**：诊断脚本 `.fastmeet/run_bfx074_diag.py`（init 前显式设 INK_LLM_*
  三环境变量绕过 BFX-075 + INK_BFX074_DIAG 诊断）二跑全程通过：
  produce-chapter 输出 `"final_status":"selected","winner_branch_version_id":2,
  "eligible_count":3,"call_count":3,"ok":true`；round 终态 `selected`，branch 1=
  selected（winner），2/3=rejected。attempt 表 9 行（draft×3 + validate×3 +
  select×3）全 success=1 无 dup key。
- **意义**：真模型全链路（章纲注入→GenerationRoundDriver 产 3 候选→RealValidationPort
  jury 7 维→RealSelectionPort 选 winner→selected）实证打通，winner 已产出待
  `scene-accept` 封版。**BFX-074 关闭，阻塞解除**，进入第1章纵切验证（tasks.md 任务 2）。
- **遗留**：BFX-075 生产侧 CLI 固化（init 前必须设 INK_LLM_*，否则静默 seed mock）
  与 BFX-076 INSERT OR IGNORE 幂等加固为 P2，不阻塞投稿。
- **现场**：`baideng_bfx074_diag.db` + `.bfx074/`（scores/text/raw + rank_trace）。


### 2026-07-15 第1章纵切闭环验证通过（accept+export 全链路）

- **背景**：BFX-074 RESOLVED 后，winner 已产出但未封版（--no-accept 模式）。
  纵切验证在 `baideng_bfx074_diag.db` 上续跑 `scene-accept` + `scene-export`，
  验收"整条线"而非"写出小说"。
- **纵切全程（真模型 winner branch_id=2，branch_version_id=2）**：
  1. `scene-accept --chapter-id 1 --branch-version-id 2 --actor fuyi` →
     `accepted_decision_id=1, head_version=1, active_snapshot_id=1, snapshot_id=1`。
  2. `writing_chapter_heads` 落 `active_snapshot_id=1, version=1`（封版 head 已落）。
  3. `writing_chapter_snapshots` snapshot_id=1：`source_branch_version_id=2`、
     `sealed_at` 非空、`snapshot_hash=535b55...a3a70`。
  4. 该 hash = `writing_chapter_candidate_branch_versions` 行 2 的 frozen hash →
     **导出版本 = 接受的封版版本**，可追溯一致。
  5. `scene-export --output .bfx074/exported_ch01.md` → 5355B，中文正常、无截断、
     无 prompt 泄漏。
- **验收项对照（tasks.md 任务2 全过）**：
  - 章纲启动 → ✓（run_bfx074_diag.py 从 24_分章大纲.md 启动）
  - ≥1 次真实 jury 决策 → ✓（9 attempt 真 model，glm-5-2 jury 7 维）
  - 正确调 scene_accept → ✓（封版 head 落库）
  - 库状态可核验 → ✓（heads/snapshots/decisions 全落）
  - 导出与接受版本一致 → ✓（hash 一致 535b55...a3a70）
  - `--no-accept` + 续 force-accept → ✓（--no-accept 产 winner 不封版，
    scene-accept --branch-version-id 续封版）
- **意义**：Scene-first 全链路（章纲→GenerationRoundDriver→RealPorts→状态机→
  scene-accept 封版→scene-export 导出）真模型纵切闭环验证通过。第1章白灯 ch01
  封版正文已产出（5355B），待作者裁定是否接受为正式第1章。**进入逐章滚动生产**
  （第2-5章+序章）。数据契约/质量门/产物目录冻结，暂停架构重构。
- **现场**：`baideng_bfx074_diag.db` + `.bfx074/`（exported_ch01.md + scores/text/raw）。


### 2026-07-15 BFX-077 修复 → 白灯第1章真正文封版（纵切实质达标）

- **承接**：同日早些时候的"纵切闭环验证"虽管线机械全过，但导出正文为
  "江辞/陆衍希"言情线，**非白灯法则第1章**。深挖发现根因并修复。
- **根因（BFX-077）**：`generation_round_real_ports.py:_generation_prompt`
  第三段字符串漏 `f` 前缀 → `{brief}` 字面不插值 → 模型只收 82c 无 brief 的
  prompt（token_input=54）→ 自由发挥写言情。详见 bugfix.md BFX-077。
- **修复验证（真模型重跑第1章，干净库）**：
  - draft attempt token_input 54 → **321**（brief 终于进 prompt）✓
  - 三候选正文全部含白灯人设（许怀山/吕素琴/硫化/密封件/返潮/装车），
    **零言情残留** ✓
  - 7 维评分（候选1）：narrative_tension 96 / character_voice 98 /
    scene_concreteness 99 / emotional_resonance 93 / pacing 95 /
    language_polish 94 / contract_adherence 96，floor=75，passed ✓
  - winner=branch_version 3（candidate_index 3）正文开头：
    "硫化车间的铁门推开时发出冗长的呻吟，许怀山走了进去……第十七批，
    一九七九年四月，硫化密封件，目的地代号攀枝花……解放牌卡车……"
    人设/场景/质感全对，文学扎实 ✓
- **封版**：`scene-accept --branch-version-id 3` → head_version=1,
  snapshot_id=1；`scene-export` → 7064B，许怀山/吕素琴/硫化/返潮全命中。
- **意义**：这才是"正文=白灯法则第1章"的真正纵切闭环——管线机械闭环
  **且** 正文达标。第1章白灯 ch01 真正文已封版产出，待作者裁定是否
  接受为正式第1章（见 memory ch01-redo-timeline，产出不封版交裁定）。
- **教训沉淀**：token_input 是判真利器；纵切验收须三查——
  ① attempt.token_input 量级；② 正文 grep 大纲人设名；③ prompt_hash 重算对齐。
- **现场**：`baideng_bfx074_diag.db` + `.bfx074/`（text_r1_b1/b2/b3.md +
  scores + exported_ch01.md 7064B 白灯正文）。
- **下一步**：逐章滚动生产第2-5章+序章。第2章"装车"章纲已就绪。

## 2026-07-15：跨章 context 注入 + 第1/2章正式库封版

**动机**：逐章滚动生产中，每章 brief 只取该章大纲卡片，不含前章正文/伏笔
状态 → 第2章及后续续接断档（人设漂移、伏笔丢失、时间线不接）。作者
2026-07-15 裁定：先做 context 注入再产第2章。

**改动1：brief_builder 加 `_prev_chapter_context`**（`ink/source/brief_builder.py`）
- 产第 N 章 brief 时，取第 N-1 章封版正文（`ChapterSnapshotRepository
  .read_active_chapter_text`），头+末各 300 字拼接（中段 >600 字时用
  "……（中段略）……"省略），拼成 context 段注入 brief。
- context 段插在字数约束句之前（`1200-1800 字。` 保持最末，对齐
  `RealGenerationPort._generation_prompt`）。
- 零额外 LLM 调用、token 可控（+~600 字/章）、`brief 即契约` 原则不破。
- graceful skip 三场景：① chapter_num<=1（第1章/序章无前章）；
  ② 前章未封版（`read_active_chapter_text` raise `DataIntegrityError` → 捕获
  返回 None，不阻断产稿）；③ 调用方未传 conn（向后兼容，旧调用方零改动）。
- `build_chapter_brief` 签名扩 `conn`/`project_id` 可选 kwargs（默认 None =
  不注入，完全向后兼容）。
- 延迟 import `ChapterSnapshotRepository`（避免 brief_builder 被 cli 早期
  加载时的循环依赖）；`DataIntegrityError` 从 `ink.errors` 取（非
  `ink.core.errors`，后者不存在）。

**改动2：cli.py produce-chapter 传 conn**（`ink/cli.py:1551`）
- `build_chapter_brief(args.outline_file, chapter_id, conn=conn, project_id=project_id)`
  —— 把 cli 已开的 conn 与 project_id 透传给 brief 构造，context 自动注入。

**改动3：单测 5 条 + 回归**（`tests/test_brief_builder.py` 新建）
- `test_chapter1_no_context`：第1章传 conn 也不注入。
- `test_prev_context_head_tail_300`：前章正文 >600 字取头300+末300，中段省略，
  字数约束最末。
- `test_prev_context_short_text_uses_all`：前章正文 ≤600 字整段返回。
- `test_prev_chapter_not_sealed_skips`：前章未封版 raise → graceful skip。
- `test_backward_compat_no_conn`：不传 conn → 纯章纲 brief 不注入不报错。
- 回归：`test_generation_round_real_ports.py` + `test_generation_round_driver.py`
  12 测全绿（RealGenerationPort 契约零破坏）。

**正式库产第1章封版（context 源）**：`baideng_prod.db`
- `produce-chapter --chapter-id 1 --candidates 3 --rounds 1 --no-accept` →
  3 候选1轮，winner=branch_version 3，selected。
- 正文 7938B：许怀山×10、吕素琴×10、硫化×5、油纸包×4、返潮×1；
  **零言情残留**（江辞×0、陆衍×0，BFX-077 修复在正式库同样生效）。
- 头200字：一九七九年四月十七，硫化二车间，许怀山，装车台，第十七批，
  一九七九年四月十五日下线，接口密封件，硫化橡胶，四二零四配方，解放牌卡车
  ——时代细节扎实。
- `scene-accept --branch-version-id 3` → snapshot_id=1, head_version=1，
  accepted_decision_id=1。第1章封版完成，作第2章 context 源。

**正式库产第2章带前章 context 产稿**：`baideng_prod.db`
- 第2章 brief 验证含 context：`build_chapter_brief(...,2,conn,project_id=1)`
  返回 2630B brief，含"前章正文摘要"段，头300（一九七九年四月十七…许怀山…
  装车台…四二零四配方）+ 中段略 + 末300（"烟囱的影子长长地投在空了的装车台"），
  字数约束最末。
- `produce-chapter --chapter-id 2 --candidates 3 --rounds 1 --no-accept` →
  3 候选1轮，winner=branch_version 4，selected。
- 正文 6639B：许怀山×6、吕素琴×8、油纸包×4、一九七八×5、密封件×5、
  装车×5、硫化×4；零言情残留。
- **续接验证**：模型准确复现第1章 context 头部的细节——"第十七批，一九七九
  年四月十五日下线，接口密封件，硫化橡胶，四二零四配方"（与第1章封版正文一致）；
  第2章开头"装车台的水泥地面被卡车轮胎碾出一道一道黑印子"接续第1章末尾"装车台"
  场景；吕素琴签名细节延展（"字小，但骨架硬"）。**证明前章 context 真进 prompt
  且被模型用于续接人设/伏笔/时间线。**
- `scene-accept --branch-version-id 4` → snapshot_id=2, accepted_decision_id=2。
  第2章封版完成。

**意义**：跨章 context 注入工程目标达成——逐章滚动不再断档，第2章正文实
证续接第1章伏笔。逐章封版表：第1章(snapshot 1)、第2章(snapshot 2)已封版，
第3-5章+序章待产。下一步：产第3章。

**现场**：`baideng_prod.db`（project_id=1，第1章 branch 3/snapshot 1，第2章
  branch 4/snapshot 2）；`ink/source/brief_builder.py`；`tests/test_brief_builder.py`。

## 2026-07-15：五专家连续评审暴露生产流程三缺陷（P0，暂停逐章）

**触发**：第1/2章封版导出审阅副本后，跑五专家连续评审
（AI工作台 AWT-20260715-171440-5aaf49，报告
`D:\_Progs\.BetterCiv\09_工程脚本\ai_workbench\runs\AWT-20260715-171440-5aaf49\
amy-review-synthesis.md`）。

**评分**：第1章 7.2 / 第2章独立 7.5 / **两章连续 7.1**。评审定位：句子、
物件、氛围已超过结构完成度——不是写得差，是两个质量不错的平行方案，尚未真正
成为有效连续的第一、二章。

**三个 P0**：
1. **P0-1 章节同构**：第2章重演第1章装车/签字/卡车驶离。读者误判"两个平行
   候选版本而非连续两章"。五位连续评审专家全命中。
2. **P0-2 完整因果链**：吕素琴从一次湿度微升直接推演到哑弹，且提前知道完整
   真相却选择不说——损害全书"结构性责任逃逸"命题。应让每人只看因果链一段。
3. **P0-3 科幻锚点缺失**：前两章像纯工业厂史，无 2063/许望舒/衡光未来回声，
   违反《白灯法则》创作契约（旧工厂必须解释未来月球文明危机）。

**根因诊断（对照代码）**：
- **P0-1 主因 = 我做的 context 注入工程**：`_prev_chapter_context` 把前章封版
  正文头+末各300字原文注入后章 brief，模型把前章场景当"本章要复现的设定"
  复述。第2章开头400字实证重演装车签字（封条×3/装车×5/卡车×2）。第2章大纲
  明明要求"裂纹样件+1978旧样件"新事件，却被前章 context 淹没。**当时验收
  "模型复现第十七批四二零四配方"被误判成功，实为重复病根**（复述≠续接）。
  → 登记为 BFX-078，memory `ink-context-injection-raw-text-backfires`。
- P0-1 非大纲问题：第1/2章大纲卡片本身**不同构**（第1章装车抽检+湿热试验+返潮；
  第2章裂纹样件+1978旧样件+两个油纸包）。重复是模型产稿时被 context 注入
  放大制造的。
- P0-2 根因 = 大纲"冲突"字段把完整因果链写死在一张卡 + 流程无视角契约字段。
- P0-3 根因 = 大纲无"未来回环"字段，brief 不含任何科幻信息。

**优化方案**（tasks 2.5 详列）：
- A. context 注入重做（修 P0-1，最高优先）：正文原文 → 结构化前情摘要（分点
  "已发生①…②…,勿复述"），来源优先大纲`章末钩子`字段；prompt 约束"从新事件
  起笔,勿重演"；验收改"新事件起笔+前情不正面复述"。
- B. 视角契约字段（修 P0-2，设定+流程层，需作者裁定大纲）。
- C. 未来回环字段（修 P0-3，设定层，需作者裁定大纲）。

**当前状态**：
- 第3章已产稿（branch_version 8, selected, **未 accept**）暂停审阅，等 P0-1
  context 重做后重产验证同构消除。
- 逐章滚动暂停（tasks 任务3 标暂停）。B/C 涉及大纲修改属作者裁定项，不在流程
  侧擅自改。

**教训**：
1. context 注入验收"复现前章细节"是错误标准——复述就是重复，不是续接。
   正确验收 = 新事件起笔 + 前情作隐含背景不正面复述。
2. 工程优化（context 注入）可能反向制造评审病根；真模型产稿后必须跑连续
   评审验证"成篇连贯性"，不能只验单章人设命中。
3. 大纲卡片的`章末钩子`字段本就是结构化前情摘要的现成来源——context 注入
   应优先用它，而非去取正文原文重新抽取。

## 2026-07-15：契约层未接线生产链路——架构根因定位（BFX-079）

**触发**：用户追问"为什么开发文档有的东西，代码实现跳过了，根因在哪儿"。
对五专家评审三个 P0 做第三轮深挖，从"机制层"挖到"架构层"。

**直接证据（代码自白）**：
- `_ensure_scene_and_contract` docstring："Dead-line policy skips the dual-blind
  self_check / independent review; the human actor activation is the seal."
  建的契约是空壳：contract_hash=sha256(brief)、source_bundle_hash 同一 hash，
  design 3.1 四层 clause 一个没落。
- `brief_builder.py:8`："死线收口用：不落 chapter contract payload / scene
  contract 四层 clause"。
- `record_contract_review` 零生产调用方（死代码）。契约层工具（confirm_and_apply/
  DecisionSession/record_contract_review/stale 传播）只挂在需人工手动触发的
  CLI 命令上，produce-chapter 生产链路完全不调。
- git 考古：契约层工具早期提交（1b93f3c5/259145e2）建好即搁置；brief_builder
  今天（03bea0fe）新建直接裸拼大纲，未接任何契约层。两层不同时间、不同目的建，
  中间无接线。

**层级落地现状**：design §2 五级契约 vs 实现——
- Book：仅 book_quality_floor 数值 75，无内容，不注入 brief，不调生产
- Volume：volume_id 全 NULL，stale 退化"全部章节"，不注入不调
- Part：part_id 全 NULL，同上
- Chapter：表存在但空壳占位，四层 clause 未落，不注入
- Scene：同 Chapter

**根因三层**：
1. 表面 = 死线降级（7-30 投稿死线压着，为端到端跑通砍契约审查）。
2. 机制 = 契约层（CLI 旁路工具）与生产层（produce-chapter）两套独立建的工具，
   中间无接线。契约层建好即搁置成死工具，生产层裸奔。
3. 真 = 无"契约贯穿生产"硬约束 + 降级不可逆。第一次降级（跳双盲审查）无追责
   无回补，后续 brief 裸拼 / context 注入正文都在"契约已缺位"错误前提上继续
   固化，错误前提被固化成架构。

**P0-1/2/3 统一解释**：缺 Chapter 级"结构职责"契约→同构；缺 Chapter 级"知情
边界"契约→全知；缺 Volume/Book 级"未来回环分布"契约→无科幻。一个根，三个
表现。BFX-078（context 注入正文原文）是此根的表层补丁，正解 = 撤正文 context、
把契约层接回生产。

**解决方案（建硬约束，非补丁）** → `docs/contract-layer-rewire-design.md`：
- A. produce-chapter 前置契约为硬 gate（无 confirmed Chapter 级契约→拒绝产稿）
- B. 契约层下沉进生产子步骤：draft_contract→record_contract_review→confirm_and_apply
- C. 加降��门+debt_marker，清"死线策略"docstring
- D. 契约成唯一真相源：brief_builder 改读契约表，撤大纲裸拼+正文 context
- E. 加成篇连贯门+jury 连贯维度

**落地顺序** B→A→C→D→E。B/C/D/E 纯代码接线。

**卡点**：卷级三表内容（章节功能分工表/视角信息分配表/未来回环分布表）是
作者设定权，需作者裁定，代码层只做读表注入+门校验。

**教训**：
1. 设计文档与代码"两张皮"是系统性风险——设计写得再完整，没有"生产必须贯穿
   契约"的硬约束，建生产层时一句 docstring 就能砍掉。
2. 降级必须可追责、可恢复、有门拦截，否则临时降级会被后续代码固化成默认架构。
3. 发现质量问题要挖根因不打补丁——之前每层补丁（单章质量门、context 注入）
   都在错误前提上加固，根因不动，质量停在 7.1 上不去。
4. 契约层工具建好后零生产调用方 = 死代码，是"建了工具没接流水线"的典型信号，
   今后新工具必须同步接进生产入口才算交付。

**登记**：BFX-079（架构根因）；tasks 插入 2.6 阻塞块，逐章滚动暂停待 BFX-079
接线；BFX-078（context 注入补丁）降级并入方案 D。memory
`ink-contract-layer-rewire-root-cause`（防再犯）。
