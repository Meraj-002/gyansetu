"""Classroom session endpoints tests."""

SESSION = {
    "sessionId": "CLS-300826-1030",
    "lessonId": "L-1",
    "lessonTitle": "Count to Five",
    "classNumber": 1,
    "subject": "numeracy",
    "teachingLanguage": "hindi",
    "targetLanguage": "sat",
    "startedAt": "2026-08-30T10:30:00.000Z",
    "endedAt": "2026-08-30T10:35:00.000Z",
    "completed": True,
    "turns": [{"id": "t1", "speaker": "student", "sourceText": "ara vaarta"}],
}


def test_create_and_list(client, auth):
    session = auth(mobile="9811111111")
    created = client.post("/api/v1/sessions", headers=session["headers"], json=SESSION)
    assert created.status_code == 201
    body = created.json()
    assert body["sessionId"] == "CLS-300826-1030"
    assert body["teacherId"] == session["account"]["id"]
    assert body["completed"] is True
    assert body["turns"][0]["sourceText"] == "ara vaarta"

    listing = client.get("/api/v1/sessions", headers=session["headers"])
    assert [s["sessionId"] for s in listing.json()] == ["CLS-300826-1030"]


def test_upsert_by_session_id_is_idempotent(client, auth):
    session = auth(mobile="9811111111")
    assert (
        client.put(
            "/api/v1/sessions/CLS-300826-1030", headers=session["headers"], json=SESSION
        ).status_code
        == 200
    )
    # Update the same session: turns grow, no duplicate row.
    updated = client.put(
        "/api/v1/sessions/CLS-300826-1030",
        headers=session["headers"],
        json={**SESSION, "turns": SESSION["turns"] + [{"id": "t2", "speaker": "teacher"}]},
    )
    assert updated.status_code == 200
    assert len(updated.json()["turns"]) == 2
    listing = client.get("/api/v1/sessions", headers=session["headers"])
    assert len(listing.json()) == 1


def test_put_id_mismatch_is_400(client, auth):
    session = auth(mobile="9811111111")
    response = client.put(
        "/api/v1/sessions/DIFFERENT", headers=session["headers"], json=SESSION
    )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "id_mismatch"


def test_get_delete_and_other_teacher(client, auth):
    first = auth(mobile="9811111111")
    second = auth(mobile="9822222222", display_name="B")
    client.post("/api/v1/sessions", headers=first["headers"], json=SESSION)

    got = client.get("/api/v1/sessions/CLS-300826-1030", headers=first["headers"])
    assert got.status_code == 200

    assert (
        client.get("/api/v1/sessions/CLS-300826-1030", headers=second["headers"]).status_code
        == 403
    )

    assert (
        client.delete(
            "/api/v1/sessions/CLS-300826-1030", headers=first["headers"]
        ).status_code
        == 204
    )
    assert client.get("/api/v1/sessions/CLS-300826-1030", headers=first["headers"]).status_code == 404