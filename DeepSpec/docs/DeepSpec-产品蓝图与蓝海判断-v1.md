# DeepSpec 产品蓝图与蓝海判断 v1

> 日期：2026-05-13  
> 状态：讨论稿  
> 基础文档：`DeepSpec-产品愿景与约束-v2.md`  
> 核心结论：DeepSpec 不是纯蓝海，但存在明确的蓝海切入点。  
> 定位升级：2026-05-14 已升级为“所见即所得的开发文档优化器”，详见 `DeepSpec-定位升级-所见即所得开发文档优化器-v1.md`。

---

## 1. 一句话定位

**DeepSpec 是软件开发的需求可视化审阅层：把项目材料转成可追溯的规格化需求 B，并用三棵树和 HTML 图表让人看清、确认和校准 AI 的理解。**

定位升级后，DeepSpec 更准确的表达是：

**DeepSpec 第一阶段是需求可视化（包括建议）：它作为用户原有 AI/IDE 工作流旁边的旁路工具，读取项目中的开发文档、代码、配置和 UI 文件，通过成熟的框架 LLM 模块调用用户配置或已有的 AI 能力，生成 `.deepspec` 规格化需求目录 B，再提供可视化查阅界面、需求决策层和来源证据。第二阶段升级为需求所见即所得，让代码与需求一致。第三阶段再调用用户 CLI 实现软件功能。**

DeepSpec 不是新的 AI IDE，不替代 Claude Code / Cursor / Codex / Kiro / VS Code，也不是传统 PRD 编辑器。它是一个本地项目规格审阅层：读取用户已有项目材料，通过框架 LLM 模块调用用户配置或已有的 AI 能力生成结构化规格，再把规格渲染成可导航、可对照、可检查的审阅界面。

当前战略定稿详见 `DeepSpec-战略定稿-v1.md`。

---

## 2. 要解决的核心痛点

### 2.1 线性文档无法承载复杂软件意图

README、需求文档、设计稿、代码注释、聊天记录、配置文件、DFM/PAS 等材料通常分散在项目中。它们是线性的、局部的、历史叠加的，人和 AI 都很难从中一次性看清：

- 产品到底要做什么；
- 系统内部怎么拆；
- 用户界面有哪些页面和层级；
- 哪些内容是确定的，哪些内容存在歧义；
- AI 是否真正理解了项目意图。

Thariq Shihipar 的 HTML effectiveness 示例指出，diff、调用图、模块结构这类信息本质是空间信息，Markdown 会把它们压平成线性文本，而 HTML 能把它们做成可扫视、可跳转、可交互的审阅材料。DeepSpec 的产品假设与此一致：**规格不是只需要生成文本，而是需要被人真正审阅。**

参考：https://thariqs.github.io/html-effectiveness/#code-review

### 2.2 AI 编码普及，但信任不足

AI 开发工具已经进入主流工作流。JetBrains 2026 AI Pulse 调研显示，2026 年 1 月有 90% 的开发者在工作中经常使用至少一种 AI 工具，74% 已采用专门面向开发者的 AI 工具。与此同时，Stack Overflow 2025 调研显示，84% 的开发者使用或计划使用 AI 工具，但 46% 不信任 AI 输出准确性。

这意味着市场需求不是“让 AI 更快写代码”这么简单，而是：**让人能审阅 AI 的理解，降低 AI 误解需求后继续写错代码的风险。**

参考：

- https://blog.jetbrains.com/research/2026/04/which-ai-coding-tools-do-developers-actually-use-at-work/
- https://stackoverflow.co/company/press/archive/stack-overflow-2025-developer-survey/

### 2.3 现有工具更重视生成，不重视审阅界面

大量工具已经能生成 PRD、任务、设计文档、代码和测试，但生成物通常仍是 Markdown、Issue、表单字段或 IDE 内部状态。DeepSpec 的差异点应放在：

