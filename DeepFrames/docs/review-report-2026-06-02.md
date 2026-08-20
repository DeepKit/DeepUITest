# DeepFrames 三专家综合评价报告

**日期**: 2026-06-02
**评审范围**: 15 份规格文档 + README 索引
**评审方法**: 三位独立专家并行评审，按各自专业维度打分和发现问题

---

## 总体评分

| 专家 | 领域 | 评分 |
|---|---|---|
| 系统架构师 | 模块边界、数据库、状态机、可扩展性 | **8.2/10** |
| AI/Agent 工程师 | Agent 工作流、Prompt 工程、TTS/ASR、质量门控 | **8.2/10** |
| 视频/媒体工程师 | 渲染管线、视觉一致性、多平台、资产管理 | **7.8/10** |
| **综合** | | **8.1/10** |

## 一句话共识

> 这是一份在"单人单机桌面音视频生产工具"定位下**完成度很高的架构设计**，文档链版本化、Agent 分层、Worker 协议抽象、质量门控体系等核心决策经过深思熟虑。主要差距在于**运行时行为定义**（job 完成判定、返工路径、并发控制）和**关键实现细节**（Chromium 帧捕获方案、StepFun 模型能力验证、FFmpeg 编码参数）需要补齐。

---

## 三专家共同发现的问题（共识）

以下问题被两位或三位专家同时识别，可信度最高：

### 🔴 共识问题 1：job 与 job_step 的完成判定规则缺失

**发现者**: 架构师、AI/Agent 工程师

文档定义了 job 和 job_step 的状态机，但没有定义：一个 job 完成是否要求所有 step 都 done？部分 step failed 但降级完成时，job 状态如何判定？这直接影响断点续跑、质量门控和候选包导出的语义。

**建议**: 在 `12.db-state` 或新增 `16.runtime` 中定义 job 完成判定规则：所有 step done → job done；存在 failed step 但在降级容忍范围内 → job done + degraded flag；failed step 超出容忍范围 → job blocked_review。

### 🔴 共识问题 2：blocked_review 到 running 的返工路径未定义

**发现者**: 架构师、AI/Agent 工程师

状态图显示 `blocked_review → running` 但没有说明返工策略。返工策略（重跑整个 job / 重跑失败 step / 重跑特定 shot）对版本链、logical_key 和已生成资产的影响完全不同。

**建议**: 定义三种返工粒度及其对 version_no / logical_key 的影响。

### 🔴 共识问题 3：StepFun 模型/图像 API 能力未验证

**发现者**: AI/Agent 工程师、视频/媒体工程师

- stepfun-flash-3.5 能否稳定生成包含 audio（6 字段）+ visual（5 字段 + 嵌套）的复杂 JSON？
- StepFun image edit API 是否支持 img2img？输入分辨率限制？
- 画面描述 Prompt 模板（画风+主体+构图+光影+色调）对中文图像生成模型的有效性？

这三个假设如果任何一个不成立，系统需要在第一条生产链路就做架构调整。

**建议**: POC 第一优先级验证以上三点。为每个假设定义明确的通过标准（如 JSON 成功率 > 80%）。

### 🔴 共识问题 4：Chromium 帧捕获的实现方案未确定

**发现者**: 视频/媒体工程师（架构师也提到 Video IR Compiler 语言歧义）

文档定义了 timestamp-driven capture 策略，但没有说明：
- 使用 Chromium 的哪个 API（Puppeteer screenshot? CDP screencast? headless frame capture?）
- CSS animation 时序同步方案
- Chromium 版本锁定策略

这直接决定 HyperFrames 管线的可行性。

**建议**: 在 `04.video` 中增加"帧捕获实现方案"小节，确定 API 选择、时序控制方式和版本锁定策略。

### 🟡 共识问题 5：跨文档的运行时行为定义不够

**发现者**: 架构师、AI/Agent 工程师、视频/媒体工程师（各自从不同角度提出）

三位专家分别识别了以下运行时行为缺失：
- 架构师：并发控制策略、磁盘空间管理、错误传播与回滚边界
- AI/Agent 工程师：QA 与 Style Keeper 结果合并逻辑、Repair 的推断依据定义
- 视频/媒体工程师：帧序列中间存储策略、磁盘空间预检

**建议**: 新增 `16.runtime-运行时行为-runtime-behavior.md`，定义跨模块运行时交互规则。

---

## 各专家独有发现

### 架构师独有发现

| # | 严重度 | 发现 |
|---|---|---|
| 1 | 🟡 | `created_at` 时区策略在文档 09 和 12 之间不一致（09 说"本地或 UTC"，12 说"UTC"） |
| 2 | 🟡 | `logical_key` 变化时的缓存策略和复用判断未定义 |
| 3 | 🟡 | `deepframes_prompt_run` 表中 LLM 特有 token 字段和 TTS/ASR/Image 的维度字段混在同一张表 |
| 4 | 🟡 | 开发路线图 Phase 5 可拆为 5a（静默预览，不依赖音频）和 5b（带声成片，依赖 Phase 4） |

### AI/Agent 工程师独有发现

