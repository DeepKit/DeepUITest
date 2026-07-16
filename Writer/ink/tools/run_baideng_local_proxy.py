"""《白灯法则》前 10 章本地代理实跑脚本（多专家圆桌评审对象）。

与 ``run_baideng_baseline.py`` 互补：
  - 后者接 iFLYTEK 官方端点（maas-coding-api），模型名走官方别名（xopglm51），key 走 IFLYTEK_API_KEY；
  - 本脚本接**本地 WiseGateway 代理**（127.0.0.1:8000），模型名用代理暴露的
    ``claude-xunfei-*`` 原生名，key 是代理签发的 ``fuyi-kiro-*``（走 LOCAL_PROXY_KEY）。
  - 两者跑相同大纲（24_分章大纲.md 前 10 章）、相同流水线，但产出存不同目录，互不覆盖，
    可作"官方端点 vs 本地代理"两条产稿线的对照。

本脚本产出供**多专家圆桌质量评审**使用：
  - DB：.inkflow/local_proxy/inkflow.db（独立库，不污染官方基线库）
  - 快照：.inkflow/local_proxy/snapshots/（每章 prompt + 12 维分 + 各 draft + winner.md）
  - 合并稿：.inkflow/local_proxy/baideng_ch01-10_winners.md（10 章 winner 合一，圆桌直接读）

用法：
  cd ink && PYTHONPATH=src:tests python tools/run_baideng_local_proxy.py
环境变量 LOCAL_PROXY_KEY 优先从运行环境读取；为兼容既有个人工作站，缺失时才读取
本文件中的 legacy key 常量。代理 key 非 appId:apiKey 格式，不走 IFLYTEK_API_KEY。
讯飞包月按次不计 token，预算不限。
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
import traceback
import hashlib

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tests"))

from ink.core.llm_gateway import LLMGateway, OpenAICompatibleProvider  # noqa: E402
from ink.core.model_role_config import upsert_role_config  # noqa: E402
from ink.errors import LLMProviderError  # noqa: E402
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator  # noqa: E402
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator  # noqa: E402
from ink.pipeline.jury_orchestrator import JuryOrchestrator  # noqa: E402
from ink.pipeline.polish_orchestrator import PolishOrchestrator  # noqa: E402
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator  # noqa: E402
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator  # noqa: E402
from ink.pipeline.write_orchestrator import WriteOrchestrator  # noqa: E402
from ink.schema import initialize_schema  # noqa: E402
from ink.source.outline_parser import parse_outline_file  # noqa: E402
from ink.source.outline_to_contract import to_chapter_contract_payload, to_shot_contract_dict  # noqa: E402
from factories import NOW  # noqa: E402
import seed_industrial_facts  # noqa: E402

PROJECT_ID = 1
SESSION_ID = 100
RUN_ID = 200
CHAPTER_ID = 1
def _chapter_range_from_env() -> list[int]:
    raw = os.environ.get("INK_BENCHMARK_CHAPTERS", "1-10").strip()
    if "-" in raw and "," not in raw:
        start, end = (int(item.strip()) for item in raw.split("-", 1))
        return list(range(start, end + 1))
    return [int(item.strip()) for item in raw.split(",") if item.strip()]


CHAPTERS_TO_RUN = _chapter_range_from_env()

OUTLINE_PATH = os.environ.get(
    "INK_BENCHMARK_OUTLINE",
    r"D:/_Progs/.Story/《白灯法则》/24_分章大纲.md",
)
DB_PATH = os.environ.get(
    "INK_BENCHMARK_DB",
    r"D:/_Progs/.Story/《白灯法则》/.inkflow/local_proxy/inkflow.db",
)
SNAPSHOT_DIR = os.environ.get(
    "INK_BENCHMARK_SNAPSHOTS",
    r"D:/_Progs/.Story/《白灯法则》/.inkflow/local_proxy/snapshots",
)
MERGED_WINNERS_PATH = os.environ.get(
    "INK_BENCHMARK_MERGED",
    r"D:/_Progs/.Story/《白灯法则》/.inkflow/local_proxy/baideng_ch01-10_winners.md",
)

# --- 本地 WiseGateway 代理配置（与 test_e2e_local_proxy.py 一致） ---------
# 代理 key 非 appId:apiKey 格式，是单一 bearer token；base_url 走 /v1（OpenAI 兼容路径）
LEGACY_LOCAL_PROXY_KEY = "fuyi-kiro-17781158558"
LOCAL_PROXY_KEY = os.environ.get("LOCAL_PROXY_KEY", "").strip() or LEGACY_LOCAL_PROXY_KEY
LOCAL_PROXY_BASE = "http://127.0.0.1:8000/v1"
# 模型名用代理暴露的 claude-xunfei-* 原生名（代理透传时 model 字段原样转讯飞）
GLM51 = "claude-xunfei-glm-5-1"
DEEPSEEK_V4PRO = "claude-xunfei-deepseek-v4-pro"
KIMI_K26 = "claude-xunfei-kimi-k2-6"
QWEN_35397B = "claude-xunfei-qwen3-5-397b-a17b"

ROLE_CHAINS: dict[str, list[tuple[str, str]]] = {
    "draft":          [("primary", GLM51), ("secondary", DEEPSEEK_V4PRO), ("tertiary", KIMI_K26)],
    "polish":         [("primary", GLM51), ("secondary", DEEPSEEK_V4PRO), ("tertiary", KIMI_K26)],
    "outline":        [("primary", GLM51), ("secondary", DEEPSEEK_V4PRO), ("tertiary", KIMI_K26)],
    "jury":           [("primary", DEEPSEEK_V4PRO), ("secondary", QWEN_35397B), ("tertiary", GLM51)],
    "chapter_review": [("primary", DEEPSEEK_V4PRO), ("secondary", QWEN_35397B), ("tertiary", GLM51)],
    "book_check":     [("primary", DEEPSEEK_V4PRO), ("secondary", QWEN_35397B), ("tertiary", GLM51)],
}
# draft/outline/polish must preserve the caller-selected model for diversity.
# Their model IDs are already local-proxy IDs, so they use the injected provider.
# Role chains are retained where tier_hint/failover semantics are intentional.
CALL_TYPES = ["jury", "chapter_review", "book_check"]

WRITER_POOL = [GLM51, DEEPSEEK_V4PRO, KIMI_K26]
JURY_POOL = [DEEPSEEK_V4PRO, QWEN_35397B, GLM51, KIMI_K26]


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def build_file_db() -> sqlite3.Connection:
    """删除旧 db → 新建文件 db → schema → project/role/session/run/shot。"""
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        log(f"已删除旧 db: {DB_PATH}")
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys=ON")
    initialize_schema(conn)
    log(f"新建文件 db 并初始化 schema: {DB_PATH}")

    conn.execute(
        """INSERT INTO writing_projects
           (project_id, code, title, writer_model_pool, jury_model_pool,
            shot_quality_floor, dimension_floor, judge_disagreement_max,
            max_calls_per_shot, max_total_llm_calls, created_at)
           VALUES (?, 'baideng', '白灯法则', ?, ?, 75, 60, 25, 45, 110, ?)""",
        (PROJECT_ID, json.dumps(WRITER_POOL), json.dumps(JURY_POOL), NOW),
    )

    for call_type in CALL_TYPES:
        for tier, model_name in ROLE_CHAINS[call_type]:
            upsert_role_config(
                conn, project_id=PROJECT_ID, call_type=call_type, tier=tier,
                model_name=model_name, provider="openai-compatible",
                api_key_env="LOCAL_PROXY_KEY", base_url=LOCAL_PROXY_BASE,
            )

    conn.execute(
        "INSERT INTO writing_sessions (session_id, project_id, started_at) VALUES (?, ?, ?)",
        (SESSION_ID, PROJECT_ID, NOW),
    )
    conn.execute(
        """INSERT INTO writing_runs
           (run_id, project_id, session_id, run_attempt, started_at, status)
           VALUES (?, ?, ?, 1, ?, 'running')""",
        (RUN_ID, PROJECT_ID, SESSION_ID, NOW),
    )

    # 解析大纲，为指定章节建 shot contract + shot
    chapters = parse_outline_file(OUTLINE_PATH)
    by_num = {c.chapter_num: c for c in chapters}
    for chapter_id in CHAPTERS_TO_RUN:
        co = by_num.get(chapter_id)
        if co is None:
            raise RuntimeError(f"大纲未找到第 {chapter_id} 章")
        logical_shot_id = f"ch-{chapter_id:02d}-shot-001"
        cur = conn.execute(
            """INSERT INTO writing_shot_contracts
               (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
               VALUES (?, ?, ?, ?, 'confirmed', ?, ?)""",
            (PROJECT_ID, chapter_id, RUN_ID, logical_shot_id, NOW, NOW),
        )
        scid = int(cur.lastrowid)
        insert_shot_contract_from_dict(conn, scid, to_shot_contract_dict(co))

        # 阶段1：落 chapter 层悬疑契约（writer prompt 第6段 + jury 审计参考）。
        chapter_payload = to_chapter_contract_payload(co)
        chapter_scope_id = f"ch-{chapter_id}"
        chapter_json = json.dumps(chapter_payload, ensure_ascii=False)
        chapter_hash = hashlib.sha256(chapter_json.encode("utf-8")).hexdigest()
        conn.execute(
            """INSERT INTO writing_contract_versions
               (project_id, scope_type, scope_id, version, status,
                contract_json, contract_hash, source_clause_ids_json, created_at)
               VALUES (?, 'chapter', ?, 1, 'confirmed', ?, ?, '[]', ?)""",
            (PROJECT_ID, chapter_scope_id, chapter_json, chapter_hash, NOW),
        )

        conn.execute(
            """INSERT INTO writing_shots
               (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
                status, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)""",
            (f"{logical_shot_id}@{RUN_ID}", PROJECT_ID, chapter_id, scid, RUN_ID,
             logical_shot_id, NOW, NOW),
        )
        log(f"第 {chapter_id} 章 contract 已从大纲解析落库 (shot_contract_id={scid})")

    conn.commit()
    return conn


def insert_shot_contract_from_dict(conn, shot_contract_id: int, d: dict) -> None:
    """shot contract 5 子表 INSERT，对齐 insert_chinese_contract_children 字段。"""
    ml = d["must_land"]
    aw = d["anti_write"]
    sc = d["scene_contract"]
    pe = d["persona"]
    sof = d["soft_constraints"]
    conn.execute(
        "INSERT INTO writing_shot_must_land (shot_contract_id, events, beats, information_releases) VALUES (?,?,?,?)",
        (shot_contract_id, json.dumps(ml["events"], ensure_ascii=False),
         json.dumps(ml["beats"], ensure_ascii=False), json.dumps(ml["information_releases"], ensure_ascii=False)),
    )
    conn.execute(
        "INSERT INTO writing_shot_anti_write (shot_contract_id, forbidden_facts, forbidden_words, pov_only) VALUES (?,?,?,?)",
        (shot_contract_id, json.dumps(aw["forbidden_facts"], ensure_ascii=False),
         json.dumps(aw["forbidden_words"], ensure_ascii=False), json.dumps(aw["pov_only"], ensure_ascii=False)),
    )
    conn.execute(
        "INSERT INTO writing_shot_scene_contract (shot_contract_id, location, time_of_day, characters_present, character_positions) VALUES (?,?,?,?,?)",
        (shot_contract_id, sc["location"], sc["time_of_day"],
         json.dumps(sc["characters_present"], ensure_ascii=False),
         json.dumps(sc["character_positions"], ensure_ascii=False)),
    )
    conn.execute(
        "INSERT INTO writing_shot_persona_assignment (shot_contract_id, persona, intensity, is_creative_shot, is_suspense_shot) VALUES (?,?,?,?,?)",
        (shot_contract_id, pe["persona"], json.dumps(pe["intensity"], ensure_ascii=False),
         int(pe["is_creative_shot"]), int(pe["is_suspense_shot"])),
    )
    conn.execute(
        "INSERT INTO writing_shot_soft_constraints (shot_contract_id, relaxable_rules, deviation_budget) VALUES (?,?,?)",
        (shot_contract_id, json.dumps(sof["relaxable_rules"], ensure_ascii=False), sof["deviation_budget"]),
    )


def chapter_shot(conn, chapter_id):
    row = conn.execute(
        "SELECT shot_id, run_id FROM writing_shots WHERE project_id=? AND chapter_id=? AND run_id=?",
        (PROJECT_ID, chapter_id, RUN_ID),
    ).fetchone()
    return str(row[0]), int(row[1])


def run_shot(conn, shot_id, run_id, gateway):
    PreDraftingOrchestrator(conn, gateway).run_until_prompt_compiled(shot_id, run_id)
    WriteOrchestrator(conn, gateway).produce_drafts(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, run_id)
    PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)


def save_snapshot(conn, chapter_id):
    """保存 baseline 快照：prompt + 12 维分数 + winner draft。"""
    os.makedirs(SNAPSHOT_DIR, exist_ok=True)
    shot_id, _ = chapter_shot(conn, chapter_id)

    # prompt snapshot（经 shot → shot_contract → task_card → prompt 关联）
    prompt_row = conn.execute(
        """SELECT p.full_prompt_text
           FROM writing_prompt_snapshots p
           JOIN writing_shot_task_cards tc ON tc.task_card_id = p.task_card_id
           JOIN writing_shot_contracts sc ON sc.shot_contract_id = tc.shot_contract_id
           JOIN writing_shots s ON s.shot_contract_id = sc.shot_contract_id
           WHERE s.shot_id = ?
           ORDER BY p.prompt_id DESC LIMIT 1""",
        (shot_id,),
    ).fetchone()
    if prompt_row:
        with open(f"{SNAPSHOT_DIR}/baseline_ch{chapter_id}_prompt.txt", "w", encoding="utf-8") as f:
            f.write(prompt_row[0])

    # 12 维分数 + draft 文本
    DIM_COLS = [
        "scene_visual_median", "rhythm_pacing_median", "dialogue_subtext_median",
        "suspense_tension_median", "language_texture_median", "emotional_progression_median",
        "character_believability_median", "structure_landing_median", "reading_fluency_median",
        "motif_theme_fit_median", "chapter_continuity_median", "creative_boundary_median",
    ]
    dim_select = ", ".join(f"j.{c}" for c in DIM_COLS)
    rows = conn.execute(
        f"""SELECT d.draft_id, d.writer_model, d.text,
                  j.final_score, j.quality_gate_passed, j.quality_gate_reasons, j.is_winner,
                  {dim_select}
           FROM writing_drafts d
           LEFT JOIN writing_jury_aggregates j ON j.draft_id = d.draft_id
           WHERE d.shot_id=? ORDER BY d.draft_id""",
        (shot_id,),
    ).fetchall()

    snapshot = {"chapter": chapter_id, "drafts": [], "soft_sealed": False}
    # 查 shot 当前状态——run_shot 末尾走 soft_seal_if_polished，过门则 status=soft_sealed
    status_row = conn.execute(
        "SELECT status FROM writing_shots WHERE shot_id=?", (shot_id,)
    ).fetchone()
    snapshot["soft_sealed"] = bool(status_row and status_row[0] == "soft_sealed")
    for r in rows:
        did, model, text, score, passed, reasons, is_win = r[:7]
        dim_vals = r[7:]
        snapshot["drafts"].append({
            "draft_id": did, "model": model, "is_winner": bool(is_win) if is_win is not None else False,
            "final_score": score, "quality_gate_passed": bool(passed) if passed is not None else None,
            "quality_gate_reasons": reasons,
            "dimensions": {DIM_COLS[i][:-7]: dim_vals[i] for i in range(len(DIM_COLS))},
            "text_len": len(text or ""),
            "text": text or "",
        })

    with open(f"{SNAPSHOT_DIR}/baseline_ch{chapter_id}.json", "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, indent=1)
    log(f"第 {chapter_id} 章 baseline 快照已保存: {SNAPSHOT_DIR}/baseline_ch{chapter_id}.json")

    # 单独存 winner draft 文本
    for d in snapshot["drafts"]:
        if d["is_winner"]:
            with open(f"{SNAPSHOT_DIR}/baseline_ch{chapter_id}_winner.md", "w", encoding="utf-8") as f:
                f.write(d["text"])
            log(f"  winner draft (model={d['model']}, score={d['final_score']}) 已存 winner.md")
            break
    return snapshot


def main():
    os.environ["LOCAL_PROXY_KEY"] = LOCAL_PROXY_KEY
    resume_existing = os.environ.get("INK_BENCHMARK_RESUME") == "1" and os.path.exists(DB_PATH)
    if resume_existing:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("PRAGMA foreign_keys=ON")
        log(f"续跑既有 benchmark DB: {DB_PATH}")
    else:
        conn = build_file_db()
        # Seed the same industrial truth baseline used by production chapter review.
        conn.close()
        seed_rc = seed_industrial_facts.main(PROJECT_ID, DB_PATH)
        if seed_rc != 0:
            raise RuntimeError(f"industrial baseline seed failed: rc={seed_rc}")
        conn = sqlite3.connect(DB_PATH)
        conn.execute("PRAGMA foreign_keys=ON")
    # 注入式 provider 作底；role-config 已落库，gateway 走 role_chain 跨模型 failover
    # 本地代理版：base_url/key 走 LOCAL_PROXY_*；provider_name 标记为 local_proxy 以区分官方端点
    provider = OpenAICompatibleProvider(
        base_url=LOCAL_PROXY_BASE, api_key=LOCAL_PROXY_KEY, max_retries=3, retry_base_delay=1.0,
    )
    gateway = LLMGateway(conn, provider=provider, provider_name="local_proxy")

    shot_id, run_id = chapter_shot(conn, CHAPTERS_TO_RUN[0])
    log(f"开始连续跑 {len(CHAPTERS_TO_RUN)} 章全链路: chapters={CHAPTERS_TO_RUN}")

    for chapter_id in CHAPTERS_TO_RUN:
        shot_id, _ = chapter_shot(conn, chapter_id)
        log(f"--- 第 {chapter_id} 章 start: shot_id={shot_id} ---")
        status = conn.execute(
            "SELECT status FROM writing_shots WHERE shot_id=?",
            (shot_id,),
        ).fetchone()[0]
        if status == "soft_sealed":
            log(f"第 {chapter_id} 章已 soft_sealed，幂等跳过产稿")
        else:
            try:
                run_shot(conn, shot_id, run_id, gateway)
                conn.commit()
                log(f"第 {chapter_id} 章全链路完成")
            except Exception as exc:
                conn.rollback()
                log(f"第 {chapter_id} 章链路中止: {type(exc).__name__}: {str(exc)[:200]}")
                traceback.print_exc()

        save_snapshot(conn, chapter_id)

        # chapter_review + accept（可选，失败不阻断，继续下一章）
        try:
            ChapterReviewOrchestrator(conn, gateway).review_chapter(PROJECT_ID, chapter_id, RUN_ID)
            conn.commit()
            log(f"第 {chapter_id} 章 chapter_review 完成")
        except Exception as exc:
            conn.rollback()
            log(f"第 {chapter_id} 章 chapter_review 失败: {str(exc)[:120]}")

    conn.close()
    log("local_proxy 10 章跑完。")

    # 合并 10 章 winner 成单一文件，供多专家圆桌直接读
    merge_winners()


def merge_winners():
    """把 snapshots/baseline_chN_winner.md 合并成单一 markdown，附每章元信息表。

    圆桌评审读这一份文件即可，无需逐章翻 DB。元信息表含每章 winner 模型/最终分/是否
    soft_sealed，让评审能先看"产稿健康度"再读正文。
    """
    os.makedirs(os.path.dirname(MERGED_WINNERS_PATH), exist_ok=True)
    rows = []
    parts = ["# 《白灯法则》前 10 章 winner 合并稿（本地代理产稿，供圆桌评审）\n",
             "\n",
             "> 产出: tools/run_baideng_local_proxy.py (本地 WiseGateway 代理, 讯飞系模型池)\n",
             "> 大纲: 24_分章大纲.md 卷一/卷二 前 10 章\n",
             "> 流水线: pre_drafting→write→hard_gate→jury→polish→hard_gate→jury→soft_seal→chapter_review\n",
             "\n",
             "## 产稿健康度元信息\n\n",
             "| 章 | winner 模型 | 最终分 | soft_sealed | winner 路径 |\n",
             "|---|---|---|---|---|\n"]
    body = ["\n## 正文\n"]
    missing = []
    for ch in CHAPTERS_TO_RUN:
        wp = os.path.join(SNAPSHOT_DIR, f"baseline_ch{ch}_winner.md")
        if not os.path.exists(wp):
            missing.append(ch)
            rows.append(f"| {ch} | — | — | — | 缺失 |")
            continue
        with open(wp, encoding="utf-8") as f:
            text = f.read()
        # 从对应 json 快照取模型/分数/soft_sealed
        meta = _read_snapshot_meta(ch)
        rows.append(f"| {ch} | {meta['model']} | {meta['score']} | {'是' if meta['soft_sealed'] else '否'} | baseline_ch{ch}_winner.md |")
        body.append(f"\n### 第 {ch} 章\n\n{text}\n")
    parts.extend(rows)
    parts.extend(body)
    if missing:
        parts.append(f"\n> ⚠️ 缺失章节: {missing}\n")
    with open(MERGED_WINNERS_PATH, "w", encoding="utf-8") as f:
        f.write("".join(parts))
    log(f"合并稿已存: {MERGED_WINNERS_PATH} (缺失章: {missing or '无'})")


def _read_snapshot_meta(ch):
    """从 baseline_chN.json 快照读 winner 模型/最终分/soft_sealed。"""
    jp = os.path.join(SNAPSHOT_DIR, f"baseline_ch{ch}.json")
    if not os.path.exists(jp):
        return {"model": "?", "score": "?", "soft_sealed": False}
    with open(jp, encoding="utf-8") as f:
        snap = json.load(f)
    model = score = "?"
    for d in snap.get("drafts", []):
        if d.get("is_winner"):
            model = d.get("model", "?")
            score = d.get("final_score", "?")
            break
    soft = bool(snap.get("soft_sealed", snap.get("soft_seal", False)))
    return {"model": model, "score": score, "soft_sealed": soft}


if __name__ == "__main__":
    main()
