#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rename-identifiers.py — TASK-0101: 类型标识符 UniFlow→DeepFlow 重命名

策略: 字节级替换 (UniFlow 是纯 ASCII), 不依赖文件编码, 能处理所有 .pas 文件。
编码修复 (TASK-0102) 是独立目标, 不在本脚本范围。

Usage:
  python rename-identifiers.py             # Dry-run, 预览不做实际改动
  python rename-identifiers.py --apply     # 实际执行替换
  python rename-identifiers.py --verify    # 检查残留 UniFlow 引用

作用域: Source/ 下所有 .pas 文件
规则:
  - UniFlow → DeepFlow   (PascalCase 标识符: TUniFlowType, IUniFlowPlugin, esUniFlow 等)
  - UNIFLOW → DEEPFLOW   (UPPERCASE 常量: UNIFLOW_PLUGIN_VERSION)
  - 不触及 uftBuild/ufsCreated 等枚举值(缩写, 非 UniFlow 扩展)
"""

import os
import sys
import re

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
SOURCE_DIRS = [
    os.path.join(BASE_DIR, "Source"),
    os.path.join(BASE_DIR, "Examples"),
]

# 字节级替换也应用于这些文本文件(MD/HTML/JS/PY)
TEXT_EXTENSIONS = {".pas", ".py", ".js", ".html", ".md"}

# 替换规则: (旧模式, 新模式) — 按字节替换, ASCII 安全
REPLACEMENTS = [
    (b"UniFlow", b"DeepFlow"),         # 核心 PascalCase 替换
    (b"UNIFLOW", b"DEEPFLOW"),         # 全大写常量替换
    (b"uniflow", b"deepflow"),         # 全小写(如有)
]


def rename_file(filepath: str, dry_run: bool = True) -> dict:
    """对单个文件执行字节级替换, 返回统计"""
    with open(filepath, "rb") as f:
        raw = f.read()

    original = raw
    changes = []

    for old, new in REPLACEMENTS:
        count = raw.count(old)
        if count > 0:
            raw = raw.replace(old, new)
            changes.append((old.decode(), new.decode(), count))

    if raw == original:
        return {"changed": False, "issues": []}

    if not dry_run:
        with open(filepath, "wb") as f:
            f.write(raw)

    return {"changed": True, "changes": changes}


def rename_directory(dry_run: bool = True) -> list:
    """遍历目录收集结果"""
    results = []
    for src_dir in SOURCE_DIRS:
        for root, dirs, files in os.walk(src_dir):
            for fname in sorted(files):
                ext = os.path.splitext(fname)[1]
                if ext not in TEXT_EXTENSIONS:
                    continue
                if fname.endswith(".dcu"):
                    continue
                fpath = os.path.join(root, fname)
                rel = os.path.relpath(fpath, BASE_DIR)
                result = rename_file(fpath, dry_run=dry_run)
                if result["changed"]:
                    for old, new, count in result["changes"]:
                        results.append({
                            "file": rel,
                            "old": old,
                            "new": new,
                            "count": count,
                        })
    return results


def verify():
    """检查残留 UniFlow 引用"""
    import subprocess
    result = subprocess.run(
        ["grep", "-rn", "UniFlow", BASE_DIR, "--exclude=*.dcu"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        lines = result.stdout.strip().split("\n")
        print(f"❌ 残留 {len(lines)} 处 UniFlow 引用:")
        for line in lines:
            print(f"   {line}")
        return False
    else:
        print("✅ 零残留: 无 UniFlow 引用")
        return True


def main():
    dry_run = "--apply" not in sys.argv
    verify_mode = "--verify" in sys.argv

    if verify_mode:
        verify()
        return

    mode = "DRY-RUN" if dry_run else "APPLY"
    print(f"模式: {mode}")
    print(f"作用域: {BASE_DIR} (Source/ + Examples/)")
    print("策略: 字节级替换 (UniFlow/UNIFLOW/uniflow → DeepFlow/DEEPFLOW/deepflow)")
    print()

    results = rename_directory(dry_run=dry_run)

    # 汇总
    file_stats = {}
    for r in results:
        key = r["file"]
        if key not in file_stats:
            file_stats[key] = {"total": 0, "details": []}
        file_stats[key]["total"] += r["count"]
        file_stats[key]["details"].append(r)

    sorted_files = sorted(file_stats.items(), key=lambda x: -x[1]["total"])

    total_replacements = 0
    for fname, stats in sorted_files:
        print(f"  {stats['total']:4d}  {fname}")
        for d in stats["details"]:
            print(f"         {d['old']:20s} → {d['new']:20s}  × {d['count']}")
        total_replacements += stats["total"]

    print()
    print(f"总计: {total_replacements} 次替换, 涉及 {len(sorted_files)} 个文件")

    if dry_run and total_replacements > 0:
        print()
        print("* 这是 dry-run, 未实际修改任何文件")
        print("  python rename-identifiers.py --apply   # 实际执行")
    elif dry_run and total_replacements == 0:
        print("  无改动, 已全部是最新状态")

    return total_replacements


if __name__ == "__main__":
    main()