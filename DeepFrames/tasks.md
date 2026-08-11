# DeepFrames Tasks

## 当前状态 (2026-07-21)

Delphi AI 视频生成 CLI。pipeline 已端到端跑通产真实 MP4（音画+烧录字幕对齐），但**仍不可商用**——07-13~07-15 解决了"生产视频无字幕无声音"核心可用性问题并重建 git 历史清空明文 key；07-21 推进 DBA 线：**密钥迁 `DeepBase.Security` 验收通过（DBA-1，07-21续3——4 secret 全 LoadSecret 往返成功 + 删明文残留 + 修存错库真因）**、诊断 WriteLn 迁 `DeepBase.Logging` 首两文件完成（DBA-5/B38）、**LLM 链走 facade 主体完成（DBA-3，LLM 路径已接 facade + Bootstrap 注册 agnes/gemini + 编译过，07-21续4 发现 pipeline 吞失败→DONE 真根因 + 加 `--test-llm` CLI）**。**07-21续5 DeepBase 编译阻断已解除**（根因=TLLMService 类声明漏 `ChatWithHistoryByProvider` forward 声明，补齐后 DeepFrames.exe built；DeepBase commit `3f056c6`）；`--test-llm agnes` 实跑 facade 链路打通（返回 STUB，因 Agnes 未配 key，--test-llm 正确判 FAIL）。架构基线 facade 接入仍在补齐中。**07-21续6**：发现 src 库缺 secret（续3 同步了根+bin 库漏了 src 库）→ 同步 9 secret 到 src 库 → `--test-llm agnes` 真调（LoadSecret len=51 真读 key + 2s 网络延迟证明 facade 真发请求）→ 撞 DeepBase facade **EAccessViolation 读 address 0x8**（nil+8 偏移，空对象字段访问）→ 详见续6/续7。**07-21续8 DeepBase facade AV 真根因找到并修复**：非续7 猜的"reasoning_content 改动引入 nil"，真因是 **`TLLMService` 继承 `TInterfacedObject`（有引用计数）但 `GLLMService` 是裸全局对象指针**——Bootstrap 调 `LLMAdmin.AddProvider` 等配置方法时，每次返回的临时 `ILLMAdmin` 接口 `Release` 使 RefCount 归 0 → 对象 `FreeSelf` → `GLLMService` 变悬挂指针（仍非 nil）→ 下次 `LLM()` 读 `GLLMService<>nil` 跳过 Create，`Result:=GLLMService` 触发 `_AddRef` 解引用悬挂 Vtable → AV/segfault 139。修：新增 `GLLMServiceHolder: ILLMAdmin` 强接口引用，Create 后持一份 AddRef 保对象永生，finalization 释放 holder 走引用计数干净释放（不再裸 Free）。DeepBase commit `0dc2fad`。**验证**：`--test-llm agnes` 真调 Agnes API `status=200` + 真实 LLM reply + `exit 0`（原 segfault 139 消失）→ **DBA-3 验收门②「真 reply」达阵**；`--run-pipeline --force-rerun` 推进到新卡点（bytea→jsonb 转换 FATAL，独立 bug，详见阻断⑤）。**07-21续9 bytea→jsonb FATAL 已修**：根因=InsertVariantDocument 的 SQL 用 `CAST(:payload_json AS jsonb)` + `SetUtf8Param`（ftVarBytes/bytea 绑定），bytea 直接 CAST 成 jsonb → PG 报错；脚本交叉定位确认全仓库仅此一处满足"bytea 绑定+CAST-AS-jsonb"BUG 组合（其余 30+ 处 CAST 配 AsString 合法）。改为 `convert_from(...::bytea,'UTF8')::jsonb`（与 InsertSourceDocument 一致）。pipeline **过了此错**，推进到新卡点：`JSON 输入语法错误，字符 "\`" 无效`（LLM 真实输出含 markdown 围栏反引号，写 jsonb 前未清洗，独立新 bug）。**07-21续10 反引号 FATAL 已修**：根因=Agnes reasoning 模型把 JSON 输出包在 ```` ```json ```` 围栏里，accuracy_check/build_variant/build_shot 三处裸传 `ChatResult.NormalizedJson` 给 `deepframes_prompt_run.normalized_json`（JSONB），首字符 `` ` `` 使 `::jsonb` cast FATAL。修：Agnes.pas 加 `StripMarkdownFence()` helper，在 provider 边界 NUL 剥离后立即调用——ResponseJson 及所有 NormalizedJson 路径（schema 修复/回退/无 schema）统一得干净 JSON，一次到位（与 build_script 已有逐 step 花括号提取一致）。加 `System.StrUtils`（PosEx）。编译 EXITCODE=0（51692 行/2.83s）；清 83 个 DeepBase 源码目录散落 x86 .dcu（与 Win64 冲突致 F2048 bad unit format）。**E2E 验证受阻**：`--test-llm agnes` 回归 `PROXY_UNREACHABLE`（8089 relay 路由 `No port binding found for port 8089`）——运行时环境/facade 代理路由配置问题，非本次代码改动引入（续8 曾 success，环境后变）；代码层修复闭环，E2E 待代理路由恢复。**07-21续11 DBA-3 残留④「pipeline 吞失败→DONE」4 处全修完结**：续4 发现的根因（`DocumentChain` 的 4 个 LLM step 在 `ChatComplete=False` 时仍产假文档+`STATUS_DONE`，真假绿无法区分），本轮一次性修完 4 处同模式缺陷——① build_script else（原产 `stub-script-v1`+DONE，commit `68e0684`）② accuracy_check else（原产 `1.0/0.0/PASS`+DONE，QA 红灯伪装满分绿灯，最危险）③ build_variant `if ChatComplete` 无 else（原静默产 `variant-main-v1` 假变体+DONE，VideoChain 消费幽灵变体）④ build_shot `if ChatComplete` 无 else（原落到合成 demo shot `开场画面`+DONE）。统一修法：`IsRealProvider=True 且 ChatComplete=False` 时标 `STATUS_FAILED`（经 `CanTransitionStatus(RUNNING→FAILED)` 校验，失败回退 CANCELLED）+ `raise Exception.CreateFmt` 带 `ChatMetrics.ErrorCode`+Model，外层 except 记 `chain_failed`/esError 结构化日志并重抛，Job 留非-DONE。非真 provider 演示路径不进这些 else，保留原 demo fallback（设计用途，不动）。编译 EXITCODE=0（69371 行/3.30s/11.5MB exe）。**残留④ 验收门「pipeline 失败不再吞成 DONE」代码层达阵**——但 DBA-3 验收门②「端到端 LLM chat 真跑」仍卡 `PROXY_UNREACHABLE`（E2E 待代理路由恢复，非代码层）。**07-21续12 残留③ stub 收敛已清**：`Provider.Types` 加 `STUB_STATUS_MARKER`/`STUB_PROMPT_SUFFIX`/`STUB_ASSET_PREFIX` 三常量替换散落 'stub' 字面量（commit `cb7eadd`，0 Error 编译），纯结构性重构不改运行时行为。**07-21续13 DBA-3 残留①「provider 文件 >600 行」已过**：Agnes 1271/Gemini 1287/StepFun 1394 三单体 provider 按 H3<600 铁律全拆——Agnes→Shared/LLM/Image/Video（commit `6a35cf7`），Gemini→Shared/LLM/TTS/ASR（commit `305953b`），StepFun→Shared/LLM/TTS/ASR/Image（commit `9817158`），原 provider.pas 改 forwarding 壳（类型别名 re-export），Registry.pas 零修改。共享段抽 .Shared 子 unit（Agnes 共享 helper 函数、Gemini/StepFun 共享 const）。`--test-llm` 拆分后真 reply（`你好`，failover 链路）验证 facade 链路完好，行为零变化。H3 全过：最大 StepFun.ASR 593 行 <600。**至此 DBA-3 残留①~④ 仅剩②（Gemini 服务端 thinking/schema 丢，需实测）+ 验收门② E2E 仍卡 PROXY_UNREACHABLE**。**07-21续14 E2E 解锁推进到根因**：启动 `AssayerProxy.exe --port 8089`（8089 LISTENING、`/health`=healthy、agnes provider green available_accounts=1 model_count=2，16 provider 全 enabled），但直 curl `/v1/chat/completions` 仍返 `route_conflict/no_port_binding`。**真根因 = Assayer 端口绑定表无 8089**：AssayerProxy chat 走 `DM.ResolvePortRoute(port)` 路由检查，已配端口绑定 6060(deepseek,red 402)/6062(fccy gpt-5.5,green)/6064(stepfun step-3.7-flash,green)/6066(disabled)/6068(xunfei-coding,green)/6070/6072/6074——**8089 无绑定**（8089 是 Assayer 管理/health 端口，非业务 chat 端口）。DeepBase facade `TProxyConfig.Init` 默认 Port=8089 → facade 连 8089 → ResolvePortRoute 返 nil → no_port_binding → facade 解读为 PROXY_UNREACHABLE。**agnes provider 存在且 enabled 但未绑到任何业务端口**。**架构对齐卡点（已上交老板）**：DeepBase facade 单端口（8089）vs Assayer 多业务端口（6060+），方案 A（给 8089 绑 agnes，risky 可能破坏管理端口）vs 方案 B（改 DeepBase facade 支持 per-provider 端口或改默认端口连 6064）——灰区无客观判据，escalation-check=IRREVERSIBLE/架构 should_escalate=true。**07-21续15 DBA-4 异步编排完成（commit `2dca985`）**：与续14 代理卡点正交的纯代码层任务独立推进。`App.Services` 新增 `RunFullPipelineAsync`/`GetPipelineStatus`/`RunFullPipelineSync`，DeepFrames 自有 `TWorkerQueue` 单例 + per-JobId 回调表 + 终态结果表（in-memory，故意不用 DependsOn 链——内存队列丢 job 后 DependsOn 永久卡，与续9/13 per-phase DB 状态驱动的断点续传正交）；CLI `--run-pipeline` 改 enqueue+poll；GUI 新增 `CMD_FULL_PIPELINE_RUN` 命令 + `TThread.Queue` 回主线程。验收① UI 不阻塞→✅；验收② 杀进程重跑续→设计满足（无 DependsOn + phase 级 FindJobByLogicalKey 短路），E2E 真跑待续14 架构方案。**DBA 线状态：DBA-1/4/5/7 已过，DBA-3 残留②+验收② E2E、DBA-6 待办**。**07-21续16 D7 商用度子项落地**（commit `7dd9b1b`）：ffmpeg/ffprobe 路径探测抽到 `Shared.Tools.TFFmpegLocator` 唯一真相源（DB1 `CONFIG_FFMPEG_DIR` 优先 + PATH 探测），AudioProcessor/Baidu/VideoRenderEngine 全转发，消除 Baidu 退化版忽略配置 bug + VideoRenderEngine 死路径硬编码；`force_video_regenerate.txt` 调试后门 gate `{$IFDEF DEBUG}`（Release 编译期消失）。标题卡副文案残留留品牌批次。

