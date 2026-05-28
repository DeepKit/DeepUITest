# CTF 方法论：建构·追溯·可谬法

> **Constructive Traceable Fallibilist Method**
> 版本：1.0
> 日期：2026-05-19
> 来源：基于 OpenAI Symphony 的五轮跨学科专家讨论
> 工程同步说明：DeepSpec 对外工程入口以根目录 README.md、SPEC.md 和 docs/CTF.md 为准；本文保留为方法论源文档。

---

## 0. 一句话定义

> **需求是人机协作的建构产物，必须可追溯，且始终可谬。方法通过四层结构（认知-正确性-生态-工程）将这一信念嵌入工具和流程，使方法论成为工具的一部分而非人的记忆负担。**

---

## 1. 哲学基础

### 1.1 本体论立场

CTF 方法建立在一个核心信念之上：

> **软件需求不是被发现的对象，而是在人类与 AI 的持续对话中被建构的实体。需求规格不是对话的终点，而是对话的中间产物——一个可以被追溯、被质疑、被修正的结构化冻结帧。**

### 1.2 三个哲学承诺

| 承诺 | 含义 | 对设计的意味 |
|------|------|-------------|
| **建构主义** | 需求不是"本来就存在等着被找到"的，而是通过人机交互被建构出来的 | 每个节点必须记录建构过程（谁、用什么输入、用什么方法） |
| **可追溯性** | 每个建构的产物必须能追溯到它的建构过程 | 不存在"无来源"的节点 |
| **可谬性** | 任何建构的产物都可能是错的，方法论必须支持修正 | 不存在"一旦确认就永远正确"的节点 |

### 1.3 方法论的第零公理

> **工具不替代人类判断。它让人类判断更有分量。**

---

## 2. 七条公理

公理是不证自明的起点。所有具体实践都从公理推导而来。

| 编号 | 名称 | 陈述 | 来源专家 |
|------|------|------|----------|
| A1 | 建构性 | 每个规格节点都是一次建构行为的结果，不是对已有事实的转录 | Amara + Hans |
| A2 | 可追溯性 | 每个建构行为必须记录其输入（证据源）、过程（LLM 推理链）、和产出（节点） | Sarah + Hans |
| A3 | 可谬性 | 每个节点都可能被后续信息推翻。不存在"一旦确认就永远正确"的节点 | Amara + Elena |
| A4 | 正交性 | 描述同一实体的不同维度（生成状态、审阅状态、证据状态）必须用独立的字段表达，不可混合 | Hans + Symphony 双状态映射 |
| A5 | 最小权限上下文 | 每次 AI 调用只获得恰好够用的信息，不多不少 | Sarah + Symphony linear_graphql |
| A6 | 问题优先 | 向人类呈现信息时，先呈现不确定性和矛盾，再呈现确定性结论 | Amara |
| A7 | 部分成功 | 系统在任何时刻都应处于"部分可用"状态，而非"全有或全无" | Marcus + Symphony 降级策略 |

### 公理间的依赖关系

```
A1 建构性 ──→ 需要追溯（A2）
  │              │
  └─→ 可能出错（A3）──→ 需要正交描述（A4）
                          │
       ┌──────────────────┘
       ↓
  AI 调用要克制（A5）
       │
       ↓
  人类审阅要触发深层思考（A6）
       │
       ↓
  系统永远部分可用（A7）
```

---

## 3. 四层模型

方法通过四个正交的层实施。每一层回答一个不同的问题，有不同的迭代节奏和验证标准。

> **核心原则：不是从 Layer A 建到 Layer D，而是从 Layer D 向下推导。**
> 先确定认知目标（为什么），再确定正确性标准（什么），再确定传播策略（怎么），最后确定具体材料（用什么）。

### Layer D：认知干预层

> **"人类的判断力怎样才更可靠？"**

| 维度 | 内容 |
|------|------|
| **目标** | 增强人类审阅判断力，对抗确认偏差 |
| **操作** | 问题优先呈现、信任信号体系、Accept 加摩擦 / Reject 减摩擦、审阅节律 |
| **迭代节奏** | 月级（按用户行为数据迭代） |
| **验证标准** | Accept/Reject 比率是否健康（建议 5:1 到 10:1）；平均审阅时长是否 > 30s/节点 |
| **失败模式** | 用户忽略所有提示 → 降级为"纯展示模式"；用户拒绝一切 → 降级为"纯 AI 模式" |
| **失败隔离** | 本层失灵 → 系统降级为展示工具，底层仍然正确运行 |

### Layer C：正确性保证层

> **"系统状态怎样才是完备的？"**

