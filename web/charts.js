/**
 * SVG charts, hand-built.
 *
 * No charting library: the CloudFront CSP is `default-src 'self'`, so a CDN
 * copy is blocked, and this project has no build step to bundle one.
 *
 * PALETTE -- validated, not chosen by eye. Checked with the dataviz skill's
 * validator against this page's dark surface (#0d1a2c):
 *
 *   categorical  #27a494 #b3822a #4a8ff0 #e2657e
 *       lightness band, chroma floor, CVD separation, normal-vision floor and
 *       contrast: all PASS (worst adjacent dE 12.9 deutan / 17.8 normal)
 *   sequential   #1f7a70 #27a494 #45b8aa #6fcabe #9adbd2
 *       monotone lightness, adjacent dL, light-end contrast, single hue: PASS
 *   valid/rejected  #4a8ff0 / #e2657e
 *       dE 17.3 protan, 30.5 tritan. Green/red was rejected outright: it scores
 *       dE 2.5 under deuteranopia, i.e. indistinguishable.
 *
 * Re-validate before changing any value here:
 *   node scripts/validate_palette.js "<hex,...>" --mode dark --surface "#0d1a2c"
 */

import { el } from './ui.js';

const NS = 'http://www.w3.org/2000/svg';

export const CATEGORICAL = ['#27a494', '#b3822a', '#4a8ff0', '#e2657e'];
export const SEQUENTIAL = ['#1f7a70', '#27a494', '#45b8aa', '#6fcabe', '#9adbd2'];
export const VALID_COLOR = '#4a8ff0';
export const REJECTED_COLOR = '#e2657e';

const SURFACE = '#0d1a2c';
const GRID = 'rgba(145, 162, 183, .16)';
const INK_MUTED = '#91a2b7';

function svg(tag, attrs = {}, children = []) {
  const node = document.createElementNS(NS, tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    node.setAttribute(key, String(value));
  }
  for (const child of [].concat(children)) {
    if (child) node.append(child);
  }
  return node;
}

function niceMax(value) {
  if (value <= 0) return 1;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  return Math.ceil(value / magnitude) * magnitude;
}

/** Shared tooltip element, positioned over whichever chart is hovered. */
function attachTooltip(figure) {
  const tip = el('div', { class: 'chart-tooltip', hidden: true });
  figure.append(tip);
  return {
    show(html, x, y) {
      tip.replaceChildren(...html);
      tip.hidden = false;
      tip.style.left = `${x}px`;
      tip.style.top = `${y}px`;
    },
    hide() { tip.hidden = true; },
  };
}

function legend(series) {
  return el('div', { class: 'chart-legend' }, series.map((s) =>
    el('span', { class: 'legend-item' }, [
      swatch(s.color),
      el('span', { text: s.label }),
    ])));
}

function swatch(color) {
  const box = el('span', { class: 'legend-swatch' });
  box.style.background = color;
  return box;
}

/** Every chart ships a table view so identity is never colour-alone. */
function tableView(columns, rows) {
  const details = el('details', { class: 'chart-table' });
  details.append(el('summary', { text: 'View as table' }));
  const head = el('tr', {}, columns.map((c) => el('th', { text: c })));
  const body = rows.map((r) => el('tr', {}, r.map((cell) => el('td', { text: String(cell) }))));
  details.append(el('div', { class: 'table-wrap' }, [
    el('table', { class: 'data-table' }, [el('thead', {}, head), el('tbody', {}, body)]),
  ]));
  return details;
}

function figureWrap(title, chart, extras = []) {
  return el('figure', { class: 'chart-figure' }, [
    title ? el('figcaption', { class: 'chart-title', text: title }) : null,
    chart,
    ...extras,
  ]);
}

/* -- Bar chart: single-series magnitude ----------------------------------- */

