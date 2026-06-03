# ArtifactOS Tasks — Phase 1A 收尾与全面开发入口

> 更新: 2026-06-03
> 状态口径：外部评价 `ARTIFACTOS_EVALUATION_2026-06-03.md` 的有效部分已并入本文件；评价文件不再保留。

---

## ✅ P0 — 安全 Critical（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 1 | Delphi SQL 注入修复 + DoQry 参数化 | d699db3 |
| 2 | RealPublishGate trigger 绑定 | ef1b183 |
| 3 | 硬编码密码移除 | ef1b183 + d699db3 |
| 4 | SourcePack 数据库层写保护 | 70159dd |
| 5 | 微信回复授权门禁 | 061fc40 |
| 38 | ChainRunner SQL 注入修复：所有业务链 SQL 改为参数化 | 77b2b2e |

## ✅ P1 — 架构与代码质量（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 6 | 消除 InsertId 重复 | f64fc6d |
| 7 | 分层违规修正 | 70159dd |
| 8 | 线程安全 | f930521 |
| 9 | 异常处理 | f930521 |
| 10 | SourcePack 核心文件导入 | 2c6287d |
| 11 | 关键 FK 即时生效 | f930521 |
| 12 | FK 时间表 | 363115f |
| 13 | DeepBase PG 适配器接入 | d699db3 |
| 14 | 配置收敛 DB1 | a089c88 |
| 15 | root.txt | c206042 |
| 39 | Case 层级验证触发器：year→quarter/month→week→day→day_sub | 77b2b2e |
| 40 | SubStudio-Artifact 1:1 约束：active artifact partial unique index | 77b2b2e |
| 41 | 跨表状态同步触发器：Artifact/Task sealed/publishing/frozen coupling | 77b2b2e |
| 42 | 清理独立 Agent 残留：runtime enum、文档、DB CHECK 约束对齐 | ced27e1 |
| 43 | Engine command lease 续期：长任务执行期间持续延长 lease_until | ced27e1 |

## ✅ P2 — 测试与质量保障（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 16 | 状态机全覆盖（59/59） | fb68e67 |
| 17 | 异常恢复（PG 断开→重连） | 97f32b6 |
| 18 | commit 后回滚链路 | 97f32b6 |
| 19 | SourcePack 哈希一致性（10/10） | 97f32b6 |
| 20 | 性能基线（1.6ms） | 97f32b6 |
| 21 | Python 烟测接入 | 502540f |
| 44 | P1 DB 触发器端到端测试：层级、1:1、状态同步 | 77b2b2e |

## ✅ P4 — DeepBase 集成收尾（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 26 | 全量 SQL 参数化 | 2d3eab4 |
| 27 | DeepBase 包引用模式 | d699db3（源码模式） |
| 28 | exe 运行时冒烟 | 6ee4d4b |
| 29 | CI build.bat | 1c1853e |

## ✅ P5 — Delphi Runtime Stack（基础完成，进入扩展）

| # | 任务 | 状态/commit |
|---|------|-------------|
| 30 | 裁决：VCL Desk + Delphi Engine + PG 直连，不采用 FastAPI；去掉独立 Agent | done |
| 31 | 迁移：`028_artifactos_runtime_command.sql` + `029_runtime_command_parent_and_cleanup.sql` | done |
| 32 | 测试：runtime command contract 静态测试接入 `tests/run_all_tests.py` | done |
| 33 | Delphi Core runtime contract units（Types、Repository、Smoke） | done |
| 34 | ArtifactOS.Engine command claim / heartbeat / idle lifecycle | done / 77b2b2e |
| 35 | ArtifactOS.Desk DeepShell 骨架 | pending |
| 36 | AutoFix wiring + smoke scenarios | pending |
| 37 | 修 Bug：`ConnectLocked` 死锁、`ArtifactOS_DB()` 双重检查锁、DPR SQL 拼接、Smoke 空异常、build.bat 硬编码用户 | done |

---

## P6 — Contract Pipeline / 全面开发入口（当前最高优先级）

外部评价的有效结论：ArtifactOS 设计质量高，剩余阻塞集中在“文档设计已经完成，代码实现尚未追上”。全面开发前应优先让 RSC/CTF/Contract 链条有数据库落点和最小可运行骨架。

| # | 任务 | 状态 | 验收标准 |
|---|------|------|---------|
| 45 | Contract pipeline 数据表迁移 | pending | 新增 `requirement_frame`、`content_spec_snapshot`、`contract_candidate`、`artifact_contract`，并让 `substudio_execution_task.contract_id` 有真实引用目标 |
| 46 | Contract pipeline 最小烟测 | pending | 插入 raw idea → RequirementFrame → ContentSpecSnapshot → ContractCandidate → ArtifactContract，task 可引用 contract 并进入 `spec_status='contracted'` |
| 47 | RSC/CTF/Contract Delphi service skeleton | pending | Delphi 服务可创建最小 contract 链；Python 只做测试/诊断，不作为正式 runtime |
| 48 | 轻量上下文组装引擎 Prompt Assembly v0 | pending | 支持 S00/S01/S02/S06/S08 最小 Slot，能输出可审计 prompt payload |
| 49 | 质量门禁 v0 | pending | 先做结构门禁 + ES 机械合规；半ES/NES 后续扩展 |
| 50 | 同步 docs/15 与 docs/26 的 Desk 裁决矛盾 | pending | docs/15 标注 Python/browser 工作台为诊断/过渡，正式 Desk 指向 Delphi VCL DeepShell |
| 51 | 补齐/确认缺失基础文档 16/18/19 | pending | 微信通道、交互修改与遗忘、证据认知与进化的 Phase 1 边界明确 |
| 52 | 迁移 runner | pending | 可按编号应用 migrations 到 `artifactos_test`，记录 applied migrations |

## P7 — 结构性技术债（非阻塞，分阶段处理）

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 53 | FK hardening phase 1B | pending | 依据 `024_fk_roadmap.sql` 逐步补 FK，避免 orphan records |
| 54 | Strategic intent layer migrations | pending | `lighthouse_strategy_objective`、`case_objective`、`purpose_portfolio` 等 |
| 55 | RealPublishGate 12 条件实现 | pending | 当前仍主要依赖 run_mode flag；后续扩展到文档定义的 12 条件 |

## P3 — 产品决策（需总设计师裁决）

| # | 任务 | 状态 |
|---|------|------|
| 22 | 裁决：影子运行 vs 平行运行 | pending |
| 23 | 裁决：Phase 1A 表数 | pending |
| 25 | 裁决："不做 MVP"条款修正 | pending |

---

## 数据库落点

```text
DB1 ConfigDB (SQLite)  ← DeepBase 自动管理 + ArtifactOS 运行参数
DB2 本地业务库 (SQLite) ← Phase 1B 按需创建
DB3 远程业务库 (PG)     ← artifactos（正式）/ artifactos_test（测试）
DB4 生产后端            ← 不直连
```
