# DeepDevLite 徽章服务 �?PG15 版本更新规格

**版本**: v1.1（替�?v1.0 �?SQLite 部分�? 
**变更**: SQLite �?PostgreSQL 15，复用已�?FastAPI 服务�? 
**其余不变**: API 接口、SVG 生成、Delphi 对接、详情页

---

## 1. 依赖更新

### requirements.txt（新�?变更部分�?
```
# 替换 sqlalchemy 默认驱动
asyncpg==0.29.0          # 异步 PG 驱动（推荐）
sqlalchemy[asyncio]==2.0.30
alembic==1.13.1          # 数据库迁移工�?
# 原有保留
fastapi==0.111.0
uvicorn==0.30.0
pydantic==2.7.0
jinja2==3.1.4
python-multipart==0.0.9
```

---

## 2. 数据库连�?
### database.py

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base
import os

# 从环境变量读取，不要硬编�?DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://user:password@localhost:5432/progeelite"
)

engine = create_async_engine(
    DATABASE_URL,
    pool_size=5,
    max_overflow=10,
    echo=False,  # 生产环境关闭 SQL 日志
)

AsyncSessionLocal = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

Base = declarative_base()

async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
```

---

## 3. 数据模型（PG15 版）

### models.py

```python
from sqlalchemy import Column, String, Integer, Boolean, DateTime, Index
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
from database import Base
import uuid

class Badge(Base):
    __tablename__ = "progeelite_badges"

    # 主键�?位短 ID（可读性好，够用）
    id             = Column(String(16),  primary_key=True)
    
    # 来自桌面端的封存数据
    report_id      = Column(String(64),  nullable=False)
    seal_hash      = Column(String(64),  nullable=False, unique=True)
    project_name   = Column(String(256), nullable=False)
    language       = Column(String(32),  nullable=False)
    scenario_total = Column(Integer,     nullable=False)
    scenario_pass  = Column(Integer,     nullable=False)
    model_used     = Column(String(64),  nullable=False)
    retry_count    = Column(Integer,     default=0)
    
    # 时间
    verified_at    = Column(DateTime,    nullable=False)  # 桌面端验证时�?    created_at     = Column(DateTime,    default=datetime.utcnow)
    
    # 状�?    is_active      = Column(Boolean,     default=True)
    view_count     = Column(Integer,     default=0)  # 详情页访问计�?
    # PG 索引（加速查询）
    __table_args__ = (
        Index('idx_seal_hash',  'seal_hash'),
        Index('idx_created_at', 'created_at'),
        Index('idx_language',   'language'),
    )

    @property
    def pass_rate(self) -> int:
        if self.scenario_total == 0:
            return 0
        return int(self.scenario_pass / self.scenario_total * 100)

    @property
    def short_date(self) -> str:
        return self.verified_at.strftime("%Y-%m-%d")
```

---

## 4. 数据库迁移（Alembic�?
### 初始�?
```bash
# 在项目根目录执行一�?alembic init migrations
```

### migrations/env.py（关键配置）

```python
from models import Base
from database import DATABASE_URL

# 替换默认配置
config.set_main_option("sqlalchemy.url", DATABASE_URL)
target_metadata = Base.metadata
```

### 生成并执行迁�?
```bash
# 生成迁移脚本
alembic revision --autogenerate -m "create progeelite_badges table"

# 执行迁移（在已有 PG15 上建表）
alembic upgrade head
```

生成�?SQL 大致为：

```sql
CREATE TABLE progeelite_badges (
    id              VARCHAR(16)  PRIMARY KEY,
    report_id       VARCHAR(64)  NOT NULL,
    seal_hash       VARCHAR(64)  NOT NULL UNIQUE,
    project_name    VARCHAR(256) NOT NULL,
    language        VARCHAR(32)  NOT NULL,
    scenario_total  INTEGER      NOT NULL,
    scenario_pass   INTEGER      NOT NULL,
    model_used      VARCHAR(64)  NOT NULL,
    retry_count     INTEGER      DEFAULT 0,
    verified_at     TIMESTAMP    NOT NULL,
    created_at      TIMESTAMP    DEFAULT NOW(),
    is_active       BOOLEAN      DEFAULT TRUE,
    view_count      INTEGER      DEFAULT 0
);

CREATE INDEX idx_seal_hash  ON progeelite_badges(seal_hash);
CREATE INDEX idx_created_at ON progeelite_badges(created_at);
CREATE INDEX idx_language   ON progeelite_badges(language);
```

---

## 5. 异步 API 接口（完整版�?
### main.py

```python
from fastapi import FastAPI, HTTPException, Depends, Response, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from datetime import datetime
import hashlib

from models import Badge
from schemas import BadgeCreate, BadgeResponse
from badge_svg import generate_svg
from database import get_db, engine, Base

# ── 如果是挂在已�?FastAPI app 上，�?router ──
from fastapi import APIRouter
router = APIRouter(prefix="/progeelite", tags=["DeepDevLite Badge"])

# ── 如果是独�?app ──
# app = FastAPI()
# app.add_middleware(CORSMiddleware, allow_origins=["*"], ...)

templates = Jinja2Templates(directory="templates")


def generate_badge_id(seal_hash: str, report_id: str) -> str:
    raw = seal_hash + report_id
    return hashlib.sha256(raw.encode()).hexdigest()[:8]