- 从已有项目材料反推规格；
- 用三棵树建立产品、模块、视图的结构化理解；
- 用 HTML/VCL 把理解结果变成可审阅界面；
- 发现问题后回到底层文件修改，而不是在 DeepSpec 里修补表象。

---

## 3. 产品原则

| 原则 | 含义 |
|---|---|
| 旁路增强 | DeepSpec 不接管主开发链路，只在用户原 AI/IDE 工作流旁边提供查阅界面、LLM 调用上下文和提示词导出。 |
| 不替代用户 AI | 用户继续使用 Claude Code / Cursor / Codex / IDE / CLI；第一层默认通过成熟框架 LLM 模块调用用户配置或已有的 AI 能力生成 B。 |
| A/B 分层 | A 是用户原始项目材料；B 是 DeepSpec 生成的 `.deepspec` 规格化事实源。 |
| 弱化语义责任 | DeepSpec 负责 LLM 任务编排、提示词工程、上下文组织、Schema 校验、来源追溯和可视化呈现，不承诺自己理解或生成完美需求。 |
| 三阶段路线 | 需求可视化（包括建议） → 需求所见即所得（代码与需求一致） → 调用 CLI 实现软件功能。 |
| 免费呈现，付费校正 | 免费层呈现可视化需求体系和建议；付费层提供 A/B 需求校正、代码与需求一致性校正和 CLI 功能实现。 |
| B 驱动 A 修订 | DeepSpec 不默认混写 A；B -> A 的需求校正 Prompt / Patch 属于付费能力。 |
| YAML 是 B 的机器事实源 | AI/DeepSpec 生成 YAML；DeepSpec 校验、解析、渲染。 |
| HTML 是人类审阅层 | HTML 不是事实源，而是由 B 生成的产品体验核心。 |
| 本地项目优先 | 读取用户本地项目文件，尽量减少平台迁移成本。 |
| 查阅界面 + LLM 任务 | 支持更好的文件/规格查阅，默认调用框架 LLM 模块生成 / 审阅 B，并保留可复制 Prompt 导出；用户仍在原工具中对话和修改。 |
| 证据优先 | 规格节点应尽量能追溯到源文件、片段或 AI 判断依据。 |
| 本地优先 | 第一版采用本地优先 + 用户配置模型 / API Key / 框架 LLM 模块；企业私有模型和内网版后续付费。 |
| 账号对接 | 云端账号、官网分发和后续授权由 `deepkit.top` 提供，DeepSpec 客户端直接对接。 |
| 第一版开源免费 | 第一版直接开源免费，用于获客、验证样例和建立开发者信任。 |

---

## 4. 目标用户

### 4.1 首批用户

第一市场楔子：

```text
AI 重度开发者的需求可视化审阅工具。
```

| 用户 | 场景 | 痛点 |
|---|---|---|
| AI 重度独立开发者 | 用 Claude Code / Cursor / Codex 快速开发产品 | AI 写得快，但需求和界面容易跑偏。 |
| 小团队技术负责人 | 需要审阅 AI 生成或新人维护的项目 | 难以快速看清产品、模块、视图是否一致。 |
| 外包/交付团队 | 从客户材料、旧项目、半成品代码整理规格 | 文档散乱，交付前需要形成可审阅规格。 |
| 传统桌面/Delphi 项目团队 | 有 DFM/PAS/历史文档 | 现有 AI 工具对 Delphi/窗体结构理解弱。 |
| AI 代理工作流使用者 | 多个 AI 工具轮流参与项目 | 每个工具上下文不同，需要稳定中间规格层。 |

### 4.2 暂不优先服务

- 大型合规需求管理团队；
- 已深度使用 DOORS/Jama 的航空、汽车、医疗器械系统工程团队；
- 需要完整多人在线协作、权限、审批流的企业客户；
- 只想“给一个提示词就输出产品”、不愿审阅规格和做需求决策的用户。

---

## 5. 核心工作流

