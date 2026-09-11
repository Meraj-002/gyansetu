"""Tests for the TranslationProvider factory (env-selected, injectable)."""

from __future__ import annotations

import pytest

from app.services.translation_provider import get_translation_provider


# The module-level translate router resolves the provider once at import; these
# tests exercise the factory directly, which is what the router uses.
def test_provider_defaults_to_the_dev_engine():
    provider = get_translation_provider()
    assert provider.source == "dev-phrasebook"
    assert provider.model_version == "dev-rules-1"
    assert provider.reviewed_by_speaker is False


def test_provider_selected_by_name():
    provider = get_translation_provider("dev")
    assert provider.source == "dev-phrasebook"


def test_unknown_provider_name_fails_loudly():
    # A made-up engine must never silently translate with the wrong one.
    with pytest.raises(RuntimeError, match=r"Unknown GYANSETU_TRANSLATION_PROVIDER"):
        get_translation_provider("google-ntp")


def test_indic_trans2_is_registered_but_constructs_lazily():
    # Construction must be cheap and silent — no torch import, no gated
    # download at startup. (Clear the process-wide model cache first so an
    # earlier test's successful load can't mask the laziness assertion.)
    from app.services import indic_trans2_translation_provider as mod

    mod._MODEL_CACHE.clear()
    mod._MODEL_DIAGNOSTICS.clear()

    provider = get_translation_provider("indic_trans2")
    assert provider.provider == "indic_trans2"
    assert provider.model_id == "TigreGotico/indictrans2-indic-indic-dist-320M-onnx"
    assert provider.loaded is False  # nothing downloaded at startup


def test_blank_provider_name_falls_back_to_dev():
    assert get_translation_provider("").source == "dev-phrasebook"
