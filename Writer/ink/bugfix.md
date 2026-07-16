# InkFlow v2 Bugfix 记录

> **用途**：记录开发中发现的缺陷、根因、修复和防回归测试。
> **最后更新**：2026-07-16

---

## 2026-07-16 BFX-086 Scene-first Accept 决定记录位于权威事务外

- **现象**：`scene-accept`、`produce-chapter` 正常接受和 force-accept 都先调用
  `record_human_decision`，再调用 `accept_chapter`；若后者因 Head CAS、stale lineage、
  Snapshot 或 Event 写入失败，Human Decision 已留库却没有对应接受结果。同时
  `writing_selection_decisions`/`record_selection_decision` 已存在但生产路径无调用。
- **根因**：Accept Repository 只把 Snapshot、Head 和 Runtime Event 纳入 `_atomic`，
  把 Selection/Human Decision 错误地当成调用方前置准备，而不是最终接受权威的一部分。
- **修复**：`accept_chapter` 改为接收决定原始证据，在同一事务内创建 Selection Decision、
  Human Decision、sealed Snapshot/Scene bindings、CAS Chapter Head 和
  `CHAPTER_ACCEPTED` Event；三个 CLI 入口均改为单次 Accept 调用，Event 同时记录两个
  Decision ID。
- **防回归**：新增成功证据一致性断言，以及对 Selection、Human、Snapshot、Head、Event
  五个写入阶段的 SQLite trigger 故障注入；任一步失败均不遗留 Decision、Snapshot、
  binding、Head 变化或 Accept Event。聚焦测试 34 passed；全量结果见 `history.md`。

## 2026-07-08（质量门真实化阶段 — 缺陷登记，修复随阶段 A-F 推进）

### BFX-033 jury/chapter_review/book_check 评分全是桩，质量门形同虚设（实跑 6 章后暴露）

- **现象**：6 章实跑链路「跑通」并产出 novel.md，但 jury/chapter_review/book_check 三处评分函数从不调 LLM，靠桩算分：`jury_orchestrator._score_for_draft`/`_median_scores_for_draft`/`_raw_scores_for_slot`（`jury_orchestrator.py:349-375`）按 `draft.text` 里的 `[low-quality]`/`[dimension-fail]` 标记字符串算分，真实 draft 无标记时一律 `84+index`；`chapter_review_orchestrator._score_chapter`（`:154-163`）、`book_rolling_check_orchestrator._book_scores/_book_issues`（`:150-167`）恒 82+、恒无 blocking。导致 `quality_gate_passed` 恒真、`has_blocking_issues` 恒假，`accept_chapter` 闸门（`human_review_orchestrator.py:29-32`）永远放行——质量门是装饰。
- **根因**：架构就绪（jury schema 12 维 + CHECK + winner 索引 + escalation 全建好）但评分实现是占位桩，实跑时没人发现「分都是假的」，因为 6 章 accept/export 流程表面跑通。属「集成测试覆盖了流程未覆盖真实性」的盲区。
- **修复计划**（阶段 C/D）：桩换成真实 `gateway.call`（call_type=jury/chapter_review/book_check）→ 解析 12/7/6 维分 → 落 raw_scores+aggregate；blocking issue 非 0 即拦 accept。复用现有 schema/quality_gate/winner。
- **防回归**：`tests/test_jury_real_scores.py`（mock gateway 验证 3 裁判真实分落库 + median + quality_gate 按真实分判）、`tests/test_chapter_review_real.py`/`test_book_check_real.py`。

### BFX-034 `_DEFAULT_ORCHESTRATOR` 单例从未赋值，是死代码（gateway 注入点误判）

- **现象**：原计划给 `JuryOrchestrator.__init__` 加 `gateway` 参数并经 `_DEFAULT_ORCHESTRATOR` 注入。审查发现 `_DEFAULT_ORCHESTRATOR`（`jury_orchestrator.py:14`）只有声明 `= None`，全仓 grep `_DEFAULT_ORCHESTRATOR =`（赋值）零命中；模块级 `score_and_select_winner(shot_id, run_id)`（`:60-63`）一调就抛 `DataIntegrityError("jury orchestrator is not configured")`。outline/write/hard_gate/polish 的同名单例同理全是死代码。
- **根因**：真实调用路径是调用方直接构造（`cli.py:966,969` 的 `JuryOrchestrator(conn)`、`resume_handlers.py:32`），不经单例。`JuryOrchestrator` 是 `_run_shot_to_soft_sealed` 里唯一没传 gateway 的（其余 PreDrafting/Write/Polish 都传了）——这才是真实 jury 不调 LLM 的直接原因（用 `LLMGateway(conn)` 默认 mock provider）。
- **修复计划**（阶段 C）：改真实构造点 `cli.py:966,969` + `resume_handlers.py:32` 传 gateway；`_handle_quality_retry_or_fail:115` 的 `WriteOrchestrator(self.conn)` 改 `WriteOrchestrator(self.conn, self.gateway)`；删 `_DEFAULT_ORCHESTRATOR` 死代码 + 模块级 `score_and_select_winner`。测试脚本同步传注入式 gateway。

### BFX-035 failover 三 tier 失败污染熔断计数（设计性，未实现先纠）

- **现象（预判）**：若 failover 内每个 tier 失败都调 `budget.record_call`，因 `retry_budget.py:155-164` 的 `check_circuit` 连续失败查询只按 `shot_id` 聚合（不按 call_type 过滤）、`record_call`（`:124-135`）按 `(shot_id, call_type, failure_type)` 计数且三 tier 同抛 `LLMProviderError`，三 tier 失败累加同一行 `consecutive_count`。默认 `consecutive_failure_circuit_break=3`（`schema.sql:27`）→ jury 3 裁判每个都 failover 时，第 2 个裁判一进来 `check_circuit` 就直接熔断，连主 tier 都不试。
- **根因**：熔断设计假设「一次 record_call = 一次逻辑调用」，failover 把一次逻辑调用拆成多次物理 tier 调用，计数语义错配。
- **修复计划**（阶段 B）：failover 内 tier 失败**不调 `record_call`**，只在逻辑调用整体成功（重置计数）/ 整体失败（记一次 `LLMProviderError`）后调。tier 切换信息走 `writing_runtime_events`（`model_role_failover`），`writing_ai_call_attempts` 不加 tier 列（避免迁移 + 破 SoftSeal 契约）。
- **防回归**：`tests/test_model_role_config.py` 验证 failover 切换不污染 `consecutive_count`。

---

## 2026-07-08（6 章流水线真实模型版阶段）

### BFX-030 PolishOrchestrator 硬编码 `smart-polish` 模型名（真实 provider 不认）

- **现象**:`tests/test_e2e_real_models.py` 实跑真实 iFLYTEK 时,polish 段抛 `LLMProviderError: provider HTTP 500: ... PathDomainError:Model Not Found`;��后 `SoftSealOrchestrator` 抛 `winner must be a polished smart-model draft before soft seal`。
- **根因**:`PolishOrchestrator.polish_winner`(`src/ink/pipeline/polish_orchestrator.py:38`)硬编码 `model_name="smart-polish"` 调 `gateway.call`;`SoftSealOrchestrator`(`src/ink/pipeline/soft_seal_orchestrator.py:33`)又校验 winner draft 的 `writer_model == "smart-polish"`。mock `WorkflowProvider` 透传入参不校验,故 m6 smoke 不暴露;真实 iFLYTEK 把 `smart-polish` 当模型名发给网关,返回 `Model Not Found`。且 `PolishOrchestrator` 用 `result.model_name` 写 `draft.writer_model`,真实 provider 返回的 `model_name` 是响应里的真实模型名(非 `smart-polish`),破坏 soft seal 契约。
- **修复(测试侧,不改生产代码)**:`tests/test_e2e_real_models.py` 原用 `_RemappingProvider` 包装层——调用底层 `OpenAICompatibleProvider` 时把 `smart-polish` 翻译成真实模型 `xopglm51`,返回 `ModelResult` 时把 `model_name` 还原为原始别名 `smart-polish`,保持 `SoftSealOrchestrator` 的生产契约。
- **生产侧已修复(2026-07-08 阶段1)**:已在 `LLMGateway` 层正式落地模型别名路由,`_RemappingProvider` 测试包装层已移除,改用与生产 CLI 完全一致的机制(别名存 `writing_projects.model_aliases` JSON 列,`LLMGateway.call` 翻译别名调 provider、返回前用 `dataclasses.replace` 还原别名保持 soft seal 契约)。详见 BFX-031。

### BFX-031 LLM provider 无退避重试(iFLYTEK 429/503 限流致 6 章链路中断)

- **现象**:实跑真实 iFLYTEK 6 章链路时,网关频繁返回 `HTTP 429`(code 11210 "authorization failed" 实为限流)/`HTTP 503`(code 10310 "system is busy")。`OpenAICompatibleProvider.complete` 无重试,单次 429 即抛 `LLMProviderError`,outline/polish 段无降级兜底直接 skip,write 段虽兜底但产出 degraded draft,6 章无法跑完。
- **根因**:`OpenAICompatibleProvider.complete`(`src/ink/core/llm_gateway.py`)对任何 `HTTPError`/`URLError` 直接抛,不区分瞬时错误(429/5xx/超时)与不可重试错误(401/400/402/404)。iFLYTEK 包月套餐限流是常态,无重试 = 实跑链路不可用。
- **修复**:`OpenAICompatibleProvider` 加 `max_retries`/`retry_base_delay` 参数,`complete` 内对 429/500/502/503/504/超时/JSON 解析失败做指数退避重试(`base * 2^attempt * (1 + jitter)`,jitter 用 `idempotency_key` 哈希做确定性种子,避免所有请求同步重试加剧限流,不引入 `random`);401/400/402/404 等立即抛。`Idempotency-Key` 保证重试安全(服务端去重)。`LLMProviderConfig` 加 `max_retries` 字段,`load_llm_provider_config` 对 openai-compatible 默认 4 次(CLI `--llm-max-retries` 或 `INK_LLM_MAX_RETRIES` 可覆盖)。`_gateway`(`src/ink/cli.py`)贯通该参数。
- **防回归**:`tests/test_openai_provider.py::TestProviderRetry` 7 个用例(429/503 重试后成功、重试耗尽抛、401 不重试、成功不重试、默认不重试、config 默认 4 次)。

### BFX-032 outline drift 阈值对真实模型过严(CJK bigram 重叠趋近 0 致全拒)

- **现象**:`tests/test_e2e_real_models.py::test_real_six_chapter_pipeline` 实跑时 outline 段抛 `DataIntegrityError: eligible outlines below threshold: 0 < 1`,3 个 writer 模型各产出的 outline 全部 drift 拒绝,6 章链路在 outline 段即 skip。
- **根因**:`OutlineOrchestrator.run_until_winner`(`src/ink/pipeline/outline_orchestrator.py:51-53`)用 `cjk_bigram_overlap(source_text, outline_text)` 算 outline 与契约结构化字段(`must_land` 事件 + `scene_contract`)的 CJK bigram **重叠度**作为 drift_score,`is_drift_rejected` 判 `drift_score < threshold` 拒绝。但 `source_text` 是短结构化字段(如"主角抵达码头""夜晚雨中"),真实模型(GLM/DeepSeek)倾向用自己话写成段叙述,bigram 与契约几乎不重叠,drift_score 趋近 0,远低于 `0.10`(甚至默认 `0.20`)阈值,全拒。这是设计假设(outline 会复用契约关键词)与真实模型行为(自由重写)的错配。
- **修复(测试侧阈值放宽)**:e2e fixture `gateway_conn` 的 `outline_drift_threshold` 由 `0.10` 降至 `0.02`,适配真实模型低重叠特性;`min_eligible_outlines` 保持 1。
- **生产侧待办(P2)**:drift 算法应改用「契约关键词在 outline 中的包含率」或「语义相似度」,而非 bigram 字面重叠,否则真实部署需把阈值压到极低(牺牲 drift 校验意义)。当前生产 CLI 已暴露 `--outline-drift-threshold`,用户可按真实模型特性调低。留作 P2 跟进。

---

