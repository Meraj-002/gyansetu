"""Free-text translation mounted at ``/api/v1/translation``.

This is the model-aware translation surface. The path deliberately avoids the
plural ``/api/v1/translations``, which stays the CRUD contract for cached
lesson translations. The two never collide. The development provider remains
the safe default; the explicitly selected IndicTrans2 provider uses the real
ONNX model.

The same surface also hosts the speech-to-speech endpoint
(``/api/v1/translation/speech``), which proxies one recorded clip to the public
Adi Vaani ISTS API and returns the honest transcript + mother-tongue text +
spoken-audio payload. It is isolated from the text providers by design: the
text padding does not change and the Adi Vaani call never touches the IndicTrans2
checkpoint or the translation cache.

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

from fastapi import APIRouter, Depends, Request, UploadFile, status
from fastapi.responses import JSONResponse

from app.api.deps import get_current_teacher
from app.core.config import get_settings
from app.models.teacher import Teacher
from app.schemas.speech_translation import SpeechTranslateResponse
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.adivaani_speech_translation_service import (
    AdiVaaniSpeechTranslationError,
    AdiVaaniSpeechTranslationService,
)
from app.services.indic_trans2_translation_provider import ModelUnavailableError
from app.services.translation_provider import TranslationProvider, get_translation_provider

router = APIRouter()

# A single provider for the whole process, chosen by environment. Construction
# is lazy: configuring the provider alone does not download a checkpoint — the
# model loads on the first request.
_translation_provider: TranslationProvider = get_translation_provider()

# The speech-to-speech proxy. Adi Vaani never contacts the text provider, the
# checkpoint, or the cache; this is a completely separate path.
_speech_translation_service = AdiVaaniSpeechTranslationService()


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


@router.post("/speech", response_model=SpeechTranslateResponse)
async def translate_speech(
    file: UploadFile,
    _teacher: Teacher = Depends(get_current_teacher),
) -> SpeechTranslateResponse:
    """Translate one recorded clip: Hindi audio in, Santali audio out.

    The device sends the raw recording; this proxies it to Adi Vaani and
    returns the honest ``transcript``, ``translatedText``, and the provider's
    own ``audio`` (base64 WAV) payload. The provider never falls back to
    fabricating either text or audio.
    """
    settings = get_settings()
    audio_bytes = await file.read()
    if len(audio_bytes) > settings.adivaani_max_audio_bytes:
        return JSONResponse(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            content={
                "detail": {
                    "code": "audio_too_large",
                    "message": "The recorded audio is too large to translate.",
                }
            },
        )

    try:
        return SpeechTranslateResponse(
            **(
                await _speech_translation_service.translate(
                    audio_bytes, file.filename or "speech.wav"
                )
            )
        )
    except AdiVaaniSpeechTranslationError as error:
        # 422 when the clip itself had no recognisable speech (the device
        # should tell the teacher to speak again); 502 for everything else
        # that is genuinely an upstream/server-side problem.
        code_for_status = {
            "upstream_no_speech": status.HTTP_422_UNPROCESSABLE_ENTITY,
        }
        return JSONResponse(
            status_code=code_for_status.get(
                error.code, status.HTTP_502_BAD_GATEWAY
            ),
            content={
                "detail": {
                    "code": error.code,
                    "message": error.message,
                    "detail": error.detail,
                }
            },
        )
