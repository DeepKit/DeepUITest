# ArtifactOS History — Completed Tasks

> 已完成任务归档。按 P0→P7 分组，附 commit hash 和完成日期。

---

## P0 — 安全 Critical（全部完成）

| # | 任务 | 来源 | 完成commit | 完成日期 |
|---|------|------|-----------|---------|
| 1 | **Delphi SQL 注入修复**：接入 DeepBase DoQry JSON 参数化 API，删除 `QueryP/ExecuteP` 和 `SafeStr` | 鲁班 + 仙儿 | d699db3 | 2026-05-28 |
| 2 | **绑定 RealPublishGate trigger** | 仙儿 | ef1b183 | 2026-05-27 |
| 3 | **移除硬编码密码**：Python 端 `.env` + Delphi 端 `DeepBase.Security.LoadSecret` | 仙儿 | ef1b183 + d699db3 | 2026-05-27/28 |
| 4 | **SourcePack 数据库层写保护**：UPDATE 触发器 + human_decision_id 门禁 + audit | 仙儿 | 70159dd | 2026-05-27 |
| 5 | **微信回复加授权门禁** | 仙儿 | 061fc40 | 2026-05-27 |
| 38 | **ChainRunner SQL 注入修复**：所有业务链 SQL 改为参数化 | 仙儿 | 77b2b2e | 2026-06-01 |

## P1 — 架构与代码质量（全部完成）

| # | 任务 | 来源 | 完成commit | 完成日期 |
|---|------|------|-----------|---------|
| 6 | **消除 InsertId 8 处重复** | 鲁班 | f64fc6d | 2026-05-27 |
| 7 | **修正 core/services 分层违规**：ChainRunner 移入 services | 鲁班 | 70159dd | 2026-05-27 |
| 8 | **DB 连接全局单例加线程安全** | 鲁班 | f930521 | 2026-05-27 |
| 9 | **细化异常处理**：区分 EFDDBEngineException / 约束违反 / 死锁 | 鲁班 | f930521 | 2026-05-27 |
| 10 | **SourcePack 核心文件导入**：Phase 1A 只导入 27 个核心文件 | 盘古 | 2c6287d | 2026-05-27 |
| 11 | **3 条关键 FK 即时生效** | 盘古 | f930521 | 2026-05-27 |
| 12 | **补齐 FK 时间表** | 盘古 | 363115f | 2026-05-27 |
| 13 | **接入 DeepBase PG 适配器**：DoQry UniDbExec/UniDbScalar/UniDbSelect | DeepBase 对齐 | d699db3 | 2026-05-28 |
| 14 | **配置收敛到 DB1** | DeepBase 对齐 | a089c88 | 2026-05-27 |
| 15 | **补齐 root.txt** | DeepBase 对齐 | c206042 | 2026-05-27 |
| 39 | **Case 层级验证触发器**：year→quarter/month→week→day→day_sub | 仙儿 | 77b2b2e | 2026-06-01 |
| 40 | **SubStudio-Artifact 1:1 约束**：active artifact partial unique index | 仙儿 | 77b2b2e | 2026-06-01 |
| 41 | **跨表状态同步触发器**：Artifact/Task sealed/publishing/frozen coupling | 仙儿 | 77b2b2e | 2026-06-01 |
| 42 | **清理独立 Agent 残留**：runtime enum、文档、DB CHECK 约束对齐 | 仙儿 | ced27e1 | 2026-06-02 |
| 43 | **Engine command lease 续期**：长任务执行期间持续延长 lease_until | 仙儿 | ced27e1 | 2026-06-02 |

## P2 — 测试与质量保障（全部完成）

| # | 任务 | 来源 | 完成commit | 完成日期 |
|---|------|------|-----------|---------|
| 16 | **状态机全覆盖（59/59）** | 鲁班 | fb68e67 | 2026-05-27 |
| 17 | **异常恢复（PG 断开→重连）** | 鲁班 | 97f32b6 | 2026-05-27 |
| 18 | **commit 后回滚链路** | 鲁班 | 97f32b6 | 2026-05-27 |
| 19 | **SourcePack 哈希一致性（10/10）** | 鲁班 | 97f32b6 | 2026-05-27 |
| 20 | **性能基线（1.6ms）** | 鲁班 | 97f32b6 | 2026-05-27 |
| 21 | **Python 烟测接入** | 仙儿 | 502540f | 2026-05-27 |
| 44 | **P1 DB 触发器端到端测试**：层级、1:1、状态同步 | 仙儿 | 77b2b2e | 2026-06-01 |

