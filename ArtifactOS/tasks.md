# ArtifactOS Tasks — Phase 1 开发主链

> 更新: 2026-06-04
> 已完成任务归档至 `history.md`，已修复 bug 归档至 `bugfix.md`
> 数据库: 44/44 migrations applied (121 tables in artifactos schema)

---

## P3 — 产品决策（需总设计师裁决）

| # | 任务 | 状态 |
|---|------|------|
| 22 | 裁决：影子运行 vs 平行运行 | pending |
| 23 | 裁决：Phase 1A 表数 | pending |
| 25 | 裁决："不做 MVP"条款修正 | pending |

---

## L2 — 第二层：单向流水线（验收 #1 #2 #3 #11 #13）

> 从选题到模拟发布包的单次通过链路，无闭环。依赖 L1（数据结构层）完成。
> L1 全部完成：44 个 migration 覆盖 121 表。
> L2 已完成 6/7，剩余 S08 结构化源映射 v0。

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 56 | 迁移 CognitionTrace + EvidenceClaim + SignalEvent + EventLedger | ✅ done | 038: 11 tables (signal/governance/event/recall/context) |
| 57 | 迁移 ContentSpecSnapshot + ContractCandidate + RequirementFrame | ✅ done | 已存在于早期迁移，列结构已验证 |
| 58 | 迁移 StrategyUnit + StrategyUnitMaturity + CognitiveDisturbanceEvent | ✅ done | 039: strategy_unit_maturity + maturity_change_log + same_day_exception |
| 59 | 选题漏斗评分引擎 v0 | ✅ done | 043: 7 signal types + 4-dim basic + 10-dim strategy + boundary decision |
| 60 | RSC→CTF→Contract 单向链条实现 | ✅ done | TopicFunnel.RunSinglePassChain 信号→需求→规格→候选 |
| 61 | LLM 调用基础设施：DeepLLMProxy 接入 | ✅ done | 7-tier proxy, ChatWithMessages, singleton access |
| 62 | 上下文组装引擎 PromptAssembly 逻辑填充 | ✅ done | 10-slot + 3-tier cache, 已可从 contract_id 组装 prompt |
| 63 | 半ES门禁 + NES门禁 + 策略裁决门禁 | ✅ done | QualityGate 四层全通：ES(5+2规则)→半ES(6 LLM)→NES(3维度)→策略裁决(8动作) |
| 64 | ChainRunner 端到端贯通：选题→合约→生成→门禁→模拟发布 | ✅ done | GenerationService AB dual-track + 3-outline + retry + winner selection |
| 65 | S08 结构化源映射 v0（因果原语 + required/forbidden relations） | pending | docs/11 TheoryWeave 接口协议 |

---

## L3 — 第三层：自治闭环（验收 #2 #3 #4 #5 #6 #7 #9 #10）

> 自动重写循环、策略裁决、条件发布。依赖 L2 完成。

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 66 | 自动重写循环：按低分维度定向修正 | pending | 半ES/NES 门禁结果驱动重写 |
| 67 | 策略裁决引擎：on_pass / on_rewrite_exhausted | pending | 合约通过→自动推进，重写耗尽→上报人类 |
| 68 | 条件自动发布（知乎单平台 + media_publish 集成） | pending | docs/13 §4.0 发布闭环 |
| 69 | 抽检 + 降权 + 红线冻结机制 | pending | CognitiveDisturbanceEvent 驱动 |
| 70 | 认知追踪生成（写/不写/发布/冻结四态） | pending | CognitionTrace 服务 |
| 71 | 边界决策引擎（不写/仅草稿/受限发布） | pending | BoundaryDecision 记录 |
| 72 | 证据包 + 封印 ID + 回滚-召回链路 | pending | PublicationSeal + RecallCard |
| 73 | 冻结状态 + 解封路径 | pending | frozen → unfreezing → active |

---

## L4 — 第四层：反馈进化（验收 #7 #8 #14 #15）

> 发布后数据回收、进化控制台、AutoTune。依赖 L3 完成。

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 74 | 数据回收：发布后表现数据采集 | pending | views/likes/favorites/comments |
| 75 | 进化控制台最小骨架：策略单元列表 + 灯号 + 降权按钮 | pending | VCL 界面 |
| 76 | calibration_delta 账本 | pending | 预测 vs 实际的校准偏差 |
| 77 | StrategyChangeProposal 自动生成（连续偏离触发） | pending | AutoTune 高风险参数 |
| 78 | 灰灯避险（algorithm_noise_overload） | pending | 算法噪音过载检测 |
| 79 | 反馈作用范围标注和写入 | pending | feedback scope + application |

---

## 依赖关系

```text
L1 补齐（#56-58）──→ L2 流水线（#59-65）──→ L3 自治闭环（#66-73）──→ L4 反馈进化（#74-79）
  ✅ 已完成            🔄 5/7 完成          待开始                待开始
```

每层完成后进入下一层；上一层的问题可以在下一层开发中修正，但不得跳层。

---

## 数据库落点

```text
DB1 ConfigDB (SQLite)  ← DeepBase 自动管理 + ArtifactOS 运行参数
DB2 本地业务库 (SQLite) ← Phase 1B 按需创建
DB3 远程业务库 (PG)     ← artifactos（正式）/ artifactos_test（测试）  44/44 migrations, 121 tables
DB4 生产后端            ← 不直连
```
