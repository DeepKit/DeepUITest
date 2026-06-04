# DeepFrames Tasks

## 当前状态

Phase 1-7 桌面骨架已完成（fake providers）。所有文档评审修复任务已归档至 [history.md](history.md)。

**2026-06-04 更新**: Provider 抽象层完成，StepFun LLM 真实 HTTP 调用就绪。三个 workflow（DocumentChain、AgentChain、AudioChain）全部通过 Provider 调用 LLM/TTS/ASR。

**当前瓶颈**: 无 Delphi 编译环境验证语法正确性。Phase 2/3 剩余任务集中在 JSON Schema 校验、Gate 门控逻辑、Style Keeper 规则引擎。

下阶段核心任务（按优先级）：
1. **P2.3** JSON Schema 校验 — LLM 输出质量保障的基础设施
2. **P2.5+P2.8** Gate 1/2 门控 — pass/warn/fail 分流 + blocked_review
3. **P3.6** Style Keeper 确定性规则引擎
4. **P2.9** 失败重试与断点续跑

---

## 已完成（2026-06-04）

- [x] **Provider Types** — `src/Provider/DeepFrames.Provider.Types.pas`
- [x] **Provider Interfaces** — `src/Provider/DeepFrames.Provider.Intf.pas`（LLM / TTS / ASR 分离）
- [x] **Provider Registry** — `src/Provider/DeepFrames.Provider.Registry.pas`（fake 默认，可切换 stepfun）
- [x] **Fake Provider** — `src/Provider/DeepFrames.Provider.Fake.pas`（回归测试夹具）
- [x] **StepFun LLM (real HTTP)** — `src/Provider/DeepFrames.Provider.StepFun.pas`（真实 HTTP POST + OpenAI 兼容解析 + 重试 + Key 缺失时 stub 降级）
- [x] **StepFun TTS/ASR Skeleton** — 同上（`ENotImplemented`，Phase 4 接入）
- [x] **VideoCompiler Utility** — `src/Workflow/DeepFrames.Workflow.VideoCompiler.pas`
- [x] **DocumentChain → Provider** — source_document 注入 prompt，LLM 调用 build_script/accuracy_check/build_variant/build_shot，失败时 stub 降级
- [x] **AgentChain → Provider** — 每个 agent role 有专用 SystemPrompt + UserPrompt
- [x] **AudioChain → Provider** — TTS/ASR provider 调用
- [x] **VideoChain → VideoCompiler** — 确定性工具类
- [x] **PackageChain → Domain Service** — BuildQualitySnapshotJson / BuildSourceTraceJson
- [x] **Repository.FindSourceDocument** — 按 ID 查找 + payload_json 解析
- [x] **UI** — "Switch AI Provider" 命令 + 启动时显示 provider 状态
- [x] **Build Config** — `dproj` + `compile_test.bat` 更新

## POC 验证（优先，不阻塞但建议先做）

> 来源：`docs/ENGINEERING_HANDOFF.md` §5

### POC 1：DB2 PostgreSQL migration + Repository 验证

- [ ] 验证 Delphi + FireDAC + DeepBase Persistence 稳定连接 DB2
- [ ] 确认所有时间字段使用 `TIMESTAMPTZ`，按 UTC 写入，UI 按本地时区显示
- [ ] 确认 Repository 使用参数化查询，不拼接 SQL
- [ ] 确认重复 logical key 不产生重复任务

### POC 2：StepFun 最小调用验证

- [ ] 验证 Step Plan 端点 `https://api.stepfun.com/step_plan/v1` 连通性
- [ ] 验证标准端点 `https://api.stepfun.com/v1` 连通性
- [ ] 确认两套 Key 不互通
- [ ] 验证 Chat / TTS / ASR 使用正确 capability 路由
- [ ] 验证 API Key 通过 `DeepBase.Security.SaveSecret/LoadSecret` 存取，不写入 `.env`、JSON、INI、日志或 DB2
- [ ] ASR SSE 单独验证：Delta 事件格式、时间戳字段路径、Done 事件完成标记、错误事件格式、word-level timestamp 累积后统一转换为秒

