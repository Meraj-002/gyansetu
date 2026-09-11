"""Teacher endpoints tests."""


def test_teacher_me_roundtrip(client, auth):
    session = auth(mobile="9811111111")
    response = client.get("/api/v1/teachers/me", headers=session["headers"])
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == session["account"]["id"]
    assert body["displayName"] == "Asha Devi"
    assert body["schoolName"] == "MS Ranchi"


def test_teacher_update_display_name_and_mobile(client, auth):
    session = auth(mobile="9811111111")
    response = client.patch(
        "/api/v1/teachers/me",
        headers=session["headers"],
        json={"displayName": "Asha K", "mobile": "+91 9000001234"},
    )
    assert response.status_code == 200
    assert response.json()["displayName"] == "Asha K"
    assert response.json()["mobileLast4"] == "1234"


def test_teacher_update_other_teachers_mobile_is_409(client, auth):
    auth(mobile="9811111111")
    second = auth(mobile="9822222222", display_name="Someone")
    response = client.patch(
        "/api/v1/teachers/me",
        headers=second["headers"],
        json={"mobile": "9811111111"},
    )
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "mobile_in_use"


def test_teacher_list_and_get(client, auth):
    session = auth(mobile="9811111111")
    listing = client.get("/api/v1/teachers", headers=session["headers"])
    assert listing.status_code == 200
    # The profile list is the signed-in teacher's own record only.
    assert [t["id"] for t in listing.json()] == [session["account"]["id"]]

    one = client.get(
        f"/api/v1/teachers/{session['account']['id']}", headers=session["headers"]
    )
    assert one.status_code == 200
    assert one.json()["displayName"] == "Asha Devi"


def test_get_another_teacher_is_403(client, auth):
    first = auth(mobile="9811111111")
    second = auth(mobile="9822222222", display_name="Someone")
    # Reading another teacher's profile is forbidden outright.
    assert (
        client.get(f"/api/v1/teachers/{first['account']['id']}", headers=second["headers"]).status_code
        == 403
    )
    # The list endpoint never leaks other profiles either.
    listing = client.get("/api/v1/teachers", headers=second["headers"])
    assert [t["id"] for t in listing.json()] == [second["account"]["id"]]


def test_teacher_get_another_or_missing_is_403(client, auth):
    session = auth(mobile="9811111111")
    # A non-matching id (missing or another teacher) is uniformly 403 rather than
    # revealing whether the target exists.
    for target in ("nope", "some-other-teacher"):
        response = client.get(
            f"/api/v1/teachers/{target}", headers=session["headers"]
        )
        assert response.status_code == 403


def test_teacher_endpoints_require_auth(client):
    assert client.get("/api/v1/teachers").status_code == 401
    assert client.patch("/api/v1/teachers/me", json={}).status_code == 401