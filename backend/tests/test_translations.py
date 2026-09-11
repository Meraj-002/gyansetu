"""Translation CRUD tests."""

from urllib.parse import quote

PAYLOAD = {
    "id": "L-1#sat",
    "lessonId": "L-1",
    "sourceMedium": "hindi",
    "targetLanguage": "sat",
    "text": "एक से पाँच तक गिनती",
    "spokenText": "ek se paanch tak ginti",
    "provenance": "aiAdapted",
    "reviewedBySpeaker": False,
    "version": 2,
}


def test_create_list_and_filter(client, auth):
    session = auth(mobile="9811111111")
    assert (
        client.post("/api/v1/translations", headers=session["headers"], json=PAYLOAD).status_code
        == 201
    )
    by_lesson = client.get("/api/v1/translations", params={"lessonId": "L-1"})
    assert len(by_lesson.json()) == 1
    assert by_lesson.json()[0]["spokenText"] == "ek se paanch tak ginti"
    assert by_lesson.json()[0]["provenance"] == "aiAdapted"


def test_update_and_delete(client, auth):
    session = auth(mobile="9811111111")
    translation_id = client.post(
        "/api/v1/translations", headers=session["headers"], json=PAYLOAD
    ).json()["id"]
    quoted = quote(translation_id, safe="")

    patched = client.patch(
        f"/api/v1/translations/{quoted}",
        headers=session["headers"],
        json={"reviewedBySpeaker": True, "version": 3},
    )
    assert patched.status_code == 200
    assert patched.json()["reviewedBySpeaker"] is True
    assert patched.json()["version"] == 3

    assert (
        client.delete(f"/api/v1/translations/{quoted}", headers=session["headers"]).status_code
        == 204
    )
    assert client.get(f"/api/v1/translations/{quoted}").status_code == 404


def test_get_missing_is_404(client, auth):
    session = auth(mobile="9811111111")
    assert client.get("/api/v1/translations/nope", headers=session["headers"]).status_code == 404