| 维度 | 内容 |
|------|------|
| **目标** | 系统状态的数学完备性 |
| **操作** | 不变量声明（INV-1~INV-N）、节点状态机、语义束跨树校验、kind 受控词表、Schema 渐进式修复 |
| **迭代节奏** | 季度级（按协议版本） |
| **验证标准** | 所有不变量有对应测试；状态机无死锁、无不可达状态；每条 failure path 有恢复行为 |
| **失败模式** | 不变量被违反 → 冻结受影响节点，标记需人工介入 |
| **失败隔离** | 本层违规 → 认知层仍展示信息（只是无法自动检测问题） |

### Layer B：生态集成层

> **"正确的东西如何进入世界？"**

| 维度 | 内容 |
|------|------|
| **目标** | 让协议被广泛采用，成为 AI 工具生态的共同语言 |
| **操作** | 独立协议仓库、CLI-first 集成路径、DeepSpec Tool Protocol、x_ 扩展命名空间、local.yaml 本地覆盖、MANIFEST.yaml 防篡改 |
| **迭代节奏** | 月-季度级（按第三方反馈） |
| **验证标准** | 第三方能否在不读实现代码的情况下完成集成？协议是否向后兼容？新的语言 binding 能否在 1 天内完成？ |
| **失败模式** | 第三方集成失败 → 降级为"只读 .deepspec/"；协议版本冲突 → 保留旧版本目录结构 |
| **失败隔离** | 本层断裂 → 正确性层仍然有效（.deepspec/ 内部不变量仍成立） |

### Layer A：工程实现层

> **"怎么可靠地造出来？"**

| 维度 | 内容 |
|------|------|
| **目标** | 可靠、可测试、可恢复的工程实现 |
| **操作** | 上下文组装管线、Hook 生命周期、快照与回滚、部分成功模式、项目健康度仪表盘、统一错误分类、单元测试 |
| **迭代节奏** | 周级（持续迭代） |
| **验证标准** | 核心模块测试覆盖率 > 80%；LLM 调用失败后自动恢复；单棵树失败不阻塞其他树审阅 |
| **失败模式** | YAML 解析失败 → 自动修复；LLM 超时 → 指数退避重试；watcher 失效 → 退化为手动触发 |
| **失败隔离** | 本层崩溃 → 生态层仍可用（CLI 可独立运行） |

### 四层的失败隔离原则

```
底层失败不向上传播：
  Layer A 崩溃 → Layer B 仍可用
  Layer B 断裂 → Layer C 仍有效
  Layer C 违规 → Layer D 仍提供价值
  Layer D 失灵 → 系统降级为展示工具

顶层设计决定底层价值：
  Layer D 目标错误 → 所有工程努力打折
```

---

## 4. 核心概念定义

### 4.1 语义束（Semantic Bundle）

四个投影树中描述同一件事的节点集合。一个语义束跨越多棵树，提供一个需求概念的所有投影。

```yaml
# bundles.yaml
bundles:
  - id: BND-001
    label: "用户登录"
    anchors:
      - tree: function
        node_id: FN-012
      - tree: module
        node_ids: [MOD-003, MOD-007]
      - tree: view
        node_ids: [VIEW-005, VIEW-006]
    confidence: 0.94
    completeness:
      has_function: true
      has_module: true
      has_view: true
      has_evidence: true
      has_decision: false
```

价值：按束审阅（而非按树审阅）、按束一致性检查、按束增量生成。

### 4.2 正交状态维度

节点的 status 拆为两个正交字段，避免语义混淆：

```
gen_status（生成维度）：pending | generated | failed
review_status（审阅维度）：pending | accepted | rejected | locked
```

组合语义：

| gen_status | review_status | 含义 |
|------------|---------------|------|
| generated | pending | AI 生成了，等人审 |
| generated | accepted | 已确认，可以作为基准 |
| failed | any | 生成失败，需要重试 |
| pending | any | 还没生成 |
| generated | rejected | AI 生成了但被否决 |
| generated | locked | 人工锁定，AI 不覆盖 |

### 4.3 信任信号（Trust Signal）

每个节点向审阅者展示的结构化可信度证据：

```
信任信号 =
  证据源状态（✅ 有来源 / ⚠️ 来源缺失 / ❌ 来源冲突）
  + LLM 推理链条（可展开，展示 AI 的推导过程）
  + 跨树一致性（同一语义束内其他树的状态）
  + 冲突检测（是否与人工决策或其他节点矛盾）
  + 人工决策历史（此节点被 accept/reject 的记录）
```

### 4.4 不变量（Invariants）

