# DeepAxis 开发任务
> **创建**: 2026-06-14  
> **更新**: 2026-08-09 — **BUG-052 实机修复完成** (微信检测/窗口/关闭/密钥诊断) + **多模型密钥架构方案定稿**
> **编译器**: Delphi 13.1 (Embarcadero Studio 37.0) — dcc64.exe (项目为 Delphi, 非 bcc64)
> **状态**: ✅ Compilation passed / ✅ 65/65 全绿 / ⚠️ 密钥获取需架构重构 (微信 4.1.11.55 不兼容)

---

## Build & Test Status

> 📋 **Latest Status** (2026-08-09): **Build #21 SUCCESSFUL** — BUG-052 实机修复
>
> | Target | Command | Result |
> |------|------|------|
> | DeepAxis.exe | `dcc64 DeepAxis.dpr -B -Ebin -Ndcu` | ✅ **0 errors** (7125508 bytes) |
> | DeepAxisTestRunner.exe | `dcc64 tests\DeepAxisTestRunner.dpr -B -Ebin -Ndcu` | ✅ **65/65 passed** |
> | 冒烟运行 | DeepAxis.exe | ✅ 启动 560×220 小窗, 解密成功放大 1600×1000, 退出码 0 |

---

## Next Priorities (2026-08-09 更新)

### ⏭️ Priority P0 — 密钥获取架构重构 (当前唯一硬阻塞)

> **背景**: 微信 4.1.11.55 轮换密钥, 旧内存扫描 (硬编码偏移, 适配 4.1.10.53) 全失效。多模型圆桌 (GLM/DeepSeek/Kimi) 已定稿方案, 见 history.md 2026-08-09 块。

- [x] **#91 密钥提取架构骨架**: ✅ 已完成 — IKeyExtractor 接口 + TKeyExtractorChain 方法链调度 + TWeChatVersionProbe 版本指纹 (PE 版本 + 进程路径) + TKeyVerifier 自验证 (单轮 PBKDF2 + contact.db 页1 HMAC) + 3 个 provider (saved_keys/version_specific/entropy_scan) + 降级诊断。TestKeyChain 实测: 版本探测 4.1.11.55 正确, 链按序执行 + 自验证拦截错误候选
- [ ] **#92 M1 边界挂钩逆向**: x64dbg 定位 4.1.11.55 的 sqlite3_key / 密钥派生函数, 提取字节签名 (带通配符 pattern)。**恢复当前版本密钥的最短路径** (需逆向环境, 3-5 天)
- [ ] **#93 Hook 注入器**: C/C++ + MinHook 写 wechat_key_hook.dll, hook 密钥函数经命名管道回传; Delphi 侧注入逻辑。最强兜底 (杀软可能拦截, 需测试)
- [ ] **#94 签名库热更机制**: 版本指纹 (PE SHA256 + DLL SHA256 + key_info 魔数) 比对, 未知版本自动进入"未认证模式 + 通用签名链 + 一键诊断上报" (把适配从"改代码发版"变"改一行签名")

### ⏭️ Priority P1 — 实机验证 (密钥解决后)

- [ ] **#72b 实机验证**: 5 场景 (smAssist/smFinal/防骚扰/Delete/UpdateRemark) — 代码就绪, 密钥获取恢复后执行

### 🔧 Priority P2 — 后续演进

- [ ] **key_info.db 专有加密解析** (L4 长期研究项): 已确认非 DPAPI/标准 AES/常见派生, 需逆向微信专有算法; 可用 M1 Hook 拿到的明文密钥反推加密机制
- [ ] **在线查询兜底** (可选插件, 默认关闭): 社区密钥库/自建服务, 需权衡隐私

---

## 已完成里程碑 (已归档 history.md)

- 2026-08-09: BUG-052 实机修复 — 微信进程误检/按钮2重启/关闭217/启动小窗/密钥诊断 + 多模型密钥架构定稿
- 2026-08-06: P0c 门禁 (#81-#84) + 功能闭环 (#85-#90) + P2 演进 (i18n/阈值/TagProfile) 全部完成
- 2026-08-06: BUG-048/050 根治 + 功能实现全面核查
- 2026-08-03: P0 Phase 3 — TagProfile 参数化落地 + 编译修复
- 2026-08-01: DeepBase 集成深度审计 — 三大 P0 反模式发现
- 2026-07-16: BUG-043 启动崩溃三版演进根治
- 2026-07-08: 阶段 8/9 — 标签建议 UI + L2a 写回 + Delete 降级 + 广告观测列
