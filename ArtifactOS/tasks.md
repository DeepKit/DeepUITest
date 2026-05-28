# ArtifactOS Tasks — Phase 1A 优化与整改

> 基于五人圆桌审阅(盘古/灵儿/鲁班/仙儿/李冰) + DeepBase 四库分层对齐
> 更新: 2026-05-28

---

## P0 — 安全 Critical（阻塞切换 real 模式）

| # | 任务 | 来源 | 状态 |
|---|------|------|------|
| 1 | **修 Delphi SQL 注入**：全量转为 FireDAC `ParamByName` 参数化查询，删除 `SafeStr` | 鲁班 + 仙儿 | pending |
| 2 | **绑定 RealPublishGate trigger**：`004_real_publish_gate.sql` 中 `fn_guard_publish_requires_gate()` 缺 `CREATE TRIGGER`，任何人可直接 UPDATE status='published' 绕过 | 仙儿 | pending |
| 3 | **移除 Python/Delphi 硬编码密码**：Python 4 个文件中的 `password=a29806588-run` 改为 os.environ，加入 .gitignore；Delphi 密码进 `DeepBase.Security.SaveSecret` | 仙儿 | pending |
| 4 | **SourcePack 加数据库层写保护**：`source_pack` / `source_inventory_candidate` 添加 UPDATE 前触发器，要求关联 `human_decision_id`；`allow_production` 只能通过存储过程修改 | 仙儿 | pending |
| 5 | **微信回复加授权门禁**：实现 `ReplyCommand` 解析，对每个入站回复校验 `risk_level`（entry/low_risk/needs_confirmation/cockpit_required），高风险必须在 Amy 总控台确认 | 仙儿 | pending |

## P1 — 架构与代码质量（Phase 1A 内修复）

| # | 任务 | 来源 | 状态 |
|---|------|------|------|
| 6 | **消除 InsertId 10 处重复**：提升为 `TArtifactDB.InsertAndReturnId` 成员方法 | 鲁班 | pending |
| 7 | **修正 core/services 分层违规**：`core/ChainRunner.pas` 依赖 `services/` → 移入 services 目录 | 鲁班 | pending |
| 8 | **DB 连接全局单例加线程安全**：`ArtifactOS_DB._Instance` 加 `TCriticalSection` 或连接池 | 鲁班 | pending |
| 9 | **细化异常处理**：区分 `EFDDBEngineException` / 约束违反 / 死锁；`Query` 异常时释放已创建的 TFDQuery；Dashboard 单条查询失败不全局崩溃 | 鲁班 | pending |
| 10 | **SourcePack 改为核心文件导入**：Phase 1A 只导入 30-50 个核心文件（7 个注册 + 母板/解释/实践各 10-15），其余文件只扫不入库 | 盘古 | pending |
| 11 | **3 条关键 FK 即时生效**：`publication_package.quality_snapshot_id` / `shadow_run_observation.shadow_run_day_id` / `artifact_version.artifact_id` | 盘古 | pending |
| 12 | **补齐 FK 补齐时间表**：在迁移文件末尾添加注释文档，列出各 FK 的 Phase 归属 | 盘古 | pending |
| 13 | **ArtifactOS 接入 DeepBase PG 适配器**：删除自建的 `TFDConnection` 拼接连接参数，改用 `DeepBase.DB.PostgreSQL.TPostgreSQLDriver` | DeepBase 对齐 | pending |
| 14 | **配置文件收敛到 DB1**：`config/phase1a/*.yaml` → `DeepBase.SetConfig` 存入 DB1 SQLite | DeepBase 对齐 | pending |
| 15 | **补齐 root.txt**：ArtifactOS 项目根目录生成 root.txt | DeepBase 对齐 | pending |

## P2 — 测试与产品节奏（Phase 1A 内完成）

| # | 任务 | 来源 | 状态 |
|---|------|------|------|
| 16 | **状态机白名单全覆盖测试**：31 个合法组合全测 + 6 个阻断级 flags 独立验证 | 李冰 | pending |
| 17 | **异常恢复路径测试**：PG 断开 → 重连 → 验证数据无污染 | 李冰 | pending |
| 18 | **commit 后回滚链路测试**：解封→重建→重跑门禁 5 步流程 | 李冰 | pending |
| 19 | **SourcePack 哈希一致性测试**：验证 2905 个文件的 file_hash 与标注一致 | 李冰 | pending |
| 20 | **性能基线测试**：`EXPLAIN ANALYZE` 主要查询 + 建必要索引 | 李冰 | pending |
| 21 | **Python 测试接入 DeepBase 门禁**：通过 `Scripts/run_tests.ps1` 调度 Python 烟测 | DeepBase 对齐 | pending |

## P3 — 产品决策（需总设计师裁决）

| # | 任务 | 来源 | 状态 |
|---|------|------|------|
| 22 | **裁决：影子运行 vs 平行运行**：灵儿建议改为平行运行让用户第一天感知价值；仙儿要求先修 5 条安全漏洞才能触碰真实发布 | 灵儿 / 仙儿 | pending |
| 23 | **裁决：Phase 1A 表数**：盘古建议从 ~75 减到 ~30；灵儿建议 ~40。or 保留全表但代码只用于主链 | 盘古 / 灵儿 | pending |
| 24 | **裁决：首个 SourcePack 大小**：保留一元论但只导核心文件（盘古），or 换更小 SourcePack（灵儿） | 盘古 / 灵儿 | pending |
| 25 | **裁决："不做 MVP"条款修正**：灵儿建议改为"架构不欠债，功能做楔子" | 灵儿 | pending |

## 数据库落点最终版

```text
DB1 ConfigDB (SQLite)  ← DeepBase 自动管理 + ArtifactOS 运行参数
DB2 本地业务库 (SQLite) ← Phase 1B 按需创建
DB3 远程业务库 (PG)     ← artifactos（正式）/ artifactos_test（测试，已存在）
DB4 生产后端            ← 不直连
```

- 不连 progee_db / progee_db_test（别人的库）
- 发布系统共用同一个 artifactos PG 库，通过 schema 隔离