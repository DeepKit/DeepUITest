# SCENE-FINGERPRINT-1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 L3 `scene_diversity` 门禁从"正文猜桶"改为"读结构化场景指纹"，新增 `writing_shot_scene_fingerprints` 表（Schema v26），退役硬编码词表为兜底。

**Architecture:** 在 `_derive_scene_contract()`（cli.py）同步计算指纹，经 `ContractCompiler` 落库到新表；`_check_chapter_scene_diversity()`（architect_gate.py）改为读指纹表，用 `scene_bucket` 相等或 `event_anchors` Jaccard ≥ 0.7 判同场景；migration v25→v26 建表并回填已有契约的指纹。

**Tech Stack:** Python 3.10+、SQLite、pytest。无新依赖。

## Global Constraints

- SCHEMA_VERSION 从 25 升到 26；新增 migration `register_migration(25, 26)`。
- `scene_bucket` 为自由 TEXT，存库前 normalize（去空白、全角→半角、ASCII 小写）。
- 同场景判定：`scene_bucket` 非空且相等 **或** `event_anchors` Jaccard ≥ 0.7。
- 硬编码 `_scene_bucket()` / `_scene_anchor_terms()` 保留为 fallback 别名，不删除。
- 每个任务结束 `python -m pytest tests/ -q` 全绿（531+ passed）后才提交。
- 遵循现有代码风格：中文 docstring、`generate_ulid()` 主键、`json.dumps(..., ensure_ascii=False)`。

---

## File Structure

- **Modify** `inkflow/src/inkflow/db/schema.sql` — 新增 `writing_shot_scene_fingerprints` 建表语句；SCHEMA_VERSION 注释升到 26。
- **Modify** `inkflow/src/inkflow/db/migration.py` — `SCHEMA_VERSION=26`；新增 `_migrate_v25_to_v26` + `_create_v26_fingerprint_table` + `_backfill_v26_fingerprints`。
- **Modify** `inkflow/src/inkflow/cli.py` — `_derive_scene_contract()` 输出新增 `fingerprint` dict；新增 `_derive_fingerprint()` + `_normalize_scene_bucket()` 辅助函数。
- **Modify** `inkflow/src/inkflow/services/contract_compiler.py` — `compile_shot_contracts()` 同时写指纹表；新增 `_write_scene_fingerprint()`。
- **Modify** `inkflow/src/inkflow/services/architect_gate.py` — shots 查询加 `wsc.contract_id`；`_check_chapter_scene_diversity()` 改读指纹；新增 `_scene_fingerprint_for_contract()` + `_jaccard()`；`_scene_bucket`/`_scene_anchor_terms` 重命名为 fallback 别名。
- **Modify** `inkflow/tests/test_schema.py` — v26 表结构测试。
- **Modify** `inkflow/tests/test_migration.py` — v25→v26 建表 + 回填测试。
- **Modify** `inkflow/tests/test_contract_compiler.py` — 写指纹表测试。
- **Modify** `inkflow/tests/test_cli.py` — `_derive_scene_contract` 输出 fingerprint 测试。
- **Modify** `inkflow/tests/test_architect_gate.py` — 指纹主路径 + Jaccard + fallback 测试。

---

### Task 1: Schema v26 — 新增指纹表

**Files:**
- Modify: `inkflow/src/inkflow/db/schema.sql`（在 `writing_shot_scene_contracts` 建表语句后追加）
- Modify: `inkflow/src/inkflow/db/migration.py:16`（`SCHEMA_VERSION = 25` → `26`）
- Test: `inkflow/tests/test_schema.py`

**Interfaces:**
- Produces: `writing_shot_scene_fingerprints` 表，列见下方 SQL。

- [ ] **Step 1: 写失败测试**

在 `test_schema.py` 末尾追加（找现有的 `def test_` 风格，若文件用类则加到合适类里）：

```python
def test_scene_fingerprints_table_exists(db):
    """v26: writing_shot_scene_fingerprints 表存在且结构正确。"""
    cols = {
        row["name"]: row for row in db.execute("PRAGMA table_info(writing_shot_scene_fingerprints)")
    }
    assert "fingerprint_id" in cols
    assert "contract_id" in cols
    assert "scene_bucket" in cols
    assert "time_jump" in cols
    assert "key_objects" in cols
    assert "event_anchors" in cols
    assert "similarity_hash" in cols
    assert "source" in cols
    # UNIQUE(contract_id)
    idx = db.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='writing_shot_scene_fingerprints'"
    ).fetchone()
    assert "UNIQUE(contract_id)" in idx["sql"]
    # source CHECK
    assert "source" in idx["sql"] and "'derived'" in idx["sql"]
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd inkflow && python -m pytest tests/test_schema.py -q -k fingerprints`
Expected: FAIL（表不存在）

- [ ] **Step 3: 在 schema.sql 追加建表语句**

在 `writing_shot_scene_contracts` 的 `CREATE INDEX idx_shot_scene_contracts_contract ...` 行之后追加：

