#!/usr/bin/env python3
"""
DeepFlow 文档编码修复脚本
=========================
文档中大量汉字因 UTF-8 尾字节丢失被不可逆破坏为 U+FFFD(�)。
本脚本通过 Kiro Gateway(127.0.0.1:8000) 调用 claude-agnes-2-5-flash,
按块提取损坏行 + 上下文,LLM 语义恢复,JSON 行号回写。

用法:
    python -X utf8 tools/fix_doc_encoding.py [--file <相对路径>] [--dry-run] [--concurrency N] [--all]
"""
import json
import os
import re
import sys
import time
import argparse
import urllib.request
import urllib.error
import concurrent.futures
from pathlib import Path

# GBK 幸存字节锚点（第三轮后增强）：坏行原始字节中未被 U+FFFD 覆盖的部分，
# 常以 GBK 编码幸存着原文真实字词，注入 prompt 帮助 LLM 精确补全。
def gbk_survivors(raw_bytes):
    """提取原始字节中幸存可 GBK 解码的片段（去 U+FFFD 序列后分段解码）。"""
    segs = [s for s in re.split(b'\xef\xbf\xbd+', raw_bytes) if s]
    out = []
    for s in segs:
        # 跳过纯 ASCII/空格片段（无汉字信息量）
        if all(c < 128 for c in s):
            continue
        for enc in ('gb18030', 'gbk'):
            try:
                d = s.decode(enc)
                if any('一' <= c <= '鿿' for c in d):
                    out.append(d.strip())
                break
            except Exception:
                continue
    return ' '.join(out)

REPL = '�'
ROOT = Path(r"D:\_Progs\02Business\DeepFlow")
ENV_PATH = Path(r"D:\_Progs\01Center\kiro-gateway\.env")
MODEL = "claude-agnes-2-5-flash"
GATEWAY = "http://127.0.0.1:8000/v1/chat/completions"

MAX_PER_BLOCK = 16     # 每块最多损坏行数（A档）
MAX_PER_BLOCK_DENSE = 1  # 密集损坏(B/C档)每块损坏行数（1行成功率最高）
DENSE_RATIO = 0.05     # 超过该损坏比例视为密集

# 上下文锚行数（第三轮加大到12，帮助 LLM 对密集丢失行做段落级推断）
CTX_BEFORE = 12
CTX_AFTER = 12


def load_api_key():
    for line in ENV_PATH.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("PROXY_API_KEY="):
            v = line.split("=", 1)[1].strip().strip('"').strip("'")
            if v:
                return v
    raise RuntimeError("PROXY_API_KEY not found in kiro .env")


def read_file(path: Path):
    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8", errors="replace")
    if text.startswith('\ufeff'):
        text = text[1:]
    return text, has_bom


def write_file(path: Path, text: str, has_bom: bool):
    if has_bom:
        path.write_bytes(b"\xef\xbb\xbf" + text.encode("utf-8"))
    else:
        path.write_bytes(text.encode("utf-8"))


def find_bad_lines(lines):
    return [i for i, l in enumerate(lines) if REPL in l]


def make_blocks(bad_idx, lines, max_per_block):
    """把损坏行按固定大小切块（不按连续性），块内最多 max_per_block 个。"""
    return [bad_idx[i:i + max_per_block] for i in range(0, len(bad_idx), max_per_block)]


def build_prompt(lines, block, dense, anchors=None):
    """构造修复提示词：✓标记损坏行，含上下文锚。行号为1-indexed。

    anchors: {0-based line index: GBK幸存字}，注入原文幸存字词帮助 LLM 精确补全。
    """
    lo = max(0, block[0] - CTX_BEFORE)
    hi = min(len(lines) - 1, block[-1] + CTX_AFTER)
    out = []
    for i in range(lo, hi + 1):
        marker = "✓" if i in block else " "
        out.append(f"{marker}[L{i+1}] {lines[i]}")
    block_txt = "\n".join(out)

    anchor_txt = ""
    if anchors:
        parts = []
        for i in block:
            if i in anchors and anchors[i]:
                parts.append(f"  L{i+1}: {anchors[i]}")
        if parts:
            anchor_txt = (
                "额外线索：下面每行中，损坏处原始字节里有一部分以 GBK 编码幸存，"
                "按出现顺序列出了原文中的真实字词（只覆盖部分位置，�处可能缺失）。"
                "请务必把这些字词用作�补全的锚点：\n"
                + "\n".join(parts)
                + "\n"
            )

    strict = (
        "5. 除修复�处的汉字外，不得增删改任何其他字符（标点、空格、字母、表格符、行首井号等全部保持原样）"
    )
    return f"""你是文档修复助手。下面的 markdown 文本中，某些汉字被损坏成了 U+FFFD 替换符（显示为�）。标记 ✓ 的行包含损坏字符，需要修复。

规则：
1. 只修复 ✓ 标记的行，其余行（标记为空格的）一律原样保留
2. 把每个 � 根据上下文语义恢复为正确的汉字（如"错�?"→"错误"，"���?"→"注册"，"清�?"→"清单"）
3. 保持 markdown 格式、缩进、表格分隔符、行号前缀 [Lxx] 完全不变
4. 只输出一个 JSON 对象：键为 1-indexed 行号字符串（如 "28"），值为修复后的完整行内容（不含行号前缀和 ✓ 标记）
5. 必须覆盖所有 ✓ 标记的行，一个不能少
6. 不得输出 JSON 之外的任何文字，不要用代码围栏```json
{strict}

{anchor_txt}
待修复内容：
{block_txt}"""


