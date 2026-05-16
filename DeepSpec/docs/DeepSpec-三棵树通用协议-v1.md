# DeepSpec 三棵树通用协议 v1.1

> 日期：2026-05-14  
> 状态：v1.1 已采纳两轮审阅意见  
> 用途：定义 DeepSpec B 事实层中三棵树、关系边、来源证据、问题和决策的 YAML Schema，作为 LLM 输出校验、DeepSpec 解析和 HTML 渲染的共同契约。

---

## 1. 设计原则

```text
AI 读 YAML，人类看 HTML；
YAML 是事实源，HTML 由 YAML 生成；
Schema 是 LLM 输出和 DeepSpec 解析的共同契约；
Schema 必须能被程序校验，不能只是文档约定；
宽松模式允许首次生成缺少非必需字段；
严格模式按节点级保护已确认的人类决策不被覆盖；
枚举值使用纯英文小写蛇形命名，便于 Delphi 枚举映射；
所有事实对象带时间戳和 content_hash，支持增量更新和并发控制。
```

---

## 2. 文件组织

```text
.deepspec/
  project-spec.yaml          # 总索引
  trees/
    function-tree.yaml       # 功能树
    module-tree.yaml         # 模块树
    view-tree.yaml           # 视图树
  relations/
    requirement-relations.yaml
  evidence/
    source-evidence.yaml
  issues/
    doc-issues.yaml
  decisions/
    requirement-decisions.yaml
```

每个文件独立校验，`project-spec.yaml` 只做索引和摘要。

---

## 3. project-spec.yaml

```yaml
version: "1.0"
project:
  name: string                # 项目名称
  path: string                # 项目根目录路径
  type: string                # 项目类型，见 3.1 推荐值
  scan_time: datetime         # 最近扫描时间 ISO 8601

summary:
  total_nodes: integer
  confirmed_nodes: integer
  uncertain_nodes: integer
  open_issues: integer
  decisions_count: integer

trees:
  function_tree: "trees/function-tree.yaml"
  module_tree: "trees/module-tree.yaml"
  view_tree: "trees/view-tree.yaml"

relations: "relations/requirement-relations.yaml"
evidence: "evidence/source-evidence.yaml"
issues: "issues/doc-issues.yaml"
decisions: "decisions/requirement-decisions.yaml"

# 跨项目复用预留（v1 新增，可选字段）
imports: []                   # 引用其他项目的 .deepspec/，格式见 3.2
```

### 3.1 project.type 推荐值

```text
delphi_vcl          Delphi VCL 桌面项目
delphi_fmx          Delphi FMX 跨平台项目
web_react           React Web 项目
web_vue             Vue Web 项目
web_angular         Angular Web 项目
node_backend        Node.js 后端服务
python_backend      Python 后端 / 脚本
dotnet_desktop      .NET 桌面（WPF/WinForms）
dotnet_backend      .NET 后端服务
java_backend        Java/Spring 后端
mobile_ios          iOS 原生
mobile_android      Android 原生
mobile_flutter      Flutter 跨平台
mobile_react_native React Native
documentation       纯文档项目
mixed               混合 / 多技术栈
unknown             未知类型
```

`project.type` 不限制可用 kind 子集（见 §17 开放问题决议）。任意类型项目可使用任意 kind 值。`type` 仅作为元信息和 LLM Prompt 的上下文提示。

### 3.2 imports 字段（预留，未来扩展）

```yaml
imports:
  - alias: string             # 本项目内的引用别名
    path: string              # 被引用 .deepspec/ 的相对或绝对路径
    version_lock: string | null  # 锁定的 B 版本（content_hash 或 git ref）
    scope: enum               # all | trees | modules | views | decisions
```

第一版 DeepSpec 不实现 imports 解析，但保留字段定义。
未来用于共享库的模块树复用、企业内部规格库等场景。
预留字段不升版本号。

---

## 4. 节点通用 Schema

所有树节点共享以下基础字段：

```yaml
# 必需字段
id: string                    # 全局唯一，格式 {tree_prefix}-{slug}
tree: enum                    # function | module | view
title: string                 # 节点标题，人类可读
kind: string                  # 见 4.1，支持扩展前缀

# 时间与并发控制（v1 新增）
created_at: datetime          # 创建时间 ISO 8601
updated_at: datetime          # 最近更新时间 ISO 8601
content_hash: string          # 节点语义内容哈希，64 字符 hex（见 4.3）
relation_hash: string         # 节点关系/装饰内容哈希，64 字符 hex（见 4.3）
revision: integer             # 修订号，每次更新 +1，从 1 开始

# 可选字段（宽松模式允许缺省）
parent_id: string | null      # 父节点 id，根节点为 null
slug_override: string | null  # 可选：覆盖默认 slug 生成规则（见 §17.4）
summary: string               # 一句话描述
status: enum                  # candidate | confirmed | uncertain | rejected | superseded
confidence: enum              # low | medium | high
source_layer: enum            # 见 4.4，纯英文枚举
source_refs: []               # 来源证据 ev-id 引用列表，见 4.5
decision_refs: []             # 关联决策 dec-id 列表
issue_refs: []                # 关联问题 issue-id 列表
related_functions: []         # 关联功能节点 id
related_modules: []           # 关联模块节点 id
related_views: []             # 关联视图节点 id
children: []                  # 子节点 id 列表（冗余索引）
tags: []                      # 自由标签
acceptance_criteria: []       # 验收标准列表（功能节点推荐）
not_doing: []                 # 明确不做事项
```

### 4.1 kind 枚举（精确拼写 + 扩展机制）

kind 值规则：

```text
1. 内置值使用纯英文小写蛇形（snake_case），无空格无特殊字符
2. 扩展值必须以 "x_" 开头，如 x_microservice、x_workflow
3. 解析器对 x_ 前缀值不报错，仅记录为 unknown_kind 警告
4. 内置值精确拼写如下，Delphi 枚举映射时一一对应
```

