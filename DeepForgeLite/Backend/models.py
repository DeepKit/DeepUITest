from sqlalchemy import Column, String, Integer, Boolean, DateTime, Index
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
from database import Base
import uuid


class Badge(Base):
    __tablename__ = "deepdevlite_badges"

    id = Column(String(16), primary_key=True)
    report_id = Column(String(64), nullable=False)
    seal_hash = Column(String(64), nullable=False, unique=True)
    project_name = Column(String(256), nullable=False)
    language = Column(String(32), nullable=False)
    scenario_total = Column(Integer, nullable=False)
    scenario_pass = Column(Integer, nullable=False)
    model_used = Column(String(64), nullable=False)
    retry_count = Column(Integer, default=0)
    verified_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)
    view_count = Column(Integer, default=0)

    __table_args__ = (
        Index('idx_seal_hash', 'seal_hash'),
        Index('idx_created_at', 'created_at'),
        Index('idx_language', 'language'),
    )

    @property
    def pass_rate(self) -> int:
        if self.scenario_total == 0:
            return 0
        return int(self.scenario_pass / self.scenario_total * 100)

    @property
    def short_date(self) -> str:
        return self.verified_at.strftime("%Y-%m-%d")
