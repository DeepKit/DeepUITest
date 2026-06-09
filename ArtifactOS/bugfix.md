# ArtifactOS Bug Log

> 记录已修复的 bug、触发条件和修复方案。按日期倒序排列。

---

## 2026-06-04

### BUG-044: Migration 043/044 非幂等导致重复执行失败

- **现象**：`python db/migrate.py` 重跑时，043 和 044 因 index/trigger 已存在而报错。
- **根因**：migration SQL 中 `CREATE INDEX` 和 `CREATE TRIGGER` 未加 `IF NOT EXISTS` / `DROP IF EXISTS`。
- **修复**：043 的 6 个 `CREATE INDEX` 改为 `CREATE INDEX IF NOT EXISTS`；044 的 2 个 `CREATE TRIGGER` 前加 `DROP TRIGGER IF EXISTS`。
- **迁移**：`043_topic_funnel_signal_score.sql`, `044_generation_session.sql`

### BUG-043: GenerationService 编译 Warning W1057 (AnsiString→string implicit cast)

- **现象**：dcc64 编译 `GenerationService.pas` 报 `W1057 Implicit string cast from 'AnsiString' to 'string'`。
- **根因**：`ParseOutlineFromLLM` 中使用 inline var 的 `for var I := ...` 循环，Delphi 对 IndexOf/Chars 操作产生隐式 AnsiString 转换。
- **修复**：将 inline 循环变量提升至 var 声明区，消除隐式类型转换。
- **文件**：`src/services/ArtifactOS.Services.GenerationService.pas`

### BUG-043a: GenerationService 未使用变量 GateResult / VerNo

- **现象**：dcc64 报 Hint `H2164 Variable 'GateResult'/'VerNo' is declared but never used`。
- **根因**：`JudgeQualification` 声明了 `GateResult: TGateResult` 但未使用；`RunABGeneration` 声明了 `VerNo` 但实际只用 `VerNoStart`。
- **修复**：删除未使用的 `GateResult` 和 `VerNo` 变量声明。
- **文件**：`src/services/ArtifactOS.Services.GenerationService.pas`

---

### BUG-037: RealPublishGate 函数签名冲突 `AmbiguousFunction`

- **现象**：`SELECT check_real_publish_gate()` 报错 `function is not unique`，migration 004 创建了 0 参数版本，037 用默认参数又创建了一个，PostgreSQL 无法区分。
- **根因**：PL/pgSQL 函数签名中 `(uuid default null, uuid default null)` 与 `()` 在调用时产生歧义。
- **修复**：037 改为 `(uuid, uuid)` 显式两参数版本 + 单独创建 0 参数 wrapper 委托调用。
- **迁移**：`037_real_publish_gate_conditions.sql`

### BUG-036: purpose_type_registry seed 缺少 `status` NOT NULL 列

- **现象**：migration 036 的 `INSERT INTO purpose_type_registry` 失败，报 `null value in column "status" violates not-null constraint`。
- **根因**：seed INSERT 列列表漏写 `status` 字段，`status` 列定义为 `NOT NULL` 无默认值。
- **修复**：INSERT 列列表补上 `status`，值 `'active'`。
- **迁移**：`036_strategic_intent_layer.sql`

### BUG-037a: PL/pgSQL `format()` 使用 `%d` 占位符

- **现象**：`check_real_publish_gate()` 在 real 模式下报 `unrecognized format() type specifier "d"`。
- **根因**：PL/pgSQL 的 `format()` 函数不支持 `%d`，只支持 `%s`（自动转文本）。
- **修复**：`format('%d/12 ...')` → `format('%s/12 ...')`。
- **迁移**：`037_real_publish_gate_conditions.sql`

### BUG-037b: `real_publish_gate_inputs` 视图列名冲突

- **现象**：`CREATE OR REPLACE VIEW` 报错 `cannot change name of view column`。
- **根因**：migration 004 创建的视图列名为 `rollback_ready`，037 新视图多了 `strategy_unit_maturity` 等列，PostgreSQL 不允许 `CREATE OR REPLACE VIEW` 改列名。
- **修复**：先 `DROP VIEW IF EXISTS` 再 `CREATE VIEW`。
- **迁移**：`037_real_publish_gate_conditions.sql`

