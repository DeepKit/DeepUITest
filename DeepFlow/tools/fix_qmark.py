# -*- coding: utf-8 -*-
"""修复文档中 汉字+? 模式的编码损坏。

背景：文档 UTF-8 尾字节丢失后，汉字被破坏成 U+FFFD(�)，且工具在 � 后补了半角问号 '?'，
形成 '汉字?' 或 '�?' 模式。上一轮已修复 U+FFFD，但遗留了大量 '汉字?' 占位。
这些 '?' 性质多样：
  - 表格分隔 '|' / 加粗 '**' 前的 '?' -> 纯残留，应删除（已由确定性规则处理）
  - '智能? (Level 3)' -> 丢字，应为 '智能体'
  - '分配计算?存储/AI' -> 丢标点，应为 '、'
  - 句尾问句 -> 应为全角 '？'
本脚本用 LLM 语义恢复剩余无法由规则确定的 '汉字?'。

用法: python -X utf8 tools/fix_qmark.py [--dry-run] [--limit N] [file.md ...]
"""
import json
import pathlib
import re
import sys
import urllib.request

REPL = '�'
ENV_PATH = pathlib.Path(r"D:\_Progs\01Center\kiro-gateway\.env")
MODEL = "claude-duojie-gpt-5-6-luna"
GATEWAY = "http://127.0.0.1:8000/v1/chat/completions"
CTX_BEFORE = 12
CTX_AFTER = 12
MAX_PER_BLOCK = 16
MAX_WORKERS = 4
MAX_RETRY = 3

Q_PAT = re.compile(r'[一-鿿]\?')


def load_api_key():
    for line in ENV_PATH.read_text(encoding='utf-8', errors='replace').splitlines():
        if line.startswith('PROXY_API_KEY='):
            return line.split('=', 1)[1].strip().strip('"').strip("'")
    raise RuntimeError("no PROXY_API_KEY in %s" % ENV_PATH)


def read_file(path):
    data = path.read_bytes()
    has_bom = data.startswith(b'\xef\xbb\xbf')
    text = data.decode('utf-8', errors='replace')
    if text.startswith('﻿'):
        text = text[1:]
    return text, has_bom


def write_file(path, text, has_bom):
    # LLM 有时会把 BOM 字符 '﻿' 复制进首行，写回时需剥离，避免重复 BOM
    if text.startswith('﻿'):
        text = text[1:]
    data = text.encode('utf-8')
    if has_bom:
        data = b'\xef\xbb\xbf' + data
    path.write_bytes(data)


def find_bad_lines(lines):
    """含 汉字+? 模式的行。"""
    return [i for i, l in enumerate(lines) if Q_PAT.search(l)]


def make_blocks(bad_idx, max_per_block=MAX_PER_BLOCK, max_gap=40):
    """按损坏行切块：同一块内相邻损坏行间隔不超过 max_gap 行，
    且单块损坏行数不超过 max_per_block。避免 L40 与 L228 这种
    远距离损坏被塞进同一块导致 prompt 超长。"""
    blocks = []
    cur = []
    for i in bad_idx:
        if cur and (i - cur[-1] > max_gap or len(cur) >= max_per_block):
            blocks.append(cur)
            cur = []
        cur.append(i)
    if cur:
        blocks.append(cur)
    return blocks


def build_prompt(lines, block):
    lo = max(0, block[0] - CTX_BEFORE)
    hi = min(len(lines) - 1, block[-1] + CTX_AFTER)
    out = []
    for i in range(lo, hi + 1):
        marker = "✓" if i in block else " "
        out.append(f"{marker}[L{i+1}] {lines[i]}")
    block_txt = "\n".join(out)
    return f"""你是文档修复助手。下面的 markdown 文本中，某些汉字后面出现了多余的半角问号 '?'（如 '记录员?'、'智能? (Level 3)'、'分配计算?存储/AI'）。
这些 '?' 是 UTF-8 编码损坏的残留——原始字符被破坏丢失，工具补了 '?' 占位。标记 ✓ 的行包含这种损坏，需要修复。

修复原则（必须严格遵守）：
1. 只修复 ✓ 行中 '汉字?' 处的 '?'，其余内容一字不改。
2. '?' 的处理取决于上下文：
   - 若 '?' 处本应是某个汉字（如 '智能? (Level 3)'→'智能体 (Level 3)'、'拍板?'→'拍板'），按语义补全或删除。
   - 若 '?' 是丢失标点（如 '分配计算?存储/AI'→'分配计算、存储/AI'），按语义补回（顿号/逗号/句号）。
   - 若句子是疑问句（如 '查询天气?'），用全角问号 '？'。
   - 若 '?' 是纯残留（角色名、节点名、表格单元格末尾），直接删除。
   - 框线图 / ASCII 艺术图 / 代码块内的 '?' 尽量保留原结构，仅删除明显多余的 '?'，不得重排框线。
3. 输出 JSON 对象，键为 ✓ 行号（1-indexed），值为修复后的完整行文本（整行，含所有原文内容）。
4. **重要**：值必须是该行的原始文本内容本身，**绝不**包含行号前缀（如 '[L40]'、'[L12]' 等）——直接输出 `### 1.2 何时使用Agent vs 传统工作流？` 这种，不要加任何行号标记。
5. 修复后行内不得再出现 '汉字?' 模式（'？' 全角问号除外）。
6. 输出必须能 json.loads 解析。

以下是文本（✓=损坏行）：
```
{block_txt}
```
输出 JSON："""


