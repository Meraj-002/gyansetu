"""Learning outcomes CRUD."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.db.session import get_db
from app.models.learning_outcome import LearningOutcome
from app.models.teacher import Teacher
from app.schemas.learning_outcome import (
    LearningOutcomeCreate,
    LearningOutcomeOut,
    LearningOutcomeUpdate,
)
from app.services import crud

router = APIRouter()


def _outcome_or_404(db: Session, outcome_id: str) -> LearningOutcome:
    return crud.get_or_404(db, LearningOutcome, outcome_id, message="learning outcome not found")


@router.get("", response_model=list[LearningOutcomeOut])
def list_learning_outcomes(
    db: Session = Depends(get_db),
    subject: str | None = Query(default=None),
    class_number: int | None = Query(default=None, alias="classNumber"),
):
    filters = {"subject": subject, "class_number": class_number}
    return crud.list_all(
        db, LearningOutcome, filters=filters, order_by=LearningOutcome.class_number
    )


@router.post("", response_model=LearningOutcomeOut, status_code=status.HTTP_201_CREATED)
def create_learning_outcome(
    payload: LearningOutcomeCreate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> LearningOutcome:
    return crud.create(db, LearningOutcome, **payload.dump_db())


@router.get("/{outcome_id}", response_model=LearningOutcomeOut)
def get_learning_outcome(outcome_id: str, db: Session = Depends(get_db)) -> LearningOutcome:
    return _outcome_or_404(db, outcome_id)


@router.patch("/{outcome_id}", response_model=LearningOutcomeOut)
def update_learning_outcome(
    outcome_id: str,
    payload: LearningOutcomeUpdate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> LearningOutcome:
    outcome = _outcome_or_404(db, outcome_id)
    return crud.update(db, outcome, **payload.dump_db())


@router.delete("/{outcome_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_learning_outcome(
    outcome_id: str,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    outcome = _outcome_or_404(db, outcome_id)
    crud.delete(db, outcome)
    return Response(status_code=status.HTTP_204_NO_CONTENT)