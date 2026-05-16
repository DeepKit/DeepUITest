# DeepSpec 借力 DeepBase 框架接入方案 v1

> 日期：2026-05-14  
> 状态：当前工程判断  
> 阅读来源：  
> `D:\_Progs\02Business\DeepBase\docs\52.extend.BrowserAutomation接入指南.md`  
> `D:\_Progs\02Business\DeepBase\docs\76.vcl.DeepShell-新VCL程序接入指南.md`  
> `D:\_Progs\02Business\DeepBase\docs\00.quickstart.AI集成总览-ai-one-file.md`  
> `D:\_Progs\02Business\DeepBase\docs\01.quickstart.对外集成入口-integration-onefile.md`  
> `D:\_Progs\02Business\DeepBase\docs\02.quickstart.下游接入流程-downstream-integration.md`

---

## 1. 总判断

DeepSpec 不应该自建基础框架。

DeepSpec 应把 DeepBase 当作底座，把自己收敛成：

```text
需求规格业务层 + 三树/图表渲染层 + B 事实管理层
```

DeepBase 已经提供的能力应直接复用：

- DeepShell VCL 工作台；
- ConfigDB / root.txt / 配置管理；
- 日志、状态、布局、MRU、主题、i18n；
- Security / Secret；
- LLM facade / 五模型槽；
- Commerce / deepkit.top 账号与授权；
- BrowserAutomation / WebView2 / JS 脚本注入；
- EventBus、Resilience、WorkerQueue；
- VCL/FMX 基础包结构。

DeepSpec 不再重复实现：

- 桌面壳；
- 设置页；
- 日志面板；
- LLM API Key 保存；
- LLM provider 配置；
- 账号和授权；
- WebView2 会话管理；
- 浏览器自动化和 JS 注入底层；
- UI 线程重试和长耗任务调度。

---

## 2. DeepShell 对 DeepSpec 的意义

DeepShell 文档已经明确 DeepSpec 是典型适用场景。

DeepSpec 主窗体应从 `TDeepMainForm` 起步：

```pascal
type
  TDeepSpecMainForm = class(TDeepMainForm)
  protected
    procedure RegisterServices; override;
    procedure RegisterCommands; override;
    procedure RegisterProviders; override;
  end;
```

DeepSpec 应按 DeepShell 的三类扩展点组织：

| DeepShell 扩展点 | DeepSpec 对应 |
|---|---|
| Services | ProjectService、ScanService、SpecStore、LLMTaskService、RenderService、DecisionService |
| Commands | OpenProject、RunScan、GenerateB、RenderHtml、ExportPrompt、WriteDecision |
| Providers | StructureProvider、MainViewProvider、InspectorProvider、SettingsPageProvider |

DeepShell 的价值：

- 主窗体、工具栏、左右悬浮窗、底部日志、设置页不重造；
- 原生树控件用于文件树、功能树、模块树、视图树；
- WebView2 / HTML 作为主审阅区；
- 设置页只追加 DeepSpec 业务配置；
- 统一状态接口显示扫描、LLM、渲染、校验进度。

结论：

```text
DeepSpec 的 UI 架构应是 DeepShell Provider 插件式业务实现，
不是从 TForm 重新做一个桌面程序。
```

---

## 3. DeepBase LLM 对 DeepSpec 的意义

DeepBase 已经定义下游不要私改 LLM 底层适配层，应通过 facade / API 对接。

DeepSpec 第一层已经决定“直接调用成熟的框架 LLM 模块”。这与 DeepBase 文档完全一致。

DeepSpec 应使用 DeepBase 的 LLM 五槽模型：

| 槽位 | DeepSpec 用途 |
|---|---|
| `TierSmart` | A -> B 主生成、冲突消解、复杂规格推断 |
| `TierBalanced` | 节点审阅、问题解释、普通 B 修订 |
| `TierFast` | 扫描摘要、轻量分类、提示词预览 |
| `TierImageGen` | 暂不作为 MVP 主线 |
| `TierImageFallback` | 未来截图 / UI 图像证据识别兜底 |

DeepSpec 必须遵守：

