# DeepFrames 工程交接文档

本文面向即将接手实现的开发人员，用于在不重新通读全部评审材料的前提下，快速理解 DeepFrames 当前规格状态、第一阶段开发边界、启动顺序、验收口径和易踩坑。

## 1. 当前交付状态

DeepFrames 当前处于 **文档规格已收敛、可以进入工程实现** 的状态。

已完成的规格收敛包括：

- DB1 / DB2 / DB3 边界已明确：DB1 是 DeepBase SQLite ConfigDB，DB2 / DB3 是 PostgreSQL。
- DeepFrames 产品边界已明确：负责生产音频 / 视频候选包，不负责发布、运营、排期、账号管理或发布后数据复盘。
- 第一条完整链路已明确：已写好的中文文章 / 网文 → 音频候选包 + B站视频候选包。
- Delphi VCL + DeepBase 是当前唯一正式主程序形态；Node / Chromium / HyperFrames / Remotion / FFmpeg 只作为外部 worker 或工具进程。
- 状态机、质量门控、资产保留、Worker 协议、Prompt 结构化输出、成本用量记录均已有正式规格。
- 三专家评审和后续外部一致性审查发现的阻塞问题已吸收到正式规格中。

历史评审材料只用于追溯设计来源；如果历史材料与正式规格冲突，以 `docs/README.md` 中列出的正式规格为准。

## 2. 开发必读顺序

开发人员建议按以下顺序阅读，而不是从全部文档随机开始：

1. `docs/README.md` — 文档索引、真相来源、历史材料边界。
2. `docs/00.quickstart-快速上手-quickstart.md` — 从用户操作视角理解一条生产链。
3. `docs/01.arch-系统架构-architecture.md` — 系统边界、战略基线、核心流水线、DeepBase 集成边界。
4. `docs/09.engineer-工程化基础-engineering.md` — 项目结构、数据库分层、DeepBase 依赖、Worker、测试和可开发范围。
5. `docs/12.db-state-数据库与状态机-db-state.md` — DB2 PostgreSQL 字段契约、状态机、事务边界。
6. `docs/10.dev-roadmap-development-roadmap.md` — Phase 1-7 开发顺序和验收口径。
7. `docs/13.worker-Worker协议-worker-contract.md` — 外部 worker 最小协议 v0。
8. `tasks.md` — 已完成的评审修复任务记录。

进入具体专项时再阅读：

- StepFun / API：`docs/02.api-阶跃星辰集成-step-plan-api.md`
- Agent：`docs/03.agent-Agent工作流-agent-workflow.md`
- 视频：`docs/04.video-视频流水线-video-pipeline.md`
- 音频：`docs/05.audio-音频流水线-audio-pipeline.md`
- 候选包：`docs/06.dist-内容分发-distribution.md`
- 平台：`docs/07.platform-多平台适配-multi-platform.md`
- 质量门控：`docs/08.quality-质量门控-quality-gate.md`
- 端到端样例：`docs/11.e2e-端到端数据流实例.md`
- Prompt 结构化输出：`docs/14.prompt-structured-output-Prompt结构化输出.md`
- 成本与用量：`docs/15.cost-usage-成本与用量-cost-usage.md`

## 3. 第一阶段开发目标

第一阶段只做 **DeepBase 桌面骨架**，不要直接跳到完整音视频生产。

目标：建立 Delphi VCL + DeepBase 原生桌面程序基础，使应用可以启动、配置、连接 DB2、创建基础项目、记录任务和展示日志。

Phase 1 范围以 `docs/10.dev-roadmap-development-roadmap.md` 为准：

- `DeepFrames.dpr` 初始化 DeepBase。
- 引入 `DeepBase.Persistence.Manager.FireDAC`。
- 使用 DeepShell 建立主窗体、设置页、任务面板和日志面板。
- 初始化 DB1 `DeepFramesConfig.db` 与 DB2 PostgreSQL `DeepFramesData`。
- 固化 RootPath、输出目录、worker 目录和日志目录。

Phase 1 验收：

- 程序可启动、关闭、恢复窗口状态。
- DB1 只保存 DeepBase 配置和本地状态。
- DB2 由 PostgreSQL migration 创建，业务表不写入 DB1。
- 日志、配置、密钥入口全部通过 DeepBase。

## 4. 建议工程启动任务拆分

### 4.1 仓库与项目骨架

