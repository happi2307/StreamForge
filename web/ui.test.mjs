/**
 * Checks for the DOM helpers in ui.js, which every portal page builds on.
 *
 * A minimal DOM stub stands in for the browser rather than pulling in jsdom —
 * these helpers touch only a handful of DOM methods. Run with:
 *   node --test web/app.test.js web/ui.test.mjs
 */

import test from 'node:test';
import assert from 'node:assert';

import { el, clear, table, formatBytes, formatNumber, formatMoney, formatDate } from './ui.js';

/* -- Minimal DOM ---------------------------------------------------------- */

class StubNode {
  constructor(tag) {
    this.tagName = tag;
    this.children = [];
    this.attributes = {};
    this.listeners = {};
    this.className = '';
    this.hidden = false;
    this._text = null;
  }

  set textContent(value) {
    this._text = value;
    this.children = [];
  }

  get textContent() {
    if (this._text !== null) return this._text;
    return this.children.map((c) => c.textContent).join('');
  }

  append(...nodes) {
    for (const node of nodes) {
      this._text = null;
      this.children.push(node);
    }
  }

  replaceChildren(...nodes) {
    this.children = nodes;
    this._text = null;
  }

  setAttribute(key, value) {
    this.attributes[key] = String(value);
  }

  addEventListener(type, fn) {
    (this.listeners[type] ||= []).push(fn);
  }

  /** Depth-first search by tag, for assertions. */
  find(tag) {
    if (this.tagName === tag) return this;
    for (const child of this.children) {
      const hit = child.find?.(tag);
      if (hit) return hit;
    }
    return null;
  }

  findAll(tag, out = []) {
    if (this.tagName === tag) out.push(this);
    for (const child of this.children) child.findAll?.(tag, out);
    return out;
  }
}

class StubText extends StubNode {
  constructor(text) {
    super('#text');
    this._text = text;
  }
}

globalThis.Node = StubNode;
globalThis.document = {
  createElement: (tag) => new StubNode(tag),
  createTextNode: (text) => new StubText(text),
};

/* -- el() ----------------------------------------------------------------- */

test('el sets class, text and arbitrary attributes', () => {
  const node = el('div', { class: 'card', 'data-id': '7', title: 'hi' });

  assert.strictEqual(node.tagName, 'div');
  assert.strictEqual(node.className, 'card');
  assert.strictEqual(node.attributes['data-id'], '7');
  assert.strictEqual(node.attributes.title, 'hi');
});

test('el skips null, undefined and false attributes', () => {
  // Pages pass conditionals straight through, e.g. `align === 'right' ? ... : null`.
  const node = el('div', { class: null, title: undefined, hidden: false, 'data-x': 0 });

  assert.strictEqual(node.className, '');
  assert.ok(!('title' in node.attributes));
  assert.strictEqual(node.attributes['data-x'], '0', 'zero is a real value, not absent');
});

test('el wires event listeners from on* keys', () => {
  let clicked = 0;
  const node = el('button', { onclick: () => { clicked += 1; } });

  node.listeners.click[0]();
  assert.strictEqual(clicked, 1);
});

test('el accepts a single child, an array, and skips blanks', () => {
  const node = el('div', {}, [el('span', { text: 'a' }), null, false, 'plain']);

  assert.strictEqual(node.children.length, 2);
  assert.strictEqual(node.textContent, 'aplain');
});

test('clear empties a node', () => {
  const node = el('div', {}, ['one', 'two']);
  clear(node);
  assert.strictEqual(node.children.length, 0);
});

/* -- table() -------------------------------------------------------------- */

test('table renders a header and one row per record', () => {
  const node = table(
    [{ key: 'name', label: 'Name' }, { key: 'size', label: 'Size', align: 'right' }],
    [{ name: 'raw', size: 12 }, { name: 'clean', size: 34 }],
  );

  assert.strictEqual(node.findAll('th').length, 2);
  assert.strictEqual(node.findAll('tr').length, 3, 'one header row plus two body rows');
  assert.strictEqual(node.findAll('th')[1].className, 'align-right');
});

test('table applies a column formatter', () => {
  const node = table(
    [{ key: 'size', label: 'Size', format: (v) => `${v} B` }],
    [{ size: 5 }],
  );

  assert.strictEqual(node.findAll('td')[0].textContent, '5 B');
});

test('table falls back to an em dash for missing values', () => {
  const node = table([{ key: 'missing', label: 'M' }], [{}]);
  assert.strictEqual(node.findAll('td')[0].textContent, '—');
});

test('table renders an empty state instead of a bare header', () => {
  const node = table([{ key: 'a', label: 'A' }], []);

  assert.strictEqual(node.find('table'), null);
  assert.ok(node.className.includes('is-empty'));
});

/* -- formatters ----------------------------------------------------------- */

test('formatBytes picks sensible units', () => {
  assert.strictEqual(formatBytes(0), '0 B');
  assert.strictEqual(formatBytes(512), '512 B');
  assert.strictEqual(formatBytes(1024), '1.0 KB');
  assert.strictEqual(formatBytes(1536), '1.5 KB');
  assert.strictEqual(formatBytes(20 * 1024), '20 KB', 'no decimal once it reaches 10');
  assert.strictEqual(formatBytes(1024 ** 3), '1.0 GB');
});

test('formatters handle null without throwing', () => {
  assert.strictEqual(formatBytes(null), '—');
  assert.strictEqual(formatNumber(null), '—');
  assert.strictEqual(formatMoney(null), '—');
  assert.strictEqual(formatDate(null), '—');
  assert.strictEqual(formatDate('not-a-date'), '—');
});

test('formatMoney renders two decimal places', () => {
  assert.strictEqual(formatMoney(7), '$7.00');
  assert.strictEqual(formatMoney(0.004), '$0.00');
});
