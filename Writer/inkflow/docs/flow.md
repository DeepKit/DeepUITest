# 墨韵 (InkFlow) v3.8: 人机交互流程

> 版本：v3.8（用户交互流程；补充 accepted canonical 与正式/审稿导出边界）
> 创建：2026-06-12 / 收敛：2026-06-15 / D-7~D-24 全部落地：2026-06-15 / 公开生产流简化：2026-06-26 / accepted canonical：2026-06-27
> 技术设计：`inkflow/docs/design.md`、`inkflow/docs/implementation-contract-v0.md`
> 角色体系：`inkflow/docs/role-system.md`
> 设计决策：`docs/decisions/README.md`
>
> 本文只定义写作模块的人机流程。

---

## 0. 当前 P0 目标：《分流》按章受控生产闭环

P0 以《分流》作为唯一验收样本：

```text
导入第 1 章人工样章
  → 锁定为 human_baseline
  → 审核 shot 边界
  → 提取风格/事实/人物声音基线
  → init 形成人类确认后的章以上层级契约
  → setup --chapter 进行单章生产前校准
  → run --chapter 按该章大纲逐 shot 生成，通过 L3/L4 后自动导出审稿稿
  → review --chapter 记录人工验收结论并写入 DB canonical 状态
  → accepted 后进入正式导出和后续历史上下文
  → 推敲系统 read-only 读取墨韵 DB 导入
```

固定路径：

```text
项目根：D:\_Progs\.Story\《分流》
墨韵库：D:\_Progs\.Story\《分流》\.inkflow\inkflow.db
模型配置：D:\_Progs\.Story\《分流》\.inkflow\.models
```

P0 不做全书一次生成，不做多项目/Universe，不做成本确认门，不让推敲回写墨韵数据库。

当前状态是受控试跑，不是正式批量生产。人类只在生产前契约/章前校准和生产后审稿阶段介入；`review --accept` 已成为章节级 accepted canonical 真相源，默认正式导出、后续 previous context 和历史 fact anchors 只认 accepted 章节。剩余主要风险是 CORE-2：run/shot attempt 身份还未和 logical shot 完全拆开。

## 1. 核心流程

```text
阶段 1: 人类与 AI 架构师沟通 (ink init)
  混合式交互：高创造力字段访谈 + 低创造力字段 AI 推断一次性呈现 (D-7)
  两阶段编译：human_confirm_layer 以上人类确认 + 以下 AI 自动展开 (D-7)
  AI 架构师识别项目结构 → 提取元契约 → 编译全链契约
  人类审核树状继承摘要，在任意节点注入修正
  契约落库，进入 confirmed 状态

阶段 2: 章前校准与 AI 全自动生产 (ink setup → ink run)
  setup 检查契约是否适用于当前章节；run 检查 setup 包是否来自当前元契约
  创建不可变契约快照
  赛车场经理加载预编译提示词
  不打断人类，不修改契约
  2-4 写手赛马（按人格差异化 prompt）(D-17)
  分层裁判：硬规则 → 类型职责 → 文学 9 维
  L4 Shot Gate 通过后，绿/黄进入正文，绿灯自动提取 9 类事实锚点 (D-19)
  红灯写 best-failed-candidate 占位 + smart-redo 3 级升级 (D-9)
  每个 Shot 完成后写入检查点 (D-14)
  L3 Chapter Gate 通过后，session 才 complete 并自动导出当前 run 审稿稿
  Scope 完成后生成三层交互式投影报告 (D-12)

阶段 3: AI 自动修补 (write repair)
  诊断红灯原因（写手失败 vs 契约问题）
  契约问题 → 四层修复金字塔（L1 零改动 / L2 风格级 / L3 结构级 / L4 方向级）(D-3)
  修复后重跑写手赛马 + 裁判 + 门控
  每次修复写入 writing_repair_audit
  优化黄灯

阶段 4: 人类集中二次处理
  审阅 run 自动导出的审稿稿
  用 ink review --accept/--revise/--reject 记录最终判断
  accepted 章节进入正式导出；revise/reject 章节进入重写准备
  查看契约仪表盘 (D-23)
```

