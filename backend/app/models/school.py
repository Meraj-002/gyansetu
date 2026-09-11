from __future__ import annotations

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, utcnow


class School(Base, TimestampMixin):
    """A school. Globally shared catalogue data, not owned by one teacher."""

    __tablename__ = "schools"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: _new_id()
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    code: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )
    district_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    district_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    block_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    block_name: Mapped[str | None] = mapped_column(String(255), nullable=True)

    teachers: Mapped[list["Teacher"]] = relationship(  # noqa: F821
        back_populates="school", passive_deletes=True
    )


def _new_id() -> str:
    import uuid

    return uuid.uuid4().hex