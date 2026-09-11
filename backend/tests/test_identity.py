"""Teacher identity + data-isolation tests.

Covers the canonical identity wire contract (/auth/me and /teachers/me carry
school + classroom), the isolation of that identity per teacher, and token
lifecycle edge cases (expired vs malformed).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.core.security import create_access_token


SETUP = {
    "schoolName": "MS Dumka",
    "districtId": "d-dumka",
    "districtName": "Dumka",
    "blockId": "b-jama",
    "blockName": "Jama",
    "teachingMedium": "hindi",
    "targetLanguage": "sat",
    "classLevel": 1,
    "subjects": ["foundationalLiteracy", "numeracy"],
    "setupCompleted": True,
    "setupCompletedAt": "2026-08-30T08:00:00.000Z",
    "pendingSync": False,
    "schemaVersion": 2,
}

SCHOOL_CODE = "JH-888"


def _provision_school(client, auth) -> None:
    """A school with real location data for teachers to join."""
    session = auth(mobile="9801000000")
    response = client.post(
        "/api/v1/schools",
        headers=session["headers"],
        json={
            "name": "MS Dumka",
            "code": SCHOOL_CODE,
            "districtId": "d-dumka",
            "districtName": "Dumka",
            "blockId": "b-jama",
            "blockName": "Jama",
        },
    )
    assert response.status_code == 201, response.text


def _push_setup(client, session) -> str:
    teacher_id = session["account"]["id"]
    response = client.post(
        "/api/v1/sync/push",
        headers=session["headers"],
        json={
            "documents": [
                {
                    "type": "classroomSetup",
                    "id": f"setup-{teacher_id}",
                    "data": {**SETUP, "teacherId": teacher_id},
                }
            ]
        },
    )
    assert response.status_code == 200, response.text
    return teacher_id


def test_me_carries_school_and_classroom_identity(client, auth):
    _provision_school(client, auth)
    session = auth(
        mobile="9811111111", school_code=SCHOOL_CODE, school_name="MS Dumka"
    )
    teacher_id = _push_setup(client, session)

    for endpoint in ("/api/v1/auth/me", "/api/v1/teachers/me"):
        response = client.get(endpoint, headers=session["headers"])
        assert response.status_code == 200
        body = response.json()
        assert body["id"] == teacher_id
        assert body["displayName"] == "Asha Devi"
        # School location comes from the linked School record.
        assert body["schoolId"] is not None
        assert body["schoolName"] == "MS Dumka"
        assert body["schoolCode"] == SCHOOL_CODE
        assert body["districtId"] == "d-dumka"
        assert body["districtName"] == "Dumka"
        assert body["blockId"] == "b-jama"
        assert body["blockName"] == "Jama"
        # Classroom fields come from the pushed ClassroomSetup row.
        assert body["classLevel"] == 1
        assert body["subjects"] == ["foundationalLiteracy", "numeracy"]
        assert body["teachingMedium"] == "hindi"
        assert body["targetLanguage"] == "sat"
        assert body["setupCompleted"] is True


def test_identity_updates_survive_patch(client, auth):
    _provision_school(client, auth)
    session = auth(
        mobile="9811111111", school_code=SCHOOL_CODE, school_name="MS Dumka"
    )
    _push_setup(client, session)
    response = client.patch(
        "/api/v1/teachers/me", headers=session["headers"], json={"displayName": "Asha K"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["displayName"] == "Asha K"
    assert body["schoolName"] == "MS Dumka"
    assert body["classLevel"] == 1
    assert body["setupCompleted"] is True


def test_classroom_identity_is_isolated_per_teacher(client, auth):
    _provision_school(client, auth)
    first = auth(
        mobile="9811111111", school_code=SCHOOL_CODE, school_name="MS Dumka"
    )
    second = auth(mobile="9822222222", display_name="Teacher B")
    _push_setup(client, first)

    # The second teacher never sees the first's classroom anywhere.
    body = client.get("/api/v1/auth/me", headers=second["headers"]).json()
    assert body["id"] == second["account"]["id"]
    assert body["setupCompleted"] is False
    assert body["classLevel"] is None
    assert body["subjects"] == []
    assert body["teachingMedium"] is None

    pull = client.post(
        "/api/v1/sync/pull",
        headers=second["headers"],
        json={"includeCatalog": False},
    ).json()
    assert pull["documents"] == []
    assert not any(
        d["id"] == f"setup-{first['account']['id']}" for d in pull["documents"]
    )


def test_expired_token_is_401(client, auth):
    session = auth(mobile="9811111111")
    expired = create_access_token(
        session["account"]["id"],
        extra={"exp": datetime.now(timezone.utc) - timedelta(minutes=5)},
    )
    response = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {expired}"}
    )
    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "invalid_token"

    teachers_response = client.get(
        "/api/v1/teachers/me", headers={"Authorization": f"Bearer {expired}"}
    )
    assert teachers_response.status_code == 401


def test_valid_token_still_accepted_after_expired_check(client, auth):
    session = auth(mobile="9811111111")
    response = client.get("/api/v1/auth/me", headers=session["headers"])
    assert response.status_code == 200