```sql

-- v26: Scene fingerprint — 场景指纹特征，用于多样性比较与重复识别
CREATE TABLE writing_shot_scene_fingerprints (
    fingerprint_id   TEXT PRIMARY KEY,
    contract_id      TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id),
    scene_bucket     TEXT NOT NULL DEFAULT '',
    time_jump        TEXT NOT NULL DEFAULT '',
    key_objects      TEXT NOT NULL DEFAULT '[]',
    event_anchors    TEXT NOT NULL DEFAULT '[]',
    similarity_hash  TEXT NOT NULL DEFAULT '',
    source           TEXT NOT NULL DEFAULT 'derived' CHECK(source IN ('derived','fallback','explicit')),
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(contract_id)
);
CREATE INDEX IF NOT EXISTS idx_shot_scene_fingerprints_bucket
    ON writing_shot_scene_fingerprints(scene_bucket);
```

同时把 schema.sql 顶部 `-- SCHEMA_VERSION: 25` 改为 `-- SCHEMA_VERSION: 26`，`-- InkFlow v3.24 — Schema v24` 注释行改为 `-- InkFlow v3.26 — Schema v26`。

- [ ] **Step 4: 改 migration.py SCHEMA_VERSION**

`inkflow/src/inkflow/db/migration.py:16` 把 `SCHEMA_VERSION = 25` 改为 `SCHEMA_VERSION = 26`。

- [ ] **Step 5: 运行测试验证通过**

Run: `cd inkflow && python -m pytest tests/test_schema.py -q -k fingerprints`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add inkflow/src/inkflow/db/schema.sql inkflow/src/inkflow/db/migration.py inkflow/tests/test_schema.py
git commit -m "feat: Schema v26 writing_shot_scene_fingerprints 表"
```

---

### Task 2: Migration v25 → v26（建表 + 回填）

**Files:**
- Modify: `inkflow/src/inkflow/db/migration.py`（在 `_migrate_v24_to_v25` 之后追加）
- Test: `inkflow/tests/test_migration.py`

**Interfaces:**
- Produces: `register_migration(25, 26)` 注册；回填从 `writing_shot_scene_contracts.location/required_anchors/time_position` 计算指纹。

- [ ] **Step 1: 写失败测试**

在 `test_migration.py` 末尾追加（参考现有 `test_migrate_v18_to_v19_backfills_logical_shot_id` 的 tmp_dir 风格）：

```python
def test_migrate_v25_to_v26_creates_and_backfills_fingerprints(tmp_dir):
    """v26 migration 建指纹表并从 scene_contract 回填。"""
    import sqlite3, json
    from inkflow.db.migration import migrate_if_needed, ensure_meta_table, set_schema_version, SCHEMA_VERSION
    conn = sqlite3.connect(str(tmp_dir / "v25_finger.db"))
    conn.row_factory = sqlite3.Row
    try:
        ensure_meta_table(conn)
        set_schema_version(conn, 25)
        # 最小 writing_shot_contracts + writing_shots 满足 FK
        conn.execute("CREATE TABLE writing_shots (shot_id TEXT PRIMARY KEY, run_id TEXT, layer_key TEXT, shot_index INTEGER)")
        conn.execute("CREATE TABLE writing_sessions (run_id TEXT PRIMARY KEY)")
        conn.execute("INSERT INTO writing_sessions(run_id) VALUES ('r1')")
        conn.execute("CREATE TABLE writing_shot_contracts (contract_id TEXT PRIMARY KEY, shot_id TEXT, run_id TEXT, contract_json TEXT)")
        # v25 scene_contract 表
        conn.execute(
            "CREATE TABLE writing_shot_scene_contracts ("
            "scene_contract_id TEXT PRIMARY KEY, contract_id TEXT NOT NULL, "
            "scene_id TEXT, location TEXT, time_position TEXT, entry_point TEXT, "
            "entry_object TEXT, required_anchors TEXT, forbidden_overlap TEXT, "
            "information_delta TEXT, exit_state TEXT, same_scene_continuation INTEGER, "
            "min_utf8_bytes INTEGER)"
        )
        conn.execute("INSERT INTO writing_shots(shot_id, run_id, layer_key, shot_index) VALUES ('sh1','r1','c01',1)")
        conn.execute(
            "INSERT INTO writing_shot_contracts(contract_id, shot_id, run_id, contract_json) "
            "VALUES ('cid1','sh1','r1', ?)",
            (json.dumps({"scene_contract": {"location": "转运站月台", "required_anchors": ["军列","交接单"]}}),),
        )
        conn.execute(
            "INSERT INTO writing_shot_scene_contracts(scene_contract_id, contract_id, scene_id, location, "
            "required_anchors, time_position) VALUES ('sc1','cid1','scene.01','转运站月台',?,'当日')",
            (json.dumps(["军列","交接单"]),),
        )
        result = migrate_if_needed(conn)
        assert any("v25" in r and "v26" in r for r in result)
        row = conn.execute(
            "SELECT scene_bucket, event_anchors, source FROM writing_shot_scene_fingerprints WHERE contract_id='cid1'"
        ).fetchone()
        assert row is not None
        assert row["scene_bucket"] == "转运站月台"
        assert json.loads(row["event_anchors"]) == ["军列", "交接单"]
        assert row["source"] == "derived"
    finally:
        conn.close()
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd inkflow && python -m pytest tests/test_migration.py -q -k v25_to_v26`
Expected: FAIL（无 migration 25→26）

- [ ] **Step 3: 实现 migration**

在 `migration.py` 的 `_create_v25_scene_contract_table` 函数之后追加：

```python
@register_migration(25, 26)
def _migrate_v25_to_v26(conn: sqlite3.Connection) -> None:
    """v26: Scene fingerprint — 场景指纹特征表，并回填已有 scene_contract。"""
    _create_v26_fingerprint_table(conn)
    _backfill_v26_fingerprints(conn)