```text
用户已有项目材料
README / 需求文档 / 设计文档 / 代码 / DFM / 配置 / AI 规则
        ↓
DeepSpec 扫描、筛选、打包上下文
        ↓
框架 LLM 模块调用用户配置或已有 AI，生成 .deepspec 规格化需求目录 B
project-spec.yaml / 三棵树 / 问题 / 来源 / 决策 / HTML
        ↓
DeepSpec 校验 YAML Schema
        ↓
DeepSpec 渲染审阅界面
VCL 树控件 + WebView2 HTML 页面
        ↓
用户审阅 AI 对项目的理解，并在 B 中做需求决策
        ↓
发现错误 / 缺口 / 冲突
        ↓
免费层：继续审阅和决策 B
付费层：生成需求/代码校正 Prompt、Patch、Review
        ↓
重新生成 YAML / HTML
```

---

## 6. 三棵树

| 树 | 回答的问题 | 来源 | 审阅重点 |
|---|---|---|---|
| 功能树 | 产品要做什么 | README、需求文档、聊天记录、业务说明 | 功能是否完整、优先级是否清楚、边界是否明确。 |
| 模块树 | 系统内部怎么拆 | 代码、目录、架构文档、配置 | 模块职责是否清楚、依赖是否合理、是否有缺失模块。 |
| 视图树 | 用户看到什么 | UI 文档、截图、DFM/FMX、前端代码 | 页面层级、主要控件、用户路径是否符合意图。 |

MVP 的三棵树不是传统编辑器，而是 B 中的规格化事实视图。用户通过它判断 A 是否足够清晰。B -> A 的需求校正 Prompt 和 Patch 建议属于付费层。

---

## 7. MVP 范围

### 7.1 必做

| 模块 | MVP 能力 |
|---|---|
| 项目扫描 | 识别文档、代码、配置、AI 规则、Delphi UI 文件。 |
| 文件清单树 | 展示项目材料来源，支持点击查看。 |
| LLM 上下文打包 | 生成给框架 LLM 模块的任务上下文，支持文件选择、排除目录、token 估算、Schema 约束；同时支持 Prompt 导出。 |
| YAML Schema | 定义功能树、模块树、视图树固定结构。 |
| YAML 导入与校验 | 解析 AI 返回内容，提示字段缺失、格式错误、超长节点。 |
| 三树展示 | VCL 树控件显示三棵树，可同时挂载对照。 |
| HTML 审阅页 | 生成可读、可导航、可展开的审阅 HTML。 |
| 源证据引用 | 节点尽量包含来源文件路径、片段摘要、可信度。 |
| 人类决策层 | 用户在 B 的页面上确认、否定、澄清、补口、裁决冲突。 |

### 7.2 暂不做

- 不做完整 PRD 在线编辑器；
- 不做多人协作、审批、权限系统；
- 不做完整 Requirements Management 替代品；
- 不做自动改代码；
- 不默认自动改 A 中的 README / PRD / 设计文档；
- 不做代码实现与规格一致性检查；
- 不调用用户 CLI 执行开发；
- 不提供 A/B 需求校正工作流；
- 不生成用于自动修订 A 的文件级 Patch；
- 不承诺 AI 输出一定正确；
- 不把 HTML 作为唯一事实源；
- 不在 MVP 中追求所有语言静态分析。

---

## 8. 数据模型草案

### 8.1 通用节点字段

```yaml
id: feature.auth.login
title: 用户登录
summary: 用户通过账号密码或第三方身份完成登录
status: inferred # confirmed | inferred | uncertain | conflict
confidence: 0.82
source_refs:
  - path: README.md
    lines: "32-48"
    note: 登录能力描述
children: []
notes: []
```

### 8.2 功能树特有字段

```yaml
user_value: 降低首次访问门槛
priority: P0
acceptance_criteria:
  - 用户输入正确账号密码后进入主界面
  - 密码错误时显示明确错误提示
open_questions:
  - 是否需要第三方登录？
```

### 8.3 模块树特有字段