### POC 3：Worker 协议 v0 验证

- [ ] 验证主程序创建 worker 工作目录 → 写入 `request.json` → 启动 worker → 读取 `progress.json` / `result.json` → 更新 DB2 step 与 asset
- [ ] 验证最小文件契约：`request.json` / `progress.json` / `result.json`
- [ ] 验证取消协议：`CTRL-BREAK` 主通道 + `cancel_file` 辅助信号
- [ ] 确认强制终止后的 partial asset 不登记为 `ready`

---

## Phase 2：文档链真实实现

> 当前状态：DocumentChain workflow 已通过 Provider 调用真实 LLM（StepFun Key 可用时），Key 不可用时 stub 降级。
> 剩余：JSON Schema 校验、Gate 1/2 门控逻辑（pass/warn/fail 分流）、失败重试与断点续跑

- [x] **P2.1** 接入 StepFun Chat API，替换 stub script_document 生成为真实 LLM 调用
- [x] **P2.2** 实现 prompt template 加载与渲染（注入 source_document 内容）
- [x] **P2.3** 实现 schema 校验：LLM 输出必须通过 `output_schema_json` 定义的 JSON Schema
- [x] **P2.4** 实现 accuracy_report 真实计算（coverage_score / distortion_score）
- [x] **P2.5** 实现 Gate 1 质量门控：`TGateEvaluator.EvaluateGate1` — coverage >= 0.95 pass, >= 0.85 warn, < 0.85 fail → blocked_review
- [x] **P2.6** 实现 build_variant 真实 LLM 调用
- [x] **P2.7** 实现 build_shot 真实 LLM 调用
- [x] **P2.8** 实现 Gate 2 质量门控：`TGateEvaluator.EvaluateGate2` — >= 0.85 pass, >= 0.70 warn, < 0.70 fail → blocked_review
- [ ] **P2.9** 实现失败重试与断点续跑（Provider 层已有 HTTP 重试，workflow 层无断点续跑）

## Phase 3：Agent 生产链真实实现

> 当前状态：AgentChain workflow 已通过 Provider 调用真实 LLM，每个 agent role 有专用 SystemPrompt + UserPrompt。StepFun provider 已接入。
> 剩余：Style Keeper 确定性规则引擎、prompt version 可复现性

- [x] **P3.1** 实现 StepFun provider adapter（`TStepFunLLMProvider` 已完成，真实 HTTP + stub 降级）
- [x] **P3.2** 实现 Splitter agent 真实调用（source_document → 拆分计划）
- [x] **P3.3** 实现 Worker agent 真实调用（逐段生成脚本内容）
- [x] **P3.4** 实现 Assembler agent 真实调用（合并为完整 script_document）
- [x] **P3.5** 实现 QA agent 真实调用（Gate 2 质量门控结果）
- [ ] **P3.6** 实现 Style Keeper 确定性规则引擎（不调用 LLM）— 当前 fake provider 输出 stub 数据，无真实规则引擎
- [ ] **P3.7** 实现 prompt version 可复现性（同一输入 + 同一 prompt version + 同一 model binding = 可复现调用记录）— 当前记录 prompt_run 但无 version 校验
- [x] **P3.8** 实现 prompt run 记录（token 用量、latency、retry、error）— 每次调用自动记录

## Phase 4：音频生产线真实实现

> 当前状态：fake TTS/ASR
> 目标：真实 TTS 合成 + ASR 时间戳 + 音频拼接 + 响度标准化

