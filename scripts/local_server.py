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
import json
import re
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

run_local = importlib.import_module("scripts.run_local")
metadata = importlib.import_module("lambda.metadata")

WEB = ROOT / "web"
# Mirrors dashboard_api.MAX_UPLOAD_BYTES. Duplicated rather than imported
# because dashboard_api pulls in boto3, which local runs do not need.
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


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
