"""Assessment (finished quiz result) endpoints. Teacher-owned records."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import bad_request, conflict, forbidden
from app.db.session import get_db
from app.models.assessment import Assessment
from app.models.teacher import Teacher
from app.schemas.assessment import AssessmentCreate, AssessmentOut
from app.services import crud

router = APIRouter()


def _assessment_or_404(db: Session, assessment_id: str) -> Assessment:
    return crud.get_or_404(db, Assessment, assessment_id, message="assessment not found")


@router.get("", response_model=list[AssessmentOut])
def list_assessments(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
    lesson_id: str | None = Query(default=None, alias="lessonId"),
):
    filters: dict = {"teacher_id": teacher.id}
    if lesson_id:
        filters["lesson_id"] = lesson_id
    return crud.list_all(db, Assessment, filters=filters, order_by=Assessment.updated_at)


@router.post("", response_model=AssessmentOut, status_code=status.HTTP_201_CREATED)
def create_assessment(
    payload: AssessmentCreate,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Assessment:
    values = payload.dump_db()
    doc_id = values.pop("id", None)
    kwargs = dict(values)
    if doc_id:
        kwargs["id"] = doc_id
    try:
        return crud.create(db, Assessment, teacher_id=teacher.id, **kwargs)
    except IntegrityError:
        conflict("already_exists", "An assessment with that id already exists.", id=str(doc_id))


@router.get("/{assessment_id}", response_model=AssessmentOut)
def get_assessment(
    assessment_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Assessment:
    assessment = _assessment_or_404(db, assessment_id)
    if assessment.teacher_id != teacher.id:
        forbidden("forbidden", "This assessment belongs to another teacher.")
    return assessment


@router.delete("/{assessment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_assessment(
    assessment_id: str,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    assessment = _assessment_or_404(db, assessment_id)
    if assessment.teacher_id != teacher.id:
        forbidden("forbidden", "This assessment belongs to another teacher.")
    crud.delete(db, assessment)
    return Response(status_code=status.HTTP_204_NO_CONTENT)