#### 功能树 (tree: function)

```yaml
kind:
  - feature           # 产品功能
  - capability        # 能力域 / 功能组
  - user_story        # 用户故事
  - use_case          # 用例
  - rule              # 业务规则
  - constraint        # 约束条件
  - non_functional    # 非功能需求
  - integration       # 集成点
```

Delphi 枚举映射示例（功能树）：

```pascal
type
  TFunctionKind = (
    fkFeature,
    fkCapability,
    fkUserStory,
    fkUseCase,
    fkRule,
    fkConstraint,
    fkNonFunctional,
    fkIntegration,
    fkExtended  // 用于 x_ 前缀的扩展值
  );
```

#### 模块树 (tree: module)

```yaml
kind:
  - package           # 包 / 命名空间
  - unit              # 单元 / 文件
  - class             # 类
  - interface         # 接口
  - service           # 服务
  - repository        # 数据访问层
  - controller        # 控制器
  - adapter           # 适配器
  - utility           # 工具类
  - config            # 配置模块
```

Delphi 枚举映射示例（模块树）：

```pascal
type
  TModuleKind = (
    mkPackage,
    mkUnit,
    mkClass,
    mkInterface,
    mkService,
    mkRepository,
    mkController,
    mkAdapter,
    mkUtility,
    mkConfig,
    mkExtended
  );
```

#### 视图树 (tree: view)

```yaml
kind:
  - application       # 应用入口
  - window            # 窗口 / 主窗体
  - dialog            # 对话框
  - page              # 页面
  - frame             # 子框架
  - panel             # 面板 / 区域
  - control           # 控件
  - menu              # 菜单
  - toolbar           # 工具栏
  - statusbar         # 状态栏
  - tray              # 托盘
```

Delphi 枚举映射示例（视图树）：

```pascal
type
  TViewKind = (
    vkApplication,
    vkWindow,
    vkDialog,
    vkPage,
    vkFrame,
    vkPanel,
    vkControl,
    vkMenu,
    vkToolbar,
    vkStatusbar,
    vkTray,
    vkExtended
  );
```

### 4.2 默认值

宽松模式下缺省字段的默认值：

```yaml
status: candidate
confidence: medium
source_layer: ai_inferred
source_refs: []
decision_refs: []
issue_refs: []
related_functions: []
related_modules: []
related_views: []
children: []
tags: []
acceptance_criteria: []
not_doing: []
revision: 1
slug_override: null
```

`created_at` / `updated_at` / `content_hash` / `relation_hash` 由 DeepSpec 自动填充，LLM 输出可省略。

### 4.3 content_hash 与 relation_hash 计算

为避免"决策写入触发假冲突"，节点哈希分为两层：

**content_hash（语义哈希，并发控制基准）**

```text
1. 计算字段（稳定排序后 JSON）：
   id, title, kind, parent_id, summary, status, confidence,
   source_refs, source_layer, acceptance_criteria, not_doing
2. 排序规则：
   - 顶层字段按字母序排列
   - source_refs 按 ref_id 字母序排序后再序列化
   - acceptance_criteria / not_doing 保持原始顺序（有序列表）
3. 不包含：
   - decision_refs / issue_refs（关系装饰）
   - related_functions / related_modules / related_views（关系装饰）
   - tags、children
   - created_at / updated_at / content_hash / relation_hash / revision 自身
4. 算法：SHA-256 → 64 字符小写 hex
5. 用途：
   - 增量检测：hash 未变可跳过 LLM 重新生成
   - 乐观并发：合并候选 B 时校验源 hash 是否匹配当前 B
   - 漂移检测：长期跟踪节点语义内容变化
```

**relation_hash（关系装饰哈希，仅用于追踪）**

```text
1. 计算字段：
   decision_refs, issue_refs, related_functions, related_modules,
   related_views, tags
2. 算法：SHA-256 → 64 字符小写 hex
3. 用途：
   - 跟踪节点装饰信息变化（如新增决策引用）
   - 不参与 §11.2 的并发冲突检测
   - HTML 渲染层用于判断节点视觉是否需要刷新
```

**设计理由**：用户对节点做 confirm 决策时，decision_refs 增加但语义内容未变。
仅检查 content_hash 时不会产生假冲突，relation_hash 变化只触发界面刷新。

### 4.4 source_layer 枚举（纯英文）

```yaml
source_layer:
  - parsed_from_a    # A:原文解析
  - human_decision   # B:人工决策
  - ai_inferred      # B:AI推断
  - generated_summary # B:生成摘要
```

HTML 显示标签时映射为中文，YAML 中始终使用英文枚举。

### 4.5 source_refs 结构（明确为 ev-id 引用）

```yaml
source_refs:
  - ref_id: string            # 必需，引用 evidence 文件中的证据 id
    relevance: enum | null    # 可选：primary | supporting | contradicting
    note: string | null       # 可选：本次引用的特定上下文说明
```

`ref_id` 必须能在 `evidence/source-evidence.yaml` 中找到对应条目。校验器对孤立的 ref_id 报 `dangling_evidence_ref` 错误。

---

## 5. 树文件结构

```yaml
version: "1.0"
tree: function | module | view
generated_at: datetime
generator: string             # 如 "deepspec-llm-v1" 或 "manual"

nodes:
  - id: "func-user-auth"
    tree: function
    title: "用户认证"
    kind: feature
    parent_id: null
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    content_hash: "a3f5..."
    relation_hash: "b8c2..."
    revision: 1
    summary: "支持用户登录、注册和密码重置"
    status: confirmed
    confidence: high
    source_layer: human_decision
    source_refs:
      - ref_id: "ev-readme-auth"
        relevance: primary
    decision_refs:
      - "dec-001"
    issue_refs: []
    related_modules:
      - "mod-auth-service"
    related_views:
      - "view-login-dialog"
    children:
      - "func-login"
      - "func-register"
    acceptance_criteria:
      - "用户能通过邮箱和密码登录"
      - "登录失败显示明确错误信息"
    not_doing:
      - "不支持第三方 OAuth（第二阶段）"
    tags:
      - "core"
      - "security"
```

