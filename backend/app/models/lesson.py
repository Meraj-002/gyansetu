from __future__ import annotations

import uuid

from sqlalchemy import JSON, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class Lesson(Base, TimestampMixin):
    """A lesson catalogue entry.

    Mirrors the Flutter ``Lesson`` model's ``toJson()`` so a remote repository
    can round-trip the same payload. Enum-like strings (``subject``) follow the
    Dart enum ``.name`` convention: ``foundationalLiteracy`` or ``numeracy``.
    """

    __tablename__ = "lessons"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: uuid.uuid4().hex
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    subject: Mapped[str] = mapped_column(
        String(32), nullable=False, index=True, default="foundationalLiteracy"
    )
    class_number: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    learning_outcome: Mapped[str] = mapped_column(String, nullable=False, default="")
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
    lesson_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    thumbnail_asset: Mapped[str | None] = mapped_column(String(255), nullable=True)
    resource_ids: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    concepts: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    audio_resource_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    worksheet_resource_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    flashcard_resource_id: Mapped[str | None] = mapped_column(String(255), nullable=True)