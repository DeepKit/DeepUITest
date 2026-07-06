# 主编台与可恢复契约交互

> **状态**：产品化设计基线（2026-07-06）
> **定位**：定义 InkFlow 如何用程序引导人类与 AI 讨论写作契约，避免聊天漂移、AI 写库遗漏和会话中断丢失。

---

## 1. 核心原则

1. **聊天不是唯一真相源**：自然语言只作为输入；生效结果必须落到结构化契约、人工决策和契约变更账本。
2. **作者只面对主编台**：默认交互入口是 `InkFlow 主编台`。后台角色可以多，但不要求作者理解或调度。
3. **AI 只提出候选**：AI 可以抽取、总结、回读、生成草案；不能直接确认契约、写 accepted canonical 或绕过质量门禁。
4. **程序驱动 AI**：程序创建任务、校验 AI 输出、决定下一步状态；AI 不自主管理流程。
5. **每次确认即时保存**：作者确认后，必须原子写入 human decision、contract changelog、契约版本和 source hash。
6. **未确认不生效**：pending / proposed / awaiting_confirm 的意见不得进入 prompt、draft、accepted 或 export。
7. **局部修改必须有作用域**：全书基线、卷/部、章、shot 的修订不能互相偷改；下游过期必须显式标记。

---

## 2. 前台角色

作者日常只需要理解以下角色：

| 前台角色 | 出现场景 | 作者动作 |
|----------|----------|----------|
| 主编台 | 唯一默认入口，提示当前步骤和待确认事项 | 用自然语言表达意见 |
| 资料官 | 导入写作指南、大纲、素材时 | 确认源文件优先级或冲突处理 |
| 契约官 | 系统回读写作规则时 | 确认、补充、驳回系统理解 |
| 审稿官 | 正文生成后 | 判断是否接受建议 |
| 封板官 | 契约确认、正文 accept、版本锁定时 | 明确确认或退回 |
| 恢复官 | 会话中断或任务失败后 | 继续、修改、取消上次未完成事项 |

前台不得要求作者选择 `DecisionSessionHost`、`ContractSteward`、`Gatekeeper` 等内部角色。

---

## 3. 后台角色

后台角色服务架构边界和审计，不默认暴露给作者。

| 后台角色 | 代码名 | 职责边界 |
|----------|--------|----------|
| 流程主持人 | `WorkflowConductor` | 读取状态、选择下一步角色、提交状态机；不直接改契约或正文 |
| 决策会话主持人 | `DecisionSessionHost` | 管理自然语言意见、AI 解析、回读确认、断点续接 |
| 源料管理员 | `SourceLibrarian` | 导入源文件、计算 hash、标记来源优先级和 stale |
| 契约抽取员 | `ContractExtractor` | 从源文档和人类意见生成 proposed contract patch |
| 契约管家 | `ContractSteward` | 管理元契约、卷/部契约、章契约、shot 契约版本和状态 |
| 封板管理员 | `LockManager` | 执行 confirmed / locked / superseded 状态转换 |
| 真相保管员 | `CanonicalKeeper` | 维护 confirmed/locked 契约与 accepted 正文的唯一真相源 |
| 模型网关 | `ModelGateway` | 处理 LLM provider、timeout、retry、失败和原始响应审计 |
| 提示词编译器 | `PromptCompiler` | 只从 confirmed/locked 契约编译 prompt snapshot |
| 草稿生成器 | `DraftGenerator` | 生成候选正文，不产生 accepted |
| 闸门守卫 | `Gatekeeper` | 执行 schema、必填字段、禁区、状态机和质量阈值检查 |
| 连续性守卫 | `ContinuityGuard` | 检查人物、时间线、证据链、伏笔与回收是否漂移 |
| 评审团 | `ReviewJury` | 给出多维文学评审，不做最终封板 |
| 验收登记员 | `AcceptanceRegistrar` | 记录 accept / revise / reject 并提升合格稿为 canonical |
| 审计账本 | `AuditLedger` | 追加记录 AI 调用、人类决策、契约变更、运行事件和失败原因 |
| 断点续接器 | `RecoveryManager` | 从 DB 恢复未完成 job、DecisionSession、resume point、import finalize |
| 导入整理员 | `ImportCurator` | 处理指南目录和已有稿导入，生成 manifest、questions、contract draft |
| 交付发布器 | `ExportPublisher` | 只从 accepted canonical 导出 |
| 阈值回放员 | `ThresholdReplayer` | 回放质量阈值和门禁候选，验证是否放过坏稿 |

`WorkflowConductor` 必须做成表驱动状态机或薄调度层。它不能成为上帝对象，不能绕过 `Gatekeeper`、`ContractSteward`、`CanonicalKeeper` 或 `AuditLedger`。

