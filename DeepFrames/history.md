# DeepFrames Development History

## 2026-06-04 — Provider 抽象层 + Workflow 重构

提交: 3 个新目录 + 5 个新文件 + 5 个 workflow 重构

### 完成范围

- **Provider 类型系统** — `DeepFrames.Provider.Types.pas`：`TTokenUsage`, `TProviderRunMetrics`, `TTtsSynthesisResult`, `TAsrWordTimestamp`, `TChatCompletionRequest/Result`
- **Provider 接口** — `DeepFrames.Provider.Intf.pas`：`IDeepFramesLLMProvider`, `IDeepFramesTTSProvider`, `IDeepFramesASRProvider`
- **Provider Registry** — `DeepFrames.Provider.Registry.pas`：单例注册表，默认 fake provider，支持运行时切换
- **Fake Provider** — `DeepFrames.Provider.Fake.pas`：原 workflow 内联 fake 函数抽取为类实现，保留为回归测试夹具
- **StepFun Skeleton** — `DeepFrames.Provider.StepFun.pas`：LLM stub 可用，TTS/ASR `ENotImplemented`，带完整 TODO 注释
- **VideoCompiler 工具** — `DeepFrames.Workflow.VideoCompiler.pas`：`CompileTimeline`, `Lint`, `RenderMetrics`, `EstimateDuration`, `CountScenes`
- **Workflow 重构** — AgentChain/AudioChain/VideoChain/PackageChain 全部移除内联 fake 函数，改用 Provider 调用
- **Domain Service 扩展** — `TProjectService.BuildQualitySnapshotJson` / `BuildSourceTraceJson`
- **UI 命令** — "Switch AI Provider" 命令（fake ↔ stepfun 切换）
- **编译配置** — `DeepFrames.dproj` + `compile_test.bat` 更新

### 架构决策

1. Per-capability 接口（LLM / TTS / ASR 分离），防止误用
2. Fake provider 保留为回归测试夹具（文档要求）
3. Provider Registry 不实现动态路由（文档明确：不在当前设计范围）
4. API Key 由 Provider 实现从 `DeepBase.Security` 加载，不经过接口传递
5. VideoCompiler 是确定性工具类，不是 provider（不属于 AI 调用）

---

## 2026-06-03 — 文档评审修复（第二轮外部评价 + 工程实现前最终校正）

### 第二轮外部评价修复任务

来源：2026-06-03 外部评价与 `docs/review-三专家综合评价报告-expert-review.md` / `docs/review-report-2026-06-02-feasibility.md` 的后续一致性审查。

#### P0 — 开工前必须补齐

- **T1 Gate → 对象状态驱动矩阵** ✅  
  在 `08.quality-质量门控-quality-gate.md` / `12.db-state-数据库与状态机-db-state.md` 中定义 Gate 1/2/3a/3b 的 `pass/warn/fail` 如何驱动业务对象状态变化。

- **T2 accuracy_report 与 Gate 2 QA 独立数据契约** ✅  
  在 `08.quality-质量门控-quality-gate.md` / `12.db-state-数据库与状态机-db-state.md` 中明确 `accuracy_report` 只检查 `script_document` 对 `source_document` 的忠实度，Gate 2 QA 只检查 `shot_document` 对 `script_document` / `accuracy_report` 的生产质量，补充 JSON schema 与失败处理流程。

- **T3 102C 资产清理策略细化** ✅  
  在 `06.dist-内容分发-distribution.md` / `12.db-state-数据库与状态机-db-state.md` 中明确 C1-C4 资产分类，定义清理触发条件、保护白名单、日志与回收语义。

- **T4 TTS 451 音频线闭环处理** ✅  
  在 `05.audio-音频流水线-audio-pipeline.md` / `08.quality-质量门控-quality-gate.md` 中明确 TTS 451 发生在音频线内部，不原地改写 `shot_document`，只生成 `tts_text_variant`，由 Gate 3a 校验语义差异并决定 pass/warn/fail。

#### P1 — 建议补齐，不阻塞首条链路

- **T5 渲染后端许可证决策点** ✅  
  在 `01.arch-系统架构-architecture.md` / `10.dev-roadmap-development-roadmap.md` 中明确 HyperFrames 优先、Remotion 后续；Remotion 商业许可复核 deadline 放在 Phase 5 末 / Phase 7 前。

- **T6 content_type adapter 就绪诊断规格** ✅  
  在 `01.arch-系统架构-architecture.md` 中补充未来 adapter 的 readiness check / readiness report 规格；当前仅对 `longform_zh_article` / `webnovel_zh` 启用内置诊断。

### 工程实现前最终校正

