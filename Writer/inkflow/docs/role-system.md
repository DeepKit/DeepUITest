# 墨韵 (InkFlow) v3.6 — 角色体系与生产边界

> Status: 设计文档 v3.6，非代码实现
> Date: 2026-06-15
> Last updated: 2026-06-15 (D-1~D-24 全部决策落地)
> 本文是 Chisel Write 写作角色与权限边界的权威口径。
> 决策来源：`docs/decisions/` 下 D-01 至 D-24 全部 24 个 ADR。

---

## 0. 当前 P0 边界（2026-06-17）

P0 只验证《分流》单书闭环：

```text
第 1 章人工样章导入并锁定
  → AI 架构师与人类多轮 setup
  → confirmed 契约
  → 按 shot 生成第 2 章
  → 章后报告
  → 推敲 read-only 导入墨韵 DB
```

角色边界补充：

1. AI 架构师可以提出主题、硬边界、不解之谜、人物声音、结尾策略的候选，但必须经人类确认后才能入契约。
2. 第 1 章 `human_baseline` 是锁定样章；墨韵只能读取，不得自动改写。
3. 写作运行期不因成本暂停，不做成本确认门。
4. 推敲系统只读墨韵 DB 并复制导入；不得回写墨韵 DB。

## 1. 核心定位

Chisel Write 是全自动文学文本生产引擎。

它不是实时写作插件，也不是每章都需要人类确认的协作编辑器。人类在前置阶段与 AI 架构师沟通目标；AI 架构师把目标转为契约并落库；随后生产线按契约快照自动写完整部小说或指定范围。

---

## 2. 角色总表

| 角色 | 类型 | 权限 | 不允许做什么 |
|------|------|------|--------------|
| 出品人 | 人类 | 前置方向、最终集中处理、必要时重设契约 | 生产期逐 Shot 干预 |
| AI 架构师 | AI | 编译全链契约、解释人类意图、标记创意空间、诊断红灯原因、元契约校准建议、Intent Drift 检测 | `ink run` 期间自动改契约；自主修改人类确认过的硬边界 |
| 赛车场经理 | Python | 锁定契约快照、调度生产、状态机、恢复/检查点、落库、提取事实锚点、Motif 密度追踪 | 改写契约语义 |
| 写手池 | AI | 按编译好的差异化提示词（按人格加权）生成候选正文；附带自评注释 | 改事实、改人物状态、输出正文外附注 |
| 9 裁判团 | AI | 按项目专属配置 3-phase 评分（独立→比较→输出）、灯色、失败原因、偏差记录、相对排序+绝对分 | 中断生产请求人类决策 |
| Chisel 校准链 | Python + AI | 全书后 scan/report/fix | 作为生产期拦截器 |

---

## 3. 人类边界

人类只在两个阶段介入：

1. `ink setup`：与 AI 架构师沟通目标 → AI 架构师编译全链契约 → 人类审核继承摘要 → 确认落库。
   - 交互采用**混合式**（D-7）：高创造力字段（主题、硬边界、核心意象等 7 项）用访谈对话；低创造力字段（反例集合、节奏曲线、ASTO 坐标等 8 项）由 AI 推断+一次性呈现。
   - 提取采用**渐进式**（D-7）：Setup 只提取核心字段 → 第一卷完成后 Chisel scan 反向提取隐含契约 → 人类确认/修正 → 后续 Act 获得更精准约束。

2. 全书生产与 AI repair 完成后：集中处理红灯、黄灯和 Chisel findings。

生产期不打断人类。章末报告、close_call、黄灯、红灯都只进入报告和修补队列，不触发即时人工确认。

人类可以在任意节点注入修正，AI 架构师自动向下重编译。

### 3.1 运行时可见性（D-8）

- **粒度**：Shot 级汇总——每个 Shot 完成后一次性呈现 winner 正文 + jury scores + 裁判评语 + 被拒绝候选亮点。
- **干预模式**：完全无人干预——流水线一次性跑完整个 Run Scope。人类只在 Scope 完成后查看投影报告。
- **文本编辑**：通过 AI 架构师中介——人类描述问题（自然语言），架构师解析为修正指令 → 启动针对性 redo → 呈现新文本。不直接编辑 AI 生成文本。

---

## 4. AI 架构师

AI 架构师是契约编译核心。职责不是"生成创意"——而是"把人类创意转成可执行的约束链"。

### 4.1 职责清单与自治级别（D-24）

| # | 职责 | 触发时机 | 模型 | 自治级别 | 人类确认 |
|---|------|---------|------|:---:|---------|
| 1 | Setup 对话（核心理念提取） | `ink setup` | Opus | L3 人类触发 | ✓ |
| 2 | 元契约草案生成 | Setup | Opus | L3 人类触发 | ✓ 逐条 |
| 3 | Voice Calibration | Setup / 人类请求 | Sonnet | L2 建议+确认 | ✓ |
| 4 | Chapter Planning | `ink plan` | Opus | L2 建议+确认 | ✓ |
| 5 | Motif Task 生成（每 Shot） | Prompt 编译 | 规则引擎 | L0 全自动 | ✗ |
| 6 | Prompt 编译与缓存管理 | 每 Shot | 引擎 | L0 全自动 | ✗ |
| 7 | Smart-Redo 决策 | Gate 2 红灯 | Sonnet→Opus | L1 自动+通知 | ✗ |
| 8 | Scope 投影报告生成 | Scope 完成 | Sonnet | L0 全自动 | ✗ |
| 9 | 元契约校准建议 | 首个 Act 完成 | Opus | L2 建议+确认 | ✓ |
| 10 | Intent Drift 检测 | 每 5 Shot | Sonnet | L0 全自动 | ✗ |
| 11 | 契约违规模式分析 | 每 Act 完成 | Sonnet | L0 全自动 | ✗ |
| 12 | 人类修改请求处理 | 人类请求 | Opus | L3 人类触发 | ✓ |
| 13 | 跨项目克隆/迁移 | 人类请求 | Sonnet | L2 建议+确认 | ✓ |
| 14 | 升级项目契约 | 人类请求 | Sonnet | L2 建议+确认 | ✓ |

### 4.2 禁止事项

- 自主修改人类确认过的硬边界——只能建议，不能修改
- 自主替换人类 approved 的 Shot——除非人类显式 unlock
- 自主创建新角色、新 Motif、新反例——可以建议，但需人类确认
- 自主修改项目配置——配置是人类的地盘

