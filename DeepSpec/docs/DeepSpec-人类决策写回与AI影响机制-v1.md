# DeepSpec 人类决策写回与 AI 影响机制 v1

> 日期：2026-05-14  
> 状态：当前产品机制定稿  
> 主题：用户在 DeepSpec 页面上做需求决策后，如何写入开发文档，并影响用户自己的 AI 后续需求撰写。

---

## 1. 核心结论

DeepSpec 第一层不应只让用户“看图”和“复制 Prompt”，而应能把页面决策写入 B 后，通过成熟的框架 LLM 模块继续完善 B。

必须先区分两个目录层：

```text
A = 用户原有需求文档目录 / 原始项目材料
B = DeepSpec 生成的规格化需求文档目录，默认在项目根目录 .deepspec/
```

A 是输入层，保留用户原来的格式、组织方式和写作习惯。

B 是 DeepSpec 规格层，由 DeepSpec 生成 YAML、HTML、决策、AI 上下文、提示词等文件，不要求和 A 的格式一致。

事实源关系：

```text
A = 原始输入材料 / 证据层
B = DeepSpec 内部的规格化事实源 / 审阅层 / 决策层
```

DeepSpec 内部以 B 为规格化事实源，但 B 中的每个重要节点、问题和决策都必须能追溯到 A。

B 的总入口：

```text
.deepspec/project-spec.yaml
```

`project-spec.yaml` 是 B 的总事实索引，负责引用：

- 三棵树；
- 来源证据；
- 文档问题；
- 人类决策；
- AI 上下文；
- A -> B 生成 / 审阅提示词；
- HTML 审阅页输出。

`project-spec.yaml` 不保存全部事实内容，只保存：

- 项目元信息；
- 当前 DeepSpec 版本；
- 输入目录 A 的摘要；
- 输出目录 B 的文件引用；
- 当前扫描时间；
- 摘要指标；
- 当前状态；
- 最近决策和问题摘要。

完整内容分散保存在 `trees/`、`issues/`、`decisions/`、`prompts/`、`html/` 等目录。

HTML 不是事实源。HTML 是由 B 中 YAML / 模型生成的交互审阅层，可以删除后重新生成。用户在 HTML 上做的任何决策，必须写回 `.deepspec/decisions/*.yaml/.md`。

HTML 页面点击不是直接写入事实。第一层采用：

```text
HTML 点击
  ↓
JS Bridge 传给 DeepShell / DeepSpec
  ↓
生成候选 Decision Record
  ↓
用户确认
  ↓
写入 .deepspec/decisions/*.yaml/.md
```

HTML 页面不直接写 YAML，也不保存事实状态。

B 的版本策略：

```text
当前工作集 + 历史摘要
```

默认保留当前工作集，并记录每次扫描的摘要、差异和决策变化；不默认完整保留每次扫描的全部 B 文件，避免体积膨胀。

更准确的机制是：

```text
DeepSpec 读取 A 中的当前文档状态
  ↓
用户在页面上做需求决策
  ↓
DeepSpec 将决策写入 B，即 .deepspec 下的可追溯规格化文档 / 决策文档
  ↓
生成给框架 LLM 模块和用户自己 AI 使用的上下文、规则和修订 Prompt 模板
  ↓
后续 B 生成 / 审阅任务必须受这些决策约束；用户的 Claude / Cursor / Codex / IDE AI 也可读取这些导出内容
```

一句话：

**页面决策不是 UI 状态，而是需求事实的一部分。**

---

## 2. 产品边界

允许：

- 用户在 HTML / DeepShell 页面上确认、否定、澄清、补口、裁决冲突；
- DeepSpec 把这些决策写入 `.deepspec` 下的规格化需求目录和结构化决策文件；
- DeepSpec 生成给框架 LLM 模块和用户自己 AI 使用的任务上下文、Prompt 模板、规则片段、文档片段；
- DeepSpec 重新扫描后，让 accepted decision 影响三棵树和后续图表。

