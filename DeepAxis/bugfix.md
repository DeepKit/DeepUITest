# DeepAxis Bug 修复记录
> **创建**: 2026-06-14

---

## BUG-2026-06-14-001: WxDecryptProbe — 微信 4.x 解密失败

### 现象
- WxDecryptProbe v0.2 在微信 4.1.10.30 上运行
- A0 数据目录扫描: ✅ 成功 (`D:\xwechat_files\...`)
- A1 进程定位: ✅ 成功 (Weixin.exe PID 10236, Weixin.dll 0x7FFFA0AF0000)
- A2 内存扫描: ❌ **0 高熵密钥候选** (175MB Weixin.dll 全量扫描, entropy > 7.0)
- A2 fallback (已知偏移): ❌ **0/5 命中** ($1131B64, $1A30000, $1F0B000, $1F30000, $2100000)
- A3 数据库验证: 未执行 (无密钥可用)

### 根因分析
微信 4.x 的加密方案与 3.x 根本不同:
1. 数据库 header **不是 "SQLite format 3"** — 全部加密字节, 无明文特征
2. Weixin.dll **无 SQLite/SQLCipher 字符串** — 可能使用 WCDB (WeChat Database) 私有格式
3. 内存中无 32 字节高熵密钥 — 密钥可能存储在:
   - 其他 DLL (mmmojo_64.dll / ilink2.dll / XNet.dll)
   - 加密存储文件 (DPAPI 保护?)
   - 服务端下发 (不持久化?)
4. 微信 4.1.x 可能使用 **每数据库独立的加密方案** (不同于旧版的单一内存密钥)

### 已尝试方案
- ✅ 进程名适配: WeChat.exe → Weixin.exe
- ✅ DLL名适配: WeChatWin.dll → Weixin.dll
- ✅ 数据目录适配: WeChat Files\...\Msg\ → xwechat_files\...\db_storage\message\
- ✅ DB文件名适配: MicroMsg.db → message_0.db
- ✅ 内存全量扫描 (entropy-based, step=8)
- ✅ 已知偏移枚举 (5个旧版偏移)
- ❌ 开源代码搜索 (PyWxDump 已删库, SharpWxDump HTTP 451)

### 下一步
- [ ] 在 Weixin.dll 上做动态分析 (IDA Pro / Ghidra + x64dbg 断点) 
- [ ] 扫描其他大 DLL (mmmojo_64.dll, XNet.dll, ilink2.dll) 寻找密钥候选
- [ ] 检查 DPAPI 加密的本地文件 (可能的密钥存储)
- [ ] 研究 WCDB 框架的解密方法
- [ ] 一旦密钥获取方式明确 → 更新 WxDecryptProbe v0.3 → 更新 tasks.md

### 影响范围
- P0a 任务 (数据可达性) — **阻塞**
- DeepAxis 整体 P0 进度 — **阻塞**
- DeepBase 32.data (SQLCipher 规格) — 可能需要重新设计以支持 4.x 加密

### 备用方案
如果逆向不可行: 转向 UIA 只读面板方案 (通过 Windows UI Automation 读取微信聊天列表和消息)
