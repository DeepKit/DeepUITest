# InkFlow 悬疑引擎 v1 — 技术设计

> 版本：v1.1
> 创建：2026-06-22
> 基于：9 位专家评估（第一轮 4 位 + 第二轮 5 位）
> 状态：已实施核心闭环。v1.1 更新：悬疑从“默认固定维度”调整为 shot 类型职责；只有悬疑/章末/信息差 shot 才启用 `suspense_effectiveness` / `hook_transition` 类型裁判。普通 shot 不因没有悬疑而扣分。

---

## 0. 设计决策记录

### 0.1 核心洞察

经过 9 位专家（小说悬疑工程学、AI 系统架构、文学创作实践、产品设计、计算文学、博弈论/机制设计、数据工程、认知科学/NLP 评估、系统可靠性工程）独立评估，原方案被判定为**方向正确但本体论有缺陷**。

### 0.2 否决的原方案

| 原方案 | 否决理由 | 来源 |
|--------|---------|------|
| 6 维度 × 0-100 滑块 | 混同频率与强度；用表面特征度量悬疑而非悬疑本质 | 专家一、四 |
| 独立 Stage 2 Metadata Extractor | 新增 LLM 调用阶段；与现有 Jury/L4 职责重叠 | 专家二、三、四 |
| 新建 `writing_chapter_metadata` 表 | 数据分散；扩展现有表更优 | 专家三 |
| 章末钩子自动重写最多 3 次 | 破坏叙事节奏；重试叠加风险 | 专家二、五 |
| 全局悬疑参数 | 悬疑是局部的，不同章节需���不同强度 | 专家二 |

### 0.3 采纳的替代方案

| 替代方案 | 来源 |
|---------|------|
| 三不对称本体论（信息不对称 × 时间不对称 × 后果不对称） | 专家一 |
| Jury 第 4 维度 `suspense_effectiveness` | 专家二 |
| Shot-level 悬疑蓝图 | 专家二 |
| 信息差生命周期追踪 | 专家一、三 |
| 评估分层（机械 90% + LLM 10%） | 专家四 |
| 全局重试预算 + 熔断器 | 专家五 |

---

## 1. 悬疑本体论：三个不对称

### 1.1 定义

悬疑的本质不是"表面修辞特征"，而是**三个不对称在读者心智中产生的张力**：

```
                                ┌─────────────────────────────┐
                                │     读者心智中的张力        │
                                │                             │
                                │  信息不对称                  │
                                │  ┌─────────────────────┐    │
                                │  │ 读者知道 ≠ 角色知道 │    │
                                │  └─────────────────────┘    │
                                │           ×                  │
                                │  时间不对称                  │
                                │  ┌─────────────────────┐    │
                                │  │ 读者预期 ≠ 实际发生 │    │
                                │  └─────────────────────┘    │
                                │           ×                  │
                                │  后果不对称                  │
                                │  ┌─────────────────────┐    │
                                │  │ 读者感知 ≠ 角色感知 │    │
                                │  └─────────────────────┘    │
                                └─────────────────────────────┘
```

### 1.2 三个不对称与六个表面特征的关系

| 不对称 | 子维度 | 表面特征映射 | 检测方式 |
|--------|--------|------------|---------|
| **信息不对称** | 读者知道什么 / 角色知道什么 | 信息差频率、预埋密度 | 结构层追踪 |
| **时间不对称** | 预期时间 / 实际时间 | 章末钩子、解释句禁令 | 机械层正则 |
| **后果不对称** | 真实后果 / 角色感知 | 伤害预演、数字体温 | 机械层正则 + 结构层 |

### 1.3 悬疑强度计算

```
悬疑强度 = α × 信息不对称 + β × 时间不对称 + γ × 后果不对称

其中 α, β, γ 由悬疑预设决定：
- 制度悬疑：α=0.5, β=0.3, γ=0.2（信息差驱动）
- 心理惊悚：α=0.2, β=0.3, γ=0.5（后果感知驱动）
- 本格推理：α=0.6, β=0.2, γ=0.2（信息编排驱动）
- 文学小说：α=0.3, β=0.4, γ=0.3（均衡）
```

---

## 2. 架构：类型职责裁判 + 悬疑蓝图

### 2.1 不新建独立 Extractor

**悬疑评估不通过独立 Stage 2 实现，而是通过扩展现有系统：**

