"""Apply the Phase 5 schema to Aurora through the RDS Data API.

The loader Lambda normally does this from inside the VPC, but that path needs
the five interface endpoints (~$36/month) purely so it can reach Secrets
Manager. With `enable_vpc_endpoints = false` the Data API does the same job
from outside the VPC at no cost.

The DDL is idempotent, so re-running is safe.

Usage:
    python scripts/bootstrap_schema.py --cluster-arn ... --secret-arn ...
    python scripts/bootstrap_schema.py            # resolves both from Terraform
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_FILES = ("schema.sql", "indexes.sql", "constraints.sql")


def split_statements(sql: str) -> list[str]:
    """Split on semicolons, ignoring those inside quotes, comments or $$ blocks.

    The Data API executes one statement per call, so a file has to be broken up.
    PL/pgSQL bodies are dollar-quoted (`DO $$ ... END $$;`) and contain their own
    semicolons, so those blocks must be treated as opaque.
    """
    text = re.sub(r"--[^\n]*", "", sql)
    statements: list[str] = []
    buffer: list[str] = []
    quote: str | None = None   # ' or "
    dollar: str | None = None  # the active $tag$ delimiter
    i = 0

    while i < len(text):
        char = text[i]

        if dollar:
            if text.startswith(dollar, i):
                buffer.append(dollar)
                i += len(dollar)
                dollar = None
                continue
        elif quote:
            if char == quote:
                quote = None
        else:
            tag = re.match(r"\$[A-Za-z_]*\$", text[i:])
            if tag:
                dollar = tag.group(0)
                buffer.append(dollar)
                i += len(dollar)
                continue
            if char in "'\"":
                quote = char
            elif char == ";":
                statement = "".join(buffer).strip()
                if statement:
                    statements.append(statement)
                buffer = []
                i += 1
                continue

        buffer.append(char)
        i += 1

    tail = "".join(buffer).strip()
    if tail:
        statements.append(tail)
    return statements


def terraform_output(name: str) -> str:
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform' / 'environments' / 'dev'}", "output", "-raw", name],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cluster-arn", default="")
    parser.add_argument("--secret-arn", default="")
    parser.add_argument("--database", default="streamforge")
    args = parser.parse_args()

    cluster_arn = args.cluster_arn or terraform_output("phase5_cluster_arn")
    secret_arn = args.secret_arn or terraform_output("phase5_database_secret_arn")

    data = boto3.client("rds-data")
    applied = 0
    failed = 0

    for filename in SCHEMA_FILES:
        path = ROOT / "database" / filename
        statements = split_statements(path.read_text(encoding="utf-8"))
        print(f"{filename}: {len(statements)} statements")

        for index, statement in enumerate(statements, start=1):
            try:
                data.execute_statement(
                    resourceArn=cluster_arn,
                    secretArn=secret_arn,
                    database=args.database,
                    sql=statement,
                )
                applied += 1
            except ClientError as exc:
                message = exc.response.get("Error", {}).get("Message", str(exc))
                # Idempotent DDL re-run: the object is already there.
                if "already exists" in message:
                    applied += 1
                    continue
                failed += 1
                print(f"  [{index}] FAILED: {message[:160]}", file=sys.stderr)
                print(f"       {statement[:120]}", file=sys.stderr)

    print(f"\napplied {applied} statements, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
