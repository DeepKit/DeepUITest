# InkFlow v3.6 — 模块决策汇总（历史参考，已融入 design.md）

> 创建：2026-06-14 / 更新：2026-06-15
> 状态：v3.6 权威决策
> 本文已融入 design.md / implementation-contract-v0.md。本文件仅保留作为决策历史参考。
> v3.5→v3.6 变更：D-1 字段扩展 / D-2 精彩坏味正交+暂准入池 / D-3 四层 repair 框架 / D-4 硬边界逃生舱 / D-5 POV 路由 / D-6 意象密度上限
> 相关文档：`inkflow/docs/design.md`, `inkflow/docs/flow.md`, `inkflow/docs/role-system.md`

---

## 1. 总目标

Chisel Write 是全自动文学文本生产引擎。

目标排序：

```text
文学质感 > 人物声音 > 情节契约 > 节奏 > 成本速度
```

成本不作为当前设计约束。DB3 是唯一真相源。

---

## 2. 权威决策

### D0. 架构总览

```
人类与 AI 架构师前置沟通 (write setup)
  → AI 架构师编译全链契约并落库
  → 人类审核继承摘要，确认
  → write run 按契约快照全自动生产正文
  → 绿灯/黄灯 Shot 直接进入正文版本链
  → 红灯 Shot 写占位正文并继续后续生产
  → 全书生产完成
  → AI 先自动修红/修黄/二次优化 (write repair)
  → 人类集中二次处理
  → Chisel scan/report/fix 做全书校准
```

不可变原则：

1. DB3 是唯一真相源，报告和导出文件只是投影。
2. 生产期不打断人类。
3. `write run` 只能执行本次已落库契约快照，不自动修改契约。
4. AI 产出直接成为正文版本；后续修改由 revision 链维护。
5. 红灯不留空，必须生成占位正文，保证后续上下文连续。
6. 质量优先级为：文学质感 > 人物声音 > 情节契约 > 节奏 > 成本速度。
7. Token 成本不作为当前架构约束。

---

### D1. 人类介入边界 (v3.5)

人类只在前置沟通和全书完成后的集中二次处理阶段介入。

生产期不打断人类。

---

### D2. 契约分层与编译 (v3.5 核心升级)

#### D2.1 项目结构自适应

Chisel Write 不预设固定的契约层级。项目结构由 AI 架构师在 setup 阶段**识别**。

系统内部使用 **MNU（最小叙事单元，Minimal Narrative Unit）** 作为统一概念。不同项目的结构映射：

| 项目 | 层级 | MNU | 人类确认到 |
|------|------|-----|-----------|
| 《分流》 | 全书→卷→章→Shot | Shot | 章 |
| 《签》 | 全书→部→场→节 | 节 | 部 |
| 《背锅侠》 | 系列→卷→集 | 集 | 卷 |
| 《数术编年史》 | 全书→纪→集 | 集 | 纪 |

存储格式：

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

#### D2.2 元契约（全书级，跨单元复用）

从四部小说的写作指南中提炼，元契约包含十个子类：

| # | 子类 | 内容 | 稳定性 | 谁可以改 |
|:---:|------|------|:---:|------|
| 1 | **identity** | 这本书是什么、不是什么 + `thematic_core`（主题内核：全书共享的叙事姿态） | ⭐⭐⭐ | 只有人类 |
| 2 | **hard_boundaries** | 绝对不能写什么 + `confidence`（高/中/低）| ⭐⭐⭐ | 只有人类 |
| 3 | **anti_reveal** | 不解之谜保护 + `release_window`（可揭露的窗口范围） | ⭐⭐⭐ | 只有人类 |
| 4 | **anti_patterns** | 最容易写偏成什么（反例表）| ⭐⭐ | 人类可以改 |
| 5 | **narrative_voice** | 叙事声音策略——策略声明 + POV 角色列表（多POV时按角色路由voice） | ⭐⭐ | 人类可改 |
| 6 | **style_locks** | 语言腔调、句式纪律、对话规则 | ⭐⭐ | 人类可以改 |
| 7 | **structure_rules** | 跨卷/部的结构循环规则（发动机公式/病种轮转等）+ `emo_state`（每卷/章的目标读者情感状态） | ⭐⭐ | 人类可改，AI按规则实例化 |
| 8 | **creative_zones** | 哪些区域允许 AI 放开写 | ⭐ | 人类可以改 |
| 9 | **motif_system** | 意象/元素的意义弧线 + `density_policy`（密度上限配置） | ⭐ | 人类可改，AI可重分配 |
| 10 | **world_knowledge** | 虚拟世界物理规则（科幻/架空必填，现实题材可选）| ⭐⭐⭐ | 只有人类 |

示例——《分流》元契约片段：

```
identity: "它不是实时写作插件，也不是每章都需要人类确认的协作编辑器。"
hard_boundaries:
  - "鱼嘴不能被推翻、不能被替换、不能被关闭"
  - "古蜀文明不写成远古高科技"
  - "结尾不写胜利，也不写投降"
anti_reveal:
  - "调度员的身份、姓名、性别、外貌、动机——全书不揭示"
  - "祭祀坑垃圾层是有意还是偶然——永远不判定"
anti_patterns:
  - "不能写成赛博朋克霓虹皮"
  - "不能把白英写成民间智慧化身"
style_locks:
  - "白描摄像机视角，作者不下场做价值评判"
  - "阿坤的膝盖要疼到最后一章"
creative_zones:
  - "精彩片段：表达、意象、身体感、尾钩放开"
  - "普通 Shot：按完整契约执行"
```

