"""Progress event endpoints (thin read/write over the sync store)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import conflict
from app.db.session import get_db
from app.models.progress_event import ProgressEvent
from app.models.teacher import Teacher
from app.schemas.progress import ProgressEventOut, ProgressEventUpsert
from app.services import crud

router = APIRouter()


def _iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


def _to_out(event: ProgressEvent) -> dict[str, Any]:
    return {
        "id": event.id,
        "type": event.type,
        "occurredAt": event.occurred_at,
        "lessonId": event.lesson_id,
        "metadata": event.event_data,
        "createdAt": _iso(event.created_at),
        "updatedAt": _iso(event.updated_at),
    }


@router.get("", response_model=list[ProgressEventOut])
def list_progress(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
    limit: int | None = Query(default=None, ge=1, le=2000),
    event_type: str | None = Query(default=None, alias="type"),
):
    filters: dict = {"teacher_id": teacher.id}
    if event_type:
        filters["type"] = event_type
    events = crud.list_all(
        db, ProgressEvent, filters=filters, order_by=ProgressEvent.occurred_at.desc()
    )
    if limit is not None:
        events = events[:limit]
    return [_to_out(e) for e in events]


@router.post("", response_model=ProgressEventOut, status_code=201)
def upsert_progress(
    payload: ProgressEventUpsert,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> dict[str, Any]:
    kwargs = {**payload.dump_db(), "teacher_id": teacher.id}
    event_id = kwargs.get("id") or payload.id
    kwargs["id"] = event_id
    if "metadata" in kwargs:
        kwargs["event_data"] = kwargs.pop("metadata")
    existing = db.get(ProgressEvent, event_id)
    try:
        if existing is not None:
            return _to_out(crud.update(db, existing, **kwargs))
        return _to_out(crud.create(db, ProgressEvent, **kwargs))
    except IntegrityError:
        conflict("already_exists", "A progress event with that id already exists.", id=event_id)