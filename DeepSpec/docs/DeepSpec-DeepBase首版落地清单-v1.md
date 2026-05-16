# DeepSpec DeepBase 首版落地清单 v1

> 日期：2026-05-14  
> 状态：执行清单  
> 前置文档：`DeepSpec-借力DeepBase框架接入方案-v1.md`

---

## 1. 总路线

DeepSpec 第一版按这个顺序落地：

```text
DeepShell 壳接入
  ↓
项目打开 / 扫描 / .deepspec 文件落地
  ↓
三树和 HTML 假数据闭环
  ↓
DeepBase LLM 生成候选 B
  ↓
Schema 校验 / 合并 B
  ↓
HTML + JS Bridge 决策写回
  ↓
3-5 个真实项目验证
```

核心原则：

```text
先跑通 B 的事实闭环，再追求图表丰富度；
先复用 DeepBase 基础设施，再写 DeepSpec 业务代码；
先做本地桌面审阅工具，再考虑第二层校正能力。
```

---

## 2. P0：DeepShell 壳接入

目标：DeepSpec 启动后已经是一个 DeepShell 工作台，而不是空 VCL 窗体。

任务：

- 创建 `TDeepSpecMainForm = class(TDeepMainForm)`；
- 覆盖 `RegisterServices`、`RegisterCommands`、`RegisterProviders`；
- 接入 DeepBase 初始化：`DeepBase.InitializeOrRaise`；
- 使用 `root.txt + ConfigDB`；
- 状态、日志、布局、MRU、主题使用 DeepBase / DeepShell；
- 注册最小命令：
  - `deepspec.project.open`
  - `deepspec.scan.run`
  - `deepspec.spec.generate`
  - `deepspec.html.render`
  - `deepspec.prompt.export`
- 注册最小 Provider：
  - `DeepSpecStructureProvider`
  - `DeepSpecMainViewProvider`
  - `DeepSpecInspectorProvider`
  - `DeepSpecSettingsProvider`

验收：

- 能启动；
- 能打开左右悬浮区；
- 能显示 fake 文件树 / fake 三树；
- 能在主区域显示 fake HTML；
- 能输出状态和日志；
- 关闭后恢复布局。

---

## 3. P1：项目扫描和 `.deepspec` 落地

目标：打开真实项目目录后生成 B 的基本目录结构。

任务：

- 打开项目目录；
- 按忽略规则扫描文件；
- 分类：
  - 文档；
  - 代码；
  - UI；
  - 配置；
  - AI 规则；
- 生成 `.deepspec/scan-report.yaml`；
- 生成 `.deepspec/project-spec.yaml` 总索引；
- 生成最小事实文件：
  - `trees/function-tree.yaml`
  - `trees/module-tree.yaml`
  - `trees/view-tree.yaml`
  - `relations/requirement-relations.yaml`
  - `evidence/source-evidence.yaml`
  - `issues/doc-issues.yaml`
- 生成 `html/index.html` 和 `html/node-detail.html`；
- 原生树和 HTML 通过 `node_id` 联动。

边界：

- 不把 B 写进 DB1；
- DB1 只保存应用设置、布局、MRU、Secret、LLM 配置和账号授权状态；
- `.deepspec` 是项目规格事实源。

验收：

- 任意项目目录进来后能生成 `.deepspec`；
- HTML 能显示扫描摘要；
- 三棵树能显示候选节点；
- 节点详情能显示来源和置信度。

---

## 4. P2：DeepBase LLM 生成候选 B

目标：直接调用 DeepBase LLM facade，生成候选 B。

任务：

- 使用 DeepBase 五槽模型：
  - `TierSmart`：A -> B 主生成；
  - `TierBalanced`：节点审阅；
  - `TierFast`：轻量摘要和分类；
- API Key / Token 走 `DeepBase.Security`；
- LLM 配置走 DeepBase 设置页 / ConfigDB；
- 构建 Context Pack；
- 生成 Prompt 模板；
- 调用 DeepBase LLM facade；
- 输出：
  - `llm/generation-task.yaml`
  - `llm/candidate-output.yaml`
  - `llm/validation-report.yaml`
  - `llm/merge-report.yaml`

校验：

- Schema 校验；
- 来源引用检查；
- 冲突检查；
- accepted decision 覆盖保护；
- 低置信标记。

