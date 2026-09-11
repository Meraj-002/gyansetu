"""The push-then-pull sync engine.

The Flutter app writes records locally first and marks them for the next sync
run (``pendingSync`` in ClassroomSetup / SessionSyncStatus, SupportReport
"handed to the backend once online"). This service is that backend's side:

* ``push`` upserts teacher-owned documents idempotently by client id;
* ``pull`` returns every teacher-owned document changed since a cursor;
* ``status`` reports what the server holds for the teacher.

Global catalogue rows (lessons, learning outcomes) are only ever pulled and
are never owned by a teacher.
"""

from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

import sqlalchemy as sa
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.models.assessment import Assessment
from app.models.classroom_session import ClassroomSession
from app.models.learning_outcome import LearningOutcome
from app.models.lesson import Lesson
from app.models.progress_event import ProgressEvent
from app.models.support_report import SupportReport
from app.models.teacher_record import ClassroomSetup
from app.models.worksheet import Worksheet
from app.schemas.sync import (
    SyncDocument,
    SyncDocumentOut,
    SyncPushItemResult,
    SyncPushResponse,
    SyncPullResponse,
    SyncStatusResponse,
)

_OWNED_MODELS = (
    ClassroomSetup,
    ClassroomSession,
    Assessment,
    Worksheet,
    ProgressEvent,
    SupportReport,
)

# -- helpers ---------------------------------------------------------------


def _to_snake(name: str) -> str:
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1).lower()


def _to_camel(name: str) -> str:
    parts = name.split("_")
    return parts[0] + "".join(p.title() for p in parts[1:])


def _column_names(model: type) -> set[str]:
    return set(model.__table__.columns.keys())


