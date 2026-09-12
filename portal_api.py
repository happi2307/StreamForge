"""Read-only endpoints backing the StreamForge portal pages.

Kept separate from dashboard_api so the upload path -- the one thing that must
not break -- stays small and easy to review. dashboard_api.lambda_handler
delegates here for every `GET /api/*` route and wraps the returned payload.

Every handler returns a plain dict and raises ValueError for bad input; HTTP
shaping is dashboard_api's job.
"""

from __future__ import annotations

import json
import os
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Iterable

import boto3
from botocore.exceptions import ClientError


# Warm containers reuse these, so a page revisit costs no AWS calls.
CACHE_TTL_SECONDS = 60
_CACHE: dict[str, tuple[float, Any]] = {}

# Cap the manifest scan so a large metadata bucket cannot blow the Lambda's
# memory or the API Gateway timeout.
MAX_MANIFESTS = 500
MAX_LIST_KEYS = 1000
ATHENA_TIMEOUT_SECONDS = 12

# Lake zone name -> environment variable holding its bucket name.
ZONES: tuple[tuple[str, str], ...] = (
    ("raw", "RAW_BUCKET"),
    ("clean", "CLEAN_BUCKET"),
    ("rejected", "REJECTED_BUCKET"),
    ("metadata", "METADATA_BUCKET"),
    ("curated", "CURATED_BUCKET"),
    ("quarantine", "QUARANTINE_BUCKET"),
    ("athena_results", "ATHENA_RESULTS_BUCKET"),
)

ZONE_PURPOSE = {
    "raw": "Untrusted CSV landing zone. Writes here trigger the pipeline.",
    "clean": "Rows that passed every validation rule.",
    "rejected": "Rows that failed validation, kept for audit.",
    "metadata": "One lineage manifest per processed batch.",
    "curated": "Partitioned Parquet, ready for Athena and the serving layer.",
    "quarantine": "Rows the Glue transform could not process.",
    "athena_results": "Encrypted query output.",
}


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _cached(key: str, producer: Callable[[], Any], ttl: int = CACHE_TTL_SECONDS) -> Any:
    hit = _CACHE.get(key)
    now = time.time()
    if hit and now < hit[0]:
        return hit[1]
    value = producer()
    _CACHE[key] = (now + ttl, value)
    return value


def _client(service: str) -> Any:
    return boto3.client(service)


def _iso(value: Any) -> str | None:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    return value


# ---------------------------------------------------------------------------
# Shared readers
# ---------------------------------------------------------------------------

def _list_objects(s3: Any, bucket: str, prefix: str = "") -> list[dict[str, Any]]:
    """Every object under a prefix, capped at MAX_LIST_KEYS."""
    objects: list[dict[str, Any]] = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            objects.append(
                {
                    "key": item["Key"],
                    "size": item["Size"],
                    "last_modified": _iso(item["LastModified"]),
                    "storage_class": item.get("StorageClass", "STANDARD"),
                }
            )
            if len(objects) >= MAX_LIST_KEYS:
                return objects
    return objects


def _manifests(s3: Any) -> list[dict[str, Any]]:
    """Every Phase 1 lineage manifest, newest first."""

    def load() -> list[dict[str, Any]]:
        bucket = _env("METADATA_BUCKET")
        prefix = _env("METADATA_PREFIX", "metadata").strip("/")
        if not bucket:
            return []

        records: list[dict[str, Any]] = []
        for item in _list_objects(s3, bucket, f"{prefix}/"):
            if not item["key"].endswith(".json") or len(records) >= MAX_MANIFESTS:
                continue
            try:
                body = s3.get_object(Bucket=bucket, Key=item["key"])["Body"].read()
                manifest = json.loads(body.decode("utf-8"))
            except (ClientError, json.JSONDecodeError, UnicodeDecodeError):
                # One unreadable manifest must not blank the whole page.
                continue
            manifest["_key"] = item["key"]
            records.append(manifest)

        records.sort(key=lambda m: str(m.get("phase1_processed_timestamp", "")), reverse=True)
        return records

    return _cached("manifests", load)


def _zone_buckets() -> dict[str, str]:
    return {zone: _env(var) for zone, var in ZONES if _env(var)}


