/**
 * DOM helpers shared by the portal pages.
 *
 * Everything is built with createElement rather than innerHTML: the CloudFront
 * CSP is `default-src 'self'` with no unsafe-inline, so style attributes in
 * markup strings are blocked, and building nodes avoids injection entirely.
 */

/** el('div', { class: 'card' }, 'text' | node | [nodes]) */
export function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);

  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key === 'hidden') node.hidden = Boolean(value);
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }

  for (const child of [].concat(children)) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

export function clear(node) {
  node.replaceChildren();
  return node;
}

/** Page heading with an optional subtitle. */
export function pageHeader(title, subtitle) {
  return el('header', { class: 'page-header' }, [
    el('h2', { text: title }),
    subtitle ? el('p', { class: 'page-subtitle', text: subtitle }) : null,
  ]);
}

/** A single statistic tile. */
export function statCard(label, value, detail) {
  return el('article', { class: 'stat-card' }, [
    el('span', { class: 'stat-label', text: label }),
    el('strong', { class: 'stat-value', text: value ?? '—' }),
    detail ? el('span', { class: 'stat-detail', text: detail }) : null,
  ]);
}

export function cardGrid(cards) {
  return el('div', { class: 'card-grid' }, cards);
}

/** Bordered section wrapper used across pages. */
export function panel(title, children, actions) {
  return el('section', { class: 'panel' }, [
    el('div', { class: 'panel-head' }, [
      el('h3', { text: title }),
      actions ? el('div', { class: 'panel-actions' }, actions) : null,
    ]),
    el('div', { class: 'panel-body' }, children),
  ]);
}

/**
 * Loading / empty / error / signed-out placeholder.
 * kind: 'loading' | 'empty' | 'error' | 'signed-out' | 'not-deployed'
 */
export function stateBlock(kind, message, action) {
  const icons = {
    loading: '◌',
    empty: '∅',
    error: '!',
    'signed-out': '🔒',
    'not-deployed': '◻',
  };
  return el('div', { class: `state-block is-${kind}`, role: kind === 'error' ? 'alert' : null }, [
    el('span', { class: 'state-icon', 'aria-hidden': 'true', text: icons[kind] || '·' }),
    el('p', { class: 'state-message', text: message }),
    action || null,
  ]);
}

/**
 * columns: [{ key, label, align?, format?, wrap? }]
 * Cells are nowrap by default so numeric columns stay aligned; set `wrap` on
 * prose columns or long text is clipped at the table edge.
 */
export function table(columns, rows, emptyMessage = 'Nothing to show yet.') {
  if (!rows || rows.length === 0) return stateBlock('empty', emptyMessage);

  const cellClass = (c) => [c.align === 'right' ? 'align-right' : null, c.wrap ? 'wrap' : null]
    .filter(Boolean).join(' ') || null;

  const head = el('tr', {}, columns.map((c) =>
    el('th', { class: cellClass(c), text: c.label })));

  const body = rows.map((row) =>
    el('tr', {}, columns.map((c) => {
      const raw = row[c.key];
      return el('td', {
        class: cellClass(c),
        text: c.format ? c.format(raw, row) : (raw ?? '—'),
      });
    })));

  return el('div', { class: 'table-wrap' }, [
    el('table', { class: 'data-table' }, [
      el('thead', {}, head),
      el('tbody', {}, body),
    ]),
  ]);
}

/** Coloured status pill. tone: 'ok' | 'warn' | 'bad' | 'idle' */
export function badge(text, tone = 'idle') {
  return el('span', { class: `badge is-${tone}`, text });
}

export function formatBytes(bytes) {
  if (bytes === null || bytes === undefined) return '—';
  if (bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const power = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** power;
  return `${value >= 10 || power === 0 ? Math.round(value) : value.toFixed(1)} ${units[power]}`;
}

export function formatNumber(value) {
  if (value === null || value === undefined) return '—';
  return new Intl.NumberFormat().format(value);
}

export function formatDate(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

export function formatMoney(value) {
  if (value === null || value === undefined) return '—';
  return `$${Number(value).toFixed(2)}`;
}
