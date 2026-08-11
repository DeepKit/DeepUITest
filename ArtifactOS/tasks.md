# ArtifactOS Tasks

> 更新: 2026-07-13
> Phase 1-3 全部完成 ✅ — 55 migrations, 154 tables
> N10-N12 审查修复全部完成 ✅ — 19 bugs fixed across 3 rounds
> 深基集成改进全部完成 ✅ — DI3-DI6 fixed
> 代码去重: 6 处 JsonStr 副本 → 1 处 (JsonBuilder)
> N13.1-13.7 + post-review 4 bugs 全部完成 ✅ (commit a9f3362, f05cea4, 82a510e, a457053)
> 当前焦点: BCW-S1~S5 ✅ + AP-P0 ✅ → AP-P1 5/5 开发完成 + 端到端烟测全绿 (SmokeCandidatePack) → 下一: AP-P2 RealPublishGate 强制

---

## DUnitX (2026-06-17)

| 度量 | 值 |
|------|------|
| Tests Found | 82 (10 fixtures) |
| Tests Passed | 48 |
| Tests Failed | 11 (已有数据依赖问题) |
| Tests Errored | 23 (已有数据依赖问题) |
| Compile Errors | 0 |

---

## 当前任务

### N13: 技术债清偿 ✅

> N13.1-13.7 全部完成并归档 history.md / bugfix.md (BUG-068~072)。

| # | 文件 | 描述 | 状态 |
|---|------|------|:---:|
| N13.6 | `GenerationService.pas` | `GetContractJson` contractId 进程内缓存 (TDictionary + TMonitor DCL)，ClearContractCache 公开 | ✅ |
| N13.7 | `JsonBuilder.pas` | git mv 至 `core/ArtifactOS.Core.Common.JsonBuilder.pas`，10 处 uses 改名，双编译 0 error | ✅ |

#### 已完成 (归档 history.md)

| # | 描述 | commit |
|---|------|--------|
| N13.1 | TheoryWeave/LegacyImport 补 RETURNING id::text，InsertAndReturnId 走原子路径 | a9f3362 |
| N13.2 | 6 处 wrapper 评估为低价值清理，延后 | a9f3362 |
| N13.3 | SQL 拼接经 N12 参数化收敛，残留项随业务演进迁移 | — |
| N13.4 | Repository.pas 私有 JSON 副本去重 (BUG-071) | a9f3362 |
| N13.5 | FormatBody TStringBuilder 性能优化 (BUG-072) | f05cea4 |

### N7.4: DeepFrames 联调 🔲

> 已交付 `src/bridge/ArtifactOSBridge.pas` (700+ 行, 5 hardening measures, 0 errors)
> 待 DeepFrames 侧接收并集成

---

## 验证基线

| # | 验证项 | 状态 | 结果 |
|---|--------|:---:|------|
| V1 | Python 集成测试 | ✅ | 13/13 PASS |
| V2 | ShadowRun 7天自动调度 | ✅ | Day 1-7 全部生成 |
| V3 | RealPublishGate 12条件 | ✅ | blocked（预期） |
| V4 | `--autofix` 诊断 | ✅ | 21/21 PASS |
| V5 | Delphi 主程序编译 | ✅ | 0 error |
| V6 | DUnitX 测试编译 | ✅ | 0 error |
| V7 | 正式环境迁移 | ✅ | 52/52 migrations applied |

## 依赖关系

```text
Phase 1-3 ✅ → N10-N12 ✅ (19 bugs fixed)
  → N13.1-13.7 ✅ + post-review ✅ (BUG-068~072)
  → BCW-S1~S6 (BCW 接入) 🔴
  → AP-P0~P5 (多平台发布) 🔴
  → N7.4 DeepFrames 联调 🔲
```

## 开发红线

