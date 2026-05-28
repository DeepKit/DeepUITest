# ArtifactOS History — Completed Tasks

> 已完成任务归档。按 P0→P3 分组，附 commit hash。

---

## P0 — 安全 Critical（全部完成）

| # | 任务 | 来源 | 完成commit | 完成日期 |
|---|------|------|-----------|---------|
| 1 | **Delphi SQL 注入修复**：接入 DeepBase DoQry JSON 参数化 API，删除 `QueryP/ExecuteP` 和 `SafeStr` | 鲁班 + 仙儿 | d699db3 | 2026-05-28 |
| 2 | **绑定 RealPublishGate trigger** | 仙儿 | ef1b183 | 2026-05-27 |
| 3 | **移除硬编码密码**：Python 端 `.env` + Delphi 端 `DeepBase.Security.LoadSecret` | 仙儿 | ef1b183 + d699db3 | 2026-05-27/28 |
| 4 | **SourcePack 数据库层写保护**：UPDATE 触发器 + human_decision_id 门禁 + audit | 仙儿 | 70159dd | 2026-05-27 |
| 5 | **微信回复加授权门禁** | 仙儿 | 061fc40 | 2026-05-27 |

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

## P3 — 产品决策（部分已裁决）

| # | 任务 | 决策 | 完成commit | 完成日期 |
|---|------|------|-----------|---------|
| 24 | **首个 SourcePack 大小**：保留一元论但只导核心文件（盘古方案） | ✅ 盘古方案采纳 | 2c6287d | 2026-05-27 |

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