谨慎允许：

- 第二层生成对 README、PRD、设计文档、AI 规则文件的 Patch 建议；
- 第二层由用户确认后应用 Patch；
- 生成 `AGENTS.md`、`CLAUDE.md`、Cursor Rules 的规则草稿。

不允许：

- DeepSpec 未经用户确认自动覆盖原始开发文档；
- DeepSpec 把自己变成主聊天工具，替代用户原 AI；
- DeepSpec 直接接管用户 IDE / CLI 的需求生成流程；
- 把 AI 推断写成用户已确认事实。

---

## 3. 三层写回模型

人类决策应写成三层产物，默认都位于 B 目录：

```text
1. 决策事实层
   .deepspec/decisions/requirement-decisions.yaml

2. 人类审阅层
   .deepspec/decisions/requirement-decisions.md

3. AI 消费层
   .deepspec/decisions/ai-requirement-context.generated.md
   .deepspec/prompts/*
   .deepspec/llm/*
```

注意：

```text
B -> A 的需求校正 Prompt、Patch 建议、A 未同步队列和同步验证属于第二层付费能力。
```

### 3.1 决策事实层

机器可读，是 DeepSpec 的权威增量事实源。

建议路径：

```text
.deepspec/decisions/requirement-decisions.yaml
```

### 3.2 人类审阅层

人类可读，便于团队和未来 AI 理解决策。

建议路径：

```text
.deepspec/decisions/requirement-decisions.md
```

### 3.3 AI 消费层

给用户自己的 AI 后续需求撰写使用。

建议路径：

```text
.deepspec/prompts/decision-context.md
.deepspec/prompts/decision-rewrite-prompt.md
.deepspec/decisions/ai-requirement-context.generated.md
```

长期规则先生成草稿，不默认写入 A：

```text
.deepspec/prompts/agents-draft.md
.deepspec/prompts/claude-draft.md
.deepspec/prompts/cursor-rules-draft.md
```

用户明确确认后，才可由用户自己的 AI 或 Patch 建议把这些内容合并回 A 中的 `AGENTS.md`、`CLAUDE.md` 或 Cursor Rules。

其中 Patch 建议和合并回 A 属于第二层代码与需求校正能力；第一层只保留 B 内部决策、AI 上下文和审阅提示词。

---

## 4. 决策类型

页面决策至少支持以下类型：

| 决策类型 | 用途 | 后续影响 |
|---|---|---|
| 确认 confirm | 确认某节点或关系是正确需求 | 提升置信度，作为后续 AI 事实。 |
| 否定 reject | 说明某节点是误解、过时、不做 | 后续 AI 不应再写回当前范围。 |
| 澄清 clarify | 把模糊表达变成明确表达 | 后续需求撰写采用澄清后的定义。 |
| 补口 gap_fill | 补充缺失规则、异常、权限、视图、模块 | 后续 AI 按补充内容改文档。 |
| 冲突裁决 resolve_conflict | 多份材料互相冲突时选定准事实 | accepted decision 优先于冲突原文。 |
| 范围决策 scope | 明确做 / 不做 / 本期 / 后续 | 防止 AI 把未来范围写进当前版本。 |
| 优先级 priority | P0 / P1 / P2 / 后续 | 影响 Roadmap、任务拆分和文档排序。 |
| 术语归一 terminology | 统一同义词、命名、领域对象 | 后续 AI 必须使用统一术语。 |
| 视图归属 view_mapping | 决定功能由哪个页面、区域、入口承载 | 影响 UI 说明和视图树。 |
| 模块归属 module_mapping | 决定功能由哪个模块、服务、能力域承载 | 影响设计文档和模块树。 |
| 权限决策 permission | 明确谁能看、做、改、审批 | 影响角色权限矩阵和验收点。 |
| 状态 / 规则决策 rule | 明确状态、触发条件、业务规则 | 影响状态图、规则表和验收标准。 |

---

## 5. 决策记录格式

