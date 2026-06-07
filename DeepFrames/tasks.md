# DeepFrames Tasks

## 当前状态

**2026-06-07**: 全量 `dcc64` 编译通过 — **0 Error / 0 Warning / 0 Hint**（DeepFrames 37 单元 + 测试）。152 tests 全绿（55 core + 97 integration）。Phase 2/3/4/5/6/7 代码全部完成。StepFun LLM/Image 已重构为 DeepBase ILLMClient 委托。可行性评审文档缺口全部补齐。**POC 1 + POC 2 全项验证通过**（DB2 13 表 + StepFun Chat/Image/TTS/ASR API 全连通）。凭据已注入 `data/DeepFramesConfig.db`（DPAPI 加密）。

已完成工作归档：[history.md](history.md) · Bug 记录：[bugfix.md](bugfix.md)

---

## 下一步

### A. POC 验证（需真实环境）

#### ✅ POC 1：DB2 PostgreSQL 连接验证（2026-06-07 通过）

PostgreSQL 13 表 + 16 索引创建完毕；FireDAC 编译通过。剩余：Repository 参数化查询端到端验证（需 Delphi 运行时）。详情：[history.md](history.md)

#### ✅ POC 2：StepFun API 连通性验证（2026-06-07 全项通过）

Chat（step-3.7-flash）/ Image（step-image-edit-2）/ TTS / ASR SSE 全连通。一个 Step Plan Key 覆盖全部能力。详情：[history.md](history.md)

#### POC 3：运行时环境验证（当前阶段）

环境状态：Node.js v22.14.0 ✓ · FFmpeg 7.1（libx264/libx265）✓ · Chrome ✓ · Delphi 13.1 ✓

| # | 验证项 | 状态 | 说明 |
|---|--------|:----:|------|
| 3a | Node.js + Remotion 环境 | ✅ | Remotion 4.0.473 渲染 1920x1080@30fps → H.264 MP4 成功（详情：history.md） |
| 3b | Chrome CDP 帧捕获确定性 | ✅ | puppeteer-core 30 帧 1920x1080 全精确匹配（HSL 色相 0→360° 验证） |
| 3c | FFmpeg 音频管线验证 | ✅ | 24k→48k + loudnorm 两 pass + AAC 192k 全通（发现 linear=true 会翻倍采样率，需 -ar 显式约束） |
| 3d | Delphi 13.1 运行时 + DB2 连接 | 🔲 | `compile_test.bat` → `DeepFrames.exe` → FireDAC 连接 → CRUD 验证 |
| 3e | Worker 协议 v0 端到端 | 🔲 | Delphi 主程序 → request.json → Node worker → progress → result → DB2 更新 |

> 来源：`docs/ENGINEERING_HANDOFF.md` §5 POC 3 + `docs/review-report-2026-06-02-feasibility.md` §风险表

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
- [ ] Chromium 帧捕获时序确定性验证 — 最高技术风险（`review-report` lines 26-44）— 需真实环境 → 合并到 POC 3b

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
- [ ] 端到端 chain 测试（需 DB2 连接）→ 合并到 POC 3d
- [x] EventLog → DeepBase.Log 真实接入（2026-06-05）
- [x] 编译警告清零（2026-06-06）
- [x] StepFun LLM/Image → DeepBase ILLMClient 委托重构（2026-06-06）
- [x] ASR 端点修正：Standard → Step Plan（POC 2d 验证，2026-06-07）

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
