"""Canonical schema for one translated phrasebook record.

This is the single schema the ingestion pipeline (scripts/import_translations)
validates data against, and the shape downstream consumers (the offline pack,
a future real provider) agree on. Every record can answer these questions:

- where the source sentence and its translation came from (``provenance``),
- whether a speaker of the language has actually checked it (``verified``),
- which classroom category / context / dialect it belongs to (``category``,
  ``context``, ``dialect``),
- which version of the data this is (``version``).

Never expose a record with ``verified=False`` as a verified translation:
``verified`` is only ever True for a sourced, provenance-carrying record, and a
placeholder (no target text) can never be verified.
"""

from __future__ import annotations

import hashlib
from datetime import datetime

from pydantic import Field, field_validator, model_validator

from app.schemas.common import APIModel
from app.schemas.translation import (
    TRANSLATION_PAIRS,
    normalise_translation_language,
)

# The classroom phrase categories the phrasebook organises sentences under.
# Mirrors the on-device PhrasebookCategory schema so a record is labelled the
# same way wherever it is read.
PHRASEBOOK_CATEGORIES = frozenset(
    {
        "greetings",
        "classroomInstructions",
        "questions",
        "answers",
        "numbers",
        "colors",
        "family",
        "schoolObjects",
        "learningActivities",
        "bodyParts",
        "food",
        "safety",
        "encouragement",
        "discipline",
        "environment",
        "basicMathematics",
        "basicScience",
        "basicActions",
    }
)

# A verified record must say where it came from — a real source (a book, an
# SIL/linguistic source, a community review). The development placeholders
# ("authored" / "authored-development" / "unknown" / blank) can never mark a
# record verified.
_DEV_PROVENANCES = frozenset({"", "authored", "authored-development", "unknown"})

_STRIPPED_PUNCTUATION = str.maketrans("", "", r"?!।,.'’‘" '\u201c\u201d')


def normalise_translation_source_text(value: str) -> str:
    """Punctuation- and case-insensitive canonical source sentence.

    Matches the lookup normalisation used by the dev engine and the on-device
    phrasebook, so a question mark a recogniser dropped — or a stray double
    space — never changes what a sentence means.
    """
    lowered = value.strip().lower().translate(_STRIPPED_PUNCTUATION)
    return " ".join(lowered.split())


def build_translation_record_id(
    source_language: str, target_language: str, source_text: str
) -> str:
    """A deterministic id, so re-importing the same sentence is idempotent.

    The natural key is (pair, normalised source sentence): refining a target
    keeps the same id, and two rows that disagree on the target for the same
    source collapse to one record instead of silently duplicating.
    """
    key = (
        f"{source_language}>{target_language}|"
        f"{normalise_translation_source_text(source_text)}"
    )
    return f"pb-{hashlib.sha1(key.encode('utf-8')).hexdigest()[:12]}"


class TranslationRecord(APIModel):
    """One validated phrasebook record, in the canonical Phase-2 schema."""

    id: str
    source_language: str
    target_language: str
    source_text: str
    target_text: str | None = None
    spoken_text: str | None = None
    category: str | None = None
    context: str | None = None
    dialect: str | None = None
    verified: bool = False
    provenance: str
    version: int = Field(default=1, ge=1)
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @field_validator("source_text")
    @classmethod
    def source_must_be_a_sentence(cls, value: str) -> str:
        stripped = (value or "").strip()
        if not stripped:
            raise ValueError("source_text must not be empty")
        return stripped

    @field_validator("source_language", "target_language")
    @classmethod
    def language_must_be_known(cls, value: str) -> str:
        return normalise_translation_language(value)

    @model_validator(mode="after")
    def record_must_be_internally_consistent(self) -> "TranslationRecord":
        pair = (self.source_language, self.target_language)
        if pair not in TRANSLATION_PAIRS:
            raise ValueError(
                "this language pair is not supported yet; "
                "hindi<->santali is the documented live pair"
            )
        if self.category is not None and self.category not in PHRASEBOOK_CATEGORIES:
            raise ValueError(f"unknown phrasebook category {self.category!r}")
        target_missing = not self.target_text or not self.target_text.strip()
        if self.verified and target_missing:
            raise ValueError(
                "a record with no target text is a placeholder and can never "
                "be marked verified"
            )
        if self.verified and not self.provenance.strip():
            raise ValueError(
                "a verified record must carry a provenance/source; "
                "an unchecked record must not be stamped verified"
            )
        if self.verified and self.provenance.strip().lower() in _DEV_PROVENANCES:
            raise ValueError(
                "verified=True requires a real provenance/source, not a "
                f"development marker {self.provenance!r}"
            )
        return self

    @property
    def is_placeholder(self) -> bool:
        return not self.target_text or not self.target_text.strip()

    def to_pack_json(self) -> dict[str, object]:
        """The camelCase line for the on-device phrasebook JSONL pack."""
        payload = self.model_dump(by_alias=True, exclude_none=True)
        payload["reviewedBySpeaker"] = self.verified
        payload["createdAt"] = (
            None if self.created_at is None else self.created_at.isoformat()
        )
        payload["updatedAt"] = (
            None if self.updated_at is None else self.updated_at.isoformat()
        )
        return payload