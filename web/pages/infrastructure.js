/**
 * Infrastructure viewer.
 *
 * A static map of the platform services to the Terraform modules that create
 * them. Kept in sync with terraform/modules/ by hand; nothing here calls AWS.
 */

import { el, pageHeader, panel, badge } from '../ui.js';

const SERVICES = [
  {
    name: 'Terraform',
    purpose: 'Single source of truth for every deployed resource. State lives in an encrypted, versioned S3 bucket with DynamoDB locking.',
    resources: 'Eleven modules under terraform/modules/, composed by terraform/environments/dev and /prod.',
    configuration: 'Remote backend configured per environment via backend.hcl, which is gitignored and never committed.',
    security: 'No credentials in state files. Secrets are referenced by ARN and resolved at runtime.',
    module: 'terraform/environments/dev',
  },
  {
    name: 'GitHub Actions',
    purpose: 'Runs tests, formatting, validation and security scans on every pull request, then gates deployment behind manual approval.',
    resources: 'Workflows in .github/workflows/, including a scheduled drift plan.',
    configuration: 'Terraform apply is manual and environment-gated. Pull requests plan but never apply.',
    security: 'No long-lived AWS keys. Credentials come from OIDC and expire with the job.',
    module: 'terraform/modules/github_actions_oidc',
  },
  {
    name: 'IAM',
    purpose: 'Least-privilege execution roles, one per function, scoped to the exact buckets and prefixes each needs.',
    resources: 'Execution roles for the Phase 1 processor, the dashboard API, the Glue jobs and the Phase 5 loader.',
    configuration: 'Inline policies generated from aws_iam_policy_document, with conditions on s3:prefix where applicable.',
    security: 'No wildcard resource ARNs outside of CloudWatch metrics, which are namespace-conditioned.',
    module: 'terraform/modules/phase1_runtime',
  },
  {
    name: 'GitHub OIDC',
    purpose: 'Lets CI assume a deployment role without storing AWS access keys anywhere.',
    resources: 'An OIDC identity provider plus per-environment deployment roles.',
    configuration: 'Trust policy restricted by repository and environment claims.',
    security: 'Credentials are short-lived and cannot be exfiltrated for reuse.',
    module: 'terraform/modules/github_actions_oidc',
  },
  {
    name: 'KMS',
    purpose: 'One customer-managed key encrypting every bucket, log group, queue, topic and database in the platform.',
    resources: 'A single CMK with an alias and automatic annual rotation.',
    configuration: 'Key policy grants only the service principals that need it.',
    security: 'SSE-KMS on all S3 objects. Cross-service grants are explicit.',
    module: 'terraform/modules/kms',
  },
  {
    name: 'Secrets Manager',
    purpose: 'Holds the Aurora master credentials, generated and rotated by RDS rather than set by a human.',
    resources: 'A managed master-user secret, encrypted with the project CMK.',
    configuration: 'manage_master_user_password is enabled, so the password never appears in Terraform state.',
    security: 'Read access limited to the loader and validation execution roles.',
    module: 'terraform/modules/phase5_serving',
  },
  {
    name: 'CloudWatch',
    purpose: 'Metrics, alarms, dashboards and encrypted log groups for every compute surface.',
    resources: 'Log groups per function, alarms on errors, throttles and duration, plus operations dashboards.',
    configuration: 'Thirty-day retention, KMS-encrypted log groups, custom pipeline-quality metrics from Glue.',
    security: 'Alerts carry batch identifiers only, never customer records or file contents.',
    module: 'terraform/modules/phase4_operations',
  },
  {
    name: 'SNS',
    purpose: 'Fan-out for operational alerts raised by alarms and EventBridge failure rules.',
    resources: 'One KMS-encrypted topic with a confirmed email subscriber.',
    configuration: 'Subscription is created only when operations_alert_email is set.',
    security: 'Topic policy restricts publishing to CloudWatch and EventBridge.',
    module: 'terraform/modules/phase4_operations',
  },
  {
    name: 'WAF',
    purpose: 'Managed rule groups in front of the CloudFront distribution serving this portal.',
    resources: 'A CLOUDFRONT-scoped web ACL.',
    configuration: 'Default allow with AWS managed rule groups evaluated first.',
    security: 'Blocks common exploit patterns before they reach the origin.',
    module: 'terraform/modules/web_static',
  },
  {
    name: 'Cognito',
    purpose: 'Authenticates portal users and issues the JWTs that authorize every API route.',
    resources: 'A user pool, an app client using OAuth2 authorization-code with PKCE, and a hosted domain.',
    configuration: 'Callback URLs cover both the CloudFront origin and http://localhost:8000 for local development.',
    security: 'No client secret. PKCE prevents code interception. Tokens are checked for expiry client-side.',
    module: 'terraform/modules/web_console',
  },
];

export function render(target) {
  target.append(pageHeader(
    'Infrastructure',
    'Every platform service, what it is for, and the Terraform module that creates it. All of it is provisioned as code; nothing here was clicked together in the console.',
  ));

  for (const service of SERVICES) {
    target.append(panel(service.name, [
      el('dl', { class: 'detail-list' }, [
        el('dt', { text: 'Purpose' }), el('dd', { text: service.purpose }),
        el('dt', { text: 'Resources' }), el('dd', { text: service.resources }),
        el('dt', { text: 'Configuration' }), el('dd', { text: service.configuration }),
        el('dt', { text: 'Security' }), el('dd', { text: service.security }),
        el('dt', { text: 'Terraform module' }), el('dd', {}, el('code', { class: 'inline-code', text: service.module })),
      ]),
    ], badge('IaC', 'ok')));
  }
}
