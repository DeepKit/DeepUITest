# ArtifactOS Tasks — Phase 1A 收尾

> P0/P1 全部完成，P2 全部完成，P4 全部完成
> 剩余：P3 产品决策（需总设计师裁决）
> 更新: 2026-05-29

---

## ✅ P0 — 安全 Critical（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 1 | Delphi SQL 注入修复 + DoQry 参数化 | d699db3 |
| 2 | RealPublishGate trigger 绑定 | ef1b183 |
| 3 | 硬编码密码移除 | ef1b183 + d699db3 |
| 4 | SourcePack 数据库层写保护 | 70159dd |
| 5 | 微信回复授权门禁 | 061fc40 |

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

## ✅ P2 — 测试与质量保障（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 16 | 状态机全覆盖（59/59） | fb68e67 |
| 17 | 异常恢复（PG 断开→重连） | 97f32b6 |
| 18 | commit 后回滚链路 | 97f32b6 |
| 19 | SourcePack 哈希一致性（10/10） | 97f32b6 |
| 20 | 性能基线（1.6ms） | 97f32b6 |
| 21 | Python 烟测接入 | 502540f |

## ✅ P4 — DeepBase 集成收尾（全部完成）

| # | 任务 | 完成commit |
|---|------|-----------|
| 26 | 全量 SQL 参数化 | 2d3eab4 |
| 27 | DeepBase 包引用模式 | d699db3（源码模式） |
| 28 | exe 运行时冒烟 | 6ee4d4b |
| 29 | CI build.bat | 1c1853e |

## P3 — 产品决策（需总设计师裁决）

| # | 任务 | 状态 |
|---|------|------|
| 22 | 裁决：影子运行 vs 平行运行 | pending |
| 23 | 裁决：Phase 1A 表数 | pending |
| 25 | 裁决："不做 MVP"条款修正 | pending |

## P5 — Delphi Runtime Stack（进行中）

| # | 任务 | 状态 |
|---|------|------|
| 30 | 裁决：VCL Desk + Delphi Agent/Engine + PG 直连，不采用 FastAPI core backend | done |
| 31 | 迁移：`028_artifactos_runtime_command.sql` 定义 runtime_instance / runtime_command / runtime_command_event | done |
| 32 | 测试：runtime command contract 静态测试接入 `tests/run_all_tests.py` | done |
| 33 | 待做：ArtifactOS.Core runtime contract Delphi units | pending |
| 34 | 待做：ArtifactOS.Engine command claim / heartbeat / idle lifecycle | pending |
| 35 | 待做：ArtifactOS.Desk DeepShell 骨架 | pending |
| 36 | 待做：ArtifactOS.Agent Tray / Amy command launcher | pending |
| 37 | 待做：AutoFix wiring + smoke scenarios | pending |

## 数据库落点

```text
DB1 ConfigDB (SQLite)  ← DeepBase 自动管理 + ArtifactOS 运行参数
DB2 本地业务库 (SQLite) ← Phase 1B 按需创建
DB3 远程业务库 (PG)     ← artifactos（正式）/ artifactos_test（测试）
DB4 生产后端            ← 不直连
```