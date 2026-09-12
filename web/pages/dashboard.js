/** Executive dashboard: platform totals drawn from the Phase 1 manifests. */

import { cachedApi } from '../api.js';
import { pageHeader, cardGrid, statCard, panel, stateBlock, el, formatBytes, formatNumber, formatDate } from '../ui.js';
import { stackedBarChart, barChart, VALID_COLOR, REJECTED_COLOR } from '../charts.js';

export async function render(target) {
  const data = await cachedApi('/api/dashboard');

  target.append(pageHeader(
    'Dashboard',
    'Every figure here is derived from the lineage manifests the pipeline writes for each batch, not from a sample or a cache.',
  ));

  target.append(cardGrid([
    statCard('Files processed', formatNumber(data.files_processed)),
    statCard('Records processed', formatNumber(data.records_processed)),
    statCard('Success rate', data.success_rate === null ? '—' : `${data.success_rate}%`, 'Rows passing validation'),
    statCard('Rejected records', formatNumber(data.failed_records), 'Kept for audit'),
    statCard('Curated objects', formatNumber(data.curated_objects), 'Partitioned Parquet'),
    statCard('Quarantined', formatNumber(data.quarantined_objects), 'Transform failures'),
    statCard('Storage used', formatBytes(data.storage_bytes), 'Across all zones'),
    statCard('Latest batch', data.latest_batch ? formatDate(data.latest_batch.phase1_processed_timestamp) : '—'),
  ]));

  const daily = (data.daily || []).map((d) => ({
    label: d.date.slice(5),
    valid: d.valid,
    invalid: d.invalid,
  }));

  const processing = stackedBarChart({
    title: 'Rows processed per day',
    data: daily,
    series: [
      { key: 'valid', label: 'Valid', color: VALID_COLOR },
      { key: 'invalid', label: 'Rejected', color: REJECTED_COLOR },
    ],
    format: formatNumber,
  });

  const storage = barChart({
    title: 'Storage by zone',
    data: (data.storage_by_zone || []).map((z) => ({ label: z.zone, value: z.bytes })),
    format: formatBytes,
  });

  target.append(panel('Processing activity', [
    el('div', { class: 'chart-row' }, [
      processing || stateBlock('empty', 'No batches processed yet. Upload a CSV to populate this chart.'),
      storage || stateBlock('empty', 'No objects stored yet.'),
    ]),
  ]));

  if (data.latest_batch) {
    const batch = data.latest_batch;
    target.append(panel('Most recent batch', [
      el('dl', { class: 'detail-list' }, [
        el('dt', { text: 'Batch ID' }), el('dd', {}, el('code', { class: 'inline-code', text: batch.phase1_batch_id || '—' })),
        el('dt', { text: 'Source file' }), el('dd', { text: batch.source_filename || '—' }),
        el('dt', { text: 'Processed' }), el('dd', { text: formatDate(batch.phase1_processed_timestamp) }),
        el('dt', { text: 'Rows' }), el('dd', {
          text: `${formatNumber(batch.total_records)} total · ${formatNumber(batch.valid_records)} valid · ${formatNumber(batch.invalid_records)} rejected`,
        }),
        el('dt', { text: 'Pipeline version' }), el('dd', { text: batch.phase1_pipeline_version || '—' }),
      ]),
    ]));
  }
}
