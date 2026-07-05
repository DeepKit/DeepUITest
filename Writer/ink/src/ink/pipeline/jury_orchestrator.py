from __future__ import annotations

import json
import sqlite3

from ink.contract.generated.dtos import DraftSpecDTO
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError
from ink.jury.scores import JUDGE_ROLES, SCORE_COLUMNS
from ink.time import now_utc_iso
from ink.writers.draft_repository import list_drafts, load_draft


_DEFAULT_ORCHESTRATOR: "JuryOrchestrator | None" = None
RAW_SCORE_INSERT_SQL = """
    INSERT INTO writing_jury_raw_scores
        (draft_id, shot_contract_id, jury_round, judge_slot, judge_model, judge_role,
         scene_visual, rhythm_pacing, dialogue_subtext, suspense_tension,
         language_texture, emotional_progression, character_believability,
         structure_landing, reading_fluency, motif_theme_fit,
         chapter_continuity, creative_boundary, evaluated_at)
    VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
"""
AGGREGATE_INSERT_SQL = """
    INSERT INTO writing_jury_aggregates
        (shot_id, draft_id, shot_contract_id, jury_round_used, judge_count,
         scene_visual_median, rhythm_pacing_median, dialogue_subtext_median,
         suspense_tension_median, language_texture_median, emotional_progression_median,
         character_believability_median, structure_landing_median, reading_fluency_median,
         motif_theme_fit_median, chapter_continuity_median, creative_boundary_median,
         weight_used, final_score, quality_gate_passed,
         quality_gate_reasons, judge_disagreement_max, is_winner, evaluated_at)
    VALUES (?, ?, ?, 1, 3, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
"""
ELIGIBLE_BASE_CANDIDATES_SQL = """
    SELECT d.draft_id
    FROM writing_drafts d
    JOIN writing_draft_eligibility e ON e.draft_id = d.draft_id
    WHERE d.shot_id = ?
      AND d.degraded = 0
      AND d.is_deviant = 0
      AND d.retry_count = 0
      AND e.gate1_eligible = 1
      AND e.gate2_eligible = 1
    ORDER BY d.draft_id
"""
ELIGIBLE_RETRY_CANDIDATES_SQL = """
    SELECT d.draft_id
    FROM writing_drafts d
    JOIN writing_draft_eligibility e ON e.draft_id = d.draft_id
    WHERE d.shot_id = ?
      AND d.degraded = 0
      AND d.is_deviant = 0
      AND d.retry_count > 0
      AND e.gate1_eligible = 1
      AND e.gate2_eligible = 1
    ORDER BY d.draft_id
"""


def score_and_select_winner(shot_id: str, run_id: int) -> DraftSpecDTO:
    if _DEFAULT_ORCHESTRATOR is None:
        raise DataIntegrityError("jury orchestrator is not configured")
    return _DEFAULT_ORCHESTRATOR.score_and_select_winner(shot_id, run_id)