export function barChart({ title, data, format = (v) => String(v), height = 210 }) {
  if (!data || data.length === 0) return null;

  const width = 620;
  const pad = { top: 14, right: 16, bottom: 34, left: 48 };
  const plotW = width - pad.left - pad.right;
  const plotH = height - pad.top - pad.bottom;
  const max = niceMax(Math.max(...data.map((d) => d.value)));
  // 2px surface gap between adjacent bars, per the mark spec.
  const slot = plotW / data.length;
  const barW = Math.max(6, slot - 10);

  const root = svg('svg', {
    class: 'chart', viewBox: `0 0 ${width} ${height}`,
    role: 'img', 'aria-label': title || 'Bar chart',
  });

  for (let i = 0; i <= 4; i += 1) {
    const y = pad.top + (plotH * i) / 4;
    root.append(svg('line', { x1: pad.left, x2: width - pad.right, y1: y, y2: y, stroke: GRID, 'stroke-width': 1 }));
    root.append(svg('text', {
      x: pad.left - 8, y: y + 4, fill: INK_MUTED, 'font-size': 10, 'text-anchor': 'end',
    }, document.createTextNode(format(Math.round(max - (max * i) / 4)))));
  }

  const figure = figureWrap(title, root, [
    tableView(['Label', 'Value'], data.map((d) => [d.label, format(d.value)])),
  ]);
  const tooltip = attachTooltip(figure);

  data.forEach((d, index) => {
    const barH = max ? (d.value / max) * plotH : 0;
    const x = pad.left + index * slot + (slot - barW) / 2;
    const y = pad.top + plotH - barH;
    const color = SEQUENTIAL[Math.min(SEQUENTIAL.length - 1, 1 + (index % 3))];

    const rect = svg('rect', {
      x, y: barH > 0 ? y : pad.top + plotH - 1, width: barW, height: Math.max(barH, 1),
      rx: 4, fill: color, class: 'chart-bar',
    });
    rect.addEventListener('mouseenter', (e) => tooltip.show(
      [el('strong', { text: d.label }), el('span', { text: format(d.value) })],
      e.offsetX, e.offsetY,
    ));
    rect.addEventListener('mouseleave', () => tooltip.hide());
    root.append(rect);

    root.append(svg('text', {
      x: x + barW / 2, y: height - pad.bottom + 15, fill: INK_MUTED,
      'font-size': 10, 'text-anchor': 'middle',
    }, document.createTextNode(d.label.length > 12 ? `${d.label.slice(0, 11)}…` : d.label)));
  });

  return figure;
}

/* -- Stacked bars: valid vs rejected over time ---------------------------- */

export function stackedBarChart({ title, data, series, format = (v) => String(v), height = 230 }) {
  if (!data || data.length === 0) return null;

  const width = 620;
  const pad = { top: 14, right: 16, bottom: 34, left: 48 };
  const plotW = width - pad.left - pad.right;
  const plotH = height - pad.top - pad.bottom;
  const totals = data.map((d) => series.reduce((sum, s) => sum + (d[s.key] || 0), 0));
  const max = niceMax(Math.max(...totals, 1));
  const slot = plotW / data.length;
  const barW = Math.max(8, Math.min(46, slot - 12));

  const root = svg('svg', {
    class: 'chart', viewBox: `0 0 ${width} ${height}`,
    role: 'img', 'aria-label': title || 'Stacked bar chart',
  });

  for (let i = 0; i <= 4; i += 1) {
    const y = pad.top + (plotH * i) / 4;
    root.append(svg('line', { x1: pad.left, x2: width - pad.right, y1: y, y2: y, stroke: GRID, 'stroke-width': 1 }));
    root.append(svg('text', {
      x: pad.left - 8, y: y + 4, fill: INK_MUTED, 'font-size': 10, 'text-anchor': 'end',
    }, document.createTextNode(format(Math.round(max - (max * i) / 4)))));
  }

  const figure = figureWrap(title, root, [
    legend(series),
    tableView(['Date', ...series.map((s) => s.label)],
      data.map((d) => [d.label, ...series.map((s) => format(d[s.key] || 0))])),
  ]);
  const tooltip = attachTooltip(figure);

  data.forEach((d, index) => {
    const x = pad.left + index * slot + (slot - barW) / 2;
    let cursor = pad.top + plotH;

    series.forEach((s) => {
      const value = d[s.key] || 0;
      if (!value) return;
      const segH = (value / max) * plotH;
      // 2px gap keeps adjacent fills from reading as one mark.
      cursor -= segH;
      const rect = svg('rect', {
        x, y: cursor, width: barW, height: Math.max(segH - 2, 1), rx: 4,
        fill: s.color, class: 'chart-bar',
      });
      rect.addEventListener('mouseenter', (e) => tooltip.show([
        el('strong', { text: d.label }),
        el('span', { text: `${s.label}: ${format(value)}` }),
      ], e.offsetX, e.offsetY));
      rect.addEventListener('mouseleave', () => tooltip.hide());
      root.append(rect);
    });

    root.append(svg('text', {
      x: x + barW / 2, y: height - pad.bottom + 15, fill: INK_MUTED,
      'font-size': 10, 'text-anchor': 'middle',
    }, document.createTextNode(d.label)));
  });

  return figure;
}

