# Ink v2 场景优先生产架构修正案

> **状态**：作者已裁定，2026-07-14 生效
> **适用系统**：`D:/_Progs/02Business/Writer/ink/`（Ink 第2版）
> **不适用系统**：旧 `inkflow/`；旧目录只作历史知识与回归不变量参考
> **优先级**：本修正案是作者裁定法源；工程细节由当前 `design.md` 与 `implementation-contract.md` 落实
> **实现状态**：设计已生效；现有代码和 `ink/sql/schema.sql` 仍以 shot 为中心，必须通过 `migration-plan.md` 迁移落实，不能把“已裁定”误写成“已实现”
> **正式决策记录**：`common/docs/decisions/D-25-scene-first-authority.md`

---

## 1. 修正目的

旧 Ink v2 以 shot 为生成、评审、修订和封版原子。该设计有利于局部重试，但会带来：

- 局部最优稿件拼成场景后失去统一呼吸；
- 单 shot 无法完整评价人物选择、场景压力和情绪转折；
- 多候选逐 shot 取优容易形成“弗兰肯斯坦章节”；
- 契约被迫细化成逐段施工图，抑制人物临场反应和文学创意；
- AI 可以通过局部 revision 间接改变已接受章节的整体效果。

本修正案将正式权威原子从 shot 升级为 scene，同时保留 shot 作为场景内部的非权威工作切片。

---

## 2. 权威单位层级

| 层级 | 定位 | 正式权威 |
|---|---|:---:|
| Shot | Scene 内部的生成切片、上下文切片、诊断锚点或流式断点 | 否 |
| Scene | 最小正式生成、修改、评审、版本、回滚和封版单位 | 是 |
| Chapter Candidate Branch | 由有序 Scene Revision 组成的完整章节候选；文学选优单位 | 是 |
| Chapter Snapshot | 冻结所选 Scene Revision 序列后的章节正式版本；导出权威 | 是 |
| Volume / Book | 人物弧线、主题、伏笔、节奏和长程一致性审计单位 | 是 |

规范性表述：

> Shot 帮助 AI 工作；Scene 决定正文是什么；Chapter Candidate 决定哪一篇更好；Chapter Snapshot 决定正式发布什么。

---

## 3. 数据库唯一真相源

### 3.1 权威边界

- 数据库保存所有有效事实、有效契约、正文 revision、候选分支、评审结果、返工决策、激活关系和正式章节快照。
- 人类原稿、写作指南、历史稿件和参考材料可以保存在文件系统，但必须在数据库登记资产 ID、路径、内容 hash、类型、版本和权威角色。
- Markdown、DOCX、PDF 和网页报告都是数据库正式快照的派生物，不得反向覆盖数据库。
- “数据库没有记录”表示 `unknown / unregistered`，不自动表示“不存在”。新事实必须经过事实认定流程入库。

### 3.2 正文权威

- 生产正文的权威文本是不可变的 `scene_revision.text`。
- 正式章节的权威不是“动态读取所有 Scene 当前版本”，而是冻结的 `chapter_snapshot`。
- 导出只能读取 active chapter snapshot。
- 已批准或已封版 Scene 不得原地修改；所有变化必须创建新 Scene Revision。

---

## 4. Scene 与内部 Shot 的关系

- 一个 Scene 可以包含零个或多个内部 Shot。
- 内部 Shot 可用于局部生成、局部重试、问题定位和上下文窗口管理。
- 内部 Shot 不拥有独立正式封版权、独立 accepted 状态或独立替换章节正文的权限。
- 即使只修改一个内部 Shot，提交结果也必须形成新的完整 Scene Revision，并重新通过 Scene 级检查。
- 内部 Shot 的拆分、合并、重排不改变旧 Scene Revision；新的结构属于新 Scene Revision 的内部拓扑。

---

## 5. 契约层级

契约的目标是“守住事实与人物因果，同时保留文学发现空间”，不得退化为禁止清单或逐段施工图。

### 5.1 Scene Contract 四个正文层

1. `hard_constraints`
   - 时间、地点、人物状态、知情边界、已发生事实、必要因果、项目红线；
   - 违反即失败。
2. `source_dna`
   - 从人类原稿提取的创作机制，如身体化职业判断、人物压力下的行为模式、叙述距离和信息释放方式；
   - 提取模式，不复制动作、顺序、措辞或原稿骨架。
3. `soft_goals`
   - 场景功能、人物变化、关系变化、情绪引力、信息策略、悬念意图和退出效果；
   - 偏离不自动淘汰，必须评估文学收益。
4. `creative_openings`
   - 明确哪些动作、对话、感官细节、配角反应、意象和实现路径由正文自由发现；
   - 每个 Scene Contract 至少有两个具体开放口。

### 5.2 来源证据层

每条硬约束和关键 DNA/软目标必须记录：

- 来源资产与版本；
- 来源锚点；
- 权威等级；
- 提取置信度；
- 冲突解决记录；
- 删除该条款会造成的风险。

### 5.3 契约减法原则

- 硬约束原则上控制在 5—10 条；
- 软目标原则上控制在 2—5 条；
- DNA 原则上控制在 2—5 条；
- 不得用修辞数量、固定段落位置、固定台词或固定动作作为文学 KPI；
- 删除后不会造成事实、人物或因果风险的条款，不得留在硬约束层。

---

## 6. 契约架构师与契约复审师

### 6.1 契约架构师

职责：

1. 冻结输入资料的版本和 hash；
2. 分别提取事实、因果与原稿写作 DNA；
3. 建立来源冲突表；
4. 起草 Scene Contract；
5. 执行条款分类、减法和创意空间自审；
6. 提交复审并根据意见修订。

契约架构师不能批准自己的契约。

