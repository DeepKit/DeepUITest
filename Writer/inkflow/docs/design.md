# 墨韵 (InkFlow) v3.12: 全自动文学文本生产引擎 — 技术设计

> 版本：v3.12（Schema v15：D-25 信息差、ARCH-12 三棵树、ARCH-13 正文真相源、ARCH-4 L0 全书宪法、ARCH-5 L0.5 卷部节奏、ARCH-10 风格偏好、ARCH-11 反契约沙盒、CREATIVE-1 意外价值、CREATIVE-2 二次精修、CREATIVE-3 留白创意评审）
> 创建：2026-06-12 / v3.5 收敛：2026-06-14 / v3.6 变更：2026-06-14 / D-7~D-24 全部落地：2026-06-15 / v3.9 Schema v8：2026-06-21 / v3.12 Schema v9：2026-06-24 / 优化迭代 Schema v15：2026-06-25
> 决策记录：`docs/decisions/` 下 D-01 至 D-24
> 角色体系：`inkflow/docs/role-system.md`
>
> 本文档是 InkFlow 的技术实现权威口径。DDL/状态机/协议以 `implementation-contract-v0.md` 为准。

---

## 0. 当前 P0 目标（2026-06-17）

墨韵当前开发目标已经收敛为《分流》单书纵向闭环：

```text
导入《分流》第 1 章人工样章
  → 锁定为 human_baseline
  → 确认 shot 边界
  → 提取风格指纹、事实锚点、人物声音基线
  → setup 多轮互动形成 confirmed 契约
  → 按第 2 章大纲逐 shot 生成第 2 章
  → writer race + jury + gate + revision + checkpoint
  → 章后报告
  → 推敲系统 read-only 读取墨韵 DB 导入并独立校准
```

固定工程边界：

1. P0 只做单书闭环，不做 Universe / 多项目同步。
2. 用户按 chapter 发起 run，系统内部按 shot 执行。
3. 第 1 章是 locked baseline，墨韵不得自动改写。
4. 第 2 章必须严格遵守章级事件，AI 只补充细节、动作、感官和过渡。
5. 关键创作字段必须经人类确认，AI 不得静默补完主题、硬边界、不解之谜和结尾策略。
6. 成本不作为开发和运行约束，只记录 usage。
7. 模型选择来自项目级 `.inkflow/.models`。
8. 推敲系统只能 read-only 读取墨韵 DB，并复制到自己的 story.db，不得回写。

## 1. 产品目标

Chisel Write 的目标是生产高质量长篇文学文本，同时在受控空间内允许 AI 发挥创造力。

核心工作方式：

```text
人类与 AI 架构师前置沟通 (write setup)
  → 混合式交互：高创造力字段访谈 + 低创造力字段 AI 推断一次性呈现 (D-7)
  → 两阶段编译：human_confirm_layer 以上人类确认 + 以下 AI 自动展开 (D-7)
  → AI 架构师编译全链契约并落库
  → 人类审核树状继承摘要，在任意节点注入修正
  → 确认后契约进入 confirmed 状态
  → write run 创建不可变契约快照，全自动生产正文
  → 每个 Shot 完成后写入检查点 (D-14)
  → 绿灯/黄灯 Shot 直接进入正文版本链，绿灯自动提取 9 类事实锚点 (D-19)
  → 红灯 Shot 写 best-failed-candidate 占位 + smart-redo 3 级升级 (D-9)
  → Scope 完成后生成交互式三层投影报告 (D-12)
  → 全书生产完成
  → AI 先诊断红灯原因（四层 repair 框架），修约后重跑
  → AI 优化黄灯
  → 人类在 Scope 投影中集中处理 (D-8)
  → Chisel scan/report/fix 做全书校准
```

不可变原则：

1. DB3 是唯一真相源，报告和导出文件只是投影。
2. 生产期不打断人类。
3. `write run` 只能执行本次已落库契约快照，不自动修改契约。
4. AI 产出直接成为正文版本；后续修改由 revision 链维护。
5. 红灯不留空，必须生成 best-failed-candidate 占位正文，保证后续上下文连续。
6. 质量优先级为：文学质感 > 人物声音 > 情节契约 > 节奏 > 成本速度。
7. Token 成本不作为当前架构约束。

---

## 2. 角色边界

| 角色 | 类型 | 职责 |
|------|------|------|
| 出品人 | 人类 | 前置沟通、审核继承摘要、节点修正、最终方向判断、Scope 投影中集中操作 |
| AI 架构师 | AI | 识别项目结构、编译全链契约、生成元契约、冲突检测、诊断红灯原因、Voice Calibration、Intent Drift 检测 |
| 赛车场经理 | Python 编排 | 锁定契约快照、加载预编译提示词、调度写手/裁判/门控、提取 9 类事实锚点、Motif 追踪、检查点、状态恢复、落库 |
| 写手池 | AI | 按 4 人格差异化提示词 + voice samples + 反例生成候选正文 |
| 裁判团 | AI | 当前默认 3 模型 × 5 维评分；标准 shot 按 `trimmed_mean`，留白 shot 按 `creative_score` |
| Chisel 校准链 | Python + AI + 人类 | 全书完成后做 scan/report/fix/二次校准 |

生产期的人类角色是旁观者，不参与单章或单 Shot 决策。

---

## 3. 契约系统

### 3.1 项目结构自适应

Chisel Write 不预设固定的四级契约结构。每个项目的叙事层级由 AI 架构师在 setup 阶段识别。

系统内部统一使用 **MNU（最小叙事单元）** 作为赛车场经理循环的基本单位。

```json
{
  "project_id": "分流",
  "layers": [
    {"index": 0, "name": "book", "native_name": "全书"},
    {"index": 1, "name": "volume", "native_name": "卷"},
    {"index": 2, "name": "chapter", "native_name": "章"},
    {"index": 3, "name": "shot", "native_name": "Shot", "is_mnu": true}
  ],
  "human_confirm_layer": 2
}
```

`human_confirm_layer` 决定两阶段编译边界（D-7）：
- `chapter` 级确认 → AI 自动展开 Shot（如《分流》）
- `部` 级确认 → AI 自动展开场（如《签》）
- `卷` 级确认 → AI 自动展开集（如《背锅侠》）

两阶段设计防止 H1 设计缺陷：人类在 human_confirm_layer 注入修正 → AI 架构师只重编译下游，已确认层不受影响。

### 3.2 元契约

全书级元契约十子类，AI 架构师从人类对话和写作指南中提取：

| 子类 | v | 内容 | 稳定性 | 谁可以改 |
|------|:---:|------|:---:|------|
| identity | 3.6 | 这本书是什么、不是什么 + `thematic_core` 主题核心声明 | ⭐⭐⭐ | 只有人类 |
| hard_boundaries | 3.5 | 绝对不能写什么 | ⭐⭐⭐ | 只有人类 |
| anti_reveal | 3.6 | 不解之谜保护 + `confidence` 置信度 + `release_window` 预计揭晓窗口 | ⭐⭐⭐ | 只有人类 |
| anti_patterns | 3.5 | 最容易写偏成什么 | ⭐⭐ | 人类可改 |
| narrative_voice | 3.6 | 叙述声音 + `pov_characters` POV 角色列表 + 各角色 voice_style | ⭐⭐ | 人类可改 |
| style_locks | 3.6 | 叙事视角、语言腔调、对话纪律 + 同一 style_lock 在不同 POV 角色下的释义差异 | ⭐⭐ | 人类可改 |
| structure_rules | 3.6 | 层级规划 + `volume_pov_routing` 卷级 POV 路由 + `emo_state` 各卷情感态势 | ⭐⭐⭐ | 只有人类 |
| creative_zones | 3.5 | 哪些区域允许 AI 放开写 | ⭐ | 人类可改 |
| motif_system | 3.6 | 意象/元素定义 + `density_policy` 密度上限 + `mutual_exclusion` 互斥对 | ⭐⭐ | 人类可改 |
| world_knowledge | 3.5 | 世界设定事实（技术/规则/地理/历史） | ⭐⭐ | 人类可改 |

