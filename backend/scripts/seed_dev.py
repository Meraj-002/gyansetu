"""Development-only seed data for GyanSetu (Class 1, Hindi -> Santali).

This script fills the development backend with a small, realistic dataset so an
engineer can point the app at the dev server and see real data on every screen
of the wiring path (catalogue, vocabulary, worksheets, assessments, sessions,
progress).

Safety:

* Refuses to run when ``GYANSETU_ENV=production`` (see Settings.is_production).
* Idempotent and additive: every row is keyed by a stable id (or a natural
  unique key such as ``School.code`` / ``Teacher.mobile``) and is only inserted
  when missing. Hand-entered data and runs against an already-seeded database
  are never overwritten.
* Runs in a single transaction: on any error the whole seed is rolled back.
* Nothing private is committed: the teacher PIN is a fixed development value
  documented here, not a secret from the environment.

Honesty boundaries (mirrors the app's own rules):

* No invented mother-tongue vocabulary. The only Santali words seeded are the
  numerals one to five, exactly as ``lib/data/flashcard_data.dart`` documents
  them ("mit'", "bar", "pe", "pon", "more"). Every translation row carries
  ``provenance="authored"`` and ``reviewed_by_speaker=False``.
* No fake AI output: worksheets are authored with ``generation_source="localOffline"``.
* There is no backend ``Student`` or ``Flashcard`` model, so no students or
  flashcards are seeded; classrooms keep using the app's local roster and
  bundled card data.

Run from the ``backend/`` directory:

    GYANSETU_ENV=development .venv/bin/python -m scripts.seed_dev

The script writes to whatever ``GYANSETU_DATABASE_URL`` resolves to (default:
``sqlite:///./gyansetu_dev.db``).
"""

from __future__ import annotations

import hashlib
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.security import hash_password
from app.models.assessment import Assessment
from app.models.classroom_session import ClassroomSession
from app.models.learning_outcome import LearningOutcome
from app.models.lesson import Lesson
from app.models.progress_event import ProgressEvent
from app.models.resource import Resource
from app.models.school import School
from app.models.teacher import Teacher
from app.models.teacher_record import ClassroomSetup
from app.models.translation import Translation
from app.models.worksheet import Worksheet

# -- stable identities -------------------------------------------------------
# Reused by the demo account, the Flutter live tests and the report.
DEV_SCHOOL_CODE = "GPS-DUMKA-DEV"
DEV_SCHOOL_NAME = "Govt. Primary School, Dumka (Dev)"
DEV_TEACHER_ID = "dev-teacher-1"
DEV_TEACHER_NAME = "Asha Murmu"
DEV_TEACHER_MOBILE = "9000012345"
DEV_TEACHER_PIN = "1234"

# Matching the app's bundled flashcards (lib/data/flashcard_data.dart), the only
# Santali vocabulary this project vouches for.
_SANTALI_NUMERALS = (
    ("1", "एक", "mit'", "मित्"),
    ("2", "दो", "bar", "बार"),
    ("3", "तीन", "pe", "पे"),
    ("4", "चार", "pon", "पोन"),
    ("5", "पाँच", "more", "मोड़े"),
)