---

## 6. 关系边 Schema

```yaml
version: "1.0"
generated_at: datetime

relations:
  - id: string                # 全局唯一，最大长度 120 字符
    from: string              # 源节点 id
    to: string                # 目标节点 id
    type: enum                # 见 6.1 枚举
    confidence: enum          # low | medium | high
    created_at: datetime
    updated_at: datetime
    source_refs: []           # ev-id 引用列表
    decision_refs: []         # 决策 id 列表
    note: string | null
```

### 6.1 关系类型枚举

```yaml
type:
  - contains          # 树内父子包含关系
  - depends_on        # 依赖关系
  - implements        # 功能由模块实现
  - presented_by      # 功能由视图承载
  - owned_by          # 归属关系
  - constrained_by    # 受约束（权限、规则、状态）
  - conflicts_with    # 冲突关系
  - derived_from      # 派生 / 推断来源
  - triggers          # 触发关系
  - extends           # 扩展关系
```

### 6.2 contains 与 parent_id/children 一致性规则

```text
contains 关系是 parent_id/children 字段的等价表达，二者必须保持一致：

1. 当节点 A 的 parent_id = B 时，relations 中应存在
   { from: B, to: A, type: contains } 或可由 DeepSpec 自动推导
2. children 字段是冗余索引，由 parent_id 反推生成
3. 同一对节点不允许同时存在 parent_id 关系和反向 contains 关系
4. 校验器优先以 parent_id 为准；relations 中的 contains 与 parent_id 不一致时报
   inconsistent_containment 错误

LLM 输出建议：
- 仅使用 parent_id 表达父子关系
- relations 中不重复声明 contains
- 跨树父子关系（如功能 contains 视图）必须使用 relations，不能用 parent_id
```

### 6.3 关系 id 命名

```text
推荐格式： rel-{seq}  或  rel-{from_slug}-{to_slug}-{type_short}
最大长度： 120 字符
type_short 缩写映射：
  contains       -> ct
  depends_on     -> dep
  implements     -> impl
  presented_by   -> pres
  owned_by       -> own
  constrained_by -> con
  conflicts_with -> conf
  derived_from   -> deriv
  triggers       -> trig
  extends        -> ext
```

---

## 7. 来源证据 Schema

```yaml
version: "1.0"

evidence:
  - id: string                # 全局唯一，格式 ev-{slug}
    source_layer: enum        # parsed_from_a | human_decision | ai_inferred | generated_summary
    path: string              # 文件相对路径
    lines: string | null      # 行范围，如 "10-25" 或 null
    excerpt: string           # 关键片段摘录，默认上限 1000 字符，可配置
    excerpt_truncated: boolean # 是否被截断
    note: string | null
    confidence: enum          # low | medium | high
    created_at: datetime
    updated_at: datetime
    content_hash: string      # 摘录内容哈希
    source_file_hash: string | null  # 源文件 SHA-256，用于检测源文件变更（v1 新增）
    is_stale: boolean         # 源文件 hash 不匹配时为 true，默认 false
    referenced_by: []         # 引用此证据的对象 id 列表
```

### 7.1 excerpt 长度规则

```text
默认上限：1000 字符（提升自 v0 草案的 500）
可配置项：deepspec.evidence.excerpt_max_chars（保存在 ConfigDB）
超出时：截断并设置 excerpt_truncated: true
保留首尾：截断时保留前 800 字符 + "..." + 后 200 字符
LLM Prompt 中：使用 excerpt 字段而非读取原文，控制 token
```

### 7.2 源文件变更检测（v1 新增）

```text
1. 创建证据时，DeepSpec 计算源文件全文的 SHA-256，存入 source_file_hash
2. 后续扫描时重新计算源文件 hash 并比对：
   - 匹配 → is_stale=false，证据有效
   - 不匹配 → is_stale=true，自动生成 stale_doc 类型问题
3. 二进制文件或大文件（>10MB）的 source_file_hash 可为 null
4. is_stale=true 的证据仍保留在 B 中，但 HTML 渲染加显眼标记
5. 重新扫描后用户可选择：
   - 接受新版本：DeepSpec 重新生成 excerpt，更新 hash
   - 保留历史：维持当前 excerpt，标记为历史快照
```

---

## 8. 问题 Schema

```yaml
version: "1.0"

issues:
  - id: string                # 全局唯一，格式 issue-{seq}
    severity: enum            # critical | high | medium | low | info
    type: enum                # 见 8.1 枚举
    title: string
    description: string
    affected_nodes: []        # 节点 id 列表
    source_refs: []           # ev-id 引用列表
    suggested_action: string | null
    suggested_prompt: string | null
    status: enum              # open | resolved | wontfix | deferred
    resolved_by: string | null # 解决该问题的决策 id
    created_at: datetime      # v1 新增
    updated_at: datetime      # v1 新增
    resolved_at: datetime | null
```

### 8.1 问题类型枚举

```yaml
type:
  - missing_requirement
  - conflict
  - ambiguity
  - stale_doc
  - no_source
  - low_confidence
  - parse_warning
  - parse_error
  - orphan_node
  - coverage_gap
```

---

## 9. 决策 Schema

决策类型与 `DeepSpec-人类决策写回与AI影响机制-v1.md` §4 的 12 种类型严格对齐。

**字段对齐说明**：

- `source_refs` 与节点的 source_refs 一致，均使用 ev-id 引用格式（见 §4.5）。
  写回文档 §5 中使用的内联 `{path: ..., note: ...}` 格式为早期示例，
  后续将同步修正为 ev-id 引用，**以本协议为准**。
