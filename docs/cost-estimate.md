# Cost

Measured, not estimated. The figures below are the actual Cost Explorer numbers
for the deployed `dev` environment in `us-east-1`, so they include whatever the
free tier already absorbs.

## Measured — August 2026

Gross usage was **$11.74**. Credits covered all of it, so the net payable was
**$0.00**; the gross figure is the one that matters, because credits run out.

| Service | Cost | Share | Note |
| --- | ---: | ---: | --- |
| AWS WAF | $7.00 | 60% | Web ACL on CloudFront, plus per-rule charges |
| EC2 — Other | $2.74 | 23% | **Not StreamForge** — an unrelated 30 GB gp3 volume in `ap-south-1` |
| KMS | $2.00 | 17% | Two customer-managed keys at $1 each |
| RDS | <$0.01 | — | Aurora storage only; no cluster runs for StreamForge |
| S3 | <$0.01 | — | ~56 KB across seven buckets |
| DynamoDB, API Gateway, Lambda, Glue, Athena, CloudFront, Cognito, SNS, SQS | $0.00 | — | Inside the free tier at this volume |

Attributable to StreamForge: **$9.01/month**.

Two things dominate, and neither is the data pipeline:

- **WAF is 60% of the bill.** A CloudFront web ACL costs $5/month before a
  single request reaches it, plus $1 per rule. It is the only fixed cost of
  meaningful size in the platform.
- **KMS is 17%.** One key per environment at $1/month, plus API requests.

Compute is effectively free at portfolio volume. Lambda, Glue, Athena and
CloudFront all bill $0.00.

## Reproducing these numbers

The Cost Explorer API charges **$0.01 per request**, which is why the portal's
Cost page ships recorded figures rather than polling live:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-08-01,End=2026-09-01 \
  --granularity MONTHLY --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
  --group-by Type=DIMENSION,Key=SERVICE
```

Filtering on `RECORD_TYPE=Usage` matters: without it, credits net the total to
approximately zero and the report looks free.

## Forward-looking

| Item | Estimate | Basis |
| --- | ---: | --- |
| Phase 6 portal | $0–2/month | Frontend plus read-only API calls against infrastructure that already exists |
| Aurora Serverless v2 | $2–4/month | Only when the Warehouse page is wired to a live database |
| Aurora, as originally configured | $81/month | What `min_capacity = 0.5` plus five VPC interface endpoints would have cost |

### Why Aurora is cheap now

The Phase 5 module previously set `serverless_min_acu = 0.5`, a floor that bills
continuously — roughly $45/month for a cluster doing nothing. It now defaults to
`0` with `seconds_until_auto_pause`, so an idle cluster pauses. Measured on this
account, a scale-to-zero Aurora cluster cost **$0.51 over 11 days**.

The second saving is the **RDS Data API** (`enable_data_api`). Callers reach
Aurora over IAM without being inside the VPC, so a read-only path such as the
portal needs none of the five interface endpoints the in-VPC loader requires.
Those endpoints are about $7.30/month each.

Scale-to-zero requires Aurora PostgreSQL 16.3 or newer; the module defaults to
16.6.

## Controls

- Partitioned Parquet and Athena workgroup byte limits cap analytics spend.
- Lifecycle rules expire quarantine objects after 180 days and Athena results
  after 30.
- Reserved concurrency on the Lambdas bounds runaway invocation cost.
- `terraform destroy` on the dev environment returns the bill to zero.