- **F1 Gate / 状态机最终一致性** ✅  
  修正业务对象 `done` 与资产 `ready` 的状态边界，补齐 `skipped`、`cancelled` 恢复、新增 `preprocess` job_type。

- **F2 音频 / API 最终一致性** ✅  
  修正 B站 AAC 采样率为 48kHz，loudnorm 改为双遍流程，TTS 451 全文统一为 `tts_text_variant` + Gate 3a 判定。

- **F3 文档就绪度最终一致性** ✅  
  补 README 历史评审索引、Phase 7 adapter/readiness、H.264/AAC 合规复核、DB 表契约与 UTC 时间策略。

---

## 2026-06-04 — Phase 1-7 桌面骨架实现（fake providers）

提交：`2e92248 feat(DeepFrames): implement Phase 1-6 desktop shell with fake providers`

### 完成范围

**Phase 1: DeepBase 桌面骨架**
- Delphi VCL + DeepBase 桌面程序启动、关闭、窗口状态恢复
- DB1 `DeepFramesConfig.db` 初始化（配置、日志、密钥引用）
- DB2 PostgreSQL `DeepFramesData` 连接与 migration
- RootPath、输出目录、worker 目录、日志目录固化
- 主窗体、设置页、任务面板、日志面板

**Phase 2: 文档链与业务库**
- `deepframes_project`、`deepframes_content_unit`、document 表、asset 表、job 表落地
- `source_document -> script_document -> accuracy_report -> variant_document -> shot_document` 版本链
- Repository 和 Application Service 层
- UI 可查看文档版本、质量标记和派生关系

**Phase 3: Agent 生产链**
- prompt registry、model binding、prompt run 记录
- Fake provider 固化结构
- Splitter、Worker、Assembler、QA 通过同一 LLM service 调用
- Style Keeper 使用确定性规则引擎
- QA 输出 Gate 2 质量门控结果
- `accuracy_report` 由上游 `build_script` 阶段产出

**Phase 4: 音频生产线**
- TTS shot 级合成 (fake)、checkpoint、资产登记
- ASR 逐字时间戳 (fake)
- WAV/PCM 中间链路、FFmpeg 拼接、响度标准化 (fake)
- `audio_manifest` 生成

**Phase 5: B站视频生产线**
- 编译后端无关的 `video_ir`
- 平台规格落地 B站：1920x1080、30fps、H.264、AAC
- HyperFrames worker (fake)：lint、snapshot、preview、render
- Gate 3b 校验

**Phase 6: 候选包与导出**
- `candidate_package` schema
- 音频候选包和 B站视频候选包
- 102C 资产策略
- 导出目录独立

**Phase 7: 扩展能力**
- BGM 库、BGM 轨道、BGM 关联
- Content type adapter 注册与 readiness report
- Extension chain workflow

### 实现文件清单

| 文件 | 说明 |
|------|------|
| `src/App/DeepFrames.App.Bootstrap.pas` | 启动引导、DB1/DB2 初始化 |
| `src/App/DeepFrames.App.Services.pas` | Application Service 层 |
| `src/App/DeepFrames.App.Constants.pas` | UI 命令常量 |
| `src/UI/DeepFrames.UI.MainForm.pas` | 主窗体（DeepShell）、所有 Phase 命令 |
| `src/Domain/DeepFrames.Domain.Types.pas` | 全部业务类型定义 |
| `src/Domain/DeepFrames.Domain.Project.pas` | 项目/文档领域服务 |
| `src/Shared/DeepFrames.Shared.Consts.pas` | 全局常量、状态/角色/门控定义 |
| `src/Persistence/DeepFrames.Persistence.Connection.pas` | DB2 连接池 |
| `src/Persistence/DeepFrames.Persistence.Repository.pas` | 全部 Repository 方法 |
| `src/Persistence/DeepFrames.Persistence.Migrations.pas` | DB2 Migration 执行器 |
| `src/Workflow/DeepFrames.Workflow.Preprocess.pas` | Phase 1 预处理工作流 |
| `src/Workflow/DeepFrames.Workflow.DocumentChain.pas` | Phase 2 文档链工作流 |
| `src/Workflow/DeepFrames.Workflow.AgentChain.pas` | Phase 3 Agent 链工作流 |
| `src/Workflow/DeepFrames.Workflow.AudioChain.pas` | Phase 4 音频链工作流 |
| `src/Workflow/DeepFrames.Workflow.VideoChain.pas` | Phase 5 视频链工作流 |
| `src/Workflow/DeepFrames.Workflow.PackageChain.pas` | Phase 6 候选包工作流 |
| `src/Workflow/DeepFrames.Workflow.ExtensionChain.pas` | Phase 7 扩展链工作流 |
| `db/postgres/001-006_*.up.pg.sql` | 6 个 PostgreSQL migration 文件 |