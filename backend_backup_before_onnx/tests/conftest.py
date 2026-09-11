"""Pytest fixtures.

Tests run against a throwaway SQLite database per test (nothing touches a real
PostgreSQL or a developer database). The application's own engine is pointed at
a scratch database too, so even the startup table-creation hook stays out of
user data.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

_scratch_db = Path(tempfile.gettempdir()) / "gyansetu_pytest_app.db"
os.environ.setdefault("GYANSETU_DATABASE_URL", f"sqlite:///{_scratch_db}")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

from app.db.base import Base  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture()
def client(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'test.db'}",
        connect_args={"check_same_thread": False},
    )
    TestingSessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    engine.dispose()


def _register(
    client,
    *,
    display_name: str = "Asha Devi",
    mobile: str = "9876543210",
    password: str = "secret123",
    school_code: str | None = "JH-001",
    school_name: str | None = "MS Ranchi",
):
    body: dict = {"displayName": display_name, "password": password, "mobile": mobile}
    if school_code:
        body["schoolCode"] = school_code
    if school_name:
        body["schoolName"] = school_name
    response = client.post("/api/v1/auth/register", json=body)
    response.raise_for_status()
    data = response.json()
    return {
        "headers": {"Authorization": f"Bearer {data['accessToken']}"},
        "account": data["account"],
        "school": data["school"],
        "token": data["accessToken"],
    }


@pytest.fixture()
def auth(client):
    """A registered teacher, ready to call authenticated endpoints."""

    def make(**kwargs):
        return _register(client, **kwargs)

    return make


def _cleanup_scratch():
    try:
        _scratch_db.unlink(missing_ok=True)
    except OSError:
        pass


def pytest_sessionfinish(session, exitstatus):  # noqa: ARG001
    _cleanup_scratch()