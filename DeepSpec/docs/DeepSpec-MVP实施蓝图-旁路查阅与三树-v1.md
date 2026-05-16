# DeepSpec MVP 实施蓝图：旁路查阅与三树 v1

> 日期：2026-05-14  
> 定位：第一阶段需求可视化（包括建议）  
> MVP 形态：通用旁路查阅界面 + 框架 LLM 调用上下文 + 三棵结构树  
> 界面底座：直接复用同事已开发的 DeepShell。

---

## 1. MVP 一句话

**用户把一个项目文件夹拖进 DeepSpec，DeepSpec 旁路读取已有开发文档、代码、配置、UI 和 AI 规则文件，调用成熟的框架 LLM 模块生成 `.deepspec` 规格化需求目录 B，并呈现文件查阅界面、三棵结构树、文档问题清单和审阅建议。**

MVP 第一层是通用免费能力，核心是需求可视化（包括建议），不能绑定在 Delphi + VCL 上。Delphi/VCL 是增强能力和第一批验证样例，不是产品适用范围边界。

B 的语义内容由框架 LLM 模块调用用户配置或已有的 AI 能力，根据 DeepSpec 提供的上下文包、Prompt 模板和 Schema 生成。DeepSpec 负责 LLM 任务编排、提示词工程、上下文组织、Schema 校验、来源追溯、HTML/三树呈现和 B 的事实源管理，不承诺自己负责语义生成。

B 不是 A 的摘要。MVP 中 B 的最小颗粒度是需求节点、关系边、来源证据、状态和人类决策。第一层的所见即所得，指用户看到的三树、图表和 HTML 与 B 中当前需求事实一致；代码结果与需求一致属于第二层能力。详见 `DeepSpec-B事实模型与第一层所见即所得-v1.md`。

MVP 遵守双界面原则：

```text
AI 读 YAML，人类看 HTML。
Prompt / LLM 任务和 HTML 页面点击都是交互入口；
二者最终都必须写回 B 中的 YAML 事实文件。
```

---

## 2. MVP 不做

- 不做主流程问答采集；
- 不要求用户迁移到 DeepSpec；
- 不要求用户在 DeepSpec 里聊天；
- 不在 DeepSpec 里写代码；
- 不未经用户确认自动修改项目文件；
- 不做完整 PRD 编辑器；
- 不做树结构编辑器；
- 不做 Git Diff 审查和 Review Pack；
- 不做 CLI 调度开发；
- 不把 HTML 当唯一事实源。

执行原则：

- MVP 页面组织、树与 HTML 联动、JS Bridge、文件拆分、校验合并流程等实现细节由执行者按当前产品原则直接决策；
- 只有产品定位、阶段边界、事实源边界、责任边界、免费/付费切分等重大战略问题需要继续和用户讨论；
- 已确定的实现细节直接写入文档，不再逐项用 A/B/C 方式询问。

---

## 3. MVP 要做

| 模块 | MVP 能力 |
|---|---|
| 打开项目 | 拖入文件夹、打开文件夹、最近项目。 |
| 项目扫描 | 递归扫描目录，忽略无关目录，识别文档/代码/UI/配置/AI 规则。 |
| 查阅界面 | 文件清单、扫描报告、文档预览、节点详情、问题页、LLM 任务页 / 提示词导出页。 |
| 三棵树 | 功能树、模块树、视图树，使用 DeepShell 原生树控件显示。 |
| 文档问题清单 | 缺失、冲突、歧义、低置信度、无证据、解析失败。 |
| 人类决策写回 | 用户在页面确认、否定、澄清、补口、裁决冲突后，写入 `.deepspec` 下的需求决策文档和 AI 上下文。 |
| LLM 调用与提示词导出 | 通过框架 LLM 模块执行 A -> B 生成 / 审阅任务，输出候选 B；同时保留可复制 Prompt、上下文包和 Schema 约束作为兜底导出。 |
| YAML 保存 | 保存扫描事实、三棵树、问题、LLM 任务元数据和提示词导出元数据。 |
| YAML 合并 | 对候选 B 做 Schema 校验、来源检查、冲突检查，再合并写入 `.deepspec` YAML 事实层。 |
| HTML 渲染 | 由 YAML/模型生成小型 HTML + JS Bridge 页面，供 WebView2 审阅和点击。 |
| 交互写回 | Prompt / LLM 任务生成候选 B；HTML 点击生成候选 Decision Record；二者确认 / 校验后写回 `.deepspec` YAML 事实层。 |
| Delphi/VCL 增强 | 作为增强能力优先支持 `.dpr/.dproj/.pas/.dfm`，生成视图树和模块树；不作为通用 MVP 的适用范围限制。 |

