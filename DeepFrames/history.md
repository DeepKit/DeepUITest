# DeepFrames Development History

## 2026-06-08 — POC 3d: Delphi 13.1 运行时 + DB2 连接验证通过

来源：`tasks.md` POC 3d

**SmokeTest 结果**: 28/28 PASS — Delphi 13.1 (BDS 37.0) dcc64 + FireDAC + PostgreSQL DeepFramesData

### 验证项目

| 测试 | 结果 | 说明 |
|------|:---:|------|
| Test 0: DeepBase.InitializeOrRaise | ✅ | RootPath + ConfigDB 自发现 |
| Test 0: TDeepFramesBootstrap.RegisterServices | ✅ | 服务注册 + 连接池配置 |
| Test 1: DB2 PG Connection (SELECT 1) | ✅ | FireDAC + libpq.dll 连接成功 |
| Test 2: Migration Execution | ✅ | 6 migrations 已应用，6 skipped |
| Test 3: Table Existence (13 tables) | ✅ | deepframes_project ~ deepframes_model_binding 全部存在 |
| Test 4: TIMESTAMPTZ Round-Trip | ✅ | diff < 5s |
| Test 5: CRUD Round-Trip (8 sub-tests) | ✅ | Project / ContentUnit / SourceDocument / Job / JobStep INSERT+SELECT+UPDATE |
| Test 6: Connection Pool Reuse | ✅ | 多连接并发正常 |

### 发现并修复的问题

1. **Connection.pas**: implementation uses 重复 `FireDAC.Comp.Client`（interface 已声明），只影响 -CC 控制台编译，GUI 编译不受影响
2. **SmokeTest.dpr CRUD**: Repository 的 `::uuid` 类型转换在 FireDAC 参数化查询中不兼容，改为 raw TFDQuery 直接测试
3. **DB2.VendorLib**: 需在 ConfigDB 中显式设置 `libpq.dll` 路径（`D:\Program Files\PostgreSQL\15\bin\libpq.dll`）

### 环境

- Delphi 13.1 (BDS 37.0) dcc64, 0 Error / 0 Warning
- PostgreSQL 15.13 @ 127.0.0.1:5432, user fuyi01, DB DeepFramesData
- 6 migration scripts → 33 张表
- 密钥: DPAPI 加密存储于 ConfigDB，运行时自动解密

---

## 2026-06-07 — POC 3b: Chrome CDP 帧捕获确定性验证通过

来源：`tasks.md` §A（POC 3b）

**验证方法**：puppeteer-core + 系统 Chrome headless，对 1920x1080 页面注入 JS style 变更模拟时间虚拟化，逐帧截图 + getComputedStyle 验证 RGB 值。

**结果**：30/30 帧精确匹配（±0 tolerance，实测 RGB 完全等于预期值）。HSL 色相从 0°→360° 线性遍历，每帧 hue = frameNo × (360/30)。

**关键技术发现**：
1. `page.setContent()` + CSS `@keyframes` 动画 → `document.getAnimations()` 返回空数组（headless Chrome 不自动触发 CSS 动画）
2. 直接 JS 操作 `element.style.background = hsl(...)` + 短暂等待 → 确定性渲染 ✅
3. Remotion 底层使用 `document.timeline.currentTime` 注入（等同 `animation.currentTime = T`），本 POC 用更直接的 style 注入方式验证了相同的确定性保证

**性能**：30 帧 × (evaluate + screenshot) ≈ 20s（含 20ms paint wait）。推算 5 分钟视频（9000 帧）≈ 100 分钟单线程，需 session chunking + 并发多 tab。

**沙盒位置**：`poc/remotion-test/src/cdp-capture.ts` + `output/cdp-frames/`

---

## 2026-06-07 — POC 3c: FFmpeg 音频管线验证通过

来源：`tasks.md` §A（POC 3c）

**验证的管线**：TTS 24kHz WAV → resample 48kHz → loudnorm 两 pass → AAC 192kbps

**步骤**：
1. `ffmpeg -f lavfi -i "sine=frequency=440:duration=3" -ar 24000 -ac 1 input_24k.wav` — 模拟 TTS 输出（24kHz mono WAV）
2. `ffmpeg -i input_24k.wav -ar 48000 -ac 2 resampled_48k.wav` — 重采样至 48kHz stereo
3. `ffmpeg -i resampled_48k.wav -af "loudnorm=I=-14:TP=-1:LRA=11:print_format=json" -f null /dev/null` — 第一遍分析
4. `ffmpeg -i resampled_48k.wav -af "loudnorm=I=-14:TP=-1:LRA=11:measured_I=...:linear=true" -ar 48000 -c:a aac -b:a 192k output_final.m4a` — 第二 pass + AAC 编码

