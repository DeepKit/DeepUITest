# DeepFrames Tasks

## 当前状态

**2026-06-05**: 全量 `dcc64` 编译通过（0 Error）。37 个 Pascal 单元。152 tests 全绿（55 core + 97 integration）。Phase 2/3/4/6 全部完成，Phase 5 剩余 2 项，Phase 7 剩余 4 项，集成测试 I1-I5 完成。下一步：POC 验证 + Phase 5/7 收尾。

已完成工作归档：[history.md](history.md) · Bug 记录：[bugfix.md](bugfix.md)

---

## 下一步：POC 验证

### POC 验证（需真实环境）

> 来源：`docs/ENGINEERING_HANDOFF.md` §5

#### POC 1：DB2 PostgreSQL 连接验证

- [ ] Delphi + FireDAC + DeepBase Persistence 连接 DB2 并创建/查询表
- [ ] 所有时间字段 `TIMESTAMPTZ`，UTC 写入，UI 本地时区显示
- [ ] Repository 全部使用参数化查询
- [ ] 重复 logical key 不产生重复任务

#### POC 2：StepFun API 连通性验证

- [ ] Step Plan 端点 Chat + TTS 连通
- [ ] 标准端点 ASR SSE 连通（/v1，非 /step_plan/v1）
- [ ] 两套 Key 不互通确认
- [ ] ASR SSE 实体验证：Delta 事件格式、时间戳字段路径、Done 标记、Error 格式

---

## Phase 5 剩余（2 项）

- [ ] **P5.1** 确认 HyperFrames 依赖许可证
- [ ] **P5.8** 验证 15 分钟以内视频完整生成链路（需 HyperFrames + FFmpeg 真实环境）

---

## Phase 7 剩余（4 项）

- [ ] **P7.1** Remotion 商业许可复核（引入前必须）
- [ ] **P7.8** H.264 / AAC 编解码器专利和平台发布合规复核
- [ ] **P7.9** 商业化、授权、销售包装
- [ ] **P7.10** EventLog → DeepBase.Log 接入（当前为内存 stub）

### Phase 7 已完成

- [x] **P7.2** Remotion worker 实现（`workers/remotion/`）
- [x] **P7.3** 多平台适配
- [x] **P7.4** 多比例视频支持（`TVideoAspect`）
- [x] **P7.5** ReadinessChecker
- [x] **P7.6** BGM 与音乐库（`TBgmManager`）
- [x] **P7.7** ArtifactOS 深度联动（`TArtifactOSBridge`）

---

## 技术债务

- [x] 编译验证：所有 `.pas` 文件通过 Delphi 编译（2026-06-05 通过）
- [x] 单元测试：Repository、Workflow、Domain 层（55 tests，7 模块覆盖）
- [x] 集成测试：I1-I5 全路径（97 tests，Provider+Schema+Gate+Worker+Error+Logging）
- [ ] 端到端 chain 测试（需 DB2 连接）
- [ ] EventLog → DeepBase.Log 真实接入

---

## 开发红线

> 来源：`docs/ENGINEERING_HANDOFF.md` §6

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
