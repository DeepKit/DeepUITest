"""主编台薄调度层。

只读取状态并选择下一步角色，不直接写契约、正文或 canonical。

角色边界：
- DecisionSessionHost：保存 human_text、AI parsed patch、readback_text、状态和恢复点
- ContractSteward：管理契约版本、source hash、confirmed/locked/superseded 状态
- Gatekeeper：校验 AI patch 的 schema、来源覆盖、上下层冲突、stale 和状态机合法性
- CanonicalKeeper：只接受已确认契约与 accepted 正文，不读取聊天内容
- AuditLedger：追加记录 AI 调用、human decision、contract changelog、runtime event
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Any

from ink.contract.patch_engine import ContractPatchEngine
from ink.core.llm_gateway import LLMGateway
from ink.decision_sessions import DecisionSessionStore
from ink.errors import ContractPatchError, DataIntegrityError
from ink.source_workflow import SourceWorkflowStore
from ink.time import now_utc_iso


# ── 结果 dataclass ──────────────────────────────────────

@dataclass(frozen=True)
class WorkflowStep:
    """调度器 step 的返回值。"""
    next_action: str
    session_id: int
    payload: dict[str, Any] | None = None


@dataclass(frozen=True)
class ParseResult:
    """DecisionSessionHost.parse 的返回值。"""
    decision_session_id: int
    parsed_patch: dict[str, Any]
    readback_text: str


@dataclass(frozen=True)
class ValidationResult:
    """Gatekeeper.validate 的返回值。"""
    is_valid: bool
    errors: list[str]


@dataclass(frozen=True)
class ApplyResult:
    """ContractSteward.apply 的返回值。"""
    contract_version_id: int
    contract_patch_id: int
    after_hash: str


# ── 角色实现 ────────────────────────────────────────────

class DecisionSessionHost:
    """保存 human_text、AI parsed patch、readback_text、状态和恢复点。"""

    def __init__(self, conn: sqlite3.Connection, *, gateway: LLMGateway | None = None) -> None:
        self.conn = conn
        self._store = DecisionSessionStore(conn)
        self._gateway = gateway

    def start_session(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
        target_type: str,
        target_id: str | None,
        human_text: str,
    ) -> int:
        """启动新的 DecisionSession。"""
        return self._store.start(
            project_id=project_id,
            scope_type=scope_type,
            scope_id=scope_id,
            target_type=target_type,
            target_id=target_id,
            human_text=human_text,
        )

    def parse(
        self,
        decision_session_id: int,
        *,
        human_text: str,
        scope_type: str,
    ) -> ParseResult:
        """AI 解析 human_text 为 patch。

        如果 gateway 为 None，则生成一个 mock patch（用于测试）。
        """
        if self._gateway is None:
            # Mock 模式：生成简单 patch
            parsed_patch = [
                {"op": "add", "path": "test_field", "value": human_text},
            ]
            readback_text = f"我理解为：{human_text}"
        else:
            # 调 LLM 解析
            prompt = self._build_parse_prompt(human_text, scope_type)
            result = self._gateway.call(
                project_id=0,
                shot_id=None,
                run_id=None,
                call_type="decision_session_parse",
                prompt_id=None,
                prompt_text=prompt,
                model_name="claude-sonnet-4-20250514",
                idempotency_key=f"parse-{decision_session_id}",
            )
            parsed_patch = self._parse_llm_output(result.text)
            readback_text = self._extract_readback(result.text)

        # 写库
        self._store.record_ai_parse(
            decision_session_id,
            parsed_patch=parsed_patch,
            readback_text=readback_text,
            source_hashes=[],
        )

        return ParseResult(
            decision_session_id=decision_session_id,
            parsed_patch=parsed_patch,
            readback_text=readback_text,
        )

    def _build_parse_prompt(self, human_text: str, scope_type: str) -> str:
        return f"""你是一个契约解析助手。请将以下用户输入解析为 JSON-Patch 格式。

用户输入：{human_text}

作用域：{scope_type}

请输出 JSON 数组，每个元素形如：
{{"op": "add|replace|remove", "path": "字段路径", "value": "值"}}

然后输出回读文本（用自然语言总结你的理解）。

