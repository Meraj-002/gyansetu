"""Downloadable content-pack endpoints.

Reading (list / detail / content) is public, exactly like the lesson catalogue:
curriculum content is not teacher-owned, so a logged-out device can browse and
download it. Mutations (create / update / delete) require an authenticated
teacher, mirroring the other catalogue routes.

The ``/content`` endpoint streams the stored bytes. It reports ``Content-Length``
and an ``ETag`` equal to the sha256 so a client can verify byte-for-byte that
what it received on disk is exactly what the backend serves.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_teacher
from app.core.exceptions import not_found
from app.db.session import get_db
from app.models.resource import Resource
from app.models.teacher import Teacher
from app.schemas.resource import ResourceCreate, ResourceOut, ResourceUpdate
from app.services import crud

router = APIRouter()

_CHUNK = 64 * 1024


def _resource_or_404(db: Session, resource_id: str) -> Resource:
    return crud.get_or_404(db, Resource, resource_id, message="resource not found")


@router.get("", response_model=list[ResourceOut])
def list_resources(
    db: Session = Depends(get_db),
    kind: str | None = Query(default=None),
    class_number: int | None = Query(default=None, alias="classNumber"),
    subject: str | None = Query(default=None),
    lesson_id: str | None = Query(default=None, alias="lessonId"),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
):
    stmt = db.query(Resource)
    filters = {
        "kind": kind,
        "class_number": class_number,
        "subject": subject,
        "lesson_id": lesson_id,
    }
    for key, value in filters.items():
        if value is not None:
            stmt = stmt.filter(getattr(Resource, key) == value)
    return (
        stmt.order_by(Resource.kind, Resource.id).offset(offset).limit(limit).all()
    )


@router.get("/{resource_id}", response_model=ResourceOut)
def get_resource(resource_id: str, db: Session = Depends(get_db)) -> Resource:
    return _resource_or_404(db, resource_id)


def _iter_bytes(blob: bytes):
    """Stream a stored pack in chunks so a large pack is never re-copied whole."""
    for i in range(0, len(blob), _CHUNK):
        yield blob[i : i + _CHUNK]


@router.get("/{resource_id}/content")
def get_resource_content(resource_id: str, db: Session = Depends(get_db)) -> Response:
    resource = _resource_or_404(db, resource_id)
    if resource.blob is None:
        not_found(
            "not_found",
            "resource content is not stored on the server",
            id=str(resource_id),
        )
    return StreamingResponse(
        _iter_bytes(resource.blob),
        media_type=resource.mime_type,
        headers={
            "Content-Length": str(resource.size_bytes),
            "ETag": f'"{resource.sha256}"',
            "X-Checksum-Sha256": resource.sha256,
            "X-Resource-Version": resource.version,
        },
    )


def _store_with_content(db: Session, resource: Resource, content: bytes | None) -> Resource:
    """Persist the byte payload and its honest size/checksum together.

    ``blob`` and ``size_bytes`` always travel in the same transaction, so a row
    can never advertise a size that does not match the stored bytes.
    """
    if content is None:
        return resource
    resource.blob = content
    resource.size_bytes = len(content)
    db.add(resource)
    db.commit()
    db.refresh(resource)
    return resource


@router.post("", response_model=ResourceOut, status_code=status.HTTP_201_CREATED)
def create_resource(
    payload: ResourceCreate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Resource:
    values = payload.dump_db()
    content = values.pop("content", None)
    resource = crud.create(db, Resource, **values)
    return _store_with_content(db, resource, content)


@router.patch("/{resource_id}", response_model=ResourceOut)
def update_resource(
    resource_id: str,
    payload: ResourceUpdate,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Resource:
    resource = _resource_or_404(db, resource_id)
    values = payload.dump_db()
    content = values.pop("content", None)
    resource = crud.update(db, resource, **values)
    return _store_with_content(db, resource, content)


@router.delete("/{resource_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_resource(
    resource_id: str,
    db: Session = Depends(get_db),
    _teacher: Teacher = Depends(get_current_teacher),
) -> Response:
    resource = _resource_or_404(db, resource_id)
    crud.delete(db, resource)
    return Response(status_code=status.HTTP_204_NO_CONTENT)