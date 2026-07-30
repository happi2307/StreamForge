"""Unit tests for the Phase 5 database loader (no AWS, no live database)."""

from __future__ import annotations

import contextlib
import importlib
import json

import pytest


loader = importlib.import_module("lambda.database_loader.loader")
db = importlib.import_module("lambda.database_loader.db")
handler = importlib.import_module("lambda.database_loader.handler")


def _curated_row(customer_id="101", sales=500, batch="phase3-batch", **overrides):
    row = {
        "customer_id": customer_id,
        "name": "John Doe",
        "email": "john@example.com",
        "sales": sales,
        "sales_category": "Medium",
        "ingestion_timestamp": "2026-07-11T10:15:00Z",
        "processed_timestamp": "2026-07-11T10:20:00Z",
        "phase1_batch_id": "phase1-batch",
        "phase3_batch_id": batch,
        "source_filename": "customers.csv",
        "source_raw_key": "incoming/customers.csv",
        "source_clean_key": "customers.csv",
        "pipeline_version": "5.0.0",
    }
    row.update(overrides)
    return row


class FakeDB:
    """Records the loader's data operations and can inject failures."""

    def __init__(self, *, existing_status=None, fail_at=None, merge_updated=0):
        self.existing_status = existing_status
        self.fail_at = fail_at
        self.merge_updated = merge_updated
        self.staged: list[dict] = []
        self.errors: list[dict] = []
        self.finalized: dict | None = None
        self.failed: dict | None = None
        self.schema_scripts: list[str] | None = None
        self.committed = False
        self.rolled_back = False

    def get_batch_status(self, batch_id):
        return self.existing_status

    def apply_schema(self, scripts):
        self.schema_scripts = list(scripts)

    @contextlib.contextmanager
    def transaction(self):
        try:
            yield
        except Exception:
            self.rolled_back = True
            raise
        else:
            self.committed = True

    def begin_batch(self, batch_id, *, source_file, start_time):
        self._maybe_fail("begin")

    def reset_staging(self, batch_id):
        self._maybe_fail("reset")

    def load_staging(self, rows):
        self.staged = list(rows)
        self._maybe_fail("load")
        return len(rows)

    def validate_pre_merge(self, batch_id, *, expected_rows):
        self._maybe_fail("pre")

    def merge(self, batch_id):
        self._maybe_fail("merge")
        inserted = len({r["customer_id"] for r in self.staged}) - self.merge_updated
        return {"inserted": inserted, "updated": self.merge_updated}

    def validate_post_merge(self, batch_id, *, expected_rows):
        self._maybe_fail("post")

    def record_errors(self, batch_id, errors):
        self.errors = list(errors)

    def finalize_batch(self, batch_id, **kwargs):
        self.finalized = {"batch_id": batch_id, **kwargs}

    def mark_failed(self, batch_id, *, source_file, error_message):
        self.failed = {"batch_id": batch_id, "error_message": error_message}

    def _maybe_fail(self, stage):
        if self.fail_at == stage:
            raise ValueError(f"injected failure at {stage}")


# -- pure helpers -----------------------------------------------------------

def test_extract_batch_id_returns_single_batch():
    rows = [_curated_row("101"), _curated_row("102")]
    assert loader.extract_batch_id(rows) == "phase3-batch"


def test_extract_batch_id_rejects_mixed_batches():
    rows = [_curated_row("101", batch="a"), _curated_row("102", batch="b")]
    with pytest.raises(ValueError, match="multiple batches"):
        loader.extract_batch_id(rows)


def test_normalize_and_validate_splits_good_and_bad_rows():
    rows = [
        _curated_row("101", sales=500),
        _curated_row("102", sales="bad"),          # non-numeric sales
        _curated_row("", sales=100),               # missing customer_id
        _curated_row("101", sales=999),            # duplicate customer_id
    ]
    valid, errors = loader.normalize_and_validate(rows)

    assert [r["customer_id"] for r in valid] == ["101"]
    assert valid[0]["batch_id"] == "phase3-batch"
    reasons = {e["error_message"] for e in errors}
    assert "missing customer_id" in reasons
    assert "duplicate customer_id within batch" in reasons
    assert any("sales" in r for r in reasons)


def test_compute_checksum_is_order_independent():
    a = [_curated_row("101", sales=1), _curated_row("102", sales=2)]
    b = list(reversed(a))
    assert loader.compute_checksum(a) == loader.compute_checksum(b)