# The documented offline phrasebook (Hindi <> Santali), in exactly the shape the
# on-device reader and the dev translation endpoints expect.
#
# Category names are the on-device PhrasebookCategory schema. `verified` is
# False on every line: these Santali forms were written by hand for development
# and no speaker has checked them yet, so the UI reports them unreviewed.
# Placeholder records (target_text None) mark the sentences the classroom knows
# it needs but has no written mother-tongue form for — the reader never answers
# from them, so a placeholder is never presented as a translation.
_PHRASEBOOK_ENTRIES: tuple[dict[str, Any], ...] = (
    # Numbers (Hindi -> Santali).
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "बच्चों, कितने आम हैं?", "target_text": "Gidra'ko, kete ul menaka?",
     "spoken_text": "गिड़ाको, केते उल् मेनाका?", "category": "questions"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "अब हम एक से दस तक गिनेंगे।",
     "target_text": "Nitok bo lekha: mit', bar, pe, pon, more, turui, eae, iril, are, gel.",
     "spoken_text": "नितोक् बो लेखा: मित्, बार, पे, पोन, मोड़े, तुरुइ, एयाए, इरिल, आरे, गेल।",
     "category": "learningActivities"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "सब बच्चे पाँच पत्थर उठाओ।", "target_text": "Sanam gidra'ko, more dhiri idi'me.",
     "spoken_text": "सानाम गिड़ाको, मोड़े ढिरी इदिमे।", "category": "classroomInstructions"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "बच्चों, आज हम 1 से 10 तक गिनती सीखेंगे।",
     "target_text": "Johar gidra'ko! Ale mit' khon gel dhabic lekha bo.",
     "spoken_text": "जोहार गिड़ाको! आले मित् खोन गेल धाबिच् लेखा बो।", "category": "learningActivities"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "एक", "target_text": "mit'", "spoken_text": "मित्", "category": "numbers"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "दो", "target_text": "bar", "spoken_text": "बार", "category": "numbers"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "तीन", "target_text": "pe", "spoken_text": "पे", "category": "numbers"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "चार", "target_text": "pon", "spoken_text": "पोन", "category": "numbers"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "पाँच", "target_text": "more", "spoken_text": "मोड़े", "category": "numbers"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "एक, दो, तीन, चार, पाँच।", "target_text": "Mit', bar, pe, pon, more.",
     "spoken_text": "मित्, बार, पे, पोन, मोड़े।", "category": "numbers"},
    # Numbers (Santali -> Hindi).
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Horoko, kete aam achhe?", "target_text": "बच्चों, कितने आम हैं?",
     "spoken_text": "बच्चों, कितने आम हैं?", "category": "questions"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Mit', bar, pe.", "target_text": "एक, दो, तीन।",
     "spoken_text": "एक, दो, तीन।", "category": "numbers"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Gidra'ko, kete ul menaka?", "target_text": "बच्चों, कितने आम हैं?",
     "spoken_text": "बच्चों, कितने आम हैं?", "category": "questions"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Mit'", "target_text": "एक", "spoken_text": "एक", "category": "numbers"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Bar", "target_text": "दो", "spoken_text": "दो", "category": "numbers"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Pe", "target_text": "तीन", "spoken_text": "तीन", "category": "numbers"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "Pon", "target_text": "चार", "spoken_text": "चार", "category": "numbers"},
    {"source_language": "santali", "target_language": "hindi",
     "source_text": "More", "target_text": "पाँच", "spoken_text": "पाँच", "category": "numbers"},
    # Placeholders: sentences the classroom needs, with NO written Santali form
    # yet. A null target is never answered from — the seed structures the
    # dataset without pretending to know what a girl in class would hear.
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "सुप्रभात, बच्चों।", "target_text": None, "spoken_text": None,
     "category": "greetings"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "शाबाश! बहुत अच्छे।", "target_text": None, "spoken_text": None,
     "category": "encouragement"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "चुपचाप बैठो।", "target_text": None, "spoken_text": None,
     "category": "classroomInstructions"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "यह सेब लाल है।", "target_text": None, "spoken_text": None,
     "category": "colors"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "अपना ध्यान दो।", "target_text": None, "spoken_text": None,
     "category": "basicActions"},
    {"source_language": "hindi", "target_language": "santali",
     "source_text": "अगर आग लगे तो मुझे बुलाओ।", "target_text": None, "spoken_text": None,
     "category": "safety"},
)

_LESSONS: tuple[dict[str, Any], ...] = (
    {
        "id": "c1-num-counting-1-10",
        "title": "Counting 1 to 10",
        "description": "Count everyday objects from one to ten with the class.",
        "subject": "numeracy",
        "outcome": "Learners count and name quantities from 1 to 10.",
        "order": 1, "minutes": 30,
        "worksheet": "c1-ws-counting-1-10",
        "concepts": ["countingObjects", "numbers1to5", "numbers6to10"],
    },
    {
        "id": "c1-num-counting-1-20",
        "title": "Numbers 1 to 20",
        "description": "Extend counting and number order to twenty.",
        "subject": "numeracy",
        "outcome": "Learners read, order and write numbers from 1 to 20.",
        "order": 2, "minutes": 30,
        "worksheet": "c1-ws-counting-1-20",
        "concepts": ["countingObjects", "numberOrder"],
    },
    {
        "id": "c1-num-addition-basics",
        "title": "First Addition",
        "description": "Join two groups and count the total (sums to 10).",
        "subject": "numeracy",
        "outcome": "Learners combine two groups and state the total.",
        "order": 3, "minutes": 30,
        "worksheet": "c1-ws-addition-basics",
        "concepts": ["addition", "countingObjects"],
    },
    {
        "id": "c1-num-shapes",
        "title": "Shapes Around Us",
        "description": "Name the circle, square and triangle in the classroom.",
        "subject": "numeracy",
        "outcome": "Learners recognise and name common 2D shapes.",
        "order": 4, "minutes": 30,
        "concepts": ["shapes"],
    },
    {
        "id": "c1-lit-colors",
        "title": "Colours",
        "description": "Say the Hindi names for the colours used in class.",
        "subject": "foundationalLiteracy",
        "outcome": "Learners name and sort common colours in the teaching language.",
        "order": 1, "minutes": 30,
        "concepts": ["colours"],
    },
    {
        "id": "c1-lit-animals",
        "title": "Animals",
        "description": "Build vocabulary for the animals around the village.",
        "subject": "foundationalLiteracy",
        "outcome": "Learners name common animals in the teaching language.",
        "order": 2, "minutes": 30,
        "concepts": ["animals"],
    },
    {
        "id": "c1-lit-nature",
        "title": "Nature Words",
        "description": "Build vocabulary for trees, water and the sun.",
        "subject": "foundationalLiteracy",
        "outcome": "Learners name common things in nature.",
        "order": 3, "minutes": 30,
        "concepts": ["nature"],
    },
    {
        "id": "c1-lit-hindi-words",
        "title": "Everyday Hindi Words",
        "description": "High-frequency Hindi words for the classroom.",
        "subject": "foundationalLiteracy",
        "outcome": "Learners recognise and say a small set of high-frequency Hindi words.",
        "order": 4, "minutes": 30,
        "concepts": ["vocabulary"],
    },
    {
        "id": "c1-lit-santali-words",
        "title": "Counting in Santali",
        "description": "The documented Santali numerals one to five, as a language lesson.",
        "subject": "foundationalLiteracy",
        "outcome": "Learners hear and say the Santali numerals one to five.",
        "order": 5, "minutes": 30,
        "concepts": ["vocabulary"],
    },
)

