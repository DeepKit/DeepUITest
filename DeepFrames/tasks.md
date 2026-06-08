# DeepFrames Tasks

## 当前状态

**2026-06-07**: 全量 `dcc64` 编译通过 — **0 Error / 0 Warning / 0 Hint**（Delphi 13.1 BDS 37.0，DeepFrames 37 单元 + 测试）。152 tests 全绿（55 core + 97 integration）。Phase 2/3/4/5/6/7 代码全部完成。StepFun LLM/Image 已重构为 DeepBase ILLMClient 委托。可行性评审文档缺口全部补齐。**POC 1 + POC 2 + POC 3a/3b/3c 全项验证通过**（DB2 13 表 + StepFun Chat/Image/TTS/ASR API 全连通 + Remotion 渲染 + CDP 帧捕获 + FFmpeg 音频管线）。凭据已注入 `data/DeepFramesConfig.db`（DPAPI 加密）。

**当前焦点**: POC 3d — Delphi 13.1 运行时 + FireDAC PostgreSQL 连接验证 → POC 3e Worker 协议端到端

已完成工作归档：[history.md](history.md) · Bug 记录：[bugfix.md](bugfix.md)

---

## 下一步

### POC 3：运行时环境验证（当前阶段）

环境状态：Node.js v22.14.0 ✓ · FFmpeg 7.1（libx264/libx265）✓ · Chrome ✓ · Delphi 13.1 ✓

> 已完成: POC 1 (DB2 schema) / POC 2 (StepFun API) / POC 3a-c (Remotion+CDP+FFmpeg) — 详见 [history.md](history.md)

#### 🔄 POC 3d: Delphi 13.1 运行时 + DB2 连接验证

**目标**: 在真实 Delphi 运行时下验证 FireDAC PostgreSQL 连接 + CRUD 操作

**步骤**:
1. [ ] 运行 `compile_test.bat`（或 `build.bat`）生成 `DeepFrames.exe`
2. [ ] 启动主程序，验证 Bootstrap 加载 `data/DeepFramesConfig.db`
3. [ ] 触发 Repository 模块对 DB2 的参数化查询（任意 read/write）
4. [ ] 验证 13 张表的 CRUD（projects / documents / jobs / job_steps / quality_gates / audio_manifests / video_ir / video_jobs / candidate_packages / assets / prompt_versions / bgm_library / style_rules）
5. [ ] 验证 `TIMESTAMPTZ` 时区字段（`+08`）往返一致

**通过标准**: 程序启动无异常 + CRUD 全部返回成功 + DB2 中可查询到写入的行

#### 🔲 POC 3e: Worker 协议 v0 端到端

**目标**: Delphi 主程序 ↔ Node Worker 完整 request/progress/result 流程

**步骤**:
1. [ ] Delphi 主程序生成 `request.json`（含 TaskType、WorkDir、Payload）
2. [ ] 启动 Node Worker 子进程（`CreateProcess`）
3. [ ] Worker 读取 request，执行（如 Remotion 渲染）
4. [ ] Worker 写 `progress.json`（heartbeat + 百分比）
5. [ ] Worker 写 `result.json`（成功/失败 + 输出文件路径）
6. [ ] Delphi 主程序读取 result，更新 DB2 job_steps

**通过标准**: 全链路无错误 + DB2 job_steps 状态正确转换（running → succeeded/failed）

---

### 后续验证

- [ ] **P5.8** 端到端视频链路验证（15 分钟以内视频完整生成链路 — 需 HyperFrames/FFmpeg 真实环境）
- [ ] 端到端 chain 测试（合并到 POC 3d 后验证 — DocumentChain + AgentChain + AudioChain + VideoChain）
- [ ] Chromium 帧捕获时序确定性验证（合并到 POC 3b 后续 deep-dive）
- [ ] Bilibili 候选包端到端验证（cover + title + description + tags + quality + manifest）— 待 P5.8 后

---

## 未完成 Feature

| Phase | 项 | 说明 | 状态 |
|-------|-----|------|------|
| P5 第 9 项 | Bilibili 候选包 | 端到端导出验证 | 待 P5.8 后验证 |
| P7.1 | 商业化打包 | 授权/许可/销售打包（`docs/10.dev-roadmap:159`） | 未开始 |
| P7.8 | H.264 专利许可审查 | `docs/16.legal-法律合规-legal-compliance.md:20` | 未开始 |
| P7.9 | DB3 多机协作 | 多机器协作架构（`docs/10.dev-roadmap:158`） | 未开始 |

---

## 法律/商业前置条件

- [ ] HyperFrames 依赖许可证审查（deadline: Phase 5 end）
- [ ] Remotion 商业许可证审查（如采用，>3 人营利组织需 Company License $0.01/render）

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