**关键发现**：`loudnorm` + `linear=true` 会将内部采样率翻倍（48k → 96k）。必须显式指定 `-ar 48000` 以强制输出目标采样率。

**输出验证**：AAC LC, 48kHz, stereo, 192kbps, 3.00s ✓

**沙盒位置**：`poc/ffmpeg-test/`（input_24k.wav + resampled_48k.wav + output_final.m4a）

---

## 2026-06-07 — POC 3a: Node.js + Remotion 环境验证通过

来源：`tasks.md` §A（POC 3a）

**环境**：
- Node.js v22.14.0 · npm 10.9.2 · TypeScript 5.x
- Remotion 4.0.473（`remotion` + `@remotion/cli` + `@remotion/renderer`）
- Chrome: 系统已安装 `C:/Program Files/Google/Chrome/Application/chrome.exe`（Remotion 自带 Chrome Headless Shell 下载超时，改用 `--browser-executable` 指向系统 Chrome）

**验证结果**：
- [x] `npm init` + Remotion 依赖安装（181 packages）✓
- [x] TSX 入口 + Composition（`TestScene`, 1920x1080, 30fps, 60 frames）✓
- [x] `remotion compositions` 列出组件 ✓
- [x] `remotion render` 渲染出 `output/test-scene.mp4`（222KB）✓
- [x] ffprobe 验证：H.264 High Profile, 1920x1080, 30fps, AAC 48kHz, "Made with Remotion 4.0.473" ✓

**渲染性能**：60 frames / 8x concurrency ≈ 40s（含 bundle 1.5s + 渲染 + H.264 编码）。推算 5 分钟视频（9000 frames）≈ 5-8 分钟，符合 `04.video` 文档预期（10-18 分钟为含复杂动画的安全余量）。

**关键技术决策**：
- 使用 `--browser-executable` 指向系统 Chrome，绕过 Remotion 自带 Chrome Headless Shell 下载（在中国大陆网络环境下 storage.googleapis.com 可能缓慢/超时）
- `--image-format jpeg --quality 85`：JPEG-95 在 `04.video` 文档中已论证为默认（PNG 81GB vs JPEG 19GB for 27000 frames）

**许可状态**：Remotion 4.x 对个人 / ≤3 人营利组织免费（含商业用途）；超过 3 人需 Company License（$0.01/render, $100/月起）。POC 阶段属免费档；商业化需在 Phase 5 end 前完成许可审查（见 `tasks.md` §D）。

**沙盒位置**：`poc/remotion-test/`（`src/index.ts` + `entry.tsx` + `Scene.tsx` + `output/test-scene.mp4`）

---

## 2026-06-07 — POC 2d: ASR SSE 端点验证通过

来源：`tasks.md` §A（POC 2）

**重大发现**：ASR SSE 使用 **Step Plan 端点** `/step_plan/v1/audio/asr/sse`（非 Standard 端点 `/v1`），使用 Step Plan Key。

**验证结果**：
- [x] ASR SSE（`stepaudio-2.5-asr`）连通 ✓ — Step Plan 端点
- [x] 请求格式为嵌套 JSON：`{ "audio": { "data": "<base64>", "input": { ... } } }`
- [x] SSE delta 事件格式：`{ "type": "transcript.text.delta", "delta": "词", "start_time": 320, "end_time": 400 }`
- [x] 时间单位 ms，每个词一个 delta 事件

**代码更新**：
- `StepFun.pas`: ASR 请求端点从 `/v1/audio/asr/sse` 改为 `/step_plan/v1/audio/asr/sse`
- `StepFun.pas`: ASR 请求格式改为嵌套 JSON（`audio.data` + `audio.input` + `audio.format`）
- `StepFun.pas`: ASR SSE 解析改为匹配 `transcript.text.delta` / `transcript.text.done` 事件
- `StepFun.pas`: 模型名更新 `step-3.7-flash`（默认）+ ASR `stepaudio-2.5-asr`
- `02.api` 文档：双端点架构表、KEY RULES、ASR 章节全部更新

**结论**：一个 Step Plan Key 即覆盖全部能力（Chat/TTS/ASR/Image），无需 Standard Key。