**07-21 核查**（上接 07-15）：
- ✅ 已真修：ffmpeg/ffprobe 混用（B1）、webhook 空串（B2）、Repository 无事务（P0-A）、StepFun 双释放（B4）、CheckSourceMetadata 接入（P0-E）、CI 已建、真集成测试缺凭据 SKIP 非假绿、GUI 进程 `WriteLn`→`EInOutError` 崩溃（B38）。
- ✅ 已处置：明文 key 进 git 历史——单人单机无远端场景，已删 `.git` 重建（commit `832fe98` 干净基线），旧历史含明文 key 彻底消失。密钥轮换对此场景不再必要。
- 🟡 实质完成待验收：① **DBA-1 密钥迁 Security——验收通过**（07-21续3，4 secret 全 LoadSecret 往返成功 + 删明文残留 + 修存错库真因）。② DBA-5 诊断迁 Logging——**实质完成**（App.Services/AudioChain/ArtifactOSBridge 全迁，`grep WriteLn src/` 非注释残留=0；DeepFrames.dpr 的 37 处 WriteLn 是 CLI 子命令 stdout 用户输出，设计正确非诊断，不迁）。③ DBA-7 Baidu `SplitOnSilence` 静音分块——代码完成（silencedetect+切片+chunk 级时间戳），端到端 ASR 真跑待凭据。④ **DBA-3 LLM 走 facade**——Agnes/Gemini `CallRealAPI` 重写为薄封装调 `LLM.ChatWithHistoryByProvider`，Bootstrap 注册两 provider，facade 补 reasoning_content 回退，编译过（commit `d90a9d9`）；**残留**：provider 文件 >600 行待拆、Gemini thinking/schema 服务端强制丢、~~stub 未集中~~（**续12 已清**，`cb7eadd`）、端到端真跑待凭据；**07-21续4 新增**——发现 pipeline 吞失败→DONE 真根因（DocumentChain else 分支产 stub doc+STATUS_DONE，详见 bugfix 07-21续4）+ 已加 `--test-llm` CLI 待 DeepBase 解封编译验证 + **DeepBase 编译阻断 07-21续5 已解除**（Service 类声明漏 forward 声明，DeepBase `3f056c6` 修；`--test-llm agnes` 实跑 facade 链路打通返回 STUB，详见阻断项）。**07-21续11 残留④ 已修完结**——DocumentChain 4 处吞失败→DONE 全改 STATUS_FAILED+raise（build_script `68e0684` + accuracy_check/build_variant/build_shot `7b21efa`），代码层达阵，唯余 E2E 待代理路由恢复。
- 🔴 仍阻断：① ~~DeepBase 工作树未提交 LLM 重构阻断编译~~ **已解除（07-21续5）**——根因是 `TLLMService` 类声明段漏 `ChatWithHistoryByProvider` forward 声明（原作者 Client.pas 加接口方法+Service 实现+Proxy 声明，独漏类 forward 声明→E2003/E2291/E2250 连锁）；补 forward + Proxy 实现后 DeepFrames.exe built（DeepBase commit `3f056c6`）。② DBA-4 未动（编排走 ExecuteAsync）；③ facade 接入仍稀疏（LLM 已接 3 provider，Logging 仅 2 文件，Config/Scheduler 0 处）；④ 测试仍以 Fake provider 为主，"全绿"掩盖真链路覆盖不足；⑤ **~~DBA-3 真跑卡在 DeepBase facade AV（续7，EAccessViolation 0x8）~~ 已修复（07-21续8）**——根因=TLLMService 继承 TInterfacedObject 但 GLLMService 裸指针，Bootstrap 临时 ILLMAdmin 接口 Release 致 RefCount 0→FreeSelf→悬挂指针→下次 LLM() AV。加 GLLMServiceHolder 强引用保活，DeepBase `0dc2fad`；`--test-llm agnes` 真返 reply+exit 0，DBA-3 验收门②达阵。**pipeline `--run-pipeline --force-rerun` 推进到新卡点**：~~bytea→jsonb 转换 FATAL~~（续9 已修：InsertVariantDocument SQL 用 `convert_from(...::bytea,'UTF8')::jsonb` 替代 `CAST AS jsonb`，唯一 bytea 绑定+CAST 组合）；~~`FATAL: JSON 输入语法错误，字符 "\`" 无效`~~（续10 已修：Agnes.pas `StripMarkdownFence()` 在 provider 边界剥离 markdown 围栏，ResponseJson/NormalizedJson 统一干净；commit `1d06c71`；编译 EXITCODE=0）。**当前卡点**：`--test-llm agnes` 回归 `PROXY_UNREACHABLE`（8089 relay 返 `No port binding found for port 8089`）——DeepBase LLM facade 代理路由配置/运行时环境问题（续8 曾 success 后回归，非代码改动引入），代码层反引号修复闭环，E2E 待代理路由恢复。详见 bugfix 07-21续8/续9/续10。

