from __future__ import annotations

from sqlalchemy import JSON, Boolean, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class ClassroomSession(Base, TimestampMixin):
    """A saved live-classroom session as returned by ClassroomSession.toJson().

    ``session_id`` is generated on the device (``CLS-ddMMyy-HHmm``) and is the
    primary key so a re-push is an idempotent upsert. ``turns`` carries the
    full conversation as JSON.
    """

    __tablename__ = "classroom_sessions"

    session_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    teacher_id: Mapped[str | None] = mapped_column(
        String(64), nullable=True, index=True
    )
    lesson_id: Mapped[str] = mapped_column(String(64), nullable=False)
    lesson_title: Mapped[str] = mapped_column(String, nullable=False, default="")
    class_number: Mapped[int] = mapped_column(Integer, nullable=False)
    subject: Mapped[str] = mapped_column(String(32), nullable=False, default="numeracy")
    teaching_language: Mapped[str] = mapped_column(
        String(16), nullable=False, default="hindi"
    )
    target_language: Mapped[str] = mapped_column(
        String(16), nullable=False, default="santali"
    )
    started_at: Mapped[str] = mapped_column(String(64), nullable=False)
    ended_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    saved_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    sync_status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="localOnly"
    )
    turns: Mapped[list] = mapped_column(JSON, nullable=False, default=list)