"""《白灯法则》章纲逐 shot 注入脚本（通用加载器）。

把 ``.inkflow/chapter-setups/v01.cXX.yaml`` 章纲里的**逐 shot 差异化内容**
（must_land / anti_patterns / pov / 章级 forbidden_phrases）覆写到 DB 的
契约子表，弥补 ``ink setup`` 只能全局灌相同 must_land 的局限（cli.py 的
``_insert_contract_children`` 对每 shot 灌同一份 options.must_land_events）。

设计原则（与主线解耦）：本脚本只**覆写** setup 已建的 shot 骨架子表，不建
新 shot 行——shot 骨架（shot_id/contract/status）由 ``ink setup`` 统一建，
本脚本只把通用占位 must_land/anti_write/scene 替换成章纲逐 shot 真值提保真。

幂等：用 ``UPDATE ... WHERE shot_contract_id`` 定位（shot_contract_id 由
``logical_shot_id = ch-{chapter:02d}-shot-{shot:03d}`` + run_id 反查），
重复跑只更新不重复插入、不建行。yaml 中缺失的 shot 序号跳过（不报错）。

映射：
  - shot.must_land          → writing_shot_must_land.events（split 成 array；
    beats/information_releases 不动——setup 已灌默认非空值，schema CHECK 要求 >0）
  - shot.anti_patterns      → writing_shot_anti_write.forbidden_words（并入非替换，
    保留 setup 灌的"突然/忽然"软禁词）
  - shot.pov                → writing_shot_anti_write.pov_only（[pov]）
  - fact_manifest.global.forbidden_phrases → writing_shot_anti_write.forbidden_facts
    （章级 AI 腔/说明文禁漂移词，每 shot 共享）

用法：
  python tools/load_chapter_setup.py \\
    --db "D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db" \\
    --project-id 1 --run-id 1 --chapter 2 \\
    --yaml "D:/_Progs/.Story/《白灯法则》/.inkflow/chapter-setups/v01.c02.yaml"
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys

DEFAULT_DB = r"D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db"
DEFAULT_PROJECT_ID = 1


def log(msg: str) -> None:
    print(f"[load_chapter_setup] {msg}", file=sys.stderr)


def _shot_contract_id(conn: sqlite3.Connection, run_id: int, chapter: int, shot_no: int) -> int | None:
    """按 logical_shot_id + run_id 反查 shot_contract_id（setup 建骨架时命名）。

    logical_shot_id 形如 ``ch-02-shot-001``（cli.py:_cmd_setup line 672）。
    shot 骨架缺失返回 None——调用方跳过该 shot（yaml 有但 DB 无，不报错）。
    """
    logical_shot_id = f"ch-{chapter:02d}-shot-{shot_no:03d}"
    row = conn.execute(
        """
        SELECT s.shot_contract_id
        FROM writing_shots s
        WHERE s.run_id = ? AND s.logical_shot_id = ?
        """,
        (run_id, logical_shot_id),
    ).fetchone()
    return int(row[0]) if row else None


def _merge_unique(*lists: list[str]) -> list[str]:
    """多 list 合并去重，保序（先出现的在前）。"""
    seen: set[str] = set()
    out: list[str] = []
    for lst in lists:
        for item in lst:
            if item and item not in seen:
                seen.add(item)
                out.append(item)
    return out


def _split_must_land(must_land_text: str) -> list[str]:
    """把章纲 must_land 自由文本切成事件 array。

    章纲 must_land 是一句话含多个事件点（"；"/"，"/"——"分隔），
    DB schema 要求 events 为非空 array。切完为空则整句作为一个 event。
    """
    if not must_land_text:
        return []
    # 按句号/分号/破折号断句，再按逗号细分——保留语义完整的事件单元
    raw = must_land_text.replace("——", "；").replace("。", "；").replace("，", "；")
    parts = [p.strip() for p in raw.split("；") if p.strip()]
    if not parts:
        return [must_land_text.strip()]
    return parts


def _json_load(row_col: str) -> list[str]:
    if not row_col:
        return []
    try:
        v = json.loads(row_col)
        return v if isinstance(v, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


def apply_chapter_setup(
    conn: sqlite3.Connection,
    project_id: int,
    run_id: int,
    chapter: int,
    yaml_path: str,
) -> dict[str, int]:
    """读章纲 yaml,逐 shot 覆写 DB 子表。返回统计 {updated,skipped_yaml,skipped_db}。"""
    import yaml  # 延迟导入，脚本无 pyyaml 也能解析参数报错

    with open(yaml_path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)

    fact_manifest = doc.get("fact_manifest", {}) or {}
    global_fm = fact_manifest.get("global", {}) or {}
    chapter_forbidden_phrases: list[str] = list(global_fm.get("forbidden_phrases", []) or [])

    shots = doc.get("shots", []) or []
    if not shots:
        log(f"WARN yaml 无 shots 字段: {yaml_path}")
        return {"updated": 0, "skipped_yaml": 0, "skipped_db": 0}

    updated = 0
    skipped_db = 0
    for shot in shots:
        shot_no = int(shot.get("shot", 0))
        if not shot_no:
            log(f"  跳过无序号 shot: {shot.get('title', '?')}")
            continue
        scid = _shot_contract_id(conn, run_id, chapter, shot_no)
        if scid is None:
            skipped_db += 1
            log(f"  跳过 shot {shot_no}「{shot.get('title', '?')}」: DB 无骨架(logical_shot_id=ch-{chapter:02d}-shot-{shot_no:03d}, run_id={run_id})")
            continue

        # --- must_land.events 覆写（beats/information_releases 不动）---
        events = _split_must_land(shot.get("must_land", "") or "")
        if events:
            conn.execute(
                "UPDATE writing_shot_must_land SET events = ? WHERE shot_contract_id = ?",
                (json.dumps(events, ensure_ascii=False), scid),
            )

        # --- anti_write 三列合并覆写 ---
        aw_row = conn.execute(
            "SELECT forbidden_facts, forbidden_words, pov_only FROM writing_shot_anti_write WHERE shot_contract_id = ?",
            (scid,),
        ).fetchone()
        existing_facts = _json_load(aw_row[0]) if aw_row else []
        existing_words = _json_load(aw_row[1]) if aw_row else []
        existing_pov = _json_load(aw_row[2]) if aw_row else []

        # anti_patterns 并入 forbidden_words（保留 setup 灌的软禁词）
        anti_patterns = list(shot.get("anti_patterns", []) or [])
        new_words = _merge_unique(existing_words, anti_patterns)

        # pov 入 pov_only
        pov = shot.get("pov")
        new_pov = _merge_unique(existing_pov, [pov] if pov else [])

        # 章级 forbidden_phrases 并入 forbidden_facts（每 shot 共享）
        new_facts = _merge_unique(existing_facts, chapter_forbidden_phrases)

        conn.execute(
            """
            UPDATE writing_shot_anti_write
            SET forbidden_facts = ?, forbidden_words = ?, pov_only = ?
            WHERE shot_contract_id = ?
            """,
            (
                json.dumps(new_facts, ensure_ascii=False),
                json.dumps(new_words, ensure_ascii=False),
                json.dumps(new_pov, ensure_ascii=False),
                scid,
            ),
        )
        updated += 1
        log(f"  ✓ shot {shot_no}「{shot.get('title', '?')}」scid={scid}: events={len(events)} facts={len(new_facts)} words={len(new_words)} pov={new_pov}")

    return {"updated": updated, "skipped_yaml": 0, "skipped_db": skipped_db}


def main(project_id: int, run_id: int, chapter: int, yaml_path: str, db_path: str) -> int:
    if not os.path.isfile(yaml_path):
        log(f"ERROR 章纲不存在: {yaml_path}")
        return 2
    if not os.path.isfile(db_path):
        log(f"ERROR DB 不存在: {db_path}")
        return 2
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        stats = apply_chapter_setup(conn, project_id, run_id, chapter, yaml_path)
        conn.commit()
        log(f"完成 chapter={chapter} project={project_id} run={run_id}: "
            f"覆写 {stats['updated']} shot，跳过(DB无骨架) {stats['skipped_db']}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="章纲逐 shot 注入脚本（通用加载器）")
    ap.add_argument("--db", dest="db_path", default=DEFAULT_DB, help="inkflow.db 路径")
    ap.add_argument("--project-id", type=int, default=DEFAULT_PROJECT_ID)
    ap.add_argument("--run-id", type=int, required=True, help="writing_runs.run_id（setup 前/后均可，run 行须先建）")
    ap.add_argument("--chapter", type=int, required=True, help="章号，对应 logical_shot_id ch-XX")
    ap.add_argument("--yaml", dest="yaml_path", required=True, help="章纲 v01.cXX.yaml 路径")
    args = ap.parse_args()
    sys.exit(main(args.project_id, args.run_id, args.chapter, args.yaml_path, args.db_path))