- `resolved_issues` 包含所有被该决策解决的问题（含冲突裁决和普通问题）。
  写回文档 §5 中的 `conflicts_resolved` 是 resolved_issues 的子集，
  统一字段名后 conflicts_resolved 不再单独存在。

```yaml
version: "1.0"

decisions:
  - id: string                # 格式 dec-{seq} 或 RD-{date}-{seq}
    type: enum                # 见 9.1 完整枚举（12 种）
    title: string
    decision: string          # 人类确认后的准事实文本
    rationale: string         # 决策理由
    target_nodes: []          # 节点 id 列表
    affected_relations: []    # 关系 id 列表
    affected_requirements: [] # 需求 id 列表（兼容写回文档命名）
    affected_views: []        # 视图节点 id 列表
    affected_modules: []      # 模块节点 id 列表
    resolved_issues: []       # issue id 列表
    source_refs: []           # ev-id 引用列表
    ai_instruction: string | null    # 给后续 AI 的写作约束
    priority: enum | null     # P0 | P1 | P2 | later
    release: string | null    # 关联版本，如 "v0.1"
    created_at: datetime
    updated_at: datetime
    decided_by: enum          # human | system
    confidence: enum          # low | medium | high
    status: enum              # proposed | accepted | rejected | superseded | rolled_back | withdrawn
    superseded_by: string | null   # 被哪个决策替代
    supersedes: []            # v1 新增：本决策替代了哪些旧决策（id 列表）
```

### 9.1 决策类型枚举（与写回文档对齐）

```yaml
type:
  - confirm             # 确认 AI 推断正确
  - reject              # 否定 AI 推断
  - clarify             # 澄清歧义描述
  - gap_fill            # 补充缺失信息（原 supplement 改为 gap_fill 与写回文档一致）
  - resolve_conflict    # 裁决冲突
  - scope               # 范围决策（做/不做/本期/后续）
  - priority            # 优先级 P0/P1/P2/later
  - terminology         # 术语归一
  - view_mapping        # 视图归属
  - module_mapping      # 模块归属
  - permission          # 权限决策
  - rule                # 状态/规则决策
```

### 9.2 status 枚举完整说明

```text
proposed       候选决策，等待人类确认
accepted       已确认，是当前事实
rejected       人类否定该候选
superseded     被新决策替代（superseded_by 必须填写）
rolled_back    撤销已生效的决策
withdrawn      未生效前主动撤回
```

---

## 10. ID 命名规范

```text
节点 id:     {tree_prefix}-{slug}
  func-     功能树节点
  mod-      模块树节点
  view-     视图树节点

关系 id:     rel-{seq} 或 rel-{from_slug}-{to_slug}-{type_short}（最大 120 字符）
证据 id:     ev-{slug}（最大 80 字符）
问题 id:     issue-{seq}
决策 id:     dec-{seq} 或 RD-{YYYYMMDD}-{seq}
```

slug 规则：

- 小写英文 + 连字符
- 不超过 40 字符
- 可读、可 grep
- 中文标题的 slug 优先使用英文翻译；翻译困难时使用拼音（首选无声调，如 `pinyin`，不用 `pīnyīn`）
- 见 §17 开放问题 4 的决议

---

## 11. 校验规则

### 11.1 宽松模式（首次生成）

```text
必须通过：
- 每个节点有 id、tree、title、kind
- id 格式正确且全局唯一
- tree 值在 function | module | view 中
- kind 值在对应树的枚举中，或以 x_ 开头（扩展值）
- 关系边的 from 和 to 引用存在的节点 id
- 关系边的 type 在枚举中
- source_refs 中的 ref_id 在 evidence 文件中存在（dangling_evidence_ref 检测）

允许缺省：
- summary、status、confidence、source_layer
- source_refs、decision_refs、issue_refs
- related_*、children、tags
- acceptance_criteria、not_doing
- created_at、updated_at、content_hash、relation_hash（由 DeepSpec 补齐）
- slug_override

自动补默认值：
- status → candidate
- confidence → medium
- source_layer → ai_inferred
- 列表字段 → []
- revision → 1
- slug_override → null
```

### 11.2 严格模式（节点级保护，v1 修正）

严格模式不再全局阻塞更新，改为按节点级判定。每个节点独立计算保护级别：

```text
节点保护级别（按优先级判定）：

LOCKED（锁定）：
  - status = confirmed 且 decision_refs 非空
  - 拒绝任何字段变更，除非候选 B 携带 decision_ref 显式覆盖
  - LLM 候选中此节点字段必须与当前 B 完全一致，否则拒绝
  - **人类 override 例外（v1 新增）**：当变更来源于 decided_by=human
    的新决策（特别是 type=reject 或 type=clarify），允许覆盖 LOCKED 节点。
    人类对自己历史决策的推翻总是被允许的。
    实施方式：增量 patch 的 operations 中携带 driver_decision_id，
    DeepSpec 校验该决策的 decided_by=human 后放行。
  - **安全边界**：driver_decision_id 引用的决策必须由 DeepSpec 内部路径
    创建（HTML JS Bridge 写入或 DeepSpec UI 操作）。LLM 候选 B 中即使
    包含 decided_by=human 的决策记录，也不得作为 driver_decision_id 使用。
    校验器对 LLM 来源的 decided_by=human 直接拒绝整个候选 B。

GUARDED（受保护）：
  - status = confirmed 但 decision_refs 为空
  - 允许补充字段（summary/acceptance_criteria/related_*）
  - 拒绝降级 status 或修改 title/kind/parent_id

OPEN（开放）：
  - status ∈ {candidate, uncertain}
  - 允许任意字段更新
  - 检测 content_hash 不匹配时记录漂移警告但不拒绝

REJECTED 节点：
  - status = rejected
  - 拒绝重新激活，除非有 type=confirm 决策

并发控制（基于 content_hash）：
- 候选 B 必须携带 base_content_hash（基于哪个版本生成）
- DeepSpec 比对当前节点 content_hash 与 base_content_hash
- 不匹配时进入冲突合并流程，不静默覆盖

整体模式判定：
- 仅当本次合并对所有节点都无违规时，整次合并通过
- 单节点违规仅拒绝该节点变更，其余节点照常合并
- 校验报告列出每个节点的处理结果
```

