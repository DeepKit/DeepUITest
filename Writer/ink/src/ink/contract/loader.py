from __future__ import annotations

import json
import sqlite3
from typing import Iterable

from ink.contract.generated.dtos import BookContextDTO, ChapterContractDTO, ShotContractDTO
from ink.errors import DataIntegrityError


def load_shot_contract(conn: sqlite3.Connection, shot_id: str, run_id: int) -> ShotContractDTO:
    row = conn.execute(
        """
        SELECT
            s.shot_id,
            s.run_id,
            ml.events,
            ml.beats,
            ml.information_releases,
            aw.forbidden_facts,
            aw.forbidden_words,
            aw.pov_only,
            sc.location,
            sc.time_of_day,
            sc.characters_present,
            sc.character_positions,
            pa.persona,
            pa.intensity,
            pa.is_creative_shot,
            pa.is_suspense_shot,
            soft.relaxable_rules,
            soft.deviation_budget
        FROM writing_shots s
        JOIN writing_shot_contracts c ON c.shot_contract_id = s.shot_contract_id
        JOIN writing_shot_must_land ml ON ml.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_anti_write aw ON aw.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_scene_contract sc ON sc.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_persona_assignment pa ON pa.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_soft_constraints soft ON soft.shot_contract_id = c.shot_contract_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"shot contract projection not found: {shot_id}/{run_id}")

    return ShotContractDTO(
        shot_id=str(row[0]),
        run_id=int(row[1]),
        must_land={
            "events": json.loads(row[2]),
            "beats": json.loads(row[3]),
            "information_releases": json.loads(row[4]),
        },
        anti_write={
            "forbidden_facts": json.loads(row[5]),
            "forbidden_words": json.loads(row[6]),
            "pov_only": json.loads(row[7]),
        },
        scene_contract={
            "location": row[8],
            "time_of_day": row[9],
            "characters_present": json.loads(row[10]),
            "character_positions": json.loads(row[11]),
        },
        persona_assignment={
            "persona": row[12],
            "intensity": json.loads(row[13]),
            "is_creative_shot": bool(row[14]),
            "is_suspense_shot": bool(row[15]),
        },
        soft_constraints={
            "relaxable_rules": json.loads(row[16]),
            "deviation_budget": float(row[17]),
        },
    )


def _flatten_json_values(values: Iterable[object]) -> list[str]:
    """把 meta_contracts 的 JSON 列值（dict/list/scalar）拍平成可读文本行。

    - dict：按 "key: value" 或 "key: [v1, v2]" 渲染每对
    - list/tuple：每个元素一行（元素为 dict 时展开为 "k: v"）
    - str/int/float：直接一行
    空集合（[]/{}/""）不产生任何行。
    """
    lines: list[str] = []

    def _emit(prefix: str, val: object) -> None:
        if val is None or val == "" or val == [] or val == {}:
            return
        if isinstance(val, dict):
            for k, v in val.items():
                if isinstance(v, (dict, list)):
                    _emit(f"{prefix}{k}" if prefix else str(k), v)
                elif v is None or v == "" or v == [] or v == {}:
                    continue
                else:
                    lines.append(f"{prefix}{k}: {v}" if prefix else f"{k}: {v}")
        elif isinstance(val, (list, tuple)):
            for item in val:
                if isinstance(item, dict):
                    _emit(prefix, item)
                elif item is None or item == "" or item == [] or item == {}:
                    continue
                else:
                    # 列表里的标量项：有 prefix（来自父 dict key）时输出 "key: item"，否则裸输出。
                    lines.append(f"{prefix}: {item}" if prefix else str(item))
        else:
            lines.append(f"{prefix}{val}" if prefix else str(val))

    for v in values:
        _emit("", v)
    return lines


def load_book_context(conn: sqlite3.Connection, project_id: int) -> BookContextDTO:
    """加载 book 层上下文喂 writer。

    数据源（均取 confirmed）：
    - writing_meta_contracts：world_knowledge→World、narrative_voice+hard_boundaries→Narrative、motif_system→Motif
    - writing_atomic_source_clauses (scope_type='book')：clause_type=world→World、character→Character、plot→Narrative、style→Motif

    Character 唯一来源是 atomic_clauses（meta_contracts 无 character 列），confirmed 为空时 Character 段为空（不阻断）。
    任一数据源缺失（无 meta_contract 行 / 无 atomic 行）均优雅降级返回空 tuple，不抛异常。
    """
    world: list[str] = []
    character: list[str] = []
    narrative: list[str] = []
    motif: list[str] = []

    meta = conn.execute(
        """
        SELECT world_knowledge, narrative_voice, hard_boundaries, motif_system
        FROM writing_meta_contracts
        WHERE project_id = ? AND status = 'confirmed'
        ORDER BY meta_contract_id DESC LIMIT 1
        """,
        (project_id,),
    ).fetchone()
    if meta is not None:
        world_knowledge, narrative_voice, hard_boundaries, motif_system = (
            json.loads(meta[0]), json.loads(meta[1]), json.loads(meta[2]), json.loads(meta[3])
        )
        world.extend(_flatten_json_values([world_knowledge]))
        narrative.extend(_flatten_json_values([narrative_voice, hard_boundaries]))
        motif.extend(_flatten_json_values([motif_system]))

    for clause_type, clause_text in conn.execute(
        """
        SELECT clause_type, clause_text
        FROM writing_atomic_source_clauses
        WHERE project_id = ? AND scope_type = 'book' AND status = 'confirmed'
        ORDER BY atomic_clause_id
        """,
        (project_id,),
    ).fetchall():
        line = str(clause_text).strip()
        if not line:
            continue
        if clause_type == "world":
            world.append(line)
        elif clause_type == "character":
            character.append(line)
        elif clause_type == "plot":
            narrative.append(line)
        elif clause_type == "style":
            motif.append(line)

    # 去重保序（meta 与 atomic 可能重复同一事实）。
    def _dedup(items: list[str]) -> tuple[str, ...]:
        seen: set[str] = set()
        out: list[str] = []
        for it in items:
            if it not in seen:
                seen.add(it)
                out.append(it)
        return tuple(out)

    return BookContextDTO(
        world=_dedup(world),
        character=_dedup(character),
        narrative=_dedup(narrative),
        motif=_dedup(motif),
    )


# ── 章节契约加载（悬疑工程学 8 字段） ────────────────────────────────────────
# 字段名与 contract/fields.py chapter scope 白名单 + outline_to_contract.to_chapter_contract_payload 对齐。
_CHAPTER_SUSPENSE_FIELDS = (
    "pursuit_type",
    "main_engine",
    "emotion_target",
    "silence_point",
    "causal_anchor",
    "hook_type",
    "light_state",
    "chapter_end_hook",
)


def load_chapter_contract(
    conn: sqlite3.Connection, project_id: int, scope_id: str
) -> ChapterContractDTO | None:
    """加载 chapter 层契约（悬疑工程学 8 字段）喂 writer prompt / jury 审计。

    数据源：writing_contract_versions（scope_type='chapter', status='confirmed'）取最新版本的 contract_json。
    confirmed 缺失（无落库）时返回 None，调用方优雅降级（不阻断 task card 编译）。
    任一字段在 payload 中缺失时填空串（frozen dataclass 必须全填，空串表示"未注入"）。
    """
    row = conn.execute(
        """
        SELECT contract_version_id, contract_json
        FROM writing_contract_versions
        WHERE project_id = ? AND scope_type = 'chapter' AND scope_id = ?
              AND status IN ('confirmed', 'locked')
        ORDER BY version DESC LIMIT 1
        """,
        (project_id, scope_id),
    ).fetchone()
    if row is None:
        return None
    contract_version_id, contract_json = row
    payload = json.loads(contract_json)

    # chapter_id 取 payload['chapter_id']['title'] 的数字部分或 scope_id 解析；
    # chapter_id 字段是 dict{title}，取其整数 id（scope_id 形如 ch-1）。
    chapter_id_val = 0
    ch_id_field = payload.get("chapter_id")
    if isinstance(ch_id_field, dict):
        try:
            chapter_id_val = int(ch_id_field.get("id", 0))
        except (TypeError, ValueError):
            chapter_id_val = 0
    if chapter_id_val == 0:
        try:
            chapter_id_val = int(str(scope_id).split("-")[-1])
        except (TypeError, ValueError):
            chapter_id_val = 0

    return ChapterContractDTO(
        chapter_id=chapter_id_val,
        scope_id=scope_id,
        **{f: str(payload.get(f, "") or "") for f in _CHAPTER_SUSPENSE_FIELDS},
    )

