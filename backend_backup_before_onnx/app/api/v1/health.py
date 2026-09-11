"""Health checks: lightweight liveness probe plus an optional DB probe."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import get_db

router = APIRouter()


def _health_body() -> dict:
    settings = get_settings()
    return {
        "status": "ok",
        "service": settings.app_name,
        "version": settings.version,
        "time": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }


@router.get("")
def health() -> dict:
    return _health_body()


@router.get("/db")
def health_db(db: Session = Depends(get_db)) -> JSONResponse:
    try:
        db.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 - a failed probe must surface as 503
        return JSONResponse(
            status_code=503,
            content={"status": "error", "message": "database unreachable"},
        )
    return JSONResponse(content={**_health_body(), "database": "reachable"})