### 11.3 校验报告格式

```yaml
validation:
  mode: lenient | strict
  timestamp: datetime
  passed: boolean
  errors:
    - rule: string
      severity: error | warning
      path: string              # 文件级/Schema 级错误用 YAML 路径，节点错误用 node_id:func-xxx
      message: string
      fix_hint: string
  node_results:                # v1 新增：节点级结果（推荐使用）
    - node_id: string
      protection: locked | guarded | open
      action: accepted | rejected | merged | skipped
      reason: string
  stats:
    total_nodes: integer
    accepted: integer
    rejected: integer
    merged: integer
    skipped: integer
    auto_filled: integer
```

**path 字段使用规则**：

```text
- 节点级错误：优先在 node_results 中报告，errors[].path 使用 "node_id:func-xxx" 格式
- 关系/证据/问题/决策错误：path 使用 "rel-id:..." / "ev-id:..." / "issue-id:..." / "dec-id:..."
- 文件级错误：path 使用相对路径，如 "trees/function-tree.yaml"
- Schema 级错误：path 使用 YAML JSON Pointer，如 "/nodes/3/kind"
```

---

## 12. LLM 输出约束

### 12.1 全量模式

LLM 生成完整 B 时必须遵守：

```text
1. 输出完整 YAML 文件，不输出片段
2. 每个节点必须有 id、tree、title、kind
3. id 必须使用规定前缀和 slug 格式
4. kind 必须在对应树的枚举范围内或以 x_ 开头
5. source_refs 应尽量填写
6. 不确定的内容标注 confidence: low 和 status: candidate
7. 不得把推断写成 status: confirmed
8. 不得删除或覆盖已有 decision_refs 非空的节点
9. 关系边的 from/to 必须引用本次输出中存在的节点 id
10. 输出必须是合法 YAML，不含 Markdown 代码块标记
11. 不得在候选 B 中设置 decided_by: human。LLM 输出的决策 decided_by
    必须为 system 或省略。decided_by: human 只能由 DeepSpec 内部路径
    （HTML JS Bridge 写入）设置。违反此条的候选 B 整体拒绝。
```

### 12.2 增量模式（v1 新增，减少 token 消耗）

针对单节点或局部更新，使用增量 patch 格式：

```yaml
mode: incremental
base_revision: integer | null # 可选：树文件级版本号（每次成功合并 +1，仅作元信息）
base_content_hashes:          # 必需：涉及节点的当前 content_hash，用于并发控制
  func-user-auth: "a3f5..."
driver_decision_id: string | null  # 可选：驱动本次变更的人类决策 id
                                    # 用于 LOCKED 节点 override 校验（见 §11.2）

operations:
  - op: add
    target: node | relation | issue | decision
    id: string
    payload:                  # add 必需：完整对象
      ...

  - op: update
    target: node | relation | issue | decision
    id: string
    base_hash: string         # update 必需：基于哪个 content_hash
    payload:                  # update 必需：仅含变更字段
      field_name: new_value   # 显式 null 表示清除该字段
                              # 字段未列出表示保持原值

  - op: delete
    target: node | relation | issue | decision
    id: string
    base_hash: string         # delete 必需：基于哪个 content_hash
    # delete 不需要 payload
```

**字段语义说明**：

```text
base_revision：
  - 可选字段，仅作信息记录（如"基于树文件第 12 版生成"）
  - 不参与并发冲突检测
  - 并发控制完全由 base_content_hashes 完成
  - 树文件级版本号在每次 DeepSpec 成功合并后 +1

base_content_hashes：
  - 必需字段
  - 列出本次 operations 中涉及的所有节点 id 及其当前 content_hash
  - DeepSpec 比对当前 B 中的 content_hash，不匹配则进入冲突合并流程

operations[].payload（update 操作）：
  - 仅包含变更字段
  - 字段未列出 → 保持原值
  - 字段值为 null → 清除该字段（恢复默认值）
  - 列表字段 → 整体替换（不做合并），如需追加请提交完整新列表

operations[].payload（delete 操作）：
  - 不需要提供 payload
  - 仅用 id 和 base_hash 即可
  - DeepSpec 删除节点时同步清理 children 反向引用和孤立的 evidence

driver_decision_id：
  - 可选字段
  - 当本次 patch 由人类决策驱动时填写
  - DeepSpec 校验该决策的 decided_by=human 后，授予 LOCKED 节点 override 权限
```

适用场景：

```text
- 节点详情页编辑后写回
- LLM 单点完善某个低置信节点
- 用户决策仅影响 3-5 个节点时
- HTML JS Bridge 写回事件
```

不适用场景：

```text
- 首次生成 B
- 重新扫描后大规模重建
- 跨 50% 以上节点的结构性变更（应使用全量模式）
```

### 12.3 错误示例对照

❌ 错误：缺少必需字段

```yaml
nodes:
  - title: "登录"     # 缺少 id、tree、kind
    summary: "用户登录"
```

✅ 正确：

```yaml
nodes:
  - id: func-login
    tree: function
    kind: feature
    title: "登录"
    summary: "用户登录"
```

❌ 错误：把推断写成 confirmed

```yaml
- id: func-some-feature
  status: confirmed       # 但 source_layer 是 ai_inferred 且无 decision_refs
  source_layer: ai_inferred
  decision_refs: []
```

✅ 正确：

```yaml
- id: func-some-feature
  status: candidate       # AI 推断默认 candidate
  confidence: low
  source_layer: ai_inferred
```

