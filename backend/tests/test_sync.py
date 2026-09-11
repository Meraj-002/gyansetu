"""Sync push/pull/status tests.

Wire contract (see app/schemas/sync.py):

* push body: ``{"deviceId": ..., "documents": [{type, id, data}, ...]}``
* push response: ``{acknowledged: [...], conflicts: [...], errors: [...], serverNow}``
* pull body: ``{since, deviceId, includeCatalog}``
* pull response: ``{since, serverNow, documents: [{type, id, updatedAt, data}], catalog}``
* status: ``{status, serverTime, counts}``
"""

SETUP = {
    "teacherId": None,
    "schoolName": "MS Ranchi",
    "districtId": "d1",
    "districtName": "Ranchi",
    "blockId": "b1",
    "blockName": "Khunti",
    "teachingMedium": "hindi",
    "targetLanguage": "sat",
    "classLevel": 1,
    "subjects": ["foundationalLiteracy", "numeracy"],
    "setupCompleted": True,
    "setupCompletedAt": "2026-08-30T08:00:00.000Z",
    "pendingSync": False,
    "schemaVersion": 2,
}

SESSION_DATA = {
    "lessonId": "L-1",
    "lessonTitle": "Count",
    "classNumber": 1,
    "subject": "numeracy",
    "teachingLanguage": "hindi",
    "targetLanguage": "sat",
    "startedAt": "2026-08-30T10:30:00.000Z",
    "completed": False,
    "turns": [],
}

WORKSHEET_DATA = {
    "lessonId": "L-1",
    "title": "WS",
    "classNumber": 1,
    "subject": "numeracy",
    "difficulty": "easy",
    "questions": [],
    "generationSource": "localOffline",
    "createdAt": "2026-08-30T10:00:00.000Z",
}

ASSESSMENT_DATA = {
    "lessonId": "L-1",
    "score": 3,
    "total": 4,
    "concepts": [],
    "answers": {},
    "startedAt": "2026-08-30T11:00:00.000Z",
    "finishedAt": "2026-08-30T11:02:00.000Z",
}

EVENT_DATA = {
    "type": "lessonCompleted",
    "occurredAt": "2026-08-30T09:00:00.000Z",
    "metadata": {"durationMinutes": "15"},
}

REPORT_DATA = {
    "message": "App crashes",
    "createdAt": "2026-08-30T12:00:00.000Z",
}


def test_empty_status(client, auth):
    session = auth(mobile="9811111111")
    response = client.get("/api/v1/sync/status", headers=session["headers"])
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["serverTime"]
    assert body["counts"]["classroomSetup"] == 0
    assert body["counts"]["classroomSession"] == 0


def test_push_acknowledges_all_doc_types(client, auth):
    session = auth(mobile="9811111111")
    teacher_id = session["account"]["id"]
    documents = [
        {"type": "classroomSetup", "id": f"setup-{teacher_id}", "data": {**SETUP, "teacherId": teacher_id}},
        {"type": "classroomSession", "id": "CLS-300826-1030", "data": SESSION_DATA},
        {"type": "worksheet", "id": "ws-1", "data": WORKSHEET_DATA},
        {"type": "assessmentResult", "id": "ass-1", "data": ASSESSMENT_DATA},
        {"type": "progressEvent", "id": "ev-1", "data": EVENT_DATA},
        {"type": "supportReport", "id": "sr-1", "data": REPORT_DATA},
    ]
    response = client.post(
        "/api/v1/sync/push",
        headers=session["headers"],
        json={"deviceId": "dev-1", "documents": documents},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["acknowledged"]) == 6, body
    assert body["conflicts"] == [], body
    assert body["errors"] == [], body
    assert body["serverNow"]
    assert {r["type"] for r in body["acknowledged"]} == {
        "classroomSetup",
        "classroomSession",
        "worksheet",
        "assessmentResult",
        "progressEvent",
        "supportReport",
    }


def test_repush_is_idempotent(client, auth):
    session = auth(mobile="9811111111")
    teacher_id = session["account"]["id"]
    doc = {"type": "classroomSetup", "id": f"setup-{teacher_id}", "data": {**SETUP, "teacherId": teacher_id}}
    first = client.post(
        "/api/v1/sync/push", headers=session["headers"], json={"documents": [doc]}
    )
    second = client.post(
        "/api/v1/sync/push", headers=session["headers"], json={"documents": [doc]}
    )
    assert first.json()["acknowledged"][0]["accepted"] is True
    assert second.json()["acknowledged"][0]["accepted"] is True

    status = client.get("/api/v1/sync/status", headers=session["headers"]).json()
    assert status["counts"]["classroomSetup"] == 1
    assert status["counts"]["classroomSession"] == 0


