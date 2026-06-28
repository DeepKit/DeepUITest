# InkFlow 三棵树架构（3-Tree Architecture）

> 版本：v1.1（2026-06-27）
> 决策编号：ARCH-12
> 依赖：8 层层级设计（`design-8layer-hierarchy.md`）
> 状态：已实施（Schema v8 起落地；ARCH-13 补充正文真相源；ARCH-4 补充 L0 宪法指针；v1.2 补充 accepted canonical selector；v1.3 补充 run attempt shot identity；v1.4 补充 book_run 编排层）

---

## 1. 设计动机

InkFlow 的数据库是**唯一真相源**（design.md §1 不可变原则 #1）。但在 v3.8 之前，契约数据散落在三张互不关联的表中，没有树结构：

| 问题 | 证据 |
|------|------|
| 没有契约树 | `writing_shot_contracts.parent_contract_id` 是死字段，从未写入 |
| 没有故事树 | `writing_project_structure` 是骨架但没有内容，没有角色状态/伏笔/时间线 |
| 没有执行树 | `writing_shots`/`writing_drafts` 散落在 run 里，没有层级关系 |
| YAML 伪根节点 | `contract-draft.yaml` 把 L0 全书宪法和 L2 章事件打平在一起，承担根节点角色 |
| L0/L0.5 缺失 | `volume_constraints` 是幽灵参数，接口预留但从未填充 |

**核心结论**：InkFlow 需要 **3 棵树**，每棵树都遵循 **8 层标准金字塔**（空则占位），共用 **4 张数据库表**。

---

## 2. 三棵树总览

```
契约树 (Contract Tree)        故事树 (Story Tree)          执行树 (Execution Tree)
"应该怎么写，哪些不能破"        "这本书里有什么"             "这次 run 干了什么"
设计时 · 版本化 · 跨 run 稳定   追加式 · 内容展开            per-run · 每次重新生成
                                                                        
L0 全书宪法                   L0 全书定义                  L0 项目运行
L1 部（占位）                  L1 部（占位）                 L1 部（占位）
L2 卷部节奏                   L2 卷定义                    L2 卷运行
L3 弧（占位）                  L3 弧（占位）                 L3 弧（占位）
L4 章节奏                     L4 章定义                    L4 章运行
L5 节（占位）                  L5 节（占位）                 L5 节（占位）
L6 场景合约                   L6 场景内容                  L6 场景执行
L7 段落规则                   L7 段落（完稿后）              L7 段落产出
```

---

## 3. 8 层标准金字塔（三棵树共用）

| 层级 | 英文代码 | 中文名 | 契约树节点内容 | 故事树节点内容 | 执行树节点内容 | 《分流》是否展开 |
|------|----------|--------|--------------|--------------|--------------|----------------|
| L0 | `work` | 全书 | identity, hard_boundaries, style_locks, motif_system, suspense_config | 书名, 主题, 时代, 全书角色表 | run_id, 契约版本指针, 开始时间 | ✅ 展开 |
| L1 | `part` | 部 | 占位 | 占位 | 占位 | ⬜ 折叠（占位） |
| L2 | `volume` | 卷 | chapter_roles, deviation_range, pov_routing, volume_arc | 卷名, 时间跨度, 主POV, 本卷主线 | 卷运行状态, 卷质量色标 | ✅ 展开 |
| L3 | `arc` | 弧 | 占位 | 占位 | 占位 | ⬜ 折叠（占位） |
| L4 | `chapter` | 章 | phase分配, deviation_budget, chapter_intent | 章名, 事件列表, POV, 时间锚点 | 章节奏结果, 章质量色标 | ✅ 展开 |
| L5 | `section` | 节 | 占位（shot内部细分用） | 占位 | 占位 | ⬜ 折叠（占位） |
| L6 | `scene` | 场景 | hard_facts, must_land, anti_write, motif_tasks | pov角色, 事件, 在场角色, 状态diff | shot状态, prompt, 草稿列表 | ✅ 展开 |
| L7 | `paragraph` | 段落 | 段长上限, 感官密度下限 | 段落文本（完稿后回填） | 段落级校验结果 | ⬜ 折叠（完稿后展开） |

