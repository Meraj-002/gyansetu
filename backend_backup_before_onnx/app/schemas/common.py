"""Base schema types.

The wire format is camelCase (``displayName``, ``classNumber``) because that is
what the Flutter models' ``toJson()``/``fromJson()`` use. Python code keeps
snake_case attribute names; Pydantic maps them via an alias generator.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class APIModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        from_attributes=True,
        serialize_by_alias=True,
    )

    def dump_db(self) -> dict[str, Any]:
        """Python-side (snake_case) values for ORM construction.

        The wire format is camelCase, so plain ``model_dump()`` would return
        aliased keys that do not match ORM constructor argument names.
        """
        return self.model_dump(exclude_unset=True, by_alias=False)


class OrmModel(APIModel):
    """A schema that can be built straight from an ORM object."""

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        from_attributes=True,
        serialize_by_alias=True,
    )


class Timestamped(OrmModel):
    created_at: datetime
    updated_at: datetime


class HealthResponse(APIModel):
    status: str
    service: str
    version: str
    time: datetime