from __future__ import annotations

from sqlalchemy import JSON, Boolean, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class ClassroomSetup(Base, TimestampMixin):
    """The teacher's classroom configuration (one row per teacher).

    Mirrors ClassroomSetup.toJson(). ``teacher_id`` is the primary key naturally,
    matching how the app stores one setup per teacher.
    """

    __tablename__ = "classroom_setup"

    teacher_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    school_name: Mapped[str] = mapped_column(String(255), nullable=False)
    district_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    district_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    block_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    block_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    teaching_medium: Mapped[str] = mapped_column(
        String(16), nullable=False, default="hindi"
    )
    target_language: Mapped[str] = mapped_column(
        String(16), nullable=False, default="santali"
    )
    class_level: Mapped[int] = mapped_column(Integer, nullable=False)
    subjects: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    setup_completed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    setup_completed_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    pending_sync: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)