# SCENE-FINGERPRINT-1 — 结构化场景指纹设计

Date: 2026-07-02
Status: Draft (brainstorming output)
Owner: InkFlow 主链路

## 1. 问题陈述

`_check_chapter_scene_diversity` (L3) 当前从**正文文本**用两张硬编码词表反推场景桶：

- `_scene_bucket(text)` — 词表 `转运站/月台/军列/微裂纹/批号/车间/铁门...` 是《白灯法则》专有词汇。
- `_scene_anchor_terms(text)` — 同上，专有词表。

换项目时所有 bucket 落 `unknown`，`scene_diversity` 静默放行。同时 `writing_shot_scene_contracts` 表已有结构化字段（`location` / `required_anchors` / `forbidden_overlap`），但 L3 完全不读它们。

**目标**：让 gate 优先读结构化指纹，消除项目专有硬编码，并保留对"架构师跨章节写不一致 bucket 名"的防御。

## 2. 核心决策

1. 新增独立表 `writing_shot_scene_fingerprints`（Schema v26），FK → `writing_shot_contracts(contract_id)`，UNIQUE 一对一。
2. `scene_bucket` 为自由 TEXT，存库前 normalize（去空白、全角转半角、小写化 ASCII）。
3. 同场景判定双防线：`scene_bucket` 字符串相等 **或** `event_anchors` Jaccard 相似度 ≥ 0.7。
4. 硬编码 `_scene_bucket()` / `_scene_anchor_terms()` 退役；仅在指纹表全缺失时作为正文兜底（保留为 `_fallback_bucket_from_text` / `_fallback_anchors_from_text`，不再作为主路径）。

## 3. 职责边界

| 表 | 职责 | 关键字段 |
|----|------|----------|
| `writing_shot_scene_contracts` (v25, 已有) | 场景**契约约束**——必须出现什么、禁止复用什么、容量下限 | location, required_anchors, forbidden_overlap, min_utf8_bytes |
| `writing_shot_scene_fingerprints` (v26, 新增) | 场景**指纹特征**——多样性比较与重复识别 | scene_bucket, time_jump, key_objects, event_anchors, similarity_hash |

两表都 UNIQUE(contract_id)，一对一。契约管"该不该出现"，指纹管"和别的像不像"。

## 4. Schema v26 表定义

```sql
CREATE TABLE IF NOT EXISTS writing_shot_scene_fingerprints (
    fingerprint_id   TEXT PRIMARY KEY,
    contract_id      TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id),
    scene_bucket     TEXT NOT NULL DEFAULT '' ,           -- 自由 TEXT,存库前 normalize
    time_jump        TEXT NOT NULL DEFAULT '',            -- immediate/next_day/next_week/... 自由 TEXT
    key_objects      TEXT NOT NULL DEFAULT '[]',          -- JSON array
    event_anchors    TEXT NOT NULL DEFAULT '[]',          -- JSON array,与 scene_contract.required_anchors 同源
    similarity_hash  TEXT NOT NULL DEFAULT '',            -- bucket+sorted(anchors[:3]) 的短 hash,便于快速查重
    source           TEXT NOT NULL DEFAULT 'derived' CHECK(source IN ('derived','fallback','explicit')),
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(contract_id)
);
CREATE INDEX IF NOT EXISTS idx_shot_scene_fingerprints_bucket
    ON writing_shot_scene_fingerprints(scene_bucket);
```

`source` 字段记录指纹来源：`explicit`（架构师显式给的）、`derived`（从契约字段推导）、`fallback`（从正文反推，旧路径兜底）。用于审计与"是否过度依赖兜底"的观测。

## 5. 生成时机

指纹在 `_derive_scene_contract()`（cli.py）已有推导中**同步计算**，不新增生成阶段。流程：

```
chapter event
  → cli._derive_scene_contract()
    → scene_contract dict (已有)
    → fingerprint dict (新增:从 location/required_anchors/time_position 计算)
      → ContractCompiler.compile_shot_contracts()
        → INSERT writing_shot_scene_contracts  (已有)
        → INSERT writing_shot_scene_fingerprints  (新增)
          → architect_gate._check_chapter_scene_diversity()  (改造:读指纹表)
```

## 6. 指纹计算规则 (`_derive_fingerprint`)

输入：`scene_contract` dict（已规范化的 location / required_anchors / time_position / key_objects）。

