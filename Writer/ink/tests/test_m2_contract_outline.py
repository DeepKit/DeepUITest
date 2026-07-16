from __future__ import annotations

import json

import pytest

from ink.contract.prompt import PromptSnapshotCompiler, load_latest_prompt_spec
from ink.contract.loader import load_shot_contract
from ink.contract.task_card import TaskCardCompiler
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import DataIntegrityError
from ink.outline.drift import cjk_bigram_overlap, is_drift_rejected
from ink.outline.repository import OutlineRepository
from ink.pipeline.outline_orchestrator import OutlineOrchestrator
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator
from ink.source.outline_parser import parse_outline
from ink.source.outline_to_contract import to_chapter_contract_payload, to_shot_contract_dict
from ink.linting.orchestrator_signature import lint_shot_orchestrator_source
from factories import NOW, insert_minimal_draft, make_schema_db


def test_contract_loader_reloads_full_projection_from_db() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_contract_children(conn, int(ids["shot_contract_id"]))

    contract = load_shot_contract(conn, str(ids["shot_id"]), int(ids["run_id"]))

    assert contract.shot_id == ids["shot_id"]
    assert contract.must_land["events"] == ["enter room"]
    assert contract.anti_write["pov_only"] == ["A"]
    assert contract.scene_contract["location"] == "archive"
    assert contract.persona_assignment["persona"] == "意象师"
    assert contract.soft_constraints["deviation_budget"] == 0.2


def test_task_card_compiler_rejects_incomplete_tail_and_supersedes_old_cards() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    compiler = TaskCardCompiler(conn)

    with pytest.raises(DataIntegrityError):
        compiler.write_task_card(int(ids["shot_contract_id"]), "把角色推到门边，然后")

    conn.commit()
    new_id = compiler.write_task_card(int(ids["shot_contract_id"]), "把角色推到门边。")

    rows = conn.execute(
        """
        SELECT task_card_id, superseded_at
        FROM writing_shot_task_cards
        WHERE shot_contract_id = ?
        ORDER BY task_card_id
        """,
        (ids["shot_contract_id"],),
    ).fetchall()
    assert rows[0][1] is not None
    assert rows[-1] == (new_id, None)


def test_task_card_compiler_compiles_only_from_db_contract() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_contract_children(conn, int(ids["shot_contract_id"]))
    conn.commit()
    compiler = TaskCardCompiler(conn)

    card = compiler.compile_for_shot(str(ids["shot_id"]), int(ids["run_id"]))

    assert card.shot_contract_id == ids["shot_contract_id"]
    assert "enter room" in card.compiled_instructions
    assert "Outline:" not in card.compiled_instructions


def test_prompt_snapshot_compiler_supersedes_by_task_card_persona() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    compiler = PromptSnapshotCompiler(conn)

    first_id = compiler.write_prompt_snapshot(int(ids["task_card_id"]), "text", "prompt v1")
    second = compiler.write_prompt_snapshot(int(ids["task_card_id"]), "text", "prompt v2")
    latest = load_latest_prompt_spec(conn, int(ids["task_card_id"]), "text")

    assert latest.prompt_id == second
    assert latest.prompt_size_bytes == len("prompt v2".encode("utf-8"))
    rows = conn.execute(
        """
        SELECT prompt_id, superseded_at
        FROM writing_prompt_snapshots
        WHERE task_card_id = ? AND persona = 'text'
        ORDER BY prompt_id
        """,
        (ids["task_card_id"],),
    ).fetchall()
    assert rows[0][1] is not None
    assert rows[1][0] == first_id
    assert rows[1][1] is not None
    assert rows[-1] == (second, None)


def test_outline_drift_threshold_and_winner_uniqueness() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    conn.commit()
    repo = OutlineRepository(conn)

    high = cjk_bigram_overlap("她走进档案室发现钥匙", "她走进档案室发现钥匙")
    low = cjk_bigram_overlap("她走进档案室发现钥匙", "城市雨夜无人回头")
    assert high == 1.0
    assert low < 0.2
    assert is_drift_rejected(low, 0.2) is True

    outline_a = repo.add_outline(int(ids["shot_contract_id"]), "outline a", high)
    outline_b = repo.add_outline(int(ids["shot_contract_id"]), "outline b", high)
    repo.select_winner(int(ids["shot_contract_id"]), outline_a)
    repo.select_winner(int(ids["shot_contract_id"]), outline_b)

    rows = conn.execute(
        "SELECT outline_id FROM writing_outline_specs WHERE shot_contract_id = ? AND is_winner = 1",
        (ids["shot_contract_id"],),
    ).fetchall()
    assert rows == [(outline_b,)]


def test_outline_drift_score_is_source_coverage_not_length_penalized_jaccard() -> None:
    source = "许怀山检查第十七批密封件微裂纹"
    detailed = (
        "承接上一章门外脚步停住的悬念。许怀山检查第十七批密封件微裂纹，"
        "先核对湿热记录，再把裂纹位置、批号和温度逐项写入工艺卡。"
        "最后让门外来人停在白灯照不到的位置。"
    )

    score = cjk_bigram_overlap(source, detailed)

    assert score == 1.0


