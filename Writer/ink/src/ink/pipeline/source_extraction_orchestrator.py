from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Protocol, Sequence

from ink.core.llm_gateway import LLMGateway
from ink.source_workflow import SourceWorkflowStore


@dataclass(frozen=True)
class ExtractedClause:
    """LLM 抽取出的单条原子条款。"""

    scope_type: str
    scope_id: str | None
    clause_type: str
    severity: str
    clause_text: str
    source_refs: Sequence[str]
    source_hashes: Sequence[str]

    def key(self) -> str:
        """归一化去重键：clause_type + scope + 首个 source_ref。

        用于 primary/crosscheck 两路抽取结果的集合比对。同位置（同 source_ref）
        但文本不同的条款对会被识别为 conflict。
        """
        first_ref = self.source_refs[0] if self.source_refs else "no-ref"
        return f"{self.clause_type}|{self.scope_type}|{self.scope_id or ''}|{first_ref}"


@dataclass(frozen=True)
class ExtractionOutcome:
    """单路抽取结果。"""

    slot: str
    model_provider: str
    model_name: str
    clauses: tuple[ExtractedClause, ...]
    raw_text: str


@dataclass(frozen=True)
class CrosscheckDiscrepancy:
    """primary 与 crosscheck 抽取差异。

    - ``missing_in_crosscheck``: primary 抽到但 crosscheck 漏抽 → low_confidence
    - ``missing_in_primary``: crosscheck 抽到但 primary 漏抽 → 低置信漏抽
    - ``conflict_texts``: 同 key 但文本不同 → conflict
    """

    missing_in_crosscheck: tuple[ExtractedClause, ...]
    missing_in_primary: tuple[ExtractedClause, ...]
    conflict_texts: tuple[tuple[ExtractedClause, ExtractedClause], ...]


@dataclass(frozen=True)
class DualExtractionResult:
    primary: ExtractionOutcome
    crosscheck: ExtractionOutcome
    discrepancy: CrosscheckDiscrepancy
    primary_clause_ids: tuple[int, ...]
    crosscheck_clause_ids: tuple[int, ...]
    primary_extraction_run_id: int
    crosscheck_extraction_run_id: int


class SourceExtractionProtocol(Protocol):
    """抽取 prompt 构造与响应解析的协议。"""

    def build_prompt(self, *, source_text: str, source_path: str) -> str: ...

    def parse(self, *, raw_text: str, source_hashes: Sequence[str]) -> list[ExtractedClause]: ...


class DefaultSourceExtractionProtocol(SourceExtractionProtocol):
    """默认 prompt/parse：要求 LLM 输出 JSON 数组。"""

    def build_prompt(self, *, source_text: str, source_path: str) -> str:
        return (
            "你是写作指南原子条款抽取器。从以下来源文本中抽取原子化、可校验的硬约束条款，"
            "每条包含 scope_type/scope_id/clause_type/severity/clause_text/source_refs。"
            "severity 仅限 hard/soft/recommended。只输出 JSON 数组，不要解释。\n\n"
            f"来源路径：{source_path}\n来源文本：\n{source_text}"
        )

    def parse(self, *, raw_text: str, source_hashes: Sequence[str]) -> list[ExtractedClause]:
        stripped = raw_text.strip()
        start = stripped.find("[")
        end = stripped.rfind("]")
        if start == -1 or end == -1 or end <= start:
            return []
        try:
            payload = json.loads(stripped[start : end + 1])
        except json.JSONDecodeError:
            return []
        if not isinstance(payload, list):
            return []
        clauses: list[ExtractedClause] = []
        for item in payload:
            if not isinstance(item, dict):
                continue
            text = str(item.get("clause_text", "")).strip()
            if not text:
                continue
            clauses.append(
                ExtractedClause(
                    scope_type=str(item.get("scope_type", "book")),
                    scope_id=item.get("scope_id"),
                    clause_type=str(item.get("clause_type", "style")),
                    severity=str(item.get("severity", "soft")),
                    clause_text=text,
                    source_refs=tuple(item.get("source_refs", []) or []),
                    source_hashes=tuple(source_hashes),
                )
            )
        return clauses


