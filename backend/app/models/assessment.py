from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import JSON, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, utcnow


class Assessment(Base, TimestampMixin):
    """A finished QuizResult pushed from the app.

    Nested structures (concepts, answers) are stored as JSON using the same
    keys the Flutter models serialise with.
    """

    __tablename__ = "assessments"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: uuid.uuid4().hex
    )
    teacher_id: Mapped[str | None] = mapped_column(
        String(64), nullable=True, index=True
    )
    lesson_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    score: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    concepts: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    started_at: Mapped[str] = mapped_column(String(64), nullable=False)
    finished_at: Mapped[str] = mapped_column(String(64), nullable=False)
    # Keyed by question id: the exact shape QuizResult.toJson() produces.
    answers: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False, default=dict)