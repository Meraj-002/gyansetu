"""School CRUD + lookup by code."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import conflict, not_found
from app.db.session import get_db
from app.models.school import School
from app.models.teacher import Teacher
from app.schemas.school import SchoolCreate, SchoolOut, SchoolUpdate
from app.services import crud

router = APIRouter()


def _school_or_404(db: Session, school_id: str) -> School:
    return crud.get_or_404(db, School, school_id, message="school not found")


@router.get("", response_model=list[SchoolOut])
def list_schools(db: Session = Depends(get_db)):
    return crud.list_all(db, School, order_by=School.name)


@router.get("/by-code/{code}", response_model=SchoolOut)
def get_school_by_code(code: str, db: Session = Depends(get_db)) -> School:
    school = db.scalar(select(School).where(School.code == code))
    if school is None:
        not_found("school_code_unknown", "This school code is not registered.", schoolCode=code)
    return school


@router.post("", response_model=SchoolOut, status_code=status.HTTP_201_CREATED)
def create_school(
    payload: SchoolCreate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> School:
    existing = db.scalar(select(School).where(School.code == payload.code))
    if existing is not None:
        conflict("code_in_use", "A school with that code already exists.", schoolCode=payload.code)
    return crud.create(db, School, **payload.dump_db())


@router.get("/{school_id}", response_model=SchoolOut)
def get_school(school_id: str, db: Session = Depends(get_db)) -> School:
    return _school_or_404(db, school_id)


@router.patch("/{school_id}", response_model=SchoolOut)
def update_school(
    school_id: str,
    payload: SchoolUpdate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> School:
    school = _school_or_404(db, school_id)
    return crud.update(db, school, **payload.dump_db())


@router.delete("/{school_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_school(
    school_id: str,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    school = _school_or_404(db, school_id)
    crud.delete(db, school)
    return Response(status_code=status.HTTP_204_NO_CONTENT)