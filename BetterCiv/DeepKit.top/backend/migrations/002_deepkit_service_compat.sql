BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE refresh_tokens
  ADD COLUMN IF NOT EXISTS app_id TEXT NOT NULL DEFAULT '';

ALTER TABLE license_snapshots
  ADD COLUMN IF NOT EXISTS entitlement_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS payload_json JSONB,
  ADD COLUMN IF NOT EXISTS key_id TEXT NOT NULL DEFAULT 'v1',
  ADD COLUMN IF NOT EXISTS schema_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS revocation_version INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='license_snapshots'
      AND column_name='payload'
  ) THEN
    EXECUTE 'UPDATE license_snapshots SET payload_json = payload WHERE payload_json IS NULL';
  END IF;
END $$;

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

INSERT INTO update_manifests(
  app_id, channel, latest_version, min_version, manifest_url, package_url,
  package_hash, signature, force_update, release_notes, updated_at
)
SELECT
  app_id,
  channel_name,
  current_version,
  '0.0.0',
  manifest_url,
  COALESCE(package_url, ''),
  COALESCE(package_hash, ''),
  COALESCE(signature, ''),
  COALESCE(force_update, false),
  COALESCE(release_notes, ''),
  COALESCE(updated_at, now())
FROM update_channels
ON CONFLICT(app_id, channel) DO NOTHING;

ALTER TABLE entitlement_consumptions
  ADD COLUMN IF NOT EXISTS entitlement_id TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS entitlement_code TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS remaining_quota INTEGER NOT NULL DEFAULT -1,
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS response_json JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS idx_entitlement_consumptions_request_id
  ON entitlement_consumptions(request_id);

INSERT INTO products(app_id, product_id, name, description, amount_minor, currency, entitlement_code, entitlement_duration_days, initial_quota, is_active, product_type)
VALUES
  ('deepclip', 'deepclip_pro_month', 'DeepClip Pro Monthly', 'DeepClip Pro monthly plan', 1900, 'CNY', 'deepclip.pro', 31, -1, true, 'subscription'),
  ('deeplaunch', 'deeplaunch_pro_year', 'DeepLaunch Pro Year', 'DeepLaunch Pro yearly plan', 9800, 'CNY', 'deeplaunch.pro', 365, -1, true, 'subscription'),
  ('deeplaunch', 'deeplaunch_pro_lifetime', 'DeepLaunch Pro Lifetime', 'DeepLaunch Pro lifetime license', 19800, 'CNY', 'deeplaunch.pro', 0, -1, true, 'perpetual'),
  ('deepdev', 'deepdev_pro_month', 'DeepDev Pro Monthly', 'DeepDev Pro monthly plan', 20800, 'CNY', 'deepdev.pro', 31, -1, true, 'subscription'),
  ('deepstory', 'deepstory_pro_month', 'DeepStory Pro Monthly', 'DeepStory Pro monthly plan', 52000, 'CNY', 'deepstory.pro', 31, -1, true, 'subscription'),
  ('deepshine', 'deepshine_pro_month', 'DeepShine Pro Monthly', 'DeepShine Pro monthly plan', 166600, 'CNY', 'deepshine.pro', 31, -1, true, 'subscription'),
  ('deepcompare', 'deepcompare_desktop_lifetime', 'DeepCompare Desktop Lifetime', 'DeepCompare desktop lifetime license', 299900, 'CNY', 'deepcompare.pro', 0, -1, true, 'perpetual'),
  ('deepllm', 'deepllm_pro_10_ports_month', 'DeepLLM Pro 10 Ports Monthly', 'DeepLLM Pro 10 ports monthly plan', 50000, 'CNY', 'deepllm.pro', 31, 10, true, 'quota')
ON CONFLICT(app_id, product_id) DO UPDATE
SET name=EXCLUDED.name,
    description=EXCLUDED.description,
    amount_minor=EXCLUDED.amount_minor,
    currency=EXCLUDED.currency,
    entitlement_code=EXCLUDED.entitlement_code,
    entitlement_duration_days=EXCLUDED.entitlement_duration_days,
    initial_quota=EXCLUDED.initial_quota,
    is_active=EXCLUDED.is_active,
    product_type=EXCLUDED.product_type,
    updated_at=now();

COMMIT;
