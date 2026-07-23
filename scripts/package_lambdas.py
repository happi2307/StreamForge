#!/usr/bin/env python3
"""Build the Lambda deployment archives consumed by the Terraform environments.

The archives are deliberately generated during CI/CD and ignored by Git. This
keeps native Python dependencies compatible with the Lambda Python 3.12,
x86_64 runtime instead of relying on a developer's operating system.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PHASE1_SOURCE_FILES = ("handler.py", "metadata.py", "validator.py")
EXCLUDED_RUNTIME_DIRECTORIES = {"__pycache__", "test", "tests", "testing"}
EXCLUDED_RUNTIME_SUFFIXES = {".pyc", ".pyo"}


def add_tree(archive: ZipFile, source: Path) -> None:
    """Add a directory to an archive with deterministic member ordering."""
    for file_path in sorted(path for path in source.rglob("*") if path.is_file()):
        relative_path = file_path.relative_to(source)
        if (
            EXCLUDED_RUNTIME_DIRECTORIES.intersection(relative_path.parts)
            or file_path.suffix in EXCLUDED_RUNTIME_SUFFIXES
        ):
            continue
        archive.write(file_path, relative_path.as_posix())


def package_phase1(output_path: Path) -> None:
    """Build the Phase 1 archive with Linux-compatible pinned dependencies."""
    build_directory = REPOSITORY_ROOT / "build"
    build_directory.mkdir(exist_ok=True)
    staging_directory = Path(
        tempfile.mkdtemp(prefix="streamforge-phase1-", dir=build_directory)
    )
    try:
        subprocess.run(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--only-binary=:all:",
                "--platform",
                "manylinux2014_x86_64",
                "--implementation",
                "cp",
                "--python-version",
                "312",
                "--target",
                str(staging_directory),
                "--requirement",
                str(REPOSITORY_ROOT / "lambda" / "requirements.txt"),
            ],
            check=True,
        )

        for filename in PHASE1_SOURCE_FILES:
            shutil.copy2(REPOSITORY_ROOT / "lambda" / filename, staging_directory / filename)

        temporary_archive = build_directory / f"{output_path.name}.tmp"
        with ZipFile(temporary_archive, "w", ZIP_DEFLATED) as archive:
            add_tree(archive, staging_directory)
        os.replace(temporary_archive, output_path)
    finally:
        try:
            shutil.rmtree(staging_directory)
        except OSError as error:
            print(
                f"Warning: could not remove temporary build directory "
                f"{staging_directory}: {error}",
                file=sys.stderr,
            )


def package_dashboard(output_path: Path) -> None:
    """Build the standalone dashboard API archive."""
    with ZipFile(output_path, "w", ZIP_DEFLATED) as archive:
        archive.write(REPOSITORY_ROOT / "dashboard_api.py", "dashboard_api.py")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--environment",
        choices=("dev", "prod"),
        required=True,
        help="Terraform environment directory that receives function.zip.",
    )
    parser.add_argument(
        "--include-dashboard",
        action="store_true",
        help="Also write dashboard-api.zip for the dev web console.",
    )
    args = parser.parse_args()

    output_directory = REPOSITORY_ROOT / "terraform" / "environments" / args.environment
    output_directory.mkdir(parents=True, exist_ok=True)

    phase1_archive = output_directory / "function.zip"
    package_phase1(phase1_archive)
    print(f"Created {phase1_archive.relative_to(REPOSITORY_ROOT)}")

    if args.include_dashboard:
        dashboard_archive = output_directory / "dashboard-api.zip"
        package_dashboard(dashboard_archive)
        print(f"Created {dashboard_archive.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
