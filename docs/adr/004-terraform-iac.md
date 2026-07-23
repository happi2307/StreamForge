# ADR 004: Manage infrastructure with Terraform

## Status

Accepted.

## Context

The initial AWS footprint was created manually and needed a repeatable,
reviewable path for change, recovery, and drift detection.

## Decision

Adopt the AWS resources into Terraform using an encrypted S3 remote state
backend and DynamoDB locking. Use reusable service modules and separate
environment roots, beginning with the existing dev stack.

## Consequences

Infrastructure changes become reviewable plans with remote state protection.
Imports and reconciliation are required before an existing resource can be
managed, and operators must avoid console changes outside incident response.