---

## 4. 最小工作流

```text
拖入项目文件夹
  ↓
扫描并分类文件
  ↓
生成扫描报告和文件查阅页
  ↓
解析项目材料并生成初步扫描事实
  ↓
构建 A -> B 上下文包、Prompt 模板和 Schema 约束
  ↓
调用框架 LLM 模块
  ↓
LLM 输出候选 B
  ↓
DeepSpec 校验候选 B
  ↓
DeepSpec 合并候选 B 到当前 B
  ↓
从 B 渲染功能树 / 模块树 / 视图树 / 图表 / 问题清单
  ↓
用户在页面点击并生成候选 Decision Record
  ↓
用户确认 Decision Record
  ↓
写入需求决策文档 / AI 上下文
  ↓
按需再次调用框架 LLM 模块完善 B
  ↓
用户继续审阅
```

---

## 5. 界面结构

直接复用同事已经开发的 DeepShell：

```text
主窗体轻，中间工作；
左右悬浮，多区多页；
上下折叠，多 Tab 承载。
```

### 5.1 主窗体

- 顶部工具栏：打开项目、重新扫描、结构窗、探查窗、生成 / 刷新 B、导出提示词、导出报告、设置。
- 顶部摘要区：项目路径、项目类型、文件数量、问题数量、最近扫描时间。
- 中部主工作区：WebView2，显示 HTML 查阅页。
- 底部信息区：扫描日志、问题摘要、解析警告。

界面分工：

```text
YAML = AI / DeepSpec 读取和校验的机器事实层
HTML = 人类阅读、审阅、点击决策的呈现层
Prompt / LLM 任务 = AI 交互入口
HTML 点击 = 人类交互入口
JS Bridge = HTML 点击事件到 DeepShell / DeepSpec 的通道
DeepShell / DeepSpec = 唯一写入 B 的执行者
```

HTML 页面组织：

- `index.html` 做入口、总览和导航；
- 功能树、模块树、视图树、问题、节点详情按页面或片段生成；
- 不做一个巨大的单页 HTML；
- MVP 不做完整前端 SPA。

树与 HTML 联动：

- B 中所有节点使用稳定 `node_id`；
- 点击 DeepShell 原生树节点时，WebView2 定位到对应 HTML 节点详情；
- 点击 HTML 中的节点或图表元素时，通过 JS Bridge 反选 DeepShell 树节点；
- 联动只传递 `node_id`、动作类型和必要参数，不传递事实数据所有权。

决策面板：

- 首页只做轻决策：确认、不清晰、冲突、缺口、待确认；
- 节点详情页生成完整候选 Decision Record；
- 用户确认后由 DeepShell / DeepSpec 写入 B；
- 不做独立重型决策编辑器。

### 5.2 左悬浮结构窗

使用 DeepShell 提供的原生树控件。若底层实现基于 VCL，MVP 可用 `TTreeView`，长期用 `VirtualStringTree`，但这只是界面实现技术，不是产品适用范围。

包含：

- 文件分类树；
- 功能树；
- 模块树；
- 视图树；
- 问题过滤视图。

### 5.3 右悬浮探查窗

显示当前对象：

- 基本属性；
- 来源文件；
- 来源片段；
- 节点状态；
- 置信度；
- 关联节点；
- 问题；
- LLM 任务上下文与可导出提示词。

---

## 6. 三棵树定义

三棵树是 DeepSpec 第一层的结构骨架。需求总览图、问题图、来源证据图都应挂在三棵树之上，而不是脱离三棵树另做一套平行模型。

