# DeepFrames Tasks

## 当前状态

**2026-06-07**: 全量 `dcc64` 编译通过 — **0 Error / 0 Warning / 0 Hint**（DeepFrames 37 单元 + 测试）。152 tests 全绿（55 core + 97 integration）。Phase 2/3/4/5/6/7 代码全部完成。StepFun LLM/Image 已重构为 DeepBase ILLMClient 委托。可行性评审文档缺口全部补齐。**POC 1 + POC 2 验证通过**（DB2 13 表创建成功 + StepFun Chat/Image API 连通）。凭据已注入 `data/DeepFramesConfig.db`（DPAPI 加密）。

已完成工作归档：[history.md](history.md) · Bug 记录：[bugfix.md](bugfix.md)

---

## 下一步

### A. POC 验证（需真实环境）

#### POC 1：DB2 PostgreSQL 连接验证 ✅ 已通过（2026-06-07）

> 来源：`docs/ENGINEERING_HANDOFF.md` §5
> 代码入口：`src/Persistence/DeepFrames.Persistence.Connection.pas` → `LoadProfile`

凭据配置（已注入 `data/DeepFramesConfig.db`）：

| 字段 | 值 |
|------|-----|
| **Host** | `127.0.0.1` |
| **Port** | `5432` |
| **Database** | `DeepFramesData` |
| **User** | `fuyi01` |
| **Password** | `secret://deepframes/db2`（DPAPI 加密存于 Config.db） |

验证结果：
- [x] PostgreSQL 连接成功，13 表 + 16 索引创建完毕
- [x] `TIMESTAMPTZ` 字段正常（`+08` 时区）
- [x] 参数化查询工作正常（`PREPARE/EXECUTE`）
- [x] Delphi FireDAC 连接验证 — 编译通过（0 Warning 0 Hint），含 `DeepBase/Features` 路径
- [ ] Repository 参数化查询端到端验证（需 Delphi 运行时）

#### POC 2：StepFun API 连通性验证 ✅ 已通过（2026-06-07）

> 代码入口：`src/Provider/DeepFrames.Provider.StepFun.pas`
> LLM/Image: 通过 DeepBase ILLMClient 配置

凭据配置（已注入 `data/DeepFramesConfig.db`）：

| 字段 | 值 |
|------|-----|
| **Step Plan Key** | `secret://deepframes/stepfun/step_plan_key`（DPAPI 加密） |
| **LLM Provider** | `stepfun` → `step-3.5-flash` / `step-3.7-flash` |
| **Image Model** | `step-image-edit-2` |
| **TTS Model** | `stepaudio-2.5-tts`（原始 HTTP，key via secret store） |
| **ASR Model** | `stepaudio-2.5-asr`（`/v1` 端点，需 Standard Key） |

验证结果：
- [x] Chat Completion（`step-3.5-flash`）连通 ✓ — 支持 reasoning 模式（`message.reasoning` 字段）
- [x] Image Generation（`step-image-edit-2`）连通 ✓ — 返回 URL 格式
- [x] 9 个可用模型确认（`/models` endpoint）
- [x] TTS（`stepaudio-2.5-tts`）连通 ✓ — `cixingnansheng` voice + `instruction` 参数均正常，输出 MP3 约 100KB/句
- [ ] ASR SSE（`stepaudio-2.5-asr`）— Step Plan Key 在 `/v1` 端点触达但返回 402（quota exceeded），需 Standard Key 或充值
- [x] 两套 Key 隔离确认 — Step Plan Key 可触达 `/v1` 端点但不互通（402 vs 401）
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

- [x] `docs/04.video` — 帧捕获实现细节（时间虚拟化 + session 分块 + JPEG vs PNG + 确定性验证）
- [x] `docs/05.audio` — `loudnorm` 两 pass（已存在于 lines 242-247）
- [x] `docs/07.platform` — H.264 编码参数（profile/level/preset/GOP/B-frames/pixel format/码率控制）
- [x] `docs/11.e2e` — 镜头数澄清（126 字节选 → 9 shots；全文 3800 字 → 180-200 shots）
- [x] `docs/08.quality` — 降级方案改为"模板化布局 + 字幕"（非纯色背景）
- [ ] Chromium 帧捕获时序确定性验证 — 最高技术风险（`review-report` lines 26-44）— 需真实环境

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
