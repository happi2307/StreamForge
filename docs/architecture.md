# Phase 1 Architecture

```mermaid
flowchart LR
    Upload[CSV upload] --> Raw[(Raw S3 bucket)]
    Raw --> EventBridge[Amazon EventBridge]
    EventBridge --> Lambda[AWS Lambda]
    Lambda --> Validation[Validate and clean]
    Validation --> Clean[(Clean S3 bucket)]
    Validation --> Rejected[(Rejected S3 bucket)]
    Lambda --> Logs[CloudWatch Logs]
```

Only the raw bucket emits object-created events. EventBridge routes those events
to the Python 3.12 Lambda. The Lambda reads the object, applies the validation
rules, and writes separate CSV outputs to the clean and rejected buckets.

