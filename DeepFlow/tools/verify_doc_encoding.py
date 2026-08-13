#!/usr/bin/env python3
"""
DeepFlow 文档编码修复质量验证
===============================
检查：
1. 所有 md 中残留 U+FFFD(�) 的数量（应为 0）
2. markdown 表格行分隔符完整性（|---| 行与 | 数据行列数一致性）
3. 修复后文件的可读性抽样
4. 编码污染签名：汉字+字面问号(汉字?) 残留（应为 0）——批量替换脚本
   用错编码切断 UTF-8 多字节汉字、或被 LLM 语义重建时的占位残留

用法：
  python verify_doc_encoding.py            # 全目录扫描
  python verify_doc_encoding.py <file>...  # 只扫指定文件（供 pre-commit hook 用）

退出码：0=全部通过；1=有残留（作为 commit 门禁）。
"""
import re
import sys
from pathlib import Path

REPL = '�'
ROOT = Path(r"D:\_Progs\02Business\DeepFlow")
# 编码污染签名：汉字后紧跟 ASCII 问号。历史来源：
#   f7a9b2f2 批量术语替换切断 UTF-8 汉字 -> U+FFFD
#   469366d6 LLM 语义重建把 U+FFFD 换成字面 '?' -> 汉字?
QMARK_PAT = re.compile(r'[一-鿿]\?')


def _files(args):
    """返回待扫描文件列表；无参数时全目录 rglob .md。
    排除：
    - _qmark_backup 备份目录
    - HANDOFF-*.md 交接文档（可能故意保留示例串，不应作为门禁阻断）
    """
    if args:
        return [Path(a) for a in args if Path(a).is_file()
                and '_qmark_backup' not in str(a)
                and not Path(a).name.startswith('HANDOFF-')]
    return [f for f in ROOT.rglob("*.md")
            if '_qmark_backup' not in str(f)
            and not f.name.startswith('HANDOFF-')]


def check_fffd(files):
    """统计残留 U+FFFD。"""
    total = 0
    files_with = []
    for f in files:
        try:
            t = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        n = t.count(REPL)
        if n:
            total += n
            files_with.append((str(f.relative_to(ROOT)), n))
    return total, files_with


def check_qmark(files):
    """统计编码污染签名：汉字+字面问号。"""
    total = 0
    files_with = []
    for f in files:
        try:
            t = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        n = len(QMARK_PAT.findall(t))
        if n:
            total += n
            files_with.append((str(f.relative_to(ROOT)), n))
    return total, files_with


def check_tables(f):
    """检查表格列一致性。返回违规行号列表。"""
    issues = []
    try:
        lines = f.read_text(encoding="utf-8", errors="replace").split("\n")
    except OSError:
        return issues
    i = 0
    while i < len(lines):
        l = lines[i]
        # 分隔行: 含 --- 且为表格行
        if re.match(r"^\s*\|[\s\-:|]+\|\s*$", l) and "---" in l:
            ncols = l.count("|") - 1
            # 检查前后行
            if i > 0:
                prev = lines[i - 1]
                if prev.count("|") - 1 != ncols and prev.strip().startswith("|"):
                    issues.append((i, f"上一行列数 {prev.count('|')-1} != 分隔行 {ncols}: {prev.strip()[:50]!r}"))
            if i + 1 < len(lines):
                nxt = lines[i + 1]
                if nxt.count("|") - 1 != ncols and nxt.strip().startswith("|"):
                    issues.append((i + 1, f"下一行列数 {nxt.count('|')-1} != 分隔行 {ncols}: {nxt.strip()[:50]!r}"))
        i += 1
    return issues


def main():
    files = _files(sys.argv[1:])
    if not files:
        print("(无匹配文件)")
        return 0

    total, files_with = check_fffd(files)
    print(f"[U+FFFD 残留] 共 {total} 个")
    for fp, n in files_with[:30]:
        print(f"  {n:4d}  {fp}")
    if files_with:
        print(f"  共 {len(files_with)} 个文件仍有残留")
    else:
        print("  ✓ 全部清零")

    qtotal, qfiles = check_qmark(files)
    print(f"\n[编码污染 汉字+? ] 共 {qtotal} 个")
    for fp, n in qfiles[:30]:
        print(f"  {n:4d}  {fp}")
    if qfiles:
        print(f"  共 {len(qfiles)} 个文件仍有残留")
    else:
        print("  ✓ 全部清零")

    print(f"\n[表格完整性] 扫描表格行分隔符列一致性...")
    bad_files = 0
    for f in files:
        issues = check_tables(f)
        if issues:
            bad_files += 1
            print(f"  {f.relative_to(ROOT)}: {len(issues)} 处列数不一致")
            for ln, msg in issues[:5]:
                print(f"    L{ln}: {msg}")
    if not bad_files:
        print("  ✓ 无列数不一致")

    return 1 if (total or qtotal or bad_files) else 0


if __name__ == "__main__":
    sys.exit(main())