---

## 4. 树1：契约树（Contract Tree）

> 治理之树。回答"应该怎么写，哪些不能破"。

### 4.1 特征

- **版本化**：宪法可以升级，章合约可以独立修改，每次修改生成新版本
- **设计时产物**：跨 run 稳定，不随 run 变化
- **层级继承**：子层继承父层约束，`is_collapsed=1` 的层自动继承（L1/L3/L5/L7）
- **冲突规则**：子层不得违反父层硬约束；若有矛盾，冲突向上报告，最多重试 3 次

### 4.2 每层存什么（contract_body_json）

**L0 全书宪法**：
```json
{
  "identity": { "title": "分流", "genre": "文学小说", "setting": "成都·当代" },
  "narrative_voice": { "pov": "多POV·限制性第三人称" },
  "hard_boundaries": { "world_rules": ["系统不恶意", ...] },
  "style_locks": { "opening": "身体时刻开场", ... },
  "anti_patterns": { "avoid": ["概念总结性结尾", ...] },
  "world_knowledge": { "locations": [...], "season": "十二月" },
  "motif_system": { "primary": ["膝盖", "都江堰分流", ...] },
  "suspense_config": { "information_gap": [...] }
}
```

**L2 卷部节奏**：
```json
{
  "volume_arc": "建立→四线并行→交织→第一次分流",
  "chapter_roles": { "c01": "baseline", "c02": "纠缠", "c03": "加深", ... },
  "deviation_range": [0.25, 0.65],
  "temperature": 0.7,
  "pov_routing": { "阿坤": 0.35, "白英": 0.25, "苏然": 0.25, "韩教授": 0.15 }
}
```

**L4 章节奏**：
```json
{
  "chapter_intent": "让四条线在同一个冬日内首次交错",
  "events": [ { "shot": "s01", "pov": "阿坤", "event": "绕城高速" }, ... ],
  "shot_rhythm": [
    { "shot_index": 1, "narrative_phase": "pulse", "deviation_budget": 0.30, "shot_role": "anchor" },
    ...
  ]
}
```

**L6 场景合约**：
```json
{
  "hard_facts": ["阿坤骑摩托车出绕城高速", ...],
  "soft_constraints": ["冬晨·雾地面升起", ...],
  "reference": ["阿坤的膝盖状态（来自 c01.s01）", ...],
  "must_land": ["建立绕城=边界的物理感知", ...],
  "anti_write": ["不能让阿坤内心独白超过3句", ...],
  "motif_tasks": [{ "motif": "膝盖", "action": "首次出现·物理损伤" }],
  "pov_routing": { "pov": "阿坤", "voice_style": "体感主导·短句·不反思" }
}
```

---

## 5. 树2：故事树（Story Tree）

> 内容之树。回答"这本书里有什么"。

### 5.1 特征

- **追加式**：故事内容随创作展开，不回头修改（与契约树的版本化不同）
- **角色状态传播**：每个节点记录结束时各角色的认知/情绪/秘密持有状态
- **伏笔追踪**：每个节点记录伏笔操作（plant/resolve/update）
- **时间线锚点**：每个节点绑定故事内时间

### 5.2 每层存什么（story_content.content_body_json）

**L0 全书**：
```json
{
  "title": "分流",
  "thematic_core": "算法是文明的隐藏语言",
  "pov_characters": ["阿坤", "白英", "苏然", "韩教授"],
  "time_span": "当代·成都"
}
```

**L2 卷**：
```json
{
  "volume_title": "骑手与系统",
  "time_range": "十二月·第一周至第三周",
  "main_pov": "阿坤",
  "volume_arc_summary": "阿坤从被动承受者到第一次意识到系统在定义他的存在范围"
}
```

**L4 章**：
```json
{
  "chapter_title": "四线交织",
  "timeline_anchor": "十二月第二个星期四",
  "events_summary": "四条线在同一冬日内首次交错",
  "character_states_on_entry": { "阿坤": { "膝盖": "恶化", "信用分": 58 } },
  "character_states_on_exit":  { "阿坤": { "膝盖": "恶化", "信用分": 55 } }
}
```

