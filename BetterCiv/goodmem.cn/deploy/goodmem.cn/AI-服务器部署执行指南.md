# AI 服务器部署执行指�?
你要部署的是一个名�?`goodmem.cn` �?Python + FastAPI + 静态前端项目�?
当前前端包含两个独立入口�?
- `WSM / 思维越狱`：`/break`
- `WSH / 五行和悦论`：`/return`

## 目标

�?Ubuntu 服务器上完成以下工作�?
1. 解压部署�?2. 建立目录
3. 安装 Python / Nginx / PostgreSQL
4. 创建虚拟环境并安装依�?5. 配置环境变量
6. 配置 PostgreSQL
7. 配置 systemd
8. 配置 Nginx
9. 配置 HTTPS
10. 验证 H5 页面�?API

## 推荐目录

统一使用�?
```text
/srv/goodmem.cn
├─ app/current
├─ env
├─ logs
├─ data/proofs
└─ certs/wechatpay
```

## 解压要求

上传�?zip 解压后，代码应位于：

```text
/srv/goodmem.cn/app/current/goodmem.cn
```

其中应包含：

- `backend`
- `frontend`
- `deploy`

## 环境变量文件

请创建：

```text
/srv/goodmem.cn/env/backend.env
```

内容基于 `backend/.env.example`，至少填写：

- `DATABASE_URL`
- `JWT_SECRET`
- `HMAC_SECRET`

如果只是演示和支付申请，可暂不填写真实微信支付证书变量�?
## systemd

请将包内 `deploy/goodmem-api.service` 复制为：

```text
/etc/systemd/system/goodmem-api.service
```

并把其中路径改为�?
- WorkingDirectory=`/srv/goodmem.cn/app/current/goodmem.cn/backend`
- EnvironmentFile=`/srv/goodmem.cn/env/backend.env`

## Nginx

请将包内 `deploy/nginx.goodmem.cn.conf` 复制为：

```text
/etc/nginx/sites-available/goodmem.cn
```

然后软链到：

```text
/etc/nginx/sites-enabled/goodmem.cn
```

要求�?
- `/` 指向前端或反代到 FastAPI
- `/static/` 正常访问
- `/api/` 反代�?`127.0.0.1:8000`

## 验证命令

部署完成后，至少验证�?
```bash
curl -I http://127.0.0.1:8000/
curl -I http://127.0.0.1:8000/break
curl -I http://127.0.0.1:8000/return
curl -I http://127.0.0.1:8000/static/wsm-config.js
curl -I http://127.0.0.1:8000/static/wsh-config.js
curl -X POST http://127.0.0.1:8000/api/v1/pay/prepay \
  -H "Content-Type: application/json" \
  -d '{"product_tier":"system","novel_key":"mindbreak"}'
```

## 页面验证

浏览器中应能访问�?
- `/break`
- `/break?view=pay&sku=system`
- `/break?view=post&sku=system`
- `/return`
- `/return?view=pay&sku=annual`
- `/return?view=post&sku=monthly`

## 支付相关要求

### 当前允许

如果当前目标只是�?
- 微信 H5 支付申请
- 商品页审�?- 前端联调

那么可以暂时保留当前 mock `/api/v1/pay/prepay`�?
### 正式收款前必须完�?
你必须检查并推进以下事项�?
1. �?`backend/main.py` 中的 `/api/v1/pay/prepay` �?mock 改成真实微信支付 V3 H5 下单
2. 准备真实微信商户配置�?   - 商户�?   - 商户证书序列�?   - 商户私钥
   - APIv3 Key
   - 平台证书或平台公�?3. 保证正式域名已开�?HTTPS
4. 配置微信支付异步回调地址到：
   - `/api/v1/wechat/webhook`
5. 校验回调签名、解密资源、校验订单状�?6. 支付成功后，按订单发放正确的 `product_tier`
7. 增加支付失败、重复通知、退款、异常订单处�?
## 禁止误判

不要把当�?mock 下单接口当成正式支付已经完成�?
当前状态是�?
- H5 页面可演�?- mock 下单可演�?- 正式支付还需要接入微�?V3

## 输出要求

你完成部署后，应输出�?
1. 实际部署目录
2. systemd 服务状�?3. Nginx 配置状�?4. 页面访问结果
5. `/api/v1/pay/prepay` 返回结果
6. 是否仍为 mock 支付
7. 若未接真实支付，明确列出剩余事项