v3.6 D-1 字段扩展摘要：`identity.thematic_core` / `anti_reveal[].confidence` / `anti_reveal[].release_window` / `structure_rules[].emo_state` / `motif_system.density_policy` / `narrative_voice.pov_characters`

### 3.3 契约编译链

AI 架构师在 setup 阶段走完以下流程：

```
Step 1: 识别项目结构 → 确定 MNU + human_confirm_layer
Step 2: 提取硬边界列表 (hard_boundaries + anti_reveal)
Step 3: 提取意象/元素 must_recur → 分配到 shot_context（叙事上下文，非章节序号）
Step 4: 按卷/部扫描大纲 → 提取每卷专属约束
Step 5: 展开 human_confirm_layer 以上契约（阶段 1a 编译）
Step 6: 人类审核 → 节点注入修正 → AI 重编译受影响节点（不碰已确认层）
Step 7: 展开 human_confirm_layer 以下至 Shot 级（阶段 1b 编译）
Step 8: 全链冲突检测
Step 9: 编译 Shot 提示词 + 版本化 + 落库
```

编译顺序：**anti_write 链先展开，must_land 链后展开。** 先锁边界再填内容。

### 3.4 意象分配

意象不分配到章节序号——分配到 `shot_context`（叙事上下文）：

```json
{
  "element": "盖碗茶",
  "total_required": 3,
  "allocations": [
    {
      "shot_context": "白英清晨开茶社，擦竹椅，试杯壁温度",
      "function": "establish_character_body_memory",
      "chapter_hint": "v01.c01",
      "chapter_hint_is_soft": true
    }
  ]
}
```

`chapter_hint` 是软建议——场景移动时分配自动跟随。

### 3.5 契约继承

- 下层自动继承上层所有约束。
- 下层可以细化上层约束，不可否定上层硬边界。
- 人类在树状继承摘要的任意节点注入修正 → AI 架构师自动向下重编译。

继承摘要示例：

```
鱼嘴不能被推翻 (全书硬边界)
  ├── 卷一：鱼嘴正常运转，边界在不知不觉中移动 ✅
  │   └── 第 01 章：苏然发现外江推了 17%，不报告 ✅
  ├── 卷三：苏然推一厘米，不是推翻 ✅
  │   └── 第 19 章 Shot 4：苏然加备注，不删库 ✅
  └── 卷四：评估团建议"可复制的局部校正模型" ✅
```

### 3.6 契约生命周期

```
draft → human_review → confirmed → locked → [repairing] → [evolving]
```

| 状态 | 含义 | 可变性 |
|------|------|------|
| `draft` | AI 架构师编译中 | 任意修改 |
| `human_review` | 等待人类审核 | 可修改 |
| `confirmed` | 人类确认，尚未 run | 可修改但需重新确认 |
| `locked` | `write run` 快照已创建 | **不可变** |
| `repairing` | 修补中 | 红灯 Shot 契约可改，硬边界不可改 |
| `evolving` | 人类追加新约束 | 未执行 Shot 自动重编译，已执行标记 stale |

### 3.7 事实锚点（D-19）

绿灯 Shot 落库时，赛车场经理自动提取 9 类不可逆事实：

```json
{
  "anchor_id": "fa_act1_037",
  "project_id": "qianlong",
  "type": "character_state",
  "subject": "Alice",
  "predicate": "location",
  "value": "废弃工厂 B 区，一楼",
  "source_shot_id": "act1_ch3_s37",
  "confidence": "explicit",
  "scope": "scene",
  "status": "active"
}
```

**9 类锚点**：

| 类型 | 示例 | scope |
|------|------|-------|
| `character_state` | Alice 在工厂 B 区 | scene |
| `character_trait` | Ben 怕黑 | project |
| `object_location` | 对讲机在 Alice 手中 | scene |
| `object_property` | 对讲机频道 7、电量不足 | scene |
| `event_occurred` | 爆炸发生在 14:30 | chapter |
| `relationship` | Alice 不信任 Ben | act |
| `world_rule` | 古蜀不存在高科技 | universe |
| `timeline` | Act 1 发生在 2024 年 3 月 | act |
| `knowledge` | Alice 不知道 Ben 的过去 | act |

**提取流程**：Shot 正文 → Fact Anchor Extractor（AI Agent）→ 新增锚点 / 更新锚点 / 确认锚点。

**5 种冲突类型**：显式矛盾 / 隐式不一致 / 时间线错位 / 可解释偏差 / 视角矛盾（POV-dependent）。

后续 repair 或新 Shot 契约编译，必须通过事实锚点一致性检查。

### 3.8 契约升级路径（D-11）

当 Chisel 版本升级引入新契约字段时：

| 级别 | 触发条件 | 处理 |
|:---:|------|------|
| L1 | 新字段有明确默认值 | 自动填充，不通知人类 |
| L2 | 新字段需要项目上下文 | AI 推断 → 人类一次性确认 |
| L3 | 新字段需要人类原创输入 | 标记 pending，人类下次 setup 处理 |

**已生成文本不回写**——升级后的新契约只影响下游未生成的 Shot。

---

## 4. 红黄绿 + 精彩/坏味灯

红黄绿以 Shot 为主粒度。精彩灯与坏味灯**完全正交**（D-2）——同一 Shot 可同时持有 brilliance 和 badsmell 双灯，互不降级。

| 灯色 | 正文行为 | 后续行为 |
|------|----------|----------|
| ⭐ 精彩 S/A+/A | winner 入正文，标注 brilliance_level | Phase 1 仅记录——人类在全书 production report 中统一审批入池 |
| 绿灯 | winner 正文进入当前正文版本链，自动提取事实锚点 | 后续 Chisel 校准仍可修改 |
| 黄灯 | winner 正文进入当前正文版本链并标记观察 | 全书完成后 AI 优先优化 |
| 💀 坏味 B/Br/Bz | winner 入正文，独立标注 badsmell_level | Br 需 repair 优化；Bz 必须人类确认后入反例库。AI Flavor 不进入坏味灯——写入 Character Writing Guide 的 `negative_samples` |
| 🔴 红灯 | best-failed-candidate 占位 + violation 说明（D-9） | smart-redo 3 级升级；耗尽后 mark `done_red_permanent` |

**Writer Race 全失败处理（D-9）**：

- **Placeholder**：Gate 2 violation 最少的候选（best-failed-candidate），附带 violation 说明
- **Smart-Redo 3 级升级**：L0 prompt 重试 → L1 fast model 重试 → L2 redo（模型从 redo_model 配置读取，默认 claude-sonnet-4-6）
- **Smart-Redo 成功**：完全替换 placeholder
- **3 级耗尽**：标记 `done_red_permanent`，Scope 投影红色边框 + violation 摘要——不暂停整个 Scope

