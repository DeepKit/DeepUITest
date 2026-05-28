# ArtifactOS Tasks — Phase 1A 剩余工作

> P0/P1 全部完成 (d699db3)。当前焦点：P2 测试 + P3 产品决策 + Phase 1A 收尾
> 更新: 2026-05-28

---

## P2 — 测试与质量保障（Phase 1A 收尾前完成）

| # | 任务 | 来源 | 状态 |
|---|------|------|------|
| 16 | **状态机白名单全覆盖测试**：31 个合法组合全测 + 6 个阻断级 flags 独立验证 | 李冰 | pending |
| 17 | **异常恢复路径测试**：PG 断开 → 重连 → 验证数据无污染 | 李冰 | pending |
| 18 | **commit 后回滚链路测试**：解封→重建→重跑门禁 5 步流程 | 李冰 | pending |
| 19 | **SourcePack 哈希一致性测试**：验证 27 个核心文件的 file_hash 与标注一致 | 李冰 | pending |
| 20 | **性能基线测试**：`EXPLAIN ANALYZE` 主要查询 + 建必要索引 | 李冰 | pending |
| 21 | **Python 测试接入 DeepBase 门禁**：通过 `Scripts/run_tests.ps1` 调度 Python 烟测 | DeepBase 对齐 | pending |

## P3 — 产品决策（需总设计师裁决）

| # | 任务 | 来源 | 状态 |
|---|------|------|------|
| 22 | **裁决：影子运行 vs 平行运行** | 灵儿 / 仙儿 | pending |
| 23 | **裁决：Phase 1A 表数**：~30（盘古）vs ~40（灵儿）vs 全表只用于主链 | 盘古 / 灵儿 | pending |
| 25 | **裁决："不做 MVP"条款修正**：灵儿建议改为"架构不欠债，功能做楔子" | 灵儿 | pending |

## P4 — DeepBase 集成收尾（d699db3 之后的新工作）

| # | 任务 | 说明 | 状态 |
|---|------|------|------|
| 26 | **全量迁移 SQL 到 ExecuteJson 参数化**：ShadowRun/CaseRunner/Dashboard 等服务层的字符串拼接 SQL 全部改为 DoQry JSON 参数 | 安全收尾 | pending |
| 27 | **DeepBase 包引用模式确认**：确认 DeepBaseCore/DeepBaseServices/DeepBaseGovernance bpl 是否需要运行时注册，还是纯源码编译 | 编译链 | pending |
| 28 | **ArtifactOS.exe 运行时冒烟**：实际运行 exe 验证 DeepBase 初始化 → PG 连接 → shadow run 全链路 | 集成验证 | pending |
| 29 | **CI 脚本：dcc64 自动编译**：编写 `build.bat` 封装 dcc64 调用，替代手动 MSBuild | DevOps | pending |

## 数据库落点

```text
DB1 ConfigDB (SQLite)  ← DeepBase 自动管理 + ArtifactOS 运行参数
DB2 本地业务库 (SQLite) ← Phase 1B 按需创建
DB3 远程业务库 (PG)     ← artifactos（正式）/ artifactos_test（测试，已存在）
DB4 生产后端            ← 不直连
```
