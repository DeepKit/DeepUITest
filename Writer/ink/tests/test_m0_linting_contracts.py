from __future__ import annotations

from pathlib import Path

from ink.linting.llm_access import lint_llm_access
from ink.linting.sql_access import lint_sql_access
from ink.linting.state_update import lint_state_updates


def codes(violations) -> set[str]:
    return {violation.code for violation in violations}


def test_sql_access_lint_allows_text_repository_and_blocks_other_revision_access() -> None:
    source = "conn.execute('SELECT text FROM writing_shot_revisions WHERE shot_id=?', (shot_id,))"

    assert lint_sql_access(source, "src/ink/core/text_repository.py") == []
    assert codes(lint_sql_access(source, "src/ink/pipeline/writer.py")) == {"TEXT_REVISIONS_ACCESS"}


def test_sql_access_lint_blocks_f_string_sql_dynamic_sql_and_orm_revision_query() -> None:
    fstring_source = "conn.execute(f'SELECT * FROM writing_{table}')"
    dynamic_source = "conn.execute('SELECT * FROM writing_' + table)"
    orm_source = "session.query(WritingShotRevision).all()"

    assert codes(lint_sql_access(fstring_source, "src/ink/pipeline/writer.py")) == {"STRING_CONCATENATED_SQL"}
    assert codes(lint_sql_access(dynamic_source, "src/ink/pipeline/writer.py")) == {"DYNAMIC_TABLE_NAME"}
    assert codes(lint_sql_access(orm_source, "src/ink/pipeline/writer.py")) == {"ORM_ACCESS"}


def test_sql_access_lint_blocks_scene_first_authority_access_outside_repositories() -> None:
    source = "conn.execute('UPDATE writing_chapter_heads SET version = version + 1')"

    assert codes(lint_sql_access(source, "src/ink/cli.py")) == {
        "SCENE_FIRST_AUTHORITY_WRITE"
    }
    assert lint_sql_access(
        source, "src/ink/core/chapter_snapshot_repository.py"
    ) == []


def test_production_source_has_no_scene_first_authority_sql_bypasses() -> None:
    root = Path(__file__).resolve().parents[1]
    violations = []
    for path in (root / "src" / "ink").rglob("*.py"):
        relative = path.relative_to(root).as_posix()
        for violation in lint_sql_access(path.read_text(encoding="utf-8"), relative):
            if violation.code == "SCENE_FIRST_AUTHORITY_WRITE":
                violations.append(f"{relative}:{violation.line}: {violation.message}")

    assert violations == []


def test_state_update_lint_allows_state_machine_only() -> None:
    source = "conn.execute('UPDATE writing_shots SET status=? WHERE shot_id=?', (status, shot_id))"

    assert lint_state_updates(source, "src/ink/core/state_machine.py") == []
    assert codes(lint_state_updates(source, "src/ink/pipeline/gate_orchestrator.py")) == {
        "DIRECT_SHOT_STATUS_UPDATE"
    }


def test_llm_access_lint_allows_gateway_only() -> None:
    source = "import openai\nfrom anthropic import Anthropic\n"

    assert lint_llm_access(source, "src/ink/core/llm_gateway.py") == []
    assert codes(lint_llm_access(source, "src/ink/writers/quad_dispatcher.py")) == {
        "DIRECT_LLM_SDK_IMPORT"
    }
