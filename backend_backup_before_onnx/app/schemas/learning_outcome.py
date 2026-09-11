from __future__ import annotations

from pydantic import Field

from app.schemas.common import APIModel, Timestamped


class LearningOutcomeBase(APIModel):
    text: str = Field(min_length=1)
    class_number: int = Field(ge=1, le=12)
    subject: str = Field(
        default="foundationalLiteracy",
        pattern=r"^(foundationalLiteracy|numeracy)$",
    )
    code: str | None = None
    language: str | None = None
    curriculum_reference: str | None = None


class LearningOutcomeCreate(LearningOutcomeBase):
    pass


class LearningOutcomeUpdate(APIModel):
    text: str | None = Field(default=None, min_length=1)
    class_number: int | None = Field(default=None, ge=1, le=12)
    subject: str | None = Field(
        default=None, pattern=r"^(foundationalLiteracy|numeracy)$"
    )
    code: str | None = None
    language: str | None = None
    curriculum_reference: str | None = None


class LearningOutcomeOut(LearningOutcomeBase, Timestamped):
    id: str