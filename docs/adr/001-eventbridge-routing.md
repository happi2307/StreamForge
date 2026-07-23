# ADR 001: Route S3 events through EventBridge

## Status

Accepted.

## Context

Raw S3 uploads must invoke Phase 1 validation and need a recoverable failure
path as the pipeline grows.

## Decision

Enable S3 EventBridge notifications and route matching object-created events to
Lambda through an EventBridge rule. Configure bounded retries and an encrypted
SQS dead-letter queue.

## Consequences

This adds a small delivery layer, but gives event filtering, future fan-out,
delivery metrics, retry control, and a durable investigation path for events
that Lambda cannot receive.
