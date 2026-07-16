from __future__ import annotations

import json
import sqlite3

from ink.contract.generated.dtos import OutlineSpecDTO
from ink.contract.loader import load_shot_contract
from ink.core.chapter_continuity import load_continuity_context, render_continuity_section
from ink.core.llm_gateway import LLMGateway
from ink.core.state_machine import load_status, transition
from ink.errors import DataIntegrityError
from ink.outline.drift import cjk_bigram_overlap, is_drift_rejected
from ink.outline.repository import OutlineRepository


_DEFAULT_ORCHESTRATOR: "OutlineOrchestrator | None" = None


def evaluate_and_select(shot_id: str, run_id: int) -> OutlineSpecDTO:
    if _DEFAULT_ORCHESTRATOR is None:
        raise DataIntegrityError("outline orchestrator is not configured")
    return _DEFAULT_ORCHESTRATOR.evaluate_and_select(shot_id, run_id)


class OutlineOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway | None = None) -> None:
        self.conn = conn
        self.gateway = gateway or LLMGateway(conn)

    def evaluate_and_select(self, shot_id: str, run_id: int) -> OutlineSpecDTO:
        context = _load_outline_context(self.conn, shot_id, run_id)
        current_status = _enter_outline_state(self.conn, shot_id, run_id)
        contract = load_shot_contract(self.conn, shot_id, run_id)
        source_text = _contract_source_text(contract.must_land, contract.scene_contract)
        continuity = load_continuity_context(self.conn, shot_id, run_id)
        continuity_section = render_continuity_section(continuity)
        pov_only = _flatten_text(contract.anti_write.get("pov_only"))
        repo = OutlineRepository(self.conn)

        eligible: list[tuple[int, str, float]] = []
        max_attempts = max(context.min_eligible_outlines * 3, len(context.writer_models), 1)
        for attempt in range(1, max_attempts + 1):
            model_name = context.writer_models[(attempt - 1) % len(context.writer_models)]
            prompt_text = _outline_prompt(
                source_text,
                attempt,
                continuity_section=continuity_section,
                pov_only=pov_only,
            )
            result = self.gateway.call(
                project_id=context.project_id,
                shot_id=shot_id,
                run_id=run_id,
                call_type="outline",
                prompt_id=None,
                prompt_text=prompt_text,
                model_name=model_name,
                idempotency_key=f"outline:{shot_id}:{run_id}:{attempt}",
            )
            drift_score = cjk_bigram_overlap(source_text, result.text)
            outline_id = repo.add_outline(context.shot_contract_id, result.text, drift_score)
            if is_drift_rejected(drift_score, context.outline_drift_threshold):
                continue
            eligible.append((outline_id, result.text, drift_score))
            if len(eligible) >= context.min_eligible_outlines:
                break

        if len(eligible) < context.min_eligible_outlines:
            raise DataIntegrityError(
                f"eligible outlines below threshold: {len(eligible)} < {context.min_eligible_outlines}"
            )

        winner_id = max(eligible, key=lambda item: (item[2], -item[0]))[0]
        repo.select_winner(context.shot_contract_id, winner_id)
        if current_status == "outline_draft":
            transition(self.conn, shot_id, run_id, "outline_draft", "outline_confirmed")
        return repo.load_winner(context.shot_contract_id)


class _OutlineContext:
    def __init__(
        self,
        *,
        project_id: int,
        shot_contract_id: int,
        min_eligible_outlines: int,
        outline_drift_threshold: float,
        writer_models: tuple[str, ...],
    ) -> None:
        self.project_id = project_id
        self.shot_contract_id = shot_contract_id
        self.min_eligible_outlines = min_eligible_outlines
        self.outline_drift_threshold = outline_drift_threshold
        self.writer_models = writer_models


def _load_outline_context(conn: sqlite3.Connection, shot_id: str, run_id: int) -> _OutlineContext:
    row = conn.execute(
        """
        SELECT s.project_id, s.shot_contract_id, p.min_eligible_outlines,
               p.outline_drift_threshold, p.writer_model_pool
        FROM writing_shots s
        JOIN writing_projects p ON p.project_id = s.project_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if row is None or row[1] is None:
        raise DataIntegrityError(f"shot not found or missing contract: {shot_id}/{run_id}")

    models = tuple(str(item) for item in json.loads(row[4]))
    if not models:
        raise DataIntegrityError("writer_model_pool is empty")
    return _OutlineContext(
        project_id=int(row[0]),
        shot_contract_id=int(row[1]),
        min_eligible_outlines=int(row[2]),
        outline_drift_threshold=float(row[3]),
        writer_models=models,
    )


def _enter_outline_state(conn: sqlite3.Connection, shot_id: str, run_id: int) -> str:
    status = load_status(conn, shot_id, run_id)
    if status == "pending":
        transition(conn, shot_id, run_id, "pending", "outline_draft")
        return "outline_draft"
    if status in {"outline_draft", "outline_confirmed"}:
        return status
    raise DataIntegrityError(f"outline cannot run from status: {status}")


def _contract_source_text(must_land: dict[str, object], scene_contract: dict[str, object]) -> str:
    parts: list[str] = []
    for key in ("events", "beats", "information_releases"):
        parts.extend(_flatten_text(must_land.get(key)))
    parts.extend(_flatten_text(scene_contract.get("location")))
    parts.extend(_flatten_text(scene_contract.get("time_of_day")))
    return "".join(parts)


def _flatten_text(value: object) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    if isinstance(value, dict):
        return [str(item) for item in value.values()]
    if value is None:
        return []
    return [str(value)]


def _outline_prompt(
    source_text: str,
    attempt: int,
    *,
    continuity_section: str = "",
    pov_only: list[str] | None = None,
) -> str:
    pov_text = "、".join(pov_only or []) or "按契约既定 POV"
    return (
        f"为本 shot 生成第 {attempt} 个可直接交给小说写手的中文分镜大纲。\n"
        # 保留稳定的机器可解析标签；现有 provider/验收工具用它提取契约源。
        f"Contract source: {source_text}\n"
        f"契约素材: {source_text}\n"
        f"POV 硬锁: {pov_text}\n"
        f"{continuity_section}"
        "大纲必须先写“如何承接上一状态”，再列本 shot 的动作推进、信息释放和结尾落点。"
        "不得新增契约外 POV；如契约明确允许切换，必须写出可见的时间/地点/分隔符转场锚点。"
        "只返回大纲正文，不要解释。"
    )