_LEARNING_OUTCOMES: tuple[dict[str, Any], ...] = (
    {"id": "lo-c1-num-counting-1-10", "code": "LO-NUM-C1-01",
     "text": "Count and state the quantity of up to 10 objects.",
     "class_number": 1, "subject": "numeracy", "language": "hindi",
     "curriculum_reference": "Class 1 Numeracy"},
    {"id": "lo-c1-num-counting-1-20", "code": "LO-NUM-C1-02",
     "text": "Read and write the numbers 1 to 20 in order.",
     "class_number": 1, "subject": "numeracy", "language": "hindi",
     "curriculum_reference": "Class 1 Numeracy"},
    {"id": "lo-c1-num-addition-basics", "code": "LO-NUM-C1-03",
     "text": "Add two small groups and find the total (up to 10).",
     "class_number": 1, "subject": "numeracy", "language": "hindi",
     "curriculum_reference": "Class 1 Numeracy"},
    {"id": "lo-c1-num-shapes", "code": "LO-NUM-C1-04",
     "text": "Recognise and name circle, square and triangle.",
     "class_number": 1, "subject": "numeracy", "language": "hindi",
     "curriculum_reference": "Class 1 Numeracy"},
    {"id": "lo-c1-lit-colors", "code": "LO-LIT-C1-01",
     "text": "Name and sort the colours used in the classroom.",
     "class_number": 1, "subject": "foundationalLiteracy", "language": "hindi",
     "curriculum_reference": "Class 1 Foundational Literacy"},
    {"id": "lo-c1-lit-animals", "code": "LO-LIT-C1-02",
     "text": "Name common animals of the locality.",
     "class_number": 1, "subject": "foundationalLiteracy", "language": "hindi",
     "curriculum_reference": "Class 1 Foundational Literacy"},
    {"id": "lo-c1-lit-nature", "code": "LO-LIT-C1-03",
     "text": "Name common things found in nature.",
     "class_number": 1, "subject": "foundationalLiteracy", "language": "hindi",
     "curriculum_reference": "Class 1 Foundational Literacy"},
    {"id": "lo-c1-lit-hindi-words", "code": "LO-LIT-C1-04",
     "text": "Read and say a small set of high-frequency Hindi words.",
     "class_number": 1, "subject": "foundationalLiteracy", "language": "hindi",
     "curriculum_reference": "Class 1 Foundational Literacy"},
    {"id": "lo-c1-lit-santali-words", "code": "LO-LIT-C1-05",
     "text": "Hear and say the Santali numerals one to five.",
     "class_number": 1, "subject": "foundationalLiteracy", "language": "hindi",
     "curriculum_reference": "Class 1 Foundational Literacy"},
)

# Worksheets are authored sample content, shaped for WorksheetQuestion.fromJson:
# correctAnswer is a String, options are Strings, type is a QuestionType.name.
def _question(
    qid: str,
    qtype: str,
    text: str,
    answer: str,
    options: list[str],
    *,
    order: int,
    translated: str | None = None,
    visual: str | None = None,
    visual_count: int | None = None,
    concept: str | None = None,
) -> dict[str, Any]:
    return {
        "id": qid,
        "type": qtype,
        "questionText": text,
        "correctAnswer": answer,
        "order": order,
        "translatedQuestionText": translated,
        "options": options,
        "explanation": None,
        "visualAsset": visual,
        "visualCount": visual_count,
        "concept": concept,
    }


def _worksheet(
    wid: str,
    lesson_id: str,
    title: str,
    outcome: str,
    subject: str,
    questions: list[dict[str, Any]],
    *,
    notes: str,
) -> dict[str, Any]:
    return {
        "id": wid,
        "lesson_id": lesson_id,
        "title": title,
        "learning_outcome": outcome,
        "class_number": 1,
        "subject": subject,
        "teaching_language": "hindi",
        "target_language": "santali",
        "difficulty": "easy",
        "questions": questions,
        "visual_examples": [],
        "culturally_familiar_examples": True,
        "teacher_notes": notes,
        "variant": 0,
        "requested_question_count": len(questions),
        "generation_source": "localOffline",
    }


