"""Worksheet endpoints tests."""

WORKSHEET = {
    "id": "ws-1",
    "lessonId": "L-1",
    "title": "Counting Worksheet",
    "learningOutcome": "Count 1-5",
    "classNumber": 1,
    "subject": "numeracy",
    "teachingLanguage": "hindi",
    "targetLanguage": "sat",
    "difficulty": "easy",
    "questions": [
        {
            "id": "q1",
            "type": "countingObjects",
            "questionText": "How many apples?",
            "options": [{"id": "a", "text": "3"}, {"id": "b", "text": "5"}],
            "correctAnswer": "a",
        }
    ],
    "visualExamples": [{"name": "apples", "glyph": "🍎"}],
    "culturallyFamiliarExamples": True,
    "variant": 0,
    "requestedQuestionCount": 5,
    "generationSource": "localOffline",
}


def test_create_and_get_own_worksheet(client, auth):
    session = auth(mobile="9811111111")
    created = client.post("/api/v1/worksheets", headers=session["headers"], json=WORKSHEET)
    assert created.status_code == 201
    body = created.json()
    assert body["id"] == "ws-1"
    assert body["teacherId"] == session["account"]["id"]
    assert body["difficulty"] == "easy"
    assert body["generationSource"] == "localOffline"
    assert body["questions"][0]["questionText"] == "How many apples?"

    got = client.get("/api/v1/worksheets/ws-1", headers=session["headers"])
    assert got.status_code == 200


def test_create_without_id_is_400(client, auth):
    session = auth(mobile="9811111111")
    payload = {k: v for k, v in WORKSHEET.items() if k != "id"}
    response = client.post("/api/v1/worksheets", headers=session["headers"], json=payload)
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "id_required"


def test_list_is_scoped_to_own_teacher(client, auth):
    first = auth(mobile="9811111111")
    second = auth(mobile="9822222222", display_name="Teacher B")
    client.post("/api/v1/worksheets", headers=first["headers"], json=WORKSHEET)
    client.post(
        "/api/v1/worksheets",
        headers=second["headers"],
        json={**WORKSHEET, "id": "ws-2", "title": "Second"},
    )
    listing = client.get("/api/v1/worksheets", headers=first["headers"])
    assert [w["id"] for w in listing.json()] == ["ws-1"]


def test_forbidden_to_read_or_delete_other_teacher(client, auth):
    first = auth(mobile="9811111111")
    second = auth(mobile="9822222222", display_name="Teacher B")
    client.post("/api/v1/worksheets", headers=first["headers"], json=WORKSHEET)
    other = client.get("/api/v1/worksheets/ws-1", headers=second["headers"])
    assert other.status_code == 403
    assert other.json()["detail"]["code"] == "forbidden"


def test_delete_own_worksheet(client, auth):
    session = auth(mobile="9811111111")
    client.post("/api/v1/worksheets", headers=session["headers"], json=WORKSHEET)
    assert (
        client.delete("/api/v1/worksheets/ws-1", headers=session["headers"]).status_code == 204
    )
    assert client.get("/api/v1/worksheets/ws-1", headers=session["headers"]).status_code == 404