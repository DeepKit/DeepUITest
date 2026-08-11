# DeepFrames Bugfix Log

## 2026-07-08 — 5 专家评估 P0 批量修复（6 项阻断 bug）

> 来源：2026-07-08 五专家商用就绪度评估（综合 3.8/10）。以下 6 项为 P0 阻断 bug，本轮全部修复。其余 P0（CookieCloud 解密协议、CheckSourceMetadata 接入、Resume 接入、预算护栏、H.264 专利、CI、key 清史轮换）见 tasks.md 待办。

### B1. ffprobe/ffmpeg 可执行文件混用（搬运全链阻断）
**Severity**: P0（最严重）
**现象**: `AudioProcessor.GetDuration`(`:552`)/`GetFileInfo`(`:578`) 用 ffprobe 参数（`-show_entries`/`-of default`）却调 ffmpeg 可执行。后果链：GetDuration 永远返回 0 → `VadSplit`/`VadScan` 100% 失败 → 搬运作业全部失败在 ASR 之前；`audio.merge` 时长校验失真。
**原因**: `RunFFmpeg` 固定调 `FindFFmpeg`，但探测类方法需要 ffprobe。
**修复**: `RunFFmpeg` 增可选 `AExe` 参数（默认 ffmpeg，向后兼容）；新增 `FindFFprobe`（与 FindFFmpeg 同路径策略，文件名 ffprobe）；GetDuration/GetFileInfo 传 `FindFFprobe`。
**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas`
**验证**: DeepFrames.dpr 编译 0 Error。

### B2. 通知 ChannelWebhook 返回空串（通知 0% 可用 + 无限重试）
**Severity**: P0
**现象**: `NotificationChain.ChannelWebhook`(`:88`) 返回空串占位，`ProcessNotifications` 取到空 URL → Deliver 失败 → `Fail(Requeue=True)` 无限重试堆积 DLQ。通知功能完全不可用。
**原因**: 占位未接配置。
**修复**: `ChannelWebhook` 改为按 channel 读 `DeepBase.Config.GetConfig`：wecom→`CONFIG_NOTIFY_WECOM_WEBHOOK`、dingtalk→`CONFIG_NOTIFY_DINGTALK_WEBHOOK`、http→`CONFIG_NOTIFY_HTTP_WEBHOOK`（常量已在 `Shared.Consts:284` 定义）。未配置 channel 返回空串，Deliver 返回 False 带原因，ProcessNotifications 走重试而非静默丢弃。
**文件**: `src/Workflow/DeepFrames.Workflow.NotificationChain.pas`

### B3. 迁移 011 重复列 + 008/009 删除致 schema 缺口（迁移无法执行 / 核心流水线 INSERT 违反 CHECK）
**Severity**: P0
**现象 a**: `011_db3_integration:19-22` 重复定义 `created_at`/`updated_at`，PostgreSQL 报错，**整个迁移无法执行**。
**现象 b**: 008（widen producer_version/codec + 扩 agent_role）与 009（gate4 约束）在 commit `8cf8ccb` 被删除但内容未合并回 002-004。新环境部署后：AudioChain 写 `agent_role='tts'/'asr'`、PackageChain 写 `gate='gate4'` **违反 CHECK 约束，核心流水线 INSERT 失败**；`producer_version` 仍 VARCHAR(16) 截断 'stepaudio-2.5-tts'。
**修复**: 011 删除重复的 created_at/updated_at 行；新建 `013_restore_008_009_schema.up.pg.sql` 幂等重应用 008+009 全部 4 项变更（ALTER TYPE 扩宽 + DROP IF EXISTS + ADD 约束）。已部署环境全为 no-op，新环境补齐缺口。
**文件**: `db/postgres/011_db3_integration.up.pg.sql`, `db/postgres/013_restore_008_009_schema.up.pg.sql`（新增）

### B4. StepFun TTS 双重释放（悬垂指针 → AV/堆损坏）
**Severity**: P0
**现象**: `StepFun.pas:540,546` 在 451/4xx 分支手动 `ResponseStream.Free` 后 `Exit`，触发 `:591` finally 再次 Free。生产高频触发，悬垂指针 → AV/堆损坏。
**修复**: 删除 :540/:546 两处手动 Free，统一交给 :591 finally 块释放。
**文件**: `src/Provider/DeepFrames.Provider.StepFun.pas`

### B5. VideoChain mux 失败被吞仍标 DONE + Gate3b 硬编码 1.0 无分支
**Severity**: P0
**现象 a**: `VideoChain.pas:343` mux 非零退出只写 `ErrorMessage` 到**旧的 render VideoStep**（mux VideoStep 在 :362 才创建），随后 :374 仍标 DONE、:393 Job 标 DONE。**产出无音频/劣质的"成功"视频并可能发布**。
**现象 b**: Gate3b 传硬编码 `1.0`，无失败分支——未来真实评估器返回 fail 会被静默忽略。
**修复 a**: mux VideoStep 提前到 mux 执行之前创建；mux 非零退出时 `UpdateVideoStepStatus(FAILED)` + `UpdateJobStepStatus(FAILED)` + `UpdateJobStatus(FAILED)` + raise，硬中断；删除原 :387 重复 CreateVideoStep（避免覆盖 ErrorMessage + 重复 Insert）。
**修复 b**: Gate3b 后加 `if GateResult.GateResult = GATE_RESULT_FAIL then` 分支：Job 标 `STATUS_BLOCKED_REVIEW` 并 Exit（当前评估器恒 pass，接线保证未来真实评估器不可被忽略）。
**续17 更新**: Gate3b 已从 render **前**挪到 render/mux **后**（评真实最终 MP4，非假 keyframe），删掉硬编码 `1.0` 的旧块，改调 `EvaluateGate3bFromVLM('', AProviderReached)` + `TFrameExtractor.ExtractFrames` 抽真帧。当前 vision provider 未接 → `AProviderReached=False` 走降级 WARN（Score=-1 sentinel，`GATE_RESULT_WARN`，红线#8 记录+续跑），不再静默硬编码 pass。vision provider 接入后换 True+真响应激活真分，FAIL 分支已通读接线。详见 history 续17。
**文件**: `src/Workflow/DeepFrames.Workflow.VideoChain.pas`（+ `GateEvaluator.pas` 续17、`Shared.Tools.pas` 续17）

### B6. .gitignore 被删 + 密钥进 git 历史（密钥泄露）
**Severity**: P0（合规硬伤）
**现象**: `.gitignore` 在 commit `8cf8ccb` 被删除；`agnes_key.txt`/`stepfun_key.txt` 明文提交进 git 历史（`8cf8ccb`/`e176c31`），当前仍被 git 跟踪。密钥已泄露，不可挽回。
**修复**: 重建 `.gitignore`（覆盖 `*_key.txt`/`*.db`/`*.partial`/`cookies.txt`/`output/`/`bin/`/`__history__/`/`*.dcu`/`*.dproj.local` 等）；`git rm --cached` 密钥文件 + 全部 .db / output/ / bin/ / __history__ / autofix-output（工作区文件保留，程序仍可读）。
**遗留（需用户手动执行）**: ① 轮换 Agnes/StepFun API key（泄露不可清史挽回）；② git 历史清史（`git filter-repo` 或 BFG 删除历史中的密钥文件后 force push）。已记入会话记忆 [[keys-leaked-in-git-history]]。
**文件**: `.gitignore`（新建）, git index（移除跟踪）

---

## 2026-07-08 — P0 工程化批量交付（7 项：P0-A/B/C/E/H + D 复核 + I 定档）

> 第二阶段 P0 清单中除 P0-F（真实集成测试+CI）、P0-G（预算护栏）外的全部项。本轮交付均编译 0 Error + 测试 194 passed（+44）。每项附单元/契约测试，不依赖真实 DB/provider。

### B7. P0-A Repository 事务边界缺失（崩溃致状态不一致）
**Severity**: P0
**现象**: `TDeepFramesRepository` 无任何事务 API；DocumentChain.RunChain 的 InsertJob+InsertJobStep+UpdateJobStepStatus 三步各自独立提交，若 InsertJobStep 失败会留下"有 Job 无 Step"的孤儿记录，状态永久不一致。
**修复**: Repository 新增 `BeginTransaction`/`CommitTransaction`/`RollbackTransaction`/`InTransaction`（委托 `FConnection`，靠 FireDAC `InTransaction` 守卫使嵌套调用为 no-op）；DocumentChain 用事务包裹 Job+首 Step 创建，事务在 provider 调用前 Commit（不持事务跨 LLM IO）；except 路径 Rollback。Commit/Rollback 在无事务时是幂等 no-op，保证异常路径不崩。
**测试**: `TestRepo_TxSafeWhenNoTxn`（无连接时 InTransaction=False + no-op Commit/Rollback 不崩）。
**文件**: `src/Persistence/DeepFrames.Persistence.Repository.pas`, `src/Workflow/DeepFrames.Workflow.DocumentChain.pas`, `tests/DeepFrames.Tests.Core.pas`

### B8. P0-B Heartbeat 未接入（长任务被回收重复执行 + 重复扣费）
**Severity**: P0
**现象**: `TWorkerProtocol` 宿主端 `WaitForWorker` 监控 `progress.json` 的 mtime 做 heartbeat_timeout 判定，但**只有读取端 `ReadProgress`，没有写入端**——worker 子进程从不写 progress.json，整个心跳机制空转：超时检测因文件永不存在而失效，长任务可能被误判超时杀掉重跑，重复扣费。
**修复**: 新增 `WriteProgress(AWorkDir, AProgress)`——worker 端把心跳写进 `progress.json`，用 `tmp + rename` 原子写（避免宿主读到半截 JSON）。宿主 `ReadProgress` 对 rename 写入安全（rename 原子）。
**测试**: `TestWorker_WriteProgressRoundtrip`（WriteProgress→ReadProgress 完整恢复 task_id/status/progress_percent/message）。
**文件**: `src/Workflow/DeepFrames.Workflow.WorkerProtocol.pas`, `tests/DeepFrames.Tests.Core.pas`

### B9. P0-C Resume 续跑缺失 + 静默假成功（failed 作业永久卡死）
**Severity**: P0
**现象**: DocumentChain.RunChain 的幂等逻辑：`if FindJobByLogicalKey(LogicalKey, ExistingJob) then Exit(ExistingJob)`——命中已存在 job **直接返回**，不检查状态。后果：job 创建后 Step3 中断崩溃，重启 RunChain 因 logical key 已存在而直接返回那个未完成 job，**静默假成功**，作业永久卡在中间态。
**修复**: 幂等改状态感知——命中已存在 job 时：终态（done/failed/cancelled/skipped）或 blocked_review→退出返回（真幂等）；pending/running（崩溃中途）→复用 `ExistingJob.JobId` 续跑（step insert 幂等 `ON CONFLICT step_key DO NOTHING`，JobId 复用避免 step 关联错乱）。新增 `IsTerminalStatus`/`IsResumableStatus` 可测函数。
**测试**: `TestResume_TerminalStatuses` + `TestResume_ResumableStatuses`（7 终态判定 + 4 续跑判定）。
**遗留**: step 级"跳过已 done step + 复用已生成产物"是更深重构，本轮实现状态感知幂等这一核心断点修复；step 级跳过留作后续增强。
**文件**: `src/Workflow/DeepFrames.Workflow.DocumentChain.pas`, `src/Shared/DeepFrames.Shared.Consts.pas`, `tests/DeepFrames.Tests.Core.pas`

### B10. P0-E CheckSourceMetadata 未接入生产链（搬运无授权审计硬门）
**Severity**: P0
**现象**: `GateEvaluator.CheckSourceMetadata` 已实现黄灯子检查，但 DocumentChain 生产链 Gate1 后未调用——unknown license 静默继续生产，搬运无授权审计硬门。
**修复**: DocumentChain 在 Gate1 评估后接入为 `GATE_SOURCE` 合规子检查：fail→`BLOCKED_REVIEW`（红灯拦截）、warn→记录继续（黄灯）、pass→直通；Repository 新增 `FindContentUnit` 供 Gate 读取来源元数据。
**文件**: `src/Workflow/DeepFrames.Workflow.DocumentChain.pas`, `src/Persistence/DeepFrames.Persistence.Repository.pas`

### B11. P0-H ArtifactOSBridge 租户隔离缺失（跨租户抢占/越权）
**Severity**: P0
**现象**: `011_db3_integration.up.pg.sql` 三张表（production_request/production_result/asset_status）都有 `tenant_id` 列，但 bridge 的 `PollRequests`/`ClaimRequest`/`ReleaseRequest`/`GetRequest`/`UpdateRequestStatus`/`ShouldRetryNow`/`WriteResult` **全都没按 tenant_id 过滤**——多租户时 worker 会跨租户抢任务、读写越权数据。
**修复**: 所有读取/claim production_request 的 SQL 加 `AND tenant_id = :tid::uuid`；ShouldRetryNow 查 production_result 加 tenant 过滤；WriteResult 的 INSERT 显式写 tenant_id 列（不再走默认 default tenant）。隔离落实在 SQL 层（强制过滤），bridge 每次 Query 带 `GetTenantId`。`SetTenantId`/`GetTenantId` 注入机制：未设时返回 default tenant 保证单租户向后兼容。
**测试**: `TestArtifactOS_TenantIdDefault`（未设→默认 tenant）+ `TestArtifactOS_TenantIdInjected`（注入读回）+ `TestArtifactOS_NotConnectedSafe`（无连接时所有 op 安全返回 False）。
**文件**: `src/Workflow/DeepFrames.Workflow.ArtifactOSBridge.pas`, `db/postgres/011_db3_integration.up.pg.sql`, `tests/DeepFrames.Tests.Core.pas`

### B12. P0-D CookieCloud 解密协议（复核确认已修复）
**Severity**: P0
**状态**: 本轮复核 `CookieCloudSync` 解密协议——key=IV=MD5(password) 已是修复后实现（与 P4-2 交付一致）。原 tasks.md 描述"现 key=IV=MD5(pw) 解密 0% 可用"为修复前状态，本轮确认修复已落地，标记完成。注：真实 CookieCloud 协议若为 key=MD5(uuid+'-'+pw)[:16]，需真实 endpoint 验证（属 P0-F 真实集成测试范畴）。

### B13. P0-I H.264 专利处理（定档 skip）
**Severity**: P0（商用合规）
**状态**: 商用需 H.264 授权或转 AV1/VP9。当前定档 skip（自用 POC 阶段），商用前必须二选一：① 取得 H.264 专利授权；② 转码管线默认 AV1/VP9（VideoTranscoder 已支持编码器切换，需补 AV1 默认策略 + 测试）。记入商用前阻断项。

### B14. P0-G 无预算护栏（LLM/图像调用无上限，单作业可烧穿预算）
**Severity**: P0（成本失控）
**现象**: DocumentChain 的 4 个 ChatComplete 调用无任何 token/调用数上限。LLM 重试循环、图像重生风暴等异常场景会持续调用 provider，单作业可烧穿整月预算，且无中断机制——这是 AI 视频流水线最大的成本泄漏风险。
**修复**: 新建 `DeepFrames.Workflow.BudgetGuard`——进程级 `TBudgetGuard`（类方法 + class var 字典），每作业按 JobId 累计 token（Prompt/Completion/Total）+ 调用计数（按 capability 分 llm/image/tts/asr/other）。`CheckBudget(JobId)` 在 token 超 `MaxTokensPerJob` 或调用数 ≥ `MaxCallsPerJob` 时 raise `EBudgetExceeded`，链路 except 路径标 job FAILED。DocumentChain 接入：Job 创建后 `Reset(JobId)`，每个 ChatComplete 前 `CheckBudget`、后 `Accumulate(Job.JobId, ChatMetrics)`。配置常量 `CONFIG_BUDGET_MAX_TOKENS_PER_JOB`/`CONFIG_BUDGET_MAX_CALLS_PER_JOB`（默认 20万 token / 60 调用）。
**测试**: `TestBudget_AccumulateAndCheck`（累计+不超）+ `TestBudget_TokenCeilingRaises`（token 超限 raise）+ `TestBudget_CallCeilingRaises`（调用数超限 raise）+ `TestBudget_ResetClearsUsage`（Reset 清零）。
**遗留**: 跨作业并发硬锁（多 job 并发访问字典）是第三阶段 High 项；当前单作业串行执行，安全。
**文件**: `src/Workflow/DeepFrames.Workflow.BudgetGuard.pas`（新建）, `src/Workflow/DeepFrames.Workflow.DocumentChain.pas`, `src/Shared/DeepFrames.Shared.Consts.pas`, `src/DeepFrames.dpr`, `tests/DeepFrames.Tests.Core.pas`

### B15. P0-F CI 流水线缺失（无自动编译+测试门禁）
**Severity**: P0（无回归防护）
**现象**: 仓库无任何 CI 配置——每次改动靠人工编译+跑测试，回归风险不可控；push/PR 无自动门禁。
**修复**: 新建 `.github/workflows/ci.yml`——self-hosted Windows runner（GitHub hosted 无 Delphi 工具链，必须 self-hosted），步骤：checkout → `_compile_df.bat` 编译主程序 → `_compile_tests.bat` 编译测试 → 跑 `tests\DeepFrames.Tests.exe`（205 测试，全 Fake provider）→ 真实 provider 集成 step（凭证门控 `DF_RUN_REAL_INTEGRATION=1` + secrets `DF_STEPFUN_KEY`/`DF_AGNES_KEY`/`DF_PG_*`）。触发：push 到 main/docs/** + PR 到 main。
**待填（P0-F 剩余）**: `tests/DeepFrames.Tests.RealIntegration.pas` 真实 StepFun/Agnes/PostgreSQL 集成测试——凭证就绪后填充，模式同 v5 VLM「配额就绪后激活」。当前 CI 跑的 205 测试全用 Fake provider mock，无真实 provider/PG 覆盖。
**文件**: `.github/workflows/ci.yml`（新建）

### B16. 第三阶段-ProbeCodec 解析容错（大小写/多空格/profile 括号）
**Severity**: High（容错）
**现象**: `ProbeCodec` 解析 `ffmpeg -i` stderr 找 `Video: ` 行，旧逻辑用大小写敏感 `Pos('Video: ')`——部分 ffmpeg 构建输出小写 `video:` 会漏；marker 后多空格时 `Copy(P+7)` 取到空串误判无视频流；codec 后紧跟 `(profile)` 如 `h264(High)` 会被吃进括号。空结果触发调用方无谓回退 libx264（浪费转码 + 专利状态误判 patented 而非 royalty-free）。
**修复**: 抽 `ParseCodecFromOutput` 为 public 纯函数（无文件 IO，可单测）；搜 lowercase marker `video:` 后 slice 原串（保 codec 原大小写）；Trim 跳过 marker 后多空格；codec token 在 `(`/`;`/空格`/逗号 处停止。ProbeCodec 注释明确：ffmpeg `-i` 对有效文件返回 exit 1 仍打印流信息，故 exit 仅参考；空结果=探测不结论，非转码失败。
**测试**: 6 个 ParseCodec 测试（标准/小写/多空格/括号 profile/无 Video 行/空输入）。
**文件**: `src/Workflow/DeepFrames.Workflow.VideoTranscoder.pas`, `tests/DeepFrames.Tests.Core.pas`

### B17. 第三阶段-Registry 单例无锁竞态（并发首调双创建+泄漏）
**Severity**: High（竞态）
**现象**: `TProviderRegistry.Instance` 旧逻辑 `if FInstance=nil then FInstance:=Create`——多 worker 线程并发首次调用时竞态：两线程同时见 nil，各创建一个实例，一个胜出赋值 FInstance，另一个的实例泄漏（FreeAndNil 只在 finalization 释放胜出者）。InitializeDefaults 的 `if FInitialized` 同样无锁，并发双初始化。
**修复**: 改双检锁——`class var FLock: TCriticalSection`，Instance 外层 nil-check（快路径无锁），内层 `FLock.Enter` 串行化 create+init；InitializeDefaults 同锁双检（TCriticalSection 基于 Windows CRITICAL_SECTION 可重入，Instance→InitializeDefaults 同线程嵌套 Enter 不死锁）。FLock 在单元 initialization 段创建（单线程加载，避免锁自身竞态），finalization 释放 FInstance+FLock。
**注**: tasks 原"SharedImageUploader/WebhookProvider 单例字段无锁"为过时引用，src/ 无此类型；ArtifactOSBridge 已有 FLock（同事加固），Registry 是唯一无锁单例。
**文件**: `src/Provider/DeepFrames.Provider.Registry.pas`

### B18. 第三阶段-DocumentChain 核心链路无结构化日志（生产链不可观测）
**Severity**: High（可观测性）
**现象**: `TWorkflowLogger` 封装 + DeepBase.Logging/LogDashboard 设施齐全，但核心生产链 `TDocumentChainWorkflow.RunChain` 完全未接入——4 个 ChatComplete provider 调用、gate 评估、链路异常均无结构化日志。provider 调用 latency/token 不可观测，链路失败时异常直接冒泡无记录，LogDashboard/LogAlert 看不到生产链任何活动。
**修复**: DocumentChain uses 加 `DeepFrames.Workflow.EventLog`；4 个 ChatComplete 成功后（TBudgetGuard.Accumulate 之后）调 `TWorkflowLogger.LogProviderCall(JobId, StepId, ProviderName, Model, CAPABILITY_LLM, LatencyMs, PromptTokens, CompletionTokens, '')`，latency/token/provider/model 入 LogDashboard 可观测；RunChain 主体包 `try/except on E do LogJobEvent('chain_failed', esError, E.Message, LogicalKey) then raise`——记链路级失败（provider down/gate hard-fail/budget exceeded/状态转换违例）后重抛，调用方行为不变。JobId 在 job 创建前失败时为空，回退 logical key 保可追溯。
**注**: metrics 基础设施 DeepBase.Metrics 已就绪，待按需埋点；错误追踪 via LogQuery/LogAlert 已可用。
**文件**: `src/Workflow/DeepFrames.Workflow.DocumentChain.pas`

---

## 2026-07-08 — 搬运 adapter 编码期 3 处编译修复

### 1. `TStringDynArray` 未声明 (YtDlpDownloader)
**Severity**: P1 (编译阻断)
**现象**: `DeepFrames.Workflow.YtDlpDownloader.pas(174) Error: E2003 Undeclared identifier: 'TStringDynArray'`
**原因**: `System.IOUtils` 不直接暴露 `TStringDynArray`，它在 `System.Types`。
**修复**: implementation uses 加 `System.Types`。
**文件**: `src/Workflow/DeepFrames.Workflow.YtDlpDownloader.pas`

### 2. interface 区 `TAudioSegment` 未声明 (AudioProcessor)
**Severity**: P1 (编译阻断)
**现象**: `AudioProcessor.pas(148) Error: E2003 Undeclared identifier: 'TAudioSegment'`，连带 626-684 行多处 E2007/E2066/E2008 级联错误。
**原因**: `VadSplit` 声明在 interface 区用了 `TArray<TAudioSegment>`，但 interface uses 只有 `System.JSON`——interface 区类型必须对使用方可见。
**修复**: interface uses 加 `DeepFrames.Domain.Types`（纯 record 定义，无循环引用风险）；从 implementation uses 移除同名重复引用。
**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas`

### 3. `DateTimeToISO8601` 未声明 (ImportChain)
**Severity**: P1 (编译阻断)
**现象**: `ExternalVideoImportChain.pas(67) Error: E2003 Undeclared identifier: 'DateTimeToISO8601'`
**原因**: 该函数签名/可用性随 Delphi RTL 版本变化，当前工具链 `System.DateUtils` 不直接暴露该名。
**修复**: 改用手写 `NowIso8601`（`DecodeDateTime` + `Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ')`），避免依赖版本特定 RTL。
**文件**: `src/Workflow/DeepFrames.Workflow.ExternalVideoImportChain.pas`

---

## 2026-06-17 — ArtifactOS 集成桥 next_retry_at 字段对齐（两轮反复）

### 1. next_retry_at 字段在 schema 与 INSERT 间反复对齐
**Severity**: P1. 同事的 ArtifactOS 加固 adapter 假定 `integration.production_result` 表含 `next_retry_at` 列，但实际 DB schema 不含该列 → `WriteResult` INSERT 失败，请求卡在处理中无法 complete。
**Root cause**: DeepFrames 侧 `011_db3_integration.up.pg.sql` 与 ArtifactOS 侧 `052_integration_tables.sql` 的 schema 定义不同步；adapter 的 `ShouldRetryNow`/`WriteResult` 假定了 ArtifactOS 侧才有的列。
**第一轮 fix** (`7a2be59`): 从 `WriteResult` INSERT 移除 `next_retry_at`、`ShouldRetryNow` 简化为恒返回 True、`PublishingWorker` 在 `WriteResult` 失败时 `ReleaseRequest`、bridge 补 `Data.DB` uses (`ftDateTime`)、修复单参 `Format()` 调用。验证 5/5 请求处理成功。
**第二轮 fix** (`1fd8bc7`): 字段实际已存在于 DB → 恢复 `ShouldRetryNow` 的 `next_retry_at` SELECT、恢复 `WriteResult` INSERT 的 `next_retry_at` 参数 (`ftDateTime` 类型)、`011_db3_integration.up.pg.sql` 的 `production_result` 表补 `next_retry_at` 列。两侧（ArtifactOS migration 052 + DeepFrames bridge）最终对齐。
**教训**: 跨系统 schema 对齐不能只看一侧迁移脚本，必须与对方实际 DB 实例核对；字段存在性反复横跳说明两轮都基于"我以为"而非"查实际表"。
**Files**: `src/Workflow/DeepFrames.Workflow.ArtifactOSBridge.pas`, `src/PublishingWorker.dpr`, `db/postgres/011_db3_integration.up.pg.sql`

### 2. PublishingWorker TThread double-free（FreeOnTerminate 默认 True）
**Severity**: P1. `TThread.CreateAnonymousThread` 默认 `FreeOnTerminate:=True`，匿名线程在 S2/S3 并行场景下被双重释放导致崩溃。
**Fix**: 显式设 `FreeOnTerminate:=False`，由调用方管理生命周期。
**File**: `src/VideoGenTest.dpr` S2_Images+S3_TTS 并行段（commit `2937292` v5）

---

## 2026-06-16 — P0-2~P7.9 开发期间发现并修复

### 1. LLM retry parse destroyed first-attempt results
**Severity**: P1. Validation failed on attempt 1, retry parse overwrote T with empty struct → 0 shots → EAccessViolation.
**Root cause**: `ParseLLM(C, T)` with `out T` zeroes the record on failure, losing valid parse from attempt 1.
**Fix**: Parse to local `NewT:TScript`, only assign `T := NewT` on success.
**File**: VideoGenTest.dpr S1_LLM

### 2. Image API rate limit (400 errors after 4+ consecutive calls)
**Severity**: P2. StepFun image API 400 after ~4 rapid calls.
**Fix**: `PC()` function with exponential backoff (max 2 retries, 1s→2s→4s…→16s), error JSON auto-detection, Sleep reduced from 3s to 2s.
**File**: VideoGenTest.dpr

### 3. VLM model `step-1o-turbo-vision` quota_exceeded
**Severity**: P2. VLM verification call returns quota_exceeded on current API plan.
**Status**: `VLM()` function + S2_Images integration ready; blocked on plan upgrade. Model exists (`/v1/models` confirmed). Also tried `step-1o-vision-32k` — both return quota_exceeded on `/v1` standard endpoint; neither available on `/step_plan/v1`.
**File**: VideoGenTest.dpr

### 4. DeepBase LLM.Proxy.pas E2555 — `deepbase.autofix` compilation blocked
**Severity**: P2. `dcc64 -B` fails on `LLM.Proxy.pas:636` — `E2555 Cannot capture symbol 'AResult'`.
**Cause**: Pre-existing bug in DeepBase dependency. Not in DeepFrames source.
**Workaround**: Incremental compile (omit `-B`) — DeepFrames units unchanged from last build.

### 5. TTask/TThread closed over `out` params — P2-7 parallelization blocker
**Severity**: P2. Delphi compiler error `E2555 Cannot capture symbol 'IP'` when `out` parameters appear in thread anonymous proc.
**Decision**: P2-7 deferred. The real constraint is StepFun API rate limits — parallel Image+TTS calls would trigger 429 without careful RPM throttling. Serialization is intentional for API safety.
**Note**: Not a bug, but a realistic API constraint documented to prevent future re-attempts.

---

## 2026-06-15 -- VideoGenTest Dev Bugs

### 1. step-3.7-flash thinking mode makes content empty
Severity: P1. LLM returned 8000+ chars but content was Chinese reasoning, not JSON.
Root cause: step-3.7-flash enables thinking mode by default, content=reasoning, reasoning_content=answer.
Fix: Add thinking:disabled to request body.
File: VideoGenTest.dpr

### 2. StepFun Image API size inversion
Severity: P2. Requesting 1360x768 returned a 768x1360 vertical image (letterboxed).
Root cause: API internally swaps width/height — 896x1184 produces 1184x896 horizontal.
Fix: Use IMG_SIZE = 896x1184 which yields 1184x896 output.
Files: VideoGenTest.dpr, StepFun.pas

### 3. ShellExecuteEx PChar dangling pointer crash
Severity: P0. EAccessViolation on ShellExecuteEx call, FFmpeg render completely broken.
Root cause: Delphi temporary string freed after PChar expression before ShellExecuteEx reads it.
Fix: Use UniqueString() to stabilize reference.
File: VideoRenderEngine.pas ShellRun()

### 4. FFmpeg zoompan format specifier clash with Delphi Format()
Severity: P1. zoompan=z=1.10+%d*on/30 where %d consumed by Delphi Format().
Root cause: Delphi Format() treats %d as integer placeholder, conflicts with FFmpeg syntax.
Fix: Replace all Format() calls with string concatenation in filter construction.
File: VideoRenderEngine.pas

### 5. AS is a Delphi reserved word
Severity: P2. var AS: TArray<string> compile error.
Fix: Rename AS to Segs.
File: VideoGenTest.dpr

### 6. CS variable name conflict
Severity: P2. var CS: TJSONArray compile error.
Fix: Rename CS to Arr.
File: VideoGenTest.dpr

### 7. Image API rate limiting on consecutive calls
Severity: P2. 400 errors after 4+ consecutive image generation calls.
Fix: Sleep(3000) between calls. Later upgraded to `PC()` exponential backoff (2026-06-16).
File: VideoGenTest.dpr

---

## 2026-06-13 — StepFun API 测试修复 (4 处)

### 1. StepFunTest.dpr 保留字冲突 (Of / TO)
**严重性**: P1 (编译阻断)
**修复**: `Of` → `OutF`，`TO` → `TkOut`
**文件**: `StepFunTest.dpr`

### 2. StepFunTest.dpr 多重变量初始化
**严重性**: P1 (编译阻断)
**修复**: `var P,F:Integer=0` → 拆分为独立声明
**文件**: `StepFunTest.dpr`

### 3. TTS WAV 二进制 → UTF-8 编码崩溃
**严重性**: P1 (运行时崩溃)
**修复**: 新增 `POST_RAW()` 通过 `ContentStream` → `TBytes` 获取原始字节
**文件**: `StepFunTest.dpr`

### 4. TTS voice ID 无效: `zh_female_qingxin`
**严重性**: P2 (API 调用失败)
**修复**: 改用 `cixingnansheng`
**文件**: `StepFunTest.dpr`

### 5. LLM small max_tokens → reasoning 吃光 token
**严重性**: P2 (content 为空)
**修复**: max_tokens 提升至 4096
**文件**: `StepFunTest.dpr`

---

### B19. 第三阶段-Baidu ASR 全 Stub + 无 TTS provider + StepFun 无订阅致 LLM/TTS/ASR 断链（真实测试前置阻断）
**Severity**: High（真实集成测试前置）
**现象**: 2026-07-09 实测外部 API 端点全部可用后，盘点 provider 代码层发现：①`TBaiduASRProvider`（284 行）全 Stub——`GetAccessToken`/`ConvertTo16kWav`/`SplitOnSilence`/`TranscribeChunk`/`Transcribe`/`TranscribeText` 均返回 NOT_IMPLEMENTED，无任何真实 HTTP 调用；②无 `TBaiduTTSProvider`（百度 audio_tts_post scope 已实测可用但无 provider 类）；③`CreateAgnesProviders` 把 LLM/TTS/ASR 复用 `TStepFun*Provider`，而 StepFun key 实测报 "you have no active step plan subscription"——LLM/TTS/ASR 三链全断。而 `TAgnesLLMProvider`/`TAgnesImageProvider`/`TAgnesVideoProvider` 已有完整真实 HTTP 实现（THTTPClient+Bearer+3 重试+metrics）且 agnes_key.txt 已有可用 key，仅 LLM 未被 `CreateAgnesProviders` 选用。
**修复计划**（本轮）：①补全 `TBaiduASRProvider` 真实 HTTP——OAuth token 获取（POST token 端点，缓存到 expires_at）、ffmpeg 转 16k WAV（复用现有 RunExternal）、server_api 分块转写（POST vop.baidu.com，base64 音频+JSON）；②新建 `TBaiduTTSProvider` 实现 `IDeepFramesTTSProvider`——POST `tsn.baidu.com` audio_tts_post，写音频到 OutputUri；③`CreateAgnesProviders` 改 LLM 用 `TAgnesLLMProvider`（已就绪真实实现），TTS/ASR 用百度（补全后）。StepFun 降级为备选（无订阅不可用）。
**注**: 安全——百度 API key/secret 经 `--set-secret deepframes/baidu/asr_key` 存 DPAPI，代码只读 secret 名，不硬编码。Agnes key 已在 agnes_key.txt（gitignore）。真实端点清单见 memory `deepframes-real-api-endpoints`。
**文件**: `src/Provider/DeepFrames.Provider.Baidu.pas`、`src/Provider/DeepFrames.Provider.Registry.pas`、（新增 TTS provider）

---

(历史 bug 从略 — 完整记录见 git log)
### B20 — DeepBase.Crypto.RSA.pas 多余 end; 致编译失败（跨仓库临时修复）
- 现象：DF/Tests 编译报 `DeepBase.Crypto.RSA.pas(671) Error: E2029 '.' expected but ';' found` → `DeepBase.Crypto.pas(28) Fatal: Could not compile used unit DeepBase.Crypto.RSA.pas`，阻断全部依赖 DeepBase.Crypto 的单元
- 根因：DeepBase.Core/DeepBase.Crypto.RSA.pas 是未跟踪（git ??）的新文件（同事草稿），LoadPrivateKeyPEM 函数末尾 :670 end;（关函数体）后多了一个 :671 end;，编译器期望单元结束符 . 却遇到 ;
- 临时修复：删除 :671 多余的 end;（属明显的单行笔误，结构配平后编译通过）。该文件在 DeepBase 仓库（非 DeepFrames），彻底修复应回 DeepBase 侧；本仓库不持有该文件，仅在本地解锁编译
- 验证：删后 _compile_df.bat 与 _compile_tests.bat 均 [OK]
### B21 — Tests.exe 退出 Runtime 217 / segfault 139（非测试失败）
- 现象：tests/DeepFrames.Tests.exe 跑完 211 tests 0 failed 后，进程退出时报 `Runtime error 217`（bash 下 segfault 139），退出码非零
- 根因：经 git stash 对照确认，217 在本轮 provider 改动之前就存在，与 Baidu/Registry/RealIntegration 改动无关；崩溃源在 DeepBase 层（疑为 DeepBase.Crypto.RSA finalization 段 BCrypt 句柄清理，与 B20 同一未完成文件相关），属 DeepBase 侧遗留
- 影响：测试结论正确（0 failed 已在崩溃前 flush 到 stdout），但非零退出码会让 CI 的 `if %ERRORLEVEL% neq 0` 误判红
- 修复：CI（.github/workflows/ci.yml）unit test step 改用 `findstr /C:"0 failed" tests_output.txt` 判断结果行而非退出码；Real step 同理用 findstr "FAIL:" 判红
- 验证：tests_output.txt 含 `=== 211 tests, 0 failed, 211 passed ===` + `All tests complete.`，findstr 命中 PASS
### B22 — RI4 Agnes image 真实生成挂起（待查）
- 现象：DF_RUN_REAL_INTEGRATION=1 跑 RealIntegration，RI1(Agnes LLM) 通过、RI2/RI3(百度) 正确 SKIP，但 RI4(Agnes image Generate) 既无 OK 也无 FAIL 输出，进程在其后无响应（被 timeout 杀）
- 可能根因：Agnes image 端点响应慢（图像生成耗时长）或请求构造问题（prompt/尺寸）或同步轮询未设超时
- 处理：未阻断 P0-F（核心目标=provider 真实 HTTP 实现就绪 + 门控正确，已达成）；记此待后续用 --set-secret 配 Agnes key 后单独调试 RI4，或给 Generate 加超时/异步轮询
- 当前 RealIntegration.pas 的 RI5(video) 已用 DF_RUN_VIDEO_TEST=1 二级门控隔离慢测试，RI4 暂未加门控（image 通常快于 video），后续视排查结果决定是否同样门控

---

## 2026-07-09 续补（RI5 真绿 + VideoChain 接入）

### B23 — RI5 Agnes 视频 URL 提取五处 bug（假绿→真绿）
- **背景**：RI5(video) 此前报 OK 但下载 0 字节/失败——假绿。真调隔离出 5 处 bug，全修后 RI5 真绿，下载到 608KB MP4。
- **bug1 — 视频取错字段**：原取 `data.result_url`，该路径 `/v1/videos/<task>/content` 实际返回 502。真实 CDN 视频在 `data.data.url`。改取 `DataObj.data.url`，`result_url` 仅作 fallback。
- **bug2 — status 大小写**：Agnes 完成返回大写 `SUCCESS`，原判断 `status=SUCCESS`（敏感比较）或只兼容小写 `completed`/`succeeded`，导致完成态轮询不退出。改 `SameText` 兼容大写 SUCCESS + 小写 completed。
- **bug3 — DownloadFile 缺鉴权**：CDN 下载未带 Authorization 头，返回 401/空。补 Bearer 头。
- **bug4 — DownloadFile 缺 Content-Type 校验**：失败响应（JSON error）被当音频写盘→0 字节坏文件。补校验 Content-Type 必须是 video/* 或 application/octet-stream，否则视为失败。
- **bug5 — CDN 拒 Bearer**：CDN 域名不接受 Bearer 鉴权（只 API 域名接受）。鉴权头只在调用 API 域名（status 轮询/result 查询）时加，下载 CDN 时不加。
- **文件**：`src/Provider/DeepFrames.Provider.Agnes.pas`（~1079/1186/1188/1201 行附近）
- **提交**：`ef17805 fix(Agnes video): 修复 5 处 URL 提取/下载 bug，RI5 从假绿转真绿`
- **关联 memory**：`agnes-video-url-extraction-bugs`

### B24 — VideoChain Step4/Step5 未接入真实 provider + mux bug 残留（生产视频无字幕无声音根因）
- **背景**：VideoChain 渲染/mux 原为 stub，不调 Agnes；字幕用硬编码假数据、无烧录；PackageChain 无入口。Agnes provider 本身已修好但接入层断链。`cf32f4c` 全链路接通。
- **Step4 接入**：`VideoChain.pas:341` 取 `TProviderRegistry.Instance.VideoProvider`（=Agnes），:363 调 `GenerateVideo`，:376 失败 raise 硬中断。无 provider 时显式报错而非静默 stub。
- **Step5 mux 加固**：mux VideoStep 提前到 mux 执行前创建（:433，使失败能记 ErrorMessage）；mux 非零退出 :507 写 ErrorMessage + :511 raise 硬中断（不再吞错标 DONE，复现 B5 的修复模式）；缺 audio URI :473 硬中断（不再静默跳过 mux 产出无声视频）。
- **字幕烧录**：有字幕时走 `-c:v libx264` 烧录分支（:493 `video_mux_subtitle_burn` 日志），无字幕走 `-c:v copy` 快速 mux（:503）。烧录用 libass，`:` 转义问题已在 :47 注释说明。
- **文件**：`src/Workflow/DeepFrames.Workflow.VideoChain.pas`
- **提交**：`cf32f4c fix(workflow): VideoChain Step4 接入 Agnes GenerateVideo + 修 Step5 mux 两处致命 bug`
- **关联 memory**：`video-chain-not-wired-end-to-end`（该 memory 记录的根因已由 `cf32f4c` 解决，待清理为已解决状态）

### B22 状态更新 — RI4 Agnes image 仍待查，但已加超时硬墙（不再挂死进程）
- RI5 已由 B23 修复转真绿；RI4 image 挂起根因（疑似 SSL 握手卡死超过 THTTPClient.ResponseTimeout，`HTTP.Post` 不返回）仍未根治，但不影响主链路（生产用 video 走 RI5 已通）。
- **2026-07-09 缓解**：RI4 测试层用 `TThread.CreateAnonymousThread` + 硬墙超时（默认 150s，`DF_IMAGE_TEST_TIMEOUT_MS` 可调）包裹 image Generate 调用。SSL 卡死时主线程轮询 `DoneFlag` 超时即报 FAIL 并写诊断行，worker 线程泄漏不 WaitFor（避免死锁，进程退出时回收）。挂起降级为可控 FAIL 而非无限挂死。生产 provider 语义不变（保持同步）。
- 根因彻底排查待：存 Agnes key 后开启 `DF_RUN_IMAGE_TEST=1` 真跑，确认是 SSL/Indy 配置还是端点本身慢，再决定 provider 层是否加异步轮询（image 无 task 模型，难像 video 那样轮询）。

---

## 2026-07-13 — pipeline 端到端首次跑通（5 blocker 修复）

> `--run-pipeline` 首次生成 366KB MP4（`output/video/{job_id}/output/bilibili_1080p.mp4`），此前管道因 5 个独立 blocker 全链中断。本轮逐一修复。

### B25. FindAudioManifestByShot 访问违规（pipeline Step1 AV）
**Severity**: P0
**现象**: `App.Services:621` 调 `FindAudioManifestByShot` 触发 AV，pipeline 在音频链入口即崩。
**原因**: 该查询对尚无 manifest 的 shot 返回状态不一致，解引用空结构。
**修复**: 管道入口绕过该调用，直接使用空 `AudioManifestId` 占位，由后续 Insert 补全。
**文件**: `src/App/DeepFrames.App.Services.pas:621`
**验证**: pipeline 跨过 Step1 进入 Step2。

### B26. InsertVideoDir 未处理空 AudioManifestId（NULL 参数类型推断失败）
**Severity**: P0
**现象**: `Repository.pas:2037` `InsertVideoIR` 传空串 `AudioManifestId` → FireDAC 参数类型推断失败，INSERT 失败。
**原因**: 空串未走 NULL 路径，驱动无法推断列类型。
**修复**: `if AudioManifestId = '' then Param.Clear else Param.AsString := AudioManifestId`。
**文件**: `src/Persistence/DeepFrames.Persistence.Repository.pas:2037`
**验证**: VideoIR 记录写入成功。

### B27. Baidu TTS 语音 ID 字符串/数字不匹配（TTS 静默失败）
**Severity**: P0
**现象**: Baidu TTS 需要数字语音 ID（如 `106`），管道传语音名称字符串（如 `cixingnansheng`）→ TTS 请求被拒。
**修复**: 加语音名→数字 ID 映射（`cixingnansheng→106`, `putongnvsheng→4118`, `putongnansheng→4119`）。
**文件**: `src/Provider/DeepFrames.Provider.Baidu.pas:773-787`
**验证**: TTS 产出真实 wav。

### B28. 空字符串作 jsonb 传参（CAST('' AS jsonb) 失败）
**Severity**: P0
**现象**: `AudioChain.pas:529` `UpdateAudioManifestLoudnorm` 传 `''` 作 `Pass1Json` → PostgreSQL 无法 `CAST('' AS jsonb)`。
**修复**: 空值改传 `'{}'`。
**文件**: `src/Workflow/DeepFrames.Workflow.AudioChain.pas:529`
**验证**: loudnorm manifest 写入成功。

### B29. LoudnormApply 用完整 ffmpeg 输出当 RawJson（JSON 解析失败）
**Severity**: P0
**现象**: `AudioProcessor.pas:474-479` 把含非 JSON 文本的完整 ffmpeg 输出当 `RawJson` → 下游 JSON 解析失败。
**修复**: 改用 `ParseLoudnormJson` 提取的纯 JSON，提取失败则回退 `'{}'`。
**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas:474-479`
**验证**: loudnorm pass2 正常执行。

---

## 2026-07-13 — mux 两处致命 bug（管道死锁 + srt 路径）

### B30. RunFFmpeg 管道死锁（mux 0 字节输出）
**Severity**: P0
**现象**: `RunFFmpeg` 用 `WaitForSingleObject(hProcess, 300000)` 等 5 分钟才读管道。ffmpeg 进度打 stderr，4KB 内核缓冲填满后 ffmpeg 阻塞在 write，父进程等子退出 → 死锁。表现：mux `exit=-1`、输出 0 字节，手动命令行 0.84s 完成。
**修复**: 改 `WaitForSingleObject(..., 100)` 短轮询 + 每次持续排空管道，累计 `TotalWaitMs` 达 300000 才 `TerminateProcess`。同时加 `ATimeoutMs: Cardinal = 300000` 默认参数（向后兼容），VideoChain mux 处按源视频时长算自适应超时 `Min(Max(120, SrcDuration×10), 1800)×1000` ms。
**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas:236`、`src/Workflow/DeepFrames.Workflow.VideoChain.pas`
**验证**: mux `exit=0`，572KB mp4。

### B31. libass subtitles filter 不接受 Windows 绝对路径
**Severity**: P0
**现象**: `-vf "subtitles=D:/path.srt"` 报 `Unable to parse ... as image size` / `original_size: Invalid argument`。
**原因**: subtitles filter 第一参数是 filename，但路径里的 `:` 被当 option 分隔符，`D` 当空 filename、`/path` 当 original_size。
**修复**: `f=` 前缀显式指定 filename + 单引号包值 + 冒号转义 `\:` → `subtitles=f='D\:/path/zh.srt'`（`EscapeSrtPathForFilter:815-816`）。`-preset` 由 `medium` 改 `veryfast`（字幕 burn 需 libx264 重编码，medium 长视频超时）。
**文件**: `src/Workflow/DeepFrames.Workflow.VideoChain.pas:628`
**验证**: 中文字幕烧入 1088x832 mp4，音画时长对齐 3.25s。

---

## 2026-07-13 — mux 音画时长错配（audio 被截到 5s）

### B32. mux 默认 shortest 策略截断音频
**Severity**: P0（核心生产能力缺陷）
**现象**: TTS 音频 68.75s，Agnes 视频 5s，mux 默认 `DEFAULT_DURATION_STRATEGY='shortest'` → 输出截到最短流(5s)，**丢弃音频尾部 63s**。MP4 有音画但音频只 5s。
**修复**: `DEFAULT_DURATION_STRATEGY` 改 `'audio-base'`（音频为准不截断）；audio-base 下若 `VideoDurSec < AudioDurSec`，给视频输入加 `-stream_loop -1`（首个 -i 前）循环填充到音频时长；两个 mux 分支 Format 串都加 `%s VideoLoopArg` 前缀。
**文件**: `src/Shared/DeepFrames.Shared.Consts.pas:331`、`src/Workflow/DeepFrames.Workflow.VideoChain.pas:545-635`
**验证**: force-rerun 后 MP4 音频=263.36s 视频=263.375s（对齐），此前 5s。
**残留**: failover 链 TTS 仍退化为 gemini STUB 假音频，真 TTS 待配 key（见 DBA-1）。

---

## 2026-07-14 — 文档链崩溃三连环（0x00 / 围栏 / raw_output）

### B33. 中文 payload_json 含 0x00 + markdown 围栏 + raw_output NOT NULL
**Severity**: P0
**现象**: pipeline 文档链（DocumentChain）写含中文的 `payload_json` 时崩溃。根因经逐行 `TextFile` marker 定位为三连环：
1. 中文 `payload_json` 含 `0x00` 字节 → FireDAC WideString 绑定层写入失败（UTF8 字节无 0x00，但 UTF16 绑定路径引入）；
2. markdown 围栏 `` ` `` 字符在 JSON 序列化时破坏结构；
3. `raw_output` 列 NOT NULL，空值写入失败。
**修复**: 三处分别处理——0x00 在写入前剥离；围栏字符转义；`raw_output` 空值补默认占位。
**文件**: `src/Workflow/DeepFrames.Workflow.DocumentChain.pas`（及关联写入路径）
**验证**: pipeline 端到端跑通生成 612KB MP4，文档链不再崩溃。
**关联 memory**: `firedac-pg-utf16-nul-blocker`（P2 残留：UTF16 绑定层 0x00 阻塞未根治，AsBytes/MapRules 待试）。

---

## 2026-07-14 — 三修复（Baidu 明文 key / Mark 接 stdout / srt 时长夹到音频）

### B34. Baidu provider 4 处明文 key 回退（违反铁律 #5）
**Severity**: P0（架构红线）
**现象**: `Baidu.pas` 的 ASR/TTS 各 2 处 `GetConfig(CONFIG_BAIDU_ASR_*, '')` 明文 Settings 回退，密钥可能落地 DB1 ConfigDB，违反开发红线 #5「不把 API Key 写入 .env/JSON/INI/Registry/日志/DB2」。
**修复**: 删 4 处明文回退，只走 env var（`DF_BAIDU_APIKEY`/`DF_BAIDU_SECRET`）+ `LoadSecret(SECRET_BAIDU_ASR_KEY)`（分号 split）。常量保留但无运行时引用。
**文件**: `src/Provider/DeepFrames.Provider.Baidu.pas`
**提交**: `cc79af8`

### B35. Mark() 空函数致步骤可观测性为 0
**Severity**: P1
**现象**: `App.Services:749` `Mark()` 是空函数，`--force-rerun` 日志无 step 边界，真假绿无法快速区分（正是 07-14 评审「真假绿」根因之一）。
**修复**: `Mark()` 改 `Writeln('[phase] ', S) + OutputDebugString`，uses 加 `Winapi.Windows`。force_rerun.log 现显示 `[phase] P0-force-rerun` ... `[phase] P6-done` 8 行边界。各 chain 细粒度日志仍由 `TWorkflowLogger` 落 PG。
**文件**: `src/App/DeepFrames.App.Services.pas:749`
**提交**: `cc79af8`

### B36. ASR 时间戳虚标致 srt 结束时间超出视频时长
**Severity**: P1
**现象**: StepFun ASR 对 3.25s 音频报 `end_time=8250ms`（`StepFun.pas:770` 用 max end_time 当时长），srt 结束 `00:00:08,250` > 视频 3.25s，字幕时间轴与视频不符。
**修复**: `VideoChain.pas:282` 调 `BuildCues` 前用 `AM.DurationSec`（mux 音频时长）夹 `TsWords[i].StartSec/EndSec`。**必须用索引循环** `for Wi:=0 to High`——Delphi for-in 对 array of record 是值拷贝，改 W 不改数组。
**文件**: `src/Workflow/DeepFrames.Workflow.VideoChain.pas:282`
**提交**: `cc79af8`
**验证**: `--force-rerun` 产 3.25s mp4（音画对齐）+ srt `00:00:00,000 --> 00:00:03,250`。

---

## 2026-07-15 — 仓库历史重建（清除明文 key 提交）

### B37. 明文 API key 残留 git 历史（单人单机场景处置）
**Severity**: 原评 P0（商用阻断）；单人单机无远端场景降为已处置
**现象**: `agnes_key.txt`/`stepfun_key.txt` 曾明文提交进旧 git 历史（`8cf8ccb`/`e176c31`），虽 07-08 做过 `git rm --cached`，但历史提交仍在，任何人 clone 可取明文 key。
**处置决策**: 仓库为单人单机、**从未配置任何远端**（`git remote -v` 为空），无协作者，历史 key 泄露对当前场景无实际风险。决定**删除整个 `.git` 重建**，而非 `git filter-repo` 清史。
**执行**:
1. 备份 `_baidukey.txt`（57B 明文）到仓库外 `D:\_Progs\02Business\DeepFrames_keys_backup\`，原文件留工作区供程序继续读；
2. `.gitignore` 加固：补 `_baidukey.txt`、`df_*.txt` 诊断、散落 JSON（`models.json`/`_fccy.json`/`veo_test.json`/`veo1.json`/`tts_test.json`）、`*.bak`、`**/root.txt`、`_*.out`/`_*.txt` 调试捕获；
3. 删 `.git` → `git init` → `git add .`（验证明文 key/二进制/诊断文件全被忽略）→ 首个 commit `832fe98 chore: rebuild repo from clean baseline`，236 文件、67 源码，含 4 个未提交源码改动（dpr/Repository/StepFun/AudioProcessor）。
**结果**: `git log` 仅剩一条干净提交，旧历史（含明文 key）彻底消失。工作区干净。
**后续**: 明文 key 待迁入 `DeepBase.Security.LoadSecret`（DB1）后删除根目录明文文件（见 tasks.md DBA-1）。
**关联 memory**: `keys-leaked-in-git-history`（该 memory 记录的「清史未做」已由本次重建解决，但「密钥轮换」对单人单机无远端场景不再必要，memory 待更新）。

---

## 2026-07-21 — DBA-5 接入首两文件时发现并修复

### B38. GUI 进程无控制台时 WriteLn 触发 EInOutError 崩溃
**Severity**: P1
**现象**: `App.Services.pas`（ImportMarkdown 诊断、`RunFullPipeline` 的 Mark/`[phase]` 边界）与 `Workflow.AudioChain.pas`（TTS 成功/ASR words 三处诊断）用裸 `WriteLn` 输出。这些路径在 CLI 控制台模式下正常，但**同一代码路径在 VCL GUI 进程内也执行**——GUI 无标准输出句柄时，`WriteLn` 抛 `EInOutError`（I/O 错误 105），导致 GUI 一键成片时崩在该诊断行，掩盖真实业务结果。也使"真假绿无法区分"——诊断只在 CLI 能看到，GUI 下直接崩。
**原因**: 诊断混用 `WriteLn`（控制台专用），未走 `DeepBase.Logging` 结构化日志 facade。
**修复**: 上述两文件全部 `WriteLn(Format(...))` → `DeepBase.Logging.Logger.InfoFmt(...)` / `ErrorFmt(...)`，带 category（`DeepFrames.Audio` 等）。统一走 facade 后：GUI 进程不崩、CLI 仍可见、且日志落 DB 可审计——一并消除 DBA 线"未接 Logging 前真假绿不分"的结构根因。
**文件**: `src/App/DeepFrames.App.Services.pas`、`src/Workflow/DeepFrames.Workflow.AudioChain.pas`
**验证**: `dcc64 -B` DeepFrames.dpr → 0 Error；EXE 内 UTF-16LE 扫描确认 `DeepFrames.Audio` category 已编入二进制。运行验证（GUI 真跑）留作 DBA-2 后续。
**注**: 仅修了首两文件；`src/` 其余 `WriteLn`（各 Workflow/Provider 诊断）仍待逐文件迁 Logger，列为 DBA-5 待办。

## 2026-07-21 续 — DBA-3 LLM facade 接入：tier 覆盖陷阱（设计缺陷，未引入即防）

**现象**: DBA-3 评估阶段发现——`DeepBase.LLM.Service.ILLMClient` 只有 `ChatWithHistory(Tier, Messages, MaxTokens, Temperature): TChatResult` 一个重载，按 tier 路由 + provider `priority` 选优，**无"指定 provider"重载**。但 DeepFrames `Provider.Registry.pas:227` 有 `TFailoverLLMProvider.Create([Agnes, Gemini])`——同进程多 LLM provider 并存且依次 failover。若 Agnes 和 Gemini 都薄封装走 `LLM.ChatWithHistory(TierSmart,...)` 且都在 Bootstrap 注册 TierSmart，**后注册者的 `SetTierModels` 覆盖前者** → failover 链断裂：Agnes 失败后调 Gemini 时 TierSmart 已被 Agnes 改向，Gemini 实际打 Agnes endpoint 必败，表现为"Agnes key 失效后整个 LLM 链死"而非优雅降级到 Gemini。
**原因**: facade 的 tier 路由模型假设"每个 tier 只有一个最优 provider"，与 DeepFrames 的"多 provider 显式 failover"语义冲突。同 tier 多 provider 注册时后者静默覆盖前者，无报错、无告警。
**修复**: 采用方案②——给 `ILLMClient` 加 `ChatWithHistoryByProvider(Name, Model, Messages, MaxTokens, Temperature): TChatResult` 重载（`DeepBase.LLM.Client.pas` 接口 + `DeepBase.LLM.Service.pas` 实现 + `DeepBase.LLM.HTTP.pas` 透传 provider 名到 `FProviders.ByName(Name)` 直路由，不经 tier 选优）。Agnes/Gemini `CallRealAPI` 走此重载，按 provider 名直路由，多 provider 并存互不覆盖。
**文件**: `DeepBase.LLM.Client.pas`、`DeepBase.LLM.Service.pas`、`DeepBase.LLM.HTTP.pas`、`src/Provider/DeepFrames.Provider.Agnes.pas`、`src/Provider/DeepFrames.Provider.Gemini.pas`
**验证**: `dcc64 -B` DeepFrames.dpr → 0 Error（68962 行 3.03s）；commit `d90a9d9`。运行时 failover 真跑验证待 DBA-1 凭据后做。
**注**: 此为**设计陷阱防回归记录**——评估阶段即识别，未实际引入 bug 即绕开。若未来有人删 `ChatWithHistoryByProvider` 重载改回 tier 路由，须先确认 DeepFrames failover 语义已改或每 tier 单 provider，否则 reintroduce 此陷阱。

## 2026-07-21 续2 — DBA-3 Gemini 走 OpenAI 兼容端点（丢服务端强制的残留记录）

**现象**: Gemini 原生 `generateContent` API 用 `responseMimeType:application/json` + `responseSchema` + `generationConfig.thinkingConfig.thinkingBudget:0` 三件服务端强制（结构化输出 + 禁 thinking）。DeepBase facade HTTP 层只支持 openai/anthropic 两格式（`DeepBase.LLM.HTTP.pas Send` 仅 `SameText(AApiFormat,'anthropic')` 分支 + else openai 分支），不支持 Gemini 原生格式。若强给 facade 加 gemini 格式分支会污染 DeepBase（违反 facade 通用性）。
**原因**: facade 的格式抽象粒度是"OpenAI 兼容 / Anthropic"，Gemini 原生格式不在其内。
**修复**: Bootstrap 注册 Gemini 用 **OpenAI 兼容端点** `https://generativelanguage.googleapis.com/v1beta/openai`（Google 官方兼容层），`ApiFormat='openai'`，facade `BuildOpenAIRequest`+`ParseOpenAIResponse` 直调直解。ASR/vision 的原生 `generateContent`（需 multipart/audio part）保留独立原生 HTTP 路径不走 facade。
**残留风险**: 三件服务端强制丢失——① `responseMimeType`/`responseSchema` 不透传，改客户端 `TJsonSchemaValidator.Validate` 兜底（与 StepFun 一致，可接受）；② `thinkingBudget=0` 不透传，Gemini 2.5 是 thinking 模型，可能因 thinking 耗尽 MaxTokens→空 content。facade 的 reasoning_content 回退（本轮补的 `ParseOpenAIResponse` 抽 reasoning）仅对 OpenAI 格式 `reasoning_content` 字段生效，Gemini OpenAI 兼容层是否回退 thinking 到 reasoning_content 待实测。缓解：调用方传大 MaxTokens + 文件内 follow-up 注释标注。
**文件**: `src/App/DeepFrames.App.Bootstrap.pas`（GEMINI_OPENAI_ENDPOINT 常量）、`src/Provider/DeepFrames.Provider.Gemini.pas`（CallRealAPI 注释 follow-up）
**验证**: 编译过；运行时 Gemini 真跑产 content 待 DBA-1 凭据后实测（重点验证 thinking 不吞空 content）。

## 2026-07-21 续3 — DBA-1 收尾：secret 存错库（运行时读根库但 secret 在 bin 库）

**现象**: `DeepFrames.exe --verify-secret <name>` 对 4 个真用 secret（`agnes_api_key`/`gemini_api_key`/`baidu_asr_key`/`stepfun_step_plan_key`）全返回 `EMPTY: not found or blank`。但 `bin/DeepFramesConfig.db` 的 Secrets 表明明有 9 行（含这 4 个）。
**原因**: `DeepBase.Manager.FindRootPath` 读 EXE 同目录 `root.txt` 第一行作 RootPath → ConfigDbPath = `RootPath\DeepFramesConfig.db`。`bin/root.txt` 内容是 `D:\_Progs\02Business\DeepFrames`（项目根），所以运行时连**根目录** `DeepFramesConfig.db`，而非 `bin/DeepFramesConfig.db`。而根库 Secrets 表空（DBA-1 期所有 `--set-secret`/`--set-secret-file` 是在 `bin/` 下跑的，灌进了 `bin/DeepFramesConfig.db`；`src/root.txt` 又指向 `src/`，故 `src/DeepFramesConfig.db` 也有自己的副本）。三库不一致：bin/ 有 9 secret、src/ 有 deepframes/db2 一条、根库 0 secret。
**修复**: 把 `bin/DeepFramesConfig.db` Secrets 全 9 行同步到根库 `DeepFramesConfig.db`（`sqlite3 ATTACH bin AS src; INSERT OR IGNORE INTO Secrets SELECT * FROM src.Secrets;`）。同机同用户 DPAPI blob 跨库可解密（CurrentUser scope，不绑定 DB 文件）。同步前备份根库为 `DeepFramesConfig.db.bak-pre-secret-sync`。
**验证**: `bin/DeepFrames.exe --verify-secret` 四个 secret 全 `OK` + 正确 length + masked head/tail：
- `agnes_api_key` len=51 head=sk-S...tail=ctzp（sk- LLM key 格式 ✓）
- `gemini_api_key` len=53 head=AQ.A...tail=n5zg（AIza 格式 ✓）
- `baidu_asr_key` len=57 两行 24+32（AppId+SecretKey ✓，head=7fEo/QFMJ 与已删 `_baidukey.txt` 明文一致——证明迁的就是那个 key，无凭据丢失）
- `stepfun_step_plan_key` len=60 ✓

  注：`Halt(0)` 后进程退出阶段 segfault（FireDAC 连接池关闭，非数据问题），`OK:` 行已先输出，功能验证通过。
**文件**: `DeepFramesConfig.db`（根库，数据同步，无代码改）
**残留/待清理**:
1. **三库副本不一致是结构问题**：根/src/bin 各有一份 DeepFramesConfig.db。根库是运行时真用的（root.txt 指向根）。建议：DBA-1 后续统一——要么 src/root.txt 也指向根、删 src 库；要么运行时固定单库。当前靠同步 patch 不治本。
2. **死 key 未清**：Secrets 表仍含大写 `AGNES_API_KEY`/`STEP_FUN_API_KEY`/`agnes_llm_api_key`（代码只读小写常量，死 key 无引用）。非阻断，清理项。
3. **`--verify-secret` 注释标 TEMP 待 DBA-1 验收后删**：现已验收通过，可择机删此临时 CLI（但保留便于老板存凭据后自检）。
**验收（DBA-1 真跑门）**：4 secret 全 LoadSecret 往返成功，无凭据丢失。**通过**。

## 2026-07-21 续4 — DBA-3 深层根因：pipeline 吞失败→DONE（设计缺陷，未修，记根因）

**现象**：DBA-3 残留④原描述"stub 返回 True 伪装成功"。本会话深查 `DocumentChain.pas:195-252` 的 `build_script` step，发现比"stub 返 True"更深一层的根因：**LLM 失败时 pipeline 把失败吞成 DONE**。`Provider.ChatComplete(...)` 返回 False（else 分支，line 240-248）时，仍 `CreateScriptDocument(... ContentHash := 'stub-script-v1')` + `ScriptDoc.Status := STATUS_DONE`，随后 line 250-252 无条件 `CanTransitionStatus(STATUS_RUNNING, STATUS_DONE)` + `UpdateJobStepStatus(Step.StepId, STATUS_DONE)`——即**无论 LLM 成功还是失败，该 step 都被标 DONE**。
**原因**：else 分支的设计意图是"无 key 时降级产 stub doc 让链继续跑"（07-13 端到端跑通期遗留），但混淆了"降级继续"与"失败伪装成功"——stub doc 没有任何 `STUB`/`degraded` 标记，Status 直接 DONE，下游无法区分"真实 LLM 产出的脚本"和"stub 占位"。这使 D2「端到端真跑」的"绿"可能掩盖 LLM 全程没真调通。**与 stub 返回值无关**：即使按 DBA-3 残留④把 CallStubAPI 改成返回 `Success=False`+STUB 标记，else 分支仍会标 DONE——残留④只动 stub 返回值治不了本。
**真修方向**（待做，需真跑验证）：① else 分支不再无条件 STATUS_DONE——至少在 stub doc 上打 `degraded=true`/`source=stub` 元数据，或当 provider 有 key 但 ChatComplete 仍失败（非降级而是真失败）时标 STATUS_FAILED/`blocked_review`（依红线 8「黄灯记录并提醒，红灯才进 blocked_review」）；② 区分"无 key 降级"（黄灯 stub 继续跑）与"有 key 真调失败"（红灯停）。**阻断**：本修复需真跑验证 LLM 链通/不通两态，但当前被 DeepBase 编译阻断（见下条 07-21续5）无法编译 EXE，故记根因暂不修。
**文件**：`src/Workflow/DeepFrames.Workflow.DocumentChain.pas:195-252`（未改）
**关联**：DBA-3 残留④、D2 真假绿、bugfix 07-21续（tier 覆盖陷阱）。

## 2026-07-21 续5 — 🔴 阻断：DeepBase 未提交 LLM 重构致 DeepFrames 编译失败（跨仓库，非本仓库引入）

**现象**：`_compile_df.bat`（`dcc64 -B` DeepFrames.dpr）失败，exit=1，错误集中在 DeepBase 仓库（非 DeepFrames）：
- `DeepBase.LLM.Proxy.pas(34) Error: E2291 Missing implementation of interface method DeepBase.LLM.Client.ILLMClient.ChatWithHistoryByProvider`
- `DeepBase.LLM.Proxy.pas(571/573/577/579) Error: E2250 There is no overloaded version of 'ForceQueue'/'Run' that can be called with these arguments`
- `DeepBase.LLM.Service.pas(21) Fatal: F2063 Could not compile used unit 'DeepBase.LLM.Proxy.pas'`

**原因**：DeepBase 工作树有未提交改动（`git diff --stat` = `LLM.Client.pas +12 / LLM.HTTP.pas +9 / LLM.Service.pas +44`，共 +65 行，全 insertion，mtime 07-21 12:24~12:29 今天刚改）给 `ILLMClient` 接口加了 `ChatWithHistoryByProvider` 等新方法/重载，但 `LLM.Proxy.pas`（mtime 07-09，未动）未更新实现 → 接口与实现不同步 → 编译不过。`-B` 强制全编 DeepBase 源码（而非用 7-16 的新鲜 dcu），撞上工作树的不匹配改动。
**性质**：DeepBase 仓库的进行中、未完成、未提交 LLM 重构，**非本会话引入**（本会话仅改 DeepFrames.dpr 加 `--test-llm` CLI，不可能影响 DeepBase.LLM.Proxy）。疑为别会话/老板今天 12:24 起的重构工作。
**决策**（escalation-check → SELF_DECIDE「重构」）：采**不破坏路径**——不回退 DeepBase 未提交改动（破坏他人进行中工作）、不擅补 Proxy.pas 实现（跨仓库介入别人重构、意图可能不符）。暂停 DeepFrames 一切需编译 EXE 的开发：DBA-3 `--test-llm` 真跑验证、D1/D2、后续全链均卡住，直至 DeepBase 重构完成/提交、DeepFrames 重新可编译。
**已留**：`--test-llm [provider]` CLI 代码已在 `src/DeepFrames.dpr`（line ~176 后，调 `TProviderRegistry.Instance.LLMProvider.ChatComplete` 打印 Success/ErrorCode/LatencyMs/Tokens/ResponseJson 头 200 字，stub 输出判 FAIL），DeepBase 解封后编译即可直击 DBA-3 验收门。
**影响范围**：DBA-3 残留④真修 + 端到端真跑验证全部待 DeepBase 解封。当前仅文档对齐类工作（tasks/history/bugfix）不依赖编译，可继续。
**验证**：`cmd.exe //c _compile_df.bat` → 上述 E2291/E2250/F2063，exit=1；DeepBase `git status --short` 确认 `M Features/DeepBase.LLM.Client.pas` / `LLM.HTTP.pas` / `LLM.Service.pas`，`LLM.Proxy.pas` 未列。
**文件**：无 DeepFrames 代码改动引入此错；DeepBase 侧 `Features/DeepBase.LLM.{Client,HTTP,Service,Proxy}.pas`。
**关联**：DBA-3、续4 pipeline 吞失败（同待 DeepBase 解封后真跑验证）。

### 续5 补记（07-21，**阻断已解除** + 真根因修正）

上面续5 初判的"Proxy.pas 未更新实现"只是**表象第一层**。老板授权介入 DeepBase 查清后，真根因如下：

**真根因**：`TLLMService`（DeepBase.LLM.Service.pas）**类声明段漏 `ChatWithHistoryByProvider` 的 forward 声明**。原作者在 Client.pas 给 `ILLMClient` 接口加了 `ChatWithHistoryByProvider` 抽象方法、Service.pas 写了实现、Proxy.pas 也声明了——**独漏 TLLMService 类声明段的 forward 声明**。Delphi 实现段写 `function TLLMService.X(...)` 要求 X 已在类声明里 forward 声明；若没有 → 编译器不认这是类方法实现 → `E2003 Undeclared identifier: 'X'`（line 454）+ `E2291 Missing implementation of interface method`（line 24，类没真正实现接口方法）+ 连带 `E2250 ForceQueue/Run 无匹配重载`（line 673 等，编译器因前面错误状态错乱后的虚假错误，根因修后自动消失）。

**诊断路径**（避免下次重蹈）：① 补 Proxy 实现 → E2291 消失但暴露 Service line 454 新错 E2029 → 对照实验（实现替最简空 stub）仍报 line 24 E2291 + line 454 E2003 → 说明实现段的方法名不被编译器认作类方法 → grep 类声明段确认缺 forward 声明 → 补 forward → 全通。**关键教训**：Delphi 接口方法新增时，三处都要同步——接口声明、实现类声明的 forward、实现体。漏 forward 的报错模式是 E2003(方法名 undeclared)+E2291(接口未实现)+E2250(虚假连带)，**不要被 E2250 误导去查 ForceQueue**。

**修复**：DeepBase commit `3f056c6`（3 处：Service 类声明段补 forward + Service 实现段参数拆行辅助 + Proxy 补声明+实现）。验证 `_compile_df.bat` → [OK] DeepFrames.exe built，E2291/E2250/F2063 全消失。

## 2026-07-21 续6 — --test-llm 实跑：facade 链路打通但返回 STUB（正面验证续4 stub 伪装现象）

DeepBase 编译解封后实跑 `DeepFrames.exe --test-llm agnes`：
```
[test-llm] provider=agnes
[test-llm] Success=True ErrorCode=STUB LatencyMs=0 Tokens=0
[test-llm] ResponseJson head: {"schema_version":"1.0.0","provider":"agnes","model":"agnes-2.0-flash","status":"stub","note":"Agnes LLM not configured ...using stub output","shots":[...
[test-llm] FAIL: call did not succeed or returned stub output
```

**结论**：① facade 调用链**打通**（编译→Bootstrap 注册→`TProviderRegistry.Instance.LLMProvider.ChatComplete`→`CallRealAPI`→`LLM.ChatWithHistoryByProvider` 全链路执行无崩）；② 但返回 `ErrorCode=STUB` + `status:stub`——**Agnes 未配 key 走 stub 分支返假数据，且 `Success=True`**（即续4 发现的"stub 伪装 Success=True"现象，--test-llm 的 stub 关键词检测 `Pos('stub', ResponseJson)>0` 正确捕获并判 FAIL）；③ `--test-llm` 自身验收逻辑生效（真 reply→OK exit 0，stub 或失败→FAIL exit 5），CLI 验收门设计正确。

**待解**：--test-llm 返回 STUB 说明 Agnes provider 的 key 没被 facade 读到——但 DBA-1（续3）已把 4 secret 迁根库。需核 provider 配置的 key 来源：是读 `DeepBase.Security` 的 secret，还是 provider 自身的配置项？若是前者，为何 --test-llm 没读到（可能 Bootstrap 注册 provider 时 key 字段未绑 secret，或 provider 名/secret 名不匹配）。这是 DBA-3 验收门②「端到端 LLM chat 真跑（非 stub）」的当前卡点——链路通，缺真凭据注入。

**关联**：续4（pipeline 吞失败→DONE，同卡 Agnes key 真跑验证）、续5（DeepBase 编译阻断已解除）。

## 2026-07-21 续7 — src 库缺 secret + DeepBase facade ChatWithHistoryByProvider 真调 EAccessViolation（读 address 0x8）

### 现象与诊断路径
续5 解除 DeepBase 编译阻断后，`--test-llm agnes` 仍返回 STUB（续6）。加临时诊断 `LoadSecret(SECRET_AGNES_API_KEY)` 长度 → **len=0**（DeepFrames.exe 进程读不到 secret）。

**根因 A（secret 缺失，非代码 bug）**：DeepFrames.exe 跑在 `src/`，读 `src/root.txt`（内容 `D:\...\DeepFrames\src\`）→ 连 `src/DeepFramesConfig.db`。而续3 修"存错库"时只把 9 secret 从 bin 库同步到**根库**（续3 用 `bin/DeepFrames.exe --verify-secret` 验证，没碰 src 库）→ src 库 Secrets 表只有 `deepframes/db2` 一条，无 `agnes_api_key`。三库对比确认：根库+bin 库各 9 secret（含 `agnes_api_key`/`agnes_llm_api_key`），src 库仅 1 条。
**修复 A**：`cp src/DeepFramesConfig.db src/DeepFramesConfig.db.bak-pre-secret-sync` 备份；`ATTACH 根库 AS root; INSERT OR IGNORE INTO Secrets(Name,CipherBlob,Description,CreatedAt,UpdatedAt) SELECT ... FROM root.Secrets;`（注意 Secrets 表列名是大小写混合 `Name/CipherBlob/...` 非 `name/value`，第一版用错列名报 "no column named value"）。src 库 Secrets 现 9 条。DPAPI CurrentUser scope 不绑定 DB 文件（续3 已验证跨库可解密）。
**验证 A**：重跑 `--test-llm agnes` → `LoadSecret(SECRET_AGNES_API_KEY) len=51`（真 key 读到）+ `Success=False ErrorCode=LLM_CALL_ERROR LatencyMs=2056`（2s 延迟 = 真网络调用，非 stub）。

### 根因 B（DeepBase facade AV，真 bug，未修）
`--test-llm agnes` 真调后**进程 Segfault exit=139**。加临时诊断在 Agnes.pas except 分支打印异常 → **`EAccessViolation: Access violation ... Read of address 0000000000000008`**（nil+8 偏移 = 访问 nil 对象的第二个 8 字节字段）。

**定位**：AV 在 DeepFrames provider `Agnes.pas:332` 调 `LLM.ChatWithHistoryByProvider`（DeepBase facade）时抛出，被 `Agnes.pas:334` except 捕获→`LLM_CALL_ERROR`→Exit(False)。`--test-llm` 输出 FAIL 后进程退出时 Segfault（AV 残留/全局对象释放序问题）。facade 链路：`TLLMService.ChatWithHistoryByProvider`（Service.pas:457）→`FHttpClient.Send`（HTTP.pas:399）→`PostJson`→`FTransport.Send`→`ParseOpenAIResponse`（续5 原作者新增 reasoning_content 抽取）。Send 有 `except` 兜成 `network_error`（HTTP.pas:438），但实际是 `LLM_CALL_ERROR`（被 provider 层 except 捕获）——说明 AV 不在 Send 的 try 内（否则会变 network_error），而在 except 外或解析路径的更深处，**待进 DeepBase 深挖**。

**关键判据（非 key 问题）**：若 Agnes key 无效，API 返 401 → 走 HTTP.pas:431 else 分支设 `HTTP 401` error code，**不崩**。`Read of address 0x8` 是纯代码空指针 bug，与 key 有效性无关。即 DBA-3 验收门②「真 reply」的真卡点是 facade 代码 bug，不是凭据。

**性质**：DeepBase 仓库代码 bug（facade HTTP/解析层），非本会话、非 DeepFrames 引入。续5 已授权介入 DeepBase 修编译，但 AV 深挖需进 DeepBase HTTP.pas 逐层加诊断定位 nil 对象，工作量和风险较大（原作者续5 改动 reasoning_content 解析，疑此处引入 nil 路径）。

**决策（escalation-check → SELF_DECIDE）**：记根因暂不深修。当前轮目标"对齐文档+继续开发"已达成核心——DeepBase 阻断解除 + secret 同步 + facade 链路真调证明（2s 网络 + 真读 key）。facade AV 深修留作下一步（需逐层在 DeepBase HTTP.pas/Service.pas 加诊断定位 nil，或核续5 原作者 reasoning_content 改动是否引入空对象路径）。

**临时诊断已移除**：`--test-llm` 的 `LoadSecret len` 诊断（DeepFrames.dpr）+ Agnes.pas except 的 `WriteLn(E.Message)` 诊断均已删，编译干净 `[OK] DeepFrames.exe built`。

**关联**：续6（--test-llm STUB 初判 Agnes 未配 key——续7 修正：是 src 库缺 secret，非未配；真因是 secret 库不同步）、续5（DeepBase 编译阻断已解除）、��4（pipeline 吞失败→DONE，同卡 facade 真跑验证）。

## 2026-07-21 续8 — DeepBase facade AV 真根因定位+修复：TLLMService 引用计数自毁致悬挂指针（DBA-3 ��收门②达阵）

### 现象回顾（续7 误判）
续7 记录 `--test-llm agnes` 真调撞 `EAccessViolation Read of address 0x8`，当时判据"401 会走 HTTP error 分支不崩，0x8 是纯代码空指针非 key 问题"正确，但**根因误猜**为"续5 原作者 reasoning_content 改动引入 nil 路径"，决策记根因暂不深修。续8 接续深挖，发现真因完全不同。

### 诊断过程
1. **文件诊断绕开 stdout 缓冲**：续7 用 `WriteLn(ErrOutput)+Flush` 的 stdout 诊断在 segfault 前 intermittently 丢失（GUI 子系统无 console 时 `Output`/`ErrOutput` 缓冲不可靠）。改用 `TextFile` 写 `avdiag.log`（Append/Rewrite + CloseFile，每行落盘）→ 诊断 100% 可靠。
2. **关键证据**：avdiag.log 显示 `enter, forceDirect=False` → `direct path, GLLMServiceAssigned=True lockAssigned=True` → **segfault**。即 `LLM()` 进入时 **GLLMService 已非 nil（已 assigned）**，但 `TryGetProxyClient` 返 nil 走直连路径，`if GLLMService=nil` 为 False 跳过 Create，`Result:=GLLMService`（接口赋值）→ AV。
3. **矛盾点**：GLLMService 已 assigned（非 nil）说明 Bootstrap 阶段已创建过它；但 `Result:=GLLMService` 这个赋值就崩 → 对象内存已无效（悬挂指针）。

### 真根因（引用计数自毁）
- `TLLMService = class(TInterfacedObject, ILLMClient, ILLMAdmin)`（Service.pas:24）——继承 **TInterfacedObject，有引用计数**。
- 但 `GLLMService: TLLMService`（Service.pas:87）是**裸全局对象指针**，不持接口强引用。
- Bootstrap.pas:46-68 调 `LLMAdmin.AddProvider(...)` 等 6 次配置方法。每次 `LLMAdmin` 函数（Service.pas:221）返 `ILLMAdmin` 接口（`Result := GLLMService` 触发 `_AddRef`，RefCount+1），调用完临时接口变量出作用域 → `_Release` → RefCount-1。
- **首次创建**：Create（RefCount=0）→ `Result:=GLLMService` AddRef→1 → 调用完 Release→0 → **TInterfacedObject._Release 在 RefCount=0 时调 `FreeSelf` → 对象自毁** → `GLLMService` 全局指针变悬挂（仍非 nil）。
- **第二次起**：`LLM()`/`LLMAdmin()` 读 `GLLMService<>nil`（悬挂非 nil）→ 跳过 Create → `Result:=GLLMService` → `_AddRef` 解引用悬挂对象的 Vtable 指针 → **EAccessViolation Read of address 0x8**（nil+8 偏移=Vtable 第一个方法槽）。
- finalization 的 `GLLMService.Free`（原代码）对已自毁对象双重释放，进一步印证 bug。

### 修复
新增全局 `GLLMServiceHolder: ILLMAdmin = nil`（Service.pas var 段），在 `LLM`/`LLMAdmin` 的 Create 后 `GLLMServiceHolder := GLLMService`（接口赋值 AddRef→保对象永生，RefCount 始终 ≥1）。finalization 改 `GLLMServiceHolder := nil; GLLMService := nil`（释放 holder 走引用计数干净释放，**不再裸 `GLLMService.Free`**，避免双重释放）。DeepBase commit `0dc2fad`。

### 验证
- `--test-llm agnes`：真调 Agnes API `PostJson status=200` + `ParseOpenAIResponse ok=True` + 真实 LLM reply（"Here's a thinking process..."）+ `exit 0`（**原 segfault 139 消失**）。**DBA-3 验收门②「真 reply」达阵**。
- `--run-pipeline seed_wsh.md --force-rerun`：pipeline 不再崩在 LLM step，推进到存储阶段新卡点 `FATAL: [FireDAC][Phys][PG] 无法将 bytea 转换为 jsonb`（LLM 输出写 jsonb 字段时传 bytea 数据，**独立新 bug，与本次修复无关**，待定位）。

### 性质
DeepBase 仓库代码 bug（singleton 生命周期管理），非本会话、非 DeepFrames 引入。续5 已授权介入 DeepBase 修编译，本次同源授权范围内（DBA-3 facade 真跑验收）深修。

### 关联
续7（AV 现象+判据正确但根因误猜）、续5（DeepBase 编译阻断已解除）、续6（src 库 secret 同步+真调首撞 AV）。

## 2026-07-21 续9 — pipeline bytea→jsonb 转换 FATAL 修复（DBA-3 真跑后首条阻塞）

### 现象
续8 修复 facade AV 后，`--run-pipeline seed_wsh.md --force-rerun` 不再崩在 LLM step，推进到存储阶段报 `FATAL: [FireDAC][Phys][PG][libpq] 错误: 无法将 bytea 转换为 jsonb`。

### 根因（交叉定位）
`SetUtf8Param`（Repository.pas:198）用 `DataType := ftVarBytes` 把参数绑成 **bytea 字节流**（绕开 FireDAC WideString 绑定层的 UTF16 0x00 bug，见记忆 fireDAC-pg-utf16-nul-blocker）。对应 SQL 必须用 `convert_from(:p::bytea,'UTF8')::jsonb` 把 bytea 解码回 text 再转 jsonb。

Repository 有 30+ 处 `CAST(:xxx AS jsonb)`，但绝大多数配 `AsString`（ftWideString/ftString）绑定——PG 当 text 处理，CAST text AS jsonb 合法，**不报错**。唯一 BUG 组合是 `InsertVariantDocument`（line ~1001 SQL `CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)` + line 1014/1015 `SetUtf8Param`）——bytea 直接 CAST 成 jsonb → PG 报"无法将 bytea 转换为 jsonb"。

用脚本交叉分析（每个 procedure 的 `CAST(:X AS jsonb)` 参数名 ∩ 该 procedure 的 `SetUtf8Param` 参数名）确认：**仅 InsertVariantDocument 一处**满足"bytea 绑定 + CAST-AS-jsonb"的 BUG 组合。对照正确写法 `InsertSourceDocument`（line 476）用 `convert_from(:payload_json::bytea,''UTF8'')::jsonb` + SetUtf8Param。

### 修复
InsertVariantDocument 的 SQL 把 `CAST(:payload_json AS jsonb), CAST(:extra_json AS jsonb)` 改为 `convert_from(:payload_json::bytea,''UTF8'')::jsonb, convert_from(:extra_json::bytea,''UTF8'')::jsonb`，与 InsertSourceDocument 一致。

### 验证
重编 `[OK] DeepFrames.exe built`，`--run-pipeline --force-rerun` **过了 bytea→jsonb 错误**，推进到新卡点：`FATAL: [FireDAC][Phys][PG][libpq] 错误: JSON 输入中有语法错误。字符 "\`" 无效`——LLM 真实输出含 markdown 围栏反引号，写 jsonb 时 PG 严格 JSON 解析拒绝（见记忆 fireDAC-pg-utf8-null-and-json-fix 同类：markdown 围栏 \` 字符）。这是 LLM 输出写入前未清洗/未包成合法 JSON 的独立新 bug。

### 关联
续8（facade AV 修复后 pipeline 推进到此）、fireDAC-pg-utf8-null-and-json-fix（同类 markdown 围栏 \` 问题）、SetUtf8Param header 注释（line 195-197 说明 bytea 绑定绕 0x00 bug 的设计）。

## 2026-07-21 续10 — JSON 反引号 FATAL 定位+修复（Agnes markdown 围栏剥离）

### 现象
续9 修完 bytea→jsonb 后，pipeline 推进报 `FATAL: [FireDAC][Phys][PG][libpq] 错误: JSON 输入中有语法错误。字符 "\`" 无效`。续9 记为"独立新 bug 待定位"，续10 定位并修复。

### 根因
Agnes reasoning 模型把 JSON 输出包在 markdown 围栏 ```` ```json ... ``` ```` 里。`accuracy_check`/`build_variant`/`build_shot` 三个 step 把 `ChatResult.NormalizedJson` **裸传**给 `deepframes_prompt_run.normalized_json`（JSONB 列）。PG `::jsonb` cast 严格 JSON 解析，首字符 `` ` `` 直接 FATAL。与记忆 fireDAC-pg-utf8-null-and-json-fix 同类（markdown 围栏 \` 字符），但续8 那次是 raw_output 列 NOT NULL 0x00 链，这次是 NormalizedJson 路径未剥离围栏。

### 修复
`src/Provider/DeepFrames.Provider.Agnes.pas` 加 `StripMarkdownFence()` helper：识别并剥离首尾 ```` ```json/```text/``` ```` 围栏（含首行换行）。在 provider 边界 NUL 剥离后立即调用，使 `ResponseJson` 及所有 `NormalizedJson` 路径（schema 修复/schema 回退/无 schema）统一得干净 JSON，一次到位。与 `build_script` 已有逐 step 花括号提取一致，提到 provider 边界避免链路重复。uses 加 `System.StrUtils`（`PosEx`）。