_WORKSHEETS: tuple[dict[str, Any], ...] = (
    _worksheet(
        "c1-ws-counting-1-10",
        "c1-num-counting-1-10",
        "Count 1 to 10 — Worksheet",
        "Learners count and name quantities from 1 to 10.",
        "numeracy",
        [
            _question(
                "c1-q-count-1", "countingObjects",
                "Count the objects. How many apples?", "5",
                ["3", "4", "5", "6"], order=1,
                translated="गिनो। कितने सेब हैं?",
                visual="apples", visual_count=5, concept="countingObjects",
            ),
            _question(
                "c1-q-count-2", "countingObjects",
                "Count the objects. How many trees?", "3",
                ["2", "3", "4", "5"], order=2,
                translated="गिनो। कितने पेड़ हैं?",
                visual="trees", visual_count=3, concept="countingObjects",
            ),
            _question(
                "c1-q-count-3", "countingObjects",
                "Count the objects. How many animals?", "4",
                ["3", "4", "5", "6"], order=3,
                translated="गिनो। कितने जानवर हैं?",
                visual="animals", visual_count=4, concept="countingObjects",
            ),
            _question(
                "c1-q-count-4", "visualIdentification",
                "Which number is the biggest?", "5",
                ["2", "3", "4", "5"], order=4,
                translated="कौन सी संख्या सबसे बड़ी है?",
                concept="numbers1to5",
            ),
        ],
        notes="Authored development sheet: count bundled picture sets.",
    ),
    _worksheet(
        "c1-ws-counting-1-20",
        "c1-num-counting-1-20",
        "Numbers 1 to 20 — Worksheet",
        "Learners read, order and write numbers from 1 to 20.",
        "numeracy",
        [
            _question(
                "c1-q-one20-1", "fillInTheBlanks",
                "Fill in the missing number: 1, 2, __, 4", "3",
                ["2", "3", "4", "5"], order=1,
                translated="छूटी हुई संख्या भरो: 1, 2, __, 4",
                concept="numberOrder",
            ),
            _question(
                "c1-q-one20-2", "countingObjects",
                "Count the objects. How many pencils?", "8",
                ["6", "7", "8", "9"], order=2,
                translated="गिनो। कितनी पेंसिलें हैं?",
                visual="householdObjects", visual_count=8, concept="countingObjects",
            ),
            _question(
                "c1-q-one20-3", "visualIdentification",
                "Which number is twelve?", "12",
                ["1", "2", "12", "20"], order=3,
                translated="बारह कौन सी संख्या है?",
                concept="countingObjects",
            ),
        ],
        notes="Authored development sheet: counting into the teens.",
    ),
    _worksheet(
        "c1-ws-addition-basics",
        "c1-num-addition-basics",
        "First Addition — Worksheet",
        "Learners combine two groups and state the total.",
        "numeracy",
        [
            _question(
                "c1-q-add-1", "countingObjects",
                "2 apples + 3 apples = how many apples?", "5",
                ["3", "4", "5", "6"], order=1,
                translated="2 सेब + 3 सेब = कितने सेब?",
                visual="apples", visual_count=5, concept="addition",
            ),
            _question(
                "c1-q-add-2", "fillInTheBlanks",
                "Fill in the total: 3 + 4 = __", "7",
                ["5", "6", "7", "8"], order=2,
                translated="कुल भरो: 3 + 4 = __",
                concept="addition",
            ),
            _question(
                "c1-q-add-3", "visualIdentification",
                "1 tree + 2 trees = how many trees?", "3",
                ["2", "3", "4", "5"], order=3,
                translated="1 पेड़ + 2 पेड़ = कितने पेड़?",
                visual="trees", visual_count=3, concept="addition",
            ),
        ],
        notes="Authored development sheet: joining small groups.",
    ),
)


# -- downloadable content packs ----------------------------------------------
# Every pack below is real, authored bytes: the JSON is serialised with the
# project's own spellings, then stored, checksummed and streamed as-is. A device
# that downloads one verifies size + sha256 against the manifest, so "Ready"
# really means the exact stored bytes are on disk. No pack is a pointer, a stub
# or a promise.