### 4.3 写作指南提取与缺项追问

AI 架构师自动从人类对话和已有 md 文件中提取结构化要素。人类不手动填表。

**通用必填（7 项，缺项由 AI 提出候选，必须经人类确认后入契约）**：

| 字段 | 说明 |
|------|------|
| one_liner | 一句话定义——这本书的核心 |
| genre_position | 它是什么 + 它不是什么（反例比正向定义更重要）|
| core_question | 最高命题——这本书真正要问的问题 |
| constitution | hard_boundaries（≥3 条）+ anti_patterns（≥3 条）|
| structure_outline | 叙事层级 + 到人类确认层的完整大纲 |
| characters | 主线人物：身份 + 核心冲突 + 弧线方向 + 语言特点 |
| style_guide | 叙事视角 + 基础腔调 + 禁止写法（≥3 条）+ 对话纪律 |

**强烈建议（4 项）**：voice_samples / world_rules / core_motifs / unsolved_mysteries

**类型专属追加**：科幻必填"世界观物理规则"，悬疑必填"线索投放表"，历史必填"时代语言约束"等——由类型自适应约束矩阵驱动。

### 4.4 类型自适应约束矩阵

六种类型的约束强度分布——决定 AI 架构师在 setup 阶段追问优先级：

| 维度 | 文学 | 悬疑 | 历史 | 科幻 | 职场 | 系列 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| 世界观 | ★★ | ★★★ | ★★★ | ★★★★★ | ★ | ★★ |
| 人物 | ★★★★ | ★★★★ | ★★★ | ★★★★ | ★★ | ★★★ |
| 结构 | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★★ |
| 主题 | ★★★★★ | ★★★ | ★★★ | ★★★★★ | ★★ | ★★★★ |
| 风格 | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★ |

### 4.5 元契约

从人类对话和写作指南中提取结构化元契约，十子类：

| # | 子类 | 内容 | 稳定性 | 谁可以改 |
|:---:|------|------|:---:|------|
| 1 | identity | 这本书是什么、不是什么 + `thematic_core`（主题内核：全书共享的叙事姿态） | ⭐⭐⭐ | 只有人类 |
| 2 | hard_boundaries | 绝对不能写什么 + `confidence`（高/中/低） | ⭐⭐⭐ | 只有人类 |
| 3 | anti_reveal | 不解之谜保护 + `release_window`（可揭露的窗口范围） | ⭐⭐⭐ | 只有人类 |
| 4 | anti_patterns | 最容易写偏成什么 | ⭐⭐ | 人类可改 |
| 5 | narrative_voice | 叙事声音策略——策略声明 + POV 角色列表（多POV时按角色路由voice） | ⭐⭐ | 人类可改 |
| 6 | style_locks | 语言腔调、句式纪律、对话规则 | ⭐⭐ | 人类可改 |
| 7 | structure_rules | 跨卷/部的结构循环规则 + `emo_state`（每卷/章的目标读者情感状态） | ⭐⭐ | 人类可改，AI按规则实例化 |
| 8 | creative_zones | 哪些区域允许 AI 放开写 | ⭐ | 人类可改 |
| 9 | motif_system | 意象/元素的意义弧线 + `density_policy`（密度上限配置） | ⭐ | 人类可改，AI可重分配 |
| 10 | world_knowledge | 虚拟世界物理规则（科幻/架空必填）| ⭐⭐⭐ | 只有人类 |

### 4.6 编译链

```
Step 1: 识别项目结构（MNU + layer index + human_confirm_layer）
Step 2: 提取硬边界 + anti_reveal
Step 3: 提取意象/元素 → 分配到 shot_context（非章节序号），执行 density_policy 软约束
Step 4: 按卷/部展开 → 卷级专属约束 + primary_pov（多POV项目的当前卷 POV 角色）
Step 5: 按章/场展开 → 章级契约（叙事目标 + 章末读者状态 + emo_state）
Step 6: 按 Shot 展开 → Shot 契约（must_land + anti_write + exit_to + 意象任务 + primary_pov 路由 voice）
Step 7: 全链冲突检测（硬边界 / anti_reveal / exit_to 连续性 / 意象密度硬计数 / 意象互斥对）
Step 8: 编译提示词 + 版本化 + 落库
```

**编译顺序**：anti_write 链先展开，must_land 链后展开。先锁边界再填内容。

### 4.7 层级可折叠

编译链支持可选层级折叠。AI 架构师在结构识别阶段判断：
- 《背锅侠》卷→集：无需"章"层
- 《分流》全书→卷→章→Shot：全层级展开
- 《签》全书→部→场→节：无需"卷"层

折叠规则：两个相邻层级的功能重叠 ≥ 60% → 折叠低层。

### 4.8 POV 角色路由

卷/章级契约新增 `primary_pov` 可选字段：
- 类型：`string`（角色 ID）
- 空值行为：fallback 到全书级 narrative_voice（单 POV 项目无需迁移）

**编译链路由逻辑**：
编译 Shot 提示词时：
- 若当前单元.primary_pov 存在 → 从 Character Writing Guide 取该角色的 voice 配置，覆盖全书级 voice
- 否则 → 使用全书级 narrative_voice

**全书级 narrative_voice 语义**：
从"单一叙事声音"改为"策略声明 + POV 角色列表"。
例如：`{"strategy": "每卷切换主导 POV，但叙述者保持同一观察距离", "povs": ["苏然", "白英", "韩教授", "阿坤"]}`

### 4.9 Universal Contract Header

所有层级契约共享统一头部：

```
contract_id / level / node_key / title / version / status / 
parent_id / child_range / genre / created_by / human_approved / timestamps
```

差异在 body：元契约 body = 10 子类，Shot 契约 body = must_land + anti_write + exit_to + ASTO + voice_phase + 意象任务。

### 4.10 元契约到 Slot 的映射规则

| 元契约子类 | → Slot | 注入方式 |
|------|------|------|
| identity | Writer Identity (L101) | 系统提示词固定层 |
| narrative_voice | Writer Identity (L101) | 合并入叙事声音指令 |
| hard_boundaries | Scene-specific taboos (L505) | 有冲突风险时注入 |
| anti_reveal | Taboos 扩展 (L505) | 匹配到涉及场景时强制注入 |
| world_knowledge | World facts (S07) | 涉及世界观时强制注入 |
| structure_rules | Intent chain (L407) | 编译到卷/部展开逻辑 |
| anti_patterns | Scene anti-examples (L507) | 按场景类型匹配 |
| style_locks | Style iron rules (L503) | 全书固定，每 Shot 注入 |
| motif_system | Scene best examples (L509) | 关联到场景时注入功能标注 |
| creative_zones | Scene best examples (L509) | 精彩片段注入更丰富的正面样本 |