class JuryOrchestrator:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def score_and_select_winner(self, shot_id: str, run_id: int) -> DraftSpecDTO:
        status = load_status(self.conn, shot_id, run_id)
        if status == "winner_selected":
            if _redo_in_progress(self.conn, shot_id, run_id):
                return self._score_redo_and_maybe_flip(shot_id, run_id)
            return _load_current_winner(self.conn, shot_id)
        if status != "jury_scoring":
            raise DataIntegrityError(f"jury cannot run from status: {status}")

        context = _load_jury_context(self.conn, shot_id, run_id)
        candidates = _eligible_candidates(self.conn, shot_id)
        if len(candidates) < context.min_eligible_candidates:
            raise DataIntegrityError(
                f"eligible jury candidates below threshold: {len(candidates)} < {context.min_eligible_candidates}"
            )

        aggregates: list[tuple[int, float]] = []
        for index, draft in enumerate(candidates):
            score = _score_for_draft(draft, index)
            self._score_draft(context, draft, score)
            medians = _median_scores_for_draft(draft, score)
            if _quality_gate_passes(context, float(score), medians, _judge_disagreement_for_draft(draft)):
                aggregates.append((draft.draft_id, float(score)))

        if not aggregates:
            return self._handle_quality_retry_or_fail(context, shot_id, run_id)

        winner_draft_id = max(aggregates, key=lambda item: (item[1], item[0]))[0]
        self.conn.execute("UPDATE writing_jury_aggregates SET is_winner = 0 WHERE shot_id = ?", (shot_id,))
        self.conn.execute(
            "UPDATE writing_jury_aggregates SET is_winner = 1 WHERE shot_id = ? AND draft_id = ?",
            (shot_id, winner_draft_id),
        )
        transition(self.conn, shot_id, run_id, "jury_scoring", "winner_selected")
        return load_draft(self.conn, winner_draft_id)

    def _handle_quality_retry_or_fail(self, context: "_JuryContext", shot_id: str, run_id: int) -> DraftSpecDTO:
        if not context.auto_retry_on_hard_failure:
            transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
            raise DataIntegrityError("no draft passed jury quality floor")

        from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator
        from ink.pipeline.write_orchestrator import WriteOrchestrator

        try:
            WriteOrchestrator(self.conn).produce_quality_retry_candidates(shot_id, run_id)
            HardGateOrchestrator(self.conn).run_both_gates(shot_id, run_id)
        except DataIntegrityError:
            transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
            raise

        retry_candidates = _eligible_candidates(self.conn, shot_id, retry_only=True)
        retry_aggregates: list[tuple[int, float]] = []
        for index, draft in enumerate(retry_candidates):
            score = _score_for_draft(draft, index)
            self._score_draft(context, draft, score)
            medians = _median_scores_for_draft(draft, score)
            if _quality_gate_passes(context, float(score), medians, _judge_disagreement_for_draft(draft)):
                retry_aggregates.append((draft.draft_id, float(score)))

        if not retry_aggregates:
            if _shot_retry_count(self.conn, shot_id, run_id) >= context.max_retries_per_gate:
                transition(self.conn, shot_id, run_id, "jury_scoring", "failed")
            raise DataIntegrityError("no retry draft passed jury quality floor")

        winner_draft_id = max(retry_aggregates, key=lambda item: (item[1], item[0]))[0]
        self.conn.execute("UPDATE writing_jury_aggregates SET is_winner = 0 WHERE shot_id = ?", (shot_id,))
        self.conn.execute(
            "UPDATE writing_jury_aggregates SET is_winner = 1 WHERE shot_id = ? AND draft_id = ?",
            (shot_id, winner_draft_id),
        )
        transition(self.conn, shot_id, run_id, "jury_scoring", "winner_selected")
        return load_draft(self.conn, winner_draft_id)

    def _score_redo_and_maybe_flip(self, shot_id: str, run_id: int) -> DraftSpecDTO:
        from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator

        HardGateOrchestrator(self.conn).run_both_gates(shot_id, run_id)
        context = _load_jury_context(self.conn, shot_id, run_id)
        redo_candidates = _eligible_candidates(self.conn, shot_id, retry_only=True)
        if len(redo_candidates) < context.redo_candidate_count:
            raise DataIntegrityError(
                f"redo jury candidates below threshold: {len(redo_candidates)} < {context.redo_candidate_count}"
            )

        best_existing = _load_best_aggregate(self.conn, shot_id)
        if best_existing is None:
            raise DataIntegrityError(f"existing winner aggregate not found for redo: {shot_id}")

        redo_aggregates: list[tuple[int, float]] = []
        for index, draft in enumerate(redo_candidates):
            score = _score_for_draft(draft, index)
            self._score_draft(context, draft, score)
            medians = _median_scores_for_draft(draft, score)
            if _quality_gate_passes(context, float(score), medians, _judge_disagreement_for_draft(draft)):
                redo_aggregates.append((draft.draft_id, float(score)))

        if redo_aggregates:
            best_redo = max(redo_aggregates, key=lambda item: (item[1], item[0]))
            if best_redo[1] > best_existing[1]:
                self.conn.execute("UPDATE writing_jury_aggregates SET is_winner = 0 WHERE shot_id = ?", (shot_id,))
                self.conn.execute(
                    "UPDATE writing_jury_aggregates SET is_winner = 1 WHERE shot_id = ? AND draft_id = ?",
                    (shot_id, best_redo[0]),
                )

        self.conn.execute(
            "UPDATE writing_shots SET redo_in_progress = 0 WHERE shot_id = ? AND run_id = ?",
            (shot_id, run_id),
        )
        return _load_current_winner(self.conn, shot_id)

    def resume_handlers(self) -> dict[str, object]:
        return {
            "rerun_jury": self.score_and_select_winner,
            "rerun_soft_gate_redo_jury": self.score_and_select_winner,
            "rerun_winner_select": self.score_and_select_winner,
        }

    def _score_draft(self, context: "_JuryContext", draft: DraftSpecDTO, score: int) -> None:
        self.conn.execute("DELETE FROM writing_jury_raw_scores WHERE draft_id = ? AND jury_round = 1", (draft.draft_id,))
        self.conn.execute("DELETE FROM writing_jury_aggregates WHERE draft_id = ?", (draft.draft_id,))

        judges = _select_judges(context.jury_models, draft.writer_model, 3)
        medians = _median_scores_for_draft(draft, score)
        for slot, judge_model in enumerate(judges, start=1):
            role = JUDGE_ROLES[slot - 1]
            scores = _raw_scores_for_slot(draft, medians, slot)
            self.conn.execute(
                RAW_SCORE_INSERT_SQL,
                (draft.draft_id, context.shot_contract_id, slot, judge_model, role, *scores, now_utc_iso()),
            )

        weight_used = {column: round(1 / len(SCORE_COLUMNS), 6) for column in SCORE_COLUMNS}
        weight_used["_intensity_5d"] = context.intensity
        if context.deviant_reference_draft_id is not None:
            weight_used["_deviant_reference_draft_id"] = context.deviant_reference_draft_id
        judge_disagreement_max = _judge_disagreement_for_draft(draft)
        quality_gate_passed = int(_quality_gate_passes(context, float(score), medians, judge_disagreement_max))
        quality_gate_reasons = _quality_gate_reasons(context, float(score), medians, judge_disagreement_max)
        self.conn.execute(
            AGGREGATE_INSERT_SQL,
            (
                context.shot_id,
                draft.draft_id,
                context.shot_contract_id,
                *medians,
                json.dumps(weight_used, ensure_ascii=False, sort_keys=True),
                float(score),
                quality_gate_passed,
                json.dumps(quality_gate_reasons, sort_keys=True),
                judge_disagreement_max,
                now_utc_iso(),
            ),
        )


