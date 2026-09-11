"""OPTIONAL live integration test for the REAL IndicTrans2 model via
``/api/v1/translation/translate``.

Runs only when ``LIVE_AI=true`` (or ``LIVE_AI=1``). The configured checkpoint is
an INT8 ONNX export; a gated checkpoint still needs ``HF_TOKEN``.

Run with:

    LIVE_AI=true HF_TOKEN=hf_... .venv/bin/python -m pytest tests/live_ai_translation_route_test.py -v

It swaps the router's provider for the real IndicTrans2 provider (exactly what
``GYANSETU_TRANSLATION_PROVIDER=indic_trans2`` hands out) and asserts real
inference on the canonical classroom sentence:

    "मेरा नाम अनिता है।"   hin_Deva -> sat_Olck

then one short Ol Chiki Santali -> Hindi sentence.

This test NEVER claims the real model works unless real inference actually
succeeds: a load failure (gated / offline / deps) produces the explicit 503
``model_unavailable`` and the test fails loudly instead of faking success.
"""

from __future__ import annotations

import os

os.environ.setdefault("GYANSETU_DATABASE_URL", "sqlite:///./gyansetu_dev.db")

import pytest
from dotenv import load_dotenv

load_dotenv()

from fastapi.testclient import TestClient  # noqa: E402

import app.api.v1.translation_route as translation_route  # noqa: E402
from app.main import app  # noqa: E402
from app.services.translation_provider import get_translation_provider  # noqa: E402


def _live_ai_enabled() -> bool:
    return os.getenv("LIVE_AI", "").strip().lower() in {"1", "true", "yes"}


LIVE_AI = _live_ai_enabled()

skip_reason = "live AI test requires LIVE_AI=true"


def _register(client: TestClient, mobile: str) -> dict:
    body = {
        "displayName": "Live AI Teacher",
        "password": "secret123",
        "mobile": mobile,
        "schoolCode": "JH-LIVE",
        "schoolName": "MS Live",
    }
    response = client.post("/api/v1/auth/register", json=body)
    response.raise_for_status()
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


@pytest.mark.skipif(not LIVE_AI, reason=skip_reason)
def test_live_indic_trans2_hindi_to_santali_and_reverse(monkeypatch):
    from app.services import indic_trans2_translation_provider as provider_module

    provider_module._MODEL_CACHE.clear()
    provider_module._MODEL_DIAGNOSTICS.clear()
    provider = get_translation_provider("indic_trans2")
    monkeypatch.setattr(translation_route, "_translation_provider", provider)

    with TestClient(app) as client:
        headers = _register(client, "9898989899")

        diag = client.get("/api/v1/translation/diagnostics", headers=headers).json()
        assert diag["provider"] == "indic_trans2"
        assert diag["loaded"] is False  # construction is lazy

        # --- Hindi -> Santali (the canonical sentence) ---
        response = client.post(
            "/api/v1/translation/translate",
            headers=headers,
            json={
                "text": "मेरा नाम अनिता है।",
                "source_language": "hin_Deva",
                "target_language": "sat_Olck",
            },
        )
        if response.status_code == 503:
            detail = response.json()["detail"]
            assert detail["code"] == "model_unavailable"
            assert detail["is_real_model"] is False
            pytest.fail(
                "real model failed to load (honest 503); the live test cannot "
                "claim real inference succeeded."
            )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["translatedText"], "empty Santali translation"
        assert body["sourceText"] == "मेरा नाम अनिता है।"
        assert body["sourceLanguage"] == "hindi"
        assert body["targetLanguage"] == "santali"
        assert body["provider"] == "indic_trans2"
        assert body["model"] == provider.model_id
        assert body["isRealModel"] is True
        assert body["confidence"] is None
        assert body["reviewed"] is False
        assert body["translatedText"].strip() != body["sourceText"].strip()

        assert provider.loaded is True
        diag = client.get("/api/v1/translation/diagnostics", headers=headers).json()
        assert diag["loaded"] is True

        # --- Santali -> Hindi (reverse, short sentence) ---
        response = client.post(
            "/api/v1/translation/translate",
            headers=headers,
            json={
                "text": "ᱤᱧᱟᱹᱜ ᱧᱩᱛᱩᱢ ᱫᱚ ᱦᱩᱭᱩᱜ ᱠᱟᱱᱟ ᱚᱱᱤᱛᱟ ᱾",
                "source_language": "sat_Olck",
                "target_language": "hin_Deva",
            },
        )
        assert response.status_code == 200, response.text
        reversed_body = response.json()
        assert reversed_body["translatedText"], "empty Hindi translation"
        assert reversed_body["sourceLanguage"] == "santali"
        assert reversed_body["targetLanguage"] == "hindi"
        assert reversed_body["isRealModel"] is True
        assert reversed_body["confidence"] is None
        assert reversed_body["reviewed"] is False