#### D2.3 契约编译链

AI 架构师在 setup 阶段走完以下编译链：

```
Step 1: 识别项目结构（MNU + layer index + human_confirm_layer）
Step 2: 提取硬边界列表 (hard_boundaries + anti_reveal)
Step 3: 提取意象/元素 must_recur 列表 → 分配到 shot_context，执行 density_policy 软约束
Step 4: 按卷/部扫描大纲 → 提取每卷专属约束 + primary_pov（多POV项目的当前卷 POV 角色）
Step 5: 按章/场展开 → 章级契约（叙事目标 + 章末读者状态 + emo_state）
Step 6: 按 Shot 展开 → Shot 契约（must_land + anti_write + exit_to + 意象任务 + primary_pov 路由 voice）
Step 7: 全链冲突检测（硬边界 / anti_reveal / exit_to 连续性 / 意象密度硬计数 / 意象互斥对）
Step 8: 编译 Shot 提示词 + 版本化 + 落库
```

**编译顺序**：anti_write 链先展开，must_land 链后展开。先锁边界再填内容。

**语义分配**：意象和元素分配到 shot_context（叙事上下文），而非章节序号。

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
    },
    {
      "shot_context": "评估团坐在茶社，白英沏茶，团长问'这杯茶在系统里是什么参数'",
      "function": "become_philosophical_metaphor",
      "chapter_hint": "v03.c13",
      "chapter_hint_is_soft": true
    }
  ]
}
```

`chapter_hint` 是软建议——如果人类调整大纲使该场景移到其他章，分配自动跟随。

#### D2.4 契约继承规则

每层契约回答不同的问题：

| 层 | 回答的问题 | 产出 |
|------|------|------|
| 全书 | 这本书的文学身份是什么？绝对不能写什么？| 元契约 10 子类 |
| 卷/部 | 这一卷在全书中承担什么功能？专属约束？| 卷级契约 |
| 章/场 | 这一章要实现的叙事结果？章末读者状态？| 章级契约 |
| Shot | 这个 Shot 具体写什么？哪里承接、送到哪里？不能写什么？| Shot 契约 |

**继承规则**：下层自动继承上层所有约束。下层可以细化，不可否定。

**稳定性梯度**：

| 约束类型 | 稳定性 | 可变范围 |
|------|:---:|------|
| 硬边界 / anti_reveal | ⭐⭐⭐ | 全书不变 |
| anti_patterns / style_locks | ⭐⭐ | 卷级可微调 |
| 意象分配 / must_land | ⭐ | Shot 级可重分配 |

**人类审核方式**：树状继承摘要，不逐 Shot 检查。

```
鱼嘴不能被推翻 (全书硬边界)
  ├── 卷一：鱼嘴正常运转，边界在不知不觉中移动 ✅
  │   ├── 第 01 章：苏然发现外江推了17%，不报告 ✅
  │   └── ...
  ├── 卷三：苏然推一厘米，不是推翻 ✅
  │   ├── 第 19 章 Shot 4：苏然加备注，不删库 ✅
  │   └── ...
  └── 卷四：评估团建议"可复制的局部校正模型" ✅
```

人类可以在任意节点注入修正，AI 架构师自动向下重编译。

---

### D3. 契约生命周期 (v3.5 核心升级)

#### D3.1 六种状态

```
draft → human_review → confirmed → locked → [repairing] → [evolving]
```

| 状态 | 含义 | 可变性 |
|------|------|------|
| `draft` | AI 架构师编译中 | 任意修改 |
| `human_review` | 等待人类审核 | 可修改 |
| `confirmed` | 人类确认，尚未 run | 可修改但需重新确认 |
| `locked` | `write run` 快照已创建 | **不可变**，只记录 deviation_notes |
| `repairing` | 全书生产完成后修补 | 红灯 Shot 契约可改，硬边界不可改 |
| `evolving` | 人类追加新约束 | 未执行 Shot 自动重编译，已执行 Shot 标记 stale |

#### D3.2 Repair 四层诊断框架 (D-3)

红灯 Shot 先诊断后修约。AI 架构师读取裁判反馈 + deviation_notes，判断红灯原因：

- **写手执行失败**：契约合理，写手没写好 → repair 用原契约，重跑赛马
- **契约本身有问题**：契约自相矛盾或与前后文冲突 → 先修约，再重跑

修约四层框架（D-3，替换旧的"小/中/大修"三阶分类）：

| 层级 | 名称 | 人类参与 | 触发条件 | 处理方式 |
|:---:|------|:---:|------|------|
| **L1** | 零改动 | 不需要告知 | 执行失败（LLM 错误/超时/截断）或写手首次裁决失败 | 原契约自动重跑（重试上限 3 次）；连续 2 次仍红灯 → 升级 L3 |
| **L2** | 风格级 | 报告标注，不需确认 | 措辞优化，不改 must_land/exit_to 语义方向 | AI 自动执行；条件：影响半径=1 / 不触 ⭐⭐⭐ 字段 / 不改 must_land 语义；入 repair 报告 diff 摘要，人类可一键回滚 |
| **L3** | 结构级 | 需确认 | Shot 拆分/合并/exit_to 变更/影响下游 ≥2 个 Shot | AI 诊断+建议方案+理由摘要；批量提交人类确认（**按章组织**，非按诊断类别）；人类可逐条审阅或全批通过；确认后系统串行执行 |
| **L4** | 方向级 | 停下来等待 | 章级约束/人物弧线/⭐⭐⭐ 元契约字段修改 | 不可批量批准（每条独立确认）；人类可指定自己的修复方案（非仅批准/否决 AI 方案） |

**硬规则安全网（不依赖 LLM 判断）**：

| 检测 | 规则 | 自动触发 |
|------|------|------|
| 连续红灯 | 同一 Shot 原契约重跑 ≥2 次仍红灯 | 升级 L3 |
| 触碰 ⭐⭐⭐ | 修约 diff 命中 identity/hard_boundaries/anti_reveal 字段 | 升级 L4 |
| 连锁影响 | 修约影响 ≥2 个下游 Shot 的 exit_to | 升级 L3（≥3 个 → L4） |
| Shot 拆分/合并 | structure_events 变更 | 升级 L4 |

**Repair 报告结构（按章组织）**：

```
第 18 章 [3 个 repair]
  Shot 18-04 [结构级] must_land 从"..."改为"..."
    影响：下游 18-05/06/07 的 exit_to 已自动重编译
  Shot 18-07 [零改动] 执行失败，原契约重跑通过（第 2 次）
  Shot 18-11 [风格级] anti_write 措辞优化，无下游影响