### 4.11 意象密度策略

`motif_system` 子类新增 `density_policy` 字段，控制意象在全书的投放节奏。

```json
{
  "density_policy": {
    "max_per_shot": 2,
    "max_consecutive_shots": 3,
    "min_gap_after_cluster": 2,
    "per_chapter_budget": 12,
    "body_moment_ratio": 0.35,
    "philosophical_motif_ratio": 0.25
  }
}
```

| 字段 | 含义 |
|------|------|
| `max_per_shot` | 单 Shot 最多可出现的"身体时刻+哲学意象"总数（硬计数） |
| `max_consecutive_shots` | 连续 N 个 Shot 都有意象后必须空至少 `min_gap_after_cluster` 个 Shot |
| `per_chapter_budget` | 每章上限——写手池提示词注入"本章还剩 X 次额度" |
| `body_moment_ratio` | 身体时刻占意象总次数的比例上限 |
| `philosophical_motif_ratio` | 哲学意象占意象总次数的比例上限 |

**检测点**：
- 编译时：Step 3 意象分配阶段按 density_policy 校验——违反则重新分配
- 门控：Contract Gate 1 新增密度硬计数检查
- 全书后：意象密度报告作为 Chisel report 子报告

**互斥对保护**：从元契约 `anti_patterns` 推导"不能同时出现的意象配对"，编译时自动验证。

### 4.12 Repair 诊断（D-3 / D-4）

全书生产完成后，AI 架构师对红灯/坏味 Shot 进行诊断。采用四层 repair 框架（统一编号 L1-L4，与 `implementation-contract-v0.md §2.7` 一致）：

| 层级 | 名称 | 定义 | 能改什么 | 审批 |
|:---:|------|------|------|:---:|
| L1 | 零改动 | 文本不变，仅追加标注/降级灯色 | 注释、灯色覆盖、报告标记 | 自动 |
| L2 | 风格级 | 微调措辞/节奏/尾钩，不动叙事内容 | 句式、节奏、局部意象、尾钩措辞 | 自动 |
| L3 | 结构级 | 拆分/合并 Shot，重排叙事顺序 | Shot 边界、叙事顺序、段落重组 | 人类确认（批量） |
| L4 | 方向级 | 改 must_land/exit_to/人物弧线/章级约束 | 章级及以上契约层 | 必须人类确认（逐项） |

**升级规则**：
- L1 连续 3 次失败 → 自动升级到 L2
- L2 连续 3 次失败 → 自动升级到 L3（含自动暂停章节后续 Shot）
- L3 连续 2 次失败 → 自动升级到 L4
- ⭐⭐⭐ 触碰 → 直接升级到 L4

**硬规则安全网**：
- 连续红灯升级：同一 Shot 连续 N 次红灯，自动升级 repair 层级
- ⭐⭐⭐ 触碰升级：L3 repair 涉及 hard_boundaries / anti_reveal 条目，立即升级 L4
- 连锁影响升级：L3 repair 变更影响 > 3 个已执行 Shot，自动升级 L4

**安全网约束（所有层级通用）**：
- 不改硬边界（⭐⭐⭐）。
- 不改已落地的绿灯事实锚点。
- 不更改已确认的 anti_reveal 保护对象。
- 不溢出本 Shot 范围（L1）、本章范围（L2）、本卷范围（L3）。

### 4.13 硬边界紧急逃生舱（D-4）

人类可以在 `ink run` 期间触发硬边界逃生舱——每 run 最多 1 次。

**触发方式**：在对话中发送 `!escape` 或 `ink revise-boundary`。

**AI 架构师响应**（对话模式，不阻塞生产）：
1. **溯源**：识别哪条硬边界被触发、触发原因（契约矛盾 / 写手偏差 / 硬边界本身过紧）
2. **审计落库**：`writing_escape_events` 表记录（run_id, shot_id, boundary_id, reason, new_direction, timestamp）
3. **方向调整**：人类给出新方向 → AI 架构师修改相关硬边界 → 自动向下重编译未执行 Shot

**影响报告**：
- 展示范围（scope / affected Shots / divergence chain / boundary gate judges）
- 逐层审查——L2 一次确认，L3 按章确认，L4 人类逐条确认
- 每次修订 ≥ 50 中文字符理由

**约束**：
- 每 run 最多 1 次。超出后红灯走标准 repair 流程。
- 已被逃生舱修改的硬边界在本次 run 中不可再次修改。
- 逃生舱事件写入全书审计日志。

### 4.14 编译链（完整产出清单）

| 层级 | 输入 | 产出 |
|------|------|------|
| 全书 | 人类方向 + 写作指南 | 元契约十子类 |
| 卷/部 | 元契约 + 大纲 | 卷级专属约束 |
| 章/场 | 卷级契约 + 大纲 | 章级契约（叙事目标 + 章末读者状态） |
| Shot | 章级契约 + 上下文 | Shot 契约（must_land + anti_write + exit_to + 意象任务） + 预编译提示词 |

---

## 5. 赛车场经理

赛车场经理是编排器：

```text
lock contract snapshot
for each shot:
  load compiled prompt from writing_shot_prompts    -- setup 阶段已预编译
  assemble context (预编译提示词 + 前文正文 + 事实锚点 + Motif Tracker 状态)
  run writer race (≥2 写手，精彩片段 ≥4，按 Shot 特征自动选写手数)
  run L0 mechanical checks
  run Contract Gate 1
  if no usable draft:
      write best-failed-candidate red placeholder revision
      run smart-redo (L0 prompt → L1 fast model → L2 redo（模型从 redo_model 配置读取）)
      if smart-redo 成功后: replace placeholder
      if 3 级耗尽: mark done_red_permanent
      continue
  run 9-jury scoring (3-phase: 独立→比较→输出)
  select winner
  run final minimum gate on final text
  if final gate red:
      create red placeholder revision
      continue
  write winner as current revision
  extract fact anchors (if green/yellow, 9 类锚点)
  update motif density tracker
  write checkpoint (恢复用)
  mark green/yellow/red
  continue

after scope complete:
  generate scope projection report from DB
  continue next scope without human interruption
```

