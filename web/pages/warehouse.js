/**
 * Warehouse explorer.
 *
 * Reads Aurora through the RDS Data API when Phase 5 is deployed. When it is
 * not, the page says so plainly rather than showing invented tables -- the
 * schema shown would otherwise be a claim the platform cannot back up.
 */

import { cachedApi } from '../api.js';
import { pageHeader, panel, table, stateBlock, el, badge, formatNumber } from '../ui.js';

export async function render(target) {
  const data = await cachedApi('/api/warehouse', 300_000);

  target.append(pageHeader(
    'Warehouse',
    'The Aurora PostgreSQL serving layer: schemas, tables, columns and the audit trail written by each incremental load.',
  ));

  if (!data.deployed) {
    target.append(stateBlock('not-deployed', data.reason));
    target.append(panel('What this page shows once Phase 5 is deployed', [
      el('ul', { class: 'note-list' }, [
        el('li', {}, [el('strong', { text: 'Schemas and tables — ' }), 'read live from information_schema, including the audit tables the loader maintains.']),
        el('li', {}, [el('strong', { text: 'Columns and types — ' }), 'every column with its data type and nullability, expandable per table.']),
        el('li', {}, [el('strong', { text: 'Row counts — ' }), 'current counts alongside the manifest counts, so drift between lake and warehouse is visible.']),
      ]),
      el('p', { class: 'panel-blurb' }, [
        'The serving layer is deployed by ',
        el('code', { class: 'inline-code', text: 'terraform/modules/phase5_serving' }),
        '. Configured for scale-to-zero, it idles at roughly $2–4/month.',
      ]),
    ]));
    return;
  }

  const tables = data.tables || [];
  const columns = data.columns || [];

  target.append(panel('Tables', [
    badge(`database: ${data.database}`, 'ok'),
    table(
      [
        { key: 'table_schema', label: 'Schema' },
        { key: 'table_name', label: 'Table' },
        { key: 'column_count', label: 'Columns', align: 'right', format: formatNumber },
      ],
      tables,
      'The database is reachable but contains no user tables yet.',
    ),
  ]));

  for (const entry of tables) {
    const owned = columns.filter(
      (c) => c.table_schema === entry.table_schema && c.table_name === entry.table_name,
    );
    if (!owned.length) continue;

    const details = el('details', { class: 'chart-table' });
    details.append(el('summary', { text: `${entry.table_schema}.${entry.table_name}` }));
    details.append(table(
      [
        { key: 'column_name', label: 'Column' },
        { key: 'data_type', label: 'Type' },
        { key: 'is_nullable', label: 'Nullable' },
      ],
      owned,
    ));
    target.append(details);
  }
}
