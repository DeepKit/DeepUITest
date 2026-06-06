# DeepFrames Tasks

## 当前状态

**2026-06-06**: 全量 `dcc64` 编译通过 — **0 Error / 0 Warning / 0 Hint**（DeepFrames 37 单元 + 测试）。152 tests 全绿（55 core + 97 integration）。Phase 2/3/4/5/6/7 代码全部完成。StepFun LLM/Image 已重构为 DeepBase ILLMClient 委托。

已完成工作归档：[history.md](history.md) · Bug 记录：[bugfix.md](bugfix.md)

---

## 下一步

### A. POC 验证（需真实环境）

#### POC 1：DB2 PostgreSQL 连接验证

> 来源：`docs/ENGINEERING_HANDOFF.md` §5
> 代码入口：`src/Persistence/DeepFrames.Persistence.Connection.pas` → `LoadProfile`
> 密钥通过 `DeepBase.Security.LoadSecret` 加载，不写入配置文件

需要填写：

| 字段 | 默认值 | 你的值 |
|------|--------|--------|
| **Host** | `127.0.0.1` | ________ |
| **Port** | `5432` | ________ |
| **Database** | `DeepFramesData` | ________ |
| **User** | `deepframes` | ________ |
| **Password** | 通过 secret store `deepframes/db2` | ________ |

验证项：
- [ ] Delphi + FireDAC + DeepBase Persistence 连接 DB2 并创建/查询表
- [ ] 所有时间字段 `TIMESTAMPTZ`，UTC 写入，UI 本地时区显示
- [ ] Repository 全部使用参数化查询
- [ ] 重复 logical key 不产生重复任务

#### POC 2：StepFun API 连通性验证

> 代码入口：`src/Provider/DeepFrames.Provider.StepFun.pas`
> LLM/Image: 通过 DeepBase ILLMClient 配置（`LLMAdmin.AddProvider`）
> TTS/ASR: Key 通过 `DeepBase.Security.LoadSecret` 加载，存入 secret store

需要填写：

| 字段 | 配置方式 | 用途 | 你的值 |
|------|----------|------|--------|
| **Step Plan Key** | DeepBase LLM provider 配置 | LLM Chat + Image（通过 `ILLMAdmin`） | ________ |
| **Step Plan Key** | `deepframes/stepfun/step_plan_key` | TTS（原始 HTTP） | ________ |
| **Standard Key** | `deepframes/stepfun/standard_key` | ASR SSE（原始 HTTP，`/v1`） | ________ |

验证项：
- [ ] DeepBase LLM 配置 StepFun provider 后 Chat 连通
- [ ] DeepBase LLM 配置后 Image generation 连通
- [ ] Step Plan 端点 TTS 连通（原始 HTTP）
- [ ] 标准端点 ASR SSE 连通（/v1，非 /step_plan/v1）
- [ ] 两套 Key 不互通确认
- [ ] ASR SSE 实体验证：Delta 事件格式、时间戳字段路径、Done 标记、Error 格式

#### POC 3：Worker 协议 v0（代码完成，需真实渲染）

- [x] 协议代码完成（`TWorkerProtocol`，I3 测试 21 项全绿）
- [ ] 真实 HyperFrames/Remotion worker 接入验证

#### P5.8：端到端视频链路验证

- [ ] **P5.8** 验证 15 分钟以内视频完整生成链路（需 HyperFrames/FFmpeg 真实环境）

---

### B. 未完成 Feature（代码侧）

| Phase | 项 | 说明 | 状态 |
|-------|-----|------|------|
| P5 | 第 9 项 | Bilibili 候选包端到端验证（cover + title + description + tags + quality + manifest） | 待 P5.8 后验证 |
| P7.1 | 商业化打包 | 授权/许可/销售打包（`docs/10.dev-roadmap:159`） | 未开始 |
| P7.9 | DB3 多机协作 | 多机器协作架构（`docs/10.dev-roadmap:158`） | 未开始 |

---

### C. 文档缺口（来自可行性评审）

> 来源：`docs/review-report-2026-06-02-feasibility.md`

- [ ] `docs/04.video` — 缺帧捕获实现细节（JPEG vs PNG、Chromium session 分块）
- [ ] `docs/05.audio` — `loudnorm` 需更新为两 pass 文档
- [ ] `docs/07.platform` — 缺 H.264 编码参数（profile/level/preset/GOP/B-frames/pixel format）
- [ ] `docs/11.e2e` — 镜头数误导（显示 9 shots for 126 chars，非 3800 chars 全文）
- [ ] Chromium 帧捕获时序确定性验证 — 最高技术风险（`review-report` lines 26-44）

---

### D. 法律/商业前置条件

- [ ] **P7.8** H.264 专利许可审查（`docs/16.legal-法律合规-legal-compliance.md:20`）
- [ ] HyperFrames 依赖许可证审查（deadline: Phase 5 end）
- [ ] Remotion 商业许可证审查（如采用）

---

### E. 技术债务

- [x] 编译验证：0 Error / 0 Warning / 0 Hint（2026-06-06）
- [x] 单元测试：55 tests，7 模块覆盖
- [x] 集成测试：97 tests（I1-I5 全路径）
- [ ] 端到端 chain 测试（需 DB2 连接）
- [x] EventLog → DeepBase.Log 真实接入（2026-06-05）
- [x] 编译警告清零（2026-06-06）
- [x] StepFun LLM/Image → DeepBase ILLMClient 委托重构（2026-06-06）

---

## 已完成 Phase 清单

| Phase | 完成 | 说明 |
|-------|:---:|------|
| **Phase 1** 桌面骨架 | ✅ | Bootstrap, MainForm, DeepShell |
| **Phase 2** 文档链 | ✅ 9/9 | DocumentChain + Gate 1 + accuracy |
| **Phase 3** Agent 链 | ✅ 8/8 | 5 agents + Style Keeper + prompts |
| **Phase 4** 音频线 | ✅ 11/11 | TTS/ASR HTTP + FFmpeg + loudnorm |
| **Phase 5** 视频线 | 7/9 | SubtitleEngine + FFmpeg mux + Gate 3b（P5.8 + 候选包验证待真实环境） |
| **Phase 6** 候选包 | ✅ 5/5 | PackageExporter + 102C + source_trace |
| **Phase 7** 扩展 | 7/10 | P7.2~P7.7 + P7.10 完成；P7.1 + P7.8 + P7.9 待做 |

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