赛车场经理必须保证：

- DB3 是唯一真相源。
- 每个 Shot 都有当前正文 revision。
- 红灯也有占位正文（best-failed-candidate）。
- 绿灯 Shot 自动提取事实锚点（9 类）入库。
- 所有模型调用和落库有 idempotency key。
- 恢复后不会重复嵌尾钩、重复计分、重复切 current。
- 每 Shot 完成后写入检查点，支持自动/手动恢复。

### 5.1 崩溃恢复与检查点（D-14）

**检查点粒度**：每个 Shot 完成后写入。含所有候选文本、jury 评分、Gate 结果、winner 正文、事实锚点、motif tracker 状态。

**恢复策略**：
- 自动：`ink run` 检测未完成 Session → 提示 "发现未完成的 Session #42 (Act1/Ch3, 已完成 17/20 Shots)。继续？"
- 手动：`ink resume <session_id>` / `ink resume --last` / `ink sessions list` / `ink sessions abort <id>`

**异常分类**：

| 异常类型 | 恢复行为 |
|---------|---------|
| API 临时错误（429, 503） | 指数退避重试（3 次）。耗尽后暂停 Session |
| API 永久错误（400, 401） | 立即暂停，不重试 |
| 单 Shot 全部失败 | best-failed placeholder → smart-redo |
| 模型输出截断 | 自动扩展 token 限制或要求写手压缩 |
| 进程崩溃 | 从最近检查点恢复 |
| 网络中断 | 等待重连，当前 Shot 重试 |
| 磁盘满 | 拒绝开始新 Shot，保留已有数据 |

---

## 6. 写手池

### 6.1 写手人格系统（D-17）

每个写手拥有一个固定的创作人格，决定其"写作偏好"——不是限制写手的能力域，而是引导其注意力分配：

| 写手 | 人格 | 核心关注 | 次要关注 | 盲区 |
|------|------|---------|---------|------|
| A | **意象师** (Imagist) | 感官细节、氛围营造、隐喻系统 | 场景沉浸 | 对话推进、情节速度 |
| B | **节奏师** (Pacer) | 叙事节奏、悬念构建、信息释放时机 | Hook/衔接 | 意象密度、氛围 |
| C | **对话师** (Dialogist) | 人物对话、潜台词、声音差异 | 声音一致性 | 场景描写、环境 |
| D | **结构师** (Structuralist) | POV 一致性、事实锚点对齐、场景结构 | 事实一致性 | 对话自然度、文学性 |

**差异化来源**：
1. **Prompt 加权**：每个写手的 prompt 中，核心关注维度获得 2 倍 token 预算（更详细的指示）
2. **正例倾斜**：voice samples / reference text 选择偏向核心关注维度
3. **自评注释**：写手产出后附自评（≤150 tokens）——"我在这里试图通过窗外的雨声传递 Alice 的不安"

**非差异化项**：基础 prompt、反例系统、模型层、输出长度限制——所有写手相同。

### 6.2 写手数量自动选择

```
shot.dialogue_ratio > 0.4              → 3 名写手 (A 意象师, B 节奏师, C 对话师)
shot.pov_count > 1 or fact_anchor_count > 3  → 4 名写手 (A, B, C, D 结构师)
else                                   → 2 名写手 (A, B)
```

默认 2 名（意象师 + 节奏师），人类可覆盖 `--writer-count 4`。

### 6.3 写手 Prompt 结构

每个写手的 prompt 由三层组成：

```
Layer 1: 共享基础 (Shared Base)
├── Shot Context（场景描述、前文摘要、人物在场列表）
├── Fact Anchors（当前 Shot 相关的事实锚点）
├── Meta-Contracts（元契约硬约束）
└── Anti-Samples（反例，最多 5 对）

Layer 2: 人格加权 (Persona Lens)
├── 核心关注维度的详细指示（2x token budget）
├── 次级关注维度的简略指示（1x token budget）
└── 盲区维度的基础提醒（0.5x token budget）

Layer 3: Shot 特定 (Shot-Specific)
├── Motif Task（本 Shot 的意象任务）
├── POV 指示（本 Shot 的视角角色）
├── Pacing Cue（本 Shot 在节奏曲线上的位置）
└── Transition Hint（与前后 Shot 的衔接提示）
```

### 6.4 Writer Profile

每个项目绑定专属 writer profile，由 AI 架构师从元契约编译初版，人类微调：

- 系统提示词模板（继承元契约编译产物）
- voice samples（正面样本——"这样写是对的"）
- anti_samples（反面样本——"不能写成这样"）
- temperature_range

voice samples 来源：
1. 人在 setup 阶段提供的样章（最可靠）
2. 裁判评分 ≥ 90 的 Shot 自动入池（Phase 2）
3. AI 架构师从元契约反推生成初版

### 6.5 反例系统（D-15）

**五类反例来源**：

| # | 来源 | 触发条件 |
|---|------|---------|
| 1 | 手动输入 | Setup 阶段人类明确指定 |
| 2 | 声音校准生成 | Voice calibration 后自动生成 |
| 3 | 红灯反向推导 | Gate 红灯时自动提取 → 成为下个 Shot 反例 |
| 4 | Project 通用反例 | 项目建立时从模板加载 |
| 5 | 人类运行时注解 | Scope review 时人类标记 |

**声音校准工作流**：
```
ink voice-calibrate <project>

1. 加载 voice samples（每个角色 ≥3 段）
2. AI 分析样本 → 提取 marker（词频/句长/修辞偏好/禁忌词/口头禅）
3. 生成反例：每个 marker 生成 1-2 个违反样本
4. 呈现给人类确认/修正/删除
```

**声音指纹存储**：
```json
{
  "markers": [
    {"type": "syntax", "rule": "句长 10-18 字，从不超 25 字", "strictness": "hard"},
    {"type": "vocabulary", "rule": "禁用情感状态直接描述", "strictness": "hard"},
    {"type": "rhetoric", "rule": "禁用比喻，最多使用白描类比", "strictness": "medium"}
  ]
}
```

**运行时反例注入**：最多 5 对样本对（❌/✅ 格式），非抽象规则。注入位置在 prompt 末尾（recency effect 最后一秒制动器）。

**反例降温**：当某个反例连续 3 个 Shot 未被触发，权重降低。连续 10 个 Shot 未触发，从活跃列表中移除（归档到参考池）。

