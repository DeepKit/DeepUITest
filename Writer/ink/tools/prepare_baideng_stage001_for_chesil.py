"""Prepare a clean heading hierarchy for importing STAGE-001 into Chesil."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(r"D:/_Progs/.Story/《白灯法则》")
SOURCE = ROOT / ".inkflow" / "stage001" / "stage001_initial_draft.md"
OUTPUT_DIR = ROOT / ".inkflow" / "stage001" / "chesil-import-v3"
OUTPUT = OUTPUT_DIR / "stage001.md"


def downgrade_headings(text: str) -> str:
    return re.sub(
        r"^(#{1,6})\s+",
        lambda match: "#" * min(6, len(match.group(1)) + 3) + " ",
        text,
        flags=re.MULTILINE,
    )


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n")
    matches = list(
        re.finditer(
            r"^#\s+(序章[^\n]*|第\s*0?([1-9]|10)\s*章[^\n]*)\s*$",
            text,
            flags=re.MULTILINE,
        )
    )
    if len(matches) != 11:
        raise RuntimeError(f"expected prologue + 10 chapter headings, got {len(matches)}")
    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        raw_title = match.group(1)
        chapter_num = match.group(2)
        title = "序章" if raw_title.startswith("序章") else f"第{int(chapter_num):02d}章"
        sections.append((title, downgrade_headings(text[start:end].strip())))
    parts = [
        "# STAGE-001 第一代与时间桥\n",
        "\n## 第一卷\n",
    ]
    for title, body in sections:
        parts.append(f"\n### {title}\n\n{body}\n")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("".join(parts), encoding="utf-8")
    print(
        json.dumps(
            {
                "source": str(SOURCE),
                "output": str(OUTPUT),
                "sections": [title for title, _ in sections],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
