from __future__ import annotations

from pydantic import Field

from app.schemas.common import APIModel
from app.schemas.school import SchoolOut
from app.schemas.teacher import TeacherOut


class RegisterRequest(APIModel):
    display_name: str = Field(min_length=1, max_length=255)
    mobile: str | None = Field(default=None, max_length=32)
    password: str = Field(min_length=4, max_length=128)
    school_code: str | None = Field(default=None, max_length=64)
    school_name: str | None = Field(default=None, max_length=255)
    device_id: str | None = Field(default=None, max_length=128)


class LoginRequest(APIModel):
    """Identifier is a mobile number or teacher id."""

    identifier: str = Field(min_length=1, max_length=255)
    password: str = Field(min_length=1, max_length=128)
    school_code: str | None = Field(default=None, max_length=64)
    device_id: str | None = Field(default=None, max_length=128)


class VerifySchoolCodeRequest(APIModel):
    school_code: str = Field(min_length=1, max_length=64)


class RecoverRequest(APIModel):
    identifier: str = Field(min_length=1, max_length=255)


class TokenResponse(APIModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    account: TeacherOut
    school: SchoolOut | None = None


class SchoolCodeInfo(APIModel):
    school_code: str
    school_name: str
    district_id: str | None = None
    district_name: str | None = None
    block_id: str | None = None
    block_name: str | None = None


class RecoverResponse(APIModel):
    status: str = "accepted"
    message: str = (
        "PIN recovery requests are recorded and acknowledged; no email or SMS "
        "is sent in this build."
    )