# CI/CD and promotion flow

```mermaid
flowchart TD
    Branch[Feature branch] --> CI[Tests, fmt, validate, security scans]
    CI --> PR[Pull request]
    PR --> Plan[Terraform plan for dev]
    Plan --> Approval[GitHub environment approval]
    Approval --> Dev[Manual deploy to dev]
    Dev --> Integration[Pipeline integration tests]
    Integration --> ProdApproval[Production approval]
    ProdApproval --> Prod[Manual deploy to prod]
    Drift[Scheduled drift plan] --> Review[Investigate and reconcile drift]
```

GitHub Actions uses OIDC roles configured per GitHub environment. Terraform
apply is intentionally manual and environment-gated; pull requests never
create infrastructure.
