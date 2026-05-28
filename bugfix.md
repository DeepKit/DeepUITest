# Bug 登记与修复记录
> 跨项目级别的 Bug 跟踪

---

## 2026-05-24 DeepSpec Phase 2~4 开发中的 Bug 修复

### BUG-DS-003: ReadTreeFile 旧 YAML 缺失 gen_status/review_status 字段 (P1)
- 发现日期: 2026-05-24
- 严重性: Medium
- 文件: `DeepSpec/src/services/DeepSpec.Services.SpecStore.pas` (ReadTreeFile)
- 问题: 旧版 YAML 只有 `status` 字段，直接解析为 gsDraft/rsUnreviewed 不符合旧数据语义
- 修复: 添加向后兼容映射 — 缺 gen_status 时从 status 派生（confirmed→gsConfirmed, rejected→gsSkipped 等）
- 状态: ✅ 已修复

### BUG-DS-004: TNodeStatus 到 TGenStatus/TReviewStatus 映射缺失 (P1)
- 发现日期: 2026-05-24
- 严重性: Medium
- 文件: `DeepSpec/src/models/DeepSpec.Models.pas` (TSpecEnums)
- 问题: 新增 GenStatus/ReviewStatus 正交维度但没有从旧 Status 派生的逻辑
- 修复: 添加 `NodeStatusToGenStatus` / `NodeStatusToReviewStatus` 映射函数
- 状态: ✅ 已修复

### BUG-DS-005: Inspector 硬编码 status=candidate (P2)
- 发现日期: 2026-05-23
- 严重性: Low
- 文件: `DeepSpec/src/providers/DeepSpec.Providers.Inspector.pas:51`
- 问题: `GetProperties` 硬编码 `status=candidate`，不从实际节点数据读取
- 修复: 改为从 `ANode.Status` 读取实际值
- 状态: ✅ 已修复

### BUG-DS-006: Validation TRegEx 重复编译 (P3)
- 发现日期: 2026-05-23
- 严重性: Low
- 文件: `DeepSpec/src/core/DeepSpec.Validation.pas:193`
- 问题: `ValidateNodeId` 每次 call 都重新编译同一个 TRegEx
- 修复: 提取为单元级 `class var` 懒初始化单例
- 状态: ✅ 已修复

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
- 状态: ✅ 已修复（实现 BCrypt AES-256-GCM 解密）
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
- 状态: ✅ 已修复（统一使用 Payment.Types 枚举，顺序一致）
- 发现日期: 2026-05-15
- 严重性: 🟠 Medium
- 文件: `DeepBase/Tests/Test.DeepBase.Payment.pas`
- 问题:
  - 25 个测试覆盖了订单校验、哈希工具、签名安全
  - 但没有任何测试覆盖 WeChatPay `VerifyNotification` 流程
  - 如果有此测试，BUG-PAY-001 会在 CI 中被立即发现
- 修复方案:
  - 补充 WeChatPay 通知解密的集成测试（使用已知密文/密钥/nonce 验证）
- 状态: ✅ 已修复（添加 17 个集成测试用例）
- 发现日期: 2026-05-15
- 严重性: 🟢 Low
- 文件: `DeepBase/ThirdParty/Payment/DeepBase.Payment.pas` (TPaymentConfig)
- 问题:
  - `TPaymentConfig` 默认使用 Windows DPAPI 加密 API 密钥
  - 非 Windows 部署时编译失败或运行时报错
  - 已有 `Core/DeepBase.Security.SecretStore.pas` 提供跨平台方案但未被 Payment 使用
- 修复方案:
  - Payment 模块改用 `ISecretStore` 接口存取密钥
- 状态: ✅ 已修复（改用 ISecretStore 接口）

---

## 2026-05-28 ArtifactOS DeepBase 集成整改

### BUG-AO-001: DB.Connection 调用 DeepBase.GetConfig 编译失败 (P0)
- 发现日期: 2026-05-28
- 严重性: Critical（无法编译）
- 文件: `ArtifactOS/src/core/ArtifactOS.Core.DB.Connection.pas:85-89`
- 问题: `DeepBase.GetConfig(...)` 语法被编译器解释为 "unit.function"，Delphi 不支持这种调用形式
- 修复: 改为 `uses DeepBase.Config` 后直接调用全局函数 `GetConfig(...)`，`LoadSecret` 同理
- 状态: ✅ 已修复 (d699db3)

