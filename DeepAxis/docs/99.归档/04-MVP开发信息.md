# MVP 开发信息

## MVP 目标

用最小成本验证：

1. 用户是否愿意为私域销售副驾付 9.9 元/月或 99 元/年。
2. 用户是否愿意用个人微信主动传播裂变素材。
3. 推广员是否愿意为了 50% 直推佣金持续推广。
4. 服务商是否能通过培训和社群服务提升付费与活跃。
5. AI 生成内容是否能降低用户日常私域销售摩擦。

## 首版页面

### 1. 首页

- 今日作战卡。
- 生成朋友圈。
- 生成私聊话术。
- 客户说太贵。
- 生成裂变海报。
- 我的收益。

### 2. 今日作战卡

- 今日朋友圈任务。
- 今日私聊任务。
- 今日跟进任务。
- 今日裂变任务。
- 完成打卡。

### 3. 文案生成

输入：

- 行业。
- 产品。
- 目标客户。
- 语气。
- 目的：信任、成交、裂变、复购、转介绍。

输出：

- 朋友圈文案。
- 私聊话术。
- 群发但需人工发送的群内容。
- 海报标题。

### 4. 客户轻管理

字段：

```text
客户昵称
来源
状态
需求
上次沟通
下次跟进时间
备注
```

### 5. 裂变中心

- 我的邀请码。
- 我的海报。
- 我的邀请人数。
- 我的付费订单。
- 我的收益。
- 提现申请。

### 6. 服务商中心

- 服务商身份。
- 伞下统计。
- 有效付费用户。
- 活跃率。
- 续费率。
- 投诉率。
- 月度奖励资格。

## 首版后端能力

```text
用户登录
会员订单
邀请码绑定
直推关系
收益流水
提现申请
AI 文案生成
AI 话术生成
客户轻记录
服务商统计
区域奖励统计
```

## 数据模型草案

```text
users
  id
  nickname
  phone
  invite_code
  invited_by
  role
  created_at

memberships
  user_id
  plan
  starts_at
  expires_at

orders
  id
  user_id
  product_id
  amount
  status
  paid_at
  referrer_id
  service_provider_id

reward_ledger
  id
  order_id
  receiver_id
  reward_type
  amount
  status
  created_at

service_provider_metrics
  provider_id
  period
  valid_paid_users
  active_rate
  renewal_rate
  refund_rate
  complaint_rate
  training_count
  qualified_bonus_rate
```

## 开发顺序

1. 登录、会员、订单、邀请码。
2. AI 文案和话术生成。
3. 今日作战卡。
4. 裂变海报和收益中心。
5. 客户轻管理。
6. 服务商统计。
7. 月度奖励池后台。

## 验证指标

首月关注：

```text
注册转付费率
付费转分享率
分享转注册率
注册转年卡率
推广员平均直推订单数
每日作战卡打开率
文案复制率
7日留存
退款率
投诉率
```

## 不做事项

- 不接个人微信协议。
- 不做自动私聊。
- 不做群控。
- 不做复杂 CRM。
- 不做企业微信集成。
- 不做多级自动分佣。
- 不做省市县自动逐单结算。