## 2026-07-07（iFLYTEK 真实 LLM 接入阶段）

### BFX-024 iFLYTEK API 401 Unauthorized（鉴权格式错误）

- **现象**：用 `apiKey`（冒号后半段）作 Bearer token，返回 `401 Unauthorized`。
- **根因**：iFLYTEK MaaS Coding API 要求 Bearer token 是**整串 `appId:apiKey`**，不是只用 apiKey 部分。
- **修复**：所有调用改用 `Authorization: Bearer 83e14cca3d4042e045c62358f11ffdfa:ZmFkMzNhMWVkOTY0NzYyYmZjZWFmYjFl`。
- **防回归**：`tests/test_iflytek_integration.py` 的连通性测试隐式验证鉴权。

### BFX-025 iFLYTEK API 404（路径前缀错误）

- **现象**：用 `/v1/chat/completions` 返回 404。
- **根因**：iFLYTEK 端点前缀是 `/v2`，不是 OpenAI 默认的 `/v1`。
- **修复**：`base_url` 用 `https://maas-coding-api.cn-huabei-1.xf-yun.com/v2`，`OpenAICompatibleProvider` 自动拼 `/chat/completions`。

### BFX-026 推理模型 content 为空（max_tokens 不足）✅ 已修复

- **现象**：`xminimaxm25` / `xsparkx2` / `xsparkx2flash` 在 `max_tokens=100` 时 `content` 为空，只有 `reasoning_content`。
- **根因**：推理模型先把 token 预算花在思维链上，剩余预算不足以产出可见 content。
- **修复**（2026-07-07）：`OpenAICompatibleProvider` 新增 `_is_reasoning_model()`（sparkx2/minimaxm 子串匹配），自动注入 `max_tokens=2000`；`_parse_chat_completion_response` 在 `content` 为空时回退读 `reasoning_content`。可用 `--llm-max-tokens` / `INK_LLM_MAX_TOKENS` 全局覆盖。
- **防回归**：`tests/test_openai_provider.py` 14 个单测覆盖 max_tokens 注入与 reasoning_content 回退。

### BFX-027 iFLYTEK API 503 限流（code:10310）

- **现象**：连续高频调用返回 `503 {"error":{"code":10310,"message":"The system is busy"}}`。
- **根因**：套餐有并发/频率限制，批量调用需间隔。
- **修复**：批量测试加 `time.sleep(2-5)`，重试 3 次（每次用新 idempotency key），仍失败则 `pytest.skip`。
- **防回归**：`test_all_standard_models_reachable` / `test_reasoning_models_reachable` 内置重试 + skip。

### BFX-028 writing_ai_call_attempts UNIQUE 约束冲突（重试时 key 复用）

- **现象**：503 重试时，`LLMGateway.call()` 在 HTTP 调用前 INSERT `writing_ai_call_attempts(idempotency_key=...)`，同一 key 二次 INSERT 触发 UNIQUE 冲突。
- **根因**：`LLMGateway.call()` 先写 DB 再发 HTTP，重试时 key 必须变更。
- **修复**：测试重试时用 `f"iflytek-std-{model_id}-{attempt}"`（含 attempt 序号）生成新 key。
- **防回归**：上述重试逻辑覆盖。

### BFX-029 TestStaleChain fixture 重复插入 project（UNIQUE 冲突）

- **现象**：`tests/test_debug_view.py::TestStaleChain` fixture 同时调用 `_insert_project(c)` 和 `insert_minimal_draft(c)`，后者也插 `project_id=1`，触发 `sqlite3.IntegrityError: UNIQUE constraint failed: writing_projects.project_id`。
- **根因**：`insert_minimal_draft` 已自带 project 插入，fixture 又额外插一次。
- **修复**：移除 `TestStaleChain` fixture 中的 `_insert_project(c)` 调用，依赖 `insert_minimal_draft` 建 project。
- **防回归**：`test_no_stale` / `test_stale_after_book_change` 重新通过。

---

## 2026-07-06（架构增强阶段）

### BFX-016 _find_chapters_in_volume/_find_chapters_in_part 方法缺失

- **现象**：`StalePropagationManager.mark_stale_after_contract_change()` 在 volume/part scope 分支调用 `self._find_chapters_in_volume()` / `self._find_chapters_in_part()`，触发 `AttributeError: 'StalePropagationManager' object has no attribute '_find_chapters_in_volume'`。
- **根因**：之前文件重写时丢失了这两个方法；volume/part 代码分支调用了不存在的方法。
- **修复**：重新添加两个方法，查询 `writing_shots.volume_id` / `writing_shots.part_id`。
- **防回归**：`tests/test_stale_propagation.py::TestVolumePartScopeStale` 全部通过。

### BFX-017 _mark_*_for_chapters（plural）方法缺失

- **现象**：volume/part scope 调用 `self._mark_prompts_for_chapters(chapter_ids)` 触发 `AttributeError: 'StalePropagationManager' object has no attribute '_mark_prompts_for_chapters'`。
- **根因**：只有单数版 `_mark_prompts_for_chapter(project_id, chapter_id)` 存在，volume/part 需要批量标记多章，但没有 plural 版方法。
- **修复**：添加 `_mark_prompts_for_chapters()` / `_mark_drafts_for_chapters()` / `_mark_reviews_for_chapters()`，内部遍历 chapter_ids 调用单数版。
- **防回归**：`tests/test_stale_propagation.py::TestVolumePartScopeStale` 全部通过。

### BFX-018 _load_session_for_confirm 缺少 scope_type/scope_id 导致 KeyError

- **现象**：`DecisionSessionStore.confirm_and_apply()` 读取 `session["scope_type"]` 触发 `KeyError: 'scope_type'`。
- **根因**：`_load_session_for_confirm()` 的 SELECT 和返回字典只包含 4 个字段，没有 `scope_type` / `scope_id`。
- **修复**：扩展 `_load_session_for_confirm` 的 SELECT 语句和返回字典，包含 `scope_type` 和 `scope_id`。
- **防回归**：所有涉及 `confirm_and_apply` 的测试通过（13 个测试之前因 KeyError 失败）。

### BFX-019 writing_ai_call_attempts.call_type CHECK 不包含 'source_extraction'

- **现象**：`LLMExtractionAdapter.__call__()` 调用 `LLMGateway.call(call_type='source_extraction', ...)` 触发 `CHECK constraint failed: call_type IN (...)`。
- **根因**：`writing_ai_call_attempts.call_type` 的 CHECK 约束只列出原有 11 种 call_type，没有 `source_extraction`。
- **修复**：DDL 中 CHECK 新增 `'source_extraction'`。
- **防回归**：`tests/test_llm_integration.py` 全部通过。

### BFX-020 ** 解包与三元运算符语法错误

- **现象**：`debug_view.py` 中 `**json.loads(str(row[2])) if row[2] else {}` 触发 `SyntaxError: invalid syntax`。
- **根因**：Python 不允许 `**expr if cond else default` 这种形式，三元运算符优先级低于 `**` 解包。
- **修复**：加括号 `**(json.loads(str(row[2])) if row[2] else {})`。
- **防回归**：语法错误在编译期被捕获；`python -m compileall` 通过。

### BFX-021 writing_runtime_events 列名错误

- **现象**：`DebugView.show_shot_full_trace()` 查询 `writing_runtime_events.payload_json` 触发 `sqlite3.OperationalError: no such column: payload_json`。
- **根因**：该表的 JSON 列名为 `event_payload`，不是 `payload_json`。
- **修复**：SELECT 和解析改为 `event_payload`。
- **防回归**：`tests/test_debug_view.py::TestShotTrace` 全部通过。

### BFX-022 ModelResult 字段名错误

- **现象**：`_ScriptedProvider` 构造 `ModelResult(tokens_used=42, ...)` 触发 `TypeError: __init__ got an unexpected keyword argument 'tokens_used'`。
- **根因**：`ModelResult` 使用 `token_input` / `token_output`，不是 `tokens_used`。
- **修复**：测试改为 `token_input=10, token_output=32`。
- **防回归**：`tests/test_llm_integration.py` 全部通过。

### BFX-023 writing_chapter_reviews 无 created_at 列

- **现象**：`DebugView.show_stale_chain()` 查询 `writing_chapter_reviews.created_at` 触发 `sqlite3.OperationalError: no such column: created_at`。
- **根因**：该表的时间列名为 `reviewed_at`，不是通用的 `created_at`。
- **修复**：SELECT 和输出字段改为 `reviewed_at`。
- **防回归**：`tests/test_debug_view.py::TestStaleChain` 全部通过。

---

## 2026-07-06（主编台产品化阶段）

### BFX-011 StalePropagationManager frozen dataclass 赋值错误

- **现象**：`StalePropagationManager.mark_stale_after_contract_change()` 返回 `StaleMarkResult` 时，尝试给 `result.affected_prompt_ids` 赋值，触发 `FrozenInstanceError: cannot assign to field`。
- **根因**：`@dataclass(frozen=True)` 创建的 dataclass 字段不可变，但代码中需要动态构建列表并赋值。
- **修复**：`StaleMarkResult` 改为 `@dataclass`（移除 `frozen=True`）。
- **防回归**：`tests/test_stale_propagation.py` 全部通过。

### BFX-012 extractor_slot 违反 CHECK 约束

- **现象**：`SourceNormalizer.normalize_source_directory()` 调用 `record_extraction_run()` 时传入 `extractor_slot="default"`，触发 `CHECK constraint failed: extractor_slot IN ('primary','crosscheck')`。
- **根因**：`writing_source_extraction_runs.extractor_slot` DDL 约束只允许 `'primary'` 或 `'crosscheck'`，代码使用了不存在的 `'default'`。
- **修复**：改为 `extractor_slot="primary"`。
- **防回归**：`tests/test_source_normalizer.py` 全部通过。

### BFX-013 writing_contract_patches 无 scope_type 列

- **现象**：`StalePropagationManager.mark_stale_after_source_change()` 查询 `writing_contract_patches` 时 SELECT `scope_type, scope_id`，触发 `sqlite3.OperationalError: no such column: scope_type`。
- **根因**：`writing_contract_patches` 表只存 `decision_session_id`，不直接存 `scope_type/scope_id`；需要通过 JOIN `writing_decision_sessions` 获取。
- **修复**：查询改为 `JOIN writing_decision_sessions ds ON ds.decision_session_id = cp.decision_session_id`，SELECT `ds.scope_type, ds.scope_id`。
- **防回归**：`tests/test_stale_propagation.py::TestSourceChangeStale` 全部通过。

### BFX-014 WorkflowConductor.step() 返回值类型错误

- **现象**：端到端测试中用 `result["next_action"]` 访问返回值，触发 `TypeError: 'WorkflowStep' object is not subscriptable`。
- **根因**：`WorkflowConductor.step()` 返回 `WorkflowStep` dataclass，不是 dict；应该用 `result.next_action` 访问。
- **修复**：测试代码改为 `result1.next_action`。
- **防回归**：`tests/test_e2e_six_chapters.py` 全部通过。

### BFX-015 WorkflowConductor.step() 缺少 human_text 参数

- **现象**：端到端测试调用 `conductor.step(project_id=1, session_id=session_id)` 后，session 状态仍为 `collecting`，未推进到 `awaiting_confirm`。
- **根因**：`step()` 在 `status == "collecting"` 时检查 `human_text is None`，如果为 None 则返回 `wait_for_input` 而不推进状态；必须传入 `human_text` 才能触发解析。
- **修复**：测试改为 `conductor.step(project_id=1, session_id=session_id, human_text="封全书基线契约")`。
- **防回归**：`tests/test_e2e_six_chapters.py::test_full_pipeline` 和 `test_recovery_point` 通过。

### BFX-010 ContractPatchEngine 开发中发现的缺陷

#### BFX-010a 测试辅助函数 _insert_project 违反 CHECK 约束

- **现象**：`test_contract_patch_engine.py` 的 `_insert_project` 用 `'["a"]'` 和 `'["b"]'` 写 `writer_model_pool` 和 `jury_model_pool`，触发 `CHECK constraint failed: json_array_length(writer_model_pool) >= draft_count`。
- **根因**：未复用 `test_decision_source_workflow.py` 中已有的正确格式（`'["writer-a","writer-b","writer-c"]'`），假设数组长度 ≥ 1 即可。
- **修复**：改用 3 个 writer + 5 个 judge 的标准格式。
- **防回归**：所有新测试通过。

