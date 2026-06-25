"""Shot splitter — detects shot boundaries in narrative text.

Uses structural markers (## scene headers) and can optionally use LLM
for semantic shot boundary detection.

For P0: shot boundaries are detected from Markdown scene headers (## 一, ## 二, etc.)
which serve as shot boundaries. Human review is supported via `ink review-shots`.
"""

from __future__ import annotations

import re

from inkflow.utils.ulid import generate as generate_ulid


def split_by_scene_headers(text: str) -> list[dict]:
    """Split text into shots using ## scene headers.

    Each ## header marks the start of a new shot. The chapter title
    (# header) is skipped. Content before the first ## header is preserved
    as a "prologue" shot.

    Returns empty list if no ## headers are found (caller should fall back).

    Args:
        text: Full chapter Markdown text.

    Returns:
        List of dicts: {shot_index, title, text, char_count}
    """
    lines = text.split("\n")
    shots = []
    current_title = ""
    current_lines = []
    prologue_lines = []
    found_first_header = False

    for line in lines:
        if line.startswith("# ") and not line.startswith("## "):
            # Chapter title only — skip
            continue
        elif line.startswith("## "):
            # Before first header: any accumulated non-header lines are prologue
            if not found_first_header and current_lines:
                body = "\n".join(current_lines).strip()
                if body:
                    prologue_lines = current_lines[:]

            # Save previous shot (if any)
            if found_first_header and current_lines:
                body = "\n".join(current_lines).strip()
                if body:
                    shots.append({
                        "shot_index": len(shots) + 1,
                        "title": current_title,
                        "text": body,
                    })
                else:
                    # Consecutive ## headers: save empty-body shot with placeholder
                    shots.append({
                        "shot_index": len(shots) + 1,
                        "title": current_title,
                        "text": f"[空场景: {current_title}]",
                    })
            # Start new shot
            current_title = line.lstrip("# ").strip()
            current_lines = []
            found_first_header = True
        else:
            current_lines.append(line)

    # Don't forget the last shot
    if found_first_header and current_title:
        body = "\n".join(current_lines).strip()
        if body:
            shots.append({
                "shot_index": len(shots) + 1,
                "title": current_title,
                "text": body,
            })
        elif current_lines or not shots:
            # Consecutive ## headers: save empty-body shot with placeholder
            shots.append({
                "shot_index": len(shots) + 1,
                "title": current_title,
                "text": f"[空场景: {current_title}]",
            })

    # Prepend prologue if there was content before the first ## header
    prologue_body = "\n".join(prologue_lines).strip()
    if prologue_body:
        prologue_shot = {
            "shot_index": 1,
            "title": "前言",
            "text": prologue_body,
        }
        shots.insert(0, prologue_shot)
        # Re-index subsequent shots
        for i in range(1, len(shots)):
            shots[i]["shot_index"] = i + 1

    return shots


def split_by_paragraphs(text: str, max_paragraphs_per_shot: int = 4) -> list[dict]:
    """Fallback: split text into shots by paragraph groups.

    Used when there are no ## scene headers.

    Args:
        text: Full chapter text.
        max_paragraphs_per_shot: Maximum paragraphs per shot.

    Returns:
        List of dicts: {shot_index, text}
    """
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    shots = []
    shot_index = 0

    for i in range(0, len(paragraphs), max_paragraphs_per_shot):
        chunk = paragraphs[i:i + max_paragraphs_per_shot]
        shot_index += 1
        shots.append({
            "shot_index": shot_index,
            "title": f"段落 {shot_index}",
            "text": "\n\n".join(chunk),
        })

    return shots


def detect_shots(text: str, chapter_key: str) -> dict:
    """Detect shot boundaries in a chapter.

    P0: uses ## scene headers. If none found, falls back to paragraph grouping.

    Args:
        text: Full chapter Markdown text.
        chapter_key: Chapter key like 'v01.c01'.

    Returns:
        Dict: {chapter_key, shot_count, shots: [{shot_index, title, text, char_count}]}
    """
    # Try scene-header split first
    shots = split_by_scene_headers(text)

    # If no scene headers found, fall back to paragraph grouping
    if not shots:
        shots = split_by_paragraphs(text)

    # Add metadata
    for shot in shots:
        shot["chapter_key"] = chapter_key
        shot["shot_key"] = f"{chapter_key}.s{shot['shot_index']:02d}"
        shot["char_count"] = len(shot["text"])

    return {
        "chapter_key": chapter_key,
        "shot_count": len(shots),
        "shots": shots,
    }


def format_shot_review(shot_analysis: dict) -> str:
    """Format shot analysis for human review.

    Args:
        shot_analysis: Result from detect_shots().

    Returns:
        Formatted text for display.
    """
    lines = [
        f"章节: {shot_analysis['chapter_key']}",
        f"检测到 {shot_analysis['shot_count']} 个 Shot",
        "",
    ]

    for shot in shot_analysis["shots"]:
        preview = shot["text"][:80].replace("\n", " ")
        lines.append(f"  Shot {shot['shot_index']:02d}: {shot['title']}")
        lines.append(f"    字数: {shot['char_count']} | 预览: {preview}...")
        lines.append("")

    return "\n".join(lines)