DB3 是唯一真相源。终端摘要、Markdown 报告、导出文件都只是 DB 投影。

P0 中第 1 章人工样章是 locked baseline；墨韵只能读取它作为风格、事实、上下文来源，不得自动改写。第 2 章链路已通过真实项目试跑并获得人工“内容基本合格”反馈；第 3 章起按 `setup --chapter → run --chapter → review --chapter` 逐章推进。

---

## 2. CLI

```bash
# 全书初始化：建库、导入样章、生成章以上层级契约草稿
ink init "分流"
ink confirm-contract "分流"

# 导入人工样章并确认 shot 边界（P0）
ink import-baseline "分流" --chapter v01.c01 --file "D:\_Progs\.Story\《分流》\正文\V01_第01章_膝盖与螺丝刀·茶与水.md"
ink review-shots "分流" --chapter v01.c01

# 章前校准：只准备本章，不初始化全书
ink setup "分流" --chapter v01.c03

# 跨项目 clone
ink clone "分流" --as "分流_英文版"

# 全自动生产并导出审稿稿到 正文/
ink run "分流" --chapter v01.c02
ink run "分流" --writer-count 4     # 覆盖默认写手数
ink run "分流" --config jury.thresholds.green=8

# 生产后人工验收记录
ink review "分流" --chapter v01.c02 --accept
ink review "分流" --chapter v01.c03 --revise "章末钩子不足"

# 正式导出默认只取 accepted；审稿/排障稿需显式 --draft
ink export "分流" --chapter v01.c02
ink export "分流" --chapter v01.c03 --draft

# 恢复中断
ink run "分流" --resume
ink resume <session_id>
ink resume --last

# Session 管理
ink sessions list
ink sessions abort <id>

# 查看状态与报告
ink status "分流"
ink report "分流"
ink contracts "分流"                # 契约仪表盘 (D-23)

# 全书完成后的 AI 自动修补
ink repair "分流" --red
ink repair "分流" --yellow

# 硬边界逃生舱（每 run ≤ 1 次）(Phase 2)
ink revise-boundary "分流" --layer meta

# 声音校准
ink voice-calibrate "分流"

# 推敲系统导入（read-only 读取墨韵 DB，再复制到推敲自己的 story.db）
chisel import-inkflow "D:\_Progs\.Story\《分流》\.inkflow\inkflow.db" --title "分流"

# Chisel 二次校准
chisel scan "分流" --depth standard
chisel report "分流"
chisel batch-fix "分流"
chisel export "分流" -o "分流_终版.md"
```

---

## 3. Init / Setup 阶段

### 3.1 Init 对话目标

`ink init` 的目标是**把全书与章以上层级的人类创作意图转为可执行契约草稿**。人类编辑 `contract-draft.yaml` 后，通过 `ink confirm-contract` 确认入库。

关键创作字段不得由 AI 擅自补完。主题、硬边界、人物命运、不解之谜、结尾策略、叙事声音必须经人类明确确认后才能进入 confirmed 契约。AI 可以提出候选，但不能静默写入。

`ink setup <project> --chapter <key>` 的目标是**某一章生产前校准**：读取已确认契约、抽出本章 shot、生成 `.inkflow/chapter-setups/<chapter>.yaml`，供人类确认本章 shot 事件、类型职责（悬疑/留白/钩子）和禁止议论规则。它不初始化全书，也不改写正文。

契约问题和软件规则问题必须分开处理：

- 契约问题：本章生产前的 world_rules、chapter_N_events、style_locks 等内容不适用于目标章节，应通过更新契约草稿、`confirm-contract` 和重新 `setup --chapter --force` 解决。
- 软件规则问题：`run` 必须拒绝缺失、过期或章节不匹配的 setup 包；硬规则裁判不能把段落长度、方言、感官密度等风格项当成清零项。

### 3.2 交互模式：混合式（D-7）

