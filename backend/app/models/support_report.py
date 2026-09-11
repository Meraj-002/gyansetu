from __future__ import annotations

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class SupportReport(Base, TimestampMixin):
    """A translation issue a teacher logged while offline, later synced."""

    __tablename__ = "support_reports"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    teacher_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)