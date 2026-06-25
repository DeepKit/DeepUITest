"""Polish Service — CREATIVE-2 winner post-processing.

The polish stage is intentionally conservative: it may improve paragraph
rhythm and whitespace, but it must preserve the original winner revision as
the parent and keep hard facts unchanged.
"""

from __future__ import annotations

import re
import sqlite3

from inkflow.services.session_manager import SessionManager
from inkflow.utils.hashing import text_hash_normalized


class PolishService:
    """Creates an audited polish revision from an accepted winner revision."""

    def __init__(self, db: sqlite3.Connection, project_id: str, run_id: str):
        self.db = db
        self.project_id = project_id
        self.run_id = run_id

    def polish_revision(
        self,
        *,
        shot_id: str,
        source_revision_id: str,
        contract_id: str,
        gate_result: dict | None = None,
        jury_summary: dict | None = None,
    ) -> dict:
        """Polish a winner revision and write a child revision if useful.

        Returns a dict with:
        - applied: whether a new write_polish revision was written
        - revision_id: new revision id when applied, otherwise source id
        - text: final text
        - reason: no_changes / failed_gate when not applied
        """
        source = self.db.execute(
            "SELECT * FROM shot_revisions WHERE revision_id = ?",
            (source_revision_id,),
        ).fetchone()
        if source is None:
            raise ValueError(f"source revision not found: {source_revision_id}")

        original_text = source["text"]
        polished_text = conservative_polish(original_text)

        if polished_text == _display_normalize(original_text):
            return {
                "applied": False,
                "reason": "no_changes",
                "revision_id": source_revision_id,
                "text": original_text,
            }

        gate = self._gate_polished_text(polished_text)
        if not gate["passed"]:
            return {
                "applied": False,
                "reason": "failed_gate",
                "revision_id": source_revision_id,
                "text": original_text,
                "gate_result": gate,
            }

        next_sequence = self._next_revision_sequence(shot_id)
        mgr = SessionManager(self.db, self.project_id)
        revision_id = mgr.write_revision(
            shot_id=shot_id,
            run_id=self.run_id,
            contract_id=contract_id,
            revision_sequence=next_sequence,
            operation="write_polish",
            text=polished_text,
            text_hash=text_hash_normalized(polished_text),
            writer_persona="润色师",
            parent_revision_id=source_revision_id,
            jury_scores_json=jury_summary,
            gate_result_json=gate_result or gate,
        )

        return {
            "applied": True,
            "revision_id": revision_id,
            "parent_revision_id": source_revision_id,
            "revision_sequence": next_sequence,
            "text": polished_text,
            "gate_result": gate,
        }

    def _next_revision_sequence(self, shot_id: str) -> int:
        row = self.db.execute(
            "SELECT COALESCE(MAX(revision_sequence), 0) + 1 FROM shot_revisions "
            "WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        return int(row[0])

    @staticmethod
    def _gate_polished_text(text: str) -> dict:
        violations: list[str] = []
        if not text or not text.strip():
            violations.append("empty_text")
        if len(text.strip()) < 50:
            violations.append("too_short")
        return {
            "passed": not violations,
            "violations": violations,
            "stage": "polish",
        }


def conservative_polish(text: str, *, max_paragraph_chars: int = 420) -> str:
    """Apply safe polish transforms without inventing new story content."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    normalized = re.sub(r"[ \t]+", " ", normalized)
    normalized = re.sub(r" *([，。！？；：、]) *", r"\1", normalized)

    paragraphs = [
        paragraph.strip()
        for paragraph in re.split(r"\n\s*\n+", normalized)
        if paragraph.strip()
    ]
    polished: list[str] = []
    for paragraph in paragraphs:
        polished.extend(_split_long_paragraph(paragraph, max_paragraph_chars))
    return "\n\n".join(polished).strip()


def _display_normalize(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n").strip()


def _split_long_paragraph(paragraph: str, max_chars: int) -> list[str]:
    if len(paragraph) <= max_chars:
        return [paragraph]

    result: list[str] = []
    rest = paragraph
    while len(rest) > max_chars:
        split_at = _find_split_point(rest, max_chars)
        result.append(rest[:split_at].strip())
        rest = rest[split_at:].strip()
    if rest:
        result.append(rest)
    return result


def _find_split_point(text: str, max_chars: int) -> int:
    lower_bound = max(120, max_chars // 2)
    window = text[:max_chars]
    punctuation = "。！？；"
    candidates = [idx + 1 for idx, char in enumerate(window) if char in punctuation]
    candidates = [idx for idx in candidates if idx >= lower_bound]
    if candidates:
        return candidates[-1]
    comma_candidates = [idx + 1 for idx, char in enumerate(window) if char in "，、"]
    comma_candidates = [idx for idx in comma_candidates if idx >= lower_bound]
    if comma_candidates:
        return comma_candidates[-1]
    return max_chars