# Authored teacher-script steps for each lesson (hindi prompt + santali intent).
_SCRIPTS: dict[str, list[tuple[str, str, str]]] = {
    "c1-num-counting-1-10": [
        ("Show five apples. Count with me: एक, दो, तीन, चार, पाँच.", "मित्, बार, पे, पोन, मोड़े", "countingObjects"),
        ("How many trees? Count the pictures on the board.", "कितने पेड़ हैं?", "countingObjects"),
        ("Say the number you see on the flashcard.", "कार्ड पर संख्या बोलो।", "countingObjects"),
    ],
    "c1-num-counting-1-20": [
        ("We counted to ten. Now let's go on: eleven to twenty.", "अब दस से बीस तक गिनें।", "numberOrder"),
        ("What comes after 12? What comes before 19?", "12 के बाद क्या आता है?", "numberOrder"),
        ("Arrange the number cards in order.", "संख्या कार्ड क्रम में लगाओ।", "numberOrder"),
    ],
    "c1-num-addition-basics": [
        ("Two apples and three apples. Join the groups, count the total.", "दो सेब और तीन सेब। कुल कितने?", "addition"),
        ("Three trees plus two trees — how many now?", "तीन पेड़ और दो पेड़ — कुल कितने?", "addition"),
        ("Try: one stone plus four stones.", "एक कंकड़ और चार कंकड़।", "addition"),
    ],
    "c1-num-shapes": [
        ("Point to the circle on the board. Say: वृत्त.", "यह गोल आकृति है — वृत्त।", "shapes"),
        ("Where is the square? Where is the triangle?", "वर्ग कहाँ है? त्रिभुज कहाँ है?", "shapes"),
        ("Find a circle and a square in the classroom.", "कंपनी में गोल और चौकोर चीज़ ढूंढो।", "shapes"),
    ],
    "c1-lit-colors": [
        ("This is लाल. Say it with me. Point to something red.", "यह लाल है।", "colours"),
        ("This is नीला. Point to the sky.", "यह नीला है।", "colours"),
        ("Sort these colour cards into groups.", "रंग कार्ड को छांटो।", "colours"),
    ],
    "c1-lit-animals": [
        ("This is a गाय. The cow is near the field.", "गाय खेत के पास है।", "animals"),
        ("This is a कुत्ता. The dog is in the village.", "कुत्ता गांव में है।", "animals"),
        ("Name the animals you see in the picture.", "चित्र में जानवरों के नाम बोलो।", "animals"),
    ],
    "c1-lit-nature": [
        ("Look at the tree — पेड़. Water is पानी.", "पेड़ लंबा है। पानी बहता है।", "nature"),
        ("The sun — सूरज — is high in the sky.", "सूरज चमकता है।", "nature"),
        ("Point to leaves, water and the sun in the photo.", "पत्ते, पानी और सूरज दिखाओ।", "nature"),
    ],
    "c1-lit-hindi-words": [
        ("The word is किताब. Say it and show me the book.", "किताब — यह शब्द पढ़ो।", "vocabulary"),
        ("The word is पानी. Point to water.", "पानी — यह शब्द पढ़ो।", "vocabulary"),
        ("Match the word card to the picture.", "शब्द कार्ड को चित्र से मिलाओ।", "vocabulary"),
    ],
    "c1-lit-santali-words": [
        ("एक in Santali is मित्. Say मित्.", "mit' — एक।", "vocabulary"),
        ("Two is बार, three is पे. Count together.", "bar bas pe — गिनो।", "vocabulary"),
        ("Listen and repeat the five numerals one to five.", "मित्, बार, पे, पोन, मोड़े।", "vocabulary"),
    ],
}


def _json_bytes(payload: dict[str, Any]) -> bytes:
    """Serialise a pack with the project's spellings, utf-8, no spaces."""
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def _content_pack(info: dict[str, Any]) -> bytes:
    script = [
        {
            "step": index,
            "prompt": prompt,
            "sayInSantali": say,
            "language": "hindi",
            "concept": concept,
        }
        for index, (prompt, say, concept) in enumerate(
            _SCRIPTS.get(info["id"], [("Introduce the lesson.", "", "learning")]),
            start=1,
        )
    ]
    return _json_bytes(
        {
            "type": "lessonContentPack",
            "schemaVersion": 1,
            "lessonId": info["id"],
            "title": info["title"],
            "subject": info["subject"],
            "classNumber": 1,
            "language": "hindi",
            "targetLanguage": "santali",
            "concepts": list(info.get("concepts") or []),
            "teachingScript": script,
            "activity": {
                "type": "guidedPractice",
                "instructions": [
                    "Do step one together.",
                    "Call up a learner for each step.",
                    "Repeat the target words once more.",
                ],
            },
            "assessmentPrompts": [
                {"id": f"{info['id']}.check-1", "text": script[0]["prompt"]},
            ],
            "passages": [
                {
                    "id": f"{info['id']}.passage-1",
                    "hindi": "सीखने का समय शुरू करें।",
                    "santali": "पढ़ने का समय है।",
                }
            ],
        }
    )


def _audio_pack(info: dict[str, Any]) -> bytes:
    utterances = [
        {
            "id": f"{info['id']}.utt-{index}",
            "speaker": "teacher",
            "sourceText": prompt,
            "targetText": say,
            "durationMs": max(800, 120 * len(prompt)),
        }
        for index, (prompt, say, _concept) in enumerate(
            _SCRIPTS.get(info["id"], [("Welcome to class.", "", "learning")]),
            start=1,
        )
    ]
    return _json_bytes(
        {
            "type": "utterancePlan",
            "schemaVersion": 1,
            "lessonId": info["id"],
            "speaker": "teacher",
            "language": "hindi",
            "targetLanguage": "santali",
            # Authored utterance plan: paced prompts and their Santali renderings.
            # Real speech synthesis stays on-device; this pack is its text source.
            "utterances": utterances,
        }
    )