系统必须始终满足的硬性约束。每个不变量必须有对应的运行时断言和测试用例。

| ID | 陈述 | 验证方式 |
|----|------|----------|
| INV-1 | 节点 ID 在单棵树内唯一 | 写入时校验 |
| INV-2 | parent_id 必须指向同树内已存在的节点（或 null） | 写入时校验 |
| INV-3 | relation 的 source 和 target 必须指向已存在的节点 | 写入时校验 |
| INV-4 | status 迁移遵守有限状态机（draft→generated→reviewed→accepted; reviewed→rejected→draft） | 状态变更时校验 |
| INV-5 | 每个 accepted 节点必须有至少一条 evidence | Accept 时校验 |
| INV-6 | content_hash 变更时 gen_status 必须降级为 draft | 写入时校验 |

### 4.5 最小权限上下文（Least Privilege Context）

每次 LLM 调用只给恰好够用的文件，按生成目标裁剪：

```
生成 function-tree → 提供项目概览 + README + 需求文档
                      不提供源代码

生成 module-tree  → 提供项目概览 + function-tree + 源代码目录结构
                      不提供完整源代码内容

生成 view-tree    → 提供项目概览 + function-tree + DFM/PAS 文件
                      不提供业务逻辑代码

生成 data-tree    → 提供项目概览 + module-tree + schema/migration/state 相关文件
                      不提供无关 UI 细节
```

### 4.6 Kind 受控词表

每棵树有独立的合法 kind 值集合，避免跨语义层污染：

| 树 | 合法 kind 值 |
|----|-------------|
| function-tree | feature, capability, user_story, use_case, rule, constraint, non_functional, integration |
| module-tree | system, module, submodule, class, package, service, utility |
| view-tree | application, window, dialog, page, frame, panel, control, menu, toolbar, statusbar, tray |
| data-tree | entity, field, relation, state, migration, constraint |
| 跨树通用 | x_ 前缀（扩展 kind，核心 spec 不定义语义） |

---

## 5. 实践载体

方法论不只存在于文档中，必须嵌入日常实践的载体。

### 载体 1：检查清单

每次做决策前的快速公理对照：

```
在做任何决策前：
  □ 这个决策是否记录了输入证据？（A2）
  □ 这个决策是否承认可能被推翻？（A3）
  □ 我是否先看了问题和不一致，再看结论？（A6）
  □ 我给出的上下文是否"恰好够用"？（A5）
  □ 如果这个决策失败，系统是否仍然部分可用？（A7）

在接受任何 AI 产出前：
  □ 我能追溯这个产出的来源吗？（A2）
  □ 系统是否展示了对这个产出的质疑？（A6）
  □ 如果我选择 Accept，我的理由被记录了吗？
```

### 载体 2：协议文件

公理的机器可执行形式。当开发者写了一个新字段并通过了 invariants 校验，就自动遵守了 A2 和 A4。

```
protocol/
  invariants.md         → A2（可追溯）、A3（可谬）、A4（正交）
  state-machine.md      → A3（状态可逆）、A7（部分成功）
  controlled-vocab.md   → A4（正交分类）
  schemas/bundle.json   → A1（建构性：同一实体的多表征）
  workflow.yaml 规范    → A5（最小权限上下文的声明式配置）
```

### 载体 3：审阅仪式

四阶段标准审阅流程。偏离仪式需要说"为什么偏离"，而不是"为什么遵守"。

```
Phase 1：问题先行（3 分钟）
  打开 DeepSpec 仪表盘 → 先看"待解决问题"列表
  不看四投影树，只看系统标记的不一致和疑问
  问自己："这些问题中哪个最让我意外？"

Phase 2：选择性深入（10 分钟）
  对最让你意外的问题，展开它的信任信号
  决定 Accept 或 Reject（带理由）

Phase 3：全局浏览（5 分钟）
  快速浏览四投影树整体结构
  关注标红/标黄节点（confidence < 0.7 或证据缺失）
  不要逐个节点审阅——让系统的问题标记引导注意力

Phase 4：生成指令（2 分钟）
  基于审阅结果决定下一步：
    ○ 重新生成有问题的子树
    ○ 补充缺失的源文件后重新扫描
    ○ 锁定已确认的节点，只生成未确认的部分
    ○ 标记"当前规格足够好"，冻结
```

### 载体 4：决策日志

审阅行为的元数据记录，为 Layer D 的验证提供数据基础。

