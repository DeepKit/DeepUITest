# InkFlow 8层层级与复合ID设计

> 版本: v1.2 (2026-06-24)
> 继承自: DeepStory 8层金字塔设计 (`DeepStory/docs/04_技术架构设计.md`)
> 关联文档: `design-3tree-architecture.md`（ARCH-12 三棵树架构, ARCH-13 正文真相源锚定）

---

## 1. 设计来源

InkFlow 继承 DeepStory 的 8 层金字塔结构。每一层对应不同的叙事粒度，从全书到自然段逐级细分。

**v1.2 更新**：明确"三棵树是索引，不是正文"（ARCH-13）。正文唯一真相源始终是 `shot_revisions.text`。执行树通过 `execution_records.revision_id` 指向正文，不复制正文。详见 `design-3tree-architecture.md` §8。

**v1.1 更新**：8 层金字塔现在是 **三棵树（契约树/故事树/执行树）** 的共用层级标准，详见 `design-3tree-architecture.md`。每层在每棵树中有不同的内容，但层定义统一；空则占位（`is_collapsed=1`），保证 `intent_chain` 路径完整。

DeepStory 文档中的定义：
- `04_技术架构设计.md` §二：8层金字塔结构
- `11_上下文组装策略.md` §2.7：Intent链与8层金字塔
- `06_契约与产出物规格详解.md` §1：产出物层级

---

## 2. 8层定义

| 层级 | 中文名 | 英文代码 | 示例 | 说明 | 是否计划节点 |
|------|--------|----------|------|------|-------------|
| L0 | 全书 | work | 《分流》 | 唯一根节点 | 是 |
| L1 | 部 | part | (未用) | 大叙事阶段划分 | 是 |
| L2 | 卷 | volume | v01, v02 | 主线弧光、基调 | 是 |
| L3 | 弧 | arc | (未用) | 完整叙事弧光/篇章 | 是 |
| L4 | 章 | chapter | c01, c02 | 子案/子弧 | 是 |
| L5 | 节 | section | s01, s02 | **最小写作单元** ← writing_shots 的行 | 是 |
| L6 | 场景 | scene | (未来) | 原子写作单元（可扩展） | 待定 |
| L7 | 自然段 | para | - | 最小文本单元 | **否** — 仅输出 |

### 《分流》当前活跃层级

```
L0 全书: 《分流》
  └── L2 卷: v01 (第一卷)
        ├── L4 章: c01 (第一章)
        │     ├── L5 节: s01  ← shot_id = v01.c01.s01
        │     ├── L5 节: s02  ← shot_id = v01.c01.s02
        │     └── ...
        └── L4 章: c02 (第二章)
              ├── L5 节: s01  ← shot_id = v01.c02.s01
              ├── L5 节: s02  ← shot_id = v01.c02.s02
              └── ...
```

L1（部）和 L3（弧）当前**折叠**（collapsed），直接继承父层意图。

---

## 3. 复合 shot_id 格式

### 3.1 格式定义

```
格式: {volume}.{chapter}.s{section}
示例: v01.c02.s03
       │    │   └── 第3节
       │    └────── 第2章
       └─────────── 第1卷
```

### 3.2 生成规则

| 组件 | 格式 | 示例 | 说明 |
|------|------|------|------|
| volume | `v` + 2位数字 | v01, v02, v10 | 卷号，从1开始 |
| chapter | `c` + 2位数字 | c01, c02, c10 | 章号，从1开始 |
| section | `s` + 2位数字 | s01, s02, s10 | 节号，从1开始 |

**生成函数**：
```python
def generate_shot_id(layer_key: str, shot_index: int) -> str:
    """
    >>> generate_shot_id("v01.c02", 3)
    'v01.c02.s03'
    """
    return f"{layer_key}.s{shot_index:02d}"
```

### 3.3 与 layer_key 的关系

| 概念 | 格式 | 示例 | 说明 |
|------|------|------|------|
| layer_key | `{volume}.{chapter}` | v01.c02 | 卷+章，存储在 `writing_shots.layer_key` |
| shot_id | `{layer_key}.s{section}` | v01.c02.s03 | 完整层级路径 |

**关系**：`shot_id = layer_key + ".s" + zfill(shot_index, 2)`

### 3.4 排序规则

字典序即可（因为每层都是零填充的2位数字）：

```
v01.c01.s01 < v01.c01.s02 < v01.c01.s10 < v01.c02.s01 < v02.c01.s01
```

也可用 `sort_key()` 返回 `(volume, chapter, section)` 元组进行排序。

---

## 4. 层级折叠 (Collapsible Layers)

某些层级可以折叠（collapsed），直接继承父层意图，不单独展开：

| 项目 | L0全书 | L1部 | L2卷 | L3弧 | L4章 | L5节 |
|------|--------|------|------|------|------|------|
| 《分流》 | 展开 | **折叠** | 展开 | **折叠** | 展开 | 展开 |
| 《未尽之算》 | 展开 | 展开 | 展开 | 展开 | 折叠* | 展开 |

*《未尽之算》L4章默认折叠，只有当单个弧超过8集时才展开。

折叠规则：
- 折叠的层级不参与 `intent_chain` 生成
- 子层自动继承父层的 `intent`
- 折叠状态记录在 `writing_project_structure.metadata_json` 中

