from __future__ import annotations

from sqlalchemy import Boolean, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class Translation(Base, TimestampMixin):
    """A cached lesson translation for one language pair.

    Matches the Flutter ``LessonTranslation`` shape (camelCase on the wire)
    with strings for the enum-like provenance field
    (``authored`` / ``aiAdapted`` / ``aiGenerated``).
    """

    __tablename__ = "translations"

    # Client key convention is "$lessonId#$targetLocale"; also accepted.
    id: Mapped[str] = mapped_column(
        String(128), primary_key=True, default=lambda: _translation_id()
    )
    lesson_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    source_medium: Mapped[str] = mapped_column(String(16), nullable=False)
    target_language: Mapped[str] = mapped_column(String(16), nullable=False)
    text: Mapped[str] = mapped_column(String, nullable=False)
    spoken_text: Mapped[str | None] = mapped_column(String, nullable=True)
    provenance: Mapped[str] = mapped_column(
        String(32), nullable=False, default="authored"
    )
    reviewed_by_speaker: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)


def _translation_id() -> str:
    import uuid

    return uuid.uuid4().hex