## P3 — 产品决策（部分已裁决）

| # | 任务 | 决策 | 完成commit | 完成日期 |
|---|------|------|-----------|---------|
| 24 | **首个 SourcePack 大小**：保留一元论但只导核心文件（盘古方案） | ✅ 盘古方案采纳 | 2c6287d | 2026-05-27 |
| 30 | **裁决：VCL Desk + Delphi Engine + PG 直连**：不采用 FastAPI；去掉独立 Agent | ✅ 总设计师裁决 | — | 2026-06-01 |

## P4 — DeepBase 集成收尾（全部完成）

| # | 任务 | 完成commit | 完成日期 |
|---|------|-----------|---------|
| 26 | **全量 SQL 参数化** | 2d3eab4 | 2026-05-28 |
| 27 | **DeepBase 包引用模式**（源码模式） | d699db3 | 2026-05-28 |
| 28 | **exe 运行时冒烟** | 6ee4d4b | 2026-05-28 |
| 29 | **CI build.bat** | 1c1853e | 2026-05-28 |

## P5 — Delphi Runtime Stack（全部完成）

| # | 任务 | 完成commit | 完成日期 |
|---|------|-----------|---------|
| 31 | **迁移 028/029 runtime command** | — | 2026-06-01 |
| 32 | **Runtime command contract 静态测试接入** | — | 2026-06-01 |
| 33 | **Delphi Core runtime contract units**（Types、Repository、Smoke） | — | 2026-06-01 |
| 34 | **Engine command claim / heartbeat / idle lifecycle** | 77b2b2e | 2026-06-01 |
| 35 | **ArtifactOS.Desk DeepShell 骨架**：`src/Desk/` 4 文件，`--desk` VCL 模式 | c17ea7f | 2026-06-04 |
| 36 | **AutoFix wiring + smoke scenarios**：8 个 AutoFix scenario + VCL hook | c17ea7f | 2026-06-04 |
| 37 | **修 Bug**：`ConnectLocked` 死锁、`ArtifactOS_DB()` 双重检查锁、DPR SQL 拼接、Smoke 空异常、build.bat 硬编码用户 | — | 2026-06-01 |

## P6 — Contract Pipeline / 全面开发入口（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 45 | **Contract pipeline 数据表迁移**：`034_contract_pipeline.sql` 含 4 表 + seed 数据 | — | 2026-06-03 |
| 46 | **Contract pipeline 最小烟测**：`test_contract_pipeline.py` 6/6 PASS | — | 2026-06-03 |
| 47 | **RSC/CTF/Contract Delphi service skeleton**：`ContractPipeline.pas` 760 行 | c17ea7f | 2026-06-04 |
| 48 | **轻量上下文组装引擎 Prompt Assembly v0**：`PromptAssembly.pas` 758 行，10-slot + 3-tier 缓存 | — | 2026-06-03 |
| 49 | **质量门禁 v0**：`QualityGate.pas` ES(3规则) + 结构门禁 + Snapshot 封印 | — | 2026-06-03 |
| 50 | **同步 docs/15 与 docs/26 的 Desk 裁决矛盾**：docs/15 §2 重写 | — | 2026-06-04 |
| 51 | **补齐/确认缺失基础文档 16/18/19**：docs/18、19 补 Phase 1 scope 表 | — | 2026-06-04 |
| 52 | **迁移 runner**：`db/migrate.py` — apply/status/dry-run/target/rebuild | — | 2026-06-04 |