**双灯记账**（D-2）：同一 Shot 可同时标注 `brilliance_level: A` 和 `badsmell_level: B`。

---

## 5. 写作流水线

```text
for shot in run_scope:
  load compiled prompt from writing_shot_prompts     -- setup 已预编译
  assemble context:
    1. 前文窗口：N-1/N-2 全文 + N-3~N-5 摘要 + Scene Start 全文
    2. 人物状态快照 (来自 fact_anchors)
    3. Shot 契约 (目标 + pov_routing)
    4. voice samples (风格参照)
    5. 反例提醒 (最多 5 对)
    6. Motif Task (Required/Suggested/Forbidden/Allowed) + tracker 状态 (D-20)
  run writer race (2-4 写手，自动选择，按人格差异化 prompt)  (D-17)
  run L0 mechanical checks
  run Contract Gate 1
  if no usable draft:
      write best-failed-candidate red placeholder revision
      run smart-redo (L0 prompt → L1 fast model → L2 redo（模型从 redo_model 配置读取，默认 claude-sonnet-4-6）)  (D-9)
      if redo succeed: replace placeholder with success revision
      if 3 levels exhausted: mark done_red_permanent
      continue
  run 9-jury scoring: 独立阅读→比较判断→最终输出  (D-21)
  select winner
  apply optional hook / transition as draft mutation
  run final minimum gate on final text
  if final gate red:
      create red placeholder revision
      continue
  write winner as current revision
  extract fact anchors (9 类) if green/yellow  (D-19)
  run Scene Composition Check if scene complete  (D-22)
  run Intent Drift Detection every 5 shots  (D-22)
  update motif density tracker  (D-20)
  write checkpoint (恢复用)  (D-14)
  mark green/yellow/red/brilliance/badsmell

after scope complete:
  generate scope projection report from DB  (D-12)
  continue next scope without human interruption
```

所有外部模型调用和 DB 写入必须有 `attempt_id` / `idempotency_key`。

---

## 6. 写手池

### 6.1 4 写手人格系统（D-17）

每个写手拥有固定创作人格，决定注意力分配——不是限制能力域，而是引导方向：

| 写手 | 人格 | 核心关注 | 次要关注 | 盲区 |
|------|------|---------|---------|------|
| A | **意象师** (Imagist) | 感官细节、氛围营造、隐喻系统 | 场景沉浸 | 对话推进、情节速度 |
| B | **节奏师** (Pacer) | 叙事节奏、悬念构建、信息释放时机 | Hook/衔接 | 意象密度、氛围 |
| C | **对话师** (Dialogist) | 人物对话、潜台词、声音差异 | 声音一致性 | 场景描写、环境 |
| D | **结构师** (Structuralist) | POV 一致性、事实锚点对齐、场景结构 | 事实一致性 | 对话自然度、文学性 |

**差异化来源**：
1. Prompt 加权：核心关注维度 2x token 预算
2. 正例倾斜：voice samples 选择偏向核心关注
3. 自评注释：写手产出后附 ≤150 token 自评

**非差异化项**：基础 prompt、反例系统、模型层、输出长度限制——所有写手相同。

### 6.2 写手数量自动选择

```
shot.dialogue_ratio > 0.4              → 3 名 (A意象+B节奏+C对话)
shot.pov_count > 1 or fact_anchor_count > 3 → 4 名 (A+B+C+D结构)
else                                   → 2 名 (A+B)
```

默认 2 名（意象师 + 节奏师），人类可覆盖 `--writer-count 4`。

### 6.3 写手 Prompt 三层结构

```
Layer 1: 共享基础 (Shared Base) — 所有写手相同
├── Shot Context (场景描述、前文窗口、人物在场列表)
├── Fact Anchors (本 Shot 相关)
├── Meta-Contracts 硬约束
└── Anti-Samples (最多 5 对)

Layer 2: 人格加权 (Persona Lens) — 按写手差异化
├── 核心关注维度：2x token budget 详细指示
├── 次级关注维度：1x token budget 简略指示
└── 盲区维度：0.5x token budget 基础提醒

Layer 3: Shot 特定 (Shot-Specific)
├── Motif Task (Required/Suggested/Forbidden/Allowed)
├── POV 指示 (本 Shot 视角角色)
├── Pacing Cue (节奏曲线位置)
└── Transition Hint (前后衔接提示)
```

### 6.4 Writer Profile

```json
{
  "profile_id": "...",
  "project_id": "...",
  "system_prompt_template": "...",
  "voice_samples": [...],
  "anti_samples": [...],
  "temperature_range": {"default": 0.7, "creative": 0.85}
}
```

### 6.5 反例系统（D-15）

**五类来源**：

| # | 来源 | 触发条件 |
|---|------|---------|
| 1 | 手动输入 | Setup 阶段人类明确指定 |
| 2 | 声音校准生成 | Voice calibration 自动生成 |
| 3 | 红灯反向推导 | Gate 红灯 → 自动提取为下个 Shot 反例 |
| 4 | Project 通用反例 | 项目建立时从模板加载 |
| 5 | 人类运行时注解 | Scope review 时标记 |

**声音校准工作流**：
```
ink voice-calibrate <project>

1. 加载 voice samples (每角色 ≥3 段)
2. AI 分析 → 提取 marker (词频/句长/修辞偏好/禁忌词/口头禅) → 生成 voice fingerprint
3. 生成反例：每 marker 1-2 个违反样本
4. 人类确认/修正/删除
```

**反例运行时注入**：最多 5 对样本对（❌/✅ 格式），prompt 末尾注入（recency effect）。

**反例降温**：连续 3 个 Shot 未触发 → 权重降低。连续 10 个 Shot 未触发 → 归档到参考池。

**Voice Drift 检测**：每 3 个 Scope 对比 voice marker 命中率与基准指纹。偏离 > 15% → 告警。

### 6.6 参考池

```sql
writing_reference_pool
  ├── sample_id
  ├── project_id
  ├── sample_type            -- 'positive' | 'negative'
  ├── source                 -- 'human_provided' | 'high_score' | 'low_score' | 'manual'
  ├── sample_text
  ├── annotation             -- 为什么好/为什么坏
  ├── tags_json              -- ["voice", "body_moment", "ai_flavor"]
  └── jury_score
```

成长飞轮：人类种子 → 写手生成 → 裁判评分 → 高分入 positive pool / 低分入 negative pool → 写手下次获得更丰富样本。

### 6.7 角色写作指南 (Character Writing Guide)

每个 POV 角色配备完整写作规范。赛车场经理加载策略：
- **POV 角色**：加载完整指南（portrait + voice + behavior_patterns + recognition_traits + phase_switching）
- **出场角色**：加载简要版（voice + recognition_traits）
- **提及角色**：仅加载 recognition_traits

### 6.8 场景姿态 (ASTO + scene_position)

ASTO 三轴：Phase（叙事节律）/ Mode（存在主义质感）/ Sequence Profile（段落级七步权重）。

scene_position 由一个字段控制整条流水线：哪些检查点激活、哪些 Slot 注入、哪些裁判维度增重。

---

## 7. 裁判团