# ---------------------------------------------------------------------------
# GET /api/storage
# ---------------------------------------------------------------------------

def _bucket_encryption(s3: Any, bucket: str) -> str:
    try:
        rules = s3.get_bucket_encryption(Bucket=bucket)["ServerSideEncryptionConfiguration"]["Rules"]
        algorithm = rules[0]["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"]
        return {"aws:kms": "SSE-KMS", "AES256": "SSE-S3"}.get(algorithm, algorithm)
    except (ClientError, KeyError, IndexError):
        return "unknown"


def _bucket_lifecycle(s3: Any, bucket: str) -> str:
    try:
        rules = s3.get_bucket_lifecycle_configuration(Bucket=bucket)["Rules"]
    except ClientError:
        return "none"
    enabled = [r for r in rules if r.get("Status") == "Enabled"]
    return f"{len(enabled)} rule{'s' if len(enabled) != 1 else ''}" if enabled else "none"


def storage(event: dict[str, Any], s3: Any) -> dict[str, Any]:
    """Per-zone totals, or a folder listing when `zone` is supplied."""
    params = event.get("queryStringParameters") or {}
    buckets = _zone_buckets()
    zone = str(params.get("zone", "")).strip()

    if zone:
        if zone not in buckets:
            raise ValueError(f"Unknown zone: {zone}")
        prefix = str(params.get("prefix", ""))
        objects = _list_objects(s3, buckets[zone], prefix)
        return {
            "zone": zone,
            "bucket": buckets[zone],
            "prefix": prefix,
            "objects": sorted(objects, key=lambda o: o["last_modified"] or "", reverse=True)[:200],
            "truncated": len(objects) >= MAX_LIST_KEYS,
        }

    def load() -> dict[str, Any]:
        zones = []
        for name, bucket in buckets.items():
            objects = _list_objects(s3, bucket)
            latest = max((o["last_modified"] or "" for o in objects), default=None)
            zones.append(
                {
                    "zone": name,
                    "bucket": bucket,
                    "purpose": ZONE_PURPOSE.get(name, ""),
                    "object_count": len(objects),
                    "total_bytes": sum(o["size"] for o in objects),
                    "latest_object": latest or None,
                    "encryption": _bucket_encryption(s3, bucket),
                    "lifecycle": _bucket_lifecycle(s3, bucket),
                    "partitioned": any("=" in o["key"] for o in objects),
                }
            )
        return {"zones": zones}

    return _cached("storage", load)


# ---------------------------------------------------------------------------
# GET /api/dashboard
# ---------------------------------------------------------------------------

def dashboard(event: dict[str, Any], s3: Any) -> dict[str, Any]:
    manifests = _manifests(s3)
    zones = storage({}, s3)["zones"]
    by_zone = {z["zone"]: z for z in zones}

    total = sum(int(m.get("total_records", 0) or 0) for m in manifests)
    valid = sum(int(m.get("valid_records", 0) or 0) for m in manifests)
    invalid = sum(int(m.get("invalid_records", 0) or 0) for m in manifests)

    daily: dict[str, dict[str, int]] = defaultdict(lambda: {"files": 0, "valid": 0, "invalid": 0})
    for manifest in manifests:
        stamp = str(manifest.get("phase1_processed_timestamp", ""))[:10]
        if not stamp:
            continue
        bucket = daily[stamp]
        bucket["files"] += 1
        bucket["valid"] += int(manifest.get("valid_records", 0) or 0)
        bucket["invalid"] += int(manifest.get("invalid_records", 0) or 0)

    series = [{"date": day, **counts} for day, counts in sorted(daily.items())]

    return {
        "files_processed": len(manifests),
        "records_processed": total,
        "valid_records": valid,
        "failed_records": invalid,
        "success_rate": round(valid / total * 100, 1) if total else None,
        "curated_objects": by_zone.get("curated", {}).get("object_count", 0),
        "quarantined_objects": by_zone.get("quarantine", {}).get("object_count", 0),
        "storage_bytes": sum(z["total_bytes"] for z in zones),
        "storage_by_zone": [
            {"zone": z["zone"], "bytes": z["total_bytes"], "objects": z["object_count"]} for z in zones
        ],
        "daily": series,
        "latest_batch": manifests[0] if manifests else None,
    }


