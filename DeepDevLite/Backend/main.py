from fastapi import FastAPI, HTTPException, Depends, Response, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from datetime import datetime
import hashlib

from models import Badge
from schemas import BadgeCreate, BadgeResponse, BadgeDetail
from badge_svg import generate_svg
from database import get_db, engine, Base

app = FastAPI(
    title="DeepDevLite Badge Service",
    description="Badge service for DeepDevLite verification",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

templates = Jinja2Templates(directory="templates")

BASE_URL = "https://badge.deepdevlite.com"


def generate_badge_id(seal_hash: str, report_id: str) -> str:
    raw = seal_hash + report_id
    return hashlib.sha256(raw.encode()).hexdigest()[:8]


@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


@app.post("/api/badges", response_model=BadgeResponse)
async def create_badge(data: BadgeCreate, db: AsyncSession = Depends(get_db)):
    badge_id = generate_badge_id(data.seal_hash, data.report_id)

    result = await db.execute(
        select(Badge).where(Badge.id == badge_id)
    )
    badge = result.scalar_one_or_none()

    if not badge:
        badge = Badge(
            id=badge_id,
            report_id=data.report_id,
            seal_hash=data.seal_hash,
            project_name=data.project_name,
            language=data.language,
            scenario_total=data.scenario_total,
            scenario_pass=data.scenario_pass,
            model_used=data.model_used,
            retry_count=data.retry_count,
            verified_at=data.verified_at,
        )
        db.add(badge)
        await db.commit()
        await db.refresh(badge)

    return _build_response(badge)


@app.get("/badge/{badge_id}/shield")
async def shield_json(badge_id: str, db: AsyncSession = Depends(get_db)):
    badge = await _get_badge(badge_id, db)

    pass_rate = badge.pass_rate
    if pass_rate == 100:
        color = "brightgreen"
    elif pass_rate >= 80:
        color = "green"
    elif pass_rate >= 60:
        color = "yellow"
    else:
        color = "red"

    return {
        "schemaVersion": 1,
        "label": "DeepDevLite",
        "message": f"{badge.scenario_pass}/{badge.scenario_total} verified",
        "color": color,
        "style": "flat-square",
        "cacheSeconds": 86400,
    }


@app.get("/badge/{badge_id}")
async def get_badge_svg(badge_id: str, db: AsyncSession = Depends(get_db)):
    badge = await _get_badge(badge_id, db)
    svg = generate_svg(badge)
    return Response(
        content=svg,
        media_type="image/svg+xml",
        headers={
            "Cache-Control": "public, max-age=86400",
            "ETag": badge.seal_hash[:16],
        }
    )


@app.get("/verify/{badge_id}", response_class=HTMLResponse)
async def verify_page(
    request: Request,
    badge_id: str,
    db: AsyncSession = Depends(get_db)
):
    badge = await _get_badge(badge_id, db)

    await db.execute(
        update(Badge)
        .where(Badge.id == badge_id)
        .values(view_count=Badge.view_count + 1)
    )
    await db.commit()

    return templates.TemplateResponse("verify.html", {
        "request": request,
        "badge": badge,
    })


@app.get("/api/badges/{badge_id}", response_model=BadgeDetail)
async def get_badge_detail(badge_id: str, db: AsyncSession = Depends(get_db)):
    badge = await _get_badge(badge_id, db)
    return BadgeDetail(
        id=badge.id,
        report_id=badge.report_id,
        project_name=badge.project_name,
        language=badge.language,
        scenario_total=badge.scenario_total,
        scenario_pass=badge.scenario_pass,
        pass_rate=badge.pass_rate,
        model_used=badge.model_used,
        retry_count=badge.retry_count,
        verified_at=badge.verified_at,
        seal_hash=badge.seal_hash,
        view_count=badge.view_count,
    )


async def _get_badge(badge_id: str, db: AsyncSession) -> Badge:
    result = await db.execute(
        select(Badge).where(Badge.id == badge_id, Badge.is_active == True)
    )
    badge = result.scalar_one_or_none()
    if not badge:
        raise HTTPException(status_code=404, detail="Badge not found")
    return badge


def _build_response(badge: Badge) -> BadgeResponse:
    badge_url = f"{BASE_URL}/badge/{badge.id}"
    shield_url = f"https://img.shields.io/endpoint?url={BASE_URL}/badge/{badge.id}/shield&style=flat-square"
    detail_url = f"{BASE_URL}/verify/{badge.id}"
    markdown = f"[![DeepDevLite Verified]({shield_url})]({detail_url})"
    html_embed = f'<a href="{detail_url}"><img src="{badge_url}" alt="DeepDevLite Verified"/></a>'

    return BadgeResponse(
        badge_id=badge.id,
        badge_url=badge_url,
        shield_url=shield_url,
        detail_url=detail_url,
        markdown=markdown,
        html_embed=html_embed,
    )


@app.get("/")
async def root():
    return {"message": "DeepDevLite Badge Service", "version": "1.0.0"}


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
