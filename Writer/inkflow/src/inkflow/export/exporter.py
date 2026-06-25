"""InkFlow exporter — DB → Markdown.

Reads current revisions from inkflow.db and writes a clean Markdown file
suitable for human review. Separates chapters by layer_key, marks baseline
shots, and annotates AI-generated shots with light status and POV.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from inkflow.services.text_repository import TextRepository


def export_markdown(
    db: sqlite3.Connection,
    output_path: str | Path,
    *,
    title: str | None = None,
    chapters: list[str] | None = None,
) -> Path:
    """Export current revisions to Markdown.

    Args:
        db: Open inkflow.db connection with row_factory=sqlite3.Row.
        output_path: Where to write the .md file.
        title: Override book title (default: read from meta-contract).
        chapters: Which chapter layer_keys to export (default: all).

    Returns:
        Path to the written file.
    """
    if not title:
        title = _resolve_title(db)

    if chapters is None:
        chapters = _list_chapters(db)

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    repo = TextRepository(db)

    lines: list[str] = []
    lines.append(f"# 《{title}》\n")

    for chapter_key in chapters:
        lines.append(f"\n## 第 {_chapter_label(chapter_key)} 章\n")

        shots = db.execute(
            "SELECT ws.shot_id, ws.shot_index, ws.shot_status, ws.light_status, "
            "ws.is_baseline, ws.brilliance_level, ws.badsmell_level, "
            "wsc.pov_routing_json, wsc.must_land_json "
            "FROM writing_shots ws "
            "LEFT JOIN writing_shot_contracts wsc "
            "  ON ws.shot_id = wsc.shot_id AND ws.run_id = wsc.run_id "
            "WHERE ws.layer_key = ? "
            "ORDER BY ws.shot_index",
            (chapter_key,),
        ).fetchall()

        if not shots:
            lines.append("\n（无内容）\n")
            continue

        for s in shots:
            text = repo.get_shot_text(s["shot_id"])
            if not text.strip():
                continue

            # Build shot header with title from contract
            header_title = _resolve_title_from_contract(s["must_land_json"])
            annotations = []
            if s["is_baseline"]:
                annotations.append("baseline · locked")
            else:
                icon = _light_icon(s["light_status"])
                pov = _resolve_pov(s["pov_routing_json"])
                annotations.append(f"{icon} {s['light_status']}")

                if s["brilliance_level"]:
                    annotations.append(f"brilliance={s['brilliance_level']}")
                if s["badsmell_level"]:
                    annotations.append(f"badsmell={s['badsmell_level']}")
                if pov:
                    annotations.append(f"POV={pov}")

            if header_title:
                header = f"### 场景 {s['shot_index']}：{header_title} — {' · '.join(annotations)}"
            else:
                header = f"### 场景 {s['shot_index']} — {' · '.join(annotations)}"
            lines.append(f"\n{header}\n")
            lines.append(text)
            lines.append("")

    content = "\n".join(lines)
    output_path.write_text(content, encoding="utf-8")
    return output_path


def export_plain_text(
    db: sqlite3.Connection,
    output_path: str | Path,
    *,
    chapters: list[str] | None = None,
) -> Path:
    """Export current revisions as plain text (no annotations, no headers).

    Useful for feeding into Chesil or other tools that expect clean text.
    """
    if chapters is None:
        chapters = _list_chapters(db)

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    repo = TextRepository(db)
    blocks: list[str] = []
    for chapter_key in chapters:
        shot_rows = db.execute(
            "SELECT ws.shot_id "
            "FROM writing_shots ws "
            "WHERE ws.layer_key = ? "
            "ORDER BY ws.shot_index",
            (chapter_key,),
        ).fetchall()
        for row in shot_rows:
            text = repo.get_shot_text(row["shot_id"])
            if text and text.strip():
                blocks.append(text.strip())

    output_path.write_text("\n\n".join(blocks), encoding="utf-8")
    return output_path


# ── helpers ──

def _resolve_title(db: sqlite3.Connection) -> str:
    row = db.execute("SELECT name FROM projects LIMIT 1").fetchone()
    if row:
        return row["name"]

    # Fallback: try meta-contract
    row = db.execute(
        "SELECT layers_json FROM writing_meta_contract "
        "ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    if row:
        layers = json.loads(row["layers_json"])
        return layers.get("identity", {}).get("title", "未命名")

    return "未命名"


def _list_chapters(db: sqlite3.Connection) -> list[str]:
    rows = db.execute(
        "SELECT DISTINCT layer_key FROM writing_shots ORDER BY layer_key"
    ).fetchall()
    return [r["layer_key"] for r in rows]


def _chapter_label(layer_key: str) -> str:
    """v01.c02 → '2'"""
    parts = layer_key.split(".")
    for p in parts:
        if p.startswith("c"):
            try:
                return str(int(p[1:]))
            except ValueError:
                return p
    return layer_key


def _light_icon(status: str | None) -> str:
    if status == "green":
        return "🟢"
    if status == "yellow":
        return "🟡"
    if status == "red":
        return "🔴"
    return "⚪"


def _resolve_pov(pov_json: str | None) -> str | None:
    if not pov_json:
        return None
    try:
        data = json.loads(pov_json) if isinstance(pov_json, str) else pov_json
        return data.get("pov_character")
    except (json.JSONDecodeError, TypeError):
        return None


def _resolve_title_from_contract(must_land_json: str | None) -> str | None:
    """Extract shot title from must_land contract."""
    if not must_land_json:
        return None
    try:
        data = json.loads(must_land_json) if isinstance(must_land_json, str) else must_land_json
        return data.get("title")
    except (json.JSONDecodeError, TypeError):
        return None