def _create_v26_fingerprint_table(conn: sqlite3.Connection) -> None:
    """Create v26 scene fingerprint table (mirrors schema.sql)."""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS writing_shot_scene_fingerprints ("
        "fingerprint_id   TEXT PRIMARY KEY, "
        "contract_id      TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id), "
        "scene_bucket     TEXT NOT NULL DEFAULT '', "
        "time_jump        TEXT NOT NULL DEFAULT '', "
        "key_objects      TEXT NOT NULL DEFAULT '[]', "
        "event_anchors    TEXT NOT NULL DEFAULT '[]', "
        "similarity_hash  TEXT NOT NULL DEFAULT '', "
        "source           TEXT NOT NULL DEFAULT 'derived' CHECK(source IN ('derived','fallback','explicit')), "
        "created_at       TEXT NOT NULL DEFAULT (datetime('now')), "
        "UNIQUE(contract_id)"
        ")"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_shot_scene_fingerprints_bucket "
        "ON writing_shot_scene_fingerprints(scene_bucket)"
    )


def _backfill_v26_fingerprints(conn: sqlite3.Connection) -> None:
    """Backfill fingerprints from existing writing_shot_scene_contracts rows."""
    import hashlib
    import json
    rows = conn.execute(
        "SELECT contract_id, location, time_position, entry_object, required_anchors "
        "FROM writing_shot_scene_contracts"
    ).fetchall()
    for r in rows:
        try:
            location = (r["location"] or "").strip()
            time_position = (r["time_position"] or "").strip()
            entry_object = (r["entry_object"] or "").strip()
            anchors_raw = r["required_anchors"] or "[]"
            anchors = json.loads(anchors_raw) if isinstance(anchors_raw, str) else list(anchors_raw)
            anchors = [str(a).strip() for a in anchors if str(a).strip()]
            bucket = _normalize_bucket(location)
            key_objects = [o for o in [entry_object, *anchors[:3]] if o]
            seen = set()
            key_objects = [o for o in key_objects if not (o in seen or seen.add(o))]
            hash_src = bucket + "|" + "|".join(sorted(anchors[:3]))
            sim_hash = hashlib.sha1(hash_src.encode("utf-8")).hexdigest()[:10]
            source = "explicit" if location and r["entry_object"] else "derived"
            if not location:
                source = "fallback"
            conn.execute(
                "INSERT OR IGNORE INTO writing_shot_scene_fingerprints "
                "(fingerprint_id, contract_id, scene_bucket, time_jump, key_objects, "
                "event_anchors, similarity_hash, source) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (generate_ulid(), r["contract_id"], bucket, time_position,
                 json.dumps(key_objects, ensure_ascii=False),
                 json.dumps(anchors, ensure_ascii=False), sim_hash, source),
            )
        except Exception:
            # 单条出错不阻断迁移
            continue
```

同时在 migration.py 顶部 import 区确认 `generate_ulid` 已可用（检查现有 import；若没有，`from inkflow.utils import generate_ulid`）。`_normalize_bucket` 在 Task 3 的 cli.py 里定义——为避免 migration 依赖 cli，把 `_normalize_bucket` 定义为 migration.py 内的模块级私有函数（见 Step 4）。

- [ ] **Step 4: 在 migration.py 定义 _normalize_bucket**

在 `_backfill_v26_fingerprints` 之前定义：

```python
def _normalize_bucket(location: str) -> str:
    """Normalize a scene location into a bucket string for comparison."""
    import re
    import unicodedata
    s = (location or "").strip()
    if not s:
        return ""
    # 全角→半角
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"\s+", "", s)
    # ASCII 部分小写
    s = "".join(c.lower() if c.isascii() else c for c in s)
    return s
```

- [ ] **Step 5: 运行测试验证通过**

Run: `cd inkflow && python -m pytest tests/test_migration.py -q -k v25_to_v26`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add inkflow/src/inkflow/db/migration.py inkflow/tests/test_migration.py
git commit -m "feat: migration v25→v26 指纹表建表与回填"
```

---

### Task 3: cli._derive_scene_contract 输出 fingerprint

**Files:**
- Modify: `inkflow/src/inkflow/cli.py:1211-1292`（`_derive_scene_contract`）+ 新增 `_derive_fingerprint` / `_normalize_scene_bucket`
- Test: `inkflow/tests/test_cli.py`

**Interfaces:**
- Produces: `_derive_scene_contract()` 返回 dict 新增 `"fingerprint"` 键，结构 `{scene_bucket, time_jump, key_objects, event_anchors, similarity_hash, source}`。

- [ ] **Step 1: 写失败测试**

在 `test_cli.py` 找到 `_derive_scene_contract` 相关测试附近追加：