def diff_extractions(primary: Sequence[ExtractedClause], crosscheck: Sequence[ExtractedClause]) -> CrosscheckDiscrepancy:
    """比对两路抽取，按位置 key 找漏抽与冲突。

    key = clause_type + scope + 首个 source_ref（不含文本），这样同位置不同文本的条款对
    会被识别为 conflict，而非相互 missing。
    """
    primary_by_key: dict[str, list[ExtractedClause]] = {}
    crosscheck_by_key: dict[str, list[ExtractedClause]] = {}
    for clause in primary:
        primary_by_key.setdefault(clause.key(), []).append(clause)
    for clause in crosscheck:
        crosscheck_by_key.setdefault(clause.key(), []).append(clause)

    missing_in_crosscheck: list[ExtractedClause] = []
    missing_in_primary: list[ExtractedClause] = []
    conflicts: list[tuple[ExtractedClause, ExtractedClause]] = []

    all_keys = set(primary_by_key) | set(crosscheck_by_key)
    for key in all_keys:
        p_list = primary_by_key.get(key, [])
        c_list = crosscheck_by_key.get(key, [])
        if p_list and not c_list:
            missing_in_crosscheck.extend(p_list)
        elif c_list and not p_list:
            missing_in_primary.extend(c_list)
        elif p_list and c_list:
            # 同 key：比较文本，不同则 conflict
            p_text = p_list[0].clause_text.strip().lower()
            c_text = c_list[0].clause_text.strip().lower()
            if p_text != c_text:
                conflicts.append((p_list[0], c_list[0]))

    return CrosscheckDiscrepancy(
        missing_in_crosscheck=tuple(missing_in_crosscheck),
        missing_in_primary=tuple(missing_in_primary),
        conflict_texts=tuple(conflicts),
    )