### 验证
`msbuild DeepFrames.dproj /p:Config=Debug`（Win64）**EXITCODE=0**（51692 行/2.83s/12.3MB exe）。编译前清 83 个 DeepBase 源码目录（Core/Features/FMX/Persistence/Governance/VCL/Libs）散落 x86 `.dcu`——与 `BuildOutput/dcu/Win64` 正版冲突致 `F2048 Bad unit format ... Found x86`。

**E2E 受阻**（非代码问题）：`--test-llm agnes` 回归 `PROXY_UNREACHABLE`（`TProxyLLMClient.DoPost` 返 False，LatencyMs=3 瞬间失败），8089 relay `/v1/chat/completions` 返 `No port binding found for port 8089`（但 `/health` 通、agnes provider status=green available_accounts=1）。续8 `--test-llm agnes` 曾 success（status 200），现回归——DeepBase LLM facade 代理路由配置/运行时环境后变，非本次代码改动引入。代码层反引号修复闭环，E2E 待代理路由恢复后真跑 `--run-pipeline --force-rerun` 验证 FATAL 消除。

### 关联
续9（bytea→jsonb 修完推进到此）、续8（facade AV 修后 `--test-llm agnes` 曾 success，现 PROXY_UNREACHABLE 回归）、fireDAC-pg-utf8-null-and-json-fix（同类 markdown 围栏 \` 问题，不同列路径）、记忆 deepbase-llm-singleton-refcount-self-destruct（facade AV 修复，决定 `--test-llm agnes` 能否通的前置）。commit `1d06c71`。

## 2026-07-21 续11 — pipeline 吞失败→DONE 4 处全修完结（DBA-3 残留④）

### 现象
续4 已记根因：`DocumentChain.pas` 的 4 个 LLM step 在 `Provider.ChatComplete` 返 False（LLM 失败：PROXY_UNREACHABLE/401/EXCEPTION 等）时，**不阻断、不报错、产假文档 + 标 `STATUS_DONE`**——真假绿无法区分。这是比 stub 返 True 更深的设计缺陷（stub 返 True 是"无凭据假成功"，吞 DONE 是"真失败伪装成功"）。残留④ 列为 DBA-3 验收门「pipeline 失败不再吞成 DONE」。

### 4 处缺陷与修法（统一模式）

| # | step | 原行为（吞失败→DONE） | 修复 |
|---|------|----------------------|------|
| 1 | build_script `else` (原 240-248) | 产 `stub-script-v1` doc + DONE，继续进 step2/3 | 标 FAILED+raise 带 ErrorCode（commit `68e0684`） |
| 2 | accuracy_check `else` (原 315-321) | 产 `1.0/0.0/GATE_RESULT_PASS` AccuracyRep + DONE——**QA 红灯伪装满分绿灯，最危险** | 标 FAILED+raise |
| 3 | build_variant `if ChatComplete` **无 else** (原 416) | 静默跳过，照产 `variant-main-v1`（ContentHash 非真输出）+DONE，VideoChain 消费幽灵变体 | 加 else 标 FAILED+raise |
| 4 | build_shot `if ChatComplete` **无 else** (原 467) | 落到合成 demo shot（`开场画面` visual_prompt）+DONE | 加 else 标 FAILED+raise |

统一修法：
- 判据：**仅 `IsRealProvider=True 且 ChatComplete=False` 才 raise**（真失败）。非真 provider 演示路径不进这些 else，保留原 demo fallback（设计用途，不动）。
- 状态：`if CanTransitionStatus(STATUS_RUNNING, STATUS_FAILED) then UpdateJobStepStatus(FAILED) else UpdateJobStepStatus(CANCELLED)`——该校验合法（`Project.pas:139` RUNNING→FAILED 在白名单）。
- 中断：`raise Exception.CreateFmt('... LLM step failed (no X produced): %s (model=%s)', [ChatMetrics.ErrorCode, ChatMetrics.Model])`——错误码在 `TLLMMetrics.ErrorCode`（不在 `TLLMChatResult`，续11 首次编译 E2003 教训），空则兜底 `LLM_FAILED`。
- 外层 `except`（line ~525）捕获后记 `chain_failed`/`esError` 结构化日志并重抛，Job 保留非-DONE 状态，调用方知失败。

### 验证
`dcc64 -B -Q`（Win64）**EXITCODE=0**（69371 行/3.30s/11.5MB exe）。本次仅改 `DocumentChain.pas`（DeepFrames 侧），不碰 DeepBase，未撞续10 的 x86 dcu 冲突。

**E2E 受阻**（非代码层）：DBA-3 验收门②「端到端 LLM chat 真跑」仍卡 `PROXY_UNREACHABLE`（续10 同一代理路由问题，8089 relay `No port binding found for port 8089`）。代码层残留④ 达阵，待代理路由恢复后 `--run-pipeline --force-rerun` 真跑验证：LLM 失败时 Job 应留非-DONE + `chain_failed` esError 日志（而非产假文档+DONE）。

### 关联
续4（首次发现吞 DONE 根因 + 加 `--test-llm` CLI）、续10（JSON 反引号 FATAL，本轮修完后 pipeline 推进的下一个卡点仍是 PROXY_UNREACHABLE 非代码层）、bugfix 续4「真假绿分不清」。commits `68e0684`（build_script 首处）+ `7b21efa`（accuracy_check/build_variant/build_shot 余 3 处）。