def _RESOURCE_PACKS() -> list[tuple[str, str, str, str, str, bytes, str | None]]:
    """Yield (id, kind, name, subject, description, blob, lesson_id) per pack."""
    packs: list[tuple[str, str, str, str, str, bytes, str | None]] = []
    for info in _LESSONS:
        lesson_id: str = info["id"]
        subject: str = info["subject"]
        packs.append(
            (
                f"{lesson_id}.content",
                "content",
                f"{info['title']} — Lesson content",
                subject,
                "Authored lesson script, activities and assessment prompts.",
                _content_pack(info),
                lesson_id,
            )
        )
        packs.append(
            (
                f"{lesson_id}.audio",
                "audio",
                f"{info['title']} — Speech plan",
                subject,
                "Authored utterance plan (prompts and Santali renderings).",
                _audio_pack(info),
                lesson_id,
            )
        )
    for sheet in _WORKSHEETS:
        packs.append(
            (
                sheet["id"],
                "worksheet",
                sheet["title"],
                sheet["subject"],
                "Authored worksheet questions for the lesson.",
                _json_bytes(sheet),
                sheet["lesson_id"],
            )
        )
    flashcard_pack = _json_bytes(
        {
            "type": "flashcardPack",
            "schemaVersion": 1,
            "classNumber": 1,
            "language": "santali",
            "cards": [
                {
                    "id": f"sat-{value}",
                    "value": value,
                    "hindi": hindi,
                    "santali": santali,
                    "devanagari": devanagari,
                }
                for value, hindi, santali, devanagari in _SANTALI_NUMERALS
            ],
        }
    )
    packs.append(
        (
            "c1-flashcards-santali-numerals",
            "flashcard",
            "Santali numerals 1–5 — flashcard pack",
            "foundationalLiteracy",
            "The documented Santali numerals bundled on-device.",
            flashcard_pack,
            "c1-lit-santali-words",
        )
    )
    translation_pack = _json_bytes(
        {
            "type": "translationPack",
            "schemaVersion": 1,
            "lessonId": "c1-num-counting-1-10",
            "targetLanguage": "santali",
            "entries": [
                {
                    "id": f"c1-num-counting-1-10#sat#{value}",
                    "hindi": hindi,
                    "santali": santali,
                    "devanagari": devanagari,
                    "provenance": "authored",
                }
                for value, hindi, santali, devanagari in _SANTALI_NUMERALS
            ],
        }
    )
    packs.append(
        (
            "c1-translations-santali",
            "translation",
            "Santali numerals 1–5 — translation pack",
            "foundationalLiteracy",
            "The documented Santali numerals as a downloadable pack.",
            translation_pack,
            "c1-num-counting-1-10",
        )
    )

    # Offline phrasebook pack consumed by the offline-first translation reader.
    # One JSON object per line, streamed line-by-line so a 2 GB device never
    # holds the whole file in memory at once. Mirrors the dev translation
    # endpoint so online and offline answers agree. Both directions are listed
    # explicitly — no direction is guessed from the script.
    phrasebook_lines = [
        json.dumps(
            {
                "id": f"pb-{index}",
                "sourceLanguage": entry["source_language"],
                "targetLanguage": entry["target_language"],
                "sourceText": entry["source_text"],
                "targetText": entry["target_text"],
                "spokenText": entry["spoken_text"],
                "category": entry.get("category"),
                "context": None,
                "dialect": None,
                "version": 1,
                "provenance": "authored-development",
                "reviewedBySpeaker": False,
                "verified": False,
            },
            ensure_ascii=False,
        )
        for index, entry in enumerate(_PHRASEBOOK_ENTRIES)
    ]
    phrasebook_pack = "\n".join(phrasebook_lines).encode("utf-8") + b"\n"
    packs.append(
        (
            "translation-hindi-santali",
            "translation",
            "Hindi → Santali offline phrasebook pack",
            "foundationalLiteracy",
            "The documented Hindi ↔ Santali phrasebook, for offline translation.",
            phrasebook_pack,
            None,
        )
    )
    return packs


# -- helpers ----------------------------------------------------------------

def _now(delta: timedelta | None = None) -> datetime:
    value = datetime.now(timezone.utc)
    return value + delta if delta else value