class SourceExtractionOrchestrator:
    """双模型抽取执行器。

    primary 与 crosscheck 两路独立抽取同一来源文档，比对差异：
    - 两路一致的条款写入 ``writing_atomic_source_clauses`` (status=proposed)
    - primary 独有的条款写入但标记 low_confidence_refs（crosscheck 漏抽）
    - crosscheck 独有的条款写入但标记 low_confidence_refs（primary 漏抽）
    - 同 key 不同文本的条款对生成 coverage conflict（``coverage_status='conflict'``）
    - 两路抽取结果分别写 ``writing_source_extraction_runs`` 记录模型与 source_hash
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        *,
        gateway: LLMGateway | None = None,
        protocol: SourceExtractionProtocol | None = None,
    ) -> None:
        self.conn = conn
        self.store = SourceWorkflowStore(conn)
        self.gateway = gateway or LLMGateway(conn)
        self.protocol = protocol or DefaultSourceExtractionProtocol()

    def extract_dual(
        self,
        *,
        project_id: int,
        source_document_id: int,
        source_text: str,
        source_path: str,
        source_hash: str,
        primary_model: str,
        crosscheck_model: str,
        primary_provider: str = "primary",
        crosscheck_provider: str = "crosscheck",
        shot_id: str | None = None,
        run_id: int | None = None,
    ) -> DualExtractionResult:
        prompt_text = self.protocol.build_prompt(source_text=source_text, source_path=source_path)

        primary_raw = self.gateway.call(
            project_id=project_id,
            shot_id=shot_id,
            run_id=run_id,
            call_type="source_extract_primary",
            prompt_id=None,
            prompt_text=prompt_text,
            model_name=primary_model,
            idempotency_key=f"src-extract-primary:{source_document_id}:{source_hash}",
            model_provider=primary_provider,
        ).text
        crosscheck_raw = self.gateway.call(
            project_id=project_id,
            shot_id=shot_id,
            run_id=run_id,
            call_type="source_extract_crosscheck",
            prompt_id=None,
            prompt_text=prompt_text,
            model_name=crosscheck_model,
            idempotency_key=f"src-extract-crosscheck:{source_document_id}:{source_hash}",
            model_provider=crosscheck_provider,
        ).text

        primary_clauses = tuple(self.protocol.parse(raw_text=primary_raw, source_hashes=[source_hash]))
        crosscheck_clauses = tuple(self.protocol.parse(raw_text=crosscheck_raw, source_hashes=[source_hash]))

        primary_clause_ids = self._persist_clauses(
            project_id=project_id,
            source_document_id=source_document_id,
            clauses=primary_clauses,
            source_hash=source_hash,
        )
        crosscheck_clause_ids = self._persist_clauses(
            project_id=project_id,
            source_document_id=source_document_id,
            clauses=crosscheck_clauses,
            source_hash=source_hash,
        )

        discrepancy = diff_extractions(primary_clauses, crosscheck_clauses)
        low_confidence_refs: list[str] = []
        for clause in discrepancy.missing_in_crosscheck:
            low_confidence_refs.append(f"primary_only:{clause.source_refs[0] if clause.source_refs else 'no-ref'}")
        for clause in discrepancy.missing_in_primary:
            low_confidence_refs.append(f"crosscheck_only:{clause.source_refs[0] if clause.source_refs else 'no-ref'}")

        primary_run_id = self.store.record_extraction_run(
            project_id=project_id,
            source_document_id=source_document_id,
            extractor_slot="primary",
            model_provider=primary_provider,
            model_name=primary_model,
            source_hash=source_hash,
            extracted_clause_ids=primary_clause_ids,
            low_confidence_refs=[r for r in low_confidence_refs if r.startswith("primary_only:")],
        )
        crosscheck_run_id = self.store.record_extraction_run(
            project_id=project_id,
            source_document_id=source_document_id,
            extractor_slot="crosscheck",
            model_provider=crosscheck_provider,
            model_name=crosscheck_model,
            source_hash=source_hash,
            extracted_clause_ids=crosscheck_clause_ids,
            low_confidence_refs=[r for r in low_confidence_refs if r.startswith("crosscheck_only:")],
        )

        self._record_conflicts(
            project_id=project_id,
            source_document_id=source_document_id,
            conflicts=discrepancy.conflict_texts,
            source_hash=source_hash,
        )

        return DualExtractionResult(
            primary=ExtractionOutcome(
                slot="primary",
                model_provider=primary_provider,
                model_name=primary_model,
                clauses=primary_clauses,
                raw_text=primary_raw,
            ),
            crosscheck=ExtractionOutcome(
                slot="crosscheck",
                model_provider=crosscheck_provider,
                model_name=crosscheck_model,
                clauses=crosscheck_clauses,
                raw_text=crosscheck_raw,
            ),
            discrepancy=discrepancy,
            primary_clause_ids=tuple(primary_clause_ids),
            crosscheck_clause_ids=tuple(crosscheck_clause_ids),
            primary_extraction_run_id=primary_run_id,
            crosscheck_extraction_run_id=crosscheck_run_id,
        )

    def _persist_clauses(
        self,
        *,
        project_id: int,
        source_document_id: int,
        clauses: Sequence[ExtractedClause],
        source_hash: str,
    ) -> list[int]:
        ids: list[int] = []
        for clause in clauses:
            clause_id = self.store.record_atomic_clause(
                project_id=project_id,
                source_document_id=source_document_id,
                scope_type=clause.scope_type,
                scope_id=clause.scope_id,
                clause_type=clause.clause_type,
                severity=clause.severity,
                clause_text=clause.clause_text,
                source_refs=clause.source_refs,
                source_hashes=[source_hash],
            )
            ids.append(clause_id)
        return ids

    def _record_conflicts(
        self,
        *,
        project_id: int,
        source_document_id: int,
        conflicts: Sequence[tuple[ExtractedClause, ExtractedClause]],
        source_hash: str,
    ) -> None:
        for primary_clause, crosscheck_clause in conflicts:
            self.store.record_coverage(
                project_id=project_id,
                contract_scope_type=primary_clause.scope_type,
                contract_scope_id=primary_clause.scope_id,
                contract_field_path=f"conflict:{source_document_id}:{primary_clause.clause_type}",
                coverage_status="conflict",
                atomic_clause_id=None,
                evidence={
                    "primary_text": primary_clause.clause_text,
                    "crosscheck_text": crosscheck_clause.clause_text,
                    "source_hash": source_hash,
                },
            )