### BUG-037c: `v_pkg` record 变量未初始化导致 `ObjectNotInPrerequisiteState`

- **现象**：real 模式调用 `check_real_publish_gate()` 时报 `record "v_pkg" is not assigned yet`。
- **根因**：PL/pgSQL 的 `record` 类型变量在 `SELECT INTO` 未命中时不为 NULL 而是未赋值状态，后续 `v_pkg is not null` 直接报错。
- **修复**：所有引用 `v_pkg` 的条件改用 `p_publication_package_id is not null` 做前置判断，通过 JOIN 查询代替 record 字段访问。
- **迁移**：`037_real_publish_gate_conditions.sql`

---

## 2026-06-03

### BUG-035: ConnectLocked 死锁

- **现象**：Delphi Engine 多线程同时调用 `ArtifactOS_DB()` 获取 PG 连接时死锁。
- **根因**：双重检查锁（double-checked locking）在 Delphi 内存模型下不安全，`FConnLock.Acquire` 在第一次检查后可能被另一个线程抢先。
- **修复**：改用 `TMonitor.Enter` + 单次检查 + lazy init 模式。
- **文件**：`src/core/ArtifactOS.Core.DB.pas`

### BUG-036a: DPR SQL 拼接残留

- **现象**：`ArtifactOS.dpr` 的初始化代码中残留手写 SQL 字符串拼接。
- **根因**：P0 #1 修复 Delphi SQL 注入时遗漏 DPR 中的初始化 SQL。
- **修复**：改为 DeepBase DoQry 参数化调用。
- **文件**：`src/ArtifactOS.dpr`

### BUG-036b: Smoke 测试空异常吞没

- **现象**：Smoke test 的 `except` 块捕获异常后不输出任何信息，导致失败测试静默通过。
- **根因**：`on E: Exception do` 块内无 `WriteLn` 或日志。
- **修复**：异常块内加 `WriteLn(E.ClassName, ': ', E.Message)` + 返回非零退出码。
- **文件**：`tests/run_all_tests.py`

---

## 2026-06-01

### BUG-034: frozen sync 递归死循环

- **现象**：`publication_package` 触发器在冻结同步时无限递归，导致 stack overflow。
- **根因**：跨表状态同步触发器在更新 artifact 时触发 publication_package 更新，后者又触发 artifact 更新，形成循环。
- **修复**：触发器内加 `pg_trigger_depth() = 0` 守卫，防止递归触发。
- **迁移**：`032_cross_table_status_sync.sql`
- **commit**：ab6a4b0

### BUG-033: RealPublishGate smoke 断言不匹配

- **现象**：`test_real_publish_gate.py` 断言 reason 文本为 `"Phase 1A"` 但实际函数返回 `"Phase 1A: shadow run only; ..."`。
- **根因**：函数返回的 reason 字符串比断言预期更长。
- **修复**：断言改为 `assert 'Phase 1A' in result['reason']`。
- **commit**：4c2f293

---

## 2026-05-28

### BUG-031: FireDAC UUID 参数绑定失败

- **现象**：E2E chain 测试中 FireDAC 将 UUID 参数绑定为 `ftWideString` 而非 `ftGuid`，PG 报类型不匹配。
- **根因**：DeepBase DoQry 的 JSON 参数协议对 UUID 字段需要显式标记类型。
- **修复**：预生成 UUID 并作为字符串参数传入，避免 FireDAC 类型推断。
- **commit**：5a0b4a6

---

## 2026-05-27

### BUG-011: InsertId 8 处重复定义

- **现象**：多个 unit 各自定义 `InsertId` 函数，链接时产生重复符号。
- **根因**：各 service unit 独立实现 `function InsertId: string`，未统一到公共 unit。
- **修复**：合并到 `ArtifactOS.Core.Types.pas` 的单一实现，其他 unit 引用。
- **commit**：f64fc6d

### BUG-012: ChainRunner 分层违规

- **现象**：`ChainRunner.pas` 位于 `core/` 目录但直接引用 `services/` 层的 PG 连接函数。
- **根因**：初期快速开发时未遵守 core → services 单向依赖。
- **修复**：ChainRunner 移入 `services/` 目录。
- **commit**：70159dd
