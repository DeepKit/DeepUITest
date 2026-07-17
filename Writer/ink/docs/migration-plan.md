# Ink v2 Shot→Scene 安全迁移计划

> 状态：当前迁移法源
> 原则：允许影子验证，不允许双正文权威

## 当前阶段状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| S0 规范冻结 | 进行中 | 当前法源已建立；剩余P0不变量未全部实现 |
| S1 新表与Repository | 已完成影子底座 | 内存SQLite与旧全量回归通过；未迁移既有文件库 |
| S2 旧数据回填 | 已落地 | 统一迁移跟踪已落地（BFX-092，2026-07-17）；详见下节 |
| S3 影子验证 | 未开始 | 尚无旧/新导出hash parity |
| S4 一次切换 | 未开始 | 禁止执行 |
| S5 移除旧权威后门 | 未开始 | 旧CLI仍是唯一生产路径 |
| S6 真实试点 | 未开始 | 待前三类章节A/B |

## S0：规范冻结

- 完成 `design.md`、`implementation-contract.md`；
- 完成 Scene-first P0 不变量；
- 定义 Scene 边界识别规则；
- 定义 Branch-local expected parent；
- 定义 Snapshot Accept 事务；
- 冻结旧 Shot schema 的新增功能。

退出条件：实现团队无需读取归档文档即可编码。

## S1：新表与Repository

- 新增 Scene/Contract/Revision/Branch/Snapshot/Head 表；
- 新增不可变 trigger 和唯一索引；
- 新增 SceneRepository、ChapterSnapshotRepository；
- 旧生产路径保持唯一权威；
- 新表只允许测试和 dry-run。

退出条件：内存SQLite测试通过，旧测试无回归。

当前结果：退出条件已满足；但这只表示影子底座完成，不表示既有生产数据库已经拥有新表。

## S2：旧数据回填

> 本节于黄金闭环②（2026-07-17）重写"无正式 migration/backfill 工具"的原描述:
> 统一迁移跟踪机制已落地并完成正式库重建。原"无工具/无跟踪"前提不再成立,
> 下文"已落地"段为实况,S2 的 schema 就绪条件已满足。
> 但"对每个 accepted 章节实际回填出 Snapshot"的语义仍保留在后半段,
> 属于第③步重产工作,本节只保证 schema 与迁移机制就绪。

### 已落地（BFX-092，2026-07-17）

- **统一迁移跟踪**：`ink/src/ink/schema.py` 新增四个函数——
  `migrate_db(conn)`（按文件名序读 `ink/sql/migrations/*.sql` 幂等应用,每迁移独立
  事务、写 `schema_migrations` 表、带 sha256 checksum 校验）、
  `mark_all_migrations_applied(conn)`（全新库专用,base schema.sql 已含全部迁移对象,
  只登记不重跑,避免重复 CREATE 已存在的表）、`list_migration_files()`、
  `applied_migrations(conn)`。
- **迁移文件已存在**：`ink/sql/migrations/` 现有 15 个迁移,其中 2 个是闭环②新增——
  `2026-07-16_schema_migrations_registry.sql`（迁移注册表,自举创建）、
  `2026-07-16_stale_marks_tables.sql`（stale_marks 三表,从原独立脚本提取为正式迁移）。
- **新增工具**：
  `ink/tools/export_legacy_params.py`（只读导参,导出 legacy 库 projects/role_configs/
  schema_authority 等为 params JSON,不写库）、
  `ink/tools/rebuild_prod_db.py`（重建干净库,默认 dry-run;`--apply` 真建库,
  `--force` 覆盖已存在文件并自动备份为 `*.bak.YYYYMMDD-HHMMSS`。全新库走
  `initialize_schema` + `mark_all_migrations_applied`,一次性带齐全部表）。
- **正式库已原地替换**（2026-07-17）：`baideng_prod.db` 已重建为新库,实测 80 张表,
  15 个迁移全部登记为已应用,legacy 参数已回灌；原库留存 2 份备份
  （`baideng_prod.db.bak.20260717-153047`、`.153134`）。

### legacy schema 缺口与游离表

实测 legacy 库（备份）比新库缺 8 张表,不止 stale_marks 三表——另有：
`writing_chapter_accept_gate_evidence`、`writing_chapter_snapshot_gate_evidence`、
`writing_contract_fact_bindings`、`writing_scene_repair_tasks`、`schema_migrations`。
说明 legacy schema 快照比"07-16 stale_marks 加入前"更老。这些缺口由新库
`rebuild_prod_db.py` 一次性补齐,无需逐表手工迁移。

游离表 `writing_schema_authority`（BFX-093,2026-07-17）：存在于 legacy 库但**不在
`schema.sql`、不在 `sql/migrations/`、不在 `src/ink/` 源码任何地方**——是 BFX-079 期间
ad-hoc 手工建的 legacy 标记表。新库不回灌此表（schema.sql 不建它则新库自然没有）；
legacy 标记状态已由 `export_legacy_params.py` 导出存入 params JSON 的 `schema_authority`
段备查。若后续仍需 legacy 隔离机制,应正式工程化（DDL 入 schema.sql 或迁移文件 + 源码
引用）,不沿用无定义的临时表。

### Snapshot 回填语义（保留，属第③步重产）

对每个 accepted 章节：

1. 读取旧 Shot 顺序和正文；
2. 生成 proposed Scene boundaries；
3. 记录置信度和歧义原因；
4. 低置信边界进入 DecisionSession；
5. 创建初始 Scene、Scene Revision；
6. 创建初始 Branch Version；
7. 创建初始 Chapter Snapshot；
8. 保存 legacy Shot lineage。

退出条件：所有 accepted 章节都有可追溯 Snapshot。

## S3：影子验证

比较：

```text
旧 accepted 导出
vs
新 Snapshot 导出
```

必须验证：

- 文本hash；
- Scene顺序；
- 标题与分隔；
- 来源血缘；
- Fact Anchor；
- 长篇连续性。

影子输出不对外，不进入正式上下文。

退出条件：差异为零，或全部有作者批准的差异记录。

## S4：一次切换

1. 备份生产库；
2. 暂停写入；
3. 完成增量回填；
4. 运行 FK、hash、唯一性和不可变检查；
5. 切换 accept/export/context/review 到 Scene-first；
6. 设置 schema marker；
7. 旧 Shot 正文路径改只读；
8. 恢复写入。

失败时恢复备份，不允许半切换。

## S5：移除旧权威后门

- export 不再读 `v_current_text`；
- accept 不再 hard-seal Shot；
- repair 命令定位 Scene；
- Shot 仅作为 Internal Shot；
- SQL lint 阻断新代码访问 legacy canonical 路径；
- 旧表归档，不急于删除。

## S6：真实试点

选择至少三类章节：

1. 工业/动作；
2. 人物关系/潜台词；
3. 低强度过渡/留白。

每类比较 Shot-first 历史结果与 Scene-first 新结果，记录：

- 作者偏好；
- 场景整体性；
- 人物可信度；
- 候选差异；
- 返工次数；
- 调用成本；
- 评审分歧；
- 少数冠军命中。

通过后才宣布 Scene-first 投产。