```python
def test_derive_scene_contract_includes_fingerprint():
    from inkflow.cli import _derive_scene_contract
    event = {
        "title": "转运站见军列",
        "event": "许怀山在转运站月台交接军列",
        "scene_contract": {
            "location": "转运站月台",
            "time_position": "当日",
            "required_anchors": ["军列", "交接单"],
            "entry_object": "军列",
        },
    }
    sc = _derive_scene_contract(event, 1, 3)
    fp = sc.get("fingerprint")
    assert fp is not None
    assert fp["scene_bucket"] == "转运站月台"
    assert fp["event_anchors"] == ["军列", "交接单"]
    assert fp["time_jump"] == "当日"
    assert fp["source"] == "explicit"
    assert fp["similarity_hash"]
    assert "军列" in fp["key_objects"]


def test_derive_fingerprint_normalizes_bucket():
    from inkflow.cli import _derive_scene_contract
    # location 全角空格 + ASCII，验证 normalize
    event = {
        "title": "t",
        "event": "e",
        "scene_contract": {"location": "Transit　Station", "required_anchors": []},
    }
    sc = _derive_scene_contract(event, 1, 2)
    fp = sc["fingerprint"]
    assert fp["scene_bucket"] == "TransitStation".lower()
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd inkflow && python -m pytest tests/test_cli.py -q -k "fingerprint"`
Expected: FAIL（`fingerprint` 键不存在）

- [ ] **Step 3: 实现 _normalize_scene_bucket 与 _derive_fingerprint**

在 `cli.py` 的 `_derive_scene_contract` 函数**之前**新增两个模块级函数：

```python
def _normalize_scene_bucket(location: str) -> str:
    """Normalize a scene location into a comparable bucket string."""
    import re
    import unicodedata
    s = (location or "").strip()
    if not s:
        return ""
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"\s+", "", s)
    s = "".join(c.lower() if c.isascii() else c for c in s)
    return s


def _derive_fingerprint(scene_contract: dict) -> dict:
    """Compute a scene fingerprint from a normalized scene_contract dict."""
    import hashlib
    location = str(scene_contract.get("location") or "").strip()
    anchors = [str(a).strip() for a in (scene_contract.get("required_anchors") or []) if str(a).strip()]
    entry_object = str(scene_contract.get("entry_object") or "").strip()
    time_position = str(scene_contract.get("time_position") or "").strip()

    bucket = _normalize_scene_bucket(location)
    key_objects: list[str] = []
    seen: set[str] = set()
    for obj in [entry_object, *anchors[:3]]:
        if obj and obj not in seen:
            seen.add(obj)
            key_objects.append(obj)
    hash_src = bucket + "|" + "|".join(sorted(anchors[:3]))
    sim_hash = hashlib.sha1(hash_src.encode("utf-8")).hexdigest()[:10]

    if location and entry_object:
        source = "explicit"
    elif location:
        source = "derived"
    else:
        source = "fallback"

    return {
        "scene_bucket": bucket,
        "time_jump": time_position,
        "key_objects": key_objects,
        "event_anchors": anchors,
        "similarity_hash": sim_hash,
        "source": source,
    }
```

- [ ] **Step 4: 在 _derive_scene_contract 返回 dict 里加 fingerprint**

`cli.py:1270` 的 `return { ... }` 块，在 `"min_utf8_bytes": max(600, min_bytes),` ���之后、`return` 的 `}` 之前追加：

```python
        "fingerprint": _derive_fingerprint({
            "location": location,
            "time_position": time_position,
            "entry_object": entry_object,
            "required_anchors": required,
        }),
```

注意：`location` / `required` / `entry_object` / `time_position` 在该函数作用域内已定义（见现有代码 1230-1262）。

- [ ] **Step 5: 运行测试验证通过**

Run: `cd inkflow && python -m pytest tests/test_cli.py -q -k "fingerprint"`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add inkflow/src/inkflow/cli.py inkflow/tests/test_cli.py
git commit -m "feat: _derive_scene_contract 输出结构化场景指纹"
```

---

### Task 4: ContractCompiler 写指纹表

**Files:**
- Modify: `inkflow/src/inkflow/services/contract_compiler.py:1043-1066`（`compile_shot_contracts` 写 scene_contract 处）
- Test: `inkflow/tests/test_contract_compiler.py`

**Interfaces:**
- Consumes: `_derive_scene_contract` 输出的 `fingerprint` dict（经 shot contract 流入）。
- Produces: `compile_shot_contracts()` 同时 INSERT `writing_shot_scene_fingerprints`。

- [ ] **Step 1: 写失败测试**

在 `test_contract_compiler.py` 找到写 `writing_shot_scene_contracts` 的测试附近追加：

```python
def test_compile_writes_scene_fingerprint(db):
    """compile_shot_contracts 同时写 writing_shot_scene_fingerprints。"""
    from inkflow.services.contract_compiler import ContractCompiler
    import json
    # 最小前置：writing_shots + writing_shot_contracts 行由现有 fixture 或 helper 提供；
    # 若无 helper，直接用 db.execute 插入必要行（参考现有 scene_contract 测试的 setup）
    # 此处假设 db 已有 shot+contract 上下文；按现有测试模式补全
    compiler = ContractCompiler(db, run_id="r1")
    shots = [{
        "shot_id": "sh1",
        "shot_index": 1,
        "layer_key": "c01",
        "must_land": {"title": "t", "event": "e"},
        "scene_contract": {
            "scene_id": "scene.01",
            "location": "转运站月台",
            "required_anchors": ["军列", "交接单"],
            "entry_object": "军列",
            "time_position": "当日",
            "min_utf8_bytes": 1200,
            "fingerprint": {
                "scene_bucket": "转运站月台",
                "time_jump": "当日",
                "key_objects": ["军列", "交接单"],
                "event_anchors": ["军列", "交接单"],
                "similarity_hash": "abc123",
                "source": "explicit",
            },
        },
    }]
    compiler.compile_shot_contracts(shots, chapter_key="c01")
    row = db.execute(
        "SELECT scene_bucket, event_anchors, source FROM writing_shot_scene_fingerprints "
        "WHERE contract_id IN (SELECT contract_id FROM writing_shot_contracts WHERE shot_id='sh1')"
    ).fetchone()
    assert row is not None
    assert row["scene_bucket"] == "转运站月台"
    assert json.loads(row["event_anchors"]) == ["军列", "交接单"]
    assert row["source"] == "explicit"