---

## 4. 作者低负担流程

复杂角色对作者包装成 4 个流程：

1. **读材料**：主编台说明读入哪些文件、发现哪些冲突、哪些源文件过期或缺失。
2. **定规则**：契约官回读“我理解为……”，作者只确认价值判断。
3. **出稿与审稿**：写手生成，审稿官总结合格点、跑偏点、建议动作。
4. **封板或返工**：作者只做 `确认`、`修改意见`、`退回重写`、`稍后`。

人类必须介入：

- 第一次导入指南后确认文档优先级和写作宪法。
- 全书元契约封板。
- 每章章级契约首次确认。
- AI 发现冲突、缺口、来源优先级无法判断。
- 正文进入 accept / reject / revise。
- 源文档 hash 变化导致契约 stale。
- AI 连续解析失败或置信不足。

人类不应介入：

- schema 校验、prompt 编译、AI timeout / retry、hash 记录、调用日志、阈值回放、中间候选状态流转、已确认契约的机械继承。

---

## 5. DecisionSession

`DecisionSession` 是一次可恢复的人类决策会话。它不是聊天记录，而是结构化状态机。

建议状态：

```text
collecting
→ ai_parsed
→ awaiting_confirm
→ confirmed
```

异常状态：

```text
needs_human
retryable_failed
stale
cancelled
```

最小字段：

```text
decision_session_id
project_id
scope_type            # book / volume / part / chapter / shot / review / import
scope_id
target_type
target_id
status
human_text            # 作者自然语言原话
parsed_patch_json     # AI 解析出的结构化变更
readback_text         # 回读给作者确认的话
source_hashes
before_hash
after_hash
created_at
updated_at
```

规则：

- 同一 target 同时只能有一个 active DecisionSession。
- `awaiting_confirm` 必须能完整恢复。
- source hash 变化后必须转 `stale`，不得直接确认。
- 作者一句“确认”只在当前唯一 awaiting_confirm 会话存在时有效。
- `confirmed` 时必须原子写入 `writing_human_decisions`、`writing_contract_changelog`、新契约版本和 source hash。

---

## 6. ScopedDecisionSession

全书不要求一次讨论死。第一次只封 `BookContract` 基线，后续用带作用域的 `ScopedDecisionSession` 优化卷/部/章/shot。

层级：

```text
BookContract
  → VolumeContract
    → PartContract
      → ChapterContract
        → ShotContract
          → PromptSnapshot
          → Draft
          → AcceptedCanonical
```

作用域修订字段：

```text
scope_type            # book / volume / part / chapter / shot
scope_id
base_contract_version
change_type           # refine / override / split / defer / reject
affected_scopes_json
stale_downstream_json
```

规则：

- 全书红线不能被章级讨论覆盖。
- 章级可以细化，但不能反向污染全书类型定位、POV、禁区和硬质量标准。
- 局部修改必须做影响分析；例如第 25 章打火机回收改动必须标记第 24/26 章和证据链受影响。
- 已生成 prompt、draft、review 若依赖旧契约，必须标记 stale。
- 已 accepted 正文不得原地改；必须新建 revise run。

---

## 7. AI 到程序的防卡约束

AI 不能直接写 SQL 或生产表。它只能返回 schema 化草案：

```json
{
  "scope_type": "chapter",
  "scope_id": 25,
  "change_type": "refine",
  "must_land": ["操作员 ID 指向李芷涵", "公开回执反查后台审计链", "账户状态进入注销链"],
  "forbidden": ["第25章集中回收打火机"],
  "carry_to_next": ["打火机情感回收延后到第26章"],
  "source_refs": ["04_写作大纲.md#第25章"]
}
```

写库前必须经过：

1. JSON / schema 校验。
2. 来源覆盖检查。
3. 上下层契约冲突检查。
4. AI 回读确认。
5. 人类明确确认。
6. 事务写库。
7. 写后审计。

AI 输出三次无法过校验时，DecisionSession 转 `needs_human`，主编台只问作者一个窄问题，不扩大成人工填表。

---

## 8. 验收口径

交互式契约机制通过标准：

- 未确认意见不会进入 prompt。
- source hash 变化能阻断旧确认。
- 会话中断后能恢复到 `awaiting_confirm`。
- 同一 target 不允许两个 active DecisionSession 并行。
- 局部修订能标记 affected scopes 和 stale downstream。
- AI 解析失败不会污染生产契约。
- confirmed 决策都有 human decision、contract changelog、before/after hash。
- 已 accepted 正文只可通过 revise run 修改。
