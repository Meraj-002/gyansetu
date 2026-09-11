"""The seam where a real translation model plugs into `/api/v1/translate`.

Every engine that answers the translate endpoint implements
[TranslationProvider]; the router summons one through [get_translation_provider]
and relays whatever provenance the provider honestly reports. The development
rule table remains the safe default, while the explicitly selected
``indic_trans2`` provider runs the verified ONNX checkpoint when its runtime is
available.

A real model is added by implementing the same protocol and changing the
factory to hand it out behind a flag; the router, the schema and the cache-key
handling on the device do not change.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas.translation import TranslateRequest, TranslateResponse


class TranslationProvider(ABC):
    """Anything that can translate one sentence honestly."""

    @property
    @abstractmethod
    def source(self) -> str:
        """What actually produced the answer (``dev-phrasebook``, a model id…)."""

    @property
    @abstractmethod
    def model_version(self) -> str:
        """Version of the underlying table/model; feeds the on-device cache key."""

    @property
    @abstractmethod
    def reviewed_by_speaker(self) -> bool:
        """True only when a speaker of the target language has checked the data."""

    @property
    @abstractmethod
    def is_real_model(self) -> bool:
        """True ONLY when an actual machine-translation model produced answers.

        The device shows an "AI translation" badge from this flag alone, so it
        must stay false for the development rule table and every other mock."""

    @abstractmethod
    def translate(self, request: TranslateRequest) -> TranslateResponse:
        """Translate [request.text], raising the honest no-rule error when the
        provider has nothing for the sentence."""


def get_translation_provider(provider_name: str | None = None) -> TranslationProvider:
    """The provider behind `/api/v1/translate`, selected by environment.

    The value of ``GYANSETU_TRANSLATION_PROVIDER`` names the provider:

    - ``dev`` — the hand-written rule table (no model).
    - ``indic_trans2`` — the IndicTrans2 ONNX checkpoint behind the real NMT
      model seam. Construction FAILS LOUDLY (RuntimeError) when its dependencies
      are missing, the checkpoint is unavailable, or access is gated —
      translation never silently falls back to another engine.

    A real provider is added here — behind its name, reading any API key or
    endpoint from environment variables, never from source code — and nothing
    above this factory changes.
    """
    from app.core.config import get_settings

    name = (provider_name or get_settings().translation_provider or "dev").strip().lower()
    if name == "dev":
        from app.services.dev_translation_engine import DevelopmentTranslationProvider

        return DevelopmentTranslationProvider()

    if name == "indic_trans2":
        from app.services.indic_trans2_translation_provider import (
            IndicTrans2TranslationProvider,
        )

        settings = get_settings()
        return IndicTrans2TranslationProvider(
            model_id=settings.translation_model_id,
            token=settings.huggingface_token,
        )

    raise RuntimeError(
        f"Unknown GYANSETU_TRANSLATION_PROVIDER {name!r}. "
        "Supported values: dev, indic_trans2."
    )
