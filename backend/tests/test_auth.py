"""Auth flow tests."""


def test_register_returns_camelcase_account_and_school(client):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "displayName": "Asha Devi",
            "mobile": "+91 9876543210",
            "schoolCode": "JH-001",
            "schoolName": "MS Ranchi",
            "password": "secret123",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["accessToken"]
    assert body["tokenType"] == "bearer"
    assert body["expiresIn"] > 0
    assert body["account"]["displayName"] == "Asha Devi"
    assert body["account"]["schoolName"] == "MS Ranchi"
    assert body["account"]["schoolCode"] == "JH-001"
    assert body["account"]["mobileLast4"] == "3210"
    assert body["account"]["hasMobile"] is True
    assert body["school"]["code"] == "JH-001"


def test_register_creates_unknown_school_when_name_given(client):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "displayName": "Ravi Kumar",
            "schoolCode": "JH-999",
            "schoolName": "New School",
            "password": "pass1234",
        },
    )
    assert response.status_code == 201
    assert response.json()["school"]["name"] == "New School"


def test_register_unknown_school_without_name_is_400(client):
    response = client.post(
        "/api/v1/auth/register",
        json={"displayName": "Ravi Kumar", "schoolCode": "JH-999", "password": "pass1234"},
    )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "unknown_school_code"


def test_register_duplicate_mobile_is_409(client):
    body = {
        "displayName": "A",
        "mobile": "9000000000",
        "schoolCode": "JH-001",
        "schoolName": "MS Ranchi",
        "password": "pass1234",
    }
    assert client.post("/api/v1/auth/register", json=body).status_code == 201
    repeat = client.post("/api/v1/auth/register", json=body)
    assert repeat.status_code == 409
    assert repeat.json()["detail"]["code"] == "mobile_in_use"


def test_login_with_mobile(client):
    client.post(
        "/api/v1/auth/register",
        json={"displayName": "A", "mobile": "9876543210", "password": "secret123"},
    )
    login = client.post(
        "/api/v1/auth/login", json={"identifier": "9876543210", "password": "secret123"}
    )
    assert login.status_code == 200
    assert login.json()["accessToken"]


def test_login_with_teacher_id(client):
    reg = client.post(
        "/api/v1/auth/register",
        json={"displayName": "A", "mobile": "9876543210", "password": "secret123"},
    ).json()
    teacher_id = reg["account"]["id"]
    login = client.post(
        "/api/v1/auth/login", json={"identifier": teacher_id, "password": "secret123"}
    )
    assert login.status_code == 200


def test_login_wrong_password_is_401(client):
    client.post(
        "/api/v1/auth/register",
        json={"displayName": "A", "mobile": "9876543210", "password": "secret123"},
    )
    bad = client.post(
        "/api/v1/auth/login", json={"identifier": "9876543210", "password": "nope"}
    )
    assert bad.status_code == 401
    assert bad.json()["detail"]["code"] == "invalid_credentials"


def test_login_school_code_mismatch_is_401(client):
    client.post(
        "/api/v1/auth/register",
        json={
            "displayName": "A",
            "mobile": "9876543210",
            "schoolCode": "JH-001",
            "schoolName": "MS Ranchi",
            "password": "secret123",
        },
    )
    bad = client.post(
        "/api/v1/auth/login",
        json={"identifier": "9876543210", "password": "secret123", "schoolCode": "XX-9"},
    )
    assert bad.status_code == 401


def test_verify_school_code_known_and_unknown(client):
    client.post(
        "/api/v1/auth/register",
        json={
            "displayName": "A",
            "mobile": "9876543210",
            "schoolCode": "JH-001",
            "schoolName": "MS Ranchi",
            "password": "secret123",
        },
    )
    known = client.post("/api/v1/auth/verify-school-code", json={"schoolCode": "JH-001"})
    assert known.status_code == 200
    assert known.json()["schoolName"] == "MS Ranchi"
    unknown = client.post("/api/v1/auth/verify-school-code", json={"schoolCode": "NOPE"})
    assert unknown.status_code == 404
    assert unknown.json()["detail"]["code"] == "school_code_unknown"


def test_recover_acknowledges(client):
    response = client.post("/api/v1/auth/recover", json={"identifier": "9876543210"})
    assert response.status_code == 200
    assert response.json()["status"] == "accepted"


def test_me_requires_valid_token(client):
    assert client.get("/api/v1/auth/me").status_code == 401
    assert (
        client.get(
            "/api/v1/auth/me", headers={"Authorization": "Bearer not.a.token"}
        ).status_code
        == 401
    )


def test_me_returns_account(client, auth):
    session = auth(mobile="9811111111")
    response = client.get("/api/v1/auth/me", headers=session["headers"])
    assert response.status_code == 200
    assert response.json()["id"] == session["account"]["id"]
    assert response.json()["displayName"] == "Asha Devi"


def test_logout_is_204(client, auth):
    session = auth(mobile="9822222222")
    response = client.post("/api/v1/auth/logout", headers=session["headers"])
    assert response.status_code == 204