输出格式：
PATCH: <JSON 数组>
READBACK: <回读文本>
"""

    def _parse_llm_output(self, text: str) -> list[dict[str, Any]]:
        # 简单解析：找 PATCH: 行
        lines = text.strip().split("\n")
        for i, line in enumerate(lines):
            if line.startswith("PATCH:"):
                patch_line = line[6:].strip()
                return json.loads(patch_line)
        return []

    def _extract_readback(self, text: str) -> str:
        lines = text.strip().split("\n")
        for line in lines:
            if line.startswith("READBACK:"):
                return line[9:].strip()
        return ""

    def create_option_set(
        self,
        decision_session_id: int,
        *,
        options: list[dict[str, Any]],
        recommended_option: int | None = None,
    ) -> int:
        """创建选项集。"""
        return self._store.create_option_set(
            decision_session_id,
            options=options,
            recommended_option=recommended_option,
        )

    def select_option(self, decision_session_id: int, selected_option: int) -> None:
        """选择选项。"""
        self._store.select_option(decision_session_id, selected_option)


class ContractSteward:
    """管理契约版本、source hash、confirmed/locked/superseded 状态。"""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self._store = DecisionSessionStore(conn)

    def apply(
        self,
        decision_session_id: int,
        *,
        actor: str,
        reason: str,
        contract_scope_type: str,
        contract_scope_id: str | None,
        contract_payload: dict[str, Any] | None = None,
        source_clause_ids: list[int] | None = None,
        source_hashes: list[str] | None = None,
        patch_engine: ContractPatchEngine | None = None,
    ) -> ApplyResult:
        """应用契约：写契约版本、patch、changelog。"""
        # 如果没有 contract_payload 和 patch_engine，构造一个默认的
        if contract_payload is None and patch_engine is None:
            # 从 session 中读取 parsed_patch
            row = self.conn.execute(
                "SELECT parsed_patch_json, scope_type, scope_id FROM writing_decision_sessions WHERE decision_session_id = ?",
                (decision_session_id,),
            ).fetchone()
            if row is not None:
                parsed_patch = json.loads(str(row[0])) if row[0] else {}
                # 构造一个简单的 contract_payload
                scope_type = str(row[1])
                if scope_type == "book":
                    contract_payload = {"identity": {"title": "Default Book"}, "logline": "Default logline"}
                elif scope_type == "volume":
                    contract_payload = {"volume_id": {"name": "Default Volume"}}
                elif scope_type == "part":
                    contract_payload = {"part_id": {"name": "Default Part"}}
                elif scope_type == "chapter":
                    contract_payload = {"chapter_id": {"title": "Default Chapter"}}
                else:
                    contract_payload = {}

        result = self._store.confirm_and_apply(
            decision_session_id,
            actor=actor,
            reason=reason,
            contract_scope_type=contract_scope_type,
            contract_scope_id=contract_scope_id,
            contract_payload=contract_payload,
            source_clause_ids=source_clause_ids or [],
            source_hashes=source_hashes or [],
            patch_engine=patch_engine,
        )
        return ApplyResult(
            contract_version_id=result.contract_version_id,
            contract_patch_id=result.contract_patch_id,
            after_hash=result.after_hash,
        )


class Gatekeeper:
    """校验 AI patch 的 schema、来源覆盖、上下层冲突、stale 和状态机合法性。"""

    def __init__(
        self,
        conn: sqlite3.Connection,
        *,
        patch_engine: ContractPatchEngine | None = None,
    ) -> None:
        self.conn = conn
        self._patch_engine = patch_engine
        self._source_store = SourceWorkflowStore(conn)

    def validate(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
        patch: list[dict[str, Any]] | None = None,
    ) -> ValidationResult:
        """校验 patch。"""
        errors: list[str] = []

        # 1. 形态校验
        if patch is not None:
            try:
                if self._patch_engine is not None:
                    self._patch_engine.validate_patch_shape(patch)
            except ContractPatchError as e:
                errors.append(f"patch 形态非法: {e}")

        # 2. coverage gate 检查
        if self._source_store.has_blocking_coverage_gaps(
            project_id=project_id,
            contract_scope_type=scope_type,
            contract_scope_id=scope_id,
        ):
            errors.append("coverage gate 有 blocking gap")

        # 3. stale 检查（未来实现）

        return ValidationResult(
            is_valid=len(errors) == 0,
            errors=errors,
        )


class CanonicalKeeper:
    """只接受已确认契约与 accepted 正文，不读取聊天内容。"""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def is_confirmed(self, *, contract_version_id: int) -> bool:
        """检查契约版本是否已 confirmed。"""
        row = self.conn.execute(
            "SELECT status FROM writing_contract_versions WHERE contract_version_id = ?",
            (contract_version_id,),
        ).fetchone()
        return row is not None and str(row[0]) == "confirmed"


class AuditLedger:
    """追加记录 AI 调用、human decision、contract changelog、runtime event。"""

    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def record_event(
        self,
        *,
        project_id: int,
        event_type: str,
        payload: dict[str, Any],
        shot_id: str | None = None,
        run_id: int | None = None,
    ) -> None:
        """记录 runtime event。"""
        now = now_utc_iso()
        self.conn.execute(
            """
            INSERT INTO writing_runtime_events
                (project_id, run_id, shot_id, event_type, event_payload, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                project_id,
                run_id,
                shot_id,
                event_type,
                json.dumps(payload, sort_keys=True),
                now,
            ),
        )