**L6 场景**：
```json
{
  "pov": "阿坤",
  "event": "阿坤骑摩托车出绕城高速，遇到拖行李箱的年轻人",
  "present_characters": ["阿坤", "年轻人"],
  "foreshadow_ops": [
    { "action": "plant", "name": "代际镜像", "planned_resolve": "v01.c05" }
  ],
  "state_diff": { "阿坤": { "emotion": "机械→微酸", "knowledge": "+年轻人=四年前的自己" } }
}
```

---

## 6. 树3：执行树（Execution Tree）

> 生产之树。回答"这次 run 干了什么，产出了什么"。

### 6.1 特征

- **per-run**：每次 run 生成一棵新的执行树
- **回溯链**：每个执行节点通过 `source_version_id` 指回契约树（"这次用的宪法v1"）
- **质量追踪**：每个节点有自己的质量色标（quality_color）

### 6.2 每层存什么（execution_records.record_body_json）

**L0 项目运行**：
```json
{
  "run_id": "run_001",
  "started_at": "2026-06-21T10:00:00",
  "constitution_version": 1,
  "target_chapter": "v01.c02"
}
```

**L4 章运行**：
```json
{
  "chapter_key": "v01.c02",
  "rhythm_analysis": { ... },
  "quality_color": "green",
  "shots_total": 5,
  "shots_green": 4,
  "shots_yellow": 1,
  "shots_red": 0
}
```

**L6 场景执行**：
```json
{
  "logical_shot_id": "v01.c02.s01",
  "shot_id": "v01.c02.s01@01KW3Q5NCBPZWRG254EXAH2PK1",
  "prompt_snapshot_id": "ps_001",
  "drafts": [
    { "persona": "意象师", "draft_id": "d001", "jury_score": 82 },
    { "persona": "节奏师", "draft_id": "d002", "jury_score": 78 },
    { "persona": "对话师", "draft_id": "d003", "jury_score": 85 },
    { "persona": "结构师", "draft_id": "d004", "jury_score": 71 }
  ],
  "selected_draft_id": "d003",
  "quality_color": "green",
  "gate_results": { "L0": "pass", "L1": "pass", "L2": "pass", "L3": "pass", "L4": "pass" }
}
```

---

## 7. 数据库设计（4 张新表）

> Schema v8，总表数从 27 → 31。

### 7.1 tree_nodes（骨架，三棵树共用）

```sql
CREATE TABLE tree_nodes (
    node_id         TEXT PRIMARY KEY,
    tree_type       TEXT NOT NULL
                        CHECK (tree_type IN ('contract', 'story', 'execution')),
    project_id      TEXT NOT NULL REFERENCES projects(project_id),
    parent_id       TEXT REFERENCES tree_nodes(node_id),

    layer_key       TEXT NOT NULL,           -- 'v01.c02.s03'
    node_level      TEXT NOT NULL            -- L0~L7
                        CHECK (node_level IN ('L0','L1','L2','L3','L4','L5','L6','L7')),
    node_name       TEXT,                    -- '第二章·四线交织'
    sort_order      INTEGER DEFAULT 0,

    -- 治理状态（三棵树各取所需）
    design_status   TEXT DEFAULT 'pending'
                        CHECK (design_status IN
                            ('pending','drafting','review','confirmed','locked')),
    quality_color   TEXT
                        CHECK (quality_color IN ('green','yellow','red','gray',NULL)),
    node_intent     TEXT,                    -- 意图链的节点贡献

    -- 执行树专属
    run_id          TEXT,                    -- 执行树节点绑定 run；其他树 NULL

    -- 指针
    source_version_id TEXT,                  -- 执行树 → contract_versions

    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(tree_type, project_id, layer_key, run_id)
);

CREATE INDEX idx_tree_nodes_parent  ON tree_nodes(parent_id);
CREATE INDEX idx_tree_nodes_lookup  ON tree_nodes(tree_type, project_id, layer_key);
CREATE INDEX idx_tree_nodes_run     ON tree_nodes(run_id) WHERE run_id IS NOT NULL;
```

