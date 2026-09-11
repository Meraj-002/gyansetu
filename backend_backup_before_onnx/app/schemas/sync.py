from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import APIModel

# The document types the device may push (each is teacher-owned and upserted).
SyncDocumentType = Literal[
    "classroomSetup",
    "classroomSession",
    "assessmentResult",
    "worksheet",
    "progressEvent",
    "supportReport",
]


class SyncDocument(APIModel):
    type: SyncDocumentType
    id: str = Field(min_length=1, max_length=128)
    data: dict[str, Any] = Field(default_factory=dict)


class SyncPushRequest(APIModel):
    device_id: str | None = None
    documents: list[SyncDocument] = Field(default_factory=list)


class SyncPushItemResult(APIModel):
    type: str
    id: str
    accepted: bool
    accepted_at: datetime | None = None
    error: str | None = None


class SyncPushResponse(APIModel):
    acknowledged: list[SyncPushItemResult] = Field(default_factory=list)
    conflicts: list[SyncPushItemResult] = Field(default_factory=list)
    errors: list[SyncPushItemResult] = Field(default_factory=list)
    server_now: datetime


class SyncPullRequest(APIModel):
    since: datetime | None = None
    device_id: str | None = None
    include_catalog: bool = False


class SyncDocumentOut(APIModel):
    type: str
    id: str
    updated_at: datetime | None = None
    data: dict[str, Any] = Field(default_factory=dict)


class SyncPullResponse(APIModel):
    since: datetime | None = None
    server_now: datetime
    documents: list[SyncDocumentOut] = Field(default_factory=list)
    catalog: list[SyncDocumentOut] | None = None


class SyncStatusResponse(APIModel):
    status: Literal["ok"] = "ok"
    server_time: datetime
    counts: dict[str, int] = Field(default_factory=dict)