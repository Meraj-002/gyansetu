"""Tests for POST /api/v1/translate (online free-text translation)."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

import app.api.v1.translate as translate_module
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.indic_trans2_translation_provider import ModelUnavailableError
from app.services.translation_provider import TranslationProvider


def _translate(client, headers, payload):
    return client.post("/api/v1/translate", json=payload, headers=headers)


@pytest.fixture()
def teacher(client, auth):
    return auth()


def test_translate_requires_auth(client):
    # No bearer token: the auth dependency refuses before any translation logic.
    response = client.post(
        "/api/v1/translate",
        json={"text": "एक", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code in (401, 403)


def test_translate_rejects_blank_text(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "   ", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code == 422


def test_translate_rejects_unknown_language(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "hello", "sourceLanguage": "klingon", "targetLanguage": "santali"},
    )
    assert response.status_code == 422


def test_translate_rejects_unsupported_pair(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "hello", "sourceLanguage": "english", "targetLanguage": "santali"},
    )
    assert response.status_code == 422


def test_translate_hindi_to_santali_success(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "बच्चों, कितने आम हैं?", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["translatedText"] == "Gidra'ko, kete ul menaka?"
    assert body["sourceLanguage"] == "hindi"
    assert body["targetLanguage"] == "santali"
    assert body["source"] == "dev-phrasebook"
    assert body["modelVersion"] == "dev-rules-1"
    assert body["confidence"] is None
    assert body["spokenText"] == "गिड़ाको, केते उल् मेनाका?"
    assert body["reviewedBySpeaker"] is False
    # The dev provider runs no model, so the device must never badge "AI".
    assert body["isRealModel"] is False
    # Compiled shape includes the requested contract fields, honestly derived.
    assert body["sourceText"] == "बच्चों, कितने आम हैं?"
    assert body["provider"] == "dev"
    assert body["model"] is None
    assert body["reviewed"] is False


def test_translate_real_model_response_shape(client, teacher, monkeypatch):
    class RealModelProvider(TranslationProvider):
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
                translated_text="नोमोस्कार गिद़ाको",
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

    monkeypatch.setattr(translate_module, "_translation_provider", RealModelProvider())
    response = _translate(
        client, teacher["headers"],
        {"text": "नमस्ते बच्चों", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["translatedText"] == "नोमोस्कार गिद़ाको"
    assert body["sourceText"] == "नमस्ते बच्चों"
    assert body["provider"] == "indic_trans2"
    assert body["model"] == "ai4bharat/indictrans2-indic-indic-dist-320M"
    assert body["isRealModel"] is True
    assert body["confidence"] is None  # never fabricated
    assert body["reviewed"] is False


def test_translate_model_unavailable_returns_explicit_503(client, teacher, monkeypatch):
    class BrokenProvider(TranslationProvider):
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
            return {
                "attempted": True,
                "error_code": "model_unavailable",
                "error_detail": "gated checkpoint: 401",
            }

        def translate(self, request: TranslateRequest) -> TranslateResponse:
            raise ModelUnavailableError(
                "model_unavailable",
                "model could not be loaded",
                "gated checkpoint: 401",
            )

    monkeypatch.setattr(translate_module, "_translation_provider", BrokenProvider())
    response = _translate(
        client, teacher["headers"],
        {"text": "एक", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "model_unavailable"
    assert detail["reason"] == "model could not be loaded"
    assert detail["is_real_model"] is False
    assert detail["provider"] == "indic_trans2"
    assert detail["model"] == "ai4bharat/indictrans2-indic-indic-dist-320M"
    # The failed provider must not invent a translation.
    assert "translatedText" not in response.json()


def test_translate_diagnostics_reports_provider_and_load_state(client, teacher):
    response = client.get("/api/v1/translate/diagnostics", headers=teacher["headers"])
    assert response.status_code == 200
    body = response.json()
    assert body["provider"] == "dev"
    assert body["loaded"] is False
    assert body["is_real_model"] is False
    assert "diagnostics" in body


def test_translate_accepts_indic_trans2_language_codes(client, teacher):
    # hin_Deva / sat_Olck are IndicTrans2's own codes; they fold onto the same
    # canonical codes the phrasebook stores, exactly like "hi-IN"/"sat".
    response = _translate(
        client, teacher["headers"],
        {"text": "एक", "sourceLanguage": "hin_Deva", "targetLanguage": "sat_Olck"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["translatedText"] == "mit'"
    assert body["sourceLanguage"] == "hindi"
    assert body["targetLanguage"] == "santali"


def test_translate_accepts_locale_id_spellings(client, teacher):
    # The classroom may send locale ids; they fold onto the canonical code.
    response = _translate(
        client, teacher["headers"],
        {"text": "एक", "sourceLanguage": "hi-IN", "targetLanguage": "sat"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["translatedText"] == "mit'"
    assert body["sourceLanguage"] == "hindi"
    assert body["targetLanguage"] == "santali"


def test_translate_reverse_pair_santali_to_hindi(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "Mit', bar, pe.", "sourceLanguage": "santali", "targetLanguage": "hindi"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["translatedText"] == "एक, दो, तीन।"


def test_translate_normalises_punctuation(client, teacher):
    # Weird spacing/punctuation still finds the phrasebook entry.
    response = _translate(
        client, teacher["headers"],
        {"text": "बच्चों   कितने  आम हैं", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code == 200
    assert response.json()["translatedText"] == "Gidra'ko, kete ul menaka?"


def test_translate_unknown_sentence_returns_404(client, teacher):
    response = _translate(
        client, teacher["headers"],
        {"text": "बच्चों अब स्कूल बंद है।", "sourceLanguage": "hindi", "targetLanguage": "santali"},
    )
    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "no_translation_rule"