```yaml
module_type: service
responsibility: 处理身份认证与会话管理
related_files:
  - src/auth/session.pas
dependencies:
  - module.user
risks:
  - 会话过期策略未在文档中明确
```

### 8.4 视图树特有字段

```yaml
view_type: form
route_or_class: TLoginForm
controls:
  - name: edtUsername
    type: input
  - name: btnLogin
    type: button
user_paths:
  - 打开应用 -> 输入账号密码 -> 点击登录 -> 进入主界面
```

---

## 9. HTML 审阅界面蓝图

HTML 是 DeepSpec 的核心体验，不是简单导出。

### 9.1 第一版页面

| 页面 | 用途 |
|---|---|
| 总览页 | 展示项目名称、生成时间、扫描来源、三棵树规模、风险摘要。 |
| 功能树页 | 功能分层、优先级、验收标准、未决问题。 |
| 模块树页 | 模块职责、依赖、相关文件、风险。 |
| 视图树页 | 页面层级、控件、用户路径、DFM/PAS 映射。 |
| 对照页 | 功能节点、模块节点、视图节点的关联关系。 |
| 问题页 | 不确定、冲突、低置信度、缺少证据的节点。 |

### 9.2 审阅交互

MVP 的 HTML 交互写回 B，不直接写回 A：

- 展开/折叠；
- 搜索；
- 节点跳转；
- 风险过滤；
- 来源文件跳转；
- 三树并排对照；
- 人类决策写入 `.deepspec/decisions`；
- 一键调用框架 LLM 模块生成 / 审阅 B，并可导出“B 生成 / 审阅 Prompt”给外部 AI。

---

## 10. 竞品与相邻市场

### 10.1 AI IDE / Spec-driven Development

| 产品 | 方向 | 对 DeepSpec 的启发 | 差异 |
|---|---|---|---|
| Kiro | Agentic IDE，spec-driven development，requirements/design/tasks | 规格先行已经成为 AI 开发工具的重要方向。 | Kiro 是完整 IDE/Agent 环境；DeepSpec 应做独立审阅层，服务用户已有工具。 |
| GitHub Spec Kit | Spec -> Plan -> Tasks -> Implement，支持多 AI agent | “规格作为 AI 输入”方向被验证。 | Spec Kit 主要产出 Markdown 流程工件；DeepSpec 强调从已有材料生成三树和 HTML 审阅。 |
| CodeTrellis | 本地桌面 app，可视化代码结构、计划、捕捉 agent drift | 本地、模型无关、MCP/agent 生态方向接近。 | CodeTrellis 偏代码结构和 agent 执行偏移；DeepSpec 偏产品意图、模块、视图规格审阅。 |

参考：

- https://kiro.dev/
- https://kiro.dev/docs/specs/
- https://github.github.io/spec-kit/
- https://codetrellis.dev/

### 10.2 产品管理 AI / PRD 生成

| 产品 | 方向 | 对 DeepSpec 的启发 | 差异 |
|---|---|---|---|
| Productboard Spark | PM AI，生成 PRD、产品 brief、竞争分析，基于产品上下文 | PM 规格生成市场需求明确。 | Productboard 是 SaaS 产品管理平台；DeepSpec 面向本地项目和开发材料。 |
| Atlassian Rovo/Jira | 从 Confluence、Slack、IDE 等生成 work item，分解任务 | 企业协作平台会把 AI 嵌进全流程。 | Atlassian 绑定 Jira/Confluence；DeepSpec 不要求用户迁移协作平台。 |
| AI PRD Generator 类工具 | 从想法生成 PRD | “生成 PRD”已拥挤。 | DeepSpec 不主打从空白想法写 PRD，而是审阅已有项目材料的 AI 理解。 |

参考：

- https://www.productboard.com/product/spark/
- https://www.atlassian.com/software/jira/ai

### 10.3 传统需求管理

