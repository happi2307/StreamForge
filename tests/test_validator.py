"""Unit tests for customer validation and cleaning."""

import importlib

import pandas as pd
import pytest


validator = importlib.import_module("lambda.validator")


def _frame(rows: list[dict]) -> pd.DataFrame:
    return pd.DataFrame(rows, columns=list(validator.REQUIRED_COLUMNS))


def test_valid_email() -> None:
    assert validator.is_valid_email("john@gmail.com")


@pytest.mark.parametrize("value", ["johngmail.com", "john@", "@gmail.com", "", None, 5])
def test_invalid_email(value: object) -> None:
    assert not validator.is_valid_email(value)


def test_missing_name_is_rejected() -> None:
    clean, rejected = validator.validate_and_split(
        _frame([{"customer_id": 1, "name": "", "email": "a@b.com", "sales": 10}])
    )
    assert clean.empty
    assert len(rejected) == 1


def test_missing_customer_id_is_rejected() -> None:
    clean, rejected = validator.validate_and_split(
        _frame([{"customer_id": None, "name": "Sam", "email": "a@b.com", "sales": 10}])
    )
    assert clean.empty
    assert len(rejected) == 1


def test_duplicate_customer_id_keeps_first() -> None:
    clean, rejected = validator.validate_and_split(
        _frame(
            [
                {"customer_id": 1, "name": "First", "email": "a@b.com", "sales": 10},
                {"customer_id": 1, "name": "Second", "email": "c@d.com", "sales": 20},
            ]
        )
    )
    assert clean["name"].tolist() == ["First"]
    assert rejected["name"].tolist() == ["Second"]


def test_non_numeric_sales_is_rejected() -> None:
    clean, rejected = validator.validate_and_split(
        _frame([{"customer_id": 1, "name": "Sam", "email": "a@b.com", "sales": "bad"}])
    )
    assert clean.empty
    assert len(rejected) == 1


def test_numeric_sales_is_accepted() -> None:
    clean, _ = validator.validate_and_split(
        _frame([{"customer_id": 1, "name": "Sam", "email": "a@b.com", "sales": "500"}])
    )
    assert len(clean) == 1


def test_missing_column_raises() -> None:
    with pytest.raises(ValueError, match="Missing required columns"):
        validator.validate_and_split(pd.DataFrame({"customer_id": [1]}))


def test_end_to_end_split_matches_spec() -> None:
    data = _frame(
        [
            {"customer_id": 101, "name": "John", "email": "john@gmail.com", "sales": 500},
            {"customer_id": 102, "name": "", "email": "mary@gmail.com", "sales": 600},
            {"customer_id": 103, "name": "Sam", "email": "samgmail.com", "sales": 700},
            {"customer_id": 104, "name": "Raj", "email": "raj@gmail.com", "sales": 1000},
        ]
    )
    clean, rejected = validator.validate_and_split(data)
    assert clean["customer_id"].tolist() == [101, 104]
    assert rejected["customer_id"].tolist() == [102, 103]
