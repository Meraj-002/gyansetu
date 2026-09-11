"""Tests for the development seed script (scripts/seed_dev.py).

A dedicated, throwaway SQLite database is created per test (like conftest) and
seeded through the same ``run()`` entry point ``python -m scripts.seed_dev``
uses, so the script and the FastAPI app in the test share one database.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker

from app.core.security import verify_password
from app.db.base import Base
from app.db.session import get_db
from app.main import app
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
from scripts.seed_dev import (
    DEV_SCHOOL_CODE,
    DEV_TEACHER_ID,
    DEV_TEACHER_MOBILE,
    DEV_TEACHER_NAME,
    DEV_TEACHER_PIN,
    run,
)

EXPECTED = {
    "schools": 1,
    "teachers": 1,
    "classroom_setups": 1,
    "students": 0,
    "lessons": 9,
    "learning_outcomes": 9,
    "translations": 5,
    "worksheets": 3,
    "assessments": 1,
    "classroom_sessions": 1,
    "progress_events": 5,
    "resources": 24,  # 9 content + 9 audio + 3 worksheet + 1 flashcard + 2 translation
}


@pytest.fixture()
def seed_db(tmp_path):
    """An empty database, returned as (session_factory, engine)."""
    engine = create_engine(
        f"sqlite:///{tmp_path / 'seed.db'}",
        connect_args={"check_same_thread": False},
    )
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False, future=True)
    Base.metadata.create_all(bind=engine)
    yield SessionLocal, engine
    engine.dispose()


@pytest.fixture()
def seeded(seed_db):
    SessionLocal, engine = seed_db
    with SessionLocal.begin() as db:
        run(db)
    return seed_db


def _counts(db) -> dict[str, int]:
    def count(model) -> int:
        return int(db.scalar(select(func.count()).select_from(model)) or 0)

    return {
        "schools": count(School),
        "teachers": count(Teacher),
        "classroom_setups": count(ClassroomSetup),
        "students": 0,
        "lessons": count(Lesson),
        "learning_outcomes": count(LearningOutcome),
        "translations": count(Translation),
        "worksheets": count(Worksheet),
        "assessments": count(Assessment),
        "classroom_sessions": count(ClassroomSession),
        "progress_events": count(ProgressEvent),
        "resources": count(Resource),
    }


def test_seed_creates_expected_rows(seeded):
    SessionLocal, _engine = seeded
    with SessionLocal() as db:
        assert _counts(db) == EXPECTED


def test_seed_is_idempotent(seed_db):
    SessionLocal, _engine = seed_db
    with SessionLocal.begin() as db:
        first = run(db)
    with SessionLocal.begin() as db:
        second = run(db)
    assert first.total == sum(EXPECTED.values())  # every planned row inserted once
    assert second.total == 0  # nothing re-inserted
    with SessionLocal() as db:
        assert _counts(db) == EXPECTED


def test_seed_refuses_to_run_in_production(seed_db):
    SessionLocal, _engine = seed_db

    class _Production:
        is_production = True

    with SessionLocal.begin() as db:
        with pytest.raises(SystemExit):
            run(db, settings=_Production())  # type: ignore[arg-type]
        assert db.get(Teacher, DEV_TEACHER_ID) is None  # nothing written


def test_seeded_teacher_login_round_trip(seeded):
    SessionLocal, _engine = seeded
    with SessionLocal() as db:
        teacher = db.scalar(select(Teacher).where(Teacher.mobile == DEV_TEACHER_MOBILE))
        assert teacher is not None
        assert teacher.display_name == DEV_TEACHER_NAME
        assert teacher.school_code == DEV_SCHOOL_CODE
        assert teacher.school_id is not None  # FK to the seeded school
        assert verify_password(DEV_TEACHER_PIN, teacher.password_hash)


@pytest.fixture()
def api(seeded):
    _, engine = seeded
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False, future=True)

    def override_get_db():
        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _login_headers(api):
    response = api.post(
        "/api/v1/auth/login",
        json={
            "identifier": DEV_TEACHER_MOBILE,
            "password": DEV_TEACHER_PIN,
            "schoolCode": DEV_SCHOOL_CODE,
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def test_seeded_api_exposes_catalogue_and_vocabulary(api):
    lessons = api.get("/api/v1/lessons?classNumber=1")
    assert lessons.status_code == 200
    assert len(lessons.json()) == EXPECTED["lessons"]
    first = lessons.json()[0]
    assert first["id"] == "c1-num-counting-1-10"
    assert first["worksheetResourceId"] == "c1-ws-counting-1-10"  # camelCase wire
    assert first["subject"] == "numeracy" and first["classNumber"] == 1

    outcomes = api.get("/api/v1/learning-outcomes?classNumber=1")
    assert len(outcomes.json()) == EXPECTED["learning_outcomes"]

    translations = api.get(
        "/api/v1/translations",
        params={"lessonId": "c1-num-counting-1-10", "targetLanguage": "santali"},
    )
    assert len(translations.json()) == EXPECTED["translations"]
    for row in translations.json():
        assert row["provenance"] == "authored"
        assert row["reviewedBySpeaker"] is False
        assert row["spokenText"]  # Devanagari rendering present


def test_seeded_api_serves_downloadable_content_packs(api):
    # The resource catalogue is public, like the lesson catalogue.
    resources = api.get("/api/v1/resources?classNumber=1&limit=200")
    assert resources.status_code == 200
    rows = resources.json()
    assert len(rows) == EXPECTED["resources"]

    kinds = {}
    for row in rows:
        kinds[row["kind"]] = kinds.get(row["kind"], 0) + 1
    assert kinds == {"content": 9, "audio": 9, "worksheet": 3,
                     "flashcard": 1, "translation": 2}

    counting = next(row for row in rows if row["id"] == "c1-num-counting-1-10.content")
    assert counting["sizeBytes"] > 0
    assert len(counting["sha256"]) == 64
    assert counting["lessonId"] == "c1-num-counting-1-10"
    assert counting["version"] == "1"

    # Every pack the catalogue advertises streams back byte-for-byte with the
    # promised checksum — the client's "Ready" gate depends on this.
    for row in rows[:3]:
        content = api.get(f"/api/v1/resources/{row['id']}/content")
        assert content.status_code == 200
        assert content.headers["x-checksum-sha256"] == row["sha256"]
        assert content.headers["content-length"] == str(row["sizeBytes"])
        import hashlib

        assert hashlib.sha256(content.content).hexdigest() == row["sha256"]


def test_seeded_api_exposes_teacher_owned_records(api):
    headers = _login_headers(api)

    worksheets = api.get("/api/v1/worksheets", headers=headers)
    assert len(worksheets.json()) == EXPECTED["worksheets"]
    questions = worksheets.json()[0]["questions"]
    assert len(questions) >= 3
    assert all(isinstance(q["correctAnswer"], str) for q in questions)
    assert all(isinstance(q["options"], list) for q in questions)

    assessments = api.get(
        "/api/v1/assessments",
        params={"lessonId": "c1-num-counting-1-10"},
        headers=headers,
    )
    assert len(assessments.json()) == 1
    row = assessments.json()[0]
    assert row["score"] == 3 and row["total"] == 4
    # The canonical device shape: answers is a map keyed by question id.
    assert isinstance(row["answers"], dict)
    assert row["answers"]["c1-q-count-1"]["selectedOptionId"] == "5"

    sessions = api.get("/api/v1/sessions", headers=headers)
    assert len(sessions.json()) == EXPECTED["classroom_sessions"]
    assert sessions.json()[0]["sessionId"] == "DEV-CLS-COUNTING-1-10"
    assert len(sessions.json()[0]["turns"]) == 2

    progress = api.get("/api/v1/progress", headers=headers)
    assert len(progress.json()) == EXPECTED["progress_events"]
    types = {event["type"] for event in progress.json()}
    assert {"lessonStarted", "lessonCompleted", "assessmentCompleted"} <= types


def test_seeded_account_sync_pull(api):
    headers = _login_headers(api)
    response = api.post(
        "/api/v1/sync/pull",
        json={"since": None, "includeCatalog": True},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()

    catalog = body["catalog"] or []
    assert sum(1 for doc in catalog if doc["type"] == "lesson") == EXPECTED["lessons"]
    assert (
        sum(1 for doc in catalog if doc["type"] == "learningOutcome")
        == EXPECTED["learning_outcomes"]
    )
    lesson_doc = next(doc for doc in catalog if doc["id"] == "c1-num-counting-1-10")
    assert lesson_doc["data"]["createdAt"]  # Lesson.fromJson strict-parses this
    assert lesson_doc["data"]["updatedAt"]

    documents = body["documents"]
    kinds = {}
    for doc in documents:
        kinds[doc["type"]] = kinds.get(doc["type"], 0) + 1
    assert kinds["classroomSetup"] == 1
    assert kinds["worksheet"] == EXPECTED["worksheets"]
    assert kinds["assessmentResult"] == EXPECTED["assessments"]
    assert kinds["classroomSession"] == EXPECTED["classroom_sessions"]
    assert kinds["progressEvent"] == EXPECTED["progress_events"]