/* -- Line chart: change over time ----------------------------------------- */

export function lineChart({ title, series, labels, format = (v) => String(v), height = 230 }) {
  const usable = (series || []).filter((s) => s.values && s.values.length);
  if (usable.length === 0) return null;

  const width = 620;
  const pad = { top: 14, right: 16, bottom: 34, left: 52 };
  const plotW = width - pad.left - pad.right;
  const plotH = height - pad.top - pad.bottom;
  const max = niceMax(Math.max(...usable.flatMap((s) => s.values), 1));
  const count = Math.max(...usable.map((s) => s.values.length));
  const xAt = (i) => pad.left + (count === 1 ? plotW / 2 : (plotW * i) / (count - 1));
  const yAt = (v) => pad.top + plotH - (v / max) * plotH;

  const root = svg('svg', {
    class: 'chart', viewBox: `0 0 ${width} ${height}`,
    role: 'img', 'aria-label': title || 'Line chart',
  });

  for (let i = 0; i <= 4; i += 1) {
    const y = pad.top + (plotH * i) / 4;
    root.append(svg('line', { x1: pad.left, x2: width - pad.right, y1: y, y2: y, stroke: GRID, 'stroke-width': 1 }));
    root.append(svg('text', {
      x: pad.left - 8, y: y + 4, fill: INK_MUTED, 'font-size': 10, 'text-anchor': 'end',
    }, document.createTextNode(format(Math.round(max - (max * i) / 4)))));
  }

  usable.forEach((s, index) => {
    const color = s.color || CATEGORICAL[index % CATEGORICAL.length];
    const points = s.values.map((v, i) => `${xAt(i)},${yAt(v)}`).join(' ');
    root.append(svg('polyline', {
      points, fill: 'none', stroke: color, 'stroke-width': 2,
      'stroke-linejoin': 'round', 'stroke-linecap': 'round',
    }));
    // >=8px markers, with a surface ring so overlapping series stay readable.
    s.values.forEach((v, i) => {
      root.append(svg('circle', {
        cx: xAt(i), cy: yAt(v), r: 4, fill: color, stroke: SURFACE, 'stroke-width': 2,
      }));
    });
  });

  const figure = figureWrap(title, root, [
    usable.length > 1 ? legend(usable.map((s, i) => ({
      label: s.label, color: s.color || CATEGORICAL[i % CATEGORICAL.length],
    }))) : null,
    tableView(['Point', ...usable.map((s) => s.label)],
      Array.from({ length: count }, (_, i) => [
        (labels && labels[i]) || `#${i + 1}`,
        ...usable.map((s) => format(s.values[i] ?? 0)),
      ])),
  ].filter(Boolean));

  const tooltip = attachTooltip(figure);
  const overlay = svg('rect', {
    x: pad.left, y: pad.top, width: plotW, height: plotH, fill: 'transparent', class: 'chart-overlay',
  });
  overlay.addEventListener('mousemove', (event) => {
    const bounds = root.getBoundingClientRect();
    const ratio = (event.clientX - bounds.left) / bounds.width * width;
    const index = Math.max(0, Math.min(count - 1, Math.round(((ratio - pad.left) / plotW) * (count - 1))));
    tooltip.show([
      el('strong', { text: (labels && labels[index]) || `Point ${index + 1}` }),
      ...usable.map((s) => el('span', { text: `${s.label}: ${format(s.values[index] ?? 0)}` })),
    ], event.offsetX, event.offsetY);
  });
  overlay.addEventListener('mouseleave', () => tooltip.hide());
  root.append(overlay);

  return figure;
}
