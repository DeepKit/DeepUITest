# 主编台与可恢复契约交互（Shot 中心历史基线）

> **状态**：产品化设计基线；2026-07-14 已按 Scene-first 修正
> **定位**：定义 Ink 如何用程序引导人类与 AI 讨论写作契约，避免聊天漂移、AI 写库遗漏和会话中断丢失。
>
> **权威修正**：参见 [scene-first-authority-amendment.md](scene-first-authority-amendment.md)。正式局部契约作用域为 Scene；Shot 仅为 Scene 内部非权威执行切片。

---

## 1. 核心原则

1. **聊天不是唯一真相源**：自然语言只作为输入；生效结果必须落到结构化契约、人工决策和契约变更账本。
2. **作者只面对主编台**：默认交互入口是 `InkFlow 主编台`。后台角色可以多，但不要求作者理解或调度。
3. **AI 只提出候选**：AI 可以抽取、总结、回读、生成草案；不能直接确认契约、写 accepted canonical 或绕过质量门禁。
4. **程序驱动 AI**：程序创建任务、校验 AI 输出、决定下一步状态；AI 不自主管理流程。
5. **每次确认即时保存**：作者确认后，必须原子写入 human decision、contract changelog、契约版本和 source hash。
6. **未确认不生效**：pending / proposed / awaiting_confirm 的意见不得进入 prompt、draft、accepted 或 export。
7. **局部修改必须有作用域**：全书基线、卷/部、章、Scene 的修订不能互相偷改；下游过期必须显式标记。

---

## 2. 源文档规范化与过程文件

主编台只能在规范化源文档上工作，不能把零散聊天、临时笔记或半处理文件当长期真相源。

源文档分三类：

| 类别 | 例子 | 生命周期 |
|------|------|----------|
| 权威源文档 | 写作指南、大纲、人物小传、世界观设定 | 保留原文、hash、优先级和来源路径 |
| 过程文件 | `better.md`、临时优化记录、AI 审读草稿 | 只作为抽取和审计输入；处理完成后必须清空，只保留 processed manifest/hash 审计 |
| 生效契约 | BookContract、VolumeContract、PartContract、ChapterContract、SceneContract | 只能由 confirmed DecisionSession 写入 |

`better.md` 的规则：

- 它不是唯一真相源，也不是长期需求文档。
- 资料官可以读取它，提取候选条款、冲突、遗漏和建议。
- 已解决内容必须合并进权威源文档的原子条款或 confirmed contract。
- 合并后必须清空 `better.md`，并记录 processed manifest/hash。
- 后续 prompt、契约确认、生成测试不得直接引用已处理的 `better.md` 内容。

规范化流程：

1. **合并**：同一事实、同一写法要求、同一剧情约束只保留一个权威条款。
2. **去重**：重复条款合并 source_refs；相互覆盖条款保留版本关系。
3. **拆矛盾**：冲突条款不得静默择一，必须生成主编台选择题。
4. **原子化**：每条规则只表达一个可验证约束。
5. **落标识**：每个原子条款必须有稳定 ID、scope、severity、source_refs、source_hash、status。

原子条款最小字段：

```text
atomic_clause_id
project_id
scope_type              # book / volume / part / chapter / shot / source
scope_id
clause_type             # plot / character / world / style / quality / forbidden / process
severity                # hard / soft / diagnostic
text
source_refs_json
source_hashes_json
status                  # proposed / confirmed / superseded / rejected / stale
supersedes_clause_id
created_at
updated_at
```

未原子化条款不得进入契约 patch；未确认条款不得进入 prompt。

### 2.1 source coverage 与抽取完整性

source coverage 采用 **原子条款 × contract field** 矩阵。每个原子条款必须映射到一个或多个契约字段，或被显式标记为 `rejected` / `deferred` / `diagnostic`。每个必填 contract field 必须能反查到 confirmed atomic clauses 或人工确认的空值理由。

覆盖矩阵最小字段：

```text
coverage_id
project_id
atomic_clause_id
contract_scope_type      # book / volume / part / chapter / shot
contract_scope_id
contract_field_path      # e.g. BookContract.evidence_chain
coverage_status          # covered / gap / conflict / rejected / deferred
decision_session_id
created_at
updated_at
```

AI 抽取完整性采用 **双模型交叉抽取 + coverage gate**：

1. `primary` 抽取器生成原子条款候选。
2. `crosscheck` 抽取器独立抽取同一源文档。
3. 程序合并候选，按语义相似度和 source ref 去重。
4. 两边不一致、未映射条款、必填字段缺口进入 `coverage_status='gap'` 或 `conflict`。
5. coverage gate 未清空 blocking gap 前，不允许生成 confirmed contract patch。
6. 缺口裁决一律生成 1-8/0/9 选择题，不要求人类编辑结构化卡片。