# ---------------------------------------------------------------------------
# GET /api/metadata
# ---------------------------------------------------------------------------

def metadata(event: dict[str, Any], s3: Any) -> dict[str, Any]:
    params = event.get("queryStringParameters") or {}
    search = str(params.get("search", "")).strip().lower()
    status = str(params.get("status", "")).strip().lower()

    try:
        limit = max(1, min(200, int(params.get("limit", 50))))
        offset = max(0, int(params.get("offset", 0)))
    except (TypeError, ValueError) as exc:
        raise ValueError("limit and offset must be integers") from exc

    rows = []
    for manifest in _manifests(s3):
        invalid = int(manifest.get("invalid_records", 0) or 0)
        row = {
            "batch_id": manifest.get("phase1_batch_id"),
            "pipeline_version": manifest.get("phase1_pipeline_version"),
            "source_filename": manifest.get("source_filename"),
            "processed_timestamp": manifest.get("phase1_processed_timestamp"),
            "total_records": manifest.get("total_records"),
            "valid_records": manifest.get("valid_records"),
            "invalid_records": invalid,
            "execution_duration_ms": manifest.get("execution_duration_ms"),
            "raw_key": manifest.get("raw_key"),
            "clean_key": manifest.get("clean_key"),
            "rejected_key": manifest.get("rejected_key"),
            "validation_status": "CLEAN" if invalid == 0 else "PARTIAL",
        }
        if status and row["validation_status"].lower() != status:
            continue
        if search and search not in json.dumps(row, default=str).lower():
            continue
        rows.append(row)

    return {"total": len(rows), "offset": offset, "limit": limit, "items": rows[offset:offset + limit]}


# ---------------------------------------------------------------------------
# GET /api/lineage
# ---------------------------------------------------------------------------

def lineage(event: dict[str, Any], s3: Any) -> dict[str, Any]:
    """The pipeline graph, annotated with real counts from the manifests."""
    params = event.get("queryStringParameters") or {}
    batch_id = str(params.get("batch_id", "")).strip()

    manifests = _manifests(s3)
    selected = next((m for m in manifests if m.get("phase1_batch_id") == batch_id), None) if batch_id else None
    if selected is None and manifests:
        selected = manifests[0]

    zones = {z["zone"]: z for z in storage({}, s3)["zones"]}
    totals = {
        "total": sum(int(m.get("total_records", 0) or 0) for m in manifests),
        "valid": sum(int(m.get("valid_records", 0) or 0) for m in manifests),
        "invalid": sum(int(m.get("invalid_records", 0) or 0) for m in manifests),
    }

    def zone_count(name: str) -> int:
        return zones.get(name, {}).get("object_count", 0)

    stages = [
        {
            "id": "upload",
            "label": "CSV upload",
            "purpose": "A signed-in user uploads a CSV through a presigned S3 PUT. The browser never holds AWS credentials.",
            "input": "Local CSV file",
            "output": f"s3://{zones.get('raw', {}).get('bucket', 'raw')}/uploads/",
            "records": totals["total"],
            "unit": "records",
            "transformations": ["Filename sanitised", "Size capped at 10 MB", "Content-type pinned to text/csv"],
        },
        {
            "id": "raw",
            "label": "Raw zone",
            "purpose": "Immutable landing area. Objects are versioned and encrypted with the project KMS key.",
            "input": "Presigned upload",
            "output": "EventBridge Object Created event",
            "records": zone_count("raw"),
            "unit": "objects",
            "transformations": ["SSE-KMS applied", "Version recorded"],
        },
        {
            "id": "validation",
            "label": "Validation Lambda",
            "purpose": "Applies the five row rules and splits the batch into clean and rejected outputs.",
            "input": "Raw CSV object",
            "output": "Clean rows, rejected rows, lineage manifest",
            "records": totals["total"],
            "unit": "records",
            "duration_ms": selected.get("execution_duration_ms") if selected else None,
            "transformations": [
                "customer_id present",
                "name present",
                "email matches pattern",
                "sales numeric",
                "duplicate customer_id rejected after first",
            ],
        },
        {
            "id": "clean",
            "label": "Clean zone",
            "purpose": "Rows that passed every rule, ready for cataloguing and transformation.",
            "input": "Validated rows",
            "output": "Glue crawler input",
            "records": totals["valid"],
            "unit": "records",
            "transformations": [],
        },
        {
            "id": "etl",
            "label": "Glue ETL",
            "purpose": "Business transforms, categorisation and Parquet conversion.",
            "input": "Clean CSV",
            "output": "Curated Parquet and quarantined rows",
            "records": None,
            "transformations": ["sales_category derived", "Snappy Parquet", "Partitioned by year/month/day"],
        },
        {
            "id": "curated",
            "label": "Curated zone",
            "purpose": "Analytics-ready Parquet, partitioned for cheap Athena scans.",
            "input": "Transformed rows",
            "output": "Athena table and serving-layer load",
            "records": zone_count("curated"),
            "unit": "objects",
            "transformations": [],
        },
        {
            "id": "athena",
            "label": "Athena",
            "purpose": "SQL over the curated dataset through the Glue Data Catalog.",
            "input": "Curated Parquet",
            "output": "Query results",
            "records": None,
            "transformations": [],
        },
        {
            "id": "aurora",
            "label": "Aurora PostgreSQL",
            "purpose": "Relational serving layer loaded incrementally with idempotent MERGE statements.",
            "input": "Curated Parquet",
            "output": "Queryable tables and audit history",
            "records": None,
            "transformations": [],
        },
        {
            "id": "portal",
            "label": "This portal",
            "purpose": "Reads every layer above to present the platform without the AWS console.",
            "input": "S3, Glue, Athena, CloudWatch, Aurora",
            "output": "Dashboards",
            "records": None,
            "transformations": [],
        },
    ]

    return {
        "batch_id": selected.get("phase1_batch_id") if selected else None,
        "source_filename": selected.get("source_filename") if selected else None,
        "stages": stages,
        "available_batches": [
            {"batch_id": m.get("phase1_batch_id"), "source_filename": m.get("source_filename"),
             "processed_timestamp": m.get("phase1_processed_timestamp")}
            for m in manifests[:25]
        ],
    }