```

**审计标记**：
- 所有契约修改（含自动小修）→ `writing_contract_snapshots` 记录 before/after diff + 诊断理由
- `shot_revisions` 新增 `repair_audit_id` 外键
- 导出文件元数据含 `repair_count` / `auto_repair_count` / `human_confirmed_repair_count`

#### D3.3 事实锚点

每个绿灯 Shot 落库时，赛车场经理自动提取不可逆事实：

```json
{
  "anchor_id": "...",
  "shot_id": "...",
  "fact_type": "character_state",
  "fact": {"character": "阿坤", "fact": "右膝保鲜膜破裂，血水流出", "irreversible": true}
}
```

后续 repair 或新 Shot 的契约编译，必须通过事实锚点一致性检查——已跑绿灯 Shot 的事实不可被后续修改覆盖。

#### D3.4 模板复用

系列化项目创建模板，填槽即可实例化：

```bash
ink setup "背锅侠_001" --template "背锅侠_发动机_现代本土卷"
```

AI 架构师加载模板，填充 task/location/protagonist/life_echo 等槽位，编译全链契约。人类只需确认填槽是否正确。

---

### D4. 生产期契约锁定

`write run` 启动时创建不可变契约快照。生产期只能执行快照，不自动修改契约。

人物是否写偏由 AI 裁判、契约门控和后续 Chisel scan 判断；生产期只记录偏差，不改契约。

---

### D5. 正文落库 (v3.5)

AI 生产结果直接进入正文版本链。

- 绿灯/黄灯 winner 写入当前正文 revision。
- 红灯占位写入当前正文 revision。
- 后续修红/修黄通过新 revision 替换。
- 每个 revision 记录 `parent_revision_id`、`run_id`、`contract_id`、`text_hash_normalized`。

---

### D6. 红黄绿

保留黄灯。

```text
绿灯: 可用正文，事实锚点自动提取
黄灯: 可用但需观察/后续优化
红灯: 占位正文，后续诊断 + 修约 + 补写/重写
```

红灯粒度固定为 Shot。红灯必须写占位正文，不能留空。

#### D6.1 硬边界逃生舱 (D-4)

AI 裁判在裁决时发现 **契约层面无法解决的红灯**（如：hard_boundary 和 must_land 在给定构造进度下不可调和），AI 可以：

1. 写占位正文（保留上下文连续性）
2. 用 flag `requires_architect_review` 标识此 Shot
3. 附带简要分析数据包（"卡在哪里" / "哪两条约束冲突" / "AI 尝试了哪些路径"）
4. 继续后续 Shot 生产

结果：
- 全书生产不会阻塞在这个 Shot 上
- `write run` 结束时，`--summary` 渲染所有需要架构师重看的 Shot
- 人类收到 **Unresolvable Shot 清单**（含分析数据包）
- 被标记的 Shot 不进入 contract_snapshot history（不算落库）

---

### D7. 门控宽松度

生产期门控偏宽松。明显事实冲突、人物状态崩坏、时间线崩坏、voice phase 崩坏、无法衔接后文时红灯。

文学性不够、节奏偏弱、轻微声音偏移默认黄灯或放行，后续由 AI repair 和 Chisel 二次校准处理。

阈值由元契约的宽松度声明控制（非全局常量）。

---

### D8. 创意空间

不可放开：

- 事实。
- 人物状态。
- 时间线。
- 世界规则。
- 禁元。
- `exit_to`。
- anti_reveal 保护的信息。

可放开：

- 表达。
- 场景角度。
- 意象。
- 节奏。
- 尾钩。
- 身体感。
- 对话潜台词。

---

### D9. 精彩片段

精彩片段使用 `creative_mode = true` 和 no-crash contract。

`must_land` 在精彩片段中是评分项，不是一票否决项。

---

### D10. 写手池 (v3.5 核心升级)

#### D10.1 Writer Profile 系统

每个项目绑定一个或多个 writer profile，由 AI 架构师从元契约自动编译初版，人类微调。

```json
{
  "profile_id": "...",
  "project_id": "...",
  "system_prompt_template": "...",
  "voice_samples": [...],    // 正面样本
  "anti_samples": [...],     // 反面样本
  "temperature_range": {"default": 0.7, "creative": 0.85}
}
```

voice samples 三个来源：
1. 人在 setup 阶段提供的样章（最可靠）
2. 从已写正文中自动选取（高分 Shot 自动入池，Phase 2）
3. AI 架构师从元契约反推生成初版

#### D10.2 参考池与成长飞轮

```sql
writing_reference_pool
  ├── sample_id
  ├── project_id
  ├── sample_type            -- 'positive' | 'negative'
  ├── source                 -- 'human_provided' | 'high_score' | 'low_score' | 'manual'
  ├── source_shot_id
  ├── sample_text
  ├── annotation             -- 为什么好/为什么坏
  ├── tags_json              -- ["voice", "body_moment", "dialogue", "ai_flavor"]
  └── jury_score