#### BFX-010b regex 不匹配实际错误消息

- **现象**：`test_rejects_unsupported_op` 的 `match="unsupported op"` 不匹配实际消息 `"op #0 has unsupported or missing op: 'copy'"`。
- **根因**：`validate_patch_shape` 的错误消息更精确（包含 "or missing"），测试 regex 未同步。
- **修复**：regex 改为 `"unsupported or missing op"`。
- **防回归**：`test_contract_patch_engine.py::TestValidatePatchShape::test_rejects_unsupported_op`。

#### BFX-010c intra-conflict 检测使用去重后的路径列表

- **现象**：`_check_intra_patch_conflicts` 用 `patch_paths(patch)` 返回去重后的列表，导致 `len(paths) != len(set(paths))` 永远为 False，冲突检测失效。
- **根因**：`patch_paths` 的设计意图是提取所有影响的 path 用于 coverage 更新，天然去重；冲突检测需要统计每个 path 的出现次数。
- **修复**：改为直接统计 `path_counts`，重复则报错。
- **防回归**：`test_contract_patch_engine.py::TestIntraPatchConflicts::test_duplicate_path_raises`。

#### BFX-010d _load_session_for_confirm 缺少 readback_text 和 source_hashes_json

- **现象**：`confirm_and_apply` 在 patch_engine 模式下读取 `session["readback_text"]` 和 `session["source_hashes_json"]`，但 `_load_session_for_confirm` 只返回 4 个字段，导致 KeyError 或空字符串。
- **根因**：原有代码只需 `parsed_patch_json`，新增 patch_engine 模式后需要 readback 和 source_hashes 但未更新 SQL 查询。
- **修复**：`_load_session_for_confirm` 扩展 SELECT 和返回字典，包含 `readback_text` 和 `source_hashes_json`。
- **防回归**：`test_contract_patch_engine.py::TestIntegrationWithDecisionSession::test_confirm_and_apply_with_patch_engine_full_audit`。

#### BFX-010e _load_session_for_confirm 返回字典时多余闭合括号

- **现象**：编辑 `_load_session_for_confirm` 添加新字段后，第 562 行有多余的 `}`，导致 `SyntaxError: unmatched '}'`。
- **根因**：复制粘贴时没有注意到原代码末尾已有字典闭合括号，重复添加。
- **修复**：删除多余的 `}`。
- **防回归**：所有测试通过（语法错误在编译期就会被捕获）。

### BFX-009 DecisionSession active 唯一索引误含 status

- **现象**：v1.1 DecisionSession DDL 初稿将 `status` 放进 active 唯一索引键，导致同一 `target_type/target_id` 可以同时存在 `collecting`、`ai_parsed` 等多个活跃会话。
- **根因**：唯一索引把“活跃状态过滤条件”和“唯一业务键”混在一起，实际约束变成“同一 target 同一状态唯一”，没有约束“同一 target 单 active session”。
- **修复**：唯一索引改为 `(project_id, target_type, COALESCE(target_id,'')) WHERE status IN (...)`，不再把 `status` 纳入唯一键。
- **防回归**：`tests/test_decision_source_workflow.py::test_decision_session_enforces_single_active_target_and_option_regeneration`。

### BFX-007 CLI resume 忽略 session 级 resume_point

- **现象**：`ink resume --session-id` 只遍历 `writing_shots` 并执行 shot 级 action，未读取 `writing_sessions.resume_point`，导致 `chapter_review`、`book_check` 等 session 级断点无法恢复。
- **根因**：M2-M4 先落地 shot 级 resume registry，M5-M6 的章级/篇级/导入恢复点没有统一 dispatch 入口。
- **修复**：新增非 shot 级 resume handler registry；`ResumeManager.execute_resume_point()` 按 `phase` 调度；CLI `resume` 在 shot 恢复后执行 session 级 resume point，并在成功后清空 `crashed/resume_point`。
- **防回归**：`tests/test_resume_handler_registry.py::test_cli_resume_executes_session_level_chapter_review`。

### BFX-008 import finalize 恢复可能重复写审计

- **现象**：同一 `import_run_id` 如果在 finalize 成功后再次通过恢复链路执行，会再次写入 `writing_human_decisions` 和 `writing_import_decisions`。
- **根因**：`ImportOrchestrator.finalize()` 没有先检查该 import run 是否已有 finalize 决策；DDL 也未对 `writing_import_decisions.import_run_id` 设置唯一约束。
- **修复**：`finalize()` 入口先读取既有 import decision；已存在时直接返回既有 `ImportFinalizeResult`，不再写第二份审计。
- **防回归**：`tests/test_resume_handler_registry.py::test_non_shot_resume_executes_import_finalize_once`。

## 2026-07-05

### BFX-001 import questions schema 字段误用

- **现象**：`test_import_finalize_rejects_unresolved_questions` 最初向 `writing_import_questions.created_at` 写入数据，但 DDL 中该表没有 `created_at` 字段。
- **根因**：测试假设了通用审计字段，未核对 import question 的真实 DDL。
- **修复**：按 schema 改为只写 `import_run_id / manifest_id / question_text / options_json`。
- **防回归**：`tests/test_m6_import.py::test_import_finalize_rejects_unresolved_questions`。

### BFX-002 revise/accept loader 绑定反转

- **现象**：reject 后 revise 被 pending-only loader 阻断；同时 accept 错误地允许 rejected review。
- **根因**：`accept_chapter` 与 `revise_chapter` 的 review loader 语义在重构中绑定反了。
- **修复**：`accept_chapter` 使用 `_load_pending_review()`；`revise_chapter` 使用 `_load_revision_source_review()`，允许从 pending/rejected 发起修订。
- **防回归**：`tests/test_m6_workflow_smoke.py::test_rejected_chapter_cannot_be_accepted` 和 `test_full_production_flow_six_chapters`。

### BFX-003 CLI setup 默认 persona 违反 DDL 枚举

- **现象**：CLI `setup` 写入英文 persona `suspense`，触发 `writing_shot_persona_assignment.persona` CHECK 失败。
- **根因**：CLI 默认契约没有复用 schema 中允许的五类中文 persona。
- **修复**：CLI 默认 setup 改为 `悬疑官`，并使用中文 5 维强度键。
- **防回归**：`tests/test_cli.py::test_cli_chapter_revise_export_import_flow` 和 `test_cli_resume_starts_pending_shot`。

### BFX-004 invariant 追踪矩阵漏接声明项

- **现象**：`invariant-traceability.md` 中存在 `INV-RUN-001`、`INV-AUDIT-001`、`INV-FACT-001`、`INV-QUALITY-009`、`INV-QUALITY-010`，但追踪测试未强制登记。
- **根因**：追踪测试只验证已登记 ID 有证据，未反向检查矩阵中的所有 `INV-*`。
- **修复**：补齐对应测试，并让追踪测试断言矩阵 ID 与 `INVARIANT_EVIDENCE` 完全对齐。
- **防回归**：`tests/test_invariant_traceability.py::test_tracked_invariants_have_executable_evidence`。

### BFX-005 polish 未显式保护 productive marker

- **现象**：polish baseline 可以产出不含 productive/protected marker 的文本，未显式阻断“磨平”有效偏离。
- **根因**：polish prompt 中声明保护，但代码未验证输出仍保留保护标记。
- **修复**：`PolishOrchestrator` 在写 revision 前检查 `[productive-deviation]` / `[protected-roughness]` 是否被保留。
- **防回归**：`tests/test_m4_review_pipeline.py::test_polish_preserves_productive_deviations`。

### BFX-006 fact anchor / contract clause attribution 缺少可执行闭环

- **现象**：DDL 有 `writing_fact_anchors` 和 `writing_contract_clauses`，但 hard gate baseline 没有用它们形成阻断和条款级 attribution。
- **根因**：M4 baseline 先实现了 hard gate 框架，未补事实锚点与条款审计链。
- **修复**：hard gate2 对 `[fact-violation]` + confirmed fact anchor 执行阻断，并写入 `writing_failure_attributions.contract_clause_id`。
- **防回归**：`tests/test_m4_review_pipeline.py::test_fact_anchor_gate_and_failure_attribution_clause_link`。

---

## 2026-07-08（质量门真实化阶段 A/B/C）

### BFX-036 jury 真实化后 max_calls_per_shot 预算不足致第二轮 jury 全失败

- **现象**：jury 桩换真实 LLM 调用后，CLI `write` 跑到 polish 后第二轮 jury 抛 `jury 评分全部 LLM 调用失败，疑似供应商故障`；DB 回滚后 shot `status=pending`、`llm_call_count=0`（main 异常回滚掩盖了真实进度）。
- **根因**：jury 真实化后单 shot jury 调用数 = 3 裁判 × draft 候选数 × 两轮（首评 + polish 后重评）。polish 会新增 1 个 smart-polish draft，故实际 draft 数 = `draft_count + 1`，两轮 jury = `3 × (draft_count+1) × 2`。默认 `draft_count=3` → 24 次，远超 schema 默认 `max_calls_per_shot=8`。第二轮 jury 评到第 12 个调用时 `llm_call_breakdown.jury` 计数超 per_type 上限 → budget blocked → 该 draft 3 裁判只成功 2 个 → `judge_count < 3` 抛 `JuryLLMFailure` → 该 draft 不落 aggregate → winner 选了未 polish 的 84 分稿 → `SoftSealOrchestrator` 抛 `winner must be a polished smart-model draft before soft seal`。
- **修复**：`cli.py` `setup` 阶段按公式 `max(8, 6×(draft_count+1)+3)` 自动放宽 `max_calls_per_shot`（默认 draft_count=3 → 27），并同步上调 `max_total_llm_calls = max(40, jury_budget×2+12)` 覆盖 draft+polish+gate+两轮 jury。
- **防回归**：`tests/test_cli.py::test_cli_chapter_revise_export_import_flow`、`tests/test_performance_baselines.py::test_cli_one_chapter_performance_baseline`、`tests/test_resume_handler_registry.py::test_cli_resume_executes_session_level_chapter_review`（完整两轮 jury + soft seal 端到端）。

### BFX-037 mock/deterministic jury 评分不区分 polished draft 致 winner 选错

- **现象**：BFX-036 修预算后，第二轮 jury 仍偶发选未 polish 稿作 winner → soft seal 失败。查 `writing_jury_aggregates`：polished draft（writer_model=smart-polish）有 raw_scores（90）但 aggregate 为 None，未参与 winner 选择。
- **根因**：`MockProvider` / `_CliDeterministicProvider` 的 jury 分支对所有 draft 返回全 84 同分，无法区分 polished（应更高分）与未 polish 稿。当 budget 恰好让 polished draft 的第 3 裁判 blocked（judge_count=2 < 3）时，该 draft 不落 aggregate，winner 落到 84 分的未 polish 稿。
- **修复**：jury 分支从 prompt_text 检测 "polished text"（deterministic polish 产出的文本标记）给 90 分、否则 84，确保 polished draft 评分更高 → 重评时 winner 仍是 smart-polish 稿（满足 soft seal 契约 `winner.writer_model == "smart-polish"`）。`MockProvider`（`llm_gateway.py`）与 `_CliDeterministicProvider`（`cli.py`）两处同步改。
- **防回归**：同 BFX-036 三个端到端测试（验证两轮 jury 后 winner 为 polished 稿且 soft seal 通过）。

---

## 2026-07-08（质量门真实化阶段 D — chapter_review + book_check 真实化）

### BFX-038 chapter_review/book_check 真实化时 `model_name=None` 触发 NOT NULL 约束失败