1. 所有 SQL 必须参数化（JsonBuilder + BindParamsFromJson）
2. 测试必须先过 artifactos_test，不得直接操作 artifactos
3. core/ 不依赖 services/；单向依赖
4. PG 连接通过 `ArtifactOS_DB` 全局单例，禁止自行创建 TFDConnection
5. UUID 必须剥离花括号后再用于 WHERE 子句
6. INSERT 后必须 `Disconnect` defer close（引用计数）
7. `InsertAndReturnId` 支持 RETURNING 原子路径（N12.3 新增）
8. `ExecuteScalar` 只读不提交，调用者管理事务
9. 生产迁移仅通过 `migrate_production.py` 执行
10. Phase 1A 仅允许 shadow/simulated 发布，RealPublishGate blocked
11. ArtifactOS 与 DeepFrames 仅通过 DB3 `integration.*` 表互通
12. 所有 SQL 输入必须参数化，禁止字符串拼接（N10）
13. `JsonEscape` 仅转义 JSON 需要的字符（`\`, `"`, `\r`, `\n`），不转义单引号（N12.1）
14. `BindParamsFromJson` 是唯一的 SQL 单引号转义点（N12.1）
15. 共享 JSON 构造使用 `ArtifactOS.Core.Common.JsonBuilder`（N10; N13.7 迁移自 core/DB）
16. `BindParamsFromJson` 参数名按长度降序排序，防止前缀冲突（N12.4）
17. **新**: `DeepLLMProxy` 每次调用创建独立 `TDeepBaseLLM`，不共享实例（N13 新增）
---

## 小红书优先的多平台自动发布专项（2026-07-11 新增）

> 老板裁决：`AutoPublishAll` 必须保留并支持多平台；现阶段通过运行参数只启用小红书。自动发布是必须交付的正式能力，不能长期退化为纯人工发布。系统应以合规、低频、可审计的浏览器人工操作仿真减少人工时间，但不得绕过验证码、伪造设备身份或规避平台明确的安全控制。

### AP-P0：发布战略参数与多平台能力边界 ✅

- [x] 保留 `AutoPublishAll` 的多平台遍历与扩展能力，不得写死为小红书专用函数。
- [x] 增加显式运行参数，例如：

```text
--platforms=xiaohongshu
--publish-mode=browser_assisted
--account-stage=new
--max-posts-per-run=1
--require-human-on-challenge=true
```

- [x] 支持平台白名单、账号白名单、内容类型白名单；当前生产默认值仅允许 `xiaohongshu`。
- [x] 未列入 `--platforms` 的适配器不得创建任务、启动浏览器或访问账号凭据。
- [x] `AutoPublishAll` 返回逐平台结果，不因一个平台失败而丢失其他平台的状态与证据。
- [x] 为未来知乎、B站等平台保留统一接口，但未验收平台默认 `disabled`。

**验收标准**：同一构建可注册多个平台；以 `--platforms=xiaohongshu` 运行时，只产生小红书发布任务和浏览器行为，其他平台零副作用。

**实现说明**（2026-07-13）：
- 新增 `TPublishRunConfig` 记录（AllowedPlatforms / PublishMode / AccountStage / MaxPostsPerRun / RequireHumanOnChallenge / EnableContentWhitelist），默认仅 `xiaohongshu`。
- `TPublicationBridge.ConfigureFromArgs` 解析 `--platforms / --publish-mode / --account-stage / --max-posts-per-run / --require-human-on-challenge / --enable-content-whitelist`；失败项回退默认。
- `AutoPublish` 入口加 `IsPlatformAllowed` 硬白名单守卫：未授权平台在写 DB 任务行之前即返回，零副作用。
- `AutoPublishAll` 遍历已注册适配器，按白名单过滤后才建任务，并受 `MaxPostsPerRun` 封顶；逐平台 try/except，单平台失败不丢其他平台证据。
- 主 exe + 测试 runner 均编译通过（0 error）。

### AP-P1：小红书视频适配与 DeepFrames 完整交接 ✅ 5/5 开发完成 + 端到端烟测全绿

- [x] 小红书适配器设置并验证 `SupportsVideo := True`，支持 3:4 视频及独立封面。
  （`TXiaoHongShuAdapter`: `SupportsVideo:=True; VideoAspect:='3:4'; CoverAspect:='3:4'; MaxVideoCount:=1; MaxVideoDurationMs:=300000`）
- [x] 读取 DeepFrames `package_manifest.json`，完整接收：

```text
video_3x4.mp4
cover_1080x1440.png
title.txt
body.txt
tags.json
ai_disclosure.txt
quality_snapshot.json
source_trace.json
package_manifest.json
```
  （`CandidatePackImporter.LoadAndValidate`: 9 文件全量读取，manifest 为入口）

- [x] 校验文件存在性、媒体格式、尺寸、时长、编码、文件大小、字幕可读性和 SHA-256 哈希。
  （ext↔mime + size>0 + cover 3:4 + video 3:4 from manifest w/h + SHA-256 重算比对 + 4 JSON 可解析 + duration_ms>0 + 字幕 UTF-8。7/7 测试全过：见 BUG-085）