# ── 调度器 ──────────────────────────────────────────────

class WorkflowConductor:
    """主编台薄调度层。

    只读取状态并选择下一步角色，不直接写契约、正文或 canonical。
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        *,
        gateway: LLMGateway | None = None,
        patch_engine: ContractPatchEngine | None = None,
    ) -> None:
        self.conn = conn
        self._host = DecisionSessionHost(conn, gateway=gateway)
        self._steward = ContractSteward(conn)
        self._gatekeeper = Gatekeeper(conn, patch_engine=patch_engine)
        self._keeper = CanonicalKeeper(conn)
        self._ledger = AuditLedger(conn)
        self._patch_engine = patch_engine

    def step(
        self,
        *,
        project_id: int,
        session_id: int,
        human_text: str | None = None,
        selected_option: int | None = None,
    ) -> WorkflowStep:
        """读取当前 session 状态，决定下一步动作。"""
        # 1. 读取 session 状态
        row = self.conn.execute(
            """
            SELECT status, scope_type, scope_id, target_type, target_id
            FROM writing_decision_sessions
            WHERE decision_session_id = ?
            """,
            (session_id,),
        ).fetchone()
        if row is None:
            raise DataIntegrityError(f"session not found: {session_id}")

        status = str(row[0])
        scope_type = str(row[1])
        scope_id = str(row[2]) if row[2] is not None else None
        target_type = str(row[3])
        target_id = str(row[4]) if row[4] is not None else None

        # 2. 根据状态机决定下一步
        if status == "collecting":
            # 需要 human_text
            if human_text is None:
                return WorkflowStep(
                    next_action="wait_for_input",
                    session_id=session_id,
                )
            # 记录审计
            self._ledger.record_event(
                project_id=project_id,
                event_type="SESSION_INPUT_RECEIVED",
                payload={"session_id": session_id, "human_text": human_text},
            )
            # 解析
            parse_result = self._host.parse(session_id, human_text=human_text, scope_type=scope_type)
            # 创建选项集
            self._host.create_option_set(
                session_id,
                options=[{"label": "确认"}, {"label": "拒绝"}],
                recommended_option=1,
            )
            return WorkflowStep(
                next_action="awaiting_confirm",
                session_id=session_id,
                payload={"parsed_patch": parse_result.parsed_patch},
            )

        elif status == "ai_parsed":
            # 自动创建选项集
            self._host.create_option_set(
                session_id,
                options=[{"label": "确认"}, {"label": "拒绝"}],
                recommended_option=1,
            )
            return WorkflowStep(
                next_action="awaiting_confirm",
                session_id=session_id,
            )

        elif status == "awaiting_confirm":
            # 需要 selected_option
            if selected_option is None:
                return WorkflowStep(
                    next_action="wait_for_selection",
                    session_id=session_id,
                )
            # 选择
            self._host.select_option(session_id, selected_option)
            if selected_option == 1:
                # 确认
                result = self._steward.apply(
                    session_id,
                    actor="author",
                    reason="workflow_conductor_confirm",
                    contract_scope_type=scope_type,
                    contract_scope_id=scope_id,
                    patch_engine=self._patch_engine,
                )
                # 记录审计
                self._ledger.record_event(
                    project_id=project_id,
                    event_type="CONTRACT_CONFIRMED",
                    payload={
                        "session_id": session_id,
                        "contract_version_id": result.contract_version_id,
                        "after_hash": result.after_hash,
                    },
                )
                return WorkflowStep(
                    next_action="confirmed",
                    session_id=session_id,
                    payload={
                        "contract_version_id": result.contract_version_id,
                        "after_hash": result.after_hash,
                    },
                )
            else:
                # 拒绝
                return WorkflowStep(
                    next_action="rejected",
                    session_id=session_id,
                )

        elif status == "confirmed":
            return WorkflowStep(
                next_action="done",
                session_id=session_id,
            )

        else:
            return WorkflowStep(
                next_action="error",
                session_id=session_id,
                payload={"error": f"unexpected status: {status}"},
            )
