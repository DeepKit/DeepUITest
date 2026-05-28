# DeepKit.top DB4 Backend

DeepKit.top is the unified DB4 service for DeepBase downstream tools. It owns:

- authentication and refresh tokens
- product catalog, orders, payments, and payment notifications
- entitlement grants and quota consumption
- signed desktop license snapshots
- update-channel metadata

The public API is mounted under `/dk` and follows the DeepBase Commerce contract.

## Local Smoke Run

```powershell
cd D:\_Progs\02Business\BetterCiv\DeepKit.top\backend
python -m pip install -r requirements.txt
$env:DEEPKIT_ENV = 'dev'
uvicorn app.main:app --reload --port 8010
```

Without `DATABASE_URL`, the service uses an in-memory store for contract smoke tests only.
Production must use PostgreSQL and the migration in `migrations/001_init.sql`.

## Production Required Environment

```text
DEEPKIT_ENV=production
DATABASE_URL=postgresql://deepkit_app:***@host:5432/deepKit
JWT_SECRET=at-least-32-random-bytes
LICENSE_ED25519_PRIVATE_KEY_B64=<base64 raw 32-byte Ed25519 private key>
LICENSE_KEY_ID=dk4-2026-01
PUBLIC_BASE_URL=https://deepkit.top

WECHAT_APP_ID=...
WECHAT_APP_SECRET=...
WECHAT_PAY_MCH_ID=...
WECHAT_PAY_API_V3_KEY=32-byte-secret
WECHAT_PAY_MERCHANT_SERIAL=...
WECHAT_PAY_MERCHANT_PRIVATE_KEY_PATH=...
WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH=...
WECHAT_PAY_NOTIFY_URL=https://deepkit.top/dk/commerce/payments/wechat_pay/notify
```

## Commercial Gate

This backend is not considered commercial-ready until:

1. PostgreSQL migration is applied to the real DB4 database.
2. Production secrets are set outside source control.
3. WeChat login `code2session` is verified with the real mini-program app.
4. WeChat Pay prepay and callback are verified end to end.
5. DeepBase client contract smoke script passes against the public URL.
6. OpenAPI JSON is exported from `/openapi.json` and archived with release docs.
