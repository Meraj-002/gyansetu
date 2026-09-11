from __future__ import annotations

import uuid

from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class LearningOutcome(Base, TimestampMixin):
    """One stated learning outcome for a class level and subject."""

    __tablename__ = "learning_outcomes"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: uuid.uuid4().hex
    )
    code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    text: Mapped[str] = mapped_column(String, nullable=False)
    class_number: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    subject: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    language: Mapped[str | None] = mapped_column(String(16), nullable=True)
    curriculum_reference: Mapped[str | None] = mapped_column(String(255), nullable=True)