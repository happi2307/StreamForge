# Monitoring flow

```mermaid
flowchart LR
    EB[EventBridge raw-upload rule] --> Lambda[Phase 1 Lambda]
    EB -->|delivery exhausted| DLQ[KMS-encrypted SQS DLQ]
    Lambda --> Logs[KMS-encrypted CloudWatch Logs]
    Glue[Phase 3 Glue job] --> Metrics[Pipeline quality metrics]
    Lambda --> Alarm[CloudWatch alarms]
    EB --> Alarm
    Metrics --> Alarm
    Glue --> FailureRule[Glue failure EventBridge rule]
    Athena[Athena workgroups] --> AthenaRule[Athena failure EventBridge rule]
    Alarm --> SNS[KMS-encrypted SNS alerts]
    FailureRule --> SNS
    AthenaRule --> SNS
    SNS --> Email[Confirmed email subscriber]
```

The dashboard combines Lambda error/throttle metrics, EventBridge delivery
failures, and batch-level Phase 3 data-quality metrics. Alerts do not contain
customer records or source file contents.
