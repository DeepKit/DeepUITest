"""Real-model implementations of the three GenerationRoundDriver ports.

These wire the shadow-layer driver to the real iFLYTEK LLM via
``LLMGateway.call`` — a single unified entry point that honors the jury
role-config failover chain (primary→secondary→tertiary) and writes
``model_events`` records. They do **not** touch the legacy Shot production
path: jury calls are made with ``shot_id=None`` (so the per-shot
``LLMCallBudget`` is skipped) and ``run_id=None``.

Two prompts are issued, both under ``call_type="chapter_review"`` (the jury
pool already has role-config tiers configured):

* **validation** — a single candidate's full chapter text is scored on the
  same seven literary dimensions the Shot-centered ``ChapterReviewOrchestrator``
  uses. All dimensions ≥ the project floor ⇒ eligible.
* **substantive difference** — all eligible candidates' texts are presented
  blind (labels A/B/C…) to the jury, which returns whether they exhibit
  *substantive* narrative difference (not just wording/length).
* **winner selection** — blind pairwise ranking: the jury scores each
  eligible candidate and the lowest-index highest-scoring branch wins, gated
  by an absolute literary floor.

Real-model behavior is non-deterministic; these ports assert "the scheduling
path ran a real LLM and returned a structurally valid verdict", not any
specific text or score (consistent with ``test_e2e_real_models.py``).
"""
from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass

from ink.core.chapter_snapshot_repository import ChapterSnapshotRepository
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.core.scene_repository import SceneRepository
from ink.errors import DataIntegrityError

# call_type whose role-config chain holds the jury failover pool.
JURY_CALL_TYPE = "chapter_review"
# Absolute literary floor for winner selection (0-100 per dimension).
# Real-model jury scores are noisy; this is a permissive floor that still
# blocks genuinely bad drafts. Tunable per-project via writing_projects later.
ABSOLUTE_LITERARY_FLOOR = 60


@dataclass(frozen=True)
class CandidateText:
    branch_id: int
    candidate_index: int
    text: str


class RealValidationPort:
    """Score one candidate on seven literary dimensions; all ≥ floor ⇒ eligible."""

    DIMENSIONS = (
        "narrative_tension",
        "character_voice",
        "scene_concreteness",
        "emotional_resonance",
        "pacing",
        "language_polish",
        "contract_adherence",
    )

    def __init__(self, gateway: LLMGateway, *, project_id: int) -> None:
        self.gateway = gateway
        self.project_id = project_id

    def validate_candidate(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
        branch_id: int,
    ) -> bool:
        text = _branch_text(repo, branch_id)
        scores = self._score(round_id=round_id, branch_id=branch_id, text=text)
        floor = _project_floor(conn, self.project_id)
        # BFX-074 诊断：落盘真模型 7 维分 + 候选正文，判断是 floor 过高还是模型打低分。
        import os as _os, json as _json
        if _os.environ.get("INK_BFX074_DIAG"):
            _os.makedirs(".bfx074", exist_ok=True)
            with open(f".bfx074/scores_r{round_id}_b{branch_id}.json", "w", encoding="utf-8") as _f:
                _json.dump({"branch_id": branch_id, "floor": floor, "scores": scores,
                            "passed": all(s >= floor for s in scores.values())}, _f, ensure_ascii=False, indent=2)
            with open(f".bfx074/text_r{round_id}_b{branch_id}.md", "w", encoding="utf-8") as _f:
                _f.write(text)
        passed = all(score >= floor for score in scores.values())
        if passed:
            repo.record_eligible_branch(round_id=round_id, branch_id=branch_id)
            repo.advance_to_literary_review(branch_id=branch_id)
        return passed

    def _score(self, *, round_id: int, branch_id: int, text: str) -> dict[str, int]:
        prompt = _validation_prompt(text, self.DIMENSIONS)
        result = self.gateway.call(
            project_id=self.project_id,
            shot_id=None,
            run_id=None,
            call_type=JURY_CALL_TYPE,
            prompt_id=None,
            prompt_text=prompt,
            model_name="",  # role-chain picks the real model; empty ⇒ chain default
            idempotency_key=_idem_key("validate", round_id, branch_id),
        )
        # BFX-074 诊断：先落盘 jury raw response，看模型实际返回格式
        import os as _os
        if _os.environ.get("INK_BFX074_DIAG"):
            _os.makedirs(".bfx074", exist_ok=True)
            with open(f".bfx074/raw_r{round_id}_b{branch_id}.txt", "w", encoding="utf-8") as _f:
                _f.write(result.text or "")
        return _parse_scores(result.text, self.DIMENSIONS)