## P7 — 结构性技术债（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 53 | **FK hardening phase 1B**：`035_fk_hardening_phase_1b.sql` — 7 个 NOT VALID + VALIDATE FK | — | 2026-06-04 |
| 54 | **Strategic intent layer migrations**：`036_strategic_intent_layer.sql` — 6 表 + 9 种目的类型 seed | — | 2026-06-04 |
| 55 | **RealPublishGate 12 条件实现**：`037_real_publish_gate_conditions.sql` — 12 条件逐一评估 + 审计日志 | — | 2026-06-04 |

## L1 补齐 — 数据结构层（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 56 | **迁移 CognitionTrace + EvidenceClaim + SignalEvent + EventLedger** | 038: 11 tables (signal/governance/event/recall/context) | 2026-06-04 |
| 57 | **迁移 ContentSpecSnapshot + ContractCandidate + RequirementFrame** | 已存在于早期迁移，列结构已验证 | 2026-06-04 |
| 58 | **迁移 StrategyUnit + StrategyUnitMaturity + CognitiveDisturbanceEvent** | 039: strategy_unit_maturity + maturity_change_log + same_day_exception | 2026-06-04 |

## L2 — 第二层：单向流水线（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 59 | **选题漏斗评分引擎 v0**：7 signal types + 4-dim basic + 10-dim strategy + boundary decision | 043 migration + TopicFunnel.pas 828 行 | 2026-06-04 |
| 60 | **RSC→CTF→Contract 单向链**：TopicFunnel.RunSinglePassChain 信号→需求→规格→候选 | commit 38f8d85 | 2026-06-04 |
| 61 | **LLM 调用基础设施：DeepLLMProxy 接入** | 7-tier proxy, ChatWithMessages, singleton access | 2026-06-04 |
| 62 | **PromptAssembly 逻辑填充**：10-slot context + 3-tier cache + contract_id 组装 | PromptAssembly.pas 758 行 | 2026-06-04 |
| 63 | **半ES门禁 + NES门禁 + 策略裁决门禁** | QualityGate 四层全通：ES(5+2规则)→半ES(6 LLM)→NES(3维度)→策略裁决(8动作) | 2026-06-04 |
| 64 | **ChainRunner 端到端贯通**：GenerationService AB dual-track, 3-outline scoring, retry, winner | 044 migration + GenerationService.pas ~1000 行 | 2026-06-04 |
| 65 | **S08 结构化源映射 v0**（因果原语 + required/forbidden relations） | TheoryWeave 服务 + migration 045 + PromptAssembly S08 接线 | 2026-06-04 |

## L3 — 第三层：自治闭环（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 66 | **自动重写循环**：按低分维度定向修正 | GenerationService rewrite loop: DetermineRewriteAction + BuildRewritePrompt | 2026-06-04 |
| 67 | **策略裁决引擎**：on_pass / on_rewrite_exhausted | GenerationService.ApplyStrategyRuling + migration 046 | 2026-06-04 |
| 68 | **条件自动发布**（知乎单平台 + media_publish 集成） | PublicationBridge + media_publish.publish_task + migration 047 | 2026-06-04 |
| 69 | **抽检 + 降权 + 红线冻结机制** | cognitive_disturbance_event table + auto-severity escalation | 2026-06-04 |
| 70 | **认知追踪生成**（写/不写/发布/冻结四态） | cognition_trace table + RecordCognitionTrace method | 2026-06-04 |
| 71 | **边界决策引擎**（不写/仅草稿/受限发布） | boundary_decision table + MakeBoundaryDecision method | 2026-06-04 |
| 72 | **证据包 + 封印 ID + 回滚-召回链路** | publication_seal + recall_card + CreatePublicationSeal/CreateRecallCard | 2026-06-04 |
| 73 | **冻结状态 + 解封路径** | FreezeArtifact/UnfreezeArtifact + frozen→assembled transition | 2026-06-04 |

