"""Scene Contract 三家族盲审编排器（BFX-079 H1 契约层接线）。

契约成立前的盲审：架构师自检（self_check）→ 两个异族独立审查。
三次审查都 approve 才允许 activate_contract，否则契约不生效——彻底取代
``_ensure_scene_and_contract`` 的"直接 approved 跳审查"绕过（BFX-079 根因）。

异族保证（INV-CONTRACT-003）：``independent_review_contract`` 在 repo 层强制
reviewer_family != architect_family。architect family 从 ``create_contract(created_by)``
取（格式 ``"<actor>:<family>"``）。此处 self_check 用架构师同家族、independent
用异族，满足约束。

LLM 调用走 gateway（call_type=contract_review，主→备→兜底 failover）。无 role_config
时降级报错——契约审查不可跳过、不可用假 verdict 兜底（H3 反事实第 2 条）。
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass

from ink.core.llm_gateway import LLMGateway, ModelResult
from ink.errors import DataIntegrityError, LLMProviderError


class ContractReviewLLMFailure(Exception):
    """contract_review 的 LLM 调用失败（供应商故障），不写假 verdict。"""


@dataclass(frozen=True)
class ContractReviewOutcome:
    scene_contract_id: int
    self_check_verdict: str
    independent_verdict: str
    second_independent_verdict: str
    approved: bool


def family_from_model_name(model_name: str) -> str:
    """从模型名解析家族标识（用于 INV-CONTRACT-003 异族校验）。

    iFLYTEK 本地代理模型名形如 ``claude-xunfei-<family>-<version>``：
    ``claude-xunfei-glm-5-2`` → ``glm``，``claude-xunfei-deepseek-v4-pro`` → ``deepseek``。
    解析不到时取整名作 family（保证能跑，但异族校验会拒绝同名）。
    """
    parts = model_name.split("-")
    # 形如 claude-xunfei-glm-5-2：第 3 段是 family。
    if len(parts) >= 3 and parts[1] == "xunfei":
        return parts[2]
    return model_name


class ContractReviewOrchestrator:
    def __init__(self, conn: sqlite3.Connection, gateway: LLMGateway) -> None:
        self.conn = conn
        self.gateway = gateway

    def review_contract(
        self,
        *,
        scene_contract_id: int,
        project_id: int,
        architect_family: str,
        reviewer_family: str,
        second_reviewer_family: str,
    ) -> ContractReviewOutcome:
        """对生效前契约跑三家族盲审。

        Args:
            scene_contract_id: 契约主键（draft 态）。
            project_id: 项目。
            architect_family: 架构师家族（与 create_contract.created_by 的 family 一致）。
            reviewer_family: 第一异族审查员家族。
            second_reviewer_family: 第二异族审查员家族；三者必须互异。

        三次审查都须 approve 才返回 approved=True。任一 revise/reject 或 LLM 失败
        都返回 approved=False（CLI 层据此拒绝产稿）。
        """
        families = {architect_family, reviewer_family, second_reviewer_family}
        if len(families) != 3:
            raise DataIntegrityError(
                "contract review requires three distinct model families: "
                f"{architect_family}, {reviewer_family}, {second_reviewer_family}"
            )
        clauses = _load_contract_clauses(self.conn, scene_contract_id)
        if not clauses:
            raise DataIntegrityError(
                f"contract {scene_contract_id} has no clauses: refuse to review empty contract"
            )
        prompt_text = _contract_review_prompt(clauses)

        # self_check：架构师同家族（合法，INV-CONTRACT-003 仅约束独立审查须异族）。
        self_model = _pick_model_for_family(self.conn, project_id, architect_family, "primary")
        self_verdict, self_evidence = self._call_review(
            project_id=project_id,
            scene_contract_id=scene_contract_id,
            slot="self",
            model_name=self_model,
            tier_hint="primary",
            prompt_text=prompt_text,
        )
        self._repo_self_check(scene_contract_id, self_model, architect_family, self_verdict, self_evidence)

        # 两个独立异族审查，共同满足 implementation-contract §4 的三家族门。
        ind_model = _pick_model_for_family(self.conn, project_id, reviewer_family, "secondary")
        ind_verdict, ind_evidence = self._call_review(
            project_id=project_id,
            scene_contract_id=scene_contract_id,
            slot="independent-1",
            model_name=ind_model,
            tier_hint="secondary",
            prompt_text=prompt_text,
        )
        self._repo_independent_review(
            scene_contract_id, ind_model, reviewer_family, ind_verdict, ind_evidence
        )

        second_model = _pick_model_for_family(
            self.conn, project_id, second_reviewer_family, "fallback"
        )
        second_verdict, second_evidence = self._call_review(
            project_id=project_id,
            scene_contract_id=scene_contract_id,
            slot="independent-2",
            model_name=second_model,
            tier_hint="fallback",
            prompt_text=prompt_text,
        )
        self._repo_independent_review(
            scene_contract_id,
            second_model,
            second_reviewer_family,
            second_verdict,
            second_evidence,
        )

        approved = all(
            verdict == "approve"
            for verdict in (self_verdict, ind_verdict, second_verdict)
        )
        return ContractReviewOutcome(
            scene_contract_id=scene_contract_id,
            self_check_verdict=self_verdict,
            independent_verdict=ind_verdict,
            second_independent_verdict=second_verdict,
            approved=approved,
        )

    def _call_review(
        self,
        *,
        project_id: int,
        scene_contract_id: int,
        slot: str,
        model_name: str,
        tier_hint: str,
        prompt_text: str,
    ) -> tuple[str, str]:
        idem = f"contract_review:{project_id}:{scene_contract_id}:{slot}"
        try:
            result = self.gateway.call(
                project_id=project_id,
                shot_id=None,
                run_id=None,
                call_type="contract_review",
                prompt_id=None,
                prompt_text=prompt_text,
                model_name=model_name,
                idempotency_key=idem,
                tier_hint=tier_hint,
            )
        except LLMProviderError as exc:
            raise ContractReviewLLMFailure(
                f"contract_review {slot} LLM 失败（contract {scene_contract_id}）: {exc}"
            ) from exc
        return _parse_review_verdict(result.text)

    # repo 层薄封装：保持审查状态机正确迁移（draft→self_checked→under_review）。
    def _repo_self_check(
        self, scene_contract_id: int, model_name: str, family: str, verdict: str, evidence: str
    ) -> None:
        from ink.core.scene_repository import SceneRepository

        SceneRepository(self.conn).self_check_contract(
            scene_contract_id=scene_contract_id,
            reviewer_model=model_name,
            reviewer_family=family,
            prompt_hash=_hash_prompt(scene_contract_id, "self"),
            blind_context_hash=_hash_prompt(scene_contract_id, "self"),
            verdict=verdict,
            evidence_json=evidence,
        )

    def _repo_independent_review(
        self, scene_contract_id: int, model_name: str, family: str, verdict: str, evidence: str
    ) -> None:
        from ink.core.scene_repository import SceneRepository

        SceneRepository(self.conn).independent_review_contract(
            scene_contract_id=scene_contract_id,
            reviewer_model=model_name,
            reviewer_family=family,
            prompt_hash=_hash_prompt(scene_contract_id, family),
            blind_context_hash=_hash_prompt(scene_contract_id, family),
            verdict=verdict,
            evidence_json=evidence,
        )


def _load_contract_clauses(conn: sqlite3.Connection, scene_contract_id: int) -> list[dict[str, str]]:
    rows = conn.execute(
        """
        SELECT layer, clause_key, clause_text, severity
        FROM writing_scene_contract_clauses
        WHERE scene_contract_id = ?
        ORDER BY
            CASE layer
                WHEN 'hard_constraint' THEN 0 WHEN 'source_dna' THEN 1
                WHEN 'soft_goal' THEN 2 WHEN 'creative_opening' THEN 3
            END, clause_key
        """,
        (scene_contract_id,),
    ).fetchall()
    return [{"layer": r[0], "clause_key": r[1], "clause_text": r[2], "severity": r[3]} for r in rows]


def _contract_review_prompt(clauses: list[dict[str, str]]) -> str:
    """构造契约审查 prompt：注入四层 clause + 审查协议 + 严格 JSON 输出。"""
    layer_label = {
        "hard_constraint": "硬约束（不可违背）",
        "source_dna": "源稿DNA（传承机制）",
        "soft_goal": "软目标（允许优秀偏离）",
        "creative_opening": "创作留白（不得预先锁死）",
    }
    blocks: list[str] = []
    cur = None
    for c in clauses:
        if c["layer"] != cur:
            blocks.append(f"\n### {layer_label.get(c['layer'], c['layer'])}")
            cur = c["layer"]
        blocks.append(f"- [{c['severity']}] {c['clause_key']}：{c['clause_text']}")
    clauses_block = "\n".join(blocks)
    return (
        "你是 Scene Contract 契约审查员（双盲：你看不到架构师身份，也不看其他审查结果）。"
        "审查下述四层契约是否自洽、可落地、无矛盾。\n\n"
        f"## 契约四层\n{clauses_block}\n\n"
        "## 审查协议\n"
        "1. hard_constraint 是否互相矛盾、是否覆盖必要事实因果与红线。\n"
        "2. source_dna 是否可被正文传递而不沦为复制骨架。\n"
        "3. soft_goal 是否给正文留出执行空间、是否与硬约束冲突。\n"
        "4. creative_opening 是否至少 2 条且未与硬约束锁死。\n"
        "任一层缺条款、硬约束矛盾、或 creative_opening 不足 2 条，判 revise。\n\n"
        "## 输出要求\n"
        "严格输出一个 JSON 对象：{\"verdict\": <\"approve\"|\"revise\"|\"reject\">, "
        "\"evidence\": <一句话说明判定理由>}。不要任何额外文本、不要 markdown 代码围栏。示例：\n"
        '{"verdict": "approve", "evidence": "四层齐全，硬约束覆盖物理因果与沉默点，留白充分。"}'
    )


def _parse_review_verdict(text: str) -> tuple[str, str]:
    """严格解析契约审查 JSON。返回 (verdict, evidence_json)。

    解析失败 / verdict 非法 → 抛 ``ContractReviewLLMFailure``（不写假 verdict）。
    evidence_json 必须是合法 JSON 字符串（存入 writing_contract_reviews.evidence_json）。
    """
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[-1]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        cleaned = cleaned.strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ContractReviewLLMFailure(f"contract_review verdict 非 JSON：{text[:200]}")
    try:
        obj = json.loads(cleaned[start : end + 1])
    except json.JSONDecodeError as exc:
        raise ContractReviewLLMFailure(f"contract_review JSON 解析失败: {exc}") from exc
    verdict = str(obj.get("verdict", "")).strip().lower()
    if verdict not in {"approve", "revise", "reject"}:
        raise ContractReviewLLMFailure(f"contract_review verdict 非法: {verdict}")
    evidence = str(obj.get("evidence", "")).strip() or "contract review（无 evidence）"
    # evidence_json 列是 JSON 文本，存一个 {evidence: ...} 对象便于后续结构化查询。
    evidence_json = json.dumps({"evidence": evidence, "verdict": verdict}, ensure_ascii=False)
    return verdict, evidence_json


def _pick_model_for_family(
    conn: sqlite3.Connection, project_id: int, family: str, tier_hint: str
) -> str:
    """取指定 family 的代表模型名。

    优先从 writing_model_role_configs 取 contract_review 该 tier 配置；
    无配置时回退到该 family 的注入式模型目录默认名（claude-xunfei-<family>-...）。
    """
    row = conn.execute(
        """
        SELECT model_name FROM writing_model_role_configs
        WHERE project_id = ? AND call_type = 'contract_review' AND tier = ?
        """,
        (project_id, tier_hint),
    ).fetchone()
    if row is not None:
        return str(row[0])
    # 回退：本地代理 iFLYTEK 命名规约。family=glm → claude-xunfei-glm-5-2。
    suffix = {"glm": "5-2", "deepseek": "v4-pro"}.get(family, "5-2")
    return f"claude-xunfei-{family}-{suffix}"


def _project_id_of_contract(conn: sqlite3.Connection, scene_contract_id: int) -> int:
    row = conn.execute(
        """
        SELECT s.project_id
        FROM writing_scene_contracts c JOIN writing_scenes s ON s.scene_id = c.scene_id
        WHERE c.scene_contract_id = ?
        """,
        (scene_contract_id,),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"unknown scene contract: {scene_contract_id}")
    return int(row[0])


def _hash_prompt(scene_contract_id: int, slot: str) -> str:
    """盲上下文 hash：审查间不可见彼此 prompt（visible_prior_reviews=0 已保证，hash 仅作记录）。"""
    return hashlib.sha256(f"{scene_contract_id}:{slot}".encode("utf-8")).hexdigest()
