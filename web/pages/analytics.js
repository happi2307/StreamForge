/**
 * Business analytics over the curated dataset, via Athena.
 *
 * The charts reflect the columns the curated table actually has -- customer_id,
 * name, sales, sales_category and the year/month/day partitions. Dimensions the
 * dataset does not carry (region, product) are deliberately absent rather than
 * invented.
 */

import { cachedApi } from '../api.js';
import { pageHeader, panel, cardGrid, statCard, table, stateBlock, el, formatNumber, formatMoney } from '../ui.js';
import { barChart, lineChart } from '../charts.js';

const number = (value) => (value === null || value === undefined || value === '' ? 0 : Number(value));

export async function render(target) {
  const data = await cachedApi('/api/analytics', 300_000);
  const sections = data.sections || {};
  const errors = data.errors || {};

  target.append(pageHeader(
    'Analytics',
    `Business aggregates computed by Athena over the curated Parquet dataset (${data.table}). Partition pruning keeps each query to a few kilobytes scanned.`,
  ));

  if (Object.keys(errors).length === Object.keys(errors).length && !Object.keys(sections).length) {
    target.append(stateBlock('error',
      Object.values(errors)[0] || 'Athena is unavailable in this environment.'));
    return;
  }

  const summary = (sections.summary || [])[0];
  if (summary) {
    target.append(cardGrid([
      statCard('Revenue', formatMoney(number(summary.revenue)), 'Sum of sales'),
      statCard('Records', formatNumber(number(summary.records))),
      statCard('Customers', formatNumber(number(summary.customers)), 'Distinct customer_id'),
      statCard('Average order', formatMoney(number(summary.average_order))),
    ]));
  }

  const byCategory = sections.by_category || [];
  if (byCategory.length) {
    target.append(panel('Revenue by sales category', [
      barChart({
        data: byCategory.map((r) => ({ label: r.sales_category || 'uncategorised', value: number(r.revenue) })),
        format: (v) => formatMoney(v),
      }),
      table(
        [
          { key: 'sales_category', label: 'Category' },
          { key: 'records', label: 'Records', align: 'right', format: (v) => formatNumber(number(v)) },
          { key: 'revenue', label: 'Revenue', align: 'right', format: (v) => formatMoney(number(v)) },
        ],
        byCategory,
      ),
    ]));
  }

  const byDay = sections.by_day || [];
  if (byDay.length) {
    const labels = byDay.map((r) => `${r.year}-${String(r.month).padStart(2, '0')}-${String(r.day).padStart(2, '0')}`);
    target.append(panel('Revenue over time', [
      lineChart({
        labels,
        series: [{ label: 'Revenue', values: byDay.map((r) => number(r.revenue)) }],
        format: (v) => formatMoney(v),
      }) || stateBlock('empty', 'Not enough partitions to plot a trend.'),
    ]));
  }

  const topCustomers = sections.top_customers || [];
  if (topCustomers.length) {
    target.append(panel('Top customers by revenue', [
      table(
        [
          { key: 'customer_id', label: 'Customer ID' },
          { key: 'name', label: 'Name' },
          { key: 'revenue', label: 'Revenue', align: 'right', format: (v) => formatMoney(number(v)) },
        ],
        topCustomers,
      ),
    ]));
  }

  const failed = Object.entries(errors);
  if (failed.length) {
    target.append(panel('Queries that did not complete', [
      el('ul', { class: 'note-list' }, failed.map(([name, message]) =>
        el('li', {}, [el('strong', { text: `${name}: ` }), message]))),
    ]));
  }
}
