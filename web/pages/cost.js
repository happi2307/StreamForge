/**
 * Cost dashboard.
 *
 * Figures are the real Cost Explorer numbers for this account, recorded rather
 * than queried live: the Cost Explorer API bills $0.01 per request, so polling
 * it from a portal page would be a genuine (if small) own goal. Refresh them by
 * re-running the command shown at the bottom of the page.
 */

import { el, pageHeader, panel, statCard, cardGrid, table, badge, formatMoney } from '../ui.js';

const PERIOD = 'August 2026';

// Gross usage, credits excluded, from:
//   aws ce get-cost-and-usage --granularity MONTHLY --metrics UnblendedCost
//     --filter RECORD_TYPE=Usage --group-by SERVICE
const SERVICES = [
  { service: 'AWS WAF', cost: 7.0000, note: 'Web ACL on CloudFront, plus per-rule charges', share: 60 },
  { service: 'EC2 — Other', cost: 2.7360, note: 'Unrelated 30 GB gp3 volume in ap-south-1, not StreamForge', share: 23 },
  { service: 'KMS', cost: 2.0000, note: 'Two customer-managed keys at $1 each', share: 17 },
  { service: 'RDS', cost: 0.0041, note: 'Aurora storage only; no cluster running for StreamForge', share: 0 },
  { service: 'S3', cost: 0.0024, note: '~56 KB across seven buckets', share: 0 },
  { service: 'DynamoDB', cost: 0.0000, note: 'Terraform state lock table', share: 0 },
  { service: 'API Gateway', cost: 0.0000, note: 'HTTP API, well inside free tier', share: 0 },
  { service: 'Lambda', cost: 0.0000, note: 'Phase 1 processor and dashboard API', share: 0 },
  { service: 'Glue', cost: 0.0000, note: 'Crawler and ETL, billed only while running', share: 0 },
  { service: 'Athena', cost: 0.0000, note: '$5/TB scanned; no queries run yet', share: 0 },
  { service: 'CloudFront', cost: 0.0000, note: 'Within the 1 TB free egress allowance', share: 0 },
  { service: 'Cognito', cost: 0.0000, note: 'One user, against a 50,000 MAU free tier', share: 0 },
];

const GROSS = SERVICES.reduce((sum, row) => sum + row.cost, 0);
const CREDITS = 11.7426;
const UNRELATED = 2.7360;

const FORWARD = [
  {
    item: 'Portal (this phase)',
    estimate: '$0 – 2 / month',
    reason: 'Frontend plus read-only API calls against infrastructure that already exists. Lambda, API Gateway and CloudFront stay inside the free tier at portfolio traffic.',
  },
  {
    item: 'Aurora Serverless v2',
    estimate: '$2 – 4 / month',
    reason: 'Only if the Warehouse page is wired to a live database. With min_capacity 0 and auto-pause the cluster idles to zero; measured at $0.51 over 11 days on this account.',
  },
  {
    item: 'Aurora as originally specced',
    estimate: '$81 / month',
    reason: 'What min_capacity 0.5 plus five VPC interface endpoints would have cost. Avoided by scaling to zero and using the RDS Data API instead of in-VPC access.',
  },
];

export function render(target) {
  target.append(pageHeader(
    'Cost',
    `Measured spend for ${PERIOD}, taken from Cost Explorer rather than estimated. Credits currently absorb the whole bill, so the net figure is zero — the gross figure is the one that matters.`,
  ));

  target.append(cardGrid([
    statCard('Gross usage', formatMoney(GROSS), PERIOD),
    statCard('Credits applied', `−${formatMoney(CREDITS)}`, 'Covers the full amount'),
    statCard('Net payable', '$0.00', 'While credits last'),
    statCard('Attributable to StreamForge', formatMoney(GROSS - UNRELATED), 'Excludes the Mumbai volume'),
  ]));

  target.append(panel(`Spend by service — ${PERIOD}`, [
    table(
      [
        { key: 'service', label: 'Service' },
        { key: 'cost', label: 'Cost', align: 'right', format: (v) => (v < 0.0005 && v > 0 ? '<$0.01' : formatMoney(v)) },
        { key: 'share', label: 'Share', align: 'right', format: (v) => (v > 0 ? `${v}%` : '—') },
        { key: 'note', label: 'Note', wrap: true },
      ],
      SERVICES,
    ),
  ], badge('measured', 'ok')));

  target.append(panel('Two things worth knowing', [
    el('ul', { class: 'note-list' }, [
      el('li', {}, [
        el('strong', { text: 'WAF is 60% of the bill. ' }),
        'A CloudFront web ACL costs $5/month before a single request reaches it, plus $1 per rule. It is the only fixed cost of meaningful size in the platform.',
      ]),
      el('li', {}, [
        el('strong', { text: 'The second-largest line is not this project. ' }),
        'A stopped t3.large and its 30 GB gp3 volume in ap-south-1 bill $2.74/month. The instance is stopped so there is no compute charge, but the volume is billed regardless of instance state.',
      ]),
    ]),
  ]));

  target.append(panel('Forward-looking estimates', [
    table(
      [
        { key: 'item', label: 'Item' },
        { key: 'estimate', label: 'Estimate', align: 'right' },
        { key: 'reason', label: 'Basis', wrap: true },
      ],
      FORWARD,
    ),
  ], badge('estimated', 'warn')));

  target.append(panel('Refreshing these numbers', [
    el('p', { class: 'panel-blurb', text: 'The Cost Explorer API charges $0.01 per request, so this page does not call it. Re-run this to update the table above:' }),
    el('pre', { class: 'code-block' }, el('code', {
      text: 'aws ce get-cost-and-usage \\\n'
        + '  --time-period Start=2026-08-01,End=2026-09-01 \\\n'
        + '  --granularity MONTHLY --metrics UnblendedCost \\\n'
        + '  --filter \'{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}\' \\\n'
        + '  --group-by Type=DIMENSION,Key=SERVICE',
    })),
  ]));
}
