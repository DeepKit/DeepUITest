from __future__ import annotations

import os
from dataclasses import dataclass


def _int_env(name: str, default: int) -> int:
    value = os.getenv(name)
    if not value:
        return default
    return int(value)


def _env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default


@dataclass(frozen=True)
class Settings:
    env: str = _env_first("DEEPKIT_ENV", "APP_ENV", default="dev")
    public_base_url: str = _env_first("PUBLIC_BASE_URL", "DEEPKIT_PUBLIC_BASE_URL", default="http://127.0.0.1:8010")
    database_url: str = _env_first("DATABASE_URL", "DEEPKIT_DATABASE_URL")
    jwt_secret: str = _env_first("JWT_SECRET", "DEEPKIT_JWT_SECRET", default="dev-only-change-before-production-32-bytes")
    access_token_ttl_seconds: int = _int_env("ACCESS_TOKEN_TTL_SECONDS", 7200)
    refresh_token_ttl_days: int = _int_env("REFRESH_TOKEN_TTL_DAYS", 30)
    license_private_key_b64: str = _env_first("LICENSE_ED25519_PRIVATE_KEY_B64", "LICENSE_PRIVATE_KEY_B64")
    license_private_key_path: str = _env_first("LICENSE_PRIVATE_KEY_PATH", "LICENSE_ED25519_PRIVATE_KEY_PATH")
    license_key_id: str = _env_first("LICENSE_KEY_ID", "LICENSE_PUBLIC_KEY_ID", default="dev-ephemeral")

    wechat_app_id: str = _env_first("WECHAT_APP_ID", "WECHAT_PAY_APPID")
    wechat_app_secret: str = os.getenv("WECHAT_APP_SECRET", "")
    wechat_pay_mch_id: str = _env_first("WECHAT_PAY_MCH_ID", "WECHAT_PAY_MCHID")
    wechat_pay_api_v3_key: str = os.getenv("WECHAT_PAY_API_V3_KEY", "")
    wechat_pay_merchant_serial: str = _env_first("WECHAT_PAY_MERCHANT_SERIAL", "WECHAT_PAY_SERIAL_NO")
    wechat_pay_merchant_private_key_path: str = _env_first("WECHAT_PAY_MERCHANT_PRIVATE_KEY_PATH", "WECHAT_PAY_PRIVATE_KEY_PATH")
    wechat_pay_platform_public_key_path: str = _env_first("WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH", "WECHAT_PAY_PLATFORM_CERT_PATH")
    wechat_pay_notify_url: str = _env_first("WECHAT_PAY_NOTIFY_URL", "WECHAT_PAY_NOTIFY_BASE_URL")

    @property
    def is_production(self) -> bool:
        return self.env.lower() == "production"

    def validate_startup(self) -> None:
        if len(self.jwt_secret) < 32:
            raise RuntimeError("JWT_SECRET must be at least 32 characters")
        if self.is_production:
            missing = []
            if not self.database_url:
                missing.append("DEEPKIT_DATABASE_URL")
            if not self.license_private_key_b64 and not self.license_private_key_path:
                missing.append("LICENSE_PRIVATE_KEY_PATH")
            if missing:
                raise RuntimeError("Missing production settings: " + ", ".join(missing))


settings = Settings()
