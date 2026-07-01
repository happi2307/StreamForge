"""Validation and cleaning primitives for customer CSV records."""

from __future__ import annotations

import re

import pandas as pd


REQUIRED_COLUMNS = ("customer_id", "name", "email", "sales")
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def is_valid_email(value: object) -> bool:
    """Return whether *value* resembles a valid email address."""
    return isinstance(value, str) and bool(EMAIL_PATTERN.fullmatch(value.strip()))


def validate_and_split(data: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split customer rows into clean and rejected dataframes.

    Duplicate customer IDs are rejected after their first occurrence.
    """
    # Ensure both sides are sets of plain strings to avoid typing issues
    missing_columns = set(REQUIRED_COLUMNS) - set(map(str, data.columns))
    if missing_columns:
        names = ", ".join(sorted(missing_columns))
        raise ValueError(f"Missing required columns: {names}")

    frame = data.loc[:, REQUIRED_COLUMNS].copy()
    customer_present = frame["customer_id"].notna() & (
        frame["customer_id"].astype(str).str.strip() != ""
    )
    name_present = frame["name"].notna() & (
        frame["name"].astype(str).str.strip() != ""
    )
    email_valid = frame["email"].apply(is_valid_email)
    sales_numeric = pd.to_numeric(frame["sales"], errors="coerce").notna()
    first_customer_id = ~frame["customer_id"].duplicated(keep="first")

    valid = (
        customer_present
        & name_present
        & email_valid
        & sales_numeric
        & first_customer_id
    )
    return frame.loc[valid].copy(), frame.loc[~valid].copy()