❌ 错误：dangling source_ref

```yaml
source_refs:
  - ref_id: ev-not-exist  # evidence 文件中不存在
```

✅ 正确：先在 evidence 文件中创建条目，再引用

❌ 错误：使用中文枚举值

```yaml
source_layer: "B:AI推断"  # 应使用纯英文 ai_inferred
```

✅ 正确：

```yaml
source_layer: ai_inferred
```

❌ 错误：包含 Markdown 代码块标记

LLM 输出包裹了三层反引号代码块（伪示例，实际内容应为纯 YAML）：

    ```yaml
    nodes: ...
    ```

✅ 正确：直接输出纯 YAML 文本，不加任何 Markdown 围栏标记

---

## 13. 版本演进策略

```text
version 字段用于前向兼容：
- "1.0" 是当前版本
- 新增可选字段不升版本号
- 删除字段或改变必需性升 minor
- 改变 id 格式或根结构升 major

DeepSpec 解析器必须：
- 忽略未知字段（前向兼容）
- 对缺失的可选字段补默认值
- 对 version 不匹配给出警告但不拒绝解析
- 对 x_ 前缀的扩展 kind 值不报错
```

### 13.1 字段废弃策略（v1 新增）

```text
1. 标记阶段：
   - 字段在 Schema 中标注 deprecated: true 和 deprecated_since: "1.x"
   - 解析器读取时输出 warning，但不拒绝
   - 默认值行为保持不变
   - 至少保留 2 个 minor 版本（如 1.2 标记，1.4 才能移除）

2. 迁移阶段：
   - 提供替代字段（如有）
   - 文档明确迁移路径
   - DeepSpec 自动迁移工具可批量转换历史 B

3. 移除阶段：
   - 在 major 版本中正式移除
   - 解析旧版 YAML 时仍能识别但忽略该字段
   - DeepSpec 提供 yaml-migrate 工具升级历史文件
```

---

## 14. 扫描报告 Schema

```yaml
version: "1.0"
scan_time: datetime
project_path: string
project_type: string

file_classification:
  documents: []
  code: []
  ui: []
  config: []
  ai_rules: []
  ignored: []

stats:
  total_files: integer
  documents: integer
  code: integer
  ui: integer
  config: integer
  ai_rules: integer
  ignored: integer

warnings: []
```

### 14.1 文件分类规则（同文件唯一分类）

每个文件只归入唯一一个分类，按以下优先级判定，命中即停：

```text
优先级 1: ai_rules
  文件名匹配（不区分路径）：
    CLAUDE.md
    AGENTS.md
    .cursorrules
    cursor-rules.md
    .github/copilot-instructions.md
    .windsurfrules
  路径匹配：
    .kiro/steering/*.md
    .kiro/specs/*/requirements.md  （仅 requirements/design/tasks 三种）
    .cursor/rules/*

优先级 2: documents
  扩展名: .md .txt .rst .doc .docx .pdf .adoc
  排除: 已归入 ai_rules 的文件

优先级 3: ui
  Delphi: .dfm .fmx
  Web: .html .htm .vue .jsx .tsx .svelte .astro
  XAML: .xaml .axaml
  Qt: .ui .qml
  注意: .dfm 严格归类为 ui，不归 code，即使它与 .pas 同名

优先级 4: code
  Delphi: .pas .dpr .inc
  通用: .py .ts .js .java .cs .go .rs .rb .php .swift .kt .c .cpp .h .hpp .m .mm

优先级 5: config
  数据格式: .yaml .yml .json .toml .ini .xml .env .properties
  Delphi: .dproj .dpk .groupproj
  其他: .sln .csproj .vcxproj .gradle .cmake .lock package.json tsconfig.json

优先级 0（最高，先于所有匹配）: ignored
  目录名匹配: node_modules, .git, .svn, .hg, __pycache__, .pytest_cache,
            build, bin, dist, out, target, Debug, Release, __history,
            .next, .nuxt, .vscode, .idea, .DS_Store
  文件名匹配: *.dcu *.exe *.dll *.so *.dylib *.o *.obj *.lib *.a
            *.pyc *.class

未匹配任何规则的文件：
  分类为 unknown，进入扫描警告，但不阻塞流程
```

`.dfm` 同名规则说明：Delphi 项目中 `MainForm.pas` 和 `MainForm.dfm` 是同一窗体的两个文件。`.pas` 归 code，`.dfm` 归 ui，DeepSpec 通过 `related_files` 元数据维护它们的关联，不重复分类。

---

## 15. 协议使用场景

```text
场景 1：LLM 首次生成 B
  输入：Context Pack（A 的文件内容 + Prompt 模板）
  输出：完整 trees/*.yaml + relations/*.yaml + evidence/*.yaml + issues/*.yaml
  模式：全量
  校验：宽松模式

场景 2：LLM 增量更新 B
  输入：当前 B 的 base_revision + 增量 operations
  输出：mode=incremental 的 patch
  模式：增量
  校验：严格模式（节点级保护）

场景 3：人类决策写回
  输入：HTML 点击事件 → 候选 Decision Record
  输出：decisions/*.yaml 追加条目 + 受影响节点的增量更新
  模式：增量
  校验：严格模式

场景 4：DeepSpec 渲染
  输入：B 中所有 YAML 文件
  输出：HTML 页面 + 原生树控件数据
  要求：每个 HTML 元素可通过 node_id 追溯到 B 中的事实对象
```

---

## 16. 示例：最小可用 B（v1 完整版本）

一个最小但完整的 `.deepspec` 示例，包含 v1 全部新增字段。

### 16.1 project-spec.yaml

