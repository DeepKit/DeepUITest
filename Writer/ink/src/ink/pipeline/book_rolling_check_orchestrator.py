from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

from ink.core.llm_gateway import LLMGateway
from ink.core.text_repository import TextRepository
from ink.errors import DataIntegrityError, LLMProviderError
from ink.time import now_utc_iso


BOOK_CHECK_DIMENSIONS = (
    "longline_suspense_closure",
    "character_arc_completeness",
    "motif_echo_density",
    "theme_sublimation",
    "global_rhythm_curve",
    "foreshadow_recovery",
)

_BOOK_CHECK_DIM_LABELS = {
    "longline_suspense_closure": "长线悬念闭环（跨章主线悬念是否在区间内闭环/推进）",
    "character_arc_completeness": "角色弧光完整（主角弧光在区间内的推进度）",
    "motif_echo_density": "母题回响密度（核心母题在区间的回响次数与质量）",
    "theme_sublimation": "主题升华（主题在区间的递进与升华）",
    "global_rhythm_curve": "全书节奏曲线（区间整体张弛曲线是否合理）",
    "foreshadow_recovery": "伏笔回收（已埋伏笔在区间的回收情况）",
}


class BookCheckLLMFailure(Exception):
    """book_check 的 LLM 调用三 tier 全失败（供应商故障），不写假分。"""


@dataclass(frozen=True)
class BookCheckResult:
    check_run_id: int
    project_id: int
    chapter_range_start: int
    chapter_range_end: int
    blocking_issue_count: int
    quality_gate_passed: bool


class BookRollingCheckOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway) -> None:
        self.conn = conn
        self.gateway = gateway

    def run_if_due(self, project_id: int, up_to_chapter: int) -> BookCheckResult | None:
        interval = _rolling_interval(self.conn, project_id)
        if up_to_chapter % interval != 0:
            return None

        existing = _load_check_for_chapter(self.conn, project_id, up_to_chapter)
        if existing is not None:
            return existing

        last_end = _last_checked_chapter(self.conn, project_id)
        chapter_range_start = 1 if last_end is None else last_end + 1
        texts = _load_accepted_texts(self.conn, project_id, up_to_chapter)
        if not texts:
            raise DataIntegrityError(f"no accepted text available for book check: {project_id}/{up_to_chapter}")

        scores, issues = self._evaluate(
            project_id=project_id,
            chapter_range_start=chapter_range_start,
            chapter_range_end=up_to_chapter,
            texts=texts,
        )
        blocking_count = sum(1 for issue in issues if str(issue.get("severity")) == "blocking")
        check_run_id = _insert_book_check(
            self.conn,
            project_id=project_id,
            chapter_range_start=chapter_range_start,
            chapter_range_end=up_to_chapter,
            scores=scores,
            issues=issues,
            blocking_count=blocking_count,
            is_incremental=0 if last_end is None else 1,
        )
        return BookCheckResult(
            check_run_id=check_run_id,
            project_id=project_id,
            chapter_range_start=chapter_range_start,
            chapter_range_end=up_to_chapter,
            blocking_issue_count=blocking_count,
            quality_gate_passed=blocking_count == 0,
        )

    def _evaluate(
        self,
        *,
        project_id: int,
        chapter_range_start: int,
        chapter_range_end: int,
        texts: list[str],
    ) -> tuple[dict[str, float], list[dict[str, object]]]:
        """单次真实调 gateway（call_type=book_check）→ 解析 6 维分 + issues list。

        gateway 内部已做主/备/兜底 failover。解析失败抛 ``LLMProviderError`` 交 gateway 换 tier
        重试；三 tier 全失败 gateway 逃出 ``LLMProviderError`` → 包成 ``BookCheckLLMFailure``
        抛出（不写假分）。
        """
        sequence = _next_sequence(self.conn, project_id)
        prompt_text = _book_check_prompt(texts, chapter_range_start, chapter_range_end)
        idem = f"book_check:{project_id}:{chapter_range_end}:{sequence}"
        try:
            result = self.gateway.call(
                project_id=project_id,
                shot_id=None,
                run_id=None,
                call_type="book_check",
                prompt_id=None,
                prompt_text=prompt_text,
                model_name=None,
                idempotency_key=idem,
                tier_hint="primary",
            )
        except LLMProviderError as exc:
            raise BookCheckLLMFailure(
                "book_check 评分 LLM 调用失败（三 tier 全失败），疑似供应商故障；"
                "请检查 role-config 主/备/兜底三档 api-key 与 base_url（call_type=book_check）"
            ) from exc
        return _parse_book_scores(result.text)