每条决策必须可追溯、可被 AI 使用、可被后续决策覆盖。

建议 YAML：

```yaml
- id: RD-20260514-001
  type: resolve_conflict
  status: accepted
  title: "模块树不等同于代码目录树"
  decision: "模块树表示需求层面的实现组织投影，不用于验证当前代码结构一致性。"
  rationale: "DeepSpec 第一层只处理人类需求表达，代码实现一致性属于第二层。"
  target_nodes:
    - tree: module
      path: "DeepSpec / 三棵树 / 模块树"
  source_refs:
    - path: "docs/DeepSpec-第一层图表体系定稿-v2.md"
      note: "三棵树定义"
  affected_requirements:
    - "REQ-TREE-001"
  affected_views: []
  affected_modules:
    - "MOD-SPEC-PROJECTION"
  conflicts_resolved:
    - "C-20260514-002"
  supersedes: []
  priority: P0
  release: "v0.1"
  decided_by: "human"
  decided_at: "2026-05-14"
  confidence: high
  ai_instruction: "后续撰写需求时，必须把模块树描述为需求层实现组织投影，不要把它等同于代码目录结构。"
```

必需字段：

| 字段 | 作用 |
|---|---|
| `id` | 决策可引用、可追踪。 |
| `type` | 区分澄清、补口、裁决、范围等语义。 |
| `status` | proposed / accepted / rejected / superseded / rolled_back。 |
| `decision` | 人类确认后的准事实。 |
| `rationale` | 为什么这样定。 |
| `target_nodes` | 影响哪些功能树、模块树、视图树节点。 |
| `source_refs` | 原始材料和证据。 |
| `affected_*` | 影响面。 |
| `supersedes` | 支持后续决策覆盖旧决策。 |
| `ai_instruction` | 给后续 AI 的明确写作约束。 |

最关键字段是：

```text
decision + rationale + source_refs + ai_instruction
```

---

## 6. AI 后续撰写优先级

用户自己的 AI 后续写需求时，应按以下优先级读取上下文：

```text
1. accepted requirement decisions
2. .deepspec 中的三棵树和当前文档状态总览
3. .deepspec 中由决策派生的 AI context / A -> B 审阅提示词
4. A 中的原始 README / 需求文档 / 设计文档 / AI 规则文件
5. rejected / superseded decisions 只作为历史参考，不能作为当前事实
```

冲突规则：

```text
当原始文档与 accepted decision 冲突时，以 accepted decision 为准。
当 generated 文档与 accepted decision 冲突时，以 accepted decision 为准。
当两个 accepted decision 冲突时，必须提示人工裁决，不能自行合并。
```

决策覆盖策略：

```text
当前规格判断 = A 的解析结果 + B 中 accepted decisions 覆盖层
```

用户做决策后，不必等 A 被自己的 AI 修改完成，三棵树就可以显示决策覆盖后的当前规格判断。

但界面必须标注：

- 哪些内容来自 A 的原始文档；
- 哪些内容来自 B 的 accepted decision；
- 哪些 decision 尚未同步回 A；
- 哪些 A 中旧描述已被 B 的 decision 覆盖。

三棵树节点应显示来源层级标签：

```text
A:原文解析
B:人工决策
B:AI推断
B:生成摘要
```

来源层级标签必须参与筛选：

```text
只看 B:人工决策
只看 B:AI推断
只看 A 未同步
只看 A 有旧描述
```

`B:AI推断` 可以进入当前规格图表，但必须标记为低置信 / 待确认，不能覆盖人工决策。

当 A 与 B 冲突时：

```text
主视图显示 B 的当前规格判断；
同时标记 A 未同步 / A 有旧描述；
详情页展示 A 的旧描述、B 的 accepted decision、覆盖理由和建议同步方式。
```

`A 未同步` 在第一层作为状态标签显示。第二层必须生成专门待办队列：

