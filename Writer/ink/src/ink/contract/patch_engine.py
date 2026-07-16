"""Contract patch engine — 厚应用层。

把 AI 输出的 JSON-Patch 及 readback 文本经过 6 步校验流水线后
应用到当前 base contract，返回新 payload 及 coverage 更新建议。

纯标准库依赖，不引入 pydantic / jsonschema。

用法::

    engine = ContractPatchEngine(conn, readback_verifier=LLMReadbackVerifier(gateway, project_id))
    result = engine.apply_and_validate(
        project_id=1, scope_type="chapter", scope_id="ch-3",
        patch=[{"op": "replace", "path": "scene_hook", "value": "new scene"}],
        readback_text="更新第三章场景钩子",
        source_clause_ids=[101, 102],
        source_hashes=["abc", "def"],
    )
    # → PatchApplicationResult(new_payload=..., applied_ops=..., affected_field_paths=["scene_hook"])
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass, field
from typing import Any, Protocol, Sequence

from ink.contract.fields import list_required_fields, validate_field_path
from ink.contract.jsonpatch import apply_patch, patch_paths
from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import ContractPatchError


# ── 返回值 ─────────────────────────────────────────────────


@dataclass(frozen=True)
class PatchApplicationResult:
    """``apply_and_validate`` 的返回值。

    调用方（通常是 ``confirm_and_apply``）拿到该结果后应：

    * ``new_payload`` → 作为 ``contract_payload`` 写库。
    * ``applied_ops`` → 写入 ``writing_contract_patches.patch_json``。
    * ``affected_field_paths`` → 更新 ``writing_source_coverage_matrix``。
    * ``base_contract_version_id`` → 关联 ``base_contract_version_id``。
    """

    new_payload: dict[str, Any]
    applied_ops: list[dict[str, Any]]
    affected_field_paths: list[str] = field(default_factory=list)
    base_contract_version_id: int | None = None


# ── 回读校验协议 ──────────────────────────────────────────


class ReadbackVerifier(Protocol):
    """回读一致性校验协议。

    比对 human-editor readback 文本与 JSON-Patch 是否语义一致，
    返回 ``True`` 表示校验通过，``False`` 表示不通过。
    """

    def verify(
        self,
        *,
        patch: list[dict[str, Any]],
        readback_text: str,
        scope_type: str,
    ) -> bool: ...


# ═══════════════════════════════════════════════════════════
#  LLMReadbackVerifier — 默认实现
# ═══════════════════════════════════════════════════════════

_VERIFY_PROMPT = """\
You are verifying a contract editing readback.

A human editor reviewed the following JSON-Patch operations and summarized them \
in natural language as a readback.

Patch:
{patch_json}

Human readback:
{readback_text}

