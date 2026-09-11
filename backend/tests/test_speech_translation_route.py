"""Tests for POST /api/v1/translation/speech (Adi Vaani speech-to-speech
proxy). The Adi Vaani call is monkeypatched so tests never hit the network."""

from __future__ import annotations

import base64

import pytest

import app.api.v1.translation_route as translation_route
from app.schemas.speech_translation import SpeechTranslateResponse

_WAV_B64 = base64.b64encode(b"RIFF.....WAVE fake audio bytes").decode()


class _FakeSpeechService:
    """A pretend Adi Vaani proxy that answers exactly the clean device shape."""

    def __init__(self, *, out: dict | None = None, error: Exception | None = None):
        self._out = out
        self._error = error
        self.last_audio: bytes | None = None
        self.last_filename: str | None = None

    async def translate(self, audio_bytes: bytes, filename: str) -> dict:
        self.last_audio = audio_bytes
        self.last_filename = filename
        if self._error is not None:
            raise self._error
        return self._out or {
            "transcript": "मेरा नाम अनिता है",
            "translated_text": "Āmić’ nám Anita aka",
            "audio": _WAV_B64,
            "content_type": "audio/wav",
            "provider": "adivaani",
        }

    async def close(self) -> None:
        pass


def _upper_text_error() -> AdiVaaniSpeechTranslationError:
    from app.services.adivaani_speech_translation_service import (
        AdiVaaniSpeechTranslationError,
    )

    return AdiVaaniSpeechTranslationError(
        "upstream_error", "Adi Vaani rejected the request (HTTP 500).", "status: 500"
    )


@pytest.fixture()
def teacher(client, auth):
    return auth()


def _post_speech(client, headers, *, audio: bytes = b"audio-bytes"):
    return client.post(
        "/api/v1/translation/speech",
        headers=headers,
        files={"file": ("speech.wav", audio, "audio/wav")},
    )


def test_speech_translation_requires_auth(client):
    response = _post_speech(client, {})
    assert response.status_code in (401, 403)


def test_speech_translation_success(client, teacher, monkeypatch):
    service = _FakeSpeechService()
    monkeypatch.setattr(translation_route, "_speech_translation_service", service)

    response = _post_speech(client, teacher["headers"], audio=b"real-audio-bytes")
    assert response.status_code == 200
    assert service.last_audio == b"real-audio-bytes"
    assert service.last_filename == "speech.wav"
    body = response.json()
    assert body["transcript"] == "मेरा नाम अनिता है"
    assert body["translatedText"] == "Āmić’ nám Anita aka"
    assert body["audio"] == _WAV_B64
    assert body["contentType"] == "audio/wav"
    assert body["provider"] == "adivaani"


def test_speech_translation_upstream_error_is_502(client, teacher, monkeypatch):
    monkeypatch.setattr(
        translation_route,
        "_speech_translation_service",
        _FakeSpeechService(error=_upper_text_error()),
    )
    response = _post_speech(client, teacher["headers"])
    assert response.status_code == 502
    detail = response.json()["detail"]
    assert detail["code"] == "upstream_error"
    assert "translatedText" not in response.json()


def test_speech_translation_no_speech_is_422(client, teacher, monkeypatch):
    from app.services.adivaani_speech_translation_service import (
        AdiVaaniSpeechTranslationError,
    )

    monkeypatch.setattr(
        translation_route,
        "_speech_translation_service",
        _FakeSpeechService(
            error=AdiVaaniSpeechTranslationError(
                "upstream_no_speech",
                "No speech could be detected in the provided audio recording.",
                "upstream status: 400",
            )
        ),
    )
    response = _post_speech(client, teacher["headers"])
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["code"] == "upstream_no_speech"


def test_speech_translation_overlarge_audio_is_413(client, teacher, monkeypatch):
    # The route reads the byte limit from settings; hand it a tiny one.
    class _SmallLimitSettings:
        adivaani_max_audio_bytes = 4  # 4 bytes

    monkeypatch.setattr(
        translation_route, "get_settings", lambda: _SmallLimitSettings()
    )
    response = _post_speech(client, teacher["headers"], audio=b"12345")
    assert response.status_code == 413
    detail = response.json()["detail"]
    assert detail["code"] == "audio_too_large"


def test_speech_route_response_model_is_serialisable():
    response = SpeechTranslateResponse(
        transcript="t",
        translated_text="tt",
        audio=_WAV_B64,
        content_type="audio/wav",
        provider="adivaani",
    )
    data = response.model_dump(by_alias=True)
    assert data["transcript"] == "t"
    assert data["translatedText"] == "tt"
    assert data["audio"] == _WAV_B64
    assert data["contentType"] == "audio/wav"
    assert data["provider"] == "adivaani"