```yaml
# .deepspec/decisions/decision-journal.yaml
entries:
  - date: "2026-05-19"
    reviewer: "张三"
    decisions:
      - node_id: FN-012
        action: accepted
        reasoning_type: "verified_source"  # verified_source | consistent | reasonable
        confidence_self: 0.9
        time_spent_seconds: 45
      - node_id: MOD-003
        action: rejected
        reasoning_type: "verified_source"
        confidence_self: 0.7
        time_spent_seconds: 120
        rejection_note: "代码中 AuthService 的职责和 AI 理解不一致"
    meta:
      total_review_time: 1200
      accept_count: 8
      reject_count: 2
      skip_count: 3
      avg_confidence: 0.83
```

监控指标：
- accept_count >> reject_count → 确认偏差警告
- avg_time_spent < 30s → 可能是快速点击
- reject 后重新生成率 → 系统的自我改进能力

### 载体 5：方法论复盘

每月一次的方法论自身迭代。CTF 方法的 A3（可谬性）适用于方法论本身。

```text
议程：
  1. 回顾决策日志数据趋势
  2. 检查不变量违规记录
  3. 审查生态集成反馈
  4. 更新方法论本身
     - 七公理是否仍然成立？
     - 审阅仪式是否需要调整？
     - 是否需要新载体？
```

---

## 6. 方法论内化路径

新成员在四周内内化 CTF 方法：

| 周 | 活动 | 认知阶段 |
|----|------|----------|
| Week 1 | 阅读七公理（30 分钟）；跟着老成员做一次完整审阅仪式 | 跟随：不需要理解"为什么"，只需要"照做" |
| Week 2 | 阅读 invariants.md 和 state-machine.md；尝试写一个新的 invariant | 理解：开始问"这个步骤对应哪个公理？" |
| Week 3 | 独立完成审阅仪式；在决策日志中记录 reasoning_type | 实践：主动发现 AI 理解偏差并报告 |
| Week 4 | 参加方法论复盘；提出一个"公理可能不对"的论点 | 质疑：如果论点成立，参与修改公理 |

第四周的"质疑方法"是关键。不能被质疑的方法论是教条，不是方法。

---

## 7. DeepSpec Tool Protocol

AI 工具（Claude、Cursor 等）消费和更新 `.deepspec/` 的标准化工具接口。DeepSpec 持有上下文和校验逻辑，AI 工具不需要理解 `.deepspec/` 内部结构。

```
Tool: deepspec_read
  Input:  { tree: "function"|"module"|"view"|"data"|"all",
           format: "yaml"|"summary",
           filter?: { status, kind, confidence_min } }
  Output: 对应的树数据或摘要

Tool: deepspec_validate
  Input:  { scope: "all"|"tree"|"file", target?: string }
  Output: { valid: bool, issues: [...], invariants_broken: [...] }

Tool: deepspec_query
  Input:  { question: string }
  Output: 基于四投影树的 RAG 回答

Tool: deepspec_update
  Input:  { tree: string, nodes: [...], decisions?: [...] }
  Output: { accepted: bool, conflicts: [...] }
```

---

## 8. 协议扩展约定

```
保留命名空间：
  x_     → 第三方扩展（任何实现必须忽略不认识的 x_ 字段）
  _      → 内部临时字段（不应持久化）
  无前缀  → 核心 spec 字段

保留文件：
  x-*.yaml   → 第三方扩展文件
  local.yaml → 用户本地覆盖（不提交到 git）

兼容性承诺：
  - 新版本必须能读取旧版本 .deepspec/ 目录
  - 字段标记 deprecated → 保留 2 个小版本 → 删除
  - 未知字段必须被忽略（向前兼容）
```

---

## 9. 方法论的元规则

CTF 方法的第零公理和第三公理适用于方法论本身：

> **方法论不替代团队判断。它让团队判断更有分量。**

> **方法论本身可谬。如果实践证明某条公理不对，就改它。修改需要证据（来自决策日志的数据）和 unanimous 团队同意。修改后更新所有载体。**

---

## 附录：从 Symphony 到 CTF 的思想图谱

```
Symphony 的核心贡献：
  "管理工具而非监督工具" 的产品哲学
  RFC 2119 级的协议工程纪律
  双状态映射的本体建模
  分层信任边界的架构思维
  Proof of Work 的信任校准设计

12 位专家的提炼（四轮）：
  协议设计     陈架构 / Elena / Kenji
  生态策略     赵开源 / 周链 / Marcus
  信任安全     Sarah / Hans / 孙炼
  认知干预     Amara / 李产品 / 王工程

3 位总结者的升华（第五轮）：
  哲学基础     Isabelle Moreau
  分层验证     James Whitfield
  知识内化     Priya Narayan

最终产物：不是一份开发文档，而是一个信念体系。
```