```
旧方案（被否决）：
  Stage 1 Generator → Stage 2 Extractor → 评估报告 → 不达标重写

新方案（采纳）：
  Writer Race → Jury 评分（含 suspense_effectiveness 维度）
    → 悬疑感强的草稿自然获得更高分
    → Winner 自动更有悬疑感
    → 不新增 pipeline 阶段
```

### 2.2 悬疑类型维度

v17 后，悬疑不再作为每个 shot 的默认文学维度。悬疑只在 `shot_profile.types` 含 `suspense` 时启用：

| 类型职责 | 维度 | 评估内容 |
|----------|------|----------|
| `suspense` | `suspense_effectiveness` | 信息差、时间差、后果差是否产生张力 |
| `hook` | `hook_transition` | 章末/转折是否留下有效牵引 |
| `blank_space` / `creative_entry` | `unexpected_value` | 留白或创意偏离是否有价值 |

类型维度是通过门槛，不进入文学 9 维 trimmed mean。类型职责未启用时，不打该类型分，也不扣分。

`suspense_effectiveness` 评分 prompt：

```
你是一位悬疑文学评审。请从"悬疑效果"维度评价以下小说正文。

评估要点：
1. 信息不对称：读者是否比角色知道得更多？这种差距是否产生了紧张感？
2. 时间不对称：是否有未完成的事件或未解答的问题让读者必须继续阅读？
3. 后果不对称：读者是否感知到角色尚未感知到的危险或后果？

请给出 0-100 分的评分，并简要说明理由。

评分参考：
- 90-100: 强烈的不对称张力，读者无法停止阅读
- 80-89: 明显的不对称，有持续的紧张感
- 70-79: 有一些不对称，但不够强烈
- 60-69: 缺乏不对称，读者没有紧迫感
- 0-59: 完全没有悬疑感
```

### 2.3 悬疑蓝图（Suspense Blueprint）

悬疑配置是 **shot-level** 的，不是全局的。在 `contract-draft.yaml` 中新增 `suspense_blueprint`：

```yaml
suspense_blueprint:
  # 全书核心悬疑问题
  global_question: "阿坤的膝盖还能撑多久？系统会不会把他完全推到外江？"

  # 每章张力目标和悬疑策略
  chapters:
    v01.c02:
      tension_target: 45        # 0-100，本章目标张力值
      info_gap_action: create   # create | maintain | reinforce | reveal
      hook_type: action_interrupt  # action_interrupt | silence | cliffhanger | information_hook
      info_gaps_to_create:       # 本章要创建的信息差
        - "苏然发现了边界线每年外推6%，但其他角色不知道"
      info_gaps_to_reinforce: []  # 本章要强化的信息差
      info_gaps_to_reveal: []     # 本章要揭露的信息差

  # 悬疑预设（可被 chapter 级覆盖）
  preset: institutional_suspense  # 制度悬疑
```

### 2.4 悬疑预设

5 个命名预设，每个预设定义 α/β/γ 权重 + 默认参数��

| 预设 | α | β | γ | 适用 |
|------|:---:|:---:|:---:|------|
| `literary_tension` | 0.3 | 0.4 | 0.3 | 文学小说 |
| `institutional_suspense` | 0.5 | 0.3 | 0.2 | 制度悬疑 |
| `psychological_thriller` | 0.2 | 0.3 | 0.5 | 心理惊悚 |
| `whodunit` | 0.6 | 0.2 | 0.2 | 本格推理 |
| `slow_burn` | 0.4 | 0.4 | 0.2 | 慢燃悬疑 |

---

## 3. 信息差生命周期追踪

### 3.1 数据模型

新增 `writing_information_gaps` 表：

```sql
CREATE TABLE writing_information_gaps (
    gap_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(project_id),
    run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
    description TEXT NOT NULL,              -- 信息差描述
    reader_knows TEXT NOT NULL,             -- 读者知道什么
    character_knows TEXT NOT NULL,          -- 角色知道什么
    created_shot_id TEXT,                   -- 在哪个 Shot 被创建
    reinforced_shot_ids TEXT,               -- 在哪些 Shot 被强化 (JSON array)
    revealed_shot_id TEXT,                  -- 在哪个 Shot 被揭露
    next_gap_id TEXT,                       -- 揭露后产生的新信息差
    status TEXT NOT NULL DEFAULT 'pending'  -- pending | active | reinforced | revealed | resolved
        CHECK (status IN ('pending', 'active', 'reinforced', 'revealed', 'resolved')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### 3.2 生命周期

```
pending → active → reinforced → revealed → resolved
                                         ↓
                                    new gap (next_gap_id)