### 7.2 contract_versions（契约树正文）

```sql
CREATE TABLE contract_versions (
    version_id        TEXT PRIMARY KEY,
    node_id           TEXT NOT NULL REFERENCES tree_nodes(node_id),

    version           INTEGER NOT NULL,
    parent_version_id TEXT REFERENCES contract_versions(version_id),
    is_collapsed      INTEGER NOT NULL DEFAULT 0,  -- 折叠层自动继承父层

    contract_body_json JSON NOT NULL,
    change_reason     TEXT,
    created_by        TEXT NOT NULL DEFAULT 'human'
                          CHECK (created_by IN ('human', 'ai', 'upgrade')),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(node_id, version)
);

CREATE INDEX idx_contract_versions_node ON contract_versions(node_id);
```

### 7.3 story_content（故事树正文）

```sql
CREATE TABLE story_content (
    content_id       TEXT PRIMARY KEY,
    node_id          TEXT NOT NULL REFERENCES tree_nodes(node_id),

    content_body_json JSON NOT NULL,
    -- 含: character_states, timeline_anchor, foreshadow_ops, state_diff

    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_story_content_node ON story_content(node_id);
```

### 7.4 execution_records（执行树正文）

> 执行树不存正文本身。正文唯一真相源始终是 `shot_revisions.text`（详见 §8）。`execution_records.revision_id` 是指向 `shot_revisions` 的指针，使执行树成为"正文的访问路径"。

```sql
CREATE TABLE execution_records (
    record_id         TEXT PRIMARY KEY,
    node_id           TEXT NOT NULL REFERENCES tree_nodes(node_id),

    run_id            TEXT NOT NULL,
    prompt_snapshot_id TEXT,
    draft_ids_json    JSON,              -- 4 份草稿 ID 列表
    selected_draft_id TEXT,
    revision_id       TEXT REFERENCES shot_revisions(revision_id),  -- 指向正文真相源
    quality_result_json JSON,

    created_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_execution_records_node ON execution_records(node_id);
CREATE INDEX idx_execution_records_run  ON execution_records(run_id);
```

---

## 8. 三棵树的关系

```
契约树 (Contract Tree)              故事树 (Story Tree)
  tree_type='contract'                tree_type='story'
  版本化，设计时                        追加式，内容展开
  contract_versions                   story_content
  layer_key 对应                       layer_key 对应
         │                                  │
         └────────────┬─────────────────────┘
                      │ layer_key 绑定
                      ↓
                执行树 (Execution Tree)
                tree_type='execution'
                per-run，每次重新生成
                source_version_id → 契约树（哪个版本）
                layer_key → 故事树（哪个节点）
                execution_records
```

**跨树引用规则**：

| 从 | 到 | 引用方式 | 含义 |
|----|----|---------|------|
| 执行树 | 契约树 | `tree_nodes.source_version_id` | 本次执行基于哪个契约版本 |
| 执行树 | 故事树 | `tree_nodes.layer_key` 相同 | 本次执行对应故事的哪个节点 |
| 契约树 | 故事树 | 相同 `layer_key`（无显式 FK） | 契约约束对应故事的哪个节点 |

**正文的真相源**：

> **三棵树是索引，不是正文。**

```text
正文唯一真相源: shot_revisions.text (is_current=1 或 MAX(revision_sequence))
                                     ↑
        契约树───────┐                │
        契约正文 → contract_versions  │ (仅存契约约束，不存正文)
                    │                │
        故事树───────┤                │
        世界状态 → story_content      │ (仅存角色/伏笔/时间线，不存正文)
                    │                │
        执行树───────┘                │
        执行元数据 → execution_records.revision_id ───→ FK → shot_revisions.revision_id
                    (存 draft_ids 和指向 revision 的指针，不复制正文)
```

三棵树各自的内容类型：

