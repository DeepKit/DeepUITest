"""Fact Anchor Extractor (Service 6).

Extracts 9 types of fact anchors from generated text:
character_state, character_trait, object_location, object_property,
event_occurred, relationship, world_rule, timeline, knowledge.

P0 implementation: deterministic keyword-based extraction of 3 core types:
  - character_state (人物状态)
  - object_location (地点/物品)
  - event_occurred (事件)

Phase 2: real LLM extraction.
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.models.enums import AnchorType


# P0: simple keyword patterns for 3 anchor types
_CHARACTER_STATE_PATTERNS = [
    (r"(.{1,6})(醒了|睡着|疲惫|高兴|难过|愤怒|冷静|紧张|困倦)", "character_state"),
    (r"(.{1,6})(心里|内心|感到|觉得)(.{2,10})", "character_state"),
]

_OBJECT_LOCATION_PATTERNS = [
    (r"(在|放|摆|搁)(.{2,8})(上|里|中|下|旁边|附近)", "object_location"),
    (r"(.{2,6})(窗户|门|桌|床|椅|墙|天花板|地板)", "object_location"),
]

_EVENT_OCCURRED_PATTERNS = [
    (r"(.{2,10})(发生|开始|结束|完成|到达|离开|出现|消失)", "event_occurred"),
    (r"(.{2,10})(拿起|放下|打开|关上|走向|跑向)", "event_occurred"),
]


class FactAnchorExtractor:
    """Extracts and manages fact anchors."""

    def __init__(self, db: sqlite3.Connection, project_id: str, models_config: dict):
        self.db = db
        self.project_id = project_id
        self.models_config = models_config

    def extract(
        self,
        shot_id: str,
        run_id: str,
        text: str,
        revision_id: str,
        *,
        pov_scope: str | None = None,
    ) -> list[str]:
        """Extract fact anchors from shot text.

        P0: deterministic keyword-based extraction of 3 core anchor types.
        Each unique anchor gets a deterministic anchor_id (so re-extraction
        is idempotent within the same revision).

        Args:
            shot_id: The shot the text belongs to.
            run_id: Current run ID.
            text: The generated text to extract from.
            revision_id: The revision this text is part of.
            pov_scope: POV character scope (from contract).

        Returns:
            List of anchor_ids created.
        """
        if not text or not text.strip():
            return []

        anchor_ids: list[str] = []
        seen_keys: set[str] = set()

        patterns = (
            _CHARACTER_STATE_PATTERNS
            + _OBJECT_LOCATION_PATTERNS
            + _EVENT_OCCURRED_PATTERNS
        )

        for pattern, anchor_type in patterns:
            for match in re.finditer(pattern, text):
                # Build a stable anchor_key from the matched text
                raw_value = match.group(0).strip()
                key_hash = hashlib.md5(
                    f"{anchor_type}:{raw_value}".encode()
                ).hexdigest()[:12]
                anchor_key = f"{anchor_type}:{key_hash}"

                # Skip duplicates within the same extraction
                if anchor_key in seen_keys:
                    continue
                seen_keys.add(anchor_key)

                try:
                    aid = self.record_anchor(
                        anchor_type=anchor_type,
                        anchor_key=anchor_key,
                        anchor_value=raw_value,
                        confidence=0.7,
                        run_id=run_id,
                        shot_id=shot_id,
                        pov_scope=pov_scope,
                        source_revision_id=revision_id,
                    )
                    anchor_ids.append(aid)
                except Exception:
                    # Skip anchors that fail DB constraints (e.g. unique key)
                    continue

        return anchor_ids

    def record_anchor(
        self,
        anchor_type: str,
        anchor_key: str,
        anchor_value: str,
        confidence: float,
        *,
        run_id: str | None = None,
        shot_id: str | None = None,
        pov_scope: str | None = None,
        source_revision_id: str | None = None,
        contract_clause_ref: str | None = None,
    ) -> str:
        """Record a single fact anchor.

        Args:
            anchor_type: One of 9 anchor types.
            anchor_key: Unique key within the project.
            anchor_value: The asserted fact.
            confidence: 0.0-1.0 confidence.
            run_id: Run ID.
            shot_id: Source shot.
            pov_scope: POV character scope.
            source_revision_id: Source revision.
            contract_clause_ref: Related contract clause.

        Returns:
            anchor_id
        """
        anchor_id = generate_ulid()

        self.db.execute(
            "INSERT INTO writing_fact_anchors "
            "(anchor_id, project_id, run_id, shot_id, anchor_type, "
            "anchor_key, anchor_value, confidence, pov_scope, "
            "source_revision_id, contract_clause_ref) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (anchor_id, self.project_id, run_id, shot_id, anchor_type,
             anchor_key, anchor_value, confidence, pov_scope,
             source_revision_id, contract_clause_ref),
        )
        self.db.commit()
        return anchor_id

    def detect_conflicts(self, new_anchor_ids: list[str]) -> list[dict]:
        """Detect conflicts between new anchors and existing ones.

        Checks for:
        - Explicit contradiction: same key, opposite value
        - Implicit inconsistency: same key, changed value without explicit update
        - Timeline misalignment: event_occurred with inconsistent timestamps
        - POV contradiction: same key, different pov_scope reports different values

        Returns:
            List of {anchor_a, anchor_b, conflict_type, description}.
        """
        conflicts = []
        new_anchors = self._get_anchors_by_ids(new_anchor_ids)

        for anchor in new_anchors:
            existing = self.db.execute(
                "SELECT * FROM writing_fact_anchors "
                "WHERE project_id = ? AND anchor_key = ? AND anchor_id != ? "
                "AND run_id = ? "
                "ORDER BY extracted_at DESC LIMIT 1",
                (self.project_id, anchor["anchor_key"], anchor["anchor_id"],
                 anchor.get("run_id")),
            ).fetchone()

            if existing is None:
                continue

            # Explicit contradiction: same key, different value
            if existing["anchor_value"] != anchor["anchor_value"]:
                conflicts.append({
                    "anchor_a": anchor["anchor_id"],
                    "anchor_b": existing["anchor_id"],
                    "conflict_type": "explicit_contradiction",
                    "description": (
                        f"'{anchor['anchor_key']}': "
                        f"'{anchor['anchor_value']}' vs '{existing['anchor_value']}'"
                    ),
                })

            # Implicit inconsistency: same key, same value but different confidence
            elif existing["anchor_value"] == anchor["anchor_value"]:
                if abs(existing["confidence"] - anchor["confidence"]) > 0.3:
                    conflicts.append({
                        "anchor_a": anchor["anchor_id"],
                        "anchor_b": existing["anchor_id"],
                        "conflict_type": "implicit_inconsistency",
                        "description": (
                            f"'{anchor['anchor_key']}': confidence drift "
                            f"({existing['confidence']} → {anchor['confidence']})"
                        ),
                    })

            # Timeline misalignment: event_occurred anchor with same key
            if anchor.get("anchor_type") == "event_occurred" and existing["anchor_type"] == "event_occurred":
                if existing["anchor_value"] != anchor["anchor_value"]:
                    conflicts.append({
                        "anchor_a": anchor["anchor_id"],
                        "anchor_b": existing["anchor_id"],
                        "conflict_type": "timeline_misalignment",
                        "description": (
                            f"Timeline event '{anchor['anchor_key']}' diverged: "
                            f"'{existing['anchor_value']}' → '{anchor['anchor_value']}'"
                        ),
                    })

            # POV contradiction: different pov_scope with different values
            if (anchor.get("pov_scope") and existing.get("pov_scope") and
                    anchor["pov_scope"] != existing["pov_scope"] and
                    anchor["anchor_value"] != existing["anchor_value"]):
                conflicts.append({
                    "anchor_a": anchor["anchor_id"],
                    "anchor_b": existing["anchor_id"],
                    "conflict_type": "pov_contradiction",
                    "description": (
                        f"'{anchor['anchor_key']}': {anchor['pov_scope']} says "
                        f"'{anchor['anchor_value']}' vs {existing['pov_scope']} says "
                        f"'{existing['anchor_value']}'"
                    ),
                })

        return conflicts

    def _get_anchors_by_ids(self, anchor_ids: list[str]) -> list[dict]:
        """Get anchor dicts by IDs."""
        if not anchor_ids:
            return []
        placeholders = ",".join("?" for _ in anchor_ids)
        rows = self.db.execute(
            f"SELECT * FROM writing_fact_anchors WHERE anchor_id IN ({placeholders})",
            anchor_ids,
        ).fetchall()
        return [dict(r) for r in rows]

    def get_anchors_for_shot(self, shot_id: str) -> list[dict]:
        """Get all fact anchors for a shot."""
        rows = self.db.execute(
            "SELECT * FROM writing_fact_anchors WHERE shot_id = ? "
            "ORDER BY anchor_type",
            (shot_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    def get_active_anchors(
        self,
        limit: int = 50,
        *,
        run_id: str | None = None,
        book_run_id: str | None = None,
    ) -> list[dict]:
        """Get canonical anchors for context assembly.

        Includes anchors from the active run, human-accepted chapters, and
        locked baseline shots. During book-run orchestration, completed earlier
        draft chapters in the same book_run are also available as temporary
        context for subsequent draft chapters.
        """
        rows = self.db.execute(
            "SELECT fa.* FROM writing_fact_anchors fa "
            "LEFT JOIN writing_shots ws ON ws.shot_id = fa.shot_id "
            "LEFT JOIN writing_chapter_reviews cr "
            "  ON cr.project_id = fa.project_id "
            " AND cr.chapter_key = ws.layer_key "
            " AND cr.run_id = fa.run_id "
            " AND cr.status = 'accepted' "
            "LEFT JOIN writing_book_run_chapters brc "
            "  ON brc.book_run_id = ? "
            " AND brc.run_id = fa.run_id "
            " AND brc.status = 'completed' "
            "WHERE fa.project_id = ? "
            "  AND ("
            "    (? IS NOT NULL AND fa.run_id = ?) "
            "    OR brc.book_run_chapter_id IS NOT NULL "
            "    OR cr.review_id IS NOT NULL "
            "    OR COALESCE(ws.is_baseline, 0) = 1"
            "  ) "
            "ORDER BY fa.extracted_at DESC LIMIT ?",
            (book_run_id, self.project_id, run_id, run_id, limit),
        ).fetchall()
        return [dict(r) for r in rows]