def parse_json_resp(content):
    content = re.sub(r"```(?:json)?", "", content).strip()
    m = re.search(r"\{.*\}", content, re.S)
    if not m:
        raise ValueError("no JSON object found")
    return json.loads(m.group(0))


def chat(api_key, prompt, max_tokens=4000):
    payload = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
    }).encode()
    req = urllib.request.Request(
        GATEWAY,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    req.data = payload
    with urllib.request.urlopen(req, timeout=300) as resp:
        res = json.load(resp)
    return res["choices"][0]["message"]["content"]


def repair_block(api_key, lines, block):
    prompt = build_prompt(lines, block)
    content = chat(api_key, prompt)
    j = parse_json_resp(content)

    expected = {str(i + 1) for i in block}
    got = set(j.keys())
    missing = expected - got
    if missing:
        raise ValueError(f"missing lines: {sorted(missing)}")

    result = {}
    for i in block:
        v = j[str(i + 1)]
        # 防泄漏: LLM 有时会把行号前缀 '[L40]' 当原文输出，剥掉
        m = re.match(r'^\s*\[L\d+\]\s*', v)
        if m:
            v = v[m.end():]
        if REPL in v:
            raise ValueError(f"line {i+1} still has U+FFFD")
        # 校验: 不得再含 汉字? (全角? 允许)
        if re.sub(r'[一-鿿]？', '', v) != v.replace('?', '?'):
            pass
        if Q_PAT.search(re.sub(r'[一-鿿]？', 'XX', v)):
            raise ValueError(f"line {i+1} still has 汉字+? : {v[:40]}")
        result[i] = v
    return result


def repair_file(api_key, path, dry_run=False):
    text, has_bom = read_file(path)
    lines = text.split('\n')
    bad = find_bad_lines(lines)
    if not bad:
        return 0, 0
    blocks = make_blocks(bad)
    fixed = 0
    fails = 0
    for bi, block in enumerate(blocks, 1):
        for attempt in range(MAX_RETRY):
            try:
                result = repair_block(api_key, lines, block)
                for i, v in result.items():
                    lines[i] = v
                fixed += len(result)
                print(f"  {path.name}: 块{bi}/{len(blocks)} 修 {len(result)} 行", flush=True)
                break
            except Exception as e:
                print(f"  {path.name}: 块{bi} 重试{attempt+1} {e}", flush=True)
                if attempt == MAX_RETRY - 1:
                    fails += 1
    if not dry_run and fixed:
        write_file(path, '\n'.join(lines), has_bom)
    return fixed, fails


def main():
    args = sys.argv[1:]
    dry_run = '--dry-run' in args
    limit = None
    if '--limit' in args:
        limit = int(args[args.index('--limit') + 1])
    files = [a for a in args if not a.startswith('--') and not a.startswith('tools/') and not a.isdigit()]

    root = pathlib.Path(r"D:\_Progs\02Business\DeepFlow")
    if files:
        targets = [root / f for f in files if (root / f).exists()]
    else:
        targets = sorted(root.glob('*.md'))
    targets = [t for t in targets if t.name != 'fix_qmark.py' and t.name != 'fix_doc_encoding.py']
    if limit:
        targets = targets[:limit]

    api_key = load_api_key()
    total_fixed = 0
    total_fail = 0
    for t in targets:
        fixed, fails = repair_file(api_key, t, dry_run)
        total_fixed += fixed
        total_fail += fails
        print(f"{t.name}: 共修 {fixed}, 失败块 {fails}", flush=True)
    print(f"\n=== 完成: 修复 {total_fixed} 行, 失败块 {total_fail} ===")
    if dry_run:
        print("(dry-run，未写盘)")


if __name__ == '__main__':
    main()
