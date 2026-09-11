"""Learning outcomes CRUD tests."""


OUTCOME = {
    "text": "Counts objects 1-5 in the target language",
    "classNumber": 1,
    "subject": "numeracy",
    "code": "M.N1.1",
}


def test_create_and_list(client, auth):
    session = auth(mobile="9811111111")
    created = client.post("/api/v1/learning-outcomes", headers=session["headers"], json=OUTCOME)
    assert created.status_code == 201
    assert created.json()["code"] == "M.N1.1"

    listing = client.get("/api/v1/learning-outcomes", params={"classNumber": 1})
    assert listing.status_code == 200
    assert len(listing.json()) == 1
    assert listing.json()[0]["text"].startswith("Counts")


def test_filter_by_subject(client, auth):
    session = auth(mobile="9811111111")
    client.post("/api/v1/learning-outcomes", headers=session["headers"], json=OUTCOME)
    client.post(
        "/api/v1/learning-outcomes",
        headers=session["headers"],
        json={**OUTCOME, "subject": "foundationalLiteracy", "code": "FLN.A1"},
    )
    numeracy = client.get("/api/v1/learning-outcomes", params={"subject": "numeracy"})
    assert len(numeracy.json()) == 1


def test_update_and_delete(client, auth):
    session = auth(mobile="9811111111")
    outcome_id = client.post(
        "/api/v1/learning-outcomes", headers=session["headers"], json=OUTCOME
    ).json()["id"]

    patched = client.patch(
        f"/api/v1/learning-outcomes/{outcome_id}",
        headers=session["headers"],
        json={"curriculumReference": "NCF 2023"},
    )
    assert patched.status_code == 200
    assert patched.json()["curriculumReference"] == "NCF 2023"

    assert (
        client.delete(
            f"/api/v1/learning-outcomes/{outcome_id}", headers=session["headers"]
        ).status_code
        == 204
    )
    assert client.get(f"/api/v1/learning-outcomes/{outcome_id}").status_code == 404