**修正方向**：补接 DeepBase facade，不自建。详见 `docs/review-report-2026-07-14-架构基线偏离与DeepBase接入.md`。DBA 线仍为最高工程优先级，先于一切功能开发。已完成项详见 `history.md`，已修 bug 详见 `bugfix.md`。

---

## 小红书单平台适配专项（2026-07-11 新增）

> 目标：把 DeepFrames 生产链路收敛到小红书单平台，产出首个可发布候选包。优先级仅次于 DBA 线（DBA 线是架构前置，XHS 是业务落地）。

### XHS-P0：首个可发布候选包（最高优先级）
- [ ] **XHS-P0.1 建立 `xiaohongshu_wsh_v1` 正式生产配方**
- [ ] **XHS-P0.2 新增 WSH 内容原子输入契约**
- [ ] **XHS-P0.3 增加小红书专属合规硬门禁**
- [ ] **XHS-P0.4 AI生成内容标识**
- [ ] **XHS-P0.5 候选包最小交付物**
- [ ] **XHS-P0.6 强制人工发布边界**

### XHS-P1：内容生产效率与防批量风险
- [ ] **XHS-P1.1 单批上限**
- [ ] **XHS-P1.2 同质化检测**
- [ ] **XHS-P1.3 原创与来源证据**
- [ ] **XHS-P1.4 低成本降级模板**
- [ ] **XHS-P1.5 制作耗时统计**
- [ ] **XHS-P1.6 软边界实验元数据**

### XHS-P2：与 ArtifactOS 的发布治理接口
- [ ] **XHS-P2.1 固化 DB3 handoff**
- [ ] **XHS-P2.2 ArtifactOS包兼容**
- [ ] **XHS-P2.3 回传稳定标识**

### XHS-P3：首轮真实验收
- [ ] **XHS-P3.1 GUI端到端生产3条**
- [ ] **XHS-P3.2 人工审阅验收**
- [ ] **XHS-P3.3 新账号手工发布验证**

### XHS专项验收标准
- P0 完成 = 首个候选包可由人工在真实账号发布 1 条合规内容
- P1 完成 = 单批 ≤ 上限、无同质化风险、有原创证据
- P2 完成 = DB3 ↔ ArtifactOS handoff 稳定、回传标识可追溯
- P3 完成 = 3 条内容经人工审阅 + 真实账号发布验证

### 最新运行基线 (2026-06-17, v5)
> 主题参数化完成，7/7 PASS。详见 `history.md` 2026-06-17 段。

---