```

每个 Shot 生成时，prompt 中注入当前活跃的信息差列表。

---

## 4. 评估分层

### 4.1 机械层（L0，正则/规则，~90% 检查）

| 检查项 | 方式 | 零 LLM 调用 |
|--------|------|:---:|
| 章末是否以动作/物件/沉默结尾 | 正则：`_check_closing_sentence()` | ✅ |
| 数字后 50 字内是否有人或物 | 正则：数字 + 后续 50 字扫描 | ✅ |
| 是否包含解释性从句 | 正则：`_CLOSING_EXPLANATION_PATTERNS` | ✅ |
| 是否包含禁止词 | 正则：`_CLOSING_SENSORY_KEYWORDS` 反向 | ✅ |

### 4.2 结构层（L1，LLM，~10% 抽检）

| 检查项 | 方式 | 触发 |
|--------|------|------|
| 信息差是否被有效创建 | Jury `suspense_effectiveness` 维度 | 每个 Shot |
| 罗丝是否产生了"必须翻下一页"的冲动 | Jury `suspense_effectiveness` 维度 | 每个 Shot |
| 抽检 Extractor 准确性 | LLM 深度评估 | 每 10 个 Shot 抽 1 个 |

### 4.3 悬疑评估基准

`tests/fixtures/suspense_benchmark/` 下包含：
- `high_suspense/` — 10 段高悬疑文本（人工标注）
- `low_suspense/` — 10 段低悬疑文本（人工标注）
- `pseudo_suspense/` — 10 段伪悬疑文本（表面有钩子但实质无悬疑）
- `benchmark.py` — 评估脚本，对比 Jury `suspense_effectiveness` 评分与人工标注

---

## 5. 工程可靠性

### 5.1 全局重试预算

每个 Shot 最多 8 次 LLM 调用（含所有阶段）：

```
Writer Race (2) + 阈值不够 Redo (2) + Smart-Redo (L0+L1+L2 = 4) = 8
```

章末钩子不再触发独立重写。不达标 → 注入下一个 Shot 的上下文。

### 5.2 熔断器

```
同一失败类型连续 3 次 → 熔断，标记 done_red_permanent
不同失败类型 → 允许重试，共享预算
```

### 5.3 failure_signature 传递

每次重试记录 `failure_signature`（结构化失败原因），后续重试读取并调整策略。

### 5.4 幂等性

所有 LLM 调用（含 Jury 第四维度）写入 `model_attempts` 表，带 `idempotency_key`。

---

## 6. 实施计划与当前状态

### Phase 1：基础建设（0 新表）

| 文件 | 内容 | 状态 |
|------|------|:---:|
| `contract-draft.yaml` | 新增 `suspense_blueprint` 示例 | ✅ |
| `architect_gate.py` | `_check_closing_sentence()` 增强；提取数字体温、解释句 | ✅ |
| `jury_service.py` | 新增 `suspense_effectiveness` 维度 | ✅ |
| `prompt_compiler.py` | 从 `suspense_blueprint` 注入悬疑指令 | ✅ |
| `quality_controller.py` | 全局重试预算 + 熔断器 | ⏳ |

### Phase 2：结构悬疑（2 个新文件，1 新表）

| 文件 | 内容 | 状态 |
|------|------|:---:|
| `information_gap_tracker.py` | 追踪信息差生命周期 | ✅ |
| `schema.sql` + `migration.py` | 新增 `writing_information_gaps` 表 | ✅ |
| `suspense_profile.py` | 5 个命名预设 → 映射到 suspense_blueprint | ✅ |

### Phase 3：评估闭环（长期）

| 文件 | 内容 | 状态 |
|------|------|:---:|
| `tests/fixtures/suspense_benchmark/` | 30 段标注文本 + 评估脚本 | ⏳ |
| `writing_reference_pool` | 新增 category, trigger_pattern, severity 字段 | ⏳ |

---

## 7. 与现有系统的集成点

| 现有系统 | 集成方式 |
|---------|---------|
| 契约编译链 | `suspense_blueprint` 作为 `contract-draft.yaml` 的子字段 |
| 写手赛马 | Jury 新增 `suspense_effectiveness` 维度 |
| 架构师门控 | L4 扩展 `_check_closing_sentence()` 输出 |
| 上下文组装 | 信息差列表注入 prompt |
| 状态机 | 不新增状态，利用现有 green/yellow/red |
| 崩溃恢复 | 信息差状态写入检查点 |
| 反例系统 | 独立于悬疑引擎，反例是事实一致性问题 |