```

成长飞轮：人类提供种子样章 → 写手生成 → 裁判评分 → 高分入 positive pool / 低分（带标注）入 negative pool → 下一次写手拿到更丰富的样本 → 质量提升 → 继续循环。

---

### D11. 裁判团 (v3.5 核心升级)

#### D11.1 裁判配置

采用 9 裁判团（6 基础 + 0-3 动态）。

动态裁判从系统级维度池中按元契约**自动激活**：

| 元契约特征 | 自动激活的裁判 |
|------|------|
| anti_reveal 列表非空 | 伏笔官 |
| 声明了主题 | 主题官 |
| 人物有弧线设计 | 弧线官 |
| 对话纪律严 | 对话官 |
| 有"身体时刻"要求 | 身体官 |
| 禁术语列表非空 | 术语官 |

裁判 prompt = 通用维度定义 + 本项目元契约相关子集 + voice samples。

#### D11.2 评分与阈值

裁判输出统一 0-100 分。红黄绿阈值由元契约的宽松度声明控制。

`close_call` 只做观察标记，不打断生产。

裁判失败时不补虚构分数。关键裁判不足时该 Shot 最高只能黄灯。

#### D11.3 精彩灯与坏味灯 (v3.5 新增)

在红黄绿之外，新增两级灯色体系——精彩灯（超越契约）和坏味灯（踩了反例）。两者各有三级。

**精彩灯**：绿灯的子集。契约履约 + 超越契约的文学亮点。裁判团共识触发（≥ 6 裁判标记 brilliance_marker），不能仅靠分数阈值。

| 级别 | 含义 | 触发 | 人类 |
|:---:|------|------|:---:|
| **A** | 局部亮——某句/某段超越契约 | 裁判团共识 ≥ 6 | 可选覆盖 |
| **A+** | Shot 级精彩——多维度同时超越 | 全部 9 裁判标记 + ≥ 2 维度 | 可选覆盖 |
| **S** | 最佳实践——可作为本书写作标准样本 | A+ + 人类主动确认 | **必须确认** |

精彩灯 Shot 必须附带详细标注（哪个维度、哪句话、为什么精彩）。自动入 `writing_reference_pool` positive pool + Character Writing Guide 的 `positive_samples`。报告 ⭐ 高亮。

**坏味灯**：黄灯的子集。不是"契约未履约"——是"写成了反例表里禁止的那个东西"。

| 级别 | 含义 | 触发 | 人类 |
|:---:|------|------|:---:|
| **B** | 轻度坏味——某句/某段踩了反例 | 禁元官或声音官标记 | 可选覆盖 |
| **Br** | 中度坏味——整段滑向禁止类型 | ≥ 3 裁判标记反例命中 | 可选覆盖 |
| **Bz** | 重度坏味——整个 Shot 写成了禁止的东西 | 全部裁判共识这是反例 | **必须确认** |

坏味灯 Shot 附带反例标注（踩了哪条反例、具体哪句话、应该怎么写）。Bz 级入反例库的样本对，反向写入 anti_patterns。

**状态机新增**：

> [已废弃] 旧版精彩/坏味灯状态机。v3.6 改为 brilliance_level / badsmell_level 正交附加字段（见 design.md §7 和 implementation-contract-v0.md §2.4）。

#### D11.4 全书后虚拟读者层 (Phase 2)

生产期裁判只判"能继续/不能继续"。全书完成后，虚拟读者池判"好不好"：

- 类型文学读者
- 严肃文学读者
- 节奏敏感读者
- 人物党读者
- 编辑型读者

虚拟读者不进红黄绿，进报告。

---

### D12. 上下文组装与提示词预编译 (v3.5 核心升级)

#### D12.1 编译一次，多次复用

提示词从全书→卷→章→Shot 层层下落编译，在 setup 阶段就完成。

赛车场经理 run 时：加载 static_prefix（setup 预编译），运行时装配 dynamic_assembly（fact anchors / previous shots / motif tracker）。

```sql
writing_shot_prompts
  ├── prompt_id
  ├── shot_id
  ├── run_id
  ├── prompt_hash             -- 版本校验和重放
  ├── compiled_prompt_text    -- 完整提示词
  ├── prompt_layers_json      -- 各层贡献占比
  ├── voice_samples_json      -- 正面样本
  ├── anti_samples_json       -- 反面样本
  └── created_at