def test_structured_log_emits_json_with_identity(caplog):
    with caplog.at_level("INFO"):
        line = loader.structured_log(loader.logging.getLogger("t"), batch_id="b1")
    payload = json.loads(line)
    assert payload["pipeline"] == "streamforge"
    assert payload["stage"] == "database_loader"
    assert payload["batch_id"] == "b1"
    assert payload["timestamp"].endswith("Z")


# -- process_batch orchestration -------------------------------------------

def test_process_batch_success_counts_and_finalizes():
    fake = FakeDB(merge_updated=1)
    rows = [_curated_row("101"), _curated_row("102"), _curated_row("103")]

    result = loader.process_batch(
        fake, rows, source_file="customers.csv", logger=loader.logging.getLogger("t")
    )

    assert result["status"] == "SUCCESS"
    assert result["records_loaded"] == 2   # 3 distinct - 1 updated
    assert result["records_updated"] == 1
    assert result["records_failed"] == 0
    assert fake.committed and not fake.rolled_back
    assert fake.finalized["status"] == "SUCCESS"
    assert fake.finalized["checksum"]


def test_process_batch_skips_already_successful_batch():
    fake = FakeDB(existing_status="SUCCESS")
    rows = [_curated_row("101")]

    result = loader.process_batch(
        fake, rows, source_file="customers.csv", logger=loader.logging.getLogger("t")
    )

    assert result["status"] == "SKIPPED"
    assert fake.finalized is None
    assert not fake.committed


def test_process_batch_captures_record_errors_without_failing():
    fake = FakeDB()
    rows = [_curated_row("101"), _curated_row("102", sales="bad")]

    result = loader.process_batch(
        fake, rows, source_file="customers.csv", logger=loader.logging.getLogger("t")
    )

    assert result["status"] == "SUCCESS"
    assert result["records_failed"] == 1
    assert fake.errors and fake.errors[0]["customer_id"] == "102"


@pytest.mark.parametrize("stage", ["pre", "merge", "post"])
def test_process_batch_rolls_back_and_marks_failed(stage):
    fake = FakeDB(fail_at=stage)
    rows = [_curated_row("101"), _curated_row("102")]

    with pytest.raises(ValueError, match="injected failure"):
        loader.process_batch(
            fake, rows, source_file="customers.csv",
            logger=loader.logging.getLogger("t"),
        )

    assert fake.rolled_back
    assert fake.committed is False
    assert fake.finalized is None
    assert fake.failed and fake.failed["batch_id"] == "phase3-batch"


# -- db.get_secret ----------------------------------------------------------

def test_get_secret_parses_json_credentials():
    class FakeSecrets:
        def get_secret_value(self, SecretId):  # noqa: N803 - boto3 kwargs
            return {"SecretString": json.dumps({"username": "u", "password": "p"})}

    creds = db.get_secret("db-secret", FakeSecrets())
    assert creds == {"username": "u", "password": "p"}


def test_get_secret_rejects_empty_secret():
    class FakeSecrets:
        def get_secret_value(self, SecretId):  # noqa: N803
            return {}

    with pytest.raises(ValueError, match="no SecretString"):
        db.get_secret("db-secret", FakeSecrets())


def test_apply_schema_runs_all_scripts_in_one_transaction():
    class FakeConnection:
        def __init__(self):
            self.calls = []

        def run(self, statement):
            self.calls.append(statement)

    connection = FakeConnection()
    db.Database(connection).apply_schema(["CREATE SCHEMA a", "CREATE SCHEMA b"])
    assert connection.calls == ["BEGIN", "CREATE SCHEMA a", "CREATE SCHEMA b", "COMMIT"]


# -- handler ----------------------------------------------------------------

def test_handler_extracts_batch_ready_event():
    event = {
        "detail": {
            "bucket": "metadata",
            "manifest_key": "serving/batches/phase3-batch.json",
            "batch_id": "phase3-batch",
        }
    }
    assert handler._extract_batch_ready(event) == (
        "metadata", "serving/batches/phase3-batch.json", "phase3-batch"
    )