- API Key / Token 走 `DeepBase.Security`；
- 不明文写 Settings、日志或业务表；
- UI 线程不做同步长耗 LLM；
- LLM 输出先进入候选 B；
- DeepSpec 做 Schema 校验、来源检查、冲突检查后合并。

建议工程分层：

```text
deepspec_llm/
  context_builder
  task_runner
  candidate_parser
  validation
  merge
```

其中 `task_runner` 调用 DeepBase LLM facade，不直接访问 provider 适配器。

---

## 4. BrowserAutomation 对 DeepSpec 的意义

DeepSpec 的 HTML 不是普通报告，而是人类审阅和点击决策层。

DeepBase BrowserAutomation 提供：

- WebView2 默认实现；
- JS 脚本注入；
- 同步 / 异步动作；
- MutationObserver 响应等待；
- 选择器自愈；
- 事件总线；
- Recovery；
- ScriptStore，可运行时调整 JS 模板；
- WebView2 异步并发。

DeepSpec 应复用其中两类能力。

### 4.1 内嵌 HTML 审阅页

DeepSpec 需要 WebView2 承载生成式 HTML 页面。

HTML 点击流程：

```text
用户点击 HTML 节点 / 按钮
  ↓
JS Bridge 捕获 node_id + action
  ↓
DeepShell / DeepSpec 生成候选 Decision Record
  ↓
用户确认
  ↓
写入 B 的 YAML 事实文件
  ↓
重新渲染 HTML / 三树
```

BrowserAutomation 的 WebView2、JS 注入、ScriptStore 可直接承载这条链路。

### 4.2 外部 AI 页面自动化不是第一层主线

BrowserAutomation 也能自动操作外部网页 AI 工具，但这不应成为第一层 MVP 主线。

原因：

- 第一层默认调用 DeepBase LLM 模块；
- 外部网页 AI 自动化容易脆弱；
- 用户仍可导出 Prompt 作为兜底；
- 自动操控外部 AI 页面更接近第三层或辅助工具能力。

结论：

```text
MVP 优先用 BrowserAutomation / WebView2 支撑 DeepSpec 自己的 HTML 审阅页和 JS Bridge；
不要优先做“自动打开 ChatGPT/Cursor 网页并粘贴 Prompt”。
```

---

## 5. Commerce / deepkit.top 对 DeepSpec 的意义

DeepBase 文档明确桌面端账号、权限、付费升级、授权快照、更新应走 Desktop Lifecycle 和 DeepKit SafeClient。

DeepSpec 已定：

```text
云端账号由 deepkit.top 网站提供，客户端直接对接。
```

DeepSpec 不应自建账号系统。

第一版开源免费时：

- 可以不强制登录；
- 可以保留 deepkit.top 账号入口；
- 可以用于更新、反馈、未来授权；
- 不能把第一层核心使用绑死在登录上。

后续付费能力：

- A/B 校正；
- 代码与需求一致性；
- Review Pack；
- CLI 调度；
- 企业内网 / 私有模型；

应通过 DeepBase Commerce / Permissions 做功能门禁。

---

## 6. ConfigDB / DB 边界

DeepBase 的配置铁律是：

```text
唯一外部配置文件是 root.txt；
配置、状态、治理规则统一存 DB1 ConfigDB。
```

DeepSpec 要区分两类存储：

| 存储 | 归属 | 内容 |
|---|---|---|
| DB1 ConfigDB | DeepBase 框架层 | 设置、布局、MRU、主题、语言、日志、Secret、LLM 配置、账号授权状态 |
| `.deepspec/` | DeepSpec 项目规格层 | B 的 YAML 事实文件、HTML、决策、LLM 候选输出、证据、问题 |

DeepSpec 不应把 B 的核心事实塞进 DB1。

原因：

- B 是项目工件，应该跟项目目录和 Git 走；
- AI 需要读 YAML；
- 人类需要查 `.deepspec`；
- HTML 可以删除重生成；
- DB1 是本机应用配置，不是项目规格事实源。

---

## 7. 安全和线程原则

DeepSpec 必须继承 DeepBase 的硬约束：