| 字段类型 | 交互方式 | 说明 |
|---------|---------|------|
| **高创造力字段**（主题、硬边界、核心意象、不解之谜、叙事声音策略、核心角色、世界规则） | **访谈对话** | 架构师像编辑一样逐条提问，激发人类尚未意识到的创作假设。总共约 10-12 轮 |
| **低创造力字段**（反例集合、节奏曲线、POV 路由、意象密度预算、ASTO 坐标、写手人格配置、jury 权重） | **AI 推断 + 一次性呈现** | 架构师根据项目类型和模板自动生成初稿，人类覆盖/确认后入库。约 2-3 分钟扫视 |

### 3.3 提取深度：渐进式（D-7）

**Init 阶段**：只提取核心字段（主题、体裁、硬边界、核心意象种子、不解之谜）。

**第一卷完成后**：
- Chisel scan 分析实际文本中的意象密度、人物声音模式、反例触发频率、节奏曲线
- AI 架构师从分析结果中**反向提取**隐含契约
- 人类确认/修正 → 扩展契约 → 后续 Act 的 Shot 获得更精准的约束

### 3.4 两阶段编译流程（D-7）

```
Step 1: 识别项目结构
  - 叙事层级 + MNU
  - human_confirm_layer（人类确认到哪一层）

Step 2: 提取元契约
  AI 架构师从人类对话和写作指南中提取十子类

Step 3: 意象和元素分配
  分配每个意象到 shot_context（非章节序号），受 motif_density_cap 约束

Step 4: 展开 human_confirm_layer 以上契约（阶段 1a 编译）
  编译到 human_confirm_layer → 暂停，等待人类确认

Step 5: 人类审核（阶段 1a 确认点）
  展示树状继承摘要 → 人类注入修正 → AI 只重编译受影响节点

Step 6: 展开 human_confirm_layer 以下至 Shot 级（阶段 1b 编译）
  AI 自动向下展开，人类不逐一审核此层

Step 7: 全链冲突检测
  硬边界 / anti_reveal / exit_to 连续性 / 意象密度硬计数 / 意象互斥对

Step 8: 确认落库
  全链契约写入 DB → 状态变为 confirmed
```

### 3.5 人类对话界面

| 按键 | 含义 |
|------|------|
| `1-7` | 选择对应选项 |
| `8` | 认可当前层，进入下一层 |
| `8+` | 认可并标记后续同类自动采用 |
| `7+` | 跳过当前层，保留默认值 |
| `9` | 重新生成选项 |
| `0` | 回到上一级 |

人类也可以直接用文字纠正。AI 架构师必须把纠正重新转为结构化约束。

### 3.6 模板复用与跨项目 Clone

```bash
# 模板复用为后续能力，当前公开入口仍从 init 开始

# 跨项目 Clone
ink clone "分流" --as "分流_英文版"
  → clone 元契约 → interactive override 阶段 → 重新编译全链
```

---

## 4. Run 阶段

### 4.1 生产原则

`ink run` 启动后：

1. 创建不可变契约快照（contract_snapshot_hash）。
2. 设置契约状态为 `locked`。
3. 生产期不再询问人类。
4. 生产期只按契约写，不自动改契约。
5. 绿灯和黄灯直接成为当前正文版本。
6. 红灯写 best-failed-candidate 占位 + smart-redo 3 级升级，继续后续 Shot。
7. 成本不作为中断条件，不做运行前成本确认。
8. 章级事件不得在 run 中被 AI 自行改写；只允许补充场景细节、动作、感官和过渡。

### 4.2 Shot 流程

