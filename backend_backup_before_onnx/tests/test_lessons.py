"""Lesson catalogue CRUD tests."""

LESSON = {
    "title": "Count to Five",
    "description": "First counting lesson",
    "subject": "numeracy",
    "classNumber": 1,
    "learningOutcome": "Count objects 1-5",
    "durationMinutes": 30,
    "lessonOrder": 1,
    "concepts": ["countingObjects"],
    "resourceIds": ["pack-1"],
}


def test_create_lesson_outputs_flutter_shape(client, auth):
    session = auth(mobile="9811111111")
    response = client.post("/api/v1/lessons", headers=session["headers"], json=LESSON)
    assert response.status_code == 201
    body = response.json()
    assert body["subject"] == "numeracy"
    assert body["classNumber"] == 1
    assert body["concepts"] == ["countingObjects"]
    assert body["resourceIds"] == ["pack-1"]
    assert body["createdAt"] and body["updatedAt"]


def test_lesson_list_filters(client, auth):
    session = auth(mobile="9811111111")
    client.post("/api/v1/lessons", headers=session["headers"], json=LESSON)
    client.post(
        "/api/v1/lessons",
        headers=session["headers"],
        json={**LESSON, "title": "FLN", "subject": "foundationalLiteracy", "classNumber": 2},
    )
    assert len(client.get("/api/v1/lessons").json()) == 2
    assert len(client.get("/api/v1/lessons", params={"classNumber": 1}).json()) == 1
    assert len(client.get("/api/v1/lessons", params={"subject": "numeracy"}).json()) == 1


def test_lesson_get_update_delete(client, auth):
    session = auth(mobile="9811111111")
    lesson_id = client.post(
        "/api/v1/lessons", headers=session["headers"], json=LESSON
    ).json()["id"]

    assert client.get(f"/api/v1/lessons/{lesson_id}").status_code == 200
    assert client.get("/api/v1/lessons/missing").status_code == 404

    patched = client.patch(
        f"/api/v1/lessons/{lesson_id}",
        headers=session["headers"],
        json={"title": "Count to Ten"},
    )
    assert patched.status_code == 200
    assert patched.json()["title"] == "Count to Ten"

    assert client.delete(f"/api/v1/lessons/{lesson_id}", headers=session["headers"]).status_code == 204
    assert client.get(f"/api/v1/lessons/{lesson_id}").status_code == 404


def test_lesson_mutations_require_auth(client):
    assert client.post("/api/v1/lessons", json=LESSON).status_code == 401
    assert client.patch("/api/v1/lessons/x", json={}).status_code == 401


def test_lesson_invalid_subject_is_422(client, auth):
    session = auth(mobile="9811111111")
    response = client.post(
        "/api/v1/lessons",
        headers=session["headers"],
        json={**LESSON, "subject": "physics"},
    )
    assert response.status_code == 422