def _clean_values(
    model: type,
    raw: dict[str, Any],
    *,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    allowed = _column_names(model)
    values = {_to_snake(k): v for k, v in raw.items()}
    values = {k: v for k, v in values.items() if k in allowed and v is not None}
    for k, v in (extra or {}).items():
        if k in allowed and v is not None:
            values[k] = v
    _coerce_datetimes(model, values)
    return values


def _coerce_datetimes(model: type, values: dict[str, Any]) -> None:
    """The app sends ISO-8601 strings; DateTime columns need real datetimes."""
    for name, column in model.__table__.columns.items():
        if name not in values or isinstance(values[name], datetime):
            continue
        if isinstance(column.type, sa.DateTime) and isinstance(values[name], str):
            try:
                values[name] = datetime.fromisoformat(values[name].replace("Z", "+00:00"))
            except ValueError:
                pass


def _apply_existing(row: Any, values: dict[str, Any]) -> None:
    for key, value in values.items():
        setattr(row, key, value)


def row_to_camel(row: Any) -> dict[str, Any]:
    """Serialise an ORM row to a camelCase dict (the Flutter wire format)."""
    out: dict[str, Any] = {}
    for attr in sa.inspect(type(row)).mapper.column_attrs:
        value = getattr(row, attr.key)
        if isinstance(value, datetime):
            if value.tzinfo is None:
                value = value.replace(tzinfo=timezone.utc)
            value = value.isoformat().replace("+00:00", "Z")
        key = _to_camel(attr.key)
        if attr.key == "event_data":
            key = "metadata"  # Flutter's ProgressEvent field name
        out[key] = value
    return out


# -- upserters -------------------------------------------------------------


def _upsert_classroom_setup(db: Session, teacher_id: str, doc: SyncDocument) -> Any:
    data = doc.data
    given = data.get("teacherId")
    if given is not None and given != teacher_id:
        return None  # owner conflict
    values = _clean_values(ClassroomSetup, data, extra={"teacher_id": teacher_id})
    values["pending_sync"] = False
    row = db.get(ClassroomSetup, teacher_id)
    if row is None:
        row = ClassroomSetup(**values)
        db.add(row)
    else:
        _apply_existing(row, values)
    return row


def _upsert_classroom_session(db: Session, teacher_id: str, doc: SyncDocument) -> Any:
    data = dict(doc.data)
    data["session_id"] = doc.id
    values = _clean_values(ClassroomSession, data, extra={"teacher_id": teacher_id})
    values["sync_status"] = "synced"
    row = db.get(ClassroomSession, doc.id)
    if row is None:
        row = ClassroomSession(**values)
        db.add(row)
    else:
        _apply_existing(row, values)
    return row


def _upsert_assessment(db: Session, teacher_id: str, doc: SyncDocument) -> Any:
    data = dict(doc.data)
    values = _clean_values(Assessment, data, extra={"teacher_id": teacher_id})
    doc_id = values.get("id") or doc.id
    values["id"] = doc_id
    row = db.get(Assessment, doc_id)
    if row is None:
        row = Assessment(**values)
        db.add(row)
    else:
        _apply_existing(row, values)
    return row


def _upsert_worksheet(db: Session, teacher_id: str, doc: SyncDocument) -> Any:
    data = dict(doc.data)
    values = _clean_values(Worksheet, data, extra={"teacher_id": teacher_id})
    doc_id = values.get("id") or doc.id
    values["id"] = doc_id
    row = db.get(Worksheet, doc_id)
    if row is None:
        row = Worksheet(**values)
        db.add(row)
    else:
        _apply_existing(row, values)
    return row


def _upsert_progress_event(db: Session, teacher_id: str, doc: SyncDocument) -> Any:
    data = dict(doc.data)
    if "metadata" in data:
        data["event_data"] = data.pop("metadata")
    values = _clean_values(ProgressEvent, data, extra={"teacher_id": teacher_id})
    values["id"] = values.get("id") or doc.id
    row = db.get(ProgressEvent, values["id"])
    if row is None:
        row = ProgressEvent(**values)
        db.add(row)
    else:
        _apply_existing(row, values)
    return row


def _upsert_support_report(db: Session, teacher_id: str, doc: SyncDocument) -> Any:
    data = dict(doc.data)
    values = _clean_values(SupportReport, data, extra={"teacher_id": teacher_id})
    values["id"] = values.get("id") or doc.id
    row = db.get(SupportReport, values["id"])
    if row is None:
        row = SupportReport(**values)
        db.add(row)
    else:
        _apply_existing(row, values)
    return row


_UPSERTERS = {
    "classroomSetup": _upsert_classroom_setup,
    "classroomSession": _upsert_classroom_session,
    "assessmentResult": _upsert_assessment,
    "worksheet": _upsert_worksheet,
    "progressEvent": _upsert_progress_event,
    "supportReport": _upsert_support_report,
}


# -- push / pull / status ---------------------------------------------------


def push_documents(
    db: Session, teacher_id: str, documents: list[SyncDocument]
) -> SyncPushResponse:
    acknowledged: list[SyncPushItemResult] = []
    conflicts: list[SyncPushItemResult] = []
    errors: list[SyncPushItemResult] = []

    for doc in documents:
        now = datetime.now(timezone.utc)
        upsert = _UPSERTERS.get(doc.type)
        if upsert is None:
            errors.append(
                SyncPushItemResult(type=doc.type, id=doc.id, accepted=False, error="unknown_type")
            )
            continue
        try:
            with db.begin_nested():
                row = upsert(db, teacher_id, doc)
                db.flush()
            if row is None:
                conflicts.append(
                    SyncPushItemResult(type=doc.type, id=doc.id, accepted=False, error="owner_mismatch")
                )
            else:
                acknowledged.append(
                    SyncPushItemResult(type=doc.type, id=doc.id, accepted=True, accepted_at=now)
                )
        except SQLAlchemyError as exc:
            errors.append(
                SyncPushItemResult(type=doc.type, id=doc.id, accepted=False, error=_brief_error(exc))
            )
    db.commit()
    return SyncPushResponse(
        acknowledged=acknowledged,
        conflicts=conflicts,
        errors=errors,
        server_now=datetime.now(timezone.utc),
    )


def pull_documents(
    db: Session,
    teacher_id: str,
    since: datetime | None,
    *,
    include_catalog: bool,
) -> SyncPullResponse:
    owned: list[tuple[str, Any]] = []
    owned.append(("classroomSetup", db.get(ClassroomSetup, teacher_id)))
    for model in _OWNED_MODELS:
        if model is ClassroomSetup:
            continue
        for row in _changed(db, model, teacher_id=teacher_id, since=since):
            owned.append((_type_name(model), row))
    owned = [(t, r) for t, r in owned if r is not None]

    documents = _to_out_documents(owned)

    catalog: list[SyncDocumentOut] | None = None
    if include_catalog:
        catalog_docs: list[tuple[str, Any]] = [
            ("lesson", r) for r in _changed(db, Lesson, teacher_id=None, since=since)
        ]
        catalog_docs.extend(
            ("learningOutcome", r)
            for r in _changed(db, LearningOutcome, teacher_id=None, since=since)
        )
        catalog = _to_out_documents(catalog_docs)

    return SyncPullResponse(
        since=since,
        server_now=datetime.now(timezone.utc),
        documents=documents,
        catalog=catalog,
    )


def _type_name(model: type) -> str:
    return _MODEL_TO_TYPE[model]


_MODEL_TO_TYPE = {
    ClassroomSetup: "classroomSetup",
    ClassroomSession: "classroomSession",
    Assessment: "assessmentResult",
    Worksheet: "worksheet",
    ProgressEvent: "progressEvent",
    SupportReport: "supportReport",
}


def _changed(
    db: Session, model: type, *, teacher_id: str | None, since: datetime | None
) -> list[Any]:
    stmt = select(model)
    if teacher_id is not None:
        stmt = stmt.where(model.teacher_id == teacher_id)
    if since is not None:
        stmt = stmt.where(model.updated_at > since)
    return list(db.scalars(stmt).all())


def _to_out_documents(rows: list[tuple[str, Any]]) -> list[SyncDocumentOut]:
    out: list[SyncDocumentOut] = []
    for type_name, row in rows:
        values = row_to_camel(row)
        ident = (
            values.get("sessionId")
            or values.get("id")
            or values.get("teacherId")
            or ""
        )
        out.append(
            SyncDocumentOut(
                type=type_name,
                id=str(ident),
                updated_at=_as_utc(values.get("updatedAt")),
                data=values,
            )
        )
    return out


def _as_utc(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value
    if isinstance(value, str):
        try:
            return _as_utc(datetime.fromisoformat(value))
        except (ValueError, TypeError):
            return None
    return None


def sync_status(db: Session, teacher_id: str) -> SyncStatusResponse:
    counts: dict[str, int] = {"classroomSetup": 1 if db.get(ClassroomSetup, teacher_id) else 0}
    for model in _OWNED_MODELS:
        if model is ClassroomSetup:
            continue
        counts[_type_name(model)] = int(
            db.scalar(
                select(sa.func.count()).select_from(model).where(model.teacher_id == teacher_id)
            )
            or 0
        )
    return SyncStatusResponse(
        server_time=datetime.now(timezone.utc),
        counts=counts,
    )


def _brief_error(exc: Exception) -> str:
    return type(exc).__name__.lower()