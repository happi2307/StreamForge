/** Data lake explorer: every storage zone, browsable down to the object. */

import { api, cachedApi } from '../api.js';
import {
  pageHeader, panel, table, stateBlock, badge, el, clear,
  formatBytes, formatNumber, formatDate,
} from '../ui.js';

export async function render(target) {
  const data = await cachedApi('/api/storage');

  target.append(pageHeader(
    'Data Lake',
    'Seven S3 zones carry data from untrusted upload through to analytics-ready Parquet. Select a zone to browse its objects.',
  ));

  const zones = data.zones || [];
  const totalObjects = zones.reduce((sum, z) => sum + z.object_count, 0);

  if (!totalObjects) {
    target.append(stateBlock('empty', 'The lake is empty. Upload a CSV to populate the raw zone.'));
    return;
  }

  const browser = el('div', { class: 'browser' });

  target.append(panel('Zones', [
    table(
      [
        { key: 'zone', label: 'Zone' },
        { key: 'purpose', label: 'Purpose', wrap: true },
        { key: 'object_count', label: 'Objects', align: 'right', format: formatNumber },
        { key: 'total_bytes', label: 'Size', align: 'right', format: formatBytes },
        { key: 'latest_object', label: 'Latest', format: formatDate },
        { key: 'encryption', label: 'Encryption' },
        { key: 'lifecycle', label: 'Lifecycle' },
      ],
      zones,
    ),
  ]));

  const buttons = zones.map((zone) => el('button', {
    class: 'chip', type: 'button', 'data-zone': zone.zone,
    text: `${zone.zone} (${zone.object_count})`,
    onclick: () => selectZone(zone),
  }));

  target.append(panel('Browse objects', [
    el('div', { class: 'chip-row' }, buttons),
    browser,
  ]));

  function markSelected(name) {
    for (const button of buttons) button.classList.toggle('is-active', button.dataset.zone === name);
  }

  async function selectZone(zone) {
    markSelected(zone.zone);
    clear(browser).append(stateBlock('loading', `Loading ${zone.zone}…`));

    try {
      const listing = await api(`/api/storage?zone=${encodeURIComponent(zone.zone)}`);
      clear(browser);

      browser.append(el('p', { class: 'browser-path' }, [
        el('code', { class: 'inline-code', text: `s3://${listing.bucket}/` }),
        zone.partitioned ? badge('partitioned', 'ok') : null,
      ]));

      if (!listing.objects.length) {
        browser.append(stateBlock('empty', 'This zone has no objects yet.'));
        return;
      }

      const partitions = derivePartitions(listing.objects);
      if (partitions.length) {
        browser.append(el('div', { class: 'partition-row' }, [
          el('span', { class: 'partition-label', text: 'Partitions' }),
          ...partitions.map((p) => el('code', { class: 'inline-code', text: p })),
        ]));
      }

      browser.append(table(
        [
          { key: 'key', label: 'Key' },
          { key: 'size', label: 'Size', align: 'right', format: formatBytes },
          { key: 'last_modified', label: 'Modified', format: formatDate },
          { key: 'storage_class', label: 'Class' },
        ],
        listing.objects,
      ));

      if (listing.truncated) {
        browser.append(el('p', { class: 'browser-note', text: 'Listing truncated at 1000 objects.' }));
      }
    } catch (error) {
      clear(browser).append(stateBlock('error', error.message));
    }
  }

  await selectZone(zones.find((z) => z.object_count > 0) || zones[0]);
}

/** Hive-style key=value path segments, e.g. year=2026/month=07. */
function derivePartitions(objects) {
  const found = new Set();
  for (const object of objects) {
    for (const segment of object.key.split('/')) {
      if (segment.includes('=')) found.add(segment);
    }
  }
  return [...found].sort().slice(0, 12);
}