**Voice Drift 检测**：每 3 个 Scope，系统对比写手产出中的 voice marker 命中率与基准指纹。命中率偏离 > 15% → 告警。

### 6.6 硬约束

- 不改事实。
- 不改人物状态（事实锚点约束）。
- 不破坏时间线。
- 不破坏世界规则。
- 不输出正文外解释。
- 不揭露 anti_reveal 保护的信息。
- 遇到契约自相矛盾时输出失败原因，由系统转红灯占位。

### 6.7 可自由发挥

- 表达。
- 场景角度。
- 意象。
- 身体感。
- 对话潜台词。
- 尾钩。
- 节奏。

### 6.8 成长飞轮

```
人类种子样章 → 写手生成 → 裁判评分
  → 高分入 positive pool / 低分入 negative pool
  → 下一次写手拿到更丰富的样本
  → 质量提升 → 继续循环
```

参考池 `writing_reference_pool` 存储正反面样本，附带标注（"为什么好/为什么坏"）。

### 6.9 角色写作指南 (Character Writing Guide)

每个 POV 角色必须配备完整的角色写作指南，远超 voice sample——是角色的完整写作规范。由 AI 架构师从人物小传和样章中编译初版，人类微调。

```json
{
  "character_id": "白英",
  "portrait": {
    "appearance": "五十岁，头发盘起来，从来不染。手指粗、有力。穿布鞋。",
    "body_memory": "盖上茶杯盖时从不发出声音。围裙口袋里永远有一包纸巾。",
    "habitual_gesture": "用手背试杯壁温度——做了三十年，手指就是温度计。"
  },
  "voice": {
    "rhythm": "短句，不解释。不说'这是我的使命'。",
    "silence_pattern": "她的话和烧的水一样——不烫，但喝下去会暖。",
    "lexicon": {
      "must_use": ["茶要凉了", "多穿点", "好"],
      "may_use": ["水开了", "你来喝"],
      "never_use": ["对抗", "这是我的使命", "我们不能让他们", "系统是错的"]
    }
  },
  "behavior_patterns": [
    "不看水温计——手背就是温度计",
    "把通知扫进抽屉，不说一个字",
    "给人续茶时不等对方开口"
  ],
  "recognition_traits": [
    "手背试杯壁的动作",
    "围裙口袋里的纸巾",
    "关抽屉时手停一下"
  ],
  "positive_samples": [{"text": "白英说'好'，把通知扫进抽屉。抽屉里已经有了三份。", "annotation": "不说'我拒绝'——说'好'。动作本身是全部判断。"}],
  "negative_samples": [{"text": "白英意识到这是系统在慢性绞杀她的茶社。", "annotation": "错——白英不总结。她的判断只存在于动作。"}],
  "voice_contrast_with": {"character_id": "苏然", "difference": "白英不解释，苏然用代码解释"},
  "phase_switching": {
    "entry": {"voice_phase": "日常温度——说'好'的时候，茶还是热的"},
    "active": {"voice_phase": "评估团在场——说'茶要凉了'，是回答也是不回答"},
    "exit": {"voice_phase": "河畔末章——说'明天降温，多穿点'，最日常的话承担最重的回声"},
    "timeless": {"voice_phase": "手背试杯壁——全书不变的身体记忆"}
  }
}
```

角色写作指南进入 writer profile，作为 POV 角色的标准配置。赛车场经理加载时：POV 角色加载完整指南，出场角色加载简要版，提及角色仅加载识别特征。

### 6.10 场景姿态定义 (ASTO 坐标)

场景级契约可选 ASTO 坐标和 scene_position。

**ASTO 三轴**：

| 轴 | 可选值 | 含义 |
|------|------|------|
| **Phase** | chaos / order / flow / pulse / dissolution / return | 叙事节奏——场景在故事节律中的位置 |
| **Mode** | free / consensus / encoding / materialization / directed | 存在主义质感——场景以什么方式存在于叙事中 |
| **Sequence Profile** | awakening / perception / analysis / intervention / design / review / dissolution | 段落级结构——七步权重加起来 = 1.0 |

**scene_position**：

| 值 | 驱动 |
|------|------|
| OPEN | 激活首钩+尾钩，检查入场衔接 |
| BUILD | 无钩子激活，正常叙事推进 |
| CLIMAX | 激活全部三个钩子，检查全部质量维度 |
| BRIDGE | 最小钩子，仅检查连续性 |
| CLOSE | 仅激活尾钩 |
| STANDALONE | 激活全部钩子 + 独立完整性检查 |

---

## 7. 9 裁判团

### 7.1 配置与评分架构（D-21）

采用 **3-phase 评分流程**：

```
Phase 1: 独立阅读（不比较）
├── 阅读候选 A → 9 维打分 + 注释
├── 阅读候选 B → 9 维打分 + 注释
├── 阅读候选 C (if present) → ...
└── 阅读候选 D (if present) → ...

Phase 2: 比较判断
├── 每维度排序 (A > B > C > D)
├── 综合排序 (winner, 1st runner-up, ...)
└── 生成比较性评语

Phase 3: 最终输出
├── winner 正文
├── 每位候选的 9 维分数
├── winner 的比较性评语
├── 被拒绝候选的亮点摘录
└── 综合置信度 (0-1)
```

**评分模式**：相对排序 + 绝对分双重机制。相对排序用于选 winner，绝对分用于 Gate（是否绿灯）。

**量程**：每维度 0-10 分，0.1 精度。

**模型**：使用 `model_tiers.jury`（默认 Sonnet），非 Opus——Jury 是评判工作不是创造工作，且需要一次读取 2-4 份候选，Sonnet 更快更经济。

**校准**：每 3 个 Scope 后检查 jury 分数分布——σ < 1.0 提示需要更多区分度；如果 winner 总是同一个人格类型，检查人格偏见。

### 7.2 裁判配置

6 基础裁判，0-3 动态裁判。动态裁判从系统级维度池由元契约自动激活。

| 基础裁判 | 维度 |
|------|------|
| 契约官 | 契约履约 |
| 声音官 | 人物声音 |
| 衔接官 | 前后衔接 |
| 禁元官 | 禁用表达和 AI 味 + 反例检测 + 类型边界 |
| 可读官 | 阅读流畅度 |
| 完整官 | Shot 独立完整性 |

动态裁判池：悬念官 / 主题官 / 伏笔官 / 弧线官 / 状态官 / 对话官 / 身体官 / 术语官。