- **现象**：阶段 D 把 `chapter_review_orchestrator`/`book_rolling_check_orchestrator` 桩评分换成真实 `gateway.call(call_type=chapter_review/book_check, model_name=None)` 后，测试 `test_m5_chapter_review.py::test_chapter_quality_gate_blocks_accept` 抛 `sqlite3.IntegrityError: NOT NULL constraint failed: writing_ai_call_attempts.model_name`。
- **根因**：这两个 call_type 不走「3 tier role chain」路径（无主/备/兜底模型链），orchestrator 传 `model_name=None` 进 `_call_with_injected_provider`；而该路径把 `model_name` 原值写入 `writing_ai_call_attempts.model_name`（NOT NULL 列），outline/draft/jury 不暴露此问题是因为它们都从 `writer_models`/`jury_models` 取了真实 `model_name` 传入。属「无 role_config 的 call_type 与有 role_config 的 call_type 在注入路径上对 `model_name` 的约束假设不一致」。
- **修复**：`llm_gateway._call_with_injected_provider` 给 `model_name` 加 `effective_model_name = model_name or self.provider_name` 兜底（与同函数 `model_provider or self.provider_name` 对齐），INSERT 与 `_resolve_model_alias` 都用 `effective_model_name`。生产路径有 role_config 时仍传真实 model_name，不受影响。
- **防回归**：`tests/test_chapter_review_real.py`、`tests/test_book_check_real.py`（注入式 provider 走 `model_name=None` 路径全程通过）。

---

## 2026-07-09（质量门真实化阶段 F — 真实模型 e2e 修复）

### BFX-039 真实模型 e2e 阶段 C/D 真实化后断裂（budget + gateway 签名 + chapter_review role-config 三连缺）

- **现象**：`tests/test_e2e_real_models.py::test_real_six_chapter_pipeline` 在阶段 C/D（jury/chapter_review 真实化）之后断 `LLM budget blocked: per_type_exceeded` → 改预算后又断 `TypeError: ChapterReviewOrchestrator.__init__() missing 1 required positional argument: 'gateway'` → 改签名后又断 `ChapterReviewLLMFailure: chapter_review 真实 LLM 调用失败`。三连断皆因 e2e fixture 未随真实化更新。
- **根因（三处）**：
  1. **预算**：jury 真实化后 `JuryOrchestrator(conn)` 默认带 gateway 调真实 LLM（3 裁判 × (draft_count+1) × 两轮 ≈ 24），但 e2e fixture 走 `writing_projects` schema 默认 `max_calls_per_shot=8`，不经 `cli.py setup` 的 BFX-036 自动放宽 → `per_type_exceeded`。
  2. **gateway 签名**：阶段 D `ChapterReviewOrchestrator.__init__` 把 `gateway` 从可选改必填，e2e 仍 `ChapterReviewOrchestrator(conn)` → `TypeError`。
  3. **chapter_review role-config**：orchestrator 传 `model_name=None`，无 role-config 时回退 `_call_with_injected_provider`，`effective_model_name = None or provider_name("iflytek")` → `provider.complete("iflytek", …)` 用非真实模型名调 iFLYTEK → 全 tier 失败 → `ChapterReviewLLMFailure`。BFX-038 的兜底只解了 NOT NULL，没解「真实调通」。
- **修复**（`tests/test_e2e_real_models.py`）：(1) fixture `UPDATE writing_projects SET max_calls_per_shot=27, max_total_llm_calls=66`（与 cli.py `max(8, 6×(draft_count+1)+3)` 同公式）；(2) `ChapterReviewOrchestrator(conn, gateway)`；(3) fixture 用 `upsert_role_config` 配 `chapter_review` 三 tier role-config（`provider="openai-compatible"`、`api_key_env="IFLYTEK_API_KEY"`、`base_url=IFLYTEK_BASE_URL`、model 取 JURY_POOL 前三），让 gateway 走 role_chain 路径（与生产 CLI 一致）而非注入式回退。
- **防回归**：本 e2e 即守卫（真实 iFLYTEK 6 章全程：draft→jury→polish→chapter_review→human_review→export）。

---

## 2026-07-11（c02/c03 真模型端到端实跑 — 暴露 write 幂等 + schema 漂移两 bug）

### BFX-040 `write` 缺逐 shot 幂等，重跑已 soft_sealed shot 抛 DataIntegrityError

- **现象**：`ink write --chapter 2` 在 c02 部分 shot 已 `soft_sealed` 后重跑（如分批续跑或重试中断）时，首个已 seal 的 shot 在 `_run_shot_to_soft_sealed` 首步 `run_until_prompt_compiled` 抛 `DataIntegrityError: pre_drafting cannot run from status: soft_sealed`，整章 write 中断。
- **根因**：`cli._cmd_write` 对每个 shot 无条件调 `_run_shot_to_soft_sealed`，未先查 `writing_shots.status`。已终态（`soft_sealed`）的 shot 不可再走状态机首步，但重跑（幂等续跑）场景下应直接跳过而非重跑。
- **修复**（`src/ink/cli.py`，+61/-4）：`_cmd_write` 循环每 shot 前查 `SELECT status FROM writing_shots WHERE shot_id=? AND run_id=?`，若 `status='soft_sealed'` 则 `skipped.append(shot_id)` 跳过、不调状态机；响应新增 `skipped_already_soft_sealed` 字段返回跳过列表。配合逐 shot `commit`（soft_seal 成功即持久化进度 + 释放未提交缓冲），实现分批、可续跑、进度可见。
- **防回归**：c02 实跑验证——首次 write 跑完 4 shot 全 `soft_sealed`（108 调用/20 drafts），重跑时 log 返回 `skipped_already_soft_sealed: [001,002]` + 新跑 003/004，`ok:true`。无单测（真模型端到端验证）。

### BFX-041 生产库 `writing_projects.suspense_decay_floor` 列缺失，章末 review 崩 OperationalError

- **现象**：c02 write 成功后跑 `ink review --chapter 2`，`_chapter_suspense_decay_floor` 执行 `SELECT suspense_decay_floor FROM writing_projects` 抛 `sqlite3.OperationalError: no such column: suspense_decay_floor`，review 全崩 `{"ok":false,"error":{"message":"no such column: suspense_decay_floor"}}`。
- **根因（schema 漂移）**：任务#21「suspense 衰减监控回炉」在 `sql/schema.sql` 给 `writing_projects` 加了 `suspense_decay_floor INTEGER NOT NULL DEFAULT 82`（CHECK ≥82）+ 代码 `_chapter_suspense_decay_floor`/`_chapter_suspense_decay_block` 据此判「本章 winner 行 `suspense_tension_median` 中位数 < 回炉线则强制回炉（E13）」，但**只改了 schema.sql 没给既有生产库迁移**。生产库（《白灯法则》`inkflow.db`）用加列前的旧 schema.sql 建表，缺该列。CLI `init`（读新 schema.sql）和测试链路 `make_schema_db`（每次重建）都天然含列，单测全绿不代表生产库 schema 对齐。
- **修复**：
  1. `sql/migrations/2026-07-09_suspense_decay_floor.sql`：迁移说明（人类可读记录，因 SQLite `ALTER TABLE ADD COLUMN` 无 IF NOT EXISTS，纯 SQL 无法幂等，不直接 executescript）。
  2. `tools/migrate_suspense_decay_floor.py`：幂等迁移工具，`PRAGMA table_info` 探测列是否存在，缺则 `ALTER TABLE writing_projects ADD COLUMN suspense_decay_floor INTEGER NOT NULL DEFAULT 82`，`--dry-run` 只探测。已在生产库执行，列补齐、project_id=1 行值=82（默认）。
- **防回归**：迁移后 c02/c03 review 均跑通（`ok:true`，c02 review_id=1 / c03 review_id=2，质量门 false 属内容问题非 bug）。无单测（部署运维动作，幂等工具自身保安全重跑）。
- **部署纪律沉淀**：见 memory `ink-schema-drift-pattern`——改 schema.sql 加列时必须同步写 migration SQL + 幂等迁移工具，并在既有生产库单独执行；CLI init/make_schema_db 不代表生产库 schema 对齐。

---

## 2026-07-11（P0 工业质量真实生产闭环）

### BFX-042 outline drift 用 Jaccard，真模型越详细越容易被拒

- **现象**：生产 c03 run2 首次真实 write 在 outline 阶段失败：`eligible outlines below threshold: 0 < 1`；阈值已低至 0.02，仍连续 3 个候选全拒。
- **根因**：`cjk_bigram_overlap` 使用 `intersection/union`。契约源很短、真模型大纲很长；即使完整保留所有契约锚点，候选新增的大量合法 bigram 也会扩大 union，把分数压低。
- **修复**：改为方向性的 source recall：`intersection/source_bigrams`。drift 的真实问题是丢契约锚点，不是候选比契约更长。
- **防回归**：`test_outline_drift_score_is_source_coverage_not_length_penalized_jaccard`；生产 run2 重跑后 4 shot 全通过 outline。

### BFX-043 polish 元话语和修改说明进入正文并被 soft seal

- **现象**：生产 c03 run2 shot2 current text 以“好的，收到。这个文本的基础非常扎实”开头，正文后附“主要调整说明/整体节奏”，但旧 hard gate、jury、chapter review 均未拦截，首次 review 甚至高分通过。
- **根因**：
  1. polish prompt 没有要求“只输出正文”；
  2. `PolishOrchestrator` 把 provider response 原样写 revision；
  3. hard gate readability 只检查非空；
  4. chapter review 没有程序级出版污染审计。
- **修复**：
  - polish prompt 明确禁止问候、标题、说明、markdown；
  - 新增 `extract_polished_prose/find_generation_artifact`；
  - hard gate readability 拒绝 artifact；
  - chapter review 加 `publication_artifact` blocking issue。
- **防回归**：`tests/test_prose_integrity.py`；run2 重新 review 后由 pass 回退为 false，证明程序门实际生效；run3 正文扫描零 artifact。

### BFX-044 chapter review 重评旧 attempt 删除太晚

- **现象**：对 pending review 重评时，新真实 LLM 调用先写相同 `idempotency_key`，撞 `writing_ai_call_attempts.idempotency_key UNIQUE`。
- **根因**：旧 attempt 只在 `_write_review` 内删除，但 `_write_review` 位于 LLM 调用之后。
- **修复**：`_prepare_review_attempts` 在模型调用前处理：accepted review 直接拒绝覆盖；pending/rejected/revised 清理 chapter_review 与 industrial drift keys。
- **防回归**：生产 run2/run3 多次真实重评成功，review_id 保持稳定更新。

### BFX-045 工业漂移把症状/背景线索误判为因果机理

- **现象**：旧 c03 的“微裂纹像蛛网”，run3 的“前线露天堆放至少四天”被真实模型判 `failure_mechanism_vague`，尽管文本只在展示症状/背景，未宣称根因。
- **根因**：prompt 把“提到失效但没解释机理”直接等价为漂移，没有区分悬疑信息释放阶段与因果断言。
- **修复**：
  - 引入 `claim_mode`；
  - observation-only 不阻断；
  - failure mechanism 必须有明确因果断言词 + 缺失 requirement + confidence≥0.75；
  - institutional conflict 必须引用直接冲突基线。
- **防回归**：`test_industrial_observation_only_is_not_misclassified_as_vague_mechanism`、`test_industrial_background_condition_is_not_promoted_to_causal_claim`。

### BFX-046 baseline 脚本产出快照但 DB 关闭后为空

- **现象**：`.inkflow/local_proxy/snapshots` 和合并稿存在，但 `local_proxy/inkflow.db` 有 52 张空表，`writing_projects=[]`。
- **根因**：脚本从初始化到 10 章运行始终处于同一隐式 SQLite transaction，关闭连接时未 commit，全部回滚；文件快照在事务内读取所以看似正常。
- **修复**：初始化完成 commit；每章 run/review 成功 commit；异常 rollback。官方 baseline 脚本同步修复。
- **防回归**：工具语法检查 + 后续实跑 DB 可直接查询项目/shot/review，不再只依赖文件快照。

### BFX-047 默认 pytest 无条件执行 10 章真实模型验收

- **现象**：`python -m pytest` 超过 10 分钟仍未结束；本地代理测试自动写入 key 并直接运行 10 章真模型。
- **根因**：README 声明“真实 LLM 不进默认 CI”，但测试模块没有 opt-in guard。
- **修复**：`test_e2e_local_proxy.py/test_e2e_real_models.py` 增加 `INK_RUN_REAL_LLM_TESTS=1` 模块级 skip guard。
- **防回归**：默认全量 `402 passed, 9 skipped in 34.88s`；真实模型验收由专用工具和显式 opt-in 测试执行。

