"""DEVELOPMENT translation engine (no model behind it).

This is the backend twin of the Flutter ``OfflinePhrasebookTranslationService``:
it answers the small set of sentences that were written out, and refuses
everything else with an honest "no rule" error rather than guessing a
mother-tongue sentence for a class of children.

There is no NLP model here. ``source`` is ``dev-phrasebook`` and the engine is
one provider swap away from POSTing to a real model service. Never claim a
translation from this engine came from an AI model.
"""

from __future__ import annotations

from typing import Any

from app.core.exceptions import not_found
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.translation_provider import TranslationProvider

MODEL_VERSION = "dev-rules-1"
SOURCE = "dev-phrasebook"

# Categories mirror the on-device PhrasebookCategory schema, so a line in the
# dataset is labelled the same way wherever it is read.
_CATEGORY_NUMBERS = "numbers"
_CATEGORY_QUESTIONS = "questions"
_CATEGORY_GREETINGS = "greetings"
_CATEGORY_LEARNING_ACTIVITIES = "learningActivities"
_CATEGORY_CLASSROOM_INSTRUCTIONS = "classroomInstructions"

# (source, target) -> normalised source sentence -> entry.
# Entries mirror the on-device phrasebook, so online and offline agree. Every
# entry is a development record: the Santali forms were written for development
# and are NOT yet checked against a sourced dataset, so `reviewed` stays False.
_PHRASEBOOK: dict[tuple[str, str], dict[str, dict[str, Any]]] = {
    ("hindi", "santali"): {
        "बच्चों कितने आम हैं": {
            "target": "Gidra'ko, kete ul menaka?",
            "spoken": "गिड़ाको, केते उल् मेनाका?",
            "category": _CATEGORY_QUESTIONS,
        },
        "अब हम एक से दस तक गिनेंगे": {
            "target": "Nitok bo lekha: mit', bar, pe, pon, more, "
                      "turui, eae, iril, are, gel.",
            "spoken": "नितोक् बो लेखा: मित्, बार, पे, पोन, मोड़े, "
                      "तुरुइ, एयाए, इरिल, आरे, गेल।",
            "category": _CATEGORY_LEARNING_ACTIVITIES,
        },
        "सब बच्चे पाँच पत्थर उठाओ": {
            "target": "Sanam gidra'ko, more dhiri idi'me.",
            "spoken": "सानाम गिड़ाको, मोड़े ढिरी इदिमे।",
            "category": _CATEGORY_CLASSROOM_INSTRUCTIONS,
        },
        "बच्चों आज हम 1 से 10 तक गिनती सीखेंगे": {
            "target": "Johar gidra'ko! Ale mit' khon gel dhabic lekha bo.",
            "spoken": "जोहार गिड़ाको! आले मित् खोन गेल धाबिच् लेखा बो।",
            "category": _CATEGORY_LEARNING_ACTIVITIES,
        },
        "एक": {"target": "mit'", "spoken": "मित्", "category": _CATEGORY_NUMBERS},
        "दो": {"target": "bar", "spoken": "बार", "category": _CATEGORY_NUMBERS},
        "तीन": {"target": "pe", "spoken": "पे", "category": _CATEGORY_NUMBERS},
        "चार": {"target": "pon", "spoken": "पोन", "category": _CATEGORY_NUMBERS},
        "पाँच": {"target": "more", "spoken": "मोड़े", "category": _CATEGORY_NUMBERS},
        "एक दो तीन चार पाँच": {
            "target": "Mit', bar, pe, pon, more.",
            "spoken": "मित्, बार, पे, पोन, मोड़े।",
            "category": _CATEGORY_NUMBERS,
        },
    },
    ("santali", "hindi"): {
        "horoko kete aam achhe": {
            "target": "बच्चों, कितने आम हैं?",
            "spoken": "बच्चों, कितने आम हैं?",
            "category": _CATEGORY_QUESTIONS,
        },
        "mit bar pe": {
            "target": "एक, दो, तीन।",
            "spoken": "एक, दो, तीन।",
            "category": _CATEGORY_NUMBERS,
        },
        "gidrako kete ul menaka": {
            "target": "बच्चों, कितने आम हैं?",
            "spoken": "बच्चों, कितने आम हैं?",
            "category": _CATEGORY_QUESTIONS,
        },
        "mit": {"target": "एक", "spoken": "एक", "category": _CATEGORY_NUMBERS},
        "bar": {"target": "दो", "spoken": "दो", "category": _CATEGORY_NUMBERS},
        "pe": {"target": "तीन", "spoken": "तीन", "category": _CATEGORY_NUMBERS},
        "pon": {"target": "चार", "spoken": "चार", "category": _CATEGORY_NUMBERS},
        "more": {"target": "पाँच", "spoken": "पाँच", "category": _CATEGORY_NUMBERS},
    },
}


def _normalise(value: str) -> str:
    """Punctuation- and case-insensitive lookup key.

    Matches the Flutter phrasebook's own normalisation so a question mark a
    recogniser dropped — or a stray double space the teacher typed — still finds
    the entry. Devanagari combining marks (ा, ं) are not punctuation and are
    kept intact.
    """
    lowered = value.lower().translate(_STRIPPED_PUNCTUATION)
    return " ".join(lowered.split()).strip()


_STRIPPED_PUNCTUATION = str.maketrans("", "", "?!।,.'’‘\u201c\u201d")


def _lookup(entries: dict[str, dict[str, Any]], text: str) -> dict[str, Any] | None:
    wanted = _normalise(text)
    return entries.get(wanted)


class DevelopmentTranslationProvider(TranslationProvider):
    """Answers the written-out phrasebook and refuses everything else honestly."""

    @property
    def source(self) -> str:
        return SOURCE

    @property
    def provider(self) -> str:
        return "dev"

    @property
    def model_version(self) -> str:
        return MODEL_VERSION

    @property
    def reviewed_by_speaker(self) -> bool:
        # Every entry is a development record written for this build; none has
        # been checked by a speaker, so none may be presented as verified.
        return False

    @property
    def is_real_model(self) -> bool:
        # No NLP model runs in the dev engine — never let the device badge this.
        return False

    def translate(self, request: TranslateRequest) -> TranslateResponse:
        entries = _PHRASEBOOK.get((request.source_language, request.target_language))
        if entries is None:
            not_found(
                "unsupported_pair",
                "Translation between these languages is not supported in this build.",
            )

        entry = _lookup({} if entries is None else entries, request.text)
        if entry is None:
            not_found(
                "no_translation_rule",
                "This sentence is not covered by the offline phrasebook yet. "
                "Connect a translation model to translate anything the teacher says.",
            )

        return TranslateResponse(
            translated_text=entry["target"],
            source_text=request.text,
            source_language=request.source_language,
            target_language=request.target_language,
            source=self.source,
            provider="dev",
            model=None,
            model_version=self.model_version,
            confidence=None,
            spoken_text=entry.get("spoken"),
            reviewed_by_speaker=self.reviewed_by_speaker,
            reviewed=self.reviewed_by_speaker,
            is_real_model=False,
        )


def dev_translate(request: TranslateRequest) -> TranslateResponse:
    """Compatibility entry point; the router uses the provider instead."""
    return DevelopmentTranslationProvider().translate(request)