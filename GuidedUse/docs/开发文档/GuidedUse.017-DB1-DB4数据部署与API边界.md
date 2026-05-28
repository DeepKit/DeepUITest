# GuidedUse.017 - DB1-DB4 数据部署与 API 边界

> 状态：开发文档初版
> 用途：把 DeepBase 的 DB1 + DB2 + DB3 + DB4 规范落到 GuidedUse，明确本地 GuidePackage、云端业务库、统一认证支付框架的职责分界

---

## 1. 冻结判断

```text
GuidedUse 第一阶段只依赖本地 DB1 + DB2。
DB3 是公网业务后端的 PG 数据库，用于云端善用包、模板市场、同步和统计。
DB4 是 DeepBase 框架统一提供的认证、支付与权益后端能力，用于账号、订单、支付、订阅和权益。
桌面端不直连 DB3 / DB4；DB3 走 GuidedUse 业务 API，DB4 走 DeepBase Commerce/Auth 模块。
```

这里的“DB3 和 DB4 放在公网”应理解为：

```text
公网开放的是 API 服务。
PG 数据库和认证支付数据库本体不直接暴露给桌面客户端。
```

---

## 2. DB1：本地配置库

DB1 是 DeepBase 的本地 config.db。

GuidedUse 中建议存放：

```text
1. 播放器窗口位置、置顶、透明度、语言。
2. 最近打开的 GuidePackage。
3. 本地工作目录。
4. API BaseUrl。
5. 当前登录状态的非敏感摘要。
6. 本地编辑器偏好。
7. 目标软件绑定偏好。
```

禁止存放：

```text
生产用户表
订单
支付流水
权益发放事实
支付密钥
公网 PG 明文密码
```

---

## 3. DB2：本地 SQLite 业务库

DB2 是 GuidedUse 第一阶段的本地业务库。

建议存放：

```text
1. 已下载或本地创建的 GuidePackage 索引。
2. GuidePackage JSON 快照。
3. FocusSketch 草稿。
4. SceneVisual / VisualAnchor 编辑缓存。
5. TraceEvent 本地记录。
6. LostRecovery 选择记录。
7. 待上传同步队列。
8. 本地 AI 草稿生成记录。
```

MVP-0 到 MVP-4 可只使用本地 JSON 文件；当播放器、编辑器和样板包稳定后，再把索引、草稿和 TraceEvent 纳入 DB2。

---

## 4. DB3：公网 PG 业务后端

DB3 是 GuidedUse 云端业务能力的 PG 后端。

桌面端访问方式：

```text
GuidedUse Desktop
  -> HTTPS API
  -> GuidedUse Backend
  -> DB3 PostgreSQL
```

DB3 可承载：

```text
1. 云端 GuidePackage 库。
2. 已发布善用包版本。
3. 模板市场。
4. 用户私有善用包同步。
5. FocusSketch 模板。
6. 卡点 TraceEvent 聚合统计。
7. AI 线框生成任务记录。
8. 受控问答知识包索引。
```

DB3 不负责认证支付事实；账号、订单、支付、权益统一归 DB4。

---

## 5. DB4：DeepBase 统一认证、支付与权益后端

DB4 不是 GuidedUse 自己实现的业务库，也不是 GuidedUse 自己维护的一套支付认证 API。DB4 由 DeepBase 框架提供统一能力，所有下游软件按同一套 Commerce/Auth 模块接入。

GuidedUse 桌面端接入方式：

```text
GuidedUse Desktop
  -> DeepBase.Commerce.SafeClient / UpgradeFlow / Permissions
  -> DeepBase Commerce/Auth HTTPS API
  -> DB4
```

DB4 负责：

```text
users
identities
orders
payments
entitlements
payment_notifications
```

GuidedUse 中对应能力：

```text
1. 登录态：通过 TDeepKitSafeClient。
2. 授权快照：通过 IssueLicenseSnapshot / RefreshLicenseSnapshot。
3. 订阅 / 买断升级：通过 DeepBase.Commerce.UpgradeFlow。
4. 模板市场付费：通过统一 product_id / entitlement_code。
5. AI 额度：通过 feature_code 和 ConsumeEntitlement。
6. 团队席位：通过 entitlement / tenant 上下文。
7. 付费功能门禁：通过 DeepBase.Commerce.Permissions。
```

支付流程必须走平台网站或后端可信域：

```text
客户端发起购买意图
  -> 后端生成 payment intent / checkout URL
  -> 用户跳转平台网站完成支付
  -> 后端接收支付通知并验签
  -> DB4 发放 entitlement
  -> 客户端查询 entitlement 并刷新本地 UI
```

客户端不得自行确认支付，也不得保存支付密钥。

下游软件只负责提供产品级参数：

```text
app_id：例如 guideduse_desktop。
product_id：例如 guideduse_pro_monthly / guideduse_template_pack。
entitlement_code：例如 pro_full / ai_calls / template_market。
feature_code：例如 ai_sketch / cloud_sync / paid_templates。
device_id：本机设备 ID。
current_version / channel：用于授权更新通道。
```

---

## 6. API 边界草案

DB3 业务 API 示例：

```text
GET    /api/guideduse/packages
POST   /api/guideduse/packages
GET    /api/guideduse/packages/{packageId}/versions
POST   /api/guideduse/sync
POST   /api/guideduse/trace-events
GET    /api/guideduse/templates
POST   /api/guideduse/ai/sketch-jobs
```

DB4 不在 GuidedUse 文档中重复定义接口契约。下游统一调用 DeepBase 框架封装：

```text
TDeepKitSafeClient
TDeepKitUpgradeFlowClient
TDeepKitPermissionClient
DeepBase.Desktop.Lifecycle
```

DeepBase 内部对应 `/dk/auth/*`、`/dk/commerce/*`、`/dk/license/*`、`/dk/updates/*` 等后端路由；GuidedUse 不直接拼接这些路由。

---

## 7. 安全规则

```text
1. 桌面端不直连公网 PG。
2. 桌面端不直连 DB4。
3. 桌面端不自建支付、订单、权益写入逻辑。
4. 桌面端只通过 DeepBase Commerce/Auth 框架保存和刷新 token，不保存支付密钥。
5. token 使用 DeepBase Security / DPAPI 或系统凭据管理保护。
6. DB3 业务 API 和 DeepBase DB4 API 必须使用 HTTPS。
7. 后端必须做租户隔离、权限校验、审计日志。
8. TraceEvent 上传前要区分匿名、登录用户和团队租户。
9. 支付回调必须幂等。
```

---

## 8. 对 MVP 的影响

```text
MVP-0：本地 GuidePackage JSON。
MVP-1：本地播放器。
MVP-2：桌面悬浮播放器。
MVP-3：FocusSketch 编辑器。
MVP-4：DeepLaunch 样板善用包。
MVP-5：AI 草稿和受控问答，可先本地或半云端试验。
P4 云端同步 / 模板市场：正式接 DB3。
商业化 / 登录 / 授权 / 付费：正式集成 DeepBase Commerce/Auth，不单独实现 DB4。
```

当前工程优先级不变：

```text
先完成本地 GuidePackage 和播放器闭环。
再沉淀 DB2 本地索引与 TraceEvent。
最后接 DB3 业务 API，并按 DeepBase 规范接入统一 DB4 能力。
```
