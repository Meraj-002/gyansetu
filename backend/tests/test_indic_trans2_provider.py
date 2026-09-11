"""Tests for the IndicTrans2 provider using injected fakes.

The real checkpoint is covered by the explicit live test; unit tests remain
isolated from any process-wide model cache.
"""

from __future__ import annotations

import threading

import pytest
from fastapi import HTTPException

from app.schemas.translation import TranslateRequest
from app.services.indic_trans2_translation_provider import (
    IndicTrans2TranslationProvider,
    LoadDiagnostics,
    ModelUnavailableError,
)

MODEL_ID = "TigreGotico/indictrans2-indic-indic-dist-320M-onnx"
MODEL_VERSION = "indictrans2-indic-indic-dist-320M-onnx-int8"


class _FakeTensor:
    pass


class _FakeModel:
    def __init__(self, name: str = "fake-model") -> None:
        self.name = name
        self.calls: list[object] = []

    def to(self, _device: str) -> "_FakeModel":
        return self

    def eval(self) -> None:
        pass

    def generate(self, **kwargs: object):
        self.calls.append(kwargs)
        return [0]

    def __call__(self):
        pass


class _FakeTokenizer:
    def __init__(self) -> None:
        self.last_inputs: list[object] = []

    def __call__(self, inputs: list[str], **kwargs: object) -> dict[str, object]:
        self.last_inputs.append(inputs)
        return {"input_ids": _FakeTensor()}

    def as_target_tokenizer(self):
        class _Scope:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return None

        return _Scope()

    def batch_decode(self, token_ids: list[object], **_kwargs):
        return ["<fake> नोमोस्कार </fake>"]


class _FakeProcessor:
    def preprocess_batch(self, sentences: list[str], **_kwargs):
        return sentences

    def postprocess_batch(self, batch: list[str], **_kwargs):
        return [text.replace("<fake> ", "").replace(" </fake>", "").strip() for text in batch]


class _Loader:
    """Records how many times it was asked for a fresh (tokenizer, model, processor)."""

    def __init__(self) -> None:
        self.calls = 0
        self.lock = threading.Lock()

    def __call__(self, model_id: str, token: str | None):
        with self.lock:
            self.calls += 1
        return _FakeTokenizer(), _FakeModel(f"{model_id}-cpu"), _FakeProcessor()


def _provider(
    loader: _Loader | None = None,
    cache: dict | None = None,
    diagnostics: dict | None = None,
) -> IndicTrans2TranslationProvider:
    return IndicTrans2TranslationProvider(
        loader=loader or _Loader(),
        cache={} if cache is None else cache,
        diagnostics={} if diagnostics is None else diagnostics,
    )


def test_indic_trans2_provider_describes_itself_honestly():
    provider = _provider()
    assert provider.loaded is False  # nothing loaded at construction (lazy)
    assert provider.reviewed_by_speaker is False
    assert provider.source == MODEL_ID
    assert provider.model_version == MODEL_VERSION
    assert provider.provider == "indic_trans2"
    assert provider.model_id == MODEL_ID
    # is_real_model tracks whether the real checkpoint is actually answerable.
    assert provider.is_real_model is False


def test_provider_is_lazy_and_never_touches_the_loader_before_a_request():
    loader = _Loader()
    provider = _provider(loader)
    assert loader.calls == 0  # construction must not load anything
    provider.translate(
        TranslateRequest(text="एक", source_language="hindi", target_language="santali")
    )
    assert loader.calls == 1


def test_translate_returns_shape_for_both_directions():
    for source, target, expected in (
        ("hindi", "santali", "नोमोस्कार"),
        ("santali", "hindi", "नोमोस्कार"),
    ):
        provider = _provider()
        response = provider.translate(
            TranslateRequest(text="नमस्ते बच्चों", source_language=source, target_language=target)
        )
        assert response.translated_text == expected
        assert response.source_text == "नमस्ते बच्चों"
        assert response.source_language == source
        assert response.target_language == target
        assert response.source == MODEL_ID
        assert response.provider == "indic_trans2"
        assert response.model == MODEL_ID
        assert response.model_version == MODEL_VERSION
        # Honesty: no confidence, no spoken text for Ol Chiki, no speaker review.
        assert response.confidence is None
        assert response.spoken_text is None
        assert response.reviewed_by_speaker is False
        assert response.reviewed is False
        assert response.is_real_model is True


def test_provider_never_loads_more_than_one_copy_across_instances():
    # Two providers sharing a cache must share a single loaded checkpoint.
    cache: dict = {}
    loader = _Loader()
    first = _provider(loader, cache)
    second = _provider(loader, cache)
    assert first.translate(TranslateRequest(text="एक", source_language="hindi", target_language="santali")).translated_text
    assert second.translate(TranslateRequest(text="दो", source_language="hindi", target_language="santali")).translated_text
    assert loader.calls == 1  # exactly one load for the whole process


def test_reuse_between_requests_uses_the_cached_model():
    cache: dict = {}
    loader = _Loader()
    provider = _provider(loader, cache)
    for _ in range(3):
        provider.translate(
            TranslateRequest(text="एक", source_language="hindi", target_language="santali")
        )
    assert loader.calls == 1
    assert provider.loaded is True
    assert provider.is_real_model is True


def test_unsupported_pair_fails_loudly_without_loading():
    loader = _Loader()
    provider = _provider(loader)
    request = TranslateRequest.model_construct(
        text="नमस्ते", source_language="mundari", target_language="santali"
    )
    with pytest.raises(HTTPException) as error:
        provider.translate(request)
    assert error.value.status_code == 404
    assert error.value.detail["code"] == "unsupported_pair"
    assert loader.calls == 0  # nothing was loaded just to refuse the pair


def test_failing_loader_raises_model_unavailable_and_never_fabricates():
    def failing_loader(model_id: str, token: str | None):
        raise RuntimeError("gated checkpoint: 401, accept terms first")

    # Fresh process-local cache so a successful test can't mask the failure.
    diagnostics: dict = {}
    provider = _provider(loader=failing_loader, cache={}, diagnostics=diagnostics)
    with pytest.raises(ModelUnavailableError) as error:
        provider.translate(
            TranslateRequest(text="एक", source_language="hindi", target_language="santali")
        )
    assert error.value.code == "model_unavailable"
    assert "gated checkpoint" in error.value.detail
    assert "gated checkpoint" in str(error.value)
    assert provider.loaded is False
    assert provider.is_real_model is False
    assert diagnostics  # diagnostics recorded the failure


def test_diagnostics_report_attempt_timing_and_success():
    cache: dict = {}
    diagnostics: dict = {}
    provider = _provider(_Loader(), cache, diagnostics)
    provider.translate(TranslateRequest(text="एक", source_language="hindi", target_language="santali"))
    d = provider.diagnostics
    assert d["attempted"] is True
    assert d["elapsed_ms"] is not None
    assert d["error_code"] is None

    LoadDiagnostics(attempted=True, elapsed_ms=1.0).to_dict()  # sanity: frozen dataclass shape


def test_empty_model_output_raises_model_unavailable():
    class _EmptyProcessor(_FakeProcessor):
        def postprocess_batch(self, batch: list[str], **_kwargs):
            return [""]

    def empty_loader(model_id: str, token: str | None):
        return _FakeTokenizer(), _FakeModel("-cpu"), _EmptyProcessor()

    provider = _provider(loader=empty_loader, cache={}, diagnostics={})
    with pytest.raises(ModelUnavailableError):
        provider.translate(
            TranslateRequest(text="अंधाधुंध", source_language="hindi", target_language="santali")
        )
