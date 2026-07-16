"""分章大纲解析器 —— 把结构化大纲 md 解析成 ChapterOutline。

支持《白灯法则》`24_分章大纲.md` 的章节格式：

    ### 第N章：标题
    > **追读类型**：X | **主引擎**：Y | **情感刻度目标**：N | **沉默点**：角色（注释）

    - **产出物**：...
    - **场景**：...
    - **冲突**：...
    - **物理因果锚点**：...
    - **灯态**：...
    - **章末钩子**：...
    - **读者审判时刻**：...（部分章有）

解析产出纯 dataclass，无 DB 依赖；DB 落库由 outline_to_contract 负责。
对齐 docs/implementation-contract-v1.md §大纲接入。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

# --- 章节切分 -------------------------------------------------------------

_CHAPTER_HEAD = re.compile(r"^#{2,4}\s*第\s*([0-9一二三四五六七八九十百零]+)\s*章[：:】]?\s*(.*)$")
# blockquote 内的悬疑契约键值，形如  **追读类型**：追查型
_CONTRACT_PAIR = re.compile(r"\*\*(.+?)\*\*\s*[：:]\s*([^|]+)")
# 列表项  - **产出物**：...
_LIST_ITEM = re.compile(r"^[-*]\s*\*\*(.+?)\*\*\s*[：:]\s*(.*)$")


def _norm_chapter_num(raw: str) -> int:
    """章节号归一为 int（支持阿拉伯数字与中文数字）。"""
    raw = raw.strip()
    if raw.isdigit():
        return int(raw)
    cn = "零一二三四五六七八九十"
    if len(raw) == 1:
        return cn.index(raw)
    # 十一、二十、二十三 等
    if raw.startswith("十"):
        return 10 + (cn.index(raw[1]) if len(raw) > 1 else 0)
    if raw.startswith("二十"):
        return 20 + (cn.index(raw[2]) if len(raw) > 2 else 0)
    if raw.startswith("三十"):
        return 30 + (cn.index(raw[2]) if len(raw) > 2 else 0)
    return 0


@dataclass(frozen=True)
class ChapterOutline:
    """一章大纲的结构化解析结果。

    contract_fields：悬疑工程学契约字段（追读类型/主引擎/情感刻度目标/沉默点），
    阶段1 起进 chapter contract payload。
    base_fields：产出物/场景/冲突/物理因果锚点/灯态/章末钩子/读者审判时刻，
    阶段0 起即用于组装 shot contract。
    """

    chapter_num: int
    title: str
    raw_text: str
    contract_fields: dict[str, str] = field(default_factory=dict)
    base_fields: dict[str, str] = field(default_factory=dict)

    def get(self, key: str, default: str = "") -> str:
        """优先取契约字段，再取基础字段。"""
        return self.contract_fields.get(key) or self.base_fields.get(key, default)


def _parse_block(block: str, head_num: int, head_title: str) -> ChapterOutline:
    contract_fields: dict[str, str] = {}
    base_fields: dict[str, str] = {}

    for line in block.splitlines():
        s = line.strip()
        if not s:
            continue
        # blockquote 悬疑契约行
        if s.startswith(">"):
            for key, val in _CONTRACT_PAIR.findall(s):
                contract_fields[key.strip()] = val.strip()
            continue
        # 列表项
        m = _LIST_ITEM.match(s)
        if m:
            key, val = m.group(1).strip(), m.group(2).strip()
            base_fields[key] = val

    return ChapterOutline(
        chapter_num=head_num,
        title=head_title.strip(),
        raw_text=block,
        contract_fields=contract_fields,
        base_fields=base_fields,
    )


def parse_outline(text: str) -> list[ChapterOutline]:
    """解析整份大纲文本，返回按章号升序的 ChapterOutline 列表。

    只切 `### 第N章` 块；卷标题（## 卷X）与其它内容忽略。
    """
    lines = text.splitlines()
    chapters: list[ChapterOutline] = []
    cur_num: int | None = None
    cur_title = ""
    buf: list[str] = []

    def flush() -> None:
        if cur_num is not None:
            chapters.append(_parse_block("\n".join(buf), cur_num, cur_title))

    for line in lines:
        m = _CHAPTER_HEAD.match(line)
        if m:
            flush()
            cur_num = _norm_chapter_num(m.group(1))
            cur_title = m.group(2)
            buf = [line]
        elif cur_num is not None:
            buf.append(line)
    flush()

    chapters.sort(key=lambda c: c.chapter_num)
    return chapters


def parse_outline_file(path: str | Path) -> list[ChapterOutline]:
    """从 md 文件解析大纲（UTF-8）。"""
    return parse_outline(Path(path).read_text(encoding="utf-8"))


def get_chapter(text: str, chapter_num: int) -> ChapterOutline | None:
    """取指定章号的大纲；不存在返回 None。"""
    for c in parse_outline(text):
        if c.chapter_num == chapter_num:
            return c
    return None
