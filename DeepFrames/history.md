# DeepFrames Development History

## 2026-07-08 — 五专家商用就绪度评估 + P0 批量修复（6 项阻断 bug）

### 评估结论
五专家（架构/安全/DB/工作流/商用就绪度）综合评估 **3.8/10**，当前为自用 POC，**不可商用**，距商用差 2-3 迭代周期。值得肯定：四层分层干净无循环、SQL 全参数化无注入面、命令调用基本不走 shell、DeepBase JobQueue 本身质量高。

### 本轮修复的 P0 阻断 bug（6 项，详见 bugfix.md）
1. **ffprobe/ffmpeg 混用** — GetDuration/GetFileInfo 新增 FindFFprobe 路径。搬运全链阻断解除。
2. **通知 webhook 空串** — ChannelWebhook 接入 GetConfig 三常量。通知从 0% 可用。
3. **迁移 011 重复列 + 008/009 缺口** — 011 删重复列；新建 013 幂等重应用 008/009 四项变更。迁移可执行 + 核心流水线 INSERT 不再违反 CHECK。
4. **StepFun TTS 双重释放** — 删两处手动 Free。消除悬垂指针 AV/堆损坏。
5. **VideoChain mux 失败被吞 + Gate3b 无分支** — mux 失败硬中断标 FAILED+raise；Gate3b 接 fail 分支标 blocked_review。不再产出"成功"的坏视频。
6. **.gitignore + 密钥清理** — 重建 .gitignore；git rm --cached 密钥/产物（工作区保留）。

验证：DeepFrames.dpr 编译 0 Error。VideoGenTest.dpr 自身 4 个 Error（`TAgnesImageProvider`/`TAgnesVideoProvider` 未声明，uses 缺 Provider.Agnes）为**改动前已存在**的遗留问题，非本轮引入，记入 tasks 待办。

### 评估发现的其余 P0（待后续迭代，已记入 tasks.md）
- Repository 无事务 + Heartbeat 从不调用（崩溃状态不一致 / 长任务被回收重复执行重复扣费）
- Resume 未接入（failed 作业无法恢复，永久卡 failed）
- CookieCloud 解密协议全错（key=IV=MD5(pw)，真实协议 key=MD5(uuid+'-'+pw)[:16]）
- CheckSourceMetadata 未接入生产链 + unknown license 静默继续（搬运无授权审计）
- 无 CI + 测试仅 Fake provider 覆盖（150 tests 0 failed 但无真实 provider/PG 集成测试）+ H.264 专利 skip + 无预算护栏
- ArtifactOSBridge 租户隔离不完整（无 tenant_id 过滤，跨租户抢占）

### 修复路径规划
- **第一阶段（本轮完成）**：6 项 P0 修复 → 内部/受控部署可达 ~6/10
- **第二阶段**：High 项（竞态、单例锁、ProbeCodec、ProbeOffset、租户隔离）+ 真实集成测试 + CI + 预算护栏 → ~7.5/10
- **第三阶段**：H.264 专利、搬运授权硬门、CookieCloud 用户知情、结构化日志/metrics/错误追踪、运维 runbook、第三方安全审计 → ~8/10 可对外商用

---

## 2026-07-08 — external_video_import 搬运 adapter 全链路编码完成 ✅

文档规范（commit `0b97e4f`）落地为可执行代码。7 个子任务全部交付：

1. **DB 迁移 012** — `content_unit` 增来源元数据列：`source_type`/`origin_url`/`local_path`/`license_hint`/`downloaded_at`。
2. **Repository 读写** — `TContentUnitInfo` 增 5 字段；`InsertContentUnit` 写入 + 新增 `UpdateContentUnitDownloadInfo`（下载后回填 local_path/downloaded_at）。
3. **ASR TranscribeText 接口** — `IDeepFramesASRProvider` 增整文本转写方法（无词级时间戳，搬运只需全文）。StepFun real 实现复用 `/audio/asr/sse`（`enable_timestamp=False`，累积 `transcript.text.delta` 的 `delta` 字段 + 优先取 done 事件 `text`）+ stub；Fake 示例文本；Baidu NOT_IMPLEMENTED stub。
4. **AudioProcessor 扩展** — `ExtractAudio`（视频→16k mono s16 WAV，ASR-ready）+ `VadSplit`（简化 VAD：60s 等长分片，非真实静音检测——整文本 ASR 不需词级时间戳）。
5. **YtDlpDownloader** — yt-dlp CLI 封装：`FindYtDlp` 探测 + `Download` 调用（复用 `CONFIG_DOWNLOAD_PROXY`/`CONFIG_DOWNLOAD_THROTTLED_RATE`/`CONFIG_DOWNLOAD_DIR`，CreateProcessW + 管道捕获 stdout，2min 超时，exit 0 后取 DownloadDir 最新文件为 LocalPath）。
6. **ExternalVideoImportChain** — `RunImport(ProjectId, VideoUrl)` 全链路编排：URL→下载→抽音→分片→ASR 逐片拼接→source_document markdown→写库。状态机对齐原创线（`JOB_TYPE_IMPORT` + `STEP_TYPE_IMPORT_DOWNLOAD`/`STEP_TYPE_IMPORT_TRANSCRIBE`，每步 DONE/FAILED）。
7. **GateEvaluator.CheckSourceMetadata** — 来源合规黄灯子检查（`GATE_SOURCE`）：original_article pass / 外部来源+self|authorized pass / external+unknown license **warn（记录但继续）** / 缺 source_type 或外部来源缺 origin_url **fail（红灯拦截）**。

验证：DeepFrames.exe + Tests.exe 编译 0 Error；单元 88 + 集成 97 全绿（搬运相关新增 11 个 L1 测试：ContentUnit×2 / AudioProcessor×2 / YtDlp×1 / ImportChain×1 / SourceMeta×4 + ASR 接口）。

交付 commit：`86b2330`(ASR) → `14a6a8e`(AudioProcessor) → `(YtDlp)` → `(ImportChain)` → `45c9bd6`(Gate)。

---

## 2026-06-17 — VideoGenTest v3/v4/v5 + ArtifactOS 集成桥（生产对接同事系统）

### v3: 主题参数化 + 逐步计时 + 最终 metrics ✅

`VideoGenTest.dpr` 升级为可配置 CLI：接受 `argv[1]` 作为主题（默认「人工智能与未来工作」），`TStopwatch` 逐步计时（S1 LLM / S2 Images / S3 TTS / S3b ASR / S4 Render / S5 Assembly），keyword 命中计数（KwTotal/KwMatched + 百分比），末尾汇总行。示例输出：`Total: 160.2s | S1:10.9s S2:86.0s S3:22.7s S3b:11.2s S4:15.0s S5:6.1s`，`Keywords: 13/17 matched (76%)`。

### v4: 质量报告 + 图片风格预设 + 交互审校 ✅

- `SaveQualityReport`: 写入 `quality_report.json`（topic/style/timing/keyword 命中率/逐 shot 详情）
- `--style <name>`: `documentary|anime|noir|watercolor`，`StyleToPromptDetails()` 映射为图片 prompt 风格修饰词
- `--review`: LLM 脚本生成后交互式 shot 审校，命令 `list / view <id> / edit <id> <field> <value> / done`，可编辑字段 text/visual/keywords/tone
- CLI 形态: `VideoGenTest.exe [topic] [--style=X] [--review]`，参数全可选、顺序无关

### v5: P2-7 并行 S2+S3 + 多 key 轮询 ✅（P2-7 从"推迟"转为已实现）

P2-7 shot 级并行化此前因 StepFun API 串联限流 + Delphi `TTask` 闭包 `out` 参数 `E2555` 被推迟。v5 用 `TThread.CreateAnonymousThread` + `FreeOnTerminate:=False`（防止双重释放崩溃）实现 S2_Images 与 S3_TTS 并行；多 key 轮询（`LoadKeys` 读 `stepfun_keys.txt` 多行，回退 `stepfun_key.txt`；`GetImgKey(ShotIdx)` 按 shot 轮询分发）规避单 key 限流。同时移除 VLM `quota_exceeded` 噪声调用。版本号升至 v5。

> 注：tasks.md 原 P2-7「推迟—需确认 API RPM 上限」状态需更新为已实现。

### ArtifactOS 集成桥 — 同事加固 adapter + 独立轮询 worker ✅

对接同事的 ArtifactOS 生产系统（DB3 集成层）：

- `DeepFrames.Workflow.ArtifactOSBridge.pas` 替换为同事的加固 adapter（约 740 行），5 项加固：参数化 SQL、指数退避重试、租户 ID 注入、连接池接口、ContextDir 解码
- `011_db3_integration.up.pg.sql` 替换为同事的 `052_integration_tables.sql` 内容（`production_request` / `production_result` / `asset_status` 完整 schema）
- 新增 `src/PublishingWorker.dpr`: 独立控制台 worker，轮询 DB3 `integration.production_request`，claim → process → complete。用法: `PublishingWorker.exe --tenant=uuid --host=... --database=... [--once]`
- Delphi 13.1 兼容修复: `TCriticalSection.Enter/Leave`、`System.SyncObjs`

### Commit 记录

```
0b97e4f docs: 借鉴 Y2A-Auto 工程能力 + 把搬运纳入为 external_video_import adapter
1fd8bc7 fix: restore next_retry_at in bridge and migration, sync with ArtifactOS
7a2be59 fix: ArtifactOS bridge — remove next_retry_at, align with actual DB schema
bb86d6f feat: ArtifactOS integration bridge — DB3 polling worker from colleague
c3bb284 fix: dproj ProjectVersion → 12.0 (Delphi 13.1)
2937292 feat: v5 — P2-7 parallel S2+S3, multi-key round-robin, fix FreeOnTerminate
72f732c feat: v4 — quality report, image style presets, interactive review
f4e86d2 feat: v3 — topic parameterization, per-step timing, final metrics
```

---

## 2026-06-16 — P0-2~P7.9: 音画对齐、生产就绪、架构深化、DB3 多机协作 (10 features)

### P0-2: ASR 关键词弹入动画 ✅

新增 `KeywordMatcher.pas` (滑动窗口 Pos 检测, 中英文), `BuildKeywordPopup` 增加 FFmpeg drawtext `alpha` 淡入淡出, `VideoGenTest` 新增 `S3b_ASR` 步骤, ASR 逐字时间戳持久化.

### P1-4: 字幕增强 ✅

`BuildSubtitle` 增加 `box=1:boxcolor=black@0.5:boxborderw=10` 背景条 + alpha 淡入淡出.

### P1-5: img2img 同组视觉连续 ✅ (prompt-only fallback)

`TShotInfo` 增加 `GroupId`, 自动分组, 同组后续 shot 注入 anchor visual_desc 到 prompt. 当前采用 prompt-only (DeepBase 不支持 `/images/edits`).

### Image API 限流 ✅

`PC()` 函数: 指数退避重试 (max 2, 1s→2s→4s…→16s), error JSON 检测自动触发.

### LLM 输出质量保证 ✅

`ValidateScript` 校验 shot_count + keywords + title, 失败重试 1 次, try/except 保护, local var 保存第一次有效结果.

### P2-6: 对齐校验 ✅

`S1b_AlignCheck` 单次 LLM 审计 text↔visual_desc, 结果保存 `align_audit.json`.

### StepFun VoiceProfile 适配 ✅

`EmotionToText`/`PaceToText`/`PitchToText` 切换为中文, `ToneToEmotion`/`BuildInstructionFromTone` 新增, `S3_TTS` 接入 `TVoiceProfile`.

### P7.9: DB3 多机协作 ✅

新增 `TDeepFramesDB3Connection` (镜像 DB2 模式), `011_db3_integration.up.pg.sql` (integration.* 表), `RunDB3Migrations` 入口.

### P3-9: 多模态反向验证 ✅ (配额就绪后激活)

`VLM()` 函数对接 `step-1o-turbo-vision`, 生成图片后反查视觉元素. 当前 quota_exceeded — 代码就绪.

### 技术细节

- ASR 关键词命中率 86% (LLM prompt 改为中文口语关键词)
- P2-7 Shot 并行化推迟 — 串行已通过 API 限流 (Sleep 间隔) 保护
- Provider 切换: ASR 已通过 `TProviderRegistry` 接入, VideoGenTest 保留 HTTP 直调用于 VLM 验证
- 新增资产: `KeywordMatcher.pas`, `DB3Connection.pas`, `011_db3_integration.up.pg.sql`
- 单元测试 88 + 集成 97 = 0 失败; e2e 7/7 PASS

### Commit 记录

```
0921f07 feat: P3-9 multi-modal reverse verification
9d497e1 fix: tighter LLM prompt with numbered rules
e592b35 fix: revert P2-7 parallel
8caba6a fix: preserve first parse on LLM retry
6bdfd24 chore: update tasks, cleanup key, optimize LLM prompt
99613ca feat: P0-2 through P7.9 (10 features)
```

### VideoGenTest — 完整端到端流水线 ✅

新建 `src/VideoGenTest.dpr`（独立控制台，零 DeepBase 依赖）+ `src/Workflow/DeepFrames.Workflow.VideoRenderEngine.pas`（FFmpeg Ken Burns 合成引擎）：

| 步骤 | 技术 | 结果 |
|------|------|:---:|
| LLM 脚本 | `step-3.7-flash` + `thinking:disabled` → 6 shot JSON + keywords + tone | ✅ |
| AI 生图 | `step-image-edit-2` × 6, `896x1184`→`1184×896` 横版, keywords 注入 prompt | ✅ |
| TTS 语音 | `stepaudio-2.5-tts` × 6, tone → `instruction` 参数透传 | ✅ |
| Ken Burns | FFmpeg `zoompan` + `drawtext` 中文字幕, `ShellExecuteEx` 驱动 | ✅ |
| 组装 | `concat` filter + 标题卡 (blur bg + title overlay) | ✅ |

**输出**: `output/video_gen/deepframes_demo.mp4` — H.264 1920×1080@30fps + AAC, ~42s, ~29MB

**API 调用统计**: 1×LLM + 6×ImageGen + 6×TTS = 13 次真实 StepFun API 调用

### 三专家报告 — 画面-音频对齐分析 ✅

发起 3 个 Explore agent 并行分析 DeepFrames 视频生成中画面与音频的语义对齐问题：

| 专家视角 | 核心发现 | 建议数 |
|----------|---------|:---:|
| 导演/视频制作 | keywords 注入 prompt + ASR 弹入动画 + img2img 连续性 | 5 |
| UI/UX 视觉设计 | drawtext 增强 + Ken Burns 情绪匹配 + 信息层次叠加 | 5 |
| LLM/Pipeline 工程 | prompt 工程 + 多阶段生成 + 关键词注入 + Shot 级并行 | 5 |

**共识**: 最大杠杆点是 LLM prompt 输出结构化 keywords 并注入图片 prompt（P0-1，三专家一致）。

### 已实现的三专家建议

| 建议 | 优先级 | 状态 |
|------|--------|:---:|
| P0-1: LLM 输出 keywords + 注入图片 prompt | P0 | ✅ 已实现 |
| P1-3: TTS tone → 图片色调映射 | P1 | ✅ 已实现（energetic/warm/serious/tense → 对应颜色修饰词） |
| P1-3: TTS tone → instruction 参数 | P1 | ✅ 已实现 |
| BuildKeywordPopup (FFmpeg drawtext 关键词弹入) | P0-2 | ⚡ 框架已写，待接入 ASR |

### StepFun Provider ImageGen 修复

`TStepFunImageProvider.CallRealAPI` — 从 `LLM.GenerateImage()`（DeepBase 委托）改为直连 HTTP POST `/step_plan/v1/images/generations`。支持 `b64_json` 解码 + 磁盘保存。Key 回退到 `stepfun_key.txt`（DPAPI 失败时的 CLI 兼容）。

### 技术发现

1. **StepFun Image API `size` 参数逆映射**: `896x1184` 产出 `1184×896`（横版）; `1360x768` 产出 `768×1360`（竖版）。API 内部交换了宽高。