## 商用就绪度待办（按修复路径排序）

> 07-08 五专家评估 3.8/10，第一阶段 B1-B6、第二阶段 P0-A~P0-I、第三阶段竞态/ProbeCodec 已全部完成（详见 `history.md`）。此处仅列商用前仍未完成项。

### 第三阶段 — High 残项（商用前）
- [ ] **运维 runbook** — 部署/回滚/告警/故障排查手册。结构化日志已接入（DocumentChain），runbook 据此写故障排查路径。
- [ ] **第三方安全审计** — 外部审计，不可自做。商用前必须。

---

## DBA 线 — DeepBase 接入（2026-07-14 新增，最高工程优先级，D 线前置）

> 来源：`docs/review-report-2026-07-14-架构基线偏离与DeepBase接入.md`。实测发现 `src/` 内 `uses DeepBase.*` 业务单元仅 5 文件 9 处，明文 key + 散落 JSON 违反 `docs/01.arch` 铁律，是上一轮"假绿/改配置不生效/真假绿分不清"的结构根因。**原则：补接 DeepBase facade，不自建。** 本线为 D 线前置：D3 的"密钥写 DeepBase.Security 不落明文"正是 DBA-1 的子集；本线未完成前，D2 的"端到端真跑"结论不可信（无统一日志无法区分真假绿）。

- [x] **DBA-1 [P0] 密钥迁入 DeepBase.Security — 验收通过** — 5 个 provider（Agnes/StepFun/Baidu/StepPlan/Persistence 连接）全部改读 `LoadSecret`，源码无 `AssignFile`/明文读取残留；`src/DeepFrames.dpr` Bootstrap 段已落地 `--set-secret`/`--set-secret-file` 写入动词（调 `SaveSecret` 入 DB1 Secrets，DPAPI 加密）+ `--verify-secret` 往返校验（打印长度+首尾掩码，不回显明文）。
  > **07-21 收尾验收通过**：① 删根目录 `_baidukey.txt` 残留 + `bin/` 副本（铁律#2「API Key 不写入文件」最后一处明文消除）；② `--verify-secret` 实跑 4 secret 全 `LoadSecret` 往返成功——agnes len=51（sk- 格式）/gemini len=53（AIza）/baidu 两行 24+32（AppId+SecretKey，head 与已删明文一致证明无凭据丢失）/stepfun len=60；③ 修 secret 存错库真因——运行时读根库但 secret 之前灌进 bin 库（root.txt 指向项目根→ConfigDbPath=根库），已 ATTACH bin 同步 9 行到根库（详见 bugfix 07-21续3）。验收门全过：`grep -r "_baidukey\|agnes_key.txt\|stepfun_key.txt" src/` 为空；4 secret 真往返成功。**残留（非阻断清理项）**：① 三库副本（根/src/bin 各一份 DeepFramesConfig.db）不一致是结构问题，建议后续统一固定单库；② Secrets 表仍含大写死 key（`AGNES_API_KEY`/`STEP_FUN_API_KEY`/`agnes_llm_api_key`，代码只读小写常量无引用）；③ `--verify-secret` 注释标 TEMP 待验收后删，现验收已过可择机删（保留便于老板存凭据后自检）。
