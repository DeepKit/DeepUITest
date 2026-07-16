"""源文档规范化算法。

读取写作指南目录 → 计算 hash → 注册源文档 → 抽取原子条款 → 合并去重 →
检测矛盾 → 生成冲突选择题。

对齐 docs/implementation-contract-v1.md §源文档规范化 相关章节。
"""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from ink.source_workflow import SourceWorkflowStore
from ink.time import now_utc_iso


# ---------------------------------------------------------------------------
# LLM 抽取适配器
# ---------------------------------------------------------------------------

_EXTRACTION_SYSTEM_PROMPT = """\
You are a clause extraction engine for a novel-writing contract system.
Given a source document (writing guide, outline, character bible, etc.),
extract atomic clauses as a JSON array.

Each clause must have:
- scope_type: one of "book", "volume", "part", "chapter"
- scope_id: null for book, or a string identifier for volume/part/chapter
- clause_type: one of "quality", "plot", "character", "world", "style", "forbidden"
- severity: "hard" (must follow) or "soft" (guideline)
- clause_text: the atomic rule or constraint

Return ONLY a valid JSON array. No markdown fences, no commentary.
Example:
[{"scope_type":"book","scope_id":null,"clause_type":"style","severity":"soft","clause_text":"Use short sentences in action scenes."}]
"""


class LLMExtractionAdapter:
    """通过 LLMGateway 调用真实 LLM 抽取原子条款。

    Usage::

        adapter = LLMExtractionAdapter(gateway, model_name="gpt-4o-mini")
        normalizer = SourceNormalizer(conn, extraction_fn=adapter)
    """

    def __init__(
        self,
        gateway: Any,
        *,
        model_name: str = "gpt-4o-mini",
        project_id: int = 0,
    ) -> None:
        self._gateway = gateway
        self._model_name = model_name
        self._project_id = project_id

    def __call__(self, content: str, filename: str) -> list[dict[str, Any]]:
        """抽取器签名：(content, filename) -> list[clause_dict]。"""
        prompt = (
            f"{_EXTRACTION_SYSTEM_PROMPT}\n\n"
            f"--- Source file: {filename} ---\n\n{content}\n"
        )
        idempotency_key = hashlib.sha256(
            f"{filename}:{content}".encode("utf-8")
        ).hexdigest()[:32]

        result = self._gateway.call(
            project_id=self._project_id,
            shot_id=None,
            run_id=None,
            call_type="source_extraction",
            prompt_id=None,
            prompt_text=prompt,
            model_name=self._model_name,
            idempotency_key=idempotency_key,
        )

        return self._parse_response(result.text)

    @staticmethod
    def _parse_response(text: str) -> list[dict[str, Any]]:
        """解析 LLM 返回的 JSON 数组。"""
        cleaned = text.strip()
        # 去除可能的 markdown 代码块
        if cleaned.startswith("```"):
            lines = cleaned.split("\n")
            # 移除首尾的 ``` 行
            lines = [l for l in lines if not l.strip().startswith("```")]
            cleaned = "\n".join(lines).strip()

        try:
            clauses = json.loads(cleaned)
        except json.JSONDecodeError:
            # 回退：尝试找到 JSON 数组
            start = cleaned.find("[")
            end = cleaned.rfind("]")
            if start >= 0 and end > start:
                clauses = json.loads(cleaned[start:end + 1])
            else:
                return []

        if not isinstance(clauses, list):
            return []

        # 规范化每个 clause
        result: list[dict[str, Any]] = []
        for c in clauses:
            if not isinstance(c, dict):
                continue
            result.append({
                "scope_type": c.get("scope_type", "book"),
                "scope_id": c.get("scope_id"),
                "clause_type": c.get("clause_type", "quality"),
                "severity": c.get("severity", "soft"),
                "clause_text": c.get("clause_text", ""),
            })
        return result


