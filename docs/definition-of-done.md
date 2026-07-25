# Phase 4 definition of done

- [x] Backend bootstrap creates encrypted S3 state and DynamoDB locking.
- [x] Dev infrastructure is adopted into Terraform with an import and drift workflow.
- [x] Phase 1–3 resources are protected by KMS-backed controls and least-privilege IAM.
- [x] Monitoring, alerting resources, dashboard, DLQ, and incident runbooks are deployed in dev.
- [x] Terraform validation, formatting, and Python tests pass locally.
- [x] Configure and confirm the dev SNS email subscription; end-to-end topic delivery is verified.
- [ ] Test each CloudWatch alarm path and record the evidence in the runbooks.
- [x] Pull-request CI, security scanning, promotion workflow, and scheduled drift workflow are versioned in this repository.
- [x] Configure GitHub `dev` OIDC deployment role, environment variables, and an independent required reviewer.
- [ ] Configure the separate GitHub `prod` environment, required approvals, and OIDC deployment role.
- [ ] Create and validate the independent production environment in its target AWS account.
- [x] ADRs, recovery objectives, cost estimate, architecture documentation, and runbooks are present.
