import os
import json
import time
import hmac
import base64
import random
import secrets
import hashlib
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
from functools import lru_cache
from contextlib import asynccontextmanager

import asyncpg
import jwt
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Header, HTTPException, Request, Security, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

load_dotenv()

# ================= Configuration =================
DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("DATABASE_URL environment variable is missing!")
JWT_SECRET = os.getenv("JWT_SECRET")
if not JWT_SECRET:
    raise ValueError("JWT_SECRET environment variable is missing!")
HMAC_SECRET = os.getenv("HMAC_SECRET")
if not HMAC_SECRET:
    raise ValueError("HMAC_SECRET environment variable is missing!")

WECHAT_PAY_API_V3_KEY = os.getenv("WECHAT_PAY_API_V3_KEY", "")
WECHAT_PAY_PLATFORM_CERT_PATH = os.getenv("WECHAT_PAY_PLATFORM_CERT_PATH", "")
WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH = os.getenv("WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH", "")
WECHAT_PAY_PLATFORM_SERIAL = os.getenv("WECHAT_PAY_PLATFORM_SERIAL", "").strip().upper()

JWT_ALGORITHM = "HS256"
JWT_EXPIRY_SECONDS = 60

TIER_AMOUNTS = {
    "emergency": 29900,  # ¥299
    "system": 39900,     # ¥399
    "archive": 99900,    # ¥999
}

# ================= App & DB Setup =================
limiter = Limiter(key_func=get_remote_address)


