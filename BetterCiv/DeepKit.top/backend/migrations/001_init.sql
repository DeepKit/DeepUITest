BEGIN;

CREATE TABLE IF NOT EXISTS users (
  user_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS identities (
  identity_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  provider TEXT NOT NULL,
  provider_user_id TEXT NOT NULL,
  app_id TEXT NOT NULL,
  union_id TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_user_id, app_id)
);

CREATE INDEX IF NOT EXISTS idx_identities_union_id ON identities(union_id);

CREATE TABLE IF NOT EXISTS products (
  app_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
  currency TEXT NOT NULL DEFAULT 'CNY',
  entitlement_code TEXT NOT NULL,
  entitlement_duration_days INTEGER NOT NULL DEFAULT 0,
  initial_quota INTEGER NOT NULL DEFAULT -1,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(app_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_products_entitlement_code ON products(entitlement_code);

CREATE TABLE IF NOT EXISTS orders (
  order_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  app_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  out_trade_no TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
  currency TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('created','paying','paid','closed','failed','refunded')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ NULL,
  FOREIGN KEY(app_id, product_id) REFERENCES products(app_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_orders_user_app ON orders(user_id, app_id);

CREATE TABLE IF NOT EXISTS payments (
  payment_id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL UNIQUE REFERENCES orders(order_id),
  provider TEXT NOT NULL CHECK (provider IN ('wechat_pay','alipay','stripe','paypal','manual','external')),
  channel TEXT NOT NULL CHECK (channel IN ('native','jsapi','mini_program','h5','app','web','manual')),
  provider_trade_no TEXT NOT NULL DEFAULT '',
  prepay_id TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('created','pending','paid','failed','refunded')),
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_provider_trade_no
  ON payments(provider, provider_trade_no)
  WHERE provider_trade_no <> '';

CREATE TABLE IF NOT EXISTS payment_notifications (
  notification_id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  notification_key TEXT NOT NULL UNIQUE,
  out_trade_no TEXT NOT NULL,
  provider_trade_no TEXT NOT NULL DEFAULT '',
  amount_minor BIGINT NOT NULL,
  currency TEXT NOT NULL,
  verified BOOLEAN NOT NULL DEFAULT FALSE,
  processed BOOLEAN NOT NULL DEFAULT FALSE,
  raw_payload JSONB NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ NULL
);

CREATE TABLE IF NOT EXISTS entitlements (
  entitlement_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  app_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  code TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active','consumed','expired','revoked')),
  valid_from TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NULL,
  remaining_quota INTEGER NOT NULL DEFAULT -1,
  source_order_id TEXT NOT NULL UNIQUE REFERENCES orders(order_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_entitlements_user_app_code
  ON entitlements(user_id, app_id, code, status);

CREATE TABLE IF NOT EXISTS entitlement_consumptions (
  consumption_id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  app_id TEXT NOT NULL,
  entitlement_id TEXT NOT NULL DEFAULT '',
  entitlement_code TEXT NOT NULL,
  feature_code TEXT NOT NULL DEFAULT '',
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  remaining_quota INTEGER NOT NULL DEFAULT -1,
  idempotency_key TEXT NOT NULL DEFAULT '',
  response_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  refresh_token_id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  app_id TEXT NOT NULL,
  device_id TEXT NOT NULL DEFAULT '',
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS license_snapshots (
  snapshot_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id),
  app_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  entitlement_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  payload_json JSONB NOT NULL,
  signature TEXT NOT NULL,
  key_id TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  revocation_version INTEGER NOT NULL DEFAULT 0,
  revoked_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS update_manifests (
  app_id TEXT NOT NULL,
  channel TEXT NOT NULL DEFAULT 'stable',
  latest_version TEXT NOT NULL,
  min_version TEXT NOT NULL DEFAULT '0.0.0',
  manifest_url TEXT NOT NULL DEFAULT '',
  package_url TEXT NOT NULL DEFAULT '',
  package_hash TEXT NOT NULL DEFAULT '',
  signature TEXT NOT NULL DEFAULT '',
  force_update BOOLEAN NOT NULL DEFAULT FALSE,
  release_notes TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(app_id, channel)
);

CREATE TABLE IF NOT EXISTS audit_logs (
  audit_id TEXT PRIMARY KEY,
  actor_user_id TEXT NOT NULL DEFAULT '',
  action TEXT NOT NULL,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  ip_address TEXT NOT NULL DEFAULT '',
  user_agent TEXT NOT NULL DEFAULT '',
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO products(app_id, product_id, name, amount_minor, currency, entitlement_code, entitlement_duration_days, initial_quota, is_active)
VALUES
  ('deepclip', 'deepclip_pro_month', 'DeepClip Pro Monthly', 1900, 'CNY', 'deepclip.pro', 31, -1, true),
  ('deeplaunch', 'deeplaunch_pro_year', 'DeepLaunch Pro Year', 9800, 'CNY', 'deeplaunch.pro', 365, -1, true),
  ('deeplaunch', 'deeplaunch_pro_lifetime', 'DeepLaunch Pro Lifetime', 19800, 'CNY', 'deeplaunch.pro', 0, -1, true),
  ('deepdev', 'deepdev_pro_month', 'DeepDev Pro Monthly', 20800, 'CNY', 'deepdev.pro', 31, -1, true),
  ('deepstory', 'deepstory_pro_month', 'DeepStory Pro Monthly', 52000, 'CNY', 'deepstory.pro', 31, -1, true),
  ('deepshine', 'deepshine_pro_month', 'DeepShine Pro Monthly', 166600, 'CNY', 'deepshine.pro', 31, -1, true),
  ('deepcompare', 'deepcompare_desktop_lifetime', 'DeepCompare Desktop Lifetime', 299900, 'CNY', 'deepcompare.pro', 0, -1, true),
  ('deepllm', 'deepllm_pro_10_ports_month', 'DeepLLM Pro 10 Ports Monthly', 50000, 'CNY', 'deepllm.pro', 31, 10, true)
ON CONFLICT(app_id, product_id) DO UPDATE
SET name=EXCLUDED.name,
    amount_minor=EXCLUDED.amount_minor,
    currency=EXCLUDED.currency,
    entitlement_code=EXCLUDED.entitlement_code,
    entitlement_duration_days=EXCLUDED.entitlement_duration_days,
    initial_quota=EXCLUDED.initial_quota,
    is_active=EXCLUDED.is_active,
    updated_at=now();

COMMIT;
