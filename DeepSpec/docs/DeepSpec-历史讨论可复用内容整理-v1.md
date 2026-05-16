# DeepSpec 历史讨论可复用内容整理 v1

> 日期：2026-05-14  
> 来源目录：`发散讨论/`  
> 目的：从早期发散讨论中抽取仍然有用的产品原则、MVP 边界、工程设计和后续路线，并按当前定位重新整理。

---

## 1. 当前应采用的新口径

DeepSpec 当前定位已经从早期的“旁路规格治理系统”“可视化需求规格生成系统”“项目开发文档与结构树读取呈现系统”，升级为：

**所见即所得的开发文档优化器。**

更准确表述：

**DeepSpec 是用户原有 AI/IDE 工作流旁边的旁路工具。它不接管开发、不替代聊天、不要求迁移，只读取同一个项目目录，提供更好的查阅界面、上下文组织和相关提示词，帮助用户用原来的 AI 工具优化底层开发文档。**

---

## 2. 从历史讨论中保留的核心原则

| 原则 | 当前解释 |
|---|---|
| 旁路增强 | DeepSpec 不进入主开发链路，只在旁边读取、呈现、提示。 |
| 不替代用户 AI | 用户继续使用 Claude Code、Cursor、Codex、IDE、CLI。 |
| 读取已有项目 | 第一入口是拖入/打开项目文件夹，不是从零问答生成需求。 |
| 树用原生控件，文档用 HTML | 三棵树是操作对象，复用 DeepShell 的原生树控件；报告、详情、摘要、提示词用 HTML/WebView2。 |
| YAML 是事实源，HTML 是审阅层 | HTML 不作为唯一事实源，结构化结果应可保存为 YAML。 |
| 只读优先 | DeepSpec 展示问题和生成提示词，真正修改回到用户原工具。 |
| 证据优先 | 节点、问题、建议要尽量指向来源文件、片段、控件或代码。 |
| 先定形，再生成 | 先把项目材料读成结构基准，再让 AI 继续优化或开发。 |
| 项目事实进项目目录，个人布局进本机配置 | `.deepspec` 存项目事实；窗口布局和最近项目存在本机。 |

---

## 3. 从历史讨论中保留的产品资产

### 3.1 三棵树

历史讨论中的“三棵基准树”仍然是产品主骨架，但需要按当前定位改名和解释：

| 历史名称 | 当前建议名称 | 作用 |
|---|---|---|
| 候选功能树 / 功能基准树 | 功能树 | 展示 AI/规则从文档、UI、代码中理解出的产品能力。 |
| 模块基准树 | 模块树 | 展示项目目录、单元、类、服务和职责边界。 |
| UI 层次树 / UI 基准树 | 视图树 | 展示用户看到的窗体、页面、控件和交互层级。 |

当前 MVP 应接受一个现实：功能树有较强推断成分，必须显示来源和置信度；模块树和视图树可以更多依赖项目事实。

### 3.2 文件扫描与分类规则

保留以下扫描分类：

- 文档：`.md`、`.txt`、`.html`、`.yaml`、`.json`、README、需求、设计、接口、TODO、Handoff。
- 代码：优先 `.dpr`、`.dproj`、`.pas`、`.dfm`，后续扩展 Web/Python/C#/Go/Java。
- UI：`.dfm`、`.fmx`、HTML 原型、CSS、图片、截图。
- 配置：`.ini`、`.json`、`.yaml`、`.config`、`.env.example`。
- AI 规则：`AGENTS.md`、`CLAUDE.md`、`.cursor/rules`、`opencode.json`、`README_AI.md`。

默认忽略：

```text
.git
.svn
.hg
node_modules
bin
obj
__history
__pycache__
dist
build
.cache
.tmp
```

### 3.3 DeepShell 桌面壳

DeepShell 已由同事开发，DeepSpec 第一层应直接复用，不把 DeepShell 作为 DeepSpec 的自研范围。

保留 DeepShell 作为标准桌面壳的设计：

```text
主窗体轻，中间工作；
左右悬浮，多区多页；
上下折叠，多 Tab 承载。
```

