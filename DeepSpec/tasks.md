# DeepSpec 开发任务清单

> 基线：Delphi 13.1 / DeepBase / DeepShell / VCL / Win64
> 协议：DeepSpec 三棵树通用协议 v1.1
> 状态：31271 行编译通过，EXE 9.4MB，0 错误，0 自身 warning

---

## 全部 P0-P5 主要功能 ✅

### P0：DeepShell 壳接入 ✅
- [x] DeepSpec.dpr / .dproj
- [x] TDeepSpecMainForm（继承 TDeepMainForm）
- [x] 6 个命令注册（Open/Scan/Generate/Render/Export/SetupLLM）
- [x] 3 个 Provider 注册（Structure/MainView/Inspector）

### P1：项目扫描和 .deepspec 落地 ✅
- [x] 项目打开（SelectDirectory）
- [x] 文件扫描引擎（递归 + 分类 + 忽略规则，按协议 §14.1）
- [x] .deepspec 目录生成（含 .gitignore）
- [x] HTML 渲染（scan-report + index）

### P2：三棵树 + 数据模型 + LLM ✅
- [x] 完整数据模型（Node/Relation/Evidence/Issue/Decision + 12 种 enum）
- [x] YAML 写入器（覆盖协议全部 Schema）
- [x] YAML 解析器（block-style mapping/sequence/scalar）
- [x] 三棵树 HTML 渲染（带 status/confidence/source_layer 徽章）
- [x] TreeBuilder（无 LLM 也能生成基础三树）
- [x] Context Pack + 4 种 Prompt 模板
- [x] DeepBase LLM facade 封装（TDeepSpecLLMService）
- [x] **真实 LLM 调用**（异步线程 + 候选 B 写入 llm/candidate-output.yaml）
- [x] **LLM 配置工具**（ModelScope OpenAI 兼容端点）
- [x] Schema 校验器（节点 ID、kind、status 校验 + LLM 安全规则）

### P3：HTML 决策写回 + 提示词导出 ✅
- [x] 4 种 Prompt 输出（context-pack / generation / node / decision-rewrite）
- [x] Decision 服务（Load/Save/Accept/Reject/AcceptDecision）
- [x] content_hash 并发控制（SHA-256，分语义/装饰两层）
- [x] file SHA-256（用于 evidence source_file_hash）
- [x] **WebView2 集成**（TEdgeBrowser 内嵌 HTML 审阅）

### P4：Delphi/VCL 增强 ✅
- [x] Delphi 文件识别
- [x] DFM 解析器（text format，binary 检测不崩溃）
- [x] PAS 解析器（unit/class/interface/uses 提取）
- [x] TreeBuilder 集成 Delphi 解析器（自动生成更丰富的模块/视图树）

### P5：质量加固 + JS Bridge ✅
- [x] **0 自身 warning**（清理 W1009/W1029/W1057/H2219）
- [x] **YAML 解析器边界加固**：
  - 代码围栏 ` ```yaml ... ``` ` 自动剥离
  - UTF-8 BOM 容忍
  - `---` 文档分隔符容忍
  - Tab 自动转换为空格
  - 行尾 `# 注释` 处理（quote-aware）
  - 块字面量 `|` 与折叠 `>` 多行 scalar
  - Flow 序列 `[a, b, c]` 解析
- [x] **JS Bridge 决策回写**（HTML → DeepShell）：
  - HTML 候选节点旁渲染 Confirm/Reject 按钮
  - 按钮通过 `window.chrome.webview.postMessage` 投递
  - WebView2 `OnWebMessageReceived` 解析 JSON
  - 追加写入 `.deepspec/decisions/pending-decisions.yaml`
  - 普通浏览器中显示 fallback 提示
- [x] **Promote Pending Decisions**：
  - `TDeepSpecDecisionsService.PromotePending` 把 pending 条目转换为正式 decision
  - 命令 `deepspec.decisions.promote` 暴露给菜单
  - `node-confirm` → `dtConfirm` + accepted；`node-reject` → `dtReject` + rejected
