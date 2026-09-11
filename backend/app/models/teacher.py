from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin


class Teacher(Base, TimestampMixin):
    """A teacher account.

    ``id`` is the server-side identifier. It is generated server-side at
    registration (a uuid hex); the offline Flutter app's TeacherAccount stores
    this same id in its ``id`` field.
    """

    __tablename__ = "teachers"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: uuid.uuid4().hex
    )
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    mobile: Mapped[str | None] = mapped_column(
        String(32), nullable=True, unique=True, index=True
    )
    mobile_last4: Mapped[str | None] = mapped_column(String(4), nullable=True)
    school_id: Mapped[str | None] = mapped_column(
        ForeignKey("schools.id", ondelete="SET NULL"), nullable=True, index=True
    )
    school_code: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    last_login_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    school: Mapped["School | None"] = relationship(  # noqa: F821
        back_populates="teachers", lazy="joined"
    )