### 7.1 3-Phase 评分架构（D-21）

```
Phase 1: 独立阅读（不比较）
├── 阅读候选 A → 当前默认 5 维打分 + 注释
├── 阅读候选 B → 当前默认 5 维打分 + 注释
├── 阅读候选 C → ...
└── 阅读候选 D → ...

Phase 2: 比较判断
├── 每维度排序 (A > B > C > D)
├── 综合排序 (winner, 1st runner-up, ...)
└── 生成比较性评语

Phase 3: 最终输出
├── winner 正文
├── 每位候选的逐维分数
├── winner 比较性评语
├── 被拒绝候选的亮点摘录
└── 综合置信度 (0-1)
```

**评分模式**：相对排序 + 绝对分双重机制。相对排序用于选 winner，绝对分用于 Gate（是否绿灯）。

**量程**：每维度 0-100 分，整数分；灯色阈值使用 green≥85 / yellow≥65。

**模型**：使用 `model_tiers.jury`（默认 Sonnet）——Jury 是评判工作，不是创造工作。

**校准**：每 3 个 Scope 检查分数分布（σ < 1.0 提示需要更多区分度）；如 winner 总是一种人格，检查人格偏见。

### 7.2 配置

当前实现采用 3 个评委模型 × 默认 5 个评分维度。旧设计中的 9 裁判团维度作为历史兼容枚举保留，不再作为默认运行口径。

动态裁判从系统级维度池中由元契约自动激活：

| 元契约特征 | 自动激活 |
|------|------|
| anti_reveal 列表非空 | 伏笔官 |
| 声明了主题 | 主题官 |
| 人物有弧线设计 | 弧线官 |
| 对话纪律严 | 对话官 |
| 有"身体时刻"要求 | 身体官 |
| 禁术语列表非空 | 术语官 |

### 7.3 输出

```json
{
  "score": 0,
  "light": "green|yellow|red",
  "confidence": 0.0,
  "reasons": [],
  "evidence": [],
  "repair_hint": "",
  "per_dimension_scores": [...],
  "comparison_notes": "...",
  "rejected_highlights": [...]
}
```

### 7.4 阈值与配置

红黄绿阈值由元契约的宽松度声明控制（非全局常量）。各维度权重可由项目配置独立调整（D-13）。

默认：green ≥ 85 / yellow ≥ 65 / red < 65。

---

## 8. 上下文组装与提示词预编译

### 8.1 4 阶段编译流水线（D-18）

```
┌──────────────────────────────────────────────────┐
│              Prompt Compiler                      │
│                                                   │
│  Stage 1: Context Assembler                      │
│    - 加载 Shot 上下文（前文窗口、人物在场、场景）│
│    - 查询相关 Fact Anchors (SQL + 向量)           │
│    - 查询 Motif Tracker 当前状态                  │
│                                                   │
│  Stage 2: Persona Lens Applicator                │
│    - 加载写手人格模板                             │
│    - 对静态缓存组件加权重组                       │
│                                                   │
│  Stage 3: Cache Resolver                         │
│    - 分离静态/动态组件                            │
│    - 静态部分使用缓存引用                         │
│    - 动态部分实时装配                             │
│                                                   │
│  Stage 4: Final Assembly                         │
│    - 拼接所有组件                                 │
│    - Token 预算检查（如超出则压缩动态部分）       │
│    - 输出最终 prompt                              │
└──────────────────────────────────────────────────┘
```

### 8.2 Anthropic Prompt Caching 集成

- **Breakpoint 1**：元契约（静态，跨 Shot 不变）→ 缓存前缀
- **Breakpoint 2**：角色声音配置（半静态）→ 缓存中点
- **Breakpoint 3**：Shot 上下文 + 事实锚点 → 动态后缀

预期 ~60% tokens 可缓存。

### 8.3 缓存策略

| 组件 | 类型 | 更新频率 | 缓存策略 |
|------|------|---------|---------|
| Meta-Contracts（硬边界） | 静态 | 每 Act 手动修改 | 永久缓存（Per-Act） |
| Meta-Contracts（软约束） | 静态 | 每 Act 手动修改 | 永久缓存（Per-Act） |
| Character Voice Profiles | 半静态 | Voice calibration 后不变 | 永久缓存（Per-Character） |
| Anti-Samples（手动） | 半静态 | 人类修改时更新 | 缓存至手动更新 |
| Anti-Samples（红灯） | 动态 | 每 Shot 可能更新 | 不缓存 |
| Fact Anchors | 动态 | 每 Shot 可能更新 | 不缓存 |
| Previous Shots Context | 动态 | each Shot 不同 | 不缓存 |
| Motif Tracker 状态 | 动态 | 每 Shot 更新 | 不缓存 |
| Persona Lens Template | 静态 | 配置级 | 永久缓存 |

### 8.4 Token 预算

- **硬预算**：单 Shot prompt ≤ 8k tokens
- **软预算**：目标 6k tokens，超出时压缩优先级：前文摘要 > positive samples > 反例 > 人格加权指示 > 硬边界
- **不压缩**：硬边界、anti_reveal、当前 Shot 契约、事实锚点

### 8.5 加载顺序 (recency effect)

```
1. 前文正文（叙事连续性）— N-1/N-2 全文 + N-3~N-5 摘要 + Scene Start 全文
2. 人物状态快照 + 意象任务（事实约束）
3. Shot 契约（目标）
4. voice samples（风格参照）
5. 反例提醒（最后一秒制动器）—— 最多 5 对具体样本对
```

---

## 9. 存储模型

### 9.1 核心表

数据库为 **38 张业务表 + `_schema_meta` 元表**（Schema v15）。Schema v8 引入三棵树 4 表；Schema v9 引入 L0 全书宪法表；Schema v10 引入 L0.5 卷部节奏表；Schema v12 引入风格偏好学习表；Schema v13 引入反契约沙盒表；Schema v14 引入 `unexpected_value` 意外价值评审维度；Schema v15 引入 `write_polish` 精修 revision 与 `polish` 模型审计 phase。CREATIVE-3 属于运行时评审策略变更：留白 shot 使用 `creative_score` 加权选稿，无新增业务表。

