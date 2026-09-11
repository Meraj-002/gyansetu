"""The seam between the GyanSetu backend and the public Adi Vaani ISTS API.

Adi Vaani is a *speech-to-speech* translation service: it takes a recorded
audio clip in one language and answers with the transcript of what was said,
the translated text in the mother tongue, and an audio payload (base64 WAV)
of the spoken translation.

The endpoint the device trusts is intentionally small. This service owns the
HTTP call to Adi Vaani, validates that the provider answered honestly, and
returns exactly the fields the device is allowed to see — nothing that is not
needed travels past this class. The provider URL and gender preference are
environment-driven (``GYANSETU_ADIVAANI_*``), never stored in source code.
"""

from __future__ import annotations

import httpx

from app.core.config import get_settings

# Multiples of the observed Adi Vaani response shape. Only transcript and
# translated_text are load-bearing today: if the provider stops answering with
# them, an honest error must be raised rather than a fabricated translation.
_REQUIRED_RESPONSE_FIELDS = ("transcript", "translated_text", "audio")


class AdiVaaniSpeechTranslationError(Exception):
    """Adi Vaani could not answer honestly (network, validation, upstream)."""

    def __init__(self, code: str, message: str, detail: str = "") -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.detail = detail


class AdiVaaniSpeechTranslationService:
    """One method: send recorded Hindi audio, get back the clean response.

    Constructed with a settings object so tests can inject a fake URL/client
    without touching environment variables.
    """

    def __init__(self, settings=None) -> None:
        self._settings = get_settings() if settings is None else settings
        self._client = httpx.AsyncClient(
            timeout=self._settings.adivaani_translate_timeout_seconds
        )

    @property
    def provider(self) -> str:
        return "adivaani"

    async def translate(
        self, audio_bytes: bytes, filename: str = "speech.wav"
    ) -> dict:
        """POST one audio clip to Adi Vaani and return the clean device shape.

        Raises [AdiVaaniSpeechTranslationError] when the upstream answers with
        an error status or a body that lacks the fields the device displays.
        """
        if not audio_bytes:
            raise AdiVaaniSpeechTranslationError(
                "empty_audio", "The uploaded audio clip is empty."
            )

        url = self._settings.adivaani_translate_url
        data = {
            "source_language": "hin",
            "target_language": "sat",
            "gender": self._settings.adivaani_translate_gender,
        }
        files = {"file": (filename, audio_bytes, "audio/wav")}

        try:
            response = await self._client.post(url, data=data, files=files)
        except httpx.TimeoutException:
            raise AdiVaaniSpeechTranslationError(
                "upstream_timeout",
                "Adi Vaani took too long to answer. Please try again.",
            ) from None
        except httpx.TransportError:
            raise AdiVaaniSpeechTranslationError(
                "upstream_unreachable",
                "The speech-translation service could not be reached.",
            ) from None

        if response.is_error:
            detail_message = ""
            try:
                error_payload = response.json()
                if isinstance(error_payload, dict) and error_payload.get("detail"):
                    detail_message = str(error_payload["detail"]).strip()
            except ValueError:
                pass

            no_speech = "no speech" in (detail_message or "").lower()
            raise AdiVaaniSpeechTranslationError(
                "upstream_no_speech" if no_speech else "upstream_error",
                detail_message
                if no_speech
                else f"Adi Vaani rejected the request (HTTP {response.status_code}).",
                detail=f"upstream status: {response.status_code}",
            )

        try:
            payload = response.json()
        except ValueError:
            raise AdiVaaniSpeechTranslationError(
                "upstream_bad_body",
                "The speech-translation service returned an unreadable answer.",
            ) from None

        if not isinstance(payload, dict):
            raise AdiVaaniSpeechTranslationError(
                "upstream_bad_body",
                "The speech-translation service returned an unreadable answer.",
            )

        missing = [key for key in _REQUIRED_RESPONSE_FIELDS if not payload.get(key)]
        if missing:
            raise AdiVaaniSpeechTranslationError(
                "upstream_incomplete",
                "The speech-translation service returned an incomplete answer.",
                detail=f"missing fields: {', '.join(missing)}",
            )

        return {
            "transcript": str(payload["transcript"]),
            "translated_text": str(payload["translated_text"]),
            "audio": str(payload["audio"]),
            "content_type": str(payload.get("content_type") or "audio/wav"),
            "provider": self.provider,
        }

    async def close(self) -> None:
        await self._client.aclose()