- [ ] **P4.1** 接入 StepFun TTS API（stepaudio-2.5-tts）
- [ ] **P4.2** 实现 TTS 参数处理：voice + instruction（限 200 字符），不传 voice_label
- [ ] **P4.3** 实现括号转义处理（TTS 括号可能被解释为内联控制指令）
- [ ] **P4.4** 实现 TTS 24kHz → 48kHz 重采样
- [ ] **P4.5** 实现 TTS 451 处理：生成 `tts_text_variant`，Gate 3a 语义相似度判定
- [ ] **P4.6** 接入 StepFun ASR API（SSE 端点，走 `/v1` 不走 `/step_plan/v1`）
- [ ] **P4.7** 实现 ASR word-level timestamp 解析（local/global 双坐标）
- [ ] **P4.8** 实现 WAV/PCM 中间链路 + FFmpeg 拼接
- [x] **P4.9** 实现 loudnorm 双遍流程：第一遍测量，第二遍线性调整（stub 数据，真实 FFmpeg 待 POC 3）
- [x] **P4.10** 实现 Gate 3a 校验：`TGateEvaluator.EvaluateGate3a` — LUFS delta ±1/±2, concat delta 200ms/500ms
- [ ] **P4.11** 实现断点续跑（每个 shot 音频可独立恢复）

## Phase 5：B站视频生产线真实实现

> 当前状态：fake HyperFrames
> 目标：真实 HyperFrames worker 渲染

- [ ] **P5.1** 确认 HyperFrames 依赖许可证（Phase 5 结束前）
- [ ] **P5.2** 实现 video_ir 编译（shot_document + audio_manifest → video_ir JSON）
- [ ] **P5.3** 实现 HyperFrames worker 集成（lint → snapshot → preview → render）
- [ ] **P5.4** 实现字幕生成与安全区计算
- [ ] **P5.5** 实现简单表意背景图或画面素材生成
- [x] **P5.6** 实现 Gate 3b 校验：`TGateEvaluator.EvaluateGate3b` — >= 0.85 pass, >= 0.70 warn, < 0.70 fail
- [ ] **P5.7** 实现 `final-with-audio` 模式绑定已通过 Gate 3a 的 audio manifest
- [ ] **P5.8** 验证 15 分钟以内视频完整生成链路

## Phase 6：候选包与导出真实实现

> 当前状态：fake package assembly
> 目标：真实候选包导出，下游系统可消费

- [ ] **P6.1** 实现音频候选包导出（manifest + 封面 + metadata）
- [ ] **P6.2** 实现 B站视频候选包导出（视频 + 封面 + 标题 + 简介 + 标签 + manifest）
- [ ] **P6.3** 实现 102C 资产策略：保留最终包和关键快照，中间大文件按策略清理
- [ ] **P6.4** 实现候选包 source_trace 完整性（回溯到 source、prompt、model、worker、gate、asset 版本）
- [ ] **P6.5** 验证下游系统无需理解内部任务表即可读取候选包 manifest

## Phase 7：扩展能力（远期）

> 当前状态：fake BGM / adapter / readiness
> 目标：真实扩展，不反向破坏核心契约

- [ ] **P7.1** Remotion 商业许可复核（引入前必须）
- [ ] **P7.2** Remotion worker 实现
- [ ] **P7.3** 更多平台规格（抖音、快手、小红书、微信视频号、YouTube、喜马拉雅）
- [ ] **P7.4** 多比例视频支持
- [ ] **P7.5** content_type adapter 扩展与 readiness check / readiness report
- [ ] **P7.6** BGM 与音乐库真实实现
- [ ] **P7.7** ArtifactOS 深度联动
- [ ] **P7.8** H.264 / AAC 编解码器专利和平台发布合规复核
- [ ] **P7.9** 商业化、授权、销售包装

---

## 技术债务 / 待改进

- [ ] 编译验证：确保所有 `.pas` 文件通过 Delphi 编译（当前为手写骨架，需在 Delphi IDE 中编译验证）
- [ ] 单元测试：为 Repository、Workflow、Domain 层添加测试
- [ ] 集成测试：端到端 fake provider 链路验证
- [ ] 错误处理增强：Workflow 中的异常恢复路径
- [ ] 日志完善：关键路径的日志插桩

---

## 开发红线（每次改动前确认）

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