- API Key / Token 走 `DeepBase.Security`；
- 不明文写日志；
- 客户端不直连 DB4；
- UI 主线程不做同步重试、Sleep、长耗 LLM；
- 长耗扫描、LLM、渲染、校验走 WorkerQueue / Resilience / async；
- 高风险动作未来走 Governance / ActionGrid。

对 DeepSpec 的直接影响：

- `GenerateB` 不能阻塞 UI；
- `RunScan` 对大项目要可取消、可进度；
- `RenderHtml` 可以后台生成，主线程只切换 WebView；
- `WriteDecision` 是低风险写 B 操作，但仍应有确认；
- 第二层 Patch / 改 A / 调 CLI 是高风险动作，未来必须接 Gate。

---

## 8. 包和工程建议

DeepSpec 作为 VCL 桌面工具，建议依赖：

```text
DeepBaseCore
DeepBaseServices
DeepBasePersistence
DeepBaseFeatures
DeepBaseVCL
```

运行时不依赖 `dclDeepBaseVCL`。

最小工程结构建议：

```text
DeepSpec.dpr
DeepSpec.dproj
src/
  DeepSpec.MainForm.pas
  DeepSpec.Services.pas
  DeepSpec.Commands.pas
  DeepSpec.Providers.pas
  DeepSpec.Project.pas
  DeepSpec.Scan.pas
  DeepSpec.SpecStore.pas
  DeepSpec.LLMTasks.pas
  DeepSpec.Render.pas
  DeepSpec.Decisions.pas
resources/
  html/
  css/
  js/
tests/
samples/
```

DeepSpec 主窗体只做注册，不做业务。

---

## 9. 我对落地优先级的判断

### P0：DeepShell 壳接入

- `TDeepSpecMainForm = class(TDeepMainForm)`；
- 注册 OpenProject / RunScan / RenderHtml 命令；
- 注册 StructureProvider、MainViewProvider、InspectorProvider；
- WebView2 能显示生成 HTML；
- 原生树能显示 fake 三树；
- 状态和日志走 DeepShell / DeepBase。

### P1：项目扫描和 B 文件落地

- 打开项目；
- 生成 `.deepspec/scan-report.yaml`；
- 生成 fake / sample B；
- 渲染 HTML；
- 树与 HTML 通过 `node_id` 联动。

### P2：DeepBase LLM 接入

- 构建 A -> B Context Pack；
- 调用 DeepBase LLM facade；
- 输出 `llm/candidate-output.yaml`；
- 校验和合并到 B；
- 记录 validation / merge report。

### P3：HTML 点击写回

- HTML + JS Bridge；
- 点击节点生成候选 Decision Record；
- 用户确认；
- 写入 `.deepspec/decisions/requirement-decisions.yaml`；
- 重新渲染 HTML / 三树。

---

## 10. 风险判断

| 风险 | 判断 | 处理 |
|---|---|---|
| 过度依赖 BrowserAutomation 自动操作外部网页 | 不适合 MVP 主线 | 只用于内部 WebView2 / JS Bridge，外部 AI 自动化后置 |
| DeepBase LLM 统一层仍在优化 | 可接受 | 只走 facade/API，不改底层适配器 |
| B 与 ConfigDB 边界混乱 | 高风险 | B 坚持 `.deepspec` YAML，DB1 只放配置状态 |
| DeepShell Provider API 与文档不完全一致 | 可控 | 以实际 API 为准，文档里的 fluent builder 不硬写不可编译代码 |
| 第一版开源免费但未来付费 | 可控 | 开源第一层，付费从校正/一致性/CLI/企业能力开始 |

---

## 11. 结论

DeepBase 对 DeepSpec 的最大价值不是某个单点 API，而是让 DeepSpec 不再浪费时间做基础设施。

DeepSpec 应专注：

```text
A -> B
B -> 三树 / 图表 / HTML
HTML 决策 -> B
B -> 后续第二层校正
```

DeepBase 负责：

```text
壳、配置、日志、安全、LLM、账号、授权、WebView2、Resilience、事件和基础桌面能力。
```

这是正确分工。
