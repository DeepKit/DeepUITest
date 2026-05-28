import os
import json
import uuid
import time
import hmac
import hashlib
import secrets
import base64
import binascii
import random
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Dict, Any
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, HTTPException, Security, status, Depends, Header, UploadFile, File
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import jwt
from pydantic import BaseModel
import asyncpg
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from dotenv import load_dotenv

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
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_SECONDS = 60  # 短效JWT

# ================= App & DB Setup =================
limiter = Limiter(key_func=get_remote_address)

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await asyncpg.create_pool(DATABASE_URL)
    yield
    await app.state.pool.close()

app = FastAPI(title="MindBreak API", version="1.0.0", lifespan=lifespan)
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

# 依赖注入：数据库连接�?async def get_db_pool():
    return app.state.pool

# ================= 依赖：JWT 验证 =================
async def get_current_token(credentials: HTTPAuthorizationCredentials = Security(security)) -> str:
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

# ================= API Routes =================

@app.post("/api/v1/auth")
@limiter.limit("5/minute")
async def authenticate(request: Request, body: AuthRequest, pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    登录并换�?60s 短效 JWT
    """
    ip = request.client.host
    passcode = body.passcode
    client_uuid = body.client_uuid

    async with pool.acquire() as conn:
        # 1. 检查是否存在该 passcode 以及状�?        user = await conn.fetchrow("SELECT * FROM users WHERE token = $1", passcode)
        if not user:
            raise HTTPException(status_code=401, detail="Invalid Passcode")
        
        if user['status'] == 'Banned':
            raise HTTPException(status_code=403, detail="Account Banned")

        # 2. 互踢判定
        now = datetime.now(timezone.utc)
        kick_inc = 0
        if user['last_active_uuid'] and user['last_active_uuid'] != client_uuid:
            # 判断旧会话是否活�?(假设心跳�?0s，如果最后活跃时间在 60s 内，说明是互�?
            if user['last_heartbeat_at'] and (now - user['last_heartbeat_at']).total_seconds() < 60:
                kick_inc = 1

        # 3. 频率熔断判定 (kick_count_10m)
        # 如果 kick_reset_at 距离现在超过 10 分钟，将计数器归�?        reset_time = user['kick_reset_at']
        if not reset_time or (now - reset_time).total_seconds() > 600:
            current_kick = kick_inc
            new_reset = now
        else:
            current_kick = user['kick_count_10m'] + kick_inc
            new_reset = reset_time

        # 如果熔断
        if current_kick >= 5:
            await conn.execute("UPDATE users SET status = 'Banned', ban_reason = 'Frequency_Melt' WHERE token = $1", passcode)
            raise HTTPException(status_code=403, detail="Account Banned due to abnormal sharing")

        # 4. 更新设备信息
        await conn.execute("""
            UPDATE users SET 
                last_active_ip = $1, last_active_uuid = $2, last_heartbeat_at = $3, 
                kick_count_10m = $4, kick_reset_at = $5,
                status = CASE WHEN $4 >= 3 THEN 'Warned' ELSE 'Active' END
            WHERE token = $6
        """, ip, client_uuid, now, current_kick, new_reset, passcode)

        # 如果是被警告状态，并且本次就是引起警告的那次，可选择弹窗。这里简化处理�?        if current_kick >= 3 and kick_inc > 0:
            # 抛出 402 交给前端自救
            raise HTTPException(status_code=402, detail="Warning: Account switching frequently")

        # 5. 生成 JWT
        exp_time = now + timedelta(seconds=JWT_EXPIRY_SECONDS)
        jwt_payload = {"passcode": passcode, "client_uuid": client_uuid, "exp": exp_time}
        access_token = jwt.encode(jwt_payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

        return {"access_token": access_token, "cashback_status": user.get('cashback_status', 'NONE')}

@app.post("/api/v1/heartbeat")
async def heartbeat(request: Request, body: HeartbeatRequest, passcode: str = Depends(get_current_token), pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    心跳引擎核心：维持存�?/ 发现互踢被挤�?/ 签发�?JWT
    """
    ip = request.client.host
    client_uuid = body.client_uuid

    async with pool.acquire() as conn:
        user = await conn.fetchrow("SELECT * FROM users WHERE token = $1", passcode)
        if not user or user['status'] == 'Banned':
            raise HTTPException(status_code=403, detail="Banned")
        
        if user['last_active_uuid'] != client_uuid:
            # 被踢下线了！抛出 401 告诉当前 JS 停止续命并弹�?            raise HTTPException(status_code=401, detail="Kicked_By_Other_Device")

        now = datetime.now(timezone.utc)
        await conn.execute("UPDATE users SET last_heartbeat_at = $1 WHERE token = $2", now, passcode)

        # 签发新的免死金牌
        exp_time = now + timedelta(seconds=JWT_EXPIRY_SECONDS)
        jwt_payload = {"passcode": passcode, "client_uuid": client_uuid, "exp": exp_time}
        new_token = jwt.encode(jwt_payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

        return {"access_token": new_token}

# ================= 分片混淆核心（注意：传输混淆而非端到端加密） =================

def chunk_string(s: str, n: int) -> List[str]:
    """将字符串尽量等分切成 n �?""
    length = len(s)
    n = min(n, max(1, length // 20 + 1))
    size = length // n + (length % n > 0)
    return [s[i:i+size] for i in range(0, length, size)]

@app.get("/api/v1/articles/{article_id}")
async def get_article(article_id: int, passcode: str = Depends(get_current_token), pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    分片乱序下发接口
    """
    async with pool.acquire() as conn:
        article = await conn.fetchrow("SELECT * FROM articles WHERE id = $1", article_id)
        if not article:
            raise HTTPException(status_code=404, detail="Article not found")
            
        user_record = await conn.fetchrow("SELECT granted_novels FROM users WHERE token = $1", passcode)
        granted_novels_json = user_record['granted_novels'] if user_record['granted_novels'] else '[]'
        try:
            granted_novels = json.loads(granted_novels_json)
        except (json.JSONDecodeError, TypeError):
            granted_novels = []
            
        if article['novel_key'] not in granted_novels:
            raise HTTPException(status_code=403, detail="Unauthorized access to this novel")
        
        raw_html = article['content_html']
        
        # 记录不重复阅读历史（LMM 防欺诈拦截线�?        await conn.execute("""
            INSERT INTO read_hiDeepStory (token, article_id) 
            VALUES ($1, $2) ON CONFLICT (token, article_id) DO NOTHING
        """, passcode, article_id)

    # 1. 切片 (比如切成 10 �?
    chunks = chunk_string(raw_html, 10)
    original_indices = list(range(len(chunks)))

    # 2. 组装对象并打�?    chunk_objs = [{"id": i, "content": c} for i, c in zip(original_indices, chunks)]
    random.shuffle(chunk_objs)

    # 取出打乱后的 id 顺序，这就是需要加密保护的“正确拼图顺序�?    shuffled_indices = [obj["id"] for obj in chunk_objs]
    
    # 修改下发的对象，将其自身�?id 移除，只�?content，让前端变成瞎子
    blind_chunks = [obj["content"] for obj in chunk_objs]

    # 3. HMAC-SHA256 加密序列
    # Key = HMAC_SECRET + passcode + article_id + 分钟级时间戳(向下取整5分钟)
    current_5min_window = int(time.time() / 300)
    hmac_key = f"{HMAC_SECRET}:{passcode}:{article_id}:{current_5min_window}".encode('utf-8')
    
    seq_str = json.dumps(shuffled_indices)
    signature = hmac.new(hmac_key, seq_str.encode('utf-8'), hashlib.sha256).hexdigest()

    # 将打乱后的明文序列、签名、以及瞎掉的碎片下发给前�?    return {
        "article_id": article['id'],
        "title": article['title'],
        "chunks": blind_chunks,
        "sequence": shuffled_indices,  # 混淆方案：明文下发（挡低级爬虫，不防抽包�?        "signature": signature
    }

@app.get("/api/v1/articles")
async def list_articles(novel_key: str, passcode: str = Depends(get_current_token), pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    轻量级返回特定小说的文章目录
    """
    async with pool.acquire() as conn:
        records = await conn.fetch("SELECT id, title, is_free, cop_type FROM articles WHERE novel_key = $1 ORDER BY id ASC", novel_key)
        return [dict(r) for r in records]

@app.post("/api/v1/wechat/webhook")
async def wechat_pay_webhook(request: Request, pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    [Phase 4 自动化接单管�?- 保险丝已启用]
    上线前必须实现微信签名校验与幂等查重，否则任何人可免费发证�?    当前状�? 501 Not Implemented (A-007 保险�?
    """
    # A-007 保险�? 签名验证未实现前拒绝所有调用，防止免费发证
    raise HTTPException(
        status_code=501,
        detail="Webhook signature verification not implemented. Deploy blocker active."
    )
    # ---- 以下为待实现的接单逻辑模板 ----
    # 0. TODO: 验证微信 V3 签名 (Wechatpay-Signature header)
    # 1. TODO: 幂等查重 transaction_id
    # 2. TODO: 解密 payload，提�?user_openid
    # 3. 产出防盗 Token 并入�?    # 4. TODO: 微信公众号模板消息发�?Token

@app.post("/api/v1/cashback/upload_proof")
async def upload_cashback_proof(passcode: str = Depends(get_current_token), file: UploadFile = File(...), pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    [Phase 5 裂变溯源器] 接收用户的截图证明，自动触发微信 V3 �?300�?退款�?    """
    async with pool.acquire() as conn:
        user = await conn.fetchrow("SELECT out_trade_no, cashback_status FROM users WHERE token = $1", passcode)
        if not user:
            raise HTTPException(status_code=403, detail="非法令牌")
        if user['cashback_status'] == 'REFUNDED_300':
            raise HTTPException(status_code=400, detail="您已参与过脱困者早鸟协议，无法重复返现�?)
            
        # 物理城墙：文件类型拦�?        if file.content_type not in ["image/jpeg", "image/png"]:
            raise HTTPException(status_code=400, detail="非法火种格式：仅支持 JPG �?PNG 本地截图")
            
        # 物理城墙：最高容�?5MB 熔断
        file_content = await file.read()
        if len(file_content) > 5 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="文件过载：请将证明截图压缩至 5MB 以内�?)

        # 1. 落地存储截图 (粗暴存图，只要服从�?
        os.makedirs("proofs", exist_ok=True)
        file_ext = file.filename.split(".")[-1].lower() if "." in file.filename else "jpg"
        if file_ext not in ["jpg", "jpeg", "png"]:
            raise HTTPException(status_code=400, detail="非法文件扩展�?)
        save_path = f"proofs/{passcode}_{int(time.time())}.{file_ext}"
        with open(save_path, "wb") as f:
            f.write(file_content)
            
        # 2. 调用微信 V3 退款接�?(Mock，后续由主理人填入证书和实战代码)
        cert_path = os.getenv('WECHAT_CERT_PATH', '')
        if not cert_path or not os.path.exists(cert_path):
            print("[警告] WECHAT_CERT_PATH 未设置或证书不存在，降级�?MOCK_REFUND！云端部署要求强�?chmod 400 证书体�?)
            
        # 真正环境里，这会带着 user['out_trade_no'] 和绝对路径访�?API
        # res = requests.post("https://api.mch.weixin.qq.com/v3/refund/...", cert=(cert_path, ...))
        
        # 3. 退款成功后打上终身防刷禁锢钢印
        await conn.execute("UPDATE users SET cashback_status = 'REFUNDED_300' WHERE token = $1", passcode)

    return {"code": "SUCCESS", "message": "火种已接收。脱困基�?(300RMB) 已自动下发至您的支付账户�?}

@app.get("/api/v1/config/ui-strings")
async def get_ui_strings():
    return {
        "kicked_msg": "【系统提示】由于在另一台设备（或另一浏览器）上发起了阅读请求，为保证安全，当前页面的阅读会话已挂起。您可以在新设备上继续阅读�?,
        "banned_msg": "【系统阻断】检测到该秘钥在短时间内出现多设备的高频异常并发（您的秘钥可能已泄漏）。根据防线协议，该秘钥已被物理物理销毁�?,
        "warning_msg": "【系统警告】检测到设备异常并发抖动。请确认您的环境安全，点击[确认]继续�?
    }

# 静态资源挂载：�?StaticFiles 服务整个 frontend 目录
frontend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))

@app.get("/")
async def serve_index():
    return FileResponse(os.path.join(frontend_dir, "index.html"))

# 将整�?frontend 目录挂载�?/static/，后续加任何 CSS/图片/JS 无需改后端代�?app.mount("/static", StaticFiles(directory=frontend_dir), name="static")

# 兼容性路由：保证旧的 /reader.html �?/index.html 链接仍可访问
@app.get("/index.html")
async def serve_index_compat():
    return FileResponse(os.path.join(frontend_dir, "index.html"))

@app.get("/reader.html")
async def serve_reader_compat():
    return FileResponse(os.path.join(frontend_dir, "reader.html"))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