- `scene_bucket` = normalize(location)（去空白、全角→半角、ASCII 小写）。location 为空则 `""`，gate 视为 `unknown`。
- `event_anchors` = `required_anchors`（同源，不重复推导）。
- `time_jump` = normalize(time_position)。
- `key_objects` = `entry_object` + required_anchors 的前 3 个去重。
- `similarity_hash` = sha1(scene_bucket + "|" + "|".join(sorted(event_anchors[:3])))[:10]。
- `source` = `"explicit"` 若 event 显式给了 scene_contract 且含 location；`"derived"` 若从 location 推导成功；`"fallback"` 若 location 为空且走正文兜底。

normalize 函数复用现有工具，不引入新依赖。

## 7. Gate 改造 (`_check_chapter_scene_diversity`)

当前实现（architect_gate.py:1153）从正文算 bucket/fingerprint。改为：

1. **主路径**：按 shot 的 contract_id 查 `writing_shot_scene_fingerprints`，拿 `scene_bucket` / `event_anchors` / `similarity_hash`。
2. **同场景判定**（双防线）：
   - 两个 shot 的 `scene_bucket` 非空且相等 → 同场景；或
   - 两个 shot 的 `event_anchors` Jaccard ≥ 0.7 → 同场景。
3. **多样性**：N≥3 shot 时，distinct 场景数 < min(N,3) → `scene_count_low` violation（保留现有 violation 类型）。
4. **相邻相似**：相邻 shot 同场景（双防线判定）且 opening 文本相似度 ≥ 0.72 → `adjacent_scene_too_similar`（保留现有阈值，但"同场景"判定改用指纹双防线而非纯文本 bucket）。
5. **兜底**：指纹表无记录（旧 DB 或迁移未跑）→ 走 `_fallback_bucket_from_text`（退役词表的别名），gate 正常工作但 `source=fallback` 会在审计里可见，便于发现"哪些 shot 没拿到结构化指纹"。

`_check_scene_contract_anchors`（L4）不受影响——它已经读 `writing_shot_scene_contracts` 的 required_anchors，不依赖退役词表。

## 8. 迁移 (v25 → v26)

`_migrate_v25_to_v26`：
1. 建 `writing_shot_scene_fingerprints` 表 + 索引。
2. **回填**：对每条 `writing_shot_scene_contracts` 记录，从其 `location` / `required_anchors` / `time_position` 计算指纹并 INSERT，`source='derived'`。
3. 回填不失败：单条出错跳过，记 warning，不阻断迁移。

回填保证升级后立即有指纹数据，gate 主路径立即可用，不需要重跑契约。

## 9. 测试

| 测试 | 覆盖 |
|------|------|
| `test_schema.py` | v26 表存在、列与 CHECK 约束、UNIQUE(contract_id) |
| `test_migration.py` | v25→v26 建表 + 回填；回填从 location/anchors 正确计算指纹；单条出错不阻断 |
| `test_contract_compiler.py` | compile_shot_contracts 同时写两表；指纹字段正确；source 取值 |
| `test_cli.py` | _derive_scene_contract 输出含 fingerprint；normalize 正确 |
| `test_architect_gate.py` | (1) 整章同 bucket → scene_count_low；(2) 3 shot 同 bucket 不同 anchors 且 Jaccard<0.7 → 通过；(3) 3 shot 不同 bucket 但 anchors Jaccard≥0.7 → adjacent_scene_too_similar；(4) 指纹表空 → 走 fallback 不崩 |

回归：现有 `scene_diversity` / `contract_scene` 测试保持通过（可能需调整 fixture 以提供指纹行）。

## 10. 不做 (YAGNI)

- **不做**项目级 bucket 字典强制（留 meta_contract 接口但不实现强制校验，默认自由 TEXT）。
- **不做**固定通用枚举（indoor/outdoor/...）。
- **不做**两层大类+子位置。
- **不删**硬编码词表（保留为 fallback 别名，等真实项目验证主路径稳定后再删）。

## 11. 验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\services\architect_gate.py src\inkflow\services\contract_compiler.py src\inkflow\cli.py
python -m pytest tests\test_schema.py tests\test_migration.py tests\test_contract_compiler.py tests\test_architect_gate.py tests\test_cli.py -q
python -m pytest tests/ -q
```

## 12. 风险

- **回填漏数据**：v25 契约若 location 为空，回填出空 bucket。已通过 `source` 字段可观测，gate 走 fallback 兜底。
- **Jaccard 阈值 0.7 偏严**：anchors 重合度高的小场景可能误报。先按 0.7 落地，用真实《白灯法则》c03 验证后调参。
- **迁移测试 fixture 老化**：test_migration.py 里有 v18→v19 等旧迁移测试，新增 v25→v26 不影响它们。
