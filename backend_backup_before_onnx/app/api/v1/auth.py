"""Auth endpoints: register, login, verify school code, me, logout."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.orm import Session

from app.api.deps import _http_bearer, get_current_teacher
from app.db.session import get_db
from app.models.teacher import Teacher
from app.schemas.auth import (
    LoginRequest,
    RecoverRequest,
    RecoverResponse,
    RegisterRequest,
    SchoolCodeInfo,
    TeacherOut,
    TokenResponse,
    VerifySchoolCodeRequest,
)
from app.services import auth_service

router = APIRouter()


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    return auth_service.register(db, payload)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    return auth_service.authenticate(db, payload)


@router.post("/verify-school-code", response_model=SchoolCodeInfo)
def verify_school_code(
    payload: VerifySchoolCodeRequest, db: Session = Depends(get_db)
) -> SchoolCodeInfo:
    school = auth_service.verify_school_code(db, payload.school_code)
    return SchoolCodeInfo(
        school_code=school.code,
        school_name=school.name,
        district_id=school.district_id,
        district_name=school.district_name,
        block_id=school.block_id,
        block_name=school.block_name,
    )


@router.post("/recover", response_model=RecoverResponse)
def request_recovery(payload: RecoverRequest, db: Session = Depends(get_db)) -> RecoverResponse:
    auth_service.request_recovery(db, payload.identifier)
    return RecoverResponse()


@router.get("/me", response_model=TeacherOut)
def me(
    db: Session = Depends(get_db),
    teacher: Teacher = Depends(get_current_teacher),
) -> TeacherOut:
    return auth_service.teacher_out(db, teacher)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(_credentials=Depends(_http_bearer)) -> Response:
    # Stateless JWTs: this build has no server-side session store to revoke.
    # The client deletes its own local session, which is what actually matters
    # for a single-device offline-first app.
    return Response(status_code=status.HTTP_204_NO_CONTENT)