| 产品 | 方向 | 对 DeepSpec 的启发 | 差异 |
|---|---|---|---|
| IBM DOORS Next | 需求管理、合规、追踪、评审、AI 改善需求质量 | 需求质量、追踪、审阅是成熟问题。 | DOORS 面向大型系统工程和合规；DeepSpec 应避免一开始进入重企业需求管理。 |
| Jama Connect Advisor | NLP/EARS/INCOSE 要求质量检查 | 需求语句质量和标准化有长期价值。 | DeepSpec 的初期不是写更规范的需求句子，而是显性化 AI 对项目整体的理解。 |

参考：

- https://www.ibm.com/products/requirements-management
- https://www.jamasoftware.com/requirements-management-guide/writing-requirements/jama-connect-advisor

### 10.4 代码库理解 / 文档生成

| 产品 | 方向 | 对 DeepSpec 的启发 | 差异 |
|---|---|---|---|
| Vxplain | 为 coding agents 生成架构图、调用图、流程图 | 可视化代码理解需求明确。 | Vxplain 偏代码结构；DeepSpec 要把产品功能、模块和 UI 意图连起来。 |
| RepoWise | 生成结构化 AI 上下文文件，适配多个 AI 工具 | “给 AI 准备上下文”是成立方向。 | RepoWise 偏持续上下文引擎；DeepSpec 偏人类审阅层和规格 HTML。 |
| SpecCanvas | UI Spec/Data Spec、HTML 生成、多模型比较 | “看见再实现”的价值非常接近。 | SpecCanvas 偏从想法/UI spec 到界面；DeepSpec 偏已有项目材料和三树规格审阅。 |

参考：

- https://www.vxplain.com/
- https://www.repowise.ai/
- https://www.speccanvas.dev/

---

## 11. 蓝海判断

### 11.1 不是蓝海的部分

以下方向已经明显进入红海或准红海：

- AI 编码助手；
- AI IDE；
- PRD 生成器；
- 产品管理 AI；
- 代码库自动文档；
- 架构图/调用图生成；
- 需求管理与追踪。

这些方向都有大厂、成熟 SaaS 或快速出现的独立产品。DeepSpec 如果直接说“AI 生成 PRD”或“AI 理解代码库”，差异不够。

### 11.2 仍有蓝海空间的部分

DeepSpec 的蓝海机会在一个更窄但更清晰的交叉点：

```text
本地已有项目材料
    ×
用户已有 AI 工具
    ×
只读规格审阅
    ×
三树结构化 YAML
    ×
HTML/VCL 可视化审阅界面
```

这个交叉点目前没有被大产品直接占满。相邻产品通常只覆盖其中一部分：

- Kiro/Spec Kit 重视规格驱动，但更偏创建新规格和实施流程；
- Productboard/Atlassian 重视协作和产品管理，但绑定平台；
- Vxplain/RepoWise 重视代码结构和 AI 上下文，但较少把产品功能、模块、UI 作为审阅规格统一展示；
- SpecCanvas 重视 UI spec 和 HTML 视觉反馈，但不是从本地既有项目材料生成三棵树。

因此判断：

**DeepSpec 不是大市场意义上的纯蓝海；但“现有项目材料 -> AI 理解 -> HTML 规格审阅 -> 回底层文件修正”是一个有差异化的蓝海切入点。**

### 11.3 蓝海成立条件

DeepSpec 必须守住以下差异，否则会滑入红海：

1. **不要主打 PRD 生成器。** 这个市场已经拥挤。
2. **不要主打 AI IDE。** 这会正面撞 Kiro、Cursor、Copilot、Codex。
3. **不要主打代码架构图。** 这会撞 Vxplain、CodeViz、RepoWise、doc0 等。
4. **必须主打审阅。** DeepSpec 的核心是让人看清 AI 的理解。
5. **必须主打已有项目。** 不是从空白想法开始，而是从真实项目材料开始。
6. **必须主打 HTML 体验。** YAML 是机器层，HTML 是用户感知价值。
7. **必须保持工具无关。** 第一层默认调用框架 LLM 模块，使用用户配置或已有的 AI 能力；Prompt 导出是兜底能力，不绑定某一家 AI。