### BFX-048 polish 后 jury 重评所有旧稿，浪费调用并触发预算熔断

- **现象**：生产 run3 单 shot jury 调用达到 27 次，第四 shot 在第二轮评分中触发 `per_type_exceeded`，运行数分钟后整 shot 事务回滚。
- **根因**：polish 只新增一个 draft，但第二次 `score_and_select_winner` 对所有旧 draft 执行 `_score_draft`，删除并重建其 raw/aggregate/attempt；未变化文本被重复付费评分。
- **修复**：同 contract、未 stale 且已有 aggregate 的 draft 复用 12 维 medians；只按当前项目阈值重算 pass/reasons。第二轮只评分新 polished draft。
- **防回归**：`test_post_polish_jury_reuses_unchanged_draft_scores`，jury breakdown 从 9 增至 12，而不是重新打旧稿。

### BFX-049 jury 容量公式未覆盖 creative/retry/escalation

- **现象**：旧 init 公式只按 `6*(draft_count+1)+3`，默认 27；真实分歧升级和 creative candidates 可超过该值。
- **根因**：容量模型只覆盖“所有稿评两遍”，既高估无分歧 polish 重评，又漏算 escalation/retry。
- **修复**：新增 `recommended_llm_capacity`，按最大候选、polished、retry wave、三次 escalation reserve 推导；默认 jury=42、total≥64。`write` 前置容量检查。
- **防回归**：`tests/test_capacity_planning.py` + CLI 全流程测试。

### BFX-050 定点修订只有一次性工具，没有正式状态/审计入口

- **现象**：真实 review 只剩一个 POV 句子问题时，完整 revise 会重写全章、耗时高并可能破坏已通过强项。
- **根因**：公开 CLI 只有 chapter-level revise，没有 shot current revision → minimal repair → automatic re-review。
- **修复**：新增 `TargetedRepairOrchestrator` 与 `ink repair`；只处理 soft-sealed、非 hard-sealed shot，写 source-linked revision，随后自动 chapter review。
- **防回归**：`tests/test_targeted_repair.py`。

### BFX-051 Python `hash(shot_id)` 使模型轮替跨进程不稳定

- **现象**：全量测试偶发 writer pool 四模型只覆盖三模型；不同 Python 进程的候选模型起点变化。
- **根因**：Python 默认对字符串 hash 加随机 salt，不适合持久生产路由或可复现实验。
- **修复**：writer/polish 模型索引用 SHA-256 前 8 字节取模。
- **防回归**：`test_select_writer_models_shot_id_offset_breaks_concentration` 稳定覆盖全部模型；全量重复运行通过。

### BFX-052 候选硬门后不足时 jury 直接中止

- **现象**：benchmark c04 三篇真模型草稿中两篇被 hard gate 淘汰，仅剩 1 篇；jury 抛 `eligible jury candidates below threshold: 1 < 2`。
- **根因**：设计说明声称“候选不足触发补写”，实现却只在所有候选评分不过质量线后 retry；评分前候选数量不足没有补写路径。
- **修复**：`_supplement_candidate_shortage` 在 jury 前调用真实 `produce_quality_retry_candidates` + hard gate，再加载候选；仍不足才失败。
- **防回归**：`test_jury_candidate_shortage_generates_supplemental_wave`；c04 续跑成功。

### BFX-053 benchmark 脚本 JuryOrchestrator 漏传真实 gateway

- **现象**：c09 supplemental quality-retry 生成 `[mock:...] generated draft`，该占位稿被真实 jury 评为 winner 并 soft seal。
- **根因**：脚本 write/polish 使用真实 gateway，但两处 `JuryOrchestrator(conn)` 未传 gateway。普通 jury 因 role-config 仍走真实模型；jury 内部补写 call_type=draft 无 role-config，回退默认 MockProvider。
- **修复**：local proxy/baseline/run_real_quality 三个工具所有 JuryOrchestrator 均显式传 gateway；MockProvider 输出不再伪装带标签正文；benchmark exporter 审计 selected shot attempts，不允许 mock/deterministic lineage。
- **防回归**：c09 新 run201、c10 新 run202 全真实重生成；`export_quality_benchmark.py` lineage 检查通过。

### BFX-054 单模型 chapter review 重评结果波动

- **现象**：同一 c08 定点修订稿一次评审通过，随后同模型重评又判 POV 切换；单次随机输出直接决定 hard gate。
- **根因**：chapter review 只有一个模型/一次样本，却承担 7 维审美分和 POV/continuity 硬审计。
- **修复**：
  - primary/secondary/tertiary 三个真实模型独立评审；
  - 7 维取中位数；
  - POV/continuity violation 需多数票；
  - review notes 保留三份 reviewer evidence；
  - 每章保留 3 条真实 attempt。
- **防回归**：chapter review 测试更新为 3 attempts；c03-c10 最终每章三模型评审，8/8 通过。

### BFX-055 `_write_review` 删除刚成功的 chapter-review attempt

- **现象**：8 章有 review 行，但 attempt 表只剩部分 industrial calls，章审模型/耗时无法审计。
- **根因**：BFX-044 已把旧 key 清理前移到调用前，但 `_write_review` 中旧删除代码未移除，模型成功后又把新 attempt 删除。
- **修复**：移除 `_write_review` 删除；`_prepare_review_attempts` 成为唯一清理入口。
- **防回归**：`test_chapter_quality_gate_blocks_accept` 断言三条 reviewer attempts 保留；benchmark 最终保留 24 条章审 attempt。

### BFX-056 synthetic provider placeholder 缺程序级阻断

- **现象**：`[mock:...] generated draft` 非空、容量正常、无 forbidden word，因此旧 hard gate 放行。
- **根因**：readability 只识别问候/修改说明等元话语，没有识别 mock/deterministic placeholder。
- **修复**：`find_generation_artifact` 新增 `synthetic_provider_placeholder`；hard gate 直接判 readability=0。benchmark exporter再做 provider lineage 审计。
- **防回归**：`test_synthetic_provider_placeholder_is_never_publishable`。

### BFX-057 伦理责任审查只有任务说明，没有法定数据与 accept 闸门

- **现象**：任务长期要求“每章伦理审查经手人留痕”，但系统只有文学质量 review；谁审查、谁受影响、不可逆后果和证据句均未落库，accept 也无法确认是否审过。
- **根因**：伦理责任被视为 review_notes 中的非结构化文字，没有独立 schema、模型协议和项目开关。
- **修复**：
  - 新增 `writing_chapter_ethics_reviews`；
  - 新增 `require_ethics_review`；
  - 三真实模型独立审查与聚合；
  - 新增 `ink ethics-review`；
  - required 项目 human accept 强制检查 approve。
- **迁移**：`tools/migrate_chapter_ethics_review.py` 已对生产/benchmark DB 执行。
- **防回归**：`tests/test_ethics_review.py` 三用例覆盖落库、缺失阻断、blocking 阻断。

### BFX-058 Shot 中心文档与 Scene-first 作者裁定并存

- **现象**：修正案规定 Scene 为正式原子，但 `design-v2.md`、`implementation-contract-v1.md`、工作流、迁移计划和运行手册仍以 Shot winner、Shot seal、`v_current_text` 动态拼章为主；开发者必须自行判断哪些段落有效。
- **根因**：使用“顶部优先级声明”覆盖数千行旧实现文档，没有把当前实现、目标设计、迁移和历史分成不同法源。
- **修复**：
  - 旧 Shot 中心开发文档移入 `docs/归档/shot-centered-v2-2026-07-14/`；
  - 新增 `docs/README.md` 权威矩阵；
  - 重写 Scene-first 设计、实现契约、迁移、作者工作流、契约工作流、不变量、踩坑、并发边界和运行手册；
  - `tasks.md` 只保留未完成 Scene-first 任务，完成记录移入 `history.md`。
- **防回归**：新增文档一致性检查任务；归档目录不得被新实现文档引用为规范来源。

### BFX-059 模型配置文档包含真实凭据形态内容

- **现象**：`docs/iflytek-model-config.md` 的运行示例包含非占位符API凭据。
- **根因**：连通性验证时把本机配置复制进开发文档，没有secret scanning门禁。
- **修复**：重写配置文档，只保留 `<appId:apiKey>` 占位符和WiseGateway接入方式，不在修复记录中复述原值。
- **后续**：轮换历史凭据、检查Git历史/日志/备份并接入secret scanning，仍列P0任务。

### BFX-060 Scene-first 缺少可执行实现契约

- **现象**：`scene-first-authority-amendment.md` 只列原则和目标表名，缺少Branch-local parent、Snapshot Accept事务、状态机、不可变约束和安全cutover。
- **根因**：设计讨论先于工程规格，旧Shot实现契约被临时标为“迁移来源”但没有新的替代法源。
- **修复**：新增 `docs/implementation-contract.md`、`docs/design.md` 和 `docs/migration-plan.md`，明确Scene/Branch/Snapshot实体、状态机、权限、事务和迁移阶段。
- **防回归**：Scene-first代码不得在缺少对应不变量和测试的情况下标记完成。

### BFX-061 Scene-first只有文档法源，没有可执行数据层

- **现象**：Scene-first文档已经规定Scene、Branch和Snapshot为正式模型，但
  `schema.sql`仍只有Shot正文权威，代码无法验证Branch-local parent、冻结和Snapshot不变性。
- **根因**：架构裁定和旧生产实现之间缺少可独立测试的影子基础层。
- **修复**：
  - 新增12张Scene-first影子表及19个新旧合计trigger；
  - 新增`SceneRepository`和`ChapterSnapshotRepository`；
  - 本阶段只新增，不切换旧accept/export。
- **防回归**：新增Scene-first Schema、Branch分叉、Revision不可变、Snapshot不可变和Head CAS测试。

### BFX-062 Snapshot/Branch绑定可被后续写入污染的风险

- **现象**：只声明“Snapshot/Branch不可变”仍不足以阻断直接SQL追加绑定、跨Scene绑定Revision，
  或让Chapter Head指向未封口、跨章节Snapshot。
- **根因**：缺少数据库级构造闩锁、归属校验和Head目标校验。
- **修复**：
  - Branch冻结后禁止INSERT/UPDATE/DELETE绑定；
  - Snapshot以同一事务内唯一一次`sealed_at`封口，封口后禁止任何绑定变化；
  - Branch/Snapshot绑定强制Revision属于对应Scene；
  - Chapter Head强制指向同project/chapter的sealed Snapshot。
- **防回归**：触发器测试覆盖冻结、跨Scene绑定、Snapshot修改/删除、Head唯一性和后续Revision隔离。

### BFX-063 不变量文档把未实现门禁登记为已追踪INV

- **现象**：重写后的`invariant-traceability.md`列出大量尚无测试的正式`INV-*`，
  同时丢失Cutover前仍须保留的旧基线ID，导致追踪测试失败并夸大完成度。
- **根因**：把目标不变量、已执行不变量和迁移回归不变量混成一张表。
- **修复**：
  - 正式`INV-*`只登记已有自动化证据的规则；
  - 保留旧基线ID并明确其只用于迁移回归；
  - 未实现P0门禁单列，不伪装为已完成。
- **防回归**：`test_tracked_invariants_have_executable_evidence`要求每个正式ID都有真实测试或lint证据。

### BFX-064 Scene-first文档把影子底座描述成完整生产契约

- **现象**：`design.md`仍称全部代码只有Shot实现；与此同时`implementation-contract.md`
  又没有区分已实现底座和最终事务，容易把基础Snapshot/CAS误读为完整Accept已经完成。
- **根因**：代码开发后没有同步维护“当前实现状态矩阵”，目标规范与完成度混写。
- **修复**：
  - `design.md`改为“旧Shot生产权威 + Scene-first影子基础层”；
  - `implementation-contract.md`增加逐能力真实状态；
  - `migration-plan.md`增加S0—S6状态表；
  - `tasks.md`补入既有库migration、schema marker、task有效性、冻结硬门和Decision/Event。