def test_handler_loads_object_end_to_end(monkeypatch):
    fake_db = FakeDB()
    rows = [_curated_row("101"), _curated_row("102")]

    class FakeBody:
        def read(self):
            return b"parquet-bytes"

    manifest = {
        "phase3_batch_id": "phase3-batch",
        "source_filename": "customers.csv",
        "source_checksum": loader.compute_checksum(rows),
        "curated_bucket": "curated",
        "curated_object_keys": ["c/x.parquet"],
    }

    class FakeS3:
        def get_object(self, Bucket, Key):  # noqa: N803
            if Bucket == "metadata":
                return {"Body": type("Body", (), {"read": lambda self: json.dumps(manifest).encode()})()}
            return {"Body": FakeBody()}

    class FakeSNS:
        def publish(self, **kwargs):
            raise AssertionError("SNS should not publish on success")

    clients = {"s3": FakeS3(), "secretsmanager": object(), "sns": FakeSNS()}
    monkeypatch.setattr(handler.boto3, "client", lambda name: clients[name])
    monkeypatch.setattr(handler, "read_parquet_rows", lambda data: rows)
    monkeypatch.setattr(handler.db_module, "get_connection", lambda client: object())
    monkeypatch.setattr(handler.db_module, "Database", lambda conn: fake_db)

    event = {
        "detail": {
            "bucket": "metadata",
            "manifest_key": "serving/batches/phase3-batch.json",
            "batch_id": "phase3-batch",
        }
    }
    result = handler.lambda_handler(event, context=None)

    assert result["status"] == "SUCCESS"
    assert fake_db.committed


def test_handler_bootstraps_schema(monkeypatch):
    fake_db = FakeDB()
    clients = {"secretsmanager": object(), "sns": object()}
    monkeypatch.setattr(handler.boto3, "client", lambda name: clients[name])
    monkeypatch.setattr(handler.db_module, "get_connection", lambda client: object())
    monkeypatch.setattr(handler.db_module, "Database", lambda conn: fake_db)

    result = handler.lambda_handler({"action": "bootstrap"}, context=None)

    assert result == {"status": "BOOTSTRAPPED", "scripts_applied": 3}
    assert fake_db.schema_scripts is not None
    assert "CREATE SCHEMA IF NOT EXISTS analytics" in fake_db.schema_scripts[0]


def test_handler_publishes_sns_on_failure(monkeypatch):
    fake_db = FakeDB(fail_at="post")
    rows = [_curated_row("101")]
    published = {}

    class FakeBody:
        def read(self):
            return b"parquet-bytes"

    manifest = {
        "phase3_batch_id": "phase3-batch",
        "source_filename": "customers.csv",
        "source_checksum": loader.compute_checksum(rows),
        "curated_bucket": "curated",
        "curated_object_keys": ["c/x.parquet"],
    }

    class FakeS3:
        def get_object(self, Bucket, Key):  # noqa: N803
            if Bucket == "metadata":
                return {"Body": type("Body", (), {"read": lambda self: json.dumps(manifest).encode()})()}
            return {"Body": FakeBody()}

    class FakeSNS:
        def publish(self, **kwargs):
            published.update(kwargs)

    clients = {"s3": FakeS3(), "secretsmanager": object(), "sns": FakeSNS()}
    monkeypatch.setattr(handler.boto3, "client", lambda name: clients[name])
    monkeypatch.setattr(handler, "read_parquet_rows", lambda data: rows)
    monkeypatch.setattr(handler.db_module, "get_connection", lambda client: object())
    monkeypatch.setattr(handler.db_module, "Database", lambda conn: fake_db)
    monkeypatch.setenv("SNS_TOPIC", "arn:aws:sns:us-east-1:1:streamforge-dev-alerts")

    event = {
        "detail": {
            "bucket": "metadata",
            "manifest_key": "serving/batches/phase3-batch.json",
            "batch_id": "phase3-batch",
        }
    }
    with pytest.raises(ValueError):
        handler.lambda_handler(event, context=None)

    assert published["TopicArn"].endswith("streamforge-dev-alerts")
    assert fake_db.failed is not None


# -- parquet round-trip (only if pyarrow is installed) ----------------------

def test_read_parquet_rows_round_trip(tmp_path):
    duckdb = pytest.importorskip("duckdb")
    path = tmp_path / "customers.parquet"
    connection = duckdb.connect(":memory:")
    try:
        connection.execute("CREATE TABLE customers (customer_id VARCHAR, sales INTEGER)")
        connection.execute("INSERT INTO customers VALUES ('101', 500), ('102', 600)")
        connection.execute(f"COPY customers TO '{path.as_posix()}' (FORMAT PARQUET)")
    finally:
        connection.close()

    rows = loader.read_parquet_rows(path.read_bytes())
    assert rows == [
        {"customer_id": "101", "sales": 500},
        {"customer_id": "102", "sales": 600},
    ]
