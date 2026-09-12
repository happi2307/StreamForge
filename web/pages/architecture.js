/**
 * Architecture viewer.
 *
 * Diagram content mirrors the real deployed topology and the Mermaid sources in
 * docs/diagrams/. Static by design -- nothing here calls AWS.
 */

import { el, pageHeader, panel } from '../ui.js';
import { flowDiagram, zoomable } from '../flow.js';

const DIAGRAMS = [
  {
    id: 'platform',
    title: 'Overall platform',
    blurb: 'Ingestion through to serving. Every hop is event-driven; nothing polls.',
    layers: [
      { nodes: [{ id: 'upload', label: 'CSV upload', sub: 'Browser → presigned PUT', tone: 'accent' }] },
      { nodes: [{ id: 'raw', label: 'S3 raw', sub: 'SSE-KMS, versioned' }] },
      { nodes: [{ id: 'eb', label: 'EventBridge', sub: 'Object Created rule' }] },
      { nodes: [{ id: 'validate', label: 'Phase 1 Lambda', sub: 'Validate and split' }] },
      {
        nodes: [
          { id: 'clean', label: 'S3 clean', sub: 'Valid rows', tone: 'ok' },
          { id: 'rejected', label: 'S3 rejected', sub: 'Failed rows', tone: 'bad' },
          { id: 'metadata', label: 'S3 metadata', sub: 'Lineage manifest' },
        ],
      },
      { nodes: [{ id: 'glue', label: 'Glue ETL', sub: 'Business transforms' }] },
      {
        nodes: [
          { id: 'curated', label: 'S3 curated', sub: 'Partitioned Parquet', tone: 'ok' },
          { id: 'quarantine', label: 'S3 quarantine', sub: 'Malformed rows', tone: 'bad' },
        ],
      },
      {
        nodes: [
          { id: 'athena', label: 'Athena', sub: 'Glue Data Catalog' },
          { id: 'aurora', label: 'Aurora PostgreSQL', sub: 'Serverless v2 serving layer' },
        ],
      },
      { nodes: [{ id: 'portal', label: 'This portal', sub: 'CloudFront → API Gateway → Lambda', tone: 'accent' }] },
    ],
  },
  {
    id: 'lake',
    title: 'Data lake zones',
    blurb: 'Seven buckets, each encrypted with the project KMS key and fronted by access logging.',
    layers: [
      { label: 'Landing', nodes: [{ id: 'z-raw', label: 'raw', sub: 'Untrusted input' }] },
      {
        label: 'Validated',
        nodes: [
          { id: 'z-clean', label: 'clean', sub: 'Schema-valid rows', tone: 'ok' },
          { id: 'z-rejected', label: 'rejected', sub: 'Rule violations', tone: 'bad' },
          { id: 'z-metadata', label: 'metadata', sub: 'Per-batch manifests' },
        ],
      },
      {
        label: 'Curated',
        nodes: [
          { id: 'z-curated', label: 'curated', sub: 'Parquet, partitioned', tone: 'ok' },
          { id: 'z-quarantine', label: 'quarantine', sub: 'Transform failures', tone: 'bad' },
        ],
      },
      { label: 'Query', nodes: [{ id: 'z-athena', label: 'athena-results', sub: 'Encrypted query output' }] },
    ],
  },
  {
    id: 'serving',
    title: 'Serving layer',
    blurb: 'Aurora sits in a private VPC with no NAT and no internet gateway; AWS APIs are reached over endpoints.',
    layers: [
      { nodes: [{ id: 's-curated', label: 'S3 curated', sub: 'Parquet written by Glue' }] },
      { nodes: [{ id: 's-eb', label: 'EventBridge', sub: 'Curated-object rule' }] },
      { nodes: [{ id: 's-loader', label: 'Loader Lambda', sub: 'In-VPC, idempotent MERGE' }] },
      {
        nodes: [
          { id: 's-secrets', label: 'Secrets Manager', sub: 'Rotating master password' },
          { id: 's-aurora', label: 'Aurora PostgreSQL', sub: 'Serverless v2', tone: 'accent' },
        ],
      },
      { nodes: [{ id: 's-audit', label: 'Audit tables', sub: 'Load history and row counts' }] },
    ],
  },
  {
    id: 'cicd',
    title: 'CI/CD and promotion',
    blurb: 'From docs/diagrams/cicd-flow.md. Apply is always manual and environment-gated; pull requests never create infrastructure.',
    layers: [
      { nodes: [{ id: 'c-branch', label: 'Feature branch' }] },
      { nodes: [{ id: 'c-ci', label: 'CI', sub: 'Tests, fmt, validate, security scans' }] },
      { nodes: [{ id: 'c-pr', label: 'Pull request' }] },
      { nodes: [{ id: 'c-plan', label: 'Terraform plan', sub: 'dev' }] },
      { nodes: [{ id: 'c-approve', label: 'Environment approval', sub: 'GitHub environments', tone: 'warn' }] },
      { nodes: [{ id: 'c-dev', label: 'Deploy to dev', sub: 'Manual' }] },
      { nodes: [{ id: 'c-int', label: 'Integration tests' }] },
      { nodes: [{ id: 'c-prod', label: 'Deploy to prod', sub: 'Second approval', tone: 'accent' }] },
    ],
  },
  {
    id: 'security',
    title: 'Security model',
    blurb: 'Defence in depth from the browser to the bucket. No long-lived AWS keys exist anywhere in the pipeline.',
    layers: [
      { nodes: [{ id: 'sec-waf', label: 'AWS WAF', sub: 'Managed rules on CloudFront' }] },
      { nodes: [{ id: 'sec-cf', label: 'CloudFront + OAC', sub: 'CSP, HSTS, frame-deny' }] },
      { nodes: [{ id: 'sec-cognito', label: 'Cognito', sub: 'OAuth2 PKCE, JWT authorizer' }] },
      { nodes: [{ id: 'sec-api', label: 'API Gateway', sub: 'JWT-authorized routes' }] },
      { nodes: [{ id: 'sec-iam', label: 'IAM', sub: 'Least-privilege execution roles' }] },
      {
        nodes: [
          { id: 'sec-kms', label: 'KMS', sub: 'Customer-managed key' },
          { id: 'sec-s3', label: 'Private S3', sub: 'No public access, SSE-KMS', tone: 'ok' },
        ],
      },
      { nodes: [{ id: 'sec-oidc', label: 'GitHub OIDC', sub: 'Short-lived deploy credentials', tone: 'accent' }] },
    ],
  },
  {
    id: 'monitoring',
    title: 'Monitoring and alerting',
    blurb: 'From docs/diagrams/monitoring-flow.md. Alerts never contain customer records or file contents.',
    layers: [
      {
        nodes: [
          { id: 'm-lambda', label: 'Lambda metrics', sub: 'Errors, throttles, duration' },
          { id: 'm-glue', label: 'Glue metrics', sub: 'Data-quality per batch' },
          { id: 'm-athena', label: 'Athena', sub: 'Query failures' },
        ],
      },
      { nodes: [{ id: 'm-alarm', label: 'CloudWatch alarms', sub: 'Thresholds per signal' }] },
      { nodes: [{ id: 'm-sns', label: 'SNS', sub: 'KMS-encrypted topic' }] },
      {
        nodes: [
          { id: 'm-email', label: 'Email subscriber', sub: 'Confirmed recipient' },
          { id: 'm-dlq', label: 'SQS DLQ', sub: 'Exhausted EventBridge deliveries', tone: 'bad' },
        ],
      },
    ],
  },
];

export function render(target) {
  target.append(pageHeader(
    'Architecture',
    'How StreamForge fits together, from the browser upload through to the serving layer. Use the zoom controls to inspect any diagram.',
  ));

  for (const diagram of DIAGRAMS) {
    target.append(panel(diagram.title, [
      el('p', { class: 'panel-blurb', text: diagram.blurb }),
      zoomable(flowDiagram({ layers: diagram.layers })),
    ]));
  }
}