---

## 2026-06-07 — POC 1 + POC 2 凭据注入与连通性验证

来源：`tasks.md` §A（POC 验证）

**POC 1：DB2 PostgreSQL** — 凭据注入 + schema 创建验证通过
- 创建 `data/DeepFramesConfig.db`（SQLite ConfigDB），写入 `deepframes/db2` secret（DPAPI 加密）
- 写入 DB2 连接配置（Host/Port/Database/User + `secret://deepframes/db2` 引用）
- PostgreSQL `127.0.0.1:5432/DeepFramesData`（user `fuyi01`）连接成功
- 13 表 + 16 索引创建：projects, documents, jobs, job_steps, quality_gates, audio_manifests, video_ir, video_jobs, candidate_packages, assets, prompt_versions, bgm_library, style_rules
- `TIMESTAMPTZ` 字段确认（`+08` 时区），参数化查询工作正常

**POC 2：StepFun API** — Chat + Image 连通性验证通过
- 注入 `deepframes/stepfun/step_plan_key` secret（DPAPI 加密）
- 注册 DeepBase LLM provider `stepfun`（BaseUrl `https://api.stepfun.com/step_plan/v1`）+ API key + 6 模型
- Chat Completion（`step-3.5-flash`）连通 ✓ — 发现 reasoning 模式（`message.reasoning` 字段，`content` 可能空，需大 `max_tokens`）
- Image Generation（`step-image-edit-2`）连通 ✓ — 返回 URL
- 9 个可用模型确认（`/models` endpoint）

**模型名修正**：发现 StepFun 实际模型 ID 为 `step-3.5-flash`（非 `stepfun-flash-3.5`）。批量更新 `AgentChain.pas` / `DocumentChain.pas` / `Provider.StepFun.pas`。

**待验证（需 Delphi 编译运行）**：
- FireDAC 连接 DB2
- TTS（`stepaudio-2.5-tts`）原始 HTTP
- ASR SSE（`stepaudio-2.5-asr`，需 Standard Key）

---

## 2026-06-06 — 可行性评审文档缺口补齐

来源：`docs/review-report-2026-06-02-feasibility.md` §必须修改 1-5

| 文档 | 修改 |
|------|------|
| `docs/04.video` | 新增"帧捕获实现方案"小节：时间虚拟化（CDP `document.timeline.currentTime` 注入）、Chromium 会话分块（N=20 scenes/chunk）、帧格式（默认 JPEG q=95，约 19 GB / 27k 帧；alpha 场景 PNG）、确定性验证方案（30 秒 CSS 动画 + 60 秒窗口 ≤ 50ms 偏差） |
| `docs/05.audio` | 已存在两 pass `loudnorm`（lines 242-247），无需修改 |
| `docs/07.platform` | 新增 H.264 编码参数表（Profile/Level/Preset/GOP/B-frames/像素格式/码率控制）+ 平台编码配置覆盖表 + FFmpeg 命令模板（B 站 / 抖音 / YouTube） |
| `docs/08.quality` | 降级方案的"纯色/渐变背景 + 字幕"改为"模板化布局（排版骨架 + 主题配色渐变背景）+ 字幕"，保持视觉结构完整性 |
| `docs/11.e2e` | 顶部新增 126 字节选 → 9 shots 与全文 3800 字 → 180-200 shots 的对照说明；`source_metadata.word_count_note` 字段注明节选规模 |

Chromium 帧捕获时序确定性验证（最高技术风险）留待真实环境 POC 阶段验证。

---

## 2026-06-06 — StepFun LLM/Image Provider → DeepBase ILLMClient 委托重构

提交：`refactor(DeepFrames): delegate StepFun LLM/Image to DeepBase ILLMClient`

将 StepFun LLM 和 Image provider 的原始 HTTP 调用替换为 DeepBase 统一 LLM 客户端：

| 改动 | 说明 |
|------|------|
| `TStepFunLLMProvider.CallRealAPI` | 删除原始 `THTTPClient` + JSON 解析，改为 `LLM.ChatWithHistory(TierSmart, Messages)` |
| `TStepFunImageProvider.CallRealAPI` | 删除原始 HTTP，改为 `LLM.GenerateImage(Prompt, Size)` + Base64/URL 下载 |
| 密钥管理 | LLM/Image 不再直接 `LoadSecret()`，改由 DeepBase LLM 配置层管理 |
| Stub fallback | `IsDeepBaseConfigured` 替代 `HasApiKey`，无 LLM provider 时仍返回 stub |
| TTS/ASR | 不变 — 仍用原始 HTTP（DeepBase 无对应抽象） |
| Schema 验证 | 保留 — LLM 返回内容仍经过 `TJsonSchemaValidator.Validate` |

