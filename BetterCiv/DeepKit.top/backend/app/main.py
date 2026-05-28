from __future__ import annotations

import hashlib
from datetime import timedelta
from typing import Annotated, Any

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import settings
from .models import (
    AuthLoginRequest,
    AuthLogoutRequest,
    AuthRefreshRequest,
    ConsumeEntitlementRequest,
    CreateOrderRequest,
    CreatePaymentIntentRequest,
    EnsureUserRequest,
    LicenseSnapshotRequest,
    ManualPaymentConfirmRequest,
)
from .security import LicenseSigner, canonical_json, create_access_token, new_refresh_token, verify_access_token, new_id
from .store import Conflict, MemoryStore, NotFound, iso, now_utc
from .wechat_pay import WeChatPayError, create_prepay, parse_paid_notification, verify_callback_signature


settings.validate_startup()
app = FastAPI(title="DeepKit DB4 API", version="0.1.0")
bearer = HTTPBearer(auto_error=False)
if settings.database_url:
    from .store_pg import PostgresStore

    store = PostgresStore(settings.database_url)
else:
    store = MemoryStore()
license_signer = LicenseSigner.from_base64_or_path_or_dev(
    settings.license_key_id,
    settings.license_private_key_b64,
    settings.license_private_key_path,
    settings.is_production,
)


def require_auth(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> dict[str, Any]:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    try:
        return verify_access_token(settings.jwt_secret, credentials.credentials)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc


def map_store_error(exc: Exception) -> HTTPException:
    if isinstance(exc, NotFound):
        return HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, Conflict):
        return HTTPException(status_code=409, detail=str(exc))
    return HTTPException(status_code=400, detail=str(exc))


def create_session(user_id: str, app_id: str, device_id: str = "") -> dict[str, Any]:
    refresh = new_refresh_token()
    expires_at = now_utc() + timedelta(days=settings.refresh_token_ttl_days)
    store.save_refresh_token(refresh, user_id, app_id, device_id, expires_at)
    return {
        "user_id": user_id,
        "access_token": create_access_token(settings.jwt_secret, user_id, app_id, settings.access_token_ttl_seconds),
        "refresh_token": refresh,
        "expires_in": settings.access_token_ttl_seconds,
    }


def wechat_code2session(code: str) -> dict[str, Any]:
    if not settings.wechat_app_id or not settings.wechat_app_secret:
        raise HTTPException(status_code=503, detail="WeChat login settings are missing")
    response = httpx.get(
        "https://api.weixin.qq.com/sns/jscode2session",
        params={
            "appid": settings.wechat_app_id,
            "secret": settings.wechat_app_secret,
            "js_code": code,
            "grant_type": "authorization_code",
        },
        timeout=15,
    )
    data = response.json()
    if response.status_code >= 400 or data.get("errcode"):
        raise HTTPException(status_code=400, detail={"wechat_error": data})
    if not data.get("openid"):
        raise HTTPException(status_code=400, detail="WeChat code2session did not return openid")
    return data


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "service": "deepkit-db4", "env": settings.env}


@app.post("/dk/auth/login")
def auth_login(req: AuthLoginRequest) -> dict[str, Any]:
    if req.login_type == "device_anonymous":
        if not req.device_id:
            raise HTTPException(status_code=422, detail="device_id is required")
        user = store.ensure_user("device", req.device_id, req.app_id)
        return create_session(user["user_id"], req.app_id, req.device_id)
    if req.login_type == "wechat":
        if req.code:
            wx = wechat_code2session(req.code)
            provider_user_id = wx["openid"]
            union_id = wx.get("unionid", "")
        elif req.provider_user_id and not settings.is_production:
            provider_user_id = req.provider_user_id
            union_id = req.union_id or ""
        else:
            raise HTTPException(status_code=422, detail="wechat login requires code")
        user = store.ensure_user("wechat_mini_program", provider_user_id, req.app_id, union_id)
        return create_session(user["user_id"], req.app_id, req.device_id or "")
    raise HTTPException(status_code=422, detail=f"Unsupported login_type: {req.login_type}")