# ---------------------------------------------------------------------------
# GET /api/metrics
# ---------------------------------------------------------------------------

def _metric_query(ident: str, namespace: str, name: str, dimensions: dict[str, str], stat: str) -> dict[str, Any]:
    return {
        "Id": ident,
        "MetricStat": {
            "Metric": {
                "Namespace": namespace,
                "MetricName": name,
                "Dimensions": [{"Name": k, "Value": v} for k, v in dimensions.items()],
            },
            "Period": 3600,
            "Stat": stat,
        },
        "ReturnData": True,
    }


def metrics(event: dict[str, Any], _s3: Any) -> dict[str, Any]:
    def load() -> dict[str, Any]:
        cloudwatch = _client("cloudwatch")
        end = datetime.now(timezone.utc)
        start = end - timedelta(days=7)

        functions = [f for f in (_env("PROCESSOR_FUNCTION_NAME"), _env("DASHBOARD_FUNCTION_NAME")) if f]
        queries = []
        for index, function in enumerate(functions):
            for suffix, name, stat in (("inv", "Invocations", "Sum"), ("err", "Errors", "Sum"), ("dur", "Duration", "Average")):
                queries.append(_metric_query(f"f{index}{suffix}", "AWS/Lambda", name, {"FunctionName": function}, stat))

        series: list[dict[str, Any]] = []
        if queries:
            try:
                response = cloudwatch.get_metric_data(
                    MetricDataQueries=queries, StartTime=start, EndTime=end, ScanBy="TimestampAscending"
                )
                for result in response.get("MetricDataResults", []):
                    series.append(
                        {
                            "id": result["Id"],
                            "label": result.get("Label"),
                            "timestamps": [_iso(t) for t in result.get("Timestamps", [])],
                            "values": result.get("Values", []),
                        }
                    )
            except ClientError as exc:
                series = []
                _CACHE.pop("metrics", None)
                raise RuntimeError(
                    f"CloudWatch rejected the metric query: {exc.response.get('Error', {}).get('Code', 'unknown')}"
                ) from exc

        alarms = []
        try:
            for alarm in _client("cloudwatch").describe_alarms().get("MetricAlarms", []):
                alarms.append(
                    {
                        "name": alarm["AlarmName"],
                        "state": alarm["StateValue"],
                        "metric": alarm.get("MetricName"),
                        "updated": _iso(alarm.get("StateUpdatedTimestamp")),
                        "description": alarm.get("AlarmDescription"),
                    }
                )
        except ClientError:
            alarms = []

        return {
            "window_days": 7,
            "functions": functions,
            "series": series,
            "alarms": sorted(alarms, key=lambda a: (a["state"] != "ALARM", a["name"])),
        }

    return _cached("metrics", load, ttl=120)