---

## 11.4 与 Spec-Driven Development 工具的对比（2026-05 补充）

> 补充日期：2026-05-14  
> 来源：OpenSpec (Fission-AI) 和 Superpowers (obra/Jesse Vincent) 调研

### OpenSpec

定位：轻量 spec-driven 框架，用 slash command 驱动 AI 按 propose → apply → archive 流程工作。核心概念是 "spec delta"——每次变更只写增量规格，不重写全量。存储为项目内 markdown 文件，不需要 API key 或 MCP，支持 20+ AI 工具。

对 DeepSpec 的启发：

- "Spec delta" 思路值得借鉴：DeepSpec 后续可在 B 中增加增量 diff 表达，让用户看到"上次扫描到这次扫描，需求理解变了什么"；
- 极度轻量、零摩擦的安装体验值得 DeepSpec 在 Prompt 导出环节学习；
- "Agree before you build" 话术和 DeepSpec 的"先看清再让 AI 写"异曲同工。

差异：

- OpenSpec 是给 AI 的"任务说明书"，不做可视化、不做来源追溯、不做人类决策写回；
- OpenSpec 假设用户从零写 spec，不是从已有项目材料中读出需求；
- OpenSpec 产出是 markdown，DeepSpec 产出是 HTML/VCL 可交互审阅界面。

### Superpowers

定位：AI 编码 agent 的完整开发方法论框架，14 个可组合 skill，自动激活。强制 AI 走 5 阶段（clarify → design → plan → code → verify），核心是 subagent-driven development + 两阶段 review（spec 合规性 + 代码质量）。已进入 Claude 官方插件市场。

对 DeepSpec 的启发：

- "Mandatory workflows, not suggestions"——DeepSpec 的提示词模板和 Schema 约束也应该是强制性的，不是建议；
- 两阶段 review（先查 spec 合规，再查代码质量）可借鉴到候选 B 校验：先查 Schema 合规，再查来源证据充分性；
- "Plan detailed enough for an enthusiastic junior engineer with poor taste"——DeepSpec 生成的提示词应达到这个具体程度；
- 跨工具支持（Claude Code / Codex / Cursor / Gemini / OpenCode / Copilot）——DeepSpec 的 Prompt 导出应考虑不同工具的格式偏好。

差异：

- Superpowers 管的是"AI 怎么写代码"（开发过程纪律），DeepSpec 管的是"AI 写代码前，需求理解对不对"（理解确认层）；
- Superpowers 不做可视化、不做已有项目分析、不做需求图表；
- 两者是互补关系，不是竞争。

### DeepSpec 的独有优势

```text
1. 可视化审阅层：HTML + VCL 树控件，不是 markdown 文本
2. 从已有项目材料反推：不假设从零开始，而是读取散乱的现有文档
3. 来源证据和置信度：每个节点追溯到 A 中的文件、片段和行号
4. 人类决策作为一等事实：结构化 Decision Log，覆盖 AI 推断
5. A/B 分层：原始材料和规格化事实共存、可冲突标记、可追溯
6. 本地桌面原生体验：独立工具，不依赖终端或 IDE 插件
7. Delphi/VCL/Legacy 项目支持：完全无人覆盖的差异化
```

### 三者的互补关系

```text
Superpowers = 纪律化 AI 的开发过程（怎么写代码）
OpenSpec = 结构化 AI 的任务输入（写什么代码）
DeepSpec = 可视化 AI 对项目的理解（AI 理解对了吗）
```

DeepSpec 和前两者不冲突。用户可以用 DeepSpec 看清需求，再用 OpenSpec 写变更 spec，再用 Superpowers 纪律化开发过程。DeepSpec 占的是"AI 写代码前的理解确认层"，这个位置目前没有被占满。

---

## 12. 战略楔子

### 12.1 最窄可赢定位

**AI 开发前的可视化需求体系呈现器。**

更完整表达：

