from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import Field

from app.schemas.common import APIModel


class ProgressEventUpsert(APIModel):
    id: str = Field(min_length=1, max_length=64)
    type: str = Field(min_length=1, max_length=32)
    occurred_at: str = Field(min_length=1, max_length=64)
    lesson_id: str | None = Field(default=None, max_length=64)
    metadata: dict[str, Any] = Field(default_factory=dict)


class ProgressEventOut(APIModel):
    """Wire output. ``metadata`` is stored as ``event_data`` in the ORM."""

    id: str
    type: str
    occurred_at: str
    lesson_id: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime