"""Tests for the Adi Vaani speech-to-speech proxy service.

The HTTP call to Adi Vaani is exercised with a fake httpx transport so the
tests never touch the real public endpoint. Focus: the exact multipart request
that leaves our backend, and the honest parsing/validation of the response.
"""

from __future__ import annotations

import base64

import httpx
import pytest

from app.services.adivaani_speech_translation_service import (
    AdiVaaniSpeechTranslationError,
    AdiVaaniSpeechTranslationService,
)


def _decode_multipart(content: bytes, content_type: str) -> dict:
    """Splits an httpx multipart body into its form fields and file fields."""
    boundary = content_type.split("boundary=", 1)[1].encode()
    result: dict = {"fields": {}, "files": {}}
    for part in content.split(b"--" + boundary):
        if b"\r\n\r\n" not in part or part.startswith(b"--\r\n"):
            continue
        headers, _, body = part.partition(b"\r\n\r\n")
        body = body.rstrip(b"\r\n")
        name = None
        filename = None
        for line in headers.split(b"\r\n"):
            lowered = line.lower()
            if lowered.startswith(b"content-disposition"):
                for chunk in line.split(b";"):
                    chunk = chunk.strip()
                    if chunk.startswith(b'name="'):
                        name = chunk[6:-1].decode()
                    elif chunk.startswith(b'filename="'):
                        filename = chunk[10:-1].decode()
        if filename is not None:
            result["files"]["file"] = {
                "filename": filename,
                "body": body,
            }
        elif name is not None:
            result["fields"][name] = body.decode()
    return result


class _FakeAdiVaani(httpx.MockTransport):
    """Serves a canned Adi Vaani response and records the outgoing request."""

    def __init__(self, *, status: int = 200, body: dict | None = None) -> None:
        super().__init__(self._handler)
        self.status = status
        self.body = body or {}
        self.sent_url: str | None = None
        self.sent_method: str | None = None
        self.sent_parsed: dict = {}

    def _handler(self, request: httpx.Request) -> httpx.Response:
        self.sent_url = str(request.url)
        self.sent_method = request.method
        self.sent_parsed = _decode_multipart(
            request.content, request.headers.get("content-type", "")
        )
        return httpx.Response(self.status, json=self.body)


class _Settings:
    adivaani_translate_url = "https://advaani.test/api/sts/translate"
    adivaani_translate_gender = "f"
    adivaani_translate_timeout_seconds = 30.0


@pytest.fixture()
def fake(monkeypatch):
    transport = _FakeAdiVaani(
        body={
            "transcript": "मेरा नाम अनिता है",
            "translated_text": "Āmić’ nám Anita aka",
            "audio": base64.b64encode(b"RIFF-WAV-BYTES").decode(),
            "content_type": "audio/wav",
            "processing_time": 4582.65,
        }
    )
    client = httpx.AsyncClient(transport=transport)
    service = AdiVaaniSpeechTranslationService(settings=_Settings())
    service._client = client
    return service, transport


@pytest.mark.asyncio
async def test_service_sends_hindi_to_santali_multipart(fake):
    service, transport = fake
    result = await service.translate(b"audio-bytes", "speech.wav")
    assert transport.sent_method == "POST"
    assert transport.sent_url == "https://advaani.test/api/sts/translate"
    assert transport.sent_parsed["fields"]["source_language"] == "hin"
    assert transport.sent_parsed["fields"]["target_language"] == "sat"
    assert transport.sent_parsed["fields"]["gender"] == "f"
    assert transport.sent_parsed["files"]["file"]["body"] == b"audio-bytes"
    assert transport.sent_parsed["files"]["file"]["filename"] == "speech.wav"
    assert result["provider"] == "adivaani"
    assert result["transcript"] == "मेरा नाम अनिता है"
    assert result["translated_text"] == "Āmić’ nám Anita aka"
    assert result["audio"] == base64.b64encode(b"RIFF-WAV-BYTES").decode()
    assert result["content_type"] == "audio/wav"


@pytest.mark.asyncio
async def test_service_rejects_empty_audio(fake):
    service, _ = fake
    with pytest.raises(AdiVaaniSpeechTranslationError) as exc:
        await service.translate(b"")
    assert exc.value.code == "empty_audio"


@pytest.mark.asyncio
async def test_service_raises_on_upstream_error_status(fake):
    service, _ = fake
    service._client = httpx.AsyncClient(
        transport=_FakeAdiVaani(status=500, body={"error": "oops"})
    )
    with pytest.raises(AdiVaaniSpeechTranslationError) as exc:
        await service.translate(b"audio")
    assert exc.value.code == "upstream_error"


@pytest.mark.asyncio
async def test_service_maps_no_speech_detail(fake):
    service, _ = fake
    service._client = httpx.AsyncClient(
        transport=_FakeAdiVaani(
            status=400,
            body={"detail": "No speech could be detected in the provided audio recording."},
        )
    )
    with pytest.raises(AdiVaaniSpeechTranslationError) as exc:
        await service.translate(b"audio")
    assert exc.value.code == "upstream_no_speech"
    assert "No speech" in exc.value.message


@pytest.mark.asyncio
async def test_service_raises_on_incomplete_body(fake):
    service, _ = fake
    service._client = httpx.AsyncClient(
        transport=_FakeAdiVaani(body={"transcript": "hi"})
    )
    with pytest.raises(AdiVaaniSpeechTranslationError) as exc:
        await service.translate(b"audio")
    assert exc.value.code == "upstream_incomplete"
    assert "translated_text" in exc.value.detail