| 树 | 表 | 存什么 | 不存什么 |
|----|----|--------|---------|
| 契约树 | `contract_versions.contract_body_json` | 契约约束（must_land / anti_write / motif_tasks） | 生成的小说正文 |
| 故事树 | `story_content.content_body_json` | 世界状态（角色状态、伏笔、时间线锚点） | 生成的小说正文 |
| 执行树 | `execution_records.*` | 执行元数据（draft_ids, selected_draft, revision_id 指针） | 正文本身（指向 `shot_revisions`） |

**正文真相源规则**：

| 状态 | 正文 = | 条件 |
|------|--------|------|
| 未封版 | `shot_revisions` 中 `revision_sequence` **最大**的行 | 最后一次生成的版本 |
| 已封版 | `shot_revisions` 中 `is_current=1` 的行 | 封版时锁定的版本，不再更新 |

`shot_revisions.is_current` 是**封版标记**——只在封版时设置一次，之后不再随新生成而更新。`writing_shots.current_revision_id` 指向最新 revision（始终随新生成而更新），当封版后也指向封版版本（两者一致）。

**accepted canonical / run attempt identity / book_run 补充（2026-06-28，Schema v20）**：

`shot_revisions.text` 仍是正文文本的存储真相源，但“哪一版可被后续章节当作正式正文”由 `writing_chapter_reviews` 的 accepted canonical selector 决定。

- `run --chapter` 完成后的自动导出是当前 run 审稿稿，只证明该 run 通过 L3/L4，不等于正式正文。
- `review --accept` 写入 `writing_chapter_reviews(status='accepted')`；同一项目/章节只允许一个 accepted run。
- `review --revise/--reject` 写入 `needs_revision/rejected`，并把该 run 本章绿/黄 shot 退回 `redo`。
- 默认 `ink export`、跨章 previous context、历史 fact anchors 只读取 accepted 章节或 locked baseline；`--draft` 才导出未 accepted 审稿稿。
- `logical_shot_id` 是契约树/故事树/排序和跨 run 定位的稳定身份；生产 run 的 `shot_id` 是 `{logical_shot_id}@{run_id}`，执行树和 `shot_revisions` 通过该 attempt 身份指向本次 run 的正文。
- baseline 人工样章是锁定来源，`shot_id == logical_shot_id`；生产章节重写必须创建新的 attempt shot 行，避免同章旧正文被误复用。
- `writing_book_runs` / `writing_book_run_chapters` 是执行调度索引，用来把多个章节 run 绑成一个全书/整卷批次；它不复制正文，也不改变 `shot_revisions.text` 的正文真相源规则。
- 同一 `book_run` 已完成的前序 draft 章节可作为后续章节临时上下文；默认正式导出、正式 fact anchors 和跨批次上下文仍只认 accepted canonical。

---

## 9. 合约继承算法

```python
def get_effective_contract(layer_key: str, project_id: str) -> dict:
    """从根到当前节点逐层 shallow merge，子层覆盖父层同名字段。"""
    path = get_ancestor_path(layer_key, project_id)  # [L0, L2, L4, L6]
    merged = {}
    for node in path:
        if node.is_collapsed:
            continue  # 折叠层（L1/L3/L5/L7）跳过，自动继承父层
        layer_data = json.loads(node.contract_body_json)
        for k, v in layer_data.items():
            if isinstance(v, dict) and isinstance(merged.get(k), dict):
                merged[k] = {**merged[k], **v}  # 单层深合并
            else:
                merged[k] = v
    return merged
```

---

## 10. 与现有表的关系

### 10.1 渐进迁移策略

v8 新增 4 张表，**不删除任何现有表**。现有表通过以下方式渐进接入：