```yaml
version: "1.0"
project:
  name: "MyApp"
  path: "D:/Projects/MyApp"
  type: "delphi_vcl"
  scan_time: "2026-05-14T10:30:00+08:00"

summary:
  total_nodes: 2
  confirmed_nodes: 1
  uncertain_nodes: 1
  open_issues: 1
  decisions_count: 1

trees:
  function_tree: "trees/function-tree.yaml"
  module_tree: "trees/module-tree.yaml"
  view_tree: "trees/view-tree.yaml"

relations: "relations/requirement-relations.yaml"
evidence: "evidence/source-evidence.yaml"
issues: "issues/doc-issues.yaml"
decisions: "decisions/requirement-decisions.yaml"

imports: []
```

### 16.2 trees/function-tree.yaml

```yaml
version: "1.0"
tree: function
generated_at: "2026-05-14T10:30:00+08:00"
generator: "deepspec-llm-v1"

nodes:
  - id: "func-root"
    tree: function
    title: "MyApp"
    kind: capability
    parent_id: null
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    content_hash: "a3f5e8c2d1b4a7f9e0c3d6b8a2f1e4c7d9b3a5e8f2c1d4b7a9e6c3f8d2b5a1e4"
    relation_hash: "b8c2d4f6a1e3c5d7b9a0e2c4f6d8b1a3e5c7d9f0b2a4e6c8d1f3b5a7e9c0d2f4"
    revision: 1
    slug_override: null
    summary: "MyApp 产品功能根节点"
    status: confirmed
    confidence: high
    source_layer: human_decision
    source_refs:
      - ref_id: "ev-readme-intro"
        relevance: primary
    decision_refs:
      - "dec-001"
    issue_refs: []
    related_modules: []
    related_views: []
    children:
      - "func-file-open"
    tags:
      - "core"
    acceptance_criteria: []
    not_doing: []

  - id: "func-file-open"
    tree: function
    title: "打开文件"
    kind: feature
    parent_id: "func-root"
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    content_hash: "c1d4b7a9e6c3f8d2b5a1e4f7c0d3b6a9e2c5f8d1b4a7e0c3d6b9a2e5f8c1d4b7"
    relation_hash: "d2f4a6e8c1d3f5a7e9c2d4f6a8e0c2d4f6a8e1c3d5f7a9e2c4d6f8a1e3c5d7f9"
    revision: 1
    slug_override: null
    summary: "用户可以打开本地文件进行编辑"
    status: candidate
    confidence: medium
    source_layer: ai_inferred
    source_refs:
      - ref_id: "ev-readme-features"
        relevance: supporting
    decision_refs: []
    issue_refs:
      - "issue-001"
    related_modules: []
    related_views: []
    children: []
    tags: []
    acceptance_criteria:
      - "支持拖放打开"
      - "支持最近文件列表"
    not_doing: []
```

### 16.3 evidence/source-evidence.yaml

```yaml
version: "1.0"

evidence:
  - id: "ev-readme-intro"
    source_layer: parsed_from_a
    path: "README.md"
    lines: "1-15"
    excerpt: "MyApp 是一个跨平台的文件编辑器，支持..."
    excerpt_truncated: false
    note: null
    confidence: high
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    content_hash: "e3a1b5d8c4f7e2a9d6c1b4f8e0a3d7c2b5f9e1a4d6c8b3f0e2a5d7c1f4e8b3a6"
    source_file_hash: "f8a2c5e1d4b7a0e3c6d9f2b5a8e1d4c7f0b3a6e9d2c5f8b1a4e7d0c3f6b9a2e5"
    is_stale: false
    referenced_by:
      - "func-root"

  - id: "ev-readme-features"
    source_layer: parsed_from_a
    path: "README.md"
    lines: "20-35"
    excerpt: "## 主要功能\n- 文件打开\n- ..."
    excerpt_truncated: false
    note: null
    confidence: medium
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    content_hash: "a7d2c5e8b1f4a9d6c3e0f7b2a5d8c1f4e7b0a3d6c9e2f5a8d1c4b7e0a3d6f9c2"
    source_file_hash: "f8a2c5e1d4b7a0e3c6d9f2b5a8e1d4c7f0b3a6e9d2c5f8b1a4e7d0c3f6b9a2e5"
    is_stale: false
    referenced_by:
      - "func-file-open"
```

### 16.4 issues/doc-issues.yaml

```yaml
version: "1.0"

issues:
  - id: "issue-001"
    severity: medium
    type: low_confidence
    title: "打开文件功能缺少明确验收标准"
    description: "README 提到了文件打开功能，但未说明支持哪些格式和异常处理"
    affected_nodes:
      - "func-file-open"
    source_refs:
      - ref_id: "ev-readme-features"
    suggested_action: "向用户确认支持的文件格式列表"
    suggested_prompt: "请列出 MyApp 应支持的文件格式..."
    status: open
    resolved_by: null
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    resolved_at: null
```

### 16.5 decisions/requirement-decisions.yaml

```yaml
version: "1.0"

decisions:
  - id: "dec-001"
    type: confirm
    title: "确认 MyApp 是文件编辑器"
    decision: "MyApp 的产品定位是跨平台文件编辑器"
    rationale: "README 第 1 段明确说明，且符合用户讨论"
    target_nodes:
      - "func-root"
    affected_relations: []
    affected_requirements: []
    affected_views: []
    affected_modules: []
    resolved_issues: []
    source_refs:
      - ref_id: "ev-readme-intro"
        relevance: primary
    ai_instruction: "后续所有规格描述围绕文件编辑器定位展开，不要扩展为 IDE 或浏览器"
    priority: P0
    release: "v0.1"
    created_at: "2026-05-14T10:30:00+08:00"
    updated_at: "2026-05-14T10:30:00+08:00"
    decided_by: human
    confidence: high
    status: accepted
    superseded_by: null
    supersedes: []
```

### 16.6 relations/requirement-relations.yaml

```yaml
version: "1.0"
generated_at: "2026-05-14T10:30:00+08:00"

relations: []
# parent_id 已表达 func-root contains func-file-open，
# 此处不重复声明 contains（见 §6.2）
```