DeepSpec 通过 Provider 接入已有 DeepShell：

- `TDeepSpecStructureProvider`：给左侧结构窗提供三棵树。
- `TDeepSpecInspectorProvider`：给右侧探查窗提供属性、来源、状态、关联、问题。
- `TDeepSpecMainViewProvider`：给中部 WebView2 提供 HTML 页面。
- `TDeepSpecCommandProvider`：注册打开项目、重新扫描、复制提示词、导出报告等命令。
- `TDeepSpecLogProvider`：输出扫描和解析日志。

### 3.4 `.deepspec` 目录

历史讨论中 `.deepspec` 目录规范仍然有价值，但要服务当前旁路定位。

```text
项目目录/
  .deepspec/
    project.yaml
    scan-report.yaml

    trees/
      function-tree.yaml
      module-tree.yaml
      view-tree.yaml

    issues/
      doc-issues.yaml

    prompts/
      context-pack.md
      doc-optimization-prompt.md
      node-prompt.md

    html/
      index.html
      scan-report.html
      function-tree.html
      module-tree.html
      view-tree.html
      issues.html
      prompt-preview.html
      node-detail.html

    logs/
      scan-log.txt
```

个人布局仍放本机：

```text
%LOCALAPPDATA%/DeepSpec/
  settings.json
  layout.json
  recent-projects.json
```

---

## 4. 需要降级为后续阶段的内容

以下内容在历史讨论中有价值，但不应进入当前 MVP 主线：

| 内容 | 当前处理 |
|---|---|
| 6 问 / 12 问需求采集向导 | 归档为未来“从零新建项目”能力，不作为当前主入口。 |
| 完整九类规格文档编辑体系 | 保留为内部参考，不要求 MVP 建完整编辑器。 |
| 红绿灯冻结状态机 | 保留概念，用于文档问题严重性，不做完整冻结流。 |
| Git Diff / Review Pack | 归入阶段二，当前只做项目材料扫描和提示词。 |
| CLI 调度开发工作台 | 归入阶段三，当前不调度用户开发工具。 |
| 完整 Agent 治理 | 归入长期路线，当前只提供旁路查阅和提示词。 |
| 树结构编辑器 | 暂不做，问题回到底层文件修正。 |

---

## 5. 历史讨论中仍可复用的口号

可继续使用：

- **拖入项目，看清结构。**
- **树用 VCL，文档用 HTML。**
- **先定形，再生成；先对齐，再开发；先留痕，再迭代。**
- **别人让 AI 更快写代码，DeepSpec 让 AI 不要写偏。**
- **开发前先看清 AI 理解了什么。**

需要更新的口号：

| 旧口号 | 新解释 |
|---|---|
| AI 在主线写代码，DeepSpec 在旁路守规范。 | 仍然成立，但“守规范”当前先落到“查阅界面 + 提示词 + 文档问题清单”。 |
| 不接管 AI 编程，只接住 AI 编程留下的工程后果。 | 更适合阶段二；MVP 先接住项目材料和文档缺口。 |
| 可视化软件需求规格生成系统。 | 过窄，容易像 PRD 生成器；当前应改为开发文档优化器。 |

---

## 6. 当前权威文档关系

建议以 `docs/` 下文档为当前权威，`发散讨论/` 作为历史材料。

当前主线文档：

1. `DeepSpec-定位升级-所见即所得开发文档优化器-v1.md`
2. `DeepSpec-产品蓝图与蓝海判断-v1.md`
3. `DeepSpec-历史讨论可复用内容整理-v1.md`
4. `DeepSpec-MVP实施蓝图-旁路查阅与三树-v1.md`
5. `DeepSpec-旁路查阅与提示词规范-v1.md`
6. `DeepSpec-DelphiVCL解析与验收-v1.md`

---

## 7. 结论

历史讨论中最有价值的不是某一个旧定位，而是四个长期原则：

```text
旁路，不接管；
读取已有项目，不重造工作流；
结构化规格给 AI，HTML/VCL 界面给人；
发现问题后回到底层开发文档优化。
```

这些原则应成为 DeepSpec 后续所有设计的判定标准。
