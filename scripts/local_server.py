"""Serve the web dashboard against the local pipeline, without AWS.

Stands in for the three AWS pieces the dashboard talks to:

    Cognito hosted UI  ->  /login and /oauth2/token (auto sign-in, fake token)
    API Gateway        ->  POST /uploads, GET /status
    S3 presigned URLs  ->  PUT /local-upload, GET /download

Everything is served from one origin, so there is no CORS to configure, and
the page's own config.js is overridden in flight rather than edited on disk.
Uploads run through the same validator as scripts/run_local.py.

Usage:
    python scripts/local_server.py            # http://localhost:8000
    python scripts/local_server.py 9000
"""

from __future__ import annotations

import base64
import importlib
import io
import json
import os
import re
import sys
import time
import types
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

run_local = importlib.import_module("scripts.run_local")
metadata = importlib.import_module("lambda.metadata")


def _install_aws_stubs() -> None:
    """Let portal_api import without boto3 installed.

    The portal endpoints are reused verbatim so local testing exercises the real
    backend logic; only the S3 client underneath is swapped for local folders.
    Anything that genuinely needs AWS is reported as unavailable rather than
    faked, so a local pass never implies a deployed one.
    """
    if "boto3" not in sys.modules:
        boto3_stub = types.ModuleType("boto3")
        boto3_stub.client = lambda service, *a, **kw: _AwsUnavailable(service)
        sys.modules["boto3"] = boto3_stub

    if "botocore.exceptions" not in sys.modules:
        botocore = sys.modules.setdefault("botocore", types.ModuleType("botocore"))
        exceptions = types.ModuleType("botocore.exceptions")

        class ClientError(Exception):
            def __init__(self, response=None, operation_name=""):
                super().__init__(operation_name)
                self.response = response or {"Error": {"Code": "LocalStub"}}

        exceptions.ClientError = ClientError
        botocore.exceptions = exceptions
        sys.modules["botocore.exceptions"] = exceptions


class _AwsUnavailable:
    """Stands in for an AWS client that has no local equivalent."""

    def __init__(self, service: str):
        self.service = service

    def __getattr__(self, name):
        def fail(*_args, **_kwargs):
            raise RuntimeError(
                f"{self.service}:{name} needs real AWS; this endpoint is unavailable locally."
            )
        return fail


_install_aws_stubs()
portal_api = importlib.import_module("portal_api")

WEB = ROOT / "web"
# Mirrors dashboard_api.MAX_UPLOAD_BYTES. Duplicated rather than imported
# because dashboard_api pulls in boto3, which local runs do not need.
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


class LocalS3:
    """The slice of the S3 API that portal_api actually uses, over local folders.

    Bucket names are the folder names under local_buckets/.
    """

    def __init__(self, root: Path):
        self.root = root

    def _bucket_dir(self, bucket: str) -> Path:
        return self.root / bucket

    def get_paginator(self, operation: str):
        if operation != "list_objects_v2":
            raise RuntimeError(f"LocalS3 does not implement {operation}")
        return _LocalPaginator(self)

    def list_objects(self, bucket: str, prefix: str = ""):
        base = self._bucket_dir(bucket)
        if not base.is_dir():
            return []
        contents = []
        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue
            key = path.relative_to(base).as_posix()
            if prefix and not key.startswith(prefix):
                continue
            stat = path.stat()
            contents.append(
                {
                    "Key": key,
                    "Size": stat.st_size,
                    "LastModified": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc),
                    "StorageClass": "STANDARD",
                }
            )
        return contents

    def get_object(self, Bucket: str, Key: str):  # noqa: N803 - matches boto3
        path = self._bucket_dir(Bucket) / Key
        if not path.is_file():
            raise _client_error("NoSuchKey", "GetObject")
        return {"Body": io.BytesIO(path.read_bytes())}

    def get_bucket_encryption(self, Bucket: str):  # noqa: N803
        # Local folders have no encryption; say so rather than claiming SSE-KMS.
        raise _client_error("ServerSideEncryptionConfigurationNotFoundError", "GetBucketEncryption")

    def get_bucket_lifecycle_configuration(self, Bucket: str):  # noqa: N803
        raise _client_error("NoSuchLifecycleConfiguration", "GetBucketLifecycleConfiguration")