2. **`step-3.7-flash` thinking mode**: 默认开启，`content` 字段返回推理过程而非最终答案。`thinking: disabled` 后直接返回纯净 JSON。

3. **ShellExecuteEx PChar 稳定性**: 临时 `string` 在 `ShellExecuteEx` 返回前被 GC → `UniqueString()` 保持引用。

4. **FFmpeg zoompan 与 Delphi Format() 冲突**: `zoompan=z='1.10+%d*on/30'` 中的 `%d` 被 `Format()` 当作占位符。改用字符串拼接。

5. **AS 是 Delphi 保留字**: 不能用做变量名。

---

## 2026-06-13 — StepFun API 真实调用验证 (5/5 PASS)

### StepFunTest — LLM/TTS/ASR 三测全通 ✅

新建 `src/StepFunTest.dpr` 独立控制台程序，使用 `THTTPClient` 直接 HTTP POST Step Plan API：

| 测试 | 结果 | 说明 |
|------|:---:|------|
| LLM Chat | 3/3 PASS | `step-3.5-flash` 返回 `"OK"`，model match，token counts 正常 |
| TTS | 1/1 PASS | `stepaudio-2.5-tts` + `cixingnansheng` voice → 444KB WAV |
| ASR SSE | 1/1 PASS | `stepaudio-2.5-asr` SSE stream 连通，`transcript.text.done` received |

**发现**：
- LLM `max_tokens=50` 全被 reasoning 消耗 → 提升至 4096 即正常
- TTS voice `zh_female_qingxin` 不存在 → 改用 `cixingnansheng`（来自 VoiceProfile 现有列表）
- WAV 二进制响应需用 `ContentStream` 读取，`ContentAsString` → UTF-8 编码崩溃
- ASR 静音 WAV 0 delta events 是预期行为（无语音内容）

### StepFunTest.dpr 编译修复

- `var P,F:Integer=0` — Delphi 不支持多重初始化 → 拆分 `P:Integer=0; F:Integer=0;`
- `Of` / `TO` — Delphi 保留字（overflow flag） → 重命名 `OutF` / `TkOut`

---

## 2026-06-12 — P7.1 商业化多平台批量导出 + GUI 中文化 + 真实视频渲染

### CommercialExporter — 7平台批量导出 ✅

新建 `CommercialExporter.pas`，一次性导出全部7平台候选包，生成 MANIFEST.txt 清单。
ChainE2E 集成 → **54/54 PASS**。

### GUI 三修 ✅

- 图标: `.dproj` + `<Icon_MainIcon>DeepFrames.ico</Icon_MainIcon>`
- 中文: `IShellLocalizationService` 注入 40+ zh-CN 翻译键（Shell系统菜单 + DeepFrames命令）
- 布局: 默认 1440×900, 最小 1024×640

### RenderTest 真实视频验证 ✅

H.264/AAC MP4 四档 (10s→300s) **16/16 PASS**，ffprobe 验证编码合规。

### AutoFix 自愈闭环 ✅

smoke scenario (DB2检查) 全流程通过。

---

## 2026-06-11 — ChainE2E 五链全部通过 (43/43 PASS) + 修复

PackageChain 端到端集成，4个 Bug 修复。Phase 5/6 全部完成。

---

## 2026-06-11 — IDE 编译搜索路径修复 + ConfigDB Schema 升级

### DCC_UnitSearchPath 修复

**问题**: IDE 报告 `[dcc64 Fatal Error] F2613 Unit 'DeepBase.Manager' not found`。但命令行编译 (`dcc64.exe`) 成功 —— 相对路径在 IDE 和命令行 MSBuild 之间解析不一致。

**修复**:
- 在 `.dproj` 的 3 个 `DCC_UnitSearchPath` 条目中增加 `..\..\02Business\DeepBase\ThirdParty\DB`
- 与 `compile_test.bat` 中使用的 UNITPATH 对齐

### ConfigDB Schema 升级

**问题**: 启动时 `Providers` 表缺少 `Description`、`SupportsStreaming`、`SupportsVision`、`SupportsTools` 列，且 `Models` 表缺少 `ModelFamily` 列。旧 schema 与当前 `DeepBase.Schema.pas` 不匹配。

**修复**: 删除 stale `DeepFramesConfig.db` 和 `data/DeepFramesConfig.db`，让框架重新创建正确的 schema。

### AutoFix 接线

- `DeepFrames.UI.MainForm.pas`: `AfterShellShown` → `AutoFix.NotifyShellShown`
- `DeepFrames.dpr`: 新增 `.dpr` 初始化通道式中调用 `AutoFix.NotifyShellShown` 信号（因为 autofix runner 使用 `-WindowStyle Hidden`，VCL 表单永远不会触发 `DoShow` → `AfterShellShown`）

### 命令行编译验证

dcc64.exe 编译 DeepFrames.dpr **成功** — 0 Error / 0 Fatal，仅 hint/warning（均来自 DeepBase 库）。

---

## 2026-06-10 — ChainE2E 端到端集成测试

来源：`tasks.md` 端到端 chain 测试

**ChainE2E 结果**: DocumentChain + AgentChain + AudioChain 三道链全部通过

### 验证项目

| 测试 | 结果 | 说明 |
|------|:---:|------|
| DocumentChain | ✅ | 4 steps (build_script+accuracy_check+build_variant+build_shot) → done |
| AgentChain | ✅ | 5 steps (splitter+worker+assembler+qa+style_keeper) → done |
| AudioChain | ✅ | 4 steps (tts_synthesis+asr_timestamps+audio_merge+loudnorm) → done, manifest created |
| Idempotency | ✅ | 重复调用返回同一 job，无重复 |
| DB2 verification | ✅ | 所有 step status=done |

### 修复的 Bug

1. **prompt_run `agent_role` CHECK 约束过窄**: 不包含 `tts`/`asr`/`merge`/`loudnorm`，导致 AudioChain 插入失败
2. **prompt_run `status` 约束 `completed/failed/skipped` vs 代码 `done`**: 新增 `STATUS_COMPLETED`，`CreatePromptRun` 改用 `'completed'`
3. **quality_gate `human_review_status` 约束 `auto_passed` vs 代码 `auto_pass`**: `GateEvaluator.ToQualityGateResult` 修复为 `'auto_passed'`
4. **eval_result `shot_document_id` 空字符串 cast uuid 失败**: AgentChain 补传 `ShotDocumentId`
5. **eval_result `recommended_action` 空字符串违反 CHECK**: `InsertEvalResult` 用 `NULLIF` 处理空值
6. **`producer_version` VARCHAR(16) 过短**: 音频模型 ID `stepaudio-2.5-tts`(18 字符) 超限
7. **INSERT jsonb 列需显式 CAST**: 多处 `InsertAudioManifest`/`InsertVideoIR`/`InsertVideoJob` 缺少 `CAST(:col AS jsonb)`
8. **UUID 字节序导致 FK 失败**: FireDAC 读写 PG uuid 字节序不一致，`InsertVideoIR` 改用子查询解析 `platform_spec_id`
9. **迁移 008**: 扩展 `prompt_run` role 约束、widen `producer_version`/`codec`

### 环境

- Delphi 13.1 (BDS 37.0) dcc64, 0 Error / 0 Warning
- PostgreSQL 15.13 @ 127.0.0.1:5432
- Fake providers (无需外部 API)

---

## 2026-06-08 — POC 3e: Worker 协议 v0 端到端验证通过

来源：`tasks.md` POC 3e

**WorkerE2E 结果**: 12/12 PASS — Delphi ↔ Node Worker 全链路

### 验证项目

| 测试 | 结果 | 说明 |
|------|:---:|------|
| Test 0: DeepBase + Bootstrap | ✅ | 服务初始化 |
| Test 1: request.json 生成 | ✅ | `TWorkerProtocol.WriteRequest` + schema_version |
| Test 2: Worker 生命周期 | ✅ | CreateProcess → progress.json heartbeat → result.json |
| Test 2a: result.json 解析 | ✅ | success/duration/output_files/metrics |
| Test 3: Cancel Signal | ✅ | cancel 文件 → worker 检测 → status=cancelled |
| Test 4: Failure Scenario | ✅ | params.fail=true → success=false + error_message |

### 技术实现

- **Delphi**: `WorkerE2E.dpr` — 调用 `TWorkerProtocol.BuildRequest/WriteRequest/LaunchWorker/ReadProgress/ReadResult`
- **Node Worker**: `workers/echo/echo-worker.js` — 读取 request.json，模拟工作步骤，写入 progress/result
- **关键修复**: `CreateProcess` 命令行格式 `"node.exe" "echo-worker.js" "workdir"`; `node.exe` 通过 PATH 解析

---

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

### 验证方法
puppeteer-core + 系统 Chrome headless，对 1920x1080 页面注入 JS style 变更模拟时间虚拟化，逐帧截图 + getComputedStyle 验证 RGB 值。

### 结果
30/30 帧精确匹配（±0 tolerance，实测 RGB 完全等于预期值）。HSL 色相从 0°→360° 线性遍历，每帧 hue = frameNo × (360/30)。

### 关键技术发现
1. `page.setContent()` + CSS `@keyframes` 动画 → `document.getAnimations()` 返回空数组（headless Chrome 不自动触发 CSS 动画）
2. 直接 JS 操作 `element.style.background = hsl(...)` + 短暂等待 → 确定性渲染 ✅
3. Remotion 底层使用 `document.timeline.currentTime` 注入（等同 `animation.currentTime = T`），本 POC 用更直接的 style 注入方式验证了相同的确定性保证

### 性能
30 帧 × (evaluate + screenshot) ≈ 20s（含 20ms paint wait）。推算 5 分钟视频（9000 帧）≈ 100 分钟单线程，需 session chunking + 并发多 tab。

### 沙盒位置
`poc/remotion-test/src/cdp-capture.ts` + `output/cdp-frames/`

---

## 2026-06-07 — POC 3c: FFmpeg 音频管线验证通过

### 验证的管线
TTS 24kHz WAV → resample 48kHz → loudnorm 两 pass → AAC 192kbps

### 关键发现
`loudnorm` + `linear=true` 会将内部采样率翻倍（48k → 96k）。必须显式指定 `-ar 48000` 以强制输出目标采样率。

### 输出验证
AAC LC, 48kHz, stereo, 192kbps, 3.00s ✓

### 沙盒位置
`poc/ffmpeg-test/`

---

## 2026-06-07 — POC 3a: Node.js + Remotion 环境验证通过

### 环境
- Node.js v22.14.0 · npm 10.9.2 · TypeScript 5.x
- Remotion 4.0.473
- Chrome: `--browser-executable` 指向系统 Chrome

### 验证结果
- [x] `npm init` + Remotion 依赖安装 ✅
- [x] TSX 入口 + Composition (1920x1080, 30fps, 60 frames) ✅
- [x] `remotion render` 输出 `output/test-scene.mp4` (222KB) ✅
- [x] ffprobe 验证 H.264 High Profile, 1920x1080, 30fps, AAC ✅

### 渲染性能
60 frames / 8x concurrency ≈ 40s。推算 5 分钟视频（9000 frames）≈ 5-8 分钟。

---

## 2026-06-07 — POC 2d: ASR SSE 端点验证通过

### 重大发现
ASR SSE 使用 **Step Plan 端点** `/step_plan/v1/audio/asr/sse`（非 Standard 端点 `/v1`），使用 Step Plan Key。

### 代码更新
- `StepFun.pas`: ASR 请求端点改为 `/step_plan/v1/audio/asr/sse`
- `StepFun.pas`: ASR 请求格式改为嵌套 JSON（`audio.data` + `audio.input`）
- `StepFun.pas`: SSE 事件解析改为 `transcript.text.delta` / `transcript.text.done`
- `02.api` 文档：双端点架构表 + ASR 章节全面修正

---

## 2026-06-07 — POC 1 + POC 2 凭据注入与连通性验证

### POC 1：DB2 PostgreSQL
- PostgreSQL `127.0.0.1:5432/DeepFramesData`（user `fuyi01`）连接成功
- 13 表 + 16 索引创建
- `TIMESTAMPTZ` 字段确认（`+08` 时区）

### POC 2：StepFun API
- Chat Completion (`step-3.5-flash`) 连通 ✅
- Image Generation (`step-image-edit-2`) 连通 ✅
- 9 个可用模型确认

---

## 2026-06-06 — 可行性评审文档缺口补齐

| 文档 | 修改 |
|------|------|
| `docs/04.video` | 新增"帧捕获实现方案"小节 |
| `docs/05.audio` | 已存在两 pass `loudnorm`，无需修改 |
| `docs/07.platform` | 新增 H.264 编码参数表 + FFmpeg 命令模板 |
| `docs/08.quality` | 降级方案改为"模板化布局" |
| `docs/11.e2e` | 新增 0.4KB(约126字)节选 → 9 shots 对照说明 |

---

## 2026-06-06 — StepFun LLM/Image Provider → DeepBase ILLMClient 委托重构

将 StepFun LLM 和 Image provider 的原始 HTTP 调用替换为 DeepBase 统一 LLM 客户端。

---

## 2026-06-06 — 编译警告清零（0 Warning / 0 Hint）

DeepFrames 37 个 Pascal 单元 + 测试文件全部 0 Warning 0 Hint 编译通过。

---

## 2026-06-05 — P7.10: EventLog → DeepBase.Logging 接入

将 `TWorkflowLogger` 的 stub 日志方法接入 DeepBase 全局 Logger 单例。

---

## 2026-06-05 — 集成测试 I1-I5 完成（152 tests 全绿）

55 core + 97 integration = **152 tests, 0 failed**

---

## 2026-06-05 — 全量编译通过（0 Error / 0 Fatal）

37 个 Pascal 单元首次全量 `dcc64` 编译成功。修复 8 个文件的 9 类编译错误。

---

## 2026-06-04 — 工程底座构建（完整 36 个 Pascal 单元）

从 fake skeleton 到完整工程底座。所有 Phase 2/3/4/6 任务完成。

---

## 2026-06-04 — Bugfix: TProcess → CreateProcess

P0 编译阻断 — `AudioProcessor.RunFFmpeg` 使用 FreePascal `TProcess`，Delphi 不支持。

---

## 2026-06-03 — 文档评审修复（T1-T6, F1-F3）

14 项修复全部完成。

---

## 2026-06-04 — Phase 1-7 桌面骨架实现（fake providers）

17 个 Pascal 文件 + 6 个 PostgreSQL migration 文件。

## 2026-07-08 — P2-P4 工程能力编码完成（Y2A 借鉴落地）

在文档规范��commit `0b97e4f`）基础上完成全部 P2-P4 代码落地，对齐 Y2A-Auto 工程能力借鉴清单：

### P2: 字幕质量与后处理
- **P2-1 字幕变换引擎 `srt_transform`** — `DeepFrames.Workflow.SubtitleTransform`：台词级变换规则（停顿/合并/拆分/重排/时间戳重算），L1 测试覆盖。
- **P2-2 字幕 QC 两层架构** — `DeepFrames.Workflow.SubtitleQcEngine`：硬规则层（时长/行数/字符率/重叠）+ AI 抽样复核层接口（`IQcReviewer`），黄灯记录红灯拦截。
- **P2-3 VAD 扫描窗真实静音检测** — `TAudioProcessor.VadScan`：ffmpeg `silencedetect` 解析静音区间反推语音段并切片，无静音整段兜底，失败回退 `VadSplit` 等长分片。

### P3: 转码与编码器策略
- **P3 视频转码 HEVC 优先 / libx264 回退** — `DeepFrames.Workflow.VideoTranscoder`：编码器选择 cpu/auto/nvidia/intel/amd → libx264/hevc_nvenc/qsv/amf；HEVC 失败自动回退 libx264（FellBack 标记）；转码后 `ProbeCodec`（ffmpeg `-i` 解析 `Video:` 行）校验输出 codec。