激活规则：例如——元契约 anti_reveal 非空 → 伏笔官；含"身体时刻"要求 → 身体官；禁术语列表非空 → 术语官。

### 7.3 阈值与裁判输入

红黄绿阈值由元契约的宽松度声明控制（非全局常量）。项目专属配置支持 9 维各维度权重独立调整（D-13）。

默认：green ≥ 85 / yellow ≥ 65 / red < 65。

裁判 prompt = 通用维度定义 + 本项目的元契约相关子集 + 本项目的 voice samples。反例和正面参照是裁判判断的基准。

### 7.4 全书后虚拟读者层（Phase 2）

生产期裁判只判"能继续/不能继续"。全书完成后虚拟读者池判"好不好"，不进红黄绿，进报告。

---

## 8. 红黄绿 + 精彩/坏味灯

红黄绿以 Shot 为主粒度。精彩灯与坏味灯**完全正交**——同一 Shot 可同时持有 brilliance 和 badsmell 双灯，互不降级。

| 灯色 | 正文行为 | 后续行为 |
|------|----------|----------|
| ⭐ 精彩 S/A+/A | winner 入正文，标注 brilliance_level | Phase 1 仅记录——人类在全书 production report 中统一审批入池 |
| 绿灯 | winner 正文进入当前正文版本链，自动提取事实锚点 | 后续 Chisel 校准仍可修改 |
| 黄灯 | winner 正文进入当前正文版本链并标记观察 | 全书完成后 AI 优先优化 |
| 💀 坏味 B/Br/Bz | winner 入正文，独立标注 badsmell_level | Br 需 repair 优化；Bz 必须人类确认后入反例库。AI Flavor 入 Character Writing Guide 的 negative_samples |
| 红灯 | 生成占位正文（best-failed-candidate），标记 placeholder_type + violation 说明 | 全书完成后 AI 先诊断原因，再修约 + 补写/重跑 |

**Writer Race 失败处理（D-9）**：

- **Placeholder**：使用 Gate 2 violation 最少的候选（best-failed-candidate），附带 violation 说明——维持下游 Shot 叙事连续性。
- **Smart-Redo 成功**：完全替换 placeholder——成功文本经完整 Gate 2 校验。
- **3 级升级耗尽**：标记 `done_red_permanent`，在 Scope 投影中红色边框 + violation 摘要，等待人类处理——不暂停整个 Scope。

---

## 9. 事实锚点（D-19）

### 9.1 数据模型

每个绿灯/黄灯 Shot 落库时自动提取不可逆事实：

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

### 9.2 提取与冲突处理

**提取触发**：Gate 2 通过后（绿/黄 Shot），在 Shot 完成确认前。

**提取流程**：Shot 正文 → Fact Anchor Extractor（AI Agent）→ 新增锚点 / 更新锚点 / 确认锚点。

**5 种冲突类型**：
- 显式矛盾（如 "Alice 在工厂" vs "Alice 在办公室"）
- 隐式不一致（从两个锚点推断出的矛盾）
- 时间线错位（事件发生顺序不一致）
- 可解释偏差（有叙事理由但需记录）
- 视角矛盾（POV 角色不知道，但叙述语气暗示知道）

**冲突解决**：显式矛盾 → AI 自动标记矛盾锚点 + Gate 2 红灯。隐式不一致 → 警告 + 标记 `needs_review`。POV-dependent 事实标记 `pov` scope。

后续 repair 或新 Shot 的契约编译，必须通过事实锚点一致性检查。

---

## 10. Motif 密度追踪（D-20）

### 10.1 Motif 定义与注册

每个 Motif = 意象 + 频率计划 + 演化弧线：

```json
{
  "motif_id": "m_act1_rain",
  "project_id": "qianlong",
  "name": "雨",
  "category": "weather",
  "description": "雨水作为压抑和清洗的双重意象",
  "planned_density": {"per_act": 12, "per_chapter": 3, "per_shot": 1},
  "variants": ["雨", "雨水", "下雨", "雨声", "细雨", "暴雨"],
  "min_shot_gap": 3,
  "evolution_phase": "establishment"
}
```

**注册来源**：Setup 人类手动定义 / AI 从导入文本逆向提取 / 模板预设 / 写作过程中人类新增。

### 10.2 密度追踪器

每个 Act 维护一个 Motif Density Tracker，实时状态分为五档：

| 状态 | 含义 |
|------|------|
| 🟢 green | 频率按计划推进，偏差 ≤ ±1 |
| 🟡 yellow | 轻微超频/欠频，偏差 ±2~3 |
| 🔵 blue | 过度使用，偏差 ≥ +4 |
| 🔴 red | 严重欠频，偏差 ≤ -4 |
| ⬜ gray | Motif 尚未进入活跃期 |

### 10.3 Motif Task 自动生成

赛车场经理在每个 Shot 编译时自动检查 Motif Tracker，生成 Motif Task：

- **Required**：该 Motif 欠频严重（red 状态），必须在此 Shot 出现
- **Suggested**：该 Motif 按计划应该出现（green→yellow），但不强制
- **Forbidden**：该 Motif 已超频（blue），或距上次出现 < min_shot_gap
- **Allowed**：不限制，但不鼓励

### 10.4 Motif 演化 Phase

- Phase 1 **establishment**：首次引入，建立感知识别
- Phase 2 **variation**：变体出现，形成 pattern
- Phase 3 **subversion**：预期被打破，产生意义转折
- Phase 4 **resolution**：意象完成其叙事功能，回归 / 消解

---

## 11. 跨 Shot 叙事一致性（D-22）

### 11.1 五层检查

| 层级 | 检查内容 | 检查方式 | 检查时机 |
|------|---------|---------|---------|
| L1: 事实连续性 | 人物位置、物品状态、时间推进 | Fact Anchor 系统自动验证 | Gate 2 中 |
| L2: 视角连续性 | POV 角色在相邻 Shot 之间切换是否合理 | Jury 维度 3 | Jury scoring |
| L3: 叙事节奏 | 事件密度变化是否符合节奏曲线 | Jury 维度 2 | Jury scoring |
| L4: 主题连贯 | 相邻 Shot 是否服务于同一场景的主题意图 | Scene Composition Check | Scene 完成后 |
| L5: 意图漂移 | 3+ 连续 Shot 从元契约核心理念逐渐偏离 | Intent Drift Detection | 每 5 Shot |

### 11.2 Continuity Context Window