```

注意：若现有测试用 `db` fixture 需要先插入 `writing_sessions` / `writing_shots` 行，照搬同文件其他 `test_compile_*` 测试的 setup 代码。

- [ ] **Step 2: 运行测试验证失败**

Run: `cd inkflow && python -m pytest tests/test_contract_compiler.py -q -k fingerprint`
Expected: FAIL（表无数据）

- [ ] **Step 3: 在 compile_shot_contracts 写完 scene_contract 后追加写指纹**

`contract_compiler.py:1066`（`self.db.execute("INSERT OR REPLACE INTO writing_shot_scene_contracts ...")` 那个 execute 调用）**之后**追加调用：

```python
        self._write_scene_fingerprint(contract_id, scene)
```

然后在 `_normalize_scene_contract` 函数**之前**新增方法：

```python
    def _write_scene_fingerprint(self, contract_id: str, scene: dict) -> None:
        """Write the v26 scene fingerprint row derived from a scene contract."""
        fp = scene.get("fingerprint")
        if not isinstance(fp, dict):
            # 兜底：现场计算（兼容未走 _derive_scene_contract 的旧路径）
            from inkflow.cli import _derive_fingerprint
            fp = _derive_fingerprint(scene)
        self.db.execute(
            "INSERT OR REPLACE INTO writing_shot_scene_fingerprints "
            "(fingerprint_id, contract_id, scene_bucket, time_jump, key_objects, "
            "event_anchors, similarity_hash, source) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                generate_ulid(),
                contract_id,
                fp.get("scene_bucket", ""),
                fp.get("time_jump", ""),
                json.dumps(fp.get("key_objects") or [], ensure_ascii=False),
                json.dumps(fp.get("event_anchors") or [], ensure_ascii=False),
                fp.get("similarity_hash", ""),
                fp.get("source", "derived"),
            ),
        )
```

确认 `generate_ulid` 与 `json` 已在 contract_compiler.py 顶部 import（检查现有 import，缺则补）。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd inkflow && python -m pytest tests/test_contract_compiler.py -q -k fingerprint`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add inkflow/src/inkflow/services/contract_compiler.py inkflow/tests/test_contract_compiler.py
git commit -m "feat: ContractCompiler 写 writing_shot_scene_fingerprints"
```

---

### Task 5: architect_gate 读指纹 + Jaccard 同场景判定

**Files:**
- Modify: `inkflow/src/inkflow/services/architect_gate.py:960-968`（shots 查询加 contract_id）
- Modify: `inkflow/src/inkflow/services/architect_gate.py:1153-1236`（`_check_chapter_scene_diversity`）
- Modify: `inkflow/src/inkflow/services/architect_gate.py:1684-1743`（`_scene_bucket`/`_scene_anchor_terms` 重命名为 fallback）
- Test: `inkflow/tests/test_architect_gate.py`

**Interfaces:**
- Consumes: `writing_shot_scene_fingerprints` 表（按 contract_id 查）。
- Produces: `_check_chapter_scene_diversity()` 改读指纹；新增 `_scene_fingerprint_for_contract(contract_id)`、`_jaccard(a, b)`。

- [ ] **Step 1: 写失败测试**

在 `test_architect_gate.py` 找到 scene_diversity 测试附近追加：

```python
def test_scene_diversity_same_bucket_flagged(db, tmp_dir):
    """整章同 scene_bucket → scene_count_low。"""
    from inkflow.services.architect_gate import ArchitectGate
    import json
    # 建最小 run+shots+contracts+fingerprints：3 shot 全 "转运站月台"
    db.execute("INSERT INTO writing_sessions(run_id) VALUES ('r1')")
    for i in range(1, 4):
        sid = f"sh{i}"
        cid = f"cid{i}"
        db.execute("INSERT INTO writing_shots(shot_id, run_id, layer_key, shot_index, shot_status, light_status) VALUES (?,?,?,?,?,?)",
                   (sid, 'r1', 'c01', i, 'done_green', 'green'))
        db.execute("INSERT INTO writing_shot_contracts(contract_id, shot_id, run_id, contract_json) VALUES (?,?,?,?)",
                   (cid, sid, 'r1', '{}'))
        db.execute("INSERT INTO writing_shot_revisions(revision_id, shot_id, text) VALUES (?,?,'正文内容较长')",
                   (f"rev{i}", sid))
        db.execute("UPDATE writing_shots SET current_revision_id=? WHERE shot_id=?", (f"rev{i}", sid))
        db.execute("INSERT INTO writing_shot_scene_contracts(scene_contract_id, contract_id, location, required_anchors) VALUES (?,?,?,?)",
                   (f"sc{i}", cid, '转运站月台', json.dumps(["军列"])))
        db.execute("INSERT INTO writing_shot_scene_fingerprints(fingerprint_id, contract_id, scene_bucket, event_anchors, source) VALUES (?,?,?,?,'derived')",
                   (f"fp{i}", cid, '转运站月台', json.dumps(["军列"])))
    gate = ArchitectGate(db, run_id="r1")
    result = gate._check_chapter_scene_diversity([
        {"shot_id": f"sh{i}", "shot_index": i} for i in range(1, 4)
    ])
    assert not result["passed"]