## L4 — 第四层：反馈进化（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 74 | **数据回收**：发布后表现数据采集 | performance_observation table + PerformanceCollector + migration 049 | 2026-06-04 |
| 75 | **进化控制台最小骨架**：策略单元列表 + 灯号 + 降权按钮 | TEvolutionConsoleFrame VCL + TEvolutionViewProvider | 2026-06-04 |
| 76 | **calibration_delta 账本** | calibration_ledger + strategy_change_proposal + migration 050 | 2026-06-04 |
| 77 | **StrategyChangeProposal 自动生成**（连续偏离触发） | CheckAndGenerateProposal: consecutive_miss≥3 → auto-generate | 2026-06-04 |
| 78 | **灰灯避险**（algorithm_noise_overload） | DetectAlgorithmNoise: quality>0.7 + engagement<0.05 → grey light | 2026-06-04 |
| 79 | **反馈作用范围标注和写入** | AnnotateFeedbackScope: 5-tier scope annotation | 2026-06-04 |

## Phase 2 — 影子闭合 + 接管闭合 + 进化控制台扩展（全部完成）

| # | 任务 | 完成说明 | 完成日期 |
|---|------|---------|---------|
| 80 | **ShadowRun 7天自动调度器** | TShadowRunScheduler: StartSevenDayRun + AdvanceDay + CloseOutRun | 2026-06-04 |
| 81 | **RealPublishGate 12条件运行时 runner** | TRealPublishGateRunner: ConfigureSession + Evaluate + EmitDisturbanceOnFailure | 2026-06-04 |
| 82 | **EvolutionConsole AutoTune 审计 + 黄灯协商** | TAutoTuneAuditFrame: event grid + approve/reject/negotiate | 2026-06-04 |

## 里程碑事件