def test_enhanced_chapter_contract_preserves_pressure_deadline_and_parallel_actions() -> None:
    chapter = parse_outline(
        """### 第1章：第十七批
> **追读类型**：追查型 | **主引擎**：预埋种植
- **产出物**：第十七批
- **场景**：1979年4月，军工配套厂。许怀山在车间抽检
- **压力来源**：前线补给催产
- **明确期限**：下午三点前发车
- **并行动作**：硫化、抽检、钉箱和湿热追踪同时进行
- **冲突**：试验未完但流程允许放行
- **不可逆选择**：签字后卡车立即离厂
- **责任轨迹**：工艺卡到封条再到司机接货
- **工业因果桥**：老师傅向新工人说明密封失效如何影响弹药
- **信息延迟**：正式哑弹反馈尚未到厂
- **目标感受**：快生产、慢追责
- **叙事速度**：快
- **未来义务**：不得提前调查事故
- **去重硬门**：只签字一次
- **章末钩子**：货已走，试验仍在跑
"""
    )[0]

    shot = to_shot_contract_dict(chapter)
    joined_beats = "\n".join(shot["must_land"]["beats"])
    assert "前线补给催产" in joined_beats
    assert "下午三点前发车" in joined_beats
    assert "同时进行" in joined_beats
    assert "老师傅" in joined_beats
    assert "签字后卡车立即离厂" in shot["must_land"]["events"]
    assert "正式哑弹反馈尚未到厂" in shot["must_land"]["information_releases"]
    assert any("不得提前调查事故" in item for item in shot["anti_write"]["forbidden_facts"])

    chapter_payload = to_chapter_contract_payload(chapter)
    assert chapter_payload["pressure_source"] == "前线补给催产"
    assert chapter_payload["deadline"] == "下午三点前发车"
    assert chapter_payload["narrative_speed"] == "快"


def test_outline_orchestrator_generates_minimum_eligible_outlines_and_selects_winner() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_chinese_contract_children(conn, int(ids["shot_contract_id"]))
    conn.execute("UPDATE writing_projects SET min_eligible_outlines = 2, outline_drift_threshold = 0.20")
    conn.commit()
    provider = SequenceProvider(
        [
            "城市雨夜无人回头",
            "她走进档案室发现钥匙门外脚步",
            "她走进档案室发现钥匙门外脚步并关上灯",
        ]
    )
    orchestrator = OutlineOrchestrator(conn, LLMGateway(conn, provider=provider))

    winner = orchestrator.evaluate_and_select(str(ids["shot_id"]), int(ids["run_id"]))

    assert winner.is_winner is True
    assert winner.drift_score >= 0.20
    status = conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0]
    assert status == "outline_confirmed"
    assert conn.execute("SELECT count(*) FROM writing_ai_call_attempts WHERE call_type = 'outline'").fetchone()[0] == 3
    rows = conn.execute(
        """
        SELECT count(*), sum(CASE WHEN drift_score < 0.20 THEN 1 ELSE 0 END)
        FROM writing_outline_specs
        WHERE shot_contract_id = ?
        """,
        (ids["shot_contract_id"],),
    ).fetchone()
    assert rows == (3, 1)
    assert provider.calls == [
        ("writer-a", "outline:shot-001@20:20:1"),
        ("writer-b", "outline:shot-001@20:20:2"),
        ("writer-c", "outline:shot-001@20:20:3"),
    ]


def test_outline_orchestrator_entrypoint_signature_lints_clean() -> None:
    from ink.pipeline import outline_orchestrator

    source = outline_orchestrator.__loader__.get_source(outline_orchestrator.__name__)
    assert lint_shot_orchestrator_source(source, "outline_orchestrator.py") == []


def test_pre_drafting_orchestrator_runs_m2_pipeline_until_prompt_compiled() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_chinese_contract_children(conn, int(ids["shot_contract_id"]))
    conn.commit()
    provider = SequenceProvider(
        [
            "她走进档案室发现钥匙门外脚步",
            "她走进档案室发现钥匙门外脚步并关上灯",
        ]
    )
    orchestrator = PreDraftingOrchestrator(conn, LLMGateway(conn, provider=provider))

    prompt = orchestrator.run_until_prompt_compiled(str(ids["shot_id"]), int(ids["run_id"]))

    status = conn.execute("SELECT status FROM writing_shots WHERE shot_id = ?", (ids["shot_id"],)).fetchone()[0]
    assert status == "prompt_compiled"
    assert prompt.persona == "悬疑官"
    assert "发现钥匙" in prompt.full_prompt_text
    snapshot = conn.execute(
        """
        SELECT prompt_id, upstream_revision_ids, context_payload
        FROM writing_context_snapshots
        WHERE shot_id = ?
        """,
        (ids["shot_id"],),
    ).fetchone()
    assert snapshot[0] == prompt.prompt_id
    assert json.loads(snapshot[1]) == []
    payload = json.loads(snapshot[2])
    assert payload["persona"] == "悬疑官"
    assert payload["relaxed_soft"] is False
    assert {item["field"] for item in payload["clipped_items"]} >= {"voice_samples", "target_reader"}
    current_task_cards = conn.execute(
        """
        SELECT count(*)
        FROM writing_shot_task_cards
        WHERE shot_contract_id = ? AND superseded_at IS NULL
        """,
        (ids["shot_contract_id"],),
    ).fetchone()[0]
    assert current_task_cards == 1


