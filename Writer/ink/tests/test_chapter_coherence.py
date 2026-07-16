from __future__ import annotations

import pytest

from ink.core.chapter_coherence import compare_chapter_texts, evaluate_chapter_overlap
from factories import make_schema_db


def test_compare_chapter_texts_exposes_repeated_scene_tokens() -> None:
    overlaps = compare_chapter_texts(
        "硫化车间 夜班 电铃响起 许怀山 检查压力表",
        [(1, "硫化车间 夜班 电铃响起 许怀山 走向压力表")],
    )

    assert overlaps[0].chapter_id == 1
    assert overlaps[0].score >= 0.5
    assert "硫化车间" in overlaps[0].shared_tokens
    assert "许怀山" in overlaps[0].shared_tokens


def test_compare_chapter_texts_keeps_distinct_chapter_below_threshold() -> None:
    overlaps = compare_chapter_texts(
        "吕素琴 清晨 档案室 拆开蓝色信封",
        [(1, "硫化车间 夜班 电铃响起 许怀山 检查压力表")],
    )

    assert overlaps[0].score == 0.0
    assert overlaps[0].shared_tokens == ()


def test_evaluate_chapter_overlap_without_previous_snapshot_passes() -> None:
    result = evaluate_chapter_overlap(
        make_schema_db(),
        project_id=1,
        chapter_id=1,
        candidate_text="硫化车间 夜班 电铃响起",
    )

    assert result.passed is True
    assert result.overlaps == ()


def test_evaluate_chapter_overlap_rejects_invalid_threshold() -> None:
    with pytest.raises(ValueError, match="threshold"):
        evaluate_chapter_overlap(
            make_schema_db(),
            project_id=1,
            chapter_id=2,
            candidate_text="text",
            threshold=1.1,
        )


def test_evaluate_chapter_overlap_reads_only_sealed_active_snapshots(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'coherence', 'Coherence', '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c"]', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_generation_rounds
            (generation_round_id, project_id, chapter_id, round_number, status,
             created_at, updated_at)
        VALUES
            (11, 1, 1, 1, 'selected', '2026-07-15T00:00:00Z', '2026-07-15T00:00:00Z'),
            (12, 1, 2, 1, 'selected', '2026-07-15T00:00:00Z', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_candidate_branches
            (branch_id, generation_round_id, candidate_index, writer_model,
             generation_strategy, status, created_at)
        VALUES
            (21, 11, 1, 'writer-a', 'test', 'selected', '2026-07-15T00:00:00Z'),
            (22, 12, 1, 'writer-a', 'test', 'selected', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_candidate_branch_versions
            (branch_version_id, branch_id, version, status, content_hash, created_at)
        VALUES
            (31, 21, 1, 'frozen', 'hash-1', '2026-07-15T00:00:00Z'),
            (32, 22, 1, 'frozen', 'hash-2', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_snapshots
            (snapshot_id, project_id, chapter_id, source_branch_version_id,
             snapshot_hash, created_at, sealed_at)
        VALUES
            (41, 1, 1, 31, 'snapshot-1', '2026-07-15T00:00:00Z', '2026-07-15T00:01:00Z'),
            (42, 1, 2, 32, 'snapshot-2', '2026-07-15T00:00:00Z', NULL)
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_heads
            (project_id, chapter_id, active_snapshot_id, version, updated_at)
        VALUES (1, 1, 41, 1, '2026-07-15T00:01:00Z')
        """
    )
    calls: list[int] = []

    def _read_active(self, *, project_id: int, chapter_id: int) -> str:
        calls.append(chapter_id)
        return "硫化车间 夜班 电铃响起 许怀山 检查压力表"

    monkeypatch.setattr(
        "ink.core.chapter_coherence.ChapterSnapshotRepository.read_active_chapter_text",
        _read_active,
    )

    result = evaluate_chapter_overlap(
        conn,
        project_id=1,
        chapter_id=3,
        candidate_text="硫化车间 夜班 电铃响起 许怀山 走向压力表",
    )

    assert calls == [1]
    assert [item.chapter_id for item in result.overlaps] == [1]
    assert result.passed is False


def test_evaluate_chapter_overlap_ignores_non_active_sealed_snapshot(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool, created_at)
        VALUES (1, 'coherence', 'Coherence', '["writer-a","writer-b","writer-c"]',
                '["judge-a","judge-b","judge-c"]', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_generation_rounds
            (generation_round_id, project_id, chapter_id, round_number, status,
             created_at, updated_at)
        VALUES
            (11, 1, 1, 1, 'selected', '2026-07-15T00:00:00Z', '2026-07-15T00:00:00Z'),
            (12, 1, 1, 2, 'selected', '2026-07-15T00:00:00Z', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_candidate_branches
            (branch_id, generation_round_id, candidate_index, writer_model,
             generation_strategy, status, created_at)
        VALUES
            (21, 11, 1, 'writer-a', 'old', 'selected', '2026-07-15T00:00:00Z'),
            (22, 12, 1, 'writer-b', 'active', 'selected', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_candidate_branch_versions
            (branch_version_id, branch_id, version, status, content_hash, created_at)
        VALUES
            (31, 21, 1, 'frozen', 'hash-old', '2026-07-15T00:00:00Z'),
            (32, 22, 1, 'frozen', 'hash-active', '2026-07-15T00:00:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_snapshots
            (snapshot_id, project_id, chapter_id, source_branch_version_id,
             snapshot_hash, created_at, sealed_at)
        VALUES
            (41, 1, 1, 31, 'snapshot-old', '2026-07-15T00:00:00Z', '2026-07-15T00:01:00Z'),
            (42, 1, 1, 32, 'snapshot-active', '2026-07-15T00:00:00Z', '2026-07-15T00:02:00Z')
        """
    )
    conn.execute(
        """
        INSERT INTO writing_chapter_heads
            (project_id, chapter_id, active_snapshot_id, version, updated_at)
        VALUES (1, 1, 42, 2, '2026-07-15T00:01:00Z')
        """
    )
    calls: list[int] = []

    def _read_active(self, *, project_id: int, chapter_id: int) -> str:
        calls.append(chapter_id)
        return "当前封版 独有内容"

    monkeypatch.setattr(
        "ink.core.chapter_coherence.ChapterSnapshotRepository.read_active_chapter_text",
        _read_active,
    )

    result = evaluate_chapter_overlap(
        conn,
        project_id=1,
        chapter_id=2,
        candidate_text="旧封版 重复内容",
    )

    assert calls == [1]
    assert len(result.overlaps) == 1
    assert result.overlaps[0].chapter_id == 1
    assert result.overlaps[0].score == 0.0
    assert result.passed is True
