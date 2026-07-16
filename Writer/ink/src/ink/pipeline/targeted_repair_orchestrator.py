from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from ink.core.llm_gateway import LLMGateway
from ink.core.prose_integrity import extract_polished_prose, find_generation_artifact
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError


@dataclass(frozen=True)
class TargetedRepairResult:
    project_id: int
    chapter_id: int
    shot_id: str
    run_id: int
    source_revision_id: int
    revision_id: int
    model_name: str
    length_before: int
    length_after: int


class TargetedRepairOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway) -> None:
        self.conn = conn
        self.gateway = gateway

    def repair(
        self,
        shot_id: str,
        run_id: int,
        *,
        issue: str,
        expected_pov: str | None = None,
    ) -> TargetedRepairResult:
        row = self.conn.execute(
            """
            SELECT s.project_id, s.chapter_id, s.status, v.revision_id, v.text
            FROM writing_shots s
            JOIN v_current_text v ON v.shot_id=s.shot_id
            WHERE s.shot_id=? AND s.run_id=?
            """,
            (shot_id, run_id),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"shot/current text not found: {shot_id}/{run_id}")
        project_id, chapter_id = int(row[0]), int(row[1])
        status = str(row[2])
        source_revision_id, source_text = int(row[3]), str(row[4])
        if status != "soft_sealed":
            raise DataIntegrityError(f"targeted repair requires soft_sealed shot, got: {status}")
        if TextRepository(self.conn).is_hard_sealed(shot_id, run_id):
            raise DataIntegrityError("accepted/hard-sealed prose cannot be targeted-repaired")
        if not issue.strip():
            raise DataIntegrityError("targeted repair requires a concrete review issue")

        pov_instruction = (
            f"硬锁 POV：{expected_pov.strip()}。\n" if expected_pov and expected_pov.strip() else ""
        )
        prompt = (
            "你是出版级小说责任编辑。对下方完整正文做一次最小范围定点修订。\n"
            f"{pov_instruction}"
            f"已确认问题：{issue.strip()}\n"
            "只改造成该问题的句子；保留所有事件、事实、物件、段落顺序、节奏、留白、人物声线和"
            "章末钩子。不得新增解释，不得把隐约感受改成作者结论。只输出修复后的完整小说正文，"
            "禁止任何说明、标题、问候、markdown 围栏或修改清单。\n\n"
            f"{source_text}"
        )
        idem = f"polish:targeted-repair:{shot_id}:{run_id}:{source_revision_id}"
        self.conn.execute("DELETE FROM writing_ai_call_attempts WHERE idempotency_key=?", (idem,))
        result = self.gateway.call(
            project_id=project_id,
            shot_id=shot_id,
            run_id=run_id,
            call_type="polish",
            prompt_id=None,
            prompt_text=prompt,
            model_name="smart-polish",
            idempotency_key=idem,
        )
        try:
            repaired = extract_polished_prose(result.text)
        except ValueError as exc:
            raise DataIntegrityError(str(exc)) from exc
        artifact = find_generation_artifact(repaired)
        if artifact:
            raise DataIntegrityError(f"repaired prose contains generation artifact: {artifact}")
        ratio = len(repaired) / max(1, len(source_text))
        if len(source_text) >= 200 and (ratio < 0.75 or ratio > 1.25):
            raise DataIntegrityError(f"targeted repair changed text length too much: ratio={ratio:.3f}")
        revision_id = TextRepository(self.conn).write_revision(
            shot_id,
            run_id,
            repaired,
            source_revision_id=source_revision_id,
            seal="shot_soft",
        )
        return TargetedRepairResult(
            project_id=project_id,
            chapter_id=chapter_id,
            shot_id=shot_id,
            run_id=run_id,
            source_revision_id=source_revision_id,
            revision_id=revision_id,
            model_name=result.model_name,
            length_before=len(source_text),
            length_after=len(repaired),
        )