```text
load compiled prompt from writing_shot_prompts  -- init/setup 已预编译
assemble context:
  1. 前文窗口：N-1/N-2 全文 + N-3~N-5 摘要 + Scene Start 全文
  2. 人物状态快照（事实约束，来自 fact_anchors）
  3. Shot 契约（目标 + pov_routing）
  4. voice samples（风格参照）
  5. 反例提醒（最后一秒制动器）—— 最多 5 对具体样本对
  6. Motif Task (Required/Suggested/Forbidden/Allowed) + tracker 状态
run writer race (2-4 写手自动选择，按人格差异化 prompt)  (D-17)
run L0 mechanical checks
run Contract Gate 1
if no usable draft:
    write best-failed-candidate red placeholder revision  (D-9)
    run smart-redo (L0 prompt → L1 fast model → L2 redo（模型从 redo_model 配置读取）)
    if redo succeed: replace placeholder
    if 3 levels exhausted: mark done_red_permanent
    continue
run 9-jury scoring: 独立阅读→比较判断→最终输出  (D-21)
select winner
apply optional POV transition（如 Shot 契约含 pov_routing 切换）
apply optional hook/transition mutation
run final minimum gate on final text
if final gate red:
    create red placeholder revision
    continue
write winner as current revision
extract 9-type fact anchors (if green/yellow)  (D-19)
run Scene Composition Check if scene complete  (D-22)
run Intent Drift Detection every 5 shots  (D-22)
update motif density tracker  (D-20)
write checkpoint  (D-14)
mark green/yellow/red/brilliance/badsmell
continue
```

所有外部模型调用和 DB 写入必须有 `attempt_id` / `idempotency_key`。

### 4.3 反例注入格式

反例不是抽象规则——是具体样本对（D-15）：

```
❌ 坏写法："许念觉得自己被所有人推到了中间。"
✅ 好写法："群里安静了三秒。许念上一条'我来处理'下面，显示已读 17 人。没有人再接一句。"
```

**注入规则**：最多 5 对。优先级：本次 Session 红灯反例 > 人类手动反例 > 声音校准反例 > 模板通用反例。降温：连续 3 Shot 未触发 → 权重降低；连续 10 Shot 未触发 → 归档。

### 4.4 上下文版本控制

每个 Shot 的上下文写入 `writing_context_snaps`。Anthropic Prompt Caching 设置 3 个 breakpoint——元契约 + 角色配置缓存前缀，预期 ~60% tokens 可缓存（D-18）。

### 4.4.1 模型配置

模型配置来自项目级 `.inkflow/.models`：

```yaml
architect:
  primary: claude-opus-4-6
  candidates: [claude-sonnet-4-6]
  fallback: gpt-5

writer:
  primary: claude-sonnet-4-6
  candidates: [gpt-5]
  fallback: local-default

jury:
  primary: claude-sonnet-4-6
  candidates: [gpt-5]
  fallback: claude-haiku-4-6
```

运行期按功能选择 primary，失败后按 candidates 顺序尝试，最后使用 fallback。成本不参与模型选择。

### 4.5 红黄绿

| 灯色 | 生产期行为 | 后续行为 |
|------|------------|----------|
| 绿 | 写入当前正文，自动提取 9 类事实锚点 | 后续全书校准 |
| 黄 | 写入当前正文并标记观察 | 全书完成后 AI 优化 |
| 红 | 写 best-failed-candidate 占位 + smart-redo 3 级升级 | 3 级耗尽后 mark done_red_permanent，Scope 投影中处理 |

### 4.6 占位格式

红灯占位使用 best-failed-candidate——Gate 2 violation 最少的候选文本（D-9）：

```text
[RED_PLACEHOLDER]
<最高分失败品的正文>
失败原因: 意象密度超标(3 > cap 2), Alice事实锚点冲突(年龄)
placeholder_type: best_failed_candidate
writer: writer_B
后续衔接: Alice 继续向工厂深处走去...
[/RED_PLACEHOLDER]
```

### 4.7 运行时人类可视性（D-8）

- **粒度**：Shot 级汇总——每个 Shot 完成后输出日志记录（纯日志，非交互式 UI）
- **干预模式**：完全无人干预——流水线一次性跑完。人类只在 Scope 完成后查看投影报告
- **Scope 进度**：终端显示 "Shot 37/52：Alice 进入废弃工厂" 而非实时文本流

---

## 5. 报告

### 5.1 Scope 投影报告（D-12）

每个 Scope 完成后生成三层交互式视图：