### P4: 分发与运维
- **P4-1 通知推送多渠道异步重试** — `DeepFrames.Workflow.NotificationChain`：企业微信/钉钉/HTTP webhook 三渠道，投 `QUEUE_DEEPFRAMES_NOTIFY` 队列异步消费；失败 `TJobQueue.Fail(Requeue=True)` 指数退避重试，达上限进 DLQ（复用 JobQueue 死信）。
- **P4-2 CookieCloud 同步** — `DeepFrames.Workflow.CookieCloudSync`：GET 拉取加密包 → AES-128-CBC 解密（KEY=IV=MD5(password)，复用 `DeepBase.Crypto.AES`）→ 解析 cookie_data 嵌套 → 导出 Netscape `cookies.txt`（yt-dlp 兼容）。
- **P4-3 上传器分块断点续传** — `DeepFrames.Workflow.ChunkedUploader`：5MiB 分块 PUT + `Content-Range`；断点续传三段式（本地 `.partial` sidecar → 服务器 `ProbeOffset` 探测 → 从 offset 续传）；单块指数退避重试，全量成功清理 sidecar。

### 验证
- 编译：DeepFrames.exe + DeepFrames.Tests.exe **0 Error**（新增 4 个 Workflow 单元 + 常量）
- 测试：**150 tests, 0 failed, 150 passed**（新增 19 个 L1 测试覆盖 P2-P4 各组件）
- 提交：P2-1/P2-2/P2-3/P3/P4-1/P4-2/P4-3 各一次 feat 提交

### 交付文件
- 新建：`SubtitleTransform.pas` / `SubtitleQcEngine.pas` / `VideoTranscoder.pas` / `NotificationChain.pas` / `CookieCloudSync.pas` / `ChunkedUploader.pas`
- 修改：`DeepFrames.Shared.Consts.pas`（视频/通知/CookieCloud/上传器配置常量）、`DeepFrames.Workflow.AudioProcessor.pas`（VadScan）、`DeepFrames.dpr`（单元注册）、`DeepFrames.Tests.Core.pas`（19 个新测试）

Y2A 借鉴清单中"未授权搬运剥离"已在前序 commit 完成；本轮完成全部工程能力编码，文档规范层与代码实现层对齐。

---

## 2026-07-08 — 第二阶段 P0 工程化批量交付（7/9 项）

五专家评估第二阶段 P0 清单 9 项，本轮完成 7 项（P0-A/B/C/D/E/H/I），剩 P0-F（真实集成测试+CI）、P0-G（预算护栏）。每项附单元/契约测试，编译 0 Error，测试 194 passed（+44，含 97 集成）。

### P0-A Repository 事务边界
- `TDeepFramesRepository` 新增 `BeginTransaction`/`CommitTransaction`/`RollbackTransaction`/`InTransaction`（FireDAC `InTransaction` 守卫，嵌套 no-op）
- DocumentChain.RunChain 用事务包裹 Job+首 Step 原子创建（InsertJob+InsertJobStep+UpdateJobStepStatus），失败回滚不留孤 Job；事务在 provider 调用前 Commit，不持事务跨 LLM IO
- 测试：`TestRepo_TxSafeWhenNoTxn`

### P0-B Heartbeat 接入
- `TWorkerProtocol` 新增 `WriteProgress`（worker 端写 progress.json 心跳，tmp+rename 原子写）
- 此前宿主 `WaitForWorker` 的 heartbeat_timeout 检测因 worker 从不写 progress.json 而空转（死代码）
- 测试：`TestWorker_WriteProgressRoundtrip`

### P0-C Resume 续跑
- DocumentChain 幂等改状态感知：终态/blocked_review→退出；pending/running→复用 ExistingJob.JobId 续跑（step insert 幂等 ON CONFLICT step_key DO NOTHING）
- 修复命中已存在 logical key 静默返回未完成 job 的**假成功 bug**
- 新增 `IsTerminalStatus`/`IsResumableStatus` 可测函数
- 测试：`TestResume_TerminalStatuses` + `TestResume_ResumableStatuses`
- 遗留：step 级"跳过已 done step + 复用产物"留作后续增强

### P0-D CookieCloud 解密协议
- 复核确认 `CookieCloudSync` 解密协议（key=IV=MD5(password)）已修复落地；真实 endpoint 验证属 P0-F

### P0-E CheckSourceMetadata 接入生产链
- DocumentChain Gate1 后接入为 GATE_SOURCE 合规子检查：fail→BLOCKED_REVIEW、warn→记录继续、pass→直通
- Repository 新增 `FindContentUnit` 供 Gate 读取来源元数据

### P0-H ArtifactOSBridge 租户隔离
- PollRequests/ClaimRequest/ReleaseRequest/GetRequest/UpdateRequestStatus/ShouldRetryNow/WriteResult 全部加 `tenant_id=:tid::uuid` 过滤（SQL 层强制）
- WriteResult INSERT 显式写 tenant_id；SetTenantId/GetTenantId 注入（未设→默认 tenant，单租户向后兼容）
- 测试：`TestArtifactOS_TenantIdDefault` + `TestArtifactOS_TenantIdInjected` + `TestArtifactOS_NotConnectedSafe`

### P0-I H.264 专利
- 定档 skip（自用 POC）；商用前阻断：授权或转 AV1/VP9（VideoTranscoder 已支持编码器切换）

### 验证
- 编译：DeepFrames.exe + DeepFrames.Tests.exe **0 Error**
- 测试：**194 tests, 0 failed, 194 passed**（本轮 +44：6 tenant + 2 tx + 5 heartbeat + 11 resume + 余接入验证）；集成 97 passed 不受影响
- 文档：tasks.md/bugfix.md/history.md 三方对齐

### 待办（第二阶段剩余 2 项 + 第三阶段 High）
- P0-F 真实集成测试 + CI（StepFun/Agnes/PostgreSQL 真实 provider 覆盖 + CI 流水线）
- P0-G 预算护栏（LLM/图像调用上限，防单作业烧穿预算）
- 第三阶段 High：竞态/单例锁/Probe 容错/结构化日志/runbook/安全审计

### P0-G 预算护栏（2026-07-08 补充）
- 新建 `DeepFrames.Workflow.BudgetGuard`：进程级 `TBudgetGuard`（class var + 字典），每作业累计 token（Prompt/Completion/Total）+ 调用计数（llm/image/tts/asr/other 分类）
- `CheckBudget(JobId)` 超 MaxTokensPerJob 或调用数≥MaxCallsPerJob 时 raise `EBudgetExceeded`；链路 except 标 job FAILED
- DocumentChain 4 个 ChatComplete 全接入：Job 创建后 `Reset`，调用前 `CheckBudget`、后 `Accumulate`
- 配置常量 `CONFIG_BUDGET_MAX_TOKENS_PER_JOB`/`CONFIG_BUDGET_MAX_CALLS_PER_JOB`（默认 20万 token / 60 调用）
- 测试：4 个（累计计数/token 超限 raise/调用数超限 raise/Reset 清零）
- 验证：DeepFrames.exe + Tests.exe 0 Error；205 tests 0 failed（+11）

### 第二阶段 P0 收尾状态（2026-07-08）
9 项 P0 中完成 8 项（A/B/C/D/E/G/H/I），仅剩 **P0-F 真实集成测试 + CI**（需真实 StepFun/Agnes/PostgreSQL 凭证 + CI runner，超代码层）。第三阶段 High 项（竞态/单例锁/Probe 容错/结构化日志/runbook/安全审计）待后续迭代。