```text
三棵树 = 结构骨架
需求总览图 = 功能树的图表化总览视图
功能-视图关系 = 视图树节点挂接到功能树节点
功能-模块关系 = 模块树节点挂接到功能树节点
问题图 = 三棵树问题聚合视图
来源证据图 = 三棵树节点证据视图
```

第一层必须区分“需求侧视图树”和“实现侧控件树”：

```text
视图树 = 功能树中交付界面部分的简化表达
控件树 = 代码/DFM/前端文件中的实现结构
```

当前 MVP 第一层优先做需求侧视图树。Delphi/VCL 的 DFM 解析可以作为辅助证据或增强能力，但不能把通用视图树定义成 DFM 控件树。

第一层的完整表达应是：

```text
平面开发文档
  ↓
三棵树结构骨架
  ↓
挂接多种需求图表
  ↓
HTML 交互审阅
  ↓
框架 LLM 模块生成 / 完善 B，提示词导出作为兜底
```

因此 HTML 页面不能只是静态报告，还要承担交互审阅和提示词出口：

- 点击图表节点；
- 展示来源证据；
- 展示问题和低置信度；
- 生成针对该节点的 B 内审阅 LLM 任务上下文和提示词导出；
- 引导用户通过框架 LLM 模块完善 B；如需修改 A 中底层文档，进入第二层需求校正能力。

第一层图表体系已定稿，MVP 图表按以下优先级实现：

```text
P0 结构骨架:
1. 功能树
2. 模块树 / 系统结构树
3. 视图树 / UI 界面树

P0 固定图表:
4. 需求总览图
5. 来源证据图
6. 需求健康图
7. 当前文档状态总览图

P1 条件必需:
8. 用户路径 / 场景流图
9. 角色权限矩阵
10. 术语与对象关系图

P2 条件扩展:
11. 状态转换图
12. 规则 / 决策表
13. 接口 / 集成关系图
14. 变更影响图
```

详见 `DeepSpec-第一层图表体系定稿-v2.md`。

### 6.1 功能树

回答：这个软件要做什么？

来源：

- README / 需求 / TODO / CHANGELOG；
- 标题和功能清单；
- 按钮、菜单、Action Caption；
- 事件处理器名；
- AI 生成的结构化理解。

注意：功能树有推断成分，必须显示 `source_refs` 和 `confidence`。

### 6.2 模块树

回答：软件内部怎么拆？

来源：

- 目录结构；
- `.dpr/.dproj/.pas`；
- Unit、Class、Form、DataModule；
- 命名模式和文件路径。

### 6.3 视图树

回答：功能树中的需求最终需要交付成哪些用户可见界面？

来源：

- 功能树中和交付界面有关的节点；
- `.dfm/.fmx`；
- 前端页面；
- HTML 原型；
- UI 文档；
- 截图说明。

第一优先级来源是功能树和设计文档中的界面意图；实现文件只作为辅助证据。

---

## 7. 节点通用字段

```yaml
id:
tree:
title:
kind:
summary:
status: candidate
confidence:
source_refs:
  - path:
    lines:
    note:
related_functions: []
related_modules: []
related_views: []
issues: []
```

关系边至少支持：

```yaml
id:
from:
to:
type: contains | depends_on | implements | presented_by | owned_by | constrained_by | conflicts_with | derived_from
confidence:
source_refs: []
decision_refs: []
```

图表中的节点和连线必须能回到 B 中的节点和关系边，不能只生成一次性静态 HTML。

状态第一版至少支持：

```text
candidate
confirmed
uncertain
ignored
```

---

## 8. 文档问题清单

MVP 应把“优化开发文档”作为核心产物之一。

```yaml
doc_issues:
  - id:
    severity: high
    type: missing_requirement
    title:
    description:
    affected_nodes:
    source_refs:
    suggested_prompt:
```

问题类型：

```text
missing_requirement
conflict
ambiguity
stale_doc
no_source
low_confidence
parse_warning
parse_error
```

---

## 9. `.deepspec` 输出目录

