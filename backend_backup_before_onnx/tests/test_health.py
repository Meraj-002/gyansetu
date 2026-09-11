"""Health endpoint tests."""


def test_root_health_is_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["service"]
    assert body["version"]
    assert body["time"]


def test_health_db_probe(client):
    response = client.get("/health/db")
    assert response.status_code == 200
    assert response.json()["database"] == "reachable"


def test_api_v1_health_matches_flutter_contract(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_root_redirects_to_docs(client):
    response = client.get("/", follow_redirects=False)
    assert response.status_code in (302, 307)


def test_openapi_has_sync_and_auth_paths(client):
    schema = client.get("/openapi.json").json()
    paths = set(schema["paths"])
    for expected in (
        "/api/v1/auth/register",
        "/api/v1/auth/login",
        "/api/v1/sync/push",
        "/api/v1/sync/pull",
        "/api/v1/sync/status",
        "/api/v1/lessons",
        "/api/v1/worksheets",
        "/api/v1/assessments",
        "/api/v1/sessions",
    ):
        assert expected in paths