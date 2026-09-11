from __future__ import annotations

from pydantic import Field

from app.schemas.common import APIModel, Timestamped

LESSON_SUBJECTS = ("foundationalLiteracy", "numeracy")


class LessonBase(APIModel):
    title: str = Field(min_length=1, max_length=255)
    description: str = ""
    subject: str = Field(default="foundationalLiteracy", pattern=r"^(foundationalLiteracy|numeracy)$")
    class_number: int = Field(ge=1, le=12)
    learning_outcome: str = ""
    duration_minutes: int = Field(default=30, ge=1)
    lesson_order: int = 0
    thumbnail_asset: str | None = None
    resource_ids: list[str] = []
    concepts: list[str] = []
    audio_resource_id: str | None = None
    worksheet_resource_id: str | None = None
    flashcard_resource_id: str | None = None


class LessonCreate(LessonBase):
    pass


class LessonUpdate(APIModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    subject: str | None = Field(
        default=None, pattern=r"^(foundationalLiteracy|numeracy)$"
    )
    class_number: int | None = Field(default=None, ge=1, le=12)
    learning_outcome: str | None = None
    duration_minutes: int | None = Field(default=None, ge=1)
    lesson_order: int | None = None
    thumbnail_asset: str | None = None
    resource_ids: list[str] | None = None
    concepts: list[str] | None = None
    audio_resource_id: str | None = None
    worksheet_resource_id: str | None = None
    flashcard_resource_id: str | None = None


class LessonOut(LessonBase, Timestamped):
    id: str