默认询问用户是否在项目中创建 `.deepspec`。若用户不同意，写入本机工作区。

必须区分：

```text
A = 用户原有需求文档目录 / 原始项目材料
B = DeepSpec 生成的规格化需求文档目录，默认为项目根目录下 .deepspec/
```

DeepSpec 默认读取 A，生成 B。B 中的 YAML、HTML、决策文档、AI 上下文和提示词不要求与 A 的格式一致。

DeepSpec 不默认把 B 混写进 A；A 的正式修改由用户自己的 AI、用户手动编辑，或用户确认后的 Patch 完成。

B 是 DeepSpec 内部的规格化事实源，A 是原始输入材料和证据层。B 必须能追溯 A，但不要求复用 A 的文档格式。

```text
.deepspec/
  project.yaml
  project-spec.yaml
  scan-report.yaml

  trees/
    function-tree.yaml
    module-tree.yaml
    view-tree.yaml

  relations/
    requirement-relations.yaml

  evidence/
    source-evidence.yaml

  issues/
    doc-issues.yaml

  prompts/
    context-pack.md
    doc-optimization-prompt.md
    node-prompt.md
    decision-context.md
    decision-rewrite-prompt.md

  llm/
    generation-task.yaml
    candidate-output.yaml
    validation-report.yaml
    merge-report.yaml
    last-run.yaml

  decisions/
    requirement-decisions.yaml
    requirement-decisions.md
    ai-requirement-context.generated.md

  patches/
    doc-patch-suggestions.md

  html/
    index.html
    scan-report.html
    documents.html
    code-files.html
    ui-files.html
    ai-rules.html
    function-tree.html
    module-tree.html
    view-tree.html
    issues.html
    prompt-preview.html
    node-detail.html

  logs/
    scan-log.txt
```

其中：

- `project-spec.yaml` 是 B 的总事实索引，引用三棵树、问题、来源、决策、LLM 任务、提示词导出和 HTML 输出；
- `project-spec.yaml` 只保存项目元信息、版本、文件引用、摘要指标和当前状态，不复制完整事实内容；
- `trees/*.yaml`、`relations/*.yaml`、`evidence/*.yaml`、`issues/*.yaml`、`decisions/*.yaml` 是事实数据；
- `html/*.html` 是由事实数据生成的审阅界面，可以删除后重新生成，不是事实源；
- `llm/candidate-output.yaml` 保存最近一次 LLM 候选输出，必须通过校验和合并后才能进入事实数据；
- `llm/validation-report.yaml` 和 `llm/merge-report.yaml` 记录校验、冲突和合并结果；
- 给用户自己 AI 的 Context Pack 以 B 为主，按需引用 A 中的来源片段。

MVP 交互边界：

- 图上节点可点击；
- 节点详情显示来源、问题、关系、状态、置信度；
- 页面提供确认、否定、澄清、补口、裁决冲突等决策按钮；
- 点击按钮先生成候选 Decision Record，用户确认后写入 B；
- HTML 通过 JS Bridge 把点击事件交给 DeepShell / DeepSpec；
- HTML 不自行保存事实状态，不直接写 YAML；
- 决策写回 B 后重新渲染三树和 HTML；
- 不做拖拽改树、直接改名、手工连线和完整画布编辑器。

B 的版本策略：

- 当前工作集保存在 `.deepspec/` 固定路径；
- 每次扫描保存摘要、diff 和决策变化；
- 不默认完整保留每次扫描的全部文件，避免体积膨胀；
- 后续可按需提供完整快照归档。

决策覆盖策略：

- A 的解析结果是基础层；
- B 中 accepted decisions 是覆盖层；
- 三棵树显示时应呈现“基础解析 + 决策覆盖”后的当前规格判断；
- 同时标注哪些节点尚未同步回 A，避免用户误以为原始文档已经被修改。

三棵树节点必须显示来源层级标签：

- `A:原文解析`；
- `B:人工决策`；
- `B:AI推断`；
- `B:生成摘要`。

来源层级标签必须参与筛选：

