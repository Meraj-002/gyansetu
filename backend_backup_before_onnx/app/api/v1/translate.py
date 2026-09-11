"""Free-text translation (`POST /api/v1/translate`).

The online half of the offline-first translation orchestrator. Shares the
camelCase wire format with everything else and requires the same teacher token
as the rest of the v1 API.

The provider is selected by ``GYANSETU_TRANSLATION_PROVIDER`` (see
`app.services.translation_provider`). The IndicTrans2 provider loads lazily on a
request — never at app import/startup — and a model that cannot be produced
surfaces as an explicit ``model_unavailable`` 503 state instead of an invented
translation.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import JSONResponse

from app.api.deps import get_current_teacher
from app.models.teacher import Teacher
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.indic_trans2_translation_provider import ModelUnavailableError
from app.services.translation_provider import get_translation_provider

router = APIRouter()

# A single provider for the whole process, chosen by environment. The factory
# marks the default DEVELOPMENT; the real model swaps in behind the same
# interface. Construction is lazy: configuring `GYANSETU_TRANSLATION_PROVIDER`
# alone does not download a checkpoint — the model loads on the first request.
_translation_provider = get_translation_provider()


@router.get("/diagnostics")
def translation_diagnostics(
    _teacher: Teacher = Depends(get_current_teacher),
) -> dict:
    """Operator readout for the real model: provider, checkpoint, load state,
    and the latest load/download diagnostics (timing + any error)."""
    return {
        "provider": getattr(_translation_provider, "provider", None),
        "model": getattr(_translation_provider, "model_id", None),
        "source": _translation_provider.source,
        "model_version": _translation_provider.model_version,
        "loaded": getattr(_translation_provider, "loaded", False),
        "is_real_model": _translation_provider.is_real_model,
        "diagnostics": getattr(_translation_provider, "diagnostics", None),
    }


@router.post("", response_model=TranslateResponse)
def translate_text(
    payload: TranslateRequest,
    request: Request,
    _teacher: Teacher = Depends(get_current_teacher),
) -> TranslateResponse:
    try:
        return _translation_provider.translate(payload)
    except ModelUnavailableError as error:
        # The real model cannot answer right now. Always an explicit state, never
        # a fabricated translation and never a silent fallback.
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "detail": {
                    "code": error.code,
                    "message": error.reason,
                    "reason": error.reason,
                    "detail": error.detail,
                    "provider": getattr(_translation_provider, "provider", None),
                    "model": getattr(_translation_provider, "model_id", None),
                    "is_real_model": False,
                    "diagnostics": getattr(_translation_provider, "diagnostics", None),
                }
            },
        )