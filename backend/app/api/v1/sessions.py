"""Live-classroom session endpoints. Idempotent upsert by session id."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import bad_request, conflict, forbidden
from app.db.session import get_db
from app.models.classroom_session import ClassroomSession
from app.models.teacher import Teacher
from app.schemas.classroom_session import ClassroomSessionCreate, ClassroomSessionOut
from app.services import crud

router = APIRouter()


def _session_or_404(db: Session, session_id: str) -> ClassroomSession:
    return crud.get_or_404(db, ClassroomSession, session_id, message="session not found")


@router.get("", response_model=list[ClassroomSessionOut])
def list_sessions(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
):
    return crud.list_all(
        db,
        ClassroomSession,
        filters={"teacher_id": teacher.id},
        order_by=ClassroomSession.started_at,
    )


@router.put("/{session_id}", response_model=ClassroomSessionOut)
def upsert_session(
    session_id: str,
    payload: ClassroomSessionCreate,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> ClassroomSession:
    if payload.session_id != session_id:
        bad_request("id_mismatch", "The session id in the body must match the URL.")
    kwargs = {
        **payload.dump_db(),
        "teacher_id": teacher.id,
        "sync_status": "synced",
    }
    existing = db.get(ClassroomSession, session_id)
    if existing is None:
        try:
            return crud.create(db, ClassroomSession, **kwargs)
        except IntegrityError:
            conflict("already_exists", "A session with that id already exists.", id=session_id)
    else:
        return crud.update(db, existing, **kwargs)


@router.post("", response_model=ClassroomSessionOut, status_code=status.HTTP_201_CREATED)
def create_session(
    payload: ClassroomSessionCreate,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> ClassroomSession:
    kwargs = {**payload.dump_db(), "teacher_id": teacher.id}
    kwargs.setdefault("sync_status", "synced")
    existing = db.get(ClassroomSession, payload.session_id)
    if existing is not None:
        return crud.update(db, existing, **kwargs)
    return crud.create(db, ClassroomSession, **kwargs)


@router.get("/{session_id}", response_model=ClassroomSessionOut)
def get_session(
    session_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> ClassroomSession:
    session = _session_or_404(db, session_id)
    if session.teacher_id != teacher.id:
        forbidden("forbidden", "This session belongs to another teacher.")
    return session


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_session(
    session_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    session = _session_or_404(db, session_id)
    if session.teacher_id != teacher.id:
        forbidden("forbidden", "This session belongs to another teacher.")
    crud.delete(db, session)
    return Response(status_code=status.HTTP_204_NO_CONTENT)