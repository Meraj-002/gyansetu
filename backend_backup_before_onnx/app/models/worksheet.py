from __future__ import annotations

import uuid

from sqlalchemy import JSON, Boolean, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, utcnow


class Worksheet(Base, TimestampMixin):
    """A generated or authored worksheet.

    Owned by the teacher who generated it, so it participates in sync. The
    nested question list is stored as JSON exactly as the Flutter model
    serialises it (camelCase keys).
    """

    __tablename__ = "worksheets"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: uuid.uuid4().hex
    )
    teacher_id: Mapped[str | None] = mapped_column(
        String(64), nullable=True, index=True
    )
    lesson_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    learning_outcome: Mapped[str] = mapped_column(String, nullable=False, default="")
    class_number: Mapped[int] = mapped_column(Integer, nullable=False)
    subject: Mapped[str] = mapped_column(String(32), nullable=False, default="numeracy")
    teaching_language: Mapped[str] = mapped_column(
        String(16), nullable=False, default="hindi"
    )
    target_language: Mapped[str] = mapped_column(
        String(16), nullable=False, default="santali"
    )
    difficulty: Mapped[str] = mapped_column(String(16), nullable=False, default="easy")
    questions: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    visual_examples: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    culturally_familiar_examples: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True
    )
    teacher_notes: Mapped[str | None] = mapped_column(String, nullable=True)
    variant: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    requested_question_count: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    generation_source: Mapped[str] = mapped_column(
        String(16), nullable=False, default="localOffline"
    )
    generated_at: Mapped[str] = mapped_column(
        String(64), nullable=False, default=lambda: utcnow().isoformat()
    )