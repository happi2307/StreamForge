# Disaster recovery

## Recovery objectives

StreamForge is a portfolio/dev data platform, not a production SLA service.
The working assumptions are an **RPO of 24 hours** for infrastructure and
configuration changes, and an **RTO of 4 hours** for dev pipeline restoration.
Production targets must be reviewed before a production environment is opened.

## Data recovery

All pipeline buckets use versioning. Recover an accidentally deleted object by
locating its prior version in S3 and restoring or copying that version to the
required key. Preserve raw objects and Phase 1 manifests; do not reconstruct
clean or curated data by hand when replaying the normal pipeline is possible.

## Infrastructure recovery

1. Confirm the remote state bucket and DynamoDB lock table are available.
2. Restore an earlier S3 state-object version only after reviewing the change
   that introduced the problem.
3. Run `terraform plan` from the relevant environment.
4. Apply only the reviewed recovery plan.
5. Run a no-drift plan and the pipeline smoke test afterwards.

## Regional or account loss

The backend bootstrap module and environment Terraform configuration are the
rebuild source. Bootstrap a new backend in the target account/region, configure
a new backend file, apply the environment, and replay retained raw data. This
is a manual, documented recovery process; cross-region replication is not yet
implemented.