```text
projects                      -- InkFlow 项目索引
writing_book_constitutions    -- L0 全书宪法（ARCH-4）
writing_project_structure     -- 项目结构定义（MNU + layers + human_confirm_layer）
writing_meta_contract         -- 元契约（十子类）
writing_meta_contract_revisions -- 契约修订审计
writing_project_config        -- 项目专属配置
writing_writer_profiles       -- 写手配置（voice_samples + anti_samples + temperature）
writing_jury_config           -- 裁判配置（基础裁判权重 + 动态裁判激活 + 阈值覆盖）
writing_motif_definitions     -- 意象定义 + 频率计划
writing_run_snapshots         -- run 契约快照 + config hash
writing_shots                 -- Shot 状态与当前 revision 指针
writing_sessions              -- 写作 session 记录（含活跃状态）
writing_session_checkpoints   -- 检查点
writing_shot_contracts        -- Shot 级契约（继承链 + 版本）
shot_revisions                -- 正文唯一真相源
writing_drafts                -- 赛马候选稿
writing_shot_prompts          -- Shot 级完整提示词（预编译）
writing_context_snaps         -- 上下文快照（版本控制 + 恢复校验）
writing_fact_anchors          -- 事实锚点（P0 已实现 3 类，设计目标 9 类）
writing_motif_instances       -- 意象实例追踪
writing_motif_tracker         -- 意象密度追踪状态
writing_jury_scores           -- 裁判评分记录（含 suspense_effectiveness / unexpected_value）
writing_repair_audit          -- repair 审计日志
writing_exception_events      -- 异常事件
writing_deviation_notes       -- 偏差记录
writing_reference_pool        -- 参考样本池（正反面 + 标注）
model_attempts                -- 模型调用审计
writing_architect_gates       -- 架构师 gate 记录
writing_outline_evaluations   -- 大纲评估记录
writing_information_gaps      -- D-25 信息差生命周期追踪
writing_chapter_rhythms       -- L1 章级节奏
writing_volume_rhythms        -- L0.5 卷部节奏
writing_style_preferences     -- 风格偏好学习
writing_anti_contract_reviews -- 反契约沙盒裁决

-- Schema v8 新增（三棵树架构 ARCH-12）
tree_nodes                    -- 三棵树骨架（tree_type='contract'/'story'/'execution'）
contract_versions             -- 契约树正文（版本化）
story_content                 -- 故事树正文（追加式）
execution_records             -- 执行树正文（per-run）
```

### 9.2 正文版本规则

- 绿灯/黄灯 winner → `shot_revisions(status='current', operation='write_generate')`
- 留白 shot winner → Jury 保留逐维原始分，同时使用 `creative_score` 提高 `unexpected_value` 权重选稿
- winner 后处理精修 → `shot_revisions(operation='write_polish', parent_revision_id=<winner_revision_id>)`，只有通过保守 gate 且有实质显示变化才写入；原 winner revision 保留为父版本
- 红灯占位 → `shot_revisions(status='current', operation='write_placeholder', placeholder_type='best_failed_candidate|redo_placeholder|permanent_red')`
- AI 修红/修黄 → `shot_revisions(status='current', operation='write_repair')`，旧 current 进入历史
- 所有 revision 必须记录 `parent_revision_id`、`run_id`、`contract_id`、`text_hash_normalized`

### 9.3 8层层级与复合 shot_id

继承自 DeepStory 8层金字塔设计（详见 `docs/design-8layer-hierarchy.md`）。

| 层级 | 中文名 | 英文代码 | 示例 |
|------|--------|----------|------|
| L0 | 全书 | work | 《分流》 |
| L1 | 部 | part | (折叠) |
| L2 | 卷 | volume | v01 |
| L3 | 弧 | arc | (折叠) |
| L4 | 章 | chapter | c02 |
| L5 | 节 | section | s03 ← writing_shots 的行 |
| L6 | 场景 | scene | (未来扩展) |
| L7 | 自然段 | para | 输出单元 |

**复合 shot_id 格式**: `{volume}.{chapter}.s{section}` = `v01.c02.s03`

- `layer_key` = `v01.c02`（卷+章）
- `shot_id` = `layer_key + ".s" + zfill(shot_index, 2)` = `v01.c02.s03`
- 排序：字典序即可（零填充保证）

### 9.4 三棵树架构（Schema v8 引入，当前 Schema v15，ARCH-12/13）

> 完整设计见 `docs/design-3tree-architecture.md`

InkFlow 的数据库是**唯一真相源**。为支撑 AI 架构师多层治理，数据库由 **3 棵树** 构成，每棵树都遵循 8 层标准金字塔（空则占位），共用 **4 张数据库表**。这 4 表在 Schema v8 引入；当前 Schema v15 总计 38 张业务表 + `_schema_meta` 元表：

> **三棵树是索引，不是正文。**
> 正文唯一真相源是 `shot_revisions.text`。

| 树 | 回答 | 特征 | 内容表 | 正文关系 |
|----|------|------|--------|---------|
| **契约树** (Contract Tree) | "应该怎么写" | 版本化，设计时，跨 run 稳定 | `contract_versions` | 存契约约束，不存正文 |
| **故事树** (Story Tree) | "这本书里有什么" | 追加式，角色状态/伏笔/时间线 | `story_content` | 存世界状态，不存正文 |
| **执行树** (Execution Tree) | "这次 run 干了什么" | per-run，每次重新生成 | `execution_records` | 存执行元数据 + 指向 `shot_revisions` 的指针 |

**骨架表**（三棵树共用）：`tree_nodes`

```
tree_nodes (骨架)
├── tree_type='contract'  → contract_versions (契约约束)
├── tree_type='story'     → story_content (世界状态)
└── tree_type='execution' → execution_records (元数据 + revision_id → shot_revisions)
                                                 ↑
                         正文唯一真相源: shot_revisions.text
```

**正文真相源规则**：

| 状态 | 正文 = | 条件 |
|------|--------|------|
| 未封版 | `shot_revisions` 中 `revision_sequence` **最大**的行 | 最后一次生成的版本 |
| 已封版 | `shot_revisions` 中 `is_current=1` 的行 | 封版时锁定的版本 |

`shot_revisions.is_current` 是**封版标记**——仅在封版时设置一次。`writing_shots.current_revision_id` 始终指向最新 revision。执行树通过 `execution_records.revision_id` (FK → `shot_revisions`) 提供访问路径。

---

## 10. 跨 Shot 叙事一致性（D-22）

### 10.1 五层检查

| 层级 | 检查内容 | 检查方式 | 检查时机 |
|------|---------|---------|---------|
| L1: 事实连续性 | 人物位置、物品状态、时间推进 | Fact Anchor 系统自动验证 | Gate 2 中 |
| L2: 视角连续性 | POV 相邻切换合理 | Jury 维度 3 | Jury scoring |
| L3: 叙事节奏 | 事件密度符合节奏曲线 | Jury 维度 2 | Jury scoring |
| L4: 主题连贯 | 相邻 Shot 服务同一场景主题意图 | Scene Composition Check | Scene 完成后 |
| L5: 意图漂移 | 3+ 连续 Shot 从核心理念偏离 | Intent Drift Detection | 每 5 Shot |

### 10.2 Continuity Context Window

```
Previous Shots Context Window:
├── Previous Shot (N-1): 全文
├── Shot N-2: 全文
├── Shot N-3: 摘要（200 tokens）
├── Shot N-4: 摘要（200 tokens）
├── Shot N-5: 摘要（200 tokens）
└── Scene Start: 场景开启 Shot 全文（作为参考锚点）
```

### 10.3 Scene Composition Check

Scene 的全部 Shot 完成后触发。合并全文 → 检查：场景弧线 / 视角切换叙事理由 / 对话推进 / 意象分布 / 叙事漏洞。输出 Scene Cohesion Score (0-10)。**诊断工具，不阻塞生产**。

### 10.4 Intent Drift Detection

每 5 Shot 触发。对比最近 5 个 Shot 的整体叙事姿态与元契约 `identity.thematic_core`。若偏离 → 写入 `intent_drift_alert`。**不自动阻止生产**——在 Scope 投影中告警。

### 10.5 跨 Shot 引用追踪

绿灯 Shot 分析正文中是否有对前文的跨 Shot 引用（call-back / 呼应）。如有 → 记录 `cross_shot_reference`。用于全书后的叙事结构分析。

---

## 11. Motif 密度追踪（D-20）

