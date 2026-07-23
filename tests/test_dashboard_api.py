from __future__ import annotations

import io
import json

from botocore.exceptions import ClientError

import dashboard_api


class FakeS3:
    def __init__(self, manifest: dict[str, object] | None = None) -> None:
        self.manifest = manifest
        self.presigned: list[dict[str, object]] = []

    def generate_presigned_url(self, operation: str, **kwargs: object) -> str:
        self.presigned.append({"operation": operation, **kwargs})
        return f"https://example.test/{operation}/{len(self.presigned)}"

    def get_object(self, **_kwargs: object) -> dict[str, object]:
        if self.manifest is None:
            raise ClientError({"Error": {"Code": "NoSuchKey"}}, "GetObject")
        return {"Body": io.BytesIO(json.dumps(self.manifest).encode("utf-8"))}


def _event(*, body: dict[str, object] | None = None, key: str | None = None) -> dict[str, object]:
    return {
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": "user-123"}}}},
        "body": json.dumps(body) if body is not None else None,
        "queryStringParameters": {"key": key} if key else {},
    }


def test_create_upload_returns_user_scoped_presigned_put(monkeypatch) -> None:
    monkeypatch.setenv("RAW_BUCKET", "raw")
    client = FakeS3()

    response = dashboard_api.create_upload(
        _event(body={"filename": "customers.csv", "size": 12}), client
    )

    payload = json.loads(response["body"])
    assert response["statusCode"] == 201
    assert payload["key"].startswith("uploads/user-123/")
    assert client.presigned[0]["operation"] == "put_object"


def test_status_returns_processing_when_manifest_is_not_written(monkeypatch) -> None:
    monkeypatch.setenv("METADATA_BUCKET", "metadata")
    monkeypatch.setenv("METADATA_PREFIX", "metadata")

    response = dashboard_api.get_status(
        _event(key="uploads/user-123/input.csv"), FakeS3()
    )

    assert json.loads(response["body"])["status"] == "PROCESSING"


def test_status_returns_counts_and_presigned_downloads(monkeypatch) -> None:
    monkeypatch.setenv("METADATA_BUCKET", "metadata")
    monkeypatch.setenv("METADATA_PREFIX", "metadata")
    client = FakeS3(
        {
            "phase1_batch_id": "batch-1",
            "source_filename": "input.csv",
            "phase1_processed_timestamp": "2026-07-21T00:00:00Z",
            "total_records": 3,
            "valid_records": 2,
            "invalid_records": 1,
            "clean_bucket": "clean",
            "clean_key": "uploads/user-123/input.csv",
            "rejected_bucket": "rejected",
            "rejected_key": "uploads/user-123/input.csv",
        }
    )

    response = dashboard_api.get_status(
        _event(key="uploads/user-123/input.csv"), client
    )

    payload = json.loads(response["body"])
    assert payload["status"] == "COMPLETE"
    assert payload["valid_records"] == 2
    assert set(payload["downloads"]) == {"clean", "rejected"}


def test_status_rejects_another_users_key() -> None:
    response = dashboard_api.get_status(
        _event(key="uploads/other-user/input.csv"), FakeS3()
    )

    assert response["statusCode"] == 403
