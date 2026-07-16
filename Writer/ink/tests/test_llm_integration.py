"""LLMExtractionAdapter 集成测试。

使用 _ScriptedProvider（MockProvider 风格）模拟 LLM 响应。
"""
from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from factories import make_schema_db
from ink.core.llm_gateway import LLMGateway, ModelProvider, ModelResult
from ink.source_normalizer import LLMExtractionAdapter, SourceNormalizer


FIXTURE_DIR = Path(__file__).parent / "fixtures"


class _ScriptedProvider:
    """返回预设响应的 provider。"""

    def __init__(self, responses: list[str]) -> None:
        self._responses = list(responses)
        self.calls: list[tuple[str, str]] = []  # (prompt, model)

    def complete(self, prompt_text: str, model_name: str, idempotency_key: str) -> ModelResult:
        self.calls.append((prompt_text, model_name))
        if not self._responses:
            return ModelResult(text="[]", token_input=0, token_output=0, model_name=model_name)
        return ModelResult(
            text=self._responses.pop(0),
            token_input=10,
            token_output=32,
            model_name=model_name,
        )


@pytest.fixture
def fixture_response() -> str:
    return (FIXTURE_DIR / "llm_extraction_response.json").read_text(encoding="utf-8")


class TestLLMExtractionAdapter:
    """LLMExtractionAdapter 测试。"""

    def test_parse_response_json_array(self, fixture_response: str) -> None:
        """解析标准 JSON 数组响应。"""
        clauses = LLMExtractionAdapter._parse_response(fixture_response)
        assert len(clauses) == 4
        assert clauses[0]["scope_type"] == "book"
        assert clauses[0]["clause_type"] == "style"
        assert clauses[1]["severity"] == "hard"
        assert clauses[2]["scope_id"] == "ch-1"

    def test_parse_response_strips_markdown_fence(self) -> None:
        """解析带 markdown 代码块的响应。"""
        text = '```json\n[{"scope_type":"book","clause_text":"rule"}]\n```'
        clauses = LLMExtractionAdapter._parse_response(text)
        assert len(clauses) == 1
        assert clauses[0]["clause_text"] == "rule"

    def test_parse_response_empty_array(self) -> None:
        """空数组返回空列表。"""
        assert LLMExtractionAdapter._parse_response("[]") == []

    def test_parse_response_invalid_json_returns_empty(self) -> None:
        """无效 JSON 返回空列表。"""
        assert LLMExtractionAdapter._parse_response("not json at all") == []

    def test_parse_response_non_array_returns_empty(self) -> None:
        """非数组 JSON 返回空列表。"""
        assert LLMExtractionAdapter._parse_response('{"key":"value"}') == []

    def test_adapter_calls_gateway_and_parses(self, fixture_response: str) -> None:
        """适配器调用 gateway 并解析响应。"""
        conn = make_schema_db()
        conn.execute(
            """
            INSERT INTO writing_projects
                (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
            VALUES (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
                    '["judge-a","judge-b","judge-c","judge-d","judge-e"]', '2026-01-01T00:00:00Z')
            """
        )
        provider = _ScriptedProvider([fixture_response])
        gateway = LLMGateway(conn, provider=provider)
        adapter = LLMExtractionAdapter(gateway, model_name="test-model", project_id=1)

        clauses = adapter("# Guide\nUse short sentences. Protagonist never lies.", "guide.md")
        assert len(clauses) == 4
        assert len(provider.calls) == 1
        assert "test-model" in provider.calls[0][1]

    def test_adapter_idempotent_key_from_content(self) -> None:
        """相同内容生成相同幂等 key。"""
        conn = make_schema_db()
        conn.execute(
            """
            INSERT INTO writing_projects
                (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
            VALUES (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
                    '["judge-a","judge-b","judge-c","judge-d","judge-e"]', '2026-01-01T00:00:00Z')
            """
        )
        provider = _ScriptedProvider(["[]", "[]"])
        gateway = LLMGateway(conn, provider=provider)
        adapter = LLMExtractionAdapter(gateway, project_id=1)

        adapter("content_a", "file_a.md")
        adapter("content_b", "file_b.md")
        # 不同内容生成不同幂等 key，两次调用都成功
        assert len(provider.calls) == 2


class TestSourceNormalizerWithLLM:
    """SourceNormalizer + LLM 集成测试。"""

    def test_normalize_with_llm_adapter(self, fixture_response: str) -> None:
        """用 LLMExtractionAdapter 抽取 clauses。"""
        conn = make_schema_db()
        # 创建项目
        conn.execute(
            """
            INSERT INTO writing_projects
                (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
            VALUES (1, 'demo', 'Demo', '["writer-a","writer-b","writer-c"]',
                    '["judge-a","judge-b","judge-c","judge-d","judge-e"]', '2026-01-01T00:00:00Z')
            """
        )

        provider = _ScriptedProvider([fixture_response])
        gateway = LLMGateway(conn, provider=provider)
        adapter = LLMExtractionAdapter(gateway, model_name="test-model", project_id=1)

        # 写入临时指南文件
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            guide = Path(tmpdir) / "writing_guide.md"
            guide.write_text("# Guide\nProtagonist never lies.", encoding="utf-8")

            normalizer = SourceNormalizer(conn, extraction_fn=adapter)
            result = normalizer.normalize_source_directory(
                project_id=1,
                source_directory=tmpdir,
            )

        assert len(result.registered_source_ids) == 1
        assert len(result.extracted_clause_ids) == 4
        assert len(provider.calls) == 1
