"""Tests for the downloadable content-pack endpoints.

The pipeline's honesty rule lives here: the list/detail manifest carries
``sha256`` + ``sizeBytes``, and ``/content`` streams exactly the bytes that
were stored, re-stating the checksum in ``ETag`` / ``X-Checksum-Sha256`` so a
client can verify locally before marking a resource Ready.
"""

from __future__ import annotations

import base64
import hashlib

from fastapi.testclient import TestClient


def _encode(content: bytes | None) -> str | None:
    if content is None:
        return None
    return base64.b64encode(content).decode("ascii")


_MISSING = object()


def _pack(content: bytes, *, blob: object = _MISSING, **overrides: str | int | bytes | None) -> dict:
    wire = _encode(content if blob is _MISSING else blob)
    return {
        "kind": "content",
        "name": "A test pack",
        "description": "Bytes under test.",
        "classNumber": 1,
        "subject": "numeracy",
        "version": "1",
        "mimeType": "application/json",
        "sizeBytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
        "content": wire,
        **overrides,
    }


def _create(client: TestClient, headers: dict, content: bytes, **overrides) -> dict:
    response = client.post(
        "/api/v1/resources", json=_pack(content, **overrides), headers=headers
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_list_resources_is_empty_on_a_fresh_database(client):
    response = client.get("/api/v1/resources")
    assert response.status_code == 200
    assert response.json() == []


def test_create_requires_authentication(client):
    response = client.post("/api/v1/resources", json=_pack(b"abc"))
    assert response.status_code in (401, 403)


def test_create_then_list_and_get_round_trip(client, auth):
    headers = auth()["headers"]
    payload = b'{"hello":"world"}'
    created = _create(client, headers, payload)
    assert created["sizeBytes"] == len(payload)
    assert created["sha256"] == hashlib.sha256(payload).hexdigest()
    # camelCase wire format (alias generator), extra fields absent.
    assert created["classNumber"] == 1
    assert "blob" not in created

    items = client.get("/api/v1/resources").json()
    assert len(items) == 1
    assert items[0]["id"] == created["id"]
    assert items[0]["kind"] == "content"

    got = client.get(f"/api/v1/resources/{created['id']}")
    assert got.status_code == 200
    assert got.json()["name"] == "A test pack"


def test_content_endpoint_streams_exact_bytes_with_checksum_headers(client, auth):
    headers = auth()["headers"]
    payload = b'{"script":[1,2,3],"spell":"mit\'"}'
    created = _create(client, headers, payload)
    response = client.get(f"/api/v1/resources/{created['id']}/content")
    assert response.status_code == 200
    assert response.content == payload
    assert response.headers["content-length"] == str(len(payload))
    assert response.headers["etag"] == f'"{created["sha256"]}"'
    assert response.headers["x-checksum-sha256"] == created["sha256"]
    assert response.headers["x-resource-version"] == "1"
    assert response.headers["content-type"] == "application/json"


def test_list_filters_and_pagination(client, auth):
    headers = auth()["headers"]
    _create(client, headers, b"1", name="one")
    _create(client, headers, b"2", name="two", kind="audio")
    _create(client, headers, b"3", name="three", classNumber=2)

    by_kind = client.get("/api/v1/resources", params={"kind": "audio"}).json()
    assert [r["name"] for r in by_kind] == ["two"]

    by_class = client.get("/api/v1/resources", params={"classNumber": 1}).json()
    assert len(by_class) == 2

    page = client.get(
        "/api/v1/resources", params={"limit": 2, "offset": 1}
    ).json()
    # Ordering is kind then id: the audio row ("two") sorts before the two
    # content rows, so offset 1 skips it and pages over the content packs.
    assert len(page) == 2
    assert {r["name"] for r in page} == {"one", "three"}


def test_get_missing_resource_is_404(client):
    assert client.get("/api/v1/resources/nope").status_code == 404
    assert client.get("/api/v1/resources/nope/content").status_code == 404


def test_content_endpoint_404_when_blob_was_never_stored(client, auth):
    headers = auth()["headers"]
    response = client.post(
        "/api/v1/resources", json=_pack(b"", blob=None), headers=headers
    )
    assert response.status_code == 201, response.text
    row = response.json()
    assert row["sizeBytes"] == 0
    assert client.get(f"/api/v1/resources/{row['id']}/content").status_code == 404


def test_patch_updates_version_and_manifest(client, auth):
    headers = auth()["headers"]
    created = _create(client, headers, b"v1", version="1")
    response = client.patch(
        f"/api/v1/resources/{created['id']}",
        json={"version": "2", "name": "renamed"},
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["version"] == "2"
    assert response.json()["name"] == "renamed"

    updated_content = b"v2-new-bytes"
    response = client.patch(
        f"/api/v1/resources/{created['id']}",
        json={
            "sizeBytes": len(updated_content),
            "sha256": hashlib.sha256(updated_content).hexdigest(),
            "content": _encode(updated_content),
        },
        headers=headers,
    )
    assert response.json()["sizeBytes"] == len(updated_content)
    body = client.get(f"/api/v1/resources/{created['id']}/content")
    assert body.content == updated_content


def test_delete_removes_the_row(client, auth):
    headers = auth()["headers"]
    created = _create(client, headers, b"bye")
    assert client.delete(
        f"/api/v1/resources/{created['id']}", headers=headers
    ).status_code == 204
    assert client.get(f"/api/v1/resources/{created['id']}").status_code == 404