`better.md` 清空后的 processed manifest 只记录审计元数据，不保留过程文件正文或摘要：

```text
process_manifest_id
source_path
content_hash
processed_hash
cleared_at
extracted_clause_ids
contract_patch_ids
decision_session_ids
```

## 3. 前台角色

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

## 4. 后台角色

后台角色服务架构边界和审计，不默认暴露给作者。

| 后台角色 | 代码名 | 职责边界 |
|----------|--------|----------|
| 流程主持人 | `WorkflowConductor` | 读取状态、选择下一步角色、提交状态机；不直接改契约或正文 |
| 决策会话主持人 | `DecisionSessionHost` | 管理自然语言意见、AI 解析、回读确认、断点续接 |
| 源料管理员 | `SourceLibrarian` | 导入源文件、计算 hash、标记来源优先级和 stale |
| 源文档规范员 | `SourceNormalizer` | 合并、去重、拆矛盾、原子化源文档条款，处理 `better.md` 生命周期 |
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

## 5. 作者低负担流程

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

## 6. 选择式对话协议

主编台默认使用选择式对话，降低人类认知负担，并防止自由聊天变形。

规则：

- 每次需要人类裁决时，主编台给出 1-8 个编号选项。
- `0` 固定表示返回上一步或退出当前选择，不写入生效契约。
- `9` 固定表示重新生成选项；系统必须保存本次选项集和 regenerate reason。
- 推荐项必须标记为 `recommended`，但不能替作者自动选择。
- 作者可以补充自然语言意见；补充意见先保存为 `human_text`，再由 AI/程序生成下一组选项，不直接生效。
- 同一个 `DecisionSession` 的选项集必须持久化，恢复时回放原选项，而不是让模型重新想一版。

选择项最小字段：

```text
option_set_id
decision_session_id
version
options_json             # 1-8
recommended_option
allow_back               # 0
allow_regenerate         # 9
regenerate_count
status                   # active / selected / superseded / cancelled
created_at
```

## 7. DecisionSession

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
option_set_json
selected_option
parent_decision_session_id
created_at
updated_at
```

规则：

- 同一 target 同时只能有一个 active DecisionSession。
- `awaiting_confirm` 必须能完整恢复。
- source hash 变化后必须转 `stale`，不得直接确认。
- 作者一句“确认”只在当前唯一 awaiting_confirm 会话存在时有效。
- `confirmed` 时必须原子写入 `writing_human_decisions`、`writing_contract_changelog`、新契约版本和 source hash。
- 若作者选择 `0`，会话回到上一步或 `collecting`，不得写 confirmed。
- 若作者选择 `9`，当前 option set 置 `superseded`，重新生成 1-8 个选项并保留审计。

---

## 8. 契约字段标准

字段标准按层级收敛，越上层越稳定，越下层越可操作。AI 可以提出字段值，程序必须校验字段完整性、来源覆盖和上下层冲突。

### 8.1 BookContract

全书基线封板字段：

- `identity`：标题、类型、目标篇幅、目标读者。
- `logline`：一句话核心承诺。
- `genre_positioning`：类型定位、竞品/标杆、不可越界方向。
- `narrative_voice`：POV、时态、叙述距离、语体边界。
- `hard_boundaries`：禁用事实、禁词、不可改设定、伦理/平台红线。
- `world_knowledge`：世界观事实、机构规则、技术/超自然规则。
- `character_bibles`：主要人物身份、欲望、恐惧、秘密、行为边界。
- `evidence_chain`：全书证据链、伏笔、回收责任。
- `motif_system`：母题、意象、重复方式和密度目标。
- `style_locks`：句式、节奏、粗粝度、对话密度、语言禁区。
- `quality_profile`：什么叫好、盲评口径、继续阅读目标、protected_roughness。
- `forbidden_directions`：全书不得写成的方向。
- `source_refs`：来源条款 ID 与 source hash。

### 8.2 VolumeContract

卷级字段：

- `volume_id`、`name`、`function`。
- `arc_goal`、`main_conflict`、`entry_state`、`exit_state`。
- `evidence_progression`、`character_arc_delta`、`motif_progression`。
- `pacing_target`、`required_turning_points`。
- `forbidden_repetition`、`source_refs`。

### 8.3 PartContract

部级字段：

- `part_id`、`name`、`local_goal`。
- `transition_function`、`required_reveals`。
- `emotional_curve`、`dependency_scopes`。
- `risk_notes`、`source_refs`。

### 8.4 ChapterContract

章级字段：

- `chapter_id`、`title`、`chapter_function`。
- `scene_hook`、`institution_action`、`character_cost`。
- `must_land`、`evidence_plant_or_payoff`、`sci_fi_or_world_anchor`。
- `chapter_end_crack`、`dialogue_anchor`、`sensory_anchor`。
- `pacing_shape`、`continuity_refs`。
- `anti_write`、`dependencies`、`source_refs`。

### 8.5 SceneContract

Scene 级字段按 Scene-first 契约四层表达；现有 5 张 shot 结构化表只作为迁移来源：

- `hard_constraints`：事实、人物状态、知情边界、必要因果和项目红线。
- `source_dna`：从人类原稿提炼的写作机制，禁止复制动作、顺序和措辞。
- `soft_goals`：场景功能、人物/关系变化、情绪引力和信息策略。
- `creative_openings`：明确留给正文发现的动作、对话、感官、意象和实现路径。
- `entry_state`、`exit_state`、`continuity_refs`、`source_refs`。
- 内部 shot task card 可由 SceneContract 编译，但不构成生效契约层。

## 9. ScopedDecisionSession

全书不要求一次讨论死。第一次只封 `BookContract` 基线，后续用带作用域的 `ScopedDecisionSession` 优化卷/部/章/Scene。

层级：

```text
BookContract
  → VolumeContract
    → PartContract
      → ChapterContract
        → SceneContract
          → PromptSnapshot
          → Draft
          → AcceptedCanonical
