from __future__ import annotations

import uuid

from sqlalchemy import Integer, LargeBinary, String
from sqlalchemy.dialects.mysql import LONGBLOB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin

#: A byte column honour-bounded on both supported engines: ``BLOB`` on SQLite
#: (no size limit) and ``LONGBLOB`` (4 GB) on MySQL, where a plain ``LargeBinary``
#: would map to the 64 KiB ``BLOB`` cap and reject real audio/language packs.
ContentBlob = LargeBinary().with_variant(LONGBLOB, "mysql")


class Resource(Base, TimestampMixin):
    """A downloadable content pack in the offline delivery pipeline.

    ``blob`` holds the actual bytes served by the ``/content`` endpoint. The
    client downloads those bytes, verifies ``sha256`` and ``size_bytes``, and
    only then reports the resource as Ready for offline use. Nothing here is
    a pointer or a promise: the checksum is computed over the exact bytes that
    are stored and served.
    """

    __tablename__ = "resources"

    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: uuid.uuid4().hex
    )
    kind: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    class_number: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    subject: Mapped[str] = mapped_column(String(32), nullable=False, default="", index=True)
    version: Mapped[str] = mapped_column(String(32), nullable=False, default="1")
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False, default="application/octet-stream")
    lesson_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    blob: Mapped[bytes | None] = mapped_column(ContentBlob, nullable=True)