```
Layer 1: 摘要卡片
 Act 1 / Ch 3 / Scope 2
 12 Shots: 9 绿 ●  2 黄 ●  1 红 ●
 Avg jury score: 7.2  |  Motif density: 1.8  |  Voice: 92%

Layer 2: Shot 列表（原文预览 + score + 灯色）
Layer 3: Shot 详情（完整正文 + 9维 radar + 裁判评语 + 被拒亮点 + Gate 结果 + 事实锚点 + 操作按钮）
```

### 5.2 人类操作

| 操作 | 含义 | 执行方式 |
|------|------|---------|
| `approve` | 显式确认无需修改 | 直接 |
| `fix "…"` | 向 AI 架构师描述问题 → 架构师重写 | 架构师中介 |
| `redo` | 用不同 writer 配置重新生成 | 直接 |
| `flag` | 标记需后续注意 | 直接 |
| `edit context` | 修改契约上下文（不直接改文本） | 架构师中介 |
| `lock` | 锁定不被后续 repair 修改 | 直接 |

### 5.3 全书报告与契约仪表盘

全书报告：
- 红灯清单 + 诊断结果
- 黄灯清单
- 高风险连续性问题（D-22 Scene Composition + Intent Drift）
- 事实锚点一致性报告（D-19）
- AI repair 队列

契约仪表盘（D-23）：
- `ink contracts "分流"` ——四维视图：条款/声音/Motif/违规

---

## 6. Repair 阶段

### 6.1 四层修复金字塔（D-3）

| 层级 | 名称 | 触发条件 | 操作 | 人类确认 |
|------|------|----------|------|----------|
| L1 | Auto-rerun | 纯随机波动（写手失败） | 保留同一裁判/契约/文件，重跑写手赛马 | 零 |
| L2 | Auto-contract-fix | 风格级契约矛盾（语气反例冲突、must_land 模糊） | AI 架构师自动修约 + 输出 diff（人类可读） | 零，但 diff 留痕 |
| L3 | Batch confirm | 结构级问题（Shot 拆分/合并） | 人类在列表中一次性看到所有变化预测 | 人类在列表中一次性确认 |
| L4 | Human intervene | 方向级问题（章节级冲突、硬边界触线） | 暂停，人类逐项确认 | 人类逐项确认 |

**升级规则**：
- L1 连续 3 次失败 → 自动升级到 L2
- L2 连续 3 次失败 → 自动升级到 L3（自动暂停章节后续 Shot）
- L3 连续 2 次失败 → 自动升级到 L4
- ⭐⭐⭐ 稳定性约束触碰 → 直接升级到 L4

**硬规则安全网**：
- 连续红灯升级：同一 Shot N 次红灯，自动升级 repair 层级
- ⭐⭐⭐ 触碰升级：L3 涉及 hard_boundaries / anti_reveal，立即升级 L4
- 连锁影响升级：L3 变更影响 > 3 个已执行 Shot，自动升级 L4

**通用规则**：
- 修复频率不超过 1x/500 Shots（contract-fix 如需可重触发）
- 每次修复写入 `writing_repair_audit`
- 红灯 Shot 若因边界/主题/契约冲突，必须诊断根因，不能盲目重跑

### 6.2 硬边界修订（D-4）

`ink revise-boundary` (Phase 2) 提供托管的人机边界修订流程。

**Phase 1a（设施）**：每个 Shot 记录 `source_hard_boundary_index` + 新增审计表 `writing_meta_contract_revisions`

**Phase 1b（边界修订对话）**：
```bash
ink revise-boundary <project> [--layer L2|L3|L4]  # (Phase 2)
```

展示影响报告：范围、受影响 Shot、divergence chain、boundary gate judges。逐层审查：L2 一次确认，L3 按章确认，L4 人类逐条确认。`per run ≤ 1` 次使用限制。每次修订 ≥ 50 中文字符理由。

**Phase 2 扩展**：
- `chisel suggest` — AI 诊断的偏差
- `ink run --suggest` — suggest + 只读 dry-run +5 Shots

