from __future__ import annotations

from typing import Any

from pydantic import Field

from app.schemas.common import APIModel, Timestamped


class AssessmentCreate(APIModel):
    """A finished quiz result, matching QuizResult.toJson() field-for-field."""

    id: str | None = Field(default=None, max_length=64)
    lesson_id: str = Field(min_length=1, max_length=64)
    score: int = Field(ge=0)
    total: int = Field(ge=0)
    concepts: list[dict[str, Any]] = []
    started_at: str = Field(min_length=1, max_length=64)
    finished_at: str = Field(min_length=1, max_length=64)
    # The canonical wire shape is the device's map keyed by question id
    # (QuizResult.toJson()/fromJson()): {questionId: {selectedOptionId, ...}}.
    # A legacy list here was the one place the contract disagreed with the app.
    answers: dict[str, Any] = Field(default_factory=dict)


class AssessmentOut(AssessmentCreate, Timestamped):
    id: str
    teacher_id: str | None = None