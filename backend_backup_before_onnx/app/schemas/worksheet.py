from __future__ import annotations

from typing import Any

from pydantic import Field

from app.schemas.common import APIModel, Timestamped


class WorksheetCreate(APIModel):
    id: str | None = Field(default=None, max_length=64)
    lesson_id: str = Field(min_length=1, max_length=64)
    title: str = Field(min_length=1, max_length=255)
    learning_outcome: str = ""
    class_number: int = Field(ge=1, le=12)
    subject: str = Field(default="numeracy", max_length=32)
    teaching_language: str = Field(default="hindi", max_length=16)
    target_language: str = Field(default="santali", max_length=16)
    difficulty: str = Field(default="easy", max_length=16)
    questions: list[dict[str, Any]] = []
    visual_examples: list[dict[str, Any]] = []
    culturally_familiar_examples: bool = True
    teacher_notes: str | None = None
    variant: int = 0
    requested_question_count: int | None = None
    generation_source: str = Field(default="localOffline", max_length=16)
    generated_at: str | None = None


class WorksheetOut(WorksheetCreate, Timestamped):
    id: str
    teacher_id: str | None = None