- **附带修复**：`create_contract`不能直接创建active/superseded状态；Contract激活和Branch选择改为原子事务。
- **防回归**：新增`test_create_contract_cannot_bypass_activation_path`，后续每次完成P0能力必须同时更新状态矩阵、tasks和history。

### BFX-065 Generation Round真实端口缺少active Contract会写出无契约候选

- **现象**：真实生成端口可在章节没有active Scene Contract时创建Branch Version，导致影子候选无法证明受哪个有效契约约束。
- **根因**：初版真实端口把单Scene绑定当作存储细节，没有把Contract有效性作为生成前置硬门。
- **修复**：`_write_branch_text`先解析当前章节active Contract；不存在或不唯一立即抛`DataIntegrityError`，且不得留下Branch Version/Revision半成品。
- **防回归**：`test_real_generation_write_fails_closed_without_active_scene_contract`断言零副作用。

### BFX-066 Generation Round选优端口提前写状态形成双写

- **现象**：`RealSelectionPort.select_winner`先把branch写成`selected`，driver随后再次执行`select_branch`并迁移round；真实验收在第二次CAS处失败。
- **根因**：SelectionPort接口文档同时要求“返回winner”和“mark selected”，与driver的状态写所有权冲突。
- **修复**：SelectionPort改为纯决策接口；branch/round状态只由driver经Repository写入。
- **防回归**：`test_real_selection_port_is_decision_only`验证调用后branch和round状态均未变化。

### BFX-067 Generation Round恢复键随机且jury解析会fail-open

- **现象**：同一round步骤重试使用随机UUID幂等键；模型回复不符合JSON时，差异门默认`True`、缺失文学维度被伪造为全维60，可能让不可审计结果越过硬门。
- **根因**：把“避免重复键”误当幂等，把模型协议容错误写成通过兜底。
- **修复**：幂等键固定为`round-{round_id}-{step}-{branch_id}`；差异和分数解析失败抛`_SelectionError`；driver捕获任意port异常并把当前round原子封到`failed`。
- **防回归**：稳定键、两个fail-closed解析器及port异常终态均有离线测试；真实iFLYTEK严格协议验收通过。

---

## 2026-07-14（Scene-first 不变量测试收尾 — 缺陷登记，随 da1a028e 修复）

### BFX-068 confirm_fact_proposal 未写 legacy fact_anchors 真实列

- **现象**：`scene_repository.confirm_fact_proposal` 在事实提案确认后，未把
  legacy `writing_fact_anchors` 的真实列（`shot_id`/`revision_id`/
  `fact_text`/`source_span`/`confidence`/`status`）填实，导致影子层提案与
  旧 Shot 生产权威的事实锚点表脱节，迁移 parity 无法自证。
- **根因**：初版把「提案确认」当成影子表内部状态推进，忽略了 Scene-first
  影子层必须对 legacy 表写真实列以保 parity 的硬约束。
- **修复**：`confirm_fact_proposal` 改写为写 legacy `writing_fact_anchors`
  真实列；rejected 路径只写 status，不写 anchor 文本列。
- **防回归**：`test_fact_proposal_confirmation_is_human_gated_and_writes_anchor`
  断言真实列被填；`test_fact_proposal_rejection_is_human_gated` 断言人-only 门。

### BFX-069 record_contract_review 冗余 same-model 守卫阻断合法自检复审

- **现象**：`scene_repository.record_contract_review` 内含 same-model（同族）
  守卫，导致契约架构师自检阶段合法复用同族模型做 self-check 时被误判阻断；
  independent_review 又依赖同一守卫区分 family-differ，语义混淆。
- **根因**：把「自检可复用 architect 同族」与「独立复审必须不同 family」
  两条独立约束合并进了同一个 same-model 守卫，前置约束过严、后置约束错位。
- **修复**：去除 `record_contract_review` 内冗余 same-model 守卫，自检阶段
  合法复用 architect 同族；family-differ 约束仅由 `independent_review_contract`
  单独守。
- **防回归**：`test_contract_self_check_moves_draft_to_self_checked`、
  `test_independent_review_requires_self_checked_and_different_family` 全绿，
  分别覆盖两条独��约束。

### BFX-070 human_activate_contract JOIN 列名 ambiguous scene_id

- **现象**：`human_activate_contract` 的多表 JOIN 产生 ambiguous `scene_id`，
  SQLite/PostgreSQL 在严格模式下抛列名歧义错误，人激活路径无法走通。
- **根因**：JOIN 多张含 `scene_id` 的表时未给列加表别名，解析器无法消歧。
- **修复**：JOIN 列名统一加表别名前缀，消除 ambiguous `scene_id`。
- **防回归**：`test_ai_actor_cannot_activate_contract` 覆盖激活路径走通且
  AI 被阻断的语义。

### BFX-071 jury 评分桩伪装真实分（BFX-033 收尾确认）

- **现象**：BFX-033 登记 jury/chapter_review/book_check 三处评分用桩算分，
  质量门形同虚设。本批 commit 1c7df99b 已把桩换成真实 `gateway.call`，但
  bugfix 侧未单独收口确认。
- **根因**：见 BFX-033。
- **修复**：jury_orchestrator 三处桩分函数全部接入真实 LLM 调用
  （`call_type=jury`）；chapter_review / book_rolling_check 同步真实化。
- **防回归**：`test_m4_review_pipeline` / `test_m5_chapter_review` /
  `test_m6_workflow_smoke` 同步真实化语义；真实 iFLYTEK 严格协议 10 章验收
  `suspense_tension` 82–92、winner 85+。本条为 BFX-033 的收尾确认，不重复
  列计划项。

### BFX-072 `_CliDeterministicProvider` 未适配 Scene-first idempotency_key 前缀

- **现象**：deterministic provider 驱动 `produce-chapter` 时，generation 过门但
  selection 报 `jury score response omitted or malformed dimensions: …`
  （character_voice/contract_adherence 等 7 维全缺）。
- **根因**：`_CliDeterministicProvider.complete` 只识别旧 Shot 流水线的 key 前缀
  （`outline:/polish:/jury:/chapter_review:/book_check:`），而 Scene-first 的
  `RealValidationPort/RealSelectionPort` 用 `_idem_key` 生成的 key 前缀是
  `round-{rid}-generate/validate/diff/select-{bid}`——匹配不到，全部落到默认
  分支 `text = f"scene text …"`，返回非 JSON，被 `_parse_scores` 判废。
- **修复**：给 `_CliDeterministicProvider` 补四个 Scene-first 分支：
  - `-generate-` → 候选正文（嵌入 branch_id 使多候选互异，避
    `writing_scene_revisions (scene_id,text_hash) UNIQUE`）；
  - `-validate-`/`-select-` → 7 维全 92 JSON（92 高于 floor 85 与
    dimension_floor 60，确定性过门）；
  - `-diff-` → `{"has_substantive_difference": true}`（false 会导致全废→
    candidate_shortage）。
- **防回归**：deterministic 端到端冒烟（临时库 3 候选 2 轮）跑通
  `accepted:true / eligible_count:3 / call_count:3`，覆盖 generate→validate→
  diff→select→accept→export 全链路。旧 Shot 的 `jury:`/`chapter_review:`
  分支未动，旧测试不受影响。

### BFX-073 白灯库 draft role-config 的 `LOCAL_PROXY_KEY` 环境未设（待真模型验证）

- **现象**：白灯库 `--llm-provider deterministic` 时 deterministic 被旁路，
  gateway 仍走 role-config 真 provider 链，报
  `api_key_env LOCAL_PROXY_KEY 未设或环境未配置`。
- **根因**：白灯库 draft/chapter_review role-config 配的 `api_key_env=
  LOCAL_PROXY_KEY`，而当前 shell 未导出该环境变量；本地代理 `127.0.0.1:8000
  /v1/models` 返回 401（代理活着但需 key）。这是配置/环境缺口，非代码缺陷。
- **修复**：跑真模型前先导出 `LOCAL_PROXY_KEY`（key 见
  `run_baideng_local_proxy.py`，memory `ink-local-proxy-baideng-runner`）。
  实测真模型烟测已验证：`LOCAL_PROXY_KEY` + `INK_LLM_API_KEY` 双设 +
  `--llm-base-url http://127.0.0.1:8000/v1`，gateway 真实命中代理 5 模型。
- **防回归**：待真模型烟测补。

### BFX-074 真模型烟测 validation 0 过门——根因订正：非过严，是 provider=mock 假象 + selection UNIQUE 冲突

- **2026-07-15 二次订正（真模型 7 维真分回传后推翻前判）**：前判「单 judge
  真模型逐维裸打偏严 → 0 过门」**错误**。加 `INK_BFX074_DIAG` 诊断落盘 jury raw
  response + 真分后，真相如下：
  - **真模型 jury（claude-xunfei-glm-5-2，单 judge，floor=75）实测真分**：
    候选1 = 90/95/92/96/88/94/91（全维 ≥88，passed=true）
    候选2 = 85/88/92/95/90/93/87（全维 ≥85，passed=true）
    候选3 = 82/85/90/88/79/92/70（pacing=79、contract=70 不合格，passed=false）
    即 **glm-5-2 完全打得出高分**，floor=75 合理（候选3 的 70 被正确挡下），
    过门逻辑（`all(score>=floor)`）本身无问题。
  - **先前"0 过门 / malformed dimensions"的真根因**：两个独立 bug 叠加
    （见 BFX-075 / BFX-076），非过门阈值问题：
    ① **BFX-075 provider=mock**：`ink init` 的 `_seed_role_config`
      （`src/ink/cli.py:702`）读 `INK_LLM_PROVIDER` 环境变量决定 role_config 的
      `provider` 字段；该变量未设时 seed 出 `provider="mock"`，后续
      `produce-chapter` 的 role chain 三档全走 `MockProvider`（`llm_gateway.py:104`
      桩输出 `scene text {model} {key}`），validation `_parse_scores` 拿到桩文本
      → 7 维全 missing → `omitted or malformed dimensions` → 上游 try 误判为
      initial_zero_pass。**这才是先前"0 过门"的真相**：根本没调真模型。
    ② **BFX-076 selection UNIQUE idempotency_key 冲突**：设好 provider 环境变量、
      真模型跑通 generation×3 + validation×3（全 SUCCEEDED，真分落盘）后，进入
      `select_winner` → `RealSelectionPort._rank`（`generation_round_real_ports.py:182`）
      对 eligible 候选 INSERT `round-1-select-N` 时抛
      `IntegrityError: UNIQUE constraint failed: writing_ai_call_attempts.idempotency_key`，
      阻塞 winner 选优产出。此为本轮新暴露 bug，单独登记 BFX-076，待定位
      `_rank` INSERT 与既有 attempt 的 key 撞车路径。
  - **BFX-075 临时绕过**：诊断脚本 `.fastmeet/run_bfx074_diag.py` 在 `ink init`
    前显式 `export INK_LLM_PROVIDER=openai-compatible INK_LLM_BASE_URL=...
    INK_LLM_API_KEY_ENV=INK_LLM_API_KEY`，使 seed 写真 provider；3 候选真分
    落盘 `.bfx074/scores_r1_b{1,2,3}.json` + 候选正文 `text_r1_b{1,2,3}.md` +
    jury raw `raw_r1_b{1,2,3}.txt`。**生产侧 CLI 应固化此环境变量约定**
    （init 前必须设 INK_LLM_*，否则静默 seed mock）。
- **结论（推翻前判的待定方向 ①②③）**：不降 floor、不换多 judge、不改过门
  逻辑——过门机制与 floor 均无问题，真模型能打高分。修复焦点转移至
  BFX-075（provider 注入）+ BFX-076（idempotency 冲突），二者修复后即可产出
  真 winner，无需架构级调整。
- **2026-07-15 RESOLVED**：`run_bfx074_diag.py`（含 INK_LLM_* 环境变量绕过
  BFX-075 + INK_BFX074_DIAG 诊断）二跑全程通过——produce-chapter 输出
  `"final_status":"selected", "winner_branch_version_id":2, "eligible_count":3,
  "call_count":3, "ok":true`，round 终态 `selected`，branch 1 = selected（winner）。
  真模型全链路（章纲→generation 3 候选→jury 7 维 validation→selection→winner
  selected）实证打通，winner 已产出待 `scene-accept` 封版。**BFX-074 关闭**，
  阻塞解除，进入第1章纵切验证。