### 16.7 trees/module-tree.yaml 和 trees/view-tree.yaml

最小示例可保留为空树：

```yaml
version: "1.0"
tree: module
generated_at: "2026-05-14T10:30:00+08:00"
generator: "deepspec-llm-v1"
nodes: []
```

---

## 17. 开放问题决议

第一轮审阅提出的 4 个开放问题，本协议给出当前决议。如有异议在第二轮审阅时提出。

### 17.1 LLM 输出格式：YAML

**决议：YAML，不支持 JSON。**

理由：

- 人类审阅 `.deepspec` 目录时 YAML 注释和缩进更友好
- Git diff 在 YAML 上更清晰
- DeepSpec 内部解析器只需维护一种格式
- 主流 LLM 对 YAML 输出能力已足够稳定
- 如需机器交换，DeepSpec 可单独提供 YAML ↔ JSON 转换工具

### 17.2 .deepspec/ 的 Git 跟踪策略

**决议：默认提交 B 的事实文件，不提交生成产物和模板类提示词。**

`.gitignore` 推荐内容：

```gitignore
# DeepSpec generated artifacts (regenerable)
.deepspec/html/
.deepspec/llm/candidate-output.yaml
.deepspec/llm/last-run.yaml
.deepspec/logs/

# DeepSpec auto-generated prompts (regenerable templates)
.deepspec/prompts/context-pack.md
.deepspec/prompts/doc-optimization-prompt.md
.deepspec/prompts/node-prompt.md
.deepspec/prompts/agents-draft.md
.deepspec/prompts/claude-draft.md
.deepspec/prompts/cursor-rules-draft.md

# DeepSpec facts (commit these)
# .deepspec/project-spec.yaml
# .deepspec/trees/
# .deepspec/relations/
# .deepspec/evidence/
# .deepspec/issues/
# .deepspec/decisions/
# .deepspec/prompts/decision-context.md       # 决策派生，提交
# .deepspec/prompts/decision-rewrite-prompt.md # 决策派生，提交
```

**prompts/ 目录的精细策略**：

```text
- 自动生成的模板类提示词（context-pack.md / doc-optimization-prompt.md / node-prompt.md
  / *-draft.md）→ 排除（每次扫描可重新生成）
- 由人类决策派生的提示词（decision-context.md / decision-rewrite-prompt.md）→ 提交
- 用户手工创建的自定义提示词 → 放在 .deepspec/prompts/custom/ 子目录，提交
```

DeepSpec 首次生成 `.deepspec` 时自动写入这份 `.gitignore`，用户可修改。

### 17.3 project.type 是否影响可用 kind 子集

**决议：不影响。**

- `project.type` 仅作为元信息和 LLM Prompt 上下文
- 任意类型项目可使用任意 kind 值
- LLM Prompt 中可附加"对 web_react 项目优先使用 page/control/service 等"提示，但不强制
- 这样跨技术栈混合项目（mixed 类型）不会被限制

### 17.4 slug 中文拼音 vs 英文翻译优先级

**决议：英文翻译优先，无声调拼音兜底，允许通过 slug_override 字段手工指定。**

```text
1. 优先：能直接英文翻译的术语用英文（如 用户登录 → user-login）
2. 兜底：领域专有名词或翻译困难时用无声调拼音（如 章鱼姐 → zhang-yu-jie）
3. 例外：title 中保留中文，slug 仅用于 id 拼接
4. 用户可在节点的 slug_override 字段中指定自定义 slug，
   DeepSpec 优先使用该值（已在 §4 节点 Schema 中定义为可选字段）
5. 同一项目内 slug 必须保持风格一致，DeepSpec 检测到混用时给出 P2 警告
```

slug_override 使用示例：

```yaml
- id: "func-bsp-driver"        # id 已固定，不再随 title 变化
  title: "BSP 板级支持包驱动"
  slug_override: "bsp-driver"  # 显式指定 slug，覆盖默认生成规则
```

设计理由：

- slug_override 存入 YAML，可追溯、可审计
- 不依赖 UI 层维护映射，重新扫描时不丢失
- 节点 id 一旦确定即稳定，不因 title 变化而改变

---

*文档版本：v1.1 · 已采纳两轮审阅意见 · 2026-05-14*

## 18. 修订记录

```text
v1.1 (2026-05-14) - 第二轮审阅修订
  - §4.1 补充模块树和视图树的 Delphi 枚举映射示例
  - §4 节点 Schema 拆分 content_hash 和 relation_hash，避免决策写入触发假冲突
  - §4 节点新增 slug_override 可选字段
  - §7 evidence 增加 source_file_hash 和 is_stale 字段（S1）
  - §9 决策 source_refs 与 resolved_issues 字段对齐说明
  - §11.2 LOCKED 节点新增人类决策 override 例外
  - §11.3 校验报告 path 字段格式细化
  - §12.2 base_revision 改为可选元信息，明确 delete payload 语义
  - §12.2 增加 driver_decision_id 字段支持 LOCKED override
  - §12.3 修复嵌套代码块渲染问题
  - §13.1 新增字段废弃策略（S3）
  - §3.2 预留 imports 跨项目复用字段（S2）
  - §16 补充完整最小可用 B 示例（v1 全部新增字段）
  - §17.2 prompts/ Git 策略精细化
  - §17.4 slug_override 字段引用 §4 定义

v1.0 (2026-05-14) - 第一轮审阅修订
  - kind 枚举增加 x_ 前缀扩展机制
  - 节点增加 created_at/updated_at/content_hash/revision
  - source_layer 改为纯英文枚举
  - 决策类型对齐写回文档 12 种
  - 严格模式改为节点级保护
  - 增加增量 patch 模式
  - 文件分类规则细化（.dfm 归 ui）

v0 (2026-05-14) - 初始草案
```