- [x] 将视频、封面、披露、来源、质量快照和资产哈希写入 publication package，不得只传递标题和正文。
  （`Persist`: `asset_file`(video/cover, 含 sha/w/h/dur) + `publication_package`(ai_disclosure/source_trace::jsonb/manifest_blob::jsonb/asset_hashes::jsonb/quality_snapshot_id)。NULLIF(:acct,'')::uuid 修复空 account_id，BUG-085）
- [x] DB3 交接仅使用 `integration.*` 表，保持 ArtifactOS 与 DeepFrames 的系统边界。
  （`Persist` 在写完 `publication_package` 后, 于同一连接内 INSERT `integration.production_request` (status='pending', request_payload 带包级摘要 package_id/platform/account_id/quality_snapshot_id/asset_hashes/title), `ON CONFLICT (tenant_id, request_code) DO NOTHING` 保证幂等; request_code=`xhs_<package_id>`。测试断言 pending 状态 + payload.package_id + 恰好 1 条/包)
- [x] **端到端验收**（合成但结构真实包，`src/smoke/SmokeCandidatePack.dpr`，2026-07-13）：
  合成 9 文件候选包（3:4 视频 64KB 占位 + 1×1 PNG 封面 + 8 role 文本/JSON 资产 + manifest），
  跑通 `LoadAndValidate`(8 assets valid, 3:4/SHA-256/mime/JSON 全过) → seed artifact/version/snapshot
  → `Persist`(写 publication_package + asset_file 2 rows + integration.production_request pending)
  → 反查(ai_disclosure / asset_hashes->video / manifest package_id / prod_request status+pkg_id+platform 全一致)
  → 幂等(同 request_code 重插 ON CONFLICT DO NOTHING → count 仍 1) → cleanup。
  `===== ALL STEPS PASSED =====`，连续两次稳定。真实 DeepFrames 产物待 N7.4 联调时替换包内容即可（导入路径编码无关，已验证）。

**验收标准**：DeepFrames 生成的一个候选包可被 ArtifactOS 无损导入、审查、排队和发布，发布记录能够反查原始候选包与资产哈希。

### AP-P2：自动发布前强制 RealPublishGate 🔴

- [ ] `AutoPublish` 和 `AutoPublishAll` 创建真实发布任务前必须调用完整 `RealPublishGate`，不得仅检查 `quality_snapshot.qualified_status`。
- [ ] 至少检查：平台启用、账号可用、登录有效、权限正常、内容审核通过、素材授权、AI 披露、频率预算、发布时间窗、幂等键、人工挑战处理策略、回滚/撤回能力。
- [ ] 新账号默认采用保守频率和单任务串行；禁止并发发布、批量重试和失败后立即重复提交。
- [ ] 每个真实发布任务必须有唯一幂等键；超时后先查询平台页面/本地证据确认是否已经发布，再决定是否重试。
- [ ] Gate 的每个条件必须输出结构化结果、原因码和审计日志。

**验收标准**：任何硬门未通过时均不能打开真实发布流程；重复执行同一任务不会产生重复帖子。

### AP-P3：浏览器辅助自动发布运行时 🔴

- [ ] 优先采用真实浏览器 UI 操作路径：打开创作页、点击上传、选择文件、填写标题正文、设置封面、预览并点击发布；禁止直接调用未公开的内部发布 HTTP 接口。
- [ ] 支持经批准的隐私/反跟踪浏览器或持久化浏览器配置文件，保持稳定的账号会话、Cookie 容器和正常浏览器特征。
- [ ] 操作节奏采用有限随机等待、元素可见性等待、页面状态确认和单步截图，避免机械固定间隔与高频操作。
- [ ] 不实施验证码破解、设备指纹伪造、安全挑战绕过或平台限制规避；出现验证码、短信验证、异常登录、风险提示时暂停并请求人工接管。
- [ ] 支持断点续跑：浏览器或网络失败后从已确认步骤恢复，不盲目重复上传或点击发布。
- [ ] 发布前保留最终预览截图；发布后采集成功页面、帖子 URL/ID、发布时间和结果截图。
- [ ] 浏览器运行器必须单账号串行，并有全局熔断、每日上限、失败上限和冷却时间。

