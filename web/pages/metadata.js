/** Metadata explorer: searchable, filterable view of the lineage manifests. */

import { api } from '../api.js';
import { pageHeader, panel, table, stateBlock, el, clear, formatNumber, formatDate } from '../ui.js';

const PAGE_SIZE = 25;

const COLUMNS = [
  { key: 'source_filename', label: 'Source file' },
  { key: 'batch_id', label: 'Batch ID', format: (v) => (v ? `${String(v).slice(0, 8)}…` : '—') },
  { key: 'processed_timestamp', label: 'Processed', format: formatDate },
  { key: 'total_records', label: 'Read', align: 'right', format: formatNumber },
  { key: 'valid_records', label: 'Accepted', align: 'right', format: formatNumber },
  { key: 'invalid_records', label: 'Rejected', align: 'right', format: formatNumber },
  { key: 'execution_duration_ms', label: 'Duration', align: 'right', format: (v) => (v ? `${Math.round(v)} ms` : '—') },
  { key: 'validation_status', label: 'Status' },
  { key: 'pipeline_version', label: 'Version' },
];

export async function render(target) {
  target.append(pageHeader(
    'Metadata',
    'One manifest per processed batch, written by the validation Lambda. This is the audit trail the rest of the platform is reconciled against.',
  ));

  const state = { search: '', status: '', offset: 0 };
  const results = el('div', { class: 'results' });

  const searchInput = el('input', {
    class: 'control', type: 'search', placeholder: 'Search batches, files, versions…',
    'aria-label': 'Search metadata',
  });
  const statusSelect = el('select', { class: 'control', 'aria-label': 'Filter by validation status' }, [
    el('option', { value: '', text: 'All statuses' }),
    el('option', { value: 'clean', text: 'Clean only' }),
    el('option', { value: 'partial', text: 'Had rejections' }),
  ]);

  let debounce;
  searchInput.addEventListener('input', () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => { state.search = searchInput.value.trim(); state.offset = 0; load(); }, 250);
  });
  statusSelect.addEventListener('change', () => { state.status = statusSelect.value; state.offset = 0; load(); });

  target.append(panel('Batches', [
    el('div', { class: 'filter-row' }, [searchInput, statusSelect]),
    results,
  ]));

  async function load() {
    clear(results).append(stateBlock('loading', 'Loading manifests…'));
    const query = new URLSearchParams({ limit: String(PAGE_SIZE), offset: String(state.offset) });
    if (state.search) query.set('search', state.search);
    if (state.status) query.set('status', state.status);

    try {
      const data = await api(`/api/metadata?${query}`);
      clear(results);

      if (!data.items.length) {
        results.append(stateBlock('empty',
          state.search || state.status
            ? 'No batches match those filters.'
            : 'No batches processed yet. Upload a CSV to create one.'));
        return;
      }

      results.append(table(COLUMNS, data.items));
      results.append(pager(data));
    } catch (error) {
      clear(results).append(stateBlock('error', error.message));
    }
  }

  function pager(data) {
    const last = data.offset + data.items.length;
    const prev = el('button', {
      class: 'button button-ghost', type: 'button', text: '← Previous',
      disabled: data.offset === 0,
      onclick: () => { state.offset = Math.max(0, state.offset - PAGE_SIZE); load(); },
    });
    const next = el('button', {
      class: 'button button-ghost', type: 'button', text: 'Next →',
      disabled: last >= data.total,
      onclick: () => { state.offset += PAGE_SIZE; load(); },
    });
    if (data.offset === 0) prev.setAttribute('disabled', 'disabled');
    if (last >= data.total) next.setAttribute('disabled', 'disabled');

    return el('div', { class: 'pager' }, [
      el('span', { class: 'pager-status', text: `${data.offset + 1}–${last} of ${formatNumber(data.total)}` }),
      el('div', { class: 'pager-actions' }, [prev, next]),
    ]);
  }

  await load();
}
