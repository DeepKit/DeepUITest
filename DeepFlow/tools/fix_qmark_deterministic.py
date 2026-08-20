# -*- coding: utf-8 -*-
"""确定性修复 汉字+? 模式（无需 LLM 语义判断）。

处理 4 类语义明确的损坏：
  1. 表格分隔：  '汉字?|'  -> '汉字|'    (? 是 '|' 前残留)
  2. 加粗标记：  '汉字?*'  -> '汉字*'    (? 是 '**' 前残留)
  3. 文件名：    '汉字?v数字' -> '汉字-v数字'   (? 是 '-' 损坏，如 '决策推演金路径?v1.0.md')
  4. 括号前：    '汉字?)'  -> '汉字)'    (? 是残留)

注意：本脚本只做上述 4 类确定性替换，其余 '汉字?' 留给 fix_qmark.py (LLM)。

用法: python -X utf8 tools/fix_qmark_deterministic.py [--dry-run] [file.md ...]
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\_Progs\02Business\DeepFlow")

# (正则, 替换函数)
RULES = [
    (re.compile(r'([一-鿿])\?\|'), lambda m: m.group(1) + '|'),
    (re.compile(r'([一-鿿])\?\*'), lambda m: m.group(1) + '*'),
    (re.compile(r'([一-鿿])\?v(\d)'), lambda m: m.group(1) + '-v' + m.group(2)),
    (re.compile(r'([一-鿿])\?\)'), lambda m: m.group(1) + ')'),
]


def fix_text(text):
    """应用全部确定性规则，返回 (新文本, 修复次数)。"""
    new = text
    n = 0
    for pat, repl in RULES:
        new, cnt = pat.subn(repl, new)
        n += cnt
    return new, n


def read_file(path):
    data = path.read_bytes()
    has_bom = data.startswith(b'\xef\xbb\xbf')
    text = data.decode('utf-8', errors='replace')
    if text.startswith('﻿'):
        text = text[1:]
    return text, has_bom


def write_file(path, text, has_bom):
    data = text.encode('utf-8')
    if has_bom:
        data = b'\xef\xbb\xbf' + data
    path.write_bytes(data)


def main():
    args = sys.argv[1:]
    dry_run = '--dry-run' in args
    files = [a for a in args if not a.startswith('--') and not a.startswith('tools/') and not a.isdigit()]

    if files:
        targets = [ROOT / f for f in files if (ROOT / f).exists()]
    else:
        targets = sorted(ROOT.rglob('*.md'))
    targets = [t for t in targets if t.name not in ('fix_qmark.py', 'fix_qmark_deterministic.py',
                                                    'fix_doc_encoding.py', 'verify_doc_encoding.py')]

    total = 0
    for t in targets:
        text, has_bom = read_file(t)
        new, n = fix_text(text)
        if n:
            if not dry_run:
                write_file(t, new, has_bom)
            print(f"{t.relative_to(ROOT)}: 修 {n} 处{' (dry-run)' if dry_run else ''}")
            total += n
    print(f"\n=== 确定性修复完成: {total} 处{' (dry-run，未写盘)' if dry_run else ''} ===")


if __name__ == '__main__':
    main()