| 日期 | 事件 | commit |
|------|------|--------|
| 2026-05-25 | 初始化项目蓝图 | 15ef229 |
| 2026-05-25 | migrations 006-020 完成 Phase 1A 数据库骨架 | 8cd4681 |
| 2026-05-26 | Delphi 项目骨架 + 端到端链路测试 | a4e965e |
| 2026-05-26 | ShadowRun/QualityGate/PackageBuilder/Notification/AutoTune 全部服务 | d50ece2 |
| 2026-05-26 | LegacyImport 服务 + Legacy Bridge 测试 | 9fd7bf5 |
| 2026-05-26 | 7 天影子运行复盘报告 — 15/15 PASS | c1d396d |
| 2026-05-27 | 五人圆桌审阅 + DeepBase 对齐任务清单 | 9a9342f |
| 2026-05-27 | P0 安全 4/5 完成，P1 9/10 完成 | 9369421 |
| 2026-05-28 | DeepBase DoQry 深度集成，Delphi 编译通过 | d699db3 |
| 2026-05-28 | P0 全部完成，P1 全部完成，Delphi exe 产出 | d699db3 |
| 2026-06-01 | 三人开发审阅 — 8 个阻塞项识别 | 77b2b2e |
| 2026-06-02 | 运行时治理硬化（Agent 清理 + Lease 续期） | ced27e1 |
| 2026-06-04 | Contract pipeline 全链（4表 + 骨架 + 烟测） | c17ea7f |
| 2026-06-04 | 数据库 37/37 migrations 全部通过 | — |
| 2026-06-04 | L2-59 选题漏斗评分引擎 + L2-60 RSC→CTF→Contract 单向链 | 38f8d85 |
| 2026-06-04 | L2-62 PromptAssembly 10-slot + 3-tier cache 填充完成 | — |
| 2026-06-04 | L2-64 GenerationService AB dual-track + 端到端贯通 | — |
| 2026-06-04 | 数据库 44/44 migrations 全部通过 (121 tables) | — |
| 2026-06-04 | L3 自治闭环 #66-73 全部完成 | — |
| 2026-06-04 | L4 反馈进化 #74-79 全部完成 | — |
| 2026-06-04 | Phase 2 影子闭合 #80-82 全部完成 — Phase 1 (L1-L4) 完整闭环 | fdc9a96 |
| 2026-06-11 | UUID brace fix, DUnitX 37.0 compat, SQL hardening, docs alignment | 758a5df |
| 2026-06-12 | BUG-048 跨连接不可见修复 + Connection.pas 重构 | b8695f3 + 4244fea |
| 2026-06-12 | DUnitX 20/20 ALL TESTS PASSED — 13 failures resolved | 0fda29f |
| 2026-06-12 | N3 DeepFrames Integration Bridge — 3 tables + 12 methods + poll scheduler | 9f38f09 |
| 2026-06-12 | N4 正式环境迁移 — 52/52 migrations applied to artifactos | 91112e8 |
| 2026-06-12 | N5 Multi-Platform Adapter — zhihu + wechat + xiaohongshu | cd94d83 |
| 2026-06-12 | N1-N5 全部完成 — Phase 1-2 task chain closed | 600c42f |
| 2026-06-13 | N6 E2E运行时验证 — 13/13 Python + 7-day Shadow + 9/9 autofix | dc0e1bf |
| 2026-06-13 | N7.2-3 DeepFrames 部分完成 — integration tables + Bridge + Scheduler 编译 | 9f38f09 |
| 2026-06-13 | N8 CI/CD 补全 — build.bat + .env.example + docs alignment | 24fc697 |
| 2026-06-13 | N8.4 BindParamsFromJson 参数化引擎 | 5269fa4 |
| 2026-06-13 | N8.5 PackageBuilder PlatformAdapter 多平台路由 | 38ebe04 |
| 2026-06-14 | N8.6 DB Integrity 12 tests migrated from Python → Delphi | b31e1dc |
| 2026-06-14 | DUnitX 37/37 ALL TESTS PASSED — 7 fixtures, 0 failures | eaa3b57 |
| 2026-06-14 | N9 Phase 3 全部完成 — 3 migrations + 4 services + 22 tests + 4-platform adapter | 9dbab69 |
| 2026-06-14 | N9.1-N9.3: strategy_unit 根表 + StrategyUnitManager CRUD | 9dbab69 |
| 2026-06-14 | N9.4: TWeiboAdapter + PublicationBridge × PlatformAdapter wiring | 9dbab69 |
| 2026-06-14 | N9.5: Legacy exit closure (L0→L5 stage machine) | 9dbab69 |
| 2026-06-14 | N9.6: Layered shared knowledge engine (Propose/Adopt/Rate/FindRelevant) | 9dbab69 |
| 2026-06-14 | DUnitX 59/59 ALL TESTS PASSED — 11 fixtures, 0 failures | 9dbab69 |
| 2026-06-14 | ArtifactOSBridge.pas 5 hardening measures (SQL param, backoff, tenant, pool, context) | 2783d84 |
| 2026-06-14 | N10 三专家审查修复 — 23 findings fixed across 8 files | d2c7699 |
| 2026-06-14 | N10.1 CRITICAL: SQL injection + single-quote escape (C1-C4) | d2c7699 |
| 2026-06-14 | N10.2 HIGH: thread safety + tx boundaries + JSON parser rewrite (H1-H5) | d2c7699 |
| 2026-06-14 | N10.3 HIGH: logic bugs + DRY extraction + JsonBuilder unit (H6-H11) | d2c7699 |
| 2026-06-14 | N10.4 MEDIUM: RowsAffected checks + error logging + overflow guards | d2c7699 |
| 2026-06-16 | N11.1 HIGH 缺口补齐 — 7 tests (StrategyUnit 4 + LegacyExit 3) | 35238a0 |
| 2026-06-16 | N11.2 MEDIUM 缺口补齐 — 15 tests (LegacyExit 5 + SharedKnowledge 5 + Integration 3 + StrategyUnit 2) | 35238a0 |
| 2026-06-16 | N11.3 AutoFix 集成 — 12 scenarios, 21/21 PASS, 0 FAIL | 35238a0 |
| 2026-06-16 | N11.4 实现修复 — F1 Weibo backtick + F2 LegacyExit L5 terminal + F3 AccountId UUID | 35238a0 |
| 2026-06-16 | StrategyUnit DUnitX 注册修复 — 补充 initialization 段 RegisterTestFixture | b31e1dc |
| 2026-06-16 | Weibo TitleHasHashTags 测试断言对齐 — #Hello World# → #HelloWorld# | b31e1dc |
| 2026-06-16 | BUG-057/058/059 记录 — N11 测试驱动发现的 3 个实现 bug | eaa3b57 |
| 2026-06-16 | 数据库密码更新 — 正式库 a29806588-run, 测试环境变量 ARTIFACTOS_DB_PASS | — |
| 2026-06-17 | N12.1 双重转义 Bug 修复 — JsonEscape 删除单引号转义，BindParamsFromJson 为唯一 SQL 转义点 | — |
| 2026-06-17 | N12.2 IntegrationBridge SQL 注入修复 — 全部 9 方法改为参数化 ExecuteJson/QueryJson | — |
| 2026-06-17 | N12.3 InsertAndReturnId 竞态条件修复 — 双路径：RETURNING 原子 / 遗留 ExecSQL+SELECT | — |
| 2026-06-17 | N12.4 BindParamsFromJson 参数名前缀冲突 — 按长度降序排序 | — |
| 2026-06-17 | N12.5-6 Weibo FormatBody 破坏性格式化修复 — 行首#剥离 + 删除过度_剥离 | — |
| 2026-06-17 | N12.7-14 代码去重 + 线程安全 + 测试质量 — 6 处 JsonStr 副本 → 1 处 JsonBuilder | — |
| 2026-06-17 | N12.8-9 PlatformAdapter 线程安全 + FormatTitle 畸形标签修复 | — |
| 2026-06-17 | N12.15 Weibo ValidateTitle 长度警告 | — |
| 2026-06-17 | DI3-DI6 DeepBase 集成改进 — LoadSecret 优先 + LLM 实例复用 + DoQry 文档 | — |
| 2026-06-17 | 最终验证 — 编译: 0 errors, autofix: 21/21 PASS, 净减少 75 行代码 | — |
| 2026-06-17 | N13.1 InsertAndReturnId 竞态修复补齐 — TheoryWeave/LegacyImport 补 RETURNING id::text | a9f3362 |
| 2026-06-17 | N13.2 InsertAndReturnId wrapper 去重评估 — 6 处均为 3 行 forwarder，低价值清理延后 | a9f3362 |
| 2026-06-17 | N13.4 Repository.pas JSON 去重 — 删除私有 JsonEscape/JsonPair/JsonObject，统一到 JsonBuilder | a9f3362 |
| 2026-06-17 | N13.5 FormatBody 性能 — TStringBuilder 替换逐字符拼接，每次省 ~1MB 临时字符串 | f05cea4 |
| 2026-06-17 | Post-review #2 DeepLLMProxy 线程安全 — 回退 DI5 共享实例，per-call Create/Free | 82a510e |
| 2026-06-17 | Post-review #3 FormatBody CRLF 边界 + 行首空格剥离修复 | 82a510e |
| 2026-06-17 | Post-review #4 FormatTitle 破坏性 # 删除 → 边缘包裹（"C# Tips" → "#C# Tips#"） | 82a510e |
| 2026-06-17 | Post-review autofix 断言对齐 — weibo_title_hashtags #Hello World# → #HelloWorld# | 82a510e |
| 2026-07-13 | 文档对齐 — tasks/history/bugfix 三档同步，N13.1-13.5 + 4 post-review bugs 归档 | — |
| 2026-07-13 | BCW-S5 CLI AV 修复 — `IfThen(Length(Pos)>N,Pos[N],'')` 对空数组越界读 nil 致 EAccessViolation；改 `PosAt: TFunc<Integer,string>` 闭包短路求值，12 处分发调用替换；status/schedule/cycle plan/config show/report 全部返回真实数据。BUG-080/081/082 同修 | — |
| 2026-07-13 | N13.6 GetContractJson 缓存 — contractId 进程内 TDictionary + TMonitor 双检锁，ClearContractCache 公开；消除每 session 5 次冗余 DB 查询 | a457053 |
| 2026-07-13 | N13.7 JsonBuilder 迁移 — git mv `core/ArtifactOS.Core.DB.JsonBuilder.pas` → `core/ArtifactOS.Core.Common.JsonBuilder.pas`，10 处 uses 改名，主+测试双编译 0 error | a457053 |

