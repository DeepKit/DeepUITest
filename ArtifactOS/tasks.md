# ArtifactOS Tasks — Phase 1 开发主链

> 更新: 2026-06-08
> 已完成任务归档至 `history.md`，已修复 bug 归档至 `bugfix.md`
> 数据库: 50 migrations, 121+ tables (artifactos + media_publish schemas)
> **Phase 1 (L1-L4) + Phase 2 全部完成** — 完整闭环 ✅
> P3 裁决：#22A(影子运行) · #23A(全量建表) · #25C(七层闭合度) ✅ 全部落定

---

## 当前状态

**Phase 1 + Phase 2 全部完成。** 等待集成测试与真实环境部署验证。

所有任务已归档至 [history.md](history.md)。

---

## 待验证项

| # | 验证项 | 状态 | 说明 |
|---|--------|------|------|
| V1 | 集成测试（L1-L4 全链路） | 🔲 | 待真实环境 |
| V2 | ShadowRun 7天自动调度实测 | 🔲 | 待真实环境 |
| V3 | RealPublishGate 12 条件实测 | 🔲 | 待真实环境 |

---

## 数据库落点

```text
DB1 ConfigDB (SQLite)  ← DeepBase 自动管理 + ArtifactOS 运行参数
DB2 本地业务库 (SQLite) ← Phase 1B 按需创建
DB3 远程业务库 (PG)     ← artifactos（正式）/ artifactos_test（测试）  50/50 migrations, 121+ tables
DB4 生产后端            ← 不直连
```

---

## 依赖关系

```text
L1 补齐（#56-58）──→ L2 流水线（#59-65）──→ L3 自治闭环（#66-73）──→ L4 反馈进化（#74-79）──→ Phase 2（#80-82）
  ✅ 已完成            ✅ 已完成             ✅ 已完成              ✅ 已完成              ✅ 已完成
```

---

## 开发红线

1. 不要把业务表写入 DB1 ConfigDB
2. 不要把 API Key 写入 `.env`、JSON、INI、Registry、日志或 DB2
3. 不要让 UI Form 直接写业务表；必须通过 application service
4. 不要让 worker 直接访问 DB1 / DB2 或读取 `shot_document`
5. 不要绕过 DeepBase 配置、日志、密钥和 JobQueue 体系
6. 不要把 Node / TypeScript 做成主程序；它们只能作为 worker
7. 不要原地覆盖文档、manifest 或候选包；返工必须产生新 version
8. 不要把黄灯当阻塞；黄灯记录并提醒，红灯才进入 `blocked_review`
9. 不要混淆业务对象状态和资产状态
10. 不要跳过 `schema_version`；所有 JSON payload 必须版本化
