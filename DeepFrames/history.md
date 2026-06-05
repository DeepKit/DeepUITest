# DeepFrames Development History

## 2026-06-05 — 全量编译通过（0 Error / 0 Fatal）

37 个 Pascal 单元首次全量 `dcc64` 编译成功。修复 8 个文件的 9 类编译错误。

### 修复摘要

| 文件 | 问题 | 修复 |
|------|------|------|
| StepFun.pas | ASR 类体重复粘贴 | 删除孤立类体 |
| StepFun.pas | `HTTP.ResponseCode` 不存在 | 改为 `Resp.StatusCode` |
| StepFun.pas | 局部变量 `Format` 遮蔽函数 | 重命名为 `Fmt` |
| Fake.pas | `TFakeImageProvider` 在 impl 段 | 移至 interface 段 |
| EventLog.pas | 缺 `Generics.Collections` + `>>` 歧义 | 添加 uses + 空格分隔 `> >` |
| AgentChain.pas | 多余 `var/begin` 嵌套 | 删除 + 提升 `Gate2Score` 声明 |
| AudioProcessor.pas | `out` 参数在默认参数后 + `GetString` 类型不匹配 | 参数重排 + `TBytes` 中转 |
| SubtitleEngine.pas | 中文标点不能放 `set of Char` | 改为常量字符串 + `System.Pos()` |
| AssetRetention.pas | `Protected` 保留字 + 缺变量 | `&Protected` + 显式声明 `V` |

详细 Bug 分析：[bugfix.md](bugfix.md)

---

## 2026-06-04 — 工程底座构建（完整 36 个 Pascal 单元）

从 fake skeleton 到完整工程底座。所有 Phase 2/3/4/6 任务完成，Phase 5 完成 7/9，POC 3 完成，Phase 7 完成 P7.3+P7.5+Image provider。

### 新建模块（21 个）

| 层 | 文件 | 说明 |
|----|------|------|
| Provider | `Types.pas` | TTokenUsage, TProviderRunMetrics, TTS/ASR/Image 类型 |
| Provider | `Intf.pas` | IDeepFramesLLM/TTS/ASR/ImageProvider (4 个接口) |
| Provider | `Registry.pas` | 单例注册表，fake↔stepfun 切换 |
| Provider | `Fake.pas` | TFakeLLM/TTS/ASR/ImageProvider（回归夹具） |
| Provider | `StepFun.pas` | 真实 HTTP LLM+TTS+ASR+Image + stub 降级 |
| Shared | `JsonSchema.pas` | JSON Schema 校验 + auto-repair |
| Domain | `VoiceProfile.pas` | 角色→音色映射 + TTS instruction builder |
| Workflow | `VideoCompiler.pas` | Timeline/IR 编译 |
| Workflow | `GateEvaluator.pas` | Gate 1/2/3a/3b/4 pass/warn/fail |
| Workflow | `StyleKeeper.pas` | 视觉一致性规则引擎（不调 LLM） |
| Workflow | `Resume.pas` | 断点续跑 + retry status |
| Workflow | `PromptVersion.pas` | SHA256 版号 + 可复现性检查 |
| Workflow | `AudioProcessor.pas` | FFmpeg resample/loudnorm/concat/Execute |
| Workflow | `SubtitleEngine.pas` | SRT/VTT/HF 字幕 + 安全区 |
| Workflow | `AssetRetention.pas` | 102C 资产策略 + 级联保护 |
| Workflow | `PackageExporter.pas` | 候选包磁盘导出 + source_trace |
| Workflow | `WorkerProtocol.pas` | Worker 协议 v0 (launch/monitor/cancel) |
| Workflow | `ReadinessChecker.pas` | Adapter readiness check (schema/pipeline/output/E2E) |
| Workflow | `DocumentExport.pas` | 文档导出 (JSON/text/markdown + 完整版本链) |

### Phase 完成度

| Phase | 完成 | 说明 |
|-------|:---:|------|
| **Phase 1** 桌面骨架 | ✅ | Bootstrap, MainForm, DeepShell |
| **Phase 2** 文档链 | ✅ 9/9 | DocumentChain + Gate 1 + accuracy |
| **Phase 3** Agent 链 | ✅ 8/8 | 5 agents + Style Keeper + prompts |
| **Phase 4** 音频线 | ✅ 11/11 | TTS/ASR HTTP + FFmpeg + loudnorm |
| **Phase 5** 视频线 | 7/9 | SubtitleEngine + FFmpeg mux + Gate 3b |
| **Phase 6** 候选包 | ✅ 5/5 | PackageExporter + 102C + source_trace |
| **POC 3** Worker | ✅ | WorkerProtocol + heartbeat + cancel |
| **Phase 7** 扩展 | 3/9 | P7.3 多平台 + P7.5 readiness + Image provider |
| **POC 1-2** | — | DB2/StepFun 连通性待真实环境 |

### 能力矩阵

| 能力 | Fake | StepFun (Key 就绪) |
|------|:---:|:---:|
| LLM Chat | ✅ stub | ✅ 真实 HTTP POST |
| TTS | ✅ stub | ✅ 真实 HTTP + binary save + 451 + 括号转义 |
| ASR | ✅ stub | ✅ 真实 SSE 流解析 |
| Image Gen | ✅ stub | ✅ 真实 HTTP /images/generations |
| FFmpeg | ✅ stub | ✅ 真实 CreateProcess + 管道 |
| Gate | ✅ pass/warn/fail | ✅ 完整门控 + blocked_review |
| Schema | ✅ auto-repair | ✅ 校验 + 修复 |

### DB Platforms (7)

bilibili, douyin, kuaishou, xiaohongshu, wechat_video, youtube, ximalaya

---

## 2026-06-04 — Bugfix: TProcess → CreateProcess

**P0 编译阻断** — `AudioProcessor.RunFFmpeg` 使用 FreePascal `TProcess`，Delphi 不支持。改用 `Winapi.Windows.CreateProcess` + 匿名管道。

提交：`8a98217 fix(DeepFrames): replace TProcess with WinAPI CreateProcess in AudioProcessor`

---

## 2026-06-03 — 文档评审修复（T1-T6, F1-F3）

### P0：开工前必须补齐

- **T1 Gate → 对象状态驱动矩阵** ✅
- **T2 accuracy_report 与 Gate 2 QA 独立数据契约** ✅
- **T3 102C 资产清理策略细化** ✅
- **T4 TTS 451 音频线闭环处理** ✅

### P1：建议补齐

- **T5 渲染后端许可证决策点** ✅
- **T6 content_type adapter 就绪诊断规格** ✅

### 工程实现前最终校正

- **F1 Gate / 状态机最终一致性** ✅
- **F2 音频 / API 最终一致性** ✅
- **F3 文档就绪度最终一致性** ✅

---

## 2026-06-04 — Phase 1-7 桌面骨架实现（fake providers）

提交：`2e92248`

17 个 Pascal 文件 + 6 个 PostgreSQL migration 文件。
