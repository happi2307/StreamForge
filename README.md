# StreamForge

A serverless AWS data platform that takes a CSV from a browser upload to a
queryable analytics dataset, and an operations portal that lets you watch it
happen without opening the AWS console.

Upload a file and it is validated row by row, split into clean and rejected
outputs, transformed into partitioned Parquet, catalogued for Athena, and
surfaced on twelve pages covering the lake, the warehouse, lineage, monitoring
and cost. Every hop is event-driven; nothing polls and nothing is started by
hand.

**Live:** https://d27fbjnqnw3vzk.cloudfront.net (Cognito sign-in required)

---

## Contents

- [What it does](#what-it-does)
- [The portal](#the-portal)
- [Phases](#phases)
- [Repository layout](#repository-layout)
- [Running it](#running-it)
- [Deploying](#deploying)
- [Cost](#cost)
- [Testing](#testing)
- [Design decisions worth knowing](#design-decisions-worth-knowing)

---

## What it does

```text
   Browser
      │  presigned PUT (no AWS credentials in the page)
      ▼
  ┌────────────┐   EventBridge    ┌──────────────────┐
  │  S3 raw    │─────────────────▶│ Phase 1 Lambda   │  validate + split
  └────────────┘  Object Created  └────────┬─────────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    ▼                      ▼                      ▼
              ┌───────────┐         ┌────────────┐        ┌──────────────┐
              │ S3 clean  │         │S3 rejected │        │ S3 metadata  │
              └─────┬─────┘         └────────────┘        │  (manifest)  │
                    │ EventBridge                         └──────────────┘
                    ▼
             ┌──────────────┐   Glue workflow + EVENT trigger
             │  Glue ETL    │   business transforms, Parquet
             └──────┬───────┘
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
    ┌────────────┐     ┌───────────────┐
    │ S3 curated │     │ S3 quarantine │  reason=invalid_sales/...
    │  Parquet   │     └───────────────┘
    └─────┬──────┘
          │
          ▼
     ┌─────────┐        ┌──────────────────────┐
     │ Athena  │        │ Aurora PostgreSQL    │  schema deployed,
     └─────────┘        │ (Serverless v2)      │  read-only from the portal
                        └──────────────────────┘
```

Validation answers *"is this row well formed?"* and produces the CSVs you
download. Glue answers *"make it useful to query"* and produces the Parquet
Athena reads. They are different layers with different jobs, and Glue is the
stricter of the two.

### The five validation rules

A row reaches the clean zone only if all five hold:

| Rule | Rejected when |
|---|---|
| `customer_id` present | blank or whitespace only |
| `name` present | blank or whitespace only |
| `email` well formed | fails `^[^@\s]+@[^@\s]+\.[^@\s]+$` |
| `sales` numeric | not parseable as a number |
| `customer_id` unique | a later duplicate; the first occurrence is kept |

Extra columns are dropped: only `customer_id`, `name`, `email` and `sales`
survive into the clean output.

---

## The portal

Twelve pages, built as plain ES modules with no build step and no
`node_modules`.

| Page | Reads |
|---|---|
| **Dashboard** | Platform totals and daily processing, from the lineage manifests |
| **Pipeline** | Component health and the most recent batches |
| **Upload** | The original console, plus a live processing timeline |
| **Data Lake** | All seven S3 zones, browsable to the object, with partitions |
| **Warehouse** | Aurora schemas, tables and columns via the RDS Data API |
| **Analytics** | Revenue, categories and top customers, via Athena over curated Parquet |
| **Lineage** | Interactive graph; selecting a stage shows its inputs, outputs and rules |
| **Metadata** | Searchable, filterable, paginated view of every batch manifest |
| **Monitoring** | CloudWatch Lambda metrics and alarm state |
| **Cost** | Measured spend by service, and what each decision would add |
| **Architecture** | Six zoomable diagrams: platform, lake, serving, CI/CD, security, monitoring |
| **Infrastructure** | Each service mapped to the Terraform module that creates it |

The upload timeline polls `GET /api/etl` for the real Glue run state, so the
Glue and Curated stages reflect what actually happened rather than sitting grey.

### API

All routes sit behind the same Cognito JWT authorizer. Nothing is public.

| Route | Purpose |
|---|---|
| `POST /uploads` | Issue a presigned PUT for the raw bucket |
| `GET /status` | Phase 1 result for one upload |
| `GET /api/dashboard` | Aggregated manifest totals and daily series |
| `GET /api/storage` | Per-zone totals, or a listing when `?zone=` is given |
| `GET /api/metadata` | Manifests, filtered and paginated |
| `GET /api/lineage` | The pipeline graph with real counts |
| `GET /api/metrics` | CloudWatch metrics and alarm state |
| `GET /api/pipeline` | Component health and recent batches |
| `GET /api/analytics` | Athena aggregates over the curated table |
| `GET /api/warehouse` | Aurora schema via the RDS Data API |
| `GET /api/etl` | Glue run state, for the upload timeline |

`dashboard_api.py` owns the upload path and delegates every `GET /api/*` route
to `portal_api.py`, which is kept separate so the upload path stays small and
easy to review.

---

## Phases

| Phase | Capability | What it added |
|---|---|---|
| **1** | Ingestion and quality | EventBridge-driven Lambda validation, clean/rejected outputs, a lineage manifest per batch |
| **2** | Query foundation | Glue crawler, Data Catalog, encrypted Athena workgroups |
| **3** | Business curation | Glue ETL, Parquet conversion, partitioning, quarantine zone |
| **4** | Platform engineering | Terraform, GitHub Actions with OIDC, KMS, CloudWatch, SNS, runbooks |
| **5** | Serving layer | Aurora PostgreSQL Serverless v2, loader Lambda, audit tables, private VPC |
| **6** | Enterprise portal | The twelve-page operations portal, and automatic ETL triggering |

Phase 6 originally scoped an Oracle to PostgreSQL migration using DMS and SCT.
That was removed; the decommission is commit `72ec5b7`. What remains under
`migration/` is a standalone Aurora data-integrity validation suite that stands
on its own.

---

## Repository layout

```text
web/                    The portal. Plain ES modules, no build step.
  index.html            Shell, nav, and the original upload console
  app.js                Upload logic and session handling
  router.js             Hash router, lazily imports each page
  api.js  ui.js         Fetch wrapper; DOM builders, tables, formatters
  charts.js  flow.js    Hand-built SVG charts; layered flow diagrams
  timeline.js           Upload timeline, polls real Glue state
  pages/*.js            One module per page

dashboard_api.py        Upload API: presigned PUT and status
portal_api.py           Read-only GET /api/* handlers

lambda/                 Phase 1 validator and the Phase 5 database loader
jobs/                   Phase 3 Glue transform and its helpers
database/               Aurora DDL: schema, indexes, constraints
migration/              Aurora data-integrity validation suite

terraform/
  environments/dev      The composed environment
  modules/              kms, s3, phase1_runtime, phase2_analytics,
                        phase3_curated, phase4_operations, phase5_serving,
                        web_console, web_static, github_actions_oidc

scripts/
  run_local.py          Run the Phase 1 pipeline against local folders
  local_server.py       Serve the whole portal with no AWS account
  package_lambdas.py    Build the deployment archives Terraform consumes
  bootstrap_schema.py   Apply the Aurora DDL via the RDS Data API

sample_data/            Test fixtures (see Testing)
docs/                   Architecture, ADRs, runbooks, cost, diagrams
```

---

## Running it

Three modes, in order of how much AWS they need.

### 1. The deployed portal — nothing to run

https://d27fbjnqnw3vzk.cloudfront.net

Sign in with a Cognito user. To set a password:

```bash
POOL=$(aws cognito-idp list-user-pools --max-results 10 \
  --query "UserPools[?contains(Name,'streamforge')].Id" --output text)
aws cognito-idp admin-set-user-password --user-pool-id "$POOL" \
  --username <your-email> --password '<12+ chars, mixed case, digit, symbol>' --permanent
```

### 2. Local page, real AWS backend

```bash
python -m http.server 8000 --directory web
```

Port **8000** exactly — it is registered in the Cognito callback URLs, the API
Gateway CORS allow-list and the raw bucket's CORS rules. `web/config.js` already
points at the deployed API, so the page talks to real infrastructure.

### 3. Fully local, no AWS account

```bash
python scripts/local_server.py        # http://localhost:8000
```

Stands in for Cognito, API Gateway and S3 presigned URLs from a single origin,
so there is no CORS to configure. Sign-in is stubbed: clicking "Sign in" logs
you straight in. Uploads run through the *real* validator via
`scripts/run_local.py`, and the portal endpoints run the *real* `portal_api`
handlers against `local_buckets/`. Endpoints that genuinely need AWS —
CloudWatch, Athena, Aurora — report as unavailable rather than returning
fabricated data.

The stubbed authentication is for local development and must never be deployed.

### Pipeline only, no UI

```bash
python scripts/run_local.py sample_data/subscribers.csv
```

Outputs land in `local_buckets/{clean,rejected,metadata}/`.

---

## Deploying

Terraform is the only supported path. Apply is manual and environment-gated;
pull requests plan but never apply.

```bash
# 1. Build the Lambda archives. They are gitignored and Terraform will not
#    apply without them.
python scripts/package_lambdas.py --environment dev --include-dashboard --include-loader

# 2. Backend config, gitignored, one per environment
cd terraform/environments/dev
cp backend.hcl.example backend.hcl        # fill in the account id

# 3. terraform.tfvars, gitignored. owner and cost_center are the only
#    required values, but an existing environment also needs the adoption
#    overrides -- see terraform.tfvars.example. Without bucket_name_overrides
#    the module's default naming does not match deployed buckets and every
#    data bucket is destroyed and recreated.
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan        # read this before applying
terraform apply
```

### Credentials

If `aws login` sessions are short in your account, Terraform's Go SDK may not
understand the `login_session` format at all. Export resolved credentials first:

```bash
aws configure export-credentials --format env > /tmp/creds.env
set -a; . /tmp/creds.env; set +a
```

A full apply that provisions Aurora can outlast a short-lived token. If it dies
mid-apply, Terraform writes `errored.tfstate`; push it back before retrying,
otherwise Terraform loses track of resources that exist:

```bash
terraform force-unlock -force <lock-id>
terraform state push errored.tfstate
```

### Aurora schema

The loader Lambda normally applies the DDL from inside the VPC, which requires
interface endpoints. With those disabled, use the Data API instead:

```bash
python scripts/bootstrap_schema.py
```

Idempotent; "already exists" is treated as success.

---

## Cost

Measured from Cost Explorer, not estimated. August 2026 gross usage was
**$11.74**, fully absorbed by credits.

| Service | Cost | Note |
|---|---:|---|
| AWS WAF | $7.00 | Web ACL on CloudFront, $5/month before a single request |
| KMS | $2.00 | Two customer-managed keys |
| Aurora Serverless v2 | ~$1–3 | `min_capacity = 0`, idles to zero |
| S3, Lambda, Glue, Athena, API Gateway, CloudFront, Cognito | ~$0.00 | Inside the free tier at this volume |

Two decisions keep the serving layer cheap:

- **`min_capacity = 0` with auto-pause.** The default 0.5 ACU floor bills
  continuously, roughly $45/month for an idle cluster. Scale-to-zero needs
  Aurora PostgreSQL 16.3 or newer; the module defaults to 17.7.
- **The RDS Data API instead of in-VPC access.** Callers reach Aurora over IAM
  without sitting inside the VPC, so the read path needs none of the five
  interface endpoints at ~$7.30/month each. `enable_vpc_endpoints` is off by
  default in dev.

Together these take the serving layer from about $81/month to the cost of
Aurora alone. The VPC, subnets and security groups were never the expense.

Full detail and the command to refresh these figures: [docs/cost-estimate.md](docs/cost-estimate.md).

---

## Testing

```bash
node --test web/app.test.js web/ui.test.mjs   # 22 tests, no dependencies
python migration/tests/test_migration.py      # 6 tests
terraform -chdir=terraform/environments/dev validate
```

The JS tests load browser code into a `node:vm` context with stubbed globals, so
they need no jsdom and no install. The migration tests stub `boto3` and `pg8000`
for the same reason.

### Fixtures

| File | Rows | Phase 1 | Phase 3 |
|---|---:|---|---|
| `customers.csv` | 4 | 2 valid / 2 rejected | — |
| `customers_sim.csv` | 22 | 8 valid / 14 rejected | — |
| `customers_large.csv` | 169 | 146 valid / 23 rejected | 141 curated / 5 quarantined |
| `subscribers.csv` | 209 | 184 valid / 25 rejected | 177 curated / 7 quarantined |

The two larger fixtures are deliberately unalike — different identifier schemes,
name pools, domains and extra columns — so batches are easy to tell apart in the
lineage and metadata views. Both exercise all five validation rules, and both
include rows that look invalid but must pass: zero and negative amounts,
plus-addressed and subdomained emails, whitespace-padded values, non-numeric
identifiers, and accented or apostrophed names.

Each also includes a small number of rows that the curated transform routes to
the quarantine zone, so that path is exercised on every run.

---

## Design decisions worth knowing

**The portal has no build step.** The CloudFront response headers policy sets
`default-src 'self'` with no `unsafe-inline`, which rules out CDN scripts,
Google Fonts, inline `<script>`/`<style>`, and `style` attributes in markup.
Charts are therefore hand-built SVG and diagrams are DOM, all constructed with
`createElement`. There is no bundler and no `node_modules`.

**Chart colours were validated, not chosen.** Green and red for valid versus
rejected scores ΔE 2.5 under deuteranopia — indistinguishable. The shipped pair
scores 17.3. Palettes and the command to re-check them are documented at the top
of `web/charts.js`.

**Pages report honestly when a dependency is missing.** The Warehouse page says
Phase 5 is not deployed rather than showing an invented schema, and the lineage
graph labels object counts as objects rather than records.

**EventBridge cannot start a Glue job directly.** The transform hangs off a Glue
workflow with an EVENT trigger, which EventBridge *can* start, rather than
introducing a Lambda whose only purpose is to call `start_job_run`. Event
batching coalesces bursts, so a group of uploads becomes a single run rather
than several racing the job's concurrency limit.

**Terraform never sees the database password.** `manage_master_user_password`
means RDS generates it straight into Secrets Manager; state holds only the ARN.

---

## Further reading

- [Architecture](docs/architecture.md) · [Database architecture](docs/database-architecture.md)
- [Cost estimate](docs/cost-estimate.md) · [Disaster recovery](docs/disaster-recovery.md)
- [ADRs](docs/adr/) · [Runbooks](docs/runbooks/) · [Diagrams](docs/diagrams/)
- [Terraform import guide](docs/terraform-import-guide.md)
- [Legacy manual deployment](docs/legacy-manual-deployment.md) — superseded, kept for reference