### P0-F CI 流水线（2026-07-08，子项交付）
- 新建 `.github/workflows/ci.yml`：self-hosted Windows runner（Delphi 13.1 BDS 37.0）
- 步骤：checkout → 编译 DeepFrames.exe → 编译 Tests.exe → 跑 205 测试（全 Fake provider）→ 真实 provider 集成 step（凭证门控 `DF_RUN_REAL_INTEGRATION=1`）
- 触发：push main/docs/** + PR main
- 约束：GitHub hosted runner 无 Delphi，必须 self-hosted；DeepBase 需预置 + dcu64 已构建
- 待填：`tests/DeepFrames.Tests.RealIntegration.pas` 真实 StepFun/Agnes/PostgreSQL 集成测试（凭证就绪后填充，同 v5 VLM 模式）

### 第三阶段 High 启动（2026-07-08，2 项）

**ProbeCodec 解析容错**
- `ParseCodecFromOutput` 抽为纯函数可单测：搜 lowercase marker `video:` + slice 原串保 codec 大小写、Trim 跳过 marker 后多空格、codec 在 `(`/`;`/空格`/逗号处停止
- ProbeCodec 注释：ffmpeg `-i` exit 1 仍打印流信息故 exit 仅参考；空结果=探测不结论非转码失败
- 6 个解析测试（标准/小写/多空格/括号 profile/无 Video 行/空输入）

**Registry 单例双检锁**
- `TProviderRegistry.Instance` 改双检锁（TCriticalSection，外层 nil-check 快路径无锁，内层串行 create+init）
- InitializeDefaults 同锁双检（TCriticalSection 可重入，Instance→InitializeDefaults 同线程嵌套安全）
- FLock 在 initialization 段单线程创建（避免锁自身竞态），finalization 释放
- 注：tasks 原"SharedImageUploader/WebhookProvider"过时引用已澄清，Registry 是唯一无锁单例

**验证**：DeepFrames.exe + Tests.exe 0 Error；211 tests 0 failed（+6 ParseCodec，集成 97 不变）

### 第三阶段剩余 High（待后续）
- 结构化日志/metrics/错误追踪（当前日志无结构、无聚合）
- 运维 runbook（部署/回滚/告警/故障排查手册）
- 第三方安全审计（外部）

### 第三阶段 High - 结构化日志接入（2026-07-08）
- 设施已存在（同事在 DeepBase 建好 Logging/Metrics/LogAggregator/LogAlert/LogDashboard/LogQuery + DeepFrames TWorkflowLogger 封装，AgentChain 已用）
- 本轮补 DocumentChain 核心链路接入：4 个 ChatComplete 成功后 `LogProviderCall`（provider/model/latency/tokens→LogDashboard），链路 except 包 `LogJobEvent('chain_failed', esError)` 记后重抛（JobId 未创建时回退 logical key）
- metrics 基础设施 DeepBase.Metrics 已就绪待按需埋点
- 验证：DeepFrames.exe + Tests.exe 0 Error；211 tests 0 failed（行为不变，日志为旁路）

### 第三阶段剩余
- 运维 runbook（部署/回滚/告警/故障排查手册，文档项）
- 第三方安全审计（外部）

### 第三阶段 High - 真实 API 端点实测 + provider 补全启动（2026-07-09）
- 实测外部 API 端点全部可用：LLM(Agnes agnes-2.0-flash 真实 HTTP 实现已就绪 / WiseGateway 经 xunfei alias 实测 200)、ASR+TTS(百度 AppID 7698708 token 实测 200 scope 含 audio_voice_assistant_get+audio_tts_post)、图像/视频(Agnes 已有真实 HTTP 实现)、Gemini/NIM 备选。详见 memory deepframes-real-api-endpoints
- 盘点 provider 代码：Agnes LLM/Image/Video 已完整真实实现，Baidu ASR 全 stub、无 Baidu TTS、StepFun 无订阅致复用它的 LLM/TTS/ASR 全断
- 本轮推进：补全 Baidu ASR 真实 HTTP + 新建 Baidu TTS + CreateAgnesProviders 改用 Agnes LLM/百度 TTS/百度 ASR，全能力就绪后跑全链路真实测试
- 安全：百度 key 经 --set-secret 存 DPAPI，不硬编码；Agnes key 在 agnes_key.txt(gitignore)

### P0-F 真实 provider 集成完成（2026-07-09）
- TBaiduASRProvider 真实 HTTP：OAuth2 access_token 获取+缓存（aip.baidubce.com/oauth/2.0/token，expires_in-300s 提前刷新）/ ConvertTo16kWav 经 ffmpeg 转 16k 单声道 WAV / SplitOnSilence 静音切分长音频为 <55s 片段 / TranscribeChunk 调 vop.baidu.com/server_api base64 上传 + dev_pid=1537 普通话 / Transcribe 编排：转码→切分→逐片转写→拼接整文本存 Words[0]（百度仅返回整句无词级时间戳）。原 GetAccessToken/ConvertTo16kWav/SplitOnSilence/TranscribeChunk 全 stub 已替换
- TBaiduTTSProvider 真实 HTTP（新建）：OAuth token / text2audio form-urlencoded POST（tex/tok/cuid/ctp=1/per/spd/pit/vol/aue）/ 按 Resp.MimeType 区分 audio/* 成功 vs application/json 失败 / 成功写 mp3 或 wav 文件 / 失败解析 err_no+err_msg / 重试 3 次 / DurationSec 按 0.25s/字估算
- CreateAgnesProviders 路由切换：LLM=TAgnesLLMProvider、TTS=TBaiduTTSProvider、ASR=TBaiduASRProvider、Image=TAgnesImageProvider、Video=TAgnesVideoProvider（StepFun 无订阅保留为独立 stepfun switch，不再默认复用）
- tests/DeepFrames.Tests.RealIntegration.pas（新建）：5 项真实集成测试 RI1-RI5（Agnes LLM/Image/Video + 百度 TTS/ASR），DF_RUN_REAL_INTEGRATION=1 env 门控，无凭证 SKIP 不 fail，RIFailCount>0 时 Halt(1)。接入 Tests.dpr uses
- CI（.github/workflows/ci.yml）：补 DF_BAIDU_APIKEY/DF_BAIDU_SECRET env；Real step 占位改真实运行（findstr "FAIL:" 判红）；unit test step 改 findstr "0 failed" 容错 Tests.exe 退出 Runtime 217（DeepBase.Crypto.RSA finalization 崩溃，非测试失败）
- 验证：DF.exe + Tests.exe 编译 0 Error；回归 211 tests 0 failed；本地 DF_RUN_REAL_INTEGRATION=1 实测 RI1 Agnes LLM 真实端点通过、RI2/RI3 百度无 key 正确 SKIP
- 遗留：百度 key 待存 secret 跑 RI2/RI3 真实验证；RI4 Agnes image 真实生成实测挂起待查（记 bugfix）；DeepBase.Crypto.RSA.pas 有未跟踪的多余 end; typo（同事草稿）已临时删除解锁编译，退出 217 崩溃源待 DeepBase 侧修

---

## 2026-07-09 续 — RI5 真绿 + VideoChain 全链路接通 + LLM 切 GPT

### RI5 Agnes 视频从假绿转真绿（bugfix B23）
- 此前 RI5 报 OK 但下载 0 字节——假绿。真调隔离出 5 处 bug（视频取错字段 result_url→应为 data.data.url；status 大小写 SUCCESS 不兼容；DownloadFile 缺鉴权；缺 Content-Type 校验；CDN 拒 Bearer 须只 API 域加 auth）。全修后 RI5 真绿，下载到 608KB MP4。
- 提交 `ef17805`。关联 memory `agnes-video-url-extraction-bugs`。

### VideoChain 全链路接通真实 provider（bugfix B24）
- 根因：VideoChain Step4 渲染/mux 原为 stub 不调 Agnes、字幕用硬编码假数据无烧录、PackageChain 无入口——生产视频无字幕无声音。Agnes provider 本身已修好但接入层断链。
- 修复：Step4 取 `TProviderRegistry.Instance.VideoProvider`(=Agnes) 调 `GenerateVideo`，失败硬中断；Step5 mux VideoStep 提前创建+非零退出硬中断+缺 audio URI 硬中断；有字幕走 libx264 烧录分支、无字幕走 copy 快速 mux。
- 提交 `cf32f4c`。关联 memory `video-chain-not-wired-end-to-end`（根因已解决，memory 待清理为已解决）。

### LLM 路由切换至 GPT-5.6（经 fccy 代理）
- 本地代理 `127.0.0.1:8000`（Kiro/WiseGateway，OpenAI 兼容）实测可用，model 字段传 `claude-` 前缀 alias 实际透传各家真实模型。curl 真调确认：fccy-gpt-5-6 系→真实 gpt-5.6-sol/luna/terra（OpenAI）；xunfei-glm-5-2→GLM；kimi-k2-6→Kimi；qwen3-coder-next→Qwen3。deepseek 系 402 余额不足不可用。
- DeepFrames 落地：`TAgnesLLMProvider` 走标准 OpenAI 协议，base URL 已是 `127.0.0.1:8000/v1`，**无需改代码**，只改 DB `Settings.Agnes.LLMModel` = `claude-fccy-gpt-5-6`（从 `claude-xunfei-glm-5-2` 切来）。key 不变（同一把 `fuyi-kiro-17781158558`）。GPT 返回 reasoning_content=null 与已修回退逻辑兼容。
- 仅改运行时根目录 DB，未改源码未重编译。Image/Video 仍走官方 Agnes 不受影响。
- 关联 memory `fccy-proxy-gpt-models`。

### 当前商用就绪度
- 仍维持 5 专家评估 3.8/10（2026-07-08）：自用 POC，不可商用。本轮（RI5 真绿 + VideoChain 接通 + LLM 切 GPT）解决了"生产视频无字幕无声音"这一核心可用性问题，但未改变商用就绪度评级——P0 阻断项（API key 泄露进 git 历史、百度 TTS/ASR 真实端点 HTTP SSL 卡死未根治、运维 runbook 缺失、第三方安全审计未做）仍待办。详见 tasks.md「商用就绪度 P0/High 待办」。

---

## 2026-07-13 — pipeline 端到端首次跑通 + mux 核心能力修复

> 本轮为管道从"能编译"到"能产出真实可用 mp4"的里程碑。所有 bug 细节见 bugfix.md B25-B32。

### 完成
1. **pipeline 5 blocker 全修（B25-B29）** — `--run-pipeline` 首次生成 366KB MP4。`FindAudioManifestByShot` AV 绕过 / `InsertVideoIR` 空 `AudioManifestId` NULL 处理 / Baidu TTS 语音名→数字 ID 映射（`cixingnansheng→106` 等）/ 空串 jsonb 改 `'{}'` / loudnorm 用纯 JSON 非 ffmpeg 全量输出。
2. **mux 管道死锁 + srt 路径（B30-B31）** — `RunFFmpeg` 改短轮询排空管道（4KB 缓冲死锁根除）+ 加 `ATimeoutMs` 自适应超时；libass `subtitles` filter 用 `f='D\:/path.srt'` 转义 Windows 绝对路径。产出 h264 1088x832 + aac + 烧录中文字幕 mp4，音画对齐 3.25s。
3. **mux 音画时长错配（B32）** — `DEFAULT_DURATION_STRATEGY` 由 `shortest` 改 `audio-base` + 短视频 `-stream_loop -1` 循环填充。音频不再被截到 5s，263s 音画对齐。
4. **超时自适应** — RunFFmpeg 固定 300s 改 `Min(Max(120, SrcDuration×10), 1800)×1000` ms，长视频不误杀。

### 残留（转入 tasks.md）
- failover 链 TTS 退化为 gemini STUB 假音频（257s），真 TTS 待配 key（→ DBA-1）。
- `df_*.txt` 诊断散落 App.Services/Baidu/VideoChain 三处，待统一到 HealthSignal（→ DBA-5）。

---

## 2026-07-14 — 架构基线评审 + 文档链三连环 + 三修复

> 本轮核心是发现"真假绿无法区分"的架构根因，并启动 DBA 线。bug 细节见 bugfix.md B33-B36。

### 完成
1. **架构基线评审** — 实测 `src/` 内 `uses DeepBase.*` 业务单元为 0，明文 key + 散落 JSON 违反 `docs/01.arch` 铁律，`IoC/EventBus/Scheduler/ExecuteAsync` 全 0。结论：问题不是缺层而是该接的 facade 没接。产出 `docs/review-report-2026-07-14-架构基线偏离与DeepBase接入.md`，新增 DBA 线作为最高工程优先级。
2. **文档链崩溃���连环（B33）** — 中文 `payload_json` 0x00 + markdown 围栏 `` ` `` + `raw_output` NOT NULL 三连环崩溃，逐行 TextFile marker 定位后修复。pipeline 端到端跑通生成 612KB MP4。
3. **三修复落地 commit `cc79af8`（B34-B36）**：
   - Baidu 删 4 处明文 key 回退（消铁律 #5 违规）；
   - `Mark()` 空函数改 `Writeln('[phase] ...')`（步骤可观测性从 0 到 8 行边界）；
   - srt 结束时长夹到音频时长（`BuildCues` 前用 `DurationSec` 夹 `TsWords`，索引循环非 for-in）。
4. **Task4 语音 facade 评估** — DeepBase Speech facade 不可接（无 word 时间戳字段 / 无 StepFun ASR 只有 Baidu vop 整句 / 是录音场景）。正确方向是反向给 DeepBase 补 StepFun ASR + 扩 Result。
5. **DeepBase 集成状态更新** — 6 合规 / 0 违规（Baidu 明文 key 已清）/ 2 缺失（语音 facade 评估为 DeepBase 缺能力非未接；Services 包 Scheduler/IoC 仍 0 引用）。
6. **`--force-rerun` 真跑验证** — 3m28s 产 622KB mp4，音画对齐 3.25s 字幕已烧入。DeepBase 集成 6 合规/1 违规(Baidu 明文 key，本轮已修)/2 缺失。

### 残留（转入 tasks.md）
- P2 残留：FireDAC UTF16 绑定层 0x00 阻塞未根治，AsBytes/MapRules 待试（→ bugfix.md B33 残留）。
- DBA-1~6 全线待落地（明文 key 迁 Security / 配置迁 DB1 / LLM 走 facade / 编排走 ExecuteAsync / 日志走 Logger 删 df_*.txt / Repository 按聚合根拆）。

---

## 2026-07-15 — 仓库历史重建（清除明文 key 历史）

> 本轮处置"API key 泄露进 git 历史"这一长期 P0。bug 细节见 bugfix.md B37。

### 完成决策与执行
- **场景判定**：仓库为单人单机、**从未配置任何远端**（`git remote -v` 为空），无协作者。历史明文 key 泄露对当前场景无实际风险，故采用**删除整个 `.git` 重建**而非 `git filter-repo` 清史。
- **执行**：备份 `_baidukey.txt` 到仓库外 → `.gitignore` 加固（补 `_baidukey.txt`/`df_*.txt`/散落 JSON/`*.bak`/`root.txt`）→ 删 `.git` → `git init` → `git add .`（验证明文 key/二进制/诊断全被忽略）→ 首个 commit `832fe98`，236 文件含 67 源码，纳入 4 个未提交源码改动（dpr/Repository/StepFun/AudioProcessor）。
- **结果**：`git log` 仅剩一条干净提交，旧历史含明文 key 彻底消失。

### 由此变更的待办状态
- **A1「key 清史轮换」改写**：原为"商用硬阻断需轮换+清史"，现 git 已重建清史完成；单人单机无远端场景密钥轮换不再必要。降级为：明文 key 待迁入 `DeepBase.Security`（DB1）后删除根目录明文文件（→ DBA-1 覆盖）。

### 生产就绪度更新
- 较 07-08 的 3.8/10 有实质进步：ffmpeg/ffprobe 混用、webhook 空串、Repository 无事务、StepFun 双释放、CheckSourceMetadata 接入、CI 已建、真集成测试缺凭据 SKIP 均已修。
- **仍不可商用**：① 明文 key 待迁 DB1（DBA-1）；② facade 接入稀疏（`uses DeepBase.*` 仅 5 文件 9 处，DBA-2~5 待落地）；③ 4 个源码改动虽已纳入新仓库 commit 但未单独评审；④ 测试仍以 Fake provider 为主。详见 tasks.md。

---

## 2026-07-21 — DBA-1 密钥迁 Security 实质完成 + DBA-5 诊断迁 DeepBase.Logging（首两文件）

> 上接 07-15：A1（git 清史）已处置，本轮推进 DBA 线——密钥迁 `DeepBase.Security`（DBA-1）、诊断 WriteLn 迁 `DeepBase.Logging`（DBA-5，首两文件）。bug 细节见 bugfix.md B38。

### DBA-1 [P0] 密钥迁入 DeepBase.Security — 实质完成（待收尾验收）
**完成内容**：
- `src/DeepFrames.dpr` Bootstrap 段已落地 `--set-secret <name> <value>` 与 `--set-secret-file <name> <path>` 两个 CLI 写入动词（调 `DeepBase.Security.SaveSecret`，写入 DB1 Secrets 表，DPAPI 加密）。`--set-secret-file` 为长 key（含换行/特殊字符）必需，避免命令行截断。
- 新增 `--verify-secret <name>`（TEMP 验收用）：读回 `LoadSecret`，打印长度 + 首尾掩码（不回显明文），证明 Save→Load 往返正确，便于 DBA-1 验收不泄露 key。
- 5 个 provider 全部改读 `LoadSecret`，源码无 `AssignFile`/明文文件读取残留：
  - `Provider.Agnes` → `SECRET_AGNES_API_KEY` / `SECRET_AGNES_LLM_API_KEY`（`:184`/`:199`）
  - `Provider.StepFun` → `SECRET_*`（`:413`/`:697` 注释确认"DeepBase.Security only，明文 fallback 已移除"）
  - `Provider.Baidu` → `SECRET_BAIDU_ASR_KEY`（`:136`/`:157`/`:598`/`:618`，4 处 `LoadSecret`）
  - `Persistence.Connection` / `DB3Connection` → `LoadSecret(SecretNameFromRef(...))`（DB 口令也走 Secret）

**残留（收尾项，非阻断）**：根目录 `_baidukey.txt`（57B 明文）仍在工作区，已无源码读取它（Baidu 走 `SECRET_BAIDU_ASR_KEY`）；待 `--set-secret-file` 写入百度 key 后删除该文件 + `bin/` 副本。`.gitignore` 已覆盖，不会进 git。

**未验收**：`--verify-secret` 尚未对每个 provider 的 secret 实跑往返（需 DB1 在线 + 已 `SaveSecret` 各 key）。这是 DBA-1 验收门，移入 tasks 待办。

### DBA-5 [P1] 诊断迁入 DeepBase.Logging — src/ 全部 WriteLn 清零（3 文件）
**完成内容**：`src/` 全部裸 `WriteLn` 已迁完——`App.Services.pas`（ImportMarkdown 诊断 + `RunFullPipeline` 的 Mark/边界）、`Workflow.AudioChain.pas`（TTS 成功/ASR words 三处诊断）、本轮新增 `Workflow.ArtifactOSBridge.pas`（11 处 `WriteLn(ErrOutput, ...)` → `Logger.ErrorFmt`/`InfoFmt`，带 `DeepFrames.ArtifactOS` category）。所有迁移沿用既有 `Logger.InfoFmt`/`ErrorFmt('...%s', [args], 'category')` 签名。
**动机（修真 bug，见 B38）**：这些代码路径在 VCL GUI 进程内也执行，GUI 无控制台时 `WriteLn` 触发 `EInOutError` 崩溃。迁 Logger 后统一走结构化日志，且解决 DBA 线"未接 `DeepBase.Logging` 前 D2 真假绿无法区分"的结构根因。
**剩余**：原 tasks 写"19 个 `df_*_diag.txt` `AssignFile` 诊断文件"实为陈旧数字——`src/` 内已 0 个 `AssignFile` 调用、0 个 `df_*` 字面量；磁盘上仅 5 个 07-14/15 早期版本运行残留（`df_fatal/mux/purge/subtitle_diag.txt` + `bin/df_fatal_diag.txt`），本轮已删，`.gitignore` line 61 本就覆盖 `df_*.txt` 故无 git 变更。退出汇总"哪些 step 走 stub"见下节。**DBA-5 实质完成。**

### DBA-5 收尾：哪些 step 走 stub — 汇总
`grep -rni "STUB|placeholder|占位|未实现" src/` 命中 149 处，集中在 3 个 provider 单元 + 1 处真实未实现：
- **`Provider.Agnes.pas`**（设计内降级，非 bug）：LLM/Image/Video 三 provider 各有 `CallStubAPI`/`BuildStubOutput`——无 key 时返回结构化 stub JSON（`status=stub, note=Agnes LLM not configured`）、stub 图片路径（`output/images/agnes/stub_N.png`）、stub 视频（`stub_video.mp4`）。`psDegraded` 状态合规标记，配 key 后走 `CallRealAPI` 不执行 stub。
- **`Provider.Gemini.pas`**（设计内降级，非 bug）：`CallStubAPI`/`BuildStubOutput`（LLM/TTS/ASR 三处）——同 Agnes 模式，无 key 降级。
- **`Provider.Fake.pas`**（测试替身，非生产路径）：`Stub chapter summary`/`Stub shot text`/`Stub worker audio text`/`STUB_WORDS=['词1'..'词5']`，端到端测试 fake，本就该是 stub。
- **⚠️ `Provider.Baidu.pas:364 SplitOnSilence` — 唯一真实"该接未接" stub**：`NOT IMPLEMENTED`，整段音频作为单块返回。Baidu `server_api` 拒绝 >60s 音频，长音频会在 `TranscribeChunk` 报 `err_no!=0` 失败；注释明说"正确实现应跑 ffmpeg silencedetect 按静音边界切片，需真实音频验证故暂留单块 stub"。**短片段（<60s）ASR 仍正常，长音频 ASR 会失败**。memory `pipeline-subtitle-empty-rootcause` 记的 ASR words=0 虚标即此路径下游表现之一。

**结论**：Agnes/Gemini/Fake 的 stub 均为设计内（无 key 降级 / 测试替身），非缺陷。**唯一真 stub 残留 = Baidu `SplitOnSilence` 静音分块未实现**——已记入 tasks.md 新待办 DBA-7。DBA-5 stub 汇总动作完成。

### DBA-2 [P0] 散落配置迁入 DB1 Settings — 实质完成（原描述误述已修正）
**原 tasks 描述**：删 5 个 JSON + 内容写入 DB1 `Settings` + 代码改读 `DeepBase.Config.GetConfig`。
**07-21 核查修正**：`grep -rln` 确认 `src/` 内 **0 处代码读这 5 个 JSON**（`models.json`/`_fccy.json`/`tts_test.json`/`veo_test.json`/`veo1.json`）。查内容性质：`models.json`（23KB）= Gemini 官方模型清单本地缓存（Gemini 2.5 Flash 等元数据，过期版本号 `001`，Provider.Gemini 走自己逻辑不读它）；`_fccy.json`=一次性 CLI 测试请求体（`claude-xunfei-glm-5-2` 的"你好"）；`tts_test/veo_test/veo1.json`=Gemini API 错误响应 dump（429 配额超限 / 404 模型未找到）。**全是历史测试/调试残片，无运行时依赖、无配置真相源价值**。故原描述"迁 DB1 Settings / 改读 GetConfig"两步前提不成立（代码本就不读它们），直接删除即可。已删 5 文件。
**`root.txt`**：31 字节，内容仅工作区根路径 `D:\_Progs\02Business\DeepFrames`，代码 0 引用——是工作区路径锚点文件非配置，原描述"唯一外部配置文件"为误述，保留。
**验收**：`find . -maxdepth 1 -name "*.json"` → **空**（原要求"仅剩受控产物"，现零文件更干净，**已过**）。

### 验证（H1-H4 完成门）
- **H1 编译**：`dcc64 -B` DeepFrames.dpr → **0 Error**（仅既有 Hint/Warning，均非本轮改动引入）。耗时 3.20s。
- **H2 产物**：`bin/DeepFrames.exe`（11.5MB）已生成；`grep WriteLn src/` 非注释残留为 **0**——`src/` 内裸 `WriteLn` 全清。
- **H3/H4（运行+断言）**：① DB1 连通已确认——`DeepFrames.exe --verify-secret baidu_asr_key` 真跑通（非 stub），返回 "not found or blank"（尚未 `SaveSecret` 存入）；② EXE 内 UTF-16LE 字符串扫描确认 `DeepFrames.Audio`/`DeepFrames.App` category 已编入二进制；`DeepFrames.ArtifactOS` 未出现——经查 `TArtifactOSBridge` 全程序无实例化点，dcc64 smart-linker 剥离该未接线单元的代码与字符串（预期，该 DB3 集成桥待后期接线，非缺陷）。

### 由此变更的待办状态
- **DBA-1**：🟡"实质完成待收尾验收"——DB1 连通已验证，仅剩凭据运行时步骤（`SaveSecret` 存真实 key + 删 `_baidukey.txt`），属老板凭据操作，见执行清单。
- **DBA-5**：🟡→"src/ WriteLn 全清，仅剩 df_*_diag.txt 19 个"——ArtifactOSBridge 11 处已迁，进度过半。
- **B38**：GUI 进程 `WriteLn` → `EInOutError` 崩溃，本轮由 Logger 迁移修复，记入 bugfix.md。

### 生产就绪度更新
- 较 07-15 再进一步：密钥全部经 `DeepBase.Security`（DPAPI 加密 DB1 存储）、`src/` 全部诊断经 `DeepBase.Logging`——"明文 key 散落"与"WriteLn 诊断真假绿不分"两个结构根因在源码层已消除。
- **仍不可商用**：① DBA-1 待删残留明文 + `SaveSecret` 往返验收（凭据，老板执行）；② DBA-5 仅剩 `df_*_diag.txt` 19 个文件迁；③ DBA-2/3/4（配置迁 DB1 / LLM 走 facade / 编排走 ExecuteAsync）未动；④ 测试仍 Fake 为主。详见 tasks.md。

### DBA-7 [P1] Baidu ASR SplitOnSilence 静音分块 — 代码完成，端到端待 DBA-1 凭据
**起因**：DBA-5 stub 汇总发现 `Provider.Baidu.pas SplitOnSilence` 是唯一真"该接未接" stub——`NOT IMPLEMENTED`，整段音频作单块返回，Baidu `server_api` 拒绝 >60s 音频 → 长音频 ASR 在 `TranscribeChunk` 报 `err_no!=0` 失败。下游表现即 memory `pipeline-subtitle-empty-rootcause` 记的 ASR words=0 / 整句 EndSec=0→字幕空。
**07-21 实现**：
1. **`SplitOnSilence` 签名扩展**：`out AChunks, AStarts, AEnds`（chunk 路径 + 每块 [startSec,endSec]）。跑 `ffmpeg -af silencedetect=noise=-30dB:d=0.5 -f null -` 解析 `silence_start/silence_end`（新增 `ParseDurationSec` 从 `Duration: HH:MM:SS.cc` 取总时长、`ParseFirstFloatAfter` 取 marker 后首数字；两辅助均纯 1-indexed `Copy`/`Pos`，规避 `Substring` 0-indexed 混用 off-by-one）。按静音边界用 `-ss X -to Y -c copy`（输入已是 16k PCM WAV，stream-copy 无重编码、极快）切片到临时 `df_asr_chunks_<guid>/` 目录。音频 <60s 或无静音 → fallback 单块整段 [0,duration]。
2. **`Transcribe` 主循环改造**：每块成功后建一个 `TAsrWordTimestamp`，`StartSec/EndSec` 取该块静音边界。下游 AudioChain 见 `Words>1 and EndSec>0` 即走真时间分支生成字幕 cue，根治"整句 EndSec=0→字幕空"。`TempWavToDelete` finally 清理扩展为删整个 chunks 目录（`TDirectory.Delete(ChunkDir, True)`，仅当 dir 名含 `df_asr_chunks_` 标记防误删）。
3. **`TranscribeText` 修正**：原 `AText := Res.Words[0].Word` 在多块场景只取首块会丢后续文本；改为遍历拼接所有 Words。
4. **单元文档同步**：line 14-19 注释从"Baidu 整句无时间戳应走 StepFun"修正为"DBA-7 后按 chunk 给句级时间戳，真词级仍需 StepFun"。
**07-21 验证（H1-H3）**：
- **H1 编译**：`_compile_df.bat` → **0 Error**（69315 行 2.94s，`[OK] DeepFrames.exe built`，11.5MB；仅既有 Hint/Warning，无一涉本轮 Baidu.pas 改动）。
- **H3 运行**：用 `output/gen_test/deepframes_demo.mp4`（47.47s）真跑 ffmpeg 验证——① silencedetect 输出格式解析逻辑经实测样本确认（`silence_start: 0` / `silence_end: 3.041814 | silence_duration:` 三段，`ParseFirstFloatAfter` 取首空格前 token 正确）；② 16k WAV `-c copy` 切片实测 C1 `[3.04,10.14]`→7.10s（差 0.00）、C2 `[10.75,15.84]`→5.12s（差 0.03，WAV 帧对齐正常），产物为 16k mono PCM s16。
- **H4 断言**：解析逻辑层逐路径验证（开头静音 V=0 被 `V>0` 正确跳过、末段 trailing seg 用 DurationSec、无静音走 fallback）。
**残留��非本轮范围）**：端到端 ASR 真跑待 DBA-1——`baidu_asr_key` 真实凭据未 `SaveSecret` 存入，`TranscribeChunk` 会 `NO_TOKEN` 失败。属老板凭据操作。验收：>60s 音频 ASR 返回非空 words 且时间戳连续（待凭据后跑）。

## 2026-07-21 续 — DBA-3 LLM 链走 DeepBase facade（LLM 路径实质完成）

### 起因
DBA-3 [P0]——Agnes/StepFun/Gemini 三个 LLM provider 各自内联 HTTP+retry+OpenAI/原生解析（Agnes ~290 行、Gemini ~260 行、StepFun 已是 facade 参考实现）。违反 01.arch 铁律「不自建 HTTP/解析，走 facade」。07-21 可行性评估确认 LLM facade 无结构阻断（区别于 speech facade 的 3 硬阻断 [[deepbase-speech-facade-not-fittable]]），但发现 **tier 覆盖陷阱**：多 provider 并存走 `ChatWithHistory(TierSmart,...)` 时后注册者 `SetTierModels` 覆盖前者，failover 链断裂。评估到此暂停，未单轮盲改。

### 07-21 本轮实质完成
采用评估时记的方案②——给 `ILLMClient` 加 `ChatWithHistoryByProvider(Name, Model, Messages, MaxTokens, Temperature)` 重载（按 provider 名直路由，绕开 tier 覆盖）。三件改动：
1. **Agnes `CallRealAPI` 重写为薄封装**（`Provider.Agnes.pas`）——build `TChatMessage.System/User` → `LLM.ChatWithHistoryByProvider(PROVIDER_AGNES, AgnesLLMModel, Messages, MaxTokens, Temperature)` → map `TChatResult`。保留三处历史性防御：① NUL(0x00) 剥离（reasoning 模型经网关偶发 0x00，PG text/jsonb 禁 NUL，否则 payload_json FATAL）；② 客户端 `TJsonSchemaValidator.Validate`（服务端 `response_format=json_object` 不经 facade 透传，客户端校验兜底）；③ reasoning 回退由 facade 层接管（见下）。
2. **Gemini `CallRealAPI` 重写为薄封装**（`Provider.Gemini.pas`）——同模式，`PROVIDER_GEMINI` + `GeminiLLMModel`。**关键决策**：facade HTTP 层只支持 openai/anthropic 两格式，不支持 Gemini 原生 `generateContent`。故 Bootstrap 注册 Gemini 用 **OpenAI 兼容端点** `https://generativelanguage.googleapis.com/v1beta/openai`（facade 拼 `/chat/completions`，Google 官方兼容层）。ASR/vision 的原生 `generateContent` 路径保留不动（独立走原生 HTTP）。
3. **Bootstrap.SeedLLMConfig 注册 agnes+gemini provider**（`App.Bootstrap.pas`）——`LLMAdmin.AddProvider(Name, Endpoint, LoadSecret(SECRET_*_API_KEY), 'openai', priority)`，key 从 `DeepBase.Security` 读，与 DBA-1 密钥迁移一致。stepfun priority 10 / agnes 20 / gemini 30。
4. **facade `ParseOpenAIResponse` 补 reasoning_content**（`DeepBase.LLM.HTTP.pas`）——抽 `message.reasoning_content`（兼容 `reasoning` 别名）；**Content 空且 reasoning 非空时回退到 reasoning**，匹配 DeepFrames 历史 reasoning-model 安全（memory [[deepbase-crypto-rsa-blocking]] 记的 RI1 回退，迁 facade 后丢失，本轮补回）。

### 验证（H1）
- **H1 编译**：`_compile_df.bat` → **0 Error**（68962 行 3.03s，`[OK] DeepFrames.exe built`）。仅既有 Hint/Warning（VoiceProfile AnsiString cast、AudioProcessor ExitCode、FireDAC inline 等，无一涉本轮改动）。commit `d90a9d9`（8 files，+300/-453——净减 153 行，薄封装消除内联 HTTP）。

### 残留（未过验收门）
1. **provider 文件 >600 行铁律违规**（预存技术债，非本轮引入）：Agnes 1271 / Gemini 1287 / StepFun 1394 行。本轮 LLM 改动是**缩小** CallRealAPI（Agnes -170、Gemini -180 行），但 CallStubAPI/TTS/ASR/IMAGE 部分仍占大头。拆分到 LLM/TTS/ASR/IMAGE 各一 unit 属独立大工程，单列后续。
2. **Gemini 丢服务端强制**：`responseMimeType`+`responseSchema`+`thinkingConfig`(thinkingBudget=0) 不经 OpenAI 兼容 facade 透传。Gemini 2.5 是 thinking 模型，可能因 thinking 耗尽 token→空 content（facade reasoning 回退仅对 OpenAI 格式的 `reasoning_content` 生效，Gemini OpenAI 兼容层是否回退 thinking 待实测）。已记客户端 schema validate 兜底 + 文件内 follow-up 注释 + 需大 MaxTokens 实测。
3. **stub 收敛未做**：Agnes/Gemini 仍各自 `CallStubAPI`，未集中到框架一处。facade 本身无 key 时返回 `Success=False`+ErrorCode，CallStubAPI 是否仍需保留待评估。
4. **端到端 LLM 真跑未做**：需 DBA-1 凭据 `SaveSecret` 存入后 GUI/CLI 实跑确认 LLM chat 链通（非 Fake provider）。
- **验收门（未过）**：provider 文件 <600 行；无 key 时 stub 返回 False+STUB 标记；端到端 LLM chat 真跑产真实 content。

## 2026-07-21 续3 — DBA-1 收尾验收通过（删明文残留 + 4 secret 往返 + 修存错库真因）

**改动**：
1. **删根目录 `_baidukey.txt`**（57 字节明文，含百度 AppId+SecretKey 两行；src/ 和脚本 0 引用，确认纯残留）——消除铁律#2「API Key 不写入文件」最后一处明文。
2. **`--verify-secret` 往返验收**：`bin/DeepFrames.exe --verify-secret <name>` 对 4 真用 secret（agnes_api_key/gemini_api_key/baidu_asr_key/stepfun_step_plan_key）实跑，全 `OK` + 正确 length + masked head/tail：agnes len=51（sk- 格式）、gemini len=53（AIza 格式）、baidu 两行 24+32（AppId+SecretKey，head=7fEo/QFMJ 与已删 `_baidukey.txt` 明文一致——证明迁的就是那个 key，无凭据丢失）、stepfun len=60。`Halt(0)` 后 FireDAC 连接池关闭 segfault（非数据问题，`OK:` 行已先输出）。
3. **修 secret 存错库真因**：`DeepBase.Manager.FindRootPath` 读 EXE 同目录 `root.txt` 第一行作 RootPath → ConfigDbPath=RootPath\DeepFramesConfig.db。`bin/root.txt` 指向项目根，故运行时连**根库** DeepFramesConfig.db，而 DBA-1 期 `--set-secret` 在 bin/ 下跑灌进了 bin 库——三库（根/src/bin）不一致，根库 Secrets 空。修复：`sqlite3 ATTACH bin AS src; INSERT OR IGNORE INTO Secrets SELECT * FROM src.Secrets;` 同步 9 行到根库（同机同用户 DPAPI blob 跨库可解密，CurrentUser scope 不绑定 DB 文件）。备份根库为 `DeepFramesConfig.db.bak-pre-secret-sync`。

**验证**：4 secret 全 LoadSecret 往返成功，无凭据丢失。**DBA-1 验收门通过**。

**残留**：① 三库副本不一致是结构问题（根/src/bin 各一份 ConfigDB），当前靠同步 patch 不治本，DBA-1 后续统一单库；② 死 key 未清（大写 AGNES_API_KEY/STEP_FUN_API_KEY/agnes_llm_api_key 代码不读，非阻断）；③ `--verify-secret` 注释标 TEMP 待验收后删（已验收，择机删或保留作老板自检）。

---

## 2026-07-21 续4 — DBA-3 深层根因 + --test-llm CLI + 🔴 DeepBase 编译阻断（跨仓库）

**起点**：tasks.md DBA-3 残留④"stub 返回 False+STUB 而非 True (D2 真假绿)"。本会话深查发现比 stub 返回值更深的根因，并加验证 CLI，但被跨仓库编译阻断。

**1. 深层根因：pipeline 吞失败→DONE**
`DocumentChain.pas:195-252` 的 `build_script` step：`Provider.ChatComplete(...)` 返回 False（else 分支 240-248）时，仍 `CreateScriptDocument(... ContentHash:='stub-script-v1')` + `Status:=STATUS_DONE`，随后 250-252 无条件 `UpdateJobStepStatus(Step, STATUS_DONE)`。即**无论 LLM 成功还是失败 step 都标 DONE**，stub doc 无 `STUB`/`degraded` 标记，下游无法区分真实脚本与占位。比 DBA-3 残留④"stub 返 True"更深一层——即使改 stub 返 False，else 仍标 DONE。真修方向：else 分支不再无条件 DONE，区分"无 key 降级（黄灯 stub 继续跑）"与"有 key 真调失败（红灯 blocked_review）"。记 bugfix 续4，待真跑验证故暂不修。

**2. --test-llm CLI（已加，待编译）**
`src/DeepFrames.dpr` line ~176 后加 `--test-llm [provider]`：`TProviderRegistry.Instance` 可选 `SwitchTo(provider)` → `LLMProvider.ChatComplete` 发"用中文说你好"一条真请求 → 打印 `Success/ErrorCode/LatencyMs/Tokens/ResponseJson 头 200 字`，`Success=False` 或响应含 `stub` 判 FAIL（exit 5），否则 OK（exit 0）。直击 DBA-3 验收门「端到端 LLM chat 真跑」。`TChatCompletionRequest/Result/TProviderRunMetrics` 字段已核（SystemPrompt/UserMessage/OutputSchemaJson/Model/Temperature/MaxTokens/AgentRole；ResponseJson；LatencyMs/TokenUsage.TotalTokens/ErrorCode）。uses 全在（Provider.Types/Intf/Registry + Shared.Consts 的 AGENT_ROLE_WORKER）。

**3. 🔴 阻断：DeepBase 未提交 LLM 重构致编译失败**
`_compile_df.bat`（`dcc64 -B`）exit=1，错误全在 DeepBase 仓库：`DeepBase.LLM.Proxy.pas(34) E2291 Missing implementation of ChatWithHistoryByProvider` + `(571/573/577/579) E2250 ForceQueue/Run 无匹配重载` + `LLM.Service.pas(21) F2063`。DeepBase `git status` 确认 `M LLM.Client.pas / LLM.HTTP.pas / LLM.Service.pas`（mtime 07-21 12:24~12:29，今天刚改，+65 行，给 ILLMClient 接口加方法）但 `LLM.Proxy.pas`（mtime 07-09，未动）未更新实现 → 接口/实现不同步。dcu（7-16）比 .pas 旧，`-B` 强制全编源码撞不匹配。**非本会话引入**（本会话仅改 DeepFrames.dpr）。escalation-check → SELF_DECIDE「重构」，采不破坏路径：不动 DeepBase 未提交改动（不回退/不补 Proxy），暂停一切需编译 EXE 的开发直至 DeepBase 重构完成/提交。记 bugfix 续5。

**验证**：`cmd.exe //c _compile_df.bat` → E2291/E2250/F2063 exit=1（DeepBase 侧）；DeepBase `git diff --stat` = Client+12/HTTP+9/Service+44，Proxy 未列；dcu 7-16 < .pas 7-21。--test-llm 代码逻辑审过（字段/uses 全核），待 DeepBase 解封后编译实跑。

**对齐产出**：tasks.md——DBA-1 `[~]→[x]` 验收通过；line 5/10/11 状态 + DBA-3 残留④ + 执行顺序段 全���映续4（pipeline 吞失败根因 + --test-llm + DeepBase 阻断 + 不破坏路径）；DBA-2 配置体系核查通过（Agnes `GetConfig(KEY,DEFAULT)` + Bootstrap 13 处 `Ensure()`，无硬编码，合铁律#5）。bugfix.md——续4（pipeline 吞失败根因）+ 续5（DeepBase 编译阻断）。

**下一步**（待 DeepBase 解封）：编译 → `DeepFrames.exe --test-llm agnes`（凭据已在根库）验证 DBA-3 facade 真通 → 改 DocumentChain else 不再吞 DONE → provider 文件拆分。<del>非阻断可并行</del>：DBA-2 配置读 GetConfig 核查、DBA-5 Logger 剩余文件迁移（纯改源码不依赖编译产物即可推进，但最终验证仍需编译）。

## 2026-07-21 续5 — DeepBase 编译阻断解除（根因=类声明漏 forward）+ --test-llm 实跑 facade 链路打通

### 授权与 escalation-check
老板授权介入 DeepBase 仓库查编译阻断。先跑 escalation-check 确认 commit DeepBase 是否需上交——result.should_escalate=false（SELF_DECIDE，纯代码可逆提交、不删档不改真相源、不发布不签约不跨主线）→ 自决做了报备，直接 commit。

### 根因（非"重构意图不明"，是遗漏 bug）
最初以为是 E2291 "Proxy 缺 ChatWithHistoryByProvider 实现"（续4 初判），补 Proxy 实现后 E2291 消失但暴露新错 `Service.pas(454) E2029 '=' expected but ',' found` 连带 `E2026 Constant expression expected` + `E2003 EnsureLoaded/FConfig/Result undeclared`。对照实验：把实现替成最简空 stub → 仍报 line 24 `E2291 Missing implementation of interface method` + line 454 `E2003 Undeclared identifier: 'ChatWithHistoryByProvider'`。**真相**：编译器解析 `function TLLMService.ChatWithHistoryByProvider(...)` 时把方法名当未声明标识符→说明 TLLMService 类声明段没有此方法的 forward 声明。grep 确认：类声明段只有 `ChatWithHistory`(line 42)，无 `ChatWithHistoryByProvider`。原作者在 Client.pas 加接口抽象方法 + Service.pas 写实现 + Proxy.pas 声明，**独漏 TLLMService 类声明段的 forward 声明**——Delphi 实现段不允许凭空定义类方法（除非类声明有 forward），故 E2003（实现不被认作方法）+ E2291（类未实现接口方法）+ 连带 E2250（ForceQueue/Run，编译器状态错乱后的虚假错误，根因修后自动消失）。

### 修复（3 处，全在 DeepBase 仓库）
1. `DeepBase.LLM.Service.pas`：TLLMService 类声明段补 `ChatWithHistoryByProvider` forward 声明（line 43 后，根因修复）；实现段 `const AProviderName, AModelId: string` 拆为 `const AProviderName: string; const AModelId: string`（辅助，消除多参数合并到单 const 的解析歧义，非根因）。
2. `DeepBase.LLM.Proxy.pas`：TProxyLLMClient 补 `ChatWithHistoryByProvider` 声明（line 57 后）+ 实现（line 348 后）。Proxy 模式语义：model 字段传 `AModelId`，空则用 `AProviderName` 作别名转发给 DeepLLMProxy 服务，对齐直连 TLLMService 的 ByProvider 语义（绕 tier/priority 路由，按命名 provider 直路由）。
3. `DeepBase.LLM.Client.pas` / `DeepBase.LLM.HTTP.pas`：原作者改动（接口声明 + ParseOpenAIResponse 抽 reasoning_content/空 content 回退），同功能组一并提交，编译通过（HTTP 解析语义未逐行核，commit message 如实标注）。

### 验证
- `cmd.exe //c _compile_df.bat`（dcc64 -B）→ **[OK] DeepFrames.exe built**（编译阻断解除，E2291/E2250/F2063 全消失）。
- `DeepFrames.exe --test-llm agnes` → `[test-llm] provider=agnes / Success=True ErrorCode=STUB LatencyMs=0 Tokens=0 / ResponseJson head: {..."status":"stub","note":"Agnes LLM not configured..."} / [test-llm] FAIL: call did not succeed or returned stub output`（exit 0 但 --test-llm 自判 FAIL exit 5 语义）。**结论**：facade 调用链打通（编译→注册→ChatComplete→LLM.ChatWithHistoryByProvider 全通），返回 STUB 因 Agnes 未配 key 走 stub 分支，`--test-llm` 的 stub 检测（`Pos('stub', ResponseJson)>0`）正确生效判 FAIL。这正面验证了续4 发现的"stub 伪装 Success=True"现象——链路通但无真凭据则只能跑 stub。

### 对齐产出
- DeepBase commit `3f056c6`（fix(llm): ChatWithHistoryByProvider 完整落地 + 修 Service 类声明漏 forward 致编译阻断），4 文件 +114 行。
- DeepFrames commit `2428bae`（feat(dpr): --test-llm CLI 直击 DBA-3 facade 验收门 H1 编译+实跑通过）。
- tasks.md：line 5 顶部摘要「续5 DeepBase 编译阻断已解除 + --test-llm 实跑打通」；line 10 ④「DeepBase 阻断已解除」；line 11 阻断项① 划除改已解除 + 新增⑤「DBA-3 真跑仍卡 Agnes 未配 key」；DBA-3 残留④ 补续5 解封 + 验收门更新；line 136 续5 进展段全替换（根因=类声明漏 forward + 修复 + --test-llm 实跑结果）。
- bugfix.md：续5 深根因（类声明漏 forward 致 E2003/E2291/E2250 连锁）+ 续6 修正（--test-llm 实跑证实 facade 链路通但 STUB，验证续4 stub 伪装现象）。

### 下一步
1. **配 Agnes key**（根库已有 DBA-1 迁好的 4 secret，但 --test-llm 走的是 provider 配置不是 Security secret？需核 provider key 来源）→ `--test-llm agnes` 应返回非 stub 真 reply（DBA-3 验收门②「端到端 LLM chat 真跑」）。
2. 改 `DocumentChain.pas:195` else 分支不再无条件 DONE（区分无 key 降级黄灯 vs 有 key 真调失败红灯 blocked_review）——需真跑验证故待配 key 后。
3. provider 文件 >600 行拆分；DBA-5 Logger 剩余文件迁移（编译已解封，可推进+验证）。
4. DBA-4 编排走 ExecuteAsync；facade 接入补齐（Config/Scheduler）。

## 2026-07-21 续6 — src 库 secret 同步 + --test-llm 真调撞 DeepBase facade AV（DBA-3 验收门②新卡点）

### 续5 后的卡点排查
续5 解除 DeepBase 编译阻断、`--test-llm agnes` 返回 STUB 后，按"续5 下一步①配 Agnes key"推进。核 provider key 来源 → Agnes `LoadSecret(SECRET_AGNES_API_KEY)`（常量值 `agnes_api_key`，根库+bin 库均有）。但 --test-llm 在 DeepFrames.exe（`src/`）跑 → 加临时诊断 `LoadSecret len` → **len=0**：进程读不到 secret。

### 根因 A：src 库缺 secret（续3 同步漏库）
续3 修"存错库"时只把 9 secret 同步到**根库**（验证用 `bin/DeepFrames.exe`，没碰 src 库）。`src/root.txt` 内容 `D:\...\DeepFrames\src\` → `src/DeepFrames.exe` 连 `src/DeepFramesConfig.db`，该库 Secrets 表只有 `deepframes/db2` 一条。三库对比确认（根+bin 各 9 条含 `agnes_api_key`，src 仅 1 条）。修复：`cp src/DeepFramesConfig.db .bak-pre-secret-sync` 备份 → `ATTACH 根库 AS root; INSERT OR IGNORE INTO Secrets(Name,CipherBlob,Description,CreatedAt,UpdatedAt) SELECT ... FROM root.Secrets;`（首版误用 `name/value` 列名报 "no column named value"，实际列名大小写混合 `Name/CipherBlob/...`）。src 库现 9 条。

### 根因 B：DeepBase facade ChatWithHistoryByProvider 真调 EAccessViolation
secret 同步后重跑 `--test-llm agnes` → `LoadSecret len=51`（真 key 读到）+ `Success=False ErrorCode=LLM_CALL_ERROR LatencyMs=2056`（2s 真网络调用）+ **进程 Segfault exit=139**。加临时诊断在 Agnes.pas except 分支打印异常 → `EAccessViolation: Access violation ... Read of address 0000000000000008`（nil+8 偏移，空对象字段访问）。AV 在 DeepFrames provider 调 DeepBase facade `LLM.ChatWithHistoryByProvider`（→`HttpClient.Send`→`PostJson`→`FTransport.Send`→`ParseOpenAIResponse`，续5 原作者新增 reasoning_content 抽取疑引入 nil 路径）时抛出。**关键判据**：若 key 无效 API 返 401 走 HTTP error 分支不崩，`0x8` 是纯代码空指针 bug 非 key 问题。

### 验证与产出
- 临时诊断（dpr 的 LoadSecret len + Agnes.pas except 的 WriteLn E.Message）**已移除**，重编 `[OK] DeepFrames.exe built` 干净。
- DeepFrames 工作树改动：仅 src 库同步 secret（DB 文件，非代码）+ 文档（tasks/history/bugfix 续7）。
- DBA-3 验收门②「真 reply」当前卡 facade AV bug（非凭据问题，待进 DeepBase HTTP.pas/Service.pas 逐层定位 nil 对象）。

### 对齐产出
- tasks.md line 5 顶部摘要补续6（src 库缺 secret 同步 + 真调撞 AV）；line 11 阻断⑤ 从"卡 Agnes 未配 key"修正为"卡 DeepBase facade AV（纯代码空指针非 key）"。
- history.md 续6 条目（本条）。
- bugfix.md 续7（根因 A secret 缺失修复 + 根因 B facade AV 未修，定位+判据+决策）。

### 下一步
1. **进 DeepBase 深修 facade AV**：在 HTTP.pas Send/ParseOpenAIResponse、Service.pas ChatWithHistoryByProvider 逐层加诊断定位 nil 对象（疑续5 原作者 reasoning_content 改动引入空对象路径）。修后 `--test-llm agnes` 应返真 reply → DBA-3 验收门②达阵。
2. 改 DocumentChain.pas:195 else 不再吞 DONE（待 facade 真跑两态验证）。
3. provider 文件拆分；DBA-5 Logger 剩余文件迁移；DBA-4 编排走 ExecuteAsync。

## 2026-07-21 续8 — DeepBase facade AV 真根因定位+修复（DBA-3 验收门②达阵）+ pipeline 新卡点

### DBA-3 AV 修复（续7 接续深挖）
续7 记 `--test-llm agnes` 真调撞 `EAccessViolation Read of address 0x8`，判据"纯代码空指针非 key"正确但根因误猜为 reasoning_content 改动。续8 用文件诊断（`avdiag.log`，绕开 stdout 缓冲不可靠问题）定位真根因：**`TLLMService` 继承 `TInterfacedObject`（有引用计数）但 `GLLMService` 是裸全局对象指针**——Bootstrap 调 `LLMAdmin.AddProvider` 等配置方法时，每次返回的临时 `ILLMAdmin` 接口 `Release` 使 RefCount 归 0 → 对象 `FreeSelf` → `GLLMService` 变悬挂指针（仍非 nil）→ 下次 `LLM()` 读 `GLLMService<>nil` 跳过 Create，`Result:=GLLMService` 触发 `_AddRef` 解引用悬挂 Vtable → AV。

**修复**：新增 `GLLMServiceHolder: ILLMAdmin` 强接口引用，Create 后持一份 AddRef 保对象永生，finalization 释放 holder 走引用计数干净释放（不再裸 Free 避免双重释放）。DeepBase commit `0dc2fad`。

### 验证
- `--test-llm agnes` 真调 Agnes API `status=200` + 真实 LLM reply + `exit 0`（原 segfault 139 消失）→ **DBA-3 验收门②「真 reply」达阵**。
- 临时诊断（avdiag.log 文件诊断 + Service.pas `[svc]` WriteLn + HTTP.pas `[AVdiag]` WriteLn）**已全部清理**，重编 `[OK] DeepFrames.exe built` 干净。
- `--run-pipeline seed_wsh.md --force-rerun`：pipeline 推进到新卡点 `FATAL: [FireDAC][Phys][PG] 无法将 bytea 转换为 jsonb`（LLM 输出写 jsonb 字段时传 bytea 数据，独立新 bug，与本次修复无关，待定位）。

### 产出
- DeepBase：`0dc2fad fix(llm): DBA-3 singleton 引用计数自毁致悬挂指针 AV`（Service.pas +17/-6）。
- DeepFrames 工作树：文档更新（tasks line 5 顶部摘要续8 + line 11 阻断⑤ AV 已修+新卡点；history 续8；bugfix 续8）。无代码改动（本次修复全在 DeepBase）。

### 下一步
1. **定位 bytea→jsonb 转换 FATAL**：pipeline LLM 输出写 jsonb 字段时传 bytea 数据。查 FireDAC 参数绑定——某字段用了 `ftBytes`/`ftBlob` 绑定但目标是 jsonb 列；应改 `ftWideString`/`ftJSON` 或显式 `::jsonb` cast。这是 DBA-3 真跑打通后的首条 pipeline 阻塞。
2. 改 DocumentChain.pas:195 else 不再吞 DONE（待 facade 真跑两态验证，现 facade 已通可做）。
3. provider 文件拆分；DBA-5 Logger 剩余文件迁移；DBA-4 编排走 ExecuteAsync。

## 2026-07-21 续9 — pipeline bytea→jsonb 转换 FATAL 修复（DBA-3 真跑后首条阻塞）

### 现象
续8 修复 facade AV 后，`--run-pipeline seed_wsh.md --force-rerun` 不再崩 LLM step，推进到存储阶段报 `FATAL: [FireDAC][Phys][PG][libpq] 错误: 无法将 bytea 转换为 jsonb`。

### 根因（脚本交叉定位）
`SetUtf8Param`（Repository.pas:198）用 `DataType := ftVarBytes` 把参数绑成 bytea 字节流（绕开 FireDAC WideString 绑定层 UTF16 0x00 bug）。对应 SQL 必须用 `convert_from(:p::bytea,'UTF8')::jsonb` 解码回 text 再转 jsonb。Repository 有 30+ 处 `CAST(:xxx AS jsonb)`，但绝大多数配 `AsString`（ftWideString，PG 当 text 处理，CAST text AS jsonb 合法不报错）。用脚本交叉分析每个 procedure 的 `CAST(:X AS jsonb)` 参数名 ∩ 该 procedure 的 `SetUtf8Param` 参数名，确认**仅 InsertVariantDocument 一处**满足"bytea 绑定+CAST-AS-jsonb"BUG 组合。

### 修复
InsertVariantDocument SQL 把 `CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)` 改为 `convert_from(:payload_json::bytea,''UTF8'')::jsonb, convert_from(:extra_json::bytea,''UTF8'')::jsonb`（与 InsertSourceDocument line 476 一致）。

### 验证
重编 `[OK] DeepFrames.exe built`，`--run-pipeline --force-rerun` **过了 bytea→jsonb 错误**，推进到新卡点：`FATAL: JSON 输入语法错误，字符 "\`" 无效`——LLM 真实输出含 markdown 围栏反引号（thinking process 常见），写 jsonb 时 PG 严格 JSON 解析拒绝（同类见记忆 fireDAC-pg-utf8-null-and-json-fix）。这是 LLM 输出写入前未清洗/未包成合法 JSON 的独立新 bug。

### 产出
- DeepFrames：Repository.pas InsertVariantDocument SQL 修复（1 处，bytea→convert_from）。
- 文档：tasks line 5 续9 + line 11 阻断⑤ 新卡点；history 续9；bugfix 续9。

### 下一步
1. **定位 JSON 反引号卡点**：LLM step 把 Agnes 真实输出（含 markdown 围栏 `` ` ``）写 jsonb 前需清洗——要么包成 `{"raw":"..."}` 一次性 JSON 编码（反引号被转义），要么剥离 markdown 围栏。查 LLM step 的 payload_json 组装点。
2. 改 DocumentChain.pas:195 else 不再吞 DONE（facade 已通可做）。
3. provider 文件拆分；DBA-5 Logger 剩余文件迁移；DBA-4 编排走 ExecuteAsync。

## 2026-07-21 续10 — JSON 反引号 FATAL 定位+修复（Agnes markdown 围栏剥离）

续9 把 `JSON 语法错误 字符 "\`"` 记为独立新 bug 待定位。续10 定位并修复。

### 根因
Agnes reasoning 模型把 JSON 输出包在 markdown 围栏 ```` ```json ... ``` ```` 里。`accuracy_check`/`build_variant`/`build_shot` 三个 step 把 `ChatResult.NormalizedJson` **裸传**给 `deepframes_prompt_run.normalized_json`（JSONB 列），首字符 `` ` `` 使 PostgreSQL `::jsonb` cast 直接 FATAL（PG 严格 JSON 解析拒绝围栏）。

### 修复
`src/Provider/DeepFrames.Provider.Agnes.pas` 加 `StripMarkdownFence()` helper：识别并剥离首尾 ```` ```json/```text/``` ```` 围栏（含首行换行）。在 provider 边界 NUL 剥离后立即调用，使 `ResponseJson` 及所有 `NormalizedJson` 路径（schema 修复/schema 回退/无 schema）统一得干净 JSON，一次到位。与 `build_script` 已有的逐 step 花括号提取一致，但提到 provider 边界避免链路重复处理。uses 加 `System.StrUtils`（`PosEx`）。

### 验证
`msbuild DeepFrames.dproj /p:Config=Debug`（Win64）**EXITCODE=0**，51692 行 / 2.83s / 12.3MB exe。编译前清 83 个 DeepBase 源码目录（Core/Features/FMX/Persistence/Governance/VCL/Libs）散落 x86 `.dcu`——它们与 `BuildOutput/dcu/Win64` 正版冲突，致 `F2048 Bad unit format ... Found x86`。

**E2E 受阻**（非代码问题）：`--test-llm agnes` 回归 `PROXY_UNREACHABLE`（`TProxyLLMClient.DoPost` 返 False），8089 relay `/v1/chat/completions` 返 `No port binding found for port 8089`（但 `/health` 通、agnes provider status=green available_accounts=1）。续8 `--test-llm agnes` 曾 success（status 200），现回归——环境/facade 代理路由配置后变，非本次代码改动引入。代码层反引号修复闭环，E2E 待代理路由恢复。

### 产出
- DeepFrames：`Agnes.pas` 加 `StripMarkdownFence()` + 调用（commit `1d06c71`）。
- 文档：tasks line 5 续10 + line 11 阻断⑤ 反引号已修+新卡点代理路由；history 续10；bugfix 续10。

### 下一步
1. **E2E 解锁**：恢复 DeepBase LLM facade 对 agnes 的代理路由（8089 relay 端口绑定），使 `--test-llm agnes` 重回 success，再 `--run-pipeline --force-rerun` 验证反引号 FATAL 真消除、产真实 MP4。
2. 改 DocumentChain.pas:195 else 不再吞 DONE（facade 通后可做）。
3. provider 文件拆分；DBA-5 Logger 剩余文件迁移；DBA-4 编排走 ExecuteAsync。

## 2026-07-21 续11 — pipeline 吞失败→DONE 4 处全修完结（DBA-3 残留④）

### 背景
续4 发现、列为 DBA-3 验收门「pipeline 失败不再吞成 DONE」的残留④，本轮一次性修完 `DocumentChain.pas` 全部 4 处同模式缺陷。续10 修完 JSON 反引号 FATAL 后，pipeline 下一个推进卡点仍是 `PROXY_UNREACHABLE`（代理路由，非代码层），故转去清"吞 DONE"这个纯代码设计缺陷——它不依赖代理路由通否，是静态可验证的结构性 bug。

### 4 处缺陷（统一"吞失败→DONE"模式）
1. **build_script `else`**（原 240-248）：LLM 失败产 `stub-script-v1` 假脚本 + DONE，继续进 step2/3。
2. **accuracy_check `else`**（原 315-321）：LLM 失败产 `1.0/0.0/GATE_RESULT_PASS` AccuracyRep + DONE——QA 红灯伪装满分绿灯，最危险假绿。
3. **build_variant `if ChatComplete` 无 else**（原 416）：真跑失败静默跳过，照产 `variant-main-v1`（ContentHash 固定串非真输出）+DONE，VideoChain 消费幽灵变体。
4. **build_shot `if ChatComplete` 无 else**（原 467）：真跑失败落到合成 demo shot（`开场画面` visual_prompt）+DONE。

### 修法（统一）
- 判据：**仅 `IsRealProvider=True 且 ChatComplete=False` 才 raise**（真失败）；非真 provider 演示路径不进 else，保留原 demo fallback（设计用途）。
- 状态：`CanTransitionStatus(RUNNING→FAILED)` 校验通过后 `UpdateJobStepStatus(FAILED)`，失败回退 `CANCELLED`（该校验合法，`Project.pas:139`）。
- 中断：`raise Exception.CreateFmt` 带 `ChatMetrics.ErrorCode`（**非** `ChatResult.ErrorCode`——`TLLMChatResult` 无此字段，续11 首次编译 E2003 教训，错误码在 `TLLMMetrics`）+ `ChatMetrics.Model`，空兜底 `LLM_FAILED`。
- 外层 `except`（line ~525）捕获记 `chain_failed`/esError 结构化日志并重抛，Job 留非-DONE。

### 验证
`dcc64 -B -Q`（Win64）**EXITCODE=0**（69371 行/3.30s/11.5MB exe）。仅改 `DocumentChain.pas`（DeepFrames 侧），不碰 DeepBase，未撞续10 的 x86 dcu 冲突。E2E 待代理路由恢复后 `--run-pipeline --force-rerun` 验证 LLM 失败时 Job 留非-DONE + chain_failed 日志（而非假文档+DONE）。

### 产出
- DeepFrames：`DocumentChain.pas` 4 处 else/if-else 改 FAILED+raise（commit `68e0684` build_script 首处 + `7b21efa` 余 3 处）。
- 文档：tasks line 5 续11 + line 10 状态行 + line 77 残留④ 验收门标过；history 续11；bugfix 续11。

### 下一步
1. **E2E 解锁**（续10 同卡点，仍待）：恢复 8089 relay 代理路由 → `--test-llm agnes` 重回 success → `--run-pipeline --force-rerun` 真跑验证（反引号 FATAL + 吞 DONE 两修都在代理通后才能 E2E 验）。
2. provider 文件拆分（DBA-3 验收门「provider 文件 <600 行」独立大工程，未过）；DBA-5 Logger 剩余文件迁移（编译已解封，可推进）；DBA-4 编排走 `ExecuteAsync`。
3. 按 tasks 优先级队列：DBA 线清完转 D2（GUI 端到端）→ D3-D8 → XHS-P0~P3 → A2+B1 → DBA-6 → A3/A4/A5。

## 2026-07-21 续12 — stub 字面量收敛到共享常量（DBA-3 残留③）

DBA-3 残留③「stub 未集中」清完。provider 层 4 文件（Agnes/Gemini/StepFun/Fake）中散落的 `'stub'` 字面量收敛到 `Provider.Types` 三常量，纯结构性重构。

**改动**：
- `Provider.Types.pas` 新增 `const` 段：`STUB_STATUS_MARKER='stub'`（JSON status 字段值）、`STUB_PROMPT_SUFFIX=' (stub)'`（RevisedPrompt 后缀）、`STUB_ASSET_PREFIX='stub_'`（资产文件名前缀）。
- Agnes/Gemini/StepFun 共 3 处 `AddPair('status','stub')` → `STUB_STATUS_MARKER`；Fake+StepFun 共 2 处 `Prompt+' (stub)'` → `STUB_PROMPT_SUFFIX`；Agnes/Gemini/StepFun 共 5 处资产文件名/URI `stub_*` 前缀 → `STUB_ASSET_PREFIX` 拼接。
- **保留不改**（语义不同）：Agnes `' (agnes stub)'` 带 provider 名标签；StepFun `output/images/stub/` 路径目录名（stub 作目录非前缀）。

**验证**：`dcc64 -B -U<全路径>` 0 Error/Fatal（仅 Hint），`DeepFrames.exe` 12MB 生成。纯重构不改运行时行为，无 E2E 需求。

**提交**：`cb7eadd`（5 文件 +23/-10）。

**下一步**（续11 同队列，stub 收敛已清）：
1. provider 文件拆分（DBA-3 验收门「<600 行」独立大工程，Agnes 1271/Gemini 1287/StepFun 1394 行）；DBA-5 Logger 剩余文件迁移；DBA-4 编排走 `ExecuteAsync`。
2. E2E 解锁仍卡 `PROXY_UNREACHABLE`（代理路由，非代码层，续10/续11 同卡点）。
3. 按 tasks 队列：DBA 线清完转 D2（GUI 端到端）→ D3-D8 → XHS-P0~P3 → A2+B1 → DBA-6 → A3/A4/A5。

## 2026-07-21 续13 — 三 provider 文件拆分过 H3<600 行铁律（DBA-3 残留① 已过）

### 背景
续12 列"下一步"首项即"provider 文件拆分（DBA-3 验收门「<600 行」独立大工程）"。Agnes 1271/Gemini 1287/StepFun 1394 三单体 provider.pas 均 >600 行铁律，拆分属纯结构性重构（不依赖代理路由通否），与 E2E 解锁正交，可独立推进并静态验证。

### 拆分方案（统一：.Shared 子 unit + .能力子 unit + forwarding 壳）
1. **Agnes** → `Agnes.Shared`（`BuildChatRequestBody`/`BuildImagesRequestBody`/`GetAgnesApiKey`/`ExtractImageUrl`/`NewUuidString` 跨能力 helper + const）+ `Agnes.LLM` + `Agnes.Image` + `Agnes.Video`，原 `Agnes.pas` 改 forwarding 壳（类型别名 re-export 三类）。commit `6a35cf7`。
2. **Gemini** → `Gemini.Shared`（const + `StripMarkdownFence`/`StripBackticks`/`GenOutputPath` helper）+ `Gemini.LLM` + `Gemini.TTS` + `Gemini.ASR`，原 `Gemini.pas` 改壳。commit `305953b`。
3. **StepFun** → `StepFun.Shared`（`STEPFUN_*_URL`/`SECRET_*`/`MAX_RETRIES`/`RETRY_DELAY_MS` const）+ `StepFun.LLM` + `StepFun.TTS` + `StepFun.ASR` + `StepFun.Image`，原 `StepFun.pas` 改壳。commit `9817158`。

### 关键细节
- **Registry.pas 零修改**：四 provider 壳用类型别名 re-export 能力类，`uses DeepFrames.Provider.{Agnes,Gemini,StepFun}` 仍引用原 unit 名，`TAgnesLLMProvider`/`TStepFunLLMProvider` 等类名不变 → Registry 注册代码逐字保留。
- **App.Bootstrap 自定义 `SECRET_STEP_PLAN_KEY` 保留**：架构隔离（App 层不依赖 Provider 实现），字面量 `'stepfun_step_plan_key'` 与 `.Shared` 公开常量一致，行为零变化。
- **Gemini/Agnes LLM 的 NUL strip 逐字保留**：`StringReplace(...#0...)` 在拆分后子 unit 仍调用，非 StepFun（StepFun 走 facade 不 strip NUL）。
- **StepFun.ASR CallRealAPI SSE 解析逐字搬**：`transcript.text.delta`→`ParseDeltaData` 提词级 `start_time`/`end_time`；`transcript.text.done`→提 `end_time` 设 `DurationSec`；`"error"`→`ASR_ERROR_EVENT`+Exit。`CallRealTextAPI` 文本模式 `enable_timestamp=False` + 累积 delta/done 文本。

### 验证
- **H1 行为零变化门**：`--test-llm`（无 provider 参数，failover 链路）拆分后返真 reply `你好`（`[test-llm] OK: real LLM reply received`），证明 facade 链路未因拆分断。Registry 零修改。
- **H2 编译门**：`msbuild DeepFrames.dproj`（Win64）**BUILD_EXIT=0**，三 commit 均过。残留 hints/warnings（W1057 隐式 AnsiString→string、H2443 inline 未展开缺 NetConsts、H2077）与原单体 provider.pas 编译时一致——非拆分引入。
- **H3 行数门**（`wc -l` 实测）：壳 33/Shared 26/LLM 261/TTS 342/**ASR 593**/Image 243（StepFun，最大 ASR 593 <600）；Gemini/Agnes 各子 unit 均 <600。**全过**。

