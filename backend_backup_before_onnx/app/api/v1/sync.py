"""Sync endpoints: the push-then-pull bridge for the offline-first app."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.db.session import get_db
from app.models.teacher import Teacher
from app.schemas.sync import (
    SyncPullRequest,
    SyncPullResponse,
    SyncPushRequest,
    SyncPushResponse,
    SyncStatusResponse,
)
from app.services import sync_service

router = APIRouter()


@router.get("/status", response_model=SyncStatusResponse)
def sync_status(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> SyncStatusResponse:
    return sync_service.sync_status(db, teacher.id)


@router.post("/push", response_model=SyncPushResponse)
def push(
    payload: SyncPushRequest,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> SyncPushResponse:
    return sync_service.push_documents(db, teacher.id, payload.documents)


@router.post("/pull", response_model=SyncPullResponse)
def pull(
    payload: SyncPullRequest,
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> SyncPullResponse:
    return sync_service.pull_documents(
        db, teacher.id, payload.since, include_catalog=payload.include_catalog
    )