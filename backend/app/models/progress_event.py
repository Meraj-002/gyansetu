from __future__ import annotations

from sqlalchemy import JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class ProgressEvent(Base, TimestampMixin):
    """One ProgressEvent (lessons, assessments, sessions, flashcards...)."""

    __tablename__ = "progress_events"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    teacher_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    occurred_at: Mapped[str] = mapped_column(String(64), nullable=False)
    lesson_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    event_data: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)