- 只看 `B:人工决策`；
- 只看 `B:AI推断`；
- 只看 `A 未同步`；
- 只看 `A 有旧描述`。

`B:AI推断` 可以进入三棵树和图表，但必须标记为低置信 / 待确认，不能覆盖 `B:人工决策`。

A 与 B 冲突时，主视图显示 B 的当前规格判断，同时标记 `A 未同步` 或 `A 有旧描述`。

`A 未同步` 可在免费层作为状态标签显示；集中同步队列、需求修订 Prompt / Patch 属于第二层代码与需求校正能力。

文档优化建议分两级：

- 第一层生成 B 内审阅建议和建议段落，不强行绑定 A 中的文件位置；
- 第二层在能够稳定定位 Markdown / 规则文件位置时，生成文件级 Patch 建议。

个人布局：

```text
%LOCALAPPDATA%/DeepSpec/
  settings.json
  layout.json
  recent-projects.json
```

---

## 10. 工程分层

```text
shell/             DeepShell 通用壳
shell_forms/       主窗体、结构窗、探查窗、顶部/底部面板
deepspec_core/     项目、扫描结果、节点、树模型、问题模型
deepspec_scan/     文件扫描、分类、忽略规则、扫描报告
deepspec_delphi/   Delphi/VCL 解析
deepspec_trees/    三树生成与关联
deepspec_llm/      框架 LLM 模块接入、任务调度、结果校验
deepspec_prompts/  上下文包、Prompt 模板与导出
deepspec_render/   HTML/Markdown 渲染
deepspec_providers/ DeepSpec 接入 DeepShell
resources/         模板、CSS、图标
tests/             样例项目和解析测试
```

原则：

```text
DeepShell 不懂业务；
业务不绑窗体；
Provider 负责接入；
DeepBase 提供配置、日志、安全、LLM、账号、授权、WebView2、Resilience 和基础桌面能力；
DeepSpec 只做需求规格业务层、三树/图表渲染层和 B 事实管理层；
LLM 调用和提示词导出不直接修改 A 中的原始文件。
未经用户确认不覆盖原始开发文档。
用户确认的人类决策默认写入 `.deepspec` 下的需求决策文档，并作为后续 AI 需求撰写的高优先级上下文。
B 是 DeepSpec 的规格化事实源；A/B 需求校正、需求修订 Prompt / Patch 和代码与需求校正属于第二层能力。
```

DeepBase 接入详见 `DeepSpec-借力DeepBase框架接入方案-v1.md`。

---

## 11. 开发批次

### P0：壳 + 扫描 + 查阅

目标：

- 打开文件夹；
- 扫描文件；
- 分类文档/代码/UI/配置/AI 规则；
- 生成 `scan-report.yaml/html`；
- WebView2 显示报告；
- 底部显示日志；
- 左右悬浮窗能打开。

验收句：

**文件夹进来，扫描结果出来，报告显示出来。**

### P1：通用三树 + Delphi/VCL 增强

目标：

- 从通用文档、目录、配置、AI 规则中生成基础功能树、模块树、视图树；
- 识别 `.dpr/.dproj/.pas/.dfm`；
- 解析 text DFM；
- 为 Delphi/VCL 项目生成更精确的视图树；
- 按目录和 Unit 生成模块树；
- 探查窗显示节点属性和来源。

验收句：

**拖入任意项目后能看到基础三树；拖入 Delphi/VCL 项目后能进一步真实看见窗体、控件和模块结构。**

### P2：功能树 + 问题 + LLM 上下文

目标：

- 从文档、Caption、Action、菜单、事件名生成功能树；
- 生成文档问题清单；
- 支持用户在页面上对问题做需求决策；
- 写入 `.deepspec/decisions/requirement-decisions.yaml/.md` 和 AI 需求上下文；
- 生成上下文包和 A -> B 生成 / 审阅 LLM 任务；
- 通过框架 LLM 模块生成 / 更新 B；
- 支持复制节点 Prompt 给外部 AI，作为兜底导出。

验收句：

**DeepSpec 不只看见结构，还能让用户做需求决策，把决策写入开发文档上下文，并通过框架 LLM 模块继续完善 B。**

