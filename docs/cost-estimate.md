# Cost estimate

This is a low-volume dev estimate for `us-east-1`; usage and regional prices
must be checked in the AWS Pricing Calculator before production deployment.

| Component | Planning estimate |
| --- | ---: |
| Customer-managed KMS key | about $1/month plus API requests |
| Five CloudWatch alarms | about $0.50/month plus notification/API use |
| Three custom Phase 3 metrics | about $0.90/month |
| CloudWatch dashboard | about $3/month for the initial dashboard |
| S3, Lambda, EventBridge, SNS, SQS | usage-based; typically minimal at manual-test volume |
| Glue and Athena | variable and potentially the largest cost; Glue worker time and Athena bytes scanned dominate |

The expected idle baseline is roughly **$5–10/month**, excluding data storage,
Glue runs, Athena scans, and any free-tier effects. Partitioned Parquet and
Athena workgroup limits are the primary cost controls for analytics.