class RealSelectionPort:
    """Blind jury: substantive-difference gate + pairwise winner selection."""

    def __init__(self, gateway: LLMGateway, *, project_id: int) -> None:
        self.gateway = gateway
        self.project_id = project_id

    # ── substantive difference ──

    def has_substantive_difference(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
    ) -> bool:
        candidates = _eligible_candidates(repo, round_id=round_id)
        if len(candidates) < 2:
            return False
        prompt = _difference_prompt(candidates)
        result = self.gateway.call(
            project_id=self.project_id,
            shot_id=None,
            run_id=None,
            call_type=JURY_CALL_TYPE,
            prompt_id=None,
            prompt_text=prompt,
            model_name="",
            idempotency_key=_idem_key("diff", round_id, 0),
        )
        return _parse_bool(result.text)

    # ── winner selection ──

    def select_winner(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
    ) -> int:
        candidates = _eligible_candidates(repo, round_id=round_id)
        if not candidates:
            raise _SelectionError("no eligible candidates to select from")
        scored = self._rank(round_id=round_id, candidates=candidates)
        # Absolute dimension floor (DB dimension_floor, CHECK >= 60): the winner
        # must clear it on EVERY dimension. This is the真实化 absolute底線 —
        # previously a hardcoded 60 constant, now read from schema.
        dim_floor = _dimension_floor(conn, self.project_id)
        qualified = [c for c in scored if min(c.scores.values()) >= dim_floor]
        if not qualified:
            raise _SelectionError(
                f"no candidate cleared the absolute dimension floor {dim_floor}"
            )
        # Lowest-index highest-score wins (deterministic tie-break).
        qualified.sort(key=lambda c: (-_total(c.scores), c.candidate_index))
        winner = qualified[0]
        # SelectionPort is decision-only. The driver owns select_branch() and the
        # round's selecting -> selected transition so state writes have one entry point.
        return winner.branch_id

    def _rank(self, *, round_id: int, candidates: list[CandidateText]) -> list[_ScoredCandidate]:
        out: list[_ScoredCandidate] = []
        for cand in candidates:
            prompt = _validation_prompt(cand.text, RealValidationPort.DIMENSIONS)
            result = self.gateway.call(
                project_id=self.project_id,
                shot_id=None,
                run_id=None,
                call_type=JURY_CALL_TYPE,
                prompt_id=None,
                prompt_text=prompt,
                model_name="",
                idempotency_key=_idem_key("select", round_id, cand.branch_id),
            )
            out.append(
                _ScoredCandidate(
                    branch_id=cand.branch_id,
                    candidate_index=cand.candidate_index,
                    scores=_parse_scores(result.text, RealValidationPort.DIMENSIONS),
                )
            )
        return out


class RealGenerationPort:
    """Generate one candidate's chapter text via the writer model, freeze it.

    The writer pool uses ``call_type="draft"`` role-config (the schema CHECK
    and ``WriteOrchestrator`` both use ``draft`` as the writer call_type).
    The generated text is written into the branch's scene revision so the
    validation/selection ports can read it back via ``read_branch_version_text``.
    """

    def __init__(
        self,
        gateway: LLMGateway,
        *,
        project_id: int,
        chapter_brief: str,
        writer_model_label: str = "real-llm",
    ) -> None:
        self.gateway = gateway
        self.project_id = project_id
        self.chapter_brief = chapter_brief
        self.writer_model_label = writer_model_label

    def generate_candidate(
        self,
        conn: sqlite3.Connection,
        repo: ChapterSnapshotRepository,
        *,
        round_id: int,
        candidate_index: int,
    ) -> int:
        branch_id = repo.create_branch(
            generation_round_id=round_id,
            candidate_index=candidate_index,
            writer_model=self.writer_model_label,  # actual model chosen by role-chain
            generation_strategy="real-llm",
        )
        result = self.gateway.call(
            project_id=self.project_id,
            shot_id=None,
            run_id=None,
            call_type="draft",
            prompt_id=None,
            prompt_text=_generation_prompt(self.chapter_brief, candidate_index),
            model_name="",
            idempotency_key=_idem_key("generate", round_id, branch_id),
        )
        _write_branch_text(repo, branch_id=branch_id, version=1, text=result.text)
        repo.start_validating_branch(branch_id=branch_id)
        return branch_id


