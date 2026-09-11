from __future__ import annotations

from typing import Any

from pydantic import Field, field_validator, model_validator

from app.schemas.common import APIModel, Timestamped


class TranslationCreate(APIModel):
    # The app's cache key is "$lessonId#$targetLocale". Optional here; the
    # server derives one when not supplied.
    id: str | None = Field(default=None, max_length=128)
    lesson_id: str = Field(min_length=1, max_length=64)
    source_medium: str = Field(min_length=1, max_length=16)
    target_language: str = Field(min_length=1, max_length=16)
    text: str = Field(min_length=1)
    spoken_text: str | None = None
    provenance: str = Field(default="authored", max_length=32)
    reviewed_by_speaker: bool = False
    version: int = Field(default=1, ge=1)


class TranslationUpdate(APIModel):
    text: str | None = Field(default=None, min_length=1)
    spoken_text: str | None = None
    provenance: str | None = Field(default=None, max_length=32)
    reviewed_by_speaker: bool | None = None
    version: int | None = Field(default=None, ge=1)


class TranslationOut(TranslationCreate, Timestamped):
    id: str


# ---------------------------------------------------------------------------
# Free-text translation (`POST /api/v1/translate`).
#
# The classroom talks to this with two languages. The development engine
# supports the one pair real data exists for — Hindi as the teaching medium and
# Santali as the mother tongue — in both directions.
# ---------------------------------------------------------------------------

# Canonical (normalised) language codes, in the same shape seed data uses.
# Hindi and Santali are live today; Mundari and Ho are the documented secondary
# target — known languages, not yet translatable, and every layer says so.
TRANSLATION_LANGUAGES = ("hindi", "santali", "mundari", "ho", "english", "bengali")

# Locale ids and loose spellings the classroom may send are folded onto the
# canonical code so "hi-IN" and "sat" and "hindi"/"santali" all mean the same.
# IndicTrans2's own codes (hin_Deva / sat_Olck) are folded the same way, so a
# model-aware caller may send them verbatim.
_TRANSLATION_LANGUAGE_ALIASES = {
    "hindi": "hindi",
    "hi": "hindi",
    "hi-in": "hindi",
    "hin": "hindi",
    "hin-deva": "hindi",
    "santali": "santali",
    "santhali": "santali",
    "sat": "santali",
    "sat-olck": "santali",
    "mundari": "mundari",
    "unr": "mundari",
    "ho": "ho",
    "hoj": "ho",
    "hoc": "ho",
    "english": "english",
    "en": "english",
    "en-in": "english",
    "bengali": "bengali",
    "bn": "bengali",
    "bn-in": "bengali",
}

TRANSLATION_PAIRS = frozenset({("hindi", "santali"), ("santali", "hindi")})

_MAX_TRANSLATE_TEXT = 1000


def normalise_translation_language(value: str) -> str:
    folded = (value or "").strip().lower().replace("_", "-")
    try:
        return _TRANSLATION_LANGUAGE_ALIASES[folded]
    except KeyError as exc:
        raise ValueError("unknown language code") from exc


class TranslateRequest(APIModel):
    """The sentence to translate and the two languages it moves between."""

    text: str
    source_language: str
    target_language: str

    # Carried, never used by the development engine. A real model may read it.
    context: dict[str, Any] = Field(default_factory=dict)

    @field_validator("text")
    @classmethod
    def text_must_be_a_sentence(cls, value: str) -> str:
        text = (value or "").strip()
        if not text:
            raise ValueError("text must not be empty")
        if len(text) > _MAX_TRANSLATE_TEXT:
            raise ValueError("text is too long; keep it to one classroom sentence")
        return text

    @field_validator("source_language", "target_language")
    @classmethod
    def language_must_be_known(cls, value: str) -> str:
        return normalise_translation_language(value)

    @model_validator(mode="after")
    def pair_must_be_supported(self) -> "TranslateRequest":
        if (self.source_language, self.target_language) not in TRANSLATION_PAIRS:
            raise ValueError("this language pair is not supported yet")
        return self


class TranslateResponse(APIModel):
    """The translated sentence, plus the honest provenance of that answer.

    ``provider`` labels the engine (``dev`` or ``indic_trans2``); ``source`` is
    the specific engine/source id (``dev-phrasebook`` today, a model id later);
    ``model`` names the actual checkpoint; ``model_version`` feeds the on-device
    cache key so a corrected phrasebook or a new model never serves a stale
    cached answer. ``confidence`` is null unless the provider reported a real
    score — IndicTrans2 exposes none, so it stays null. ``reviewed`` is true
    only when a speaker checked the answer.
    """

    translated_text: str
    source_text: str | None = None
    source_language: str
    target_language: str
    source: str
    provider: str | None = None
    model: str | None = None
    model_version: str
    confidence: float | None = None
    spoken_text: str | None = None
    reviewed_by_speaker: bool = False
    reviewed: bool = False
    is_real_model: bool = False