- [x] **DBA-2 [P0] 散落配置迁入 DB1 Settings — 实质完成（原描述误述已修正）** — 原 tasks 写"删 5 个 JSON + 内容写入 DB1 Settings + 代码改读 GetConfig"。**07-21 核查修正**：`grep -rln` 确认 `src/` 内 **0 处代码读这 5 个 JSON**——它们全是历史测试/调试残片（`models.json`=Gemini 官方模型清单本地缓存、`_fccy.json`=一次性 CLI 测试请求体、`tts_test/veo_test/veo1.json`=Gemini API 错误响应 dump），无运行时依赖、无配置真相源价值。故"迁 DB1 Settings / 改读 GetConfig"两步前提不成立（代码本就不读它们），直接删除即可。已删 5 文件。`root.txt`（31 字节，内容仅工作区根路径 `D:\_Progs\02Business\DeepFrames`）经查代码 0 引用——是工作区路径锚点文件非配置，原描述"唯一外部配置文件"为误述，保留。验收：`find . -maxdepth 1 -name "*.json"` → **空**（原要求"仅剩受控产物"，现零文件更干净，**已过**）。
- [~] **DBA-3 [P0] LLM 链走 DeepBase LLM facade — LLM 路径实质完成，文件拆分 + stub 收敛残留** — `Provider.Agnes/StepFun/Gemini.pas` 的 LLM `CallRealAPI` 改为走 `LLM.ChatWithHistoryByProvider(Name, Model, Messages, MaxTokens, Temperature)` facade 调用，消除各自内联 HTTP/retry/解析（Agnes -170 行、Gemini -180 行）。Bootstrap.SeedLLMConfig 注册 `agnes`+`gemini` provider（key 从 `DeepBase.Security` secret 读，OpenAI 兼容格式）。facade HTTP 层补 `reasoning_content` 抽取 + Content 空回退（reasoning-model 安全）。**tier 覆盖陷阱已绕开**：采用方案②——给 `ILLMClient` 加 `ChatWithHistoryByProvider(Name,...)` 重载，按 provider 名直路由而非按 tier，多 provider 并存不互相覆盖（`DeepBase.LLM.Client/Service/HTTP` 三件改，task7 已完成）。验收：`Provider.*.pas` 各文件 < 600 行；LLM stub 在无 key 时返回 False + metrics 标 `STUB`，不再伪装成功。
  - **07-21 实质完成项**：① Agnes `CallRealAPI` 重写为薄封装（`LLM.ChatWithHistoryByProvider(PROVIDER_AGNES, AgnesLLMModel,...)`），保留 NUL 剥离 + 客户端 `TJsonSchemaValidator.Validate` + reasoning 回退；② Gemini `CallRealAPI` 重写为薄封装，走 OpenAI 兼容端点（`generativelanguage.googleapis.com/v1beta/openai`，facade 拼 `/chat/completions`）；③ Bootstrap 注册两 provider；④ facade `ParseOpenAIResponse` 抽 `reasoning_content`/`reasoning` 并在 Content 空时回退；⑤ dcc64 编译 0 Error（68962 行 3.03s，`[OK] DeepFrames.exe built`），commit `d90a9d9`。
  - **残留（未过验收门）**：① **~~文件行数超标~~ ✅已过（07-21续13）**——Agnes 1271/Gemini 1287/StepFun 1394 三单体按 H3<600 铁律全拆为 Shared/能力子 unit + forwarding 壳，Registry.pas 零修改（commit `6a35cf7`/`305953b`/`9817158`），`--test-llm` 拆分后真 reply 验证 facade 链路完好。② **Gemini 丢服务端强制**——`responseMimeType`+`responseSchema`+`thinkingConfig`(thinkingBudget=0) 不经 OpenAI 兼容 facade 透传，Gemini 2.5 可能因 thinking 耗尽 token→空 content；已记客户端 schema validate 兜底 + 文件内 follow-up 注释，需大 MaxTokens 实测验证。③ **stub 收敛 ✅已完成**（07-21续12，commit `cb7eadd`）：`Provider.Types` 新增 `STUB_STATUS_MARKER`/`STUB_PROMPT_SUFFIX`/`STUB_ASSET_PREFIX` 三常量，替换 Agnes/Gemini/StepFun/Fake 中散落 'stub' status 字段(3处)+' (stub)' prompt 后缀(2处)+stub_ 资产文件名前缀(5处)；Agnes `'(agnes stub)'` 带名标签 + StepFun `output/images/stub/` 目录名语义不同保留。dcc64 -B 编译 0 Error，纯结构性重构不改运行时行为。④ **端到端真跑未做**——需凭据后 GUI/CLI 实跑确认 LLM 链通。**07-21续4 进展**：凭据已就绪（DBA-1 已过，4 secret 在根库），已加 `--test-llm [provider]` CLI（dpr，调 `TProviderRegistry.Instance.LLMProvider.ChatComplete` 打印 Success/ErrorCode/ResponseJson 头 200 字，stub 输出判 FAIL）直击 DBA-3 验收门「端到端 LLM chat 真跑」。**07-21续5 解封**：DeepBase 编译阻断已解除（根因=TLLMService 类声明漏 forward，DeepBase `3f056c6` 修），DeepFrames.exe built，`--test-llm agnes` 实跑 **facade 链路打通**——返回 `STUB`（因 Agnes 未配 key 走 stub 分支），`--test-llm` 正确判 FAIL（exit 5），确认编译阻断解除 + facade 调用链通 + stub 检测生效。**新发现更深根因**（bugfix 07-21续4）：`DocumentChain.pas:195` 的 `ChatComplete` False 分支（else）仍产 `'stub-script-v1'` document + `STATUS_DONE`——即 LLM 失败时 pipeline 把失败吞成 DONE，比 stub 返 True 更深一层；即使改 stub 返 False，else 分支仍标 DONE。故 DBA-3 残留④的真修方向是**改 pipeline else 分支不再伪装 DONE**（标 FAILED 或至少 STUB 标记），且需真跑验证（待配 Agnes key）。**07-21续11 残留④ 已修完结**：DocumentChain 4 处 LLM step 的吞失败→DONE 全部改为 STATUS_FAILED+raise（见上），代码层达阵；唯一剩 DBA-3 验收门②「端到端 LLM chat 真跑」仍卡 `PROXY_UNREACHABLE`（代理路由恢复后即验，非代码层）。验收门：~~provider 文件 <600 行~~（**续13 已过**）；~~pipeline 失败不再吞成 DONE~~（**续11 已过**）；端到端 LLM chat 真跑（待代理路由恢复）。
