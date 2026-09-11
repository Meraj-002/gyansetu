"""Teacher endpoints (the signed-in teacher's own account).

Identity is strictly self-owned: every endpoint here returns the signed-in
teacher only, never another teacher's profile.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import conflict, forbidden
from app.db.session import get_db
from app.models.teacher import Teacher
from app.schemas.teacher import TeacherOut, TeacherUpdate
from app.services import auth_service, crud

router = APIRouter()


@router.get("", response_model=list[TeacherOut])
def list_teachers(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
):
    """The profile list is the signed-in teacher's own record only."""
    return [auth_service.teacher_out(db, teacher)]


@router.get("/me", response_model=TeacherOut)
def me(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> TeacherOut:
    return auth_service.teacher_out(db, teacher)


@router.patch("/me", response_model=TeacherOut)
def update_me(
    payload: TeacherUpdate,
    teacher: Teacher = Depends(get_current_teacher),
    db: Session = Depends(get_db),
) -> TeacherOut:
    values = payload.dump_db()
    mobile = values.get("mobile")
    if mobile is not None:
        digits = "".join(c for c in mobile if c.isdigit())
        if digits.startswith("91") and len(digits) == 12:
            digits = digits[2:]
        values["mobile"] = digits or None
        values["mobile_last4"] = digits[-4:] if digits else None
        if digits:
            clash = db.scalar(select(Teacher).where(Teacher.mobile == digits))
            if clash is not None and clash.id != teacher.id:
                conflict("mobile_in_use", "Another teacher already uses that mobile.")
    updated = crud.update(db, teacher, **values)
    return auth_service.teacher_out(db, updated)


@router.get("/{teacher_id}", response_model=TeacherOut)
def get_teacher(
    teacher_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> TeacherOut:
    if teacher_id != teacher.id:
        forbidden("forbidden", "You may only read your own teacher profile.")
    return auth_service.teacher_out(db, teacher)