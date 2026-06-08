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
