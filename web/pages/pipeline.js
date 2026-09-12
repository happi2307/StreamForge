/** Pipeline page: component health and the most recent batches. */

import { cachedApi } from '../api.js';
import { pageHeader, cardGrid, statCard, panel, table, badge, el, formatNumber, formatDate } from '../ui.js';

const TONE = { healthy: 'ok', idle: 'idle', 'not-deployed': 'warn', failing: 'bad' };
const LABEL = { healthy: 'healthy', idle: 'idle', 'not-deployed': 'not deployed', failing: 'failing' };

export async function render(target) {
  const data = await cachedApi('/api/pipeline');

  target.append(pageHeader(
    'Pipeline',
    'The five stages a CSV passes through, and how the most recent batches fared.',
  ));

  target.append(cardGrid([
    statCard('Batches processed', formatNumber(data.batches_processed)),
    statCard('Success rate', data.success_rate === null ? '—' : `${data.success_rate}%`),
    statCard('Average duration', data.average_duration_ms === null ? '—' : `${data.average_duration_ms} ms`, 'Validation stage'),
    statCard('Latest run', formatDate(data.latest_run)),
  ]));

  target.append(panel('Components', [
    el('div', { class: 'component-list' }, (data.components || []).map((c) =>
      el('article', { class: 'component' }, [
        el('div', { class: 'component-head' }, [
          el('strong', { text: c.name }),
          badge(LABEL[c.status] || c.status, TONE[c.status] || 'idle'),
        ]),
        el('p', { class: 'component-role', text: c.role }),
        el('p', { class: 'component-detail' }, [
          el('span', { class: 'component-service', text: c.service }),
          el('span', { text: ` · ${c.detail}` }),
        ]),
      ]))),
  ]));

  target.append(panel('Recent batches', [
    table(
      [
        { key: 'source_filename', label: 'Source file' },
        { key: 'processed_timestamp', label: 'Processed', format: formatDate },
        { key: 'total_records', label: 'Rows', align: 'right', format: formatNumber },
        { key: 'valid_records', label: 'Valid', align: 'right', format: formatNumber },
        { key: 'invalid_records', label: 'Rejected', align: 'right', format: formatNumber },
        { key: 'duration_ms', label: 'Duration', align: 'right', format: (v) => (v ? `${Math.round(v)} ms` : '—') },
      ],
      data.recent_batches,
      'No batches yet. Upload a CSV from the Upload page.',
    ),
  ]));
}
