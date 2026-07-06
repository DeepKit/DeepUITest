# WeChat 4.x WCDB 解密方法论 (Decryption Methodology)

## 概述

本文档记录 WeChat 4.x (已验证 4.1.10.53) WCDB 数据库的完整解密流程。
核心原理：在 `sqlite3_key()` 调用时捕获 `x'<64hex key><32hex salt>'` 格式的密钥字符串，
通过 HMAC-SHA512 验证，然后用 AES-256-CBC 逐页解密。

---

## Phase 1: 密钥捕获 (Key Capture)

### 方法 A: INT3 断点探针 (推荐)

使用 `probe_v4.py`，在以下 SQLCipher 内部函数设置 INT3 断点：

```
CfgHandler:  0x5032E70  — PRAGMA 处理器
Verify3:     0x5034DF3  — DB 头验证
```

**操作步骤**:
1. 运行 `python probe_v4.py`
2. 看到 `>>> SCAN QR CODE NOW <<<` 后立即扫码登录
3. 探针在每次断点命中时搜索 RDX/RCX/栈中的 `x'...'` hex 密钥字符串
4. 找到密钥后自动 HMAC 验证并保存

**关键时序**: DB 在 Weixin.dll 加载阶段打开。DebugActiveProcess 必须在 DB 打开前完成。
如果 0 hits（断点从未触发），说明 attach 太晚，重试。

### 方法 B: 内存扫描 (备选)

如果断点方法失败，可以从已登录的 WeChat 进程内存中扫描 hex 密钥字符串：

```bash
python ylt_style_scan.py
```