def test_pull_returns_pushed_docs_with_metadata_mapping(client, auth):
    session = auth(mobile="9811111111")
    teacher_id = session["account"]["id"]
    client.post(
        "/api/v1/sync/push",
        headers=session["headers"],
        json={
            "documents": [
                {"type": "classroomSetup", "id": f"setup-{teacher_id}", "data": {**SETUP, "teacherId": teacher_id}},
                {"type": "progressEvent", "id": "ev-1", "data": EVENT_DATA},
            ]
        },
    )

    pull = client.post(
        "/api/v1/sync/pull",
        headers=session["headers"],
        json={"since": "2000-01-01T00:00:00.000Z"},
    )
    assert pull.status_code == 200
    body = pull.json()
    assert body["serverNow"]

    by_type = {d["type"]: d for d in body["documents"]}
    assert "classroomSetup" in by_type
    assert by_type["classroomSetup"]["data"]["teacherId"] == teacher_id
    assert "progressEvent" in by_type
    assert by_type["progressEvent"]["id"] == "ev-1"
    assert by_type["progressEvent"]["data"]["metadata"] == {"durationMinutes": "15"}


def test_pull_since_excludes_older_but_always_returns_setup(client, auth):
    session = auth(mobile="9811111111")
    teacher_id = session["account"]["id"]
    pushed = client.post(
        "/api/v1/sync/push",
        headers=session["headers"],
        json={
            "documents": [
                {"type": "classroomSetup", "id": f"setup-{teacher_id}", "data": {**SETUP, "teacherId": teacher_id}},
                {"type": "worksheet", "id": "ws-1", "data": WORKSHEET_DATA},
            ]
        },
    )
    server_now = pushed.json()["serverNow"]

    pull = client.post(
        "/api/v1/sync/pull", headers=session["headers"], json={"since": server_now}
    )
    types = {d["type"] for d in pull.json()["documents"]}
    # classroomSetup is a single row always returned; newer documents are excluded.
    assert "worksheet" not in types
    assert "classroomSetup" in types


def test_pull_includes_catalog(client, auth):
    session = auth(mobile="9811111111")
    client.post(
        "/api/v1/lessons",
        headers=session["headers"],
        json={
            "title": "Count",
            "subject": "numeracy",
            "classNumber": 1,
            "learningOutcome": "LO",
            "durationMinutes": 20,
        },
    )
    client.post(
        "/api/v1/learning-outcomes",
        headers=session["headers"],
        json={"text": "Counts 1-5", "classNumber": 1, "subject": "numeracy"},
    )
    pull = client.post(
        "/api/v1/sync/pull",
        headers=session["headers"],
        json={"since": "2000-01-01T00:00:00.000Z", "includeCatalog": True},
    )
    body = pull.json()
    assert body["catalog"] is not None
    types = {d["type"] for d in body["catalog"]}
    assert "lesson" in types
    assert "learningOutcome" in types


def test_unknown_doc_type_is_422(client, auth):
    session = auth(mobile="9811111111")
    response = client.post(
        "/api/v1/sync/push",
        headers=session["headers"],
        json={"documents": [{"type": "bananas", "id": "x", "data": {}}]},
    )
    assert response.status_code == 422


def test_owner_conflict_is_a_conflict_result(client, auth):
    session = auth(mobile="9811111111")
    response = client.post(
        "/api/v1/sync/push",
        headers=session["headers"],
        json={
            "documents": [
                {
                    "type": "classroomSetup",
                    "id": "setup-other",
                    "data": {**SETUP, "teacherId": "someone-else"},
                }
            ]
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["acknowledged"] == []
    assert body["conflicts"][0]["error"] == "owner_mismatch"


def test_sync_requires_auth(client):
    assert client.post("/api/v1/sync/push", json={"documents": []}).status_code == 401
    assert client.post("/api/v1/sync/pull", json={}).status_code == 401
    assert client.get("/api/v1/sync/status").status_code == 401