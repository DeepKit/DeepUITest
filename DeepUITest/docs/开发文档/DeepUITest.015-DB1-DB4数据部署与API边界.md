# DeepUITest.015 - DB1-DB4 数据部署与 API 边界

> 状态：开发文档初版
> 用途：把 DeepBase 的 DB1 + DB2 + DB3 + DB4 规范落到 DeepUITest，明确本地库、公网业务 API、统一认证支付框架的边界

---

## 1. 冻结判断

```text
DeepUITest 第一阶段只依赖本地 DB1 + DB2。
DB3 是公网业务后端的 PG 数据库，但桌面端不直连 DB3，只访问后端 API。
DB4 是 DeepBase 框架统一提供的认证、支付与权益后端能力，DeepUITest 只集成 DeepBase Commerce/Auth 模块。
```

这里的“DB3 和 DB4 放在公网”应理解为：

```text
公网开放的是 HTTPS API 服务。
PG / 支付认证数据库本体不裸露给桌面客户端。
```

---

## 2. DB1：本地配置库

DB1 是 DeepBase 的本地 config.db。

DeepUITest 中建议存放：

```text
1. Designer / Runner 本地设置。
2. 最近打开的 AppProject。
3. DeepLaunch / 被测程序路径。
4. Runner 工作目录。
5. API BaseUrl。
6. 当前登录状态的非敏感摘要。
7. 本地 UI 偏好。
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

DB2 是 DeepUITest 第一阶段的主业务库。

第一版 16 张核心表默认进入 DB2：

```text
AppProject
AppVersion
SourceFileIndex
WindowDef
ControlDef
TestCase
JourneyStep
AssertRule
LampEvaluation
RunnerBatch
RunnerResult
RunnerStepResult
BugRecord
BugDiagnosis
BugObjectLink
HumanDecisionLog
```

DB2 负责：

```text
1. 本地测试项目。
2. 本地测试链配置。
3. Runner 执行结果。
4. 本地 BugRecord / BugDiagnosis。
5. DeepLaunch 样板测试链。
6. 离线工作缓存。
7. 待上传的结果队列。
```

---

## 4. DB3：公网 PG 业务后端

DB3 是 DeepUITest 后续共享能力的业务后端，物理形态以 PostgreSQL 为主。

桌面端访问方式：

```text
DeepUITest Desktop
  -> HTTPS API
  -> DeepUITest Backend
  -> DB3 PostgreSQL
```

DB3 可承载：

```text
1. 团队共享 AppProject。
2. 共享 TestCase / JourneyStep 模板。
3. 测试运行结果同步。
4. BugPattern 公共库。
5. 样板测试链市场。
6. 跨设备测试历史。
7. AI 配置生成任务记录。
```

第一阶段暂不依赖 DB3。只有当出现团队协作、跨设备同步、公共 BugPattern、云端样板库时，才进入 DB3 API 阶段。

---

## 5. DB4：DeepBase 统一认证、支付与权益后端

DB4 不是 DeepUITest 自己实现的业务库，也不是 DeepUITest 自己维护的一套支付认证 API。DB4 由 DeepBase 框架提供统一能力，所有下游软件按同一套 Commerce/Auth 模块接入。

DeepUITest 桌面端接入方式：

```text
DeepUITest Desktop
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

DeepUITest 中对应能力：

```text
1. 登录态：通过 TDeepKitSafeClient。
2. 授权快照：通过 IssueLicenseSnapshot / RefreshLicenseSnapshot。
3. 订阅 / 买断升级：通过 DeepBase.Commerce.UpgradeFlow。
4. 付费功能门禁：通过 DeepBase.Commerce.Permissions。
5. 团队席位、云端功能开关：通过 entitlement / feature_code。
6. 权益查询和额度扣减：通过 ListEntitlements / ConsumeEntitlement。
```

支付确认只能由后端完成：

```text
支付平台通知
  -> 后端验签 / 查单 / 校验订单金额币种
  -> DB4 写入支付事实
  -> 发放 entitlement
  -> 客户端查询 entitlement
```

客户端不得自行确认支付，也不得保存支付密钥。

下游软件只负责提供产品级参数：

```text
app_id：例如 deepuitest_desktop。
product_id：例如 deepuitest_pro_monthly。
entitlement_code：例如 pro_full / team_full。
feature_code：例如 cloud_bug_patterns / team_sync。
device_id：本机设备 ID。
current_version / channel：用于授权更新通道。
```

---

## 6. API 边界草案

DB3 业务 API 示例：

```text
GET    /api/deepuitest/projects
POST   /api/deepuitest/projects
GET    /api/deepuitest/testcases
POST   /api/deepuitest/runs
POST   /api/deepuitest/bug-records
GET    /api/deepuitest/bug-patterns
```

DB4 不在 DeepUITest 文档中重复定义接口契约。下游统一调用 DeepBase 框架封装：

```text
TDeepKitSafeClient
TDeepKitUpgradeFlowClient
TDeepKitPermissionClient
DeepBase.Desktop.Lifecycle
```

DeepBase 内部对应 `/dk/auth/*`、`/dk/commerce/*`、`/dk/license/*`、`/dk/updates/*` 等后端路由；DeepUITest 不直接拼接这些路由。

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
8. 上传 RunnerResult / BugRecord 时必须带产品、版本、用户和租户上下文。
9. 支付回调必须幂等。
```

---

## 8. 对 MVP 的影响

```text
MVP-1：只做 DB1 + DB2，本地跑通 DeepLaunch 测试链。
MVP-2~MVP-4：仍以本地 DB2 为主，最多预留 API 配置项。
MVP-5 后：如果做共享 BugPattern、团队协作或样板库，再接 DB3 业务 API。
商业化阶段：只要出现登录、付费、授权，就集成 DeepBase Commerce/Auth，不单独实现 DB4。
```

当前工程优先级不变：

```text
先跑通本地 Runner 闭环。
再抽象 DB2 Schema。
最后再接 DB3 业务 API，并按 DeepBase 规范接入统一 DB4 能力。
```
