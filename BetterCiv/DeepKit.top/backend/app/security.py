from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode((data + padding).encode("ascii"))


def canonical_json(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_urlsafe(18)}"


def new_refresh_token() -> str:
    return "rt_" + secrets.token_urlsafe(48)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_access_token(secret: str, user_id: str, app_id: str, ttl_seconds: int) -> str:
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "sub": user_id,
        "app_id": app_id,
        "iat": now,
        "exp": now + ttl_seconds,
        "type": "access",
    }
    signing_input = (
        b64url_encode(canonical_json(header).encode("utf-8"))
        + "."
        + b64url_encode(canonical_json(payload).encode("utf-8"))
    )
    signature = hmac.new(secret.encode("utf-8"), signing_input.encode("ascii"), hashlib.sha256).digest()
    return signing_input + "." + b64url_encode(signature)


def verify_access_token(secret: str, token: str) -> dict[str, Any]:
    try:
        header_b64, payload_b64, signature_b64 = token.split(".")
    except ValueError as exc:
        raise ValueError("Malformed bearer token") from exc
    signing_input = header_b64 + "." + payload_b64
    expected = hmac.new(secret.encode("utf-8"), signing_input.encode("ascii"), hashlib.sha256).digest()
    actual = b64url_decode(signature_b64)
    if not hmac.compare_digest(expected, actual):
        raise ValueError("Invalid bearer token signature")
    payload = json.loads(b64url_decode(payload_b64).decode("utf-8"))
    if payload.get("type") != "access":
        raise ValueError("Invalid bearer token type")
    if int(payload.get("exp", 0)) <= int(time.time()):
        raise ValueError("Bearer token expired")
    return payload


@dataclass
class LicenseSigner:
    key_id: str
    private_key: Ed25519PrivateKey

    @classmethod
    def from_base64_or_path_or_dev(
        cls,
        key_id: str,
        raw_b64: str,
        pem_path: str,
        production: bool,
    ) -> "LicenseSigner":
        if raw_b64:
            raw = base64.b64decode(raw_b64)
            return cls(key_id=key_id, private_key=Ed25519PrivateKey.from_private_bytes(raw))
        if pem_path:
            data = Path(pem_path).read_bytes()
            key = serialization.load_pem_private_key(data, password=None)
            if not isinstance(key, Ed25519PrivateKey):
                raise RuntimeError("License private key must be Ed25519")
            return cls(key_id=key_id, private_key=key)
        if production:
            raise RuntimeError("Production license signing requires LICENSE_PRIVATE_KEY_PATH")
        return cls(key_id=key_id, private_key=Ed25519PrivateKey.generate())

    def sign_payload(self, payload: dict[str, Any]) -> str:
        body = canonical_json(payload).encode("utf-8")
        return b64url_encode(self.private_key.sign(body))