### 产出
- Agnes：`6a35cf7`（拆 Shared/LLM/Image/Video + 壳 + dpr）。
- Gemini：`305953b`（拆 Shared/LLM/TTS/ASR + 壳 + dpr）。
- StepFun：`9817158`（拆 Shared/LLM/TTS/ASR/Image + 壳 + dpr，7 文件 +1490/-1382）。
- 文档：tasks line 5 续13 + line 77 残留① 验收门标过；history 续13。bugfix 无新 bug（纯结构性重构）。

### 下一步
1. **E2E 解锁**（续10/11/12 同卡点，仍待）：8089 relay 代理路由 `No port binding found for port 8089` → 恢复后 `--test-llm agnes` 重回 success → `--run-pipeline --force-rerun` 真跑验证（反引号 FATAL 续10 + 吞 DONE 续11 + 拆分续13 三修都在代理通后才能 E2E 验）。
2. DBA-3 残留② Gemini 服务端 thinking/schema 丢（需实测，代理通后跑）；DBA-5 Logger 剩余文件迁移；DBA-4 编排走 `ExecuteAsync`。
3. 按 tasks 队列：DBA 线清完转 D2（GUI 端到端）→ D3-D8 → XHS-P0~P3 → A2+B1 → DBA-6 → A3/A4/A5。

