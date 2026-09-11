"""Tests for POST /api/v1/translation/translate (model-aware free-text
translation). The provider is mocked so normal tests never touch torch or a
checkpoint download."""

from __future__ import annotations

import pytest

import app.api.v1.translation_route as translation_route
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.indic_trans2_translation_provider import ModelUnavailableError
from app.services.translation_provider import TranslationProvider


def _translate(client, headers, payload):
    return client.post("/api/v1/translation/translate", json=payload, headers=headers)


@pytest.fixture()
def teacher(client, auth):
    return auth()


class _FakeRealModelProvider(TranslationProvider):
    """A pretend real model that answers honestly-shaped responses."""

    def __init__(self, out: dict) -> None:
        self._out = out

    @property
    def source(self) -> str:
        return "ai4bharat/indictrans2-indic-indic-dist-320M"

    @property
    def provider(self) -> str:
        return "indic_trans2"

    @property
    def model_id(self) -> str:
        return "ai4bharat/indictrans2-indic-indic-dist-320M"

    @property
    def model_version(self) -> str:
        return "indictrans2-indic-indic-dist-320M"

    @property
    def reviewed_by_speaker(self) -> bool:
        return False

    @property
    def is_real_model(self) -> bool:
        return True

    @property
    def diagnostics(self) -> dict:
        return {"attempted": True}

    def translate(self, request: TranslateRequest) -> TranslateResponse:
        return TranslateResponse(
            translated_text=self._out.get("translated_text", ""),
            source_text=request.text,
            source_language=request.source_language,
            target_language=request.target_language,
            source=self.source,
            provider=self.provider,
            model=self.model_id,
            model_version=self.model_version,
            confidence=None,
            reviewed=False,
            is_real_model=True,
        )


def test_translation_requires_auth(client):
    response = _translate(
        client, {},
        {"text": "मेरा नाम अनिता है।", "source_language": "hin_Deva", "target_language": "sat_Olck"},
    )
    assert response.status_code in (401, 403)


def test_translation_rejects_empty_text(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "   ", "source_language": "hindi", "target_language": "santali"},
    )
    assert response.status_code == 422
    assert any("text" in item.get("loc", []) for item in response.json()["detail"])


def test_translation_rejects_unknown_language(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "hello", "source_language": "klingon", "target_language": "santali"},
    )
    assert response.status_code == 422


def test_translation_rejects_unsupported_pair(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "hello", "source_language": "english", "target_language": "santali"},
    )
    assert response.status_code == 422


def test_translation_hindi_to_santali_success(client, teacher, monkeypatch):
    provider = _FakeRealModelProvider({"translated_text": "Āmić’ nám Anita aka."})
    monkeypatch.setattr(translation_route, "_translation_provider", provider)

    response = _translate(
        client, teacher["headers"],
        {"text": "मेरा नाम अनिता है।", "source_language": "hin_Deva", "target_language": "sat_Olck"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["sourceText"] == "मेरा नाम अनिता है।"
    assert body["translatedText"] == "Āmić’ nám Anita aka."
    assert body["sourceLanguage"] == "hindi"
    assert body["targetLanguage"] == "santali"
    assert body["provider"] == "indic_trans2"
    assert body["model"] == "ai4bharat/indictrans2-indic-indic-dist-320M"
    assert body["isRealModel"] is True
    assert body["confidence"] is None
    assert body["reviewed"] is False


def test_translation_santali_to_hindi_success(client, teacher, monkeypatch):
    provider = _FakeRealModelProvider({"translated_text": "मेरा नाम अनिता है।"})
    monkeypatch.setattr(translation_route, "_translation_provider", provider)

    response = _translate(
        client, teacher["headers"],
        {"text": "Āmić’ nám Anita aka.", "source_language": "sat_Olck", "target_language": "hin_Deva"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["translatedText"] == "मेरा नाम अनिता है।"
    assert body["sourceLanguage"] == "santali"
    assert body["targetLanguage"] == "hindi"
    assert body["isRealModel"] is True


def test_translation_model_unavailable_is_explicit_503(client, teacher, monkeypatch):
    class _Broken(TranslationProvider):
        @property
        def source(self) -> str:
            return "ai4bharat/indictrans2-indic-indic-dist-320M"

        @property
        def provider(self) -> str:
            return "indic_trans2"

        @property
        def model_id(self) -> str:
            return "ai4bharat/indictrans2-indic-indic-dist-320M"

        @property
        def model_version(self) -> str:
            return "indictrans2-indic-indic-dist-320M"

        @property
        def reviewed_by_speaker(self) -> bool:
            return False

        @property
        def is_real_model(self) -> bool:
            return False

        @property
        def diagnostics(self) -> dict:
            return {"attempted": True, "error_code": "model_unavailable"}

        def translate(self, request: TranslateRequest) -> TranslateResponse:
            raise ModelUnavailableError(
                "model_unavailable", "model could not be loaded", "gated checkpoint: 401"
            )

    monkeypatch.setattr(translation_route, "_translation_provider", _Broken())
    response = _translate(
        client, teacher["headers"],
        {"text": "एक", "source_language": "hindi", "target_language": "santali"},
    )
    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "model_unavailable"
    assert detail["is_real_model"] is False
    assert "translatedText" not in response.json()


def test_translation_diagnostics_reports_provider_and_load_state(client, teacher):
    response = client.get("/api/v1/translation/diagnostics", headers=teacher["headers"])
    assert response.status_code == 200
    body = response.json()
    assert body["provider"] == "dev"
    assert body["loaded"] is False
    assert body["is_real_model"] is False
    assert "diagnostics" in body