1. 建立 `src/`、`db/postgres/`、`workers/`、`tests/` 等目录结构。
2. 创建 Delphi VCL 程序入口 `src/DeepFrames.dpr`。
3. 创建启动单元，例如 `DeepFrames.App.Bootstrap`。
4. 创建主窗体 `DeepFrames.UI.MainForm`，继承 DeepShell 体系，而不是从空白 Form 重新造工具壳。

### 4.2 DeepBase 初始化

必须使用文档中的启动模板作为基线：

```delphi
program DeepFrames;

uses
  Vcl.Forms,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  DeepFrames.App.Bootstrap,
  DeepFrames.UI.MainForm in 'UI\DeepFrames.UI.MainForm.pas' {MainForm};

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;

  DeepBase.InitializeOrRaise;
  try
    TDeepFramesBootstrap.RegisterServices;
    Application.CreateForm(TMainForm, MainForm);
    DeepBase.FireReadyCallbacks;
    Application.Run;
  finally
    TDeepFramesBootstrap.Shutdown;
    DeepBase.Finalize;
  end;
end.
```

关键点：最终 `.dpr` 或启动 bootstrap 单元必须引用 `DeepBase.Persistence.Manager.FireDAC`，否则 DB1 FireDAC adapter 不会注册。

### 4.3 DB1 / DB2 初始化

DB1：

- 文件：`{RootPath}/DeepFramesConfig.db`
- 用途：DeepBase Settings、Logs、I18n、FormStates、MRU、Hotkeys、LLM 配置、Secrets 引用。
- 禁止：DeepFrames 业务表、生产任务、资产索引。

DB2：

- PostgreSQL database：`DeepFramesData`
- 用途：项目、文档版本、任务、资产、质量门控、候选包。
- 禁止：API Key 明文、发布账号、运营数据。

DB2 连接参数写入 DB1：

```text
DB2.Type = PostgreSQL
DB2.Host = 127.0.0.1
DB2.Port = 5432
DB2.Database = DeepFramesData
DB2.User = deepframes
DB2.PasswordSecretRef = secret://deepframes/db2
```

### 4.4 最小 DB2 migration

第一版 migration 应优先落地这些表或最小等价骨架：

- `deepframes_project`
- `deepframes_content_unit`
- `deepframes_source_document`
- `deepframes_script_document`
- `deepframes_accuracy_report`
- `deepframes_variant_document`
- `deepframes_shot_document`
- `deepframes_audio_manifest`
- `deepframes_video_ir`
- `deepframes_candidate_package`
- `deepframes_asset`
- `deepframes_job`
- `deepframes_job_step`
- `deepframes_quality_gate_result`
- `deepframes_prompt_template`
- `deepframes_prompt_run`
- `deepframes_model_binding`
- `deepframes_eval_result`
- `deepframes_platform_spec`
- `deepframes_video_job`
- `deepframes_video_step`
- `deepframes_video_asset`

字段契约以 `docs/12.db-state-数据库与状态机-db-state.md` 为权威，`docs/09.engineer-工程化基础-engineering.md` 可作为工程说明补充。

### 4.5 最小 UI

Phase 1 UI 只需要支撑工程验证，不要提前做复杂生产编辑器：

- 主窗体可启动和恢复窗口状态。
- 设置页可配置 RootPath、DB2 连接、工具路径。
- 任务面板能显示 job / step 列表。
- 日志面板能显示 DeepBase 日志和外部 worker 摘要。
- UI 只调用 application service，不直接访问 FireDAC query，不直接写业务表。

### 4.6 最小状态机

必须先实现状态合法性，不要用自由字符串更新状态。

任务状态：

```text
pending -> running -> blocked_review -> running -> done
pending -> running -> failed
pending -> running -> skipped
running -> cancelled
blocked_review -> cancelled
blocked_review -> skipped
```

状态集合：

```text
pending / running / blocked_review / done / skipped / failed / cancelled
```

断点续跑只处理：

```text
pending / failed / 可重试的 blocked_review
```

必须跳过：

```text
done / skipped
```

资产状态单独使用：

```text
temp / ready / failed / deleted
```

不要把业务对象的 `done` 和资产的 `ready` 混用。

### 4.7 最小任务模型

使用两层模型：

1. DeepBase `TJobQueue`：领取、去重、心跳、死任务回收。
2. DeepFrames DB2 表：业务语义、阶段状态、质量门控、资产结果。

二者通过 `job_queue_task_id` 和 `logical_key` 关联，不混用状态字段。

建议第一批 logical key：

