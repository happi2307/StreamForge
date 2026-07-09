"""Unit tests for the Lambda handler using a mocked S3 client."""

import importlib
import io

import pytest


handler = importlib.import_module("lambda.handler")


class _FakeBody:
    def __init__(self, data: bytes) -> None:
        self._data = data

    def read(self) -> bytes:
        return self._data


class _FakeS3Client:
    """Minimal stand-in for a boto3 S3 client."""

    def __init__(self, object_bytes: bytes) -> None:
        self._object_bytes = object_bytes
        self.puts: dict[str, bytes] = {}

    def get_object(self, Bucket: str, Key: str) -> dict:  # noqa: N803 - boto3 kwargs
        return {"Body": _FakeBody(self._object_bytes)}

    def put_object(self, Bucket: str, Key: str, Body: bytes, **_: object) -> None:  # noqa: N803
        self.puts[Bucket] = Body


CSV_BYTES = (
    b"customer_id,name,email,sales\n"
    b"101,John,john@gmail.com,500\n"
    b"102,,mary@gmail.com,600\n"
    b"103,Sam,samgmail.com,700\n"
    b"104,Raj,raj@gmail.com,1000\n"
)


def _event(bucket: str = "dataflow-raw", key: str = "customers.csv") -> dict:
    return {"detail": {"bucket": {"name": bucket}, "object": {"key": key}}}


@pytest.fixture(autouse=True)
def _buckets(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CLEAN_BUCKET", "dataflow-clean")
    monkeypatch.setenv("REJECTED_BUCKET", "dataflow-rejected")


def _patch_client(monkeypatch: pytest.MonkeyPatch, client: _FakeS3Client) -> None:
    monkeypatch.setattr(handler.boto3, "client", lambda service: client)


def test_handler_returns_statistics(monkeypatch: pytest.MonkeyPatch) -> None:
    client = _FakeS3Client(CSV_BYTES)
    _patch_client(monkeypatch, client)

    stats = handler.lambda_handler(_event(), context=None)

    assert stats == {"total_records": 4, "valid_records": 2, "invalid_records": 2}


def test_handler_writes_clean_and_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    client = _FakeS3Client(CSV_BYTES)
    _patch_client(monkeypatch, client)

    handler.lambda_handler(_event(), context=None)

    clean = client.puts["dataflow-clean"].decode("utf-8")
    rejected = client.puts["dataflow-rejected"].decode("utf-8")
    assert "101,John" in clean and "104,Raj" in clean
    assert "102," in rejected and "103,Sam" in rejected


def test_handler_rejects_empty_object(monkeypatch: pytest.MonkeyPatch) -> None:
    client = _FakeS3Client(b"   ")
    _patch_client(monkeypatch, client)

    with pytest.raises(ValueError, match="empty"):
        handler.lambda_handler(_event(), context=None)


def test_handler_rejects_malformed_event(monkeypatch: pytest.MonkeyPatch) -> None:
    client = _FakeS3Client(CSV_BYTES)
    _patch_client(monkeypatch, client)

    with pytest.raises(ValueError, match="detail"):
        handler.lambda_handler({}, context=None)


def test_handler_requires_env_buckets(monkeypatch: pytest.MonkeyPatch) -> None:
    client = _FakeS3Client(CSV_BYTES)
    _patch_client(monkeypatch, client)
    monkeypatch.delenv("CLEAN_BUCKET", raising=False)

    with pytest.raises(ValueError, match="CLEAN_BUCKET"):
        handler.lambda_handler(_event(), context=None)