class _LocalPaginator:
    def __init__(self, client: LocalS3):
        self.client = client

    def paginate(self, Bucket: str, Prefix: str = "", **_kwargs):  # noqa: N803
        yield {"Contents": self.client.list_objects(Bucket, Prefix)}


def _client_error(code: str, operation: str):
    from botocore.exceptions import ClientError  # resolved via the stub above

    return ClientError({"Error": {"Code": code}}, operation)


def configure_portal_env() -> None:
    """Point portal_api at the local buckets."""
    os.environ.setdefault("METADATA_PREFIX", "metadata")
    for zone, variable in portal_api.ZONES:
        os.environ.setdefault(variable, zone.replace("_", "-"))


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def fake_id_token(ttl_seconds: int = 3600) -> str:
    """A structurally valid, unsigned JWT. Nothing here verifies signatures."""
    header = b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
    claims = {
        "sub": "local-dev-user",
        "email": "local@localhost",
        "exp": int(time.time()) + ttl_seconds,
    }
    return f"{header}.{b64url(json.dumps(claims).encode())}.local-development-only"


def sanitize_filename(name: str) -> str:
    """Same rule as dashboard_api._sanitize_filename."""
    name = (name or "").strip()
    if not name.lower().endswith(".csv"):
        raise ValueError("Only .csv uploads are supported")
    clean = re.sub(r"[^A-Za-z0-9._-]", "_", name.rsplit("/", 1)[-1])
    if not clean or clean == ".csv":
        raise ValueError("A valid CSV filename is required")
    return clean


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    # -- helpers ---------------------------------------------------------

    def send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_body(self) -> bytes:
        return self.rfile.read(int(self.headers.get("content-length") or 0))

    def origin(self) -> str:
        return f"http://{self.headers.get('host', 'localhost:8000')}"

    # -- routes ----------------------------------------------------------

    def do_GET(self) -> None:
        route = urlparse(self.path)
        query = parse_qs(route.query)

        if route.path == "/config.js":
            self.serve_config()
            return

        # Stand-in for the Cognito hosted UI: bounce straight back with a code.
        if route.path == "/login":
            redirect = query.get("redirect_uri", [self.origin() + "/"])[0]
            self.send_response(302)
            self.send_header("location", redirect + "?code=local-development")
            self.end_headers()
            return

        if route.path == "/status":
            self.handle_status(query.get("key", [""])[0])
            return

        if route.path == "/download":
            self.handle_download(query.get("path", [""])[0])
            return

        if route.path.startswith("/api/"):
            self.handle_portal(f"GET {route.path}", query)
            return

        super().do_GET()

    def do_POST(self) -> None:
        route = urlparse(self.path)

        if route.path == "/oauth2/token":
            self.read_body()
            self.send_json(200, {"id_token": fake_id_token(), "token_type": "Bearer"})
            return

        if route.path == "/uploads":
            self.handle_create_upload()
            return

        self.send_json(404, {"message": "Route not found"})

    def do_PUT(self) -> None:
        route = urlparse(self.path)
        if route.path != "/local-upload":
            self.send_json(404, {"message": "Route not found"})
            return

        try:
            key = sanitize_filename(parse_qs(route.query).get("key", [""])[0])
        except ValueError as exc:
            self.send_json(400, {"message": str(exc)})
            return

        run_local.RAW.mkdir(parents=True, exist_ok=True)
        target = run_local.RAW / key
        target.write_bytes(self.read_body())

        # The same validator the deployed Lambda uses.
        try:
            run_local.process_file(target)
        except Exception as exc:  # surfaced to the browser, not swallowed
            self.send_json(500, {"message": f"Processing failed: {exc}"})
            return

        self.send_response(200)
        self.send_header("content-length", "0")
        self.end_headers()

    # -- handlers --------------------------------------------------------

    def serve_config(self) -> None:
        origin = self.origin()
        body = "\n".join(
            [
                "window.STREAMFORGE_CONFIG = {",
                f'  apiEndpoint: "{origin}",',
                f'  cognitoDomain: "{origin}",',
                '  clientId: "local-development",',
                f'  redirectUri: "{origin}/",',
                "};",
                "",
            ]
        ).encode()
        self.send_response(200)
        self.send_header("content-type", "application/javascript")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_create_upload(self) -> None:
        try:
            body = json.loads(self.read_body() or b"{}")
            key = sanitize_filename(body.get("filename"))
            size = int(body.get("size", 0))
            if size <= 0 or size > MAX_UPLOAD_BYTES:
                raise ValueError(
                    f"Upload size must be between 1 and {MAX_UPLOAD_BYTES} bytes"
                )
        except ValueError as exc:
            self.send_json(400, {"message": str(exc)})
            return

        self.send_json(
            201,
            {
                "upload_url": f"{self.origin()}/local-upload?key={key}",
                "key": key,
                "expires_in_seconds": 900,
            },
        )

    def handle_portal(self, route_key: str, query: dict) -> None:
        """Run the real portal_api handler against the local buckets."""
        if not portal_api.handles(route_key):
            self.send_json(404, {"message": "Route not found"})
            return

        # portal_api caches per process; drop it so local edits show up at once.
        portal_api._CACHE.clear()

        event = {"queryStringParameters": {k: v[0] for k, v in query.items()}}
        try:
            self.send_json(200, portal_api.handle(route_key, event, LocalS3(run_local.BUCKETS)))
        except ValueError as exc:
            self.send_json(400, {"message": str(exc)})
        except RuntimeError as exc:
            # Endpoints that genuinely need AWS (CloudWatch, Athena, Aurora).
            self.send_json(502, {"message": str(exc)})

    def manifest_path(self, key: str) -> Path:
        return run_local.MANIFESTS / Path(metadata.build_manifest_key(key))

    def handle_status(self, key: str) -> None:
        if not key:
            self.send_json(400, {"message": "A key is required"})
            return

        path = self.manifest_path(key)
        if not path.exists():
            self.send_json(200, {"status": "PROCESSING", "key": key})
            return

        manifest = json.loads(path.read_text(encoding="utf-8"))
        origin = self.origin()
        downloads = {}
        for folder in ("clean", "rejected"):
            if (run_local.BUCKETS / folder / key).exists():
                downloads[folder] = f"{origin}/download?path={folder}/{key}"

        self.send_json(
            200,
            {
                "status": "COMPLETE",
                "key": key,
                "batch_id": manifest["phase1_batch_id"],
                "source_filename": manifest["source_filename"],
                "processed_timestamp": manifest["phase1_processed_timestamp"],
                "total_records": manifest["total_records"],
                "valid_records": manifest["valid_records"],
                "invalid_records": manifest["invalid_records"],
                "downloads": downloads,
            },
        )

    def handle_download(self, rel: str) -> None:
        buckets = run_local.BUCKETS.resolve()
        target = (buckets / rel).resolve()
        # Never serve anything outside local_buckets/.
        if not target.is_relative_to(buckets) or not target.is_file():
            self.send_json(404, {"message": "Not found"})
            return

        body = target.read_bytes()
        self.send_response(200)
        self.send_header("content-type", "text/csv")
        self.send_header("content-disposition", f'attachment; filename="{target.name}"')
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main(argv: list[str]) -> int:
    port = int(argv[0]) if argv else 8000
    configure_portal_env()
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"StreamForge local dashboard: http://localhost:{port}")
    print("Sign-in is stubbed - clicking 'Sign in' logs you straight in.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
