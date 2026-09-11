"""Small helpers that raise FastAPI HTTPExceptions with a structured body.

The error body is always::

    {"detail": {"code": "school_code_in_use", "message": "..."}}

``code`` is a stable machine-readable slug; ``message`` is human-readable.
"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

DETAIL_ROOT = "detail"


def _raise(status_code: int, code: str, message: str, **extra: Any) -> None:
    detail: dict[str, Any] = {"code": code, "message": message}
    detail.update(extra)
    raise HTTPException(status_code=status_code, detail=detail)


def bad_request(code: str, message: str, **extra: Any) -> None:
    _raise(status.HTTP_400_BAD_REQUEST, code, message, **extra)


def unauthorized(code: str, message: str, **extra: Any) -> None:
    _raise(status.HTTP_401_UNAUTHORIZED, code, message, **extra)


def forbidden(code: str, message: str, **extra: Any) -> None:
    _raise(status.HTTP_403_FORBIDDEN, code, message, **extra)


def not_found(code: str, message: str, **extra: Any) -> None:
    _raise(status.HTTP_404_NOT_FOUND, code, message, **extra)


def conflict(code: str, message: str, **extra: Any) -> None:
    _raise(status.HTTP_409_CONFLICT, code, message, **extra)


def server_error(code: str, message: str, **extra: Any) -> None:
    _raise(status.HTTP_500_INTERNAL_SERVER_ERROR, code, message, **extra)