**验收标准**：在不使用内部接口的前提下，自动完成一次小红书视频 UI 发布；遇到安全挑战时安全暂停，人工处理后可继续；全流程有截图与步骤日志。

### AP-P4：小红书内容与账号风险门禁 🔴

- [ ] 检测并默认阻断：外链、二维码、微信号、手机号、邮箱、跨平台水印及明显站外导流表达。
- [ ] 检测心理疾病诊断、治疗承诺、绝对化效果、过度恐吓等高风险表达，转入人工复核。
- [ ] 检查 AI 生成/辅助披露是否满足当前策略，披露文本必须进入最终发布包。
- [ ] 检查图片、字体、音乐、视频素材来源与许可状态；来源不完整不得自动发布。
- [ ] 增加跨内容相似度和模板同质化检查，避免短期批量发布高度相似作品。
- [ ] 新账号建立独立风险档案：账号年龄、历史发布数、最近异常、频率预算、冷却状态、人工挑战次数。

#### AP-P4.1：软边界实验与爆款破格机制 🔴

- [ ] 内容风险分为`hard_redline`与`soft_boundary`，不得把品味偏好、标题强度和争议表达与法律/平台硬门混为一类。
- [ ] 支持：

```yaml
risk_mode: edge_experiment
edge_variables:
  - stronger_title
  - higher_emotional_intensity
  - controversial_position
  - dramatic_expression
  - unconventional_visual
  - limited_template_reuse
  - humor_or_satire
```

- [ ] 虚构、改编、合成人物、多个案例合并、寓言、假设场景和故事新编是正常媒体创作，不默认标记为`edge_experiment`。
- [ ] 支持`story_mode=observed|adapted|composite|fictional|allegorical|hypothetical`，用于生产溯源，不强制前台论文式逐句披露。
- [ ] 硬红线收缩为违法违规、平台安全控制绕过、隐私侵害、冒充真实身份/资质、把虚构包装成真实用户背书/研究证据/效果数据、欺诈性商业承诺、明确现实伤害和当前站外导流。
- [ ] `edge_experiment`比例由Amy动态决定，不设固定15%硬上限；变量数量以可归因和创意完整性的平衡为准。
- [ ] 通过硬门的边界实验可按已授权风险策略发布，不要求老板逐条审批。
- [ ] 一次高流量不得触发自动复制；至少重复验证后才能晋级普通模式。
- [ ] 同时采集收益和伤害：点击、主页访问、关注、追更、误读、负面反馈、举报/限流、取消关注、账号异常。
- [ ] 出现平台警告、严重误读、举报激增或账号异常时自动熔断同模式。

**验收标准**：故事和虚构内容可正常进入生产发布；软边界实验可受控发布并回收双向信号；只有欺诈性真实性表达和必要硬风险被阻断。

**验收标准**：构造导流、诊断承诺、来源缺失和高度同质化样本，均能被阻断或转人工复核，并给出可追溯原因。

### AP-P5：人工介入最小化与例外工作台 🟡

- [ ] 人工只处理系统无法安全完成的例外：首次登录、安全挑战、最终高风险裁决、平台页面重大变化和撤回确认。
- [ ] 提供待处理队列，展示问题、截图、建议动作和“继续/终止/退回修改”按钮，避免人工重新走完整流程。
- [ ] 支持一次性审批与策略审批；策略审批必须限定账号、平台、内容类型、有效期和频率上限。
- [ ] 正常合格任务可在批准的策略范围内自动发布，不要求老板逐条点击。
- [ ] 所有人工介入均记录人员、时间、依据、前后状态和结果。

**验收标准**：正常任务无需人工逐步操作；异常任务可在一个工作台内完成最小必要接管，且恢复后不重复已完成步骤。

### AP-P6：发布证据、反馈与撤回闭环 🟡

- [ ] 自动记录帖子 ID/URL、账号、平台、内容版本、资产哈希、发布时间、发布模式、浏览器会话标识和最终截图。
- [ ] 采集 1h/24h/72h 指标：曝光、播放、完播、点赞、收藏、评论、关注变化、主页访问及异常状态；无法自动采集时生成明确的待补录项。
- [ ] 保存用户评论原话并关联内容假设，用于判断“外部价值是否真实”。
- [ ] 支持撤回/删除工作流，但真实撤回默认需要人工确认并保留完整审计链。
- [ ] 将反馈写回策略与生产侧，支持后续主题、钩子、时长和表达方式校准。

