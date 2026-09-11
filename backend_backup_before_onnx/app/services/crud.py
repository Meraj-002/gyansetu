"""Small generic database helpers shared by the route handlers."""

from __future__ import annotations

from typing import Any, TypeVar

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import not_found

ModelT = TypeVar("ModelT")

Msg = str | None


def get_or_404(db: Session, model: type, id: Any, *, message: Msg = None) -> Any:
    obj = db.get(model, id)
    if obj is None:
        not_found(
            "not_found",
            message or f"{model.__tablename__}.not_found",
            id=str(id),
        )
    return obj


def list_all(
    db: Session,
    model: type,
    *,
    filters: dict[str, Any] | None = None,
    order_by: Any = None,
    limit: int | None = None,
) -> list:
    stmt = select(model)
    for key, value in (filters or {}).items():
        if value is not None:
            stmt = stmt.filter_by(**{key: value})
    if order_by is not None:
        stmt = stmt.order_by(order_by)
    if limit is not None:
        stmt = stmt.limit(limit)
    return list(db.scalars(stmt).all())


def create(db: Session, model: type, **values: Any) -> Any:
    obj = model(**values)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


def update(db: Session, obj: Any, **values: Any) -> Any:
    for key, value in values.items():
        if value is not None:
            setattr(obj, key, value)
    db.commit()
    db.refresh(obj)
    return obj


def delete(db: Session, obj: Any) -> None:
    db.delete(obj)
    db.commit()


def count(db: Session, model: type, *, filters: dict[str, Any] | None = None) -> int:
    stmt = select(func.count()).select_from(model)
    for key, value in (filters or {}).items():
        if value is not None:
            stmt = stmt.filter_by(**{key: value})
    return int(db.scalar(stmt) or 0)