```

#### D12.2 加载顺序 (recency effect 利用)

```
1. 前文正文（建立叙事连续性）
2. 人物状态快照 + 意象任务（建立事实约束）
3. Shot 契约（建立目标）
4. voice samples（建立风格参照）
5. 反例/偏法提醒（最后一秒的制动器）
```

#### D12.3 反例注入格式

反例不是抽象规则——是具体样本对：

```
❌ 坏："许念觉得自己被所有人推到了中间。"
✅ 好："群里安静了三秒。许念上一条'我来处理'下面，显示已读 17 人。没有人再接一句。"
```

#### D12.4 上下文版本控制

每个 Shot 的上下文写入 `writing_context_snaps`，`context_hash` 用于恢复时校验。

---

### D13. 后置改写

尾钩、过渡句、局部修句都是正文变更。所有正文变更必须在最终落库前跑最小门控。

---

### D14. 全书后处理

全书先生产完成，再进入：

```text
AI 诊断红灯原因
  → 区分"写手执行失败" vs "契约本身有问题"
  → 修约（按小/中/大修分级处理）
  → 重跑写手赛马
AI 优化黄灯
Chisel scan/report/fix
人类集中二次处理
```

---

### D15. CLI

```bash
# 前置沟通与契约落库
ink setup "分流"

# 系列化模板复用
ink setup "背锅侠_001" --template "背锅侠_发动机_现代本土卷"

# 全自动生产
ink run "分流" --chapter v01.c01
ink run "分流" --volume 1
ink run "分流" --from v01.c01 --to v01.c32

# 恢复中断
ink run "分流" --resume

# 查看状态与报告
ink status "分流"
ink contracts "分流"           # 从 DB 投影生成

# 全书完成后的 AI 自动修补
ink repair "分流" --red
ink repair "分流" --yellow

