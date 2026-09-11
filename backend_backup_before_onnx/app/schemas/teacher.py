from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.schemas.common import APIModel, OrmModel


class TeacherUpdate(APIModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=255)
    mobile: str | None = Field(default=None, max_length=32)


class TeacherOut(OrmModel):
    """The teacher's canonical identity: account + school + classroom.

    District/block come from the linked School record; the classroom fields
    come from the teacher's ClassroomSetup row (null until the device pushes
    a completed setup via sync). The app's offline account stays small; the
    richer fields here hydrate the cached profile once it is reachable.
    """

    id: str
    display_name: str
    school_id: str | None = None
    school_name: str | None = None
    school_code: str | None = None
    district_id: str | None = None
    district_name: str | None = None
    block_id: str | None = None
    block_name: str | None = None
    class_level: int | None = None
    subjects: list[str] = Field(default_factory=list)
    teaching_medium: str | None = None
    target_language: str | None = None
    setup_completed: bool = False
    mobile_last4: str | None = None
    has_mobile: bool = False
    created_at: datetime
    updated_at: datetime