# ── helpers ──


@dataclass(frozen=True)
class _ScoredCandidate:
    branch_id: int
    candidate_index: int
    scores: dict[str, int]


class _SelectionError(Exception):
    pass


def _branch_text(repo: ChapterSnapshotRepository, branch_id: int) -> str:
    return repo.read_branch_version_text(repo.frozen_branch_version_id(branch_id))


def _eligible_candidates(
    repo: ChapterSnapshotRepository, *, round_id: int
) -> list[CandidateText]:
    # Validation advances eligible → literary_review, so the pool under
    # selection is the 'literary_review' set (matches StubValidationPort).
    rows = repo.conn.execute(
        """
        SELECT branch_id, candidate_index
        FROM writing_chapter_candidate_branches
        WHERE generation_round_id = ? AND status = 'literary_review'
        ORDER BY candidate_index
        """,
        (round_id,),
    ).fetchall()
    return [
        CandidateText(
            branch_id=int(bid),
            candidate_index=int(idx),
            text=_branch_text(repo, int(bid)),
        )
        for bid, idx in rows
    ]


def _write_branch_text(
    repo: ChapterSnapshotRepository, *, branch_id: int, version: int, text: str
) -> None:
    """Write through SceneRepository; never bypass active-contract invariants.

    Generation Round consumes an upstream active Scene Contract. Contract creation
    and dual-review belong to P0-3, so this P0-1 port deliberately fails closed
    when no active contract exists instead of manufacturing one here.
    """
    conn = repo.conn
    project_id, chapter_id, outline_version_id, chapter_contract_version_id = (
        _round_owner(conn, branch_id)
    )
    scene = conn.execute(
        """
        SELECT s.scene_id, c.scene_contract_id
        FROM writing_scenes s
        JOIN writing_scene_contracts c ON c.scene_id = s.scene_id
        WHERE s.project_id = ? AND s.chapter_id = ? AND c.status = 'active'
        ORDER BY s.scene_order, c.version DESC
        LIMIT 1
        """,
        (project_id, chapter_id),
    ).fetchone()
    if scene is None:
        raise DataIntegrityError(
            f"round branch {branch_id} requires an active Scene Contract"
        )
    scene_id, scene_contract_id = int(scene[0]), int(scene[1])
    branch_version_id = repo.create_branch_version(
        branch_id=branch_id,
        version=version,
        parent_branch_version_id=None,
        outline_version_id=outline_version_id,
        chapter_contract_version_id=chapter_contract_version_id,
    )
    SceneRepository(conn).create_revision(
        scene_id=scene_id,
        branch_version_id=branch_version_id,
        scene_order=1,
        expected_parent_revision_id=None,
        scene_contract_id=scene_contract_id,
        text=text,
        actor_type="ai",
        actor_id="generation-round",
        change_reason="candidate",
        generation_task_id=branch_id,
    )
    repo.freeze_branch_version(branch_version_id, actor="human:generation-supervisor")


def _round_owner(
    conn: sqlite3.Connection, branch_id: int
) -> tuple[int, int, int | None, int | None]:
    row = conn.execute(
        """
        SELECT gr.project_id, gr.chapter_id,
               gr.outline_version_id, gr.chapter_contract_version_id
        FROM writing_chapter_generation_rounds gr
        JOIN writing_chapter_candidate_branches b
          ON b.generation_round_id = gr.generation_round_id
        WHERE b.branch_id = ?
        """,
        (branch_id,),
    ).fetchone()
    if row is None:
        raise _SelectionError(f"branch {branch_id} has no owning round")
    return (
        int(row[0]),
        int(row[1]),
        None if row[2] is None else int(row[2]),
        None if row[3] is None else int(row[3]),
    )


