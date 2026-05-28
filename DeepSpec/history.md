# DeepSpec 开发历史

> 已完成的任务归档于此。按时间倒序排列。

---

## 2026-05-24 Phase 2~4 完成 (working tree)

### Phase 2: 正交状态 + 单元测试

#### C-P0：节点正交状态维度
- [x] TSpecNode 增加 `GenStatus: TGenStatus`（draft / generated / confirmed / skipped）
- [x] TSpecNode 增加 `ReviewStatus: TReviewStatus`（unreviewed / accepted / rejected / deferred）
- [x] `TSpecEnums` 增加序列化/反序列化方法
- [x] 旧 `Status: TNodeStatus` 映射逻辑：gen_status + review_status 组合兼容旧 status
- [x] YAML Writer 输出新字段（gen_status, review_status），旧 status 保留用于向后兼容
- [x] YAML Parser 读取新字段，回填旧 status
- [x] SpecStore.ReadTreeFile 向后兼容映射（旧 YAML 缺 gen_status/review_status 时从 status 派生）
- [x] Render HTML 展示双状态徽章（gen: / rev:）

#### A-P0：YAML Parser 单元测试
- [x] 创建 `tests/Test.DeepSpec.Yaml.Parser.pas`（DUnitX）
- [x] 测试用例：解析空树 / 单节点 / 嵌套子节点 / data-tree 专属字段 / 旧格式兼容
- [x] 边界：非法 YAML / 缺失字段 / 未知字段忽略
- [x] 编译并通过测试（41/41 pass）

#### A-P0：Validation 单元测试
- [x] 创建 `tests/Test.DeepSpec.Validation.pas`（DUnitX）
- [x] INV-1: ID 格式校验（前缀匹配树类型）
- [x] INV-3: Kind 受控词表校验（x_ 扩展）
- [x] 编译并通过测试（41/41 pass）

### Phase 3: 认知干预

#### D-P0：问题优先呈现
- [x] Render 新增 `RenderProblemsPage`：扫描所有树的问题列表
- [x] 问题类型：低置信度 / 无证据 / 未审阅 / 不确定 / 孤立节点
- [x] 跨树一致性检测：断裂的 cross-tree 引用（broken ref）
- [x] index.html 导航增加 "Problems" 链接
- [x] 连接到 RenderAll / RunScan / RefreshFromYaml

#### D-P0：信任信号体系
- [x] 节点卡片信任信号折叠展示（`<details>` 默认收起）
- [x] 信号内容：证据源 (source_refs) / 跨树引用 (related_*) / 决策历史 (decision_refs)
- [x] 各信号类型颜色区分 CSS

### Phase 4: 上下文管线 + 语义束 + 状态机

#### A-P1：上下文组装管线
- [x] `IContextSource` 可插拔接口 + `TContextChunk` 记录
- [x] `TContextAssembler`：优先级排序 + token 预算动态裁剪
- [x] 内置源：`TTreeContextSource` / `TDecisionContextSource` / `TStringContextSource`
- [x] 新单元 `DeepSpec.Services.Context.pas`

#### C-P1：语义束
- [x] Models 增加 `TSemanticBundle` 记录
- [x] SpecStore 增加 `WriteBundlesFile` / `ReadBundlesFile` 读写 bundles.yaml
- [x] Render problems 页面跨树引用断裂检测

#### C-P1：决策写回状态机
- [x] `TSpecEnums.CanTransitionGen` / `CanTransitionReview` 状态迁移合法性校验
- [x] `TSpecEnums.TryTransitionGen` / `TryTransitionReview` 原子迁移 + 错误提示
- [x] GenStatus 状态机：draft→generated→confirmed, draft/generated→skipped（confirmed/skipped 终态）
- [x] ReviewStatus 状态机：unreviewed→accepted/rejected/deferred, deferred→accepted/rejected（accepted/rejected 终态）
- [x] `ApplyNodeStatusTransitions`：accepted 决策自动传播到树 YAML 节点
- [x] Controller `PromotePendingDecisions` 集成自动状态迁移

---

## 2026-05-24 遗留 Validation + 语义束 UI (working tree)

### A-P0：Validation 剩余用例
- [x] INV-2: parent_id 引用存在性（invalid_parent_ref 规则 + 单元测试）
- [x] INV-4: gen_status / review_status 值合法性（invalid_gen_status / invalid_review_status 规则 + 单元测试）
- [x] INV-5: 循环依赖检测（circular_parent 规则 — 遍历 parent 链检测环 + 单元测试）
- [x] INV-6: content_hash 一致性（ValidateNodeHashes 方法，对 TSpecNode 列表校验）
- 关联公理：A2, A7