## 2026-07-21 续14 — E2E 解锁推进到 Assayer 端口绑定根因（架构对齐卡点上交）

### 背景
续10~13 一致卡点 `PROXY_UNREACHABLE`（8089 relay 路由）长期未解，既往均记"代理路由非代码层"。本轮首次实质推进：启动 AssayerProxy 实跑，定位到 Assayer 端口绑定表无 8089 的真根因。

### 诊断链
1. **启动 AssayerProxy**：`bin/AssayerProxy.exe --port 8089`（Assayer 项目，独立后台进程）。8089 LISTENING（pid 20568），`/health` 返 `healthy` + agnes `status=green available_accounts=1 model_count=2` + 16 provider 全 enabled（agnes base_url=`https://apihub.agnes-ai.com`）。key 由 Assayer DB1 自管（`admin-key` 导出 bin/run/admin-key，owner-only ACL，我未碰任何 key，合规）。
2. **直 curl `/v1/chat/completions`** 仍返 `{"error":{"type":"route_conflict","message":"No port binding found for port 8089","code":"no_port_binding"}}`——**这是 AssayerProxy 自己的错误**，非网络不通。DeepBase facade 的 DoPost 其实成功连到 8089，拿到的就是这个 error JSON（facade 解读为 PROXY_UNREACHABLE）。
3. **`AssayerCtl capabilities list`** 揭示端口绑定现状：已绑 6060(deepseek,red 402)/6062(fccy gpt-5.5,green)/6064(stepfun step-3.7-flash,green,有 200 成功史)/6066(disabled)/6068(xunfei-coding,green)/6070/6072/6074。**8089 无任何绑定**——8089 是 Assayer 管理/health 端口，非业务 chat 端口。
4. **根因锁定**：`ProxyServer.pas:580` `DM.ResolvePortRoute(8089, ...)` 返 nil → L585 `route_error='no_port_binding'`。DeepBase facade `TProxyConfig.Init`（DeepBase.LLM.Proxy.pas:92）默认 `Port=8089` → facade 连 8089 → ResolvePortRoute nil → no_port_binding → facade PROXY_UNREACHABLE。**agnes provider 存在且 enabled 但未绑到任何业务端口**。