def _project_floor(conn: sqlite3.Connection, project_id: int) -> int:
    """Per-project winner floor (shot_quality_floor). Schema enforces an absolute
    DB底线 via CHECK (shot_quality_floor >= 75); we only read it here.
    Falls back to ABSOLUTE_LITERARY_FLOOR only if the column is NULL."""
    row = conn.execute(
        "SELECT shot_quality_floor FROM writing_projects WHERE project_id=?",
        (project_id,),
    ).fetchone()
    if row is not None and row[0] is not None:
        return int(row[0])
    return ABSOLUTE_LITERARY_FLOOR


def _dimension_floor(conn: sqlite3.Connection, project_id: int) -> int:
    """Per-dimension floor (dimension_floor). Schema CHECK (dimension_floor >= 60)
    is the absolute底線 — a candidate must clear it on *every* dimension to be
    a qualified winner."""
    row = conn.execute(
        "SELECT dimension_floor FROM writing_projects WHERE project_id=?",
        (project_id,),
    ).fetchone()
    if row is not None and row[0] is not None:
        return int(row[0])
    return ABSOLUTE_LITERARY_FLOOR


def _idem_key(step: str, round_id: int, branch_id: int) -> str:
    """Stable across crash recovery; one logical round step has one provider key."""
    return f"round-{round_id}-{step}-{branch_id}"


def _total(scores: dict[str, int]) -> int:
    return sum(scores.values())


# ── prompts ──


def _validation_prompt(text: str, dimensions: tuple[str, ...]) -> str:
    dims = "\n".join(f"- {d}" for d in dimensions)
    return (
        "你是中文小说终审评委。请对以下章节候选正文逐维打分（0-100 整数），"
        "只输出 JSON，键为维度名、值为分数。\n维度：\n"
        f"{dims}\n\n正文：\n{text}"
    )


def _difference_prompt(candidates: list[CandidateText]) -> str:
    blocks = "\n\n".join(
        f"【候选 {chr(ord('A') + i)}】\n{c.text}" for i, c in enumerate(candidates)
    )
    return (
        "你是中文小说终审评委。下面是同一章的多个候选正文（标签 A/B/C…，盲审，"
        "标签与作者无关）。请判断这些候选之间是否存在**实质性叙事差异**"
        "（情节走向/人物动作/场景功能不同），而非仅措辞、字数或顺序差异。"
        "只输出 JSON：{\"has_substantive_difference\": true 或 false}。\n\n"
        f"{blocks}"
    )


def _generation_prompt(brief: str, candidate_index: int) -> str:
    # 三段都是 f-string：第三段含 {brief}，漏 f 前缀会让 brief 字面不插值
    # （BFX-077：模型收不到纲要→自由发挥写非白灯人设）。
    return (
        f"你是中文小说写手。请据以下章节纲要独立创作第 {candidate_index + 1} 个候选正文，"
        "追求文学质量与叙事张力，1200-1800 字。只输出正文，不要标题或解释。\n\n纲要：\n"
        f"{brief}"
    )


# ── parsers ──


def _parse_scores(text: str, dimensions: tuple[str, ...]) -> dict[str, int]:
    """Extract per-dimension integer scores from the jury's JSON-ish reply."""
    out: dict[str, int] = {}
    for dim in dimensions:
        m = re.search(rf'"{re.escape(dim)}"\s*:\s*(\d+)', text)
        if m:
            out[dim] = int(m.group(1))
    if len(out) != len(dimensions):
        missing = sorted(set(dimensions) - set(out))
        raise _SelectionError(
            "jury score response omitted or malformed dimensions: "
            + ", ".join(missing)
        )
    return out


def _parse_bool(text: str) -> bool:
    m = re.search(r"has_substantive_difference[\"']?\s*:\s*(true|false)", text, re.I)
    if m:
        return m.group(1).lower() == "true"
    raise _SelectionError("jury difference response is not parseable")