def parse_json_resp(content: str):
    """从 LLM 输出提取 JSON 对象。"""
    # 去代码围栏
    content = re.sub(r"```(?:json)?", "", content).strip()
    m = re.search(r"\{.*\}", content, re.S)
    if not m:
        raise ValueError("no JSON object found")
    return json.loads(m.group(0))


def chat(api_key, prompt, max_tokens=6000):
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


def repair_block(api_key, lines, block, dense, raw_lines=None):
    """修复一个块，返回 {line_index_0based: fixed_line}。失败抛异常。"""
    anchors = {}
    if raw_lines is not None:
        for i in block:
            if i < len(raw_lines):
                s = gbk_survivors(raw_lines[i])
                if s:
                    anchors[i] = s
    prompt = build_prompt(lines, block, dense, anchors)
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
        if REPL in v:
            raise ValueError(f"line {i+1} still has U+FFFD")
        result[i] = v
    return result


def repair_file(api_key, rel_path, dry_run=False, max_workers=4):
    path = ROOT / rel_path
    text, has_bom = read_file(path)
    raw = path.read_bytes()
    # 原始字节按 \n 切分，供 GBK 幸存字提取（与 text 的行切分对齐）
    raw_lines = raw.split(b"\n")
    lines = text.split("\n")
    bad = find_bad_lines(lines)
    if not bad:
        return 0, 0

    # 密集 = 每损坏行平均 >4 个 U+FFFD（行损坏率高的低频文件不算密集）
    bad_char_total = sum(l.count(REPL) for l in lines)
    dense = (bad_char_total / max(len(bad), 1)) > 4
    max_per_block = MAX_PER_BLOCK_DENSE if dense else MAX_PER_BLOCK
    blocks = make_blocks(bad, lines, max_per_block)

    def try_block(block):
        """修复一个块（重试+失败拆半降级）。"""
        return (block, _repair_with_fallback(block, attempts=2))

    def _repair_with_fallback(block, attempts):
        # 网关偶发 502：单行块也重试，命中成功窗口；最多 3 次
        if len(block) == 1:
            attempts = max(attempts, 2)
        for a in range(attempts):
            try:
                return repair_block(api_key, lines, block, dense, raw_lines)
            except Exception:
                if a < attempts - 1:
                    time.sleep(1.2)
        if len(block) <= 1:
            return None
        # 拆半：小半块修复成功率高，且能明确失败行
        mid = max(1, len(block) // 2)
        r1 = _repair_with_fallback(block[:mid], 1)
        r2 = _repair_with_fallback(block[mid:], 1)
        merged = {}
        if r1:
            merged.update(r1)
        if r2:
            merged.update(r2)
        return merged or None

    fixed_total = 0
    fail_count = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = [ex.submit(try_block, b) for b in blocks]
        done = 0
        for fut in concurrent.futures.as_completed(futures):
            block, result = fut.result()
            done += 1
            if result is not None:
                for i, v in result.items():
                    lines[i] = v
                fixed_total += len(result)
            else:
                fail_count += 1
                print(f"  [FAIL] {rel_path} 块{done}/{len(blocks)} ({len(block)}行): 重试耗尽")
            if done % 20 == 0 or done == len(blocks):
                print(f"  ... {rel_path}: 块 {done}/{len(blocks)} 已修 {fixed_total} 行", flush=True)

    if not dry_run and fixed_total:
        write_file(path, "\n".join(lines), has_bom)
    return fixed_total, fail_count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="只修复指定相对路径文件")
    ap.add_argument("--dry-run", action="store_true", help="只计算不写盘")
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--all", action="store_true", help="扫描并修复全部 md（默认）")
    args = ap.parse_args()

    api_key = load_api_key()
    print(f"模型: {MODEL} | 网关: {GATEWAY} | 并发: {args.concurrency}", flush=True)

    if args.file:
        rel = Path(args.file)
        n, f = repair_file(api_key, rel, args.dry_run, args.concurrency)
        print(f"\n文件 {rel}: 修复 {n} 行, 失败 {f} 块")
        return

    # 收集所有含�的 md
    all_files = []
    for f in ROOT.rglob("*.md"):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if REPL in text:
            all_files.append(f.relative_to(ROOT))

    print(f"待修复文件 {len(all_files)} 个", flush=True)
    total_fixed, total_fail = 0, 0
    done_files = 0
    import threading
    lock = threading.Lock()

    def work_file(rel):
        nonlocal total_fixed, total_fail, done_files
        start = time.time()
        n, f = repair_file(api_key, rel, args.dry_run, args.concurrency)
        with lock:
            total_fixed += n
            total_fail += f
            done_files += 1
            state = f"修复{n}行" if n else "无损坏"
            print(f"[{done_files}/{len(all_files)}] {rel} — {state}, 失败{f}块, {time.time()-start:.1f}s", flush=True)

    file_workers = 4   # 文件级并发
    with concurrent.futures.ThreadPoolExecutor(max_workers=file_workers) as ex:
        list(ex.map(work_file, all_files))

    print(f"\n全部完成: 修复 {total_fixed} 行, 失败 {total_fail} 块", flush=True)


if __name__ == "__main__":
    main()