- 决策已经在 B 中成立；
- A 中原始文档尚未同步；
- 用户可以集中生成 Prompt；
- 能稳定定位时生成文件级 Patch；
- 同步后重新扫描，验证 A 是否吸收了 B 的决策。

Patch 建议属于第二层，分两级：

1. 建议段落：默认生成，说明应写入 A 的内容，但不强行绑定文件位置；
2. 文件级 Patch：当 DeepSpec 能稳定定位 Markdown、AI 规则或设计文档位置时，再生成具体 Patch 建议。

Context Pack 生成原则：

```text
以 B 为主，按需引用 A。
```

也就是说，给用户 AI 的上下文包应优先包含 `.deepspec` 中的 accepted decisions、三棵树、当前文档状态和问题建议；只有需要证据、原文语境或消解冲突时，才引用 A 中的原始来源片段。

---

## 7. 页面交互

当前文档状态总览图和节点详情页都应支持决策，但职责不同。

首页只做轻决策：

- 确认为正确；
- 标为不清晰；
- 标为冲突；
- 标为缺口；
- 标为待确认；
- 进入详情决策；
- 生成提示词要点。

详情页做结构化决策：

- 选择决策类型；
- 填写人类判断；
- 选择影响范围；
- 绑定来源证据；
- 生成 `ai_instruction`；
- 预览将写入的决策文档；
- 生成 B 内审阅提示词和规则草稿。

不要把首页做成重型编辑器。

---

## 8. 写回流程

标准流程：

```text
用户在图表或详情页做决策
  ↓
DeepSpec 生成候选 Decision Record
  ↓
用户确认该决策文本
  ↓
写入 requirement-decisions.yaml / .md
  ↓
生成 .deepspec 下的 AI 消费层文档、LLM 任务和修订 Prompt 模板
  ↓
DeepSpec 调用框架 LLM 模块继续完善 B；必要时用户也可导出 A -> B 审阅 Prompt 给自己的外部 AI
  ↓
第二层付费能力可生成 B -> A 修订 Prompt / Patch
  ↓
AI 修改 README / 需求文档 / 设计文档 / 规则文件
  ↓
DeepSpec 重新扫描
  ↓
验证决策是否已被底层文档吸收
```

这里的“写入开发文档”默认指写入 B：

```text
.deepspec/decisions/requirement-decisions.md
.deepspec/decisions/ai-requirement-context.generated.md
```

而不是直接写入 A 中用户原有格式的 README、PRD、设计文档。

DeepSpec 生成的 B 不一定和 A 格式一致。B 的价值是规格化、可视化、可追溯、可再生成。

---

## 9. 对现有边界的修正

原约束“DeepSpec 不自动修改项目文件”需要精确化为：

```text
DeepSpec 不未经用户确认自动修改项目文件；
DeepSpec 可以默认写入 B，即 `.deepspec` 下的需求决策文档、AI 上下文文档、HTML、YAML 和审阅提示词；
DeepSpec 不默认覆盖原始 README / PRD / 设计文档；
原始开发文档的正式修订，属于第二层代码与需求校正能力，优先由用户自己的 AI 或用户确认后的 Patch 完成。
```

这保留旁路定位，同时让人类决策真正进入项目材料。

---

## 10. 定稿结论

第 6 点应定为：

```text
人类可以在页面上做需求决策；
决策写入 `.deepspec` 下可追溯的规格化需求文档和结构化 Decision Log；
这些决策优先于旧文档影响后续 AI 需求撰写；
第一层生成 B 内 AI 上下文、审阅 LLM 任务和提示词导出；
第二层生成 B -> A 需求校正 Prompt、规则和 Patch 建议，帮助用户自己的 AI 或用户确认后的 Patch 修改 A；
DeepSpec 不未经确认直接覆盖原始项目文档。
```

一句话：

**DeepSpec 第一层的页面不是编辑器，而是需求决策面板；它把 A 中散乱的原始需求材料读成 B 中规格化、可视化、可追溯、可被 AI 读取的需求事实。**
