# DeepFrames Tasks

## 第二轮外部评价修复任务（2026-06-03）

> 来源：2026-06-03 外部评价与 `docs/review-三专家综合评价报告-expert-review.md` / `docs/review-report-2026-06-02-feasibility.md` 的后续一致性审查。临时评价输入已同步为本任务清单。

### P0 — 开工前必须补齐

- [x] **T1 Gate → 对象状态驱动矩阵**  
  在 `08.quality-质量门控-quality-gate.md` / `12.db-state-数据库与状态机-db-state.md` 中定义 Gate 1/2/3a/3b 的 `pass/warn/fail` 如何驱动 `source_document`、`script_document`、`shot_document`、`audio_manifest`、`video_ir`、`candidate_package`、job/step 状态变化。

- [x] **T2 accuracy_report 与 Gate 2 QA 独立数据契约**  
  在 `08.quality-质量门控-quality-gate.md` / `12.db-state-数据库与状态机-db-state.md` 中明确 `accuracy_report` 只检查 `script_document` 对 `source_document` 的忠实度，Gate 2 QA 只检查 `shot_document` 对 `script_document` / `accuracy_report` 的生产质量，并补充 JSON schema 与失败处理流程。

- [x] **T3 102C 资产清理策略细化**  
  在 `06.dist-内容分发-distribution.md` / `12.db-state-数据库与状态机-db-state.md` 中明确长期保留、短期保留、可清理、立即清理的资产分类，定义清理触发条件、保护白名单、日志与回收语义。

- [x] **T4 TTS 451 音频线闭环处理**  
  在 `05.audio-音频流水线-audio-pipeline.md` / `08.quality-质量门控-quality-gate.md` 中明确 TTS 451 发生在音频线内部，不原地改写 `shot_document`，只生成 `tts_text_variant`，由 Gate 3a 校验语义差异并决定 pass/warn/fail。

### P1 — 建议补齐，不阻塞首条链路

- [x] **T5 渲染后端许可证决策点**  
  在 `01.arch-系统架构-architecture.md` / `10.dev-roadmap-development-roadmap.md` 中明确 HyperFrames 优先、Remotion 后续；Remotion 商业许可复核 deadline 放在 Phase 5 末 / Phase 7 前。

- [x] **T6 content_type adapter 就绪诊断规格**  
  在 `01.arch-系统架构-architecture.md` 中补充未来 adapter 的 readiness check / readiness report 规格；当前仅对 `longform_zh_article` / `webnovel_zh` 启用内置诊断。

## 工程实现前最终校正（2026-06-03）

- [x] **F1 Gate / 状态机最终一致性**  
  修正业务对象 `done` 与资产 `ready` 的状态边界，补齐 `skipped`、`cancelled` 恢复、新增 `preprocess` job_type。

- [x] **F2 音频 / API 最终一致性**  
  修正 B站 AAC 采样率为 48kHz，loudnorm 改为双遍流程，TTS 451 全文统一为 `tts_text_variant` + Gate 3a 判定。

- [x] **F3 文档就绪度最终一致性**  
  补 README 历史评审索引、Phase 7 adapter/readiness、H.264/AAC 合规复核、DB 表契约与 UTC 时间策略。