| 现有表 | v8 处置 | 说明 |
|--------|---------|------|
| `writing_project_structure` | **保留，不修改** | 旧的骨架树，v8 后由 `tree_nodes` 接管新业务 |
| `writing_meta_contract` | **保留，加指针列** | 加 `constitution_version_id` 指向 L0 契约版本（v9, ARCH-4） |
| `writing_shot_contracts` | **保留，加指针列** | 加 `source_version_id` 指向生成它的契约版本 |
| `writing_chapter_rhythms` | **保留，加指针列** | 加 `layer_key` + `source_version_id` |
| `writing_shots` / `shot_revisions` / `writing_drafts` 等 | **保留，不修改** | **正文唯一真相源**：`shot_revisions.text`（`is_current=1` 或 `MAX(seq)`）。执行树通过 `execution_records.revision_id` 指向 `shot_revisions` |
| `writing_fact_anchors` | **保留，不修改** | 故事树通过 `layer_key` 关联事实锚点 |

### 10.2 向后兼容

- 现有 277 个测试全部保留，不受影响
- 旧代码路径（`ContractCompiler.get_chapter_events()` 等）继续读旧表
- 新功能通过 `tree_nodes` 读写，通过 `source_version_id` 桥接

### 10.3 未来瘦身（v9+）

当 `tree_nodes` + `contract_versions` 稳定后，可以将 `writing_meta_contract.layers_json` 拆分为 `contract_versions` 的多行，`writing_meta_contract` 退化为指针表。但这不是 v8 的任务。

---

## 11. 实施阶段

| Phase | 内容 | 新增/修改文件 |
|-------|------|-------------|
| **P1 地基** | Schema v8 迁移；`TreeManager` 核心类（CRUD + `get_effective_contract`） | `db/schema.sql`, `db/migration.py`, `services/tree_manager.py`（新建） |
| **P2 回填** | 从现有 `writing_meta_contract` 自动生成 `contract_versions` L0 行 | `services/tree_manager.py` |
| **P3 卷级** | `VolumeRhythmArchitect` + `volumes/v01.yaml` 格式 | `services/volume_rhythm.py`（新建） |
| **P4 桥接** | `cli.py` 接入树管道；`INKFLOW_TREE=1` 环境变量切换 | `cli.py`, `utils/config.py` |
| **P5 故事树** | `story_content` 接入；角色状态传播；伏笔追踪 | `services/story_manager.py`（新建） |
| **P6 执行树** | `execution_records` 接入；run 执行树自动生成 | `services/run_manager.py`（新建） |

---

## 12. 设计决策记录

| # | 决策 | 理由 |
|---|------|------|
| T1 | 3 棵树分离，不是 1 棵 | 故事不版本化（事件不会改），契约要版本化（宪法可升级），执行是 per-run；混在一起会导致语义冲突 |
| T2 | 4 张表，不是 8 张 | `tree_nodes` 是统一骨架（3 棵树共用），`contract_versions`/`story_content`/`execution_records` 各存各的正文；避免每棵树一套独立表 |
| T3 | 8 层必须有，空则占位 | 与 DeepStory 标准对齐；L1/L3/L5/L7 当前折叠（`is_collapsed=1`），但节点必须存在，保证 intent_chain 路径完整 |
| T4 | 不照搬 DeepStory 单表 | DeepStory 没有 run 概念，单表可行；InkFlow 有 run，必须设计时/运行时分离 |
| T5 | 不删现有表，渐进接入 | 277 个测试和现有生产代码不受影响；新功能通过指针列桥接 |
| T6 | `layer_key` 作为业务主键 | `v01.c02.s03` 是人类可读的稳定标识符，比 ULID 更适合跨树引用 |
| T7 | 三棵树是索引，正文在 `shot_revisions` | 树的职责是提供访问路径和语义索引，正文物理行始终在 `shot_revisions.text`。`execution_records.revision_id` 是执行树到正文的指针。避免正文在三棵树中冗余存储导致的同步问题 |

---

## 13. 参考文档

- 8 层层级设计：`design-8layer-hierarchy.md`
- DeepStory 树表设计：`D:\_Progs\02Business\DeepStory\sql\migrations\db3\001.up.sqlite.sql`
- DeepStory 契约层级文档：`D:\_Progs\02Business\DeepStory\docs\24_L0全书契约.md` ~ `27d_L3弧契约.md`
- InkFlow 技术设计：`design.md`
- InkFlow 实现契约：`implementation-contract-v0.md`