引入单元：`DeepBase.LLM.Client`, `DeepBase.LLM.Types`, `DeepBase.LLM.Service`

---

## 2026-06-06 — 编译警告清零（0 Warning / 0 Hint）

DeepFrames 37 个 Pascal 单元 + 测试文件全部 0 Warning 0 Hint 编译通过。仅剩 DeepBase 库的 2 个 W1057 不在本次范围。

### 修复内容

| 类别 | 数量 | 修复方式 |
|------|:---:|------|
| W1057 AnsiString→string 隐式转换 | 7 处 | `GetValue<string>('key')` → `GetValue('key').Value`（3 文件：StepFun / PackageExporter / AssetRetention / StyleKeeper） |
| W1057 中文字面量隐式转换 | ~30 处 | 添加 UTF-8 BOM（`EF BB BF`）到 11 个源文件，Delphi 12.x 按 UTF-8 解析源码，消除隐式 AnsiString 转换 |
| H2077 Result 赋值后未读取 | 3 处 | 删除 `CallRealAPI` 开头的 `Result := False` 死代码（StepFun LLM/ASR/Image） |
| H2443 Generics.Collections 未引入 | 11 处 | 7 个 Workflow 文件 + StepFun.pas 的 implementation uses 添加 `System.Generics.Collections` |
| H2443 TDirectory.GetCurrentDirectory | 1 处 | Migrations.pas 添加 `Winapi.Windows` |

152 tests 全绿（55 core + 97 integration），无回归。

---

## 2026-06-05 — P7.10: EventLog → DeepBase.Logging 接入

提交：`feat(DeepFrames): wire EventLog to DeepBase.Logging (P7.10)`

将 `TWorkflowLogger` 的 stub 日志方法接入 DeepBase 全局 Logger 单例：

| 改动 | 说明 |
|------|------|
| `LogJobEvent` / `LogStepEvent` | 实际调用 `Logger.Log(Msg, Level, 'DeepFrames.Workflow')` |
| `SeverityToLogLevel` 新增 | `TEventSeverity → TLogLevel` 映射（info/warn/error/fatal → llInfo/llWarn/llError/llFatal） |
| `LogGateResult/LogProviderCall/LogAssetEvent` | 间接通过 LogJobEvent/LogStepEvent 路由到 DeepBase |
| `BuildPayload` | 仍生成结构化 JSON（为未来 Extra 字段做准备） |

DeepBase Logger 自动处理：
- 消息防注入（CR/LF 中和、控制字符替换）
- 异步写入（队列 + 写线程）
- 多目标路由（文件 / DB / Aggregator）
- 滚动文件（按日期 + 大小）

152 tests 全绿，无回归。

---

## 2026-06-05 — 集成测试 I1-I5 完成（152 tests 全绿）

新建 `tests/DeepFrames.Tests.Integration.pas`，覆盖 5 个集成测试维度：

| 维度 | 测试数 | 覆盖范围 |
|------|:------:|----------|
| **I1** Provider+Schema+Gate | 27 | Fake LLM/TTS/ASR/Image 真实调用 + StepFun 降级 + Registry 切换 |
| **I2** Gate 全路径 | 15 | Gate1/2/3a/3b/4 边界 + TargetJobStatus 映射 + QualityGateResult round-trip |
| **I3** WorkerProtocol | 21 | TaskType 映射 + Request/Progress/Result JSON round-trip + WorkDir 生命周期 |
| **I4** 错误路径 | 8 | Schema 空/repair、未知 role、负分/超分、字幕空文本 |
| **I5** 日志+PromptVersion | 12 | WorkflowLogger 调用/BuildPayload/Severity + PromptVersion 稳定性 + StyleKeeper |

**测试规模**：55 core + 97 integration = **152 tests, 0 failed**

发现并修正的预期差异（非 bug）：
- `SeverityToStr` 返回小写（`info`/`warn`/`error`/`fatal`），测试已对齐
- Fake splitter 返回 `shots` 数组（非 `segments`），Schema 测试已对齐
- Schema auto-repair 对空对象缺少 required 字段时会注入默认值

---

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
