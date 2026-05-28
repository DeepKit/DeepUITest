# DeepKit DB4 Acceptance Curl

Set variables:

```bash
BASE="https://deepkit.top"
APP_ID="deeplaunch"
DEVICE_ID="accept-device-001"
```

Login:

```bash
curl -s "$BASE/dk/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"login_type":"device_anonymous","app_id":"deeplaunch","device_id":"accept-device-001"}'
```

Products:

```bash
curl -s "$BASE/dk/commerce/products?app_id=deeplaunch"
```

Create order:

```bash
curl -s "$BASE/dk/commerce/orders" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"'$USER_ID'","app_id":"deeplaunch","product_id":"deeplaunch_pro_year"}'
```

Create payment intent:

```bash
curl -s "$BASE/dk/commerce/payments/intents" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: accept-intent-001" \
  -d '{"order_id":"'$ORDER_ID'","provider":"wechat_pay","channel":"native"}'
```

Entitlements:

```bash
curl -s "$BASE/dk/commerce/entitlements?app_id=deeplaunch" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Consume quota:

```bash
curl -s "$BASE/dk/commerce/entitlements/consume" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: accept-consume-001" \
  -d '{"app_id":"deeplaunch","entitlement_code":"deeplaunch.pro","feature_code":"pro","quantity":1}'
```

License snapshot:

```bash
curl -s "$BASE/dk/license/snapshot/issue" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"app_id":"deeplaunch","device_id":"accept-device-001"}'
```

Export OpenAPI:

```bash
curl -s "$BASE/openapi.json" > deepkit-openapi.json
```