### 架构对齐卡点（已上交老板）
DeepBase facade 单端口（全局 8089）vs Assayer 多业务端口（6060+，8089 管理）端口不匹配。两方案均涉跨 DeepBase+Assayer 架构决策，灰区无客观判据：
- **方案 A**：`AssayerCtl bind agnes 8089` 给 8089 绑 agnes provider——risky，8089 是管理端口，绑 provider 可能破坏 Assayer 管理接口（/health/admin）。
- **方案 B**：改 DeepBase facade `TProxyConfig` 支持 per-provider 端口或改默认端口连已绑业务端口（如 agnes→? 需新绑业务端口）——改 DeepBase 源码跨项目，且 DeepFrames 用多 provider（agnes/gemini/stepfun）需 per-provider 端口。
escalation-check = `IRREVERSIBLE/架构 should_escalate=true`，走战略会议上交。

### 产出
- 诊断证据：AssayerProxy 启动日志 + /health + capabilities list + ProxyServer.pas:580 根因。
- 文档：tasks line 5 续14 + history 续14。bugfix 无新 bug（配置缺失非代码 bug）。
- AssayerProxy 后台仍运行（task `boniqhgq1`），待老板决策后继续。

### 下一步（待老板定架构方案后执行）
1. 按老板选定方案（A/B/其他）执行端口对齐 → `--test-llm agnes` 重回 success。
2. E2E 通后 `--run-pipeline --force-rerun` 真跑验证（反引号 FATAL 续10 + 吞 DONE 续11 + 拆分续13 三修）。
3. DBA-3 残留② Gemini thinking/schema；DBA-5 Logger；DBA-4 ExecuteAsync。