Is the readback semantically consistent with the patch? \
Answer only 'true' if it correctly reflects the changes, or 'false' if it \
misrepresents, omits, or contradicts the patch."""


class LLMReadbackVerifier:
    """默认 ReadbackVerifier 实现：通过 LLM 比对语义一致性。

    构造时注入 ``LLMGateway``； ``verify()`` 方法向 LLM 发送结构化 prompt，
    要求仅输出 ``true`` / ``false``。

    LLM call 失败（网络错误、非 true/false 输出、超时）均返回 ``False``。
    """

    _GATEWAY_MODEL = "claude-sonnet-4-20250514"

    def __init__(
        self,
        gateway: LLMGateway,
        project_id: int,
        *,
        idempotency_prefix: str = "readback",
        model: str | None = None,
    ) -> None:
        self._gateway = gateway
        self._project_id = project_id
        self._prefix = idempotency_prefix
        self._model = model or self._GATEWAY_MODEL

    def verify(
        self,
        *,
        patch: list[dict[str, Any]],
        readback_text: str,
        scope_type: str,
    ) -> bool:
        if not readback_text.strip():
            return False
        prompt = _VERIFY_PROMPT.format(
            patch_json=json.dumps(patch, ensure_ascii=False, indent=2),
            readback_text=readback_text,
        )
        id_key = _sha256(self._prefix + "|" + prompt)
        try:
            result: ModelResult = self._gateway.call(
                project_id=self._project_id,
                shot_id=None,
                run_id=None,
                call_type="readback_verify",
                prompt_id=None,
                prompt_text=prompt,
                model_name=self._model,
                idempotency_key=id_key,
            )
        except Exception:
            return False
        text = result.text.strip().lower()
        return text == "true"


# ═══════════════════════════════════════════════════════════
#  ContractPatchEngine — 核心引擎
# ═══════════════════════════════════════════════════════════


class ContractPatchEngine:
    """契约 patch 引擎 —— 6 步校验流水线。

    :param conn: 数据库连接（用于加载 base contract）。
    :param readback_verifier: 可选回读校验器；为 ``None`` 时跳过步骤 6。

    流水线步骤:

    0. 形态校验（``validate_patch_shape``，在 ``record_ai_parse`` 时提前调用）
    1. Schema 白名单校验
    2. 同 patch intra‑conflict 检测
    3. 加载 base contract payload
    4. 应用 ``apply_patch``
    5. 必填字段检查
    6. 回读一致性校验（可选）
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        *,
        readback_verifier: ReadbackVerifier | None = None,
    ) -> None:
        self.conn = conn
        self._verifier = readback_verifier

    # ── 第 0 步：解析时形态校验 ──────────────────────────────
    # 在 record_ai_parse 时提前调用，尽早拒绝格式非法 patch。

    @staticmethod
    def validate_patch_shape(patch: object) -> list[dict[str, Any]]:
        """拒绝形态非法的 patch（不涉及 scope）。

        * 必须是 ``list[dict]``。
        * 非空。
        * 每个 op 必须有合法的 ``op`` 和 ``path`` 字段。
        * ``move`` op 必须有 ``from`` 字段。

        :returns: 校验通过后原值（已断言类型），可直接用于后续步骤。
        :raises ContractPatchError: 形态非法时抛出。
        """
        if not isinstance(patch, list):
            raise ContractPatchError("patch must be a list of operations")
        if not patch:
            raise ContractPatchError("patch must not be empty")
        for i, op in enumerate(patch):
            if not isinstance(op, dict):
                raise ContractPatchError(f"op #{i} must be a dict")
            kind = op.get("op")
            if not isinstance(kind, str) or kind not in {"add", "remove", "replace", "move"}:
                raise ContractPatchError(
                    f"op #{i} has unsupported or missing op: {kind!r}"
                )
            path = op.get("path")
            if not isinstance(path, str) or not path:
                raise ContractPatchError(f"op #{i} ({kind}) missing or invalid path")
            if kind == "move":
                src = op.get("from")
                if not isinstance(src, str) or not src:
                    raise ContractPatchError(
                        f"op #{i} (move) missing or invalid 'from'"
                    )
        return patch  # type: ignore[return-value]  # 已断言

    # ── 主入口：6 步流水线 ──────────────────────────────────

    def apply_and_validate(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
        patch: list[dict[str, Any]],
        readback_text: str,
        source_clause_ids: Sequence[int],
        source_hashes: Sequence[str],
    ) -> PatchApplicationResult:
        """完整 6 步校验流水线。

        :param project_id: 项目 ID。
        :param scope_type: ``book`` / ``volume`` / ``part`` / ``chapter``。
        :param scope_id: 作用域 ID（如 ``ch-3``）。
        :param patch: JSON-Patch 操作列表。
        :param readback_text: 人类 editor 的读回确认文本。
        :param source_clause_ids: 来源原子条款 ID 列表。
        :param source_hashes: 来源 hash 列表。
        :returns: 包含应用后 payload、影响路径、base 版本 ID 的结果。
        :raises ContractPatchError: 任意步骤失败时抛出（不写库）。
        """
        # 步骤 0：形态校验（防御重复校验）
        patch = self.validate_patch_shape(patch)

        # 步骤 1：schema 白名单校验
        self._validate_schema(patch, scope_type)

        # 步骤 2：intra‑conflict 检测
        self._check_intra_patch_conflicts(patch)

        # 步骤 3：加载 base contract
        base_version_id, base_payload = self._load_base_contract_payload(
            project_id=project_id,
            scope_type=scope_type,
            scope_id=scope_id,
        )

        # 步骤 4：应用 patch
        new_payload = apply_patch(base_payload or {}, patch)

        # 步骤 5：必填字段检查
        self._check_required_fields(new_payload, scope_type)

        # 步骤 6：回读一致性校验
        if self._verifier is not None:
            self._verify_readback(patch, readback_text, scope_type)

        # 提取所有受影响字段路径
        paths = patch_paths(patch)

        return PatchApplicationResult(
            new_payload=new_payload,
            applied_ops=patch,
            affected_field_paths=paths,
            base_contract_version_id=base_version_id,
        )

    # ── 步骤 1：Schema 白名单 ──────────────────────────────

    @staticmethod
    def _validate_schema(
        patch: list[dict[str, Any]],
        scope_type: str,
    ) -> None:
        """严格校验 patch 的每个 path 是否在 scope_type 的白名单内。"""
        invalid: list[str] = []
        for op in patch:
            path = op.get("path")
            if isinstance(path, str) and not validate_field_path(scope_type, path):
                invalid.append(path)
        if invalid:
            raise ContractPatchError(
                f"patch contains paths not in scope '{scope_type}' whitelist: "
                f"{', '.join(sorted(set(invalid)))}"
            )

    # ── 步骤 2：Intra‑conflict ─────────────────────────────

    @staticmethod
    def _check_intra_patch_conflicts(
        patch: list[dict[str, Any]],
    ) -> None:
        """同一 patch 中多个 op 改同 path → 报错。"""
        path_counts: dict[str, int] = {}
        for op in patch:
            path = op.get("path")
            if isinstance(path, str) and path:
                path_counts[path] = path_counts.get(path, 0) + 1
        duplicates = [p for p, count in path_counts.items() if count > 1]
        if duplicates:
            raise ContractPatchError(
                f"patch contains multiple operations targeting the same field path: "
                f"{', '.join(duplicates)}"
            )

    # ── 步骤 3：加载 base ─────────────────────────────────

    def _load_base_contract_payload(
        self,
        *,
        project_id: int,
        scope_type: str,
        scope_id: str | None,
    ) -> tuple[int | None, dict[str, Any] | None]:
        """加载最新 confirmed/locked 契约版本。

        :returns: ``(version_id, payload_dict)``，首次确认返回 ``(None, None)``。
        """
        row = self.conn.execute(
            """
            SELECT contract_version_id, contract_json
            FROM writing_contract_versions
            WHERE project_id = ? AND scope_type = ? AND COALESCE(scope_id, '') = COALESCE(?, '')
              AND status IN ('confirmed', 'locked')
            ORDER BY version DESC LIMIT 1
            """,
            (project_id, scope_type, scope_id),
        ).fetchone()
        if row is None:
            return None, None
        payload = json.loads(str(row[1]))
        if not isinstance(payload, dict):
            payload = {}
        return int(row[0]), payload

    # ── 步骤 5：必填字段 ──────────────────────────────────

    @staticmethod
    def _check_required_fields(
        payload: dict[str, Any],
        scope_type: str,
    ) -> None:
        """确认 payload 包含 scope 的所有必填字段（含嵌套）。"""
        missing: list[str] = []
        for path in list_required_fields(scope_type):
            parts = path.split(".")
            node: Any = payload
            found = True
            for part in parts:
                if isinstance(node, dict) and part in node:
                    node = node[part]
                else:
                    found = False
                    break
            if not found:
                missing.append(path)
        if missing:
            raise ContractPatchError(
                f"required fields missing after patch: {', '.join(missing)}"
            )

    # ── 步骤 6：回读校验 ──────────────────────────────────

    def _verify_readback(
        self,
        patch: list[dict[str, Any]],
        readback_text: str,
        scope_type: str,
    ) -> None:
        """调 verifier 比对 readback 与 patch 语义一致性。"""
        if self._verifier is None:
            return
        if not readback_text.strip():
            raise ContractPatchError(
                "readback_text is empty; readback verification required"
            )
        ok = self._verifier.verify(
            patch=patch,
            readback_text=readback_text,
            scope_type=scope_type,
        )
        if not ok:
            raise ContractPatchError(
                "readback verification failed: readback does not match patch"
            )


# ── 工具函数 ──────────────────────────────────────────────


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
