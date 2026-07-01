"""AWS Lambda entry point for customer CSV processing."""

from __future__ import annotations

import logging
from typing import Any


LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, int]:
    """Handle an S3 event delivered by EventBridge.

    S3 integration is intentionally added in the implementation step; this
    starter fails visibly instead of silently accepting an unprocessed event.
    """
    LOGGER.info("Received EventBridge event")
    raise NotImplementedError("S3 processing has not been implemented yet")

