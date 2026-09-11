"""Shared FastAPI dependencies."""

from __future__ import annotations

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.exceptions import unauthorized
from app.core.security import decode_access_token
from app.db.session import get_db
from app.models.teacher import Teacher

_http_bearer = HTTPBearer(auto_error=True, description="Access token from /auth/login")


def get_current_teacher(
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials = Depends(_http_bearer),
) -> Teacher:
    try:
        payload = decode_access_token(credentials.credentials)
    except jwt.PyJWTError:
        unauthorized("invalid_token", "The access token is invalid or has expired.")

    subject = payload.get("sub")
    teacher = db.get(Teacher, subject) if subject else None
    if teacher is None:
        unauthorized("teacher_not_found", "The account for this token no longer exists.")

    return teacher