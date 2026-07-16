from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

from ink.core.llm_gateway import LLMGateway
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError, LLMProviderError
from ink.time import now_utc_iso


RISK_ORDER = {"low": 0, "medium": 1, "high": 2, "blocking": 3}


@dataclass(frozen=True)
class EthicsReviewResult:
    ethics_review_id: int
    project_id: int
    chapter_id: int
    run_id: int
    risk_level: str
    recommendation: str
    reviewer_models: tuple[str, ...]


@dataclass(frozen=True)
class _EthicsVote:
    responsibility_question: str
    affected_parties: tuple[str, ...]
    irreversible_harm: str
    agency_obscured: bool
    evidence_sentences: tuple[str, ...]
    risk_level: str
    recommendation: str
    review_notes: str


class EthicsReviewOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway) -> None:
        self.conn = conn
        self.gateway = gateway

    def review_chapter(
        self,
        project_id: int,
        chapter_id: int,
        run_id: int,
        *,
        reviewer_actor: str,
    ) -> EthicsReviewResult:
        accepted = self.conn.execute(
            """
            SELECT 1 FROM writing_chapter_reviews
            WHERE project_id=? AND chapter_id=? AND run_id=? AND status='accepted'
            """,
            (project_id, chapter_id, run_id),
        ).fetchone()
        if accepted is not None:
            raise DataIntegrityError("accepted chapter ethics review is immutable")
        shots = self.conn.execute(
            """
            SELECT shot_id, status FROM writing_shots
            WHERE project_id=? AND chapter_id=? AND run_id=?
            ORDER BY shot_id
            """,
            (project_id, chapter_id, run_id),
        ).fetchall()
        if not shots or any(str(row[1]) != "soft_sealed" for row in shots):
            raise DataIntegrityError("ethics review requires all chapter shots soft_sealed")
        repo = TextRepository(self.conn)
        chapter_text = "\n\n".join(
            repo.read_current_text(str(row[0]), run_id) for row in shots
        )
        prompt = _ethics_prompt(chapter_text)
        prefix = f"ethics_review:{project_id}:{chapter_id}:{run_id}"
        self.conn.execute(
            "DELETE FROM writing_ai_call_attempts WHERE idempotency_key LIKE ?",
            (f"{prefix}:%",),
        )

        votes: list[_EthicsVote] = []
        models: list[str] = []
        for slot, tier in enumerate(("primary", "secondary", "tertiary"), start=1):
            key = f"{prefix}:{slot}"
            try:
                response = self.gateway.call(
                    project_id=project_id,
                    shot_id=None,
                    run_id=run_id,
                    call_type="chapter_review",
                    prompt_id=None,
                    prompt_text=prompt,
                    model_name=None,
                    idempotency_key=key,
                    tier_hint=tier,
                )
                votes.append(_parse_ethics_vote(response.text))
                attempt = self.conn.execute(
                    """
                    SELECT model_name FROM writing_ai_call_attempts
                    WHERE idempotency_key=?
                    """,
                    (key,),
                ).fetchone()
                models.append(str(attempt[0]) if attempt else str(response.model_name))
            except LLMProviderError:
                continue
        if len(votes) < 2:
            raise LLMProviderError(
                f"ethics review requires at least 2 valid reviewers, got {len(votes)}"
            )

        risk = max((vote.risk_level for vote in votes), key=RISK_ORDER.__getitem__)
        revise_votes = sum(vote.recommendation == "revise" for vote in votes)
        recommendation = "revise" if risk == "blocking" or revise_votes >= (len(votes) // 2 + 1) else "approve"
        responsibility_question = max(
            (vote.responsibility_question for vote in votes),
            key=len,
        )
        irreversible_harm = max((vote.irreversible_harm for vote in votes), key=len)
        affected = _unique(item for vote in votes for item in vote.affected_parties)
        evidence = _unique(item for vote in votes for item in vote.evidence_sentences)
        notes = "\n".join(
            f"[ethics-reviewer-{idx}] {vote.review_notes}"
            for idx, vote in enumerate(votes, start=1)
        )
        self.conn.execute(
            """
            DELETE FROM writing_chapter_ethics_reviews
            WHERE project_id=? AND chapter_id=? AND run_id=?
            """,
            (project_id, chapter_id, run_id),
        )
        cursor = self.conn.execute(
            """
            INSERT INTO writing_chapter_ethics_reviews
                (project_id, chapter_id, run_id, reviewer_actor, reviewer_models_json,
                 responsibility_question, affected_parties_json, irreversible_harm,
                 agency_obscured, evidence_sentences_json, risk_level, recommendation,
                 review_notes, reviewed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                project_id,
                chapter_id,
                run_id,
                reviewer_actor,
                json.dumps(models, ensure_ascii=False),
                responsibility_question,
                json.dumps(affected, ensure_ascii=False),
                irreversible_harm,
                int(any(vote.agency_obscured for vote in votes)),
                json.dumps(evidence, ensure_ascii=False),
                risk,
                recommendation,
                notes,
                now_utc_iso(),
            ),
        )
        return EthicsReviewResult(
            ethics_review_id=int(cursor.lastrowid),
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            risk_level=risk,
            recommendation=recommendation,
            reviewer_models=tuple(models),
        )


def _ethics_prompt(chapter_text: str) -> str:
    return (
        "你是小说责任与伦理后果审查员。你的任务不是审查政治正确，也不是要求人物道德完美，"
        "而是确认文本没有用叙事技巧遮蔽行动者、受影响者和不可逆后果。\n\n"
        "重点检查：谁作出决定；谁承担风险；制度/集体措辞是否抹去个人能动性；"
        "伤害是否被浪漫化或仅作为悬疑道具；文本是否给读者足够证据自行判断。\n\n"
        f"## 本章正文\n{chapter_text}\n\n"
        "严格只输出 JSON："
        '{"responsibility_question":"本章要求读者判断的责任问题",'
        '"affected_parties":["受影响者"],'
        '"irreversible_harm":"可能或已经发生的不可逆后果",'
        '"agency_obscured":false,'
        '"evidence_sentences":["正文证据句"],'
        '"risk_level":"low|medium|high|blocking",'
        '"recommendation":"approve|revise",'
        '"review_notes":"简要理由"}。'
        "blocking 仅用于文本确实美化/抹除严重伤害或完全隐藏关键行动者；人物做出错误决定本身不是 blocking。"
    )


def _parse_ethics_vote(text: str) -> _EthicsVote:
    raw = text.strip()
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end <= start:
        raise LLMProviderError("ethics review response has no JSON object")
    try:
        obj = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as exc:
        raise LLMProviderError(f"ethics review JSON parse failed: {exc}") from exc
    risk = str(obj.get("risk_level", "")).strip()
    recommendation = str(obj.get("recommendation", "")).strip()
    if risk not in RISK_ORDER:
        raise LLMProviderError(f"invalid ethics risk_level: {risk}")
    if recommendation not in {"approve", "revise"}:
        raise LLMProviderError(f"invalid ethics recommendation: {recommendation}")
    return _EthicsVote(
        responsibility_question=str(obj.get("responsibility_question", "")).strip(),
        affected_parties=tuple(str(item).strip() for item in obj.get("affected_parties", []) if str(item).strip()),
        irreversible_harm=str(obj.get("irreversible_harm", "")).strip(),
        agency_obscured=obj.get("agency_obscured") is True,
        evidence_sentences=tuple(
            str(item).strip() for item in obj.get("evidence_sentences", []) if str(item).strip()
        ),
        risk_level=risk,
        recommendation=recommendation,
        review_notes=str(obj.get("review_notes", "")).strip(),
    )


def _unique(items) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in items:
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result
