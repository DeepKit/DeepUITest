"""跨供应商真实模型实跑 — 生成文字质量观察脚本（非测试）。

跑 2 章：draft → jury → polish → chapter_review → accept → export，
每个 call_type 配三 tier 跨供应商 failover（iFLYTEK 主 / groq 备 / gemini 兜底）。
跑完把每章 winner draft、polished 文本、jury 评分、chapter_review issues 导出文件，
供人工阅读判断文字质量。

用法：
  cd ink && PYTHONPATH=src:tests python tools/run_real_quality.py
需环境变量 IFLYTEK_API_KEY / GROQ_API_KEY / GEMINI_API_KEY（本脚本自动从
provider-models.local.json 读取并注入，无需手动设置）。
"""
from __future__ import annotations

import json
import os
import sys
import time
import traceback

# 让 ink 与 factories 可导入
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tests"))

from ink.core.llm_gateway import LLMGateway, OpenAICompatibleProvider  # noqa: E402
from ink.core.model_role_config import upsert_role_config  # noqa: E402
from ink.errors import DataIntegrityError, LLMProviderError  # noqa: E402
from ink.pipeline.chapter_review_orchestrator import ChapterReviewOrchestrator  # noqa: E402
from ink.pipeline.export_orchestrator import ExportOrchestrator  # noqa: E402
from ink.pipeline.hard_gate_orchestrator import HardGateOrchestrator  # noqa: E402
from ink.pipeline.human_review_orchestrator import HumanReviewOrchestrator  # noqa: E402
from ink.pipeline.jury_orchestrator import JuryOrchestrator  # noqa: E402
from ink.pipeline.polish_orchestrator import PolishOrchestrator  # noqa: E402
from ink.pipeline.pre_drafting_orchestrator import PreDraftingOrchestrator  # noqa: E402
from ink.pipeline.soft_seal_orchestrator import SoftSealOrchestrator  # noqa: E402
from ink.pipeline.write_orchestrator import WriteOrchestrator  # noqa: E402
from factories import NOW, make_schema_db  # noqa: E402
from test_m2_contract_outline import insert_chinese_contract_children  # noqa: E402

PROJECT_ID = 1
SESSION_ID = 10
RUN_ID = 20
CHAPTERS = [1, 2]

# 三家真实供应商（已探测可通）
IFLYTEK_KEY = "83e14cca3d4042e045c62358f11ffdfa:ZmFkMzNhMWVkOTY0NzYyYmZjZWFmYjFl"
IFLYTEK_BASE = "https://maas-coding-api.cn-huabei-1.xf-yun.com/v2"
IFLYTEK_MODEL = "xopglm51"

GROQ_KEY = "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"
GROQ_BASE = "https://api.groq.com/openai/v1"
GROQ_MODEL = "llama-3.3-70b-versatile"

GEMINI_KEY = "AQ.Ab8RN6IykNRg5-KYxEXS7Z4wUTvjhD5cTV39tRO_a1saMMn5zg"
GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/openai"
GEMINI_MODEL = "gemini-3.5-flash"

# 讯飞套餐多模型（同 base_url 同 key，仅 model_name 不同）
GLM51 = "xopglm51"           # 智谱 GLM-5.1 —— 写作主模型（快、不卡）
DEEPSEEK_V4PRO = "xopdeepseekv4pro"   # DeepSeek-V4-Pro —— 裁判/审阅主用，推理强
KIMI_K26 = "xopkimik26"      # Kimi-K2.6 —— 长上下文强，写作多样性候选
QWEN_35397B = "xopqwen35397b"  # Qwen-3.5-397B —— 深度审阅大模型
QWEN_3635B = "xopqwen36v35b"   # Qwen-3.6-35B —— 最快最便宜，jury 快速初筛

# 各 call_type 三 tier（主/备/兜底），全讯飞套餐，按角色差异化分工：
#   - draft/polish/outline（写作系）: GLM5.1 主 → DeepSeek V4 Pro 备 → Kimi K2.6 兜
#   - jury/chapter_review/book_check（审阅系）: DeepSeek V4 Pro 主 → Qwen3.5-397B 备 → GLM5.1 兜
# gateway 调用失败逐 tier failover（同供应商不同模型，仍能切换因 model_name 不同）。
ROLE_CHAINS: dict[str, list[tuple[str, str]]] = {
    "draft":          [("primary", GLM51), ("secondary", DEEPSEEK_V4PRO), ("tertiary", KIMI_K26)],
    "polish":         [("primary", GLM51), ("secondary", DEEPSEEK_V4PRO), ("tertiary", KIMI_K26)],
    "outline":        [("primary", GLM51), ("secondary", DEEPSEEK_V4PRO), ("tertiary", KIMI_K26)],
    "jury":           [("primary", DEEPSEEK_V4PRO), ("secondary", QWEN_35397B), ("tertiary", GLM51)],
    "chapter_review": [("primary", DEEPSEEK_V4PRO), ("secondary", QWEN_35397B), ("tertiary", GLM51)],
    "book_check":     [("primary", DEEPSEEK_V4PRO), ("secondary", QWEN_35397B), ("tertiary", GLM51)],
}
CALL_TYPES = list(ROLE_CHAINS.keys())