### 11.1 Motif 定义与注册

```json
{
  "motif_id": "m_act1_rain",
  "project_id": "qianlong",
  "name": "雨",
  "category": "weather",
  "description": "雨水作为压抑和清洗的双重意象",
  "planned_density": {"per_act": 12, "per_chapter": 3, "per_shot": 1},
  "variants": ["雨", "雨水", "下雨", "雨声", "细雨", "暴雨"],
  "current_count": 4,
  "last_used_shot": "act1_ch2_s20",
  "min_shot_gap": 3,
  "evolution_phase": "establishment"
}
```

**注册来源**：Setup 人类手动 / AI 从导入文本逆向提取 / 模板预设 / 写作过程中人类新增。

### 11.2 Motif Density Tracker

每个 Act 维护一个 Density Tracker，实时状态五档：

| 状态 | 含义 |
|------|------|
| 🟢 green | 频率按计划，偏差 ≤ ±1 |
| 🟡 yellow | 轻微超频/欠频，偏差 ±2~3 |
| 🔵 blue | 过度使用，偏差 ≥ +4 |
| 🔴 red | 严重欠频，偏差 ≤ -4 |
| ⬜ gray | 尚未进入活跃期 |

### 11.3 Motif Task 自动生成

赛车场经理在每个 Shot 编译时自动检查 Tracker 生成 Motif Task：

- **Required**：red 状态，必须在本 Shot 出现
- **Suggested**：green→yellow，按计划应出现但不强制
- **Forbidden**：blue 或距上次 < min_shot_gap
- **Allowed**：不限制但不鼓励

### 11.4 4 Phase Motif Evolution

- Phase 1 **establishment**：首次引入，建立感知识别
- Phase 2 **variation**：变体出现，形成 pattern
- Phase 3 **subversion**：预期被打破，产生意义转折
- Phase 4 **resolution**：意象完成叙事功能

---

## 12. 多项目管理（D-10 / D-16）

### 12.1 Universe → Project → Act 三级模型

```
Universe (1) ──< Project (N) ──< Act (N)
```

- **Universe**：共享世界观容器。含宇宙级事实锚点和共享人物池。
- **Project**：独立写作任务。继承 Universe 锚点，追加 Project 级锚点。
- **Act**：分卷/分部。继承 Project + Universe 锚点。

项目可不属于任何 Universe（独立作品），此时 Project 自己是事实锚点根。

### 12.2 元契约三层继承

```
Universe 级 — 世界观规则、禁忌、硬边界
    ↓ 覆盖 / 追加
Project 级 — 主题、体裁、核心意象、叙事声音
    ↓ 覆盖 / 追加
Act 级 — 节奏曲线、意象密度预算、POV 权重
```

继承规则：子级默认继承 → 可覆盖（只影响当前及后续层级）→ 覆盖不反向传播。冲突检测：Act 级覆盖与 Universe 级硬边界冲突 → 架构师警告并请求人类确认。

### 12.3 事实锚点跨项目同步

Universe 级锚点修改 → 所有 Project 收到"事实变更通知" → 人类 accept / override / defer。已写 Shot 不回写，下游未生成 Shot 使用更新后锚点。

### 12.4 批量导入与契约逆向提取（D-16）

支持 `.txt` / `.md` / `.docx` 导入已有作品。逆向工程提取元契约分置信度：
- **高（>70%）**：硬边界、已揭露信息、角色列表 → 自动纳入
- **中（40-70%）**：叙事声音策略、意象系统 → 人类确认
- **低（<40%）**：潜在反例、隐含主题 → 建议方式呈现

**从停更点继续**：导入部分完成稿 → 扫描已写 Shot 提取事实锚点 → 从下一个未写 Shot 开始。

---

## 13. 状态机与崩溃恢复

### 13.1 Shot 写作状态

> **权威冻结**：Shot 持久化状态以 `implementation-contract-v0.md §2.2` 的 CHECK 约束为准。以下为运行时处理阶段（非 DB 状态），用于赛车场经理的编排逻辑。

运行时处理阶段（非 DB 状态）：
assembling → writing → l0_checking → contract1_checking → jury_scoring → winner_selected → mutating_final_text → final_gate_checking → persisting_revision → extracting_fact_anchors → running_scene_composition

对应的 DB 状态（implementation-contract-v0.md §2.2）：
pending → generating → gate1_check → jury_scoring → final_gate → done_green / done_yellow / placeholder → redo → done_red_permanent

所有外部模型调用和 DB 写入必须有 `attempt_id` / `idempotency_key`。

### 13.2 检查点与恢复（D-14）

**检查点粒度**：每个 Shot 完成后写入——含所有候选文本、jury 评分、Gate 结果、winner 正文、事实锚点、motif tracker 状态。

**自动恢复**：
```
ink run  → 检测未完成 Session → 提示 "发现未完成 Session #42 (Act1/Ch3, 已完成 17/20 Shots)。继续？"
```

**手动恢复**：
```bash
ink resume <session_id>      # 恢复指定 Session
ink resume --last             # 恢复最近中断的 Session
ink sessions list             # 查看所有未完成 Session
ink sessions abort <id>       # 放弃 Session，已生成文本保留
```

**异常分类**：

| 异常类型 | 恢复行为 |
|---------|---------|
| API 临时错误（429, 503） | 指数退避重试（3 次）→ 耗尽后暂停 Session |
| API 永久错误（400, 401） | 立即暂停，不重试 |
| 单 Shot 全失败 | best-failed placeholder → smart-redo 3 级升级 |
| 模型输出截断 | 自动扩展 token 限制或要求写手压缩 |
| 进程崩溃 | 从最近检查点恢复 |
| 网络中断 | 等待重连，当前 Shot 重试 |
| 磁盘满 | 拒绝开始新 Shot，保留已有数据 |

---

## 14. 后处理

全书生产完成后进入自动后处理：

### 14.1 Repair 四层框架（D-3）

```
L1 零改动 — 自动重跑（writer 执行失败/文风不稳/上下文漂移）
L2 风格级 — AI 微调提示词可选附带原文重跑
L3 结构级 — AI 修改 Shot 约束（非硬边界），按章批量提交人类确认
L4 方向级 — 可能触碰硬边界或跨章结构性重规划，必须人类确认
```

升级规则：
- L1 连续 3 次失败 → 自动升级到 L2
- L2 连续 3 次失败 → 自动升级到 L3（含自动暂停章节后续 Shot）
- L3 连续 2 次失败 → 自动升级到 L4
- ⭐⭐⭐ 稳定性约束触碰 → 直接升级到 L4

硬规则安全网：
- 连续红灯升级：同一 Shot N 次红灯，自动升级 repair 层级
- ⭐⭐⭐ 触碰升级：L3 涉及 hard_boundaries / anti_reveal，立即升级 L4
- 连锁影响升级：L3 变更影响 > 3 个已执行 Shot，自动升级 L4

### 14.2 Post-processing Pipeline

1. AI 架构师诊断每个红灯 Shot（写手执行失败 vs 契约问题）。
2. 按四层框架分级处理。
3. L1 静默重跑。L3 按章批量确认。L4 必须人类确认。
4. 每次 repair 写入 `writing_repair_audit`。
5. 重跑写手赛马 + 裁判 + 门控，生成 `write_repair` revision。
6. AI 对黄灯 Shot 做文学性和连续性优化。
7. Chisel scan/report 对全书做二次校准。
8. 人类集中查看投影报告，做最终裁决。