def test_scene_diversity_jaccard_catches_anchor_overlap(db, tmp_dir):
    """不同 bucket 但 anchors Jaccard>=0.7 → adjacent_scene_too_similar。"""
    from inkflow.services.architect_gate import ArchitectGate
    import json
    db.execute("INSERT INTO writing_sessions(run_id) VALUES ('r1')")
    anchors_a = json.dumps(["军列", "交接单", "司机"])
    anchors_b = json.dumps(["军列", "交接单", "签字"])  # Jaccard 2/4=0.5 <0.7 → 不应判同
    anchors_c = json.dumps(["军列", "交接单", "司机", "月台"])  # 3/4 与 a 重合 → 0.6
    # 用高度重合: a 与 d 共享 3/3
    anchors_d = json.dumps(["军列", "交接单", "司机"])
    for i, (bucket, anchors) in enumerate([("转运站", anchors_a), ("月台", anchors_d)], 1):
        sid, cid = f"sh{i}", f"cid{i}"
        db.execute("INSERT INTO writing_shots(shot_id, run_id, layer_key, shot_index, shot_status, light_status) VALUES (?,?,?,?,?,?)",
                   (sid, 'r1', 'c01', i, 'done_green', 'green'))
        db.execute("INSERT INTO writing_shot_contracts(contract_id, shot_id, run_id, contract_json) VALUES (?,?,?,?)",
                   (cid, sid, 'r1', '{}'))
        db.execute("INSERT INTO writing_shot_scene_fingerprints(fingerprint_id, contract_id, scene_bucket, event_anchors, source) VALUES (?,?,?,?,'derived')",
                   (f"fp{i}", cid, bucket, anchors))
    gate = ArchitectGate(db, run_id="r1")
    result = gate._check_chapter_scene_diversity([
        {"shot_id": "sh1", "shot_index": 1}, {"shot_id": "sh2", "shot_index": 2},
    ])
    # bucket 不同但 anchors 完全相同 → 应判同场景
    found_similar = any(v["type"] == "adjacent_scene_too_similar" for v in result.get("violations", []))
    assert found_similar


def test_scene_diversity_fallback_when_no_fingerprint(db, tmp_dir):
    """指纹表无记录 → 走 fallback 不崩。"""
    from inkflow.services.architect_gate import ArchitectGate
    db.execute("INSERT INTO writing_sessions(run_id) VALUES ('r1')")
    for i in range(1, 4):
        sid = f"sh{i}"
        db.execute("INSERT INTO writing_shots(shot_id, run_id, layer_key, shot_index, shot_status, light_status) VALUES (?,?,?,?,?,?)",
                   (sid, 'r1', 'c01', i, 'done_green', 'green'))
        db.execute("INSERT INTO writing_shot_revisions(revision_id, shot_id, text) VALUES (?,?,'露天堆场转运站工厂车间正文')",
                   (f"rev{i}", sid))
        db.execute("UPDATE writing_shots SET current_revision_id=? WHERE shot_id=?", (f"rev{i}", sid))
        # 不插 fingerprint 行
    gate = ArchitectGate(db, run_id="r1")
    result = gate._check_chapter_scene_diversity([
        {"shot_id": f"sh{i}", "shot_index": i} for i in range(1, 4)
    ])
    # 不应抛异常；返回结构完整
    assert "passed" in result
    assert "scenes" in result
```

注意：`writing_shot_revisions` 表名与列名以现有 schema 为准——若实际是 `shot_revisions`，按现有测试 fixture 改正。参考 `test_architect_gate.py` 现有 scene_diversity 测试的建表方式对齐。

- [ ] **Step 2: 运行测试验证失败**

Run: `cd inkflow && python -m pytest tests/test_architect_gate.py -q -k "scene_diversity"`
Expected: FAIL（新测试不通过）

- [ ] **Step 3: shots 查询加 contract_id**

`architect_gate.py:961-962` 把 SELECT 列改为加 `wsc.contract_id`：

```python
            "SELECT ws.shot_id, ws.shot_index, ws.shot_status, ws.light_status, "
            "wsc.contract_id, wsc.must_land_json, wsc.pov_routing_json, wsc.contract_json "
```

- [ ] **Step 4: 新增 _scene_fingerprint_for_contract 与 _jaccard**

在 `_scene_contract_from_row` 方法（line 1326）**之后**新增：

```python
    def _scene_fingerprint_for_contract(self, contract_id) -> dict:
        """Fetch the v26 scene fingerprint row for a contract, or empty dict."""
        if not contract_id:
            return {}
        row = self.db.execute(
            "SELECT scene_bucket, time_jump, key_objects, event_anchors, "
            "similarity_hash, source FROM writing_shot_scene_fingerprints "
            "WHERE contract_id = ?",
            (contract_id,),
        ).fetchone()
        if not row:
            return {}
        try:
            anchors = json.loads(row["event_anchors"]) if row["event_anchors"] else []
        except (json.JSONDecodeError, TypeError):
            anchors = []
        try:
            key_objects = json.loads(row["key_objects"]) if row["key_objects"] else []
        except (json.JSONDecodeError, TypeError):
            key_objects = []
        return {
            "scene_bucket": row["scene_bucket"] or "",
            "time_jump": row["time_jump"] or "",
            "key_objects": key_objects,
            "event_anchors": anchors,
            "similarity_hash": row["similarity_hash"] or "",
            "source": row["source"] or "derived",
        }