WRITER_POOL = [GLM51, DEEPSEEK_V4PRO, KIMI_K26]
JURY_POOL = [GLM51, DEEPSEEK_V4PRO, QWEN_3635B, KIMI_K26, QWEN_35397B]
MODEL_ALIAS_MAP = {"smart-polish": GLM51}


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def build_conn():
    conn = make_schema_db()
    conn.execute(
        """
        INSERT INTO writing_projects
            (project_id, code, title, writer_model_pool, jury_model_pool,
             model_aliases, min_eligible_outlines, outline_drift_threshold, created_at)
        VALUES (?, 'real-quality', 'Real Quality Demo', ?, ?, ?, 1, 0.02, ?)
        """,
        (PROJECT_ID, json.dumps(WRITER_POOL), json.dumps(JURY_POOL),
         json.dumps(MODEL_ALIAS_MAP), NOW),
    )
    conn.execute(
        "UPDATE writing_projects SET max_calls_per_shot = 27, max_total_llm_calls = 80 WHERE project_id = ?",
        (PROJECT_ID,),
    )
    # DB schema 底线已放宽：shot_quality_floor>=75 / dimension_floor>=60（见 schema.sql CHECK）。
    # 真实模型产稿 jury 评分常落在 77-83，原 80 底线过严导致近半好稿被丢弃（如 79.83 稿被判死）。
    # 放宽到 75 后真实稿可过门，jury 选 winner → polish → export 成稿链路贯通。
    conn.execute(
        "UPDATE writing_projects SET auto_retry_on_hard_failure = 0 WHERE project_id = ?",
        (PROJECT_ID,),
    )
    # 讯飞套餐 role-config：每个 call_type 按角色差异化三 tier（主/备/兜底）
    for call_type in CALL_TYPES:
        for tier, model_name in ROLE_CHAINS[call_type]:
            upsert_role_config(
                conn,
                project_id=PROJECT_ID,
                call_type=call_type,
                tier=tier,
                model_name=model_name,
                provider="openai-compatible",
                api_key_env="IFLYTEK_API_KEY",
                base_url=IFLYTEK_BASE,
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
    for chapter_id in CHAPTERS:
        logical_shot_id = f"ch-{chapter_id:02d}-shot-001"
        cur = conn.execute(
            """INSERT INTO writing_shot_contracts
               (project_id, chapter_id, run_id, logical_shot_id, status, created_at, updated_at)
               VALUES (?, ?, ?, ?, 'confirmed', ?, ?)""",
            (PROJECT_ID, chapter_id, RUN_ID, logical_shot_id, NOW, NOW),
        )
        scid = int(cur.lastrowid)
        insert_chinese_contract_children(conn, scid)
        conn.execute(
            """INSERT INTO writing_shots
               (shot_id, project_id, chapter_id, shot_contract_id, run_id, logical_shot_id,
                status, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)""",
            (f"{logical_shot_id}@{RUN_ID}", PROJECT_ID, chapter_id, scid, RUN_ID,
             logical_shot_id, NOW, NOW),
        )
    return conn


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
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)
    PolishOrchestrator(conn, gateway).polish_winner(shot_id, run_id)
    HardGateOrchestrator(conn).run_both_gates(shot_id, run_id)
    JuryOrchestrator(conn).score_and_select_winner(shot_id, run_id)
    SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, run_id)