参考实现: [ylytdeng/wechat-decrypt](https://github.com/ylytdeng/wechat-decrypt)
- 扫描所有 Weixin.exe 进程的 MEM_COMMIT 区域
- 搜索正则: `x'([0-9a-fA-F]{64,192})'`
- 对每个匹配到的 64-hex 密钥，用 HMAC-SHA512 验证

### 方法 C: sqlite3 句柄扫描 (无断点，零崩溃风险)

```bash
python find_sqlite3_handle.py
```

- 滑动窗口扫描所有 heap 区域，寻找 sqlite3 结构体签名
- 签名: `+0x00 = 0x0003E80000000000`, `+0x28 = 0x40`, `+0x40 = 0x3`
- 追踪指针链: sqlite3+0x48 → Btree → Pager → codec_ctx → key
- **限制**: 在 4.1.10.53 中，key 在 DB 打开后立即清零

---

## Phase 2: 密钥验证 (Key Verification)

### HMAC-SHA512 验证公式

```python
import hashlib, hmac, struct

def verify_key(key_bytes, page1):
    """验证 32-byte 密钥是否匹配 DB 文件的第一页"""
    salt = page1[:16]                                    # bytes 0-15
    mac_salt = bytes(b ^ 0x3A for b in salt)             # XOR 0x3A
    mac_key = hashlib.pbkdf2_hmac('sha512', key_bytes, mac_salt, 2, dklen=32)
    hmac_data = page1[16:4096-80+16]                     # bytes 16-4032
    stored_hmac = page1[4096-64:4096]                    # bytes 4032-4095
    hm = hmac.new(mac_key, hmac_data, hashlib.sha512)
    hm.update(struct.pack('<I', 1))                      # page number LE32
    return hm.digest() == stored_hmac
```

### 将密钥匹配到数据库

```python
# 密钥格式: x'<64-hex-key><32-hex-salt>'
# salt 后缀匹配 DB 文件的前 16 字节

for key_hex, salt_suffix in captured_keys:
    key_raw = bytes.fromhex(key_hex)
    for db_path, page1 in db_files.items():
        if page1[:16].hex() == salt_suffix:
            if verify_key(key_raw, page1):
                print(f"MATCH: {db_path}")
```

---

## Phase 3: 数据库解密 (Database Decryption)

### 页面布局

```
SQLCipher v4 加密页面 (4096 bytes):
┌──────────┬─────────────────────┬──────────┬──────────────┐
│ Salt     │ Encrypted content   │ IV       │ HMAC-SHA512  │
│ 16B      │ 4000B               │ 16B      │ 64B          │
│ 0-15     │ 16-4015             │ 4016-4031│ 4032-4095    │
└──────────┴─────────────────────┴──────────┴──────────────┘

解密后重建为标准 SQLite 页面 (4096 bytes):
┌──────────────────────┬────────────────────┬──────────────────┐
│ "SQLite format 3\0"  │ Decrypted content  │ Zero padding     │
│ 16B (magic)          │ 4000B              │ 80B              │
│ 0-15                 │ 16-4015            │ 4016-4095        │
└──────────────────────┴────────────────────┴──────────────────┘
```

### 解密代码

```python
from Crypto.Cipher import AES

PAGE_SZ = 4096
RESERVE_SZ = 80
SQLITE_HDR = b'SQLite format 3\x00'

def decrypt_database(enc_path, out_path, key):
    with open(enc_path, 'rb') as fin, open(out_path, 'wb') as fout:
        for pgno in range(1, total_pages + 1):
            page = fin.read(PAGE_SZ)
            iv = page[PAGE_SZ - RESERVE_SZ : PAGE_SZ - RESERVE_SZ + 16]

            if pgno == 1:
                enc = page[16 : PAGE_SZ - RESERVE_SZ]  # skip salt
                plain = AES.new(key, AES.MODE_CBC, iv).decrypt(enc)
                full = SQLITE_HDR + plain + b'\x00' * RESERVE_SZ
            else:
                enc = page[:PAGE_SZ - RESERVE_SZ]
                plain = AES.new(key, AES.MODE_CBC, iv).decrypt(enc)
                full = plain + b'\x00' * RESERVE_SZ

            fout.write(full)
```

**重要**: 不要修改 page_size (4096) 和 reserved (80)。B-tree 索引基于 usable_size=4016 构建。

### 验证解密结果

```python
import sqlite3
conn = sqlite3.connect(decrypted_path)
tables = conn.execute(
    "SELECT name FROM sqlite_master WHERE type='table'"
).fetchall()
conn.close()
```

---

## 如果加密方式变更 (Future Adaptation)

### 1. 检测变化
- 检查 DB 前 16 字节是否为随机数据（加密标志）
- 检查文件大小是否仍是 4096 的倍数
- 用已知 key 验证 HMAC，如果失败说明参数变化

### 2. 暴力探测新参数
```python
for page_size in [512, 1024, 2048, 4096, 8192, 16384]:
    for reserve in [0, 16, 32, 48, 64, 80]:
        for hmac_hash in ['sha512', 'sha256', 'sha1']:
            # 尝试 HMAC 验证
```

### 3. 重新定位断点地址
如果 Weixin.dll 更新导致 RVA 变化：
1. 在 .rdata 段搜索 "PRAGMA cipher_" 和 "SQLite format 3"
2. 在 .text 段搜索 `LEA rcx, [rip + disp32]` 引用这些字符串
3. 找到引用函数即为新的 CfgHandler/Verify3 地址

### 4. 密钥格式变化
- 如果 hex 字符串格式变化，搜索更宽泛的正则: `rb"x'([0-9a-fA-F]{32,256})'"`
- 如果密钥被 XOR 混淆，尝试已知常量: `E8AC38291BD79C663F4654D4F9D7537E4ACC81E5CAD1412C7BD0F6E73138D2CF`
- 如果密钥是纯二进制，使用滑动窗口 HMAC 验证（扫描所有 32-byte 窗口）

---

## 参考

- [ylytdeng/wechat-decrypt](https://github.com/ylytdeng/wechat-decrypt) — HMAC 验证公式和页面重建
- [SQLCipher 4](https://github.com/sqlcipher/sqlcipher) — codec_ctx 布局和加密参数
- [WCDB](https://github.com/Tencent/wcdb) — 腾讯微信数据库框架

## 当前会话结果

- **WeChat 版本**: 4.1.10.53
- **解密数据库**: 17/19
- **密钥来源**: WxHybridTap v1 (WxTap3), 24 个唯一密钥
- **解密文件**: `D:\tmp\decrypted_dbs\`
- **密钥文件**: `D:\tmp\found_keys\all_keys.json`
- **核心工具**: `probe_v4.py`, `verify_old_keys.py`, `decrypt_all_dbs.py`