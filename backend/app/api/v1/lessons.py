"""Lesson catalogue CRUD."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.db.session import get_db
from app.models.lesson import Lesson
from app.models.teacher import Teacher
from app.schemas.lesson import LessonCreate, LessonOut, LessonUpdate
from app.services import crud

router = APIRouter()


def _lesson_or_404(db: Session, lesson_id: str) -> Lesson:
    return crud.get_or_404(db, Lesson, lesson_id, message="lesson not found")


@router.get("", response_model=list[LessonOut])
def list_lessons(
    db: Session = Depends(get_db),
    subject: str | None = Query(default=None),
    class_number: int | None = Query(default=None, alias="classNumber"),
):
    filters = {"subject": subject, "class_number": class_number}
    return crud.list_all(db, Lesson, filters=filters, order_by=Lesson.lesson_order)


@router.get("/{lesson_id}", response_model=LessonOut)
def get_lesson(lesson_id: str, db: Session = Depends(get_db)) -> Lesson:
    return _lesson_or_404(db, lesson_id)


@router.post("", response_model=LessonOut, status_code=status.HTTP_201_CREATED)
def create_lesson(
    payload: LessonCreate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Lesson:
    return crud.create(db, Lesson, **payload.dump_db())


@router.patch("/{lesson_id}", response_model=LessonOut)
def update_lesson(
    lesson_id: str,
    payload: LessonUpdate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Lesson:
    lesson = _lesson_or_404(db, lesson_id)
    return crud.update(db, lesson, **payload.dump_db())


@router.delete("/{lesson_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_lesson(
    lesson_id: str,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    lesson = _lesson_or_404(db, lesson_id)
    crud.delete(db, lesson)
    return Response(status_code=status.HTTP_204_NO_CONTENT)