- [x] **DBA-4 [P1] 编排改用 DeepBaseServices — 异步编排完成，E2E 真跑待代理路由恢复（续15）** — `App.Services.pas` 的 `RunFullPipeline` 硬编码 P1→P6 串联，改为用 DeepBase `TWorkerQueue` 异步执行。**07-21续15 完成（commit `2dca985`）**：① `RunFullPipelineAsync(ForceRerun, AOnProgress, AOnComplete): string`（返 worker 内部 JobId）+ `GetPipelineStatus(JobId): TPipelineStatus`（IsTerminal + FinalJob）+ `RunFullPipelineSync`（同步核心，blocking `RunFullPipeline` 退为 wrapper）；DeepFrames 自有一个 `TWorkerQueue` 单例（懒建 + finalization Free），按 `JobType` 注册 handler，回调存 `GPipelineCallbacks`、终态存 `GPipelineResults`（in-memory，故意不用 DependsOn 链——内存队列丢 job 后 DependsOn 永久卡）。② CLI `--run-pipeline` 改 enqueue + `GetPipelineStatus` poll 循环，OnProgress 在 worker 线程 WriteLn stdout 不碰共享 PL。③ GUI 新增 `CMD_FULL_PIPELINE_RUN` 命令，`CmdRunFullPipeline` 用 `TThread.Queue` 回主线程刷 `Status` + `RefreshProjectView`。**验收对照**：pipeline 运行中 UI 不阻塞 → ✅（GUI 主线程立即返回，worker 跑）；进程被杀重跑从断点续 → 设计满足（无 DependsOn + per-phase `FindJobByLogicalKey` 短路，续9/13 已验 phase 级幂等），但 **E2E 真跑待续14 上交的代理路由架构对齐方案落地**（`--run-pipeline --force-rerun` 仍撞 `PROXY_UNREACHABLE`）。
- [~] **DBA-5 [P1] 诊断迁入 DeepBase.Logging — src/ WriteLn 全清 + diag 残留已删，实质完成** — `src/` 全部裸 `WriteLn` 已迁完：`App.Services.pas`（ImportMarkdown 诊断 + `RunFullPipeline` Mark/边界）、`AudioChain.pas`（TTS/ASR 三处）、`ArtifactOSBridge.pas`（11 处 `WriteLn(ErrOutput,...)` → `Logger.ErrorFmt/InfoFmt` 带 `DeepFrames.ArtifactOS` category）。**动机**：GUI 进程无控制台时 `WriteLn` 触发 `EInOutError` 崩溃（bugfix B38）；迁 Logger 同时消除"未接 Logging 前真假绿不分"根因。**07-21 验证**：dcc64 编译 0 Error；`grep WriteLn src/` 非注释残留为 0；EXE 内 `DeepFrames.Audio`/`DeepFrames.App` category 字符串已确认（UTF-16）；`DeepFrames.ArtifactOS` 因 `TArtifactOSBridge` 全程序未实例化被 smart-link 剥离（预期，该桥待 DB3 集成阶段接线）。**diag 残留已清**：原 tasks 写"19 个 `AssignFile` 诊断文件"实为陈旧数字——`src/` 内已 0 个 `AssignFile` 调用、0 个 `df_*` 字面量；磁盘上仅 5 个 07-14/15 早期版本运行残留（`df_fatal/mux/purge/subtitle_diag.txt` + `bin/df_fatal_diag.txt`），已删，`.gitignore` line 61 本就覆盖 `df_*.txt` 故无 git 变更。**剩余**：无。stub 汇总已完成（见 history.md 07-21 节，发现唯一真残留 Baidu `SplitOnSilence` → 新建 DBA-7）。验收：`grep -r "df_.*_diag\|AssignFile.*df_" src/` 收敛到零（**已过**）。
- [ ] **DBA-6 [P2] Repository 按聚合根拆分** — `Persistence/Repository.pas`（2839 行/87 方法/40+ 表）拆为 `TShotRepository`/`TAudioManifestRepository`/`TVideoJobRepository`/`TJobRepository` 等，每个 < 300 行。Repository 只做 CRUD，跨聚合事务放 Application Service。（DeepBase 不替你做，属下游职责。）
- [~] **DBA-7 [P1] Baidu ASR SplitOnSilence 静音分块实现 — 代码完成，端到端验收待 DBA-1 凭据** — `Provider.Baidu.pas SplitOnSilence` 原 `NOT IMPLEMENTED`（整段作单块，>60s 音频被 Baidu `server_api` 拒绝失败）。**07-21 实现**：① `SplitOnSilence` 签名扩展为 `out AChunks, AStarts, AEnds`，跑 `ffmpeg -af silencedetect=noise=-30dB:d=0.5 -f null -` 解析 `silence_start/silence_end`（新增 `ParseDurationSec`/`ParseFirstFloatAfter` 辅助，纯 1-indexed `Copy`/`Pos` 避免 `Substring` off-by-one），按静音边界用 `-ss X -to Y -c copy`（16k PCM WAV stream-copy 无重编码）切片到临时 `df_asr_chunks_<guid>/` 目录；音频 <60s 或无静音 → fallback 单块。② `Transcribe` 主循环改：每块成功后建一个 `TAsrWordTimestamp`，`StartSec/EndSec` 取该块的静音边界（下游 AudioChain 见 `Words>1 and EndSec>0` 走真时间分支生成字幕 cue，根治 `pipeline-subtitle-empty-rootcause` 记的"整句 EndSec=0→字幕空"）；`TempWavToDelete` 清理扩展为删整个 chunks 目录。③ `TranscribeText` 改拼接所有 Words（原只取 `Words[0]` 会丢多块文本）。**07-21 验证**：dcc64 编译 0 Error（69315 行 2.94s，EXE 11.5MB）；ffmpeg silencedetect 真输出格式解析逻辑经实测样本验证（`Duration: 00:00:47.47` + `silence_start/end` 三段）；16k WAV `-c copy` 切片实测 C1 `[3.04,10.14]`→7.10s（差 0.00）、C2 `[10.75,15.84]`→5.12s（差 0.03，帧对齐）。**残留**：端到端 ASR 真跑待 DBA-1（`baidu_asr_key` 真实凭据未存，`TranscribeChunk` 会 `NO_TOKEN`）——不属本轮范围，老板凭据操作。验收：>60s 音频 ASR 返回非空 words 且时间戳连续（待凭据后跑）。

---

## A 线 — 商用就绪度收尾（P0/High 残项）

- [ ] **A1 [已处置] 明文 key 进 git 历史** — 原为 P0 商用硬阻断"key 清史轮换"。**07-15 已处置**：单人单机无远端场景，已删 `.git` 重建（commit `832fe98`），旧历史含明文 key 彻底消失，密钥轮换对此场景不再必要。剩余工作由 **DBA-1** 覆盖（明文 key 迁入 `DeepBase.Security` 后删除根目录明文文件）。memory `keys-leaked-in-git-history`。
- [ ] **A2 [P0] 百度 TTS/ASR 真实端点 HTTP SSL 卡死根治** — provider 已实现但 HTTP 调用在某些环境 SSL 卡死未根治（memory `baidu-provider-static-fixes`），RI2/RI3 仍 SKIP。需存百度 key 后实测定位是 Indy/OpenSSL 配置还是端点问题。
- [ ] **A3 [High] 运维 runbook** — 部署/回滚/告警/故障排查手册（第三阶段残项）。结构化日志已接入（DocumentChain），runbook 据此写故障排查路径。
- [ ] **A4 [High] 第三方安全审计** — 外部审计，不可自做。商用前必须。
- [ ] **A5 [P0] H.264 专利** — 商用需授权或转 AV1/VP9（当前 skip，P0-I 已记）。

---

## B 线 — 生产链路端到端实测验证（接通后必跑）

- [ ] **B1 百度 key 存 secret 跑 RI2/RI3 真实验证** — P0-F 遗留。`--set-secret` 存百度 API key/secret 后跑 RealIntegration，确认 TTS/ASR 真实端点通（依赖 A2 的 SSL 修复）。
- [ ] **B2 RI4 Agnes image 挂起排查** — bugfix B22。给 `Generate` 加超时/异步轮询，或用 `--set-secret` 配 Agnes key 后单独调试（image 端点慢或请求构造问题）。
- [ ] **B3 VideoChain 端到端真跑（GUI 触发）** — B24 接通后需真跑一次完整链路（LLM→字幕→图像→TTS→ASR→Agnes video→mux 烧录→package），确认产出的视频有画面+字幕+声音。**无法 CLI 自动化，需用户在 GUI 触发**。这是验证"生产视频无字幕无声音"根因是否真解决的最终判据。
- [ ] **B4 LLM GPT 端到端验证（GUI 触发）** — 本轮只改了 DB 配置 + curl 模拟，未在应用内真跑 chat。需 GUI 发一次 chat 请求确认 GPT 路由在应用层通（依赖 reasoning_content=null 回退逻辑，理论兼容但需实测）。

