"""Assessment (quiz result) endpoints tests.

The canonical `answers` shape is the device's map keyed by question id
(QuizResult.toJson()). The schema rejects a list so a legacy shape can never
creep back in, and the round-trip below pins it end to end.
"""

ASSESSMENT = {
    "lessonId": "L-1",
    "score": 3,
    "total": 4,
    "concepts": [{"concept": "countingObjects", "correct": 3, "total": 4}],
    "startedAt": "2026-08-30T10:00:00.000Z",
    "finishedAt": "2026-08-30T10:04:00.000Z",
    "answers": {"q1": {"questionId": "q1", "selectedOptionId": "a"}},
}


def test_create_generates_id_when_missing(client, auth):
    session = auth(mobile="9811111111")
    created = client.post("/api/v1/assessments", headers=session["headers"], json=ASSESSMENT)
    assert created.status_code == 201
    body = created.json()
    assert body["id"]
    assert body["teacherId"] == session["account"]["id"]
    assert body["score"] == 3
    assert body["total"] == 4
    assert body["concepts"][0]["correct"] == 3


def test_create_with_client_id_and_answers_map(client, auth):
    session = auth(mobile="9811111111")
    payload = {**ASSESSMENT, "id": "ass-1"}
    assert client.post("/api/v1/assessments", headers=session["headers"], json=payload).status_code == 201

    listing = client.get("/api/v1/assessments", headers=session["headers"])
    assert [a["id"] for a in listing.json()] == ["ass-1"]

    by_lesson = client.get("/api/v1/assessments", headers=session["headers"], params={"lessonId": "L-1"})
    assert len(by_lesson.json()) == 1


def test_answers_round_trip_as_the_device_map(client, auth):
    session = auth(mobile="9811111111")
    client.post(
        "/api/v1/assessments",
        headers=session["headers"],
        json={**ASSESSMENT, "id": "ass-rt"},
    )
    row = client.get(
        "/api/v1/assessments/ass-rt", headers=session["headers"]
    ).json()
    assert row["answers"] == {"q1": {"questionId": "q1", "selectedOptionId": "a"}}


def test_legacy_list_shaped_answers_is_rejected(client, auth):
    """The canonical wire shape is a map; a list is the old bug, not an accepted
    form. This pins the contract at the schema layer instead of a UI conversion."""
    session = auth(mobile="9811111111")
    payload = {**ASSESSMENT, "answers": [{"questionId": "q1", "selectedOptionId": "a"}]}
    response = client.post("/api/v1/assessments", headers=session["headers"], json=payload)
    assert response.status_code == 422


def test_duplicate_client_id_is_409(client, auth):
    session = auth(mobile="9811111111")
    payload = {**ASSESSMENT, "id": "ass-1"}
    assert client.post("/api/v1/assessments", headers=session["headers"], json=payload).status_code == 201
    duplicate = client.post("/api/v1/assessments", headers=session["headers"], json=payload)
    assert duplicate.status_code == 409
    assert duplicate.json()["detail"]["code"] == "already_exists"


def test_other_teacher_forbidden(client, auth):
    first = auth(mobile="9811111111")
    second = auth(mobile="9822222222", display_name="B")
    client.post(
        "/api/v1/assessments",
        headers=first["headers"],
        json={**ASSESSMENT, "id": "ass-1"},
    )
    assert client.get("/api/v1/assessments/ass-1", headers=second["headers"]).status_code == 403
    assert (
        client.delete("/api/v1/assessments/ass-1", headers=second["headers"]).status_code == 403
    )


def test_delete_own_assessment(client, auth):
    session = auth(mobile="9811111111")
    client.post(
        "/api/v1/assessments", headers=session["headers"], json={**ASSESSMENT, "id": "ass-1"}
    )
    assert (
        client.delete("/api/v1/assessments/ass-1", headers=session["headers"]).status_code == 204
    )