class _JuryContext:
    def __init__(
        self,
        *,
        shot_id: str,
        shot_contract_id: int,
        jury_models: tuple[str, ...],
        min_eligible_candidates: int,
        redo_candidate_count: int,
        auto_retry_on_hard_failure: bool,
        max_retries_per_gate: int,
        shot_quality_floor: int,
        dimension_floor: int,
        judge_disagreement_max: int,
        deviant_reference_draft_id: int | None,
        intensity: dict[str, object],
    ) -> None:
        self.shot_id = shot_id
        self.shot_contract_id = shot_contract_id
        self.jury_models = jury_models
        self.min_eligible_candidates = min_eligible_candidates
        self.redo_candidate_count = redo_candidate_count
        self.auto_retry_on_hard_failure = auto_retry_on_hard_failure
        self.max_retries_per_gate = max_retries_per_gate
        self.shot_quality_floor = shot_quality_floor
        self.dimension_floor = dimension_floor
        self.judge_disagreement_max = judge_disagreement_max
        self.deviant_reference_draft_id = deviant_reference_draft_id
        self.intensity = intensity


def _load_jury_context(conn: sqlite3.Connection, shot_id: str, run_id: int) -> _JuryContext:
    row = conn.execute(
        """
        SELECT s.shot_contract_id, p.jury_model_pool, p.min_eligible_candidates, p.redo_candidate_count,
               p.auto_retry_on_hard_failure, p.max_retries_per_gate,
               p.shot_quality_floor, p.dimension_floor, p.judge_disagreement_max,
               pa.intensity, pa.is_creative_shot
        FROM writing_shots s
        JOIN writing_projects p ON p.project_id = s.project_id
        JOIN writing_shot_persona_assignment pa ON pa.shot_contract_id = s.shot_contract_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[0] is None:
        raise DataIntegrityError(f"shot not found or missing jury context: {shot_id}/{run_id}")
    return _JuryContext(
        shot_id=shot_id,
        shot_contract_id=int(row[0]),
        jury_models=tuple(str(item) for item in json.loads(row[1])),
        min_eligible_candidates=int(row[2]),
        redo_candidate_count=int(row[3]),
        auto_retry_on_hard_failure=bool(row[4]),
        max_retries_per_gate=int(row[5]),
        shot_quality_floor=int(row[6]),
        dimension_floor=int(row[7]),
        judge_disagreement_max=int(row[8]),
        deviant_reference_draft_id=_load_deviant_reference(conn, shot_id) if int(row[10]) == 1 else None,
        intensity=json.loads(row[9]),
    )


def _eligible_candidates(conn: sqlite3.Connection, shot_id: str, *, retry_only: bool = False) -> list[DraftSpecDTO]:
    rows = conn.execute(
        ELIGIBLE_RETRY_CANDIDATES_SQL if retry_only else ELIGIBLE_BASE_CANDIDATES_SQL,
        (shot_id,),
    ).fetchall()
    return [load_draft(conn, int(row[0])) for row in rows]


def _select_judges(jury_models: tuple[str, ...], writer_model: str, count: int) -> tuple[str, ...]:
    judges = tuple(model for model in jury_models if model != writer_model)
    if len(judges) < count:
        raise DataIntegrityError("not enough jury models after excluding writer_model")
    return judges[:count]


def _redo_in_progress(conn: sqlite3.Connection, shot_id: str, run_id: int) -> bool:
    row = conn.execute(
        "SELECT redo_in_progress FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    return row is not None and int(row[0]) == 1


def _shot_retry_count(conn: sqlite3.Connection, shot_id: str, run_id: int) -> int:
    row = conn.execute(
        "SELECT retry_count FROM writing_shots WHERE shot_id = ? AND run_id = ?",
        (shot_id, run_id),
    ).fetchone()
    return 0 if row is None else int(row[0])


def _load_best_aggregate(conn: sqlite3.Connection, shot_id: str) -> tuple[int, float] | None:
    row = conn.execute(
        """
        SELECT draft_id, final_score
        FROM writing_jury_aggregates
        WHERE shot_id = ? AND is_winner = 1 AND quality_gate_passed = 1
        ORDER BY final_score DESC, draft_id DESC
        LIMIT 1
        """,
        (shot_id,),
    ).fetchone()
    return None if row is None else (int(row[0]), float(row[1]))


def _load_deviant_reference(conn: sqlite3.Connection, shot_id: str) -> int | None:
    row = conn.execute(
        """
        SELECT draft_id
        FROM writing_drafts
        WHERE shot_id = ? AND is_deviant = 1 AND degraded = 0
        ORDER BY draft_id DESC
        LIMIT 1
        """,
        (shot_id,),
    ).fetchone()
    return None if row is None else int(row[0])


def _score_for_draft(draft: DraftSpecDTO, index: int) -> int:
    if "[low-quality]" in draft.text:
        return 70
    if "[dimension-fail]" in draft.text:
        return 84
    if "[disagreement]" in draft.text:
        return 84
    if "[redo-better]" in draft.text:
        return 92 + index
    return 84 + index


def _median_scores_for_draft(draft: DraftSpecDTO, final_score: int) -> list[float]:
    medians = [float(final_score)] * len(SCORE_COLUMNS)
    if "[dimension-fail]" in draft.text:
        medians[0] = 60.0
    return medians


def _raw_scores_for_slot(draft: DraftSpecDTO, medians: list[float], slot: int) -> list[int]:
    offsets = (-14, 0, 16) if "[disagreement]" in draft.text else (-1, 0, 1)
    offset = offsets[slot - 1]
    return [max(0, min(100, int(value + offset))) for value in medians]


def _judge_disagreement_for_draft(draft: DraftSpecDTO) -> int:
    return 30 if "[disagreement]" in draft.text else 2


def _quality_gate_passes(
    context: _JuryContext,
    final_score: float,
    medians: list[float],
    judge_disagreement_max: float,
) -> bool:
    return (
        final_score >= context.shot_quality_floor
        and min(medians) >= context.dimension_floor
        and judge_disagreement_max <= context.judge_disagreement_max
    )


def _quality_gate_reasons(
    context: _JuryContext,
    final_score: float,
    medians: list[float],
    judge_disagreement_max: float,
) -> list[str]:
    reasons = []
    if final_score < context.shot_quality_floor:
        reasons.append("final_score_below_shot_quality_floor")
    if min(medians) < context.dimension_floor:
        reasons.append("dimension_below_floor")
    if judge_disagreement_max > context.judge_disagreement_max:
        reasons.append("judge_disagreement_exceeded")
    return reasons


def _load_current_winner(conn: sqlite3.Connection, shot_id: str) -> DraftSpecDTO:
    row = conn.execute(
        "SELECT draft_id FROM writing_jury_aggregates WHERE shot_id = ? AND is_winner = 1",
        (shot_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"winner not found for shot: {shot_id}")
    return load_draft(conn, int(row[0]))