合并：

```text
candidate-output.yaml
  ↓
validation-report.yaml
  ↓
merge-report.yaml
  ↓
trees / relations / evidence / issues / decisions
```

验收：

- LLM 输出不会直接覆盖 B；
- 校验失败进入问题清单；
- 校验通过后合并到 B；
- HTML / 三树重新渲染。

---

## 5. P3：HTML + JS Bridge 决策写回

目标：人类在 HTML 上点击，生成候选 Decision Record，经确认后写入 B。

任务：

- HTML 页面生成稳定 `data-node-id`；
- HTML 按钮只发送事件，不写事实；
- JS Bridge 传递：
  - `node_id`
  - `action`
  - `payload`
- DeepShell / DeepSpec 接收事件；
- 生成候选 Decision Record；
- 用户确认；
- 写入：
  - `decisions/requirement-decisions.yaml`
  - `decisions/requirement-decisions.md`
  - `decisions/ai-requirement-context.generated.md`
- 重新计算当前规格判断；
- 重新渲染 HTML 和三树。

可用 DeepBase 能力：

- BrowserAutomation / WebView2；
- JS 注入；
- ScriptStore；
- EventBus；
- Resilience。

边界：

- HTML 不直接写 YAML；
- HTML 不保存事实状态；
- BrowserAutomation 不优先用于自动操作外部 AI 网页；
- 外部 AI 自动化后置到辅助能力或第三层。

验收：

- 点击 HTML 节点能反选 DeepShell 树节点；
- 点击决策按钮能生成候选 Decision Record；
- 确认后写入 B；
- 页面刷新后决策仍存在；
- accepted decision 能覆盖 AI 推断。

---

## 6. P4：deepkit.top 账号入口

目标：第一版开源免费，但保留 deepkit.top 账号对接能力。

任务：

- 不强制登录使用第一层核心能力；
- 提供账号入口；
- 使用 DeepBase Commerce / SafeClient / DesktopLifecycle；
- deepkit.top 提供账号、官网分发和后续授权；
- 客户端不自建账号系统；
- 客户端不直连 DB4。

第一版用途：

- 用户身份；
- 反馈；
- 更新；
- 后续授权入口；
- 未来付费能力门禁。

验收：

- 未登录可打开项目、扫描、生成 B、查看 HTML；
- 登录入口存在；
- 登录失败不阻断第一层本地核心流程；
- 后续付费功能可接 Permissions。

---

## 7. P5：验证样例

必须用三类项目验证：

1. DeepSpec 自身；
2. Delphi / VCL 项目；
3. 非 Delphi 的现代 Web / 工具项目。

验证指标：

- 10 分钟内能看懂需求结构；
- 三棵树能反映功能、模块、视图；
- 来源证据能追溯；
- 问题清单能发现缺口、冲突、低置信；
- 决策能写回 B；
- 重新渲染后状态一致；
- 用户能指出 AI 理解错误。

通过前不进入第二层。

---

## 8. 不做清单

首版不做：

- 自建桌面壳；
- 自建 LLM provider 管理；
- 自建账号系统；
- 自建支付授权；
- 自建 WebView2 自动化底层；
- B 写入 ConfigDB；
- HTML 保存事实状态；
- 自动改 A；
- 代码与需求一致性；
- Git Diff / Review Pack；
- CLI 调度开发；
- 外部 AI 网页自动操作作为主流程。

---

## 9. 开源边界

第一版开源免费，协议：

```text
Apache-2.0
```

开源范围：

- 第一层需求可视化；
- `.deepspec` 文件格式；
- 三树和 HTML 审阅；
- B 内决策写回；
- DeepBase 接入示例。

后续付费能力：

- A/B 需求校正；
- 代码与需求一致性；
- Review Pack；
- CLI 调度；
- 企业内网 / 私有模型 / 团队协作。

---

## 10. 当前判断

DeepBase 已经把 DeepSpec 最容易分心的基础设施问题解决了。

DeepSpec 第一版的胜负点不在框架，而在：

```text
B 的事实模型是否稳；
三树和 HTML 是否真的比 Markdown 好审阅；
LLM 候选 B 是否可校验、可追溯、可合并；
人类决策是否能自然写回 B；
真实项目是否能暴露 AI 理解偏差。
```
