# Diagrams

## Terraform module layout

```mermaid
flowchart TD
    subgraph Envs[Root modules]
        Dev[environments/dev]
        Prod[environments/prod]
    end
    subgraph Modules[Reusable modules]
        KMS[kms]
        S3[s3]
        P1[phase1_runtime]
        P2[phase2_analytics]
        P3[phase3_curated]
        Mon[monitoring]
    end
    Dev --> KMS & S3 & P1 & P2 & P3 & Mon
    Prod --> KMS & S3 & P1 & P2 & P3 & Mon
    Backend[(bootstrap/backend\nS3 state + DynamoDB lock)] -.state.- Dev
    Backend -.state.- Prod
```

## Monitoring and notification flow

```mermaid
flowchart LR
    Lambda[Phase 1 Lambda] -->|Errors / Throttles / Duration| Alarms[CloudWatch alarms]
    GlueJob[Phase 3 Glue job] -->|Job State Change| Rule[EventBridge rule]
    Alarms --> Topic[(SNS alerts topic)]
    Rule --> Topic
    Topic --> Email[Email subscription]
```

The infrastructure topology for the data plane itself is in
[../architecture.md](../architecture.md). CI/CD and security-architecture
diagrams are added as those workflows land.