---

## D 线 — 全能力 CLI 链路（2026-07-13 新增，最高工程优先级）

> 来源：`docs/17.lessons-y2a` §D 线全能力 CLI 链路 + 接入执行顺序。

- [ ] **D1 全能力 CLI 参数化** — 扩展 `--run-pipeline <seedPath>`，支持全部生产开关（与 GUI 设置页对齐，见 D3）：
  - `--duration-strategy {shortest|audio-base|video-base}`（默认 audio-base，见 B32）
  - `--asr-provider {stepfun|baidu|gemini}` + `--tts-provider {stepfun|baidu|gemini}` + `--llm-provider {fccy-gpt|agnes|gemini}`
  - `--voice <name>` + `--subtitle-lang {zh|en}` + `--ffmpeg-path <dir>` + `--force-rerun`
- [ ] **D2 全链路 CLI 端到端真跑** — 用 D1 的 CLI 参数跑一次完整链路（LLM→字幕→图像→TTS→ASR→Agnes video→mux 烧录→package），**产出有画面+字幕+声音+音画同步的 MP4**。这是 B3 的 CLI 等价物：B3 依赖 GUI 触发无法自动化，D2 用 CLI 把同样的验证变成可重复、可进 CI 的脚本。验收：成片 SHA256 稳定、音画时长差 ≤ 1 帧、字幕 cue 数 = ASR 词级时间戳数。
- [ ] **D3 GUI 设置页补齐** — 报告 P0-7/P1-1。UI 加：API 密钥（写 `DeepBase.Security`，不落明文）/ provider 选择 / LLM 模型 / 音色 / 字幕语言 / ffmpeg 路径。设置项与 D1 CLI 参数一一对应（同一 DB 配置真相，CLI 与 GUI 两种入口）。
- [ ] **D4 GUI 一键成片 + 后台线程 + 预览** — 报告 P0-6/P1-1/P1-2。①注册 `RunFullPipeline` 为 UI 命令（现仅 CLI，`UI.MainForm.pas:1027-1054` 未注册）；②chain 移 `TThread`/`TTask` 后台执行，`Status` 做分步进度回调（`Step 3/8`）；③成片后结构树资产节点右键"打开/播放/在资源管理器中显示"（`ShellExecute`）。
- [ ] **D5 音画时长显式对齐** — 报告 P0-5。现状 mux 用 audio-base + `-stream_loop` 循环填充（B32 已修默认），但需把 `-duration-strategy` 接入 D1 参数。以音频时长为基准（TTS 可控 + ASR 有精确时长），视频短→循环/补帧，视频长→`-t <音频时长>` 裁剪；字幕已用 ASR 词级时间戳对齐（已通，无需再动��。
- [ ] **D6 ASR 降级告警** — 报告 P0-4。failover 到 baidu/gemini ASR（无词级时间戳）时，字幕层标 `warn` 并在 quality_snapshot 记录 `subtitle_degraded=whole_text_blob`，不让用户误以为字幕坏了。或对无时间戳 ASR 结果用 TTS 分段时间戳做均匀分段兜底。
- [~] **D7 删调试产物 + 去硬编码**（续16 `7dd9b1b`）— 报告 P1-3/P1-4/P1-5。**已落地**：`force_video_regenerate.txt` 后门 gate 到 `{$IFDEF DEBUG}`（Release 编译期消失）；ffmpeg/ffprobe 路径探测抽到 `Shared.Tools.TFFmpegLocator`（唯一真相源，DB1 `CONFIG_FFMPEG_DIR` 优先 + known paths + PATH），AudioProcessor/Baidu 转发，VideoRenderEngine 死路径 `'C:\ProgramData\chocolatey\bin\ffmpeg.exe'` 改调 locator（本轮发现的最严重硬编码）；`df_phase.txt`/`df_before_promptrun_diag.txt` 源码无命中（已删）。**残留**：标题卡副文案 `"DeepFrames AI"` 仍字面量（`VideoRenderEngine.pas:167/176`），仅 `VideoGenTest.dpr` 测试程序调用，商用度影响低，留品牌参数化批次。
- [~] **D8 Gate3b 接真实视觉评分**（续17）— 报告 P0-2/P0-3。**��落地**（续17 三步）：① `Shared.Tools.TFrameExtractor.ExtractFrames`（ffmpeg `-vf fps=1` 抽真实帧，失败返 False 走降级）；② `GateEvaluator.EvaluateGate3bFromVLM(AVlmText, AProviderReached)` + `IsDegraded` + `GATE3B_DEGRADED_SCORE=-1` sentinel——VLM 不可达/响应不可解析时降级 WARN（红线#8：记录+续跑，非静默硬编码 pass）；③ `VideoChain` Gate3b 从 render **前**挪到 render/mux **后**，评真实最终 MP4（`Gate3bMp4`=mux 产物 or render 产物），删掉评假 `keyframe_001.png` 硬编码 `1.0` 的旧块。单测 7 条全绿（`Tests.Core.pas` Gate3b pass/warn/fail + FromVLM unreachable/unparseable/parseable）。**残留**：vision provider 未接（StepFunLLM `ChatComplete` 纯文本无 image_url），当前 `AProviderReached:=False` 走降级 WARN；接 GPT-4o/StepFun Vision/Gemini generateContent 多模态后换 True+真响应即激活真分，FAIL 分支已通读接线。

### D 线验收标准
- D1 完成 = CLI 全开关可配，与 GUI 设置页参数一一对应
- D2 完成 = 可重复、可进 CI 的端到端真跑脚本，产出真实可用 MP4
- D3-D8 完成 = "能跑"变成"能用 + 音画名副其实 + 无调试残留"

---