# ---------------------------------------------------------------------------
# GET /api/pipeline
# ---------------------------------------------------------------------------

def pipeline(event: dict[str, Any], s3: Any) -> dict[str, Any]:
    manifests = _manifests(s3)
    total = sum(int(m.get("total_records", 0) or 0) for m in manifests)
    valid = sum(int(m.get("valid_records", 0) or 0) for m in manifests)

    durations = [float(m["execution_duration_ms"]) for m in manifests if m.get("execution_duration_ms")]

    components = [
        {
            "name": "Phase 1 Lambda",
            "service": "AWS Lambda",
            "role": "Validates and splits every uploaded CSV",
            "status": "healthy" if manifests else "idle",
            "detail": f"{len(manifests)} batches processed",
        },
        {
            "name": "EventBridge",
            "service": "Amazon EventBridge",
            "role": "Routes raw-bucket object events to the validator",
            "status": "healthy" if manifests else "idle",
            "detail": "Object Created rule on the raw bucket",
        },
        {
            "name": "Glue ETL",
            "service": "AWS Glue",
            "role": "Business transforms and Parquet conversion",
            "status": "healthy",
            "detail": _env("GLUE_JOB_NAME") or "streamforge-transform-customers",
        },
        {
            "name": "Athena",
            "service": "Amazon Athena",
            "role": "SQL over the curated dataset",
            "status": "healthy",
            "detail": _env("ATHENA_WORKGROUP") or "streamforge-phase3",
        },
        {
            "name": "Aurora PostgreSQL",
            "service": "Amazon RDS",
            "role": "Relational serving layer",
            "status": "not-deployed" if not _env("AURORA_CLUSTER_ARN") else "healthy",
            "detail": "Phase 5 is not deployed in this environment"
            if not _env("AURORA_CLUSTER_ARN")
            else _env("AURORA_CLUSTER_ARN").rsplit(":", 1)[-1],
        },
    ]

    return {
        "components": components,
        "success_rate": round(valid / total * 100, 1) if total else None,
        "batches_processed": len(manifests),
        "average_duration_ms": round(sum(durations) / len(durations), 1) if durations else None,
        "latest_run": manifests[0].get("phase1_processed_timestamp") if manifests else None,
        "recent_batches": [
            {
                "batch_id": m.get("phase1_batch_id"),
                "source_filename": m.get("source_filename"),
                "processed_timestamp": m.get("phase1_processed_timestamp"),
                "total_records": m.get("total_records"),
                "valid_records": m.get("valid_records"),
                "invalid_records": m.get("invalid_records"),
                "duration_ms": m.get("execution_duration_ms"),
            }
            for m in manifests[:15]
        ],
    }


# ---------------------------------------------------------------------------
# GET /api/analytics
# ---------------------------------------------------------------------------

ANALYTICS_QUERIES = {
    "summary": "SELECT COUNT(*) AS records, COUNT(DISTINCT customer_id) AS customers, "
               "SUM(sales) AS revenue, AVG(sales) AS average_order FROM {table}",
    "by_category": "SELECT sales_category, COUNT(*) AS records, SUM(sales) AS revenue "
                   "FROM {table} GROUP BY sales_category ORDER BY revenue DESC",
    "by_day": "SELECT year, month, day, COUNT(*) AS records, SUM(sales) AS revenue "
              "FROM {table} GROUP BY year, month, day ORDER BY year, month, day",
    "top_customers": "SELECT customer_id, name, SUM(sales) AS revenue FROM {table} "
                     "GROUP BY customer_id, name ORDER BY revenue DESC LIMIT 10",
}


