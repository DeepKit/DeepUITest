"""《白灯法则》工业事实基线灌库脚本（块C1）。

把外部事实源文档 ``23_第一代工厂质感.md`` 抽成 atomic clauses 灌入
``writing_atomic_source_clauses``，作为 chapter review 工业事实漂移检测器
(``_chapter_industrial_fact_drift_block``) 的事实基线（task#19 的工艺细节库落点）。

clause_type 复用现有 schema CHECK 枚举（sql/schema.sql:900）：
  - 工艺真锚点 / 报废制度 / 失效机理  → ``process`` + ``hard``
  - 武侠化禁漂移规则                 → ``forbidden`` + ``soft``

幂等：文档级按 (project_id, source_path, content_hash) 去重（UNIQUE 约束兜底），
      条款级按 (source_document_id, clause_text) 去重（先查后插）。
      重复跑只补缺失条目，不重灌、不改已 confirmed 的旧条目。

用法：
  cd ink && PYTHONPATH=src:tests python tools/seed_industrial_facts.py
可选 --project-id / --db-path 覆盖默认。
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from ink.source_workflow import SourceWorkflowStore  # noqa: E402

PROJECT_ID = 1
SOURCE_PATH = r"D:/_Progs/.Story/《白灯法则》/23_第一代工厂质感.md"
DB_PATH = r"D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db"
# 23_ 是第一代（卷一）全卷级质感文档。
SCOPE_TYPE = "volume"
SCOPE_ID = "1"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---- 基线条目（从 23_ 抽取，§号对应原文小节） ---------------------------
# 每条：(clause_type, severity, clause_text, [source_refs])
CLAUSES: list[tuple[str, str, str, list[str]]] = [
    # — process / hard：工艺真锚点（应有什么）—
    ("process", "hard",
     "每道工序结束需操作工、检验员、车间主任三级钢笔签字（蓝黑墨水）并盖私人木头印章（小拇指大、刻本人名、红印泥）。",
     ["§三.签字"]),
    ("process", "hard",
     "质检室气味为酒精棉球、干燥器硅胶、天平室防震橡胶；吕素琴的湿热试验箱打开时冲出湿热空气（如掀蒸笼但不香）。",
     ["§二.气味"]),
    ("process", "hard",
     "仓库气味为油纸、防锈脂、木材包装箱松脂；记录本以油纸包裹、木柜压存，打开有纸浆油墨混合霉味。",
     ["§二.气味"]),

    # — process / hard：报废制度锚点（制度冲突的基线事实）—
    ("process", "hard",
     "签字表格无'最终后果'一栏——根本没有位置留给'若这批货在前线失效，找谁'；不是不敢签，是那一栏不存在。",
     ["§三.签字"]),
    ("process", "hard",
     "1978 样件的军工报废销毁制度冲突：封存样件表面微小变化、临界点湿度波动等不敢写进正式报告的数据，被以油纸私藏而非按报废制度销毁。",
     ["§四.藏在油纸里的东西"]),

    # — process / hard：失效机理锚点 —
    ("process", "hard",
     "押运员把货送到下一站点后回来说'交了'而非'送到了'；许怀山 1980 年最后一次跟车看到目的地是转运站旁的军列，回来后再没提过那批货，直到前线失效报告传回。",
     ["§四.工厂里的人和不在的人"]),

    # — forbidden / soft：武侠化禁漂移规则（禁止什么）—
    ("forbidden", "soft",
     "禁止水浒式兄弟情：工人之间的情谊是具体的（一起上夜班、吃食堂、澡堂聊天），不是江湖传奇；情感须落物件动作，不可传奇化。",
     ["§六.避免的陷阱.4"]),
    ("forbidden", "soft",
     "禁止'那个年代'式感慨（'那时候的人还相信……'）；让物件、动作、对话自己说话，不用叙述者抒情。",
     ["§六.避免的陷阱.1"]),
    ("forbidden", "soft",
     "禁止美化贫困（工人不是苦行僧，想涨工资换大房子让孩子上好学校）与丑化体制（厂长非官僚、工人非螺丝钉，各有理由顾虑伤口）。",
     ["§六.避免的陷阱.2-3"]),
    # 反向 marker 词表（武侠化/仪式感压过工艺的典型表达），供规则层硬匹配。
    ("forbidden", "soft",
     "[marker] 武侠化/仪式感压过工艺的表达：传奇化、江湖、义薄云天、肝胆相照、闻味即断（以仪式感替代工艺真实）、神探式一眼识破。",
     ["§六.避免的陷阱（反向词表）"]),
    # 触发关键词词表（工艺失效信号词），供启发式筛可疑段——命中即送 LLM 兜底判
    # 「提到失效却没说清制度事实」。与 [marker] 对称：marker 是反向禁词，trigger 是
    # 正向信号词，皆存项目基线（机制层 _suspicious_segments 从此解析，不硬编码）。
    ("process", "hard",
     "[trigger] 工艺失效信号词：失效、报废、前线、押运、废品、退货、事故、信不过。",
     ["§六.避免的陷阱（触发词表）"]),
]


def _content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _existing_doc_id(conn: sqlite3.Connection, project_id: int, source_path: str) -> int | None:
    row = conn.execute(
        "SELECT source_document_id FROM writing_source_documents "
        "WHERE project_id = ? AND source_path = ? ORDER BY updated_at DESC LIMIT 1",
        (project_id, source_path),
    ).fetchone()
    return int(row[0]) if row else None


def _existing_clause_texts(conn: sqlite3.Connection, source_document_id: int) -> set[str]:
    rows = conn.execute(
        "SELECT clause_text FROM writing_atomic_source_clauses WHERE source_document_id = ?",
        (source_document_id,),
    ).fetchall()
    return {r[0] for r in rows}


def main(project_id: int, db_path: str) -> int:
    if not os.path.isfile(SOURCE_PATH):
        log(f"ERROR 源文档不存在: {SOURCE_PATH}")
        return 2
    with open(SOURCE_PATH, "r", encoding="utf-8") as fh:
        content = fh.read()
    content_hash = _content_hash(content)
    log(f"源文档 {SOURCE_PATH} ({len(content)} bytes, hash={content_hash[:8]})")

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    store = SourceWorkflowStore(conn)

    doc_id = _existing_doc_id(conn, project_id, SOURCE_PATH)
    if doc_id is None:
        doc_id = store.register_source_document(
            project_id=project_id,
            source_path=SOURCE_PATH,
            source_kind="guide",
            content_hash=content_hash,
            status="active",
        )
        log(f"注册源文档 → source_document_id={doc_id}")
    else:
        log(f"源文档已存在 source_document_id={doc_id}（幂等跳过注册）")

    existing = _existing_clause_texts(conn, doc_id)
    inserted = 0
    for clause_type, severity, clause_text, refs in CLAUSES:
        if clause_text in existing:
            continue
        store.record_atomic_clause(
            project_id=project_id,
            source_document_id=doc_id,
            scope_type=SCOPE_TYPE,
            scope_id=SCOPE_ID,
            clause_type=clause_type,
            severity=severity,
            clause_text=clause_text,
            source_refs=refs,
            source_hashes=[content_hash],
            status="confirmed",
        )
        inserted += 1
        log(f"  + [{clause_type}/{severity}] {clause_text[:40]}…")
    conn.commit()
    log(f"完成：新灌 {inserted} 条，已有 {len(existing)} 条（共 {len(CLAUSES)} 条目标）")
    conn.close()
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="灌工业事实基线 atomic clauses（块C1）")
    ap.add_argument("--project-id", type=int, default=PROJECT_ID)
    ap.add_argument("--db-path", default=DB_PATH)
    args = ap.parse_args()
    sys.exit(main(args.project_id, args.db_path))