# ── 1. 创建徽章 ──
@router.post("/api/badges", response_model=BadgeResponse)
async def create_badge(data: BadgeCreate, db: AsyncSession = Depends(get_db)):
    badge_id = generate_badge_id(data.seal_hash, data.report_id)

    # 幂等：已存在则直接返�?    result = await db.execute(
        select(Badge).where(Badge.id == badge_id)
    )
    badge = result.scalar_one_or_none()

    if not badge:
        badge = Badge(
            id             = badge_id,
            report_id      = data.report_id,
            seal_hash      = data.seal_hash,
            project_name   = data.project_name,
            language       = data.language,
            scenario_total = data.scenario_total,
            scenario_pass  = data.scenario_pass,
            model_used     = data.model_used,
            retry_count    = data.retry_count,
            verified_at    = data.verified_at,
        )
        db.add(badge)
        await db.commit()
        await db.refresh(badge)

    return _build_response(badge)


# ── 2. Shields.io JSON ──
@router.get("/badge/{badge_id}/shield")
async def shield_json(badge_id: str, db: AsyncSession = Depends(get_db)):
    badge = await _get_badge(badge_id, db)

    color = (
        "brightgreen" if badge.pass_rate == 100 else
        "green"       if badge.pass_rate >= 80  else
        "yellow"      if badge.pass_rate >= 60  else
        "red"
    )

    return {
        "schemaVersion": 1,
        "label":         "DeepDevLite",
        "message":       f"{badge.scenario_pass}/{badge.scenario_total} verified",
        "color":         color,
        "style":         "flat-square",
        "cacheSeconds":  86400,
    }


# ── 3. 自绘 SVG 徽章 ──
@router.get("/badge/{badge_id}")
async def get_badge_svg(badge_id: str, db: AsyncSession = Depends(get_db)):
    badge = await _get_badge(badge_id, db)
    svg = generate_svg(badge)
    return Response(
        content=svg,
        media_type="image/svg+xml",
        headers={
            "Cache-Control": "public, max-age=86400",
            "ETag":          badge.seal_hash[:16],
        }
    )


# ── 4. 详情�?──
@router.get("/verify/{badge_id}", response_class=HTMLResponse)
async def verify_page(
    request: Request,
    badge_id: str,
    db: AsyncSession = Depends(get_db)
):
    badge = await _get_badge(badge_id, db)

    # 访问计数（非阻塞�?    await db.execute(
        update(Badge)
        .where(Badge.id == badge_id)
        .values(view_count=Badge.view_count + 1)
    )
    await db.commit()

    return templates.TemplateResponse("verify.html", {
        "request": request,
        "badge":   badge,
    })


# ── 工具函数 ──
async def _get_badge(badge_id: str, db: AsyncSession) -> Badge:
    result = await db.execute(
        select(Badge).where(Badge.id == badge_id, Badge.is_active == True)
    )
    badge = result.scalar_one_or_none()
    if not badge:
        raise HTTPException(status_code=404, detail="Badge not found")
    return badge


def _build_response(badge: Badge) -> BadgeResponse:
    BASE        = "https://badge.progeelite.com"
    badge_url   = f"{BASE}/progeelite/badge/{badge.id}"
    shield_url  = f"https://img.shields.io/endpoint?url={BASE}/progeelite/badge/{badge.id}/shield&style=flat-square"
    detail_url  = f"{BASE}/progeelite/verify/{badge.id}"
    markdown    = f"[![DeepDevLite Verified]({shield_url})]({detail_url})"
    html_embed  = f'<a href="{detail_url}"><img src="{badge_url}" alt="DeepDevLite Verified"/></a>'

    return BadgeResponse(
        badge_id   = badge.id,
        badge_url  = badge_url,
        shield_url = shield_url,
        detail_url = detail_url,
        markdown   = markdown,
        html_embed = html_embed,
    )
```

---

## 6. 挂载到已�?FastAPI app

如果你的服务器已经有一�?FastAPI 实例，只需�?
```python
# 在你已有�?main.py �?app.py 里加两行
from progeelite_badge import router as badge_router

app.include_router(badge_router)
```

路由会自动注册为�?- `POST /progeelite/api/badges`
- `GET  /progeelite/badge/{id}`
- `GET  /progeelite/badge/{id}/shield`
- `GET  /progeelite/verify/{id}`

---

## 7. 环境变量

```bash
# .env 文件
DATABASE_URL=postgresql+asyncpg://your_user:your_password@localhost:5432/your_db
BADGE_BASE_URL=https://badge.progeelite.com
```

```python
# �?python-dotenv 加载
from dotenv import load_dotenv
load_dotenv()
```

---

## 8. PG15 特有优化（可选，后期�?
```sql
-- 统计各语言徽章数量（用于展示页�?CREATE VIEW progeelite_stats AS
SELECT
    language,
    COUNT(*)                              AS total_badges,
    AVG(pass_rate)                        AS avg_pass_rate,
    SUM(view_count)                       AS total_views,
    MAX(created_at)                       AS latest_at
FROM progeelite_badges
WHERE is_active = TRUE
GROUP BY language;

-- 分区（如果徽章量很大，按月分区）
-- 暂时不需要，等数据量超过 100 万再考虑
```

---

## 9. 开发顺序（更新版）

| 步骤 | 内容 | 时间 |
|------|------|------|
| 1 | 安装 asyncpg，配�?DATABASE_URL | 15分钟 |
| 2 | 运行 `alembic upgrade head` 建表 | 10分钟 |
| 3 | �?router 挂载到已�?FastAPI app | 15分钟 |
| 4 | 测试 `POST /api/badges` | 30分钟 |
| 5 | 测试 Shields.io JSON + 详情�?| 30分钟 |
| 6 | Delphi 侧对接（参�?Core-Spec.md）| 2小时 |
| **合计** | | **�?3-4 小时** |
