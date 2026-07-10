"""《白灯法则》生产 run 一次性 bootstrap（块2）。

已手动建好 session_id=1/run_id=1（指向 project_id=1）。本脚本读
``contract-draft.yaml``，把 identity/narrative_voice/hard_boundaries/
style_locks/world_knowledge/motif_system/creative_zones 七段转成 JSON 字符串，
**进程内**调 ``ink.cli.main(['setup', ...])`` 灌 meta_contract + c2/c3 shot 骨架
（避开 Windows argv 七段 JSON 转义地狱）。

setup 灌的是全局相同 must_land/anti_write/scene 占位——本脚本随后调
``load_chapter_setup`` 把 c02/c03 章纲逐 shot 真值覆写进去。

幂等：setup 的 _cmd_setup 对 shot_contracts 走 INSERT OR IGNORE（UNIQUE
project_id+chapter_id+logical_shot_id+run_id 兜底），meta_contract 走
upsert，重复跑只补不冲突。
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import ink.cli as cli  # noqa: E402
import load_chapter_setup as lcs  # noqa: E402

PROJECT_ID = 1
RUN_ID = 1
DB = r"D:/_Progs/.Story/《白灯法则》/.inkflow/inkflow.db"
CONTRACT_YAML = r"D:/_Progs/.Story/《白灯法则》/.inkflow/contract-draft.yaml"
SETUP_DIR = r"D:/_Progs/.Story/《白灯法则》/.inkflow/chapter-setups"


def _j(obj) -> str:
    return json.dumps(obj, ensure_ascii=False)


def main() -> int:
    import yaml

    with open(CONTRACT_YAML, "r", encoding="utf-8") as fh:
        d = yaml.safe_load(fh)

    # setup 从 ch1 起 N 章连续建骨架（cli 的 _cmd_setup 走 range(1, N+1)）。
    # 灌到 ch3 → ch1/ch2/ch3 各 4 shot 骨架；ch1 是样稿但 contract 骨架无害（仅结构壳）。
    # --db 是顶层 arg，须在 setup 子命令之前。
    argv = [
        "--db", DB,
        "setup",
        "--project-id", str(PROJECT_ID),
        "--run-id", str(RUN_ID),
        "--chapters", "3",
        "--shots-per-chapter", "4",
        "--identity-json", _j(d["identity"]),
        "--narrative-voice-json", _j(d["narrative_voice"]),
        "--hard-boundaries-json", _j(d["hard_boundaries"]),
        "--style-locks-json", _j(d["style_locks"]),
        "--world-knowledge-json", _j(d["world_knowledge"]),
        "--motif-system-json", _j(d["motif_system"]),
        "--creative-zones-json", _j(d["creative_zones"]),
    ]
    print(f"[bootstrap] setup argv (identity 截断): {_j(d['identity'])[:60]}…", file=sys.stderr)
    rc = cli.main(argv)
    if rc != 0:
        print(f"[bootstrap] ERROR setup 返回 {rc}", file=sys.stderr)
        return rc

    # 注入 c02/c03 章纲逐 shot 真值
    for ch in (2, 3):
        yaml_path = os.path.join(SETUP_DIR, f"v01.c0{ch}.yaml")
        if not os.path.isfile(yaml_path):
            print(f"[bootstrap] WARN 章纲不存在，跳过: {yaml_path}", file=sys.stderr)
            continue
        print(f"[bootstrap] 注入章纲 c0{ch}: {yaml_path}", file=sys.stderr)
        rc2 = lcs.main(PROJECT_ID, RUN_ID, ch, yaml_path, DB)
        if rc2 != 0:
            print(f"[bootstrap] ERROR 注入 c0{ch} 返回 {rc2}", file=sys.stderr)
            return rc2
    print("[bootstrap] 完成 setup + 章纲注入", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
