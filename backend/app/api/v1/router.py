"""Aggregates every /api/v1 route group."""

from fastapi import APIRouter

from app.api.v1 import (
    assessments,
    auth,
    health,
    learning_outcomes,
    lessons,
    progress,
    resources,
    schools,
    sessions,
    sync,
    teachers,
    translate,
    translation_route,
    translations,
    worksheets,
)

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(teachers.router, prefix="/teachers", tags=["teachers"])
api_router.include_router(schools.router, prefix="/schools", tags=["schools"])
api_router.include_router(lessons.router, prefix="/lessons", tags=["lessons"])
api_router.include_router(resources.router, prefix="/resources", tags=["resources"])
api_router.include_router(
    learning_outcomes.router, prefix="/learning-outcomes", tags=["learning-outcomes"]
)
api_router.include_router(translations.router, prefix="/translations", tags=["translations"])
api_router.include_router(translate.router, prefix="/translate", tags=["translate"])
api_router.include_router(
    translation_route.router, prefix="/translation", tags=["translation"]
)
api_router.include_router(worksheets.router, prefix="/worksheets", tags=["worksheets"])
api_router.include_router(assessments.router, prefix="/assessments", tags=["assessments"])
api_router.include_router(sessions.router, prefix="/sessions", tags=["sessions"])
api_router.include_router(progress.router, prefix="/progress", tags=["progress"])
api_router.include_router(sync.router, prefix="/sync", tags=["sync"])
api_router.include_router(health.router, prefix="/health", tags=["health"])