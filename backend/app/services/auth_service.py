"""Authentication flows: registration, login, school-code verification."""

from __future__ import annotations

import uuid

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.exceptions import bad_request, conflict, not_found, unauthorized
from app.core.security import create_access_token, hash_password, verify_password
from app.db.base import utcnow
from app.models.school import School
from app.models.teacher import Teacher
from app.models.teacher_record import ClassroomSetup
from app.schemas.auth import (
    LoginRequest,
    RegisterRequest,
    TeacherOut,
    TokenResponse,
)
from app.services import crud


def teacher_out(db: Session, teacher: Teacher) -> TeacherOut:
    """Serialise the canonical identity: account + school + classroom.

    School location comes from the joined ``teacher.school``; classroom
    fields come from the teacher's single ClassroomSetup row when present.
    """
    school = teacher.school
    classroom = db.scalar(
        select(ClassroomSetup).where(ClassroomSetup.teacher_id == teacher.id)
    )
    # The School record is the source of truth when the teacher belongs to one;
    # otherwise the classroom's own school name stands in for it.
    if school is not None:
        school_name = school.name
    elif classroom is not None and classroom.school_name:
        school_name = classroom.school_name
    else:
        school_name = teacher.school_code or ""
    return TeacherOut(
        id=teacher.id,
        display_name=teacher.display_name,
        school_id=teacher.school_id,
        school_name=school_name,
        school_code=teacher.school_code,
        district_id=school.district_id if school is not None else None,
        district_name=school.district_name if school is not None else None,
        block_id=school.block_id if school is not None else None,
        block_name=school.block_name if school is not None else None,
        class_level=classroom.class_level if classroom is not None else None,
        subjects=list(classroom.subjects) if classroom is not None else [],
        teaching_medium=classroom.teaching_medium if classroom is not None else None,
        target_language=classroom.target_language if classroom is not None else None,
        setup_completed=classroom.setup_completed if classroom is not None else False,
        mobile_last4=teacher.mobile_last4,
        has_mobile=bool(teacher.mobile),
        created_at=teacher.created_at,
        updated_at=teacher.updated_at,
    )


def _resolve_school(db: Session, code: str, school_name: str | None) -> School:
    school = db.scalar(select(School).where(School.code == code))
    if school is not None:
        return school
    if not school_name:
        bad_request(
            "unknown_school_code",
            "The school code is not registered; provide schoolName to create it.",
            schoolCode=code,
        )
    return crud.create(db, School, name=school_name, code=code)


def register(db: Session, payload: RegisterRequest) -> TokenResponse:
    mobile = _normalize_mobile(payload.mobile)
    if mobile is not None:
        existing = db.scalar(select(Teacher).where(Teacher.mobile == mobile))
        if existing is not None:
            conflict("mobile_in_use", "A teacher with that mobile is already registered.")

    school: School | None = None
    school_code: str | None = None
    if payload.school_code:
        school = _resolve_school(db, payload.school_code, payload.school_name)
        school_code = school.code

    teacher = crud.create(
        db,
        Teacher,
        id=uuid.uuid4().hex,
        display_name=payload.display_name,
        mobile=mobile,
        mobile_last4=(mobile[-4:] if mobile else None),
        school_id=school.id if school else None,
        school_code=school_code,
        password_hash=hash_password(payload.password),
    )
    if school is not None:
        teacher.school = school
    return _token_response(db, teacher, school)


def authenticate(db: Session, payload: LoginRequest) -> TokenResponse:
    teacher = db.scalar(
        select(Teacher).where(
            or_(Teacher.mobile == payload.identifier, Teacher.id == payload.identifier)
        )
    )
    if teacher is None or not verify_password(payload.password, teacher.password_hash):
        unauthorized("invalid_credentials", "Identifier or password is incorrect.")

    if payload.school_code and teacher.school_code != payload.school_code:
        unauthorized(
            "invalid_credentials",
            "The identifier or password does not match this school code.",
        )

    teacher.last_login_at = utcnow()
    db.commit()
    db.refresh(teacher)
    return _token_response(db, teacher, teacher.school)


def verify_school_code(db: Session, code: str) -> School:
    school = db.scalar(select(School).where(School.code == code))
    if school is None:
        not_found("school_code_unknown", "This school code is not registered.", schoolCode=code)
    return school


def request_recovery(db: Session, identifier: str) -> None:
    # Nothing is dispatched in this build: there is no email/SMS channel by
    # design. The record of a PIN-recovery request is kept honest and minimal.
    db.rollback()


def _token_response(db: Session, teacher: Teacher, school: School | None) -> TokenResponse:
    settings = get_settings()
    token = create_access_token(teacher.id)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in=settings.access_token_expires_minutes * 60,
        account=teacher_out(db, teacher),
        school=school,
    )


def _normalize_mobile(mobile: str | None) -> str | None:
    """Keep only digits; strip common prefixes like +91."""
    if mobile is None:
        return None
    digits = "".join(ch for ch in mobile if ch.isdigit())
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    return digits or None