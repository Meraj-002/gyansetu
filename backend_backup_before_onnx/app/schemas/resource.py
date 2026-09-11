from __future__ import annotations

import base64

from pydantic import Field, field_validator

from app.schemas.common import APIModel, OrmModel

RESOURCE_KINDS = ("content", "audio", "worksheet", "flashcard", "translation")


def _decode_content(value: bytes | None) -> bytes | None:
    """Decode the base64 transport encoding of the raw pack bytes.

    Content is arbitrary bytes, so the JSON body carries it base64-encoded
    (``content`` on the wire is a string); this decodes it back to the exact
    bytes that get stored, checksummed and streamed.
    """
    if value is None:
        return None
    try:
        return base64.b64decode(value, validate=True)
    except Exception as exc:  # noqa: BLE001
        raise ValueError("content must be base64-encoded") from exc


class ResourceBase(APIModel):
    kind: str = Field(pattern=r"^(content|audio|worksheet|flashcard|translation)$")
    name: str = Field(min_length=1, max_length=255)
    description: str = ""
    class_number: int = Field(ge=1, le=12)
    subject: str = ""
    version: str = Field(default="1", min_length=1, max_length=32)
    mime_type: str = Field(default="application/octet-stream", max_length=64)
    lesson_id: str | None = None


class ResourceCreate(ResourceBase):
    size_bytes: int = Field(ge=0)
    sha256: str = Field(min_length=64, max_length=64)
    content: bytes | None = None

    _decode = field_validator("content", mode="before")(staticmethod(_decode_content))


class ResourceUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    version: str | None = Field(default=None, min_length=1, max_length=32)
    mime_type: str | None = Field(default=None, max_length=64)
    lesson_id: str | None = None
    size_bytes: int | None = Field(default=None, ge=0)
    sha256: str | None = Field(default=None, min_length=64, max_length=64)
    content: bytes | None = None

    _decode = field_validator("content", mode="before")(staticmethod(_decode_content))


class ResourceOut(OrmModel):
    id: str
    kind: str
    name: str
    description: str
    class_number: int
    subject: str
    version: str
    size_bytes: int
    sha256: str
    mime_type: str
    lesson_id: str | None = None