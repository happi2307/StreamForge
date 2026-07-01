"""Baseline tests for customer validation."""

import importlib

import pandas as pd


validator = importlib.import_module("lambda.validator")


def test_valid_email() -> None:
    assert validator.is_valid_email("john@gmail.com")


def test_invalid_email() -> None:
    assert not validator.is_valid_email("johngmail.com")


def test_validation_rules_and_duplicates() -> None:
    data = pd.DataFrame(
        [
            {"customer_id": 101, "name": "John", "email": "john@gmail.com", "sales": 500},
            {"customer_id": 102, "name": "", "email": "mary@gmail.com", "sales": 600},
            {"customer_id": None, "name": "Sam", "email": "sam@gmail.com", "sales": 700},
            {"customer_id": 104, "name": "Raj", "email": "raj@gmail.com", "sales": "bad"},
            {"customer_id": 101, "name": "Jane", "email": "jane@gmail.com", "sales": 900},
        ]
    )

    clean, rejected = validator.validate_and_split(data)

    assert clean["customer_id"].tolist() == [101]
    assert len(rejected) == 4