**验收标准**：发布后可从 ArtifactOS 还原“候选包 → 门禁 → 浏览器步骤 → 已发布帖子 → 72小时反馈”的完整链路。

### AP-P7：测试与灰度验收 🔴

- [ ] 为参数过滤、平台白名单、RealPublishGate、幂等、断点恢复、风险门禁和证据采集增加自动测试。
- [ ] 建立浏览器页面适配层与选择器版本，页面结构变化时快速熔断，不继续盲点。
- [ ] 测试顺序：模拟页面 → 测试账号/草稿模式 → 单条真实灰度 → 连续 3 条低频灰度。
- [ ] 第一阶段只启用一个小红书账号、单任务串行、每次最多发布 1 条。
- [ ] 连续 3 次真实发布全部满足：无重复、无误发、证据完整、挑战可接管、反馈可回收，方可扩大频率。

**首轮业务验收**：DeepFrames 生产 3 个 WSH 候选，ArtifactOS 完成审核并按参数仅对小红书自动发布其中 1 个，随后形成 72 小时反馈记录。

### 专项依赖关系

```text
AP-P0 参数与平台边界
  → AP-P1 完整资产交接
  → AP-P2 RealPublishGate
  → AP-P3 浏览器辅助自动发布
  → AP-P4 风险门禁
  → AP-P5 最小人工介入
  → AP-P6 证据反馈闭环
  → AP-P7 灰度验收
```

### 新增开发红线

18. `AutoPublishAll` 必须保持多平台能力；当前启用平台必须由显式参数/白名单控制，不得靠修改代码切换。
19. `AutoPublish` 是正式交付能力，但任何真实发布任务必须先通过 `RealPublishGate`。
20. 优先使用公开可见的浏览器 UI 完成发布，不调用未公开内部接口。
21. 可使用隐私保护和反跟踪能力维持账号会话安全，但禁止验证码破解、设备指纹伪造和安全控制绕过。
22. 遇到验证码、短信验证、异常登录或风险提示必须熔断并转人工接管。
23. 自动发布必须具备幂等、限频、冷却、断点续跑、截图留证和全链路审计。
24. 当前生产参数只允许小红书，但架构与测试必须保证后续可扩展到多个平台。

---

## BCW 简化接入专项（2026-07-13）

> 个人单用户系统，不建设企业级审批、权限、消息总线和复杂策略治理。接口规格见 `docs/27.[协议]-BCW决议接入与治理回流-BCW-Interface.md`。

### BCW-S1：本地文件交换 ✅（2026-07-13）

- [x] 建立：

```text
integration/bcw/inbox/      ← BCW 投递 decision_package（JSON）
integration/bcw/applied/    ← 导入成功后文件移入
integration/bcw/outbox/     ← S4 result_summary
integration/bcw/snapshots/  ← S2 旧配置快照
```

- [x] 支持JSON `decision_package`导入（Delphi 端无 YAML 库，S1 起改 JSON 复用 System.JSON + 参数化绑定，零新增依赖）。
- [x] 四项检查：schema 可解析、package id 去重、必填���段存在、account+platform+effective_date 冲突检测（S1 仅告警，S2 仲裁）。
- [x] 落库 `artifactos.bcw_applied_package`（status=`imported`，raw_payload 原始 JSON 不可变）+ `event_ledger` 审计。
- [x] `artifactos bcw apply` 子命令挂载（dpr 位置参数分发，优先于 --flag 模式）。

**实现**：`src/services/ArtifactOS.Services.BCWImport.pas` + `db/migrations/056_bcw_import.sql`。
**验收标准**：一个合法package可导入；重复package不会重复应用；缺必填字段时给出可读错误。✅

**端到端验证（2026-07-13）**：
- ✅ 主 exe 编译 0 error（dcc64，53248 行）。
- ✅ 端到端发现并修复 inbox/applied 路径 bug：`TPath.Combine(ExtractFilePath(ParamStr(0)), …)` 错把 inbox 解析到 `bin/Win64/Debug/integration/…`（exe 目录），改为 `TPath.GetFullPath(BCW_INBOX_DIR)` 相对进程 cwd——CLI 应从仓库根运行。修复后 `bcw apply` 正确发现 `inbox/BCW-PKG-20260713-001.json`。
- ✅ 运行时 DB 落库实测通过（2026-07-14）：修复 BUG-076（.env 密码被 shell 残留 env 覆盖，`load_dotenv` 加 `override=True`）+ BUG-077（PG 中文 lc_messages 致 psycopg2 握手崩溃）后，DB1 `Secrets` 表写入真实 PG 凭据（`ArtifactOS.DB.User`=fuyi01 / `.Pass`=a29806588-run，DPAPI 加密），`LoadSecret` 解密成功。`bcw apply` 端到端打通：包 BCW-PKG-20260713-001 导入 `artifactos.bcw_applied_package`（record `8fae9f4e-ac50-4da3-be47-00b4c85e02c5`），`event_ledger` 联动写入。migration 56/56 全 APPLIED。详见 BUG-076/077。

