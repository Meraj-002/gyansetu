"""Progress event endpoints tests."""

EVENT = {
    "id": "ev-1",
    "type": "lessonCompleted",
    "occurredAt": "2026-08-30T09:00:00.000Z",
    "lessonId": "L-1",
    "metadata": {"durationMinutes": "15"},
}


def test_create_and_list(client, auth):
    session = auth(mobile="9811111111")
    created = client.post("/api/v1/progress", headers=session["headers"], json=EVENT)
    assert created.status_code == 201
    assert created.json()["metadata"] == {"durationMinutes": "15"}

    listing = client.get("/api/v1/progress", headers=session["headers"])
    assert listing.status_code == 200
    assert [e["id"] for e in listing.json()] == ["ev-1"]


def test_filter_by_type(client, auth):
    session = auth(mobile="9811111111")
    client.post("/api/v1/progress", headers=session["headers"], json=EVENT)
    client.post(
        "/api/v1/progress",
        headers=session["headers"],
        json={**EVENT, "id": "ev-2", "type": "assessmentCompleted"},
    )
    only_lessons = client.get("/api/v1/progress", headers=session["headers"], params={"type": "lessonCompleted"})
    assert [e["id"] for e in only_lessons.json()] == ["ev-1"]


def test_upsert_is_idempotent(client, auth):
    session = auth(mobile="9811111111")
    client.post("/api/v1/progress", headers=session["headers"], json=EVENT)
    client.post(
        "/api/v1/progress",
        headers=session["headers"],
        json={**EVENT, "metadata": {"durationMinutes": "20"}},
    )
    listing = client.get("/api/v1/progress", headers=session["headers"])
    assert len(listing.json()) == 1
    assert listing.json()[0]["metadata"] == {"durationMinutes": "20"}