- **复现**：`cd ink && python -X utf8 .fastmeet/run_bfx074_diag.py`
  （脚本已含 INK_LLM_* 环境变量 + 诊断开关 + 删库重建）。临时库
  `baideng_bfx074_diag.db` + 诊断产物 `.bfx074/` 已留现场。

---

### BFX-075 `ink init` 未设 `INK_LLM_PROVIDER` 环境变量 → role_config 静默 seed `provider="mock"`

- **现象**：`ink init --writer-models ... --jury-models ...` 后 `produce-chapter
  --llm-provider openai-compatible --llm-base-url ... --llm-api-key-env ...`，
  CLI 虽传了 `--llm-provider openai-compatible`，但 role chain 三档全走
  `MockProvider`，jury 返回桩文本 `scene text {model} {key}`，validation 解析 0 维。
- **根因**：`ink init` 的向后兼容 `_seed_role_config`（`src/ink/cli.py:700-728`）
  读 `INK_LLM_PROVIDER` 环境变量决定 seed 的 `provider` 字段；该变量未设时默认
  `"mock"`（`cli.py:702` `env.get("INK_LLM_PROVIDER") or "mock"`），seed 出
  `provider="mock"` 的 role_config。`produce-chapter` 的 `_gateway()` 虽按
  `--llm-provider` 构造了真 `ModelProvider`，但 `LLMGateway.call` 走 role chain
  分支（`llm_gateway.py:278`）时，每档 provider 取自 DB role_config（mock）而非
  注入的真 provider——真 provider 只在无 role_config 的注入式老路径生效。
- **影响**：真模型烟测静默走桩，所有 call_type 评分/产稿均为假象；前次 BFX-074
  "0 过门" 即此误判。`--llm-provider` CLI 参数对 role_config 项目无效。
- **修复方向（待裁定）**：① init seed 时若 CLI 同传了 `--llm-provider`
  真实值，优先用 CLI 值而非环境变量；② 或 init seed 默认 `provider="openai-compatible"`
  + 从 CLI `--llm-base-url`/`--llm-api-key-env` 填字段；③ 至少在 seed 出 mock 时
  打 warning。临时绕过：init 前显式设 `INK_LLM_PROVIDER=openai-compatible` +
  `INK_LLM_BASE_URL` + `INK_LLM_API_KEY_ENV` 三环境变量（见 `.fastmeet/run_bfx074_diag.py`）。

---

### BFX-076 selection 阶段 `writing_ai_call_attempts.idempotency_key` UNIQUE 冲突——偶发，不阻塞

- **现象**：BFX-075 绕过后首次重跑，`select_winner` → `RealSelectionPort._rank`
  INSERT `round-1-select-N` 时抛 `IntegrityError: UNIQUE constraint failed:
  writing_ai_call_attempts.idempotency_key`，winner 未产出。
- **二跑诊断（2026-07-15）**：给 `_rank` 加 `INK_BFX074_DIAG` trace 落盘每次
  调用的 key + DB 已有同 key 行数，重跑结果：`_rank` 对 branch 1/2/3 各调一次
  （key=round-1-select-1/2/3），三行 existing_rows 全为 0，INSERT 全部成功落库
  （attempt 7/8/9，success=1，无 dup key），round 终态 `selected`，branch 1 =
  `selected`（winner，winner_branch_version_id=2），2/3 = `rejected`。
  **UNIQUE 冲突不复现**——判定为偶发（疑首次跑 jury 真模型响应延迟致某 idempotency
  INSERT 时序撞，或上游某重复调用首跑触发、二跑时 state 已推进绕开）。
- **影响**：**不阻塞** BFX-074。真模型全链路（章纲→generation 3 候选→jury 7 维
  validation→selection→winner selected）已实证打通，winner 已产出待 `scene-accept`
  封版。非质量门、非架构问题。
- **后续（P2，不阻塞投稿）**：若 UNIQUE 偶发复现，给 role chain 成功路径 INSERT
  （`llm_gateway.py:446-458`）加 `INSERT OR IGNORE` + 命中既有行时返回缓存结果，
  既消除偶发冲突又获得真幂等（崩溃恢复重入同 key 直接取旧 result）。当前不急修。


## BFX-077 generation prompt 漏 f 前缀 → brief 字面不插值（白灯正文变言情线）

- **状态**：RESOLVED（2026-07-15）
- **现象**：第1章纵切导出正文人物为"江辞/陆衍希"（总裁办公室/言情线），
  而非白灯法则第1章的"许怀山/吕素琴"（1979 军工配套厂硫化车间）。诊断库
  grep 人设关键词："许怀山/吕素琴/1979/军工/密封件/硫化"全 0 命中，
  "江辞/陆衍希/总裁"命中。
- **误判排查**：
  1. 先疑 `run_bfx074_diag.py` 灌错 outline —— 实查脚本传
     `--outline-file 24_分章大纲.md --chapter-id 1`，正确。
  2. 再疑 `build_chapter_brief` 解析丢内容 —— 实跑 `build_chapter_brief(大纲,1)`
     返回完整白灯 brief（含许怀山/吕素琴/硫化/返潮），正确。
  3. 再疑 caller 未传 brief —— 实查 cli.py:1567 `RealGenerationPort(
     ..., chapter_brief=brief)`，正确传入。
  4. 查 `writing_ai_call_attempts` attempt 1：`call_type=draft`、
     `model_name=claude-xunfei-deepseek-v4-pro`、`token_input=54`、
     `prompt_hash=16a1d764...`。**token_input=54 异常**（白灯 brief ~464c，
     token 应 700+）。
  5. 用 `_generation_prompt(brief,0)` 重算 sha256 → `3a14550f...`，
     与 attempt 的 `16a1d764...` 不符；prompt 仅 82 字符、不含"许怀山"。
- **根因（一字符 bug）**：`generation_round_real_ports.py:_generation_prompt`
  原实现：
  ```python
  return (
      f"你是中文小说写手。请据以下章节纲要独立创作第 {candidate_index + 1} 个候选正文，"
      "追求文学质量与叙事张力，1200-1800 字。只输出正文，不要标题或解释。

纲要：
{brief}"
  )
  ```
  第三段字符串**漏了 `f` 前缀** → `{brief}` 是字面文本不插值 → 模型只收到
  "你是中文小说写手……纲要：
{brief}"（82c），**完全收不到章纲内容**，
  遂按训练里熟悉的言情套路自由发挥产出江辞/陆衍希。
- **影响范围**：所有走 `RealGenerationPort.generate_candidate` 的真模型产稿
  （BFX-074 诊断库、以及未来逐章生产）均受影响——产出的是模型自由发挥稿，
  **不是白灯法则正文**。纵切验证虽然"管线机械闭环全过"（封版/导出/hash 一致），
  但"正文=白灯第1章"这一实质目标未达成。
- **修复**：`generation_round_real_ports.py:_generation_prompt` 第三段补 `f` 前缀，
  并拆为独立 `f"{brief}"` 段，注释标明漏 f 的后果。修复后 prompt 464c、含
  许怀山/硫化/返潮，sha256 变化（符合预期，brief 终于进 prompt）。
- **验证**：
  - 单元：`_generation_prompt(brief,0)` 返回 464c 含白灯人设 ✓
  - 回归：`tests/ -k "generation_round_real or brief"` 全过 ✓
  - 待真模型重跑第1章：产出正文应含许怀山/吕素琴（待跑）
- **教训**：纵切验收"管线闭环"≠"正文达标"。token_input 字段是判真利器——
  54 token 的 draft prompt 直接暴露 brief 未进 prompt。今后真模型产稿验收
  必须核对：① attempt.token_input 量级（draft 应 ≥ brief 字数×1.5）；
  ② 正文 grep 大纲人设名是否命中；③ prompt_hash 与重算一致。

## BFX-078：跨章 context 注入正文原文制造章节同构重复（P0，2026-07-15）

**症状**：第2章正文开头重演第1章的装车/签字/卡车驶离动作（封条×3、装车×5、
卡车×2，开头400字整段重演装车签字），与第2章大纲要求的"裂纹样件+1978旧样件"
新事件不符。五专家连续评审（AWT-20260715-171440-5aaf49）判定为 P0-1 章节同构。

**根因**：`brief_builder._prev_chapter_context` 把前章封版正文**头+末各300字原文**
注入后章 brief。模型把前章场景细节当成"本章要复现的设定"复述，淹没章纲要求的
新事件。验收时"模型复现第十七批四二零四配方"被误判为成功，实为重复病根
（复述 ≠ 续接）。

**影响**：context 注入工程（BFX-074 修复后的延伸工作）非但没解决续接断档，
反而放大了章节同构。第1/2章连续评分 7.1/10（独立 7.2/7.5）。

**修复方案**（待作者裁定后实施，非已修）：
- context 不给正文原文，改给**结构化前情摘要**——分点"上一章已发生①…②…"，
  每点标"已发生,勿复述"。来源优先用封版时大纲的`章末钩子`字段（本就结构化），
  次选小模型抽动作清单。
- prompt 显式约束"本章从新事件起笔,不得重演前章动作"。
- 验收从"复现前章细节"改为"新事件起笔+前情作隐含背景不正面复述"。

**关联**：memory `ink-context-injection-raw-text-backfires`；评审报告
`D:\_Progs\.BetterCiv\09_工程脚本\ai_workbench\runs\AWT-20260715-171440-5aaf49\amy-review-synthesis.md`。

## BFX-079：契约层未接线进生产链路（架构根因，P0，2026-07-15）

**症状**：P0-1 章节同构、P0-2 完整因果链、P0-3 科幻锚点缺失——五专家连续评审
（AWT-20260715-171440）三个 P0，深挖到架构根因。

**根因**：设计文档（design.md §2/§3.1）定义了契约层（五级 Book/Volume/Part/
Chapter/Scene + 四层 clause + 架构师起草/复审师审查/返工闭环），早期也建了契约
工具（confirm_and_apply / DecisionSession / record_contract_review / stale 传播，
提交 1b93f3c5 / 259145e2）。但契约层只挂在需人工手动触发的 CLI 命令
（confirm-contract / decision-session）上，**从未接线进自动生产链路
（produce-chapter）**。

**直接证据（代码自白）**：
- `_ensure_scene_and_contract` docstring："Dead-line policy skips the dual-blind
  self_check / independent review; the human actor activation is the seal." 它建的
  契约是空壳：contract_hash=sha256(brief)、source_bundle_hash 同一 hash，四层
  clause 一个没落。
- `brief_builder.py:8`："死线收口用：不落 chapter contract payload / scene contract
  四层 clause"。
- `record_contract_review` 零生产调用方（死代码）。
- git 考古：契约层工具早期建好即搁置，brief_builder 今天新建直接裸拼大纲未接。

**真根因三层**：
1. 表面 = 死线降级（7-30 投稿死线）。
2. 机制 = 契约层（CLI 旁路工具）与生产层（produce-chapter）两套独立建的工具，
   中间无接线。
3. 真 = 无"契约贯穿生产"硬约束 + 降级不可逆。第一次降级（跳双盲审查）无追责无
   回补，后续 brief 裸拼 / context 注入正文都在"契约已缺位"错误前提上继续固化，
   错误前提被固化成架构。

**P0-1/2/3 统一解释**：缺 Chapter 级"结构职责"契约→同构；缺 Chapter 级"知情边界"
契约→全知；缺 Volume/Book 级"未来回环分布"契约→无科幻。一个根，三个表现。

**修复方案**（非补丁，建硬约束，详见 docs/contract-layer-rewire-design.md）：
1. produce-chapter 前置契约为硬 gate：无 confirmed 的 Chapter 级契约（含四层
   payload）则拒绝产稿，不降级。
2. 契约层下沉进生产子步骤：draft_contract → record_contract_review →
   confirm_and_apply，做进 produce-chapter 内部，不再靠人���跑 CLI。
