# DeepFrames 文档索引

本文档用于区分正式规格文档与历史评审材料，避免多套文档同时作为真相来源。

## 推荐阅读顺序

0. `00.quickstart-快速上手-quickstart.md` — 用户操作视角的端到端生产流程（新用户入口）。
1. `01.arch-系统架构-architecture.md` — 系统边界、战略基线、核心流水线和模块关系。
2. `ENGINEERING_HANDOFF.md` — 工程实现交接说明、Phase 1 启动任务、风险清单和验收脚本。
3. `09.engineer-工程化基础-engineering.md` — 工程结构、DB1/DB2/DB3、任务、状态、worker、测试。
4. `10.dev-roadmap-development-roadmap.md` — 按依赖顺序推进的开发阶段和验收口径。
5. 专项规格：
   - `02.api-阶跃星辰集成-step-plan-api.md`
   - `03.agent-Agent工作流-agent-workflow.md`
   - `04.video-视频流水线-video-pipeline.md`
   - `05.audio-音频流水线-audio-pipeline.md`
   - `06.dist-内容分发-distribution.md`
   - `07.platform-多平台适配-multi-platform.md`
   - `08.quality-质量门控-quality-gate.md`
6. 深化规范：
   - `12.db-state-数据库与状态机-db-state.md` — DB2 PostgreSQL 字段契约、状态机、事务边界，不是 SQL migration。
   - `13.worker-Worker协议-worker-contract.md` — 外部 worker 最小协议 v0。
   - `14.prompt-structured-output-Prompt结构化输出.md` — Agent 输出解析、校验、修复和重试策略。
   - `15.cost-usage-成本与用量-cost-usage.md` — 自用版用量记录与预算控制边界。
6. `11.e2e-端到端数据流实例.md` — 用一条完整示例验证字段和数据流是否能串起来。

## 历史评审材料

以下文件是历史评审、决策或优化记录，用于追溯设计来源；它们不覆盖上面的正式规格文档。

- `review-report-2026-06-02.md` — 第二轮三专家综合评价报告（架构师 8.2 + AI/Agent 8.2 + 视频/媒体 7.8 = 综合 8.1）。
- `review-report-2026-06-02-feasibility.md` — 第三轮实施可行性评审。
- `review-三专家综合评价报告-expert-review.md` — 2026-06-03 三专家综合评价报告。
- `review-report-2026-06-01.md` — 第一轮多专家评审报告。
- `review-decisions-2026-06-01.md` — 已完成的逐项决策记录。
- `better.md` — 8.4 → 9.5 的历史优化笔记。

如果历史材料与正式规格冲突，以正式规格为准；历史材料只用于理解为什么做出某个决策。

## 当前文档收敛状态

- DB1 保持 SQLite ConfigDB；DB2 / DB3 统一为 PostgreSQL。
- `Style Keeper` 是确定性规则引擎，不调用 LLM。
- Video IR Compiler 由 Delphi 主程序执行，render worker 只消费已编译的 Video IR。
- `accuracy_report` 是脚本级准确性报告；Gate 2 QA 结果写入质量门控记录。
- Worker 取消以 `CTRL-BREAK` 为主，`cancel_file` 为辅。
- StepFun（正文技术语境）与阶跃星辰（文档标题/元数据）是同一 provider 的不同称呼。

## 已确认战略决策索引

| # | 决策 | 状态 | 权威文档 |
|---|---|---|---|
| 1 | 双层产品定位：当前是中文长内容/文章/网文音视频候选包生产工具，长期愿景是通用 AI 音视频生产工具 | 当前实现 + 长期愿景 | `01.arch` |
| 2 | DeepFrames 以候选包为主；ArtifactOS / 发布系统负责最终标题、标签、简介、账号定位、排期和运营策略 | 当前边界 | `01.arch`, `06.dist` |
| 3 | 轻量 Provider 边界：当前只实现 StepFun，不做自动路由、fallback、多 Provider UI | 当前实现 | `02.api` |
| 4 | fake provider 工程主线 + StepFun prompt POC 验证支线并行 | 当前工程策略 | `03.agent`, `10.dev-roadmap` |
| 5 | VCL 是当前唯一正式实现，但业务核心 UI 无关 | 当前实现 + 预留 | `01.arch`, `09.engineer` |
| 6 | 定义 Accuracy Mode / Expressive Mode | 当前规范 | `03.agent` |
| 7 | 现在写 DDL / 状态机规范，不马上写 SQL migration | 当前规范 | `12.db-state` |
| 8 | 最小 Worker 协议 v0：字段和职责先定，传输细节 Phase 4 校准 | 当前规范 | `13.worker` |
| 9 | Prompt 输出采用 Extract / Normalize → Schema Validate → Repair / Retry | 当前规范 | `14.prompt-structured-output` |
| 10 | 自用版记录用量，但不做预算控制 | 当前规范 + 商业化基础 | `15.cost-usage` |
| 11 | 视觉一致性采用 Reference image / img2img → prompt-only fallback → human review / regenerate anchor | 当前规范 + 预留 | `04.video`, `08.quality` |
| 12 | HyperFrames 最小可靠性：frame_no 连续、frame_count 对齐、scene-level checkpoint、timestamp-driven capture | 当前规范 | `04.video` |
| 13 | 预留 content_type adapter | 预留 | `01.arch`, `12.db-state` |
| 14 | 商业化后置，只预留 usage / 合规评估基础 | 后置 | `01.arch`, `15.cost-usage` |
| 15 | 预留异步审阅包：Phase 1-4 候选包即审阅包，Phase 5+ HTML review package | 预留 | `06.dist`, `08.quality` |
| 16 | 记录生产内反馈，不做自动学习 | 当前规范 + 后置学习 | `08.quality`, `12.db-state` |