def test_resume_rerun_prompt_supersedes_previous_prompt_snapshot() -> None:
    conn = make_schema_db()
    ids = insert_minimal_draft(conn)
    insert_chinese_contract_children(conn, int(ids["shot_contract_id"]))
    conn.commit()
    provider = SequenceProvider(
        [
            "她走进档案室发现钥匙门外脚步",
            "她走进档案室发现钥匙门外脚步并关上灯",
        ]
    )
    orchestrator = PreDraftingOrchestrator(conn, LLMGateway(conn, provider=provider))
    first_prompt = orchestrator.run_until_prompt_compiled(str(ids["shot_id"]), int(ids["run_id"]))

    from ink.core.resume import ResumeManager

    result = ResumeManager(conn).execute_resume_action(
        str(ids["shot_id"]),
        int(ids["run_id"]),
        "rerun_prompt",
        orchestrator.resume_handlers(),
    )

    assert result.prompt_id != first_prompt.prompt_id
    rows = conn.execute(
        """
        SELECT prompt_id, superseded_at
        FROM writing_prompt_snapshots
        WHERE task_card_id = ? AND persona = '悬疑官'
        ORDER BY prompt_id
        """,
        (first_prompt.task_card_id,),
    ).fetchall()
    assert rows == [(first_prompt.prompt_id, rows[0][1]), (result.prompt_id, None)]
    assert rows[0][1] is not None


class SequenceProvider:
    def __init__(self, responses: list[str]) -> None:
        self.responses = responses
        self.calls: list[tuple[str, str]] = []

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.calls.append((model_name, idempotency_key))
        return ModelResult(
            text=self.responses.pop(0),
            model_name=model_name,
            token_input=len(prompt_text.split()),
            token_output=1,
        )


def insert_contract_children(conn, shot_contract_id: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_shot_must_land
            (shot_contract_id, events, beats, information_releases)
        VALUES (?, ?, ?, ?)
        """,
        (
            shot_contract_id,
            json.dumps(["enter room"]),
            json.dumps(["beat one"]),
            json.dumps(["key reveal"]),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_anti_write
            (shot_contract_id, forbidden_facts, forbidden_words, pov_only)
        VALUES (?, ?, ?, ?)
        """,
        (shot_contract_id, json.dumps([]), json.dumps(["突然"]), json.dumps(["A"])),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_scene_contract
            (shot_contract_id, location, time_of_day, characters_present, character_positions)
        VALUES (?, 'archive', 'night', ?, ?)
        """,
        (shot_contract_id, json.dumps(["A"]), json.dumps({"A": "door"})),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_persona_assignment
            (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot)
        VALUES (?, '意象师', ?, 0, 1)
        """,
        (
            shot_contract_id,
            json.dumps({"画面": 8, "节奏": 5, "对话": 3, "结构": 6, "悬疑": 6}, ensure_ascii=False),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_soft_constraints
            (shot_contract_id, relaxable_rules, deviation_budget)
        VALUES (?, ?, 0.2)
        """,
        (shot_contract_id, json.dumps(["metaphor"])),
    )


def insert_chinese_contract_children(conn, shot_contract_id: int) -> None:
    conn.execute(
        """
        INSERT INTO writing_shot_must_land
            (shot_contract_id, events, beats, information_releases)
        VALUES (?, ?, ?, ?)
        """,
        (
            shot_contract_id,
            json.dumps(["她走进档案室"]),
            json.dumps(["发现钥匙"]),
            json.dumps(["门外脚步"]),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_anti_write
            (shot_contract_id, forbidden_facts, forbidden_words, pov_only)
        VALUES (?, ?, ?, ?)
        """,
        (shot_contract_id, json.dumps([]), json.dumps(["突然"]), json.dumps(["她"])),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_scene_contract
            (shot_contract_id, location, time_of_day, characters_present, character_positions)
        VALUES (?, '档案室', '夜晚', ?, ?)
        """,
        (shot_contract_id, json.dumps(["她"]), json.dumps({"她": "门边"}, ensure_ascii=False)),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_persona_assignment
            (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot)
        VALUES (?, '悬疑官', ?, 0, 1)
        """,
        (
            shot_contract_id,
            json.dumps({"画面": 7, "节奏": 6, "对话": 3, "结构": 6, "悬疑": 8}, ensure_ascii=False),
        ),
    )
    conn.execute(
        """
        INSERT INTO writing_shot_soft_constraints
            (shot_contract_id, relaxable_rules, deviation_budget)
        VALUES (?, ?, 0.2)
        """,
        (shot_contract_id, json.dumps(["metaphor"])),
    )

