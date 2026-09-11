"""Password hashing and JWT utilities for the backend.

Passwords are hashed with scrypt-free, dependency-free PBKDF2-HMAC-SHA256
(same primitive the offline Flutter app uses for its local PIN verifier).
Stored form: ``pbkdf2_sha256$<iterations>$<salt_b64>$<hash_b64>``.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt

from app.core.config import get_settings


def _b64encode(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def _b64decode(value: str) -> bytes:
    return base64.b64decode(value.encode("ascii"))


def hash_password(password: str, *, iterations: int | None = None) -> str:
    """Return a portable PBKDF2-HMAC-SHA256 hash of ``password``."""
    settings = get_settings()
    salt = os.urandom(16)
    iterations = iterations or settings.password_hash_iterations
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, iterations
    )
    return "$".join(
        [
            settings.password_hash_algorithm,
            str(iterations),
            _b64encode(salt),
            _b64encode(digest),
        ]
    )


def verify_password(password: str, stored: str) -> bool:
    """Constant-time check of ``password`` against a stored hash string.

    Returns False (never raises) for malformed stored values.
    """
    try:
        algorithm, iterations_str, salt_b64, hash_b64 = stored.split("$")
        iterations = int(iterations_str)
        salt = _b64decode(salt_b64)
        expected = _b64decode(hash_b64)
    except (ValueError, TypeError):
        return False

    if algorithm != get_settings().password_hash_algorithm:
        return False

    actual = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, iterations
    )
    return hmac.compare_digest(actual, expected)


def create_access_token(subject: str, *, extra: dict[str, Any] | None = None) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": subject,
        "iat": now,
        "nbf": now,
        "exp": now + timedelta(minutes=settings.access_token_expires_minutes),
        "iss": settings.token_issuer,
        "token_type": "access",
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)


def decode_access_token(token: str) -> dict[str, Any]:
    """Decode and validate a token. Raises jwt.InvalidTokenError on failure."""
    settings = get_settings()
    return jwt.decode(
        token,
        settings.secret_key,
        algorithms=[settings.algorithm],
        issuer=settings.token_issuer,
    )