## C 线 — 待激活/可选
- [ ] **C1 P3-9 多模态反向验证** — `VLM()` 函数 + S2_Images 集成已完成，待 StepFun plan 开通 `step-1o-turbo-vision` 配额（当前 quota_exceeded）。配额开通后零代码改动激活。**注**：现已切 GPT，可评估改用 GPT-4o 多模态替代 StepFun VLM，绕开配额依赖。
- [x] **C2 Gemini failover provider** — **已完成态（2026-07-09 复核）**：`CreateProductionProviders`（Registry:199）已将 LLM/TTS/ASR 三件套用 `TFailoverXxxProvider` 包 `[primary, TGeminiXxxProvider]`，且 `InitializeDefaults` 默认即 `production` 链（fresh install 默认启用 failover）。Failover 逻辑（Failover.pas:132 `for` 遍历→首个 True 退出）正确。Gemini provider 1349 行三能力（LLM/TTS/ASR）各有 CallRealAPI+CallStubAPI+HasKey 门控，实现完整。RI9 已有 failover 自动切换测试（primary 强制失败→Gemini，RI7/RI9 因 Gemini TTS 模型不稳定而 SKIP，不影响 failover 机制本身）。**无需再编码**。

---

## 建议执行顺序（2026-07-15 更新）

0. **DBA-1 ✅验收通过 + DBA-3 残留 + DBA-2 [P0]**（密钥迁 Security 收尾验收已过 / LLM facade 文件拆分+stub 收敛+pipeline 吞失败修复 / 配置迁 DB1）——补接 DeepBase 铁律基线，消除"改配置不生效"和"stub 伪装成功"的结构根因。**在一切功能验证之前**：未接入 `DeepBase.Logging` 前，D2 的"端到端真跑"结论不可信（真假绿无法区分）。
   - **07-21 续4 进展**：① **DBA-1 验收通过**（4 secret 全 LoadSecret 往返成功 + 删明文 + 修存错库，见 line 72）。② **DBA-3 残留深入**——发现 pipeline 吞失败→DONE 真根因（`DocumentChain.pas:195` ChatComplete False 分支产 stub doc + STATUS_DONE，即使 LLM 失败 step 仍标 DONE，比 stub 返 True 更深）；已加 `--test-llm` CLI 直击验收门。③ **DBA-2 配置体系核查通过**（续4）：Agnes base_url/model 全走 `GetConfig(KEY, DEFAULT)` 有 DB1 降级默认（`Agnes.pas:154/174/222`），Bootstrap `Ensure()` 13 处 seed 配置全进 DB1 Settings，无硬编码，合铁律#5「不绕过 DeepBase 配置体系」。④ **DeepBase 编译阻断已解除**（07-21续5）：老板授权介入 DeepBase，查清根因——**不是重构意图不明，是原���者遗漏 bug**：Client.pas 给 ILLMClient 加 `ChatWithHistoryByProvider` 接口方法 + Service.pas 实现 + Proxy.pas 声明，**独漏 `TLLMService` 类声明段的 forward 声明**→Delphi 实现段凭空定义类方法→E2003(undeclared)+E2291(类未实现接口方法)+连带 E2250(ForceQueue 编译器状态错乱)。修复：Service 类声明段补 forward 声明 + Proxy 补声明+实现（Proxy 模式 model 字段传 AModelId/provider 名）。DeepBase commit `3f056c6`；DeepFrames.exe built；`--test-llm agnes` 实跑 facade 链路打通（返回 STUB，因 Agnes 未配 key）。**下一步**：配 Agnes key 后 `--test-llm agnes` 应返回非 stub 真 reply（验收门）→改 pipeline else 不再吞 DONE→provider 文件拆分；DBA-5 Logger 剩余文件迁移（编译已解封，可推进+验证）。
1. **D1 + D2**（全能力 CLI 参数化 + CLI 端到端真跑）——DBA-1~3 落地后，用 D1 的 CLI 参数跑一次完整链路，验证本轮接通是否真生效。DBA 线为 D 线前置。
2. **DBA-3 残留② + 验收 E2E [P1]**（Gemini thinking/schema 实测 + 代理路由恢复后 E2E 真跑）——DBA-4（续15 `2dca985`）+ DBA-5（line 79 实质完成，WriteLn 全清、diag 残留已删）已落地，真假绿可查的结构根因已除。剩余 DBA-3 残留②（Gemini 服务端 thinking/schema 丢，需实测）+ 所有 DBA 项的 E2E 真跑验收仍卡续14 代理架构对齐。可与 D4（GUI 一键+后台）协同。
3. **B3 + B4**（GUI 端到端真跑）——D2 跑通后，验证同一配置经 GUI 一键成片产出等价结果。
4. **D3-D8**（GUI 设置页 / 一键+后台+预览 / 音画时长对齐 / ASR 降级告警 / 删调试产物 / Gate3b 真分）——把"能跑"变成"能用 + 音画名副其实"。注意 D3 的"密钥写 DeepBase.Security"已被 DBA-1 覆盖，D3 只需接 UI。
5. **XHS-P0~P3**（小红书单平台适配）——DBA + D 线就绪后，把通用链路收敛到小红书首个可发布候选包。
6. **A2 + B1**（百度 SSL 修复 + 真实验证）——补全 TTS/ASR 真实链路。
7. **DBA-6 [P2]**（Repository 按聚合根拆）——降合并冲突、提可测性，可后续迭代做。
8. **A3/A4/A5**（商用收尾）——runbook / 审计 / 专利，商用前。
   - **注**：A1（key 清史轮换）原排第 5，07-15 已处置（git 重建清史，单人单机场景密钥轮换不再必要），剩余工作并入 DBA-1。

---

## 开发红线

> `docs/ENGINEERING_HANDOFF.md` §6

1. 不把业务表写入 DB1 ConfigDB
2. 不把 API Key 写入 `.env`/JSON/INI/Registry/日志/DB2
3. UI Form 不直接写业务表，必须通过 application service
4. worker 不直接访问 DB1/DB2 或读 `shot_document`
5. 不绕过 DeepBase 配置/日志/密钥/JobQueue 体系
6. Node/TypeScript 只能作为 worker，不做主程序
7. 不原地覆盖文档/manifest/候选包，返工产生新 version
8. 黄灯记录并提醒，红灯才进 `blocked_review`
9. 不混淆业务对象状态和资产状态
10. 不跳过 `schema_version`，所有 JSON payload 必须版本化