```

在模块级（`_scene_bucket` 函数附近，line 1684 之前）新增：

```python
def _jaccard(a: list[str], b: list[str]) -> float:
    """Jaccard similarity of two anchor lists (sets)."""
    sa = {x for x in (a or []) if x}
    sb = {x for x in (b or []) if x}
    if not sa and not sb:
        return 0.0
    union = sa | sb
    if not union:
        return 0.0
    return len(sa & sb) / len(union)


def _scenes_same(fp_a: dict, fp_b: dict, text_a: str, text_b: str) -> bool:
    """Decide if two shots are the same scene via fingerprint + Jaccard, fallback to text bucket."""
    bucket_a = (fp_a or {}).get("scene_bucket", "")
    bucket_b = (fp_b or {}).get("scene_bucket", "")
    if bucket_a and bucket_b and bucket_a == bucket_b:
        return True
    anchors_a = (fp_a or {}).get("event_anchors", [])
    anchors_b = (fp_b or {}).get("event_anchors", [])
    if anchors_a and anchors_b and _jaccard(anchors_a, anchors_b) >= 0.7:
        return True
    # fallback：指纹缺失时回退到正文词表（仅当双方都无结构化指纹）
    if not fp_a and not fp_b:
        ba = _fallback_bucket_from_text(text_a)
        bb = _fallback_bucket_from_text(text_b)
        if ba and bb and ba != "unknown" and ba == bb:
            return True
    return False
```

- [ ] **Step 5: 重命名 _scene_bucket / _scene_anchor_terms 为 fallback**

`architect_gate.py:1684` 的 `def _scene_bucket(text):` 改名为 `def _fallback_bucket_from_text(text):`（docstring 改为 "Fallback scene classification from prose; used only when no structured fingerprint exists."）。

`line 1729` 的 `def _scene_anchor_terms(text):` 改名为 `def _fallback_anchors_from_text(text):`。

在原 `_scene_bucket` 名字处加一个兼容别名（防止其他地方仍引用旧名）：

```python
_scene_bucket = _fallback_bucket_from_text
_scene_anchor_terms = _fallback_anchors_from_text
```

放在两个新函数定义之后。

- [ ] **Step 6: 改造 _check_chapter_scene_diversity 读指纹**

把 `architect_gate.py:1153-1236` 的 `_check_chapter_scene_diversity` 方法体替换为：

```python
    def _check_chapter_scene_diversity(self, shots) -> dict:
        """Reject chapters where several shots all land in the same scene.

        v26: reads writing_shot_scene_fingerprints (scene_bucket + event_anchors
        Jaccard) as primary signal; falls back to prose-derived bucket only when
        no fingerprint row exists.
        """
        shot_count = len(shots)
        repo = TextRepository(self.db)
        scenes: list[dict] = []
        violations: list[dict] = []

        for shot in shots:
            text = repo.get_shot_text(shot["shot_id"])
            if not (text or "").strip():
                continue
            contract_id = shot.get("contract_id")
            fp = self._scene_fingerprint_for_contract(contract_id)
            bucket = fp.get("scene_bucket", "") if fp else ""
            if not bucket and not fp:
                bucket = _fallback_bucket_from_text(text)
            opening = _normalize_opening(text)
            fingerprint = bucket if bucket and bucket != "unknown" else opening[:90]
            scenes.append({
                "shot_id": shot["shot_id"],
                "shot_index": shot["shot_index"],
                "bucket": bucket,
                "fingerprint": fingerprint,
                "opening": _first_sentence(text)[:90],
                "bytes": _utf8_size(text),
                "anchors": fp.get("event_anchors", []) if fp else [],
                "fp_source": fp.get("source", "") if fp else "fallback",
            })

        if shot_count < 3 or len(scenes) < 3:
            return {
                "passed": True,
                "shot_count": shot_count,
                "scene_count": len(scenes),
                "distinct_count": 0,
                "min_required": 0,
                "scenes": scenes,
                "violations": [],
            }

        # distinct scene count via _scenes_same pairwise
        groups: list[int] = []
        representative: list[dict] = []
        for s in scenes:
            placed = False
            for gi, rep in enumerate(representative):
                if _scenes_same(
                    {"scene_bucket": s["bucket"], "event_anchors": s["anchors"]},
                    {"scene_bucket": rep["bucket"], "event_anchors": rep["anchors"]},
                    "", "",
                ):
                    groups.append(gi)
                    placed = True
                    break
            if not placed:
                representative.append(s)
                groups.append(len(representative) - 1)
        distinct_count = len(representative)
        min_required = min(len(scenes), 3)
        if distinct_count < min_required:
            violations.append({
                "type": "scene_count_low",
                "reason": (
                    f"only {distinct_count} distinct scene(s) for {len(scenes)} "
                    f"shot(s), require >= {min_required}"
                ),
            })

        buckets = [s["bucket"] for s in scenes if s["bucket"] and s["bucket"] != "unknown"]
        if len(buckets) == len(scenes) and len(set(buckets)) == 1:
            violations.append({
                "type": "scene_bucket_collapsed",
                "bucket": buckets[0],
                "reason": f"all shots land in scene bucket '{buckets[0]}'",
            })

        for left, right in zip(scenes, scenes[1:]):
            same = _scenes_same(
                {"scene_bucket": left["bucket"], "event_anchors": left["anchors"]},
                {"scene_bucket": right["bucket"], "event_anchors": right["anchors"]},
                "", "",
            )
            if not same:
                continue
            left_opening = left["fingerprint"]
            right_opening = right["fingerprint"]
            if not left_opening or not right_opening:
                # 同场景但无 opening 文本可比 → 仍记为相邻相似（场景层面重复）
                violations.append({
                    "type": "adjacent_scene_too_similar",
                    "left": left["shot_index"],
                    "right": right["shot_index"],
                    "similarity": 1.0,
                    "reason": (
                        f"s{left['shot_index']:02d}/s{right['shot_index']:02d} "
                        f"same scene (bucket/anchors)"
                    ),
                })
                continue
            similarity = difflib.SequenceMatcher(
                None, left_opening, right_opening,
            ).ratio()
            if similarity >= 0.72:
                violations.append({
                    "type": "adjacent_scene_too_similar",
                    "left": left["shot_index"],
                    "right": right["shot_index"],
                    "similarity": round(similarity, 3),
                    "reason": (
                        f"s{left['shot_index']:02d}/s{right['shot_index']:02d} "
                        f"scene opening similarity {similarity:.2f}"
                    ),
                })

        return {
            "passed": not violations,
            "shot_count": shot_count,
            "scene_count": len(scenes),
            "distinct_count": distinct_count,
            "min_required": min_required,
            "scenes": scenes,
            "violations": violations,
        }
