#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""行级合并还原框线图: 保留工作区正文修复，从 HEAD 确定性还原框线字符。

背景: 编码损坏把框线字符(│┐┘└┌├┤等)转成 U+FFFD+'?'。上一会话用 LLM 重绘，
引入幻觉字符(✓ ┤ ┣ 「」 等)破坏框线拓扑。本脚本按行对齐:
  - HEAD 该行是框线损坏行 → 用 HEAD 行做确定性还原
  - 其余行(目录树/正文汉字损坏) → 保留工作区版本

框线损坏判定(每行):
  - '�?' 在行首(仅缩进) → 框线竖线引导
  - 行内含 │ ┌ ┐ ┘ ┬ ┴ ▼ 任一 → 框线
  - └/├ 后跟 ─ 延伸至框线角/损坏角/行尾 → 框线 (非目录树)
  - 其余(目录树/正文) → 非框线，保留工作区

还原规则(框线行内 '�?'):
  - 前一非空字符是 '─' → 按最近开角 (┌→┐ └→┘ ├→┤)
  - 否则 → '│'
"""
import re, subprocess, sys, pathlib

ROOT = pathlib.Path('D:/_Progs/02Business')

def is_box_damage_line(l):
    """保守判定: 只处理明确框线/目录树行，避免正文汉字损坏误伤"""
    if '�' not in l:
        return False
    # 行首 �? 后跟目录树/框线结构 (├ └ │ ┌ ┐ 等)
    if re.match(r'^\s*�\?(\s*)([├└│┌┐┘┬┴▼])', l):
        return True
    # 行内含框线框特征(非正文的 ┌ ┐ ┘ ┬ ┴ ▼ │)
    if any(c in l for c in '│┌┐┘┬┴▼'):
        return True
    # └/├ 后跟横线延伸无文字 → 框线
    m = re.match(r'^\s*[└├]\s*─+', l)
    if m:
        rest = l[m.end():]
        if not re.search(r'[一-鿿A-Za-z]', rest):
            return True
    return False

def restore_line(l):
    if '�' not in l:
        return l
    matches = list(re.finditer(r'�\?', l))
    if not matches:
        return l
    chars = list(l)
    for m in reversed(matches):
        j = m.start()
        prev_vis = l[:j].rstrip()
        prev_ch = prev_vis[-1] if prev_vis else ''
        if prev_ch == '─':
            opens = [(k, c) for k, c in enumerate(l[:j]) if c in '┌└├┤']
            if opens:
                c = opens[-1][1]
                repl = {'┌': '┐', '└': '┘', '├': '┤', '┤': '┤'}.get(c, '│')
            else:
                repl = '│'
        else:
            repl = '│'
        chars[j] = repl
        del chars[j + 1]
    return ''.join(chars)

def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    if '--file' not in args:
        print('usage: restore_box_drawing.py --file <path> [--dry-run]'); sys.exit(1)
    f = args[args.index('--file') + 1]
    rel = f if f.startswith('DeepFlow/') else f'DeepFlow/{f}'
    head = subprocess.run(['git', 'show', f'HEAD:{rel}'], capture_output=True, text=True, cwd=ROOT).stdout
    head_lines = head.split('\n')
    cur = (ROOT / rel).read_text(encoding='utf-8').split('\n')
    if len(cur) != len(head_lines):
        print(f'跳过 {rel}: 行数不一致 HEAD={len(head_lines)} 工作区={len(cur)}')
        sys.exit(1)
    changes = 0
    new_lines = []
    for i, h in enumerate(head_lines):
        if is_box_damage_line(h):
            restored = restore_line(h)
            if restored != cur[i]:
                changes += 1
            new_lines.append(restored)
        else:
            new_lines.append(cur[i])
    if not dry and changes:
        has_bom = (ROOT / rel).read_bytes().startswith(b'\xef\xbb\xbf')
        text = '\n'.join(new_lines)
        if has_bom:
            text = '﻿' + text
        (ROOT / rel).write_bytes(text.encode('utf-8'))
    print(f'{rel}: 框线行替换 {changes} 处 {"(dry-run)" if dry else "(已写盘)"}')

if __name__ == '__main__':
    main()
