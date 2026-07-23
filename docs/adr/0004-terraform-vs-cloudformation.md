# ADR 0004: Terraform vs CloudFormation

- Status: Accepted
- Date: 2026-07-23

## Context

Phase 1-3 were deployed with the AWS CLI and PowerShell scripts. Phase 4 adopts
the running footprint as infrastructure as code so it can be recreated and
governed. The main options are Terraform and AWS CloudFormation.

## Decision

Use Terraform, adopting the existing resources with `terraform import` rather
than recreating them.

## Consequences

- The live stack is imported into state and reconciled with `plan` before any
  `apply`, so adoption is low risk (see `docs/terraform-import-guide.md`).
- Reusable modules (`kms`, `s3`, `phase1_runtime`, `phase2_analytics`,
  `phase3_curated`, `monitoring`) are shared across the `dev` and `prod` root
  modules.
- Remote state lives in the bootstrap S3 bucket with a DynamoDB lock table.
- Terraform is a separate toolchain from AWS-native CloudFormation and requires
  its own CLI and provider versions, pinned in `versions.tf`.