# Chisel 二次校准
chisel scan "分流" --depth standard
chisel report "分流"
chisel batch-fix "分流"
chisel export "分流" -o "分流_终版.md"
```

---

### D16. 类型自适应约束系统 (DeepStory 吸收)

#### D16.1 通用写作指南模板

所有项目继承统一的 `writing_novel_guide_template`。AI 架构师自动从人类对话和已有 md 文件中提取，缺项主动追问。缺项由 AI 自动补充默认值，不拒绝编译。人类可后续修改。

**通用必填字段（7 项，所有类型）**：

| 字段 | 类型 | 说明 |
|------|------|------|
| one_liner | string(≤150) | 一句话定义——这本书的核心 |
| genre_position | object | `is`（它是什么）+ `is_not`（它不是——反例比正向定义更重要）|
| core_question | string | 最高命题——这本书真正要问的问题 |
| constitution | object | `hard_boundaries`（≥3 条）+ `anti_patterns`（≥3 条）|
| structure_outline | object | 叙事层级 + 顶层数量 + 到人类确认层的完整大纲 |
| characters | array(≥1) | 主线人物：身份 + 核心冲突 + 弧线方向 + 语言特点 |
| style_guide | object | 叙事视角 + 基础腔调 + 禁止写法（≥3 条）+ 对话纪律 |

**强烈建议字段（4 项）**：

| 字段 | 说明 |
|------|------|
| voice_samples | 已写正文样章 ≥ 500 字——写手风格参照 |
| world_rules | 世界观/场域规则——关键场域的定义和功能 |
| core_motifs | 核心意象/物件清单及叙事功能 |
| unsolved_mysteries | 不解之谜保护列表——永远不能揭露的信息 |

#### D16.2 类型专属子架构

不同类型追加不同的专属字段。从六种类型（文学/悬疑/历史/科幻/职场/系列）的约束强度矩阵驱动：

| 维度 | 文学 | 悬疑 | 历史 | 科幻 | 职场 | 系列 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| 世界观 | ★★ | ★★★ | ★★★ | ★★★★★ | ★ | ★★ |
| 人物 | ★★★★ | ★★★★ | ★★★ | ★★★★ | ★★ | ★★★ |
| 结构 | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★★ |
| 主题 | ★★★★★ | ★★★ | ★★★ | ★★★★★ | ★★ | ★★★★ |
| 风格 | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★ | ★★★★ |

类型专属追加字段：

| 类型 | 专属追加字段 |
|------|------|
| **科幻** | 世界观物理规则（必填）、技术载体、技术的社会后果、去神秘化约束 |
| **文学** | 意象密度目标、身体时刻要求、留白规则、禁止解释约束 |
| **悬疑** | 线索投放表、红鲱鱼清单、不解之谜保护（严格模式）、揭秘节奏 |
| **历史** | 时代语言约束、古今同构映射、禁止炫历史约束、物质文化参照 |
| **职场** | 行业细部规则、场域清单、责任滑落机制、反爽文约束 |
| **系列/项目卷** | 发动机公式、模板复用规则、跨卷一致性约束 |

#### D16.3 角色定义升级：Character Writing Guide

角色定义从当前的"身份+核心冲突+弧线方向"升级为完整的角色写作指南：

```json
{
  "character_id": "...",
  "portrait": {
    "appearance": "外表与肢体特征",
    "body_memory": "身体习惯动作",
    "habitual_gesture": "标志性动作"
  },
  "voice": {
    "rhythm": "句子长度偏好",
    "silence_pattern": "沉默频率与含义",
    "lexicon": {
      "must_use": ["习惯用语"],
      "may_use": ["可接受的表达"],
      "never_use": ["禁止的表达——包括角色不会使用的词汇和句式"]
    }
  },
  "behavior_patterns": ["行为模式列表"],
  "recognition_traits": ["读者一眼能识别这个角色的特征"],
  "positive_samples": [{"text": "...", "annotation": "为什么好"}],
  "negative_samples": [{"text": "...", "annotation": "为什么错"}],
  "voice_contrast_with": {"character_id": "与另一个角色的声音对比"},
  "phase_switching": {
    "entry": {"voice_phase": "初期声音状态"},
    "active": {"voice_phase": "中期声音状态"},
    "exit": {"voice_phase": "后期声音状态"},
    "timeless": {"voice_phase": "跨阶段恒定的声音特征"}
  }
}
```

#### D16.4 场景姿态定义：ASTO 坐标

吸收 DeepStory 的 ASTO 系统作为场景级契约的可选字段：

```json
{
  "asto": {
    "phase": "chaos|order|flow|pulse|dissolution|return",
    "mode": "free|consensus|encoding|materialization|directed",
    "sequence_profile": {
      "awakening": 0.15,
      "perception": 0.15,
      "analysis": 0.15,
      "intervention": 0.20,
      "design": 0.15,
      "review": 0.10,
      "dissolution": 0.10
    }
  },
  "scene_position": "OPEN|BUILD|CLIMAX|BRIDGE|CLOSE|STANDALONE"
}
```

`scene_position` 驱动：
- 钩子契约注入（OPEN 激活首钩+尾钩，CLIMAX 激活全部三个钩子，BRIDGE 不激活）
- 质量检查点激活（CLIMAX 检查全部，BRIDGE 只检查连续性）
- Slot 注入范围（L5 约束层按 position 开关）

#### D16.5 层级可折叠

编译链支持可选层级折叠。不是每个项目都需要所有层级：
- 《背锅侠》卷→集：无需"章"层，L3 折叠
- 《分流》全书→卷→章→Shot：全层级展开
- 《签》全书→部→场→节：无需"卷"层

折叠规则：AI 架构师在结构识别阶段判断——如果两个相邻层级的功能重叠 ≥ 60%，则折叠低层。

#### D16.6 Universal Contract Header

从 DeepStory 吸收——所有层级契约共享统一头部：

```
contract_id / level / node_key / title / version / status / 
parent_id / child_range / genre / created_by / human_approved / timestamps
```

差异在 body：元契约 body = 10 子类，Shot 契约 body = must_land + anti_write + exit_to + ASTO + voice_phase + 意象任务。

#### D16.7 Slot 映射规则

元契约十子类到 DeepStory L5 约束 Slot 的对应关系——确保提示词编译时有确定性的数据流：

| 元契约子类 | → L5 Slot | 注入方式 |
|------|------|------|
| identity | L101 Writer Identity | 系统提示词固定层 |
| hard_boundaries | L505 Scene-specific taboos | 有冲突风险时注入 |
| anti_reveal | L505 Taboos（扩展） | 匹配到涉及场景时强制注入 |
| anti_patterns | L507 Scene anti-examples | 按场景类型匹配 |
| style_locks | L503 Style iron rules | 全书固定，每 Shot 注入 |
| creative_zones | L509 Scene best examples | 精彩片段注入更丰富的正面样本 |

---

### D17. 多 POV 声音路由 (v3.6, D-5)

#### D17.1 POV 角色声明

`narrative_voice` 子类包含 `pov_characters` 列表：

```json
{
  "pov_characters": [
    {
      "character_id": "su_ran",
      "role": "primary_pov",
      "voice_style": "白描摄像机",
      "dominant_volumes": ["v01", "v03", "v04"]
    }
  ]
}
```

#### D17.2 卷级 primary_pov 路由

`structure_rules` 中声明每卷的默认 POV 角色：

```json
{
  "volume_pov_routing": {
    "v01": {"primary_pov": "su_ran", "note": "苏然视角，鱼嘴现场"},
    "v03": {"primary_pov": "su_ran", "note": "城市实验室"},
    "v04": {"primary_pov": "su_ran", "note": "评估团"}
  }
}
```

#### D17.3 Shot 契约继承

当项目声明了多个 POV 角色时，Shot 契约束 `primary_pov` 从卷级契约继承。

Prompt 编译注入 `primary_pov` 对应的 Character Writing Guide 中的 voice 配置（节奏、词库、感官偏好、行为模式）和 positive/negative samples。

POV 路由不仅改变 AI 的"角色扮演"——它改变 Shot 契约束中 style_locks 的**释义**。同样的 `style_locks` 条目，不同 POV 角色释义不同。

#### D17.4 与已有系统的兼容

POV 去重：如果 primary_pov 和 narrative_voice 中的叙述者一致，两者引用同一个 Character Writing Guide 实例，不维护两份副本。

---

### D18. 意象密度上限 (v3.6, D-6)

#### D18.1 density_policy 字段

`motif_system` 子类包含 `density_policy`：

```json
{
  "motif_system": {
    "elements": [...],
    "density_policy": {
      "max_per_shot": 2,
      "max_per_chapter": 6,
      "max_per_volume": 20,
      "min_shot_gap": 1,
      "exclude_contexts": ["action_climax", "exposition_dump"],
      "mutual_exclusion": [
        {"pair": ["鱼碑", "盖碗茶"], "min_gap_shots": 3}
      ]
    }
  }
}
```

#### D18.2 密度计数

- Shot 级意象计数 = 该 Shot 的 motif_system 分配数
- 编译阶段执行硬计数检查，超限则 rebalance（推迟到后续符合 min_gap 的 Shot）
- `mutual_exclusion`：指定的意象对不得出现在同一 Shot，且必须间隔 ≥ min_gap_shots

#### D18.3 密度上限仅做硬计数

密度上限不涉及 LLM 裁决。AI 架构师在编译阶段执行：
1. 分配意象到 shot_context
2. 执行硬计数检查（max_per_shot / max_per_chapter / mutual_exclusion）
3. 超限则在上限内 rebalance

阈值 0 表示该层级关闭密度约束（如 `max_per_volume: 0`）。

---

### D19. 精彩灯与坏味灯完全正交 (v3.6, D-2)

#### D19.1 同一 Shot 双灯可能

同一 Shot 可以同时持有精彩灯和坏味灯。例如：某个 Shot 整体精彩（A 级），但有一段对话滑向了反例（B 级）。

#### D19.2 双灯记账

Shot 状态独立记录：
- `brilliance_level`: null | A | A+ | S
- `badsmell_level`: null | B | Br | Bz

两者互不降级。人类可看到完整质量剖面而非单一分级。

#### D19.3 暂不入 positive pool

精彩灯 Shot **暂不**自动入 `writing_reference_pool`（Phase 2 启动自动收集）。Phase 1 仅记录标注，不写入 pool。

暂不入池逻辑：
- 绿灯入 positive pool 需逐条确认
- 黄灯入 negative pool 需逐条确认
- 精彩灯/坏味灯 Shot 额外标注"建议入池"，人类在全书 production report 中统一审批

极黑区自由写手不检查坏味灯——它只按 no-crash contract 工作。

---

### D20. AI Flavor 检测独立于坏味灯 (v3.6, D-2)

AI Flavor 标记保留在禁元官/声音官维度的常规裁决中（D11.3 精彩坏味灯表），不进入坏味灯状态机。

理由：坏味灯专注"反例匹配"（anti_patterns），AI Flavor 是风格质量问题，两者检测维度不同。混入坏味灯会导致 false positive。

#### D20.1 AI Flavor 融入角色写作指南的负面样本

AI Flavor 的检测结果注入 Character Writing Guide 的 `negative_samples`。长期效果优于红黄绿裁决中的单次扣分。

---

### D21. 决策审计 (v3.6)

| 决策 ID | 状态 | 来源 | 简述 |
|------|:---:|------|------|
| D-1 | ✅ Applied | role-system v3.6 | 元契约 10 子类字段扩展：thematic_core / confidence / release_window / emo_state / density_policy / POV 角色列表 |
| D-2 | ✅ Applied | role-system v3.6 | 精彩坏味正交 + 暂不入参考池 + AI Flavor 检测独立于坏味灯 |
| D-3 | ✅ Applied | role-system v3.6 | 四层 repair 框架：零改动 / 风格级 / 结构级 / 方向级 + 升级规则 + 按章批量确认 + 审计 diff |
| D-4 | ✅ Applied | role-system v3.6 | 硬边界逃生舱：requires_architect_review flag + 分析数据包 + Unresolvable Shot 清单 |
| D-5 | ✅ Applied | role-system v3.6 | 多 POV 声音路由：primary_pov 声明 + 卷级路由 + Shot 契约束继承 + style_locks 释义按 POV 切换 |
| D-6 | ✅ Applied | role-system v3.6 | 意象密度上限：density_policy + 硬计数 + rebalance + mutual_exclusion 互斥对 |

---

## 3. Phase 1 实现范围

1. 项目结构自适应（MNU + layer index + human_confirm_layer + 层级可折叠）
2. 通用写作指南模板（7 必填 + 4 建议 + AI 主动提取 + 缺项追问）
3. 类型自适应子架构（6 种类型的约束强度矩阵 + 专属字段追加）
4. 角色写作指南（Character Writing Guide，含肖像 + 正反样本 + 词库 + 节奏 + 阶段切换）
5. 元契约 10 子类存储（identity / hard_boundaries / anti_reveal / anti_patterns / narrative_voice / style_locks / structure_rules / creative_zones / motif_system / world_knowledge）
6. Universal Contract Header（所有层级统一头部，差异在 body）
7. 契约编译链（解析→分配→细化→冲突检测→落库，anti_write 先展开）
8. ASTO 坐标 + scene_position（场景姿态可选字段 + 位置驱动检查点和钩子注入）
9. Slot 映射规则（元契约十子类 → L5 约束 Slot 的确定性数据流）
10. Shot 契约继承链 + 树状继承摘要
11. 契约生命周期状态机（draft → locked → repairing → evolving）
12. 事实锚点自动提取
13. Writer profile + 参考池（手动种子，Phase 2 自动收集）
14. 裁判维度池（元契约自动激活动态裁判 + 阈值可配置）
15. 上下文预编译入库（writing_shot_prompts + writing_context_snaps）
16. Repair 诊断 + 修约 + 重跑
17. 模板复用系统（writing_contract_templates + 填槽实例化）
18. DB schema：writing_novel_guide_template / writing_meta_contract / writing_character_guides / writing_shot_contracts / writing_shot_prompts / writing_writer_profiles / writing_reference_pool / writing_jury_config / writing_fact_anchors / writing_contract_templates / writing_context_snaps / writing_sessions / writing_run_snapshots / writing_drafts / writing_jury_scores / writing_deviation_notes
19. 细粒度状态机 + idempotency key
20. 测试：test_write_contract_compiler.py / test_write_contract_lifecycle.py / test_write_context_assembler.py / test_write_jury.py / test_write_pipeline_recovery.py / test_write_storage.py / test_write_cli.py
21. 四层 repair 框架（L1-L4 + 升级规则 + 硬规则安全网 + 按章批量确认 + repair_audit）
22. 硬边界逃生舱（requires_architect_review flag + 分析数据包 + Unresolvable Shot 清单）
23. 多 POV 声音路由（primary_pov 声明 + 卷级路由 + Shot 契约束继承 + style_locks 释义按 POV 切换 + POV 去重）
24. 意象密度上限（density_policy + 硬计数检查 + rebalance + mutual_exclusion 互斥对）
25. D-1 元契约字段扩展（thematic_core / confidence / release_window / emo_state / density_policy / POV 角色列表）
26. D-2 精彩坏味正交 + 暂不入参考池 + AI Flavor 检测独立于坏味灯 + AI Flavor → 角色写作指南 negative_samples
27. 决策审计文档（D-1 到 D-6 审计记录）
28. DB schema 新增：writing_repair_audit（repair_audit_id / contract_id / diff / diagnosis / layer）+ writing_unresolvable_shots（shot_id / reason_packet / architect_review_status）+ writing_pov_routing（project_id / volume_key / primary_pov / voice_config_ref）

---

## 4. 验收标准

- AI 架构师能自动从人类对话和已有 md 文件提取通用写作指南要素（7 必填 + 4 建议）
- 缺项时主动追问，缺项由 AI 自动补充默认值，不拒绝编译。人类可后续修改。
- 类型自适应子架构：6 种类型的约束强度矩阵 + 专属字段追加
- 角色定义升级为 Character Writing Guide（肖像 + 正反样本 + 词库 + 阶段切换）
- ASTO 坐标 + scene_position 作为场景可选字段
- 层级可折叠（编译链自动识别是否折叠中间层）
- Universal Contract Header 统一所有层级契约存储格式
- Slot 映射规则：元契约十子类 → L5 Slot 确定性数据流
- 项目结构自适应，不硬编码四级
- 元契约 10 子类完整落库
- 编译链可重放（同一输入 → 同一契约快照 hash）
- 继承链可追溯（每个 Shot 契约标注继承来源）
- 硬边界不可变，意象分配可重分配
- 红灯先诊断后修约，修约分级处理
- 事实锚点自动提取，跨 Shot 一致性检查
- Writer profile 从元契约编译初版
- 角色写作指南进入 writer profile 作为 POV 角色的标准配置
- 裁判维度由元契约自动激活
- static_prefix 预编译入库 + dynamic_assembly 运行时装配
- 模板可复用，填槽实例化
- 生产期不打断人类
- AI 写作产出直接进入正文版本链
- 任意当前正文能从 DB3 revision 链追踪来源
- 红灯占位能支撑后续 Shot 继续生产
- 全书完成后自动生成 red/yellow repair 队列
- 四层 repair 按 L1-L4 分级处理，L1 不需要告知人类，L3 按章批量确认
- 硬规则安全网无需 LLM 判断：连续红灯升级 / ⭐⭐⭐ 触碰升级 / 连锁影响升级
- 硬边界逃生舱：AI 发现不可调和冲突时写入 requires_architect_review + 分析数据包，不阻塞生产
- POV 路由：Shot 契约束正确继承 primary_pov，style_locks 释义按 POV 角色切换
- 意象密度上限：编译阶段硬计数检查 + 超限 rebalance + mutual_exclusion 互斥对硬拦截
- D-2 精彩坏味正交：同一 Shot 可同时持有 brilliance_level 和 badsmell_level
- AI Flavor 检测结果进入 Character Writing Guide 的 negative_samples
- Phase 1 精彩灯暂不入 writing_reference_pool（Phase 2 启动批量收集）
- 元契约束 D-1 ~ D-6 审计记录随文件维护

---
Doc version: v3.6 (2026-06-16)
Based on: role-system v3.6 / decisions D-1~D-6
Changes: 契约编译 7→8 步 + 四层 repair 替换三阶修约 + 硬边界逃生舱 + 多 POV 声音路由 + 意象密度上限 + D-2 精彩坏味正交
Status: authoritative for write module — full spec appendix: D1~D21 + acceptance criteria