@app.post("/dk/auth/refresh")
def auth_refresh(req: AuthRefreshRequest) -> dict[str, Any]:
    try:
        row = store.use_refresh_token(req.refresh_token)
        store.revoke_refresh_token(req.refresh_token)
        return create_session(row["user_id"], row["app_id"], row.get("device_id", ""))
    except Exception as exc:
        raise map_store_error(exc)


@app.post("/dk/auth/logout")
def auth_logout(req: AuthLogoutRequest, _: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    store.revoke_refresh_token(req.refresh_token)
    return {"success": True}


@app.get("/dk/auth/me")
def auth_me(token: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    try:
        user = store.get_user(token["sub"])
    except Exception as exc:
        raise map_store_error(exc)
    return user


@app.post("/dk/commerce/users/ensure")
def ensure_user(req: EnsureUserRequest, _: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    try:
        return store.ensure_user(
            req.provider,
            req.provider_user_id,
            req.app_id,
            req.union_id,
            req.display_name,
            req.email,
            req.phone,
        )
    except Exception as exc:
        raise map_store_error(exc)


@app.get("/dk/commerce/products")
def list_products(app_id: str) -> dict[str, Any]:
    return {"products": store.list_products(app_id)}


@app.post("/dk/commerce/orders")
def create_order(req: CreateOrderRequest, token: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    if token["sub"] != req.user_id:
        raise HTTPException(status_code=403, detail="Cannot create order for another user")
    try:
        return store.create_order(req.user_id, req.app_id, req.product_id)
    except Exception as exc:
        raise map_store_error(exc)


@app.post("/dk/commerce/payments/intents")
def create_payment_intent(
    req: CreatePaymentIntentRequest,
    _: Annotated[dict[str, Any], Depends(require_auth)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, Any]:
    try:
        order = store.get_order(req.order_id)
        payment = store.create_payment(req.order_id, req.provider, req.channel)
    except Exception as exc:
        raise map_store_error(exc)
    prepay_id = payment.get("prepay_id", "")
    pay_url = ""
    qr_code_data = ""
    client_params_json = "{}"
    if req.provider == "wechat_pay":
        if settings.is_production or settings.wechat_pay_mch_id:
            notify_url = settings.wechat_pay_notify_url or (
                settings.public_base_url.rstrip("/") + "/dk/commerce/payments/wechat_pay/notify"
            )
            try:
                prepay = create_prepay(
                    settings.wechat_app_id,
                    settings.wechat_pay_mch_id,
                    settings.wechat_pay_merchant_serial,
                    settings.wechat_pay_merchant_private_key_path,
                    notify_url,
                    order["title"],
                    order["out_trade_no"],
                    int(order["amount_minor"]),
                    order["currency"],
                    req.channel,
                    req.payer_open_id,
                )
            except WeChatPayError as exc:
                raise HTTPException(status_code=503, detail=str(exc)) from exc
            prepay_id = prepay["prepay_id"]
            pay_url = prepay["pay_url"]
            qr_code_data = prepay["qr_code_data"]
            client_params_json = prepay["client_params_json"]
            if hasattr(store, "update_payment_intent"):
                store.update_payment_intent(payment["payment_id"], prepay_id, canonical_json(prepay["raw"]))
    return {
        "success": True,
        "payment_id": payment["payment_id"],
        "out_trade_no": order["out_trade_no"],
        "prepay_id": prepay_id,
        "client_params_json": client_params_json,
        "pay_url": pay_url,
        "qr_code_data": qr_code_data,
        "error_code": "",
        "error_message": "",
    }


@app.post("/dk/commerce/payments/manual/confirm")
def manual_confirm(req: ManualPaymentConfirmRequest, _: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    if settings.is_production:
        raise HTTPException(status_code=403, detail="Manual payment confirm is disabled in production")
    try:
        return store.confirm_payment(
            "manual",
            req.out_trade_no,
            req.provider_trade_no,
            req.amount_minor,
            req.currency,
            canonical_json(req.model_dump()),
            "manual:" + req.provider_trade_no,
        )
    except Exception as exc:
        raise map_store_error(exc)


@app.post("/dk/commerce/payments/wechat_pay/notify")
async def wechat_pay_notify(
    request: Request,
    wechatpay_timestamp: Annotated[str | None, Header(alias="Wechatpay-Timestamp")] = None,
    wechatpay_nonce: Annotated[str | None, Header(alias="Wechatpay-Nonce")] = None,
    wechatpay_signature: Annotated[str | None, Header(alias="Wechatpay-Signature")] = None,
) -> dict[str, Any]:
    body = await request.body()
    try:
        if not (wechatpay_timestamp and wechatpay_nonce and wechatpay_signature):
            raise WeChatPayError("Missing WeChat Pay signature headers")
        verify_callback_signature(
            settings.wechat_pay_platform_public_key_path,
            wechatpay_timestamp,
            wechatpay_nonce,
            wechatpay_signature,
            body,
        )
        parsed = parse_paid_notification(settings.wechat_pay_api_v3_key, body, settings.wechat_pay_mch_id)
        notification_key = parsed["notification_key"] or hashlib.sha256(body).hexdigest()
        store.confirm_payment(
            "wechat_pay",
            parsed["out_trade_no"],
            parsed["provider_trade_no"],
            parsed["amount_minor"],
            parsed["currency"],
            body.decode("utf-8"),
            "wechat_pay:" + notification_key,
        )
        return {"code": "SUCCESS", "message": "成功"}
    except WeChatPayError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise map_store_error(exc)


@app.get("/dk/commerce/entitlements")
def list_entitlements(app_id: str, token: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    return {"items": store.list_entitlements(token["sub"], app_id)}


@app.post("/dk/commerce/entitlements/consume")
def consume_entitlement(
    req: ConsumeEntitlementRequest,
    token: Annotated[dict[str, Any], Depends(require_auth)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, Any]:
    request_id = req.request_id or idempotency_key or ""
    try:
        return store.consume_entitlement(
            token["sub"],
            req.app_id,
            req.entitlement_code,
            req.feature_code,
            req.quantity,
            request_id,
        )
    except Exception as exc:
        raise map_store_error(exc)


def make_license_snapshot(user_id: str, app_id: str, device_id: str) -> dict[str, Any]:
    entitlements = store.list_entitlements(user_id, app_id)
    issued_at = now_utc()
    expires_at = issued_at + timedelta(days=7)
    payload = {
        "schema_version": 1,
        "user_id": user_id,
        "app_id": app_id,
        "device_id": device_id,
        "issued_at": iso(issued_at),
        "expires_at": iso(expires_at),
        "entitlements": entitlements,
    }
    snapshot = {
        "snapshot_id": new_id("lic"),
        "issued_at": payload["issued_at"],
        "expires_at": payload["expires_at"],
        "payload": payload,
        "signature": license_signer.sign_payload(payload),
        "key_id": license_signer.key_id,
        "schema_version": 1,
        "revocation_version": 0,
    }
    store.save_license_snapshot(snapshot)
    return snapshot


@app.post("/dk/license/snapshot/issue")
def issue_license_snapshot(req: LicenseSnapshotRequest, token: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    return make_license_snapshot(token["sub"], req.app_id, req.device_id)


@app.post("/dk/license/snapshot/refresh")
def refresh_license_snapshot(req: LicenseSnapshotRequest, token: Annotated[dict[str, Any], Depends(require_auth)]) -> dict[str, Any]:
    return make_license_snapshot(token["sub"], req.app_id, req.device_id)


@app.get("/dk/updates/manifest")
def updates_manifest(app_id: str, current_version: str, channel: str = "stable") -> dict[str, Any]:
    return store.update_manifest(app_id, current_version, channel)
