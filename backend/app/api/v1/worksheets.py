"""Worksheet endpoints. Worksheets are teacher-owned (syncable) records."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import bad_request, forbidden
from app.db.session import get_db
from app.models.teacher import Teacher
from app.models.worksheet import Worksheet
from app.schemas.worksheet import WorksheetCreate, WorksheetOut
from app.services import crud

router = APIRouter()


def _worksheet_or_404(db: Session, worksheet_id: str) -> Worksheet:
    return crud.get_or_404(db, Worksheet, worksheet_id, message="worksheet not found")


@router.get("", response_model=list[WorksheetOut])
def list_worksheets(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
    lesson_id: str | None = Query(default=None, alias="lessonId"),
):
    filters: dict = {"teacher_id": teacher.id}
    if lesson_id:
        filters["lesson_id"] = lesson_id
    return crud.list_all(db, Worksheet, filters=filters, order_by=Worksheet.updated_at)


@router.post("", response_model=WorksheetOut, status_code=status.HTTP_201_CREATED)
def create_worksheet(
    payload: WorksheetCreate,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Worksheet:
    if not payload.id:
        bad_request("id_required", "Worksheets are client-generated; supply the id to upsert.")
    return crud.create(db, Worksheet, teacher_id=teacher.id, **payload.dump_db())


@router.get("/{worksheet_id}", response_model=WorksheetOut)
def get_worksheet(
    worksheet_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Worksheet:
    worksheet = _worksheet_or_404(db, worksheet_id)
    if worksheet.teacher_id != teacher.id:
        forbidden("forbidden", "This worksheet belongs to another teacher.")
    return worksheet


@router.delete("/{worksheet_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_worksheet(
    worksheet_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    worksheet = _worksheet_or_404(db, worksheet_id)
    if worksheet.teacher_id != teacher.id:
        forbidden("forbidden", "This worksheet belongs to another teacher.")
    crud.delete(db, worksheet)
    return Response(status_code=status.HTTP_204_NO_CONTENT)