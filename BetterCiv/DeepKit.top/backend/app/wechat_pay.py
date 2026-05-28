from __future__ import annotations

import base64
import json
import secrets
import time
from typing import Any, Optional

import httpx
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class WeChatPayError(Exception):
    pass


def _load_public_key(path: str):
    if not path:
        raise WeChatPayError("WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH is required")
    with open(path, "rb") as f:
        return serialization.load_pem_public_key(f.read())


def _load_private_key(path: str):
    if not path:
        raise WeChatPayError("WECHAT_PAY_MERCHANT_PRIVATE_KEY_PATH is required")
    with open(path, "rb") as f:
        return serialization.load_pem_private_key(f.read(), password=None)


def _rsa_sha256_sign(private_key_path: str, message: str) -> str:
    private_key = _load_private_key(private_key_path)
    signature = private_key.sign(message.encode("utf-8"), padding.PKCS1v15(), hashes.SHA256())
    return base64.b64encode(signature).decode("ascii")


def _authorization_header(
    mch_id: str,
    serial_no: str,
    private_key_path: str,
    method: str,
    url_path: str,
    body: str,
) -> str:
    timestamp = str(int(time.time()))
    nonce = secrets.token_urlsafe(16)
    message = f"{method}\n{url_path}\n{timestamp}\n{nonce}\n{body}\n"
    signature = _rsa_sha256_sign(private_key_path, message)
    token = (
        f'mchid="{mch_id}",nonce_str="{nonce}",signature="{signature}",'
        f'timestamp="{timestamp}",serial_no="{serial_no}"'
    )
    return "WECHATPAY2-SHA256-RSA2048 " + token


def _client_params(app_id: str, prepay_id: str, private_key_path: str) -> dict[str, str]:
    timestamp = str(int(time.time()))
    nonce = secrets.token_urlsafe(16)
    package = "prepay_id=" + prepay_id
    message = f"{app_id}\n{timestamp}\n{nonce}\n{package}\n"
    return {
        "appId": app_id,
        "timeStamp": timestamp,
        "nonceStr": nonce,
        "package": package,
        "signType": "RSA",
        "paySign": _rsa_sha256_sign(private_key_path, message),
    }


def create_prepay(
    app_id: str,
    mch_id: str,
    merchant_serial: str,
    merchant_private_key_path: str,
    notify_url: str,
    description: str,
    out_trade_no: str,
    amount_minor: int,
    currency: str,
    channel: str,
    payer_open_id: str = "",
) -> dict[str, Any]:
    if not all([app_id, mch_id, merchant_serial, merchant_private_key_path, notify_url]):
        raise WeChatPayError("WeChat Pay prepay settings are incomplete")
    if channel in ("jsapi", "mini_program"):
        endpoint = "/v3/pay/transactions/jsapi"
    elif channel == "native":
        endpoint = "/v3/pay/transactions/native"
    elif channel == "h5":
        endpoint = "/v3/pay/transactions/h5"
    elif channel == "app":
        endpoint = "/v3/pay/transactions/app"
    else:
        raise WeChatPayError(f"Unsupported WeChat Pay channel: {channel}")

    body: dict[str, Any] = {
        "appid": app_id,
        "mchid": mch_id,
        "description": description[:127],
        "out_trade_no": out_trade_no,
        "notify_url": notify_url,
        "amount": {"total": amount_minor, "currency": currency},
    }
    if endpoint.endswith("/jsapi"):
        if not payer_open_id:
            raise WeChatPayError("payer_open_id is required for JSAPI/mini_program")
        body["payer"] = {"openid": payer_open_id}
    if endpoint.endswith("/h5"):
        body["scene_info"] = {"payer_client_ip": "127.0.0.1", "h5_info": {"type": "Wap"}}

    raw_body = json.dumps(body, ensure_ascii=False, separators=(",", ":"))
    headers = {
        "Authorization": _authorization_header(
            mch_id,
            merchant_serial,
            merchant_private_key_path,
            "POST",
            endpoint,
            raw_body,
        ),
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Wechatpay-Serial": merchant_serial,
    }
    response = httpx.post("https://api.mch.weixin.qq.com" + endpoint, content=raw_body, headers=headers, timeout=20)
    if response.status_code >= 400:
        raise WeChatPayError(f"WeChat Pay prepay failed: {response.status_code} {response.text}")
    data = response.json()
    prepay_id = data.get("prepay_id", "")
    result = {
        "prepay_id": prepay_id,
        "pay_url": data.get("h5_url", ""),
        "qr_code_data": data.get("code_url", ""),
        "client_params_json": "{}",
        "raw": data,
    }
    if prepay_id and channel in ("jsapi", "mini_program", "app"):
        result["client_params_json"] = json.dumps(
            _client_params(app_id, prepay_id, merchant_private_key_path),
            ensure_ascii=False,
            separators=(",", ":"),
        )
    return result


def verify_callback_signature(
    platform_public_key_path: str,
    timestamp: str,
    nonce: str,
    signature_b64: str,
    body: bytes,
) -> None:
    public_key = _load_public_key(platform_public_key_path)
    message = timestamp.encode("utf-8") + b"\n" + nonce.encode("utf-8") + b"\n" + body + b"\n"
    try:
        public_key.verify(
            base64.b64decode(signature_b64),
            message,
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except InvalidSignature as exc:
        raise WeChatPayError("WeChat Pay callback signature verification failed") from exc


def decrypt_resource(api_v3_key: str, resource: dict[str, Any]) -> dict[str, Any]:
    if len(api_v3_key.encode("utf-8")) != 32:
        raise WeChatPayError("WECHAT_PAY_API_V3_KEY must be 32 bytes")
    ciphertext = base64.b64decode(resource["ciphertext"])
    nonce = resource["nonce"].encode("utf-8")
    aad = resource.get("associated_data", "").encode("utf-8")
    plaintext = AESGCM(api_v3_key.encode("utf-8")).decrypt(nonce, ciphertext, aad)
    return json.loads(plaintext.decode("utf-8"))


def parse_paid_notification(api_v3_key: str, body: bytes, expected_mch_id: str = "") -> dict[str, Any]:
    outer = json.loads(body.decode("utf-8"))
    resource = outer.get("resource")
    if not isinstance(resource, dict):
        raise WeChatPayError("Missing encrypted resource")
    data = decrypt_resource(api_v3_key, resource)
    if expected_mch_id and data.get("mchid") != expected_mch_id:
        raise WeChatPayError("WeChat Pay mchid mismatch")
    if data.get("trade_state") != "SUCCESS":
        raise WeChatPayError("WeChat Pay trade_state is not SUCCESS")
    amount = data.get("amount") or {}
    return {
        "notification_key": outer.get("id") or data.get("transaction_id") or "",
        "out_trade_no": data["out_trade_no"],
        "provider_trade_no": data.get("transaction_id", ""),
        "amount_minor": int(amount["total"]),
        "currency": amount.get("currency", "CNY"),
        "raw": outer,
    }
