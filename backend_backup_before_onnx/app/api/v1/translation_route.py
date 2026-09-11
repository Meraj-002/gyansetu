"""Free-text translation mounted at ``/api/v1/translation``.

This is the model-aware translation surface. The path deliberately avoids the
plural ``/api/v1/translations``, which stays the CRUD contract for cached
lesson translations. The two never collide.

Request (camelCase in the payload, folded by the schema):

    POST /api/v1/translation/translate
    {
      "source_language": "hin_Deva",   # or "hindi", "hi-IN", ...
      "target_language": "sat_Olck",   # or "santali", "sat", ...
      "text": "मेरा नाम अनिता है।"
    }

Response carries the honest provenance of the answer:

    source_text, translated_text, source_language, target_language,
    provider, model, is_real_model, confidence, reviewed

``provider`` is ``dev`` (the hand-written phrasebook, no model) or
``indic_trans2`` (the real NMT checkpoint); ``is_real_model`` is true ONLY
when a real checkpoint actually produced the answer; ``confidence`` stays null
unless the provider reports a real score; ``reviewed`` is true only when a
speaker checked the answer.

The provider is selected by ``GYANSETU_TRANSLATION_PROVIDER`` and loads the
IndicTrans2 checkpoint lazily on the first request — never at import/startup.
A model that cannot be produced surfaces as an explicit ``model_unavailable``
503, never a fabricated translation.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import JSONResponse

from app.api.deps import get_current_teacher
from app.models.teacher import Teacher
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.indic_trans2_translation_provider import ModelUnavailableError
from app.services.translation_provider import TranslationProvider, get_translation_provider

router = APIRouter()

# A single provider for the whole process, chosen by environment. Construction
# is lazy: configuring the provider alone does not download a checkpoint — the
# model loads on the first request.
_translation_provider: TranslationProvider = get_translation_provider()


def _provider() -> TranslationProvider:
    return _translation_provider


@router.get("/diagnostics")
def translation_diagnostics(
    _teacher: Teacher = Depends(get_current_teacher),
) -> dict:
    """Operator readout for the real model: provider, checkpoint, load state,
    and the latest load/download diagnostics (timing + any error)."""
    provider = _provider()
    return {
        "provider": getattr(provider, "provider", None),
        "model": getattr(provider, "model_id", None),
        "source": provider.source,
        "model_version": provider.model_version,
        "loaded": getattr(provider, "loaded", False),
        "is_real_model": provider.is_real_model,
        "diagnostics": getattr(provider, "diagnostics", None),
    }


@router.post("/translate", response_model=TranslateResponse)
def translate_text(
    payload: TranslateRequest,
    request: Request,
    _teacher: Teacher = Depends(get_current_teacher),
) -> TranslateResponse:
    provider = _provider()
    try:
        return provider.translate(payload)
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
                    "provider": getattr(provider, "provider", None),
                    "model": getattr(provider, "model_id", None),
                    "is_real_model": False,
                    "diagnostics": getattr(provider, "diagnostics", None),
                }
            },
        )
