from __future__ import annotations

from pydantic import Field

from app.schemas.common import APIModel, Timestamped


class SchoolBase(APIModel):
    name: str = Field(min_length=1, max_length=255)
    code: str = Field(min_length=1, max_length=64)
    district_id: str | None = Field(default=None, max_length=64)
    district_name: str | None = Field(default=None, max_length=255)
    block_id: str | None = Field(default=None, max_length=64)
    block_name: str | None = Field(default=None, max_length=255)


class SchoolCreate(SchoolBase):
    pass


class SchoolUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    district_id: str | None = Field(default=None, max_length=64)
    district_name: str | None = Field(default=None, max_length=255)
    block_id: str | None = Field(default=None, max_length=64)
    block_name: str | None = Field(default=None, max_length=255)


class SchoolOut(Timestamped):
    id: str
    name: str
    code: str
    district_id: str | None = None
    district_name: str | None = None
    block_id: str | None = None
    block_name: str | None = None