- [x] **Render HTML 命令** (`deepspec.html.render`)：脱离扫描重渲染所有 HTML
- [x] **YAML 端到端往返**：
  - `TSpecEnums` 增补 `TreeTypeFromStr` / `NodeStatusFromStr` / `ConfidenceFromStr` / `SourceLayerFromStr`
  - `TDeepSpecStoreService.ReadTreeFile` 读 YAML 还原 `TList<TSpecNode>`
  - `Controller.RefreshFromYaml` + 命令 `deepspec.html.refresh-from-yaml`：
    手改 YAML 后无需 rescan 即可刷新 HTML，端到端验证 Writer ↔ Parser 闭环

---

## 协议包独立交付 ✅

`DeepSpec/protocol/`:
- 7 个 JSON Schema 形式化定义
- 4 个种子项目（React/Go/Python/Docs-only）
- TypeScript / Python 参考 reader
- 兼容性测试套件（fixtures + run.py）
- 10 分钟集成指南 + Reader Profile
- GOVERNANCE.md
- Apache-2.0 LICENSE

---

## 使用流程（端到端）

1. 启动 `bin\Win64\Debug\DeepSpec.exe`
2. 菜单 **Tools → Setup LLM (ModelScope)**：粘贴 API Key 和模型名（如 `Qwen/Qwen2.5-72B-Instruct`）
3. 菜单 **File → Open Project**：选择项目文件夹
4. 自动扫描 → 生成 `.deepspec/` → 写 YAML → 渲染 HTML 到 WebView2
5. 菜单 **Run → Generate B**：调用 LLM 生成候选 B（`.deepspec/llm/candidate-output.yaml`）
6. 菜单 **Tools → Export Prompt**：导出 Context Pack + 生成提示词
7. 在 WebView2 内点 **Confirm/Reject** → 写入 `pending-decisions.yaml`
8. 菜单 **Tools → Promote Pending Decisions**：把 pending 条目转换为正式 decision
9. 菜单 **View → Render HTML**：脱离扫描重渲染（用于手动编辑 YAML 后刷新）
10. 菜单 **View → Refresh HTML from YAML**：从硬盘 YAML 重新解析三树并渲染（端到端往返）

---

## 代码统计

| 模块 | 单元数 |
|------|------|
| app/ | 4 |
| services/ | 9 (Project/Scan/SpecStore/Render/TreeBuilder/Prompts/Decisions/LLM/LLMConfig) |
| providers/ | 3 (Structure/MainView/Inspector) |
| controllers/ | 1 |
| models/ | 1 |
| core/ | 7 (Yaml.Writer/Yaml.Parser/Hash/Delphi.DfmParser/Delphi.PasParser/Validation) |
| **DeepSpec 单元总数** | **25** |

编译总行数（含 DeepBase）：26597 行
EXE：8.1 MB（Debug Win64）
0 编译错误

---

## 无法在 AI 会话独立完成的剩余工作

| 项 | 原因 | 谁来做 |
|----|------|------|
| WebView2 Runtime 未安装时的体验 | 依赖运行环境 | 用户验证 / 安装 Runtime |
| LLM 实际调用稳定性 | 依赖网络、API 配额、模型行为 | 联调测试 |
| 跨平台测试 | Win64 only | 后续移植 |
| 5 个真实项目封版验证 | 需要时间和真实样本 | P6 阶段 |

---

## 下一步建议

1. 在 IDE 或命令行运行 `bin\Win64\Debug\DeepSpec.exe`
2. **Setup LLM** → 输入 ModelScope API Key
3. **Open Project** → 选择 `D:\_Progs\02Business\DeepSpec` 自身做测试
4. 检查 `.deepspec/` 目录生成
5. **Generate B** → 看看 LLM 输出
6. WebView2 应该自动加载 `.deepspec/html/index.html`
