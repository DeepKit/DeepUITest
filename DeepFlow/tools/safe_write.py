# -*- coding: utf-8 -*-
"""受控写文件工具 — 编码污染源头防线（治本层）。

根因复盘：f7a9b2f2 批量替换脚本用错编码读写，把 UTF-8 汉字按字节切断成
U+FFFD(�)，引入 2209 处**不可逆**损坏（U+FFFD 一旦产生无法恢复原文）。
本工具强制四条防线，杜绝"裸脚本直接覆写"导致的同类事故：

  1. 只允许显式 utf-8 编码（杜绝"用错编码"）；
  2. 写前校验污染签名（U+FFFD / 汉字+?），默认拒绝损坏内容落盘；
  3. 原子写：临时文件 + fsync + os.replace，防截断/半写/进程中断留残文件；
  4. 写后重读校验字节一致 + 签名复核，防写坏。

用法：
    from safe_write import atomic_write_text, detect_corruption
    atomic_write_text(path, text)                    # 干净内容正常写
    atomic_write_text(path, text, allow_corrupted=True)  # 明确允许污染（中间产物）
    sig = detect_corruption(text)                    # {'ufffd': n, 'hanzi_qmark': n}

配套门禁（下游防线，进库前拦截）：
    .pre-commit-config.yaml  /  .git/hooks/pre-commit  — 拦污染进 commit
"""
import os
import pathlib
import re
import tempfile

UFFFD = '�'  # U+FFFD Replacement Character
Q_PAT = re.compile(r'[一-鿿]\?')  # 汉字+? 占位残留
BOM = b'\xef\xbb\xbf'


class CorruptedWriteError(ValueError):
    """写入内容含编码污染签名，被受控工具拒绝。"""


def detect_corruption(text: str) -> dict:
    """统计文本中的编码污染签名。返回 {'ufffd': int, 'hanzi_qmark': int}。"""
    return {
        'ufffd': text.count(UFFFD),
        'hanzi_qmark': len(Q_PAT.findall(text)),
    }


def atomic_write_text(
    path,
    text,
    *,
    encoding='utf-8',
    has_bom=False,
    allow_corrupted=False,
    validate=True,
):
    """受控写文本文件：显式 UTF-8 + 污染校验 + 原子写 + 写后重读校验。

    Args:
        path: 目标路径（str 或 Path）。
        text: 要写入的文本。
        encoding: 只允许 'utf-8'，传其他值直接报错（治 f7a9b2f2 用错编码根因）。
        has_bom: 原文件带 BOM 则保留之。
        allow_corrupted: 是否允许写入含污染签名内容。默认 False，
            检测到 U+FFFD 或 汉字+? 即抛 CorruptedWriteError。
        validate: 写后重读校验字节一致与签名复核（默认 True）。

    Raises:
        CorruptedWriteError: 内容含污染签名且 allow_corrupted=False。
        ValueError: encoding 非 utf-8。
        OSError: 写后校验失败。
    """
    path = pathlib.Path(path)
    if encoding != 'utf-8':
        raise ValueError(
            "safe_write 只允许 utf-8 编码（防重蹈 f7a9b2f2 用错编码覆辙）")

    if not allow_corrupted:
        sig = detect_corruption(text)
        if sig['ufffd'] or sig['hanzi_qmark']:
            raise CorruptedWriteError(
                f"拒绝写入 {path.name}: U+FFFD={sig['ufffd']} 处, "
                f"汉字+?={sig['hanzi_qmark']} 处。"
                f"（U+FFFD 不可逆，请先修复；如确需写中间产物用 "
                f"allow_corrupted=True）")

    data = text.encode('utf-8')
    if has_bom:
        data = BOM + data

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + '.', suffix='.tmp')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())

        if validate:
            back = pathlib.Path(tmp).read_bytes()
            if back != data:
                raise OSError(f"写后校验失败: {path.name} 字节不一致")
            if not allow_corrupted:
                back_text = back.decode('utf-8')
                if has_bom and back_text.startswith(UFFFD):
                    back_text = back_text[1:]
                sig = detect_corruption(back_text)
                if sig['ufffd'] or sig['hanzi_qmark']:
                    raise CorruptedWriteError(
                        f"写后校验拦截 {path.name}: 落盘内容含污染签名 {sig}")

        os.replace(tmp, path)  # 原子替换，防半写/截断
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


if __name__ == '__main__':
    import sys
    # 命令行：safe_write.py <path>  — 检查文件是否含污染签名（只读，不写）
    for p in sys.argv[1:]:
        try:
            t = pathlib.Path(p).read_text(encoding='utf-8', errors='replace')
        except OSError as e:
            print(f"{p}: 读取失败 {e}")
            continue
        sig = detect_corruption(t)
        if sig['ufffd'] or sig['hanzi_qmark']:
            print(f"{p}: 污染 U+FFFD={sig['ufffd']}, 汉字+?={sig['hanzi_qmark']}")
        else:
            print(f"{p}: 干净")
