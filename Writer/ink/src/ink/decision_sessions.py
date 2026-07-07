from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from typing import Sequence

from ink.contract.patch_engine import ContractPatchEngine, PatchApplicationResult
from ink.errors import ConcurrentModificationError, ContractPatchError, DataIntegrityError
from ink.event_log import EventLog
from ink.time import now_utc_iso


@dataclass(frozen=True)
class DecisionSessionRecord:
    decision_session_id: int
    project_id: int
    status: str
    target_type: str
    target_id: str | None


@dataclass(frozen=True)
class ConfirmedContractResult:
    """``confirm_and_apply`` 的原子写入结果。

    所有 ID 在同一 SAVEPOINT 内产生；任一写入失败整体回滚，不会返回半状态。
    ``stale_mark`` 在 SAVEPOINT 释放后由 ``stale_manager`` 产生（若传入）。
    """

    decision_session_id: int
    human_decision_id: int
    contract_version_id: int
    contract_patch_id: int
    contract_changelog_id: int
    after_hash: str
    stale_mark: object | None = None  # StaleMarkResult | None


class DecisionSessionStore:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn
        self._event_log = EventLog(conn)

    def start(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
        target_type: str,
        target_id: str | None,
        human_text: str,
        parent_decision_session_id: int | None = None,
    ) -> int:
        now = now_utc_iso()
        # 自动记录当前 scope 最新 confirmed/locked version 的 hash，供 confirm 时做冲突检测。
        # 首次确认前无 base version，before_hash 为 None，confirm 时跳过冲突检测。
        before_hash = _current_scope_version_hash(
            self.conn, project_id=project_id,
            scope_type=scope_type, scope_id=scope_id,
        )
        try:
            cursor = self.conn.execute(
                """
                INSERT INTO writing_decision_sessions
                    (project_id, scope_type, scope_id, target_type, target_id,
                     parent_decision_session_id, status, human_text, before_hash,
                     created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 'collecting', ?, ?, ?, ?)
                """,
                (
                    project_id,
                    scope_type,
                    scope_id,
                    target_type,
                    target_id,
                    parent_decision_session_id,
                    human_text,
                    before_hash,
                    now,
                    now,
                ),
            )
        except sqlite3.IntegrityError as exc:
            # scope 级 partial unique index (idx_active_decision_session_scope) 命中：
            # 同 scope 已有活跃 session。target 级 index 命中也会走到这里（同 target 重复）。
            raise DataIntegrityError(
                f"an active decision session already exists for scope "
                f"{scope_type}/{scope_id} in project {project_id}; "
                f"cancel or confirm it first"
            ) from exc
        session_id = int(cursor.lastrowid)
        self._event_log.log_session_event(
            session_id,
            "created",
            {"scope_type": scope_type, "scope_id": scope_id, "target_type": target_type, "target_id": target_id},
        )
        return session_id

    def record_ai_parse(
        self,
        decision_session_id: int,
        *,
        parsed_patch: object,
        readback_text: str,
        source_hashes: Sequence[str],
        before_hash: str | None = None,
        patch_engine: ContractPatchEngine | None = None,
    ) -> None:
        # 解析时形态校验（可选）：尽早拒绝格式非法 patch
        if patch_engine is not None:
            try:
                patch_engine.validate_patch_shape(parsed_patch)
            except ContractPatchError as exc:
                raise DataIntegrityError(
                    f"rejected malformed patch for session {decision_session_id}: {exc}"
                ) from exc
        now = now_utc_iso()
        updated = self.conn.execute(
            """
            UPDATE writing_decision_sessions
            SET status = 'ai_parsed',
                parsed_patch_json = ?,
                readback_text = ?,
                source_hashes_json = ?,
                before_hash = COALESCE(?, before_hash),
                updated_at = ?
            WHERE decision_session_id = ?
              AND status IN ('collecting','retryable_failed','needs_human','stale')
            """,
            (
                _json(parsed_patch),
                readback_text,
                _json(list(source_hashes)),
                before_hash,
                now,
                decision_session_id,
            ),
        ).rowcount
        if updated != 1:
            raise DataIntegrityError(f"decision session is not parseable: {decision_session_id}")
        self._event_log.log_session_event(
            decision_session_id,
            "ai_parsed",
            {"readback_text": readback_text, "source_hashes": list(source_hashes)},
        )

    def create_option_set(
        self,
        decision_session_id: int,
        *,
        options: Sequence[dict[str, object]],
        recommended_option: int | None = None,
    ) -> int:
        _validate_options(options, recommended_option)
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_set")
            version = _next_option_version(self.conn, decision_session_id)
            cursor = self.conn.execute(
                """
                INSERT INTO writing_decision_option_sets
                    (decision_session_id, version, options_json, recommended_option, regenerate_count,
                     status, created_at)
                VALUES (?, ?, ?, ?, 0, 'active', ?)
                """,
                (decision_session_id, version, _json(list(options)), recommended_option, now),
            )
            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET status = 'awaiting_confirm', updated_at = ?
                WHERE decision_session_id = ? AND status = 'ai_parsed'
                """,
                (now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(f"decision session is not ready for options: {decision_session_id}")
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_set")
            self.conn.execute("RELEASE decision_option_set")
            raise
        else:
            self.conn.execute("RELEASE decision_option_set")
            option_set_id = int(cursor.lastrowid)
            self._event_log.log_session_event(
                decision_session_id,
                "option_set_created",
                {"option_set_id": option_set_id, "option_count": len(options)},
            )
            return option_set_id

    def regenerate_options(
        self,
        decision_session_id: int,
        *,
        options: Sequence[dict[str, object]],
        recommended_option: int | None = None,
    ) -> int:
        _validate_options(options, recommended_option)
        current = _load_active_option_set(self.conn, decision_session_id)
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_regenerate")
            self.conn.execute(
                """
                UPDATE writing_decision_option_sets
                SET status = 'superseded'
                WHERE option_set_id = ?
                """,
                (int(current["option_set_id"]),),
            )
            cursor = self.conn.execute(
                """
                INSERT INTO writing_decision_option_sets
                    (decision_session_id, version, options_json, recommended_option, regenerate_count,
                     status, created_at)
                VALUES (?, ?, ?, ?, ?, 'active', ?)
                """,
                (
                    decision_session_id,
                    int(current["version"]) + 1,
                    _json(list(options)),
                    recommended_option,
                    int(current["regenerate_count"]) + 1,
                    now,
                ),
            )
            self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET selected_option = NULL, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (now, decision_session_id),
            )
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_regenerate")
            self.conn.execute("RELEASE decision_option_regenerate")
            raise
        else:
            self.conn.execute("RELEASE decision_option_regenerate")
            return int(cursor.lastrowid)

    def select_option(self, decision_session_id: int, selected_option: int) -> None:
        if selected_option == 9:
            raise DataIntegrityError("option 9 requires regenerate_options() with a new option set")
        current = _load_active_option_set(self.conn, decision_session_id)
        if selected_option == 0:
            self._return_to_collecting(decision_session_id, int(current["option_set_id"]))
            return
        options = json.loads(str(current["options_json"]))
        if not isinstance(options, list) or selected_option < 1 or selected_option > len(options):
            raise DataIntegrityError(f"selected option is outside the active option set: {selected_option}")
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_select")
            self.conn.execute(
                "UPDATE writing_decision_option_sets SET status = 'selected' WHERE option_set_id = ?",
                (int(current["option_set_id"]),),
            )
            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET selected_option = ?, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (selected_option, now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(f"decision session is not awaiting confirmation: {decision_session_id}")
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_select")
            self.conn.execute("RELEASE decision_option_select")
            raise
        else:
            self.conn.execute("RELEASE decision_option_select")
            self._event_log.log_session_event(
                decision_session_id,
                "option_selected",
                {"selected_option": selected_option},
            )

    def confirm(self, decision_session_id: int, *, after_hash: str) -> None:
        row = self.conn.execute(
            """
            SELECT selected_option
            FROM writing_decision_sessions
            WHERE decision_session_id = ? AND status = 'awaiting_confirm'
            """,
            (decision_session_id,),
        ).fetchone()
        if row is None or row[0] is None:
            raise DataIntegrityError(f"decision session has no selected option: {decision_session_id}")
        updated = self.conn.execute(
            """
            UPDATE writing_decision_sessions
            SET status = 'confirmed', after_hash = ?, updated_at = ?
            WHERE decision_session_id = ? AND status = 'awaiting_confirm'
            """,
            (after_hash, now_utc_iso(), decision_session_id),
        ).rowcount
        if updated != 1:
            raise DataIntegrityError(f"decision session cannot be confirmed: {decision_session_id}")
        self._event_log.log_session_event(
            decision_session_id,
            "confirmed",
            {"after_hash": after_hash},
        )

    def confirm_and_apply(
        self,
        decision_session_id: int,
        *,
        actor: str,
        reason: str,
        contract_scope_type: str,
        contract_scope_id: str | None,
        contract_payload: dict[str, object] | None = None,
        change_type: str = "refine",
        source_clause_ids: Sequence[int] = (),
        affected_scopes: Sequence[dict[str, object]] = (),
        stale_downstream: Sequence[dict[str, object]] = (),
        source_hashes: Sequence[str] = (),
        coverage_gate=None,
        patch_engine: ContractPatchEngine | None = None,
        stale_manager=None,
    ) -> ConfirmedContractResult:
        """原子写入 confirmed 审计链。

        在单个 SAVEPOINT 内按 implementation-contract-v1 §3.6a 写入规则 7-8 完成：

        1. coverage gate 检查（blocking gap 未清空时阻断，不写任何行）
        2. ``writing_human_decisions``（decision_type='contract_confirm'）
        3. ``writing_contract_versions``（新版本，status='confirmed'）
        4. ``writing_contract_patches``（status='confirmed'，关联 base/target version）
        5. ``writing_contract_changelog``（old_hash/new_hash/human_decision_id）
        6. DecisionSession 置 ``confirmed`` + after_hash
        7. （仅 ``patch_engine`` 模式）coverage matrix 置 ``covered``

        :param patch_engine: 传入时执行 AI patch → 程序校验应用流水线，
            ``contract_payload`` 自动派生，调用方无需传（传了也忽略）。
            不传时保持原行为（显式要求 ``contract_payload``）。
        :param contract_payload: 非 patch_engine 模式时必填。
        :param stale_manager: 传入 ``StalePropagationManager`` 时，在 SAVEPOINT
            释放后自动调用 ``mark_stale_after_contract_change``，标记下游
            prompt/draft/review/book check stale；结果挂在返回值的 ``stale_mark``。
            不传时保持原行为（调用方需手动触发 stale 传播）。
        """
        session = _load_session_for_confirm(self.conn, decision_session_id)
        project_id = int(session["project_id"])
        before_hash = session["before_hash"]
        parsed_patch_raw = session["parsed_patch_json"]

        # ── patch_engine 分支（接管 contract_payload 派生） ──
        if patch_engine is not None:
            patch_list = json.loads(str(parsed_patch_raw)) if isinstance(parsed_patch_raw, str) else parsed_patch_raw
            if not source_hashes:
                raw = session.get("source_hashes_json")
                source_hashes = list(json.loads(str(raw))) if raw else []
            engine_result = patch_engine.apply_and_validate(
                project_id=project_id,
                scope_type=contract_scope_type,
                scope_id=contract_scope_id,
                patch=patch_list,
                readback_text=str(session.get("readback_text", "")),
                source_clause_ids=source_clause_ids,
                source_hashes=source_hashes,
            )
            contract_payload = dict(engine_result.new_payload)
            if not affected_scopes and engine_result.affected_field_paths:
                affected_scopes = [{
                    "scope_type": contract_scope_type,
                    "scope_id": contract_scope_id,
                    "field_paths": engine_result.affected_field_paths,
                }]
        elif contract_payload is None:
            raise DataIntegrityError(
                "either contract_payload or patch_engine must be provided"
            )

        new_hash = _contract_hash(contract_payload, source_hashes)

        if coverage_gate is not None and coverage_gate.has_blocking_coverage_gaps(
            project_id=project_id,
            contract_scope_type=contract_scope_type,
            contract_scope_id=contract_scope_id,
        ):
            raise DataIntegrityError(
                f"coverage gate has blocking gaps; cannot confirm: {decision_session_id}"
            )

        now = now_utc_iso()

        # ── 冲突检测：base version hash 必须与 session 记录的 before_hash 一致 ──
        # start 时自动把当前 scope 最新 version 的 hash 写入 before_hash；
        # 若此后有人改过同 scope 的契约（base hash 变了），这里拒绝并标 session stale。
        # before_hash 为 None（首次确认、无 base version）时跳过检测。
        if before_hash is not None:
            base_version_id = _resolve_base_contract_version_id(
                self.conn,
                project_id=project_id,
                scope_type=contract_scope_type,
                scope_id=contract_scope_id,
            )
            if base_version_id is not None:
                base_hash = _version_hash_by_id(self.conn, base_version_id)
                if base_hash != before_hash:
                    self._mark_session_stale(decision_session_id)
                    raise ConcurrentModificationError(
                        f"contract version changed since this session started "
                        f"(expected {before_hash[:8]}, got {str(base_hash)[:8]}); "
                        f"session marked stale, please re-open"
                    )

        try:
            self.conn.execute("SAVEPOINT decision_confirm_apply")

            human_decision_id = _insert_contract_confirm_decision(
                self.conn,
                project_id=project_id,
                actor=actor,
                reason=reason,
                preconditions={
                    "decision_session_id": decision_session_id,
                    "contract_scope_type": contract_scope_type,
                    "contract_scope_id": contract_scope_id,
                    "change_type": change_type,
                    "coverage_gate_checked": coverage_gate is not None,
                },
                now=now,
            )

            base_contract_version_id = _resolve_base_contract_version_id(
                self.conn,
                project_id=project_id,
                scope_type=contract_scope_type,
                scope_id=contract_scope_id,
            )
            version = _next_contract_version(
                self.conn,
                project_id=project_id,
                scope_type=contract_scope_type,
                scope_id=contract_scope_id,
            )
            version_cursor = self.conn.execute(
                """
                INSERT INTO writing_contract_versions
                    (project_id, scope_type, scope_id, version, status, contract_json,
                     contract_hash, source_clause_ids_json, created_from_decision_session_id,
                     created_at)
                VALUES (?, ?, ?, ?, 'confirmed', ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    contract_scope_type,
                    contract_scope_id,
                    version,
                    _json(contract_payload),
                    new_hash,
                    _json(list(source_clause_ids)),
                    decision_session_id,
                    now,
                ),
            )
            contract_version_id = int(version_cursor.lastrowid)

            patch_cursor = self.conn.execute(
                """
                INSERT INTO writing_contract_patches
                    (project_id, decision_session_id, base_contract_version_id,
                     target_contract_version_id, change_type, patch_json,
                     affected_scopes_json, stale_downstream_json, source_clause_ids_json,
                     status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'confirmed', ?)
                """,
                (
                    project_id,
                    decision_session_id,
                    base_contract_version_id,
                    contract_version_id,
                    change_type,
                    parsed_patch_raw,
                    _json(list(affected_scopes)),
                    _json(list(stale_downstream)),
                    _json(list(source_clause_ids)),
                    now,
                ),
            )
            contract_patch_id = int(patch_cursor.lastrowid)

            # ── patch_engine 模式：更新 coverage matrix ──
            if patch_engine is not None and coverage_gate is not None:
                for path in engine_result.affected_field_paths:
                    coverage_gate.record_coverage(
                        project_id=project_id,
                        contract_scope_type=contract_scope_type,
                        contract_scope_id=contract_scope_id,
                        contract_field_path=path,
                        coverage_status="covered",
                        decision_session_id=decision_session_id,
                        evidence={"source": "patch_engine", "patch_id": contract_patch_id},
                    )

            changelog_cursor = self.conn.execute(
                """
                INSERT INTO writing_contract_changelog
                    (project_id, clause_id, old_hash, new_hash, actor, reason,
                     human_decision_id, created_at)
                VALUES (?, NULL, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    before_hash,
                    new_hash,
                    actor,
                    reason,
                    human_decision_id,
                    now,
                ),
            )
            contract_changelog_id = int(changelog_cursor.lastrowid)

            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET status = 'confirmed', after_hash = ?, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (new_hash, now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(
                    f"decision session cannot be confirmed: {decision_session_id}"
                )
        except Exception:
            self.conn.execute("ROLLBACK TO decision_confirm_apply")
            self.conn.execute("RELEASE decision_confirm_apply")
            raise
        else:
            self.conn.execute("RELEASE decision_confirm_apply")
            self._event_log.log_session_event(
                decision_session_id,
                "confirmed",
                {
                    "after_hash": new_hash,
                    "contract_version_id": contract_version_id,
                    "contract_patch_id": contract_patch_id,
                },
            )
            self._event_log.log_version_event(
                project_id=session["project_id"],
                event_type="confirmed",
                scope_type=session["scope_type"],
                payload={"contract_version_id": contract_version_id},
                contract_version_id=contract_version_id,
                scope_id=session.get("scope_id"),
            )
            # ── 自动 stale 传播（SAVEPOINT 已释放，契约已确认）──
            stale_mark = None
            if stale_manager is not None:
                stale_mark = stale_manager.mark_stale_after_contract_change(
                    project_id=project_id,
                    scope_type=contract_scope_type,
                    scope_id=contract_scope_id,
                    contract_version_id=contract_version_id,
                )
            return ConfirmedContractResult(
                decision_session_id=decision_session_id,
                human_decision_id=human_decision_id,
                contract_version_id=contract_version_id,
                contract_patch_id=contract_patch_id,
                contract_changelog_id=contract_changelog_id,
                after_hash=new_hash,
                stale_mark=stale_mark,
            )

    def _mark_session_stale(self, decision_session_id: int) -> None:
        """把 awaiting_confirm 的 session 标记为 stale。

        用于冲突检测拒绝路径：base version 在 session 存续期间被改过，
        标 stale 后同 scope 可开新 session（stale 不在互斥 index 的活跃集合内）。
        """
        now = now_utc_iso()
        self.conn.execute(
            """
            UPDATE writing_decision_sessions
            SET status = 'stale', updated_at = ?
            WHERE decision_session_id = ? AND status = 'awaiting_confirm'
            """,
            (now, decision_session_id),
        )
        self._event_log.log_session_event(decision_session_id, "stale", {"reason": "base_version_changed"})

    def _return_to_collecting(self, decision_session_id: int, option_set_id: int) -> None:
        now = now_utc_iso()
        try:
            self.conn.execute("SAVEPOINT decision_option_back")
            self.conn.execute(
                "UPDATE writing_decision_option_sets SET status = 'cancelled' WHERE option_set_id = ?",
                (option_set_id,),
            )
            updated = self.conn.execute(
                """
                UPDATE writing_decision_sessions
                SET status = 'collecting', selected_option = NULL, updated_at = ?
                WHERE decision_session_id = ? AND status = 'awaiting_confirm'
                """,
                (now, decision_session_id),
            ).rowcount
            if updated != 1:
                raise DataIntegrityError(f"decision session cannot return to collecting: {decision_session_id}")
        except Exception:
            self.conn.execute("ROLLBACK TO decision_option_back")
            self.conn.execute("RELEASE decision_option_back")
            raise
        else:
            self.conn.execute("RELEASE decision_option_back")


def _validate_options(options: Sequence[dict[str, object]], recommended_option: int | None) -> None:
    if not 1 <= len(options) <= 8:
        raise DataIntegrityError("option set must contain 1-8 options")
    if recommended_option is not None and not 1 <= recommended_option <= len(options):
        raise DataIntegrityError("recommended option must reference an existing option")


def _next_option_version(conn: sqlite3.Connection, decision_session_id: int) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(version), 0) + 1 FROM writing_decision_option_sets WHERE decision_session_id = ?",
        (decision_session_id,),
    ).fetchone()
    return int(row[0])


def _load_active_option_set(conn: sqlite3.Connection, decision_session_id: int) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT option_set_id, version, options_json, regenerate_count
        FROM writing_decision_option_sets
        WHERE decision_session_id = ? AND status = 'active'
        """,
        (decision_session_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"decision session has no active option set: {decision_session_id}")
    return {
        "option_set_id": int(row[0]),
        "version": int(row[1]),
        "options_json": str(row[2]),
        "regenerate_count": int(row[3]),
    }


def _load_session_for_confirm(conn: sqlite3.Connection, decision_session_id: int) -> dict[str, object]:
    row = conn.execute(
        """
        SELECT project_id, status, before_hash, parsed_patch_json,
               readback_text, source_hashes_json, scope_type, scope_id
        FROM writing_decision_sessions
        WHERE decision_session_id = ?
        """,
        (decision_session_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"decision session not found: {decision_session_id}")
    if str(row[1]) != "awaiting_confirm":
        raise DataIntegrityError(
            f"decision session is not awaiting confirmation: {decision_session_id}"
        )
    return {
        "project_id": int(row[0]),
        "status": str(row[1]),
        "before_hash": None if row[2] is None else str(row[2]),
        "parsed_patch_json": str(row[3]),
        "readback_text": str(row[4]) if row[4] is not None else "",
        "source_hashes_json": str(row[5]) if row[5] is not None else "[]",
        "scope_type": str(row[6]),
        "scope_id": None if row[7] is None else str(row[7]),
    }


def _insert_contract_confirm_decision(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    actor: str,
    reason: str,
    preconditions: dict[str, object],
    now: str,
) -> int:
    cursor = conn.execute(
        """
        INSERT INTO writing_human_decisions
            (project_id, decision_type, actor, reason, preconditions_json,
             quality_report_json, hard_quality_override, created_at)
        VALUES (?, 'contract_confirm', ?, ?, ?, '{}', 0, ?)
        """,
        (
            project_id,
            actor,
            reason,
            _json(preconditions),
            now,
        ),
    )
    return int(cursor.lastrowid)


def _resolve_base_contract_version_id(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    scope_type: str,
    scope_id: str | None,
) -> int | None:
    """返回当前 confirmed/locked 契约版本作为 patch 的 base；首次确认返回 None。"""
    row = conn.execute(
        """
        SELECT contract_version_id
        FROM writing_contract_versions
        WHERE project_id = ? AND scope_type = ? AND COALESCE(scope_id, '') = COALESCE(?, '')
          AND status IN ('confirmed','locked')
        ORDER BY version DESC
        LIMIT 1
        """,
        (project_id, scope_type, scope_id),
    ).fetchone()
    return None if row is None else int(row[0])


def _current_scope_version_hash(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    scope_type: str,
    scope_id: str | None,
) -> str | None:
    """返回当前 scope 最新 confirmed/locked version 的 contract_hash；首次确认前为 None。

    在 ``start`` 时调用，把 base version 的 hash 写入 session 的 before_hash，
    供 ``confirm_and_apply`` 检测期间是否有人改过同一 scope 的契约。
    """
    row = conn.execute(
        """
        SELECT contract_hash
        FROM writing_contract_versions
        WHERE project_id = ? AND scope_type = ? AND COALESCE(scope_id, '') = COALESCE(?, '')
          AND status IN ('confirmed','locked')
        ORDER BY version DESC
        LIMIT 1
        """,
        (project_id, scope_type, scope_id),
    ).fetchone()
    return None if row is None else str(row[0])


def _version_hash_by_id(conn: sqlite3.Connection, version_id: int) -> str | None:
    """按 contract_version_id 取 contract_hash。"""
    row = conn.execute(
        "SELECT contract_hash FROM writing_contract_versions WHERE contract_version_id = ?",
        (version_id,),
    ).fetchone()
    return None if row is None else str(row[0])


def _next_contract_version(
    conn: sqlite3.Connection,
    *,
    project_id: int,
    scope_type: str,
    scope_id: str | None,
) -> int:
    row = conn.execute(
        """
        SELECT COALESCE(MAX(version), 0) + 1
        FROM writing_contract_versions
        WHERE project_id = ? AND scope_type = ? AND COALESCE(scope_id, '') = COALESCE(?, '')
        """,
        (project_id, scope_type, scope_id),
    ).fetchone()
    return int(row[0])


def _contract_hash(contract_payload: dict[str, object], source_hashes: Sequence[str]) -> str:
    payload = json.dumps(
        {"contract": contract_payload, "source_hashes": list(source_hashes)},
        ensure_ascii=False,
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)