### BUG-AO-002: ShadowRun AbortRun SQL 字符串语法错误 (P0)
- 发现日期: 2026-05-28
- 严重性: Critical（无法编译）
- 文件: `ArtifactOS/src/services/ArtifactOS.Services.ShadowRun.pas:85`
- 问题: Delphi 字符串内嵌引号 + JSON 拼接导致 `')' expected but identifier 'WHERE' found`
- 修复: 改为 `ExecuteJson` + JSON 参数绑定，消除字符串拼接
- 状态: ✅ 已修复 (d699db3)

### BUG-AO-003: QualityGate Body.Split.Length 不合法 (P1)
- 发现日期: 2026-05-28
- 严重性: High（无法编译）
- 文件: `ArtifactOS/src/services/ArtifactOS.Services.QualityGate.pas:78`
- 问题: `Body.Split(['\n\n']).Length` — Delphi 动态数组没有 `.Length` 属性
- 修复: 改为 `Length(Body.Split([sLineBreak + sLineBreak]))`
- 状态: ✅ 已修复 (d699db3)

### BUG-AO-004: .env.example 暴露真实数据库用户名 (P1)
- 发现日期: 2026-05-28
- 严重性: Medium
- 文件: `ArtifactOS/.env.example:5`
- 问题: `ARTIFACTOS_DB_USER=fuyi01` — 模板文件包含真实用户名
- 修复: 改为 `ARTIFACTOS_DB_USER=your_db_user`
- 状态: ✅ 已修复 (d699db3)

### BUG-AO-005: RealPublishGate 未覆盖 published 状态 (P1)
- 发现日期: 2026-05-28
- 严重性: High
- 文件: `ArtifactOS/db/migrations/004_real_publish_gate.sql:69`
- 问题: Guard trigger 只拦截 `queued` / `submitting`，攻击者可跳过 gate 直接设为 `published`
- 修复: 将 `published` 加入拦截列表
- 状态: ✅ 已修复 (d699db3)

### BUG-AO-006: SourcePack loading_level 缺写保护 (P1)
- 发现日期: 2026-05-28
- 严重性: Medium
- 文件: `ArtifactOS/db/migrations/022_sourcepack_write_protection.sql`
- 问题: Guard trigger 保护了 `display_name/source_root/pack_type` 但遗漏 `loading_level`
- 修复: 将 `loading_level` 纳入保护范围；同时补 `metadata jsonb` 列
- 状态: ✅ 已修复 (d699db3)

### BUG-AO-007: SourceCoreFile seed 在空库上执行报错 (P2)
- 发现日期: 2026-05-28
- 严重性: Medium
- 文件: `ArtifactOS/db/migrations/025_sourcepack_core_files.sql:32`
- 问题: `SELECT id INTO sp_id FROM source_pack LIMIT 1` 返回 NULL 时后续 INSERT 全部失败
- 修复: 加 `IF sp_id IS NULL THEN RAISE NOTICE ... RETURN; END IF;` 防御
- 状态: ✅ 已修复 (d699db3)

---

## 2026-05-20 DeepSpec 编译错误

### BUG-DS-001: Models.pas 三处语法错误 (P0)
- 发现日期: 2026-05-20
- 严重性: Critical（无法编译）
- 文件: `DeepSpec/src/models/DeepSpec.Models.pas`
- 问题:
  - `RiskLevelToStr` 声明为 `function` 而非 `class function`，与实现不匹配
  - `DataKindFromStr` 中 `'state'` 条件缺少 `=` 号：`else if LLower 'state' then`
  - `RiskLevelToStr` 中 `rlCritical` 分支缺少 `:`：`rlCritical Result :=`
- 修复: 补充 `class` / `=` / `:` 关键字和符号
- 状态: 已修复 (commit `2a799fe`)

### BUG-DS-002: Writer.pas 四处语法错误 (P0)
- 发现日期: 2026-05-20
- 严重性: Critical（无法编译）
- 文件: `DeepSpec/src/core/DeepSpec.Yaml.Writer.pas`
- 问题:
  - `WriteBoolKV` 使用非法表达式 `if AValue then 'true' else 'false'`（Delphi 不支持内联 if-then 作为表达式）
  - `WriteQuotedKVtarget_entity'` 缺少左引号和左括号，应为 `WriteQuotedKV('target_entity'`
  - `A.Cardinality` 引用不存在的变量 `A`，应为 `ANode.Cardinality`
  - uses 缺少 `System.StrUtils`（`IfThen` 函数所在单元）
- 修复: 改用 `IfThen(AValue, 'true', 'false')`，补全引号/括号/变量名���增加 uses
- 状态: 已修复 (commit `2a799fe`)