### P3：样例库 + 封版

目标：

- 建立 5 个样例项目；
- 验证扫描、解析、三树、问题、LLM 任务和提示词导出；
- 处理损坏/缺失/二进制 DFM 不崩溃；
- 打磨 Demo。

---

## 12. MVP 封版标准

打开一个通用开发项目后，DeepSpec 必须能稳定完成：

1. 扫描目录；
2. 分类文件；
3. 生成扫描报告；
4. 生成模块树；
5. 生成视图树；
6. 生成候选功能树；
7. 生成文档问题清单；
8. 支持人类决策写入需求决策文档；
9. 生成并执行 B 内文档优化 LLM 任务，且可导出对应提示词；
10. 在 DeepShell 原生树控件和 WebView2 中清晰呈现；
11. 遇到损坏文件、乱码文件、未知项目类型不崩溃。

Delphi/VCL 增强验收：

- 能识别 `.dpr/.dproj/.pas/.dfm`；
- 能解析 text DFM；
- 能生成更准确的窗体/控件视图树；
- 遇到 binary DFM 或损坏 DFM 不崩溃，并进入问题清单。

---

## 13. 当前 Demo 场景

```text
打开 DeepSpec
  ↓
拖入 Sample02_MultiForms
  ↓
显示扫描报告
  ↓
查看视图树
  ↓
点击 BtnOpenFolder
  ↓
探查窗显示控件信息和来源 DFM
  ↓
查看模块树
  ↓
查看功能树
  ↓
打开问题页
  ↓
调用框架 LLM 模块生成 / 审阅 B
  ↓
查看更新后的三树、问题和 HTML 审阅页
```

---

## 14. 提示词导出适配规范（2026-05-14 补充）

提示词导出时，应按目标工具做轻量格式适配，降低用户粘贴后的摩擦：

| 目标工具 | 适配要点 |
|---|---|
| Claude Code | 带 `# 不要修改以下文件` 约束段；使用 markdown 结构 |
| Cursor | 带 `@file` 引用格式；适配 Cursor Rules 风格 |
| Codex CLI | 带 `## 约束` 和 `## 输出格式` 段落 |
| 通用 | 纯 markdown，不依赖特定工具语法 |

导出提示词必须包含：

- 节点路径和当前描述；
- 问题类型和严重程度；
- 来源证据摘要；
- DeepSpec 的判断和建议修改方向；
- 受影响的关联节点；
- 明确的"不要做"约束（不改代码、不改 HTML、不推翻已确认决策）。

导出提示词不能只复制节点文本。

---

## 15. LLM 候选 B 校验失败的重试引导（2026-05-14 补充）

用户的 LLM 生成候选 B，出错责任在用户的 AI。但 DeepSpec 有责任提供清晰的重试引导。

校验失败时，DeepSpec 应：

1. 显示具体失败原因（缺字段、id 格式错误、无 source_refs、冲突覆盖等）；
2. 生成"修正提示词"，用户可直接粘贴给自己的 AI 重新生成；
3. 保留最近 N 次候选输出的校验报告，让用户看到趋势（"这次比上次好了"或"反复在同一处出错"）；
4. 不自动重试，不替用户决定换模型。

Schema 模式：

- 宽松模式（默认首次生成）：允许缺少非必需字段，自动补默认值，只拒绝结构性错误；
- 严格模式（用户做过决策后）：不允许覆盖 accepted decision，不允许缺少 source_refs。

---

## 16. DeepBase 反馈机制（2026-05-14 补充）

DeepSpec 作为 DeepBase 的第一个重度业务下游，开发过程中应维护：

```text
docs/deepbase-feedback.md
```

记录内容：

- DeepShell Provider API 与文档不一致的地方；
- LLM facade 的实际使用痛点；
- JS Bridge / WebView2 的性能或兼容问题；
- ConfigDB 边界不清晰的场景；
- Security / Secret 的使用摩擦；
- 建议 DeepBase 新增或修改的能力。

目标：DeepSpec 实践 DeepBase，同时反哺 DeepBase 迭代。