```
Previous Shots Context Window:
├── Previous Shot (N-1): 全文
├── Shot N-2: 全文
├── Shot N-3: 摘要（200 tokens）
├── Shot N-4: 摘要（200 tokens）
├── Shot N-5: 摘要（200 tokens）
└── Scene Start: 场景开启 Shot 全文（作为参考锚点）
```

### 11.3 Scene Composition Check

Scene 的全部 Shot 完成后触发。合并全文 → 检查：场景弧线完整性 / 视角切换是否有叙事理由 / 对话是否推进场景 / 意象分布是否均匀 / 是否有"叙事漏洞"。输出 Scene Cohesion Score (0-10)。**诊断工具，不阻塞生产**。

### 11.4 Intent Drift Detection

每 5 Shot 触发一次。对比最近 5 个 Shot 的整体叙事姿态与元契约 `identity.thematic_core` 和 `hard_boundaries`。若偏离 → 写入 `intent_drift_alert`。**不自动阻止生产**——在 Scope 投影中告警。

### 11.5 跨 Shot 引用追踪

绿灯 Shot 时，分析正文中是否有对前文的**跨 Shot 引用**（call-back / 呼应）。如有 → 记录 `cross_shot_reference`（from_shot_id → to_shot_id → reference_text）。用于全书后的叙事结构分析。

---

## 12. 多项目管理（D-10）

### 12.1 Universe → Project → Act 三级模型

```
Universe (1) ──< Project (N) ──< Act (N)
```

- **Universe**：共享世界观的容器。含宇宙级事实锚点（物理法则、历史事件、地点字典）和共享人物池。
- **Project**：一个独立的写作任务（一本书、一个系列的一部）。继承 Universe 的事实锚点。
- **Act**：Project 的分卷/分部。继承 Project + Universe 的事实锚点。

Project 可不属于任何 Universe（独立作品），此时 Project 自己是事实锚点根。

### 12.2 元契约三层继承

```
Universe 级元契约 (世界观规则、禁忌、硬边界)
    ↓ 覆盖 / 追加
Project 级元契约 (主题、体裁、核心意象、叙事声音)
    ↓ 覆盖 / 追加
Act 级元契约 (节奏曲线、意象密度预算、POV 权重)
```

继承规则：子级默认继承父级所有字段 → 可覆盖（只影响当前及后续层级）→ 覆盖不反向传播。冲突检测：Act 级覆盖与 Universe 级硬边界冲突 → 架构师警告并请求人类确认。

### 12.3 事实锚点跨项目同步

Universe 级事实锚点修改 → 所有 Project 收到"事实变更通知" → 人类选择 accept / override / defer。

- **Accept**：更新所有引用该锚点的 Shot（已写 Shot 不回写，下游 Shot 使用新锚点）
- **Override**：Project 级创建覆盖（不再受 Universe 级同步）
- **Defer**：保持当前版本

### 12.4 批量导入与契约逆向提取（D-16）

支持 `.txt` / `.md` / `.docx` 导入已有作品。

**逆向工程提取元契约**（分置信度）：
- **高置信度（>70%）**：硬边界、已揭露信息、角色列表 → 自动纳入元契约草案
- **中置信度（40-70%）**：叙事声音策略、意象系统 → 呈现给人类确认
- **低置信度（<40%）**：潜在反例、隐含主题 → 以提示/建议方式呈现

**从停更点继续**：导入部分完成稿 → 扫描已写 Shot 提取事实锚点 → 从下一个未写 Shot 开始。

**系列作品**：`ink clone <source_project> --as <new_project>` ——从已有项目复制元契约，interactive override 阶段修改。

---

## 13. Prompt 编译与缓存（D-18）

### 13.1 编译流水线

4 阶段编译，Setup 阶段预编译入库：

```
Stage 1: Context Assembler
  - 加载 Shot 上下文（前文窗口、人物在场、场景）
  - 查询相关 Fact Anchors
  - 查询 Motif Tracker 当前状态

Stage 2: Persona Lens Applicator
  - 加载写手人格模板
  - 对静态缓存组件加权重组

Stage 3: Cache Resolver
  - 分离静态/动态组件
  - 静态部分使用缓存引用
  - 动态部分实时装配

Stage 4: Final Assembly
  - 拼接所有组件
  - Token 预算检查（如超出则压缩动态部分）
  - 输出最终 prompt
```

### 13.2 Anthropic Prompt Caching 集成

- **Breakpoint 1**：元契约（静态，跨 Shot 不变）→ 缓存前缀
- **Breakpoint 2**：角色声音配置（半静态）→ 缓存中点
- **Breakpoint 3**：Shot 上下文 + 事实锚点 → 动态后缀

预期 ~60% tokens 可缓存，显著降低 API 调用成本。

### 13.3 Token 预算

- **硬预算**：单 Shot prompt ≤ 8k tokens
- **软预算**：目标 6k tokens，超出时压缩优先级：前文摘要 > positive samples > 反例 > 人格加权指示 > 硬边界
- **不压缩**：硬边界、anti_reveal、当前 Shot 契约、事实锚点

---

## 14. 元契约可审计性（D-23）

### 14.1 条款追踪

每条元契约条款有唯一 ID，可在系统各处引用：

```json
{
  "contract_id": "mc_qianlong_v36_h1",
  "section": "hard_boundaries",
  "index": 1,
  "text": "Alice 不知道 Ben 的过去...",
  "violation_count": 1,
  "violation_history": [
    {"shot_id": "act1_ch3_s39", "jury_dimension": 8, "severity": "major", "resolution": "smart-redo L1 → resolved"}
  ]
}
```

**引用链**：`Meta-Contract → Jury Dimension 8 Score → Gate 2 Decision → Shot Status`。任何红灯 Shot 可向上追溯到违反的具体条款。

### 14.2 契约仪表盘

`ink contracts <project>` ——四维视图：
- **条款维度**：每条条款的 violation 计数 + 最近 3 次违规
- **声音维度**：每个 POV 角色的 voice drift 趋势
- **Motif 维度**：每个 Motif 的密度 vs 计划对比
- **违规维度**：按 Act 聚合的违规热力图

### 14.3 契约演化日志

`contract_changelog` 记录每次契约修改：谁修改、什么字段、旧值、新值、人类是否确认、修改原因、时间戳。支持完整审计追溯。

### 14.4 违规模式分析

每 Act 完成后 AI 架构师自动分析：哪些条款被频繁违反 / 哪些 Shot 类型容易违规 / 是否有模式（如某个写手总是触发某类违规）。