**DeepSpec 是一个本地桌面工具，读取现有项目材料，通过框架 LLM 模块和提示词工程生成产品功能树、模块树、视图树，并渲染成 HTML/VCL 审阅界面，帮助开发者确认 AI 是否正确理解了项目。**

### 12.2 第一阶段不要承诺

- 不承诺自动生成完美 PRD；
- 不承诺 DeepSpec 自己负责语义生成；
- 不承诺自动修复代码；
- 不承诺替代 Jira/Confluence/Productboard；
- 不承诺完整需求追踪合规；
- 不承诺全语言准确静态分析。

### 12.3 第一阶段必须做到

- 扫描真实项目；
- LLM 上下文和 Prompt 模板质量高；
- YAML Schema 稳；
- HTML 审阅页明显比 Markdown 好读；
- 三树能暴露项目理解偏差；
- 用户能把问题带回原 AI 工具修底层文件。

---

## 13. 商业化方向

### 13.1 可选模式

| 模式 | 说明 | 适配度 |
|---|---|---|
| 免费桌面版 | 本地工具，呈现可视化需求体系 | 高 |
| 开源免费版 | 第一版直接开源免费，降低试用门槛并吸引开发者反馈 | 高 |
| 专业版 | 提供 A/B 需求校正、代码与需求校正、Review Pack | 高 |
| BYOK 版 | 用户填自己的 API key，用于付费校正能力或更深上下文处理 | 中高 |
| 企业内网版 | 不上传代码，支持离线/私有模型 | 中高 |
| Delphi/Legacy 插件包 | 针对 VCL/FMX/Win32 老项目增强 | 高，适合差异化 |
| SaaS 协作版 | 云端项目、多人评审 | 后期考虑 |

账号体系：

```text
DeepSpec 客户端不自建独立云端账号；
云端账号、用户体系、官网分发和后续授权直接对接 deepkit.top。
```

### 13.2 免费 / 付费切分

免费层：

- 扫描 A；
- 通过框架 LLM 模块和提示词工程生成 B；
- 呈现三棵树、HTML、来源证据、当前文档状态、问题和人类决策；
- 让用户看见可视化需求体系。

付费层：

- A/B 需求校正；
- `A 未同步` 队列；
- 面向 A 的需求修订 Prompt / Patch；
- 代码与需求一致性校正；
- Git Diff / Review Pack / 漂移检测；
- Delphi/Legacy 深度增强；
- 企业本地/内网/私有模型能力。

收费起点：

```text
免费止于需求可视化 + 建议 + B 内决策；
收费从 A/B 校正、代码与需求一致性、Review Pack、CLI 调度开始。
```

第一版发布策略：

```text
第一版直接开源免费；
免费开源不改变后续付费能力边界。
```

---

## 14. 关键风险

| 风险 | 表现 | 应对 |
|---|---|---|
| 定位滑入 PRD 生成器 | 用户只把它当文档生成工具 | 强调“审阅 AI 理解”，不是“替你写 PRD”。 |
| HTML 体验不够强 | 用户觉得和 Markdown 差不多 | MVP 必须做出对照、跳转、风险聚合、三树联动。 |
| YAML Schema 过早复杂 | AI 难以稳定输出 | 先保持少字段、强校验、逐步扩展。 |
| 上下文打包质量差 | AI 输出幻觉多 | 文件筛选、token 预算、源证据要求必须是核心能力。 |
| 竞品快速覆盖 | Kiro/Spec Kit 加入类似视图 | 以本地旁路审阅、A/B 规格化目录、Delphi/legacy、HTML 体验差异化。 |
| 语义责任过重 | 用户认为 DeepSpec 应该保证 B 一定正确 | 明确 B 由框架 LLM 模块调用用户配置或已有 AI 生成，DeepSpec 负责任务编排、提示词工程、校验和可视化审阅。 |
| 用户不愿闭环修底层文件 | 期望在 DeepSpec 里直接编辑 | 免费层呈现问题；付费层提供需求/代码校正能力。 |

