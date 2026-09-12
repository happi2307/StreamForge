/** CloudWatch metrics and alarm state for the pipeline's compute surfaces. */

import { cachedApi } from '../api.js';
import { pageHeader, panel, cardGrid, statCard, table, stateBlock, badge, el, formatNumber, formatDate } from '../ui.js';
import { lineChart, CATEGORICAL } from '../charts.js';

const ALARM_TONE = { OK: 'ok', ALARM: 'bad', INSUFFICIENT_DATA: 'idle' };

export async function render(target) {
  const data = await cachedApi('/api/metrics', 120_000);

  target.append(pageHeader(
    'Monitoring',
    `Lambda metrics and alarm state over the last ${data.window_days} days, read directly from CloudWatch.`,
  ));

  const series = data.series || [];
  const alarms = data.alarms || [];
  const find = (suffix) => series.filter((s) => s.id.endsWith(suffix));

  const invocations = find('inv');
  const errors = find('err');
  const durations = find('dur');

  const totalInvocations = invocations.reduce((sum, s) => sum + s.values.reduce((a, b) => a + b, 0), 0);
  const totalErrors = errors.reduce((sum, s) => sum + s.values.reduce((a, b) => a + b, 0), 0);
  const inAlarm = alarms.filter((a) => a.state === 'ALARM').length;

  target.append(cardGrid([
    statCard('Invocations', formatNumber(Math.round(totalInvocations)), `Last ${data.window_days} days`),
    statCard('Errors', formatNumber(Math.round(totalErrors)),
      totalInvocations ? `${((totalErrors / totalInvocations) * 100).toFixed(2)}% error rate` : 'No invocations'),
    statCard('Alarms configured', formatNumber(alarms.length)),
    statCard('Currently in alarm', formatNumber(inAlarm), inAlarm ? 'Needs attention' : 'All clear'),
  ]));

  const invocationChart = lineChart({
    title: 'Lambda invocations',
    series: invocations.map((s, i) => ({
      label: s.label || `Function ${i + 1}`,
      values: s.values,
      color: CATEGORICAL[i % CATEGORICAL.length],
    })),
    format: (v) => formatNumber(Math.round(v)),
  });

  const durationChart = lineChart({
    title: 'Average duration (ms)',
    series: durations.map((s, i) => ({
      label: s.label || `Function ${i + 1}`,
      values: s.values.map((v) => Math.round(v)),
      color: CATEGORICAL[i % CATEGORICAL.length],
    })),
    format: (v) => `${formatNumber(Math.round(v))} ms`,
  });

  target.append(panel('Lambda activity', [
    el('div', { class: 'chart-row' }, [
      invocationChart || stateBlock('empty', 'No invocation data in this window.'),
      durationChart || stateBlock('empty', 'No duration data in this window.'),
    ]),
  ]));

  target.append(panel('Alarms', [
    alarms.length
      ? table(
        [
          { key: 'name', label: 'Alarm' },
          { key: 'metric', label: 'Metric' },
          { key: 'state', label: 'State' },
          { key: 'updated', label: 'Last change', format: formatDate },
          { key: 'description', label: 'Description', wrap: true },
        ],
        alarms,
      )
      : stateBlock('empty', 'No CloudWatch alarms are configured in this account.'),
  ], alarms.length ? badge(inAlarm ? `${inAlarm} in alarm` : 'all clear', inAlarm ? 'bad' : 'ok') : null));

  if (alarms.length) {
    target.append(panel('Alarm states at a glance', [
      el('div', { class: 'chip-row' }, alarms.map((a) =>
        el('span', { class: 'alarm-chip' }, [
          badge(a.state.replace('_', ' ').toLowerCase(), ALARM_TONE[a.state] || 'idle'),
          el('span', { class: 'alarm-name', text: a.name }),
        ]))),
    ]));
  }
}
