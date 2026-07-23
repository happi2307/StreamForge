# ADR 0001: EventBridge vs direct S3 notifications

- Status: Accepted
- Date: 2026-07-23

## Context

The Phase 1 Lambda must run when a CSV lands in the raw bucket. S3 can invoke
Lambda directly through bucket notifications, or it can emit events to Amazon
EventBridge which then routes them to targets.

## Decision

Route raw-bucket `Object Created` events through EventBridge to the Lambda.

## Consequences

- One event source can fan out to multiple targets later (for example the
  Phase 4 monitoring pipeline) without touching the bucket configuration.
- Rich content-based filtering lives in the EventBridge rule rather than in the
  Lambda, so unrelated objects never invoke the function.
- The raw bucket only needs the `EventBridge` notification toggle enabled; the
  routing is declared in `aws_cloudwatch_event_rule.raw_uploads`.
- Slightly more moving parts than a direct notification, and events are
  best-effort with at-least-once delivery, so the handler stays idempotent.
