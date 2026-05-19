# Bug 登记与修复记录
> 跨项目级别的 Bug 跟踪

---

## 2026-05 DeepBase 认证/付费模块审查

### BUG-PAY-001: WeChatPay 通知解密完全失效 (P0)
- 发现日期: 2026-05-15
- 严重性: 🔴 Critical
- 文件: `DeepBase/ThirdParty/Payment/DeepBase.Payment.pas:775-779`
- 调用方: `DeepBase/ThirdParty/Payment/DeepBase.Payment.WeChatPay.pas:1165`
- 问题:
  - `TPaymentHelper.AES256GCMDecrypt` 是空桩实现，永远返回空字符串
  - WeChatPay `VerifyNotification` 调用该方法解密回调通知体
  - 解密结果为空 → 直接 Exit → 微信支付回调永远不会被正确处理
  - 用户付款成功但系统收不到确认
- 根因:
  - Payment 单元设计上不引入 OpenSSL/CNG 依赖，留下了替换接口
  - 但 WeChatPay 调用方没有覆盖或注入真实实现
  - `Core/DeepBase.Crypto.OpenSSL.pas:460-530` 已有完整可用的 `OpenSSL_AES256GCM_Decrypt`（含单测覆盖）
- 修复方案:
  - 在 `TPaymentHelper.AES256GCMDecrypt` 中调用 `OpenSSL_AES256GCM_Decrypt`
  - 或改为可注入的加密策略接口，让 TWeChatPayClient 构造时注入
- 状态: 🔲 待修复

### BUG-PAY-002: 两套支付类型系统枚举值冲突 (P1)
- 发现日期: 2026-05-15
- 严重性: 🟡 High
- 文件:
  - `DeepBase/ThirdParty/Payment/DeepBase.Payment.pas:28` — `TPaymentProvider = (ppAlipay, ppWeChatPay, ppStripe, ppPayPal)`
  - `DeepBase/ThirdParty/Payment/DeepBase.Payment.Types.pas:17` — `TPaymentProvider = (ppStripe, ppPayPal, ppAlipay, ppWeChatPay)`
- 问题:
  - 两个单元各自定义了 `TPaymentProvider`、`TPaymentStatus` 等枚举
  - 枚举值顺序不同：Stripe 在 Types.pas 中 ordinal=0，在 Payment.pas 中 ordinal=2
  - 如果混用（序列化/反序列化、数据库存储），会导致 provider 类型错乱
- 修复方案:
  - 统一为一套类型定义（保留 `Payment.Types.pas` 作为唯一来源）
  - 或在 `Payment.pas` 中 uses `Payment.Types` 并删除重复定义
- 状态: 🔲 待修复

### BUG-PAY-003: 支付测试未覆盖 WeChatPay 通知解密 (P2)
- 发现日期: 2026-05-15
- 严重性: 🟠 Medium
- 文件: `DeepBase/Tests/Test.DeepBase.Payment.pas`
- 问题:
  - 25 个测试覆盖了订单校验、哈希工具、签名安全
  - 但没有任何测试覆盖 WeChatPay `VerifyNotification` 流程
  - 如果有此测试，BUG-PAY-001 会在 CI 中被立即发现
- 修复方案:
  - 补充 WeChatPay 通知解密的集成测试（使用已知密文/密钥/nonce 验证）
- 状态: 🔲 待修复

### BUG-PAY-004: DPAPI 密钥存储锁死 Windows (P3)
- 发现日期: 2026-05-15
- 严重性: 🟢 Low
- 文件: `DeepBase/ThirdParty/Payment/DeepBase.Payment.pas` (TPaymentConfig)
- 问题:
  - `TPaymentConfig` 默认使用 Windows DPAPI 加密 API 密钥
  - 非 Windows 部署时编译失败或运行时报错
  - 已有 `Core/DeepBase.Security.SecretStore.pas` 提供跨平台方案但未被 Payment 使用
- 修复方案:
  - Payment 模块改用 `ISecretStore` 接口存取密钥
- 状态: 🔲 待修复（低优先级，当前仅 Windows 部署）
