from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class BadgeCreate(BaseModel):
    report_id: str
    seal_hash: str
    project_name: str
    language: str
    scenario_total: int
    scenario_pass: int
    model_used: str
    retry_count: int = 0
    verified_at: datetime


class BadgeResponse(BaseModel):
    badge_id: str
    badge_url: str
    shield_url: str
    detail_url: str
    markdown: str
    html_embed: str


class BadgeDetail(BaseModel):
    id: str
    report_id: str
    project_name: str
    language: str
    scenario_total: int
    scenario_pass: int
    pass_rate: int
    model_used: str
    retry_count: int
    verified_at: datetime
    seal_hash: str
    view_count: int