---

## 15. 项目专属配置（D-13）

### 15.1 三层配置

```
Default Config (Chisel 内置，5 个预设)
    ↓ 覆盖
Project Config (.chisel/config.yaml)
    ↓ 覆盖
Act Config (仅节奏曲线和 jury 权重)
```

**覆盖规则**：子层覆盖父层同名字段，未覆盖字段继承。

### 15.2 5 个内置预设

| 预设 | 适用 | 核心调整 |
|------|------|---------|
| `literary` | 文学小说 | 声音官+主题官权重 ↑，节奏权重 ↓ |
| `scifi` | 科幻 | 术语官启用，世界观权重 ↑ |
| `mystery` | 悬疑 | 伏笔官启用，对话权重 ↑ |
| `web-novel` | 网文/爽文 | 节奏权重 ↑，完整官权重 ↓ |
| `series` | 系列作品 | 衔接官权重 ↑，跨卷一致性检查 |

### 15.3 CLI 覆盖

```bash
ink run "分流" --config jury.thresholds.green=8 --config writer_count=4
```

---

## 16. 契约生命周期

六种状态（draft → human_review → confirmed → locked，异常分支 repairing / evolving）：

| 状态 | 含义 | 可变性 |
|------|------|------|
| `draft` | AI 架构师编译中 | 任意修改 |
| `human_review` | 等待人类审核 | 可修改 |
| `confirmed` | 人类确认，尚未 run | 可修改但需重新确认 |
| `locked` | `ink run` 快照已创建 | **不可变** |
| `repairing` | 修补中（红灯 Shot） | 红灯 Shot 契约可改，硬边界不可改 |
| `evolving` | 人类追加新约束 | 未执行 Shot 自动重编译，已执行标记 stale |

### 16.1 契约升级路径（D-11）

当 Chisel 版本升级引入新契约字段时：
- **Level 1 自动填充**：新字段有明确默认值 → 自动填充，不通知人类
- **Level 2 建议填充**：新字段需要项目上下文 → AI 推断 → 人类一次性确认
- **Level 3 手动填充**：新字段需要人类原创输入 → 标记为 pending，人类在下次 setup 时处理

**已生成文本不回写**——升级后的新契约只影响下游未生成的 Shot。

---

## 17. Scope 投影报告（D-12）

### 17.1 三层交互式视图

```
Layer 1: 摘要卡片
┌────────────────────────────────────────────┐
│ Act 1 / Ch 3 / Run Scope 2                │
│ 12 Shots: 9 绿 ●  2 黄 ●  1 红 ●          │
│ Avg jury score: 7.2 (-0.3 vs prev scope)   │
│ Motif density: 1.8 avg (cap 2.0)           │
│ Voice consistency: 92%                      │
└────────────────────────────────────────────┘

Layer 2: Shot 列表（展开 Layer 1）
┌──┬──────┬───────┬──────────────────────────┐
│37│绿 ●  │ 7.8   │ Alice 推开废弃工厂的铁门…│
│38│绿 ●  │ 8.1   │ 她看见墙角有一组新鲜的足迹│
│39│红 ●perm_r│ 5.2│ [PLACEHOLDER]…           │
│40│黄 ●  │ 6.9   │ 对讲机突然发出噪音…      │
└──┴──────┴───────┴──────────────────────────┘

Layer 3: Shot 详情（展开单个 Shot）
- 完整正文（可阅读格式）
- 9 维 jury scores 雷达图
- 裁判主席评语
- 被拒绝候选方案亮点
- Gate 1 / Gate 2 结果
- 事实锚点提取结果（绿Shot）
- [操作] approve / fix / redo / flag / edit context / lock
```

### 17.2 6 种人类操作

| 操作 | 含义 |
|------|------|
| `approve` | 显式确认该 Shot 无需修改 |
| `fix "…"` | 向架构师描述问题 → 架构师重写 |
| `redo` | 用不同 writer 配置重新生成该 Shot |
| `flag` | 标记需要后续注意（不立即修改） |
| `edit context` | 修改该 Shot 的契约上下文（不直接改文本） |
| `lock` | 锁定该 Shot 不被后续 repair 修改 |

---

## 18. 上下文组装

赛车场经理使用 static_prefix（setup 预编译）+ dynamic_assembly（运行时装配）。最终 prompt 在运行时完成装配。

加载顺序（recency effect）：
```
1. 前文正文（叙事连续性）
   - N-1, N-2 全文
   - N-3~N-5 摘要（200 tokens）
   - Scene Start 全文（锚点）
2. 人物状态快照 + 意象任务（事实约束）
3. Shot 契约（目标）
4. voice samples（风格参照）
5. 反例提醒（最后一秒制动器）—— 最多 5 对，具体样本对
```

---

## 19. 与 Chisel 的关系

Write 负责生产正文。

Chisel 负责生产后的二次校准：

```text
ink run
→ ink repair red/yellow (诊断 + 修约 + 重跑)
→ chisel scan
→ chisel report
→ chisel batch-fix
→ human final handling
```

Chisel scan/fix 不是生产期拦截器，不阻止全书跑完。

---

## 20. 权威规则

如其它文档与本文冲突，以以下规则为准：

1. 人类前置沟通，AI 架构师编译全链契约并落库。
2. 项目结构自适应，不预设固定层级。
3. 元契约十子类 + 继承链 + 稳定性梯度。
4. 意象分配到 shot_context，非章节序号。
5. 生产期 AI 全自动写完整目标范围。
6. 生产期不打断人类。
7. 生产期不自动改契约。
8. 绿/黄直接入正文。绿灯自动提取 9 类事实锚点。
9. 红灯写 best-failed-candidate 占位，smart-redo 自动升级处理。
10. Repair 四层框架，先诊断后修约。
11. 全书完成后 AI 先修红/黄。
12. 人类最后集中二次处理。
13. DB3 是唯一真相源。
14. static_prefix 预编译入库 + dynamic_assembly 运行时装配，4 阶段编译 + Anthropic Prompt Caching。
15. 成本不是设计约束。
16. 4 写手人格系统（意象师/节奏师/对话师/结构师），同名同模型，差异化 prompt。
17. 9 裁判团 3-phase 评分（独立→比较→输出），相对排序+绝对分。
18. 每 Shot 检查点 + 自动/手动恢复。
19. 跨 Shot 叙事一致性五层检查。
20. 元契约条款唯一 ID + 完整审计链。
