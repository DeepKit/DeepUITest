"""tools/load_chapter_setup.py 单测。

构造 in-memory schema DB + setup 风格的 shot 骨架（含 must_land/anti_write/scene
子表），写一份最小章纲 yaml，验证：
  1. 注入后 must_land.events 含 yaml must_land 事件
  2. anti_write.pov_only 含 yaml pov
  3. anti_write.forbidden_words 含 yaml anti_patterns（且并入非替换——保留 setup 灌的软禁词）
  4. anti_write.forbidden_facts 含章级 forbidden_phrases
  5. beats/information_releases 不被破坏（schema CHECK 要求 >0）
  6. 幂等：重复跑结果一致，不重复并入
  7. yaml 有但 DB 无骨架的 shot 跳过不报错
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
import textwrap

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))

from factories import NOW, insert_minimal_draft, make_schema_db  # noqa: E402

import load_chapter_setup as lcs  # noqa: E402


def _make_db_with_run() -> sqlite3.Connection:
    """make_schema_db + insert_minimal_draft 建 project(1)/session(10)/run(20)。"""
    conn = make_schema_db()
    insert_minimal_draft(conn)
    conn.commit()
    return conn


def _seed_shot_skeleton(conn: sqlite3.Connection, run_id: int, chapter: int, shot_no: int) -> int:
    """仿 ink setup 的 _insert_contract_children：建 shot 行 + 5 张子表（含默认非空值）。"""
    logical_shot_id = f"ch-{chapter:02d}-shot-{shot_no:03d}"
    cur = conn.execute(
        """
        INSERT INTO writing_shot_contracts
            (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
        VALUES (1, ?, ?, ?, 'confirmed', ?, ?)
        """,
        (chapter, run_id, logical_shot_id, NOW, NOW),
    )
    scid = int(cur.lastrowid)
    shot_id = f"{logical_shot_id}@{run_id}"
    conn.execute(
        """
        INSERT INTO writing_shots
            (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id, status, created_at, updated_at)
        VALUES (?, 1, ?, ?, ?, ?, 'pending', ?, ?)
        """,
        (shot_id, chapter, scid, run_id, logical_shot_id, NOW, NOW),
    )
    # must_land：setup 默认灌 must_land_events=["发现钥匙"], beats=["发现钥匙"]
    conn.execute(
        "INSERT INTO writing_shot_must_land (shot_contract_id, events, beats, information_releases) "
        "VALUES (?, ?, ?, ?)",
        (scid, json.dumps(["发现钥匙"], ensure_ascii=False),
         json.dumps(["发现钥匙"], ensure_ascii=False), json.dumps([])),
    )
    # anti_write：setup 默认 forbidden_words=["突然","忽然"], 其余空
    conn.execute(
        "INSERT INTO writing_shot_anti_write (shot_contract_id, forbidden_facts, forbidden_words, pov_only) "
        "VALUES (?, ?, ?, ?)",
        (scid, json.dumps([]), json.dumps(["突然", "忽然"], ensure_ascii=False), json.dumps([])),
    )
    # scene_contract + persona + soft_constraints（setup 必灌，loader JOIN 要全，但本测不验证这些列）
    conn.execute(
        "INSERT INTO writing_shot_scene_contract (shot_contract_id, location, time_of_day, characters_present, character_positions) "
        "VALUES (?, ?, ?, ?, ?)",
        (scid, "厂区仓库外", "白昼", json.dumps(["许怀山"]), json.dumps({})),
    )
    conn.execute(
        "INSERT INTO writing_shot_persona_assignment (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot) "
        "VALUES (?, ?, ?, ?, ?)",
        (scid, "结构师", json.dumps({"画面": 8, "节奏": 7, "对话": 6, "结构": 9, "悬疑": 5}), 0, 1),
    )
    conn.execute(
        "INSERT INTO writing_shot_soft_constraints (shot_contract_id, relaxable_rules, deviation_budget) "
        "VALUES (?, ?, ?)",
        (scid, json.dumps([]), 0),
    )
    return scid


def _make_yaml(tmp_path) -> str:
    """最小章纲 yaml：2 个 shot + 章级 forbidden_phrases。"""
    content = textwrap.dedent(
        """\
        chapter: 2
        shots:
          - shot: 1
            title: 装车
            pov: 许怀山
            must_land: 产出物：第十七批封装箱，共十二箱。场景：厂区仓库外，卡车已在等
            anti_patterns:
              - 禁止把意象解释成主题
              - 禁止长段系统议论
          - shot: 2
            title: 冲突1
            pov: 吕素琴
            must_land: 吕素琴发现异常样件湿度临界点波动
            anti_patterns:
              - 禁止用总结句替代动作
        fact_manifest:
          global:
            forbidden_phrases:
              - "那时候的人还相信"
              - "时代的洪流"
        """
    )
    p = tmp_path / "v01.c02.yaml"
    p.write_text(content, encoding="utf-8")
    return str(p)


def _get(conn: sqlite3.Connection, scid: int, table: str, cols: str) -> tuple:
    row = conn.execute(f"SELECT {cols} FROM {table} WHERE shot_contract_id = ?", (scid,)).fetchone()
    return tuple(json.loads(c or "[]") for c in row)


def test_apply_chapter_setup_overwrites_and_merges(tmp_path):
    conn = _make_db_with_run()
    # setup 灌 c02 共 2 shot 骨架（模拟）
    scid1 = _seed_shot_skeleton(conn, run_id=20, chapter=2, shot_no=1)
    scid2 = _seed_shot_skeleton(conn, run_id=20, chapter=2, shot_no=2)
    yaml_path = _make_yaml(tmp_path)

    stats = lcs.apply_chapter_setup(conn, project_id=1, run_id=20, chapter=2, yaml_path=yaml_path)
    conn.commit()

    assert stats["updated"] == 2
    assert stats["skipped_db"] == 0

    # shot1 must_land.events 含 yaml must_land 切分后的事件
    events, beats, releases = _get(conn, scid1, "writing_shot_must_land", "events, beats, information_releases")
    assert any("封装箱" in e for e in events), f"events 未含章纲 must_land: {events}"
    # beats 不被破坏（schema CHECK 要求 >0）
    assert len(beats) > 0, "beats 被置空破坏了 setup 默认值"

    # shot1 anti_write：pov_only 含许怀山，forbidden_words 含 anti_patterns + 保留"突然/忽然"
    facts, words, pov = _get(conn, scid1, "writing_shot_anti_write", "forbidden_facts, forbidden_words, pov_only")
    assert "许怀山" in pov, f"pov_only 未含章纲 pov: {pov}"
    assert "禁止把意象解释成主题" in words, f"forbidden_words 未含 anti_patterns: {words}"
    assert "突然" in words and "忽然" in words, f"setup 灌的软禁词被替换了（应并入保留）: {words}"
    # 章级 forbidden_phrases 入 forbidden_facts
    assert "那时候的人还相信" in facts, f"forbidden_facts 未含章级 forbidden_phrases: {facts}"


def test_apply_chapter_setup_skips_missing_skeleton(tmp_path):
    """yaml 有 2 shot 但 DB 只建了 shot1——shot2 跳过(skipped_db)，不报错。"""
    conn = _make_db_with_run()
    _seed_shot_skeleton(conn, run_id=20, chapter=2, shot_no=1)  # 只建 shot1
    yaml_path = _make_yaml(tmp_path)

    stats = lcs.apply_chapter_setup(conn, project_id=1, run_id=20, chapter=2, yaml_path=yaml_path)
    conn.commit()
    assert stats["updated"] == 1
    assert stats["skipped_db"] == 1  # shot2 骨架缺失被跳过


def test_apply_chapter_setup_idempotent(tmp_path):
    """重复跑两遍，结果一致（forbidden_words 不重复并入）。"""
    conn = _make_db_with_run()
    _seed_shot_skeleton(conn, run_id=20, chapter=2, shot_no=1)
    _seed_shot_skeleton(conn, run_id=20, chapter=2, shot_no=2)
    yaml_path = _make_yaml(tmp_path)

    lcs.apply_chapter_setup(conn, 1, 20, 2, yaml_path)
    conn.commit()
    stats2 = lcs.apply_chapter_setup(conn, 1, 20, 2, yaml_path)  # 第二遍
    conn.commit()

    assert stats2["updated"] == 2  # 仍更新（幂等=结果不变，不是 no-op）
    facts, words, pov = _get(conn, _shot1_scid(conn), "writing_shot_anti_write", "forbidden_facts, forbidden_words, pov_only")
    # 第二遍后 forbidden_words 无重复条目
    assert words.count("禁止把意象解释成主题") == 1, f"重复并入导致重复: {words}"
    assert words.count("突然") == 1, f"软禁词重复: {words}"


def _shot1_scid(conn: sqlite3.Connection) -> int:
    row = conn.execute(
        "SELECT shot_contract_id FROM writing_shots WHERE logical_shot_id = ? AND run_id = ?",
        ("ch-02-shot-001", 20),
    ).fetchone()
    return int(row[0])


def test_split_must_land_splits_into_events():
    out = lcs._split_must_land("产出物：第十七批封装箱，共十二箱。场景：厂区仓库外，卡车已在等")
    assert len(out) >= 2  # 被 。/， 切成多事件
    assert any("封装箱" in e for e in out)


def test_split_must_land_single_returns_self():
    assert lcs._split_must_land("单一事件无标点") == ["单一事件无标点"]
    assert lcs._split_must_land("") == []