def has_blocking_issues(conn: sqlite3.Connection, project_id: int) -> bool:
    row = conn.execute(
        """
        SELECT blocking_issue_count
        FROM writing_book_check_results
        WHERE project_id = ?
        ORDER BY check_run_id DESC
        LIMIT 1
        """,
        (project_id,),
    ).fetchone()
    return row is not None and int(row[0]) > 0


def _rolling_interval(conn: sqlite3.Connection, project_id: int) -> int:
    row = conn.execute(
        "SELECT chapter_rolling_check_interval FROM writing_projects WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"project not found: {project_id}")
    return max(1, int(row[0]))


def _load_check_for_chapter(conn: sqlite3.Connection, project_id: int, up_to_chapter: int) -> BookCheckResult | None:
    row = conn.execute(
        """
        SELECT check_run_id, chapter_range_start, chapter_range_end, blocking_issue_count, quality_gate_passed
        FROM writing_book_check_results
        WHERE project_id = ? AND chapter_range_end = ?
        ORDER BY check_run_id DESC
        LIMIT 1
        """,
        (project_id, up_to_chapter),
    ).fetchone()
    if row is None:
        return None
    return BookCheckResult(
        check_run_id=int(row[0]),
        project_id=project_id,
        chapter_range_start=int(row[1]),
        chapter_range_end=int(row[2]),
        blocking_issue_count=int(row[3]),
        quality_gate_passed=bool(row[4]),
    )


def _last_checked_chapter(conn: sqlite3.Connection, project_id: int) -> int | None:
    row = conn.execute(
        "SELECT max(chapter_range_end) FROM writing_book_check_results WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    return None if row is None or row[0] is None else int(row[0])


def _load_accepted_texts(conn: sqlite3.Connection, project_id: int, up_to_chapter: int) -> list[str]:
    rows = conn.execute(
        """
        SELECT s.shot_id, s.run_id
        FROM writing_chapter_reviews r
        JOIN writing_shots s
          ON s.project_id = r.project_id
         AND s.chapter_id = r.chapter_id
         AND s.run_id = r.run_id
        WHERE r.project_id = ?
          AND r.chapter_id <= ?
          AND r.status = 'accepted'
          AND s.status = 'hard_sealed'
        ORDER BY r.chapter_id, s.logical_shot_id
        """,
        (project_id, up_to_chapter),
    ).fetchall()
    repo = TextRepository(conn)
    return [repo.read_current_text(str(row[0]), int(row[1])) for row in rows]


def _book_check_prompt(texts: list[str], chapter_range_start: int, chapter_range_end: int) -> str:
    """构造篇级检测 prompt：注入已 accept 章文本区间 + 6 维定义 + JSON 输出（分 + issues）。"""
    dims_block = "\n".join(
        f'  "{col}": <0-100 整数>  // {label}' for col, label in _BOOK_CHECK_DIM_LABELS.items()
    )
    body = "\n\n".join(texts)
    return (
        "你是小说篇级滚动检测。审视第 "
        f"{chapter_range_start}-{chapter_range_end} 章已定稿文本，给出全书级 6 维检测分与问题清单。\n\n"
        f"## 区间文本\n{body}\n\n"
        f"## 检测维度（共 6 维，每维 0-100 整数）\n{dims_block}\n\n"
        "## 输出要求\n"
        "严格输出一个 JSON 对象，含上述 6 个维度键（值为 0-100 整数）外加一个 \"issues\" 数组键。"
        "issues 每项含 severity（'blocking' 或 'warning'）、code（短代号）、chapter_range_end（本区间末章号）、"
        "detail（简述）。无问题则 issues 为空数组。不要任何额外文本、不要 markdown 代码围栏。示例：\n"
        '{"longline_suspense_closure": 78, "character_arc_completeness": 85, "motif_echo_density": 80, '
        '"theme_sublimation": 82, "global_rhythm_curve": 86, "foreshadow_recovery": 70, '
        '"issues": [{"severity": "warning", "code": "foreshadow_unrecovered", "chapter_range_end": 6, '
        '"detail": "第 2 章埋的伏笔尚未回收"}]}'
    )


def _parse_book_scores(text: str) -> tuple[dict[str, float], list[dict[str, object]]]:
    """解析检测返回的 6 维分 + issues list。

    容错：非 JSON / 缺维 / 越界 → 抛 ``LLMProviderError``（交 gateway failover 换 tier 重试）。
    issues 缺失或非数组回退为空（不视为硬失败）。
    """
    raw = text.strip()
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise LLMProviderError("book_check 评分非 JSON：未找到 JSON 对象边界")
    try:
        obj = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as exc:
        raise LLMProviderError(f"book_check 评分 JSON 解析失败：{exc}") from exc
    scores: dict[str, float] = {}
    for col in BOOK_CHECK_DIMENSIONS:
        if col not in obj:
            raise LLMProviderError(f"book_check 评分缺维度：{col}")
        val = obj[col]
        if not isinstance(val, (int, float)) or isinstance(val, bool):
            raise LLMProviderError(f"book_check 评分维度 {col} 非数值：{val!r}")
        iv = int(val)
        if iv < 0 or iv > 100:
            raise LLMProviderError(f"book_check 评分维度 {col} 越界(0-100)：{iv}")
        scores[col] = float(iv)
    issues_val = obj.get("issues", [])
    if not isinstance(issues_val, list):
        issues_val = []
    issues: list[dict[str, object]] = []
    for item in issues_val:
        if isinstance(item, dict):
            issues.append({str(k): v for k, v in item.items()})
    return scores, issues


def _insert_book_check(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    chapter_range_start: int,
    chapter_range_end: int,
    scores: dict[str, float],
    issues: list[dict[str, object]],
    blocking_count: int,
    is_incremental: int,
) -> int:
    sequence = _next_sequence(conn, project_id)
    # 重检（同区间再次 run_if_due 前已有 stale 传播触发重算）时清旧 book_check attempt 行：
    # writing_ai_call_attempts.idempotency_key 全局 UNIQUE，重调用同 key 会撞 UNIQUE。
    conn.execute(
        "DELETE FROM writing_ai_call_attempts WHERE call_type = 'book_check' AND idempotency_key = ?",
        (f"book_check:{project_id}:{chapter_range_end}:{sequence}",),
    )
    cursor = conn.execute(
        """
        INSERT INTO writing_book_check_results
            (project_id, check_sequence, chapter_range_start, chapter_range_end,
             longline_suspense_closure, character_arc_completeness, motif_echo_density,
             theme_sublimation, global_rhythm_curve, foreshadow_recovery,
             is_incremental, issues, blocking_issue_count, quality_gate_passed, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            project_id,
            sequence,
            chapter_range_start,
            chapter_range_end,
            scores["longline_suspense_closure"],
            scores["character_arc_completeness"],
            scores["motif_echo_density"],
            scores["theme_sublimation"],
            scores["global_rhythm_curve"],
            scores["foreshadow_recovery"],
            is_incremental,
            json.dumps(issues, ensure_ascii=False, sort_keys=True),
            blocking_count,
            int(blocking_count == 0),
            now_utc_iso(),
        ),
    )
    return int(cursor.lastrowid)


def _next_sequence(conn: sqlite3.Connection, project_id: int) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(check_sequence), 0) + 1 FROM writing_book_check_results WHERE project_id = ?",
        (project_id,),
    ).fetchone()
    return int(row[0])