```text
preprocess:{project_id}:{content_unit_id}:{source_document_id}:{script_policy_hash}
agent:{project_id}:{content_unit_id}:{variant_id}:{prompt_version}:{model_binding}
audio:{shot_document_id}:{voice_profile_version}:{audio_policy_hash}
video:{shot_document_id}:{platform}:{render_backend}:{template_version}:{audio_manifest_id}
package:{content_unit_id}:{platform}:{candidate_package_profile}
```

## 5. 三个优先 POC

工程实现建议并行准备以下 POC，但不要让 POC 代码污染正式业务层。

### POC 1：DB2 PostgreSQL migration + Repository

目标：验证 Delphi + FireDAC + DeepBase Persistence 能稳定连接 DB2，并创建 / 查询 / 更新最小业务表。

验收：

- 可创建 `deepframes_project`、`deepframes_content_unit`、`deepframes_job`。
- 所有时间字段使用 `TIMESTAMPTZ`，按 UTC 写入，UI 按本地时区显示。
- Repository 使用参数化查询，不拼接 SQL。
- 重复 logical key 不产生重复任务。

### POC 2：StepFun 最小调用

目标：验证 DeepBase 配置 / 密钥 / provider adapter 路径，而不是在业务代码里直接散落 HTTP 调用。

必须验证：

- Step Plan 端点：`https://api.stepfun.com/step_plan/v1`
- 标准端点：`https://api.stepfun.com/v1`
- 两套 Key 不互通。
- Chat / TTS / ASR 使用正确 capability 路由。
- API Key 使用 `DeepBase.Security.SaveSecret/LoadSecret`，不写入 `.env`、JSON、INI、日志或 DB2。

ASR SSE 是最高风险接口，必须单独验证：

- Delta 事件格式。
- 时间戳字段路径。
- Done 事件完成标记。
- 错误事件格式。
- word-level timestamp 累积后统一转换为秒。

### POC 3：Worker 协议 v0

目标：验证主程序可以创建工作目录、写入 request、启动 worker、读取 progress / result，并在 DB2 中更新 step 与 asset。

最小文件契约：

- `request.json`
- `progress.json`
- `result.json`

主程序职责：

1. 创建 `deepframes_job` 和 `deepframes_job_step`。
2. 创建 worker 工作目录。
3. 写入 `request.json` 和已编译输入 manifest。
4. 启动进程。
5. 监控 heartbeat。
6. 读取 `result.json`。
7. 在一个事务内更新 step、登记 asset、记录 metrics。

取消协议：主通道使用 `CTRL-BREAK`，`cancel_file` 只作为辅助信号；强制终止后的 partial asset 不得登记为 `ready`。

## 6. 开发红线

以下事项不要在第一阶段破坏：

1. 不要把业务表写入 DB1 ConfigDB。
2. 不要把 API Key 写入 `.env`、JSON、INI、Registry、日志或 DB2。
3. 不要让 UI Form 直接写业务表；必须通过 application service。
4. 不要让 worker 直接访问 DB1 / DB2 或读取 `shot_document`。
5. 不要绕过 DeepBase 配置、日志、密钥和 JobQueue 体系。
6. 不要把 Node / TypeScript 做成主程序；它们只能作为 worker。
7. 不要原地覆盖文档、manifest 或候选包；返工必须产生新 version。
8. 不要把黄灯当阻塞；黄灯记录并提醒，红灯才进入 `blocked_review`。
9. 不要混淆业务对象状态和资产状态。
10. 不要跳过 `schema_version`；所有 JSON payload 必须版本化。

## 7. 首个可验收里程碑

第一个可交付里程碑建议定义为：

> DeepFrames 桌面程序能启动，完成 DB1 / DB2 初始化，创建项目，导入一段文章为 `source_document`，创建一个 `preprocess` job，并在 UI 中显示任务、状态和日志。

最小验收脚本：

1. 启动 DeepFrames。
2. 设置 RootPath。
3. 设置 DB2 PostgreSQL 连接。
4. 保存配置到 DB1。
5. 执行 DB2 migration。
6. 新建项目。
7. 导入一段 Markdown 文本。
8. 生成 `source_document`。
9. 创建 `preprocess` job / step。
10. UI 任务面板显示状态从 `pending` 到 `running` 到 `done`。
11. 关闭并重启程序，窗口状态、配置、项目和任务仍可恢复。

该里程碑不要求真实调用 StepFun，也不要求生成音频或视频。

## 8. 后续阶段顺序

不要跳过 Phase 2 / Phase 3 直接做媒体线。

推荐顺序：

1. **Phase 1：DeepBase 桌面骨架**  
   启动、DB1/DB2、主窗体、设置、任务、日志。