### 6.3 修复执行

```text
Step 1: 诊断红灯原因
  AI 架构师加载每个红灯 Shot 的裁判反馈 + deviation_notes
  判断：写手执行失败？还是契约本身有问题？

Step 2: L1 - 如果是"写手失败"
  原契约重跑写手赛马 + 裁判 + 门控 → 生成 write_repair revision
  无需人类确认

Step 3: L2/L3/L4 - 如果是"契约问题"
  按四层修复金字塔处理：
  L2（自动修约）→ AI 架构师自动修约，输出 diff 留痕
  L3（批量确认）→ 生成修约建议，人类列表一次性确认
  L4（人工介入）→ 必须人类逐项确认
  修约完成后重跑写手赛马 + 裁判 + 门控

Step 4: 优化黄灯
  读取黄灯正文 + 黄灯原因 → 做文学性、声音、衔接优化

Step 5: 事实锚点一致性检查
  所有 repair revision 必须与已跑绿灯 Shot 的事实锚点一致 (D-19)
```

repair 仍不要求人类逐 Shot 介入。repair 完成后，人类集中审阅。

---

## 7. 与 Chisel 二次校准衔接

全书生产和 AI repair 完成后，或单章 `review --accept` 后：

```bash
chisel import-inkflow "D:\_Progs\.Story\《分流》\.inkflow\inkflow.db" --title "分流"
chisel scan "分流" --depth standard
chisel report "分流"
chisel batch-fix "分流"
chisel export "分流" -o "分流_终版.md"
```

Chisel 的职责是二次校准和优化，不是生产期拦截器。Chisel 只读 InkFlow DB，并复制导入到自己的 story.db；不得回写 InkFlow DB。

---

## 8. 完整工作流

```bash
# Step 1: 全书初始化，并生成 contract-draft.yaml
ink init "分流"

# Step 2: 人类编辑 contract-draft.yaml 后确认
ink confirm-contract "分流"
  # 高创造力字段：10-12 轮访谈对话
  # 低创造力字段：AI 推断 + 一次性呈现，约 2-3 分钟扫视
  # 阶段 1a 编译到 human_confirm_layer
  # 人类审核树状继承摘要 → 注入修正 → AI 重编译受影响节点
  # 阶段 1b AI 自动展开至 Shot 级
  # 确认后契约落库

# Step 3: 章前校准
ink setup "分流" --chapter v01.c03
  # 人类确认本章 shot、POV、类型职责、章末钩子、禁止议论规则

# Step 4: 生成本章并自动导出审稿稿到 D:\_Progs\.Story\《分流》\正文\
ink run "分流" --chapter v01.c03 --resume
  # 2-4 写手按人格差异化 prompt
  # 硬规则 → 类型职责 → 文学 9 维评分
  # 绿/黄入正文，9 类事实锚点自动提取
  # 红灯 best-failed-candidate + smart-redo 3 级升级
  # 每 Shot 检查点，Scene Composition Check + Intent Drift Detection
  # Scope 完成后生成交互式三层投影报告

# Step 5: 人工验收；accepted 后进入正式导出和后续上下文
ink review "分流" --chapter v01.c03 --accept
  # 或：ink review "分流" --chapter v01.c03 --revise "具体问题"

# Step 6: AI 自动修补（四层修复金字塔，如需要）
ink repair "分流" --red
  # AI 诊断红灯原因 → L1～L4 逐级修复 → 重跑
ink repair "分流" --yellow

# Step 6b: 硬边界修订（如需要，per run ≤ 1）(Phase 2)
ink revise-boundary "分流" --layer meta

# Step 6c: 查看契约仪表盘
ink contracts "分流"

# Step 7: Chisel 二次校准
chisel import-inkflow "D:\_Progs\.Story\《分流》\.inkflow\inkflow.db" --title "分流"
chisel scan "分流" --depth standard
chisel report "分流"
chisel batch-fix "分流"
chisel export "分流" -o "分流_终版.md"
```
