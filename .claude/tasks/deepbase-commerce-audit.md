# DeepBase Commerce Module Audit

**Date**: 2026-05-19
**Scope**: `DeepBase/Features/DeepBase.Commerce.*.pas` (13 files)
**Status**: Issues identified, awaiting fix

---

## Critical (生产环境会导致错误行为)

### C1. Firebase / Supabase 适配器��无限配额 (-1) 永远无法消费

- **File**: `Adapter.Firebase.pas:904`, `Adapter.Supabase.pas:706`
- **Detail**:
  - Firebase: `AEntitlement.RemainingQuota >= ACount` — 当 quota=-1 时 -1>=任何正数为 False，跳过更新
  - Supabase: `AEntitlement.RemainingQuota < ACount` — 当 quota=-1 时 -1<任何正数为 True，直接 `Exit(False)`
- **Impact**: 无限期/无限次数产品的 entitlement 通过云存储后端永远不会扣减配额
- **Fix**: 在判断前先检查 `RemainingQuota < 0`，若是则跳过配额扣减直接返回 True

### C2. Firebase 适配器：`ConsumeEntitlement` 配额不足时仍返回 True

- **File**: `Adapter.Firebase.pas:904-930`
- **Detail**: 当 `RemainingQuota < ACount` 但 >= 0 时，跳过更新块，但第 930 行 `Result := True` 在 if 块外面
- **Impact**: 配额不足时调用者认为消费成功，实际什么都没扣
- **Fix**: 当 quota 不够时 `Exit(False)`

### C3. Firebase 适配器：所有 `Find*` 方法泄漏 JSON 对象

- **File**: `Adapter.Firebase.pas:525-532` 等 (`FindUserById`, `FindProduct`, `FindOrderById`, `FindPaymentByOrderId`, `FindEntitlement`)
- **Detail**: `FirestoreGet` 返回的 `TJSONObject` 从未被 Free
- **Impact**: 长期运行的服务端进程会持续泄漏内存
- **Fix**: 加 `try/finally Doc.Free`

### C4. Supabase 适配器：所有 `Find*` 方法泄漏 JSON 对象

- **File**: `Adapter.Supabase.pas` 所有 `Find*` 方法
- **Detail**: 与 Firebase 同样的问题，`SupabaseGet` 返回的对象未被释放
- **Impact**: 同 C3
- **Fix**: 加 `try/finally Obj.Free`

### C5. PaymentBridge：所有工厂方法永远抛异常，整个单元是死代码

- **File**: `PaymentBridge.pas:99-103, 212, 227, 238, 252`
- **Detail**: `EnsurePaymentBridgeServerOnly` 无条件 raise，四个 `Create*NotificationVerifier` 都调用了它
- **Impact**: 服务端无法使用这些工厂函数创建支付回调验证器
- **Fix**: 用编译期指令 `{$IFNDEF DESKTOP}` 替代运行时异常；或加 TODO 注释标记为未实现

---

## High (数据丢失或逻辑错误)

### H1. Supabase 适配器：`PaymentToJson` 未序列化 channel 字段

- **File**: `Adapter.Supabase.pas:404`
- **Detail**: `Result.AddPair('channel', '')` 写死空串，未调用 `ChannelToString(APayment.Channel)`
- **Impact**: 非 Native 渠道的支付记录存入后读取时总是丢失为 `cpcNative`

### H2. License Snapshot 过期校验时区错误

- **File**: `SafeClient.pas:615`
- **Detail**: `TryISO8601ToDate(ASnapshot.ExpiresAtISO, ExpiresAt, True)` 第三个参数 `True` 表示输入为本地时间，但服务器下发的是 UTC ISO 时间戳
- **Impact**: 非 UTC 时区客户端校验结果可能错误（提前过期或延迟过期）
- **Fix**: 改为 `False` 表示 UTC 输入

### H3. UpgradeFlow：孤订单清理无效

- **File**: `UpgradeFlow.pas:131-136`
- **Detail**: 注释说 "best-effort close"，但代码只调了 `GetOrder`（读取），没有调任何 close/update 操作
- **Impact**: 支付意图创建失败后，订单永远停留在 `cosCreated` 状态，形成垃圾数据
- **Fix**: 实现实际的订单关闭逻辑，或调用后端 close 接口

---

## Medium (并发/健壮性)

### M1. 三处重复的 entitlement 可用性判断逻辑

- **File**: `Service.pas:388`, `Permissions.pas:58`, `UpgradeFlow.pas:52`
- **Detail**: `IsEntitlementUsable` / `IsEntitlementCurrentlyUsable` / `IsUpgradeEntitlementUsable` 逻辑几乎相同
- **Impact**: 业务规则分散，任何修改都需要同步三处
- **Fix**: 统一到 `DeepBase.Commerce.Types` 或一个共享 unit 中

### M2. TOCTOU 竞态：Entitlement 消费非原子操作

- **File**: `Service.pas:422`, `Permissions.pas:166`, 两个云适配器
- **Detail**: 先查询再扣减，中间可被并发请求穿透；Supabase 虽用了 optimistic filter 但仍非真正原子事务
- **Impact**: 并发消费可能导致超额扣减
- **Fix**: 对于 HTTP 后端场景，服务端应使用数据库级原子操作（如 `UPDATE ... WHERE remaining_quota >= N`）

### M3. Backend.Http：`ConsumeEntitlement` 默认 success=True (fail-open)

- **File**: `Backend.Http.pas` (~line 761)
- **Detail**: `JsonValueAsBool(Json, SCommerceFieldSuccess, True)` — 响应缺少 success 字段时默认成功
- **Fix**: 默认值改为 `False`

### M4. `JsonUtil.ParseJsonObject` 对空输入返回空对象

- **File**: `JsonUtil.pas:123`
- **Detail**: `ABody = ''` 时返回空 `TJSONObject` 而非 nil
- **Impact**: 调用者期望必有数据时拿到空 record 默认值而非异常

---

## Low (代码质量/防御性)

### L1. Firebase `FindUserByIdentity`：`FreeAndNil(Results)` 后 finally 中 `Results.Free`

- **File**: `Adapter.Firebase.pas:570-575`
- **Detail**: 安全但令人混淆，`FreeAndNil` 后 finally 的 `.Free` 是 no-op

### L2. InMemoryStorage：`FindUserById` 大小写敏感

- **File**: `Storage.pas:145`
- **Detail**: UserID 查找大小写敏感，与 ProductKey 的规范化处理不一致

### L3. PaymentBridge：PayPal 验签传空 CertUrl

- **File**: `PaymentBridge.pas:179`
- **Detail**: `FPayPalClient.VerifyWebhookSignature(... '')` 第五参数为空
- **Impact**: 若该单元被启用，PayPal webhook 验签可能失败

---

## Summary

| Severity | Count | Key Issues |
|----------|-------|------------|
| Critical | 5 | JSON 内存泄漏×2、无限配额无法消费×2、PaymentBridge 死代码 |
| High | 3 | Channel 字段丢失、时区错误、孤订单未清理 |
| Medium | 4 | 重复逻辑、TOCTOU 竞态、fail-open 默认值、空输入处理 |
| Low | 3 | 代码质量 |
