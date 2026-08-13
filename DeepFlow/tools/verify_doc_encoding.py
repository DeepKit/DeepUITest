#!/usr/bin/env python3
"""
DeepFlow 文档编码修复质量验证
===============================
检查：
1. 所有 md 中残留 U+FFFD(�) 的数量（应为 0）
2. markdown 表格行分隔符完整性（|---| 行与 | 数据行列数一致性）
3. 修复后文件的可读性抽样
"""
import re
import sys
from pathlib import Path

REPL = '�'
ROOT = Path(r"D:\_Progs\02Business\DeepFlow")


def check_fffd():
    """统计残留 U+FFFD。"""
    total = 0
    files_with = []
    for f in ROOT.rglob("*.md"):
        try:
            t = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        n = t.count(REPL)
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
    total, files_with = check_fffd()
    print(f"[U+FFFD 残留] 共 {total} 个")
    for fp, n in files_with[:30]:
        print(f"  {n:4d}  {fp}")
    if files_with:
        print(f"  共 {len(files_with)} 个文件仍有残留")
    else:
        print("  ✓ 全部清零")

    print(f"\n[表格完整性] 扫描表格行分隔符列一致性...")
    bad_files = 0
    for f in ROOT.rglob("*.md"):
        issues = check_tables(f)
        if issues:
            bad_files += 1
            print(f"  {f.relative_to(ROOT)}: {len(issues)} 处列数不一致")
            for ln, msg in issues[:5]:
                print(f"    L{ln}: {msg}")
    if not bad_files:
        print("  ✓ 无列数不一致")

    return 1 if (total or bad_files) else 0


if __name__ == "__main__":
    sys.exit(main())