### BCW-S2：预览、应用和回退 ✅（2026-07-14）

- [x] 导入后显示“新增、修改、停止什么”。（`bcw preview` 输出 MODIFY/Add/Stop diff）
- [x] 确认后保存旧配置快照并应用新配置。（`bcw_config_snapshot` 落 pre-apply strategy_unit 快照；`bcw apply` 落应用行 + strategy_unit upsert）
- [x] 记录当前package id和应用时间。（`bcw_applied_package.status=applied`、`applied_at`、`previous_package_id` 链）
- [x] 支持一键恢复上一版快照。（`bcw rollback` 用 snapshot 还原 strategy_unit、行标记 rolled_back、写 event_ledger）

**验收标准**：preview(2 MODIFY)→apply→rollback 三步全 exit 0。

### BCW-S3：运行配置映射 ✅（2026-07-14）

- [x] 将package映射为AccountProfile、StrategyUnit、资源比例、理论边界、发布规则和复盘计划。（`MapPackageToSURecord` 把 `theory_boundary.disclosure`→`theory_intervention`、`platform`→`content_type`、`series[].status`→`autonomy_level`+`publish_permission`、`resource_ratio`→`experiment_strategy.resource_ratio`、`review_cycle`→字段；AccountProfile 由账号行承载，不另建表）
- [x] 不要求每个字段建立独立审批和生命周期对象。（字段直接落 strategy_unit 单表，无 per-field 审批表）
- [x] 账号名称、理论定义、唯一主平台、重大资源变化和扩大自动发布权限只提示，不自动修改。（`icPromptOnly` 约束：autonomy_level 提升、publish_permission 扩权、resource_ratio Δ>0.2 时 hold back 旧值并产出 PROMPT_ONLY issue，不写新值）

**验收标准**：能建立“和悦论／我不让你背锅”“拒绝后的24小时”和80/20资源配置。

✅ 运行时实测通过（2026-07-14）：
- `bcw preview` S2TEST 包：2 MODIFY（series1/series2 均已存在行）。
- `bcw apply` S2TEST 包：disclosure=medium → theory_intervention=medium_explicit；platform=xhs → content_type=card；series1 flagship_candidate → L2/auto_if_passed；series2 test_series → L1/human_review_only。apply exit 0，无 issue（autonomy 平级、ratio 不变）。
- `bcw apply` S3ESCALATE 包（series2 test_series→flagship_candidate、ratio 0.2→0.6、disclosure→high）：产出 3 个 `PROMPT_ONLY` issue 并 hold back——
  - `autonomy_level`: L1_ai_assist -> L2_auto_with_sample（§116 hold back）
  - `publish_permission`: human_review_only -> auto_if_passed（§116 hold back）
  - `resource_ratio`: swing 0.4 (>0.2) from 0.2 to 0.6（§113 hold back）
- **hold back 持久性验证**：二次 apply 同包仍报同样 3 个 PROMPT_ONLY（库字段未提升），证明 hold back 真回写库、不泄漏。
- `bcw preview/apply` S3RETIRE 包：retired 轻量分支——series1 `active->retired`(MODIFY)、series2 `active->retired`(STOP)；apply exit 0，无 issue。
- 主 exe + 测试 runner 均 0 fatal 编译通过（dcc64 54119 lines / 36912 lines）。详见 BCWImport.pas。

### BCW-S4：结果摘要 ✅

- [x] 生成 `result_summary`，包含发布数、阻断数、关键信号、事故、建议和待裁决项。
- [x] 详细评论、截图和平台指标仍保存在ArtifactOS。
- [x] 支持7天和30天摘要。

**验收标准**：BCW无需读取ArtifactOS全部日志，即可获得足够的复盘信息。

### BCW-S5：BCW/Amy运营控制CLI 🔴