---

## 15. 验证计划

### 验证批次

- 选 2 个真实项目：一个 DeepSpec 自身，一个 Delphi/VCL 项目；
- 定义三树 YAML 最小 Schema；
- 写第一版 Prompt 模板和 LLM 任务模板；
- 通过框架 LLM 模块调用 Claude/Codex 等模型生成 YAML，必要时手工对照；
- 记录 AI 最常犯的格式和理解错误。

- 将样例 YAML 渲染为单文件 HTML；
- 做总览页、三树页、问题页；
- 每个节点显示来源文件和置信度；
- 和纯 Markdown 输出做可读性对比。

- DeepShell 壳层加载项目；
- 左右悬浮窗挂三棵树；
- WebView2 显示 HTML；
- 支持导入 YAML、刷新 HTML。

- 找 3 个真实旧项目做闭环测试；
- 用"B 生成 / 审阅任务"让框架 LLM 模块完善 B，必要时导出 Prompt 给外部 AI；
- 重新生成，对比错误是否减少。

### 啊哈时刻场景（2026-05-14 补充）

MVP 必须能在 demo 中 3 分钟内演示以下两个场景：

场景 A："AI 把登录和注册混为一谈"

```text
用户项目 README 写了"用户登录"，设计文档写了"注册流程"，但没有明确区分。
  
DeepSpec 生成功能树后，把"登录"和"注册"合并成一个节点
  
置信度标为 medium
  
问题清单标记：conflict  README 说登录，设计文档说注册，是同一个功能还是两个？
  
用户看到问题，做决策"这是两个独立功能"
  
DeepSpec 写回 B，生成提示词
  
用户把提示词粘贴给自己的 Claude / Cursor / Codex
  
AI 帮用户补充 README 中的登录/注册区分
  
重新扫描后，两个节点分开，问题消失
```

场景 B："AI 漏掉了权限边界"

```text
用户项目有 5 个页面，但文档里从没说过"谁能访问哪个页面"
  
DeepSpec 需求健康图标红：权限未说明
  
来源证据图显示：5 个视图节点，0 个权限约束
  
用户点击后看到提示词：
  "请为以下 5 个页面补充角色权限说明：管理员/普通用户/访客分别能看到什么、能操作什么。"
  
用户复制到 Claude Code
  
AI 补完文档
  
重新扫描后权限问题消失
```

这两个场景直接证明 DeepSpec 的核心价值："让你事前看出 AI 会误解什么"。

### 验证指标

- 用户是否能在 10 分钟内看懂项目结构；
- 用户是否能指出 AI 理解错误；
- HTML 是否明显优于 Markdown；
- 重新生成后错误是否减少；
- 用户是否愿意把这个流程放进真实 AI 开发前置步骤。

---
## 16. 当前建议

1. **产品主线定为“规格审阅”，不是“规格生成”。**
2. **MVP 坚持只读，不做树编辑器。**
3. **第一层默认调用成熟的框架 LLM 模块，复制 Prompt 只是导出和兜底；不把用户 CLI 调度作为免费 MVP 主线。**
4. **HTML 审阅页必须作为第一等公民设计。**
5. **三树 YAML Schema 先小后大。**
6. **用 Delphi/VCL 项目作为差异化样板，但不要把市场锁死在 Delphi。**
7. **蓝海表述要谨慎：DeepSpec 是红海邻域里的蓝海楔子。**

---

## 17. 结论

DeepSpec 的机会不是“AI 帮你写 PRD”，也不是“AI 帮你理解代码”。这些方向已经拥挤。

DeepSpec 真正有价值的命题是：

**在 AI 写代码之前，先把 AI 对项目的理解变成可审阅的规格界面。**

如果 DeepSpec 能把散乱项目材料稳定转成三棵树，并用 HTML/VCL 做出明显优于 Markdown 的审阅体验，它就有机会在 AI 开发工具链中占据一个独立位置：**规格理解与审阅层**。