```

- [ ] **Step 7: 运行测试验证通过**

Run: `cd inkflow && python -m pytest tests/test_architect_gate.py -q -k "scene_diversity"`
Expected: PASS

- [ ] **Step 8: 提交**

```bash
git add inkflow/src/inkflow/services/architect_gate.py inkflow/tests/test_architect_gate.py
git commit -m "feat: L3 scene_diversity 读结构化指纹 + Jaccard 同场景判定"
```

---

### Task 6: 全量回归 + 文档同步

**Files:**
- Modify: `inkflow/docs/history.md`（追加 v3.28 段）
- Modify: `inkflow/TASKS.md`（标记 SCENE-FINGERPRINT-1 完成；Status passed 数更新）
- Modify: `inkflow/docs/bugfix.md`（若有 bug 记录则追加）

- [ ] **Step 1: 全量回归**

Run: `cd inkflow && python -m pytest tests/ -q`
Expected: 全绿（531+ passed）。若有失败，逐个修复后重跑。

- [ ] **Step 2: 更新 history.md**

在 v3.27 段之前追加 v3.28 段：

```markdown
## v3.28 结构化场景指纹 (2026-07-02)

把 L3 scene_diversity 从"正文猜桶"改为"读结构化指纹",新增 Schema v26 `writing_shot_scene_fingerprints` 表。

### 完成项

- 新增 `writing_shot_scene_fingerprints` 表(scene_bucket/time_jump/key_objects/event_anchors/similarity_hash/source),UNIQUE(contract_id) 一对一。
- migration v25→v26 建表 + 从已有 scene_contract 回填指纹。
- `_derive_scene_contract()` 同步计算指纹,ContractCompiler 落库到新表。
- L3 `_check_chapter_scene_diversity()` 改读指纹:同场景判定双防线 `scene_bucket` 相等 或 `event_anchors` Jaccard >= 0.7。
- 硬编码 `_scene_bucket`/`_scene_anchor_terms` 重命名为 fallback 别名,仅在指纹缺失时兜底。

### 验证

- 全量回归:NNN passed, 4 warnings。
```

把 `NNN` 替换为 Step 1 实际通过数。

- [ ] **Step 3: 更新 TASKS.md**

Status 行把 `531 passed` 改为 Step 1 实际数;P0 表里 `SCENE-FINGERPRINT-1` 行改为"已完成"(或从 open-only 待办移除,因 TASKS.md 是 open-only)。

- [ ] **Step 4: 提交**

```bash
git add inkflow/docs/history.md inkflow/TASKS.md inkflow/docs/bugfix.md
git commit -m "docs: v3.28 结构化场景指纹完成同步"
```

---

## Self-Review

**1. Spec coverage:**
- §4 表定义 → Task 1 ✓
- §8 迁移+回填 → Task 2 ✓
- §5/§6 生成时机+计算规则 → Task 3 ✓
- 落库 → Task 4 ✓
- §7 gate 改造+双防线+兜底 → Task 5 ✓
- §9 测试 → 各 Task 内 ✓
- 文档 → Task 6 ✓

**2. Placeholder scan:** Task 6 Step 2 的 `NNN` 是待填实际数（运行后填），非设计占位。其余无 TBD/TODO。

**3. Type consistency:** `_derive_fingerprint` 返回的 dict 键（scene_bucket/time_jump/key_objects/event_anchors/similarity_hash/source）与 Task 4 写库、Task 5 `_scene_fingerprint_for_contract` 读取的键一致。`_normalize_bucket`（migration）与 `_normalize_scene_bucket`（cli）逻辑相同，分处两文件避免跨层依赖。`_scenes_same` 签名在 Task 5 Step 4/6 使用一致。