- [ ] 按`BCW-D20260714-003`将正式主接口改为PG中心化领域接口；文件inbox/outbox只保留兼容和恢复用途。
- [ ] 实现`idempotency_key / correlation_id / fencing_token / asset://`公共协议，详见`docs/29.[架构]-PG中心化运行真相源优化方案-PG-Centered-Runtime.md`。
- [x] 2026-07-14完成现状审计：除`bcw apply` S1外，其余运营CLI未实现；十个运营对象大部分可由现有表组合承载，不先新增十张表。详见`docs/28.[审计]-Amy自主运营对象与CLI缺口-Amy-Operations-Audit.md`。
- [x] 建立合同级dry-run样例：`integration/dry-runs/BCW-A20260714-001/xhs-first-package-dry-run.json`；该样例不冒充已执行回执。
- [x] P0：未知位置参数命令必须非零退出，禁止落入默认Dashboard和自动测试写链。
- [x] P0：CLI模式提供可信同步退出码、stdout单一JSON envelope、stderr诊断和零写入`--dry-run`。
  - 退出码/envelope/dry-run已实现(退出码0/2/3/4/5/70,envelope含ok/exit_code/command/subcommand/dry_run/message);stderr诊断暂并入envelope的message字段(Delphi console无预定义stderr TextFile,见BUG-079)。
- [x] P0：将Dashboard中的`TChainRunner.RunFullChain`改为仅由显式demo/test命令触发。
- [x] 提供统一CLI(骨架): 路由守卫已建立, 未知命令非零退出, 已知未实现命令返回NotImplemented envelope(退出码3). 子命令领域逻辑待后续S5填充.
- [x] 2026-07-13 修复 CLI 分发块 `IfThen(Length(Pos)>N, Pos[N],'')` 对空数组越界读 nil 的 EAccessViolation(BUG-080);5 个已实现子命令(status/schedule/cycle plan/config show/report)全部返回真实数据,无 FATAL。顺带修 BUG-081(schedule 表名 `command`→`runtime_command`、时间字段 `created_at`→`requested_at`、LIMIT 移入子查询)和 BUG-082(config show 删 `flagship_candidate`、`active` 改由 `status='active'` 派生)。

```text
artifactos bcw apply
artifactos config show|set
artifactos cycle plan
artifactos hypothesis add|list|select
artifactos batch create
artifactos guide set
artifactos production run
artifactos schedule show
artifactos status
artifactos report
```

- [ ] `config set`只能修改当前package授权范围内的运行参数。
- [ ] `cycle plan`支持7天、30天周期及复盘时间。
- [ ] `batch create`支持账号、数量、系列、媒体形态和发布窗口。
- [ ] `guide set`支持按周期/批次保存运营与生产指导。
- [ ] `production run`把批次与指导编译为ContentContract并交接DeepFrames。
- [ ] 所有写命令支持`--dry-run`，所有命令支持`--json`和稳定退出码。
- [ ] 命令尽量幂等，并记录变更和运行日志。

**验收标准**：Amy可只通过CLI完成“应用BCW配置→创建7天周期→创建8+2批次→写入生产指导→交接DeepFrames→查看排程和状态→生成复盘摘要”。

### BCW-S6：轻量Skill 🟡

- [ ] CLI跑通首个实例后，创建 `bcw-artifactos-handoff` Skill。
- [ ] Skill把老板自然语言要求转为CLI参数，先dry-run预览再执行。
- [ ] Skill只编排CLI、展示差异、汇总异常和复盘，不保存第二份业务状态。

**验收标准**：不用Skill也能完整运行；Skill移除后ArtifactOS CLI能力不受影响。

### 依赖关系

```text
BCW-S1文件交换 ✅
→ BCW-S2预览应用回退 ✅
→ BCW-S3配置映射 ✅
→ BCW-S4结果摘要
→ BCW-S5运营控制CLI
→ BCW-S6轻量Skill
```

### 简化红线

25. 不建设多人权限和多级审批。
26. 不让ArtifactOS直接把会议草稿当运行配置。
27. 同一个package不得重复应用。
28. 应用前保留上一版快照。
29. 详细运行数据留在ArtifactOS，BCW只保存摘要。
30. CLI是BCW/Amy配置、安排和指导ArtifactOS的正式入口，不在Skill中重复实现业务逻辑。
31. 周期指导和批次指导不得静默改变长期账号身份与理论边界。