```

作用域修订字段：

```text
scope_type            # book / volume / part / chapter / scene
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

## 10. 下游 stale 传播规则

契约变化必须显式传播 stale，不允许旧 prompt、旧 draft 或旧 review 继续冒充当前结果。

传播矩阵：

| 变更层级 | 必须标记 stale 的下游 |
|----------|------------------------|
| BookContract | 全部 Volume/Part/Chapter/Scene 契约、prompt、draft、review、book check |
| VolumeContract | 本卷 Part/Chapter/Scene 契约、prompt、draft、review、book check |
| PartContract | 本部 Chapter/Scene 契约、prompt、draft、review、book check |
| ChapterContract | 本章 Scene 契约、prompt、draft、chapter review、book check |
| SceneContract | 本 Scene prompt、revision、jury、Scene review、chapter review、book check |
| source hash | 依赖该 source 的 atomic clauses、contract patch、DecisionSession、prompt snapshot |

规则：

- 上游 confirmed contract 变化后，下游必须记录 `stale_reason`、`source_contract_version`、`new_contract_version`。
- 依赖旧契约的 prompt snapshot 必须 supersede 后重编译。
- 依赖旧 prompt 的 draft/review 不得继续 accept。
- 已 accepted 正文不原地编辑；只能新建 revise run，旧 accepted 留审计。
- stale 传播是程序责任，不要求作者手动判断影响范围。

## 11. AI 到程序的防卡约束

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

## 12. 生成测试与覆盖决策

首次真实生成测试采用“两段式封板”：

1. 先完成 `BookContract` 全书基线封板，确认写作宪法、人物核心、证据链、风格锁和禁止方向。
2. 再运行前 6 章灰度生成，验证章级/shot 级契约、stale 传播、主编台交互负担、恢复点和质量门禁。

已定策略：

- source coverage 粒度使用 **原子条款 × contract field** 矩阵。
- AI 抽取 completeness 使用 **双模型交叉抽取 + coverage gate**。
- `better.md` 清空后的 manifest 记录 hash、处理时间、抽取条款 ID、contract patch ID 和 decision session ID，不记录过程文件正文或摘要。

## 13. 验收口径

交互式契约机制通过标准：

- 未确认意见不会进入 prompt。
- source hash 变化能阻断旧确认。
- 会话中断后能恢复到 `awaiting_confirm`。
- 同一 target 不允许两个 active DecisionSession 并行。
- 局部修订能标记 affected scopes 和 stale downstream。
- AI 解析失败不会污染生产契约。
- confirmed 决策都有 human decision、contract changelog、before/after hash。
- 已 accepted 正文只可通过 revise run 修改。
- `better.md` 处理后不再被 prompt 或契约确认直接引用。
- 冲突/遗漏裁决使用 1-8/0/9 选择式对话，恢复后选项集不漂移。
- source coverage gate 未清空 blocking gap 时，不得确认 BookContract 或进入前 6 章生成。