### 6.2 多模型契约复审师

- 同一门使用目的相近、完整职责相同的复审专家；
- 差异主要由不同 LLM 家族产生，不把责任拆成互不覆盖的碎片角色；
- 各模型独立复审，不看其他模型结论；
- 复审师只能输出 `keep / soften / split / delete / add_source / needs_human`，不能直接改库；
- 事实冲突或来源不支持的重大问题必须阻断；
- 文学偏好分歧不得被多数票自动升级为硬约束。

### 6.3 契约状态

```text
draft
→ self_checked
→ under_review
→ revision_required | human_resolution_required | approved
→ active
→ amendment_proposed
→ superseded
```

同一 Scene 同一时刻只能有一个 active contract version。

---

## 7. 样本和指导卡

- 每个 Scene 不强制额外生成探针样本。
- 第9步首批正式候选本身是首要运行时探针。
- 额外短探针只在新契约模板冷启动、重大契约修改、连续双败、候选高度同构或复审持续分歧时触发。
- 完整最佳稿和完整负面稿不得默认注入生成 Prompt。
- 最佳示例应蒸馏为 `guidance_card`：技法、适用条件、边界条件、反照抄规则和替代实现。
- 负面样本应蒸馏为 `anti_pattern_card`：失败症状、失败原因和修复方向；原始失败文本主要供诊断器和复审师查看。
- 指导卡必须按故障签名和场景标签检索，每轮限制加载数量，并记录使用次数、冷却和过期信息。

---

## 8. 章节候选与文学选优

### 8.1 候选定义

流程中的“一篇稿件”是完整 Chapter Candidate Branch，不是单个 Scene，更不是单个 Shot。

每个候选分支必须绑定：

- outline version；
- contract version；
- world/fact snapshot；
- 有序 Scene Revision 序列；
- prompt/context snapshot；
- 生成模型与策略；
- 所用 guidance cards。

### 8.2 第9—14步

1. 第9步生成两个完整章节候选分支。
2. 每个候选内所有必要 Scene 逐一通过契约符合性门和事实门；完整章节再通过基础连续性门。
3. 首批两个候选中：
   - 0 篇过线：不得进入第12步，返回第9步；
   - 1 或 2 篇过线：进入第12步补稿；
   - 后续生产轮中若同一大纲和契约作用域已累计 3 篇有效候选，可直接进入选优。
4. 第12步默认补充 3 个完整章节候选，每个生产轮最多补一次。
5. 文学选优入口必须同时满足：
   - 有效过线稿数量不少于 3；
   - 候选之间存在实质性文学差异；
   - 至少一篇达到文学质量绝对门槛。

### 8.3 文学门槛

不得只按平均分选“最不差”的稿件。正式候选必须：

- 无严重文学否决项；
- 至少有一项由具体文本证据支持的杰出性；
- 完成章节必要叙事功能。

非共识但有明确文本证据支持的候选进入“少数冠军”保护，不得仅按多数票淘汰。

---

## 9. 返工与契约修订

每次失败先做快速归因；同一 Scene 重复失败、候选持续同构或准备升级上游时才做深度归因。

可能的责任层：

- fact source；
- contract gap；
- contract overconstraint；
- outline weakness；
- writer drift；
- candidate similarity；
- context compilation；
- reviewer false positive；
- model failure；
- unknown。

只有根因位于契约层时才增删契约：

- 缺少权威事实边界：增加硬约束；
- 漏掉原稿创作机制：增加 DNA；
- 缺少叙事方向：增加软目标；
- 创意窒息或候选同构：软化/删除方法性条款，增加开放口；
- 文笔、节奏执行、评审误杀、大纲无戏剧张力等问题不得通过堆契约禁令修复。

优秀偏离不能直接改契约，必须先形成 amendment proposal，经架构师修订和复审后生成新版本。

---

## 10. AI 防乱改

- AI 无权原地更新已存在的 Scene Revision 文本；
- AI 只能在有效返工任务下创建 candidate revision；
- 写入必须携带目标 Scene、预期父 revision、契约版本、允许修改范围、原因和 actor；
- 预期父 revision 与数据库 active revision 不一致时，写入失败；
- 生成新 revision 不等于激活；
- 激活、替换和章节封版必须由独立状态迁移和数据库事务完成；
- 文件修改、无记录 SQL 或导出物回写均不得改变正式稿。

---

## 11. 目标数据模型

至少需要以下权威实体：

```text
writing_scenes
writing_scene_contracts
writing_scene_revisions
writing_scene_internal_shots        -- 可选、非权威
writing_chapter_candidate_branches
writing_branch_scenes
writing_chapter_snapshots
writing_chapter_snapshot_scenes
writing_guidance_cards
writing_revision_decisions
writing_contract_reviews
writing_contract_amendments
```

现有 `writing_shot_*` 表属于当前已实现的 shot 中心模型。迁移期间：

- 不得简单全局改名；
- 不得让 shot 与 scene 同时成为正文权威；
- 旧表只作为迁移来源或内部切片实现；
- Scene 权威链完成并验证前，不宣布新架构已经投产。

---

## 12. 文档一致性规则

从本修正案生效起：

1. `ink/` 是当前系统；根目录旧任务文档和旧 `inkflow/` 文档不得再被称为当前技术权威。
2. 旧文档中的“shot 级正式封版、shot 是正文最小权威、逐 shot 文学选优”均视为被本修正案取代。
3. 旧文档中的 `writing_shot_*` 表名仍可用于描述当前代码和迁移来源，不能用于描述目标架构。
4. 新代码、迁移、测试和流程图必须使用 Scene-first 目标模型。
5. 若其他文档与本修正案冲突，以本修正案为准，并应在发现后立即修订。
