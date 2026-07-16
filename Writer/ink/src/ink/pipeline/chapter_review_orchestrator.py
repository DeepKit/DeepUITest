from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

from ink.core.chapter_coherence import CoherenceGateResult, evaluate_chapter_overlap
from ink.core.chapter_continuity import load_previous_chapter_tail
from ink.core.llm_gateway import LLMGateway
from ink.core.prose_integrity import find_generation_artifact
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError, LLMProviderError
from ink.time import now_utc_iso


CHAPTER_REVIEW_DIMENSIONS = (
    "chapter_continuity_hard",
    "pov_consistency",
    "character_consistency",
    "chapter_hook_soft",
    "rhythm_curve",
    "motif_density",
    "info_gap_lifecycle",
    "chapter_coherence",
)

_CHAPTER_REVIEW_DIM_LABELS = {
    "chapter_continuity_hard": "章续硬衔接（与上一章结尾的逻辑/时空连续）",
    "pov_consistency": "视角一致性（POV 不漂移、人称不混用）",
    "character_consistency": "人物一致性（言行/动机符合设定）",
    "chapter_hook_soft": "章末钩子（是否拉住读者往下读）",
    "rhythm_curve": "节奏曲线（张弛得当、信息密度合理）",
    "motif_density": "母题密度（核心母题在本章的呼应次数与质量）",
    "info_gap_lifecycle": "信息缺口生命周期（悬念抛出/搁置/回收的节奏）",
    "chapter_coherence": "成篇连贯（跨章结构有新增推进，不无意义重演前章核心场景/动作）",
}


class ChapterReviewLLMFailure(Exception):
    """chapter_review 的 LLM 调用三 tier 全失败（供应商故障），不写假分。"""


@dataclass(frozen=True)
class ChapterReviewResult:
    review_id: int
    project_id: int
    chapter_id: int
    run_id: int
    quality_gate_passed: bool
    blocking_issues: tuple[str, ...]


@dataclass(frozen=True)
class ChapterReviewAudit:
    pov_tail_violation: bool = False
    pov_tail_evidence: str = ""
    continuity_violation: bool = False
    continuity_evidence: str = ""


class ChapterReviewOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway) -> None:
        self.conn = conn
        self.gateway = gateway

    def review_chapter(self, project_id: int, chapter_id: int, run_id: int) -> ChapterReviewResult:
        shots = _load_chapter_shots(self.conn, project_id, chapter_id, run_id)
        if not shots:
            raise DataIntegrityError(f"chapter has no shots: {project_id}/{chapter_id}/{run_id}")
        not_soft_sealed = [shot_id for shot_id, status in shots if status != "soft_sealed"]
        if not_soft_sealed:
            raise DataIntegrityError(f"chapter review requires all shots soft_sealed: {not_soft_sealed}")

        repo = TextRepository(self.conn)
        texts = [repo.read_current_text(shot_id, run_id) for shot_id, _ in shots]
        floor = _chapter_quality_floor(self.conn, project_id)
        contract_summary = _load_chapter_contract_summary(self.conn, project_id, chapter_id, run_id)
        overlap = evaluate_chapter_overlap(
            self.conn,
            project_id=project_id,
            chapter_id=chapter_id,
            candidate_text="\n\n".join(texts),
        )
        _prepare_review_attempts(self.conn, project_id, chapter_id, run_id)
        scores, review_notes, audit = self._score_chapter(
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            texts=texts,
            contract_summary=contract_summary,
            previous_chapter_tail=load_previous_chapter_tail(
                self.conn,
                project_id,
                chapter_id,
            ),
            overlap=overlap,
        )
        blocking_issues = tuple(dimension for dimension, score in scores.items() if score < floor)
        if audit.pov_tail_violation:
            blocking_issues = _append_unique(blocking_issues, "pov_tail_transition")
            review_notes += f"\n[pov_tail_transition] {audit.pov_tail_evidence}"
        if audit.continuity_violation:
            blocking_issues = _append_unique(blocking_issues, "chapter_continuity_anchor")
            review_notes += f"\n[chapter_continuity_anchor] {audit.continuity_evidence}"
        artifact_hits = [
            artifact
            for text in texts
            if (artifact := find_generation_artifact(text)) is not None
        ]
        if artifact_hits:
            blocking_issues = _append_unique(blocking_issues, "publication_artifact")
            review_notes += (
                "\n[publication_artifact] 正文含模型问候/润色说明/markdown 等不可出版元文本："
                + "；".join(dict.fromkeys(artifact_hits))
            )
        # 悬疑张力衰减监控（E13）：客观聚合章内 winner 行 suspense_tension_median 中位数，
        # 低于项目 suspense_decay_floor（默认 82）则强制回炉 —— 补 LLM 7 维无法捕捉的悬疑衰减。
        shot_ids = tuple(shot_id for shot_id, _ in shots)
        decay_block, decay_median = _chapter_suspense_decay_block(self.conn, project_id, shot_ids)
        if decay_block:
            blocking_issues = blocking_issues + (decay_block,)
            review_notes = review_notes + (
                f"\n[suspense_decay] 章内 winner 行 suspense_tension_median 中位数="
                f"{decay_median:.1f} 低于回炉线 {_chapter_suspense_decay_floor(self.conn, project_id):.0f}，强制回炉（E13）。"
            )
        # 事实漂移硬校验（E13 病灶3）：对照项目事实基线 atomic clauses 判风格化传奇/
        # 失效机理模糊/报废制度冲突 —— 冲奖关键差异化维度，规则层 + LLM 兜底两层判定。
        drift_block, drift_evidence = self._industrial_fact_drift_block(
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            texts=texts,
            contract_summary=contract_summary,
        )
        if drift_block:
            blocking_issues = blocking_issues + (drift_block,)
            review_notes = review_notes + (
                f"\n[industrial_fact_drift] {drift_evidence}（对照 23_ 工艺基线）。"
            )
        repeated = tuple(item for item in overlap.overlaps if item.score >= overlap.threshold)
        if repeated:
            evidence = "; ".join(
                f"chapter={item.chapter_id}, overlap={item.score:.2f}, "
                f"shared={','.join(item.shared_tokens[:8])}"
                for item in repeated
            )
            blocking_issues = blocking_issues + ("chapter_scene_overlap",)
            review_notes = review_notes + f"\n[chapter_scene_overlap] {evidence}"
        review_id = self._write_review(
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            scores=scores,
            blocking_issues=blocking_issues,
            review_notes=review_notes,
        )
        return ChapterReviewResult(
            review_id=review_id,
            project_id=project_id,
            chapter_id=chapter_id,
            run_id=run_id,
            quality_gate_passed=not blocking_issues,
            blocking_issues=blocking_issues,
        )

    def _score_chapter(
        self,
        *,
        project_id: int,
        chapter_id: int,
        run_id: int,
        texts: list[str],
        contract_summary: str,
        previous_chapter_tail: str,
        overlap: CoherenceGateResult,
    ) -> tuple[dict[str, int], str, ChapterReviewAudit]:
        """Three-model chapter review with median scores and majority hard audits.

        Each reviewer starts from a different configured tier.  This prevents one
        model's stochastic POV/continuity interpretation from flipping a chapter
        between pass/fail on every rerun.
        """
        prompt_text = _chapter_review_prompt(
            texts,
            contract_summary,
            previous_chapter_tail=previous_chapter_tail,
            overlap_evidence=_chapter_overlap_evidence(overlap),
        )
        results: list[tuple[dict[str, int], str, ChapterReviewAudit]] = []
        tiers = ("primary", "secondary", "tertiary")
        for slot, tier in enumerate(tiers, start=1):
            try:
                result = self.gateway.call(
                    project_id=project_id,
                    shot_id=None,
                    run_id=run_id,
                    call_type="chapter_review",
                    prompt_id=None,
                    prompt_text=prompt_text,
                    model_name=None,
                    idempotency_key=f"chapter_review:{project_id}:{chapter_id}:{run_id}:{slot}",
                    tier_hint=tier,
                )
                results.append(_parse_chapter_scores(result.text))
            except LLMProviderError:
                continue
        if len(results) < 2:
            raise ChapterReviewLLMFailure(
                f"chapter_review 需要至少 2 个有效独立评审，实际 {len(results)}；"
                "请检查 role-config 主/备/兜底三档 api-key 与 base_url（call_type=chapter_review）"
            )
        scores = {
            dimension: int(_numeric_median([item[0][dimension] for item in results]))
            for dimension in CHAPTER_REVIEW_DIMENSIONS
        }
        notes = "\n".join(
            f"[reviewer-{index}] {item[1]}" for index, item in enumerate(results, start=1)
        )
        pov_votes = [item[2] for item in results if item[2].pov_tail_violation]
        continuity_votes = [item[2] for item in results if item[2].continuity_violation]
        majority = len(results) // 2 + 1
        audit = ChapterReviewAudit(
            pov_tail_violation=len(pov_votes) >= majority,
            pov_tail_evidence=" | ".join(
                item.pov_tail_evidence for item in pov_votes if item.pov_tail_evidence
            ),
            continuity_violation=len(continuity_votes) >= majority,
            continuity_evidence=" | ".join(
                item.continuity_evidence for item in continuity_votes if item.continuity_evidence
            ),
        )
        return scores, notes, audit

    def _industrial_fact_drift_block(
        self,
        *,
        project_id: int,
        chapter_id: int,
        run_id: int,
        texts: list[str],
        contract_summary: str,
    ) -> tuple[str | None, str | None]:
        """工业事实漂移硬校验（E13 病灶3：工业可信度失分，冲奖关键差异化）。

        两层判定，对照项目事实基线 atomic clauses（task#19 的(3)事实细节库）：
          1. 规则层（不调 LLM）：``forbidden`` ``[marker]`` 反向词表硬匹配命中即漂移；
             ``process`` ``[trigger]`` 触发词"本章提到失效/报废却未触及对应制度事实"的启发式判可疑段。
          2. LLM 兜底层（规则未命中或可疑段触发）：``call_type=chapter_review`` 调 gateway
             （复用 chapter_review 三档 role-config failover，零新 call_type 配置），
             严格 JSON 解析判定风格化传奇/失效机理模糊/报废制度冲突。

        命中（规则硬命中 或 LLM 判 drift=true）→ 返回 ``("industrial_fact_drift", evidence)``；
        无基线条目 / 规则未命中且无可疑段 / LLM 判无漂移 → ``(None, None)`` 不阻断。
        LLM 三 tier 全失败 → 返回 ``(None, None)`` 不阻断（工业事实是尽力而为补充校验，
        不因供应商故障中断 pipeline，与 write 降级哲学一致）。
        """
        clauses = _load_industrial_clauses(self.conn, project_id)
        if not clauses:
            return None, None
        chapter_text = "\n\n".join(texts)
        # — 规则层：forbidden marker 词表硬匹配 —
        forbidden_markers = [c for c in clauses if c["clause_type"] == "forbidden"]
        hit_marker = _match_forbidden_markers(chapter_text, forbidden_markers)
        if hit_marker:
            return "industrial_fact_drift", f"[规则硬命中] 风格漂移 marker「{hit_marker}」"
        # — 启发式：本章提失效/报废关键词但未触及对应 process 锚点 → 送 LLM 兜底 —
        suspicious = _suspicious_segments(chapter_text, clauses)
        if not suspicious:
            return None, None
        prompt_text = _industrial_drift_prompt(suspicious, contract_summary, clauses)
        idem = f"industrial_fact_drift:{project_id}:{chapter_id}:{run_id}"
        try:
            result = self.gateway.call(
                project_id=project_id,
                shot_id=None,
                run_id=run_id,
                call_type="chapter_review",
                prompt_id=None,
                prompt_text=prompt_text,
                model_name=None,
                idempotency_key=idem,
                tier_hint="primary",
            )
        except LLMProviderError:
            # 三 tier 全失败：工业事实是补充校验，不阻断 pipeline。
            return None, None
        try:
            drift_type, evidence_sentence = _parse_industrial_drift(result.text)
        except LLMProviderError:
            return None, None
        if drift_type is None:
            return None, None
        return "industrial_fact_drift", f"[LLM 判定/{drift_type}] {evidence_sentence}"

    def _write_review(
        self,
        *,
        project_id: int,
        chapter_id: int,
        run_id: int,
        scores: dict[str, int],
        blocking_issues: tuple[str, ...],
        review_notes: str,
    ) -> int:
        existing = self.conn.execute(
            """
            SELECT status
            FROM writing_chapter_reviews
            WHERE project_id = ? AND chapter_id = ? AND run_id = ?
            """,
            (project_id, chapter_id, run_id),
        ).fetchone()
        if existing is not None and str(existing[0]) == "accepted":
            raise DataIntegrityError(f"accepted chapter review cannot be overwritten: {project_id}/{chapter_id}/{run_id}")

        try:
            self.conn.execute("SAVEPOINT chapter_review")
            self.conn.execute(
                "DELETE FROM writing_chapter_reviews WHERE project_id = ? AND chapter_id = ? AND run_id = ?",
                (project_id, chapter_id, run_id),
            )
            cursor = self.conn.execute(
                """
                INSERT INTO writing_chapter_reviews
                    (project_id, chapter_id, run_id, status,
                     chapter_continuity_hard, pov_consistency, character_consistency,
                     chapter_hook_soft, rhythm_curve, motif_density, info_gap_lifecycle,
                     chapter_coherence, quality_gate_passed, blocking_issues, review_notes, reviewed_at)
                VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    chapter_id,
                    run_id,
                    scores["chapter_continuity_hard"],
                    scores["pov_consistency"],
                    scores["character_consistency"],
                    scores["chapter_hook_soft"],
                    scores["rhythm_curve"],
                    scores["motif_density"],
                    scores["info_gap_lifecycle"],
                    scores["chapter_coherence"],
                    int(not blocking_issues),
                    json.dumps(list(blocking_issues), ensure_ascii=False, sort_keys=True),
                    review_notes,
                    now_utc_iso(),
                ),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO chapter_review")
            self.conn.execute("RELEASE chapter_review")
            raise
        else:
            self.conn.execute("RELEASE chapter_review")
            return int(cursor.lastrowid)


def _load_chapter_shots(conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int) -> list[tuple[str, str]]:
    rows = conn.execute(
        """
        SELECT shot_id, status
        FROM writing_shots
        WHERE project_id = ? AND chapter_id = ? AND run_id = ?
        ORDER BY shot_id
        """,
        (project_id, chapter_id, run_id),
    ).fetchall()
    return [(str(row[0]), str(row[1])) for row in rows]


def _prepare_review_attempts(
    conn: sqlite3.Connection,
    project_id: int,
    chapter_id: int,
    run_id: int,
) -> None:
    """Make non-accepted chapter review reruns idempotent before calling the LLM.

    The attempt table owns a global UNIQUE idempotency key.  Deleting the old key
    only in ``_write_review`` is too late: the new real-model call has already
    tried to insert its attempt.  Accepted reviews remain immutable.
    """
    row = conn.execute(
        """
        SELECT status
        FROM writing_chapter_reviews
        WHERE project_id=? AND chapter_id=? AND run_id=?
        """,
        (project_id, chapter_id, run_id),
    ).fetchone()
    if row is None:
        return
    if str(row[0]) == "accepted":
        raise DataIntegrityError(
            f"accepted chapter review cannot be overwritten: {project_id}/{chapter_id}/{run_id}"
        )
    legacy_key = f"chapter_review:{project_id}:{chapter_id}:{run_id}"
    conn.execute(
        """
        DELETE FROM writing_ai_call_attempts
        WHERE idempotency_key = ?
           OR idempotency_key LIKE ?
           OR idempotency_key = ?
        """,
        (
            legacy_key,
            f"{legacy_key}:%",
            f"industrial_fact_drift:{project_id}:{chapter_id}:{run_id}",
        ),
    )


def _chapter_quality_floor(conn: sqlite3.Connection, project_id: int) -> int:
    row = conn.execute(
        "SELECT chapter_quality_floor FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"project not found: {project_id}")
    return int(row[0])


def _chapter_suspense_decay_floor(conn: sqlite3.Connection, project_id: int) -> float:
    row = conn.execute(
        "SELECT suspense_decay_floor FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"project not found: {project_id}")
    return float(row[0])


def _chapter_suspense_decay_block(
    conn: sqlite3.Connection, project_id: int, shot_ids: tuple[str, ...]
) -> tuple[str | None, float | None]:
    """悬疑张力衰减监控（E13）：聚合本章 winner 行 suspense_tension_median 取中位数。

    若中位数低于项目 suspense_decay_floor（默认 82），返回阻塞项 "suspense_decay" ——
    对应 E13 诊断"suspense_tension 91→82 递减后章节失张力"，强制回炉。

    shot 无 winner 行（jury 未跑/无聚合）时返回 (None, None)，不阻断：章级 suspense
    监控依赖 jury 已产出 winner 聚合；soft_sealed 前置已保证 jury 已跑。
    """
    if not shot_ids:
        return None, None
    placeholders = ",".join("?" for _ in shot_ids)
    rows = conn.execute(
        f"""
        SELECT suspense_tension_median
        FROM writing_jury_aggregates
        WHERE shot_id IN ({placeholders}) AND is_winner = 1
        """,
        shot_ids,
    ).fetchall()
    if not rows:
        return None, None
    medians = sorted(float(row[0]) for row in rows)
    mid = len(medians) // 2
    chapter_median = medians[mid]
    floor = _chapter_suspense_decay_floor(conn, project_id)
    return ("suspense_decay", chapter_median) if chapter_median < floor else (None, chapter_median)





def _load_chapter_contract_summary(
    conn: sqlite3.Connection, project_id: int, chapter_id: int, run_id: int
) -> str:
    """取本章各 shot task_card 的 compiled_instructions 拼接作为评审参考（与 jury 复用同一契约源）。

    评审看 writer 生成时用的同一约束，保证裁判与 writer 对齐。取 superseded_at IS NULL 当前版。
    """
    rows = conn.execute(
        """
        SELECT tc.compiled_instructions
        FROM writing_shot_task_cards tc
        JOIN writing_shots s ON s.shot_contract_id = tc.shot_contract_id
        WHERE s.project_id = ? AND s.chapter_id = ? AND s.run_id = ?
          AND tc.superseded_at IS NULL
        ORDER BY s.shot_id
        """,
        (project_id, chapter_id, run_id),
    ).fetchall()
    parts = [str(row[0]) for row in rows if row[0]]
    if not parts:
        return ""
    text = "\n---\n".join(parts)
    return text[:3000] + ("…[截断]" if len(text) > 3000 else "")


# ---- 事实漂移硬校验（块C2） -----------------------------------------
# marker/trigger 词表由项目 atomic clauses 驱动，机制本身不含小说专属语义。
def _load_industrial_clauses(conn: sqlite3.Connection, project_id: int) -> list[dict[str, object]]:
    """取项目事实基线 atomic clauses（clause_type IN process/forbidden）。

    全项目粒度（不绑 volume scope）——事实一致性是全项目约束；项目质感文档的制度
    事实（签字/报废/失效机理）对全书有效。返回字典列表，键：
    clause_type/severity/clause_text。无基线时返回空列表（检测器据此短路不阻断）。
    """
    rows = conn.execute(
        """
        SELECT clause_type, severity, clause_text
        FROM writing_atomic_source_clauses
        WHERE project_id = ? AND clause_type IN ('process', 'forbidden')
          AND status IN ('confirmed', 'proposed')
        """,
        (project_id,),
    ).fetchall()
    return [
        {"clause_type": r[0], "severity": r[1], "clause_text": r[2]}
        for r in rows
    ]


def _match_forbidden_markers(chapter_text: str, forbidden_clauses: list[dict[str, object]]) -> str | None:
    """规则层硬匹配：从 ``[marker]`` clause 文本解析词表，命中即返回命中的词。

    数据驱动（与主线解耦）：marker 词表存于具体项目的 atomic clauses 而非硬编码——
    换项目换基线即换词表，流水线本身不含任何小说专属语义。``[marker]`` 条目形如
    ``[marker] <分类描述>：<词1>、<词2>（注释）、<词3>。`` 冒号后为词表，括号注释
    在匹配前剔除。非 ``[marker]`` 的 forbidden 条目是软性创作纪律，交 LLM 判定。
    """
    markers = _extract_marker_terms(forbidden_clauses)
    if not markers:
        return None
    for marker in markers:
        if marker and marker in chapter_text:
            return marker
    return None


def _extract_marker_terms(forbidden_clauses: list[dict[str, object]]) -> list[str]:
    """从所有 ``[marker]`` clause 抽取词表项（去括号注释、按顿号/逗号分词）。"""
    terms: list[str] = []
    for clause in forbidden_clauses:
        text = str(clause["clause_text"])
        if not text.startswith("[marker]"):
            continue
        body = text[len("[marker]"):].strip()
        # 冒号后才是词表（冒号前是分类描述）。
        if "：" in body:
            body = body.split("：", 1)[1]
        elif ":" in body:
            body = body.split(":", 1)[1]
        # 剔除中/英文括号注释（"闻味即断（以仪式感替代工艺真实）" → "闻味即断"）。
        for opener, closer in (("（", "）"), ("(", ")")):
            while opener in body and closer in body and body.index(opener) < body.index(closer):
                start = body.index(opener)
                end = body.index(closer, start)
                body = body[:start] + body[end + 1:]
        for term in body.replace("，", "、").split("、"):
            term = term.strip(" 。.")
            if term:
                terms.append(term)
    return terms


def _suspicious_segments(chapter_text: str, clauses: list[dict[str, object]]) -> str:
    """启发式筛可疑段：命中触发关键词的段落送 LLM 兜底判定。

    数据驱动（与主线解耦）：触发关键词从 ``[trigger]`` 前缀的 process clause 解析，
    而非硬编码——"失效/报废/前线"这类工艺语义词属具体项目基线，存于其 atomic clauses。
    返回拼接的可疑文本（限 1500 字，超长截断）；无 ``[trigger]`` clause 或无可疑段
    返回空串（检测器据此返回不阻断）���规则层 forbidden marker 未命中时调用——
    把"提到触发词却没说清制度事实"的段落交给 LLM 判。
    """
    trigger_keywords = _extract_trigger_keywords(clauses)
    if not trigger_keywords or not any(kw in chapter_text for kw in trigger_keywords):
        return ""
    # 按段落（空行分隔）筛含触发关键词的段。
    paragraphs = [p.strip() for p in chapter_text.split("\n\n") if p.strip()]
    suspicious = [p for p in paragraphs if any(kw in p for kw in trigger_keywords)]
    if not suspicious:
        return ""
    text = "\n---\n".join(suspicious)
    return text[:1500] + ("…[截断]" if len(text) > 1500 else "")


def _extract_trigger_keywords(clauses: list[dict[str, object]]) -> list[str]:
    """从所有 ``[trigger]`` clause 抽取触发关键词词表（去括号注释、按顿号/逗号分词）。

    ``[trigger]`` clause 形如 ``[trigger] 工艺失效信号词：失效、报废、前线、押运、废品。``，
    冒号后为词表。供 ``_suspicious_segments`` 启发式筛段——与 ``_extract_marker_terms``
    对称：marker 是 forbidden 反向词表，trigger 是 process 触发词表，皆存项目基线。
    """
    terms: list[str] = []
    for clause in clauses:
        text = str(clause["clause_text"])
        if not text.startswith("[trigger]"):
            continue
        body = text[len("[trigger]"):].strip()
        if "：" in body:
            body = body.split("：", 1)[1]
        elif ":" in body:
            body = body.split(":", 1)[1]
        for opener, closer in (("（", "）"), ("(", ")")):
            while opener in body and closer in body and body.index(opener) < body.index(closer):
                start = body.index(opener)
                end = body.index(closer, start)
                body = body[:start] + body[end + 1:]
        for term in body.replace("，", "、").split("、"):
            term = term.strip(" 。.")
            if term:
                terms.append(term)
    return terms


def _industrial_drift_prompt(
    suspicious: str, contract_summary: str, clauses: list[dict[str, object]]
) -> str:
    """构造事实漂移判定 prompt：注入项目事实基线 + 可疑段 + 严格 JSON 输出。

    机制通用、不含任何小说专属语义——具体领域事实由注入的 atomic clauses 基线
    文本带入（``[marker]``/``[trigger]``/``process`` 条目本身携带项目语义）。
    """
    baseline_block = "\n".join(
        f"  - [{c['clause_type']}/{c['severity']}] {c['clause_text']}" for c in clauses
    )
    return (
        "你是工业叙事事实漂移审查员。判定下述可疑段落是否发生「事实漂移」。"
        "必须保护文学表达：比喻、留白、人物当时不知道根因、或仅报告具体症状，都不自动等于"
        "机理模糊。只有文本主动给出/暗示因果解释却缺乏可核验支撑，才可判"
        " failure_mechanism_vague。\n\n"
        f"## 事实基线（本章须对照）\n{baseline_block}\n\n"
        f"## 契约要点\n{contract_summary or '（无契约摘要）'}\n\n"
        f"## 可疑段落\n{suspicious}\n\n"
        "## 判定协议\n"
        "1. claim_mode=observation_only：只展示症状/线索；causal_claim：声称原因或机理；"
        "institutional_claim：声称制度/流程如何处理。\n"
        "2. causal_claim 至少应有一个可观测锚点（温湿度、时间、尺寸、批次、裂纹位置/形态、"
        "材料状态、测试结果等）和一条可复盘因果链（条件→材料/工艺变化→缺陷→后果）。\n"
        "3. observation_only 只要症状具体且符合悬疑信息释放节奏，即使暂未解释根因，"
        "不得判 failure_mechanism_vague。条件与故障线索相邻出现、人物提出怀疑、"
        "或报告“露天堆放四天”等背景事实，也仍是 observation_only；只有正文明确使用"
        "“因为/导致/造成/因此/源于/说明/证明/意味着/根因是”等因果断言，才可进入 causal_claim。\n"
        "4. scrap_regime_conflict 必须指出与哪条基线制度直接冲突；不能因本段没有复述完整流程而判冲突。\n"
        "5. wuxia 仅在传奇化能力替代工艺证据时成立；普通修辞不成立。\n\n"
        "## 输出要求\n"
        "严格输出一个 JSON 对象：{\"drift\": <true/false>, "
        "\"drift_type\": <\"wuxia\"|\"failure_mechanism_vague\"|\"scrap_regime_conflict\"|null>, "
        "\"claim_mode\": <\"observation_only\"|\"causal_claim\"|\"institutional_claim\">, "
        "\"observable_anchors\": [<已有的可观测参数或症状>], "
        "\"causal_chain\": [<按顺序列出已有因果节点>], "
        "\"missing_requirements\": [<真正缺失且导致漂移的要素>], "
        "\"baseline_conflict\": <冲突基线原句或空串>, "
        "\"confidence\": <0到1>, "
        "\"evidence_sentence\": <从段落引用的判定证据句>}。drift=false 时 drift_type=null、"
        "evidence_sentence 可为空串。不要任何额外文本、不要 markdown 代码围栏。示例：\n"
        '{"drift": false, "drift_type": null, "claim_mode": "observation_only", '
        '"observable_anchors": ["裂纹集中在密封件边缘", "露天高湿环境三日"], '
        '"causal_chain": [], "missing_requirements": [], "baseline_conflict": "", '
        '"confidence": 0.91, "evidence_sentence": ""}'
    )


def _parse_industrial_drift(text: str) -> tuple[str | None, str]:
    """严格解析工业漂移判定 JSON。返回 (drift_type, evidence_sentence)。

    drift=false / 无 drift_type → (None, "")。解析失败抛 ``LLMProviderError``
    （交 gateway 换 tier 重试；本检测器上层已 catch 转 (None,None) 不阻断）。
    """
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[-1]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        cleaned = cleaned.strip()
    try:
        obj = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise LLMProviderError(f"industrial drift JSON 解析失败: {exc}: {text[:200]}") from exc
    if not isinstance(obj, dict) or "drift" not in obj:
        raise LLMProviderError(f"industrial drift JSON 缺 drift 字段: {text[:200]}")
    drift = bool(obj.get("drift"))
    drift_type = obj.get("drift_type")
    if not drift or drift_type is None:
        return None, ""
    if drift_type not in ("wuxia", "failure_mechanism_vague", "scrap_regime_conflict"):
        raise LLMProviderError(f"industrial drift JSON drift_type 非法: {drift_type}")
    # 新协议返回结构化自证时，执行一致性校验。旧历史响应无这些字段时保持兼容。
    claim_mode = obj.get("claim_mode")
    confidence_raw = obj.get("confidence")
    confidence = float(confidence_raw) if isinstance(confidence_raw, (int, float)) else None
    if confidence is not None and confidence < 0.75:
        return None, ""
    if drift_type == "failure_mechanism_vague" and claim_mode is not None:
        missing = obj.get("missing_requirements")
        if claim_mode != "causal_claim":
            return None, ""
        if not isinstance(missing, list) or not any(str(item).strip() for item in missing):
            return None, ""
        evidence_for_claim = str(obj.get("evidence_sentence", "")).strip()
        if not _contains_explicit_causal_claim(evidence_for_claim):
            return None, ""
    if drift_type == "scrap_regime_conflict" and claim_mode is not None:
        if claim_mode != "institutional_claim":
            return None, ""
        if not str(obj.get("baseline_conflict", "")).strip():
            return None, ""
    evidence = str(obj.get("evidence_sentence", "")).strip()
    return str(drift_type), evidence


def _contains_explicit_causal_claim(text: str) -> bool:
    cues = (
        "因为",
        "由于",
        "导致",
        "造成",
        "因此",
        "所以",
        "源于",
        "引发",
        "使得",
        "说明",
        "证明",
        "意味着",
        "根因",
        "原因是",
        "注定",
    )
    return any(cue in text for cue in cues)


def _chapter_overlap_evidence(overlap: CoherenceGateResult) -> str:
    """Render bounded deterministic overlap evidence for the literary reviewer."""
    if not overlap.overlaps:
        return "无可比较的前序封版章（首章或前章尚未封版）。"
    ranked = sorted(overlap.overlaps, key=lambda item: item.score, reverse=True)[:3]
    return "\n".join(
        f"- 前章 {item.chapter_id}: overlap={item.score:.2f}, "
        f"shared={','.join(item.shared_tokens[:8]) or '无'}"
        for item in ranked
    ) + f"\n确定性阻断阈值={overlap.threshold:.2f}；此结果不可被文学评分推翻。"


def _chapter_review_prompt(
    texts: list[str],
    contract_summary: str,
    *,
    previous_chapter_tail: str = "",
    overlap_evidence: str = "",
) -> str:
    """构造章级评审 prompt：注入章文本、契约、重叠证据与严格 JSON 输出。"""
    dims_block = "\n".join(
        f'  "{col}": <0-100 整数>  // {label}' for col, label in _CHAPTER_REVIEW_DIM_LABELS.items()
    )
    chapter_text = "\n\n".join(texts)
    previous_block = previous_chapter_tail or "（首章或没有可用上一章正文，不做跨章承接处罚）"
    dimension_count = len(CHAPTER_REVIEW_DIMENSIONS)
    overlap_block = overlap_evidence or "无可用确定性重叠证据。"
    return (
        f"你是小说章级质量评审。审视本章（一章可能含多个 shot）文本，对照契约要点给出 {dimension_count} 维硬质量评分。\n\n"
        f"## 契约要点（本章各 shot 生成时所用约束）\n{contract_summary or '（无契约摘要）'}\n\n"
        f"## 上一章最终状态（仅用于章续硬衔接）\n{previous_block}\n\n"
        f"## 确定性跨章重叠证据（只读，不得重算或推翻）\n{overlap_block}\n\n"
        f"## 本章文本\n{chapter_text}\n\n"
        f"## 评分维度（共 {dimension_count} 维，每维 0-100 整数）\n{dims_block}\n\n"
        "## 两项不可被平均分掩盖的硬审计\n"
        "A. 末段 POV：检查本章最后 25%（至少最后两个自然段）。只有叙述进入契约 POV 之外角色"
        "的感知、记忆、判断或内心才算切 POV；仅提及、看见、对话中出现其他角色不算。"
        "若发生切换且之前没有章节标题、场景分隔符、明确时间/地点变化等读者可见锚点，"
        "pov_tail_audit.violation=true，pov_consistency 不得高于 60。\n"
        "B. 章续承接：若提供了上一章最终状态，本章开头必须解释人物位置、时间、未完成动作或悬念"
        "如何继续/为何转移。无解释的时空跳跃，或把上一章未完成现场直接丢弃，"
        "continuity_audit.violation=true，chapter_continuity_hard 不得高于 60。"
        "若没有上一章正文则跨章项必须 false；章内相邻 shot 的无锚点跳转仍按 violation 处理。\n"
        "C. 成篇连贯：chapter_coherence 评价本章相对前章是否承担新的结构职责、推进新的事件/信息，"
        "以及是否避免无意义重演前章核心场景与动作。确定性重叠证据达到阈值时，系统会独立阻断；"
        "本维度不得把该结果改判为通过，也不得仅因共享设定词就低分。\n\n"
        "## 输出要求\n"
        f"严格输出一个 JSON 对象，含上述 {dimension_count} 个维度键（值为 0-100 整数）、\"review_notes\"，"
        "以及两个结构化硬审计对象。不要任何额外文本、不要 markdown 代码围栏。示例：\n"
        '{"chapter_continuity_hard": 88, "pov_consistency": 90, "character_consistency": 85, '
        '"chapter_hook_soft": 82, "rhythm_curve": 86, "motif_density": 80, "info_gap_lifecycle": 84, '
        '"chapter_coherence": 87, "review_notes": "章末钩子偏弱，节奏前紧后松。", '
        '"pov_tail_audit": {"violation": false, "expected_pov": "许怀山", "observed_pov": "许怀山", '
        '"transition_anchor": "", "evidence": ""}, '
        '"continuity_audit": {"violation": false, "transition_anchor": "次日清晨/同一厂区", '
        '"evidence": "开头明确交代时间推进并承接上一章未完成调查"}}'
    )


def _parse_chapter_scores(text: str) -> tuple[dict[str, int], str, ChapterReviewAudit]:
    """解析评审返回的章级维度分（0-100）+ review_notes。

    容错：非 JSON / 缺维 / 越界 → 抛 ``LLMProviderError``（交 gateway failover 换 tier 重试）。
    review_notes 缺失回退固定串（不视为硬失败）。
    """
    raw = text.strip()
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise LLMProviderError("chapter_review 评分非 JSON：未找到 JSON 对象边界")
    try:
        obj = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as exc:
        raise LLMProviderError(f"chapter_review 评分 JSON 解析失败：{exc}") from exc
    scores: dict[str, int] = {}
    for col in CHAPTER_REVIEW_DIMENSIONS:
        if col not in obj:
            raise LLMProviderError(f"chapter_review 评分缺维度：{col}")
        val = obj[col]
        if not isinstance(val, (int, float)) or isinstance(val, bool):
            raise LLMProviderError(f"chapter_review 评分维度 {col} 非数值：{val!r}")
        iv = int(val)
        if iv < 0 or iv > 100:
            raise LLMProviderError(f"chapter_review 评分维度 {col} 越界(0-100)：{iv}")
        scores[col] = iv
    notes = obj.get("review_notes")
    if not isinstance(notes, str) or not notes.strip():
        notes = "chapter review（无 evidence）"
    pov_audit = obj.get("pov_tail_audit")
    continuity_audit = obj.get("continuity_audit")
    return scores, notes, ChapterReviewAudit(
        pov_tail_violation=_audit_violation(pov_audit),
        pov_tail_evidence=_audit_evidence(pov_audit, "末段发生无转场 POV 切换"),
        continuity_violation=_audit_violation(continuity_audit),
        continuity_evidence=_audit_evidence(continuity_audit, "本章缺少上一状态承接锚点"),
    )


def _audit_violation(value: object) -> bool:
    return isinstance(value, dict) and value.get("violation") is True


def _audit_evidence(value: object, fallback: str) -> str:
    if not isinstance(value, dict):
        return ""
    evidence = str(value.get("evidence", "")).strip()
    expected = str(value.get("expected_pov", "")).strip()
    observed = str(value.get("observed_pov", "")).strip()
    anchor = str(value.get("transition_anchor", "")).strip()
    details: list[str] = []
    if expected or observed:
        details.append(f"expected={expected or '未知'}, observed={observed or '未知'}")
    if anchor:
        details.append(f"anchor={anchor}")
    if evidence:
        details.append(evidence)
    return "；".join(details) or fallback


def _append_unique(items: tuple[str, ...], value: str) -> tuple[str, ...]:
    return items if value in items else items + (value,)


def _numeric_median(values: list[int]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return float(ordered[middle])
    return (ordered[middle - 1] + ordered[middle]) / 2.0
