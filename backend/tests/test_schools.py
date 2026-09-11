"""School CRUD tests."""


def test_create_school_outputs_camelcase(client, auth):
    session = auth(mobile="9811111111")
    response = client.post(
        "/api/v1/schools",
        headers=session["headers"],
        json={
            "name": "UP Jamshedpur",
            "code": "JH-042",
            "districtName": "Jamshedpur",
            "blockName": "Sakchi",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "UP Jamshedpur"
    assert body["districtName"] == "Jamshedpur"
    assert body["blockName"] == "Sakchi"


def test_create_duplicate_code_is_409(client, auth):
    session = auth(mobile="9811111111")
    payload = {"name": "A", "code": "JH-042"}
    assert (
        client.post("/api/v1/schools", headers=session["headers"], json=payload).status_code
        == 201
    )
    response = client.post("/api/v1/schools", headers=session["headers"], json=payload)
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "code_in_use"


def test_school_by_code(client, auth):
    session = auth(mobile="9811111111")
    code = session["school"]["code"]
    response = client.get(f"/api/v1/schools/by-code/{code}")
    assert response.status_code == 200
    assert response.json()["name"] == "MS Ranchi"
    assert client.get("/api/v1/schools/by-code/UNKNOWN").status_code == 404


def test_school_get_update_delete(client, auth):
    session = auth(mobile="9811111111")
    created = client.post(
        "/api/v1/schools",
        headers=session["headers"],
        json={"name": "Beta School", "code": "JH-100"},
    ).json()
    school_id = created["id"]

    got = client.get(f"/api/v1/schools/{school_id}")
    assert got.status_code == 200
    assert got.json()["name"] == "Beta School"

    patched = client.patch(
        f"/api/v1/schools/{school_id}",
        headers=session["headers"],
        json={"districtName": "Ranchi"},
    )
    assert patched.status_code == 200
    assert patched.json()["districtName"] == "Ranchi"

    deleted = client.delete(f"/api/v1/schools/{school_id}", headers=session["headers"])
    assert deleted.status_code == 204
    assert client.get(f"/api/v1/schools/{school_id}").status_code == 404


def test_school_mutations_require_auth(client):
    assert client.post("/api/v1/schools", json={"name": "X", "code": "Y"}).status_code == 401
    assert client.delete("/api/v1/schools/abc").status_code == 401