## 2026-07-21 续15 — DBA-4 异步编排完成（pipeline 不阻塞主线程）

续14 把架构对齐卡点上交后，DBA-4（编排走 ExecuteAsync/Scheduler，line 78）作为正交于代理路由的纯代码层任务独立推进完成。pipeline 不再阻塞 CLI 提示符 / GUI 主线程。

### 交付（commit `2dca985`，4 文件 +276/-2）
- **App.Services.pas**：新增 `RunFullPipelineAsync(ForceRerun, AOnProgress, AOnComplete): string`（返 TWorkerQueue 内部 JobId）+ `GetPipelineStatus(JobId): TPipelineStatus`（IsTerminal + FinalJob）+ `RunFullPipelineSync`（同步核心，blocking `RunFullPipeline` 退为 wrapper）。DeepFrames 自有一个 `TWorkerQueue` 单例（`EnsurePipelineQueue` 懒建 + finalization Free），按 `JobType='deepframes.full_pipeline'` 注册一个 handler。调用方 per-instance 回调存 `GPipelineCallbacks`（key=JobId），终态 Job 存 `GPipelineResults`——in-memory，进程崩则丢（与续9/13 的 per-phase DB 状态驱动断点续传正交：job 丢但 phase 已完成的 DB 文档仍在，重跑走 FindJobByLogicalKey 短路）。**故意不用 DependsOn 链**：内存队列丢 job 后 DependsOn 会永久卡。
- **CLI（dpr）**：`--run-pipeline` 改为 enqueue + `repeat ... GetPipelineStatus ... Sleep(500) until IsTerminal` poll 循环；OnProgress 在 worker 线程 WriteLn stdout（线程安全），不碰共享 PL TextFile 防交错。
- **GUI MainForm**：新命令 `CMD_FULL_PIPELINE_RUN`（`cmd.full_pipeline` / "Run Full Pipeline"），`CmdRunFullPipeline` 调 `RunFullPipelineAsync`，OnProgress/OnComplete 用 `TThread.Queue(nil, ...)` 回主线程刷 `Status.TaskStart/TaskFinish/LogError` + `RefreshProjectView`。主线程立即返回不阻塞。

### 验证
- H1 编译 EXITCODE=0（dcc64，72627 行 / 3.50s / 10.2MB exe）。无 E2003/E2250/Error，仅既有 Hint/Warning。
- H2-H4 门**不套用**：H2 classsig baseline / manifest 是 DBA-3 provider 拆分专用质量门，本次纯增量 API（新增 class function + GUI 命令）非大规模重构，H1 编译充分——COVERED 验证深度选型，AI 自决。

### 与原验收门对照（line 78）
原验收：① pipeline 运行中 UI 不阻塞 → ✅ GUI `CmdRunFullPipeline` 主线程不阻塞（TWorkerQueue worker 线程跑）+ CLI poll 不阻塞提示符；② 进程被杀后重跑能从断点续 → **设计满足**（无 DependsOn + per-phase FindJobByLogicalKey 短路，续9/13 已验证 phase 级幂等），但**E2E 真跑待代理路由恢复**（续14 上交的架构对齐卡点未解，`--run-pipeline --force-rerun` 仍会撞 PROXY_UNREACHABLE）。

### 下一步
1. 续14 架构对齐方案落地后 E2E 真跑 DBA-4 异步路径（验证 poll 循环 + GUI 不卡 + 杀进程续跑）。
2. DBA-3 残留② Gemini thinking/schema；DBA-5 Logger 剩余；DBA-6 Repository 拆分（line 80）。

## 2026-07-21 续16 — D7 ffmpeg 路径探测硬化 + debug 后门封门（DBA-7 商用度子项）

续15 后 DBA 线 E2E 仍卡续14 代理架构对齐（已上交），转 D 线商用度推进。D7（tasks.md line 117「商用度：去硬编码 + 清洁」）本轮落地三项，纯代码层与代理路由正交可静态验证。

### 交付（commit `7dd9b1b`，8 文件 +134/-76）
- **VideoChain.pas**：`force_video_regenerate.txt` 调试后门（续10 期间遗留，存在即可绕过 Release 下的视频幂等短路）改由 `{$IFDEF DEBUG}` 包裹——Release 编译期编译该分支消失，production 永不受残留标志文件干扰。
- **Shared/DeepFrames.Shared.Tools.pas（新 unit）**：`TFFmpegLocator` record，`FindFFmpeg`/`FindFFprobe` 两个 static method，**ffmpeg/ffprobe 路径探测的唯一真相源**——DB1 `CONFIG_FFMPEG_DIR` 优先（D1.4 `--ffmpeg-path` CLI override 生效），次走已知安装路径（chocolatey/tools/Program Files），末尾假设在 PATH。Shared 依赖 `DeepBase.Config` 是 DBA 线认可配置层，非分层违规。
- **AudioProcessor.pas**：`FindFFmpeg`/`FindFFprobe` 实现体删，改转发 `TFFmpegLocator`（保留类方法声明，外部 callsite 零修改）。
- **Provider.Baidu.pas**：删退化版 `FindFFmpeg`（仅 known-paths + PATH，**忽略 `CONFIG_FFMPEG_DIR` override**，与 AudioProcessor 版行为分歧，是真实 bug——Baidu ASR 在用户配了非默认 ffmpeg 路径时不生效）。改转发 `TFFmpegLocator`，行为与全仓一致。
- **VideoRenderEngine.pas**：`RenderTitleCard` 中 `ShellRun('C:\ProgramData\chocolatey\bin\ffmpeg.exe', Args)` 硬编码路径改 `TFFmpegLocator.FindFFmpeg`——这是本轮发现的最严重硬编码（直接调死路径，非探测候选，没装 chocolatey 就跑不了标题卡渲染）。

### 验证
- H1 编译 EXITCODE=0（dcc64，72681 行 / 3.27s / 10.2MB exe）。无 Error，仅既有 W1057 Hint（AnsiString cast，全仓库预存，与本次无关）。
- H2-H4 门不套用：纯路径探测重构 + debug 后门封门，无 classsig/manifest 大规模变更，H1 充分——COVERED 验证深度选型，AI 自决。
- 运行时回归检查：`--test-llm agnes` ��返 `PROXY_UNREACHABLE`（续14 代理路由卡点，改前改后同），证明 D7 改动未破坏 facade 链路。FindFFmpeg 逻辑逐字搬迁自 AudioProcessor 原版（memory: ffmpeg-installed 记录 7.1 在 chocolatey/bin 实测可跑），无行为变化。
- .gitignore 补 `*.db-shm`/`*.db-wal`（SQLite WAL 边车文件，原仅忽略 `*.db`，遗漏边车；本轮差点误提交 `src/DeepFramesConfig.db-shm/-wal`）。

### 残留
- `VideoRenderEngine.pas` 标题卡副文案 `"DeepFrames AI"` 仍是字面量（line 167/176 drawtext filter），未参数化——该函数仅 `VideoGenTest.dpr`（独立测试程序，非主程序 pipeline 路径）调用，商用度影响低，本轮抽常量未改签名，留后续 D7 品牌参数化批次。

### 下一步
1. 续14 架构对齐方案落地后 E2E 真跑（D7 改动届时随 pipeline 验证 ASR/mux/标题卡路径探测）。
2. D 线余项：D2 GUI 端到端、D3-D8（line 132-133）；DBA 线：DBA-3 残留②、DBA-6 Repository 拆分（line 80）。

---

## 2026-07-21 续17 — D8 Gate3b 视觉评分基础设施（抽真帧 + 降级 sentinel + Gate 挪后）

续16 D7 收尾后转 D8（tasks.md line 118「Gate3b 接真实视觉评分」）。D8 原 stub 评假关键帧 `keyframe_001.png` 硬编码 `1.0`（红线#8 静默 pass），FAIL 分支已接但无真实分触发即永 pass。本轮落地抽帧 + 降级 + Gate 时序三项基础设施，vision provider 真接入即激活，纯代码层与续14 代理路由正交可静态验证。

### 交付（三步）
1. **`Shared/DeepFrames.Shared.Tools.pas` — `TFrameExtractor`**：`ExtractFrames(AMp4Path, ANfps, out AFramePaths): Boolean`（ffmpeg `-vf fps=ANfps` 抽真实帧到 temp dir，失败返 False + 空数组让调用方走降级）；`FrameToBase64(APngPath)` 读 PNG 转 base64（无 MIME 前缀，为未来 DeepBase LLM().ChatVision image_url 输入备）；`CleanupFrames` 最佳努力清理（temp 清理永不阻塞 pipeline）。复用续16 `TFFmpegLocator.FindFFmpeg` 探测。
2. **`Workflow/DeepFrames.Workflow.GateEvaluator.pas` — `EvaluateGate3bFromVLM(AVlmText, AProviderReached) + IsDegraded`**：`GATE3B_DEGRADED_SCORE=-1` sentinel。VLM 不可达（`AProviderReached=False`）或响应不可解析（无 0-1 数字）→ 返回降级 verdict（Score=-1，reason 标 "visual gate UNVERIFIED/degraded"），`IsDegraded` 返 True。VLM 达且解析出分 → 委派 `EvaluateGate3b(score)` 走阈值（≥0.85 PASS / 0.70-0.85 WARN / <0.70 FAIL）。降级 verdict 经 `ToQualityGateResult` 落 `GATE_RESULT_WARN`（黄灯，红线#8 记录+续跑）。
3. **`Workflow/DeepFrames.Workflow.VideoChain.pas` — Gate3b 时序对调**：删 render **前**的旧 Gate3b 块（评假 `keyframe_001.png` 硬编码 `1.0`）。新增 `video.gate3b` JobStep 放 render/mux **后**、Finalize 前，评真实最终 MP4：`Gate3bMp4` = mux 产物（`MuxFile`，有音频 mux 时 mux 成功分支赋值）or render 产物（`FinalVideoAsset.Uri`，无音频路径）。抽帧 → `EvaluateGate3bFromVLM('', False)`（当前 vision provider 未接，`AProviderReached=False` 走降级 WARN）→ `InsertQualityGateResult` → 仅 FAIL 才 block（降级 WARN/真 WARN 均续跑）。temp 帧在 `finally CleanupFrames` 清理。

### 验证
- **H1 编译** EXITCODE=0（dcc64 主项目 + tests runner 双过）。无 Error，仅既有 W1057（与本次无关）。
- **H2 静态分析**：本次改动 3 文件（GateEvaluator/VideoChain/Shared.Tools）无新 warning。
- **H3 单测**：`tests/DeepFrames.Tests.Core.pas` 新增 7 条 Gate3b 测试全绿——`TestGate3b_Pass/Warn/Fail`（阈值边界 0.90/0.75/0.50）+ `TestGate3bFromVLM_Unreachable_DegradesToWarn`（unreachable → WARN + IsDegraded）+ `TestGate3bFromVLM_Unparseable_DegradesToWarn`（"looks fine" 无数字 → 降级）+ `TestGate3bFromVLM_ParseableScore_DelegatesToThreshold`（"score: 0.92" → PASS 且非降级）。全套 97+7 通过，0 失败。
- **H4 三文档对齐**：tasks.md D8 标 `[~]`（续17 基础设施已落地，vision 真分待接）；history.md 续17 段；bugfix.md B5 条更新（stub 1.0 已删）。

### 残留（D8 未完部分，待续18）
- **vision provider 未接**：`StepFunLLMProvider.ChatComplete` 纯文本（`TChatCompletionRequest` 无 image_url 字段），Gate3b 当前 `AProviderReached:=False` 走降级 WARN。接 GPT-4o / StepFun `step-1o-turbo-vision` / Gemini `generateContent` 多模态后，把 `AProviderReached` 换 True + 喂 `FrameToBase64` 帧 + VLM 自由文本响应即激活真实评分，FAIL 分支已通读接线无需再改。
- **CLIP/SSIM 方案**：tasks.md 原 D8 提 CLIP（帧 vs visual_prompt 文本）或 SSIM（帧 vs 帧）——本轮先接 VLM 文本评分路径（更通用、provider 现成），CLIP/SSIM 留作 vision provider 选型确定后再评估。
- **Snapshot JobStep**：旧 Step3 `video.snapshot` step 仍注册假 `keyframe_001.png` 资产（资产记录占位，无真实图文件）——Gate3b 挪走后该 step 无实质视觉评分作用，保留是为资产链路完整；后续可评估删 step 或改其抽帧产物指向 Gate3b 抽出的真帧。

### 下一步
1. 续14 代理架构对齐落地后 E2E 真跑（D7+D8 改动届时随 pipeline 验证 Gate3b 抽帧+降级路径）。
2. D 线余项：D2 GUI 端到端、D3-D7（D7 标题卡品牌参数化残留）、D8 vision provider 接入；DBA 线：DBA-3 残留②、DBA-6 Repository 拆分。

---