---

## 15. Scope 投影报告（D-12）

### 15.1 用户交互

每个 Scope 完成后，人类在终端看到**交互式分层视图**（D-8）：

```
Layer 1: 摘要卡片
┌─────────────────────────────────────────────────────────────┐
│ Act 1 / Ch 3 / Run Scope 2                                  │
│ 12 Shots: 9 绿 ●  2 黄 ●  1 红 ●                           │
│ Avg jury score: 7.2 (-0.3 vs prev scope)                    │
│ Motif density: 1.8 avg (cap 2.0)                            │
│ Voice consistency: 92%                                       │
└─────────────────────────────────────────────────────────────┘

Layer 2: Shot 列表（展开 Layer 1）
┌──┬──────┬───────┬───────────────────────────────────────────┐
│37│绿 ● A│ 7.8   │ Alice 推开废弃工厂的铁门，                │
│38│绿 ● A│ 8.1   │ 她看见墙角有一组新鲜的足迹                │
│39│红 ●perm│ 5.2  │ [PLACEHOLDER: fact 冲突]                 │
│40│黄 ● B│ 6.9   │ 对讲机突然发出噪音…                      │
└──┴──────┴───────┴────────────────────────────────────────────────┘

Layer 3: Shot 详情（展开单个 Shot — 完整正文 + radar + 评语 + 操作）
```

### 15.2 6 种人类操作

| 操作 | 含义 |
|------|------|
| `approve` | 显式确认该 Shot 无需修改 |
| `fix "…"` | 向架构师描述问题 → 架构师重写 |
| `redo` | 用不同 writer 配置重新生成 |
| `flag` | 标记需后续注意（不立即修改） |
| `edit context` | 修改契约上下文（不直接改文本） |
| `lock` | 锁定不被后续 repair 修改 |

**文本编辑全部通过 AI 架构师中介（D-8）**——人类描述问题，架构师解析为修正指令 → 启动 redo → 契约校验 + Gate 验证 → 呈现新文本。确保修改后文本保持作者声音一致性。

---

## 16. 项目专属配置（D-13）

### 16.1 三层配置

```
Default Config (Chisel 内置，5 个预设)
    ↓ 覆盖
Project Config (config.yaml)
    ↓ 覆盖
Act Config (仅节奏曲线和 jury 权重)
```

**5 个内置预设**：

| 预设 | 适用 | 核心调整 |
|------|------|---------|
| `literary` | 文学小说 | 声音官+主题官权重 ↑，节奏权重 ↓ |
| `scifi` | 科幻 | 术语官启用，世界观权重 ↑ |
| `mystery` | 悬疑 | 伏笔官启用，对话权重 ↑ |
| `web-novel` | 网文/爽文 | 节奏权重 ↑，完整官权重 ↓ |
| `series` | 系列作品 | 衔接官权重 ↑，跨卷一致性检查 |

### 16.2 配置项

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `jury_thresholds` | green≥85, yellow≥65, red<65 | 三色判定阈值 |
| `writer_count` | 2 (auto-select) | 竞赛写手数 |
| `model_tiers.writer` | fast | 写手模型层 |
| `model_tiers.jury` | sonnet | 裁判模型层 |
| `model_tiers.rewriter` | opus | 重写模型层 |
| `motif_density_default` | `{per_chapter: 3, per_shot: 2}` | 默认密度上限 |
| `max_token` | 每 Shot 6k tokens | Shot 最大输出长度 |

### 16.3 配置管理

主路径：`config.yaml`。CLI 覆盖：`ink run "分流" --config jury.thresholds.green=8 --config writer_count=4`

---

## 17. 元契约可审计性（D-23）

### 17.1 条款追踪

每条元契约条款有唯一 ID：

```json
{
  "contract_id": "mc_qianlong_v36_h1",
  "section": "hard_boundaries",
  "index": 1,
  "text": "Alice 不知道 Ben 的过去…",
  "violation_count": 1,
  "violation_history": [
    {"shot_id": "act1_ch3_s39", "jury_dimension": 8, "severity": "major", "resolution": "smart-redo L1 → resolved"}
  ]
}
```

**引用链**：`Meta-Contract → Jury Dimension 8 Score → Gate 2 Decision → Shot Status`

任何红灯 Shot 可向上追溯到违反的具体条款 → 哪个 jury 维度 → 哪个候选文本的哪段内容。

### 17.2 契约仪表盘

`ink contracts <project>` ——四维视图：
- **条款维度**：每条 violation 计数 + 最近 3 次违规
- **声音维度**：每个 POV 角色 voice drift 趋势
- **Motif 维度**：每个 Motif 密度 vs 计划对比
- **违规维度**：按 Act 聚合的违规热力图

### 17.3 契约演化日志

`contract_changelog` 记录每次契约修改：谁修改、什么字段、旧值、新值、人类是否确认、修改原因、时间戳。

### 17.4 违规模式分析

每 Act 完成后 AI 架构师自动分析：哪些条款被频繁违反 / 哪些 Shot 类型容易违规 / 是否有模式（如某个写手总是触发某类违规）。

---

## 18. AI 架构师能力边界（D-24）

### 18.1 职责清单

| # | 职责 | 触发时机 | 模型 | 自治级别 |
|---|------|---------|------|:---:|
| 1 | Setup 对话 | `ink setup` | Opus | L3 人类触发 |
| 2 | 元契约草案生成 | Setup | Opus | L3 人类触发 |
| 3 | Voice Calibration | Setup / 人类请求 | Sonnet | L2 建议+确认 |
| 4 | Chapter Planning | `ink plan` | Opus | L2 建议+确认 |
| 5 | Motif Task 生成 | Prompt 编译 | 规则引擎 | L0 全自动 |
| 6 | Prompt 编译与缓存 | 每 Shot | 引擎 | L0 全自动 |
| 7 | Smart-Redo 决策 | Gate 2 红灯 | Sonnet→Opus | L1 自动+通知 |
| 8 | Scope 投影报告 | Scope 完成 | Sonnet | L0 全自动 |
| 9 | 元契约校准建议 | 首个 Act 完成 | Opus | L2 建议+确认 |
| 10 | Intent Drift 检测 | 每 5 Shot | Sonnet | L0 全自动 |
| 11 | 契约违规模式分析 | 每 Act 完成 | Sonnet | L0 全自动 |
| 12 | 人类修改请求处理 | 人类请求 | Opus | L3 人类触发 |
| 13 | 跨项目 clone/migrate | 人类请求 | Sonnet | L2 建议+确认 |
| 14 | 升级项目契约 | 人类请求 | Sonnet | L2 建议+确认 |

### 18.2 禁止事项

- 自主修改人类确认过的硬边界——只能建议
- 自主替换人类 approved 的 Shot——除非人类显式 unlock
- 自主创建新角色、新 Motif、新反例——可建议但需人类确认
- 自主修改项目配置

---

## 19. 模板复用

系列化项目创建模板，填槽实例化：

```bash
ink setup "背锅侠_001" --template "背锅侠_发动机_现代本土卷"
```

AI 架构师加载模板 → 填充 slot → 编译全链契约。人类只需确认填槽是否正确。

