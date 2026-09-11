from __future__ import annotations

from typing import Any

from pydantic import Field

from app.schemas.common import APIModel, Timestamped


class ClassroomSessionCreate(APIModel):
    """A saved live-classroom session, shape-compatible with the app model."""

    session_id: str = Field(min_length=1, max_length=64)
    lesson_id: str = Field(min_length=1, max_length=64)
    lesson_title: str = ""
    class_number: int = Field(ge=1, le=12)
    subject: str = Field(default="numeracy", max_length=32)
    teaching_language: str = Field(default="hindi", max_length=16)
    target_language: str = Field(default="santali", max_length=16)
    started_at: str = Field(min_length=1, max_length=64)
    ended_at: str | None = None
    completed: bool = False
    saved_at: str | None = None
    sync_status: str = Field(default="localOnly", max_length=16)
    turns: list[dict[str, Any]] = []


class ClassroomSessionOut(ClassroomSessionCreate, Timestamped):
    teacher_id: str | None = None