### C-P1：语义束审阅 UI
- [x] RenderBundlesPage 方法：读取 bundles → 展示各束 + 成员节点列表 + 状态/置信度徽章
- [x] Accept All / Reject All 按钮（data-action="bundle-accept/reject" + JS Bridge postMessage）
- [x] index.html 导航增加 "Bundles" 链接
- [x] Controller 三个渲染入口（OpenAndScan / RefreshFromYaml / RunScan）均接入 bundles 渲染
- 关联公理：A1

---

## 2026-05-20 Data-Tree 全链路实现 (commit `2a799fe`)

### DT-1：TreeBuilder 生成 data-tree 节点
- [x] TreeBuilder 增加 `FDataNodes: TList<TSpecNode>`
- [x] 新增 `BuildDataTreeFromDelphi` 方法：从 .pas 文件 published 段提取字段声明
- [x] 为每个 class 生成 entity 节点 + field 子节点（含 data_type）
- [x] 去重：`LEntitySlugs` 防止同名类重复
- [x] 暴露 `property DataNodes`
- [x] 编译通过：dcc64 零错误

### DT-2：Controller 集成 data-tree
- [x] `RenderAll` 增加 data-tree 渲染（有节点时）
- [x] `RefreshFromYaml` 读取 `data-tree.yaml` 并渲染
- [x] `RunScan` 写入 `data-tree.yaml` 后渲染
- [x] 日志消息增加 data 节点计数

### DT-3：Render 渲染 data-tree HTML
- [x] `index.html` 导航增加 "Data Tree" 链接
- [x] RenderNode 展示 data-tree 专属字段：data_type / risk_score / persistence 徽章
- [x] 新增 CSS 样式：badge-data-type / badge-risk-* / badge-persistence

### DT-4：Commands 注册 data-tree 命令
- [x] `deepspec.data.render` 命令注册

### DT-5：SpecStore 写入 data-tree
- [x] `WriteProjectSpec` 写入 `trees/data-tree.yaml`
- [x] `WriteEmptyTrees` 生成空 `data-tree.yaml`
- [x] `project-spec.yaml` 填充 `data_tree` 字段

---

## 2026-05-20 编译错误修复 (commit `2a799fe`)

### BUG-COMPILER-001：Models.pas 三处语法错误
- [x] `RiskLevelToStr` 缺 `class` 关键字
- [x] `DataKindFromStr` 缺 `=` 号（`'state'` 条件无法编译）
- [x] `RiskLevelToStr` 缺 `:` 冒号（`rlCritical` 分支）

### BUG-COMPILER-002：Writer.pas 四处语法错误
- [x] `WriteBoolKV` 使用了非法的 `if ... then` 表达式语法，改为 `IfThen()`
- [x] `WriteQuotedKVtarget_entity` 缺少左引号和左括号
- [x] `A.Cardinality` 应为 `ANode.Cardinality`
- [x] uses 缺少 `System.StrUtils`（`IfThen` 所在单元）

---

## 2026-05-20 文档与协议校正 (commit `5b7a2e6`)

- [x] 在 `D:\_Progs\02Business\DeepSpec` 初始化独立 Git 仓库
- [x] 新增根目录 `README.md` 和 `SPEC.md`
- [x] 新增 `docs/CTF.md`
- [x] 修复 `protocol/schemas/*.json` JSON 语法错误
- [x] 明确 v1.2-draft 四投影：function/module/view/data
- [x] 明确 `data-tree` 是第四树，`risk_score` 是字段
- [x] 明确 `execution_status` 不属于 CTF/DeepSpec
- [x] 明确新协议优先 `gen_status + review_status`，旧 `status` 兼容

---

## 2026-05-19 P0-P5 基线完成 (commit `1dc6451`)

### P0：DeepShell 壳接入
- [x] DeepSpec.dpr + MainForm 注册到 DeepShell
- [x] 命令面板注册所有命令

### P1：项目扫描和 .deepspec 落地
- [x] ScanService 扫描项目目录，分类文件（code/ui/config/doc/data）
- [x] ProjectService 管理 .deepspec/ 目录结构

### P2：三棵树 + 数据模型 + LLM
- [x] Models 定义 TSpecNode / TSpecEvidence / TSpecDecision
- [x] TreeBuilder 从扫描结果构建 function/module/view 树
- [x] SpecStore YAML 读写
- [x] LLM 服务集成（ModelScope/Qwen）

### P3：HTML 决策写回 + 提示词导出
- [x] RenderService 生成树形 HTML
- [x] JS Bridge：Confirm/Reject 按钮通过 WebView2 postMessage 写回
- [x] PromptsService 导出 context-pack / system-prompt

### P4：Delphi/VCL 增强
- [x] DFM Parser 提取表单控件结构
- [x] PAS Parser 提取类/接口声明
- [x] Delphi 增强：module tree 补充 unit/class 层级，view tree 补充 DFM 控件

### P5：质量加固 + JS Bridge
- [x] 决策服务：PromotePendingDecisions
- [x] Validation 框架
- [x] Hash 内容/关系哈希
- [x] 协议文件：schemas + invariants + state-machine + controlled-vocab