---

## 5. intent_chain

`intent_chain` 是从 L0 到当前场景的完整路径上，每层契约的意向摘要链。

### 5.1 结构

```yaml
intent_chain:
  - level: 0
    level_name: "全书"
    display_name: "《分流》"
    intent: "算法是文明的隐藏语言"
  - level: 2
    level_name: "卷"
    display_name: "第一卷"
    intent: "成都外江的骑手生态"
  - level: 4
    level_name: "章"
    display_name: "第二章"
    intent: "考古坑与系统分流的交织"
  - level: 5
    level_name: "节"
    display_name: "第3节"
    intent: "白英在茶社中感受到的内外江差异"
```

### 5.2 生成规则

1. 从层级树自动提取
2. 跳过 `collapsed: true` 的层级
3. 注入到 LLM prompt 的叙事素材部分

### 5.3 与 DeepStory 的对应

DeepStory 中定义在 `11_上下文组装策略.md` §2.7，作为 Slot L407 / S06 注入。

---

## 6. 数据库存储

> v1.1 更新：8 层层级现在由 **4 张新表**（Schema v8）承载三棵树。详见 `design-3tree-architecture.md`。

### 6.1 tree_nodes（骨架，三棵树共用）

所有 8 层节点注册在这张表中，用 `tree_type` 区分所属树（`contract` / `story` / `execution`），用 `parent_id` 构成树结构，用 `node_level` 标识层级（L0~L7）。

```sql
CREATE TABLE tree_nodes (
    node_id         TEXT PRIMARY KEY,
    tree_type       TEXT NOT NULL,  -- 'contract' | 'story' | 'execution'
    project_id      TEXT NOT NULL,
    parent_id       TEXT REFERENCES tree_nodes(node_id),
    layer_key       TEXT NOT NULL,  -- 'v01.c02.s03'
    node_level      TEXT NOT NULL,  -- L0~L7
    node_name       TEXT,
    node_intent     TEXT,           -- 意图链节点贡献
    design_status   TEXT,
    quality_color   TEXT,
    run_id          TEXT            -- 执行树专属
);
```

### 6.2 contract_versions（契约树正文，版本化）

```sql
CREATE TABLE contract_versions (
    version_id       TEXT PRIMARY KEY,
    node_id          TEXT NOT NULL REFERENCES tree_nodes(node_id),
    version          INTEGER NOT NULL,
    is_collapsed     INTEGER DEFAULT 0,
    contract_body_json JSON NOT NULL
);
```

### 6.3 story_content / execution_records（故事树 / 执行树正文）

结构同上，分别存储故事内容（角色状态/伏笔/时间线）和执行记录（元数据 + 指针）。

> ⚠️ **正文真相源**：三棵树都是**索引**，不存储生成的小说正文。正文唯一真相源始终是 `shot_revisions.text`：
> - **未封版**���`MAX(revision_sequence)` 的行（最后一次生成）
> - **已封版**：`is_current=1` 的行（封版锁定，不再更新）
>
> 执行树通过 `execution_records.revision_id` FK 指向 `shot_revisions.revision_id`，提供正文的访问路径。详见 `design-3tree-architecture.md` §8。

### 6.4 旧表（Schema v7，保留兼容）

| 表 | v8 处置 |
|---|---------|
| `writing_shots` | 保留，shot_id 仍为复合格式 `v01.c02.s03` |
| `writing_project_structure` | 保留，旧骨架；新业务由 `tree_nodes` 接管 |
| `writing_meta_contract` | 保留，加 `constitution_version_id` 指针 |
| `writing_shot_contracts` | 保留，加 `source_version_id` 指针 |
| `writing_chapter_rhythms` | 保留，加 `layer_key` + `source_version_id` 指针 |

---

## 7. 迁移策略

### 7.1 旧格式 (v4)

shot_id 是 26 字符 ULID：`01KVJ1QVDRDGFX9J73459RE11H`

### 7.2 新格式 (v5)

shot_id 是复合格式：`v01.c02.s03`

### 7.3 迁移步骤

1. 关闭外键约束
2. 读取所有 `writing_shots` 的 `(shot_id, layer_key, shot_index)`
3. 构建 `old_id → new_id` 映射
4. 更新所有 FK 表（18张表）
5. 更新 `writing_shots` 主表
6. 恢复外键约束

详见 `src/inkflow/db/migration.py` 中的 `migrate_v4_to_v5()`。

---

## 8. 设计决策记录

| # | 决策 | 理由 |
|---|------|------|
| D1 | 点分隔格式 `v01.c02.s03` | 与 DeepStory 一致，可读性好 |
| D2 | shot_id 本身变为复合ID | 不需要新增列，275处引用无需改动 |
| D3 | 其他主键保持 ULID | shot_id 是唯一需要人类读写的 ID |
| D4 | 迁移而非双格式共存 | P0 数据量小，干净迁移优于永久兼容 |

---

## 9. 参考文档

- DeepStory 8层设计: `D:\_Progs\02Business\DeepStory\docs\04_技术架构设计.md`
- Intent链规格: `D:\_Progs\02Business\DeepStory\docs\11_上下文组装策略.md` §2.7
- 契约字段: `D:\_Progs\02Business\DeepStory\MvpDocs\10_T03契约字段定稿.md`
