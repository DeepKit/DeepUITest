from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field


class AuthLoginRequest(BaseModel):
    login_type: str
    app_id: str
    device_id: Optional[str] = None
    device_fingerprint: Optional[str] = None
    email: Optional[str] = None
    password: Optional[str] = None
    code: Optional[str] = None
    provider_user_id: Optional[str] = None
    union_id: Optional[str] = None


class AuthRefreshRequest(BaseModel):
    refresh_token: str


class AuthLogoutRequest(BaseModel):
    refresh_token: str


class EnsureUserRequest(BaseModel):
    provider: str
    provider_user_id: str
    app_id: str
    union_id: str = ""
    display_name: str = ""
    email: str = ""
    phone: str = ""


class CreateOrderRequest(BaseModel):
    user_id: str
    app_id: str
    product_id: str


class CreatePaymentIntentRequest(BaseModel):
    order_id: str
    provider: str
    channel: str
    payer_open_id: str = ""


class ConsumeEntitlementRequest(BaseModel):
    app_id: str
    entitlement_code: str
    feature_code: str = ""
    quantity: int = Field(default=1, gt=0)
    request_id: str = ""


class LicenseSnapshotRequest(BaseModel):
    app_id: str
    device_id: str
    snapshot_id: str = ""


class ManualPaymentConfirmRequest(BaseModel):
    out_trade_no: str
    provider_trade_no: str
    amount_minor: int
    currency: str = "CNY"


JsonDict = dict[str, Any]