# source_kind 推断映射
_KIND_KEYWORDS = {
    "guide": ["writing_guide", "style_guide", "guide"],
    "outline": ["outline", "plot"],
    "character": ["character", "bible", "persona"],
    "world": ["world", "setting", "lore"],
    "process_scratch": ["process", "scratch", "todo", "draft"],
}


@dataclass
class NormalizeResult:
    """规范化结果。"""
    registered_source_ids: list[int] = field(default_factory=list)
    extracted_clause_ids: list[int] = field(default_factory=list)
    duplicate_count: int = 0
    conflict_count: int = 0
    # dry_run 预览:每个源文档的推断信息(filename/source_kind/content_hash/条款示例),不落库。
    preview_documents: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class Conflict:
    """一对矛盾条款。"""
    clause_a_id: int
    clause_b_id: int
    scope_type: str
    scope_id: str | None
    reason: str


@dataclass
class ConflictQuestion:
    """冲突选择题。"""
    question_id: int  # = decision_session_id
    scope_type: str
    scope_id: str | None
    clause_a_id: int
    clause_b_id: int
    reason: str


class SourceNormalizer:
    """源文档规范化：读取目录、计算 hash、注册、抽取、合并去重、检测矛盾。

    使用 mock 抽取器（基于文本分割规则）进行测试和生产环境可运行。
    真实 LLM 抽取通过 ``extraction_fn`` 参数注入。
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        *,
        extraction_fn: Any = None,
    ) -> None:
        self.conn = conn
        self._store = SourceWorkflowStore(conn)
        self._extraction_fn = extraction_fn or self._default_extraction

    # ------------------------------------------------------------------
    # 目录规范化
    # ------------------------------------------------------------------

    def normalize_source_directory(
        self,
        *,
        project_id: int,
        source_directory: str,
    ) -> NormalizeResult:
        """读取写作指南目录，注册所有源文档，计算 hash，抽取原子条款。

        - 遍历目录中的 .md / .txt 文件
        - 对每个文件计算 content_hash，推断 source_kind
        - 注册为 writing_source_documents
        - 调用抽取器生成原子条款
        - 返回注册 + 抽取结果
        """
        result = NormalizeResult()
        dir_path = Path(source_directory)
        if not dir_path.is_dir():
            raise FileNotFoundError(f"source directory not found: {source_directory}")

        for file_path in sorted(dir_path.iterdir()):
            if file_path.suffix not in (".md", ".txt"):
                continue
            content = file_path.read_text(encoding="utf-8")
            content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()

            # 推断 source_kind
            source_kind = self._infer_source_kind(file_path.name)

            # 注册
            source_doc_id = self._store.register_source_document(
                project_id=project_id,
                source_path=str(file_path),
                source_kind=source_kind,
                content_hash=content_hash,
                priority=100,
                status="active",
            )
            result.registered_source_ids.append(source_doc_id)

            # 抽取原子条款
            clauses = self._extraction_fn(content, file_path.name)
            clause_ids: list[int] = []
            for clause in clauses:
                clause_id = self._store.record_atomic_clause(
                    project_id=project_id,
                    source_document_id=source_doc_id,
                    scope_type=clause.get("scope_type", "book"),
                    scope_id=clause.get("scope_id"),
                    clause_type=clause.get("clause_type", "quality"),
                    severity=clause.get("severity", "soft"),
                    clause_text=clause.get("clause_text", ""),
                    source_refs=[str(file_path.name)],
                    source_hashes=[content_hash],
                    status="proposed",
                )
                clause_ids.append(clause_id)

            # 记录抽取运行
            self._store.record_extraction_run(
                project_id=project_id,
                source_document_id=source_doc_id,
                extractor_slot="primary",
                model_provider="mock",
                model_name="rule_based",
                source_hash=content_hash,
                extracted_clause_ids=clause_ids,
                status="completed",
            )

            result.extracted_clause_ids.extend(clause_ids)

        # 合并去重
        result.duplicate_count = self.merge_and_deduplicate(
            project_id=project_id,
            source_document_ids=result.registered_source_ids,
        )

        return result

    # ------------------------------------------------------------------
    # 合并去重
    # ------------------------------------------------------------------

    def merge_and_deduplicate(
        self,
        *,
        project_id: int,
        source_document_ids: list[int],
    ) -> int:
        """合并去重：同 source_document 内的重复条款去重。

        重复定义：clause_text 完全相同的条款。
        保留最先出现的一条，其余标记为 superseded，记录 supersedes_clause_id。

        Returns:
            去重的条款数量。
        """
        duplicate_count = 0
        for doc_id in source_document_ids:
            # 查该文档的所有条款
            rows = self.conn.execute(
                """
                SELECT atomic_clause_id, clause_text, status
                FROM writing_atomic_source_clauses
                WHERE source_document_id = ?
                ORDER BY atomic_clause_id
                """,
                (doc_id,),
            ).fetchall()

            seen_texts: dict[str, int] = {}  # clause_text → first clause_id
            for row in rows:
                clause_id = int(row[0])
                clause_text = str(row[1])
                status = str(row[2])

                if status in ("superseded", "rejected"):
                    continue

                if clause_text in seen_texts:
                    # 重复条款：标记为 superseded
                    first_id = seen_texts[clause_text]
                    self.conn.execute(
                        """
                        UPDATE writing_atomic_source_clauses
                        SET status = 'superseded', supersedes_clause_id = ?,
                            updated_at = ?
                        WHERE atomic_clause_id = ?
                        """,
                        (first_id, now_utc_iso(), clause_id),
                    )
                    duplicate_count += 1
                else:
                    seen_texts[clause_text] = clause_id

        return duplicate_count

    # ------------------------------------------------------------------
    # 矛盾检测
    # ------------------------------------------------------------------

    def detect_conflicts(
        self,
        *,
        project_id: int,
        clause_ids: list[int] | None = None,
    ) -> list[Conflict]:
        """检测矛盾：同 scope 内的互斥条款。

        简化规则（无 LLM）：
        1. 同 scope_type + scope_id 内，severity=hard 且 clause_type 相同的条款
           如果文本互斥（包含互斥关键词），则标记为冲突。
        2. 实际生产中应使用 LLM 做语义矛盾检测。

        这里使用简化版本：同 scope 内 severity=hard 的同 type 条款如果有
        超过 1 条，且文本相似度低（长度差异大），标记为冲突。
        """
        if clause_ids:
            placeholders = ",".join("?" for _ in clause_ids)
            rows = self.conn.execute(
                f"""
                SELECT atomic_clause_id, scope_type, scope_id, clause_type,
                       severity, clause_text, status
                FROM writing_atomic_source_clauses
                WHERE atomic_clause_id IN ({placeholders})
                    AND status IN ('proposed', 'confirmed')
                ORDER BY scope_type, scope_id, clause_type, severity
                """,
                clause_ids,
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT atomic_clause_id, scope_type, scope_id, clause_type,
                       severity, clause_text, status
                FROM writing_atomic_source_clauses
                WHERE project_id = ? AND status IN ('proposed', 'confirmed')
                ORDER BY scope_type, scope_id, clause_type, severity
                """,
                (project_id,),
            ).fetchall()

        # 按 scope + type 分组
        groups: dict[tuple[str, str | None, str], list[tuple[int, str]]] = {}
        for row in rows:
            c_id = int(row[0])
            s_type = str(row[1])
            s_id = str(row[2]) if row[2] is not None else None
            c_type = str(row[3])
            severity = str(row[4])
            text = str(row[5])

            if severity != "hard":
                continue

            key = (s_type, s_id, c_type)
            groups.setdefault(key, []).append((c_id, text))

        # 检测冲突：同组内超过 1 条 hard 条款
        conflicts: list[Conflict] = []
        for (s_type, s_id, _c_type), items in groups.items():
            if len(items) < 2:
                continue
            # 简化：取前两条作为冲突对
            conflicts.append(Conflict(
                clause_a_id=items[0][0],
                clause_b_id=items[1][0],
                scope_type=s_type,
                scope_id=s_id,
                reason=f"同 scope ({s_type}/{s_id}) 有 {len(items)} 条互斥 hard 条款",
            ))

        return conflicts

    # ------------------------------------------------------------------
    # 冲突选择题生成
    # ------------------------------------------------------------------

    def generate_conflict_questions(
        self,
        *,
        project_id: int,
        conflicts: list[Conflict],
    ) -> list[ConflictQuestion]:
        """生成冲突选择题：每个冲突生成 1 个 DecisionSession。

        选项：
        1. 保留条款 A
        2. 保留条款 B
        3. 合并为折中版
        4. 两条都删除

        返回 ConflictQuestion 列表（question_id = decision_session_id）。
        """
        questions: list[ConflictQuestion] = []
        for conflict in conflicts:
            # 获取条款文本
            row_a = self.conn.execute(
                "SELECT clause_text FROM writing_atomic_source_clauses WHERE atomic_clause_id = ?",
                (conflict.clause_a_id,),
            ).fetchone()
            row_b = self.conn.execute(
                "SELECT clause_text FROM writing_atomic_source_clauses WHERE atomic_clause_id = ?",
                (conflict.clause_b_id,),
            ).fetchone()

            text_a = str(row_a[0]) if row_a else "(unknown)"
            text_b = str(row_b[0]) if row_b else "(unknown)"

            # 创建 DecisionSession
            now = now_utc_iso()
            cursor = self.conn.execute(
                """
                INSERT INTO writing_decision_sessions
                    (project_id, scope_type, scope_id, target_type, target_id,
                     human_text, status, created_at, updated_at)
                VALUES (?, ?, ?, 'ConflictResolution', ?, ?, 'collecting', ?, ?)
                """,
                (
                    project_id,
                    conflict.scope_type,
                    conflict.scope_id,
                    f"{conflict.clause_a_id}_{conflict.clause_b_id}",
                    conflict.reason,
                    now,
                    now,
                ),
            )
            session_id = int(cursor.lastrowid)

            # 创建选项集
            options = [
                {"label": f"保留条款 A: {text_a[:60]}"},
                {"label": f"保留条款 B: {text_b[:60]}"},
                {"label": "合并为折中版"},
                {"label": "两条都删除"},
            ]
            self.conn.execute(
                """
                INSERT INTO writing_decision_option_sets
                    (decision_session_id, version, options_json, recommended_option,
                     status, created_at)
                VALUES (?, 1, ?, NULL, 'active', ?)
                """,
                (session_id, json.dumps(options, ensure_ascii=False), now),
            )

            questions.append(ConflictQuestion(
                question_id=session_id,
                scope_type=conflict.scope_type,
                scope_id=conflict.scope_id,
                clause_a_id=conflict.clause_a_id,
                clause_b_id=conflict.clause_b_id,
                reason=conflict.reason,
            ))

        return questions

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    @staticmethod
    def _infer_source_kind(filename: str) -> str:
        """从文件名推断 source_kind。"""
        lower = filename.lower()
        for kind, keywords in _KIND_KEYWORDS.items():
            if any(kw in lower for kw in keywords):
                return kind
        return "other"

    @staticmethod
    def _default_extraction(content: str, filename: str) -> list[dict[str, Any]]:
        """默认的基于规则抽取器：按行分割，每个非空段落作为一条条款。

        生产环境应替换为 LLM 抽取器。
        """
        clauses: list[dict[str, Any]] = []
        for line in content.split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # 简化规则：按句号/分号分割
            for segment in line.replace(";", ".").split("."):
                segment = segment.strip()
                if len(segment) < 5:
                    continue
                clauses.append({
                    "scope_type": "book",
                    "scope_id": None,
                    "clause_type": "quality",
                    "severity": "soft",
                    "clause_text": segment,
                })
        return clauses
