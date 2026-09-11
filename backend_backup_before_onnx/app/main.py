"""GyanSetu backend application entrypoint.

Run locally::

    uvicorn app.main:app --reload

Docs: http://localhost:8000/docs  (OpenAPI at /openapi.json)
Health: GET /health  and  GET /api/v1/health
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

import app.models  # noqa: F401  (registers ORM models with Base.metadata)
from app.api.v1.health import router as health_router
from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.base import Base
from app.db.session import engine

settings = get_settings()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Local-development convenience only: create missing tables for SQLite.
    # Production relies on Alembic migrations against PostgreSQL.
    if settings.is_sqlite and not settings.is_production:
        Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title=settings.app_name,
    version=settings.version,
    description=(
        "Sync/content backend for GyanSetu. Implements the wire contracts the "
        "Flutter app already declares (camelCase JSON, offline-first sync)."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    return RedirectResponse(url="/docs")


app.include_router(api_router, prefix="/api/v1")
app.include_router(health_router, prefix="/health")