def _ts(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _iso_now() -> str:
    return _ts(_now())


def _created(db: Session, model: type, pk_attr: str, pk_value: str, **values: Any) -> bool:
    """Insert a row keyed by ``pk_attr`` unless it already exists."""
    existing = db.execute(select(model).where(getattr(model, pk_attr) == pk_value)).scalar_one_or_none()
    if existing is not None:
        return False
    db.add(model(**{pk_attr: pk_value, **values}))
    return True


@dataclass
class SeedSummary:
    """How many rows this run actually inserted (0 means nothing to do)."""

    schools: int = 0
    teachers: int = 0
    classroom_setups: int = 0
    students: int = 0
    lessons: int = 0
    learning_outcomes: int = 0
    translations: int = 0
    worksheets: int = 0
    assessments: int = 0
    classroom_sessions: int = 0
    progress_events: int = 0
    resources: int = 0

    @property
    def total(self) -> int:
        return sum(
            (
                self.schools, self.teachers, self.classroom_setups, self.students,
                self.lessons, self.learning_outcomes, self.translations,
                self.worksheets, self.assessments, self.classroom_sessions,
                self.progress_events, self.resources,
            )
        )


def run(db: Session, *, settings: Settings | None = None) -> SeedSummary:
    """Seed a development database. Returns what was inserted this run.

    Idempotent, additive and wrapped in a single transaction by the caller's
    commit (or rolled back here on failure) — see `main`.
    """
    cfg = settings or get_settings()
    if cfg.is_production:
        raise SystemExit(
            "Refusing to run: GYANSETU_ENV=production. seed_dev.py is "
            "development-only; use GYANSETU_ENV=development to seed a local DB."
        )

    total = SeedSummary()

    # 1. School (created by natural key: code).
    school = db.execute(select(School).where(School.code == DEV_SCHOOL_CODE)).scalar_one_or_none()
    if school is None:
        school = School(
            name=DEV_SCHOOL_NAME,
            code=DEV_SCHOOL_CODE,
            district_id="dumka",
            district_name="Dumka",
            block_id="kathikund",
            block_name="Kathikund",
        )
        db.add(school)
        total.schools += 1
    # Materialise the school id (default applied on flush) so a freshly created
    # school can be referenced by the teacher below.
    db.flush()

    # 2. Teacher (created by natural key: mobile).
    teacher = db.execute(select(Teacher).where(Teacher.mobile == DEV_TEACHER_MOBILE)).scalar_one_or_none()
    if teacher is None:
        teacher = Teacher(
            id=DEV_TEACHER_ID,
            display_name=DEV_TEACHER_NAME,
            mobile=DEV_TEACHER_MOBILE,
            mobile_last4=DEV_TEACHER_MOBILE[-4:],
            school_id=school.id,
            school_code=school.code,
            password_hash=hash_password(DEV_TEACHER_PIN),
        )
        db.add(teacher)
        total.teachers += 1
    # Self-heal an older seed that missed the FK (fills the gap, never overwrites
    # a stored value).
    if teacher.school_id != school.id or teacher.school_code != school.code:
        teacher.school_id = school.id
        teacher.school_code = school.code

    # 3. Classroom setup (PK teacher_id).
    if db.get(ClassroomSetup, teacher.id) is None:
        db.add(
            ClassroomSetup(
                teacher_id=teacher.id,
                school_name=school.name,
                district_id=school.district_id,
                district_name=school.district_name,
                block_id=school.block_id,
                block_name=school.block_name,
                teaching_medium="hindi",
                target_language="santali",
                class_level=1,
                subjects=["foundationalLiteracy", "numeracy"],
                setup_completed=True,
                setup_completed_at=_iso_now(),
                pending_sync=False,
                schema_version=1,
            )
        )
        total.classroom_setups += 1

    # 4. Lessons + 5. Learning outcomes.
    for info in _LESSONS:
        if _created(db, Lesson, "id", info["id"],
                    title=info["title"], description=info["description"],
                    subject=info["subject"], class_number=1,
                    learning_outcome=info["outcome"],
                    duration_minutes=info["minutes"],
                    lesson_order=info["order"],
                    resource_ids=[f"{info['id']}.content", f"{info['id']}.audio"],
                    concepts=list(info.get("concepts") or []),
                    worksheet_resource_id=info.get("worksheet")):
            total.lessons += 1

    for info in _LEARNING_OUTCOMES:
        if _created(db, LearningOutcome, "id", info["id"],
                    code=info["code"], text=info["text"],
                    class_number=info["class_number"], subject=info["subject"],
                    language=info["language"],
                    curriculum_reference=info["curriculum_reference"]):
            total.learning_outcomes += 1

    # 5b. Downloadable content packs (real bytes + honest checksum/size).
    for rid, kind, name, subject, description, blob, lesson_id in _RESOURCE_PACKS():
        if _created(db, Resource, "id", rid,
                    kind=kind, name=name, description=description,
                    class_number=1, subject=subject, version="1",
                    lesson_id=lesson_id,
                    mime_type="application/json",
                    size_bytes=len(blob),
                    sha256=hashlib.sha256(blob).hexdigest(),
                    blob=blob):
            total.resources += 1

    # 6. Translations: only the documented Santali numerals (provenance authored).
    for value, _hindi, santali, devanagari in _SANTALI_NUMERALS:
        rid = f"c1-num-counting-1-10#sat#{value}"
        if _created(db, Translation, "id", rid,
                    lesson_id="c1-num-counting-1-10",
                    source_medium="hindi",
                    target_language="santali",
                    text=santali,
                    spoken_text=devanagari,
                    provenance="authored",
                    reviewed_by_speaker=False,
                    version=1):
            total.translations += 1

    # 7. Worksheets (teacher-owned sample sheets).
    for sheet in _WORKSHEETS:
        if _created(db, Worksheet, "id", sheet["id"],
                    teacher_id=teacher.id,
                    generated_at=_iso_now(),
                    **{k: v for k, v in sheet.items() if k != "id"}):
            total.worksheets += 1

    # 8. Assessment sample: lesson "Counting 1 to 10", 3 of 4 correct.
    started = _now(timedelta(minutes=-45))
    # Keyed by question id — the device's canonical answers shape
    # (QuizResult.fromJson/toJson), which the sync round-trip and GET
    # /assessments both agree on.
    ans = {
        "c1-q-count-1": {"questionId": "c1-q-count-1", "selectedOptionId": "5",
                         "correct": True, "answeredAt": _ts(started + timedelta(seconds=40)), "timeTakenMs": 9000},
        "c1-q-count-2": {"questionId": "c1-q-count-2", "selectedOptionId": "2",
                         "correct": False, "answeredAt": _ts(started + timedelta(seconds=70)), "timeTakenMs": 11000},
        "c1-q-count-3": {"questionId": "c1-q-count-3", "selectedOptionId": "4",
                         "correct": True, "answeredAt": _ts(started + timedelta(seconds=95)), "timeTakenMs": 8000},
        "c1-q-count-4": {"questionId": "c1-q-count-4", "selectedOptionId": "5",
                         "correct": True, "answeredAt": _ts(started + timedelta(seconds=120)), "timeTakenMs": 6500},
    }
    if _created(db, Assessment, "id", "assessment-c1-num-counting-1-10",
                teacher_id=teacher.id,
                lesson_id="c1-num-counting-1-10",
                score=3, total=4,
                concepts=[{"concept": "countingObjects", "correct": 3, "total": 4}],
                started_at=_ts(started),
                finished_at=_ts(started + timedelta(seconds=125)),
                answers=ans):
        total.assessments += 1

    # 9. One sample saved classroom session with two turns.
    started = _now(timedelta(hours=-1))
    if db.get(ClassroomSession, "DEV-CLS-COUNTING-1-10") is None:
        db.add(
            ClassroomSession(
                session_id="DEV-CLS-COUNTING-1-10",
                teacher_id=teacher.id,
                lesson_id="c1-num-counting-1-10",
                lesson_title="Counting 1 to 10",
                class_number=1,
                subject="numeracy",
                teaching_language="hindi",
                target_language="santali",
                started_at=_ts(started),
                ended_at=_ts(started + timedelta(minutes=30)),
                completed=True,
                saved_at=_ts(started + timedelta(minutes=30, seconds=1)),
                sync_status="synced",
                turns=[
                    {
                        "id": "dev-turn-1",
                        "sessionId": "DEV-CLS-COUNTING-1-10",
                        "speaker": "teacher",
                        "sourceLanguage": "hindi",
                        "targetLanguage": "santali",
                        "timestamp": _ts(started + timedelta(seconds=5)),
                        "status": "played",
                        "sourceText": "Count the apples.",
                        "translatedText": "सेबों को गिनो।",
                        "audioResourceId": None,
                        "metrics": None,
                        "confidence": None,
                        "failureMessage": None,
                        "translatedSpokenText": None,
                        "wasOffline": False,
                    },
                    {
                        "id": "dev-turn-2",
                        "sessionId": "DEV-CLS-COUNTING-1-10",
                        "speaker": "teacher",
                        "sourceLanguage": "hindi",
                        "targetLanguage": "santali",
                        "timestamp": _ts(started + timedelta(seconds=10)),
                        "status": "played",
                        "sourceText": "How many apples are there?",
                        "translatedText": "कितने सेब हैं?",
                        "audioResourceId": None,
                        "metrics": None,
                        "confidence": None,
                        "failureMessage": None,
                        "translatedSpokenText": None,
                        "wasOffline": False,
                    },
                ],
            )
        )
        total.classroom_sessions += 1

    # 10. A short progress trail on the counting lesson.
    trail = (
        ("lessonStarted", dict()),
        ("lessonCompleted", dict()),
        ("assessmentStarted", dict()),
        ("assessmentCompleted", {"score": "3"}),
        ("classroomSessionCompleted", {"sessionId": "DEV-CLS-COUNTING-1-10"}),
    )
    for index, (event_type, metadata) in enumerate(trail):
        occurred = _now(timedelta(hours=-1, minutes=index * 5))
        event_id = f"{event_type}#c1-num-counting-1-10"
        if db.get(ProgressEvent, event_id) is None:
            db.add(
                ProgressEvent(
                    id=event_id,
                    teacher_id=teacher.id,
                    type=event_type,
                    occurred_at=_ts(occurred),
                    lesson_id="c1-num-counting-1-10",
                    event_data=metadata,
                )
            )
            total.progress_events += 1

    return total


def main() -> None:
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    settings = get_settings()
    if settings.is_production:
        sys.exit(
            "Refusing to run: GYANSETU_ENV=production. seed_dev.py is "
            "development-only; use GYANSETU_ENV=development to seed a local DB."
        )

    import app.models  # noqa: F401  (register ORM models on Base.metadata)
    from app.db.base import Base

    engine = create_engine(
        settings.database_url,
        connect_args={"check_same_thread": False} if settings.is_sqlite else {},
    )
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine, autocommit=False, autoflush=False, future=True)

    with session_factory.begin() as db:  # single transaction; rollback on error
        summary = run(db, settings=settings)

    print(f"Seeded development database: {settings.database_url}")
    print(summary)
    print(
        f"Dev teacher: {DEV_TEACHER_NAME}  mobile={DEV_TEACHER_MOBILE}  "
        f"PIN={DEV_TEACHER_PIN}  (id {DEV_TEACHER_ID})."
    )
    if summary.total == 0:
        print("Nothing new to insert — the database was already seeded.")


if __name__ == "__main__":
    main()