2. **Phase 2：文档链与业务库**  
   `source_document -> script_document -> accuracy_report -> variant_document -> shot_document`，版本链、Repository、Application Service。

3. **Phase 3：Agent 生产链**  
   先 fake provider 固化 schema、prompt registry、model binding、prompt run、QA gate，再接 StepFun adapter。

4. **Phase 4：音频生产线**  
   TTS shot 级合成、ASR timestamps、WAV/PCM 中间链、loudnorm 双遍、audio manifest。

5. **Phase 5：B站视频生产线**  
   Video IR、HyperFrames worker、snapshot、preview、render、Gate 3b。

6. **Phase 6：候选包与导出**  
   音频候选包、B站视频候选包、manifest、quality snapshot、102C 资产策略。

7. **Phase 7：扩展能力**  
   Remotion、多平台、多比例、content_type adapter readiness、BGM、ArtifactOS 深度联动、商业化和许可复核。

## 9. 重点风险清单

### 9.1 StepFun 双 Base URL

- Chat / TTS / Image：`https://api.stepfun.com/step_plan/v1`
- ASR：`https://api.stepfun.com/v1`

ASR SSE 不走 `/step_plan/v1`。两套 Key 不互通。

### 9.2 TTS 参数限制

- `stepaudio-2.5-tts` 不支持 `voice_label`。
- 只使用 `voice` + `instruction`。
- `instruction` 限 200 字符。
- TTS 默认输出 24kHz，混音前统一重采样到 48kHz。
- 括号 `()` 可能被解释为内联控制指令，原文括号需转义或移除。

### 9.3 TTS 451

TTS 451 发生在音频线内部，不能原地改写 `shot_document`。处理方式是生成 `tts_text_variant`，由 Gate 3a 做语义相似度判定：

- `>= 0.95`：pass
- `0.85 - 0.95`：warn
- `< 0.85`：fail，进入 `blocked_review`

### 9.4 loudnorm

不能只做单遍 loudnorm。必须采用两遍流程：第一遍测量，第二遍带 `measured_*` 参数线性调整；Gate 3a 用独立测量结果验证 -16 LUFS ± 1。

### 9.5 视频正式成片依赖音频 manifest

视频线可以先做静默预览、图片生成和模板校验，但 `final-with-audio` 必须绑定已通过 Gate 3a 的 audio manifest。

### 9.6 102C 资产清理

候选包引用的资产必须受保护。清理策略必须遵守：

- `retention_class`
- `cleanup_eligible_at`
- `protected_until`
- 候选包 `source_trace` 引用检测
- 级联保护

失败或 partial asset 不得登记为 `ready`。

### 9.7 许可证与合规

- HyperFrames 是 Phase 5 默认后端，Phase 5 结束前复核依赖许可证。
- Remotion 是后续扩展后端；引入前必须复核商业许可。
- H.264 / AAC 编解码器专利与分发合规在 Phase 5 结束、Phase 7 商业化前复核。
- 自用版可先按本机 FFmpeg 能力生产候选包，但商业化必须明确授权边界或替代编码方案。

## 10. 工程验证命令

工程建立后，应固化统一验证命令。文档建议为：

```powershell
cmd /c compile_test.bat
powershell -ExecutionPolicy Bypass -File .\Scripts\run_tests.ps1 -Type Unit -CI -Platform Win64
```

如果改动 DeepBase 适配层，还需要在 DeepBase 仓库运行对应模块回归。DeepFrames 不应在下游私改 DeepBase Core、LLM 或 SQLite/PostgreSQL 适配层。

## 11. 开发人员每日参考清单

实现过程中每天开始前建议快速确认：

- 当前改动是否仍符合 `docs/01.arch-系统架构-architecture.md` 的产品边界？
- 是否误把业务数据写进 DB1？
- 是否绕过 DeepBase 配置 / 密钥 / 日志 / JobQueue？
- 是否保持 UI 与业务核心分离？
- 是否给新增 JSON payload 加了 `schema_version`？
- 是否保证状态流转合法？
- 是否保证文档 / manifest / asset 返工不覆盖旧版本？
- 是否把 worker 限制在文件协议和工作目录内？
- 是否有可重复的 logical key？
- 是否能通过最小启动 / 迁移 / 创建项目 / 导入文章验收脚本？

## 12. 结论

DeepFrames 现在可以交给开发人员执行开发。建议先完成 Phase 1 的桌面骨架与 DB2 基础，再逐步推进文档链、Agent、音频、视频和候选包。第一阶段的成功标准不是“生成视频”，而是建立稳定、可迁移、可恢复、可追踪的工程底座。