| # | 严重度 | 发现 |
|---|---|---|
| 1 | 🔴 | 缺少 Few-shot 示例管理策略——示例从哪来、如何按 preset 分类、如何版本管理 |
| 2 | 🟡 | QA Agent（deepseek-v4-pro）与 Worker Agent（stepfun-flash-3.5）的能力不对称可能导致系统性低分 |
| 3 | 🟡 | Repair + Retry 组合的最坏情况（最多 10 次 LLM 调用）未在成本和延迟预算内评估 |
| 4 | 🟡 | 缺少推理参数策略（temperature / top_p 按 Agent 角色区分） |
| 5 | 🟡 | TTS 451 审查改写的具体改写策略未定义（规则引擎还是 LLM？） |

### 视频/媒体工程师独有发现

| # | 严重度 | 发现 |
|---|---|---|
| 1 | 🔴 | Windows NTFS atomic rename 的非 POSIX 行为——目标文件已存在时需要 `MOVEFILE_REPLACE_EXISTING` |
| 2 | 🟡 | FFmpeg 编码参数未文档化（profile/level, preset, GOP, B 帧, 像素格式） |
| 3 | 🟡 | 帧序列中间存储策略缺失——15 分钟视频可能需要 13-135 GB 中间存储 |
| 4 | 🟡 | Chromium 字体渲染差异——建议自定义字体打包到 worker 目录 |
| 5 | 🟡 | 抖音码率范围偏保守（2-5 Mbps，建议 4-8 Mbps） |
| 6 | 🟡 | 候选包导出的文件系统多文件写入不是原子操作 |

---

## 最优设计判断

### 三专家共识

> **架构方向是最优的，但"最后一公里"的实现细节定义不够。**

具体而言：

1. **已做对的最优决策**（不需要改）：
   - Agent 分层架构（Splitter/Worker/Assembler/QA/Style Keeper）的职责边界
   - Video IR 后端无关抽象
   - Worker 协议 v0 的最小性（request/progress/result 三文件）
   - 文档链版本化（不可覆盖、只增不改）
   - 质量门控的分级设计（pass/warn/fail + 降级蔓延检测）
   - 音视频独立流水线、松耦合
   - Style Keeper 作为确定性规则引擎而非 LLM
   - 全局时间轴量化避免累计漂移

2. **需要补充的最优设计缺失**：
   - 运行时行为文档（job 完成判定、返工路径、并发控制、磁盘管理）
   - Chromium 帧捕获实现方案
   - FFmpeg 编码参数完整定义
   - StepFun 模型/API 能力的 POC 验证
   - Few-shot 示例管理和推理参数策略

3. **不需要改变的东西**（避免过度设计）：
   - 不需要引入消息队列、分布式调度、微服务
   - 不需要自动 prompt 调优、自动模型路由
   - 不需要预算拦截、成本控制
   - 不需要多租户、云部署

### 距最优设计的差距

| 方面 | 当前评分 | 最优可达 | 差距原因 |
|---|---|---|---|
| 架构方向 | 9.5/10 | 9.5-10 | 接近最优，方向完全正确 |
| 文档完成度 | 8.0/10 | 9.5 | 运行时行为和实现细节需要补充 |
| POC 验证 | 6.0/10 | 9.0 | 关键假设（StepFun 能力、Chromium 帧捕获）未验证 |
| **综合** | **8.1/10** | **9.5** | 补齐运行时文档 + POC 验证后可达 |

---

## 建议的行动计划

### Phase 0（工程启动前，1-2 天）

| # | 行动 | 优先级 | 产出 |
|---|---|---|---|
| 1 | 补充 job 完成判定规则和返工路径 | 🔴 | 更新 `12.db-state` |
| 2 | 确定 Chromium 帧捕获实现方案 | 🔴 | 更新 `04.video` |
| 3 | 统一 `created_at` 时区策略为 UTC | 🟡 | 更新 `09.engineer` |
| 4 | 补充 FFmpeg 编码参数 | 🟡 | 更新 `07.platform` |
| 5 | 新增 `16.runtime-运行时行为-runtime-behavior.md` | 🟡 | 新文档 |

### Phase 1（POC 验证，1 周）

| # | 验证项 | 通过标准 | 阻塞项 |
|---|---|---|---|
| 1 | stepfun-flash-3.5 生成 Worker 级复杂 JSON | 成功率 > 80% | Agent 工作流 |
| 2 | StepFun image edit API img2img 能力 | 可用且输出稳定 | 视觉一致性主策略 |
| 3 | 画面描述 Prompt 到图像生成的有效性 | 5/10 张图风格基本一致 | 视觉表达质量 |
| 4 | Chromium 逐帧捕获的时序精度 | 60 秒窗口偏差 < 50ms | HyperFrames 可行性 |

### Phase 2（基于 POC 结果调整）

根据 Phase 1 的验证结果决定：
- 如果 flash 模型 JSON 成功率 < 80%：考虑升级到 Pro 模型或简化输出 schema
- 如果 image edit 不可用：直接采用 prompt-only fallback，标黄灯
- 如果 Chromium 时序精度不足：考虑 JavaScript currentTime 控制

---

## 附录：各专家详细报告索引

| 专家 | 完整报告 |
|---|---|
| 系统架构师 | 见本文件"架构评审"部分（由 Agent 产出） |
| AI/Agent 工程师 | 见本文件"AI/Agent 评审"部分（由 Agent 产出） |
| 视频/媒体工程师 | 见本文件"视频/媒体评审"部分（由 Agent 产出） |

三位专家的完整评审意见已在本文件上方记录，此处只保留综合汇总。
