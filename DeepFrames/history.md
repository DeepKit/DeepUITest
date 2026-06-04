# DeepFrames Development History

## 2026-06-04 — 工程底座构建（22 次提交，33 个 Pascal 单元）

从 fake skeleton 到完整工程底座：Provider 抽象层、真实 API 调用、全链路 Workflow 工具。

### 提交序列

| # | 提交 | 内容 |
|---|------|------|
| 1 | `17b6cf0` | **Provider 抽象层** — Types/Intf/Registry/Fake/StepFun，5 workflow 重构 |
| 2 | `c267c84` | **StepFun LLM 真实 HTTP** — POST /chat/completions + stub 降级 |
| 3 | `ad5d697` | **DocumentChain → Provider** — source_document 注入 + FindSourceDocument |
| 4 | `a3a6ccb` | **JSON Schema 校验** — TJsonSchemaValidator + auto-repair + AgentChain output schemas |
| 5 | `15a24d0` | **Gate 1-4 门控** — TGateEvaluator pass/warn/fail + blocked_review |
| 6 | `2dbb55e` | **Style Keeper + Resume + PromptVersion** — P3.6+P2.9+P3.7 |
| 7 | `f599b0b` | **TTS + ASR 真实 HTTP** — P4.1-P4.7 |
| 8 | `360d8fc` | **FFmpeg AudioProcessor** — resample + loudnorm two-pass |
| 9 | `709bee7` | **SubtitleEngine + AssetRetention** — SRT/VTT/HF + 102C 策略 |
| 10 | `3b87531` | **PackageExporter** — 音频/视频候选包磁盘导出 |
| 11 | `8233998` | **Worker protocol v0** — CreateProcess + heartbeat + cancel |
| 12 | `8a98217` | **Bugfix: TProcess → CreateProcess** — FreePascal 类在 Delphi 不可用 |
| +10 docs | | tasks.md / history.md / bugfix.md 对齐提交 |

### Phase 完成度

| Phase | 完成 | 剩余 |
|-------|:---:|------|
| **Phase 2** 文档链 | ✅ 9/9 | — |
| **Phase 3** Agent 链 | ✅ 8/9 | — |
| **Phase 4** 音频线 | ✅ 11/11 | — |
| **Phase 5** 视频线 | 7/9 | P5.1 许可证、P5.8 验证（需外部依赖） |
| **Phase 6** 候选包 | ✅ 5/5 | — |
| **POC 3** Worker 协议 | ✅ | — |
| **POC 1-2** | — | DB2/StepFun 连通性待真实环境 |

### 新建模块（16 个）

| 层 | 文件 | 说明 |
|----|------|------|
| Provider | `Types.pas` | TTokenUsage, TProviderRunMetrics, TTS/ASR 类型 |
| Provider | `Intf.pas` | IDeepFramesLLM/TTS/ASRProvider |
| Provider | `Registry.pas` | 单例注册表，fake↔stepfun 切换 |
| Provider | `Fake.pas` | TFakeLLM/TTS/ASRProvider（回归夹具） |
| Provider | `StepFun.pas` | 真实 HTTP LLM+TTS+ASR + stub 降级 |
| Shared | `JsonSchema.pas` | JSON Schema 校验 + auto-repair |
| Workflow | `VideoCompiler.pas` | Timeline/IR 编译（确定性） |
| Workflow | `GateEvaluator.pas` | Gate 1/2/3a/3b/4 pass/warn/fail |
| Workflow | `StyleKeeper.pas` | 视觉一致性规则引擎（不调 LLM） |
| Workflow | `Resume.pas` | 断点续跑 + retry status 检查 |
| Workflow | `PromptVersion.pas` | SHA256 版号 + 可复现性检查 |
| Workflow | `AudioProcessor.pas` | FFmpeg resample/loudnorm/concat/mux |
| Workflow | `SubtitleEngine.pas` | SRT/VTT/HF 字幕引擎 + 安全区 |
| Workflow | `AssetRetention.pas` | 102C 资产策略 + 级联保护 |
| Workflow | `PackageExporter.pas` | 候选包磁盘导出 + source_trace |
| Workflow | `WorkerProtocol.pas` | Worker 协议 v0 (launch/monitor/cancel) |

---

## 2026-06-03 — 文档评审修复（第二轮外部评价 + 工程实现前最终校正）

### P0 — 开工前必须补齐

- **T1 Gate → 对象状态驱动矩阵** ✅
- **T2 accuracy_report 与 Gate 2 QA 独立数据契约** ✅
- **T3 102C 资产清理策略细化** ✅
- **T4 TTS 451 音频线闭环处理** ✅

### P1 — 建议补齐

- **T5 渲染后端许可证决策点** ✅
- **T6 content_type adapter 就绪诊断规格** ✅

### 工程实现前最终校正

- **F1 Gate / 状态机最终一致性** ✅ — done/ready 边界、skipped/cancelled 恢复、preprocess job_type
- **F2 音频 / API 最终一致性** ✅ — 48kHz AAC、loudnorm 双遍、TTS 451
- **F3 文档就绪度最终一致性** ✅ — 评审索引、Phase 7 adapter、H.264/AAC 合规、DB UTC

---

## 2026-06-04 — Phase 1-7 桌面骨架实现（fake providers）

提交：`2e92248 feat(DeepFrames): implement Phase 1-6 desktop shell with fake providers`

17 个 Pascal 文件：Bootstrap、Services、MainForm、Domain/Types/Project、Consts、Connection、Migrations、Repository、Preprocess/DocumentChain/AgentChain/AudioChain/VideoChain/PackageChain/ExtensionChain。6 个 PostgreSQL migration 文件。