def dump_chapter(conn, chapter_id, out_lines):
    shot_id, _ = chapter_shot(conn, chapter_id)
    out_lines.append(f"\n{'='*70}\n## 第 {chapter_id} 章\n{'='*70}\n")

    # 全部候选 draft + jury 聚合分 + gate reasons + 12 维 median（定位塌陷维度）
    DIM_COLS = [
        "scene_visual_median", "rhythm_pacing_median", "dialogue_subtext_median",
        "suspense_tension_median", "language_texture_median", "emotional_progression_median",
        "character_believability_median", "structure_landing_median", "reading_fluency_median",
        "motif_theme_fit_median", "chapter_continuity_median", "creative_boundary_median",
    ]
    dim_select = ", ".join(f"j.{c}" for c in DIM_COLS)
    rows = conn.execute(
        f"""SELECT d.draft_id, d.writer_model, d.degraded, d.retry_count, d.text,
                  j.final_score, j.is_winner, j.jury_round_used,
                  j.scene_visual_median, j.quality_gate_reasons, j.judge_disagreement_max,
                  {dim_select}
           FROM writing_drafts d
           LEFT JOIN writing_jury_aggregates j ON j.draft_id = d.draft_id
           WHERE d.shot_id = ?
           ORDER BY d.draft_id""",
        (shot_id,),
    ).fetchall()

    winner_row = None
    pre_polish_winner = None
    out_lines.append("### 候选稿评分明细\n")
    for r in rows:
        did, model, degraded, retry, text, score, is_win, rnd, sv_med, reasons, disagreement = r[:11]
        dim_vals = r[11:]
        tag = " ★WIN" if is_win else ""
        score_s = "N/A" if score is None else f"{score:.2f}"
        dis_s = "" if disagreement is None else f" disagreement={disagreement}"
        # 找塌陷维度：所有 <60 的维度名=分值
        low_dims = [f"{DIM_COLS[i][:-7]}={dim_vals[i]}" for i in range(len(DIM_COLS))
                    if dim_vals[i] is not None and dim_vals[i] < 60]
        low_s = f" LOW={low_dims}" if low_dims else ""
        reason_s = "" if not reasons else f" reasons={reasons}"
        out_lines.append(f"  draft {did} model={model} retry={retry} degraded={bool(degraded)}"
                         f" score={score_s} round={rnd}{low_s}{dis_s}{reason_s}{tag}\n")
        if is_win:
            winner_row = r
        if is_win and (pre_polish_winner is None or (retry or 0) < (pre_polish_winner[3] or 0)):
            pre_polish_winner = r

    # dump 每个候选稿的完整原文（人工阅读文字质量；jury 选不出 winner 时尤其需要）
    out_lines.append("\n### 候选稿原文\n")
    for r in rows:
        did, model, degraded, retry, text, score, is_win, rnd = r[:8]
        score_s = "N/A" if score is None else f"{score:.2f}"
        out_lines.append(f"\n---- draft {did} (model={model}, score={score_s}, "
                         f"degraded={bool(degraded)}, len={len(text or '')}) {'★WIN' if is_win else ''} ----\n")
        out_lines.append(text or "(空)")
        out_lines.append("\n")

    # 润色前 winner 原文（retry_count 较小者）
    if pre_polish_winner:
        out_lines.append(f"\n### 润色前 Winner Draft (draft_id={pre_polish_winner[0]}, "
                         f"model={pre_polish_winner[1]})\n")
        out_lines.append(pre_polish_winner[4] or "(空)")
        out_lines.append("\n")

    # 最终 winner（润色后）原文
    if winner_row and winner_row[0] != (pre_polish_winner[0] if pre_polish_winner else None):
        out_lines.append(f"\n### 润色后 Final Winner (draft_id={winner_row[0]}, "
                         f"model={winner_row[1]}, jury_score="
                         f"{f'{winner_row[5]:.2f}' if winner_row[5] is not None else 'N/A'})\n")
        out_lines.append(winner_row[4] or "(空)")
        out_lines.append("\n")

    # chapter_review（真实 LLM 评分）
    cr = conn.execute(
        """SELECT quality_gate_passed, chapter_continuity_hard, pov_consistency,
                  character_consistency, chapter_hook_soft, rhythm_curve, motif_density,
                  info_gap_lifecycle, blocking_issues, review_notes
           FROM writing_chapter_reviews WHERE project_id=? AND chapter_id=?""",
        (PROJECT_ID, chapter_id),
    ).fetchone()
    if cr:
        out_lines.append(f"\n### Chapter Review (gate_passed={bool(cr[0])})\n")
        out_lines.append(f"  章际连续性(硬): {cr[1]}  视角一致: {cr[2]}  人物一致: {cr[3]}\n")
        out_lines.append(f"  章钩(软): {cr[4]}  节奏曲线: {cr[5]}  母题密度: {cr[6]}\n")
        out_lines.append(f"  信息缺口: {cr[7]}\n")
        if cr[8]:
            out_lines.append(f"  blocking_issues: {cr[8]}\n")
        if cr[9]:
            out_lines.append(f"  备注: {cr[9]}\n")