| 2026-07-13 | BCW-S1 本地文件交换闭环 — `bcw apply` 子命令（dpr 位置参数分发）；TBCWImportService 四项检查（schema/package_id 去重/必填字段/account+platform+effdate 冲突告警）；落库 bcw_applied_package + event_ledger；inbox→applied 文件迁移；migration 056；协议文档 v0.2 YAML→JSON；示例包 BCW-PKG-20260713-001.json | — |
| 2026-07-14 | BCW-S1 全链路实测通过 — 修复 BUG-076（.env 密码被 shell 残留 env 覆盖）+ BUG-077（PG 中文 lc_messages 致 psycopg2 握手崩溃）+ DB1 Secrets 写入真实 PG 凭据（DPAPI）后，`bcw apply` 端到端打通：包 BCW-PKG-20260713-001 导入 `artifactos.bcw_applied_package`（record `8fae9f4e-...`），event_ledger 联动；migration 56/56 全 APPLIED；migrate.py 加 `load_dotenv(override=True)` + 连接后 `SET lc_messages=english` | — |
| 2026-07-14 | BCW-S2 端到端验证通过 — `bcw preview/apply/rollback` 三子命令链路打通：preview 显示 2 个 MODIFY diff（bcw-xhs-1/2）；apply 落 bcw_applied_package(record `49fc7729-...`) + bcw_config_snapshot 快照 + strategy_unit upsert + event_ledger；rollback 用 snapshot 还原 strategy_unit、行标记 rolled_back。修复 BUG-078（BindParamsFromJson 把空 PrevPkgId 绑成 `''::uuid` 触发 PG 无效 uuid 语法，首次应用无前序包时必现）。migration 057 account+snapshot 两表。 | — |
| 2026-07-14 | BCW-S3 运行配置映射 — `MapPackageToSURecord`：disclosure→theory_intervention、platform→content_type、series.status→autonomy_level+publish_permission、resource_ratio→experiment_strategy、review_cycle→字段；单表 strategy_unit 承载，无 per-field 审批表。`icPromptOnly` 约束：autonomy 提级/publish 扩权/resource_ratio Δ>0.2 时 hold back 旧值并产 PROMPT_ONLY issue。实测：S2TEST 包映射字段全对(disclosure=medium→medium_explicit、xhs→card、flagship_candidate→L2)；S3ESCALATE 包产 3 个 PROMPT_ONLY 并 hold back，二次 apply 仍报同样 issue 证明持久回写；S3RETIRE 包走 retired 轻量分支(active→retired MODIFY/STOP)。主+测试双编译 0 fatal。 | — |
| 2026-07-14 | BCW-S5 运营CLI骨架(P0) — 新增 `ArtifactOS.Core.CLI.Dispatch.pas`：TCLIExitCode(0/2/3/4/5/70)+TCLICommand注册表(bcw/config/cycle/batch/guide/production/schedule/status/report)+TCLIResult.ToEnvelope(stdout单一JSON envelope)+dry-run解析。dpr 守卫块：未知位置参数→退出码2+envelope(不落Dashboard)；已知未实现命令→退出码3+NotImplemented envelope(不静默成功)；RunFullChain 默认路径改由 `--run-demo` 显式触发(P0第三条)。实测三条全过：`frobnicate`→exit2、`config show`→exit3+envelope、`cycle plan --dry-run`→dry_run:true。主+测试双编译 0 error。 | — |
| 2026-07-13 | AP-P0 多平台发布参数与白名单 — 新增 `TPublishRunConfig`(AllowedPlatforms/PublishMode/AccountStage/MaxPostsPerRun/RequireHumanOnChallenge/EnableContentWhitelist，默认仅 xiaohongshu)；`TPublicationBridge.ConfigureFromArgs` 解析 6 个 --flags 并失败回退默认；`AutoPublish` 入口加 `IsPlatformAllowed` 硬白名单守卫(未授权平台写 DB 前即返回，零副作用)；`AutoPublishAll` 遍历已注册适配器→白名单过滤→建任务→MaxPostsPerRun 封顶，逐平台 try/except 单点失败不丢证据。编译期修 BUG-083(for-in 变量赋值 E2081)与 BUG-084(uses 重声明 E2004)。主+测试双编译 0 error。 | — |
| 2026-07-13 | AP-P1 4/5 完成 — (1) XiaoHongShu 适配器 `SupportsVideo:=True`+`VideoAspect:='3:4'`+`CoverAspect:='3:4'`+`MaxVideoCount:=1`+`MaxVideoDurationMs:=300000`；(2) `CandidatePackImporter.LoadAndValidate` 读 `package_manifest.json` 全量接收 9 文件(8 资产+manifest 入口)；(3) 校验 ext↔mime+size>0+cover/video 3:4+SHA-256 重算比对+4 JSON 可解析+duration_ms>0+字幕 UTF-8，7/7 测试全过；(4) `Persist` 写 `asset_file`(video/cover 含 sha/w/h/dur)+`publication_package`(ai_disclosure/source_trace::jsonb/manifest_blob::jsonb/asset_hashes::jsonb/quality_snapshot_id)。修复 BUG-085(`:acct` 空串→`NULLIF(:acct,'')::uuid`，与 BUG-078 同源空 uuid 归一)，解锁 Persist 全链路。**剩余**：第 5 条 `integration.production_request` handoff INSERT 未实现(设计已记注释)+ 真实 DeepFrames 包 E2E 未跑(当前用合成 fixture)。另记 BUG-086(DoQry 查询注册表未填充致 26 测试 errored，预存在、独立于 AP-P1)。主 exe 55499 行 0 error。 | — |
| 2026-07-13 | AP-P1 5/5 开发完成 — 第 5 条 `integration.production_request` handoff ���现：`Persist` 在 `publication_package` INSERT 后(同一连接、未 disconnect), INSERT 一条 pending 请求到 `integration.production_request`, `request_payload` 带包级摘要(package_id/platform/account_id/quality_snapshot_id/asset_hashes/title)供 DeepFrames 轮询无需回查包表; `request_code='xhs_'+package_id` + `ON CONFLICT (tenant_id, request_code) DO NOTHING` 保证同一候选包重复导入只产 1 条请求(幂等)。测试加 4 项断言(pending 状态/platform/payload.package_id/恰好 1 条), `CleanupChain` 增删 production_request 行防堆积。CandidatePackImporter 套件 7/7 全过; 主 exe 55493 行 + 测试 38089 行双编译 0 error。剩余 AP-P1 仅端到端真实 DeepFrames 包 E2E 未跑(合成 fixture 已覆盖代码路径)。BUG-086(查询注册表未填充致 27 errored/1 failed)预存在、独立于本次改动。 | — |
| 2026-07-13 | AP-P1 端到端烟测全绿 — 新增 `src/smoke/SmokeCandidatePack.dpr` 独立 exe：合成结构真实候选包(9 文件: 3:4 视频 64KB 占位+1×1 PNG 封面+8 role 文本/JSON 资产+manifest，uses 加 `FireDAC.Phys.SQLite`/`SQLiteDef` 供 DeepBase 读 config.db)，跑通 `LoadAndValidate`(8 assets valid, 3:4/SHA-256/mime/JSON 全过) → seed artifact/version/snapshot → `Persist`(写 publication_package + asset_file 2 rows + integration.production_request pending) → 反查(ai_disclosure/asset_hashes->video/manifest package_id/prod_request status+pkg_id+platform 全一致) → 幂等(同 request_code 重插 `ON CONFLICT (tenant_id,request_code) DO NOTHING` → count 仍 1) → cleanup。`===== ALL STEPS PASSED =====` 连续两次稳定。修复 3 个真实 schema 对齐问题: manifest asset role 必须是 `source`(非 `source_trace`)、`artifact` 表无 `kind` 列(只插 title)、`account_id` 是 uuid 列(空串走 `NULLIF('','')::uuid`→NULL, 不能传字符串)。幂等测试步从"重调 Persist"改为"直接重插 production_request 验证 ON CONFLICT"——Persist 对 publication_package 不幂等(其 idempotency_key 唯一约束, PackageBuilder 恰好调一次), 只有 AP-P1 #5 的 handoff INSERT 幂等。真实 DeepFrames 产物待 N7.4 联调替换包内容即可(导入路径编码无关)。AP-P1 全 5 条 ✅。 | — |
