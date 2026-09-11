"""Translation (lesson-level) CRUD for cached lesson translations."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.db.session import get_db
from app.models.teacher import Teacher
from app.models.translation import Translation
from app.schemas.translation import TranslationCreate, TranslationOut, TranslationUpdate
from app.services import crud

router = APIRouter()


def _translation_or_404(db: Session, translation_id: str) -> Translation:
    return crud.get_or_404(db, Translation, translation_id, message="translation not found")


@router.get("", response_model=list[TranslationOut])
def list_translations(
    db: Session = Depends(get_db),
    lesson_id: str | None = Query(default=None, alias="lessonId"),
    target_language: str | None = Query(default=None, alias="targetLanguage"),
):
    filters = {"lesson_id": lesson_id, "target_language": target_language}
    return crud.list_all(db, Translation, filters=filters, order_by=Translation.updated_at)


@router.post("", response_model=TranslationOut, status_code=status.HTTP_201_CREATED)
def create_translation(
    payload: TranslationCreate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Translation:
    return crud.create(db, Translation, **payload.dump_db())


@router.get("/{translation_id}", response_model=TranslationOut)
def get_translation(translation_id: str, db: Session = Depends(get_db)) -> Translation:
    return _translation_or_404(db, translation_id)


@router.patch("/{translation_id}", response_model=TranslationOut)
def update_translation(
    translation_id: str,
    payload: TranslationUpdate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Translation:
    translation = _translation_or_404(db, translation_id)
    return crud.update(db, translation, **payload.dump_db())


@router.delete("/{translation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_translation(
    translation_id: str,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    translation = _translation_or_404(db, translation_id)
    crud.delete(db, translation)
    return Response(status_code=status.HTTP_204_NO_CONTENT)