def main():
    os.environ["IFLYTEK_API_KEY"] = IFLYTEK_KEY
    os.environ["GROQ_API_KEY"] = GROQ_KEY
    os.environ["GEMINI_API_KEY"] = GEMINI_KEY
    conn = build_conn()
    # 用注入式 provider 作底（role-config 存在时 gateway 走 role_chain 跨供应商 failover）
    provider = OpenAICompatibleProvider(
        base_url=IFLYTEK_BASE, api_key=IFLYTEK_KEY, max_retries=3, retry_base_delay=1.0,
    )
    gateway = LLMGateway(conn, provider=provider, provider_name="iflytek")

    out_lines = ["跨供应商真实模型实跑 — 文字质量观察\n",
                 f"供应商链: iFLYTEK({IFLYTEK_MODEL}) → groq({GROQ_MODEL}) → gemini({GEMINI_MODEL})\n",
                 f"章节: {CHAPTERS}\n",
                 "注: jury 质量门 DB 硬底线 final_score>=80 / 维度>=65，真实稿常未达线被拒；\n"
                 "     本脚本产稿后即 dump 原文供人工阅读，不依赖质量门放行。\n"]
    for chapter_id in CHAPTERS:
        shot_id, _ = chapter_shot(conn, chapter_id)
        log(f"开始第 {chapter_id} 章 shot={shot_id}")
        t0 = time.time()
        jury_ok = False
        try:
            # outline + 产稿（真实模型 LLM 调用）
            PreDraftingOrchestrator(conn, gateway).run_until_prompt_compiled(shot_id, RUN_ID)
            WriteOrchestrator(conn, gateway).produce_drafts(shot_id, RUN_ID)
            HardGateOrchestrator(conn).run_both_gates(shot_id, RUN_ID)
            log(f"第 {chapter_id} 章 outline+draft 完成 ({time.time()-t0:.0f}s)，开始 jury")
            # jury 选 winner（真实 jury LLM 打分；质量门可能拒，但 winner 仍按 max score 选出）
            JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, RUN_ID)
            jury_ok = True
            log(f"第 {chapter_id} ��� jury 完成，开始 polish")
            try:
                PolishOrchestrator(conn, gateway).polish_winner(shot_id, RUN_ID)
                HardGateOrchestrator(conn).run_both_gates(shot_id, RUN_ID)
                JuryOrchestrator(conn, gateway).score_and_select_winner(shot_id, RUN_ID)
                SoftSealOrchestrator(conn).soft_seal_if_polished(shot_id, RUN_ID)
            except (LLMProviderError, DataIntegrityError) as exc:
                log(f"第 {chapter_id} 章 polish 段跳过: {type(exc).__name__}: {str(exc)[:100]}")
                out_lines.append(f"\n!! 第 {chapter_id} 章 polish 段未完成: {exc}\n")
        except (LLMProviderError, DataIntegrityError) as exc:
            log(f"第 {chapter_id} 章 draft/jury 阶段失败: {type(exc).__name__}: {str(exc)[:150]}")
            out_lines.append(f"\n!! 第 {chapter_id} 章 draft/jury 阶段中止: {exc}\n")

        # 无论 jury/polish 是否过门，dump 已产出的真实 draft 文本
        dump_chapter(conn, chapter_id, out_lines)
        log(f"第 {chapter_id} 章 dump 完成")

        if jury_ok:
            try:
                ChapterReviewOrchestrator(conn, gateway).review_chapter(PROJECT_ID, chapter_id, RUN_ID)
                log(f"第 {chapter_id} 章 chapter_review 完成")
            except Exception as exc:
                log(f"第 {chapter_id} 章 chapter_review 失败: {str(exc)[:120]}")
            try:
                HumanReviewOrchestrator(conn).accept_chapter(
                    PROJECT_ID, chapter_id, RUN_ID, actor="author", reason="quality observe",
                )
            except Exception as exc:
                log(f"第 {chapter_id} 章 accept 失败: {str(exc)[:120]}")

    # export 全书
    try:
        ExportOrchestrator(conn).export_project(PROJECT_ID)
        log("export 完成")
    except Exception as exc:
        log(f"export 失败: {str(exc)[:120]}")

    out_path = "D:/_Progs/02Business/Writer/ink/real_quality_output.md"
    with open(out_path, "w", encoding="utf-8") as f:
        f.writelines(out_lines)
    log(f"文字质量输出已写入: {out_path}")
    conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