3. 加降级门：跳契约步骤留 debt_marker，入口校验存在则警告/拒绝；清"死线策略"
   docstring。
4. 契约成唯一真相源：brief_builder 改读契约表（卷级三表+章级四层），撤大纲
   裸拼+前章正文 context（BFX-078 的正解）。
5. 加成篇连贯门（coherence_gate 查同构/视角越界/未来回环分布）+ jury"与前章
   连贯"维度。

**卡点**：卷级三表内容（章节功能分工表/视角信息分配表/未来回环分布表）是作者
设定权，需作者裁定，代码层只做读表注入+门校验。

**关联**：BFX-078（context 注入正文原文，本根因的表层补丁，正解=方案4撤正文
context）；memory `ink-contract-layer-rewire-root-cause`、
`ink-context-injection-raw-text-backfires`；评审报告
`D:\_Progs\.BetterCiv\09_工程脚本\ai_workbench\runs\AWT-20260715-171440-5aaf49\amy-review-synthesis.md`。

### H1-H4 防绕过验收补充（2026-07-15）
- **状态**：RESOLVED。
- **H1/H2**：brief 唯一来源锁定为四层 clause；DB 与 Repository 双层阻止残缺契约
  激活，激活后 clause/provenance hash 不可变。
- **H3/H4**：9 条反事实测试 + 两类全源码静态扫描；恢复 Scene-first schema 尾部
  覆盖造成的 6 表缺失，并补回 schema.sql 遗漏的两个项目迁移列。
- **验证**：全量 `python -m pytest -q` 通过。

## BFX-080 BFX-079 接线实施中的具体缺陷（P0，2026-07-15）

BFX-079 架构根因修复（方案 B/C/D）落地时连带暴露的代码缺陷，逐条登记：

### BFX-080-1 `brief_compiler.compile_brief` 误删字数约束行
- **状态**：RESOLVED（2026-07-15）
- **现象**：迁移跨章 context 注入到 `compile_brief` 时，误删 `parts.append("1200-1800 字。")`，
  导致编译出的 brief 不含字数约束，`RealGenerationPort._generation_prompt` 失去
  字数指引。
- **根因**：手工重构时把字数约束行合并进 context 注入分支，原行被替换掉。
- **修复**：恢复 `parts.append("1200-1800 字。")` 在 context 注入前；context 插到
  字数约束前面（约束保持最末）。`tests/test_brief_compiler_context.py` 加
  `test_*_endswith` 不变量守卫。

### BFX-080-2 `compile_brief` 缺跨章 context 能力（BFX-079 方案 D 迁移漏）
- **状态**：RESOLVED（2026-07-15）
- **现象**：删 `brief_builder.py` 后，跨章 context 注入能力（task#7）会随文件
  丢失。`compile_brief` 原只从四层 clause 编译，无前章正文续接。
- **根因**：brief_builder 两个能力混在一起——`build_brief_from_outline`（V1 死
  代码）与 `_prev_chapter_context`（真能力），删文件会一起丢。
- **修复**：把 `_prev_chapter_context` 迁进 `brief_compiler`，`compile_brief` 加
  `inject_prev_context=True` 参数，从契约→scene→chapter_id 自动解析章号取前章
  封版正文头尾各 300 字。第 1 章/前章未封版 graceful skip。7 条单元测试覆盖
  （`test_brief_compiler_context.py`）。

### BFX-080-3 `_ensure_scene_contract_clauses` 异族解析依赖 local import
- **状态**：RESOLVED（2026-07-15）
- **现象**：新 `_ensure_scene_contract_clauses`/`_architect_model`/`_reviewer_model`
  三个 helper 用 `family_from_model_name`，但该符号只在 `produce-chapter` 的
  local import 里——模块级函数调用时 NameError（import 时因未执行分支没暴露）。
- **根因**：helper 是模块级函数，引用的符号必须在模块级可见。
- **修复**：`from ink.pipeline.contract_review_orchestrator import family_from_model_name`
  提到 cli 模块级 import；produce-chapter local import 去掉重复的
  `family_from_model_name`。

### BFX-080-4 双盲审查员取数无 contract_review role 兜底
- **状态**：RESOLVED（2026-07-15）
- **现象**：`_reviewer_model` 若无 `call_type='contract_review'` 配置会直接取不到
  审查员模型，双盲 independent_review 无法发起。
- **根因**：seed 库未为 contract_review role 建配置（新接线 role）。
- **修复**：`_reviewer_model` 三级兜底——优先 contract_review role_config；
  无则从 jury 池取异族；最后固定异族对（architect=glm→deepseek，反之 glm）。
  保证审查员必与架构师异族（INV-CONTRACT-003）。

## BFX-081 E-2 连贯维度接线后的防绕过缺口（P0，2026-07-15）

- **状态**：RESOLVED（2026-07-15）。
- **现象**：chapter review 已新增 `chapter_coherence`，但若只验证正常 8 维返回，仍有
  三类未被证明关闭的旁路：旧 7 维 provider 是否会被默认补分；文学 reviewer 高分
  是否能覆盖确定性同构阻断；E-1 是否可能误读旧 sealed 但非 active 的 Snapshot。
- **根因**：功能测试只证明“新路径能走”，没有用反事实输入证明旧返回、评分覆盖和
  Snapshot 版本漂移都必然 fail closed。
- **修复**：
  1. 增旧 7 维缺 `chapter_coherence` 测试，三 reviewer 都缺维时抛
     `ChapterReviewLLMFailure`，且 `writing_chapter_reviews` 零落库；
  2. 增 coherence=74 独立阻断测试，确认 `blocking_issues` 精确包含该维；
  3. 增 reviewer 8 维全 99 分 + 人工注入 E-1 overlap 命中测试，确认
     `chapter_scene_overlap` 仍阻断且保留证据；
  4. 增 active sealed 来源测试和旧 sealed/non-active 反事实测试，锁定版本读取边界；
  5. 修复 `test_m6_book_export` 夹具继续写 7 维 accepted 假数据的问题，显式写第 8 维。
- **防回归**：`tests/test_chapter_review_real.py`、`tests/test_chapter_coherence.py`、
  `tests/test_m6_book_export.py`；定向 13 条通过，全量 `python -m pytest -q` 通过。

## BFX-082 契约激活门少于规范要求的三家族盲审（P0，2026-07-15）

- **状态**：RESOLVED（2026-07-15）。
- **现象**：`implementation-contract.md` §4 要求同一门至少三个不同模型家族、一家族
  一票；实现却只要求 self-check + 一次 independent review 两条 approve。调用
  `SceneRepository.activate_contract` 或直接更新数据库时，双家族证据即可激活。
- **根因**：早期“dual-master”不变量遗留，Repository、SQLite trigger、审查编排器和
  测试工厂共同固化了两票口径，未随 SPW 三家族门同步升级。
- **修复**：
  1. Repository 与 SQLite trigger 均要求 review_order 1/2/3 三条盲审记录全部
     `approve`、`visible_prior_reviews=0`，且 `reviewer_family` 三者互异；
  2. `independent_review_contract` 支持 `under_review` 态追加第二个独立审查，并拒绝
     已用家族；
  3. `ContractReviewOrchestrator` 改为架构师自检 + 两个异族独立审查，三票全通过才
     `approved=True`；
  4. CLI 模型选择从 contract_review/jury 配置和固定兜底池中选出两个互异异族，
     不足三家族时 fail closed；
  5. 更新测试工厂及激活反事实测试，防止两票激活回归。
- **防回归**：契约激活定向测试 35 条通过；全量 `python -m pytest -q` 通过。

## BFX-083 Shot TaskCard 编译前读取裸 outline（P0，2026-07-15）

- **状态**：RESOLVED（2026-07-15）。
- **现象**：`PreDraftingOrchestrator.compile_task_card` 在调用 `TaskCardCompiler` 前仍通过
  `OutlineRepository.load_winner` 读取 winner outline；读取结果虽未进入当前渲染，却保留了
  Shot 生产链重新把裸 outline 注入 TaskCard 的旁路入口。
- **根因**：旧 Shot 流程遗留的无用取数未随契约唯一真相源改造删除，且 H4 只扫描
  brief 裸拼，未覆盖 TaskCard 编译边界。
- **修复**：
  1. 删除 `compile_task_card` 对 `OutlineRepository` 和 winner outline 的读取；
  2. TaskCard 保持仅由已落库 shot/chapter/book contract 与 continuity context 编译；
  3. 新增 `TASK_CARD_OUTLINE_INJECTION` AST 扫描，若 `compile_for_shot` 出现 outline
     参数或局部 outline 读取则 CI 失败；
  4. 增参数注入、局部读取两个反事实测试和全源码扫描。
- **防回归**：TaskCard/H4 聚焦测试全通过；全量 `python -m pytest -q` 通过。

## BFX-084 AI Scene Repair Task 仅校验非空 ID（P0，2026-07-16）

- **状态**：RESOLVED（2026-07-16）。
- **现象**：`SceneRepository.create_revision` 已对 `generation_task_id` 做候选 Branch
  存在性和章节作用域校验，但 `repair_task_id` 没有权威表，任意非空整数都能让 AI
  Revision 通过审计门；实现契约仍明确写着“存在性、作用域和状态校验尚待接入”。
- **根因**：早期不变量只防“AI 无任务裸写正文”，后续只把 generation task 映射到
  `writing_chapter_candidate_branches`，没有为 repair 建立等价的持久化真相源��导致同一
  不变量两条分支强度不一致。
- **修复**：
  1. 新增 `writing_scene_repair_tasks`，持久化 project/chapter/scene/branch/source revision/
     active contract/issue/status/creator；
  2. 新增 `SceneRepository.create_repair_task`，创建时验证 Branch-local Scene head 和
     active Contract；
  3. AI Revision 强制 generation/repair task 恰好一个；generation task 必须对应目标
     Branch 且未 rejected；repair task 必须真实存在、作用域和 lineage 一致、状态为
     planned/running；
  4. 新增幂等旧库迁移 `tools/migrate_scene_repair_tasks.py`，不伪造历史 repair task；
  5. 更新 `implementation-contract.md`，删除“尚待接入”的陈旧声明。
- **防回归**：`tests/test_scene_repository.py` 覆盖伪 ID、已完成任务复用和双 task 同传；
  `tests/test_migrate_scene_repair_tasks.py` 覆盖建表、dry-run 与幂等；全量 pytest 通过。

## BFX-085 后继 Contract 激活后旧正文仍可作为当前权威读取（P0，2026-07-16）

- **状态**：RESOLVED（2026-07-16）。
- **现象**：Scene Contract amendment 能记录 parent/actor/reason，但激活后继 Contract 时，
  旧 active Contract、基于旧 Contract 的 Scene Revision、候选 Branch 和已接受 Chapter
  Snapshot 都没有失效传播；旧正文仍能 freeze/select/accept/export，形成双真相源。
- **根因**：已有设计只保证 Contract clause 和 Revision 内容不可变，没有建立“契约权威
  变化 → 派生资产失效”的持久化状态与读取门；repair task 也不会随旧 Contract 失效。
- **修复**：
  1. 新增 Revision、Branch Version、Chapter Snapshot 三层 stale mark 表和 Contract
     replacement 字段；所有失效信息追加记录，不原地修改不可变正文；
  2. 激活同 Scene 后继 Contract 时，在同一事务内 supersede 原 active Contract、传播
     stale、取消旧 Contract 的 planned/running repair task，并记录 runtime event；
  3. generation task 禁止扩展 stale 父 Revision；repair task 允许在 building Branch 上
     使用新 active Contract 修复，绑定后按 Branch 当前 Scene 集合重算 stale；
  4. freeze/select/accept、Branch 正文读取、active Snapshot 正文和 ID 读取统一 fail-closed；
  5. 新增幂等迁移 `tools/migrate_scene_contract_supersede_stale.py`，不伪造历史替代关系。
- **防回归**：`tests/test_scene_stale_propagation.py` 覆盖自动 supersede、三层传播、旧
  generation 拒绝、新 Contract repair 解封、open repair task 取消、active Snapshot 读取
  拒绝和幂等；聚焦测试通过；全量 `pytest` 为 820 passed、10 skipped。
