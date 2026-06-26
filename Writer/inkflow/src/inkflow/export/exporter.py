"""InkFlow exporter — DB → Markdown.

Reads current revisions from inkflow.db and writes a clean Markdown file
suitable for human review. Separates chapters by layer_key while keeping
internal production metadata out of the editor-facing manuscript.
"""

from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path

from inkflow.services.text_repository import TextRepository

_TARGET_PARAGRAPH_CHARS = 300
_MAX_PARAGRAPH_CHARS = 420
_SENTENCE_END_CHARS = "。！？；…"
_SOFT_BREAK_CHARS = "，、：,;"
_CLOSING_PUNCT = "”’）】》」』"


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
            "SELECT ws.shot_id, ws.shot_index, wsc.must_land_json "
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

        rendered_shot_count = 0
        for s in shots:
            text = repo.get_shot_text(s["shot_id"])
            if not text.strip():
                continue

            if rendered_shot_count > 0:
                lines.append("\n---\n")

            # Editor-facing export keeps contract titles but hides pipeline metadata.
            header_title = _resolve_title_from_contract(s["must_land_json"])
            if header_title:
                lines.append(f"\n### {header_title}\n")
            lines.append(_format_prose_for_export(text))
            lines.append("")
            rendered_shot_count += 1

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


def _format_prose_for_export(text: str) -> str:
    """Normalize manuscript spacing and split long prose paragraphs for review."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not normalized:
        return ""

    output_blocks: list[str] = []
    for block in re.split(r"\n\s*\n+", normalized):
        block = block.strip()
        if not block:
            continue

        if _is_generated_heading_block(block):
            continue

        if _is_structural_markdown_block(block):
            output_blocks.append(block)
            continue

        lines = [line.strip() for line in block.split("\n") if line.strip()]
        if len(lines) > 1:
            for line in lines:
                output_blocks.extend(_split_long_paragraph(line))
        else:
            output_blocks.extend(_split_long_paragraph(lines[0]))

    return "\n\n".join(output_blocks)


def _is_generated_heading_block(block: str) -> bool:
    """Drop Markdown headings generated inside prose; exporter supplies titles."""
    stripped = block.lstrip()
    return bool(re.match(r"^#{1,6}\s+\S+", stripped))


def _is_structural_markdown_block(block: str) -> bool:
    """Leave lists, quotes, tables, and code blocks untouched."""
    stripped = block.lstrip()
    if stripped.startswith(("```", "- ", "* ", "> ", "|")):
        return True
    return False


def _split_long_paragraph(paragraph: str) -> list[str]:
    paragraph = re.sub(r"[ \t]+", " ", paragraph.strip())
    if len(paragraph) <= _MAX_PARAGRAPH_CHARS:
        return [paragraph]

    chunks: list[str] = []
    current = ""
    for sentence in _split_sentences(paragraph):
        pieces = _split_oversized_sentence(sentence)
        for piece in pieces:
            if not current:
                current = piece
                continue
            if len(current) >= _TARGET_PARAGRAPH_CHARS or (
                len(current) + len(piece) > _MAX_PARAGRAPH_CHARS
            ):
                chunks.append(current.strip())
                current = piece
            else:
                current += piece

    if current.strip():
        chunks.append(current.strip())

    return chunks or [paragraph]


def _split_sentences(paragraph: str) -> list[str]:
    sentences: list[str] = []
    start = 0
    i = 0
    while i < len(paragraph):
        if paragraph[i] in _SENTENCE_END_CHARS:
            end = i + 1
            while end < len(paragraph) and paragraph[end] in _CLOSING_PUNCT:
                end += 1
            sentence = paragraph[start:end].strip()
            if sentence:
                sentences.append(sentence)
            start = end
            i = end
            continue
        i += 1

    tail = paragraph[start:].strip()
    if tail:
        sentences.append(tail)
    return sentences or [paragraph]


def _split_oversized_sentence(sentence: str) -> list[str]:
    """Best-effort fallback for very long sentences with comma-like pauses."""
    if len(sentence) <= _MAX_PARAGRAPH_CHARS:
        return [sentence]

    parts: list[str] = []
    start = 0
    for i, char in enumerate(sentence):
        if char in _SOFT_BREAK_CHARS and i - start >= _TARGET_PARAGRAPH_CHARS:
            parts.append(sentence[start : i + 1].strip())
            start = i + 1

    tail = sentence[start:].strip()
    if tail:
        parts.append(tail)
    return parts or [sentence]


def _resolve_title_from_contract(must_land_json: str | None) -> str | None:
    """Extract shot title from must_land contract."""
    if not must_land_json:
        return None
    try:
        data = json.loads(must_land_json) if isinstance(must_land_json, str) else must_land_json
        return data.get("title")
    except (json.JSONDecodeError, TypeError):
        return None