async def ensure_runtime_schema(pool: asyncpg.Pool) -> None:
    async with pool.acquire() as conn:
        await conn.execute(
            """
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1
                    FROM information_schema.columns
                    WHERE table_name = 'articles' AND column_name = 'cop_type'
                ) AND NOT EXISTS (
                    SELECT 1
                    FROM information_schema.columns
                    WHERE table_name = 'articles' AND column_name = 'rfi_type'
                ) THEN
                    ALTER TABLE articles RENAME COLUMN cop_type TO rfi_type;
                END IF;
            END $$;

            ALTER TABLE articles ADD COLUMN IF NOT EXISTS rfi_type VARCHAR(10);
            ALTER TABLE articles ADD COLUMN IF NOT EXISTS external_code VARCHAR(10);
            ALTER TABLE users ADD COLUMN IF NOT EXISTS diagnosis_mode VARCHAR(10);
            ALTER TABLE users ADD COLUMN IF NOT EXISTS rfi_type VARCHAR(10);
            ALTER TABLE users ADD COLUMN IF NOT EXISTS secondary_rfi_type VARCHAR(10);
            ALTER TABLE users ADD COLUMN IF NOT EXISTS last_diagnosis_payload JSONB;
            ALTER TABLE users ADD COLUMN IF NOT EXISTS last_diagnosis_at TIMESTAMP WITH TIME ZONE;
            ALTER TABLE users ADD COLUMN IF NOT EXISTS pack_type VARCHAR(20) DEFAULT 'universal';
            ALTER TABLE users ADD COLUMN IF NOT EXISTS pack_article_ids JSONB;
            ALTER TABLE users ADD COLUMN IF NOT EXISTS product_tier VARCHAR(20) DEFAULT 'system';

            CREATE TABLE IF NOT EXISTS wechat_pay_events (
                transaction_id VARCHAR(128) PRIMARY KEY,
                notification_id VARCHAR(128) UNIQUE,
                out_trade_no VARCHAR(128),
                event_type VARCHAR(64) NOT NULL,
                token VARCHAR(64) REFERENCES users(token) ON DELETE SET NULL,
                payload JSONB NOT NULL,
                processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );
            """
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await asyncpg.create_pool(DATABASE_URL)
    await ensure_runtime_schema(app.state.pool)
    yield
    await app.state.pool.close()


app = FastAPI(title="MindBreak API", version="1.1.0", lifespan=lifespan)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

security = HTTPBearer()

origins = [
    "http://localhost",
    "http://127.0.0.1",
    "http://localhost:8000",
    "http://127.0.0.1:8000",
    "https://goodmem.cn",
    "http://goodmem.cn",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def get_db_pool():
    return app.state.pool


async def get_current_token(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> str:
    token = credentials.credentials
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload.get("passcode")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token Expired")
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid Token")


# ================= Pydantic Models =================
class AuthRequest(BaseModel):
    passcode: str
    client_uuid: str


class HeartbeatRequest(BaseModel):
    client_uuid: str


class DiagnosisSyncRequest(BaseModel):
    payload: Dict[str, Any]


class PrepayRequest(BaseModel):
    product_tier: str  # 'emergency', 'system', 'archive'
    rfi_type: Optional[str] = None
    novel_key: str = "mindbreak"
    client_uuid: Optional[str] = None
    out_trade_no: Optional[str] = None


# ================= Shared Helpers =================
def isoformat_or_none(value: Optional[datetime]) -> Optional[str]:
    return value.isoformat() if isinstance(value, datetime) else None


def parse_jsonb_array(value: Any) -> List[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return []
        return parsed if isinstance(parsed, list) else []
    return []


def parse_jsonb_object(value: Any) -> Optional[Dict[str, Any]]:
    if value is None:
        return None
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None
    return None


def parse_iso_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value or not isinstance(value, str):
        return None
    try:
        normalized = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def build_auth_payload(access_token: str, user: asyncpg.Record) -> Dict[str, Any]:
    return {
        "access_token": access_token,
        "product_tier": user["product_tier"] or "system",
        "cashback_status": user["cashback_status"] or "NONE",
        "pack_type": user["pack_type"] or "universal",
        "diagnosis_payload": parse_jsonb_object(user["last_diagnosis_payload"]),
        "diagnosis_updated_at": isoformat_or_none(user["last_diagnosis_at"]),
    }


async def save_diagnosis_payload(
    conn: asyncpg.Connection,
    passcode: str,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    diagnosis_mode = payload.get("diagnosis_mode")
    triage_status = payload.get("triage_status")
    if not diagnosis_mode or not triage_status:
        raise HTTPException(status_code=400, detail="Diagnosis payload is incomplete")

    saved_at = parse_iso_datetime(payload.get("saved_at")) or datetime.now(timezone.utc)
    normalized_payload = {**payload, "saved_at": saved_at.isoformat()}

    await conn.execute(
        """
        UPDATE users
        SET diagnosis_mode = $1,
            rfi_type = $2,
            secondary_rfi_type = $3,
            last_diagnosis_payload = $4::jsonb,
            last_diagnosis_at = $5
        WHERE token = $6
        """,
        diagnosis_mode,
        payload.get("rfi_type"),
        payload.get("secondary_rfi_type"),
        json.dumps(normalized_payload, ensure_ascii=False),
        saved_at,
        passcode,
    )
    return normalized_payload


def chunk_string(content: str, parts: int) -> List[str]:
    length = len(content)
    parts = min(parts, max(1, length // 20 + 1))
    size = length // parts + (length % parts > 0)
    return [content[i : i + size] for i in range(0, length, size)]


def parse_attach_payload(raw_attach: Any) -> Dict[str, Any]:
    if isinstance(raw_attach, dict):
        return raw_attach
    if isinstance(raw_attach, str) and raw_attach.strip():
        try:
            parsed = json.loads(raw_attach)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            return {"raw_attach": raw_attach}
    return {}


async def generate_unique_token(conn: asyncpg.Connection) -> str:
    for _ in range(12):
        token = secrets.token_hex(6)
        exists = await conn.fetchval("SELECT 1 FROM users WHERE token = $1", token)
        if not exists:
            return token
    raise HTTPException(status_code=500, detail="Unable to allocate token")


@lru_cache(maxsize=1)
def load_wechat_platform_key() -> Tuple[Any, str]:
    if WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH and os.path.exists(WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH):
        with open(WECHAT_PAY_PLATFORM_PUBLIC_KEY_PATH, "rb") as fp:
            public_key = serialization.load_pem_public_key(fp.read())
        return public_key, WECHAT_PAY_PLATFORM_SERIAL

    if WECHAT_PAY_PLATFORM_CERT_PATH and os.path.exists(WECHAT_PAY_PLATFORM_CERT_PATH):
        with open(WECHAT_PAY_PLATFORM_CERT_PATH, "rb") as fp:
            cert = x509.load_pem_x509_certificate(fp.read())
        serial = format(cert.serial_number, "X").upper()
        return cert.public_key(), WECHAT_PAY_PLATFORM_SERIAL or serial

    raise HTTPException(
        status_code=503,
        detail="WeChat Pay platform certificate/public key is not configured",
    )


def verify_wechat_signature(
    raw_body: bytes,
    timestamp: Optional[str],
    nonce: Optional[str],
    signature: Optional[str],
    serial: Optional[str],
) -> None:
    if not timestamp or not nonce or not signature or not serial:
        raise HTTPException(status_code=400, detail="Missing WeChat Pay signature headers")

    public_key, expected_serial = load_wechat_platform_key()
    header_serial = serial.strip().upper()
    if expected_serial and header_serial != expected_serial:
        raise HTTPException(status_code=401, detail="WeChat Pay serial mismatch")

    message = b"\n".join(
        [timestamp.encode("utf-8"), nonce.encode("utf-8"), raw_body, b""]
    )
    try:
        signature_bytes = base64.b64decode(signature)
        public_key.verify(signature_bytes, message, padding.PKCS1v15(), hashes.SHA256())
    except (ValueError, InvalidSignature):
        raise HTTPException(status_code=401, detail="Invalid WeChat Pay signature")


def decrypt_wechat_resource(resource: Dict[str, Any]) -> Dict[str, Any]:
    if len(WECHAT_PAY_API_V3_KEY.encode("utf-8")) != 32:
        raise HTTPException(status_code=503, detail="WeChat Pay API v3 key is not configured")

    nonce = resource.get("nonce")
    ciphertext = resource.get("ciphertext")
    if not nonce or not ciphertext:
        raise HTTPException(status_code=400, detail="WeChat Pay resource payload is incomplete")

    associated_data = resource.get("associated_data", "")
    aesgcm = AESGCM(WECHAT_PAY_API_V3_KEY.encode("utf-8"))
    try:
        plaintext = aesgcm.decrypt(
            nonce.encode("utf-8"),
            base64.b64decode(ciphertext),
            associated_data.encode("utf-8") if associated_data else None,
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Failed to decrypt WeChat payload: {exc}")

    try:
        return json.loads(plaintext.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid WeChat resource JSON: {exc}")


def success_ack() -> Dict[str, str]:
    return {"code": "SUCCESS", "message": "成功"}


# ================= API Routes =================
@app.post("/api/v1/auth")
@limiter.limit("5/minute")
async def authenticate(
    request: Request,
    body: AuthRequest,
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    ip = request.client.host
    passcode = body.passcode
    client_uuid = body.client_uuid

    async with pool.acquire() as conn:
        user = await conn.fetchrow("SELECT * FROM users WHERE token = $1", passcode)
        if not user:
            raise HTTPException(status_code=401, detail="Invalid Passcode")
        if user["status"] == "Banned":
            raise HTTPException(status_code=403, detail="Account Banned")

        now = datetime.now(timezone.utc)
        kick_inc = 0
        if user["last_active_uuid"] and user["last_active_uuid"] != client_uuid:
            if user["last_heartbeat_at"] and (now - user["last_heartbeat_at"]).total_seconds() < 60:
                kick_inc = 1

        reset_time = user["kick_reset_at"]
        if not reset_time or (now - reset_time).total_seconds() > 600:
            current_kick = kick_inc
            new_reset = now
        else:
            current_kick = user["kick_count_10m"] + kick_inc
            new_reset = reset_time

        if current_kick >= 5:
            await conn.execute(
                "UPDATE users SET status = 'Banned', ban_reason = 'Frequency_Melt' WHERE token = $1",
                passcode,
            )
            raise HTTPException(status_code=403, detail="Account Banned due to abnormal sharing")

        await conn.execute(
            """
            UPDATE users SET
                last_active_ip = $1,
                last_active_uuid = $2,
                last_heartbeat_at = $3,
                kick_count_10m = $4,
                kick_reset_at = $5,
                status = CASE WHEN $4 >= 3 THEN 'Warned' ELSE 'Active' END
            WHERE token = $6
            """,
            ip,
            client_uuid,
            now,
            current_kick,
            new_reset,
            passcode,
        )

        user = await conn.fetchrow("SELECT * FROM users WHERE token = $1", passcode)
        if current_kick >= 3 and kick_inc > 0:
            raise HTTPException(status_code=402, detail="Warning: Account switching frequently")

        exp_time = now + timedelta(seconds=JWT_EXPIRY_SECONDS)
        jwt_payload = {"passcode": passcode, "client_uuid": client_uuid, "exp": exp_time}
        access_token = jwt.encode(jwt_payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
        return build_auth_payload(access_token, user)


@app.post("/api/v1/heartbeat")
async def heartbeat(
    request: Request,
    body: HeartbeatRequest,
    passcode: str = Depends(get_current_token),
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    client_uuid = body.client_uuid

    async with pool.acquire() as conn:
        user = await conn.fetchrow("SELECT * FROM users WHERE token = $1", passcode)
        if not user or user["status"] == "Banned":
            raise HTTPException(status_code=403, detail="Banned")
        if user["last_active_uuid"] != client_uuid:
            raise HTTPException(status_code=401, detail="Kicked_By_Other_Device")

        now = datetime.now(timezone.utc)
        await conn.execute(
            "UPDATE users SET last_heartbeat_at = $1, last_active_ip = $2 WHERE token = $3",
            now,
            request.client.host,
            passcode,
        )

        exp_time = now + timedelta(seconds=JWT_EXPIRY_SECONDS)
        jwt_payload = {"passcode": passcode, "client_uuid": client_uuid, "exp": exp_time}
        new_token = jwt.encode(jwt_payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
        return {"access_token": new_token}


@app.get("/api/v1/diagnosis")
async def get_diagnosis(
    passcode: str = Depends(get_current_token),
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    async with pool.acquire() as conn:
        user = await conn.fetchrow(
            """
            SELECT diagnosis_mode, rfi_type, secondary_rfi_type, last_diagnosis_payload,
                   last_diagnosis_at, pack_type
            FROM users WHERE token = $1
            """,
            passcode,
        )
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "diagnosis_payload": parse_jsonb_object(user["last_diagnosis_payload"]),
        "diagnosis_updated_at": isoformat_or_none(user["last_diagnosis_at"]),
        "pack_type": user["pack_type"] or "universal",
    }


@app.post("/api/v1/diagnosis")
async def save_diagnosis(
    body: DiagnosisSyncRequest,
    passcode: str = Depends(get_current_token),
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    async with pool.acquire() as conn:
        stored_payload = await save_diagnosis_payload(conn, passcode, body.payload)
    return {
        "diagnosis_payload": stored_payload,
        "diagnosis_updated_at": stored_payload.get("saved_at"),
    }


@app.get("/api/v1/articles/{article_id}")
async def get_article(
    article_id: int,
    passcode: str = Depends(get_current_token),
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    async with pool.acquire() as conn:
        article = await conn.fetchrow("SELECT * FROM articles WHERE id = $1", article_id)
        if not article:
            raise HTTPException(status_code=404, detail="Article not found")

        user_record = await conn.fetchrow(
            "SELECT granted_novels FROM users WHERE token = $1",
            passcode,
        )
        granted_novels = parse_jsonb_array(user_record["granted_novels"] if user_record else None)
        if article["novel_key"] not in granted_novels:
            raise HTTPException(status_code=403, detail="Unauthorized access to this novel")

        raw_html = article["content_html"]
        await conn.execute(
            """
            INSERT INTO read_hiDeepStory (token, article_id)
            VALUES ($1, $2)
            ON CONFLICT (token, article_id) DO NOTHING
            """,
            passcode,
            article_id,
        )

    chunks = chunk_string(raw_html, 10)
    original_indices = list(range(len(chunks)))
    chunk_objs = [{"id": i, "content": c} for i, c in zip(original_indices, chunks)]
    random.shuffle(chunk_objs)

    shuffled_indices = [obj["id"] for obj in chunk_objs]
    blind_chunks = [obj["content"] for obj in chunk_objs]

    current_5min_window = int(time.time() / 300)
    hmac_key = f"{HMAC_SECRET}:{passcode}:{article_id}:{current_5min_window}".encode("utf-8")
    seq_str = json.dumps(shuffled_indices)
    signature = hmac.new(hmac_key, seq_str.encode("utf-8"), hashlib.sha256).hexdigest()

    return {
        "article_id": article["id"],
        "external_code": article["external_code"],
        "title": article["title"],
        "chunks": blind_chunks,
        "sequence": shuffled_indices,
        "signature": signature,
    }


async def get_user_allowed_article_ids(conn: asyncpg.Connection, user: asyncpg.Record) -> List[int]:
    """根据用户�?product_tier 计算其允许访问的文章 ID 列表"""
    tier = user["product_tier"] or "system"
    rfi_type = user["rfi_type"]
    novel_key = "mindbreak" # 暂定

    if tier == "emergency":
        # 5 篇：3 篇固定证明件 + 2 篇主局核心�?        proof_codes = ["M0410", "H3110", "J4110"]
        proof_rows = await conn.fetch(
            "SELECT id FROM articles WHERE external_code = ANY($1)", proof_codes
        )
        ids = [r["id"] for r in proof_rows]
        
        if rfi_type:
            main_rows = await conn.fetch(
                "SELECT id FROM articles WHERE rfi_type = $1 AND external_code NOT IN ('M0410', 'H3110', 'J4110') ORDER BY id ASC LIMIT 2",
                rfi_type
            )
            ids.extend([r["id"] for r in main_rows])
        return list(set(ids))

    elif tier == "system":
        # 108 篇：主局优先，补足至 108
        rows = await conn.fetch(
            """
            SELECT id FROM articles 
            WHERE novel_key = $1 
            ORDER BY (CASE WHEN rfi_type = $2 THEN 0 ELSE 1 END), id ASC 
            LIMIT 108
            """,
            novel_key, rfi_type
        )
        return [r["id"] for r in rows]

    elif tier == "archive":
        # 236 篇规格：36 通用 + 80 主局 + 120 (4x30) 其它
        final_ids = []
        
        # 36 通用
        univ_rows = await conn.fetch(
            "SELECT id FROM articles WHERE novel_key = $1 AND (rfi_type IS NULL OR cluster_id IN ('00', '99')) ORDER BY id ASC LIMIT 36",
            novel_key
        )
        final_ids.extend([r["id"] for r in univ_rows])
        
        # 80 主局
        if rfi_type:
            main_rows = await conn.fetch(
                "SELECT id FROM articles WHERE novel_key = $1 AND rfi_type = $2 ORDER BY id ASC LIMIT 80",
                novel_key, rfi_type
            )
            final_ids.extend([r["id"] for r in main_rows])
            
        # 120 其它 (�?30)
        other_types = ["water", "wood", "fire", "earth", "metal"]
        if rfi_type in other_types:
            other_types.remove(rfi_type)
            
        for ot in other_types:
            ot_rows = await conn.fetch(
                "SELECT id FROM articles WHERE novel_key = $1 AND rfi_type = $2 ORDER BY id ASC LIMIT 30",
                novel_key, ot
            )
            final_ids.extend([r["id"] for r in ot_rows])
            
        return list(set(final_ids))

    return []


@app.get("/api/v1/articles")
async def list_articles(
    novel_key: str,
    passcode: str = Depends(get_current_token),
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    async with pool.acquire() as conn:
        user_record = await conn.fetchrow(
            "SELECT * FROM users WHERE token = $1",
            passcode,
        )
        if not user_record:
             raise HTTPException(status_code=401, detail="Invalid token")

        granted_novels = parse_jsonb_array(user_record["granted_novels"])
        if novel_key not in granted_novels:
            raise HTTPException(status_code=403, detail="Unauthorized access to this novel")

        allowed_ids = await get_user_allowed_article_ids(conn, user_record)
        
        records = await conn.fetch(
            """
            SELECT id, external_code, title, is_free, rfi_type, subtitle, drug_type, drug_layer, judgment_tag
            FROM articles
            WHERE id = ANY($1)
            ORDER BY id ASC
            """,
            allowed_ids,
        )
        return [dict(record) for record in records]


@app.post("/api/v1/wechat/webhook")
async def wechat_pay_webhook(
    request: Request,
    pool: asyncpg.Pool = Depends(get_db_pool),
    wechatpay_timestamp: Optional[str] = Header(default=None, alias="Wechatpay-Timestamp"),
    wechatpay_nonce: Optional[str] = Header(default=None, alias="Wechatpay-Nonce"),
    wechatpay_signature: Optional[str] = Header(default=None, alias="Wechatpay-Signature"),
    wechatpay_serial: Optional[str] = Header(default=None, alias="Wechatpay-Serial"),
):
    raw_body = await request.body()
    verify_wechat_signature(
        raw_body,
        wechatpay_timestamp,
        wechatpay_nonce,
        wechatpay_signature,
        wechatpay_serial,
    )

    try:
        notification = json.loads(raw_body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid webhook JSON: {exc}")

    event_type = notification.get("event_type") or ""
    if event_type != "TRANSACTION.SUCCESS":
        return success_ack()

    resource = notification.get("resource")
    if not isinstance(resource, dict):
        raise HTTPException(status_code=400, detail="Missing WeChat resource block")

    resource_data = decrypt_wechat_resource(resource)
    if resource_data.get("trade_state") != "SUCCESS":
        return success_ack()

    transaction_id = resource_data.get("transaction_id")
    out_trade_no = resource_data.get("out_trade_no")
    if not transaction_id or not out_trade_no:
        raise HTTPException(status_code=400, detail="WeChat transaction payload is incomplete")

    attach_payload = parse_attach_payload(resource_data.get("attach"))
    granted_novels = attach_payload.get("granted_novels", ["mindbreak"])
    if isinstance(granted_novels, str):
        granted_novels = [granted_novels]
    granted_novels = granted_novels if isinstance(granted_novels, list) and granted_novels else ["mindbreak"]
    
    # 提取 product_tier
    product_tier = attach_payload.get("product_tier", "system")
    pack_type = attach_payload.get("pack_type", "universal")

    async with pool.acquire() as conn:
        inserted = await conn.fetchrow(
            """
            INSERT INTO wechat_pay_events (
                transaction_id, notification_id, out_trade_no, event_type, payload
            )
            VALUES ($1, $2, $3, $4, $5::jsonb)
            ON CONFLICT DO NOTHING
            RETURNING transaction_id
            """,
            transaction_id,
            notification.get("id"),
            out_trade_no,
            event_type,
            json.dumps(resource_data, ensure_ascii=False),
        )
        if not inserted:
            return success_ack()

        user = await conn.fetchrow(
            "SELECT token FROM users WHERE out_trade_no = $1",
            out_trade_no,
        )
        if user:
            token = user["token"]
            await conn.execute(
                """
                UPDATE users
                SET payment_status = 'Paid',
                    granted_novels = $1::jsonb,
                    pack_type = $2,
                    product_tier = $3
                WHERE token = $4
                """,
                json.dumps(granted_novels, ensure_ascii=False),
                pack_type,
                product_tier,
                token,
            )
        else:
            token = await generate_unique_token(conn)
            await conn.execute(
                """
                INSERT INTO users (
                    token, granted_novels, payment_status, out_trade_no,
                    cashback_status, status, pack_type, product_tier
                )
                VALUES ($1, $2::jsonb, 'Paid', $3, 'NONE', 'Active', $4, $5)
                """,
                token,
                json.dumps(granted_novels, ensure_ascii=False),
                out_trade_no,
                pack_type,
                product_tier,
            )

        await conn.execute(
            "UPDATE wechat_pay_events SET token = $1 WHERE transaction_id = $2",
            token,
            transaction_id,
        )

    return success_ack()


@app.post("/api/v1/pay/prepay")
async def create_prepay_order(
    body: PrepayRequest,
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    """
    模拟微信支付统一下单接口�?    实际环境中应当调用微信支�?V3 SDK 发起下单�?    """
    tier = body.product_tier
    if tier not in TIER_AMOUNTS:
        raise HTTPException(status_code=400, detail="Invalid product tier")
        
    amount = TIER_AMOUNTS[tier]
    out_trade_no = body.out_trade_no or f"ORDER_{int(time.time())}_{secrets.token_hex(4)}"
    
    # 原型阶段返回 H5 支付占位参数；正式环境中这里应调用微信支�?V3 下单�?    return {
        "code": "SUCCESS",
        "out_trade_no": out_trade_no,
        "amount": amount,
        "product_tier": tier,
        "pay_params": {
            "appId": "wx_mock_appid",
            "timeStamp": str(int(time.time())),
            "nonceStr": secrets.token_hex(16),
            "package": f"prepay_id=mock_{secrets.token_hex(10)}",
            "signType": "RSA",
            "paySign": "mock_sign"
        }
    }


@app.post("/api/v1/cashback/upload_proof")
async def upload_cashback_proof(
    passcode: str = Depends(get_current_token),
    file: UploadFile = File(...),
    pool: asyncpg.Pool = Depends(get_db_pool),
):
    async with pool.acquire() as conn:
        user = await conn.fetchrow(
            "SELECT out_trade_no, cashback_status FROM users WHERE token = $1",
            passcode,
        )
        if not user:
            raise HTTPException(status_code=403, detail="非法令牌")
        if user["cashback_status"] == "REFUNDED_300":
            raise HTTPException(status_code=400, detail="当前账号的返现申请已处理完成，请勿重复提交�?)

        if file.content_type not in ["image/jpeg", "image/png"]:
            raise HTTPException(status_code=400, detail="文件格式不支持，请上�?JPG �?PNG 图片�?)

        file_content = await file.read()
        if len(file_content) > 5 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="图片过大，请压缩�?5MB 以内�?)

        proofs_dir = os.getenv("PROOFS_DIR", "proofs")
        os.makedirs(proofs_dir, exist_ok=True)
        file_ext = file.filename.split(".")[-1].lower() if "." in file.filename else "jpg"
        if file_ext not in ["jpg", "jpeg", "png"]:
            raise HTTPException(status_code=400, detail="文件扩展名不支持�?)
        save_path = os.path.join(proofs_dir, f"{passcode}_{int(time.time())}.{file_ext}")
        with open(save_path, "wb") as fp:
            fp.write(file_content)

        cert_path = os.getenv("WECHAT_CERT_PATH", "")
        if not cert_path or not os.path.exists(cert_path):
            print("[警告] WECHAT_CERT_PATH 未设置或证书不存在，降级�?MOCK_REFUND�?)

        await conn.execute(
            "UPDATE users SET cashback_status = 'REFUNDED_300' WHERE token = $1",
            passcode,
        )

    return {"code": "SUCCESS", "message": "证明材料已接收，申请结果会按当前流程处理�?}


@app.get("/api/v1/config/ui-strings")
async def get_ui_strings():
    return {
        "kicked_msg": "【系统提示】由于在另一台设备（或另一浏览器）上发起了阅读请求，为保证安全，当前页面的阅读会话已挂起。您可以在新设备上继续阅读�?,
        "banned_msg": "【系统阻断】检测到该秘钥在短时间内出现多设备的高频异常并发（您的秘钥可能已泄漏）。根据防线协议，该秘钥已被物理物理销毁�?,
        "warning_msg": "【系统警告】检测到设备异常并发抖动。请确认您的环境安全，点击[确认]继续�?,
    }


# ================= Static Routes =================
frontend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))


@app.get("/")
async def serve_index():
    return FileResponse(os.path.join(frontend_dir, "index.html"))


@app.get("/break")
@app.get("/break/")
@app.get("/break/diag")
@app.get("/break/result")
@app.get("/break/pay")
@app.get("/break/pay/basic")
async def serve_break_alias():
    return FileResponse(os.path.join(frontend_dir, "index.html"))


app.mount("/static", StaticFiles(directory=frontend_dir), name="static")


@app.get("/index.html")
async def serve_index_compat():
    return FileResponse(os.path.join(frontend_dir, "index.html"))


@app.get("/reader.html")
async def serve_reader_compat():
    return FileResponse(os.path.join(frontend_dir, "reader.html"))


@app.get("/return")
@app.get("/return/")
@app.get("/return/result")
@app.get("/return/pay")
@app.get("/return/annual")
async def serve_wsh_alias():
    return FileResponse(os.path.join(frontend_dir, "wsh.html"))


@app.get("/wsh.html")
async def serve_wsh_compat():
    return FileResponse(os.path.join(frontend_dir, "wsh.html"))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
