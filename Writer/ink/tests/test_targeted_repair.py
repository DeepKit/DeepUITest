from __future__ import annotations

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.pipeline.targeted_repair_orchestrator import TargetedRepairOrchestrator
from test_m5_chapter_review import _ids, make_soft_sealed_chapter


class RepairProvider:
    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        source = prompt_text.split("\n\n", 1)[1]
        repaired = source.replace("作者知道门外是谁。", "许怀山只听见门外鞋底擦过水泥地。")
        return ModelResult(
            text=repaired,
            model_name=model_name,
            token_input=10,
            token_output=10,
        )


def test_targeted_repair_writes_audited_revision_from_current_text() -> None:
    conn = make_soft_sealed_chapter()
    ids = _ids(conn)
    current = conn.execute(
        "SELECT revision_id, text FROM v_current_text WHERE shot_id=?",
        (ids["shot_id"],),
    ).fetchone()
    conn.execute(
        "UPDATE writing_shot_revisions SET text='作者知道门外是谁。' WHERE revision_id=?",
        (current[0],),
    )

    result = TargetedRepairOrchestrator(
        conn,
        LLMGateway(conn, provider=RepairProvider()),
    ).repair(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        issue="全知叙述越过人物认知",
        expected_pov="许怀山",
    )

    row = conn.execute(
        "SELECT text, source_revision_id, sealed_by FROM writing_shot_revisions WHERE revision_id=?",
        (result.revision_id,),
    ).fetchone()
    assert row[0] == "许怀山只听见门外鞋底擦过水泥地。"
    assert row[1] == current[0]
    assert row[2] == "shot_soft"