跨项目 clone：
```bash
ink clone "分流" --as "分流_英文版"   # 复制元契约 → interactive override → 重新编译
```

---

## 20. CLI

```bash
# 前置沟通与契约落库
ink setup "分流"

# 系列化模板复用 / 跨项目 clone
ink setup "背锅侠_001" --template "背锅侠_发动机_现代本土卷"
ink clone "分流" --as "分流_英文版"

# 全自动生产
ink run "分流" --chapter v01.c01
ink run "分流" --volume 1
ink run "分流" --from v01.c01 --to v01.c32

# 恢复中断
ink run "分流" --resume
ink resume <session_id>
ink resume --last
ink sessions list
ink sessions abort <id>

# 查看状态与报告
ink status "分流"
ink report "分流"                   # (Phase 2)
ink contracts "分流"              # 契约仪表盘

# 全书完成后的 AI 自动修补
ink repair "分流" --red
ink repair "分流" --yellow

# 硬边界紧急逃生舱
ink revise-boundary "分流" --layer meta   # (Phase 2)

# 声音校准
ink voice-calibrate "分流"

# Chisel 二次校准
chisel scan "分流" --depth standard
chisel report "分流"
chisel batch-fix "分流"
chisel export "分流" -o "分流_终版.md"
```

---

## 21. 测试要求

必须补齐：

- `test_write_contract_compiler.py` — 契约编译链（结构识别 + 继承 + 冲突检测）
- `test_write_contract_lifecycle.py` — 契约生命周期（状态转换 + 修约 + 传播 + 升级路径 D-11）
- `test_write_context_assembler.py` — 上下文组装（预编译提示词加载 + 顺序 + 版本控制 + 缓存命中 D-18）
- `test_write_jury.py` — 裁判团（自动激活 + 阈值 + 3-phase 评分 D-21）
- `test_write_pipeline_recovery.py` — 状态机恢复幂等 + 检查点 D-14
- `test_write_storage.py` — 存储模型 CRUD + 9 类事实锚点提取 D-19
- `test_write_cli.py` — CLI 命令
- `test_write_boundary_revision.py` — 硬边界逃生舱 D-4
- `test_write_writer_personas.py` — 4 写手人格差异化 D-17
- `test_write_motif_tracker.py` — Motif 密度追踪 + 4 phase evolution D-20
- `test_write_cross_shot.py` — 跨 Shot 叙事一致性五层检查 D-22
- `test_write_contract_audit.py` — 元契约可审计性 D-23
- `test_write_anti_samples.py` — 反例系统（5 来源 + 降温 + voice drift）D-15
- `test_write_scope_report.py` — Scope 投影报告三层视图 D-12
- `test_write_multi_project.py` — 多项目管理 Universe/Project/Act D-10
- `test_write_import.py` — 批量导入 + 契约逆向提取 D-16

最低 E2E replay：

```text
import finalized book
→ write setup creates meta_contract + compiles full contract chain
→ human reviews inheritance tree, confirms
→ write run full chapter
→ 2-4 writer race with persona-differentiated prompts
→ 3-phase jury scoring (independent → compare → output)
→ green/yellow revisions become current, 9-type fact anchors auto-extracted
→ red best-failed-candidate placeholder + smart-redo 3-level escalation
→ checkpoint written after each shot
→ scope projection report generated from DB (3-layer interactive)
→ crash recovery via --resume works
→ write repair diagnoses red, applies D-3 four-layer repair
→ each repair writes writing_repair_audit
→ scene composition check runs on scene completion
→ intent drift detection runs every 5 shots
→ contract dashboard shows violation traceability
→ scan/report can continue
```

---

## 22. 悬疑引擎（D-25）

> 完整设计文档：`docs/suspense-engine.md`
> 设计决策：9 位专家评估（2026-06-22）
> 状态：Phase 1 实施中

### 22.1 核心本体论：三个不对称

悬疑的本质不是"表面修辞特征"，而是**三个不对称在读者心智中产生的张力**：

| 不对称 | 定义 | 检测方式 |
|--------|------|---------|
| **信息不对称** | 读者知道什么 vs 角色知道什么 | 结构层追踪（`writing_information_gaps`） |
| **时间不对称** | 读者预期什么时间发生 vs 实际发生时间 | 机械层正则（章末钩子、解释句检测） |
| **后果不对称** | 读者预期的后果严重性 vs 角色感知的严重性 | 机械层 + 结构层（伤害预演、数字体温） |

6 个表面特征（章末钩子、信息差、伤害预演、数字体温、解释句禁令、预埋密度）是三个不对称的**局部投影**，不是悬疑本身。

### 22.2 架构：Jury 第四维度 + 悬疑蓝图

不新建独立 Stage 2 Extractor。悬疑评估通过扩展现有系统实现：

- **Jury 第四维度**：D-25 阶段从 3 模型 × 3 维度 = 9 分扩展为 3 模型 × 4 维度 = 12 分，新增 `suspense_effectiveness` 维度，让赛马自然筛选出更有悬疑感的文本。当前实现已在 CREATIVE-1 继续扩展到默认 3 模型 × 5 维度，新增 `unexpected_value`。
- **悬疑蓝图**：Shot-level 悬疑配置，在 `contract-draft.yaml` 中定义每章的 `tension_target`、`info_gap_action`、`hook_type`。
- **信息差追踪**：新增 `writing_information_gaps` 表，追踪信息差的完整生命周期（pending → active → reinforced → revealed → resolved → new gap）。

### 22.3 悬疑预设

5 个命名预设，定义 α/β/γ 权重（信息不对称 / 时间不对称 / 后果不对称）：

| 预设 | α | β | γ | 适用 |
|------|:---:|:---:|:---:|------|
| `literary_tension` | 0.3 | 0.4 | 0.3 | 文学小说 |
| `institutional_suspense` | 0.5 | 0.3 | 0.2 | 制度悬疑 |
| `psychological_thriller` | 0.2 | 0.3 | 0.5 | 心理惊悚 |
| `whodunit` | 0.6 | 0.2 | 0.2 | 本格推理 |
| `slow_burn` | 0.4 | 0.4 | 0.2 | 慢燃悬疑 |

### 22.4 评估分层

| 层级 | 检查项 | 方式 | LLM 调用 |
|------|--------|------|:---:|
| L0 机械层 | 章末钩子类型、数字体温、解释句检测 | 正则/规则 | 0 |
| L1 结构层 | 信息差效果、悬疑密度、张力曲线 | Jury `suspense_effectiveness` 维度 | 与现有评分合并 |

### 22.5 工程可靠性

- **全局重试预算**：每个 Shot 最多 8 次 LLM 调用（Writer Race 2 + Redo 2 + Smart-Redo 4 = 8）
- **熔断器**：同一失败类型连续 3 次 → 熔断，标记 `done_red_permanent`
- **章末钩子**：不达标不重写，而是注入下一个 Shot 的上下文，让下一个 Shot 的写手自然承接

### 22.6 实施计划

| Phase | 内容 | 新增表 |
|:---:|------|:---:|
| 1 | Jury 第四维度 + 悬疑蓝图 + 全局重试预算 + 熔断器 | 0 |
| 2 | 信息差生命周期追踪 + 悬疑预设系统 | 1 (`writing_information_gaps`) |
| 3 | 悬疑评估基准 + 反例 schema 扩展 | 0 |