def _run_athena(query: str) -> list[dict[str, Any]]:
    athena = _client("athena")
    workgroup = _env("ATHENA_WORKGROUP")
    database = _env("GLUE_DATABASE")
    if not workgroup or not database:
        raise RuntimeError("Athena is not configured for this environment")

    started = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": database},
        WorkGroup=workgroup,
    )["QueryExecutionId"]

    deadline = time.time() + ATHENA_TIMEOUT_SECONDS
    while time.time() < deadline:
        execution = athena.get_query_execution(QueryExecutionId=started)["QueryExecution"]
        state = execution["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in {"FAILED", "CANCELLED"}:
            reason = execution["Status"].get("StateChangeReason", state)
            raise RuntimeError(f"Athena query {state.lower()}: {reason}")
        time.sleep(0.4)
    else:
        raise RuntimeError("Athena query did not finish within the request budget")

    result = athena.get_query_results(QueryExecutionId=started, MaxResults=100)
    rows = result["ResultSet"]["Rows"]
    if not rows:
        return []

    headers = [c.get("VarCharValue", "") for c in rows[0]["Data"]]
    records = []
    for row in rows[1:]:
        values = [c.get("VarCharValue") for c in row["Data"]]
        records.append(dict(zip(headers, values)))
    return records


def analytics(event: dict[str, Any], _s3: Any) -> dict[str, Any]:
    table = _env("CURATED_TABLE", "customers_curated")

    def load() -> dict[str, Any]:
        results: dict[str, Any] = {"table": table, "sections": {}, "errors": {}}
        for name, template in ANALYTICS_QUERIES.items():
            try:
                results["sections"][name] = _run_athena(template.format(table=f'"{table}"'))
            except (RuntimeError, ClientError) as exc:
                # One failing query should not blank the whole dashboard.
                results["errors"][name] = str(exc)
        return results

    return _cached("analytics", load, ttl=300)


# ---------------------------------------------------------------------------
# GET /api/warehouse
# ---------------------------------------------------------------------------

WAREHOUSE_QUERIES = {
    "tables": """
        SELECT table_schema, table_name,
               (SELECT COUNT(*) FROM information_schema.columns c
                 WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name) AS column_count
        FROM information_schema.tables t
        WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema')
        ORDER BY table_schema, table_name
    """,
    "columns": """
        SELECT table_schema, table_name, column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
        ORDER BY table_schema, table_name, ordinal_position
    """,
}


def warehouse(event: dict[str, Any], _s3: Any) -> dict[str, Any]:
    cluster_arn = _env("AURORA_CLUSTER_ARN")
    secret_arn = _env("AURORA_SECRET_ARN")
    database = _env("AURORA_DATABASE", "streamforge")

    if not cluster_arn or not secret_arn:
        return {
            "deployed": False,
            "reason": "Phase 5 is not deployed in this environment, so there is no Aurora cluster to inspect.",
        }

    def load() -> dict[str, Any]:
        data = _client("rds-data")
        sections: dict[str, Any] = {}
        for name, sql in WAREHOUSE_QUERIES.items():
            response = data.execute_statement(
                resourceArn=cluster_arn,
                secretArn=secret_arn,
                database=database,
                sql=sql,
                formatRecordsAs="JSON",
            )
            sections[name] = json.loads(response.get("formattedRecords", "[]"))
        return {"deployed": True, "database": database, **sections}

    try:
        return _cached("warehouse", load, ttl=300)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "unknown")
        return {
            "deployed": False,
            "reason": f"Aurora is configured but unreachable ({code}). The cluster may be paused or the Data API disabled.",
        }


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

ROUTES: dict[str, Callable[[dict[str, Any], Any], dict[str, Any]]] = {
    "GET /api/dashboard": dashboard,
    "GET /api/storage": storage,
    "GET /api/metadata": metadata,
    "GET /api/lineage": lineage,
    "GET /api/metrics": metrics,
    "GET /api/pipeline": pipeline,
    "GET /api/analytics": analytics,
    "GET /api/warehouse": warehouse,
}


def handles(route_key: str) -> bool:
    return route_key in ROUTES


def handle(route_key: str, event: dict[str, Any], s3: Any) -> dict[str, Any]:
    return ROUTES[route_key](event, s3)
